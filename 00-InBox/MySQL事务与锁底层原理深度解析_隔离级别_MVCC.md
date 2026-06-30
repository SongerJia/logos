# MySQL 事务与锁（隔离级别 + MVCC）底层原理深度解析

> **本文定位**：从 InnoDB 源码层面系统解析 MySQL 事务、隔离级别、MVCC 多版本并发控制、锁体系的完整底层原理。
>
> **前置阅读**：建议先读《MySQL索引底层原理深度解析》，理解 B+Tree、聚簇索引、二级索引、页结构等基础概念。
>
> **InnoDB 源码版本参考**：MySQL 8.0.x（storage/innobase 目录）

---

## 目录

- [第一部分：事务基础 — ACID 与事务生命周期](#第一部分事务基础--acid-与事务生命周期)
- [第二部分：四种隔离级别 — 从现象到本质](#第二部分四种隔离级别--从现象到本质)
- [第三部分：MVCC 多版本并发控制 — 核心原理](#第三部分mvcc-多版本并发控制--核心原理)
- [第四部分：Undo Log — 版本链的源头](#第四部分undo-log--版本链的源头)
- [第五部分：Redo Log — WAL 与崩溃恢复](#第五部分redo-log--wal-与崩溃恢复)
- [第六部分：Buffer Pool 与事务的协同](#第六部分buffer-pool-与事务的协同)
- [第七部分：InnoDB 锁体系 — 7 种锁全解析](#第七部分innodb-锁体系--7-种锁全解析)
- [第八部分：锁兼容性矩阵与加锁规则](#第八部分锁兼容性矩阵与加锁规则)
- [第九部分：死锁检测与处理](#第九部分死锁检测与处理)
- [第十部分：RC vs RR — 锁与 MVCC 的差异](#第十部分rc-vs-rr--锁与-mvcc-的差异)
- [第十一部分：两阶段提交（2PC）— Redo Log 与 Binlog 的一致性](#第十一部分两阶段提交2pc--redo-log-与-binlog-的一致性)
- [第十二部分：分布式事务 — XA 与 MySQL XA](#第十二部分分布式事务--xa-与-mysql-xa)
- [第十三部分：实战 — 锁等待分析与死锁排查](#第十三部分实战--锁等待分析与死锁排查)
- [第十四部分：事务设计原则与最佳实践](#第十四部分事务设计原则与最佳实践)
- [附录 A：InnoDB 事务与锁核心源码文件索引](#附录-ainnodb-事务与锁核心源码文件索引)
- [附录 B：锁类型与隔离级别速查表](#附录-b锁类型与隔离级别速查表)
- [附录 C：与前面文档的衔接关系](#附录-c与前面文档的衔接关系)

---

## 第一部分：事务基础 — ACID 与事务生命周期

### 1.1 ACID 四大特性

```
┌─────────────────────────────────────────────────────────┐
│                      ACID 四大特性                        │
├──────────────┬──────────────────────────────────────────┤
│              │  事务是一个不可分割的工作单位，             │
│ Atomicity    │  要么全部成功，要么全部回滚。               │
│ 原子性       │                                          │
│              │  实现：Undo Log（回滚日志）                │
├──────────────┼──────────────────────────────────────────┤
│              │  事务执行前后，数据库从一个一致性状态       │
│ Consistency  │  转变到另一个一致性状态。                   │
│ 一致性       │                                          │
│              │  实现：AID 共同保证（约束 + 触发器 + 应用）  │
├──────────────┼──────────────────────────────────────────┤
│              │  多个事务并发执行时，一个事务的执行         │
│ Isolation    │  不应影响其他事务。                        │
│ 隔离性       │                                          │
│              │  实现：MVCC + Lock（锁机制）              │
├──────────────┼──────────────────────────────────────────┤
│              │  事务一旦提交，对数据库的修改是永久的，     │
│ Durability   │  即使系统崩溃也不会丢失。                   │
│ 持久性       │                                          │
│              │  实现：Redo Log（重做日志）               │
└──────────────┴──────────────────────────────────────────┘
```

### 1.2 事务的底层实现 — AID 如何保证 C

```
                    事务执行过程
                         
  BEGIN ──→ SQL执行 ──→ COMMIT / ROLLBACK
    │           │              │
    │           │              │
    ▼           ▼              ▼
  开启事务    写 Undo Log     写 Redo Log (Prepare)
  分配 trx   修改 Buffer Pool  写 Binlog
  分配 Undo  写 Redo Log      写 Redo Log (Commit)
             (修改时同步写)    
    │           │              │
    │           │              │
    ▼           ▼              ▼
  Atomicity   Isolation     Durability
  (Undo Log   (MVCC +       (Redo Log
   回滚)       Lock)         WAL)
    │           │              │
    └───────────┴──────────────┘
                │
                ▼
           Consistency
           (AID 共同保证)
```

**关键理解**：

- **A（原子性）** 靠 Undo Log：修改前先记录旧值，回滚时根据 Undo Log 恢复
- **I（隔离性）** 靠 MVCC + Lock：读靠 MVCC 快照，写靠锁互斥
- **D（持久性）** 靠 Redo Log：修改先写日志（WAL），崩溃后重做恢复
- **C（一致性）** 是目标，AID 是手段

### 1.3 事务对象 — trx_t 结构（源码）

InnoDB 中每个事务用一个 `trx_t` 结构体表示，定义在 `trx0trx.h`：

```c
// storage/innobase/trx/trx0trx.h (简化)

struct trx_t {
    // ========== 事务标识 ==========
    trx_id_t    id;          // 事务ID（只读事务为0）
    trx_id_t    no;          // 事务提交序号（commit时分配）
    
    // ========== 事务状态 ==========
    trx_state_t state;       // NOT_STARTED / ACTIVE / PREPARED / COMMITTED
    
    // ========== 隔离级别 ==========
    enum isolation_level_t   isolation_level;  // READ_UNCOMMITTED / READ_COMMITTED
                                               // / REPEATABLE_READ / SERIALIZABLE
    
    // ========== ReadView（MVCC 核心）==========
    ReadView*   read_view;   // 当前事务的快照视图
    
    // ========== Undo Log ==========
    trx_undo_t* insert_undo; // INSERT 操作的 Undo Log
    trx_undo_t* update_undo; // UPDATE/DELETE 操作的 Undo Log
    roll_ptr_t  roll_limit;  // 回滚指针限制
    
    // ========== 锁信息 ==========
    trx_lock_t  lock;        // 事务持有的所有锁
    ulint       n_rec_locks; // 持有的记录锁数量
    ulint       dict_operation_lock_mode; // DDL锁模式
    
    // ========== 修改的表 ==========
    ib_vector_t* mysql_tables;          // 修改的 MySQL 表
    ib_vector_t* mysql_thd_tables;      // THD 中的表
    
    // ========== Redo Log ==========
    lsn_t       commit_lsn;  // 提交时的 LSN
    trx_rseg_t* rseg;        // 回滚段
    
    // ========== 事务统计 ==========
    ulint       n_mysql_tables_in_use;
    ulint       mysql_n_tables_locked;
    
    // ========== 错误信息 ==========
    dberr_t     error_state; // 事务错误状态
    const dict_index_t* error_index;
};
```

**关键字段解读**：

| 字段 | 作用 |
|------|------|
| `id` | 事务ID，全局递增，用于 MVCC 版本链中的 `trx_id` |
| `no` | 提交序号，commit 时分配，用于判断事务提交顺序 |
| `state` | 事务状态机：NOT_STARTED → ACTIVE → PREPARED → COMMITTED |
| `read_view` | MVCC 快照，RC 每次 SELECT 创建新的，RR 只在第一次 SELECT 创建 |
| `insert_undo` | INSERT 的 Undo Log，回滚时直接删除记录 |
| `update_undo` | UPDATE/DELETE 的 Undo Log，保留供 MVCC 使用 |
| `lock` | 事务持有的所有锁的链表头 |
| `rseg` | 回滚段，管理 Undo Log 的存储空间 |

### 1.4 事务状态机

```
                    事务状态转换图

  ┌──────────────┐     BEGIN / START TRANSACTION
  │  NOT_STARTED │ ──────────────────────────────┐
  └──────────────┘                               │
        ▲                                        ▼
        │                                  ┌──────────┐
        │ ROLLBACK /                       │  ACTIVE  │
        │ COMMIT 完成                      │ (执行中)  │
        │                                  └──────────┘
        │                                      │   │
        │                              COMMIT  │   │ ROLLBACK
        │                                      ▼   │
        │                              ┌──────────┐│
        │                              │ PREPARED ││ 写 Undo Log
        │                              │ (2PC)    ││ 回滚
        │                              └──────────┘│
        │                                      │   │
        │                              Binlog  │   │
        │                              写完     │   │
        │                                      ▼   │
        │                              ┌──────────┐│
        └──────────────────────────────│COMMITTED ││
                                       └──────────┘│
                                                    │
                              ROLLBACK ◄────────────┘
```

### 1.5 autocommit 机制

```sql
-- MySQL 默认 autocommit = 1
mysql> SHOW VARIABLES LIKE 'autocommit';
+---------------+-------+
| Variable_name | Value |
+---------------+-------+
| autocommit    | ON    |
+---------------+-------+

-- autocommit=1 时：
-- 每条 SQL 自动包裹在事务中，执行完自动提交
-- 相当于：BEGIN; SQL; COMMIT;

-- 显式事务：
BEGIN;
UPDATE account SET balance = balance - 100 WHERE id = 1;
UPDATE account SET balance = balance + 100 WHERE id = 2;
COMMIT;  -- 或 ROLLBACK;
```

**autocommit 与锁的关系**：

```
autocommit = 1 (默认)：
  SELECT * FROM t WHERE id = 1 FOR UPDATE;
  -- 锁在 SELECT 执行时加，语句结束后立即释放（因为自动提交了）

autocommit = 0 或显式事务：
  BEGIN;
  SELECT * FROM t WHERE id = 1 FOR UPDATE;
  -- 锁持有，不释放
  -- ... 其他操作
  COMMIT;  -- 此时才释放锁
```

### 1.6 隐式提交

某些 DDL 语句会触发隐式 COMMIT：

```sql
BEGIN;
INSERT INTO t VALUES (1);

-- 以下语句会隐式提交前面的 INSERT
ALTER TABLE t ADD COLUMN c2 INT;  -- DDL 触发隐式提交
-- 此时 INSERT 已经提交，无法回滚

ROLLBACK;  -- 无效，事务已提交
```

**会触发隐式提交的语句**：
- DDL：CREATE / ALTER / DROP / TRUNCATE / RENAME
- 管理语句：CREATE USER / GRANT / REVOKE
- LOAD DATA / LOAD XML
- ANALYZE TABLE / OPTIMIZE TABLE / REPAIR TABLE
- SET AUTOCommit=1（如果当前在事务中）

---

## 第二部分：四种隔离级别 — 从现象到本质

### 2.1 并发事务的三种问题

```
┌─────────────────────────────────────────────────────────────────┐
│                    并发事务的三种问题                              │
├─────────────┬───────────────────────────────────────────────────┤
│             │  事务 A 读到了事务 B 尚未提交的修改。               │
│  脏读       │  如果 B 回滚，A 读到的就是"脏"数据。               │
│ Dirty Read  │                                                   │
│             │  示例：A 读到 B 未提交的 balance=0，B 回滚后       │
│             │        balance 实际还是 100                       │
├─────────────┼───────────────────────────────────────────────────┤
│             │  事务 A 两次读取同一行，结果不同。                  │
│ 不可重复读   │  因为事务 B 在两次读之间修改并提交了。              │
│ Non-Repeat  │                                                   │
│ able Read   │  示例：A 第一次读 balance=100，                   │
│             │        B 修改为 200 并提交，                       │
│             │        A 第二次读 balance=200                     │
├─────────────┼───────────────────────────────────────────────────┤
│             │  事务 A 两次范围查询，结果集行数不同。              │
│  幻读       │  因为事务 B 在两次查询间插入/删除了新行并提交。     │
│ Phantom Read│                                                   │
│             │  示例：A 第一次查 id>10 返回 5 行，               │
│             │        B 插入 id=11 并提交，                       │
│             │        A 第二次查 id>10 返回 6 行                 │
└─────────────┴───────────────────────────────────────────────────┘

  严重程度：脏读 > 不可重复读 > 幻读
```

### 2.2 四种隔离级别总览

```
┌──────────────────────────────────────────────────────────────────────┐
│                         SQL 标准四种隔离级别                           │
├─────────────────┬────────┬──────────┬──────────┬────────────────────┤
│    隔离级别      │ 脏读   │ 不可重复读│  幻读    │    InnoDB 实现方式  │
├─────────────────┼────────┼──────────┼──────────┼────────────────────┤
│ READ UNCOMMITTED│  ✗     │    ✗     │    ✗     │ 不使用 MVCC，直接读 │
│ (读未提交 RU)    │ 可能   │   可能   │   可能   │ 最新数据（脏读）     │
├─────────────────┼────────┼──────────┼──────────┼────────────────────┤
│ READ COMMITTED  │  ✓     │    ✗     │    ✗     │ MVCC：每条 SELECT  │
│ (读已提交 RC)    │ 不可能 │   可能   │   可能   │ 创建新的 ReadView   │
├─────────────────┼────────┼──────────┼──────────┼────────────────────┤
│ REPEATABLE READ │  ✓     │    ✓     │  ✓*      │ MVCC：事务首次      │
│ (可重复读 RR)    │ 不可能 │  不可能  │ 不可能*  │ SELECT 创建 ReadView│
│ (InnoDB 默认)    │        │          │          │ + Next-Key Lock     │
├─────────────────┼────────┼──────────┼──────────┼────────────────────┤
│ SERIALIZABLE    │  ✓     │    ✓     │    ✓     │ 所有 SELECT 隐式    │
│ (串行化)         │ 不可能 │  不可能  │  不可能  │ 加 LOCK IN SHARE MODE│
└─────────────────┴────────┴──────────┴──────────┴────────────────────┘

* InnoDB 的 RR 级别通过 Next-Key Lock 解决了幻读（SQL 标准说 RR 不能解决幻读，
  但 InnoDB 的实现超出了 SQL 标准）。
```

### 2.3 设置隔离级别

```sql
-- 全局设置
SET GLOBAL transaction_isolation = 'READ-COMMITTED';

-- 会话设置
SET SESSION transaction_isolation = 'REPEATABLE-READ';

-- 查看当前隔离级别
SELECT @@transaction_isolation;
-- 或 MySQL 5.7:
SELECT @@tx_isolation;

-- MySQL 8.0 变量名：
-- transaction_isolation (取代 tx_isolation)
-- transaction_read_only  (取代 tx_read_only)
```

### 2.4 READ UNCOMMITTED — 脏读演示

```sql
-- 准备数据
CREATE TABLE t (id INT PRIMARY KEY, val INT);
INSERT INTO t VALUES (1, 100);

-- 会话 A                          -- 会话 B
SET SESSION transaction_isolation  
= 'READ-UNCOMMITTED';

BEGIN;                              BEGIN;
SELECT val FROM t WHERE id=1;      
-- 结果: 100

                                   UPDATE t SET val=200 WHERE id=1;
                                   -- 未提交

SELECT val FROM t WHERE id=1;
-- 结果: 200 ← 脏读！读到了 B 未提交的数据

                                   ROLLBACK;
                                   -- B 回滚，val 恢复为 100

SELECT val FROM t WHERE id=1;
-- 结果: 100
```

**源码层面**：RU 级别不创建 ReadView，直接读取最新版本的数据：

```c
// storage/innobase/row/row0sel.cc (简化)

dberr_t row_search_for_mysql(byte *buf, ...) {
    // ...
    
    if (trx->isolation_level == TRX_ISO_READ_UNCOMMITTED) {
        // READ UNCOMMITTED：不使用 MVCC，直接读最新版本
        // 即使数据未被其他事务提交，也直接读取
        // 不创建 ReadView，不做可见性检查
        rec = row_search_get_first_rec(...);
        // 直接返回最新记录
        goto return_rec;
    }
    
    // 其他隔离级别：走 MVCC 或加锁读
    // ...
}
```

### 2.5 READ COMMITTED — 不可重复读演示

```sql
-- 会话 A                          -- 会话 B
SET SESSION transaction_isolation
= 'READ-COMMITTED';

BEGIN;                              BEGIN;
SELECT val FROM t WHERE id=1;
-- 结果: 100

                                   UPDATE t SET val=200 WHERE id=1;
                                   COMMIT;
                                   -- B 提交

SELECT val FROM t WHERE id=1;
-- 结果: 200 ← 不可重复读！
-- 同一事务内两次读取结果不同

COMMIT;
```

**源码层面**：RC 级别每次 SELECT 都创建新的 ReadView：

```c
// storage/innobase/trx/trx0trx.cc (简化)

void trx_assign_read_view(trx_t *trx) {
    if (!trx->read_view) {
        // 创建新的 ReadView
        trx->read_view = MVCC::view_open(trx->id);
    }
}

// 每次 SELECT 执行前
void trx_search_handle_called(trx_t *trx) {
    if (trx->isolation_level == TRX_ISO_READ_COMMITTED) {
        // RC 级别：每次 SELECT 关闭旧 ReadView
        // 下次 SELECT 会创建新的 ReadView
        MVCC::view_close(trx->read_view);
        trx->read_view = NULL;
    }
    // RR 级别：不关闭，继续使用首次创建的 ReadView
}
```

### 2.6 REPEATABLE READ — 可重复读演示

```sql
-- 会话 A                          -- 会话 B
-- (默认隔离级别 RR)

BEGIN;                              BEGIN;
SELECT val FROM t WHERE id=1;
-- 结果: 100

                                   UPDATE t SET val=200 WHERE id=1;
                                   COMMIT;

SELECT val FROM t WHERE id=1;
-- 结果: 100 ← 可重复读！
-- 同一事务内多次读取结果一致

COMMIT;

-- 提交后再次读取
SELECT val FROM t WHERE id=1;
-- 结果: 200
```

### 2.7 InnoDB RR 如何解决幻读 — Next-Key Lock

```sql
-- 会话 A                          -- 会话 B
-- (默认隔离级别 RR)

BEGIN;                              BEGIN;
SELECT * FROM t WHERE id > 10 
FOR UPDATE;
-- 假设返回 id=11,12,13
-- 加 Next-Key Lock: (10, +∞)

                                   INSERT INTO t VALUES (14, 999);
                                   -- 阻塞！← 被 Gap Lock 阻止
                                   -- 不会出现幻行

SELECT * FROM t WHERE id > 10;
-- 结果: id=11,12,13 ← 没有幻读

COMMIT;
                                   -- 会话 B 的 INSERT 才能执行
```

### 2.8 SERIALIZABLE — 串行化

```sql
-- 会话 A                          -- 会话 B
SET SESSION transaction_isolation
= 'SERIALIZABLE';

BEGIN;                              BEGIN;
SELECT * FROM t WHERE id=1;
-- 隐式加 S锁（共享锁）

                                   UPDATE t SET val=200 WHERE id=1;
                                   -- 阻塞！被 A 的 S锁阻塞

COMMIT;
                                   -- A 提交后，B 才能执行
```

**源码层面**：Serializable 级别将普通 SELECT 转换为加锁读：

```c
// storage/innobase/row/row0sel.cc (简化)

dberr_t row_search_for_mysql(byte *buf, ...) {
    // ...
    
    if (trx->isolation_level == TRX_ISO_SERIALIZABLE) {
        // Serializable：普通 SELECT 也加共享锁
        // 相当于 SELECT ... LOCK IN SHARE MODE
        mode = LOCK_S;  // 加共享锁
        // 走加锁读路径，不走 MVCC
    } else if ( trx->isolation_level <= TRX_ISO_READ_COMMITTED
               || prebuilt->select_lock_type != LOCK_NONE) {
        // RC 及以下 + FOR UPDATE / LOCK IN SHARE MODE：加锁读
        // ...
    } else {
        // RR / RC 的普通 SELECT：走 MVCC 快照读
        // ...
    }
}
```

### 2.9 隔离级别与一致性读对比

```
┌─────────────────────────────────────────────────────────────────┐
│              隔离级别 vs 读方式 vs 锁                            │
├─────────────────┬────────────────┬──────────────────────────────┤
│    隔离级别      │  快照读(SELECT) │    当前读(FOR UPDATE /       │
│                 │                │    LOCK IN SHARE MODE /      │
│                 │                │    UPDATE / DELETE / INSERT) │
├─────────────────┼────────────────┼──────────────────────────────┤
│ READ UNCOMMITTED│  读最新版本     │  加锁                        │
│                 │  (无 MVCC)     │  (Record Lock)               │
├─────────────────┼────────────────┼──────────────────────────────┤
│ READ COMMITTED  │  MVCC          │  加锁                        │
│                 │  每次SELECT新  │  (Record Lock only)          │
│                 │  ReadView      │  无 Gap Lock                 │
├─────────────────┼────────────────┼──────────────────────────────┤
│ REPEATABLE READ │  MVCC          │  加锁                        │
│                 │  首次SELECT    │  (Next-Key Lock =            │
│                 │  创建ReadView  │   Record Lock + Gap Lock)    │
├─────────────────┼────────────────┼──────────────────────────────┤
│ SERIALIZABLE    │  隐式加S锁     │  加锁                        │
│                 │  (不走MVCC)    │  (Next-Key Lock + S锁)       │
└─────────────────┴────────────────┴──────────────────────────────┘

  快照读：SELECT * FROM t WHERE ... (不加锁的普通查询)
  当前读：SELECT ... FOR UPDATE / SELECT ... LOCK IN SHARE MODE
          UPDATE / DELETE / INSERT (需要读取最新数据)
```

---

## 第三部分：MVCC 多版本并发控制 — 核心原理

### 3.1 为什么需要 MVCC

```
没有 MVCC 的世界（纯锁方案）：

  读-写冲突：
  ┌─────────┐         ┌─────────┐
  │ 事务 A   │         │ 事务 B   │
  │ SELECT  │  ← 阻塞 → │ UPDATE  │
  │ (读)     │         │ (写)     │
  └─────────┘         └─────────┘
  读必须等写完成，写必须等读完成 → 并发度极低

有 MVCC 的世界：

  读-写不冲突：
  ┌─────────┐         ┌─────────┐
  │ 事务 A   │         │ 事务 B   │
  │ SELECT  │  ← 不阻塞 → │ UPDATE  │
  │ (快照读) │         │ (加锁写) │
  └─────────┘         └─────────┘
  A 读旧版本（Undo Log），B 写新版本 → 读写并行
```

### 3.2 MVCC 三要素

```
┌─────────────────────────────────────────────────────────────────┐
│                        MVCC 三要素                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 隐藏字段（每行记录都有）                                      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  DB_TRX_ID (6字节)   │  DB_ROLL_PTR (7字节)  │  ...数据  │  │
│  │  最近修改的事务ID     │  指向 Undo Log 中       │          │  │
│  │                       │  上一版本的指针          │          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  2. Undo Log 版本链                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                 │
│  │ 当前版本  │←──│ 旧版本1   │←──│ 旧版本2   │←── ...          │
│  │ trx_id=5 │    │ trx_id=3 │    │ trx_id=1 │                 │
│  │ roll_ptr─┘    │ roll_ptr─┘    │ roll_ptr─┘                 │
│  └──────────┘    └──────────┘    └──────────┘                  │
│   (Buffer Pool    (Undo Log      (Undo Log                     │
│    或磁盘)         段)            段)                            │
│                                                                 │
│  3. ReadView（一致性读视图）                                      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  m_creator_trx_id: 创建 ReadView 的事务ID                │  │
│  │  m_low_limit_id:   下一个要分配的事务ID（> 此值的不可见）  │  │
│  │  m_up_limit_id:    最小活跃事务ID（< 此值的可见）         │  │
│  │  m_ids:            创建时所有活跃事务ID列表               │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.3 隐藏字段详解

InnoDB 为每行记录添加了两个隐藏字段（聚簇索引中）：

```c
// 每行记录的隐藏字段（在记录头之后、用户数据之前）

// 1. DB_TRX_ID (6 bytes)
//    记录最后一次修改（INSERT/UPDATE/DELETE）这行的事务ID
//    trx_id_t 类型，全局递增

// 2. DB_ROLL_PTR (7 bytes) 
//    回滚指针，指向 Undo Log 中的上一版本
//    roll_ptr_t 类型，包含：回滚段号 + Undo Log页号 + 页内偏移

// 如果表没有主键，InnoDB 还会添加：
// 3. DB_ROW_ID (6 bytes)
//    隐式自增主键（仅在表没有主键且没有唯一非空索引时）
```

**验证隐藏字段的存在**：

```sql
-- 创建表时不指定主键
CREATE TABLE t_no_pk (a INT, b INT);

-- InnoDB 自动添加 DB_ROW_ID
-- 可以通过查看 ibd 文件或 Information Schema 确认

-- 有主键的表：
CREATE TABLE t_with_pk (
    id INT PRIMARY KEY,
    val INT
) ENGINE=InnoDB;

-- 行格式（Compact/Dynamic）：
-- ┌─────────────┬──────────────┬──────────────┬────────┬────────┐
-- │ Record Header│ DB_TRX_ID   │ DB_ROLL_PTR  │ id     │ val    │
-- │ (变长)       │ (6 bytes)   │ (7 bytes)    │ (4B)   │ (4B)   │
-- └─────────────┴──────────────┴──────────────┴────────┴────────┘
```

### 3.4 Undo Log 版本链构建过程

```
初始状态：
  事务1 (trx_id=1) INSERT INTO t VALUES(1, 'A');
  
  ┌────────────────────────────────────────┐
  │  聚簇索引记录（当前版本）               │
  │  id=1, val='A'                        │
  │  DB_TRX_ID=1                          │
  │  DB_ROLL_PTR → Undo Log 页1 位置A     │
  └────────────────────────────────────────┘
                    │
                    ▼
  ┌────────────────────────────────────────┐
  │  Undo Log (insert_undo)               │
  │  类型: TRX_UNDO_INSERT_REC            │
  │  主键: id=1                           │
  │  （INSERT 的 Undo 只记录主键，          │
  │    回滚时按主键删除）                    │
  └────────────────────────────────────────┘


事务2 (trx_id=2) UPDATE t SET val='B' WHERE id=1;

  Step1: 将旧版本拷贝到 Undo Log
  Step2: 修改当前记录，更新 DB_TRX_ID 和 DB_ROLL_PTR

  ┌────────────────────────────────────────┐
  │  聚簇索引记录（当前版本 v2）            │
  │  id=1, val='B'                        │
  │  DB_TRX_ID=2                          │
  │  DB_ROLL_PTR → Undo Log 页2 位置B     │
  └────────────────────────────────────────┘
                    │
                    ▼
  ┌────────────────────────────────────────┐
  │  Undo Log (update_undo) 版本 v1       │
  │  类型: TRX_UNDO_UPD_EXIST_REC         │
  │  旧值: id=1, val='A'                  │
  │  DB_TRX_ID=1                          │
  │  DB_ROLL_PTR → Undo Log 页1 位置A     │
  └────────────────────────────────────────┘
                    │
                    ▼
  ┌────────────────────────────────────────┐
  │  Undo Log (insert_undo) 版本 v0       │
  │  类型: TRX_UNDO_INSERT_REC            │
  │  主键: id=1                           │
  │  DB_ROLL_PTR = NULL (链表终点)        │
  └────────────────────────────────────────┘


事务3 (trx_id=3) UPDATE t SET val='C' WHERE id=1;

  ┌────────────────────────────────────────┐
  │  聚簇索引记录（当前版本 v3）            │
  │  id=1, val='C'                        │
  │  DB_TRX_ID=3                          │
  │  DB_ROLL_PTR → Undo Log 页3 位置C     │
  └────────────────────────────────────────┘
                    │
                    ▼
  ┌────────────────────────────────────────┐
  │  Undo Log 版本 v2                      │
  │  旧值: id=1, val='B'                  │
  │  DB_TRX_ID=2                          │
  │  DB_ROLL_PTR → Undo Log 页2 位置B     │
  └────────────────────────────────────────┘
                    │
                    ▼
  ┌────────────────────────────────────────┐
  │  Undo Log 版本 v1                      │
  │  旧值: id=1, val='A'                  │
  │  DB_TRX_ID=1                          │
  │  DB_ROLL_PTR → Undo Log 页1 位置A     │
  └────────────────────────────────────────┘
                    │
                    ▼
                 NULL（链表终点）

  版本链：v3(当前) → v2 → v1 → v0(NULL)
  MVCC 沿着 DB_ROLL_PTR 遍历版本链，找到对当前事务可见的版本
```

### 3.5 ReadView 结构详解（源码）

```c
// storage/innobase/read/read0read.h (简化)

class ReadView {
    // ========== 核心字段 ==========
    
    // 创建此 ReadView 的事务ID
    trx_id_t    m_creator_trx_id;
    
    // 创建 ReadView 时，系统中下一个将要分配的事务ID
    // 事务ID >= m_low_limit_id 的记录都不可见
    // （因为它们是在 ReadView 创建之后才开始的事务）
    trx_id_t    m_low_limit_id;
    
    // 创建 ReadView 时，系统中当前最小活跃事务ID
    // 事务ID < m_up_limit_id 的记录都可见
    // （因为它们在 ReadView 创建之前就已经提交）
    trx_id_t    m_up_limit_id;
    
    // 创建 ReadView 时，所有活跃事务ID的集合
    // 活跃 = 已开始但未提交
    ids_t       m_ids;  // std::vector<trx_id_t>，有序排列
    
    // ========== 状态管理 ==========
    bool        m_closed;
    
    // ========== 方法 ==========
    
    // 判断某事务ID的记录是否对本 ReadView 可见
    bool changes_visible(trx_id_t id) const {
        // 1. 事务ID < m_up_limit_id → 可见（已提交）
        if (id < m_up_limit_id) {
            return true;
        }
        
        // 2. 事务ID == m_creator_trx_id → 可见（自己修改的）
        if (id == m_creator_trx_id) {
            return true;
        }
        
        // 3. 事务ID >= m_low_limit_id → 不可见（ReadView创建后的事务）
        if (id >= m_low_limit_id) {
            return false;
        }
        
        // 4. 在 m_up_limit_id 和 m_low_limit_id 之间
        //    检查是否在活跃事务列表中
        //    二分查找 m_ids
        if (!m_ids.empty()) {
            // 在活跃列表中 → 不可见（未提交）
            // 不在活跃列表中 → 可见（已提交）
            return !std::binary_search(m_ids.begin(), m_ids.end(), id);
        }
        
        return true;
    }
};
```

### 3.6 ReadView 可见性判断算法（核心）

```
                    ReadView 可见性判断流程

                    ┌─────────────────┐
                    │ 记录的 trx_id   │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ trx_id <        │
                    │ m_up_limit_id?  │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │ YES          │ NO           │
              ▼              ▼              │
        ┌──────────┐  ┌─────────────┐     │
        │ 可见 ✓   │  │ trx_id ==   │     │
        │ (已提交) │  │ m_creator   │     │
        └──────────┘  │ _trx_id?    │     │
                      └──────┬──────┘     │
                             │             │
              ┌──────────────┼──────────┐  │
              │ YES          │ NO       │  │
              ▼              ▼          │  │
        ┌──────────┐  ┌───────────┐    │  │
        │ 可见 ✓   │  │ trx_id >= │    │  │
        │ (自己改的)│  │m_low_limit│    │  │
        └──────────┘  │ _id?      │    │  │
                      └─────┬─────┘    │  │
                            │          │  │
              ┌─────────────┼──────────┘  │
              │ YES         │ NO          │
              ▼             ▼             │
        ┌──────────┐  ┌───────────┐     │
        │ 不可见 ✗ │  │ trx_id 在 │     │
        │(ReadView │  │ m_ids 中? │     │
        │ 之后的事务)│ └─────┬─────┘     │
        └──────────┘        │           │
                    ┌───────┴───────┐   │
                    │ YES           │ NO│
                    ▼               ▼   │
              ┌──────────┐  ┌────────┐  │
              │ 不可见 ✗ │  │ 可见 ✓ │  │
              │(活跃未   │  │(已提交)│  │
              │ 提交)    │  └────────┘  │
              └──────────┘              │
                                         │
                    如果不可见，沿 DB_ROLL_PTR │
                    找上一版本，重复判断 ──────┘
```

### 3.7 MVCC 完整工作流程示例

```
时间线：
  t1: 事务100 INSERT id=1, val='A' 并提交
  t2: 事务200 BEGIN
  t3: 事务200 SELECT val FROM t WHERE id=1  → 读到 'A'
  t4: 事务300 BEGIN; UPDATE t SET val='B' WHERE id=1; COMMIT
  t5: 事务300 BEGIN; UPDATE t SET val='C' WHERE id=1; COMMIT
  t6: 事务200 SELECT val FROM t WHERE id=1  → 读到 ??? (RR级别)

版本链：
  v3: val='C', trx_id=300, roll_ptr→v2
  v2: val='B', trx_id=300, roll_ptr→v1  (注意：同一个事务300两次修改)
  v1: val='A', trx_id=100, roll_ptr→NULL

事务200的 ReadView（在 t3 首次 SELECT 时创建）：
  m_creator_trx_id = 200
  m_low_limit_id = 301   (下一个要分配的事务ID)
  m_up_limit_id = 101    (最小活跃事务ID，此时只有200活跃，100已提交)
  m_ids = [200]          (活跃事务列表)

t6 时（RR级别，使用 t3 创建的 ReadView）：
  1. 读取当前版本 v3: trx_id=300
     300 >= m_low_limit_id(301)?  300 < 301 → 继续判断
     300 == m_creator_trx_id(200)? No
     300 < m_up_limit_id(101)? No
     300 in m_ids([200])? No → 不可见（因为300 >= 301? 不，300 < 301）
     
     等等，让我重新分析：
     m_low_limit_id = 301, trx_id=300
     300 >= 301? No → 继续判断
     300 < m_up_limit_id(101)? No
     300 == m_creator_trx_id(200)? No  
     300 in m_ids([200])? No
     → 不可见？不对。
     
     正确分析：
     事务300在t3时已经提交了吗？
     - t3: 事务200 SELECT，此时事务300还没开始
     - t4: 事务300 BEGIN, UPDATE, COMMIT
     - t5: 又一个事务300 BEGIN...（假设是事务400）
     
     让我重新设定：
     
     事务ID分配：
     t1: trx_id=100 INSERT + COMMIT
     t2: trx_id=200 BEGIN (活跃)
     t3: trx_id=200 SELECT → ReadView创建
         m_low_limit_id = 201 (下一个事务ID)
         m_up_limit_id = 200 (最小活跃事务，即200自己... 不对)
         
     实际上，ReadView创建时：
     - m_low_limit_id = 当前最大事务ID + 1
     - 如果此时只有事务200活跃，且事务100已提交
     - m_ids = [200] (活跃列表)
     - m_low_limit_id = 201
     - m_up_limit_id = min(m_ids) = 200
     
     但 trx_id=200 是自己（m_creator_trx_id=200）
     m_up_limit_id 应该是 200，但 200 在活跃列表中
     
     更准确：m_up_limit_id = m_ids 的最小值 = 200
     
     但事务100的 trx_id=100 < 200 = m_up_limit_id → 可见 ✓
     
     t4: trx_id=300 BEGIN, UPDATE val='B', COMMIT
     t5: trx_id=400 BEGIN, UPDATE val='C', COMMIT
     
     版本链：
     v3: val='C', trx_id=400
     v2: val='B', trx_id=300
     v1: val='A', trx_id=100
     
     t6: 事务200 SELECT（RR，用t3的ReadView）
     ReadView: m_creator_trx_id=200, m_low_limit_id=201, 
               m_up_limit_id=200, m_ids=[200]
     
     v3: trx_id=400
     400 >= m_low_limit_id(201)? YES → 不可见 ✗
     → 沿 roll_ptr 找 v2
     
     v2: trx_id=300
     300 >= m_low_limit_id(201)? YES → 不可见 ✗
     → 沿 roll_ptr 找 v1
     
     v1: trx_id=100
     100 < m_up_limit_id(200)? YES → 可见 ✓
     
     返回 val='A' ← 可重复读！
```

### 3.8 RC 级别的 ReadView 行为

```
RC 级别：每次 SELECT 都创建新的 ReadView

时间线：
  t1: 事务100 INSERT id=1, val='A' 并提交
  t2: 事务200 BEGIN
  t3: 事务200 SELECT → ReadView1 创建
      ReadView1: m_low_limit_id=201, m_up_limit_id=200, m_ids=[200]
      → 读到 val='A' (trx_id=100 < 200, 可见)
      
  t4: 事务300 UPDATE val='B'; COMMIT
  
  t5: 事务200 SELECT → ReadView2 创建（新的！）
      ReadView2: m_low_limit_id=301, m_up_limit_id=200, m_ids=[200]
      (事务300已提交，不在活跃列表中)
      
      版本链：
      v2: val='B', trx_id=300
      v1: val='A', trx_id=100
      
      v2: trx_id=300
      300 >= m_low_limit_id(301)? No
      300 < m_up_limit_id(200)? No
      300 == m_creator_trx_id(200)? No
      300 in m_ids([200])? No → 可见 ✓
      
      → 读到 val='B' ← 不可重复读！
```

### 3.9 ReadView 创建时机总结

```
┌─────────────────────────────────────────────────────────────────┐
│                ReadView 创建时机对比                              │
├─────────────────┬───────────────────────────────────────────────┤
│   READ COMMITTED│  每次执行 SELECT 都创建新的 ReadView           │
│      (RC)       │  → 能看到其他事务最新提交的数据                 │
│                 │  → 不可重复读                                  │
├─────────────────┼───────────────────────────────────────────────┤
│ REPEATABLE READ │  事务中第一次 SELECT 时创建 ReadView           │
│      (RR)       │  之后所有 SELECT 复用这个 ReadView             │
│                 │  → 看到的数据停留在第一次 SELECT 时的快照       │
│                 │  → 可重复读                                    │
├─────────────────┼───────────────────────────────────────────────┤
│  READ UNCOMMITTED│ 不创建 ReadView，直接读最新版本               │
│      (RU)       │  → 脏读                                       │
├─────────────────┼───────────────────────────────────────────────┤
│  SERIALIZABLE   │  不走 MVCC，SELECT 隐式加 S锁                  │
│                 │  → 串行执行                                    │
└─────────────────┴───────────────────────────────────────────────┘

注意：只有"快照读"（普通 SELECT）走 MVCC。
"当前读"（SELECT FOR UPDATE / UPDATE / DELETE）不走 MVCC，读最新版本+加锁。
```

### 3.10 MVCC 的 purge 问题 — 何时清理 Undo Log

```
Undo Log 版本链不能无限增长，需要 Purge 线程清理。

清理条件：某版本对所有活跃事务都不可见（即没有任何 ReadView 需要它）

  ┌─────────────────────────────────────────────────────────┐
  │  活跃事务 A 的 ReadView：m_up_limit_id = 100            │
  │  活跃事务 B 的 ReadView：m_up_limit_id = 200            │
  │                                                         │
  │  → 系统最小 ReadView 的 m_up_limit_id = 100             │
  │                                                         │
  │  Undo Log 中 trx_id < 100 的版本可以清理                │
  │  （因为所有活跃事务都不可能再看到它们）                    │
  └─────────────────────────────────────────────────────────┘

Purge 线程源码（简化）：

  // storage/innobase/trx/trx0purge.cc
  
  void trx_purge(trx_id_t limit) {
      // limit = 最小的活跃 ReadView 的 m_up_limit_id
      // 清理 Undo Log 中 trx_id < limit 的记录
      
      while (undo_rec = get_next_undo_rec()) {
          if (undo_rec->trx_id < limit) {
              // 可以安全清理
              purge_undo_rec(undo_rec);
          } else {
              break;  // 后面的都不能清理
          }
      }
  }
```

**长事务的危害**：

```
长事务（运行时间很长的事务）会导致：
  1. Undo Log 无法清理 → Undo 表空间膨胀 → 磁盘空间告警
  2. 版本链变长 → MVCC 遍历链表查找可见版本变慢 → 查询变慢
  3. 占着锁不释放 → 其他事务等待 → 连接堆积
  
监控：
  SELECT * FROM information_schema.innodb_trx 
  WHERE TIME_TO_SEC(TIMEDIFF(NOW(), trx_started)) > 60;
  -- 查找运行超过60秒的事务
```

---

## 第四部分：Undo Log — 版本链的源头

### 4.1 Undo Log 的两大作用

```
┌─────────────────────────────────────────────────────────┐
│                   Undo Log 的两大作用                     │
├─────────────────────┬───────────────────────────────────┤
│  1. 事务回滚         │  修改前记录旧值，ROLLBACK 时恢复   │
│   (Atomicity)       │  → 保证原子性                     │
├─────────────────────┼───────────────────────────────────┤
│  2. MVCC 版本链      │  为快照读提供历史版本数据          │
│   (Isolation)       │  → 保证隔离性                     │
└─────────────────────┴───────────────────────────────────┘
```

### 4.2 Undo Log 的两种类型

```
┌─────────────────────────────────────────────────────────────────┐
│                    Undo Log 两种类型                             │
├─────────────────┬───────────────────────────────────────────────┤
│                 │  INSERT 操作产生的 Undo Log                   │
│  Insert Undo    │                                               │
│  Log            │  内容：记录主键值                              │
│                 │  回滚方式：按主键直接 DELETE                   │
│                 │  生命周期：事务提交后立即可被 Purge 清理        │
│                 │  （因为 INSERT 的新行对其他事务原本就不可见）   │
│                 │  存储位置：trx_undo_t (insert_undo)           │
├─────────────────┼───────────────────────────────────────────────┤
│                 │  UPDATE / DELETE 操作产生的 Undo Log          │
│  Update Undo    │                                               │
│  Log            │  内容：记录旧值的完整信息                      │
│                 │  回滚方式：用旧值覆盖当前值 / 重新 INSERT      │
│                 │  生命周期：事务提交后，需等 Purge 线程清理      │
│                 │  （因为 MVCC 可能还需要旧版本）                │
│                 │  存储位置：trx_undo_t (update_undo)           │
└─────────────────┴───────────────────────────────────────────────┘
```

### 4.3 Undo Log 记录类型

```c
// storage/innobase/trx/trx0types.h

enum trx_undo_rec_type {
    TRX_UNDO_INSERT_REC = 1,         // INSERT 记录
    
    // MySQL 8.0 简化了 UPDATE 类型
    TRX_UNDO_UPD_EXIST_REC = 2,      // UPDATE 已存在记录
    // (MySQL 5.7 还有 TRX_UNDO_UPD_DEL_REC 和 TRX_UNDO_DEL_MARK_REC
    //  MySQL 8.0 统一为 UPD_EXIST_REC)
    
    TRX_UNDO_DEL_MARK_REC = 3,       // DELETE 标记删除
    
    // ... 其他类型
};
```

### 4.4 INSERT 的 Undo Log 格式

```
INSERT 产生的 Undo Log 记录格式：

  ┌──────────────┬──────────────┬──────────────────────────┐
  │ Undo Type    │ DB_TRX_ID    │ Primary Key Fields       │
  │ (1 byte)     │ (6 bytes)    │ (变长)                   │
  │ INSERT_REC   │              │                          │
  └──────────────┴──────────────┴──────────────────────────┘

  回滚时：
  DELETE FROM table WHERE pk = <记录的主键值>

  示例：
  INSERT INTO t (id, name) VALUES (1, 'Alice');
  
  Undo Log:
    type: TRX_UNDO_INSERT_REC
    trx_id: 当前事务ID
    primary_key: id=1
  
  回滚 = DELETE FROM t WHERE id=1
```

### 4.5 UPDATE 的 Undo Log 格式

```
UPDATE 产生的 Undo Log 记录格式：

  ┌──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐
  │ Undo Type    │ DB_TRX_ID    │ Update Number│ Info Bits    │ Old Values   │
  │ UPD_EXIST    │ (6 bytes)    │ (2 bytes)    │ (1 byte)     │ (变长)       │
  │ _REC         │              │              │              │              │
  └──────────────┴──────────────┴──────────────┴──────────────┴──────────────┘
  
  Old Values 包含：
    - 被修改列的旧值（只记录修改的列，不记录所有列）
    - 主键值（如果主键被修改，还需记录旧主键）

  示例：
  UPDATE t SET name='Bob' WHERE id=1;  -- 原来 name='Alice'
  
  Undo Log:
    type: TRX_UNDO_UPD_EXIST_REC
    trx_id: 当前事务ID
    update_number: 1 (当前Undo页中第几次更新)
    old_values: name='Alice'
  
  回滚 = UPDATE t SET name='Alice' WHERE id=1
```

### 4.6 DELETE 的 Undo Log 格式

```
DELETE 产生的 Undo Log 记录格式（标记删除）：

  InnoDB 的 DELETE 不是立即物理删除，而是：
  1. 标记记录的 deleted_flag = 1
  2. 在 Undo Log 记录完整旧值
  3. Purge 线程后续物理删除

  ┌──────────────┬──────────────┬──────────────────────────┐
  │ Undo Type    │ DB_TRX_ID    │ All Column Values        │
  │ DEL_MARK     │ (6 bytes)    │ (变长，完整行)           │
  │ _REC         │              │                          │
  └──────────────┴──────────────┴──────────────────────────┘

  注意：DELETE 的 Undo 记录了完整行数据，因为回滚时需要重新 INSERT
  
  回滚 = INSERT INTO t VALUES (完整旧值)
```

### 4.7 Undo Log 存储结构

```
Undo Log 的物理存储层次：

  ┌─────────────────────────────────────────────────────────┐
  │                    Undo TableSpace                      │
  │  (独立的表空间文件 undo001, undo002, ...)               │
  │                                                         │
  │  ┌─────────────────────────────────────────────────┐   │
  │  │                Rollback Segment                  │   │
  │  │           (回滚段，128个， trx_rseg_t)            │   │
  │  │                                                 │   │
  │  │  ┌──────────┐ ┌──────────┐ ┌──────────┐       │   │
  │  │  │ Undo Slot│ │ Undo Slot│ │ Undo Slot│  ...   │   │
  │  │  │ 0        │ │ 1        │ │ 2        │        │   │
  │  │  └────┬─────┘ └────┬─────┘ └────┬─────┘       │   │
  │  └───────┼────────────┼────────────┼──────────────┘   │
  │          │            │            │                    │
  │  ┌───────▼────────────▼────────────▼──────────────┐   │
  │  │            Undo Log Segment                     │   │
  │  │         (Undo 日志段，多个 Undo 页)              │   │
  │  │                                                 │   │
  │  │  ┌────────┐ ┌────────┐ ┌────────┐             │   │
  │  │  │Undo    │→│Undo    │→│Undo    │→ ...        │   │
  │  │  │Page 1  │ │Page 2  │ │Page 3  │             │   │
  │  │  └────────┘ └────────┘ └────────┘             │   │
  │  │                                                 │   │
  │  │  每个 Undo Page (16KB) 包含多条 Undo 记录       │   │
  │  └─────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────┘

层次关系：
  Undo Tablespace → Rollback Segment (128个) → Undo Slot (1024个/段)
  → Undo Log Segment → Undo Page → Undo Record

事务分配回滚段：
  trx_assign_rseg_low() → 从 rseg_array 中选择一个回滚段
  每个事务最多使用 2 个 Undo Log：
    1 个 insert_undo（用于 INSERT）
    1 个 update_undo（用于 UPDATE/DELETE）
```

### 4.8 Undo Log 与事务的关联

```c
// storage/innobase/trx/trx0trx.cc (简化)

// 事务开始时分配回滚段
dberr_t trx_start_low(trx_t *trx, ulint rseg_id) {
    // 分配回滚段
    trx->rseg = trx_rseg_get_on_id(rseg_id);
    
    // 分配 Undo Log 段（延迟分配，第一次修改时才分配）
    trx->insert_undo = NULL;
    trx->update_undo = NULL;
    
    trx->state = TRX_STATE_ACTIVE;
    
    return DB_SUCCESS;
}

// 执行 INSERT 时
dberr_t trx_undo_report_row_operation(...) {
    if (op_type == TRX_UNDO_INSERT_OP) {
        // 使用 insert_undo
        if (!trx->insert_undo) {
            // 分配 insert_undo slot
            trx_undo_assign_undo(trx, TRX_UNDO_INSERT);
        }
        undo_page = trx_undo_get_page(trx->insert_undo);
        // 写入 INSERT Undo 记录
        trx_undo_insert_rec_write(undo_page, ...);
    } else {
        // UPDATE/DELETE 使用 update_undo
        if (!trx->update_undo) {
            trx_undo_assign_undo(trx, TRX_UNDO_UPDATE);
        }
        undo_page = trx_undo_get_page(trx->update_undo);
        // 写入 UPDATE/DELETE Undo 记录
        trx_undo_update_rec_write(undo_page, ...);
    }
}
```

### 4.9 Purge 线程 — 清理 Undo Log

```c
// storage/innobase/trx/trx0purge.cc (简化)

// Purge 线程的主循环
void trx_purge_truncate() {
    while (true) {
        // 1. 获取最旧的活跃 ReadView
        ReadView *oldest_view = MVCC::get_oldest_view();
        trx_id_t limit = oldest_view ? oldest_view->m_up_limit_id : 0;
        
        // 2. 扫描 Undo Log，清理 trx_id < limit 的记录
        while (undo_rec = get_next_undo_record()) {
            if (undo_rec->trx_id < limit) {
                // 可以清理
                // 对于 DELETE 标记的记录：物理删除
                // 对于 Undo Log 记录：释放空间
                purge_record(undo_rec);
            } else {
                break;
            }
        }
        
        // 3. 回收 Undo Log 段空间
        trx_purge_truncate_marked_undo();
        
        // 4. 等待下一轮
        os_event_wait(purge_event);
    }
}
```

**Purge 相关参数**：

```sql
-- 控制 Purge 线程数量
innodb_purge_threads = 4  (默认4个 purge 线程)

-- 控制每轮 Purge 最多清理的 Undo Page 数量
innodb_purge_batch_size = 300  (默认300页)

-- 控制Undo表空间回收
innodb_undo_log_truncate = ON  (MySQL 8.0 默认开启)
innodb_max_undo_log_size = 1GB  (超过此大小触发截断)
innodb_undo_log_truncate_frequency = 128 (每128次purge检查一次)
```

### 4.10 Undo Log 与回滚过程

```c
// storage/innobase/trx/trx0roll.cc (简化)

// 事务回滚
dberr_t trx_rollback(trx_t *trx, bool partial) {
    // 1. 先回滚 update_undo（最近的修改先回滚）
    if (trx->update_undo) {
        trx_undo_traverse(trx->update_undo, trx_undo_rollback_rec);
    }
    
    // 2. 再回滚 insert_undo
    if (trx->insert_undo) {
        trx_undo_traverse(trx->insert_undo, trx_undo_rollback_rec);
    }
    
    // 3. 释放 Undo Log 段
    trx_undo_free(trx);
    
    trx->state = TRX_STATE_COMMITTED_IN_MEMORY;
    
    return DB_SUCCESS;
}

// 回滚单条 Undo 记录
dberr_t trx_undo_rollback_rec(trx_t *trx, undo_rec_t *undo_rec) {
    switch (undo_rec->type) {
        case TRX_UNDO_INSERT_REC:
            // INSERT 的回滚 = DELETE
            row_undo_rec_remove(undo_rec);
            break;
            
        case TRX_UNDO_UPD_EXIST_REC:
            // UPDATE 的回滚 = 用旧值覆盖
            row_undo_rec_update(undo_rec);
            break;
            
        case TRX_UNDO_DEL_MARK_REC:
            // DELETE 的回滚 = 清除删除标记 + 恢复数据
            row_undo_rec_unmark(undo_rec);
            break;
    }
}
```

---

## 第五部分：Redo Log — WAL 与崩溃恢复

### 5.1 WAL（Write-Ahead Logging）核心思想

```
WAL 原则：先写日志，再写数据

  没有 WAL 的问题：
  
  ┌──────────────────────────────────────────────┐
  │  事务修改数据页 → 直接写入磁盘的数据文件       │
  │                                              │
  │  如果写入中途崩溃：                            │
  │  - 数据页可能写了一半（torn page）             │
  │  - 无法知道哪些修改已完成，哪些未完成           │
  │  - 无法恢复到一致性状态                        │
  └──────────────────────────────────────────────┘
  
  有 WAL 的方案：
  
  ┌──────────────────────────────────────────────┐
  │  事务修改数据页：                              │
  │                                              │
  │  Step 1: 修改 Buffer Pool 中的数据页（内存）   │
  │  Step 2: 将修改记录写入 Redo Log Buffer（内存）│
  │  Step 3: 将 Redo Log Buffer 刷到磁盘（redo log file）│
  │  Step 4: 异步将 Buffer Pool 的脏页刷到磁盘（数据文件）│
  │                                              │
  │  崩溃恢复时：                                  │
  │  - 重放 Redo Log，恢复所有已提交的修改          │
  │  - 数据文件的随机 I/O 变成 redo log 的顺序 I/O  │
  └──────────────────────────────────────────────┘

  性能优势：
  - 随机写（数据页）→ 顺序写（redo log）
  - 多次小写（数据页）→ 一次大写（redo log group commit）
  - 写性能大幅提升
```

### 5.2 Redo Log 物理结构

```
Redo Log 文件结构：

  ib_logfile0    ib_logfile1    ib_logfile2    ...
  ┌──────────┐   ┌──────────┐   ┌──────────┐
  │  512B    │   │  512B    │   │  512B    │   ← 每个 512 字节的 block
  │  header  │   │  header  │   │  header  │
  ├──────────┤   ├──────────┤   ├──────────┤
  │  Data    │   │  Data    │   │  Data    │   ← 496 字节的数据区
  │  (496B)  │   │  (496B)  │   │  (496B)  │
  ├──────────┤   ├──────────┤   ├──────────┤
  │  Trailer │   │  Trailer │   │  Trailer │   ← 4 字节的尾部校验
  │  (4B)    │   │  (4B)    │   │  (4B)    │
  ├──────────┤   ├──────────┤   ├──────────┤
  │  512B    │   │  512B    │   │  512B    │   ← 下一个 block
  │  ...     │   │  ...     │   │  ...     │
  └──────────┘   └──────────┘   └──────────┘
  
  循环写入：写满 ib_logfile0 → 写 ib_logfile1 → ... → 覆盖 ib_logfile0

Redo Log Block 结构 (512 bytes)：
  ┌─────────────────────────────────────────┐
  │ Block Header (12 bytes)                 │
  │  ├── LOG_BLOCK_HDR_NO (4B): block序号   │
  │  ├── LOG_BLOCK_DATA_LEN (2B): 数据长度  │
  │  └── LOG_BLOCK_FIRST_REC (2B): 第一条   │
  │      完整记录的偏移量                     │
  │      (0 = 本block无完整记录，续上一个)    │
  ├─────────────────────────────────────────┤
  │ Block Data (496 bytes)                  │
  │  └── Redo Log Records                   │
  ├─────────────────────────────────────────┤
  │ Block Trailer (4 bytes)                 │
  │  └── LOG_BLOCK_CHECKSUM (4B): 校验和    │
  └─────────────────────────────────────────┘
```

### 5.3 LSN（Log Sequence Number）

```
LSN 是 Redo Log 的全局递增序列号，贯穿整个 InnoDB：

  ┌──────────────────────────────────────────────────────────────┐
  │                       LSN 体系                               │
  ├──────────────────┬───────────────────────────────────────────┤
  │ LSN              │ 全局日志序列号，单调递增                    │
  │ (Log Sequence    │ 每写入一定量的 redo log，LSN 就增加        │
  │  Number)         │                                           │
  ├──────────────────┼───────────────────────────────────────────┤
  │ flush_lsn        │ 已经刷到 Redo Log 文件的 LSN               │
  ├──────────────────┼───────────────────────────────────────────┤
  │ write_lsn        │ 已经写入 Redo Log Buffer 的 LSN            │
  ├──────────────────┼───────────────────────────────────────────┤
  │ buf_lsn          │ Redo Log Buffer 中的最新 LSN               │
  ├──────────────────┼───────────────────────────────────────────┤
  │ checkpoint_lsn   │ 最新 checkpoint 的 LSN                     │
  │                  │ 恢复时从这里开始重放 redo log               │
  ├──────────────────┼───────────────────────────────────────────┤
  │ oldest_lsn       │ Buffer Pool 中最旧的脏页对应的 LSN          │
  │                  │ checkpoint_lsn 不能超过此值                │
  └──────────────────┴───────────────────────────────────────────┘

  关系：buf_lsn >= write_lsn >= flush_lsn >= checkpoint_lsn
  
  查看当前 LSN：
  SHOW ENGINE INNODB STATUS\G
  ---
  LOG
  ---
  Log sequence number 1234567890      ← buf_lsn（最新写入的）
  Log buffer assigned up to 1234567890
  Log buffer flushed up to 1234567800 ← flush_lsn
  Log written up to 1234567800        ← write_lsn
  LSN 1234567000                      ← checkpoint_lsn
```

### 5.4 Redo Log 的写入流程

```
                     Redo Log 写入流程

  事务执行                     Redo Log Buffer           Redo Log File
  ┌────────┐                  ┌──────────────┐          ┌────────────┐
  │修改Buffer│ ──mtr_commit──→ │ 写入 Redo    │──flush──→│ 写入磁盘    │
  │Pool脏页  │                  │ Log Buffer   │          │ ib_logfile  │
  └────────┘                  └──────────────┘          └────────────┘
       │                              │                        │
       │                              │                        │
   修改在内存中                    日志先写入内存            定期刷盘
   （此时是脏页）                  （很快）                   （保证持久性）

  详细步骤：
  
  1. Mini-Transaction (mtr) 阶段：
     - 一个 mtr 是一组不可分割的修改
     - 修改 Buffer Pool 中的数据页
     - 将修改对应的 redo log entry 写入 mtr 的本地 buffer
     
  2. mtr_commit 阶段：
     - 将 mtr buffer 中的 redo log 写入全局 Redo Log Buffer
     - 同时将修改的脏页加入 Buffer Pool 的 flush list
     - 更新 buf_lsn
     
  3. Flush 阶段：
     - 后台线程将 Redo Log Buffer 刷到磁盘文件
     - 更新 flush_lsn
     - 触发时机：
       a. 事务提交时（COMMIT 触发 flush）
       b. Redo Log Buffer 半满（> innodb_log_buffer_size / 2）
       c. 后台线程每秒刷一次
       d. MySQL 关闭时
```

### 5.5 Mini-Transaction (mtr) — 原子操作

```c
// storage/innobase/mtr/mtr0mtr.cc (简化)

// mtr 是 InnoDB 内部的"微型事务"
// 保证一组操作在物理层面是原子的

struct mtr_t {
    // mtr 的本地 redo log buffer
    mtr_buf_t   m_memo;    // 修改的页的 latch
    mtr_buf_t   m_log;     // redo log 记录
    
    lsn_t       m_commit_lsn;  // commit 时分配的 LSN
    bool        m_made_dirty;  // 是否产生了脏页
    
    mtr_state_t m_state;   // MTR_ACTIVE / MTR_COMMITTING / MTR_COMMITTED
};

// mtr 提交
void mtr_t::commit() {
    // 1. 将 mtr 的 redo log 写入全局 Redo Log Buffer
    lsn_t lsn = log_buffer_write(m_log);
    
    // 2. 将脏页加入 flush list
    if (m_made_dirty) {
        buf_flush_list_add(m_modified_pages);
    }
    
    // 3. 如果是同步 mtr，立即刷盘
    if (m_sync) {
        log_write_up_to(lsn);  // 确保写到 lsn
    }
    
    m_state = MTR_COMMITTED;
    m_commit_lsn = lsn;
}

// 使用示例：修改一行的值
dberr_t btr_cur_update_in_place(...) {
    mtr_t mtr;
    mtr_start(&mtr);
    
    // 获取页的 X-latch
    buf_block_t *block = buf_page_get(page_id, RW_X_LATCH, &mtr);
    
    // 修改数据
    rec_t *rec = page_rec_find(block, key);
    rec_set_col(rec, col_offset, new_value);
    
    // 记录 redo log
    mlog_write_ulint(rec + col_offset, new_value, &mtr);
    
    // 记录 undo log（在 mtr 内）
    trx_undo_report_row_operation(..., &mtr);
    
    // 提交 mtr（原子操作）
    mtr_commit(&mtr);
}
```

### 5.6 Redo Log 记录格式

```
Redo Log 记录格式：

  ┌──────────────┬──────────────┬──────────────────────────┐
  │ Type (1B)    │ Space ID(4B) │ Page No (4B)             │
  │ 记录类型     │ 表空间ID     │ 页号                      │
  ├──────────────┴──────────────┴──────────────────────────┤
  │ Body (变长)                                              │
  │ 根据类型不同，记录不同的修改内容                          │
  └─────────────────────────────────────────────────────────┘

常见 Redo Log 类型：

  MLOG_1BYTE  : 修改1字节 (如 flag 修改)
  MLOG_2BYTE  : 修改2字节 (如 16位整数字段)
  MLOG_4BYTE  : 修改4字节 (如 32位整数字段)
  MLOG_8BYTE  : 修改8字节 (如 64位整数字段、trx_id)
  MLOG_WRITE_STRING : 修改变长数据
  
  MLOG_REC_INSERT      : INSERT 一行记录
  MLOG_REC_DELETE      : DELETE 一行记录
  MLOG_REC_UPDATE_IN_PLACE : 原地 UPDATE
  
  MLOG_LIST_START_DELETE    : 页中记录列表删除开始
  MLOG_LIST_END_COPY_CREATED : 页中记录列表删除结束
  
  MLOG_PAGE_CREATE     : 创建新页
  MLOG_8BYTES          : 修改8字节（如 B+Tree 节点指针）
  
  MLOG_INDEX_LOAD      : 索引加载（CREATE INDEX）
  
  MLOG_TABLE_DYNAMIC_META : 表的动态元数据变更
```

### 5.7 Checkpoint 机制

```
Checkpoint 的作用：
  - 记录"哪些脏页已经刷到磁盘"
  - 崩溃恢复时，只需重放 checkpoint 之后的 redo log
  - 加速恢复过程

Checkpoint 类型：

  1. Sharp Checkpoint：
     - 将所有脏页刷到磁盘
     - 恢复时几乎不需要重放 redo log
     - 但刷盘时系统停顿严重
     - 只在 MySQL 正常关闭时使用（innodb_fast_shutdown）
  
  2. Fuzzy Checkpoint（InnoDB 默认）：
     - 只刷部分脏页
     - 后台线程持续运行
     - 4 种触发条件：
       a. Master Thread 每秒刷（异步）
       b. Flush List 中脏页太多（old > innodb_max_dirty_pages_pct）
       c. Redo Log 空间不足（即将被覆盖）
       d. 用户线程空闲时帮忙刷

Checkpoint 过程：

  ┌──────────────────────────────────────────────────────┐
  │  Redo Log 文件（循环使用）                            │
  │                                                      │
  │  ┌──checkpoint_lsn──→──write_lsn──→                 │
  │  │                  ↑                                │
  │  │    可覆盖区域     │  活跃区域（未刷盘的脏页对应）   │
  │  │  (已刷盘)        │                                │
  │  ▼                  │                                │
  │  ═══════════════════╪══════════════════════════     │
  │  ← 文件开头          │                    文件末尾 →  │
  │                      │                                │
  │  checkpoint_lsn 之前的 redo log 可以被覆盖            │
  │  因为对应的脏页已经刷到数据文件                        │
  └──────────────────────────────────────────────────────┘

  Checkpoint 更新：
  - 后台线程定期执行 checkpoint
  - 将 Buffer Pool 中 LSN <= target_lsn 的脏页刷到磁盘
  - 更新 checkpoint_lsn = target_lsn
  - 将新的 checkpoint_lsn 写入 redo log 的 header

  Redo Log 空间不足时的处理：
  - 如果 write_lsn 追上了 checkpoint_lsn + redo_log_file_size
  - 说明 redo log 即将被覆盖，但对应的脏页还没刷盘
  - 触发同步刷盘（flush_sync），阻塞用户线程
  - 这就是 "redo log stall" 现象
```

### 5.8 Group Commit — 组提交

```
Group Commit：多个事务的 redo log 合并为一次 I/O 写入

  没有 Group Commit：
  
  事务A COMMIT ──→ flush redo log A ──→ 磁盘I/O
  事务B COMMIT ──→ flush redo log B ──→ 磁盘I/O
  事务C COMMIT ──→ flush redo log C ──→ 磁盘I/O
  3次磁盘I/O，性能差

  有 Group Commit：
  
  事务A COMMIT ──→ ┐
  事务B COMMIT ──→ ├──→ 一次 flush ──→ 一次磁盘I/O
  事务C COMMIT ──→ ┘
  1次磁盘I/O，性能好

  MySQL 8.0 的 Group Commit 实现（两阶段）：

  Phase 1: Flush 阶段
  - 多个事务的 redo log 写入 Redo Log Buffer
  - 第一个进入 flush 的事务成为 leader
  - 其他事务等待
  
  Phase 2: Sync 阶段
  - Leader 将 Redo Log Buffer 刷到磁盘
  - Followers 等待
  
  事务A: flush → sync → done
  事务B: flush → wait → done (follower)
  事务C: flush → wait → done (follower)

  相关参数：
  innodb_flush_log_at_trx_commit = 1  (默认)
    0: 每秒刷盘（可能丢失1秒数据）
    1: 每次提交都刷盘（最安全，性能最低）
    2: 每次提交写入OS Buffer，每秒刷盘（折中）
  
  innodb_log_buffer_size = 16MB  (默认，可增大以支持更大事务)
```

### 5.9 崩溃恢复（Crash Recovery）

```
崩溃恢复流程：

  MySQL 启动 → 读取 checkpoint_lsn → 从 checkpoint_lsn 开始重放 redo log

  ┌──────────────────────────────────────────────────────────┐
  │                    崩溃恢复流程                           │
  │                                                          │
  │  1. 读取最后一个 checkpoint                              │
  │     checkpoint_lsn = 1234567000                         │
  │                                                          │
  │  2. 从 checkpoint_lsn 开始扫描 redo log                  │
  │     依次读取每条 redo log entry                          │
  │                                                          │
  │  3. 对每条 redo log entry：                              │
  │     a. 解析出 (space_id, page_no, modification)         │
  │     b. 检查 Buffer Pool 中该页的 LSN                     │
  │     c. 如果 redo log entry 的 LSN > 页的 LSN：           │
  │        - 重放修改（apply redo）                          │
  │        - 更新页的 LSN                                    │
  │     d. 如果 redo log entry 的 LSN <= 页的 LSN：          │
  │        - 跳过（该修改已经持久化）                         │
  │                                                          │
  │  4. 处理未完成的事务：                                    │
  │     a. 扫描 Undo Log                                    │
  │     b. 对于 state = ACTIVE 的事务：                      │
  │        - 事务未提交 → 回滚                               │
  │     c. 对于 state = PREPARED 的事务：                    │
  │        - 检查 Binlog 中是否有对应的 XID                  │
  │        - 有 → 提交（2PC 第二阶段）                       │
  │        - 无 → 回滚                                       │
  │                                                          │
  │  5. 清理 Undo Log 中已完成事务的记录                      │
  │                                                          │
  │  6. 新的 checkpoint，恢复正常服务                         │
  └──────────────────────────────────────────────────────────┘

  源码入口：
  // storage/innobase/srv/srv0start.cc
  DB_SUCCESS srv_start(create_info) {
      // ...
      // 崩溃恢复
      if (recv_recovery_from_checkpoint_start(checkpoint_lsn)) {
          // 重放 redo log
          recv_apply_hashed_log_recs();
      }
      recv_recovery_from_checkpoint_finish();
      // 回滚未完成的事务
      trx_rollback_or_clean_all_without_sess();
      // ...
  }
```

### 5.10 Redo Log 与 Binlog 的区别

```
┌──────────────────────────────────────────────────────────────────┐
│              Redo Log vs Binlog 对比                              │
├──────────────┬─────────────────────────┬─────────────────────────┤
│    属性       │ Redo Log                │ Binlog                  │
├──────────────┼─────────────────────────┼─────────────────────────┤
│ 归属         │ InnoDB 引擎层            │ MySQL Server 层         │
│              │ (storage/innobase)      │ (sql/binlog)            │
├──────────────┼─────────────────────────┼─────────────────────────┤
│ 格式         │ 物理日志（记录页的修改） │ 逻辑日志（SQL语句/行变更）│
│              │ "page X offset Y = Z"   │ "UPDATE t SET..."       │
├──────────────┼─────────────────────────┼─────────────────────────┤
│ 写入方式     │ 顺序循环写               │ 追加写（文件切换）       │
│              │ (文件会被覆盖)           │ (文件不会被覆盖)        │
├──────────────┼─────────────────────────┼─────────────────────────┤
│ 用途         │ 崩溃恢复（Crash Recovery）│ 主从复制 + PITR恢复     │
│              │ + 保证持久性             │                         │
├──────────────┼─────────────────────────┼─────────────────────────┤
│ 粒度         │ 细粒度（每个页的每次修改）│ 粗粒度（每条SQL/每行变更）│
├──────────────┼─────────────────────────┼─────────────────────────┤
│ 事务性       │ 自动保证（mtr 原子写入） │ 通过 2PC 保证一致性      │
├──────────────┼─────────────────────────┼─────────────────────────┤
│ 写入时机     │ 事务执行过程中持续写     │ 事务提交时写            │
├──────────────┼─────────────────────────┼─────────────────────────┤
│ 大小         │ 固定大小（循环使用）     │ 无限增长（可设置过期）   │
│              │ innodb_log_file_size    │ binlog_expire_logs_secs │
└──────────────┴─────────────────────────┴─────────────────────────┘
```

---

## 第六部分：Buffer Pool 与事务的协同

### 6.1 Buffer Pool 中的事务相关数据结构

```
Buffer Pool 中的三个核心链表（与事务相关）：

  ┌─────────────────────────────────────────────────────────────┐
  │                     Buffer Pool                             │
  │                                                             │
  │  ┌─────────────────────────────────────────────────────┐   │
  │  │  Free List（空闲页链表）                              │   │
  │  │  ┌────┐ ┌────┐ ┌────┐                                │   │
  │  │  │page│→│page│→│page│→ NULL                          │   │
  │  └─────┘ └────┘ └────┘                                    │   │
  │  未使用的空闲页，等待分配                                    │   │
  │                                                             │
  │  ┌─────────────────────────────────────────────────────┐   │
  │  │  LRU List（最近使用页链表）                           │   │
  │  │  ┌──────────────────────┬──────────────────────┐    │   │
  │  │  │   Old 区域 (3/8)      │   Young 区域 (5/8)   │    │   │
  │  │  │  ┌────┐ ┌────┐ ┌───┐│  ┌────┐ ┌────┐ ┌───┐│    │   │
  │  │  │  │page│→│page│→│pge││→│page│→│page│→│pge││    │   │
  │  │  │  └────┘ └────┘ └───┘│  └────┘ └────┘ └───┘│    │   │
  │  │  │  cold←──────────────→│←──────────────→hot  │    │   │
  │  │  └──────────────────────┴──────────────────────┘    │   │
  │  │  数据页按访问顺序排列，cold端优先淘汰                  │   │
  │  └─────────────────────────────────────────────────────┘   │
  │                                                             │
  │  ┌─────────────────────────────────────────────────────┐   │
  │  │  Flush List（脏页链表）                               │   │
  │  │  ┌────┐ ┌────┐ ┌────┐                                │   │
  │  │  │page│→│page│→│page│→ NULL                          │   │
  │  │  │LSN1│ │LSN2│ │LSN3│                                │   │
  │  │  └────┘ └────┘ └────┘                                │   │
  │  │  按 LSN 排序（ oldest → newest ）                     │   │
  │  │  被修改过的页，等待刷盘                                │   │
  │  └─────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────┘
```

### 6.2 修改一行的完整流程（事务 + Buffer Pool + Redo Log + Undo Log）

```
  UPDATE t SET val = 'new' WHERE id = 1;

  ┌──────────────────────────────────────────────────────────────────┐
  │  Step 1: 查找记录                                                │
  │  ┌──────────────────────────────────────────────────┐           │
  │  │  Buffer Pool 中是否有 id=1 所在的页？              │           │
  │  │  ├─ YES → 直接使用                                 │           │
  │  │  └─ NO  → 从 Free List 取一页 → 从磁盘读取         │           │
  │  │           → 加入 LRU List                          │           │
  │  └──────────────────────────────────────────────────┘           │
  │                           │                                     │
  │  Step 2: 开启 mtr，获取页的 X-latch                              │
  │  ┌──────────────────────────────────────────────────┐           │
  │  │  mtr_start(&mtr)                                  │           │
  │  │  buf_page_get(page_id, RW_X_LATCH, &mtr)         │           │
  │  └──────────────────────────────────────────────────┘           │
  │                           │                                     │
  │  Step 3: 记录 Undo Log                                          │
  │  ┌──────────────────────────────────────────────────┐           │
  │  │  将旧值 val='old' 写入 Undo Log Buffer             │           │
  │  │  设置记录的 DB_TRX_ID = 当前事务ID                 │           │
  │  │  设置记录的 DB_ROLL_PTR → Undo Log 记录位置        │           │
  │  └──────────────────────────────────────────────────┘           │
  │                           │                                     │
  │  Step 4: 修改数据（内存）                                       │
  │  ┌──────────────────────────────────────────────────┐           │
  │  │  在 Buffer Pool 中修改记录的 val = 'new'           │           │
  │  │  页变为脏页（dirty）                               │           │
  │  │  → 加入 Flush List（如果还不在的话）               │           │
  │  └──────────────────────────────────────────────────┘           │
  │                           │                                     │
  │  Step 5: 记录 Redo Log                                          │
  │  ┌──────────────────────────────────────────────────┐           │
  │  │  将修改操作写入 mtr 的 redo buffer                 │           │
  │  │  mlog_write_string(page, offset, 'new', &mtr)    │           │
  │  └──────────────────────────────────────────────────┘           │
  │                           │                                     │
  │  Step 6: mtr_commit                                             │
  │  ┌──────────────────────────────────────────────────┐           │
  │  │  将 mtr 的 redo log 写入全局 Redo Log Buffer       │           │
  │  │  更新 buf_lsn                                     │           │
  │  │  脏页加入 Flush List（按 LSN 排序）               │           │
  │  │  释放页的 X-latch                                  │           │
  │  └──────────────────────────────────────────────────┘           │
  │                           │                                     │
  │  Step 7: COMMIT                                                │
  │  ┌──────────────────────────────────────────────────┐           │
  │  │  将 Redo Log Buffer 刷到磁盘（WAL保证）            │           │
  │  │  写 Binlog                                        │           │
  │  │  更新 Redo Log 的 commit 标记                      │           │
  │  │  事务状态 → COMMITTED                              │           │
  │  │  Undo Log 保留（供 MVCC 使用，等 Purge 清理）      │           │
  │  └──────────────────────────────────────────────────┘           │
  │                           │                                     │
  │  Step 8: 后台异步刷脏页                                         │
  │  ┌──────────────────────────────────────────────────┐           │
  │  │  后台线程将 Flush List 中的脏页刷到数据文件         │           │
  │  │  从 Flush List 移除                               │           │
  │  │  更新 checkpoint_lsn                              │           │
  │  └──────────────────────────────────────────────────┘           │
  └──────────────────────────────────────────────────────────────────┘
```

### 6.3 Flush List 的 LSN 排序与 Checkpoint

```
Flush List 按页的 oldest_modification (oldest_lsn) 排序：

  Flush List:
  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
  │ Page A   │──→│ Page B   │──→│ Page C   │──→│ Page D   │
  │ LSN=100  │    │ LSN=200  │    │ LSN=350  │    │ LSN=500  │
  └──────────┘    └──────────┘    └──────────┘    └──────────┘
  ↑ oldest                                        ↑ newest

  Checkpoint 时：
  - 取 Flush List 中最旧的脏页 LSN (oldest_lsn = 100)
  - 将 LSN <= 100 的脏页刷到磁盘
  
  但实际上 checkpoint 不是取 oldest_lsn，而是：
  - 后台线程持续从 Flush List 头部刷脏页
  - 刷完后更新 checkpoint_lsn = 最新刷完的 LSN
  - checkpoint_lsn <= oldest_lsn_in_flush_list
  
  如果 redo log 即将覆盖到 checkpoint_lsn 之前：
  - 紧急同步刷盘
  - 用户线程被阻塞（redo log stall）
  
  这就是为什么 innodb_log_file_size 太小会导致性能波动
```

---

## 第七部分：InnoDB 锁体系 — 7 种锁全解析

### 7.1 InnoDB 锁分类总览

```
┌──────────────────────────────────────────────────────────────────┐
│                    InnoDB 锁体系全景                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              全局锁 (Global Lock)                        │   │
│  │  FTWRL (Flush Tables With Read Lock)                    │   │
│  │  全库只读，用于备份                                      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              表级锁 (Table Lock)                         │   │
│  │  ┌─────────────────┐  ┌──────────────────┐               │   │
│  │  │ 表锁            │  │ 意向锁            │               │   │
│  │  │ LOCK TABLES     │  │ IS (意向共享)     │               │   │
│  │  │ t READ/WRITE    │  │ IX (意向排他)     │               │   │
│  │  └─────────────────┘  └──────────────────┘               │   │
│  │  ┌─────────────────┐  ┌──────────────────┐               │   │
│  │  │ AUTO-INC 锁     │  │ MDL 锁            │               │   │
│  │  │ (自增锁)        │  │ (元数据锁)        │               │   │
│  │  └─────────────────┘  └──────────────────┘               │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              行级锁 (Row Lock) — InnoDB 核心             │   │
│  │                                                          │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  Record Lock (记录锁)                               │  │   │
│  │  │  锁定索引中的一条记录                               │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  Gap Lock (间隙锁)                                 │  │   │
│  │  │  锁定索引记录之间的间隙，防止插入                   │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  Next-Key Lock (临键锁)                            │  │   │
│  │  │  = Record Lock + Gap Lock                          │  │   │
│  │  │  锁定一条记录 + 该记录前面的间隙                    │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  Insert Intention Lock (插入意向锁)                 │  │   │
│  │  │  INSERT 前设置的间隙锁特殊形式                      │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  Predicate Lock (谓词锁)                           │  │   │
│  │  │  用于空间索引（GIS），本文不展开                    │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Record Lock（记录锁）

```
Record Lock：锁定索引中的一条记录

  索引结构（假设有 id 索引，值为 10, 20, 30, 40）：
  
  ┌────┐    ┌────┐    ┌────┐    ┌────┐
  │ 10 │──→│ 20 │──→│ 30 │──→│ 40 │
  └────┘    └────┘    └────┘    └────┘
  
  SELECT * FROM t WHERE id = 20 FOR UPDATE;
  
  加锁：Record Lock on id=20
  
  ┌────┐    ┌────┐    ┌────┐    ┌────┐
  │ 10 │──→│ 20 │──→│ 30 │──→│ 40 │
  └────┘    └─🔒─┘    └────┘    └────┘
              ↑
         Record Lock (X)
  
  效果：
  - 其他事务不能修改/删除 id=20 的记录
  - 其他事务可以修改/删除 id=10, 30, 40 的记录
  - 其他事务可以插入 id=15, 25 等新记录

源码表示：
  lock_rec_t {
      page_id_t  page_id;   // 锁所在的页
      ulint      bit;       // 页内记录的 bit 位置
      lock_mode  mode;      // LOCK_S 或 LOCK_X
      // 注意：Record Lock 不带 LOCK_GAP 标志
  }
```

### 7.3 Gap Lock（间隙锁）

```
Gap Lock：锁定两个索引记录之间的间隙，防止 INSERT

  索引结构：10, 20, 30, 40
  
  SELECT * FROM t WHERE id BETWEEN 15 AND 25 FOR UPDATE;
  (RR 隔离级别)
  
  加锁：Gap Lock on (10, 20) 和 (20, 30)
  
  ┌────┐         ┌────┐         ┌────┐         ┌────┐
  │ 10 │──→  ◄间隙►  │ 20 │──→  ◄间隙►  │ 30 │──→ ... │ 40 │
  └────┘    🔒    └────┘    🔒    └────┘         └────┘
         Gap Lock       Gap Lock
         (10,20)        (20,30)
  
  效果：
  - 其他事务不能 INSERT id=11~19, id=21~29 的记录
  - 但可以修改 id=20 本身（如果只加 Gap Lock，没有 Record Lock）
  - 其他事务可以 INSERT id=5, id=35 等
  
  注意：Gap Lock 只在 RR 隔离级别下使用
        RC 隔离级别不需要 Gap Lock（因为 RC 允许幻读）
  
  Gap Lock 的特点：
  - 不锁记录本身，只锁间隙
  - Gap Lock 之间不冲突（多个事务可以同时持有同一间隙的 Gap Lock）
  - Gap Lock 只与 Insert Intention Lock 冲突
```

### 7.4 Next-Key Lock（临键锁）

```
Next-Key Lock = Record Lock + Gap Lock
锁定一条记录 + 该记录前面的间隙

  索引结构：10, 20, 30, 40
  
  SELECT * FROM t WHERE id > 15 AND id < 35 FOR UPDATE;
  (RR 隔离级别)
  
  加锁：Next-Key Lock on (10, 20], (20, 30], (30, 40)
  
  ┌────┐         ┌────┐         ┌────┐         ┌────┐
  │ 10 │──→  ◄间隙+锁►  │ 20 │──→  ◄间隙+锁►  │ 30 │──→  ◄间隙+锁►  │ 40 │
  └────┘         └────┘         └────┘         └────┘
       (10,20]       (20,30]       (30,40)
  
  Next-Key Lock 是左开右闭区间：
  - (10, 20] = 锁定 10 和 20 之间的间隙 + 锁定 20 这条记录
  - (20, 30] = 锁定 20 和 30 之间的间隙 + 锁定 30 这条记录
  - (30, 40) = 这里退化成了 Gap Lock（因为 40 不在查询范围内）
  
  效果：
  - 其他事务不能 INSERT id=11~19, 21~29, 31~39
  - 其他事务不能修改/删除 id=20, 30
  - 完全防止幻读
  
  InnoDB RR 级别默认使用 Next-Key Lock
  但在某些情况下会退化为 Record Lock 或 Gap Lock：
  - 等值查询命中唯一索引 → 退化为 Record Lock
  - 等值查询未命中 → 退化为 Gap Lock
```

### 7.5 Insert Intention Lock（插入意向锁）

```
Insert Intention Lock：INSERT 操作前设置的间隙锁特殊形式

  作用：表示"我想要在这个间隙插入数据"
  
  场景：
  
  事务 A：
  SELECT * FROM t WHERE id BETWEEN 10 AND 20 FOR UPDATE;
  -- 加 Next-Key Lock: (10, 20]
  
  事务 B：
  INSERT INTO t VALUES (15);
  -- 需要在间隙 (10, 20) 中插入
  -- 先设置 Insert Intention Lock on (10, 20)
  -- 但 A 持有 Gap Lock (10, 20]
  -- Insert Intention Lock 与 Gap Lock 冲突
  -- B 阻塞等待
  
  事务 C：
  INSERT INTO t VALUES (12);
  -- 也需要在间隙 (10, 20) 中插入
  -- 先设置 Insert Intention Lock on (10, 20)
  -- Insert Intention Lock 之间不冲突！
  -- B 和 C 可以同时等待（只要 A 释放后，B 和 C 都能插入）
  
  ┌────┐                      ┌────┐
  │ 10 │  ← 间隙 (10,20) →    │ 20 │
  └────┘                      └────┘
          ↑ Gap Lock (事务A)
          ↑ Insert Intention Lock (事务B, id=15)
          ↑ Insert Intention Lock (事务C, id=12)
          B 和 C 互相不阻塞，但都被 A 阻塞

  为什么需要 Insert Intention Lock？
  - 如果直接用 Gap Lock，多个 INSERT 会互相阻塞
  - Insert Intention Lock 让多个 INSERT 同一间隙的操作互不阻塞
  - 只阻塞与已有 Gap Lock 的冲突
```

### 7.6 意向锁（Intention Lock）

```
意向锁：表级锁，表示事务打算对表中的行加行锁

  作用：快速判断表中是否有行锁，避免逐行检查

  两种意向锁：
  - IS (Intention Shared)：打算加行级 S 锁
  - IX (Intention Exclusive)：打算加行级 X 锁

  加锁规则：
  - 加行级 S 锁前，先加表级 IS 锁
  - 加行级 X 锁前，先加表级 IX 锁

  示例：
  SELECT * FROM t WHERE id = 1 LOCK IN SHARE MODE;
  → 先加 IS 表锁，再加 S 行锁

  SELECT * FROM t WHERE id = 1 FOR UPDATE;
  → 先加 IX 表锁，再加 X 行锁

  意向锁的作用场景：
  
  事务 A：                              事务 B：
  SELECT * FROM t                       
  WHERE id=1 FOR UPDATE;                LOCK TABLES t WRITE;
  -- 加 IX 表锁 + X 行锁                -- 需要加表级 X 锁
                                        -- 检查：表上有 IX 锁
                                        -- IX 与表级 X 冲突 → 阻塞
  
  如果没有意向锁：
  事务 B 想加表锁时，需要逐行检查是否有行锁 → O(n) 效率极低
  
  有了意向锁：
  只需检查表级意向锁 → O(1) 效率高
```

### 7.7 AUTO-INC Lock（自增锁）

```
AUTO-INC Lock：用于 AUTO_INCREMENT 列的自增锁

  三种模式（innodb_autoinc_lock_mode 参数）：

  ┌──────────────────────────────────────────────────────────────┐
  │  innodb_autoinc_lock_mode = 0 (Traditional, 传统模式)       │
  │                                                              │
  │  每次 INSERT 都加表级 AUTO-INC 锁                            │
  │  语句结束后释放（不是事务结束后）                              │
  │  并发 INSERT 串行执行                                        │
  │  安全但性能差                                                │
  ├──────────────────────────────────────────────────────────────┤
  │  innodb_autoinc_lock_mode = 1 (Consecutive, MySQL 5.7默认)  │
  │                                                              │
  │  Simple INSERT（确定行数）：                                 │
  │    用轻量级互斥量（mutex）获取自增值，立即释放                │
  │    不加表锁，性能好                                          │
  │                                                              │
  │  Bulk INSERT（不确定行数，如 INSERT...SELECT）：             │
  │    加表级 AUTO-INC 锁，语句结束后释放                         │
  │    保证自增值连续                                            │
  ├──────────────────────────────────────────────────────────────┤
  │  innodb_autoinc_lock_mode = 2 (Interleaved, MySQL 8.0默认)  │
  │                                                              │
  │  所有 INSERT 都用轻量级互斥量                                │
  │  不加表级锁                                                  │
  │  并发性能最好                                                │
  │  但 Bulk INSERT 的自增值可能不连续                           │
  │  需要 binlog_format = ROW（保证主从一致）                    │
  └──────────────────────────────────────────────────────────────┘

  查看当前模式：
  SELECT @@innodb_autoinc_lock_mode;
  -- MySQL 8.0 默认 = 2
  -- MySQL 5.7 默认 = 1
```

### 7.8 锁模式（Lock Mode）

```c
// storage/innobase/include/lock0types.h

// 锁模式
enum lock_mode {
    LOCK_IS = 0,     // 意向共享锁
    LOCK_IX,         // 意向排他锁 (1)
    LOCK_S,          // 共享锁 (2)
    LOCK_X,          // 排他锁 (3)
    LOCK_AUTO_INC,   // 自增锁 (4)
    LOCK_NUM = 5,    // 锁模式总数
};

// 锁标志（与锁模式组合使用）
#define LOCK_ORDINARY   0   // Next-Key Lock（默认）
#define LOCK_GAP        512 // Gap Lock（不带记录锁）
#define LOCK_REC_NOT_GAP 1024 // Record Lock（不带间隙锁）
#define LOCK_INSERT_INTENTION 2048 // 插入意向锁
#define LOCK_PREDICATE  8192 // 谓词锁
#define LOCK_PRDT_PAGE  16384 // 谓词页锁

// 锁的组合示例：
// LOCK_X | LOCK_ORDINARY           → X 型 Next-Key Lock
// LOCK_X | LOCK_GAP                 → X 型 Gap Lock
// LOCK_X | LOCK_REC_NOT_GAP         → X 型 Record Lock
// LOCK_X | LOCK_INSERT_INTENTION    → X 型插入意向锁
```

### 7.9 锁的内存结构

```c
// storage/innobase/lock/lock0lock.h (简化)

// 一个锁对象
struct lock_t {
    trx_t*      trx;           // 持有此锁的事务
    
    // 锁类型和模式
    ulint       type_mode;     // 包含 lock_mode + 标志位
    
    union {
        lock_table_t    tab_lock;   // 表锁信息
        lock_rec_t      rec_lock;   // 行锁信息
    } un;
};

// 行锁信息
struct lock_rec_t {
    space_id_t  space;     // 表空间ID
    page_no_t   page_no;   // 页号
    ulint       n_bits;    // bitmap 位数（每条记录一个 bit）
    
    // bitmap: 记录哪些行被锁
    // bit[i] = 1 表示第 i 条记录被锁
    // 每页的记录数有限，bitmap 大小通常为 1-2 个字节到几十个字节
};

// 表锁信息
struct lock_table_t {
    dict_table_t*   table;      // 被锁的表
    ulint           locks;      // 锁数量
};
```

**锁的存储方式**：

```
  InnoDB 的行锁不是存储在记录上，而是存储在内存中的 hash table 里
  
  ┌─────────────────────────────────────────────────────────┐
  │              Lock Sys Hash Table                         │
  │                                                         │
  │  Key = (space_id, page_no)                              │
  │  Value = 锁链表（同一页上的所有锁）                       │
  │                                                         │
  │  ┌─────────────────────────────────────────────────┐   │
  │  │  Key: (space=7, page=100)                       │   │
  │  │  ┌──────┐ ┌──────┐ ┌──────┐                   │   │
  │  │  │lock_t│→│lock_t│→│lock_t│→ NULL              │   │
  │  │  │trx=1 │ │trx=2 │ │trx=3 │                   │   │
  │  │  │mode=X│ │mode=S│ │mode=X│                   │   │
  │  │  │bits: │ │bits: │ │bits: │                   │   │
  │  │  │01000 │ │00010 │ │10000 │                   │   │
  │  │  └──────┘ └──────┘ └──────┘                   │   │
  │  └─────────────────────────────────────────────────┘   │
  │  ┌─────────────────────────────────────────────────┐   │
  │  │  Key: (space=7, page=101)                       │   │
  │  │  ...                                            │   │
  │  └─────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────┘
  
  查找某条记录的锁：
  1. 计算页的 (space_id, page_no)
  2. 在 hash table 中查找
  3. 遍历锁链表，检查 bitmap 中对应 bit 是否为 1
```

---

## 第八部分：锁兼容性矩阵与加锁规则

### 8.1 行锁兼容性矩阵

```
┌──────────────────────────────────────────────────────────────────┐
│              行锁兼容性矩阵                                       │
│                                                                  │
│         │  Requested Lock                                       │
│         │  S(Rec)  X(Rec)  S(Gap)  X(Gap)  S(NextKey) X(NextKey)│
│  ───────┼─────────────────────────────────────────────────────── │
│  S(Rec) │   ✓       ✗       ✓       ✗       ✓          ✗      │
│ Held    │                                                          │
│ X(Rec)  │   ✗       ✗       ✓       ✗       ✗          ✗      │
│ Lock    │                                                          │
│ S(Gap)  │   ✓       ✓       ✓       ✓       ✓          ✓      │
│         │                                                          │
│ X(Gap)  │   ✓       ✓       ✓       ✓       ✓          ✓      │
│         │                                                          │
│S(NextK) │   ✓       ✗       ✓       ✓       ✓          ✗      │
│         │                                                          │
│X(NextK) │   ✗       ✗       ✓       ✓       ✗          ✗      │
│  ───────┴─────────────────────────────────────────────────────── │
│  ✓ = 兼容（可以同时持有）  ✗ = 冲突（需要等待）                  │
│                                                                  │
│  关键规律：                                                      │
│  1. Gap Lock 之间永远兼容（多个事务可以锁同一个间隙）             │
│  2. Record Lock 遵循 S/X 兼容规则                                │
│  3. Next-Key Lock 的兼容性 = Record 部分和 Gap 部分的交集        │
│  4. Insert Intention Lock 与 Gap Lock 冲突                      │
└──────────────────────────────────────────────────────────────────┘
```

### 8.2 表锁兼容性矩阵

```
┌──────────────────────────────────────────────────────────────────┐
│              表锁兼容性矩阵                                       │
│                                                                  │
│           │  Requested                                          │
│           │  IS    IX    S     X     AUTO_INC                   │
│  ─────────┼──────────────────────────────────────────────        │
│  IS       │  ✓     ✓    ✓     ✗         ✗                      │
│  Held  IX │  ✓     ✓    ✗     ✗         ✗                      │
│        S  │  ✓     ✗    ✓     ✗         ✗                      │
│        X  │  ✗     ✗    ✗     ✗         ✗                      │
│  AUTO_INC │  ✗     ✗    ✗     ✗         ✗                      │
│  ─────────┴────────────────────────────────────────────────────  │
│                                                                  │
│  规律：                                                          │
│  1. IS/IX 之间互相兼容（意向锁只与表锁冲突，不互相冲突）          │
│  2. IS 与 S 兼容，与 X 冲突                                      │
│  3. IX 与 S 冲突，与 X 冲突                                      │
│  4. AUTO_INC 与所有锁冲突                                       │
└──────────────────────────────────────────────────────────────────┘
```

### 8.3 加锁规则详解（RC 隔离级别）

```
RC 隔离级别的加锁规则（简单，只有 Record Lock，没有 Gap Lock）：

  规则1：等值查询唯一索引，命中 → Record Lock
  ┌─────────────────────────────────────────────────────┐
  │  SELECT * FROM t WHERE id = 10 FOR UPDATE;          │
  │  (id 是主键，存在 id=10)                             │
  │                                                     │
  │  加锁：X Record Lock on id=10                       │
  └─────────────────────────────────────────────────────┘

  规则2：等值查询唯一索引，未命中 → 无锁（RC 不防幻读）
  ┌─────────────────────────────────────────────────────┐
  │  SELECT * FROM t WHERE id = 15 FOR UPDATE;          │
  │  (id 是主键，不存在 id=15)                           │
  │                                                     │
  │  加锁：无（RC 不加 Gap Lock）                        │
  └─────────────────────────────────────────────────────┘

  规则3：范围查询 → 只对命中的记录加 Record Lock
  ┌─────────────────────────────────────────────────────┐
  │  SELECT * FROM t WHERE id > 10 AND id < 30          │
  │  FOR UPDATE;                                        │
  │  (存在 id=15, 20, 25)                               │
  │                                                     │
  │  加锁：X Record Lock on id=15, 20, 25              │
  │  不加 Gap Lock                                      │
  └─────────────────────────────────────────────────────┘

  规则4：非唯一索引 → 每条命中记录加 Record Lock
  ┌─────────────────────────────────────────────────────┐
  │  SELECT * FROM t WHERE name = 'A' FOR UPDATE;       │
  │  (name 是普通索引，存在多条 name='A')                │
  │                                                     │
  │  加锁：X Record Lock on 每条 name='A' 的记录        │
  │       （二级索引 + 聚簇索引都加锁）                   │
  └─────────────────────────────────────────────────────┘
```

### 8.4 加锁规则详解（RR 隔离级别）

```
RR 隔离级别的加锁规则（复杂，使用 Next-Key Lock）

  数据准备：
  CREATE TABLE t (id INT PRIMARY KEY, name VARCHAR(10), KEY idx_name(name));
  INSERT INTO t VALUES (10,'A'), (20,'A'), (30,'B'), (40,'C'), (50,'D');
  
  索引结构（id 主键）：
  10, 20, 30, 40, 50
  
  索引结构（idx_name 二级索引）：
  A→10, A→20, B→30, C→40, D→50

  ====== 唯一索引等值查询 ======
  
  规则1：等值命中唯一索引 → 退化为 Record Lock
  ┌─────────────────────────────────────────────────────┐
  │  SELECT * FROM t WHERE id = 20 FOR UPDATE;          │
  │                                                     │
  │  加锁：X Record Lock on id=20                      │
  │  （退化为 Record Lock，不加 Gap Lock）               │
  └─────────────────────────────────────────────────────┘
  
  规则2：等值未命中唯一索引 → 退化为 Gap Lock
  ┌─────────────────────────────────────────────────────┐
  │  SELECT * FROM t WHERE id = 25 FOR UPDATE;          │
  │  (不存在 id=25)                                     │
  │                                                     │
  │  加锁：X Gap Lock on (20, 30)                      │
  │  （退化为 Gap Lock，锁住 20 和 30 之间的间隙）       │
  │  效果：不能 INSERT id=21~29                         │
  └─────────────────────────────────────────────────────┘

  ====== 唯一索引范围查询 ======
  
  规则3：范围查询 → Next-Key Lock
  ┌─────────────────────────────────────────────────────┐
  │  SELECT * FROM t WHERE id > 10 AND id <= 30         │
  │  FOR UPDATE;                                        │
  │                                                     │
  │  加锁：                                             │
  │  (10, 20] Next-Key Lock  (id=20 及前间隙)           │
  │  (20, 30] Next-Key Lock  (id=30 及前间隙)           │
  │                                                     │
  │  效果：不能 INSERT id=11~30, 不能修改 id=20,30     │
  └─────────────────────────────────────────────────────┘
  
  规则4：范围查询（> 不含 =）→ Next-Key Lock + Gap
  ┌─────────────────────────────────────────────────────┐
  │  SELECT * FROM t WHERE id > 10 AND id < 30          │
  │  FOR UPDATE;                                        │
  │                                                     │
  │  加锁：                                             │
  │  (10, 20] Next-Key Lock                             │
  │  (20, 30) Gap Lock   (因为 < 30 不含 30，退化为Gap) │
  │                                                     │
  │  效果：不能 INSERT id=11~29                         │
  │        可以修改 id=30（没有被锁）                    │
  └─────────────────────────────────────────────────────┘
  
  规则5：>= 范围查询
  ┌─────────────────────────────────────────────────────┐
  │  SELECT * FROM t WHERE id >= 20 FOR UPDATE;         │
  │                                                     │
  │  加锁：                                             │
  │  (10, 20] Next-Key Lock  (因为 >= 20，先定位到20)   │
  │  (20, 30] Next-Key Lock                             │
  │  (30, 40] Next-Key Lock                             │
  │  (40, 50] Next-Key Lock                             │
  │  (50, +∞) Next-Key Lock  (supremum 伪记录)          │
  │                                                     │
  │  效果：不能 INSERT/修改 id=11~+∞                    │
  └─────────────────────────────────────────────────────┘

  ====== 非唯一索引等值查询 ======
  
  规则6：等值命中非唯一索引 → Next-Key Lock + Gap Lock (下一个)
  ┌─────────────────────────────────────────────────────┐
  │  SELECT * FROM t WHERE name = 'A' FOR UPDATE;       │
  │  (name='A' 有两条：A→10, A→20)                     │
  │                                                     │
  │  二级索引加锁：                                     │
  │  (-∞, A→10] Next-Key Lock                          │
  │  (A→10, A→20] Next-Key Lock                        │
  │  (A→20, B→30] Next-Key Lock  ← 多锁一个间隙！       │
  │                                                     │
  │  聚簇索引加锁：                                     │
  │  X Record Lock on id=10                            │
  │  X Record Lock on id=20                            │
  │                                                     │
  │  效果：不能 INSERT name='A' 的任何新记录             │
  │        不能修改/删除 name='A' 或 name='B' 的记录     │
  │  为什么多锁一个 (A→20, B→30]?                       │
  │  因为 name 是非唯一索引，可能有多个 'A'              │
  │  需要扫描到第一个不等于 'A' 的记录才能确认范围       │
  └─────────────────────────────────────────────────────┘

  ====== 非唯一索引范围查询 ======
  
  规则7：非唯一索引范围查询 → 全部 Next-Key Lock
  ┌─────────────────────────────────────────────────────┐
  │  SELECT * FROM t WHERE name >= 'B' FOR UPDATE;      │
  │                                                     │
  │  加锁：                                             │
  │  (A→20, B→30] Next-Key Lock                        │
  │  (B→30, C→40] Next-Key Lock                        │
  │  (C→40, D→50] Next-Key Lock                        │
  │  (D→50, +∞) Next-Key Lock                          │
  │                                                     │
  │  效果：不能 INSERT name >= 'A'(第二个之后)          │
  └─────────────────────────────────────────────────────┘
```

### 8.5 加锁规则速查表

```
┌──────────────────────────────────────────────────────────────────┐
│              RR 隔离级别加锁规则速查表                            │
├───────────┬──────────┬──────────┬───────────────────────────────┤
│  索引类型  │ 查询类型  │ 是否命中  │ 加锁类型                      │
├───────────┼──────────┼──────────┼───────────────────────────────┤
│  唯一索引  │  等值    │   命中    │ Record Lock                   │
│  唯一索引  │  等值    │  未命中   │ Gap Lock (前后记录间隙)        │
│  唯一索引  │  范围    │    -     │ Next-Key Lock (命中区间)      │
│           │          │          │ + 边界处理                     │
├───────────┼──────────┼──────────┼───────────────────────────────┤
│  非唯一索引│  等值    │   命中    │ Next-Key Lock + 下一个间隙    │
│  非唯一索引│  等值    │  未命中   │ Gap Lock (前后记录间隙)        │
│  非唯一索引│  范围    │    -     │ Next-Key Lock (所有命中区间)  │
├───────────┼──────────┼──────────┼───────────────────────────────┤
│  无索引   │   任意   │    -     │ 全表所有行加 Next-Key Lock    │
│           │          │          │ = 表锁效果（但不是真正的表锁） │
│           │          │          │ ⚠️ 极度危险！                  │
└───────────┴──────────┴──────────┴───────────────────────────────┘

  边界处理细节：
  - > value  → 不锁 value 本身，锁 value 之后的间隙
  - >= value → 锁 value 及之后
  - < value  → 锁到 value 之前（不锁 value）
  - <= value → 锁到 value（含 value）
  
  特殊情况：
  - LIMIT 子句不影响加锁范围（锁住扫描过的所有记录）
  - ORDER BY 不影响加锁范围
  - 聚簇索引和二级索引都会加锁
```

### 8.6 加锁源码分析

```c
// storage/innobase/lock/lock0prdt.cc & lock0lock.cc (简化)

// 行锁加锁入口
dberr_t lock_rec_lock(
    bool        impl,       // 是否隐式锁
    ulint       mode,       // 锁模式 LOCK_S / LOCK_X
    const buf_block_t* block,  // 记录所在页
    const rec_t*    rec,       // 记录
    dict_index_t*   index,    // 索引
    que_thr_t*      thr)      // 查询线程
{
    trx_t* trx = thr_get_trx(thr);
    
    // 1. 检查是否已有兼容的锁
    if (lock_rec_has_expl(mode, block, rec, trx)) {
        // 已经持有更强的锁，不需要再加
        return DB_SUCCESS;
    }
    
    // 2. 检查是否有冲突的锁
    lock_t* wait_for = lock_rec_other_has_conflicting(
        mode, block, rec, trx);
    
    if (wait_for == NULL) {
        // 3a. 无冲突，直接加锁
        lock_rec_add_to_queue(LOCK_REC|mode, block, rec, index, trx);
        return DB_SUCCESS;
    } else {
        // 3b. 有冲突，加入等待队列
        // 创建锁对象，状态为 WAITING
        lock_t* lock = lock_rec_create(
            mode | LOCK_WAIT, block, rec, index, trx);
        
        // 设置等待关系
        trx->lock.wait_lock = lock;
        lock->un_member.rec_lock.wait_for = wait_for;
        
        // 加入死锁检测图
        lock_deadlock_check(trx);
        
        // 挂起当前线程
        return DB_LOCK_WAIT;
    }
}

// 判断锁冲突
lock_t* lock_rec_other_has_conflicting(
    ulint           mode,       // 请求的锁模式
    const buf_block_t* block,
    const rec_t*    rec,
    const trx_t*    trx)        // 当前事务（排除自己）
{
    // 遍历该页上所有锁
    lock_t* lock = lock_rec_get_first_on_page(block);
    
    while (lock) {
        if (lock->trx != trx  // 不是自己的锁
            && lock_rec_get_nth_bit(lock, page_rec_get_heap_no(rec))
            // 锁定了同一条记录
            && lock_mode_compatible(
                lock_get_mode(lock), 
                mode) == false) {
            // 锁模式不兼容 → 冲突
            return lock;
        }
        lock = lock_rec_get_next_on_page(lock);
    }
    
    return NULL;  // 无冲突
}
```

---

## 第九部分：死锁检测与处理

### 9.1 死锁的产生条件

```
死锁四个必要条件（操作系统经典）：

  1. 互斥：锁是互斥的，同一时刻只能一个事务持有
  2. 持有并等待：事务持有已获得的锁，同时等待新锁
  3. 不可剥夺：锁不能被强制剥夺，只能等事务主动释放
  4. 循环等待：事务之间形成等待环

  InnoDB 死锁示例：

  事务 A                           事务 B
  BEGIN;                            BEGIN;
  UPDATE t SET v=1 WHERE id=1;     
  -- 加 X Lock on id=1             
  
                                    UPDATE t SET v=2 WHERE id=2;
                                    -- 加 X Lock on id=2
  
  UPDATE t SET v=3 WHERE id=2;     
  -- 等待 X Lock on id=2           
  -- (被 B 持有)                    
  
                                    UPDATE t SET v=4 WHERE id=1;
                                    -- 等待 X Lock on id=1
                                    -- (被 A 持有)
  
  ┌──────────────────────────────────────────────┐
  │              死锁！                           │
  │  A 持有 id=1，等待 id=2                      │
  │  B 持有 id=2，等待 id=1                      │
  │  循环等待：A → B → A                         │
  └──────────────────────────────────────────────┘
```

### 9.2 InnoDB 死锁检测 — Wait-for Graph

```
InnoDB 使用 Wait-for Graph（等待图）进行死锁检测

  构建方式：
  - 每个事务是一个节点
  - 如果事务 A 等待事务 B 持有的锁，画一条 A→B 的边
  - 如果图中存在环 → 死锁

  示例：

  事务 A (持有 id=1, 等待 id=2)
  事务 B (持有 id=2, 等待 id=1)
  事务 C (持有 id=3, 等待 id=4)
  事务 D (持有 id=4, 等待 id=3)

  Wait-for Graph：
  
  ┌───┐         ┌───┐
  │ A │────────→│ B │
  │   │←────────│   │    ← 环！A→B→A，死锁
  └───┘         └───┘
  
  ┌───┐         ┌───┐
  │ C │────────→│ D │
  │   │←────────│   │    ← 环！C→D→C，死锁
  └───┘         └───┘

  死锁检测触发时机：
  - 每次事务请求锁被阻塞时，触发死锁检测
  - 从当前事务出发，深度优先搜索 Wait-for Graph
  - 如果回到起点 → 发现环 → 死锁
  
  死锁解决：
  - InnoDB 选择回滚"代价最小"的事务（undo log 量最少的）
  - 被回滚的事务收到错误：ERROR 1213 (40001): Deadlock found
  - 另一个事务继续执行
```

### 9.3 死锁检测源码

```c
// storage/innobase/lock/lock0deadlock.cc (简化)

// 死锁检测主函数
lock_t* lock_deadlock_check_and_resolve(
    trx_t*      trx,        // 被阻塞的事务
    lock_t*     wait_lock)  // 等待的锁
{
    // DFS 搜索是否有环
    lock_t* mark = lock_deadlock_check(trx, wait_lock);
    
    if (mark != NULL) {
        // 发现死锁！
        // 选择 victim（回滚代价最小的事务）
        trx_t* victim = lock_deadlock_select_victim(trx);
        
        // 回滚 victim 事务
        lock_deadlock_victim_notify(victim, trx);
        
        // 中断 victim 的锁等待
        lock_cancel_waiting_and_release(victim);
        
        return victim == trx ? wait_lock : NULL;
    }
    
    return NULL;  // 无死锁
}

// DFS 检测环
lock_t* lock_deadlock_check(
    trx_t*      start,      // 起点
    lock_t*     wait_lock)  // 等待的锁
{
    // 获取阻塞当前锁的所有事务
    trx_t* blocker = lock_get_trx(wait_lock);
    
    // 递归检查 blocker 是否在等待 start
    if (blocker == start) {
        // 回到起点 → 发现环 → 死锁！
        return wait_lock;
    }
    
    // 检查 blocker 是否也在等待
    if (blocker->lock.wait_lock != NULL) {
        // 递归
        return lock_deadlock_check(start, blocker->lock.wait_lock);
    }
    
    return NULL;  // 无环
}

// 选择回滚 victim
trx_t* lock_deadlock_select_victim(trx_t* trx) {
    // 回滚代价 = Undo Log 的大小
    // 选择 Undo Log 最小（修改最少）的事务作为 victim
    // 因为回滚代价最小
    
    ulint min_weight = ULONG_MAX;
    trx_t* victim = trx;
    
    // 遍历死锁环中的所有事务
    for (auto t : deadlock_trx_list) {
        ulint weight = trx_undo_weight(t);
        if (weight < min_weight) {
            min_weight = weight;
            victim = t;
        }
    }
    
    return victim;
}
```

### 9.4 死锁场景分析

```
场景1：互相更新对方的行（最常见）

  事务 A                           事务 B
  UPDATE t SET v=1 WHERE id=1;     UPDATE t SET v=2 WHERE id=2;
  UPDATE t SET v=1 WHERE id=2;     UPDATE t SET v=2 WHERE id=1;
  → 死锁

  解决方案：所有事务按相同顺序加锁
  UPDATE t SET v=1 WHERE id=1;     UPDATE t SET v=2 WHERE id=1;  -- 先操作 id=1
  UPDATE t SET v=1 WHERE id=2;     UPDATE t SET v=2 WHERE id=2;  -- 再操作 id=2


场景2：Gap Lock 导致的死锁（RR 级别特有）

  数据：id=10, 20, 30
  
  事务 A                           事务 B
  BEGIN;                            BEGIN;
  SELECT * FROM t WHERE id=15      
  FOR UPDATE;                       
  -- Gap Lock (10,20)              -- A 持有 Gap Lock (10,20)
  
                                    SELECT * FROM t WHERE id=12
                                    FOR UPDATE;
                                    -- Gap Lock (10,20)
                                    -- A 和 B 都持有 Gap Lock (10,20)
                                    -- Gap Lock 之间兼容，不阻塞
  
  INSERT INTO t VALUES (15);        
  -- 需要 Insert Intention Lock (10,20)
  -- 被 B 的 Gap Lock 阻塞
  -- A 等待 B
  
                                    INSERT INTO t VALUES (12);
                                    -- 需要 Insert Intention Lock (10,20)
                                    -- 被 A 的 Gap Lock 阻塞
                                    -- B 等待 A
  
  → 死锁！A 等 B 的 Gap Lock, B 等 A 的 Gap Lock
  
  解决方案：
  1. 降低隔离级别到 RC（无 Gap Lock）
  2. 先 INSERT 再 SELECT（INSERT 不会产生 Gap Lock 等待）
  3. 使用 INSERT ... ON DUPLICATE KEY UPDATE


场景3：唯一键冲突导致的死锁

  数据：无 id=10 的记录
  
  事务 A                           事务 B                           事务 C
  INSERT INTO t VALUES(10);        INSERT INTO t VALUES(10);        INSERT INTO t VALUES(10);
  -- 检查唯一键，加 S Lock          -- 检查唯一键，加 S Lock          -- 检查唯一键，加 S Lock
  -- 无冲突，S Lock 兼容            -- 无冲突，S Lock 兼容            -- 
  -- 准备加 X Lock 插入             -- 准备加 X Lock 插入             -- 
  -- X Lock 等待 B 的 S Lock       -- X Lock 等待 A 的 S Lock       -- 
  → A 等 B, B 等 A → 死锁
  
  InnoDB 检测到死锁后，回滚其中一个事务
  另一个事务成功 INSERT
  第三个事务继续...
```

### 9.5 锁等待超时

```sql
-- 锁等待超时参数
SELECT @@innodb_lock_wait_timeout;
-- 默认 50 秒

-- 如果一个事务等待锁超过此时间：
-- ERROR 1205 (HY000): Lock wait timeout exceeded;
-- try restarting transaction

-- 死锁检测参数
SELECT @@innodb_deadlock_detect;
-- 默认 ON

-- 在高并发场景下，死锁检测本身可能成为性能瓶颈
-- 可以关闭死锁检测，依赖锁等待超时
SET GLOBAL innodb_deadlock_detect = OFF;
-- ⚠️ 关闭后死锁只能靠 innodb_lock_wait_timeout 解决
```

---

## 第十部分：RC vs RR — 锁与 MVCC 的差异

### 10.1 RC 与 RR 的全面对比

```
┌──────────────────────────────────────────────────────────────────┐
│              RC vs RR 全面对比                                    │
├──────────────────┬────────────────────┬─────────────────────────┤
│     维度          │ RC (读已提交)       │ RR (可重复读，默认)      │
├──────────────────┼────────────────────┼─────────────────────────┤
│ 脏读             │ 不可能              │ 不可能                   │
│ 不可重复读       │ 可能                │ 不可能                   │
│ 幻读             │ 可能                │ 不可能                   │
├──────────────────┼────────────────────┼─────────────────────────┤
│ MVCC ReadView    │ 每次 SELECT 创建   │ 首次 SELECT 创建         │
│                  │ 新的 ReadView       │ 事务内复用               │
├──────────────────┼────────────────────┼─────────────────────────┤
│ 快照读           │ 读最新已提交版本    │ 读事务首次SELECT时的快照 │
│                  │ 可能读到新数据      │ 数据不变                 │
├──────────────────┼────────────────────┼─────────────────────────┤
│ 当前读加锁       │ Record Lock only   │ Next-Key Lock            │
│                  │ (无 Gap Lock)      │ (Record + Gap)           │
├──────────────────┼────────────────────┼─────────────────────────┤
│ INSERT 阻塞      │ 不会被 Gap Lock    │ 可能被 Gap Lock 阻塞     │
│                  │ 阻塞（无Gap Lock）  │                          │
├──────────────────┼────────────────────┼─────────────────────────┤
│ 死锁概率         │ 较低（锁少）        │ 较高（Gap Lock 多）      │
├──────────────────┼────────────────────┼─────────────────────────┤
│ 并发性能         │ 较高（锁少）        │ 较低（锁多）             │
├──────────────────┼────────────────────┼─────────────────────────┤
│ 半一致性读       │ 支持（UPDATE 时    │ 不支持                   │
│ (Semi-Consistent │ 退化为最新已提交值  │                          │
│  Read)           │  判断是否需要加锁）  │                          │
├──────────────────┼────────────────────┼─────────────────────────┤
│ Binlog 格式      │ 必须用 ROW 格式     │ ROW / STATEMENT 均可     │
│                  │ (STATEMENT 不安全)  │                          │
├──────────────────┼────────────────────┼─────────────────────────┤
│ 适用场景         │ 高并发互联网应用    │ 对一致性要求高的场景      │
│                  │ （大多互联网公司    │ （金融、账务）            │
│                  │  使用 RC）          │                          │
└──────────────────┴────────────────────┴─────────────────────────┘
```

### 10.2 半一致性读（Semi-Consistent Read）

```
RC 级别特有的一种优化：UPDATE 时的"半一致性读"

  场景：
  UPDATE t SET v = v + 1 WHERE id = 1;
  
  如果 id=1 正在被其他事务 X 锁锁定：
  
  RR 级别：
  - 直接等待，直到持有锁的事务提交或回滚
  - 等待期间不做任何判断
  
  RC 级别（Semi-Consistent Read）：
  - 先读取该行的最新已提交版本（不是 MVCC 快照）
  - 判断该版本是否满足 WHERE 条件
  - 如果不满足 → 跳过该行（不需要加锁，直接返回）
  - 如果满足 → 再尝试加 X 锁（可能等待）
  
  优势：
  - 减少不必要的锁等待
  - 如果 WHERE 条件不满足，根本不需要加锁
  
  源码：
  // storage/innobase/row/row0upd.cc
  
  if (trx->isolation_level == TRX_ISO_READ_COMMITTED
      && !row_upd_changes_disowned_external(field)) {
      // RC 级别：先读最新已提交版本判断
      if (!row_sel_match_rec_to_where(rec, index, ...)) {
          // WHERE 条件不满足，跳过
          continue;
      }
      // 条件满足，尝试加锁
  }
```

### 10.3 为什么 RC 不需要 Gap Lock

```
根本原因：RC 的 ReadView 每次都新建

  RR 级别：
  - ReadView 在事务首次 SELECT 时创建，之后复用
  - 如果其他事务插入了新行并提交，RR 读不到（ReadView 没更新）
  - 但"当前读"（FOR UPDATE）需要防幻读 → 需要 Gap Lock
  
  RC 级别：
  - ReadView 每次 SELECT 都新建
  - 如果其他事务插入了新行并提交，RC 能读到（新 ReadView）
  - 幻读是允许的 → 不需要 Gap Lock
  
  结论：
  - Gap Lock 的目的是防止幻读
  - RC 允许幻读 → 不需要 Gap Lock → 锁更少 → 并发更高 → 死锁更少
  - 这也是为什么很多互联网公司选择 RC 隔离级别
```

### 10.4 RC 隔离级别必须用 Row 格式 Binlog 的原因

```
RC + STATEMENT 格式的 Binlog 会导致主从不一致：

  主库（RC 级别）：
  事务 A: BEGIN; UPDATE t SET v=1 WHERE v=0; -- 假设匹配 3 行
  事务 B: BEGIN; INSERT INTO t VALUES(0); COMMIT;
  事务 A: COMMIT;
  
  事务 A 执行时，只看到 3 行 v=0 的记录（B 还没提交）
  
  从库（重放 Binlog）：
  - STATEMENT 格式记录的是 SQL 语句
  - 从库重放顺序：先执行 B 的 INSERT，再执行 A 的 UPDATE
  - A 的 UPDATE 在从库匹配 4 行（多了一行 B 插入的）
  - 主从数据不一致！
  
  RC + ROW 格式：
  - ROW 格式记录的是行变更（具体哪几行被修改）
  - 从库直接应用行变更，不受隔离级别影响
  - 主从一致
  
  所以：
  RC 隔离级别 + binlog_format=STATEMENT → 不安全
  RC 隔离级别 + binlog_format=ROW → 安全（MySQL 8.0 默认 ROW）
  
  RR 隔离级别 + binlog_format=STATEMENT → 安全（因为 RR 防幻读）
```

---

## 第十一部分：两阶段提交（2PC）— Redo Log 与 Binlog 的一致性

### 11.1 为什么需要两阶段提交

```
问题：Redo Log 和 Binlog 是两个独立的日志系统

  如果不用两阶段提交：
  
  场景1：先写 Redo Log，再写 Binlog
  - 写完 Redo Log 后崩溃
  - 恢复后 Redo Log 重放 → 主库有这条数据
  - Binlog 没写 → 从库没有这条数据
  - 主从不一致
  
  场景2：先写 Binlog，再写 Redo Log
  - 写完 Binlog 后崩溃
  - 恢复后 Redo Log 没有这条记录 → 主库没有这条数据
  - Binlog 有 → 从库有这条数据
  - 主从不一致
  
  解决方案：两阶段提交
  
  Phase 1 (Prepare)：写 Redo Log（标记为 PREPARE 状态）
  Phase 2 (Commit)：写 Binlog + 写 Redo Log（标记为 COMMIT 状态）
  
  崩溃恢复时：
  - 如果 Redo Log 有 PREPARE 但没有 COMMIT：
    - 检查 Binlog 是否有对应的 XID
    - 有 → 提交（Binlog 已写入，从库会执行）
    - 没有 → 回滚（Binlog 未写入，从库不会执行）
  - 保证主从一致
```

### 11.2 两阶段提交流程

```
                    两阶段提交详细流程

  ┌──────────────────────────────────────────────────────────────┐
  │                                                              │
  │  事务执行阶段：                                               │
  │  ┌──────────────────────────────────────────────────┐        │
  │  │  1. 修改 Buffer Pool 中的数据页                   │        │
  │  │  2. 写 Undo Log                                  │        │
  │  │  3. 写 Redo Log Buffer（但还没刷盘）              │        │
  │  └──────────────────────────────────────────────────┘        │
  │                         │                                    │
  │                    COMMIT 触发                                │
  │                         │                                    │
  │  ┌──────────────────────▼───────────────────────────┐        │
  │  │  Phase 1: Prepare（准备阶段）                     │        │
  │  │                                                   │        │
  │  │  1. 事务状态 → PREPARED                           │        │
  │  │  2. 将 Redo Log 刷到磁盘                          │        │
  │  │     （包含事务的 PREPARE 标记）                    │        │
  │  │  3. 记录 prepare_lsn                              │        │
  │  └──────────────────────┬───────────────────────────┘        │
  │                         │                                    │
  │  ┌──────────────────────▼───────────────────────────┐        │
  │  │  Phase 2: Commit（提交阶段）                      │        │
  │  │                                                   │        │
  │  │  1. 写 Binlog 到 Binlog 文件                      │        │
  │  │     （包含事务的 XID）                             │        │
  │  │  2. 将 Redo Log 的 COMMIT 标记刷到磁盘             │        │
  │  │  3. 事务状态 → COMMITTED                          │        │
  │  │  4. 释放锁                                        │        │
  │  │  5. Undo Log 保留（等 Purge 清理）                │        │
  │  └──────────────────────────────────────────────────┘        │
  │                                                              │
  └──────────────────────────────────────────────────────────────┘
```

### 11.3 两阶段提交的崩溃恢复

```
崩溃恢复逻辑：

  ┌──────────────────────────────────────────────────────────────┐
  │  扫描 Redo Log，找到所有 PREPARE 状态的事务                  │
  │                                                              │
  │  对每个 PREPARED 事务：                                       │
  │  ┌─────────────────────────────────────────────────┐        │
  │  │  1. 读取该事务的 prepare_lsn                     │        │
  │  │  2. 在 Binlog 中查找 XID 对应的位置               │        │
  │  │     （通过 XID 与 prepare_lsn 关联）              │        │
  │  └──────────────────────┬──────────────────────────┘        │
  │                         │                                    │
  │              ┌──────────┼──────────┐                         │
  │              │                     │                         │
  │              ▼                     ▼                         │
  │     ┌──────────────┐      ┌──────────────┐                  │
  │     │ Binlog 有    │      │ Binlog 没有  │                  │
  │     │ 该 XID       │      │ 该 XID       │                  │
  │     └──────┬───────┘      └──────┬───────┘                  │
  │            │                     │                          │
  │            ▼                     ▼                          │
  │     ┌──────────────┐      ┌──────────────┐                  │
  │     │ 提交事务      │      │ 回滚事务      │                  │
  │     │ (COMMIT)     │      │ (ROLLBACK)   │                  │
  │     │              │      │              │                  │
  │     │ 重放 Redo    │      │ 执行 Undo    │                  │
  │     │ Log          │      │ Log 回滚     │                  │
  │     └──────────────┘      └──────────────┘                  │
  │                                                              │
  │  结果：主从一致                                              │
  │  - 提交的事务：Binlog 有记录 → 从库也会执行                  │
  │  - 回滚的事务：Binlog 无记录 → 从库不会执行                  │
  └──────────────────────────────────────────────────────────────┘
```

### 11.4 组提交（Group Commit）与两阶段

```
MySQL 5.7+ 对两阶段提交的优化：将多个事务的两阶段合并

  传统两阶段（串行）：
  事务A: Prepare → Commit
  事务B:          Prepare → Commit
  事务C:                   Prepare → Commit
  → 3 次刷盘

  组提交（并行）：
  事务A ─┐
  事务B ─┤── Flush → Sync → Commit
  事务C ─┘
  → 1 次刷盘

  三个阶段：
  
  1. Flush Stage：
     - 多个事务的 Redo Log 写入 Redo Log Buffer
     - Leader 事务负责 flush
  
  2. Sync Stage：
     - Leader 将 Redo Log 刷到磁盘
     - Followers 等待
     - 同时等待更多事务加入（延迟组提交）
  
  3. Commit Stage：
     - Leader 写 Binlog + Redo Log Commit 标记
     - Followers 依次写各自的 Binlog Commit
  
  相关参数：
  binlog_group_commit_sync_delay = 0    (默认，微秒级等待)
  binlog_group_commit_sync_no_delay_count = 0  (达到此数量立即 sync)
  
  通过设置延迟，让更多事务加入组提交，提高性能
  但会增加单个事务的延迟
```

---

## 第十二部分：分布式事务 — XA 与 MySQL XA

### 12.1 XA 协议

```
XA（eXtended Architecture）是 X/Open 组织定义的分布式事务标准

  XA 定义了三个角色：
  - AP (Application Program)：应用程序
  - TM (Transaction Manager)：事务管理器（协调者）
  - RM (Resource Manager)：资源管理器（数据库）

  XA 两阶段提交：

  Phase 1: Prepare
  ┌────────┐    Prepare     ┌────────┐
  │   TM   │──────────────→│ RM 1   │
  │        │──────────────→│ RM 2   │
  │        │                │ RM 3   │
  └────────┘                └────────┘
  等待所有 RM 回复 Ready / Abort

  Phase 2: Commit / Rollback
  ┌────────┐    Commit      ┌────────┐
  │   TM   │──────────────→│ RM 1   │
  │        │──────────────→│ RM 2   │
  │        │──────────────→│ RM 3   │
  └────────┘                └────────┘
  如果所有 RM 都 Ready → Commit
  如果任一 RM Abort → Rollback
```

### 12.2 MySQL XA 语法

```sql
-- MySQL 内部 XA（单库多引擎，或模拟分布式事务）

-- 开启 XA 事务
XA START 'xid_1';

-- 执行 SQL
UPDATE account SET balance = balance - 100 WHERE id = 1;
UPDATE account SET balance = balance + 100 WHERE id = 2;

-- Phase 1: Prepare
XA END 'xid_1';
XA PREPARE 'xid_1';
-- 此时 Redo Log 写入 PREPARE 状态

-- Phase 2: Commit 或 Rollback
XA COMMIT 'xid_1';
-- 或
XA ROLLBACK 'xid_1';

-- 查看 PREPARE 状态的 XA 事务
XA RECOVER;
-- 返回所有处于 PREPARED 状态的事务

-- 崩溃后恢复：
-- MySQL 重启后，PREPARED 状态的事务仍然存在
-- 需要手动 XA COMMIT 或 XA ROLLBACK
```

### 12.3 跨库 XA 事务示例

```java
// 使用 Atomikos 等 TM 实现跨库 XA 事务

// 数据源1：MySQL order_db
DataSource orderDS = ...;  
// 数据源2：MySQL stock_db
DataSource stockDS = ...;

// 创建 XA 数据源
XADataSource xaOrderDS = createXADataSource(orderDS);
XADataSource xaStockDS = createXADataSource(stockDS);

// TM 协调
UserTransaction ut = com.atomikos.icatch.jta.UserTransactionImp();
ut.begin();

try {
    // 在 order_db 执行
    Connection orderConn = xaOrderDS.getXAConnection().getConnection();
    orderConn.executeUpdate(
        "INSERT INTO orders VALUES(1, 'product_A', 2)");
    
    // 在 stock_db 执行
    Connection stockConn = xaStockDS.getXAConnection().getConnection();
    stockConn.executeUpdate(
        "UPDATE stock SET count = count - 2 WHERE product='product_A'");
    
    ut.commit();  // TM 协调两阶段提交
} catch (Exception e) {
    ut.rollback();  // 两个库都回滚
}
```

### 12.4 XA 的问题与替代方案

```
XA 的问题：
  1. 性能差：两阶段提交，所有 RM 阻塞等待
  2. 协调者单点：TM 挂了，RM 处于 PREPARED 状态无法释放
  3. 数据不一致：Phase 2 部分成功部分失败
  4. 不适合微服务：跨服务 XA 几乎不可行

替代方案：

  ┌──────────────────────────────────────────────────────────┐
  │  1. TCC (Try-Confirm-Cancel)                             │
  │  - Try: 预留资源                                         │
  │  - Confirm: 确认操作                                     │
  │  - Cancel: 取消预留                                      │
  │  - 业务层面实现，性能好但侵入性强                          │
  ├──────────────────────────────────────────────────────────┤
  │  2. Saga                                                  │
  │  - 将长事务拆分为多个短事务                                │
  │  - 每个短事务有对应的补偿操作                              │
  │  - 失败时执行补偿，最终一致                                │
  ├──────────────────────────────────────────────────────────┤
  │  3. 本地消息表                                            │
  │  - 主库写业务数据 + 消息表（同一事务）                     │
  │  - 消息服务轮询消息表，发送到 MQ                          │
  │  - 消费者消费消息，操作其他库                              │
  │  - 最终一致                                              │
  ├──────────────────────────────────────────────────────────┤
  │  4. Seata AT 模式                                        │
  │  - 自动生成 undo log                                     │
  │  - 一阶段：执行 SQL + 记录 undo log（本地事务）           │
  │  - 二阶段提交：删除 undo log                             │
  │  - 二阶段回滚：用 undo log 反向补偿                       │
  └──────────────────────────────────────────────────────────┘
```

---

## 第十三部分：实战 — 锁等待分析与死锁排查

### 13.1 查看锁信息

```sql
-- MySQL 8.0 查看当前锁情况

-- 1. 查看正在运行的事务
SELECT * FROM information_schema.innodb_trx\G

-- 关键字段：
-- trx_id: 事务ID
-- trx_state: LOCK WAIT / RUNNING
-- trx_started: 事务开始时间
-- trx_requested_lock_id: 正在等待的锁ID
-- trx_wait_started: 开始等待的时间
-- trx_weight: 事务权重（锁数 + undo行数）
-- trx_rows_locked: 锁定的行数
-- trx_rows_modified: 修改的行数
-- trx_query: 正在执行的SQL

-- 2. 查看锁等待关系
SELECT * FROM performance_schema.data_lock_waits\G

-- 关键字段：
-- ENGINE: 引擎
-- REQUESTING_ENGINE_TRANSACTION_ID: 等待锁的事务ID
-- REQUESTING_ENGINE_LOCK_ID: 请求的锁ID
-- BLOCKING_ENGINE_TRANSACTION_ID: 持有锁的事务ID
-- BLOCKING_ENGINE_LOCK_ID: 阻塞的锁ID

-- 3. 查看所有锁
SELECT * FROM performance_schema.data_locks\G

-- 关键字段：
-- ENGINE_LOCK_ID: 锁ID
-- ENGINE_TRANSACTION_ID: 事务ID
-- THREAD_ID: 线程ID
-- OBJECT_SCHEMA: 数据库名
-- OBJECT_NAME: 表名
-- INDEX_NAME: 索引名
-- LOCK_TYPE: RECORD / TABLE
-- LOCK_MODE: S/X/IS/IX/GAP/...
-- LOCK_DATA: 锁定的数据（记录值）
-- LOCK_STATUS: GRANTED / PENDING

-- 4. 查看锁等待链（哪个事务阻塞了哪个）
SELECT
    r.trx_id AS waiting_trx_id,
    r.trx_mysql_thread_id AS waiting_thread,
    r.trx_query AS waiting_query,
    b.trx_id AS blocking_trx_id,
    b.trx_mysql_thread_id AS blocking_thread,
    b.trx_query AS blocking_query,
    TIMEDIFF(NOW(), r.trx_wait_started) AS wait_time
FROM information_schema.innodb_trx r
JOIN information_schema.innodb_trx b
    ON r.trx_requested_lock_id IN (
        SELECT lock_id 
        FROM information_schema.innodb_locks
        WHERE lock_table = b.trx_table_in_use
    )
WHERE r.trx_state = 'LOCK WAIT';
```

### 13.2 排查锁等待

```sql
-- 步骤1：发现锁等待
SELECT * FROM information_schema.innodb_trx 
WHERE trx_state = 'LOCK WAIT';

-- 步骤2：找到等待的事务和阻塞的事务
SELECT
    waiting.trx_id AS waiting_trx_id,
    waiting.trx_mysql_thread_id AS waiting_thread_id,
    waiting.trx_query AS waiting_query,
    blocking.trx_id AS blocking_trx_id,
    blocking.trx_mysql_thread_id AS blocking_thread_id,
    blocking.trx_query AS blocking_query,
    blocking.trx_started AS blocking_started,
    TIMESTAMPDIFF(SECOND, blocking.trx_started, NOW()) AS blocking_duration_sec
FROM information_schema.innodb_trx waiting
JOIN performance_schema.data_lock_waits dlw
    ON waiting.trx_id = dlw.REQUESTING_ENGINE_TRANSACTION_ID
JOIN information_schema.innodb_trx blocking
    ON dlw.BLOCKING_ENGINE_TRANSACTION_ID = blocking.trx_id;

-- 步骤3：查看阻塞事务的详细信息
SELECT * FROM information_schema.innodb_trx 
WHERE trx_id = <blocking_trx_id>\G

-- 步骤4：如果需要，杀掉阻塞的事务
KILL <blocking_thread_id>;

-- 步骤5：查看锁的具体信息
SELECT 
    OBJECT_SCHEMA, OBJECT_NAME, INDEX_NAME,
    LOCK_TYPE, LOCK_MODE, LOCK_STATUS, LOCK_DATA
FROM performance_schema.data_locks
WHERE ENGINE_TRANSACTION_ID = <blocking_trx_id>;
```

### 13.3 排查死锁

```sql
-- 查看最后一次死锁信息
SHOW ENGINE INNODB STATUS\G

-- 在输出中找 "LATEST DETECTED DEADLOCK" 部分：
/*
========================
LATEST DETECTED DEADLOCK
========================
2024-06-30 10:15:00 0x7f8b2c0b7700
*** (1) TRANSACTION:
TRANSACTION 12345, ACTIVE 5 sec starting index read
mysql tables in use 1, locked 1
LOCK WAIT 3 lock struct(s), heap size 1136, 2 row lock(s)
MySQL thread id 10, OS thread handle 140234567890, query id 100 localhost root updating
UPDATE t SET v=1 WHERE id=2

*** (1) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 50 page no 3 n bits 72 index PRIMARY of table `test`.`t`
trx id 12345 lock_mode X locks rec but not gap waiting
Record lock, heap no 3 PHYSICAL RECORD: n_fields 3; compact format; ...
 0: len 4; hex 80000002; asc     ;;  -- id=2

*** (2) TRANSACTION:
TRANSACTION 12346, ACTIVE 3 sec starting index read
mysql tables in use 1, locked 1
3 lock struct(s), heap size 1136, 2 row lock(s)
MySQL thread id 11, OS thread handle 140234567891, query id 101 localhost root updating
UPDATE t SET v=2 WHERE id=1

*** (2) HOLDS THE LOCK(S):
RECORD LOCKS space id 50 page no 3 n bits 72 index PRIMARY of table `test`.`t`
trx id 12346 lock_mode X locks rec but not gap
Record lock, heap no 3 PHYSICAL RECORD: n_fields 3; compact format; ...
 0: len 4; hex 80000002; asc     ;;  -- id=2

*** (2) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 50 page no 3 n bits 72 index PRIMARY of table `test`.`t`
trx id 12346 lock_mode X locks rec but not gap waiting
Record lock, heap no 2 PHYSICAL RECORD: n_fields 3; compact format; ...
 0: len 4; hex 80000001; asc     ;;  -- id=1

*** WE ROLL BACK TRANSACTION (2)
*/

-- 分析：
-- 事务1 (12345) 等待 id=2 的 X 锁
-- 事务2 (12346) 持有 id=2 的 X 锁，等待 id=1 的 X 锁
-- 事务1 持有 id=1 的 X 锁
-- 死锁：事务1 等事务2，事务2 等事务1
-- InnoDB 回滚了事务2（undo log 更少）

-- 开启完整的死锁日志
SET GLOBAL innodb_print_all_deadlocks = ON;
-- 所有死锁信息写入 error log
```

### 13.4 死锁日志分析步骤

```
死锁日志分析 5 步法：

  Step 1: 找到两个事务
  - *** (1) TRANSACTION: 事务1（被回滚的或等待的）
  - *** (2) TRANSACTION: 事务2（被回滚的或等待的）

  Step 2: 找到每个事务执行的 SQL
  - 事务1: UPDATE t SET v=1 WHERE id=2
  - 事务2: UPDATE t SET v=2 WHERE id=1

  Step 3: 找到每个事务持有的锁
  - *** (2) HOLDS THE LOCK(S): 事务2持有 id=2 的 X 锁
  - 事务1持有 id=1 的 X 锁（从 WAITING FOR 反推）

  Step 4: 找到每个事务等待的锁
  - *** (1) WAITING FOR: 事务1等待 id=2 的 X 锁
  - *** (2) WAITING FOR: 事务2等待 id=1 的 X 锁

  Step 5: 画等待图，确认死锁
  事务1 (持有 id=1, 等待 id=2)
  事务2 (持有 id=2, 等待 id=1)
  → 环：1→2→1 → 死锁

  最后看哪个被回滚：
  *** WE ROLL BACK TRANSACTION (2)
  → 事务2 被回滚（代价更小）
```

### 13.5 常见锁等待场景与优化

```
场景1：长事务持锁不释放

  问题描述：
  事务 A 执行一条慢 SQL，长时间持有锁
  事务 B~Z 都在等待 A 释放锁
  → 连接堆积，系统响应变慢

  排查：
  SELECT trx_id, trx_started, trx_query, 
         TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS duration
  FROM information_schema.innodb_trx
  ORDER BY trx_started ASC;
  
  优化：
  1. 优化慢 SQL（加索引、改写SQL）
  2. 缩短事务范围（不要在事务中做 RPC 调用）
  3. 设置 innodb_lock_wait_timeout = 10（缩短超时时间）

场景2：批量更新锁太多

  问题描述：
  UPDATE t SET status = 1 WHERE status = 0 LIMIT 10000;
  → 锁定 10000 行，阻塞其他事务

  优化：
  1. 分批更新：每次 UPDATE 100 行，循环执行
  2. 使用 SELECT ... FOR UPDATE 只锁需要的行
  3. 将大事务拆分为多个小事务

场景3：Gap Lock 导致 INSERT 阻塞

  问题描述（RR 级别）：
  事务 A: SELECT * FROM t WHERE id > 100 FOR UPDATE;
  → 加 Next-Key Lock (100, +∞)
  事务 B: INSERT INTO t VALUES (200, ...);
  → 被 Gap Lock 阻塞

  优化：
  1. 降级到 RC 隔离级别（无 Gap Lock）
  2. 缩小 A 的查询范围（精确条件代替范围查询）
  3. 使用 INSERT IGNORE 或 INSERT ... ON DUPLICATE KEY UPDATE

场景4：唯一键冲突导致的死锁

  问题描述：
  多个事务同时 INSERT 相同唯一键
  → S 锁兼容但 X 锁互斥 → 死锁

  优化：
  1. 先 SELECT 检查再 INSERT（但仍有并发问题）
  2. 使用 INSERT ... ON DUPLICATE KEY UPDATE
  3. 使用分布式锁/乐观锁控制并发
```

---

## 第十四部分：事务设计原则与最佳实践

### 14.1 事务设计 8 大原则

```
┌──────────────────────────────────────────────────────────────────┐
│                  事务设计 8 大原则                                │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. 事务要短小                                                   │
│     ✗ 错误：BEGIN; ... RPC调用 ... ... COMMIT;                  │
│     ✓ 正确：先准备好数据，再 BEGIN; SQL操作; COMMIT;             │
│     原则：事务中不要做耗时的非数据库操作                         │
│                                                                  │
│  2. 避免大事务                                                   │
│     ✗ 错误：一次 UPDATE 10 万行                                 │
│     ✓ 正确：分批 UPDATE，每批 100~500 行                       │
│     原则：大事务持有锁时间长、Undo Log 大、崩溃恢复慢            │
│                                                                  │
│  3. 加锁顺序一致                                                 │
│     ✗ 错误：事务A 先锁 id=1 再锁 id=2                          │
│             事务B 先锁 id=2 再锁 id=1                          │
│     ✓ 正确：所有事务都按 id 升序加锁                            │
│     原则：统一加锁顺序，避免循环等待死锁                         │
│                                                                  │
│  4. 使用合适的隔离级别                                           │
│     互联网应用：RC（高并发，允许幻读）                            │
│     金融账务：RR（严格一致性，防幻读）                            │
│     原则：不要无脑用默认 RR，RC 在大多数场景更合适               │
│                                                                  │
│  5. 避免锁升级                                                   │
│     ✗ 错误：SELECT * FROM t WHERE non_index_col = 1 FOR UPDATE  │
│     （无索引列查询，锁全表）                                      │
│     ✓ 正确：确保 WHERE 条件走索引                                │
│     原则：FOR UPDATE / LOCK IN SHARE MODE 必须走索引             │
│                                                                  │
│  6. 善用乐观锁                                                   │
│     ✗ 错误：SELECT ... FOR UPDATE; 修改; COMMIT;                │
│     ✓ 正确：SELECT version FROM t; 修改;                       │
│             UPDATE t SET ..., version=version+1                 │
│             WHERE id=? AND version=?;                           │
│     原则：冲突少的场景用乐观锁，避免持锁等待                     │
│                                                                  │
│  7. 控制事务传播行为（Spring）                                   │
│     @Transactional(propagation = REQUIRES_NEW)                  │
│     原则：日志/审计等操作用 REQUIRES_NEW，不受主事务影响         │
│                                                                  │
│  8. 处理死锁重试                                                 │
│     死锁是正常现象（ERROR 1213），应用层应自动重试               │
│     原则：捕获 DeadlockLoserDataAccessException，重试 2~3 次    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 14.2 Spring @Transactional 与隔离级别

```java
// Spring @Transactional 注解可以指定隔离级别

@Transactional(isolation = Isolation.READ_COMMITTED)
public void updateUser(Long id, String name) {
    // 此方法内所有 SQL 使用 RC 隔离级别
    userRepository.updateName(id, name);
}

// Isolation 枚举值：
// DEFAULT     → 使用数据库默认隔离级别
// READ_UNCOMMITTED → READ UNCOMMITTED
// READ_COMMITTED   → READ COMMITTED
// REPEATABLE_READ  → REPEATABLE READ
// SERIALIZABLE     → SERIALIZABLE

// Spring 如何设置隔离级别：
// 在事务开始时执行：
// SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
// 事务结束后恢复原隔离级别

// @Transactional 失效场景（与 AOP 代理相关）：
// 1. 方法不是 public（Spring AOP 只代理 public 方法）
// 2. 同类内部方法调用（this.xxx() 不走代理）
// 3. 异常被 catch 吞掉（Spring 检测不到异常，不会回滚）
// 4. 抛出非 RuntimeException（默认只回滚 RuntimeException）
//    → @Transactional(rollbackFor = Exception.class) 解决

// 正确的重试模板：
@Retryable(
    value = {DeadlockLoserDataAccessException.class},
    maxAttempts = 3,
    backoff = @Backoff(delay = 100, multiplier = 2)
)
@Transactional
public void transfer(Long from, Long to, BigDecimal amount) {
    accountDao.deduct(from, amount);
    accountDao.add(to, amount);
}
```

### 14.3 隔离级别选择建议

```
┌──────────────────────────────────────────────────────────────────┐
│              隔离级别选择决策树                                    │
│                                                                  │
│                    ┌─────────────────┐                           │
│                    │ 是否需要严格     │                           │
│                    │ 一致性？         │                           │
│                    └────────┬────────┘                           │
│                             │                                    │
│              ┌──────────────┼──────────────┐                     │
│              │ YES          │ NO           │                     │
│              ▼              ▼              │                     │
│     ┌──────────────┐  ┌──────────────┐   │                     │
│     │ RR (默认)     │  │ 是否允许     │   │                     │
│     │ 适合：金融、  │  │ 不可重复读？ │   │                     │
│     │ 账务、库存    │  └──────┬───────┘   │                     │
│     └──────────────┘         │           │                     │
│                    ┌─────────┼─────────┐ │                     │
│                    │ YES     │ NO      │ │                     │
│                    ▼         ▼         │ │                     │
│             ┌──────────┐ ┌──────────┐  │ │                     │
│             │ RC       │ │ RR       │  │ │                     │
│             │ (推荐)   │ │ + 乐观锁 │  │ │                     │
│             │ 互联网   │ │          │  │ │                     │
│             │ 通用     │ └──────────┘  │ │                     │
│             └──────────┘               │ │                     │
│                                        │ │                     │
│  Serializable 几乎不用（性能太差）      │ │                     │
│  RU 几乎不用（脏读不可接受）            │ │                     │
└──────────────────────────────────────────────────────────────────┘

  互联网公司常用配置：
  - 阿里：RC + binlog_format=ROW
  - 美团：RC + binlog_format=ROW
  - 字节：RC + binlog_format=ROW
  
  为什么互联网公司选 RC：
  1. 并发性能更好（无 Gap Lock）
  2. 死锁概率更低
  3. 长事务影响更小
  4. 配合 ROW 格式 Binlog，主从一致
  5. 幻读问题在业务层面处理（乐观锁/唯一约束）
```

### 14.4 InnoDB 锁相关参数调优

```sql
-- 1. 锁等待超时（秒）
innodb_lock_wait_timeout = 50
-- 建议：高并发场景设为 10~30 秒
-- 过长：锁等待堆积；过短：正常事务被误杀

-- 2. 死锁检测
innodb_deadlock_detect = ON
-- 高并发场景（>1000 TPS）考虑关闭，用 lock_wait_timeout 兜底
-- 关闭死锁检测可减少 CPU 开销

-- 3. 隔离级别
transaction_isolation = 'READ-COMMITTED'
-- 互联网应用建议 RC

-- 4. 自增锁模式
innodb_autoinc_lock_mode = 2
-- MySQL 8.0 默认值，并发性能最好

-- 5. Undo Log 相关
innodb_undo_log_truncate = ON
innodb_max_undo_log_size = 1G
-- 自动截断 Undo 表空间，防止长事务导致 Undo 膨胀

-- 6. Redo Log 相关
innodb_log_buffer_size = 64M
-- 大事务场景增大，减少 redo log buffer 刷盘频率

innodb_log_file_size = 1G  (MySQL 8.0: innodb_redo_log_capacity)
-- Redo Log 文件大小，影响 checkpoint 频率
-- 太小：频繁 checkpoint，redo log stall
-- 太大：崩溃恢复时间长

-- 7. Buffer Pool 相关
innodb_buffer_pool_size = 物理内存的 60~80%
innodb_buffer_pool_instances = 4~8
-- 多实例减少锁竞争

-- 8. 事务相关
autocommit = 1
-- 保持默认 ON，避免忘记 COMMIT 导致长事务

-- 9. 死锁日志
innodb_print_all_deadlocks = ON
-- 将所有死锁写入 error log，便于排查
```

---

## 附录 A：InnoDB 事务与锁核心源码文件索引

```
┌──────────────────────────────────────────────────────────────────┐
│          InnoDB 事务与锁核心源码文件索引                          │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  事务核心：                                                     │
│  ├── trx0trx.h / trx0trx.cc      → trx_t 结构、事务开始/提交   │
│  ├── trx0roll.h / trx0roll.cc    → 事务回滚                     │
│  ├── trx0types.h                  → 事务类型定义                 │
│  ├── trx0undo.h / trx0undo.cc    → Undo Log 管理                │
│  ├── trx0purge.h / trx0purge.cc  → Purge 线程（清理Undo）       │
│  ├── trx0rec.h / trx0rec.cc      → Undo Log 记录格式            │
│  └── trx0rseg.h / trx0rseg.cc    → 回滚段管理                   │
│                                                                │
│  MVCC：                                                        │
│  ├── read0read.h / read0read.cc  → ReadView 结构与可见性判断     │
│  ├── row0vers.h / row0vers.cc    → 版本链遍历                    │
│  └── row0sel.h / row0sel.cc      → 快照读入口                    │
│                                                                │
│  锁：                                                          │
│  ├── lock0lock.h / lock0lock.cc  → 锁核心（加锁/冲突检测）       │
│  ├── lock0deadlock.h / lock0deadlock.cc → 死锁检测              │
│  ├── lock0prdt.h / lock0prdt.cc  → 谓词锁                       │
│  ├── lock0types.h                 → 锁类型定义                   │
│  └── lock0wait.h / lock0wait.cc  → 锁等待管理                    │
│                                                                │
│  Redo Log：                                                    │
│  ├── log0log.h / log0log.cc      → Redo Log 核心                │
│  ├── log0buf.h / log0buf.cc      → Redo Log Buffer              │
│  ├── log0write.h / log0write.cc  → Redo Log 写入                │
│  ├── log0recv.h / log0recv.cc    → 崩溃恢复                      │
│  ├── mtr0mtr.h / mtr0mtr.cc      → Mini-Transaction             │
│  └── mtr0log.h / mtr0log.cc      → mtr 日志记录                  │
│                                                                │
│  Buffer Pool：                                                 │
│  ├── buf0buf.h / buf0buf.cc      → Buffer Pool 核心             │
│  ├── buf0flu.h / buf0flu.cc      → 脏页刷盘                     │
│  ├── buf0lru.h / buf0lru.cc      → LRU 淘汰                     │
│  └── buf0checksum.h / buf0checksum.cc → 页校验                  │
│                                                                │
│  两阶段提交：                                                   │
│  ├── trx0trx.cc                   → trx_t::commit()             │
│  ├── log0log.cc                   → log_write_up_to()           │
│  └── sql/binlog.cc                → MYSQL_BIN_LOG::commit()     │
│                                                                │
│  Crash Recovery：                                              │
│  ├── srv0start.h / srv0start.cc  → 启动入口                     │
│  ├── log0recv.cc                  → redo log 重放               │
│  └── trx0roll.cc                  → 未完成事务回滚               │
│                                                                │
└──────────────────────────────────────────────────────────────────┘
```

---

## 附录 B：锁类型与隔离级别速查表

```
┌──────────────────────────────────────────────────────────────────┐
│              锁类型速查表                                        │
├──────────────────┬───────────────────────────────────────────────┤
│  全局锁          │ FTWRL → 全库只读                               │
│                  │ 场景：全库逻辑备份                             │
├──────────────────┼───────────────────────────────────────────────┤
│  表锁            │ LOCK TABLES t READ/WRITE                      │
│                  │ 场景：DDL 操作                                 │
├──────────────────┼───────────────────────────────────────────────┤
│  意向锁 (IS/IX)  │ 加行锁前自动加，表级                           │
│                  │ 场景：快速判断表中是否有行锁                    │
├──────────────────┼───────────────────────────────────────────────┤
│  AUTO-INC 锁     │ 自增列锁                                       │
│                  │ 场景：INSERT 自增主键                          │
├──────────────────┼───────────────────────────────────────────────┤
│  Record Lock     │ 锁定单条记录                                   │
│                  │ 场景：等值查询唯一索引命中                      │
├──────────────────┼───────────────────────────────────────────────┤
│  Gap Lock        │ 锁定间隙（不含记录）                           │
│                  │ 场景：RR级别等值查询唯一索引未命中              │
├──────────────────┼───────────────────────────────────────────────┤
│  Next-Key Lock   │ Record + Gap（锁记录+前间隙）                  │
│                  │ 场景：RR级别范围查询、非唯一索引等值查询        │
├──────────────────┼───────────────────────────────────────────────┤
│  Insert Intention│ INSERT 前的间隙锁                              │
│  Lock            │ 场景：插入到有 Gap Lock 的间隙                  │
├──────────────────┼───────────────────────────────────────────────┤
│  Predicate Lock  │ 空间索引谓词锁                                 │
│                  │ 场景：GIS 空间索引                             │
└──────────────────┴───────────────────────────────────────────────┘


┌──────────────────────────────────────────────────────────────────┐
│              隔离级别与锁行为速查表                               │
├─────────────────┬───────────┬───────────┬───────────┬───────────┤
│  行为            │ RU        │ RC        │ RR        │ SERIALIZABLE│
├─────────────────┼───────────┼───────────┼───────────┼───────────┤
│ 快照读          │ 读最新    │ MVCC      │ MVCC      │ 隐式加S锁  │
│                 │ (脏读)    │ (每次新RV)│ (复用RV)  │ (不走MVCC) │
├─────────────────┼───────────┼───────────┼───────────┼───────────┤
│ 当前读加锁      │ Record    │ Record    │ Next-Key  │ Next-Key   │
│                 │ Lock      │ Lock      │ Lock      │ Lock + S   │
├─────────────────┼───────────┼───────────┼───────────┼───────────┤
│ Gap Lock        │ 无        │ 无        │ 有        │ 有         │
├─────────────────┼───────────┼───────────┼───────────┼───────────┤
│ 防幻读          │ ✗         │ ✗         │ ✓         │ ✓         │
├─────────────────┼───────────┼───────────┼───────────┼───────────┤
│ 死锁概率        │ 低        │ 低        │ 中        │ 高         │
├─────────────────┼───────────┼───────────┼───────────┼───────────┤
│ 并发性能        │ 最高      │ 高        │ 中        │ 最低       │
├─────────────────┼───────────┼───────────┼───────────┼───────────┤
│ Binlog格式要求  │ ROW       │ ROW       │ ROW/STMT  │ ROW/STMT   │
└─────────────────┴───────────┴───────────┴───────────┴───────────┘
```

---

## 附录 C：与前面文档的衔接关系

```
┌──────────────────────────────────────────────────────────────────┐
│              MySQL 系列文档衔接关系                               │
│                                                                  │
│  《MySQL索引底层原理深度解析》                                    │
│  ├── B+Tree 结构、页结构、聚簇/二级索引                           │
│  ├── 最左前缀、覆盖索引、ICP                                      │
│  └──→ 本文的 MVCC 版本链、Gap Lock 都建立在索引结构之上          │
│       (Gap Lock 锁的是索引记录之间的间隙)                         │
│                                                                  │
│  《MySQL EXPLAIN实战与慢查询优化》                                │
│  ├── EXPLAIN 12列、访问类型、Extra                               │
│  ├── ORDER BY / JOIN / 子查询优化                                │
│  └──→ 本文的锁等待分析、死锁排查是慢查询的另一种维度              │
│       (锁等待导致的慢 ≠ 索引问题导致的慢)                         │
│                                                                  │
│  《Spring全家桶综合串讲》                                        │
│  ├── @Transactional 的传播行为、失效场景                         │
│  ├── AOP 代理 → TransactionInterceptor                           │
│  └──→ 本文从 MySQL 底层解释 @Transactional 的隔离级别设置         │
│       和事务提交/回滚的底层行为                                   │
│                                                                  │
│  《Spring AOP源码深度解析》                                      │
│  ├── TransactionInterceptor → DataSource → Connection            │
│  ├── ThreadLocal 绑定 Connection                                 │
│  └──→ 本文的 trx_t 对应 Spring 的 Connection                     │
│       ReadView 对应 Spring 的 @Transactional(isolation=...)      │
│                                                                  │
│  完整链路：                                                      │
│  Spring @Transactional                                           │
│    → TransactionInterceptor.invoke()                             │
│    → DataSource.getConnection()                                  │
│    → MySQL trx_t (BEGIN)                                         │
│    → MVCC ReadView (SELECT 快照读)                               │
│    → Record/Gap/Next-Key Lock (FOR UPDATE 当前读)                │
│    → Undo Log (回滚/版本链)                                      │
│    → Redo Log (WAL/持久性)                                       │
│    → 2PC (Redo Log + Binlog 一致性)                              │
│    → COMMIT / ROLLBACK                                           │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 总结

本文从 InnoDB 源码层面系统解析了 MySQL 事务与锁的完整底层原理：

**核心知识点串联**：

1. **ACID 四大特性** — A 靠 Undo Log，I 靠 MVCC + Lock，D 靠 Redo Log，C 是 AID 的目标

2. **四种隔离级别** — RU（脏读）→ RC（不可重复读）→ RR（可重复读+防幻读）→ Serializable（串行化）；InnoDB 的 RR 通过 MVCC + Next-Key Lock 超出了 SQL 标准

3. **MVCC 三要素** — 隐藏字段（DB_TRX_ID + DB_ROLL_PTR）+ Undo Log 版本链 + ReadView（4 个核心字段 + 可见性判断算法）；RC 每次 SELECT 创建新 ReadView，RR 事务内复用

4. **Undo Log** — Insert Undo（提交后即清理）vs Update Undo（等 Purge 清理）；版本链构建、Purge 线程清理、长事务危害

5. **Redo Log** — WAL 原则（先写日志再写数据）、LSN 体系、Mini-Transaction、Checkpoint、Group Commit、崩溃恢复

6. **InnoDB 锁体系** — Record Lock（锁记录）+ Gap Lock（锁间隙）+ Next-Key Lock（锁记录+前间隙）+ Insert Intention Lock（插入意向锁）+ 意向锁（IS/IX）+ AUTO-INC 锁

7. **加锁规则** — RR 级别的 7 种场景规则（唯一索引等值命中/未命中、范围查询、非唯一索引等值/范围）；RC 级别只用 Record Lock

8. **死锁** — Wait-for Graph 检测算法、3 种常见死锁场景（互更新、Gap Lock、唯一键冲突）、死锁日志分析 5 步法

9. **RC vs RR** — ReadView 策略差异、Gap Lock 有无、死锁概率、半一致性读、Binlog 格式要求；互联网公司普遍选择 RC

10. **两阶段提交** — Redo Log Prepare → Binlog 写入 → Redo Log Commit；保证 Redo Log 与 Binlog 的一致性，进而保证主从一致

11. **分布式事务** — XA 两阶段提交、TCC、Saga、本地消息表、Seata AT 等替代方案

12. **实战** — 锁等待排查（innodb_trx + data_locks + data_lock_waits）、死锁排查（SHOW ENGINE INNODB STATUS + 5 步分析法）、8 大事务设计原则

建议配合之前的《MySQL索引底层原理深度解析》和《MySQL EXPLAIN实战与慢查询优化》一起阅读，形成 MySQL 从索引→查询优化→事务锁的完整知识体系。