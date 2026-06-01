---
title: MySQL 面试理论
tags:
  - Database
  - Interview
---

## 一、索引底层结构（必问硬核）

> **Q1** 为什么 MySQL InnoDB 用 B+ 树而不是 B 树？B+ 树比 B 树多了哪些关键特性？（从数据存储位置、叶子节点连接、IO 效率三个维度对比）

> **Q2** B+ 树为什么比红黑树更适合做数据库索引？从磁盘 IO、树的高度、范围查询三个角度分析。

> **Q3** 为什么建议 InnoDB 表必须有主键？如果你不指定主键，InnoDB 会怎么做？`ROW_ID` 是什么？自增主键 vs UUID 做索引的性能差异？

> **Q4** 聚簇索引和非聚簇索引的区别？回表是什么意思？覆盖索引如何避免回表？写一条覆盖索引的 SQL 示例。

---

## 二、联合索引 & 索引实战

> **Q5** 联合索引 `(a, b, c)` 的最左前缀原则：以下查询哪些能走索引？`WHERE a=1`、`WHERE a=1 AND b=2`、`WHERE b=2`、`WHERE a=1 AND c=3`、`WHERE b=2 AND c=3`、`WHERE a>1 AND b=2`、`ORDER BY b`？

> **Q6** 索引失效的常见场景，至少说 8 种。`WHERE name LIKE '%abc'` 为什么不行？`!=`/`<>` 一定不走索引吗？

> **Q7** 字符串字段不加引号会发生什么？`WHERE phone = 13800000000`（phone 是 `varchar`）会走索引吗？隐式类型转换底层是怎么执行的？

> **Q8** `ORDER BY a, b` 和 `ORDER BY b, a` 在使用联合索引 `(a, b)` 时有什么区别？`ORDER BY` 怎么也讲究最左前缀？

---

## 三、事务 ACID & 隔离级别

> **Q9** ACID 四个特性分別由什么技术保证？（undo log → 原子性、redo log → 持久性、MVCC+锁 → 隔离性、约束+事务 → 一致性）

> **Q10** 四个隔离级别各自解决什么问题？脏读、不可重复读、幻读分别是什么？InnoDB 的可重复读能解决幻读吗？（能，但不完全能）

> **Q11** 什么是"当前读"和"快照读"？`SELECT`、`SELECT ... FOR UPDATE`、`INSERT`/`UPDATE`/`DELETE` 分别属于哪种？为什么 `FOR UPDATE` 能防止幻读但普通 `SELECT` 不行？

> **Q12** `READ COMMITTED` 和 `REPEATABLE READ` 在 MVCC 层面，`Read View` 的生成时机有什么区别？（RC：每次快照读生成 / RR：事务第一次快照读生成）

---

## 四、MVCC（必问源码级）

> **Q13** MVCC 依赖哪三个隐藏列？`DB_TRX_ID`、`DB_ROLL_PTR`、`DB_ROW_ID` 分别在什么时候写入？

> **Q14** `Read View` 的四个关键字段是什么？`m_ids`、`min_trx_id`、`max_trx_id`、`creator_trx_id`，一条 undo log 版本记录的可见性判断规则说清楚。

> **Q15** 如果事务 A 先插入一条记录（未提交），事务 B 用快照读能查到吗？事务 B 用当前读呢？undo log 版本链在插入时也会生成吗？

---

## 五、日志系统（redo / undo / binlog）

> **Q16** `redo log` 和 `binlog` 的区别？（所属层、记录内容、写入时机、用途四个维度对比）

> **Q17** 两阶段提交（2PC）的流程：`redo log prepare` → `binlog write` → `redo log commit`，如果每一步之间崩溃了，怎么恢复？为什么能保证一致性？

> **Q18** `undo log` 的两个作用？事务回滚和 MVCC 哪个依赖 `undo log`？`undo log` 什么时候被删除？（并不是事务结束就删）

---

## 六、SQL 优化 & EXPLAIN

> **Q19** `EXPLAIN` 输出的 `type` 字段从好到坏依次是什么？`const`、`eq_ref`、`ref`、`range`、`index`、`ALL` 分别对应什么查询？

> **Q20** `EXPLAIN` 的 `Extra` 字段中，`Using index`、`Using index condition`（索引下推 ICP）、`Using where`、`Using filesort`、`Using temporary` 分别说明什么问题？哪个是一定要优化的？

> **Q21** 深度分页 `LIMIT 1000000, 10` 为什么慢？延迟关联（子查询 + JOIN）怎么优化？游标分页（CURSOR）和传统分页有什么区别？

> **Q22** 一个慢 SQL 的排查思路：从发现到优化，你完整的操作流程是什么？

---

## 七、锁机制（InnoDB 锁深入）

> **Q23** InnoDB 的行锁实际上锁的是什么？为什么说"如果没有索引，行锁会升级为表锁"？

> **Q24** 共享锁、排他锁、意向锁的区别？为什么需要意向锁（IS/IX）？它解决了什么问题？

> **Q25** 记录锁（Record Lock）、间隙锁（Gap Lock）、临键锁（Next-Key Lock）分别锁什么范围？在哪个隔离级别下生效？

> **Q26** RR 隔离级别下，间隙锁如何防止幻读？如果是 RC 隔离级别，还有间隙锁吗？这个区别对你的项目选型有什么影响？

> **Q27** 死锁是怎么产生的？`SHOW ENGINE INNODB STATUS` 怎么看死锁日志？两个事务分别 `UPDATE t SET c=1 WHERE id=1` 和 `UPDATE t SET c=2 WHERE id=2` 会死锁吗？什么情况下会？

---

## 八、Buffer Pool & Change Buffer

> **Q28** Buffer Pool 里有什么？Free List、LRU List（young/old 分区）、Flush List 分别干什么？

> **Q29** Change Buffer 是什么？对什么类型的操作有优化效果？为什么唯一索引的写操作用不了 Change Buffer？

---

## 九、MySQL 8.0 新特性（拉开分差）

> **Q30** MySQL 8.0 的原子 DDL（Atomic DDL）是什么？`ALTER TABLE` 中途失败了，会半途留下脏字段吗？

> **Q31** MySQL 8.0 的不可见索引（Invisible Index）和降序索引（Descending Index）各有什么作用？不可见索引用在什么场景？

> **Q32** MySQL 8.0 窗口函数（`ROW_NUMBER()`/`RANK()`/`DENSE_RANK()`）和 CTE（`WITH AS` 公用表表达式）有什么用？写一个"每个部门工资前三名"的 SQL。

---

## 十、实战场景

> **Q33** 一个 5000 万行的大表，要加一个字段（`ALTER TABLE ADD COLUMN`），直接执行会锁表吗？如何安全地在线上加字段？（Online DDL、pt-online-schema-change、gh-ost）

> **Q34** 分库分表后，跨分片的 `ORDER BY time DESC LIMIT 10` 怎么实现？如果按 `user_id` 分片，现在要按 `order_time` 排序查所有用户的最近 10 单，怎么办？

> **Q35** 主从延迟的原因有哪些？你怎么监控主从延迟？如果业务能容忍 500ms 延迟，但偶尔会到 5 秒，你怎么做"读写分离"下的兜底？（强制走主库 / 从库超时降级）

> **Q36** 一个交易系统的核心表，QPS 10000，UPDATE 占 60%，怎么做高并发下的库存扣减？（`UPDATE ... SET stock = stock - 1 WHERE stock > 0` → 乐观锁、Redis 预热扣减 + 异步写 MySQL）
