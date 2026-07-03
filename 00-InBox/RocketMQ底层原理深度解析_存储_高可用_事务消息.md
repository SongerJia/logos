# RocketMQ 底层原理深度解析 —— 存储 / 高可用 / 事务消息

---

## 第一部分：架构全景

### 1.1 RocketMQ 是什么

RocketMQ 是阿里巴巴开源的**分布式消息中间件**，基于**纯 Java 实现**，2017 年成为 Apache 顶级项目。它借鉴了 Kafka 的设计并做了大量改进，特别适合**金融级高可靠**场景（如双 11 核心交易链路）。

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         RocketMQ 物理部署架构                              │
│                                                                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                      │
│  │ NameServer  │  │ NameServer  │  │ NameServer  │   ← 无状态路由中心    │
│  │  (节点1)    │  │  (节点2)    │  │  (节点3)    │     互相不通信，最终一致 │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                      │
│         │                │                │                              │
│    ┌────┴────┐      ┌────┴────┐      ┌────┴────┐                         │
│    │ Broker  │      │ Broker  │      │ Broker  │                         │
│    │ Master  │◄────►│ Master  │◄────►│ Master  │   ← Broker 集群         │
│    │         │      │         │      │         │                         │
│    │  Slave  │      │  Slave  │      │  Slave  │   ← 主从同步            │
│    └────┬────┘      └────┬────┘      └────┬────┘                         │
│         │                │                │                              │
│    ┌────┴─────────────────┴─────────────────┴────┐                        │
│    │               Producer / Consumer             │                        │
│    │                                              │                        │
│    │  Producer-1  Producer-2  Consumer-1 Consumer-2│                       │
│    └──────────────────────────────────────────────┘                        │
└─────────────────────────────────────────────────────────────────────────┘
```

**四大核心角色：**

| 角色 | 职责 | 特点 |
|------|------|------|
| **NameServer** | 路由注册中心 | 无状态、不通信、CAP 的 AP、类似 DNS |
| **Broker** | 消息存储与转发 | 接收 Producer 消息、投递给 Consumer |
| **Producer** | 消息生产者 | 从 NameServer 获取 Broker 路由 |
| **Consumer** | 消息消费者 | 从 NameServer 获取 Broker 路由，拉取消息 |

### 1.2 与 Kafka 架构的差异

| 维度 | RocketMQ | Kafka |
|------|----------|-------|
| **注册中心** | NameServer（自研，无状态） | Zookeeper（外部依赖） |
| **存储模型** | CommitLog（所有 Topic 混合写入）+ ConsumeQueue | Partition（按 Topic 独立目录） |
| **消费模型** | Pull + Push（长轮询 Long Polling） | Pull（Kafka Streams 除外） |
| **顺序消息** | 天然支持（队列内有序） | 单个 Partition 内有序 |
| **事务消息** | 原生支持（半消息 + 回查） | 仅支持幂等 Producer (KIP-98) |
| **延迟消息** | 18 级时间轮 | tick 定时扫描 |
| **消息过滤** | Tag + SQL92 表达式 | 客户端过滤 |
| **高可用** | Master-Slave + Dledger (Raft) | ISR (Leader-Follower) |

### 1.3 一条消息的旅程

```
Producer                              NameServer                           Consumer
   │                                      │                                    │
   │ ① 定时获取 Broker 路由信息           │                                    │
   │─────────────────────────────────────►│                                    │
   │◄─────────────────────────────────────│                                    │
   │                                      │                                    │
   │ ② 发送消息到 Broker                  │         ④ 获取 Broker 路由           │
   │──────────────────┐                   │◄───────────────────────────────────│
   │                  │                   │────────────────────────────────────►│
   │                  ▼                   │                                    │
   │            ┌──────────┐              │           ⑤ 拉取消息               │
   │            │  Broker  │              │───────────────────────────────────►│
   │            │ Master   │              │                                    │
   │            │          │              │                                    │
   │            │ ③ CommitLog                                             │
   │            │    ↓                                                       │
   │            │ ③ ConsumeQueue                                            │
   │            │    ↓                                                       │
   │            │ ③ 异步复制到 Slave                                        │
   │            └──────────┘                                                │
   │                                                                         │
   └─────────────────────────────────────────────────────────────────────────┘
```

**核心流程：**
1. NameServer 启动，等待 Broker/Producer/Consumer 连接
2. Broker 启动后向所有 NameServer 注册 Topic 路由信息（每 30s 心跳续约）
3. Producer 从 NameServer 获取 Topic 路由，选择 MessageQueue 发送
4. Consumer 从 NameServer 获取路由，对 MessageQueue 进行 Rebalance 分配
5. Broker 将消息写入 CommitLog（顺序写磁盘），然后构建 ConsumeQueue 索引
6. Consumer 从 Broker 拉取消息并消费

---

## 第二部分：NameServer —— 无状态路由中心

### 2.1 架构设计

```
┌──────────────────────────────────────────────────────┐
│                  NameServer 架构                       │
│                                                       │
│  ┌─────────────────────────────────────────────────┐ │
│  │              RouteInfoManager                    │ │
│  │                                                  │ │
│  │  topicQueueTable: Map<String,List<QueueData>>    │ │
│  │       Topic → 该 Topic 有哪些 Broker 的队列       │ │
│  │                                                  │ │
│  │  brokerAddrTable: Map<String,BrokerData>         │ │
│  │       BrokerName → Broker 的 IP + HA 地址        │ │
│  │                                                  │ │
│  │  clusterAddrTable: Map<String,Set<String>>       │ │
│  │       集群名 → 该集群下的 Broker 名称集合         │ │
│  │                                                  │ │
│  │  brokerLiveTable: Map<String,Long>              │ │
│  │       Broker 地址 → 最后心跳时间戳               │ │
│  │                                                  │ │
│  │  filterServerTable: Map<String,List<String>>     │ │
│  │       Broker 地址 → FilterServer 列表            │ │
│  └─────────────────────────────────────────────────┘ │
│                                                       │
│  特点:                                                │
│  - 多个 NameServer 之间**不通信**                     │
│  - 最终一致性（Broker 向所有 NameServer 注册）        │
│  - 无持久化，重启后数据从 Broker 心跳恢复              │
└──────────────────────────────────────────────────────┘
```

### 2.2 RouteInfoManager 源码

```java
public class RouteInfoManager {
    // Topic → 该 Topic 的消息队列分布
    private final HashMap<String, List<QueueData>> topicQueueTable;
    // BrokerName → Broker 数据（集群名 + 地址）
    private final HashMap<String, BrokerData> brokerAddrTable;
    // 集群名 → Broker 名称集合
    private final HashMap<String, Set<String>> clusterAddrTable;
    // Broker 地址 → 最后心跳时间戳
    private final HashMap<String, Long> brokerLiveTable;
    // Broker 地址 → FilterServer 列表
    private final HashMap<String, List<String>> filterServerTable;
}
```

**数据结构关系图：**

```
topicQueueTable:                        brokerAddrTable:
  "order_topic"                         "broker-a"
    → [QueueData(broker-a, 4),           → BrokerData(
        QueueData(broker-b, 4)]              clusterName: "DefaultCluster",
                                              brokerAddrs: {
  "log_topic"                                 0: "192.168.1.1:10911",
    → [QueueData(broker-a, 8)]                1: "192.168.1.2:10911"
                                              })

clusterAddrTable:                       brokerLiveTable:
  "DefaultCluster"                        "192.168.1.1:10911"  → 1625000000000
    → {"broker-a", "broker-b"}            "192.168.1.2:10911"  → 1625000005000
```

### 2.3 Broker 注册流程

```java
// DefaultRequestProcessor.processRequest()
// → RequestCode.REGISTER_BROKER 分支

public RegisterBrokerResult registerBroker(
    final String clusterName,      // 集群名
    final String brokerAddr,       // Broker IP:Port
    final String brokerName,       // Broker 名称
    final long brokerId,           // 0=Master, >0=Slave
    final String haServerAddr,     // HA Service 地址
    final TopicConfigSerializeWrapper topicConfigWrapper,  // Topic 配置
    final List<String> filterServerList,
    final Channel channel
) {
    RegisterBrokerResult result = new RegisterBrokerResult();

    try {
        // ========== 步骤1: 加写锁 ==========
        this.lock.writeLock().lockInterruptibly();

        // ========== 步骤2: 更新 clusterAddrTable ==========
        Set<String> brokerNames = this.clusterAddrTable.get(clusterName);
        if (brokerNames == null) {
            brokerNames = new HashSet<>();
            this.clusterAddrTable.put(clusterName, brokerNames);
        }
        brokerNames.add(brokerName);

        // ========== 步骤3: 更新 brokerAddrTable ==========
        BrokerData brokerData = this.brokerAddrTable.get(brokerName);
        if (brokerData == null) {
            // 先注册 BrokerData
            BrokerData newBrokerData = new BrokerData(
                clusterName, brokerName, new HashMap<>()
            );
            // 第一次注册：设置 Master 和 Slave 地址
            if (brokerId == MixAll.MASTER_ID) {
                // Master: 设置 Master 地址
                newBrokerData.getBrokerAddrs().put(MixAll.MASTER_ID, brokerAddr);
            } else {
                // Slave: 先占位
                newBrokerData.getBrokerAddrs().put(brokerId, brokerAddr);
            }
            this.brokerAddrTable.put(brokerName, newBrokerData);
        } else {
            // 已注册：追加或更新地址
            String oldAddr = brokerData.getBrokerAddrs().get(brokerId);
            if (!brokerAddr.equals(oldAddr)) {
                brokerData.getBrokerAddrs().put(brokerId, brokerAddr);
            }
        }

        // ========== 步骤4: 更新 topicQueueTable ==========
        if (brokerId == MixAll.MASTER_ID) {
            // 只有 Master 才注册 Topic 路由
            for (TopicConfig topicConfig : topicConfigWrapper.getTopicConfigTable().values()) {
                String topicName = topicConfig.getTopicName();
                List<QueueData> queueList = this.topicQueueTable.get(topicName);
                if (queueList == null) {
                    queueList = new LinkedList<>();
                    this.topicQueueTable.put(topicName, queueList);
                }

                // 检查 QueueData 是否已存在
                QueueData oldQueueData = findQueueData(brokerName, queueList);
                if (oldQueueData == null) {
                    // 新注册 QueueData
                    queueList.add(new QueueData(
                        brokerName,
                        topicConfig.getReadQueueNums(),   // 读队列数
                        topicConfig.getWriteQueueNums(),   // 写队列数
                        topicConfig.getPerm()              // 权限
                    ));
                } else {
                    // 更新写队列数（支持动态扩容）
                    oldQueueData.setWriteQueueNums(topicConfig.getWriteQueueNums());
                }
            }
        }

        // ========== 步骤5: 更新心跳时间 ==========
        this.brokerLiveTable.put(brokerAddr, System.currentTimeMillis());

    } finally {
        this.lock.writeLock().unlock();
    }
    return result;
}
```

**关键设计：**
- **只有 Master 注册 Topic 路由**：Slave 只作为数据副本，消费者不直接从 Slave 读取
- **写队列数可扩容**：动态增加 WriteQueueNums 不会影响已有消费进度
- **读队列数需等消息过期**：减少 ReadQueueNums 要等 ConsumeQueue 中的消息全部被消费

### 2.4 路由剔除机制

```java
// NamesrvController.initialize() 中启动定时任务
// 每 10 秒扫描一次 brokerLiveTable

