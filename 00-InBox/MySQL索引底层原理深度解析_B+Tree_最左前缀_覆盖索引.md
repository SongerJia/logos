# MySQL 索引底层原理深度解析：B+Tree + 最左前缀 + 覆盖索引

> 本文档系统解析 MySQL（InnoDB）索引的底层实现原理，从数据结构到查询优化，覆盖 B+Tree 源码级实现、页结构、聚簇索引与二级索引、最左前缀匹配、覆盖索引、索引下推（ICP）、MRR、索引统计信息与选择、索引失效场景等。目标：读完此文档后，你能从 InnoDB 源码层面理解索引为什么这样工作。

---

## 目录

```
第一部分：索引基础与数据结构
  1.1 索引是什么——从无索引到有索引的世界
  1.2 InnoDB 整体架构与索引的关系
  1.3 B+Tree 数据结构详解
  1.4 为什么 InnoDB 选择 B+Tree 而不是 B-Tree / Hash / 跳表
  1.5 B+Tree 在 InnoDB 中的源码实现——从 btr0btr.cc 到 page0page.cc

第二部分：InnoDB 页结构——索引的物理存储
  2.1 Page 的基本结构（38 字节 FIL Header + 5 字节 Page Header）
  2.2 Infimum + Supremum 伪记录
  2.3 User Record 与记录头信息（5 字节 Record Header）
  2.4 Page Directory（页目录）——Slot 机制实现页内二分查找
  2.5 Free Space 与碎片整理
  2.6 B+Tree 节点分裂——页分裂的完整过程
  2.7 B+Tree 节点合并——页合并的条件与过程
  2.8 页结构完整图解

第三部分：聚簇索引与二级索引
  3.1 聚簇索引（Clustered Index）——表就是索引，索引就是表
  3.2 二级索引（Secondary Index）——叶子存主键值
  3.3 二级索引的回表查询——为什么要"回表"
  3.4 索引高度计算——一棵 3 层 B+Tree 能存多少行
  3.5 联合索引的结构——多列在 B+Tree 中的排列方式
  3.6 联合索引的排序规则——字符串比较的 collation 影响
  3.7 索引的物理存储——.ibd 文件中的区、段、页

第四部分：最左前缀匹配原理
  4.1 最左前缀是什么——从联合索引的 B+Tree 结构推导
  4.2 全列匹配——索引的完美使用
  4.3 最左前缀匹配——前缀列的等值查询
  4.4 范围查询打破最左前缀——第一个范围列之后的列无法利用索引
  4.5 跳过中间列——索引部分生效
  4.6 列顺序无关——优化器的索引列顺序自动调整
  4.7 最左前缀在 LIKE 中的应用——为什么只有前缀 LIKE 能用索引
  4.8 最左前缀在 ORDER BY 中的应用——索引排序替代 Filesort
  4.9 最左前缀在 GROUP BY 中的应用
  4.10 最左前缀原理总结与速查表

第五部分：覆盖索引
  5.1 覆盖索引的定义——查询的列全部在索引中
  5.2 覆盖索引如何避免回表
  5.3 覆盖索引的 EXPLAIN 标识——Using index
  5.4 覆盖索引的实战场景
  5.5 覆盖索引与 SELECT * 的矛盾
  5.6 覆盖索引与 ORDER BY 的配合
  5.7 覆盖索引与分页查询的优化
  5.8 覆盖索引的限制——不是所有查询都能覆盖

第六部分：索引下推（ICP）与 MRR
  6.1 Index Condition Pushdown（ICP）——把 WHERE 条件下推到存储引擎层
  6.2 ICP 的工作流程——Without ICP vs With ICP 对比
  6.3 ICP 的适用条件
  6.4 ICP 的 EXPLAIN 标识——Using index condition
  6.5 Multi-Range Read（MRR）——二级索引回表的顺序化优化
  6.6 MRR 的工作原理——先排序主键再回表
  6.7 MRR 的适用场景与限制
  6.8 Batched Key Access（BKA）——MRR + join buffer

第七部分：索引统计信息与优化器选择
  7.1 优化器的索引选择流程
  7.2 索引统计信息——SHOW INDEX 的 Cardinality
  7.3 InnoDB 的统计信息采集——persistent vs transient
  7.4 索引选择成本计算——MySQL 8.0 的成本模型
  7.5 紧索引扫描 vs 松索引扫描
  7.6 索引合并（Index Merge）——Intersection / Union / Sort-Union
  7.7 优化器 Trace——OPTIMIZER_TRACE 分析索引选择
  7.8 FORCE INDEX / USE INDEX——绕过优化器的选择

第八部分：索引失效场景全面解析
  8.1 索引失效的 12 种典型场景
  8.2 函数/计算导致索引失效
  8.3 类型转换导致索引失效
  8.4 LIKE 前缀通配符导致索引失效
  8.5 OR 条件导致索引失效
  8.6 NOT IN / NOT EXISTS 导致索引失效
  8.7 范围查询之后的列索引失效
  8.8 索引列顺序颠倒（可被优化器纠正）
  8.9 隐式类型转换的坑——字符串 vs 数字
  8.10 索引选择率太低——全表扫描比索引更快
  9.11 事务隔离级别对索引的影响
  8.12 索引失效速查表

第九部分：InnoDB Buffer Pool 与索引页缓存
  9.1 Buffer Pool 架构——LRU List + Free List + Flush List
  9.2 Buffer Pool 的改进 LRU——冷热分区（old sublist / young sublist）
  9.3 页的读取与预读机制——线性预读与随机预读
  9.4 页的修改与脏页刷盘——Flush List 与刷盘策略
  9.5 Buffer Pool 对索引查询性能的影响
  9.6 Multiple Buffer Pool Instance——并发优化
  9.7 Change Buffer——二级索引的异步变更合并
  9.8 Buffer Pool 配置与监控

第十部分：索引设计原则与实战
  10.1 索引设计的基本原则
  10.2 联合索引列顺序选择——区分度高的列放左边
  10.3 避免冗余索引与重复索引
  10.4 前缀索引——长字符串列的索引优化
  10.5 函数索引——MySQL 8.0 的新特性
  10.6 不可见索引——MySQL 8.0 的安全验证机制
  10.7 索引与 DML 的权衡——索引越多越慢？
  10.8 索引设计 Checklist

附录 A：InnoDB 索引核心源码文件速查
附录 B：索引相关 EXPLAIN 字段完整解读
附录 C：索引相关参数与变量速查
```

---

# 第一部分：索引基础与数据结构

## 1.1 索引是什么——从无索引到有索引的世界

### 无索引的世界：顺序扫描

一张表有 100 万行数据，没有索引。执行：

```sql
SELECT * FROM user WHERE id = 500000;
```

InnoDB 的执行过程：

```
1. 从数据文件的第一页开始
2. 逐页逐行扫描每一行记录
3. 对每行检查 id 是否等于 500000
4. 找到匹配行后返回
5. 扫描完毕，返回结果
```

**代价**：100 万行全部扫描，O(N) 时间复杂度。即使数据在第 50 万行就找到了，InnoDB 也不知道后面还有没有匹配行，所以仍然要扫描完整个表。

### 有索引的世界：B+Tree 定位

有了 `id` 列的主键索引（B+Tree），执行同样的查询：

```
1. 从 B+Tree Root 页开始（第 3 层）
2. Root 页中二分查找 → 找到指向下一层的指针
3. 进入第 2 层的非叶子节点页 → 二分查找 → 找到指向叶子层的指针
4. 进入第 1 层的叶子页 → 二分查找 → 找到 id=500000 的记录
5. 返回结果
```

**代价**：3 次页读取（假设 3 层 B+Tree），O(log N) 时间复杂度。100 万行数据只需 3 次 I/O。

### 索引的本质

**索引 = 一种有序的数据结构，用于加速查找。**

类比：
- 无索引 = 在一本没有目录的书里逐页翻找关键词
- 有索引 = 先翻目录找到关键词对应的页码，再翻到那一页

---

## 1.2 InnoDB 整体架构与索引的关系

### InnoDB 存储引擎架构

```
                        ┌─────────────────────────────────────────┐
                        │           InnoDB Storage Engine          │
                        ├─────────────────────────────────────────┤
                        │                                         │
  ┌──────────┐          │   ┌─────────────────────────────────┐   │
  │ Client   │──────────│──→│        Buffer Pool              │   │
  │ (SQL)    │          │   │  ┌────────┐ ┌────────┐ ┌─────┐ │   │
  └──────────┘          │   │  │Data Page│ │Index   │ │Change│ │   │
                        │   │  │  (LRU) │ │Page    │ │Buffer│ │   │
                        │   │  └────────┘ └────────┘ └─────┘ │   │
                        │   └─────────────────────────────────┘   │
                        │                                         │
                        │   ┌──────────────┐ ┌──────────────┐     │
                        │   │ Log System   │ │  Lock System  │     │
                        │   │(Redo/Undo)   │ │ (Row Lock/   │     │
                        │   │              │ │  MVCC)       │     │
                        │   └──────────────┘ └──────────────┘     │
                        │                                         │
                        │   ┌─────────────────────────────────┐   │
                        │   │      B+Tree Index Engine         │   │
                        │   │  ┌──────────┐ ┌──────────────┐ │   │
                        │   │  │Clustered │ │ Secondary    │ │   │
                        │   │  │Index     │ │ Index        │ │   │
                        │   │  │(数据页)   │ │ (二级索引页) │ │   │
                        │   │  └──────────┘ └──────────────┘ │   │
                        │   └─────────────────────────────────┘   │
                        │                                         │
                        │   ┌─────────────────────────────────┐   │
                        │   │       File Space Management      │   │
                        │   │  Segment → Extent → Page → Row  │   │
                        │   └─────────────────────────────────┘   │
                        └─────────────────────────────────────────┘
                                     │
                                     ▼
                        ┌─────────────────────────────────┐
                        │        .ibd File (Disk)          │
                        │  ┌──────┐  ┌──────┐  ┌──────┐   │
                        │  │Page1 │  │Page2 │  │PageN │   │
                        │  │16KB  │  │16KB  │  │16KB  │   │
                        │  └────────────────────────────── │
                        └─────────────────────────────────┘
```

**关键关系**：

- **索引 = B+Tree**：InnoDB 中每个索引就是一棵 B+Tree
- **聚簇索引的叶子节点 = 数据行**：表的数据行存储在聚簇索引的叶子页中
- **二级索引的叶子节点 = 主键值 + 索引列值**：二级索引叶子不存完整数据行
- **.ibd 文件 = 表空间**：一棵 B+Tree 的所有页存储在 .ibd 文件中

---

## 1.3 B+Tree 数据结构详解

### B+Tree 的定义

B+Tree 是 B-Tree 的变体，与 B-Tree 的核心区别：

| 特性 | B-Tree | B+Tree |
|------|--------|--------|
| 数据存储位置 | 所有节点（叶子+非叶子）都存数据 | **只有叶子节点存数据** |
| 非叶子节点内容 | 键 + 数据 + 子节点指针 | **只有键 + 子节点指针** |
| 叶子节点链接 | 无 | **叶子节点通过双向链表连接** |
| 查找路径 | 在非叶子节点就可能找到数据 | **必须走到叶子节点才找到数据** |
| 范围查询 | 需要中序遍历整棵树 | **沿叶子链表顺序扫描即可** |

### B+Tree 的结构图

一棵 3 层 B+Tree（假设每个非叶子节点能存 1000 个键）：

```
                    ┌─── Root (Level 3) ───┐
                    │ 1 | 1001 | 2001 | ... │   ← 只存键值 + 子节点指针
                    └─┬─────┬──────┬─────┬──┘
                      │     │      │     │
          ┌───────────┘     │      │     └───────────┐
          ▼                 ▼      ▼                  ▼
   ┌─ Level 2 ──┐   ┌─ Level 2 ──┐   ┌─ Level 2 ──┐
   │1|2|3|...|  │   │1001|1002|..│   │2001|2002|..│   ← 只存键值 + 子节点指针
   │1000        │   │2000        │   │3000        │
   └─┬──┬──┬──┘   └─┬──┬──┬──┘   └─┬──┬──┬──┘
     │  │  │        │  │  │        │  │  │
     ▼  ▼  ▼        ▼  ▼  ▼        ▼  ▼  ▼
  ┌─────────┐    ┌─────────┐    ┌─────────┐
  │Leaf Page│    │Leaf Page│    │Leaf Page│   ← 存完整数据行（聚簇索引）
  │(1-10)   │←──→│(11-20)  │←──→│(21-30)  │←──→ ...  ← 双向链表
  │数据行   │    │数据行   │    │数据行   │
  └─────────┘    └─────────┘    └─────────┘
```

### B+Tree 的核心参数

InnoDB 中 B+Tree 的关键参数：

```
页大小（Page Size） = 16KB（默认，innodb_page_size）
非叶子节点存储     = 键值 + 子节点指针（Page Directory 指针）
叶子节点存储       = 完整数据行（聚簇索引）或 索引列值+主键值（二级索引）
节点最大键数       = 页大小 / (键值大小 + 指针大小)
最小填充率         = 50%（节点最少有一半的键，B+Tree 定义要求）
分裂时机           = 页满时（超过页容量的阈值）
合并时机           = 页使用率低于 MERGE_THRESHOLD（默认 50%）
```

### B+Tree 的查找过程

**点查（Point Query）**：`WHERE id = 500000`

```
Step 1: 加载 Root 页（Page 3，Level 2）
  → 页内二分查找 500000
  → 500000 在键 [1, 1001] 之间 → 5 < 500000 < 1001
  → 跟随指针到 Level 1 的中间节点

Step 2: 加载 Level 1 非叶子页（Page 5）
  → 页内二分查找 500000
  → 500000 在键 [400001, 500001] 之间
  → 跟随指针到 Level 0 的叶子页

Step 3: 加载 Level 0 叶子页（Page 100）
  → 页内通过 Page Directory Slot 先粗定位
  → 再在 Slot 范围内线性/二分精查找
  → 找到 id=500000 的记录 → 返回数据行
```

**范围查询（Range Query）**：`WHERE id BETWEEN 500000 AND 500100`

```
Step 1: 先通过点查定位 id=500000 的叶子页
Step 2: 从该叶子页开始，沿叶子链表向后扫描
Step 3: 逐页读取，直到 id > 500100 时停止
```

**范围查询的优势**：B+Tree 叶子节点的双向链表使得范围查询只需先定位起点，然后顺序扫描链表即可，无需回溯到根节点重新查找。

---

## 1.4 为什么 InnoDB 选择 B+Tree 而不是 B-Tree / Hash / 跳表

### B+Tree vs B-Tree

| 对比维度 | B-Tree | B+Tree |
|----------|--------|--------|
| 非叶子节点空间利用率 | 低（每个节点都存数据，空间浪费） | **高（非叶子只存键，一个页能存更多键）** |
| 树的高度 | 更高（每个节点存数据，键数少） | **更低（非叶子只存键，叉数更大）** |
| 范围查询 | 需要中序遍历（O(N) 但要反复回溯） | **沿叶子链表顺序扫描（O(K)）** |
| 查询稳定性 | 不稳定（可能在非叶子就命中） | **稳定（始终走到叶子，路径长度一致）** |
| I/O 次数 | 更多（树更高） | **更少（树更矮）** |

**核心优势**：B+Tree 非叶子节点不存数据 → 一个 16KB 页能存更多键 → 叉数更大 → 树更矮 → I/O 更少。

计算对比（假设键 8 字节，指针 6 字节，数据行 1KB）：

```
B-Tree 非叶子节点：
  一个 16KB 页能存：16KB / (8B + 6B + 1KB) ≈ 15 个键
  3 层 B-Tree 最多存：15 × 15 × 15 = 3375 行

B+Tree 非叶子节点：
  一个 16KB 页能存：16KB / (8B + 6B) ≈ 1170 个键
  3 层 B+Tree 最多存：1170 × 1170 × 叶子页行数
  叶子页行数 ≈ 16KB / 1KB ≈ 16 行
  总计：1170 × 1170 × 16 ≈ 2190 万行！
```

### B+Tree vs Hash

| 对比维度 | Hash 索引 | B+Tree 索引 |
|----------|-----------|-------------|
| 等值查询 | O(1) 极快 | O(log N) |
| 范围查询 | **不支持**（Hash 值无序） | **支持**（叶子链表顺序扫描） |
| 排序 | **不支持** | **支持**（索引本身有序） |
| 最左前缀 | **不支持** | **支持** |
| 等值冲突 | 性能退化（链表扫描） | 不受影响 |

**结论**：Hash 索引只适合等值查询（如 Memory 引擎的 Hash 索引），不适合数据库的通用索引。

### B+Tree vs 跳表

| 对比维度 | 跳表 | B+Tree |
|----------|------|--------|
| 查询复杂度 | O(log N) | O(log N) |
| 范围查询 | 支持（沿链表扫描） | 支持（沿叶子链表） |
| 磁盘友好度 | **差**（节点分散，I/O 多） | **好**（页式存储，一个页一次 I/O） |
| 并发控制 | CAS 无锁 | 页锁 / 乐观锁 |
| 空间利用率 | 不稳定（随机层数） | **稳定（保证 ≥ 50%）** |

**结论**：跳表适合内存数据结构（如 Redis 的 ZSET），B+Tree 适合磁盘数据结构（以页为单位 I/O）。

### 最终选择原因

```
InnoDB 选择 B+Tree 的三大核心原因：

1. 磁盘 I/O 优化：B+Tree 的页式存储与磁盘块对齐，一次 I/O 读取一个完整页
   → 非叶子只存键 → 叉数大 → 树矮 → I/O 少（3 层存 2190 万行）

2. 范围查询优化：叶子链表使得范围查询变为顺序扫描
   → 数据库 90% 的查询是范围查询，这是最关键的优化

3. 空间利用率保证：B+Tree 节点分裂保证至少 50% 填充率
   → 空间浪费可控，不会出现跳表的随机空洞
```

---

## 1.5 B+Tree 在 InnoDB 中的源码实现——从 btr0btr.cc 到 page0page.cc

### InnoDB B+Tree 源码核心文件

InnoDB 的 B+Tree 实现分布在多个源码文件中：

```
存储引擎层（storage/innobase/）

B+Tree 操作：
  btr0btr.cc    — B+Tree 的查找、插入、删除、分裂、合并
  btr0cur.cc    — B+Tree 游标（cursor）操作
  btr0pcur.cc   — B+Tree 持久游标（persistent cursor）

页操作：
  page0page.cc  — 页内记录操作（插入记录、删除记录、页目录维护）
  page0cur.cc   — 页内游标操作

索引字典：
  dict0dict.cc  — 索引字典（dict_index_t 结构定义）
  dict0mem.cc   — 索引内存结构管理

锁与并发：
  lock0lock.cc  — 行锁与 Next-Key Lock
  buf0buf.cc    — Buffer Pool 页管理（页的读取、修改、刷盘）
```

### dict_index_t — 索引的核心数据结构

```c
// storage/innobase/include/dict0mem.h

struct dict_index_t {
    dict_table_t*   table;          // 所属的表
    const char*     name;           // 索引名称（"PRIMARY" 或自定义名）
    ulint           space;          // 表空间 ID
    ulint           id;             // 索引 ID
    ulint           n_fields;       // 索引包含的列数
    ulint           n_unique;       // 唯一列数（唯一索引前几列唯一）
    dict_field_t*   fields;         // 索引列数组
    page_size_t     page_size;      // 页大小（16KB）
    ulint           root_page_no;   // B+Tree 的根页号（通常是 3 或 4）
    bool            is_clustered;   // 是否是聚簇索引
    bool            is_unique;      // 是否是唯一索引
    bool            is_auto_inc;    // 是否包含自增列
    
    // 线上信息
    ulint           stat_n_rows;    // 估算的行数（用于统计信息）
    ulint           stat_n_leaf_pages; // 叶子页数
};
```

