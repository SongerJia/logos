# 系统设计深度解析：分库分表 + CAP/BASE + 一致性哈希

> 面试高频系统设计三大核心理论，从原理到实战全链路拆解
> 每个模块含：理论基础 → 实战设计 → 源码级实现 → 面试追问防线

---

# 第一篇：分库分表

## 第一章 为什么需要分库分表

### 1.1 单库单表的瓶颈

```
┌──────────────────────────────────────────────────────────┐
│          单库单表性能瓶颈演进                              │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  数据量增长阶段：                                          │
│                                                          │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌────────┐│
│  │ < 500万  │───→│ 500-2000万│───→│ 2000-5000万│───→│> 5000万││
│  │ 正常运行 │    │ 索引优化 │    │ 性能下降 │    │ 不可用 ││
│  │ 单表OK   │    │ 还能撑  │    │ 急需拆分 │    │ 必须拆 ││
│  └─────────┘    └─────────┘    └─────────┘    └────────┘│
│                                                          │
│  瓶颈表现：                                               │
│  1. IO瓶颈：数据量大 → 索引B+Tree层级深 → 查询IO次数多    │
│  2. CPU瓶颈：复杂查询 → 全表扫描/大范围扫描 → CPU占用高    │
│  3. 锁瓶颈：高并发更新 → 行锁/表锁竞争激烈                │
│  4. 连接瓶颈：并发连接数超过MySQL max_connections          │
│  5. 内存瓶颈：Buffer Pool无法缓存所有热数据               │
│                                                          │
│  MySQL单机性能天花板：                                    │
│  - 写QPS：约5000~8000（取决于硬件）                       │
│  - 读QPS：约10000~20000（有缓存）                        │
│  - 数据量：单表超过500万行性能明显下降                     │
│  - 连接数：默认151，调到几千仍有上限                       │
└──────────────────────────────────────────────────────────┘
```

### 1.2 分库分表的两种维度

```
┌──────────────────────────────────────────────────────────┐
│          分库分表两种维度                                  │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  垂直拆分（按业务拆）：                                    │
│  ┌────────────────────────┐                              │
│  │   单库 all_in_one       │                              │
│  │ ├─ user表              │                              │
│  │ ├─ order表             │                              │
│  │ ├─ product表           │                              │
│  │ ├─ payment表           │                              │
│  │ ├─ log表               │                              │
│  │ └─────────→ 拆分：      │                              │
│  │                                                         │
│  │  user_db    order_db   product_db   log_db            │
│  │  ├─user     ├─order    ├─product    ├─log             │
│  │  ├─role     ├─order_   ├─category   ├─operation_log  │
│  │             detail     ├─sku        ├─access_log      │
│  │             ├─pay_item                              │
│  └────────────────────────┘                              │
│                                                          │
│  水平拆分（按数据拆）：                                    │
│  ┌────────────────────────┐                              │
│  │   order表（5000万行）    │                              │
│  │   ───────────→ 拆分：    │                              │
│  │                                                         │
│  │  db_0        db_1        db_2        db_3             │
│  │  ├─t_0       ├─t_0       ├─t_0       ├─t_0           │
│  │  ├─t_1       ├─t_1       ├─t_1       ├─t_1           │
│  │  ├─...       ├─...       ├─...       ├─...           │
│  │  └─t_3       └─t_3       └─t_3       └─t_3           │
│  │  4库×4表 = 16个分表                                     │
│  │  每个分表约312万行                                      │
│  └────────────────────────┘                              │
│                                                          │
│  实际方案：先垂直拆分业务，再水平拆分大表                   │
└──────────────────────────────────────────────────────────┘
```

### 1.3 垂直拆分详解

**垂直分库**：按业务领域拆分数据库

```
原则：
1. 高内聚低耦合：经常一起使用的表放同一库
2. 业务边界清晰：不同微服务使用不同数据库
3. 独立演进：各库可独立优化、扩容、备份

拆分示例：
┌──────────────────────────────────────────────────┐
│  用户中心库 (user_db)                             │
│  ├─ t_user          用户基本信息                   │
│  ├─ t_user_profile  用户详情                      │
│  ├─ t_user_role     用户角色                      │
│  └─ t_user_setting  用户设置                      │
│                                                  │
│  交易中心库 (trade_db)                            │
│  ├─ t_order         订单                          │
│  ├─ t_order_item    订单明细                      │
│  ├─ t_payment       支付记录                      │
│  └─ t_refund        退款记录                      │
│                                                  │
│  商品中心库 (product_db)                          │
│  ├─ t_product       商品                          │
│  ├─ t_category      分类                          │
│  ├─ t_sku           SKU                           │
│  └─ t_inventory     库存                          │
│                                                  │
│  日志库 (log_db)                                  │
│  ├─ t_operation_log 操作日志                      │
│  ├─ t_access_log    访问日志                      │
│  └─ t_error_log     错误日志                      │
└──────────────────────────────────────────────────┘
```

**垂直分表**：按字段使用频率拆分同一张表

```sql
-- 拆分前：t_user（100+字段，大部分查询只需要前10个）
CREATE TABLE t_user (
    id          BIGINT PRIMARY KEY,
    username    VARCHAR(50),
    password    VARCHAR(100),
    nickname    VARCHAR(50),
    avatar      VARCHAR(200),
    email       VARCHAR(100),
    phone       VARCHAR(20),
    -- 以下是低频字段（80%查询不需要）
    birthday    DATE,
    address     VARCHAR(500),
    education   VARCHAR(50),
    occupation  VARCHAR(50),
    bio         TEXT,           -- 个人简介，可能很长
    hobby       VARCHAR(500),
    -- ... 更多低频字段
);

-- 拆分后：热表 + 冷表
-- 热表：高频查询字段（查询快，IO少）
CREATE TABLE t_user (
    id          BIGINT PRIMARY KEY,
    username    VARCHAR(50),
    nickname    VARCHAR(50),
    avatar      VARCHAR(200),
    phone       VARCHAR(20)
);

-- 冷表：低频查询字段（不影响热表查询性能）
CREATE TABLE t_user_detail (
    id          BIGINT PRIMARY KEY,  -- 与热表同ID
    email       VARCHAR(100),
    birthday    DATE,
    address     VARCHAR(500),
    bio         TEXT
);
```

### 1.4 水平拆分详解

```
┌──────────────────────────────────────────────────────────┐
│          水平拆分：按分片键将数据分散到多个分表              │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  原始：order表5000万行                                    │
│                                                          │
│  拆分后（4库 × 4表 = 16分片）：                            │
│                                                          │
│  db_0                    db_1                            │
│  ├─ order_0 (312万)      ├─ order_0 (312万)              │
│  ├─ order_1 (312万)      ├─ order_1 (312万)              │
│  ├─ order_2 (312万)      ├─ order_2 (312万)              │
│  └─ order_3 (312万)      └─ order_3 (312万)              │
│                                                          │
│  db_2                    db_3                            │
│  ├─ order_0 (312万)      ├─ order_0 (312万)              │
│  ├─ order_1 (312万)      ├─ order_1 (312万)              │
│  ├─ order_2 (312万)      ├─ order_2 (312万)              │
│  └─ order_3 (312万)      └─ order_3 (312万)              │
│                                                          │
│  路由规则：                                               │
│  分片键 = user_id                                         │
│  库编号 = hash(user_id) % 4                               │
│  表编号 = hash(user_id) / 4 % 4                           │
│                                                          │
│  例：user_id = 123                                        │
│  hash(123) = 123                                          │
│  库编号 = 123 % 4 = 3 → db_3                             │
│  表编号 = 123 / 4 % 4 = 3 → order_3                      │
│  → 数据在 db_3.order_3                                    │
└──────────────────────────────────────────────────────────┘
```

---

## 第二章 分片策略与路由算法

### 2.1 分片键选择原则

```
┌──────────────────────────────────────────────────────────┐
│          分片键选择——最关键的设计决策                       │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  选择原则：                                               │
│  1. 数据均匀分布 → 避免数据倾斜（某分片过大）              │
│  2. 查询尽量落到单分片 → 避免跨库查询                      │
│  3. 业务核心维度 → 最常用的查询条件                        │
│                                                          │
│  常见分片键选择：                                          │
│  ┌─────────────┬────────────┬──────────────────────┐     │
│  │ 业务场景     │ 分片键      │ 原因                 │     │
│  ├─────────────┼────────────┼──────────────────────┤     │
│  │ 用户系统     │ user_id    │ 大部分查询按用户维度   │     │
│  │ 订单系统     │ user_id    │ 用户查自己的订单      │     │
│  │ 支付流水     │ order_id   │ 按订单查支付记录      │     │
│  │ 日志系统     │ create_time│ 按时间范围查日志      │     │
│  │ 商品系统     │ product_id │ 按商品查库存/详情     │     │
│  └─────────────┴────────────┴──────────────────────┘     │
│                                                          │
│  ⚠️ 避免选以下字段做分片键：                              │
│  - auto_increment id：新增数据集中在一个分片               │
│  - 状态字段：数据严重倾斜（status=active占90%）           │
│  - 时间字段（只用日期）：同一天数据集中                    │
│  - 随机字符串：无法路由，每次都要全分片扫描                │
└──────────────────────────────────────────────────────────┘
```

### 2.2 路由算法

**算法1：取模哈希**

```
┌──────────────────────────────────────────────────────────┐
│          取模哈希路由                                      │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  公式：分片编号 = hash(shardKey) % N                      │
│                                                          │
│  优点：                                                   │
│  - 数据分布均匀                                           │
│  - 实现简单                                               │
│  - 查询精确路由到单分片                                    │
│                                                          │
│  缺点：                                                   │
│  - 扩容困难！N从4变成5，所有数据都要重新分布               │
│  - 70%~80%的数据需要迁移                                  │
│                                                          │
│  示例（4分片 → 8分片扩容）：                               │
│  hash(1) % 4 = 1 → db_1                                  │
│  hash(1) % 8 = 1 → db_1 (不变 ✓)                         │
│  hash(5) % 4 = 1 → db_1                                  │
│  hash(5) % 8 = 5 → db_5 (变了！需要迁移 ✗)               │
│                                                          │
│  结论：取模哈希适合分片数量固定的场景                       │
│  不适合需要频繁扩容的场景                                  │
└──────────────────────────────────────────────────────────┘
```

**算法2：范围分片**

