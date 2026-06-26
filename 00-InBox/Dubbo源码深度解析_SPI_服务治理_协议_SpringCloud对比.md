# Dubbo 源码深度解析

## ——SPI 机制 / 服务导出 / 服务引用 / 协议通信 / 集群容错 / 负载均衡 / 服务治理 / 与 Spring Cloud 对比

> **版本说明**：本文基于 Dubbo 2.7.x（主线分析）+ Dubbo 3.x（Triple 协议单独章节）源码进行深度解析。
>
> **前置阅读**：建议先阅读《Spring_IoC_DI源码深度解析》和《Spring_Cloud_MyBatis源码深度解析》，理解 Bean 生命周期和 Spring Cloud 生态后再来对比阅读 Dubbo。

---

## 目录

```
第一部分  Dubbo 整体架构与核心概念
  1.1  Dubbo 是什么
  1.2  核心角色
  1.3  分层架构（10 层）
  1.4  一次完整 RPC 调用的全链路
  1.5  Dubbo 3.x 新特性

第二部分  Dubbo SPI 机制（核心中的核心）
  2.1  Java SPI vs Dubbo SPI
  2.2  ExtensionLoader 核心数据结构
  2.3  getExtension() 完整流程
  2.4  自适应扩展 @Adaptive
  2.5  包装类扩展 Wrapper（AOP）
  2.6  @Activate 扩展（条件激活）
  2.7  ExtensionFactory IOC 注入
  2.8  SPI 缓存机制
  2.9  Dubbo SPI 与 Spring IoC 的关系

第三部分  服务导出（Export）源码
  3.1  ServiceBean 初始化与 Spring 衔接
  3.2  export() 入口
  3.3  doExport() → doExportUrls()
  3.4  本地暴露 vs 远程暴露
  3.5  DubboProtocol.export() — 打开 Server
  3.6  注册中心注册
  3.7  Exporter 架构

第四部分  服务引用（Refer）源码
  4.1  ReferenceBean 初始化
  4.2  createProxy() — 创建代理对象
  4.3  registryProtocol.refer() — 从注册中心订阅
  4.4  DubboProtocol.refer() — 创建客户端 Invoker
  4.5  Invoker 代理创建（JavassistProxyFactory）
  4.6  集群 Invoker 包装

第五部分  Dubbo 协议与网络通信
  5.1  Protocol 体系
  5.2  DubboProtocol.export()/refer()
  5.3  HeaderExchangeServer/Client
  5.4  NettyTransporter / NettyServer / NettyClient
  5.5  Codec2 编解码体系
  5.6  请求-响应模型（Request/Response）
  5.7  心跳机制

第六部分  集群容错
  6.1  Cluster 接口体系
  6.2  FailoverClusterInvoker（默认）
  6.3  FailfastClusterInvoker
  6.4  FailsafeClusterInvoker
  6.5  ForkingClusterInvoker
  6.6  BroadcastClusterInvoker
  6.7  AvailableCluster / MergeableCluster
  6.8  ClusterInvoker 整体流程

第七部分  负载均衡
  7.1  LoadBalance 接口体系
  7.2  RandomLoadBalance（默认加权随机）
  7.3  RoundRobinLoadBalance（平滑加权轮询）
  7.4  LeastActiveLoadBalance（最小活跃数）
  7.5  ConsistentHashLoadBalance（一致性哈希）
  7.6  ShortestResponseLoadBalance（Dubbo 2.7+）
  7.7  负载均衡器选择时机

第八部分  服务治理
  8.1  注册中心集成（ZookeeperRegistry）
  8.2  路由规则（Router / RouterChain）
  8.3  配置中心（ConfigurationUtils / DynamicConfiguration）
  8.4  元数据中心（MetadataReport）
  8.5  应用级服务发现（Dubbo 3.x）
  8.6  服务降级（mock 机制）

第九部分  Filter 责任链
  9.1  ProtocolFilterWrapper — Filter 链入口
  9.2  Filter 链构建过程
  9.3  内置 Filter 全解析
  9.4  自定义 Filter 实现原理
  9.5  ConsumerContextFilter / ContextFilter / ExceptionFilter

第十部分  异步调用与线程池模型
  10.1  Dispatcher 线程派发模型
  10.2  ThreadPool 线程池体系
  10.3  ThreadlessExecutor（Dubbo 2.7+）
  10.4  CompletableFuture 异步调用
  10.5  Dubbo 线程模型全景图

第十一部分  Dubbo 3.x Triple 协议
  11.1  Triple 协议概述
  11.2  基于 HTTP/2 和 gRPC
  11.3  Triple 流式调用
  11.4  Triple vs Dubbo 协议

第十二部分  Dubbo vs Spring Cloud 全面对比
  12.1  架构设计对比
  12.2  通信模型对比
  12.3  SPI 机制对比
  12.4  服务治理对比
  12.5  性能对比
  12.6  生态与社区对比
  12.7  选型建议

附录
  A. Dubbo 源码阅读路线图
  B. Dubbo 核心配置速查表
  C. Dubbo 面试高频问题汇总
```

---

## 第一部分 Dubbo 整体架构与核心概念

### 1.1 Dubbo 是什么

Dubbo 是阿里巴巴开源的高性能 Java RPC 框架，后捐献给 Apache 基金会，成为 Apache 顶级项目。

**核心能力：**

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Dubbo 核心能力                                │
├─────────────┬───────────────────────────────────────────────────────┤
│  面向接口代理  │  面向接口编程，透明调用远程方法，调用方式与本地一致           │
├─────────────┼───────────────────────────────────────────────────────┤
│  多协议支持   │  dubbo / triple / rest / grpc / hessian / thrift 等     │
├─────────────┼───────────────────────────────────────────────────────┤
│  服务治理    │  注册中心 / 负载均衡 / 集群容错 / 路由规则 / 配置中心         │
├─────────────┼───────────────────────────────────────────────────────┤
│  SPI 扩展    │  微内核 + SPI 插件化，所有组件都可替换                     │
├─────────────┼───────────────────────────────────────────────────────┤
│  高性能      │  Netty NIO + 自定义二进制协议 + 线程池隔离                  │
├─────────────┼───────────────────────────────────────────────────────┤
│  云原生     │  Dubbo 3.x 应用级服务发现 + Triple 协议 + Service Mesh     │
└─────────────┴───────────────────────────────────────────────────────┘
```

### 1.2 核心角色

```
                          ┌──────────────┐
                          │   Registry   │  注册中心（Zookeeper/Nacos）
                          │  (注册中心)    │
                          └──────┬───────┘
                    注册①  ↑     │     ② 订阅
                    ④ 变更  │     │     ③ 推送
                          │     ↓
    ┌──────────┐                              ┌──────────┐
    │ Provider │ ←──────── ⑤ RPC 调用 ────────│ Consumer │
    │ 服务提供者 │                              │ 服务消费者 │
    └────┬─────┘                              └────┬─────┘
         │                                         │
         │           ⑥ Monitor                     │
         │              ↓                          │
         └─────────→ ┌──────────┐ ←───────────────┘
                     │ Monitor  │  监控中心
                     │ (监控中心) │
                     └──────────┘
```

| 角色 | 说明 |
|------|------|
| **Provider** | 服务提供方，启动时向注册中心注册自己的地址和服务信息 |
| **Consumer** | 服务消费方，启动时从注册中心订阅所需服务，缓存到本地 |
| **Registry** | 注册中心，存储服务地址列表，变更时推送给消费者 |
| **Monitor** | 监控中心，统计服务的调用次数和调用耗时 |

**关键设计原则：**
- 注册中心、服务提供方、服务消费方之间均为**长连接**
- 注册中心宕机**不影响已运行的** Provider 和 Consumer（Consumer 本地缓存了服务列表）
- 监控中心宕机**不影响** RPC 调用，只是丢失统计数据
- 服务提供方宕机，注册中心通过**心跳检测**将其摘除，并推送给消费者

### 1.3 分层架构（10 层）

Dubbo 采用微内核 + 分层架构，全部 10 层之间单向依赖：

```
┌──────────────────────────────────────────────────────────────────┐
│                        business 业务层                            │
│              Service / 业务接口和实现                               │
├──────────────────────────────────────────────────────────────────┤
│                    config 配置层                                   │
│         ServiceConfig / ReferenceConfig / @Service                │
│    职责：解析配置，组装 ServiceBean / ReferenceBean                  │
├──────────────────────────────────────────────────────────────────┤
│                    proxy 代理层                                    │
│         JavassistProxyFactory / JdkProxyFactory                   │
│    职责：生成 Consumer 代理对象 / Provider Invoker 代理              │
├──────────────────────────────────────────────────────────────────┤
│                  registry 注册中心层                                │
│         ZookeeperRegistry / NacosRegistry / RegistryProtocol       │
│    职责：服务注册、服务发现、订阅推送                                 │
├──────────────────────────────────────────────────────────────────┤
│                   cluster 集群层                                   │
│     FailoverCluster / RouterChain / LoadBalance                   │
│    职责：多 Provider 的容错、路由、负载均衡                           │
├──────────────────────────────────────────────────────────────────┤
│                   monitor 监控层                                   │
│            MonitorFilter / DubboMonitor                            │
│    职责：调用统计上报                                                │
├──────────────────────────────────────────────────────────────────┤
│                   protocol 协议层                                   │
│         DubboProtocol / TripleProtocol / RestProtocol              │
│    职责：RPC 协议封装，服务暴露与引用                                 │
├──────────────────────────────────────────────────────────────────┤
│                  exchange 信息交换层                                │
│       HeaderExchangeServer / HeaderExchangeClient                  │
│    职责：封装请求-响应语义，心跳                                     │
├──────────────────────────────────────────────────────────────────┤
│                  transport 网络传输层                               │
│       NettyTransporter / NettyServer / NettyClient                 │
│    职责：抽象网络通信，Netty/Mina 实现                                │
├──────────────────────────────────────────────────────────────────┤
│                   serialize 序列化层                                │
│      Hessian2Serialization / KryoSerialization / Protobuf           │
│    职责：请求/响应数据的序列化与反序列化                               │
└──────────────────────────────────────────────────────────────────┘
```

**层间依赖规则：**
- 每一层**只能依赖**自己下面的层，不能反向依赖
- 序列化层是最底层，不依赖任何上层
- 业务层在最上面，可以调用所有下层能力
- 各层之间通过 **SPI 接口**解耦，实现可替换

### 1.4 一次完整 RPC 调用的全链路

从 Consumer 发起调用到 Provider 返回结果，**完整调用链路**如下：

```
Consumer 侧：
  ① proxy 层     ─→ UserService proxy.sayHello("zhang")
                       │
  ② cluster 层   ─→ MockClusterInvoker.invoke()
                       │
                 ─→ AbstractClusterInvoker.invoke()
                       │  路由过滤 + 负载均衡选 Provider
                       │
  ③ protocol 层   ─→ DubboInvoker.invoke()（filter 链）
                       │
                 ─→ ProtocolFilterWrapper.invoker()
                       │  ConsumerContextFilter → FutureFilter → Monitor → ...
                       │
  ④ exchange 层   ─→ HeaderExchangeClient.request()
                       │
  ⑤ transport 层  ─→ NettyClient.send()
                       │
  ⑥ serialize 层  ─→ Hessian2ObjectOutput.writeObject()
                       │
                   ════════ 网络传输 ════════
                       │
Provider 侧：
  ⑥ serialize 层  ─→ Hessian2ObjectInput.readObject()
                       │
  ⑤ transport 层  ─→ NettyServer.messageReceived()
                       │
  ④ exchange 层   ─→ HeaderExchangeHandler.received()
                       │  解码 → 线程派发
                       │
  ③ protocol 层   ─→ DubboProtocolExchangeHandler.reply()
                       │  filter 链
                       │
                 ─→ ContextFilter → ExceptionFilter → TimeoutFilter → ...
                       │
  ② proxy 层     ─→ AbstractProxyInvoker.invoke()
                       │
  ① business 层   ─→ UserServiceImpl.sayHello("zhang")
                       │  执行业务逻辑
                       │
                   ════════ 原路返回 ════════
                       │
Consumer 侧：        ← Response
  ⑤ transport 层  ─→ NettyClient.messageReceived()
  ④ exchange 层   ─→ HeaderExchangeClient 处理响应
  ③ protocol 层   ─→ DubboInvoker 设置 Future
  ② cluster 层    ─→ ClusterInvoker 返回结果
  ① proxy 层      ─→ proxy 返回 String "hello zhang"
```

**关键类对应关系：**

| 层 | Consumer 侧类 | Provider 侧类 |
|----|---------------|---------------|
| proxy | `InvokerInvocationHandler` | `AbstractProxyInvoker` |
| cluster | `MockClusterInvoker` / `FailoverClusterInvoker` | - |
| protocol | `DubboInvoker` | `DubboProtocol` + `ExchangeHandler` |
| exchange | `HeaderExchangeClient` | `HeaderExchangeServer` |
| transport | `NettyClient` | `NettyServer` |
| serialize | `Hessian2ObjectOutput` | `Hessian2ObjectInput` |

### 1.5 Dubbo 3.x 新特性

Dubbo 3.x 相对于 2.x 的主要变化：

```
┌────────────────────────────────────────────────────────────────────┐
│                      Dubbo 3.x 核心新特性                            │
├────────────────┬───────────────────────────────────────────────────┤
│ 应用级服务发现   │ 从「接口级」升级到「应用级」，注册数据量大幅减少          │
│                │ 与 Spring Cloud / Kubernetes 服务发现模型对齐           │
├────────────────┼───────────────────────────────────────────────────┤
│ Triple 协议    │ 基于 HTTP/2 + gRPC，兼容 gRPC 生态                     │
│                │ 支持 Stream 流式调用，支持浏览器/移动端直接调用            │
├────────────────┼───────────────────────────────────────────────────┤
│ Service Mesh   │ 支持 sidecar 模式，与 Istio 等服务网格集成               │
├────────────────┼───────────────────────────────────────────────────┤
│ 云原生         │ 原生 Kubernetes 部署支持，容器化适配                     │
├────────────────┼───────────────────────────────────────────────────┤
│ 编程模型扩展    │ 支持 Reactive / 响应式编程                             │
└────────────────┴───────────────────────────────────────────────────┘
```

> **Dubbo 2.x vs 3.x 服务注册对比：**
> - 2.x：每个接口注册一条数据，N 个接口 = N 条注册数据
> - 3.x：每个应用注册一条数据，N 个接口 = 1 条应用数据 + 接口映射

---

## 第二部分 Dubbo SPI 机制（核心中的核心）

> **Dubbo SPI 是整个 Dubbo 框架的灵魂。** 所有核心组件（Protocol、Transporter、Serialization、LoadBalance、Cluster 等）都通过 SPI 加载。理解了 SPI，就理解了 Dubbo 的骨架。

### 2.1 Java SPI vs Dubbo SPI

#### 2.1.1 Java SPI 简介

Java SPI（Service Provider Interface）是 JDK 内置的服务发现机制：

```
配置文件位置：META-INF/services/接口全限定名
配置文件内容：每行一个实现类全限定名
```

```java
// ServiceLoader 核心方法
public final class ServiceLoader<S> implements Iterable<S> {
    // 加载所有实现
    public static <S> ServiceLoader<S> load(Class<S> service) {
        // 从 META-INF/services/ 加载
    }
}
```

**Java SPI 的问题：**
1. **一次性加载所有实现**，无法按需获取某一个
2. **无法依赖注入**，实现类之间的依赖需要自己 new
3. **没有缓存**，每次 load 都重新创建
4. **没有自适应**，无法根据运行时参数动态选择实现

#### 2.1.2 Dubbo SPI 的优势

Dubbo SPI 对 Java SPI 的增强：

```
┌──────────────┬──────────────────────────┬─────────────────────────────┐
│     特性      │       Java SPI            │       Dubbo SPI              │
├──────────────┼──────────────────────────┼─────────────────────────────┤
│ 按需加载      │ 一次性加载所有              │ 按需加载指定 name 的实现        │
│ IOC 注入     │ 不支持                    │ 支持，通过 ExtensionFactory     │
│ AOP 包装     │ 不支持                    │ 支持 Wrapper 自动包装           │
│ 自适应扩展    │ 不支持                    │ 支持 @Adaptive 动态选择          │
│ 条件激活      │ 不支持                    │ 支持 @Activate 条件激活          │
│ 缓存          │ 无                       │ 多级缓存                      │
│ 配置文件      │ META-INF/services/        │ META-INF/dubbo/               │
│              │                          │ META-INF/dubbo/internal/       │
│              │                          │ META-INF/dubbo/external/       │
└──────────────┴──────────────────────────┴─────────────────────────────┘
```

**配置文件格式对比：**

```
# Java SPI：每行一个全限定类名
com.example.MyImpl1
com.example.MyImpl2

# Dubbo SPI：key=value 格式
impl1=com.example.MyImpl1
impl2=com.example.MyImpl2
```

### 2.2 ExtensionLoader 核心数据结构

`ExtensionLoader` 是 Dubbo SPI 的核心类，每个 SPI 接口对应一个 `ExtensionLoader` 实例。

```java
public class ExtensionLoader<T> {

    // ========== 静态缓存：接口 → ExtensionLoader ==========
    // key: SPI 接口的 Class, value: 对应的 ExtensionLoader
    private static final ConcurrentMap<Class<?>, ExtensionLoader<?>> EXTENSION_LOADERS
        = new ConcurrentHashMap<>();

    // ========== 静态缓存：实现类 Class → 实例 ==========
    // key: 实现类的 Class, value: 实现类实例（单例）
    private static final ConcurrentMap<Class<?>, Object> EXTENSION_INSTANCES
        = new ConcurrentHashMap<>();

    // ========== 实例字段 ==========

    // 当前 ExtensionLoader 负责的 SPI 接口类型
    private final Class<?> type;

    // ExtensionFactory，用于 IOC 注入
    private final ExtensionFactory objectFactory;

    // ========== 扩展类缓存 ==========

    // 配置文件中 name → Class 的映射（类型缓存）
    private final Holder<Map<String, Class<?>>> cachedClasses = new Holder<>();

    // name → 扩展实例的缓存
    private final ConcurrentMap<String, Holder<Object>> cachedInstances
        = new ConcurrentHashMap<>();

    // @Adaptive 扩展实例缓存
    private final Holder<Object> cachedAdaptiveInstance = new Holder<>();

    // @Adaptive 标注的 Class 缓存（代码生成的代理类）
    private volatile Class<?> cachedAdaptiveClass = null;

    // @Adaptive 注解标注的方法
    private Method[] cachedAdaptiveMethod;

    // 包装类（Wrapper）Class 列表
    private Set<Class<?>> cachedWrapperClasses;

    // 扩展名缓存：Class → name
    private final ConcurrentMap<Class<?>, String> cachedNames = new ConcurrentHashMap<>();

    // @Activate 扩展：name → Activate 注解信息
    private final Map<String, Object> cachedActivates = new ConcurrentHashMap<>();

    // 默认扩展名（@SPI 注解的 value）
    private String cachedDefaultName;

    // 异常缓存
    private Map<String, IllegalStateException> exceptions = new ConcurrentHashMap<>();
}
```

**Holder 类**是一个简单的持有者，用 volatile 保证可见性：

```java
public class Holder<T> {
    private volatile T value;

    public T get() { return value; }
    public void set(T value) { this.value = value; }
}
```

> **设计意图**：`Holder` 用 volatile + double-check 模式实现懒加载，避免了直接用 ConcurrentHashMap 的 value 还需要原子创建的问题。

### 2.3 getExtension() 完整流程

`getExtension(String name)` 是 Dubbo SPI 最核心的入口方法：

```java
public T getExtension(String name) {
    if (StringUtils.isEmpty(name)) {
        throw new IllegalArgumentException("Extension name == null");
    }
    // ① 获取默认扩展
    if ("true".equals(name)) {
        return getDefaultExtension();
    }
    // ② 从缓存中获取 Holder
    final Holder<Object> holder = getOrCreateHolder(name);
    Object instance = holder.get();
    if (instance == null) {
        synchronized (holder) {
            instance = holder.get();
            if (instance == null) {
                // ③ 创建扩展实例
                instance = createExtension(name);
                holder.set(instance);
            }
        }
    }
    return (T) instance;
}
```

**createExtension() — 扩展实例的创建过程：**

```java
private T createExtension(String name) {
    // ① 加载所有扩展类，获取指定 name 的 Class
    Class<?> clazz = getExtensionClasses().get(name);
    if (clazz == null) {
        throw findException(name);
    }
    try {
        // ② 从实例缓存中获取，没有则反射创建
        T instance = (T) EXTENSION_INSTANCES.get(clazz);
        if (instance == null) {
            EXTENSION_INSTANCES.putIfAbsent(clazz, clazz.newInstance());
            instance = (T) EXTENSION_INSTANCES.get(clazz);
        }

        // ③ IOC 依赖注入
        injectExtension(instance);

        // ④ Wrapper 包装（AOP）
        Set<Class<?>> wrapperClasses = cachedWrapperClasses;
        if (CollectionUtils.isNotEmpty(wrapperClasses)) {
            for (Class<?> wrapperClass : wrapperClasses) {
                // 每个 Wrapper 都创建新实例，注入原实例，再做 IOC
                instance = injectExtension(
                    (T) wrapperClass.getConstructor(type).newInstance(instance)
                );
            }
        }

        // ⑤ 初始化回调（Lifecycle）
        initExtension(instance);

        return instance;
    } catch (Throwable t) {
        throw new IllegalStateException("...");
    }
}
```

**核心流程图：**

```
getExtension("dubbo")
    │
    ├── ① cachedInstances 缓存命中？ ──→ 直接返回
    │         │ 否
    │         ▼
    ├── ② getExtensionClasses() 加载配置文件
    │         │
    │    ┌────┴────────────────────────────────┐
    │    │ loadDirectory(META-INF/dubbo/internal/)│
    │    │ loadDirectory(META-INF/dubbo/)          │
    │    │ loadDirectory(META-INF/dubbo/external/) │
    │    │ loadDirectory(META-INF/services/)       │ ← 兼容 Java SPI
    │    └────┬────────────────────────────────┘
    │         │ 解析 key=value
    │         ▼
    │    cachedClasses = {dubbo: DubboProtocol.class, ...}
    │
    ├── ③ 反射创建实例（clazz.newInstance()）
    │
    ├── ④ injectExtension() — IOC 注入
    │         │
    │    遍历所有 setter 方法
    │    如果参数类型是 SPI 接口 → getAdaptiveExtension() 注入
    │
    ├── ⑤ Wrapper 包装（AOP）
    │         │
    │    如果构造函数有唯一参数 = type → 认为是 Wrapper
    │    循环包装：原实例 → Wrapper1(原实例) → Wrapper2(Wrapper1(...))
    │
    └── ⑥ 返回最终实例
```

#### 2.3.1 getExtensionClasses() — 配置文件加载

```java
private Map<String, Class<?>> getExtensionClasses() {
    // 双重检查锁
    Map<String, Class<?>> classes = cachedClasses.get();
    if (classes == null) {
        synchronized (cachedClasses) {
            classes = cachedClasses.get();
            if (classes == null) {
                classes = loadExtensionClasses();  // 加载
                cachedClasses.set(classes);
            }
        }
    }
    return classes;
}

public Map<String, Class<?>> loadExtensionClasses() {
    // ① 缓存默认扩展名（@SPI 注解的 value）
    cacheDefaultExtensionName();

    Map<String, Class<?>> extensionClasses = new HashMap<>();

    // ② 从四个目录加载配置文件
    //    Dubbo 内部扩展：META-INF/dubbo/internal/
    //    用户自定义扩展：META-INF/dubbo/
    //    兼容旧版：      META-INF/dubbo/external/
    //    兼容 Java SPI： META-INF/services/
    loadDirectory(extensionClasses, DUBBO_INTERNAL_DIRECTORY, type.getName());
    loadDirectory(extensionClasses, DUBBO_INTERNAL_DIRECTORY,
                  type.getName().replace("org.apache", "com.alibaba")); // 兼容旧包名
    loadDirectory(extensionClasses, DUBBO_DIRECTORY, type.getName());
    loadDirectory(extensionClasses, DUBBO_DIRECTORY,
                  type.getName().replace("org.apache", "com.alibaba"));
    loadDirectory(extensionClasses, SERVICES_DIRECTORY, type.getName());
    loadDirectory(extensionClasses, SERVICES_DIRECTORY,
                  type.getName().replace("org.apache", "com.alibaba"));

    return extensionClasses;
}
```

**loadDirectory() — 读取配置文件并解析：**

```java
private void loadDirectory(Map<String, Class<?>> extensionClasses, String dir, String type) {
    // ① 拼接文件路径：META-INF/dubbo/internal/org.apache.dubbo.rpc.Protocol
    String fileName = dir + type;
    try {
        Enumeration<URL> urls;
        ClassLoader classLoader = findClassLoader();
        urls = classLoader.getResources(fileName);
        if (urls != null) {
            while (urls.hasMoreElements()) {
                URL resourceUrl = urls.nextElement();
                // ② 读取并解析每个配置文件
                loadResource(extensionClasses, classLoader, resourceUrl);
            }
        }
    } catch (Throwable t) {
        logger.error("...");
    }
}

private void loadResource(Map<String, Class<?>> extensionClasses,
                          ClassLoader classLoader, URL resourceURL) {
    try {
        BufferedReader reader = new BufferedReader(
            new InputStreamReader(resourceURL.openStream(), UTF_8));
        String line;
        while ((line = reader.readLine()) != null) {
            // ① 去掉注释
            final int commentIndex = line.indexOf('#');
            if (commentIndex >= 0) {
                line = line.substring(0, commentIndex);
            }
            line = line.trim();
            if (line.length() > 0) {
                try {
                    String name = null;
                    int i = line.indexOf('=');
                    if (i > 0) {
                        // ② 解析 key=value
                        name = line.substring(0, i).trim();
                        line = line.substring(i + 1).trim();
                    }
                    if (line.length() > 0) {
                        // ③ 加载 Class
                        Class<?> clazz = Class.forName(line, true, classLoader);
                        // ④ 判断是普通扩展、Wrapper、还是 @Adaptive
                        if (!isWrapperClass(clazz)) {
                            // 普通扩展：检查 @Adaptive 和 @Activate
                            clazz.getAnnotation(Adaptive.class);
                            // 存入 extensionClasses
                            extensionClasses.put(name, clazz);
                        } else {
                            // Wrapper：存入 cachedWrapperClasses
                            cachedWrapperClasses.add(clazz);
                        }
                    }
                } catch (Throwable t) {
                    // ...
                }
            }
        }
    } catch (Throwable t) {
        // ...
    }
}
```

**Dubbo Protocol 的 SPI 配置文件**（`META-INF/dubbo/internal/org.apache.dubbo.rpc.Protocol`）：

```properties
# 协议实现
filter=org.apache.dubbo.rpc.protocol.ProtocolFilterWrapper
listener=org.apache.dubbo.rpc.protocol.ProtocolListenerWrapper
mock=org.apache.dubbo.rpc.support.MockProtocol
dubbo=org.apache.dubbo.rpc.protocol.dubbo.DubboProtocol
injvm=org.apache.dubbo.rpc.protocol.injvm.InjvmProtocol
rest=org.apache.dubbo.rpc.protocol.rest.RestProtocol
grpc=org.apache.dubbo.rpc.protocol.grpc.GrpcProtocol
tri=org.apache.dubbo.rpc.protocol.tri.TripleProtocol
```

其中 `filter` 和 `listener` 是 **Wrapper 类**（构造函数接收 Protocol 参数），会被放入 `cachedWrapperClasses`。

### 2.4 自适应扩展 @Adaptive

> **@Adaptive 是 Dubbo SPI 最精妙的设计**，它允许在运行时根据 URL 参数动态选择 SPI 实现。

#### 2.4.1 为什么需要自适应扩展

考虑这个场景：

```java
// Protocol 接口有多个实现：dubbo、rest、grpc、tri...
@SPI("dubbo")
public interface Protocol {
    <T> Exporter<T> export(Invoker<T> invoker) throws RpcException;
    <T> Invoker<T> refer(Class<T> type, URL url) throws RpcException;
}