**关键字段解析**：

- `root_page_no`：每棵 B+Tree 的根页号。聚簇索引的根页号固定在表空间的第 3 页（`SYS_INDEXES` 系统表中记录），二级索引的根页号在创建索引时分配
- `n_fields`：索引包含的列数。联合索引 `(a, b, c)` 的 n_fields = 3
- `n_unique`：唯一索引的唯一列数。唯一索引 `(a, b)` 的 n_unique = 2
- `is_clustered`：聚簇索引和二级索引的区别标志

### btr_cur_search_to_nth_level — B+Tree 查找的入口函数

```c
// storage/innobase/btr/btr0cur.cc

void btr_cur_search_to_nth_level(
    dict_index_t*   index,      // 索引对象
    ulint           level,      // 目标层级（0 = 叶子层）
    const dtuple_t* tuple,      // 查找的键值 tuple
    page_cur_mode_t mode,       // 查找模式（<= / < / = / >= / >）
    ulint           latch_mode, // 锁模式（RW_LOCK_SHARED / RW_LOCK_EX）
    btr_cur_t*      cursor,     // 输出：游标位置
    ulint           has_search_latch,
    const char*     file,       // 调用文件名（用于调试）
    ulint           line        // 调用行号
)
{
    page_t*     page;           // 当前页
    page_cur_t  page_cursor;    // 页内游标
    ulint       page_no;        // 当前页号
    ulint       space;          // 表空间 ID
    ulint       up_node;        // 父节点中的位置
    ulint       up_page_no;     // 父页号
    
    space = index->space;
    page_no = index->root_page_no;  // 从根页开始
    
    // 从根页向下逐层查找
    while (level > 0) {
        // 1. 从 Buffer Pool 获取页
        page = buf_page_get_gen(space, page_size, page_no,
                                RW_LOCK_SHARED, ...);
        
        // 2. 在页内查找匹配的键
        page_cur_search(page, tuple, mode, &page_cursor);
        
        // 3. 获取子节点指针
        node_ptr = page_cur_get_rec(&page_cursor);
        page_no = btr_node_ptr_get_child_page_no(node_ptr);
        
        // 4. 释放当前页的 latch
        buf_page_release(page, ...);
        
        level--;  // 下一层
    }
    
    // 到达目标层（叶子层）
    page = buf_page_get_gen(space, page_size, page_no,
                            latch_mode, ...);
    page_cur_search(page, tuple, mode, &cursor->page_cur);
    
    cursor->index = index;
    cursor->block = ...; // 页块
}
```

**查找流程图解**：

```
  btr_cur_search_to_nth_level(index, level=0, tuple={id=500000})
  
  ┌──────────────────────────────────────────────────────┐
  │  Level 2 (Root Page 3)                               │
  │  page_cur_search: 二分查找 tuple 在页中的位置        │
  │  → 找到子节点指针 → page_no = 5                     │
  └──────────────┬───────────────────────────────────────┘
                 │  buf_page_get: 加载 Page 5
                 ▼
  ┌──────────────────────────────────────────────────────┐
  │  Level 1 (Page 5)                                    │
  │  page_cur_search: 二分查找 tuple 在页中的位置        │
  │  → 找到子节点指针 → page_no = 100                   │
  └──────────────┬───────────────────────────────────────┘
                 │  buf_page_get: 加载 Page 100
                 ▼
  ┌──────────────────────────────────────────────────────┐
  │  Level 0 (Leaf Page 100)                             │
  │  page_cur_search: 在叶子页中找到 id=500000 的记录   │
  │  → cursor 定位到该记录位置                           │
  └──────────────────────────────────────────────────────┘
```

### page_cur_search — 页内查找的核心实现

```c
// storage/innobase/page/page0cur.cc

void page_cur_search(
    const page_t*       page,       // 当前页
    const dtuple_t*     tuple,      // 查找键值
    page_cur_mode_t     mode,       // 查找模式
    page_cur_t*         cursor      // 输出游标
)
{
    ulint   n_records;      // 页内记录数
    ulint   up_lim;         // 上界
    ulint   low_lim;        // 下界
    ulint   mid;            // 中间位置
    int     cmp;            // 比较结果
    
    // 如果页有 Page Directory（Slot）
    if (page_dir_get_n_slots(page) > 0) {
        // 先通过 Page Directory 粗定位
        up_lim  = page_dir_find_owner_slot(page, ...);
        low_lim = PAGE_INFIMUM + 1;
        
        // 在 Slot 范围内线性/二分精查找
        // ...
    }
    
    // 标准二分查找
    n_records = page_get_n_recs(page);
    up_lim  = n_records - 1;
    low_lim = 0;
    
    while (low_lim <= up_lim) {
        mid = (low_lim + up_lim) / 2;
        rec = page_get_rec(page, mid);
        
        cmp = cmp_dtuple_rec(tuple, rec, index);
        
        if (cmp == 0) {
            // 找到精确匹配
            break;
        } else if (cmp < 0) {
            up_lim = mid - 1;  // tuple < rec
        } else {
            low_lim = mid + 1; // tuple > rec
        }
    }
    
    page_cur_position(rec, page, cursor);
}
```

---

# 第二部分：InnoDB 页结构——索引的物理存储

## 2.1 Page 的基本结构

InnoDB 的 B+Tree 每个**节点就是一个 Page（页）**，大小默认 **16KB**。

一个 Page 的整体结构：

```
┌──────────────────────────────────────────────────────┐
│                   InnoDB Page (16KB)                  │
├──────────────────────────────────────────────────────┤
│                                                      │
│  ┌──────────── FIL Header (38 Bytes) ────────────┐  │
│  │ FIL_PAGE_SPACE_OR_CHK  (4B) — 表空间ID/校验   │  │
│  │ FIL_PAGE_OFFSET        (4B) — 页号（0,1,2..） │  │
│  │ FIL_PAGE_PREV          (4B) — 前一页号        │  │
│  │ FIL_PAGE_NEXT          (4B) — 后一页号        │  │
│  │ FIL_PAGE_LSN           (8B) — 最后修改LSN     │  │
│  │ FIL_PAGE_TYPE          (2B) — 页类型          │  │
│  │ FIL_PAGE_FILE_FLUSH_LSN(8B) — 文件刷盘LSN    │  │
│  │ FIL_PAGE_ARCH_LOG_NO   (8B) — 归档日志号      │  │
│  └─────────────────────────────────────────────────┘  │
│                                                      │
│  ┌──────────── Page Header (56 Bytes) ────────────┐  │
│  │ PAGE_N_DIR_SLOTS   (2B) — Page Directory Slot数│ │
│  │ PAGE_HEAP_TOP      (2B) — 堆顶位置（空闲起始） │ │
│  │ PAGE_N_HEAP        (2B) — 堆中记录数（含2伪记录）│ │
│  │ PAGE_FREE          (2B) — 空闲链表头位置       │  │
│  │ PAGE_GARBAGE       (2B) — 可重用空间大小       │  │
│  │ PAGE_LAST_INSERT   (2B) — 最后插入位置        │  │
│  │ PAGE_DIRECTION     (2B) — 插入方向（左/右/无） │ │
│  │ PAGE_N_DIRECTION   (2B) — 同方向连续插入数    │  │
│  │ PAGE_N_RECS        (2B) — 用户记录数          │  │
│  │ PAGE_MAX_TRX_ID    (8B) — 修改该页的最大事务ID│ │
│  │ PAGE_LEVEL         (2B) — 页层级（0=叶子）    │  │
│  │ PAGE_INDEX_ID      (8B) — 索引ID              │  │
│  └─────────────────────────────────────────────────┘  │
│                                                      │
│  ┌──────────── Infimum + Supremum (26 Bytes) ────┐  │
│  │ Infimum  伪记录 — "比所有用户记录都小"        │  │
│  │ Supremum 伪记录 — "比所有用户记录都大"        │  │
│  └─────────────────────────────────────────────────┘  │
│                                                      │
│  ┌──────────── User Records (变长) ──────────────┐  │
│  │ Record 1: [Record Header] + [列数据]          │  │
│  │ Record 2: [Record Header] + [列数据]          │  │
│  │ ...                                            │  │
│  │ Record N: [Record Header] + [列数据]          │  │
│  └─────────────────────────────────────────────────┘  │
│                                                      │
│  ┌──────────── Free Space (变长) ─────────────────┐  │
│  │ 未使用的空间，新记录从这里分配                  │  │
│  └─────────────────────────────────────────────────┘  │
│                                                      │
│  ┌──────────── Page Directory (变长) ─────────────┐  │
│  │ Slot 0: 指向 Supremum                          │  │
│  │ Slot 1: 指向某条用户记录（每隔4-8条一个Slot） │  │
│  │ Slot 2: 指向某条用户记录                       │  │
│  │ ...                                            │  │
│  │ Slot N: 指向 Infimum                           │  │
│  └─────────────────────────────────────────────────┘  │
│                                                      │
│  ┌──────────── FIL Trailer (8 Bytes) ─────────────┐  │
│  │ FIL_PAGE_END_LSN    (4B) — 页末LSN（校验用） │  │
│  │ FIL_PAGE_SPACE_OR_CHK(4B) — 校验和           │  │
│  └─────────────────────────────────────────────────┘  │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### FIL Header 关键字段

| 字段 | 大小 | 说明 |
|------|------|------|
| `FIL_PAGE_OFFSET` | 4B | 页号，在表空间中的偏移量。Page 0 = FSP Header，Page 1 = IBUF Bitmap，Page 2 = INODE，Page 3 = 聚簇索引 Root |
| `FIL_PAGE_PREV` | 4B | **B+Tree 叶子节点的前一页号**（叶子链表的 prev 指针） |
| `FIL_PAGE_NEXT` | 4B | **B+Tree 叶子节点的后一页号**（叶子链表的 next 指针） |
| `FIL_PAGE_TYPE` | 2B | 页类型：`FIL_PAGE_INDEX`（索引数据页）、`FIL_PAGE_INODE`（索引节点段描述）、`FIL_PAGE_FSP_HDR`（表空间头）等 |

**注意**：`FIL_PAGE_PREV` 和 `FIL_PAGE_NEXT` 就是 B+Tree 叶子链表的双向指针！

### Page Header 关键字段

| 字段 | 大小 | 说明 |
|------|------|------|
| `PAGE_LEVEL` | 2B | **页层级**：0 = 叶子层，1 = 叶子上一层，...根页 level 最大 |
| `PAGE_N_RECS` | 2B | 页内用户记录数（不含 Infimum 和 Supremum） |
| `PAGE_HEAP_TOP` | 2B | 堆顶位置：已用空间的末尾，新记录从这里开始分配 |
| `PAGE_FREE` | 2B | 空闲链表头：删除的记录组成链表，可重用 |
| `PAGE_GARBAGE` | 2B | 已删除记录占用的总字节数（碎片空间） |
| `PAGE_N_DIR_SLOTS` | 2B | Page Directory 的 Slot 数量 |

---

## 2.2 Infimum + Supremum 伪记录

每个页都有两条**伪记录（Pseudo Record）**，它们不存储任何用户数据，作用是界定页内记录的范围：

```
页内记录排列（按键值从小到大）：

┌──────────┐    ┌───────┐    ┌───────┐    ┌───────┐    ┌──────────┐
│ Infimum  │───→│Rec 1  │───→│Rec 2  │───→│Rec N  │───→│Supremum  │
│(最小伪记录)│    │id=1   │    │id=2   │    │id=N   │    │(最大伪记录)│
└──────────┘    └───────┘    └───────┘    └───────┘    └──────────┘

Infimum:  "比页内所有用户记录都小"
  → 5字节Record Header + 内容 "infimum" + 1字节长度
  → 总大小 13 字节（含 5B Header）

Supremum: "比页内所有用户记录都大"
  → 5字节Record Header + 内容 "supremum" + 1字节长度
  → 总大小 13 字节（含 5B Header）
```

**伪记录的作用**：

1. **二分查找的边界**：页内二分查找时，Infimum 是下界，Supremum 是上界
2. **链表的首尾**：页内记录组成链表，Infimum 是链表头，Supremum 是链表尾
3. **空页也能查找**：即使页内没有用户记录，Infimum → Supremum 的链表仍然存在

---

## 2.3 User Record 与记录头信息

每条用户记录的结构：

```
┌───────────────────────────────────────────────────────────┐
│                    User Record 结构                        │
├──────────┬────────────────────────────────────────────────┤
│          │                                                │
│ Record   │  ┌──────────── 5 Bytes ──────────────┐       │
│ Header   │  │ next_rec_off (2B) — 下一条记录偏移  │       │
│ (5B)     │  │ delete_flag   (1bit)— 删除标记      │       │
│          │  │ min_rec_flag  (1bit)— 非叶子最小记录 │       │
│          │  │ n_owned       (4bit)— 该记录"拥有"   │       │
│          │  │                        的记录数     │       │
│          │  │ heap_no       (13bit)— 堆中序号     │       │
│          │  │ record_type   (3bit)— 记录类型       │       │
│          │  │                        (0=常规,1=   │       │
│          │  │                        节点指针,    │       │
│          │  │                        2=Infimum,   │       │
│          │  │                        3=Supremum)  │       │
│          │  │ info_flag     (1bit)— 1=变长列存在  │       │
│          │  └─────────────────────────────────────┘       │
│          │                                                │
│          │  ┌──────────── Hidden Columns ─────────┐      │
│          │  │ DB_TRX_ID  (6B) — 最后修改的事务ID   │      │
│          │  │ DB_ROLL_PTR(7B) — 回滚指针（Undo Log）│      │
│          │  └─────────────────────────────────────┘      │
│          │                                                │
│          │  ┌──────────── User Columns ────────────┐      │
│          │  │ 列1数据  列2数据  ...  列N数据       │      │
│          │  └─────────────────────────────────────┘      │
│          │                                                │
└──────────┴────────────────────────────────────────────────┘
```

### Record Header 5 字节详细解析

```c
// 记录头信息存储在记录的前5字节中（紧凑格式）

// 字节1-2：next_rec_off（下一记录偏移量）
//   值 = 下一记录与本记录的偏移字节数（负数表示前一记录）
//   这是页内链表的"next指针"

// 字节3的部分位：
//   delete_flag (1 bit)：1 = 已删除（在 PAGE_FREE 链表中）
//   min_rec_flag (1 bit)：1 = 该页在 B+Tree 非叶子层中的最小记录

// 字节3-5的部分位：
//   n_owned (4 bit)：该记录"拥有"多少条连续记录（用于 Page Directory）
//   heap_no (13 bit)：记录在堆中的序号（Infimum=0, Supremum=1, 用户从2开始）
//   record_type (3 bit)：0=常规记录, 1=B+Tree节点指针, 2=Infimum, 3=Supremum
```

**n_owned 机制**（与 Page Directory 配合）：

```
假设页内有 20 条记录（含 Infimum 和 Supremum），Page Directory 如下：

Slot 4 (Supremum):  n_owned = 5 → Supremum "拥有" 它前面 4 条记录
Slot 3:            n_owned = 4 → Slot 3 的记录 "拥有" 它前面 3 条记录
Slot 2:            n_owned = 4 → Slot 2 的记录 "拥有" 它前面 3 条记录
Slot 1:            n_owned = 4 → Slot 1 的记录 "拥有" 它前面 3 条记录
Slot 0 (Infimum):  n_owned = 1 → Infimum 只 "拥有" 自己
                                          ──
                                    Total = 5+4+4+4+1+4+4 = 20 ✓

规则：每个 Slot 的记录的 n_owned 表示从上一个 Slot 到本 Slot 之间的记录数
      （含本 Slot 对应的记录自己）
      InnoDB 保证每个 Slot 之间间隔 4-8 条记录
```

---

## 2.4 Page Directory（页目录）——Slot 机制实现页内二分查找

### Page Directory 的结构

Page Directory 位于页的末尾（FIL Trailer 之前），由一系列 **Slot** 组成：

```
Page Directory 示例（页末尾区域）：

┌───────────────────────────────────┐
│ Slot 0 → Infimum  位置 (offset)  │   ← 固定：永远指向 Infimum
│ Slot 1 → Record 4  位置          │   ← 每4-8条记录设一个Slot
│ Slot 2 → Record 8  位置          │
│ Slot 3 → Record 12 位置          │
│ Slot 4 → Supremum 位置           │   ← 固定：永远指向 Supremum
└───────────────────────────────────┘

Slot 从页末尾向页头增长（新 Slot 从后往前分配）
每个 Slot 占 2 字节（存储记录在页内的偏移量）
```

### 页内查找的两阶段过程

**阶段一：Slot 粗定位（二分查找 Slot）**

```
目标：找到 id=7 的记录

Slot 数组：[Infimum, Rec4, Rec8, Rec12, Supremum]
  → Slot[0] 的键 = 最小
  → Slot[1] 的键 = 4
  → Slot[2] 的键 = 8
  → Slot[3] 的键 = 12
  → Slot[4] 的键 = 最大

二分查找：id=7 在 Slot[1](4) 和 Slot[2](8) 之间
  → 粗定位范围：Record 4 到 Record 8 之间的记录
```

**阶段二：Slot 范围内线性/二分精查找**

```
在 Record 4 到 Record 8 之间逐一比较（最多 4-8 条）
  → 找到 id=7 的记录
```

**为什么不用全页二分查找？**

因为页内记录不是定长的（变长列导致记录大小不同），无法像数组一样直接计算中间位置。Slot 提供了"定长的索引点"，可以在 Slot 上做二分查找，然后在 Slot 之间的少量记录中线性查找。

### Page Directory 源码

```c
// storage/innobase/page/page0dir.cc

// 获取 Slot 指向的记录
rec_t* page_dir_get_nth_rec(
    const page_t*  page,    // 页
    ulint          n        // Slot 编号
)
{
    // Slot 数组在页末尾，从后向前排列
    ulint   slot_offset = page_dir_get_nth_slot_offset(page, n);
    return(page + slot_offset);  // 返回 Slot 对应的记录指针
}

// 创建新 Slot（当 n_owned > 8 时分裂）
void page_dir_split_slot(
    page_t*     page,       // 页
    ulint       slot_no     // 要分裂的 Slot 编号
)
{
    // 找到该 Slot 的记录
    rec_t*  rec = page_dir_get_nth_rec(page, slot_no);
    
    // 在该 Slot 范围的中间记录处新建一个 Slot
    // 将 n_owned 从原来的值分成两部分
    // ...
}
```

---

## 2.5 Free Space 与碎片整理

### 页内空间分布

```
┌──────────────────────────────────────────────────────┐
│ Page 内部空间划分                                     │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │ FIL Header (38B) + Page Header (56B)         │    │
│  │ = 固定头部 94 字节                            │    │
│  └──────────────────────────────────────────────┘    │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │ Infimum + Supremum = 固定 26 字节            │    │
│  └──────────────────────────────────────────────┘    │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │ User Records = 从 HEAP_TOP 向下增长          │    │
│  │   新记录从 PAGE_HEAP_TOP 处分配              │    │
│  │   → HEAP_TOP 向前移动                        │    │
│  └──────────────────────────────────────────────┘    │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │ Free Space = HEAP_TOP 到 Page Directory 之间 │    │
│  │   可用空间 = PAGE_HEAP_TOP 到 Page Dir 末尾 │    │
│  └──────────────────────────────────────────────┘    │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │ Page Directory = 从页末尾向前增长             │    │
│  │   新 Slot 从末尾分配                          │    │
│  └──────────────────────────────────────────────┘    │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │ FIL Trailer = 固定 8 字节                     │    │
│  └──────────────────────────────────────────────┘    │
│                                                      │
│  已删除记录空间（PAGE_FREE 链表 + PAGE_GARBAGE）     │
│   删除记录不立即释放，而是加入 PAGE_FREE 链表        │
│   → 新记录可以重用这些空间（大小匹配时）              │
│   → 不匹配时成为碎片（PAGE_GARBAGE）                 │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### 碎片整理（Page Compaction / Defragmentation）

