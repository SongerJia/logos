|序号|知识点|笔记写什么|重要度|
|---|---|---|---|
|7.1|Kafka Streams 核心概念|KStream（每个Key多条记录）/ KTable（每个Key最新值，对应Compacted Topic）/ GlobalKTable（全局部署，用于维表 Join）；流式计算 DSL（map/filter/groupId/reduce/aggregate/windowedBy）|🔥 **加分项**|
|7.2|时间窗口(Windowing)|滚动窗口(Tumbling)/跳跃窗口(Hopping)/滑动窗口(Sliding)/会话窗口(Session)；窗口存储状态（RocksDB 本地状态存储）；延迟事件处理（Grace Period）|热|
|7.3|Kafka Connect 框架|Source Connector（从外部系统导入 Kafka）/ Sink Connector（从 Kafka 导出到外部系统）；常见 Connector（Debezium/MySQL Binlog → Kafka / Kafka → Elasticsearch）；分布式模式 vs 独立模式|热|
|7.4|KSQL(现在的 ksqlDB)|SQL 化流式查询；与 Kafka Streams 的关系（底层就是 Streams）；适用场景和限制|热|