this.scheduledExecutorService.scheduleAtFixedRate(
    new Runnable() {
        @Override
        public void run() {
            RouteInfoManager.this.scanNotActiveBroker();
        }
    },
    5, 10, TimeUnit.SECONDS
);

// scanNotActiveBroker():
public void scanNotActiveBroker() {
    Iterator<Entry<String, Long>> it = this.brokerLiveTable.entrySet().iterator();
    while (it.hasNext()) {
        Entry<String, Long> entry = it.next();
        // 超过 120 秒没有心跳 → 剔除
        if (System.currentTimeMillis() - entry.getValue() > 120000) {
            this.unRegisterBroker(entry.getKey());
            it.remove();
        }
    }
}
```

### 2.5 NameServer vs Zookeeper vs Nacos

| 维度 | NameServer | Zookeeper | Nacos |
|------|------------|-----------|-------|
| 一致性 | 最终一致 | CP (ZAB) | AP (Distro) + CP (Raft) |
| 持久化 | 无 | 有 | 有 (MySQL/Derby) |
| 通信 | 单节点独立 | 集群选举 | 集群同步 |
| 健康检查 | 心跳超时 | 临时节点 | 心跳 + 主动探测 |
| CAP | AP | CP | AP + CP 切换 |
| 运维成本 | 极低 | 高 | 中 |
| 适用规模 | 万级 Topic | 千级节点 | 十万级实例 |
| 设计哲学 | 简单即正确 | 强一致性 | 功能全面 |

**NameServer 的设计哲学：**
> "NameServer 之间不通信，也不做持久化。Broker 同时向所有 NameServer 注册。即使所有 NameServer 全挂了，已经建立的 Producer-Broker-Consumer 链路不受影响，只是新的路由变更无法感知。重启 NameServer 后，Broker 心跳会自动恢复路由信息。"

---

## 第三部分：消息存储 —— CommitLog + ConsumeQueue + IndexFile

这是 RocketMQ 最核心的设计，也是它区别于 Kafka 的地方。

### 3.1 三文件存储模型

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      RocketMQ 存储模型                                    │
│                                                                          │
│  store/                                                                  │
│  ├── commitlog/                     ← 所有 Topic 的消息混合顺序写入       │
│  │   ├── 00000000000000000000       ← 1GB 一个文件                        │
│  │   ├── 00000000001073741824                                              │
│  │   └── ...                                                              │
│  │                                                                        │
│  ├── consumequeue/                  ← 每个 Topic/Queue 的索引             │
│  │   ├── TopicA/                                                         │
│  │   │   ├── 0/                    ← Queue ID 0                         │
│  │   │   │   ├── 00000000000000000000                                    │
│  │   │   │   └── ...                                                     │
│  │   │   └── 1/                    ← Queue ID 1                         │
│  │   └── TopicB/                                                         │
│  │                                                                        │
│  ├── index/                         ← 基于 Key（MessageID/Key）的查询    │
│  │   ├── 20250615100000000          ← 时间戳命名                          │
│  │   └── ...                                                              │
│  │                                                                        │
│  └── config/                                                             │
│      ├── consumerOffset.json        ← 消费者偏移量                        │
│      ├── delayOffset.json           ← 延迟消息进度                        │
│      └── ...                                                              │
└─────────────────────────────────────────────────────────────────────────┘
```

**三文件关系图：**

```
CommitLog（所有消息混合顺序写）
┌──────────────────────────────────────────────────────────────────────────┐
│  offset=0    │  offset=100  │  offset=200  │  offset=300  │  offset=400  │
│  TopicA-Q0   │  TopicB-Q0   │  TopicA-Q1   │  TopicC-Q0   │  TopicA-Q0   │
│  msg1        │  msg1        │  msg1        │  msg1        │  msg2        │
└──────────────────────────────────────────────────────────────────────────┘
        │              │              │              │
        ▼              ▼              ▼              ▼
ConsumeQueue（每个 Topic/Queue 的索引，按顺序追加）
┌──────────────────────┐   ┌──────────────────────┐
│  TopicA / Queue-0    │   │  TopicA / Queue-1    │
│                      │   │                      │
│  offset=0,size=100   │   │  offset=200,size=80  │
│  offset=400,size=120 │   │  ...                 │
│  ...                 │   │                      │
└──────────────────────┘   └──────────────────────┘

IndexFile（按消息 Key 快速定位）
┌─────────────────────────────────────────────────────────────────┐
│  Header  │  Slot Table (500w 槽位)  │  Index Items              │
│          │  keyHash % 500w → itemIdx │  [keyHash, offset, diff]  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 CommitLog 源码

```java
public class CommitLog {
    // 文件大小：默认 1GB
    protected final int mappedFileSize = 1024 * 1024 * 1024;
    // 文件列表（MappedFile 是内存映射文件的封装）
    protected final MappedFileQueue mappedFileQueue;
    // 写锁：putMessage 需要获取
    protected final PutMessageLock putMessageLock;
    // 刷盘服务（同步或异步）
    protected final FlushCommitLogService flushCommitLogService;
    // 文件预留大小：用于在文件末尾新写入最后一条消息时保证文件不过小
    protected static final int END_FILE_MIN_BLANK_LENGTH = 4 + 4;
    // 'MAGIC+minBlankLength' 的最小长度

    // ==================== putMessage 核心方法 ====================
    public PutMessageResult putMessage(final MessageExtBrokerInner msg) {
        // 1. 设置存储时间
        msg.setStoreTimestamp(System.currentTimeMillis());
        msg.setBodyCRC(UtilAll.crc32(msg.getBody()));

        // 2. 获取最后一个 MappedFile
        MappedFile mappedFile = this.mappedFileQueue.getLastMappedFile();

        // 3. 如果文件不存在或已满 → 创建一个新的
        if (mappedFile == null || mappedFile.isFull()) {
            mappedFile = this.mappedFileQueue.getLastMappedFile(0);
        }

        // 4. 将消息编码为字节数组
        byte[] encodeData = this.encode(msg);

        // 5. 写入 MappedFile
        //    使用 putMessageLock（自旋锁或 ReentrantLock）保证线程安全
        this.putMessageLock.lock();
        try {
            // 追加到文件
            AppendMessageResult result = mappedFile.appendMessage(
                encodeData, this.appendMessageCallback
            );

            switch (result.getStatus()) {
                case PUT_OK:
                    break;
                case END_OF_FILE:
                    // 当前文件空间不够 → 创建一个新文件
                    mappedFile = this.mappedFileQueue.getLastMappedFile(0);
                    result = mappedFile.appendMessage(
                        encodeData, this.appendMessageCallback
                    );
                    break;
                // ... 其他状态处理
            }
        } finally {
            this.putMessageLock.unlock();
        }

        // 6. 异步构建 ConsumeQueue 和 IndexFile
        //    通过 putMessageLock 保证了 CommitLog 中消息的顺序
        //    但是 ConsumeQueue 的构建可以并行（不同 Queue）

        // 7. 触发刷盘
        handleDiskFlush(result, msg);

        // 8. 触发 HA（主从同步）
        handleHA(result, putMessageResult, msg);

        return putMessageResult;
    }
}
```

**关键设计：**
- **顺序写**：所有 Topic 的消息混合写入同一个 CommitLog，保证了磁盘顺序写入的高性能
- **1GB 一个文件**：内存映射 MappedFile，避免频繁 `mmap`
- **自旋锁 vs ReentrantLock**：putMessageLock 是自旋锁（短暂持有，适合忙等），避免线程切换开销

### 3.3 MappedFile 内存映射文件

```java
public class MappedFile extends ReferenceResource {
    // 文件名（即文件起始偏移量）
    private String fileName;
    // 文件大小
    private int fileSize;
    // 文件通道
    private FileChannel fileChannel;
    // 内存映射缓冲区（MappedByteBuffer）
    private MappedByteBuffer mappedByteBuffer;
    // 写入位置
    protected final AtomicInteger wrotePosition = new AtomicInteger(0);
    // Commit 位置（刷盘后的位置）
    protected final AtomicInteger committedPosition = new AtomicInteger(0);
    // Flush 位置（实际刷入磁盘的位置）
    protected final AtomicInteger flushedPosition = new AtomicInteger(0);