当页内碎片过多时，InnoDB 会进行页内碎片整理：

```c
// storage/innobase/page/page0page.cc

void page_compact(
    page_t*     page,       // 需要整理的页
    dict_index_t* index     // 索引
)
{
    // 1. 从 Infimum 开始，沿 next 指针遍历所有存活记录
    // 2. 将存活记录依次紧凑排列（消除碎片间隙）
    // 3. 更新每条记录的 next_rec_off
    // 4. 更新 Page Directory（重新分配 Slot）
    // 5. 更新 PAGE_HEAP_TOP（堆顶前移）
    // 6. 清空 PAGE_FREE 链表和 PAGE_GARBAGE
}
```

---

## 2.6 B+Tree 节点分裂——页分裂的完整过程

### 分裂触发条件

当插入一条记录，目标页的**剩余空间不足**时，触发页分裂：

```c
// storage/innobase/btr/btr0btr.cc

// 判断是否需要分裂
if (page_get_free_space_of_all(page) < rec_size) {
    // 空间不足 → 需要分裂
    btr_page_split_and_insert(index, cursor, ...);
}
```

### 页分裂的完整过程

**场景**：在 Leaf Page A 中插入 id=15，但 Page A 已满。

```
分裂前：
  ┌─────────────────────────────────┐
  │ Page A (已满)                   │
  │ [10, 11, 12, 13, 14, 16, 17, 18]│
  └─────────────────────────────────┘

Step 1: 创建新页 Page B
  → 在表空间中分配一个新页（FSP_ALLOCATE_FREE_PAGE）

Step 2: 确定分裂点（Split Point）
  → InnoDB 默认从页中间分裂（中点分裂）
  → 或根据插入位置分裂（优化频繁插入场景）
  
  中点分裂：Page A 有 8 条记录 → 分裂点 = 第 4 条记录 (id=14)
  
  插入位置分裂：如果插入在页的前半部分 → 从中点分裂
                如果插入在页的后半部分 → 从插入位置分裂

Step 3: 将分裂点之后的记录移到 Page B
  ┌──────────────────────┐    ┌──────────────────────┐
  │ Page A (分裂后)      │    │ Page B (新页)        │
  │ [10, 11, 12, 13, 14] │←──→│ [16, 17, 18]        │
  └──────────────────────┘    └──────────────────────┘

Step 4: 更新父节点
  → 在父节点中插入 Page B 的最小键 (id=16) 和 Page B 的指针
  → 父节点原指向 Page A 的指针保持不变

  父节点（分裂前）：
  │ ... | id=10 → Page A | id=20 → Page C | ...

  父节点（分裂后）：
  │ ... | id=10 → Page A | id=16 → Page B | id=20 → Page C | ...

Step 5: 更新叶子链表
  → Page A.FIL_PAGE_NEXT = Page B 的页号
  → Page B.FIL_PAGE_PREV = Page A 的页号
  → Page B.FIL_PAGE_NEXT = 原来 Page A.FIL_PAGE_NEXT 的值
  → 原 Page A 后一页的 FIL_PAGE_PREV = Page B 的页号

Step 6: 在分裂后的目标页（Page A 或 Page B）中插入新记录
  → id=15 在 Page A 和 Page B 之间 → 插入到 Page B
  → Page B: [15, 16, 17, 18]
```

### 分裂的类型

```
1. 中点分裂（Mid Split）：
   → 页内一半记录留在原页，一半移到新页
   → 保证分裂后两个页至少 50% 填充率
   → 适用于随机插入场景

2. 插入位置分裂（Insert Point Split）：
   → 从插入位置分裂，前半部分留在原页
   → 后半部分移到新页
   → 适用于顺序插入（自增主键）场景
   → 避免每次分裂都只在新页留一条记录的"低填充率问题"

3. InnoDB 的实际策略：
   → 如果插入位置在页的前半部分 → 中点分裂
   → 如果插入位置在页的后半部分 → 从插入位置分裂
   → 源码：btr0btr.cc 中的 btr_page_get_split_rec()
```

### 分裂对性能的影响

```
页分裂的成本：

1. 数据移动：原页一半记录需要拷贝到新页（I/O + CPU）
2. 父节点更新：需要在父节点中插入一个新键（可能触发父节点分裂 → 递归）
3. 链表更新：3 个页的 prev/next 指针需要更新
4. 空间浪费：分裂后每个页可能只有 50% 填充率
5. 锁开销：分裂期间需要持有多个页的 X-Latch

优化建议：
  → 自增主键：顺序插入不触发分裂（新记录总是在页末尾，页满后顺序分裂到新页）
  → 随机主键（UUID）：频繁分裂 → 页填充率低 → 索引碎片多 → 性能差
```

---

## 2.7 B+Tree 节点合并——页合并的条件与过程

### 合并触发条件

当删除记录导致页的**使用率低于 MERGE_THRESHOLD**（默认 50%）时，尝试与相邻页合并：

```c
// storage/innobase/btr/btr0btr.cc

// InnoDB 8.0 引入了 MERGE_THRESHOLD 参数
#define BTR_MERGE_THRESHOLD  50  // 默认 50%

// 判断是否需要合并
if (page_get_used_space_ratio(page) < BTR_MERGE_THRESHOLD) {
    // 尗试与左兄弟或右兄弟合并
    btr_page_merge(index, page, ...);
}
```

### 合并过程

```
合并前：
  ┌──────────┐    ┌──────────┐    ┌──────────┐
  │ Page A   │←──→│ Page B   │←──→│ Page C   │
  │ [10-14]  │    │ [16,17]  │    │ [20-28]  │
  │ 80% 满   │    │ 20% 满   │    │ 70% 满   │
  └──────────┘    └──────────┘    └──────────┘
                  ← 低于 MERGE_THRESHOLD，触发合并

Step 1: 选择合并方向
  → 优先与右兄弟（Page C）合并（如果合并后不超过页容量）
  → 或与左兄弟（Page A）合并

Step 2: 将 Page B 的记录移到 Page A 或 Page C
  → 假设与 Page A 合并：
  ┌──────────────────────────────┐    ┌──────────┐
  │ Page A (合并后)              │    │ Page C   │
  │ [10, 11, 12, 13, 14, 16, 17] │←──→│ [20-28]  │
  └──────────────────────────────┘    └──────────┘

Step 3: 删除 Page B
  → 将 Page B 标记为空闲页（FSP_FREE 链表）
  → 更新叶子链表指针

Step 4: 更新父节点
  → 删除父节点中指向 Page B 的键和指针
  → 如果父节点也低于 MERGE_THRESHOLD → 递归合并父节点
```

---

## 2.8 页结构完整图解

```
╔══════════════════════════════════════════════════════════════╗
║              InnoDB Page 完整结构 (16KB)                      ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  ┌─ FIL Header (38B) ──────────────────────────────────────┐║
║  │ Space_ID | Page_No | Prev_Page | Next_Page | LSN | Type │║
║  └──────────────────────────────────────────────────────────┘║
║                                                              ║
║  ┌─ Page Header (56B) ─────────────────────────────────────┐║
║  │ N_DIR_SLOTS | HEAP_TOP | N_HEAP | FREE | GARBAGE |      │║
║  │ LAST_INSERT | DIRECTION | N_DIRECTION | N_RECS |         │║
║  │ MAX_TRX_ID | LEVEL | INDEX_ID                          │║
║  └──────────────────────────────────────────────────────────┘║
║                                                              ║
║  ┌─ Records (从 Infimum 到 Supremum 的链表) ───────────────┐║
║  │                                                          │║
║  │  Infimum ─→ [Rec1: RH+数据] ─→ [Rec2] ─→ ... ─→ Supremum│║
║  │              ↑ 5B Header                                  │║
║  │              │ next_off | delete | n_owned | heap_no |...  │║
║  │                                                          │║
║  └──────────────────────────────────────────────────────────┘║
║                                                              ║
║  ┌─ Free Space ─────────────────────────────────────────────┐║
║  │  （新记录从 HEAP_TOP 分配，删除记录进 FREE 链表）        │║
║  └──────────────────────────────────────────────────────────┘║
║                                                              ║
║  ┌─ Page Directory (从末尾向前增长) ────────────────────────┐║
║  │  Slot[0]=Infimum | Slot[1]=Rec4 | Slot[2]=Rec8 |        │║
║  │  Slot[3]=Rec12 | Slot[N]=Supremum                        │║
║  └──────────────────────────────────────────────────────────┘║
║                                                              ║
║  ┌─ FIL Trailer (8B) ──────────────────────────────────────┐║
║  │  End_LSN | Checksum                                      │║
║  └──────────────────────────────────────────────────────────┘║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

**页查找的两阶段流程图**：

```
  传入查找键 tuple
  
  ┌────────────────────────────┐
  │ 阶段1：Slot 二分查找       │
  │                            │
  │ Slot[0]  → Infimum (最小)  │
  │ Slot[1]  → Rec4  (id=4)   │
  │ Slot[2]  → Rec8  (id=8)   │  ← 目标 id=7
  │ Slot[3]  → Rec12 (id=12)  │
  │ Slot[4]  → Supremum(最大) │
  │                            │
  │ 二分: 7 ∈ [4, 8]          │
  │ → 粗定位到 Slot[1]~Slot[2]│
  └────────────┬───────────────┘
               │
               ▼
  ┌────────────────────────────┐
  │ 阶段2：线性精查找          │
  │                            │
  │ 从 Rec4 开始沿 next 指针   │
  │ Rec4 → Rec5 → Rec6 → Rec7 │  ← 找到 id=7！
  │ 最多查找 4-8 条记录        │
  └────────────────────────────┘
```

---

# 第三部分：聚簇索引与二级索引

## 3.1 聚簇索引（Clustered Index）——表就是索引，索引就是表

### 聚簇索引的定义

**聚簇索引 = 按主键排序存储整行数据的 B+Tree**

InnoDB 中每张表有且仅有**一棵聚簇索引 B+Tree**：
- 如果表定义了主键 → 主键就是聚簇索引
- 如果表没有主键 → InnoDB 自动选择第一个唯一非空列作为聚簇索引
- 如果既没有主键也没有唯一非空列 → InnoDB 自动生成一个 6 字节的隐藏 row_id 作为聚簇索引

```
聚簇索引 B+Tree：

              ┌─── Root Page (Level 2) ───┐
              │ 1  |  101  |  201  | 301  │  ← 主键值
              └──┬─────┬───────┬─────┬───┘
                 │     │       │     │
     ┌───────────┘     │       │     └───────────┐
     ▼                 ▼       ▼                  ▼
 ┌─Level 1─┐     ┌─Level 1─┐ ┌─Level 1─┐   ┌─Level 1─┐
 │1|2|..|100│     │101|..   │ │201|..   │   │301|..   │
 └─┬──┬──┘     └─┬──┬──┘ └─┬──┬──┘   └─┬──┬──┘
   │  │          │  │       │  │        │  │
   ▼  ▼          ▼  ▼       ▼  ▼        ▼  ▼
┌──────────────────────────────────────────────────────┐
│                  Leaf Pages                           │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │ Leaf Record = 完整数据行                     │    │
│  │                                              │    │
│  │ id=1 | name='Alice' | age=25 | email=...     │    │
│  │ id=2 | name='Bob'   | age=30 | email=...     │    │
│  │ ...                                          │    │
│  │ id=100 | name='Zoe' | age=28 | email=...     │    │
│  │                                              │    │
│  │ ←── 双向链表连接 ──→                         │    │
│  └──────────────────────────────────────────────┘    │
│                                                      │
└──────────────────────────────────────────────────────┘
```

**关键理解**：

- 聚簇索引的叶子节点存储的是**完整的数据行**，不是只有主键值
- 表的数据**物理上按主键顺序存储**，不是随机位置
- 查找主键 = 3 次 I/O 直接定位（假设 3 层 B+Tree），无需回表
- 范围查询 `WHERE id BETWEEN 1 AND 100` = 定位起点后沿叶子链表顺序扫描

---

## 3.2 二级索引（Secondary Index）——叶子存主键值

### 二级索引的定义

**二级索引 = 按索引列排序存储（索引列值 + 主键值）的 B+Tree**

```sql
CREATE INDEX idx_name ON user(name);
```

```
二级索引 idx_name 的 B+Tree：

              ┌─── Root Page ───┐
              │ 'A' | 'M' | 'Z' │  ← name 列值
              └──┬────┬────┬───┘
                 │    │    │
     ┌───────────┘    │    └───────────┐
     ▼                ▼                ▼
 ┌─Level 1─┐    ┌─Level 1─┐    ┌─Level 1─┐
 │'A'|'B'|..│    │'M'|'N'|..│    │'Z'|... │
 └─┬──┬──┘    └─┬──┬──┘    └─┬──┬──┘
   │  │         │  │         │  │
   ▼  ▼         ▼  ▼         ▼  ▼
┌──────────────────────────────────────────────────────┐
│                  Leaf Pages                           │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │ Leaf Record = (索引列值 + 主键值)            │    │
│  │                                              │    │
│  │ name='Alice', id=1                           │    │
│  │ name='Bob',   id=2                           │    │
│  │ name='Carol', id=3                           │    │
│  │ ...                                          │    │
│  │ name='Zoe',   id=100                         │    │
│  │                                              │    │
│  │ ←── 双向链表连接 ──→                         │    │
│  └──────────────────────────────────────────────┘    │
│                                                      │
└──────────────────────────────────────────────────────┘
```

**关键理解**：

- 二级索引叶子节点只存 **索引列值 + 主键值**，不存完整数据行
- 二级索引中主键值的作用：**唯一标识一条数据行**，用于回表查找
- 为什么存主键而不是行指针？→ 避免行移动时更新所有二级索引（聚簇索引分裂/合并时行会移动，但主键值不变）

### 二级索引的记录结构

```
二级索引叶子的记录结构：

┌──────────────────────────────────────────────────────────┐
│ 二级索引 Leaf Record                                      │
│                                                          │
│  ┌─ Record Header (5B) ──┐                               │
│  │ next_off | flags | ... │                               │
│  └────────────────────────┘                               │
│                                                          │
│  ┌─ 索引列值 ─────────────┐                               │
│  │ name = 'Alice'         │  ← 索引列的值                  │
│  └────────────────────────┘                               │
│                                                          │
│  ┌─ 主键值 ───────────────┐                               │
│  │ id = 1                 │  ← 聚簇索引的主键值            │
│  └────────────────────────┘                               │
│                                                          │
│  注意：二级索引叶子不存 DB_TRX_ID 和 DB_ROLL_PTR          │
│  → 事务信息只在聚簇索引中维护                              │
│  → 二级索引的 MVCC 检查需要回表到聚簇索引                 │
└──────────────────────────────────────────────────────────┘
```

---

## 3.3 二级索引的回表查询——为什么要"回表"

### 回表的定义

**回表 = 通过二级索引找到主键值后，再到聚簇索引中查找完整数据行**

### 回表的完整过程

```sql
SELECT * FROM user WHERE name = 'Alice';
```

```
Step 1: 在二级索引 idx_name 的 B+Tree 中查找 name='Alice'
  → Root → Level 1 → Leaf Page
  → 找到二级索引叶子记录: name='Alice', id=1
  → 取出主键值 id=1

Step 2: 在聚簇索引的 B+Tree 中查找 id=1
  → Root → Level 1 → Leaf Page
  → 找到聚簇索引叶子记录: id=1 | name='Alice' | age=25 | email=...
  → 返回完整数据行

回表代价：
  → 二级索引查找: 3 次 I/O（3 层 B+Tree）
  → 聚簇索引回表: 3 次 I/O（3 层 B+Tree）
  → 总计: 6 次 I/O（比直接查聚簇索引多 3 次）
```

**回表的代价图解**：

```
┌─────────────────────────────────────────────────────────────┐
│                     回表查询流程                              │
│                                                             │
│  ┌─────────────────────────────────┐                        │
│  │     二级索引 B+Tree (idx_name)  │                        │
│  │                                 │                        │
│  │  Root → ... → Leaf              │                        │
│  │  找到 name='Alice'              │                        │
│  │  → 取出主键 id=1 ──────────────│──┐                     │
│  └─────────────────────────────────┘  │                     │
│                                       │                     │
│                                       ▼                     │
│  ┌─────────────────────────────────┐                        │
│  │     聚簇索引 B+Tree (PRIMARY)   │                        │
│  │                                 │                        │
│  │  Root → ... → Leaf              │                        │
│  │  用 id=1 查找                   │                        │
│  │  找到完整行数据                  │                        │
│  │  → 返回给客户端 ───────────────│──→ 结果集              │
│  └─────────────────────────────────┘                        │
│                                                             │
│  总 I/O = 二级索引3次 + 聚簇索引3次 = 6次                    │
└─────────────────────────────────────────────────────────────┘
```

### 回表对范围查询的影响

```sql
SELECT * FROM user WHERE name BETWEEN 'A' AND 'C';
```

```
1. 在 idx_name 中范围扫描 → 找到 100 条匹配的二级索引记录
2. 每条记录都要回表到聚簇索引 → 100 次回表
3. 如果这 100 条记录的 id 在聚簇索引中分散在不同页 → 100 次随机 I/O！

优化器可能选择：
  → 如果匹配行数很多（选择率低）→ 直接全表扫描聚簇索引（顺序 I/O 更快）
  → 如果匹配行数很少（选择率高）→ 用二级索引 + 回表（总 I/O 少）
```

---

## 3.4 索引高度计算——一棵 3 层 B+Tree 能存多少行

### 计算公式

```
非叶子节点：
  每个页存键值 + 子节点指针
  每个键值对占空间 ≈ 索引列大小 + 页号指针(4B)
  非叶子页可存键数 ≈ 16KB / (索引列大小 + 4B + 记录头5B)
  
  主键 BIGINT(8B) 的非叶子页：
    每条 ≈ 8B + 4B + 5B = 17B（实际更复杂，约 20B）
    可存 ≈ 16KB / 20B ≈ 800 个键
    
  主键 INT(4B) 的非叶子页：
    每条 ≈ 4B + 4B + 5B = 13B（实际约 15B）
    可存 ≈ 16KB / 15B ≈ 1070 个键

叶子节点：
  每条记录大小 ≈ 主键 + 其他列 + 隐藏列(DB_TRX_ID+DB_ROLL_PTR) + Record Header
  假设每行 1KB → 每叶子页约 16 行
  假设每行 100B → 每叶子页约 160 行
  假设每行 500B → 每叶子页约 32 行

高度计算：
  假设非叶子页存 1170 个键（INT 主键），每叶子页 16 行（1KB 行）
  
  1层 (只有Root=叶子): 16 行
  2层: 1170 × 16 = 18,720 行
  3层: 1170 × 1170 × 16 = 21,902,400 行 ≈ 2190 万行
  4层: 1170 × 1170 × 1170 × 16 ≈ 25.6 亿行

结论：3 层 B+Tree 可以存约 2190 万行 → 99% 的表 3 层就够了
      → 查询任意一行只需 2-3 次 I/O
```

### 索引高度查询

```sql
-- 查看索引的高度（Level）
SELECT 
    index_name,
    stat_value AS leaf_pages,
    ROUND(stat_value * @@innodb_page_size / 1024 / 1024, 2) AS size_mb
FROM mysql.innodb_index_stats
WHERE database_name = 'test' AND table_name = 'user'
  AND stat_name = 'n_leaf_pages';