// 在 RegistryProtocol 中需要使用 Protocol，但不知道用户配了哪个协议
// 这时候就需要「自适应扩展」
```

如果不使用自适应扩展，代码就要这样写：

```java
// 硬编码判断 —— 不好
if (url.getProtocol().equals("dubbo")) {
    new DubboProtocol().export(invoker);
} else if (url.getProtocol().equals("rest")) {
    new RestProtocol().export(invoker);
}
```

使用自适应扩展后：

```java
// Protocol$Adaptive 在运行时动态生成，根据 URL 中的 protocol 参数选择
Protocol adaptiveProtocol = ExtensionLoader.getExtensionLoader(Protocol.class)
    .getAdaptiveExtension();
adaptiveProtocol.export(invoker);  // 自动根据 URL 选择 DubboProtocol 或 RestProtocol
```

#### 2.4.2 @Adaptive 注解的使用方式

**方式一：标注在方法上**（生成动态代理类）

```java
@SPI("dubbo")
public interface Protocol {
    @Adaptive  // 标注在方法上 → 生成代码动态选择
    <T> Exporter<T> export(Invoker<T> invoker) throws RpcException;

    @Adaptive
    <T> Invoker<T> refer(Class<T> type, URL url) throws RpcException;

    int getDefaultPort();  // 没有标注 → 不会生成动态逻辑
}
```

**方式二：标注在类上**（手动实现的固定自适应类）

```java
@Adaptive
public class AdaptiveExtensionFactory implements ExtensionFactory {
    // 不生成代码，自己实现选择逻辑
}
```

#### 2.4.3 getAdaptiveExtension() 流程

```java
public T getAdaptiveExtension() {
    Object instance = cachedAdaptiveInstance.get();
    if (instance == null) {
        if (createAdaptiveInstanceError == null) {
            synchronized (cachedAdaptiveInstance) {
                instance = cachedAdaptiveInstance.get();
                if (instance == null) {
                    try {
                        // 创建自适应扩展实例
                        instance = createAdaptiveExtension();
                        cachedAdaptiveInstance.set(instance);
                    } catch (Throwable t) {
                        createAdaptiveInstanceError = t;
                        throw new IllegalStateException("...");
                    }
                }
            }
        }
    }
    return (T) instance;
}

private T createAdaptiveExtension() {
    try {
        // ① 获取自适应扩展类 → 实例化 → IOC 注入
        T instance = (T) getAdaptiveExtensionClass().newInstance();
        injectExtension(instance);
        return instance;
    } catch (Exception e) {
        // ...
    }
}

private Class<?> getAdaptiveExtensionClass() {
    // ① 先加载所有扩展类（触发配置文件解析）
    getExtensionClasses();
    // ② 如果有类上标注 @Adaptive，直接用
    if (cachedAdaptiveClass != null) {
        return cachedAdaptiveClass;
    }
    // ③ 没有手动实现的，动态生成代码
    return cachedAdaptiveClass = createAdaptiveExtensionClass();
}
```

#### 2.4.4 createAdaptiveExtensionClass() — 动态代码生成

这是 Dubbo SPI 最核心的代码生成逻辑，使用 **Javassist** 动态生成代理类：

```java
private Class<?> createAdaptiveExtensionClass() {
    // ① 生成 Java 源码
    String code = new AdaptiveClassCodeGenerator(type, cachedDefaultName).generate();
    // ② 编译
    ClassLoader classLoader = findClassLoader();
    org.apache.dubbo.common.compiler.Compiler compiler =
        ExtensionLoader.getExtensionLoader(org.apache.dubbo.common.compiler.Compiler.class)
            .getAdaptiveExtension();
    return compiler.compile(code, classLoader);
}
```

**AdaptiveClassCodeGenerator.generate() 生成的代码**以 Protocol 接口为例，实际生成的代码大致如下：

```java
package org.apache.dubbo.rpc;

import org.apache.dubbo.common.extension.ExtensionLoader;

public class Protocol$Adaptive implements org.apache.dubbo.rpc.Protocol {

    public org.apache.dubbo.rpc.Exporter export(
            org.apache.dubbo.rpc.Invoker arg0)
            throws org.apache.dubbo.rpc.RpcException {
        if (arg0 == null) {
            throw new IllegalArgumentException("org.apache.dubbo.rpc.Invoker argument == null");
        }
        if (arg0.getUrl() == null) {
            throw new IllegalArgumentException(
                "org.apache.dubbo.rpc.Invoker argument getUrl() == null");
        }
        // ① 从 URL 中获取 protocol 参数，没有则用默认值 "dubbo"
        org.apache.dubbo.common.URL url = arg0.getUrl();
        String extName = (url.getProtocol() == null ? "dubbo" : url.getProtocol());
        if (extName == null) {
            throw new IllegalStateException(
                "Failed to get extension ...");
        }
        // ② 根据扩展名获取实现
        org.apache.dubbo.rpc.Protocol extension =
            ExtensionLoader.getExtensionLoader(org.apache.dubbo.rpc.Protocol.class)
                .getExtension(extName);
        // ③ 调用实现的 export 方法
        return extension.export(arg0);
    }

    public org.apache.dubbo.rpc.Invoker refer(
            java.lang.Class arg0, org.apache.dubbo.common.URL arg1)
            throws org.apache.dubbo.rpc.RpcException {
        if (arg0 == null) {
            throw new IllegalArgumentException("...");
        }
        if (arg1 == null) {
            throw new IllegalArgumentException("...");
        }
        org.apache.dubbo.common.URL url = arg1;
        String extName = (url.getProtocol() == null ? "dubbo" : url.getProtocol());
        if (extName == null) {
            throw new IllegalStateException("...");
        }
        org.apache.dubbo.rpc.Protocol extension =
            ExtensionLoader.getExtensionLoader(org.apache.dubbo.rpc.Protocol.class)
                .getExtension(extName);
        return extension.refer(arg0, arg1);
    }

    public int getDefaultPort() {
        // 没有 @Adaptive 注解，抛异常
        throw new UnsupportedOperationException(
            "The method public abstract int getDefaultPort() of interface ... " +
            "is not adaptive method!");
    }
}
```

**代码生成的核心逻辑：**

```java
// AdaptiveClassCodeGenerator 核心方法
private String generate() {
    // ① 检查是否有 @Adaptive 方法
    if (!hasAdaptiveMethod()) {
        throw new IllegalStateException("No adaptive method exist on extension " + type.getName());
    }

    StringBuilder code = new StringBuilder();
    // ② 生成包名、import、类签名
    code.append(generatePackageInfo());
    code.append(generateImports());
    code.append(generateClassSignature());

    // ③ 为每个方法生成自适应代码
    Method[] methods = type.getMethods();
    for (Method method : methods) {
        code.append(generateMethod(method));
    }
    code.append("}");

    return code.toString();
}

private String generateMethod(Method method) {
    // ① 方法签名
    // ② 参数非空校验
    // ③ 从 URL 中提取扩展名
    //    - 根据方法参数找到 URL 类型参数
    //    - 根据方法名推断 URL 的 key（如 export 方法 → protocol 参数）
    //    - @Adaptive 注解的 value 指定 key
    // ④ getExtension(extName) 获取实现
    // ⑤ 调用实现方法
}
```

**扩展名从 URL 中的哪个 key 获取？**

```java
// @Adaptive 注解可以指定从 URL 的哪个参数获取扩展名
@Adaptive({"protocol", "transporter"})  // 先找 protocol，没有再找 transporter
```

如果没指定，则根据方法名推断：

| 方法名 | URL key |
|--------|---------|
| `export` | `protocol` |
| `refer` | `protocol` |
| `connect` | `client` |
| `bind` | `server` |

#### 2.4.5 自适应扩展执行流程

```
调用 Protocol$Adaptive.export(invoker)
              │
              ├── ① 从 invoker.getUrl() 获取 protocol 参数
              │       url = dubbo://192.168.1.10:20880/com.example.UserService
              │       extName = "dubbo"
              │
              ├── ② ExtensionLoader.getExtensionLoader(Protocol.class)
              │       .getExtension("dubbo")
              │
              │       ┌── cachedInstances 缓存命中？──→ 返回
              │       │       否
              │       │   createExtension("dubbo")
              │       │       ├── DubboProtocol 实例
              │       │       ├── IOC 注入
              │       │       └── Wrapper 包装：
              │       │           DubboProtocol
              │       │             → ProtocolFilterWrapper(DubboProtocol)
              │       │               → ProtocolListenerWrapper(ProtocolFilterWrapper(...))
              │       │
              │       ▼
              └── ③ 返回包装后的 Protocol 实例
                      调用 ProtocolListenerWrapper.export(invoker)
                          → ProtocolFilterWrapper.export(invoker)
                              → DubboProtocol.export(invoker)
```

### 2.5 包装类扩展 Wrapper（AOP）

Wrapper 是 Dubbo SPI 实现 **AOP** 的机制。当一个扩展类的构造函数**有且只有一个参数，且参数类型就是 SPI 接口本身**时，它被识别为 Wrapper。

#### 2.5.1 Wrapper 的识别

```java
// ProtocolFilterWrapper 是一个 Wrapper
public class ProtocolFilterWrapper implements Protocol {
    // 构造函数参数是 Protocol —— 这就是 Wrapper 的标志
    private final Protocol protocol;

    public ProtocolFilterWrapper(Protocol protocol) {
        this.protocol = protocol;
    }

    @Override
    public <T> Exporter<T> export(Invoker<T> invoker) {
        // 前置逻辑：构建 Filter 链
        if (UrlUtils.isRegistry(invoker.getUrl())) {
            return protocol.export(invoker);  // 注册中心协议不做 Filter 处理
        }
        // 为 Invoker 添加 Filter 链
        Invoker<T> invokerChain = buildInvokerChain(invoker, ...);
        // 委托给被包装的 Protocol
        return protocol.export(invokerChain);
    }

    @Override
    public <T> Invoker<T> refer(Class<T> type, URL url) {
        // 前置逻辑
        Invoker<T> invoker = protocol.refer(type, url);
        // 构建 Filter 链
        return buildInvokerChain(invoker, ...);
    }
}
```

#### 2.5.2 isWrapperClass() 判断

```java
private boolean isWrapperClass(Class<?> clazz) {
    try {
        // 获取构造函数，参数类型是否为 type（即 SPI 接口本身）
        clazz.getConstructor(type);
        return true;
    } catch (NoSuchMethodException e) {
        return false;
    }
}
```

#### 2.5.3 Wrapper 包装顺序

在 `createExtension()` 中：

```java
// 遍历所有 Wrapper 类，依次包装
Set<Class<?>> wrapperClasses = cachedWrapperClasses;
if (CollectionUtils.isNotEmpty(wrapperClasses)) {
    for (Class<?> wrapperClass : wrapperClasses) {
        instance = injectExtension(
            (T) wrapperClass.getConstructor(type).newInstance(instance)
        );
    }
}
```

**包装过程示例：**

```
原始实例：DubboProtocol

第1次包装（ProtocolFilterWrapper）：
    ProtocolFilterWrapper(DubboProtocol)

第2次包装（ProtocolListenerWrapper）：
    ProtocolListenerWrapper(ProtocolFilterWrapper(DubboProtocol))

最终结构：
    ProtocolListenerWrapper
        └── ProtocolFilterWrapper
                └── DubboProtocol
```

调用时**从外到内**：

```
ProtocolListenerWrapper.export()
    → ProtocolFilterWrapper.export()    ← 构建 Filter 链
        → DubboProtocol.export()         ← 真正的服务暴露
```

> **这就是 Dubbo 的 AOP**：Wrapper 拦截对核心实现的调用，在前后插入切面逻辑（如 Filter 链构建、监听器通知等），与 Spring AOP 的拦截器链思想完全一致。

### 2.6 @Activate 扩展（条件激活）

@Activate 用于**条件激活**扩展，主要用在 Filter 扩展上——根据条件（如 group、value）自动激活一组扩展。

#### 2.6.1 @Activate 注解定义

```java
@Documented
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.TYPE, ElementType.METHOD})
public @interface Activate {
    // 组过滤：provider 或 consumer
    String[] group() default {};

    // Key 过滤：URL 中包含这些 key 时激活
    String[] value() default {};

    // 排序，数组越小优先级越高
    int order() default 0;

    // 在 SPI 配置加载后立即触发加载
    boolean onLoad() default false;
}
```

#### 2.6.2 Filter 上的 @Activate 示例

```java
// Consumer 侧自动激活，URL 中有 mock 参数时激活
@Activate(group = CONSUMER, value = MOCK_KEY)
public class MockClusterInvoker implements Cluster { ... }

// Provider 和 Consumer 都激活
@Activate(group = {PROVIDER, CONSUMER})
public class ContextFilter implements Filter { ... }

// Consumer 侧激活，order=-100000 保证最先执行
@Activate(group = CONSUMER, order = -100000)
public class ConsumerContextFilter implements Filter { ... }

// Provider 侧激活，用于异常处理
@Activate(group = PROVIDER, order = -1000)
public class ExceptionFilter implements Filter { ... }

// Provider 侧激活，用于超时检查
@Activate(group = PROVIDER, value = TIMEOUT_KEY)
public class TimeoutFilter implements Filter { ... }
```

#### 2.6.3 getActivateExtension() — 条件激活逻辑

```java
public List<T> getActivateExtension(URL url, String[] values, String group) {
    // ① 加载所有扩展类
    Map<String, Class<?>> classes = getExtensionClasses();

    // ② cachedActivates 是 name → @Activate 注解信息的缓存
    //    遍历所有带 @Activate 注解的扩展
    for (Map.Entry<String, Object> entry : cachedActivates.entrySet()) {
        String name = entry.getKey();
        Activate activate = (Activate) entry.getValue();

        // ③ 检查 group 条件
        if (isMatchGroup(group, activate.group())) {
            // ④ 检查 key 条件（URL 中是否包含指定参数）
            //    如果 @Activate 没有 value，则无条件匹配
            //    如果有 value，URL 中需要包含对应的 key
            if (StringUtils.isEmpty(activate.value())) {
                // 无条件匹配
                activateExtensions.put(name, getExtension(name));
            } else {
                for (String key : activate.value()) {
                    if (url.hasParameter(key)) {
                        // URL 中有对应参数，激活
                        activateExtensions.put(name, getExtension(name));
                        break;
                    }
                }
            }
        }
    }

    // ⑤ 处理用户手动指定的扩展（values 参数）
    if (!StringUtils.isEmpty(values)) {
        // 用户指定的优先级最高，放到最后执行
    }

    // ⑥ 按 @Activate 的 order 排序
    List<T> exts = new ArrayList<>(activateExtensions.values());
    sort(exts);

    return exts;
}
```

**条件匹配流程：**

```
getActivateExtension(url, values=null, group="consumer")
    │
    ├── ① 遍历所有带 @Activate 的扩展
    │       ├── ConsumerContextFilter: group=consumer, order=-100000 → 匹配 ✓
    │       ├── ContextFilter:        group=provider,consumer         → 匹配 ✓
    │       ├── ExceptionFilter:      group=provider                  → 不匹配 ✗
    │       ├── TimeoutFilter:        group=provider                  → 不匹配 ✗
    │       └── MonitorFilter:        group=consumer                  → 匹配 ✓
    │
    ├── ② 如果 values 非空，加入用户手动指定的 Filter
    │
    └── ③ 按 order 排序
            ConsumerContextFilter(-100000) → ContextFilter → MonitorFilter
```

### 2.7 ExtensionFactory IOC 注入

Dubbo SPI 支持**依赖注入**，当一个扩展类的 setter 方法参数类型是另一个 SPI 接口时，会自动注入对应的自适应扩展。

#### 2.7.1 injectExtension() 源码

```java
private T injectExtension(T instance) {
    try {
        if (objectFactory == null) {
            return instance;
        }
        // 遍历所有方法
        for (Method method : instance.getClass().getMethods()) {
            // ① 只处理 setter 方法（以 "set" 开头，参数个数为 1，返回 void）
            if (!isSetter(method)) {
                continue;
            }
            // ② 检查是否有 @DisableInject 注解（禁止注入）
            if (method.getAnnotation(DisableInject.class) != null) {
                continue;
            }
            // ③ 获取参数类型
            Class<?> pt = method.getParameterTypes()[0];
            // 基本类型和 String 不注入
            if (ReflectUtils.isPrimitives(pt)) {
                continue;
            }

            try {
                // ④ 从方法名提取属性名：setProtocol → protocol
                String property = getSetterProperty(method);
                // ⑤ 通过 ExtensionFactory 获取依赖
                Object object = objectFactory.getExtension(pt, property);
                if (object != null) {
                    // ⑥ 反射调用 setter 注入
                    method.invoke(instance, object);
                }
            } catch (Exception e) {
                logger.error("...");
            }
        }
    } catch (Exception e) {
        logger.error("...");
    }
    return instance;
}
```

#### 2.7.2 ExtensionFactory 体系

```
ExtensionFactory（SPI 接口）
    │
    ├── SpiExtensionFactory — 从 Dubbo SPI 获取
    │   getExtension(Protocol.class, "protocol")
    │       → ExtensionLoader.getExtensionLoader(Protocol.class)
    │           .getAdaptiveExtension()
    │
    ├── SpringExtensionFactory — 从 Spring 容器获取
    │   getExtension(MyService.class, "myService")
    │       → applicationContext.getBean("myService", MyService.class)
    │
    └── AdaptiveExtensionFactory — 自适应（组合 Spi + Spring）
        @Adaptive
        public class AdaptiveExtensionFactory implements ExtensionFactory {
            private final List<ExtensionFactory> factories;

            public AdaptiveExtensionFactory() {
                ExtensionLoader<ExtensionFactory> loader =
                    ExtensionLoader.getExtensionLoader(ExtensionFactory.class);
                Set<String> names = loader.getSupportedExtensions();
                factories = new ArrayList<>();
                for (String name : names) {
                    factories.add(loader.getExtension(name));
                }
            }

            @Override
            public <T> T getExtension(Class<T> type, String name) {
                // 遍历所有 ExtensionFactory，第一个返回非 null 的结果
                for (ExtensionFactory factory : factories) {
                    T extension = factory.getExtension(type, name);
                    if (extension != null) {
                        return extension;
                    }
                }
                return null;
            }
        }
```

> **设计亮点**：`AdaptiveExtensionFactory` 是唯一一个在**类上**标注 `@Adaptive` 的扩展。它不需要动态生成代码，因为它需要组合所有 `ExtensionFactory` 实现，而不是根据 URL 参数动态选择。

#### 2.7.3 IOC 注入示例

```java
// RegistryProtocol 中有 setter 方法
public class RegistryProtocol implements Protocol {
    private Protocol protocol;  // 需要注入

    // setter 方法 —— Dubbo SPI 会自动注入
    public void setProtocol(Protocol protocol) {
        this.protocol = protocol;
    }

    // Cluster 也需要注入
    private Cluster cluster;

    public void setCluster(Cluster cluster) {
        this.cluster = cluster;
    }
}
```

当 `createExtension("registry")` 创建 `RegistryProtocol` 时：

```
① new RegistryProtocol()
② injectExtension(instance):
    遍历 setter 方法:
        setProtocol(Protocol) → objectFactory.getExtension(Protocol.class, "protocol")
                              → SpiExtensionFactory → Protocol$Adaptive（自适应扩展）
        setCluster(Cluster)   → objectFactory.getExtension(Cluster.class, "cluster")
                              → SpiExtensionFactory → Cluster$Adaptive（自适应扩展）
③ Wrapper 包装...
```

### 2.8 SPI 缓存机制

Dubbo SPI 有多层缓存，避免重复加载：

```
┌─────────────────────────────────────────────────────────────────┐
│                    Dubbo SPI 多级缓存体系                          │
├──────────────────────┬──────────────────────────────────────────┤
│  缓存名               │  作用                                     │
├──────────────────────┼──────────────────────────────────────────┤
│  EXTENSION_LOADERS   │  接口 Class → ExtensionLoader（全局静态）   │
│  EXTENSION_INSTANCES │  实现类 Class → 实例（全局静态，单例）        │
│  cachedClasses       │  name → Class（每个 ExtensionLoader 独有）  │
│  cachedInstances     │  name → Holder<实例>（每个 ExtensionLoader）│
│  cachedAdaptiveClass │  @Adaptive 代理类 Class                   │
│  cachedAdaptiveInstance │ @Adaptive 代理类实例                   │
│  cachedWrapperClasses│  Wrapper Class 集合                       │
│  cachedActivates     │  name → @Activate 注解信息                 │
│  cachedNames         │  Class → name（反向映射）                  │
└──────────────────────┴──────────────────────────────────────────┘
```

**缓存生命周期：**

```
首次调用 getExtension("dubbo"):
    ① ExtensionLoader.getExtensionLoader(Protocol.class)
       → EXTENSION_LOADERS 没有就 new ExtensionLoader 存入

    ② loader.getExtension("dubbo")
       → cachedInstances 没有就 createExtension()

    ③ createExtension():
       → getExtensionClasses() → cachedClasses 没有 → loadExtensionClasses()
       → EXTENSION_INSTANCES 没有 → new DubboProtocol()
       → injectExtension() 注入
       → Wrapper 包装
       → cachedInstances.set(instance)

后续调用 getExtension("dubbo"):
    → cachedInstances 直接命中，返回缓存实例
```

### 2.9 Dubbo SPI 与 Spring IoC 的关系

| 维度 | Dubbo SPI | Spring IoC |
|------|-----------|------------|
| **容器** | ExtensionLoader | ApplicationContext |
| **注册** | META-INF/dubbo/ 配置文件 | @Component / XML / @Bean |
| **获取** | `getExtension("name")` | `getBean("name")` |
| **注入** | setter + ExtensionFactory | @Autowired / @Resource |
| **AOP** | Wrapper 包装类 | BeanPostProcessor + 动态代理 |
| **作用域** | 单例 | singleton/prototype/request/... |
| **扩展来源** | Dubbo SPI + Spring 容器 | Spring 容器 |
| **自适应** | @Adaptive 动态选择 | 无 |

> **关键区别**：Spring IoC 的 Bean 定义在编译时就确定了，而 Dubbo SPI 的 @Adaptive 可以在运行时根据 URL 参数动态切换实现。这是 RPC 框架的核心需求——同一个接口在不同场景下用不同的协议实现。

---

## 第三部分 服务导出（Export）源码

> 服务导出是 Provider 侧的核心流程：将服务接口暴露出去，让 Consumer 可以远程调用。

### 3.1 ServiceBean 初始化与 Spring 衔接

Dubbo 与 Spring 的衔接点是 `ServiceBean`，它实现了 `InitializingBean` 和 `ApplicationListener`：

```java
public class ServiceBean<T> extends ServiceConfig<T>
        implements InitializingBean, DisposableBean,
        ApplicationContextAware, ApplicationListener<ContextRefreshedEvent>,
        BeanNameAware {

    @Override
    @SuppressWarnings({"unchecked", "deprecation"})
    public void afterPropertiesSet() throws Exception {
        // ① 如果配置了 provider，设置 provider
        if (getProvider() == null) {
            // 从 Spring 容器中查找 ProviderConfig
            Map<String, ProviderConfig> providerConfigMap =
                applicationContext == null ? null :
                BeanFactoryUtils.beansOfTypeIncludingAncestors(
                    applicationContext, ProviderConfig.class, false, false);
            // ...
        }

        // ② 设置 Protocol、Registry 等配置
        // ...

        // ③ 如果没有配置 delay 或 delay <= 0，等 Spring 容器刷新完成后再导出
        //    否则立即导出
        if (!shouldDelay()) {
            export();  // ← 核心入口
        }
    }

    @Override
    public void onApplicationEvent(ContextRefreshedEvent event) {
        // Spring 容器刷新完成事件 → 延迟导出的服务在这里触发
        if (!isExported() && !isUnexported()) {
            if (logger.isInfoEnabled()) {
                logger.info("The service ready on spring started. service: " + getInterface());
            }
            export();  // ← 延迟导出的入口
        }
    }
}
```

**`@Service` 注解的扫描：**

```java
// Dubbo 的 @Service 注解（不是 Spring 的）
@Documented
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.TYPE})
public @interface Service {
    Class<?> interfaceClass() default void.class;
    String interfaceName() default "";
    String version() default "";
    String group() default "";
    // ... 其他配置
}

// ServiceClassPostProcessor 处理 @Service 注解
public class ServiceClassPostProcessor implements BeanDefinitionRegistryPostProcessor {
    @Override
    public void postProcessBeanDefinitionRegistry(BeanDefinitionRegistry registry) {
        // ① 扫描 @Service 注解的类
        // ② 注册为 ServiceBean 的 BeanDefinition
        // ③ Spring 创建 ServiceBean 实例时触发 export()
    }
}
```

### 3.2 export() 入口

```java
// ServiceConfig.export()
public synchronized void export() {
    // ① 检查是否应该导出
    if (!shouldExport()) {
        return;
    }

    // ② 如果没有配置延迟，立即导出
    if (shouldDelay()) {
        // 延迟导出 —— 启动一个定时任务
        delayExportExecutor.schedule(this::doExport, getDelay(), TimeUnit.MILLISECONDS);
    } else {
        // 立即导出
        doExport();
    }

    // ③ 导出后处理（如注册到 ServiceConfigurationListener）
    exported();
}
```

### 3.3 doExport() → doExportUrls()

```java
protected synchronized void doExport() {
    // ① 检查配置合法性
    if (unexported) {
        throw new IllegalStateException("Already unexported!");
    }
    if (exported) {
        return;
    }
    exported = true;

    // ② 初始化路径（接口全限定名 + group + version）
    if (StringUtils.isEmpty(path)) {
        path = interfaceName;
    }
    // ③ 执行导出
    doExportUrls();
}

private void doExportUrls() {
    // ① 加载所有注册中心 URL
    List<URL> registryURLs = ConfigValidationUtils.loadRegistries(this, true);

    // ② 遍历所有协议，对每个协议在每个注册中心都导出一次
    for (ProtocolConfig protocolConfig : protocols) {
        String pathKey = URL.buildKey(getContextPath(protocolConfig)
                .map(p -> p + "/" + path).orElse(path), group, version);
        // 保存到 ProviderModel
        Repository repository = ApplicationModel.getRepository();
        ProviderModel providerModel = new ProviderModel(pathKey, ref, interfaceClass);
        repository.registerProvider(providerModel);

        // ③ 对每个注册中心执行导出
        for (URL registryURL : registryURLs) {
            doExportUrlsFor1Protocol(protocolConfig, registryURL);
        }
    }
}
```

### 3.4 本地暴露 vs 远程暴露

```java
private void doExportUrlsFor1Protocol(ProtocolConfig protocolConfig, URL registryURL) {
    // ① 构建 Service URL
    //    dubbo://192.168.1.10:20880/com.example.UserService?version=1.0.0&...
    URL url = buildServiceUrl(protocolConfig, registryURL);

    // ② 生成 Invoker（将服务实现包装为 Invoker）
    Invoker<?> invoker = proxyFactory.getInvoker(ref, (Class) interfaceClass, url);

    // ③ 包装为 DelegateProviderMetaDataInvoker
    DelegateProviderMetaDataInvoker wrapperInvoker =
        new DelegateProviderMetaDataInvoker(invoker, providerModel);

    // ④ 导出！
    Exporter<?> exporter = protocolSPI.export(wrapperInvoker);

    // ⑤ 保存 Exporter
    exporters.add(exporter);
}
```

**核心：`protocolSPI.export(wrapperInvoker)`** 这一行触发了整个导出链路。由于 `protocolSPI` 是自适应扩展，实际执行的是：

```
Protocol$Adaptive.export(invoker)
    │  URL: registry://zookeeper://127.0.0.1:2181/...
    │  extName = "registry"
    │
    ▼