```
┌──────────────────────────────────────────────────────────┐
│          范围分片路由                                      │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  规则：按分片键的值范围划分                                │
│                                                          │
│  示例（按user_id范围）：                                   │
│  db_0: user_id 1 ~ 100万                                 │
│  db_1: user_id 100万 ~ 200万                             │
│  db_2: user_id 200万 ~ 300万                             │
│  db_3: user_id 300万 ~ 400万                             │
│                                                          │
│  优点：                                                   │
│  - 扩容方便（直接加新范围）                                │
│  - 范围查询友好（连续范围在同一分片）                      │
│  - 不需要迁移旧数据                                       │
│                                                          │
│  缺点：                                                   │
│  - 数据倾斜！新用户集中在最新分片                          │
│  - 热点问题：最新分片压力大，旧分片空闲                    │
│  - 非范围查询可能跨分片                                    │
│                                                          │
│  适用场景：                                               │
│  - 按时间分片的日志系统（天然时间顺序）                    │
│  - 数据量均匀增长（每个时间段数据量相似）                   │
└──────────────────────────────────────────────────────────┘
```

**算法3：一致性哈希（详见第三篇）**

```
┌──────────────────────────────────────────────────────────┐
│          一致性哈希路由                                    │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  核心优势：扩容时只需迁移约1/N的数据                       │
│  取模哈希扩容迁移70-80%，一致性哈希扩容迁移约25%           │
│                                                          │
│  详见第三篇"一致性哈希"章节                               │
└──────────────────────────────────────────────────────────┘
```

### 2.3 ShardingSphere 分片配置实战

```yaml
# ShardingSphere-JDBC 分片配置
# 4库 × 4表 = 16分片，按user_id取模

spring:
  shardingsphere:
    datasource:
      names: ds0,ds1,ds2,ds3
      ds0:
        type: com.zaxxer.hikari.HikariDataSource
        driver-class-name: com.mysql.cj.jdbc.Driver
        jdbc-url: jdbc:mysql://192.168.1.1:3306/db_0
        username: root
        password: xxx
      ds1:
        jdbc-url: jdbc:mysql://192.168.1.2:3306/db_1
      ds2:
        jdbc-url: jdbc:mysql://192.168.1.3:3306/db_2
      ds3:
        jdbc-url: jdbc:mysql://192.168.1.4:3306/db_3

    rules:
      sharding:
        tables:
          # 订单表：按user_id取模分4库4表
          t_order:
            actual-data-nodes: ds${0..3}.t_order${0..3}
            # 库路由：hash(user_id) % 4
            database-strategy:
              standard:
                sharding-column: user_id
                sharding-algorithm-name: order-db-mod
            # 表路由：hash(user_id) / 4 % 4
            table-strategy:
              standard:
                sharding-column: user_id
                sharding-algorithm-name: order-table-mod
            # 主键生成策略
            key-generate-strategy:
              column: id
              key-generator-name: snowflake

          # 订单明细表：跟订单表同分片
          t_order_item:
            actual-data-nodes: ds${0..3}.t_order_item${0..3}
            database-strategy:
              standard:
                sharding-column: user_id
                sharding-algorithm-name: order-db-mod
            table-strategy:
              standard:
                sharding-column: user_id
                sharding-algorithm-name: order-table-mod
            key-generate-strategy:
              column: id
              key-generator-name: snowflake

        # 绑定表：订单和订单明细必须同分片
        binding-tables:
          - t_order,t_order_item

        sharding-algorithms:
          order-db-mod:
            type: MOD
            props:
              sharding-count: 4
          order-table-mod:
            type: MOD
            props:
              sharding-count: 4
          # 一致性哈希算法（可选）
          order-consistent-hash:
            type: CONSISTENT_HASH
            props:
              sharding-count: 4

        key-generators:
          snowflake:
            type: SNOWFLAKE
            props:
              worker-id: 1
```

### 2.4 绑定表与广播表

```
┌──────────────────────────────────────────────────────────┐
│          绑定表 vs 广播表                                  │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  绑定表（Binding Table）：                                │
│  - 主表和子表使用相同分片键 → 数据落在同分片               │
│  - JOIN查询不需要跨库                                     │
│  - 例：t_order + t_order_item（都按user_id分片）          │
│                                                          │
│  广播表（Broadcast Table）：                              │
│  - 小表，每个分片都存一份全量数据                          │
│  - JOIN时可以在本地分片完成                                │
│  - 例：t_region（省市区表，几万行，每个库一份）            │
│  - 写操作：所有分片都写（保持一致）                        │
│  - 读操作：只读本地分片（避免跨库）                        │
│                                                          │
│  ┌──────────────────────────────────────────────┐        │
│  │  ds_0          ds_1          ds_2          ds_3│        │
│  │  ├─t_order_0   ├─t_order_0   ├─t_order_0   ├─t_order_0│
│  │  ├─t_item_0    ├─t_item_0    ├─t_item_0    ├─t_item_0│
│  │  ├─t_region*   ├─t_region*   ├─t_region*   ├─t_region*│ ←广播表│
│  │  └──────────────└──────────────└──────────────┘        │
│  │  * 每个库一份全量                                      │
│  └──────────────────────────────────────────────┘        │
└──────────────────────────────────────────────────────────┘
```

---

## 第三章 分布式ID生成方案

### 3.1 为什么不能用自增ID

```
┌──────────────────────────────────────────────────────────┐
│          分库分表后自增ID的问题                             │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  问题1：ID冲突                                            │
│  db_0: AUTO_INCREMENT → 1, 2, 3, 4...                   │
│  db_1: AUTO_INCREMENT → 1, 2, 3, 4...                   │
│  db_2: AUTO_INCREMENT → 1, 2, 3, 4...                   │
│  → 三个库都有 id=1 的记录！全局不唯一！                    │
│                                                          │
│  问题2：ID不连续                                          │
│  db_0: 1, 5, 9, 13... (步长=4)                          │
│  db_1: 2, 6, 10, 14...                                  │
│  db_2: 3, 7, 11, 15...                                  │
│  db_3: 4, 8, 12, 16...                                  │
│  → 设置不同起始值+步长可以避免冲突                        │
│  → 但扩容困难（增加第5个库，步长要改5）                   │
│                                                          │
│  问题3：可预测性                                          │
│  - 自增ID可推算业务量                                     │
│  - 爬虫可按ID遍历数据                                     │
│                                                          │
│  解决方案：分布式ID生成器                                  │
└──────────────────────────────────────────────────────────┘
```

### 3.2 Snowflake雪花算法

```
┌──────────────────────────────────────────────────────────┐
│          Snowflake ID 结构（64bit = 8字节 = Long）         │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  0 | 00000000 00000000 00000000 00000000 00000000 0      │
│    | ├────────41bit时间戳────────┤├──10bit机器──┤├12bit序│
│    | │  (毫秒级，可用69年)       ││(5数据中心+5││列号    │
│    | │                           ││工作机器)   ││(毫秒内 │
│    | │                           ││           ││4096)  │
│                                                          │
│  各部分解析：                                             │
│  1bit符号位：始终为0（Long正数）                          │
│  41bit时间戳：当前毫秒 - 开始毫秒(可自定义epoch)          │
│    → 2^41 / (365*24*60*60*1000) ≈ 69年                  │
│  10bit机器ID：5bit数据中心ID + 5bit工作机器ID             │
│    → 最多32个数据中心 × 32台机器 = 1024台                 │
│  12bit序列号：同一毫秒内的自增序号                        │
│    → 单机每毫秒最多4096个ID = 每秒400万                  │
│                                                          │
│  总容量：1024台机器 × 400万/秒 = 理论峰值40亿/秒          │
│  实际单机：400万/秒，远超任何业务需求                     │
└──────────────────────────────────────────────────────────┘
```

```java
/**
 * Snowflake ID生成器实现
 */
public class SnowflakeIdWorker {

    // 开始时间戳（2026-01-01 00:00:00）
    private final long epoch = 1735689600000L;

    // 位数分配
    private final long workerIdBits = 5L;     // 机器ID位数
    private final long datacenterIdBits = 5L; // 数据中心ID位数
    private final long sequenceBits = 12L;    // 序列号位数

    // 最大值
    private final long maxWorkerId = ~(-1L << workerIdBits);        // 31
    private final long maxDatacenterId = ~(-1L << datacenterIdBits); // 31
    private final long maxSequence = ~(-1L << sequenceBits);        // 4095

    // 位移
    private final long workerIdShift = sequenceBits;                          // 12
    private final long datacenterIdShift = sequenceBits + workerIdBits;       // 17
    private final long timestampShift = sequenceBits + workerIdBits + datacenterIdBits; // 22

    private final long workerId;
    private final long datacenterId;
    private long sequence = 0L;
    private long lastTimestamp = -1L;

    public SnowflakeIdWorker(long workerId, long datacenterId) {
        if (workerId > maxWorkerId || workerId < 0) {
            throw new IllegalArgumentException("workerId范围: 0~31");
        }
        if (datacenterId > maxDatacenterId || datacenterId < 0) {
            throw new IllegalArgumentException("datacenterId范围: 0~31");
        }
        this.workerId = workerId;
        this.datacenterId = datacenterId;
    }

    /**
     * 生成下一个ID（核心方法）
     */
    public synchronized long nextId() {
        long timestamp = System.currentTimeMillis();

        // 1. 时钟回拨检测（重要！）
        if (timestamp < lastTimestamp) {
            long offset = lastTimestamp - timestamp;
            if (offset <= 5) {
                // 小幅回拨：等待时钟追上
                try { Thread.sleep(offset * 2); } catch (InterruptedException e) {}
                timestamp = System.currentTimeMillis();
                if (timestamp < lastTimestamp) {
                    throw new RuntimeException("时钟回拨超过5ms，拒绝生成ID");
                }
            } else {
                throw new RuntimeException("时钟回拨超过5ms，拒绝生成ID");
            }
        }

        // 2. 同一毫秒内：序列号自增
        if (timestamp == lastTimestamp) {
            sequence = (sequence + 1) & maxSequence;
            if (sequence == 0) {
                // 序列号溢出：等到下一毫秒
                timestamp = tilNextMillis(lastTimestamp);
            }
        } else {
            // 不同毫秒：序列号从0开始
            sequence = 0L;
        }

        lastTimestamp = timestamp;

        // 3. 组装ID
        return ((timestamp - epoch) << timestampShift)
             | (datacenterId << datacenterIdShift)
             | (workerId << workerIdShift)
             | sequence;
    }

    private long tilNextMillis(long lastTimestamp) {
        long timestamp = System.currentTimeMillis();
        while (timestamp <= lastTimestamp) {
            timestamp = System.currentTimeMillis();
        }
        return timestamp;
    }
}
```