-- 然后用公式：height = log(fanout, leaf_pages) + 1
```

---

## 3.5 联合索引的结构——多列在 B+Tree 中的排列方式

### 联合索引的定义

```sql
CREATE INDEX idx_a_b_c ON user(a, b, c);
```

联合索引 `(a, b, c)` 的 B+Tree 按什么顺序排列？

**排序规则：先按 a 排序，a 相同按 b 排序，a 和 b 相同按 c 排序**

```
联合索引 (a, b, c) 的叶子记录排列：

  a=1, b=1, c=1  →  主键值=5
  a=1, b=1, c=3  →  主键值=1
  a=1, b=2, c=1  →  主键值=3
  a=1, b=3, c=2  →  主键值=7
  a=2, b=1, c=1  →  主键值=4
  a=2, b=1, c=4  →  主键值=2
  a=2, b=2, c=1  →  主键值=8
  a=3, b=1, c=1  →  主键值=6
  ...

排序过程：
  第1级排序：按 a 列值从小到大
    → a=1 的所有记录 < a=2 的所有记录 < a=3 的所有记录
  
  第2级排序：a 相同时，按 b 列值从小到大
    → (a=1, b=1) < (a=1, b=2) < (a=1, b=3)
  
  第3级排序：a 和 b 相同时，按 c 列值从小到大
    → (a=1, b=1, c=1) < (a=1, b=1, c=3)
  
  最终排序：a=b=c 都相同时，按主键值排序
    → (a=1, b=1, c=1, id=5) < (a=1, b=1, c=1, id=10)
```

### 联合索引的非叶子节点

```
非叶子节点存的是索引列的前缀键值：

Root Page（假设扇出大）：
  │ (a=1) → 子树1 │ (a=2) → 子树2 │ (a=3) → 子树3 │

Level 1（更细的分叉）：
  子树1内：
  │ (a=1,b=1) → 叶子组1 │ (a=1,b=2) → 叶子组2 │ (a=1,b=3) → 叶子组3 │

注意：非叶子节点不一定存完整的联合索引键
  → 非叶子节点只存足以区分子树的键前缀
  → 例如，如果所有 a=1 的记录都在同一棵子树中
     → 非叶子节点只存 a=1 就够了（不需要存 b 和 c）
```

---

## 3.6 联合索引的排序规则——字符串比较的 collation 影响

### 字符串列的排序规则

联合索引中如果包含字符串列（VARCHAR/CHAR），排序受 **collation（排序规则）** 影响：

```sql
-- 默认 utf8mb4_general_ci（不区分大小写）
CREATE INDEX idx_name ON user(name);  -- 使用默认 collation

-- 'Alice' 和 'alice' 在索引中被视为相同值！
-- 唯一索引会冲突：INSERT 'alice' 时如果已有 'Alice' → 报错 Duplicate

-- 使用 utf8mb4_bin（区分大小写，按字节排序）
CREATE INDEX idx_name ON user(name) COLLATE utf8mb4_bin;
-- 'Alice' < 'alice'（因为 'A' < 'a' 在 ASCII 中）
```

### 对最左前缀的影响

```
如果 name 列使用 utf8mb4_general_ci：
  WHERE name = 'Alice'  → 能用到索引（不区分大小写匹配）
  WHERE name LIKE 'A%'  → 能用到索引（前缀匹配）
  WHERE name LIKE '%A%' → 不能用索引（中间通配符）

如果 name 列使用 utf8mb4_bin：
  WHERE name = 'Alice'  → 只匹配 'Alice'，不匹配 'alice'
  WHERE name LIKE 'A%'  → 只匹配以大写 'A' 开头的
```

---

## 3.7 納引的物理存储——.ibd 文件中的区、段、页

### 表空间的层次结构

```
.ibd 文件（独立表空间）的物理结构：

┌──────────────────────────────────────────────────────┐
│                    .ibd File                         │
│                                                      │
│  ┌─ Segment（段）──────────────────────────────────┐ │
│  │  每个索引占 2 个段：                             │ │
│  │  - 数据段（Leaf Segment）：叶子节点页            │ │
│  │  - 非叶子段（Non-Leaf Segment）：非叶子节点页    │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  ┌─ Extent（区）───────────────────────────────────┐ │
│  │  1 个区 = 64 个连续页 = 1MB（默认页大小16KB）    │ │
│  │  索引的段以区为单位分配空间                       │ │
│  │  最初分配 1 个区，后续按需扩展                    │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  ┌─ Page（页）─────────────────────────────────────┐ │
│  │  1 个页 = 16KB（默认）                           │ │
│  │  页是 I/O 的最小单位                             │ │
│  │  一个页 = B+Tree 的一个节点                      │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  ┌─ Row（行）──────────────────────────────────────┐ │
│  │  行存在页内的 Record Heap 中                     │ │
│  │  行大小可变（动态行格式）                         │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  .ibd 文件的初始页：                                  │
│  Page 0: FSP Header（表空间头，管理空闲区链表）      │
│  Page 1: IBUF Bitmap（Change Buffer 位图）           │
│  Page 2: INODE（段描述信息）                          │
│  Page 3: 聚簇索引 Root Page                          │
│  Page 4+: 索引数据页                                 │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### Fragment Extent（碎片区）

```
段的初始分配策略：

1. 段刚创建时，不直接分配完整的区（64页）
   → 先从 FSP 的碎片页中分配最多 32 个页
   → 这些页叫"碎片页"（Fragment Pages）
   → 避免小表浪费空间

2. 当段的碎片页超过 32 个后，才开始按区分配
   → 每次分配一个完整的区（64页）
   → 后续分配以区为单位

源码：fsp0fsp.cc 中的 fsp_alloc_free_page() 和 fsp_alloc_free_extent()
```

---

# 第四部分：最左前缀匹配原理

## 4.1 最左前缀是什么——从联合索引的 B+Tree 结构推导

### 最左前缀的定义

**最左前缀 = 联合索引的索引列按照定义顺序从左到右依次匹配**

联合索引 `(a, b, c)` 的 B+Tree 排序规则：
- 先按 a 排序
- a 相同时按 b 排序  
- a 和 b 相同时按 c 排序

这意味着：

```
索引 (a, b, c) 的有序性：

✅ a 是全局有序的（整棵 B+Tree 按 a 从小到大排列）
✅ a 确定后，b 是局部有序的（同一 a 值范围内 b 有序）
✅ a 和 b 确定后，c 是局部有序的

❌ b 不是全局有序的（不同 a 值下的 b 值交错排列）
❌ c 不是全局有序的（不同 a 或 b 值下的 c 值交错排列）
❌ (b, c) 不是全局有序的
❌ (a, c) 是部分有序的（a 有序，但 c 在不同 a 值下无序）

最左前缀匹配规则：
  只有从最左列开始，依次使用索引列，才能利用 B+Tree 的有序性
  → 跳过最左列 → 无法利用索引排序 → 只能全索引扫描
```

---

## 4.2 全列匹配——索引的完美使用

```sql
-- 联合索引 (a, b, c)

-- 全列等值匹配（完美）
SELECT * FROM user WHERE a = 1 AND b = 2 AND c = 3;
→ 等值条件覆盖所有 3 列 → B+Tree 直接定位 → 3 层 I/O
→ EXPLAIN: type=ref, key=idx_a_b_c, key_len=完整长度

-- 列顺序无关（优化器会自动调整）
SELECT * FROM user WHERE c = 3 AND a = 1 AND b = 2;
→ MySQL 优化器会自动将条件调整为 (a=1 AND b=2 AND c=3)
→ 仍然完美使用索引
→ 注意：这是等值条件的特性，范围条件则不同
```

---

## 4.3 最左前缀匹配——前缀列的等值查询

```sql
-- 匹配最左 1 列
SELECT * FROM user WHERE a = 1;
→ a 全局有序 → B+Tree 在 a 列上直接定位
→ 找到所有 a=1 的记录后，在叶子链表中扫描
→ EXPLAIN: type=ref, key=idx_a_b_c, key_len=a列长度

-- 匹配最左 2 列
SELECT * FROM user WHERE a = 1 AND b = 2;
→ a 全局有序 → 先定位 a=1
→ 在 a=1 的范围内 b 有序 → 再定位 b=2
→ EXPLAIN: type=ref, key=idx_a_b_c, key_len=a+b列长度
```

---

## 4.4 范围查询打破最左前缀——第一个范围列之后的列无法利用索引

```sql
-- a 范围查询 + b 等值 → b 无法利用索引排序
SELECT * FROM user WHERE a > 1 AND b = 2;
→ a 范围查询：在 B+Tree 中定位 a>1 的范围后，需要扫描所有 a>1 的叶子记录
→ 在这些记录中，b 不保证有序（因为 a 的值不同，b 的排列可能交错）
→ b=2 的条件只能在扫描过程中逐行过滤
→ EXPLAIN: type=range, key=idx_a_b_c, key_len=a列长度（只用到了 a 列）

-- a 等值 + b 范围 → c 无法利用索引排序
SELECT * FROM user WHERE a = 1 AND b > 2 AND c = 3;
→ a=1 等值 → 定位 a=1 的范围
→ b>2 范围 → 在 a=1 的范围内，b 是有序的，可以利用 b 的范围扫描
→ c=3 等值 → 但在 b>2 的范围内，c 不保证有序 → 只能逐行过滤
→ EXPLAIN: type=range, key=idx_a_b_c, key_len=a+b列长度（用到了 a 和 b）
```

**核心原理图解**：

```
联合索引 (a, b, c) 的叶子记录：

  a=1, b=1, c=5    ← WHERE a>1 AND b=2 扫描到这里时，b=1 ≠ 2，跳过
  a=1, b=2, c=1    ← b=2 匹配，但这是 a=1，不是 a>1
  a=1, b=2, c=3
  a=1, b=3, c=2
  a=2, b=1, c=1    ← a>1 开始，但 b=1 ≠ 2，跳过
  a=2, b=1, c=4    ← b=1 ≠ 2，跳过
  a=2, b=2, c=1    ← 匹配！a>1 ✓, b=2 ✓
  a=2, b=2, c=5    ← 匹配！
  a=2, b=3, c=1    ← b=3 ≠ 2，跳过
  a=3, b=1, c=1    ← b=1 ≠ 2，跳过
  a=3, b=2, c=2    ← 匹配！
  ...

问题：a>1 范围内的记录，b 值交错排列（b=1, b=1, b=2, b=2, b=3, b=1, b=2...）
→ b 不全局有序 → 无法在 B+Tree 上利用 b=2 的有序性
→ 只能逐行扫描检查 b=2

范围查询打破最左前缀的本质：
  → 范围条件后的列在 B+Tree 中的有序性被打破
  → 因为范围条件跨越了多个"前缀列值"的分组
  → 不同分组中后续列的值是各自有序但全局无序的
```

---

## 4.5 跳过中间列——索引部分生效

```sql
-- 跳过 b 列，只用 a 和 c
SELECT * FROM user WHERE a = 1 AND c = 3;
→ a=1 等值 → 定位 a=1 的范围
→ 跳过 b → 在 a=1 的范围内 c 不保证有序
→ c=3 条件只能逐行过滤
→ EXPLAIN: type=ref, key=idx_a_b_c, key_len=a列长度
→ 索引只用到 a 列，c 列未利用索引排序

注意：MySQL 5.6+ 引入 ICP 后，c=3 的条件会被下推到存储引擎层
→ 在二级索引扫描时就过滤 c=3（而不是回表后再过滤）
→ 减少回表次数 → 性能提升
→ 但 c 列仍然没有利用索引的有序性（只是提前过滤）
```

---

## 4.6 列顺序无关——优化器的索引列顺序自动调整

```sql
-- 等值条件列顺序无关
SELECT * FROM user WHERE b = 2 AND a = 1;
→ MySQL 优化器自动调整为 WHERE a = 1 AND b = 2
→ 仍然匹配最左前缀 a → b
→ EXPLAIN: type=ref, key=idx_a_b_c, key_len=a+b列长度

-- 但范围条件列顺序相关！
SELECT * FROM user WHERE b > 2 AND a = 1;
→ 优化器调整为 WHERE a = 1 AND b > 2 → 匹配最左前缀 a → b范围

SELECT * FROM user WHERE a > 1 AND b = 2;
→ 无法调整！a 范围条件在 b 等值之前 → b 无法利用索引
→ EXPLAIN: key_len=a列长度（只用到了 a）

结论：
  ✅ 等值条件：列顺序无关（优化器自动调整）
  ❌ 范围条件：列顺序影响索引使用（范围列在前的后续列无法用索引）
```

---

## 4.7 最左前缀在 LIKE 中的应用——为什么只有前缀 LIKE 能用索引

```sql
-- 前缀 LIKE（可以用索引）
SELECT * FROM user WHERE name LIKE 'Ali%';
→ 'Ali%' 等价于 name >= 'Ali' AND name < 'Alj'
→ 范围查询，name 在 B+Tree 中有序 → 可以利用索引定位
→ EXPLAIN: type=range, key=idx_name

-- 中缀/后缀 LIKE（不能用索引）
SELECT * FROM user WHERE name LIKE '%li%';
→ '%li%' 无法转化为有意义的范围查询
→ B+Tree 无法定位 '%li%' 的起始位置
→ EXPLAIN: type=ALL（全表扫描）

SELECT * FROM user WHERE name LIKE '%ce';
→ '%ce' 同理，无法转化为范围查询
→ EXPLAIN: type=ALL

本质：
  LIKE 'X%' → 可以转为范围查询 → 能用 B+Tree 有序性
  LIKE '%X' → 无法转为范围查询 → B+Tree 有序性无用
  LIKE '%X%' → 同理

  最左前缀原则在 LIKE 中的体现：
  字符串索引等价于以每个字符为"列"的联合索引
  → LIKE 'ABC%' 等价于 WHERE char1='A' AND char2='B' AND char3='C' AND char4范围
  → 匹配最左前缀 → 能用索引
  → LIKE '%BC%' 跳过了最左的 char1 → 不能用索引
```

---

## 4.8 最左前缀在 ORDER BY 中的应用——索引排序替代 Filesort

```sql
-- ORDER BY 使用联合索引的排序
CREATE INDEX idx_a_b ON user(a, b);

-- ORDER BY a（最左列）→ 使用索引排序
SELECT * FROM user WHERE a = 1 ORDER BY b;
→ WHERE a=1 定位范围 → 在 a=1 范围内 b 有序 → ORDER BY b 不需要额外排序
→ EXPLAIN: Extra 没有 Using filesort

-- ORDER BY a, b → 使用索引排序
SELECT * FROM user ORDER BY a, b;
→ 完全匹配索引列顺序 → 索引本身就是 a,b 排序的 → 不需要 Filesort
→ EXPLAIN: Extra 没有 Using filesort

-- ORDER BY b（跳过最左列 a）→ 不能使用索引排序
SELECT * FROM user ORDER BY b;
→ b 不是全局有序 → 需要额外排序
→ EXPLAIN: Extra=Using filesort

-- ORDER BY b, a（列顺序与索引不一致）→ 不能使用索引排序
SELECT * FROM user ORDER BY b, a;
→ 索引按 (a, b) 排序，但 ORDER BY 要求按 (b, a) 排序 → 顺序不一致
→ EXPLAIN: Extra=Using filesort

-- WHERE a=1 ORDER BY b → 完美使用索引
SELECT * FROM user WHERE a = 1 ORDER BY b;
→ a=1 等值过滤后，剩余记录在 b 上有序 → ORDER BY b 不需要 Filesort
→ EXPLAIN: Extra 没有 Using filesort ✅

-- WHERE a > 1 ORDER BY b → b 无法使用索引排序
SELECT * FROM user WHERE a > 1 ORDER BY b;
→ a>1 是范围查询 → b 在 a>1 范围内不一定有序 → ORDER BY b 需要 Filesort
→ EXPLAIN: Extra=Using filesort ❌
```

---

## 4.9 最左前缀在 GROUP BY 中的应用

```sql
CREATE INDEX idx_a_b_c ON user(a, b, c);

-- GROUP BY a → 使用索引排序分组
SELECT a, COUNT(*) FROM user GROUP BY a;
→ 索引按 a 排序 → 分组只需沿叶子链表扫描 → 不需要临时表排序
→ EXPLAIN: Extra 没有 Using temporary; Using filesort

-- GROUP BY a, b → 使用索引排序分组
SELECT a, b, COUNT(*) FROM user GROUP BY a, b;
→ 索引按 (a, b) 排序 → 分组有序 → 不需要临时表
→ EXPLAIN: Extra 没有 Using temporary

-- GROUP BY b → 不能使用索引排序分组
SELECT b, COUNT(*) FROM user GROUP BY b;
→ b 不全局有序 → 需要临时表排序
→ EXPLAIN: Extra=Using temporary; Using filesort

-- WHERE a = 1 GROUP BY b → 使用索引
SELECT b, COUNT(*) FROM user WHERE a = 1 GROUP BY b;
→ a=1 等值过滤后，b 在 a=1 范围内有序 → 分组有序
→ EXPLAIN: Extra 没有 Using temporary ✅
```

---

## 4.10 最左前缀原理总结与速查表

### 速查表

```
联合索引 (a, b, c)

WHERE 条件                          │ 索引使用情况         │ key_len
────────────────────────────────────│─────────────────────│────────
a = 1                               │ ✅ 用到 a            │ a列长度
a = 1 AND b = 2                     │ ✅ 用到 a, b         │ a+b列长度
a = 1 AND b = 2 AND c = 3           │ ✅ 用到 a, b, c      │ a+b+c列长度
a > 1                               │ ✅ 用到 a（范围）     │ a列长度
a > 1 AND b = 2                     │ ✅ 用到 a（范围）     │ a列长度
                                    │ ❌ b 无法利用索引     │
a = 1 AND b > 2                     │ ✅ 用到 a, b（范围）  │ a+b列长度
a = 1 AND b > 2 AND c = 3           │ ✅ 用到 a, b（范围）  │ a+b列长度
                                    │ ❌ c 无法利用索引     │
a = 1 AND c = 3                     │ ✅ 用到 a            │ a列长度
                                    │ ❌ c 无法利用索引排序 │
                                    │ ⚠️ ICP可提前过滤c    │
b = 2                               │ ❌ 跳过最左列a       │ (全索引扫描)
b = 2 AND c = 3                     │ ❌ 跳过最左列a       │ (全索引扫描)
c = 3                               │ ❌ 跳过最左列a和b    │ (全索引扫描)
a LIKE 'Ali%'                       │ ✅ 前缀LIKE = 范围   │ a列长度
a LIKE '%li%'                       │ ❌ 中缀LIKE          │ (全表扫描)
ORDER BY a                          │ ✅ 索引排序          │ -
ORDER BY a, b                       │ ✅ 索引排序          │ -
ORDER BY b                          │ ❌ 跳过最左列        │ Using filesort
ORDER BY b, a                       │ ❌ 顺序不一致        │ Using filesort
WHERE a=1 ORDER BY b                │ ✅ a等值+b有序       │ a+b列长度
WHERE a>1 ORDER BY b                │ ❌ a范围+b无序       │ Using filesort
```

---

# 第五部分：覆盖索引

## 5.1 覆盖索引的定义——查询的列全部在索引中

### 定义

**覆盖索引 = 查询所需的所有列都包含在索引中，无需回表到聚簇索引获取数据**

```sql
CREATE INDEX idx_a_b_c ON user(a, b, c);

-- 覆盖索引查询
SELECT a, b, c FROM user WHERE a = 1;
→ 查询的列 (a, b, c) 全部在索引 idx_a_b_c 中
→ 无需回表 → 直接从二级索引叶子获取数据
→ EXPLAIN: Extra=Using index ✅

-- 非覆盖索引查询
SELECT a, b, c, name FROM user WHERE a = 1;
→ name 列不在 idx_a_b_c 中 → 需要回表获取 name
→ 不是覆盖索引 → 需要回表
→ EXPLAIN: Extra 没有 Using index ❌
```

