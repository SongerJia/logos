#### 8.3.1 RPC框架：Dubbo vs gRPC vs OpenFeign

```
┌──────────────────┬───────────────┬──────────────┬──────────────┐
│     评估维度       │  Apache Dubbo  │    gRPC      │ OpenFeign    │
│                   │    3.2         │              │              │
├──────────────────┼───────────────┼──────────────┼──────────────┤
│ 协议             │ TCP+Dubbo协议  │ HTTP/2+Protobuf│ HTTP/1.1 JSON │
│ 序列化            │ Hessian2/Kryo  │ Protobuf      │ Jackson JSON │
│ 性能(QPS基准)     │ ~200K(最高)    │ ~150K         │ ~50K(最低)   │
│ 延迟(P99)        │ <1ms          │ <2ms          │ 5-15ms       │
│ 跨语言支持        │ 弱(主要是Java) │ ★ 极强        │ 中(HTTP通用) │
│ 服务发现集成      │ Nacos/ZooKeeper│ 需自己集成     │ Spring LoadBalancer │
│ 负载均衡          │ 10种内置策略   │ client-side    │ Ribbon/Spring │
│ 熔断降级          │ Sentinel原生   │ 需外接         │ Sentinel/Resilience4j │
│ 生态(SpringCloud) │ ★ Alibaba全家桶 │ 需适配层       │ ★ 标准组件    │
│ 学习曲线          │ 中(中文资料多) │ 高(IDL/Proto)  │ 低(声明式)    │
│ 社区活跃度        │ ★ 非常活跃     │ Google维护     │ Spring维护    │
├──────────────────┼───────────────┼──────────────┼──────────────┤
│ FlowPulse选择     │ ★ 内部通信首选  │ 备选(有Go服务时)│ Gateway/外部接口│
│ 选择理由          │ 性能最强+Sentinel│ 跨语言需求时   │ RESTful标准    │
└──────────────────┴───────────────┴──────────────┴──────────────┘

最终决策(ADR-002):
  内部高频调用 → Dubbo (性能优先)
  Gateway路由 → Feign   (RESTful标准)
  未来Go服务桥接 → gRPC (跨语言)
  ─────────────────────────→ 这就是"组合选型"思维！
```

#### 8.3.2 消息队列：RocketMQ vs Kafka vs RabbitMQ

|维度|RocketMQ|Kafka|RabbitMQ|
|---|---|---|---|
|吞吐量(单机)|10万+/秒|100万+/秒|2万+/秒|
|延迟(ms级)|1-5|5-10|微秒~毫秒|
|消息可靠性|★★★ 同步刷盘/Dleger|副本同步|持久化+ACK|
|事务消息|★★★ 支持|仅幂等生产者|不支持(需插件)|
|消息定时|★★★ 精确延时|仅Log Compaction|TTL死信|
|消息回溯|★★★ 支持按时间|支持Offset|不支持|
|运维复杂度|中(有控制台)|高(ZooKeeper依赖)|低(管理简单)|
|适用场景|★ 业务系统/订单/支付/金融|大数据/日志/用户行为|传统企业/中小规模|
|**FlowPulse选择理由**|**★ 事务消息(分布式一致性) + 定时消息(任务延迟) + 回溯(故障排查) + 阿里生产验证 + Java友好**|||

> **面试金句**："我们选 RocketMQ 不是因为 Kafka 不好，而是因为我们的场景是**业务系统**而非大数据管道。业务系统需要**事务消息保证最终一致**、**精确定时消息支持任务调度**、**消息回溯用于排查**，这三点 RocketMQ 天然契合。"

#### 8.3.3 数据库：MySQL 8 vs PostgreSQL vs MongoDB

