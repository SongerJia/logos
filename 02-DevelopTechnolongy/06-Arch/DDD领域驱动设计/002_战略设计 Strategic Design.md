|#|知识点|核心内容|关键要点|面试追问|FlowPulse 实战|
|---|---|---|---|---|---|
|**7.2.1**|**Domain 领域**|组织所从事的活动范围及其涉及的问题空间；是所有子域的超集；识别领域边界的第一步|问题空间(Solution Space之外的现实世界) vs 解 Solution Space(软件系统)|"怎么确定一个系统的领域范围？"|FlowPulse领域：智能业务流程管理平台(涵盖流程编排/任务调度/通知/文件/监控)|
|**7.2.2**|**Subdomain 子域**|将领域拆分为多个子域，每个子域解决一个特定的业务问题；是战略设计的起点|**核心子域**(Core)：核心竞争力/差异化价值 → **支撑子域**(Supporting)：辅助业务但不可或缺 → **通用子域**(Generic)：非差异化/可直接外包或购买|"核心子域、支撑子域、通用子域分别举例说明？"|**★ 核心**: 工作流引擎(FlowPulse创新所在) / **★ 支撑**: 认证授权 / 任务调度 / 消息通知 / 实时通信 / **★ 通用**: 文件存储 / 监控告警|
|**7.2.3**|**Bounded Context 限界上下文 ★★★**|DDD最重要的战略概念！一个上下文内部，领域模型保持一致且含义明确；跨上下文时模型可能同名但含义不同|边界内的统一语言(Ubiquitous Language)、边界明确、大小适中(不能太大也不能太小)；**一个限界上下文 ≈ 一个微服务**|"限界上下文和微服务的关系？一个BC一定是一个服务吗？"|**FlowPulse的10个服务 = 10个限界上下文** ↓ 见详细映射表|
|**7.2.4**|**Context Map 上下文映射**|描述各个限界上下文之间的关系及交互方式；全局视角的系统架构蓝图|**关系类型**：Shared Kernel(共享内核) / Customer-Supplier(客户-供应商) / Conformist(遵从者) / Anti-Corruption Layer(防腐层) / Open Host Service(开放主机) / Published Language(发布语言)|"防腐层(ACL)的实现方式是什么？什么时候需要ACL？"|workflow-service ↔ auth-service 用 **ACL** (避免auth模型污染workflow)|
|**7.2.5**|**核心域识别方法论**|不是所有域都值得投入同样的精力；核心域 = 80%的价值来自20%的功能；识别维度：差异化程度 / 业务复杂度 / 团队投入意愿|"怎么说服管理层在核心域上多投入资源？"|FlowPulse的核心域就是**自研工作流引擎**——这是区别于Activiti/Flowable的关键竞争力||
|**7.2.6**|**子域到限界上下文的映射策略**|一个核心子域通常对应一个独立的BC；多个相关支撑子域可以合并到一个BC；通用子域可能被多个BC共享|映射不是一对一！需要根据团队规模/技术约束/部署需求灵活调整|"一个子域可以跨越两个限界上下文吗？"|见下方完整映射表|

> **🔥 FlowPulse 子域→限界上下文→微服务 完整映射**

```
┌──────────┬──────────────────┬──────────────────────┬──────────────────┬─────────────┐
│ 子域类型   │ 子域名称          │ 限界上下文(BC)         │ 对应微服务         │ 数据库       │
├──────────┼──────────────────┼──────────────────────┼──────────────────┼─────────────┤
│ ★ 核心    │ 流程编排引擎       │ Workflow Context      │ workflow-engine  │ flowpulse_wf│
│ ★ 支撑    │ 用户认证授权       │ Auth Context          │ auth-service      │ flowpulse_auth│
│ ★ 支撑    │ 任务调度中心       │ Scheduler Context     │ scheduler-svc     │ flowpulse_sched│
│ ★ 支撑    │ 消息通知推送       │ Message Context       │ message-svc       │ flowpulse_msg│
│ ★ 支撑    │ 实时通信推送       │ Realtime Context      │ realtime-svc      │ (无独立DB)   │
│ ★ 支撑    │ 分布式事务协调     │ Transaction Context   │ tx-service        │ flowpulse_tx│
│   通用    │ 文件对象存储       │ File Context          │ file-service      │ flowpulse_file│
│   通用    │ 系统监控告警       │ Monitor Context       │ monitor-svc       │ flowpulse_mon│
│   基础设施  │ API路由网关       │ Gateway Context       │ gateway-service   │ 无DB(无状态) │
└──────────┴──────────────────┴──────────────────────┴──────────────────┴─────────────┘

上下文间关系:
  Workflow(Auth) ← Customer-Supplier: workflow调用auth验证用户身份
  Workflow(Message) ← Publish Language: 通过Domain Event解耦
  Workflow(Scheduler) ← Shared Kernel: 共享任务状态枚举定义
  All(Gateway) ← Conformist: 各服务遵循Gateway的路由规范
  Auth(外部LDAP) ← ACL: 不让外部认证模型侵入内部体系
```