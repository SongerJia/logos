# Kafka 底层原理深度解析 — 存储引擎 · ISR · 零拷贝 · 生产消费

> 本文档是《WorkBuddy 源码学习系列》第 25 份，系统解析 Kafka 底层原理。
> 建议配合《RocketMQ底层原理深度解析》对比阅读，理解两款 MQ 在存储、高可用、事务等方面的设计差异。

---

## 目录

- [第一部分：Kafka 架构全景](#第一部分kafka-架构全景)
  - [1.1 Kafka 是什么](#11-kafka-是什么)
  - [1.2 四大角色](#12-四大角色)
  - [1.3 核心概念](#13-核心概念)
  - [1.4 架构全景图](#14-架构全景图)
  - [1.5 Kafka vs 其他 MQ 速览](#15-kafka-vs-其他-mq-速览)
- [第二部分：Topic 与 Partition —— 分布式基础](#第二部分topic-与-partition--分布式基础)
  - [2.1 Topic 的物理存储模型](#21-topic-的物理存储模型)
  - [2.2 Partition 的分段存储（Log Segment）](#22-partition-的分段存储log-segment)
  - [2.3 稀疏索引 vs 密集索引](#23-稀疏索引-vs-密集索引)
  - [2.4 日志段文件详解](#24-日志段文件详解)
  - [2.5 LogSegment 源码结构](#25-logsegment-源码结构)
- [第三部分：消息存储引擎 —— 顺序写 + Page Cache + 零拷贝](#第三部分消息存储引擎--顺序写--page-cache--零拷贝)
  - [3.1 顺序写 vs 随机写](#31-顺序写-vs-随机写)
  - [3.2 Page Cache —— 操作系统的天然缓存](#32-page-cache--操作系统的天然缓存)
  - [3.3 零拷贝 sendfile](#33-零拷贝-sendfile)
  - [3.4 传统 4 次拷贝 vs 零拷贝 2 次拷贝](#34-传统-4-次拷贝-vs-零拷贝-2-次拷贝)
  - [3.5 Kafka 为什么快？—— 四大原因总结](#35-kafka-为什么快--四大原因总结)
- [第四部分：Producer —— 生产端原理](#第四部分producer--生产端原理)
  - [4.1 Producer 工作流程](#41-producer-工作流程)
  - [4.2 分区策略 Partition](#42-分区策略-partitioner)
  - [4.3 消息发送流程 send()](#43-消息发送流程-send)
  - [4.4 RecordAccumulator 双端队列批量发送](#44-recordaccumulator-双端队列批量发送)
  - [4.5 Sender 线程与 NetworkClient](#45-sender-线程与-networkclient)
  - [4.6 幂等性实现 Idempotent](#46-幂等性实现-idempotent)
  - [4.7 事务与 Exactly Once 语义](#47-事务与-exactly-once-语义)
  - [4.8 Ack 机制与可靠性](#48-ack-机制与可靠性)
- [第五部分：Consumer —— 消费端原理](#第五部分consumer--消费端原理)
  - [5.1 Consumer 工作流程](#51-consumer-工作流程)
  - [5.2 Consumer Group 与消费模型](#52-consumer-group-与消费模型)
  - [5.3 Rebalance 协议——最核心的机制](#53-rebalance-协议最核心的机制)
  - [5.4 GroupCoordinator 源码](#54-groupcoordinator-源码)
  - [5.5 偏移量提交 Offset Commit](#55-偏移量提交-offset-commit)
  - [5.6 __consumer_offsets 内部主题](#56-__consumer_offsets-内部主题)
- [第六部分：副本机制 —— ISR 与高可用](#第六部分副本机制--isr-与高可用)
  - [6.1 副本分布规则](#61-副本分布规则)
  - [6.2 ISR（In-Sync Replicas）](#62-isrin-sync-replicas)
  - [6.3 LEO 与 HW 水位线](#63-leo-与-hw-水位线)
  - [6.4 Leader 选举机制](#64-leader-选举机制)
  - [6.5 Unclean Leader Election](#65-unclean-leader-election)
  - [6.6 副本同步源码](#66-副本同步源码)
- [第七部分：Controller 与 KafkaController](#第七部分controller-与-kafkacontroller)
  - [7.1 Controller 是什么](#71-controller-是什么)
  - [7.2 Controller 选举](#72-controller-选举)
  - [7.3 Controller 的职责](#73-controller-的职责)
  - [7.4 PartitionStateMachine 与 ReplicaStateMachine](#74-partitionstatemachine-与-replicastatemachine)
  - [7.5 Controller 与 ZK 的交互](#75-controller-与-zk-的交互)
  - [7.6 Kafka 去 ZK 化——KRaft](#76-kafka-去-zk-化kraft)
- [第八部分：日志清理与压缩](#第八部分日志清理与压缩)
  - [8.1 基于时间的删除](#81-基于时间的删除)
  - [8.2 基于大小的删除](#82-基于大小的删除)
  - [8.3 Log Compaction——按 Key 压缩](#83-log-compaction按-key-压缩)
  - [8.4 Cleaner 线程源码](#84-cleaner-线程源码)
  - [8.5 CleanerPoint 与 Dirty Ratio](#85-cleanerpoint-与-dirty-ratio)
- [第九部分：Kafka 性能优化实战](#第九部分kafka-性能优化实战)
  - [9.1 Producer 端优化](#91-producer-端优化)
  - [9.2 Broker 端优化](#92-broker-端优化)
  - [9.3 Consumer 端优化](#93-consumer-端优化)
  - [9.4 OS 层面优化](#94-os-层面优化)
- [第十部分：Kafka vs RocketMQ 深度对比](#第十部分kafka-vs-rocketmq-深度对比)
  - [10.1 架构对比](#101-架构对比)
  - [10.2 存储机制对比](#102-存储机制对比)
  - [10.3 事务消息对比](#103-事务消息对比)
  - [10.4 消费模型对比](#104-消费模型对比)
  - [10.5 高可用对比](#105-高可用对比)
  - [10.6 性能对比](#106-性能对比)
  - [10.7 选型建议](#107-选型建议)
- [第十一部分：面试高频题 20 问](#第十一部分面试高频题-20-问)
- [附录](#附录)
  - [附录 A：Kafka 核心参数速查表](#附录-akafka-核心参数速查表)
  - [附录 B：Kafka 版本演进](#附录-bkafka-版本演进)
  - [附录 C：与已有文档衔接关系](#附录-c与已有文档衔接关系)

---

## 第一部分：Kafka 架构全景

### 1.1 Kafka 是什么

Kafka 是一个**分布式流处理平台**，不是简单的消息队列。它由 LinkedIn 开发，2011 年开源，现为 Apache 顶级项目。

Kafka 的三大能力：
1. **消息队列**：发布/订阅，削峰填谷
2. **流处理**：Kafka Streams API，实时计算
3. **存储系统**：持久化所有消息，可回溯消费

### 1.2 四大角色

| 角色 | 职责 | 核心组件 |
|------|------|----------|
| **Producer** | 生产消息 | KafkaProducer、RecordAccumulator、Sender |
| **Broker** | 存储转发 | LogManager、ReplicaManager、GroupCoordinator |
| **Consumer** | 消费消息 | KafkaConsumer、ConsumerCoordinator、Fetcher |
| **Zookeeper** | 集群协调 | Broker 注册、Controller 选举、Topic 配置 |

> 注：Kafka 2.8+ 支持 KRaft 模式，去 ZK 化，后文详述。

### 1.3 核心概念

```
┌─────────────────────────────────────────────────────────────────┐
│                          Kafka 核心概念                            │
├────────────┬────────────────────────────────────────────────────┤
│ Topic      │ 消息的逻辑分类，类似"表名"                             │
│ Partition  │ Topic 的物理分片，有序不可变的消息序列                    │
│ Segment    │ Partition 的物理分段，每个 Segment 是一个文件组          │
│ Offset     │ 消息在 Partition 中的唯一序号（64 位，单调递增）          │
│ Producer   │ 消息生产者，向指定 Topic 的指定 Partition 发送消息         │
│ Consumer   │ 消息消费者，从指定 Partition 拉取消息（Pull 模型）         │
│ Broker     │ Kafka 服务节点，存储 Partition 数据                     │
│ Replica    │ Partition 的副本，Leader + Follower                   │
│ ISR        │ 与 Leader 保持同步的副本集合                            │
│ Controller │ Broker 集群的管理者，负责 Leader 选举、分区重分配         │
└────────────┴────────────────────────────────────────────────────┘
```

### 1.4 架构全景图

```
     Producer1                Producer2                Producer3
         │                        │                        │
         │    ┌───────────────────┼───────────────────┐    │
         └────┤       发送消息（指定 Topic + Key）       ├────┘
              └───────────────────┼───────────────────┘
                                  │
              ┌───────────────────▼───────────────────┐
              │            Kafka Cluster               │
              │                                        │
              │  ┌─────────┐  ┌─────────┐  ┌───────┐  │
              │  │Broker 1 │  │Broker 2 │  │Broker 3│  │
              │  │         │  │         │  │       │  │
              │  │ P0(L)   │  │ P0(F)   │  │ P0(F) │  │
              │  │ P1(F)   │  │ P1(L)   │  │ P1(F) │  │
              │  │ P2(F)   │  │ P2(F)   │  │ P2(L) │  │
              │  └─────────┘  └─────────┘  └───────┘  │
              │                                        │
              │  Controller: Broker 1                  │
              └───────────────────┬───────────────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              │            ZooKeeper Cluster            │
              │   /brokers/ids, /brokers/topics,        │
              │   /controller, /consumers               │
              └────────────────────────────────────────┘

     Consumer Group A              Consumer Group B
  ┌────────┬────────┐         ┌────────┬────────┐
  │ C1     │ C2     │         │ C3     │ C4     │
  │ P0,P1  │ P2     │         │ P0,P2  │ P1     │
  └────────┴────────┘         └────────┴────────┘
```

### 1.5 Kafka vs 其他 MQ 速览

| 对比项 | Kafka | RocketMQ | RabbitMQ | ActiveMQ |
|--------|-------|----------|----------|----------|
| 定位 | 流处理+存储 | 业务消息 | 企业消息 | JMS 规范 |
| 吞吐量 | 百万级 | 十万级 | 万级 | 万级 |
| 延迟 | 毫秒级 | 毫秒级 | 微秒级 | 毫秒级 |
| 存储 | 磁盘持久化（日志型） | 磁盘持久化（CommitLog） | 内存/磁盘 | 内存/磁盘 |
| 消费模型 | Pull（长轮询） | Pull（长轮询） | Push/Pull | Push/Pull |
| 消息回溯 | ✓ 天然支持 | ✓ 支持 | ✗ | ✗ |
| 事务消息 | ✓（幂等+事务） | ✓（半消息） | ✗ | ✓ |
| 海量 Topic | 差（文件数多） | 好（单文件存储） | 好 | 中 |
| 顺序消息 | Partition 内有序 | Queue 内有序 | ✗ | ✗ |
| 社区活跃度 | 极高 | 高 | 高 | 低 |

---

## 第二部分：Topic 与 Partition —— 分布式基础

### 2.1 Topic 的物理存储模型

Kafka 的 Topic 在物理上被分为多个 Partition，每个 Partition 是一个独立的日志文件组。

```
Topic: user-events (3 Partitions, 3 Replicas)

                    Partition 0                    Partition 1
              ┌─────────────────┐            ┌─────────────────┐
              │    Segment 0    │            │    Segment 0    │
              │  .log   .index  │            │  .log   .index  │
              │  .timeindex     │            │  .timeindex     │
              ├─────────────────┤            ├─────────────────┤
              │    Segment 1    │            │    Segment 1    │
              │  .log   .index  │            │  .log   .index  │
              │  .timeindex     │            │  .timeindex     │
              ├─────────────────┤            ├─────────────────┤
              │    Segment 2    │            │    Segment 2    │
              │  .log   .index  │            │  .log   .index  │
              │  .timeindex     │            │  .timeindex     │
              └─────────────────┘            └─────────────────┘

              Partition 2: 同理

物理目录结构:
/tmp/kafka-logs/
  ├── user-events-0/        ← Partition 0
  │   ├── 00000000000000000000.log
  │   ├── 00000000000000000000.index
  │   ├── 00000000000000000000.timeindex
  │   ├── 00000000000000000500.log       ← 新 Segment（500 开头）
  │   ├── 00000000000000000500.index
  │   └── 00000000000000000500.timeindex
  ├── user-events-1/        ← Partition 1
  └── user-events-2/        ← Partition 2
```

### 2.2 Partition 的分段存储（Log Segment）

**核心原理**：Partition 不是一个巨大的文件，而是被切分为多个 Segment。

```
Partition 内部的 Segment 切分:

Offset: 0              500             1000            1500
        │    Segment-0   │   Segment-1   │   Segment-2   │
        │ baseOffset=0   │ baseOffset=500│ baseOffset=1000│
        │                │               │               │
        │ [msg0..msg499] │[msg500..msg999]│[msg1000..]   │
        └────────────────┴───────────────┴───────────────┘
        活跃 Segment（Active Segment）= Segment-2（正在写入）

每个 Segment 包含 3 个文件:
  1. .log           → 消息数据文件
  2. .index         → 偏移量索引文件（稀疏索引）
  3. .timeindex     → 时间戳索引文件
```

**为什么要分段？**
1. **删除方便**：直接删除旧 Segment 文件，O(1)
2. **清理方便**：Log Compaction 只需要处理旧 Segment
3. **读写隔离**：Active Segment 正在写，旧 Segment 只读，避免写入影响查询
4. **索引可控**：每个 Segment 的索引文件大小可控

### 2.3 稀疏索引 vs 密集索引

Kafka 使用**稀疏索引**，而非密集索引。这是 Kafka 与 MySQL 索引设计的核心差异。

```
密集索引（MySQL B+Tree）:
    叶子节点包含所有记录，每个 key 都有索引

稀疏索引（Kafka .index）:
    每隔 N 条消息（由 log.index.interval.bytes 控制，默认 4KB）记录一条索引

类比理解:
    ┌──────────────────────────────────────────────┐
    │  一本书的目录（密集索引）：                        │
    │  第1页, 第2页, 第3页, ... 每个页面都有            │
    │                                              │
    │  一本书的章节标题（稀疏索引）：                      │
    │  第1章 → 第1页，第2章 → 第50页，第3章 → 第100页    │
    │  要找第 75 页？先定位到第2章(第50页)，然后顺序翻      │
    └──────────────────────────────────────────────┘
```

**稀疏索引的查找过程**：

```
步骤：
  1. 二分查找 .index 文件，找到 ≤ targetOffset 的最大索引条目
  2. 获取该条目对应的 .log 文件的物理位置（position）
  3. 从 position 开始，顺序扫描 .log 文件，直到找到 targetOffset

示例：查找 offset=378 的消息

    .index 文件（稀疏索引）:
    ┌──────────────────────────────────────────┐
    │ relativeOffset=100 → position=0          │
    │ relativeOffset=200 → position=4096       │
    │ relativeOffset=300 → position=8192       │
    │ relativeOffset=400 → position=12288      │  ← 找到这条！
    │ relativeOffset=500 → position=16384      │
    └──────────────────────────────────────────┘

    .log 文件（物理存储）:
    position 12288: offset=400, msg="xxx"
    position 12500: offset=401, msg="yyy"    ← 顺序扫描
    position 12700: offset=402, msg="zzz"
    ...
    实际要找的是 offset=378，从 400 往前扫描即可（或更准确地说，
    索引存的是最近的 ≤ target 位置，需要从小位置向前扫描到大位置）

注意：Kafka 的相对偏移量（relativeOffset）= 绝对偏移量 - baseOffset
```

### 2.4 日志段文件详解

```
LogSegment 文件说明:

┌──────────────────────────────────────────────────────────────┐
│                         .log 文件                             │
├──────────────────────────────────────────────────────────────┤
│ 实际存储消息的二进制文件。每条消息格式：                           │
│                                                              │
│ ┌────────┬────────┬────────┬─────────┬───────────┬────────┐ │
│ │ offset │ length │ magic  │ crc     │ timestamp │attrs  │ │
│ │ 8 bytes│ 4 bytes│ 1 byte │ 4 bytes │ 8 bytes   │1 byte │ │
│ ├────────┴────────┴────────┴─────────┴───────────┴────────┤ │
│ │                    key (optional)                        │ │
│ ├─────────────────────────────────────────────────────────┤ │
│ │                    value (payload)                       │ │
│ └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                        .index 文件                            │
├──────────────────────────────────────────────────────────────┤
│ 每条索引 8 字节:                                              │
│                                                              │
│ ┌─────────────────────┬────────────────────────────────────┐ │
│ │ relativeOffset      │ physicalPosition                   │ │
│ │ 4 bytes             │ 4 bytes                            │ │
│ └─────────────────────┴────────────────────────────────────┘ │
│                                                              │
│ relativeOffset = absoluteOffset - baseOffset                 │
│ physicalPosition = 该 offset 在 .log 文件中的字节位置            │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                      .timeindex 文件                          │
├──────────────────────────────────────────────────────────────┤
│ 每条索引 12 字节:                                             │
│                                                              │
│ ┌─────────────────────┬────────────────────────────────────┐ │
│ │ timestamp           │ relativeOffset                     │ │
│ │ 8 bytes             │ 4 bytes                            │ │
│ └─────────────────────┴────────────────────────────────────┘ │
│                                                              │
│ 用于根据时间戳快速定位消息位置（如 seek by timestamp）             │
└──────────────────────────────────────────────────────────────┘
```

### 2.5 LogSegment 源码结构

```scala
// 源码位置: core/src/main/scala/kafka/log/LogSegment.scala

class LogSegment private[log] (
    val log: FileRecords,          // .log 文件句柄
    val lazyOffsetIndex: LazyIndex[OffsetIndex],     // .index 稀疏索引
    val lazyTimeIndex: LazyIndex[TimeIndex],         // .timeindex 时间索引 
    val txnIndex: TransactionIndex,                   // 事务索引
    val baseOffset: Long,                              // 起始偏移量
    val indexIntervalBytes: Int,                      // 索引间隔（默认 4096）
    val rollJitterMs: Long,
    val time: Time
) extends Logging {
  
  // ========== 追加消息 ==========
  def append(largestOffset: Long,
             largestTimestamp: Long,
             shallowOffsetOfMaxTimestamp: Long,
             records: MemoryRecords): Unit = {
    // 1. 检查物理合法性
    if (records.sizeInBytes > 0) {
      // 2. 追加到 .log 文件
      val physicalPosition = log.sizeInBytes()
      log.append(records)
      
      // 3. 按 indexIntervalBytes 间隔，更新稀疏索引
      if (bytesSinceLastIndexEntry > indexIntervalBytes) {
        offsetIndex.append(largestOffset, physicalPosition)
        timeIndex.maybeAppend(largestTimestamp, shallowOffsetOfMaxTimestamp)
        bytesSinceLastIndexEntry = 0
      }
    }
  }
  
  // ========== 查找消息（核心算法）==========
  def read(startOffset: Long,
           maxSize: Int,
           maxPosition: Long = size,
           minOneMessage: Boolean = false): FetchDataInfo = {
    
    // Step 1: 在 .index 中二分查找 ≤ startOffset 的最大索引条目
    val offsetIndexEntry = offsetIndex.lookup(startOffset)
    // offsetIndexEntry = (relativeOffset, physicalPosition)
    
    // Step 2: 从 physicalPosition 开始，顺序扫描 .log 文件
    val fetchInfo = log.read(
      startPosition = offsetIndexEntry.position,
      maxLength = maxSize
    )
    
    FetchDataInfo(offsetIndexEntry, fetchInfo)
  }
  
  // ========== 检查是否到达切分点 ==========
  def shouldRoll(rollParams: RollParams): Boolean = {
    // 条件 1: 超过 segment.bytes（默认 1GB）
    size > rollParams.maxSegmentBytes - rollParams.messagesSize ||
    // 条件 2: 超过 segment.ms（默认 7 天）
    (timeWaitedForRoll(rollParams.now, rollParams.maxTimestampInMessages) 
     > rollParams.maxSegmentMs - rollJitterMs) ||
    // 条件 3: .index 文件满了
    offsetIndex.isFull ||
    // 条件 4: .timeindex 文件满了
    timeIndex.isFull
  }
}

// ========== OffsetIndex 稀疏索引实现 ==========
// 源码位置: core/src/main/scala/kafka/log/OffsetIndex.scala

class OffsetIndex(
    _file: File,
    baseOffset: Long,           // Segment 的起始 offset
    maxIndexSize: Int = -1      // 索引文件最大大小
) extends AbstractIndex[Long, Int](_file, baseOffset, maxIndexSize) {
  
  // 每条索引条目: (relativeOffset: Int, physicalPosition: Int)
  // 占用 8 字节
  
  override def entrySize = 8
  
  // 二分查找: 找到 ≤ targetOffset 的最大 relativeOffset
  def lookup(targetOffset: Long): OffsetPosition = {
    lock synchronized {
      // 将 mmap 的内存区域包装为 ByteBuffer
      val idx = mmap.duplicate()
      
      // 二分查找
      val slot = largestLowerBoundSlotFor(idx, 
        relativeOffset(targetOffset), IndexEntryType(0, identity))
      
      // 返回: (absoluteOffset, physicalPosition)
      OffsetPosition(
        baseOffset + relativeOffset(idx, slot),  // 绝对 offset
        physical(idx, slot)                       // 物理位置
      )
    }
  }
  
  // 二分查找核心
  private def largestLowerBoundSlotFor(
      idx: ByteBuffer,
      target: Long,
      entryType: IndexEntryType
  ): Int = {
    var lo = 0
    var hi = entries - 1
    while (lo < hi) {
      val mid = ceil(hi / 2.0 + lo / 2.0).toInt
      val found = parseEntry(idx, mid).indexEntryKey
      if (found <= target) lo = mid
      else hi = mid - 1
    }
    lo
  }
}
```

---

## 第三部分：消息存储引擎 —— 顺序写 + Page Cache + 零拷贝

### 3.1 顺序写 vs 随机写

这是 Kafka 高性能的最根本原因。

```
磁盘顺序写 vs 随机写性能对比:

┌──────────────────────────────────────────────────────────┐
│  操作类型        │  机械硬盘           │  SSD              │
├──────────────────────────────────────────────────────────┤
│  顺序写          │  ~100 MB/s         │  ~500 MB/s        │
│  随机写          │  ~100 KB/s（慢1000倍）│ ~100 MB/s        │
│  顺序读          │  ~100 MB/s         │  ~500 MB/s        │
│  随机读          │  ~100 KB/s         │  ~400 MB/s        │
└──────────────────────────────────────────────────────────┘

为什么顺序写比随机写快 1000 倍？
  1. 磁头寻道时间（机械硬盘）：顺序写 → 磁头不移动，随机写 → 频繁寻道
  2. Page Cache 预写：顺序写连续命中 Page Cache
  3. I/O Scheduler 合并：内核 I/O 调度器可以把相邻的写请求合并
```

**Kafka 如何保证顺序写？**
- 所有消息**追加到 .log 文件末尾**，永远不修改已有消息
- 每个 Partition 的 Active Segment 只有一个，追加写入
- 不存在更新/删除操作（Log Compaction 是后台线程异步重写整个文件）

### 3.2 Page Cache —— 操作系统的天然缓存

Kafka **不依赖 JVM 堆内存**缓存数据，而是依赖 OS 的 Page Cache。

```
Page Cache 工作原理:

┌──────────────────────────────────────────────────────────┐
│                   用户态（Kafka Broker）                    │
│                                                          │
│  write() ──────────────────────────────► read()           │
│     │                                      ▲              │
│     │              ┌───────────┐           │              │
│     └──────────────┤ Page Cache├───────────┘              │
│                    │ (空闲内存) │                          │
│                    │           │                          │
│                    └─────┬─────┘                          │
│                          │                                │
│                          │ 异步刷盘（pdflush）               │
│                          ▼                                │
│                    ┌───────────┐                          │
│                    │   磁盘     │                          │
│                    └───────────┘                          │
└──────────────────────────────────────────────────────────┘

Page Cache 的优势:
  1. 读命中: 如果数据在 Page Cache 中，直接返回（内存速度）
  2. 写缓冲: write() 调用写入 Page Cache 即返回，由 OS 异步刷盘
  3. 预读: OS 检测到顺序读，自动预读后续数据
  4. 自动管理: OS 根据内存压力自动回收，无需 JVM GC
```

**为什么 Kafka 不用 JVM 堆内存缓存？**
1. JVM 对象开销大：一条消息在 JVM 中占 40+ 字节头部 + padding
2. GC 问题：大量堆内存缓存导致 GC 停顿不可控
3. Page Cache 已经足够好：OS 层面的缓存命中率极高

### 3.3 零拷贝 sendfile

Kafka Consumer 读取消息时，使用 `sendfile` 系统调用实现零拷贝。

```
零拷贝 = 数据不经过用户态，直接从磁盘 → Page Cache → Socket Buffer → 网卡

Java NIO 中的调用:
  FileChannel.transferTo(position, count, socketChannel)
  
底层系统调用（Linux）:
  sendfile(out_fd, in_fd, offset, count)
```

### 3.4 传统 4 次拷贝 vs 零拷贝 2 次拷贝

```
传统方式: read() + send()——4 次拷贝 + 4 次上下文切换

  用户态:         read buffer────────────send buffer
                    ▲  ▲                    │  │
     上下文切换 ────┘  │                    │  └─── 上下文切换
                    │  │                    │
  内核态:     DMA copy │              DMA copy
              ┌───────┘              ┌───────▼
              │                      │
          Page Cache            Socket Buffer
              ▲                      │
              │   DMA copy           │ DMA copy
              │                      │
          ┌───┴──────────────────────┴───┐
          │           磁盘                │
          └──────────────────────────────┘

  4 次拷贝: 磁盘→内核→用户→内核→网卡
  4 次上下文切换: 用户态↔内核态 × 2


零拷贝: sendfile()——2 次拷贝 + 2 次上下文切换

  用户态:         sendfile() 调用
                    │          ▲
     上下文切换 ────┘          └─── 上下文切换
                    │
  内核态:       Page Cache─────────────Socket Buffer
                    ▲                        │
              DMA copy                  DMA copy
                    │                        ▼
          ┌─────────┴──────────────────────────┐
          │              磁盘                   │
          └────────────────────────────────────┘

  2 次拷贝: 磁盘→内核→网卡（Socket Buffer 只存描述符，不存数据）
  2 次上下文切换: 只有 sendfile() 一次调用
```

**Kafka 中零拷贝的生效条件**：
```scala
// 源码位置: clients/src/main/java/org/apache/kafka/common/network/TransferableChannel.java

// Kafka 使用 FileChannel.transferTo() 实现零拷贝
// 调用链: KafkaChannel.send() → FileRecords.writeTo() → FileChannel.transferTo()

// 什么时候用零拷贝?
// 1. 不修改消息内容（不解压缩、不转换格式）
// 2. 直接从磁盘传输到网络
// 3. 使用 PLAINTEXT 协议（非 SSL）

// 什么时候退化为普通拷贝?
// 1. SSL 加密：必须先拷贝到用户态加密
// 2. 消息格式转换（老版本兼容）
// 3. 日志压缩后的消息组合
```

### 3.5 Kafka 为什么快？—— 四大原因总结

```
┌──────────────────────────────────────────────────────────────┐
│                Kafka 高性能的四大支柱                           │
├───────────────┬──────────────────────────────────────────────┤
│               │                                              │
│  1. 顺序写磁盘 │  Partition 内消息追加写入，从不修改           │
│     (O(1))    │  Page Cache 缓存热数据                        │
│               │  机械硬盘: 顺序写~100MB/s vs 随机写~100KB/s     │
│               │                                              │
│  2. Page Cache│  依赖 OS 内存管理，不依赖 JVM 堆               │
│     (读命中)  │  OS 自动预读顺序数据                          │
│               │  无 JVM GC 压力                              │
│               │                                              │
│  3. 零拷贝    │  sendfile() 系统调用                          │
│     (sendfile)│  减少 2 次拷贝 + 2 次上下文切换               │
│               │  Consumer 拉取消息时生效                       │
│               │                                              │
│  4. 批量处理  │  Producer: 批量发送（batch.size + linger.ms）   │
│     (Batching)│  Consumer: 批量拉取（fetch.min.bytes）         │
│               │  Broker: 批量写入（sendfile 批量传输）          │
│               │                                              │
└───────────────┴──────────────────────────────────────────────┘

性能数据:
  - 单 Broker 吞吐: 数十万 ~ 百万条/秒（3 副本）
  - 端到端延迟: 毫秒级
  - 数据可靠性: 通过 Replica + ISR + ack 保证
```

---

## 第四部分：Producer —— 生产端原理

### 4.1 Producer 工作流程

```
KafkaProducer.send() 主流程:

  ┌──────────┐     ┌──────────────────┐     ┌────────────────┐
  │ 应用代码  │────►│  KafkaProducer   │────►│ RecordAccumu-  │
  │ send()   │     │  .send(record)   │     │ lator          │
  └──────────┘     └──────────────────┘     │ (按分区缓存)     │
                                            └───────┬────────┘
                                                    │
                       ┌────────────────────────────┘
                       │ batch.size 满了 或 linger.ms 到了
                       ▼
              ┌─────────────────┐
              │   Sender 线程    │
              │  (IO 线程)       │ ───► NetworkClient.send()
              └────────┬────────┘
                       │
                       ▼
              ┌─────────────────┐
              │   Kafka Broker  │
              │   接收消息并持久化  │
              └────────┬────────┘
                       │
                       ▼
              ┌─────────────────┐
              │   返回响应        │
              │   (Metadata)     │ ───► 回调 Callback
              └─────────────────┘
```

### 4.2 分区策略 Partitioner

```java
// 源码位置: clients/src/main/java/org/apache/kafka/clients/producer/internals/DefaultPartitioner.java

public class DefaultPartitioner implements Partitioner {
    
    public int partition(String topic, Object key, byte[] keyBytes,
                         Object value, byte[] valueBytes, Cluster cluster) {
        
        List<PartitionInfo> partitions = cluster.partitionsForTopic(topic);
        int numPartitions = partitions.size();
        
        // 情况 1: 指定了 Key → 对 Key Hash 后取模
        if (keyBytes != null) {
            // hash(key) % numPartitions
            return Utils.toPositive(Utils.murmur2(keyBytes)) % numPartitions;
        }
        
        // 情况 2: 没有 Key → 轮询 + 粘性分区（Sticky Partitioning）
        // Kafka 2.4+ 默认使用粘性分区
        return stickyPartitionCache.partition(topic, cluster);
    }
}

// ========== 分区策略总结 ==========
// 1. 指定 Partition:  使用指定值
// 2. 指定 Key:        hash(Key) % numPartitions
// 3. 都不指定:         Sticky 分区（2.4+）/ Round Robin（2.3-）
```

```
粘性分区（Sticky Partitioning）vs 轮询:

Round Robin:
  batch1 → P0, batch2 → P1, batch3 → P2, batch4 → P0, ...
  问题: 每个 batch 很小，请求数多，延迟高

Sticky Partitioning (默认):
  batch1 → P0, batch2 → P0, batch3 → P0, batch4 → P1, ...
  优势: 随机选一个分区，直到 batch 满了才切换
        减少请求数，增大 batch 大小，提高吞吐
```

### 4.3 消息发送流程 send()

```java
// 源码位置: clients/src/main/java/org/apache/kafka/clients/producer/KafkaProducer.java

public class KafkaProducer<K, V> implements Producer<K, V> {
    
    // 核心字段
    private final RecordAccumulator accumulator;   // 消息累积器
    private final Sender sender;                   // IO 发送线程
    private final Metadata metadata;               // 集群元数据
    private final Partitioner partitioner;         // 分区器
    
    public Future<RecordMetadata> send(ProducerRecord<K, V> record, 
                                        Callback callback) {
        // ========== Step 1: 等待元数据 ==========
        // 首次发送时需要获取 Topic 的 Partition 信息
        clusterAndWaitTime = waitOnMetadata(
            record.topic(), record.partition(), maxBlockTimeMs);
        
        // ========== Step 2: 序列化 Key 和 Value ==========
        byte[] serializedKey = keySerializer.serialize(
            record.topic(), record.headers(), record.key());
        byte[] serializedValue = valueSerializer.serialize(
            record.topic(), record.headers(), record.value());
        
        // ========== Step 3: 计算分区 ==========
        int partition = partition(
            record, serializedKey, serializedValue, cluster);
        
        // ========== Step 4: 消息追加到 RecordAccumulator ==========
        RecordAccumulator.RecordAppendResult result = 
            accumulator.append(
                tp, timestamp, serializedKey, serializedValue,
                headers, interceptCallback, remainingWaitMs);
        
        // ========== Step 5: 如果 batch 满了或新建 batch，唤醒 Sender ==========
        if (result.batchIsFull || result.newBatchCreated) {
            this.sender.wakeup();
        }
        
        return result.future;
    }
}
```

### 4.4 RecordAccumulator 双端队列批量发送

```java
// 源码位置: clients/src/main/java/org/apache/kafka/clients/producer/internals/RecordAccumulator.java

public final class RecordAccumulator {
    
    // 核心数据结构: ConcurrentMap<TopicPartition, Deque<ProducerBatch>>
    // 每个 Partition 对应一个双端队列
    private final ConcurrentMap<TopicPartition, Deque<ProducerBatch>> batches;
    
    // 未发送完成的最老 batch（用于追踪 delivery timeout）
    private final Map<TopicPartition, Long> incomplete;
    
    // 是否已经耗尽缓冲区（阻塞生产者）
    private final BufferPool free;  // 内存池
    
    // 核心参数
    private final int batchSize;    // batch 大小（默认 16384 = 16KB）
    private final CompressionType compression;  // 压缩类型
    
    // ========== 追加消息 ==========
    public RecordAppendResult append(TopicPartition tp,
                                      long timestamp,
                                      byte[] key, byte[] value,
                                      Callback callback,
                                      long maxTimeToBlock) throws InterruptedException {
        
        // Step 1: 从 BufferPool 申请内存
        ByteBuffer buffer = free.allocate(size, maxTimeToBlock);
        
        // Step 2: 获取该 Partition 对应的 Deque
        Deque<ProducerBatch> dq = getOrCreateDeque(tp);
        
        synchronized (dq) {
            // Step 3: 尝试追加到最后一个 batch（如果没满）
            RecordAppendResult result = tryAppend(timestamp, key, value, 
                                                   callback, dq);
            if (result != null) return result;  // 追加成功
            
            // Step 4: 最后一个 batch 满了或不存在，创建新 batch
            MemoryRecordsBuilder recordsBuilder = 
                recordsBuilder(buffer, ...);
            ProducerBatch batch = new ProducerBatch(tp, recordsBuilder, ...);
            dq.addLast(batch);  // 追加到队尾
            
            // Step 5: 把消息写入新 batch
            FutureRecordMetadata future = 
                batch.tryAppend(timestamp, key, value, callback);
            
            return new RecordAppendResult(future, dq.size() > 1, true);
        }
    }
    
    // ========== 准备发送: 收集已就绪的 batch ==========
    public ReadyCheckResult ready(Cluster cluster, long nowMs) {
        // 遍历所有 Partition 的队列
        for (Map.Entry<TopicPartition, Deque<ProducerBatch>> entry : 
             batches.entrySet()) {
            
            Deque<ProducerBatch> deque = entry.getValue();
            synchronized (deque) {
                ProducerBatch first = deque.peekFirst();
                if (first != null) {
                    // 条件 1: batch 满了
                    // 条件 2: linger.ms 到了
                    // 条件 3: accumulator 关闭了
                    // 条件 4: flush 被调用
                    boolean full = deque.size() > 1 || first.records().isFull();
                    boolean expired = waitedTimeMs >= lingerMs;
                    
                    if (full || expired || closed || forceFlush) {
                        readyNodes.add(leader);
                    }
                }
            }
        }
    }
}
```

### 4.5 Sender 线程与 NetworkClient

```java
// 源码位置: clients/src/main/java/org/apache/kafka/clients/producer/internals/Sender.java

public class Sender implements Runnable {
    
    private final KafkaClient client;  // NetworkClient（NIO 客户端）
    private final RecordAccumulator accumulator;
    private final Metadata metadata;
    
    public void run() {
        while (running) {
            runOnce();
        }
    }
    
    void runOnce() {
        // ========== Step 1: 从 Accumulator 获取就绪的 batch ==========
        long currentTimeMs = time.milliseconds();
        RecordAccumulator.ReadyCheckResult result = 
            accumulator.ready(cluster, currentTimeMs);
        
        // ========== Step 2: 对未知 Leader 的 Partition 更新元数据 ==========
        if (result.unknownLeaderTopics.size() > 0) {
            metadata.requestUpdate();
        }
        
        // ========== Step 3: 过滤出可以发送消息的节点 ==========
        Iterator<Node> iter = result.readyNodes.iterator();
        while (iter.hasNext()) {
            Node node = iter.next();
            if (!this.client.ready(node, currentTimeMs))
                iter.remove();  // 连接未就绪，跳过
        }
        
        // ========== Step 4: 从 Accumulator 拉取待发送的 batch ==========
        Map<Integer, List<ProducerBatch>> batches = 
            accumulator.drain(cluster, result.readyNodes, maxRequestSize, now);
        
        // ========== Step 5: 构建 ProduceRequest 并发送 ==========
        List<ClientRequest> requests = createProduceRequests(batches, now);
        for (ClientRequest request : requests) {
            client.send(request, now);
        }
        
        // ========== Step 6: 处理响应 ==========
        client.poll(pollTimeout, now);  // 轮询 NIO Selector
    }
}
```

### 4.6 幂等性实现 Idempotent

Kafka 的幂等性保证了 **同一 Producer 的同一消息不会在 Partition 中重复**。

```
幂等性的实现原理 —— PID + Sequence Number:

┌──────────────────────────────────────────────────────────────┐
│  1. Producer 启动时，向 Broker 申请 PID（Producer ID）        │
│     PID 由 Broker 分配，全局唯一                              │
│                                                              │
│  2. 每条消息附带:                                             │
│     - PID（Producer ID）                                      │
│     - SeqNo（Sequence Number，单调递增，从 0 开始）             │
│     - 目标 Partition                                          │
│                                                              │
│  3. Broker 端维护每个 Producer 的最近 5 个 SeqNo:              │
│     Map<PID, Map<Partition, ProducerStateEntry>>              │
│                                                              │
│  4. 收到消息时检查:                                           │
│     - SeqNo == lastSeqNo + 1 → 正常，接受                     │
│     - SeqNo <= lastSeqNo     → 重复，丢弃                     │
│     - SeqNo > lastSeqNo + 1  → 乱序，抛出异常                  │
└──────────────────────────────────────────────────────────────┘

配置: enable.idempotence = true
必要条件: max.in.flight.requests.per.connection <= 5
         acks = all
         retries > 0
```

```scala
// 源码位置: core/src/main/scala/kafka/server/ProducerStateManager.scala

class ProducerStateManager(val topicPartition: TopicPartition) {
  
  // 每个 Producer 的状态: (lastSeqNo, lastOffset, timestamp)
  private val producers = mutable.Map.empty[Long, ProducerStateEntry]
  
  // ========== 幂等性检查核心 ==========
  def validateAppend(producerId: Long, 
                     firstSeq: Int, 
                     lastSeq: Int): Option[CompletedTxn] = {
    
    val currentEntry = producers.get(producerId)
    
    currentEntry match {
      case None =>
        // 新 Producer, 必须从 SeqNo=0 开始
        if (firstSeq != 0) {
          throw new OutOfOrderSequenceException(
            s"Invalid sequence number for new producer $producerId: $firstSeq")
        }
        None
        
      case Some(entry) =>
        // 已存在的 Producer，检查 SeqNo 连续性
        val expectedSeq = entry.lastSeq + 1
        if (firstSeq == expectedSeq) {
          // 正常: 序列号连续
          None
        } else if (firstSeq < expectedSeq) {
          // 重复数据: 在 lastSeq~lastSeq-5 范围内 → 幂等丢弃
          if (firstSeq >= entry.lastSeq - 5) {
            None  // 重复，丢弃
          } else {
            throw new OutOfOrderSequenceException(...)
          }
        } else {
          // 乱序: firstSeq > expectedSeq → 抛出异常
          throw new OutOfOrderSequenceException(...)
        }
    }
  }
}
```

### 4.7 事务与 Exactly Once 语义

Kafka 事务可以保证**跨 Partition 和跨 Topic 的原子写入**。

```
事务消息流程（以消费→处理→生产为例）:

   ┌──────────┐         ┌──────────┐         ┌──────────┐
   │ Consumer │         │  Processor│         │ Producer │
   │ (读 Topic A)│      │  (处理)   │         │ (写 Topic B)│
   └─────┬────┘         └─────┬────┘         └─────┬────┘
         │                    │                    │
         │  1. 读取消息        │                    │
         │◄───────────────────┤                    │
         │                    │                    │
         │  2. 返回消息+offset │                    │
         ├────────────────────►                    │
         │                    │                    │
         │                    │ 3. initTransactions │
         │                    ├───────────────────►│
         │                    │                    │
         │                    │ 4. beginTransaction │
         │                    ├───────────────────►│
         │                    │                    │
         │                    │ 5. 消费（记录 offset）│
         │◄───────────────────┤                    │
         │                    │                    │
         │                    │ 6. 处理业务逻辑      │
         │                    │                    │
         │                    │ 7. 发送结果消息       │
         │                    ├────────────────────►│
         │                    │                    │
         │                    │ 8. commitTransaction│
         │                    ├────────────────────►│
         │                    │                    │
         │                    │  9. 写入 END 标记    │
         │                    │                    │
         ▼                    ▼                    ▼

关键点:
  - Consumer 读取 offset → 通过 sendOffsetsToTransaction() 提交
  - Producer 发送消息 → 写事务标记
  - commitTransaction → 写入事务控制消息（COMMIT/ABORT）
```

```java
// 事务 Producer 的使用方式

// 1. 配置事务 Producer
Properties props = new Properties();
props.put("bootstrap.servers", "localhost:9092");
props.put("transactional.id", "my-transactional-id");  // 全局唯一
props.put("enable.idempotence", true);  // 事务必须幂等

KafkaProducer<String, String> producer = new KafkaProducer<>(props);

// 2. 初始化事务（申请 PID + epoch）
producer.initTransactions();

try {
    // 3. 开始事务
    producer.beginTransaction();
    
    // 4. 发送消息
    producer.send(new ProducerRecord<>("output-topic", "key", "value"));
    
    // 5. 如果消费-处理-生产模式，提交消费 offset
    Map<TopicPartition, OffsetAndMetadata> offsets = new HashMap<>();
    offsets.put(new TopicPartition("input-topic", 0), 
                new OffsetAndMetadata(123L));
    producer.sendOffsetsToTransaction(offsets, "consumer-group-id");
    
    // 6. 提交事务
    producer.commitTransaction();
} catch (Exception e) {
    // 7. 异常时中止事务
    producer.abortTransaction();
}

// 事务原理:
// 1. transactional.id → PID 映射（基于 __transaction_state 主题）
// 2. PID + epoch → 隔离写入，防止僵尸进程
// 3. 事务控制消息（BEGIN/COMMIT/ABORT/END）→ 写 Partition 日志
// 4. Consumer 读取时根据事务标记决定消息可见性
```

### 4.8 Ack 机制与可靠性

```
ack 参数决定消息可靠性:

┌──────────┬──────────────────────────────────────────────────┐
│   ack=0  │  Producer 不等待 Broker 确认                       │
│          │  最快，最不可靠                                    │
│          │  适用: 日志采集、监控数据                           │
├──────────┼──────────────────────────────────────────────────┤
│   ack=1  │  Leader 写入本地日志即返回确认                      │
│          │  中等速度，中等可靠                                │
│          │  风险: Leader 宕机但消息未同步到副本 → 数据丢失      │
├──────────┼──────────────────────────────────────────────────┤
│  ack=all │  Leader + 所有 ISR 副本全部写入才返回               │
│ (ack=-1) │  最慢，最可靠                                      │
│          │  配合 min.insync.replicas 使用                     │
│          │  适用: 金融交易、订单系统                           │
└──────────┴──────────────────────────────────────────────────┘

min.insync.replicas（最小 ISR 数量）:
  ack=all 时有效
  例如: replication.factor=3, min.insync.replicas=2
  含义: 至少 2 个副本（含 Leader）确认写入才成功
  
  极端情况: min.insync.replicas=replication.factor=3
  含义: 全部 3 个副本确认 → 除非全部宕机，否则数据不丢
  风险: 任意一个副本宕机 → 写入失败，可用性降低
```

---

## 第五部分：Consumer —— 消费端原理

### 5.1 Consumer 工作流程

```
KafkaConsumer 核心工作流程:

  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
  │  KafkaConsumer│────►│ConsumerCoordi-│────►│  Fetcher     │
  │  .poll()     │     │ nator         │     │  (拉取数据)   │
  └──────┬───────┘     │(Rebalance)    │     └──────┬───────┘
         │             └──────────────┘            │
         │                                         ▼
         │             ┌──────────────┐     ┌──────────────┐
         │             │ Subscription │     │  Consumer    │
         │             │ State        │     │  Records     │
         │             │ (管理订阅信息) │     │  (返回结果)   │
         │             └──────────────┘     └──────────────┘
         │
         │  每次 poll() 执行:
         │  1. 检查是否需要 Rebalance（心跳超时、元数据变更等）
         │  2. 如果 Rebalance 中，等待完成
         │  3. 拉取数据（Fetcher.poll()）
         │  4. 反序列化数据
         │  5. 返回 ConsumerRecords
         ▼
```

### 5.2 Consumer Group 与消费模型

```
Consumer Group 消费模型:

Topic: orders (3 Partitions)

  ┌─────────────────────────────────────────────────────────┐
  │                                                         │
  │  Consumer Group A (广播模式)                                │
  │  ┌──────┐ ┌──────┐ ┌──────┐                             │
  │  │  C1  │ │  C2  │ │  C3  │   每个 Consumer 消费一个      │
  │  │  P0  │ │  P1  │ │  P2  │   Partition                 │
  │  └──────┘ └──────┘ └──────┘                             │
  │                                                         │
  │  Consumer Group B (另一组独立消费)                           │
  │  ┌──────┐ ┌──────┐                                      │
  │  │  C4  │ │  C5  │   C4 消费 P0+P1, C5 消费 P2           │
  │  │P0,P1 │ │  P2  │   同组内多个 Partition 可分配给同 Consumer│
  │  └──────┘ └──────┘                                      │
  │                                                         │
  └─────────────────────────────────────────────────────────┘

核心规则:
  1. 同一 Partition 只能被同一 Group 中的一个 Consumer 消费
  2. 同一 Consumer 可以消费多个 Partition
  3. 不同 Group 之间相互独立，消息被"广播"
  4. 当 Consumer 数量 > Partition 数量时，多余的 Consumer 空闲
```

### 5.3 Rebalance 协议——最核心的机制

Rebalance 是 Consumer Group 协调过程中的核心机制。当 Group 成员或订阅的 Partition 发生变化时，触发重新分配。

```
Rebalance 的触发条件:
  1. Consumer 加入或离开 Group
  2. Consumer 心跳超时（session.timeout.ms）
  3. Topic 的 Partition 数量发生变化
  4. Consumer 订阅的 Topic 发生变化

Rebalance 协议流程（Eager Protocol，默认）:

  Consumer          GroupCoordinator(Broker)          Other Consumer
     │                      │                              │
     │  1. JoinGroup        │                              │
     │  (memberId, protocols)                              │
     ├─────────────────────►│                              │
     │                      │                              │
     │                      │  2. 等待所有 Consumer 加入      │
     │                      │     (group.initial.rebalance. │
     │                      │      delay.ms)               │
     │                      │                              │
     │  3. JoinGroup        │                              │
     │  Response            │                              │
     │  (leader, members)   │                              │
     │◄─────────────────────┤                              │
     │                      │                              │
     │  4. Consumer Leader 执行分配策略                       │
     │     (Range/RoundRobin/Sticky/CooperativeSticky)     │
     │                      │                              │
     │  5. SyncGroup        │                              │
     │  (assignment)        ├──────────────────────────────►
     ├─────────────────────►│  6. SyncGroup Response        │
     │                      │     (每个 Consumer 的分区列表)   │
     │  7. SyncGroup        │                              │
     │  Response            │                              │
     │  (partition list)    │                              │
     │◄─────────────────────┤                              │
     │                      │                              │
     │  8. 开始消费              │  9. 开始消费                  │
     ▼                      ▼                              ▼

注意 Eager Protocol 的问题: STOP-THE-WORLD
  所有 Consumer 在 Rebalance 期间停止消费，直到新的分配完成。
  这就是"Rebalance 惊群"问题。

Cooperative Rebalance（增量协作，Kafka 2.4+）:
  不再全部暂停，只重新分配需要的 Partition
  配置: partition.assignment.strategy = CooperativeStickyAssignor
```

### 5.4 GroupCoordinator 源码

```scala
// 源码位置: core/src/main/scala/kafka/coordinator/group/GroupCoordinator.scala

class GroupCoordinator(
    val brokerId: Int,
    val config: KafkaConfig,
    replicaManager: ReplicaManager,
    ...) extends Logging {
    
  // 管理所有 Consumer Group 的状态
  private val groupMetadataCache = 
    new Pool[String, GroupMetadata]
  
  // ========== handleJoinGroup（消费者加入 Group）==========
  def handleJoinGroup(
      groupId: String,
      memberId: String,
      protocolType: String,
      protocols: List[(String, Array[Byte])],
      responseCallback: JoinGroupResult => Unit
  ): Unit = {
    
    // Step 1: 获取或创建 GroupMetadata
    val group = groupMetadataCache.getOrElseUpdate(groupId, 
      new GroupMetadata(groupId, initialState = Empty))
    
    // Step 2: 检查 Protocol Type 一致性（同一 Group 只能有一种协议）
    if (!group.is(Empty) && !group.protocolType.contains(protocolType))
      throw Errors.INCONSISTENT_GROUP_PROTOCOL
    
    // Step 3: 添加成员到 Group
    group.add(memberId, clientId, clientHost, ...)
    
    // Step 4: 如果这是最后一个加入的消费者
    //    （在 rebalanceTimeoutMs 内所有 Consumer 到齐）
    if (group.is(PreparingRebalance)) {
      // 选出 Leader Consumer（第一个加入的）
      val leaderId = group.leaderOrNull
      
      // 返回 JoinGroup Response，Leader 收到所有成员信息
      responseCallback(JoinGroupResult(
        members = if (isLeader) group.allMembers else Map.empty,
        memberId = memberId,
        generationId = group.generationId,
        leaderId = leaderId
      ))
    }
  }
  
  // ========== handleSyncGroup（Leader 提交分配方案）==========
  def handleSyncGroup(
      groupId: String,
      generation: Int,
      memberId: String,
      groupAssignment: Map[String, Array[Byte]],  // 只有 Leader 发送
      responseCallback: Array[Byte] => Unit
  ): Unit = {
    
    val group = groupMetadataCache.get(groupId)
    
    // Step 1: 验证 Generation（防止过期请求）
    if (group.generationId != generation) {
      responseCallback(Errors.ILLEGAL_GENERATION)
      return
    }
    
    // Step 2: Leader 提交分配方案
    if (!groupAssignment.isEmpty) {
      // 执行分配策略
      performAssignment(group, groupAssignment)
    }
    
    // Step 3: 返回该 Consumer 的 Partition 列表
    val partitionList = group.currentMemberMetadata(memberId).assignment
    responseCallback(partitionList)
  }
  
  // ========== handleHeartbeat（心跳检测）==========
  def handleHeartbeat(
      groupId: String,
      memberId: String,
      generationId: Int,
      responseCallback: Errors => Unit
  ): Unit = {
    
    val group = groupMetadataCache.get(groupId)
    
    // 心跳超时检查
    if (group.generationId != generationId) {
      responseCallback(Errors.ILLEGAL_GENERATION)
    } else {
      // 更新最后心跳时间
      group.currentMember(memberId).latestHeartbeat = time.milliseconds()
      responseCallback(Errors.NONE)
    }
  }
}
```

### 5.5 偏移量提交 Offset Commit

```
Offset 提交的两种方式:

1. 自动提交（enable.auto.commit=true，默认）
   ┌──────────────────────────────────────────────────────────┐
   │  Consumer 后台线程定期提交（auto.commit.interval.ms=5000） │
   │                                                          │
   │  问题: 可能重复消费                                       │
   │  poll() → 拉取 10 条 → 处理 3 条 → 自动提交 offset=10     │
   │  → 崩溃重启 → 从 offset=10 开始 → 第 4-10 条被跳过！       │
   └──────────────────────────────────────────────────────────┘

2. 手动提交（enable.auto.commit=false）
   ┌──────────────────────────────────────────────────────────┐
   │  同步提交: consumer.commitSync()                         │
   │  异步提交: consumer.commitAsync()                        │
   │                                                          │
   │  最佳实践: 处理完消息后提交偏移量                            │
   │  poll() → process all → commit                           │
   └──────────────────────────────────────────────────────────┘
```

```scala
// 源码位置: core/src/main/scala/kafka/coordinator/group/GroupMetadataManager.scala

class GroupMetadataManager(...) {
  
  // ========== 存储 Offset ==========
  def storeOffsets(
      group: GroupMetadata,
      consumerId: String,
      generationId: Int,
      offsetMetadata: immutable.Map[TopicPartition, OffsetAndMetadata],
      responseCallback: immutable.Map[TopicPartition, Errors] => Unit
  ): Unit = {
    
    // Step 1: 验证 Generation（防止过期 Consumer 提交旧 Offset）
    if (generationId < 0) {
      // 如果 generation < 0，认为 Consumer 已退出，拒绝
      responseCallback(offsetMetadata.mapValues(_ => 
        Errors.ILLEGAL_GENERATION))
      return
    }
    
    // Step 2: 构建 Offset Commit Key/Value
    val offsetCommits = offsetMetadata.map { case (tp, offsetAndMetadata) =>
      // Key:   GroupTopicPartitionKey  (groupId, topic, partition)
      val key = GroupTopicPartitionKey(
        group.groupId, tp.topic, tp.partition)
      // Value: GroupTopicPartitionValue (offset, metadata, timestamp)
      val value = GroupTopicPartitionValue(
        offsetAndMetadata.offset, offsetAndMetadata.metadata, timestamp)
      (key, value)
    }
    
    // Step 3: 写入 __consumer_offsets 主题
    replicaManager.appendRecords(
      timeout = config.offsetCommitTimeoutMs.toLong,
      requiredAcks = config.offsetCommitRequiredAcks,
      internalTopicsAllowed = true,
      entriesPerPartition = Map(offsetTopicPartition -> 
        MemoryRecords.withRecords(MessageWriter, offsetCommits))
    )
  }
}
```

### 5.6 __consumer_offsets 内部主题

Kafka 使用内置 Topic `__consumer_offsets` 存储消费者偏移量，取代了旧版的 ZK 存储。

```
__consumer_offsets 主题结构:

  Partition 数量: offsets.topic.num.partitions = 50（默认）
  Replication 因子: offsets.topic.replication.factor = 3（默认）

  Key:   (GroupId, Topic, Partition)
  Value: (Offset, Metadata, CommitTimestamp, ExpireTimestamp)

  示例:
  Key  : (order-consumer, orders, 0)
  Value: (offset=12345, metadata="", timestamp=1680000000000)
  
  查找方式:
  GroupCoordinator 的 Broker 根据 groupId.hashCode % 50 
  确定该 Group 对应 __consumer_offsets 的哪个 Partition
```

---

## 第六部分：副本机制 —— ISR 与高可用

### 6.1 副本分布规则

```
Partition 副本分布策略:

Topic: orders, 3 Partitions, Replication Factor=3

  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
  │  Broker 1   │   │  Broker 2   │   │  Broker 3   │
  │             │   │             │   │             │
  │ P0: Leader  │   │ P0: Follower│   │ P0: Follower│
  │ P1: Follower│   │ P1: Leader  │   │ P1: Follower│
  │ P2: Follower│   │ P2: Follower│   │ P2: Leader  │
  └─────────────┘   └─────────────┘   └─────────────┘

副本分配原则:
  1. 每个 Partition 的副本必须分布在不同 Broker 上（不能同机架）
  2. 优先均匀分配，避免某 Broker 承担过多 Leader
  3. 机架感知: broker.rack 配置 → 跨机架分布
```

### 6.2 ISR（In-Sync Replicas）

ISR 是 Kafka 高可用的核心机制。它定义了**与 Leader 保持同步的副本集合**。

```
ISR 的定义:

  ISR = {副本 | LEO ≥ Leader 的 HW, 且过去 replica.lag.time.max.ms 内有 Fetch 请求}

  两个条件:
    1. LEO 不能落后 Leader 的 HW
    2. 必须在 replica.lag.time.max.ms（默认 30s）内发送 Fetch 请求

OSR（Out-of-Sync Replicas）:
  ISR 之外的副本 = OSR
  即: AR（Assigned Replicas）= ISR + OSR

ISR 动态变化:

  ┌───────────────────────────────────────────────────────────┐
  │  初始: ISR = {Broker1(L), Broker2(F), Broker3(F)}       │
  │                                                           │
  │  Broker3 故障（超过 30s 无 Fetch）:                         │
  │  ISR 收缩为 {Broker1(L), Broker2(F)}                      │
  │  Broker3 → OSR                                            │
  │                                                           │
  │  Broker3 恢复（追上 Leader）:                               │
  │  ISR 扩展为 {Broker1(L), Broker2(F), Broker3(F)}          │
  └───────────────────────────────────────────────────────────┘
```

### 6.3 LEO 与 HW 水位线

```
LEO（Log End Offset）: 每个副本的最后一条消息的 offset + 1
HW（High Watermark）:  所有 ISR 副本中最小的 LEO

┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  Leader (Broker 1):                                          │
│  msg0  msg1  msg2  msg3  msg4  msg5  msg6                    │
│  │                       │                  │                │
│  │◄── HW = 4 ──────────►│                  │                │
│  │     (消费者可见)                          │                │
│  │                              LEO = 7 ────►│                │
│                                                              │
│  Follower (Broker 2):                                        │
│  msg0  msg1  msg2  msg3  msg4                                │
│  │                            │                              │
│  │◄── HW = 4 ────────────────►│                              │
│  │                 LEO = 5 ───►│                              │
│                                                              │
│  Follower (Broker 3):                                        │
│  msg0  msg1  msg2  msg3                                      │
│  │                  │                                        │
│  │◄── HW = 4 ──────►│                                        │
│  │       LEO = 4 ───►│                                        │
│                                                              │
│  ISR 中最小的 LEO = min(7, 5, 4) = 4                         │
│  所以 HW = 4（消费者只能读到 ≤4 的数据）                          │
│                                                              │
│  注意: 旧版本 HW 由 Leader 广播，2.4+ 改为 Follower 独立维护      │
│        fetch response 告知 Leader 的 HW                       │
└──────────────────────────────────────────────────────────────┘

消费者读取规则:
  消费者只能读取 ≤ HW 的消息
  未达到 HW 的消息（如 msg4、msg5、msg6）不可见
  这保证了消费者读到的数据已经在 ISR 中多数副本确认
```

### 6.4 Leader 选举机制

```
Leader 选举由 Controller 负责:

选举时机:
  1. 某个 Partition 的 Leader 宕机
  2. 某个 Broker 宕机（影响它上面所有 Leader Partition）
  3. 新创建 Topic
  4. 手动触发 Preferred Leader Election

选举规则:
  1. 优先从 ISR 中选
  2. 在 ISR 中，按 AR（Assigned Replicas）的顺序优先
     即: 先创建的副本优先（比如 Partition 0 的 Replica 0 优先）
  3. 如果 ISR 为空且 unclean.leader.election.enable=true:
     从 OSR 中选（Unclean Leader Election）

选举流程:

  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
  │  Controller  │     │  Zookeeper   │     │   Broker     │
  └──────┬───────┘     └──────┬───────┘     └──────┬───────┘
         │                    │                    │
         │  1. ZK Watch 感知    │                    │
         │  Broker 下线         │                    │
         │◄───────────────────┤                    │
         │                    │                    │
         │  2. 确定受影响 Partition                    │
         │  (遍历该 Broker 上的所有 Leader)            │
         │                    │                    │
         │  3. 为每个 Partition 选新 Leader           │
         │     从 ISR 中按 AR 顺序选                  │
         │                    │                    │
         │  4. 更新 ZK 状态       │                    │
         │  /brokers/topics/   │                    │
         │  [topic]/partitions/│                    │
         │  [pid]/state        │                    │
         ├───────────────────►│                    │
         │                    │                    │
         │  5. 发送 LeaderAndIsr 请求                    │
         │  (告知所有副本新的 Leader 和 ISR)           │
         │                    │                    │
         ├────────────────────┼───────────────────►│
         │                    │                    │
         │                    │  6. Follower 切换为 Leader
         │                    │     开始处理读写请求   │
         │                    │     旧 Leader 降级为 Follower
         │                    │                    │
         ▼                    ▼                    ▼
```

### 6.5 Unclean Leader Election

```
Unclean Leader Election (脏 Leader 选举):

  场景: 所有 ISR 副本全部宕机，只有 OSR 副本存活

  ┌──────────────────────────────────────────────────────────┐
  │  配置: unclean.leader.election.enable                    │
  │                                                          │
  │  true（默认旧版本）:                                      │
  │    从 OSR 中选 Leader → 可用性优先                         │
  │    风险: 可能丢失 ISR 副本上未同步的数据                     │
  │    适用: 容忍丢数据但要求高可用的场景                         │
  │                                                          │
  │  false（推荐）:                                           │
  │    不选 Leader → 一致性优先，等待 ISR 恢复                   │
  │    代价: 该 Partition 一段时间不可用                        │
  │    适用: 金融、支付等不能丢数据的场景                         │
  └──────────────────────────────────────────────────────────┘
```

### 6.6 副本同步源码

```scala
// 源码位置: core/src/main/scala/kafka/server/ReplicaManager.scala

class ReplicaManager(
    val config: KafkaConfig,
    metrics: Metrics,
    time: Time,
    ...) extends Logging {
  
  // 所有 Partition 的集合: Map[TopicPartition, Partition]
  private val allPartitions = new Pool[TopicPartition, Partition]
  
  // ========== Follower Fetch 请求处理 ==========
  def fetchMessages(
      timeout: Long,
      replicaId: Int,
      fetchMinBytes: Int,
      fetchMaxBytes: Int,
      hardMaxBytesLimit: Boolean,
      fetchInfos: Seq[(TopicPartition, PartitionData)],
      ...): Map[TopicPartition, FetchPartitionData] = {
    
    val logReadResults = new mutable.HashMap[TopicPartition, LogReadResult]
    
    for ((topicPartition, partitionData) <- fetchInfos) {
      // Step 1: 检查是否为当前 Leader
      val localReplica = getPartition(topicPartition).get.leaderReplicaIfLocal
      if (localReplica.isEmpty) {
        // 已不是 Leader，返回 NOT_LEADER_OR_FOLLOWER
        logReadResults.put(topicPartition, LogReadResult(
          error = Errors.NOT_LEADER_OR_FOLLOWER))
      } else {
        // Step 2: 根据 FetchOffset 读取日志
        val logReadInfo = localReplica.log.get.read(
          startOffset = partitionData.fetchOffset,
          maxLength = partitionData.maxBytes,
          maxOffset = None,
          minOneMessage = true
        )
        
        // Step 3: 如果 Follower 追上了 Leader
        // 记录最后 Fetch 时间（用于 ISR 判断）
        if (partitionData.fetchOffset >= localReplica.logEndOffset) {
          // Follower 已追上 → update ISR
        }
        
        logReadResults.put(topicPartition, LogReadResult(info = logReadInfo))
      }
    }
    logReadResults.toMap
  }
  
  // ========== 更新 ISR（周期性检查）==========
  def maybeShrinkIsr(): Unit = {
    allPartitions.values.foreach { partition =>
      // 检查每个 Follower 是否在规定时间内发送了 Fetch 请求
      val leaderReplica = partition.leaderReplicaIfLocal
      leaderReplica.foreach { leader =>
        val outOfSyncReplicas = partition.getOutOfSyncReplicas(
          leader.logEndOffset,
          config.replicaLagTimeMaxMs
        )
        if (outOfSyncReplicas.nonEmpty) {
          // 将超时副本从 ISR 中移除
          partition.maybeShrinkIsr(config.replicaLagTimeMaxMs)
        }
      }
    }
  }
  
  // ========== 更新 HW ==========
  def maybeIncrementLeaderHW(partition: Partition): Unit = {
    val leaderReplica = partition.getReplica()
    // HW = min(Leader LEO, all ISR LEO)
    val newHighWatermark = partition.inSyncReplicas
      .map(_.logEndOffset)
      .min
    
    leaderReplica.foreach { leader =>
      if (newHighWatermark > leader.highWatermark.messageOffset) {
        leader.highWatermark = new LogOffsetMetadata(newHighWatermark)
      }
    }
  }
}
```

---

## 第七部分：Controller 与 KafkaController

### 7.1 Controller 是什么

Controller 是 Kafka 集群的管理者，负责管理整个集群中所有 Partition 和 Replica 的状态。

```
Controller 的定位:

  ┌───────────────────────────────────────────────────────────┐
  │  Controller = 集群的"心脏"                                 │
  │                                                           │
  │  - 集群中同时只有一个 Controller（通过 ZK 选举）              │
  │  - 其他 Broker 作为普通节点                                │
  │  - Controller 宕机 → ZK 触发重新选举                       │
  │  - 控制了所有 Leader 选举和 Partition 分配                  │
  └───────────────────────────────────────────────────────────┘
```

### 7.2 Controller 选举

```
Controller 选举流程:

  ┌──────────────────────────────────────────────────────────┐
  │  1. 所有 Broker 启动时，尝试在 ZK 创建 /controller 临时节点 │
  │    create /controller {"brokerid": 1, "timestamp": ...}  │
  │                                                          │
  │  2. 只有第一个成功创建的是 Controller                     │
  │    其他 Broker 注册 Watch，监听 /controller 变化           │
  │                                                          │
  │  3. Controller 宕机 → 临时节点消失 → Watch 触发             │
  │    所有剩余 Broker 重新竞争 /controller                   │
  │                                                          │
  │  4. 新 Controller 当选后，从 ZK 读取所有元数据              │
  │    (Topic/Partition/Replica/Broker 信息)                 │
  └──────────────────────────────────────────────────────────┘
```

```scala
// 源码位置: core/src/main/scala/kafka/controller/KafkaController.scala

class KafkaController(
    val config: KafkaConfig,
    zkClient: KafkaZkClient,
    ...) extends Logging {
  
  // ControllerContext: 集群上下文信息
  val controllerContext = new ControllerContext
  
  // 状态机
  val partitionStateMachine: PartitionStateMachine
  val replicaStateMachine: ReplicaStateMachine
  
  // ========== Controller 选举 ==========
  def elect(): Unit = {
    // 在 ZK 尝试创建 /controller 临时节点
    val (epoch, epochZkVersion) = 
      zkClient.registerControllerAndIncrementControllerEpoch(
        controllerId
      )
    
    controllerContext.epoch = epoch
    controllerContext.epochZkVersion = epochZkVersion
    
    // 成为 Controller 后：初始化状态机
    onControllerFailover()
  }
  
  // ========== Controller 故障转移 ==========
  private def onControllerFailover(): Unit = {
    // Step 1: 从 ZK 读取所有数据
    initializeControllerContext()
    
    // Step 2: 初始化 Partition 状态机
    partitionStateMachine.startup()
    
    // Step 3: 初始化 Replica 状态机
    replicaStateMachine.startup()
    
    // Step 4: 注册各种 ZK Watch
    registerPartitionModificationsHandlers()
    registerBrokerChangeHandler()
    
    // Step 5: 开始处理 Leader 选举
    partitionStateMachine.triggerOnlinePartitionStateChange()
    
    // Step 6: 处理副本重分配
    maybeTriggerPartitionReassignment()
  }
}
```

### 7.3 Controller 的职责

```
Controller 的 5 大职责:

1. Partition Leader 选举
   Broker 宕机 → Controller 为受影响 Partition 选新 Leader

2. 同步副本 ISR 管理
   管理每个 Partition 的 ISR 集合

3. Partition 和 Replica 分配
   创建 Topic 时分配 Partition 到 Broker
   增加 Partition 数量时重新分配

4. 代理 Broker 上下线
   Broker 上下线 → 更新元数据 → 通知所有 Broker

5. 元数据同步
   向所有 Broker 广播最新的 Cluster Metadata
```

### 7.4 PartitionStateMachine 与 ReplicaStateMachine

```scala
// Partition 状态机 —— 管理所有 Partition 的状态转换
// 源码位置: core/src/main/scala/kafka/controller/PartitionStateMachine.scala

class PartitionStateMachine(controller: KafkaController) extends Logging {
  
  // Partition 的状态
  // NonExistent → NewPartition → OnlinePartition → OfflinePartition
  //                     ↕
  //              OnlinePartition ↔ OnlinePartition (reassign)
  
  // ========== 初始化所有 Partition 为 Online ==========
  def triggerOnlinePartitionStateChange(): Unit = {
    val partitions = controllerContext
      .partitionLeadershipInfo.keySet.toSeq
    
    doHandleStateChanges(
      partitions,
      targetState = OnlinePartition,
      partitionLeaderElectionStrategyOpt = 
        Some(PartitionLeaderElectionAlgorithms.offlinePartitionLeaderElection)
    )
    // 内部调用 electLeaderForPartition() 进行 Leader 选举
  }
  
  // ========== Leader 选举 ==========
  private def doElectLeaderForPartition(
      partition: TopicPartition,
      leaderElectionStrategy: PartitionLeaderElectionStrategy
  ): Option[LeaderAndIsr] = {
    
    // 获取 AR 和 ISR
    val replicas = controllerContext.partitionReplicaAssignment(partition)
    val isr = controllerContext.partitionLeadershipInfo(partition).isr
    
    // 根据选举策略，选出新 Leader
    val leaderAndIsr = leaderElectionStrategy match {
      case OfflinePartitionLeaderElectionStrategy =>
        // ISR 中按 AR 顺序选 Leader
        electLeaderFromIsr(partition, replicas, isr)
      
      case ReassignPartitionLeaderElectionStrategy =>
        // 重分配时，考虑新 AR
        electLeaderForReassign(partition, replicas, isr)
      
      case PreferredReplicaPartitionLeaderElectionStrategy =>
        // Preferred Leader Election（AR 中第一个）
        electPreferredLeader(partition, replicas, isr)
    }
    
    leaderAndIsr
  }
}
```

### 7.5 Controller 与 ZK 的交互

```
Controller 在 ZK 中的核心路径:

  /controller                      ← Controller 选举临时节点
    {"brokerid":1, "timestamp":"..."}

  /controller_epoch                ← Controller epoch（递增）
    1

  /brokers/ids/[0..N]              ← 各 Broker 的注册信息
    {"host":"...", "port":9092, "rack":"rack1"}

  /brokers/topics/[topic]          ← Topic 配置和分区信息
    {"version":2, "partitions":{"0":[0,1,2], "1":[1,2,0], "2":[2,0,1]}}

  /brokers/topics/[topic]/partitions/[pid]/state  ← Partition 状态
    {"leader":1, "leader_epoch":0, "isr":[1,2,3], "version":1}

  /admin/reassign_partitions       ← 分区重分配任务
  /admin/delete_topics             ← Topic 删除任务

Controller 的 Watch 机制:
  - /brokers/ids:         Watch Broker 上下线
  - /brokers/topics:      Watch Topic 创建/删除
  - /admin/reassign_partitions: Watch 重分配
  - /admin/delete_topics: Watch 删除 Topic
```

### 7.6 Kafka 去 ZK 化——KRaft

```
KRaft（Kafka Raft Metadata Mode，Kafka 2.8+）:

┌────────────────────────────────────────────────────────────┐
│  动机:                                                      │
│    1. ZK 成为设计瓶颈（海量 Partition 时性能差）              │
│    2. 运维两套系统（Kafka + ZK）复杂度高                      │
│    3. ZK 和 Kafka 的元数据不一致风险                           │
│                                                              │
│  KRaft 核心思想:                                             │
│    - 用 Kafka 自己管理元数据                                   │
│    - 内部 Topic: @metadata 主题                              │
│    - 元数据节点（Controller Quorum）使用 Raft 协议             │
│    - 所有元数据操作通过 Raft 日志复制                          │
│                                                              │
│  对比:                                                       │
│  ┌──────────────┬─────────────────┬────────────────┐       │
│  │              │   ZK 模式       │   KRaft 模式    │       │
│  ├──────────────┼─────────────────┼────────────────┤       │
│  │ 元数据存储    │  Zookeeper      │  @metadata Topic│       │
│  │ 选举/共识     │  ZK Leader选举  │  Raft 协议       │       │
│  │ Controller选举│  ZK 临时节点     │  Raft Leader    │       │
│  │ 运维组件      │  Kafka + ZK     │  仅 Kafka       │       │
│  │ 海量 Partition│  性能瓶颈        │  好得多         │       │
│  │ 成熟度        │  生产验证        │  3.3+ 生产可用   │       │
│  └──────────────┴─────────────────┴────────────────┘       │
└──────────────────────────────────────────────────────────┘
```

---

## 第八部分：日志清理与压缩

### 8.1 基于时间的删除

```
log.retention.hours = 168（默认 7 天，还可配置 .minutes 和 .ms）

原理:
  LogManager 后台线程定时检查 Segment:
    如果 Segment 的最后修改时间 > retention.ms → 删除整个 Segment 文件组
  
  注意: 只删除非 Active Segment
```

### 8.2 基于大小的删除

```
log.retention.bytes = -1（默认无限制）

原理:
  当一个 Partition 的所有 Segment 总大小 > retention.bytes
  → 删除最老的 Segment，直到小于限制
```

### 8.3 Log Compaction——按 Key 压缩

Log Compaction 是 Kafka 特有的功能，保证**每个 Key 至少保留最新一条消息**。

```
Log Compaction 原理:

  压缩前:
  ┌─────────────────────────────────────────────────────────────┐
  │  Key=K1  Value=V1  Key=K2  Value=V2  Key=K1  Value=V3      │
  │  Offset=0          Offset=1          Offset=2              │
  │  Key=K3  Value=V4  Key=K1  Value=V5                        │
  │  Offset=3          Offset=4                                │
  └─────────────────────────────────────────────────────────────┘

  压缩后（只保留每个 Key 的最新值）:
  ┌─────────────────────────────────────────────────────────────┐
  │  Key=K2  Value=V2  Key=K3  Value=V4  Key=K1  Value=V5      │
  │  Offset=1          Offset=3          Offset=4              │
  └─────────────────────────────────────────────────────────────┘

  Key=K1 的 V1 和 V3 被清理掉了，只保留最新的 V5

使用场景:
  1. 数据库 CDC（只关心每行数据的最新状态）
  2. Key-Value 存储（类似 Redis RDB）
  3. 事件溯源（最终状态 > 中间过程）
```

```
Log Compaction 的实现机制:

┌──────────────────────────────────────────────────────────────┐
│  Cleaner Thread 工作流程:                                    │
│                                                              │
│  1. 选择最脏的 Segment（dirty ratio = 脏消息数/总消息数）     │
│                                                              │
│  2. 构建 Offset Map:                                         │
│     读取整个 Segment，记录:                                   │
│     Map<Key, (Offset, value是否为空?)>                       │
│     重复的 Key → 保留最新 Offset                              │
│                                                              │
│  3. 将 Offset Map 中的消息重新写入新 Segment                  │
│     (跳过脏消息)                                             │
│                                                              │
│  4. 用新 Segment 替换旧 Segment                              │
│                                                              │
│  ┌──────────┐    ┌──────────┐                               │
│  │ 旧 Segment│    │ 新 Segment│                               │
│  │ (含脏数据) │ → │ (干净压缩)│                                │
│  │ K1:V1    │    │ K2:V2    │                               │
│  │ K2:V2    │    │ K3:V4    │  ← K1:V1, K1:V3 被删除       │
│  │ K1:V3    │    │ K1:V5    │                               │
│  │ K3:V4    │    │          │                               │
│  │ K1:V5    │    │          │                               │
│  └──────────┘    └──────────┘                               │
└──────────────────────────────────────────────────────────────┘

删除键（Tombstone）:
  写入 Key=K1, Value=null → 表示删除该 Key
  Cleaner 在遇到 Tombstone 后，保留一段时间（delete.retention.ms）
  保留期过后才真正删除该 Key 的记录
```

### 8.4 Cleaner 线程源码

```scala
// 源码位置: core/src/main/scala/kafka/log/LogCleaner.scala

class LogCleaner(
    initialConfig: CleanerConfig,
    val config: CleanerConfig,
    logDirs: Seq[File],
    logs: Pool[TopicPartition, Log],
    time: Time
) extends Logging {
  
  // 后台清理线程
  private val cleaners = (0 until config.numThreads).map(i => 
    new CleanerThread(i))
  
  // ========== 选择要清理的 Segment ==========
  def pickLogToClean(currentTime: Long): Option[LogToClean] = {
    // 从所有 compacted Topic 中找到最脏的 Partition
    val dirtyLogs = logs.values.filter { log =>
      log.config.compact && 
      log.logSegments.size > 1  // 至少有非活跃 Segment
    }
    
    // 按 dirty ratio 排序，选最大
    val sortedLogs = dirtyLogs
      .map(log => (log, cleanableRatio(log, currentTime)))
      .filter { case (_, ratio) => ratio > config.minCleanableRatio }
      .sortBy { case (_, ratio) => -ratio }  // 降序
    
    sortedLogs.headOption.map { case (log, _) =>
      new LogToClean(log.topicPartition, log, 
        log.firstUncleanableOffset)
    }
  }
  
  // ========== 清理一个 Segment ==========
  private def cleanSegments(
      log: Log,
      firstDirtyOffset: Long,
      upperBoundOffset: Long,
      map: OffsetMap
  ): (Long, immutable.Seq[LogSegment]) = {
    
    // Step 1: 读取 Segment 并填充 OffsetMap
    for (segment <- log.logSegments(firstDirtyOffset, upperBoundOffset)) {
      val records = segment.log.read(...)
      for (batch <- records.batches) {
        for (record <- batch) {
          // 将 Key 对应的最新 Offset 记录到 OffsetMap
          map.put(record.key, record.offset)
        }
      }
    }
    
    // Step 2: 根据 OffsetMap 重新写入干净的消息
    val cleanedSegments = new ListBuffer[LogSegment]
    for ((key, offset) <- map.entries) {
      // 只保留 OffsetMap 中的消息
      cleaned.append(message)
    }
    
    cleanedSegments.toList
  }
}
```

### 8.5 CleanerPoint 与 Dirty Ratio

```
CleanerPoint = 已清理到哪个 Offset 的标记
Dirty Ratio   = 脏消息数 / 总消息数（从 CleanerPoint 到当前 LEO）

  ┌───────────────────────────────────────────────────────────┐
  │  Offset=0 ──► CleanerPoint=100 ──► LEO=500                │
  │              │                                             │
  │              │◄──── Dirty Segment ────►│                   │
  │              │    （需要清理的区域）                          │
  │              │                                             │
  │              假设 400 条消息中有 100 条是脏的                 │
  │              dirty ratio = 100/400 = 25%                   │
  │                                                           │
  │  min.cleanable.dirty.ratio = 0.5（默认）                   │
  │  25% < 50% → 暂不清理                                     │
  └───────────────────────────────────────────────────────────┘

参数:
  log.cleaner.min.cleanable.ratio = 0.5
  → 脏消息占比须 ≥ 50% 才触发清理
  → 避免频繁清理带来的 I/O 开销
```

---

## 第九部分：Kafka 性能优化实战

### 9.1 Producer 端优化

| 参数 | 推荐值 | 说明 |
|------|--------|------|
| `batch.size` | 16384 → 65536（64KB） | 增大 batch 减少请求次数 |
| `linger.ms` | 5-50ms | 等待时间，填满 batch |
| `compression.type` | lz4 / snappy | 压缩传输，lz4 压比高、速度快 |
| `buffer.memory` | 33554432（32MB） | Producer 缓冲区大小 |
| `max.in.flight.requests.per.connection` | 5 | 控制在途请求数 |
| `acks` | 1 或 all | 视场景定（日志 ack=1，订单 ack=all） |
| `retries` | Integer.MAX_VALUE | 无限重试 + delivery.timeout.ms 兜底 |
| `enable.idempotence` | true | 开启幂等（防止重试导致重复） |

```java
// Producer 优化示例
Properties props = new Properties();
props.put("bootstrap.servers", "broker1:9092,broker2:9092");
props.put("batch.size", 65536);               // 64KB
props.put("linger.ms", 10);                    // 10ms
props.put("compression.type", "lz4");         // LZ4 压缩
props.put("buffer.memory", 67108864);          // 64MB
props.put("max.in.flight.requests.per.connection", 5);
props.put("acks", "all");
props.put("retries", Integer.MAX_VALUE);
props.put("delivery.timeout.ms", 120000);     // 2 分钟
props.put("enable.idempotence", true);

// 异步发送 + 回调
producer.send(record, (metadata, exception) -> {
    if (exception != null) {
        log.error("Send failed: ", exception);
    } else {
        log.debug("Sent to partition {}", metadata.partition());
    }
});
```

### 9.2 Broker 端优化

| 参数 | 推荐值 | 说明 |
|------|--------|------|
| `num.network.threads` | CPU 核数 | 网络线程数 |
| `num.io.threads` | CPU 核数 × 2 | IO 线程数 |
| `log.flush.interval.messages` | 10000+ | 依赖 Page Cache，不要频繁 fsync |
| `log.flush.interval.ms` | 1000+ | fsync 间隔 |
| `log.segment.bytes` | 1073741824（1GB） | Segment 大小 |
| `log.retention.hours` | 168（7天） | 保留时间 |
| `num.replica.fetchers` | CPU 核数 | Follower 拉取线程数 |
| `replica.fetch.max.bytes` | 10485760（10MB） | 单次拉取最大字节数 |
| `replica.socket.receive.buffer.bytes` | 65536 | Socket 接收缓冲区 |
| `unclean.leader.election.enable` | false | 禁止脏选举 |

```properties
# Broker 优化示例
num.network.threads=8
num.io.threads=16

# 日志存储
log.segment.bytes=1073741824        # 1GB
log.retention.hours=168             # 7 天
log.index.interval.bytes=4096       # 稀疏索引间隔

# 副本同步
num.replica.fetchers=4
replica.fetch.max.bytes=10485760    # 10MB
replica.fetch.wait.max.ms=500       # 等 500ms 凑 batch

# 可靠性
unclean.leader.election.enable=false
min.insync.replicas=2
default.replication.factor=3
```

### 9.3 Consumer 端优化

| 参数 | 推荐值 | 说明 |
|------|--------|------|
| `fetch.min.bytes` | 10240（10KB） | 最小拉取字节数（减少空拉取） |
| `fetch.max.wait.ms` | 500 | 最大等待时间（凑 batch） |
| `max.partition.fetch.bytes` | 10485760（10MB） | 单 Partition 拉取上限 |
| `max.poll.records` | 500 | 每次 poll 最多返回条数 |
| `enable.auto.commit` | false（推荐） | 手动提交 offset |
| `session.timeout.ms` | 30000（默认） | 心跳超时判定 |
| `heartbeat.interval.ms` | 3000 | 心跳间隔 < session.timeout / 3 |

```java
// Consumer 优化示例
Properties props = new Properties();
props.put("bootstrap.servers", "broker1:9092,broker2:9092");
props.put("group.id", "order-consumer");
props.put("enable.auto.commit", "false");
props.put("max.poll.records", 500);
props.put("fetch.min.bytes", 10240);
props.put("fetch.max.wait.ms", 500);
props.put("session.timeout.ms", 30000);
props.put("heartbeat.interval.ms", 3000);
props.put("partition.assignment.strategy", 
          "org.apache.kafka.clients.consumer.CooperativeStickyAssignor");

// 处理完成后手动提交
while (true) {
    ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(1000));
    for (ConsumerRecord<String, String> record : records) {
        process(record);
    }
    // 关键：处理完再提交
    consumer.commitSync();
}
```

### 9.4 OS 层面优化

```bash
# ========== 文件描述符上限 ==========
ulimit -n 100000

# ========== 虚拟内存 ==========
# vm.swappiness = 1 （尽量不 swap，Page Cache 优先）
sysctl -w vm.swappiness=1

# ========== 脏页刷盘策略 ==========
# vm.dirty_ratio = 60-80（脏页占内存 60-80% 时刷盘）
sysctl -w vm.dirty_ratio=60
sysctl -w vm.dirty_background_ratio=5

# ========== 网络优化 ==========
# Socket 缓冲区
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216

# ========== 磁盘调度器（机械硬盘）==========
echo deadline > /sys/block/sda/queue/scheduler

# 使用独立磁盘（或 SSD）存放 Kafka 数据
# /data1/kafka-logs, /data2/kafka-logs, ...
```

---

## 第十部分：Kafka vs RocketMQ 深度对比

### 10.1 架构对比

```
┌──────────────────┬─────────────────────┬──────────────────────┐
│                  │        Kafka        │       RocketMQ       │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 注册中心         │ ZK / KRaft          │ NameServer（自研）     │
│ 元数据管理        │ Controller + ZK     │ Broker 自主上报       │
│ CAP 偏好          │ CP（注册中心）       │ AP（注册中心）         │
│ 消息模型          │ Topic + Partition   │ Topic + Queue         │
│ 事务消息          │ 幂等 + 事务 API      │ 半消息 + 回查          │
│ 延迟消息          │ 不原生支持（需自己实现）│ 18 级时间轮（原生）     │
│ 顺序消息          │ Partition 内有序    │ Queue 内有序           │
│ 消息过滤          │ 不原生支持（需 Consumer 处理）│ Tag + SQL92 过滤  │
│ 批量消息          │ ✓ 原生支持          │ ✓ 支持                │
│ 消息回溯          │ ✓ 按时间/Offset      │ ✓ 按时间/Offset       │
│ 死信队列          │ ✗（需自己实现）      │ ✓ 原生支持             │
│ 流处理            │ Kafka Streams       │ RocketMQ Streams      │
└──────────────────┴─────────────────────┴──────────────────────┘
```

### 10.2 存储机制对比

```
┌──────────────────┬─────────────────────┬──────────────────────┐
│                  │        Kafka        │       RocketMQ       │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 存储结构          │ 每个 Partition 独立日志│ 所有 Topic 混合 CommitLog │
│ 索引方式          │ 稀疏索引（.index）    │ ConsumeQueue 密集索引  │
│ 读取方式          │ sendfile 零拷贝      │ mmap 内存映射         │
│ 海量 Topic        │ 差（文件句柄多）      │ 好（单一 CommitLog）   │
│ 单 Topic 性能      │ 极高                 │ 高                   │
│ 清理策略          │ 按时间/大小 + 压缩    │ 按时间 + 文件过期       │
│ 磁盘 I/O          │ 顺序写（单 Partition） │ 顺序写（全局 CommitLog）│
└──────────────────┴─────────────────────┴──────────────────────┘

核心差异图解:

  Kafka: 每个 Partition 一个目录
    /kafka-logs/
      ├── orders-0/          ← 独立日志
      │   ├── 000.log
      │   ├── 000.index
      │   └── 000.timeindex
      └── orders-1/
          ├── 000.log
          └── ...

  问题: 10000 个 Topic × 3 Partition = 30000 个目录 × 每个 3 个文件
        = 90000 个文件句柄 → 文件系统压力大

  RocketMQ: 所有 Topic 共享 CommitLog
    /store/
      ├── commitlog/
      │   ├── 00000000000000000000
      │   └── 00000000001073741824
      └── consumequeue/
          ├── orders/0/
          │   └── 00000000000000000000
          └── orders/1/
              └── ...

  优势: CommitLog 只有少量大文件，文件句柄少
```

### 10.3 事务消息对比

```
┌──────────────────┬─────────────────────┬──────────────────────┐
│                  │        Kafka        │       RocketMQ       │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 事务模型          │ 通用事务 API         │ 半消息（Half Message）│
│ 实现方式          │ PID + Transaction   │ prepare → commit/     │
│                  │ Coordinator         │ rollback              │
│ 幂等              │ PID + SeqNo         │ 无原生幂等            │
│ 消费-处理-生产     │ 原生支持（sendOffsets）│ 需要手动编码           │
│ 学习难度          │ 较高                 │ 较低                  │
│ 适用场景          │ 流处理 + 事务        │ 业务消息 + 事务        │
└──────────────────┴─────────────────────┴──────────────────────┘

Kafka 事务流程:
  initTransactions() → beginTransaction() → send() → 
  sendOffsetsToTransaction() → commitTransaction()

RocketMQ 事务流程:
  sendMessageInTransaction() → executeLocalTransaction() →
  commit / rollback / unknow → checkLocalTransaction()
```

### 10.4 消费模型对比

```
┌──────────────────┬─────────────────────┬──────────────────────┐
│                  │        Kafka        │       RocketMQ       │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 消费方式          │ Pull（长轮询默认）    │ Pull（长轮询默认）    │
│ 消费组            │ Consumer Group      │ Consumer Group       │
│ 负载均衡          │ Rebalance 协议       │ Rebalance 协议        │
│ 消费进度存储       │ __consumer_offsets  │ Broker 内存 + 磁盘    │
│ 广播消费          │ 不同 Group           │ 不同 Group / 广播模式  │
│ 集群消费          │ 同一 Group           │ 同一 Group            │
│ 消息重试          │ 无原生支持            │ 延时重试 + 死信队列    │
│ 消费模式          │ Center（GroupCoord） │ Center（Broker）     │
└──────────────────┴─────────────────────┴──────────────────────┘
```

### 10.5 高可用对比

```
┌──────────────────┬─────────────────────┬──────────────────────┐
│                  │        Kafka        │       RocketMQ       │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 副本机制          │ ISR + HW/LEO        │ Master-Slave          │
│ 同步方式          │ 异步拉取（Fetcher）   │ 同步双写 / 异步复制    │
│ 数据一致性        │ 最终一致性           │ 最终一致性 / 强一致性    │
│ Leader 选举       │ Controller + ISR    │ 手动 / Dledger Raft   │
│ 注册中心          │ ZK（去 ZK 化后 KRaft) │ NameServer            │
│ 注册中心 HA        │ ZK 自身 HA          │ 无状态（无 HA 问题）    │
│ 故障恢复          │ 自动                 │ 手动 / Dledger 自动    │
│ 跨机房            │ MirrorMaker 2       │ 无原生支持             │
└──────────────────┴─────────────────────┴──────────────────────┘
```

### 10.6 性能对比

```
┌──────────────────┬─────────────────────┬──────────────────────┐
│                  │        Kafka        │       RocketMQ       │
├──────────────────┼─────────────────────┼──────────────────────┤
│ 单机吞吐（写入）   │ 100万+ 条/秒         │ 10万+ 条/秒           │
│ 单机吞吐（消费）   │ 百万级条/秒          │ 十万级条/秒           │
│ 端到端延迟        │ 毫秒级               │ 毫秒级                │
│ 海量 Topic        │ 弱项                 │ 强项（单文件存储）     │
│ 长尾延迟          │ 低（顺序读写）        │ 低                    │
│ 水平扩展          │ 增加 Broker + Partition│ 增加 Broker         │
│ 批量优化          │ 原生极致优化          │ 有批量优化             │
└──────────────────┴─────────────────────┴──────────────────────┘

性能差异原因:
  1. Kafka 的零拷贝 sendfile → Consumer 不经过用户态
  2. Kafka 的顺序写入 + Page Cache → Producer 写极快
  3. RocketMQ mmap → 需要处理缺页中断
  4. Kafka 稀疏索引 → 索引开销小
```

### 10.7 选型建议

```
┌──────────────────────────────────────────────────────────────┐
│  选 Kafka:                                                    │
│    ✓ 大数据场景（日志采集、流计算、数据管道）                    │
│    ✓ 海量数据写入（百万级 TPS）                                 │
│    ✓ 需要消息回溯能力                                          │
│    ✓ 强依赖流处理（Kafka Streams / Flink 集成）                  │
│    ✓ Topic 数量不多（< 1000 个 Topic）                         │
│    ✓ 团队能同时运维 ZK + Kafka                                 │
│                                                              │
│  选 RocketMQ:                                                 │
│    ✓ 业务消息场景（订单、支付、库存）                            │
│    ✓ 需要事务消息（半消息模型更简单）                             │
│    ✓ 需要延迟消息（原生 18 级时间轮）                            │
│    ✓ 需要死信队列                                              │
│    ✓ 海量 Topic 场景（> 1000 个 Topic）                        │
│    ✓ 团队熟悉 Java（阿里巴巴系）                                 │
│    ✓ 不想维护 ZK                                               │
│                                                              │
│  混合使用（大厂常见架构）:                                      │
│    Kafka → 日志、用户行为、数据管道                             │
│    RocketMQ → 交易、订单、支付等业务消息                         │
└──────────────────────────────────────────────────────────────┘
```

---

## 第十一部分：面试高频题 20 问

**Q1: Kafka 为什么快？**

答：四大支柱：① Partition 内顺序写磁盘（O(1)）；② OS Page Cache 缓存热数据（不依赖 JVM 堆，无 GC 压力）；③ sendfile 零拷贝（Consumer 拉取数据不经过用户态）；④ 批量处理（Producer batch + Broker batch + Consumer batch）。

---

**Q2: Kafka 的 ISR 是什么？和 OSR 有什么区别？**

答：ISR = In-Sync Replicas，与 Leader 保持同步的副本集合（LEO ≥ HW，且 replica.lag.time.max.ms 内有 Fetch）。OSR = Out-of-Sync Replicas，即 ISR 之外的副本。AR = ISR + OSR。Leader 选举优先从 ISR 中选。

---

**Q3: Kafka 如何保证消息不丢失？**

答：三层保障：
1. Producer：acks=all + retries=MAX + enable.idempotence=true
2. Broker：replication.factor=3 + min.insync.replicas=2 + unclean.leader.election.enable=false
3. Consumer：enable.auto.commit=false + 处理完再手动提交

---

**Q4: Kafka 如何保证消息不重复？**

答：开启幂等（enable.idempotence=true），Broker 端根据 PID + SeqNo 去重（最近 5 条）。或 Consumer 端做幂等（唯一键去重、Redis SETNX）。

---

**Q5: Kafka 的 Rebalance 是什么？什么时候触发？**

答：Rebalance = Consumer Group 中消费者分配 Partition 的重新调整。触发条件：① Consumer 加入/离开 Group；② 心跳超时（session.timeout.ms）；③ Topic Partition 数量变化；④ 订阅 Topic 变化。Rebalance 期间该 Group 停止消费（Eager 协议）。

---

**Q6: Kafka 如何解决 Rebalance 的惊群问题？**

答：① 使用 CooperativeStickyAssignor（增量协作，不全部暂停）；② 增大 session.timeout.ms 和 heartbeat.interval.ms；③ 合理设置 max.poll.interval.ms 避免处理超时触发 Rebalance；④ Consumer 数量 ≤ Partition 数量（避免空闲 Consumer 频繁加入退出）。

---

**Q7: Kafka 的 HW 和 LEO 是什么？**

答：LEO = Log End Offset，每个副本最后一条消息的 offset + 1；HW = High Watermark，所有 ISR 副本中最小的 LEO。消费者只能读取 ≤ HW 的消息（保证这些消息已被 ISR 多数确认）。

---

**Q8: Kafka 的副本同步机制是怎样的？**

答：Follower 主动向 Leader 发送 Fetch 请求，拉取 offset ≥ 自身 LEO 的消息。Leader 返回消息 + 当前 HW。Follower 写入后更新 HW。replica.lag.time.max.ms 内没有 Fetch 的副本被踢出 ISR。

---

**Q9: Kafka 的 Leader 选举机制？**

答：由 Controller 负责：① ISR 中选；② 优先按 AR 顺序（先创建的先选）；③ 如果 ISR 为空 + unclean.leader.election.enable=true → 从 OSR 中选（可能丢数据）。

---

**Q10: Kafka 的分区策略有哪些？**

答：① 指定 Partition → 直接写入；② 指定 Key → hash(key) % n；③ 都不指定 → Sticky Partition（2.4+，随机选一个直到 batch 满）。可实现自定义 Partitioner。

---

**Q11: Kafka 的消息顺序性如何保证？**

答：Partition 内天然有序（追加写入）。要保证业务顺序：① 同一 Key → 同一 Partition（hash 路由）；② 单 Partition 内单线程消费（Consumer 内轮询）。

---

**Q12: Kafka 的消费进度存在哪里？**

答：存在 Kafka 内部 Topic `__consumer_offsets` 中（50 个 Partition，3 副本）。旧版存在 ZK 中（已废弃）。

---

**Q13: Kafka 的事务消息原理？**

答：基于 PID + Transaction Coordinator + `__transaction_state` 主题。流程：initTransactions（分配 PID）→ beginTransaction → send + sendOffsets → commitTransaction（写入 COMMIT 标记）。Consumer 隔离级别 read_committed 时过滤未提交事务消息。

---

**Q14: Kafka 如何处理消息积压？**

答：① 增加 Consumer 数量（不能超过 Partition 数）；② 增加 Partition 数量（需要业务允许）；③ 提高 Consumer 处理能力（扩容、异步处理）；④ 短期方案：临时增加 Partition + 新 Consumer Group 并行消费。

---

**Q15: Kafka 的零拷贝是如何实现的？**

答：使用 Java NIO 的 `FileChannel.transferTo()` → Linux `sendfile()` 系统调用。数据从磁盘 → Page Cache → Socket Buffer → 网卡，不经过用户态。只有 2 次 DMA 拷贝 + 2 次上下文切换（传统方式 4+4）。

---

**Q16: Log Compaction 是什么？适用什么场景？**

答：按 Key 压缩：每个 Key 只保留最新一条消息。适用场景：① 数据库 CDC（只关心最新状态）；② KV 存储（如 Redis AOF 快照）；③ 事件溯源。不适用：需要每一条历史消息的场景。

---

**Q17: Kafka 的 Controller 是做什么的？**

答：Controller 是集群管理者：① Leader 选举；② 元数据管理（Topic / Partition / Replica）；③ Broker 上下线感知；④ 分区重分配；⑤ ISR 管理。Controller 通过 ZK `/controller` 临时节点选举。

---

**Q18: Kafka 和 RocketMQ 的区别？**

答：核心差异：
- 存储：Kafka Partition 独立日志 vs RocketMQ 全局 CommitLog
- 注册中心：Kafka ZK/KRaft vs RocketMQ NameServer（无状态）
- 事务：Kafka 通用 API vs RocketMQ 半消息模型
- 零拷贝：Kafka sendfile vs RocketMQ mmap
- 海量 Topic：Kafka 弱 vs RocketMQ 强
- 适用：Kafka 大数据流处理 vs RocketMQ 业务消息

---

**Q19: Kafka 为什么要去 ZK？KRaft 是什么？**

答：ZK 成为瓶颈/运维复杂/元数据不一致。KRaft 用 Kafka 自己的 Raft 协议管理元数据：内部 @metadata Topic 存储元数据，Controller Quorum 使用 Raft 通信，简化架构，提升海量 Partition 性能。

---

**Q20: ack=all 时一定能保证消息不丢吗？**

答：不能 100% 保证。场景：全部 ISR 收到消息但返回 ack 前 Leader 宕机，消息尚未到 HW → 消费者不可见 → 新 Leader 选举后该消息被视为未提交。改进：配合 `min.insync.replicas=replication.factor`，所有副本全部确认 → 但可用性降低。

---

## 附录

### 附录 A：Kafka 核心参数速查表

```
┌────────────────────────────────┬──────────┬──────────────────────────┐
│ 参数名                          │ 默认值   │ 说明                     │
├────────────────────────────────┼──────────┼──────────────────────────┤
│  **Broker 核心**                                                │
│ broker.id                      │ 0        │ Broker 唯一 ID            │
│ listeners                      │ PLAINTEXT│ 监听地址和协议             │
│ log.dirs                       │ /tmp/kafka-logs │ 日志存储目录     │
│ num.partitions                 │ 1        │ 默认 Partition 数          │
│ default.replication.factor     │ 1        │ 默认副本因子               │
│ num.network.threads            │ 3        │ 网络线程数                │
│ num.io.threads                 │ 8        │ IO 线程数                 │
├────────────────────────────────┼──────────┼──────────────────────────┤
│  **日志存储**                                                    │
│ log.segment.bytes              │ 1GB      │ Segment 大小              │
│ log.retention.hours            │ 168(7天) │ 日志保留时间               │
│ log.retention.bytes            │ -1       │ 日志保留大小（-1 无限）     │
│ log.cleanup.policy             │ delete   │ 清理策略 delete/compact   │
│ log.cleaner.min.cleanable.ratio│ 0.5      │ 最小脏比例                 │
│ log.index.interval.bytes       │ 4096     │ 稀疏索引间隔               │
│ log.flush.interval.messages    │ 922337203│ fsync 消息间隔              │
│ log.flush.interval.ms          │ 922337203│ fsync 时间间隔              │
├────────────────────────────────┼──────────┼──────────────────────────┤
│  **副本机制**                                                    │
│ replica.lag.time.max.ms        │ 30000    │ Follower 最大延迟判定 ISR  │
│ replica.fetch.max.bytes        │ 1MB      │ Follower 单次拉取上限       │
│ min.insync.replicas            │ 1        │ 最小 ISR 数量              │
│ unclean.leader.election.enable │ false    │ 是否允许脏 Leader 选举     │
├────────────────────────────────┼──────────┼──────────────────────────┤
│  **Producer 核心**                                               │
│ batch.size                     │ 16384(16K)│ batch 大小              │
│ linger.ms                      │ 0        │ 等待填充时间              │
│ buffer.memory                  │ 32MB     │ Producer 缓冲区大小       │
│ acks                           │ all      │ 确认机制 0/1/all         │
│ retries                        │ 2147483647│ 重试次数                │
│ compression.type               │ none     │ 压缩 none/gzip/snappy/lz4│
│ enable.idempotence            │ true     │ 幂等性                   │
│ max.in.flight.requests.per.conn│ 5        │ 最大在途请求数            │
├────────────────────────────────┼──────────┼──────────────────────────┤
│  **Consumer 核心**                                               │
│ group.id                       │ (required)│ Consumer Group ID      │
│ enable.auto.commit             │ true     │ 自动提交 offset          │
│ auto.commit.interval.ms        │ 5000     │ 自动提交间隔              │
│ session.timeout.ms             │ 45000    │ 心跳超时（触发 Rebalance）│
│ heartbeat.interval.ms          │ 3000     │ 心跳间隔                 │
│ max.poll.interval.ms           │ 300000   │ 两次 poll 最大间隔        │
│ max.poll.records               │ 500      │ 单次 poll 最大记录数      │
│ fetch.min.bytes                │ 1        │ 最小拉取字节数            │
│ fetch.max.wait.ms              │ 500      │ 最大拉取等待时间          │
│ auto.offset.reset              │ latest   │ 无 offset 时的策略        │
└────────────────────────────────┴──────────┴──────────────────────────┘
```

### 附录 B：Kafka 版本演进

```
┌──────────────────┬──────────────────────────────────────────────┐
│  版本             │  重要特性                                     │
├──────────────────┼──────────────────────────────────────────────┤
│  0.8.x (2013)    │  内部 Topic 存储 offset，不再存 ZK              │
│  0.9.x (2015)    │  新 Consumer API，安全特性（SSL/SASL）          │
│  0.10.x (2016)   │  Kafka Streams，Timestamp 字段                │
│  0.11.x (2017)   │  事务（Exactly Once）、幂等 Producer             │
│  1.0.x (2017)    │  Controller 改进，JMX 监控增强                  │
│  2.0.x (2018)    │  前缀 ACL，主机名验证增强                       │
│  2.4.x (2019)    │  Cooperative Rebalance，Sticky Partition      │
│  2.5.x (2020)    │  TLS 1.3，metrics 改进                        │
│  2.6.x (2020)    │  KIP-500（KRaft 预览）                         │
│  2.7.x (2020)    │  KRaft 控制平面可用                            │
│  2.8.x (2021)    │  KRaft 早期访问，去 ZK                          │
│  3.0.x (2021)    │  KRaft 生产就绪预览，移除 ZK 依赖选项             │
│  3.3.x (2022)    │  KRaft 生产可用（推荐新集群使用）                  │
│  3.5+ (2023)     │  KRaft 持续完善，ZK 模式即将废弃                  │
│  4.0 (计划)       │  彻底移除 ZK，仅 KRaft                          │
└──────────────────┴──────────────────────────────────────────────┘
```

### 附录 C：与已有文档衔接关系

```
本文档在 WorkBuddy 源码学习系列中的位置:

已完成的 24 份文档:
  1. HashMap 源码
  2. ConcurrentHashMap 源码
  3. ThreadPoolExecutor 源码
  4. synchronized + AQS + ReentrantLock 源码
  5. volatile + JMM + 单例模式 源码
  6. Java 基础（String/equals/泛型/反射/异常）源码
  7. Java 8+ 新特性（Stream/Optional/CompletableFuture）源码
  8. Java 与 Tomcat 类加载机制 源码
  9. Spring IoC/DI 源码
  10. Spring AOP（JDK Proxy/CGLIB/@Transactional）源码
  11. Spring Cloud + MyBatis 源码
  12. Dubbo 源码
  13. Spring 全家桶综合串讲
  14. MySQL 索引底层原理
  15. MySQL EXPLAIN 实战 + 慢查询优化
  16. MySQL 事务与锁（隔离级别 + MVCC）
  17. Redis 数据结构底层原理
  18. Nginx 底层原理
  19. Netty 底层原理
  20. Redis 缓存问题 + 分布式锁 + 集群
  21. Elasticsearch 底层原理
  22. Zookeeper 底层原理
  23. RocketMQ 底层原理
  ★ 25. Kafka 底层原理（本文档）

建议交叉阅读:
  Kafka + RocketMQ:         存储引擎设计对比（独立日志 vs 统一 CommitLog）
  Kafka + Netty:            NIO 网络通信（Kafka 的 SocketServer 基于 NIO）
  Kafka + Zookeeper:        注册中心与协调机制对比
  Kafka + Elasticsearch:    Kafka 作为 ES 的数据管道上游
  Kafka + MySQL:            CDC（Canal → Kafka → ES/Redis）数据同步架构
  Kafka + Spring全家桶:      Spring Kafka + Spring Cloud Stream 集成
```

---

> **总结**: Kafka 通过 Partition 内顺序写 + Page Cache + sendfile 零拷贝 + 批量处理四大支柱实现了极高的吞吐量。ISR 机制保证数据可靠性，Controller + ZK（或 KRaft）管理集群元数据。Kafka 和 RocketMQ 各有优势：Kafka 适合大数据流处理和高吞吐场景，RocketMQ 适合业务消息和事务消息场景。理解 Kafka 的存储引擎和副本机制，是深入掌握分布式消息系统的关键。