**Snowflake时钟回拨问题及解决方案**：

```
┌──────────────────────────────────────────────────────────┐
│          Snowflake时钟回拨问题                             │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  问题：NTP同步导致系统时钟回拨                             │
│  → lastTimestamp > 当前时间                               │
│  → 可能生成重复ID                                         │
│                                                          │
│  解决方案（从轻到重）：                                    │
│                                                          │
│  1. 小幅回拨（<5ms）：等待时钟追上                         │
│     Thread.sleep(offset * 2)                              │
│                                                          │
│  2. 中等回拨（<500ms）：借用未来时间                       │
│     用lastTimestamp + offset生成ID                        │
│     代价：ID时间戳不准确（但全局仍然唯一）                  │
│                                                          │
│  3. 大幅回拨（>500ms）：拒绝生成 + 告警                    │
│     throw RuntimeException                               │
│     运维介入检查NTP配置                                   │
│                                                          │
│  4. 百度UidGenerator方案：RingBuffer预生成                 │
│     提前生成一批ID放入环形缓冲区                           │
│     即使时钟回拨，从缓冲区取ID也不会重复                   │
│                                                          │
│  5. 美团Leaf方案：Zookeeper分配workerId                   │
│     双Buffer + 自增序列                                   │
│     时钟回拨时从备用Buffer取ID                             │
└──────────────────────────────────────────────────────────┘
```

### 3.3 其他分布式ID方案对比

| 方案 | 原理 | 优点 | 缺点 | 性能 |
|------|------|------|------|------|
| UUID | 随机128bit | 简单无依赖 | 无序不可排序/字符串存储效率低/索引性能差 | 极高 |
| DB自增 | AUTO_INCREMENT | 简单有序 | 性能瓶颈/单点故障 | 低 |
| DB号段模式 | 批量取号段 | 有序/减少DB访问 | DB单点/号段不连续 | 中 |
| Redis INCR | 单线程自增 | 有序/性能好 | Redis持久化风险 | 高 |
| Snowflake | 时间+机器+序列 | 有序/高性能/无依赖 | 时钟回拨风险 | 极高 |
| 美团Leaf | 号段+Snowflake双模式 | 高可用/解决时钟回拨 | 依赖ZK | 高 |
| 百度Uid | RingBuffer预生成 | 极高性能 | 时间不准 | 极高 |

**推荐选择**：绝大多数场景用 Snowflake 足够，时钟回拨概率极低且有多种应对方案。

---

## 第四章 跨库查询问题与解决方案

### 4.1 跨库查询场景

```
┌──────────────────────────────────────────────────────────┐
│          跨库查询的四大难题                                │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  1. 跨库JOIN                                              │
│     SELECT o.*, u.nickname                               │
│     FROM t_order o JOIN t_user u ON o.user_id = u.id     │
│     → order在ds0, user在user_db → 无法直接JOIN            │
│                                                          │
│  2. 跨库聚合                                             │
│     SELECT COUNT(*) FROM t_order WHERE status = 'PAID'    │
│     → 需要查所有16个分片 → 合并结果                       │
│                                                          │
│  3. 跨库排序                                             │
│     SELECT * FROM t_order ORDER BY create_time LIMIT 10   │
│     → 每个分片取TOP 10 → 内存中合并排序取全局TOP 10       │
│                                                          │
│  4. 跨库分页                                             │
│     SELECT * FROM t_order ORDER BY id LIMIT 100, 10       │
│     → 第101~110条在哪个分片？不知道 → 必须查所有分片       │
│     → 每个分片取100+10=110条 → 合并排序 → 取第101~110    │
│     → 性能极差！深分页（LIMIT 10000,10）更恐怖            │
└──────────────────────────────────────────────────────────┘
```

### 4.2 跨库JOIN解决方案

```
┌──────────────────────────────────────────────────────────┐
│          跨库JOIN四种解决方案                              │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  方案1：绑定表（最佳方案）                                 │
│  - 主表和子表用相同分片键 → 数据在同一分片                 │
│  - t_order和t_order_item都按user_id分片                   │
│  - JOIN查询自然落在同一分片，无需跨库                     │
│                                                          │
│  方案2：广播表                                           │
│  - 小表全量复制到每个分片                                  │
│  - t_region（省市区）每个库一份                           │
│  - JOIN在本地分片完成                                     │
│                                                          │
│  方案3：全局表                                           │
│  - 和广播表类似，但适用于稍大的表                          │
│  - 用ETL工具定时同步到各分片                              │
│                                                          │
│  方案4：应用层组装                                        │
│  - 分别查各库 → 应用代码JOIN                              │
│  - 先查order → 拿到user_id列表 → 批量查user              │
│  - 适合：非频繁的跨库查询                                  │
│                                                          │
│  ⚠️ 反模式：                                             │
│  - ShardingSphere的跨库JOIN（笛卡尔积式）                 │
│  - 每个分片的每条记录都要和其他分片JOIN                    │
│  - 性能极差，只适合小数据量                                │
└──────────────────────────────────────────────────────────┘
```

```java
// 应用层组装示例
@Service
public class OrderQueryService {

    /**
     * 查询订单列表（含用户昵称）
     * 应用层组装，而非SQL JOIN
     */
    public List<OrderVO> queryOrdersWithUser(OrderQuery query) {
        // 1. 查订单（路由到单分片）
        List<Order> orders = orderMapper.selectByUserId(query.getUserId());

        if (orders.isEmpty()) {
            return Collections.emptyList();
        }

        // 2. 收集user_id列表
        Set<Long> userIds = orders.stream()
            .map(Order::getUserId)
            .collect(Collectors.toSet());

        // 3. 批量查用户（user_db）
        Map<Long, User> userMap = userService.batchGetUsers(userIds)
            .stream()
            .collect(Collectors.toMap(User::getId, u -> u));

        // 4. 应用层组装
        return orders.stream().map(order -> {
            OrderVO vo = new OrderVO();
            vo.setOrder(order);
            vo.setNickname(userMap.get(order.getUserId()).getNickname());
            return vo;
        }).collect(Collectors.toList());
    }
}
```

### 4.3 跨库分页解决方案

```
┌──────────────────────────────────────────────────────────┐
│          跨库分页——最难的问题                              │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  问题：                                                  │
│  SELECT * FROM t_order ORDER BY create_time LIMIT 10000,10│
│  → 每个分片取10010条 → 合并排序 → 取最后10条              │
│  → 16分片 × 10010条 = 160160条需要加载到内存              │
│  → 深分页性能灾难                                        │
│                                                          │
│  解决方案1：禁止深分页                                    │
│  - 不提供"跳转到第N页"功能                               │
│  - 只提供"下一页"（基于游标分页）                         │
│  - WHERE create_time > lastTime ORDER BY create_time      │
│  - 每次查询只往后看，不回头                               │
│                                                          │
│  解决方案2：二次查询法                                    │
│  - 第一次：各分片查 LIMIT 10010 的最大create_time         │
│  - 第二次：各分片查 WHERE create_time > maxTime           │
│  - 大幅减少数据量                                        │
│                                                          │
│  解决方案3：全局索引表                                    │
│  - 维护一张全局索引表（不分片）                           │
│  - 只存(排序字段, 分片位置)                               │
│  - 先查索引表定位分片 → 再查具体数据                     │
│                                                          │
│  解决方案4：ES/Redis辅助                                  │
│  - 需要跨库查询/排序/分页的数据 → 同步到ES               │
│  - ES天然支持全局排序分页                                 │
│  - 查ES拿到ID列表 → 再按ID查各分片                       │
└──────────────────────────────────────────────────────────┘
```

### 4.4 ShardingSphere跨库查询机制

```java
// ShardingSphere处理跨库查询的核心流程
/**
 * ShardingSphere SQL执行引擎
 * 1. SQL解析 → 提取分片键
 * 2. SQL路由 → 决定哪些分片需要执行
 * 3. SQL改写 → 改写SQL适配各分片（如LIMIT改写）
 * 4. SQL执行 → 并行执行各分片SQL
 * 5. 结果归并 → 合并各分片结果
 */

// 分页查询改写示例
// 原始SQL：SELECT * FROM t_order ORDER BY id LIMIT 100, 10
// 
// ShardingSphere改写：
// 各分片执行：SELECT * FROM t_order_0 ORDER BY id LIMIT 0, 110
// 各分片执行：SELECT * FROM t_order_1 ORDER BY id LIMIT 0, 110
// ...
// 合并：对所有分片结果排序 → 取第100~109条

// 归并策略（根据SQL类型）：
// SELECT COUNT(*) → 聚合归并（SUM各分片COUNT）
// SELECT * ORDER BY → 排序归并（归并排序）
// SELECT * GROUP BY → 分组归并
// LIMIT → Limit归并
```

---

## 第五章 分库分表扩容方案

### 5.1 扩容难点

```
┌──────────────────────────────────────────────────────────┐
│          分库分表扩容的核心难题                             │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  取模分片扩容：                                           │
│  4库 → 8库                                               │
│  hash(user_id) % 4 → hash(user_id) % 8                   │
│                                                          │
│  问题：                                                  │
│  - 旧数据按%4分布，新数据按%8分布                        │
│  - 50%的数据需要迁移                                     │
│  - 迁移过程中如何保证服务可用？                           │
│                                                          │
│  迁移数据量估算：                                         │
│  - 4库每库2500万 → 总1亿                                │
│  - 扩到8库 → 5000万条需要迁移                            │
│  - 迁移耗时：小时级                                      │
│                                                          │
│  关键要求：                                               │
│  1. 迁移过程中服务不停机                                  │
│  2. 迁移过程中数据不丢失                                  │
│  3. 迁移完成后无缝切换                                    │
└──────────────────────────────────────────────────────────┘
```

### 5.2 成倍扩容法（推荐）

```
┌──────────────────────────────────────────────────────────┐
│          成倍扩容法（最简单的扩容方案）                     │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  核心思路：每次扩容翻倍（4→8→16→32）                     │
│  这样旧数据的分布规则不变！                               │
│                                                          │
│  原来：4库，hash(user_id) % 4                            │
│  扩容：8库，hash(user_id) % 8                            │
│                                                          │
│  旧数据迁移：                                            │
│  db_0 → db_0(不变) + db_4(迁移)                         │
│  db_1 → db_1(不变) + db_5(迁移)                         │
│  db_2 → db_2(不变) + db_6(迁移)                         │
│  db_3 → db_3(不变) + db_7(迁移)                         │
│                                                          │
│  迁移规则：hash(user_id) % 8 != hash(user_id) % 4 的数据 │
│  → 即 hash(user_id) % 4 的值 >= 4 的数据                │
│                                                          │
│  优点：                                                  │
│  - 只需迁移50%数据                                       │
│  - 每个旧库拆成两个新库，逻辑简单                        │
│  - 可以逐库迁移，不影响其他库                            │
│                                                          │
│  实操步骤：                                               │
│  1. 新建db_4~db_7（空库）                                │
│  2. 从db_0复制一半数据到db_4                             │
│  3. 验证db_4数据正确                                     │
│  4. 切换路由规则%4 → %8                                  │
│  5. 删除db_0中已迁移到db_4的数据                         │
│  6. 重复步骤2~5处理db_1→db_5, db_2→db_6, db_3→db_7    │
└──────────────────────────────────────────────────────────┘
```

