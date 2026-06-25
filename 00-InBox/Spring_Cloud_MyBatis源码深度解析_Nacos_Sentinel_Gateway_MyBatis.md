# Spring Cloud（Nacos / Sentinel / Gateway）+ MyBatis 源码深度解析

> **阅读提示**：本文档基于 Spring Cloud Alibaba 2.x / 2021.x 和 MyBatis 3.5.x 源码整理，结合面试高频考点和实际工程问题逐层剖析。建议先阅读《Spring_IoC_DI源码深度解析》和《Spring_AOP源码深度解析》，理解 Spring 容器和代理机制后再读本文。

---

## 全文结构总览

```
Spring Cloud + MyBatis 源码深度解析
│
├── 第一部分：Nacos — 服务注册与发现 + 配置中心
│   ├── 1.1  Nacos 整体架构
│   ├── 1.2  服务注册源码（NamingService.registerInstance）
│   ├── 1.3  服务发现源码（NamingService.selectInstances）
│   ├── 1.4  心跳与健康检查（ClientBeat + HealthCheckTask）
│   ├── 1.5  配置中心源码（ConfigService.getConfig / publishConfig）
│   ├── 1.6  长轮询机制（ClientWorker.LongPollingRunnable）
│   ├── 1.7  Nacos 集群数据同步（Distro + Raft）
│   ├── 1.8  Spring Cloud Nacos 自动装配（NacosServiceRegistryAutoConfiguration）
│   └── 1.9  Nacos 源码面试高频题
│
├── 第二部分：Sentinel — 流控 + 熔断 + 系统保护
│   ├── 2.1  Sentinel 整体架构（Slot Chain）
│   ├── 2.2  Entry 与 Context 模型（ContextUtil.enter / CtEntry）
│   ├── 2.3  滑动窗口统计（LeapArray + WindowWrap + MetricBucket）
│   ├── 2.4  FlowSlot — 流控规则源码（FlowRuleChecker.canPass）
│   ├── 2.5  DegradeSlot — 熔断降级源码（CircuitBreaker 三种策略）
│   ├── 2.6  SystemSlot — 系统自适应保护
│   ├── 2.7  AuthoritySlot / ClusterSlot / StatSlot
│   ├── 2.8  Sentinel Spring Cloud Gateway 适配
│   ├── 2.9  Sentinel 源码面试高频题
│   └── 2.10 Sentinel 规则配置持久化（Nacos 数据源）
│
├── 第三部分：Spring Cloud Gateway — 响应式网关
│   ├── 3.1  Gateway 整体架构（WebFlux + Route + Filter）
│   ├── 3.2  Route 定义与 Predicate（RoutePredicateFactory 体系）
│   ├── 3.3  Filter Chain 模型（GatewayFilterChain + GlobalFilter）
│   ├── 3.4  核心处理器 FilteringWebHandler
│   ├── 3.5  ReactiveLoadBalancerClientFilter — 负载均衡过滤器
│   ├── 3.6  NettyRoutingFilter — 底层 HTTP 路由
│   ├── 3.7  Gateway 自动装配与 Route 定位（RouteDefinitionLocator）
│   ├── 3.8  限流过滤器 RequestRateLimiterGatewayFilter（Redis + Lua）
│   ├── 3.9  Gateway 源码面试高频题
│   └── 3.10 Gateway 与 Sentinel 集成原理
│
├── 第四部分：MyBatis — ORM 框架核心
│   ├── 4.1  MyBatis 整体架构（接口层 + 核心处理层 + 基础支持层）
│   ├── 4.2  SqlSession 与 Mapper 代理（DefaultSqlSession + MapperProxy）
│   ├── 4.3  Executor 体系（SimpleExecutor / ReuseExecutor / BatchExecutor）
│   ├── 4.4  StatementHandler 体系（SimpleStatementHandler / PreparedStatementHandler）
│   ├── 4.5  ParameterHandler — 参数处理与 TypeHandler 映射
│   ├── 4.6  ResultSetHandler — 结果集映射与嵌套查询
│   ├── 4.7  一级缓存（LocalCache / PerpetualCache）
│   ├── 4.8  二级缓存（TransactionalCacheManager / CachingExecutor）
│   ├── 4.9  动态 SQL — OGNL 表达式 + SqlNode 体系
│   ├── 4.10 插件机制（Interceptor + Plugin.wrap 四大对象拦截）
│   ├── 4.11 MyBatis-Spring 自动装配（SqlSessionTemplate + MapperScannerConfigurer）
│   ├── 4.12 MyBatis 源码面试高频题
│   └── 4.13 MyBatis 与 Spring Cloud 整合链路（从 Controller 到 DB 的完整调用链）
│
├── 附录 A：Spring Cloud + MyBatis 请求全链路图
│
└── 附录 B：面试速记卡片（50 题精炼）
```

---

# 第一部分：Nacos — 服务注册与发现 + 配置中心

---

## 1.1 Nacos 整体架构

### 1.1.1 架构全景图

```
                    ┌─────────────────────────────────┐
                    │         Nacos Console           │
                    │      （管理界面 / Open API）      │
                    └────────────┬────────────────────┘
                                 │
                    ┌────────────▼────────────────────┐
                    │         Naming Service          │
                    │      （服务注册 / 发现 / 健康检查） │
                    └────────────┬────────────────────┘
                                 │
              ┌──────────────────▼──────────────────┐
              │          Config Service              │
              │      （配置管理 / 长轮询 / 版本控制）   │
              └──────────────────┬──────────────────┘
                                 │
              ┌──────────────────▼──────────────────┐
              │          Nacos Core                  │
              │  ┌──────────┐  ┌──────────────────┐ │
              │  │  Distro  │  │    Raft (CP)     │ │
              │  │  (AP临时) │  │  （持久数据共识）  │ │
              │  └──────────┘  └──────────────────┘ │
              │  ┌──────────┐  ┌──────────────────┐ │
              │  │Protocol  │  │   Auth / CMDB    │ │
              │  │(gRPC+HTTP│  │  （鉴权 / 元数据） │ │
              │  └──────────┘  └──────────────────┘ │
              └──────────────────┬──────────────────┘
                                 │
              ┌──────────────────▼──────────────────┐
              │          Nacos Plugin                │
              │  （Trace / 灰度 / 自定义 SPI 扩展）    │
              └─────────────────────────────────────┘
```

### 1.1.2 核心概念

| 概念 | 含义 | 源码类 |
|------|------|--------|
| **Namespace** | 命名空间，隔离环境（dev/prod） | `Namespace` |
| **Group** | 服务分组，同一 Namespace 下再隔离 | `Service` 的 group 字段 |
| **Service** | 逻辑服务名（如 `order-service`） | `Service` |
| **Instance** | 服务实例（IP + Port + 元数据） | `Instance` |
| **Cluster** | 实例集群（同机房/同区域归组） | `Cluster` |
| **ClusterName** | 集群名（如 `SH-AZ1`） | Instance 的 clusterName 字段 |
| **Ephemeral** | 临时实例（客户端心跳保活，AP） | Instance 的 ephemeral 字段 |
| **Persistent** | 持久实例（服务端主动探测，CP） | ephemeral = false |
| **Health Status** | 健康状态 | Instance 的 healthy 字段 |

### 1.1.3 AP vs CP 模式选择

```
Nacos 1.x：
  ┌──────────────────────────────────────────┐
  │  临时实例 (ephemeral=true) → Distro 协议  │
  │  • AP 模式：优先可用性，弱一致性           │
  │  • 客户端心跳保活，心跳丢失 → 自动剔除     │
  │  • 注册数据在各节点间异步复制              │
  │                                          │
  │  持久实例 (ephemeral=false) → Raft 协议   │
  │  • CP 模式：优先一致性，Leader 写入       │
  │  • 服务端主动探测（TCP/HTTP/MySQL）        │
  │  • 数据通过 Raft 日志同步                  │
  └──────────────────────────────────────────┘

Nacos 2.x：
  ┌──────────────────────────────────────────┐
  │  临时实例 → gRPC 长连接 + Distro          │
  │  • 连接断开 → 2s 内感知并剔除             │
  │  • 比 1.x 心跳（15s）更实时                │
  │                                          │
  │  持久实例 → Raft（不变）                   │
  └──────────────────────────────────────────┘
```

---

## 1.2 服务注册源码（NamingService.registerInstance）

### 1.2.1 注册入口与完整调用链

```java
// 入口：应用启动时自动调用
NacosNamingService.registerInstance("order-service", "192.168.1.10", 8080);

// ──── 调用链 ────
NacosNamingService.registerInstance(serviceName, ip, port)
    │
    ├── 1. 构建 Instance 对象
    │   Instance instance = new Instance();
    │   instance.setIp(ip);
    │   instance.setPort(port);
    │   instance.setEphemeral(true);  // 默认临时实例
    │   instance.setWeight(1.0);
    │   instance.setClusterName("DEFAULT");
    │
    ├── 2. registerInstance(serviceName, groupName, instance)
    │   │
    │   ├── 2.1 检查参数（validateInstance）
    │   │
    │   ├── 2.2 如果 ephemeral=true → 心跳任务启动
    │   │   │   clientProxy = new NamingClientProxyDelegate(this);
    │   │   │   // delegate 内部根据 ephemeral 选择：
    │   │   │   //   ephemeral=true  → NamingClientProxy (gRPC/HTTP)
    │   │   │   //   ephemeral=false → NamingServerProxy (直接HTTP)
    │   │   │
    │   │   ├── 2.2.1 gRPC 注册（Nacos 2.x）
    │   │   │   │   NamingClientProxy.registerService(serviceName, groupName, instance)
    │   │   │   │   │
    │   │   │   │   ├── 建立 gRPC 连接（GrpcConnection）
    │   │   │   │   ├── 发送 RegisterInstanceRequest
    │   │   │   │   └── 注册成功 → 启动心跳（BeatTask 1.x / 连接保活 2.x）
    │   │   │   │
    │   │   │   └── 2.2.2 HTTP 注册（Nacos 1.x / 兼容）
    │   │   │       │   NamingClientProxy.registerServiceHttp(...)
    │   │   │       │   │
    │   │   │       │   ├── POST /nacos/v1/ns/instance
    │   │   │       │   ├── 参数: serviceName, ip, port, weight, ephemeral...
    │   │   │       │   └── 返回: "ok"
    │   │   │       │
    │   │   │       └── 启动 BeatTask（心跳）
    │   │   │           BeatTask.run()
    │   │   │           │   ├── 构造 BeatInfo
    │   │   │           │   ├── POST /nacos/v1/ns/instance/beat
    │   │   │           │   ├── 服务端返回心跳间隔
    │   │   │           │   ├── 5s 默认间隔，scheduleAtFixedRate
    │   │   │           │   └── 心跳失败 → 重试，连续失败 → 标记不健康
    │   │   │
    │   │   └── 2.3 如果 ephemeral=false → 服务端探测注册
    │   │       │   NamingServerProxy.registerService(...)
    │   │       │   │   POST /nacos/v1/ns/instance (ephemeral=false)
    │   │       │   │   → 服务端创建 HealthCheckTask
    │   │       │   │   → TCP/HTTP/MYSQL 探测
    │   │   │
    │   └── 3. 注册完成（缓存到本地 registeredServices）
```

### 1.2.2 服务端注册处理（InstanceController.register）

```java
// Nacos 服务端 — InstanceController
@PostMapping("/instance")
public String register(HttpServletRequest request) {
    // ──── 服务端处理链 ────
    
    // 1. 解析参数，构建 Instance
    String serviceName = request.getParameter("serviceName");
    String ip = request.getParameter("ip");
    int port = Integer.parseInt(request.getParameter("port"));
    boolean ephemeral = Boolean.parseBoolean(request.getParameter("ephemeral"));
    
    // 2. 获取 ServiceManager → getService
    Service service = manager.getService(namespaceId, serviceName);
    if (service == null) {
        // 2.1 服务不存在 → 创建并注册
        service = new Service(serviceName, namespaceId);
        service.setEphemeral(ephemeral);
        manager.putService(service);   // 注册到 registry
        service.init();                // 启动健康检查
    }
    
    // 3. 添加 Instance 到 Service
    service.addInstance(instance);
    
    // 4. 如果 ephemeral → Distro 协议同步到其他节点
    if (ephemeral) {
        distroProtocol.sync(new DistroKey(serviceName, namespaceId), 
                            DataOperation.ADD, 1000L);
    }
    // 如果 persistent → Raft 协议写入
    else {
        raftProtocol.write(new RaftKey(serviceName, namespaceId), instance);
    }
    
    return "ok";
}
```

### 1.2.3 Instance 数据结构

```java
// 核心字段
public class Instance {
    private String instanceId;      // 自动生成: ip#port#clusterName#serviceName
    private String ip;
    private int port;
    private double weight = 1.0;    // 权重（负载均衡）
    private boolean healthy = true; // 健康状态
    private boolean enabled = true; // 是否启用
    private boolean ephemeral = true; // 临时 vs 持久
    private String clusterName;     // 集群名
    
    // 元数据（可扩展：region, zone, env, version 等）
    private Map<String, String> metadata = new HashMap<>();
    
    // 心跳相关（1.x）
    private long heartbeatInterval = 5000L; // 心跳间隔（ms）
    private long heartbeatTimeout = 15000L;  // 心跳超时
    private long ipDeleteTimeout = 30000L;   // IP 删除超时
    
    // 常用元数据约定
    // metadata.put("preserved.register.source", "SPRING_CLOUD");
    // metadata.put("version", "2.0.0");
    // metadata.put("zone", "SH-AZ1");
}
```

### 1.2.4 注册的内存存储结构

```
Nacos 服务端内存结构（ServiceManager）：

ServiceManager (ConcurrentHashMap<String, Map<String, Service>>)
    │
    │   key: namespaceId (如 "public", "dev-ns")
    │   value: Map<String, Service>
    │       │   key: groupName@@serviceName (如 "DEFAULT_GROUP@@order-service")
    │       │   value: Service 对象
    │
    └── Service
        │   namespaceId, name, groupName, ephemeral
        │
        ├── ClusterMap (ConcurrentHashMap<String, Cluster>)
        │   │   key: clusterName (如 "DEFAULT", "SH-AZ1")
        │   │   value: Cluster
        │   │       │
        │   │       ├── ephemeralInstances (Set<Instance>)  // 临时实例
        │   │       ├── persistentInstances (Set<Instance>) // 持久实例
        │   │       └── healthChecker (AbstractHealthChecker) // 健康检查器
        │   │           ├── TcpHealthChecker   // TCP 探测
        │   │           ├── HttpHealthChecker   // HTTP 探测  
        │   │           └── MysqlHealthChecker  // MySQL 探测
        │   │
        │   └── 服务端定时任务
        │       ├── ClientBeatCheckTask    // 临时实例心跳检查
        │       │   • 检查 lastBeat > heartbeatTimeout → 标记不健康
        │       │   • 检查 lastBeat > ipDeleteTimeout → 删除实例
        │       │
        │       └── HealthCheckTask        // 持久实例主动探测
        │           • Tcp: 尝试建立 TCP 连接
        │           • Http: 发送 GET 请求
        │           • 探测失败 → 标记不健康
```

---

## 1.3 服务发现源码（NamingService.selectInstances）

### 1.3.1 查询调用链

```java
// 入口
List<Instance> instances = namingService.selectInstances("order-service", true);

// ──── 调用链 ────
NacosNamingService.selectInstances(serviceName, healthy)
    │
    ├── 1. selectInstances(serviceName, groupName, clusters, healthy)
    │
    ├── 2. 订阅 + 查询（subscribe + queryInstancesOfService）
    │   │
    │   ├── 2.1 订阅服务变更
    │   │   │   clientProxy.subscribe(serviceName, groupName, clusters)
    │   │   │   │
    │   │   │   ├── gRPC 模式（2.x）
    │   │   │   │   ├── 发送 SubscribeServiceRequest
    │   │   │   │   ├── 服务端注册 PushReceiver
    │   │   │   │   └── 服务端变更 → gRPC 推送 NotifySubscriberRequest
    │   │   │   │
    │   │   │   └── HTTP 模式（1.x）
    │   │   │       ├── 注册 EventListener
    │   │   │       ├── 启动 UpdateTask（定时拉取）
    │   │   │       │   GET /nacos/v1/ns/instance/list
    │   │   │       │   → 缓存到 serviceInfoMap
    │   │   │       │   → 对比新旧数据 → 触发 InstancesChangeEvent
    │   │   │       │   → 6s 首次，之后 30s 或收到 UDP 推送后 15s
    │   │   │
    │   ├── 2.2 查询实例列表
    │   │   │   clientProxy.queryInstancesOfService(serviceName, groupName, clusters)
    │   │   │   │
    │   │   │   ├── gRPC：发送 ServiceQueryRequest
    │   │   │   │   → 服务端从 ServiceManager 取数据 → 返回
    │   │   │   │
    │   │   │   ├── HTTP：GET /nacos/v1/ns/instance/list
    │   │   │   │   → 从本地缓存 serviceInfoMap 取 → 如无则实时查
    │   │   │
    │   └── 3. healthy 过滤
    │       │   if (healthy) {
    │       │       return instances.stream()
    │       │           .filter(Instance::isHealthy)
    │       │           .filter(Instance::isEnabled)
    │       │           .collect(Collectors.toList());
    │       │   }
    │       │   return instances;
    │
    └── 4. 返回结果给调用方
```

### 1.3.2 服务端推送机制（PushReceiver）

```
Nacos 1.x UDP 推送：
  ┌──────────────────────────────────────┐
  │  服务端变更事件 → PushService         │
  │  │                                   │
  │  ├── 服务注册/注销/健康状态变更        │
  │  │   → 找到所有订阅该服务的客户端      │
  │  │   → UDP 推送数据到客户端            │
  │  │   → 客户端 AckReceiver 收到后      │
  │  │       更新本地缓存                  │
  │  │       15s 后再拉取一次（确认）       │
  │  │                                   │
  │  ├── UDP 不可靠 → 客户端定时拉取兜底   │
  │  │   UpdateTask: 6s首次 / 30s定期     │
  │  └──────────────────────────────────┘

Nacos 2.x gRPC 推送：
  ┌──────────────────────────────────────┐
  │  gRPC 长连接 → 双向流                 │
  │  │                                   │
  │  ├── 客户端连接建立时                 │
  │  │   → 服务端注册 Connection            │
  │  │   → 记录订阅关系                    │
  │  │                                   │
  │  ├── 服务变更时                       │
  │  │   → 直接通过 gRPC stream 推送       │
  │  │   → 可靠、实时、无 UDP 丢失问题      │
  │  │                                   │
  │  ├── 连接断开 → 2s 内感知             │
  │  │   → 自动剔除对应实例               │
  │  └──────────────────────────────────┘
```

### 1.3.3 本地缓存与故障兜底

```java
// Nacos 客户端本地缓存机制
public class ServiceInfoHolder {
    // 服务信息缓存
    private ConcurrentMap<String, ServiceInfo> serviceInfoMap;
    
    // 失败请求的故障服务缓存（兜底）
    private ConcurrentMap<String, ServiceInfo> failoverMap;
    
    // 查询逻辑：
    ServiceInfo getServiceInfo(String key) {
        // 1. 先从 serviceInfoMap 取（正常缓存）
        ServiceInfo info = serviceInfoMap.get(key);
        
        if (info == null) {
            // 2. 缓存无 → 触发立即订阅
            info = clientProxy.subscribe(...);
            serviceInfoMap.put(key, info);
        }
        
        // 3. 如果 Nacos 服务器不可达
        if (!nacosServerAvailable) {
            // 从 failoverMap 取（磁盘缓存加载）
            info = failoverMap.get(key);
            // failoverMap 来源：本地文件
            //   {user.home}/nacos/naming/{namespaceId}/failover/{serviceName}
        }
        
        return info;
    }
    
    // 本地文件缓存路径
    // {user.home}/nacos/naming/{namespaceId}/cache/{serviceName}
    // 定时写磁盘 → 服务重启时加载
}
```

---

## 1.4 心跳与健康检查（ClientBeat + HealthCheckTask）

### 1.4.1 客户端心跳（临时实例）

```java
// Nacos 1.x — BeatTask
public class BeatTask implements Runnable {
    private BeatInfo beatInfo;
    private NamingClientProxy clientProxy;
    private long beatInterval;  // 心搏间隔
    
    @Override
    public void run() {
        // 1. 发送心跳请求
        long result = clientProxy.sendBeat(beatInfo);
        
        // 2. 根据返回调整间隔
        if (result > 0) {
            beatInterval = result;  // 服务端建议间隔
        }
        
        // 3. 心跳失败处理
        long nextTime = beatInterval;
        if (beatInfo.isHealthy()) {
            // 正常 → 下次心跳
            nextTime = beatInterval;
        } else {
            // 不健康 → 加倍间隔，等待恢复
            nextTime = beatInterval * 2;
            
            // 尝试重新注册
            if (beatRetryCount > MAX_RETRY) {
                clientProxy.registerService(...);  // 重新注册
                beatRetryCount = 0;
            }
        }
        
        // 4. 安排下一次心跳
        executor.schedule(new BeatTask(...), nextTime, TimeUnit.MILLISECONDS);
    }
}

// 心跳请求
POST /nacos/v1/ns/instance/beat
    参数: serviceName, ip, port, weight, clusterName, beat
    返回: 心跳间隔（ms）或 0（正常）
```

### 1.4.2 服务端健康检查（持久实例）

```java
// HealthCheckTask — 服务端主动探测
public class HealthCheckTask implements Runnable {
    private Cluster cluster;
    
    @Override
    public void run() {
        // 对每个 persistentInstance 执行探测
        for (Instance instance : cluster.persistentInstances()) {
            AbstractHealthChecker checker = cluster.healthChecker();
            
            boolean healthy = checker.check(instance);
            
            if (healthy && !instance.isHealthy()) {
                // 恢复健康 → 发布 HealthCheckChangedEvent
                instance.setHealthy(true);
                NotifyPublisher.publish(
                    new HealthCheckChangedEvent(instance, true));
            }
            
            if (!healthy && instance.isHealthy()) {
                // 变为不健康 → 发布事件
                instance.setHealthy(false);
                NotifyPublisher.publish(
                    new HealthCheckChangedEvent(instance, false));
            }
        }
    }
}

// TCP 探测
public class TcpHealthChecker {
    public boolean check(Instance instance) {
        try {
            Socket socket = new Socket();
            socket.connect(new InetSocketAddress(instance.getIp(), instance.getPort()), 
                          TIMEOUT_MS);
            socket.close();
            return true;  // 连接成功 → 健康
        } catch (Exception e) {
            return false; // 连接失败 → 不健康
        }
    }
}
```

### 1.4.3 心跳时序图

```
     客户端                          Nacos Server                    其他节点
        │                                │                              │
        │  ── registerInstance ──▶       │                              │
        │                                │  ── Distro sync ──▶          │
        │                                │                              │
        │  ── heartbeat (5s) ──▶         │                              │
        │                                │  更新 lastBeat                │
        │                                │                              │
        │  ── heartbeat ──▶              │                              │
        │                                │                              │
        │      ✕ (网络故障)               │                              │
        │                                │  ClientBeatCheckTask          │
        │                                │  lastBeat > 15s → 标记不健康  │
        │                                │  ── push 订阅者 ──▶           │
        │                                │                              │
        │                                │  lastBeat > 30s → 删除实例    │
        │                                │  ── Distro sync(delete) ──▶  │
        │                                │                              │
        │  ── heartbeat恢复 ──▶          │                              │
        │                                │  重新标记健康                 │
        │                                │  ── push 订阅者 ──▶           │
```

---

## 1.5 配置中心源码（ConfigService.getConfig / publishConfig）

### 1.5.1 配置获取调用链

```java
// 入口
String config = configService.getConfig("order-service.yaml", "DEFAULT_GROUP", 5000);

// ──── 调用链 ────
NacosConfigService.getConfig(dataId, group, timeoutMs)
    │
    ├── 1. getServerConfig(dataId, group, namespace, timeoutMs)
    │   │
    │   ├── HTTP: GET /nacos/v1/cs/configs
    │   │   参数: dataId, group, namespace, tenant
    │   │   返回: 配置内容（String）
    │   │
    │   ├── gRPC (2.x): ConfigQueryRequest
    │   │   → 服务端从 ConfigDiskService 取 → 返回
    │
    ├── 2. 本地缓存兜底
    │   │   如果服务端不可达 → 从本地文件取
    │   │   路径: {user.home}/nacos/config/{namespace}/snapshot/{dataId}
    │
    └── 3. 返回配置内容
```