    /**
     * 创建 MappedFile
     * mmap → FileChannel.map(READ_WRITE, startOffset, fileSize)
     */
    public void init(final String fileName, final int fileSize) {
        this.fileName = fileName;
        this.fileSize = fileSize;
        this.file = new File(fileName);
        // 计算起始偏移量（文件名就是偏移量）
        this.fileFromOffset = Long.parseLong(this.file.getName());

        // 确保父目录存在
        boolean ok = false;
        ensureDirOK(this.file.getParent());

        try {
            this.fileChannel = new RandomAccessFile(this.file, "rw").getChannel();
            // ★ 核心：内存映射，减少一次数据拷贝
            this.mappedByteBuffer = this.fileChannel.map(
                FileChannel.MapMode.READ_WRITE, 0, fileSize
            );
            TOTAL_MAPPED_VIRTUAL_MEMORY.addAndGet(fileSize);
            ok = true;
        } catch (...) {
            // ...
        } finally {
            if (!ok) {
                this.fileChannel.close();
            }
        }
    }

    /**
     * 追加消息到 MappedFile
     */
    public AppendMessageResult appendMessage(final byte[] data) {
        int currentPos = this.wrotePosition.get();

        // 检查文件是否有足够空间
        if (currentPos < this.fileSize) {
            // ★ 直接写入 mappedByteBuffer（操作系统负责刷盘）
            ByteBuffer byteBuffer = this.mappedByteBuffer.slice();
            byteBuffer.position(currentPos);
            byteBuffer.put(data);

            // 更新写入位置
            this.wrotePosition.addAndGet(data.length);

            return new AppendMessageResult(AppendMessageStatus.PUT_OK);
        }
        // 文件空间不足
        return new AppendMessageResult(AppendMessageStatus.END_OF_FILE);
    }
}
```

**mmap 原理：**

```
传统 IO（4 次拷贝 / 4 次上下文切换）：
  磁盘 → 内核缓冲区 → 用户缓冲区 → Socket 缓冲区 → 网卡

mmap（3 次拷贝 / 4 次上下文切换）：
  磁盘 → 内核缓冲区（mmap 映射到用户空间） → Socket 缓冲区 → 网卡

sendfile（2 次拷贝 / 2 次上下文切换）：
  磁盘 → 内核缓冲区 → 网卡（通过 DMA gather 直接从内核缓冲区拷贝到网卡）
```

RocketMQ 使用 mmap 写入 CommitLog 和 ConsumeQueue，Consumer 拉取消息时使用 **sendfile** 零拷贝传输。

### 3.4 刷盘机制

```
┌─────────────────────────────────────────────────────────────┐
│                    刷盘策略对比                               │
│                                                              │
│  异步刷盘（默认）                         同步刷盘            │
│  ┌──────────────────┐                  ┌──────────────────┐  │
│  │ Producer 写消息   │                  │ Producer 写消息   │  │
│  │   │              │                  │   │              │  │
│  │   ▼              │                  │   ▼              │  │
│  │ CommitLog（内存） │                  │ CommitLog（内存） │  │
│  │   │              │                  │   │              │  │
│  │   │ (立即返回)    │                  │   │ fsync 刷盘    │  │
│  │   ▼              │                  │   ▼              │  │
│  │ 返回成功          │                  │ 等待刷盘完成      │  │
│  │                  │                  │   │              │  │
│  │ --- 后台线程 --- │                  │   ▼              │  │
│  │ 异步刷盘线程     │                  │ 返回成功          │  │
│  │ 每 500ms 刷一次  │                  │                  │  │
│  └──────────────────┘                  └──────────────────┘  │
│                                                              │
│  吞吐量高（10w+ TPS）                  可靠性高（断电不丢）    │
│  可能丢失最近 500ms 的消息              吞吐量降低 10 倍       │
└─────────────────────────────────────────────────────────────┘
```

```java
// CommitLog 中的异步刷盘服务
class GroupCommitService extends FlushCommitLogService {
    private volatile List<GroupCommitRequest> requestsWrite =
        new ArrayList<>();
    private volatile List<GroupCommitRequest> requestsRead =
        new ArrayList<>();

    @Override
    public void run() {
        while (!this.isStopped()) {
            try {
                // 每 10ms 或有新请求时触发刷盘
                this.waitForRunning(10);
                this.doCommit();
            } catch (Exception e) {
                // ...
            }
        }

        // 退出前执行最后一次刷盘
        try {
            Thread.sleep(10);
        } catch (InterruptedException e) {
            // ...
        }
        this.doCommit();
    }

    private void doCommit() {
        synchronized (this.requestsWrite) {
            if (!this.requestsWrite.isEmpty()) {
                // 交换读写列表
                List<GroupCommitRequest> tmp = this.requestsWrite;
                this.requestsWrite = this.requestsRead;
                this.requestsRead = tmp;

                for (GroupCommitRequest req : this.requestsRead) {
                    // ★ 检查是否本轮刷盘已覆盖该请求
                    boolean flushOK = CommitLog.this.mappedFileQueue
                        .getFlushedWhere() >= req.getNextOffset();
                    // 如果需要刷盘的位置已经被刷了 → 成功
                    // 否则执行 MappedFileQueue.flush(0)
                    req.wakeupCustomer(flushOK ?
                        CommitLog.this.mappedFileQueue.getFlushedWhere() :
                        CommitLog.this.mappedFileQueue.flush(0)
                    );
                }

                this.requestsRead.clear();
            }
        }
    }
}
```

### 3.5 ConsumeQueue —— 消费队列索引

ConsumeQueue 是 RocketMQ 存储模型的精髓——它解决了 Kafka 的痛点（多 Partition 导致随机写磁盘）。

**ConsumeQueue 条目录项（20 字节）：**

```
┌────────────────┬──────────────┬───────────────┐
│  commitLogOffset │  size (4B)  │  tagsCode     │
│     (8B)         │              │  (8B)         │
├────────────────┼──────────────┼───────────────┤
│  CommitLog 中    │  消息体大小   │  Tag 的 HashCode│
│  消息的物理偏移  │              │  用于消息过滤    │
└────────────────┴──────────────┴───────────────┘
```

```java
// DefaultAppendMessageCallback.doAppend() 中构建 ConsumeQueue

// 1. 生成 ConsumeQueue Entry
Long queueOffset = topicQueueTable.get(topic).get(queueId)
    .getMaxOffset() + 1;  // Queue 内的逻辑偏移量

// 2. 每个 ConsumeQueue 条目 = 20 字节
//    commitLogOffset(8) + size(4) + tagsCode(8)
//    ConsumeQueue 文件由这 20 字节的记录组成

// 3. DispatchRequest 包含了构建 ConsumeQueue 所需的所有信息
DispatchRequest dispatchRequest = new DispatchRequest(
    topic,
    queueId,
    commitLogOffset,     // CommitLog 物理偏移量
    msgSize,             // 消息大小
    tagsCode,            // Tag 的 HashCode
    storeTimestamp,
    queueOffset,         // Queue 内的逻辑偏移量
    keys,
    uniqKey,
    sysFlag
);

// 4. 由 ReputMessageService（异步线程）构建 ConsumeQueue
//    保证了 CommitLog 不因构建索引而降低写入性能

// ==================== ConsumeQueue 核心 ====================
public class ConsumeQueue {
    // 每个条目固定 20 字节
    public static final int CQ_STORE_UNIT_SIZE = 20;
    // 每个文件默认存储 30 万条（约 6MB）
    private final int mappedFileSizeConsumeQueue;

    /**
     * 从 Queue 偏移量（逻辑偏移）计算 ConsumeQueue 中的物理位置
     */
    private long offsetToPhysicalOffset(final long queueOffset) {
        // queueOffset * 20 → ConsumeQueue 文件中的位置
        return queueOffset * CQ_STORE_UNIT_SIZE;
    }

    /**
     * 从逻辑偏移量获取真正的 CommitLog 偏移量
     * Consumer 拉取消息时先查 ConsumeQueue，再根据物理偏移读 CommitLog
     */
    public SelectMappedBufferResult getIndexBuffer(final long startIndex) {
        int mappedFileSize = this.mappedFileSizeConsumeQueue;
        long offset = startIndex * CQ_STORE_UNIT_SIZE;  // 计算 ConsumeQueue 文件偏移
        // ...

        // 读取 ConsumeQueue，获取 CommitLog Offset + Size
        SelectMappedBufferResult result = mappedFile.selectMappedBuffer(
            (int) (offset % mappedFileSize)
        );
        return result;
    }
}
```

**为什么用 ConsumeQueue？**

| 问题 | Kafka 方案 | RocketMQ 方案 |
|------|-----------|---------------|
| 多 Topic 多 Partition 写入 | 每个 Partition 独立目录 → 随机写 | 所有消息混合写入 CommitLog → 顺序写 |
| 读取性能 | Partition 内顺序读 | 通过 ConsumeQueue 快速定位，再批量顺序读 CommitLog |
| 扩容影响 | 增加 Partition 需迁移数据 | 增加 Queue 数只需在 NameServer 更新元数据 |
| 海量 Topic 场景 | 文件句柄爆炸（每 Partition 至少 2 个文件） | 所有 Topic 共享少量 CommitLog 文件 |

### 3.6 IndexFile —— 基于 Key 的消息查询

```java
public class IndexFile {
    // Index Header: 40 字节
    // ┌─────────────────────────────────────────────────────┐
    // │ beginTimestamp(8) │ endTimestamp(8) │ beginOffset(8) │
    // │ endOffset(8)      │ hashSlotCount(4)│ indexCount(4)   │
    // └─────────────────────────────────────────────────────┘

    // Hash Slot Table: hashSlotCount * 4 字节
    // 每个 slot 存储一个 indexCount（该槽位最后一个 IndexItem 的序号）

    // Index Item List: indexCount * 20 字节
    // ┌─────────────────────────────────────────────────────┐
    // │ keyHash(4) │ commitLogOffset(8) │ timeDiff(4)      │
    // │ nextIndex(4)                                        │
    // └─────────────────────────────────────────────────────┘
    // nextIndex: 哈希冲突时指向前一个 IndexItem

    private static final int INDEX_ITEM_SIZE = 20;