### 5.3 一致性哈希扩容（详见第三篇）

```
┌──────────────────────────────────────────────────────────┐
│          一致性哈希扩容优势                                │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  扩容4→5分片：                                            │
│  - 取模哈希：70-80%数据需要迁移                           │
│  - 一致性哈希：只有约20-25%数据需要迁移                   │
│  - 新节点只影响相邻节点上的数据                           │
│                                                          │
│  详见第三篇"一致性哈希"                                  │
└──────────────────────────────────────────────────────────┘
```

### 5.4 扩容过程中的数据一致性

```
┌──────────────────────────────────────────────────────────┐
│          扩容双写方案（不停机迁移）                        │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  1. 双写阶段：                                           │
│     - 新写入同时写旧分片和新分片                          │
│     - 读仍从旧分片读                                     │
│     - 持续一段时间（确保所有新数据都到新分片）              │
│                                                          │
│  2. 历史数据迁移：                                       │
│     - 离线迁移旧数据到新分片                              │
│     - 校验数据一致性                                     │
│                                                          │
│  3. 切读阶段：                                           │
│     - 读从新分片读                                       │
│     - 写仍双写                                           │
│     - 验证新分片读正常                                   │
│                                                          │
│  4. 去双写阶段：                                         │
│     - 写只写新分片                                       │
│     - 删除旧分片中已迁移的数据                            │
│                                                          │
│  5. 清理阶段：                                           │
│     - 旧分片退役                                         │
│                                                          │
│  关键保障：                                               │
│  - 每步都可回滚                                          │
│  - 校验数据完整性                                        │
│  - 灰度切换，逐步放量                                    │
└──────────────────────────────────────────────────────────┘
```

---

## 第六章 ShardingSphere 源码级解析

### 6.1 ShardingSphere架构

```
┌──────────────────────────────────────────────────────────┐
│          ShardingSphere 三大产品线                        │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ShardingSphere-JDBC（轻量级，推荐）：                    │
│  - Java框架，应用内嵌入                                  │
│  - 伪装成DataSource，应用无感知                          │
│  - 性能损耗极小（直连DB）                                │
│  - 适合：Java应用，分片规则相对固定                       │
│                                                          │
│  ShardingSphere-Proxy（独立代理）：                       │
│  - 独立部署的数据库代理服务                               │
│  - 对应用完全透明（像连接MySQL一样）                      │
│  - 支持异构语言（任何语言都可以用）                       │
│  - 性能损耗稍大（多一次网络转发）                        │
│  - 适合：多语言环境、分片规则频繁变更                     │
│                                                          │
│  ShardingSphere-Sidecar（云原生）：                       │
│  - 基于Envoy的Mesh方案                                  │
│  - 对应用完全透明                                        │
│  - 未来方向，尚未成熟                                    │
│                                                          │
│  JDBC vs Proxy选择：                                     │
│  ┌──────────┬──────────────┬──────────────┐             │
│  │ 维度      │ JDBC          │ Proxy        │             │
│  ├──────────┼──────────────┼──────────────┤             │
│  │ 性能      │ 高（直连DB）  │ 中（多一跳）  │             │
│  │ 透明性    │ 需配置应用    │ 完全透明      │             │
│  │ 语言限制  │ Java only    │ 任何语言      │             │
│  │ 运维      │ 简单          │ 独立部署维护  │             │
│  │ 适用      │ 单语言Java   │ 多语言/运维需求│             │
│  └──────────┴──────────────┴──────────────┘             │
└──────────────────────────────────────────────────────────┘
```

### 6.2 ShardingSphere-JDBC核心流程源码

```java
// ShardingSphere核心执行流程（5步）
// 1. SQL Parsing → 2. SQL Route → 3. SQL Rewrite → 4. SQL Execute → 5. Result Merge

/**
 * ShardingSphere执行引擎入口
 * 类：ShardingSpherePreparedStatement
 */
public class ShardingSpherePreparedStatement extends AbstractPreparedStatement {

    @Override
    public ResultSet executeQuery() throws SQLException {
        // Step 1: SQL解析
        // ParserEngine将SQL解析为AST（抽象语法树）
        // 提取表名、分片键、WHERE条件、ORDER BY、LIMIT等
        SQLStatement sqlStatement = parserEngine.parse(sql);

        // Step 2: SQL路由
        // RouteEngine根据分片规则决定SQL应该路由到哪些分片
        // 核心逻辑：提取分片键值 → 计算路由目标
        RouteResult routeResult = routeEngine.route(
            sqlStatement, 
            connectionContext
        );

        // Step 3: SQL改写
        // RewriteEngine将原始SQL改写为各分片可执行的SQL
        // 如：t_order → t_order_0, LIMIT 100,10 → LIMIT 0,110
        List<ExecutionUnit> executionUnits = rewriteEngine.rewrite(
            sqlStatement, 
            routeResult
        );

        // Step 4: SQL执行
        // ExecutorEngine并行执行各分片SQL
        // 使用线程池并行执行，提高效率
        List<QueryResult> queryResults = executorEngine.execute(
            executionUnits,
            connectionContext
        );

        // Step 5: 结果归并
        // MergeEngine合并各分片结果
        // 根据SQL类型选择归并策略：
        // SELECT ORDER BY → 排序归并
        // SELECT GROUP BY → 分组归并
        // SELECT COUNT → 聚合归并
        // LIMIT → Limit归并
        ResultSet mergedResultSet = mergeEngine.merge(
            queryResults,
            sqlStatement
        );

        return mergedResultSet;
    }
}
```

### 6.3 路由引擎核心逻辑

```java
/**
 * 路由引擎核心逻辑
 * 类：ShardingRouter
 */
public class ShardingRouter {

    /**
     * 根据分片键值计算路由目标
     */
    public RouteResult route(SQLStatement sqlStatement) {
        // 1. 提取分片键值
        // 从WHERE条件中提取分片键对应的值
        Map<String, Comparable<?>> shardingValues = extractShardingValues(sqlStatement);

        // 2. 精确路由（分片键=具体值）
        if (isPreciseSharding(shardingValues)) {
            // hash(user_id) % 4 → 直接计算目标分片
            String targetDatasource = preciseShardingAlgorithm.calculate(shardingValues);
            String targetTable = tableShardingAlgorithm.calculate(shardingValues);
            return RouteResult.single(targetDatasource, targetTable);
        }

        // 3. 范围路由（分片键 BETWEEN/IN）
        if (isRangeSharding(shardingValues)) {
            // 计算范围涉及的所有分片
            List<RouteTarget> targets = rangeShardingAlgorithm.calculate(shardingValues);
            return RouteResult.multi(targets);
        }

        // 4. 无分片键 → 全分片路由（广播查询）
        // 所有分片都要执行，结果合并
        return RouteResult.all();
    }
}
```

---

---

# 第二篇：CAP定理与BASE理论

## 第七章 CAP定理

### 7.1 CAP定义

```
┌──────────────────────────────────────────────────────────┐
│          CAP定理（Brewer's Theorem）                      │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  C - Consistency（一致性）                                │
│  所有节点在同一时刻看到相同的数据                          │
│  例：写入db_0的数据，从db_1读也能立即看到                  │
│                                                          │
│  A - Availability（可用性）                               │
│  每个请求都能在合理时间内收到非错误响应                    │
│  例：即使某个节点故障，系统仍能响应读写请求                │
│                                                          │
│  P - Partition Tolerance（分区容忍性）                    │
│  系统在网络分区（节点间通信中断）时仍能继续运作             │
│  例：机房A和机房B网络断了，各自仍能提供服务                │
│                                                          │
│  ┌──────────────────────────────────────┐               │
│  │         CAP三角                       │               │
│  │              C                        │               │
│  │           ╱  ╲                        │               │
│  │          ╱    ╲                       │               │
│  │    CA ╱   P   ╲ AP                   │               │
│  │      ╱────────╲                       │               │
│  │     A          P                      │               │
│  │                                        │               │
│  │  只能同时满足两点，不能三点同时满足      │               │
│  └──────────────────────────────────────┘               │
│                                                          │
│  核心结论：                                               │
│  网络分区（P）必然发生 → 必须在C和A之间做选择              │
│  - 选择CP：牺牲可用性保证一致性                           │
│  - 选择AP：牺牲一致性保证可用性                           │
│  - CA不存在：因为网络分区不可避免                          │
└──────────────────────────────────────────────────────────┘
```

### 7.2 为什么只能三选二

```
┌──────────────────────────────────────────────────────────┐
│          为什么CP和AP矛盾？——网络分区场景推演              │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  场景：两个节点N1、N2，网络分区断开                       │
│                                                          │
│  ┌─────┐     ✗网络断开     ┌─────┐                      │
│  │ N1  │ ────────────────  │ N2  │                      │
│  │ db_0│                   │ db_1│                      │
│  └─────┘                   └─────┘                      │
│                                                          │
│  用户写N1：value = V2                                    │
│  用户读N2：value = V1（旧值）                            │
│                                                          │
│  此时必须做选择：                                         │
│                                                          │
│  选择CP（一致性优先）：                                   │
│  - N1写入成功 → 同步N2 → 但网络断了 → N2无法更新         │
│  - 选择：N2暂停服务（返回错误）→ 牺牲可用性               │
│  - 等网络恢复 → N2同步完成 → 重新提供服务                 │
│                                                          │
│  选择AP（可用性优先）：                                   │
│  - N1写入成功 → N2无法同步 → 但N2继续服务                │
│  - 用户读N2 → 返回V1（旧值）→ 牺牲一致性                 │
│  - 网络恢复后 → N2异步同步 → 最终一致性                   │
│                                                          │
│  不能选择CA：                                             │
│  - CA假设网络永远不分区 → 但现实中网络分区必然发生         │
│  - 所以CA在分布式系统中不存在                             │
│  - 单机系统（如单机MySQL）可以CA，但不是分布式             │
└──────────────────────────────────────────────────────────┘
```