RegistryProtocol.export(invoker)   ← 被 Wrapper 包装
    │  ProtocolFilterWrapper(RegistryProtocol)
    │  ProtocolListenerWrapper(ProtocolFilterWrapper(RegistryProtocol))
    │
    ▼  先经过 Filter Wrapper 和 Listener Wrapper
    │
    │  ProtocolFilterWrapper.export():
    │    如果是 registry 协议，直接放行（registry 不做 Filter）
    │    如果是 dubbo 协议，构建 Filter 链后再 export
    │
    ▼
RegistryProtocol.doLocalExport(invoker)  ← 核心导出逻辑
    │
    │  将 registry:// 转换为 dubbo:// 协议
    │  registry://zookeeper:2181/... → dubbo://192.168.1.10:20880/...
    │
    ▼
Protocol$Adaptive.export(invoker)  ← 再次自适应，这次 extName="dubbo"
    │
    ▼
DubboProtocol.export(invoker)
    │
    ├── ① 打开 Server（如果还没有打开）
    │      openServer(url)
    │          → createServer(url)
    │              → Exchangers.bind(url, requestHandler)
    │                  → HeaderExchanger.bind()
    │                      → new HeaderExchangeServer(Transporters.bind(url, handler))
    │                          → NettyTransporter.bind()
    │                              → new NettyServer(url, handler)
    │                                  → doOpen() → 启动 Netty BossEventLoop
    │
    ├── ② 将 Invoker 注册到 exporterMap
    │      key = serviceKey: com.example.UserService:1.0.0:20880
    │      value = DubboExporter(invoker)
    │
    └── ③ 返回 DubboExporter
```

### 3.5 RegistryProtocol.export() — 完整源码

```java
public <T> Exporter<T> export(Invoker<T> originInvoker) throws RpcException {
    // ① 获取注册中心 URL
    //    zookeeper://127.0.0.1:2181/org.apache.dubbo.registry.RegistryService
    URL registryUrl = getRegistryUrl(originInvoker);

    // ② 获取要注册的 Provider URL
    //    dubbo://192.168.1.10:20880/com.example.UserService?...
    URL providerUrl = getProviderUrl(originInvoker);

    // ③ 获取覆盖配置 URL（动态配置覆盖）
    final URL overrideSubscribeUrl = getSubscribedOverrideUrl(providerUrl);
    final OverrideListener overrideSubscribeListener =
        new OverrideListener(overrideSubscribeUrl, originInvoker);

    // ④ 注册到注册中心
    //    先做本地导出（打开 Netty Server）
    final ExporterChangeableWrapper<T> exporter =
        doLocalExport(originInvoker, providerUrl);

    // ⑤ 连接注册中心
    final Registry registry = getRegistry(originInvoker);

    // ⑥ 注册 Provider URL 到注册中心
    //    Zookeeper: 创建 /dubbo/com.example.UserService/providers/dubbo%3A%2F%2F... 节点（临时节点）
    registry.register(providerUrl);

    // ⑦ 订阅配置覆盖
    registry.subscribe(overrideSubscribeUrl, overrideSubscribeListener);

    // ⑧ 通知 Exporter
    notifyExport(providerUrl);

    // ⑨ 创建并返回 DestroyableExporter
    return new DestroyableExporter<>(exporter);
}
```

#### 3.5.1 doLocalExport() — 本地导出

```java
private <T> ExporterChangeableWrapper<T> doLocalExport(
        final Invoker<T> originInvoker, URL providerUrl) {
    String key = getCacheKey(originInvoker);

    // 从缓存获取
    ExporterChangeableWrapper<T> exporter =
        (ExporterChangeableWrapper<T>) bounds.get(key);
    if (exporter == null) {
        synchronized (bounds) {
            exporter = (ExporterChangeableWrapper<T>) bounds.get(key);
            if (exporter == null) {
                // ① 创建代理 Invoker
                final Invoker<?> invokerDelegate =
                    new InvokerDelegate<>(originInvoker, providerUrl);

                // ② 调用 DubboProtocol.export()
                //    protocol 是自适应扩展，根据 providerUrl 的 protocol 选择
                Exporter<T> exporterDelegate =
                    protocol.export(invokerDelegate);

                // ③ 包装为 ChangeableWrapper
                exporter = new ExporterChangeableWrapper<>(
                    exporterDelegate, originInvoker);
                bounds.put(key, exporter);
            }
        }
    }
    return exporter;
}
```

#### 3.5.2 DubboProtocol.export() — 打开 Server

```java
public <T> Exporter<T> export(Invoker<T> invoker) throws RpcException {
    URL url = invoker.getUrl();

    // ① 生成 service key：group/interface:version:port
    //    如：com.example.UserService:1.0.0:20880
    String key = serviceKey(url);

    // ② 创建 DubboExporter，放入 exporterMap
    DubboExporter<T> exporter = new DubboExporter<T>(invoker, key, exporterMap);
    exporterMap.put(key, exporter);

    // ③ 存储_stub 类
    //export an stub service for dispatching event
    Boolean isStubSupportEvent = url.getParameter(STUB_EVENT_KEY, DEFAULT_STUB_EVENT);
    // ...

    // ④ 打开 Server
    openServer(url);

    // ⑤ 优化序列化
    optimizeSerialization(url);

    return exporter;
}

private void openServer(URL url) {
    // key = ip:port
    String key = url.getAddress();

    // ① 检查是否已有 Server
    ExchangeServer server = serverMap.get(key);
    if (server == null) {
        synchronized (this) {
            server = serverMap.get(key);
            if (server == null) {
                // ② 创建 Server
                serverMap.put(key, createServer(url));
            }
        }
    } else {
        // ③ Server 已存在，重置配置
        server.reset(url);
    }
}

private ExchangeServer createServer(URL url) {
    // ① 设置默认参数
    url = URLBuilder.from(url)
        .addParameterIfAbsent(CHANNEL_READONLYEVENT_SENT_KEY, Boolean.TRUE.toString())
        .addParameterIfAbsent(CODEC_KEY, DubboCodec.NAME)
        .addParameterIfAbsent(HEARTBEAT_KEY, String.valueOf(DEFAULT_HEARTBEAT))
        .build();

    // ② 获取 Server 实现（默认 netty）
    String str = url.getParameter(SERVER_KEY, DEFAULT_REMOTING_SERVER);

    // ③ 通过 Exchange 层创建 Server
    ExchangeServer server;
    try {
        server = Exchangers.bind(url, requestHandler);
    } catch (RemotingException e) {
        throw new RpcException("Fail to start server...");
    }
    return server;
}
```

### 3.6 注册中心注册

以 Zookeeper 为例：

```java
// ZookeeperRegistry.register()
public void doRegister(URL url) {
    try {
        // ① 创建 Zookeeper 节点
        //    路径：/dubbo/com.example.UserService/providers/dubbo%3A%2F%2F192.168.1.10%3A20880%2Fcom.example.UserService
        //    节点类型：临时节点（EPHEMERAL）
        zkClient.create(toUrlPath(url), url.getParameter(DYNAMIC_KEY, true));
    } catch (Throwable e) {
        // ② 重试
        throw new RpcException("Failed to register " + url + " to zookeeper " + getUrl()
            + ", cause: " + e.getMessage(), e);
    }
}
```

**Zookeeper 节点结构：**

```
/dubbo                              ← 根节点
  └── com.example.UserService        ← 接口名
       ├── providers                  ← 提供者目录
       │    └── dubbo://192.168.1.10:20880/com.example.UserService?version=1.0.0
       │         （临时节点，Provider 宕机自动删除）
       ├── consumers                  ← 消费者目录
       │    └── consumer://192.168.1.20/com.example.UserService?version=1.0.0
       │         （临时节点）
       ├── routers                    ← 路由规则目录
       │    └── condition://...       （持久节点）
       ├── configurators              ← 配置覆盖目录
       │    └── override://...        （持久节点）
       └── metadatas                  ← 元数据目录（Dubbo 3.x）
            └── ...
```

### 3.7 Exporter 架构

```
Exporter 体系：
    Exporter<T>（接口）
        │
        ├── AbstractExporter<T>
        │   ├── DubboExporter<T>          ← DubboProtocol 导出的
        │   ├── InjvmExporter<T>          ← InjvmProtocol 导出的（本地调用）
        │   └── RestExporter<T>           ← RestProtocol 导出的
        │
        ├── ExporterChangeableWrapper<T>  ← RegistryProtocol 包装
        │   └── 持有原始 Invoker 和 delegate Exporter
        │
        └── DestroyableExporter<T>        ← 最外层，支持优雅关闭
            └── 持有 ExporterChangeableWrapper
```

**DubboExporter 的 getInvoker() — 请求处理时获取 Invoker：**

```java
public class DubboExporter<T> extends AbstractExporter<T> {
    private final String key;      // service key
    private final Map<String, Exporter<?>> exporterMap;

    @Override
    public Invoker<T> getInvoker() {
        return super.getInvoker();
    }

    // 静态方法：根据 key 从 map 中获取 Exporter
    public static <T> Exporter<T> getExporter(
            Map<String, Exporter<?>> exporterMap, String key) {
        Exporter<?> exporter = exporterMap.get(key);
        // ... 兼容处理
        return (Exporter<T>) exporter;
    }
}
```

**完整的 Export 流程图：**

```
ServiceBean.afterPropertiesSet()
    │
    ├── ServiceConfig.export()
    │       │
    │       └── doExport()
    │               │
    │               └── doExportUrls()
    │                       │
    │                       └── doExportUrlsFor1Protocol()
    │                               │
    │                               ├── proxyFactory.getInvoker(ref, interfaceClass, url)
    │                               │   → 创建 AbstractProxyInvoker（包装服务实现）
    │                               │
    │                               └── protocolSPI.export(invoker)
    │                                       │
    │                               ┌───────┴───────────────────────────┐
    │                               │ Protocol$Adaptive.export()          │
    │                               │   extName = "registry"              │
    │                               └───────┬───────────────────────────┘
    │                                       │
    │                               ┌───────┴───────────────────────────┐
    │                               │ ProtocolListenerWrapper.export()    │
    │                               │   → 无 Listener，直接放行             │
    │                               └───────┬───────────────────────────┘
    │                                       │
    │                               ┌───────┴───────────────────────────┐
    │                               │ ProtocolFilterWrapper.export()      │
    │                               │   → registry 协议，直接放行           │
    │                               └───────┬───────────────────────────┘
    │                                       │
    │                               ┌───────┴───────────────────────────┐
    │                               │ RegistryProtocol.export()           │
    │                               └───────┬───────────────────────────┘
    │                                       │
    │                               ┌───────┴───────────────────────────┐
    │                               │ doLocalExport(invoker)              │
    │                               │   → protocol.export(invokerDelegate)│
    │                               │     extName = "dubbo"              │
    │                               └───────┬───────────────────────────┘
    │                                       │
    │                               ┌───────┴───────────────────────────┐
    │                               │ ProtocolFilterWrapper.export()      │
    │                               │   → dubbo 协议，构建 Filter 链        │
    │                               │     invoker → Filter1 → Filter2     │
    │                               └───────┬───────────────────────────┘
    │                                       │
    │                               ┌───────┴───────────────────────────┐
    │                               │ DubboProtocol.export()              │
    │                               │   → exporterMap.put(key, exporter) │
    │                               │   → openServer(url)                 │
    │                               │       → createServer(url)          │
    │                               │           → Exchangers.bind()      │
    │                               │               → NettyTransporter    │
    │                               │                   → new NettyServer│
    │                               │                       → doOpen()   │
    │                               │                           Netty 启动│
    │                               └───────────────────────────────────┘
    │
    └── registry.register(providerUrl)
            → ZookeeperRegistry.doRegister()
                → zkClient.create(path, EPHEMERAL)
                    → 创建临时节点
```

---

## 第四部分 服务引用（Refer）源码

> 服务引用是 Consumer 侧的核心流程：从注册中心订阅服务，创建代理对象供业务代码调用。

### 4.1 ReferenceBean 初始化

```java
public class ReferenceBean<T> extends ReferenceConfig<T>
        implements FactoryBean, ApplicationContextAware, InitializingBean, DisposableBean {

    @Override
    @SuppressWarnings("unchecked")
    public T getObject() {
        // FactoryBean.getObject() → 获取代理对象
        return get();
    }

    @Override
    public void afterPropertiesSet() throws Exception {
        // ① 检查配置
        // ② 如果是单例且 init=true，立即引用
        if (shouldInit()) {
            get();  // ← 触发引用创建
        }
    }
}
```

**`@DubboReference` 注解的注入：**

```java
// DubboReferenceAnnotationBeanPostProcessor 处理 @DubboReference 注解
// 类似 Spring 的 @Autowired
public class DubboReferenceAnnotationBeanPostProcessor
        extends AnnotationInjectedBeanPostProcessor {

    // 扫描 @DubboReference 注解的字段/方法
    // 创建 ReferenceBean → getObject() → 代理对象
    // 注入到 Bean 的字段中
}
```

### 4.2 createProxy() — 创建代理对象

```java
// ReferenceConfig.get() → init() → createProxy()

private T createProxy(Map<String, String> map) {
    // ① 判断是否为本地引用（injvm）
    if (shouldJvmRefer(map)) {
        URL url = new URL(LOCAL_PROTOCOL, LOCALHOST_VALUE, 0,
            interfaceClass.getName()).addParameters(map);
        invoker = protocolSPI.refer(interfaceClass, url);
    } else {
        // ② 远程引用：遍历注册中心 URL
        urls.clear();
        // ②.a 直连模式（点对点）
        if (url != null && url.length() > 0) {
            // user specified URL
            String[] us = SEMICOLON_SPLIT_PATTERN.split(url);
            for (String u : us) {
                URL url = URL.valueOf(u);
                urls.add(url);
            }
        }
        // ②.b 注册中心模式
        if (urls.isEmpty()) {
            // 从注册中心引用
            List<URL> us = ConfigValidationUtils.loadRegistries(this, false);
            for (URL u : us) {
                URL monitorUrl = ...;
                u = u.addParameterAndEncoded(REFER_KEY, ...);
                urls.add(u);
            }
        }

        // ③ 对每个 URL 创建 Invoker
        if (urls.size() == 1) {
            // 单注册中心
            invoker = protocolSPI.refer(interfaceClass, urls.get(0));
        } else {
            // 多注册中心：每个 URL 创建 Invoker，然后用 ZoneAwareCluster 包装
            List<Invoker<?>> invokers = new ArrayList<>();
            for (URL url : urls) {
                invokers.add(protocolSPI.refer(interfaceClass, url));
            }
            // ZoneAwareCluster 聚合多个注册中心的 Invoker
            invoker = CLUSTER.join(new StaticDirectory<>(invokers));
        }
    }

    // ④ 创建代理对象
    // （T）proxyFactory.getProxy(refer(invoker))
    // invoker 可能被 MockClusterWrapper 包装
    return (T) PROXY_FACTORY.getProxy(invoker);
}
```

### 4.3 registryProtocol.refer() — 从注册中心订阅

```
protocolSPI.refer(interfaceClass, registryUrl)
    │  URL: registry://zookeeper://127.0.0.1:2181/...
    │  extName = "registry"
    │
    ▼
Protocol$Adaptive.refer()
    → ProtocolListenerWrapper.refer()    ← Wrapper
    → ProtocolFilterWrapper.refer()      ← Wrapper（构建 Consumer Filter 链）
    → RegistryProtocol.refer()           ← 实际执行
```

**RegistryProtocol.refer() 源码：**

```java
public <T> Invoker<T> refer(Class<T> type, URL url) throws RpcException {
    // ① 从 registry:// URL 中提取真正的注册中心 URL
    url = getRegistryUrl(url);

    // ② 获取注册中心实例
    Registry registry = registryFactory.getRegistry(url);

    // ③ 检查是否为普通服务
    if (RegistryService.class.equals(type)) {
        return proxyFactory.getInvoker((T) registry, type, url);
    }

    // ④ 将 group、version 等参数转换为查询条件
    Map<String, String> qs = StringUtils.parseQueryString(
        url.getParameterAndDecoded(REFER_KEY));

    // ⑤ 创建 RegistryDirectory（动态目录，负责订阅和通知）
    RegistryDirectory<T> directory =
        new RegistryDirectory<T>(type, url);

    // ⑥ 设置注册中心和协议
    directory.setRegistry(registry);
    directory.setProtocol(protocolSPI);

    // ⑦ 注册 Consumer 到注册中心
    if (!ANY_VALUE.equals(qs.get(CONSUMER_SIDE_KEY))) {
        // 注册消费者 URL（创建 /dubbo/.../consumers/... 临时节点）
        registry.subscribe(
            url.addParameters(CATEGORY_KEY, CONSUMERS_CATEGORY,
                CHECK_KEY, String.valueOf(false)), directory);
    }

    // ⑧ 订阅 Provider、Configuration、Router 变更
    directory.subscribe(toSubscribeUrl(url));

    // ⑨ 创建 Cluster Invoker（带容错和负载均衡）
    Invoker<T> invoker = cluster.join(directory);

    // ⑩ 返回 invoker
    return invoker;
}
```

#### 4.3.1 RegistryDirectory — 动态服务目录

`RegistryDirectory` 是 Consumer 侧的核心组件，它实现了 `NotifyListener`，监听注册中心的变更：

```java
public class RegistryDirectory<T> extends AbstractDirectory<T>
        implements NotifyListener {

    // 最新的 Invoker 列表（从注册中心推送的 Provider 列表）
    private volatile Map<URL, Invoker<T>> urlInvokerMap;

    @Override
    public synchronized void notify(List<URL> urls) {
        // ① 分类 URL：providers / configurators / routers
        Map<String, List<URL>> categoryUrls = urls.stream()
            .collect(Collectors.groupingBy(this::getCategory));

        // ② 处理 configurators（配置覆盖）
        List<URL> configuratorUrls = categoryUrls.get(CONFIGURATORS_CATEGORY);
        this.configurators = toConfigurators(configuratorUrls);

        // ③ 处理 routers（路由规则）
        List<URL> routerUrls = categoryUrls.get(ROUTERS_CATEGORY);
        this.routers = toRouters(routerUrls);

        // ④ 处理 providers（服务提供者列表）
        List<URL> providerUrls = categoryUrls.get(PROVIDERS_CATEGORY);
        // 刷新 Invoker 列表
        refreshOverrideAndInvoker(providerUrls);
    }

    private void refreshInvoker(List<URL> invokerUrls) {
        // ① 如果 URL 列表为空，销毁所有 Invoker
        if (invokerUrls.isEmpty()) {
            this.forbidden = true;
            this.invokers = Collections.emptyList();
            destroyAllInvokers();
            return;
        }

        // ② 遍历 URL，创建/更新 Invoker
        Map<URL, Invoker<T>> newUrlInvokerMap = new HashMap<>();
        for (URL providerUrl : invokerUrls) {
            // 如果 URL 是 empty 协议，表示没有 Provider
            if (EMPTY_PROTOCOL.equals(providerUrl.getProtocol())) {
                continue;
            }
            // 处理 override 配置
            URL url = mergeUrl(providerUrl);
            // 从缓存获取或创建新 Invoker
            Invoker<T> invoker = urlInvokerMap.get(url);
            if (invoker == null) {
                // 创建新 Invoker
                invoker = new InvokerDelegate<>(protocol.refer(serviceType, url), url);
                newUrlInvokerMap.put(url, invoker);
            } else {
                newUrlInvokerMap.put(url, invoker);
            }
        }

        // ③ 关闭不再使用的 Invoker
        destroyUnusedInvokers(oldUrlInvokerMap, newUrlInvokerMap);

        // ④ 更新引用
        this.urlInvokerMap = newUrlInvokerMap;
    }
}
```

**RegistryDirectory 工作流程：**

```
注册中心通知 Provider 列表变更
    │
    ├── notify(urls)
    │       │
    │       ├── 分类：providers / configurators / routers
    │       │
    │       └── refreshInvoker(providerUrls)
    │               │
    │               ├── 遍历 providerUrls
    │               │   ├── 新增 Provider → protocol.refer() 创建 DubboInvoker
    │               │   ├── 已有 Provider → 复用缓存
    │               │   └── 删除 Provider → destroy Invoker
    │               │
    │               └── 更新 urlInvokerMap
    │
    └── 后续调用时
            directory.list(invocation)
                → 从 urlInvokerMap 获取 Invoker 列表
                → 经过 RouterChain 过滤
                → 返回可用的 Invoker 列表
```

### 4.4 DubboProtocol.refer() — 创建客户端 Invoker

```java
public <T> Invoker<T> refer(Class<T> serviceType, URL url) throws RpcException {
    optimizeSerialization(url);

    // ① 创建 DubboInvoker
    DubboInvoker<T> invoker = new DubboInvoker<T>(serviceType, url, getClients(url), invokers);

    // ② 加入 invokers 集合
    invokers.add(invoker);

    return invoker;
}

private ExchangeClient[] getClients(URL url) {
    // 是否使用共享连接
    boolean useShareConnect = false;
    int connections = url.getParameter(CONNECTIONS_KEY, 0);
    List<ReferenceCountExchangeClient> shareClients = null;

    if (connections == 0) {
        // 默认使用共享连接
        useShareConnect = true;
        String shareConnectionsStr = url.getParameter(SHARE_CONNECTIONS_KEY, DEFAULT_SHARE_CONNECTIONS);
        connections = Integer.parseInt(shareConnectionsStr);
        shareClients = getSharedClient(url, connections);
    }

    ExchangeClient[] clients = new ExchangeClient[connections];
    for (int i = 0; i < clients.length; i++) {
        if (useShareConnect) {
            // 共享连接
            clients[i] = shareClients.get(i);
        } else {
            // 独立连接
            clients[i] = initClient(url);
        }
    }
    return clients;
}

private ExchangeClient initClient(URL url) {
    // ① 获取客户端类型（默认 netty）
    String str = url.getParameter(CLIENT_KEY, url.getParameter(SERVER_KEY, DEFAULT_REMOTING_CLIENT));

    // ② 设置编解码器和心跳
    url = url.addParameter(CODEC_KEY, DubboCodec.NAME);
    url = url.addParameterIfAbsent(HEARTBEAT_KEY, String.valueOf(DEFAULT_HEARTBEAT));

    // ③ 创建连接（懒惰连接 or 立即连接）
    ExchangeClient client;
    try {
        if (url.getParameter(LAZY_CONNECT_KEY, false)) {
            // 懒连接：第一次调用时才真正建立连接
            client = new LazyConnectExchangeClient(url, requestHandler);
        } else {
            // 立即连接
            client = Exchangers.connect(url, requestHandler);
        }
    } catch (RemotingException e) {
        throw new RpcException("Fail to create remoting client for service...");
    }
    return client;
}
```

### 4.5 DubboInvoker — 远程调用执行

```java
public class DubboInvoker<T> extends AbstractInvoker<T> {

    private final ExchangeClient[] clients;
    private final AtomicPositiveInteger index = new AtomicPositiveInteger();

    @Override
    protected Result doInvoke(final Invocation invocation) throws Throwable {
        RpcInvocation inv = (RpcInvocation) invocation;
        final String methodName = RpcUtils.getMethodName(invocation);
        boolean isOneway = RpcUtils.isOneway(inv);
        int timeout = RpcUtils.getTimeout(inv);

        // 选择一个 Client（轮询）
        ExchangeClient currentClient;
        if (clients.length == 1) {
            currentClient = clients[0];
        } else {
            currentClient = clients[index.getAndIncrement() % clients.length];
        }

        try {
            if (isOneway) {
                // ① 单向调用（不等待响应）
                boolean isSent = getUrl().getMethodParameter(methodName, Constants.SENT_KEY, false);
                currentClient.send(inv, isSent);
                return AsyncRpcResult.newDefaultAsyncResult(invocation);
            } else {
                // ② 同步调用（等待响应）
                // 使用 CompletableFuture
                CompletableFuture<Object> responseFuture =
                    currentClient.request(inv, timeout);
                // 获取结果
                AsyncRpcResult asyncRpcResult = new AsyncRpcResult(
                    asyncResultCompleter, inv);
                asyncRpcResult.subscribeTo(responseFuture);
                return asyncRpcResult;
            }
        } catch (TimeoutException e) {
            throw new RpcException(...);
        } catch (RemotingException e) {
            throw new RpcException(...);
        }
    }
}
```

### 4.6 Invoker 代理创建

最终通过 `ProxyFactory` 创建代理对象：

```java
// JavassistProxyFactory.getProxy()
public <T> T getProxy(Invoker<T> invoker) throws RpcException {
    // 获取接口列表
    Class<?>[] interfaces = ...;
    // 使用 Javassist 生成代理类
    return (T) Proxy.getProxy(interfaces).newInstance(
        new InvokerInvocationHandler(invoker));
}
```

**InvokerInvocationHandler — 代理调用处理器：**

```java
public class InvokerInvocationHandler implements InvocationHandler {
    private final Invoker<?> invoker;

    public InvokerInvocationHandler(Invoker<?> handler) {
        this.invoker = handler;
    }

    @Override
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        // ① Object 方法直接本地调用
        if (method.getDeclaringClass() == Object.class) {
            return method.invoke(invoker, args);
        }

        // ② 特殊方法处理
        String methodName = method.getName();
        Class<?>[] parameterTypes = method.getParameterTypes();
        if (parameterTypes.length == 0) {
            if ("toString".equals(methodName)) {
                return invoker.toString();
            } else if ("hashCode".equals(methodName)) {
                return invoker.hashCode();
            }
        } else if (parameterTypes.length == 1 && "equals".equals(methodName)) {
            return invoker.equals(args[0]);
        }

        // ③ 构建 RpcInvocation，发起远程调用
        RpcInvocation rpcInvocation = new RpcInvocation(
            method, invoker.getInterface().getName(), protocolServiceKey,
            args, invoker.getUrl().getOrDefaultRpcModel());

        // ④ 调用 Invoker 链
        //    MockClusterInvoker → AbstractClusterInvoker → DubboInvoker → ...
        return invoker.invoke(rpcInvocation).recreate();
    }
}
```

**Consumer 代理调用全链路：**

```
userService.sayHello("zhang")
    │  ← 代理对象
    │
    ├── InvokerInvocationHandler.invoke()
    │       │  构建 RpcInvocation
    │       │
    │       └── invoker.invoke(rpcInvocation)
    │               │
    │               ▼  invoker = MockClusterInvoker
    │
    ├── MockClusterInvoker.invoke()
    │       │  检查是否需要 mock
    │       │
    │       └── AbstractClusterInvoker.invoke()
    │               │
    │               ├── ① 路由过滤：RouterChain.route()
    │               │       从 urlInvokerMap 中过滤出符合条件的 Invoker
    │               │
    │               ├── ② 负载均衡：select()
    │               │       LoadBalance.select(invokers, url, invocation)
    │               │       从列表中选一个 Invoker
    │               │
    │               └── ③ 容错执行：doInvoke()
    │                       │
    │                       ▼  FailoverClusterInvoker.doInvoke()
    │
    ├── FailoverClusterInvoker.doInvoke()
    │       │  重试逻辑
    │       │
    │       └── invoker.invoke(invocation)  ← 选中的 DubboInvoker
    │               │
    │               ▼
    │
    ├── Filter 链执行
    │       ConsumerContextFilter → FutureFilter → MonitorFilter → ...
    │       │
    │       └── DubboInvoker.doInvoke()
    │               │
    │               ├── currentClient.request(inv, timeout)
    │               │       │
    │               │       └── HeaderExchangeClient.request()
    │               │               │
    │               │               └── channel.request()
    │               │                       │
    │               │                       └── NettyChannel.send()
    │               │                               │
    │               │                               └── 序列化 + 网络发送
    │               │                                       │
    │               │                               ════ 网络传输 ════
    │               │
    │               └── 等待响应...
    │
    └── 返回 Result
