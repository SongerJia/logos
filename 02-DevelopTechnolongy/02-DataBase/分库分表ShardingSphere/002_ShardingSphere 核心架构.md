|#|知识点|笔记三层写法建议|关联|
|---|---|---|---|
|2.1|**ShardingSphere 项目定位与发展历程**|是什么：Apache顶级项目，JDBC/Proxy/Sidecar 三种接入形态；为什么：理解它不是简单的一个jar包而是一套生态；面试：「ShardingSphere和MyCat的区别是什么？」|MyCat 对比|
|2.2|**ShardingSphere-JDBC vs ShardingSphere-Proxy**|是什么：JDBC=轻量级jar嵌入应用层，Proxy=独立部署中间件层；为什么：选型影响架构——JDBC无中心化适合云原生/微服务，Proxy对应用透明适合旧系统；面试：「你们用的哪种模式？为什么这么选？」|微服务架构|
|2.3|**ShardingSphere-JDBC 架构层次**|是什么：解析→路由→改写→执行→归并 五步处理流程图；为什么：理解这个流程才能理解每个配置项在做什么；面试：「一条SQL在ShardingSphere里经历了什么？」|4.x SQL路由与改写|
|2.4|**核心概念：逻辑表/真实表/绑定表/广播表**|是什么：四个术语精确定义+示例（t_order→ds0.t_order_0/ds1.t_order_1）；为什么：这些是配置文件的核心词汇，不理解就写不出正确配置；面试：「什么是绑定表？解决了什么问题？」|3.x 分片策略|
|2.5|**数据分片的两种模式：数据节点 & 自定义**|是什么：inline/standard/complex/hint 四种分片配置方式详解；为什么：从简到复杂对应不同的分片需求；面试：「你们的分片规则是用哪种方式配置的？」|3.x 分片策略与算法|
|2.6|**配置体系（YAML/properties/Spring Boot Starter）**|是什么：一套完整可运行的Spring Boot + ShardingSphere-JDBC 配置模板；为什么：会配才能用，面试可能让你现场写配置；面试：「帮我写一个按user_id取模分片的配置」|Spring Boot 自动配置|
|2.7|**与其他框架的集成（MyBatis/JPA/Hibernate）**|是什么：作为DataSource注入到ORM框架中的方式；为什么：本质就是一个DataSource实现，对上层透明；面试：「ShardingSphere和MyBatis是怎么配合工作的？」|MyBatis SqlSessionFactory|
|2.8|**ShardingSphere 5.x 新特性（可插拔架构）**|是什么：5.x重构后的SPI架构（QueryEngine/RouteEngine/RewriteEngine等）；为什么：5.x是一次重大升级，了解才能跟上最新版本；面试：「ShardingSphere 5.x和4.x有什么区别？」|SPI机制(JVM)|