    /**
     * 根据消息 Key 查找 CommitLog 偏移量
     */
    public void selectPhyOffset(List<Long> phyOffsets, String key,
                                 int maxNum, long begin, long end) {
        // 1. 计算 Key 的 hash
        int keyHash = indexKeyHashMethod(key);
        // 2. hash % 500w → slot 索引
        int slotPos = keyHash % this.hashSlotNum;
        // 3. 从 slot 找到最新的 IndexItem
        int indexCount = this.indexHeader.getIndexCount();
        int absSlotPos = IndexHeader.INDEX_HEADER_SIZE + slotPos * hashSlotSize;

        int slotValue = this.mappedByteBuffer.getInt(absSlotPos);
        // 4. 遍历链表，匹配 keyHash
        while (slotValue <= indexCount && slotValue > 0) {
            int absIndexPos = IndexHeader.INDEX_HEADER_SIZE
                + this.hashSlotNum * hashSlotSize
                + (slotValue - 1) * INDEX_ITEM_SIZE;

            // 检查 keyHash 和 时间范围
            int itemKeyHash = this.mappedByteBuffer.getInt(absIndexPos);
            long timeDiff = this.mappedByteBuffer.getInt(absIndexPos + 12);
            long time = this.indexHeader.getBeginTimestamp() + timeDiff;

            if (itemKeyHash == keyHash && time >= begin && time <= end) {
                // 命中：获取 CommitLog 偏移量
                long offset = this.mappedByteBuffer.getLong(absIndexPos + 4);
                phyOffsets.add(offset);
            }

            // 获取下一个（哈希冲突链表）
            slotValue = this.mappedByteBuffer.getInt(absIndexPos + 16);
        }
    }
}
```

### 3.7 ReputMessageService —— 异步分发服务

```
CommitLog 写入完成后                             后台异步分发
      │                                               │
      ▼                                               ▼
PutMessageResult                              ReputMessageService
      │                                          (Daemon 线程)
      │                                               │
  ┌───┴───┐                                     ┌────┴────┐
  │ 返回    │                                     │从 CommitLog│
  │ Producer│                                     │读取新消息  │
  └─────────┘                                    └────┬────┘
                                                      │
                                           ┌──────────┼──────────┐
                                           ▼          ▼          ▼
                                     ConsumeQueue  IndexFile   其他
                                     (构建索引)   (构建索引)  (HA同步)
```

```java
public class ReputMessageService extends ServiceThread {

    @Override
    public void run() {
        while (!this.isStopped()) {
            try {
                // 每隔 1ms 检查一次
                Thread.sleep(1);
                this.doReput();
            } catch (Exception e) {
                // ...
            }
        }
    }

    private void doReput() {
        // 从 CommitLogDispatcher 的 reputFromOffset 开始读取
        for (boolean doNext = true; this.isCommitLogAvailable() && doNext; ) {

            // ① 从 CommitLog 读取已写入的消息
            SelectMappedBufferResult result = DefaultMessageStore.this
                .commitLog.getData(reputFromOffset);
            if (result == null) {
                break;
            }

            // ② 解析消息，构建 DispatchRequest
            DispatchRequest dispatchRequest =
                DefaultMessageStore.this.commitLog.checkMessageAndReturnSize(
                    result.getByteBuffer()
                );

            // ③ 分发给各个分发器
            for (CommitLogDispatcher dispatcher : this.dispatcherList) {
                dispatcher.dispatch(dispatchRequest);
            }

            // ④ 更新 reputFromOffset
            // ⑤ 更新 Store 的最大偏移量
        }
    }
}

// CommitLogDispatcherList 包含:
// 1. CommitLogDispatcherBuildConsumeQueue → 构建 ConsumeQueue
// 2. CommitLogDispatcherBuildIndex        → 构建 IndexFile
// 3. HAService.AcceptSocketService        → HA 主从同步
```

---

## 第四部分：消息发送流程

### 4.1 Producer 发送消息全链路

```
Producer.send()
    │
    ▼
DefaultMQProducerImpl.sendDefaultImpl()
    │
    │ ① 验证消息（Topic、Body 不能为空）
    ├── ② 获取 Topic 的路由信息
    │    ├── 本地缓存 (topicPublishInfoTable) 没有 → 从 NameServer 拉取
    │    └── 拉取成功后缓存到本地
    │
    │ ③ 选择 Queue（selectOneMessageQueue）
    │    ├── 开启故障延迟 → 跳过故障 Broker
    │    └── 分布式算法选择 Queue
    │
    │ ④ 发送消息（sendKernelImpl）
    │    ├── 分配全局唯一 MessageId
    │    ├── 压缩消息体（超过 4KB 自动 zlib 压缩）
    │    ├── 通过 Netty 发送到 Broker
    │    └── 等待响应
    │
    │ ⑤ 发送失败处理
    │    ├── 重试（retryTimesWhenSendFailed）
    │    ├── 更新故障信息
    │    └── 选择新 Queue 重试
    │
    └── 返回 SendResult
```

### 4.2 Queue 选择算法

```java
public MessageQueue selectOneMessageQueue(final TopicPublishInfo tpInfo,
                                           final String lastBrokerName) {
    // ========== 1. 开启故障延迟 ==========
    if (this.sendLatencyFaultEnable) {
        // 随机递增取模
        int index = tpInfo.getSendWhichQueue().getAndIncrement();
        for (int i = 0; i < tpInfo.getMessageQueueList().size(); i++) {
            int pos = Math.abs(index++) % tpInfo.getMessageQueueList().size();
            MessageQueue mq = tpInfo.getMessageQueueList().get(pos);
            // ★ 检查 Broker 是否可用（不故障的才发）
            if (latencyFaultTolerance.isAvailable(mq.getBrokerName())) {
                return mq;
            }
        }
        // 所有 Broker 都不可用 → 随机选一个
        return tpInfo.selectOneMessageQueue();
    }

    // ========== 2. 不开启故障延迟（默认）==========
    // 轮询选择 Queue（Round Robin）
    int index = tpInfo.getSendWhichQueue().getAndIncrement();
    int pos = Math.abs(index) % tpInfo.getMessageQueueList().size();
    return tpInfo.getMessageQueueList().get(pos);
}
```

### 4.3 故障延迟机制

```java
public class MQFaultStrategy {
    // 延迟时间表（毫秒）
    private long[] latencyMax = {
        50L, 100L, 550L, 1000L, 2000L, 3000L, 15000L
    };
    // 对应不可用时长
    private long[] notAvailableDuration = {
        0L, 0L, 30000L, 60000L, 120000L, 180000L, 600000L
    };

    /**
     * 根据最新延迟更新故障列表
     * 发送成功或失败后，传递当前 Broker 的延迟时间
     */
    public void updateFaultItem(String brokerName, long currentLatency,
                                 boolean isolation) {
        if (this.sendLatencyFaultEnable) {
            // 根据延迟时间查表，决定不可用时长
            long duration = computeNotAvailableDuration(
                isolation ? 30000 : currentLatency
            );
            this.latencyFaultTolerance.updateFaultItem(
                brokerName, currentLatency, duration
            );
        }
    }

    private long computeNotAvailableDuration(long currentLatency) {
        for (int i = latencyMax.length - 1; i >= 0; i--) {
            if (currentLatency >= latencyMax[i]) {
                return this.notAvailableDuration[i];
            }
        }
        return 0;
    }
}
```

**故障延迟效果示例：**

| 延迟范围 | 延迟时长 | 不可用惩罚 |
|---------|---------|-----------|
| < 50ms | 正常 | 0（不惩罚） |
| 50~100ms | 轻微 | 0 |
| 100~550ms | 中等 | 30 秒不可用 |
| 550~1000ms | 严重 | 1 分钟不可用 |
| 1000~2000ms | 严重 | 2 分钟不可用 |
| 2000~3000ms | 非常严重 | 3 分钟不可用 |
| > 3000ms | 极严重 | 10 分钟不可用 |

### 4.4 Broker 端接收消息

```java
// SendMessageProcessor.processRequest()
// → asyncPutMessage()

public CompletableFuture<PutMessageResult> asyncPutMessage(
    final MessageExtBrokerInner msg
) {
    // 1. 设置存储时间
    msg.setStoreTimestamp(System.currentTimeMillis());
    // 2. 设置 CRC32
    msg.setBodyCRC(UtilAll.crc32(msg.getBody()));

    // 3. 检查是否可写入
    //    - 是否是 Slave（Slave 不允许写入）
    //    - 是否磁盘满了
    //    - 是否有写入权限

    // 4. 写入 CommitLog
    CompletableFuture<PutMessageResult> putResultFuture =
        this.commitLog.asyncPutMessage(msg);

    // 5. 返回结果
    return putResultFuture;
}
```

---

## 第五部分：消息消费模型

### 5.1 Pull vs Push 消费模型

```
RocketMQ 的消费模型本质上是 **Long Polling Push**：
- Consumer 发起 Pull 请求
- Broker 如果没有新消息 → 不立即返回，hold 住请求
- 等待新消息到达或有超时 → 返回

