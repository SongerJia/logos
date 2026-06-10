## FlowPulse 智能业务流程平台

### 为什么选这个？

1. **覆盖面最广**：一个项目里嵌入所有你梳理的技术点
2. **软著创新点充足**：自研轻量级工作流引擎 + 分布式调度算法
3. **面试亮点多**：可以讲架构设计、性能优化、分布式事务处理
4. **可拆分子软著**：各微服务模块可单独申请软著

---

## 📐 FlowPulse 项目架构设计

```
SmartFlow 智能业务流程平台
│
├─ 用户服务 (Spring Boot + MyBatis-Plus + Redis)
│   └─ 覆盖：Spring Core / MyBatis-Plus / Redis缓存 / JWT认证
│
├─ 流程引擎服务 (Spring Boot + 自研工作流引擎)
│   └─ 覆盖：设计模式 / 状态机 / 并发锁
│
├─ 任务调度服务 (借鉴XXL-JOB自研)
│   └─ 覆盖：分布式调度 / Quartz / 分片广播
│
├─ 消息通知服务 (Spring Cloud Stream + RocketMQ)
│   └─ 覆盖：RocketMQ / 事务消息 / 死信队列
│
├─ 文件存储服务 (MinIO + Canal监听)
│   └─ 覆盖：MinIO / Canal / Binlog同步
│
├─ API网关 (Spring Cloud Gateway + Nginx)
│   └─ 覆盖：Gateway / Nginx / 限流熔断
│
├─ 分布式事务协调 (Seata)
│   └─ 覆盖：Seata AT/TCC / 分布式事务
│
├─ 实时消息服务 (Netty + WebSocket)
│   └─ 覆盖：Netty / WebSocket / 长连接管理
│
├─ RPC服务调用 (Dubbo)
│   └─ 覆盖：Dubbo / SPI / 集群容错
│
├─ 监控告警服务 (SkyWalking + Prometheus)
│   └─ 覆盖：SkyWalking / Prometheus / Grafana
│
└─ 前端管理台 (Vue3 + Element Plus)
    └─ 覆盖：前端技能（为前端方向打基础）
```

---

## 📝 详细模块设计（每个模块对应你已学的知识点）

### 模块1：用户与权限服务

**技术栈**：Spring Boot + MyBatis-Plus + Redis + MySQL + Spring Security + JWT

**覆盖知识点**：

- Spring Security 认证授权流程
- JWT 双Token机制（Access + Refresh）
- Redis 缓存用户信息、权限点
- MyBatis-Plus 分页、逻辑删除、乐观锁
- OAuth2 第三方登录集成（软著创新点）

**软著创新点**：自研的 RBAC + ABAC 混合权限模型

---

### 模块2：自研轻量级工作流引擎

**技术栈**：Spring Boot + 状态机 + 设计模式

**覆盖知识点**：

- 状态模式 / 责任链模式 / 策略模式
- 流程定义解析（JSON/BPMN）
- 节点跳转、驳回、会签逻辑
- 流程版本管理

**软著创新点**：**自研轻量级工作流引擎**（这是核心创新，可以单独申请软著）

---

### 模块3：分布式任务调度服务

**技术栈**：Spring Boot + 自研调度器（参考XXL-JOB设计）

**覆盖知识点**：

- 分片广播 / 故障转移 / 路由策略
- Quartz / Spring Scheduler
- 调度日志 / 告警通知
- XXL-JOB 原理复现

**软著创新点**：自研的**弹性分布式调度算法**

---

### 模块4：消息通知与事件总线

**技术栈**：Spring Cloud Stream + RocketMQ + WebSocket

**覆盖知识点**：

- RocketMQ 顺序消息 / 事务消息 / 延迟消息
- 消息轨迹追踪
- WebSocket 推送（Netty实现）
- 死信队列处理

**软著创新点**：自研的**消息可靠投递保障机制**

---

### 模块5：分布式事务协调服务

**技术栈**：Seata + 自研补偿框架

**覆盖知识点**：

- Seata AT模式（Undo Log / 全局锁）
- TCC模式（Try / Confirm / Cancel）
- 幂等性设计
- 异常数据回补

**软著创新点**：自研的**混合分布式事务框架**（AT + TCC + Saga）

---

### 模块6：API网关与限流服务

**技术栈**：Spring Cloud Gateway + Nginx + Sentinel

**覆盖知识点**：

- Gateway 路由、过滤器
- Nginx 反向代理、负载均衡
- Sentinel 限流、熔断、降级
- OAuth2 资源服务器

**软著创新点**：自研的**动态路由与智能限流算法**

---

### 模块7：文件存储与数据同步服务

**技术栈**：MinIO + Canal + Elasticsearch

**覆盖知识点**：

- MinIO 分片上传、断点续传
- Canal 监听 Binlog 同步到 ES
- Elasticsearch 全文检索
- 数据一致性保障

**软著创新点**：自研的**实时数据同步引擎**

---

### 模块8：可观测性服务

**技术栈**：SkyWalking + Prometheus + Grafana

**覆盖知识点**：

- SkyWalking 链路追踪
- Prometheus 指标采集
- 自定义 Metrics
- 告警规则配置

**软著创新点**：自研的**智能异常检测算法**