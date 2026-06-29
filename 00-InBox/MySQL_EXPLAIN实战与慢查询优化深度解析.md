# MySQL EXPLAIN 实战 + 慢查询优化深度解析

> **从 EXPLAIN 输出到慢查询治理的完整知识体系**
>
> 本文档基于 MySQL 8.0 源码（`sql_optimizer.cc` / `sql_executor.cc` / `opt_explain.cc` / `filesort.cc` 等），
> 系统解析 EXPLAIN 12 列含义、访问类型 8 级、Extra 15 种状态、成本模型、ORDER BY / GROUP BY / LIMIT / JOIN 优化原理，
> 以及 15 个真实慢查询案例的完整优化过程。

---

## 目录

```
第一部分  EXPLAIN 基础 — 12 列逐列详解
第二部分  访问类型（type 列）8 级全解析
第三部分  Extra 列 15 种状态详解
第四部分  EXPLAIN FORMAT=JSON — 成本模型详解
第五部分  ANALYZE 语句（MySQL 8.0）
第六部分  慢查询日志配置与分析
第七部分  ORDER BY 优化
第八部分  GROUP BY 优化
第九部分  LIMIT 深分页优化
第十部分  JOIN 优化
第十一部分  子查询优化
第十二部分  15 个真实慢查询案例
第十三部分  优化器 Trace 分析
附录
```

---

## 第一部分 EXPLAIN 基础 — 12 列逐列详解

### 1.1 EXPLAIN 命令概述与语法

#### 1.1.1 EXPLAIN 是什么

EXPLAIN 是 MySQL 提供的**查询执行计划分析工具**。它不会真正执行 SQL（EXPLAIN ANALYZE 除外），而是让优化器生成一份执行计划，告诉你：

- 这条 SQL 会用哪个索引
- 预估扫描多少行
- 有没有临时表、文件排序
- JOIN 的驱动表是哪个
- 估算成本是多少

```
┌─────────────────────────────────────────────────────────────────┐
│                      EXPLAIN 工作原理                            │
│                                                                 │
│  SQL 语句                                                       │
│    │                                                            │
│    ▼                                                            │
│  ┌──────────────┐                                               │
│  │  词法/语法分析  │  Parser（sql_yacc.yy）                      │
│  │  生成 AST      │  → SELECT_LEX / SELECT_LEX_UNIT              │
│  └──────┬───────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │  预处理        │  resolve_column / resolve_table              │
│  │  语义检查      │  名称解析、权限检查                            │
│  └──────┬───────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │  逻辑优化      │  sql_optimizer.cc                            │
│  │               │  - 子查询改写                                 │
│  │               │  - 常量传播                                   │
│  │               │  - 等价谓词重写                               │
│  │               │  - 外连接消除                                 │
│  │               │  - 视图合并                                   │
│  │               │  - ORDER BY 消除                              │
│  └──────┬───────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │  物理优化      │  sql_optimizer.cc                            │
│  │               │  - 成本估算                                   │
│  │               │  - 索引选择                                   │
│  │               │  - JOIN 顺序                                  │
│  │               │  - 访问路径选择                               │
│  └──────┬───────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │  生成执行计划   │  JOIN_TAB / QEP_TAB                         │
│  │  QEP_TAB       │  Query Execution Plan Table                 │
│  └──────┬───────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │  EXPLAIN      │  opt_explain.cc                              │
│  │  格式化输出    │  Explain_format tradicional / JSON / TREE    │
│  └──────────────┘                                               │
│                                                                 │
│  ※ EXPLAIN 不执行 SQL，只展示优化器选定的执行计划                  │
│  ※ EXPLAIN ANALYZE（8.0.18+）会真正执行 SQL 并输出实际耗时         │
└─────────────────────────────────────────────────────────────────┘
```

#### 1.1.2 EXPLAIN 语法

```sql
-- 传统格式（默认）
EXPLAIN SELECT * FROM users WHERE age > 25;

-- JSON 格式（最详细，包含成本信息）
EXPLAIN FORMAT=JSON SELECT * FROM users WHERE age > 25;

-- TREE 格式（8.0.16+，树形展示，更直观）
EXPLAIN FORMAT=TREE SELECT * FROM users WHERE age > 25;

-- ANALYZE 格式（8.0.18+，真正执行并输出实际耗时）
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

-- 针对指定连接
EXPLAIN FOR CONNECTION <connection_id>;
```

#### 1.1.3 EXPLAIN 输出示例

```sql
CREATE TABLE users (
    id          BIGINT PRIMARY KEY AUTO_INCREMENT,
    name        VARCHAR(50) NOT NULL,
    age         INT NOT NULL,
    city        VARCHAR(50) NOT NULL,
    email       VARCHAR(100),
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_age_city (age, city),
    INDEX idx_email (email),
    INDEX idx_name (name)
) ENGINE=InnoDB;

EXPLAIN SELECT * FROM users WHERE age = 25 AND city = '杭州';

-- +----+-------------+-------+------------+------+----------------+----------------+---------+-------------+------+----------+-------+
-- | id | select_type | table | partitions | type | possible_keys  | key            | key_len | ref         | rows | filtered | Extra |
-- +----+-------------+-------+------------+------+----------------+----------------+---------+-------------+------+----------+-------+
-- |  1 | SIMPLE      | users | NULL       | ref  | idx_age_city   | idx_age_city   | 158     | const,const |    1 |   100.00 | NULL  |
-- +----+-------------+-------+------------+------+----------------+----------------+---------+-------------+------+----------+-------+
```

#### 1.1.4 12 列总览与性能关注优先级

```
性能关注优先级：
  type > key > rows > Extra > key_len > possible_keys > ref > filtered

┌────────────────┬──────────────────────────────────────────────────────┐
│     列名       │                    含义                              │
├────────────────┼──────────────────────────────────────────────────────┤
│ id             │ 查询标识符，标识 SELECT 的序号                       │
│ select_type    │ 查询类型（SIMPLE / PRIMARY / SUBQUERY / ...）        │
│ table          │ 表名（或别名、派生表名）                              │
│ partitions     │ 匹配的分区                                           │
│ type           │ 访问类型（性能关键指标，system → ALL）               │
│ possible_keys  │ 可能使用的索引                                       │
│ key            │ 实际使用的索引                                       │
│ key_len        │ 使用的索引长度（字节）                                │
│ ref            │ 索引比较的来源（const / 列名 / func）                │
│ rows           │ 预估扫描行数                                         │
│ filtered       │ 过滤后剩余百分比（5.7+）                             │
│ Extra          │ 额外信息（Using index / Using temporary / ...）     │
└────────────────┴──────────────────────────────────────────────────────┘
```

---

### 1.2 id 列 — 查询标识符

| id 模式 | 含义 |
|---------|------|
| id 相同 | 同一组 SELECT，从上往下顺序执行 |
| id 不同 | id 越大越先执行（子查询先于外层） |
| id 为 NULL | UNION 合并的临时表（`<union1,2>`） |

```sql
-- 1. id 相同（JOIN）
EXPLAIN SELECT * FROM users u JOIN orders o ON u.id = o.user_id;
-- u.id = 1, o.id = 1 （同一组，从上往下执行）

-- 2. id 不同（子查询，子查询先执行）
EXPLAIN SELECT * FROM users WHERE id IN (SELECT user_id FROM orders);
-- orders 子查询 id = 2 （先执行）
-- users 外查询   id = 1 （后执行）

-- 3. id 为 NULL（UNION）
EXPLAIN SELECT id FROM users WHERE age = 25
UNION
SELECT id FROM users WHERE age = 30;
-- users 第一行 id = 1
-- users 第二行 id = 2
-- <union1,2>   id = NULL （UNION 合并去重的临时表）
```

> **执行顺序判断规则**：id 越大越先执行；id 相同时从上往下执行；id 为 NULL 最后执行。MySQL 8.0 优化器可能将子查询改写为半连接，此时 id 可能全部相同。

---

### 1.3 select_type 列 — 查询类型

| select_type | 含义 | 性能影响 |
|-------------|------|---------|
| SIMPLE | 简单查询（无子查询/UNION） | 好 |
| PRIMARY | 最外层查询 | 正常 |
| SUBQUERY | 子查询中的第一个 SELECT | 看优化器策略 |
| DERIVED | 派生表（FROM 子句中的子查询） | 可能产生临时表 |
| UNION | UNION 中的第二个及以后 SELECT | 正常 |
| UNION RESULT | UNION 结果集 | 需去重 |
| DEPENDENT SUBQUERY | 依赖外层的子查询 | **差**（每行重复执行） |
| DEPENDENT UNION | 依赖外层的 UNION | **差** |
| MATERIALIZED | 物化子查询 | 较好（只执行一次） |
| UNCACHEABLE SUBQUERY | 不可缓存的子查询 | **差** |

```sql
-- DEPENDENT SUBQUERY（性能杀手）
EXPLAIN SELECT * FROM users u WHERE EXISTS (
    SELECT 1 FROM orders o WHERE o.user_id = u.id
);
-- users:  select_type = PRIMARY
-- orders: select_type = DEPENDENT SUBQUERY（依赖外层 u.id，每行重复执行）

-- MATERIALIZED（优化器对子查询的优化）
EXPLAIN SELECT * FROM users WHERE id IN (SELECT user_id FROM orders);
-- orders: select_type = MATERIALIZED（子查询只执行一次，结果物化为临时表）
```

> **关键区别**：`DEPENDENT SUBQUERY` 是性能杀手——子查询对外层每一行重复执行。`MATERIALIZED` 是优化——子查询只执行一次，结果物化为临时表。

---

### 1.4 table 列 — 表名与别名

```sql
-- table = users          → 普通表
-- table = u              → 别名
-- table = <derived2>     → 派生表（数字是对应子查询的 id）
-- table = <union1,2>     → UNION 合并结果（id=1 和 id=2）
```

---

### 1.5 partitions 列 — 分区信息

```sql
-- 非分区表显示 NULL
EXPLAIN SELECT * FROM users WHERE age = 25;
-- partitions = NULL

-- 分区裁剪：只扫描匹配的分区
EXPLAIN SELECT * FROM orders WHERE created_at BETWEEN '2025-02-01' AND '2025-02-28';
-- partitions = p202502 （只扫描2月分区）

-- 无分区裁剪：扫描所有分区
EXPLAIN SELECT * FROM orders WHERE amount > 100;
-- partitions = p202501,p202502,p202503,pmax （全部分区）
```

> **优化要点**：如果 partitions 列显示了所有分区名，说明分区裁剪（Partition Pruning）未生效。确保 WHERE 条件包含分区键。

---

### 1.6 type 列 — 访问类型总览

`type` 列是 EXPLAIN 中**最重要的性能指标**：