这样既保持了 Pull 的灵活性（消费端控制速率），
又实现了 Push 的低延迟（消息到达即通知）。
```

**PullRequest 结构：**

```java
public class PullRequest {
    private String consumerGroup;    // 消费组
    private MessageQueue messageQueue; // 消息队列
    private long nextOffset;         // 下次拉取的位置
    private ProcessQueue processQueue; // 处理队列
    private boolean lockedFirst;     // 是否已锁定
}
```

### 5.2 长轮询 Long Polling 机制

```java
// PullMessageProcessor.processRequest()
public RemotingCommand processRequest(ChannelHandlerContext ctx,
                                       RemotingCommand request) {
    // ========== 步骤1: 获取消费偏移量 ==========
    long offset = requestHeader.getQueueOffset();
    // ========== 步骤2: 从 ConsumeQueue 查找消息 ==========
    final GetMessageResult getMessageResult =
        this.brokerController.getMessageStore().getMessage(
            consumerGroup, topic, queueId, offset, maxMsgNums, messageFilter
        );

    // ========== 步骤3: 如果有消息 → 直接返回 ==========
    if (getMessageResult.getStatus() == GetMessageStatus.FOUND) {
        response.setCode(ResponseCode.SUCCESS);
        response.setBody(getMessageResult.getMessageBuffer());
        return response;
    }

    // ========== 步骤4: 没有消息 → 挂起请求（Long Polling） ==========
    switch (getMessageResult.getStatus()) {
        case NO_MATCHED_MESSAGE:
            // 没有匹配的消息 → 直接返回空
            response.setCode(ResponseCode.PULL_NOT_FOUND);
            break;

        case NO_MESSAGE_IN_QUEUE:
        case OFFSET_OVERFLOW_ONE:
        case OFFSET_TOO_SMALL:
            // ★ 消息还没到达（offset 后的消息还没写入）
            // → 挂起请求，等待新消息
            final PollingHeader pollingHeader = new PollingHeader(
                requestHeader.getConsumerGroup(),
                topic, queueId, offset, maxMsgNums
            );
            // 保存到长轮询表
            this.brokerController.getPullRequestHoldService()
                .suspendPullRequest(topic, queueId, pollingHeader);

            // 不立即返回（异步等待）
            return null;
    }

    return response;
}
```

```java
// PullRequestHoldService 长轮询服务
public class PullRequestHoldService extends ServiceThread {

    // 长轮询表: Topic → QueueId → 挂起的请求
    private ConcurrentMap<String, ConcurrentMap<Integer, ManyPullRequest>>
        pullRequestTable = new ConcurrentHashMap<>();

    /**
     * 挂起 Pull 请求
     */
    public void suspendPullRequest(String topic, int queueId,
                                    final PullRequest pullRequest) {
        // 1. 放入 pullRequestTable
        ManyPullRequest mpr = this.pullRequestTable
            .computeIfAbsent(topic, k -> new ConcurrentHashMap<>())
            .computeIfAbsent(queueId, k -> new ManyPullRequest());

        mpr.addPullRequest(pullRequest);

        // 2. 设置定时超时（默认 15s 后自动返回）
        //    如果不设置，请求会一直挂起，Consumer 端也会超时
    }

    /**
     * 检查是否有新消息到达 → 唤醒挂起的请求
     * 由 NotifyMessageArrivingListener 触发
     */
    public void checkHoldRequest() {
        // 遍历 pullRequestTable
        for (String topic : this.pullRequestTable.keySet()) {
            String[] split = topic.split(TOPIC_GROUP_SEPARATOR);
            String realTopic = split[0];
            String consumerGroup = split[1];

            ManyPullRequest mpr = this.pullRequestTable.get(topic);
            for (Integer queueId : mpr.keySet()) {
                List<PullRequest> requestList = mpr.get(queueId);

                // 拉取消息
                GetMessageResult getMessageResult =
                    this.messageStore.getMessage(
                        consumerGroup, realTopic, queueId,
                        requestList.get(0).getNextOffset(),
                        maxMsgNums, null
                    );

                // 有新消息 → 唤醒所有挂起的请求
                if (getMessageResult.getStatus() == GetMessageStatus.FOUND) {
                    for (PullRequest request : requestList) {
                        // ★ 通知 Consumer 有新消息
                        executeRequestWhenWakeup(request.getClientChannel(),
                                                  request);
                    }
                    mpr.remove(queueId);
                }
            }
        }
    }
}
```

**长轮询时序图：**

```
Consumer                Broker (PullRequestHoldService)          Producer
   │                              │                                   │
   │ ① PULL_REQUEST (offset=100) │                                   │
   │─────────────────────────────►│                                   │
   │                              │                                   │
   │                              │ ② ConsumeQueue 没有新消息          │
   │                              │    → suspendPullRequest            │
   │                              │    → 挂起 15s                      │
   │                              │                                   │
   │                              │                     ③ 新消息到达  │
   │                              │◄──────────────────────────────────│
   │                              │                                   │
   │ ④ PULL_RESPONSE (新消息)     │                                   │
   │◄─────────────────────────────│                                   │
   │                              │                                   │
   │ （或 15s 超时后返回空）      │                                   │
   │◄─────────────────────────────│                                   │
```

### 5.3 Rebalance —— 队列重分配

```java
// RebalanceImpl.doRebalance()
public void doRebalance() {
    // 1. 获取当前 Topic 的所有 MessageQueue
    Set<MessageQueue> mqSet = this.topicSubscribeInfoTable.get(topic);

    // 2. 获取消费组内所有 Consumer (Client ID 列表)
    List<String> cidAll = this.mQClientFactory.findConsumerIdList(
        topic, consumerGroup
    );

    // 3. 排序（保证所有 Consumer 看到相同的顺序）
    Collections.sort(mqAll);  // MessageQueue 排序
    Collections.sort(cidAll); // Consumer 排序

    // 4. 分配算法（默认: 平均分配 AllocateMessageQueueAveragely）
    AllocateMessageQueueStrategy strategy = this.allocateMessageQueueStrategy;
    List<MessageQueue> allocateResult = strategy.allocate(
        this.consumerGroup,
        this.mQClientFactory.getClientId(),
        mqAll,  // 所有 Queue
        cidAll  // 所有 Consumer
    );

    // 5. 对比新旧分配 → diff 更新
    //    - 新增 Queue → 创建新 PullRequest
    //    - 删除 Queue → 关闭已有 PullRequest
    this.updateProcessQueueTableInRebalance(topic, allocateResult, isOrder);
}
```

**平均分配算法：**

```java
public class AllocateMessageQueueAveragely
    implements AllocateMessageQueueStrategy {

    @Override
    public List<MessageQueue> allocate(String consumerGroup,
                                        String currentCID,
                                        List<MessageQueue> mqAll,
                                        List<String> cidAll) {
        List<MessageQueue> result = new ArrayList<>();

        int index = cidAll.indexOf(currentCID);
        int total = cidAll.size();
        int queueSize = mqAll.size();

        // 计算当前 Consumer 负责的 Queue 数量
        int mod = queueSize % total;       // 余数
        int averageSize = queueSize / total; // 每个 Consumer 的基础数量

        // 前 mod 个 Consumer 多分配一个 Queue
        int startIndex = index < mod ?
            index * (averageSize + 1) :
            mod * (averageSize + 1) + (index - mod) * averageSize;
        int range = index < mod ? averageSize + 1 : averageSize;

        for (int i = 0; i < range; i++) {
            result.add(mqAll.get((startIndex + i) % queueSize));
        }
        return result;
    }
}
```

**Rebalance 触发时机：**
1. Consumer 启动或关闭
2. Broker 上线或下线（触发 Consumer 30s 周期检查）
3. Topic 的 Queue 数量变化
4. Consumer 心跳超时被剔除
5. 定时触发（默认 20s）

---

## 第六部分：高可用 —— Master-Slave + Dledger

### 6.1 同步双写 vs 异步复制

```
┌─────────────────────────────────────────────────────────────┐
│                Master-Slave 数据同步机制                       │
│                                                              │
│  ┌──────────────────┐          ┌──────────────────┐         │
│  │    Master         │          │    Slave          │         │
│  │                   │          │                   │         │
│  │ CommitLog         │          │ CommitLog         │         │
│  │ commitedPos=1000  │          │ commitedPos=800   │         │
│  │                   │          │                   │         │
│  │ HAService ────────│──TCP────►│ HAService         │         │
│  │                   │          │                   │         │
│  └──────────────────┘          └──────────────────┘         │
│                                                              │
│  同步复制 (SYNC_MASTER)          异步复制 (ASYNC_MASTER)       │
│  ┌──────────────────┐          ┌──────────────────┐         │
│  │ Producer 写 Master│          │ Producer 写 Master│         │
│  │   │              │          │   │              │          │
│  │   ├──► 写 Slave  │          │   ├──► 返回成功   │          │
│  │   │    等待 ACK  │          │   │   (不等待)    │          │
│  │   ▼              │          │   ▼              │          │
│  │ Slave 同步完成   │          │ 异步写 Slave     │          │
│  │   │              │          │                  │          │
│  │   ▼              │          │ 牺牲一致性        │          │
│  │ 返回成功         │          │ 提升吞吐量        │          │
│  └──────────────────┘          └──────────────────┘          │
│                                                              │
│  Broker Role 配置:                                            │
│  - ASYNC_MASTER  → 默认，异步复制                             │
│  - SYNC_MASTER   → 同步双写                                   │
│  - SLAVE          → 从节点（只读）                            │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 HA 同步源码

```java
// HAService —— Broker 端高可用服务
public class HAService {
    // 主节点: 接受 Slave 连接，推送数据
    // 从节点: 连接 Master，拉取数据

    // Master 端
    class AcceptSocketService extends ServiceThread {
        @Override
        public void run() {
            // 监听 Slave 的连接
            SocketChannel sc = serverSocketChannel.accept();
            // 创建 HAConnection 处理该 Slave 的数据同步
            HAConnection conn = new HAConnection(HAService.this, sc);
            conn.start();
        }
    }

    // Master → Slave 数据推送
    class ReadSocketService extends ServiceThread {
        @Override
        public void run() {
            while (true) {
                // 等待 Slave 报告已同步到的偏移量
                int read = this.socketChannel.read(this.byteBufferRead);
                if (read > 0) {
                    long slaveAckOffset = this.byteBufferRead.getLong();
                    // 更新 Master 端记录的 Slave 同步进度
                    this.currentTransferedCommitLogOffset = slaveAckOffset;
                }

                // 判断是否需要推送数据
                if (slaveRequestOffset == -1) {
                    slaveRequestOffset = slaveAckOffset;
                }

                if (slaveAckOffset >= slaveRequestOffset) {
                    // Slave 已追上 → 继续推送新数据
                    long maxOffset = HAService.this.defaultMessageStore
                        .getCommitLog().getMaxOffset();
                    if (slaveAckOffset < maxOffset) {
                        // 还有未同步的数据 → 继续 push
                    }
                }
            }
        }
    }

    // Master 端写（推送数据给 Slave）
    class WriteSocketService extends ServiceThread {
        @Override
        public void run() {
            while (!this.isStopped()) {
                // 1. 获取 Slave 的同步进度
                long nextOffset = this.slaveRequestOffset;
                // 2. 从 CommitLog 读取数据
                SelectMappedBufferResult selectResult =
                    commitLog.getData(nextOffset);
                // 3. 发送给 Slave
                if (selectResult != null) {
                    // 通过 Socket 推送给 Slave
                    this.socketChannel.write(...);
                    // 更新 nextTransferFromWhere
                } else {
                    // 没有新数据 → 等待
                    waitForRunning(1000);
                }
            }
        }
    }
}
```