```

---

## 第五部分 Dubbo 协议与网络通信

### 5.1 Protocol 体系

```
Protocol（SPI 接口）
    │
    ├── @SPI("dubbo")  ← 默认使用 dubbo 协议
    │
    ├── DubboProtocol      ← Dubbo 默认协议，基于 TCP 长连接
    ├── TripleProtocol     ← Dubbo 3.x，基于 HTTP/2 + gRPC
    ├── RestProtocol       ← REST 风格，基于 HTTP
    ├── InjvmProtocol      ← 本地调用，不经过网络
    ├── GrpcProtocol       ← gRPC 协议
    ├── RegistryProtocol   ← 注册中心协议（服务导出/引用的入口）
    │
    └── Wrapper：
        ├── ProtocolFilterWrapper  ← 构建 Filter 链
        └── ProtocolListenerWrapper ← Listener 通知
```

**Protocol 接口定义：**

```java
@SPI("dubbo")
public interface Protocol {

    /**
     * 默认端口
     */
    int getDefaultPort();

    /**
     * 服务导出
     * @param invoker 服务的本地执行体
     * @return exporter 暴露服务的远程执行体
     */
    @Adaptive
    <T> Exporter<T> export(Invoker<T> invoker) throws RpcException;

    /**
     * 服务引用
     * @param type 服务接口
     * @param url 服务地址
     * @return invoker 服务的远程执行体
     */
    @Adaptive
    <T> Invoker<T> refer(Class<T> type, URL url) throws RpcException;

    /**
     * 销毁
     */
    void destroy();
}
```

### 5.2 Dubbo 协议格式

Dubbo 协议是自定义的二进制协议，紧凑高效：

```
Dubbo 协议帧结构（共 16 字节头部 + 变长 body）：

 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  Magic Number (0xdabb)          |  Flag  |  Status (Response) |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        Request ID                               |
|                                                                 |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Data Length                                  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                     Body (变长)                                  |
|                     ...                                          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

字段说明：
┌──────────────┬──────────┬──────────────────────────────────────────┐
│ 字段           │ 字节数    │ 说明                                     │
├──────────────┼──────────┼──────────────────────────────────────────┤
│ Magic Number │ 2        │ 固定 0xdabb，用于识别 Dubbo 协议帧           │
│ Flag         │ 1        │ 第0位: 0=Response, 1=Request               │
│              │          │ 第1位: 0=单向, 1=双向                       │
│              │          │ 第2位: 0=无事件, 1=事件（心跳等）              │
│              │          │ 第3-7位: 序列化方式（2=hessian2, ...）      │
│ Status       │ 1        │ 响应状态码（仅 Response 有效）                │
│              │          │ 20=OK, 30=CLIENT_TIMEOUT, 31=SERVER_TIMEOUT│
│              │          │ 40=BAD_REQUEST, 50=BAD_RESPONSE, ...      │
│ Request ID   │ 8        │ 请求 ID，用于匹配请求与响应                    │
│ Data Length  │ 4        │ Body 数据长度                               │
│ Body         │ 变长      │ 序列化后的请求/响应数据                        │
└──────────────┴──────────┴──────────────────────────────────────────┘
```

**为什么 Dubbo 协议比 HTTP 快？**
1. 二进制格式比文本格式（HTTP）更紧凑
2. 单一长连接复用，避免了 HTTP 每次请求的连接建立开销
3. 自定义序列化（Hessian2）比 JSON 更小更快
4. 协议头仅 16 字节，开销极小

### 5.3 HeaderExchangeServer/Client

Exchange 层封装了请求-响应语义，在 Transport 层的纯消息收发之上增加了**请求-响应匹配**和**心跳**。

#### 5.3.1 HeaderExchangeServer — Provider 侧

```java
public class HeaderExchangeServer implements RemotingServer {

    private final ExchangeServer server;
    private ScheduledExecutorService heartbeatTimer;

    public HeaderExchangeServer(RemotingServer server) {
        this.server = server;

        // ① 启动心跳定时器
        startHeartBeatTask();
    }

    private void startHeartBeatTask() {
        int heartbeat = server.getUrl().getParameter(HEARTBEAT_KEY, 0);
        int idleTimeout = server.getUrl().getParameter(HEARTBEAT_TIMEOUT_KEY, heartbeat * 3);

        if (heartbeat < 1) {
            return;  // 不需要心跳
        }

        heartbeatTimer.scheduleAtFixedRate(() -> {
            // ② 遍历所有 Channel
            for (Channel channel : server.getChannels()) {
                if (channel.isConnected() && isNeedHeartbeat(channel)) {
                    // ③ 发送心跳
                    Request heartRequest = createHeartbeatRequest();
                    channel.send(heartRequest);
                }
            }
        }, heartbeat, heartbeat, TimeUnit.MILLISECONDS);
    }

    @Override
    public void close() {
        doClose();
        server.close();
    }

    private void doClose() {
        // 关闭心跳定时器
    }
}
```

#### 5.3.2 HeaderExchangeClient — Consumer 侧

```java
public class HeaderExchangeClient implements ExchangeClient {

    private final Client client;
    private ScheduledExecutorService heartbeatTimer;

    public HeaderExchangeClient(Client client, boolean needHeartbeat) {
        this.client = client;

        if (needHeartbeat) {
            // 启动心跳
            int heartbeat = client.getUrl().getParameter(HEARTBEAT_KEY, DEFAULT_HEARTBEAT);
            startHeartBeatTimer(heartbeat);
        }
    }

    @Override
    public CompletableFuture<Object> request(Object request, int timeout) throws RemotingException {
        // ① 创建 DefaultFuture（CompletableFuture）
        // ② 发送请求
        // ③ 返回 Future
        return channel.request(request, timeout);
    }

    private void startHeartBeatTimer(int heartbeat) {
        heartbeatTimer.scheduleAtFixedRate(() -> {
            if (client.isConnected()) {
                // 发送心跳
                Request heartRequest = new Request();
                heartRequest.setEvent(Request.HEARTBEAT_EVENT);
                client.send(heartRequest);
            }
        }, heartbeat, heartbeat, TimeUnit.MILLISECONDS);
    }
}
```

#### 5.3.3 DefaultFuture — 请求-响应匹配

```java
public class DefaultFuture extends CompletableFuture<Object> {

    // 请求 ID → DefaultFuture 映射（用于匹配响应）
    private static final Map<Long, DefaultFuture> FUTURES = new ConcurrentHashMap<>();

    private final long id;          // 请求 ID
    private final Channel channel;  // 通道
    private final Request request;  // 请求
    private final int timeout;      // 超时时间
    private final long start;       // 开始时间

    public DefaultFuture(Channel channel, Request request, int timeout) {
        this.id = request.getId();
        this.channel = channel;
        this.request = request;
        this.timeout = timeout;
        this.start = System.currentTimeMillis();

        // ① 存入静态 Map
        FUTURES.put(id, this);
        CHANNELS.put(id, channel);
    }

    /**
     * 收到响应时的回调
     */
    public static void received(Channel channel, Response response) {
        // ① 根据 response.getId() 找到对应的 DefaultFuture
        DefaultFuture future = FUTURES.remove(response.getId());

        if (future != null) {
            // ② 取消超时检查
            Timeout timeout = future.timeoutCheckTask;
            if (timeout != null) {
                timeout.cancel();
            }

            // ③ 根据 Response 状态处理
            if (response.getStatus() == Response.OK) {
                // 正常响应
                future.complete(response.getResult());
            } else {
                // 异常响应
                future.completeExceptionally(
                    new RemotingException(channel, response.getErrorMessage()));
            }
        }
    }

    /**
     * 超时检查
     */
    private static class TimeoutCheckTask implements TimerTask {
        private final Long requestID;

        @Override
        public void run(Timeout timeout) {
            DefaultFuture future = FUTURES.get(requestID);
            if (future == null || future.isDone()) {
                return;
            }

            // 超时后创建超时 Response
            Response timeoutResponse = new Response(requestID);
            timeoutResponse.setStatus(future.isSent() ?
                Response.SERVER_TIMEOUT : Response.CLIENT_TIMEOUT);
            timeoutResponse.setErrorMessage("Waiting server-side response timeout. ...");

            // 处理超时
            DefaultFuture.received(future.getChannel(), timeoutResponse);
        }
    }
}
```

**请求-响应匹配流程：**

```
Consumer 发送请求：
    ① Request(id=1, data=RpcInvocation{sayHello})
    ② new DefaultFuture(channel, request, timeout=1000)
       FUTURES.put(1, future)
    ③ channel.send(request)  ← 序列化 + 网络发送
    ④ 返回 future（CompletableFuture）
    ⑤ 业务线程阻塞等待 future.get() 或通过回调获取

Provider 返回响应：
    ① Response(id=1, result=RpcResult{"hello zhang"})
    ② 网络接收 → 解码
    ③ DefaultFuture.received(channel, response)
       FUTURES.remove(1) → future
       future.complete(result)  ← 唤醒等待的线程

超时处理：
    ① TimeoutCheckTask 在 timeout 时间后触发
    ② 检查 future 是否完成
    ③ 如果未完成，创建超时 Response
    ④ DefaultFuture.received(channel, timeoutResponse)
       future.completeExceptionally(TimeoutException)
```

### 5.4 NettyTransporter / NettyServer / NettyClient

Transport 层是真正进行网络通信的地方，默认使用 Netty。

#### 5.4.1 Transporter SPI

```java
@SPI("netty")
public interface Transporter {
    @Adaptive({Constants.SERVER_KEY, Constants.TRANSPORTER_KEY})
    RemotingServer bind(URL url, ChannelHandler... handlers) throws RemotingException;

    @Adaptive({Constants.CLIENT_KEY, Constants.TRANSPORTER_KEY})
    Client connect(URL url, ChannelHandler... handlers) throws RemotingException;
}
```

SPI 配置文件（`META-INF/dubbo/internal/org.apache.dubbo.remoting.Transporter`）：

```properties
netty=org.apache.dubbo.remoting.transport.netty4.NettyTransporter
netty4=org.apache.dubbo.remoting.transport.netty4.NettyTransporter
mina=org.apache.dubbo.remoting.transport.mina.MinaTransporter
grizzly=org.apache.dubbo.remoting.transport.grizzly.GrizzlyTransporter
```

#### 5.4.2 NettyServer — Provider 侧 Netty 服务器

```java
public class NettyServer extends AbstractServer implements RemotingServer {

    private ServerBootstrap bootstrap;
    private EventLoopGroup bossGroup;
    private EventLoopGroup workerGroup;
    private Channel channel;

    @Override
    protected void doOpen() throws Throwable {
        // ① 创建 Netty Bootstrap
        bootstrap = new ServerBootstrap();

        // ② 创建 Boss 和 Worker 线程组
        bossGroup = new NioEventLoopGroup(1, new DefaultThreadFactory("NettyServerBoss", true));
        workerGroup = new NioEventLoopGroup(
            getUrl().getPositiveParameter(IO_THREADS_KEY, Constants.DEFAULT_IO_THREADS),
            new DefaultThreadFactory("NettyServerWorker", true));

        // ③ 配置 Netty
        final NettyServerHandler nettyServerHandler = new NettyServerHandler(
            getUrl(), this);
        bootstrap.group(bossGroup, workerGroup)
            .channel(NioServerSocketChannel.class)
            .childOption(ChannelOption.TCP_NODELAY, Boolean.TRUE)
            .childOption(ChannelOption.SO_REUSEADDR, Boolean.TRUE)
            .childOption(ChannelOption.ALLOCATOR, PooledByteBufAllocator.DEFAULT)
            .childHandler(new ChannelInitializer<NioSocketChannel>() {
                @Override
                protected void initChannel(NioSocketChannel ch) throws Exception {
                    // ④ Pipeline 配置
                    int idleTimeout = UrlUtils.getIdleTimeout(getUrl());
                    NettyCodecAdapter adapter = new NettyCodecAdapter(
                        getCodec(), getUrl(), NettyServer.this);
                    ch.pipeline()
                        // 编解码器
                        .addLast("decoder", adapter.getDecoder())
                        .addLast("encoder", adapter.getEncoder())
                        // 空闲检测
                        .addLast("server-idle-handler", new IdleStateHandler(0, 0, idleTimeout, MILLISECONDS))
                        // 业务处理器
                        .addLast("handler", nettyServerHandler);
                }
            });

        // ⑤ 绑定端口
        ChannelFuture channelFuture = bootstrap.bind(getBindAddress());
        channelFuture.syncUninterruptibly();
        this.channel = channelFuture.channel();
    }

    @Override
    protected void doClose() {
        // 关闭 Netty 资源
        if (channel != null) {
            channel.close();
        }
        if (bootstrap != null) {
            bossGroup.shutdownGracefully();
            workerGroup.shutdownGracefully();
        }
    }
}
```

#### 5.4.3 NettyClient — Consumer 侧 Netty 客户端

```java
public class NettyClient extends AbstractClient {

    private Bootstrap bootstrap;
    private EventLoopGroup nioEventLoopGroup;
    private volatile Channel channel;

    @Override
    protected void doOpen() throws Throwable {
        // ① 创建 Netty Bootstrap（客户端不需要 BossGroup）
        bootstrap = new Bootstrap();

        nioEventLoopGroup = new NioEventLoopGroup(
            getUrl().getPositiveParameter(IO_THREADS_KEY, Constants.DEFAULT_IO_THREADS),
            new DefaultThreadFactory("NettyClientWorker", true));

        bootstrap.group(nioEventLoopGroup)
            .channel(NioSocketChannel.class)
            .option(ChannelOption.SO_KEEPALIVE, true)
            .option(ChannelOption.TCP_NODELAY, true)
            .option(ChannelOption.ALLOCATOR, PooledByteBufAllocator.DEFAULT);

        bootstrap.handler(new ChannelInitializer() {
            @Override
            protected void initChannel(Channel ch) throws Exception {
                // ② Pipeline 配置
                NettyCodecAdapter adapter = new NettyCodecAdapter(
                    getCodec(), getUrl(), NettyClient.this);
                int heartbeatInterval = UrlUtils.getHeartbeat(getUrl());
                ch.pipeline()
                    .addLast("decoder", adapter.getDecoder())
                    .addLast("encoder", adapter.getEncoder())
                    .addLast("client-idle-handler",
                        new IdleStateHandler(heartbeatInterval, 0, 0, MILLISECONDS))
                    .addLast("handler", new NettyClientHandler(NettyClient.this));
            }
        });
    }

    @Override
    protected void doConnect() throws Throwable {
        long start = System.currentTimeMillis();
        // ① 连接服务器
        ChannelFuture future = bootstrap.connect(getConnectAddress());
        try {
            // ② 等待连接完成（带超时）
            boolean ret = future.awaitUninterruptibly(
                getConnectTimeout(), MILLISECONDS);

            if (ret && future.isSuccess()) {
                Channel newChannel = future.channel();
                try {
                    // ③ 关闭旧 Channel
                    Channel oldChannel = NettyClient.this.channel;
                    if (oldChannel != null) {
                        oldChannel.close();
                    }
                } finally {
                    NettyClient.this.channel = newChannel;
                }
            }
        } finally {
            // ...
        }
    }
}
```

#### 5.4.4 NettyServerHandler / NettyClientHandler

```java
// NettyServerHandler — Provider 侧 Netty 处理器
@Sharable
public class NettyServerHandler extends ChannelDuplexHandler {

    private final ChannelHandler handler;  // 实际是 HeaderExchangeHandler

    @Override
    public void channelRead(ChannelHandlerContext ctx, Object msg) throws Exception {
        // msg 已经被 Decoder 解码为 Request/Response 对象
        NettyChannel channel = NettyChannel.getOrAddChannel(ctx.channel(), url, handler);
        // 委托给 HeaderExchangeHandler 处理
        handler.received(channel, msg);
    }

    @Override
    public void channelActive(ChannelHandlerContext ctx) throws Exception {
        // 连接建立
        handler.connected(NettyChannel.getOrAddChannel(ctx.channel(), url, handler));
    }

    @Override
    public void channelInactive(ChannelHandlerContext ctx) throws Exception {
        // 连接断开
        handler.disconnected(NettyChannel.getOrAddChannel(ctx.channel(), url, handler));
    }

    @Override
    public void userEventTriggered(ChannelHandlerContext ctx, Object evt) throws Exception {
        if (evt instanceof IdleStateEvent) {
            // 空闲检测：关闭连接
            NettyChannel channel = ...;
            logger.warn("Idle event triggered, close channel " + channel);
            channel.close();
        }
    }
}
```

### 5.5 Codec2 编解码体系

```
Codec2（SPI 接口）
    │
    ├── DubboCodec          ← Dubbo 协议编解码器
    ├── ExchangeCodec       ← 交换层编解码器
    ├── TransportCodec      ← 传输层编解码器
    └── TelnetCodec         ← Telnet 编解码器
```

**DubboCodec 编码过程：**

```java
// ExchangeCodec.encode()
public void encode(Channel channel, ChannelBuffer buffer, Object msg) throws IOException {
    if (msg instanceof Request) {
        // ① 编码请求
        encodeRequest(channel, buffer, (Request) msg);
    } else if (msg instanceof Response) {
        // ② 编码响应
        encodeResponse(channel, buffer, (Response) msg);
    } else if (msg instanceof String) {
        // ③ Telnet 命令
        buffer.writeBytes(msg.getBytes());
    } else {
        // ④ 不支持的类型
        throw new UnsupportedOperationException("...");
    }
}

protected void encodeRequest(Channel channel, ChannelBuffer buffer, Request req) throws IOException {
    // ① 获取序列化器
    Serialization serialization = getSerialization(channel);
    // ② 创建字节输出流
    ChannelBufferOutputStream os = new ChannelBufferOutputStream(buffer);
    // ③ 写头部（16 字节）
    //    Magic(2) + Flag(1) + Status(1) + RequestId(8) + DataLength(4)
    byte[] header = new byte[HEADER_LENGTH];
    // 设置 Magic Number
    Bytes.short2bytes(MAGIC, header);
    // 设置 Flag（请求/响应 + 序列化类型 + 单向/双向 + 事件）
    header[2] = (byte) (FLAG_REQUEST | serialization.getContentTypeId());
    if (req.isTwoWay()) header[2] |= FLAG_TWOWAY;
    if (req.isEvent()) header[2] |= FLAG_EVENT;
    // 设置 Request ID
    Bytes.long2bytes(req.getId(), header, 4);

    // ④ 先写占位的长度（后面回填）
    int savedWriteIndex = os.writeIndex();
    os.writeIndex = savedWriteIndex + HEADER_LENGTH;

    // ⑤ 序列化 Body
    ObjectOutput out = serialization.serialize(channel.getUrl(), os);
    if (req.isEvent()) {
        // 事件（心跳）
        encodeEventData(channel, out, req.getData());
    } else {
        // 正常请求：序列化 RpcInvocation
        encodeRequestData(channel, out, req.getData());
    }
    out.flushBuffer();

    // ⑥ 回填 Body 长度
    int len = os.writeIndex() - savedWriteIndex - HEADER_LENGTH;
    Bytes.int2bytes(len, header, 12);

    // ⑦ 写回头部
    os.writeIndex = savedWriteIndex;
    os.write(header);
    os.writeIndex = savedWriteIndex + HEADER_LENGTH + len;
}
```

**DubboCodec 解码过程：**

```java
protected Object decode(Channel channel, ChannelBuffer buffer, int readable, byte[] header) {
    // ① 检查 Magic Number
    if (readable > 0 && header[0] != MAGIC_HIGH
            || readable > 1 && header[1] != MAGIC_LOW) {
        // 可能是 Telnet 命令
        return decodeTelnet(channel, buffer, readable);
    }

    // ② 检查可读长度是否够头部
    if (readable < HEADER_LENGTH) {
        return NEED_MORE_INPUT;  // 需要更多数据
    }

    // ③ 解析头部
    int len = Bytes.bytes2int(header, 12);  // Body 长度
    // 检查 Body 长度是否超过限制
    if (len > payload) {
        throw new IOException("Data length too large: " + len);
    }

    // ④ 检查是否收到完整 Body
    if (readable < HEADER_LENGTH + len) {
        return NEED_MORE_INPUT;  // 需要更多数据
    }

    // ⑤ 解析 Flag
    byte flag = header[2];
    boolean isRequest = (flag & FLAG_REQUEST) != 0;
    boolean isEvent = (flag & FLAG_EVENT) != 0;
    boolean isTwoWay = (flag & FLAG_TWOWAY) != 0;
    int serializationId = flag & SERIALIZE_MASK;

    // ⑥ 获取 Request ID
    long id = Bytes.bytes2long(header, 4);

    // ⑦ 反序列化 Body
    if (isRequest) {
        // 解码请求
        Request req = new Request(id);
        req.setVersion(Version.getProtocolVersion());
        req.setTwoWay(isTwoWay);
        req.setEvent(isEvent);

        if (isEvent) {
            req.setData(decodeEventData(channel, in));
        } else {
            // 反序列化 RpcInvocation
            req.setData(decodeRequestData(channel, in));
        }
        return req;
    } else {
        // 解码响应
        Response res = new Response(id);
        res.setEvent(isEvent);
        byte status = header[3];
        res.setStatus(status);
        if (status == Response.OK) {
            // 反序列化 Result
            res.setResult(decodeResponseData(channel, in));
        } else {
            res.setErrorMessage(in.readUTF());
        }
        return res;
    }
}
```

### 5.6 HeaderExchangeHandler — Provider 侧请求处理

```java
public class HeaderExchangeHandler implements ChannelHandlerDelegate {

    @Override
    public void received(Channel channel, Object message) throws RemotingException {
        if (message instanceof Request) {
            // ① 处理请求
            Request req = (Request) message;

            if (req.isEvent()) {
                // ② 心跳事件
                handlerEvent(channel, req);
            } else {
                // ③ 正常 RPC 请求
                if (req.isTwoWay()) {
                    // 双向请求：需要返回响应
                    handleRequest(channel, req);
                } else {
                    // 单向请求：不需要返回响应
                    handler.received(channel, req.getData());
                }
            }
        } else if (message instanceof Response) {
            // ④ 响应（Consumer 侧收到 Provider 的响应）
            DefaultFuture.received(channel, (Response) message);
        } else if (message instanceof String) {
            // ⑤ Telnet 命令
            String echo = handler.telnet(channel, (String) message);
        }
    }

    void handleRequest(final ExchangeChannel channel, Request req) {
        // ① 创建响应
        Response res = new Response(req.getId(), req.getVersion());

        // ② 检查请求是否可解码
        if (req.isBroken()) {
            Object data = req.getData();
            res.setErrorMessage("Fail to decode request due to: " + data);
            res.setStatus(Response.BAD_REQUEST);
            channel.send(res);
            return;
        }

        // ③ 获取请求数据（RpcInvocation）
        Object msg = req.getData();

        try {
            // ④ 调用 ExchangeHandler.reply() —— 进入 Protocol 层
            CompletionStage<Object> future = handler.reply(channel, msg);

            // ⑤ 设置响应
            future.whenComplete((appResult, t) -> {
                try {
                    if (t == null) {
                        res.setStatus(Response.OK);
                        res.setResult(appResult);
                    } else {
                        res.setStatus(Response.SERVICE_ERROR);
                        res.setErrorMessage(StringUtils.toString(t));
                    }
                    // ⑥ 发送响应
                    channel.send(res);
                } catch (RemotingException e) {
                    logger.warn("Send result to client failed...");
                }
            });
        } catch (Throwable e) {
            res.setStatus(Response.SERVICE_ERROR);
            res.setErrorMessage(StringUtils.toString(e));
            channel.send(res);
        }
    }
}
```

**ExchangeHandler.reply() — DubboProtocol 的内部类：**

```java
// DubboProtocol 中的 requestHandler
private ExchangeHandler requestHandler = new ExchangeHandlerAdapter() {

    @Override
    public CompletableFuture<Object> reply(ExchangeChannel channel, Object message)
            throws RemotingException {

        if (!(message instanceof Invocation)) {
            throw new RemotingException(...);
        }

        Invocation inv = (Invocation) message;
        // ① 获取服务 key
        String serviceKey = serviceKey(
            inv.getAttachment(PATH_KEY),
            inv.getAttachment(GROUP_KEY),
            inv.getAttachment(VERSION_KEY),
            channel.getUrl().getPort());

        // ② 从 exporterMap 中获取 Exporter
        DubboExporter<?> exporter = (DubboExporter<?>) exporterMap.get(serviceKey);
        if (exporter == null) {
            throw new RemotingException(..., "Not found exported service: " + serviceKey);
        }

        // ③ 获取 Invoker
        Invoker<?> invoker = exporter.getInvoker();

        // ④ 判断是否是回调
        boolean isCallBackServiceInvoke = false;

        // ⑤ 执行调用链（Filter 链 → 业务方法）
        RpcContext.getContext().setRemoteAddress(channel.getRemoteAddress());
        Result result = invoker.invoke(inv);

        // ⑥ 返回结果
        return CompletableFuture.completedFuture(result);
    }

    @Override
    public void received(Channel channel, Object message) throws RemotingException {
        if (message instanceof Invocation) {
            reply(channel, message);
        } else {
            super.received(channel, message);
        }
    }
};
```

### 5.7 心跳机制

```
心跳参数：
  heartbeat  = 60s（默认）  心跳发送间隔
  heartbeat.timeout = 180s   心跳超时时间

Provider 侧：
  ┌─────────────────────────────────────────┐
  │  HeaderExchangeServer                    │
  │    ├── heartbeatTimer（定时器）            │
  │    │     每 60s 检查一次                   │
  │    │     对每个 Channel：                  │
  │    │       如果上次读时间 > heartbeat       │
  │    │         → 发送心跳 Request             │
  │    │     如果上次读写时间 > timeout(180s)   │
  │    │         → 关闭 Channel                │
  │    └── Netty IdleStateHandler            │
  │          readerIdleTime = 0（不检测）      │
  │          writerIdleTime = 0（不检测）      │
  │          allIdleTime = 180s              │
  │          → 空闲 180s 关闭连接              │
  └─────────────────────────────────────────┘

Consumer 侧：
  ┌─────────────────────────────────────────┐
  │  HeaderExchangeClient                    │
  │    ├── heartbeatTimer（定时器）            │
  │    │     每 60s 发送一次心跳                │
  │    │     → channel.send(heartRequest)    │
  │    └── Netty IdleStateHandler            │
  │          readerIdleTime = 60s            │
  │          → 60s 没收到数据 → 发送心跳        │
  │          writerIdleTime = 0              │
  │          allIdleTime = 0                 │
  └─────────────────────────────────────────┘

心跳 Request：
  Request {
      id = 递增 ID
      event = HEARTBEAT_EVENT (true)
      twoWay = true
      data = null  ← 心跳不携带数据
  }

心跳 Response：
  Response {
      id = 对应 Request 的 id
      event = HEARTBEAT_EVENT (true)
      status = OK
      result = null
  }