```
性能从好到差：

  system  >  const  >  eq_ref  >  ref  >  range  >  index  >  ALL
    │         │         │         │        │         │         │
    │         │         │         │        │         │         └─ 全表扫描（
    │         │         │         │        │         └─ 全索引扫描
    │         │         │         │        └─ 索引范围扫描
    │         │         │         └─ 非唯一索引等值
    │         │         └─ JOIN 唯一索引等值（最优 JOIN）
    │         └─ 主键/唯一索引等值
    └─ 系统表单行

  额外类型：
  - index_merge：索引合并
  - fulltext：全文索引
  - ref_or_null：ref + NULL 查询
  - unique_subquery：IN 子查询优化为主键等值
  - index_subquery：IN 子查询优化为索引等值
```

> **黄金法则**：生产环境至少达到 `range` 级别，最好达到 `ref` 级别。`index` 和 `ALL` 在大表上必须避免。详细解析见第二部分。

---

### 1.7 possible_keys 列 — 可能使用的索引

```sql
-- 可能使用多个索引，但优化器只选一个
EXPLAIN SELECT * FROM users WHERE age = 25 OR email = 'test@test.com';
-- possible_keys = idx_age_city,idx_email

-- possible_keys 为 NULL：没有可用索引
EXPLAIN SELECT * FROM users WHERE created_at > '2025-01-01';
-- possible_keys = NULL → type = ALL

-- 有 possible_keys 但 key 为 NULL：优化器认为全表扫描成本更低
EXPLAIN SELECT * FROM users WHERE age > 0;
-- possible_keys = idx_age_city, key = NULL, type = ALL
```

---

### 1.8 key 列 — 实际使用的索引

```sql
-- 使用了 idx_age_city
EXPLAIN SELECT * FROM users WHERE age = 25 AND city = '杭州';
-- key = idx_age_city

-- 索引合并
EXPLAIN SELECT * FROM users WHERE age = 25 OR email = 'test@test.com';
-- key = idx_age_city,idx_email （index_merge）
-- type = index_merge
```

> **注意**：`key` 列显示的索引名可能和 `possible_keys` 不同——优化器可能选择了非预期索引。这时需要用 `FORCE INDEX` 或 `optimizer_trace` 分析。

---

### 1.9 key_len 列 — 索引使用长度

`key_len` 表示**实际使用的索引字段的字节长度**，是判断**复合索引用了几个列**的关键指标。

#### 1.9.1 key_len 计算规则

```
┌──────────────┬──────────────────────────────────────────────────────┐
│ 数据类型     │ key_len                                              │
├──────────────┼──────────────────────────────────────────────────────┤
│ TINYINT      │ 1                                                    │
│ SMALLINT     │ 2                                                    │
│ INT          │ 4                                                    │
│ BIGINT       │ 8                                                    │
│ DATE         │ 3                                                    │
│ DATETIME     │ 5（MySQL 5.6.4+）                                    │
│ TIMESTAMP    │ 4                                                    │
│ CHAR(n)      │ n × 字符字节数（utf8mb4: 4）                         │
│ VARCHAR(n)   │ n × 字符字节数 + 2（变长标识）                       │
└──────────────┴──────────────────────────────────────────────────────┘

额外规则：
  - 允许 NULL：额外 + 1 字节
  - 字符集 utf8mb4：每个字符 4 字节
```

#### 1.9.2 key_len 实战计算

```sql
CREATE TABLE example (
    id      BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,   -- BIGINT: 8
    a_int   INT NOT NULL,                                 -- INT NOT NULL: 4
    b_int   INT,                                          -- INT NULL: 4 + 1 = 5
    c_var   VARCHAR(50) NOT NULL,                         -- 50 × 4 + 2 = 202
    d_var   VARCHAR(50),                                  -- 50 × 4 + 2 + 1 = 203
    e_char  CHAR(10) NOT NULL,                            -- 10 × 4 = 40
    f_date  DATE NOT NULL,                                -- DATE: 3
    INDEX idx_compound (a_int, b_int, c_var, d_var, e_char, f_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 1. 只用第一列
EXPLAIN SELECT * FROM example WHERE a_int = 1;
-- key_len = 4

-- 2. 用前两列
EXPLAIN SELECT * FROM example WHERE a_int = 1 AND b_int = 2;
-- key_len = 4 + 5 = 9

-- 3. 用前三列
EXPLAIN SELECT * FROM example WHERE a_int = 1 AND b_int = 2 AND c_var = 'test';
-- key_len = 4 + 5 + 202 = 211

-- 4. 范围查询截断后续列
EXPLAIN SELECT * FROM example WHERE a_int = 1 AND b_int > 2 AND c_var = 'test';
-- key_len = 9 （只用 a_int + b_int，c_var 因 b_int 范围查询无法用于索引查找）
-- 注意：ICP 可以在引擎层用 c_var 过滤，但 key_len 不体现
```

> **核心用途**：通过 `key_len` 判断复合索引用了几列。如果 key_len 不符合预期，说明某些列因**最左前缀**或**范围查询截断**而未被使用。

---

### 1.10 ref 列 — 索引比较来源

| ref 值 | 含义 |
|--------|------|
| const | 与常量比较 |
| `db.table.column` | 与另一个表的列比较（JOIN） |
| func | 与函数结果比较 |
| NULL | 没有使用索引或索引合并 |

```sql
-- const：与常量比较
EXPLAIN SELECT * FROM users WHERE age = 25 AND city = '杭州';
-- ref = const,const

-- 列名：JOIN
EXPLAIN SELECT * FROM users u JOIN orders o ON u.id = o.user_id;
-- orders: ref = test_db.u.id

-- func
EXPLAIN SELECT * FROM users WHERE id = ABS(-1);
-- ref = func
```

---

### 1.11 rows 列 — 预估扫描行数

`rows` 是优化器**预估的需要扫描的行数**，不是实际行数：

```sql
-- 预估扫描 1 行（主键等值）
EXPLAIN SELECT * FROM users WHERE id = 1;
-- rows = 1

-- 预估扫描 5000 行（范围查询）
EXPLAIN SELECT * FROM users WHERE age > 25;
-- rows = 5000

-- 全表扫描
EXPLAIN SELECT * FROM users;
-- rows = 1000000
```

#### 估算原理

```
1. 等值查询（ref 访问）：rows = 表总行数 / 索引基数（Cardinality）
2. 范围查询（range 访问）：rows = 命中区间的行数之和（B+Tree 叶子页采样估算）
3. 全表扫描（ALL）：rows = 表统计信息中的总行数

统计信息来源：InnoDB dict_table_t → stats->records
更新统计信息：ANALYZE TABLE users;
```

> **注意**：`rows` 是预估值，可能严重偏离实际值。MySQL 8.0 的 `EXPLAIN ANALYZE` 提供 `r_rows`（实际行数）用于对比。

---

### 1.12 filtered 列 — 过滤百分比

`filtered` 表示**经过 WHERE 条件过滤后，剩余行占 rows 的百分比**：

```sql
-- rows = 1000, filtered = 10 → 实际返回 100 行
EXPLAIN SELECT * FROM users WHERE age > 25 AND city = '杭州';
-- rows = 1000, filtered = 10.00
```

#### filtered 在 JOIN 中的意义

```
JOIN 执行：驱动表 → 被驱动表
驱动表：rows × filtered% = 传给被驱动表的行数

示例：
  users（驱动表）：rows=10000, filtered=10.00
  → 传给 orders 的行数 = 10000 × 10% = 1000 行
  → orders 每行做一次索引查找 → 1000 次索引查找

如果 filtered 估算准确，优化器能选对驱动表
如果 filtered 偏差大，可能导致 JOIN 顺序错误
```

---

### 1.13 Extra 列 — 额外信息总览

| Extra 值                       | 性能影响 | 说明          |
| ----------------------------- | ---- | ----------- |
| Using index                   | 好    | 覆盖索引，无需回表   |
| Using index condition         | 较好   | ICP 索引下推    |
| Using where                   | 一般   | 服务层过滤       |
| Using temporary               | 差    | 临时表         |
| Using filesort                | 差    | 文件排序        |
| Using join buffer             | 差    | BNL/BKA     |
| Using MRR                     | 较好   | 多范围读优化      |
| Distinct                      | 好    | DISTINCT 优化 |
| Select tables optimized away  | 好    | 优化器已算出结果    |
| Impossible WHERE              | 好    | WHERE 条件恒假  |
| Range checked for each record | 差    | 每行重新评估索引    |
| FirstMatch                    | 好    | 半连接优化       |

详细解析见第三部分。

---

## 第二部分 访问类型（type 列）8 级全解析

### 2.1 system — 系统表单行

```sql
-- 只有一行的系统表（MyISAM/Memory）
EXPLAIN SELECT * FROM mysql.proxies_priv;
-- type = system
-- InnoDB 表不会出现 system，最差也是 const
```

### 2.2 const — 主键/唯一索引等值查询

```sql
-- 主键等值
EXPLAIN SELECT * FROM users WHERE id = 1;
-- type = const

-- 唯一索引等值
EXPLAIN SELECT * FROM users WHERE email = 'test@test.com';
-- type = const（email 上有 UNIQUE 索引）
```

**底层原理**：优化器在优化阶段就能确定最多匹配一行 → B+Tree 一次索引查找即可定位 → 读取行数据后将值视为常量。源码：`sql_optimizer.cc → make_join_readinfo()` 设置 `JT_CONST`。

### 2.3 eq_ref — JOIN 主键/唯一索引等值

```sql
-- JOIN 时被驱动表使用主键或唯一索引等值
EXPLAIN SELECT * FROM users u JOIN orders o ON u.id = o.user_id;
-- users: type = ALL（驱动表）
-- orders: type = eq_ref（o.user_id 是主键，与 u.id 等值连接）
```

**eq_ref vs ref**：

```
┌──────────────┬────────────────────────┬──────────────────────────┐
│              │  eq_ref                 │  ref                     │
├──────────────┼────────────────────────┼──────────────────────────┤
│ 索引类型     │  主键 / 唯一索引        │  普通索引                 │
│ 匹配行数     │  最多 1 行              │  0 ~ N 行                │
│ 使用场景     │  JOIN 被驱动表          │  单表 / JOIN             │
│ 性能         │  最优 JOIN              │  较好                    │
└──────────────┴────────────────────────┴──────────────────────────┘
```

### 2.4 ref — 非唯一索引等值