### 覆盖索引的本质

```
覆盖索引不是一种特殊的索引类型！
覆盖索引 = 一个索引碰巧包含了查询所需的所有列

二级索引叶子节点的列：
  1. 索引定义的列（a, b, c）
  2. 主键列（id）

所以联合索引 (a, b, c) 的叶子实际上包含 4 列的值：(a, b, c, id)
→ SELECT a, b, c, id FROM user WHERE a = 1 → 也是覆盖索引！
→ SELECT id FROM user WHERE a = 1 → 也是覆盖索引！（只用索引中的主键值）
```

---

## 5.2 覆盖索引如何避免回表

### 对比流程

```
非覆盖索引查询：
  SELECT * FROM user WHERE a = 1;
  
  1. 在 idx_a_b_c 中查找 a=1 → 找到叶子记录 → 取出主键 id
  2. 用 id 回表到聚簇索引 → 找到完整数据行 → 取出所有列
  3. 返回结果
  
  代价：二级索引 2-3 次 I/O + 聚簇索引 2-3 次 I/O = 4-6 次 I/O

覆盖索引查询：
  SELECT a, b FROM user WHERE a = 1;
  
  1. 在 idx_a_b_c 中查找 a=1 → 找到叶子记录 → 叶子包含 (a, b, id)
  2. 直接从叶子记录取出 a 和 b 的值 → 无需回表
  3. 返回结果
  
  代价：二级索引 2-3 次 I/O → 聚簇索引 0 次 I/O = 2-3 次 I/O
  
  节省：50% 的 I/O！
```

---

## 5.3 覆盖索引的 EXPLAIN 标识——Using index

```sql
-- 覆盖索引
EXPLAIN SELECT a, b FROM user WHERE a = 1;
+----+-------------+-------+-------+---------------+-------+---------+------+------+-------------+
| id | select_type | table | type  | possible_keys | key   | key_len | ref  | rows | Extra       |
+----+-------------+-------+-------+---------------+-------+---------+------+------+-------------+
|  1 | SIMPLE      | user  | ref   | idx_a_b_c     | idx_a_b_c| a列长 | const| 10  | Using index |
+----+-------------+-------+-------+---------------+-------+---------+------+------+-------------+

Extra = "Using index" → 表示这是覆盖索引查询

-- 非覆盖索引
EXPLAIN SELECT a, b, name FROM user WHERE a = 1;
+----+-------------+-------+-------+---------------+-------+---------+------+------+-----------+
| id | select_type | table | type  | possible_keys | key   | key_len | ref  | rows | Extra     |
+----+-------------+-------+-------+---------------+-------+---------+------+------+-----------+
|  1 | SIMPLE      | user  | ref   | idx_a_b_c     | idx_a_b_c| a列长 | const| 10  |           |
+----+-------------+-------+-------+---------------+-------+---------+------+------+-----------+

Extra 没有 "Using index" → 不是覆盖索引，需要回表
```

---

## 5.4 覆盖索引的实战场景

### 场景一：COUNT 查询优化

```sql
-- 无覆盖索引
SELECT COUNT(*) FROM user WHERE a = 1;
→ 需要回表获取完整行 → 回表代价大

-- 有覆盖索引 idx_a_b
SELECT COUNT(a) FROM user WHERE a = 1;
→ a 列在索引中 → 覆盖索引 → Using index → 无回表
→ 快得多！

注意：COUNT(*) 和 COUNT(1) 在 InnoDB 中等价
→ InnoDB 的 COUNT(*) 会遍历最小的二级索引（如果有的话）
→ 因为二级索引比聚簇索引的叶子记录小 → 扫描更快
→ 这本身就是一种"覆盖索引"的利用（索引叶子包含主键值足够做计数）
```

### 场景二：分页查询优化

```sql
-- 低效：先回表再分页
SELECT * FROM user WHERE a > 1000 LIMIT 100;
→ 需要回表获取所有列 → 回表 100 次

-- 高效：延迟回表（先覆盖索引取主键，再回表）
SELECT * FROM user 
WHERE id IN (
    SELECT id FROM user WHERE a > 1000 LIMIT 100
);
→ 子查询用覆盖索引 idx_a 取 id → Using index → 无回表
→ 主查询用聚簇索引直接定位 id → 最多 100 次回表
→ 但更有序（id 连续 → 聚簇索引页命中率高）
```

### 场景三：统计查询优化

```sql
-- 低效：全表扫描
SELECT SUM(b) FROM user WHERE a = 1;
→ 如果没有覆盖索引 → 全表扫描或二级索引+回表

-- 高效：覆盖索引
CREATE INDEX idx_a_b ON user(a, b);
SELECT SUM(b) FROM user WHERE a = 1;
→ (a, b) 在索引中 → 覆盖索引 → Using index → 无回表
```

---

## 5.5 覆盖索引与 SELECT * 的矛盾

```
SELECT * = 查询所有列 = 永远不能被覆盖索引覆盖（除非索引包含所有列）

最佳实践：
  ❌ SELECT * FROM user WHERE a = 1;  → 永远需要回表
  ✅ SELECT a, b, id FROM user WHERE a = 1;  → 覆盖索引

  → 除非索引包含所有列（不太现实），SELECT * 永远无法使用覆盖索引
  → 只查询需要的列 → 更可能使用覆盖索引 → 更少的 I/O
```

---

## 5.6 覆盖索引与 ORDER BY 的配合

```sql
CREATE INDEX idx_a_b ON user(a, b);

-- 覆盖索引 + ORDER BY = 完美
SELECT a, b FROM user WHERE a = 1 ORDER BY b;
→ WHERE a=1 → 索引定位
→ ORDER BY b → a=1范围内b有序 → 不需要Filesort
→ SELECT a, b → 覆盖索引 → 不需要回表
→ Extra: Using index → 完美！

-- 覆盖索引 + ORDER BY + 非覆盖列 = 退化
SELECT a, b, name FROM user WHERE a = 1 ORDER BY b;
→ ORDER BY b 可以用索引排序
→ 但 SELECT name → 不覆盖 → 需要回表
→ Extra: 没有 Using index → 回表
```

---

## 5.7 覆盖索引与分页查询的优化

### 经典分页优化：延迟关联

```sql
-- 低效的分页查询（深分页问题）
SELECT * FROM user ORDER BY a LIMIT 100000, 10;
→ 需要扫描 100010 行 → 前 100000 行的回表全部浪费 → 极慢

-- 优化：延迟关联（覆盖索引取主键 + 回表取数据行）
SELECT u.* FROM user u
INNER JOIN (
    SELECT id FROM user ORDER BY a LIMIT 100000, 10
) t ON u.id = t.id;

→ 子查询：SELECT id FROM user ORDER BY a LIMIT 100000, 10
  → id 在二级索引 idx_a 的叶子中 → 覆盖索引
  → 只扫描索引叶子页 → 不回表 → 快
  → Extra: Using index

→ 主查询：SELECT u.* FROM user WHERE id IN (...)
  → 用聚簇索引直接定位 → 只有 10 次回表 → 快
```

---

## 5.8 覆盖索引的限制——不是所有查询都能覆盖

```
覆盖索引的适用条件：

1. 查询列必须全部在索引定义列 + 主键列中
   → SELECT * → 除非索引覆盖所有列（罕见）→ 不能覆盖

2. 索引列太多 → 索引维护成本高（INSERT/UPDATE/DELETE 每个索引都要更新）
   → 覆盖索引列多 → 索引页更大 → 索引碎片更多 → 空间浪费

3. 长字符串列（TEXT/BLOB）不能作为索引列
   → 含 TEXT/BLOB 的查询不能使用覆盖索引

4. 覆盖索引对 UPDATE/DELETE 无意义
   → UPDATE/DELETE 通常需要回表获取完整行 → 覆盖索引不减少 I/O

权衡：
  → 覆盖索引是读优化 → 牺牲写性能换取读性能
  → 高读低写的场景 → 多建覆盖索引
  → 高写低读的场景 → 少建覆盖索引
```

---

# 第六部分：索引下推（ICP）与 MRR

## 6.1 Index Condition Pushdown（ICP）——把 WHERE 条件下推到存储引擎层

### ICP 的定义

**ICP = 将 WHERE 条件中可以在索引列上过滤的部分，下推到存储引擎层，在索引扫描时就过滤，减少回表次数**

MySQL 5.6 引入 ICP，优化了"索引只能用部分列"的查询。

### Without ICP vs With ICP 对比

```sql
CREATE INDEX idx_a_b_c ON user(a, b, c);

-- WHERE a = 1 AND c LIKE '%xyz%'
-- a 可以用索引，c 不能用索引排序（跳过 b 列）
```

```
Without ICP（MySQL 5.6 之前）：

  Step 1: 在 idx_a_b_c 中定位 a=1 → 找到 100 条匹配的二级索引记录
  Step 2: 全部 100 条回表到聚簇索引 → 获取完整行数据
  Step 3: 在 Server 层检查 c LIKE '%xyz%' → 只有 10 条匹配
  Step 4: 返回 10 条结果
  
  回表次数：100 次（90 次白回表！）

With ICP（MySQL 5.6+）：

  Step 1: 在 idx_a_b_c 中定位 a=1 → 找到 100 条二级索引记录
  Step 2: 在存储引擎层直接检查 c LIKE '%xyz%'
          → c 列值在索引叶子中！可以直接在索引上过滤
          → 只有 10 条满足 c LIKE '%xyz%'
  Step 3: 只 10 条回表到聚簇索引 → 获取完整行数据
  Step 4: 返回 10 条结果
  
  回表次数：10 次（减少 90%！）
```

**ICP 流程图**：

```
┌─────────────────────────────────────────────────────────────┐
│                  Without ICP                                 │
│                                                             │
│  Server层                                                   │
│  │  WHERE a=1 → 交给存储引擎                                 │
│  │                                                          │
│  存储引擎层                                                 │
│  │  在idx_a_b_c中找a=1 → 100条二级索引记录                   │
│  │  全部回表 → 100次I/O                                      │
│  │                                                          │
│  Server层                                                   │
│  │  检查c LIKE '%xyz%' → 10条匹配 → 90条浪费                │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                  With ICP                                    │
│                                                             │
│  Server层                                                   │
│  │  WHERE a=1 AND c LIKE '%xyz%' → 全部下推到存储引擎        │
│  │                                                          │
│  存储引擎层                                                 │
│  │  在idx_a_b_c中找a=1 → 100条二级索引记录                   │
│  │  直接在索引叶子上检查c LIKE '%xyz%' → 10条匹配            │
│  │  只有10条回表 → 10次I/O                                   │
│  │                                                          │
│  Server层                                                   │
│  │  10条结果直接返回 → 无额外过滤                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 6.2 ICP 的工作流程——Without ICP vs With ICP 对比

### ICP 在 InnoDB 源码中的实现

```c
// storage/innobase/row/row0sel.cc

// ICP 的核心：在索引扫描时就应用 WHERE 条件
ha_innobase::index_read_with_pushcond()
{
    // 1. 将 WHERE 条件中可以在索引列上评估的部分提取出来
    //    → Item_func_like / Item_func_eq 等只涉及索引列的条件
    //    → 形成 "pushed condition"
    
    // 2. 在索引扫描每条记录时：
    //    → 先用 pushed condition 在索引记录上评估
    //    → 不满足 → 直接跳过，不回表
    //    → 满足 → 再回表到聚簇索引
    
    // 3. 回表后，Server 层再用完整 WHERE 条件做最终过滤
    //    → 但大多数过滤已经在存储引擎层完成
}
```

---

## 6.3 ICP 的适用条件

```
ICP 的适用条件：

1. 只适用于 InnoDB 和 MyISAM 引擎
2. 只适用于二级索引（聚簇索引没有回表问题，ICP 无意义）
3. 只适用于 range、ref、eq_ref、ref_or_null 访问方法
4. 不适用于子查询的条件
5. 不适用于存储函数的条件（如 WHERE YEAR(create_time) = 2024）
6. 不适用于全文索引
7. 被下推的条件必须只涉及索引列

ICP 不适用的情况：
  → 覆盖索引查询（Using index）：没有回表 → ICP 无意义
  → 聚簇索引查询：没有回表 → ICP 无意义
  → 全表扫描：不走索引 → ICP 无意义
```

---

## 6.4 ICP 的 EXPLAIN 标识——Using index condition

```sql
EXPLAIN SELECT * FROM user WHERE a = 1 AND c LIKE '%xyz%';
+----+-------------+-------+-------+---------------+-----------+---------+------+------+---------------------+
| id | select_type | table | type  | possible_keys | key       | key_len | ref  | rows | Extra               |
+----+-------------+-------+-------+---------------+-----------+---------+------+------+---------------------+
|  1 | SIMPLE      | user  | ref   | idx_a_b_c     | idx_a_b_c | a列长   | const| 100  | Using index condition|
+----+-------------+-------+-------+---------------+-----------+---------+------+------+---------------------+

Extra = "Using index condition" → ICP 被使用

注意区分：
  "Using index"       → 覆盖索引（无回表）
  "Using index condition" → ICP（有回表，但提前过滤减少回表次数）
  两者同时出现 → 不可能（覆盖索引时不需要 ICP）
```

---

## 6.5 Multi-Range Read（MRR）——二级索引回表的顺序化优化

### MRR 的定义

**MRR = 先按二级索引扫描获取主键值 → 对主键值排序 → 再按排序后的主键顺序回表 → 减少随机 I/O**

### Without MRR vs With MRR

```
Without MRR：

  二级索引扫描顺序：name='A'(id=50) → name='B'(id=3) → name='C'(id=99)
  回表顺序：id=50 → id=3 → id=99
  → 随机 I/O（三个 id 分散在不同聚簇索引页）
  → 每次回表可能读一个新页

With MRR：

  二级索引扫描 → 收集主键值：[50, 3, 99]
  → 排序主键值：[3, 50, 99]
  → 按排序后的顺序回表：id=3 → id=50 → id=99
  → 顺序 I/O（相邻 id 可能同一页 → 只读一次页）
  → Buffer Pool 命中率更高
```

---

## 6.6 MRR 的工作原理——先排序主键再回表

```
MRR 的完整流程：

Step 1: 在二级索引中扫描匹配记录
  → 收集 (索引列值, 主键值) 对到 Row Buffer 中

Step 2: 对 Row Buffer 中的主键值排序
  → 按主键从小到大排序

Step 3: 按排序后的主键值依次回表
  → 相邻的主键值大概率在同一个或相邻的聚簇索引页
  → 减少随机 I/O → 变为半顺序 I/O

Step 4: 对于范围查询，MRR 可以将范围拆分为多个子范围
  → 每个子范围的主键值排序后回表
  → 进一步减少随机 I/O
```

### MRR 的适用场景

```
MRR 适用于：
  → 二级索引范围查询 + 回表量大
  → 范围查询返回的主键值分散 → 随机 I/O 多 → MRR 收益大
  → 范围查询返回的主键值集中 → 随机 I/O 少 → MRR 收益小

MRR 的代价：
  → Row Buffer 的排序需要额外内存和 CPU
  → 如果回表量很少（几条）→ 排序的代价大于收益
  → Buffer Pool 足够大时 → 页都在内存中 → 随机 I/O 不是问题 → MRR 收益小
```

---

## 6.7 MRR 的适用场景与限制

```sql
-- 启用 MRR
SET optimizer_switch='mrr=on,mrr_cost_based=on';

-- mrr_cost_based=on：优化器根据成本模型决定是否用 MRR
--   → 如果 MRR 成本更低 → 用 MRR
--   → 如果 MRR 成本更高（回表量少）→ 不用 MRR

-- 强制 MRR（忽略成本模型）
SET optimizer_switch='mrr=on,mrr_cost_based=off';
--   → 所有二级索引范围查询都尝试用 MRR
--   → 可能比不用 MRR 更慢（排序代价）

-- MRR 的 read_rnd_buffer_size 参数
SET read_rnd_buffer_size = 256K;
--   → Row Buffer 的大小 → 影响 MRR 的排序效率
--   → 默认 256KB → 可以调大到 1M-4M（大范围查询）
```

---

## 6.8 Batched Key Access（BKA）——MRR + join buffer

### BKA 的定义

**BKA = MRR 用于 JOIN 查询的变体**

```
BKA 的工作原理：

  JOIN 查询：t1 JOIN t2 ON t1.a = t2.a

  Without BKA：
    → 对 t1 的每一行 → 用 t1.a 在 t2 的索引中查找 → 回表
    → N 次随机 I/O

  With BKA：
    → 先扫描 t1 → 将所有 t1.a 值收集到 Join Buffer 中
    → 对 Join Buffer 中的 t1.a 值排序
    → 批量用排序后的 t1.a 值在 t2 的索引中 MRR 查找
    → 减少随机 I/O → 变为半顺序 I/O
```

```sql
-- 启用 BKA
SET optimizer_switch='batched_key_access=on';
```

---

# 第七部分：索引统计信息与优化器选择

## 7.1 优化器的索引选择流程

```
MySQL 优化器选择索引的流程：

┌──────────────────────────────────────────────────────────┐
│              优化器索引选择流程                             │
│                                                          │
│  Step 1: 解析 SQL → 提取 WHERE 条件                       │
│  Step 2: 识别可用的索引（possible_keys）                   │
│  │  → 哪些索引的列匹配 WHERE 条件？                       │
│  │  → 可能有多个候选索引                                  │
│                                                          │
│  Step 3: 计算每个候选索引的代价                            │
│  │  → 代价 = I/O 代价 + CPU 代价                         │
│  │  → I/O 代价：需要读取的页数估算                        │
│  │  → CPU 代价：需要评估的记录数估算                      │
│  │                                                        │
│  │  估算方法：                                             │
│  │  → 使用索引统计信息（Cardinality / n_distinct）        │
│  │  → Cardinality / 表行数 = 选择率（selectivity）        │
│  │  → 选择率 × 表行数 = 估算匹配行数                      │
│  │                                                        │
│  Step 4: 计算全表扫描的代价                                │
│  │  → 代价 = 聚簇索引叶页数 × 单页I/O代价                 │
│  │                                                        │
│  Step 5: 选择代价最低的方案                                │
│  │  → 索引代价 < 全表扫描代价 → 选索引                    │
│  │  → 索引代价 > 全表扫描代价 → 选全表扫描                │
│  │                                                        │
│  Step 6: 生成执行计划（EXPLAIN 输出）                      │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## 7.2 索引统计信息——SHOW INDEX 的 Cardinality

```sql
SHOW INDEX FROM user;
+-------+------------+-----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+
| Table | Non_unique | Key_name  | Seq_in_index | Column_name | Collation | Cardinality | Sub_part | Packed | Null | Index_type | Comment | Index_comment |
+-------+------------+-----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+
| user  | 0          | PRIMARY   | 1            | id          | A         | 1000000     | NULL     | NULL   |      | BTREE      |         |               |
| user  | 1          | idx_a_b   | 1            | a           | A         | 500         | NULL     | NULL   | YES  | BTREE      |         |               |
| user  | 1          | idx_a_b   | 2            | b           | A         | 1000        | NULL     | NULL   | YES  | BTREE      |         |               |
+-------+------------+-----------+--------------+-------------+-----------+-------------+----------+--------+------+------------+---------+---------------+
```

### Cardinality 的含义