### 1.5.2 配置发布调用链

```java
// 入口
boolean success = configService.publishConfig("order-service.yaml", "DEFAULT_GROUP", content);

// ──── 调用链 ────
NacosConfigService.publishConfig(dataId, group, content)
    │
    ├── HTTP: POST /nacos/v1/cs/configs
    │   参数: dataId, group, content, type (yaml/properties/json/text)
    │
    ├── 服务端处理：ConfigController.publishConfig
    │   │
    │   ├── 1. 校验参数（长度限制、格式检查）
    │   │
    │   ├── 2. 持久化到数据库（MySQL / 内嵌 Derby）
    │   │   │   configInfo = new ConfigInfo(dataId, group, namespace, content, type);
    │   │   │   configDiskService.save(configInfo);
    │   │   │   // SQL: INSERT / UPDATE config_info
    │   │   │   // 同时写入 config_tags_relation, his_config_info（历史）
    │   │   │
    │   │   ├── 3. 写入本地磁盘缓存
    │   │   │   configDiskService.writeToDisk(dataId, group, namespace, content);
    │   │   │
    │   │   ├── 4. 发布 ConfigDataChangeEvent
    │   │   │   │   NotifyCenter.publishEvent(
    │   │   │   │       new ConfigDataChangeEvent(dataId, group, namespace, lastModified));
    │   │   │   │
    │   │   │   └── 4.1 AsyncNotifyService 处理事件
    │   │   │       │   遍历所有 Nacos 节点
    │   │   │       │   → 发送 HTTP/gRPC 通知
    │   │   │       │   → 其他节点更新本地缓存
    │   │   │       │   → 通知所有订阅客户端（长轮询）
    │   │   │
    │   │   └── 5. 返回 true
    │
    └── 客户端收到通知 → 触发 Listener 回调
```

### 1.5.3 配置存储结构

```
MySQL 表结构（config_info）：
  ┌────────────────────────────────────────────┐
  │  config_info                                │
  │  ├── id           (BIGINT, PK, 自增)        │
  │  ├── data_id      (VARCHAR 255, 配置名)     │
  │  ├── group_id     (VARCHAR 128, 分组)        │
  │  ├── content      (LONGTEXT, 配置内容)       │
  │  ├── md5          (VARCHAR 32, 内容MD5)      │
  │  ├── type         (VARCHAR 10, yaml/json...) │
  │  ├── tenant_id    (VARCHAR 128, namespace)   │
  │  ├── app_name     (VARCHAR 128)              │
  │  ├── src_user     (VARCHAR 50, 操作人)       │
  │  ├── gmt_create   (DATETIME)                 │
  │  ├── gmt_modified (DATETIME)                 │
  └────────────────────────────────────────────┘

  ┌────────────────────────────────────────────┐
  │  his_config_info （历史版本表）              │
  │  ├── id, data_id, group_id, content         │
  │  ├── md5, tenant_id, src_user               │
  │  ├── gmt_create, gmt_modified               │
  │  ├── nid (自增, 历史记录序号)                │
  │  ├── op_type (I=插入, U=更新, D=删除)       │
  └────────────────────────────────────────────┘
```

---

## 1.6 长轮询机制（ClientWorker.LongPollingRunnable）

### 1.6.1 配置变更监听原理

```
  客户端如何感知配置变更？

  方案一：定时拉取（简单但低效）
    ┌── 每 30s 拉一次 ──→ 配置不变 →浪费带宽
  
  方案二：服务端推送（实时但连接管理复杂）
    ┌── WebSocket/gRPC ──→ 服务端压力大

  方案三：长轮询（Nacos 采用）
    ┌── 客户端发起请求，带 timeout=29.5s ──────────▶ 服务端
    │                                                │
    │   如果配置无变化 ──── 服务端 hold 29.5s ──────▶ 返回空
    │   如果配置有变化 ──── 服务端立即返回 ──────────▶ 返回变更的 dataId
    │                                                │
    │   客户端收到响应 → 立即发起下一次长轮询          │
    │   （变化时延迟 < 500ms，无变化时 30s 一次）       │
```

### 1.6.2 客户端长轮询源码

```java
// ClientWorker — 栢询核心
public class ClientWorker {
    // 长轮询任务（2个线程轮替，避免阻塞）
    private ScheduledExecutorService executor;
    private ExecutorService longPollingExecutor;
    
    // 监听的配置组
    private CacheDataMap (Map<String, CacheData>)
    // 每个 CacheData 包含:
    //   dataId, group, namespace, md5(上次), content, listeners
    
    // ──── 长轮询流程 ────
    class LongPollingRunnable implements Runnable {
        private int taskId;
        
        @Override
        public void run() {
            // 1. 收集需要检查的 CacheData
            List<CacheData> cacheDatas = new ArrayList<>();
            for (CacheData cacheData : cacheMap.values()) {
                if (cacheData.getTaskId() == taskId) {
                    cacheDatas.add(cacheData);
                }
            }
            
            // 2. 检查本地 md5 是否与服务端一致
            //    先用短超时（3s）快速检查
            List<String> changedGroups = checkUpdateDataIds(cacheDatas, 3000L);
            
            // 3. 如果有变更 → 立即获取新配置
            for (String groupKey : changedGroups) {
                String[] keys = GroupKey.parseKey(groupKey);
                String content = getServerConfig(keys[0], keys[1], keys[2], 3000L);
                CacheData cacheData = cacheMap.get(groupKey);
                cacheData.setContent(content);
            }
            
            // 4. 如果无变更 → 发起长轮询（29.5s timeout）
            //    POST /nacos/v1/cs/configs/listener
            //    body: dataId×group×md5 数据
            //    Long-Pulling-Timeout: 29500
            List<String> changedGroups = 
                checkUpdateConfigDataIds(cacheDatas, 29500L);
            
            // 5. 长轮询返回后 → 处理变更
            for (String groupKey : changedGroups) {
                // 获取新配置 → 更新 CacheData → 触发 Listener
            }
            
            // 6. 触发所有 CacheData 的 Listener（即使没变更也要检查）
            for (CacheData cacheData : cacheDatas) {
                // 检查 md5 是否变化
                // 变化 → 遍历 listeners → listener.receiveConfigInfo(content)
            }
            
            // 7. 安排下一次长轮询
            executor.schedule(this, 500L, TimeUnit.MILLISECONDS);
        }
    }
    
    // 检查配置变更的请求
    private List<String> checkUpdateConfigDataIds(List<CacheData> cacheDatas, long timeout) {
        // POST /nacos/v1/cs/configs/listener
        // Header: Long-Pulling-Timeout = timeout
        // Body: dataId^2group^2md5;dataId^2group^2md5;...
        // 
        // 服务端处理：
        //   遍历每个 dataId+group
        //   比对 md5
        //   如果不一致 → 立即返回变更列表
        //   如果都一致 → hold 直到超时或配置变更
    }
}
```

### 1.6.3 服务端长轮询处理

```java
// ConfigController — listener 接口
@PostMapping("/listener")
public void listener(HttpServletRequest request, HttpServletResponse response) {
    // 1. 解析客户端的配置监听列表
    String data = request.getParameter("Listening-Configs");
    Map<String, String> clientMd5Map = parseData(data);
    
    // 2. 比对 MD5
    Map<String, String> changedConfigs = new HashMap<>();
    for (Map.Entry<String, String> entry : clientMd5Map.entrySet()) {
        String groupKey = entry.getKey();
        String clientMd5 = entry.getValue();
        
        // 从缓存取服务端 MD5
        String serverMd5 = configCacheService.getConfigMd5(groupKey);
        
        if (!clientMd5.equals(serverMd5)) {
            changedConfigs.put(groupKey, serverMd5);
        }
    }
    
    // 3. 如果有变更 → 立即返回
    if (!changedConfigs.isEmpty()) {
        response.getWriter().write(formatResult(changedConfigs));
        return;
    }
    
    // 4. 无变更 → 挂起请求（长轮询核心）
    //    使用 AsyncContext（Servlet 3.0）异步处理
    AsyncContext asyncContext = request.startAsync();
    
    //    创建 LongPollingService.ClientLongPolling 任务
    //    29.5s 后自动返回空响应
    //    如果期间配置变更 → 立即完成响应
    ConfigChangeNotificationTask task = new ConfigChangeNotificationTask(
        asyncContext, clientMd5Map, 29500L);
    
    //    注册到 LongPollingService.allSubs
    longPollingService.addClient(task);
    
    //    当配置变更事件到达时:
    //    LongPollingService.onEvent(ConfigDataChangeEvent)
    //      → 遍历 allSubs
    //      → 找到匹配的 ClientLongPolling
    //      → 返回变更的 groupKey
    //      → 移除订阅
}
```

### 1.6.4 长轮询时序图

```
     客户端 A                    Nacos Server                客户端 B
        │                            │                          │
        │ ── POST listener ──────▶   │                          │
        │    (dataId, md5=v1)        │                          │
        │                            │  比对: 服务端 md5=v1      │
        │                            │  无变更 → hold           │
        │                            │                          │
        │                            │                          │
        │                            │  ── 管理员发布新配置 ──   │
        │                            │  (content → md5=v2)      │
        │                            │                          │
        │                            │  ConfigDataChangeEvent    │
        │                            │  → 遍历 allSubs          │
        │  ──── 返回 changed ─────◀ │  → 匹配 A 的订阅        │
        │    (dataId, md5=v2)        │  → asyncContext.complete │
        │                            │                          │
        │ ── GET config ─────────▶  │                          │
        │    返回新配置内容            │                          │
        │                            │                          │
        │ ── POST listener ──────▶   │                          │
        │    (dataId, md5=v2)        │                          │
        │                            │                          │
        │    ...循环...               │                          │
```

---

## 1.7 Nacos 集群数据同步（Distro + Raft）

### 1.7.1 Distro 协议（AP 临时数据）

```
Distro 协议 — 临时实例数据同步
  ┌──────────────────────────────────────────────────┐
  │  核心思想：各节点负责一部分数据，异步同步到其他节点  │
  │                                                  │
  │  数据分配规则：                                   │
  │  │   根据 serviceHash 计算每个节点负责的 range      │
  │  │   node1: range [0, 33%)                       │
  │  │   node2: range [33%, 66%)                     │
  │  │   node3: range [66%, 100%)                    │
  │  │   客户端注册 → 路由到负责该 service 的节点      │
  │                                                  │
  │  同步流程：                                       │
  │  │   1. 注册请求到达负责节点                       │
  │  │   2. 负责节点处理并存储                         │
  │  │   3. 异步同步到其他节点（DistroSyncTask）        │
  │  │   4. 其他节点收到后验证并存储                    │
  │  │   5. 同步失败 → 重试                           │
  │                                                  │
  │  初始化同步：                                     │
  │  │   节点启动 → 从其他节点拉取全量数据              │
  │  │   DistroLoadDataTask                          │
  │                                                  │
  │  定期校验：                                       │
  │  │   DistroVerifyTask → 对比各节点数据一致性        │
  │  │   不一致 → 重新同步                            │
  └──────────────────────────────────────────────────┘
```

```java
// Distro 协议核心类
public class DistroProtocol {
    // 数据同步
    public void sync(DistroKey key, DataOperation action, long delay) {
        // 遍历所有其他节点
        for (Member member : memberManager.allMembers()) {
            if (member.equals(memberManager.getSelf())) continue;
            
            // 创建同步任务
            DistroSyncTask task = new DistroSyncTask(key, action, member);
            
            // 延迟执行（异步）
            distroTaskEngine.execute(task, delay);
        }
    }
    
    // 数据接收处理
    public void onReceive(DistroData data, DataOperation action) {
        switch (action) {
            case ADD:
                // 处理新增数据
                distroDataProcessor.processData(data);
                break;
            case CHANGE:
                // 处理变更数据
                distroDataProcessor.processData(data);
                break;
            case DELETE:
                // 处理删除数据
                distroDataProcessor.processData(data);
                break;
        }
    }
}
```

### 1.7.2 Raft 协议（CP 持久数据）

```
Raft 协议 — 持久实例和配置数据共识
  ┌──────────────────────────────────────────┐
  │  核心概念：                                │
  │  │   Leader: 处理所有写请求                │
  │  │   Follower: 接收 Leader 日志           │
  │  │   Candidate: 选举中                    │
  │                                          │
  │  选举流程：                                │
  │  │   1. Follower 心跳超时 → 变为 Candidate │
  │  │   2. 增加 term，投自己一票             │
  │  │   3. 向其他节点发送 VoteRequest        │
  │  │   4. 获得多数票 → 变为 Leader          │
  │  │   5. 开始发送心跳（AppendEntries）      │
  │                                          │
  │  日志复制：                                │
  │  │   1. 客户端写请求 → Leader             │
  │  │   2. Leader 写本地日志                 │
  │  │   3. 发送 AppendEntries 到 Follower    │
  │  │   4. 多数 Follower 确认 → commit       │
  │  │   5. apply 到状态机                    │
  │                                          │
  │  Nacos Raft 实现（1.x）：                  │
  │  │   JRaft（基于 SOFAJRaft）               │
  │  │   2.x → 简化，持久数据用简化 Raft       │
  └──────────────────────────────────────────┘
```

---

## 1.8 Spring Cloud Nacos 自动装配（NacosServiceRegistryAutoConfiguration）

### 1.8.1 自动装配入口

```java
// NacosServiceRegistryAutoConfiguration
@Configuration
public class NacosServiceRegistryAutoConfiguration {
    
    @Bean
    public NacosServiceRegistry nacosServiceRegistry(
            NacosDiscoveryProperties properties,
            NacosServiceInstance instance) {
        return new NacosServiceRegistry(properties);
    }
    
    @Bean
    @ConditionalOnMissingBean
    public NacosRegistration nacosRegistration(
            NacosDiscoveryProperties properties) {
        return new NacosRegistration(properties);
    }
    
    @Bean
    public NacosAutoServiceRegistration nacosAutoServiceRegistration(
            NacosServiceRegistry registry,
            NacosRegistration registration) {
        return new NacosAutoServiceRegistration(registry, registration);
    }
}

// ──── 注册流程 ────
// Spring Cloud 启动 → AbstractAutoServiceRegistration.onApplicationEvent
// → WebServerInitializedEvent（端口就绪）
// → NacosAutoServiceRegistration.register()
// → NacosServiceRegistry.register(registration)
// → NacosNamingService.registerInstance(...)
```

### 1.8.2 配置中心自动装配

```java
// NacosConfigAutoConfiguration
@Configuration
public class NacosConfigAutoConfiguration {
    
    @Bean
    public NacosConfigProperties nacosConfigProperties() {
        return new NacosConfigProperties();
    }
    
    @Bean
    public NacosConfigService nacosConfigService(NacosConfigProperties properties) {
        return new NacosConfigService(properties);
    }
    
    @Bean
    public NacosPropertySourceLocator nacosPropertySourceLocator(
            NacosConfigService configService) {
        return new NacosPropertySourceLocator(configService);
    }
}

// ──── 配置加载流程 ────
// Spring Cloud Bootstrap 阶段
// → PropertySourceLocator.locate()
// → NacosPropertySourceLocator.locate()
//   ├── 加载共享配置（shared-configs）
//   ├── 加载扩展配置（extension-configs）
//   ├── 加载应用配置（dataId = ${spring.application.name}.${file-extension})
//   → 每个配置 → NacosConfigService.getConfig()
//   → 转为 NacosPropertySource → 加入 Environment
```

### 1.8.3 配置动态刷新

```java
// @RefreshScope 机制
// 1. NacosContextRefresher 注册 Listener
@Configuration
public class NacosConfigListenerAutoConfiguration {
    @Bean
    public NacosContextRefresher nacosContextRefresher(
            NacosConfigService configService,
            NacosRefreshProperties properties) {
        return new NacosContextRefresher(configService, properties);
    }
}

// 2. NacosContextRefresher 启动时注册监听
public class NacosContextRefresher implements ApplicationListener<ApplicationReadyEvent> {
    @Override
    public void onApplicationEvent(ApplicationReadyEvent event) {
        // 对每个 NacosPropertySource 注册 Listener
        for (NacosPropertySource source : nacosPropertySources) {
            configService.addListener(
                source.getDataId(), source.getGroup(), 
                new NacosRefreshListener(source));
        }
    }
}

// 3. Listener 回调 → 发布 RefreshEvent
class NacosRefreshListener implements Listener {
    @Override
    public void receiveConfigInfo(String configInfo) {
        // 配置变更 → 发布 RefreshEvent
        applicationEventPublisher.publishEvent(
            new RefreshEvent(this, configInfo, "Nacos config refresh"));
    }
}

// 4. RefreshEvent → RefreshEventListener.handle()
// → ContextRefresher.refresh()
//   ├── 重新拉取配置 → 更新 Environment
//   ├── 找到 @RefreshScope Bean → 销毁
//   │   RefreshScope.clear()
//   │   → 下次访问时重新创建（带新配置）
//   └── 发布 EnvironmentChangeEvent
```

---

## 1.9 Nacos 源码面试高频题

| # | 问题 | 核心答案 |
|---|------|----------|
| 1 | Nacos 如何保证服务注册的实时性？ | 1.x UDP推送+定时拉取(6s/30s)；2.x gRPC长连接推送，变更<500ms感知 |
| 2 | Nacos AP 和 CP 模式怎么选？ | 临时实例→Distro(AP，可用性优先)；持久实例→Raft(CP，一致性优先) |
| 3 | Nacos 和 Eureka 区别？ | Nacos支持AP+CP、配置中心、权重路由、gRPC；Eureka只有AP+REST+无配置 |
| 4 | Nacos 配置变更如何实时推送？ | 客户端长轮询(29.5s hold)，服务端变更→asyncContext.complete立即返回 |
| 5 | Nacos 集群如何同步数据？ | 临时→Distro异步复制(各节点负责部分数据)；持久→Raft日志复制(Leader写) |
| 6 | Nacos 客户端如何容灾？ | 本地缓存+failover磁盘文件+定时写盘；服务器不可达→从本地文件读取 |
| 7 | Nacos 2.x 比 1.x 有哪些改进？ | gRPC长连接替代UDP+HTTP心跳；连接断开2s感知vs1.x30s；配置gRPC推送 |
| 8 | Nacos 配置的 md5 作用？ | 快速比对配置是否变更，避免全量对比content；长轮询body传md5而非content |
| 9 | @RefreshScope 原理？ | 配置变更→销毁@RefreshScope Bean→下次访问重新创建(新配置注入) |
| 10 | Nacos 心跳超时如何处理？ | 15s未心跳→标记不健康→推送给订阅者；30s未心跳→删除实例→Distro同步删除 |

---

# 第二部分：Sentinel — 流控 + 熔断 + 系统保护

---

## 2.1 Sentinel 整体架构（Slot Chain）

### 2.1.1 Slot Chain 全景图

```
Sentinel 核心处理链 — Slot Chain
  ┌────────────────────────────────────────────────────┐
  │  SphU.entry("resourceName")                        │
  │  │                                                 │
  │  ├── ① NodeSelectorSlot                           │
  │  │   创建 Context 和 EntranceNode / DefaultNode     │
  │  │   树状统计节点体系                                │
  │  │                                                 │
  │  ├── ② ClusterBuilderSlot                         │
  │  │   创建 ClusterNode（全局统计）                     │
  │  │   绑定 ClusterNode → DefaultNode                 │
  │  │                                                 │
  │  ├── ③ LogSlot                                    │
  │  │   记录异常日志                                    │
  │  │                                                 │
  │  ├── ④ StatisticSlot                              │
  │  │   实时数据统计（滑动窗口）                          │
  │  │   pass / block / success / exception / rt        │
  │  │                                                 │
  │  ├── ⑤ AuthoritySlot                             │
  │  │   黑白名单授权控制                                 │
  │  │                                                 │
  │  ├── ⑥ SystemSlot                                │
  │  │   系统自适应保护（Load / CPU / RT / 入口QPS）      │
  │  │                                                 │
  │  ├── ⑦ FlowSlot                                  │
  │  │   流量控制（QPS / Thread / 关联 / 链路）           │
  │  │                                                 │
  │  ├── ⑧ DegradeSlot                               │
  │  │   熔断降级（慢调用比例 / 异常比例 / 异常数）        │
  │  │                                                 │
  │  ├── ⑨ SlotChainProvider.customSlots               │
  │  │   用户自定义 Slot                                 │
  │  │                                                 │
  │  ├── ★ 业务逻辑                                    │
  │  │   try { businessCode(); }                       │
  │  │                                                 │
  │  ├── ⑩⑨⑧⑦⑥⑤④③②① exit 逆序处理                  │
  │  │   StatisticSlot.recordSuccess / recordException  │
  │  │   DegradeSlot 记录 RT                            │
  │  │                                                 │
  └── 如果某 Slot 触发规则 → 抛 BlockException          │
      │   → 不进入后续 Slot                              │
      │   → 直接跳到 exit                                │
      └─────────────────────────────────────────────────┘
```

### 2.1.2 ProcessorSlotChain 构建

```java
// SlotChainProvider — 构建 Slot Chain
public class SlotChainProvider {
    private static final SpiLoader<ProcessorSlot> SPI_LOADER = 
        SpiLoader.of(ProcessorSlot.class);
    
    public static ProcessorSlotChain newSlotChain() {
        // 1. 从 SPI 加载默认 Slot 链
        //    sentinel-core 的 META-INF/services/com.alibaba.csp.sentinel.slotchain.ProcessorSlot
        //    内容：按顺序排列的 Slot 实现类
        
        ProcessorSlotChain chain = new DefaultProcessorSlotChain();
        
        // 2. 添加默认 Slot（按优先级排序）
        //    优先级通过 @Spi(order=N) 注解指定
        chain.addLast(nodeSelectorSlot);     // order=-10000
        chain.addLast(clusterBuilderSlot);    // order=-9000
        chain.addLast(logSlot);              // order=-8000
        chain.addLast(statisticSlot);        // order=-7000
        chain.addLast(authoritySlot);        // order=-6000
        chain.addLast(systemSlot);           // order=-5000
        chain.addLast(flowSlot);             // order=-4000
        chain.addLast(degradeSlot);          // order=-3000
        
        // 3. 加载用户自定义 Slot（SPI 扩展）
        List<ProcessorSlot> customSlots = SPI_LOADER.loadInstanceList();
        for (ProcessorSlot slot : customSlots) {
            chain.addLast(slot);
        }
        
        return chain;
    }
}

// DefaultProcessorSlotChain — 链式调用
public class DefaultProcessorSlotChain extends ProcessorSlotChain {
    // 链头 AbstractLinkedProcessorSlot
    // 每个Slot通过 next 字段连接下一个
    
    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, Object... params) {
        // 首先调用第一个 Slot 的 entry
        first.entry(context, resourceWrapper, params);
    }
    
    @Override
    public void exit(Context context, ResourceWrapper resourceWrapper, int count, Object... params) {
        // 首先调用第一个 Slot 的 exit
        first.exit(context, resourceWrapper, count, params);
    }
}

// AbstractLinkedProcessorSlot — 单个 Slot
public abstract class AbstractLinkedProcessorSlot<T> {
    protected AbstractLinkedProcessorSlot<?> next;  // 下一个 Slot
    
    public void fireEntry(Context context, ResourceWrapper resourceWrapper, Object... params) {
        if (next != null) {
            next.entry(context, resourceWrapper, params);  // 传递给下一个
        }
    }
    
    public void fireExit(Context context, ResourceWrapper resourceWrapper, int count) {
        if (next != null) {
            next.exit(context, resourceWrapper, count);  // 传递给下一个
        }
    }
}
```

---

## 2.2 Entry 与 Context 模型（ContextUtil.enter / CtEntry）

### 2.2.1 Context 创建与 Entry 入口