```sql
-- 普通索引等值
EXPLAIN SELECT * FROM users WHERE age = 25;
-- type = ref（idx_age_city 的前导列 age 等值匹配）

-- 复合索引多列等值
EXPLAIN SELECT * FROM users WHERE age = 25 AND city = '杭州';
-- type = ref（idx_age_city 两列等值匹配）
-- ref = const,const

-- JOIN 使用普通索引
EXPLAIN SELECT * FROM users u JOIN orders o ON u.id = o.user_id
WHERE o.amount > 100;
-- 如果 user_id 上只有普通索引（非 UNIQUE）
-- orders: type = ref
```

### 2.5 range — 索引范围扫描

```sql
-- 各种范围查询
EXPLAIN SELECT * FROM users WHERE id BETWEEN 1 AND 100;
-- type = range

EXPLAIN SELECT * FROM users WHERE age IN (25, 30, 35);
-- type = range

EXPLAIN SELECT * FROM users WHERE age > 25 AND age < 40;
-- type = range

-- LIKE 前缀匹配也是 range
EXPLAIN SELECT * FROM users WHERE name LIKE '张%';
-- type = range（name 上有索引）

-- != 和 NOT IN 不是 range
EXPLAIN SELECT * FROM users WHERE age != 25;
-- type = ALL（!= 无法利用索引范围扫描）
```

#### range 访问的索引扫描过程

```
B+Tree 范围扫描：
  1. 从根节点向下查找 age=25 的叶子节点
  2. 沿叶子节点链表向右扫描
  3. 直到 age > 40 时停止

  根节点(非叶子)
   /    |    \
  ...   25    40   60  ...
         │     │
  叶子: [25]→[28]→[30]→[33]→[35]→[38]→[40]→...
         ↑                      ↑
         开始                    结束

  源码：ha_innobase::index_read() → btr_cur_search_to_nth_level()
  → 沿 rec_get_next() 链表扫描
```

### 2.6 index — 全索引扫描

```sql
-- 全索引扫描：扫描整个索引，不回表
EXPLAIN SELECT COUNT(*) FROM users;
-- type = index, key = PRIMARY（扫描主键索引统计行数）

-- 覆盖索引全扫描
EXPLAIN SELECT age, city FROM users;
-- type = index, key = idx_age_city（需要 age, city 列，索引覆盖）

-- ORDER BY 使用索引
EXPLAIN SELECT * FROM users ORDER BY name;
-- type = index, key = idx_name（按索引顺序扫描，避免 filesort）
```

**index vs ALL**：

```
┌──────────────┬──────────────────────────┬──────────────────────────┐
│              │  index                    │  ALL                     │
├──────────────┼──────────────────────────┼──────────────────────────┤
│ 扫描对象     │  索引（B+Tree 全部叶子页）│  数据页（全部聚簇索引页） │
│ I/O          │  索引页（通常较小）       │  数据页（通常较大）       │
│ 回表         │  不需要（覆盖索引时）     │  不需要（直接读数据页）   │
│ 性能         │  比 ALL 好               │  最差                    │
│ 适用场景     │  COUNT / 覆盖索引 / ORDER │  无可用索引时             │
└──────────────┴──────────────────────────┴──────────────────────────┘
```

### 2.7 ALL — 全表扫描

```sql
-- 无索引可用
EXPLAIN SELECT * FROM users WHERE created_at > '2025-01-01';
-- type = ALL（created_at 无索引）

-- 有索引但优化器选择全表扫描
EXPLAIN SELECT * FROM users WHERE age > 0;
-- type = ALL（条件选择率太低，全表扫描成本更低）
```

**ALL 的代价**：全表扫描 = 从第一个数据页到最后一个数据页，逐页读取。100 万行 ≈ 10000 页 ≈ 160MB。如果数据不在 Buffer Pool → 大量磁盘 I/O。

### 2.8 index_merge — 索引合并

```sql
-- OR 条件使用不同索引
EXPLAIN SELECT * FROM users WHERE age = 25 OR email = 'test@test.com';
-- type = index_merge
-- key = idx_age_city,idx_email
-- Extra = Using union(idx_age_city,idx_email); Using where
```

#### 索引合并三种方式

```
1. Using union(...)：并集
   age = 25 OR email = 'x'
   → 分别用 idx_age_city 和 idx_email 查找 → 合并结果去重

2. Using intersect(...)：交集
   age = 25 AND name = '张三'
   → 分别用 idx_age_city 和 idx_name 查找 → 取主键 ID 交集

3. Using sort_union(...)：排序并集
   age > 25 OR email LIKE 'test%'
   → 分别范围扫描 → 按主键排序后合并去重

注意：index_merge 通常不如复合索引高效 → 优先考虑建复合索引
```

### 2.9 访问类型性能对比矩阵

```
┌────────────────┬───────────┬───────────────┬──────────────────────┐
│ 访问类型       │  I/O 代价  │  CPU 代价     │  典型场景             │
├────────────────┼───────────┼───────────────┼──────────────────────┤
│ system         │  极低      │  极低          │  系统表单行           │
│ const          │  极低      │  极低          │  主键等值             │
│ eq_ref         │  低        │  低            │  JOIN 唯一索引        │
│ ref            │  低~中     │  低            │  普通索引等值         │
│ range          │  中        │  低~中         │  范围查询             │
│ index_merge    │  中~高     │  中            │  多索引合并           │
│ index          │  中~高     │  低~中         │  全索引扫描           │
│ ALL            │  高        │  中            │  全表扫描             │
└────────────────┴───────────┴───────────────┴──────────────────────┘

  优化目标：至少达到 range，最好达到 ref，绝对避免 ALL 在大表上
```

---

## 第三部分 Extra 列 15 种状态详解

### 3.1 Using index — 覆盖索引

```sql
-- 索引覆盖所有查询列，无需回表
EXPLAIN SELECT age, city FROM users WHERE age = 25;
-- Extra = Using index（idx_age_city 覆盖了 age, city）

EXPLAIN SELECT id, age FROM users WHERE age = 25;
-- Extra = Using index（id 是主键，自动包含在二级索引中）

-- 反例：SELECT * 需要回表
EXPLAIN SELECT * FROM users WHERE age = 25;
-- Extra = NULL（需要回表取所有列）
```

**Using index 的底层原理**：

```
二级索引叶子节点存储：(索引列值, 主键值)

  idx_age_city 叶子节点：
  ┌──────────┬─────────┬────────┐
  │ age=25   │ city=杭州│ id=100 │  ← 这个叶子节点已包含 age, city, id
  ├──────────┼─────────┼────────┤
  │ age=25   │ city=北京│ id=200 │
  └──────────┴─────────┴────────┘

  SELECT age, city → 索引叶子节点已包含 → 不需要回表 → Using index
  SELECT *         → 索引叶子节点没有 name, email, created_at → 需要回表
```

> **优化建议**：将 `SELECT *` 改为只查需要的列，可能触发覆盖索引，消除回表。

### 3.2 Using where — 服务层过滤

```sql
-- 索引只用了部分列，WHERE 还有额外条件在服务层过滤
EXPLAIN SELECT * FROM users WHERE age = 25 AND name LIKE '%三';
-- Extra = Using where（age 用了索引，name LIKE 在服务层过滤）
```

**Using where 的含义**：MySQL 服务层（Server Layer）在从存储引擎获取行后，还需要用 WHERE 条件的剩余部分过滤。

### 3.3 Using index condition — 索引下推（ICP）

```sql
-- ICP：将 WHERE 条件下推到存储引擎层执行
EXPLAIN SELECT * FROM users WHERE age = 25 AND city LIKE '杭%';
-- type = ref, key = idx_age_city
-- Extra = Using index condition（city LIKE '杭%' 下推到引擎层）
```

**ICP 原理图解**：

```
没有 ICP（MySQL 5.6 之前）：
  存储引擎层                服务层
  ┌──────────┐            ┌──────────────┐
  │ idx_age   │            │ WHERE city    │
  │ age=25    │──1000行──→│ LIKE '杭%'    │──100行──→ 结果
  │           │            │ 逐行回表过滤  │
  └──────────┘            └──────────────┘
  回表 1000 次

有 ICP（MySQL 5.6+）：
  存储引擎层                服务层
  ┌──────────────────┐    ┌──────────┐
  │ idx_age_city      │    │          │
  │ age=25            │    │          │
  │ + city LIKE '杭%' │─100行─→│ 直接返回 │──100行──→ 结果
  │ （在索引层过滤）   │    │          │
  └──────────────────┘    └──────────┘
  回表 100 次

  源码：ha_innobase::index_read() → innobase_index_cond()
  → Item_cond::eval() 在索引层评估条件
```

### 3.4 Using temporary — 临时表

```sql
-- GROUP BY 产生临时表
EXPLAIN SELECT city, COUNT(*) FROM users GROUP BY city;
-- Extra = Using temporary

-- DISTINCT 产生临时表
EXPLAIN SELECT DISTINCT city FROM users;
-- Extra = Using temporary

-- UNION 产生临时表
EXPLAIN SELECT city FROM users UNION SELECT city FROM orders;
-- Extra = Using temporary（UNION 去重需要临时表）
```

**临时表类型**：

```
1. MEMORY 引擎（内存临时表）— 默认，大小受 tmp_table_size 限制
2. TempTable 引擎（MySQL 8.0）— 优化内存管理
3. InnoDB 引擎（磁盘临时表）— 超过内存限制时转换

内存 → 磁盘转换条件：
  - 表大小 > tmp_table_size（默认 16MB）
  - 表大小 > max_heap_table_size
  - 包含 BLOB/TEXT 列
  - GROUP BY/DISTINCT 列超过 512 字节
```

### 3.5 Using filesort — 文件排序

```sql
-- ORDER BY 无法使用索引
EXPLAIN SELECT * FROM users ORDER BY created_at;
-- Extra = Using filesort（created_at 无索引）

-- ORDER BY 混合排序方向
EXPLAIN SELECT * FROM users WHERE age > 25 ORDER BY age DESC, city ASC;
-- Extra = Using filesort（DESC + ASC 混合方向）

-- ORDER BY 列不在索引中
EXPLAIN SELECT * FROM users WHERE age = 25 ORDER BY name;
-- Extra = Using filesort（name 不在 idx_age_city 中）
```

> **注意**：`Using filesort` 不一定真的使用磁盘文件。如果数据量小于 `sort_buffer_size`，排序在内存中完成。详细解析见第七部分。

### 3.6 Using join buffer — BNL/BKA

```sql
-- 被驱动表无索引，使用 BNL
EXPLAIN SELECT * FROM users u JOIN orders o ON u.name = o.remark;
-- Extra = Using join buffer (Block Nested Loop)

-- MySQL 8.0.18+ 可能使用 Hash Join
-- Extra = Using join buffer (hash join)
```

详细解析见第十部分。

### 3.7 Distinct — 优化 DISTINCT

```sql
EXPLAIN SELECT DISTINCT o.user_id FROM orders o JOIN users u ON o.user_id = u.id;
-- Extra = Distinct（找到 u.id 的第一行匹配就停止扫描 o 的重复行）
```