```

**心跳流程图：**

```
Consumer                    Network                    Provider
   │                           │                           │
   │   ──── 心跳 Request ────→ │   ──── 心跳 Request ────→ │
   │                           │                           │
   │                           │ ←──── 心跳 Response ──── │
   │ ←──── 心跳 Response ──── │                           │
   │                           │                           │
   │  更新 lastRead 时间         │                    更新 lastRead 时间
   │                           │                           │
   │   ... (60s 无数据) ...      │                           │
   │                           │                           │
   │   ──── 心跳 Request ────→ │   ──── 心跳 Request ────→ │
   │                           │                           │
   │                           │ ←──── 心跳 Response ──── │
   │ ←──── 心跳 Response ──── │                           │
   │                           │                           │

如果 Provider 超过 180s 没收到心跳：
   │                           │                           │
   │                           │    Provider 关闭连接        │
   │                           │  ←─── Connection Closed ──│
   │                           │                           │
   │  Consumer 检测到连接断开     │                           │
   │  下次调用时重连              │                           │
```

---

## 第六部分 集群容错

> 集群容错是 Dubbo 服务治理的核心能力之一，当调用失败时，根据策略进行重试、快速失败、安全失败等处理。

### 6.1 Cluster 接口体系

```
Cluster（SPI 接口）
    │
    ├── @SPI("failover")  ← 默认使用 FailoverCluster
    │
    ├── FailoverCluster       ← 失败自动重试（默认）
    ├── FailfastCluster       ← 快速失败
    ├── FailsafeCluster       ← 失败安全（忽略异常）
    ├── ForkingCluster        ← 并行调用多个 Provider
    ├── BroadcastCluster      ← 广播调用所有 Provider
    ├── AvailableCluster      ← 遍历直到找到可用的
    ├── MergeableCluster      ← 合并结果（分组聚合）
    └── ZoneAwareCluster      ← 多注册中心感知（Dubbo 3.x）
```

**Cluster 接口定义：**

```java
@SPI("failover")
public interface Cluster {

    /**
     * 将 Directory 中的多个 Invoker 合并为一个容错的 Invoker
     */
    @Adaptive
    <T> Invoker<T> join(Directory<T> directory) throws RpcException;
}
```

**核心设计模式**：Cluster 通过 `join()` 将多个 Provider 的 Invoker 合并为一个虚拟 Invoker，对上层透明。当调用这个虚拟 Invoker 时，Cluster 实现会根据策略选择实际的 Invoker。

```
RegistryDirectory（服务目录）
    │
    │  包含多个 Invoker：
    │  [DubboInvoker@192.168.1.10:20880,
    │   DubboInvoker@192.168.1.11:20880,
    │   DubboInvoker@192.168.1.12:20880]
    │
    ▼
Cluster.join(directory)
    │
    ▼
FailoverClusterInvoker（虚拟 Invoker）
    │  对上层透明，看起来就是一个 Invoker
    │
    │  调用时：
    │  ├── 路由过滤：RouterChain.route()
    │  ├── 负载均衡：LoadBalance.select()
    │  └── 容错执行：doInvoke()
    │       ├── 失败 → 重试（Failover）
    │       ├── 失败 → 快速返回异常（Failfast）
    │       └── 失败 → 忽略异常返回空（Failsafe）
```

### 6.2 FailoverClusterInvoker（默认）

失败自动重试，默认重试 2 次，共 3 次调用。

```java
public class FailoverClusterInvoker<T> extends AbstractClusterInvoker<T> {

    @Override
    @SuppressWarnings({"unchecked", "rawtypes"})
    public Result doInvoke(Invocation invocation, final List<Invoker<T>> invokers,
                           LoadBalance loadbalance) throws RpcException {
        // ① 获取重试次数（默认 2 次，加上初次调用共 3 次）
        int retries = getUrl().getMethodParameter(
            invocation.getMethodName(), RETRIES_KEY, DEFAULT_RETRIES) + 1;
        if (retries <= 0) {
            retries = 1;
        }

        // ② 保存上次调用的 Invoker（用于异常信息）
        Invoker<T> lastInvoker = null;

        // ③ 重试循环
        for (int i = 0; i < retries; i++) {
            // 重新获取 Invoker 列表（可能在重试过程中列表变化）
            List<Invoker<T>> copyInvokers = invokers;
            checkInvokers(copyInvokers, invocation);

            // ④ 负载均衡选择一个 Invoker
            Invoker<T> invoker = select(loadbalance, invocation, copyInvokers, selected);
            selected.remove(invoker);  // 移除已选，下次重试不重复选
            lastInvoker = invoker;

            try {
                // ⑤ 执行调用
                Result result = invoker.invoke(invocation);
                return result;
            } catch (RpcException e) {
                // ⑥ 业务异常不重试
                if (e.isBiz()) {
                    throw e;
                }
                // ⑦ 网络异常：记录日志，继续重试
                if (i < retries - 1) {
                    logger.warn("... retry ...");
                    // 延迟一点再重试（避免立即重试打到同一个 Provider）
                    if (retryTimer != null) {
                        retryTimer.newTimeout(timeout -> { }, RETRY_SLEEP_TIME, MILLISECONDS);
                    }
                }
            } catch (Throwable e) {
                // 其他异常不重试
                throw new RpcException(e.getMessage(), e);
            }
        }

        // ⑧ 所有重试都失败
        throw new RpcException("Failed to invoke the method " + invocation.getMethodName()
            + " in the service " + getInterface().getName()
            + ". Tried " + retries + " times ...");
    }
}
```

**Failover 执行流程：**

```
FailoverClusterInvoker.doInvoke()
    │
    ├── 第 1 次尝试
    │   ├── select() → 选择 Invoker@192.168.1.10
    │   ├── invoker.invoke() → 超时异常
    │   └── 记录异常，继续重试
    │
    ├── 第 2 次尝试
    │   ├── select() → 选择 Invoker@192.168.1.11（排除上次选的）
    │   ├── invoker.invoke() → 网络异常
    │   └── 记录异常，继续重试
    │
    ├── 第 3 次尝试
    │   ├── select() → 选择 Invoker@192.168.1.12（排除上次选的）
    │   ├── invoker.invoke() → 成功！
    │   └── 返回 Result
    │
    └── 如果 3 次都失败 → 抛出 RpcException
```

### 6.3 FailfastClusterInvoker

快速失败，只调用一次，失败立即返回异常。

```java
public class FailfastClusterInvoker<T> extends AbstractClusterInvoker<T> {

    @Override
    public Result doInvoke(Invocation invocation, List<Invoker<T>> invokers,
                           LoadBalance loadbalance) throws RpcException {
        checkInvokers(invokers, invocation);
        // ① 负载均衡选择一个 Invoker
        Invoker<T> invoker = select(loadbalance, invocation, invokers, null);
        try {
            // ② 只调用一次，不重试
            return invoker.invoke(invocation);
        } catch (Throwable e) {
            // ③ 失败立即抛出异常
            if (e instanceof RpcException && ((RpcException) e).isBiz()) {
                throw (RpcException) e;
            }
            throw new RpcException("Failfast invoke providers " + invoker
                + " " + loadbalance.getClass().getSimpleName()
                + " select from all providers " + invokers
                + " for service " + getInterface().getName()
                + " method " + invocation.getMethodName()
                + " on consumer " + RpcContext.getContext().getLocalAddress()
                + " use dubbo version " + Version.getVersion()
                + ", but no luck to perform the invocation. Last error is: " + e.getMessage(),
                e);
        }
    }
}
```

**适用场景**：非幂等操作（如新增记录），重试会导致重复插入。

### 6.4 FailsafeClusterInvoker

安全失败，出现异常时忽略，返回空结果。

```java
public class FailsafeClusterInvoker<T> extends AbstractClusterInvoker<T> {

    @Override
    public Result doInvoke(Invocation invocation, List<Invoker<T>> invokers,
                           LoadBalance loadbalance) throws RpcException {
        try {
            checkInvokers(invokers, invocation);
            Invoker<T> invoker = select(loadbalance, invocation, invokers, null);
            return invoker.invoke(invocation);
        } catch (Throwable e) {
            // 异常只记录日志，返回空结果
            logger.error("Failsafe ignore exception: " + e.getMessage(), e);
            return AsyncRpcResult.newDefaultAsyncResult(null, null, invocation);
        }
    }
}
```

**适用场景**：写日志、发通知等非关键操作，失败不影响主流程。

### 6.5 ForkingClusterInvoker

并行调用多个 Provider，只要一个成功就返回。

```java
public class ForkingClusterInvoker<T> extends AbstractClusterInvoker<T> {

    @Override
    public Result doInvoke(Invocation invocation, List<Invoker<T>> invokers,
                           LoadBalance loadbalance) throws RpcException {

        try {
            checkInvokers(invokers, invocation);
            final List<Invoker<T>> selected;

            // ① 获取并行调用数（默认 2）
            final int forks = getUrl().getParameter(FORKS_KEY, DEFAULT_FORKS);
            // ② 获取超时时间
            final int timeout = getUrl().getPositiveParameter(TIMEOUT_KEY, DEFAULT_TIMEOUT);

            // ③ 选择 forks 个 Invoker
            if (forks <= 0 || forks >= invokers.size()) {
                selected = invokers;
            } else {
                selected = new ArrayList<>();
                for (int i = 0; i < forks; i++) {
                    Invoker<T> invoker = select(loadbalance, invocation, invokers, selected);
                    selected.add(invoker);
                }
            }

            RpcContext.getContext().setInvokers((List) selected);

            // ④ 计数器
            final AtomicInteger count = new AtomicInteger();
            final BlockingQueue<Object> ref = new LinkedBlockingQueue<>();

            // ⑤ 并行调用
            for (final Invoker<T> invoker : selected) {
                executor.execute(() -> {
                    try {
                        Result result = invoker.invoke(invocation);
                        // 成功结果放入队列
                        ref.offer(result);
                    } catch (RpcException e) {
                        // 失败计数
                        int value = count.incrementAndGet();
                        if (value >= selected.size()) {
                            // 全部失败，放入异常
                            ref.offer(e);
                        }
                    }
                });
            }

            // ⑥ 等待第一个结果（带超时）
            Object ret = ref.poll(timeout, TimeUnit.MILLISECONDS);
            if (ret instanceof Throwable) {
                throw new RpcException((Throwable) ret);
            }
            return (Result) ret;
        } catch (Throwable e) {
            // ...
        }
    }
}
```

**适用场景**：实时性要求极高的场景，用多倍资源换取最低延迟。

### 6.6 BroadcastClusterInvoker

广播调用所有 Provider，任意一个报错则报错。

```java
public class BroadcastClusterInvoker<T> extends AbstractClusterInvoker<T> {

    @Override
    public Result doInvoke(final Invocation invocation, List<Invoker<T>> invokers,
                           LoadBalance loadbalance) throws RpcException {
        checkInvokers(invokers, invocation);
        RpcContext.getContext().setInvokers((List) invokers);

        RpcException rpcException = null;
        Result result = null;

        // 遍历所有 Provider，逐个调用
        for (Invoker<T> invoker : invokers) {
            try {
                result = invoker.invoke(invocation);
            } catch (RpcException e) {
                // 记录异常但不中断，继续调用下一个
                rpcException = e;
                logger.warn(e.getMessage(), e);
            }
        }

        // 如果有任何一个失败，抛出最后一个异常
        if (rpcException != null) {
            throw rpcException;
        }

        // 返回最后一个结果
        return result;
    }
}
```

**适用场景**：刷新所有节点的本地缓存或日志。

### 6.7 AvailableCluster / MergeableCluster

```java
// AvailableCluster：遍历所有 Invoker，找到第一个可用的调用
public class AvailableClusterInvoker<T> extends AbstractClusterInvoker<T> {
    @Override
    public Result doInvoke(Invocation invocation, List<Invoker<T>> invokers,
                           LoadBalance loadbalance) throws RpcException {
        for (Invoker<T> invoker : invokers) {
            if (invoker.isAvailable()) {
                return invoker.invoke(invocation);
            }
        }
        throw new RpcException("No provider available in: " + invokers);
    }
}

// MergeableCluster：按 group 分组调用，然后合并结果
public class MergeableClusterInvoker<T> extends AbstractClusterInvoker<T> {
    @Override
    protected Result doInvoke(Invocation invocation, List<Invoker<T>> invokers,
                              LoadBalance loadbalance) throws RpcException {
        // ① 按 group 分组
        Map<String, List<Invoker<T>>> groupInvokers = ...;

        // ② 并行调用每个 group
        // ③ 使用 Merger 合并各 group 的结果
        //    如：合并多个数据源查询结果
        Merger merger = ...;
        Object mergedResult = merger.merge(results);
        return new AsyncRpcResult(mergedResult, invocation);
    }
}
```

### 6.8 ClusterInvoker 整体流程

**AbstractClusterInvoker.invoke() — 所有 ClusterInvoker 的基类逻辑：**

```java
public abstract class AbstractClusterInvoker<T> implements Invoker<T> {

    @Override
    public Result invoke(final Invocation invocation) throws RpcException {
        checkWhetherDestroyed();

        // ① 绑定 attachment
        Map<String, Object> contextAttachments = ...;
        RpcContext.getContext().setObjectAttachments(contextAttachments);

        // ② 获取 Invoker 列表（从 Directory）
        List<Invoker<T>> invokers = list(invocation);

        // ③ 获取负载均衡器
        LoadBalance loadbalance = initLoadBalance(invokers, invocation);

        // ④ 子类实现具体的容错策略
        return doInvoke(invocation, invokers, loadbalance);
    }

    protected List<Invoker<T>> list(Invocation invocation) throws RpcException {
        // 从 Directory 获取 Invoker 列表，经过 RouterChain 过滤
        return directory.list(invocation);
    }

    /**
     * 负载均衡选择 + 重选逻辑
     */
    protected Invoker<T> select(LoadBalance loadbalance, Invocation invocation,
                                List<Invoker<T>> invokers, List<Invoker<T>> selected)
            throws RpcException {

        // ① 如果只有一个 Invoker，直接返回
        if (invokers.size() == 1) {
            return invokers.get(0);
        }

        // ② 调用 LoadBalance 选择
        Invoker<T> invoker = loadbalance.select(invokers, getUrl(), invocation);

        // ③ 检查选中的 Invoker 是否在 selected 列表中（上次失败的）
        if (selected != null && !selected.isEmpty() && selected.contains(invoker)) {
            try {
                // ④ 重选：避开上次失败的 Invoker
                Invoker<T> rInvoker = reselect(loadbalance, invocation,
                    invokers, selected, available);
                if (rInvoker != null) {
                    invoker = rInvoker;
                }
            } catch (Throwable t) {
                // ...
            }
        }
        return invoker;
    }

    /**
     * 子类实现具体的容错策略
     */
    protected abstract Result doInvoke(Invocation invocation, List<Invoker<T>> invokers,
                                       LoadBalance loadbalance) throws RpcException;
}
```

**完整调用流程：**

```
invoker.invoke(invocation)  ← FailoverClusterInvoker
    │
    ├── AbstractClusterInvoker.invoke()
    │       │
    │       ├── ① directory.list(invocation)
    │       │       │
    │       │       └── RegistryDirectory.list()
    │       │           ├── 从 urlInvokerMap 获取所有 Invoker
    │       │           └── RouterChain.route() 路由过滤
    │       │               ├── ConditionRouter 条件路由
    │       │               ├── ScriptRouter 脚本路由
    │       │               └── TagRouter 标签路由
    │       │
    │       ├── ② initLoadBalance()
    │       │       根据配置选择 LoadBalance（默认 random）
    │       │
    │       └── ③ doInvoke() ← 子类实现
    │
    ├── FailoverClusterInvoker.doInvoke()
    │       │
    │       ├── for (i = 0; i < retries; i++)
    │       │   ├── select(loadbalance, invocation, invokers, selected)
    │       │   │       └── loadbalance.select()
    │       │   │
    │       │   └── invoker.invoke(invocation)
    │       │           └── DubboInvoker.doInvoke()
    │       │               └── currentClient.request()
    │       │
    │       └── 成功则返回，失败则重试
    │
    └── 返回 Result
```

---

## 第七部分 负载均衡

### 7.1 LoadBalance 接口体系

```
LoadBalance（SPI 接口）
    │
    ├── @SPI("random")  ← 默认使用 RandomLoadBalance
    │
    ├── RandomLoadBalance          ← 加权随机（默认）
    ├── RoundRobinLoadBalance      ← 平滑加权轮询
    ├── LeastActiveLoadBalance     ← 最小活跃数
    ├── ConsistentHashLoadBalance  ← 一致性哈希
    └── ShortestResponseLoadBalance ← 最短响应时间（Dubbo 2.7+）
```

```java
@SPI("random")
public interface LoadBalance {

    /**
     * 从 Invoker 列表中选择一个
     */
    @Adaptive("loadbalance")
    <T> Invoker<T> select(List<Invoker<T>> invokers, URL url, Invocation invocation)
        throws RpcException;
}
```

### 7.2 RandomLoadBalance（默认加权随机）

```java
public class RandomLoadBalance extends AbstractLoadBalance {

    @Override
    protected <T> Invoker<T> doSelect(List<Invoker<T>> invokers, URL url, Invocation invocation) {
        // ① Invoker 数量
        int length = invokers.size();

        // ② 是否所有 Invoker 权重相同
        boolean sameWeight = true;
        // ③ 权重数组
        int[] weights = new int[length];
        // ④ 第一个 Invoker 的权重
        int firstWeight = getWeight(invokers.get(0), invocation);
        weights[0] = firstWeight;
        // ⑤ 总权重
        int totalWeight = firstWeight;

        for (int i = 1; i < length; i++) {
            int weight = getWeight(invokers.get(i), invocation);
            weights[i] = weight;
            totalWeight += weight;
            // 检查权重是否相同
            if (sameWeight && weight != firstWeight) {
                sameWeight = false;
            }
        }

        // ⑥ 如果权重不相同，按总权重随机
        if (!sameWeight && totalWeight > 0) {
            // 在 [0, totalWeight) 范围内随机
            int offset = ThreadLocalRandom.current().nextInt(totalWeight);
            // 找到落在哪个 Invoker 的权重区间
            for (int i = 0; i < length; i++) {
                offset -= weights[i];
                if (offset < 0) {
                    return invokers.get(i);
                }
            }
        }

        // ⑦ 权重相同，直接随机
        return invokers.get(ThreadLocalRandom.current().nextInt(length));
    }
}
```

**加权随机算法图解：**

```
假设 3 个 Provider，权重分别为 5:3:2，总权重 10

权重区间：
  Provider A [0, 5)    ── 占 50%
  Provider B [5, 8)    ── 占 30%
  Provider C [8, 10)   ── 占 20%

随机数 offset = 3 → 3 < 5 → 返回 Provider A
随机数 offset = 6 → 6 >= 5, 6-5=1 < 3 → 返回 Provider B
随机数 offset = 9 → 9 >= 5, 9-5=4 >= 3, 4-3=1 < 2 → 返回 Provider C

getWeight() 方法中还会考虑预热（warmup）：
  如果 Provider 启动时间 < warmup 时间（默认 10 分钟）
  则按比例降低权重：
    weight = uptime / warmup * configuredWeight
  这样新启动的 Provider 不会突然接收大量请求
```

**AbstractLoadBalance.getWeight() — 权重计算 + 预热：**

```java
public abstract class AbstractLoadBalance implements LoadBalance {

    int getWeight(Invoker<?> invoker, Invocation invocation) {
        // ① 获取配置权重（默认 100）
        int weight = invoker.getUrl()
            .getMethodParameter(invocation.getMethodName(), WEIGHT_KEY, DEFAULT_WEIGHT);
        if (weight > 0) {
            // ② 获取启动时间戳
            long timestamp = invoker.getUrl().getParameter(REMOTE_TIMESTAMP_KEY, 0L);
            if (timestamp > 0L) {
                // ③ 计算运行时间
                long uptime = System.currentTimeMillis() - timestamp;
                // ④ 预热时间（默认 10 分钟）
                int warmup = invoker.getUrl().getParameter(WARMUP_KEY, DEFAULT_WARMUP);
                // ⑤ 如果还在预热期，按比例降低权重
                if (uptime > 0 && uptime < warmup) {
                    weight = calculateWarmupWeight((int)uptime, warmup, weight);
                }
            }
        }
        return Math.max(weight, 0);
    }

    static int calculateWarmupWeight(int uptime, int warmup, int weight) {
        // 预热期内权重 = (uptime / warmup) * weight
        // 逐渐增加，避免新服务启动瞬间被大流量压垮
        int ww = (int) ((float) uptime / ((float) warmup / (float) weight));
        return ww < 1 ? 1 : (Math.min(ww, weight));
    }
}
```

### 7.3 RoundRobinLoadBalance（平滑加权轮询）

```java
public class RoundRobinLoadBalance extends AbstractLoadBalance {

    // 每个 methodKey → Invoker 的 WeightedRoundRobin 状态
    private final ConcurrentMap<String, ConcurrentMap<String, WeightedRoundRobin>>
        methodWeightMap = new ConcurrentHashMap<>();

    @Override
    protected <T> Invoker<T> doSelect(List<Invoker<T>> invokers, URL url, Invocation invocation) {
        String key = invokers.get(0).getUrl().getServiceKey() + "." + invocation.getMethodName();
        ConcurrentMap<String, WeightedRoundRobin> map = methodWeightMap.computeIfAbsent(
            key, k -> new ConcurrentHashMap<>());

        int totalWeight = 0;
        long maxCurrent = Long.MIN_VALUE;
        long now = System.currentTimeMillis();
        Invoker<T> selectedInvoker = null;
        WeightedRoundRobin selectedWRR = null;

        // ① 遍历所有 Invoker
        for (Invoker<T> invoker : invokers) {
            String identifyString = invoker.getUrl().toIdentityString();
            int weight = getWeight(invoker, invocation);
            WeightedRoundRobin wrr = map.computeIfAbsent(
                identifyString, k -> new WeightedRoundRobin());
            wrr.setWeight(weight);

            // ② 核心：current += weight
            long cur = wrr.increaseCurrent();
            // ③ 更新最后使用时间
            wrr.setLastUpdate(now);

            // ④ 找到 current 最大的
            if (cur > maxCurrent) {
                maxCurrent = cur;
                selectedInvoker = invoker;
                selectedWRR = wrr;
            }
            totalWeight += weight;
        }

        // ⑤ 清理过期的 WeightedRoundRobin
        if (invokers.size() != map.size()) {
            map.entrySet().removeIf(item -> {
                return now - item.getValue().getLastUpdate() > RECYCLE_PERIOD;
            });
        }

        // ⑥ 核心：current -= totalWeight
        if (selectedWRR != null) {
            selectedWRR.sel(totalWeight);
            return selectedInvoker;
        }

        return invokers.get(0);
    }

    protected static class WeightedRoundRobin {
        private int weight;           // 配置权重
        private AtomicLong current = new AtomicLong(0);  // 当前权重
        private long lastUpdate;      // 最后更新时间

        long increaseCurrent() {
            // current = current + weight
            return current.addAndGet(weight);
        }

        void sel(int totalWeight) {
            // current = current - totalWeight
            current.addAndGet(-1 * totalWeight);
        }
    }
}
```

**平滑加权轮询算法图解：**

```
假设 3 个 Provider，权重 A=5, B=1, C=1，总权重 7

每次选择时：
  ① 每个 Invoker: current += weight
  ② 选择 current 最大的
  ③ 被选中的: current -= totalWeight

迭代过程：
┌────┬───────────────────────────┬───────────────────────────┬───────────────────────────┬────────┐
│轮次 │ A(current)                 │ B(current)                 │ C(current)                 │ 选中    │
├────┼───────────────────────────┼───────────────────────────┼───────────────────────────┼────────┤
│ 初始 │ 0                           │ 0                           │ 0                           │        │
│  1  │ 0+5=5 → max → 5-7=-2        │ 0+1=1                       │ 0+1=1                       │  A     │
│  2  │ -2+5=3 → max → 3-7=-4       │ 1+1=2                       │ 1+1=2                       │  A     │
│  3  │ -4+5=1                       │ 2+1=3 → max → 3-7=-4        │ 2+1=3                       │  B     │
│  4  │ 1+5=6 → max → 6-7=-1        │ -4+1=-3                     │ 3+1=4                       │  A     │
│  5  │ -1+5=4                       │ -3+1=-2                     │ 4+1=5 → max → 5-7=-2        │  C     │
│  6  │ 4+5=9 → max → 9-7=2         │ -2+1=-1                     │ -2+1=-1                     │  A     │
│  7  │ 2+5=7 → max → 7-7=0         │ -1+1=0                      │ -1+1=0                      │  A     │
└────┴───────────────────────────┴───────────────────────────┴───────────────────────────┴────────┘

7 次选择结果：A A B A C A A
A 出现 5 次，B 出现 1 次，C 出现 1 次 → 5:1:1，与权重比例一致
且分布均匀，不会集中调用某一个
```

### 7.4 LeastActiveLoadBalance（最小活跃数）

```java
public class LeastActiveLoadBalance extends AbstractLoadBalance {

    @Override
    protected <T> Invoker<T> doSelect(List<Invoker<T>> invokers, URL url, Invocation invocation) {
        int length = invokers.size();
        int leastActive = -1;       // 最小活跃数
        int leastCount = 0;         // 最小活跃数相同的 Invoker 个数
        int[] leastIndexes = new int[length];  // 最小活跃数 Invoker 的索引
        int totalWeight = 0;        // 总权重
        int firstWeight = 0;        // 第一个权重
        boolean sameWeight = true;  // 权重是否相同

        // ① 遍历所有 Invoker，找最小活跃数
        for (int i = 0; i < length; i++) {
            Invoker<T> invoker = invokers.get(i);
            // 获取活跃数（正在处理的请求数）
            int active = RpcStatus.getStatus(
                invoker.getUrl(), invocation.getMethodName()).getActive();
            int weight = getWeight(invoker, invocation);

            // ② 如果比当前最小活跃数更小
            if (leastActive == -1 || active < leastActive) {
                leastActive = active;
                leastCount = 1;
                leastIndexes[0] = i;
                totalWeight = weight;
                firstWeight = weight;
                sameWeight = true;
            }
            // ③ 如果等于当前最小活跃数
            else if (active == leastActive) {
                leastIndexes[leastCount++] = i;
                totalWeight += weight;
                if (sameWeight && weight != firstWeight) {
                    sameWeight = false;
                }
            }
        }

        // ④ 如果只有一个最小活跃数的 Invoker，直接返回
        if (leastCount == 1) {
            return invokers.get(leastIndexes[0]);
        }

        // ⑤ 多个最小活跃数相同，按权重随机选择
        if (!sameWeight && totalWeight > 0) {
            int offsetWeight = ThreadLocalRandom.current().nextInt(totalWeight);
            for (int i = 0; i < leastCount; i++) {
                int leastIndex = leastIndexes[i];
                offsetWeight -= getWeight(invokers.get(leastIndex), invocation);
                if (offsetWeight < 0) {
                    return invokers.get(leastIndex);
                }
            }
        }

        // ⑥ 权重相同，随机
        return invokers.get(leastIndexes[ThreadLocalRandom.current().nextInt(leastCount)]);
    }
}
```

**活跃数统计原理：**

```java
// RpcStatus 记录每个方法的调用状态
public class RpcStatus {
    private final ConcurrentMap<String, RpcStatus> SERVICE_STATISTICS = new ConcurrentHashMap<>();
    private final ConcurrentMap<String, ConcurrentMap<String, RpcStatus>> METHOD_STATISTICS = ...;

    private final AtomicLong active = new AtomicLong();