```java
// 使用方式
Entry entry = null;
try {
    entry = SphU.entry("orderService");
    // 执行业务逻辑
    doBusiness();
} catch (BlockException e) {
    // 流控/熔断拦截
    handleBlock(e);
} catch (Exception e) {
    // 业务异常 → 记录到 DegradeSlot
    Tracer.trace(e);
} finally {
    if (entry != null) {
        entry.exit();
    }
}

// ──── entry 创建流程 ────
SphU.entry(resourceName)
    │
    ├── CtSph.entry(resourceName, EntryType.IN, 1, args)
    │   │
    │   ├── 1. ContextUtil.enter(contextName, origin)
    │   │   │   如果当前线程无 Context → 创建
    │   │   │   │   context = new Context(node, contextName);
    │   │   │   │   context.setOrigin(origin);  // 来源（调用方）
    │   │   │   │   ThreadLocal<Context> contextThreadLocal.set(context);
    │   │   │
    │   ├── 2. 查找或创建 ProcessorSlotChain
    │   │   │   chain = SlotChainProvider.newSlotChain();
    │   │   │   // 每个 Resource 对应一个 chain（缓存）
    │   │   │   chainMap.put(resourceWrapper, chain);
    │   │   │
    │   ├── 3. 创建 CtEntry
    │   │   │   entry = new CtEntry(resourceWrapper, chain, context);
    │   │   │   // 入栈：context.curEntry = entry
    │   │   │   // 如果有上一个 Entry → entry.parent = lastEntry
    │   │   │
    │   ├── 4. 执行 Slot Chain
    │   │   │   chain.entry(context, resourceWrapper, 1, args);
    │   │   │   // 从 NodeSelectorSlot 开始逐个执行
    │
    └── 5. 返回 entry
```

### 2.2.2 Entry 调用树模型

```
调用链嵌套示例：
  ──── Context: "order-context" ────
  
  entry1 = SphU.entry("orderService")       // 入口资源
      │
      ├── NodeSelectorSlot → 创建 EntranceNode("orderService")
      ├── ClusterBuilderSlot → 创建 ClusterNode("orderService")
      │
      ├── entry2 = SphU.entry("payService")   // 下游资源
      │   │
      │   ├── NodeSelectorSlot → 创建 DefaultNode("payService")
      │   │   // 挂在 EntranceNode("orderService") 下
      │   ├── ClusterBuilderSlot → 创建 ClusterNode("payService")
      │   │
      │   ├── StatisticSlot → 统计 payService 的 pass/block/rt
      │   ├── FlowSlot → 检查 payService 流控规则
      │   ├── DegradeSlot → 检查 payService 熔断规则
      │   │
      │   ├── entry3 = SphU.entry("dbQuery")    // 更下游
      │   │   ├── ... 同上结构 ...
      │   │   └── entry3.exit()
      │   │
      │   └── entry2.exit()
      │
      ├── entry1.exit()

  统计节点树：
  ──── EntranceNode("orderService") ────
      ├── DefaultNode("orderService")
      │   └── ClusterNode("orderService")
      ├── DefaultNode("payService")
      │   └── ClusterNode("payService")
      └── DefaultNode("dbQuery")
          └── ClusterNode("dbQuery")
  
  ClusterNode = 全局统计（跨 Context 共享）
  DefaultNode = 当前调用路径统计（特定 Context 下）
  EntranceNode = 入口总统计
```

---

## 2.3 滑动窗口统计（LeapArray + WindowWrap + MetricBucket）

### 2.3.1 滑动窗口原理图

```
滑动时间窗口（LeapArray）
  时间轴（ms）：
  
  ──0────1000────2000────3000────4000────5000─── 当前时间=4600ms
    │       │       │       │       │       │
    │  W0   │  W1   │  W2   │  W3   │  W4   │
    │1000ms │1000ms │1000ms │1000ms │1000ms │
    │       │       │       │       │       │
    │pass=5 │pass=8 │pass=12│pass=6 │pass=3 │
    │block=1│block=0│block=2│block=1│       │
    │rt=50  │rt=80  │rt=120 │rt=45  │       │
    
  窗口长度 windowLengthInMs = 1000ms
  采样数 sampleCount = 10（10个1s窗口）
  总时间 intervalInMs = 10000ms
  
  当前时间 4600ms → 窗口索引 = (4600 / 1000) % 10 = 4
  窗口起始时间 = 4600 - (4600 % 1000) = 4000ms
  
  过期窗口判断：
  │  当前时间 - windowStart > intervalInMs → 过期 → 重置
  │  W0(0ms) : 4600 - 0 = 4600 > 10000? No → 有效
  │  但如果时间到了 11000ms → W0(0ms): 11000-0 > 10000 → 过期 → 重置为 W0(10000ms)
```

### 2.3.2 LeapArray 核心源码

```java
// LeapArray — 滑动窗口数组
public abstract class LeapArray<T> {
    protected int windowLengthInMs;    // 单个窗口时长（如 1000ms）
    protected int sampleCount;        // 窗口数量（如 10）
    protected int intervalInMs;       // 总时间跨度（如 10000ms）
    
    // 窗口数组（AtomicReferenceArray，线程安全）
    protected AtomicReferenceArray<WindowWrap<T>> array;
    
    // ──── 核心方法：根据时间定位窗口 ────
    public WindowWrap<T> currentWindow(long timeMillis) {
        // 1. 计算窗口索引
        int idx = calculateTimeIdx(timeMillis);
        //    idx = (timeMillis / windowLengthInMs) % sampleCount
        
        // 2. 计算窗口起始时间
        long windowStart = calculateWindowStart(timeMillis);
        //    windowStart = timeMillis - (timeMillis % windowLengthInMs)
        
        // 3. 获取或创建窗口
        while (true) {
            WindowWrap<T> old = array.get(idx);
            
            if (old == null) {
                // 窗口不存在 → 创建新窗口
                WindowWrap<T> window = new WindowWrap<>(windowLengthInMs, 
                    windowStart, newEmptyBucket());
                if (array.compareAndSet(idx, null, window)) {
                    return window;
                }
            } else if (windowStart == old.windowStart()) {
                // 窗口起始时间匹配 → 直接返回
                return old;
            } else if (windowStart > old.windowStart() + intervalInMs) {
                // 窗口过期 → 重置
                return resetWindowTo(old, windowStart);
            } else {
                // 窗口正在被其他线程更新 → 等待
                Thread.yield();
            }
        }
    }
    
    // ──── 获取时间范围内的所有有效窗口 ────
    public List<WindowWrap<T>> values(long startTime, long endTime) {
        List<WindowWrap<T>> result = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            WindowWrap<T> window = array.get(i);
            if (window == null) continue;
            
            // 过期窗口跳过
            if (currentTimeMillis() - window.windowStart() > intervalInMs) {
                continue;
            }
            
            // 时间范围内的窗口
            if (window.windowStart() >= startTime && 
                window.windowStart() + windowLengthInMs <= endTime) {
                result.add(window);
            }
        }
        return result;
    }
}

// WindowWrap — 窗口包装器
public class WindowWrap<T> {
    private long windowStart;         // 窗口起始时间(ms)
    private int windowLengthInMs;     // 窗口长度(ms)
    private T value;                  // 窗口数据（MetricBucket）
}

// MetricBucket — 统计桶
public class MetricBucket {
    // 计数器（LongAdder，高性能原子计数）
    private LongAdder[] counters;  // 索引对应 MetricEvent
    
    // MetricEvent 枚举：
    //   PASS     — 通过数
    //   BLOCK    — 拦截数
    //   EXCEPTION — 异常数
    //   SUCCESS  — 成功数
    //   RT       — 响应时间总和(ms)
    //   OCCUPIED_PASS — 预占用通过数
    
    public long get(MetricEvent event) {
        return counters[event.ordinal()].sum();
    }
    
    public void add(MetricEvent event, long n) {
        counters[event.ordinal()].add(n);
    }
}
```

### 2.3.3 StatisticSlot 统计流程

```java
// StatisticSlot — 核心统计 Slot
@Spi(order = -7000)
public class StatisticSlot extends AbstractLinkedProcessorSlot<DefaultNode> {
    
    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, 
                      int count, Object... args) throws Throwable {
        // 先让后续 Slot 检查（流控/熔断）
        try {
            fireEntry(context, resourceWrapper, count, args);
            
            // 通过 → 记录统计数据
            // 1. 增加 pass 计数
            node.increasePassQps(count);
            // 2. 增加 thread 数
            node.increaseThreadNum();
            // 3. 记录来源统计
            if (context.getOrigin() != null) {
                originNode.increasePassQps(count);
            }
            // 4. 入口统计
            if (resourceWrapper.getEntryType() == EntryType.IN) {
                entranceNode.increasePassQps(count);
            }
            
        } catch (BlockException e) {
            // 被拦截 → 记录 block 统计
            node.increaseBlockQps(count);
            if (context.getOrigin() != null) {
                originNode.increaseBlockQps(count);
            }
            entranceNode.increaseBlockQps(count);
            
            // 抛出 BlockException → 不再进入后续 Slot
            throw e;
        }
    }
    
    @Override
    public void exit(Context context, ResourceWrapper resourceWrapper, 
                     int count, Object... args) {
        // 1. 减少 thread 数
        node.decreaseThreadNum();
        
        // 2. 记录响应时间(RT)
        long rt = System.currentTimeMillis() - entry.getCreateTime();
        node.addRt(rt);
        
        // 3. 如果有异常
        if (context.getCurEntry().getError() != null) {
            node.increaseExceptionQps(count);
        } else {
            node.increaseSuccessQps(count);
        }
        
        fireExit(context, resourceWrapper, count, args);
    }
}
```

---

## 2.4 FlowSlot — 流控规则源码（FlowRuleChecker.canPass）

### 2.4.1 流控规则数据结构

```java
// FlowRule — 流控规则
public class FlowRule {
    private String resource;          // 资源名
    private int grade;                // 限流阈值类型
    //   RuleConstant.FLOW_GRADE_QPS = 1  (QPS 限流)
    //   RuleConstant.FLOW_GRADE_THREAD = 0 (线程数限流)
    
    private double count;             // 限流阈值
    //   grade=QPS → count=100 表示 QPS上限100
    //   grade=THREAD → count=10 表示并发线程上限10
    
    private int strategy;             // 流控策略
    //   RuleConstant.STRATEGY_DIRECT = 0   (直接限流)
    //   RuleConstant.STRATEGY_RELATE = 1   (关联限流)
    //   RuleConstant.STRATEGY_CHAIN = 2    (链路限流)
    
    private String refResource;       // 关联资源名（strategy=RELATE时）
    private int controlBehavior;      // 流控效果
    //   RuleConstant.CONTROL_BEHAVIOR_DEFAULT = 0  (直接拒绝)
    //   RuleConstant.CONTROL_BEHAVIOR_WARM_UP = 1  (预热/冷启动)
    //   RuleConstant.CONTROL_BEHAVIOR_RATE_LIMITER = 2 (匀速排队)
    //   RuleConstant.CONTROL_BEHAVIOR_WARM_UP_RATE_LIMITER = 3 (预热+匀速)
    
    private boolean clusterMode;      // 是否集群限流
    private ClusterFlowConfig clusterConfig; // 集群限流配置
    private int warmUpPeriodSec = 10; // 预热时间（秒）
    private int maxQueueingTimeMs = 500; // 最大排队时间(ms)
}
```

### 2.4.2 FlowSlot 检查流程

```java
// FlowSlot
@Spi(order = -4000)
public class FlowSlot extends AbstractLinkedProcessorSlot<DefaultNode> {
    
    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, 
                      int count, Object... args) throws Throwable {
        // 流控规则检查
        FlowRuleChecker.checkFlow(resourceWrapper, context, node, count);
        
        fireEntry(context, resourceWrapper, count, args);
    }
}

// FlowRuleChecker — 流控检查核心
public class FlowRuleChecker {
    
    public static void checkFlow(ResourceWrapper resource, Context context,
                                  DefaultNode node, int count) {
        // 1. 获取该资源的所有流控规则
        List<FlowRule> rules = FlowRuleManager.getRules(resource.getName());
        
        // 2. 逐条检查
        for (FlowRule rule : rules) {
            if (!canPassCheck(rule, context, node, count)) {
                // 触发限流 → 抛出 FlowException
                throw new FlowException(rule.getResource(), rule);
            }
        }
    }
    
    // ──── canPassCheck ────
    public static boolean canPassCheck(FlowRule rule, Context context, 
                                        DefaultNode node, int count) {
        // 根据策略选择统计节点
        Node selectedNode = selectNode(rule, context, node);
        if (selectedNode == null) return true;
        
        // 根据限流模式选择检查器
        if (rule.isClusterMode()) {
            // 集群限流 → ClusterFlowChecker
            return passClusterCheck(rule, selectedNode, count);
        } else {
            // 单机限流 → TrafficShapingController
            return rule.getRater().canPass(selectedNode, count);
        }
    }
    
    // ──── selectNode — 根据策略选择统计节点 ────
    private static Node selectNode(FlowRule rule, Context context, DefaultNode node) {
        switch (rule.getStrategy()) {
            case STRATEGY_DIRECT:
                // 直接限流 → 使用当前资源的 ClusterNode（全局统计）
                return node.getClusterNode();
                
            case STRATEGY_RELATE:
                // 关联限流 → 使用关联资源的 ClusterNode
                //   当关联资源 QPS 超阈值 → 限流当前资源
                ClusterNode relateNode = ClusterBuilderSlot.getClusterNode(rule.getRefResource());
                return relateNode;
                
            case STRATEGY_CHAIN:
                // 链路限流 → 使用来源统计节点
                //   只统计来自特定调用方的 QPS
                String origin = context.getOrigin();
                if (origin == null) return null;
                DefaultNode originNode = node.getOriginNode(origin);
                return originNode;
        }
    }
}
```

### 2.4.3 流控效果实现（TrafficShapingController）

```java
// ──── 1. DefaultController — 直接拒绝 ────
public class DefaultController implements TrafficShapingController {
    private double count;  // QPS 阈值
    private int grade;     // QPS or THREAD
    
    @Override
    public boolean canPass(Node node, int acquireCount) {
        int currentQps = (int) node.passQps();  // 当前已通过QPS
        
        if (currentQps + acquireCount > count) {
            // 超阈值 → 拒绝
            return false;
        }
        return true;
    }
}

// ──── 2. WarmUpController — 预热/冷启动 ────
// 使用 Guava RateLimiter 的预热算法
// 冷启动：初始阈值 = count/3，逐渐升高到 count
// 适用场景：冷系统刚启动，缓存未加载，防止瞬间流量打崩
public class WarmUpController implements TrafficShapingController {
    private double count;           // 最大 QPS
    private int warmUpPeriodSec;    // 预热时长
    private double coldFactor = 3;  // 冷因子
    
    // 预热令牌桶（基于 Guava SmoothWarmingUp）
    private double storedTokens;     // 当前存储令牌
    private double maxTokens;        // 最大令牌数
    private double stableInterval;   // 稳定时间间隔(ms/request)
    private double coldInterval;     // 冷时间间隔
    
    @Override
    public boolean canPass(Node node, int acquireCount) {
        long passQps = node.passQps();
        long lastPassQps = node.previousPassQps(); // 前一秒QPS
        
        // 同步令牌
        syncToken(lastPassQps);
        
        // 计算剩余令牌
        double restToken = storedTokens - acquireCount;
        
        if (restToken >= 0) {
            // 有足够令牌 → 通过（但间隔可能比稳定期长）
            storedTokens -= acquireCount;
            return true;
        }
        
        // 令牌不足 → 判断是否在预热期
        double expectedInterval = calculateInterval(restToken);
        long currentTime = System.currentTimeMillis();
        long lastTime = node.lastPassTime();
        
        if (currentTime - lastTime > expectedInterval) {
            // 时间间隔满足 → 通过
            storedTokens -= acquireCount;
            return true;
        }
        return false;
    }
    
    // 预热曲线：
    // QPS
    // │         ┌──────────────────── count (最大QPS)
    // │        /
    // │       /  ← 预热阶段，QPS逐渐升高
    // │      /
    // │     /
    // │    ┌────── count/coldFactor (初始QPS ≈ count/3)
    // │
    // └────────────────── 时间 →
    //      |← warmUpPeriodSec →|
}

// ──── 3. RateLimiterController — 匀速排队 ────
// 使用虚拟队列，请求匀速通过
// 适用场景：突发流量削峰填谷
public class RateLimiterController implements TrafficShapingController {
    private double count;            // QPS 阈值
    private int maxQueueingTimeMs;   // 最大排队时间
    
    @Override
    public boolean canPass(Node node, int acquireCount) {
        // 计算每个请求的间隔
        long intervalInMs = 1000 * acquireCount / (long)count;
        // 例：count=100 → interval=10ms
        
        long currentTime = System.currentTimeMillis();
        long lastPassTime = node.lastPassTime();
        
        // 计算期望通过时间
        long expectedTime = lastPassTime + intervalInMs;
        
        if (expectedTime <= currentTime) {
            // 无排队 → 直接通过
            node.setLastPassTime(currentTime);
            return true;
        }
        
        // 需要排队
        long waitTime = expectedTime - currentTime;
        if (waitTime > maxQueueingTimeMs) {
            // 排队超时 → 拒绝
            return false;
        }
        
        // 排队等待 → sleep 后通过
        try {
            Thread.sleep(waitTime);
        } catch (InterruptedException e) {
            return false;
        }
        node.setLastPassTime(expectedTime);
        return true;
    }
}
```

### 2.4.4 四种流控效果对比

```
  ┌──────────────────────────────────────────────────────┐
  │  流控效果对比                                         │
  │                                                      │
  │  ┌───────┬────────┬────────┬──────────┬───────────┐  │
  │  │效果   │直接拒绝 │预热冷启│匀速排队   │预热+匀速  │  │
  │  ├───────┼────────┼────────┼──────────┼───────────┤  │
  │  │超阈值 │立即拒绝 │渐进放行│排队等待   │渐进排队   │  │
  │  │       │        │        │          │           │  │
  │  │曲线   │阶梯函数 │指数增长│匀速线性   │指数→匀速  │  │
  │  │       │  ┌─    │   /    │  ─────── │    /───── │  │
  │  │       │  │     │  /     │          │   /       │  │
  │  │       │  │     │ /      │          │  /        │  │
  │  │       │  │     │/       │          │ /         │  │
  │  │       │  └──   │──      │          │──         │  │
  │  │       │        │        │          │           │  │
  │  │适用   │精确限流 │冷启动  │削峰填谷   │冷启动+   │  │
  │  │场景   │        │缓存预热│消息队列   │削峰填谷   │  │
  │  │       │        │        │流量平滑  │           │  │
  │  └────────┴────────┴────────┴──────────┴───────────┘  │
  └──────────────────────────────────────────────────────┘
```

---

## 2.5 DegradeSlot — 熔断降级源码（CircuitBreaker 三种策略）

### 2.5.1 熔断规则数据结构

```java
// DegradeRule — 熔断规则
public class DegradeRule {
    private String resource;         // 资源名
    private int grade;               // 熔断策略
    //   CircuitBreakerStrategy.SLOW_REQUEST_RATIO = 0 (慢调用比例)
    //   CircuitBreakerStrategy.ERROR_RATIO = 1 (异常比例)
    //   CircuitBreakerStrategy.ERROR_COUNT = 2 (异常数)
    
    private double count;            // 阈值
    //   grade=0 → 慢调用RT阈值(ms)，如 200ms
    //   grade=1 → 异常比例阈值，如 0.5 (50%)
    //   grade=2 → 异常数阈值，如 10
    
    private int timeWindow;          // 熔断持续时间(s)
    private int minRequestAmount;    // 最小请求数（触发熔断的前提）
    //   例：minRequestAmount=5 → 至少5个请求才计算比例
    private double slowRatioThreshold; // 慢调用比例阈值（grade=0时）
}
```

### 2.5.2 CircuitBreaker 三种策略实现

```java
// ──── CircuitBreaker 接口 ────
public interface CircuitBreaker {
    boolean tryPass(Context context);     // 尝试通过
    void onRequestComplete(long rt, boolean exception);  // 请求完成回调
    State currentState();                 // 当前状态
    
    enum State {
        CLOSED,      // 关闭（正常放行）
        OPEN,        // 打开（熔断拦截）
        HALF_OPEN    // 半开（试探放行）
    }
}

// ──── 1. ExceptionCircuitBreaker — 异常比例/异常数 ────
public class ExceptionCircuitBreaker implements CircuitBreaker {
    private double threshold;           // 比例阈值
    private int minRequestAmount;       // 最小请求数
    private int timeWindow;             // 熔断时长(s)
    private int strategy;               // ERROR_RATIO or ERROR_COUNT
    
    // 滑动窗口统计
    private LeapArray<SimpleCounterData> slidingWindow;
    
    @Override
    public boolean tryPass(Context context) {
        switch (currentState) {
            case CLOSED:
                // 关闭状态 → 放行
                return true;
                
            case OPEN:
                // 打开状态 → 判断是否到了半开时间
                if (System.currentTimeMillis() - nextRetryTimestamp > timeWindow * 1000) {
                    // 熔断时长已过 → 进入半开
                    currentState = State.HALF_OPEN;
                    return true;  // 允许试探请求
                }
                return false;  // 继续熔断
                
            case HALF_OPEN:
                // 半开 → 只放行一个试探请求
                return false;
        }
    }
    
    @Override
    public void onRequestComplete(long rt, boolean exception) {
        // 记录统计数据
        SimpleCounterData data = slidingWindow.currentWindow().value();
        if (exception) {
            data.exceptionCount++;
        }
        data.totalCount++;
        
        // 检查是否触发熔断
        if (data.totalCount >= minRequestAmount) {
            double exceptionRatio = data.exceptionCount / (double)data.totalCount;
            
            if (strategy == ERROR_RATIO && exceptionRatio >= threshold) {
                // 异常比例超阈值 → 熔断
                transformToOpen();
            }
            if (strategy == ERROR_COUNT && data.exceptionCount >= (int)threshold) {
                // 异常数超阈值 → 熔断
                transformToOpen();
            }
        }
        
        // 半开状态下的试探请求结果
        if (currentState == State.HALF_OPEN) {
            if (exception) {
                // 试探失败 → 重新熔断
                transformToOpen();
            } else {
                // 试探成功 → 关闭熔断
                transformToClosed();
            }
        }
    }
    
    private void transformToOpen() {
        currentState = State.OPEN;
        nextRetryTimestamp = System.currentTimeMillis() + timeWindow * 1000;
    }
}

// ──── 2. SlowRequestCircuitBreaker — 慢调用比例 ────
public class SlowRequestCircuitBreaker implements CircuitBreaker {
    private double maxAllowedRt;         // 慢调用RT阈值(ms)
    private double slowRatioThreshold;   // 慢调用比例阈值
    private int minRequestAmount;
    private int timeWindow;
    
    // 滑动窗口
    private LeapArray<SlowCounterData> slidingWindow;
    
    @Override
    public void onRequestComplete(long rt, boolean exception) {
        SlowCounterData data = slidingWindow.currentWindow().value();
        data.totalCount++;
        
        // 判断是否是慢调用
        if (rt > maxAllowedRt || exception) {
            data.slowCount++;
        }
        
        // 检查比例
        if (data.totalCount >= minRequestAmount) {
            double slowRatio = data.slowCount / (double)data.totalCount;
            if (slowRatio >= slowRatioThreshold) {
                transformToOpen();
            }
        }
        
        // 半开试探
        if (currentState == State.HALF_OPEN) {
            if (rt > maxAllowedRt || exception) {
                transformToOpen();
            } else {
                transformToClosed();
            }
        }
    }
}
```

### 2.5.3 熔断状态转换图

```
  猪断状态转换（三态模型）
  
  ┌──────────────────────────────────────────────────────────┐
  │                                                          │
  │   CLOSED (正常放行)                                       │
  │   │                                                      │
  │   │ 统计数据满足熔断条件                                   │
  │   │ (异常比例 ≥ threshold / 慢调用比例 ≥ threshold)       │
  │   │                                                      │
  │   ▼                                                      │
  │                                                          │
  │   OPEN (熔断拦截)                                         │
  │   │                                                      │
  │   │ 等待 timeWindow 秒                                    │
  │   │                                                      │
  │   ▼                                                      │
  │                                                          │
  │   HALF_OPEN (半开试探)                                    │
  │   │                                                      │
  │   ├── 试探请求成功 → ──────▶ CLOSED                       │
  │   │                                                      │
  │   ├── 试探请求失败 → ──────▶ OPEN (重新熔断)              │
  │   │                                                      │
  └──────────────────────────────────────────────────────────┘
  
  时间线示例：
  
  ──0────5────10────15────20────25────30── 时间(s)
    │     │     │     │     │     │     │
    正常  正常  熔断  熔断  半开  正常  正常
    │     │     │     │     │     │     │
    │     │     │← 熔断5s →│     │     │
    │     │     │         │试探  │     │
    │     │  异常比例达50%  │成功  │     │
    │     │     │         │→CLOSE │     │
```

---

## 2.6 SystemSlot — 系统自适应保护