### 3.8 Range checked for each record

```sql
-- 每行重新评估使用哪个索引（性能很差）
EXPLAIN SELECT * FROM t1 JOIN t2 ON t1.col1 = t2.col2 OR t1.col3 = t2.col4;
-- Extra = Range checked for each record (index map: 0x...)
```

### 3.9 Using MRR — 多范围读

```sql
SET optimizer_switch='mrr=on,mrr_cost_based=off';
EXPLAIN SELECT * FROM users WHERE age BETWEEN 25 AND 35;
-- Extra = Using index condition; Using MRR
```

**MRR 原理**：范围扫描得到的主键是无序的。直接回表会产生大量随机 I/O。MRR 先将主键排序，再回表，将随机 I/O 转为顺序 I/O。

### 3.10 FirstMatch — 半连接优化

```sql
EXPLAIN SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
-- Extra = FirstMatch(users)（找到第一个匹配就跳过后续）
```

### 3.11 Select tables optimized away

```sql
EXPLAIN SELECT MIN(id), MAX(id) FROM users;
-- Extra = Select tables optimized away（B+Tree 最左/最右叶子直接取值）
```

### 3.12 Impossible WHERE

```sql
EXPLAIN SELECT * FROM users WHERE 1 = 0;
-- Extra = Impossible WHERE
```

### 3.13 No tables used

```sql
EXPLAIN SELECT 1;
-- Extra = No tables used
```

### 3.14 Full scan on NULL key

```sql
-- 子查询中 NULL 值导致全表扫描
EXPLAIN SELECT * FROM users WHERE NOT EXISTS (
    SELECT 1 FROM orders WHERE user_id = users.id
);
-- Extra = Full scan on NULL key
```

### 3.15 Extra 状态性能影响总结

```
┌─────────────────────────────────┬──────────────────────────────┐
│  Extra 状态                     │  性能影响                     │
├─────────────────────────────────┼──────────────────────────────┤
│  Using index                    │  好（覆盖索引）               │
│  Using index condition          │  较好（ICP）                  │
│  Using MRR                      │  较好（顺序回表）             │
│  Distinct                       │  好（优化 DISTINCT）          │
│  FirstMatch                     │  好（半连接优化）             │
│  Select tables optimized away   │  好（优化器已算出）           │
│  Impossible WHERE               │  好（直接返回空）             │
│  Using where                    │  一般（服务层过滤）           │
│  Using join buffer              │  差（BNL/Hash Join）          │
│  Using temporary                │  差（临时表）                 │
│  Using filesort                 │  差（文件排序）               │
│  Range checked for each record  │  差（逐行选索引）             │
│  Full scan on NULL key          │  差（NULL 全表扫描）          │
└─────────────────────────────────┴──────────────────────────────┘

  看到以下状态必须优化：
  1. Using temporary → 消除临时表（改 GROUP BY 为索引扫描）
  2. Using filesort  → 消除排序（ORDER BY 使用索引）
  3. Using join buffer → 给被驱动表加索引
  4. ALL → 给 WHERE 条件加索引
```

---

## 第四部分 EXPLAIN FORMAT=JSON — 成本模型详解

### 4.1 JSON 格式概述

```sql
EXPLAIN FORMAT=JSON
SELECT * FROM users WHERE age = 25 AND city = '杭州';
```

```json
{
  "query_block": {
    "select_id": 1,
    "cost_info": { "query_cost": "1.20" },
    "table": {
      "table_name": "users",
      "access_type": "ref",
      "possible_keys": ["idx_age_city"],
      "key": "idx_age_city",
      "used_key_parts": ["age", "city"],
      "key_length": "158",
      "ref": ["const", "const"],
      "rows_examined_per_scan": 1,
      "rows_produced_per_join": 1,
      "filtered": "100.00",
      "cost_info": {
        "read_cost": "1.00",
        "eval_cost": "0.20",
        "prefix_cost": "1.20",
        "data_read_per_join": "400"
      },
      "used_columns": ["id", "name", "age", "city", "email", "created_at"]
    }
  }
}
```

### 4.2 成本模型字段解析

```
┌─────────────────┬───────────────────────────────────────────────┐
│ 字段            │ 含义                                          │
├─────────────────┼───────────────────────────────────────────────┤
│ query_cost      │ 整个查询的总成本                              │
│ read_cost       │ 读取数据的成本（I/O + 引擎层成本）             │
│ eval_cost       │ 评估WHERE条件的成本（CPU）                    │
│ prefix_cost     │ 当前表及之前所有表的累积成本                   │
│ data_read_per_join│ 每次JOIN读取的数据量（字节）                 │
│ used_key_parts  │ 实际使用的索引列                             │
│ used_columns    │ 查询涉及的所有列                             │
│ attached_condition│ 附加到存储引擎的条件（ICP 条件）             │
└─────────────────┴───────────────────────────────────────────────┘
```

### 4.3 成本计算公式

```
总成本 = IO 成本 + CPU 成本

IO 成本：
  - 全表扫描：表页数 × page_io_cost
  - 索引扫描：索引页数 × page_io_cost
  - 回表：回表行数 × row_io_cost

CPU 成本：
  - 评估 WHERE 条件：行数 × row_eval_cost
  - 排序：排序行数 × row_eval_cost × sort_factor

成本模型参数（mysql.server_cost / mysql.engine_cost）：

  server_cost:
  ┌──────────────────────────────┬──────────┬────────────────────────┐
  │ 参数                         │ 默认值   │ 含义                    │
  ├──────────────────────────────┼──────────┼────────────────────────┤
  │ disk_temptable_create_cost   │ 20.0     │ 创建磁盘临时表          │
  │ disk_temptable_row_cost      │ 0.5      │ 磁盘临时表每行           │
  │ memory_temptable_create_cost │ 1.0      │ 创建内存临时表          │
  │ memory_temptable_row_cost    │ 0.1      │ 内存临时表每行           │
  │ key_compare_cost             │ 0.05     │ 索引比较（排序/GROUP BY）│
  │ row_evaluate_cost            │ 0.10     │ 行评估（WHERE 过滤）    │
  └──────────────────────────────┴──────────┴────────────────────────┘

  engine_cost（InnoDB）:
  ┌──────────────────────────────┬──────────┬────────────────────────┐
  │ io_block_read_cost           │ 1.0      │ 磁盘读取一个页           │
  │ memory_block_read_cost       │ 0.25     │ 内存读取一个页（Buffer Pool）│
  └──────────────────────────────┴──────────┴────────────────────────┘
```

### 4.4 成本计算示例

```
全表扫描 100 万行的成本：
  10000 页 × 1.0 = 10000（IO 成本）
  100 万行 × 0.10 = 100000（CPU 成本）
  总成本 = 110000

索引扫描 1000 行的成本：
  索引页 10 × 1.0 = 10（索引 IO）
  1000 行 × 0.10 = 100（索引 CPU）
  回表 1000 × 1.0 = 1000（回表 IO）
  1000 行 × 0.10 = 100（回表 CPU）
  总成本 = 10 + 100 + 1000 + 100 = 1210

优化器选择：1210 < 110000 → 使用索引
但如果 age > 0（匹配 99% 行）→ 回表 99 万次 → 成本 > 全表扫描 → 优化器选择全表扫描
```

---

## 第五部分 ANALYZE 语句（MySQL 8.0）

### 5.1 EXPLAIN ANALYZE 语法

```sql
-- MySQL 8.0.18+
EXPLAIN ANALYZE SELECT * FROM users WHERE age = 25 AND city = '杭州';
```

输出示例：

```
-> Filter: (users.age = 25 and users.city = '杭州')  (cost=1.20 rows=1) (actual time=0.045..0.046 rows=1 loops=1)
    -> Index lookup on users using idx_age_city (age, city)  (cost=1.20 rows=1) (actual time=0.040..0.041 rows=1 loops=1)
```

### 5.2 r_rows vs rows — 实际 vs 预估

```
┌──────────────┬──────────────────────────────────────────────┐
│ 字段         │ 含义                                         │
├──────────────┼──────────────────────────────────────────────┤
│ rows         │ 优化器预估行数                               │
│ actual rows  │ 实际扫描行数（r_rows）                      │
│ loops        │ 该操作执行的次数                             │
│ actual time  │ 实际耗时（毫秒），格式：min..max            │
│ cost         │ 优化器预估成本                               │
└──────────────┴──────────────────────────────────────────────┘

分析要点：
  - rows 远小于 actual rows → 统计信息不准确 → ANALYZE TABLE
  - actual time 高但 rows 低 → 单行处理代价高 → 检查回表
  - loops > 1 → 子查询重复执行 → 考虑改写为 JOIN
```

### 5.3 EXPLAIN ANALYZE 实战案例

```sql
-- 案例：范围查询预估与实际偏差
EXPLAIN ANALYZE SELECT * FROM users WHERE age BETWEEN 25 AND 35;

-- 输出：
-> Filter: (users.age between 25 and 35)  (cost=2050 rows=10000) (actual time=0.1..15.2 rows=50000 loops=1)
    -> Index range scan on users using idx_age_city  (cost=2050 rows=10000) (actual time=0.08..10.5 rows=50000 loops=1)

-- 分析：
-- 预估 rows=10000，实际 rows=50000 → 5 倍偏差
-- 原因：统计信息过期
-- 修复：ANALYZE TABLE users; 然后重新检查
```

---

## 第六部分 慢查询日志配置与分析

### 6.1 slow_query_log 配置详解

```sql
-- 查看慢查询日志状态
SHOW VARIABLES LIKE 'slow_query%';
SHOW VARIABLES LIKE 'long_query_time';

-- 开启慢查询日志
SET GLOBAL slow_query_log = ON;
SET GLOBAL slow_query_log_file = '/var/log/mysql/slow.log';

-- 设置慢查询阈值（秒）
SET GLOBAL long_query_time = 1;

-- my.cnf 永久配置
[mysqld]
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 1
log_queries_not_using_indexes = 1
log_slow_admin_statements = 1
log_slow_slave_statements = 1
min_examined_row_limit = 100
```

### 6.2 关键配置参数

```
┌──────────────────────────────────────┬────────────────────────────────┐
│ 参数                                  │ 含义                            │
├──────────────────────────────────────┼────────────────────────────────┤
│ slow_query_log                       │ 是否开启慢查询日志               │
│ slow_query_log_file                  │ 日志文件路径                     │
│ long_query_time                      │ 慢查询阈值（秒，精度到微秒）      │
│ log_queries_not_using_indexes        │ 记录未使用索引的查询              │
│ log_slow_admin_statements            │ 记录慢管理语句（ALTER/ANALYZE）  │
│ log_slow_slave_statements            │ 记录从库慢语句                   │
│ min_examined_row_limit               │ 扫描行数低于此值不记录            │
│ log_output                           │ FILE / TABLE / FILE,TABLE       │
│ log_throttle_queries_not_using_indexes│ 每分钟记录无索引查询的最大次数   │
└──────────────────────────────────────┴────────────────────────────────┘
```

