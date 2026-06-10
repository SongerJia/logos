Canal 是阿里开源的 MySQL Binlog 增量订阅&消费组件，在**数据同步、缓存失效、搜索索引构建**场景中非常常用。

|#|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|1.1|**Binlog 基础回顾**|🔴 必背|① 三种格式：STATEMENT（记录 SQL）→ ROW（记录行变更，默认）→ MIXED ② Canal 依赖 ROW 格式，因为能精确拿到每行数据的前后镜像 ③ 面试：MySQL 的 binlog 有哪几种格式？各有什么优缺点？|→ MySQL 日志系统（M8）、→ 主从复制原理|
|1.2|**Canal 架构 & 工作原理**|🔴 必背|① Canal Server 伪装成 MySQL Slave → 发送 dump 协议 → Master 推送 Binlog → Server 解析后投递到消息队列/存储 ② 核心组件：Parser（binlog 解析器）→ Sink（过滤&路由）→ Store（存储）③ 面试：Canal 是怎么获取 MySQL 变更数据的？为什么不用定时轮询？|→ MySQL 主从复制协议（相同原理）|
|1.3|**典型场景一：缓存一致性**|🔴 必背|① 问题：更新 DB 后 Redis 缓存怎么同步？方案对比：延时双删 vs 订阅 Binlog ② Canal 方案：DB 更新 → Canal 解析 → 发 MQ → 消费端删/更 Redis ③ 优势：最终一致 + 不侵入业务代码 ④ 面试：Redis 和 MySQL 如何保证缓存一致性？（答出 Canal 方案是亮点）|→ Redis 缓存设计问题、→ RocketMQ/Kafka|
|1.4|**典型场景二：搜索索引同步**|🟡 应掌握|① DB 写入 → Canal 解析 → 同步到 Elasticsearch/MongoDB 构建索引 ② 相比全量同步（定时重建），增量实时性更好 ③ 面试：你们 ES 索引是怎么和 DB 保持同步的？|→ Elasticsearch 写入流程|
|1.5|**HA 高可用部署**|🟡 应掌握|① Canal Server 支持 ZooKeeper 做高可用：多实例 + ZK 选主 ② Instance 分区：多个 Canal Server 可以分担不同的数据库实例 ③ 面试：Canal 挂了怎么办？数据会丢吗？（ZK 协调 + 断点续传 position）|→ S4 ZooKeeper|
|1.6|**Canal Adapter vs Canal Client**|🟢 了解|① **Canal Client**：Java SDK，自己写消费逻辑，灵活性高；② **Canal Adapter**：内置适配器（ES/HBase/Kafka/HDFS），配置即用 ③ 选型：简单场景用 Adapter，需要定制逻辑用 Client|→ Kafka Connect 类比|
|1.7|**数据可靠性保障**|🟡 应掌握|① 位点管理（position）：记录已消费到的 binlog 位置，重启后断点续传 ② 幂等消费：下游消费者需要保证重复处理不产生副作用（如 Redis SET 天然幂等）③ 面试：Canal 消费出现堆积或重复消费怎么办？|→ MQ 消费者幂等处理|
|1.8|**Maxwell / Debezium 对比**|🟢 了解|① Maxwell（Zendesk）：轻量，直接输出 JSON 到 Kafka，适合简单场景 ② Debezium（Red Hat）：CDC 标准，支持多种数据库，基于 Kafka Connect ③ 面试：你们为什么选 Canal 而不是 Debezium？（社区活跃度 / 中文生态 / 成熟度）|→ Kafka Connect|

> **🏗️ 架构追问**：如果让你设计一个「跨机房数据同步」方案，Canal + MQ 够不够？需要考虑哪些边界情况（网络分区、数据回环、Schema 变更）？