```java
// SystemSlot — 系统级保护
@Spi(order = -5000)
public class SystemSlot extends AbstractLinkedProcessorSlot<DefaultNode> {
    
    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper, 
                      int count, Object... args) throws Throwable {
        // 检查系统规则
        SystemRuleManager.checkSystem(context);
        
        fireEntry(context, resourceWrapper, count, args);
    }
}

// SystemRuleManager — 系统规则检查
public class SystemRuleManager {
    // 系统保护规则（全局配置）
    private static volatile double maxLoad = -1;      // 最大系统 Load
    private static volatile double maxCpuUsage = -1;   // 最大 CPU 使用率
    private static volatile double maxRt = -1;         // 最大平均 RT(ms)
    private static volatile long maxThread = -1;       // 最大并发线程数
    private static volatile double maxGlobalQps = -1;  // 最大入口总 QPS
    
    public static void checkSystem(Context context) {
        // 只对入口资源（EntryType.IN）检查
        if (context.getEntranceNode() == null) return;
        
        EntranceNode entranceNode = context.getEntranceNode();
        
        // 1. 检查系统 Load（仅 Linux）
        double currentLoad = getCurrentLoad();
        if (currentLoad > maxLoad) {
            // 系统过载 → 拒绝新请求
            throw new SystemBlockException(resource, "load");
        }
        
        // 2. 检查 CPU 使用率
        double currentCpu = getCpuUsage();
        if (currentCpu > maxCpuUsage) {
            throw new SystemBlockException(resource, "cpu");
        }
        
        // 3. 检查平均 RT
        double avgRt = entranceNode.avgRt();
        if (avgRt > maxRt) {
            throw new SystemBlockException(resource, "rt");
        }
        
        // 4. 检查并发线程数
        long currentThread = entranceNode.currentThreadNum();
        if (currentThread > maxThread) {
            throw new SystemBlockException(resource, "thread");
        }
        
        // 5. 检查入口总 QPS
        double currentQps = entranceNode.passQps();
        if (currentQps > maxGlobalQps) {
            throw new SystemBlockException(resource, "qps");
        }
    }
}
```

---

## 2.7 AuthoritySlot / ClusterSlot / StatSlot

### 2.7.1 AuthoritySlot — 黑白名单授权

```java
// AuthoritySlot
@Spi(order = -6000)
public class AuthoritySlot extends AbstractLinkedProcessorSlot<DefaultNode> {
    
    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper,
                      int count, Object... args) throws Throwable {
        // 检查黑白名单
        AuthorityRuleManager.checkAuthority(resourceWrapper, context, node, count);
        
        fireEntry(context, resourceWrapper, count, args);
    }
}

// AuthorityRule — 授权规则
public class AuthorityRule {
    private String resource;   // 资源名
    private int strategy;      // AUTH_WHITE=0 白名单 / AUTH_BLACK=1 黑名单
    private String limitApp;   // 限制的来源应用（逗号分隔）
}

// 检查逻辑
public static void checkAuthority(ResourceWrapper resource, Context context) {
    List<AuthorityRule> rules = getRules(resource.getName());
    String origin = context.getOrigin();  // 调用方来源
    
    for (AuthorityRule rule : rules) {
        if (rule.getStrategy() == AUTH_WHITE) {
            // 白名单 → origin 必须在列表中
            if (!rule.getLimitApp().contains(origin)) {
                throw new AuthorityException(resource, rule);
            }
        } else {
            // 黑名单 → origin 不能在列表中
            if (rule.getLimitApp().contains(origin)) {
                throw new AuthorityException(resource, rule);
            }
        }
    }
}
```

---

## 2.8 Sentinel Spring Cloud Gateway 适配

### 2.8.1 Gateway 适配架构

```
  Spring Cloud Gateway + Sentinel 集成
  ┌──────────────────────────────────────────────────┐
  │  Gateway Filter Chain                             │
  │  │                                               │
  │  ├── SentinelGatewayFilter (全局过滤器)           │
  │  │   │                                           │
  │  │   ├── entry = SphU.entry(routeId)             │
  │  │   │   或 SphU.entry(apiName)                  │
  │  │   │                                           │
  │  │   ├── Slot Chain 执行                         │
  │  │   │   ├── FlowSlot → 检查路由流控             │
  │  │   │   ├── DegradeSlot → 检查熔断              │
  │  │   │                                           │
  │  │   ├── 被拦截 → BlockRequestHandler 处理       │
  │  │   │   → 返回 429 / 自定义响应                  │
  │  │   │                                           │
  │  │   ├── 正常通过 → 继续执行后续 Filter           │
  │  │   │                                           │
  │  │   ├── exit → 记录统计                         │
  │  │                                               │
  │  ├── 其他 GatewayFilter                          │
  │  │   ├── ReactiveLoadBalancerClientFilter        │
  │  │   ├── NettyRoutingFilter                     │
  │  │   └── ...                                    │
  │  │                                               │
  └──────────────────────────────────────────────────┘
  
  资源名定义方式：
  ┌─── SentinelGatewayConfig ───┐
  │  routeId 模式：               │
  │    资源名 = route.getId()     │
  │    如 "order-route"           │
  │                              │
  │  api分组模式：                 │
  │    资源名 = ApiDefinition     │
  │    如 "order-api-group"       │
  │                              │
  │  自定义模式：                  │
  │    SentinelGatewayFilter      │
  │    .getRequestPredicate()     │
  │    → 自定义匹配规则            │
  └──────────────────────────────┘
```

### 2.8.2 SentinelGatewayFilter 源码

```java
// SentinelGatewayFilter — 核心过滤器
public class SentinelGatewayFilter implements GlobalFilter, Ordered {
    
    private final GatewayFilterManager filterManager;
    
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        // 1. 获取路由ID
        Route route = exchange.getAttribute(GATEWAY_ROUTE_ATTR);
        String routeId = route.getId();
        
        // 2. 获取 API 定义名（如果配置了 api 分组）
        String apiName = getApiName(exchange);
        
        // 3. 确定 Sentinel 资源名
        String resourceName = apiName != null ? apiName : routeId;
        EntryType entryType = EntryType.IN;
        
        // 4. 创建 Sentinel Entry（异步适配）
        return Mono.fromCallable(() -> {
            // 同步创建 entry
            AsyncEntry entry = SphU.asyncEntry(resourceName, entryType);
            exchange.getAttributes().put(SENTINEL_ENTRY_ATTR, entry);
            return entry;
        })
        .flatMap(entry -> {
            // 5. 正常通过 → 执行后续 Filter
            return chain.filter(exchange)
                .doOnSuccess(v -> entry.exit())
                .doOnError(e -> {
                    if (e instanceof BlockException) {
                        // 6. 被拦截 → BlockRequestHandler 处理
                        handleBlockRequest(exchange, e);
                    } else {
                        // 7. 业务异常 → Tracer.trace
                        Tracer.trace(e);
                        entry.exit(1, e);
                    }
                });
        })
        .onErrorResume(BlockException.class, e -> {
            // 返回自定义拦截响应
            return blockRequestHandler.handleRequest(exchange, e);
        });
    }
}
```

---

## 2.9 Sentinel 源码面试高频题

| # | 问题 | 核心答案 |
|---|------|----------|
| 1 | Sentinel Slot Chain 执行顺序？ | NodeSelector→ClusterBuilder→Log→Statistic→Authority→System→Flow→Degrade→自定义 |
| 2 | Sentinel 滑动窗口原理？ | LeapArray，10个1s窗口覆盖10s，AtomicReferenceArray+CAS保证线程安全 |
| 3 | Sentinel 三种流控效果？ | 直接拒绝(DefaultController)、预热冷启动(WarmUpController)、匀速排队(RateLimiterController) |
| 4 | Sentinel 熔断三种策略？ | 慢调用比例(SlowRequest)、异常比例(ExceptionRatio)、异常数(ExceptionCount) |
| 5 | Sentinel 熔断状态转换？ | CLOSED→OPEN(满足条件)→HALF_OPEN(timeWindow到期)→CLOSED(试探成功)/OPEN(试探失败) |
| 6 | LeapArray 如何保证并发安全？ | AtomicReferenceArray+CAS，窗口创建用compareAndSet，窗口重置用CAS |
| 7 | Sentinel 关联限流原理？ | strategy=RELATE，使用关联资源的ClusterNode统计QPS，当关联资源超阈值→限流当前资源 |
| 8 | Sentinel 链路限流原理？ | strategy=CHAIN，使用originNode统计特定调用方QPS，只统计来自指定来源的流量 |
| 9 | Sentinel 预热算法来源？ | 基于 Guava SmoothWarmingUp，coldFactor=3，初始QPS=count/3逐渐升高到count |
| 10 | Sentinel 集群限流原理？ | TokenServer模式：TokenServer分配令牌，客户端向Server请求令牌；嵌入模式：某节点兼任Server |

---

## 2.10 Sentinel 规则配置持久化（Nacos 数据源）

### 2.10.1 规则推送模式

```
  Sentinel 规则持久化三种模式
  ┌──────────────────────────────────────────────────┐
  │                                                  │
  │  模式一：原始模式（默认）                          │
  │  │   规则推到 Sentinel → 内存中                   │
  │  │   应用重启 → 规则丢失                          │
  │  │   仅用于测试                                    │
  │                                                  │
  │  模式二：Pull 模式                                │
  │  │   客户端定时从数据源（文件/DB）拉取规则           │
  │  │   推送：控制台→DB→客户端定时拉取                 │
  │  │   问题：实时性差（30s延迟）                     │
  │                                                  │
  │  模式三：Push 模式（推荐，Nacos 数据源）           │
  │  │   推送：控制台→Nacos→客户端 Listener 实时接收   │
  │  │   数据源：NacosDataSource                      │
  │  │   实时性好，生产推荐                            │
  │                                                  │
  └──────────────────────────────────────────────────┘
```

```java
// NacosDataSource — Sentinel + Nacos 数据源
public class NacosDataSource<T> extends AbstractDataSource<T> {
    private final String dataId;
    private final String groupId;
    private final String namespace;
    private final ConfigService configService;
    
    // ──── 初始化 ────
    public NacosDataSource(String namespace, String groupId, 
                           String dataId, Converter<String, T> parser) {
        super(parser);
        this.configService = NacosFactory.createConfigService(
            createProperties(namespace));
        
        // 注册 Listener → 规则变更时实时更新
        configService.addListener(dataId, groupId, new Listener() {
            @Override
            public void receiveConfigInfo(String configInfo) {
                // 解析规则 → 更新到 RuleManager
                T rules = parser.convert(configInfo);
                SentinelRuleManager.updateRules(rules);
            }
        });
        
        // 初始加载
        String config = configService.getConfig(dataId, groupId, 5000L);
        T rules = parser.convert(config);
        SentinelRuleManager.updateRules(rules);
    }
    
    @Override
    public T load() {
        String config = configService.getConfig(dataId, groupId, 5000L);
        return parser.convert(config);
    }
}

// 使用方式
// 流控规则数据源
NacosDataSource<List<FlowRule>> flowDs = new NacosDataSource<>(
    namespace, "SENTINEL_GROUP", "order-service-flow-rules",
    source -> JSON.parseObject(source, new TypeReference<List<FlowRule>>(){}));
FlowRuleManager.register2Property(flowDs.getProperty());

// 熔断规则数据源
NacosDataSource<List<DegradeRule>> degradeDs = new NacosDataSource<>(
    namespace, "SENTINEL_GROUP", "order-service-degrade-rules",
    source -> JSON.parseObject(source, new TypeReference<List<DegradeRule>>(){}));
DegradeRuleManager.register2Property(degradeDs.getProperty());

// Nacos dataId 约定：
//   ${spring.application.name}-flow-rules     → 流控规则
//   ${spring.application.name}-degrade-rules   → 熔断规则
//   ${spring.application.name}-system-rules    → 系统规则
//   ${spring.application.name}-authority-rules → 授权规则
```

---

# 第三部分：Spring Cloud Gateway — 响应式网关

---

## 3.1 Gateway 整体架构（WebFlux + Route + Filter）

### 3.1.1 架构全景图

```
  Spring Cloud Gateway 整体架构
  
  ┌──────────────────────────────────────────────────────────┐
  │                  Client Request                           │
  │                  (HTTP / HTTPS)                           │
  └──────────────────────┬──────────────────────────────────┘
                         │
  ┌──────────────────────▼──────────────────────────────────┐
  │              Gateway Handler Mapping                      │
  │  │   RoutePredicateHandlerMapping                        │
  │  │   │   遍历所有 Route 定义                              │
  │  │   │   逐个匹配 Predicate                              │
  │  │   │   找到匹配的 Route → 返回 FilteringWebHandler     │
  │  │   │   无匹配 → 返回 null → 404                        │
  └──────────────────────┬──────────────────────────────────┘
                         │
  ┌──────────────────────▼──────────────────────────────────┐
  │             FilteringWebHandler                           │
  │  │   获取 Route 的所有 GatewayFilter                     │
  │  │   + 所有 GlobalFilter                                 │
  │  │   │   合并排序（@Order 注解）                           │
  │  │   │   │   组装 GatewayFilterChain                     │
  │  │   │   │   │   执行责任链                              │
  │  │   │   │   │   │   ├── Filter1.filter(exchange, chain)│
  │  │   │   │   │   │   │   ├── 前置逻辑                   │
  │  │   │   │   │   │   │   ├── chain.filter(exchange)     │
  │  │   │   │   │   │   │   │   ├── Filter2...             │
  │  │   │   │   │   │   │   │   │   ├── ...                │
  │  │   │   │   │   │   │   │   │   │   NettyRoutingFilter │
  │  │   │   │   │   │   │   │   │   │   │ → 发送请求到后端 │
  │  │   │   │   │   │   │   │   │   │   │ ← 接收响应      │
  │  │   │   │   │   │   │   │   │   │   ├── 后置逻辑       │
  │  │   │   │   │   │   │   │   │   ├── 后置逻辑           │
  │  │   │   │   │   │   │   │   ├── 后置逻辑               │
  │  │   │   │   │   │   │   ├── 后置逻辑                   │
  │  │   │   │   │   │   ├── 后置逻辑                       │
  └──────────────────────┬──────────────────────────────────┘
                         │
  ┌──────────────────────▼──────────────────────────────────┐
  │              Proxy Request (Netty HttpClient)             │
  │              → Downstream Service                         │
  │              ← Response                                   │
  └──────────────────────┬──────────────────────────────────┘
                         │
  ┌──────────────────────▼──────────────────────────────────┐
  │                  Client Response                          │
  └──────────────────────────────────────────────────────────┘
```

### 3.1.2 核心概念

| 概念 | 含义 | 源码类 |
|------|------|--------|
| **Route** | 路由定义（ID + URI + Predicate + Filter） | `Route` |
| **Predicate** | 路由匹配条件（Path/Host/Method/Header等） | `RoutePredicateFactory` |
| **GatewayFilter** | 路由级过滤器（只对特定Route生效） | `GatewayFilter` |
| **GlobalFilter** | 全局过滤器（对所有Route生效） | `GlobalFilter` |
| **GatewayFilterChain** | 过滤器责任链 | `DefaultGatewayFilterChain` |
| **ServerWebExchange** | 请求/响应上下文（贯穿整个链） | `ServerWebExchange` |
| **RouteDefinitionLocator** | 路由定义定位器（从配置/Nacos/Redis等加载） | `RouteDefinitionLocator` |

### 3.1.3 WebFlux 响应式模型

```
  Spring Cloud Gateway 基于 Spring WebFlux（Reactor + Netty）
  
  传统 Servlet 模型 vs WebFlux 模型：
  ┌──────────────────────────────────────────────────┐
  │  Servlet 模型（Spring MVC）：                     │
  │  │   Thread-per-request                          │
  │  │   请求 → 分配线程 → 同步处理 → 线程等待IO      │
  │  │   线程池 200 繁忙 → 新请求排队                  │
  │                                                  │
  │  WebFlux 模型（Gateway）：                        │
  │  │   Event-loop + Reactive                       │
  │  │   请求 → 少量线程(Netty eventLoop) → 异步IO   │
  │  │   Mono/Flux 声明式编排                         │
  │  │   线程不阻塞 → 高并发低资源                     │
  │                                                  │
  │  Gateway 中的 Mono 链式调用：                     │
  │  │   Mono.fromCallable(() -> entry)              │
  │  │     .flatMap(entry -> chain.filter(exchange)) │
  │  │     .doOnSuccess(v -> entry.exit())           │
  │  │     .doOnError(e -> Tracer.trace(e))          │
  │  │     .onErrorResume(BlockException.class, ...) │
  └──────────────────────────────────────────────────┘
  
  核心 Reactor 类型：
  │   Mono<Void>  → 0 或 1 个元素的异步序列（Gateway 主要用这个）
  │   Flux<T>     → 0 到 N 个元素的异步序列
  │
  │   Mono.defer(() -> ...)  → 惰性创建
  │   Mono.fromCallable(...) → 同步转异步
  │   Mono.flatMap(...)      → 异步串联
  │   Mono.then(...)         → 顺序执行
```

---

## 3.2 Route 定义与 Predicate（RoutePredicateFactory 体系）

### 3.2.1 Route 数据结构

```java
// Route — 核心数据结构
public class Route implements Comparable<Route> {
    private String id;                    // 路由ID（唯一标识）
    private URI uri;                      // 目标 URI（如 lb://order-service）
    private int order;                    // 优先级（数字越小优先级越高）
    private Predicate<ServerWebExchange> predicate;  // 匹配条件
    private List<GatewayFilter> gatewayFilters;      // 路由级过滤器
    
    // URI 类型：
    //   lb://order-service  → 负载均衡（LoadBalancerClientFilter 处理）
    //   http://192.168.1.10 → 直接代理（NettyRoutingFilter 处理）
    //   ws://websocket-service → WebSocket 代理
}

// RouteDefinition — 路由定义（配置来源）
public class RouteDefinition {
    private String id;
    private URI uri;
    private Map<String, String> predicates;   // Predicate 定义
    //   如 "Path": "/api/order/**"
    //      "Host": "order.example.com"
    //      "Method": "GET"
    
    private Map<String, String> filters;      // Filter 定义
    //   如 "AddRequestHeader": "X-Source,gateway"
    //      "RequestRateLimiter": "10,1,#{@keyResolver}"
    
    private int order;
}
```

### 3.2.2 PredicateFactory 体系

```java
// RoutePredicateFactory — 路由匹配工厂（工厂模式）
// 每个 Predicate 类型对应一个 Factory

// ──── PathRoutePredicateFactory ────
public class PathRoutePredicateFactory 
    extends AbstractRoutePredicateFactory<PathRoutePredicateFactory.Config> {
    
    @Override
    public Predicate<ServerWebExchange> apply(Config config) {
        // 构建路径匹配 Pattern
        PathPatternParser parser = new PathPatternParser();
        PathPattern pattern = parser.parse(config.getPattern());
        
        return exchange -> {
            // 匹配请求路径
            PathContainer pathContainer = exchange.getRequest().getPath().pathWithinApplication();
            return pattern.matches(pathContainer);
        };
    }
    
    public static class Config {
        private String pattern;  // 如 "/api/order/**"
    }
}

// ──── 所有内置 PredicateFactory ────
// AfterRoutePredicateFactory       → 时间之后
// BeforeRoutePredicateFactory      → 时间之前
// BetweenRoutePredicateFactory     → 时间之间
// CookieRoutePredicateFactory      → Cookie 匹配
// HeaderRoutePredicateFactory      → Header 匹配
// HostRoutePredicateFactory        → Host 匹配
// MethodRoutePredicateFactory      → HTTP Method 匹配
// PathRoutePredicateFactory        → 路径匹配（最常用）
// QueryRoutePredicateFactory       → Query 参数匹配
// ReadBodyPredicateFactory         → Body 内容匹配
// RemoteAddrRoutePredicateFactory  → IP 地址匹配
// WeightRoutePredicateFactory      → 权重路由（同组路由按权重分流）
// CloudFoundryRouteServiceRoutePredicateFactory → CF 路由服务
```

### 3.2.3 Route 匹配流程

```java
// RoutePredicateHandlerMapping — 路由匹配核心
public class RoutePredicateHandlerMapping extends AbstractHandlerMapping {
    
    @Override
    protected Mono<?> getHandlerInternal(ServerWebExchange exchange) {
        // 1. 获取所有 Route
        return this.routeLocator.getRoutes()
            .concatMap(route -> {
                // 2. 对每个 Route 执行 Predicate 匹配
                return Mono.just(route)
                    .filter(r -> r.getPredicate().test(exchange))
                    .map(r -> {
                        // 3. 匹配成功 → 记录日志 + 验证 URI
                        log.info("Route matched: " + r.getId());
                        exchange.getAttributes().put(GATEWAY_ROUTE_ATTR, r);
                        return r;
                    });
            })
            .next()  // 取第一个匹配的 Route
            .map(route -> {
                // 4. 返回 FilteringWebHandler
                return new FilteringWebHandler(
                    route.getFilters(), globalFilters);
            });
    }
}
```

---

## 3.3 Filter Chain 模型（GatewayFilterChain + GlobalFilter）

### 3.3.1 GatewayFilterChain 责任链

```java
// DefaultGatewayFilterChain — 过滤器责任链
public class DefaultGatewayFilterChain implements GatewayFilterChain {
    
    private final List<GatewayFilter> filters;
    private final int index;
    
    @Override
    public Mono<Void> filter(ServerWebExchange exchange) {
        if (index < filters.size()) {
            GatewayFilter filter = filters.get(index);
            // 执行当前 filter → 传入 next chain
            return filter.filter(exchange, new DefaultGatewayFilterChain(filters, index + 1));
        }
        // 链尾 → 返回完成信号
        return Mono.empty();
    }
}

// GatewayFilter 接口
public interface GatewayFilter extends Ordered {
    Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain);
}

// GlobalFilter 接口
public interface GlobalFilter extends Ordered {
    Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain);
}
```

### 3.3.2 FilteringWebHandler 组装 Filter Chain

```java
// FilteringWebHandler — 组装并执行 Filter Chain
public class FilteringWebHandler implements WebHandler {
    
    private final List<GatewayFilter> combinedFilters;
    
    public FilteringWebHandler(List<GatewayFilter> routeFilters,
                               List<GlobalFilter> globalFilters) {
        // 1. 合并 Route 专属 Filter + GlobalFilter
        List<GatewayFilter> allFilters = new ArrayList<>(globalFilters);
        allFilters.addAll(routeFilters);
        
        // 2. 按 @Order 排序
        allFilters.sort(Comparator.comparingInt(GatewayFilter::getOrder));
        
        this.combinedFilters = allFilters;
    }
    
    @Override
    public Mono<Void> handle(ServerWebExchange exchange) {
        // 3. 创建 Filter Chain 并执行
        return new DefaultGatewayFilterChain(combinedFilters).filter(exchange);
    }
}
```

### 3.3.3 Filter 执行流程图

```
  Filter Chain 执行流程（责任链 + Mono 嵌套）
  
  Request 进入
      │
      ▼
  ┌─── GlobalFilter[Order=-1] ───────────────────────────┐
  │  │  前置逻辑（如：记录开始时间）                       │
  │  │                                                    │
  │  ├── chain.filter(exchange)  ──────────────────▶     │
  │  │  │                                                │
  │  │  ▼                                                │
  │  ┌─── GlobalFilter[Order=0] ──────────────────────┐  │
  │  │  │  前置逻辑（如：Sentinel 检查）                │  │
  │  │  │                                              │  │
  │  │  ├── chain.filter(exchange)  ─────────────▶    │  │
  │  │  │  │                                          │  │
  │  │  │  ▼                                          │  │
  │  │  ┌─── ReactiveLoadBalancerClientFilter ────┐   │  │
  │  │  │  │  前置：选择服务实例                     │   │  │
  │  │  │  │  URI: lb://order → http://10.0.0.5   │   │  │
  │  │  │  │                                      │   │  │
  │  │  │  ├── chain.filter(exchange)  ──────▶    │   │  │
  │  │  │  │  │                                  │   │  │
  │  │  │  │  ▼                                  │   │  │
  │  │  │  ┌─── NettyRoutingFilter ───────────┐  │   │  │
  │  │  │  │  │  发送请求到后端                  │  │  │  │
  │  │  │  │  │  httpClient.request(proxyURI)  │  │  │  │
  │  │  │  │  │  │                             │  │  │  │
  │  │  │  │  │  ▼ 后端响应                     │  │  │  │
  │  │  │  │  │  response → exchange           │  │  │  │
  │  │  │  │  ├── 后置：记录响应状态             │  │  │  │
  │  │  │  │  └── ←─────────────────────       │  │  │  │
  │  │  │  └── 后置：记录负载均衡信息            │   │  │  │
  │  │  │  └── ←───────────────────────        │   │  │  │
  │  │  └── 后置：记录 RT / exit                │   │  │  │
  │  │  └── ←──────────────────────────        │   │  │  │
  │  └── 后置：计算耗时、记录日志                 │    │  │  │
  │  └── ←───────────────────────────────       │    │  │  │
  └─────────────────────────────────────────────┘    │  │  │
                                                     │  │  │
  ← Response 返回给客户端                             │  │  │
```