### 6.3 Dledger —— Raft 协议实现

RocketMQ 4.5+ 引入了基于 Raft 的 Dledger 模式，替代传统的 Master-Slave。

```
┌─────────────────────────────────────────────────────────────┐
│                  Dledger (Raft) 架构                          │
│                                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐               │
│  │ Leader   │    │ Follower │    │ Follower │               │
│  │ (Broker) │    │ (Broker) │    │ (Broker) │               │
│  │          │    │          │    │          │               │
│  │ 接收写入  │    │ 只读     │    │ 只读     │               │
│  └────┬─────┘    └────▲─────┘    └────▲─────┘               │
│       │               │               │                     │
│       └───────────────┴───────────────┘                     │
│           ② Append Entries (Raft log 复制)                    │
│                                                              │
│  核心流程:                                                    │
│  ① Producer 发送消息到 Leader                                │
│  ② Leader 将消息作为 Raft Log Entry 复制到所有 Follower      │
│  ③ 过半 Follower 成功写入 → Leader Commit                    │
│  ④ 返回成功给 Producer                                       │
│                                                              │
│  Dledger CommitLog 格式:                                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ magic │ size │ DledgerEntry │ body                    │   │
│  │ (4B)  │ (4B) │ (总长度-8)   │ (消息体)               │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  DledgerEntry:                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ group(8B) │ term(8B) │ index(8B) │ body              │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**Dledger vs 传统 Master-Slave：**

| 维度 | 传统 Master-Slave | Dledger (Raft) |
|------|-------------------|----------------|
| Leader 选举 | 手动或脚本 | Raft 自动选举 |
| 数据一致性 | 异步复制可能丢数据 | 过半确认，强一致 |
| 故障恢复 | 人工介入 | 自动 Failover |
| 写入性能 | 异步: ~100w TPS | ~50w TPS（因为过半确认开销） |
| 适用场景 | 高吞吐、允许少量丢失 | 金融级、零丢失 |

---

## 第七部分：事务消息 —— 半消息 + 回查

### 7.1 事务消息流程

```
Producer                RocketMQ Broker                 Local Transaction
   │                         │                                 │
   │ ① send(msg)             │                                 │
   │    (半消息，Consumer不可见)│                                 │
   │─────────────────────────►│                                 │
   │                         │                                 │
   │ ② 写入 CommitLog        │                                 │
   │    TRANSACTION_NOT_FIRST│                                 │
   │    TRANSACTION_PREPARED │                                 │
   │◄────────────────────────│                                 │
   │                         │                                 │
   │          ③ executeLocalTransaction()                      │
   │─────────────────────────────────────────────────────────►│
   │                         │                                 │
   │                         │                  ④ 本地事务结果  │
   │                         │◄────────────────────────────────│
   │                         │       COMMIT / ROLLBACK           │
   │                         │                                 │
   │ ⑤ COMMIT/ROLLBACK       │                                 │
   │─────────────────────────►│                                 │
   │                         │                                 │
   │                         │ ⑥ COMMIT: 消息对 Consumer 可见   │
   │                         │    ROLLBACK: 消息被丢弃          │
   │                         │                                 │
   │             ⑦ 如果 ⑤ 未到达（超时/网络异常）               │
   │                Broker 回查 Producer                       │
   │◄────────────────────────│                                 │
   │                         │                                 │
   │ ⑧ checkLocalTransaction│                                 │
   │──────────────────────────────────────────────────────────►│
   │                         │                                 │
```

### 7.2 事务消息源码

```java
// TransactionMQProducer.sendMessageInTransaction()
public TransactionSendResult sendMessageInTransaction(
    final Message msg,
    final Object arg
) {
    // ① 将消息标记为事务消息（设置 TRAN_MSG 属性）
    msg.putUserProperty(MessageConst.PROPERTY_TRANSACTION_PREPARED, "true");
    msg.putUserProperty(MessageConst.PROPERTY_PRODUCER_GROUP,
                        this.getProducerGroup());

    // ② 发送半消息（Broker 端标记为 PREPARED，Consumer 不可见）
    SendResult sendResult = this.send(msg);
    // 半消息写入 CommitLog，但不会被构建到 ConsumeQueue

    // ③ 执行本地事务
    LocalTransactionState localTransactionState =
        this.getTransactionListener().executeLocalTransaction(
            msg, arg
        );

    // ④ 根据本地事务结果，通知 Broker COMMIT 或 ROLLBACK
    this.endTransaction(sendResult, localTransactionState, null);

    return transactionSendResult;
}
```

```java
// Broker 端：EndTransactionProcessor
// 处理 COMMIT 和 ROLLBACK 请求

// COMMIT 操作:
// 1. 将半消息的状态从 PREPARED 改为 COMMITTED
// 2. 将消息放入 ConsumeQueue（Consumer 可见）
// 3. 更新消息属性

// ROLLBACK 操作:
// 1. 标记消息为 ROLLBACKED
// 2. 不放入 ConsumeQueue
// 3. 后续会被清理线程删除
```

### 7.3 回查机制

```java
// TransactionalMessageCheckService
// 定期检查长时间未 COMMIT/ROLLBACK 的半消息

public class TransactionalMessageCheckService extends ServiceThread {
    @Override
    public void run() {
        long checkInterval = brokerController.getBrokerConfig()
            .getTransactionCheckInterval();  // 默认 60s

        while (!this.isStopped()) {
            waitForRunning(checkInterval);

            // 1. 遍历所有半消息
            //    从 TRANS_CHECK_MAXTIME_OFFSET 中获取需要检查的消息
            long timeout = brokerController.getBrokerConfig()
                .getTransactionTimeOut();  // 默认 6000ms

            // 2. 找到超过 timeout 仍未 COMMIT/ROLLBACK 的半消息
            // 3. 向 Producer 发送回查请求
            checkProducerTransactionState(producerGroup, msgExt);
        }
    }
}

// Producer 端
public class TransactionListener {
    /**
     * Broker 回查时调用
     */
    LocalTransactionState checkLocalTransaction(MessageExt msg);
}
```

**事务消息为什么不丢消息？**
- 半消息持久化在 CommitLog 中，Broker 宕机重启后可以恢复
- 回查机制确保最终一致性（COMMIT 或 ROLLBACK 一定会执行）
- 如果回查超过 15 次仍未确定 → Broker 主动 ROLLBACK（避免半消息堆积）

---

## 第八部分：延迟消息 —— 18 级时间轮

### 8.1 延迟级别

```java
// MessageStoreConfig
private String messageDelayLevel = "1s 5s 10s 30s 1m 2m 3m 4m 5m 6m 7m 8m 9m 10m 20m 30m 1h 2h";
//                               0  1   2   3   4  5  6  7  8  9  10 11 12 13  14  15  16 17
//                               ↑ level=3 → 延迟 30s

// 使用方法:
message.setDelayTimeLevel(3);  // 延迟 30s 投递
```

### 8.2 延迟消息实现原理

```
正常消息:
  Producer → CommitLog → ConsumeQueue → Consumer

延迟消息:
  Producer → CommitLog
    │
    ├── 写入 ConsumeQueue
    │   (以 SCHEDULE_TOPIC_XXXX 命名的特殊 Topic)
    │
    └── 定时任务 ScheduleMessageService 扫描延迟队列
        │
        ├── 每 1s 检查一次（对应 level=0, 1, 2）
        ├── 如果 TTL 过了 → 投递到原始 Topic 的 ConsumeQueue
        └── 否则 → 等待下一个扫描周期
```

```java
public class ScheduleMessageService extends ConfigManager {
    // 延迟级别 → ConsumeQueue 偏移量
    private final ConcurrentMap<Integer, Long> offsetTable =
        new ConcurrentHashMap<>(32);

    @Override
    public void run() {
        // 每个延迟级别一个定时任务
        for (Map.Entry<Integer, Long> entry : this.delayLevelTable.entrySet()) {
            Integer level = entry.getKey();
            Long timeDelay = entry.getValue();

            // 定时任务：每隔 timeDelay 检查
            this.deliverExecutorService.schedule(new DeliverDelayedMessageTimerTask(
                level, offset
            ), FIRST_DELAY_TIME, TimeUnit.MILLISECONDS);
        }
    }

    // 投递延迟消息
    class DeliverDelayedMessageTimerTask implements Runnable {
        @Override
        public void run() {
            try {
                // 1. 从 SCHEDULE_TOPIC_XXXX 的 ConsumeQueue 中读取消息
                ConsumeQueue cq = scheduleMessageStore.findConsumeQueue(
                    TopicValidator.RMQ_SYS_SCHEDULE_TOPIC, level);

                // 2. 获取消息的 TTL（存储时间 + 延迟时长）
                long now = System.currentTimeMillis();
                // 3. 如果 TTL 已过 → 投递到原始 Topic
                if (msg.getStoreTimestamp() + delayTime < now) {
                    // ★ 将消息写入原始 Topic 的 CommitLog
                    //    此时该消息才会出现在 Consumer 可见的 ConsumeQueue 中
                    MessageExtBrokerInner msgInner = messageTimeup(msg);
                    PutMessageResult result =
                        messageStore.putMessage(msgInner);
                } else {
                    // 还没到时间 → 等待下一个周期
                    // 例如 level=14 (10 分钟延迟) → 每 10 分钟扫描一次
                }
            } finally {
                // 继续下一次调度
                scheduleExecutorService.schedule(this, delayTime);
            }
        }
    }
}
```

**延迟消息的局限：**
- 只支持预定义的 18 个级别，不支持任意时间
- level=1 (5s) 精度是 1s，level>2 精度是级别本身的时间
- 延迟消息存储在 `SCHEDULE_TOPIC_XXXX` 下，占用额外存储

---

## 第九部分：消息过滤 —— Tag + SQL92

### 9.1 Tag 过滤

```java
// Producer 设置 Tag
message.setTags("TagA");