```
Cardinality = 索引列中不重复值的估算数量

  idx_a_b 的 a 列 Cardinality = 500
  → a 列约有 500 个不同的值
  → 选择率 ≈ 500 / 1000000 = 0.05%
  → WHERE a = 1 估算匹配 ≈ 1000000 × 0.05% = 2000 行

  idx_a_b 的 (a, b) Cardinality = 1000
  → (a, b) 组合约有 1000 个不同的值
  → 选择率 ≈ 1000 / 1000000 = 0.1%
  → WHERE a = 1 AND b = 2 估算匹配 ≈ 1000000 × 0.1% = 1000 行

理想情况：Cardinality / 表行数 ≈ 1（唯一索引）→ 选择率最高
糟糕情况：Cardinality / 表行数 ≈ 0（只有几个不同值）→ 选择率极低 → 不走索引
```

---

## 7.3 InnoDB 的统计信息采集——persistent vs transient

### 两种统计信息模式

```
1. transient（非持久化，默认在 MySQL 5.6 之前）
   → 统计信息存在内存中，重启后丢失
   → 每次重启后第一次打开表时重新采样
   → 采样方法：随机选几个叶子页 → 统计不同值数
   → 不精确 → 不同时间 SHOW INDEX 的 Cardinality 可能不同
   → 导致执行计划不稳定

2. persistent（持久化，MySQL 5.6+ 推荐默认）
   → 统计信息存在 mysql.innodb_table_stats 和 mysql.innodb_index_stats 表中
   → 重启后不丢失 → 执行计划更稳定
   → 采样方法仍然是随机采样（但采样结果持久化）
   → 修改统计信息后需要 ANALYZE TABLE 更新

配置：
  SET GLOBAL innodb_stats_persistent = ON;  -- 推荐 ON
  SET GLOBAL innodb_stats_persistent_sample_pages = 20;  -- 采样页数（默认20）
  → 采样页数越多 → 统计信息越精确 → 但 ANALYZE TABLE 越慢
```

### innodb_index_stats 表内容

```sql
SELECT * FROM mysql.innodb_index_stats
WHERE database_name = 'test' AND table_name = 'user';
+---------------+------------+------------+--------+-------------+----------+-------------------+
| database_name | table_name | index_name | stat_name | stat_value | sample_size | stat_description |
+---------------+------------+------------+--------+-------------+----------+-------------------+
| test          | user       | PRIMARY    | n_diff_pfx01 | 1000000 | 20        | id               |
| test          | user       | idx_a_b    | n_diff_pfx01 | 500     | 20        | a                |
| test          | user       | idx_a_b    | n_diff_pfx02 | 1000    | 20        | a,b              |
| test          | user       | idx_a_b    | n_diff_pfx03 | 2000    | 20        | a,b,id           |
| test          | user       | PRIMARY    | n_leaf_pages | 5000    | NULL      | Number of leaf pages |
| test          | user       | PRIMARY    | size         | 6000    | NULL      | Number of pages    |
+---------------+------------+------------+------------+-------------+----------+-------------------+
```

---

## 7.4 索引选择成本计算——MySQL 8.0 的成本模型

### MySQL 8.0 成本模型

MySQL 8.0 引入了更精细的成本模型，考虑不同 I/O 类型的代价差异：

```sql
-- 成本模型参数（mysql.server_cost_table 和 mysql.engine_cost_table）
SELECT * FROM mysql.server_cost_table;
+------------------------------+------------+---------------+
| cost_name                    | cost_value | default_value  |
+------------------------------+------------+---------------+
| disk_temptable_create_cost   | NULL       | 20.0           |
| disk_temptable_row_cost      | NULL       | 0.5            |
| key_compare_cost             | NULL       | 0.05           |
| memory_temptable_create_cost | NULL       | 1.0            |
| memory_temptable_row_cost    | NULL       | 0.1            |
| row_evaluate_cost            | NULL       | 0.1            |
+------------------------------+------------+---------------+

SELECT * FROM mysql.engine_cost_table;
+---------------+------------+------------------+------------+---------------+
| engine_name   | device_type | cost_name       | cost_value | default_value |
+---------------+------------+------------------+------------+---------------+
| innodb        | 0          | io_block_read_cost | NULL     | 1.0           |
| innodb        | 0          | memory_block_read_cost | NULL | 0.25         |
+---------------+------------+------------------+------------+---------------+
```

### 成本计算公式

```
索引访问成本：
  cost = (匹配行数 × row_evaluate_cost)  -- CPU 代价：评估每行的成本
       + (索引I/O页数 × io_block_read_cost)  -- 索引页I/O代价
       + (回表行数 × io_block_read_cost)  -- 回表I/O代价
       + (回表行数 × row_evaluate_cost)  -- 回表后评估每行的CPU代价

全表扫描成本：
  cost = (表总行数 × row_evaluate_cost)  -- CPU 代价
       + (聚簇索引叶页数 × io_block_read_cost)  -- 顺序I/O代价
       × memory_block_read_cost / io_block_read_cost  -- 如果页在Buffer Pool中

选择逻辑：
  → 索引成本 < 全表扫描成本 → 走索引
  → 索引成本 > 全表扫描成本 → 走全表扫描
```

---

## 7.5 紧索引扫描 vs 松索引扫描

### 紧索引扫描（Tight Index Scan）

```
紧索引扫描 = 使用联合索引的最左前缀条件定位范围 → 在范围内扫描过滤

适用：WHERE 条件包含最左前缀列的等值或范围条件

示例：
  索引 (a, b, c)
  WHERE a = 1 AND b IN (1, 2) AND c = 3
  
  → a=1 等值 → 定位
  → b IN (1,2) → 在 a=1 范围内扫描 b=1 和 b=2
  → c=3 → 逐行过滤
```

### 松索引扫描（Loose Index Scan）

```
松索引扫描 = 利用索引的有序性跳跃式扫描，只读取每个不同值的第一条记录

适用：GROUP BY 查询中，分组列是索引的最左前缀列

示例：
  索引 (a, b, c)
  SELECT a, COUNT(*) FROM user GROUP BY a;
  
  → 紧扫描：沿叶子链表扫描所有记录，逐个统计每组的行数
  → 松扫描：直接跳跃读取每个不同 a 值的第一条记录 → 更快
  
  松扫描的条件：
  → GROUP BY 的列是索引的最左前缀
  → 查询中没有聚合函数以外的其他列引用（或聚合函数是 MIN/MAX）
  → 没有 WHERE 条件（或 WHERE 条件也是最左前缀等值）
```

---

## 7.6 索引合并（Index Merge）——Intersection / Union / Sort-Union

### 索引合并的定义

**索引合并 = 对多个索引分别扫描，然后合并结果**

```sql
CREATE INDEX idx_a ON user(a);
CREATE INDEX idx_b ON user(b);

-- Intersection Merge（交集合并）
SELECT * FROM user WHERE a = 1 AND b = 2;
→ 优化器可能选择：
  1. 用 idx_a 找到所有 a=1 的主键集合 → {1, 3, 5, 7, ...}
  2. 用 idx_b 找到所有 b=2 的主键集合 → {2, 3, 5, 8, ...}
  3. 取交集 → {3, 5, ...}
  4. 用交集主键回表到聚簇索引

EXPLAIN:
  type=index_merge
  key=idx_a,idx_b
  Extra=Using intersect(idx_a,idx_b); Using where

适用条件：
  → 每个索引的条件都是等值（= / IN）
  → 每个索引的选择率都较高（匹配行少）
  → 没有覆盖联合索引 (a, b)

-- Union Merge（并集合并）
SELECT * FROM user WHERE a = 1 OR b = 2;
→ 用 idx_a 找到 a=1 → 用 idx_b 找到 b=2 → 合并去重 → 回表
EXPLAIN: Extra=Using union(idx_a,idx_b); Using where

-- Sort-Union Merge（排序并集合并）
SELECT * FROM user WHERE a > 1 OR b < 5;
→ 两个范围条件 → 先排序再合并
EXPLAIN: Extra=Using sort_union(idx_a,idx_b); Using where
```

### 索引合并 vs 联合索引

```
索引合并的问题：
  → 需要扫描多个索引 → 多次索引 I/O
  → 合并操作需要额外内存和 CPU
  → 回表量可能很大（交集小 → 回表多但结果少）

联合索引的优势：
  → 一个索引搞定所有条件 → 一次索引 I/O
  → 不需要合并 → 无额外 CPU 开销
  → 回表量 = 结果行数（精确匹配）

最佳实践：
  → 索引合并是"没有合适联合索引时的退路"
  → 看到 Using intersect → 考虑建联合索引
  → 看到 Using union → 考虑建联合索引或改写查询
```

---

## 7.7 优化器 Trace——OPTIMIZER_TRACE 分析索引选择

```sql
-- 开启优化器 Trace
SET optimizer_trace='enabled=on';

-- 执行查询
SELECT * FROM user WHERE a = 1 AND b = 2;

-- 查看 Trace
SELECT * FROM information_schema.OPTIMIZER_TRACE;
```

### Trace 中的关键信息

```
OPTIMIZER_TRACE 输出 JSON，包含：

1. steps[0]: "join_preparation" — SQL 解析和条件提取
2. steps[1]: "join_optimization" — 优化过程
   → range_optimizer: 分析每个索引的可选范围
     → index_scan: 每个索引的代价估算
       → index=idx_a_b: rows_estimated=100, cost=10.5
       → index=idx_a: rows_estimated=500, cost=50.3
     → table_scan: 全表扫描的代价
       → rows=1000000, cost=2000.5
   → best_range_plan: 选择 idx_a_b（代价最低）
   → reconsidering_access_paths_for_index_ordering: 
     ORDER BY 是否影响索引选择
3. steps[2]: "join_execution" — 执行过程

关键分析点：
  → 如果优化器选了"错"的索引 → 看 range_optimizer 的各索引代价估算
  → 如果 Cardinality 不准确 → 估算行数偏大 → 选了全表扫描
  → 如果 FORCE INDEX 改善 → 说明统计信息有偏差 → ANALYZE TABLE
```

---

## 7.8 FORCE INDEX / USE INDEX——绕过优化器的选择

```sql
-- 强制使用指定索引（不走全表扫描）
SELECT * FROM user FORCE INDEX (idx_a_b) WHERE a = 1;

-- 建议使用指定索引（优化器仍然可以选择不用的权利）
SELECT * FROM user USE INDEX (idx_a_b) WHERE a = 1;

-- 禁止使用指定索引
SELECT * FROM user IGNORE INDEX (idx_a_b) WHERE a = 1;

使用场景：
  → 优化器选了全表扫描但你知道索引更优 → FORCE INDEX
  → 优化器选了低效索引 → FORCE INDEX 指定高效索引
  → 临时排查性能问题 → 先 FORCE INDEX 验证 → 再 ANALYZE TABLE 修复统计信息

注意：
  → FORCE INDEX 是临时方案 → 长期方案应该修复统计信息
  → 数据量变化后 FORCE INDEX 可能反而更慢 → 需要定期审查
```

---

# 第八部分：索引失效场景全面解析

## 8.1 索引失效的 12 种典型场景

```
索引失效速查（12 种场景）：

 1. WHERE 条件中对索引列使用函数/计算        → ❌ 索引失效
 2. WHERE 条件中对索引列隐式类型转换          → ❌ 索引失效
 3. LIKE '%xxx' 前缀通配符                    → ❌ 索引失效
 4. OR 条件中一侧无索引                       → ❌ 索引失效
 5. NOT IN / NOT EXISTS / !=                  → ⚠️ 可能失效
 6. 范围查询之后的列                          → ❌ 最左前缀失效
 7. 索引列顺序颠倒（等值条件可纠正）          → ⚠️ 优化器可能纠正
 8. 隐式类型转换（字符串列传数字）            → ❌ 紁引失效
 9. 索引选择率太低（匹配行太多）              → ❌ 优化器选全表扫描
10. 索引列 IS NULL（B+Tree 不存 NULL 行）     → ⚠️ 取决于列定义
11. 事务隔离级别导致索引锁升级                → ⚠️ 间接影响
12. 紁引统计信息过期                          → ⚠️ 优化器选错索引
```

---

## 8.2 函数/计算导致索引失效

```sql
CREATE INDEX idx_create_time ON user(create_time);

-- ❌ 对索引列使用函数
SELECT * FROM user WHERE YEAR(create_time) = 2024;
→ YEAR() 函数破坏了 B+Tree 的有序性
→ 紁引无法定位 YEAR(create_time)=2024 的范围
→ 全表扫描

-- ✅ 改写为范围查询
SELECT * FROM user 
WHERE create_time >= '2024-01-01' AND create_time < '2025-01-01';
→ 范围查询 → 紁引有序 → 可以定位
→ EXPLAIN: type=range, key=idx_create_time ✅

-- ❌ 对索引列做计算
SELECT * FROM user WHERE id + 1 = 1000;
→ id + 1 破坏了 B+Tree 有序性
→ 全表扫描

-- ✅ 改写
SELECT * FROM user WHERE id = 999;
→ 等值查询 → 紁引定位 ✅

-- ❌ 对索引列做运算
SELECT * FROM user WHERE id * 2 > 100;
→ 全表扫描

-- ✅ 改写
SELECT * FROM user WHERE id > 50;
→ 范围查询 → 紁引 ✅

-- MySQL 8.0 函数索引（新特性）
CREATE INDEX idx_year ON user((YEAR(create_time)));
SELECT * FROM user WHERE YEAR(create_time) = 2024;
→ 现在可以用函数索引了！
→ EXPLAIN: key=idx_year ✅
```

---

## 8.3 类型转换导致索引失效

```sql
CREATE INDEX idx_phone ON user(phone);  -- phone 是 VARCHAR

-- ❌ 传入数字值 → 隐式类型转换
SELECT * FROM user WHERE phone = 13800138000;
→ MySQL 将 phone 列转为数字再比较（对每个值调用 CAST 函数）
→ 相当于 WHERE CAST(phone AS SIGNED) = 13800138000
→ 对索引列使用函数 → 紁引失效！

-- ✅ 传入字符串值
SELECT * FROM user WHERE phone = '13800138000';
→ 类型匹配 → 紁引正常使用 ✅

规则：
  → 紁引列是字符串 → WHERE 条件必须传字符串
  → 紁引列是数字 → WHERE 条件可以传字符串（MySQL 自动转数字，不影响索引）
  
  为什么字符串→数字会失效？
  → MySQL 的隐式转换规则：当类型不一致时，将字符串转为数字
  → 字符串列传数字 → 对列做 CAST → 函数 → 紁引失效
  → 数字列传字符串 → 对常量做 CAST → 不影响列 → 紁引不失效
```

---

## 8.4 LIKE 前缀通配符导致索引失效

```sql
CREATE INDEX idx_name ON user(name);

-- ✅ 前缀 LIKE
SELECT * FROM user WHERE name LIKE 'Ali%';
→ 可以转化为范围查询 → 紁引有效

-- ❌ 中缀/后缀 LIKE
SELECT * FROM user WHERE name LIKE '%li%';
→ 无法转化为范围查询 → 全表扫描

SELECT * FROM user WHERE name LIKE '%ce';
→ 无法转化为范围查询 → 全表扫描

-- ⚠️ 前缀 LIKE 的长度限制
-- 如果前缀太短（只有1个字符）→ 选择率太低 → 优化器可能选全表扫描
SELECT * FROM user WHERE name LIKE 'A%';
→ 如果 A 开头的名字占 30% → 全表扫描更快 → 紁引被优化器放弃
```

---

## 8.5 OR 条件导致索引失效

```sql
CREATE INDEX idx_a ON user(a);
-- 没有 b 列的索引

-- ❌ OR 一侧无索引
SELECT * FROM user WHERE a = 1 OR b = 2;
→ a=1 可以用 idx_a → b=2 无索引 → 全表扫描
→ 优化器：OR 条件要求两侧都有索引才能用索引合并
→ 一侧无索引 → 全表扫描

-- ✅ OR 两侧都有索引
CREATE INDEX idx_b ON user(b);
SELECT * FROM user WHERE a = 1 OR b = 2;
→ a=1 用 idx_a → b=2 用 idx_b → 紁引合并 Union
→ EXPLAIN: type=index_merge, Extra=Using union(idx_a,idx_b)

-- ✅ 改写为 UNION
SELECT * FROM user WHERE a = 1
UNION
SELECT * FROM user WHERE b = 2;
→ 两条查询分别走不同索引 → 合并结果
```

---

## 8.6 NOT IN / NOT EXISTS 导致索引失效

```sql
-- NOT IN
SELECT * FROM user WHERE a NOT IN (1, 2, 3);
→ NOT IN 等价于 a <> 1 AND a <> 2 AND a <> 3
→ != 条件无法转化为范围查询 → 全表扫描（大多数场景）
→ 如果 a 的值只有 1,2,3,4 → NOT IN (1,2,3) 等价于 a=4 → 可以用索引
→ 但大多数场景 NOT IN 匹配大量行 → 全表扫描更优

-- NOT EXISTS
SELECT * FROM user WHERE NOT EXISTS (SELECT 1 FROM order WHERE order.user_id = user.id);
→ NOT EXISTS 本身是子查询 → 不涉及索引失效问题
→ 但子查询的执行效率取决于子查询是否走索引

改写建议：
  → NOT IN 改写为 LEFT JOIN + IS NULL
  → NOT EXISTS 改写为 LEFT JOIN + IS NULL
  → 或使用反向索引查询（如果反面的值少）
```

---

## 8.7 范围查询之后的列索引失效

```sql
CREATE INDEX idx_a_b_c ON user(a, b, c);

-- ❌ a 范围后 b/c 无法用索引
SELECT * FROM user WHERE a > 1 AND b = 2;
→ a>1 范围查询 → 在 a>1 范围内 b 不全局有序
→ b=2 只能逐行过滤 → 紁引只用到 a 列
→ EXPLAIN: key_len=a列长度

-- ❌ a 等值 + b 范围后 c 无法用索引
SELECT * FROM user WHERE a = 1 AND b > 2 AND c = 3;
→ a=1 定位 → b>2 范围 → c 在 b>2 范围内无序
→ 紁引只用到 a+b → c 逐行过滤
→ EXPLAIN: key_len=a+b列长度

关键理解：
  → 范围条件之后的列在 B+Tree 中的有序性被"打破"
  → 不同范围值分组中后续列各自有序但全局无序
  → 范围条件 = 第一个"破坏"最左前缀连续性的条件
```

---

## 8.8 索引列顺序颠倒（可被优化器纠正）

```sql
CREATE INDEX idx_a_b ON user(a, b);

-- 等值条件顺序无关（优化器自动调整）
SELECT * FROM user WHERE b = 2 AND a = 1;
→ 优化器自动调整为 WHERE a = 1 AND b = 2
→ 匹配最左前缀 → 紁引正常使用
→ EXPLAIN: key=idx_a_b, key_len=a+b列长度 ✅

-- 范围条件顺序相关
SELECT * FROM user WHERE b > 2 AND a = 1;
→ 优化器调整为 WHERE a = 1 AND b > 2
→ 匹配最左前缀 a → b 范围 → 紁引使用 ✅

SELECT * FROM user WHERE a > 1 AND b = 2;
→ 无法调整 → a 范围在前 → b 无法用索引 ❌

注意：这里说的是 WHERE 条件中列的书写顺序
      紁引定义的列顺序（INDEX(a,b) vs INDEX(b,a）是固定的，不能被优化器调整
```

---

## 8.9 隐式类型转换的坑——字符串 vs 数字