---

## 3.4 核心处理器 FilteringWebHandler

### 3.4.1 内置 GlobalFilter 列表及 Order

```
  ┌──────────────────────────────────────────────────────────┐
  │  内置 GlobalFilter（按 Order 排序）                        │
  │                                                          │
  │  Order   Filter                      功能                 │
  │  ──────  ──────────────────────────  ────────────────    │
  │  -1      ReactiveLoadBalancerClient  负载均衡选择实例     │
  │  0       NettyRoutingFilter          HTTP 路由到后端      │
  │  0       NettyWriteResponseFilter    写响应给客户端       │
  │  10000   RouteToRequestUrlFilter     URI 模板变量替换     │
  │  10001   ForwardRoutingFilter        本地转发             │
  │  2147483646  ForwardPathFilter       路径转发             │
  │                                                          │
  │  常见自定义/第三方 Filter：                                │
  │  Order   Filter                      功能                 │
  │  ──────  ──────────────────────────  ────────────────    │
  │  -1      SentinelGatewayFilter       Sentinel 流控       │
  │  -1      RateLimiterFilter           Redis 限流          │
  │  10      LoggingFilter               请求日志            │
  │  20      AuthFilter                  认证鉴权            │
  │  30      RequestSizeFilter           请求大小限制        │
  │                                                          │
  │  注意：Order 值越小越先执行（前置段）                       │
  │        Order 值越小越后执行后置逻辑（后置段）               │
  └──────────────────────────────────────────────────────────┘
```

---

## 3.5 ReactiveLoadBalancerClientFilter — 负载均衡过滤器

```java
// ReactiveLoadBalancerClientFilter
public class ReactiveLoadBalancerClientFilter implements GlobalFilter, Ordered {
    
    private final ReactiveLoadBalancer.Factory loadBalancerFactory;
    
    @Override
    public int getOrder() { return ReactiveLoadBalancerClientFilter.ORDER; }
    // ORDER = 10150（在 RouteToRequestUrl 之后）
    
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        // 1. 获取 Route
        Route route = exchange.getAttribute(GATEWAY_ROUTE_ATTR);
        URI uri = route.getUri();
        
        // 2. 判断是否是负载均衡 URI（lb:// 开头）
        if ("lb".equals(uri.getScheme())) {
            String serviceId = uri.getHost();  // 如 "order-service"
            
            // 3. 使用 LoadBalancer 选择实例
            return Mono.fromCallable(() -> {
                // 从 Nacos/Eureka 获取实例列表
                // 按负载均衡策略（RoundRobin/Random/Weighted）选择
                ServiceInstance instance = loadBalancer.choose(serviceId);
                return instance;
            })
            .flatMap(instance -> {
                if (instance == null) {
                    // 无可用实例 → 503
                    exchange.getResponse().setStatusCode(HttpStatus.SERVICE_UNAVAILABLE);
                    return exchange.getResponse().setComplete();
                }
                
                // 4. 替换 URI：lb://order-service → http://10.0.0.5:8080
                URI newUri = reconstructUri(uri, instance);
                exchange.getAttributes().put(GATEWAY_REQUEST_URL_ATTR, newUri);
                
                // 5. 继续执行后续 Filter（NettyRoutingFilter 会用到新 URI）
                return chain.filter(exchange);
            });
        }
        
        // 非 lb:// → 直接继续
        return chain.filter(exchange);
    }
}
```

---

## 3.6 NettyRoutingFilter — 底层 HTTP 路由

```java
// NettyRoutingFilter — 核心路由过滤器
public class NettyRoutingFilter implements GlobalFilter, Ordered {
    
    private final HttpClient httpClient;  // Netty ReactiveHttpClient
    
    @Override
    public int getOrder() { return 2147483647; }  // 最高 Order → 最后执行前置
    
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        // 1. 获取最终的请求 URI
        URI requestUrl = exchange.getAttribute(GATEWAY_REQUEST_URL_ATTR);
        
        // 2. 构建请求方法
        HttpMethod method = HttpMethod.valueOf(exchange.getRequest().getMethodValue());
        
        // 3. 构建请求 Headers
        HttpHeaders filteredHeaders = filterHeaders(exchange.getRequest().getHeaders());
        
        // 4. 发送请求到后端服务（Netty HttpClient）
        return httpClient.request(method, requestUrl, 
            httpHeaders -> httpHeaders.set(filteredHeaders))
            .response(response -> {
                // 5. 收到后端响应
                //    保存响应状态码
                exchange.getAttributes().put(GATEWAY_RESPONSE_STATUS_ATTR, 
                    response.status().code());
                
                //    保存响应 Headers
                exchange.getResponse().setStatusCode(
                    HttpStatus.valueOf(response.status().code()));
                exchange.getResponse().getHeaders().putAll(
                    response.responseHeaders());
                
                // 6. 继续执行后续 Filter（后置逻辑）
                return chain.filter(exchange);
            });
    }
}
```

---

## 3.7 Gateway 自动装配与 Route 定位（RouteDefinitionLocator）

### 3.7.1 自动装配入口

```java
// GatewayAutoConfiguration
@Configuration
public class GatewayAutoConfiguration {
    
    // ──── 核心 Bean ────
    
    @Bean
    public RoutePredicateHandlerMapping routePredicateHandlerMapping(
            RouteLocator routeLocator,
            List<GlobalFilter> globalFilters) {
        return new RoutePredicateHandlerMapping(routeLocator, globalFilters);
    }
    
    @Bean
    public FilteringWebHandler filteringWebHandler(
            List<GlobalFilter> globalFilters) {
        return new FilteringWebHandler(globalFilters);
    }
    
    @Bean
    public NettyRoutingFilter nettyRoutingFilter(HttpClient httpClient) {
        return new NettyRoutingFilter(httpClient);
    }
    
    @Bean
    public ReactiveLoadBalancerClientFilter loadBalancerClientFilter(
            ReactiveLoadBalancer.Factory factory) {
        return new ReactiveLoadBalancerClientFilter(factory);
    }
}

// GatewayProperties — 路由配置
@ConfigurationProperties("spring.cloud.gateway")
public class GatewayProperties {
    private List<RouteDefinition> routes = new ArrayList<>();
    private List<FilterDefinition> defaultFilters = new ArrayList<>();
    
    // YAML 配置示例：
    // spring.cloud.gateway.routes:
    //   - id: order-route
    //     uri: lb://order-service
    //     predicates:
    //       - Path=/api/order/**
    //     filters:
    //       - AddRequestHeader=X-Source,gateway
    //       - RequestRateLimiter=10,1,#{@keyResolver}
}
```

### 3.7.2 RouteDefinitionLocator 体系

```
  ┌──────────────────────────────────────────────────────┐
  │  RouteDefinitionLocator 体系（路由定义来源）           │
  │                                                      │
  │  ┌────────────────────────────────────────────────┐  │
  │  │  PropertiesRouteDefinitionLocator              │  │
  │  │  从 application.yml 加载路由定义（最基础）       │  │
  │  │  → GatewayProperties.getRoutes()               │  │
  │  └────────────────────────────────────────────────┘  │
  │                                                      │
  │  ┌────────────────────────────────────────────────┐  │
  │  │  InMemoryRouteDefinitionRepository             │  │
  │  │  内存存储（支持 Actuator 动态添加路由）          │  │
  │  │  → Map<String, RouteDefinition>                │  │
  │  └────────────────────────────────────────────────┘  │
  │                                                      │
  │  ┌────────────────────────────────────────────────┐  │
  │  │  DiscoveryClientRouteDefinitionLocator         │  │
  │  │  从 Nacos/Eureka 自动发现服务 → 自动创建路由    │  │
  │  │  → /${serviceId}/** → lb://${serviceId}       │  │
  │  └────────────────────────────────────────────────┘  │
  │                                                      │
  │  ┌────────────────────────────────────────────────┐  │
  │  │  NacosRouteDefinitionRepository                │  │
  │  │  从 Nacos 配置中心动态加载路由                   │  │
  │  │  → 配置变更 → 实时更新路由                      │  │
  │  │  → NacosDataSource<List<RouteDefinition>>      │  │
  │  └────────────────────────────────────────────────┘  │
  │                                                      │
  │  ┌────────────────────────────────────────────────┐  │
  │  │  RedisRouteDefinitionRepository                │  │
  │  │  从 Redis 加载路由定义（支持动态更新）           │  │
  │  │  → Redis Hash 存储                             │  │
  │  └────────────────────────────────────────────────┘  │
  │                                                      │
  │  ┌────────────────────────────────────────────────┐  │
  │  │  CompositeRouteDefinitionLocator               │  │
  │  │  组合多个 Locator → 合并路由定义                │  │
  │  │  → Flux.fromIterable(locators).concatMap(...) │  │
  │  └────────────────────────────────────────────────┘  │
  │                                                      │
  │  路由定义 → RouteDefinition → Route (转换)          │
  │  RouteDefinitionRouteLocator                        │
  │  │   将 RouteDefinition 转为 Route                  │
  │  │   │   predicates → Predicate<ServerWebExchange>  │
  │  │   │   filters → GatewayFilter                   │
  │  │   │   使用对应的 Factory 创建                     │
  └──────────────────────────────────────────────────────┘
```

### 3.7.3 Route 转换流程

```java
// RouteDefinitionRouteLocator — 将定义转为 Route
public class RouteDefinitionRouteLocator implements RouteLocator {
    
    private final RouteDefinitionLocator routeDefinitionLocator;
    private final Map<String, RoutePredicateFactory> predicateFactories;
    private final Map<String, GatewayFilterFactory> filterFactories;
    
    @Override
    public Flux<Route> getRoutes() {
        return routeDefinitionLocator.getRouteDefinitions()
            .map(this::convertToRoute);
    }
    
    private Route convertToRoute(RouteDefinition routeDefinition) {
        // 1. 转换 Predicate
        Predicate<ServerWebExchange> predicate = combinePredicates(routeDefinition);
        
        // 2. 转换 Filter
        List<GatewayFilter> gatewayFilters = convertFilters(routeDefinition);
        
        // 3. 构建 Route
        return new Route(routeDefinition.getId(), 
                        routeDefinition.getUri(),
                        predicate, 
                        gatewayFilters,
                        routeDefinition.getOrder());
    }
    
    private Predicate<ServerWebExchange> combinePredicates(RouteDefinition def) {
        // 对每个 Predicate 定义：
        //   "Path=/api/order/**" → PathRoutePredicateFactory.apply(Config)
        //   "Method=GET" → MethodRoutePredicateFactory.apply(Config)
        // 多个 Predicate → and() 组合
        return predicates.stream()
            .map(pDef -> {
                RoutePredicateFactory factory = predicateFactories.get(pDef.getName());
                return factory.applyAsync(config);
            })
            .reduce(Predicate::and)
            .orElse(exchange -> true);
    }
}
```

---

## 3.8 限流过滤器 RequestRateLimiterGatewayFilter（Redis + Lua）

### 3.8.1 限流原理与源码

```java
// RequestRateLimiterGatewayFilterFactory
public class RequestRateLimiterGatewayFilterFactory 
    extends AbstractGatewayFilterFactory<RequestRateLimiterConfig> {
    
    private final RateLimiter rateLimiter;  // RedisRateLimiter
    private final KeyResolver keyResolver;  // 限流 Key 解析器
    
    @Override
    public GatewayFilter apply(Config config) {
        return (exchange, chain) -> {
            // 1. 解析限流 Key
            String key = keyResolver.resolve(exchange);
            //   常见 KeyResolver：
            //   - HostKeyResolver: exchange.getRequest().getRemoteAddress().getHostName()
            //   - PathKeyResolver: exchange.getRequest().getPath().value()
            //   - UserKeyResolver: exchange.getRequest().getHeaders().getFirst("X-User")
            //   - IPKeyResolver: exchange.getRequest().getRemoteAddress().getAddress().getHostAddress()
            
            // 2. 请求限流检查
            return Mono.fromCallable(() -> 
                rateLimiter.isAllowed(key, config.getReplenishRate(), 
                                      config.getBurstCapacity()))
            .flatMap(response -> {
                if (response.isAllowed()) {
                    // 3. 通过 → 添加限流 Headers → 继续
                    exchange.getResponse().getHeaders().add(
                        "X-RateLimit-Remaining", 
                        String.valueOf(response.getRemainingTokens()));
                    exchange.getResponse().getHeaders().add(
                        "X-RateLimit-Burst-Capacity", 
                        String.valueOf(config.getBurstCapacity()));
                    return chain.filter(exchange);
                }
                
                // 4. 拒绝 → 429 Too Many Requests
                exchange.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
                return exchange.getResponse().setComplete();
            });
        };
    }
}
```

### 3.8.2 RedisRateLimiter — Lua 脚本实现

```java
// RedisRateLimiter — 基于 Redis + Lua 的令牌桶
public class RedisRateLimiter implements RateLimiter {
    
    // Lua 装到（原子操作，保证并发安全）
    private static final String REDIS_SCRIPT =
        "local tokens_key = KEYS[1] .. '.tokens' " +
        "local timestamp_key = KEYS[1] .. '.timestamp' " +
        "local rate = tonumber(ARGV[1]) " +           // replenishRate（令牌生成速率）
        "local capacity = tonumber(ARGV[2]) " +        // burstCapacity（桶容量）
        "local requested = tonumber(ARGV[3]) " +       // 请求令牌数
        "local fill_time = capacity / rate " +
        "local fill_tokens = math.max(0, fill_time - (now - last_refreshed)) * rate " +
        "local allowed_tokens = math.min(capacity, last_tokens + fill_tokens) " +
        "local allowed = 0 " +
        "if allowed_tokens >= requested then " +
        "  allowed = requested " +
        "  allowed_tokens = allowed_tokens - requested " +
        "else " +
        "  allowed = 0 " +
        "end " +
        "redis.call('set', tokens_key, allowed_tokens) " +
        "redis.call('set', timestamp_key, now) " +
        "return { allowed, allowed_tokens } ";
    
    @Override
    public Response isAllowed(String id, int replenishRate, int burstCapacity) {
        // 执行 Lua 装到
        List<Long> result = redisTemplate.execute(REDIS_SCRIPT, 
            Keys.list(id), 
            Args.list(replenishRate, burstCapacity, 1));
        
        long allowed = result.get(0);     // 允许的令牌数
        long remaining = result.get(1);   // 剩余令牌数
        
        return new Response(allowed > 0, remaining);
    }
}

// 令牌桶算法：
// ┌────────────────────────────────────────────┐
// │  令牌桶（Token Bucket）                     │
// │                                            │
// │  replenishRate = 10  → 每秒生成10个令牌    │
// │  burstCapacity = 20  → 桶最大容量20       │
// │                                            │
// │  时间轴：                                   │
// │  ──0────1────2────3────4────── 时间(s)     │
// │    │     │     │     │     │              │
// │    10    20    20    20    20  令牌数       │
// │    (生成) (满了) (满了) (满了)             │
// │                                            │
// │  请求到达 → 取1令牌 → 通过                  │
// │  桶空 → 拒绝 → 429                         │
// │                                            │
// │  burst 允许突发：                           │
// │  桶有20令牌 → 突发20个请求全部通过          │
// │  之后限速10/s                               │
// └────────────────────────────────────────────┘
```

---

## 3.9 Gateway 源码面试高频题

| # | 问题 | 核心答案 |
|---|------|----------|
| 1 | Gateway 为什么用 WebFlux 而不是 Servlet？ | Netty EventLoop异步IO，不阻塞线程，少量线程支撑高并发；Servlet线程等待IO浪费资源 |
| 2 | Gateway Filter 执行顺序？ | 按 Order 排序，Order小→前置先执行→后置后执行；NettyRoutingFilter Order=Integer.MAX_VALUE |
| 3 | Gateway 路由匹配流程？ | RoutePredicateHandlerMapping→遍历Route→Predicate.test(exchange)→取第一个匹配→FilteringWebHandler |
| 4 | lb:// URI 如何工作？ | ReactiveLoadBalancerClientFilter识别lb://→LoadBalancer.choose(serviceId)→替换为http://ip:port |
| 5 | Gateway 限流原理？ | RequestRateLimiter + Redis Lua令牌桶，原子操作保证并发安全，KeyResolver决定限流维度 |
| 6 | RouteDefinitionLocator 作用？ | 路由定义来源：Properties(yml)、InMemory(Actuator)、Discovery(Nacos自动发现)、Nacos/Redis(动态) |
| 7 | Gateway Filter 和 GlobalFilter 区别？ | GatewayFilter 路由级(只对特定Route)；GlobalFilter 全局级(所有Route)；合并后按Order排序执行 |
| 8 | Gateway 如何动态路由？ | NacosRouteDefinitionRepository：监听Nacos配置变更→实时更新RouteDefinition→刷新Route |
| 9 | Gateway 前置/后置逻辑怎么写？ | 前置在chain.filter()之前，后置在chain.filter().doOnSuccess()/doOnError()回调中 |
| 10 | Gateway 请求转发完整链路？ | RoutePredicate→ReactiveLoadBalancer→NettyRoutingFilter→HttpClient.request→后端→Response写回 |

---

## 3.10 Gateway 与 Sentinel 集成原理

### 3.10.1 集成架构

```
  Gateway + Sentinel 集成链路
  
  ┌──────────────────────────────────────────────────────┐
  │  Request → Gateway                                   │
  │  │                                                   │
  │  ├── SentinelGatewayFilter (Order=-1)               │
  │  │   │                                               │
  │  │   ├── 1. SphU.asyncEntry(routeId/apiName)        │
  │  │   │   → Slot Chain 执行                           │
  │  │   │   │   ├── NodeSelectorSlot → 创建统计节点     │
  │  │   │   │   ├── StatisticSlot → 滑动窗口统计        │
  │  │   │   │   ├── FlowSlot → 流控检查                 │
  │  │   │   │   ├── DegradeSlot → 熔断检查              │
  │  │   │   │   │                                      │
  │  │   │   │   ├── BlockException →                    │
  │  │   │   │   │   BlockRequestHandler.handleRequest() │
  │  │   │   │   │   → 返回自定义 429 响应               │
  │  │   │   │   │                                      │
  │  │   │   │   ├── 通过 → 继续执行后续 Filter           │
  │  │   │   │                                          │
  │  │   ├── 2. chain.filter(exchange)                  │
  │  │   │   → ReactiveLoadBalancerClientFilter          │
  │  │   │   → NettyRoutingFilter                       │
  │  │   │   → ...                                      │
  │  │   │                                              │
  │  │   ├── 3. exit → 记录 RT / 成功数                  │
  │  │   │                                              │
  │  ├── 其他 GlobalFilter                              │
  │  │                                                   │
  │  ← Response                                         │
  └──────────────────────────────────────────────────────┘
  
  依赖配置：
  spring.cloud.sentinel.datasource.flow.nacos:
    server-addr: 127.0.0.1:8848
    dataId: ${spring.application.name}-flow-rules
    groupId: SENTINEL_GROUP
    rule-type: flow
  
  spring.cloud.sentinel.datasource.degrade.nacos:
    server-addr: 127.0.0.1:8848
    dataId: ${spring.application.name}-degrade-rules
    groupId: SENTINEL_GROUP
    rule-type: degrade
```

---

# 第四部分：MyBatis — ORM 框架核心

---

## 4.1 MyBatis 整体架构（接口层 + 核心处理层 + 基础支持层）

### 4.1.1 架构全景图

```
  MyBatis 三层架构
  
  ┌──────────────────────────────────────────────────────────┐
  │                   接口层（API Layer）                      │
  │                                                          │
  │  ┌──────────┐  ┌──────────┐  ┌───────────────────┐      │
  │  │SqlSession │  │MapperProxy│  │  Spring 整合接口   │      │
  │  │selectList │  │(动态代理) │  │SqlSessionTemplate │      │
  │  │selectOne  │  │          │  │MapperFactoryBean  │      │
  │  │insert     │  │          │  │MapperScanner...   │      │
  │  │update     │  │          │  │                   │      │
  │  │delete     │  │          │  │                   │      │
  │  └──────────┘  └──────────┘  └───────────────────┘      │
  │        │             │              │                     │
  └────────┼─────────────┼──────────────┼────────────────────┘
           │             │              │
  ┌────────▼─────────────▼──────────────▼────────────────────┐
  │                核心处理层（Core Processing Layer）          │
  │                                                          │
  │  ┌──────────────────────────────────────────────────┐    │
  │  │  SqlSession → Executor → StatementHandler        │    │
  │  │       │          │           │                    │    │
  │  │       │    ┌─────┼──────┐    │                    │    │
  │  │       │    │     │      │    │                    │    │
  │  │       │  Simple  Reuse  Batch                   │    │
  │  │       │Executor Executor Executor               │    │
  │  │       │    │     │      │                        │    │
  │  │       │    ▼     ▼      ▼                        │    │
  │  │  ┌──────────────────────────────────────────┐   │    │
  │  │  │  StatementHandler                          │   │    │
  │  │  │  ├── SimpleStatementHandler (Statement)   │   │    │
  │  │  │  ├── PreparedStatementHandler (PreparedStatement) │ │
  │  │  │  ├── CallableStatementHandler (CallableStatement) │ │
  │  │  │  │                                      │   │    │
  │  │  │  │  ParameterHandler → TypeHandler       │   │    │
  │  │  │  │  ResultSetHandler → ResultMap         │   │    │
  │  │  │  └──────────────────────────────────────│   │    │
  │  │  └──────────────────────────────────────────┘   │    │
  │  └──────────────────────────────────────────────────┘    │
  │                                                          │
  │  ┌──────────────────────────────────────────────────┐    │
  │  │  插件层（Interceptor + Plugin.wrap）              │    │
  │  │  拦截四大对象：Executor / StatementHandler        │    │
  │  │  / ParameterHandler / ResultSetHandler            │    │
  │  └──────────────────────────────────────────────────┘    │
  │                                                          │
  └──────────────────────────────────────────────────────────┘
           │
  ┌────────▼──────────────────────────────────────────────────┐
  │               基础支持层（Base Support Layer）               │
  │                                                          │
  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐    │
  │  │配置解析   │ │动态SQL    │ │反射模块   │ │类型转换   │    │
  │  │XMLConfig │ │SqlNode   │ │Reflector │ │TypeHandler│    │
  │  │Builder   │ │体系      │ │MetaObject│ │TypeAlias │    │
  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘    │
  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐    │
  │  │日志模块   │ │缓存模块   │ │数据源模块 │ │事务管理   │    │
  │  │Logging   │ │Cache     │ │DataSource│ │Transaction│    │
  │  │(适配多框架│ │Local/2nd │ │Unpooled │ │Jdbc/Mgd  │    │
  │  │SLF4J等)  │ │Cache     │ │Pooled   │ │Spring    │    │
  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘    │
  │                                                          │
  └──────────────────────────────────────────────────────────┘
```

### 4.1.2 核心执行流程图