|维度|MySQL 8.0|PostgreSQL 16|MongoDB 7|
|---|---|---|---|
|数据模型|关系型(行存)|关系型(列存+行存+JSON)|文档型(BSON)|
|ACID事务|★ InnoDB强一致|MVCC强一致|多文档事务(4.0+)|
|JSON支持|JSON类型(有索引)|★ JSONB(更强大)|原生文档|
|全文检索|基础(Fulltext)|★ 强大(tsvector)|文本索引|
|地理空间|基础|★ PostGIS(极强)|GeoJSON|
|并发能力|读写分离/MGR|流复制/逻辑复制|Sharding集群|
|团队经验|★★★ 最熟悉|中|低|
|云服务|RDS/Aurora|RDS/AtlasDB|Atlas|
|**FlowPulse选择**|**★ 主力存储(关系模型成熟/InnoDB引擎/团队精通/MGR高可用)**||文件元数据可选MongoDB(但MinIO更适合对象存储)|

> **面试金句**："MySQL 最大的优势不是技术参数，而是**团队的熟练度和生态成熟度**。出问题了Google一下就有百万级答案，招人也是MySQL熟手最多。对于 FlowPulse 这种体量的业务系统，MySQL 8.0 + MGR 完全够用。"

#### 8.3.4 工作流引擎：自研 vs Activiti vs Flowable

|维度|自研引擎 (FlowPulse)|Activiti 7|Flowable 7|
|---|---|---|---|
|定制灵活性|★★★ 完全可控|受BPMN规范限制|较Activiti灵活|
|学习曲线|自己写的自然懂|BPMN规范陡峭|类似Activiti|
|软著价值|★★★ 可申请软著！|开源无软著价值|开源无软著价值|
|功能完整性|按需实现(够用就好)|★★★ 极其完善|★★★ 更完善(比Activiti多)|
|性能|★ 轻量级无历史包袱|重(设计器/表单/历史)|更重|
|数据库表数|17张(精简)|28+张(复杂)|30+张(更复杂)|
|面试亮点|★★★ 创新点突出|"我会用Activiti" (普通)|"我会用Flowable" (稍好)|
|维护成本|自己负责|社区维护|商业公司维护|
|**选择理由**|**★ 软著需求 + 创新点展示 + 轻量定制 + 面试差异化**|||

> **这是 FlowPulse 最关键的选型决策(ADR-004)！**
> 
> "为什么不选 Activiti/Flowable？三个原因：
> 
> 1. **BPMN 规范太重** —— 我们不需要完整的 BPMN 2.0，只需要 5 种核心节点(UserTask/ServiceTask/Gateway/Condition/EndEvent)
> 2. **软著需要自研** —— 使用开源引擎无法申请软件著作权，而软著对跳槽/职称评定很重要
> 3. **面试差异化** —— '我用过 Activiti' 太普通，'我设计并实现了一个自适应调度的工作流引擎' 才是亮点"

#### 8.3.5 注册中心：Nacos vs Eureka vs Consul vs ZooKeeper

|维度|Nacos 2.3|Eureka 1.x|Consul|ZooKeeper 3.8|
|---|---|---|---|---|
|CAP模式|AP/CP可切换|AP(仅AP)|CP|CP(仅CP)|
|功能范围|注册+配置+DNS|仅注册|注册+KV+网关|协调(不仅是注册)|
|健康检查|Client+Server|Client仅|Client+Server|Server仅|
|配置管理|★★★ 内置|需Spring Config|Consul Template|需Apollo|
|中文生态|★★★ 阿里/国内主流|Netflix(已停更!)|HashiCorp|Apache/Hadoop生态|
|长期维护|★★★ 活跃开发|已停止维护!|活跃|成熟稳定|
|SpringCloud集成|★ Alibaba原生|Netflix原生|需适配|需适配|
|**FlowPulse选择理由**|**★ AP/CP双模切换 + 注册配置一体 + 阿里开源持续维护 + 国内社区活跃 + Spring Cloud Alibaba深度集成**|已停更!|功能好但非Java系|只适合做协调不做注册发现|