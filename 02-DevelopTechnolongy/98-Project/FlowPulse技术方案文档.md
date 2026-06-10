# FlowPulse 流程脉冲智能业务平台 V1.0

> **软件著作权名称**：FlowPulse流程脉冲智能业务平台 V1.0  
> **版本**：V1.0  
> **编写日期**：2026-06-10  
> **编写人**：FlowPulse架构组

---

## 目录

- [1 项目概述](#1-项目概述)
  - [1.1 项目背景](#11-项目背景)
  - [1.2 项目目标](#12-项目目标)
  - [1.3 核心创新点（软著核心）](#13-核心创新点软著核心)
  - [1.4 技术选型](#14-技术选型)

- [2 技术架构设计](#2-技术架构设计)
  - [2.1 整体架构图](#21-整体架构图)
  - [2.2 服务通信架构](#22-服务通信架构)
  - [2.3 数据流向设计](#23-数据流向设计)

- [3 各模块详细设计](#3-各模块详细设计)
  - [3.1 用户认证服务 (auth-service)](#31-用户认证服务-auth-service)
  - [3.2 自研工作流引擎 (workflow-engine)](#32-自研工作流引擎-workflow-engine)
  - [3.3 分布式任务调度服务 (scheduler-service)](#33-分布式任务调度服务-scheduler-service)
  - [3.4 分布式事务服务 (transaction-service)](#34-分布式事务服务-transaction-service)
  - [3.5 API网关服务 (gateway-service)](#35-api网关服务-gateway-service)
  - [3.6 实时消息服务 (realtime-service)](#36-实时消息服务-realtime-service)
  - [3.7 文件存储服务 (file-service)](#37-文件存储服务-file-service)
  - [3.8 监控告警服务 (monitor-service)](#38-监控告警服务-monitor-service)

- [4 数据库设计](#4-数据库设计)
- [5 接口设计](#5-接口设计)
- [6 部署方案](#6-部署方案)
- [7 开发计划](#7-开发计划)
- [8 软著申请材料清单](#8-软著申请材料清单)
- [9 项目亮点总结（面试用）](#9-项目亮点总结面试用)
- [10 风险与应对](#10-风险与应对)

---

## 1 项目概述

### 1.1 项目背景

随着企业数字化转型的深入，业务流程自动化需求日益增长。传统的工作流引擎（如Activiti、Flowable、Camunda等）虽然功能强大，但普遍存在以下痛点：

| 问题 | 具体表现 |
|------|----------|
| **体积庞大** | 引入依赖多，启动慢，内存占用高（通常500MB+） |
| **学习成本高** | BPMN规范复杂，上手周期长，需要专业培训 |
| **定制化困难** | 核心逻辑耦合深，二次开发难度大 |
| **国产环境适配差** | 对国产数据库、中间件支持不足 |
| **性能瓶颈明显** | 高并发场景下流程实例创建和推进延迟较高 |

基于上述问题，本项目旨在研发一套**轻量级、高性能、易扩展、国产化适配**的智能业务流程平台——**FlowPulse（流程脉冲）**。

### 1.2 项目目标

#### 总体目标

构建一套企业级的智能业务流程管理平台，实现：

1. **自研轻量级工作流引擎** — 替代Activiti/Flowable，核心代码量控制在合理范围
2. **分布式微服务架构** — 基于Spring Cloud Alibaba，实现高可用、可扩展
3. **可视化流程设计器** — 支持拖拽式流程定义，降低使用门槛
4. **实时监控能力** — 全链路追踪，流程状态实时推送
5. **国产中间件深度集成** — RocketMQ、Seata、Nacos、Canal等

#### 功能全景

```
┌─────────────────────────────────────────────────────────────┐
│                    FlowPulse 功能全景                        │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ 流程设计器 │  │ 流程运行  │  │ 任务中心  │  │ 实时监控  │   │
│  │·拖拽设计  │  │·启动流程  │  │·我的待办  │  │·流程图谱  │   │
│  │·条件分支  │  │·审批流转  │  │·已办任务  │  │·状态推送  │   │
│  │·会签/或签  │  │·驳回/转办  │  │·委托/抄送  │  │·性能指标  │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │分布式调度 │  │ 消息通知  │  │ 文件管理  │  │ 系统配置  │   │
│  │·Cron调度  │  │·站内信    │  │·上传下载  │  │·权限管理  │   │
│  │·分片广播  │  │·邮件/短信  │  │·断点续传  │  │·日志审计  │   │
│  │·故障转移  │  │·Webhook  │  │·在线预览  │  │·系统监控  │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 核心创新点（软著核心）

本项目包含以下**四大技术创新点**，作为软著申请的核心支撑：

#### 创新点一：自适应节点调度算法

根据节点类型（用户任务、系统任务、网关节点）和系统负载（CPU/内存/线程池），动态选择最优执行策略。

| 维度 | 传统方案 | 本项目创新方案 |
|------|---------|---------------|
| 执行策略 | 统一同步执行 | 动态选择（同步/异步线程/异步队列/缓存评估） |
| 负载感知 | 无 | 实时采集CPU/内存/QPS指标 |
| 节点区分 | 不区分类型 | 按节点类型匹配最优策略 |
| 性能提升 | - | 高负载下性能提升30%+ |

#### 创新点二：混合分布式事务框架

封装Seata的AT/TCC/Saga三种模式，提供统一的编程接口。框架自动根据业务场景特征选择最合适的事务模式。

| 模式 | 适用场景 | 一致性级别 | 性能影响 | 复杂度 |
|------|---------|-----------|---------|--------|
| AT模式 | 短事务、简单场景、无特殊补偿 | 最终一致 | 低 | 低 |
| TCC模式 | 强一致性要求、有补偿逻辑 | 强一致 | 中 | 高 |
| Saga模式 | 长时间运行、可补偿的业务流程 | 最终一致 | 高 | 中 |

#### 创新点三：实时流程状态同步机制

基于Netty WebSocket的长连接推送机制，实现流程状态的毫秒级实时通知。

核心特性：
- 心跳检测（每30秒一次），自动清理死连接
- 断线重连（指数退避策略，最大间隔30秒）
- 订阅过滤（只推送用户关心的流程变更）
- 消息去重（防止重复推送）

#### 创新点四：智能限流与动态路由算法

在API网关层实现基于令牌桶 + 漏桶的混合限流算法，结合历史流量数据进行QPS预测，动态调整限流阈值。

### 1.4 技术选型

#### 整体技术栈一览

| 层级 | 技术组件 | 版本号 | 用途说明 |
|------|---------|--------|---------|
| **微服务框架** | Spring Boot / Spring Cloud Alibaba | 3.2.0 / 2023.0.1.0 | 基础应用框架 + 微服务全家桶 |
| **服务治理** | Nacos / Dubbo | 2.3.0 / 3.2.0 | 注册中心+配置中心 / RPC远程调用 |
| **网关层** | Spring Cloud Gateway / Nginx | 2023.0.1.0 / 1.26 | API网关 / 反向代理+负载均衡 |
| **ORM & 数据库** | MyBatis-Plus / MySQL / ShardingSphere | 3.5.5 / 8.0 / 5.4.0 | ORM框架 / 关系型数据库 / 分库分表 |
| **缓存** | Redis / Caffeine | 7.2 / 3.1.8 | 缓存+分布式锁 / 本地缓存 |
| **消息队列** | RocketMQ | 5.2.0 | 异步消息 + 事务消息 |
| **分布式事务** | Seata | 2.0.0 | 分布式事务协调 |
| **搜索引擎** | Elasticsearch | 8.12 | 全文检索 |
| **对象存储** | MinIO | RELEASE.2024-02 | 文件存储 |
| **数据同步** | Canal | 1.1.7 | Binlog增量同步 |
| **网络编程** | Netty | 4.1.110 | WebSocket长连接 |
| **安全框架** | Spring Security / JWT | 6.2.0 / 0.12.3 | 认证授权 / 无状态Token认证 |
| **链路追踪** | SkyWalking | 9.0.0 | APM全链路监控 |
| **监控** | Prometheus / Grafana | 2.50.0 / 10.2.0 | 时序指标采集 / 可视化大盘 |
| **前端** | Vue3 / Element Plus / Vite | 3.4.x / 2.5.x / 5.2.x | 前端框架 / UI组件库 / 构建工具 |
| **容器化** | Docker / Docker Compose | 24.0 / V2.24 | 容器运行时 / 编排工具 |

#### 关键选型决策

| 选型决策 | 选择理由 |
|---------|---------|
| 为什么用 Spring Cloud Alibaba？ | 国内生态更成熟，Nacos比Eureka更适合国内环境；Sentinel比Hystrix更活跃 |
| 为什么自研工作流引擎？ | 软著需要原创性；学习价值更大；可以完全控制复杂度 |
| 为什么用 RocketMQ？ | 事务消息支持最好；阿里开源，社区活跃；适合金融级场景 |
| 为什么用 Netty 实现 WebSocket？ | 性能远高于Tomcat内置WebSocket；可自定义协议；面试加分项 |
| 为什么自研任务调度？ | XXL-JOB已有软著，需要差异化；自研能体现技术深度 |

---

## 2 技术架构设计

### 2.1 整体架构图

```
╔═══════════════════════════════════════════════════════════════╗
║                      前端层 (Vue3 + Element Plus)              ║
║  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐     ║
║  │ 流程设计器 │  │ 任务中心  │  │ 监控大屏  │  │ 系统管理  │     ║
║  └──────────┘  └──────────┘  └──────────┘  └──────────┘     ║
╚═════════════════╤═════════════════════════════════════════════╝
                    │ HTTPS (TLS 1.3)
╔═══════════════════╧═════════════════════════════════════════════╗
║              Nginx 反向代理 + 负载均衡 + SSL终止                ║
║           · upstream 负载均衡 · gzip压缩 · HTTP/2 · WAF防护      ║
╚═══════════════════╤═════════════════════════════════════════════╝
                    │
╔═══════════════════╧═════════════════════════════════════════════╗
║                 API 网关层 (Spring Cloud Gateway)              ║
║  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐         ║
║  │ 路由转发      │ │ 限流熔断      │ │ 认证鉴权      │         ║
║  │ ·路径匹配     │ │ ·令牌桶限流   │ │ ·JWT校验     │         ║
║  │ ·Header路由   │ │ ·漏桶平滑    │ │ ·角色校验    │         ║
║  │ ·参数路由     │ │ ·Sentinel集成│ │ ·白名单      │         ║
║  └──────────────┘ └──────────────┘ └──────────────┘         ║
╚═══════════════════╤═════════════════════════════════════════════╝
                    │
╔═══════════════════╧═════════════════════════════════════════════╗
║                  业务服务层 (Spring Boot 3.x)                   ║
║  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          ║
║  │ 用户认证服务  │  │ 流程引擎服务  │  │ 任务调度服务  │          ║
║  │ auth-service│  │ workflow-svc│  │ scheduler-svc│          ║
║  └─────────────┘  └─────────────┘  └─────────────┘          ║
║  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          ║
║  │ 消息通知服务  │  │ 文件存储服务  │  │ 监控告警服务  │          ║
║  │ message-svc  │  │ file-service│  │ monitor-svc  │          ║
║  └─────────────┘  └─────────────┘  └─────────────┘          ║
║  ┌─────────────┐  ┌─────────────┐                            ║
║  │ 分布式事务服务 │  │ 实时消息服务  │                            ║
║  │ tx-service   │  │ realtime-svc │                            ║
║  └─────────────┘  └─────────────┘                            ║
╚═══════════════════╤═════════════════════════════════════════════╝
                    │
╔═══════════════════╧═════════════════════════════════════════════╗
║                       基础设施层                               ║
║  ┌────────┐ ┌──────────┐ ┌────────┐ ┌────────┐ ┌────────┐    ║
║  │ Nacos  │ │RocketMQ │ │ Redis  │ │ Seata  │ │MySQL   │    ║
║  │注册+配置│ │消息队列  │ │ 缓存/锁 │ │分布式TX │ │主从复制 │    ║
║  └────────┘ └──────────┘ └────────┘ └────────┘ └────────┘    ║
║  ┌──────────┐ ┌──────────┐ ┌────────┐ ┌────────┐             ║
║  │ Elastic  │ │  MinIO   │ │ Canal  │ │SkyWalk │             ║
║  │ Search    │ │对象存储  │ │Binlog同步│ │ APM   │             ║
║  └──────────┘ └──────────┘ └────────┘ └────────┘             ║
╚═══════════════════════════════════════════════════════════════╝
```

### 2.2 服务通信架构

本项目中各微服务之间采用**四种通信方式组合**：

| 通信方式 | 使用场景 | 代表模块 | 特点 |
|---------|---------|---------|------|
| **Dubbo (RPC)** | 内部高频服务调用 | auth -> workflow | 高吞吐、强类型约束、集群容错 |
| **OpenFeign (HTTP)** | 对外暴露的服务接口 | gateway -> 各业务服务 | 跨语言兼容、开发便捷 |
| **RocketMQ (异步)** | 事件驱动型交互 | workflow -> message | 解耦、削峰、可靠投递 |
| **Netty WebSocket** | 客户端与服务端的实时交互 | realtime -> 浏览器 | 低延迟、双向通信 |

### 2.3 数据流向设计

```
用户请求 -> Nginx(负载均衡) -> Gateway(鉴权/限流) -> 业务服务
                                                    ├-> MySQL(业务数据)
                                                    ├-> Redis(缓存)
                                                    ├-> RocketMQ(异步消息)
                                                    ├-> Seata(分布式事务)
                                                    └-> Elasticsearch(搜索索引)
                                                              ↓
                                                         Canal(Binlog监听)
                                                              ↓
                                                       数据同步服务
                                                              ↓
                                                     Elasticsearch(索引更新)
                                                              ↓
                                                        SkyWalking(链路追踪)
```

---

## 3 各模块详细设计

### 3.1 用户认证服务 (auth-service)

#### 功能清单

| 功能模块 | 功能点 | 描述 |
|---------|-------|------|
| 登录认证 | 用户名密码登录 | BCrypt加密 + 失败次数限制 + 验证码 |
| | OAuth2第三方登录 | 微信/钉钉/GitHub接入 |
| Token管理 | Access Token | 短期有效（15分钟），携带身份和权限 |
| | Refresh Token | 长期有效（7天），仅用于刷新Access Token |
| | Token黑名单 | Redis黑名单，登出即失效 |
| 用户管理 | 用户CRUD | 创建/查询/修改/禁用用户 |
| | 角色分配 | RBAC角色继承体系 |
| 权限控制 | 菜单权限 | 控制前端菜单可见性 |
| | 按钮权限 | @PreAuthorize接口级别控制 |
| 会话管理 | 在线用户列表 | 查看在线用户，支持强制踢出 |
| | 登录日志 | IP/设备/时间记录 |

#### JWT Token 结构

```json
// Access Token Payload
{
  "sub": "10001",
  "username": "zhangsan",
  "roles": ["admin", "manager"],
  "permissions": ["user:create", "process:start"],
  "iat": 1718000000,
  "exp": 1718000900,
  "jti": "uuid-access-token"
}
// Refresh Token Payload - 只含最少信息
{
  "sub": "10001",
  "type": "refresh",
  "iat": 1718000000,
  "exp": 1718634800
}
```

---

### 3.2 自研工作流引擎 (workflow-engine) ★ 核心创新

#### 与 Activiti/Flowable 的对比

| 维度 | Activiti/Flowable | FlowPulse Engine |
|------|-------------------|------------------|
| 核心JAR包大小 | ~25MB | ~2MB |
| 启动时间 | ~15秒 | ~3秒 |
| 学习曲线 | 陡峭（BPMN完整规范） | 平缓（精简子集） |
| 定制化难度 | 高（代码耦合深） | 低（完全自主可控） |
| 数据库依赖 | 需要28张表 | 仅需5张核心表 |
| 软著原创性 | 已被广泛使用 | 完全原创 |

#### 支持的节点类型

- **事件节点**：StartEvent（开始）、EndEvent（结束：正常/异常/取消）
- **任务节点**：UserTask（人工审批）、ServiceTask（自动执行）、TimerTask（定时等待）、SubProcess（子流程）
- **网关节点**：ExclusiveGateway（排他/条件分支）、ParallelGateway（并行/会签）、InclusiveGateway（包容分支）

#### 流程定义模型（JSON格式示例）

```json
{
  "processId": "leave-apply-v1",
  "processName": "员工请假申请流程",
  "version": "1.0.0",
  "nodes": [
    {"nodeId": "start_1", "type": "StartEvent", "name": "开始", "next": ["user_task_apply"]},
    {
      "nodeId": "user_task_apply", "type": "UserTask", "name": "填写请假单",
      "assignee": "${applicant}", "next": ["service_task_check"]
    },
    {"nodeId": "service_task_check", "type": "ServiceTask", "name": "假期余额检查",
      "implementationType": "BEAN", "implementation": "leaveBalanceChecker",
      "next": ["exclusive_gateway_days"]},
    {
      "nodeId": "exclusive_gateway_days", "type": "ExclusiveGateway", "name": "天数判断",
      "conditions": [
        {"expression": "${days > 0 && days <= 3}", "next": ["user_task_manager"]},
        {"expression": "${days > 3}", "next": ["user_task_director"]}
      ]
    },
    {"nodeId": "user_task_manager", "type": "UserTask", "name": "经理审批",
      "assignee": "${manager}", "actions": ["approve","reject","return"],
      "next": ["end_approve","end_reject"]},
    {"nodeId": "end_approve", "type": "EndEvent", "name": "审批通过", "result": "APPROVED"},
    {"nodeId": "end_reject", "type": "EndEvent", "name": "审批拒绝", "result": "REJECTED"}
  ]
}
```

#### 自适应节点调度算法（创新点一）

```java
public ExecutionStrategy determineStrategy(Node node, SystemMetrics metrics) {
    NodeType type = node.getType();
    double cpu = metrics.getCpuUsage();

    // 规则1: 系统任务在高负载下走队列
    if (type == SERVICE_TASK && cpu > 85) return ASYNC_QUEUE;
    if (type == SERVICE_TASK && cpu > 70) return ASYNC_THREAD_POOL;
    if (type == SERVICE_TASK) return SYNC;

    // 规则2: 用户任务必须同步
    if (type == USER_TASK) return SYNC;

    // 规则3: 多条件排他网关启用缓存
    if (type == EXCLUSIVE_GATEWAY && getConditionCount(node) >= 5)
        return CACHED_EVALUATION;

    return SYNC; // 默认同步
}
```

#### 引擎代码结构

```
com.flowpulse.workflow.engine/
├── core/
│   ├── ProcessEngine.java          # 流程引擎主类
│   ├── ExecutionContext.java       # 执行上下文
│   └── ExecutionStrategy.java      # 执行策略枚举
├── definition/
│   ├── ProcessDefinition.java      # 流程定义实体
│   ├── Node.java                   # 节点抽象基类
│   │   ├── StartEventNode / EndEventNode
│   │   ├── UserTaskNode / ServiceTaskNode
│   │   └── ExclusiveGatewayNode / ParallelGatewayNode
│   └── ConditionExpression.java    # 条件表达式
├── runtime/
│   ├── ProcessInstance.java        # 流程实例
│   ├── ExecutionPointer.java       # 执行指针
│   └── TaskInstance.java           # 任务实例
├── handler/                        # 节点处理器（策略模式）
│   ├── NodeHandler.java            # 处理器接口
│   ├── StartEventHandler / EndEventHandler
│   ├── UserTaskHandler.java        # 核心
│   ├── ServiceTaskHandler.java     # 核心
│   └── ExclusiveGatewayHandler.java# 核心
├── scheduler/                      # ★ 创新点：自适应调度器
│   ├── AdaptiveNodeScheduler.java
│   └── SystemMetricCollector.java
├── event/                          # 事件发布机制
│   ├── WorkflowEvent.java
│   ├── EventPublisher.java
│   └── ProcessStarted/CompletedEvent, TaskCreated/CompletedEvent
└── history/
    └── HistoryActivityRepository.java
```

---

### 3.3 分布式任务调度服务 (scheduler-service)

#### 架构

```
+----------------------------------- 调度中心 ------------------------------------+
|  +----------+  +----------+  +----------+  +----------+  +----------+        |
|  | 任务管理  |  | 调度日志  |  | 执行器管理|  | 路由引擎  |  | 告警服务  |        |
|  | CRUD操作 |  | 成功/失败 |  | 在线/离线|  | 9种策略  |  | 邮件/企微 |        |
|  +----------+  +----------+  +----------+  +----------+  +----------+        |
+------------------------------- HTTP + JSON ----------------------------------+
                                    |
+----------------------------------- 执行器 -------------------------------------+
|  +----------+  +----------+  +----------+                                             |
|  | 任务执行  |  | 回调上报  |  | 日志采集  |                                             |
|  |反射调用  |  |执行结果  |  |关键日志  |                                             |
|  |线程池    |  |进度上报  |  |异常堆栈  |                                             |
|  +----------+  +----------+  +----------+                                             |
|  +----------+                                                                    |
|  | 心跳上报 | 每30秒上报存活状态                                                   |
|  +----------+                                                                    |
+-----------------------------------------------------------------------------------+
```

#### 9种路由策略

| 策略名 | 说明 | 适用场景 |
|--------|------|---------|
| FIRST | 固定选择第一个机器 | 测试环境 |
| LAST | 固定选择最后一个机器 | 特殊场景 |
| ROUND | 轮询分配 | 通用场景（默认推荐） |
| RANDOM | 随机选择 | 无状态服务 |
| CONSISTENT_HASH | 一致性Hash（相同参数→同一台机） | 有状态处理、分片任务 |
| LEAST_FREQUENTLY_USED(LFU) | 最不经常使用 | 缓存命中优化 |
| LEAST_RECENTLY_USED(LRU) | 最近最久未使用 | 连接复用 |
| FAILOVER | 故障转移（检测健康状态） | 生产环境高可用 |
| BUSYOVER | 忙碌转移（优先空闲节点） | 负载敏感场景 |
| **SHARDING_BROADCAST** | **分片广播（所有机器都执行）** | **大数据量批量处理 ★** |

#### 分片广播原理

```
场景：处理10000条订单，3台机器(A/B/C)
配置：shardingTotal = 3

A: shardingIndex=0 -> SELECT * FROM orders WHERE id % 3 = 0
B: shadingIndex=1 -> SELECT * FROM orders WHERE id % 3 = 1
C: shadingIndex=2 -> SELECT * FROM orders WHERE id % 3 = 2

优势：增加机器即可水平扩展！
```

---

### 3.4 分布式事务服务 (transaction-service) ★ 创新点二

#### 混合事务模式选择器

开发者只需声明业务场景特征，框架自动匹配合适的模式：

```java
@GlobalTransaction(scene = {
    consistency = STRONG,       // 一致性强度
    duration = SHORT,           // 预计时长
    hasCompensation = true,     // 是否有补偿动作
    dataSensitivity = HIGH      // 数据敏感度
})
public void orderAndDeduct(OrderRequest request) { ... }

// 框架自动选择逻辑:
// consistency=STRONG + hasCompensation=true  -> TCC
// duration=LONG   + hasCompensation=true    -> Saga
// consistency=EVENTUAL + no compensation   -> AT (默认)
```

#### AT模式两阶段提交

```
第一阶段（执行阶段）:
  1. 解析原始SQL -> 2. 查询Before Image -> 3. 执行业务SQL
  -> 4. 查询After Image -> 5. 生成Undo Log -> 6. 本地事务提交(SQL+UndoLog)
  -> 7. 向TC注册全局锁

第二阶段（提交/回滚）:
  提交 -> 异步删除Undo Log + 释放全局锁
  回滚 -> Undo Log反向执行（UPDATE反转、INSERT->DELETE、DELETE->INSERT）
```

#### 全局锁机制（Redis SETNX + Lua原子释放）

---

### 3.5 API网关服务 (gateway-service) ★ 创新点四

#### 核心功能矩阵：动态路由 / 认证鉴权(JWT) / 限流熔断(令牌桶) / 协议转换 / 日志追踪 / 响应缓存

#### 智能限流配置

```
/api/v1/workflow/**  -> 200 QPS（突发400）
/api/v1/auth/login   -> 20 QPS（突发40）  防暴力破解
/api/v1/schedule/**  -> 50 QPS（突发100）
default              -> 100 QPS（突发200）
```
限流维度：用户ID > API Key > IP地址

---

### 3.6 实时消息服务 (realtime-service) ★ 创新点三

#### 为什么用Netty？

| 对比项 | Tomcat WS | Netty WS |
|--------|----------|----------|
| 连接数上限 | 受线程限制 | Epoll模型，10万+连接 |
| 内存占用 | ~8KB/连接 | ~2KB/连接（ByteBuf池化） |
| 面试价值 | 普通 | **显著加分 ★** |

#### Netty架构：Boss Group(1线程) -> Worker Group(CPU核数) -> Pipeline(Http编解码->WS握手->心跳检测->消息处理)

#### WebSocket协议：AUTH(认证) / SUBSCRIBE(订阅) / PING-PONG(心跳) / STATUS_CHANGE(推送)

---

### 3.7 文件存储服务 (file-service)

MinIO分片上传 + 断点续传(MD5校验) + 秒传 + 在线预览 + RBAC权限控制

### 3.8 监控告警服务 (monitor-service)

Metrics(Prometheus) + Traces(SkyWalking) + Logs(Loki/EFK) 三支柱可观测性体系

---

## 4 数据库设计

共 **17 张核心表**，覆盖7大领域：

| 领域 | 表数 | 核心表 |
|------|------|--------|
| 认证授权 | 5张 | sys_user / sys_role / sys_permission / sys_user_role / sys_role_permission |
| 工作流引擎 | 5张 | wf_process_definition / wf_instance / wf_task_instance / wf_execution_pointer / wf_history_activity |
| 任务调度 | 2张 | schedule_job_info / schedule_job_log |
| 消息通知 | 2张 | msg_template / msg_record |
| 系统+字典+文件 | 3张 | sys_oper_log / sys_dict_type,data / file_info |

> 完整DDL见附件 `sql/flowpulse_schema.sql`

---

## 5 接口设计

### 统一规范：`/api/v1` 前缀，响应格式 `{code, message, data, timestamp}`

### 接口速查

- **认证**: POST login/register/logout/refresh
- **工作流定义**: CRUD + deploy/suspend
- **流程实例**: 启动/查询/取消/图谱SVG/轨迹
- **任务管理**: 待办/已办/认领/完成(同意/拒绝/驳回)/转办
- **任务调度**: CRUD + enable/disable/trigger/日志
- **文件管理**: upload/chunk-upload/merge/download/preview/delete
- **系统管理**: menu树/dict/操作日志/在线用户

---

## 6 部署方案

### Docker Compose: MySQL8 + Redis7.2 + Nacos2.3 + RocketMQ5.2 + Seata2.0 + MinIO（7个容器编排）
### Kubernetes: 3副本Deployment + G1GC JVM参数 + liveness/readiness探针
### Nginx: TLS1.3 + least_conn负载均衡 + WebSocket代理(proxy_read_timeout=3600s)

---

## 7 开发计划（13周 ≈ 3个月）

### 第一阶段（第1-2周）：基础设施 → 父工程/Nacos/用户服务/Gateway/前端登录页
### 第二阶段（第3-6周）：★核心 → 流程引擎全流程开发 + 前端设计器（含自适应调度器创新点一）
### 第三阶段（第7-9周）：中间件 → Redis/RocketMQ/Seata/混合事务框架(创新二)/Canal+ES/MinIO
### 第四阶段（第10-11周）：高级特性 → Netty WS(创新三) + Dubbo + Sentinel + 智能限流网关(创新四)
### 第五阶段（第12周）：监控优化 → SkyWalking/Prometheus/JVM调优/压测/安全加固
### 第六阶段（第13周）：软著材料 → 创新点整理/图形绘制/用户手册/源代码去敏60页/在线申报

---

## 8 软著申请材料清单

### 必需材料：登记申请表 + 软件说明书(60-80页,需截图) + 源代码(60页,每页50行) + 身份证明

### 说明书大纲：
- 第1章 软件概述（5页）
- 第2章 技术特点（25-35页）★★★ 四大创新点详细描述 + 图表
- 第3章 操作说明（20-30页，必须有截图！）
- 第4章 异常处理与维护（5-10页）

### 分模块软著策略（推荐拿4个软著）：
1. FlowPulse-Engine流程脉冲引擎 V1.0 （创新点一）
2. FlowPulse-Scheduler流程脉冲调度平台 V1.0 （路由策略+分片广播）
3. FlowPulse-Gateway流程脉冲智能网关 V1.0 （创新点四）
4. FlowPulse-TX流程脉冲分布式事务框架 V1.0 （创新点二）

---

## 9 项目亮点总结（面试用）

### 9.1 四大技术亮点

1. **自研轻量级工作流引擎** — JSON流程定义 + 自适应节点调度 + 仅5张表(vs Activiti 28张)
2. **混合分布式事务框架** — AT/TCC/Saga统一封装 + 场景自动匹配 + Redis全局锁(Lua)
3. **Netty WebSocket实时推送** — Reactor主从模型 + 心跳保活 + 订阅过滤 + 毫秒级通知
4. **智能限流API网关** — 多维QPS控制 + 令牌桶漏斗混合 + 动态阈值调整

### 9.2 知识点覆盖率

| 已学方向 | 项目对应模块 | 覆盖度 |
|---------|------------|--------|
| Java四件套 | 全模块（并发锁/JVM调优/集合/基础） | 90% |
| 框架五件套 | 全部Spring技术栈 | 100% |
| 数据库与存储 | MySQL/Redis/ES/MinIO | 100% |
| 中间件方向 | RocketMQ/Seata/SkyWalking/Canal | 100% |
| Netty网络编程 | realtime-service WebSocket服务 | 80% |
| Dubbo RPC | 服务间RPC调用 | 70% |
| 安全认证 | auth-service Spring Security + JWT | 100% |
| Nginx | Gateway层反向代理+负载均衡 | 80% |

### 9.3 压测目标数据（开发完成后填写）

- 流程引擎：启动<50ms, 节点执行<10ms, 并发1000+ QPS
- 任务调度：秒级精度, 支持百万级任务, 100+执行器分片
- API网关：5000+ QPS, 平均响应<100ms, 错误率<0.1%

---

## 10 风险与应对

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| 工作流引擎复杂度高 | 开发周期延长 | 先实现核心功能（Start/UserTask/Gateway/End），后续迭代扩展 |
| 分布式事务一致性问题 | 数据不一致 | 充分测试回滚场景；设计补偿机制和人工对账界面 |
| 中间件版本兼容性 | 系统不稳定 | 使用稳定版本；做好版本锁定(Docker固定镜像tag) |
| 性能达不到预期 | 用户体验差 | 提前做压力测试；持续JVM+DB调优 |
| 软著审查被要求补正 | 延迟下证 | 说明书多放截图；源代码去除敏感信息；创新点描述充分 |

---

> **文档结束**
>
> 版本：V1.0 | 最后更新：2026-06-10
>
> 如需获取完整建表SQL文件(`flowpulse_schema.sql`)或Docker Compose完整配置，请告知。
├── scheduler/                      # 创新