    // 开始调用前 active+1
    public static void beginCount(URL url, String methodName) {
        RpcStatus status = getMethodStatus(url, methodName);
        status.active.incrementAndGet();
    }

    // 调用结束后 active-1
    public static void endCount(URL url, String methodName, long elapsed, boolean succeeded) {
        RpcStatus status = getMethodStatus(url, methodName);
        status.active.decrementAndGet();
        status.total.incrementAndGet();
        status.totalElapsed.addAndGet(elapsed);
        if (!succeeded) {
            status.failed.incrementAndGet();
        }
    }

    public int getActive() {
        return active.intValue();
    }
}
```

**LeastActive 的工作原理：** 活跃数表示某个 Provider 正在处理的请求数量。选择活跃数最小的 Provider，意味着把请求分配给最空闲的 Provider，实现更均衡的负载分配。适合处理速度差异较大的 Provider 集群。

### 7.5 ConsistentHashLoadBalance（一致性哈希）

```java
public class ConsistentHashLoadBalance extends AbstractLoadBalance {

    // 每个 method → ConsistentHashSelector
    private final ConcurrentMap<String, ConsistentHashSelector<?>> selectors =
        new ConcurrentHashMap<>();

    @Override
    protected <T> Invoker<T> doSelect(List<Invoker<T>> invokers, URL url, Invocation invocation) {
        String methodName = RpcUtils.getMethodName(invocation);
        String key = invokers.get(0).getUrl().getServiceKey() + "." + methodName;

        // ① 获取或创建 Selector
        int identityHashCode = System.identityHashCode(invokers);
        ConsistentHashSelector<T> selector = (ConsistentHashSelector<T>) selectors.get(key);
        if (selector == null || selector.identityHashCode != identityHashCode) {
            selectors.put(key, new ConsistentHashSelector<T>(invokers, methodName, identityHashCode));
            selector = (ConsistentHashSelector<T>) selectors.get(key);
        }

        // ② 选择 Invoker
        return selector.select(invocation);
    }

    private static final class ConsistentHashSelector<T> {
        // 虚拟节点 → Invoker 的 TreeMap
        private final TreeMap<Long, Invoker<T>> virtualInvokers = new TreeMap<>();
        private final int replicaNumber;  // 虚拟节点数（默认 160）
        private final int identityHashCode;
        private final int[] argumentIndex;  // 参与哈希的参数索引

        ConsistentHashSelector(List<Invoker<T>> invokers, String methodName, int identityHashCode) {
            this.virtualInvokers = new TreeMap<>();
            this.identityHashCode = identityHashCode;

            // 获取虚拟节点数配置
            URL url = invokers.get(0).getUrl();
            this.replicaNumber = url.getMethodParameter(methodName, HASH_NODES, 160);
            // 获取参与哈希计算的参数索引
            String[] indexArray = url.getMethodParameter(methodName, HASH_ARGUMENTS, "0").split(",");
            argumentIndex = new int[indexArray.length];
            for (int i = 0; i < indexArray.length; i++) {
                argumentIndex[i] = Integer.parseInt(indexArray[i]);
            }

            // ③ 为每个 Invoker 创建虚拟节点
            for (Invoker<T> invoker : invokers) {
                String address = invoker.getUrl().getAddress();
                for (int i = 0; i < replicaNumber / 4; i++) {
                    // MD5 哈希
                    byte[] digest = md5(address + i);
                    // 每个 digest 生成 4 个虚拟节点
                    for (int h = 0; h < 4; h++) {
                        long m = hash(digest, h);
                        virtualInvokers.put(m, invoker);
                    }
                }
            }
        }

        public Invoker<T> select(Invocation invocation) {
            // ① 根据参数生成 key
            String key = toKey(invocation.getArguments());
            // ② MD5 哈希
            byte[] digest = md5(key);
            // ③ 一致性哈希选择
            return selectForKey(hash(digest, 0));
        }

        private String toKey(Object[] args) {
            StringBuilder buf = new StringBuilder();
            for (int i : argumentIndex) {
                if (i >= 0 && i < args.length) {
                    buf.append(args[i]);
                }
            }
            return buf.toString();
        }

        private Invoker<T> selectForKey(long hash) {
            // ① 在 TreeMap 中找到 >= hash 的第一个节点
            Map.Entry<Long, Invoker<T>> entry = virtualInvokers.ceilingEntry(hash);
            // ② 如果没有更大的，回到第一个节点（环形）
            if (entry == null) {
                entry = virtualInvokers.firstEntry();
            }
            return entry.getValue();
        }
    }
}
```

**一致性哈希原理图：**

```
虚拟节点环（0 ~ 2^32-1）：

        0
        │
   Invoker A 虚拟节点群 (160个)
   ├── hash(A+0) → A
   ├── hash(A+1) → A
   ├── hash(A+2) → A
   ├── ...
   └── hash(A+39) → A
        │
        │  哈希空间
        │
   Invoker B 虚拟节点群 (160个)
   ├── hash(B+0) → B
   ├── ...
   └── hash(B+39) → B
        │
        │
   Invoker C 虚拟节点群 (160个)
   ├── hash(C+0) → C
   ├── ...
   └── hash(C+39) → C
        │
   2^32-1

请求来了：
  对参数做 MD5 哈希 → 得到一个 hash 值
  在 TreeMap 中找 >= hash 的第一个虚拟节点
  → 返回该虚拟节点对应的 Invoker

特点：
  ① 相同参数的请求总是发到同一个 Provider（粘性路由）
  ② Provider 增减时，只有部分请求迁移（不像简单取模全部重新分配）
  ③ 虚拟节点解决数据倾斜问题
```

### 7.6 ShortestResponseLoadBalance（Dubbo 2.7+）

选择响应时间最短的 Provider，基于滑动窗口统计：

```java
public class ShortestResponseLoadBalance extends AbstractLoadBalance {

    @Override
    protected <T> Invoker<T> doSelect(List<Invoker<T>> invokers, URL url, Invocation invocation) {
        int length = invokers.size();
        // 最短响应时间
        long shortestResponse = Long.MAX_VALUE;
        // 最短响应时间相同的 Invoker 个数
        int shortestCount = 0;
        int[] shortestIndexes = new int[length];
        // 各 Invoker 的权重
        int[] weights = new int[length];
        int totalWeight = 0;
        int firstWeight = 0;
        boolean sameWeight = true;

        for (int i = 0; i < length; i++) {
            Invoker<T> invoker = invokers.get(i);
            RpcStatus rpcStatus = RpcStatus.getStatus(invoker.getUrl(), invocation.getMethodName());

            // ① 计算估算响应时间 = 成功调用次数 × 平均响应时间
            //    成功调用次数 = succeededCount
            //    平均响应时间 = totalElapsed / succeededCount
            //    估算响应时间 = succeededCount * (totalElapsed / succeededCount) = totalElapsed
            //    但实际上考虑了活跃数
            long succeeded = rpcStatus.getSucceeded();
            long succeededElapsed = rpcStatus.getSucceededElapsed();
            int active = rpcStatus.getActive();
            long estimateResponse = active > 0 ?
                (succeededElapsed * active) / succeeded : 0;

            int weight = getWeight(invoker, invocation);
            weights[i] = weight;

            // ② 找最短响应时间
            if (estimateResponse < shortestResponse) {
                shortestResponse = estimateResponse;
                shortestCount = 1;
                shortestIndexes[0] = i;
                totalWeight = weight;
                firstWeight = weight;
                sameWeight = true;
            } else if (estimateResponse == shortestResponse) {
                shortestIndexes[shortestCount++] = i;
                totalWeight += weight;
                if (sameWeight && weight != firstWeight) {
                    sameWeight = false;
                }
            }
        }

        // ③ 只有一个最短，直接返回
        if (shortestCount == 1) {
            return invokers.get(shortestIndexes[0]);
        }

        // ④ 多个相同，按权重随机
        if (!sameWeight && totalWeight > 0) {
            int offsetWeight = ThreadLocalRandom.current().nextInt(totalWeight);
            for (int i = 0; i < shortestCount; i++) {
                int leastIndex = shortestIndexes[i];
                offsetWeight -= weights[leastIndex];
                if (offsetWeight < 0) {
                    return invokers.get(leastIndex);
                }
            }
        }

        // ⑤ 权重相同，随机
        return invokers.get(shortestIndexes[ThreadLocalRandom.current().nextInt(shortestCount)]);
    }
}
```

### 7.7 负载均衡器选择时机

```
负载均衡器的选择发生在 ClusterInvoker 中：

AbstractClusterInvoker.invoke()
    │
    ├── ① initLoadBalance()
    │       │
    │       │  从 URL 中获取 loadbalance 参数
    │       │  默认 "random" → RandomLoadBalance
    │       │
    │       │  ExtensionLoader.getExtensionLoader(LoadBalance.class)
    │       │      .getExtension(loadbalanceName)
    │       │
    │       │  也可以在方法级别配置：
    │       │  <dubbo:reference>
    │       │      <dubbo:method name="sayHello" loadbalance="roundrobin"/>
    │       │  </dubbo:reference>
    │       │
    │       └── 返回 LoadBalance 实例
    │
    ├── ② select(loadbalance, invocation, invokers, selected)
    │       │
    │       │  调用 loadbalance.select(invokers, url, invocation)
    │       │  → 根据策略选择一个 Invoker
    │       │
    │       └── 返回选中的 Invoker
    │
    └── ③ invoker.invoke(invocation)
            执行选中的 Invoker
```

**5 种负载均衡对比：**

| 策略 | 原理 | 优势 | 劣势 | 适用场景 |
|------|------|------|------|----------|
| Random | 加权随机 | 简单高效 | 可能不均匀 | 默认策略，通用 |
| RoundRobin | 平滑加权轮询 | 均匀分布 | 计算稍复杂 | 需要严格均匀分配 |
| LeastActive | 最小活跃数 | 自适应负载 | 需要统计活跃数 | Provider 性能差异大 |
| ConsistentHash | 一致性哈希 | 相同参数路由到同一 Provider | 增减节点有迁移 | 有状态请求/缓存 |
| ShortestResponse | 最短响应时间 | 自适应最快 | 依赖统计准确 | 响应时间敏感场景 |

---

## 第八部分 服务治理

### 8.1 注册中心集成（ZookeeperRegistry）

#### 8.1.1 Registry 体系

```
RegistryFactory（SPI 接口）
    │
    ├── @Adaptive("protocol")
    │   根据 URL 的 protocol 选择注册中心实现
    │
    ├── ZookeeperRegistryFactory   → ZookeeperRegistry
    ├── NacosRegistryFactory       → NacosRegistry
    ├── RedisRegistryFactory       → RedisRegistry
    ├── MulticastRegistryFactory   → MulticastRegistry
    └── EtcdRegistryFactory        → EtcdRegistry

Registry（接口）
    │
    ├── 注册：register(url)
    ├── 注销：unregister(url)
    ├── 订阅：subscribe(url, listener)
    ├── 取消订阅：unsubscribe(url, listener)
    └── 查询：lookup(url)

AbstractRegistry → FailbackRegistry → ZookeeperRegistry
```

#### 8.1.2 ZookeeperRegistry 源码

```java
public class ZookeeperRegistry extends FailbackRegistry {

    private final ZookeeperClient zkClient;

    public ZookeeperRegistry(URL url, ZookeeperTransporter zookeeperTransporter) {
        super(url);
        // ① 连接 Zookeeper
        zkClient = zookeeperTransporter.connect(url);
        // ② 添加状态监听
        zkClient.addStateListener(state -> {
            if (state == StateListener.RECONNECTED) {
                // 重连后恢复注册和订阅
                recover();
            }
        });
    }

    // ========== 注册 ==========
    @Override
    public void doRegister(URL url) {
        try {
            // 创建临时节点：/dubbo/interface/providers/url
            zkClient.create(toUrlPath(url), url.getParameter(DYNAMIC_KEY, true));
        } catch (Throwable e) {
            throw new RpcException("Failed to register " + url + " to zookeeper " + getUrl()
                + ", cause: " + e.getMessage(), e);
        }
    }

    @Override
    public void doUnregister(URL url) {
        try {
            // 删除节点
            zkClient.delete(toUrlPath(url));
        } catch (Throwable e) {
            throw new RpcException("Failed to unregister " + url + " to zookeeper " + getUrl()
                + ", cause: " + e.getMessage(), e);
        }
    }

    // ========== 订阅 ==========
    @Override
    public void doSubscribe(final URL url, final NotifyListener listener) {
        try {
            if (ANY_VALUE.equals(url.getServiceInterface())) {
                // ① 订阅所有接口（全量订阅）
                String root = toRootPath();
                ConcurrentMap<NotifyListener, ChildListener> listeners = ...;
                ChildListener zkListener = listeners.get(listener);
                if (zkListener == null) {
                    zkListener = (parentPath, currentChilds) -> {
                        for (String child : currentChilds) {
                            child = URL.decode(child);
                            // 订阅每个接口
                            subscribe(url, listener);
                        }
                    };
                    listeners.put(listener, zkListener);
                }
                zkClient.addDataListener(root, zkListener);
            } else {
                // ② 订阅特定接口
                //    监听 providers / configurators / routers 三个目录
                for (String path : toCategoriesPath(url)) {
                    ConcurrentMap<NotifyListener, ChildListener> listeners = ...;
                    ChildListener zkListener = listeners.get(listener);
                    if (zkListener == null) {
                        zkListener = (parentPath, currentChilds) -> {
                            // 子节点变化时通知 listener
                            ZookeeperRegistry.this.notify(url, listener,
                                toUrlsWithEmpty(url, parentPath, currentChilds));
                        };
                        listeners.put(listener, zkListener);
                    }
                    // 添加 Zookeeper 子节点监听
                    zkClient.addChildListener(path, zkListener);

                    // 首次订阅，立即获取当前节点列表并通知
                    List<String> children = zkClient.getChildren(path);
                    if (children != null) {
                        notify(url, listener, toUrlsWithEmpty(url, path, children));
                    }
                }
            }
        } catch (Throwable e) {
            throw new RpcException("Failed to subscribe " + url + " to zookeeper " + getUrl()
                + ", cause: " + e.getMessage(), e);
        }
    }

    // ========== 通知 ==========
    // 继承自 AbstractRegistry
    protected void notify(URL url, NotifyListener listener, List<URL> urls) {
        // ① 过滤和排序 URL
        // ② 通知 listener（即 RegistryDirectory）
        listener.notify(urls);
    }
}
```

#### 8.1.3 FailbackRegistry — 失败重试

```java
public abstract class FailbackRegistry extends AbstractRegistry {

    // 注册失败的 URL 集合（定时重试）
    private final Set<URL> failedRegistered = new ConcurrentHashSet<>();
    // 注销失败的 URL 集合
    private final Set<URL> failedUnregistered = new ConcurrentHashSet<>();
    // 订阅失败的 URL → Listener 集合
    private final ConcurrentMap<URL, Set<NotifyListener>> failedSubscribed = ...;
    // 取消订阅失败的
    private final ConcurrentMap<URL, Set<NotifyListener>> failedUnsubscribed = ...;

    private volatile ScheduledFuture<?> retryFuture;

    public FailbackRegistry(URL url) {
        super(url);
        // 启动定时重试任务（默认 5 秒）
        this.retryFuture = retryExecutor.scheduleWithFixedDelay(
            this::retry, RETRY_PERIOD, RETRY_PERIOD, TimeUnit.MILLISECONDS);
    }

    @Override
    public void register(URL url) {
        // ① 先从失败集合中移除
        failedRegistered.remove(url);
        try {
            // ② 执行注册
            doRegister(url);
        } catch (Exception e) {
            // ③ 失败则加入重试集合
            failedRegistered.add(url);
            logger.warn("Failed to register, will retry later, ...");
        }
    }

    private void retry() {
        // 重试注册
        if (!failedRegistered.isEmpty()) {
            Set<URL> failed = new HashSet<>(failedRegistered);
            for (URL url : failed) {
                try {
                    doRegister(url);
                    failedRegistered.remove(url);
                } catch (Exception e) {
                    // 仍然失败，等下次重试
                }
            }
        }
        // 重试订阅...
    }
}
```

### 8.2 路由规则（Router / RouterChain）

#### 8.2.1 Router 体系

```
Router（接口）
    │
    ├── ConditionRouter      ← 条件路由（最常用）
    ├── ScriptRouter         ← 脚本路由（JavaScript/Groovy）
    ├── TagRouter            ← 标签路由
    ├── AppRouter            ← 应用级路由
    └── ServiceRouter        ← 服务级路由

RouterFactory（SPI 接口）
    │
    ├── @SPI("condition")
    ├── ConditionRouterFactory   → ConditionRouter
    ├── ScriptRouterFactory      → ScriptRouter
    └── TagRouterFactory         → TagRouter
```

#### 8.2.2 ConditionRouter — 条件路由

条件路由是最常用的路由规则，支持类似表达式的语法：

```properties
# 示例：来自 10.20.153.* 的消费者只调用 10.20.153.* 的 Provider
=> host != 10.20.153.*

# 示例：黑名单
host = 10.20.153.10 =>

# 示例：读写分离
method = find*,get*,query* => host = 10.20.153.*
method = save*,update*,delete* => host = 10.20.153.11
```

**ConditionRouter.route() 源码：**

```java
public class ConditionRouter extends AbstractRouter {

    // 匹配规则（when 条件 → Consumer 侧）
    protected Map<String, MatchPair> whenCondition;
    // 过滤规则（then 条件 → Provider 侧）
    protected Map<String, MatchPair> thenCondition;

    @Override
    public <T> List<Invoker<T>> route(List<Invoker<T>> invokers, URL url,
                                       Invocation invocation) throws RpcException {
        if (!enabled) {
            return invokers;
        }

        // ① 检查是否匹配 when 条件（Consumer 侧条件）
        if (matchWhen(invocation, url)) {
            // ② 匹配 when 条件，执行 then 过滤
            List<Invoker<T>> result = new ArrayList<>();
            for (Invoker<T> invoker : invokers) {
                if (matchThen(invoker.getUrl(), url)) {
                    result.add(invoker);
                }
            }
            if (!result.isEmpty()) {
                return result;
            } else if (force) {
                // 强制路由，即使没有匹配的也返回空（拒绝调用）
                return result;
            }
        }

        // ③ 不匹配 when 条件，不过滤
        return invokers;
    }

    private boolean matchWhen(Invocation invocation, URL url) {
        if (whenCondition == null || whenCondition.isEmpty()) {
            // 没有 when 条件 = 匹配所有 Consumer
            return true;
        }
        return matchCondition(whenCondition, invocation, url);
    }

    private boolean matchThen(URL providerUrl, URL consumerUrl) {
        if (thenCondition == null || thenCondition.isEmpty()) {
            // 没有 then 条件 = 不过滤任何 Provider
            return false;
        }
        return matchCondition(thenCondition, providerUrl, consumerUrl);
    }

    /**
     * 条件匹配
     * MatchPair 包含 matches（匹配集合）和 mismatches（不匹配集合）
     */
    private boolean matchCondition(Map<String, MatchPair> condition, URL url) {
        for (Map.Entry<String, MatchPair> entry : condition.entrySet()) {
            String key = entry.getKey();
            MatchPair pair = entry.getValue();

            // 获取 URL 中对应 key 的值
            String sample = url.getParameter(key);
            if (sample != null) {
                // 匹配检查
                if (!pair.isMatch(sample, url)) {
                    return false;
                }
            } else {
                // key 不存在于 URL 中
                if (!pair.isEmpty()) {
                    return false;
                }
            }
        }
        return true;
    }

    static class MatchPair {
        Set<String> matches = new HashSet<>();     // 匹配集合
        Set<String> mismatches = new HashSet<>();  // 不匹配集合

        boolean isMatch(String value, URL url) {
            // ① 先检查 mismatches（不匹配集合）
            if (!mismatches.isEmpty() && mismatches.contains(value)) {
                return false;
            }
            // ② 再检查 matches（匹配集合）
            if (!matches.isEmpty()) {
                return matches.contains(value);
            }
            // ③ matches 为空，mismatches 不包含，默认匹配
            return true;
        }
    }
}
```

**条件路由语法解析：**

```
路由规则格式：when条件 => then条件

when 条件（Consumer 侧）：
  - host：消费者 IP
  - application：消费者应用名
  - method：调用方法名
  - group：消费组
  - version：消费版本

then 条件（Provider 侧）：
  - host：提供者 IP
  - application：提供者应用名
  - port：提供者端口
  - protocol：提供者协议
  - tag：提供者标签

操作符：
  =   精确匹配
  !=  不等于
  >   大于
  <   小于
  ,   多值分隔
  $   通配符

示例：
  host = 10.20.153.*,10.20.154.*  → IP 匹配两个网段
  method != get*                   → 方法名不以 get 开头
  host = $host                     → Consumer IP = Provider IP（同机房路由）
```

#### 8.2.3 RouterChain — 路由链

```java
public class RouterChain<T> {

    private final List<Router> routers;

    public List<Invoker<T>> route(URL url, Invocation invocation, List<Invoker<T>> invokers) {
        List<Invoker<T>> finalInvokers = invokers;
        // 依次执行所有 Router 的过滤
        for (Router router : routers) {
            if (router.isRuntime()) {
                finalInvokers = router.route(finalInvokers, url, invocation);
            }
        }
        return finalInvokers;
    }

    public void addRouters(List<Router> routers) {
        this.routers.addAll(routers);
        // 按 priority 排序
        Collections.sort(this.routers, Comparator.comparingInt(Router::getPriority));
    }
}
```

**路由链执行流程：**

```
RegistryDirectory.list(invocation)
    │
    ├── 获取所有 Invoker（从 urlInvokerMap）
    │
    └── RouterChain.route(url, invocation, invokers)
            │
            ├── TagRouter.route()
            │       根据标签过滤（如 gray 标签只路由到 gray Provider）
            │
            ├── AppRouter.route()
            │       应用级条件路由
            │
            ├── ServiceRouter.route()
            │       服务级条件路由
            │
            └── CustomRouter.route()
                    用户自定义路由规则

    最终返回过滤后的 Invoker 列表 → 交给 LoadBalance 选择
```

### 8.3 配置中心（ConfigurationUtils / DynamicConfiguration）

```
DynamicConfiguration（SPI 接口）
    │
    ├── ZookeeperDynamicConfiguration
    ├── NacosDynamicConfiguration
    ├── ApolloDynamicConfiguration
    └── EtcdDynamicConfiguration
```

**配置覆盖机制：**

```java
// Dubbo 支持多层次的配置，优先级从高到低：
// 1. JVM 参数（-D）
// 2. 动态配置中心（覆盖规则）
// 3. 应用级配置（dubbo.properties）
// 4. 组件级配置（@DubboService / @DubboReference）
// 5. 全局配置（dubbo:application / dubbo:registry）
// 6. 默认值

// 配置覆盖 URL（override://）
// 注册中心推送的覆盖配置会修改 Provider URL
public class OverrideListener implements NotifyListener {
    @Override
    public void notify(List<URL> urls) {
        // 解析 override:// URL
        for (URL overrideUrl : urls) {
            // 合并覆盖参数到 Provider URL
            URL newUrl = providerUrl.addParameters(overrideUrl.getParameters());
            // 重新导出或更新 Invoker
        }
    }
}
```

### 8.4 元数据中心（MetadataReport）

Dubbo 2.7+ 引入元数据中心，将服务元数据从注册中心分离：

```java
// MetadataReport 接口
public interface MetadataReport {
    void storeProviderMetadata(URL url, FullServiceDefinition serviceDefinition);
    void storeConsumerMetadata(URL url, FullServiceDefinition serviceDefinition);
    ServiceDefinition getServiceDefinition(String serviceKey);
    void unpublishProvider(URL providerUrl);
}

// 元数据存储内容（FullServiceDefinition）：
{
    "url": "dubbo://192.168.1.10:20880/com.example.UserService",
    "parameters": {
        "version": "1.0.0",
        "group": "dev",
        "timeout": 1000,
        "retries": 2
    },
    "methods": [
        {
            "name": "sayHello",
            "parameterTypes": ["java.lang.String"],
            "returnType": "java.lang.String"
        }
    ]
}
```

**注册中心与元数据中心的分离：**

```
Dubbo 2.6 之前：
  注册中心存储全部信息：
    /dubbo/interface/providers/dubbo://ip:port?timeout=1000&retries=2&methods=sayHello,getUser...

Dubbo 2.7+：
  注册中心只存储精简信息：
    /dubbo/interface/providers/dubbo://ip:port?version=1.0.0

  元数据中心存储完整信息：
    /dubbo/metadata/interface/provider/dubbo://ip:port
    → 完整的方法签名、参数类型、配置等

好处：
  ① 注册中心数据量大幅减少，降低 Zookeeper 压力
  ② 元数据中心可以独立部署，支持更丰富的元数据
  ③ 为应用级服务发现做准备
```

### 8.5 应用级服务发现（Dubbo 3.x）

Dubbo 3.x 将服务注册从**接口级**升级为**应用级**：

```
Dubbo 2.x 接口级服务发现：
  Provider 注册：
    /dubbo/com.example.UserService/providers/dubbo://192.168.1.10:20880/...
    /dubbo/com.example.OrderService/providers/dubbo://192.168.1.10:20880/...
    /dubbo/com.example.ProductService/providers/dubbo://192.168.1.10:20880/...

  一个应用有 N 个接口 = N 条注册数据

Dubbo 3.x 应用级服务发现：
  Provider 注册：
    /services/user-service-provider/192.168.1.10:20880
    → 应用级注册，每个应用只注册一条数据

  元数据映射（接口 → 应用）：
    MetadataReport 存储：
      com.example.UserService → user-service-provider
      com.example.OrderService → user-service-provider
      com.example.ProductService → user-service-provider

  Consumer 发现流程：
    ① Consumer 需要调用 UserService
    ② 从元数据中心查询：UserService 属于 user-service-provider 应用
    ③ 从注册中心查询 user-service-provider 的实例列表
    ④ 获取实例列表后，再从元数据中心获取该应用的接口映射
    ⑤ 得到最终可用的 Provider URL
```

**应用级服务发现的优势：**

```
┌────────────────┬────────────────────────┬────────────────────────────┐
│       维度      │    Dubbo 2.x（接口级）   │     Dubbo 3.x（应用级）      │
├────────────────┼────────────────────────┼────────────────────────────┤
│ 注册数据量      │ N 接口 = N 条            │ N 接口 = 1 条               │
│ 注册中心压力    │ 大                      │ 小                          │
│ 与 Spring Cloud │ 不兼容                  │ 兼容（相同的服务发现模型）     │
│ Kubernetes 对齐 │ 不对齐                  │ 对齐（应用级）               │
│ Service Mesh   │ 不支持                  │ 支持                         │
│ 迁移成本        │ -                      │ 有迁移工具                   │
└────────────────┴────────────────────────┴────────────────────────────┘
```

### 8.6 服务降级（mock 机制）

Dubbo 支持通过 `mock` 参数实现服务降级：

```java
// 配置方式
@DubboReference(mock = "true")
private UserService userService;

// mock = "true" → 查找 UserServiceMock 类（接口名 + Mock）
@DubboReference(mock = "force:return null")
private UserService userService;

// mock = "force:return null" → 强制返回 null，不发起远程调用
// mock = "fail:return null" → 调用失败后返回 null（默认）

// 自定义 mock 实现
@DubboReference(mock = "com.example.UserServiceMock")
private UserService userService;

public class UserServiceMock implements UserService {
    @Override
    public String sayHello(String name) {
        // 降级逻辑
        return "服务降级：hello " + name;
    }
}
```

**MockClusterInvoker — Mock 的实现入口：**

```java
public class MockClusterInvoker<T> implements Invoker<T> {

