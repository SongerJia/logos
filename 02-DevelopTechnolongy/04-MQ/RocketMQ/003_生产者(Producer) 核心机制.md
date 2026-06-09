|序号|知识点|笔记写什么|important|
|---|---|---|---|
|3.1|Producer 类型选择|DefaultMQProducer（普通）/ TransactionMQProducer（事务）/ 同步发送 / 异步发送 / 单向发送(Oneway) 三种发送方式对比|🔥🔥🔥 **必考**|
|3.2|发送消息完整流程|1)获取Topic路由 → 2)选择Queue(轮询/随机/Hash) → 3)构建请求 → 4)发送到Broker → 5)处理响应；画时序图|🔥🔥🔥|
|3.3|Queue 选择策略（负载均衡）|轮询SelectMessageQueueByRoundRobin（默认）/ 随机 / 最小活跃数 / Hash（顺序消息用）；自定义策略场景|核|
|3.4|同步发送 vs 异步发送 vs Oneway|可靠性：同步 > 异步 > Oneway；性能：Oneway > 异步 > 同步；各自适用场景和异常处理差异|🔥🔥🔥|
|3.5|批量发送(Batch)|批量发送条件（同一Topic同一WaitStoreMsgOK）/ 默认大小限制1MB；Splitter 自定义分批逻辑；批量 vs 单条的性能对比数据|热|
|3.6|消息可靠性保障（Producer侧）|SendResult 中 SendStatus（SEND_OK/FLUSH_DISK_TIMEOUT/FLUSH_SLAVE_TIMEOUT/SLAVE_NOT_AVAILABLE）含义；重试次数配置|核|
|3.7|Producer 本地缓存|MQClientInstance 单例（同进程共享）；本地路由表(TopicPublishInfo) 缓存与更新机制；为什么需要本地缓存|热|