|#|要素|定义|关键规则|代码示例|面试追问|FlowPulse 应用|
|---|---|---|---|---|---|---|
|**7.3.1**|**实体 Entity ★**|有唯一标识(ID)的对象，通过ID判等而非属性值；标识在其生命周期内不变，属性可变；具有生命周期和行为|①必须有ID ②通过equals/hashCode基于ID比较 ③包含业务行为(不贫血) ④可追踪状态变化|`public boolean equals(Object o)` 基于 `id` 字段比较|"实体的ID生成策略有哪些？什么时候用自然键什么时候用代理键？"|**ProcessDefinition**(defId) / **ProcessInstance**(instId) / **TaskInstance**(taskId) — 三大核心实体|
|**7.3.2**|**值对象 Value Object ★**|没有唯一标识，通过所有属性值判等的不可变对象；度量/描述/量化某个领域的概念；创建后永不修改(要改就整体替换新VO)|①无ID ②Immutable(final字段+私有构造) ③基于所有字段equals/hashCode ④可共享/可复用|`ProcessStatus status = ProcessStatus.of("RUNNING")`|"值对象的不可变性怎么保证？为什么不用Lombok @Data？"|**ProcessStatus**(RUNNING/COMPLETED) / **NodeType**(USER_TASK/SERVICE_TASK) / **ExecutionStrategy**(SYNC/ASYNC_THREAD) / **Money**(amount+currency) / **DateRange**(start+end)|
|**7.3.3**|**聚合根 Aggregate Root ★★★**|DDD战术设计的**核心**！一组关联对象的聚类，以根实体为唯一入口；聚合内部保持一致性(不变量)，聚合之间只能通过ID引用|①一个聚合一个根 ②外部只持有聚合根引用 ③聚合内修改通过根来协调 ④一个事务只修改一个聚合(事务边界=聚合边界)|`processDef.addNode(node)` 通过聚合根操作内部实体|"聚合边界和事务边界的关系？为什么一个事务只能改一个聚合？"|**ProcessDefinition 为聚合根** → 内部持有 Node(节点) + Transition(连线) + Variable(变量定义)。修改流程定义必须通过 ProcessDefinition API|
|**7.3.4**|**聚合设计原则**|①聚合要小(理想3-5个实体) ②通过引用ID而非对象引用其他聚合 ③最终一致性跨聚合 ④乐观锁防并发冲突|大聚合 = 性能瓶颈 + 并发冲突热点；小聚合 = 高并发友好但跨聚合逻辑变复杂|`@Version` 乐观锁注解|"聚合设计太大有什么坏处？怎么拆分大聚合？"|流程实例聚合(ProcessInstance→TaskInstance→ExecutionPointer)：一次流程推进=修改一个聚合(串行执行保证一致性)|
|**7.3.5**|**领域服务 Domain Service**|当某个操作不属于任何单个实体/值对象时(跨聚合操作/第三方接口调用/类型转换逻辑)，将其建模为领域服务|①无状态 ②操作领域对象(非CRUD) ③命名反映领域意图(非技术术语) ④放在领域层(domain包)|`ProcessEngine.execute(processDefId, variables)`|"领域服务和应用服务的区别？怎么区分？"|**ProcessEngine**(流程引擎核心执行器) / **ConditionEvaluator**(条件表达式求值) / **PermissionChecker**(权限校验领域逻辑)|
|**7.3.6**|**领域事件 Domain Event ★**|领域中已经发生的**事实**(过去式命名)；用于解耦聚合间依赖；驱动后续动作(通知/统计/搜索索引更新)|①命名过去式(ProcessStartedEvent) ②不可变(@Value/Lombok.Value) ③携带时间戳和触发信息 ④由聚合根发布|`eventPublisher.publish(new ProcessStartedEvent(instId, userId))`|"领域事件和应用事件的区别？事件存储(Event Store)要不要做？"|**ProcessStartedEvent** / **TaskCreatedEvent** / **TaskCompletedEvent** / **ProcessCompletedEvent** / **TaskRejectedEvent**|
|**7.3.7**|**资源库 Repository**|聚合根的集合式容器；对上层屏蔽数据存取细节(ORM/Mongo/Redis)；接口属于领域层，实现属于基础设施层|①只服务于聚合根(不为实体单独建Repo) ②接口定义在domain，实现infra ③返回聚合根(完整对象) ④支持按ID查找和条件查询|`interface ProcessDefinitionRepository { Optional<ProcessDefinition> findById(Long id); ProcessDefinition save(ProcessDefinition def); }`|" Repository 和 DAO 的区别？能不能有 findByName 这种查询？"|`ProcessDefinitionRepository` / `ProcessInstanceRepository` / `TaskInstanceRepository` — MyBatis-Plus实现|
|**7.3.8**|**工厂 Factory**|封装复杂对象的创建过程；当构造函数/Builder不够用(创建逻辑含业务规则/需从DB组装/需创建聚合根及内部对象) 时使用|①接口工厂(抽象) vs 实体工厂(具体) ②可组合使用Builder ③隐藏创建复杂性|`ProcessInstance factory.create(defId, starterId, variables)`|"什么时候用工厂而不是直接new？工厂和Builder的区别？"|`ProcessInstanceFactory`: 创建实例时同时初始化第一个任务节点 + 设置初始变量 + 发布启动事件|