### 6.3 慢查询日志格式

```
# Time: 2025-06-29T10:15:41.123456Z
# User@Host: root[root] @ localhost [127.0.0.1]  Id: 12345
# Query_time: 3.456789  Lock_time: 0.000123  Rows_sent: 10  Rows_examined: 1000000
# Bytes_sent: 2048  Tmp_tables: 1  Tmp_disk_tables: 0  Tmp_table_sizes: 16777216
# InnoDB_pages_distinct: 5000
use mydb;
SET timestamp=1719653741;
SELECT * FROM users WHERE age > 25 ORDER BY created_at LIMIT 10;

字段解读：
  Query_time    — 查询总耗时（秒）
  Lock_time     — 等待锁的时间（秒）
  Rows_sent     — 返回给客户端的行数
  Rows_examined — 扫描的行数（关键指标）
  Tmp_tables    — 创建的内存临时表数量
  Tmp_disk_tables — 创建的磁盘临时表数量（性能杀手）

  优化目标：
  Rows_examined / Rows_sent 应该尽可能接近 1:1
  如果比值为 100000:1 → 需要优化
```

### 6.4 mysqldumpslow 工具

```bash
# 按查询时间排序，显示前 10
mysqldumpslow -s t -t 10 /var/log/mysql/slow.log

# 按次数排序（最频繁的查询）
mysqldumpslow -s c -t 10 /var/log/mysql/slow.log

# 参数说明：
# -s t  按总时间排序
# -s at 按平均时间排序
# -s c  按次数排序
# -s r  按返回行数排序
# -t N  显示前 N 条
# -g pattern  只显示匹配的查询（正则）

# 输出示例：
# Count: 500  Time=2.50s (1250s)  Lock=0.00s (0s)  Rows=10.0 (5000)
#   SELECT * FROM users WHERE age > N ORDER BY created_at LIMIT N
```

### 6.5 pt-query-digest 工具

```bash
# 基本用法（比 mysqldumpslow 更强大）
pt-query-digest /var/log/mysql/slow.log

# 按特定数据库过滤
pt-query-digest --filter '$event->{db} eq "mydb"' /var/log/mysql/slow.log

# 只分析最近 1 小时
pt-query-digest --since '1h' /var/log/mysql/slow.log

# 输出示例：
# Profile
# Rank Query ID                      Response time  Calls  R/Call  V/M
# ==== ============================= ============== ====== ======= =====
#    1 0xABCDEF1234567890...          500.0000 45.0%    50 10.0000  0.5
#    2 0x1234567890ABCDEF...          200.0000 18.0%   100  2.0000  0.1
```

### 6.6 Performance Schema 慢查询分析

```sql
-- 查看按摘要分组的慢查询统计
SELECT 
    DIGEST_TEXT,
    COUNT_STAR AS exec_count,
    ROUND(AVG_TIMER_WAIT/1000000000, 2) AS avg_ms,
    ROUND(SUM_TIMER_WAIT/1000000000, 2) AS total_ms,
    SUM_ROWS_EXAMINED AS rows_examined,
    SUM_ROWS_SENT AS rows_sent,
    SUM_CREATED_TMP_TABLES AS tmp_tables,
    SUM_CREATED_TMP_DISK_TABLES AS tmp_disk_tables
FROM performance_schema.events_statements_summary_by_digest
WHERE AVG_TIMER_WAIT > 1000000000  -- 平均超过 1 秒
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;
```

### 6.7 sys schema 慢查询分析

```sql
-- 查看慢查询 Top 10
SELECT * FROM sys.statements_with_runtimes_in_95th_percentile LIMIT 10;

-- 查看全表扫描的查询
SELECT * FROM sys.statements_with_full_table_scans LIMIT 10;

-- 查看使用临时表的查询
SELECT * FROM sys.statements_with_temp_tables LIMIT 10;
```

### 6.8 慢查询治理流程

```
1. 收集慢查询 → pt-query-digest 分析 → 按总耗时排序 → 找最大收益目标
2. 分类慢查询：
   - 索引问题（type=ALL）→ 加索引
   - 排序问题（Using filesort）→ ORDER BY 优化
   - 临时表（Using temporary）→ GROUP BY 优化
   - JOIN 问题（Using join buffer）→ 加索引
   - 深分页 → 延迟关联/游标分页
   - 子查询 → 改写为 JOIN
3. EXPLAIN 分析 → FORMAT=JSON 查看成本 → ANALYZE 查看实际
4. 优化执行 → 加索引 / 改 SQL / 改表结构
5. 验证效果 → 重新 EXPLAIN → 压测确认 → 持续监控
6. 持续治理 → 定期巡检 → 设置报警 → 建立知识库
```

---

## 第七部分 ORDER BY 优化

### 7.1 Using filesort 触发条件

```sql
-- 场景1：ORDER BY 列无索引
EXPLAIN SELECT * FROM users ORDER BY created_at;
-- Extra = Using filesort（created_at 无索引）

-- 场景2：ORDER BY 列有索引，但 WHERE 用了不同索引
EXPLAIN SELECT * FROM users WHERE age = 25 ORDER BY name;
-- key = idx_age_city, Extra = Using filesort（name 不在使用的索引中）

-- 场景3：ORDER BY 混合排序方向
EXPLAIN SELECT * FROM users WHERE age > 25 ORDER BY age DESC, city ASC;
-- Extra = Using filesort（DESC + ASC 混合方向，索引无法满足）

-- 场景4：SELECT * 导致回表后排序
EXPLAIN SELECT * FROM users WHERE age > 25 ORDER BY age, city;
-- Extra = Using filesort（回表后数据无序，需重新排序）

-- 场景5：ORDER BY 使用索引（无 filesort）
EXPLAIN SELECT id, age, city FROM users WHERE age > 25 ORDER BY age, city;
-- Extra = Using index condition（覆盖索引，索引有序，无需排序）
```

### 7.2 排序算法详解

#### 7.2.1 单路排序（Single-Pass Sort）— MySQL 4.1+ 默认

```
单路排序（默认）：
  一次性读取所有需要的列到 sort_buffer → 排序 → 输出

  优点：只需一次 I/O（所有数据在内存中排序）
  缺点：内存占用大（存所有 SELECT 列）

  如果 sort_buffer 不够：
  1. 将 sort_buffer 中的数据写入临时文件
  2. 继续读取下一批到 sort_buffer
  3. 最后对多个有序的临时文件做归并排序
```

#### 7.2.2 优先队列排序（Top-N Sort）

```sql
-- LIMIT 场景使用优先队列
EXPLAIN SELECT * FROM users ORDER BY age LIMIT 10;
-- Extra = Using filesort
-- 实际使用优先队列（堆排序），只维护 Top 10
```

```
优先队列排序（Top-N）：
  当有 LIMIT N 时，不需要对所有数据排序
  使用大小为 N 的堆（优先队列），只维护最大的 N 个元素

  1. 读取第一行 → 放入堆
  2. 读取下一行 → 与堆顶比较
     - 如果更小（ASC排序）→ 替换堆顶，调整堆
     - 如果更大 → 丢弃
  3. 重复直到所有行读完
  4. 堆中剩余 N 行就是结果

  优点：内存 O(N) 而非 O(全部行数)，不需要临时文件

  源码：filesort.cc → Filesort::sort()
  → check_if_pq_applicable() 判断是否可以使用优先队列
  → Bounded_queue<...> 优先队列实现
```

### 7.3 sort_buffer_size 与临时文件

```sql
SHOW VARIABLES LIKE 'sort_buffer_size';
-- 默认 256KB

SHOW STATUS LIKE 'Sort_merge_passes';
-- 如果持续增长 → sort_buffer_size 太小，需要调大

-- sort_buffer_size 调优建议：
-- - 默认 256KB（适合小结果集）
-- - 1MB ~ 4MB（一般场景）
-- - 不超过 8MB（避免内存浪费，每个连接独立分配）
```

### 7.4 ORDER BY 索引优化策略

```
1. ORDER BY 列与索引列顺序一致
   INDEX (a, b, c)
   ✅ ORDER BY a, b, c  → 无 filesort
   ✅ ORDER BY a, b     → 无 filesort
   ✅ ORDER BY a        → 无 filesort
   ❌ ORDER BY b, c     → 缺少最左前缀 a，需 filesort
   ❌ ORDER BY a, c     → 跳过 b，需 filesort

2. WHERE 等值 + ORDER BY 使用同一索引
   INDEX (a, b)
   ✅ WHERE a=1 ORDER BY b  → 索引中 a 相同的范围内 b 有序
   ❌ WHERE a>1 ORDER BY b  → a 是范围查询，b 不一定有序

3. ORDER BY 方向一致
   ✅ ORDER BY a ASC, b ASC   → 同方向
   ✅ ORDER BY a DESC, b DESC → 同方向
   ❌ ORDER BY a ASC, b DESC  → 混合方向，需 filesort

4. 覆盖索引消除 filesort
   INDEX (a, b, c)
   ✅ SELECT a,b,c FROM t WHERE a=1 ORDER BY b,c → 覆盖索引，无 filesort
   ❌ SELECT * FROM t WHERE a=1 ORDER BY b,c     → 需回表 → filesort

5. 使用覆盖索引 + 延迟关联
   SELECT * FROM t t1
   JOIN (SELECT id FROM t WHERE a=1 ORDER BY b LIMIT 10) t2
   ON t1.id = t2.id;
   → 子查询用覆盖索引排序，只对 10 行回表
```

### 7.5 filesort 源码解析

```cpp
// filesort.cc 核心流程简化

int Filesort::sort(THD *thd, ...) {
    // 1. 判断是否可以使用优先队列（LIMIT 场景）
    if (check_if_pq_applicable(...)) {
        return create_priority_queue_and_sort(...);  // 堆排序
    }
    
    // 2. 分配 sort_buffer
    sort_buffer = alloc_sort_buffer(...);
    
    // 3. 读取数据到 sort_buffer
    while (read_record(...)) {
        put_record_in_buffer(sort_buffer, record);
        if (buffer_full(sort_buffer)) {
            write_block_to_tempfile(tempfile, sort_buffer);  // 写临时文件
            clear_buffer(sort_buffer);
        }
    }
    
    // 4. 排序
    if (no_tempfile) {
        sort_buffer_in_memory(sort_buffer);  // 内存排序
    } else {
        merge_sort_tempfiles(tempfile, sort_buffer);  // 归并排序
    }
    
    return 0;
}
```