### 7.3 三种CAP组合及实例

```
┌──────────────────────────────────────────────────────────┐
│          三种CAP组合及典型系统                              │
├─────────────┬─────────────┬──────────────────────────────┤
│   CP系统     │   AP系统     │   CA系统（理论上不存在）      │
├─────────────┼─────────────┼──────────────────────────────┤
│ 一致性优先   │ 可用性优先   │ 单机系统                      │
│ 分区时牺牲A │ 分区时牺牲C │ 不考虑分区（不现实）           │
├─────────────┼─────────────┼──────────────────────────────┤
│ Zookeeper   │ Cassandra   │ 单机MySQL                     │
│ Etcd        │ DynamoDB    │ 单机Redis                     │
│ HBase       │ Eureka      │ 单机PostgreSQL                │
│ MongoDB     │ Consul(AP) │                              │
│ Redis(主从) │ Couchbase  │                              │
├─────────────┼─────────────┼──────────────────────────────┤
│ 适合：      │ 适合：      │ 适合：                        │
│ 金融交易    │ 社交/内容   │ 小规模应用                    │
│ 配置中心    │ 电商推荐    │ 不需要分布式                  │
│ 分布式锁    │ 日志/监控   │                              │
├─────────────┼─────────────┼──────────────────────────────┤
│ 写多读少    │ 读多写少    │                              │
│ 数据准确性  │ 高可用优先  │                              │
│ 关键        │ 数据可容忍  │                              │
│             │ 短暂不一致 │                              │
└─────────────┴─────────────┴──────────────────────────────┘

注意：CAP不是绝对的二选一，而是分区发生时的倾向选择
实际系统在网络正常时同时满足C和A，只在分区时做取舍
```

### 7.4 CAP在微服务架构中的选择

```
┌──────────────────────────────────────────────────────────┐
│          不同业务场景的CAP选择                              │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  金融交易 → CP                                           │
│  ┌──────────────────────────────────────────┐           │
│  │ 转账：张三→李四 100元                     │           │
│  │ 一致性：绝对不能出现张三扣了钱但李四没收到 │           │
│  │ 可用性：暂时不可用可以接受（返回"系统繁忙"）│           │
│  │ 方案：2PC/TCC/Seata AT → 强一致性         │           │
│  └──────────────────────────────────────────┘           │
│                                                          │
│  电商订单 → AP + 最终一致                                 │
│  ┌──────────────────────────────────────────┐           │
│  │ 下单+扣库存+扣余额                        │           │
│  │ 一致性：可以容忍短暂不一致（库存显示1→实际0）│           │
│  │ 可用性：宁可多卖也不能完全不可用           │           │
│  │ 方案：RocketMQ事务消息 + 本地消息表        │           │
│  └──────────────────────────────────────────┘           │
│                                                          │
│  社交内容 → AP                                           │
│  ┌──────────────────────────────────────────┐           │
│  │ 发朋友圈/点赞/评论                        │           │
│  │ 一致性：延迟几秒显示完全可以接受           │           │
│  │ 可用性：不能因为同步延迟导致不可用         │           │
│  │ 方案：异步复制 + 最终一致性               │           │
│  └──────────────────────────────────────────┘           │
│                                                          │
│  配置中心 → CP                                           │
│  ┌──────────────────────────────────────────┐           │
│  │ Nacos/Zookeeper 配置变更                  │           │
│  │ 一致性：所有节点必须看到相同配置           │           │
│  │ 可用性：配置不一致比不可用更危险           │           │
│  │ 方案：ZAB/Raft协议 → 强一致性             │           │
│  └──────────────────────────────────────────┘           │
└──────────────────────────────────────────────────────────┘
```

---

## 第八章 BASE理论

### 8.1 BASE定义

```
┌──────────────────────────────────────────────────────────┐
│          BASE理论——CAP的工程化妥协方案                     │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  BA - Basically Available（基本可用）                     │
│  系统在故障时允许响应时间变长或功能降级，但不完全不可用     │
│  例：                                                     │
│  - 响应时间：正常10ms → 故障时2秒（仍可用）               │
│  - 功能降级：正常返回全部数据 → 故障时返回部分数据        │
│  - 退款排队：正常实时退款 → 大促时退款延迟1小时           │
│                                                          │
│  S - Soft State（软状态）                                 │
│  允许系统中的数据存在中间状态，且该中间状态不影响系统可用   │
│  例：                                                     │
│  - 订单状态：创建→支付→发货（中间状态"已支付未发货"）     │
│  - 数据复制：主从同步中间状态（主写完，从还没同步完）     │
│  - 购物车：多端数据短暂不一致（手机加了，电脑还没看到）   │
│                                                          │
│  E - Eventually Consistent（最终一致性）                  │
│  系统保证在没有新更新操作的情况下，数据最终会达到一致状态   │
│  例：                                                     │
│  - 主从同步：主写入 → 从延迟1秒同步 → 最终一致           │
│  - 缓存更新：DB更新 → 缓存延迟更新 → 最终一致           │
│  - MQ异步：发送消息 → 消费者异步处理 → 最终一致          │
│                                                          │
│  时间窗口：                                               │
│  - 最终一致性不是立即一致，而是有延迟窗口                  │
│  - 通常：毫秒到秒级                                      │
│  - 极端：分钟级（网络故障恢复后）                          │
│                                                          │
│  BASE vs ACID：                                           │
│  ┌──────────┬──────────────┬──────────────┐             │
│  │ 维度      │ ACID（数据库）│ BASE（分布式）│             │
│  ├──────────┼──────────────┼──────────────┤             │
│  │ 一致性    │ 强一致        │ 最终一致      │             │
│  │ 可用性    │ 单机可用      │ 基本可用      │             │
│  │ 状态      │ 硬状态        │ 软状态        │             │
│  │ 延迟      │ 无延迟        │ 有延迟窗口    │             │
│  │ 适用      │ 单库事务      │ 分布式系统    │             │
│  │ 典型      │ MySQL InnoDB │ Redis/Cassandra│             │
│  └──────────┴──────────────┴──────────────┘             │
└──────────────────────────────────────────────────────────┘
```

### 8.2 最终一致性的五种变体

```
┌──────────────────────────────────────────────────────────┐
│          最终一致性的五种变体（由弱到强）                    │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  1. 弱一致性（Weak Consistency）                          │
│     写入后不保证什么时候能读到，但最终会读到               │
│     例：DNS更新（可能几小时才生效）                        │
│                                                          │
│  2. 因果一致性（Causal Consistency）                      │
│     有因果关系的写操作顺序一致                             │
│     例：A评论了帖子 → B回复了A → 其他用户看到B的回复时    │
│     必定能看到A的评论                                     │
│                                                          │
│  3. 读己之写（Read Your Writes）                          │
│     自己写的数据自己一定能读到最新值                       │
│     例：用户修改头像 → 自己看到新头像 → 他人可能延迟看到  │
│                                                          │
│  4. 单调读（Monotonic Read）                              │
│     一个用户不会读到比之前更旧的数据                       │
│     例：不会出现第一次读到新数据第二次读到旧数据           │
│     实现：用户总是读同一个从库                             │
│                                                          │
│  5. 单调写（Monotonic Write）                             │
│     同一用户的写操作顺序一致                               │
│     例：先发朋友圈再删 → 不会出现删了再发的顺序            │
│                                                          │
│  ┌──────────────────────────────────────────┐           │
│  │  弱 ←────────────────────────────→ 强     │           │
│  │  弱一致性 因果一致性 读己之写 单调读 单调写 │           │
│  └──────────────────────────────────────────┘           │
│                                                          │
│  面试回答：                                               │
│  "最终一致性不是一种，而是从弱到强的五种变体               │
│   大多数互联网系统选择因果一致性或读己之写                 │
│   只有金融等强一致场景才需要线性一致性（Linearizability）  │"
└──────────────────────────────────────────────────────────┘
```

### 8.3 BASE在分布式系统中的实现方式

```
┌──────────────────────────────────────────────────────────┐
│          BASE的实现方式                                    │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  1. 异步复制（MySQL主从）                                 │
│     Master写入 → 异步发送Binlog → Slave应用              │
│     延迟：毫秒~秒级                                      │
│     风险：Master宕机 → Slave可能丢失数据                 │
│                                                          │
│  2. 半同步复制（MySQL半同步）                             │
│     Master写入 → 至少1个Slave确认 → Master返回成功       │
│     延迟：毫秒级                                         │
│     折衷：比纯异步更可靠，比全同步更高效                   │
│                                                          │
│  3. MQ异步（本地消息表）                                  │
│     本地事务写业务数据+消息表 → MQ发送 → 消费者处理       │
│     延迟：秒级                                           │
│     优势：本地事务保证，MQ保证最终送达                    │
│                                                          │
│  4. 定时补偿（补偿事务）                                  │
│     定时扫描未完成的消息 → 重试/补偿                      │
│     延迟：分钟级                                         │
│     兜底：即使MQ丢失也能最终完成                          │
│                                                          │
│  5. 读写分离（Redis/MySQL）                               │
│     写走主 → 读走从 → 主从异步同步                       │
│     延迟：毫秒级                                         │
│     适用：读多写少场景                                    │
│                                                          │
│  6. 缓存更新策略                                         │
│     Cache-Aside：先更新DB → 再删缓存 → 下次读时重建      │
│     延迟：毫秒级                                         │
│     短暂不一致：删缓存后~重建前可能有旧数据               │
└──────────────────────────────────────────────────────────┘
```

### 8.4 CAP与BASE的关系

```
┌──────────────────────────────────────────────────────────┐
│          CAP与BASE的关系                                   │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  CAP是理论：                                              │
│  - 告诉你分布式系统中C和A不能同时满足                     │
│  - 是一个不可能三角                                       │
│                                                          │
│  BASE是实践：                                             │
│  - 告诉你如何在选择AP后尽量保证一致性                     │
│  - 是CAP的工程化妥协                                     │
│                                                          │
│  关系：                                                   │
│  CAP选择了AP → 牺牲强一致 → BASE用最终一致来弥补          │
│  → 不是完全不管一致性，而是"最终"会一致                    │
│                                                          │
│  ┌──────────────────────────────────────────┐           │
│  │            理论层面                        │           │
│  │    CAP：AP系统不能保证强一致性              │           │
│  │         ↓                                  │           │
│  │            实践层面                        │           │
│  │    BASE：但可以用最终一致性来弥补           │           │
│  │         ↓                                  │           │
│  │            实现层面                        │           │
│  │    具体方案：MQ/异步复制/补偿事务           │           │
│  └──────────────────────────────────────────┘           │
│                                                          │
│  面试回答：                                               │
│  "CAP告诉我分布式系统不可能同时满足强一致和高可用          │
│   BASE告诉我选择AP后可以通过最终一致性来弥补               │
│   实际中绝大多数互联网系统选择AP+最终一致                  │
│   只有金融等关键场景才选择CP+强一致                       │
│   而且同一个系统中不同模块可以有不同的CAP选择              │"
└──────────────────────────────────────────────────────────┘
```