```sql
-- 经典坑：手机号/订单号等字符串列传数字
CREATE INDEX idx_order_no ON order(order_no);  -- order_no VARCHAR(20)

-- ❌ 传数字 → 隐式转换 → 紁引失效
SELECT * FROM order WHERE order_no = 20240615;
→ MySQL 将 order_no 列转为数字：CAST(order_no AS SIGNED)
→ 等价于对每行调用 CAST 函数 → 紁引失效
→ 全表扫描

-- ✅ 传字符串 → 类型匹配 → 紁引正常
SELECT * FROM order WHERE order_no = '20240615';
→ 类型匹配 → 紁引定位 ✅

MySQL 隐式转换规则（源码层面）：
  → 两个值比较时，如果类型不同 → 将字符串转为数字
  → 字符串列 vs 数字常量 → 对列做 CAST → 紁引失效
  → 数字列 vs 字符串常量 → 对常量做 CAST → 不影响列 → 紁引不失效
  
  示例：
    id(INT) = '1' → 将 '1' 转为 1 → 等价于 id = 1 → 紁引正常 ✅
    phone(VARCHAR) = 138 → 将 phone 转为数字 → 紁引失效 ❌

防范建议：
  → 永远保持 WHERE 条件值与索引列类型一致
  → 字符串列传字符串，数字列传数字
  → 使用参数化查询（PreparedStatement）→ 自动类型匹配
```

---

## 8.10 索引选择率太低——全表扫描比索引更快

```sql
CREATE INDEX idx_gender ON user(gender);  -- gender 只有 'M'/'F' 两个值

-- ❌ 选择率太低 → 全表扫描更优
SELECT * FROM user WHERE gender = 'M';
→ gender='M' 匹配约 50% 的行 → 100 万行中有 50 万行匹配
→ 紁引 + 回表：扫描 50 万行 → 每行回表 → 50 万次随机 I/O
→ 全表扫描：顺序扫描聚簇索引 → 100 万行顺序 I/O
→ 顺序 I/O 比 50 万次随机 I/O 快得多 → 优化器选择全表扫描

-- ✅ 高选择率列走索引
CREATE INDEX idx_email ON user(email);  -- email 基本唯一
SELECT * FROM user WHERE email = 'alice@example.com';
→ 匹配约 1 行 → 紁引 + 回表 ≈ 3+3 = 6 次 I/O
→ 全表扫描 ≈ 几千次 I/O → 紁引快得多

选择率阈值：
  → 一般认为选择率 > 15-30% 时，全表扫描更优
  → 具体取决于 Buffer Pool 大小、页在内存中的比例等
  → 优化器根据成本模型自动判断
  
低选择率索引的应对：
  → 不建索引（gender 这种列不需要索引）
  → 或者与高选择率列组合建联合索引 (gender, email)
  → 用覆盖索引避免回表（如果只需要少数列）
```

---

## 8.11 事务隔离级别对索引的影响

```
事务隔离级别间接影响索引使用：

1. MVCC 与二级索引
   → 二级索引叶子不存 DB_TRX_ID 和 DB_ROLL_PTR
   → 二级索引的 MVCC 检查需要回表到聚簇索引
   → 在 RR 隔离级别下，即使二级索引覆盖了查询列
     → 仍然可能回表检查 MVCC 可见性
   → 这可能破坏覆盖索引的"Using index"效果

2. Next-Key Lock 与索引
   → RR 隔离级别下，InnoDB 使用 Next-Key Lock 防止幻读
   → Next-Key Lock 锁定的范围取决于索引
   → 没有索引时 → Next-Key Lock 锁定整张表！
   → 有索引时 → Next-Key Lock 只锁定索引范围内的间隙

   示例：
   DELETE FROM user WHERE a = 5;
   → 有 idx_a 紁引 → 锁定 (3, 5) 和 (5, 7) 两个间隙
   → 无索引 → 锁定 (-∞, +∞) 全表 → 其他事务无法 INSERT
   
3. 死锁与索引
   → 不同事务用不同索引顺序访问 → 可能死锁
   → 事务 A: UPDATE WHERE a=1 → UPDATE WHERE b=2
   → 事务 B: UPDATE WHERE b=2 → UPDATE WHERE a=1
   → 两个事务按不同索引顺序锁定行 → 死锁

防范建议：
  → 确保 WHERE 条件有索引 → 避免全表 Next-Key Lock
  → 统一访问顺序 → 避免死锁
```

---

## 8.12 索引失效速查表

```
┌──────────────────────────────────────────────────────────────┐
│                    紁引失效速查表                              │
├──────────────────────────────────────┬───────────────────────┤
│ 场景                                 │ 是否失效               │
├──────────────────────────────────────┼───────────────────────┤
│ 对索引列使用函数                     │ ❌ 失效               │
│ 对索引列做计算                       │ ❌ 失效               │
│ 字符串列传数字（隐式转换）           │ ❌ 失效               │
│ 数字列传字符串（隐式转换）           │ ✅ 不失效             │
│ LIKE 'xxx%'（前缀通配符）           │ ✅ 不失效             │
│ LIKE '%xxx%'（中缀/后缀通配符）     │ ❌ 失效               │
│ OR 一侧无索引                       │ ❌ 失效               │
│ OR 两侧都有索引                     │ ✅ 紁引合并           │
│ NOT IN / !=（低选择率）             │ ⚠️ 可能全表扫描      │
│ IS NULL（列允许 NULL）              │ ✅ 不失效             │
│ IS NOT NULL                         │ ⚠️ 可能失效           │
│ 范围查询之后的列                    │ ❌ 最左前缀失效       │
│ 跳过联合索引中间列                  │ ⚠️ 部分失效(ICP可用) │
│ WHERE 列顺序颠倒（等值）            │ ✅ 优化器可纠正      │
│ WHERE 列顺序颠倒（范围在前）        │ ❌ 后续列失效         │
│ ORDER BY 非最左列                   │ ❌ Filesort          │
│ GROUP BY 非最左列                   │ ❌ Using temporary   │
│ 匹配行数太多（低选择率）            │ ❌ 优化器选全表扫描   │
│ 统计信息过期                        │ ⚠️ 优化器选错索引    │
│ FORCE INDEX 绕过优化器              │ ✅ 不失效             │
└──────────────────────────────────────┴───────────────────────┘
```

---

# 第九部分：InnoDB Buffer Pool 与索引页缓存

## 9.1 Buffer Pool 架构——LRU List + Free List + Flush List

### Buffer Pool 的三个核心链表

```
┌──────────────────────────────────────────────────────────────┐
│                  Buffer Pool 架构                              │
│                                                              │
│  ┌─ Free List ──────────────────────────────────────────────┐│
│  │  空闲页链表：未被使用的页                                   ││
│  │  → 初始化时所有页都在 Free List                             ││
│  │  → 当需要读新页时 → 从 Free List 取一个空闲页               ││
│  │  → Free List 耗尽 → 需要从 LRU List 淘汰页                ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌─ LRU List ──────────────────────────────────────────────┐│
│  │  最近使用页链表：被访问过的页                               ││
│  │  → 改进的 LRU：分为 Young Sublist 和 Old Sublist          ││
│  │  → Young Sublist (5/8)：热数据区 → 最近被频繁访问的页      ││
│  │  → Old Sublist (3/8)：冷数据区 → 最近被访问但未确认"热"的页││
│  │                                                            ││
│  │  ┌── Young Sublist ──┐    ┌── Old Sublist ──┐           ││
│  │  │ 热页: Head→...→Mid │←──→│ 冷页: Mid→...→Tail│           ││
│  │  │ (37.5% of LRU)    │    │ (62.5% of LRU)   │           ││
│  │  └───────────────────┘    └───────────────────┘           ││
│  │                                                            ││
│  │  淘汰策略：从 Old Sublist Tail 淘汰                        ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌─ Flush List ─────────────────────────────────────────────┐│
│  │  脏页链表：被修改但未刷盘的页                               ││
│  │  → 页被修改后 → 加入 Flush List                           ││
│  │  → 刷盘策略：LRU 刷盘 / Async 刷盘 / Sync 刷盘            ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## 9.2 Buffer Pool 的改进 LRU——冷热分区（old sublist / young sublist）

### 改进 LRU 的工作流程

```
改进 LRU 的核心思想：
  → 防止"一次扫描污染整个 Buffer Pool"
  → 例如：全表扫描 100 万行 → 如果每行读一页 → 100 万页进入 LRU
  → 如果 LRU 大小只有 10 万页 → 所有热页被淘汰 → Buffer Pool 被污染
  → 下次查询热数据 → 需要重新从磁盘读取 → 性能暴跌

改进 LRU 的解决方案：
  → 新读入的页先进入 Old Sublist（冷区） → 不直接进入 Young Sublist
  → 如果在 Old Sublist 中被再次访问（innodb_old_blocks_time 间隔内）
     → 才晋升到 Young Sublist（热区）
  → 如果没有被再次访问 → 仍然在 Old Sublist → 下次淘汰时优先淘汰

innodb_old_blocks_time 参数：
  → 默认 1000ms（1秒）
  → 页进入 Old Sublist 后 1000ms 内再次被访问 → 晋升到 Young
  → 页进入 Old Sublist 后 1000ms 后再被访问 → 也晋升到 Young
  → 但全表扫描通常每页只访问一次 → 不会晋升 → 会被淘汰

流程图：
  ┌──────────────────────────────────────────────────────┐
  │  1. 新页读入 Buffer Pool                              │
  │     → 放到 Old Sublist 的 Head（Mid Point）           │
  │                                                       │
  │  2a. 如果在 innodb_old_blocks_time 内再次访问          │
  │     → 晋升到 Young Sublist 的 Head                    │
  │     → 成为"热页"                                     │
  │                                                       │
  │  2b. 如果在 innodb_old_blocks_time 后再次访问          │
  │     → 晋升到 Young Sublist 的 Head                    │
  │     → 成为"热页"                                     │
  │                                                       │
  │  2c. 如果没有被再次访问                               │
  │     → 仍在 Old Sublist                               │
  │     → 淘汰时优先淘汰                                  │
  │                                                       │
  │  3. Young Sublist 满时                                │
  │     → Young Sublist 的 Tail 移到 Old Sublist 的 Head │
  │     → Old Sublist 的 Tail 被淘汰                      │
  └──────────────────────────────────────────────────────┘
```

---

## 9.3 页的读取与预读机制——线性预读与随机预读

### 预读（Read-Ahead）机制

```
InnoDB 的两种预读：

1. 线性预读（Linear Read-Ahead）
   → 检测到顺序访问模式（连续读取同一个 Extent 中的页）
   → 当一个 Extent 中超过 innodb_read_ahead_threshold（默认56）个页被顺序读取
   → 预读下一个 Extent 的所有页
   
   参数：innodb_read_ahead_threshold = 56（默认）
   → 一个 Extent 有 64 页 → 56/64 ≈ 88% 被顺序读取 → 触发预读
   
   适用场景：全表扫描、大范围索引扫描

2. 随机预读（Random Read-Ahead）
   → 检测到随机访问模式（同一个 Extent 中的页被随机访问）
   → 当一个 Extent 中超过 13 个页被读取（不论顺序）
   → 预读该 Extent 的剩余页
   
   默认关闭：innodb_random_read_ahead = OFF
   → 随机预读的效果不稳定 → 可能浪费 I/O
   
   适用场景：热点数据分散在一个 Extent 中

预读的源码实现：
  buf0rea.cc 中的 buf_read_ahead_linear() 和 buf_read_ahead_random()
  → 监控每个 Extent 的访问模式
  → 当触发条件满足时 → 一次性预读多个页到 Buffer Pool
```

---

## 9.4 页的修改与脏页刷盘——Flush List 与刷盘策略

```
脏页刷盘的触发条件：

1. LRU 刀片淘汰（Flush from LRU）
   → Buffer Pool 空间不足 → 从 Old Sublist Tail 淘汰页
   → 如果淘汰的是脏页 → 先刷盘再淘汰
   → 源码：buf0flu.cc 中的 buf_flush_LRU_list()

2. Async Flush（异步刷盘）
   → 脏页比例超过 innodb_max_dirty_pages_pct（默认75%）
   → 后台线程异步刷盘 → 不阻塞用户线程
   → 源码：buf0flu.cc 中的 buf_flush_async()

3. Sync Flush（同步刷盘）
   → 脏页比例超过 innodb_max_dirty_pages_pct_lwm（默认0%）
   → 强制同步刷盘 → 阻塞用户线程
   → 极端情况（Redo Log 空间不足时）才触发

4. Sharp Checkpoint（完全检查点）
   → 正常关闭 MySQL 时 → 将所有脏页刷盘
   → shutdown 时执行 → 确保数据一致性

5. Fuzzy Checkpoint（模糊检查点）
   → 运行期间定期刷盘 → 不一次性刷完所有脏页
   → 后台线程每秒刷一定数量的脏页
   → 参数：innodb_io_capacity（默认200 → 每秒最多200次I/O）
   → 参数：innodb_io_capacity_max（默认400 → 紧急时最多400次I/O）

刷盘线程：
  → InnoDB 有多个后台线程负责刷盘
  → Page Cleaner Thread：专门负责刷脏页（MySQL 5.7+）
  → Master Thread：也负责部分刷盘工作
```

---

## 9.5 Buffer Pool 对索引查询性能的影响

```
Buffer Pool 对索引查询的影响：

1. 页在 Buffer Pool 中 → 0 次 I/O（直接从内存读取）
   → 3 层 B+Tree 的查找 → 如果 Root 和中间层都在 Buffer Pool
   → 只需要 1 次 I/O（读叶子页）
   → 甚至如果叶子页也在 Buffer Pool → 0 次 I/O

2. 页不在 Buffer Pool 中 → 1 次 I/O（从磁盘读取）
   → 3 层 B+Tree → 最多 3 次 I/O
   → 但 Root 页几乎永远在 Buffer Pool（热页）
   → 中间层页大部分也在 Buffer Pool（热页）
   → 通常只需 1 次 I/O（读叶子页）

3. 范围查询的 Buffer Pool 效果
   → 范围查询扫描多个叶子页 → 如果页在 Buffer Pool → 顺序扫描极快
   → 如果页不在 Buffer Pool → 需要预读机制 → 线性预读加速
   → 预读可以将多个页一次性读入 Buffer Pool → 减少随机 I/O

4. 回表的 Buffer Pool 效果
   → 二级索引回表 → 随机访问聚簇索引页
   → 如果聚簇索引页在 Buffer Pool → 回表很快
   → 如果不在 → 随机 I/O → MRR 可以优化（排序主键 → 变半顺序I/O）

配置建议：
  → innodb_buffer_pool_size = 物理内存的 60-80%
  → 越大 → 更多页在内存 → 更少磁盘 I/O → 更快
  → 但不要超过物理内存 → 避免 OOM
```

---

## 9.6 Multiple Buffer Pool Instance——并发优化

```
Multiple Buffer Pool Instance：

  → MySQL 5.5+ 支持多个 Buffer Pool Instance
  → 参数：innodb_buffer_pool_instances（默认1，推荐8或更多）
  → 每个 Instance 有自己的 LRU List、Free List、Flush List
  → 减少锁竞争 → 多线程并发访问不同 Instance → 互不阻塞

  配置要求：
  → innodb_buffer_pool_size >= 1GB 时才能使用多个 Instance
  → 每个 Instance 至少 1GB

  源码层面：
  → buf0buf.cc 中的 buf_pool_get() → 根据页号的 hash 值选择 Instance
  → 不同页号的请求自动路由到不同 Instance
  → 减少单个 Instance 的 mutex 争用
```

---

## 9.7 Change Buffer——二级索引的异步变更合并

### Change Buffer 的定义

```
Change Buffer = 对二级索引页的变更（INSERT/UPDATE/DELETE）先缓存在 Change Buffer 中
               → 后续读取该页时再合并变更

为什么需要 Change Buffer？
  → 二级索引的变更通常是随机 I/O（因为二级索引不按主键排序）
  → 聚簇索引的变更通常是顺序 I/O（自增主键时）
  → 二级索引的随机 I/O 是性能瓶颈
  → Change Buffer 将随机 I/O 延后 → 在页被读取时一次性合并 → 变为顺序 I/O

Change Buffer 的适用条件：
  → 只适用于二级索引（非唯一索引）
  → 唯一索引不能用 Change Buffer → 因为需要立即检查唯一性冲突
  → 聚簇索引不能用 Change Buffer → 因为数据行必须立即更新

Change Buffer 的流程：
  ┌────────────────────────────────────────────────────────┐
  │  1. INSERT/UPDATE/DELETE 二级索引                      │
  │     → 检查目标页是否在 Buffer Pool                    │
  │                                                        │
  │  1a. 页在 Buffer Pool → 直接修改页（不经过 Change Buffer）│
  │  1b. 页不在 Buffer Pool → 变更记录存入 Change Buffer   │
  │                                                        │
  │  2. 后续 SELECT 查询需要读取该页                       │
  │     → 从磁盘读取页到 Buffer Pool                       │
  │     → 合并 Change Buffer 中的变更记录                  │
  │     → 返回合并后的数据                                 │
  │                                                        │
  │  3. 后台线程定期合并 Change Buffer                     │
  │     → Master Thread / Page Cleaner Thread              │
  │     → 在空闲时合并 → 避免高峰期影响性能                │
  └────────────────────────────────────────────────────────┘
```

### Change Buffer 的参数

```sql
-- Change Buffer 的类型（MySQL 5.5+）
SET GLOBAL innodb_change_buffering = 'all';  -- 默认：缓存 INSERT + DELETE + PURGE
-- 可选值：none / inserts / deletes / changes(inserts+deletes) / purges / all

-- Change Buffer 的最大大小
SET GLOBAL innodb_change_buffer_max_size = 25;  -- 默认：最多占 Buffer Pool 的 25%
-- 调大 → 缓存更多变更 → 减少随机 I/O → 但占用 Buffer Pool 空间

-- 监控 Change Buffer
SHOW ENGINE INNODB STATUS;
→ 查看 "INSERT BUFFER AND ADAPTIVE HASH INDEX" 部分
→ 显示 Change Buffer 中的变更数量和合并统计
```

---

## 9.8 Buffer Pool 配置与监控

```sql
-- 核心配置参数
SET GLOBAL innodb_buffer_pool_size = 8G;  -- Buffer Pool 大小（最重要！）
SET GLOBAL innodb_buffer_pool_instances = 8;  -- Instance 数量
SET GLOBAL innodb_old_blocks_time = 1000;  -- 冷页晋升等待时间（ms）
SET GLOBAL innodb_read_ahead_threshold = 56;  -- 线性预读阈值

-- 监控 Buffer Pool
SHOW ENGINE INNODB STATUS;
→ Buffer Pool size: 524288 pages (8GB)
→ Free buffers: 100 pages
→ Database pages: 524188 pages
→ Old database pages: 196593 pages (37.5%)
→ Modified db pages: 50000 pages (脏页)
→ Pending reads: 0
→ Pending writes: LRU 0, flush list 0, single page 0

-- Buffer Pool 命中率
SHOW STATUS LIKE 'Innodb_buffer_pool_read%';
→ Innodb_buffer_pool_read_requests: 10000000  (总读请求)
→ Innodb_buffer_pool_reads: 50000  (磁盘读次数)
→ 命中率 = (10000000 - 50000) / 10000000 = 99.5%
→ 命中率应 > 95% → 否则说明 Buffer Pool 太小

-- Buffer Pool 预读
SHOW STATUS LIKE 'Innodb_buffer_pool_read_ahead%';
→ Innodb_buffer_pool_read_ahead: 10000  (预读页数)
→ Innodb_buffer_pool_read_ahead_evicted: 500  (预读后被淘汰的页数)
→ 预读浪费率 = 500 / 10000 = 5% → 较低 → 预读效果好
```

---

# 第十部分：索引设计原则与实战

## 10.1 索引设计的基本原则

```
索引设计 8 条基本原则：

1. 选择高选择率列做索引
   → 选择率 > 0.15-0.3 → 值建索引
   → 选择率 < 0.05 → 不建索引（全表扫描更优）
   → 示例：email 列（接近唯一）→ 建索引 ✅
           gender 列（只有 M/F）→ 不建索引 ❌