### 7.6 排序算法选择决策树

```
                     有 LIMIT N?
                    /           \
                  是              否
                  |               |
          数据量 <= sort_buffer?   数据量 <= sort_buffer?
           /         \             /         \
         是           否          是           否
         |            |           |            |
    优先队列排序    优先队列+    内存排序      归并排序
    (堆排序)      临时文件                   (多路归并)
```

---

## 第八部分 GROUP BY 优化

### 8.1 Using temporary 触发条件

```sql
-- GROUP BY 列无索引 → 临时表
EXPLAIN SELECT city, COUNT(*) FROM users GROUP BY city;
-- Extra = Using temporary; Using filesort

-- GROUP BY 使用索引（无临时表）
EXPLAIN SELECT age, COUNT(*) FROM users GROUP BY age;
-- key = idx_age_city, Extra = Using index（age 是索引前导列，索引有序）
```

> **注意**：MySQL 8.0 默认 `GROUP BY` 不排序（除非显式 `ORDER BY`）。

### 8.2 松散索引扫描（Loose Index Scan）

```sql
-- 松散索引扫描：跳过不相关的索引值
-- INDEX (a, b)
EXPLAIN SELECT a, MIN(b) FROM t GROUP BY a;
-- Extra = Using index for group-by（松散索引扫描）
```

```
松散索引扫描原理：
  B+Tree 叶子节点链表（按 a, b 排序）：
  [1,1]→[1,2]→[1,3]→[2,1]→[2,2]→[3,1]→[3,2]

  GROUP BY a, MIN(b):
  → [1,1] 取 MIN(b)=1，跳到下一个 a 值
  → [2,1] 取 MIN(b)=1，跳到下一个 a 值
  → [3,1] 取 MIN(b)=1，结束

  只扫描了 3 行（每个 a 值的第一行），而非全部 7 行
  适合：MIN/MAX/COUNT(DISTINCT) 等聚合

  源码：sql_executor.cc → QUICK_GROUP_MIN_MAX_SELECT
```

### 8.3 紧凑索引扫描（Tight Index Scan）

```sql
-- 紧凑索引扫描：扫描全部索引，但无需临时表
EXPLAIN SELECT a, b, SUM(c) FROM t WHERE a > 1 GROUP BY a, b;
-- Extra = Using index（紧凑索引扫描）
-- 需要扫描所有匹配的索引条目，但利用索引有序性避免临时表
```

### 8.4 GROUP BY 临时表内部过程

```
SELECT city, COUNT(*) FROM users GROUP BY city;

  1. 创建临时表（city 为 KEY）
  ┌──────────┬──────────┐
  │ city     │ COUNT(*) │
  │ (KEY)    │ (INT)    │
  └──────────┴──────────┘

  2. 逐行扫描 users 表
     行1: city='杭州' → 插入 ('杭州', 1)
     行2: city='北京' → 插入 ('北京', 1)
     行3: city='杭州' → 已有 '杭州' → COUNT 更新为 2
     ...

  3. 扫描完成后，从临时表读取结果

  源码：sql_executor.cc → create_tmp_table() → sub_select_op()
```

### 8.5 GROUP BY 优化策略

```
1. 给 GROUP BY 列加索引 → 消除 Using temporary
2. WHERE 和 GROUP BY 使用同一索引
3. 使用覆盖索引
4. 避免 SELECT *
5. MySQL 8.0：GROUP BY 不默认排序，不需要 ORDER BY NULL
6. 大量分组时考虑预聚合（先在子表聚合，再外层聚合）
7. 限制分组数量（GROUP BY ... LIMIT N）
```

---

## 第九部分 LIMIT 深分页优化

### 9.1 深分页性能问题本质

```sql
-- 深分页（慢）
SELECT * FROM orders ORDER BY id LIMIT 1000000, 20;
-- 扫描 1000020 行，回表 100 万次，只返回 20 行
```

### 9.2 延迟关联（Deferred Join）

```sql
-- 子查询只扫描主键（覆盖索引），只对 20 行回表
SELECT * FROM orders o
JOIN (
    SELECT id FROM orders ORDER BY id LIMIT 1000000, 20
) t ON o.id = t.id;
```

```
延迟关联原理：
  优化前：SELECT * FROM t ORDER BY id LIMIT 1000000, 20
  → B+Tree 扫描 100 万行 → 每行回表 → 回表 100 万次

  优化后：SELECT * FROM t JOIN (SELECT id FROM t ORDER BY id LIMIT 1000000, 20) tmp ON t.id = tmp.id
  → 子查询：覆盖索引扫描（只扫主键，不回表）→ 取最后 20 个 id
  → JOIN：只对 20 行回表
```

### 9.3 游标分页（Cursor-based Pagination）

```sql
-- 前端传上一页最后的 id
SELECT * FROM orders WHERE id > 1000000 ORDER BY id LIMIT 20;
-- 直接走主键索引 range 扫描，扫描 20 行
```

### 9.4 深分页优化方案对比

```
┌──────────────────┬───────────────┬───────────────┬──────────────────────┐
│ 方案             │  扫描行数      │  回表次数      │  适用场景             │
├──────────────────┼───────────────┼───────────────┼──────────────────────┤
│ 原始 LIMIT       │  offset+N     │  offset+N     │  浅分页               │
│ 延迟关联          │  offset+N     │  N            │  深分页 + 需跳页      │
│ 游标分页          │  N            │  N            │  深分页 + 不需跳页    │
│ WHERE id > cursor│  N            │  N            │  主键有序 + 无间隙    │
│ 预计算/缓存       │  0            │  N            │  超大数据量           │
└──────────────────┴───────────────┴───────────────┴──────────────────────┘

  推荐策略：
  - 浅分页（offset < 1000）：直接 LIMIT
  - 中等分页（1000 < offset < 100000）：延迟关联
  - 深分页（offset > 100000）：游标分页
  - 超深分页：预计算 + 缓存（Redis ZSET）
```

---

## 第十部分 JOIN 优化

### 10.1 Nested Loop Join（NLJ）— 基础 JOIN 算法

```sql
SELECT * FROM users u JOIN orders o ON u.id = o.user_id WHERE u.age > 25;
```

```
Nested Loop Join 执行过程：

  驱动表 users（WHERE age > 25，匹配 1000 行）
  被驱动表 orders（user_id 上有索引 idx_user_id）

  for each row r in users where age > 25:    // 1000 次
      for each row s in orders where s.user_id = r.id:  // 索引查找
          if match:
              output (r, s)

  总成本：
  - 驱动表扫描：1000 行
  - 被驱动表索引查找：1000 次
  - 总 I/O：1000 + 1000 × 2 = 3000 次

  源码：sql_executor.cc → sub_select()
```

### 10.2 Block Nested Loop（BNL）— 被驱动表无索引

```sql
SELECT * FROM users u JOIN orders o ON u.name = o.remark;
-- orders.remark 无索引 → 使用 BNL
-- Extra = Using join buffer (Block Nested Loop)
```

```
Block Nested Loop 执行过程：

  Step 1: 将驱动表一批数据放入 Join Buffer
  Step 2: 扫描被驱动表，与 Buffer 中的每行做匹配
  Step 3: Buffer 用完后，加载下一批驱动表数据

  总扫描次数：
  - 驱动表：1000 行（分 10 批）
  - 被驱动表：100000 × 10 = 1000000 次（每批扫描一次）
  - 总比较次数：1000 × 100000 = 1 亿次

  BNL 比有索引的 NLJ 慢 100000 倍！
```

### 10.3 Hash Join（MySQL 8.0.18+）

```sql
SELECT * FROM users u JOIN orders o ON u.name = o.remark;
-- MySQL 8.0.18+ 使用 Hash Join
-- Extra = Using join buffer (hash join)
```

```
Hash Join 执行过程：

  Phase 1: Build（构建哈希表）
  → 扫描驱动表（较小的表）
  → 对 JOIN 条件的列计算 hash
  → 构建 Hash Table

  Phase 2: Probe（探测）
  → 扫描被驱动表
  → 对 JOIN 条件的列计算 hash
  → 在 Hash Table 中查找匹配

  总成本：
  - Build：扫描驱动表 1 次
  - Probe：扫描被驱动表 1 次
  - 比 BNL 快很多（BNL 扫描被驱动表 N 批次次）

  源码：sql_executor.cc → QEP_TAB::prepare_hash_join()
  → HashJoinRowBuffer::BuildHashTable() / Lookup()
```

### 10.4 驱动表选择策略

```
优化器选择驱动表的原则：
  选择「扫描成本 + 被驱动表查找成本」最小的方案

  小表驱动大表：
  - 驱动表小 → 扫描少 → 被驱动表索引查找次数少

  估算公式（NLJ）：
  总成本 = 驱动表扫描成本 + (驱动表结果行数 × 被驱动表单次查找成本)

  示例：
  表 A：WHERE 后 10 行
  表 B：WHERE 后 1000 行
  B 有索引

  A 驱动 B：10 × (B索引查找) = 10 次 ✅
  B 驱动 A：1000 × (A索引查找) = 1000 次 ❌

  必要时用 STRAIGHT_JOIN 强制驱动顺序
  SELECT * FROM A STRAIGHT_JOIN B ON ... -- A 驱动 B
```

### 10.5 BKA（Batched Key Access）

```sql
SET optimizer_switch='batched_key_access=on,mrr=on,mrr_cost_based=off';
-- BKA：批量索引查找 + MRR
-- 收集一批 JOIN key → 批量索引查找 → 主键排序 → 顺序回表
```

### 10.6 JOIN 优化实战策略

```
1. 给被驱动表的 JOIN 列加索引（消除 BNL）
2. 小表驱动大表（优化器通常自动选择，必要时 STRAIGHT_JOIN）
3. 减少驱动表结果集（WHERE 条件尽早过滤）
4. 覆盖索引避免回表
5. Hash Join 替代 BNL（8.0+）
6. 避免过多表 JOIN（3 表以上拆分）
7. 控制JOIN行数（子查询先过滤和 LIMIT）

  JOIN 三种变体：
  ┌──────────┬──────────────┬───────────────────────┐
  │ NLJ      │ 被驱动表有索引│ 逐行索引查找           │
  │ BNL      │ 被驱动表无索引│ Join Buffer 批量匹配   │
  │ Hash Join│ 等值连接      │ 哈希表一次匹配（8.0+）│
  └──────────┴──────────────┴───────────────────────┘
```

---

## 第十一部分 子查询优化

### 11.1 物化（Materialization）

```sql
-- MySQL 5.6+ 对 IN 子查询的优化
EXPLAIN SELECT * FROM users WHERE id IN (SELECT user_id FROM orders);
```