> **🔥 FlowPulse 工作流引擎 — 聚合关系全景图**
> 
> ```
> ┌─────────────────────────────────────────────────────────────────┐
> │                    聚合: ProcessDefinition                      │
> │                     ★ 聚合根 ★                                  │
> │  id: Long (标识)                                                  │
> │  name, version, status                                           │
> │  ┌──────────────────────────────────────────────────────────┐    │
> │  │  nodes: List<Node>           ← 实体(有id, 属于此聚合)       │    │
> │  │  ├── UserTaskNode (key, assigneePolicy, formKey)          │    │
> │  │  ├── ServiceTaskNode (key, serviceType, params)           │    │
> │  │  ├── ConditionNode (key, expression)                      │    │
> │  │  ├── ParallelGateway (key, forkMode)                      │    │
> │  │  └── EndEventNode (key, resultVar)                        │    │
> │  │                                                            │    │
> │  │  transitions: List<Transition>  ← 实体(有id)               │    │
> │  │  └── fromNode → toNode (conditionExpression?)              │    │
> │  │                                                            │    │
> │  │  variableDefs: List<VariableDef> ← 值对象(无id)             │    │
> │  │  └── Var(name, type, defaultValue, required)               │    │
> │  └──────────────────────────────────────────────────────────┘    │
> │                                                                   │
> │  行为: start() / activateNode() / addNode() / publish()          │
> └─────────────────────────────────────────────────────────────────┘
>           │ 1:N 创建
>           ▼
> ┌─────────────────────────────────────────────────────────────────┐
> │                    聚合: ProcessInstance                        │
> │                     ★ 聚合根 ★                                  │
> │  id: Long / processDefId(FK, 引用另一聚合) / status / starterId  │
> │  variables: Map<String, Object> (运行时变量)                     │
> │  ┌──────────────────────────────────────────────────────────┐    │
> │  │ tasks: List<TaskInstance>     ← 实体                       │    │
> │  │  taskId / nodeKey / assignee / status(PENDING/COMPLETED)  │    │
> │  │  executionStrategy: ExecutionStrategy (值对象!)            │    │
> │  │                                                            │    │
> │  │ pointers: List<ExecutionPointer] ← 实体(引擎内部)           │    │
> │  │  currentActivityId / tokenPosition                        │    │
> │  └──────────────────────────────────────────────────────────┘    │
> │                                                                   │
> │  行为: advance() / completeTask() / suspend() / cancel()         │
> └─────────────────────────────────────────────────────
> ```