// Consumer 订阅 Tag
consumer.subscribe("TopicA", "TagA || TagB");
// Tag 过滤在 Broker 端完成，减少网络传输

// ====== Broker 端 Tag 过滤 ======
// ExpressionMessageFilter.isMatchedByConsumeQueue()
// tagsCode 是 Tag 的 HashCode（存储在 ConsumeQueue 条目中）

if (subscriptionData.getSubString().equals(SubscriptionData.SUB_ALL)) {
    return true;  // 订阅 "*" → 匹配所有
}

// Tag1 || Tag2 解析
for (String tag : tagsSet) {
    if (tag.equals(MessageConst.MESSAGE_TAG_NOT_SET)) {
        return true;
    }
    Long tagCode = subscriptionData.getCodeSet().get(tag);
    if (tagCode != null && tagCode.longValue() == tagsCode) {
        return true;
    }
}
```

### 9.2 SQL92 过滤（慎用）

```java
// Producer 设置属性
message.putUserProperty("a", "10");
message.putUserProperty("b", "20");

// Consumer 设置 SQL92 过滤
consumer.subscribe("TopicA", MessageSelector.bySql("a > 5 AND b <= 20"));

// Broker 端过滤: 需要反序列化消息的 properties
// SELECT 开销较大，只适合轻量级过滤
```

---

## 第十部分：顺序消息

### 10.1 分区顺序消息

```
RocketMQ 通过 MessageQueueSelector 实现分区有序

Producer:
  ┌──────────────────────────────────────────────────┐
  │ 同一条业务 Key（如 orderId）→ 同一个 MessageQueue │
  │                                                  │
  │ send(msg, new MessageQueueSelector() {            │
  │     select(mqs, msg, orderId) {                   │
  │         int index = orderId.hashCode() % mqs.size();│
  │         return mqs.get(index);                    │
  │     }                                             │
  │ })                                                │
  └──────────────────────────────────────────────────┘

Consumer:
  ┌──────────────────────────────────────────────┐
  │ 同一个 MessageQueue 由同一个 Consumer 消费   │
  │ 同一线程内串行消费，保证顺序                  │
  │                                              │
  │ registerMessageListener(                     │
  │     MessageListenerOrderly → 顺序消费监听器   │
  │ )                                            │
  └──────────────────────────────────────────────┘
```

### 10.2 顺序消费源码

```java
// ConsumeMessageOrderlyService
public class ConsumeMessageOrderlyService implements ConsumeMessageService {

    @Override
    public void submitConsumeRequest(
        final List<MessageExt> msgs,
        final ProcessQueue processQueue,
        final MessageQueue messageQueue,
        final boolean dispathToConsume
    ) {
        // 提交消费请求到单线程线程池
        // ★ 同一个 MessageQueue 的所有请求由同一个线程串行处理
        this.consumeExecutor.submit(new ConsumeRequest(
            msgs, processQueue, messageQueue
        ));
    }

    // 顺序消费的 ProcessQueue 维护了一把锁
    // 保证同一 Queue 同一时间只有一条消息在被消费
    // 前一条消息消费成功后才拉取下一条
}
```

---

## 第十一部分：消息重试与死信队列

### 11.1 重试机制

```
正常消费流程:
  Consumer → ack → Broker 标记消费成功 → 更新 offset

消费失败:
  Consumer → RECONSUME_LATER (status code)
    │
    ▼
  消息被写入 RETRY 主题:
    %RETRY%{consumerGroup}
    │
    │ 延迟级别递增:
    │   第1次失败 → level 0 (1s 后重试)
    │   第2次失败 → level 1 (5s 后重试)
    │   第3次失败 → level 2 (10s 后重试)
    │   ...
    │   第16次失败 → level 17 (2h 后重试)
    │
    ▼
  超过最大重试次数 (默认 16 次)
    │
    ▼
  进入死信队列: %DLQ%{consumerGroup}
```

```java
// Consumer 端
consumer.setMaxReconsumeTimes(16);  // 最大重试次数

// Broker 端：SendMessageProcessor.asyncConsumerSendMsgBack()
// 处理 RECONSUME_LATER
// 1. 获取消息的重试次数
int reconsumeTimes = msgExt.getReconsumeTimes() + 1;

// 2. 判断是否超过最大重试次数
if (reconsumeTimes > maxReconsumeTimes) {
    // 进入死信队列
    newTopic = MixAll.getDLQTopic(consumerGroup);
    // 直接写入死信队列，不再重试
} else {
    // 写入 RETRY 主题
    newTopic = MixAll.getRetryTopic(consumerGroup);
    // 设置延迟级别（递增）
    int delayLevel = Math.min(reconsumeTimes, maxDelayLevel);
    msgInner.setDelayTimeLevel(delayLevel);
}

// 3. 写入 CommitLog
this.messageStore.putMessage(msgInner);
```

### 11.2 死信队列

```
死信队列是全托管队列——RocketMQ 自动创建的：

DLQ Topic 命名规则: %DLQ%{ConsumerGroup}

特点:
- 消息进入死信队列后不再被原 Consumer 消费
- 需要单独启动一个 Consumer 消费死信消息
- 可用于人工介入处理（告警、补偿、审计）

死信消息的特征:
- reconsumeTimes = 16（或配置的最大值）
- 原始消息的 properties 完整保留
- UNIQ_KEY 保留原始 MessageId

监控建议:
- 死信队列的消息积压量（DLQ 堆积 = 消费失败量）
- 设置告警阈值（如 DLQ 堆积 > 100）
```

---

## 第十二部分：RocketMQ vs Kafka 全面对比

### 12.1 架构对比

| 维度 | RocketMQ | Kafka |
|------|----------|-------|
| **注册中心** | NameServer（自研，无状态） | Zookeeper（外部依赖） |
| **存储模型** | CommitLog（所有Topic混合）+ ConsumeQueue | Partition（每个Topic独立目录） |
| **消息存储** | mmap + 顺序写 | mmap + 顺序写 |
| **消费模型** | Pull + Long Polling | Pull |
| **消息有序** | 分区内有序 + 严格顺序消费线程模型 | 单分区内有序 |
| **事务消息** | 原生支持（半消息+回查） | 仅幂等 Producer |
| **延迟消息** | 18级时间轮 | 无原生支持 |
| **消息过滤** | Tag(SQL92) Broker端过滤 | 客户端过滤 |
| **消息重试** | 自动重试 + 死信队列 | 手动重试 |
| **消息回溯** | 按时间戳回退 | 按 offset 重置 |

### 12.2 性能对比

| 维度 | RocketMQ | Kafka |
|------|----------|-------|
| **单Broker吞吐** | ~10w TPS | ~100w TPS（PageCache加速） |
| **延迟** | 1-10ms（长轮询） | 5-15ms（Pull） |
| **海量Topic** | 高（单文件顺序写） | 低（多文件分散写，文件句柄爆炸） |
| **堆积能力** | 强（CommitLog只写1个文件） | 强（Partition隔离） |
| **消息大小** | 默认4MB | 默认1MB |

### 12.3 为什么 RocketMQ 比 Kafka 更适合海量 Topic？

```
Kafka:
  TopicA/Partition0 → 目录: topicA-0/
                        ├── 0000000000.log  ← 一个 FD
                        ├── 0000000000.index ← 一个 FD
                        └── 0000000000.timeindex ← 一个 FD

  1000 个 Topic，每个 4 个 Partition → 12000 个文件句柄
  写入时: 磁盘头 1000 次来回寻道（在 HDD 时代极慢）
           SSD 时代好很多，但仍然是随机写

RocketMQ:
  所有 Topic 都写入同一个 CommitLog 文件
  1000 个 Topic → 1 个 CommitLog 文件 → 1 次顺序写

  所以 RocketMQ 天然适合海量 Topic 场景