    @Override
    public Result invoke(Invocation invocation) throws RpcException {
        String mock = getUrl().getParameter(MOCK_KEY);

        if (mock != null && mock.trim().length() > 0 && !NORMAL_PROTOCOL.equals(mock)) {
            // ① 有 mock 配置
            if (mock.startsWith("force:")) {
                // ② 强制 mock：不发起远程调用
                return doMockInvoke(invocation, mock);
            } else {
                // ③ 失败后 mock：先正常调用
                try {
                    Result result = invoker.invoke(invocation);
                    return result;
                } catch (RpcException e) {
                    // 调用失败，走 mock 逻辑
                    return doMockInvoke(invocation, mock);
                }
            }
        }

        // ④ 无 mock，正常调用
        return invoker.invoke(invocation);
    }

    private Result doMockInvoke(Invocation invocation, String mock) {
        // 解析 mock 配置
        // "return null" → 返回 null
        // "throw" → 抛出异常
        // 自定义 Mock 类名 → 反射创建 Mock 实例，调用对应方法

        Result result = null;
        Invoker<T> mockInvoker = getMockInvoker(invocation, mock);
        if (mockInvoker != null) {
            result = mockInvoker.invoke(invocation);
        } else {
            result = AsyncRpcResult.newDefaultAsyncResult(
                "mock result is null", invocation);
        }
        return result;
    }
}
```

---

## 第九部分 Filter 责任链

### 9.1 ProtocolFilterWrapper — Filter 链入口

Filter 链的构建在 `ProtocolFilterWrapper` 中完成，它是 `DubboProtocol` 的 Wrapper：

```java
public class ProtocolFilterWrapper implements Protocol {

    private final Protocol protocol;

    public ProtocolFilterWrapper(Protocol protocol) {
        this.protocol = protocol;
    }

    @Override
    public <T> Exporter<T> export(Invoker<T> invoker) throws RpcException {
        if (UrlUtils.isRegistry(invoker.getUrl())) {
            // registry 协议不做 Filter 处理
            return protocol.export(invoker);
        }
        // ① 为 Provider 构建 Filter 链
        Invoker<T> invokerChain =
            buildInvokerChain(invoker, SERVICE_FILTER_KEY, SERVICE_PROVIDER);
        // ② 委托给 DubboProtocol
        return protocol.export(invokerChain);
    }

    @Override
    public <T> Invoker<T> refer(Class<T> type, URL url) throws RpcException {
        if (UrlUtils.isRegistry(url)) {
            return protocol.refer(type, url);
        }
        // ① 委托给 DubboProtocol 获取原始 Invoker
        Invoker<T> invoker = protocol.refer(type, url);
        // ② 为 Consumer 构建 Filter 链
        return buildInvokerChain(invoker, REFERENCE_FILTER_KEY, SERVICE_CONSUMER);
    }

    /**
     * 构建 Filter 责任链
     */
    private static <T> Invoker<T> buildInvokerChain(Invoker<T> invoker, String key, String group) {
        Invoker<T> last = invoker;

        // ① 获取所有激活的 Filter
        List<Filter> filters = ExtensionLoader.getExtensionLoader(Filter.class)
            .getActivateExtension(invoker.getUrl(), key, group);

        if (!filters.isEmpty()) {
            for (int i = filters.size() - 1; i >= 0; i--) {
                final Filter filter = filters.get(i);
                final Invoker<T> next = last;
                // ② 每个 Filter 包装成一个 Invoker
                last = new Invoker<T>() {
                    @Override
                    public Result invoke(Invocation invocation) throws RpcException {
                        // 调用 Filter.filter()，在 Filter 内部调用 next.invoke()
                        Result result = filter.invoke(next, invocation);
                        // 执行 onResponse 回调
                        if (result instanceof AsyncRpcResult) {
                            AsyncRpcResult asyncResult = (AsyncRpcResult) result;
                            asyncResult.thenApplyWithContext(r -> {
                                filter.onResponse(r, next, invocation);
                                return r;
                            });
                            return asyncResult;
                        } else {
                            return filter.onResponse(result, next, invocation);
                        }
                    }
                    // ... 其他方法委托给 invoker
                };
            }
        }
        return last;
    }
}
```

**Filter 链构建图解：**

```
原始 Invoker（DubboInvoker）
    │
    │  buildInvokerChain() 从后往前包装
    │
    ▼
Filter3 的 Invoker
    └── invoke() {
            filter3.invoke(next=Filter2Invoker, invocation)
            // Filter3 内部会调用 next.invoke() 执行 Filter2
        }
        │
        ▼
Filter2 的 Invoker
    └── invoke() {
            filter2.invoke(next=Filter1Invoker, invocation)
        }
        │
        ▼
Filter1 的 Invoker
    └── invoke() {
            filter1.invoke(next=DubboInvoker, invocation)
        }
        │
        ▼
原始 DubboInvoker.invoke()  ← 真正的网络调用
```

**执行顺序（从外到内，再从内到外）：**

```
ConsumerContextFilter.invoke()     ← 最外层
    │
    ├── FutureFilter.invoke()
    │       │
    │       ├── MonitorFilter.invoke()
    │       │       │
    │       │       ├── DubboInvoker.invoke()  ← 真正的 RPC 调用
    │       │       │       │
    │       │       │       └── 网络发送 → 等待响应 → 返回 Result
    │       │       │
    │       │       └── MonitorFilter.onResponse()  ← 统计上报
    │       │
    │       └── FutureFilter.onResponse()  ← 异步回调
    │
    └── ConsumerContextFilter.onResponse()  ← 清理上下文
```

### 9.2 内置 Filter 全解析

Dubbo 内置了大量 Filter，通过 @Activate 自动激活：

```properties
# META-INF/dubbo/internal/org.apache.dubbo.rpc.Filter
consumercontext=...ConsumerContextFilter    # Consumer 上下文传递
context=...ContextFilter                     # Provider 上下文接收
exception=...ExceptionFilter                 # Provider 异常处理
timeout=...TimeoutFilter                     # Provider 超时处理
monitor=...MonitorFilter                     # 调用监控
future=...FutureFilter                       # Consumer 异步回调
active=...ActiveLimitFilter                  # Provider 并发控制
accesslog=...AccessLogFilter                 # 访问日志
executelimit=...ExecuteLimitFilter           # Provider 执行限制
token=...TokenFilter                         # Provider Token 验证
tps=...TpsLimitFilter                        # TPS 限流
generic=...GenericFilter                     # 泛化调用
classloader=...ClassLoaderFilter             # 类加载器切换
echo=...EchoFilter                           # 回声测试
genericimpl=...GenericImplFilter             # 泛化实现
validation=...ValidationFilter               # 参数校验
cache=...CacheFilter                         # 结果缓存
trace=...TraceFilter                         # 链路追踪
```

### 9.3 ConsumerContextFilter — Consumer 侧上下文

```java
@Activate(group = CONSUMER, order = -100000)
public class ConsumerContextFilter implements Filter {

    @Override
    public Result invoke(Invoker<?> invoker, Invocation invocation) throws RpcException {
        // ① 设置 RPC 上下文
        RpcContext.getContext()
            .setInvoker(invoker)
            .setInvocation(invocation)
            // 设置本地和远程地址
            .setLocalAddress(NetUtils.getLocalHost(), 0)
            .setRemoteAddress(invoker.getUrl().getHost(), invoker.getUrl().getPort());

        // ② 传递 attachment（隐式参数）
        if (CollectionUtils.isNotEmptyMap(RpcContext.getContext().getObjectAttachments())) {
            invocation.addObjectAttachmentsIfAbsent(RpcContext.getContext().getObjectAttachments());
        }

        // ③ 传递 Consumer 应用信息
        invocation.setAttachment(CommonConstants.APPLICATION_KEY,
            RpcContext.getContext().getLocalServiceName());

        try {
            // ④ 继续调用链
            return invoker.invoke(invocation);
        } finally {
            // ⑤ 清理上下文
            RpcContext.removeContext();
            // 清理异步上下文
            RpcContext.removeServerContext();
        }
    }

    @Override
    public Result onResponse(Result result, Invoker<?> invoker, Invocation invocation) {
        // ⑥ 接收 Provider 返回的 attachment
        RpcContext.getServerContext().setObjectAttachments(result.getObjectAttachments());
        return result;
    }
}
```

### 9.4 ContextFilter — Provider 侧上下文

```java
@Activate(group = PROVIDER, order = -1000)
public class ContextFilter implements Filter {

    @Override
    public Result invoke(Invoker<?> invoker, Invocation invocation) throws RpcException {
        // ① 从 Invocation 中获取 attachment
        Map<String, Object> attachments = invocation.getObjectAttachments();
        if (attachments != null) {
            // 移除保留 key
            attachments.remove(PATH_KEY);
            attachments.remove(INTERFACE_KEY);
            attachments.remove(GROUP_KEY);
            attachments.remove(VERSION_KEY);
            attachments.remove(DUBBO_VERSION_KEY);
            attachments.remove(TOKEN_KEY);
            attachments.remove(TIMEOUT_KEY);
            // 保留 attachment 到本地上下文
            RpcContext.getContext().setObjectAttachments(attachments);
        }

        // ② 设置本地/远程地址
        RpcContext.getContext()
            .setInvoker(invoker)
            .setInvocation(invocation)
            .setLocalAddress(invoker.getUrl().getHost(), invoker.getUrl().getPort());

        // ③ 设置远程地址
        if (attachments != null) {
            // 从 attachment 中获取 Consumer 地址
            Object ip = attachments.get(REMOTE_ADDR_KEY);
            Object port = attachments.get(REMOTE_PORT_KEY);
            if (ip != null && port != null) {
                RpcContext.getContext().setRemoteAddress(ip.toString(), Integer.parseInt(port.toString()));
            }
        }

        try {
            // ④ 设置当前调用的上下文
            invocation.setAttachment(REMOTE_ADDR_KEY, RpcContext.getContext().getRemoteAddressString());
            // ⑤ 继续调用链
            return invoker.invoke(invocation);
        } finally {
            // ⑥ 清理
            RpcContext.removeContext();
            // ⑦ 将 Provider 的 attachment 回传给 Consumer
            result.addObjectAttachments(RpcContext.getServerContext().getObjectAttachments());
        }
    }
}
```

### 9.5 ExceptionFilter — Provider 异常处理

```java
@Activate(group = PROVIDER)
public class ExceptionFilter implements Filter, Filter.Listener {

    @Override
    public Result invoke(Invoker<?> invoker, Invocation invocation) throws RpcException {
        return invoker.invoke(invocation);
    }

    @Override
    public void onResponse(Result appResponse, Invoker<?> invoker, Invocation invocation) {
        if (appResponse.hasException() && GenericService.class != invoker.getInterface()) {
            try {
                Throwable exception = appResponse.getException();

                // ① 如果是 checked 异常，直接返回
                if (!(exception instanceof RuntimeException) &&
                    (exception instanceof Exception)) {
                    return;
                }

                // ② 如果方法签名声明了该异常，直接返回
                try {
                    Method method = invoker.getInterface().getMethod(
                        invocation.getMethodName(), invocation.getParameterTypes());
                    Class<?>[] exceptionClassses = method.getExceptionTypes();
                    for (Class<?> exceptionClass : exceptionClassses) {
                        if (exception.getClass().equals(exceptionClass)) {
                            return;
                        }
                    }
                } catch (NoSuchMethodException e) {
                    return;
                }

                // ③ 如果是 RPC 异常，直接返回
                if (exception instanceof RpcException) {
                    return;
                }

                // ④ 其他未声明异常：记录日志，包装成 RuntimeException
                //    避免暴露 Provider 的内部异常类给 Consumer
                logger.error("...", exception);
                appResponse.setException(new RuntimeException(
                    StringUtils.toString(exception)));
            } catch (Throwable e) {
                logger.warn("...", e);
            }
        }
    }
}
```

### 9.6 TimeoutFilter — Provider 超时处理

```java
@Activate(group = PROVIDER)
public class TimeoutFilter implements Filter, Filter.Listener {

    private static final String TIMEOUT_FILTER_START_TIME = "timeout_filter_start_time";

    @Override
    public Result invoke(Invoker<?> invoker, Invocation invocation) throws RpcException {
        // 记录开始时间
        long start = System.currentTimeMillis();
        invocation.setAttachment(TIMEOUT_FILTER_START_TIME, String.valueOf(start));
        return invoker.invoke(invocation);
    }

    @Override
    public void onResponse(Result result, Invoker<?> invoker, Invocation invocation) {
        String startTime = invocation.getAttachment(TIMEOUT_FILTER_START_TIME);
        if (startTime != null) {
            long elapsed = System.currentTimeMillis() - Long.parseLong(startTime);
            int timeout = invoker.getUrl().getMethodParameter(invocation.getMethodName(),
                TIMEOUT_KEY, DEFAULT_TIMEOUT);
            // 如果执行时间超过配置的超时时间，记录警告
            if (elapsed > timeout) {
                logger.warn("invoke time is too long, ...");
            }
        }
    }
}
```

### 9.7 自定义 Filter

```java
// 1. 实现 Filter 接口
@Activate(group = {PROVIDER, CONSUMER}, order = 100)
public class MyTraceFilter implements Filter, Filter.Listener {

    @Override
    public Result invoke(Invoker<?> invoker, Invocation invocation) throws RpcException {
        // 前置逻辑
        long start = System.currentTimeMillis();
        String traceId = generateTraceId();
        invocation.setAttachment("traceId", traceId);

        try {
            // 调用下一个 Invoker
            Result result = invoker.invoke(invocation);
            return result;
        } finally {
            // 后置逻辑
            long elapsed = System.currentTimeMillis() - start;
            log.trace("traceId={}, method={}, elapsed={}ms", traceId,
                invocation.getMethodName(), elapsed);
        }
    }

    @Override
    public void onResponse(Result result, Invoker<?> invoker, Invocation invocation) {
        // 响应处理
    }
}

// 2. 在 META-INF/dubbo/org.apache.dubbo.rpc.Filter 中注册
// myTrace=com.example.MyTraceFilter
```

---

## 第十部分 异步调用与线程池模型

### 10.1 Dispatcher 线程派发模型

Dubbo 的网络 IO 线程和业务线程是分离的，由 Dispatcher 决定在哪个线程处理消息：

```java
@SPI("all")
public interface Dispatcher {
    @Adaptive({Constants.DISPATCHER_KEY, "channel.handler"})
    ChannelHandler dispatch(ChannelHandler handler, URL url);
}
```

**5 种 Dispatcher 实现：**

```
┌──────────────────┬────────────────────────────────────────────────────────┐
│ Dispatcher        │ 行为                                                    │
├──────────────────┼────────────────────────────────────────────────────────┤
│ all（默认）        │ 所有消息都派发到线程池（包括连接/断开/读写/异常）              │
│ direct            │ 所有消息都在 IO 线程上直接处理（不使用线程池）                  │
│ message           │ 只有请求/响应消息派发到线程池，其他在 IO 线程处理               │
│ execution         │ 只有请求派发到线程池，响应在 IO 线程处理                      │
│ connection        │ 连接/断开事件派发到线程池，读写在 IO 线程处理                  │
└──────────────────┴────────────────────────────────────────────────────────┘
```

**AllChannelHandler — 默认的 all 派发器：**

```java
public class AllChannelHandler implements ChannelHandlerDelegate {

    private final ChannelHandler handler;
    private final ExecutorService executor;  // 线程池

    @Override
    public void received(Channel channel, Object message) throws RemotingException {
        // 将所有消息处理任务提交到线程池
        ExecutorService executor = getExecutorService();
        try {
            executor.execute(() -> {
                try {
                    handler.received(channel, message);
                } catch (Throwable t) {
                    // 异常处理
                }
            });
        } catch (Throwable t) {
            // 线程池满，拒绝策略
            if (t instanceof RejectedExecutionException) {
                throw new ExecutionException("Thread pool is EXHAUSTED! ...");
            }
        }
    }

    @Override
    public void connected(Channel channel) throws RemotingException {
        // 连接事件也提交到线程池
        ExecutorService executor = getExecutorService();
        executor.execute(() -> handler.connected(channel));
    }

    // ... 其他方法类似
}
```

### 10.2 ThreadPool 线程池体系

```java
@SPI("fixed")
public interface ThreadPool {
    @Adaptive({THREADPOOL_KEY})
    Executor getExecutor(URL url);
}
```

**3 种线程池实现：**

```java
// 1. FixedThreadPool（默认）— 固定大小线程池
public class FixedThreadPool implements ThreadPool {
    @Override
    public Executor getExecutor(URL url) {
        String name = url.getParameter(THREAD_NAME_KEY, DEFAULT_THREAD_NAME);
        int threads = url.getParameter(THREADS_KEY, DEFAULT_THREADS);  // 默认 200
        int queues = url.getParameter(QUEUES_KEY, DEFAULT_QUEUES);     // 默认 0（SynchronousQueue）
        return new ThreadPoolExecutor(threads, threads, 0, MILLISECONDS,
            queues == 0 ? new SynchronousQueue<Runnable>() :
            (queues < 0 ? new LinkedBlockingQueue<Runnable>() :
                          new LinkedBlockingQueue<Runnable>(queues)),
            new NamedInternalThreadFactory(name, true),
            new AbortPolicyWithReport(name, url));
    }
}

// 2. CachedThreadPool — 缓存线程池
public class CachedThreadPool implements ThreadPool {
    @Override
    public Executor getExecutor(URL url) {
        String name = url.getParameter(THREAD_NAME_KEY, DEFAULT_THREAD_NAME);
        int cores = url.getParameter(CORE_THREADS_KEY, DEFAULT_CORE_THREADS);  // 默认 0
        int threads = url.getParameter(THREADS_KEY, Integer.MAX_VALUE);         // 最大 Integer.MAX
        int queues = url.getParameter(QUEUES_KEY, DEFAULT_QUEUES);              // 默认 0
        int alive = url.getParameter(ALIVE_KEY, DEFAULT_ALIVE);                 // 默认 60s
        return new ThreadPoolExecutor(cores, threads, alive, MILLISECONDS,
            queues == 0 ? new SynchronousQueue<>() : ...,
            new NamedInternalThreadFactory(name, true),
            new AbortPolicyWithReport(name, url));
    }
}

// 3. EagerThreadPool — 优先创建新线程的线程池
public class EagerThreadPool implements ThreadPool {
    @Override
    public Executor getExecutor(URL url) {
        String name = url.getParameter(THREAD_NAME_KEY, DEFAULT_THREAD_NAME);
        int cores = url.getParameter(CORE_THREADS_KEY, DEFAULT_CORE_THREADS);
        int threads = url.getParameter(THREADS_KEY, Integer.MAX_VALUE);
        int queues = url.getParameter(QUEUES_KEY, DEFAULT_QUEUES);
        int alive = url.getParameter(ALIVE_KEY, DEFAULT_ALIVE);

        // TaskQueue 重写了 offer()，优先创建新线程而不是入队
        TaskQueue<Runnable> taskQueue = new TaskQueue<>(
            queues <= 0 ? 1 : queues);
        EagerThreadPoolExecutor executor = new EagerThreadPoolExecutor(
            cores, threads, alive, MILLISECONDS, taskQueue,
            new NamedInternalThreadFactory(name, true),
            new AbortPolicyWithReport(name, url));
        taskQueue.setExecutor(executor);
        return executor;
    }
}
```

**EagerThreadPool 的 TaskQueue — 优先创建新线程：**

```java
public class TaskQueue<R extends Runnable> extends LinkedBlockingQueue<Runnable> {

    private EagerThreadPoolExecutor executor;

    @Override
    public boolean offer(Runnable runnable) {
        // ① 如果线程数 < 最大线程数，返回 false 让 ThreadPoolExecutor 创建新线程
        if (executor.getPoolSize() < executor.getMaximumPoolSize()) {
            return false;  // 关键：返回 false → ThreadPoolExecutor 会创建新线程
        }
        // ② 如果线程数已达最大，放入队列
        return super.offer(runnable);
    }

    @Override
    public boolean offer(Runnable runnable, long timeout, TimeUnit unit) {
        // 同上
        if (executor.getPoolSize() < executor.getMaximumPoolSize()) {
            return false;
        }
        return super.offer(runnable, timeout, unit);
    }

    @Override
    public Runnable take() {
        // 如果所有线程都在忙，等待任务
        if (executor.getPoolSize() == executor.getMaximumPoolSize()) {
            return super.take();
        }
        // 否则用 poll 非阻塞获取
        Runnable runnable = super.poll();
        if (runnable == null) {
            // 队列为空，等待新任务
            // ...
        }
        return runnable;
    }
}
```

**线程池拒绝策略 — AbortPolicyWithReport：**

```java
public class AbortPolicyWithReport extends ThreadPoolExecutor.AbortPolicy {

    @Override
    public void rejectedExecution(Runnable r, ThreadPoolExecutor e) {
        // ① 记录线程池状态信息
        String msg = String.format(
            "Thread pool is EXHAUSTED! " +
            "Thread Name: %s, Pool Size: %d (active: %d, core: %d, max: %d, largest: %d), " +
            "Task: %d (completed: %d), " +
            "Executor status: (isShutdown: %s, isTerminated: %s, isTerminating: %s)",
            threadName, e.getPoolSize(), e.getActiveCount(),
            e.getCorePoolSize(), e.getMaximumPoolSize(), e.getLargestPoolSize(),
            e.getTaskCount(), e.getCompletedTaskCount(),
            e.isShutdown(), e.isTerminated(), e.isTerminating());

        // ② 输出线程转储（dump 线程栈）
        dumpJStack();

        // ③ 抛出异常
        throw new RejectedExecutionException(msg);
    }
}
```

### 10.3 ThreadlessExecutor（Dubbo 2.7+）

`ThreadlessExecutor` 是 Dubbo 2.7 引入的特殊线程池，用于**异步转同步**的场景：

```java
public class ThreadlessExecutor extends AbstractExecutorService {

    private final BlockingQueue<Runnable> queue = new LinkedBlockingQueue<>();

    // 标记是否等待
    private volatile boolean waiting = true;

    /**
     * 业务线程在此等待并执行任务
     */
    public void waitAndDrain() throws InterruptedException {
        Runnable runnable;
        while ((runnable = queue.take()) != WAITING_TASK) {
            // 执行队列中的任务
            runnable.run();
        }
    }

    @Override
    public void execute(Runnable runnable) {
        runnable = new RunnableWrapper(runnable);
        if (!waiting) {
            // 不在等待状态，提交到共享线程池
            sharedExecutor.execute(runnable);
            return;
        }
        // 放入队列，由业务线程执行
        queue.put(runnable);
    }

    /**
     * 当 RPC 响应到达时，唤醒等待的线程
     */
    public void notifyReturn() {
        // 放入特殊标记任务，结束 waitAndDrain
        queue.put(WAITING_TASK);
    }
}
```

**ThreadlessExecutor 的作用：**

```
传统模式（Dubbo 2.6）：
  Consumer 线程 → 发送请求 → future.get() 阻塞等待
  IO 线程 → 收到响应 → 提交到业务线程池 → 唤醒 Consumer 线程

  问题：Consumer 线程阻塞期间不干活，而业务线程池还要占用一个线程处理响应回调

ThreadlessExecutor 模式（Dubbo 2.7+）：
  Consumer 线程 → 发送请求 → waitAndDrain() 循环执行队列中的任务
  IO 线程 → 收到响应 → 将响应处理任务放入 ThreadlessExecutor 队列
  Consumer 线程 → 在 waitAndDrain 中执行响应处理任务 → 获取结果

  优势：Consumer 线程不会空等，而是主动执行响应回调，避免额外线程切换
```

### 10.4 CompletableFuture 异步调用

Dubbo 2.7+ 全面支持 CompletableFuture 异步调用：

```java
// 1. 定义返回 CompletableFuture 的接口
public interface UserService {
    CompletableFuture<String> asyncSayHello(String name);
}

// 2. Consumer 侧使用
@DubboReference
private UserService userService;

// 异步调用
CompletableFuture<String> future = userService.asyncSayHello("zhang");
future.thenAccept(result -> {
    System.out.println("Result: " + result);
});

// 3. Provider 侧实现
public class UserServiceImpl implements UserService {
    @Override
    public CompletableFuture<String> asyncSayHello(String name) {
        return CompletableFuture.supplyAsync(() -> {
            // 异步执行
            return "hello " + name;
        }, customExecutor);
    }
}
```

**Dubbo 对 CompletableFuture 的处理：**

```java
// AsyncRpcResult — 异步结果
public class AsyncRpcResult implements Result {

    private CompletableFuture<Object> valueFuture;
    private Invocation invocation;

    // 当 valueFuture 完成时，执行 onResponse 回调
    public void subscribeTo(CompletableFuture<?> future) {
        future.whenComplete((v, t) -> {
            if (t != null) {
                this.completeExceptionally(t);
            } else {
                this.complete(v);
            }
        });
    }

    @Override
    public Object recreate() throws Throwable {
        // 同步等待结果
        return valueFuture.get();
    }
}
```

### 10.5 Dubbo 线程模型全景图

```
┌──────────────────────────────────────────────────────────────────┐
│                     Dubbo 线程模型全景图                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Consumer 侧：                                                    │
│  ┌───────────────┐     ┌───────────────┐                        │
│  │  业务线程      │     │  IO 线程       │                        │
│  │ (User Thread) │     │ (Netty Worker)│                        │
│  │               │     │               │                        │
│  │ 调用 proxy    │     │ 网络读写       │                        │
│  │ 构建 Invoc     │     │ 编解码         │                        │
│  │ 发送请求       │     │               │                        │
│  │ future.get()  │     │               │                        │
│  │ 或等待回调     │     │ 收到响应       │                        │
│  │               │     │ → DefaultFuture│                        │
│  └───────────────┘     └───────────────┘                        │
│                          │                                        │
│                     线程派发(Dispatcher)                          │
│                          │                                        │
│                     ┌────▼────┐                                   │
│                     │线程池    │                                   │
│                     │(可选)   │                                   │
│                     └─────────┘                                   │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Provider 侧：                                                    │
│  ┌───────────────┐     ┌───────────────┐     ┌───────────────┐  │
│  │  业务线程      │     │  IO 线程       │     │  Boss 线程     │  │
│  │(Biz Thread)   │     │(Netty Worker) │     │(Netty Boss)   │  │
│  │               │     │               │     │               │  │
│  │ 执行业务方法   │     │ 网络读写       │     │ Accept 连接   │  │
│  │ 调用 Impl     │     │ 编解码         │     │               │  │
│  │               │     │               │     └───────────────┘  │
│  │ 执行 Filter链 │     │ 接收请求       │                        │
│  │               │     │ → 派发到线程池  │                        │
│  │ 返回 Result   │     │               │                        │
│  └───────────────┘     └───────────────┘                        │
│         ▲                      │                                 │
│         │               线程派发(Dispatcher)                      │
│         │                      │                                 │
│         │               ┌──────▼──────┐                          │
│         └───────────────│  线程池      │                          │
│                         │(ThreadPool) │                          │
│                         │ 默认 fixed  │                          │
│                         │ 200 线程    │                          │
│                         └─────────────┘                          │
│                                                                  │
│  线程隔离：                                                       │
│  ┌─────────────────────────────────────────────────┐             │
│  │  Netty Boss Group   → Accept 连接（1 线程）       │             │
│  │  Netty Worker Group → IO 读写（CPU 核数线程）      │             │
│  │  Dubbo ThreadPool   → 业务执行（默认 200 线程）     │             │
│  └─────────────────────────────────────────────────┘             │
│                                                                  │
│  线程池满时的处理：                                                │
│  ┌─────────────────────────────────────────────────┐             │
│  │  1. 拒绝任务（RejectedExecutionException）        │             │
│  │  2. Consumer 收到线程池满异常                     │             │
│  │  3. 根据 Cluster 策略处理（如 Failover 重试）      │             │
│  │  4. dump 线程栈帮助排查                          │             │
│  └─────────────────────────────────────────────────┘             │
└──────────────────────────────────────────────────────────────────┘
```

---

## 第十一部分 Dubbo 3.x Triple 协议

### 11.1 Triple 协议概述

Triple 是 Dubbo 3.x 推出的新协议，基于 HTTP/2 和 gRPC：

```
┌────────────────────────────────────────────────────────────────────┐
│                      Triple 协议核心特性                             │
├────────────────┬───────────────────────────────────────────────────┤
│ 基于 HTTP/2    │ 多路复用、头部压缩、二进制分帧                        │
├────────────────┼───────────────────────────────────────────────────┤
│ 兼容 gRPC      │ 可以与 gRPC 客户端/服务端互调                         │
├────────────────┼───────────────────────────────────────────────────┤
│ 流式调用       │ 支持 Unary / Server Stream / Client Stream / BiDi  │
├────────────────┼───────────────────────────────────────────────────┤
│ 跨语言          │ 基于 Protobuf IDL，天然多语言支持                    │
├────────────────┼───────────────────────────────────────────────────┤
│ 浏览器支持     │ 可通过 HTTP/2 直接从浏览器调用                        │
├────────────────┼───────────────────────────────────────────────────┤
│ Service Mesh   │ 支持 sidecar 模式，与 Istio 集成                    │
└────────────────┴───────────────────────────────────────────────────┘
```

### 11.2 基于 HTTP/2 和 gRPC

**Triple 协议帧格式（基于 HTTP/2 帧）：**

```
Triple 请求（HTTP/2 帧）：

  HEADERS 帧：
  ┌──────────────────────────────────────────────────┐
  │ :method = POST                                    │
  │ :scheme = http                                    │
  │ :path = /com.example.UserService/sayHello        │
  │ content-type = application/grpc                   │
  │ grpc-encoding = identity                          │
  │ grpc-timeout = 1000m                             │
  │ dubbo-service-group = dev                        │
  │ dubbo-service-version = 1.0.0                    │
  └──────────────────────────────────────────────────┘

  DATA 帧（gRPC 消息格式）：
  ┌──────────────────────────────────────────────────┐
  │ Compressed(1 byte) | Length(4 bytes) | Message   │
  │ 0                   | 0x00000034    | Protobuf数据│
  └──────────────────────────────────────────────────┘