2. 联合索引优于多个单列索引
   → (a, b) 联合索引 > idx_a + idx_b 两个单列索引
   → 联合索引一次 I/O 解决 → 紁引合并多次 I/O

3. 联合索引列顺序：区分度高的列放左边
   → (email, gender) > (gender, email)
   → email 选择率高 → 放左边 → 最左前缀过滤效果更好
   → 但也要考虑查询模式 → WHERE 条件最常出现的列放左边

4. 避免冗余索引和重复索引
   → (a, b) 联合索引已经包含了 a 列的索引
   → 再建 idx_a 单列索引 → 冗余 → 浪费空间和 DML 性能

5. 覆盖索引减少回表
   → 查询只需少数列 → 建覆盖索引 → Using index → 无回表

6. 控制索引数量
   → 每个索引增加 INSERT/UPDATE/DELETE 的开销
   → 单表索引数建议不超过 5-6 个

7. 自增主键优于随机主键
   → 自增主键 → 顺序插入 → 不触发页分裂 → 页填充率高
   → UUID 主键 → 随机插入 → 频繁页分裂 → 页碎片多 → 性能差

8. 定期维护索引
   → ANALYZE TABLE 更新统计信息
   → 检查 Cardinality 是否准确
   → 删除不再使用的索引
```

---

## 10.2 联合索引列顺序选择——区分度高的列放左边

### 列顺序选择的两个维度

```
维度一：区分度（选择率）
  → 区分度高的列放左边 → 最左前缀过滤效果好
  → email 区分度 > gender 区分度 → (email, gender) 优于 (gender, email)

维度二：查询模式
  → 最常出现在 WHERE 条件中的列放左边
  → 如果大部分查询是 WHERE gender='M' AND email='xxx'
  → 虽然 email 区分度高，但 WHERE 条件都包含两列 → 列顺序影响不大
  → 如果大部分查询是 WHERE gender='M'（只查 gender）
  → (gender, email) 更优 → 因为 gender 在左边 → 最左前缀匹配

权衡：
  → 如果查询总是包含所有列 → 区分度顺序优先
  → 如果查询只包含部分列 → 查询模式优先
  → 通常：区分度优先 → 因为高区分度列在最左 → 单列查询也能用索引
```

### 实战案例

```sql
-- 假设表 user 有列：city, age, name, gender
-- city 有 50 个不同值 → 选择率 = 50/1000000 = 0.00005
-- age 有 100 个不同值 → 选择率 = 100/1000000 = 0.0001
-- name 有 500000 个不同值 → 选择率 = 500000/1000000 = 0.5
-- gender 有 2 个不同值 → 选择率 = 2/1000000 = 0.000002

-- 查询模式1：WHERE city=? AND age=? AND name=? → 全列匹配 → 任意顺序
-- 查询模式2：WHERE city=? AND name=? → (city, name, age) 或 (name, city, age)
-- 查询模式3：WHERE name=? → name 在最左 → (name, city, age)

-- 综合考虑：
-- 如果大部分查询包含 name → name 放最左
CREATE INDEX idx_name_city_age ON user(name, city, age);
→ WHERE name=? → 用索引
→ WHERE name=? AND city=? → 用索引
→ WHERE name=? AND city=? AND age=? → 用索引

→ 但 WHERE city=? → 不能用索引（跳过 name）
→ 如果 WHERE city=? 也很常见 → 另建 idx_city 单列索引
```

---

## 10.3 避免冗余索引与重复索引

```sql
-- 重复索引：两个索引的列完全相同
CREATE INDEX idx_a ON user(a);      -- 单列索引 a
CREATE INDEX idx_a2 ON user(a);     -- 重复！完全冗余
→ 删除其中一个 → 浪费空间和 DML 性能

-- 冗余索引：联合索引已经覆盖了单列索引
CREATE INDEX idx_a_b ON user(a, b); -- 联合索引 (a, b)
CREATE INDEX idx_a ON user(a);      -- 冗余！联合索引已经包含 a 列的索引
→ WHERE a=? → 可以用 idx_a_b（最左前缀匹配 a）
→ idx_a 完全冗余 → 删除

-- 不冗余的情况：
CREATE INDEX idx_a_b ON user(a, b); -- 联合索引 (a, b)
CREATE INDEX idx_b ON user(b);      -- 不冗余！
→ WHERE b=? → 不能用 idx_a_b（跳过最左列 a）
→ 需要单独的 idx_b

-- 检查冗余索引的 SQL
SELECT 
    s.table_schema, s.table_name, s.index_name, s.column_name,
    s.seq_in_index
FROM information_schema.statistics s
JOIN information_schema.statistics s2
    ON s.table_schema = s2.table_schema
    AND s.table_name = s2.table_name
    AND s.seq_in_index = s2.seq_in_index
    AND s.column_name = s2.column_name
    AND s.index_name != s2.index_name
GROUP BY s.table_schema, s.table_name, s.index_name
ORDER BY s.table_schema, s.table_name;
```

---

## 10.4 前缀索引——长字符串列的索引优化

```sql
-- 问题：VARCHAR(255) 的列建完整索引 → 紁引太长 → 页存键少 → B+Tree 更高 → I/O 更多
CREATE INDEX idx_email ON user(email);  -- email VARCHAR(255)
→ 每个索引键约 255 字节 → 非叶子页只能存约 16KB/255 ≈ 63 个键
→ B+Tree 更高 → I/O 更多

-- 解决：前缀索引
CREATE INDEX idx_email ON user(email(20));  -- 只索引前 20 个字符
→ 每个索引键约 20 字节 → 非叶子页能存约 16KB/20 ≈ 800 个键
→ B+Tree 更矮 → I/O 更少

-- 前缀索引的缺点：
→ 无法做覆盖索引（因为索引只存前 20 个字符，不是完整值）
→ 无法做 ORDER BY / GROUP BY 精确排序
→ 等值查询可能不精确（email 前 20 字符相同但完整值不同）
→ 需要回表验证完整值

-- 前缀长度的选择
→ 选择让前缀的区分度接近完整列的区分度
→ 方法：
SELECT 
    COUNT(DISTINCT LEFT(email, 5)) / COUNT(*) AS prefix_5,
    COUNT(DISTINCT LEFT(email, 10)) / COUNT(*) AS prefix_10,
    COUNT(DISTINCT LEFT(email, 20)) / COUNT(*) AS prefix_20,
    COUNT(DISTINCT email) / COUNT(*) AS full_column
FROM user;
→ 选择使 prefix_ratio ≈ full_ratio 的最短前缀长度
```

---

## 10.5 函数索引——MySQL 8.0 的新特性

```sql
-- MySQL 8.0 支持函数索引（实质上是基于虚拟列的索引）

-- 场景1：日期列的年份查询
CREATE INDEX idx_year ON user((YEAR(create_time)));
SELECT * FROM user WHERE YEAR(create_time) = 2024;
→ 现在可以用函数索引了！
→ EXPLAIN: key=idx_year ✅

-- 场景2：JSON 列的提取查询
CREATE INDEX idx_json_age ON user((CAST(json_data->>'$.age' AS SIGNED)));
SELECT * FROM user WHERE CAST(json_data->>'$.age' AS SIGNED) > 18;
→ 可以用函数索引了！

-- 函数索引的本质：
  → MySQL 自动创建一个隐藏的虚拟列（Generated Column）
  → 虚拟列的值 = 函数表达式
  → 紁引建在虚拟列上
  → 虚拟列不存储数据 → 不占用额外空间（VIRTUAL 类型）
  → 查询条件匹配函数索引 → 自动使用虚拟列的索引

-- 也可以手动创建虚拟列 + 紁引
ALTER TABLE user ADD COLUMN year_created INT 
    GENERATED ALWAYS AS (YEAR(create_time)) VIRTUAL;
CREATE INDEX idx_year_created ON user(year_created);
SELECT * FROM user WHERE year_created = 2024;
→ 效果与函数索引相同
```

---

## 10.6 不可见索引——MySQL 8.0 的安全验证机制

```sql
-- MySQL 8.0 支持不可见索引（Invisible Index）

-- 创建不可见索引
CREATE INDEX idx_a ON user(a) INVISIBLE;
→ 紁引存在但不被优化器使用
→ EXPLAIN 不会选择 idx_a

-- 临时验证：如果不可见索引确实有用 → 设为可见
ALTER TABLE user ALTER INDEX idx_a VISIBLE;
→ 紁引变为可见 → 优化器可以使用

-- 如果不可见索引无用 → 删除
ALTER TABLE user DROP INDEX idx_a;

-- 使用场景：
  → 准备删除索引 → 先设为 INVISIBLE → 观察一段时间
  → 如果性能没有下降 → 安全删除
  → 如果性能下降 → 设回 VISIBLE → 不需要重建索引（只是切换状态）
  
  → 优势：切换 INVISIBLE/VISIBLE 是瞬时操作
  → 删除索引后重建需要大量时间（大表可能几小时）
  → INVISIBLE → VISIBLE → 零风险验证

-- 注意：
  → INVISIBLE 紁引仍然被维护（INSERT/UPDATE/DELETE 时更新）
  → 只是优化器不使用它
  → 可以通过 FORCE INDEX 强制使用 INVISIBLE 紁引
  → SET SESSION optimizer_switch='use_invisible_indexes=on'; → 全局启用不可见索引
```

---

## 10.7 紁引与 DML 的权衡——索引越多越慢？

```
索引对 DML 性能的影响：

  INSERT：每插入一行 → 需要在每个索引的 B+Tree 中插入一条记录
    → N 个索引 → N 次 B+Tree 插入
    → 可能触发页分裂 → I/O 更多
    → 1 个索引 → 1 次插入 → 快
    → 5 个索引 → 5 次插入 → 5 倍开销

  UPDATE：如果更新了索引列 → 需要删除旧索引记录 + 插入新索引记录
    → 非索引列的更新 → 不影响索引 → 只更新聚簇索引
    → 更新索引列 → 等价于 DELETE + INSERT → 开销翻倍

  DELETE：每删除一行 → 需要在每个索引的 B+Tree 中删除一条记录
    → 可能触发页合并 → I/O 更多
    → N 个索引 → N 次 B+Tree 删除

索引空间开销：
  → 每个索引 = 一棵完整的 B+Tree → 占用磁盘空间
  → 联合索引 (a, b, c) 的叶子记录比单列索引 (a) 更长 → 占更多空间
  → 二级索引叶子只存 (索引列值 + 主键值) → 但索引列越多 → 叶子越长 → 页存记录更少 → B+Tree 更高

权衡原则：
  → 查询频繁的列 → 建索引（读优化优先）
  → 更新频繁的列 → 少建索引（写优化优先）
  → 低选择率列 → 不建索引（全表扫描够快）
  → 冗余索引 → 删除（浪费空间和 DML 性能）
  → 单表索引数 ≤ 5-6 个（经验值）

最佳实践：
  → 高读低写表 → 多建索引（查询优化为主）
  → 高写低读表 → 少建索引（DML 性能为主）
  → 日志表 → 只建时间索引（几乎只 INSERT）
  → 配置表 → 建必要索引（数据量少 → 紁引成本可控）
```

---

## 10.8 紁引设计 Checklist

```
索引设计 Checklist（建索引前逐项检查）：

✅ 1. 选择率是否足够高？
    → 选择率 > 15% → 值建索引
    → 选择率 < 5% → 不建索引

✅ 2. WHERE 条件是否匹配最左前缀？
    → 联合索引列顺序是否与查询条件匹配
    → 是否有范围条件打破最左前缀

✅ 3. 是否可以利用覆盖索引？
    → 查询的列是否在索引中 → Using index → 减少回表

✅ 4. 是否可以避免回表？
    → SELECT 列是否只需要索引列 → 避免 SELECT *

✅ 5. 是否有冗余索引？
    → 联合索引是否已覆盖单列索引 → 删除冗余

✅ 6. 紁引列是否过长？
    → VARCHAR(255) → 用前缀索引
    → TEXT/BLOB → 不能建普通索引 → 用函数索引

✅ 7. 是否需要 ORDER BY / GROUP BY？
    → 紁引列顺序是否匹配 ORDER BY → 避免 Filesort

✅ 8. 自增主键 vs UUID？
    → 新表 → 自增主键 → 顺序插入 → 不分裂
    → 已有 UUID → 不能改 → 接受分裂代价

✅ 9. DML 频率如何？
    → 高写 → 少建索引
    → 低写 → 多建索引

✅ 10. 是否需要定期 ANALYZE TABLE？
    → 统计信息是否准确 → 优化器选择是否正确

✅ 11. 是否需要 FORCE INDEX 临时方案？
    → 优化器选错索引 → 先 FORCE INDEX 验证 → 再 ANALYZE TABLE 修复

✅ 12. 是否需要 INVISIBLE INDEX 安全验证？
    → 准备删除索引 → 先 INVISIBLE → 观察 → 安全删除
```

---

# 附录 A：InnoDB 紁引核心源码文件速查

```
┌──────────────────────────────────────────────────────────────┐
│              InnoDB 紁引核心源码文件                            │
├──────────────────────────────────────┬───────────────────────┤
│ 文件                                 │ 功能                   │
├──────────────────────────────────────┼───────────────────────┤
│ btr0btr.cc                          │ B+Tree 查找/分裂/合并  │
│ btr0cur.cc                          │ B+Tree 游标操作        │
│ btr0pcur.cc                         │ B+Tree 持久游标        │
│ page0page.cc                        │ 页内记录操作           │
│ page0cur.cc                         │ 页内游标               │
│ page0dir.cc                         │ Page Directory Slot    │
│ dict0dict.cc                        │ 紁引字典定义           │
│ dict0mem.cc                         │ 紁引内存结构           │
│ buf0buf.cc                          │ Buffer Pool 页管理     │
│ buf0flu.cc                          │ 脏页刷盘               │
│ buf0rea.cc                          │ 页预读                 │
│ ibuf0ibuf.cc                        │ Change Buffer          │
│ fsp0fsp.cc                          │ 表空间/区/段管理        │
│ rem0rec.cc                          │ 记录格式定义           │
│ lock0lock.cc                        │ 行锁/Next-Key Lock     │
│ row0sel.cc                          │ 行查询/ICP/MRR         │
│ ha_innodb.cc                        │ MySQL 接口层           │
│ opt_range.cc                        │ 优化器范围估算         │
└──────────────────────────────────────┴───────────────────────┘
```

---

# 附录 B：索引相关 EXPLAIN 字段完整解读

```
┌──────────────────────────────────────────────────────────────┐
│              EXPLAIN 紁引相关字段解读                          │
├──────────────┬───────────────────────────────────────────────┤
│ 字段          │ 含义                                          │
├──────────────┼───────────────────────────────────────────────┤
│ type         │ 访问类型                                      │
│   system     │ 表只有一行 → const                            │
│   const      │ 主键/唯一索引等值 → 只读一行                   │
│   eq_ref     │ JOIN 中主键/唯一索引等值 → 每行只读一行         │
│   ref        │ 非唯一索引等值 → 可能读多行                    │
│   ref_or_null│ 非唯一索引等值 + IS NULL                      │
│   range      │ 紁引范围扫描 → BETWEEN / > / < / IN          │
│   index      │ 全索引扫描（扫描所有叶子页）                   │
│   index_merge│ 多个索引合并                                  │
│   ALL        │ 全表扫描 → 无索引或索引失效                    │
│              │                                               │
│ key          │ 实际使用的索引名称                             │
│ key_len      │ 使用索引的字节数 → 推断用了哪些列              │
│ ref          │ 紁引比较的值（const/列名/null）                │
│ rows         │ 估算扫描行数                                   │
│ filtered     │ WHERE 条件过滤比例                            │
│              │                                               │
│ Extra        │ 额外信息                                      │
│   Using index              │ 覆盖索引 → 无回表              │
│   Using index condition    │ ICP → 紁引条件下推             │
│   Using where              │ Server层WHERE过滤              │
│   Using filesort           │ 需要额外排序                   │
│   Using temporary          │ 需要临时表                     │
│   Using MRR                │ Multi-Range Read              │
│   Using intersect          │ 紁引合并交集                   │
│   Using union              │ 紁引合并并集                   │
│   Using sort_union         │ 紁引合并排序并集               │
│   LooseScan                │ 松索引扫描                     │
│   FirstMatch               │ Semi-join 首匹配              │
└──────────────┴───────────────────────────────────────────────┘
```

---

# 附录 C：索引相关参数与变量速查

```
┌──────────────────────────────────────────────────────────────┐
│              紁引相关参数与变量速查                              │
├──────────────────────────┬───────────────────────────────────┤
│ 参数                      │ 默认值 │ 说明                     │
├──────────────────────────┼─────────┼─────────────────────────┤
│ innodb_page_size         │ 16384  │ 页大小(16KB)              │
│ innodb_buffer_pool_size  │ 128MB  │ Buffer Pool大小           │
│ innodb_buffer_pool_instances│ 1   │ Buffer Pool Instance数    │
│ innodb_old_blocks_time  │ 1000   │ 冷页晋升等待(ms)          │
│ innodb_old_blocks_pct   │ 37     │ Old Sublist比例(3/8)      │
│ innodb_read_ahead_threshold│ 56   │ 线性预读阈值              │
│ innodb_random_read_ahead │ OFF    │ 随机预读开关              │
│ innodb_max_dirty_pages_pct│ 75    │ 脏页比例阈值(异步刷盘)    │
│ innodb_io_capacity       │ 200    │ 每秒I/O上限               │
│ innodb_io_capacity_max   │ 400    │ 紧急I/O上限               │
│ innodb_change_buffering  │ all    │ Change Buffer类型         │
│ innodb_change_buffer_max_size│ 25 │ Change Buffer最大比例     │
│ innodb_stats_persistent  │ ON     │ 统计信息持久化             │
│ innodb_stats_persistent_sample_pages│ 20 │ 采样页数             │
│ innodb_flush_method      │ fsync  │ 刷盘方法                  │
│ innodb_adaptive_hash_index│ ON    │ 自适应哈希索引(AHI)       │
│ read_rnd_buffer_size     │ 256K   │ MRR Row Buffer大小        │
│ optimizer_switch         │ ...    │ 优化器开关(ICP/MRR/BKA)   │
│ MERGE_THRESHOLD          │ 50     │ 页合并阈值(MySQL 8.0)     │
└──────────────────────────┴─────────┴─────────────────────────┘
```

---

**文档结语**

本文档从 InnoDB 源码层面系统解析了 MySQL 紁引的底层原理：

- **B+Tree** 是 InnoDB 紁引的核心数据结构，每个索引就是一棵 B+Tree
- **页结构** 是 B+Tree 的物理存储基础，Page Directory + Slot 实现页内高效查找
- **聚簇索引** 叶子存完整数据行，二级索引叶子存（索引列值 + 主键值）
- **最左前缀** 是联合索引使用的核心规则，范围查询打破最左前缀
- **覆盖索引** 避免回表，EXPLAIN 中 Using index 标识
- **ICP** 将 WHERE 条件下推到存储引擎层减少回表
- **MRR** 排序主键后回表减少随机 I/O
- **Buffer Pool** 和 **Change Buffer** 是索引性能的关键基础设施

建议配合之前的《Spring全家桶综合串讲》文档一起阅读——从 Gateway 到 MySQL 的请求全链路中，索引是最后一环：Gateway → 服务 AOP → @Transactional → MyBatis → MySQL B+Tree 紁引查找。理解了 B+Tree 的底层原理，你就能从磁盘 I/O 层面理解为什么某个查询快、某个查询慢。

---

*文档完成日期：2026-06-26*
*文档版本：v1.0*