|序号|知识点|笔记写什么|重要度|
|---|---|---|---|
|8.1|Kafka 事务消息|0.11 引入；跨 Partition 原子写入（Producer 端 transactionId + 两阶段提交到 Transaction Coordinator）；isolated.reads.enabled=true 消费端读已提交事务消息；与 RMQ 事务消息的对比|🔥🔥🔥|
|8.2|Exactly-Once 语义(EOS)实现|三种机制组合：① 幂等 Producer（PID+序列号去重）② 事务消息（跨 Partition 原子性）③ 消费者手动提交 + 幂等输出（消费-处理-产出 原子性）；EOS 的性能代价|🔥🔥🔥🔥 **高阶必考**|
|8.3|关键性能参数调优|Producer：batch.size/linger.ms/compression.type；Broker：num.network.threads/num.io.threads/log.flush.interval.messages；Consumer：fetch.min.bytes/fetch.max.bytes/max.poll.records；完整调优清单|🔥🔥|
|8.4|监控指标与常用命令|kafka-topics.sh / kafka-consumer-groups.sh（查看 Lag！）/ kafka-run-class.sh kafka.tools.GetOffsetShell；关键指标：UnderReplicatedPartitions / OfflinePartitionsCount / Consumer Lag / RequestHandlerAvgIdlePercent|🔥🔥🔥 **实战必会**|
|8.5|常见故障排查|消费者 Lag 飙升（消费慢 / 分区不够 / Rebalance 频繁）/ Broker 磁盘满 / Controller 频繁切换 / OOM（堆内存不足或 PageCache 被刷爆）；排查思路|🔥🔥🔥|