|知识点|笔记时重点写什么|
|---|---|
|**RocketMQ 核心概念**|热 Producer（消息生产者）、Consumer（消费者）、Broker（消息存储服务器）、Topic（主题，消息分类）、Tag（标签，Topic 内细分）、Queue（消息队列，Topic 的分区）、Message Queue（实际存储单元）、NameServer（注册中心，管理 Broker 路由）|
|**消息模型**|热 普通消息（点对点/发布订阅）、顺序消息（全局有序/分区有序——同一个 Queue 内 FIFO）、事务消息（半消息 → 本地事务 → 回查/提交/回滚）、延迟消息（18 个等级，不支持任意精度）|
|**消息可靠性保障（三步）**|核 **发送端**：Sync Send + 重试 + `sendResult.getSendStatus()` 确认。**存储端**：同步刷盘 `flushDiskType=SYNC` + 同步复制 `brokerRole=SYNC_MASTER`（主从双写）。**消费端**：手动 ACK（`MessageListenerConcurrently` 默认一条消费成功就 ACK；`MessageListenerOrderly` 保证顺序消费）+ 幂等处理|
|**消息积压处理**|热 排查原因（消费者挂了 / 消费太慢 / 消费报错不停重试）。解决方案：临时扩容 Consumer（增加消费者数量 ≤ Queue 数量）、新建 Topic + 增加队列数做转发消费、只消费重要消息丢弃过期消息|
|**Spring Cloud Stream**|核 消息中间件的编程抽象层。Binder（绑定器，屏蔽 MQ 差异）、Output/Source（输出通道）、Input/Sink（输入通道）。切换 MQ 只换 Binder 不改代码。`@EnableBinding` + `@StreamListener`|
|**死信队列 DLQ**|消费失败的 message 进入死信 Topic。需要在控制台配置死信队列策略。用于后续人工排查或补偿处理|
|**消息幂等性设计**|热 唯一 ID（消息ID / 业务流水号）+ 数据库唯一索引 / Redis SETNX / 分布式锁。**消息队列不保证恰好一次语义，幂等是消费端的责任**|