```
物化优化过程：

  优化前（DEPENDENT SUBQUERY）：每行重复执行子查询
  优化后（MATERIALIZED）：
  Step 1: 执行子查询，结果物化为临时表（有索引）
  Step 2: 外查询与物化表做半连接（索引查找 O(1)）

  性能提升：子查询从 N 次执行降为 1 次

  源码：sql_optimizer.cc → convert_subquery_to_semijoin()
  → JT_MATERIALIZE → create_tmp_table()
```

### 11.2 半连接（Semi-Join）五种策略

```
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders)

MySQL 优化器可能选择以下策略之一：

1. FirstMatch → 找到第一个匹配就停止
2. Materialization → 子查询物化为临时表
3. LooseScan → 子查询表做索引扫描，跳过重复值
4. DuplicateWeedout → 先 JOIN 再用临时表去重
5. MaterializeScan → 物化子查询，然后扫描 JOIN

源码：sql_optimizer.cc → convert_subquery_to_semijoin()
→ optimize_semijoin_nests() 选择最优策略
```

### 11.3 NOT IN / NOT EXISTS → 反连接（Anti-Join）

```sql
-- MySQL 8.0 优化为 Anti-Join
EXPLAIN SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM orders);
-- Extra = Anti-join
```

### 11.4 派生表（Derived Table）优化

```sql
-- MySQL 5.7+：派生表合并（Derived Merge）
EXPLAIN SELECT * FROM (
    SELECT id, name, age FROM users WHERE age > 25
) AS t WHERE t.name LIKE '张%';
-- 等价于：SELECT id, name, age FROM users WHERE age > 25 AND name LIKE '张%'
-- 不再产生临时表（derived_merge=on）
```

### 11.5 子查询改写为 JOIN

```sql
-- IN 子查询 → INNER JOIN
SELECT u.* FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE o.amount > 100;
-- 如果 user_id 不唯一，需要 DISTINCT

-- NOT IN → LEFT JOIN + IS NULL
SELECT u.* FROM users u
LEFT JOIN orders o ON u.id = o.user_id
WHERE o.user_id IS NULL;
```

---

## 第十二部分 15 个真实慢查询案例

### 12.1 案例1：全表扫描 → 加索引

```sql
-- 问题 SQL（耗时 3.2s）
SELECT * FROM orders WHERE customer_id = 12345 AND status = 'PAID';
-- EXPLAIN: type = ALL, key = NULL, rows = 1000000

-- 优化：加复合索引
CREATE INDEX idx_customer_status ON orders(customer_id, status);
-- 优化后: type = ref, key = idx_customer_status, rows = 50
-- 耗时：2ms（提升 1600 倍）
```

### 12.2 案例2：隐式类型转换导致索引失效

```sql
-- 问题 SQL（耗时 5.8s）
SELECT * FROM orders WHERE order_no = 20250629001;  -- order_no 是 VARCHAR
-- EXPLAIN: type = ALL（隐式转换导致索引失效）

-- 优化：传入正确的类型
SELECT * FROM orders WHERE order_no = '20250629001';
-- 优化后: type = ref, rows = 1
-- 耗时：1ms（提升 5800 倍）
```

### 12.3 案例3：深分页 LIMIT 1000000, 20

```sql
-- 问题 SQL（耗时 8.5s）
SELECT * FROM orders ORDER BY id LIMIT 1000000, 20;

-- 方案1：延迟关联（200ms）
SELECT * FROM orders o
JOIN (SELECT id FROM orders ORDER BY id LIMIT 1000000, 20) t ON o.id = t.id;

-- 方案2：游标分页（2ms）
SELECT * FROM orders WHERE id > 1000000 ORDER BY id LIMIT 20;
-- 提升 4250 倍
```

### 12.4 案例4：ORDER BY filesort 优化

```sql
-- 问题 SQL（耗时 4.2s）
SELECT * FROM users WHERE age > 25 ORDER BY created_at DESC LIMIT 20;
-- Extra = Using filesort

-- 方案1：加索引消除 filesort
CREATE INDEX idx_age_created ON users(age, created_at);
-- Extra = NULL（索引有序）
-- 耗时 15ms

-- 方案2：延迟关联 + 覆盖索引
SELECT * FROM users u
JOIN (SELECT id FROM users WHERE age > 25 ORDER BY created_at DESC LIMIT 20) t ON u.id = t.id;
-- 耗时 10ms（提升 280 倍）
```

### 12.5 案例5：GROUP BY 临时表优化

```sql
-- 问题 SQL（耗时 6.5s）
SELECT city, COUNT(*) FROM users WHERE age > 25 GROUP BY city;
-- Extra = Using temporary; Using filesort

-- 优化：新建索引
CREATE INDEX idx_city_age ON users(city, age);
-- Extra = Using index（覆盖索引，无临时表）
-- 耗时 200ms（提升 32 倍）
```

### 12.6 案例6：JOIN 驱动表选择错误

```sql
-- 问题 SQL（耗时 12s）
SELECT * FROM orders o JOIN users u ON o.user_id = u.id
WHERE o.status = 'PENDING' AND u.city = '杭州';
-- 优化器错误选择 orders（50万行）驱动 users

-- 优化1：STRAIGHT_JOIN
SELECT STRAIGHT_JOIN * FROM users u JOIN orders o ON o.user_id = u.id
WHERE o.status = 'PENDING' AND u.city = '杭州';
-- 耗时 800ms

-- 优化2：加索引让优化器做对选择
CREATE INDEX idx_status_user ON orders(status, user_id);
CREATE INDEX idx_city ON users(city);
-- 耗时 300ms（提升 40 倍）
```

### 12.7 案例7：OR 条件索引失效

```sql
-- 问题 SQL（耗时 7.3s）
SELECT * FROM users WHERE age = 25 OR name = '张三';
-- type = ALL

-- 优化：UNION 改写
SELECT * FROM users WHERE age = 25
UNION
SELECT * FROM users WHERE name = '张三';
-- 两个查询分别使用索引
-- 耗时 20ms（提升 365 倍）
```

### 12.8 案例8：函数导致索引失效

```sql
-- 问题 SQL（耗时 4.8s）
SELECT * FROM orders WHERE DATE(created_at) = '2025-06-29';
-- type = ALL

-- 优化：改为范围查询
SELECT * FROM orders 
WHERE created_at >= '2025-06-29 00:00:00' AND created_at < '2025-06-30 00:00:00';
-- type = range
-- 耗时 5ms（提升 960 倍）
```

### 12.9 案例9：范围查询后索引列失效

```sql
-- 问题 SQL（耗时 3.1s）
SELECT * FROM users WHERE age > 25 AND city = '杭州';
-- 索引 idx_age_city(age, city)：只用了 age（范围查询截断 city）
-- key_len = 4, rows = 50000

-- 优化：调整索引列顺序（等值在前，范围在后）
CREATE INDEX idx_city_age ON users(city, age);
-- key_len = 206（两列都用上）
-- rows = 5000
-- 耗时 50ms（提升 62 倍）
```

### 12.10 案例10：LIKE 前导通配符

```sql
-- 问题 SQL（耗时 5.2s）
SELECT * FROM users WHERE name LIKE '%三';
-- type = ALL

-- 优化1：改用后导通配符
SELECT * FROM users WHERE name LIKE '张%';
-- type = range（10ms）

-- 优化2：全文索引
ALTER TABLE users ADD FULLTEXT INDEX ft_name(name);
SELECT * FROM users WHERE MATCH(name) AGAINST('三' IN BOOLEAN MODE);
```

### 12.11 案例11：复合索引顺序问题

```sql
-- 问题 SQL（耗时 6.8s）
SELECT * FROM orders WHERE status = 'PAID' AND created_at > '2025-06-01' AND customer_id = 12345;
-- 现有索引 idx_status_created(status, created_at)：只用了 status
-- rows = 200000

-- 优化：等值列在前，范围列在后
CREATE INDEX idx_customer_status_created ON orders(customer_id, status, created_at);
-- 三列都用上, rows = 50
-- 耗时 3ms（提升 2266 倍）
```

### 12.12 案例12：COUNT(*) 优化

```sql
-- 问题 SQL（耗时 4.5s）
SELECT COUNT(*) FROM orders WHERE status = 'PENDING';
-- 仍需扫描 50 万行计数

-- 优化：维护计数表
CREATE TABLE order_counts (status VARCHAR(20) PRIMARY KEY, cnt BIGINT NOT NULL);
-- 通过触发器或应用维护
SELECT cnt FROM order_counts WHERE status = 'PENDING';
-- type = const, rows = 1
-- 耗时 0.1ms（提升 45000 倍）
```

### 12.13 案例13：DISTINCT 优化

```sql
-- 问题 SQL（耗时 3.6s）
SELECT DISTINCT customer_id FROM orders WHERE status = 'PAID';
-- Extra = Using temporary

-- 优化：加覆盖索引
CREATE INDEX idx_status_customer ON orders(status, customer_id);
-- Extra = Using index; Using index for group-by（松散索引扫描）
-- 耗时 100ms（提升 36 倍）
```

### 12.14 案例14：UNION vs UNION ALL

```sql
-- 问题 SQL（耗时 5.4s）
SELECT id, name FROM users WHERE age = 25
UNION
SELECT id, name FROM users WHERE city = '杭州';
-- UNION 需要去重 → Using temporary

-- 优化：如果确定无交集，改为 UNION ALL
SELECT id, name FROM users WHERE age = 25
UNION ALL
SELECT id, name FROM users WHERE city = '杭州';
-- 无 Using temporary
-- 耗时 200ms（提升 27 倍）
```

### 12.15 案例15：子查询改写为 JOIN

```sql
-- 问题 SQL（耗时 8.2s）
SELECT * FROM users u WHERE u.id IN (
    SELECT user_id FROM orders WHERE amount > 1000
);
-- 可能退化为 DEPENDENT SUBQUERY

-- 优化1：改写为 JOIN
SELECT DISTINCT u.* FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE o.amount > 1000;
-- 耗时 300ms

-- 优化2：EXISTS 改写（MySQL 8.0 优化为半连接）
SELECT * FROM users u WHERE EXISTS (
    SELECT 1 FROM orders o WHERE o.user_id = u.id AND o.amount > 1000
);
-- 耗时 200ms（提升 41 倍）
```

---

## 第十三部分 优化器 Trace 分析

### 13.1 optimizer_trace 开启与配置

```sql
SET optimizer_trace = 'enabled=on';
SET optimizer_trace_max_mem_size = 1048576;  -- 1MB

-- 执行查询
SELECT * FROM users WHERE age = 25 AND city = '杭州';

-- 查看 trace
SELECT * FROM information_schema.OPTIMIZER_TRACE\G
```

