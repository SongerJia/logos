# 可观测性体系深度解析：Metrics + Logging + Tracing + OpenTelemetry

> **定位**：从监控到可观测性的完整知识体系，覆盖三大支柱（Metrics/Logging/Tracing）的底层原理、架构设计、核心源码剖析，以及 OpenTelemetry 统一标准、告警体系、Grafana 可视化和生产级最佳实践。
>
> **目标读者**：中高级 Java 后端工程师 / 运维 / SRE / 架构师
>
> **阅读建议**：先读第一章建立全局认知，再按需深入各支柱章节，最后读实践篇串联落地。

---

## 目录

- [第一章 可观测性概述](#第一章-可观测性概述)
  - [1.1 什么是可观测性](#11-什么是可观测性)
  - [1.2 监控 vs 可观测性](#12-监控-vs-可观测性)
  - [1.3 三大支柱](#13-三大支柱)
  - [1.4 黄金信号与方法论](#14-黄金信号与方法论)
- [第二章 Metrics 指标监控 — Prometheus 深度剖析](#第二章-metrics-指标监控--prometheus-深度剖析)
  - [2.1 Prometheus 整体架构](#21-prometheus-整体架构)
  - [2.2 数据模型与四种指标类型](#22-数据模型与四种指标类型)
  - [2.3 Pull 模型与服务发现机制](#23-pull-模型与服务发现机制)
  - [2.4 PromQL 查询语言](#24-promql-查询语言)
  - [2.5 存储引擎底层原理](#25-存储引擎底层原理)
  - [2.6 Prometheus 高可用方案](#26-prometheus-高可用方案)
- [第三章 Logging 日志体系 — ELK/EFK 深度剖析](#第三章-logging-日志体系--elkefk-深度剖析)
  - [3.1 ELK 架构演进](#31-elk-架构演进)
  - [3.2 Elasticsearch 存储原理（日志视角）](#32-elasticsearch-存储原理日志视角)
  - [3.3 Logstash 采集与处理管道](#33-logstash-采集与处理管道)
  - [3.4 Fluentd / Fluent Bit 轻量采集](#34-fluentd--fluent-bit-轻量采集)
  - [3.5 结构化日志与 MDC](#35-结构化日志与-mdc)
  - [3.6 日志采样与脱敏](#36-日志采样与脱敏)
- [第四章 Tracing 分布式链路追踪深度剖析](#第四章-tracing-分布式链路追踪深度剖析)
  - [4.1 Google Dapper 论文核心思想](#41-google-dapper-论文核心思想)
  - [4.2 Span/Trace 数据模型](#42-spantrace-数据模型)
  - [4.3 上下文传播机制](#43-上下文传播机制)
  - [4.4 采样策略](#44-采样策略)
  - [4.5 SkyWalking 架构与源码剖析](#45-skywalking-架构与源码剖析)
  - [4.6 Jaeger vs Zipkin vs SkyWalking 对比](#46-jaeger-vs-zipkin-vs-skywalking-对比)
- [第五章 OpenTelemetry 统一标准](#第五章-opentelemetry-统一标准)
  - [5.1 OTLP 协议设计](#51-otlp-协议设计)
  - [5.2 Instrumentation 自动埋点](#52-instrumentation-自动埋点)
  - [5.3 Collector 架构](#53-collector-架构)
  - [5.4 与 Prometheus/Jaeger/SkyWalking 的关系](#54-与-prometheusjaegerskywalking-的关系)
- [第六章 告警体系](#第六章-告警体系)
  - [6.1 Alertmanager 工作原理](#61-alertmanager-工作原理)
  - [6.2 告警分级与路由](#62-告警分级与路由)
  - [6.3 告警收敛与降噪](#63-告警收敛与降噪)
- [第七章 Grafana 可视化体系](#第七章-grafana-可视化体系)
  - [7.1 Dashboard 设计原则](#71-dashboard-设计原则)
  - [7.2 数据源与变量模板](#72-数据源与变量模板)
  - [7.3 Grafana Alerting](#73-grafana-alerting)
- [第八章 生产级最佳实践](#第八章-生产级最佳实践)
  - [8.1 SLI/SLO/SLA 体系](#81-slislosla-体系)
  - [8.2 RED / USE / Four Golden Signals 方法论落地](#82-red--use--four-golden-signals-方法论落地)
  - [8.3 可观测性成熟度模型](#83-可观测性成熟度模型)
  - [8.4 容器与 Kubernetes 可观测性](#84-容器与-kubernetes-可观测性)
- [第九章 面试高频题](#第九章-面试高频题)

---

## 第一章 可观测性概述

### 1.1 什么是可观测性

**可观测性（Observability）** 是一个源自控制理论的术语，由 Rudolf E. Kálmán 在 1960 年提出。其原始定义是：

> **一个系统能否仅从其外部输出（行为）推断出内部状态的能力。**

在软件工程领域，可观测性指的是：**通过系统外部的输出（Metrics、Logs、Traces），能够理解系统内部正在发生什么的能力。**

核心区别在于：

```
┌─────────────────────────────────────────────────────┐
│                    监控 (Monitoring)                  │
│  "我知道可能会出什么问题，我设了监控来盯着它"           │
│  → 已知未知 (Known Unknowns)                         │
│  → 你知道该监控什么，提前埋了点                        │
└─────────────────────────────────────────────────────┘
                      ↓ 演进
┌─────────────────────────────────────────────────────┐
│                  可观测性 (Observability)             │
│  "我不知道会出什么问题，但系统足够透明，出了就能查"      │
│  → 未知未知 (Unknown Unknowns)                       │
│  → 系统输出足够丰富，能应对任何问题排查                 │
└─────────────────────────────────────────────────────┘
```

**为什么需要可观测性？**

| 传统监控的问题 | 可观测性如何解决 |
|---|---|
| 微服务架构下，一个请求经过 10+ 服务，链路复杂 | Tracing 全链路追踪 |
| 容器化/K8s 环境下，基础设施频繁创建销毁 | 动态服务发现 + 自动采集 |
| 问题发生前无法预见所有可能的故障 | 高基数维度数据，支持灵活查询 |
| 故障定位需要登录多台机器看日志 | 统一平台关联 Metrics/Logs/Traces |
| 告警泛滥，运维疲劳 | 告警收敛 + 基于 SLO 的告警策略 |

### 1.2 监控 vs 可观测性

| 维度 | 监控 (Monitoring) | 可观测性 (Observability) |
|---|---|---|
| **目标** | 回答"系统是否正常？" | 回答"系统为什么不正常？" |
| **方式** | 预设检查项 + 阈值告警 | 灵活查询 + 关联分析 |
| **数据** | 低基数指标为主 | 高基数指标 + 日志 + 链路 |
| **应对** | 已知故障模式 | 未知故障模式 |
| **工具** | Zabbix、Nagios | Prometheus、ELK、Jaeger、Grafana |
| **文化** | 被动响应告警 | 主动探索分析 |

### 1.3 三大支柱

可观测性的三大支柱是 **Metrics（指标）**、**Logging（日志）**、**Tracing（链路追踪）**：

```
                    ┌──────────────────────┐
                    │    可观测性 Observability   │
                    └──────────┬───────────┘
                    ┌──────────┼───────────┐
                    │          │           │
              ┌─────▼─────┐ ┌──▼──────┐ ┌─▼──────────┐
              │  Metrics  │ │ Logging  │ │  Tracing   │
              │   指标    │ │  日志    │ │  链路追踪   │
              └─────┬─────┘ └──┬──────┘ └─┬──────────┘
                    │          │           │
         ┌──────────┘          │           └──────────┐
         │                     │                      │
    ┌────▼─────┐         ┌─────▼─────┐         ┌──────▼──────┐
    │ 什么在   │         │ 发生了    │         │  在哪里     │
    │ 发生     │         │ 什么      │         │  发生的     │
    │(聚合数值)│         │(事件记录) │         │(请求路径)   │
    └──────────┘         └───────────┘         └─────────────┘
         │                     │                      │
    ┌────▼─────┐         ┌─────▼─────┐         ┌──────▼──────┐
    │ CPU 90%  │         │ 14:23 OOM │         │ Gateway→    │
    │ QPS 1.2k │         │ Error...  │         │ OrderSvc→   │
    │ RT 200ms │         │           │         │ MySQL(3.5s) │
    └──────────┘         └───────────┘         └─────────────┘
```

**三者的关系**：

| 特征 | Metrics | Logging | Tracing |
|---|---|---|---|
| **数据量** | 小（聚合数据） | 大（每条记录） | 中（采样后） |
| **基数** | 低（标签有限） | 高（每条唯一） | 高（每请求唯一） |
| **查询成本** | 低 | 高（全文检索） | 中 |
| **保留周期** | 长（15-90天） | 短（7-30天） | 中（7-14天） |
| **回答什么** | 正在发生什么 | 发生了什么细节 | 请求经过了什么路径 |
| **典型工具** | Prometheus | ELK/EFK | Jaeger/SkyWalking |
| **关联方式** | 时间戳 + 标签 | TraceID | TraceID + SpanID |

**关联关系（关键）**：

```
用户请求
    │
    ├─► Tracing: TraceID=abc123, 完整调用链
    │       │
    │       └─► Span: OrderService.createOrder() duration=3.5s
    │               │
    │               ├─► Logging: TraceID=abc123 "订单创建成功, userId=12345"
    │               │
    │               └─► Metrics: order_create_duration_seconds{service=order} p99=3.5s
    │
    └─► 通过 TraceID 将三者关联起来！
```

### 1.4 黄金信号与方法论

#### 1.4.1 Google SRE 四大黄金信号 (Four Golden Signals)

Google SRE Book 提出的四大黄金信号是监控任何服务的核心维度：

```
┌─────────────────────────────────────────────────────────────┐
│                    四大黄金信号                                │
├───────────────┬───────────────┬───────────────┬─────────────┤
│   延迟        │   流量        │   错误        │  饱和度     │
│  Latency     │  Traffic     │   Errors     │ Saturation  │
├───────────────┼───────────────┼───────────────┼─────────────┤
│ 请求处理时间   │ 服务承载量    │ 请求失败率    │ 资源利用率  │
│               │               │               │             │
│ p50/p90/p99   │ QPS/TPS       │ 5xx 比例      │ CPU/Memory  │
│ 成功vs失败延迟 │ 并发数        │ 4xx 比例      │ 磁盘/网络   │
│               │ 吞吐量        │ 降级次数      │ 连接池      │
│               │               │               │ 队列深度    │
├───────────────┼───────────────┼───────────────┼─────────────┤
│ Prometheus:   │ Prometheus:   │ Prometheus:   │ Prometheus: │
│ http_request  │ http_request  │ http_request  │ node_cpu    │
│ _duration     │ _count        │ _count{code    │ _seconds    │
│ _seconds      │               │ =~"5.."}      │             │
└───────────────┴───────────────┴───────────────┴─────────────┘
```

#### 1.4.2 RED 方法（微服务监控）

RED 方法由 Tom Wilkie 提出，适用于请求驱动的服务：

| 信号 | 含义 | 指标 |
|---|---|---|
| **R**ate | 请求速率 | QPS / TPS |
| **E**rrors | 错误率 | 错误请求数 / 总请求数 |
| **D**uration | 请求时长 | p50, p90, p99 延迟分布 |

#### 1.4.3 USE 方法（资源监控）

USE 方法由 Brendan Gregg 提出，适用于基础设施资源监控：

| 信号 | 含义 | 指标 |
|---|---|---|
| **U**tilization | 使用率 | CPU 使用率、内存使用率 |
| **S**aturation | 饱和度 | 队列长度、等待请求数 |
| **E**rrors | 错误 | 网络丢包率、磁盘 I/O 错误 |

**RED vs USE 使用场景**：

```
              分析对象
           ┌───────────┐
           │           │
  资源层    │  USE 方法  │  CPU/磁盘/网络/内存
(硬件)     │           │  "这台机器健康吗？"
           └───────────┘
           ┌───────────┐
           │           │
  服务层    │  RED 方法  │  HTTP请求/RPC调用
(软件)     │           │  "这个服务健康吗？"
           └───────────┘
           ┌───────────┐
           │           │
  全局层    │ Golden    │  综合 RED + USE
           │ Signals   │  "整体系统健康吗？"
           └───────────┘
```

---

## 第二章 Metrics 指标监控 — Prometheus 深度剖析

### 2.1 Prometheus 整体架构

```
┌───────────────────────────────────────────────────────────────────────┐
│                         Prometheus 架构                                │
│                                                                       │
│   ┌─────────┐  ┌─────────┐  ┌─────────┐                              │
│   │  App 1  │  │  App 2  │  │ MySQL   │     ← Exporter 暴露 /metrics  │
│   │ /metrics│  │ /metrics│  │Exporter │                               │
│   └────┬────┘  └────┬────┘  └────┬────┘                               │
│        │            │            │                                     │
│        │    Pull     │   Pull     │   Pull                             │
│        │◄───────────┤◄───────────┤◄──────────┐                        │
│        │            │            │           │                        │
│                          ┌───────┴───────────┴──┐                     │
│                          │                      │                     │
│                          │   Prometheus Server  │                     │
│                          │                      │                     │
│                          │  ┌────────────────┐  │                     │
│                          │  │ Retrieval     │  │  ← 定时拉取          │
│                          │  │ (Scrape)      │  │                     │
│                          │  └───────┬───────┘  │                     │
│                          │          │          │                     │
│                          │  ┌───────▼───────┐  │                     │
│                          │  │ TSDB          │  │  ← 时序存储          │
│                          │  │ (本地磁盘)     │  │                     │
│                          │  └───────┬───────┘  │                     │
│                          │          │          │                     │
│                          │  ┌───────▼───────┐  │                     │
│                          │  │ HTTP Server   │  │  ← PromQL 查询       │
│                          │  │ (Query API)   │  │                     │
│                          │  └───────┬───────┘  │                     │
│                          └──────────┼──────────┘                     │
│                                     │                                  │
│          ┌──────────────────────────┼────────────────────────┐        │
│          │                          │                        │        │
│   ┌──────▼──────┐          ┌────────▼────────┐      ┌───────▼──────┐ │
│   │   Grafana   │          │  Alertmanager   │      │   API/SDK    │ │
│   │  Dashboard  │          │  (告警路由)      │      │  (PromQL)    │ │
│   └─────────────┘          └────────┬────────┘      └──────────────┘ │
│                                     │                                  │
│                              ┌──────▼──────┐                         │
│                              │  Email/钉钉  │                         │
│                              │  /Webhook   │                         │
│                              └─────────────┘                         │
│                                                                     │
│   ┌──────────────┐                                                    │
│   │ Pushgateway │  ← 短生命周期任务 Push 指标                          │
│   │ (短期任务)   │                                                    │
│   └──────────────┘                                                    │
└───────────────────────────────────────────────────────────────────────┘
```

**核心组件职责**：

| 组件 | 职责 | 类比 |
|---|---|---|
| **Prometheus Server** | 核心服务，采集+存储+查询 | 数据库 |
| **Exporter** | 被监控端暴露指标 | 数据源 |
| **Pushgateway** | 短生命周期任务推送指标 | 中转站 |
| **Alertmanager** | 告警路由、分组、抑制、沉默 | 告警中心 |
| **Grafana** | 可视化仪表盘 | 展示层 |

**Pull vs Push 模型对比**：

```java
// Pull 模型（Prometheus 的选择）
// Prometheus 主动去拉取目标的 /metrics 端点

// 优势：
// 1. 主动权在监控系统，知道目标是否可达
// 2. 目标不需要知道监控系统地址
// 3. 天然的健康检查（拉不到=目标挂了）
// 4. 可以做采样控制

// Push 模型（如 StatsD、InfluxDB Telegraf）
// 应用主动推送指标到监控服务

// 优势：
// 1. 适合短生命周期任务（如 Cron Job）
// 2. 适合 NAT 后的服务
// 3. 更实时的推送

// Prometheus 为什么选 Pull？
// 1. 简化客户端：不需要配置推送地址、重试策略
// 2. 主动健康检查：拉不到就是挂了
// 3. 防止指标洪泛：客户端不会在系统忙时压垮监控系统
// 4. 安全性：监控服务可以控制采集频率和范围
```

### 2.2 数据模型与四种指标类型

#### 2.2.1 数据模型

Prometheus 所有数据都是**时序数据**，由以下要素组成：

```
metric_name{label1="value1", label2="value2"}  sample_value  timestamp

└──────┬────┘ └──────────┬──────────────────┘  └────┬────┘  └────┬───┘
     指标名            标签(Label)                  值        时间戳
```

**核心概念：每条时序 = 指标名 + 一组标签的唯一定义**

```
// 以下两条是不同的时序
http_requests_total{method="GET", status="200"}
http_requests_total{method="POST", status="200"}

// 如果标签不同 → 不同的时序 → 不同的存储条目
// 标签数 × 标签值组合数 = 时序数量（基数 Cardinality）
// ⚠️ 高基数标签（如 userId）会导致时序爆炸！
```

#### 2.2.2 四种指标类型

```
┌─────────────────────────────────────────────────────────────────┐
│                  Prometheus 四种指标类型                        │
├──────────────┬──────────────────┬─────────────────────────────┤
│    Counter   │     Gauge        │     Histogram    │ Summary  │
│    计数器    │      仪表盘      │       直方图     │   摘要   │
├──────────────┼──────────────────┼────────────────┼───────────┤
│  只增不减    │   可增可减      │   分布统计      │ 分布统计  │
│  (除非重启)  │                  │   (客户端分桶)  │(客户端计  │
│              │                  │                 │  算分位)  │
├──────────────┼──────────────────┼────────────────┼───────────┤
│ 请求总数     │ 当前内存使用     │ 请求延迟分布    │ 请求延迟  │
│ 错误总数     │ 当前连接数       │ 响应体大小分布  │ p99/p95   │
│ 已处理任务数 │ 队列长度         │                 │ (客户端算)│
│              │ CPU 使用率       │                 │           │
├──────────────┼──────────────────┼────────────────┼───────────┤
│  rate()计算  │ 直接使用         │ histogram_      │ 直接使用  │
│  QPS         │                  │ quantile()计算  │           │
│              │                  │ 分位数          │           │
├──────────────┼──────────────────┼────────────────┼───────────┤
│  存储成本低   │  存储成本低      │  存储成本中     │ 存储成本高│
│  1条时序     │  1条时序         │  N个桶+sum+count│ N个分位数 │
└──────────────┴──────────────────┴────────────────┴───────────┘
```

**Counter 详解**：

```java
// Counter：单调递增计数器
// 典型场景：请求总数、错误总数、已处理任务数

// Micrometer 实现示例（Spring Boot 默认集成）
@Component
public class OrderMetrics {
    private final Counter orderCreatedCounter;
    private final Counter orderFailedCounter;
    
    public OrderMetrics(MeterRegistry registry) {
        this.orderCreatedCounter = Counter.builder("order.created")
            .tag("service", "order-service")
            .tag("type", "normal")
            .description("订单创建总数")
            .register(registry);
            
        this.orderFailedCounter = Counter.builder("order.failed")
            .tag("service", "order-service")
            .description("订单创建失败总数")
            .register(registry);
    }
    
    public void recordOrder(boolean success) {
        if (success) {
            orderCreatedCounter.increment();
        } else {
            orderFailedCounter.increment();
        }
    }
}

// Prometheus 暴露的格式：
// # HELP order_created_total 订单创建总数
// # TYPE order_created_total counter
// order_created_total{service="order-service",type="normal"} 12345
```

**Gauge 详解**：

```java
// Gauge：瞬时值，可增可减
// 典型场景：当前连接数、内存使用量、队列长度、温度

@Component
public class ConnectionMetrics {
    private final AtomicInteger activeConnections = new AtomicInteger(0);
    
    @PostConstruct
    public void init() {
        Metrics.gauge("db.connections.active", activeConnections);
    }
    
    public void onConnectionAcquired() {
        activeConnections.incrementAndGet();
    }
    
    public void onConnectionReleased() {
        activeConnections.decrementAndGet();
    }
}

// Prometheus 暴露：
// # TYPE db_connections_active gauge
// db_connections_active 15
```

**Histogram 详解**：

```java
// Histogram：将数据分布到预定义的桶中
// 典型场景：请求延迟分布、响应体大小分布

// Histogram 暴露的不是 p99 值，而是：
// 1. 每个桶的累计计数：le="0.1", le="0.5", le="1.0"...
// 2. 总和 _sum
// 3. 总计数 _count

// Micrometer 实现示例
@Component
public class RequestMetrics {
    private final Timer requestTimer;
    
    public RequestMetrics(MeterRegistry registry) {
        this.requestTimer = Timer.builder("http.server.requests")
            .tag("uri", "/api/orders")
            .tag("method", "POST")
            // 指定分桶边界（SLA 配置）
            .sla(Duration.ofMillis(10), Duration.ofMillis(50), 
                 Duration.ofMillis(100), Duration.ofMillis(500),
                 Duration.ofSeconds(1), Duration.ofSeconds(5))
            .register(registry);
    }
    
    public void recordRequest(Runnable request) {
        requestTimer.record(() -> {
            try {
                request.run();
            } catch (Exception e) {
                throw e;
            }
        });
    }
}

// Prometheus 暴露格式：
// # TYPE http_server_requests_seconds histogram
// http_server_requests_seconds_bucket{uri="/api/orders",le="0.01"} 100
// http_server_requests_seconds_bucket{uri="/api/orders",le="0.05"} 500
// http_server_requests_seconds_bucket{uri="/api/orders",le="0.1"} 800
// http_server_requests_seconds_bucket{uri="/api/orders",le="0.5"} 950
// http_server_requests_seconds_bucket{uri="/api/orders",le="1.0"} 980
// http_server_requests_seconds_bucket{uri="/api/orders",le="5.0"} 1000
// http_server_requests_seconds_bucket{uri="/api/orders",le="+Inf"} 1000
// http_server_requests_seconds_count{uri="/api/orders"} 1000
// http_server_requests_seconds_sum{uri="/api/orders"} 120.5

// 通过 histogram_quantile() 计算 p99：
// histogram_quantile(0.99, rate(http_server_requests_seconds_bucket[5m]))
```

**Histogram vs Summary 对比**：

```
                    Histogram                    Summary
                 ┌────────────────┐          ┌────────────────┐
  客户端          │ 分桶计数        │          │ 客户端计算分位数 │
  (App)          │ le=0.1: 800    │          │ quantile=0.99   │
                 │ le=0.5: 950    │          │   =0.045        │
                 │ le=1.0: 980    │          │ quantile=0.95   │
                 │ count: 1000   │          │   =0.023        │
                 └───────┬────────┘          └───────┬────────┘
                         │                           │
  服务端          ┌──────▼────────┐          ┌──────▼────────┐
  (Prometheus)   │ histogram_    │          │  直接读取      │
                 │ quantile()     │          │  不能跨实例    │
                 │ 服务端计算      │          │  聚合分位数    │
                 │                 │          │                │
                 │ ✅ 可跨实例聚合  │          │ ❌ 不可聚合     │
                 │ ✅ 可事后调整    │          │ ❌ 不可调整     │
                 │    分位数值     │          │    分位数值     │
                 └────────────────┘          └────────────────┘

  推荐选择：Histogram（除非已知不需要聚合 + 对精度要求极高）
```

### 2.3 Pull 模型与服务发现机制

```yaml
# prometheus.yml 核心配置
global:
  scrape_interval: 15s          # 全局采集间隔
  evaluation_interval: 15s      # 规则评估间隔

# 服务发现配置示例（Kubernetes）
scrape_configs:
  # 1. 静态配置（最简单）
  - job_name: 'static-apps'
    static_configs:
      - targets: ['app1:9090', 'app2:9090']
  
  # 2. 文件服务发现（动态更新）
  - job_name: 'file-sd'
    file_sd_configs:
      - files: ['/etc/prometheus/targets/*.yml']
        refresh_interval: 30s
  
  # 3. Consul 服务发现
  - job_name: 'consul-sd'
    consul_sd_configs:
      - server: 'consul:8500'
        services: ['order-service', 'payment-service']
  
  # 4. Kubernetes 服务发现
  - job_name: 'k8s-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      # 只采集有 prometheus.io/scrape 注解的 Pod
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      # 使用注解中指定的端口
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: (.+)
        replacement: $1
  
  # 5. DNS 服务发现
  - job_name: 'dns-sd'
    dns_sd_configs:
      - names: ['my-service.my-namespace.svc.cluster.local']
        type: A
        port: 9090
```

**服务发现工作流程**：

```
┌──────────────────────────────────────────────────────┐
│              Prometheus Service Discovery             │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │  Consul  │  │   K8s    │  │   DNS    │  ...      │
│  │  API     │  │   API    │  │  Lookup  │           │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘           │
│       │              │             │                  │
│       └──────────────┼─────────────┘                  │
│                      ▼                                │
│              ┌───────────────┐                       │
│              │  SD Manager   │  ← 定期刷新目标列表     │
│              │  (发现目标)   │     (refresh_interval) │
│              └───────┬───────┘                       │
│                      │                                │
│              ┌───────▼───────┐                       │
│              │  Target Set   │  ← 当前活动目标集合     │
│              │  10.0.0.1:9090 │                       │
│              │  10.0.0.2:9090 │                       │
│              │  10.0.0.3:9090 │                       │
│              └───────┬───────┘                       │
│                      │                                │
│              ┌───────▼───────┐                       │
│              │   Scrape      │  ← 按间隔拉取 /metrics  │
│              │   Manager     │                       │
│              └───────────────┘                       │
└──────────────────────────────────────────────────────┘
```

### 2.4 PromQL 查询语言

PromQL 是 Prometheus 的查询语言，功能强大但学习曲线陡峭。

**基础查询**：

```promql
// 1. 即时查询（Instant Vector）：返回最新值
http_requests_total{method="GET"}

// 2. 范围查询（Range Vector）：返回时间范围内所有值
http_requests_total{method="GET"}[5m]

// 3. 标量查询（Scalar）：返回一个数字
42.5

// 4. 字符串查询
"hello"
```

**常用聚合与函数**：

```promql
// === 基础 ===
// rate: 计算每秒增长率（最常用！）
rate(http_requests_total[5m])

// increase: 计算时间范围内总增长量
increase(http_requests_total[1h])

// irate: 瞬时增长率（只看最后两个点，更敏感但不稳定）
irate(http_requests_total[1m])

// === 聚合 ===
// sum: 按标签求和
sum by (service) (rate(http_requests_total[5m]))

// avg: 求平均值
avg by (method) (http_request_duration_seconds_sum / http_request_duration_seconds_count)

// topk: 取最高的 N 个
topk(5, rate(http_requests_total[5m]))

// histogram_quantile: 从 Histogram 桶计算分位数
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))

// === 运算 ===
// 计算错误率
sum(rate(http_requests_total{status=~"5.."}[5m])) 
  / 
sum(rate(http_requests_total[5m]))

// === 常用函数 ===
// 计算 5 分钟内的最大值
max_over_time(http_request_duration_seconds[5m])

// 一分钟增长率
predict_linear(node_filesystem_avail_bytes[1h], 4 * 3600)  // 预测 4 小时后磁盘剩余

// 0~1 之间归一化
clamp_min(clamp_max(
  1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes),
  1), 0)
```

**PromQL 执行原理**：

```
查询: sum by (service) (rate(http_requests_total{method="GET"}[5m]))

执行步骤:
┌─────────────────────────────────────────────────────────┐
│ 1. 简化匹配: http_requests_total{method="GET"}          │
│    → 从 TSDB 中找出所有 method="GET" 的时序               │
│    → 结果: N 条时序 (每个 instance+status 一条)            │
└─────────────────────────┬───────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────┐
│ 2. 范围选择: ...[5m]                                     │
│    → 对每条时序取过去 5 分钟的所有采样点                    │
│    → 结果: N 条时序 × M 个点                              │
└─────────────────────────┬───────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────┐
│ 3. rate() 函数: 对每条时序计算增长率                       │
│    → (最后一个点值 - 第一个点值) / 时间跨度                │
│    → 结果: N 条时序 × 1 个即时值                          │
└─────────────────────────┬───────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────┐
│ 4. sum by (service) 聚合                                │
│    → 按 service 标签分组求和                              │
│    → 结果: K 条时序 (K = service 标签值数量)              │
└─────────────────────────────────────────────────────────┘
```

### 2.5 存储引擎底层原理

Prometheus TSDB（Time Series Database）经历了从 V2（LevelDB）到 V3（自研）的演进，V3 是目前主流版本。

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Prometheus TSDB V3 存储架构                       │
│                                                                     │
│  时间窗口: 2小时一个 Block                                           │
│                                                                     │
│  ┌──────────────────────┐  ┌──────────────────────┐                 │
│  │   Head (内存)         │  │  最近完成的 Block     │                 │
│  │   最新数据缓冲区       │  │  (只读)              │                 │
│  │                      │  │                      │                 │
│  │  ┌────────────────┐ │  │  ┌────────────────┐ │                 │
│  │  │  mem-chunks    │ │  │  │  chunks/      │ │                 │
│  │  │  (最新数据)     │ │  │  │  (压缩后)     │ │                 │
│  │  └────────────────┘ │  │  └────────────────┘ │                 │
│  │  ┌────────────────┐ │  │  ┌────────────────┐ │                 │
│  │  │  mmapped-chunks│ │  │  │  index/        │ │                 │
│  │  │  (映射到文件)   │ │  │  │  (倒排索引)    │ │                 │
│  │  └────────────────┘ │  │  └────────────────┘ │                 │
│  │  ┌────────────────┐ │  │  ┌────────────────┐ │                 │
│  │  │  WAL           │ │  │  │  meta.json     │ │                 │
│  │  │  (预写日志)    │ │  │  │  (元数据)       │ │                 │
│  │  └────────────────┘ │  │  └────────────────┘ │                 │
│  └──────────────────────┘  └──────────────────────┘                 │
│                                                                     │
│  时间轴: ─────────────────────────────────────────────────────►     │
│         [新数据写入] [Head]  [Block-1] [Block-2] [Block-3] ...     │
│         ◄── 2h ──►  ◄── 2h ►◄── 2h ►◄── 2h ►                       │
│                                                                     │
│  Compaction (压实):                                                  │
│  多个 2h Block → 合并为 1 个更大 Block                                │
│  [2h][2h][2h] → [6h] → [18h] → ... 最终形成 1 个 Block 覆盖更长时间  │
│                                                                     │
│  Retention (保留):                                                   │
│  超过 retention_time (默认15天) 的 Block 被删除                       │
└─────────────────────────────────────────────────────────────────────┘
```

**关键存储概念**：

```
1. WAL (Write-Ahead Log)
   - 写入先记 WAL，再写入内存
   - 崩溃后通过 WAL 恢复
   - 类比 MySQL redo log

2. Head Block (内存)
   - 最新 2 小时数据在内存
   - 超过 2h → 持久化为磁盘 Block
   - 内存中只保留 chunk 引用

3. Persistent Block (磁盘)
   - 每个 Block 覆盖 2h 时间范围
   - 包含: chunks/ + index/ + meta.json
   - 只读，不可修改

4. Index (倒排索引)
   - 从标签到时序 ID 的反向映射
   - 支持 label="value" 快速查找
   - 类比 Elasticsearch 的倒排索引

5. Chunk
   - 一个时序在一段时间内的数据点集合
   - 默认每个 chunk 最多 120 个点
   - 使用 Gorilla 压缩算法（XOR 编码）
```

**Gorilla 压缩算法核心**：

```java
// Gorilla 压缩（Facebook 提出，Prometheus TSDB 借鉴）
// 专门针对时序数据的压缩方案

// 1. 时间戳压缩（Delta of Delta）
//   连续点之间的时间间隔通常是固定的
//   只需存储时间间隔的变化的变化

// 2. 值压缩（XOR 编码）
//   相邻数据点的值通常变化不大
//   只需存储 XOR 后的有效位

// 示例：
// 原始数据: 120.5, 120.6, 120.7, 120.8
// XOR 压缩后只需要存很小的差异位
// 
// 实测效果：10 字节/点 → 1.37 字节/点（约 7x 压缩率）
```

### 2.6 Prometheus 高可用方案

```
方案一：基本高可用（最常用）
┌─────────────┐     ┌─────────────┐
│ Prometheus  │     │ Prometheus  │
│   Node-1   │     │   Node-2   │    ← 两个实例完全相同
│  (active)  │     │  (active)  │       采集相同目标
└──────┬──────┘     └──────┬──────┘       独立存储
       │                    │
       └────────┬───────────┘
                │
         ┌──────▼──────┐
         │   Grafana   │  ← Grafana 配置两个数据源
         │  (去重查询)  │     查询时去重
         └─────────────┘

  优势：简单，双活，任何一个挂了另一个可用
  劣势：存储独立，历史数据在故障后可能不一致

方案二：远程存储（长期存储 + 高可用）
┌─────────────┐     ┌─────────────┐
│ Prometheus  │     │ Prometheus  │
│   Node-1   │     │   Node-2   │
└──────┬──────┘     └──────┬──────┘
       │  Remote Write      │  Remote Write
       └────────┬───────────┘
                │
         ┌──────▼──────┐
         │   Thanos    │  ← 远程存储 + 全局查询
         │  / Cortex   │     对象存储(S3/GCS)
         │  / VictoriaMetrics │
         └─────────────┘

  优势：长期存储，全局视图，高可用
  劣势：架构复杂

方案三：Thanos 方案（业界主流）
┌─────────────────────────────────────────────┐
│                 Thanos 架构                   │
│                                             │
│  ┌────────────┐    ┌────────────┐           │
│  │ Prometheus │    │ Prometheus │           │
│  │  + Sidecar │    │  + Sidecar │  ← Sidecar│
│  │  (Thanos)  │    │  (Thanos)  │    上传   │
│  └─────┬──────┘    └──────┬─────┘    到S3   │
│        │                   │               │
│        └─────────┬─────────┘               │
│                  │                          │
│          ┌───────▼───────┐                 │
│          │   Thanos      │                 │
│          │   Store       │  ← 从 S3 读取   │
│          └───────┬───────┘                 │
│                  │                          │
│          ┌───────▼───────┐                 │
│          │   Thanos      │  ← 全局查询     │
│          │   Query       │    合并         │
│          └───────┬───────┘                 │
│                  │                          │
│          ┌───────▼───────┐                 │
│          │   Grafana     │                 │
│          └───────────────┘                 │
│                                             │
│  ┌──────────────────┐                      │
│  │  Object Storage  │  ← S3/GCS/MinIO     │
│  │  (长期存储)      │     压缩后的 Block    │
│  └──────────────────┘                      │
│                                             │
│  ┌──────────────────┐                      │
│  │  Thanos Compact  │  ← 下采样+压实        │
│  └──────────────────┘     5m → 1h → 1d     │
│                                             │
│  ┌──────────────────┐                      │
│  │  Thanos Ruler    │  ← 分布式告警评估      │
│  └──────────────────┘                      │
└─────────────────────────────────────────────┘
```

---

## 第三章 Logging 日志体系 — ELK/EFK 深度剖析

### 3.1 ELK 架构演进

```
第一代：基础 ELK
┌──────┐    ┌──────────┐    ┌───────────────┐    ┌──────────┐
│ App  │───►│ Logstash │───►│ Elasticsearch │───►│  Kibana  │
│ Logs │    │ (采集+    │    │  (存储+搜索)   │    │ (可视化)  │
└──────┘    │  处理)    │    └───────────────┘    └──────────┘
            └──────────┘
  问题：Logstash JVM 太重，每台机器部署消耗资源大

第二代：ELK + Kafka 缓冲
┌──────┐    ┌──────────┐    ┌───────┐    ┌──────────┐    ┌───────────────┐    ┌──────────┐
│ App  │───►│ Filebeat │───►│ Kafka │───►│ Logstash │───►│ Elasticsearch │───►│  Kibana  │
│ Logs │    │ (轻量    │    │(缓冲) │    │ (处理)   │    │  (存储+搜索)   │    │ (可视化)  │
└──────┘    │  采集)    │    └───────┘    └──────────┘    └───────────────┘    └──────────┘
            └──────────┘
  优势：Kafka 削峰，Logstash 集中处理
  问题：Logstash 仍是瓶颈，JVM 消耗大

第三代：EFK（Fluentd 替代 Logstash）
┌──────┐    ┌──────────┐    ┌───────────────┐    ┌──────────┐
│ App  │───►│ Fluentd  │───►│ Elasticsearch │───►│  Kibana  │
│ Logs │    │ /Fluent  │    │  (存储+搜索)   │    │ (可视化)  │
└──────┘    │  Bit     │    └───────────────┘    └──────────┘
            │ (轻量    │
            │  Ruby/C) │
            └──────────┘
  优势：Fluentd Ruby 更轻，Fluent Bit C 语言更省资源

第四代：云原生 EFK + Kafka（生产推荐）
┌──────┐    ┌───────────┐    ┌───────┐    ┌──────────┐    ┌───────────────┐    ┌──────────┐
│ App  │───►│ Fluent    │───►│ Kafka │───►│ Fluentd  │───►│ Elasticsearch │───►│  Kibana  │
│ Logs │    │ Bit       │    │(缓冲) │    │ /Logstash│    │  (存储+搜索)   │    │ (可视化)  │
│      │    │ (DaemonSet)│   └───────┘    │ (集中处理)│    └───────────────┘    └──────────┘
└──────┘    └───────────┘                 └──────────┘
  优势：Fluent Bit 每节点部署(DaemonSet)，Kafka 缓冲，Fluentd 集中处理
```

### 3.2 Elasticsearch 存储原理（日志视角）

```
日志写入 Elasticsearch 的完整路径:

App 日志: "2024-01-15 14:23:45 ERROR OrderService userId=12345 订单创建失败: 库存不足"
           │
           ▼
    ┌──────────────┐
    │  Fluent Bit  │  ← 采集 + 解析为 JSON
    │  (Parser)    │
    └──────┬───────┘
           │
           │  {"timestamp":"2024-01-15T14:23:45Z",
           │   "level":"ERROR",
           │   "service":"OrderService",
           │   "userId":"12345",
           │   "message":"订单创建失败: 库存不足"}
           ▼
    ┌──────────────┐
    │Elasticsearch │  ← 写入 ES
    │   Node       │
    │              │
    │  ┌────────┐  │
    │  │ Index  │  │  ← logstash-2024.01.15 (按天索引)
    │  │        │  │
    │  │ ┌────┐ │  │
    │  │ │Shard│ │  │  ← 分片（水平切分）
    │  │ │0   │ │  │
    │  │ │     │ │  │
    │  │ │ ┌──┐│ │  │
    │  │ │ │Seg││ │  │  ← Segment（倒排索引文件，不可变）
    │  │ │ │ment││ │  │
    │  │ │ └──┘│ │  │
    │  │ └────┘ │  │
    │  └────────┘  │
    └──────────────┘
```

**Elasticsearch 日志索引管理**：

```json
// ILM (Index Lifecycle Management) 策略
PUT _ilm/policy/logs_policy
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_size": "50gb",        // 50GB 滚动
            "max_age": "1d",            // 或 1 天滚动
            "max_docs": 100000000      // 或 1 亿条滚动
          },
          "set_priority": { "priority": 100 }
        }
      },
      "warm": {
        "min_age": "3d",              // 3 天后转为 warm
        "actions": {
          "shrink": { "number_of_shards": 1 },  // 缩减分片
          "forcemerge": { "max_num_segments": 1 }, // 强制合并
          "set_priority": { "priority": 50 }
        }
      },
      "cold": {
        "min_age": "7d",              // 7 天后转为 cold
        "actions": {
          "freeze": {}                 // 冻结索引，减少内存
        }
      },
      "delete": {
        "min_age": "30d",             // 30 天后删除
        "actions": {
          "delete": {}
        }
      }
    }
  }
}

// Index Template
PUT _index_template/logs_template
{
  "index_patterns": ["logs-*"],
  "template": {
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 1,
      "index.lifecycle.name": "logs_policy",
      "index.refresh_interval": "5s"
    },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "level": { "type": "keyword" },
        "service": { "type": "keyword" },
        "traceId": { "type": "keyword" },
        "message": { "type": "text", "analyzer": "ik_max_word" },
        "userId": { "type": "keyword" }
      }
    }
  }
}
```

### 3.3 Logstash 采集与处理管道

```
Logstash 处理管道 (Pipeline):

Input → Filter → Output

┌──────────┐     ┌──────────────────────┐     ┌──────────────┐
│  Input   │────►│      Filter          │────►│   Output     │
│  (采集)  │     │      (处理)          │     │   (输出)     │
└──────────┘     └──────────────────────┘     └──────────────┘

Input 插件:           Filter 插件:              Output 插件:
- beats              - grok (正则解析)         - elasticsearch
- kafka              - mutate (字段修改)       - kafka
- file               - date (时间解析)         - file
- tcp/udp            - json                    - stdout
- syslog             - geoip (IP→地理位置)     - s3
- redis              - useragent (UA解析)      - redis
                     - ruby (Ruby代码处理)
```

```ruby
# logstash.conf 示例：日志采集和处理
input {
  beats {
    port => 5044
  }
}

filter {
  # 解析 JSON 格式日志
  json {
    source => "message"
    remove_field => ["message"]
  }
  
  # 解析时间字段
  date {
    match => ["timestamp", "yyyy-MM-dd HH:mm:ss.SSS"]
    target => "@timestamp"
  }
  
  # 根据日志级别添加字段
  mutate {
    add_field => {
      "env" => "production"
    }
    convert => {
      "duration" => "float"
    }
  }
  
  # 使用 Grok 解析非结构化日志
  grok {
    match => {
      "message" => "%{TIMESTAMP_ISO8601:log_time} %{LOGLEVEL:log_level} %{JAVACLASS:logger} - %{GREEDYDATA:log_message}"
    }
  }
  
  # 根据 traceId 添加链路追踪关联
  if [traceId] {
    mutate {
      add_field => { "has_trace" => "true" }
    }
  }
}

output {
  elasticsearch {
    hosts => ["es-node1:9200", "es-node2:9200", "es-node3:9200"]
    index => "logs-%{service}-%{+YYYY.MM.dd}"
    user => "elastic"
    password => "${ES_PASSWORD}"
  }
}
```

### 3.4 Fluentd / Fluent Bit 轻量采集

```
Fluentd vs Fluent Bit:

                    Fluentd                  Fluent Bit
                ┌──────────────┐         ┌──────────────┐
  语言           │   Ruby       │         │     C        │
  内存           │  ~40MB       │         │   ~450KB     │
  吞吐量         │  ~5k events/s│         │  ~50k/s     │
  插件           │  800+ 插件   │         │  70+ 插件   │
  定位           │  聚合器      │         │  采集器      │
  部署           │  集中部署    │         │  DaemonSet  │
                │              │         │  每节点部署  │
                └──────────────┘         └──────────────┘

推荐架构：Fluent Bit (DaemonSet) → Fluentd (StatefulSet) → ES
```

```yaml
# Fluent Bit 配置示例 (fluent-bit.conf)
[SERVICE]
    Flush         5          # 5 秒刷新一次
    Log_Level    info
    Parsers_File parsers.conf

[INPUT]
    Name         tail
    Path         /var/log/containers/*.log
    Parser       docker
    Tag          kube.*
    Mem_Buf_Limit 50MB      # 内存缓冲限制

[FILTER]
    Name         kubernetes
    Match        kube.*
    Kube_URL     https://kubernetes.default.svc:443
    Merge_Log    true                    # 合并多行 JSON 日志
    K8S-Logging.Parser  on               # 使用容器注解指定 Parser
    K8S-Logging.Exclude on               # 使用容器注解排除日志

[OUTPUT]
    Name         es
    Match        kube.*
    Host         elasticsearch.logging.svc.cluster.local
    Port         9200
    Index        logs
    Type         _doc
    Retry_Limit  5
    Buffer_Size  10MB
```

### 3.5 结构化日志与 MDC

```java
// === 非结构化日志（反模式）===
log.info("User " + userId + " created order " + orderId + " for " + amount + " yuan");
// 问题：无法搜索、无法解析、无法关联 TraceID

// === 结构化日志（推荐）===
// 使用 JSON 格式，每个字段独立

// SLF4J + Logback JSON 格式
log.info("User created order")
    .addKeyValue("userId", userId)
    .addKeyValue("orderId", orderId)
    .addKeyValue("amount", amount)
    .addKeyValue("traceId", MDC.get("traceId"))
    .log();

// 输出：
// {"timestamp":"2024-01-15T14:23:45.123Z",
//  "level":"INFO",
//  "logger":"com.example.OrderService",
//  "message":"User created order",
//  "userId":"12345",
//  "orderId":"ORD-2024-001",
//  "amount":99.50,
//  "traceId":"abc123def456"}

// === MDC (Mapped Diagnostic Context) 实现日志关联 ===

@Component
public class TraceLoggingFilter extends OncePerRequestFilter {
    
    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                     HttpServletResponse response,
                                     FilterChain filterChain) 
            throws ServletException, IOException {
        // 从请求头获取 TraceID（由链路追踪组件注入）
        String traceId = request.getHeader("X-Trace-Id");
        if (traceId == null) {
            traceId = generateTraceId();
        }
        
        // 放入 MDC
        MDC.put("traceId", traceId);
        MDC.put("userId", getCurrentUserId());
        MDC.put("requestId", UUID.randomUUID().toString());
        
        try {
            filterChain.doFilter(request, response);
        } finally {
            MDC.clear();  // 重要：防止线程池复用导致数据错乱
        }
    }
}

// logback.xml 配置 MDC 输出
// <pattern>
//   {"timestamp":"%d","level":"%level","logger":"%logger",
//    "traceId":"%X{traceId}","userId":"%X{userId}",
//    "message":"%msg"}%n
// </pattern>
```

**MDC 底层原理**：

```java
// MDC 底层使用 ThreadLocal 存储
public class MDC {
    // Logback 的 MDC 实现
    static ThreadLocal<Map<String, String>> mdcAdapter = 
        ThreadLocal.withInitial(HashMap::new);
    
    public static void put(String key, String val) {
        mdcAdapter.get().put(key, val);
    }
    
    public static String get(String key) {
        return mdcAdapter.get().get(key);
    }
    
    public static void clear() {
        mdcAdapter.get().clear();
    }
}

// ⚠️ ThreadLocal 在线程池环境下的陷阱：
// 线程池复用线程 → ThreadLocal 数据残留 → 日志错乱
// 解决：finally 块中必须 MDC.clear()
// 线程池 submit 时需要传递 MDC 上下文：

public class MdcTaskDecorator implements TaskDecorator {
    @Override
    public Runnable decorate(Runnable runnable) {
        Map<String, String> context = MDC.getCopyOfContextMap();
        return () -> {
            Map<String, String> previous = MDC.getCopyOfContextMap();
            if (context != null) {
                MDC.setContextMap(context);
            }
            try {
                runnable.run();
            } finally {
                if (previous != null) {
                    MDC.setContextMap(previous);
                } else {
                    MDC.clear();
                }
            }
        };
    }
}

// 线程池配置
@Bean
public ExecutorService executorService() {
    ThreadPoolExecutor executor = new ThreadPoolExecutor(
        10, 50, 60, TimeUnit.SECONDS, new LinkedBlockingQueue<>(100));
    // 使用装饰器传递 MDC
    return new ContextAwareExecutorService(executor, new MdcTaskDecorator());
}
```

### 3.6 日志采样与脱敏

```java
// === 日志采样：高 QPS 场景下降低日志量 ===

// 方案1：基于比例采样
@Component
public class SampledLogger {
    private final AtomicLong counter = new AtomicLong(0);
    private final double sampleRate = 0.1;  // 采样 10%
    
    public void logAccess(String path, long duration) {
        if (counter.getAndIncrement() % 100 < 10) {  // 每 100 条记 10 条
            log.info("Access sampled")
                .addKeyValue("path", path)
                .addKeyValue("duration", duration)
                .addKeyValue("sampled", true)
                .log();
        }
    }
}

// 方案2：基于条件采样（只记慢请求和错误）
public void logRequest(RequestContext ctx) {
    boolean isError = ctx.getStatus() >= 500;
    boolean isSlow = ctx.getDuration() > 1000;  // >1s
    
    if (isError || isSlow || shouldSample()) {
        log.info("Request completed")
            .addKeyValue("status", ctx.getStatus())
            .addKeyValue("duration", ctx.getDuration())
            .log();
    }
}

// === 日志脱敏 ===

// 方案1：Logback 自定义 Converter
public class SensitiveDataConverter extends ClassicConverter {
    private static final Pattern PHONE_PATTERN = 
        Pattern.compile("(\\d{3})\\d{4}(\\d{4})");
    private static final Pattern ID_CARD_PATTERN = 
        Pattern.compile("(\\d{4})\\d{10}(\\d{4})");
    private static final Pattern EMAIL_PATTERN = 
        Pattern.compile("(\\w{2})\\w*@(\\w+\\.\\w+)");
    
    @Override
    public String convert(ILoggingEvent event) {
        String msg = event.getFormattedMessage();
        msg = PHONE_PATTERN.matcher(msg).replaceAll("$1****$2");
        msg = ID_CARD_PATTERN.matcher(msg).replaceAll("$1**********$2");
        msg = EMAIL_PATTERN.matcher(msg).replaceAll("$1***@$2");
        return msg;
    }
}

// 方案2：自定义日志工具类
public class SecureLogger {
    public static String maskPhone(String phone) {
        if (phone == null || phone.length() < 7) return phone;
        return phone.substring(0, 3) + "****" + phone.substring(7);
    }
    
    public static String maskIdCard(String idCard) {
        if (idCard == null || idCard.length() < 8) return idCard;
        return idCard.substring(0, 4) + "**********" + idCard.substring(14);
    }
    
    public static String maskEmail(String email) {
        if (email == null || !email.contains("@")) return email;
        int at = email.indexOf("@");
        if (at <= 2) return email;
        return email.substring(0, 2) + "***" + email.substring(at);
    }
}

// 使用
log.info("User registered")
    .addKeyValue("phone", SecureLogger.maskPhone(user.getPhone()))
    .addKeyValue("email", SecureLogger.maskEmail(user.getEmail()))
    .log();
```

---

## 第四章 Tracing 分布式链路追踪深度剖析

### 4.1 Google Dapper 论文核心思想

Google 在 2010 年发表的 Dapper 论文是分布式追踪的奠基之作，几乎所有主流追踪系统（Zipkin、Jaeger、SkyWalking、Pinpoint）都借鉴了 Dapper 的设计。

**Dapper 的核心设计目标**：

```
1. 极低开销：追踪开销 < 生产环境 1% CPU
2. 对应用透明：开发者不需要修改业务代码
3. 可扩展：支持新服务自动接入
4. 采样：不可能记录所有请求，需要采样策略

Dapper 的核心概念:

┌──────────────────────────────────────────────────────────┐
│                     Trace（一次完整调用链）                  │
│                                                          │
│  Span A (Gateway)                                         │
│  ├── Span B (OrderService.createOrder)                   │
│  │   ├── Span C (InventoryService.deduct)               │
│  │   ├── Span D (PaymentService.charge)                 │
│  │   │   └── Span E (PayGateway.callback)              │
│  │   └── Span F (NotificationService.send)              │
│  └── Span G (UserService.getProfile)                     │
│                                                          │
│  每个 Span 包含:                                          │
│  - traceId: 全局唯一 Trace ID                            │
│  - spanId: 当前 Span 的唯一 ID                           │
│  - parentSpanId: 父 Span 的 ID                           │
│  - operationName: 操作名称                               │
│  - startTime / duration: 起始时间和耗时                   │
│  - tags: 标签 (如 http.status_code, db.statement)       │
│  - logs: 事件日志 (如异常信息)                            │
│  - baggage: 跨进程传递的上下文                            │
└──────────────────────────────────────────────────────────┘
```

**Span 树形结构**：

```
    时间轴 ──────────────────────────────────────────────►
    
    ┌───── Span A: Gateway.handleRequest (120ms) ──────────────┐
    │                                                          │
    │  ┌── Span B: OrderService.createOrder (80ms) ──────┐    │
    │  │                                                  │    │
    │  │  ┌── Span C: Inventory.deduct (20ms) ──┐        │    │
    │  │  └──────────────────────────────────────┘        │    │
    │  │                                                  │    │
    │  │  ┌── Span D: Payment.charge (40ms) ─────┐       │    │
    │  │  │  ┌── Span E: PayGW.callback (10ms) ┐  │       │    │
    │  │  │  └──────────────────────────────────┘  │       │    │
    │  │  └────────────────────────────────────────┘       │    │
    │  │                                                  │    │
    │  │  ┌── Span F: Notification.send (15ms) ──┐        │    │
    │  │  └────────────────────────────────────────┘        │    │
    │  └──────────────────────────────────────────────────┘    │
    │                                                          │
    │  ┌── Span G: UserService.getProfile (25ms) ────────┐    │
    │  └──────────────────────────────────────────────────┘    │
    └──────────────────────────────────────────────────────────┘
```

### 4.2 Span/Trace 数据模型

```java
// OpenTracing 标准的 Span 数据模型

public class Span {
    // === 核心标识 ===
    private String traceId;           // 全局 Trace ID
    private String spanId;            // 当前 Span ID
    private String parentSpanId;       // 父 Span ID (根 Span 为 null)
    
    // === 时间信息 ===
    private long startTimeMicros;     // 起始时间（微秒）
    private long durationMicros;      // 持续时间（微秒）
    
    // === 描述信息 ===
    private String operationName;     // 操作名称 (如 "OrderService.createOrder")
    private Map<String, String> tags; // 标签 (如 "http.status_code"="200")
    private List<LogEntry> logs;      // 事件日志 (如异常栈)
    
    // === 上下文 ===
    private SpanContext context;       // 上下文 (traceId + spanId + baggage)
    private List<Span> children;       // 子 Span 列表
}

public class SpanContext {
    private String traceId;           // Trace ID
    private String spanId;            // Span ID
    private Map<String, String> baggage;  // 跨进程传递的额外信息
}

// Baggage 示例：跨服务传递用户信息
// baggage: {"userId": "12345", "tenantId": "acme", "canary": "true"}
// 每个下游服务都能读取 baggage 中的信息
// ⚠️ Baggage 会增加请求头大小，不要放太多数据
```

**Span 生命周期**：

```
┌─────────────────────────────────────────────────────────┐
│                    Span 生命周期                         │
│                                                        │
│  1. 创建 Span                                          │
│     tracer.buildSpan("operationName")                  │
│           .asChildOf(parentSpan)                       │
│           .withTag("key", "value")                     │
│           .start();                                    │
│                                                        │
│  2. 记录标签 (Tags)                                     │
│     span.setTag("http.status_code", 200);              │
│     span.setTag("http.url", "/api/orders");            │
│     span.setTag("error", false);                        │
│                                                        │
│  3. 记录事件 (Logs)                                     │
│     span.log(Map.of("event", "cache.miss"));           │
│     span.log(System.currentTimeMillis(),              │
│               Map.of("event", "error",                 │
│                       "error.object", exception));     │
│                                                        │
│  4. 结束 Span                                          │
│     span.finish();  // 记录结束时间，计算 duration       │
│                                                        │
│  5. 上报 Span (异步)                                    │
│     reporter.report(span);  // 发送到后端存储            │
└─────────────────────────────────────────────────────────┘
```

### 4.3 上下文传播机制

**这是分布式追踪最核心的机制：如何将 TraceID 跨进程/跨服务传递？**

```
服务 A 调用服务 B 时，Trace 上下文传播:

┌─────────────┐                    ┌─────────────┐
│  Service A  │   HTTP/RPC 请求    │  Service B  │
│             │───────────────────►│             │
│  Span: A    │  Headers:          │  Span: B    │
│  traceId:1  │  traceparent:       │  traceId:1 │
│  spanId:A   │  00-1-A-01          │  spanId:B  │
│             │  (W3C Trace Context)│  parent:A  │
│             │                     │             │
│  1.创建SpanA │                     │  2.提取上下文│
│  3.注入上下文 │                     │  4.创建SpanB│
│             │                     │  5.执行业务 │
│             │◄───────────────────│             │
│  6.完成SpanA│   HTTP 响应         │  7.完成SpanB│
└─────────────┘                    └─────────────┘
```

**三种上下文传播格式**：

```
1. W3C Trace Context (推荐，标准格式)
   Header: traceparent
   格式: 00-{trace-id}-{parent-id}-{trace-flags}
   示例: traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
                                          │                     │           │
                                    trace-id(32hex)        parent-id(16hex)  flags

   Header: tracestate (可选，厂商扩展)
   tracestate: vendor1=value1,vendor2=value2

2. B3 (Zipkin 格式，向后兼容)
   X-B3-TraceId: 80f198ee56343ba864fe8b2a57d3eff7
   X-B3-SpanId:  e457b5a2e4d86bd1
   X-B3-ParentSpanId: e457b5a2e4d86bd1
   X-B3-Sampled: 1

3. Jaeger 格式
   uber-trace-id: {trace-id}:{span-id}:{parent-span-id}:{flags}
```

**Java 代码实现上下文传播**：

```java
// === HTTP 调用时注入上下文 ===

// 使用 OpenTelemetry SDK
public class HttpClientInterceptor implements Interceptor {
    private final Tracer tracer = GlobalOpenTelemetry.getTracer("http-client");
    
    @Override
    public Response intercept(Chain chain) throws IOException {
        Request request = chain.request();
        
        // 创建客户端 Span
        Span span = tracer.spanBuilder("HTTP " + request.method())
            .setSpanKind(SpanKind.CLIENT)
            .setAttribute("http.method", request.method())
            .setAttribute("http.url", request.url().toString())
            .startSpan();
        
        try (Scope scope = span.makeCurrent()) {
            // 将上下文注入到 HTTP Headers
            Request.Builder requestBuilder = request.newBuilder();
            TextMapPropagator propagator = 
                GlobalOpenTelemetry.getPropagators()
                    .getTextMapPropagator(W3CTraceContextPropagator.INSTANCE);
            
            propagator.inject(Context.current(), requestBuilder, 
                (carrier, key, value) -> carrier.addHeader(key, value));
            
            Response response = chain.proceed(requestBuilder.build());
            
            span.setAttribute("http.status_code", response.code());
            if (response.code() >= 400) {
                span.setAttribute("error", true);
            }
            
            return response;
        } catch (Exception e) {
            span.recordException(e);
            span.setAttribute("error", true);
            throw e;
        } finally {
            span.end();
        }
    }
}

// === 服务端接收时提取上下文 ===

public class ServerInterceptor implements HandlerInterceptor {
    private final Tracer tracer = GlobalOpenTelemetry.getTracer("http-server");
    
    @Override
    public boolean preHandle(HttpServletRequest request, 
                             HttpServletResponse response, 
                             Object handler) {
        // 从 HTTP Headers 提取上下文
        Context parentContext = GlobalOpenTelemetry.getPropagators()
            .getTextMapPropagator()
            .extract(Context.current(), request, 
                new HttpServletRequestTextMapGetter());
        
        // 创建服务端 Span，继承父上下文
        Span span = tracer.spanBuilder(request.getRequestURI())
            .setParent(parentContext)
            .setSpanKind(SpanKind.SERVER)
            .setAttribute("http.method", request.getMethod())
            .setAttribute("http.url", request.getRequestURL().toString())
            .startSpan();
        
        // 将 Span 放入当前上下文
        try (Scope scope = span.makeCurrent()) {
            request.setAttribute("span", span);
            return true;
        }
    }
    
    @Override
    public void afterCompletion(HttpServletRequest request, 
                                HttpServletResponse response, 
                                Object handler, Exception ex) {
        Span span = Span.current();
        span.setAttribute("http.status_code", response.getStatus());
        if (ex != null) {
            span.recordException(ex);
            span.setAttribute("error", true);
        }
        span.end();
    }
}
```

**跨线程传播**：

```java
// 线程池场景下需要手动传递上下文
ExecutorService tracedExecutor = Context.current()
    .wrapExecutorService(originalExecutor);

// 或者使用 OpenTelemetry 的工具
ExecutorService executor = Executors.newCachedThreadPool();
// 提交任务时自动传递上下文
executor.submit(() -> {
    Span span = tracer.spanBuilder("async-task")
        .setParent(Context.current())  // 从当前上下文获取父 Span
        .startSpan();
    try (Scope scope = span.makeCurrent()) {
        // 执行异步任务
        doAsyncWork();
    } finally {
        span.end();
    }
});
```

### 4.4 采样策略

**为什么需要采样？**

```
全量采集的问题:
  - 10000 QPS → 每秒 10000 个 Trace → 每天 8.6 亿条
  - 存储成本极高
  - 网络传输压力大
  - 大部分 Trace 是正常的，价值低

解决方案: 采样 (Sampling)

采样策略分类:

┌──────────────────────────────────────────────────────────────┐
│                      采样策略分类                              │
├───────────────────┬──────────────────┬──────────────────────┤
│  Head-based       │  Tail-based      │  Hybrid              │
│  (头部采样)       │  (尾部采样)      │  (混合采样)           │
├───────────────────┼──────────────────┼──────────────────────┤
│ 入口处决定        │ 执行完后决定      │ 头部+尾部结合         │
│ 全链路统一        │ 可按结果决定      │                      │
│                   │                   │                      │
│ 优点:             │ 优点:             │ 优点:                 │
│ - 简单            │ - 能确保采到      │ - 兼顾性能和完整性     │
│ - 低开销          │   错误和慢请求    │                      │
│ - 全链路一致       │                   │ 缺点:                 │
│                   │ 缺点:             │ - 实现复杂            │
│ 缺点:             │ - 需要缓冲全链路  │                      │
│ - 可能漏采错误    │ - 内存开销大      │                      │
│ - 无法按结果决定  │ - 实现复杂        │                      │
├───────────────────┼──────────────────┼──────────────────────┤
│ 适用:             │ 适用:             │ 适用:                 │
│ 高QPS、简单场景   │ 对可观测性要求高  │ 大型分布式系统        │
│                   │ 的核心系统        │                      │
└───────────────────┴──────────────────┴──────────────────────┘
```

**头部采样实现**：

```java
// 头部采样：在请求入口决定是否采样
// 一旦决定采样，整个链路都会被采

public class HeadBasedSampler {
    private final double samplingRate;  // 采样率，如 0.1 = 10%
    
    public boolean shouldSample(String traceId) {
        // 使用 traceId 做哈希，确保同一 traceId 结果一致
        long hash = traceId.hashCode();
        return Math.abs(hash % 100) < samplingRate * 100;
    }
}

// OpenTelemetry 内置实现
Sampler sampler = Sampler.traceIdRatioBased(0.1);  // 10% 采样率
// 或固定比例
Sampler alwaysOn = Sampler.alwaysOn();   // 全采样（开发环境）
Sampler alwaysOff = Sampler.alwaysOff(); // 不采样
```

**尾部采样实现**：

```yaml
# 尾部采样：等整个 Trace 完成后，根据结果决定是否上报
# Jaeger/Tempo/OTel Collector 支持

# OpenTelemetry Collector 尾部采样配置
# otel-collector-config.yaml
processors:
  tail_sampling:
    decision_wait: 30s        # 等待 30 秒收集完整 Trace
    num_traces: 50000         # 内存中缓冲的 Trace 数
    expected_new_traces_per_sec: 1000
    
    policies:
      # 策略1：所有错误请求都采
      - name: errors
        type: status_code
        status_code:
          status_codes: [ERROR]
      
      # 策略2：慢请求都采（>500ms）
      - name: slow
        type: latency
        latency:
          threshold_ms: 500
      
      # 策略3：正常请求采 10%
      - name: normal_sample
        type: probabilistic
        probabilistic:
          sampling_percentage: 10
```

### 4.5 SkyWalking 架构与源码剖析

SkyWalking 是国产 APM 系统（Apache 顶级项目），在 Java 生态中使用最广泛。

```
┌──────────────────────────────────────────────────────────────────┐
│                    SkyWalking 架构                                │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │                    Probe（探针层）                        │     │
│  │                                                        │     │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐               │     │
│  │  │ Java    │  │  .NET   │  │ Node.js │  ...           │     │
│  │  │ Agent   │  │  Agent  │  │  Agent  │               │     │
│  │  │(无侵入) │  │         │  │         │               │     │
│  │  └────┬────┘  └────┬────┘  └────┬────┘               │     │
│  └───────┼────────────┼────────────┼─────────────────────┘     │
│          │            │            │                            │
│          │   gRPC     │            │                            │
│          ▼            ▼            ▼                            │
│  ┌────────────────────────────────────────────────────────┐     │
│  │                Backend（后端处理层）                     │     │
│  │                                                        │     │
│  │  ┌──────────────────────────────────────────────────┐  │     │
│  │  │  OAP Server (Observability Analysis Platform)     │  │     │
│  │  │                                                  │  │     │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐       │  │     │
│  │  │  │ Receiver │  │ Analyzer │  │ Exporter │       │  │     │
│  │  │  │ (接收)   │  │ (分析)   │  │ (导出)   │       │  │     │
│  │  │  └──────────┘  └──────────┘  └──────────┘       │  │     │
│  │  └──────────────────────────────────────────────────┘  │     │
│  └────────────────────────┬───────────────────────────────┘     │
│                           │                                      │
│          ┌────────────────┼────────────────┐                    │
│          │                │                │                    │
│  ┌───────▼───────┐ ┌──────▼──────┐ ┌──────▼────────┐          │
│  │ Elasticsearch  │ │   MySQL     │ │   BanyanDB    │          │
│  │   (存储)       │ │   (存储)    │ │   (自研存储)   │          │
│  └───────────────┘ └─────────────┘ └───────────────┘          │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    UI（展示层）                          │  │
│  │  ┌─────────┐  ┌──────────┐  ┌───────────┐             │  │
│  │  │ Trace   │  │ Topology │  │  Alarm   │             │  │
│  │  │ 查询    │  │  拓扑图   │  │  告警    │             │  │
│  │  └─────────┘  └──────────┘  └───────────┘             │  │
│  └──────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

**SkyWalking Java Agent 核心原理：ByteBuddy 字节码增强**

```java
// SkyWalking Agent 使用 ByteBuddy 在类加载时修改字节码
// 实现无侵入式埋点

public class SkyWalkingAgent {
    public static void premain(String agentArgs, Instrumentation instrumentation) {
        // 使用 ByteBuddy 创建 AgentBuilder
        AgentBuilder agentBuilder = new AgentBuilder.Default()
            .type(ElementMatchers.named("org.springframework.web.servlet.DispatcherServlet"))
            .transform((builder, typeDescription, classLoader, module) -> {
                return builder
                    .method(ElementMatchers.named("doDispatch"))
                    .intercept(MethodDelegation.to(new ServletInterceptor()));
            });
        
        agentBuilder.installOn(instrumentation);
    }
}

// 拦截器：自动创建 Span
public class ServletInterceptor {
    @RuntimeType
    public Object intercept(
            @This Object obj,
            @AllArguments Object[] allArguments,
            @SuperCall Callable<?> callable) throws Exception {
        
        HttpServletRequest request = (HttpServletRequest) allArguments[0];
        
        // 创建 Entry Span（服务端 Span）
        ContextCarrier carrier = new ContextCarrier();
        // 从请求头提取上游传递的上下文
        CarrierItem items = carrier.items();
        while (items.hasNext()) {
            items = items.next();
            items.setHeadValue(request.getHeader(items.getHeadKey()));
        }
        
        // 创建 Span
        AbstractSpan span = ContextManager.createEntrySpan(
            request.getRequestURI(), carrier);
        span.tag("http.method", request.getMethod());
        span.tag("http.url", request.getRequestURL().toString());
        
        try {
            Object result = callable.call();
            span.tag("http.status_code", 
                String.valueOf(((HttpServletResponse) allArguments[1]).getStatus()));
            return result;
        } catch (Exception e) {
            span.log(e);  // 记录异常
            span.errorOccurred();
            throw e;
        } finally {
            ContextManager.stopSpan();  // 结束 Span
        }
    }
}
```

**SkyWalking 插件机制**：

```
SkyWalking 通过插件（Plugin）支持各种框架:

┌─────────────────────────────────────────────────────────┐
│                SkyWalking 插件体系                       │
│                                                         │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐      │
│  │ Spring MVC  │ │   Dubbo     │ │  MyBatis    │      │
│  │ Plugin      │ │  Plugin     │ │  Plugin     │      │
│  └─────────────┘ └─────────────┘ └─────────────┘      │
│                                                         │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐      │
│  │ HttpClient  │ │  Feign     │ │   Redis    │      │
│  │ Plugin      │ │  Plugin     │ │  Plugin     │      │
│  └─────────────┘ └─────────────┘ └─────────────┘      │
│                                                         │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐      │
│  │ Kafka       │ │ RabbitMQ    │ │ gRPC       │      │
│  │ Plugin      │ │  Plugin     │ │  Plugin     │      │
│  └─────────────┘ └─────────────┘ └─────────────┘      │
│                                                         │
│  插件定义文件: META-INF/skywalking-plugin.define        │
│  插件增强定义: xxx.enhance → 匹配类 → 拦截方法           │
└─────────────────────────────────────────────────────────┘

// 插件定义示例
// spring-mvc-annotation-5.x-plugin.define
name=Spring MVC Annotation Plugin
enhance.class=org.springframework.web.servlet.HandlerMethod
interceptor=org.apache.skywalking.plugin.spring.mvc
  .HandlerMethodInterceptor
enhance.method=invoke
```

### 4.6 Jaeger vs Zipkin vs SkyWalking 对比

| 维度 | Zipkin | Jaeger | SkyWalking |
|---|---|---|---|
| **起源** | Twitter (2012) | Uber (2015) | 中国 (2015) |
| **语言** | Java/Scala | Go | Java |
| **数据模型** | Zipkin Span | OpenTracing | 自研 + OpenTracing |
| **协议** | HTTP/Kafka | gRPC/HTTP | gRPC |
| **存储** | ES/MySQL/Cassandra | ES/Cassandra | ES/MySQL/BanyanDB |
| **采样** | 头部 | 头部+尾部 | 头部 |
| **无侵入** | 否，需手动埋点 | 否，需手动埋点 | 是，Java Agent 自动 |
| **UI** | 简洁 | 现代 | 功能丰富 |
| **拓扑图** | 无 | 无 | 有，服务拓扑 |
| **告警** | 无 | 无 | 有，内置告警 |
| **社区** | 活跃 | CNCF 毕业项目 | Apache 顶级项目 |
| **适合** | 简单场景 | 云原生 | Java 生态 |

```
选型建议：

如果使用 Java 技术栈 → SkyWalking（无侵入 Agent 最省心）
如果需要云原生标准 → Jaeger（CNCF 生态）
如果已有 ELK 基础 → Zipkin（轻量集成）
如果想统一标准 → OpenTelemetry + 任意后端
```

---

## 第五章 OpenTelemetry 统一标准

### 5.1 OTLP 协议设计

OpenTelemetry（简称 OTel）是 CNCF 主导的可观测性统一标准，合并了 OpenTracing 和 OpenMetrics 两个项目，目标是统一 Metrics/Logs/Traces 三大数据类型。

```
OpenTelemetry 的使命:

BEFORE (碎片化):
┌──────────┐  ┌──────────┐  ┌──────────┐
│OpenTracing│  │OpenMetrics│  │ 各家 SDK  │
│ (Tracing) │  │ (Metrics) │  │ 不兼容    │
└─────┬─────┘  └─────┬─────┘  └─────┬────┘
      │              │              │
      ▼              ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────┐
│  Jaeger   │  │Prometheus│  │Zipkin/SW │  ← 各自协议不兼容
└──────────┘  └──────────┘  └──────────┘

AFTER (统一):
┌──────────────────────────────────────────┐
│           OpenTelemetry SDK              │
│  统一 API + 统一数据模型 + 统一协议 OTLP  │
└──────────────────┬───────────────────────┘
                   │ OTLP (gRPC/HTTP)
                   ▼
┌──────────────────────────────────────────┐
│        OTel Collector (可选)             │
│   接收 → 处理 → 导出                     │
└─────┬──────────┬──────────┬──────────────┘
      │          │          │
      ▼          ▼          ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│Prometheus│ │ Jaeger   │ │   ES     │  ← 统一导出到任意后端
│ (Metrics)│ │ (Traces) │ │ (Logs)   │
└──────────┘ └──────────┘ └──────────┘
```

**OTLP 数据模型**：

```protobuf
// OTLP 协议基于 Protobuf 定义

// Trace 数据
message TracesData {
  repeated ResourceSpans resource_spans = 1;
}

message ResourceSpans {
  Resource resource = 1;          // 资源信息 (service.name, host.name)
  repeated ScopeSpans scope_spans = 2;
}

message Span {
  bytes trace_id = 1;            // Trace ID (16 bytes)
  bytes span_id = 2;             // Span ID (8 bytes)
  string trace_state = 3;        // tracestate (W3C)
  bytes parent_span_id = 4;      // 父 Span ID
  string name = 5;                // 操作名称
  SpanKind kind = 6;             // Span 类型 (SERVER/CLIENT/INTERNAL)
  fixed64 start_time_unix_nano = 7;  // 起始时间
  fixed64 end_time_unix_nano = 8;    // 结束时间
  repeated KeyValue attributes = 9;   // 标签
  repeated Event events = 11;        // 事件日志
  repeated Link links = 12;          // 关联链接
  SpanStatus status = 13;             // 状态
}

// Metrics 数据
message Metric {
  string name = 1;
  string description = 2;
  string unit = 3;
  oneof data {
    Gauge gauge = 5;
    Sum sum = 7;
    Histogram histogram = 9;
    ExponentialHistogram exponential_histogram = 10;
    Summary summary = 11;
  }
}
```

### 5.2 Instrumentation 自动埋点

```java
// OpenTelemetry 提供自动埋点 Agent（类似 SkyWalking）

// 启动命令
// java -javaagent:opentelemetry-javaagent.jar
//      -Dotel.service.name=order-service
//      -Dotel.exporter.otlp.endpoint=http://otel-collector:4317
//      -jar order-service.jar

// 自动埋点覆盖的组件:
// - HTTP: Spring MVC, JAX-RS, Servlet, HttpClient, OkHttp
// - RPC: gRPC, Dubbo
// - DB: JDBC, Hibernate, MyBatis
// - Cache: Redis(Jedis/Lettuce), Caffeine
// - MQ: Kafka, RabbitMQ, Pulsar
// - Logging: Logback, Log4j2 (注入 TraceID)
// - Others: Spring Scheduled, Thread Pool

// 手动埋点 API
public class OrderService {
    private static final Tracer tracer = 
        GlobalOpenTelemetry.getTracer("order-service");
    
    public Order createOrder(OrderRequest request) {
        // 手动创建 Span
        Span span = tracer.spanBuilder("OrderService.createOrder")
            .setAttribute("order.userId", request.getUserId())
            .setAttribute("order.amount", request.getAmount())
            .startSpan();
        
        try (Scope scope = span.makeCurrent()) {
            // 业务逻辑
            Order order = doCreateOrder(request);
            span.setAttribute("order.id", order.getId());
            return order;
        } catch (Exception e) {
            span.recordException(e);
            span.setAttribute("error", true);
            throw e;
        } finally {
            span.end();
        }
    }
    
    // 使用 @WithSpan 注解自动创建 Span
    @WithSpan("validateOrder")
    public boolean validateOrder(
            @SpanAttribute("orderId") String orderId) {
        // 自动创建 Span，方法参数自动标记为 attribute
        return validate(orderId);
    }
}
```

### 5.3 Collector 架构

```
┌──────────────────────────────────────────────────────────────────┐
│                OpenTelemetry Collector 架构                       │
│                                                                  │
│  Pipeline: Receivers → Processors → Exporters                    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │                     Receivers (接收)                    │     │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐         │     │
│  │  │ OTLP   │ │ Jaeger  │ │ Zipkin │ │Prometheus│        │     │
│  │  │ (gRPC) │ │ (gRPC)  │ │ (HTTP) │ │ (scrape)│        │     │
│  │  └────────┘ └────────┘ └────────┘ └────────┘         │     │
│  └────────────────────────────┬────────────────────────────┘     │
│                               │                                  │
│  ┌────────────────────────────▼────────────────────────────┐     │
│  │                   Processors (处理)                       │     │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │     │
│  │  │ Batch    │ │ Memory   │ │ Tail     │ │ Attribute│   │     │
│  │  │ (批量)   │ │ Limiter  │ │ Sampling │ │ (属性处理)│   │     │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘   │     │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │     │
│  │  │ Filter   │ │ Resource │ │ Span     │ │ Metrics  │   │     │
│  │  │ (过滤)   │ │ (资源)   │ │ Metrics  │ │ Transform│   │     │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘   │     │
│  └────────────────────────────┬────────────────────────────┘     │
│                               │                                  │
│  ┌────────────────────────────▼────────────────────────────┐     │
│  │                   Exporters (导出)                       │     │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐            │     │
│  │  │ OTLP   │ │ Jaeger  │ │ Zipkin │ │Prometheus│          │     │
│  │  └────────┘ └────────┘ └────────┘ └────────┘            │     │
│  │  ┌────────┐ ┌────────┐ ┌────────┐                       │     │
│  │  │ ES     │ │ Kafka   │ │ File   │                       │     │
│  │  └────────┘ └────────┘ └────────┘                       │     │
│  └─────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────┘
```

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 5s
    send_batch_size: 1000
  
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128
  
  # 尾部采样
  tail_sampling:
    decision_wait: 30s
    num_traces: 50000
    policies:
      - name: errors
        type: status_code
        status_code:
          status_codes: [ERROR]
      - name: slow
        type: latency
        latency:
          threshold_ms: 500
      - name: sample
        type: probabilistic
        probabilistic:
          sampling_percentage: 10

  # 资源属性处理
  resource:
    attributes:
      - key: deployment.environment
        value: production
        action: upsert

exporters:
  otlp:
    endpoint: tempo:4317
    tls:
      insecure: true
  
  prometheus:
    endpoint: 0.0.0.0:8889
  
  elasticsearch:
    endpoint: http://elasticsearch:9200
    logs_index: otel-logs

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, tail_sampling, batch]
      exporters: [otlp]
    
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [prometheus]
    
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [elasticsearch]
```

### 5.4 与 Prometheus/Jaeger/SkyWalking 的关系

```
OpenTelemetry 是"标准"，不是"后端":

┌──────────────────────────────────────────────┐
│            你的应用 (App)                    │
│  ┌──────────────────────────────────────┐   │
│  │    OpenTelemetry SDK / Agent         │   │
│  │  (统一采集: Traces+Metrics+Logs)     │   │
│  └──────────────┬───────────────────────┘   │
│                 │ OTLP                       │
└─────────────────┼────────────────────────────┘
                  │
         ┌────────▼────────┐
         │  OTel Collector  │  ← 统一收集、处理
         └───┬────┬────┬───┘
             │    │    │
     ┌───────▼──┐ │ ┌──▼───────┐
     │ Prometheu│ │ │  Jaeger  │  ← 各自专注自己擅长的
     │  us      │ │ │  /Tempo  │
     │ (Metrics)│ │ │ (Traces) │
     └──────────┘ │ └──────────┘
            ┌─────▼─────┐
            │    ES     │
            │  (Logs)   │
            └───────────┘

迁移路径:
  现有系统 → 不用急着换
  新系统 → 直接用 OTel SDK + 任意后端
  未来 → OTel 成为唯一标准，后端可随意切换
```

---

## 第六章 告警体系

### 6.1 Alertmanager 工作原理

```
┌─────────────────────────────────────────────────────────────────┐
│                   Alertmanager 工作流程                          │
│                                                                 │
│  ┌──────────────┐                                               │
│  │ Prometheus   │  按 evaluation_interval (15s) 评估告警规则      │
│  │ Server      │  rule: rate(http_errors[5m]) > 0.05            │
│  │             │  → 触发告警: FIRING 状态                        │
│  └──────┬──────┘  → 告警未触发: PENDING 状态 (持续 for 条件)     │
│         │                                                       │
│         │  POST /api/v1/alerts                                 │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │ Alertmanager │                                               │
│  │             │                                               │
│  │  1. 接收告警  │  ← 可能有多个 Prometheus 实例发送相同告警      │
│  │             │                                               │
│  │  2. 去重     │  ← 基于标签指纹去重                            │
│  │  (Dedup)    │     key = {alertname, instance, severity}     │
│  │             │                                               │
│  │  3. 分组     │  ← 按标签分组 (如按 service 分组)             │
│  │  (Group)    │     group_by: ['service', 'alertname']        │
│  │             │                                               │
│  │  4. 抑制     │  ← 如果高级别告警触发，抑制低级别告警           │
│  │  (Inhibit)  │     如: 节点宕机 → 抑制该节点上的服务告警       │
│  │             │                                               │
│  │  5. 沉默     │  ← 匹配沉默规则的告警不发送                     │
│  │  (Silence)  │     如: 维护窗口期间静默告警                   │
│  │             │                                               │
│  │  6. 路由     │  ← 按标签路由到不同的接收器                   │
│  │  (Route)    │     severity=critical → 电话                  │
│  │             │     severity=warning → 钉钉                   │
│  └──────┬──────┘                                               │
│         │                                                       │
│    ┌────┼────┬────────┬─────────┐                             │
│    ▼    ▼    ▼        ▼         ▼                              │
│  Email 钉钉  Webhook  Slack   电话/PagerDuty                   │
└─────────────────────────────────────────────────────────────────┘
```

**告警规则配置**：

```yaml
# Prometheus 告警规则 rules.yml
groups:
  - name: service-alerts
    rules:
      # 1. 高错误率告警
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
            /
          sum(rate(http_requests_total[5m])) by (service)
            > 0.05
        for: 5m              # 持续 5 分钟才告警（避免抖动）
        labels:
          severity: critical
          team: backend
        annotations:
          summary: "服务 {{ $labels.service }} 错误率过高"
          description: "服务 {{ $labels.service }} 5xx 错误率 {{ $value | humanizePercentage }}，超过 5% 阈值"
          runbook: "https://wiki.example.com/runbooks/high-error-rate"
      
      # 2. 响应时间过高
      - alert: HighLatency
        expr: |
          histogram_quantile(0.99,
            sum by (le, service) (rate(http_request_duration_seconds_bucket[5m]))
          ) > 1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "服务 {{ $labels.service }} P99 延迟过高"
          description: "P99 延迟 {{ $value }}s，超过 1s 阈值"
      
      # 3. 服务不可用
      - alert: ServiceDown
        expr: up{job="spring-boot"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "服务 {{ $labels.instance }} 不可用"
          description: "服务已宕机超过 1 分钟"
      
      # 4. JVM 内存告警
      - alert: JVMMemoryHigh
        expr: |
          jvm_memory_used_bytes{area="heap"} 
            / jvm_memory_max_bytes{area="heap"} > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "JVM 堆内存使用率过高"
          description: "实例 {{ $labels.instance }} 堆内存使用率 {{ $value | humanizePercentage }}"

# Alertmanager 配置 alertmanager.yml
route:
  group_by: ['service', 'alertname']   # 分组
  group_wait: 30s                        # 首次告警等待时间
  group_interval: 5m                     # 分组发送间隔
  repeat_interval: 4h                    # 重复告警间隔
  receiver: 'default'
  routes:
    - matchers: ['severity="critical"']
      receiver: 'critical-webhook'
      group_wait: 10s
    - matchers: ['severity="warning"']
      receiver: 'warning-webhook'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://dingtalk-alert:8060/dingtalk/send'
  
  - name: 'critical-webhook'
    webhook_configs:
      - url: 'http://alert-gateway:8080/critical'
    # 同时发电话
    pagerduty_configs:
      - service_key: '${PAGERDUTY_KEY}'
  
  - name: 'warning-webhook'
    webhook_configs:
      - url: 'http://dingtalk-alert:8060/dingtalk/warning'

# 抑制规则：节点宕机时抑制该节点的其他告警
inhibit_rules:
  - source_matchers: ['alertname="NodeDown"']
    target_matchers: ['alertname=~"High.*"']
    equal: ['instance']
```

### 6.2 告警分级与路由

```
告警分级体系:

P0 - 致命 (Critical)
├── 核心服务完全不可用
├── 数据丢失/损坏
├── 支付/交易中断
├── 安全漏洞被利用
└── 响应要求: 立即响应，电话通知

P1 - 严重 (High)
├── 核心服务性能严重下降
├── 非核心服务不可用
├── 告警风暴的前兆
├── 依赖的中间件不可用
└── 响应要求: 15分钟内响应，IM通知

P2 - 警告 (Warning)
├── 指标异常但未影响服务
├── 资源使用率偏高
├── 错误率略高于正常
├── 证书即将过期
└── 响应要求: 1小时内响应，工单通知

P3 - 提示 (Info)
├── 自动扩缩容事件
├── 配置变更通知
├── 部署完成通知
└── 响应要求: 工作时间处理，邮件通知
```

### 6.3 告警收敛与降噪

```
告警泛滥的常见原因:

1. 告警规则太敏感
   → 解决: for: 5m 持续时间 + 合理阈值

2. 一个根因引发大量告警
   → 解决: 抑制规则 (Inhibit)
   例: 机房网络断 → 所有服务告警 → 只报网络告警

3. 告警未分组
   → 解决: group_by 合并相似告警

4. 告警重复发送
   → 解决: repeat_interval 控制重复频率

5. 非工作时间告警
   → 解决: 按时间段路由 (工作时间→钉钉，非工作时间→电话)

告警收敛策略:

┌────────────────────────────────────────────────────┐
│                告警收敛策略                           │
│                                                    │
│  1. 去重 (Deduplication)                           │
│     同一告警只保留一条                               │
│     key = labels 的 hash                           │
│                                                    │
│  2. 分组 (Grouping)                                │
│     相似告警合并为一条通知                           │
│     "3 个服务的错误率告警" → 1 条通知               │
│                                                    │
│  3. 抑制 (Inhibition)                              │
│     高级别告警抑制低级别告警                         │
│     NodeDown → 抑制 HighCPU, HighMemory            │
│                                                    │
│  4. 沉默 (Silence)                                 │
│     主动静默，如维护窗口                             │
│     silences API: POST /api/v2/silences            │
│                                                    │
│  5. 延迟 (group_wait)                              │
│     首次告警等待一段时间，期间可能自动恢复            │
│                                                    │
│  6. 间隔 (repeat_interval)                         │
│     控制重复告警频率，避免轰炸                       │
│                                                    │
│  7. 根因关联 (Correlation)                         │
│     关联分析，找到根因，只报根因告警                 │
│     如: 数据库慢 → 连接池满 → 请求超时             │
│         → 只报数据库慢告警                          │
└────────────────────────────────────────────────────┘
```

---

## 第七章 Grafana 可视化体系

### 7.1 Dashboard 设计原则

```
Dashboard 分层设计:

第一层: 全局概览 (Overview Dashboard)
┌──────────────────────────────────────────────────┐
│  全局健康指标                                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐        │
│  │ 总 QPS   │ │ 总错误率  │ │ 整体 P99 │        │
│  │ 1.2k     │ │ 0.02%   │ │ 230ms   │        │
│  └──────────┘ └──────────┘ └──────────┘        │
│  ┌──────────────────────────────────────────┐   │
│  │  全部服务状态一览 (Service Map)            │   │
│  │  OK Gateway  OK Order  WARN Payment      │   │
│  │  OK User     OK Stock  OK Notification   │   │
│  └──────────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘

第二层: 服务详情 (Service Dashboard) — 每个服务一个
┌──────────────────────────────────────────────────┐
│  服务: OrderService                              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐        │
│  │  RED 指标                                         │
│  │  Rate    │ │  Errors  │ │ Duration │        │
│  │  500/s   │ │  0.1%   │ │  p99=120 │        │
│  └──────────┘ └──────────┘ └──────────┘        │
│  ┌──────────────────┐  ┌──────────────────┐     │
│  │  QPS 趋势图       │  │  延迟分布图       │     │
│  │  (按接口分组)     │  │  (p50/p90/p99)   │     │
│  └──────────────────┘  └──────────────────┘     │
│  ┌──────────────────┐  ┌──────────────────┐     │
│  │  JVM 监控         │  │  依赖服务状态     │     │
│  │  CPU/Heap/GC     │  │  MySQL/Redis    │     │
│  └──────────────────┘  └──────────────────┘     │
└──────────────────────────────────────────────────┘

第三层: 基础设施 (Infrastructure Dashboard)
┌──────────────────────────────────────────────────┐
│  基础设施: Node/Pod/Container                    │
│  ┌──────────────────────────────────────────┐   │
│  │  节点资源使用率                             │   │
│  │  CPU / Memory / Disk / Network          │   │
│  └──────────────────────────────────────────┘   │
│  ┌──────────────────┐  ┌──────────────────┐     │
│  │  Pod 状态         │  │  容器指标         │     │
│  │  Running/Pending  │  │  CPU/Memory/IO  │     │
│  └──────────────────┘  └──────────────────┘     │
└──────────────────────────────────────────────────┘
```

**Dashboard 设计最佳实践**：

```
1. 5 秒原则: 任何 Dashboard 应在 5 秒内理解整体健康状态
   → 用颜色和图标表达健康/告警/异常
   
2. 自上而下: 最重要的信息在顶部
   → 概览指标 → 趋势图 → 明细表

3. 黄金信号覆盖: 每个服务 Dashboard 必须包含
   → Rate (流量) + Errors (错误) + Duration (延迟) + Saturation (饱和度)

4. 使用变量: Dashboard 可切换服务/环境
   → 变量: $service, $environment, $instance

5. 合理的查询粒度
   → 概览: 1m 粒度
   → 明细: 15s 粒度
   → 长期趋势: 1h 粒度

6. 阈值线: 在图表上标出告警阈值
   → 让人一眼看出是否接近告警线
```

### 7.2 数据源与变量模板

```
Grafana 支持的数据源:

┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│ Prometheus  │ │Elasticsearch│ │   Jaeger    │
│ (Metrics)   │ │  (Logs)     │ │  (Traces)   │
└─────────────┘ └─────────────┘ └─────────────┘
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│   MySQL    │ │   InfluxDB   │ │  Postgres   │
│  (Query)   │ │  (Metrics)   │ │  (Query)    │
└─────────────┘ └─────────────┘ └─────────────┘
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│   Loki      │ │  CloudWatch  │ │    Zabbix   │
│  (Logs)     │ │  (AWS)       │ │  (Legacy)   │
└─────────────┘ └─────────────┘ └─────────────┘

变量模板 (Templating):
通过变量让 Dashboard 可动态切换

变量类型:
- Query: 从数据源查询获取值 (如所有服务名)
- Custom: 手动定义值列表
- Interval: 时间间隔 (1m, 5m, 1h)
- Data source: 切换数据源
- Constant: 常量

示例: 服务选择变量
查询: label_values(http_requests_total, service)
→ 自动获取所有有 http_requests_total 指标的服务名

在 Panel 查询中使用:
http_requests_total{service="$service"}

实现效果: 选择不同服务 → Dashboard 自动更新
```

**Metrics + Logs + Traces 关联**：

```json
// Grafana 支持在 Metrics Panel 中跳转到 Logs/Traces
// 实现三支柱关联

// 1. Metrics → Logs
// 在 Panel 的 Data Links 中配置
{
  "title": "View Logs",
  "url": "/explore?orgId=1&left=%7B%22datasource%22:%22elasticsearch%22,%22queries%22:%5B%7B%22query%22:%22service:${__field.labels.service}%20AND%20traceId:*%22%7D%5D%7D"
}

// 2. Logs → Traces
// 在 ES 数据源中配置 TraceID 字段
// 日志中包含 traceId → 可点击跳转到 Jaeger/Tempo

// 3. Traces → Logs
// 在 Tempo 数据源中配置
// Span 详情页可跳转到对应时间段的日志
```

### 7.3 Grafana Alerting

```yaml
# Grafana Unified Alerting (统一告警)
# 支持多种数据源的告警规则

# 1. 告警规则
rule:
  - name: "Order Service P99 > 1s"
    condition: A  # 基于查询 A 的结果
    data:
      - refId: A
        relativeTimeRange:
          from: 600  # 过去 10 分钟
        datasourceUid: prometheus
        model:
          expr: |
            histogram_quantile(0.99,
              sum by (le) (rate(
                http_request_duration_seconds_bucket{service="order"}[5m]
              ))
            ) > 1
    for: 5m  # 持续 5 分钟
    annotations:
      summary: "Order Service P99 延迟 > 1s"
      description: "当前 P99: {{ $values.A.value }}s"
    labels:
      severity: warning
      service: order

# 2. 告警通知策略 (Notification Policy)
# 类似 Alertmanager 的路由
policies:
  - rootPolicy:
      receiver: default
      group_by: ['service', 'severity']
      routes:
        - matcher: ['severity="critical"']
          receiver: oncall-phone
        - matcher: ['severity="warning"']
          receiver: team-dingtalk

# 3. Contact Points (通知渠道)
contactPoints:
  - name: oncall-phone
    type: webhook
    settings:
      url: http://alert-gateway:8080/critical
  - name: team-dingtalk
    type: dingtalk
    settings:
      url: https://oapi.dingtalk.com/robot/send?access_token=xxx
      msgType: markdown
```

---

## 第八章 生产级最佳实践

### 8.1 SLI/SLO/SLA 体系

```
Google SRE 核心理念: 用 SLO 驱动告警，而非用阈值驱动告警

┌─────────────────────────────────────────────────────────────────┐
│                    SLI / SLO / SLA 体系                          │
│                                                                 │
│  SLI (Service Level Indicator) - 服务水平指标                    │
│  ┌─────────────────────────────────────────────┐               │
│  │  衡量服务质量的量化指标                       │               │
│  │  例: 请求成功率 = 成功请求数 / 总请求数       │               │
│  │      p99 延迟                                │               │
│  └─────────────────────────────────────────────┘               │
│                                                                 │
│  SLO (Service Level Objective) - 服务水平目标                    │
│  ┌─────────────────────────────────────────────┐               │
│  │  对 SLI 设定的目标值                         │               │
│  │  例: 30天内请求成功率 >= 99.9%               │               │
│  │      p99 延迟 < 500ms                        │               │
│  └─────────────────────────────────────────────┘               │
│                                                                 │
│  SLA (Service Level Agreement) - 服务水平协议                    │
│  ┌─────────────────────────────────────────────┐               │
│  │  对外承诺的服务水平 (通常比 SLO 低)           │               │
│  │  违反 SLA 需要赔偿                           │               │
│  │  例: 月度可用性 >= 99.5%，否则退款 10%        │               │
│  └─────────────────────────────────────────────┘               │
│                                                                 │
│  Error Budget (错误预算)                                        │
│  ┌─────────────────────────────────────────────┐               │
│  │  SLO 99.9% → 允许 0.1% 的错误               │               │
│  │  一个月 43200 分钟 × 0.1% = 43.2 分钟        │               │
│  │  → 允许 43.2 分钟的不可用时间                │               │
│  │                                              │               │
│  │  Error Budget 的用途:                        │               │
│  │  - 预算充足 → 可以发新版本、做实验             │               │
│  │  - 预算耗尽 → 冻结发版，专注稳定性             │               │
│  │  - 预算快耗尽 → 告警，但不是"故障"告警        │               │
│  └─────────────────────────────────────────────┘               │
└─────────────────────────────────────────────────────────────────┘
```

**基于 SLO 的告警 vs 基于阈值的告警**：

```yaml
# 传统阈值告警（容易误报）
- alert: HighErrorRate
  expr: rate(http_errors[5m]) > 10
  # 问题: 10 个错误在大流量下完全正常，在小流量下是灾难

# 基于 SLO 的告警（更科学）
# 方案1: 多窗口多燃烧率 (Multi-window Multi-burn-rate)
- alert: SLOBurnRateCritical
  expr: |
    (
      # 1小时窗口，燃烧率 > 14.4 (2% 预算/1h)
      (1 - sum(rate(http_requests_total{status!~"5.."}[1h])) 
           / sum(rate(http_requests_total[1h]))) > 14.4 * (1 - 0.999)
    )
    and
    (
      # 5分钟窗口，同样阈值
      (1 - sum(rate(http_requests_total{status!~"5.."}[5m])) 
           / sum(rate(http_requests_total[5m]))) > 14.4 * (1 - 0.999)
    )
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "SLO 错误预算燃烧过快，1小时内消耗了 2% 的月度预算"

# 燃烧率 (Burn Rate) 计算:
# burn_rate = 实际错误率 / 允许错误率
# SLO = 99.9% → 允许错误率 = 0.1%
# 如果当前错误率 = 1% → burn_rate = 10
# 意味着: 按当前速度，1个月(43200分钟)的预算将在 4320 分钟(72小时)耗尽
# burn_rate=14.4 → 预算将在 1 小时耗尽 → 立即告警
```

### 8.2 RED / USE / Four Golden Signals 方法论落地

```
落地到 Prometheus 指标:

Java 应用 (Spring Boot + Micrometer):

# RED 指标 (服务层)
http_server_requests_seconds_count{method,uri,status}  # Rate
http_server_requests_seconds_sum{method,uri,status}    # Duration (计算均值)
http_server_requests_seconds_bucket{le}                 # Duration (计算分位数)
http_server_requests_seconds_count{status=~"5.."}      # Errors

# USE 指标 (资源层)
system_cpu_usage                # CPU 使用率
jvm_memory_used_bytes           # JVM 内存使用
jvm_threads_live_threads        # 线程数
hikaricp_connections_active     # 连接池活跃数 (饱和度)
hikaricp_connections_pending    # 连接池等待数 (饱和度)

# 业务指标
order_created_total             # 订单创建数
order_failed_total              # 订单失败数
payment_amount_sum              # 支付金额
```

```java
// Spring Boot Actuator + Micrometer 自动暴露指标
// 依赖
// implementation 'org.springframework.boot:spring-boot-starter-actuator'
// implementation 'io.micrometer:micrometer-registry-prometheus'
// runtimeOnly 'io.micrometer:micrometer-registry-prometheus'

// application.yml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus,metrics
  metrics:
    tags:
      application: ${spring.application.name}
      environment: ${spring.profiles.active}
    distribution:
      percentiles-histogram:
        http.server.requests: true
      percentiles:
        http.server.requests: 0.5, 0.9, 0.99
    export:
      prometheus:
        enabled: true

// 自定义业务指标
@Component
public class BusinessMetrics {
    private final Counter orderCounter;
    private final Timer orderProcessingTime;
    private final Gauge pendingOrders;
    
    public BusinessMetrics(MeterRegistry registry) {
        this.orderCounter = Counter.builder("order.created")
            .tag("type", "normal")
            .register(registry);
            
        this.orderProcessingTime = Timer.builder("order.processing")
            .publishPercentiles(0.5, 0.9, 0.99)
            .register(registry);
            
        this.pendingOrders = Gauge.builder("order.pending", 
            () -> getOrderPendingCount())
            .register(registry);
    }
}
```

### 8.3 可观测性成熟度模型

```
可观测性成熟度评估:

Level 0: 无监控 (Blind)
├── 出了问题靠用户反馈
├── 不知道系统在做什么
└── 排查靠猜

Level 1: 基础监控 (Basic Monitoring)
├── CPU/内存/磁盘基础指标
├── 简单的阈值告警
├── 日志在文件中，需要登录机器看
├── 无链路追踪
└── 出了问题能知道"哪里出问题"

Level 2: 结构化监控 (Structured Monitoring)
├── Metrics + Logs + Traces 三支柱覆盖
├── 指标有标签维度，可多维查询
├── 日志结构化，集中存储
├── 链路追踪覆盖核心调用链
├── Grafana Dashboard 统一展示
├── 告警有分级和收敛
└── 出了问题能知道"为什么出问题"

Level 3: 可观测性 (Observability)
├── 高基数标签，支持灵活探索
├── Metrics/Logs/Traces 三者关联
├── OpenTelemetry 统一标准
├── 基于采样策略平衡开销
├── SLO 体系驱动告警
├── 未知问题也能排查 (Unknown Unknowns)
└── 能"主动发现"潜在问题

Level 4: 智能可观测性 (AIOps)
├── 自动异常检测 (不需要设阈值)
├── 智能根因分析
├── 自动关联事件和告警
├── 预测性告警 (提前预警)
├── 自动修复 (Self-healing)
└── 能"预测和预防"问题

大部分企业在 Level 1-2 之间
目标: 达到 Level 2-3
```

### 8.4 容器与 Kubernetes 可观测性

```
Kubernetes 可观测性全景:

┌──────────────────────────────────────────────────────────────┐
│                  K8s 可观测性                                 │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │                   Metrics                             │    │
│  │                                                      │    │
│  │  Node 层:                                             │    │
│  │  - node-exporter (CPU/Memory/Disk/Network)           │    │
│  │  - kube-state-metrics (Pod/Deployment/Service 状态)  │    │
│  │                                                      │    │
│  │  Container 层:                                       │    │
│  │  - cAdvisor (容器 CPU/Memory/IO)                    │    │
│  │                                                      │    │
│  │  K8s 组件:                                           │    │
│  │  - API Server /metrics                              │    │
│  │  - Controller Manager /metrics                      │    │
│  │  - Scheduler /metrics                               │    │
│  │  - etcd /metrics                                    │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │                   Logging                             │    │
│  │                                                      │    │
│  │  容器 stdout/stderr → Fluent Bit DaemonSet            │    │
│  │  K8s 系统组件日志                                     │    │
│  │  应用日志 (文件/stdout)                               │    │
│  │  审计日志 (Audit Log)                                 │    │
│  │                                                      │    │
│  │  采集: Fluent Bit DaemonSet                           │    │
│  │  处理: Fluentd / Logstash                             │    │
│  │  存储: Elasticsearch                                  │    │
│  │  查询: Kibana                                         │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │                   Tracing                             │    │
│  │                                                      │    │
│  │  应用层: OTel Agent / SkyWalking Agent                │    │
│  │  Service Mesh 层: Istio/Linkerd 自动追踪              │    │
│  │  存储后端: Jaeger / Tempo / SkyWalking OAP            │    │
│  └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘

// kube-prometheus-stack (一体化监控方案)
// 包含: Prometheus + Grafana + Alertmanager + Node Exporter
//       + kube-state-metrics + cAdvisor

// Helm 安装
// helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack

// 关键 PromQL 查询:

// Pod CPU 使用率
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (pod) 
  / sum(kube_pod_container_resource_limits{resource="cpu"}) by (pod)

// Pod 内存使用率
sum(container_memory_working_set_bytes{container!=""}) by (pod)
  / sum(kube_pod_container_resource_limits{resource="memory"}) by (pod)

// Pod 重启次数
kube_pod_container_status_restarts_total

// Deployment 副本数异常
kube_deployment_status_replicas != kube_deployment_spec_replicas

// Node 资源使用率
sum(rate(node_cpu_seconds_total{mode!="idle"}[5m])) by (instance)
```

---

## 第九章 面试高频题

### Q1: 可观测性的三大支柱是什么？它们之间如何关联？

**参考回答**：

可观测性三大支柱是 **Metrics（指标）、Logging（日志）、Tracing（链路追踪）**。

- **Metrics**：聚合数值数据，回答"什么在发生"（如 QPS=1000，CPU=90%），存储成本低，适合告警。
- **Logging**：离散事件记录，回答"发生了什么细节"（如 14:23 用户 12345 创建订单失败），存储成本高，适合事后分析。
- **Tracing**：请求路径追踪，回答"在哪里发生的"（如 Gateway→Order→MySQL 耗时 3.5s），适合性能分析和故障定位。

三者通过 **TraceID** 关联：Tracing 中每个 Span 携带 TraceID，Logging 中通过 MDC 注入 TraceID，Metrics 中可标记 TraceID。这样从一个指标异常 → 跳到对应时间段日志 → 再跳到链路追踪，形成完整排查链路。

---

### Q2: Prometheus 为什么选择 Pull 模型而不是 Push？

**参考回答**：

Prometheus 选择 Pull 模型有四个核心原因：

1. **主动健康检查**：如果 Prometheus 拉不到目标数据，就知道目标不可达，天然的健康检查。
2. **控制权在监控系统**：采集频率、范围由 Prometheus 控制，防止大量客户端推送压垮监控系统。
3. **简化客户端**：客户端只需暴露 `/metrics` 端点，不需要配置推送地址、重试策略等。
4. **安全性**：监控系统可以控制采集范围，不需要向所有应用暴露接收端口。

对于短生命周期任务（如 Cron Job），Prometheus 提供 Pushgateway 作为中转，任务完成后推送指标到 Pushgateway，Prometheus 再从 Pushgateway 拉取。

---

### Q3: Prometheus 的四种指标类型有什么区别？什么场景用哪种？

**参考回答**：

| 类型 | 特点 | 场景 | PromQL |
|---|---|---|---|
| Counter | 只增不减 | 请求总数、错误总数 | rate() 计算 QPS |
| Gauge | 可增可减 | 当前连接数、内存、队列长度 | 直接使用 |
| Histogram | 分桶统计 | 请求延迟分布、响应大小分布 | histogram_quantile() 算分位数 |
| Summary | 客户端算分位数 | 对精度要求高的延迟统计 | 直接读取 |

推荐用 Histogram 而非 Summary，因为 Histogram 可以跨实例聚合（多个 Pod 的 p99 合并），而 Summary 不可聚合。

---

### Q4: 什么是高基数（High Cardinality）标签？为什么它是个问题？

**参考回答**：

高基数标签是指标签值非常多甚至无限的标签，如 userId、orderId、email。Prometheus 中每条时序 = 指标名 + 标签组合，标签值越多 → 时序数量爆炸。

例如：`http_requests_total{userId="12345"}` 如果有 100 万用户，就会产生 100 万条时序，占用大量内存和存储。

解决方案：
- **Metrics 不放高基数标签**：userId 放在 Logs/Tracing 中。
- **用 Histogram 替代**：将值分桶，如 `request_duration_bucket{le="0.1"}`。
- **使用 exemplars**：Prometheus 支持 Exemplar（示例），在指标中关联 TraceID，不增加时序数。

---

### Q5: 分布式链路追踪的上下文是如何跨服务传递的？

**参考回答**：

通过 HTTP Headers 传播上下文。主流格式有三种：

1. **W3C Trace Context**（推荐）：`traceparent: 00-{trace-id}-{parent-id}-{flags}`
2. **B3**（Zipkin）：`X-B3-TraceId`、`X-B3-SpanId`、`X-B3-Sampled`
3. **Jaeger**：`uber-trace-id: {trace-id}:{span-id}:{parent-span-id}:{flags}`

流程：
1. 服务 A 创建 Span，将 traceId + spanId 注入到 HTTP Headers。
2. 服务 A 发起 HTTP 请求，Headers 中携带追踪上下文。
3. 服务 B 从 Headers 中提取上下文。
4. 服务 B 创建子 Span，parentSpanId = 服务 A 的 spanId。
5. 服务 B 完成后结束 Span，异步上报。

跨线程传播需要将 Context 通过 ThreadLocal 传递，使用线程池时需要用装饰器传递。

---

### Q6: 头部采样和尾部采样有什么区别？

**参考回答**：

- **头部采样（Head-based）**：在请求入口决定是否采样。一旦决定采样，整个链路都会采。优点是简单、低开销；缺点是无法根据请求结果采样，可能漏采错误请求。
- **尾部采样（Tail-based）**：等整个 Trace 完成后，根据结果决定是否上报。可以确保采到所有错误和慢请求，正常请求只采一小部分。缺点是需要缓冲完整链路、内存开销大、实现复杂。

生产推荐：错误请求 100% 采、慢请求 100% 采、正常请求 10% 采。这能以很低的开销保证故障可追溯。

---

### Q7: SkyWalking 的无侵入 Agent 是怎么实现的？

**参考回答**：

SkyWalking Java Agent 基于 **ByteBuddy** 字节码增强，在 JVM 启动时通过 `premain` 方法介入类加载过程：

1. JVM 启动时加载 `premain` 方法，注册 `ClassFileTransformer`。
2. 当目标类（如 `DispatcherServlet`）被加载时，ByteBuddy 匹配到插件定义的增强规则。
3. ByteBuddy 修改字节码，在目标方法（如 `doDispatch`）前后插入拦截器代码。
4. 拦截器在方法执行前创建 Span、提取上游传递的 ContextCarrier，方法执行后结束 Span、异步上报。

整个过程对业务代码完全透明，开发者不需要修改任何代码，只需在启动命令加 `-javaagent:skywalking-agent.jar`。

SkyWalking 通过插件机制支持各种框架（Spring MVC、Dubbo、MyBatis、HttpClient、Kafka 等），每个插件定义了要增强的类和方法。

---

### Q8: OpenTelemetry 和 SkyWalking/Jaeger 是什么关系？

**参考回答**：

OpenTelemetry 是**标准**（API + SDK + 协议），不是后端存储和展示系统。SkyWalking/Jaeger/Prometheus 是**后端**。

关系：
- **之前**：每个追踪系统有自己的 SDK（OpenTracing、Jaeger client、SkyWalking agent），数据格式不兼容，切换成本极高。
- **现在**：OpenTelemetry 统一了 API 和数据模型（OTLP 协议），应用只需接入 OTel SDK，通过 OTel Collector 可以导出到任意后端（Jaeger、Tempo、SkyWalking、Prometheus、ES 等）。

迁移路径：现有系统不用急着换；新系统直接用 OTel SDK + 任意后端；未来 OTel 成为唯一标准，后端可随意切换。

---

### Q9: 什么是 SLI/SLO/SLA？如何基于 SLO 做告警？

**参考回答**：

- **SLI（Service Level Indicator）**：衡量服务质量的量化指标，如请求成功率、p99 延迟。
- **SLO（Service Level Objective）**：对 SLI 设定的目标值，如 30天内成功率 ≥ 99.9%。
- **SLA（Service Level Agreement）**：对外承诺的服务水平，违反需赔偿，通常比 SLO 低。
- **Error Budget（错误预算）**：SLO 99.9% → 允许 0.1% 的不可用 → 每月允许 43.2 分钟不可用。

基于 SLO 的告警用**燃烧率（Burn Rate）**策略：

burn_rate = 实际错误率 / 允许错误率

如果 SLO=99.9%（允许 0.1% 错误），当前错误率 1% → burn_rate=10 → 按此速度一个月预算在 3 天耗尽。

使用多窗口多燃烧率告警：1小时窗口 + 5分钟窗口双确认，burn_rate>14.4 时立即告警（1小时内消耗 2% 月预算），避免误报同时保证快速响应。

---

### Q10: 生产环境如何搭建完整的可观测性体系？

**参考回答**：

分三步走：

**第一步：基础监控（Level 1-2）**
- Metrics：Spring Boot Actuator + Micrometer + Prometheus，暴露 RED 指标
- Logging：结构化 JSON 日志 + ELK（Fluent Bit → Kafka → Logstash → ES → Kibana）
- Tracing：SkyWalking Agent（Java 技术栈无侵入）或 OTel Agent
- 可视化：Grafana 统一 Dashboard，覆盖 Overview → Service → Infrastructure 三层
- 告警：Prometheus AlertManager，P0-P3 分级 + 告警收敛

**第二步：关联与优化（Level 2-3）**
- 三支柱关联：Metrics → Logs → Traces 通过 TraceID 串联
- 采样策略：Tracing 尾部采样（错误 100% + 慢请求 100% + 正常 10%）
- 日志脱敏：手机号/身份证/邮箱自动脱敏
- SLO 体系：定义 SLI/SLO，基于燃烧率告警
- 日志 ILM：hot → warm → cold → delete 生命周期管理

**第三步：深度可观测性（Level 3+）**
- OpenTelemetry 统一标准：SDK + Collector，后端可切换
- 高基数标签：Metrics 不放 userId，用 Exemplar 关联 TraceID
- Thanos/VictoriaMetrics：Prometheus 长期存储 + 全局查询
- K8s 可观测：kube-prometheus-stack 一体化方案
- Error Budget 驱动发布：预算充足才允许发版

---

### Q11: ELK 架构演进经历了哪些阶段？每个阶段解决了什么问题？

**参考回答**：

四个阶段：

1. **基础 ELK**：App → Logstash → ES → Kibana。问题：Logstash JVM 太重，每台机器部署消耗资源大。
2. **ELK + Kafka**：App → Filebeat → Kafka → Logstash → ES → Kibana。解决：Kafka 削峰，Logstash 集中处理。但 Logstash 仍是瓶颈。
3. **EFK**：用 Fluentd/Fluent Bit 替代 Logstash。Fluent Bit C 语言编写，内存仅 ~450KB，适合 DaemonSet 部署。
4. **云原生 EFK + Kafka**：Fluent Bit (DaemonSet) → Kafka (缓冲) → Fluentd (集中处理) → ES → Kibana。这是生产推荐方案。

关键优化点：采集端轻量化（Fluent Bit）、缓冲解耦（Kafka）、集中处理（Fluentd/Logstash）、索引生命周期管理（ILM：hot→warm→cold→delete）。

---

### Q12: Grafana 如何实现 Metrics、Logs、Traces 三支柱关联？

**参考回答**：

Grafana 通过以下机制实现三支柱关联：

1. **Metrics → Logs**：在 Metrics Panel 的 Data Links 中配置跳转链接，点击图表上的数据点直接跳转到对应时间段的日志查询。
2. **Logs → Traces**：在 ES/Loki 数据源中配置 TraceID 字段识别，日志中的 TraceID 变成可点击链接，跳转到 Jaeger/Tempo 查看完整链路。
3. **Traces → Logs**：在 Tempo/Jaeger 数据源中配置日志关联，Span 详情页可跳转到对应时间段的日志。

核心是 **TraceID 作为关联键**：Metrics 指标中通过 Exemplar 关联 TraceID，日志中通过 MDC 注入 TraceID，Trace 本身就有 TraceID。三个数据源都支持 TraceID 之间的跳转，形成闭环。

---

> **总结**
>
> 本文从可观测性的核心概念出发，系统覆盖了：
> - **Metrics**：Prometheus 架构/四种指标类型/PromQL/TSDB 存储/Gorilla 压缩/高可用方案
> - **Logging**：ELK 架构演进/ES 存储原理/Fluent Bit 采集/结构化日志/MDC/日志脱敏
> - **Tracing**：Dapper 论文/Span 数据模型/上下文传播机制/采样策略/SkyWalking 源码/三大系统对比
> - **OpenTelemetry**：OTLP 协议/自动埋点/Collector 架构/与传统系统的关系
> - **告警体系**：Alertmanager 原理/告警分级/收敛降噪/SLO 驱动告警
> - **Grafana**：Dashboard 设计/变量模板/三支柱关联/统一告警
> - **生产实践**：SLI/SLO/SLA 体系/RED+USE 方法论/成熟度模型/K8s 可观测性