```
  MyBatis 一次查询的完整执行流程
  
  用户代码
    │
    ├── sqlSession.selectList("com.example.mapper.OrderMapper.selectAll")
    │   或
    ├── orderMapper.selectAll()  ←── MapperProxy 动态代理
    │
    ▼
  DefaultSqlSession
    │
    ├── 1. 获取 MappedStatement（SQL 映射配置）
    │   │   configuration.getMappedStatement("com.example.mapper.OrderMapper.selectAll")
    │   │   → 包含 SQL 语句、参数映射、结果映射等
    │
    ├── 2. 获取 Executor
    │   │   executor = configuration.newExecutor(transaction, executorType)
    │   │   │   executorType = SIMPLE (默认)
    │   │   │   │   → SimpleExecutor
    │   │   │   │   → 每次创建新 Statement
    │   │   │   │   REUSE → ReuseExecutor（复用 Statement）
    │   │   │   │   BATCH → BatchExecutor（批量执行）
    │   │   │   │
    │   │   │   └── 如果开启二级缓存 → CachingExecutor（装饰器包装）
    │   │   │   │   CachingExecutor(delegate=SimpleExecutor)
    │   │   │
    │   │   └── 插件拦截（Plugin.wrap 四大对象）
    │
    ├── 3. Executor.query(ms, parameter, rowBounds, resultHandler)
    │   │
    │   ├── 3.1 如果是 CachingExecutor → 先查二级缓存
    │   │   │   tcm.getObject(cacheKey) → 缓存命中 → 直接返回
    │   │   │   缓存未命中 → delegate.query(...) → 查一级缓存
    │   │   │
    │   ├── 3.2 SimpleExecutor.query(...)
    │   │   │   │
    │   │   │   ├── 查一级缓存（LocalCache）
    │   │   │   │   localCache.getObject(cacheKey) → 命中 → 返回
    │   │   │   │   未命中 → queryFromDatabase(...)
    │   │   │   │
    │   │   │   ├── queryFromDatabase(...)
    │   │   │   │   │
    │   │   │   │   ├── 3.2.1 创建 StatementHandler
    │   │   │   │   │   │   statementHandler = config.newStatementHandler(
    │   │   │   │   │   │       executor, ms, parameter, rowBounds, resultHandler, boundSql)
    │   │   │   │   │   │   │   → 根据 ms.getStatementType() 选择：
    │   │   │   │   │   │   │     STATEMENT → SimpleStatementHandler
    │   │   │   │   │   │   │     PREPARED → PreparedStatementHandler（最常用）
    │   │   │   │   │   │   │     CALLABLE → CallableStatementHandler
    │   │   │   │   │   │   │
    │   │   │   │   │   │   │   → 创建 ParameterHandler 和 ResultSetHandler
    │   │   │   │   │   │
    │   │   │   │   ├── 3.2.2 prepareStatement(connection, mappedStatement)
    │   │   │   │   │   │   │   Connection conn = getConnection(transaction)
    │   │   │   │   │   │   │   PreparedStatement ps = conn.prepareStatement(boundSql.getSql())
    │   │   │   │   │   │   │   parameterHandler.setParameters(ps)  ← 设置参数
    │   │   │   │   │   │
    │   │   │   │   ├── 3.2.3 执行查询
    │   │   │   │   │   │   List<E> result = statementHandler.query(statement, resultHandler)
    │   │   │   │   │   │   │   → ResultSetHandler.handleResultSets(ps.executeQuery())
    │   │   │   │   │   │   │   → 将 ResultSet 映射为 Java 对象
    │   │   │   │   │   │
    │   │   │   │   ├── 3.2.4 存入一级缓存
    │   │   │   │   │   │   localCache.putObject(cacheKey, result)
    │   │   │   │   │   │
    │   │   │   │   └── 3.2.5 返回结果
    │
    └── 4. 返回 List<Order> 给用户代码
```

---

## 4.2 SqlSession 与 Mapper 代理（DefaultSqlSession + MapperProxy）

### 4.2.1 SqlSession 接口体系

```java
// SqlSession — MyBatis 核心接口
public interface SqlSession {
    <T> T selectOne(String statement, Object parameter);
    <E> List<E> selectList(String statement, Object parameter);
    <K, V> Map<K, V> selectMap(String statement, Object parameter, String mapKey);
    <T> Cursor<T> selectCursor(String statement, Object parameter);
    int insert(String statement, Object parameter);
    int update(String statement, Object parameter);
    int delete(String statement, Object parameter);
    void commit();
    void rollback();
    void close();
    <T> T getMapper(Class<T> type);
    Connection getConnection();
}

// DefaultSqlSession — 默认实现
public class DefaultSqlSession implements SqlSession {
    private Configuration configuration;     // 全局配置
    private Executor executor;               // 执行器
    private boolean autoCommit;              // 自动提交
    
    @Override
    public <E> List<E> selectList(String statement, Object parameter) {
        // 1. 获取 MappedStatement
        MappedStatement ms = configuration.getMappedStatement(statement);
        
        // 2. 交给 Executor 执行
        return executor.query(ms, parameter, RowBounds.DEFAULT, Executor.NO_RESULT_HANDLER);
    }
    
    @Override
    public int insert(String statement, Object parameter) {
        // insert 和 update 在 MyBatis 内部都走 update
        return update(statement, parameter);
    }
    
    @Override
    public int update(String statement, Object parameter) {
        MappedStatement ms = configuration.getMappedStatement(statement);
        return executor.update(ms, parameter);
    }
    
    @Override
    public <T> T getMapper(Class<T> type) {
        // 从 Configuration 获取 MapperProxyFactory
        return configuration.getMapper(type, this);
    }
}
```

### 4.2.2 MapperProxy 动态代理

```java
// MapperProxyFactory — 创建 Mapper 代理
public class MapperProxyFactory<T> {
    private Class<T> mapperInterface;
    private Map<Method, MapperMethod> methodCache = new ConcurrentHashMap<>();
    
    public T newInstance(SqlSession sqlSession) {
        // JDK 动态代理
        MapperProxy<T> mapperProxy = new MapperProxy<>(sqlSession, mapperInterface, methodCache);
        return (T) Proxy.newProxyInstance(
            mapperInterface.getClassLoader(),
            new Class[]{mapperInterface},
            mapperProxy);
    }
}

// MapperProxy — InvocationHandler 实现
public class MapperProxy<T> implements InvocationHandler {
    private SqlSession sqlSession;
    private Class<T> mapperInterface;
    private Map<Method, MapperMethod> methodCache;
    
    @Override
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        // 1. Object 方法直接执行（toString/hashCode/equals 等）
        if (Object.class.equals(method.getDeclaringClass())) {
            return method.invoke(this, args);
        }
        
        // 2. 获取 MapperMethod（缓存）
        MapperMethod mapperMethod = cachedMapperMethod(method);
        
        // 3. 根据 SQL 类型执行
        return mapperMethod.execute(sqlSession, args);
    }
    
    private MapperMethod cachedMapperMethod(Method method) {
        return methodCache.computeIfAbsent(method, 
            m -> new MapperMethod(mapperInterface, m, sqlSession.getConfiguration()));
    }
}

// MapperMethod — 封装 SQL 类型和执行逻辑
public class MapperMethod {
    private SqlCommand command;     // SQL 命令类型（INSERT/UPDATE/DELETE/SELECT）
    private MethodSignature method; // 方法签名（返回类型、参数类型等）
    
    public Object execute(SqlSession sqlSession, Object[] args) {
        switch (command.getType()) {
            case INSERT:
                return sqlSession.insert(command.getName(), param);
            case UPDATE:
                return sqlSession.update(command.getName(), param);
            case DELETE:
                return sqlSession.delete(command.getName(), param);
            case SELECT:
                if (method.returnsMany()) {
                    return sqlSession.selectList(command.getName(), param);
                }
                if (method.returnsMap()) {
                    return sqlSession.selectMap(command.getName(), param, method.getMapKey());
                }
                if (method.returnsCursor()) {
                    return sqlSession.selectCursor(command.getName(), param);
                }
                // 单个对象
                return sqlSession.selectOne(command.getName(), param);
            case FLUSH:
                return sqlSession.flushStatements();
        }
    }
}
```

### 4.2.3 Mapper 代理创建流程图

```
  ──── Mapper 代理创建 ────
  
  Configuration.addMapper(OrderMapper.class)
    │
    ├── 1. MapperRegistry.addMapper
    │   │   knownMappers.put(mapperInterface, new MapperProxyFactory<>(mapperInterface))
    │   │
    │   ├── 2. MapperAnnotationBuilder.parse()
    │   │   │   解析 @Select/@Insert/@Update/@Delete 注解
    │   │   │   或加载同名 XML 文件
    │   │   │   → 创建 MappedStatement
    │   │   │   → 存入 Configuration.mappedStatements
    │   │
    │   └── 3. 代理对象创建（调用时）
    │       │   sqlSession.getMapper(OrderMapper.class)
    │       │   → MapperRegistry.getMapper(OrderMapper.class, sqlSession)
    │       │   → MapperProxyFactory.newInstance(sqlSession)
    │       │   → Proxy.newProxyInstance(..., MapperProxy)
    │       │   → 返回代理对象 OrderMapper proxy
    │       │
    │       └── 4. 方法调用
    │           │   proxy.selectAll()
    │           │   → MapperProxy.invoke()
    │           │   → MapperMethod.execute(sqlSession, args)
    │           │   → sqlSession.selectList("selectAll")
    │           │   → executor.query(...)
    │
    └── 5. MappedStatement 数据结构
        │   id: "com.example.mapper.OrderMapper.selectAll"
        │   sqlSource: DynamicSqlSource / RawSqlSource
        │   parameterMap: 参数映射
        │   resultMaps: 结果映射
        │   statementType: PREPARED (默认)
        │   sqlCommandType: SELECT
        │   cache: 二级缓存引用
        │   useCache: true (查询默认开启二级缓存)
```

---

## 4.3 Executor 体系（SimpleExecutor / ReuseExecutor / BatchExecutor）

### 4.3.1 Executor 接口与三种实现

```java
// Executor 接口
public interface Executor {
    int update(MappedStatement ms, Object parameter);
    <E> List<E> query(MappedStatement ms, Object parameter, RowBounds rowBounds, ResultHandler handler);
    <E> Cursor<E> queryCursor(MappedStatement ms, Object parameter, RowBounds rowBounds);
    List<BatchResult> flushStatements();
    void commit(boolean required);
    void rollback(boolean required);
    CacheKey createCacheKey(MappedStatement ms, Object parameter, RowBounds rowBounds, BoundSql boundSql);
    boolean isCached(MappedStatement ms, CacheKey key);
    void clearLocalCache();
}

// ──── BaseExecutor — 基础执行器（模板方法模式）─────
public abstract class BaseExecutor implements Executor {
    protected Transaction transaction;         // 事务
    protected PerpetualCache localCache;       // 一级缓存
    protected Map<String, Cache> localOutputParameterCache;
    
    @Override
    public <E> List<E> query(MappedStatement ms, Object parameter, 
                              RowBounds rowBounds, ResultHandler resultHandler) {
        // 1. 获取 BoundSql（最终执行的 SQL）
        BoundSql boundSql = ms.getBoundSql(parameter);
        
        // 2. 生成 CacheKey
        CacheKey cacheKey = createCacheKey(ms, parameter, rowBounds, boundSql);
        
        // 3. 查一级缓存
        List<E> cachedResult = localCache.getObject(cacheKey);
        if (cachedResult != null) {
            // 命中 → 直接返回
            return cachedResult;
        }
        
        // 4. 未命中 → 查数据库
        return queryFromDatabase(ms, parameter, rowBounds, resultHandler, cacheKey, boundSql);
    }
    
    private <E> List<E> queryFromDatabase(...) {
        // 先放占位符（防止递归查询同一个 SQL）
        localCache.putObject(cacheKey, ExecutionPlaceholder.EXECUTION_PLACEHOLDER);
        
        try {
            // 执行查询（交给子类实现）
            List<E> result = doQuery(ms, parameter, rowBounds, resultHandler, boundSql);
            
            // 存入一级缓存
            localCache.putObject(cacheKey, result);
            return result;
        } finally {
            // 清除占位符（如果出错）
            localCache.removeObject(cacheKey);
        }
    }
    
    // 子类实现的模板方法
    protected abstract <E> List<E> doQuery(MappedStatement ms, Object parameter, 
                                            RowBounds rowBounds, ResultHandler resultHandler, 
                                            BoundSql boundSql);
}

// ──── SimpleExecutor — 每次创建新 Statement ────
public class SimpleExecutor extends BaseExecutor {
    @Override
    protected <E> List<E> doQuery(...) {
        // 1. 创建 StatementHandler
        StatementHandler handler = configuration.newStatementHandler(
            this, ms, parameter, rowBounds, resultHandler, boundSql);
        
        // 2. 准备 Statement
        Statement stmt = prepareStatement(handler, ms.getStatementLog());
        
        // 3. 执行查询
        return handler.query(stmt, resultHandler);
    }
    
    private Statement prepareStatement(StatementHandler handler, StatementLog statementLog) {
        Connection conn = getConnection(statementLog);  // 从 Transaction 获取连接
        Statement stmt = handler.prepare(conn, ms.getStatementTimeout());
        handler.parameterize(stmt);  // 设置参数
        return stmt;
    }
    
    // 每次执行完毕后关闭 Statement
    @Override
    public void doCloseStatement(Statement stmt) {
        stmt.close();
    }
}

// ──── ReuseExecutor — 复用 Statement ────
public class ReuseExecutor extends BaseExecutor {
    // Statement 缓存（按 SQL 字符串缓存）
    private Map<String, Statement> statementMap = new HashMap<>();
    
    @Override
    protected <E> List<E> doQuery(...) {
        StatementHandler handler = configuration.newStatementHandler(...);
        Statement stmt = getReusableStatement(handler, boundSql.getSql());
        handler.parameterize(stmt);
        return handler.query(stmt, resultHandler);
    }
    
    private Statement getReusableStatement(StatementHandler handler, String sql) {
        Statement stmt = statementMap.get(sql);
        if (stmt == null) {
            Connection conn = getConnection(statementLog);
            stmt = handler.prepare(conn, ms.getStatementTimeout());
            statementMap.put(sql, stmt);  // 缓存 Statement
        }
        return stmt;
    }
    // 相同 SQL 只创建一次 Statement，参数通过 parameterize 更新
    // 注意：Statement 缓存是基于 SQL 字符串的，不是基于参数
}

// ──── BatchExecutor — 批量执行 ────
public class BatchExecutor extends BaseExecutor {
    // 批量 Statement 列表
    private final List<Statement> statementList = new ArrayList<>();
    private final List<BatchResult> batchResultList = new ArrayList<>();
    
    @Override
    public int doUpdate(MappedStatement ms, Object parameter) {
        // 1. 获取或创建 PreparedStatement（按 SQL 分组）
        String sql = ms.getBoundSql(parameter).getSql();
        PreparedStatement stmt = getBatchPreparedStatement(sql);
        
        // 2. 设置参数 → 添加到 batch
        handler.parameterize(stmt);
        handler.getParameterHandler().setParameters(stmt);
        stmt.addBatch();  // JDBC batch
        
        // 3. 记录 batch 结果
        batchResultList.add(new BatchResult(ms, sql, parameter));
        
        return BATCH_UPDATE_RETURN_VALUE;  // 返回 -2147482646（占位符）
    }
    
    @Override
    public List<BatchResult> doFlushStatements() {
        // 执行所有 batch → 返回结果
        List<BatchResult> results = new ArrayList<>();
        for (Statement stmt : statementList) {
            int[] updateCounts = stmt.executeBatch();  // JDBC 执行批量
            // ...
        }
        return results;
    }
}
```

### 4.3.2 CacheKey 生成规则

```java
// CacheKey — 一级/二级缓存键
public class CacheKey {
    // 多因素组合确保唯一性
    private List<Object> updateList = new ArrayList<>();
    
    // CacheKey 由以下因素决定：
    // 1. MappedStatement.id（SQL 的唯一标识）
    //    如 "com.example.mapper.OrderMapper.selectAll"
    
    // 2. RowBounds.offset 和 limit（分页偏移）
    //    RowBounds.DEFAULT → offset=0, limit=Integer.MAX_VALUE
    
    // 3. BoundSql.sql（SQL 语句字符串）
    //    如 "SELECT * FROM order WHERE id = ?"
    
    // 4. 参数值（按顺序）
    //    如 id=1 → updateList.add(1)
    
    // 5. Environment.id（数据源环境标识）
    //    如 "development"
    
    // equals 和 hashCode 基于所有 updateList 元素
    // 两个 CacheKey 相等 → 所有因素完全一致 → 缓存命中
    
    // 示例：
    // selectAll(id=1) → CacheKey: [selectAll, 0, MAX, SELECT..., 1, dev]
    // selectAll(id=2) → CacheKey: [selectAll, 0, MAX, SELECT..., 2, dev]  ← 不同 Key
    // selectAll(id=1) → CacheKey: [selectAll, 0, MAX, SELECT..., 1, dev]  ← 同 Key → 命中
    
    // 注意：同一个 SQL 不同参数 → 不同 CacheKey → 不命中
}
```

---

## 4.4 StatementHandler 体系（SimpleStatementHandler / PreparedStatementHandler）

### 4.4.1 StatementHandler 接口与实现

```java
// StatementHandler 接口
public interface StatementHandler {
    Statement prepare(Connection connection, Integer transactionTimeout);
    void parameterize(Statement statement);
    <E> List<E> query(Statement statement, ResultHandler resultHandler);
    int update(Statement statement);
    BoundSql getBoundSql();
    ParameterHandler getParameterHandler();
}

// ──── RoutingStatementHandler — 路由策略 ────
public class RoutingStatementHandler implements StatementHandler {
    private StatementHandler delegate;  // 根据 StatementType 选择实际 Handler
    
    public RoutingStatementHandler(Executor executor, MappedStatement ms, 
                                    Object parameter, RowBounds rowBounds, 
                                    ResultHandler resultHandler, BoundSql boundSql) {
        switch (ms.getStatementType()) {
            case STATEMENT:
                delegate = new SimpleStatementHandler(executor, ms, parameter, rowBounds, resultHandler, boundSql);
                break;
            case PREPARED:
                delegate = new PreparedStatementHandler(executor, ms, parameter, rowBounds, resultHandler, boundSql);
                break;
            case CALLABLE:
                delegate = new CallableStatementHandler(executor, ms, parameter, rowBounds, resultHandler, boundSql);
                break;
        }
    }
    
    @Override
    public Statement prepare(Connection connection, Integer transactionTimeout) {
        return delegate.prepare(connection, transactionTimeout);
    }
}

// ──── PreparedStatementHandler — 最常用 ────
public class PreparedStatementHandler extends BaseStatementHandler {
    
    @Override
    protected Statement instantiateStatement(Connection connection) {
        String sql = boundSql.getSql();
        
        // 创建 PreparedStatement
        PreparedStatement ps = connection.prepareStatement(sql);
        
        // 设置超时
        if (mappedStatement.getStatementTimeout() != null) {
            ps.setQueryTimeout(mappedStatement.getStatementTimeout());
        }
        
        return ps;
    }
    
    @Override
    public void parameterize(Statement statement) {
        // 使用 ParameterHandler 设置参数
        parameterHandler.setParameters((PreparedStatement) statement);
    }
    
    @Override
    public <E> List<E> query(Statement statement, ResultHandler resultHandler) {
        PreparedStatement ps = (PreparedStatement) statement;
        // 执行查询
        ResultSet rs = ps.executeQuery();
        // 使用 ResultSetHandler 映射结果
        return resultSetHandler.handleResultSets(rs);
    }
    
    @Override
    public int update(Statement statement) {
        PreparedStatement ps = (PreparedStatement) statement;
        return ps.executeUpdate();
    }
}
```

---

## 4.5 ParameterHandler — 参数处理与 TypeHandler 映射

### 4.5.1 ParameterHandler 源码

```java
// DefaultParameterHandler
public class DefaultParameterHandler implements ParameterHandler {
    private MappedStatement mappedStatement;
    private Object parameterObject;
    private BoundSql boundSql;
    
    @Override
    public void setParameters(PreparedStatement ps) {
        // 1. 获取参数映射列表
        List<ParameterMapping> parameterMappings = boundSql.getParameterMappings();
        
        // 2. 逐个设置参数
        for (int i = 0; i < parameterMappings.size(); i++) {
            ParameterMapping mapping = parameterMappings.get(i);
            String propertyName = mapping.getProperty();  // 如 "id", "name"
            
            // 3. 获取参数值
            Object value;
            if (parameterObject instanceof Map) {
                // Map 参数 → 直接取值
                value = ((Map)parameterObject).get(propertyName);
            } else {
                // JavaBean 参数 → 通过 MetaObject 取值（反射）
                MetaObject metaObject = configuration.newMetaObject(parameterObject);
                value = metaObject.getValue(propertyName);
            }
            
            // 4. 获取 TypeHandler（参数类型 → JDBC 类型映射）
            TypeHandler typeHandler = mapping.getTypeHandler();
            //   如 String → StringTypeHandler → ps.setString(i+1, value)
            //   如 Integer → IntegerTypeHandler → ps.setInt(i+1, value)
            //   如 Date → DateTypeHandler → ps.setDate(i+1, value)
            
            // 5. 设置 PreparedStatement 参数
            typeHandler.setParameter(ps, i + 1, value, mapping.getJdbcType());
        }
    }
}

// TypeHandler — 类型处理器（Java ↔ JDBC 类型映射）
// 注册表：TypeHandlerRegistry
public class TypeHandlerRegistry {
    // 已注册的 TypeHandler 映射
    // Java Type → JDBC Type → TypeHandler
    private Map<Type, Map<JdbcType, TypeHandler>> typeHandlerMap;
    
    // 常见映射：
    //   String    → VARCHAR   → StringTypeHandler    → ps.setString / rs.getString
    //   Integer   → INTEGER   → IntegerTypeHandler   → ps.setInt / rs.getInt
    //   Long      → BIGINT    → LongTypeHandler      → ps.setLong / rs.getLong
    //   Double    → DOUBLE    → DoubleTypeHandler    → ps.setDouble / rs.getDouble
    //   Date      → TIMESTAMP → DateTypeHandler      → ps.setDate / rs.getDate
    //   Boolean   → BOOLEAN   → BooleanTypeHandler   → ps.setBoolean / rs.getBoolean
    //   BigDecimal → DECIMAL  → BigDecimalTypeHandler → ps.setBigDecimal / rs.getBigDecimal
    //   byte[]    → BLOB      → BlobTypeHandler      → ps.setBlob / rs.getBlob
    
    // 自定义 TypeHandler：
    //   @MappedTypes(MyEnum.class)
    //   @MappedJdbcTypes(JdbcType.INTEGER)
    //   public class MyEnumTypeHandler extends BaseTypeHandler<MyEnum> {
    //       public void setNonNullParameter(PreparedStatement ps, int i, MyEnum param, JdbcType jdbcType) {
    //           ps.setInt(i, param.getCode());  // 枚举 → int
    //       }
    //       public MyEnum getNullableResult(ResultSet rs, String columnName) {
    //           return MyEnum.fromCode(rs.getInt(columnName));  // int → 枚举
    //       }
    //   }
}
```

### 4.5.2 MetaObject 反射取值

```java
// MetaObject — MyBatis 反射工具（简化属性访问）
// 支持嵌套属性：order.customer.name → 逐层反射

public class MetaObject {
    private Object originalObject;       // 原始对象
    private Reflector reflector;         // 反射元数据
    
    // 设置嵌套属性
    public void setValue(String name, Object value) {
        // "order.customer.name"
        // → 先获取 order 属性
        // → 再获取 order 的 customer 属性
        // → 再设置 customer 的 name 属性
        PropertyTokenizer tokenizer = new PropertyTokenizer(name);
        while (tokenizer.hasNext()) {
            metaObject = metaObject.metaObjectForProperty(tokenizer.getCurrentName());
            tokenizer = tokenizer.next();
        }
        metaObject.setProperty(tokenizer.getCurrentName(), value);
    }
    
    // 获取嵌套属性
    public Object getValue(String name) {
        PropertyTokenizer tokenizer = new PropertyTokenizer(name);
        Object value = reflector.getGetterInvoker(tokenizer.getCurrentName()).invoke(originalObject);
        // 逐层深入...
        return value;
    }
}
```

---

## 4.6 ResultSetHandler — 结果集映射与嵌套查询

### 4.6.1 DefaultResultSetHandler 核心源码