### 13.2 trace JSON 关键结构

```json
{
  "steps": [
    {
      "join_preparation": { ... }
    },
    {
      "join_optimization": {
        "steps": [
          {
            "condition_processing": {
              "transformation": "equality_propagation",
              "resulting_condition": "..."
            }
          },
          {
            "rows_estimation": {
              "table": "users",
              "range_analysis": {
                "table_scan": { "rows": 1000000, "cost": 205000 },
                "potential_range_indexes": [
                  {"index": "idx_age_city", "usable": true},
                  {"index": "idx_email", "usable": false}
                ],
                "best_range_access": {
                  "chosen_range_access": {
                    "key": "idx_age_city", "rows": 50, "cost": 61
                  }
                }
              }
            }
          },
          {
            "considered_execution_plans": [{
              "best_access_path": {
                "access_type": "ref", "key": "idx_age_city",
                "cost": 1.2, "rows": 1
              }
            }]
          }
        ]
      }
    }
  ]
}
```

### 13.3 关键分析点

```
1. rows_estimation → table_scan → 查看全表扫描成本
2. rows_estimation → potential_range_indexes → 查看可用索引及原因
3. rows_estimation → best_range_access → 优化器选择的最佳索引
4. considered_execution_plans → best_access_path → 最终访问路径
5. attaching_conditions_to_tables → 确认 ICP 是否生效
```

### 13.4 调试优化器选择错误索引

```sql
-- Step 1: 查看 trace 中的成本对比
SET optimizer_trace = 'enabled=on';
SELECT * FROM users WHERE age = 25 AND name = '张三';
SELECT trace FROM information_schema.OPTIMIZER_TRACE\G

-- Step 2: 使用 FORCE INDEX 验证
SELECT * FROM users FORCE INDEX(idx_B) WHERE age = 25 AND name = '张三';

-- Step 3: 可能的原因
-- a. 统计信息过期 → ANALYZE TABLE
-- b. 索引基数不准 → 调采样页数
SET GLOBAL innodb_stats_persistent_sample_pages = 100;
ANALYZE TABLE users;

-- Step 4: 永久修复
-- ANALYZE TABLE / 调整 optimizer_switch / FORCE INDEX / 删除冗余索引
```

---

## 附录

### 附录 A：EXPLAIN 列速查表

```
┌────────────────┬─────────────────────────────────────┬─────────────────────────┐
│ 列名           │ 含义                                │ 关注重点                 │
├────────────────┼─────────────────────────────────────┼─────────────────────────┤
│ id             │ SELECT 序号                        │ 执行顺序                 │
│ select_type    │ 查询类型                            │ DEPENDENT SUBQUERY 差    │
│ table          │ 表名                                │ <derived> <union> 特殊   │
│ partitions     │ 分区                                │ 是否分区裁剪             │
│ type           │ 访问类型                            │ 至少 range，避免 ALL     │
│ possible_keys  │ 可能索引                            │ 有值但 key=NULL 需关注   │
│ key            │ 实际索引                            │ 是否用了预期索引         │
│ key_len        │ 索引长度                            │ 复合索引用了几列         │
│ ref            │ 比较来源                            │ const / 列名 / func      │
│ rows           │ 预估行数                            │ 越小越好                 │
│ filtered       │ 过滤百分比                          │ JOIN 时影响驱动表选择    │
│ Extra          │ 额外信息                            │ Using temporary/filesort │
└────────────────┴─────────────────────────────────────┴─────────────────────────┘
```

### 附录 B：慢查询优化 Checklist（50 项）

```
□ 1.  EXPLAIN 查看 type 列，是否至少为 range
□ 2.  EXPLAIN 查看 key 列，是否使用了预期索引
□ 3.  EXPLAIN 查看 rows 列，预估行数是否合理
□ 4.  EXPLAIN 查看 Extra 列，是否有 Using temporary
□ 5.  EXPLAIN 查看 Extra 列，是否有 Using filesort
□ 6.  EXPLAIN 查看 Extra 列，是否有 Using join buffer
□ 7.  key_len 是否复合预期（复合索引是否用满）
□ 8.  WHERE 条件是否满足最左前缀
□ 9.  范围查询是否截断了后续索引列
□ 10. 是否有隐式类型转换（VARCHAR = INT）
□ 11. 是否有函数作用于索引列（DATE(col) = ...）
□ 12. 是否有计算作用于索引列（col + 1 = ...）
□ 13. LIKE 是否有前导通配符（'%xxx'）
□ 14. OR 条件是否导致索引失效
□ 15. != / NOT IN 是否导致索引失效
□ 16. SELECT * 是否可以改为只查需要的列
□ 17. 是否可以使用覆盖索引
□ 18. ORDER BY 是否可以使用索引
□ 19. ORDER BY 排序方向是否一致（ASC/DESC 混合）
□ 20. GROUP BY 是否可以使用索引
□ 21. JOIN 被驱动表的 JOIN 列是否有索引
□ 22. JOIN 驱动表是否选择正确
□ 23. 是否有 DEPENDENT SUBQUERY（子查询每行执行）
□ 24. 子查询是否可以改写为 JOIN
□ 25. UNION 是否可以改为 UNION ALL
□ 26. LIMIT 深分页是否使用延迟关联
□ 27. LIMIT 深分页是否可以使用游标分页
□ 28. COUNT(*) 是否可以维护计数表
□ 29. DISTINCT 是否可以使用覆盖索引
□ 30. 复合索引顺序是否合理（等值在前，范围在后）
□ 31. 是否有冗余索引可以删除
□ 32. 统计信息是否准确（ANALYZE TABLE）
□ 33. 表是否需要优化（OPTIMIZE TABLE）
□ 34. sort_buffer_size 是否合适
□ 35. join_buffer_size 是否合适
□ 36. tmp_table_size 是否合适
□ 37. 是否有大量磁盘临时表（Tmp_disk_tables）
□ 38. Buffer Pool 命中率是否正常
□ 39. 是否有锁等待（Lock_time 过高）
□ 40. 是否可以使用 ICP（索引下推）
□ 41. 是否可以使用 MRR
□ 42. 是否可以使用 Hash Join（8.0+）
□ 43. 是否可以使用 BKA
□ 44. 是否需要使用 FORCE INDEX
□ 45. 是否需要使用 STRAIGHT_JOIN
□ 46. 是否需要调整 optimizer_switch
□ 47. 是否需要使用 optimizer_trace 调试
□ 48. 是否需要使用 EXPLAIN ANALYZE 对比预估值
□ 49. 是否需要分区表
□ 50. 是否需要读写分离 / 分库分表
```

### 附录 C：常用 SQL 性能监控命令速查

```sql
-- 1. 查看当前连接和正在执行的 SQL
SHOW PROCESSLIST;
SHOW FULL PROCESSLIST;

-- 2. 查看服务器状态
SHOW GLOBAL STATUS LIKE 'Slow_queries';
SHOW GLOBAL STATUS LIKE 'Sort_merge_passes';
SHOW GLOBAL STATUS LIKE 'Created_tmp_disk_tables';

-- 3. 查看 InnoDB 状态
SHOW ENGINE INNODB STATUS\G

-- 4. 查看索引使用情况
SELECT object_schema, object_name, index_name,
    count_read, count_fetch
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE object_schema = 'your_db'
ORDER BY count_read DESC;

-- 5. 查看未使用的索引
SELECT * FROM sys.schema_unused_indexes WHERE object_schema = 'your_db';

-- 6. 查看冗余索引
SELECT * FROM sys.schema_redundant_indexes WHERE table_schema = 'your_db';

-- 7. 查看表大小和行数
SELECT table_name, table_rows,
    ROUND(data_length/1024/1024, 2) AS data_mb,
    ROUND(index_length/1024/1024, 2) AS index_mb
FROM information_schema.tables
WHERE table_schema = 'your_db'
ORDER BY (data_length+index_length) DESC;

-- 8. Buffer Pool 命中率
SELECT (1 - Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests) * 100
AS buffer_pool_hit_rate
FROM (
    SELECT
        MAX(IF(Variable_name='Innodb_buffer_pool_reads', VALUE, 0)) AS Innodb_buffer_pool_reads,
        MAX(IF(Variable_name='Innodb_buffer_pool_read_requests', VALUE, 0)) AS Innodb_buffer_pool_read_requests
    FROM performance_schema.global_status
) t;

-- 9. 慢查询 Top 10
SELECT DIGEST_TEXT, COUNT_STAR AS exec_count,
    ROUND(AVG_TIMER_WAIT/1000000000, 2) AS avg_ms,
    ROUND(SUM_TIMER_WAIT/1000000000, 2) AS total_ms
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC LIMIT 10;

-- 10. 查看优化器开关
SHOW VARIABLES LIKE 'optimizer_switch'\G

-- 11. 查看成本模型
SELECT * FROM mysql.server_cost;
SELECT * FROM mysql.engine_cost;

-- 12. 更新统计信息
ANALYZE TABLE users;
```

### 附录 D：与《MySQL 索引底层原理》文档的衔接关系

```
《MySQL 索引底层原理深度解析》
（B+Tree / 页结构 / 聚簇索引 / 最左前缀 / 覆盖索引）
     │
     │  理解了索引的物理结构后
     ▼
《MySQL EXPLAIN 实战 + 慢查询优化深度解析》
（本文档）
（EXPLAIN / 访问类型 / 成本模型 / ORDER BY / JOIN / 慢查询）

两份文档的关系：
- 索引文档讲「索引是怎么设计和存储的」
- 本文讲「优化器如何选择索引、SQL 如何高效使用索引」

对照阅读：
- 索引文档的「最左前缀」↔ 本文的「key_len 列」
- 索引文档的「覆盖索引」↔ 本文的「Using index」
- 索引文档的「回表」↔ 本文的「rows 列 + 回表成本」
- 索引文档的「ICP」↔ 本文的「Using index condition」
- 索引文档的「MRR」↔ 本文的「Using MRR」
- 索引文档的「索引失效」↔ 本文的「案例1-10」
```

---

> **文档总结**
>
> 本文档从 EXPLAIN 12 列逐列解析开始，覆盖了访问类型 8 级、Extra 15 种状态、成本模型、ANALYZE 语句、慢查询日志分析工具、ORDER BY / GROUP BY / LIMIT / JOIN / 子查询优化的底层原理，以及 15 个真实慢查询案例的完整优化过程和优化器 Trace 分析方法。
>
> 建议配合之前的《MySQL 索引底层原理深度解析》一起阅读——索引文档讲索引的物理存储，本文讲如何通过 EXPLAIN 判断索引是否被高效使用。两者结合，才能从"理解索引原理"到"实战优化慢查询"形成完整闭环。