```

### 12.4 选型建议

| 场景 | 推荐 | 理由 |
|------|------|------|
| 大数据日志采集 | Kafka | 高吞吐、PageCache、生态成熟 |
| 在线业务 | RocketMQ | 低延迟 Long Polling、事务消息 |
| 海量 Topic (1000+) | RocketMQ | 单文件顺序写，不受 Topic 数影响 |
| 严格顺序消息 | RocketMQ | 分区顺序 + 顺序消费线程模型 |
| 金融支付 | RocketMQ | 事务消息、同步刷盘、Dledger |
| 流计算 | Kafka | Kafka Streams、KSQL 生态 |
| Spring Cloud 生态 | RocketMQ | Spring Cloud Stream 集成 |

---

## 第十三部分：面试高频题 20 问

### Q1: RocketMQ 为什么用 NameServer 而不是 Zookeeper？

> NameServer 之间不通信、不做持久化、CAP 选 AP。ZK 是 CP，在网络分区时可能降低可用性。NameServer 挂了不影响已有连接，ZK 挂了会导致 Kafka 不可用。

### Q2: CommitLog + ConsumeQueue 的设计解决了什么问题？

> 解决了 Kafka 在海量 Topic 场景下随机写磁盘的问题。RocketMQ 所有 Topic 的消息混合写入一个 CommitLog（顺序写），每个 Topic/Queue 独立构建 ConsumeQueue 索引（轻量级，快速定位）。

### Q3: 如何保证消息不丢失？

> 三重保障：
> 1. **同步刷盘**（flushDiskType=SYNC_FLUSH，每条消息 flush 后才返回）
> 2. **同步复制**（brokerRole=SYNC_MASTER，等待 Slave 同步）
> 3. **事务消息**（半消息+Commit，保证发送端不丢）
> 4. **消费端手动 ACK**（重试+死信队列）

### Q4: 如何处理消息重复消费？

> RocketMQ 无法保证 Exactly Once，需要消费端做幂等：
> - 数据库唯一键约束
> - Redis SETNX
> - MessageId/业务 Key 去重表

### Q5: Broker 如何实现高可用？

> Master-Slave 模式：
> - Master 挂了 → 消费者可以自动切到 Slave 读取（只读不写）
> - 4.5+ 支持 Dledger（Raft）自动切换
> - 生产者启用 `sendLatencyFaultEnable` 自动避开故障 Broker

### Q6: 消息消费的 Push 和 Pull 区别？RocketMQ 用哪种？

> RocketMQ 本质是 **Long Polling Push**：
> - Consumer 发起 Pull 请求
> - Broker 如果没有消息 → hold 住 15s，等新消息到达或超时后返回
> - 结合了 Pull（消费端控制速率）和 Push（低延迟）的优点

### Q7: 为什么顺序消息不能部署多个 Consumer 实例？

> 因为 Rebalance 可能导致同一个 Queue 被分配给不同的 Consumer，破坏顺序性。部署多个 Consumer 实例时，要确保 Queue 数 ≥ Consumer 实例数，否则多余的 Consumer 会被分配 Queue，产生并发消费。

### Q8: 消息堆积如何解决？

> 1. **增加消费者**：增加 Consumer 实例数（不能超过 Queue 数）
> 2. **增加 Queue 数**：动态增加 Topic 的 WriteQueueNum
> 3. **消息过滤**：对于可丢弃的消息快速跳过
> 4. **异步处理**：消费后异步处理，快速 ACK
> 5. **扩容 Broker**：增加 Broker 节点分摊负载

### Q9: 如何实现消息回溯？

> RocketMQ 支持按时间戳回溯：
> ```
> consumer.setConsumeFromWhere(ConsumeFromWhere.CONSUME_FROM_TIMESTAMP);
> ```
> Broker 根据时间戳找到对应的 ConsumeQueue 偏移量，Consumer 从该位置开始消费。

### Q10: 事务消息的实现原理？为什么可靠？

> 1. **半消息**：Producer 先发一条 PREPARED 消息（Consumer 不可见）
> 2. **执行本地事务**：成功 → COMMIT，失败 → ROLLBACK
> 3. **回查机制**：如果半消息长时间未确认，Broker 主动回查 Producer 的 `checkLocalTransaction`
> 4. 半消息写入 CommitLog，Broker 宕机可恢复；回查保证了最终一致性

### Q11: 消息的存储结构是怎样的？

> 三层文件：
> 1. **CommitLog**：所有消息的原始数据，混合存储，顺序写
> 2. **ConsumeQueue**：每个 Topic/Queue 的索引，20 字节/条（CommitLogOffset + Size + TagHash）
> 3. **IndexFile**：基于 Key 的哈希索引，用于快速查询指定 Key 的消息

### Q12: Rebalance 的触发时机？

> 1. Consumer 启动或关闭 → 触发 20s 内 Rebalance
> 2. Broker 上线或下线 → 触发 30s 内感知
> 3. Topic 的 Queue 数量变化 → 触发
> 4. Consumer 心跳超时被剔除 → 其他 Consumer Rebalance
> 5. 定时周期检查（20s 一次）

### Q13: 延迟消息的原理和局限？

> **原理**：延迟消息写入 `SCHEDULE_TOPIC_XXXX` 的 ConsumeQueue，ScheduleMessageService 定时扫描，到期后投递到原始 Topic。**局限**：只支持 18 个预定义级别，不支持任意时间。开源方案可用 `RocketMQ-Delay-Server` 或基于时间轮的自定义实现。

### Q14: 消息过滤在 Broker 端还是 Consumer 端？

> **Broker 端**：Tag 过滤在 Broker 端完成（通过 ConsumeQueue 条目中的 tagsCode Hash），减少网络传输。SQL92 过滤也在 Broker 端，但需要反序列化消息属性（性能开销大）。Kafka 是 Consumer 端过滤。

### Q15: 重复消费的场景和解决方案？

> **场景**：
> 1. Producer 重复发送（发送成功但 ACK 丢失 → 重发）
> 2. Consumer 重复消费（消费成功但 ACK 丢失 → Broker 重新投递）
> 3. Rebalance 时重复消费（Queue 重新分配 → 某些消息未 ACK 被重新消费）
> **方案**：消费端幂等处理（DB 唯一键、Redis、去重表）

### Q16: 消息顺序性如何保证？

> - **全局顺序**：单 Queue + 单 Consumer（性能差）
> - **分区顺序**：同 Key 路由到同一 Queue → 单线程串行消费（局部有序）
> - 顺序消费时使用 `MessageListenerOrderly`，同一 Queue 的消息串行处理

### Q17: Producer 的故障转移机制？

> Producer 维护 TopicPublishInfo，包含 20 种算法：
> 1. **开缺陷转移**（sendLatencyFaultEnable=true）：根据上次发送的延迟判断 Broker 是否可用
> 2. **未开缺陷转移**：轮询所有 Queue，失败的 Queue 不重试

### Q18: RocketMQ 的零拷贝机制？

> 1. **mmap**：写入 CommitLog + ConsumeQueue 使用 MappedByteBuffer（堆外内存映射）
> 2. **sendfile**：Consumer 拉取消息时，Broker 使用 `FileRegion.transferTo()` → 零拷贝发送

### Q19: 主从切换时如何处理？

> - **异步复制**：从节点可能缺失部分数据，消费者可能消费不到
> - **同步复制**：从节点拥有全部数据，切换后无影响
> - **Dledger**：Raft 协议保证切换后数据一致，超过半数节点拥有完整数据

### Q20: RocketMQ 的刷盘策略如何选择？

> | 场景 | 推荐策略 | 刷盘 | 复制 |
> |------|---------|------|------|
> | 日志/监控 | 异步 | 异步 | 异步 |
> | 订单/交易 | 同步 | 同步 | 同步 |
> | 中等重要性 | 异步刷盘 | 同步复制 |

---

## 附录 A：RocketMQ 核心参数速查表

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `flushDiskType` | ASYNC_FLUSH | 刷盘模式（SYNC_FLUSH/ASYNC_FLUSH） |
| `brokerRole` | ASYNC_MASTER | Broker 角色（SYNC_MASTER/ASYNC_MASTER/SLAVE） |
| `mapedFileSizeCommitLog` | 1GB | CommitLog 文件大小 |
| `mapedFileSizeConsumeQueue` | 30 万×20B | ConsumeQueue 文件大小 |
| `messageDelayLevel` | 1s~2h (18级) | 延迟消息级别 |
| `sendMessageThreadPoolNums` | 1 | 发送消息线程池大小 |
| `pullMessageThreadPoolNums` | 16+CPUs×2 | 拉消息线程池大小 |
| `transactionCheckInterval` | 60s | 事务消息回查间隔 |
| `transactionTimeOut` | 6s | 事务消息超时 |
| `maxReconsumeTimes` | 16 | 消费最大重试次数 |
| `longPollingEnable` | true | 启用长轮询 |
| `shortPollingTimeMills` | 1000 | 短轮询等待时间 |
| `scanNotActiveBrokerInterval` | 5s | NameServer 心跳超时扫描间隔 |
| `brokerNotActiveTimeoutMillis` | 120s | NameServer Broker 心跳超时 |

## 附录 B：RocketMQ 版本演进

| 版本 | 核心特性 |
|------|---------|
| 1.x | MetaQ |
| 2.x | 更名为 RocketMQ |
| 3.x | CommitLog + ConsumeQueue 存储模型 |
| 4.0 | 支持 SQL92 过滤、定时消息 |
| 4.3 | 事务消息 |
| 4.5 | Dledger (Raft) |
| 4.7 | ACL 鉴权 |
| 4.9 | 轻量级消息追踪 |
| 5.0 | Pop 消费模式、Proxy、Controller 模式 |

## 附录 C：RocketMQ 与已有文档的衔接关系

```
                       ┌──────────────────────────┐
                       │    Spring 全家桶综合串讲    │
                       └────────────┬─────────────┘
                                    │
         ┌──────────────────────────┼──────────────────────────┐
         │                          │                          │
         ▼                          ▼                          ▼
┌─────────────────┐    ┌─────────────────────┐    ┌──────────────────────┐
│ Spring Cloud     │    │  Dubbo               │    │  MySQL                │
│ (Nacos/Sentinel/ │    │  (SPI/服务治理/协议)  │    │  (索引/EXPLAIN/事务)  │
│  Gateway)        │    │                      │    │                      │
└────────┬────────┘    └──────────┬───────────┘    └──────────┬───────────┘
         │                        │                           │
         │                        │ 注册中心: ZK/Nacos        │
         │                        │                           │
         ▼                        ▼                           ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         RocketMQ                                         │
│                                                                          │
│  与 Spring Cloud:  [Gateway → Controller → 发消息 → RocketMQ Broker]    │
│  与 Dubbo:         [Dubbo 调用完成后 → 投递事务消息]                     │
│  与 MySQL:         [本地事务 DB 写入 + RocketMQ 事务消息 → 最终一致]     │
│  与 Redis:         [缓存失效 → 发送 MQ 重建缓存消息]                     │
│  与 Zookeeper:     [NameServer vs ZK 路由注册机制对比]                   │
│  与 Nacos:         [Nacos 也可作为 RocketMQ 的注册中心]                  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

> 本文是第 24 份源码学习文档，至此已完成 Java 基础/并发 → Spring 全家桶 → MySQL → Redis → 分布式中间件（Dubbo/Nacos/Netty/Nginx/ZK/ES）→ 消息队列（RocketMQ）的完整体系。
