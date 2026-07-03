# Zookeeper 底层原理深度解析

> **本文档基于 Zookeeper 3.8.x 源码**，系统解析 ZK 的架构设计、ZAB 协议、Leader 选举、数据同步、Watch 机制、会话管理、请求处理链、持久化、典型应用场景。

---

## 目录

- [第一部分：Zookeeper 架构全景](#第一部分zookeeper-架构全景)
- [第二部分：数据模型与 ZNode](#第二部分数据模型与-znode)
- [第三部分：ZAB 协议详解](#第三部分zab-协议详解)
- [第四部分：Leader 选举源码](#第四部分leader-选举源码)
- [第五部分：数据同步机制](#第五部分数据同步机制)
- [第六部分：Watch 机制源码](#第六部分watch-机制源码)
- [第七部分：会话管理](#第七部分会话管理)
- [第八部分：请求处理链](#第八部分请求处理链)
- [第九部分：持久化机制](#第九部分持久化机制)
- [第十部分：客户端与 Curator](#第十部分客户端与-curator)
- [第十一部分：集群动态配置与 Observer](#第十一部分集群动态配置与-observer)
- [第十二部分：典型应用场景](#第十二部分典型应用场景)
- [第十三部分：ZAB vs Raft vs Paxos 对比](#第十三部分zab-vs-raft-vs-paxos-对比)
- [第十四部分：性能优化与最佳实践](#第十四部分性能优化与最佳实践)
- [第十五部分：面试高频题 20 问](#第十五部分面试高频题-20-问)

---

## 第一部分：Zookeeper 架构全景

### 1.1 Zookeeper 是什么

Zookeeper 是一个**分布式协调服务**（Distributed Coordination Service），由 Yahoo 开发，后捐赠给 Apache 基金会。

**核心定位**：不是数据库、消息队列、缓存，而是分布式系统中的"协调者"——提供配置管理、命名服务、分布式锁、Leader 选举、集群管理等能力。

**一句话理解**：Zookeeper 就像一个**分布式文件系统 + 通知机制**，你往里面存数据，数据变化时通知你。

```
┌─────────────────────────────────────────────────────────────────┐
│                     Zookeeper 集群架构                           │
│                                                                 │
│    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    │
│    │   Client 1   │    │   Client 2   │    │   Client 3   │    │
│    └──────┬───────┘    └──────┬───────┘    └──────┬───────┘    │
│           │  TCP 长连接        │                   │              │
│           ▼                   ▼                   ▼              │
│    ┌──────────────────────────────────────────────────────┐     │
│    │                    Zookeeper 集群                     │     │
│    │   ┌──────────┐    ┌──────────┐    ┌──────────┐      │     │
│    │   │  Leader   │◄──►│ Follower │◄──►│ Follower │      │     │
│    │   │ (处理写)   │    │ (处理读)  │    │ (处理读)  │      │     │
│    │   └──────────┘    └──────────┘    └──────────┘      │     │
│    │         ▲               │               │             │     │
│    │         │    ZAB 协议    │               │             │     │
│    │         └───────────────┴───────────────┘             │     │
│    │                 原子广播 + 过半提交                      │     │
│    └──────────────────────────────────────────────────────┘     │
│                                                                 │
│    可选: ┌──────────┐                                          │
│         │ Observer  │  (只读，不参与选举和写投票)                    │
│         └──────────┘                                          │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 集群角色

| 角色 | 职责 | 参与选举 | 处理写 | 处理读 |
|------|------|:-------:|:-----:|:-----:|
| **Leader** | 处理所有写请求，发起 ZAB 协议广播 | ✅ | ✅ | ✅ |
| **Follower** | 处理读请求，参与 Leader 选举和写投票 | ✅ | ❌（转发给 Leader） | ✅ |
| **Observer** | 处理读请求，不参与选举和投票 | ❌ | ❌ | ✅ |

### 1.3 写请求处理流程

```
Client ──写请求──► Follower/Observer
                      │ 转发给 Leader
                      ▼
                   Leader
                      │
            ┌─────────┴─────────┐
            │  生成 ZXID        │
            │  发起 Proposal    │
            └─────────┬─────────┘
                      │
          ┌───────────┼───────────┐
          ▼           ▼           ▼
     Follower    Follower    Observer
     (ACK)       (ACK)       (不投票)
          │           │
          └─────┬─────┘
                │ 收到过半 ACK
                ▼
            Leader
                │
        ┌───────┴───────┐
        │  发送 Commit   │
        │  写入事务日志   │
        │  应用到内存树   │
        └───────────────┘
```

### 1.4 为什么是"过半"而不是"全部"

Zookeeper 使用**过半机制**（Quorum）而非一致投票：

| 策略 | 可用性 | 一致性 | 说明 |
|------|--------|--------|------|
| 全部同意（All） | ❌ 任何一个节点宕机就不可写 | ✅ 强一致 | 太严格 |
| 过半同意（Quorum） | ✅ 少数节点宕机仍可用 | ✅ 最终一致 | 平衡 |
| 少数同意（Minority） | ✅ 高可用 | ❌ 脑裂风险 | 不可用 |

**过半的数学保证**：N 个节点中，只要 `N/2 + 1` 个节点同意，任意两个过半集合必有交集，因此任何两个已提交的 Proposal 必然被同一个节点先 ACK，这个节点的 ZXID 一定更大 → Leader 选举时能选出数据最新的节点。

### 1.5 ZXID —— 事务的全局唯一标识

ZXID 是 64 位长整型，由两部分组成：

```
┌──────────────────────────────────────────────────┐
│                    ZXID (64 bit)                  │
├──────────────────────┬───────────────────────────┤
│   epoch (高 32 位)   │   counter (低 32 位)      │
│                      │                           │
│  Leader 任期编号      │  当前 epoch 内的递增序号   │
│  每次 Leader 切换 +1   │  每次 Proposal +1         │
└──────────────────────┴───────────────────────────┘
```

```java
// ZxidUtils.java
public class ZxidUtils {
    public static long getEpochFromZxid(long zxid) {
        return zxid >> 32L;
    }
    public static long getCounterFromZxid(long zxid) {
        return zxid & 0xffffffffL;
    }
    public static long makeZxid(long epoch, long counter) {
        return (epoch << 32L) | (counter & 0xffffffffL);
    }
}
```

### 1.6 核心架构组件全景

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Zookeeper Server 架构                         │
│                                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────┐ │
│  │  NettyServer │  │  NIOServer  │  │  ZooKeeper  │  │ WatchMgr  │ │
│  │  网络层      │  │  网络层      │  │  Server     │  │ (Watch    │ │
│  │             │  │             │  │  核心入口    │  │  管理)    │ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └─────┬──────┘ │
│         └────────────────┴────────────────┘               │         │
│                              │                             │         │
│                    ┌─────────▼─────────┐                  │         │
│                    │  FirstProcessor     │  ← 请求处理链入口 │         │
│                    │  (PrepReqProc)      │                  │         │
│                    └─────────┬─────────┘                  │         │
│                              │                             │         │
│                    ┌─────────▼─────────┐                  │         │
│                    │ ProposalReqProc    │  ← ZAB 协议     │         │
│                    │ (Leader 专用)       │     Proposal     │         │
│                    └─────────┬─────────┘                  │         │
│                              │                             │         │
│                    ┌─────────▼─────────┐                  │         │
│                    │  CommitProcessor   │  (等待过半 ACK)   │         │
│                    └─────────┬─────────┘                  │         │
│                              │                             │         │
│                    ┌─────────▼─────────┐                  │         │
│                    │ FinalReqProcessor  │  ← 应用到内存树  │         │
│                    │ (执行 + 响应)      │     + 触发 Watch  │         │
│                    └─────────┬─────────┘                  │         │
│                              │              ┌──────────────┘         │
│                    ┌─────────▼─────────┐    │                       │
│                    │   ZKDatabase       │◄───┘                       │
│                    │   (ZNode 内存树)   │                            │
│                    └─────────┬─────────┘                            │
│                              │                                       │
│                    ┌─────────▼─────────┐                            │
│                    │  FileTxnSnapLog    │  ← 持久化                   │
│                    │ (事务日志 + 快照)   │                            │
│                    └───────────────────┘                            │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                     Leader 选举组件                            │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │  │
│  │  │ QuorumCnxMgr  │  │ FastLeader   │  │  Learner    │        │  │
│  │  │ (网络连接管理) │  │ Election     │  │  Handler    │        │  │
│  │  │               │  │ (选举算法)    │  │ (数据同步)   │        │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                     会话管理                                    │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │  │
│  │  │ SessionTracker│  │  ExpiryQueue  │  │  Touch       │        │  │
│  │  │ (会话跟踪)     │  │ (超时队列)    │  │  (心跳续期)   │        │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │  │
│  └──────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

### 1.7 Zookeeper 的 ACID 保证

| 特性 | 保证程度 | 说明 |
|------|----------|------|
| **原子性** | ✅ 强保证 | 写操作要么全部节点成功，要么全部失败（ZAB 二阶段提交） |
| **一致性** | ✅ 顺序一致 | 客户端看到的写顺序与 Leader 的发起顺序一致 |
| **隔离性** | ✅ 线性一致 | 每个写操作都是原子的，不存在中间状态 |
| **持久性** | ✅ 强保证 | 过半节点写入事务日志后才响应客户端成功 |

> ⚠️ **注意**：Zookeeper 不保证读到最新数据。Follower 可能有延迟，读请求可能读到旧数据。如需强一致读，需要在读之前调用 `sync()` 操作。

---

## 第二部分：数据模型与 ZNode

### 2.1 ZNode 树结构

Zookeeper 的数据模型类似文件系统的目录树，每个节点称为 **ZNode**（ZooKeeper Node）。

```
/                       ← 根节点
├── /app1               ← 持久节点
│   ├── /app1/config    ← 持久节点（存储配置）
│   ├── /app1/leader    ← 临时节点（Leader 选举）
│   └── /app1/members   ← 持久节点
│       ├── /app1/members/node_0001  ← 顺序持久节点
│       ├── /app1/members/node_0002
│       └── /app1/members/node_0003
├── /app2
│   ├── /app2/lock       ← 临时节点（分布式锁）
│   └── /app2/tasks
│       └── /app2/tasks/task_0001  ← 顺序临时节点（任务队列）
├── /zookeeper           ← ZK 系统内置节点
│   ├── /zookeeper/quota ← 配额管理
│   └── /zookeeper/config ← 集群动态配置
```

### 2.2 四种节点类型

| 类型 | 标志 | 说明 | 典型场景 |
|------|------|------|----------|
| **持久节点** | `PERSISTENT` | 客户端断开后节点依然存在 | 配置存储、命名服务 |
| **持久顺序节点** | `PERSISTENT_SEQUENTIAL` | 持久 + 自动追加递增序号后缀 | 任务队列、注册编号 |
| **临时节点** | `EPHEMERAL` | 客户端会话断开后自动删除 | 分布式锁、Leader 选举 |
| **临时顺序节点** | `EPHEMERAL_SEQUENTIAL` | 临时 + 自动追加递增序号后缀 | 公平锁、排队队列 |
| **容器节点** | `CONTAINER` | 最后一个子节点删除后自动清除 | Leader 选举父节点 |
| **TTL 节点** | `PERSISTENT_WITH_TTL` | 持久但超过 TTL 无子节点时删除 | 临时配置 |

```java
// CreateMode.java 源码
public enum CreateMode {
    PERSISTENT(0, false, false),
    PERSISTENT_SEQUENTIAL(2, false, true),
    EPHEMERAL(1, true, false),
    EPHEMERAL_SEQUENTIAL(3, true, true),
    CONTAINER(4, false, false),
    PERSISTENT_WITH_TTL(5, false, false),
    PERSISTENT_SEQUENTIAL_WITH_TTL(6, false, true);

    private final int value;
    private final boolean ephemeral;
    private final boolean sequential;
    
    public boolean isEphemeral() { return ephemeral; }
    public boolean isSequential() { return sequential; }
    public int toFlag() {
        int ret = 0;
        if (ephemeral) ret |= 0x01;
        if (sequential) ret |= 0x02;
        return ret;
    }
}
```

### 2.3 ZNode 数据结构

```java
// DataNode.java — ZNode 在内存中的表示
public class DataNode implements Record {
    byte data[];                    // 节点存储的数据（最大 1MB）
    Long acl;                       // ACL 权限索引
    public StatPersisted stat;      // 节点状态信息
    Set<String> children = null;    // 子节点列表
}

// StatPersisted 中包含的关键字段：
// czxid:  创建该节点的事务 ZXID
// mzxid:  最后修改该节点的事务 ZXID
// ctime:  创建时间戳
// mtime:  最后修改时间戳
// version:  数据版本号（每次修改 +1）
// cversion: 子节点版本号
// aversion: ACL 版本号
// ephemeralOwner: 临时节点的会话 ID（非临时节点为 0）
// pzxid:  最后一个子节点创建/删除的 ZXID
// dataLength: 数据长度
// numChildren: 子节点数量
```

### 2.4 version 的乐观锁机制

Zookeeper 的 `setData` 和 `delete` 操作支持**版本检查**，实现乐观锁：

```java
// version = -1 表示不检查版本
// version >= 0 表示期望当前版本必须是这个值
zk.setData("/config", newData, expectedVersion);

// 服务端检查逻辑（PrepRequestProcessor）
if (version != -1 && record.stat.getVersion() != version) {
    throw new BadVersionException(path);
}
```

**典型场景**：
```
Client A 读取 /config，version = 3
Client B 读取 /config，version = 3
Client A 写入 /config，version = 3 → 成功，version 变为 4
Client B 写入 /config，version = 3 → 失败！BadVersionException
Client B 重新读取，version = 4
Client B 写入 /config，version = 4 → 成功
```

### 2.5 ZKDatabase —— 内存数据树

```java
// ZKDatabase.java
public class ZKDatabase {
    private DataTree dataTree;
    private ConcurrentHashMap<Long, Integer> sessionsWithTimeouts;
    private FileTxnLog txnLog;
    private FileSnap snapLog;
    private volatile long minCommittedLog;
    private volatile long maxCommittedLog;
    
    // 从快照 + 事务日志恢复数据
    public long loadDataBase() throws IOException {
        // 1. 加载快照
        long zxid = snapLog.deserialize(dataTree, sessionsWithTimeouts);
        // 2. 重放事务日志
        txnLog.replay(zxid, replayer);
        return zxid;
    }
}
```

### 2.6 DataTree 源码

```java
// DataTree.java
public class DataTree {
    // 所有 ZNode 的哈希表：path → DataNode
    private final ConcurrentHashMap<String, DataNode> nodes =
        new ConcurrentHashMap<>();
    
    // 临时节点索引：sessionId → Set<path>
    private final Map<Long, HashSet<String>> ephemerals =
        new ConcurrentHashMap<>();
    
    // Watch 管理器
    private final WatchManager dataWatches;
    private final WatchManager childWatches;
    
    // 会话过期时，删除该会话的所有临时节点
    public void killEphemerals(long sessionId) {
        HashSet<String> toKill = ephemerals.remove(sessionId);
        if (toKill != null) {
            for (String path : toKill) {
                DataNode node = nodes.get(path);
                deleteNode(path, node.stat.getMzxid());
                dataWatches.triggerWatch(path, EventType.NodeDeleted);
            }
        }
    }
    
    // 创建节点的事务处理
    public void processTxn(TxnHeader header, Record txn) {
        if (txn instanceof CreateTxn) {
            CreateTxn createTxn = (CreateTxn) txn;
            DataNode node = new DataNode();
            node.data = createTxn.getData();
            node.stat.setCzxid(header.getZxid());
            node.stat.setMzxid(header.getZxid());
            node.stat.setEphemeralOwner(createTxn.getEphemeral() ? 
                header.getClientId() : 0);
            addDataNode(createTxn.getPath(), node);
        } else if (txn instanceof DeleteTxn) {
            deleteTxn((DeleteTxn) txn);
        } else if (txn instanceof SetDataTxn) {
            setDataTxn((SetDataTxn) txn);
        }
    }
}
```

---

## 第三部分：ZAB 协议详解

### 3.1 ZAB 协议概述

**ZAB（ZooKeeper Atomic Broadcast）** 是 Zookeeper 专门设计的**原子广播协议**，用于保证集群中各节点数据一致性。

ZAB 不是 Paxos，也不是 Raft，但思想类似——都是基于 Leader 的共识协议。

**ZAB 的两个核心阶段**：
1. **Leader 选举**：集群启动或 Leader 崩溃时，选出一个新 Leader 并同步数据
2. **原子广播**：Leader 将写请求广播给所有 Follower，过半 ACK 后提交

```
                    ZAB 协议状态机
                    
    ┌─────────────┐     启动 / Leader 崩溃      ┌──────────────┐
    │  LOOKING    │ ──────────────────────────► │   LOOKING    │
    │  (选举中)    │ ◄────────────────────────── │  (选举中)     │
    └──────┬──────┘     选举完成                  └──────────────┘
           │ 选出 Leader                               
           ▼                                           
    ┌─────────────┐     Leader 确认                 ┌──────────────┐
    │  FOLLOWING  │                              │   LEADING    │
    │  (跟随者)    │ ◄────────────────────────── │  (领导者)     │
    └──────┬──────┘     Leader 崩溃                └──────┬───────┘
           │ Observer                                    │
           ▼                                            ▼
    ┌─────────────┐                              ┌──────────────┐
    │  OBSERVING  │                              │ Leader 崩溃   │
    │  (观察者)    │                              │ → LOOKING    │
    └─────────────┘                              └──────────────┘
```

### 3.2 ZAB 协议的四个阶段

```
阶段 1: Discovery（发现）
├── 所有节点进入 LOOKING 状态
├── 各节点广播自己的 (myid, lastZxid)
└── 选出拥有最大 ZXID 的节点作为 Leader 候选

阶段 2: Synchronization（同步）
├── Leader 收集 Follower 的 ZXID
├── 比较 Leader 与 Follower 的 ZXID 差异
├── 差异小 → DIFF（发送差异事务）
├── Follower ZXID > Leader → TRUNC（截断多余事务）
└── 差异大 → SNAP（发送完整快照）

阶段 3: Broadcast（广播）
├── Leader 进入 LEADING 状态
├── Follower 进入 FOLLOWING 状态
├── 写请求 → Leader 发起 Proposal
├── Follower ACK → Leader 收集过半 ACK
├── Leader 发送 Commit
└── 所有节点应用到内存树

阶段 4: Broadcast 持续运行直到 Leader 崩溃 → 回到阶段 1
```

### 3.3 原子广播 —— 写请求处理流程

```
    Client                Leader                 Follower
      │  1. 写请求            │                      │
      ├─────────────────────►│                      │
      │            ┌─────────┴─────────┐            │
      │            │ 2. 生成 Proposal   │            │
      │            │    ZXID = next     │            │
      │            │    写入事务日志     │            │
      │            └─────────┬─────────┘            │
      │           ┌──────────┼──────────┐           │
      │           ▼          ▼          ▼           │
      │     Follower1   Follower2   Follower3      │
      │      3.PROPOSAL  3.PROPOSAL  3.PROPOSAL    │
      │           │          │          │           │
      │     ┌─────┴────┐┌────┴────┐┌────┴────┐     │
      │     │写入日志   ││写入日志  ││写入日志  │     │
      │     │(flush)   ││(flush)  ││(flush)  │     │
      │     └─────┬────┘└────┬────┘└────┬────┘     │
      │      4.ACK     4.ACK     4.ACK          │
      │           └──────────┼──────────┘           │
      │            ┌─────────┴─────────┐            │
      │            │ 5. 收到过半 ACK    │            │
      │            │    Leader Commit  │            │
      │            └─────────┬─────────┘            │
      │           ┌──────────┼──────────┐           │
      │           ▼          ▼          ▼           │
      │     Follower1   Follower2   Follower3      │
      │      6.COMMIT    6.COMMIT    6.COMMIT      │
      │           │          │          │           │
      │     ┌─────┴────┐┌────┴────┐┌────┴────┐     │
      │     │应用到     ││应用到    ││应用到    │     │
      │     │内存树     ││内存树    ││内存树    │     │
      │     └──────────┘└─────────┘└─────────┘     │
      │  7. 响应成功          │                      │
      │◄─────────────────────┤                      │
```

### 3.4 ZAB 二阶段提交 vs 传统 2PC

| 特性 | 传统 2PC | ZAB |
|------|----------|-----|
| 协调者 | 单点故障 | Leader 崩溃可重新选举 |
| 提交策略 | 所有参与者同意 | **过半**参与者同意 |
| 阻塞 | 协调者宕机后阻塞 | Leader 崩溃后快速恢复 |
| 日志 flush | Prepare 后不强制 | Follower ACK 前必须 flush |
| 数据恢复 | 需要人工介入 | 自动选举 + 自动同步 |

**ZAB 的关键改进**：
1. **过半 ACK 即提交**——不需要所有节点同意，提高可用性
2. **Follower 先 flush 再 ACK**——保证 ACK 的数据一定落盘，Leader 崩溃后数据不丢
3. **Leader 选举选最大 ZXID**——保证新 Leader 的数据最完整
4. **ZXID 包含 epoch**——防止旧 Leader 的幽灵 Proposal 被接受

### 3.5 Proposal 队列与 Follower 顺序保证

```
    Leader 的 Proposal 队列
    
    ┌─────────────────────────────────────────────┐
    │             Leader 内部                      │
    │   请求队列        Proposal 队列              │
    │   ┌───────┐     ┌──────────────────┐       │
    │   │ Req1   │────►│ Proposal(zxid=1) │──────►──┐
    │   │ Req2   │────►│ Proposal(zxid=2) │──────►──┤ → 广播给所有 Follower
    │   │ Req3   │────►│ Proposal(zxid=3) │──────►──┤
    │   └───────┘     └──────────────────┘       │
    │   ACK 等待队列                                │
    │   ┌─────────────────────────────────────┐   │
    │   │ zxid=1: ACK=[F1,F2] ✓ (committed)  │   │
    │   │ zxid=2: ACK=[F1]    ⏳ (waiting)   │   │
    │   │ zxid=3: ACK=[]      ⏳ (waiting)   │   │
    │   └─────────────────────────────────────┘   │
    │   关键约束:                                   │
    │   ✓ zxid=1 commit 后，才能 commit zxid=2    │
    │   ✓ 保证 Follower 收到的 Proposal 是有序的   │
    │   ✓ 保证 Commit 也是有序的                   │
    └─────────────────────────────────────────────┘
```

### 3.6 ZXID 的 monotonic 保证

```java
// LeaderZooKeeperServer.java
public long getNextZxid() {
    // epoch 不变，counter +1
    return ZxidUtils.makeZxid(epoch, ++lastProcessedZxid);
}

// 新 Leader 选举后，epoch +1
long newEpoch = lastLoggedZxid >> 32; // 获取旧 epoch
newEpoch++;                             // epoch +1
// 新 Leader 的第一个 ZXID = newEpoch << 32
```

---

## 第四部分：Leader 选举源码

### 4.1 Leader 选举入口

```java
// QuorumPeer.java
public class QuorumPeer extends ZooKeeperThread {
    volatile ServerState state = ServerState.LOOKING;
    private Election electionAlg;
    
    @Override
    public void run() {
        while (running) {
            switch (getPeerState()) {
                case LOOKING:
                    // LOOKING 状态 → 启动选举
                    setCurrentVote(makeLEStrategy().lookForLeader());
                    break;
                case OBSERVING:
                    setObserver(makeObserverLogAndPropose());
                    break;
                case FOLLOWING:
                    setFollower(makeFollowerLogAndPropose());
                    break;
                case LEADING:
                    setLeader(makeLeader());
                    break;
            }
        }
    }
}
```

### 4.2 FastLeaderElection 算法

FastLeaderElection 是 Zookeeper 默认的选举算法，基于**快速选举**策略——不需要等到所有节点投票，只要有过半节点同意就选出 Leader。

```
           FastLeaderElection 选举流程
           
    1. 更新逻辑时钟 logicalclock++
    2. 获取本节点的提案 (myid, zxid)
    3. 给自己投票 vote = (myid, zxid)
    4. 广播投票给所有其他节点
    5. 循环接收其他节点的投票
    6. 收到其他节点投票 response
       a. 状态 == LOOKING → 比较选票
       b. 状态 == FOLLOWING 或 LEADING → 直接接受该 Leader
    7. 选票比较规则:
       a. epoch 大的优先
       b. epoch 相同，ZXID 大的优先
       c. ZXID 相同，myid 大的优先
    8. 如果对方选票更优 → 更新自己的选票 → 重新广播
       如果自己更优 → 记录对方的选票 → 统计是否过半
    9. 如果自己的选票过半 → 选举完成!
```

### 4.3 选举选票比较规则

```
              选票比较优先级
              
    ┌─────────────┐
    │  1. epoch   │ ← Leader 任期（高的优先）
    │     最大?    │
    └──────┬──────┘
           │ 相同?
           ▼
    ┌─────────────┐
    │  2. ZXID    │ ← 最后提交的事务 ID（数据最新）
    │     最大?    │
    └──────┬──────┘
           │ 相同?
           ▼
    ┌─────────────┐
    │  3. myid    │ ← 服务器 ID（配置文件中配置）
    │     最大?    │
    └─────────────┘
```

**为什么要先比 ZXID 再比 myid？** ZXID 最大的节点拥有最新的数据。优先选数据最新的节点当 Leader，减少同步成本。

### 4.4 lookForLeader() 源码

```java
// FastLeaderElection.java
public Vote lookForLeader() throws InterruptedException {
    HashMap<Long, Vote> recvset = new HashMap<>();
    
    // 1. 增加逻辑时钟
    synchronized (this) {
        logicalclock.incrementAndGet();
        updateProposal(getMyId(), getInitLastLoggedZxid(), getPeerEpoch());
    }
    
    // 2. 广播自己的选票
    sendNotifications();
    
    // 3. 循环等待和处理选票
    while ((self.getPeerState() == ServerState.LOOKING) && running) {
        Notification n = recvqueue.poll(notTimeout, TimeUnit.MILLISECONDS);
        
        if (n == null) {
            if (manager.haveDelivered()) {
                sendNotifications();
            } else {
                manager.connectAll();
            }
            continue;
        }
        
        // 4. 处理收到的选票
        switch (n.state) {
            case LOOKING:
                if (n.electionEpoch > logicalclock.get()) {
                    // 对方的选举轮次更高 → 重置并采用对方的轮次
                    logicalclock.set(n.electionEpoch);
                    recvset.clear();
                    if (totalOrderPredicate(n.leader, n.zxid, n.peerEpoch,
                            proposedLeader, proposedZxid, proposedEpoch)) {
                        updateProposal(n.leader, n.zxid, n.peerEpoch);
                    } else {
                        updateProposal(proposedLeader, proposedZxid, proposedEpoch);
                    }
                    sendNotifications();
                } else if (n.electionEpoch < logicalclock.get()) {
                    // 对方的选举轮次更低 → 忽略
                    break;
                } else if (totalOrderPredicate(n.leader, n.zxid, n.peerEpoch,
                        proposedLeader, proposedZxid, proposedEpoch)) {
                    // 轮次相同，对方的选票更优 → 更新
                    updateProposal(n.leader, n.zxid, n.peerEpoch);
                    sendNotifications();
                }
                
                recvset.put(n.sid, new Vote(n.leader, n.zxid, 
                    n.electionEpoch, n.peerEpoch));
                
                // 5. 检查是否有过半节点同意
                if (containsQuorum(recvset, getVote())) {
                    // 过半！选举成功
                    while ((n = recvqueue.poll(500, TimeUnit.MILLISECONDS)) != null) {
                        if (totalOrderPredicate(n.leader, n.zxid, 
                                n.peerEpoch, vote.getLeader(), 
                                vote.getZxid(), vote.getPeerEpoch())) {
                            recvqueue.put(n);
                            break;
                        }
                    }
                    // 设置最终状态
                    if (self.getPeerState() == ServerState.LOOKING) {
                        if (vote.getLeader() == self.getMyId()) {
                            self.setPeerState(ServerState.LEADING);
                        } else {
                            self.setPeerState(ServerState.FOLLOWING);
                        }
                    }
                    return vote;
                }
                break;
            case FOLLOWING:
            case LEADING:
                // 对方已经有 Leader
                if (n.electionEpoch == logicalclock.get()) {
                    recvset.put(n.sid, new Notification(n));
                    if (containsQuorum(recvset, n)) {
                        self.setPeerState(
                            (n.leader == self.getMyId()) ? 
                            ServerState.LEADING : ServerState.FOLLOWING);
                        return new Vote(n.leader, n.zxid, 
                                       n.electionEpoch, n.peerEpoch);
                    }
                }
                break;
        }
    }
    return null;
}
```

### 4.5 选票比较 totalOrderPredicate

```java
protected boolean totalOrderPredicate(
        long newId, long newZxid, long newEpoch,
        long curId, long curZxid, long curEpoch) {
    // 优先级 1: epoch
    if (newEpoch > curEpoch) return true;
    if (newEpoch < curEpoch) return false;
    // 优先级 2: ZXID
    if (newZxid > curZxid) return true;
    if (newZxid < curZxid) return false;
    // 优先级 3: myid
    if (newId > curId) return true;
    return false;
}
```

### 4.6 QuorumCnxManager —— 选举网络层

```java
// QuorumCnxManager.java
public class QuorumCnxManager {
    // 发送队列：sid → ArrayBlockingQueue
    final ConcurrentHashMap<Long, ArrayBlockingQueue<ByteBuffer>> queueSendMap;
    // 接收队列
    final LinkedBlockingQueue<QuorumPacket> recvQueue;
    // 发送线程
    final ConcurrentHashMap<Long, SendWorker> senderWorkerMap;
    
    // 建立连接时的规则：myid 大的一方主动发起连接
    public boolean initiateConnection(long sid) {
        if (sid > self.getId()) {
            return false; // 对方 myid 大，应该对方发起
        }
        SocketChannel channel = ...;
        channel.connect(new InetSocketAddress(addr, electionPort));
        return true;
    }
}
```

```
         选举网络连接管理（3 节点示例）
         
         Node1 (myid=1)     Node2 (myid=2)     Node3 (myid=3)
              │◄────── 连接 ──────│                   │
              │   (Node2 发起)     │                   │
              │◄────── 连接 ──────┼───────────────────│
              │   (Node3 发起)     │                   │
              │                   │◄────── 连接 ──────│
              │                   │   (Node3 发起)      │
         
         规则: myid 小的被连接，myid 大的主动连接
```

### 4.7 选举超时与重试

```
    初始超时: 200ms
    最大超时: 60000ms (1分钟)
    
    每次超时后: notTimeout = min(notTimeout * 2, 60000)
    → 200 → 400 → 800 → 1600 → 3200 → 6400 → 12800 → 25600 → 51200 → 60000
    
    收到消息后重置超时为初始值
```

---

## 第五部分：数据同步机制

### 5.1 数据同步概述

Leader 选举完成后，新 Leader 需要将自己的数据同步给所有 Follower，确保各节点数据一致后才开始处理客户端请求。

### 5.2 同步流程

```
     Leader                           Follower
       │  1. Follower 连接 Leader          │
       │◄────────────────────────────────┤
       │  (FOLLOWERINFO, 携带 zxid)         │
       │  2. Leader 计算 newEpoch           │
       │  3. Leader 发送 LEADERINFO        │
       ├────────────────────────────────►│
       │  4. Follower ACK                 │
       │◄────────────────────────────────┤
       │  5. Leader 比较 Follower 的       │
       │     lastZxid 与 Leader 的         │
       │     minCommittedLog /              │
       │     maxCommittedLog               │
       │  6. 选择同步策略:                  │
       │     lastZxid == maxZxid → DIFF    │
       │     lastZxid > maxZxid → TRUNC    │
       │     lastZxid < minZxid → SNAP     │
       │  7. 发送同步数据                   │
       ├────────────────────────────────►│
       │  8. 发送 UPTODATE (同步完成)       │
       ├────────────────────────────────►│
```

### 5.3 三种同步策略

```java
// LearnerHandler.java
public void syncFollower(long peerLastZxid) {
    long maxCommittedLog = zkDb.getMaxCommittedLog();
    long minCommittedLog = zkDb.getMinCommittedLog();
    
    // 情况 1: 完全一致
    if (peerLastZxid == maxCommittedLog) {
        queuedPackets.add(new QuorumPacket(Leader.UPTODATE, -1, null, null));
        return;
    }
    
    // 情况 2: DIFF 策略 — Follower 在 Leader 的提交范围内
    if (peerLastZxid < maxCommittedLog &&
        peerLastZxid >= minCommittedLog) {
        Iterator<Proposal> itr = zkDb.getProposals().iterator();
        while (itr.hasNext()) {
            Proposal proposal = itr.next();
            long packetZxid = proposal.getZxid();
            if (packetZxid > peerLastZxid) {
                queuedPackets.add(new QuorumPacket(
                    Leader.PROPOSAL, packetZxid,
                    proposal.getProposal().getBytes(), null));
                queuedPackets.add(new QuorumPacket(
                    Leader.COMMIT, packetZxid, null, null));
            }
        }
    }
    
    // 情况 3: TRUNC 策略 — Follower 超前于 Leader（脑裂场景）
    if (peerLastZxid > maxCommittedLog) {
        queuedPackets.add(new QuorumPacket(
            Leader.TRUNC, maxCommittedLog, null, null));
    }
    
    // 情况 4: SNAP 策略 — Follower 太旧
    if (peerLastZxid < minCommittedLog) {
        queuedPackets.add(new QuorumPacket(
            Leader.SNAP, maxCommittedLog, null, null));
        OutputArchive oa = new BinaryOutputArchive(bufferedOutput);
        zkDb.serializeSnapshot(oa);
    }
}
```

### 5.4 DIFF 同步场景

```
    Leader 的已提交事务: ZXID: 1, 2, ..., 10
    minCommittedLog = 1, maxCommittedLog = 10
    Follower 的 lastZxid = 7
    
    DIFF 同步:
    Leader 发送: PROPOSAL(zxid=8) + COMMIT(8)
                PROPOSAL(zxid=9) + COMMIT(9)
                PROPOSAL(zxid=10) + COMMIT(10)
                UPTODATE
    Follower 重放事务 8, 9, 10 → 数据追平
```

### 5.5 TRUNC 同步场景（脑裂恢复）

```
    场景：5 节点 → 脑裂为 3+2 两部分
    原 Leader 分区(3 节点): 提交了 zxid=11, 12
    新 Leader 分区(2 节点): 只提案了 zxid=11 但没过半提交
    
    Leader 的 maxCommittedLog = 10
    Follower 的 lastZxid = 12
    
    TRUNC 同步:
    Leader 发送: TRUNC(zxid=10) → Follower 回滚到 zxid=10
                UPTODATE
    Follower 删除 zxid=11, 12 的事务 → 数据一致
```

### 5.6 SNAP 同步场景

```
    Leader 的 minCommittedLog = 50
    Follower 的 lastZxid = 3 (太旧了)
    
    SNAP 同步:
    Leader 发送: SNAP(maxZxid=100)
                → 序列化完整 DataTree
                → 发送所有节点数据
                → 发送所有会话信息
                UPTODATE
    Follower: 清空自己的 DataTree → 反序列化 → 重建
```

---

## 第六部分：Watch 机制源码

### 6.1 Watch 机制概述

Watch 是 Zookeeper 的**数据变更通知机制**——客户端可以注册 Watch，当被监听的 ZNode 发生变化时，服务端会通知客户端。

```
    Client                         Server
      │  1. getData("/config", true) │  ← 注册 Watch
      ├─────────────────────────────►│
      │  2. 返回数据 + WatchManager     │
      │     记录: /config → Client    │
      │◄─────────────────────────────┤
      │                              │
      │       (另一个 Client 修改)     │
      │  3. setData("/config", newData)│
      │                              │◄─── 其他 Client
      │  4. 触发 Watch                 │
      │     WatchManager.trigger      │
      │     删除: /config → Client    │  ← Watch 一次性！
      │◄─────────────────────────────┤
      │  WatchedEvent:                │
      │    type=NodeDataChanged       │
      │    path=/config               │
      │  5. 客户端收到通知              │
      │     执行 Watcher.process()    │
      │     通常: 再次 getData()       │  ← 重新注册 Watch
      ├─────────────────────────────►│
```

### 6.2 Watch 的三种注册方式和四种触发类型

| 注册方式 | 触发类型 | 说明 |
|---------|---------|------|
| getData() | NodeDataChanged | 数据被修改 |
| getData() | NodeDeleted | 节点被删除 |
| getChildren() | NodeChildrenChanged | 子节点列表变化 |
| getChildren() | NodeDeleted | 节点被删除 |
| exists() | NodeCreated | 节点被创建 |
| exists() | NodeDataChanged | 数据被修改 |
| exists() | NodeDeleted | 节点被删除 |

> 注意: 没有针对子节点数据变化的 Watch，只能监听直接子节点的列表变化。

### 6.3 Watch 的一次性触发特性

```
    Client                    Server
      │ getData("/config", w1)  │
      ├────────────────────────►│ WatchManager: /config → [w1]
      │◄──── data ─────────────┤
      │                         │ setData("/config", d2)
      │◄── WatchEvent ──────────┤ WatchManager: /config → [] (w1 被删除)
      │                         │
      │  需要重新注册 Watch!      │ setData("/config", d3)
      │   ❌ 没有通知!           │ (w1 已经被删除)
      │                         │
      │ getData("/config", w2)  │
      ├────────────────────────►│ WatchManager: /config → [w2]
      │◄──── data ─────────────┤
```

**一次性的原因**：
1. 简化服务端实现——不需要管理 Watch 的生命周期
2. 避免大量 Watch 堆积——防止内存溢出
3. 客户端收到通知后重新注册即可

### 6.4 服务端 WatchManager 源码

```java
// WatchManager.java
public class WatchManager {
    // path → Set<Watcher> 映射
    private final Map<String, Set<Watcher>> watchTable =
        new ConcurrentHashMap<>();
    // Watcher → Set<path> 映射（反向索引）
    private final Map<Watcher, Set<String>> watch2Paths =
        new ConcurrentHashMap<>();
    
    // 注册 Watch
    public synchronized boolean addWatch(String path, Watcher watcher) {
        Set<Watcher> list = watchTable.get(path);
        if (list == null) {
            list = new HashSet<>();
            watchTable.put(path, list);
        }
        list.add(watcher);
        Set<String> paths = watch2Paths.get(watcher);
        if (paths == null) {
            paths = new HashSet<>();
            watch2Paths.put(watcher, paths);
        }
        paths.add(path);
        return true;
    }
    
    // 触发 Watch
    public Set<Watcher> triggerWatch(String path, EventType type) {
        WatchedEvent e = new WatchedEvent(type, 
            KeeperState.SyncConnected, path);
        Set<Watcher> watchers = watchTable.remove(path);  // ← 一次性！删除！
        if (watchers == null || watchers.isEmpty()) return null;
        
        Set<Watcher> triggeredWatchers = new HashSet<>();
        for (Watcher w : watchers) {
            triggeredWatchers.add(w);
            Set<String> paths = watch2Paths.get(w);
            if (paths != null) paths.remove(path);
        }
        
        for (Watcher w : triggeredWatchers) {
            w.process(e); // NIOServerCnxn.process() → 发送 WatchEvent 给客户端
        }
        return triggeredWatchers;
    }
}
```

### 6.5 客户端 Watch 处理

```java
// ClientCnxn.java
void processEvent(WatchedEvent event) {
    switch (event.getType()) {
        case NodeDataChanged:
        case NodeCreated:
        case NodeDeleted:
            Set<Watcher> watchers = watchManager.getDataWatches()
                .remove(event.getPath());
            if (watchers != null) {
                for (Watcher w : watchers) {
                    w.process(event);
                }
            }
            break;
        case NodeChildrenChanged:
            watchers = watchManager.getChildWatches()
                .remove(event.getPath());
            if (watchers != null) {
                for (Watcher w : watchers) {
                    w.process(event);
                }
            }
            break;
    }
}
```

### 6.6 持久 Watch（Zookeeper 3.6+）

```java
// 持久 Watch 解决了传统 Watch 一次性触发的问题
zk.addWatch("/config", watcher, AddWatchMode.PERSISTENT);
// PERSISTENT          — 持久监听数据变化和子节点变化
// PERSISTENT_RECURSIVE — 递归监听所有子节点的变化
```

### 6.7 Watch 性能分析

| 特性 | 数值 |
|------|------|
| 注册开销 | O(1) — ConcurrentHashMap.put() |
| 触发开销 | O(n) — n = Watcher 数量 |
| 传输开销 | 通过已有 TCP 连接，无额外连接开销 |
| 内存消耗 | 每个 Watch 约 200 bytes |
| 触发延迟 | ~1ms（Leader → Follower → Client） |
| 一次性问题 | 传统 Watch 通知后需重新注册 |
| 丢失窗口 | 通知和重新注册之间的变更不通知 |

---

## 第七部分：会话管理

### 7.1 会话生命周期

```
    ┌─────────┐  connect  ┌──────────────┐  超时  ┌──────────┐
    │  未连接  │─────────►│  已连接        │──────►│  已过期   │
    │         │           │  (CONNECTED)  │       │ (EXPIRED)│
    └─────────┘           └──────┬───────┘       └──────────┘
           ▲                     │
           │  断开               │ 断开
           │                     ▼
    ┌─────────┐           ┌──────────────┐
    │  关闭    │◄─────────│  连接断开      │
    │ (CLOSED)│  close    │  (DISCONNECTED)│
    └─────────┘           └──────────────┘
```

### 7.2 SessionTracker 源码

```java
// SessionTrackerImpl.java
public class SessionTrackerImpl extends ZooKeeperCriticalThread 
        implements SessionTracker {
    
    // 会话超时时间表：sessionId → timeout
    private final ConcurrentHashMap<Long, Integer> sessionTimeouts;
    // 过期队列：按超时时间分桶
    private final ExpiryQueue<Long> sessionExpiryQueue;
    
    @Override
    public void run() {
        while (running) {
            // 1. 计算下一个过期检查时间
            long expirationTime = roundToInterval(
                System.currentTimeMillis() + expirationInterval);
            // 2. 等待到过期检查时间
            Thread.sleep(waitTime);
            // 3. 检查过期会话
            Set<Long> expired = sessionExpiryQueue.poll();
            if (expired != null) {
                for (long sessionId : expired) {
                    setSessionClosing(sessionId);
                    expirer.expire(sessionId);
                }
            }
        }
    }
    
    // 会话续期（心跳）
    public boolean touchSession(long sessionId, int sessionTimeout) {
        SessionInfo info = sessionsById.get(sessionId);
        if (info == null || info.isClosing()) return false;
        // 重新设置过期时间
        long newExpirationTime = roundToInterval(
            System.currentTimeMillis() + sessionTimeout);
        sessionExpiryQueue.update(sessionId, newExpirationTime);
        return true;
    }
}
```

### 7.3 ExpiryQueue —— 分桶过期队列

```java
// ExpiryQueue.java
public class ExpiryQueue<E> {
    // 时间轮：expirationTime → Set<element>
    private final ConcurrentHashMap<Long, Set<E>> expiryMap;
    // 元素 → 过期时间
    private final ConcurrentHashMap<E, Long> expiryElemMap;
    private final int expirationInterval; // 分桶间隔
    
    public void update(E elem, long newExpirationTime) {
        Long oldExpirationTime = expiryElemMap.get(elem);
        if (oldExpirationTime != null) {
            expiryMap.get(oldExpirationTime).remove(elem);
        }
        expiryMap.computeIfAbsent(newExpirationTime, k -> new HashSet<>())
            .add(elem);
        expiryElemMap.put(elem, newExpirationTime);
    }
}
```

```
            ExpiryQueue 分桶机制
            
    时间轴 ──────────────────────────────────────────►
    桶1(100ms)  桶2(200ms)  桶3(300ms)  桶4(400ms)
    ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
    │ S1      │ │ S3      │ │ S2      │ │         │
    │ S5      │ │         │ │         │ │         │
    └─────────┘ └─────────┘ └─────────┘ └─────────┘
    now = 150ms → 检查桶1 → S1, S5 过期
```

### 7.4 心跳与超时时间的关系

```
    sessionTimeout = 40000ms (40秒)
    客户端: 每 20 秒（超时时间的一半）发送一次 Ping
    
    ────┬────┬────┬────┬────┬────┬────┬────► 时间
        │    │    │    │    │    │    │
       Ping Ping Ping Ping Ping Ping Ping
        20s  20s  20s  20s  20s  20s
    
    如果连续 40 秒没收到服务端响应 → 会话过期
    服务端: 每 tickTime（默认 2000ms）检查一次过期
```

### 7.5 临时节点清理

```java
// 会话过期时触发
public void expire(long sessionId) {
    close(sessionId);
    // 提交 closeSession 事务
    Request si = new Request(null, sessionId, 
        OpCode.closeSession, -1, null, null);
    submitRequest(si);
}

// FinalRequestProcessor 处理 closeSession
case closeSession: {
    // 删除该会话的所有临时节点
    zk.getZKDatabase().getDataTree().killEphemerals(sessionId);
    // 触发 NodeDeleted Watch
}
```

---

## 第八部分：请求处理链

### 8.1 请求处理链概述

Zookeeper 使用**责任链模式**处理请求。不同角色有不同的处理链。

```
          Leader 的请求处理链
          
    请求 ──► LeaderRequestProcessor (生成 ZXID)
             │
             ▼
          PrepRequestProcessor (请求预处理 + ACL 检查)
             │
             ▼
          ProposalRequestProcessor (发起 ZAB Proposal)
             │
             ▼
          CommitProcessor (等待过半 ACK)
             │
             ▼
          FinalRequestProcessor (应用到内存树 + 触发 Watch + 响应)

          Follower 的请求处理链
          
    请求 ──► FollowerRequestProcessor
             │ ├── 读请求 → 直接 FinalRequestProcessor
             │ └── 写请求 → 转发给 Leader
             ▼
          CommitProcessor (等待 Leader 的 Commit)
             │
             ▼
          FinalRequestProcessor (应用 + 响应)
```

### 8.2 PrepRequestProcessor 源码

```java
// PrepRequestProcessor.java
protected void pRequest(Request request) {
    checkACL(request);
    switch (request.getType()) {
        case OpCode.create:
            CreateRequest createRequest = ...;
            validatePath(createRequest.getPath());
            // 检查父节点存在性
            // 检查 ACL
            // 检查子节点是否已存在
            // 处理顺序节点
            CreateTxn txn = new CreateTxn(path, data, ...);
            request.setTxnHeader(new TxnHeader(
                request.getSessionId(), request.getCxid(),
                -1, System.currentTimeMillis(), OpCode.create));
            request.setTxn(txn);
            break;
        case OpCode.setData:
            // 版本检查（乐观锁）
            if (setDataRequest.getVersion() != -1 &&
                node.stat.getVersion() != setDataRequest.getVersion()) {
                throw new KeeperException.BadVersionException();
            }
            break;
    }
    nextProcessor.processRequest(request);
}
```

### 8.3 ProposalRequestProcessor 源码

```java
// ProposalRequestProcessor.java
public void processRequest(Request request) {
    if (request.getHdr() != null) {
        leader.propose(request); // 发起 ZAB Proposal
    }
    nextProcessor.processRequest(request); // 传给 CommitProcessor
}

// Leader.propose()
public void propose(Request request) {
    long zxid = zkDb.getNextZxid();
    request.getHdr().setZxid(zxid);
    byte[] data = SerializeUtils.serializeTxn(
        request.getTxnHeader(), request.getTxn());
    QuorumPacket proposal = new QuorumPacket(
        Leader.PROPOSAL, zxid, data, null);
    // 写入 Leader 的事务日志
    zkDb.getLogWriter().append(request);
    // 广播给所有 Follower
    for (LearnerHandler f : getLearners()) {
        f.queuePacket(proposal);
    }
    // Leader 自己也 ACK
    Proposal p = new Proposal(request, zxid);
    p.addAck(self.getId());
    proposals.put(zxid, p);
}
```

### 8.4 CommitProcessor 源码

```java
// CommitProcessor.java
public class CommitProcessor extends ZooKeeperCriticalThread 
        implements RequestProcessor {
    private final LinkedBlockingQueue<Request> queuedRequests;
    private final LinkedBlockingQueue<CommitProposal> committedRequests;
    private final Map<Long, Request> pendingRequests;
    
    @Override
    public void run() {
        while (!stopped) {
            Request request = queuedRequests.peek();
            CommitProposal committed = committedRequests.peek();
            if (committed != null) {
                committedRequests.remove();
                nextProcessor.processRequest(committed.request);
            }
        }
    }
    
    public void commit(long zxid) {
        Request request = pendingRequests.remove(zxid);
        if (request != null) {
            committedRequests.add(new CommitProposal(zxid, request));
        }
        notifyAll();
    }
}
```

### 8.5 FinalRequestProcessor 源码

```java
// FinalRequestProcessor.java
public void processRequest(Request request) {
    switch (request.getType()) {
        case OpCode.create:
            zkDb.processTxn(request.getTxnHeader(), (CreateTxn) request.getTxn());
            cnxn.sendResponse(new CreateResponse(path));
            break;
        case OpCode.setData:
            zkDb.processTxn(request.getTxnHeader(), (SetDataTxn) request.getTxn());
            // 触发 Watch（NodeDataChanged）
            zkDb.getDataTree().triggerWatch(path, EventType.NodeDataChanged);
            break;
        case OpCode.delete:
            zkDb.processTxn(request.getTxnHeader(), (DeleteTxn) request.getTxn());
            zkDb.getDataTree().triggerWatch(path, EventType.NodeDeleted);
            zkDb.getDataTree().triggerWatch(parentPath, EventType.NodeChildrenChanged);
            break;
        case OpCode.getData:
            // 读取数据
            DataNode node = zkDb.getNode(path);
            if (request.getWatch()) {
                zkDb.getDataTree().addWatch(path, new ServerCnxn(cnxn));
            }
            cnxn.sendResponse(new GetDataResponse(node.data, node.stat));
            break;
        case OpCode.closeSession:
            zkDb.getDataTree().killEphemerals(request.getSessionId());
            break;
    }
}
```

### 8.6 请求处理链的顺序保证

```
    关键约束: 所有请求必须按 ZXID 顺序应用
    
    Client                 Leader              Follower
      │ create("/a")         │                     │
      ├─────────────────────►│ propose zxid=1      │
      │                      ├────────────────────►│
      │                      │◄──── ACK ──────────┤
      │                      │ commit zxid=1       │
      │                      ├────────────────────►│ apply(zxid=1)
      │ create("/b")         │                     │
      ├─────────────────────►│ propose zxid=2      │
      │                      ├────────────────────►│
      │                      │◄──── ACK ──────────┤
      │                      │ commit zxid=2       │
      │                      ├────────────────────►│ apply(zxid=2)
      
    保证: Follower 先 apply zxid=1，再 apply zxid=2 → 全局有序
```

---

## 第九部分：持久化机制

### 9.1 持久化概述

| 机制 | 说明 | 触发条件 |
|------|------|----------|
| **事务日志** (TxnLog) | 记录每个写操作的完整事务记录 | 每次写操作 |
| **数据快照** (SnapLog) | 每隔一段时间保存完整内存树 | snapCount 次事务后 |

```
    /data/version-2/
    ├── log.1              ← 事务日志 [zxid 1 ~ 100]
    ├── log.101            ← 事务日志 [zxid 101 ~ 200]
    ├── snapshot.100      ← 快照 (zxid=100 时的数据)
    ├── log.201            ← 事务日志 [zxid 201 ~ 300]
    ├── snapshot.200      ← 快照 (zxid=200 时的数据)
    
    恢复流程:
    1. 找到最新的快照 snapshot.200 → 恢复到 zxid=200
    2. 重放 log.201 中的事务 → 恢复到最新状态
```

### 9.2 事务日志格式

```java
// FileTxnLog.java
public synchronized boolean append(TxnHeader hdr, Record txn) {
    if (logStream == null) {
        String logFile = "log." + Long.toHexString(hdr.getZxid());
        logStream = new FileOutputStream(logFile, false);
    }
    // 写入文件头（如果是新文件）
    // 写入事务头
    outputArchive.writeRecord(hdr, "hdr");
    // 写入事务体
    outputArchive.writeRecord(txn, "txn");
    // 写入 CRC32 校验
    // flush + fsync
    logStream.getChannel().force(false);
}

// 日志文件格式:
// ┌──────────┬──────────┬──────────┬──────────┬──────────┐
// │FileHeader│ TxnHeader│ TxnBody  │  CRC32   │ TxnHeader│ ...
// │ (4+4+8)  │ (固定大小)│ (变长)   │ (8 bytes)│          │
// └──────────┴──────────┴──────────┴──────────┴──────────┘
```

### 9.3 数据快照机制

```java
// FileSnap.java
public synchronized void serialize(DataTree dataTree,
        ConcurrentHashMap<Long, Integer> sessions) {
    long zxid = dataTree.getLastProcessedZxid();
    String snapFile = "snapshot." + Long.toHexString(zxid);
    // 写入文件头
    // 序列化会话信息
    // 序列化 DataTree
    // 写入 CRC32 校验
    // flush + fsync
}

// 反序列化恢复数据
public long deserialize(DataTree dataTree,
        ConcurrentHashMap<Long, Integer> sessions) {
    // 找到最新的快照文件
    // 读取文件头
    // 读取会话信息
    // 反序列化 DataTree
    // 校验 CRC
    return dataTree.getLastProcessedZxid();
}
```

### 9.4 数据恢复流程

```java
// ZKDatabase.java
public long loadDataBase() throws IOException {
    // 1. 从最新快照恢复
    long zxid = snapLog.deserialize(dataTree, sessionsWithTimeouts);
    // 2. 重放事务日志
    txnLog.replay(zxid, replayer);
    // 3. 恢复临时节点索引
    dataTree.rebuildEphemeralIndex();
    return lastProcessedZxid;
}
```

```
    时间线:  快照        事务日志
             │           │  │  │  │
             ▼           ▼  ▼  ▼  ▼
    ────────┬───────────┬──┬──┬──┬──┬────────────►
    zxid:  200          201 202 203 204 (当前)
    
    1. 读取 snapshot.200 → 恢复到 zxid=200
    2. 重放 log.201~204  → 恢复到最新
    3. 恢复临时节点索引
    4. 恢复完成，lastProcessedZxid = 204
```

---

## 第十部分：客户端与 Curator

### 10.1 原生客户端的问题

1. Watch 是一次性的，每次触发后需要手动重新注册
2. 会话重连需要手动处理
3. 没有递归创建节点的能力
4. API 不友好（同步/异步混用）

### 10.2 Curator 客户端

```java
// Curator 客户端使用
RetryPolicy retryPolicy = new ExponentialBackoffRetry(1000, 3);
CuratorFramework client = CuratorFrameworkFactory.builder()
    .connectString("host:2181")
    .sessionTimeoutMs(30000)
    .connectionTimeoutMs(10000)
    .retryPolicy(retryPolicy)
    .namespace("myapp")
    .build();
client.start();

// 递归创建节点
client.create()
    .creatingParentsIfNeeded()
    .withMode(CreateMode.PERSISTENT)
    .forPath("/app1/config", "value".getBytes());

// 使用 Cache（自动重新注册 Watch）
NodeCache nodeCache = new NodeCache(client, "/config");
nodeCache.getListenable().addListener(() -> {
    ChildData data = nodeCache.getCurrentData();
    if (data != null) {
        System.out.println("Data changed: " + new String(data.getData()));
    }
});
nodeCache.start(true);

// PathChildrenCache: 监听子节点变化
PathChildrenCache pathCache = new PathChildrenCache(client, "/services", true);
pathCache.getListenable().addListener((client, event) -> {
    switch (event.getType()) {
        case CHILD_ADDED:
            System.out.println("Service added");
            break;
        case CHILD_REMOVED:
            System.out.println("Service removed");
            break;
    }
});
pathCache.start();

// TreeCache: 递归监听整棵子树
TreeCache treeCache = new TreeCache(client, "/app");
treeCache.getListenable().addListener((client, event) -> {
    System.out.println("Event: " + event.getType());
});
treeCache.start();
```

### 10.3 Curator 分布式锁

```java
// InterProcessMutex — Curator 可重入分布式锁
InterProcessMutex lock = new InterProcessMutex(client, "/locks/order-lock");
if (lock.acquire(5, TimeUnit.SECONDS)) {
    try {
        doBusinessLogic();
    } finally {
        lock.release();
    }
}
```

**InterProcessMutex 底层原理**：

```
    1. 创建临时顺序节点: /locks/order-lock/lock-00000001
    2. 获取所有子节点列表
    3. 如果自己是序号最小的 → 获得锁
    4. 如果不是 → 监听前一个节点的删除事件
    5. 前一个节点删除 → 收到通知 → 检查自己是否最小 → 获得锁
    6. 可重入: ThreadLocal 记录重入次数
    
    /locks/order-lock/
    ├── lock-00000001 (Client A) ← 最小，获得锁
    ├── lock-00000002 (Client B) ← 监听 lock-00000001
    ├── lock-00000003 (Client C) ← 监听 lock-00000002
    └── lock-00000004 (Client D) ← 监听 lock-00000003
    
    Client A 释放锁 → 删除 lock-00000001
    → Client B 收到通知 → 检查自己是第一个 → 获得锁
```

### 10.4 Curator Leader 选举

```java
LeaderSelector leaderSelector = new LeaderSelector(
    client, "/elections/leader", new LeaderSelectorListener() {
    @Override
    public void takeLeadership() {
        // 当选 Leader 后执行
        System.out.println("I am the leader!");
        while (true) {
            Thread.sleep(1000);
        }
    }
});
leaderSelector.autoRequeue();
leaderSelector.start();
```

---

## 第十一部分：集群动态配置与 Observer

### 11.1 动态配置

Zookeeper 3.5+ 支持**动态集群配置**——无需重启即可增减节点。

```
    1. 初始集群配置
       /zookeeper/config:
       server.1=host1:2888:3888:participant
       server.2=host2:2888:3888:participant
       server.3=host3:2888:3888:participant
    
    2. 添加新节点
       reconfig(add=server.4=host4:2888:3888:participant)
       → ZAB 协议广播配置变更 → 新节点加入集群
    
    3. 移除旧节点
       reconfig(remove=server.1)
       → 节点 1 被移除 → 不影响集群正常运作
```

### 11.2 Observer 节点

```
    场景: 读请求量大，需要扩展读能力
    但不想增加选举和写投票的节点数
    
    ┌─────────┐  ┌─────────┐  ┌─────────┐
    │ Leader   │◄─►│Follower │◄─►│Follower │ ← 参与选举和投票
    └─────────┘  └─────────┘  └─────────┘
         ▲          ▲          ▲
    ┌────┴────┐┌────┴────┐┌────┴────┐
    │Observer ││Observer ││Observer │ ← 只读，不参与选举和投票
    └─────────┘└─────────┘└─────────┘
    
    特点:
    1. 不参与 Leader 选举
    2. 不参与写投票（Proposal ACK）
    3. 接收 Leader 的 Proposal 并应用
    4. 处理读请求
    5. 可以跨机房部署
```

---

## 第十二部分：典型应用场景

### 12.1 分布式锁

```
    方案 1: 简单锁（非公平，有羊群效应）
    所有客户端尝试 create("/lock", EPHEMERAL)
    只有一个成功 → 获得锁
    失败的 → getChildren("/lock", watch)
    锁释放 → 触发所有客户端的 Watch → 所有客户端再次竞争
    问题: 羊群效应
    
    方案 2: 公平锁（顺序临时节点）← 推荐方案
    1. create("/lock/node-", EPHEMERAL_SEQUENTIAL)
    2. 获取所有子节点列表
    3. 如果自己是最小的 → 获得锁
    4. 如果不是 → exists("/lock/node-" + (mySeq - 1), watch)
    5. 前一个节点删除 → 收到通知 → 检查是否最小 → 获得锁
    
    优点: 无羊群效应，只有下一个获得锁的客户端被唤醒
```

### 12.2 配置中心

```
    /config/
    ├── /config/database
    │   ├── /config/database/url    = "jdbc:..."
    │   ├── /config/database/user   = "root"
    │   └── /config/database/pass   = "xxx"
    ├── /config/redis
    │   ├── /config/redis/host     = "10.0.0.1"
    │   └── /config/redis/port     = "6379"
    
    1. 应用启动时读取配置 + 注册 Watch
    2. 运维修改配置 → setData
    3. 所有应用收到 Watch 通知 → 重新读取 → 重新注册 Watch
```

### 12.3 Leader 选举

```
    方案: 临时节点 + Watch 机制
    
    1. 所有实例尝试 create("/elections/master", EPHEMERAL)
       → 只有一个成功 → 成为 Master
    2. 失败的 → exists("/elections/master", watch=true)
    3. Master 宕机 → 临时节点自动删除 → 触发 Watch
    4. 所有等待的实例再次竞争 → 新 Master 产生
```

### 12.4 服务注册与发现

```
    /services/
    ├── /services/user-service
    │   ├── /services/user-service/provider-00000001  ← 临时节点
    │   │   数据: {"host":"10.0.0.1","port":8080}
    │   ├── /services/user-service/provider-00000002
    │   │   数据: {"host":"10.0.0.2","port":8080}
    └── /services/order-service
        └── /services/order-service/provider-00000001
    
    服务提供者: 启动时创建临时节点，下线时自动删除
    服务消费者: getChildren + Watch，列表变化时更新本地缓存
    
    这就是 Dubbo 使用 Zookeeper 注册中心的基本原理
```

### 12.5 分布式队列

```
    /queue/
    ├── task-00000001  ← "task data 1"
    ├── task-00000002  ← "task data 2"
    
    生产者: create("/queue/task-", data, PERSISTENT_SEQUENTIAL)
    消费者: getChildren → 取最小的 → delete（乐观锁确保只消费一次）
```

### 12.6 分布式屏障（Barrier）

```
    /barrier/
    └── ready  ← 屏障标志节点
    
    1. 初始化: 创建 /barrier/ready
    2. 每个节点完成后: create("/barrier/node-", EPHEMERAL_SEQUENTIAL)
    3. 检查子节点数量 >= expected_count → 删除 /barrier/ready
    4. /barrier/ready 被删除 → 所有等待的节点继续执行
```

---

## 第十三部分：ZAB vs Raft vs Paxos 对比

### 13.1 三种共识协议对比

| 维度 | ZAB | Raft | Paxos |
|------|-----|------|-------|
| 设计目标 | 主备数据同步 | 通用共识协议 | 理论证明 |
| Leader 角色 | ✅ 有 | ✅ 有 | ❌ 无 Leader |
| 选举算法 | FastLeaderElection | 随机超时 + RequestVote | 无选举 |
| 投票过半 | ✅ Quorum | ✅ Majority | ✅ Quorum |
| 日志连续性 | ✅ 连续 | ✅ 连续 | ❌ 可空洞 |
| 日志编号 | ZXID | LogIndex | BallotNum |
| 任期编号 | epoch | term | BallotNum |
| 数据同步 | DIFF/TRUNC/SNAP | Log matching | 日志补全 |
| 提交保证 | 顺序提交 | 顺序提交 | 无顺序保证 |
| 脑裂防护 | epoch | term | BallotNum |
| 实际应用 | Zookeeper | Etcd, Consul | Chubby |
| 可读性 | 中等 | 高 | 低 |

### 13.2 ZAB vs Raft 详细对比

```
    选举阶段:
    ZAB:
    ├── 广播 (myid, zxid, epoch)
    ├── 比较: epoch > zxid > myid
    └── 过半同意 → 选举完成
    
    Raft:
    ├── 自增 term，投自己一票
    ├── 广播 RequestVote RPC
    ├── 收到过半票 → 成为 Leader
    └── 心跳维持 Leader 地位
    
    数据同步:
    ZAB:
    ├── 比较 Follower 的 lastZxid
    ├── DIFF: 发送差异事务
    ├── TRUNC: 截断多余事务
    └── SNAP: 发送完整快照
    
    Raft:
    ├── prevLogIndex + prevLogTerm 验证
    ├── 如果不匹配 → 删除冲突日志
    └── 发送缺失的日志
```

### 13.3 ZAB 的独特优势

```
    ZAB 相比 Raft 的优势:
    1. 崩溃恢复更快 — 只需比较 ZXID 即可确定数据差异
    2. 顺序保证更强 — ZXID 全局连续递增，无日志空洞
    3. 专为 ZK 设计 — 优化了 ZK 的读写模型
    
    Raft 相比 ZAB 的优势:
    1. 更易于理解 — 设计目标是可理解性
    2. 更成熟的生态 — Etcd, Consul, TiKV 等广泛使用
    3. 更好的日志压缩 — Snapshot + Log Compaction 标准方案
```

---

## 第十四部分：性能优化与最佳实践

### 14.1 JVM 调优

```
    # 独立部署（推荐）
    -Xms4g -Xmx4g                    # 堆大小 4G
    -XX:+UseG1GC                     # G1 收集器
    -XX:MaxGCPauseMillis=200         # GC 暂停 < 200ms
    -XX:+ParallelRefProcEnabled     # 并行引用处理
    -XX:+HeapDumpOnOutOfMemoryError # OOM 时 dump
    -XX:HeapDumpPath=/data/logs/zk_dump.hprof
    
    关键: -Xms 和 -Xmx 设为相同值，避免堆动态扩展
    推荐: 堆大小不超过物理内存的 75%
```

### 14.2 关键参数调优

```
    # zoo.cfg 核心参数
    
    # 基本时间单元（ms）
    tickTime=2000
    
    # Follower 初始连接 Leader 的超时时间 = tickTime × initLimit
    initLimit=10                    # 20秒
    
    # Follower 与 Leader 同步的超时时间 = tickTime × syncLimit
    syncLimit=5                     # 10秒
    
    # 数据目录
    dataDir=/data/zookeeper/data
    
    # 事务日志目录（建议单独磁盘）
    dataLogDir=/data/zookeeper/log
    
    # 客户端连接端口
    clientPort=2181
    
    # 最大客户端连接数
    maxClientCnxns=60
    
    # 保留的事务日志文件数
    autopurge.snapRetainCount=3
    
    # 自动清理间隔（小时）
    autopurge.purgeInterval=1
    
    # 快照触发事务数
    snapCount=100000
    
    # 最小/最大会话超时时间
    minSessionTimeout=4000
    maxSessionTimeout=40000
    
    # 集群配置
    server.1=host1:2888:3888:participant
    server.2=host2:2888:3888:participant
    server.3=host3:2888:3888:participant
```

### 14.3 磁盘优化

```
    1. 事务日志单独磁盘
       dataLogDir 指向单独的 SSD
       事务日志是顺序写，SSD 大幅提升性能
    
    2. 快照可以放在 HDD
       dataDir 指向 HDD
       快照频率低，对性能影响小
    
    3. 禁用 atime
       mount -o noatime,nodiratime /data
    
    4. 文件系统选择
       推荐: ext4 或 xfs
       避免: zfs（对 ZK 的顺序写不友好）
```

### 14.4 网络优化

```
    1. 集群节点间网络延迟 < 1ms
    2. 使用独立网卡用于集群通信
    3. TCP 参数优化:
       net.core.somaxconn = 2048
       net.ipv4.tcp_max_syn_backlog = 2048
       net.ipv4.tcp_tw_reuse = 1
```

### 14.5 最佳实践

```
    部署:
    ├── 集群节点数: 3 或 5（奇数，过半计算方便）
    ├── JVM 堆: 4~8G（不要太大会导致 GC 暂停长）
    ├── 事务日志: 独立 SSD
    └── 网络: 集群节点间低延迟
    
    使用:
    ├── ZNode 数据: < 1KB（最大 1MB）
    ├── Watch 数量: 单 path < 100 个 Watcher
    ├── 临时节点: 会话过期自动清理，用于服务注册
    ├── 顺序节点: 用于分布式锁和队列
    └── 避免频繁创建/删除大量节点
    
    监控:
    ├── zk_avg_latency: 平均延迟 < 10ms
    ├── zk_max_latency: 最大延迟 < 100ms
    ├── zk_outstanding_requests: 堆积请求数
    ├── zk_watch_count: Watch 数量
    ├── zk_ephemerals_count: 临时节点数量
    ├── zk_num_alive_connections: 活跃连接数
    └── zk_leader: 是否为 Leader
    
    告警:
    ├── Leader 切换 → 立即告警
    ├── 平均延迟 > 50ms → 告警
    ├── Watch 数量 > 100000 → 告警
    └── 堆积请求 > 100 → 告警
```

---

## 第十五部分：面试高频题 20 问

### Q1: Zookeeper 是什么？有哪些典型应用场景？

**A**: Zookeeper 是一个分布式协调服务，提供配置管理、命名服务、分布式锁、Leader 选举、集群管理、服务注册与发现等能力。

典型应用场景：
1. **配置中心** — 配置存储 + 变更通知（Watch 机制）
2. **分布式锁** — 临时顺序节点实现公平锁
3. **Leader 选举** — 临时节点 + Watch
4. **服务注册与发现** — 临时节点注册服务，消费者订阅子节点变化
5. **分布式队列** — 顺序持久节点
6. **分布式屏障** — 等待所有节点到达同步点

### Q2: Zookeeper 的 ZAB 协议是什么？和 Raft 有什么区别？

**A**: ZAB（ZooKeeper Atomic Broadcast）是 ZK 专用的原子广播协议，保证集群数据一致性。

**与 Raft 的区别**：
1. **选举比较** — ZAB 按 epoch > ZXID > myid 选举，Raft 按 term + 日志长度选举
2. **数据同步** — ZAB 有 DIFF/TRUNC/SNAP 三种策略，Raft 通过 prevLogIndex 匹配
3. **日志连续性** — ZAB 的 ZXID 全局连续递增无空洞，Raft 日志可能有空洞
4. **设计目标** — ZAB 专为 ZK 主备同步设计，Raft 是通用共识协议

### Q3: Zookeeper 的 Watch 机制有什么特点？为什么是一次性的？

**A**: Watch 特点：
1. **一次性触发** — 触发后自动删除，需要重新注册
2. **轻量级** — 只通知事件类型和路径，不传数据
3. **客户端有序** — 客户端收到的 Watch 事件与服务端事件顺序一致
4. **通过 TCP 连接传输** — 不需要额外连接

**一次性的原因**：
1. 简化服务端实现——不需要管理 Watch 生命周期
2. 避免大量 Watch 堆积——防止内存溢出
3. 客户端收到通知后重新注册即可

### Q4: Zookeeper 如何保证数据一致性？

**A**: 通过 ZAB 协议：
1. **所有写请求由 Leader 处理** — 保证全局有序
2. **ZAB 二阶段提交** — Proposal → 过半 ACK → Commit
3. **ZXID 单调递增** — 保证事务全局有序
4. **Leader 选举选最大 ZXID** — 保证新 Leader 数据最完整
5. **数据同步机制** — DIFF/TRUNC/SNAP 保证 Follower 数据一致

**注意**：ZK 保证的是**顺序一致性**，不是强一致性。Follower 的读请求可能读到旧数据。如果需要强一致读，需要先调用 `sync()`。

### Q5: Zookeeper 的 Leader 选举过程？

**A**: 
1. 所有节点进入 LOOKING 状态，增加逻辑时钟
2. 每个节点投票给自己 (myid, zxid, epoch)
3. 广播选票给其他节点
4. 收到其他节点选票后比较：epoch > ZXID > myid
5. 如果对方更优，更新自己的选票并重新广播
6. 如果自己更优，记录对方选票
7. 当某个节点获得过半选票时，选举完成
8. 获胜者成为 Leader，其他节点成为 Follower

### Q6: Zookeeper 的过半机制为什么能防止脑裂？

**A**: 过半机制的数学保证：N 个节点中，任意两个过半集合必有交集。

例如 5 节点集群需要 3 个同意。如果发生网络分区（3+2），只有 3 个节点的分区能达成过半继续工作，2 个节点的分区无法达成过半，自动停止写操作。因此不会出现两个分区同时写数据的情况，防止了脑裂。

### Q7: 临时节点和持久节点的区别？临时节点有什么用？

**A**: 
- **持久节点** — 客户端断开后节点依然存在
- **临时节点** — 客户端会话过期后自动删除

临时节点的用途：
1. **分布式锁** — 客户端宕机后锁自动释放
2. **Leader 选举** — Leader 宕机后临时节点自动删除，触发重新选举
3. **服务注册** — 服务下线后注册信息自动删除

**注意**：临时节点不能有子节点。

### Q8: Zookeeper 的 ZXID 是什么？为什么需要 epoch？

**A**: ZXID 是 64 位事务 ID，由 epoch（高 32 位）+ counter（低 32 位）组成。

- **epoch** 是 Leader 的任期编号，每次 Leader 切换 +1
- **counter** 是当前 epoch 内的递增序号

epoch 的作用：防止旧 Leader 恢复后用旧 epoch 提交数据（脑裂防护）。新 Leader 的 epoch 比旧 Leader 大，旧 Leader 的 Proposal 会被 Follower 拒绝。

### Q9: Zookeeper 的数据同步有哪几种方式？

**A**: 三种方式：
1. **DIFF（差异同步）** — Follower 的 ZXID 在 Leader 的 [minCommittedLog, maxCommittedLog] 范围内，发送差异事务
2. **TRUNC（截断同步）** — Follower 的 ZXID 大于 Leader（脑裂场景），截断多余事务
3. **SNAP（快照同步）** — Follower 的 ZXID 太旧（小于 minCommittedLog），发送完整快照

### Q10: Zookeeper 如何实现分布式锁？有什么优化？

**A**: 
**简单方案**（有羊群效应）：所有客户端争抢创建同一个临时节点，失败的监听该节点删除事件。节点删除后所有客户端被唤醒竞争。

**优化方案**（公平锁，推荐）：
1. 创建临时顺序节点
2. 获取所有子节点列表
3. 如果自己序号最小 → 获得锁
4. 否则监听前一个节点的删除事件
5. 前一个节点删除 → 收到通知 → 检查是否最小 → 获得锁

优点：无羊群效应，只有下一个获得锁的客户端被唤醒。

### Q11: Zookeeper 的 Observer 是什么？有什么用？

**A**: Observer 是不参与选举和投票的只读节点。

用途：
1. **扩展读能力** — 不影响写性能（不参与投票）
2. **跨机房部署** — Observer 可以部署在远程机房，不影响集群选举
3. **不增加写延迟** — 普通 Follower 越多，写延迟越高（需要更多 ACK），Observer 不参与 ACK

### Q12: Zookeeper 为什么不适合存储大量数据？

**A**: 
1. **ZNode 数据限制 1MB** — 设计目标不是存储数据
2. **全内存存储** — DataTree 在内存中，数据量大导致内存消耗大
3. **快照序列化耗时** — 大量数据导致快照序列化/反序列化慢
4. **网络传输开销** — 数据变更时需要广播给所有 Follower

ZK 适合存储**少量元数据**（配置、路由信息、服务列表），不适合存储业务数据。

### Q13: Zookeeper 集群为什么推荐奇数节点？

**A**: 
1. **相同的容错能力** — 3 节点容忍 1 个宕机，4 节点也容忍 1 个宕机（需要 3 个 ACK），但多一个节点不增加容错
2. **更少的资源** — 3 节点 vs 4 节点，省一台机器
3. **更快的写入** — 3 节点需要 2 个 ACK，5 节点需要 3 个 ACK，奇数更优
4. **更稳定的选举** — 奇数节点不会出现平票

### Q14: Zookeeper 的持久化机制是什么？

**A**: 两种持久化：
1. **事务日志（TxnLog）** — 每次写操作都追加到事务日志，先写日志再应用内存（WAL）
2. **数据快照（SnapLog）** — 每处理 snapCount（默认 10 万）次事务后做一次快照

恢复流程：先加载最新快照，再重放快照之后的事务日志。

### Q15: Zookeeper 和 Redis 哪个更适合做分布式锁？

**A**: 

| 维度 | Zookeeper | Redis |
|------|----------|-------|
| 一致性 | CP（强一致） | AP（最终一致） |
| 可靠性 | 高（过半提交） | 中（主从异步复制可能丢锁） |
| 性能 | 中（每次写需要 ZAB 广播） | 高（内存操作） |
| 公平锁 | 原生支持（顺序节点） | 需要自己实现 |
| 锁释放 | 自动（临时节点） | 需要设置过期时间 + 看门狗 |

**结论**：对一致性要求高用 ZK，对性能要求高用 Redis。大部分互联网场景用 Redis（Redisson），金融场景用 ZK。

### Q16: Zookeeper 的请求处理链是什么？

**A**: Leader 的处理链：
1. **LeaderRequestProcessor** — 生成 ZXID
2. **PrepRequestProcessor** — 请求预处理 + ACL 检查 + 创建事务
3. **ProposalRequestProcessor** — 发起 ZAB Proposal
4. **CommitProcessor** — 等待过半 ACK
5. **FinalRequestProcessor** — 应用到内存树 + 触发 Watch + 响应客户端

Follower 的处理链：
1. **FollowerRequestProcessor** — 读请求直接处理，写请求转发给 Leader
2. **CommitProcessor** — 等待 Leader 的 Commit
3. **FinalRequestProcessor** — 应用 + 响应

### Q17: Zookeeper 的会话管理是怎样的？

**A**: 
1. 客户端连接时创建会话，协商超时时间
2. 客户端每隔 sessionTimeout/2 发送 Ping 心跳
3. 服务端用 SessionTracker 跟踪会话
4. 会话超时使用 ExpiryQueue 分桶机制检查
5. 会话过期时自动删除该会话的所有临时节点

### Q18: Zookeeper 和 Nacos 的区别？

**A**: 

| 维度 | Zookeeper | Nacos |
|------|----------|-------|
| 一致性 | CP（ZAB） | AP（Distro）+ CP（Raft）可选 |
| 数据模型 | 树形 ZNode | KV + 服务模型 |
| 健康检查 | 会话心跳 | TCP/HTTP/自定义 |
| 配置中心 | Watch 机制 | 长轮询 + 推送 |
| 服务发现 | 临时节点 + Watch | 服务列表 + 推送 |
| 语言 | Java | Java |
| 生态 | 成熟 | Spring Cloud Alibaba |

### Q19: Zookeeper 如何实现配置中心？

**A**: 
1. 配置存储在 ZNode 中：`/config/database/url = "jdbc:..."`
2. 客户端读取配置并注册 Watch
3. 配置变更时触发 Watch，客户端收到通知
4. 客户端重新读取配置并重新注册 Watch
5. 使用 Curator NodeCache 自动重新注册 Watch

### Q20: Zookeeper 的瓶颈在哪里？如何优化？

**A**: 
**瓶颈**：
1. **写性能** — 每次写需要 ZAB 广播 + 过半 ACK + fsync，TPS 约 1~5 万
2. **JVM GC 暂停** — 导致心跳超时，触发 Leader 选举
3. **Watch 风暴** — 大量 Watch 触发时影响性能
4. **快照阻塞** — 快照序列化期间可能阻塞请求

**优化**：
1. 事务日志用独立 SSD
2. JVM 堆大小 4~8G，使用 G1GC
3. 集群节点数 3~5 个（奇数）
4. 减少 ZNode 数据量（< 1KB）
5. 使用 Observer 扩展读能力
6. 使用 Curator Cache 减少手动 Watch 管理

---

## 附录 A：Zookeeper 核心参数速查表

### 基本参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| tickTime | 2000ms | 基本时间单元 |
| initLimit | 10 | Follower 初始连接 Leader 的超时 tick 数 |
| syncLimit | 5 | Follower 与 Leader 同步的超时 tick 数 |
| dataDir | - | 数据目录（快照） |
| dataLogDir | - | 事务日志目录（建议独立 SSD） |
| clientPort | 2181 | 客户端连接端口 |
| maxClientCnxns | 60 | 最大客户端连接数 |

### 会话参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| minSessionTimeout | 2 × tickTime | 最小会话超时 |
| maxSessionTimeout | 20 × tickTime | 最大会话超时 |

### 快照与清理

| 参数 | 默认值 | 说明 |
|------|--------|------|
| snapCount | 100000 | 每多少次事务做一次快照 |
| autopurge.snapRetainCount | 3 | 保留的快照文件数 |
| autopurge.purgeInterval | 1 | 自动清理间隔（小时） |

### 集群参数

| 参数 | 说明 |
|------|------|
| server.N=host:port1:port2[:role] | 集群节点配置 |
| port1 | Follower 与 Leader 通信端口 |
| port2 | 选举端口 |
| role | participant（默认）或 observer |

### 性能参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| preAllocSize | 65536KB | 事务日志预分配大小 |
| forceSync | yes | 是否强制 fsync |
| jute.maxbuffer | 1048575 | ZNode 最大数据量（~1MB） |

---

## 附录 B：Zookeeper 常见问题排查

### B.1 Leader 频繁切换

```
原因:
1. JVM GC 暂停导致心跳超时
2. 网络抖动
3. 磁盘 I/O 瓶颈导致 fsync 慢

排查:
1. 检查 GC 日志: -Xlog:gc*
2. 检查网络延迟: ping 各节点
3. 检查磁盘 I/O: iostat -x 1
4. 检查 ZK 日志: grep "Leader election" zk.log

解决:
1. 优化 JVM（减小堆、用 G1GC）
2. 事务日志用独立 SSD
3. 调大 syncLimit 和 tickTime
```

### B.2 写延迟高

```
原因:
1. Follower ACK 慢（网络或磁盘）
2. 事务日志 fsync 慢
3. 快照阻塞

排查:
1. 检查各节点磁盘 I/O
2. 检查网络延迟
3. 检查是否有大量快照操作

解决:
1. 事务日志用独立 SSD
2. 增大 preAllocSize
3. 调整 snapCount
```

### B.3 Watch 失效

```
原因:
1. 会话过期导致所有 Watch 被清除
2. Watch 是一次性的，触发后需要重新注册
3. 网络断开导致 Watch 丢失

排查:
1. 检查会话状态
2. 检查客户端 Watch 注册逻辑
3. 使用 Curator Cache 自动管理

解决:
1. 使用持久 Watch（3.6+）
2. 使用 Curator NodeCache/PathChildrenCache
3. 会话重连后重新注册所有 Watch
```

### B.4 内存溢出

```
原因:
1. ZNode 数据量过大
2. Watch 数量过多
3. 临时节点未清理
4. 堆大小不足

排查:
1. 检查 ZNode 数量: echo "stat" | nc host 2181
2. 检查 Watch 数量: echo "wchs" | nc host 2181
3. 检查临时节点数量: echo "stat" | nc host 2181

解决:
1. 限制 ZNode 数据大小
2. 减少 Watch 数量
3. 增大 JVM 堆
4. 定期清理无用的持久节点
```

---

## 附录 C：与其他文档的衔接关系

```
                    文档关系图
                    
    ┌─────────────────────────────────────────────────────────────┐
    │                    Java 基础 / 并发                          │
    │  HashMap → ConcurrentHashMap → ThreadPoolExecutor         │
    │  → synchronized/AQS/ReentrantLock → volatile/JMM/单例      │
    │  → Java基础 → Java8新特性 → 并发同步工具                     │
    └──────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
    ┌─────────────────────────────────────────────────────────────┐
    │                    Spring 全家桶                             │
    │  IoC/DI → AOP → Spring Cloud(Nacos/Sentinel/Gateway)      │
    │  → MyBatis → Dubbo → 综合串讲                              │
    └──────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
    ┌─────────────────────────────────────────────────────────────┐
    │                    中间件                                    │
    │  MySQL(索引/EXPLAIN/事务锁) → Redis(数据结构/缓存锁集群)    │
    │  → Nginx → Netty → Elasticsearch → Zookeeper ← 你在这里     │
    └─────────────────────────────────────────────────────────────┘
    
    衔接关系:
    
    1. Zookeeper ←→ Dubbo
       Dubbo 使用 ZK 作为注册中心
       服务注册: create("/services/...", EPHEMERAL)
       服务订阅: getChildren + Watch
       《Dubbo源码深度解析》中的 RegistryProtocol 依赖 ZK
    
    2. Zookeeper ←→ Spring Cloud
       Spring Cloud Zookeeper 提供服务注册发现
       可替代 Nacos 作为注册中心
       《Spring_Cloud_MyBatis源码深度解析》中的 Nacos 可对比阅读
    
    3. Zookeeper ←→ Redis
       分布式锁: ZK（CP，强一致） vs Redis（AP，高性能）
       《Redis缓存问题与分布式锁集群深度解析》可对比阅读
    
    4. Zookeeper ←→ Kafka
       Kafka 早期使用 ZK 管理集群元数据
       Kafka 3.x+ 逐步移除 ZK 依赖（KRaft）
    
    5. Zookeeper 的 ZAB vs Redis Cluster 的 Gossip
       ZAB: 强一致共识协议（CP）
       Gossip: 最终一致协议（AP）
       《Redis缓存问题与分布式锁集群深度解析》可对比阅读
```

---

> **文档统计**: 共 23 份源码学习文档
> 
> | 领域 | 文档数 |
> |------|--------|
> | Java 基础/并发 | 6 份 |
> | Spring 全家桶 | 4 份 |
> | MyBatis | 1 份 |
> | Dubbo | 1 份 |
> | MySQL | 3 份 |
> | Redis | 2 份 |
> | Nginx | 1 份 |
> | Netty | 1 份 |
> | Elasticsearch | 1 份 |
> | Zookeeper | 1 份 |
> | 综合串讲 | 1 份 |
> | **合计** | **23 份** |

---

*本文档基于 Zookeeper 3.8.x 源码整理，涵盖架构设计、ZAB 协议、Leader 选举、数据同步、Watch 机制、会话管理、请求处理链、持久化、典型应用场景、ZAB vs Raft vs Paxos 对比、性能优化、面试高频题。*