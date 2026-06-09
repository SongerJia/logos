|序号|知识点|笔记写什么|important|
|---|---|---|---|
|4.1|Push Consumer vs Pull Consumer|DefaultMQPushConsumer（长轮询推送）/ DefaultMQPullConsumer（主动拉取）/ Reactive PushConsumer(RMQ 5.0)；Push底层也是Pull，只是封装了轮询逻辑|🔥🔥🔥 **绝对高频**|
|4.2|负载均衡策略（消费端）|AllocateMessageQueueAveragly（平均分配，默认）/ AveragelyByCircle（环形平均）/ ConsistentHash（一致性哈希）/ Configuration（手动指定）；Rebalance 时分配算法详解|🔥🔥🔥🔥 **高频考点**|
|4.3|Rebalance 机制|触发条件（消费者上下线 / Queue数量变化 / 订阅变化）；Rebalance 流程；Rebalance 过程中消息是否丢失？怎么避免？|🔥🔥🔥🔥 **核心难点**|
|4.4|消息消费模式|集群模式(Clustering，负载均衡，默认)/ 广播模式(Broadcasting，每台都收)；两种模式的Queue分配差异和适用场景|🔥🔥🔥|
|4.5|消息ACK机制|成功消费后返回 ConsumeConcurrentlyStatus.CONSUME_SUCCESS / RECONSUME_LATER；ACK时机（消费完成后才确认）；消费失败的重试策略|🔥🔥🔥🔥 **必须精通**|
|4.6|消息重试机制|重试次数限制（默认16次）/ 重试间隔递增策略（1m/5m/10m...2h）/ 最大重试后进DLQ；并发消费 vs 顺序消费的重试差异|🔥🔥🔥|
|4.7|消息堆积处理|原因分析（消费慢/消费者宕机/Broker满载）；排查命令（consumerProgress / consumerConnection）；解决方案（扩消费者/跳过非关键消息/临时新建消费组赶进度）|🔥🔥🔥 **实战高频题**|