Triple 响应（HTTP/2 帧）：

  HEADERS 帧：
  ┌──────────────────────────────────────────────────┐
  │ :status = 200                                     │
  │ content-type = application/grpc                   │
  │ grpc-encoding = identity                          │
  └──────────────────────────────────────────────────┘

  DATA 帧（gRPC 消息）：
  ┌──────────────────────────────────────────────────┐
  │ Compressed(1 byte) | Length(4 bytes) | Message   │
  └──────────────────────────────────────────────────┘

  Trailers 帧（gRPC 状态）：
  ┌──────────────────────────────────────────────────┐
  │ grpc-status = 0                                   │  0=OK
  │ grpc-message = OK                                 │
  └──────────────────────────────────────────────────┘
```

### 11.3 Triple 流式调用

```java
// 1. Unary（一元调用）— 传统请求-响应
public interface UserService {
    User getUser(Long id);
}

// 2. Server Stream（服务端流）— 服务端返回多个消息
public interface UserService {
    void streamUsers(List<Long> ids, StreamObserver<User> responseObserver);
}

// 3. Client Stream（客户端流）— 客户端发送多个消息
public interface UserService {
    StreamObserver<UserRequest> uploadUsers(StreamObserver<Response> responseObserver);
}

// 4. BiDi Stream（双向流）— 双方都可以发送多个消息
public interface ChatService {
    StreamObserver<ChatMessage> chat(StreamObserver<ChatMessage> responseObserver);
}
```

**Triple 流式调用底层实现：**

```java
// TripleProtocol — 服务导出和引用
public class TripleProtocol extends AbstractProtocol {

    @Override
    public <T> Exporter<T> export(Invoker<T> invoker) throws RpcException {
        URL url = invoker.getUrl();
        String key = serviceKey(url);
        final TripleExporter<T> exporter = new TripleExporter<>(invoker, key, exporterMap);
        exporterMap.put(key, exporter);

        // 启动 HTTP/2 Server
        server = (Http2Server) serverManager.createServer(url);
        // 注册服务
        server.addProtocolHandler(new TripleHttp2ProtocolHandler(...));

        return exporter;
    }

    @Override
    public <T> Invoker<T> refer(Class<T> type, URL url) throws RpcException {
        // 创建 TripleInvoker（基于 HTTP/2 客户端）
        TripleInvoker<T> invoker = new TripleInvoker<>(type, url, invokers);
        invokers.add(invoker);
        return invoker;
    }
}

// TripleInvoker — 发送 HTTP/2 请求
public class TripleInvoker<T> extends AbstractInvoker<T> {

    @Override
    protected Result doInvoke(Invocation invocation) {
        // ① 构建 HTTP/2 请求
        RequestMetadata metadata = buildRequestMetadata(invocation);

        // ② 根据调用类型选择 Stream
        if (isUnaryCall(invocation)) {
            // Unary 调用
            return doUnaryInvoke(invocation, metadata);
        } else if (isServerStream(invocation)) {
            // Server Stream
            return doServerStreamInvoke(invocation, metadata);
        } else if (isBiDiStream(invocation)) {
            // BiDi Stream
            return doBiDiStreamInvoke(invocation, metadata);
        }
    }

    private Result doUnaryInvoke(Invocation invocation, RequestMetadata metadata) {
        // 创建 HTTP/2 Stream
        Stream stream = httpClientStream.createStream(metadata);

        // 序列化请求（Protobuf）
        byte[] requestData = serializeRequest(invocation);

        // 发送请求（HEADERS + DATA + END_STREAM）
        stream.sendHeaders(metadata.getHeaders());
        stream.sendData(requestData, true);

        // 等待响应
        CompletableFuture<Object> future = stream.responseFuture();
        return new AsyncRpcResult(future, invocation);
    }
}
```

### 11.4 Triple vs Dubbo 协议

```
┌──────────────────┬──────────────────────┬──────────────────────────┐
│      维度         │    Dubbo 协议         │     Triple 协议           │
├──────────────────┼──────────────────────┼──────────────────────────┤
│ 传输层            │ TCP 长连接             │ HTTP/2                    │
│ 序列化            │ Hessian2/Kryo         │ Protobuf（默认）           │
│ 多路复用          │ 单连接（Request ID 区分）│ HTTP/2 Stream 原生支持     │
│ 流式调用          │ 不支持                 │ 支持（4 种模式）            │
│ 跨语言            │ Java 为主             │ 原生多语言（Protobuf IDL）  │
│ 浏览器调用        │ 不支持                 │ 支持                       │
│ gRPC 互操作      │ 不支持                 │ 支持                       │
│ Service Mesh    │ 不友好                 │ 友好（HTTP/2 标准）         │
│ 性能             │ 高（二进制紧凑）        │ 略低于 Dubbo（HTTP/2 开销） │
│ 头部压缩         │ 无                     │ HPACK                     │
│ 生态             │ Dubbo 生态             │ gRPC + 云原生生态           │
└──────────────────┴──────────────────────┴──────────────────────────┘
```

---

## 第十二部分 Dubbo vs Spring Cloud 全面对比

### 12.1 架构设计对比

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Dubbo vs Spring Cloud 架构对比                     │
├──────────────┬──────────────────────────┬────────────────────────────┤
│     维度      │         Dubbo             │      Spring Cloud          │
├──────────────┼──────────────────────────┼────────────────────────────┤
│ 定位         │ RPC 框架                  │ 微服务解决方案（全家桶）       │
│ 通信方式     │ TCP 长连接（私有协议）      │ HTTP/REST（标准协议）        │
│ 序列化       │ Hessian2/Protobuf         │ JSON                       │
│ 注册中心     │ Zookeeper/Nacos           │ Eureka/Nacos/Consul        │
│ 负载均衡     │ 客户端 LB（5种策略）       │ Ribbon/LoadBalancer（客户端）│
│ 熔断降级     │ Sentinel/Resilience4j     │ Hystrix/Resilience4j       │
│ 网关         │ Dubbo Gateway（可选）     │ Spring Cloud Gateway       │
│ 配置中心     │ Dubbo Config Center       │ Spring Cloud Config        │
│ 链路追踪     │ 集成 OpenTracing          │ Sleuth + Zipkin            │
│ 服务网格     │ Dubbo 3.x Sidecar         │ Istio/Linkerd              │
│ 编程模型     │ 面向接口代理               │ RestTemplate/Feign         │
└──────────────┴──────────────────────────┴────────────────────────────┘
```

### 12.2 通信模型对比

```
Dubbo 通信模型：
  Consumer ──── TCP 长连接 ────→ Provider
              （自定义二进制协议）
              （单连接多路复用）
              （Hessian2 序列化）

  特点：
  ① 单一长连接，减少连接建立开销
  ② 二进制协议，数据量小
  ② NIO 非阻塞 IO，高并发
  ④ 自定义 Request ID 匹配请求-响应

Spring Cloud 通信模型：
  Consumer ──── HTTP 短连接 ────→ Provider
              （标准 HTTP 协议）
              （每次请求新建连接）
              （JSON 序列化）

  特点：
  ① 标准 HTTP 协议，通用性强
  ② JSON 序列化，可读性好
  ③ 每次 HTTP 请求建立连接（HTTP/2 可复用）
  ④ 通过 Feign/RestTemplate 封装

性能差异（同等条件下的大致比例）：
  ┌──────────────┬──────────┬──────────────┬──────────┐
  │   指标        │  Dubbo   │ Spring Cloud │ 倍数      │
  ├──────────────┼──────────┼──────────────┼──────────┤
  │ 单次调用延迟  │ ~1ms     │ ~3-5ms       │ 3-5x     │
  │ 吞吐量(QPS)   │ ~50000   │ ~10000-15000 │ 3-5x     │
  │ CPU 使用率    │ 低       │ 较高          │ -        │
  │ 网络带宽      │ 小       │ 大            │ -        │
  └──────────────┴──────────┴──────────────┴──────────┘
  （以上数据为大致参考，实际取决于场景和优化）
```

### 12.3 SPI 机制对比

```
┌──────────────────────┬──────────────────────┬────────────────────────────┐
│        维度           │     Dubbo SPI         │     Spring SPI              │
├──────────────────────┼──────────────────────┼────────────────────────────┤
│ 配置位置              │ META-INF/dubbo/       │ spring.factories            │
│ 配置格式              │ key=value             │ 全限定类名（每行一个）        │
│ 按需加载              │ ✓ 支持（getExtension）  │ ✗ 不支持（全量加载）          │
│ IOC 注入             │ ✓ 支持                 │ ✗ 不支持                     │
│ AOP 包装             │ ✓ 支持（Wrapper）       │ ✗ 不支持                     │
│ 自适应扩展            │ ✓ 支持（@Adaptive）     │ ✗ 不支持                     │
│ 条件激活              │ ✓ 支持（@Activate）     │ ✗ 不支持                     │
│ 缓存                 ✓ 多级缓存               │ ✗ 无缓存                    │
│ 动态选择              │ ✓ 运行时根据 URL 选择   │ ✗ 编译时确定                 │
│ 扩展点覆盖            │ ✓ 支持                 │ ✗ 不支持                     │
└──────────────────────┴──────────────────────┴────────────────────────────┘

Dubbo SPI 的灵活性远超 Spring SPI，是 Dubbo 微内核架构的基础。
Spring 的扩展更多依赖 BeanPostProcessor 和 @Conditional 注解。
```

### 12.4 服务治理对比

```
┌──────────────────┬────────────────────────────┬────────────────────────────────┐
│   治理能力        │         Dubbo               │       Spring Cloud              │
├──────────────────┼────────────────────────────┼────────────────────────────────┤
│ 服务注册          │ Zookeeper/Nacos              │ Eureka/Nacos/Consul            │
│ 服务发现          │ 客户端推送（长连接监听）       │ 客户端拉取（定时轮询）            │
│ 负载均衡          │ 客户端 LB（5种策略 + 预热）   │ 客户端 LB（Ribbon/Gateway）      │
│ 集群容错          │ 6种策略（Failover/Failfast..）│ Hystrix/Resilience4j           │
│ 路由规则          │ 条件/标签/脚本路由            │ 无原生支持（需 Gateway）         │
│ 服务降级          │ Mock 机制                    │ Fallback                       │
│ 流量控制          │ Sentinel（线程数 + TPS）     │ Sentinel/RateLimiter           │
│ 配置管理          │ 动态配置中心（实时推送）       │ Config Server（Git/bus）        │
│ 元数据管理        │ MetadataReport              │ 无原生支持                      │
│ 多注册中心        │ 支持（ZoneAwareCluster）     │ 支持（多 Registration）         │
│ 服务分组          │ 支持（group + version）      │ 不支持原生                      │
│ 多版本            │ 支持（version）              │ 不支持原生                      │
│ 隐式参数传递       │ 支持（attachment）           │ 不支持原生                      │
│ 异步调用          │ CompletableFuture           │ AsyncRestTemplate              │
│ 泛化调用          │ 支持（GenericService）       │ 不支持                          │
└──────────────────┴────────────────────────────┴────────────────────────────────┘
```

### 12.5 性能对比

```
性能对比维度：

1. 序列化性能：
   Dubbo:  Hessian2 二进制序列化，体积小，速度快
   Cloud:  JSON 文本序列化，体积大，速度慢（~3-5x）

2. 协议开销：
   Dubbo:  16 字节头部 + body，极小开销
   Cloud:  HTTP 头部（200-500 字节）+ body，较大开销

3. 连接模型：
   Dubbo:  单一长连接 + 多路复用，连接复用率高
   Cloud:  HTTP/1.1 每次请求新连接（或连接池），开销大
           HTTP/2 可复用，但仍有 HTTP 头部开销

4. 线程模型：
   Dubbo:  Netty NIO + 业务线程池隔离，高效
   Cloud:  Tomcat/Undertow 线程模型，每个请求占用一个线程

5. 负载均衡精度：
   Dubbo:  客户端直接选 Provider，精确控制
   Cloud:  Ribbon/Gateway 负载均衡，精度稍低

6. 综合性能（大致参考）：
   ┌────────────────┬──────────┬──────────────┐
   │ 场景             │  Dubbo   │ Spring Cloud  │
   ├────────────────┼──────────┼──────────────┤
   │ 单次调用延迟     │ 1-2ms    │ 3-8ms         │
   │ 高并发 QPS      │ 5万+     │ 1-1.5万       │
   │ CPU 占用率      │ 低       │ 中高          │
   │ 内存占用        │ 中       │ 中            │
   │ 网络带宽占用     │ 小       │ 大            │
   └────────────────┴──────────┴──────────────┘
```

### 12.6 生态与社区对比

```
┌────────────────┬──────────────────────────────┬────────────────────────────────┐
│     维度        │          Dubbo                │        Spring Cloud             │
├────────────────┼──────────────────────────────┼────────────────────────────────┤
│ 开源组织        │ Apache 基金会                  │ VMware/Pivotal                  │
│ 主要语言        │ Java（支持多语言）              │ Java（Spring 生态）              │
│ 社区活跃度      │ 活跃（中国社区强）              │ 非常活跃（全球社区）              │
│ 文档质量        │ 中文文档优秀                    │ 英文为主                        │
│ 企业使用        │ 阿里/京东/滴滴/饿了么等         │ Netflix/亚马逊/国内大量企业      │
│ 学习曲线        │ 中等（SPI 概念需理解）          │ 较陡（Spring 全家桶组件多）      │
│ 与 K8s 集成    │ Dubbo 3.x 原生支持             │ 原生支持                        │
│ Service Mesh   │ Dubbo 3.x Sidecar             │ Istio/Linkerd                  │
│ 国际化         │ 中文为主，逐渐国际化            │ 全球化                          │
│ 与 Spring 集成 │ dubbo-spring-boot-starter     │ 原生 Spring                     │
│ REST 支持       │ 支持（RestProtocol）           │ 原生支持                        │
│ gRPC 支持       │ Triple 协议兼容 gRPC           │ 需额外集成                      │
└────────────────┴──────────────────────────────┴────────────────────────────────┘
```

### 12.7 选型建议

```
选 Dubbo 的场景：
  ✓ 高性能 RPC 调用是核心需求
  ✓ 内部微服务通信，不需要跨语言
  ✓ 需要丰富的服务治理能力（路由/降级/分组/多版本）
  ✓ 已有 Java 技术栈，团队熟悉 Dubbo
  ✓ 需要高吞吐量、低延迟
  ✓ 需要细粒度的流量控制

选 Spring Cloud 的场景：
  ✓ 需要标准化的 REST API（外部可调用）
  ✓ 技术栈多样化（不只 Java）
  ✓ 团队更熟悉 Spring 生态
  ✓ 需要与大量第三方系统集成
  ✓ 对性能要求不是极致
  ✓ 需要 Service Mesh（Istio）

混合使用（常见实践）：
  ✓ 外部 API 网关用 Spring Cloud Gateway
  ✓ 内部服务间通信用 Dubbo
  ✓ 通过 Dubbo 3.x Triple 协议与 gRPC 生态打通
  ✓ 通过 Nacos 同时作为 Dubbo 注册中心和 Spring Cloud 注册中心
```

**Dubbo + Spring Cloud 混合架构示例：**

```
                    ┌─────────────────┐
                    │  API Gateway    │  ← Spring Cloud Gateway
                    │  (REST + 限流)   │
                    └────────┬────────┘
                             │ HTTP
                    ┌────────▼────────┐
                    │  Order Service   │  ← Spring Boot + Dubbo Consumer
                    │  (REST 接口)     │
                    └────────┬────────┘
                             │ Dubbo RPC (TCP)
                ┌────────────┼────────────┐
                │            │            │
       ┌────────▼───┐ ┌──────▼─────┐ ┌───▼────────┐
       │User Service│ │Pay Service │ │Stock Service│  ← Dubbo Provider
       │(Dubbo)     │ │(Dubbo)     │ │(Dubbo)      │
       └────────────┘ └────────────┘ └─────────────┘

       Nacos（注册中心 + 配置中心）  ← 同时服务 Dubbo 和 Spring Cloud
       Sentinel（流控熔断）          ← 同时服务 Dubbo 和 Spring Cloud
```

---

## 附录 A：Dubbo 源码阅读路线图

```
Dubbo 源码阅读建议按以下顺序（由浅入深）：

Level 1：理解 SPI（核心基础）
  ① ExtensionLoader.getExtensionLoader()
  ② ExtensionLoader.getExtension()
  ③ ExtensionLoader.getAdaptiveExtension()
  ④ 理解 @Adaptive 代码生成
  ⑤ 理解 Wrapper 包装
  → 对应模块：dubbo-common/extension/

Level 2：理解服务导出与引用
  ① ServiceBean.afterPropertiesSet() → export()
  ② ReferenceBean.getObject() → createProxy()
  ③ RegistryProtocol.export()/refer()
  ④ DubboProtocol.export()/refer()
  → 对应模块：dubbo-config/dubbo-rpc-api/

Level 3：理解网络通信
  ① Exchangers.bind()/connect()
  ② HeaderExchangeServer/Client
  ③ NettyServer/NettyClient
  ④ DubboCodec 编解码
  ⑤ DefaultFuture 请求-响应匹配
  → 对应模块：dubbo-remoting/

Level 4：理解集群与负载均衡
  ① AbstractClusterInvoker.invoke()
  ② FailoverClusterInvoker.doInvoke()
  ③ LoadBalance.select()
  ④ RegistryDirectory.notify()
  ⑤ RouterChain.route()
  → 对应模块：dubbo-cluster/

Level 5：理解 Filter 与异步
  ① ProtocolFilterWrapper.buildInvokerChain()
  ② ConsumerContextFilter / ContextFilter
  ③ AsyncRpcResult
  ④ ThreadlessExecutor
  ⑤ Dispatcher 线程派发
  → 对应模块：dubbo-rpc-api/dubbo-common/

Level 6：理解 Triple 协议（Dubbo 3.x）
  ① TripleProtocol.export()/refer()
  ② TripleInvoker
  ③ HTTP/2 Stream
  ④ Protobuf 序列化
  → 对应模块：dubbo-rpc-triple/
```

## 附录 B：Dubbo 核心配置速查表

### B.1 Provider 配置

```xml
<!-- 服务提供者配置 -->
<dubbo:application name="user-service-provider"/>
<dubbo:registry address="zookeeper://127.0.0.1:2181"/>
<dubbo:protocol name="dubbo" port="20880" threads="200"/>

<!-- 服务暴露 -->
<dubbo:service interface="com.example.UserService" ref="userService"
    version="1.0.0" group="dev" timeout="1000" retries="2"
    loadbalance="random" cluster="failover" actives="10"
    executes="10" connections="1" />
```

### B.2 Consumer 配置

```xml
<!-- 服务消费者配置 -->
<dubbo:application name="order-service-consumer"/>
<dubbo:registry address="zookeeper://127.0.0.1:2181"/>

<!-- 服务引用 -->
<dubbo:reference id="userService" interface="com.example.UserService"
    version="1.0.0" group="dev" timeout="1000" retries="2"
    loadbalance="random" cluster="failover" check="false"
    mock="false" cache="false" async="false" />
```

### B.3 关键参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `timeout` | 1000ms | 调用超时时间 |
| `retries` | 2 | 重试次数（Failover 模式） |
| `loadbalance` | random | 负载均衡策略 |
| `cluster` | failover | 集群容错策略 |
| `connections` | 0(共享) | 连接数 |
| `actives` | 0(不限) | Consumer 并发控制 |
| `executes` | 0(不限) | Provider 并发控制 |
| `threads` | 200 | 线程池大小 |
| `queues` | 0 | 线程池队列大小 |
| `iothreads` | CPU+1 | IO 线程数 |
| `heartbeat` | 60000ms | 心跳间隔 |
| `check` | true | 启动时检查 Provider |
| `mock` | false | 服务降级 |
| `cache` | false | 结果缓存 |
| `group` | - | 服务分组 |
| `version` | - | 服务版本 |
| `weight` | 100 | 权重 |
| `warmup` | 600000ms | 预热时间 |

### B.4 注解配置

```java
// Provider
@DubboService(version = "1.0.0", group = "dev", timeout = 1000)
public class UserServiceImpl implements UserService { ... }

// Consumer
@DubboReference(version = "1.0.0", group = "dev", timeout = 1000,
    retries = 2, loadbalance = "random", check = false)
private UserService userService;

// 方法级配置
@DubboReference(methods = {
    @Method(name = "sayHello", timeout = 500, retries = 0),
    @Method(name = "getUser", timeout = 2000, retries = 3)
})
private UserService userService;
```

## 附录 C：Dubbo 面试高频问题汇总

### Q1：Dubbo SPI 和 Java SPI 的区别？

| 维度 | Java SPI | Dubbo SPI |
|------|----------|-----------|
| 加载 | 一次性全部加载 | 按需加载（getExtension("name")） |
| IOC | 不支持 | 支持（ExtensionFactory） |
| AOP | 不支持 | 支持（Wrapper） |
| 动态选择 | 不支持 | 支持（@Adaptive） |
| 缓存 | 无 | 多级缓存 |

### Q2：@Adaptive 自适应扩展的原理？

1. 检查 SPI 接口是否有 @Adaptive 方法
2. 使用 Javassist 动态生成代理类（接口名 + $Adaptive）
3. 生成的代码从 URL 中提取扩展名（根据 @Adaptive value 或方法名推断）
4. 通过 ExtensionLoader.getExtension(extName) 获取实现
5. 调用实现的对应方法

### Q3：Dubbo 的服务注册流程？

1. ServiceBean 初始化 → export()
2. 加载注册中心 URL → 构建 Provider URL
3. doLocalExport() → DubboProtocol.export() → 打开 Netty Server
4. ZookeeperRegistry.register() → 创建临时节点
5. Consumer 订阅 → 注册中心推送 Provider 列表 → RegistryDirectory.notify()

### Q4：Dubbo 有哪些集群容错策略？

- **Failover**：失败自动重试（默认），适合幂等操作
- **Failfast**：快速失败，适合非幂等操作
- **Failsafe**：忽略异常，适合写日志等非关键操作
- **Forking**：并行调用，适合实时性要求高的场景
- **Broadcast**：广播调用，适合刷新缓存

### Q5：Dubbo 的 5 种负载均衡策略？

- **Random**：加权随机（默认），考虑预热
- **RoundRobin**：平滑加权轮询，避免连续打到同一个
- **LeastActive**：最小活跃数，自适应负载
- **ConsistentHash**：一致性哈希，相同参数路由到同一 Provider
- **ShortestResponse**：最短响应时间（Dubbo 2.7+）

### Q6：Dubbo 的线程模型是怎样的？

- **Netty Boss Group**：Accept 连接（1 线程）
- **Netty Worker Group**：IO 读写（CPU 核数）
- **Dubbo ThreadPool**：业务执行（默认 200 线程，fixed）
- **Dispatcher**：决定消息在 IO 线程还是线程池处理（默认 all）
- 线程池满时抛出 RejectedExecutionException，dump 线程栈

### Q7：Dubbo vs Spring Cloud 如何选型？

- **选 Dubbo**：高性能 RPC、内部服务调用、丰富服务治理、Java 技术栈
- **选 Spring Cloud**：标准 REST API、多语言、Spring 生态、Service Mesh
- **混合使用**：Gateway 用 Spring Cloud，内部用 Dubbo，通过 Nacos 统一注册

### Q8：Dubbo 3.x 有哪些重要变化？

1. **应用级服务发现**：从接口级注册升级到应用级，注册数据量大幅减少
2. **Triple 协议**：基于 HTTP/2 + gRPC，支持流式调用和跨语言
3. **Service Mesh**：支持 Sidecar 模式，与 Istio 集成
4. **云原生**：原生 Kubernetes 部署支持

### Q9：Dubbo 如何实现服务降级？

1. **mock="force:return null"**：不调用，直接返回 null
2. **mock="fail:return null"**：调用失败后返回 null
3. **mock="com.example.UserServiceMock"**：调用失败后执行自定义 Mock 实现
4. MockClusterInvoker 在调用前后检查 mock 配置

### Q10：Dubbo 的 Filter 链是如何工作的？

1. ProtocolFilterWrapper 在 export/refer 时构建 Filter 链
2. 通过 getActivateExtension() 根据条件激活 Filter
3. Filter 链是责任链模式，从外到内执行
4. 每个 Filter 可以在 invoke() 前后插入逻辑
5. onResponse() 回调在响应返回时执行

---

> **总结**：Dubbo 的核心设计哲学是「微内核 + SPI」，所有组件通过 SPI 插件化，从协议到序列化、从注册中心到负载均衡，一切都是可替换的扩展点。理解了 Dubbo SPI，就理解了 Dubbo 的骨架；理解了 Export/Refer 流程，就理解了服务是如何暴露和消费的；理解了 Protocol + Exchange + Transport 三层网络模型，就理解了 RPC 调用是如何在网络中传输的；理解了 Cluster + LoadBalance，就理解了多 Provider 下的容错和负载分配。
>
> 建议配合之前的《Spring_Cloud_MyBatis源码深度解析》一起阅读，对比 Dubbo 和 Spring Cloud 在注册中心、负载均衡、熔断降级等方面的实现差异，加深对微服务架构的理解。