```java
// DefaultResultSetHandler — 结果集映射核心
public class DefaultResultSetHandler implements ResultSetHandler {
    
    @Override
    public List<Object> handleResultSets(Statement stmt) {
        // 1. 获取 ResultSet
        ResultSet rs = stmt.getResultSet();
        
        // 2. 遍历 ResultMap 映射
        List<Object> results = new ArrayList<>();
        for (ResultMap resultMap : mappedStatement.getResultMaps()) {
            // 3. 处理每个 ResultSet（可能有多个）
            handleResultSet(rs, resultMap, results);
        }
        
        return results;
    }
    
    private void handleResultSet(ResultSet rs, ResultMap resultMap, List<Object> results) {
        // 创建 ResultHandler（DefaultResultHandler / 自定义）
        
        // 创建 RowMapper（按 ResultMap 映射每行）
        Object rowValue = getRowValue(rs, resultMap);
        
        // 添加到结果列表
        results.add(rowValue);
    }
    
    private Object getRowValue(ResultSet rs, ResultMap resultMap) {
        // 1. 创建结果对象
        Object resultObject = createResultObject(rs, resultMap);
        //   → 通过反射创建 Order.class 实例
        
        // 2. 创建 MetaObject（用于设置属性）
        MetaObject metaObject = configuration.newMetaObject(resultObject);
        
        // 3. 映射每个 ResultMapping
        for (ResultMapping resultMapping : resultMap.getResultMappings()) {
            // 简单映射
            if (!resultMapping.hasNestedResultMapping()) {
                // 3.1 直接从 ResultSet 取值 → 设置到对象
                String column = resultMapping.getColumn();  // "order_id"
                String property = resultMapping.getProperty();  // "orderId"
                TypeHandler typeHandler = resultMapping.getTypeHandler();
                
                Object value = typeHandler.getResult(rs, column);
                metaObject.setValue(property, value);
            }
            
            // 嵌套映射（关联查询）
            if (resultMapping.hasNestedResultMapping()) {
                // 3.2 嵌套查询 / 嵌套结果映射
                Object nestedValue = getNestedMappingValue(rs, resultMapping);
                metaObject.setValue(resultMapping.getProperty(), nestedValue);
            }
        }
        
        return resultObject;
    }
}
```

### 4.6.2 嵌套查询 vs 嵌套结果映射

```
  ──── 嵌套查询（N+1 问题）─────
  
  <resultMap id="orderResultMap" type="Order">
      <id column="order_id" property="id"/>
      <result column="order_name" property="name"/>
      <!-- 嵌套查询：先查 Order，再对每条 Order 执行子查询 -->
      <association property="customer" 
                   select="selectCustomerById" 
                   column="customer_id"/>
  </resultMap>
  
  执行过程：
  │   1. SELECT * FROM order        → 返回 100 条 Order
  │   2. 对每条 Order → SELECT * FROM customer WHERE id = ?
  │   │   → 执行 100 次子查询（N+1 问题！）
  │   → 总 SQL 数 = 1 + 100 = 101
  
  ┌──────────────────────────────────────┐
  │  N+1 问题的危害：                     │
  │  │   100条数据 → 101次SQL              │
  │  │   1000条数据 → 1001次SQL            │
  │  │   性能灾难                          │
  │                                      │
  │  解决方案：                            │
  │  │   1. 使用嵌套结果映射（JOIN）        │
  │  │   2. 延迟加载（lazyLoadingEnabled） │
  │  │   3. 手动 JOIN 写大 SQL             │
  └──────────────────────────────────────┘
  
  ──── 嵌套结果映射（JOIN，推荐）─────
  
  <resultMap id="orderWithCustomerResultMap" type="Order">
      <id column="order_id" property="id"/>
      <result column="order_name" property="name"/>
      <association property="customer" javaType="Customer">
          <id column="customer_id" property="id"/>
          <result column="customer_name" property="name"/>
      </association>
  </resultMap>
  
  SQL: SELECT o.*, c.* FROM order o LEFT JOIN customer c ON o.customer_id = c.id
  
  执行过程：
  │   1. 一条 JOIN SQL → 返回所有数据
  │   2. ResultSetHandler 根据 ResultMap 映射
  │   │   → order_id → Order.id
  │   │   → customer_id → Order.customer.id
  │   │   → 同一个 customer_id 的行 → 合并为一个 Customer 对象
  │   → 总 SQL 数 = 1（性能好！）
```

---

## 4.7 一级缓存（LocalCache / PerpetualCache）

### 4.7.1 一级缓存原理与源码

```java
// 一级缓存 — SqlSession 级别（默认开启，不可关闭）
// 存储位置：BaseExecutor.localCache (PerpetualCache)

// PerpetualCache — 基于 HashMap 的缓存
public class PerpetualCache implements Cache {
    private String id;  // Cache ID（通常是 MappedStatement.id）
    private Map<Object, Object> cache = new HashMap<>();
    
    @Override
    public void putObject(Object key, Object value) {
        cache.put(key, value);
    }
    
    @Override
    public Object getObject(Object key) {
        return cache.get(key);
    }
}
```

### 4.7.2 一级缓存命中条件

```
  一级缓存命中条件（4 个全部满足）：
  ┌──────────────────────────────────────────────────┐
  │                                                  │
  │  1. 同一个 SqlSession（不同 Session 不共享）      │
  │     │   sqlSession1.selectList(...) → 缓存       │
  │     │   sqlSession2.selectList(...) → 不命中     │
  │                                                  │
  │  2. 同一个 MappedStatement.id（同一个 SQL 映射）  │
  │     │   selectById → 缓存                        │
  │     │   selectByName → 不命中（不同 ms.id）      │
  │                                                  │
  │  3. 同一个 SQL + 相同参数值                       │
  │     │   selectById(1) → 缓存                    │
  │     │   selectById(2) → 不命中（不同参数）        │
  │                                                  │
  │  4. 相同的 RowBounds（分页参数一致）               │
  │     │   offset=0, limit=100 → 缓存              │
  │     │   offset=0, limit=50 → 不命中              │
  │                                                  │
  └──────────────────────────────────────────────────┘
  
  一级缓存失效场景：
  ┌──────────────────────────────────────────────────┐
  │                                                  │
  │  1. SqlSession 关闭 → 缓存清空                   │
  │     │   sqlSession.close() → localCache.clear() │
  │                                                  │
  │  2. 执行 insert/update/delete → 缓存清空         │
  │     │   sqlSession.update(...)                   │
  │     │   → BaseExecutor.update()                  │
  │     │   → clearLocalCache()                      │
  │     │   原因：数据变更 → 缓存可能过期              │
  │                                                  │
  │  3. 手动清空缓存                                  │
  │     │   sqlSession.clearCache()                  │
  │     │   → localCache.clear()                     │
  │                                                  │
  │  4. commit / rollback → 缓存清空                  │
  │     │   sqlSession.commit()                      │
  │     │   → BaseExecutor.commit()                  │
  │     │   → localCache.clear()                     │
  │                                                  │
  │  5. 不同的查询条件 → CacheKey 不同 → 不命中      │
  │                                                  │
  └──────────────────────────────────────────────────┘
```

---

## 4.8 二级缓存（TransactionalCacheManager / CachingExecutor）

### 4.8.1 二级缓存原理

```
  ──── 二级缓存 — Mapper 级别（跨 SqlSession 共享）─────
  
  开启条件：
  │   1. 全局配置：cacheEnabled=true（默认 true）
  │   2. Mapper XML：<cache/> 或 @CacheNamespace
  │   3. 实体类可序列化（implements Serializable）
  
  工作流程：
  
  SqlSession A                          SqlSession B
      │                                      │
      ├── selectById(1) ──────────▶          │
      │   │                                  │
      │   ├── 一级缓存未命中 ──────▶          │
      │   │   → 查数据库                      │
      │   │   → 结果存入一级缓存               │
      │   │   → 结果暂存到 TransactionalCache │
      │   │       （事务未提交，暂不写入二级缓存）│
      │   │                                  │
      │   ├── sqlSessionA.commit() ────▶     │
      │   │   → TransactionalCacheManager.commit() │
      │   │   → 暂存数据 → 写入二级缓存       │
      │   │   → 一级缓存清空                  │
      │   │                                  │
      │   │              sqlSessionB.selectById(1)
      │   │                  │
      │   │                  ├── 一级缓存未命中
      │   │                  ├── 二级缓存命中！✓
      │   │                  │   → 返回数据（不需要查数据库）
      │   │                  │   → 存入 B 的一级缓存
      │   │
      │   └── sqlSessionA 关闭 ──────▶       │
```

### 4.8.2 CachingExecutor 源码

```java
// CachingExecutor — 二级缓存装饰器
public class CachingExecutor implements Executor {
    private Executor delegate;  // 实际执行器（SimpleExecutor）
    private TransactionalCacheManager tcm;  // 事务缓存管理器
    
    @Override
    public <E> List<E> query(MappedStatement ms, Object parameter, 
                              RowBounds rowBounds, ResultHandler resultHandler) {
        // 1. 获取 BoundSql 和 CacheKey
        BoundSql boundSql = ms.getBoundSql(parameter);
        CacheKey cacheKey = delegate.createCacheKey(ms, parameter, rowBounds, boundSql);
        
        // 2. 检查二级缓存
        Cache cache = ms.getCache();  // 二级缓存对象（Mapper 级别）
        if (cache != null) {
            // 2.1 检查是否需要清空缓存（写操作后）
            if (ms.isFlushCacheRequired()) {
                cache.clear();
            }
            
            // 2.2 查询二级缓存
            List<E> cachedResult = (List<E>) tcm.getObject(cache, cacheKey);
            if (cachedResult != null) {
                // 命中 → 返回
                return cachedResult;
            }
            
            // 2.3 未命中 → 查数据库（委托给 SimpleExecutor）
            List<E> result = delegate.query(ms, parameter, rowBounds, resultHandler);
            
            // 2.4 暂存结果到 TransactionalCache
            tcm.putObject(cache, cacheKey, result);
            // 注意：此时数据只在 TransactionalCache 的 entriesToAddOnCommit 中
            //       还没写入真正的二级缓存
            //       等事务提交后才会写入
            
            return result;
        }
        
        // 3. 无二级缓存 → 直接查一级缓存 + 数据库
        return delegate.query(ms, parameter, rowBounds, resultHandler);
    }
    
    @Override
    public void commit(boolean required) {
        // 事务提交 → 将暂存数据写入二级缓存
        delegate.commit(required);
        tcm.commit();  // TransactionalCacheManager.commit()
    }
    
    @Override
    public void rollback(boolean required) {
        // 事务回滚 → 清除暂存数据（不写入二级缓存）
        delegate.rollback(required);
        tcm.rollback();
    }
}
```

### 4.8.3 TransactionalCacheManager

```java
// TransactionalCacheManager — 管理事务与缓存的协调
public class TransactionalCacheManager {
    // 每个 Mapper 的二级缓存 → 对应一个 TransactionalCache
    private Map<Cache, TransactionalCache> transactionalCaches = new HashMap<>();
    
    public void putObject(Cache cache, CacheKey key, Object value) {
        // 暂存到 TransactionalCache
        getTransactionalCache(cache).putObject(key, value);
    }
    
    public Object getObject(Cache cache, CacheKey key) {
        // 从 TransactionalCache 取
        // 如果事务已提交 → 从真正的缓存取
        // 如果事务未提交 → 从 entriesToAddOnCommit 取（可能返回 null）
        return getTransactionalCache(cache).getObject(key);
    }
    
    public void commit() {
        // 所有 TransactionalCache 提交
        for (TransactionalCache txCache : transactionalCaches.values()) {
            txCache.commit();
        }
    }
    
    public void rollback() {
        // 所有 TransactionalCache 回滚
        for (TransactionalCache txCache : transactionalCaches.values()) {
            txCache.rollback();
        }
    }
}

// TransactionalCache — 事务缓存（装饰器）
public class TransactionalCache implements Cache {
    private Cache delegate;  // 真正的二级缓存（PerpetualCache + 装饰器链）
    
    // 暂存区：事务提交后才写入 delegate
    private Map<Object, Object> entriesToAddOnCommit = new HashMap<>();
    
    // 待清除区：事务提交时清除 delegate 中的这些 key
    private Set<Object> entriesToRemoveOnCommit = new HashSet<>();
    
    @Override
    public void putObject(Object key, Object value) {
        // 不直接写 delegate → 写暂存区
        entriesToAddOnCommit.put(key, value);
    }
    
    @Override
    public Object getObject(Object key) {
        // 先查 delegate（已提交的数据）
        Object value = delegate.getObject(key);
        if (value != null) return value;
        
        // 再查暂存区（当前事务的数据）
        return entriesToAddOnCommit.get(key);
    }
    
    public void commit() {
        // 提交 → 暂存数据写入真正的缓存
        for (Map.Entry<Object, Object> entry : entriesToAddOnCommit.entrySet()) {
            delegate.putObject(entry.getKey(), entry.getValue());
        }
        // 清除标记的 key
        for (Object key : entriesToRemoveOnCommit) {
            delegate.removeObject(key);
        }
        // 清空暂存区
        entriesToAddOnCommit.clear();
        entriesToRemoveOnCommit.clear();
    }
    
    public void rollback() {
        // 回滚 → 不写入缓存 → 清空暂存区
        entriesToAddOnCommit.clear();
        entriesToRemoveOnCommit.clear();
    }
}
```

### 4.8.4 二级缓存装饰器链

```
  二级缓存装饰器链（<cache/> 默认配置）：
  
  ┌─── Cache Builder 创建 ──── ──────────────────────┐
  │                                                    │
  │  PerpetualCache（底层 HashMap 存储）                │
  │  │                                                 │
  │  ├── 装饰器1: BlockingCache                       │
  │  │   │   防止缓存击穿：缓存未命中时加锁            │
  │  │   │   只允许一个线程查数据库写入缓存            │
  │  │   │   其他线程等待 → 缓存写入后释放锁          │
  │  │                                                 │
  │  ├── 装饰器2: FifoCache                            │
  │  │   │   FIFO 淘汰策略：LinkedHashMap + maxSize   │
  │  │   │   缓存数量超 maxSize → 淘汰最早的           │
  │  │                                                 │
  │  ├── 装饰器3: LoggingCache                         │
  │  │   │   日志装饰器：记录缓存命中/未命中次数       │
  │  │   │   hit / miss 比率                          │
  │  │                                                 │
  │  ├── 装饰器4: SynchronizedCache                    │
  │  │   │   同步装饰器：所有操作加 synchronized       │
  │  │   │   保证线程安全                              │
  │  │                                                 │
  │  └── 最终链路：                                    │
  │   SynchronizedCache → LoggingCache → FifoCache     │
  │   → BlockingCache → PerpetualCache                 │
  │                                                    │
  │   getObject 请求流转：                              │
  │   Sync.getObject → Logging.getObject(记录命中)     │
  │   → Fifo.getObject → Blocking.getObject(锁)       │
  │   → Perpetual.getObject → HashMap.get              │
  │                                                    │
  │   自定义装饰器（XML 配置）：                        │
  │   <cache type="com.example.MyCache">               │
  │     <property name="maxSize" value="1024"/>         │
  │     <property name="eviction" value="LRU"/>         │
  │   </cache>                                         │
  │                                                    │
  │   可选淘汰策略：                                    │
  │   FIFO  → FifoCache（先进先出）                     │
  │   LRU   → LruCache（最近最少使用）                  │
  │   SOFT  → SoftCache（软引用，GC时回收）             │
  │   WEAK  → WeakCache（弱引用，更早回收）             │
  └────────────────────────────────────────────────────┘
```

---

## 4.9 动态 SQL — OGNL 表达式 + SqlNode 体系

### 4.9.1 SqlNode 体系

```
  ──── 动态 SQL — SqlNode 体系 ────
  
  XML 标签 → SqlNode 实现类
  
  ┌──────────────────┬──────────────────┬─────────────────┐
  │  XML 标签          │  SqlNode 实现类    │  功能             │
  ├──────────────────┼──────────────────┼─────────────────┤
  │  <if>            │ IfSqlNode        │ 条件判断          │
  │  <choose>/<when> │ ChooseSqlNode    │ 多条件分支        │
  │  <otherwise>     │                  │                   │
  │  <where>         │ WhereSqlNode     │ WHERE 条件拼接    │
  │  <set>           │ SetSqlNode       │ UPDATE SET 拼接   │
  │  <foreach>       │ ForEachSqlNode   │ 集合遍历          │
  │  <trim>          │ TrimSqlNode      │ 前缀/后缀裁剪     │
  │  <sql>/<include> │ SqlFragment      │ SQL 片段引用      │
  │  <bind>          │ VarDeclSqlNode   │ 变量绑定          │
  │  文本 SQL         │ StaticTextSqlNode│ 静态文本          │
  │  ${}             │ TextSqlNode      │ 文本替换(不安全)   │
  │  混合内容          │ MixedSqlNode     │ 多 SqlNode 组合   │
  └──────────────────┴──────────────────┴─────────────────┘
```

### 4.9.2 动态 SQL 解析与执行

```java
// DynamicSqlSource — 动态 SQL 源
public class DynamicSqlSource implements SqlSource {
    private Configuration configuration;
    private SqlNode rootSqlNode;  // 根 SqlNode（通常是 MixedSqlNode）
    
    @Override
    public BoundSql getBoundSql(Object parameterObject) {
        // 1. 创建 DynamicContext（上下文，存储拼接的 SQL）
        DynamicContext context = new DynamicContext(configuration, parameterObject);
        
        // 2. 递归应用所有 SqlNode → 拼接 SQL 到 context
        rootSqlNode.apply(context);
        //   每个 SqlNode 的 apply() 方法：
        //   IfSqlNode.apply():
        //     if (OGNL.eval(expression, parameterObject)) {
        //         contents.apply(context);  // 条件满足 → 拼接内容
        //     }
        //   ForEachSqlNode.apply():
        //     for (item : collection) {
        //         context.bind("item", item);
        //         contents.apply(context);  // 遍历 → 逐项拼接
        //     }
        //   WhereSqlNode.apply():
        //     contents.apply(context);  // 先拼接子内容
        //     // 然后裁剪：去掉前缀的 AND/OR，添加 WHERE
        
        // 3. 解析 #{} 占位符
        SqlSourceBuilder sqlSourceBuilder = new SqlSourceBuilder(configuration);
        SqlSource sqlSource = sqlSourceBuilder.parse(context.getSql(), parameterObject);
        
        // 4. 创建 BoundSql
        BoundSql boundSql = sqlSource.getBoundSql(parameterObject);
        
        // 5. 绑定附加参数
        for (Map.Entry<String, Object> entry : context.getBindings()) {
            boundSql.setAdditionalParameter(entry.getKey(), entry.getValue());
        }
        
        return boundSql;
    }
}

// #{} vs ${} 占位符解析
// ──── #{} → PreparedStatement 参数（安全，防 SQL 注入）─────
//   SELECT * FROM order WHERE id = #{id}
//   → 解析为: SELECT * FROM order WHERE id = ?
//   → ParameterMapping: {property="id", jdbcType=null}
//   → ps.setInt(1, idValue)
//
// ──── ${} → 直接替换字符串（不安全，有 SQL 注入风险）─────
//   SELECT * FROM ${tableName} WHERE id = ${id}
//   → 解析为: SELECT * FROM order WHERE id = 1
//   → 无参数绑定，直接拼接字符串
//   → 不推荐使用！仅在 ORDER BY / 动态表名等场景

// OGNL 表达式
// ──── MyBatis 使用 OGNL 表达式语言解析条件 ────
// <if test="id != null">        → OGNL: parameterObject.id != null
// <if test="name != null and name != ''"> → OGNL: name != null && name != ''
// <if test="list != null and list.size > 0"> → OGNL: list != null && list.size > 0
// OGNL 支持的运算：==, !=, >, <, >=, <=, and, or, !, 方法调用
```

### 4.9.3 WhereSqlNode 和 SetSqlNode 裁剪逻辑

```java
// WhereSqlNode — 自动处理 WHERE 前缀
public class WhereSqlNode extends TrimSqlNode {
    public WhereSqlNode(Configuration configuration, SqlNode contents) {
        // TrimSqlNode 参数：
        super(configuration, contents,
            "WHERE",            // 前缀：添加 WHERE
            "AND |OR ",         // 前缀覆盖：去掉开头 AND/OR
            null,               // 后缀：无
            "AND |OR ",         // 后缀覆盖：去掉结尾 AND/OR
            "WHERE");           // 前缀首次出现的标记
    }
}

// 举例：
// <where>
//     <if test="id != null"> AND id = #{id} </if>
//     <if test="name != null"> AND name = #{name} </if>
// </where>
//
// 场景1：id=1, name=null
//   拼接: " AND id = ?"
//   裁剪: 去掉前缀 AND → "id = ?"
//   添加前缀 WHERE → "WHERE id = ?"
//
// 场景2：id=null, name="张三"
//   拼接: " AND name = ?"
//   裁剪: 去掉前缀 AND → "name = ?"
//   添加前缀 WHERE → "WHERE name = ?"
//
// 场景3：id=1, name="张三"
//   拼接: " AND id = ? AND name = ?"
//   裁剪: 去掉前缀 AND → "id = ? AND name = ?"
//   添加前缀 WHERE → "WHERE id = ? AND name = ?"
//
// 场景4：id=null, name=null
//   拼接: ""（空）
//   不添加 WHERE → ""（无 WHERE 子句）

// SetSqlNode — 自动处理 SET 前缀和逗号
public class SetSqlNode extends TrimSqlNode {
    public SetSqlNode(Configuration configuration, SqlNode contents) {
        super(configuration, contents,
            "SET",              // 前缀：添加 SET
            null,               // 前缀覆盖：无
            ",",                // 后缀覆盖：去掉结尾逗号
            null,               // 后缀：无
            "SET");             // 首次出现标记
    }
}

// 举例：
// <set>
//     <if test="name != null"> name = #{name}, </if>
//     <if test="status != null"> status = #{status}, </if>
// </set>
//
// 场景：name="张三", status=1
//   拼接: " name = ?, status = ?,"
//   裁剪: 去掉结尾逗号 → " name = ?, status = ?"
//   添加前缀 SET → "SET name = ?, status = ?"
```

---

## 4.10 插件机制（Interceptor + Plugin.wrap 四大对象拦截）

### 4.10.1 插件机制原理

```
  ──── MyBatis 插件（Interceptor）机制 ────
  
  核心原理：JDK 动态代理 + 责任链
  
  可拦截的四大对象：
  ┌──────────────────────────────────────────────────┐
  │  1. Executor                                     │
  │     │   拦截点：update, query, commit, rollback   │
  │     │   适用：缓存、分页、SQL 改写                 │
  │                                                  │
  │  2. StatementHandler                             │
  │     │   拦截点：prepare, parameterize, query      │
  │     │   适用：SQL 改写、分页（最常用拦截点）        │
  │                                                  │
  │  3. ParameterHandler                             │
  │     │   拦截点：setParameters                     │
  │     │   适用：参数改写                             │
  │                                                  │
  │  4. ResultSetHandler                             │
  │     │   拦截点：handleResultSets                  │
  │     │   适用：结果集改写                           │
  └──────────────────────────────────────────────────┘
  
  代理创建顺序：
  │   Executor（最先被代理）
  │   │   → StatementHandler
  │   │   │   → ParameterHandler
  │   │   │   │   → ResultSetHandler（最后被代理）
  │
  │   多个插件 → 多层代理（责任链）
  │   │   Plugin.wrap(Plugin.wrap(Plugin.wrap(target, interceptor1), interceptor2), interceptor3)
  │   │   → 三层代理嵌套
  │   │   → 调用时逐层拦截 → 递归调用
```

### 4.10.2 Plugin.wrap 源码

```java
// Plugin — JDK 动态代理创建
public class Plugin implements InvocationHandler {
    private Object target;           // 目标对象（四大对象之一）
    private Interceptor interceptor; // 拦截器
    private Map<Class<?>, Set<Method>> signatureMap;  // 拦截方法映射
    
    // ──── wrap — 创建代理 ────
    public static Object wrap(Object target, Interceptor interceptor) {
        // 1. 解析 @Intercepts 注解 → 获取要拦截的方法
        Map<Class<?>, Set<Method>> signatureMap = getSignatureMap(interceptor);
        
        // 2. 检查 target 是否是需要拦截的类
        Class<?> type = target.getClass();
        for (Class<?> key : signatureMap.keySet()) {
            if (key.isAssignableFrom(type)) {
                // 3. 创建 JDK 动态代理
                return Proxy.newProxyInstance(
                    type.getClassLoader(),
                    type.getInterfaces(),  // 四大对象的接口
                    new Plugin(target, interceptor, signatureMap));
            }
        }
        
        // 不需要拦截 → 返回原始对象
        return target;
    }
    
    // ──── invoke — 代理调用 ────
    @Override
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        // 1. 检查是否是拦截方法
        Set<Method> methods = signatureMap.get(method.getDeclaringClass());
        if (methods != null && methods.contains(method)) {
            // 2. 是拦截方法 → 调用 Interceptor.intercept
            return interceptor.intercept(new Invocation(target, method, args));
        }
        
        // 3. 不是拦截方法 → 直接调用原方法
        return method.invoke(target, args);
    }
}

// @Intercepts 注解
@Intercepts({
    @Signature(type = StatementHandler.class, method = "prepare", 
               args = {Connection.class, Integer.class}),
    @Signature(type = StatementHandler.class, method = "query", 
               args = {Statement.class, ResultHandler.class})
})
public class MyInterceptor implements Interceptor {
    @Override
    public Object intercept(Invocation invocation) throws Throwable {
        // 拦截逻辑
        StatementHandler handler = (StatementHandler) invocation.getTarget();
        BoundSql boundSql = handler.getBoundSql();
        String sql = boundSql.getSql();
        
        // 改写 SQL（如添加分页）
        String newSql = sql + " LIMIT 10 OFFSET 0";
        // 通过反射修改 BoundSql.sql（MetaObject）
        MetaObject metaObject = SystemMetaObject.forObject(handler);
        metaObject.setValue("delegate.boundSql.sql", newSql);
        
        // 继续执行（调用原方法）
        return invocation.proceed();
    }
    
    @Override
    public Object plugin(Object target) {
        return Plugin.wrap(target, this);  // 创建代理
    }
}
```

