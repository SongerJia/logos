|序号|知识点|笔记写什么|重要度|
|---|---|---|---|
|4.1|消费者组重平衡(Rebalance)|触发条件：CG 成员变化 / Topic Partition 数变化 / 订阅 Topic 变化；Rebalance 期间的 Stop-the-world（所有消费者停227ms~几秒）；如何避免频繁 Rebalance（心跳 timeout 调优 / 静态成员 Static Membership）|🔥🔥🔥🔥 **超级高频**|
|4.2|分区分配策略(Partition Assignment)|RangeAssignor（按范围，默认，可能不平衡）/ RoundRobinAssignor（轮询，均匀）/ StickyAssignor（尽量保持原有分配，减少Rebalance开销）/ CooperativeStickyAssignor（增量Rebalance，Kafka 2.4+ 推荐）|🔥🔥🔥|
|4.3|位移(Offset)管理|消费者自己维护 offset（存在内部 Topic `__consumer_offsets`）；自动提交(auto.commit.enable) vs 手动提交(commitSync/commitAsync)；**为什么自动提交可能丢消息或重复消费**|🔥🔥🔥🔥 **必考**|
|4.4|消费语义保证|At-Most-Once（最多一次：先提交再处理）/ At-Least-Once（至少一次：先处理再提交，默认，会重复）/ Exactly-Once（精确一次：需要事务消息或幂等消费）|🔥🔥🔥🔥|
|4.5|消费者拉取模型(Poll)|consumer.poll(Duration)；一次 poll 返回一批消息（max.poll.records）；poll 间隔超时(max.poll.interval.ms) → 被踢出CG触发Rebalance|核|
|4.6|独立消费者(Standalone Consumer)|不需要 CG，直接 assign(Collection) + seek() 指定 offset；适用场景：广播 / 精准控制每个Partition的消费进度|热|