---

---

# 第三篇：一致性哈希

## 第九章 一致性哈希原理

### 9.1 为什么需要一致性哈希

```
┌──────────────────────────────────────────────────────────┐
│          传统哈希的问题                                    │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  传统取模哈希：                                           │
│  节点编号 = hash(key) % N                                │
│                                                          │
│  问题：扩缩容时数据大量迁移                               │
│                                                          │
│  示例：3节点 → 4节点扩容                                  │
│                                                          │
│  3节点时：                                                │
│  hash("A") % 3 = 0 → node0                              │
│  hash("B") % 3 = 1 → node1                              │
│  hash("C") % 3 = 2 → node2                              │
│  hash("D") % 3 = 0 → node0                              │
│                                                          │
│  4节点时：                                                │
│  hash("A") % 4 = 0 → node0 (不变 ✓)                    │
│  hash("B") % 4 = 1 → node1 (不变 ✓)                    │
│  hash("C") % 4 = 2 → node2 (不变 ✓)                    │
│  hash("D") % 4 = 0 → node0 (变了! 原来node0，现在还是?) │
│  hash("E") % 4 = 1 → node1                              │
│                                                          │
│  实际迁移量：                                             │
│  3→4节点：约75%的数据需要重新映射                         │
│  4→5节点：约80%的数据需要重新映射                         │
│  N→N+1节点：约(N-1)/N的数据需要迁移                      │
│                                                          │
│  一致性哈希解决：                                         │
│  N→N+1节点：只约1/N的数据需要迁移                         │
│  3→4节点：只约25%迁移（vs 传统75%）                      │
└──────────────────────────────────────────────────────────┘
```

### 9.2 一致性哈希算法原理

```
┌──────────────────────────────────────────────────────────┐
│          一致性哈希算法                                    │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  核心思想：                                               │
│  1. 将整个哈希值空间组织成一个虚拟圆环（哈希环）          │
│     空间大小：0 ~ 2^32-1（MD5取前32bit）                  │
│                                                          │
│  2. 将节点映射到哈希环上                                  │
│     node位置 = hash(nodeIP/名称)                          │
│                                                          │
│  3. 将数据映射到哈希环上                                  │
│     data位置 = hash(key)                                  │
│                                                          │
│  4. 数据归属：顺时针方向最近的节点                        │
│     从data位置顺时针找 → 第一个遇到的节点就是归属节点     │
│                                                          │
│  哈希环示例：                                             │
│                                                          │
│          0/2^32                                          │
│        ┌─────┐                                           │
│   node2│     │                                           │
│  ○     │     │ node0                                     │
│        │  ○  │                                           │
│  ──────┘    └────── 环                                │
│        ○    ○                                            │
│   data_A  node1                                          │
│                                                          │
│  data_A顺时针 → node0 → 归属node0                       │
│                                                          │
│  扩缩容影响：                                             │
│  新增node3 → 只影响node3逆时针到node3之间的数据          │
│  → 即node3接管了原来属于node0的部分数据                  │
│  → 其他节点数据不受影响！                                 │
└──────────────────────────────────────────────────────────┘
```

### 9.3 一致性哈希扩缩容分析

```
┌──────────────────────────────────────────────────────────┐
│          一致性哈希扩容 vs 传统哈希扩容                     │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  场景：3节点 → 4节点扩容                                  │
│                                                          │
│  传统哈希（取模）：                                       │
│  ┌──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐│
│  │ key1 │ key2 │ key3 │ key4 │ key5 │ key6 │ key7 │ key8 ││
│  │ →n1  │ →n2  │ →n0  │ →n1  │ →n2  │ →n0  │ →n1  │ →n2 ││
│  │ 3节点│ 3节点│ 3节点│ 3节点│ 3节点│ 3节点│ 3节点│ 3节点││
│  │ →n1  │ →n2  │ →n3  │ →n0  │ →n1  │ →n2  │ →n3  │ →n0 ││
│  │ 4节点│ 4节点│ 4节点│ 4节点│ 4节点│ 4节点│ 4节点│ 4节点││
│  │ 迁移 │ 迁移 │ 迁移 │ 迁移 │ 迁移 │ 迁移 │ 迁移 │ 迁移 ││
│  └──75%迁移──────────────────────────────────────────┘ │
│                                                          │
│  一致性哈希：                                             │
│  新增node3只接管node0和node3之间的数据                     │
│  ┌──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐│
│  │ key1 │ key2 │ key3 │ key4 │ key5 │ key6 │ key7 │ key8 ││
│  │ →n0  │ →n0  │ →n1  │ →n1  │ →n2  │ →n2  │ →n0  │ →n1 ││
│  │ 3节点│ 3节点│ 3节点│ 3节点│ 3节点│ 3节点│ 3节点│ 3节点││
│  │ →n0  │ →n3  │ →n1  │ →n1  │ →n2  │ →n2  │ →n0  │ →n1 ││
│  │ 4节点│ 4节点│ 4节点│ 4节点│ 4节点│ 4节点│ 4节点│ 4节点││
│  │ 不变 │ 迁移 │ 不变 │ 不变 │ 不变 │ 不变 │ 不变 │ 不变 ││
│  └──12.5%迁移（≈1/N）───────────────────────────────┘ │
│                                                          │
│  结论：                                                   │
│  一致性哈希扩容迁移量 ≈ 1/N                               │
│  传统哈希扩容迁移量 ≈ (N-1)/N                             │
│  N=4时：一致性12.5% vs 传统75%                           │
│  N=100时：一致性1% vs 传统99%                            │
└──────────────────────────────────────────────────────────┘
```

### 9.4 数据倾斜问题

```
┌──────────────────────────────────────────────────────────┐
│          一致性哈希的数据倾斜问题                          │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  问题：节点少时，数据分布可能严重不均匀                    │
│                                                          │
│  只有3节点时：                                            │
│                                                          │
│          0                                               │
│        ┌───┐                                             │
│        │   │                                             │
│  node0○│   │                                             │
│        │   │                                             │
│  node1○───○node2                                         │
│                                                          │
│  node0覆盖范围：0→node1（很大！）                        │
│  node1覆盖范围：node1→node2（很小）                     │
│  node2覆盖范围：node2→0（中等）                          │
│                                                          │
│  → node0承担70%数据，node1承担10%，node2承担20%          │
│  → 严重倾斜！                                            │
│                                                          │
│  根本原因：                                               │
│  节点位置由hash(nodeIP)决定                               │
│  节点少 → 位置分布不均匀 → 各节点覆盖范围差异大           │
│                                                          │
│  解决方案：虚拟节点（见第十章）                            │
└──────────────────────────────────────────────────────────┘
```

---

## 第十章 虚拟节点与数据倾斜解决

### 10.1 虚拟节点原理

```
┌──────────────────────────────────────────────────────────┐
│          虚拟节点原理                                     │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  核心思路：                                               │
│  每个真实节点在哈希环上对应多个虚拟节点                    │
│  虚拟节点均匀分布在环上 → 数据分布自然均匀                │
│                                                          │
│  示例：3个真实节点，每个节点100个虚拟节点                  │
│                                                          │
│  node0 → v0_0, v0_1, v0_2, ..., v0_99                   │
│  node1 → v1_0, v1_1, v1_2, ..., v1_99                   │
│  node2 → v2_0, v2_1, v2_2, ..., v2_99                   │
│                                                          │
│  哈希环上300个虚拟节点 → 分布更均匀                      │
│                                                          │
│  数据路由：                                               │
│  hash(key) → 顺时针找虚拟节点 → 找到真实节点              │
│                                                          │
│  ┌──────────────────────────────────────┐               │
│  │        哈希环（300个虚拟节点）         │               │
│  │                                        │               │
│  │  v0_3  v1_5  v2_7  v0_15  v1_20  v2_23│               │
│  │   ○     ○     ○    ○      ○      ○   │               │
│  │  ...均匀分布...                       │               │
│  │                                        │               │
│  │  虚拟节点分布统计：                    │               │
│  │  node0: 100个虚拟节点 → 覆盖≈33%      │               │
│  │  node1: 100个虚拟节点 → 覆盖≈33%      │               │
│  │  node2: 100个虚拟节点 → 覆盖≈33%      │               │
│  │  → 数据分布接近均匀                    │               │
│  └──────────────────────────────────────┘               │
│                                                          │
│  虚拟节点数量选择：                                       │
│  - 经验值：每个真实节点 100~200 个虚拟节点                │
│  - 节点越多 → 虚拟节点可以少一点                          │
│  - 节点越少 → 虚拟节点需要多一些                          │
│  - 3个节点 → 150虚拟节点/真实节点                        │
│  - 10个节点 → 100虚拟节点/真实节点                       │
│  - 100个节点 → 50虚拟节点/真实节点                       │
└──────────────────────────────────────────────────────────┘
```

### 10.2 一致性哈希实现（含虚拟节点）