### 4.10.3 多层代理执行流程

```
  多层代理执行流程（3 个 Interceptor）
  
  executor.query(...)
      │
      ▼
  Proxy$Interceptor3.invoke()  ←── 最外层代理
      │   检查方法是否在 signatureMap
      │   是 → interceptor3.intercept(invocation)
      │   │   │   前置逻辑
      │   │   ├── invocation.proceed()
      │   │   │   │
      │   │   │   ▼
      │   │   │   method.invoke(target, args)  ←── target 是下一层代理
      │   │   │   │
      │   │   │   ▼
      │   │   │   Proxy$Interceptor2.invoke()
      │   │   │   │   interceptor2.intercept(invocation)
      │   │   │   │   │   前置逻辑
      │   │   │   │   │   ├── invocation.proceed()
      │   │   │   │   │   │   │
      │   │   │   │   │   │   ▼
      │   │   │   │   │   │   Proxy$Interceptor1.invoke()
      │   │   │   │   │   │   │   interceptor1.intercept(invocation)
      │   │   │   │   │   │   │   │   前置逻辑
      │   │   │   │   │   │   │   │   ├── invocation.proceed()
      │   │   │   │   │   │   │   │   │   │
      │   │   │   │   │   │   │   │   │   ▼
      │   │   │   │   │   │   │   │   │   SimpleExecutor.query()
      │   │   │   │   │   │   │   │   │   │   → 查一级缓存
      │   │   │   │   │   │   │   │   │   │   → 查数据库
      │   │   │   │   │   │   │   │   │   │   ← 返回结果
      │   │   │   │   │   │   │   │   │
      │   │   │   │   │   │   │   │   后置逻辑
      │   │   │   │   │   │   │   ← 返回结果
      │   │   │   │   │   │   │
      │   │   │   │   │   │   后置逻辑
      │   │   │   │   │   │   ← 返回结果
      │   │   │   │   │   │
      │   │   │   │   │   后置逻辑
      │   │   │   │   │   ← 返回结果
      │   │   │   │   │
      │   │   │   │   后置逻辑
      │   │   │   │   ← 返回结果
      │   │   │   │
      │   │   │   后置逻辑
      │   │   │   ← 返回结果
      │   │
      │   后置逻辑
      │   ← 返回结果
  
  注意：
  │   Interceptor 注册顺序 → wrap 嵌套顺序
  │   第一个注册的 → 最内层代理 → 前置最先执行
  │   最后注册的 → 最外层代理 → 后置最后执行
```

---

## 4.11 MyBatis-Spring 自动装配（SqlSessionTemplate + MapperScannerConfigurer）

### 4.11.1 SqlSessionTemplate — Spring 管理的 SqlSession

```java
// SqlSessionTemplate — 线程安全的 SqlSession
// 问题：DefaultSqlSession 不是线程安全的（一级缓存是 HashMap）
// 解决：SqlSessionTemplate 通过动态代理保证每次使用不同的 SqlSession

public class SqlSessionTemplate implements SqlSession, DisposableBean {
    private SqlSessionFactory sqlSessionFactory;
    private ExecutorType executorType;
    private SqlSession sqlSessionProxy;  // 代理对象
    
    public SqlSessionTemplate(SqlSessionFactory sqlSessionFactory) {
        this.sqlSessionFactory = sqlSessionFactory;
        this.sqlSessionProxy = (SqlSession) Proxy.newProxyInstance(
            SqlSessionFactory.class.getClassLoader(),
            new Class[]{SqlSession.class},
            new SqlSessionInterceptor());  // ← 关键：每次调用创建新 SqlSession
    }
    
    @Override
    public <E> List<E> selectList(String statement, Object parameter) {
        // 调用代理对象 → SqlSessionInterceptor.invoke()
        return sqlSessionProxy.selectList(statement, parameter);
    }
    
    // ──── SqlSessionInterceptor — 核心拦截逻辑 ────
    private class SqlSessionInterceptor implements InvocationHandler {
        @Override
        public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
            // 1. 获取当前事务绑定的 SqlSession
            //    Spring 事务管理器会将 SqlSession 绑定到 ThreadLocal
            SqlSession sqlSession = SqlSessionUtils.getSqlSession(
                sqlSessionFactory, executorType, 
                TransactionSynchronizationManager.getResource(sqlSessionFactory));
            
            if (sqlSession == null) {
                // 无事务 → 创建新 SqlSession
                sqlSession = sqlSessionFactory.openSession(executorType);
            }
            
            try {
                // 2. 执行方法
                Object result = method.invoke(sqlSession, args);
                
                // 3. 如果不是事务环境 → 自动提交关闭
                if (!TransactionSynchronizationManager.isSynchronizationActive()) {
                    sqlSession.commit();
                    sqlSession.close();
                }
                
                return result;
            } catch (Exception e) {
                // 异常 → 关闭 SqlSession
                sqlSession.close();
                throw e;
            }
        }
    }
}

// SqlSessionUtils — 管理 SqlSession 与 Spring 事务的绑定
public class SqlSessionUtils {
    // ThreadLocal: 事务绑定的 SqlSession
    // key: SqlSessionFactory
    // value: SqlSessionHolder（包含 SqlSession + 事务信息）
    
    public static SqlSession getSqlSession(SqlSessionFactory factory, ExecutorType type, 
                                            SqlSessionHolder holder) {
        // 1. 如果有事务绑定 → 直接返回（事务内共用同一个 SqlSession）
        if (holder != null && holder.getSqlSession() != null) {
            return holder.getSqlSession();
        }
        
        // 2. 无事务 → 创建新 SqlSession
        SqlSession session = factory.openSession(type);
        
        // 3. 如果有 Spring 事务 → 注册同步
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            holder = new SqlSessionHolder(session, type);
            TransactionSynchronizationManager.bindResource(factory, holder);
            // 事务结束时 → 自动 commit/close
        }
        
        return session;
    }
}
```

### 4.11.2 MapperScannerConfigurer — 自动扫描 Mapper

```java
// MapperScannerConfigurer — 扫描 Mapper 接口并注册为 Bean
public class MapperScannerConfigurer implements BeanDefinitionRegistryPostProcessor {
    
    private String basePackage;  // 如 "com.example.mapper"
    
    @Override
    public void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) {
        // 1. 创建 ClassPathMapperScanner
        ClassPathMapperScanner scanner = new ClassPathMapperScanner(registry);
        scanner.setSqlSessionTemplate(sqlSessionTemplate);
        scanner.setSqlSessionFactory(sqlSessionFactory);
        
        // 2. 扫描指定包下的 Mapper 接口
        scanner.scan(basePackage);
        // │   → 找到所有 @Mapper 注解或指定包下的接口
        // │   → 为每个接口创建 MapperFactoryBean Definition
        // │   → 注册到 Spring 容器
    }
}

// MapperFactoryBean — 创建 Mapper 代理 Bean
public class MapperFactoryBean<T> extends SqlSessionDaoSupport 
    implements FactoryBean<T> {
    
    private Class<T> mapperInterface;
    
    @Override
    public T getObject() {
        // 通过 SqlSessionTemplate 获取 Mapper 代理
        return getSqlSession().getMapper(mapperInterface);
        // │   → SqlSessionTemplate.getMapper()
        // │   → Configuration.getMapper()
        // │   → MapperProxyFactory.newInstance(sqlSession)
        // │   → JDK 动态代理创建 MapperProxy
    }
    
    @Override
    public Class<T> getObjectType() {
        return mapperInterface;
    }
}

// ──── Mapper 扫描后的 Bean 注册 ────
// com.example.mapper.OrderMapper → MapperFactoryBean<OrderMapper>
//   │   getObject() → OrderMapper 代理对象
//   │   → 注入到 Service 层
//   │   → service.orderMapper.selectAll()
//   │   → MapperProxy.invoke()
//   │   → SqlSessionTemplate.selectList()
//   │   → SqlSessionInterceptor → 获取 SqlSession → executor.query()
```

---

## 4.12 MyBatis 源码面试高频题

| # | 问题 | 核心答案 |
|---|------|----------|
| 1 | MyBatis 一级缓存和二级缓存区别？ | 一级=SqlSession级别HashMap默认开启不可关闭；二级=Mapper级别跨Session共享需手动开启 |
| 2 | 一级缓存什么时候失效？ | SqlSession关闭/执行update/insert/delete/commit/rollback/clearCache |
| 3 | 二级缓存为什么需要序列化？ | 跨SqlSession共享，可能存到磁盘/外部缓存，必须序列化；否则对象引用混乱 |
| 4 | #{} 和 ${} 区别？ | #{}=PreparedStatement参数(防注入)；${}=字符串直接替换(有注入风险) |
| 5 | MapperProxy 原理？ | JDK动态代理→invoke()→MapperMethod.execute()→SqlSession.selectList/update等 |
| 6 | MyBatis 插件拦截哪些对象？ | Executor/StatementHandler/ParameterHandler/ResultSetHandler四大对象 |
| 7 | Plugin.wrap 原理？ | JDK动态代理→InvocationHandler.invoke()→检查是否拦截方法→interceptor.intercept() |
| 8 | Executor 三种类型？ | Simple每次新建Statement；Reuse按SQL缓存Statement；Batch批量addBatch+executeBatch |
| 9 | SqlSessionTemplate 为什么线程安全？ | 每次调用通过代理创建新SqlSession(非事务)或获取事务绑定的SqlSession(有事务) |
| 10 | 嵌套查询 N+1 问题？ | select属性→先查主表→每行触发子查询→SQL数=N+1；解决：用嵌套结果映射(JOIN) |
| 11 | MyBatis 如何处理动态 SQL？ | SqlNode体系→各节点apply()拼接→OGNL表达式判断→BoundSql最终SQL |
| 12 | CacheKey 由什么决定？ | MappedStatement.id + RowBounds + SQL字符串 + 参数值 + Environment.id |
| 13 | TransactionalCache 作用？ | 事务未提交→暂存entriesToAddOnCommit；提交→写入真正缓存；回滚→清空暂存 |
| 14 | TypeHandler 作用？ | Java类型↔JDBC类型映射；setParameter设参数值；getResult取结果值；可自定义 |
| 15 | 延迟加载原理？ | lazyLoadingEnabled=true→嵌套查询返回代理对象→首次访问属性时才执行子查询 |

---

## 4.13 MyBatis 与 Spring Cloud 整合链路（从 Controller 到 DB 的完整调用链）

### 4.13.1 完整请求链路图

```
  ──── Spring Cloud + MyBatis 完整请求链路 ────
  
  用户请求: GET /api/order/1
      │
      ▼
  ┌─── Spring Cloud Gateway ───────────────────────────┐
  │  │                                                  │
  │  ├── 1. RoutePredicateHandlerMapping               │
  │  │   │   Path=/api/order/** → 匹配 order-route     │
  │  │                                                  │
  │  ├── 2. SentinelGatewayFilter                      │
  │  │   │   SphU.entry("order-route")                 │
  │  │   │   FlowSlot → 检查流控规则                    │
  │  │                                                  │
  │  ├── 3. ReactiveLoadBalancerClientFilter            │
  │  │   │   lb://order-service → Nacos 查询实例        │
  │  │   │   → 选择 10.0.0.5:8080                     │
  │  │                                                  │
  │  ├── 4. NettyRoutingFilter                         │
  │  │   │   HttpClient.request → 发送到 10.0.0.5:8080 │
  │  │                                                  │
  │  └── 5. Response → 返回给用户                       │
  └─────────────────────────────────────────────────────┘
      │
      ▼ HTTP 转发
  ┌─── Order Service (10.0.0.5:8080) ───────────────────┐
  │  │                                                    │
  │  ├── 6. DispatcherServlet (Spring MVC)               │
  │  │   │   HandlerMapping → OrderController.getOrder() │
  │  │                                                    │
  │  ├── 7. AOP Proxy                                    │
  │  │   │   @Transactional → TransactionInterceptor     │
  │  │   │   │   doBegin() → DataSource.getConnection    │
  │  │   │   │   → autocommit=false                      │
  │  │   │   │   → 绑定到 TransactionSynchronizationMgr │
  │  │                                                    │
  │  ├── 8. OrderController.getOrder(1)                  │
  │  │   │   → orderService.getOrder(1)                  │
  │  │                                                    │
  │  ├── 9. OrderService.getOrder(1)                     │
  │  │   │   → orderMapper.selectById(1)                 │
  │  │   │   │   → MapperProxy.invoke()                  │
  │  │   │   │   → MapperMethod.execute()                │
  │  │   │   │   → SqlSessionTemplate.selectOne()        │
  │  │   │   │   → SqlSessionInterceptor.invoke()        │
  │  │   │   │   → 获取事务绑定的 SqlSession               │
  │  │                                                    │
  │  ├── 10. SqlSession → Executor → 查缓存             │
  │  │   │   → 二级缓存(CachingExecutor) → 未命中       │
  │  │   │   → 一级缓存(BaseExecutor.localCache) → 未命中│
  │  │   │   → queryFromDatabase()                       │
  │  │                                                    │
  │  ├── 11. StatementHandler                            │
  │  │   │   PreparedStatementHandler.prepare()           │
  │  │   │   │   → conn.prepareStatement(sql)            │
  │  │   │   → ParameterHandler.setParameters()          │
  │  │   │   │   → TypeHandler.setInt(ps, 1, idValue)    │
  │  │   │   → ps.executeQuery()                         │
  │  │                                                    │
  │  ├── 12. ResultSetHandler                            │
  │  │   │   → handleResultSets(rs)                      │
  │  │   │   → ResultMap 映射 → Order 对象               │
  │  │   │   → TypeHandler.getInt(rs, "id")              │
  │  │   │   → MetaObject.setValue("id", value)          │
  │  │                                                    │
  │  ├── 13. 缓存写入                                    │
  │  │   │   → localCache.putObject(cacheKey, result)    │
  │  │   │   → tcm.putObject(cache, cacheKey, result)    │
  │  │   │   │   → entriesToAddOnCommit（暂存）          │
  │  │                                                    │
  │  ├── 14. @Transactional 后置                          │
  │  │   │   → commit()                                  │
  │  │   │   │   → SqlSession.commit()                   │
  │  │   │   │   → Executor.commit()                     │
  │  │   │   │   │   → tcm.commit() → 写入二级缓存       │
  │  │   │   │   │   → localCache.clear()                │
  │  │   │   │   → connection.commit()                   │
  │  │   │   │   → connection.close()                    │
  │  │                                                    │
  │  └── 15. 返回 Order 对象 → JSON 响应                 │
  │       │                                               │
  └── 16. Gateway Netty → 收到响应 → 返回给用户            │
  └────────────────────────────────────────────────────────┘
```

---

# 附录 A：Spring Cloud + MyBatis 请求全链路图

```
  ┌──────────────────────────────────────────────────────────────┐
  │                    请求全链路（从浏览器到数据库）               │
  │                                                              │
  │  Browser                                                     │
  │    │                                                         │
  │    │  GET /api/order/1                                       │
  │    ▼                                                         │
  │  ┌─────── Nacos 注册中心 ────────────────┐                   │
  │  │  order-service: 10.0.0.5:8080 (健康)  │                   │
  │  │  order-service: 10.0.0.6:8080 (健康)  │                   │
  │  │  pay-service:   10.0.0.7:8080 (健康)  │                   │
  │  └────────────────────────────────────────┘                   │
  │    │ ← 服务发现                                              │
  │    ▼                                                         │
  │  ┌─────── Spring Cloud Gateway ──────────┐                   │
  │  │  Sentinel 流控 → 放行                  │                   │
  │  │  LoadBalancer → 选择 10.0.0.5         │                   │
  │  │  Netty → 路由到后端                    │                   │
  │  └────────────────────────────────────────┘                   │
  │    │ ← HTTP 请求                                             │
  │    ▼                                                         │
  │  ┌─────── Order Service ─────────────────┐                   │
  │  │  Controller → Service → Mapper        │                   │
  │  │  │                                    │                   │
  │  │  │  @Transactional 开启事务            │                   │
  │  │  │  SqlSession → Executor → Statement │                   │
  │  │  │  → ParameterHandler → TypeHandler │                   │
  │  │  │  → PreparedStatement.execute()     │                   │
  │  │  │                                    │                   │
  │  │  │  ResultSet → ResultMap → Order     │                   │
  │  │  │  缓存写入                          │                   │
  │  │  │  commit / 返回                     │                   │
  │  └────────────────────────────────────────┘                   │
  │    │ ← JDBC                                                  │
  │    ▼                                                         │
  │  ┌─────── MySQL ──────────────────────────┐                   │
  │  │  SELECT * FROM order WHERE id = 1      │                   │
  │  │  → 返回 ResultSet                      │                   │
  │  └────────────────────────────────────────┘                   │
  │                                                              │
  │  配置来源：                                                   │
  │  ┌─── Nacos Config ───────────────────┐                     │
  │  │  gateway-route-config (路由配置)     │                     │
  │  │  order-service.yaml (应用配置)       │                     │
  │  │  sentinel-flow-rules (流控规则)      │                     │
  │  │  sentinel-degrade-rules (熔断规则)   │                     │
  │  │  datasource-config (数据源配置)      │                     │
  │  └─────────────────────────────────────┘                     │
  │                                                              │
  │  流控保护链路：                                               │
  │  ┌─── Sentinel Slot Chain ─────────────────────┐            │
  │  │  Gateway 入口 → NodeSelector → Statistic    │            │
  │  │  → Flow → Degrade → (通过/拦截)             │            │
  │  │                                              │            │
  │  │  Service 内部 → @Transactional 方法级流控    │            │
  │  │  → 也可加 Sentinel 注解保护                  │            │
  │  └─────────────────────────────────────────────┘            │
  └──────────────────────────────────────────────────────────────┘
```

---

# 附录 B：面试速记卡片（50 题精炼）

## Nacos（15题）

| # | 问题 | 一句话答案 |
|---|------|----------|
| 1 | Nacos AP/CP？ | 临时实例Distro(AP)+持久实例Raft(CP) |
| 2 | 注册实时性？ | 1.x UDP推送6s+30s拉取；2.x gRPC<500ms |
| 3 | 心跳机制？ | 临时5s心跳保活，15s超时不健康30s剔除；持久服务端TCP/HTTP探测 |
| 4 | 配置推送？ | 长轮询29.5s hold，变更立即返回 |
| 5 | 集群同步？ | Distro异步复制(AP)+Raft日志共识(CP) |
| 6 | 容灾机制？ | 本地缓存+磁盘snapshot+failover兜底 |
| 7 | Namespace作用？ | 环境隔离(dev/staging/prod) |
| 8 | Group作用？ | 同环境下的业务分组隔离 |
| 9 | 权重路由？ | Instance.weight → Ribbon/LoadBalancer权重选择 |
| 10 | Nacos vs Eureka？ | Nacos有CP+配置中心+权重+gRPC；Eureka只有AP+无配置 |
| 11 | 配置MD5作用？ | 快速比对是否变更，长轮询传MD5而非全量 |
| 12 | @RefreshScope？ | 配置变更→销毁Bean→下次访问重建(新配置) |
| 13 | 2.x改进？ | gRPC长连接替代UDP+HTTP；断连2s感知；性能提升 |
| 14 | 配置存储？ | MySQL config_info表+磁盘缓存+历史表his_config_info |
| 15 | 长轮询AsyncContext？ | Servlet3.0异步，请求hold在allSubs，变更时complete |

## Sentinel（15题）

| # | 问题 | 一句话答案 |
|---|------|----------|
| 16 | Slot顺序？ | NodeSelector→ClusterBuilder→Log→Statistic→Authority→System→Flow→Degrade |
| 17 | 滑动窗口？ | LeapArray 10个1s窗口AtomicReferenceArray+CAS |
| 18 | 三种流控？ | 直接拒绝+预热冷启动(WarmUp)+匀速排队(RateLimiter) |
| 19 | 三种熔断？ | 慢调用比例+异常比例+异常数 |
| 20 | 状态转换？ | CLOSED→OPEN→HALF_OPEN→CLOSED/OPEN |
| 21 | 预热算法？ | Guava SmoothWarmingUp, coldFactor=3, 初始QPS=count/3 |
| 22 | 匀速排队？ | 虚拟队列，sleep排队，超maxQueueingTimeMs拒绝 |
| 23 | 关联限流？ | 关联资源QPS超阈值→限流当前资源 |
| 24 | 链路限流？ | 只统计特定origin的QPS |
| 25 | 系统保护？ | Load/CPU/RT/Thread/入口QPS五维度 |
| 26 | 黑白名单？ | AuthoritySlot, origin匹配limitApp |
| 27 | 集群限流？ | TokenServer分配令牌，客户端请求令牌 |
| 28 | 持久化？ | NacosDataSource Push模式，Listener实时更新RuleManager |
| 29 | 统计节点体系？ | EntranceNode→DefaultNode→ClusterNode三层 |
| 30 | MetricBucket？ | LongAdder原子计数，PASS/BLOCK/EXCEPTION/SUCCESS/RT |

## Gateway（10题）

| # | 问题 | 一句话答案 |
|---|------|----------|
| 31 | 为什么WebFlux？ | Netty异步IO少量线程高并发，Servlet线程等IO浪费 |
| 32 | Filter执行？ | Order小→前置先→后置后；NettyRoutingFilter最后 |
| 33 | lb://URI？ | ReactiveLoadBalancerClientFilter→Nacos选实例→替换URI |
| 34 | 限流？ | Redis Lua令牌桶，KeyResolver决定维度 |
| 35 | 路由来源？ | Properties(yml)/InMemory/Nacos动态/Discovery自动发现 |
| 36 | Filter vs GlobalFilter？ | Filter路由级；Global全局级；合并排序执行 |
| 37 | Predicate体系？ | Path/Host/Method/Header/Cookie/Query/Weight等工厂 |
| 38 | 动态路由？ | NacosRouteDefinitionRepository→配置变更→实时更新Route |
| 39 | 前后置写法？ | 前置chain.filter()前；后置doOnSuccess/doOnError回调 |
| 40 | +Sentinel？ | SentinelGatewayFilter→entry→SlotChain→拦截429 |

## MyBatis（15题）

| # | 问题 | 一句话答案 |
|---|------|----------|
| 41 | 一二级缓存？ | 一级SqlSession级默认开不可关；二级Mapper级需手动开 |
| 42 | 一级失效？ | close/update/commit/rollback/clearCache |
| 43 | 二级序列化？ | 跨Session共享需序列化，否则引用混乱 |
| 44 | #{} vs ${}？ | #{}参数绑定防注入；${}字符串替换有风险 |
| 45 | MapperProxy？ | JDK动态代理→MapperMethod.execute→SqlSession操作 |
| 46 | 四大对象？ | Executor/StatementHandler/ParameterHandler/ResultSetHandler |
| 47 | Plugin.wrap？ | JDK动态代理→签名匹配→intercept→proceed递归 |
| 48 | Executor类型？ | Simple(每次新建)/Reuse(缓存Statement)/Batch(批量) |
| 49 | SqlSessionTemplate线程安全？ | 代理每次新SqlSession或用事务绑定的 |
| 50 | N+1问题？ | select嵌套查询每行子查询；解决用JOIN结果映射 |

---

> **全文完** | 共 4 大部分：Nacos 服务注册与发现 + 配置中心、Sentinel 流控熔断、Spring Cloud Gateway 响应式网关、MyBatis ORM 核心 | 附录 A 全链路图 + 附录 B 50 题速记