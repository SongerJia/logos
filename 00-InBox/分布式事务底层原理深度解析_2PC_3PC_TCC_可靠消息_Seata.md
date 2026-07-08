# 分布式事务底层原理深度解析：2PC/3PC + TCC + 可靠消息 + Seata

> 本文从底层原理出发，系统解析分布式事务的核心理论、经典方案与 Seata 实现，让你不翻项目源码也能彻底搞懂分布式事务的来龙去脉。

---

## 目录

- [一、为什么需要分布式事务](#一为什么需要分布式事务)
- [二、理论基础：CAP 与 BASE](#二理论基础cap-与-base)
- [三、2PC — 两阶段提交](#三2pc--两阶段提交)
- [四、3PC — 三阶段提交](#四3pc--三阶段提交)
- [五、TCC — Try‑Confirm‑Cancel](#五tcc--tryconfirmcancel)
- [六、可靠消息最终一致性](#六可靠消息最终一致性)
- [七、Seata — 阿里分布式事务框架](#七seata--阿里分布式事务框架)
- [八、各方案对比与选型指南](#八各方案对比与选型指南)
- [九、面试高频问题与标准回答](#九面试高频问题与标准回答)

---

## 一、为什么需要分布式事务

### 1.1 单机事务的局限

在单体架构中，所有业务数据存储在同一个数据库实例中，本地事务（`BEGIN → SQL → COMMIT`）由数据库的 ACID 机制保证：

| 特性 | 含义 | 单机保证方式 |
|------|------|-------------|
| **A**tomicity | 全做或全不做 | undo log（回滚日志） |
| **C**onsistency | 约束不被破坏 | 约束检查 + 锁 |
| **I**solation | 并发互不干扰 | MVCC / 锁机制 |
| **D**urability | 提交后不丢 | redo log（重做日志） |

一旦业务拆分为微服务，**一个业务操作跨越多个数据库实例**，单机事务就无法覆盖了。

### 1.2 典型分布式事务场景

```
场景1：电商下单
  ├── 订单服务 → 创建订单（订单DB）
  ├── 库存服务 → 扣减库存（库存DB）
  ├── 账户服务 → 扣减余额（账户DB）
  └── 积分服务 → 增加积分（积分DB）
  问题：订单创建了，库存扣了，余额扣失败 → 数据不一致

场景2：跨行转账
  ├── A银行 → 扣减账户（A银行DB）
  ├── B银行 → 增加账户（B银行DB）
  问题：A扣了钱，B没收到 → 资金丢失

场景3：订单+MQ
  ├── 订单DB → 创建订单
  ├── RocketMQ → 发送消息通知下游
  问题：订单创建成功但消息发送失败 → 下游不感知
```

### 1.3 分布式事务的本质

**分布式事务 = 保证跨节点操作的原子性与一致性**

核心矛盾：
- **网络不可靠**：节点间通信可能超时、丢包、乱序
- **节点不可靠**：任意节点可能宕机、重启
- **时钟不可靠**：各节点时钟不一致

因此，分布式事务不可能完美达到单机 ACID，只能在**一致性强度**与**可用性**之间做权衡。

---

## 二、理论基础：CAP 与 BASE

### 2.1 CAP 定理

```
         C (Consistency)          A (Availability)
        ┌─────────────────┐     ┌─────────────────┐
        │ 所有节点读到的   │     │ 每个请求都得到   │
        │ 数据一致        │     │ 非错误响应       │
        └─────────────────┘     └─────────────────┘
                      ╲            ╱
                       ╲          ╱
                        ╲        ╱
                    ┌─────────────────┐
                    │ P (Partition)   │
                    │ 网络分区必然发生 │
                    └─────────────────┘
```

**Brewer 定理核心结论**：当网络分区发生时（P 必然成立），**C 和 A 只能选择其一**。

| 组合 | 含义 | 适用场景 |
|------|------|---------|
| **CP** | 分区时牺牲可用性，保证一致性 | ZooKeeper、Etcd、HBase |
| **AP** | 分区时牺牲强一致性，保证可用性 | Eureka、Cassandra、DNS |
| **CA** | 不分区时才能同时满足（理论存在，现实不存在） | 单机数据库 |

**对分布式事务的影响**：
- 追求 **强一致性**（CP）→ 2PC/XA，但分区时阻塞不可用
- 追求 **高可用性**（AP）→ 最终一致性方案（TCC/消息），允许短暂不一致

### 2.2 BASE 理论

BASE 是对 CAP 中 AP 方向的工程化总结：

| 缩写 | 全称 | 含义 |
|------|------|------|
| **BA** | Basically Available | 基本可用：允许响应时间变长或功能降级 |
| **S** | Soft State | 软状态：允许中间状态存在（数据暂时不一致） |
| **E** | Eventually Consistent | 最终一致性：经过一段时间后数据终会一致 |

**BASE vs ACID**：

```
ACID（传统数据库）
  ┌──────────────────────────┐
  │  强一致性 · 立即可见      │
  │  牺牲可用性 · 性能        │
  └──────────────────────────┘

BASE（分布式系统）
  ┌──────────────────────────┐
  │  最终一致性 · 延迟可见    │
  │  保证可用性 · 更高性能    │
  └──────────────────────────┘

     一致性强度 ─────────────────────→
     2PC/XA     TCC     可靠消息    Saga
     强 ←──────────────────────────→ 弱

     可用性 ──────────────────────→
     2PC/XA     TCC     可靠消息    Saga
     低 ←──────────────────────────→ 高
```

### 2.3 一致性模型分类

| 级别 | 名称 | 特点 | 代表方案 |
|------|------|------|---------|
| 1 | **强一致性** | 任何时刻读到的数据都是最新提交的 | 2PC/XA |
| 2 | **顺序一致性** | 所有节点看到相同的操作顺序 | Paxos/Raft |
| 3 | **因果一致性** | 因果相关的操作有序，无关操作可乱序 | CRDT |
| 4 | **最终一致性** | 一段时间后数据趋同 | 可靠消息/TCC |
| 5 | **弱一致性** | 不保证趋同 | 最大努力通知 |

---

## 三、2PC — 两阶段提交

### 3.1 起源与背景

2PC（Two-Phase Commit）最早由 Jim Gray 在 1978 年论文《Notes on Data Base Operating Systems》中提出，是分布式事务的**奠基性协议**。

核心角色：
- **Coordinator（协调者/事务管理器 TM）**：全局决策者
- **Participant（参与者/资源管理器 RM）**：各数据库节点

### 3.2 协议流程

#### Phase 1：准备阶段（Prepare / Vote）

```
                Coordinator
                    │
        ┌───────────┼───────────┐
        │           │           │
   Prepare      Prepare      Prepare
        │           │           │
    ┌───┴───┐   ┌───┴───┐   ┌───┴───┐
    │ RM-1  │   │ RM-2  │   │ RM-3  │
    │       │   │       │   │       │
    │执行SQL│   │执行SQL│   │执行SQL│
    │写undo │   │写undo │   │写undo │
    │写redo │   │写redo │   │写redo │
    │持锁   │   │持锁   │   │持锁   │
    └───┬───┘   └───┬───┘   └───┬───┘
        │           │           │
     Yes/No      Yes/No      Yes/No
        │           │           │
        └───────────┼───────────┘
                    │
               收集所有投票
```

**每个参与者的 Prepare 动作**：

1. **执行事务操作**：执行 SQL 但不提交
2. **写 undo log**：记录回滚信息（修改前的值）
3. **写 redo log**：记录提交信息（修改后的值）
4. **加锁**：锁定涉及的资源，防止其他事务修改
5. **投票**：向协调者回复 `Yes`（准备好）或 `No`（无法执行）

> 关键：Prepare 成功意味着参与者**已经具备随时提交或回滚的能力**。

#### Phase 2：提交阶段（Commit / Abort）

**情况1：所有参与者投票 Yes → 全部提交**

```
                Coordinator
                    │
        ┌───────────┼───────────┐
        │           │           │
     Commit       Commit       Commit
        │           │           │
    ┌───┴───┐   ┌───┴───┐   ┌───┴───┐
    │ RM-1  │   │ RM-2  │   │ RM-3  │
    │提交   │   │提交   │   │提交   │
    │释放锁 │   │释放锁 │   │释放锁 │
    │清日志 │   │清日志 │   │清日志 │
    └───┬───┘   └───┬───┘   └───┬───┘
        │           │           │
       ACK         ACK         ACK
        │           │           │
        └───────────┼───────────┘
                    │
              事务完成 ✓
```

**情况2：任一参与者投票 No 或超时 → 全部回滚**

```
                Coordinator
                    │
        ┌───────────┼───────────┐
        │           │           │
     Rollback     Rollback     Rollback
        │           │           │
    ┌───┴───┐   ┌───┴───┐   ┌───┴───┐
    │ RM-1  │   │ RM-2  │   │ RM-3  │
    │回滚   │   │回滚   │   │回滚   │
    │释放锁 │   │释放锁 │   │释放锁 │
    │清日志 │   │清日志 │   │清日志 │
    └───┬───┘   └───┬───┘   └───┬───┘
        │           │           │
       ACK         ACK         ACK
        └───────────┼───────────┘
                    │
              事务回滚 ✗
```

### 3.3 完整时序图

```
时间轴 →

RM-1            Coordinator              RM-2            RM-3
 │                  │                     │               │
 │  ──Prepare────→ │                     │               │
 │                  │──Prepare──────────→│               │
 │                  │──Prepare──────────────────────────→│
 │                  │                     │               │
 │  ←──Yes──────── │                     │               │
 │                  │←──Yes─────────────│               │
 │                  │←──Yes─────────────────────────────│
 │                  │                     │               │
 │                  │ [所有Yes → 决定Commit]              │
 │                  │                     │               │
 │  ──Commit─────→ │                     │               │
 │                  │──Commit──────────→│               │
 │                  │──Commit──────────────────────────→│
 │                  │                     │               │
 │  ←──ACK─────── │                     │               │
 │                  │←──ACK─────────────│               │
 │                  │←──ACK─────────────────────────────│
 │                  │                     │               │
 │            [事务完成]                  │               │
```

### 3.4 2PC 的致命问题

#### 问题1：同步阻塞（Blocking）

```
                    时间轴 →
RM-1     Coordinator     RM-2
 │           │            │
 │──Yes──→  │            │
 │  [等待]  │──Prepare──→│
 │  [等待]  │  [等待]    │ ← RM-2 执行慢
 │  [等待]  │  [等待]    │
 │  [等待]  │  [等待]    │ ← RM-1 持锁，其他事务全部阻塞！
 │  [等待]  │  [等待]    │
 │  [等待]  │←──Yes───  │
 │←──Commit─│──Commit──→│
```

**影响**：
- Prepare 阶段持有资源锁 → 其他事务等待
- 协调者等待所有参与者投票 → 延迟叠加
- 整个事务期间，涉及的所有资源**被锁定不可用**

#### 问题2：单点故障（Coordinator Down）

```
情况A：协调者 Prepare 后宕机
  RM-1: Yes（持锁等待）
  RM-2: Yes（持锁等待）
  Coordinator: 宕机 ← 无法发出 Commit/Rollback
  → 所有参与者永远阻塞！资源锁永不释放！

情况B：协调者 Commit 后宕机（部分参与者未收到）
  RM-1: 收到 Commit → 提交
  RM-2: 未收到 → 仍在持锁等待
  → 数据不一致！
```

#### 问题3：网络分区（Split Brain）

```
Coordinator 发出 Commit 消息后网络分区：

  ┌─────────────────┐     ┌─────────────────┐
  │ Partition A     │     │ Partition B     │
  │ Coordinator     │     │ RM-3            │
  │ RM-1 (committed)│     │ (still waiting) │
  │ RM-2 (committed)│     │                 │
  └─────────────────┘     └─────────────────┘

  → Partition A 已提交，Partition B 仍在等待
  → 全局不一致，且 RM-3 永久持锁阻塞
```

#### 问题4：太保守（Conservative）

只要一个参与者回复 No 或超时，**所有参与者都要回滚**，即使大部分已经准备好。这在高并发场景下容易导致大量不必要的回滚。

### 3.5 XA 规范 — 2PC 的工业标准

XA 是 X/Open 组织定义的分布式事务处理标准，是 2PC 在数据库层面的实现规范。

#### XA 接口定义

```java
// X/Open XA 规范核心接口
public interface XAResource {
    // 第一阶段：准备
    int prepare(Xid xid) throws XAException;
    // 返回值：XA_RDONLY（只读无需提交） / XA_OK（准备好）

    // 第二阶段：提交
    void commit(Xid xid, boolean onePhase) throws XAException;
    // onePhase=true → 一阶段提交（只有一个参与者时优化）

    // 第二阶段：回滚
    void rollback(Xid xid) throws XAException;

    // 分支事务结束（不提交不回滚，仅断开关联）
    void end(Xid xid, int flags) throws XAException;

    // 开始分支事务
    void start(Xid xid, int flags) throws XAException;
}
```

#### MySQL XA 实现

```sql
-- MySQL XA 事务操作流程
XA START 'xid_branch_1';       -- 开始XA事务分支
UPDATE account SET balance = balance - 100 WHERE id = 1;
XA END 'xid_branch_1';         -- 结束SQL阶段
XA PREPARE 'xid_branch_1';     -- 第一阶段：准备
-- 等待TM决策...
XA COMMIT 'xid_branch_1';      -- 第二阶段：提交
-- 或
XA ROLLBACK 'xid_branch_1';    -- 第二阶段：回滚
```

**MySQL XA 的底层实现**：

```
XA PREPARE 时 MySQL 内部：
  1. 写入 redo log（记录修改后的数据）
  2. 写入 undo log（记录修改前的数据，用于回滚）
  3. 将事务状态标记为 PREPARED
  4. 持锁等待 TM 决策

XA COMMIT 时 MySQL 内部：
  1. 将事务状态从 PREPARED → COMMITTED
  2. 释放所有行锁/表锁
  3. 清理 undo log（提交后无需回滚）

XA ROLLBACK 时 MySQL 内部：
  1. 利用 undo log 回滚所有修改
  2. 释放所有锁
  3. 将事务状态标记为 ROLLED_BACK
```

#### MySQL XA 的 `xa_recovery` 机制

```sql
-- 宕机恢复时查询 PREPARED 状态的事务
XA RECOVER;

-- 输出示例：
-- formatID: 1, gtrid_length: 5, bqual_length: 7, data: tx123_branch1
-- 表示事务 tx123 的分支 branch1 处于 PREPARED 状态

-- TM 根据日志决定：
XA COMMIT 'tx123_branch1';     -- 如果全局决策是提交
XA ROLLBACK 'tx123_branch1';   -- 如果全局决策是回滚
```

#### XA 的实际缺陷

| 缺陷 | 说明 |
|------|------|
| **性能差** | 持锁时间长，并发吞吐量极低 |
| **日志开销** | Prepare 阶段需要写 undo + redo，双份日志 |
| **单点阻塞** | TM 宕机所有 RM 阻塞 |
| **不支持跨服务** | XA 仅适用于同一 TM 管理的数据库，不适用于微服务调用 |
| **MySQL 5.7 之前 xa 与 replication 不兼容** | 主从复制时 PREPARED 事务可能丢失 |

---

## 四、3PC — 三阶段提交

### 4.1 3PC 的设计动机

3PC（Three-Phase Commit）是对 2PC **阻塞问题**的改进尝试。核心思路：在 Prepare 前增加一个**轻量的检查阶段**，降低资源锁定的时间窗口。

### 4.2 三个阶段详解

#### Phase 1：CanCommit（询问阶段）

```
                Coordinator
                    │
        ┌───────────┼───────────┐
        │           │           │
   CanCommit    CanCommit    CanCommit
        │           │           │
    ┌───┴───┐   ┌───┴───┐   ┌───┴───┐
    │ RM-1  │   │ RM-2  │   │ RM-3  │
    │       │   │       │   │       │
    │检查: │   │检查: │   │检查: │
    │·有锁?│   │·有锁?│   │·有锁?│
    │·可执行?│   │·可执行?│   │·可执行?│
    │·不执行│   │·不执行│   │·不执行│
    │  SQL │   │  SQL │   │  SQL │
    └───┬───┘   └───┬───┘   └───┬───┘
        │           │           │
     Yes/No      Yes/No      Yes/No
```

**关键**：CanCommit 阶段**不执行任何 SQL，不持锁，不写日志**，只做可行性检查。

#### Phase 2：PreCommit（预提交阶段）

```
所有参与者回复 Yes → 进入 PreCommit

                Coordinator
                    │
        ┌───────────┼───────────┐
        │           │           │
   PreCommit     PreCommit    PreCommit
        │           │           │
    ┌───┴───┐   ┌───┴───┐   ┌───┴───┐
    │ RM-1  │   │ RM-2  │   │ RM-3  │
    │       │   │       │   │       │
    │执行SQL│   │执行SQL│   │执行SQL│
    │写undo │   │写undo │   │写undo │
    │写redo │   │写redo │   │写redo │
    │持锁   │   │持锁   │   │持锁   │
    │ACK    │   │ACK    │   │ACK    │
    └───┬───┘   └───┬───┘   └───┬───┘
```

**关键**：PreCommit = 2PC 的 Prepare 阶段。此时才真正执行 SQL、持锁、写日志。

**如果有 No 或超时**：

```
                Coordinator
                    │
        ┌───────────┼───────────┐
        │           │           │
     Abort        Abort        Abort
        │           │           │
    ┌───┴───┐   ┌───┴───┐   ┌───┴───┐
    │ RM-1  │   │ RM-2  │   │ RM-3  │
    │直接中断│   │直接中断│   │直接中断│
    │(无锁无日志)│ │(无锁无日志)│ │(无锁无日志)│
    └───┴───┘   └───┴───┘   └───┴───┘
```

由于 CanCommit 没持锁没写日志，中断代价极低！

#### Phase 3：DoCommit（提交阶段）

```
                Coordinator
                    │
        ┌───────────┼───────────┐
        │           │           │
     Commit       Commit       Commit
        │           │           │
    ┌───┴───┐   ┌───┴───┐   ┌───┴───┐
    │ RM-1  │   │ RM-2  │   │ RM-3  │
    │提交   │   │提交   │   │提交   │
    │释放锁 │   │释放锁 │   │释放锁 │
    └───┴───┘   └───┴───┘   └───┴───┘
```

### 4.3 3PC 如何减少阻塞

**关键改进：超时自动提交机制**

```
                    时间轴 →
RM-1     Coordinator     RM-2
 │           │            │
 │──Yes──→  │            │
 │           │──CanCommit→│
 │           │←──Yes──── │
 │           │            │
 │           │──PreCommit→│
 │←──PreCommit│←──ACK──── │
 │  [ACK]    │            │
 │           │            │ ← Coordinator 宕机！
 │           ✗            │
 │  [等待超时]              │
 │           │            │
 │  ←─────────────────── │ ← RM-2 也等待超时
 │           │            │
 │  超时 → 自动提交！      │ ← 默认提交（因为PreCommit已成功）
 │           │            │
```

**核心逻辑**：
- 如果参与者已进入 **PreCommit** 状态 → 超时后默认**提交**
- 因为 PreCommit 成功意味着所有参与者都在 CanCommit 阶段同意了，大概率应该提交
- 如果参与者只在 **CanCommit** 状态 → 超时后默认**中断**（还没持锁写日志，中断无代价）

### 4.4 3PC 的完整时序图

```
时间轴 →

RM-1          Coordinator            RM-2          RM-3
 │                │                   │              │
 │──CanCommit──→ │                   │              │
 │                │──CanCommit──────→│              │
 │                │──CanCommit──────────────────────→│
 │                │                   │              │
 │←──Yes──────── │                   │              │
 │                │←──Yes───────────│              │
 │                │←──Yes──────────────────────────│
 │                │                   │              │
 │                │ [所有Yes → PreCommit]            │
 │                │                   │              │
 │──PreCommit──→ │                   │              │
 │                │──PreCommit──────→│              │
 │                │──PreCommit──────────────────────→│
 │                │                   │              │
 │←──ACK──────── │                   │              │
 │                │←──ACK───────────│              │
 │                │←──ACK──────────────────────────│
 │                │                   │              │
 │                │ [所有ACK → DoCommit]            │
 │                │                   │              │
 │──DoCommit───→ │                   │              │
 │                │──DoCommit───────→│              │
 │                │──DoCommit──────────────────────→│
 │                │                   │              │
 │          [事务完成]                  │              │
```

### 4.5 3PC 仍然无法解决的问题

#### 网络分区下的数据不一致

```
场景：PreCommit 后网络分区

  ┌──────────────────┐     ┌──────────────────┐
  │ Partition A      │     │ Partition B      │
  │ Coordinator      │     │ RM-3             │
  │ RM-1 (precommit) │     │ (precommit)      │
  │ RM-2 (precommit) │     │                  │
  │                  │     │ 超时 → 自动提交   │
  │ Coordinator发送  │     │                  │
  │ Abort指令        │     │                  │
  │ RM-1 回滚 ✗     │     │ RM-3 提交 ✓      │
  │ RM-2 回滚 ✗     │     │                  │
  └──────────────────┘     └──────────────────┘

  → RM-1/2 回滚，RM-3 提交 → 数据不一致！
```

**结论**：3PC 的超时自动提交机制在网络分区场景下反而加剧了不一致风险。

#### 3PC 的其他问题

| 问题 | 说明 |
|------|------|
| **网络分区仍不一致** | 超时自动提交与协调者指令矛盾 |
| **轮次更多，延迟更大** | 3次网络往返 vs 2PC的2次 |
| **实际极少使用** | 工程中几乎不用3PC，理论意义大于实践 |

> **面试要点**：3PC 是理论改进，实际工程中几乎不被使用。核心原因：网络分区下超时自动提交反而加剧不一致。

---

## 五、TCC — Try‑Confirm‑Cancel

### 5.1 TCC 的设计思想

TCC（Try-Confirm-Cancel）是**业务层面的分布式事务方案**，由 Pat Helland 在 2007 年论文《Life beyond Distributed Transactions》中提出。

核心思路：**将一个跨服务事务拆分为三个业务阶段**，每个阶段由业务代码显式实现。

```
2PC/XA：数据库层面保证（依赖undo/redo log）
TCC：   业务层面保证（依赖业务Try/Confirm/Cancel实现）
```

### 5.2 三个阶段详解

#### Try — 资源预留

```
电商下单 TCC 示例：

  ┌──────────────────────────────────────────────────┐
  │ Try 阶段：冻结资源，但不真正扣减                    │
  │                                                    │
  │ 订单服务：                                         │
  │   INSERT INTO order (status='TRYING', ...)        │
  │   → 订单状态标记为 TRYING（尚未确认）              │
  │                                                    │
  │ 库存服务：                                         │
  │   UPDATE inventory                                │
  │   SET frozen = frozen + 1,                        │
  │       available = available - 1                   │
  │   WHERE sku = 'SKU001'                            │
  │   → 把1件从"可用"转移到"冻结"                      │
  │                                                    │
  │ 账户服务：                                         │
  │   UPDATE account                                  │
  │   SET frozen = frozen + 100,                      │
  │       available = available - 100                 │
  │   WHERE user_id = 'U001'                          │
  │   → 把100元从"可用余额"转移到"冻结金额"            │
  └──────────────────────────────────────────────────┘
```

**关键约束**：
- Try 必须做**资源检查与预留**，不能直接扣减
- 预留的资源要有**明确的冻结标记**（frozen 字段）
- Try 成功 = 业务具备执行 Confirm 的条件

#### Confirm — 确认提交

```
  ┌──────────────────────────────────────────────────┐
  │ Confirm 阶段：真正执行业务，消耗预留资源            │
  │                                                    │
  │ 订单服务：                                         │
  │   UPDATE order SET status='CONFIRMED'             │
  │   → 订单状态改为已确认                             │
  │                                                    │
  │ 库存服务：                                         │
  │   UPDATE inventory                                │
  │   SET frozen = frozen - 1,                        │
  │       sold = sold + 1                             │
  │   → 从"冻结"转为"已售"                            │
  │                                                    │
  │ 账户服务：                                         │
  │   UPDATE account                                  │
  │   SET frozen = frozen - 100,                      │
  │       balance = balance + 100（记账侧）           │
  │   → 从"冻结金额"转为"实际扣减"                    │
  └──────────────────────────────────────────────────┘
```

**关键约束**：
- Confirm **不允许失败**（Try 已成功 = 必须能 Confirm）
- Confirm 必须做**幂等设计**（可能被重复调用）
- Confirm 操作应该是**轻量的**（只改状态/标记，不做复杂逻辑）

#### Cancel — 取消回滚

```
  ┌──────────────────────────────────────────────────┐
  │ Cancel 阶段：释放预留资源，恢复到 Try 前状态         │
  │                                                    │
  │ 订单服务：                                         │
  │   UPDATE order SET status='CANCELLED'             │
  │   → 订单标记为已取消                               │
  │                                                    │
  │ 库存服务：                                         │
  │   UPDATE inventory                                │
  │   SET frozen = frozen - 1,                        │
  │       available = available + 1                   │
  │   → 从"冻结"退回"可用"                            │
  │                                                    │
  │ 账户服务：                                         │
  │   UPDATE account                                  │
  │   SET frozen = frozen - 100,                      │
  │       available = available + 100                 │
  │   → 从"冻结金额"退回"可用余额"                    │
  └──────────────────────────────────────────────────┘
```

**关键约束**：
- Cancel 也必须**幂等**（可能被重复调用）
- Cancel 还要处理 **空回滚**（Try 未执行但被调 Cancel）
- Cancel 要处理 **悬挂**（Cancel 先于 Try 到达）

### 5.3 TCC 的异常场景与解决方案

#### 异常1：空回滚（Try 未执行，Cancel 先到达）

```
场景：Try 请求因网络丢失，未到达参与者，但 TM 已经发起 Cancel

  Try ──────── ✗（网络丢失，RM未执行）
                    │
  Cancel ──────→ RM ← 收到 Cancel，但 Try 从未执行过！

  如果 Cancel 不做特殊处理：
    frozen -= 1 → frozen 变成负数！数据异常！

  解决方案：空回滚
    Cancel 检查：如果 Try 未执行（无冻结记录），则：
      1. 插入一条空记录，标记"已空回滚"
      2. 直接返回成功，不做实际扣减

  实现：
    Cancel 时检查是否存在 Try 记录：
    SELECT * FROM tcc_transaction WHERE xid = ? AND branch = ?
    如果不存在 → 空回滚：INSERT 记录标记已Cancel → 返回成功
```

#### 异常2：悬挂（Cancel 先于 Try 到达）

```
场景：空回滚后，Try 请求延迟到达

  Cancel ──→ RM（空回滚成功，插入标记）
                    │
  Try ──────→ RM ← Try 廞迟到达，正常执行资源冻结！

  问题：Cancel 已经释放了，Try 又冻结了 → 资源永久冻结！

  解决方案：悬挂控制
    Try 执行前检查：如果已存在空回滚记录，则拒绝执行 Try

  实现：
    Try 时检查：
    SELECT * FROM tcc_transaction WHERE xid = ? AND branch = ?
    如果已存在且状态 = 'CANCELLED' → 拒绝 Try，直接返回失败
```

#### 异常3：幂等（重复调用 Confirm/Cancel）

```
场景：网络超时导致 TM 重试

  Confirm ──→ RM（第一次，成功提交）
  Confirm ──→ RM（重试，重复到达）

  如果 Confirm 不幂等：
    frozen -= 1（第二次） → frozen 再减一次 → 数据错误！

  解决方案：幂等控制
    Confirm/Cancel 执行前检查事务状态：

    SELECT status FROM tcc_transaction WHERE xid = ? AND branch = ?
    如果 status = 'CONFIRMED' → 直接返回成功（不再执行）
    如果 status = 'CANCELLED' → 直接返回成功（不再执行）
    如果 status = 'TRYING' → 执行 Confirm 并更新状态为 CONFIRMED
```

### 5.4 TCC 完整流程图

```
              TM (事务管理器)
                 │
    ┌────────────┼────────────┐
    │            │            │
  Try-RM1    Try-RM2     Try-RM3
    │            │            │
    ├ 资源检查   ├ 资源检查   ├ 资源检查
    ├ 资源冻结   ├ 资源冻结   ├ 资源冻结
    ├ 记录事务   ├ 记录事务   ├ 记录事务
    │            │            │
  成功/失败   成功/失败   成功/失败
    │            │            │
    └────────────┼────────────┘
                 │
        ┌────────┴────────┐
        │  所有Try成功?    │
        │                  │
   Yes ─┤            No───┤
        │                  │
    ┌───┴───┐          ┌───┴───┐
    │Confirm│          │Cancel │
    │阶段   │          │阶段   │
    └───┬───┘          └───┬───┘
        │                  │
  ┌─────┼─────┐      ┌─────┼─────┐
  │     │     │      │     │     │
CF-RM1 CF-RM2 CF-RM3  CC-RM1 CC-RM2 CC-RM3
  │     │     │      │     │     │
  ├确认 ├确认 ├确认   ├释放 ├释放 ├释放
  ├幂等 ├幂等 ├幂等   ├幂等 ├幂等 ├幂等
  │     │     │      │     │     │
  └─────┼─────┘      └─────┼─────┘
        │                  │
    事务完成 ✓          事务回滚 ✗
```

### 5.5 TCC vs 2PC/XA 对比

| 维度 | 2PC/XA | TCC |
|------|--------|-----|
| **层面** | 数据库层面（底层） | 业务层面（上层） |
| **锁** | 数据库行锁/表锁（粗粒度） | 业务冻结字段（细粒度） |
| **侵入性** | 低（仅XA接口） | 高（每个服务写3个方法） |
| **性能** | 持锁时间长，并发差 | Try后可释放部分锁，并发好 |
| **一致性** | 强一致 | 最终一致（Confirm成功后） |
| **异常处理** | 阻塞等待 | 空回滚+悬挂+幂等 |
| **适用范围** | 同TM管理的DB | 跨微服务调用 |
| **通用性** | 通用（任何XA兼容DB） | 业务定制（每个业务写TCC） |

### 5.6 TCC 的优缺点

**优点**：
1. **性能好**：Try 只冻结不持锁，Confirm 快速改状态
2. **灵活**：业务自定义冻结/确认/释放逻辑
3. **跨服务**：适用于微服务架构
4. **不依赖数据库XA**：无需特殊数据库支持

**缺点**：
1. **业务侵入性极高**：每个服务需写 Try/Confirm/Cancel 三套代码
2. **开发复杂**：空回滚、悬挂、幂等三个异常场景都需要处理
3. **一致性弱于XA**：Confirm 阶段可能出现不一致（需人工补偿）
4. **资源预留成本**：需要额外的 frozen 字段/表

---

## 六、可靠消息最终一致性

### 6.1 核心思想

**不追求强一致，用消息的可靠投递来保证最终一致。**

```
本地事务 + 消息 → 只要本地事务成功，消息终会被消费 → 最终一致

关键问题：如何保证"本地事务"与"消息发送"的原子性？
```

### 6.2 方案一：本地消息表

#### 原理

```
┌─────────────────────────────────────────────────────┐
│ 本地消息表方案核心流程                                │
│                                                       │
│ 步骤1：业务操作 + 写消息表（同一本地事务）             │
│                                                       │
│   BEGIN;                                              │
│   UPDATE account SET balance = balance - 100;        │
│   INSERT INTO message_table (                         │
│     id, content, status='PENDING', create_time        │
│   );                                                  │
│   COMMIT; ← 两者在同一事务中，保证原子性               │
│                                                       │
│ 步骤2：后台线程轮询消息表                              │
│                                                       │
│   SELECT * FROM message_table WHERE status = 'PENDING'│
│   → 取出待发送消息                                    │
│                                                       │
│ 步骤3：发送到 MQ                                      │
│                                                       │
│   producer.send(message) → RocketMQ/Kafka            │
│                                                       │
│ 步骤4：发送成功 → 更新消息状态                         │
│                                                       │
│   UPDATE message_table SET status = 'SENT'            │
│   WHERE id = ?;                                       │
│                                                       │
│ 步骤5：下游消费 → 回调确认                             │
│                                                       │
│   consumer.onMessage → 执行业务 → 回ACK               │
│   → TM 收到 ACK → 更新 status = 'CONFIRMED'          │
└─────────────────────────────────────────────────────┘
```

#### 完整流程图

```
     服务A                              MQ                     服务B
       │                                │                       │
       │ BEGIN;                         │                       │
       │ 1. 业务SQL                     │                       │
       │ 2. INSERT消息表(PENDING)       │                       │
       │ COMMIT;                        │                       │
       │                                │                       │
       │ ←── 后台线程轮询 ──→           │                       │
       │    SELECT PENDING              │                       │
       │                                │                       │
       │ ──── send message ──────────→ │                       │
       │                                │ ──── push ──────────→ │
       │                                │                       │
       │ ←── send OK ────              │                       │
       │                                │                       │
       │ UPDATE status=SENT             │    消费业务 ───────── │
       │                                │                       │
       │                                │ ←── ACK ──────────── │
       │                                │                       │
       │ UPDATE status=CONFIRMED        │                       │
       │                                │                       │
```

#### 异常处理

```
异常1：消息发送失败
  → 消息状态仍是 PENDING
  → 后台线程下次轮询重新发送
  → 直到发送成功或达到最大重试次数

异常2：消息已发送但ACK未收到
  → 消息状态是 SENT（非 CONFIRMED）
  → 后台线程对 SENT 消息定时重发
  → 下游需保证幂等消费

异常3：重复消费
  → 下游服务做幂等处理（消费前检查业务唯一ID）
```

#### 本地消息表的优缺点

| 优点 | 缺点 |
|------|------|
| 实现简单，不依赖特殊MQ | 与业务数据库耦合（消息表在业务DB中） |
| 本地事务保证原子性 | 后台线程轮询有延迟（秒级~分钟级） |
| 可靠性高，不丢消息 | 消息表膨胀，需定期清理 |
| 适用于任何MQ | 每个服务都要建消息表 |

### 6.3 方案二：RocketMQ 事务消息

#### 原理

RocketMQ 提供了**半消息（Half Message）机制**，让"本地事务"与"消息发送"的原子性由 MQ 自身保证。

```
┌─────────────────────────────────────────────────────┐
│ RocketMQ 事务消息核心流程                              │
│                                                       │
│ Step 1：发送半消息（对消费者不可见）                    │
│                                                       │
│   producer.sendHalfMessage(topic, message)            │
│   → 消息存入 Broker 的 HALF_TOPIC                     │
│   → 消费者暂时看不到这条消息                           │
│                                                       │
│ Step 2：执行本地事务                                   │
│                                                       │
│   executeLocalTransaction() {                         │
│     BEGIN;                                            │
│     UPDATE account SET balance -= 100;               │
│     COMMIT;                                           │
│     return COMMIT / ROLLBACK / UNKNOWN;               │
│   }                                                   │
│                                                       │
│ Step 3：根据本地事务结果提交或回滚                      │
│                                                       │
│   COMMIT → Broker 将半消息移到真实 Topic → 消费者可见 │
│   ROLLBACK → Broker 删除半消息 → 消费者永远看不到     │
│   UNKNOWN → Broker 等待回查                           │
│                                                       │
│ Step 4：回查机制（UNKNOWN 时触发）                     │
│                                                       │
│   Broker 定时扫描未决的半消息                          │
│   → 向 Producer 发起回查：checkLocalTransaction()     │
│   → Producer 查本地DB判断事务状态                      │
│   → 返回 COMMIT/ROLLBACK                              │
└─────────────────────────────────────────────────────┘
```

#### 半消息的底层存储原理

```
RocketMQ Broker 内部：

半消息发送时：
  ┌───────────────────────────────────────┐
  │ CommitLog（物理存储）                   │
  │                                       │
  │ [half_msg_1] [normal_msg] [half_msg_2] │
  │                                       │
  │ 半消息与普通消息混存，但 Topic 不同     │
  │ 半消息 Topic = RMQ_SYS_TRANS_HALF_TOPIC│
  │ 普通消息 Topic = 用户指定的 Topic      │
  └───────────────────────────────────────┘

半消息提交（COMMIT）时：
  ┌───────────────────────────────────────┐
  │ 1. 从 CommitLog 读出半消息             │
  │ 2. 修改 Topic/QueueId 为真实目标       │
  │ 3. 写入 CommitLog 作为新消息           │
  │ 4. 写入 OP_MESSAGE（标记已提交）       │
  │ 5. 消费者拉取时可见                    │
  └───────────────────────────────────────┘

半消息回滚（ROLLBACK）时：
  ┌───────────────────────────────────────┐
  │ 1. 写入 OP_MESSAGE（标记已回滚）       │
  │ 2. 不移到真实 Topic                    │
  │ 3. 半消息对消费者永远不可见            │
  └───────────────────────────────────────┘

回查机制：
  ┌───────────────────────────────────────┐
  │ TransactionalMessageCheckService       │
  │                                       │
  │ 定时（默认60秒）扫描：                  │
  │ 1. 从 HALF_TOPIC 读出半消息            │
  │ 2. 检查是否有对应的 OP_MESSAGE          │
  │ 3. 无OP → 说明Producer未二次确认       │
  │ 4. 向Producer发起回查请求              │
  │ 5. 最大回查次数：15次（默认）           │
  │ 6. 超过次数 → 默认回滚                 │
  └───────────────────────────────────────┘
```

#### 事务消息源码关键类

```java
// RocketMQ 事务消息核心类（开源版）

// 1. 事务消息发送入口
public class TransactionMQProducer extends DefaultMQProducer {
    private TransactionCheckListener checkListener;  // 回查回调
    private int checkThreadPoolMinSize = 1;
    private int checkThreadPoolMaxSize = 1;

    // 发送事务消息
    public TransactionSendResult sendMessageInTransaction(
        Message msg, LocalTransactionExecuter executer, Object arg) {

        // Step 1: 发送半消息
        SendResult sendResult = this.sendHalfMessage(msg);

        // Step 2: 执行本地事务
        LocalTransactionState localState = executer.executeLocalTransactionBranch(msg, arg);

        // Step 3: 根据结果二次确认
        switch (localState) {
            case COMMIT_MESSAGE:
                this.endTransaction(sendResult, localState);
                break;
            case ROLLBACK_MESSAGE:
                this.endTransaction(sendResult, localState);
                break;
            case UNKNOW:
                // 不确认，等回查
                break;
        }
    }
}

// 2. Broker端半消息处理
class TransactionalMessageService {
    // 保存半消息（改Topic为RMQ_SYS_TRANS_HALF_TOPIC）
    PutMessageResult prepareMessage(MessageExt messageInner) {
        // 修改原始Topic保存到属性
        messageInner.putProperty(MessageConst.PROPERTY_REAL_TOPIC, messageInner.getTopic());
        messageInner.putProperty(MessageConst.PROPERTY_REAL_QUEUE_ID,
            String.valueOf(messageInner.getQueueId()));
        // 替换Topic
        messageInner.setTopic(TransactionalMessageUtil.buildHalfTopic());
        messageInner.setQueueId(0);
        // 存入CommitLog
        return this.brokerController.getMessageStore().putMessage(messageInner);
    }

    // 提交半消息（移到真实Topic）
    ResolveResultType commitMessage(String offset) {
        // 1. 读出半消息
        MessageExt halfMsg = this.brokerController.getMessageStore().lookMessageByOffset(offset);
        // 2. 恢复原始Topic
        String realTopic = halfMsg.getProperty(MessageConst.PROPERTY_REAL_TOPIC);
        int realQueueId = Integer.parseInt(
            halfMsg.getProperty(MessageConst.PROPERTY_REAL_QUEUE_ID));
        halfMsg.setTopic(realTopic);
        halfMsg.setQueueId(realQueueId);
        // 3. 作为新消息写入CommitLog
        this.brokerController.getMessageStore().putMessage(halfMsg);
        // 4. 写OP消息标记已提交
        this.brokerController.getMessageStore().putMessage(buildOpMessage(offset, COMMIT));
    }
}

// 3. 回查服务
class TransactionalMessageCheckService {
    // 定时扫描未决半消息
    void checkMessage() {
        // 1. 遍历 HALF_TOPIC 下的半消息
        // 2. 检查每个半消息是否有对应的OP消息
        // 3. 无OP且超时 → 向Producer发起回查
        // 4. 回查结果 → COMMIT/ROLLBACK
        // 5. 超过最大回查次数(15) → 强制ROLLBACK
    }
}
```

#### 事务消息的完整流程图

```
   Producer              Broker                Consumer
     │                    │                       │
     │──sendHalfMessage──→│                       │
     │                    │                       │
     │                    │ 存入HALF_TOPIC         │
     │                    │ (消费者不可见)          │
     │                    │                       │
     │←──HalfMsg OK────── │                       │
     │                    │                       │
     │ 执行本地事务       │                       │
     │ BEGIN→COMMIT       │                       │
     │                    │                       │
     │──COMMIT/ROLLBACK──→│                       │
     │                    │                       │
     │   [COMMIT时]       │                       │
     │                    │ 移到真实Topic          │
     │                    │                       │
     │                    │──push message────────→ │
     │                    │                       │ 消费业务
     │                    │←──ACK─────────────── │
     │                    │                       │
     │                    │                       │

     │   [UNKNOWN时]      │                       │
     │                    │ 定时回查               │
     │──checkLocalTx──→  │                       │
     │  查本地DB          │                       │
     │←──COMMIT/ROLLBACK─ │                       │
     │                    │                       │
```

### 6.4 方案三：最大努力通知

#### 原理

```
最大努力通知 = "我尽力通知你，但你不收到我也没办法"

核心流程：
  ┌──────────────────────────────────┐
  │ 通知方：                          │
  │ 1. 执行本地事务                   │
  │ 2. 发送通知（HTTP/MQ/邮件）       │
  │ 3. 按递增间隔重试（1s,5s,30s...） │
  │ 4. 达到最大次数后停止              │
  │                                   │
  │ 被通知方：                        │
  │ 1. 收到通知执行业务               │
  │ 2. 回ACK                         │
  │ 3. 如果未收到通知 → 主动查询通知方 │
  └──────────────────────────────────┘
```

**与可靠消息的区别**：
- 可靠消息 = 保证消息必达 + 消费者必消费
- 最大努力通知 = 尽力通知 + 消费者可主动查询

**适用场景**：跨企业/跨平台的弱一致性场景（支付结果通知、银行对账）

#### 典型实现：支付宝支付结果通知

```
支付流程：
  用户 → 商户下单 → 支付宝支付 → 支付成功

支付宝通知商户：
  1. 支付宝内部事务完成（订单状态=PAID）
  2. HTTP POST 通知商户回调URL
  3. 商户返回 "success" → 停止通知
  4. 商户未返回 → 按间隔重试：
     第1次: 立即
     第2次: 15s后
     第3次: 30s后
     第4次: 3min后
     第5次: 10min后
     第6次: 30min后
     ...最多通知8次
  5. 8次失败 → 支付宝不再主动通知

商户主动查询：
  商户可调用支付宝查询API：alipay.trade.query
  → 主动获取支付结果，补偿被动通知的缺失
```

### 6.5 三种消息方案对比

| 维度 | 本地消息表 | RocketMQ事务消息 | 最大努力通知 |
|------|-----------|-----------------|-------------|
| **一致性** | 最终一致 | 最终一致 | 最终一致（更弱） |
| **实现复杂度** | 低 | 中 | 低 |
| **MQ依赖** | 无（任何MQ） | 仅RocketMQ | 无 |
| **业务侵入** | 低（加消息表） | 低（Producer回调） | 低 |
| **延迟** | 秒级~分钟级 | 毫秒级~秒级 | 分钟级 |
| **可靠性** | 高 | 高 | 中 |
| **适用场景** | 内部微服务 | 内部微服务 | 跨企业通知 |
| **主动查询** | 不支持 | 不支持 | 支持 |

---

## 七、Seata — 阿里分布式事务框架

### 7.1 Seata 概述

Seata（Simple Extensible Autonomous Transaction Architecture）是阿里开源的分布式事务框架，前身是 Fescar。

**设计理念**：把 2PC/XA 的全局协调思想，**用无锁/低侵入的方式实现**。

### 7.2 Seata 架构：三大角色

```
                ┌─────────────────────────────────────┐
                │           TC (Transaction Coordinator)│
                │           事务协调者（独立服务）        │
                │                                       │
                │  · 维护全局事务状态                     │
                │  · 驱动全局提交或回滚                   │
                │  · 持久化事务日志                       │
                └───────────┬───────────────┬───────────┘
                            │               │
                ┌───────────┴───┐       ┌───┴───────────┐
                │   TM          │       │   RM           │
                │ Transaction   │       │  Resource      │
                │ Manager       │       │  Manager       │
                │               │       │               │
                │ · 开启全局事务 │       │ · 分支事务注册 │
                │ · 决策提交/回滚│       │ · 执行本地SQL │
                │ · 事务发起方   │       │ · 上报分支状态 │
                │               │       │ · 提交/回滚   │
                └───────────────┘       └───────────────┘
```

| 角色 | 全称 | 说明 | 部署形态 |
|------|------|------|---------|
| **TC** | Transaction Coordinator | 全局事务协调者 | 独立Server（seata-server） |
| **TM** | Transaction Manager | 事务管理器（发起方） | 嵌入业务服务中 |
| **RM** | Resource Manager | 资源管理器（参与方） | 嵌入业务服务中 |

### 7.3 Seata 四种事务模式

| 模式 | 一致性 | 侵入性 | 性能 | 适用场景 |
|------|--------|--------|------|---------|
| **AT** | 最终一致 | 低（仅加undo_log表） | 高 | 大多数业务 |
| **TCC** | 最终一致 | 高（写3个方法） | 高 | 资源预留型业务 |
| **Saga** | 最终一致 | 中（写正向+补偿） | 最高 | 长流程编排 |
| **XA** | 强一致 | 低（依赖XA DB） | 低 | 强一致要求 |

### 7.4 AT 模式 — Seata 最核心的模式

#### AT 模式核心原理

```
AT = Automatic Transaction（自动事务）
核心思想：自动拦截SQL，自动生成回滚日志，自动提交/回滚

      ┌──────────────────────────────────────────────────┐
      │  AT 模式的工作流程                                 │
      │                                                    │
      │  Phase 1（业务SQL + undo log）：                    │
      │    1. 拦截业务SQL                                   │
      │    2. 查询修改前的数据（before-image）              │
      │    3. 执行业务SQL                                    │
      │    4. 查询修改后的数据（after-image）               │
      │    5. 生成 undo_log 记录（before + after + branchId）│
      │    6. 保存 undo_log 到本地 undo_log 表             │
      │    7. 向 TC 注册分支事务，上报 before-image         │
      │    8. 提交本地事务（业务SQL + undo_log 同时提交）    │
      │    9. 释放本地锁（仅本地DB锁）                       │
      │                                                    │
      │  Phase 2（全局决策）：                               │
      │    TC 收到所有分支的状态 → 决定全局提交或回滚        │
      │                                                    │
      │    全局提交 → 删除 undo_log（异步，一阶段已提交）    │
      │    全局回滚 → 读 undo_log 回滚（反向补偿）          │
      └──────────────────────────────────────────────────┘
```

#### AT 模式的关键：一阶段本地提交

```
与 2PC/XA 的根本区别：

  2PC/XA:
    Phase 1: 执行SQL + 持锁 + 不提交
    Phase 2: 提交或回滚 + 释放锁

  Seata AT:
    Phase 1: 执行SQL + 写undo_log + 本地提交 + 释放本地锁
    Phase 2: 提交 → 删undo_log / 回滚 → 读undo_log补偿

  关键优势：
    一阶段就提交 → 不持锁 → 其他事务不阻塞！
    如果需要回滚 → 用 undo_log 做反向补偿
```

#### undo_log 表结构

```sql
-- Seata AT 模式的 undo_log 表（每个参与DB都需要）
CREATE TABLE undo_log (
    id            BIGINT PRIMARY KEY AUTO_INCREMENT,
    branch_id     BIGINT NOT NULL,       -- 分支事务ID
    xid           VARCHAR(100) NOT NULL, -- 全局事务ID
    context       VARCHAR(128) NOT NULL, -- 上下文（序列化方式等）
    rollback_info LONGBLOB NOT NULL,     -- 回滚数据（before+after image）
    log_status    INT NOT NULL,          -- 状态（1=正常,2=已回滚）
    log_created   DATETIME NOT NULL,
    log_modified  DATETIME NOT NULL,
    UNIQUE KEY ux_undo_log (xid, branch_id)
);
```

#### undo_log 内容详解

```json
// rollback_info 存储的 JSON 结构
{
    "branchId": 2001,
    "xid": "192.168.1.1:8091:1234567890",
    "tableName": "account",
    "sqlType": "UPDATE",

    // 修改前的数据（before-image）
    "beforeImage": {
        "rows": [
            {
                "fields": [
                    {"name": "id", "type": 4, "value": 1},
                    {"name": "balance", "type": 12, "value": 500},
                    {"name": "frozen", "type": 12, "value": 0}
                ]
            }
        ]
    },

    // 修改后的数据（after-image）
    "afterImage": {
        "rows": [
            {
                "fields": [
                    {"name": "id", "type": 4, "value": 1},
                    {"name": "balance", "type": 12, "value": 400},
                    {"name": "frozen", "type": 12, "value": 100}
                ]
            }
        ]
    }
}
```

#### AT 模式全局锁机制

```
问题：一阶段本地提交了，其他事务可能修改同一行数据！
     如果后续需要回滚，undo_log 的 before-image 可能已经过期！

解决：Seata 的全局锁

  ┌──────────────────────────────────────────────────┐
  │ 全局锁机制                                        │
  │                                                    │
  │ Phase 1 时：                                       │
  │   RM 向 TC 注册分支时，上报 before-image           │
  │   TC 在自己的 lock_table 中记录：                   │
  │     xid=123, table=account, pk=1 → 被全局事务123锁 │
  │                                                    │
  │ 本地事务提交后，TC 检查：                           │
  │   如果另一全局事务想修改同一行 → TC 拒绝 → 等待     │
  │                                                    │
  │ 全局提交后：                                       │
  │   TC 释放全局锁 → 其他事务可修改                    │
  │                                                    │
  │ 全局回滚时：                                       │
  │   RM 读 undo_log → 校验 after-image               │
  │   如果当前数据 ≠ after-image → 说明被其他事务改了  │
  │   → 报告脏写异常 → 需人工介入                      │
  └──────────────────────────────────────────────────┘
```

#### 全局锁的实现（TC 端 lock_manager）

```java
// Seata TC 端的锁管理器核心逻辑（简化版）

public class DefaultLockManager implements LockManager {

    // lock_table 结构
    // key: tableName:pkValue → value: xid
    private ConcurrentHashMap<String, String> lockTable = new ConcurrentHashMap<>();

    // 申请全局锁（Phase 1 注册分支时）
    public boolean acquireLock(String xid, List<RowLock> rowLocks) {
        for (RowLock lock : rowLocks) {
            String lockKey = lock.getTable() + ":" + lock.getPk();
            String existingXid = lockTable.putIfAbsent(lockKey, xid);
            if (existingXid != null && !existingXid.equals(xid)) {
                // 锁已被其他全局事务持有 → 申请失败
                releaseLock(xid, rowLocks); // 释放已获取的锁
                return false;
            }
        }
        return true;
    }

    // 释放全局锁（全局提交/回滚后）
    public boolean releaseLock(String xid, List<RowLock> rowLocks) {
        for (RowLock lock : rowLocks) {
            String lockKey = lock.getTable() + ":" + lock.getPk();
            lockTable.remove(lockKey, xid); // 仅移除匹配的xid
        }
        return true;
    }

    // 检查是否全局锁已释放（本地事务提交后等待）
    public boolean isLockable(String xid, String lockKey) {
        String existingXid = lockTable.get(lockKey);
        return existingXid == null || existingXid.equals(xid);
    }
}
```

#### AT 模式完整流程时序图

```
   TM                TC                RM-A             RM-B
    │                 │                  │                │
    │──@GlobalTransactional──→           │                │
    │                 │                  │                │
    │──begin(xid)───→│                  │                │
    │←──xid───────── │                  │                │
    │                 │                  │                │
    │──执行业务SQL──→│                  │                │
    │                 │──branchRegister──→                │
    │                 │←──branchId────── │                │
    │                 │                  │                │
    │                 │    [RM-A Phase 1]│                │
    │                 │                  │──拦截SQL       │
    │                 │                  │──查beforeImage │
    │                 │                  │──执行SQL       │
    │                 │                  │──查afterImage  │
    │                 │                  │──写undo_log    │
    │                 │                  │──本地提交      │
    │                 │                  │──释放本地锁    │
    │                 │←──branchStatus── │                │
    │                 │                  │                │
    │──调用服务B───→ │                  │                │
    │                 │──branchRegister──────────────────→│
    │                 │←──branchId───────────────────────│
    │                 │                  │                │
    │                 │    [RM-B Phase 1]│                │
    │                 │                  │                │──拦截SQL
    │                 │                  │                │──查beforeImage
    │                 │                  │                │──执行SQL
    │                 │                  │                │──查afterImage
    │                 │                  │                │──写undo_log
    │                 │                  │                │──本地提交
    │                 │                  │                │──释放本地锁
    │                 │←──branchStatus───────────────────│
    │                 │                  │                │
    │──commit/rollback──→│               │                │
    │                 │                  │                │

  [全局提交时]:
    │                 │──commit(xid)───→│                │
    │                 │←──committed──── │                │
    │                 │──commit(xid)──────────────────→ │
    │                 │←──committed──────────────────── │
    │                 │                  │                │
    │                 │    RM: 删除undo_log（异步）       │
    │                 │    TC: 释放全局锁                 │

  [全局回滚时]:
    │                 │──rollback(xid)──→│                │
    │                 │                  │──读undo_log    │
    │                 │                  │──校验afterImage│
    │                 │                  │──反向补偿      │
    │                 │                  │──删除undo_log  │
    │                 │←──rolledback──── │                │
    │                 │──rollback(xid)──────────────────→│
    │                 │                  │                │──读undo_log
    │                 │                  │                │──反向补偿
    │                 │                  │                │──删除undo_log
    │                 │←──rolledback──────────────────── │
    │                 │    TC: 释放全局锁                 │
```

#### AT 模式的脏写问题与防御

```
脏写场景：
  时间轴 →

  全局事务T1:
    Phase1: 修改 account(id=1, balance: 500→400)
    本地提交 → balance=400

  全局事务T2:
    Phase1: 修改 account(id=1, balance: 400→300)
    本地提交 → balance=300
    全局提交 → balance=300 ✓

  全局事务T1:
    全局回滚 → 读undo_log → before-image=500 → 尝试恢复到500
    但当前 balance=300 ≠ after-image(400) → 脏写！

防御机制：
  1. 全局锁：T2 的 Phase1 试图获取 account(id=1) 的全局锁
     → TC 发现 T1 已持有 → T2 等待或获取失败

  2. 校验 after-image：
     回滚时校验当前数据是否等于 after-image
     如果不等 → 报告脏写 → 人工介入

  3. 实际锁等待机制：
     RM-A 本地提交后，会等待 TC 确认全局锁释放才返回
     → 保证 Phase1 结束后其他事务不能修改同一行
```

### 7.5 TCC 模式

#### Seata TCC 与普通 TCC 的关系

Seata TCC 模式就是标准 TCC 方案，由业务方实现 Try/Confirm/Cancel 三个接口。

```java
// Seata TCC 模式接口定义
@LocalTCC
public interface AccountTccService {

    // Try: 资源预留
    @TwoPhaseBusinessAction(
        name = "accountTcc",
        commitMethod = "confirm",
        rollbackMethod = "cancel",
        useTCCFence = true  // 开启防悬挂/空回滚
    )
    boolean prepare(BusinessActionContext context,
                    @BusinessActionContextParameter(paramName = "userId") String userId,
                    @BusinessActionContextParameter(paramName = "amount") BigDecimal amount);

    // Confirm: 确认提交
    boolean confirm(BusinessActionContext context);

    // Cancel: 取消回滚
    boolean cancel(BusinessActionContext context);
}
```

#### Seata TCC 的防悬挂与空回滚

```
Seata 通过 TCC Fence 机制解决空回滚和悬挂问题：

tcc_fence_log 表结构：
┌──────────────────────────────────────────────────┐
│ CREATE TABLE tcc_fence_log (                      │
│   xid         VARCHAR(128) NOT NULL,              │
│   branch_id   BIGINT NOT NULL,                    │
│   action_name VARCHAR(64) NOT NULL,               │
│   status      TINYINT NOT NULL,                   │
│   -- status: 1=tried, 2=committed, 3=rollbacked   │
│   create_time DATETIME,                           │
│   PRIMARY KEY (xid, branch_id)                    │
│ );                                                │
└──────────────────────────────────────────────────┘

Try 时：
  INSERT INTO tcc_fence_log (xid, branch_id, status=1)
  → 如果 INSERT 失败（唯一键冲突）→ 说明已存在记录 → 悬挂 → 拒绝执行

Cancel 时：
  检查 tcc_fence_log 是否存在 Try 记录：
  SELECT status FROM tcc_fence_log WHERE xid=? AND branch_id=?
  → 不存在 → 空回滚 → INSERT status=3 → 返回成功
  → 存在且 status=1 → 正常回滚 → UPDATE status=3

Confirm 时：
  UPDATE tcc_fence_log SET status=2 WHERE xid=? AND branch_id=?
  → 如果 status≠1 → 说明已被Cancel → 直接返回失败
```

### 7.6 Saga 模式

#### Saga 原理

Saga 最早由 Hector Garcia-Molina 和 Kenneth Salem 在 1987 年论文《Sagas》中提出。

核心思想：**将长事务拆分为多个短事务，每个短事务有对应的补偿事务**。

```
正向流程：    T1 → T2 → T3 → T4 → ... → Tn  (全部成功)

补偿流程（T3失败）：    T1⁻¹ → T2⁻¹  (反向补偿1和2)
                         ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ← ←
```

#### Seata Saga 状态机实现

```json
// Seata Saga 状态机定义（JSON格式）
{
    "Name": "purchaseOrder",
    "Comment": "采购订单Saga",
    "StartState": "CreateOrder",
    "States": {
        "CreateOrder": {
            "Type": "ServiceTask",
            "ServiceName": "orderService",
            "ServiceMethod": "createOrder",
            "CompensateState": "CancelOrder",
            "Next": "DeductInventory",
            "Input": ["$.orderData"],
            "Output": {
                "orderId": "$.orderId"
            }
        },
        "CancelOrder": {
            "Type": "ServiceTask",
            "ServiceName": "orderService",
            "ServiceMethod": "cancelOrder",
            "Input": ["$.orderId"]
        },
        "DeductInventory": {
            "Type": "ServiceTask",
            "ServiceName": "inventoryService",
            "ServiceMethod": "deductInventory",
            "CompensateState": "RestoreInventory",
            "Next": "DeductBalance",
            "Input": ["$.orderData.skuId", "$.orderData.quantity"],
            "Output": {
                "deductResult": "$.deductResult"
            }
        },
        "RestoreInventory": {
            "Type": "ServiceTask",
            "ServiceName": "inventoryService",
            "ServiceMethod": "restoreInventory",
            "Input": ["$.orderData.skuId", "$.orderData.quantity"]
        },
        "DeductBalance": {
            "Type": "ServiceTask",
            "ServiceName": "accountService",
            "ServiceMethod": "deductBalance",
            "CompensateState": "RestoreBalance",
            "Next": "Succeed",
            "Input": ["$.orderData.userId", "$.orderData.amount"]
        },
        "RestoreBalance": {
            "Type": "ServiceTask",
            "ServiceName": "accountService",
            "ServiceMethod": "restoreBalance",
            "Input": ["$.orderData.userId", "$.orderData.amount"]
        },
        "Succeed": {
            "Type": "Succeed"
        }
    }
}
```

#### Saga 执行流程图

```
正向执行（全部成功）：
  CreateOrder ──→ DeductInventory ──→ DeductBalance ──→ Succeed ✓

反向补偿（DeductBalance失败）：
  CreateOrder ──→ DeductInventory ──→ DeductBalance ✗
                                    │
  CancelOrder ←── RestoreInventory ←─┘  (补偿反向执行)
```

#### Saga vs TCC vs 2PC

| 维度 | 2PC/XA | TCC | Saga |
|------|--------|-----|------|
| **一致性** | 强一致 | 最终一致 | 最终一致 |
| **隔离性** | 有隔离（锁） | 有隔离（冻结） | 无隔离（可能脏读） |
| **侵入性** | 低 | 高（3个方法） | 中（正向+补偿） |
| **性能** | 低（锁） | 中 | 高（无锁） |
| **适用场景** | 短事务 | 资源预留 | 长流程编排 |
| **回滚** | 同步回滚 | 同步补偿 | 反向补偿链 |
| **业务异常** | 全部回滚 | 全部补偿 | 从失败点反向补偿 |

### 7.7 XA 模式

```
Seata XA 模式 = 标准 2PC/XA 协议的包装

  ┌──────────────────────────────────────────────────┐
  │ Seata XA 模式流程                                 │
  │                                                    │
  │ Phase 1:                                           │
  │   RM 使用 XA 协议与本地DB交互                       │
  │   xa.start → 执行SQL → xa.end → xa.prepare        │
  │   向 TC 注册分支                                   │
  │                                                    │
  │ Phase 2:                                           │
  │   全局提交 → xa.commit                              │
  │   全局回滚 → xa.rollback                           │
  │                                                    │
  │ 与标准 XA 的区别：                                 │
  │   Seata XA 由 TC 统一协调，而非独立的 TM            │
  │   Seata 提供了自动 XA 代理（DataSourceProxy）       │
  │   应用代码无感知，只需标注 @GlobalTransactional     │
  └──────────────────────────────────────────────────┘
```

```java
// Seata XA DataSourceProxy 自动拦截
public class DataSourceProxyXA extends AbstractDataSourceProxy {

    // 获取 XA 连接
    public Connection getConnection() throws SQLException {
        XAConnection xaConnection = xaDataSource.getXAConnection();
        Connection physicalConn = xaConnection.getConnection();
        // 返回代理连接，自动拦截 SQL 转为 XA 操作
        return new ConnectionProxyXA(physicalConn, xaConnection, this);
    }
}

// ConnectionProxyXA 自动拦截
public class ConnectionProxyXA extends AbstractConnectionProxy {

    public void commit() throws SQLException {
        if (currentXid != null) {
            // 在全局事务中 → xa.prepare（Phase 1）
            xaResource.prepare(currentXid);
            // 等待 TC 决策后再 xa.commit 或 xa.rollback（Phase 2）
        } else {
            // 非全局事务 → 直接提交
            targetConnection.commit();
        }
    }
}
```

### 7.8 Seata 源码核心类梳理

```
Seata 模块结构：
┌──────────────────────────────────────────────────┐
│ seata-server（TC 端）                              │
│ ├── coordinator/                                  │
│ │   ├── DefaultCoordinator.java  ← 全局事务协调   │
│ │   ├── DefaultCore.java         ← 核心处理逻辑   │
│ │   └── GlobalStatus.java        ← 全局事务状态   │
│ ├── lock/                                         │
│ │   ├── DefaultLockManager.java  ← 全局锁管理     │
│ │   └── LockStore.java           ← 锁存储         │
│ ├── session/                                      │
│ │   ├── SessionManager.java      ← 会话管理       │
│ │   ├── GlobalSession.java       ← 全局会话       │
│ │   └── BranchSession.java       ← 分支会话       │
│ └──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│ seata-tm（TM 端，嵌入业务服务）                     │
│ ├── DefaultTransactionManager.java ← TM 实现      │
│ ├── GlobalTransactionScanner.java ← 扫描注解      │
│ ├── TransactionalTemplate.java    ← 事务模板      │
│ └──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│ seata-rm（RM 端，嵌入业务服务）                     │
│ ├── rm-datasource/                                │
│ │   ├── DataSourceProxy.java      ← AT数据源代理  │
│ │   ├── ConnectionProxy.java      ← AT连接代理    │
│ │   ├── ExecuteTemplate.java      ← SQL拦截执行   │
│ │   ├── UndoLogManager.java       ← undo_log管理  │
│ │   └── UndoLogParser.java        ← undo日志解析  │
│ ├── rm-tcc/                                       │
│ │   ├── TCCResourceManager.java   ← TCC资源管理   │
│ │   ├── TCCFenceHandler.java      ← 防悬挂处理    │
│ └──────────────────────────────────────────────────┘
```

#### TM 核心流程：@GlobalTransactional 注解拦截

```java
// GlobalTransactionScanner 扫描 @GlobalTransactional 注解
// 并创建 AOP 代理

public class GlobalTransactionScanner extends AbstractAutoProxyCreator {

    protected Object wrapIfNecessary(Object bean, String beanName, Object[] cacheKey) {
        // 1. 检查方法上是否有 @GlobalTransactional
        Method[] methods = bean.getClass().getMethods();
        for (Method method : methods) {
            if (method.getAnnotation(GlobalTransactional.class) != null) {
                // 2. 创建代理
                return createProxy(bean, beanName, cacheKey,
                    new GlobalTransactionalInterceptor());
            }
        }
        return bean;
    }
}

// GlobalTransactionalInterceptor 拦截事务方法
public class GlobalTransactionalInterceptor implements MethodInterceptor {

    public Object invoke(MethodInvocation methodInvocation) throws Throwable {
        GlobalTransactional annotation = methodInvocation.getMethod()
            .getAnnotation(GlobalTransactional.class);

        // 获取超时、回滚异常等配置
        int timeout = annotation.timeout();
        Class<? extends Exception>[] rollbackFor = annotation.rollbackForClassName();

        // 使用 TransactionalTemplate 执行
        return transactionalTemplate.execute(
            new TransactionalExecutor() {
                public Object execute() throws Throwable {
                    return methodInvocation.proceed(); // 执行业务方法
                }
            },
            timeout, rollbackFor
        );
    }
}
```

#### TransactionalTemplate — 事务执行模板

```java
// Seata 事务执行的核心模板方法（简化版）
public class TransactionalTemplate {

    public Object execute(TransactionalExecutor executor, int timeout,
                          Class<? extends Exception>[] rollbackFor) throws Throwable {

        // 1. 开启全局事务
        GlobalTransaction tx = RootContext.getCurrent();
        if (tx == null) {
            tx = transactionManager.begin(timeout);
            RootContext.bind(tx.getXid()); // 绑定xid到当前线程
        }

        try {
            // 2. 执行业务
            Object result = executor.execute();

            // 3. 全局提交
            transactionManager.commit(tx.getXid());
            return result;

        } catch (Exception ex) {
            // 4. 判断是否需要回滚
            if (shouldRollback(ex, rollbackFor)) {
                transactionManager.rollback(tx.getXid());
            }
            throw ex;

        } finally {
            // 5. 清理上下文
            RootContext.unbind();
        }
    }
}
```

#### RM AT 模式核心：SQL 拦截与 undo_log 生成

```java
// ExecuteTemplate — Seata AT 模式 SQL 执行拦截器
public class ExecuteTemplate {

    public static <T> T execute(SQLRecognizer sqlRecognizer,
                                StatementProxy statementProxy,
                                StatementCallback<T> callback) {

        // 判断是否在全局事务中
        String xid = RootContext.getXID();
        if (xid == null) {
            // 非全局事务 → 直接执行
            return callback.execute(statementProxy.getTargetStatement());
        }

        // 全局事务中 → 拦截处理
        switch (sqlRecognizer.getSQLType()) {
            case INSERT:
                return ExecuteTemplate.executeInsert(xid, sqlRecognizer, statementProxy, callback);
            case UPDATE:
                return ExecuteTemplate.executeUpdate(xid, sqlRecognizer, statementProxy, callback);
            case DELETE:
                return ExecuteTemplate.executeDelete(xid, sqlRecognizer, statementProxy, callback);
            default:
                return callback.execute(statementProxy.getTargetStatement());
        }
    }
}

// Update 执行流程（最核心）
public static <T> T executeUpdate(String xid, SQLRecognizer sqlRecognizer,
                                   StatementProxy statementProxy,
                                   StatementCallback<T> callback) {

    // Step 1: 查询 before-image（修改前的数据）
    TableRecords beforeImage = beforeImage(sqlRecognizer, statementProxy);

    // Step 2: 执行业务 UPDATE
    T result = callback.execute(statementProxy.getTargetStatement());

    // Step 3: 查询 after-image（修改后的数据）
    TableRecords afterImage = afterImage(sqlRecognizer, statementProxy);

    // Step 4: 生成 undo_log
    SQLUndoLog undoLog = new SQLUndoLog();
    undoLog.setSqlType(SQLType.UPDATE);
    undoLog.setTableName(sqlRecognizer.getTableName());
    undoLog.setBeforeImage(beforeImage);
    undoLog.setAfterImage(afterImage);

    // Step 5: 写入 undo_log 表（与业务SQL在同一本地事务中）
    UndoLogManager.flushUndoLog(xid, branchId, undoLog, statementProxy.getConnectionProxy());

    // Step 6: 向 TC 注册分支
    long branchId = DefaultResourceManager.get().branchRegister(
        BranchType.AT, resourceId, xid, null, lockKeys);

    return result;
}
```

#### before-image 和 after-image 的查询原理

```java
// before-image 查询：根据 UPDATE 的 WHERE 条件，查出修改前的行
public TableRecords beforeImage(SQLRecognizer recognizer, StatementProxy stmtProxy) {

    // 从 UPDATE SQL 中提取 WHERE 条件
    // 例如: UPDATE account SET balance=400 WHERE id=1
    // → WHERE 条件 = "id = 1"

    // 构建 SELECT 语句查询修改前的数据
    String selectSQL = buildSelectSQL(recognizer.getTableName(),
                                      recognizer.getWhereCondition());
    // 例如: SELECT id, balance, frozen FROM account WHERE id = 1

    // 执行 SELECT（在 UPDATE 执行之前）
    ResultSet rs = stmtProxy.getTargetStatement().executeQuery(selectSQL);
    return TableRecords.buildRecords(tableName, rs);
    // 结果: {id=1, balance=500, frozen=0}
}

// after-image 查询：UPDATE 执行后，查出修改后的行
public TableRecords afterImage(SQLRecognizer recognizer, StatementProxy stmtProxy) {

    // 用 before-image 的主键值查询
    // 构建: SELECT id, balance, frozen FROM account WHERE id = 1
    String selectSQL = buildSelectSQLByPk(recognizer.getTableName(),
                                           beforeImage.pkValues());

    ResultSet rs = stmtProxy.getTargetStatement().executeQuery(selectSQL);
    return TableRecords.buildRecords(tableName, rs);
    // 结果: {id=1, balance=400, frozen=100}
}
```

#### undo_log 回滚执行

```java
// UndoLogManager — AT 模式回滚核心

public class UndoLogManager {

    // 回滚操作
    public void undo(String xid, long branchId, Connection conn) {

        // 1. 从 undo_log 表读取 undo 记录
        SQLUndoLog undoLog = fetchUndoLog(xid, branchId, conn);

        // 2. 校验 after-image（防脏写）
        TableRecords currentRecords = queryCurrentRecords(undoLog, conn);
        if (!currentRecords.equals(undoLog.getAfterImage())) {
            // 当前数据 ≠ after-image → 被其他事务修改了 → 脏写！
            if (undoLog.getSqlType() == SQLType.INSERT) {
                // INSERT 的脏写 → 当前行已存在 → 无需回滚
                return;
            }
            // UPDATE/DELETE 的脏写 → 报异常
            throw new BranchTransactionException(
                "Dirty write detected! Current data does not match after-image.");
        }

        // 3. 根据 before-image 生成反向 SQL
        switch (undoLog.getSqlType()) {
            case INSERT:
                // INSERT 的反向 → DELETE
                generateDeleteSQL(undoLog.getTableName(), undoLog.getAfterImage().pkValues());
                break;
            case UPDATE:
                // UPDATE 的反向 → UPDATE（用 before-image 的值）
                generateReverseUpdateSQL(undoLog, conn);
                break;
            case DELETE:
                // DELETE 的反向 → INSERT（用 before-image 的值）
                generateInsertSQL(undoLog.getBeforeImage(), conn);
                break;
        }

        // 4. 执行反向 SQL
        executeReverseSQL(conn);

        // 5. 删除 undo_log 记录
        deleteUndoLog(xid, branchId, conn);
    }
}
```

### 7.9 Seata TC 的全局事务状态管理

```
全局事务状态流转：

  ┌──────┐  begin   ┌──────┐  commit   ┌──────────┐
  │  无  │────────→│Begin │────────→│Committing│
  │      │         │      │         │          │
  └──────┘         │      │         │          │
                   │      │  rollback│          │
                   │      │────────→│Rollbacking│
                   │      │         │          │
                   └──┬───┘         └──────────┘
                      │                  │
                      │ timeout          │ 全部分支完成
                      │                  │
                   ┌──┴───┐         ┌───┴───────┐
                   │Timeout│         │Committed/ │
                   │Retrying│         │RolledBack │
                   │      │         │           │
                   └──────┘         └───────────┘
```

```java
// DefaultCore — TC 端全局事务核心处理逻辑

public class DefaultCore implements Core {

    // 全局提交
    public GlobalStatus commit(String xid) throws TransactionException {
        GlobalSession globalSession = sessionManager.findGlobalSession(xid);

        // 1. 标记全局事务状态为 Committing
        globalSession.changeStatus(GlobalStatus.Committing);

        // 2. 逐个提交分支
        for (BranchSession branchSession : globalSession.getSortedBranches()) {
            BranchStatus branchStatus = branchCommit(branchSession);
            if (branchStatus == BranchStatus.PhaseTwo_Committed) {
                // 分支提交成功 → 从全局会话移除
                globalSession.removeBranch(branchSession);
            }
        }

        // 3. 全局提交完成
        globalSession.changeStatus(GlobalStatus.Committed);
        return GlobalStatus.Committed;
    }

    // 全局回滚
    public GlobalStatus rollback(String xid) throws TransactionException {
        GlobalSession globalSession = sessionManager.findGlobalSession(xid);

        // 1. 标记全局事务状态为 Rollbacking
        globalSession.changeStatus(GlobalStatus.Rollbacking);

        // 2. 逆序回滚分支（保证补偿顺序正确）
        List<BranchSession> branches = globalSession.getReverseSortedBranches();
        for (BranchSession branchSession : branches) {
            BranchStatus branchStatus = branchRollback(branchSession);
            if (branchStatus == BranchStatus.PhaseTwo_Rolled_Back) {
                globalSession.removeBranch(branchSession);
            }
        }

        // 3. 全局回滚完成
        globalSession.changeStatus(GlobalStatus.RolledBack);
        return GlobalStatus.RolledBack;
    }
}
```

### 7.10 Seata 与 Spring Boot 集成配置

#### 依赖配置

```xml
<!-- Seata Spring Boot Starter -->
<dependency>
    <groupId>io.seata</groupId>
    <artifactId>seata-spring-boot-starter</artifactId>
    <version>1.8.0</version>
</dependency>
```

#### application.yml 配置

```yaml
seata:
  enabled: true
  application-id: order-service      # 服务标识
  tx-service-group: my_tx_group      # 事务分组（逻辑分组）

  service:
    vgroup-mapping:
      my_tx_group: default            # 事务分组 → TC集群映射
    enable-degrade: false              # 降级开关
    disable-global-transaction: false  # 全局事务开关

  registry:
    type: nacos                        # 注册中心类型
    nacos:
      server-addr: 127.0.0.1:8848
      namespace: ""
      group: SEATA_GROUP
      application: seata-server

  config:
    type: nacos                        # 配置中心类型
    nacos:
      server-addr: 127.0.0.1:8848
      namespace: ""
      group: SEATA_GROUP

  transport:
    type: TCP
    server-mode: NIO
    heartbeat: true
    serialization: seata
    compressor: none

  client:
    undo:
      data-validation: true            # undo_log 脏写校验
      log-serialization: jackson       # undo日志序列化方式
      only-care-update-columns: true   # 只记录修改的列
    lock:
      retry-interval: 10              # 全局锁获取重试间隔(ms)
      retry-times: 30                 # 全局锁获取重试次数
      retry-policy-branch-rollback-on-conflict: true
```

#### 业务代码示例

```java
// 订单服务 — @GlobalTransactional 使用示例
@Service
public class OrderService {

    @Autowired
    private AccountService accountService;    // Feign调用
    @Autowired
    private InventoryService inventoryService; // Feign调用
    @Autowired
    private OrderMapper orderMapper;

    @GlobalTransactional(name = "create-order", timeoutMills = 60000,
                         rollbackFor = Exception.class)
    public Order createOrder(OrderDTO orderDTO) {

        // 1. 创建订单（本地事务）
        Order order = new Order();
        order.setStatus("INIT");
        order.setUserId(orderDTO.getUserId());
        order.setAmount(orderDTO.getAmount());
        orderMapper.insert(order);  // ← Seata AT自动拦截

        // 2. 扣减库存（远程调用）
        inventoryService.deduct(orderDTO.getSkuId(), orderDTO.getQuantity());
        // ← Seata 传递 xid 到库存服务

        // 3. 扣减余额（远程调用）
        accountService.deduct(orderDTO.getUserId(), orderDTO.getAmount());
        // ← Seata 传递 xid 到账户服务

        // 4. 更新订单状态
        order.setStatus("CONFIRMED");
        orderMapper.update(order);

        return order;
        // ← 方法返回时 TM 自动 commit/rollback
    }
}
```

#### xid 传递机制

```
Seata xid 在微服务间的传递：

  ┌──────────────────────────────────────────────────┐
  │ 服务A (TM)                                        │
  │   RootContext.bind(xid) ← 开启全局事务时绑定       │
  │                                                    │
  │   Feign调用 → SeataFeignInterceptor               │
  │     ↓ 拦截请求                                     │
  │     ↓ 在HTTP Header 中添加 xid:                   │
  │       X-TX-XID: 192.168.1.1:8091:1234567890       │
  │                                                    │
  │ 服务B (RM)                                        │
  │   SeataHandlerInterceptor                         │
  │     ↓ 拦截请求                                     │
  │     ↓ 从HTTP Header 取出 xid                      │
  │     ↓ RootContext.bind(xid) ← 绑定到当前线程      │
  │                                                    │
  │   执行本地SQL → Seata 自动识别全局事务 → 拦截      │
  │                                                    │
  │   返回响应 → RootContext.unbind() ← 清理xid       │
  └──────────────────────────────────────────────────┘
```

### 7.11 Seata 各模式使用建议

| 场景 | 推荐模式 | 理由 |
|------|---------|------|
| **大多数业务（订单/库存/账户）** | AT | 低侵入、高性能、自动拦截 |
| **资源需要冻结（预扣库存）** | TCC | 业务需要预留机制 |
| **长流程编排（跨国转账多步）** | Saga | 流程长、补偿链清晰 |
| **强一致要求（金融核心账户）** | XA | 必须强一致，宁可牺牲性能 |
| **跨企业通知（支付回调）** | 最大努力通知 | 对方系统不可控 |

---

## 八、各方案对比与选型指南

### 8.1 六大方案全面对比

```
一致性强度 ───────────────────────────────→

  XA/2PC    AT      TCC     本地消息表  事务消息   Saga   最大努力通知
  强一致    最终一致  最终一致  最终一致    最终一致  最终一致  最终一致（弱）

性能/吞吐 ───────────────────────────────→

  XA/2PC    AT      TCC     本地消息表  事务消息   Saga   最大努力通知
  低        中      高      高          高        最高    最高

实现复杂度 ───────────────────────────────→

  XA/2PC    AT      TCC     本地消息表  事务消息   Saga   最大努力通知
  低(依赖DB) 低(加表) 高(3方法) 中(加表+轮询) 中(依赖MQ) 中(状态机) 低

业务侵入 ───────────────────────────────→

  XA/2PC    AT      TCC     本地消息表  事务消息   Saga   最大努力通知
  低        低      高      中          低        中      低
```

### 8.2 详细对比表

| 维度 | 2PC/XA | 3PC | TCC | 本地消息表 | RocketMQ事务消息 | Saga | Seata AT | 最大努力通知 |
|------|--------|-----|-----|-----------|-----------------|------|---------|------------|
| **一致性** | 强一致 | 强一致（理论） | 最终一致 | 最终一致 | 最终一致 | 最终一致 | 最终一致 | 最终一致（弱） |
| **可用性** | 低 | 中 | 高 | 高 | 高 | 最高 | 高 | 高 |
| **性能** | 低 | 低 | 中 | 中 | 高 | 最高 | 高 | 高 |
| **业务侵入** | 低 | 低 | 高 | 中 | 低 | 中 | 低 | 低 |
| **实现复杂度** | 低 | 低 | 高 | 中 | 中 | 中 | 低 | 低 |
| **隔离性** | 有 | 有 | 有 | 无 | 无 | 无 | 有（全局锁） | 无 |
| **回滚方式** | 同步undo | 同步undo | 业务Cancel | 无需回滚 | 无需回滚 | 补偿链 | 自动undo | 无需回滚 |
| **适用场景** | 同DB | 同DB | 微服务 | 内部 | 内部 | 长流程 | 微服务 | 跨企业 |
| **是否落地** | 是 | 几乎不用 | 是 | 是 | 是 | 是 | 是 | 是 |

### 8.3 选型决策树

```
                    你需要分布式事务吗？
                         │
                    Yes ─┤── No → 不需要
                         │
                    一致性要求多强？
                         │
              ┌──────────┼──────────┐
              │          │          │
          强一致      最终一致    最终一致（弱）
              │          │          │
         XA/2PC      可接受延迟?  跨企业？
              │          │          │
         ┌────┤     Yes──┤── No  Yes──┤── No
         │    │          │          │
    Seata   纯XA   微服务?   跨企业?  最大努力通知
    AT模式         │       │
         │    ┌───┤──┐  本地消息表
         │    │   │   │  RocketMQ事务消息
     可冻结? 长流程? 一般业务
         │    │   │
     TCC  Saga  AT模式
```

### 8.4 实际项目中的最佳实践

#### 实践1：大多数业务用 Seata AT

```
推荐理由：
  ✓ 低侵入：仅加 undo_log 表 + @GlobalTransactional 注解
  ✓ 高性能：一阶段本地提交，不持长锁
  ✓ 自动化：SQL 拦截自动生成 undo_log
  ✓ Spring Boot 集成方便

注意事项：
  ⚠ 每个参与数据库都要建 undo_log 表
  ⚠ 全局锁等待需配置合理的超时和重试次数
  ⚠ 脏写异常需人工介入处理
  ⚠ 需部署独立的 TC Server
```

#### 实践2：核心金融场景用 XA 或 TCC

```
金融场景要求：
  ✓ 资金操作不能出现不一致
  ✓宁可牺牲性能也要保证数据正确

选择策略：
  同库操作 → XA（强一致，有隔离）
  跨服务操作 → TCC（业务冻结，高可靠）
```

#### 实践3：跨服务异步场景用事务消息

```
场景：订单创建 → 通知积分服务、物流服务

选择：RocketMQ 事务消息
  ✓ 消息必达保证
  ✓ 回查机制兜底
  ✓ 不依赖额外框架（仅RocketMQ）

替代：本地消息表（如果不用RocketMQ）
```

#### 实践4：跨企业场景用最大努力通知

```
场景：支付宝回调商户、银行间对账

选择：最大努力通知
  ✓ 对方系统不可控，无法强一致
  ✓ 尽力通知 + 对方主动查询
  ✓ 递增间隔重试策略
```

---

## 九、面试高频问题与标准回答

### Q1：分布式事务和本地事务有什么区别？

```
本地事务：
  单库事务，由数据库 ACID 保证（undo log + redo log + 锁 + MVCC）
  优点：强一致、简单可靠
  缺点：只能覆盖单一数据库

分布式事务：
  跨多库/多服务的事务，无法由单一数据库保证
  需要：协调者（TC/TM）、参与者（RM）、通信协议（2PC/TCC）
  核心矛盾：CAP定理 → 不能同时满足强一致和高可用
  实际选择：根据业务需求在一致性强度与可用性之间权衡
```

### Q2：2PC 有什么问题？3PC 能解决吗？

```
2PC 的三个致命问题：
  1. 同步阻塞：Prepare阶段持锁，其他事务全部等待
  2. 单点故障：协调者宕机，所有参与者永久阻塞
  3. 网络分区：分区后部分提交部分等待，数据不一致

3PC 的改进：
  增加 CanCommit 阶段（轻量检查，不持锁不写日志）
  超时自动提交机制（减少阻塞）

3PC 仍然不能解决：
  网络分区下超时自动提交反而加剧不一致
  → 3PC 在工程中几乎不被使用
```

### Q3：TCC 的空回滚、悬挂、幂等是什么？

```
空回滚：
  Try 未执行但 Cancel 先到达 → Cancel 应识别"未Try"→ 插标记返回成功
  原因：Try请求网络丢失

悬挂：
  空回滚后 Try 延迟到达 → Try 应检查"已Cancel"→ 拒绝执行
  原因：Try延迟到达

幂等：
  Confirm/Cancel 被重复调用 → 应检查事务状态，已完成的直接返回
  原因：网络超时导致 TM 重试

Seata TCC 通过 tcc_fence_log 表自动解决这三个问题
```

### Q4：Seata AT 模式的一阶段为什么能直接提交？

```
2PC/XA：一阶段不提交 → 持锁 → 其他事务阻塞

Seata AT：一阶段就提交 → 不持本地锁 → 性能好

关键保障：
  1. undo_log：一阶段同时写业务SQL + undo_log → 本地事务保证原子性
  2. 全局锁：TC 记录哪些行被哪个全局事务占用 → 防止其他全局事务修改同一行
  3. 脏写校验：回滚时校验 after-image → 发现脏写则人工介入

一阶段提交后的回滚能力：
  读 undo_log → 生成反向SQL → 补偿恢复 → 删除 undo_log
```

### Q5：Seata AT 的全局锁有什么用？和数据库锁有什么区别？

```
数据库锁：
  本地事务的行锁/表锁
  Seata AT 一阶段提交后就释放了本地锁

全局锁：
  TC 端维护的逻辑锁（lock_table: tableName:pk → xid）
  作用：防止其他全局事务在当前全局事务未完成时修改同一行

场景：
  全局事务T1 修改 account(id=1)
  T1 一阶段提交 → 本地锁释放 → 但 TC 持有全局锁

  全局事务T2 试图修改 account(id=1)
  T2 一阶段 → RM 向 TC 申请全局锁 → TC 发现 T1 持有 → T2 等待

  T1 全局提交 → TC 释放全局锁 → T2 获得全局锁 → 继续

如果不加全局锁：
  T2 可修改 account(id=1) → T1 回滚时发现 after-image 不匹配 → 脏写
```

### Q6：RocketMQ 事务消息的半消息机制是怎么实现的？

```
半消息 = 对消费者不可见的消息

存储原理：
  发送半消息时 → Topic 改为 RMQ_SYS_TRANS_HALF_TOPIC
  存入 CommitLog → 消费者订阅原 Topic → 看不到

提交时：
  读出半消息 → 改回原始 Topic → 重新写入 CommitLog
  写 OP_MESSAGE 标记已提交 → 消费者可见

回滚时：
  写 OP_MESSAGE 标记已回滚 → 消费者永远看不到

回查机制：
  TransactionalMessageCheckService 定时扫描
  发现无 OP 的半消息 → 向 Producer 发回查
  Producer 查本地DB判断事务状态 → 返回 COMMIT/ROLLBACK
  最大回查15次 → 超过默认回滚
```

### Q7：Seata 四种模式怎么选？

```
AT 模式（首选）：
  大多数业务场景
  低侵入（仅加undo_log表 + 注解）
  高性能（一阶段本地提交）
  自动化SQL拦截

TCC 模式：
  需要资源冻结的业务（预扣库存/冻结金额）
  高侵入但高可靠

Saga 模式：
  长流程编排（跨国转账多步骤）
  无隔离性，允许脏读

XA 模式：
  强一致要求（金融核心账户）
  性能最低但一致性最强

一句话总结：日常用AT，冻结用TCC，长流程用Saga，强一致用XA
```

### Q8：如何处理分布式事务中的脏写？

```
脏写 = 一个全局事务的回滚数据被另一个事务修改了

Seata AT 的三层防御：
  1. 全局锁：TC 端逻辑锁 → 防止并发全局事务修改同一行
  2. after-image 校验：回滚时校验当前数据是否等于 after-image
     不等 → 说明被其他本地事务改了 → 报脏写异常
  3. 人工介入：脏写异常需要人工处理（手动补偿或数据修复）

预防措施：
  - 合理设置全局锁重试次数和超时时间
  - 非Seata管理的本地事务不应修改Seata管理的行
  - 生产环境建议开启 undo_log 数据校验（data-validation=true）
```

### Q9：分布式事务的一致性和性能如何权衡？

```
理论基础：CAP定理
  网络分区时 → C 和 A 只能选其一

工程实践：BASE理论
  放弃强一致 → 追求最终一致 → 保证高可用

选型策略：
  ┌──────────────┐
  │ 金融核心账户 │ → XA/TCC → 强一致，牺牲性能
  │ 支付结算     │ → Seata AT → 最终一致，性能好
  │ 电商下单     │ → Seata AT → 最终一致，性能好
  │ 积分/通知   │ → 事务消息 → 最终一致，异步高性能
  │ 跨企业通知   │ → 最大努力通知 → 弱一致，最高可用
  └──────────────┘

原则：业务决定一致性要求，架构决定可用性要求，技术方案适配两者
```

### Q10：Seata 的 TC 集群如何保证高可用？

```
TC 集群部署：
  多个 TC Server 实例 → 通过 Nacos 注册发现

事务日志存储：
  TC 的全局事务日志存储在独立DB中（MySQL/Redis等）
  → TC 宕机后，新 TC 可从DB恢复未决事务

事务分组映射：
  client配置 tx-service-group → 映射到 TC 集群
  → 一个分组可对应多个 TC 实例 → 故障自动切换

TC 降级机制：
  enable-degrade: true → TC 不可用时降级为非事务模式
  → 保证业务可用，但失去事务保证

TC 非侵入降级：
  Seata 支持配置 disable-global-transaction: true
  → 紧急情况下关闭全局事务 → 优先保证业务可用
```

---

## 附录：关键术语速查表

| 术语 | 全称 | 含义 |
|------|------|------|
| **2PC** | Two-Phase Commit | 两阶段提交协议 |
| **3PC** | Three-Phase Commit | 三阶段提交协议 |
| **TCC** | Try-Confirm-Cancel | 业务层面三阶段事务 |
| **XA** | X/Open XA | 分布式事务工业标准 |
| **Saga** | Saga Pattern | 长事务拆分为短事务链+补偿链 |
| **AT** | Automatic Transaction | Seata自动事务模式 |
| **TC** | Transaction Coordinator | Seata事务协调者 |
| **TM** | Transaction Manager | Seata事务管理器 |
| **RM** | Resource Manager | Seata资源管理器 |
| **undo_log** | Undo Log | Seata AT的回滚日志表 |
| **before-image** | Before Image | 修改前的数据快照 |
| **after-image** | After Image | 修改后的数据快照 |
| **全局锁** | Global Lock | TC端维护的逻辑行锁 |
| **半消息** | Half Message | RocketMQ对消费者不可见的消息 |
| **空回滚** | Empty Rollback | Try未执行但Cancel被调用 |
| **悬挂** | Suspension | 空回滚后Try延迟到达 |
| **幂等** | Idempotent | 重复调用结果不变 |
| **脏写** | Dirty Write | 回滚数据被其他事务修改 |
| **CAP** | Consistency-Availability-Partition tolerance | 分布式系统三要素定理 |
| **BASE** | Basically Available-Soft State-Eventually Consistent | 分布式系统工程理论 |

---

> **学习路线建议**：
> 1. 先理解 **CAP/BASE** 理论 → 明确分布式事务的设计约束
> 2. 掌握 **2PC/XA** → 理解强一致的代价（阻塞、单点）
> 3. 学习 **TCC** → 理解业务层面事务的实现与异常处理
> 4. 理解 **事务消息** → 掌握最终一致性方案的实现
> 5. 深入 **Seata** → 实战主流框架的四种模式
> 6. 对比选型 → 根据业务场景选择合适方案
> 7. 衔接已学的 **RocketMQ/Kafka** → 事务消息是消息队列的扩展应用
> 8. 衔接已学的 **Spring Cloud** → Seata 是微服务事务的标配组件

---

*本文为 Java 后端全栈学习系列第 28 篇，前序文档涵盖 HashMap → ConcurrentHashMap → 线程池 → AQS → volatile/JMM → Java基础 → Java8新特性 → 并发同步工具 → 类加载 → Spring IoC → Spring AOP → Spring Cloud → Dubbo → Spring全家桶串讲 → MySQL索引 → EXPLAIN → MySQL事务锁 → Redis数据结构 → Redis缓存 → Nginx → Netty → Elasticsearch → Zookeeper → RocketMQ → Kafka → JVM GC → JVM调优*