```java
/**
 * 一致性哈希实现（含虚拟节点）
 */
public class ConsistentHashing {

    // 哈希环：SortedMap有序，便于顺时针查找
    private final SortedMap<Long, String> hashRing = new TreeMap<>();

    // 每个真实节点的虚拟节点数量
    private final int virtualNodeCount;

    // 哈希函数
    private final HashFunction hashFunction;

    public ConsistentHashing(int virtualNodeCount, Collection<String> nodes) {
        this.virtualNodeCount = virtualNodeCount;
        this.hashFunction = new MD5HashFunction();
        for (String node : nodes) {
            addNode(node);
        }
    }

    /**
     * 添加节点：为每个真实节点创建N个虚拟节点
     */
    public void addNode(String node) {
        for (int i = 0; i < virtualNodeCount; i++) {
            // 虚拟节点名称：node#0, node#1, ..., node#N-1
            String virtualNodeName = node + "#" + i;
            long hash = hashFunction.hash(virtualNodeName);
            hashRing.put(hash, node); // 虚拟节点映射到真实节点
        }
    }

    /**
     * 移除节点：删除所有虚拟节点
     */
    public void removeNode(String node) {
        for (int i = 0; i < virtualNodeCount; i++) {
            String virtualNodeName = node + "#" + i;
            long hash = hashFunction.hash(virtualNodeName);
            hashRing.remove(hash);
        }
    }

    /**
     * 获取数据归属节点：顺时针查找
     */
    public String getNode(String key) {
        if (hashRing.isEmpty()) {
            return null;
        }

        long hash = hashFunction.hash(key);

        // 顺时针查找：tailMap返回大于hash的部分
        SortedMap<Long, String> tailMap = hashRing.tailMap(hash);

        // 如果tailMap为空 → 从环的起点（0）开始找
        long nodeHash = tailMap.isEmpty() ? hashRing.firstKey() : tailMap.firstKey();

        return hashRing.get(nodeHash);
    }

    /**
     * MD5哈希函数（比String.hashCode分布更均匀）
     */
    private static class MD5HashFunction implements HashFunction {
        @Override
        public long hash(String key) {
            byte[] digest = DigestUtils.md5(key.getBytes());
            // 取MD5前4字节（32bit）作为哈希值
            long h = 0;
            for (int i = 0; i < 4; i++) {
                h <<= 8;
                h |= (digest[i] & 0xFF);
            }
            return h & 0xFFFFFFFFL; // 保证正数
        }
    }
}
```

### 10.3 虚拟节点数量与数据均匀性

```
┌──────────────────────────────────────────────────────────┐
│          虚拟节点数量对数据均匀性的影响                     │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  实验：3个节点，100万条数据，不同虚拟节点数量              │
│                                                          │
│  虚拟节点=0（无虚拟节点）：                               │
│  node0: 72万  node1: 8万  node2: 20万  → 极不均匀       │
│                                                          │
│  虚拟节点=10：                                           │
│  node0: 45万  node1: 28万  node2: 27万  → 仍偏斜        │
│                                                          │
│  虚拟节点=50：                                           │
│  node0: 35万  node1: 33万  node2: 32万  → 较均匀        │
│                                                          │
│  虚拟节点=100：                                          │
│  node0: 33.5万 node1: 33.2万 node2: 33.3万 → 很均匀    │
│                                                          │
│  虚拟节点=200：                                          │
│  node0: 33.34万 node1: 33.33万 node2: 33.33万 → 极均匀 │
│                                                          │
│  结论：                                                   │
│  - 虚拟节点越多 → 数据分布越均匀                         │
│  - 100~200个虚拟节点足够均匀                             │
│  - 但虚拟节点过多 → 内存占用增加 + 路由查找变慢           │
│  - 实际选择100~150个虚拟节点                             │
│                                                          │
│  经验公式：                                               │
│  virtualNodeCount = max(100, totalNodes * 20)             │
└──────────────────────────────────────────────────────────┘
```

---

## 第十一章 一致性哈希的应用场景

### 11.1 分布式缓存路由

```
┌──────────────────────────────────────────────────────────┐
│          分布式缓存路由（Memcached/Redis集群）             │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  场景：多个Redis节点组成缓存集群                          │
│  - 传统取模：3节点 → 4节点 → 75%缓存失效（缓存雪崩！）   │
│  - 一致性哈希：3节点 → 4节点 → 只25%缓存失效             │
│                                                          │
│  缓存失效对比：                                           │
│  ┌──────────┬──────────────────┬──────────────────────┐ │
│  │ 扩容方式 │ 传统取模失效比例  │ 一致性哈希失效比例   │ │
│  ├──────────┼──────────────────┼──────────────────────┤ │
│  │ 3→4节点  │ 75%              │ ~25%                │ │
│  │ 4→5节点  │ 80%              │ ~20%                │ │
│  │ 10→11节点│ 90%              │ ~10%                │ │
│  │ 100→101 │ 99%              │ ~1%                 │ │
│  └──────────┴──────────────────┴──────────────────────┘ │
│                                                          │
│  ⚠️ 缓存雪崩：传统取模扩容 → 大量缓存瞬间失效            │
│     → 请求全部涌向DB → DB被打垮 → 系统崩溃               │
│                                                          │
│  一致性哈希扩容 → 只小部分缓存失效 → 不会雪崩             │
│                                                          │
│  Memcached客户端（如SpyMemcached/XMemcached）             │
│  默认使用一致性哈希 + Ketama算法（虚拟节点）              │
└──────────────────────────────────────────────────────────┘
```

### 11.2 分布式存储路由

```
┌──────────────────────────────────────────────────────────┐
│          分布式存储路由                                    │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  1. Cassandra：                                          │
│     - 一致性哈希 + 虚拟节点（Token）                     │
│     - 每个节点256个Token → 数据均匀分布                  │
│     - 扩缩容只影响相邻Token → 迁移量小                   │
│                                                          │
│  2. DynamoDB（Amazon）：                                  │
│     - 一致性哈希 + 分区（Partition）                     │
│     - 每个分区有自己的哈希范围                            │
│     - 扩容自动重新分配分区                                │
│                                                          │
│  3. Riak：                                               │
│     - 一致性哈希 + vnode（虚拟节点）                     │
│     - 默认每个节点64个vnode                              │
│                                                          │
│  4. Swift（OpenStack对象存储）：                          │
│     - 一致性哈希 + 环（Ring）                            │
│     - 3副本：数据在环上顺时针3个节点                      │
│                                                          │
│  共同设计模式：                                           │
│  ┌──────────┬────────────┬──────────────┐              │
│  │ 系统      │ 虚拟节点    │ 虚拟节点数量  │              │
│  ├──────────┼────────────┼──────────────┤              │
│  │ Cassandra│ Token      │ 256/节点     │              │
│  │ DynamoDB │ Partition  │ 动态分配     │              │
│  │ Riak     │ vnode      │ 64/节点      │              │
│  │ Swift    │ Ring       │ 可配置       │              │
│  └──────────┴────────────┴──────────────┘              │
└──────────────────────────────────────────────────────────┘
```

### 11.3 分库分表路由

```
┌──────────────────────────────────────────────────────────┐
│          分库分表路由（一致性哈希版）                       │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ShardingSphere一致性哈希分片算法：                       │
│                                                          │
│  spring:                                                 │
│    shardingsphere:                                       │
│      rules:                                              │
│        sharding:                                         │
│          sharding-algorithms:                            │
│            consistent-hash:                              │
│              type: CONSISTENT_HASH                       │
│              props:                                      │
│                sharding-count: 4                         │
│                                                          │
│  与取模分片对比：                                         │
│                                                          │
│  取模分片：                                               │
│  - 数据分布严格均匀                                      │
│  - 扩容迁移量大（75%）                                   │
│  - 适合：分片数量固定                                    │
│                                                          │
│  一致性哈希分片：                                         │
│  - 数据分布接近均匀（虚拟节点保证）                       │
│  - 扩容迁移量小（25%）                                   │
│  - 适合：需要频繁扩容                                    │
│                                                          │
│  选择建议：                                               │
│  - 分片数量确定不变 → 取模（更均匀）                      │
│  - 可能扩容 → 一致性哈希（迁移少）                       │
│  - 数据量极大（百亿）→ 一致性哈希 + 虚拟节点             │
└──────────────────────────────────────────────────────────┘
```

### 11.4 负载均衡路由

```
┌──────────────────────────────────────────────────────────┐
│          负载均衡路由                                     │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  Nginx一致性哈希负载均衡：                               │
│                                                          │
│  upstream backend {                                      │
│      hash $request_uri consistent;  # 按URL一致性哈希    │
│      server 192.168.1.1:8080;                           │
│      server 192.168.1.2:8080;                           │
│      server 192.168.1.3:8080;                           │
│  }                                                       │
│                                                          │
│  效果：                                                   │
│  - 同一URL的请求始终路由到同一后端                        │
│  - 后端本地缓存利用率高（相同请求命中相同缓存）          │
│  - 扩缩容时只影响部分URL → 缓存不大量失效               │
│                                                          │
│  适用场景：                                               │
│  - 有本地缓存的场景（如CDN边缘节点）                     │
│  - Session保持（同一用户路由到同一服务器）                │
│  - WebSocket长连接保持                                   │
└──────────────────────────────────────────────────────────┘
```

---

## 第十二章 一致性哈希的数据迁移

### 12.1 扩容迁移流程

```
┌──────────────────────────────────────────────────────────┐
│          一致性哈希扩容迁移流程                            │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  步骤（新增node3）：                                      │
│                                                          │
│  1. 计算新节点位置                                        │
│     hash(node3) → 确定node3在环上的位置                   │
│     + 所有虚拟节点的位置                                  │
│                                                          │
│  2. 识别需要迁移的数据                                   │
│     node3逆时针到node3之间的数据                          │
│     → 原来属于node0 → 现在属于node3                     │
│                                                          │
│  3. 数据迁移                                              │
│     从node0复制数据到node3                                │
│     → 只迁移属于node3范围的数据                          │
│                                                          │
│  4. 路由规则更新                                         │
│     将node3及其虚拟节点加入哈希环                        │
│     → 新请求路由到node3                                  │
│                                                          │
│  5. 验证数据一致性                                       │
│     校验node3数据正确                                    │
│                                                          │
│  6. 清理旧数据                                           │
│     删除node0中已迁移到node3的数据                       │
│                                                          │
│  关键：                                                   │
│  - 步骤3和4可以并行（双写阶段）                          │
│  - 步骤6可以延迟（旧数据不影响正确性）                    │
│  - 整个过程可以不停服                                    │
└──────────────────────────────────────────────────────────┘
```

### 12.2 缩容迁移流程

```
┌──────────────────────────────────────────────────────────┐
│          一致性哈希缩容迁移流程                            │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  步骤（移除node2）：                                      │
│                                                          │
│  1. 识别需要迁移的数据                                   │
│     node2上的所有数据 → 迁移到顺时针下一个节点node0       │
│                                                          │
│  2. 数据迁移                                              │
│     从node2复制数据到node0                                │
│                                                          │
│  3. 路由规则更新                                         │
│     从哈希环移除node2及其虚拟节点                        │
│                                                          │
│  4. 验证                                                 │
│     校验node0数据正确                                    │
│                                                          │
│  5. node2下线                                            │
│                                                          │
│  迁移量：                                                 │
│  只迁移node2的数据 → 约1/N的数据量                      │
│                                                          │
│  ⚠️ 缩容风险：                                           │
│  - node2上的数据必须完全迁移完再下线                     │
│  - 否则会丢数据                                          │
│  - 建议：先标记node2只读 → 迁移 → 再下线                │
└──────────────────────────────────────────────────────────┘
```

### 12.3 平滑迁移方案（不停服）

```
┌──────────────────────────────────────────────────────────┐
│          一致性哈希平滑迁移（不停服）                      │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  双写 + 灰度切换方案：                                   │
│                                                          │
│  Phase 1: 双写                                           │
│  - 新写入同时写旧节点和新节点                            │
│  - 读仍从旧节点读                                       │
│                                                          │
│  Phase 2: 历史迁移                                       │
│  - 从旧节点迁移历史数据到新节点                          │
│  - 迁移只涉及受影响范围的数据                            │
│                                                          │
│  Phase 3: 切读                                           │
│  - 读从新节点读                                         │
│  - 写仍双写                                             │
│                                                          │
│  Phase 4: 去双写                                         │
│  - 写只写新节点                                         │
│                                                          │
│  Phase 5: 清理                                           │
│  - 删除旧节点已迁移数据                                  │
│                                                          │
│  每步都可回滚，灰度切换逐步放量                          │
│  与分库分表扩容方案类似，只是迁移量更小                   │
└──────────────────────────────────────────────────────────┘
```

---

## 第十三章 三大理论综合对比与应用

### 13.1 三大理论关系图

```
┌──────────────────────────────────────────────────────────┐
│          三大理论关系                                      │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  分库分表 ── 实践层面（怎么做）                           │
│     │ 解决单库单表性能瓶颈                               │
│     │ 核心决策：分片键 + 路由算法                        │
│     │                                                   │
│     ├── 路由算法选择 → 一致性哈希                        │
│     │   │ 减少扩缩容时的数据迁移量                      │
│     │   │                                               │
│     │   └── 一致性哈希 ── 算法层面（怎么路由）           │
│     │       │ 数据均匀分布 + 扩缩容友好                 │
│     │       │ 虚拟节点解决倾斜                          │
│     │                                                   │
│     ├── 一致性保障 → CAP/BASE                            │
│     │   │                                               │
│     │   └── CAP ── 理论层面（为什么不可能）              │
│     │       │ 分布式不可能三角                           │
│     │       │                                           │
│     │       └── BASE ── 实践层面（怎么妥协）             │
│     │           │ AP + 最终一致性                        │
│     │           │ 允许短暂不一致                        │
│                                                          │
│  三者层次：                                               │
│  ┌──────────────────────────────────────┐               │
│  │ 理论：CAP → 分布式系统不可能三角       │               │
│  │ 妥协：BASE → AP + 最终一致性           │               │
│  │ 算法：一致性哈希 → 扩缩容友好路由      │               │
│  │ 实践：分库分表 → 具体拆分方案          │               │
│  └──────────────────────────────────────┘               │
└──────────────────────────────────────────────────────────┘
```

### 13.2 一致性哈希 vs 取模哈希 vs 范围分片

| 维度 | 取模哈希 | 范围分片 | 一致性哈希 |
|------|---------|---------|-----------|
| 数据均匀性 | 严格均匀 | 可能倾斜 | 接近均匀(虚拟节点) |
| 扩容迁移量 | 70-80% | 不需要迁移 | ~1/N(~25%) |
| 缩容迁移量 | 70-80% | 不需要迁移 | ~1/N |
| 范围查询 | 需跨分片 | 同分片友好 | 需跨分片 |
| 精确查询 | 单分片 | 可能跨分片 | 单分片 |
| 实现复杂度 | 简单 | 简单 | 中等(需虚拟节点) |
| 扩缩容频率 | 固定不分片 | 适合扩展 | 适合频繁调整 |
| 适用场景 | 分片数固定 | 时间序列数据 | 频繁扩缩容 |

### 13.3 分库分表CAP选择

```
┌──────────────────────────────────────────────────────────┐
│          分库分表场景下的CAP选择                           │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  分库分表后的新问题：                                     │
│  - 数据分散在不同库 → 跨库一致性保障                     │
│  - 主从同步延迟 → 读写分离的一致性选择                   │
│                                                          │
│  场景1：订单查询（读己之写）                              │
│  - 用户刚下单 → 立即查询 → 主从可能还没同步              │
│  - 选择：关键查询走主库 → CP倾向                        │
│  - 实现：ShardingSphere hint强制路由主库                  │
│                                                          │
│  场景2：报表统计（最终一致）                              │
│  - 从库延迟几秒完全可以接受                               │
│  - 选择：读从库 → AP倾向                                │
│  - 实现：ShardingSphere默认读写分离                     │
│                                                          │
│  场景3：跨库事务                                          │
│  - 不同库的事务无法直接保证一致性                         │
│  - 选择：强一致 → 2PC/XA → CP                          │
│  - 选择：最终一致 → MQ → AP                             │
│                                                          │
│  关键理解：                                               │
│  同一个系统不同操作可以有不同的CAP选择                    │
│  - 写操作/关键读 → CP（走主库）                         │
│  - 普通读/统计 → AP（走从库）                           │
│  - 跨库事务 → 根据业务需要选CP或AP                      │
└──────────────────────────────────────────────────────────┘
```

---

## 第十四章 面试高频10题

### Q1：什么时候需要分库分表？

> 当单表数据超过500万行、单库QPS超过5000、或单库连接数接近上限时考虑分库分表。先做索引优化、读写分离等简单方案，效果不够时再分库分表。分库分表是最后的手段，引入后会增加跨库查询、分布式事务、扩容迁移等复杂问题。

### Q2：分片键怎么选？

> 三原则：①数据均匀分布（避免倾斜）②查询尽量落到单分片（避免跨库）③业务核心维度（最常用的查询条件）。订单选user_id（用户查自己的订单），日志选create_time（按时间查），商品选product_id。避免用auto_increment、状态字段、纯日期字段。

### Q3：分库分表后如何做跨库JOIN？

> 四种方案：①绑定表（主子表同分片键，JOIN自然在同一分片）②广播表（小表全量复制到每个分片）③全局表（类似广播表）④应用层组装（分别查各库，代码中JOIN）。最推荐绑定表+广播表方案，应用层组装适合非频繁的跨库查询。

### Q4：分库分表后如何做跨库分页？

> 最难的问题。四种方案：①禁止深分页（只提供下一页游标分页）②二次查询法（先查范围边界再精确查）③全局索引表（不分片的索引表辅助定位）④ES辅助（同步到ES做全局排序分页）。最推荐游标分页+ES辅助方案。

### Q5：CAP定理是什么？为什么CA不存在？

> CAP：一致性C、可用性A、分区容忍性P，只能同时满足两个。CA不存在因为网络分区是必然的（网络延迟、断网是客观现实），分区发生时必须在C和A之间做选择：CP牺牲可用性保证一致性，AP牺牲一致性保证可用性。

### Q6：BASE理论是什么？和CAP的关系？

> BASE是CAP的工程化妥协：BA基本可用（降级而非不可用）、S软状态（允许中间状态）、E最终一致性（延迟后一致）。关系：CAP选择了AP → 牺牲强一致 → BASE用最终一致性弥补。不是完全不管一致性，而是"最终"会一致。

### Q7：一致性哈希是什么？解决了什么问题？

> 将哈希空间组织成环，数据顺时针找最近的节点。解决传统取模哈希扩缩容时数据大量迁移的问题：取模扩容迁移70-80%数据，一致性哈希只迁移约1/N数据。新增节点只影响相邻节点范围内的数据。

### Q8：一致性哈希的数据倾斜怎么解决？

> 虚拟节点：每个真实节点在哈希环上对应100-200个虚拟节点。虚拟节点均匀分布在环上 → 数据分布自然均匀。3个真实节点+300虚拟节点 → 数据分布接近33%/33%/33%。虚拟节点越多越均匀，但过多会增加内存和查找开销，通常100-150个。

### Q9：分布式ID生成方案有哪些？推荐哪个？

> 七种方案：UUID（无序低效）、DB自增（性能瓶颈）、DB号段（减少访问）、Redis INCR（持久化风险）、Snowflake（推荐）、美团Leaf（号段+雪花双模式）、百度Uid（RingBuffer预生成）。推荐Snowflake：有序、高性能、无外部依赖、单机400万/秒。时钟回拨是唯一风险，小幅回拨可sleep等待。

### Q10：分库分表扩容怎么做？

> 推荐成倍扩容法：每次翻倍（4→8→16），旧数据分布规则不变，只迁移50%数据。实操：新建空库 → 复制一半数据到新库 → 验证 → 切路由规则 → 删除旧库已迁移数据。不停服方案：双写→历史迁移→切读→去双写→清理，每步可回滚。一致性哈希扩容更优：只迁移约1/N数据。

---

## 附录：核心概念速查表

| 概念 | 类别 | 核心要点 |
|------|------|---------|
| 垂直分库 | 分库分表 | 按业务拆分数据库，高内聚低耦合 |
| 垂直分表 | 分库分表 | 按字段频率拆分热表+冷表 |
| 水平分库分表 | 分库分表 | 按分片键将数据分散到多个分片 |
| 分片键 | 分库分表 | 最关键设计决策，决定数据分布和查询效率 |
| 取模哈希 | 路由算法 | 均匀但扩容迁移量大 |
| 范围分片 | 路由算法 | 扩容方便但可能数据倾斜 |
| 一致性哈希 | 路由算法 | 扩缩容迁移量小 |
| 绑定表 | 分库分表 | 主子表同分片键，JOIN不跨库 |
| 广播表 | 分库分表 | 小表全量复制，JOIN本地完成 |
| Snowflake | 分布式ID | 时间+机器+序列，有序高性能 |
| ShardingSphere | 分库分表中间件 | JDBC嵌入式/Proxy代理式 |
| CAP | 理论 | 一致性+可用性+分区容忍，三选二 |
| CP | CAP选择 | 一致性优先，分区时牺牲可用性 |
| AP | CAP选择 | 可用性优先，分区时牺牲一致性 |
| CA | CAP选择 | 理论不存在（分区必然发生） |
| BASE | 理论 | 基本可用+软状态+最终一致性 |
| 最终一致性 | BASE变体 | 延迟后保证一致，有5种变体 |
| 一致性哈希环 | 算法 | 0~2^32-1虚拟圆环 |
| 虚拟节点 | 算法 | 每真实节点100-200虚拟节点 |
| Ketama | 算法 | Memcached一致性哈希实现 |
| 成倍扩容 | 扩容方案 | 翻倍扩容，只迁移50%数据 |
| 双写方案 | 扩容方案 | 不停服迁移五阶段 |
