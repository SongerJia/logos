# Spring 全家桶综合串讲：从 IoC 到微服务全链路

> **定位**：这是一份「串讲」文档，不是零散的知识点罗列。  
> 它把之前 13 份源码解析文档中所有核心机制，按照 **「一个请求从浏览器发出到数据库返回」** 的完整链路串联起来，让你看到每一层源码如何衔接、如何协作、如何退化。  
> 读完这份文档，你应该能用一条线把 Spring 全家桶的所有核心源码串起来讲清楚。

---

## 目录

```
第一部分  架构全景图 — Spring 全家桶的"一张地图"
第二部分  核心机制串讲 — 6 个贯穿全家桶的底层机制
  2.1  Bean 生命周期：从 Class 到 Object 的全流程
  2.2  代理机制：JDK Proxy → CGLIB → AOP → @Transactional → Dubbo Invoker
  2.3  SPI 扩展机制：Java SPI → Spring FactoryBean → Dubbo ExtensionLoader
  2.4  责任链模式：AOP Advice Chain → Sentinel Slot Chain → Gateway Filter Chain → Dubbo Filter Chain
  2.5  缓存机制：MyBatis L1/L2 → Spring Cache → Nacos 本地缓存 → Dubbo Service Cache
  2.6  异步与线程模型：WebFlux Mono → CompletableFuture → Dubbo Async → Netty EventLoop

第三部分  请求全链路追踪 — 一个 HTTP 请求的完整旅途
  3.1  Phase 1：浏览器 → Gateway
  3.2  Phase 2：Gateway 内部处理链路
  3.3  Phase 3：Gateway →下游服务（负载均衡 + 路由）
  3.4  Phase 4：下游服务内部（IoC → AOP → @Transactional → MyBatis）
  3.5  Phase 5：跨服务调用（Dubbo RPC 链路）
  3.6  Phase 6：异常与降级链路（Sentinel → Dubbo Mock）
  3.7  全链路时序图

第四部分  机制对比矩阵 — 同一个设计问题，不同框架的不同解法
  4.1  服务注册与发现：Nacos vs Zookeeper vs Eureka vs Consul
  4.2  配置管理：Nacos Config vs Spring Cloud Config vs Apollo
  4.3  流控与熔断：Sentinel vs Hystrix vs Dubbo Mock
  4.4  网关：Spring Cloud Gateway vs Zuul vs Dubbo Gateway
  4.5  RPC 协议：Dubbo vs Triple vs gRPC vs REST
  4.6  负载均衡：Spring Cloud Ribbon vs Dubbo LoadBalance vs Nacos Weight
  4.7  SPI 扩展：Java SPI vs Spring FactoryBean vs Dubbo ExtensionLoader
  4.8  代理机制：JDK Proxy vs CGLIB vs ByteBuddy vs Javassist（Dubbo）

第五部分  设计模式提炼 — Spring 全家桶用到的 12 个核心设计模式
  5.1  工厂模式
  5.2  单例模式
  5.3  代理模式
  5.4  责任链模式
  5.5  观察者模式
  5.6  策略模式
  5.7  模板方法模式
  5.8  装饰器模式
  5.9  适配器模式
  5.10 建造者模式
  5.11 享元模式
  5.12 回调模式

第六部分  面试串讲 — 50 个高频问题的一条线回答
  6.1  IoC/DI 系列（10 题）
  6.2  AOP/代理 系列（10 题）
  6.3  事务 系列（8 题）
  6.4  微服务 系列（12 题）
  6.5  MyBatis 系列（10 题）

第七部分  实战架构设计 — 从零设计一个微服务系统的关键决策
  7.1  单体 → 微服务拆分策略
  7.2  注册中心选型决策树
  7.3  网关层设计
  7.4  RPC 框架选型（Dubbo vs Spring Cloud）
  7.5  数据库层设计（MyBatis + 分库分表）
  7.6  全链路灰度发布方案
  7.7  容灾与降级方案

附录 A  Spring 全家桶核心类速查表
附录 B  13 份源码文档索引与衔接关系图
```

---

# 第一部分 架构全景图 — Spring 全家桶的"一张地图"

## 1.1 分层架构全景图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         客户端（浏览器 / App / 小程序）                    │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │ HTTP / HTTPS
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    网关层 — Spring Cloud Gateway                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐               │
│  │ Predicate │  │  Filter  │  │ Sentinel │  │  Load    │               │
│  │  匹配路由 │  │  链执行  │  │  流控熔断 │  │ Balancer │               │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘               │
│  底层：WebFlux + Netty（响应式）                                         │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │ HTTP / gRPC / Dubbo
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    服务层 — Spring Boot 应用                              │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Spring IoC 容器（核心底座）                     │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐          │   │
│  │  │ BeanFactory│ │ AppContext│ │ BeanPost │ │ 三级缓存 │          │   │
│  │  │  创建Bean  │ │  事件发布 │ │ Processor│ │ 解决循环 │          │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Spring AOP（代理层）                           │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐          │   │
│  │  │ JDK Proxy│ │  CGLIB   │ │ @Transac-│ │ 自定义   │          │   │
│  │  │  接口代理 │ │ 类代理   │ │ tional   │ │  Advice  │          │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌──────────────────────────┐  ┌──────────────────────────┐           │
│  │    MyBatis（ORM 层）       │  │    Dubbo（RPC 层）         │           │
│  │  SqlSession → Executor   │  │  Invoker → Filter Chain  │           │
│  │  → StatementHandler      │  │  → NettyClient → 序列化  │           │
│  │  → ResultSetHandler      │  │  → Provider → Filter     │           │
│  │  一级/二级缓存            │  │  → ReflectInvoker        │           │
│  └──────────────────────────┘  └──────────────────────────┘           │
│                                                                         │
│  ┌──────────────────────────┐  ┌──────────────────────────┐           │
│  │    Nacos（注册+配置）      │  │    Sentinel（流控熔断）    │           │
│  │  NamingService 注册      │  │  Slot Chain 8 Slot       │           │
│  │  ConfigService 长轮询    │  │  LeapArray 滑动窗口      │           │
│  │  @RefreshScope 刷新      │  │  FlowRule 流控           │           │
│  └──────────────────────────┘  └──────────────────────────┘           │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │ TCP / Dubbo Protocol / Triple / HTTP
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    数据层 — MySQL + Redis + MQ                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                              │
│  │  MySQL    │  │  Redis   │  │RocketMQ  │                              │
│  │  主从复制  │  │  缓存    │  │异步消息  │                              │
│  └──────────┘  └──────────┘  └──────────┘                              │
└─────────────────────────────────────────────────────────────────────────┘
```

## 1.2 核心框架之间的衔接关系

```
                    ┌───────────────────┐
                    │   Spring IoC/DI   │  ← 一切的底座
                    │   （Bean 容器）     │
                    └─────────┬─────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
      ┌───────────┐  ┌───────────┐  ┌───────────┐
      │ Spring    │  │  MyBatis  │  │  Dubbo    │
      │   AOP     │  │ SqlSession│  │ Reference │
      │ 代理机制  │  │  代理机制  │  │  代理机制  │
      └───────────┘  └───────────┘  └───────────┘
          │               │               │
          │  @Transactional│  MapperProxy  │  InvokerProxy
          │  事务代理      │  SQL代理       │  RPC代理
          │               │               │
          ▼               ▼               ▼
      ┌───────────────────────────────────────────┐
      │          三种代理，三种用途，一个原理          │
      │                                          │
      │  JDK Proxy：基于接口，生成 $Proxy0         │
      │  CGLIB：基于类，生成 $$EnhancerByCGLIB    │
      │  Javassist：Dubbo 用，动态生成代码          │
      │                                          │
      │  核心都是：拦截方法调用 → 执行增强逻辑 →      │
      │           放行或修改原始方法                  │
      └───────────────────────────────────────────┘
```

**关键衔接点**：

| 衔接点 | 源码机制 | 作用 |
|--------|----------|------|
| IoC → AOP | `AbstractAutoProxyCreator`（BeanPostProcessor） | Bean 初始化后创建代理 |
| IoC → MyBatis | `MapperScannerConfigurer`（BeanDefinitionRegistryPostProcessor） | 扫描 @Mapper 接口，注册为 FactoryBean |
| IoC → Dubbo | `ServiceBean` / `ReferenceBean`（FactoryBean + InitializingBean） | Spring Bean 生命周期触发 Dubbo export/refer |
| AOP → @Transactional | `TransactionInterceptor`（MethodInterceptor） | 代理拦截 → 事务增强 |
| AOP → Sentinel | `SentinelResourceAspect`（@Aspect） | AOP 切面拦截 → Sentinel Slot Chain |
| MyBatis → @Transactional | `SqlSessionTemplate` + `SpringManagedTransaction` | 事务管理器控制 Connection 的 commit/rollback |
| Dubbo → Sentinel | `DubboInterceptor`（Filter） | Dubbo Filter 链中嵌入 Sentinel 入口 |
| Gateway → Nacos | `ReactiveLoadBalancerClientFilter` | lb:// → Nacos ServiceInstance 选择 |
| Gateway → Sentinel | `SentinelGatewayFilter`（GlobalFilter） | Gateway Filter 链中嵌入 Sentinel |

## 1.3 从 Class 到远程调用 — Bean 的 7 种形态

```
  Class 文件 (.java → .class)
      │
      ▼  ClassLoader 加载
  Class 对象（元数据）
      │
      ▼  BeanDefinition 注册
  BeanDefinition（描述如何创建 Bean）
      │
      ▼  InstantiationStrategy 实例化
  原始对象（刚 new 出来，未注入、未代理）
      │
      ▼  属性注入 + Aware 回调
  半成品对象（已注入依赖，但未代理）
      │
      ├──▶ 检查是否需要 AOP 代理？
      │    │
      │    ├── 是 → 创建代理对象（JDK Proxy / CGLIB）
      │    │         代理对象内部持有原始对象引用
      │    │         代理对象才是容器中的 Bean
      │    │
      │    └── 否 → 原始对象直接就是容器中的 Bean
      │
      ▼  放入 singletonObjects 一级缓存
  最终 Bean（可能是原始对象，也可能是代理对象）
      │
      ├──▶ 如果是 @Service + @Transactional
      │    → 代理对象内部有 TransactionInterceptor
      │    → 调用方法时先走事务增强再走原始方法
      │
      ├──▶ 如果是 @Mapper 接口
      │    → MapperProxy 代理（JDK Proxy）
      │    → 调用方法时先走 MapperMethod → SqlSession → Executor
      │
      ├──▶ 如果是 Dubbo @Reference
      │    → ReferenceBean 创建的代理（JDK Proxy / Javassist）
      │    → 调用方法时先走 Invoker → Filter → NettyClient → 远程
      │
      └──▶ 如果是普通 @Component
           → 原始对象直接使用
```

---

# 第二部分 核心机制串讲 — 6 个贯穿全家桶的底层机制

## 2.1 Bean 生命周期：从 Class 到 Object 的全流程

### 2.1.1 完整生命周期时序图

```
┌─────────┐                              ┌──────────────┐
│  Class   │                              │  IoC 容器     │
└─────────┘                              └──────────────┘
     │                                          │
     │  ① ClassLoader 加载 Class                   │
     │──────────────────────────────────────────▶│
     │                                          │
     │  ② BeanDefinitionScanner 扫描注解           │
     │     (@Component/@Service/@Configuration)   │
     │──────────────────────────────────────────▶│
     │                                          │ ③ BeanFactoryPostProcessor
     │                                          │    修改 BeanDefinition
     │                                          │    （PropertySourcesPlaceholderConfigurer
     │                                          │     处理 ${...} 占位符）
     │                                          │
     │                                          │ ④ InstantiationStrategy
     │                                          │    .instantiate() → new 对象
     │                                          │    （CGLIB 构造器注入 / 反射无参构造）
     │                                          │
     │                                          │ ⑤ MergedBeanDefinitionPostProcessor
     │                                          │    .postProcessMergedBeanDefinition()
     │                                          │    （收集 @Autowired/@Value 元数据）
     │                                          │
     │                                          │ ⑥ populateBean() 属性注入
     │                                          │    ├── @Autowired → AutowiredAnnotationBeanPostProcessor
     │                                          │    ├── @Value → 解析占位符
     │                                          │    └── setter 注入
     │                                          │
     │                                          │ ⑦ Aware 回调
     │                                          │    ├── BeanNameAware.setBeanName()
     │                                          │    ├── BeanFactoryAware.setBeanFactory()
     │                                          │    ├── ApplicationContextAware.setApplicationContext()
     │                                          │
     │                                          │ ⑧ BeanPostProcessor.postProcessBeforeInitialization()
     │                                          │    （@PostConstruct → InitDestroyAnnotationBeanPostProcessor）
     │                                          │
     │                                          │ ⑨ InitializingBean.afterPropertiesSet()
     │                                          │    （自定义 init-method）
     │                                          │
     │                                          │ ⑩ BeanPostProcessor.postProcessAfterInitialization()
     │                                          │    ├── AbstractAutoProxyCreator → AOP 代理
     │                                          │    ├── ServiceBean.afterPropertiesSet() → Dubbo export
     │                                          │    ├── ReferenceBean.afterPropertiesSet() → Dubbo refer
     │                                          │
     │                                          │ ⑪ 放入 singletonObjects 一级缓存
     │                                          │
     │                                          │ ⑫ DisposableBean.destroy()（容器关闭时）
     │                                          │    ├── @PreDestroy
     │                                          │    ├── Dubbo ServiceBean.unexport()
```

### 2.1.2 循环依赖 — 三级缓存如何解决

```java
// DefaultSingletonBeanRegistry 三级缓存
/** 一级缓存：完全初始化好的 Bean */
private final Map<String, Object> singletonObjects = new ConcurrentHashMap<>();

/** 二级缓存：早期暴露的 Bean（已实例化，未注入） */
private final Map<String, Object> earlySingletonObjects = new ConcurrentHashMap<>();

/** 三级缓存：ObjectFactory — 能生成早期引用的工厂 */
private final Map<String, ObjectFactory<?>> singletonFactories = new HashMap<>();
```

**三级缓存解决循环依赖的关键流程**：

```
  创建 A（@Service）
      │
      ▼ 实例化 A（new A()，未注入属性）
      │
      ▼ 将 A 的 ObjectFactory 放入三级缓存
      │   singletonFactories.put("a", () -> getEarlyBeanReference("a", beanDefinition, rawA))
      │   ↑ 注意：这个 ObjectFactory 会检查是否需要 AOP 代理
      │   ↑ 如果需要代理，就提前创建代理对象（否则返回原始对象）
      │
      ▼ 注入 A 的属性 → 发现需要注入 B
      │
      ▼ 创建 B
      │   ├── 实例化 B（new B()，未注入属性）
      │   ├── 将 B 的 ObjectFactory 放入三级缓存
      │   ├── 注入 B 的属性 → 发现需要注入 A
      │   │
      │   │   ★ B 需要 A，但 A 还没完成初始化
      │   │   ★ 从三级缓存获取 A 的 ObjectFactory
      │   │   ★ ObjectFactory.getObject() → 
      │   │       如果 A 需要 AOP 代理 → 返回 A 的代理对象
      │   │       如果 A 不需要代理   → 返回 A 的原始对象
      │   │   ★ 将结果放入二级缓存 earlySingletonObjects
      │   │   ★ 删除三级缓存中的 A 的 ObjectFactory
      │   │   ★ B 拿到 A 的早期引用（可能是代理），注入到 B
      │   │
      │   ├── B 的 BeanPostProcessor 处理 → 可能创建 B 的代理
      │   ├── B 完成初始化 → 放入一级缓存
      │   └─────────────────────────────
      │
      ▼ A 注入 B 完成
      │
      ▼ A 的 BeanPostProcessor 处理
      │   ★ 关键问题：A 已经在创建代理时被提前暴露了
      │   ★ 如果 A 需要 AOP 代理，代理已经在 B 注入 A 时创建了
      │   ★ 此时不会再创建第二次代理（通过二级缓存判断）
      │
      ▼ A 完成初始化 → 放入一级缓存
      │   ★ 从二级缓存移除 A 的早期引用
```

**为什么必须是三级缓存，不能是两级？**

如果只有两级缓存（没有 ObjectFactory），那么在实例化后就必须立即决定是否创建代理。但 AOP 代理的正常时机是在 `postProcessAfterInitialization()` 之后。三级缓存的 ObjectFactory 延迟了这个决策——只有在出现循环依赖时才提前创建代理，没有循环依赖就按正常流程走。

### 2.1.3 Bean 的类型决定了后续的一切

| Bean 类型 | 创建方式 | 代理方式 | 后续机制 |
|-----------|---------|---------|---------|
| `@Component` | 反射实例化 | 可能 CGLIB（如有 AOP Advisor） | 直接使用 |
| `@Service` + `@Transactional` | 反射实例化 | CGLIB 代理（TransactionInterceptor） | 事务增强 |
| `@Mapper` | 不实例化（接口） | JDK Proxy（MapperProxy） | MyBatis SQL 执行 |
| `@DubboReference` | 不实例化（接口） | JDK Proxy / Javassist（Invoker 代理） | Dubbo RPC 远程调用 |
| `@DubboService` | 反射实例化 + Dubbo export | 不代理（直接注册为远程服务） | 对外暴露 RPC 服务 |
| `FactoryBean` | FactoryBean.getObject() | 由 FactoryBean 决定 | 自定义创建逻辑 |
| `@RestController` | 反射实例化 | 可能 CGLIB（如有 AOP） | Spring MVC 请求映射 |

## 2.2 代理机制：JDK Proxy → CGLIB → AOP → @Transactional → Dubbo Invoker

### 2.2.1 四种代理技术的统一原理

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                    所有代理的共同模型                              │
  │                                                                  │
  │  调用方 → 代理对象.方法(参数)                                      │
  │              │                                                    │
  │              ▼                                                    │
  │          拦截/增强逻辑                                             │
  │              │                                                    │
  │              ├── 前置增强（Before）                                │
  │              ├── 环绕增强（Around.invoke()）                       │
  │              │      │                                             │
  │              │      ▼                                             │
  │              │   原始对象.方法(参数)  ←── 真正执行业务逻辑           │
  │              │      │                                             │
  │              │      ▼                                             │
  │              │   返回结果                                          │
  │              │                                                    │
  │              ├── 后置增强（AfterReturning）                        │
  │              ├── 异常增强（AfterThrowing）                         │
  │              └── 最终增强（After）                                 │
  │              │                                                    │
  │              ▼                                                    │
  │          返回给调用方                                              │
  └──────────────────────────────────────────────────────────────────┘
```

### 2.2.2 四种代理的源码对比

| 维度 | JDK Proxy | CGLIB | ByteBuddy | Javassist（Dubbo） |
|------|-----------|-------|-----------|---------------------|
| 代理对象类型 | 接口实现类 | 子类 | 子类 | 子类/接口实现 |
| 生成方式 | `ProxyGenerator` 生成字节码 | `Enhancer` 生成字节码 | `DynamicType.Builder` | `ctClass.toClass()` |
| 拦截入口 | `InvocationHandler.invoke()` | `MethodInterceptor.intercept()` | `Advice` | `Invoker.invoke()` |
| 调用原始方法 | `Method.invoke()` | `MethodProxy.invokeSuper()` | `Method.invoke()` | 反射调用 |
| 性能优化 | 无 | **FastClass 索引加速** | 无 | 无 |
| 使用场景 | Spring AOP（接口） | Spring AOP（类） | Spring AOP（3.x 可选） | Dubbo @Adaptive |
| 生成类名 | `$Proxy0` | `$$EnhancerByCGLIB$$xxx` | 自定义 | `Protocol$Adaptive` |

### 2.2.3 代理链 — 一个方法可能被多层代理

```
  UserService.方法(参数)
      │
      ▼ 第一层代理：CGLIB AOP 代理（Spring 创建）
      │   ├── TransactionInterceptor（@Transactional）
      │   │   ├── 开启事务
      │   │   ├── 调用原始方法
      │   │   ├── 提交/回滚事务
      │   │
      │   ├── CustomAspectAdvice（自定义 @Around）
      │   │   ├── 前置逻辑
      │   │   ├── 调用 MethodInvocation.proceed()
      │   │   ├── 后置逻辑
      │
      │   ▼ 第二层代理：MapperProxy（MyBatis 创建）
      │       ├── MapperMethod.execute()
      │       ├── SqlSession.selectList()
      │       ├── Executor.query()
      │       ├── StatementHandler.prepare()
      │       ├── ResultSetHandler.handleResultSets()
      │       → 返回 List<User>
      │
      ▼ 第三层代理：Dubbo InvokerProxy（Dubbo 创建）
          ├── Invoker.invoke(Invocation)
          ├── Filter Chain 执行
          ├── DubboInvoker.doInvoke()
          ├── NettyClient.send()
          → 远程调用返回结果
```

**实际场景**：一个 `OrderService` 可能同时有：
- `@Transactional` 代理 → 事务控制
- `@SentinelResource` 切面 → 流控
- `@Reference` 注入的 `UserService` → Dubbo 远程调用代理
- `@Autowired` 注入的 `OrderMapper` → MyBatis SQL 代理

所有代理都通过 IoC 容器注入到同一个 Bean 中，调用时层层嵌套。

### 2.2.4 @Transactional 代理内部结构详解

```java
// CGLIB 代理对象内部结构
class UserService$$EnhancerByCGLIB$$xxx {
    // 拦截器列表（Spring AOP Advice Chain）
    private MethodInterceptor[] interceptors;
    
    // 最核心的拦截器：CglibMethodInterceptor
    // 它内部持有：
    //   - target: UserService 原始对象
    //   - advisorChain: Advisor 列表
    //     ├── TransactionInterceptor（@Transactional）
    //     │     内部持有：
    //     │     - PlatformTransactionManager
    //     │     - TransactionAttributeSource（解析 @Transactional 注解）
    //     │
    //     ├── AspectJAroundAdvice（自定义 @Around）
    //     │     内部持有：
    //     │     - aspectInstance: 自定义 Aspect Bean
    //     │     - aspectJAdviceMethod: @Around 标注的方法
    
    @Override
    public Object intercept(Object obj, Method method, Object[] args, MethodProxy proxy) {
        // 1. 获取 MethodInterceptor 链
        // 2. 创建 CglibMethodInvocation（责任链）
        // 3. 执行 proceed() → 依次调用每个 Advice
        
        // 执行顺序：
        // TransactionInterceptor.invoke()
        //   → invokeWithinTransaction()
        //     → createTransactionIfNecessary()  // 开启事务
        //     → invocation.proceed()             // 调用下一个 Advice
        //       → AspectJAroundAdvice.invoke()
        //         → @Around 方法执行
        //           → proceed() → 调用原始方法
        //     → commitTransactionAfterReturning() // 提交事务
        //     或 → completeTransactionAfterThrowing() // 回滚事务
    }
}
```

## 2.3 SPI 扩展机制：Java SPI → Spring FactoryBean → Dubbo ExtensionLoader

### 2.3.1 三种 SPI 的源码对比

```
  ┌────────────────────────────────────────────────────────────────────┐
  │                      Java SPI                                      │
  │  配置文件：META-INF/services/接口全限定名                             │
  │  加载方式：ServiceLoader.load(接口.class)                            │
  │  核心源码：                                                          │
  │    lazyIterator.next() →                                            │
  │      Class.forName(line) →                                          │
  │        clazz.newInstance()                                           │
  │  问题：一次性加载所有实现类，无法按需选择                               │
  │  使用场景：JDBC Driver、SLF4J LoggerFactory                         │
  └────────────────────────────────────────────────────────────────────┘
  
  ┌────────────────────────────────────────────────────────────────────┐
  │                      Spring FactoryBean                            │
  │  配置方式：@Bean / @Component / XML <bean class="FactoryBean">      │
  │  核心源码：                                                          │
  │    AbstractAutowireCapableBeanFactory.doCreateBean()                │
  │      → getObjectFromFactoryBean()                                   │
  │        → factoryBean.getObject()  ←── 你自定义创建逻辑               │
  │  优势：可以和 IoC 容器无缝集成，支持依赖注入                            │
  │  使用场景：MyBatis MapperFactoryBean、Dubbo ReferenceBean           │
  └────────────────────────────────────────────────────────────────────┘
  
  ┌────────────────────────────────────────────────────────────────────┐
  │                      Dubbo ExtensionLoader                         │
  │  配置文件：META-INF/dubbo/接口全限定名                                │
  │  核心源码（完整调用链）：                                              │
  │    ExtensionLoader.getExtensionLoader(Protocol.class)               │
  │      → new ExtensionLoader(Protocol.class)                          │
  │        → cachedDefaultName = @SPI("dubbo") 的值                     │
  │    ExtensionLoader.getExtension("dubbo")                            │
  │      → createExtension("dubbo")                                     │
  │        → getExtensionClasses()  ←── 加载所有配置文件中的实现类          │
  │          → loadDirectory(META-INF/dubbo/internal/)                  │
  │          → loadDirectory(META-INF/dubbo/)                            │
  │          → loadDirectory(META-INF/services/)                        │
  │        → clazz.newInstance()  ←── 实例化 DubboProtocol              │
  │        → injectExtension(instance)  ←── IOC 注入                    │
  │          → objectFactory.getExtension(pt, property)                 │
  │            → SpiExtensionFactory 或 SpringExtensionFactory           │
  │        → wrapExtension(instance, wrapperClassesList) ←── Wrapper AOP│
  │          → 依次用 Wrapper 类包装（ProtocolFilterWrapper →             │
  │             QosProtocolWrapper → ...）                               │
  │  优势：按需加载 + IOC 注入 + Wrapper AOP + @Adaptive 动态选择         │
  └────────────────────────────────────────────────────────────────────┘
```

### 2.3.2 @Adaptive — Dubbo SPI 最精妙的设计

```java
// Dubbo 的 @Adaptive 机制
// @SPI("dubbo") 标注在 Protocol 接口上 → 默认使用 dubbo 协议
// @Adaptive 标注在 Protocol.export() 和 refer() 方法上 → 根据 URL 参数动态选择实现

// ExtensionLoader 会动态生成一个 Protocol$Adaptive 类：
public class Protocol$Adaptive implements Protocol {
    public Exporter export(Invoker invoker) throws RpcException {
        // 从 URL 中获取协议名
        String protocolName = url.getParameter("protocol", "dubbo");
        // 按名字获取扩展实现
        Protocol extension = ExtensionLoader
            .getExtensionLoader(Protocol.class)
            .getExtension(protocolName);
        // 调用具体实现
        return extension.export(invoker);
    }
    
    public Invoker refer(Class type, URL url) throws RpcException {
        String protocolName = url.getParameter("protocol", "dubbo");
        Protocol extension = ExtensionLoader
            .getExtensionLoader(Protocol.class)
            .getExtension(protocolName);
        return extension.refer(type, url);
    }
}
```

**这和 Spring AOP 的 `@Transactional` 有什么本质区别？**

| 维度 | Spring AOP @Transactional | Dubbo @Adaptive |
|------|--------------------------|-----------------|
| 决策时机 | 编译期/启动期（切面定义固定） | 运行期（根据 URL 参数动态选择） |
| 选择逻辑 | 固定切面 → 固定 Advisor | URL 参数 → 动态选择 SPI 实现 |
| 代理方式 | CGLIB/JDK Proxy | Javassist 代码生成 |
| 增强内容 | 事务开启/提交/回滚 | 协议切换、序列化切换 |

### 2.3.3 FactoryBean 在 Spring 全家桶中的应用

```
  ┌──────────────────────────────────────────────────────────────────┐
  │              FactoryBean — Spring 的"Bean 工厂模式"               │
  │                                                                  │
  │  MyBatis：                                                       │
  │    MapperFactoryBean<T>                                          │
  │      getObject() → sqlSession.getMapper(接口.class)              │
  │      → 返回 MapperProxy 代理对象                                  │
  │                                                                  │
  │  Dubbo：                                                         │
  │    ReferenceBean<T>                                              │
  │      getObject() → createProxy() → 返回 Invoker 代理对象         │
  │      afterPropertiesSet() → refer() → 注册到注册中心               │
  │                                                                  │
  │    ServiceBean<T>                                                │
  │      getObject() → 返回原始对象（不是代理）                        │
  │      afterPropertiesSet() → export() → 注册到注册中心               │
  │                                                                  │
  │  Spring Cloud Gateway：                                          │
  │    GatewayFilterFactory（不是 FactoryBean，但类似的工厂模式）      │
  │      newFactory() → 创建 GatewayFilter 实例                      │
  │                                                                  │
  │  Nacos：                                                         │
  │    NacosServiceInstance（不是 FactoryBean，但类似思想）            │
  │      通过 NamingService 获取服务实例                               │
  └──────────────────────────────────────────────────────────────────┘
```

## 2.4 责任链模式：四种 Chain 的统一原理

### 2.4.1 四种责任链的源码结构对比

```
  ┌──────────────────────────────────────────────────────────────────────┐
  │                四种 Chain，同一个递归结构                              │
  │                                                                      │
  │  Spring AOP Advice Chain：                                            │
  │    ReflectiveMethodInvocation                                        │
  │      interceptorsAndDynamicMethodMatchers[]                          │
  │      currentInterceptorIndex = 0                                     │
  │      proceed() → interceptors[index].invoke(this) → this.proceed()   │
  │                                                                      │
  │  Sentinel Slot Chain：                                                │
  │    ProcessorSlotChain                                                │
  │      firstSlot → nextSlot → nextSlot → ...                          │
  │      entry() → firstSlot.entry(context, chain)                      │
  │                → chain.entryNext() → nextSlot.entry()               │
  │                                                                      │
  │  Gateway Filter Chain：                                               │
  │    DefaultGatewayFilterChain                                         │
  │      filters[]                                                       │
  │      index = 0                                                       │
  │      filter() → filters[index].filter(exchange, this)               │
  │                → chain.filter() → filters[index+1].filter()          │
  │                                                                      │
  │  Dubbo Filter Chain：                                                 │
  │    ProtocolFilterWrapper.buildInvokerChain()                        │
  │      InvokerNode(head) → InvokerNode(next) → ... → final Invoker    │
  │      invoke() → node.invoke(invocation)                             │
  │                → next.invoke(invocation) → ...                       │
  │                                                                      │
  │  ────────────────────────────────────────────────────────────────    │
  │  共同模式：                                                          │
  │    1. 按顺序排列的处理器列表                                           │
  │    2. 每个处理器决定是否继续传递给下一个                                 │
  │    3. 递归/链式调用：processor.handle(ctx, chain)                     │
  │       → chain.handle(ctx) → 下一个 processor                         │
  │    4. 可以中断链路（短路）                                             │
  │    5. 可以修改上下文（增/删/改数据）                                   │
  └──────────────────────────────────────────────────────────────────────┘
```

### 2.4.2 一个请求穿越四条责任链的完整路径

```
  HTTP 请求进入 Gateway
      │
      ▼ ===== Gateway Filter Chain =====
      │
      │  Filter[0]: SentinelGatewayFilter
      │    → Sentinel Slot Chain 嵌入！
      │      │
      │      ▼ ===== Sentinel Slot Chain =====
      │      │
      │      │  Slot[0]: NodeSelectorSlot（构建调用树）
      │      │  Slot[1]: ClusterBuilderSlot（构建集群节点）
      │      │  Slot[2]: LogSlot（日志记录）
      │      │  Slot[3]: StatisticSlot（滑动窗口统计）
      │      │  Slot[4]: AuthoritySlot（授权控制）
      │      │  Slot[5]: SystemSlot（系统保护）
      │      │  Slot[6]: FlowSlot（流控规则检查）  ←── 可能在这里短路！
      │      │  Slot[7]: DegradeSlot（熔断规则检查） ←── 可能在这里短路！
      │      │
      │      │  如果没有被流控/熔断 → 继续往下走
      │      │
      │  Filter[1]: ReactiveLoadBalancerClientFilter
      │    → 从 Nacos 获取服务实例 → 选择一个 → 转发请求
      │
      │  Filter[2]: NettyRoutingFilter
      │    → 底层 HTTP 路由转发
      │
      ▼ ===== 到达下游 Spring Boot 服务 =====
      │
      ▼ ===== Spring AOP Advice Chain =====
      │
      │  Advisor[0]: TransactionInterceptor（@Transactional）
      │    → 开启事务
      │    → proceed() → 继续往下走
      │
      │  Advisor[1]: CustomAroundAdvice（@Around）
      │    → 前置逻辑
      │    → proceed() → 继续往下走
      │
      │  → 调用原始方法
      │
      │  原始方法内部可能调用 Dubbo 远程服务：
      │
      ▼ ===== Dubbo Filter Chain =====
      │
      │  Filter[0]: ConsumerContextFilter（设置 RpcContext）
      │  Filter[1]: MonitorFilter（监控统计）
      │  Filter[2]: FutureFilter（异步回调）
      │  Filter[3]: TimeoutFilter（超时警告日志）
      │
      │  → DubboInvoker → NettyClient → 远程 Provider
      │
      │  Provider 端：
      │  Filter[0]: ContextFilter（清理 RpcContext）
      │  Filter[1]: ExceptionFilter（异常处理）
      │  Filter[2]: TraceFilter（调用链追踪）
      │  Filter[3]: MonitorFilter（监控统计）
      │
      │  → ReflectInvoker → 调用 Provider 的原始方法
      │
      │  Provider 方法可能调用 MyBatis：
      │
      ▼ ===== MyBatis Executor 链 =====
      │
      │  CachingExecutor.query()
      │    → 检查二级缓存（ miss）
      │    → delegate = SimpleExecutor
      │      → 检查一级缓存（ miss）
      │      → StatementHandler.prepare()
      │      → ParameterHandler.setParameters()
      │      → StatementHandler.execute()
      │      → ResultSetHandler.handleResultSets()
      │
      │  → 返回结果
      │
      ▼ ===== 逐层返回 =====
      
      MyBatis → Dubbo Provider Filter → Netty → Dubbo Consumer Filter 
      → AOP Advice Chain → Gateway Filter Chain → 浏览器
```

### 2.4.3 四条 Chain 的中断规则对比

| Chain | 中断条件 | 中断行为 |
|-------|---------|---------|
| AOP Advice Chain | `@Transactional` 异常回滚 | 不中断链，但标记事务 rollback-only |
| Sentinel Slot Chain | FlowRule 检查不通过 / DegradeSlot 短路 | 抛 `FlowException` / `DegradeException`，中断整条链 |
| Gateway Filter Chain | Sentinel 流控拦截 | 返回 429/503 响应，不再转发 |
| Dubbo Filter Chain | ExceptionFilter 包装异常 | 不中断链，但修改 Invocation 的异常类型 |

## 2.5 缓存机制：MyBatis L1/L2 → Spring Cache → Nacos 本地缓存 → Dubbo Service Cache

### 2.5.1 四种缓存的层次对比

```
  ┌──────────────────────────────────────────────────────────────────────┐
  │                     四种缓存，四种用途                                 │
  │                                                                      │
  │  L1 缓存（请求级）                                                    │
  │    ┌──────────────────────────────────────────────────────────────┐  │
  │    │  MyBatis PerpetualCache（HashMap）                            │  │
  │    │  作用域：SqlSession 内部                                       │  │
  │    │  生命周期：一个 SqlSession（一次请求）                           │  │
  │    │  何时失效：SqlSession.close() / commit() / update()          │  │
  │    │  线程安全：否（SqlSession 不是线程安全的）                      │  │
  │    │  关联事务：commit 时清空 L1（因为数据可能变了）                  │  │
  │    └──────────────────────────────────────────────────────────────┘  │
  │                                                                      │
  │  L2 缓存（应用级）                                                    │
  │    ┌──────────────────────────────────────────────────────────────┐  │
  │    │  MyBatis CachingExecutor + TransactionalCacheManager          │  │
  │    │  作用域：Mapper namespace 级别                                 │  │
  │    │  生命周期：应用运行期间                                         │  │
  │    │  何时失效：任何该 namespace 的写操作 commit 后                   │  │
  │    │  线程安全：TransactionalCache 装饰器保证事务隔离                │  │
  │    │  关联事务：事务 commit 时将暂存区数据刷入真正的 L2               │  │
  │    └──────────────────────────────────────────────────────────────┘  │
  │                                                                      │
  │  配置缓存（远程+本地双层）                                             │
  │    ┌──────────────────────────────────────────────────────────────┐  │
  │    │  Nacos ConfigService                                          │  │
  │    │  远程层：Nacos Server 集群存储                                  │  │
  │    │  本地层：本地磁盘文件缓存（failover 文件）                       │  │
  │    │  更新机制：长轮询 29.5s + AsyncContext                          │  │
  │    │  @RefreshScope：配置变更 → Bean 重建                           │  │
  │    │  缓存路径：~/.nacos/config/{group}/{dataId}                   │  │
  │    └──────────────────────────────────────────────────────────────┘  │
  │                                                                      │
  │  注册缓存（本地内存）                                                  │
  │    ┌──────────────────────────────────────────────────────────────┐  │
  │    │  Nacos NamingService + Dubbo RegistryDirectory                │  │
  │    │  Nacos：本地 Map<ServiceName, List<Instance>>                 │  │
  │    │  Dubbo：Directory.methodInvokerMap（本地路由表缓存）            │  │
  │    │  更新机制：Push（Nacos UDP/TCP 推送）+ Pull（定时拉取）        │  │
  │    │  关联：@RefreshScope 可以刷新 Ribbon 的 ServerList             │  │
  │    └──────────────────────────────────────────────────────────────┘  │
  └──────────────────────────────────────────────────────────────────────┘
```

### 2.5.2 MyBatis 缓存与 @Transactional 的交互

```java
// MyBatis + Spring 事务的缓存交互

// SpringManagedTransaction 持有的 Connection 和 @Transactional 绑定
// SqlSessionTemplate 的 SqlSession 是线程安全的（每次请求获取新的）
// 但同一个事务内，用的是同一个 SqlSession

// 场景：@Transactional 方法内多次查询同一 SQL
@Transactional
public void processOrder(Long orderId) {
    // 第一次查询 → 走 L1 缓存（命中）
    Order order1 = orderMapper.selectById(orderId);
    
    // 第二次查询 → 走 L1 缓存（命中，因为同一 SqlSession）
    Order order2 = orderMapper.selectById(orderId);
    
    // order1 == order2 → true（L1 缓存返回的是同一个对象引用）
    
    // 写操作 → L1 缓存清空
    orderMapper.updateStatus(orderId, "PAID");
    
    // 第三次查询 → L1 缓存 miss → 重新查数据库
    Order order3 = orderMapper.selectById(orderId);
    
    // 事务 commit → L1 缓存完全清空 → L2 暂存区刷入正式 L2
}
```

### 2.5.3 缓存一致性：从本地到分布式

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                    缓存一致性三层模型                              │
  │                                                                  │
  │  第一层：单机一致性                                               │
  │    MyBatis L1 缓存 + Spring 事务                                 │
  │    同一事务内：保证读到最新数据（写操作清空 L1）                     │
  │    不同事务间：不保证（事务隔离级别决定）                            │
  │                                                                  │
  │  第二层：应用间一致性                                             │
  │    MyBatis L2 缓存 + Redis                                       │
  │    L2 缓存：namespace 级别，多个 SqlSession 共享                  │
  │    问题：多实例部署时，各实例的 L2 缓存不共享！                     │
  │    解决：多实例场景一般不用 L2，改用 Redis                          │
  │                                                                  │
  │  第三层：分布式一致性                                             │
  │    Nacos 配置 + Dubbo 注册                                       │
  │    Nacos：Distro（AP）协议保证最终一致                             │
  │    Dubbo：Zookeeper（CP）临时节点保证强一致                        │
  │    选择依据：配置/注册是否允许短暂不一致                             │
  └──────────────────────────────────────────────────────────────────┘
```

## 2.6 异步与线程模型：WebFlux Mono → CompletableFuture → Dubbo Async → Netty EventLoop

### 2.6.1 四种异步模型的源码对比

```
  ┌──────────────────────────────────────────────────────────────────────┐
  │                  四种异步模型，四种线程策略                             │
  │                                                                      │
  │  ① WebFlux Mono（Gateway 底层）                                      │
  │    核心源码：Mono.subscribe() → Reactor 内部调度                     │
  │    线程模型：Netty EventLoop（少量线程处理大量连接）                    │
  │    特点：非阻塞 I/O，事件驱动，线程数 ≈ CPU 核数                      │
  │    适用：高并发网关、I/O 密集型                                       │
  │                                                                      │
  │  ② CompletableFuture（Sentinel 异步 / Dubbo 3.x）                   │
  │    核心源码：CompletableFuture.supplyAsync() → ForkJoinPool          │
  │    线程模型：ForkJoinPool.commonPool（默认 CPU 核数 -1）              │
  │    特点：有返回值，可链式编排 thenApply/thenCompose                   │
  │    适用：异步 RPC、异步回调                                           │
  │                                                                      │
  │  ③ Dubbo Async（CompletableFuture + ThreadlessExecutor）             │
  │    核心源码：DubboInvoker.doInvoke() → CompletableFuture             │
  │    线程模型：                                                        │
  │      Consumer 端：ThreadlessExecutor（业务线程等待响应）              │
  │      Provider 积：FixedThreadPool / EagerThreadPool                 │
  │    特点：RPC 请求发出后业务线程不阻塞，响应回调触发后续逻辑             │
  │                                                                      │
  │  ④ Netty EventLoop（底层通信层）                                     │
  │    核心源码：NioEventLoop.run() → select → processSelectedKeys       │
  │    线程模型：1 个 EventLoop 处理多个 Channel                          │
  │    特点：单线程事件循环，I/O + 业务在同一线程                          │
  │    适用：所有基于 Netty 的框架（Dubbo、Gateway）                      │
  └──────────────────────────────────────────────────────────────────────┘
```

### 2.6.2 Gateway → Dubbo → MyBatis 的线程流转

```
  ┌────────────────────────────────────────────────────────────────────┐
  │                  一个请求的线程流转全景图                              │
  │                                                                    │
  │  [Netty EventLoop Thread]  ←── Gateway 入口线程                    │
  │    │                                                               │
  │    ▼ Gateway Filter Chain 执行                                     │
  │    │                                                               │
  │    ▼ ReactiveLoadBalancerClientFilter                              │
  │    │   → Nacos 选择实例                                            │
  │    │                                                               │
  │    ▼ NettyRoutingFilter                                            │
  │    │   → HTTP 转发到下游服务                                        │
  │    │                                                               │
  │  [Tomcat HTTP Thread]  ←── 下游服务入口线程                         │
  │    │                                                               │
  │    ▼ DispatcherServlet.doDispatch()                                │
  │    │                                                               │
  │    ▼ Controller 方法                                               │
  │    │                                                               │
  │    ▼ AOP 代理 → TransactionInterceptor                             │
  │    │   → 开启事务 → 获取 Connection                                │
  │    │                                                               │
  │    ▼ Service 方法                                                  │
  │    │                                                               │
  │    ├──▶ 调用 MyBatis                                               │
  │    │    → SqlSession → Executor → JDBC → MySQL                     │
  │    │    → 同步等待 DB 返回                                          │
  │    │    → [Tomcat HTTP Thread] 阻塞等待                             │
  │    │                                                               │
  │    ├──▶ 调用 Dubbo RPC                                             │
  │    │    → DubboInvoker → NettyClient.send()                        │
  │    │    → [Tomcat HTTP Thread] 如果同步调用 → 阻塞等待               │
  │    │    → [Tomcat HTTP Thread] 如果异步调用 → CompletableFuture     │
  │    │                                                               │
  │    │    Provider 端：                                               │
  │    │    [Dubbo ThreadPool Thread]  ←── Provider 处理线程             │
  │    │      → Dubbo Filter Chain → ReflectInvoker                    │
  │    │      → Provider Service 方法                                  │
  │    │      → MyBatis → JDBC → MySQL                                 │
  │    │                                                               │
  │    ▼ 提交/回滚事务                                                 │
  │    │                                                               │
  │  [Tomcat HTTP Thread]  → 返回响应                                   │
  │    │                                                               │
  │  [Netty EventLoop Thread]  ←── Gateway 收到响应                    │
  │    │                                                               │
  │    ▼ 返回给浏览器                                                  │
  └────────────────────────────────────────────────────────────────────┘
  
  线程总结：
  │ 环节            │ 线程类型                │ 是否阻塞          │
  │─────────────────│─────────────────────────│───────────────────│
  │ Gateway 入口    │ Netty EventLoop         │ 非阻塞            │
  │ HTTP 转发       │ Netty EventLoop         │ 非阻塞            │
  │ 服务入口        │ Tomcat HTTP Thread      │ 阻塞（同步 Servlet）│
  │ AOP/事务        │ Tomcat HTTP Thread      │ 同线程            │
  │ MyBatis/JDBC    │ Tomcat HTTP Thread      │ 阻塞等待 DB       │
  │ Dubbo 同步 RPC  │ Tomcat HTTP Thread      │ 阻塞等待远程      │
  │ Dubbo 异步 RPC  │ CompletableFuture 回调  │ 非阻塞            │
  │ Provider 处理   │ Dubbo ThreadPool Thread │ 阻塞处理业务      │
  │ Netty I/O       │ Netty EventLoop         │ 非阻塞            │
```

---

# 第三部分 请求全链路追踪 — 一个 HTTP 请求的完整旅途

## 3.1 Phase 1：浏览器 → Gateway

```
  浏览器发出请求：GET /api/orders/123
      │
      │ DNS 解析 → Gateway 服务器 IP
      │ TCP 连接 → TLS 握手（HTTPS）
      │ HTTP 请求报文
      │
      ▼
  ┌──────────────────────────────────────────────────────────────┐
  │              Spring Cloud Gateway 接收请求                    │
  │                                                              │
  │  ReactorHttpServerAdapter.handleRequest()                    │
  │    → Netty 接收 HTTP 请求                                    │
  │    → 转换为 Reactor ServerHttpRequest                       │
  │    → 交给 ReactorHttpHandlerAdapter                          │
  │      → DispatcherHandler.handle()                           │
  │        → RoutePredicateHandlerMapping.getHandler()           │
  │          → 逐一匹配 Route 的 Predicate                        │
  │            ├── PathRoutePredicate: /api/orders/**  ✓ 匹配   │
  │            ├── MethodRoutePredicate: GET  ✓ 匹配             │
  │            ├── HeaderRoutePredicate: 无要求  ✓               │
  │            → 找到匹配的 Route：route_id = "order-service"     │
  │            → Route URI = lb://order-service/api/orders/**    │
  │                                                              │
  │  ★ lb:// 协议标识 → 需要负载均衡选择实例                       │
  └──────────────────────────────────────────────────────────────┘
```

## 3.2 Phase 2：Gateway 内部处理链路

```
  找到匹配的 Route 后，进入 Filter Chain：
  
  ┌──────────────────────────────────────────────────────────────────┐
  │              DefaultGatewayFilterChain 执行                      │
  │                                                                  │
  │  Filter[0]: ReactiveLoadBalancerClientFilter                     │
  │    │                                                              │
  │    │  ① 解析 lb://order-service → serviceId = "order-service"    │
  │    │                                                              │
  │    │  ② 调用 Nacos ReactiveLoadBalancer.choose()                  │
  │    │      │                                                       │
  │    │      ▼ NacosNamingService.selectInstances()                  │
  │    │        │                                                      │
  │    │        │  本地缓存命中 → 直接返回                               │
  │    │        │  本地缓存 miss → 从 Nacos Server 拉取                │
  │    │        │                                                      │
  │    │        │  返回 List<ServiceInstance>                           │
  │    │        │    ├── 192.168.1.10:8080 (weight=3)                  │
  │    │        │    ├── 192.168.1.11:8080 (weight=2)                  │
  │    │        │    └── 192.168.1.12:8080 (weight=1)                  │
  │    │        │                                                      │
  │    │        ▼ RoundRobinLoadBalancer.choose()                      │
  │    │          → 按权重轮询选择 → 选中 192.168.1.10:8080             │
  │    │                                                              │
  │    │  ③ 重建 URI：                                                │
  │    │     lb://order-service → http://192.168.1.10:8080            │
  │    │                                                              │
  │    │  ④ 将选中的实例信息放入 GATEWAY_LOADBALANCER_ATTR             │
  │    │                                                              │
  │    ▼ chain.filter(exchange) → 继续下一个 Filter                  │
  │                                                                  │
  │  Filter[1]: SentinelGatewayFilter                                │
  │    │                                                              │
  │    │  进入 Sentinel Slot Chain：                                   │
  │    │    NodeSelectorSlot → ClusterBuilderSlot → StatisticSlot     │
  │    │    → FlowSlot（检查流控规则）                                   │
  │    │      │                                                       │
  │    │      │  LeapArray 统计当前 QPS                                │
  │    │      │  当前 QPS = 150 > rule.count = 100                    │
  │    │      │  → 流控生效！                                          │
  │    │      │  → 抛出 FlowException                                  │
  │    │      │  → Gateway 返回 429 Too Many Requests                  │
  │    │      │  → 请求链路终止！                                       │
  │    │      │                                                        │
  │    │      （如果 QPS < 100 → 通过 → 继续往下走）                    │
  │    │                                                              │
  │    ▼ chain.filter(exchange) → 继续下一个 Filter                  │
  │                                                                  │
  │  Filter[2]: NettyRoutingFilter                                   │
  │    │                                                              │
  │    │  HTTP 转发到 192.168.1.10:8080                               │
  │    │  → Netty HttpClient 发出请求                                  │
  │    │  → 等待响应（非阻塞 Mono）                                     │
  │                                                                  │
  └──────────────────────────────────────────────────────────────────┘
```

## 3.3 Phase 3：Gateway → 下游服务（负载均衡 + 路由）

```
  ┌──────────────────────────────────────────────────────────────────┐
  │           Gateway 到下游服务的完整路由链路                         │
  │                                                                  │
  │  Gateway（Netty EventLoop Thread）                               │
  │    │                                                              │
  │    │  HTTP 请求：GET http://192.168.1.10:8080/api/orders/123     │
  │    │                                                              │
  │    ▼                                                              │
  │  下游服务（Tomcat HTTP Thread）                                    │
  │    │                                                              │
  │    │  DispatcherServlet.doDispatch()                              │
  │    │    │                                                          │
  │    │    │  ① HandlerMapping.getHandler()                          │
  │    │    │     → RequestMappingHandlerMapping                      │
  │    │    │     → 匹到 @GetMapping("/api/orders/{id}")              │
  │    │    │     → 返回 HandlerExecutionChain                        │
  │    │    │       ├── HandlerMethod: OrderController.getOrder()      │
  │    │    │       ├── Interceptor[0]: SentinelInterceptor            │
  │    │    │       ├── Interceptor[0]: LoggingInterceptor             │
  │    │    │                                                          │
  │    │    │  ② HandlerAdapter.handle()                              │
  │    │    │     → InvocableHandlerMethod.invokeForRequest()         │
  │    │    │     → 反射调用 OrderController.getOrder()               │
  │    │    │                                                          │
  │    │    │  ★ Controller 方法不是直接调用的！                        │
  │    │    │  ★ Spring MVC 通过反射调用                               │
  │    │    │  ★ 而且如果 Controller 有 AOP 代理，                     │
  │    │    │  ★ 反射调用的其实是代理对象                               │
  │    │    │                                                          │
  │    │    ▼                                                          │
  │    │  Controller.getOrder(123)                                    │
  │    │    → 返回 Order 对象                                          │
  │    │    → Spring MVC 序列化为 JSON                                 │
  │    │    → 返回 HTTP 200 + JSON Body                                │
  │    │                                                              │
  │    ▼                                                              │
  │  Gateway 收到响应 → 返回浏览器                                      │
  └──────────────────────────────────────────────────────────────────┘
```

## 3.4 Phase 4：下游服务内部（IoC → AOP → @Transactional → MyBatis）

```
  ┌──────────────────────────────────────────────────────────────────┐
  │          OrderService.getOrder() 的完整内部链路                    │
  │                                                                  │
  │  Controller 调用 orderService.getOrder(123)                      │
  │      │                                                            │
  │      │  ★ orderService 是 CGLIB 代理对象                          │
  │      │  ★ 因为 @Service + @Transactional → AOP 代理               │
  │      │                                                            │
  │      ▼ CGLIB 代理拦截                                             │
  │      │                                                            │
  │      │  CglibMethodInterceptor.intercept()                        │
  │      │    │                                                        │
  │      │    │  获取 Advice Chain：                                    │
  │      │    │    ├── TransactionInterceptor                          │
  │      │    │    ├── CustomAroundAdvice（如果有自定义 @Around）        │
  │      │    │                                                        │
  │      │    │  创建 ReflectiveMethodInvocation                       │
  │      │    │    currentInterceptorIndex = 0                         │
  │      │    │                                                        │
  │      │    │  proceed() → 调用第一个 Advice                          │
  │      │    │                                                        │
  │      │    ▼                                                        │
  │      │                                                            │
  │      │  ===== TransactionInterceptor.invoke() =====               │
  │      │                                                            │
  │      │  invokeWithinTransaction()                                  │
  │      │    │                                                        │
  │      │    │  ① createTransactionIfNecessary()                     │
  │      │    │     │                                                  │
  │      │    │     │  DataSourceTransactionManager.doBegin()         │
  │      │    │     │    │                                              │
  │      │    │     │    │  从 DataSource 获取 Connection              │
  │      │    │     │    │  Connection.setAutoCommit(false) ← 关闭自动提交│
  │      │    │     │    │  将 Connection 绑定到 ThreadLocal           │
  │      │    │     │    │    TransactionSynchronizationManager       │
  │      │    │     │    │      .bindResource(dataSource, connHolder) │
  │      │    │     │    │                                              │
  │      │    │     │  事务状态对象 = TransactionInfo                   │
  │      │    │     │    ├── newTransaction = true                     │
  │      │    │     │    ├── connectionHolder = connHolder             │
  │      │    │     │                                                  │
  │      │    │  ② invocation.proceed() → 继续下一个 Advice             │
  │      │    │     │                                                  │
  │      │    │     │  如果有自定义 @Around → 调用                      │
  │      │    │     │  否则 → 直接调用原始方法                           │
  │      │    │     │                                                  │
  │      │    │     ▼                                                  │
  │      │    │                                                        │
  │      │    │  ===== 原始方法执行 =====                               │
  │      │    │                                                        │
  │      │    │  OrderService.getOrder(123)  ←── 原始对象的方法         │
  │      │    │    │                                                    │
  │      │    │    │  ★ orderMapper 是 MapperProxy 代理                 │
  │      │    │    │  ★ 注入的是 JDK Proxy 创建的代理对象               │
  │      │    │    │                                                    │
  │      │    │    ▼                                                    │
  │      │    │                                                        │
  │      │    │  ===== MapperProxy.invoke() =====                      │
  │      │    │                                                        │
  │      │    │  MapperMethod.execute(sqlSession, args)                │
  │      │    │    │                                                    │
  │      │    │    │  ★ sqlSession 是 SqlSessionTemplate               │
  │      │    │    │  ★ 线程安全：每次获取新的 SqlSession                 │
  │      │    │    │  ★ 但在 @Transactional 内，用的是同一个 SqlSession  │
  │      │    │    │                                                    │
  │      │    │    ▼                                                    │
  │      │    │                                                        │
  │      │    │  ===== SqlSession.selectOne() =====                    │
  │      │    │                                                        │
  │      │    │  CachingExecutor.query()                                │
  │      │    │    │                                                    │
  │      │    │    │  ① 检查二级缓存（TransactionalCache 暂存区）       │
  │      │    │    │     → miss（首次查询）                              │
  │      │    │    │                                                    │
  │      │    │    │  ② delegate.query() = SimpleExecutor.query()      │
  │      │    │    │    │                                                │
  │      │    │    │    │  检查一级缓存（LocalCache）                    │
  │      │    │    │    │    → miss                                      │
  │      │    │    │    │                                                │
  │      │    │    │    │  queryFromDatabase()                          │
  │      │    │    │    │    │                                            │
  │      │    │    │    │    │  StatementHandler.prepare()              │
  │      │    │    │    │    │    → RoutingStatementHandler              │
  │      │    │    │    │    │      → SimpleStatementHandler            │
  │      │    │    │    │    │      → Connection.prepareStatement()     │
  │      │    │    │    │    │      → ParameterHandler.setParameters()  │
  │      │    │    │    │    │          → TypeHandler.setParameter()    │
  │      │    │    │    │    │      → Statement.executeQuery()         │
  │      │    │    │    │    │      → ResultSetHandler.handleResultSets()│
  │      │    │    │    │    │          → TypeHandler.getResult()       │
  │      │    │    │    │    │          → 返回 Order 对象               │
  │      │    │    │    │    │                                            │
  │      │    │    │    │  放入一级缓存                                   │
  │      │    │    │    │                                                │
  │      │    │    │  ③ 放入二级缓存暂存区                                │
  │      │    │    │                                                    │
  │      │    │    │  返回 Order 对象                                    │
  │      │    │    │                                                    │
  │      │    │  返回 Order 对象                                         │
  │      │    │                                                        │
  │      │    │  ★ 同一个事务中，Connection 是同一个                     │
  │      │    │  ★ 因为 @Transactional 在 doBegin 时绑定到 ThreadLocal  │
  │      │    │  ★ MyBatis 的 SpringManagedTransaction                  │
  │      │    │    → 从 ThreadLocal 获取当前事务的 Connection            │
  │      │    │                                                        │
  │      │    │  ③ commitTransactionAfterReturning()                    │
  │      │    │     │                                                  │
  │      │    │     │  DataSourceTransactionManager.doCommit()          │
  │      │    │     │    │                                              │
  │      │    │     │    │  Connection.commit() ← 提交事务             │
  │      │    │     │    │  Connection.setAutoCommit(true) ← 恢复     │
  │      │    │     │    │  从 ThreadLocal 解绑 Connection             │
  │      │    │     │    │  归还 Connection 到 DataSource pool         │
  │      │    │     │                                                    │
  │      │    │  ★ 事务 commit 时：                                     │
  │      │    │    MyBatis L1 缓存清空                                  │
  │      │    │    MyBatis L2 暂存区数据刷入正式 L2                     │
  │      │    │                                                        │
  │      │    ▼                                                        │
  │      │                                                            │
  │      │  返回 Order 对象给 Controller                                │
  │      │                                                            │
  │      ▼                                                            │
  │                                                                  │
  │  Controller 返回 JSON 响应                                        │
  └──────────────────────────────────────────────────────────────────┘
```

### 3.4.1 @Transactional 与 MyBatis 的 Connection 绑定关系

```java
// 关键源码衔接点：
// @Transactional 如何让 MyBatis 用同一个 Connection？

// 1. TransactionInterceptor 开启事务
DataSourceTransactionManager.doBegin()
    → DataSource.getConnection()
    → Connection.setAutoCommit(false)
    → TransactionSynchronizationManager.bindResource(dataSource, connectionHolder)
      // ThreadLocal<Map<Object, Object>> resources
      // key = DataSource, value = ConnectionHolder

// 2. MyBatis 获取 Connection
SpringManagedTransaction.getConnection()
    → TransactionSynchronizationManager.getResource(dataSource)
    // 从 ThreadLocal 中取出 ConnectionHolder
    // 如果存在 → 使用事务的 Connection
    // 如果不存在 → 自己从 DataSource 获取新 Connection

// 3. 事务提交
DataSourceTransactionManager.doCommit()
    → Connection.commit()
    → TransactionSynchronizationManager.unbindResource(dataSource)
    // 从 ThreadLocal 解绑

// ★ 这就是 @Transactional 和 MyBatis 串联的核心：
//   同一个 ThreadLocal，同一个 DataSource，同一个 Connection
```

## 3.5 Phase 5：跨服务调用（Dubbo RPC 链路）

```
  ┌──────────────────────────────────────────────────────────────────┐
  │          OrderService 调用 UserService（Dubbo RPC）               │
  │                                                                  │
  │  orderService.getOrder(123) 内部调用：                            │
  │    userService.getUser(order.getUserId())                         │
  │                                                                  │
  │  ★ userService 是 Dubbo ReferenceBean 创建的代理                 │
  │  ★ JDK Proxy / Javassist 代理对象                               │
  │                                                                  │
  │  ▼ 代理拦截                                                      │
  │                                                                  │
  │  InvokerInvocationHandler.invoke()                               │
  │    → Invoker.invoke(new RpcInvocation("getUser", args))          │
  │      │                                                            │
  │      │  ===== Dubbo Filter Chain =====                           │
  │      │                                                            │
  │      │  Filter[0]: ConsumerContextFilter                          │
  │      │    → 设置 RpcContext（IP、附件、调用信息）                   │
  │      │                                                            │
  │      │  Filter[1]: MonitorFilter                                  │
  │      │    → 记录调用次数 + 考勤统计                                │
  │      │                                                            │
  │      │  Filter[2]: SentinelDubboConsumerFilter（如果集成 Sentinel） │
  │      │    → Sentinel Slot Chain 嵌入！                            │
  │      │      │                                                     │
  │      │      │  NodeSelectorSlot → ClusterBuilderSlot              │
  │      │      │  → StatisticSlot → FlowSlot                        │
  │      │      │    │                                                │
  │      │      │    │  检查流控规则 → 通过                             │
  │      │      │    │                                                │
  │      │      │  → DegradeSlot                                      │
  │      │      │    │                                                │
  │      │      │    │  检查熔断状态 → CLOSED（正常）                   │
  │      │      │    │                                                │
  │      │      │  → 继续往下走                                       │
  │      │                                                            │
  │      │  Filter[3]: FutureFilter                                   │
  │      │    → 异步回调设置                                          │
  │      │                                                            │
  │      │  Filter[4]: TimeoutFilter                                  │
  │      │    → 超时警告日志                                          │
  │      │                                                            │
  │      │  ▼ 最后到达 DubboInvoker                                   │
  │      │                                                            │
  │      │  DubboInvoker.doInvoke(invocation)                         │
  │      │    │                                                        │
  │      │    │  ① 选择 ExchangeClient                                │
  │      │    │     → HeaderExchangeClient                             │
  │      │    │                                                        │
  │      │    │  ② 请求发送                                            │
  │      │    │     → HeaderExchangeChannel.request(invocation, timeout)│
  │      │    │       │                                                │
  │      │    │       │  Request 对象创建                               │
  │      │    │       │    ├── id = 递增 Request ID                    │
  │      │    │       │    ├── data = RpcInvocation                    │
  │      │    │       │    ├── twoWay = true（需要响应）                │
  │      │    │       │                                                │
  │      │    │       │  NettyChannel.send(request)                    │
  │      │    │       │    │                                            │
  │      │    │       │    │  DubboCodec.encode(request)               │
  │      │    │       │    │    ├── 16 字节 Header                     │
  │      │    │       │    │    │    magic(2) + flag(1) + status(1)   │
  │      │    │       │    │    │    + requestId(8) + bodyLength(4)   │
  │      │    │       │    │    ├── Body 序列化                        │
  │      │    │       │    │    │    Hessian2Serialization             │
  │      │    │       │    │    │    → RpcInvocation 序列化为字节流    │
  │      │    │       │    │    → Netty Channel 写出                   │
  │      │    │       │    │                                            │
  │      │    │       │  ★ 同步调用：                                   │
  │      │    │       │    DefaultFuture.newFuture(request, timeout)    │
  │      │    │       │    → future.get(timeout) ← 阻塞等待响应        │
  │      │    │       │                                                │
  │      │    │       │  ★ 异步调用：                                   │
  │      │    │       │    返回 CompletableFuture                      │
  │      │    │       │    → 非阻塞，响应到达时回调                     │
  │      │    │                                                        │
  │      │    │  ★ 请求通过 Netty 网络传输到达 Provider                 │
  │      │    │                                                        │
  │      │    ▼                                                        │
  │      │                                                            │
  │  ===== Provider 端处理 =====                                      │
  │                                                                  │
  │  NettyServer 收到请求                                             │
  │    → DubboCodec.decode() → Request 对象                          │
  │    → HeaderExchangeHandler.handle()                               │
  │    → DubboProtocol.requestHandler.reply()                        │
  │      │                                                            │
  │      │  ===== Dubbo Provider Filter Chain =====                   │
  │      │                                                            │
  │      │  Filter[0]: ContextFilter                                  │
  │      │    → 清理/设置 RpcContext                                   │
  │      │                                                            │
  │      │  Filter[1]: TraceFilter                                    │
  │      │    → 调用链追踪                                             │
  │      │                                                            │
  │      │  Filter[2]: ExceptionFilter                                │
  │      │    → 异常类型包装                                           │
  │      │                                                            │
  │      │  Filter[3]: MonitorFilter                                  │
  │      │    → 调用统计                                               │
  │      │                                                            │
  │      │  Filter[4]: SentinelDubboProviderFilter                    │
  │      │    → Sentinel Slot Chain（Provider 端流控/熔断）            │
  │      │                                                            │
  │      │  ▼ 最后到达 ReflectInvoker                                 │
  │      │                                                            │
  │      │  JavassistProxyFactory.getInvoker()                        │
  │      │    → wrapper.invoke(invocation)                            │
  │      │    → 反射调用 UserServiceImpl.getUser(userId)              │
  │      │      │                                                      │
  │      │      │  UserServiceImpl 可能也有 @Transactional             │
  │      │      │  → 同样的 AOP 代理链 → 事务处理 → MyBatis            │
  │      │      │                                                      │
  │      │      │  返回 User 对象                                      │
  │      │      │                                                      │
  │      │  ▼ Response 返回                                            │
  │      │                                                            │
  │      │  DubboCodec.encode(Response)                               │
  │      │    → Netty 写回 Consumer                                   │
  │      │                                                            │
  │  ===== Consumer 端收到响应 =====                                  │
  │                                                                  │
  │  NettyClient 收到响应                                             │
  │    → DubboCodec.decode() → Response 对象                          │
  │    → DefaultFuture.received(response)                              │
  │    → future.complete(result) ← 解阻塞                             │
  │    → 返回 User 对象                                               │
  │                                                                  │
  │  ★ 整个 Dubbo RPC 链路穿越了两条 Filter Chain                     │
  │  ★ Consumer 端 5 个 Filter + Provider 端 5 个 Filter              │
  │  ★ 两端都有 Sentinel 嵌入                                        │
  └──────────────────────────────────────────────────────────────────┘
```

## 3.6 Phase 6：异常与降级链路（Sentinel → Dubbo Mock）

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                异常与降级的三层防线                                 │
  │                                                                  │
  │  第一层：Gateway 入口 — Sentinel 流控                             │
  │    SentinelGatewayFilter                                         │
  │      → FlowSlot → QPS 超限 → 429 Too Many Requests              │
  │      → DegradeSlot → 熔断 → 503 Service Unavailable             │
  │    ★ 在网关层就拦截，请求不会进入下游                               │
  │                                                                  │
  │  第二层：服务内部 — Sentinel 方法级                                │
  │    @SentinelResource(value = "getOrder")                         │
  │      → SentinelResourceAspect 切面拦截                            │
  │      → Slot Chain 执行                                           │
  │      → 异常 → fallback / blockHandler                            │
  │    ★ 在方法级别降级，不影响其他方法                                 │
  │                                                                  │
  │  第三层：Dubbo RPC — Sentinel + Mock                              │
  │    Dubbo SentinelConsumerFilter                                  │
  │      → Slot Chain → 流控/熔断                                     │
  │    Dubbo MockClusterInvoker（服务降级）                            │
  │      → 如果配置了 mock="return null"                               │
  │      → 不发起远程调用，直接返回 null                                │
  │      → 如果配置了 mock="throw"                                     │
  │      → 直接抛出 RpcException                                       │
  │      → 如果配置了 mock="force:return {value}"                     │
  │      → 强制返回指定值                                               │
  │      → 如果配置了 mock="fail:return {value}"                      │
  │      → 调用失败后才返回指定值                                       │
  │    ★ Dubbo Mock 可以在注册中心动态配置                              │
  │    ★ Sentinel 可以在 Nacos 数据源动态推送规则                      │
  │                                                                  │
  │  异常处理串联：                                                    │
  │                                                                  │
  │  Dubbo RPC 异常                                                  │
  │    → Dubbo ExceptionFilter 包装异常                               │
  │    → Dubbo Invoker 抛出 RpcException                              │
  │    → Spring @Transactional 的 completeTransactionAfterThrowing() │
  │    → 回滚事务（如果异常匹配回滚规则）                               │
  │    → 异常继续向上传播                                              │
  │    → Controller 的 @ExceptionHandler 处理                        │
  │    → Gateway 收到错误响应                                         │
  │    → 返回给浏览器                                                 │
  │                                                                  │
  │  ★ 从 Dubbo 异常到事务回滚到 Gateway 返回                         │
  │  ★ 一条完整的异常传播链                                            │
  └──────────────────────────────────────────────────────────────────┘
```

## 3.7 全链路时序图

```
  浏览器        Gateway       Nacos       服务A       Dubbo       服务B       MySQL
    │             │            │           │           │           │           │
    │─ GET ──────▶│            │           │           │           │           │
    │             │            │           │           │           │           │
    │             │─ 查服务列表 ─▶│           │           │           │           │
    │             │◀─ 返回实例 ──│           │           │           │           │
    │             │            │           │           │           │           │
    │             │─ Sentinel ──│           │           │           │           │
    │             │  流控检查    │           │           │           │           │
    │             │  ✓ 通过     │           │           │           │           │
    │             │            │           │           │           │           │
    │             │─ HTTP 转发 ────────────▶│           │           │           │
    │             │            │           │           │           │           │
    │             │            │           │─ @Transactional ────▶│           │
    │             │            │           │  开启事务   │           │           │
    │             │            │           │           │           │           │
    │             │            │           │─ getOrder ─────────────────────▶│
    │             │            │           │  MyBatis   │           │           │
    │             │            │           │           │           │           │
    │             │            │           │◀─ Order ───────────────────────│
    │             │            │           │           │           │           │
    │             │            │           │─ getUser ─────────▶│           │
    │             │            │           │  Dubbo RPC │           │           │
    │             │            │           │           │           │           │
    │             │            │           │           │─ Filter ─▶│           │
    │             │            │           │           │  Chain    │           │
    │             │            │           │           │           │           │
    │             │            │           │           │           │─ getUser ─▶│
    │             │            │           │           │           │  MyBatis   │
    │             │            │           │           │           │           │
    │             │            │           │           │           │◀─ User ───│
    │             │            │           │           │           │           │
    │             │            │           │           │◀─ User ──│           │
    │             │            │           │           │           │           │
    │             │            │           │◀─ User ──│           │           │
    │             │            │           │           │           │           │
    │             │            │           │─ commit ──│           │           │
    │             │            │           │  事务提交   │           │           │
    │             │            │           │           │           │           │
    │             │◀─ 200 OK ────────────│           │           │           │
    │◀─ 200 OK ───│            │           │           │           │           │
    │             │            │           │           │           │           │
```

---

# 第四部分 机制对比矩阵 — 同一个设计问题，不同框架的不同解法

## 4.1 服务注册与发现：Nacos vs Zookeeper vs Eureka vs Consul

| 维度 | Nacos | Zookeeper | Eureka | Consul |
|------|-------|-----------|--------|--------|
| **一致性模型** | AP（Distro）+ CP（Raft）可切换 | CP（ZAB） | AP（自我保护） | CP（Raft） |
| **健康检查** | 客户端心跳 + 服务端 TCP/HTTP 探测 | 会话保活（Session） | 客户端心跳（30s） | Agent + HTTP/TCP/gRPC |
| **临时/持久实例** | ✅ 同时支持 | ❌ 只有临时节点 | ❌ 只有临时 | ✅ 通过 deregister |
| **配置中心** | ✅ 内置（长轮询） | ❌ 需独立部署 | ❌ 无 | ✅ 内置（KV 存储） |
| **Spring Cloud 集成** | ✅ spring-cloud-alibaba | ❌ 需 curator 手动 | ✅ spring-cloud-netflix | ✅ spring-cloud-consul |
| **Dubbo 集成** | ✅ dubbo-registry-nacos | ✅ dubbo-registry-zookeeper | ❌ 不支持 | ✅ dubbo-registry-consul |
| **推/拉模型** | Push（UDP/TCP）+ Pull（定时） | Watch 推送 | Pull（定时 30s） | Watch 推送 |
| **集群规模** | 支持万级实例 | 千级实例（ZK 性能瓶颈） | 万级实例 | 千级实例 |
| **选型建议** | 中大型微服务首选 | Dubbo 传统选型 | 已进入维护模式 | Kubernetes 生态 |

## 4.2 配置管理：Nacos Config vs Spring Cloud Config vs Apollo

| 维度 | Nacos Config | Spring Cloud Config | Apollo |
|------|-------------|--------------------|---------| ----|
| **存储** | 内置 MySQL + 本地磁盘 | Git 仓库 | MySQL + 本地缓存 |
| **推送方式** | 长轮询 29.5s | Git Webhook → Bus 刷新 | 长轮询 + 实时推送 |
| **多环境** | namespace + group + dataId | profile + label | env + cluster + namespace |
| **灰度发布** | ✅ 内置 | ❌ 需 Bus + 手动 | ✅ 内置灰度规则 |
| **权限管理** | ✅ 内置 RBAC | ❌ 依赖 Git 权限 | ✅ 细粒度权限 |
| **@RefreshScope** | ✅ 支持 | ✅ 支持 | ✅ 支持 |
| **适用场景** | Alibaba 生态首选 | GitOps 风格团队 | 大型企业精细化管理 |

## 4.3 流控与熔断：Sentinel vs Hystrix vs Dubbo Mock

| 维度 | Sentinel | Hystrix | Dubbo Mock |
|------|---------|---------|-----------|
| **流控** | ✅ QPS / 线程数 / 热点参数 | ❌ 只有线程隔离 | ❌ 无流控 |
| **熔断策略** | 慢调用比例 / 异常比例 / 异常数 | 单一异常比例 | ❌ 无熔断 |
| **熔断恢复** | HALF_OPEN → 探测恢复 | HALF_OPEN → 探测恢复 | ❌ 手动配置 |
| **统计窗口** | LeapArray 滑动窗口（1s 粒度） | RxJava 滑动窗口（10s/1s） | ❌ 无统计 |
| **降级方式** | fallback / blockHandler | fallback / command | mock=return/throw |
| **规则推送** | ✅ Nacos/Zookeeper 数据源 | ❌ 需手动 | ✅ 注册中心动态配置 |
| **链路入口** | Gateway / Dubbo / @SentinelResource | @HystrixCommand | Dubbo Consumer/Provider |
| **隔离策略** | 信号量（不创建线程） | 线程池隔离（创建线程） | ❌ 无隔离 |
| **适用场景** | 当前首选（Alibaba 生态） | 已停止维护 | Dubbo 专项降级 |

## 4.4 网关：Spring Cloud Gateway vs Zuul vs Dubbo Gateway

| 维度 | Spring Cloud Gateway | Zuul 1.x | Zuul 2.x | Dubbo Gateway |
|------|---------------------|----------|----------|---------------|
| **底层模型** | WebFlux + Netty（响应式） | Servlet + Thread-per-request | Netty（响应式） | Dubbo Protocol + Netty |
| **过滤器** | GlobalFilter + GatewayFilter | ZuulFilter（pre/route/post/error） | ZuulFilter | Dubbo Filter |
| **路由匹配** | Route Predicate（11 种） | URL pattern | URL pattern | Dubbo 路由规则 |
| **负载均衡** | ReactiveLoadBalancer | Ribbon | Ribbon | Dubbo LoadBalance |
| **流控集成** | SentinelGatewayFilter | ❌ 需手动 | ❌ 需手动 | SentinelDubboFilter |
| **协议支持** | HTTP/HTTPS | HTTP/HTTPS | HTTP/HTTPS | Dubbo/Triple/HTTP |
| **性能** | 高（非阻塞） | 低（阻塞） | 高（非阻塞） | 高（非阻塞） |
| **适用场景** | Spring Cloud 体系首选 | 已淘汰 | Netflix 内部 | Dubbo 体系 |

## 4.5 RPC 协议：Dubbo vs Triple vs gRPC vs REST

| 维度 | Dubbo 协议 | Triple（Dubbo 3.x） | gRPC | REST（HTTP JSON） |
|------|-----------|---------------------|------|-------------------|
| **传输层** | TCP（Netty） | HTTP/2（Netty） | HTTP/2 | HTTP/1.1 |
| **序列化** | Hessian2 | Protobuf / JSON | Protobuf | JSON |
| **流式调用** | ❌ 单次 | ✅ Unary/Server/Client/BiStream | ✅ 4 种流式 | ❌ 单次 |
| **跨语言** | ❌ Java only | ✅ 跨语言 | ✅ 跨语言 | ✅ 跨语言 |
| **性能** | 高（二进制 + 长连接） | 高（HTTP/2 + Protobuf） | 高（HTTP/2 + Protobuf） | 低（JSON + 短连接） |
| **浏览器兼容** | ❌ | ✅ HTTP/2 可穿透 | ❌ 需要 gRPC-Web | ✅ 天然兼容 |
| **适用场景** | Dubbo 2.x Java 内部 | Dubbo 3.x + 跨语言 | 跨语言 gRPC 生态 | 对外 API / 前端调用 |

## 4.6 负载均衡：Spring Cloud Ribbon vs Dubbo LoadBalance vs Nacos Weight

| 维度 | Ribbon（Spring Cloud） | Dubbo LoadBalance | Nacos Weight |
|------|----------------------|-------------------|-------------|
| **算法种类** | Random / RoundRobin / WeightedResponseTime | Random / RoundRobin / LeastActive / ConsistentHash / ShortestResponse | 权重分配（影响 Ribbon/Dubbo 选择概率） |
| **预热机制** | ❌ 无 | ✅ Random 有 warmup 权重计算 | ✅ 通过权重配置实现 |
| **一致性哈希** | ❌ 无 | ✅ ConsistentHash + 虚拟节点 | ❌ 无 |
| **动态调整** | ❌ 需重启 | ✅ 注册中心推送权重 | ✅ Nacos 控制台实时调权重 |
| **上下文传递** | ❌ 无 | ✅ RpcContext 附件传递 | ❌ 无 |

## 4.7 SPI 扩展：Java SPI → Spring FactoryBean → Dubbo ExtensionLoader

| 维度 | Java SPI | Spring FactoryBean | Dubbo ExtensionLoader |
|------|----------|-------------------|----------------------|
| **配置文件** | META-INF/services/接口名 | @Bean/@Component/XML | META-INF/dubbo/接口名 |
| **加载方式** | ServiceLoader.load() | BeanFactory.getBean() | ExtensionLoader.getExtension() |
| **按需选择** | ❌ 全加载 | ✅ 按 Bean 名选择 | ✅ 按名字 + @Adaptive 动态 |
| **IOC 注入** | ❌ 无 | ✅ Spring DI | ✅ ExtensionFactory |
| **AOP/包装** | ❌ 无 | ❌ 无 | ✅ Wrapper 类自动包装 |
| **缓存** | ❌ 无 | ✅ singletonObjects | ✅ 多级缓存 MAP |
| **生命周期** | 无管理 | Spring 管理（destroy） | 无管理（单例缓存） |

## 4.8 代理机制：JDK Proxy vs CGLIB vs ByteBuddy vs Javassist

| 维度 | JDK Proxy | CGLIB | ByteBuddy | Javassist |
|------|-----------|-------|-----------|-----------|
| **要求** | 必须有接口 | 无要求（子类继承） | 无要求 | 无要求 |
| **生成类名** | `$Proxy0` | `$$EnhancerByCGLIB$$xxx` | 自定义 | 自定义 |
| **性能** | 较慢（反射调用） | **快（FastClass 索引）** | 较快 | 较慢 |
| **Spring AOP** | ✅ 接口代理默认 | ✅ 类代理默认 | ✅ 3.x 可选 | ❌ |
| **Dubbo 使用** | ✅ Consumer 代理 | ❌ | ❌ | ✅ @Adaptive 代码生成 |
| **MyBatis 使用** | ✅ MapperProxy | ❌ | ❌ | ❌ |
| **限制** | 不能代理 final 类 | 不能代理 final 方法 | 不能代理 final 方法 | 语法限制 |

---

# 第五部分 设计模式提炼 — Spring 全家桶用到的 12 个核心设计模式

## 5.1 工厂模式

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  工厂模式在 Spring 全家桶中的 4 种形态                               │
  │                                                                    │
  │  ① Simple Factory — BeanFactory                                   │
  │    DefaultListableBeanFactory.getBean("orderService")              │
  │    → 根据 Bean 名称获取 Bean 实例                                  │
  │                                                                    │
  │  ② Factory Method — FactoryBean                                   │
  │    MapperFactoryBean.getObject() → 返回 MapperProxy 代理           │
  │    ReferenceBean.getObject() → 返回 Dubbo Invoker 代理             │
  │    → 延迟决策：由 FactoryBean 决定创建什么                          │
  │                                                                    │
  │  ③ Abstract Factory — AbstractAutowireCapableBeanFactory          │
  │    createBean() → instantiateBean() → populateBean()              │
  │    → 定义 Bean 创建的骨架流程，子类可覆盖各步骤                      │
  │                                                                    │
  │  ④ Static Factory — Dubbo ExtensionLoader                         │
  │    ExtensionLoader.getExtensionLoader(Protocol.class)              │
  │    → 静态方法获取扩展加载器，再按名字获取扩展实例                    │
  └────────────────────────────────────────────────────────────────────┘
```

## 5.2 单例模式

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  单例模式在 Spring 全家桶中的 4 种实现                               │
  │                                                                    │
  │  ① Spring IoC 单例 — singletonObjects 一级缓存                    │
  │    DefaultSingletonBeanRegistry.getSingleton()                     │
  │    → ConcurrentHashMap 存储，全局唯一                              │
  │    → 和传统单例的区别：Spring 管理生命周期，不是自己管                │
  │                                                                    │
  │  ② DCL 单例 — volatile + double-check                             │
  │    Java 基础中的经典实现                                            │
  │    volatile 防止指令重排，synchronized 防止并发创建                  │
  │    → Spring 不用这种方式，因为容器本身就是线程安全的                  │
  │                                                                    │
  │  ③ 枚举单例 — Sentinel 的 NodeSelectorSlot                        │
  │    NodeSelectorSlot 是 ProcessorSlotChain 中的单例节点             │
  │    → Sentinel 通过 SlotChainBuilder 构建链，每个 Slot 只创建一次    │
  │                                                                    │
  │  ④ ExtensionLoader 单例 — cachedInstances                         │
  │    ExtensionLoader 内部的 MAP<name, Object> 缓存                  │
  │    → 每个 SPI 扩展只创建一次，放入缓存                              │
  │    → 和 Spring singletonObjects 的思想完全一致                       │
  └────────────────────────────────────────────────────────────────────┘
```

## 5.3 代理模式

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  代理模式贯穿 Spring 全家桶的 5 个层次                               │
  │                                                                    │
  │  第 1 层：Spring AOP 代理                                          │
  │    CGLIB 代理 → TransactionInterceptor → 事务增强                  │
  │    → 代理对象持有原始对象引用                                        │
  │                                                                    │
  │  第 2 层：MyBatis MapperProxy                                      │
  │    JDK Proxy → MapperMethod → SqlSession → Executor                │
  │    → 代理的是接口，没有原始对象（接口不能实例化）                      │
  │    → 每次调用都是 SQL 执行                                          │
  │                                                                    │
  │  第 3 层：Dubbo ReferenceBean 代理                                 │
  │    JDK Proxy / Javassist → Invoker → Filter → Netty                │
  │    → 代理的是远程服务接口                                           │
  │    → 调用不执行本地代码，而是远程传输                                 │
  │                                                                    │
  │  第 4 层：Dubbo Wrapper 代理（SPI AOP）                             │
  │    ProtocolFilterWrapper 包装 DubboProtocol                        │
  │    → 类似装饰器，但更接近代理                                        │
  │    → 在 export/refer 前后增加逻辑                                   │
  │                                                                    │
  │  第 5 层：Dubbo @Adaptive 代理                                     │
  │    Javassist 生成的 Protocol$Adaptive                               │
  │    → 动态代理，根据 URL 参数选择 SPI 实现                            │
  │    → 和 Spring AOP 的区别：决策逻辑在运行时动态                      │
  └────────────────────────────────────────────────────────────────────┘
```

## 5.4 责任链模式

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  责任链模式 — 四条 Chain 的递归结构完全一致                          │
  │                                                                    │
  │  AOP：    ReflectiveMethodInvocation.proceed()                     │
  │           → interceptors[index++].invoke(this) → proceed()         │
  │                                                                    │
  │  Sentinel：ProcessorSlotChain.entry()                              │
  │           → slot.entry(ctx, chain) → chain.entryNext()             │
  │                                                                    │
  │  Gateway：DefaultGatewayFilterChain.filter()                       │
  │           → filters[index++].filter(exchange, this) → filter()     │
  │                                                                    │
  │  Dubbo：  InvokerChain.invoke()                                    │
  │           → node.invoke(invocation) → next.invoke(invocation)      │
  │                                                                    │
  │  ──────────────────────────────────────────────                    │
  │  共同骨架：                                                        │
  │    1. 顺序排列的处理器列表                                           │
  │    2. 每个处理器处理完后调用 chain.continue()                        │
  │    3. 可以中断链路（短路返回）                                       │
  │    4. 可以修改上下文数据                                            │
  │    5. 最后一个处理器执行原始逻辑                                     │
  └────────────────────────────────────────────────────────────────────┘
```

## 5.5 观察者模式

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  观察者模式 — 从 Spring 事件到 Nacos 推送                           │
  │                                                                    │
  │  ① Spring ApplicationEvent                                        │
  │    ApplicationEventPublisher.publishEvent(event)                   │
  │    → @EventListener 方法接收事件                                   │
  │    → 典型事件：ContextRefreshedEvent / RefreshScopeRefreshedEvent   │
  │                                                                    │
  │  ② Nacos 配置变更推送                                              │
  │    ConfigService.addListener(dataId, group, listener)              │
  │    → 长轮询返回 → listener.receiveConfigInfo()                    │
  │    → 触发 @RefreshScope 重建 Bean                                  │
  │                                                                    │
  │ ③ Dubbo 注册中心订阅                                               │
  │    RegistryDirectory.subscribe(url)                                │
  │    → Zookeeper/childrenChanged → notify() → 刷新 Invoker 列表     │
  │    → Nacos/ServiceChanged → notify() → 刷新 ServiceInstance 列表  │
  │                                                                    │
  │  ④ Nacos 服务变更推送                                              │
  │    NamingService.subscribe(serviceName, listener)                  │
  │    → UDP/TCP Push → listener.onEvent() → 更新本地缓存              │
  └────────────────────────────────────────────────────────────────────┘
```

## 5.6 策略模式

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  策略模式 — Dubbo 用得最多                                          │
  │                                                                    │
  │  ① 集群容错策略                                                    │
  │    Cluster 接口 → Failover / Failfast / Failsafe / Forking / ...   │
  │    → 每种策略封装为独立类                                           │
  │    → 通过 @SPI 配置选择                                            │
  │                                                                    │
  │  ② 负载均衡策略                                                    │
  │    LoadBalance 接口 → Random / RoundRobin / LeastActive / ...      │
  │    → 每种算法独立实现                                               │
  │    → 通过 @SPI 配置选择                                            │
  │                                                                    │
  │ ③ 序列化策略                                                      │
  │    Serialization 接口 → Hessian2 / Protobuf / JSON / FastJson      │
  │    → 通过 URL 参数 dynamic 选择                                    │
  │                                                                    │
  │  ④ Spring AOP 代理选择策略                                         │
  │    DefaultAopProxyFactory.createAopProxy()                         │
  │    → if (targetClass 有接口) → JdkDynamicAopProxy                 │
  │    → else → CglibAopProxy                                         │
  │    → 策略选择逻辑在 AopProxyFactory 中                              │
  │                                                                    │
  │  ⑤ Sentinel 流控效果策略                                           │
  │    FlowRule.controller → Default / WarmUp / RateLimiter            │
  │    → 三种效果策略独立实现                                           │
  │    → 通过 FlowRule.controlBehavior 选择                            │
  └────────────────────────────────────────────────────────────────────┘
```

## 5.7 模板方法模式

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  模板方法 — Spring 中的「骨架 + 钩子」                               │
  │                                                                    │
  │  ① AbstractAutowireCapableBeanFactory.createBean()                │
  │    骨架：createBeanInstance → populateBean → initializeBean        │
  │    钩子：BeanPostProcessor 可以覆盖每个步骤                         │
  │                                                                    │
  │  ② TransactionTemplate.execute()                                  │
  │    骨架：getTransaction → action.doInTransaction → commit/rollback │
  │    钩子：TransactionCallback.doInTransaction() 由用户定义           │
  │                                                                    │
  │  ③ MyBatis BaseExecutor.query()                                   │
  │    骨架：queryFromDatabase → prepareStatement → execute → close    │
  │    钩子：SimpleExecutor / ReuseExecutor / BatchExecutor 各有差异    │
  │                                                                    │
  │  ④ Dubbo AbstractClusterInvoker.invoke()                          │
  │    钨架：selectInvoker → doInvoke → 返回结果                       │
  │    钩子：FailoverClusterInvoker.doInvoke() → 重试循环              │
  │          FailfastClusterInvoker.doInvoke() → 直接调用               │
  │          FailsafeClusterInvoker.doInvoke() → 异常吞掉               │
  └────────────────────────────────────────────────────────────────────┘
```

## 5.8 装饰器模式

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  装饰器模式 — 增强功能而不改变接口                                   │
  │                                                                    │
  │  ① MyBatis CachingExecutor 装饰 SimpleExecutor                    │
  │    CachingExecutor.query() → 先查缓存 → delegate.query()          │
  │    → 增加了二级缓存功能                                             │
  │                                                                    │
  │  ② MyBatis TransactionalCache 装饰 PerpetualCache                 │
  │    → 事务未提交时写入暂存区                                          │
  │    → 事务提交后刷入真正的 L2 缓存                                   │
  │    → 增加了事务隔离功能                                             │
  │                                                                    │
  │  ③ Dubbo ProtocolFilterWrapper 装饰 DubboProtocol                 │
  │    → export() 时构建 Filter Chain                                  │
  │    → refer() 时构建 Filter Chain                                  │
  │    → 增加了 Filter 功能                                             │
  │                                                                    │
  │  ④ Dubbo QosProtocolWrapper 装饰 ProtocolFilterWrapper            │
  │    → export() 时启动 QoS Server                                   │
  │    → 增加了运维管理功能                                             │
  │                                                                    │
  │  ⑤ Spring BeanPostProcessor 装饰 Bean                             │
  │    → 在原始 Bean 上叠加代理/增强                                    │
  │    → 增加了 AOP / 事务 / 自定义逻辑                                │
  └────────────────────────────────────────────────────────────────────┘
```

## 5.9 适配器模式

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  适配器模式 — 统一不同接口的调用方式                                 │
  │                                                                    │
  │  ① Spring AOP AdvisorAdapter                                      │
  │    MethodBeforeAdviceAdapter → 将 BeforeAdvice 适配为 MethodInterceptor│
  │    AfterReturningAdviceAdapter → 将 AfterReturningAdvice 适配      │
  │    → 不同类型的 Advice 适配为统一的 Interceptor 接口                 │
  │                                                                    │
  │  ② Spring MVC HandlerAdapter                                      │
  │    SimpleControllerHandlerAdapter → 适配 Controller 接口            │
  │    HttpRequestHandlerAdapter → 适配 HttpRequestHandler 接口         │
  │    RequestMappingHandlerAdapter → 适配 HandlerMethod                │
  │    → 不同类型的 Handler 适配为统一的 handle() 调用                   │
  │                                                                    │
  │  ③ Dubbo RegistryFactory 适配                                      │
  │    ZookeeperRegistryFactory → 适配 Zookeeper                       │
  │    NacosRegistryFactory → 适配 Nacos                               │
  │    → 不同注册中心适配为统一的 Registry 接口                         │
  │                                                                    │
  │  ④ MyBatis TypeHandler 适配                                        │
  │    IntegerTypeHandler → 适配 Integer ↔ JDBC INT                    │
  │    StringTypeHandler → 适配 String ↔ JDBC VARCHAR                  │
  │    → Java 类型 ↔ JDBC 类型 适配                                    │
  └────────────────────────────────────────────────────────────────────┘
```

## 5.10 建造者模式

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  建造者模式 — 分步骤构建复杂对象                                     │
  │                                                                    │
  │  ① BeanDefinitionBuilder                                          │
  │    .beanDefinitionClass(OrderService.class)                        │
  │    .addPropertyValue("name", "order")                              │
  │    .addAutowiredProperty("userService")                            │
  │    .setScope("singleton")                                         │
  │    → 分步构建 BeanDefinition                                       │
  │                                                                    │
  │  ② Gateway Route.Builder                                           │
  │    Route.builder()                                                 │
  │      .id("order-service")                                          │
  │      .uri("lb://order-service")                                    │
  │      .predicate(path("/api/orders/**"))                            │
  │      .filter(addRequestHeader("X-Source", "gateway"))              │
  │      → 分步构建 Route 对象                                          │
  │                                                                    │
  │  ③ Dubbo URL 构建                                                  │
  │    URL.valueOf("dubbo://192.168.1.10:20880/UserService?version=1.0")│
  │    → 解析协议 + 主机 + 端口 + 参数 = URL 对象                       │
  │    → URL 是 Dubbo 的统一配置总线                                    │
  │                                                                    │
  │ ④ MyBatis XMLMapperBuilder                                        │
  │    .parse() → configurationElement() → buildStatementFromContext() │
  │    → 分步解析 XML → 构建 Configuration + MappedStatement           │
  └────────────────────────────────────────────────────────────────────┘
```

## 5.11 享元模式

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  享元模式 — 共享不可变对象以节省内存                                  │
  │                                                                    │
  │  ① JDK Proxy WeakCache                                            │
  │    同一个接口 + 同一 Loader + 同一 InvocationHandler                │
  │    → 共享同一个 $Proxy0 类（Class 对象）                            │
  │    → 只是实例不同，但类定义共享                                      │
  │                                                                    │
  │  ② Dubbo ExtensionLoader cachedInstances                          │
  │    同一个 SPI 扩展名 → 共享同一个实例                                │
  │    → 不重复创建，从缓存获取                                         │
  │                                                                    │
  │ ③ Sentinel StatisticNode ArrayMetric                              │
  │    LeapArray 的 AtomicReferenceArray<WindowWrap<MetricBucket>>     │
  │    → 窗口对象循环使用（时间窗口滑动后旧窗口被新数据覆盖）              │
  │    → 不创建新对象，复用旧窗口                                       │
  │                                                                    │
  │  ④ Spring singletonObjects                                        │
  │    Bean 实例全局共享 → 所有注入点引用同一个对象                       │
  │    → 和享元模式的目标一致：减少对象创建                               │
  └────────────────────────────────────────────────────────────────────┘
```

## 5.12 回调模式

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  回调模式 — 我调用你，你完成后回调我                                 │
  │                                                                    │
  │  ① Spring Aware 回调                                              │
  │    BeanNameAware.setBeanName() → 容器回调 Bean                     │
  │    ApplicationContextAware.setApplicationContext() → 容器回调 Bean  │
  │    → 容器在 Bean 初始化的某个阶段回调 Bean                           │
  │                                                                    │
  │  ② BeanPostProcessor 回调                                          │
  │    postProcessBeforeInitialization() → 容器回调后处理器              │
  │    postProcessAfterInitialization() → 容器回调后处理器               │
  │    → 后处理器可以修改/替换 Bean                                     │
  │                                                                    │
  │ ③ Dubbo AsyncCallback                                              │
  │    AsyncToSyncInvoker.invoke() → future.get() → 同步等待           │
  │    CompletableFuture.whenComplete() → 异步回调                     │
  │    → RPC 调用完成后回调业务逻辑                                     │
  │                                                                    │
  │  ④ Nacos 长轮询回调                                               │
  │    AsyncContext.start() → hold 29.5s → complete() → 回调客户端      │
  │    → 配置变更后回调客户端刷新                                       │
  └────────────────────────────────────────────────────────────────────┘
```

---

# 第六部分 面试串讲 — 50 个高频问题的一条线回答

## 6.1 IoC/DI 系列（10 题）

### Q1：Spring IoC 容器的启动流程？
```
一条线：Class 扫描 → BeanDefinition 注册 → BeanFactoryPostProcessor 修改
→ 实例化 → 属性注入 → Aware 回调 → BeanPostProcessor → 初始化 → 放入缓存

关键源码：AbstractApplicationContext.refresh() 12 步
```

### Q2：Spring 如何解决循环依赖？
```
一条线：实例化 A → 三级缓存 ObjectFactory 暴露 → 创建 B → B 需要 A
→ 从三级缓存获取 A 的 ObjectFactory → 如果需要代理就提前创建 → 放入二级缓存
→ B 完成 → A 完成

关键：三级缓存（singletonFactories）的 ObjectFactory 延迟了代理决策
为什么不能两级：没有 ObjectFactory 就必须在实例化后立即决定是否代理，但正常代理时机是 postProcessAfterInitialization
```

### Q3：@Autowired 注入原理？
```
一条线：MergedBeanDefinitionPostProcessor 收集 @Autowired 元数据
→ AutowiredAnnotationBeanPostProcessor.postProcessProperties()
→ resolveDependency() → findAutowireCandidates() → 按类型匹配
→ 如果多个 → @Qualifier 按名称筛选 → 如果还多个 → @Primary 优先

注意：@Autowired 注入的是容器中的 Bean（可能是代理对象）
```

### Q4：BeanFactory 和 ApplicationContext 的区别？
```
一条线：BeanFactory 是基础容器（getBean）
ApplicationContext = BeanFactory + MessageSource + ResourceLoader + ApplicationEventPublisher
+ Lifecycle + AOP 集成 + 国际化 + 事件机制

ApplicationContext 内部持有一个 DefaultListableBeanFactory
所有 getBean 最终还是走 BeanFactory
```

### Q5：FactoryBean 和 BeanFactory 的区别？
```
一条线：BeanFactory 是容器（生产各种 Bean 的工厂）
FactoryBean 是特殊的 Bean（生产特定类型 Bean 的工厂）

FactoryBean.getObject() 返回的才是真正的 Bean
FactoryBean 自身也被容器管理（&factoryBean 获取 FactoryBean 本身）

典型应用：MapperFactoryBean（MyBatis）、ReferenceBean（Dubbo）
```

### Q6：Spring 事件机制原理？
```
一条线：ApplicationEventPublisher.publishEvent()
→ SimpleApplicationEventMulticaster.multicastEvent()
→ 遍历 @EventListener 方法 → 执行监听逻辑

典型事件：ContextRefreshedEvent（容器启动完成）
→ Dubbo ServiceBean.onApplicationEvent() → export()
```

### Q7：Spring 如何整合 MyBatis？
```
一条线：@MapperScan → MapperScannerConfigurer（BeanDefinitionRegistryPostProcessor）
→ 扫描 @Mapper 接口 → 为每个接口注册 MapperFactoryBean（FactoryBean）
→ MapperFactoryBean.getObject() → sqlSession.getMapper() → MapperProxy 代理

SqlSessionTemplate 保证线程安全（每次获取新 SqlSession）
SpringManagedTransaction 从 ThreadLocal 获取事务 Connection
```

### Q8：Spring 如何整合 Dubbo？
```
一条线：@DubboService → ServiceBean（FactoryBean + InitializingBean + ApplicationListener）
→ afterPropertiesSet() → export() → RegistryProtocol → 注册中心注册 + Netty Server

@DubboReference → ReferenceBean（FactoryBean + InitializingBean）
→ getObject() → createProxy() → Invoker 代理

★ ServiceBean 监听 ContextRefreshedEvent 才触发 export（延迟到容器启动完成）
★ ReferenceBean 在 afterPropertiesSet 中就触发 refer（注入时就需要代理）
```

### Q9：@RefreshScope 如何实现动态刷新？
```
一条线：Nacos 配置变更 → 长轮询通知 → listener.receiveConfigInfo()
→ Spring Cloud 发布 RefreshEvent → RefreshScope.refreshAll()
→ 清除 @RefreshScope Bean 的缓存 → 下次 getBean() 重新创建
→ 新 Bean 使用新配置值

@RefreshScope Bean 不在 singletonObjects 中，而是在 CachingScopedBeanFactory
```

### Q10：为什么 Spring 默认单例？有没有问题？
```
一条线：单例减少对象创建开销 + 线程安全（容器创建一次）
问题：单例 Bean 中注入的属性也是单例 → 有状态数据不安全

解决：
1. 有状态数据用 @Scope("prototype")
2. 使用 ThreadLocal（如 TransactionSynchronizationManager）
3. 用原型 Bean 注入到单例中（@Lookup 方法注入）
```

## 6.2 AOP/代理 系列（10 题）

### Q11：Spring AOP 的代理创建时机？
```
一条线：AbstractAutoProxyCreator（BeanPostProcessor）
→ postProcessAfterInitialization()
→ wrapIfNecessary() → findEligibleAdvisors() → createProxy()
→ 在 Bean 初始化后创建代理

特殊情况：循环依赖时提前创建代理（通过三级缓存 ObjectFactory）
```

### Q12：JDK Proxy 和 CGLIB 的选择策略？
```
一条线：DefaultAopProxyFactory.createAopProxy()
→ if (targetClass 有接口 && proxyTargetClass=false) → JDK Proxy
→ else → CGLIB

默认行为：有接口用 JDK，没有用 CGLIB
spring.aop.proxy-target-class=true → 强制 CGLIB（Spring Boot 2.x 默认）
```

### Q13：AOP Advice 的执行顺序？
```
一条线：ReflectiveMethodInvocation.proceed()
→ 递归调用每个 Advice：
  @Around → proceed() → @Before → proceed() → 原始方法 → @After → @AfterReturning

执行顺序图：
  Around.start
    → Before
      → 原始方法
    → AfterReturning
    → After
  Around.end

异常时：@AfterThrowing 替代 @AfterReturning，@After 仍然执行
```

### Q14：@Transactional 代理的内部结构？
```
一条线：CGLIB 代理 → TransactionInterceptor（Advice Chain 中一个节点）
→ invokeWithinTransaction()
→ doBegin()（获取 Connection，关闭自动提交，绑定 ThreadLocal）
→ invocation.proceed()（执行原始方法）
→ commit/rollback（根据异常决定）

★ Connection 通过 ThreadLocal 传递给 MyBatis 的 SpringManagedTransaction
★ 这就是 @Transactional 和 MyBatis 串联的核心
```

### Q15：@Transactional 失效的场景？
```
一条线：6 种失效场景的本质都是"代理没有拦截到方法调用"

1. 自调用：同一 Bean 内方法 A 调方法 B → 绕过代理（this.methodB()）
2. 非 public 方法：CGLIB/JDK Proxy 只拦截 public
3. final 方法：CGLIB 无法代理 final 方法
4. 异常类型不匹配：rollbackFor 没覆盖实际异常类型
5. 异常被 catch 吞掉：代理看不到异常 → 不回滚
6. 传播行为不当：PROPAGATION_NOT_SUPPORTED / NEVER 不创建事务

解决：1 用 AopContext.currentProxy()  2-3 改方法修饰符  4 指定 rollbackFor  5 手动 rollback  6 检查传播行为
```

### Q16：Dubbo 的代理和 Spring AOP 的代理有什么区别？
```
一条线：Spring AOP 代理 → 增强本地方法调用（事务/日志/权限）
Dubbo 代理 → 替换本地方法调用为远程 RPC 调用

Spring AOP：代理对象.方法() → 增强逻辑 → 原始对象.方法()（本地执行）
Dubbo：    代理对象.方法() → Invoker → Filter → Netty → 远程执行（不在本地）

★ Spring AOP 代理的原始对象在本地
★ Dubbo 代理的"原始对象"在远程机器上
```

### Q17：MyBatis MapperProxy 和 JDK Proxy 有什么区别？
```
一条线：MapperProxy 是 JDK Proxy 的 InvocationHandler 实现
→ 但它不需要原始对象（因为接口不能实例化）
→ 每次调用都走 MapperMethod.execute() → SqlSession → SQL 执行

普通 JDK Proxy：需要 InvocationHandler 持有目标对象
MapperProxy：没有目标对象，所有调用都走 MyBatis SQL 执行路径

本质：MapperProxy 是 JDK Proxy 的特殊用法——代理接口，目标"方法"是 SQL
```

### Q18：CGLIB 的 FastClass 为什么比 JDK Proxy 快？
```
一条线：JDK Proxy 调用原始方法 → Method.invoke()（反射调用，每次查方法表）
CGLIB 调用原始方法 → MethodProxy.invokeSuper() → FastClass.getIndex(method) → 索引直接定位方法 → 直接调用

FastClass：为代理类和原始类分别生成索引类
→ 方法签名 → int 索引 → 直接调用对应方法（跳过反射查找）

代价：生成更多类（代理类 + 2 个 FastClass），但调用更快
```

### Q19：@EnableAspectJAutoProxy 做了什么？
```
一条线：@EnableAspectJAutoProxy → @Import(AspectJAutoProxyRegistrar.class)
→ registerBeanDefinitions() → 注册 AnnotationAwareAspectJAutoProxyCreator（BeanDefinition）

AnnotationAwareAspectJAutoProxyCreator 是 BeanPostProcessor
→ postProcessAfterInitialization() → findAdvisors()
→ 扫描 @Aspect 类 → ReflectiveAspectJAdvisorFactory.getAdvice()
→ @Before → AspectJMethodBeforeAdvice
→ @Around → AspectJAroundAdvice
→ @After → AspectJAfterAdvice
→ @AfterReturning → AspectJAfterReturningAdvice
→ @AfterThrowing → AspectJAfterThrowingAdvice
```

### Q20：一个方法可能被多少层代理？
```
一条线：最多 3 层代理（Spring 全家桶实际场景）

第 1 层：Spring AOP CGLIB 代理（@Transactional + 自定义 @Aspect）
第 2 层：属性注入的代理（MapperProxy / Dubbo InvokerProxy）
第 3 层：Dubbo SPI Wrapper 代理（ProtocolFilterWrapper 包装 Protocol）

但注意：第 2、3 层代理不是叠加在同一个方法上，而是不同的 Bean
→ AOP 代理包裹原始方法
→ 原始方法内部调用的 userService 是 Dubbo 代理（另一个 Bean）
→ Dubbo 代理内部调用的 Protocol 是 Wrapper 代理（又一个 Bean）

★ 代理是嵌套调用，不是代理叠加
```

## 6.3 事务 系列（8 题）

### Q21：@Transactional 的七种传播行为？
```
一条线：TransactionInterceptor.invokeWithinTransaction()
→ getTransaction() → TransactionDefinition.getPropagationBehavior()

REQUIRED（默认）：有事务加入，无事务新建
SUPPORTS：有事务加入，无事务非事务运行
MANDATORY：必须在事务中，否则抛异常
REQUIRES_NEW：总是新建事务，外层事务挂起
NOT_SUPPORTED：非事务运行，有事务挂起
NEVER：必须非事务，有事务抛异常
NESTED：有事务则嵌套（savepoint），无事务新建
```

### Q22：事务传播行为 REQUIRED vs REQUIRES_NEW 的源码差异？
```
一条线：REQUIRED → joinExistingTransaction() → 使用外层 Connection
REQUIRES_NEW → doBegin() → 新 Connection + 新 ThreadLocal 绑定 → 外层 Connection 挂起

REQUIRES_NEW 源码：
  doBegin() → new Connection → setAutoCommit(false)
  → TransactionSynchronizationManager.bindResource(dataSource, newConnHolder)
  → 外层 connHolder 保存到新事务的 suspendedResources
  → 事务完成后 → resumeTransaction() → 恢复外层 Connection 到 ThreadLocal

★ REQUIRES_NEW 用了不同的 Connection → 不同的数据库连接
★ 内层事务回滚不影响外层事务
```

### Q23：@Transactional 和 MyBatis 的 Connection 如何绑定？
```
一条线：@Transactional.doBegin() → Connection 绑定 ThreadLocal
→ MyBatis SpringManagedTransaction.getConnection()
→ 从 ThreadLocal 获取同一个 Connection

★ 同一个事务内所有 MyBatis 操作用同一个 Connection
★ 不同事务用不同 Connection
★ 非 @Transactional 方法 → MyBatis 每次获取新 Connection（无事务控制）
```

### Q24：事务回滚规则？
```
一条线：TransactionInterceptor.completeTransactionAfterThrowing()
→ rollbackOn() → 判断异常是否匹配回滚规则

默认规则：
  RuntimeException + Error → 回滚
  checked Exception → 不回滚

自定义：@Transactional(rollbackFor = Exception.class) → 所有异常回滚
noRollbackFor = BusinessException.class → 指定异常不回滚

★ 异常类型检查是深度继承检查（子类也算）
```

### Q25：事务隔离级别如何生效？
```
一条线：DataSourceTransactionManager.doBegin()
→ Connection.setTransactionIsolation(level)

ISOLATION_DEFAULT → 使用数据库默认（MySQL 是 REPEATABLE_READ）
ISOLATION_READ_UNCOMMITTED → Connection 设置 READ_UNCOMMITTED
ISOLATION_READ_COMMITTED → Connection 设置 READ_COMMITTED
ISOLATION_REPEATABLE_READ → Connection 设置 REPEATABLE_READ
ISOLATION_SERIALIZABLE → Connection 设置 SERIALIZABLE

★ Spring 只是调用 JDBC API 设置隔离级别
★ 实际隔离效果取决于数据库引擎实现
```

### Q26：分布式事务方案？
```
一条线：本地事务 → @Transactional（单库）
→ 跨服务事务 → 需要分布式方案

1. 2PC（XA）：Seata AT 模式 / XA Protocol
   → 全局事务协调器 → 一阶段分支注册 → 二阶段 commit/rollback
   → 性能差（锁等待长）但强一致

2. TCC：Seata TCC 模式
   → Try → Confirm → Cancel 三个阶段
   → 性能好但代码复杂（需要写三套逻辑）

3. Saga：长事务拆分
   → 正向补偿链 → 失败反向补偿链
   → 适合业务流程长的事务

4. 最终一致：RocketMQ 事务消息
   → 半消息 → 本地事务 → commit/rollback → 消费者处理
   → 性能好但只能最终一致

★ 实际选型：大多数场景用最终一致（MQ），强一致场景用 Seata AT
```

### Q27：事务超时如何实现？
```
一条线：@Transactional(timeout = 30)
→ TransactionDefinition.getTimeout() = 30 秒
→ DataSourceTransactionManager.doBegin()
→ ConnectionHolder.setTimeoutInSeconds(30)
→ deadline = System.currentTimeMillis() + 30 * 1000

→ 每次操作前检查：if (System.currentTimeMillis() > deadline) → 抛 TransactionTimedOutException

★ 超时检查不是数据库层面的，而是 Spring 在每次操作前检查
★ 超时是从事务开始时计算，不是从单条 SQL 开始
```

### Q28：只读事务有什么用？
```
一条线：@Transactional(readOnly = true)
→ DataSourceTransactionManager.doBegin()
→ Connection.setReadOnly(true) ← 通知数据库这是只读事务

效果：
1. MySQL InnoDB → 不加排他锁，只加共享锁 → 提高并发
2. Hibernate → 不做脏检查 → flush 不写数据库
3. Spring → 标记 Connection 为只读 → 部分连接池可能路由到读库

★ readOnly 只是"建议"，数据库可以忽略
★ 如果在只读事务中写数据 → 不同数据库行为不同（MySQL 允许写，但会警告）
```

## 6.4 微服务 系列（12 题）

### Q29：Nacos 服务注册的完整流程？
```
一条线：Spring Cloud Nacos Discovery AutoConfiguration
→ NacosServiceRegistry.register()
→ NamingService.registerInstance(serviceName, instance)
→ gRPC/HTTP 请求发送到 Nacos Server
→ Nacos Server → ServiceManager.putInstanceAndDeploy() → Distro 协议同步到其他节点
→ 客户端 → 心跳保活（5s 间隔 / 15s 超时 / 30s 删除）

Dubbo 注册类似但用 RegistryProtocol：
→ ZookeeperRegistry.register() → createEphemeralNode() → 临时节点
→ NacosRegistry.register() → NamingService.registerInstance()
```

### Q30：Nacos 配置长轮询机制？
```
一条线：ConfigService.getConfigAndSignListener()
→ gRPC 请求到 Nacos Server → Server 检查配置 MD5
→ MD5 未变 → hold 请求 29.5s（AsyncContext.start() + scheduledFuture 延迟 29.5s）
→ MD5 变了 → 立即返回新配置
→ 29.5s 到了 → 返回空响应 → 客户端再次长轮询

★ 长轮询是"伪推送"：客户端主动拉，服务端 hold 等变
★ 和 WebSocket 的区别：长轮询每次都是新 HTTP 请求
```

### Q31：Sentinel 滑动窗口统计原理？
```
一条线：LeapArray（10 个 1s 窗口）
→ 当前时间 → 计算窗口索引 → AtomicReferenceArray[index]
→ WindowWrap<MetricBucket> → MetricBucket 统计 pass/block/exception/rt
→ CAS 更新：compareAndSet(null, newWrap) → 当前窗口重置：reset()

→ FlowSlot 检查 → FlowRuleChecker.canPassCheck()
→ 统计当前 QPS = 当前窗口.pass + 前面窗口.pass
→ 如果 QPS > rule.count → 拒绝
```

### Q32：Sentinel 熔断状态转换？
```
一条线：CLOSED → OPEN → HALF_OPEN → CLOSED

CLOSED（正常）：请求正常通过，统计慢调用/异常比例
→ 达到阈值 → 转换为 OPEN

OPEN（熔断）：所有请求直接拒绝，不执行业务
→ 熔断时间到期 → 转换为 HALF_OPEN

HALF_OPEN（探测）：允许一个请求通过
→ 如果成功 → 转回 CLOSED
→ 如果失败 → 转回 OPEN

三种策略：
1. 慢调用比例：responseTime > maxRT 的比例 > ratio → 熔断
2. 异常比例：exception / total > ratio → 熔断
3. 异常数：exception count > count → 熔断
```

### Q33：Gateway 路由匹配原理？
```
一条线：RoutePredicateHandlerMapping.getHandlerInternal()
→ 遍历所有 Route → 逐一检查 Predicate
→ PathPredicate / MethodPredicate / HeaderPredicate / HostPredicate 等
→ 所有 Predicate 都满足 → Route 匹配成功

→ 匹配后 → Filter Chain 执行
→ 路由优先级：order 值越小越优先
```

### Q34：Gateway Filter 执行顺序？
```
一条线：GlobalFilter（所有路由共享） + GatewayFilter（特定路由）
→ 合并排序 → 按 order 值从小到大执行

前置阶段（request 修改）：ReactiveLoadBalancerClientFilter → NettyRoutingFilter
后置阶段（response 修改）：NettyWriteResponseFilter → LoggingFilter

★ GlobalFilter 和 GatewayFilter 混合排序
★ order 值小的先执行 pre，后执行 post（责任链嵌套）
```

### Q35：Dubbo SPI 和 Java SPI 的核心区别？
```
一条线：Java SPI → ServiceLoader → 全部加载 → 无选择能力
Dubbo SPI → ExtensionLoader → 按需加载 → @Adaptive 动态选择 → IOC 注入 → Wrapper AOP

关键差异：
1. 按需加载：getExtension("dubbo") 只加载 DubboProtocol
2. @Adaptive：根据 URL 参数动态选择实现
3. IOC 注入：ExtensionFactory 自动注入依赖
4. Wrapper AOP：ProtocolFilterWrapper 自动包装增强
5. @Activate：条件激活（只在特定条件下生效）
```

### Q36：Dubbo 服务导出的完整流程？
```
一条线：ServiceBean.afterPropertiesSet()
→ export() → doExport() → doExportUrls()
→ RegistryProtocol.export()
→ doLocalExport() → DubboProtocol.export()
→ createExporter() → openServer() → NettyServer 启动
→ 注册到注册中心 → Zookeeper/Nacos createNode()

→ ServiceBean 还监听 ContextRefreshedEvent → 延迟到容器启动完成再 export
★ 这和 Spring IoC 的 refresh() 12 步衔接
```

### Q37：Dubbo 服务引用的完整流程？
```
一条线：ReferenceBean.getObject()
→ init() → createProxy()
→ RegistryProtocol.refer()
→ doRefer() → RegistryDirectory.subscribe()
→ 注册中心订阅 → notify() → 刷新 Invoker 列表
→ DubboInvoker 创建 → NettyClient 连接
→ 创建代理对象返回

★ ReferenceBean 是 FactoryBean → getObject() 返回代理
★ 代理对象注入到其他 Bean → 调用时走 Dubbo RPC
```

### Q38：Dubbo 集群容错的几种策略？
```
一条线：ClusterInvoker.invoke() → 调用策略

Failover（默认）：失败重试其他 Provider → retry=2 → 最多调 3 次
Failfast：失败立即报错 → 不重试 → 适合非幂等操作
Failsafe：失败吞掉异常 → 返回空结果 → 适合日志/监控写入
Forking：并行调用多个 → 任一成功即返回 → 适合实时性要求高
Broadcast：逐个调用所有 → 任一失败则报错 → 适合通知/更新缓存
Mergeable：分组聚合 → 多个分组结果合并 → 适合多数据源
```

### Q39：Dubbo 负载均衡算法？
```
一条线：LoadBalance.doSelect() → 选择 Invoker

Random（默认）：加权随机 + 预热权重计算（warmup 期间权重降低）
RoundRobin：平滑加权轮询（避免连续选同一节点）
LeastActive：最少活跃调用数（选当前并发最低的）
ConsistentHash：一致性哈希 + 160 虚拟节点 → 相同参数总到同一 Provider
ShortestResponse：最短响应时间（选响应最快的）← Dubbo 2.7.5 新增
```

### Q40：Dubbo vs Spring Cloud 怎么选？
```
一条线：按业务场景选型

Dubbo 适合：
- Java 技术栈统一
- 内部服务间高频调用
- 性能敏感（二进制协议 + 长连接）
- 需要精细的 RPC 控制（超时/重试/负载均衡）

Spring Cloud 适合：
- 多语言技术栈
- 对外 API + 内部服务混合
- HTTP 协议友好（浏览器/前端/第三方兼容）
- Spring 生态深度依赖

混合架构：
- 外层 Gateway（Spring Cloud Gateway）对外 HTTP
- 内层 Dubbo RPC 服务间高频调用
- 共用 Nacos 注册中心 + 配置中心
- 共用 Sentinel 流控熔断
```

## 6.5 MyBatis 系列（10 题）

### Q41：MyBatis 的完整执行流程？
```
一条线：MapperProxy.invoke()
→ MapperMethod.execute()
→ SqlSession.selectList()/insert()/update()/delete()
→ Executor.query()/update()
→ CachingExecutor → 二级缓存检查
→ SimpleExecutor → 一级缓存检查 → queryFromDatabase()
→ StatementHandler.prepare()
→ ParameterHandler.setParameters()
→ Statement.execute()
→ ResultSetHandler.handleResultSets()
→ 返回结果
```

### Q42：MyBatis 一级缓存和二级缓存的区别？
```
一条线：一级缓存（SqlSession 级别）
→ PerpetualCache（HashMap）→ 同一 SqlSession 内共享
→ commit/close/update 时清空
→ 线程不安全（SqlSession 不是线程安全的）

二级缓存（Mapper namespace 级别）
→ CachingExecutor + TransactionalCacheManager
→ 事务未提交 → 数据在暂存区（TransactionalCache）
→ 事务提交 → 暂存区数据刷入正式 L2（PerpetualCache）
→ 线程安全（TransactionalCache 装饰器保证隔离）

★ 多实例部署时 L2 不共享 → 一般改用 Redis
```

### Q43：MyBatis 插件（Interceptor）机制？
```
一条线：Plugin.wrap(target, interceptor)
→ 四大对象：Executor / StatementHandler / ParameterHandler / ResultSetHandler
→ 为每个对象创建 JDK Proxy 代理
→ InterceptorChain.pluginAll() → 依次包装

→ 调用时 → Interceptor.invoke() → intercept() → 自定义逻辑
→ invocation.proceed() → 继续执行原始方法

★ 多个 Interceptor 会多层代理（类似 Dubbo Filter Chain）
★ @Intercepts + @Signature 指定拦截哪个对象的哪个方法
```

### Q44：MyBatis 动态 SQL 的 SqlNode 体系？
```
一条线：XMLScriptBuilder.parseDynamicNode()
→ MixedSqlNode（根节点）→ 包含多个子 SqlNode
→ IfSqlNode（<if test="...">）→ OgnlUtil.evaluateBoolean() → 条件判断
→ WhereSqlNode（<where>）→ 自动去掉前缀 AND/OR
→ SetSqlNode（<set>）→ 自动去掉末尾逗号
→ ForeachSqlNode（<foreach>）→ 循环展开 + 添加分隔符
→ ChooseSqlNode（<choose>/<when>/<otherwise>）→ switch-case
→ TrimSqlNode（<trim>）→ 通用前缀/后缀裁剪

→ DynamicSqlSource vs RawSqlSource
→ DynamicSqlSource：每次执行时重新解析 SqlNode → 生成 BoundSql
→ RawSqlSource：编译时解析一次 → 缓存 BoundSql
```

### Q45：MyBatis-Spring 的自动装配原理？
```
一条线：@MapperScan → MapperScannerConfigurer
→ processBeanDefinitions() → 为每个 @Mapper 接口注册 MapperFactoryBean
→ MapperFactoryBean.getObject() → SqlSession.getMapper()

SqlSessionTemplate（线程安全的 SqlSession）：
→ 代理 SqlSession → 每次操作获取新 SqlSession（从 SqlSessionFactory）
→ 但在 @Transactional 内 → 使用同一个 SqlSession（事务绑定）

SpringManagedTransaction：
→ 从 ThreadLocal 获取当前事务的 Connection
→ 和 @Transactional 串联的关键
```

### Q46：MyBatis 如何处理结果映射？
```
一条线：ResultSetHandler.handleResultSets()
→ ResultSetWrapper（封装 ResultSet + 列名 + 类型映射）
→ ResultMapResolver → 解析 <resultMap> 配置
→ DefaultResultHandler → 按映射规则创建 Java 对象

嵌套映射：
→ <association> → 创建嵌套对象 + 嵌套查询/嵌套结果映射
→ <collection> → 创建集合 + 嵌套查询/嵌套结果映射
→ <discriminator> → 根据某列值决定使用哪个 ResultMap

延迟加载：
→ ProxFactory.createProxy() → CGLIB/Javassist 代理嵌套对象
→ 调用 getter 时才触发嵌套查询
```

### Q47：MyBatis TypeHandler 机制？
```
一条线：TypeHandlerRegistry → 注册 Java ↔ JDBC 类型映射
→setParameter()：Java → JDBC（设置 PreparedStatement 参数）
→getResult()：JDBC → Java（从 ResultSet 获取结果）

内置：IntegerTypeHandler / StringTypeHandler / DateTypeHandler / ...
自定义：@MappedTypes + @MappedJdbcTypes → 实现 TypeHandler<T>

★ TypeHandler 是 MyBatis 灵活性的核心
★ 任何自定义类型都可以通过 TypeHandler 映射
```

### Q48：MyBatis Executor 三种类型的区别？
```
一条线：SimpleExecutor：每次创建新 Statement → 用完关闭
ReuseExecutor：缓存 Statement（key = SQL 字符串）→ 同一 SQL 复用
BatchExecutor：批量执行 → Statement.addBatch() → 一次性 executeBatch()
→ 适合批量插入/更新场景

★ 默认用 SimpleExecutor
★ 通过 configuration.setDefaultExecutorType() 切换
★ Spring Boot 默认也是 SimpleExecutor
```

### Q49：MyBatis 如何防止 SQL 注入？
```
一条线：ParameterHandler.setParameters()
→ 使用 PreparedStatement（预编译）→ 参数用 ? 占位 → setValue() 设置参数值
→ 不拼接 SQL 字符串 → 参数不会被当作 SQL 语法解析

动态 SQL 的 <if>/<where>/<foreach>：
→ 拼接的是 SQL 结构（关键字/表名），不是参数值
→ 参数值始终通过 PreparedStatement.setXXX() 设置
→ 安全性由 PreparedStatement 保证

★ #{} → PreparedStatement 参数占位 → 安全
★ ${} → 字符串直接拼接 → 不安全（仅用于表名/列名等结构性参数）
```

### Q50：MyBatis 一级缓存什么时候会出问题？
```
一条线：一级缓存的坑 — 同一 SqlSession 内数据不一致

场景1：SqlSession 查 A → 别人改了 A → SqlSession 再查 A → 返回旧数据
→ 因为 L1 缓存没清空 → 拿到脏数据

场景2：Spring + MyBatis + 非 @Transactional
→ SqlSessionTemplate 每次获取新 SqlSession → L1 缓存每次都是空的
→ L1 缓存完全无效

场景3：Spring + MyBatis + @Transactional
→ 同一事务内用同一 SqlSession → L1 缓存有效
→ 但事务内修改数据 → L1 不自动清空（除非显式 update()）

★ 实际开发中一级缓存的坑很少遇到
★ 因为 Spring 环境下 SqlSessionTemplate 一般不用 L1
★ @Transactional 内的 L1 在事务结束时清空
```

---

# 第七部分 实战架构设计 — 从零设计一个微服务系统的关键决策

## 7.1 单体 → 微服务拆分策略

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                  拆分策略 — 渐进式，不是一刀切                     │
  │                                                                  │
  │  第一步：识别边界                                                  │
  │    ├── 按业务域拆分（DDD Bounded Context）                        │
  │    │   用户域 → UserService                                      │
  │    │   订单域 → OrderService                                     │
  │    │   商品域 → ProductService                                   │
  │    │   支付域 → PaymentService                                   │
  │    │                                                              │
  │    ├── 按变更频率拆分（高频独立部署）                               │
  │    │   高频变更 → 独立服务                                        │
  │    │   低频变更 → 合并到一个服务                                   │
  │    │                                                              │
  │    └── 按团队拆分（康威定律）                                      │
  │    │   团队 A → 服务 A                                           │
  │    │   团队 B → 服务 B                                           │
  │                                                                  │
  │  第二步：先剥离最独立的服务                                        │
  │    → 用户服务（最少依赖）                                          │
  │    → 使用 Strangler Pattern（绞杀者模式）                          │
  │      ├── 新功能走新服务                                            │
  │      ├── 旧功能逐步迁移                                            │
  │      ├── Gateway 路由分流                                          │
  │      ├── 最终旧代码完全被替代                                       │
  │                                                                  │
  │  第三步：基础设施搭建                                              │
  │    → 注册中心（Nacos）                                            │
  │    → 配置中心（Nacos Config）                                     │
  │    → 网关（Spring Cloud Gateway）                                 │
  │    → 流控（Sentinel）                                             │
  │    → RPC（Dubbo 或 Spring Cloud OpenFeign）                      │
  │                                                                  │
  │  第四步：逐步迁移                                                  │
  │    → 每次迁移一个服务 → 验证 → 再迁移下一个                        │
  │    → 保持向后兼容（API 版本管理）                                  │
  │    → 数据库先共享 → 逐步拆分                                      │
  └──────────────────────────────────────────────────────────────────┘
```

## 7.2 注册中心选型决策树

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                  注册中心选型决策树                                │
  │                                                                  │
  │  你的技术栈是什么？                                                │
  │      │                                                            │
  │      ├── 纯 Java（Dubbo + Spring Cloud Alibaba）                  │
  │      │   → Nacos（首选）                                          │
  │      │   → 理由：同时支持注册+配置+AP/CP切换                       │
  │      │                                                            │
  │      ├── Java（Dubbo 2.x 传统）                                    │
  │      │   → Zookeeper（兼容性好）                                   │
  │      │   → 理由：Dubbo 原生支持 + 久经考验                         │
  │      │                                                            │
  │      ├── 多语言 + Kubernetes                                       │
  │      │   → Consul + K8s Service                                   │
  │      │   → 理由：健康检查 + KV + 多语言 + K8s 原生                 │
  │      │                                                            │
  │      ├── 只用 Spring Cloud Netflix（遗留系统）                     │
  │      │   → Eureka（兼容）                                          │
  │      │   → 理由：已停维但还能用                                    │
  │      │                                                            │
  │      ├── 混合架构（Dubbo + Spring Cloud）                         │
  │      │   → Nacos（唯一同时支持两者）                               │
  │      │   → 理由：Dubbo + Spring Cloud 共用一个注册中心              │
  │      │                                                            │
  │  你需要配置中心吗？                                                │
  │      │                                                            │
  │      ├── 需要 → Nacos（内置）或 Apollo（精细管理）                 │
  │      ├── 不需要 → Zookeeper / Consul / Eureka                     │
  │                                                                  │
  │  你需要 AP 还是 CP？                                              │
  │      │                                                            │
  │      ├── AP（注册允许短暂不一致）→ Nacos（Distro）/ Eureka         │
  │      ├── CP（注册必须强一致）→ Zookeeper（ZAB）/ Consul（Raft）    │
  │      ├── 两者都要 → Nacos（临时实例 AP + 永久实例 CP）             │
  └──────────────────────────────────────────────────────────────────┘
```

## 7.3 网关层设计

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                  Gateway 层设计要点                                │
  │                                                                  │
  │  ① 路由配置                                                       │
  │    ├── 动态路由（Nacos Config 掉）                                 │
  │    │   → 路由配置放在 Nacos → @RefreshScope 动态刷新              │
  │    │   → 不重启即可增删路由                                        │
  │    │                                                              │
  │    ├── 静态路由（application.yml）                                 │
  │    │   → 简单场景够用                                              │
  │    │   → 修改需要重启                                              │
  │                                                                  │
  │  ② 流控熔断                                                       │
  │    ├── Gateway Sentinel 集成                                      │
  │    │   → SentinelGatewayFilter（GlobalFilter）                    │
  │    │   → 流控规则从 Nacos 数据源 Push                              │
  │    │   → 熔断规则从 Nacos 数据源 Push                              │
  │    │                                                              │
  │    ├── 限流维度                                                    │
  │    │   → 按 Route ID（整路由限流）                                 │
  │    │   → 按 API Group（分组限流）                                  │
  │    │   → 按 IP（单 IP 限流）                                      │
  │    │   → 按 参数（热点参数限流）                                   │
  │                                                                  │
  │  ③ 认证鉴权                                                       │
  │    ├── JWT Token 验证（GlobalFilter）                              │
  │    │   → 解析 JWT → 校验签名 → 放入 Header                       │
  │    │                                                              │
  │    ├── OAuth2 + Spring Security                                   │
  │    │   → 统一认证 → Token 传递 → 下游服务信任 Gateway              │
  │    │                                                              │
  │    ├── RBAC 权限控制                                               │
  │    │   → URL + Method → 权限匹配                                  │
  │                                                                  │
  │  ④ 跨域 CORS                                                     │
  │    → CorsWebFilter 配置                                           │
  │    → 允许的 Origin / Method / Header                              │
  │                                                                  │
  │  ⑤ 全链路追踪                                                     │
  │    → Sleuth + Zipkin / SkyWalking                                 │
  │    → Gateway 生成 Trace ID → 传递到下游                           │
  │    → Dubbo 传播 Trace ID → 跨服务追踪                             │
  │                                                                  │
  │  ⑥ 日志记录                                                       │
  │    → GlobalFilter 记录请求/响应日志                                │
  │    → ELK / Loki 收集                                              │
  │                                                                  │
  │  ⑦ 灰度发布                                                       │
  │    → 基于权重路由（Nacos weight 调整）                             │
  │    → 基于标签路由（Dubbo tag routing / Gateway Predicate）         │
  │    → 详见 7.6 节                                                  │
  └──────────────────────────────────────────────────────────────────┘
```

## 7.4 RPC 框架选型（Dubbo vs Spring Cloud）

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                  Dubbo vs Spring Cloud 选型决策                   │
  │                                                                  │
  │  选型维度：                                                        │
  │                                                                  │
  │  ① 通信协议                                                       │
  │    Dubbo → TCP + Hessian2（二进制长连接）→ 性能高                  │
  │    Spring Cloud → HTTP + JSON（REST）→ 通用性强                   │
  │                                                                  │
  │  ② 调用方式                                                       │
  │    Dubbo → 接口级调用（像调本地方法一样调远程）                     │
  │    OpenFeign → HTTP 接口级调用（声明式 HTTP 客户端）              │
  │    → 体验类似，但底层协议不同                                      │
  │                                                                  │
  │  ③ 性能                                                           │
  │    Dubbo → 单次调用延迟 < 1ms（二进制 + 长连接）                  │
  │    OpenFeign → 单次调用延迟 > 10ms（HTTP + JSON + 短连接）        │
  │    → 10倍差距在高频调用场景下很明显                                 │
  │                                                                  │
  │ ④ 服务治理                                                       │
  │    Dubbo → SPI 可扩展 + 内置集群容错 + 负载均衡 + 路由规则         │
  │    Spring Cloud → Ribbon + Sentinel + 各种 Starter                │
  │    → Dubbo 治理能力更强更细                                       │
  │                                                                  │
  │  ⑤ 跨语言                                                         │
  │    Dubbo → Triple 协议（HTTP/2 + Protobuf）→ 跨语言               │
  │    Spring Cloud → HTTP REST → 天然跨语言                          │
  │                                                                  │
  │  ⑥ 生态                                                           │
  │    Dubbo → Alibaba 生态（Nacos + Sentinel + Seata）               │
  │    Spring Cloud → Spring 生态（Netflix / Alibaba / Kubernetes）   │
  │                                                                  │
  │  ──────────────────────────────────────────────────────────      │
  │                                                                  │
  │  推荐方案：混合架构                                                │
  │                                                                  │
  │  ┌───────────────────────┐                                       │
  │  │     Gateway 层         │ ←── Spring Cloud Gateway (HTTP)      │
  │  │    (对外 HTTP 入口)     │                                       │
  │  └───────────┬───────────┘                                       │
  │              │                                                    │
  │     ┌────────┴────────┐                                          │
  │     │                  │                                          │
  │  ┌──▼──────────┐  ┌──▼──────────┐                                │
  │  │  服务 A      │  │  服务 B      │                                │
  │  │  (Dubbo RPC) │  │  (Dubbo RPC) │ ←── 内部高频调用用 Dubbo      │
  │  └─────────────┘  └─────────────┘                                │
  │                                                                  │
  │  ★ 内部服务间 → Dubbo（高性能）                                   │
  │  ★ 对外接口 → Gateway HTTP（通用性强）                            │
  │  ★ 注册中心 → Nacos（Dubbo + Spring Cloud 共用）                  │
  │  ★ 流控熔断 → Sentinel（Dubbo + Gateway 共用）                   │
  └──────────────────────────────────────────────────────────────────┘
```

## 7.5 数据库层设计（MyBatis + 分库分表）

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                  数据库层设计要点                                   │
  │                                                                  │
  │  ① 单库阶段（初期）                                               │
  │    MyBatis + 单 MySQL + 主从复制                                  │
  │    → 一主多从 → 读走从库、写走主库                                │
  │    → Spring + MyBatis 配置读写分离                                │
  │      ├── @Transactional(readOnly=true) → 路由到从库               │
  │      ├── @Transactional → 路由到主库                              │
  │      ├── DynamicDataSource + ThreadLocal 切换                    │
  │                                                                  │
  │  ② 分库分表阶段（规模增长）                                       │
  │    ShardingSphere / MyCat + MyBatis                              │
  │    → 水平分表：order_0 / order_1 / order_2 ...                   │
  │    → 水平分库：db_0 / db_1 / db_2 ...                            │
  │    → 分片键：user_id / order_id                                  │
  │                                                                  │
  │    MyBatis + ShardingSphere：                                     │
  │      → ShardingSphere 作为 DataSource 代理                       │
  │      → MyBatis 不感知分库分表                                     │
  │      → SQL → ShardingSphere 路由 → 多个真实 DataSource           │
  │                                                                  │
  │    ★ @Transactional 和分库分表的冲突：                             │
  │      → 跨库事务不能简单用 @Transactional                          │
  │      → 需要分布式事务（Seata AT）                                  │
  │      → 或最终一致（RocketMQ 事务消息）                             │
  │                                                                  │
  │  ③ 缓存层                                                        │
  │    Redis + Spring Cache                                           │
  │    → @Cacheable / @CachePut / @CacheEvict                        │
  │    → 替代 MyBatis L2 缓存（多实例共享）                           │
  │                                                                  │
  │    读写策略：                                                      │
  │      ├── Cache Aside：读缓存 → miss → 读 DB → 写缓存             │
  │      ├── Write Through：写缓存 → 缓存同步写 DB                   │
  │      ├── Write Behind：写缓存 → 缓存异步写 DB                     │
  │                                                                  │
  │    ★ 缓存一致性：                                                  │
  │      → 更新 DB + 删除缓存（推荐）                                 │
  │      → 不要更新缓存（并发问题）                                   │
  │      → 延迟双删（极端一致性要求）                                  │
  └──────────────────────────────────────────────────────────────────┘
```

## 7.6 全链路灰度发布方案

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                  全链路灰度发布                                    │
  │                                                                  │
  │  方案一：Gateway 权重路由                                         │
  │    → Nacos ServiceInstance 的 weight 属性                        │
  │    → 灰度版本 weight=10 / 正式版本 weight=90                      │
  │    → 10% 流量走灰度版本                                           │
  │                                                                  │
  │    实现方式：                                                      │
  │      ├── Nacos 控制台调整 weight → 实时生效                       │
  │      ├── Gateway ReactiveLoadBalancer 读取 weight                 │
  │      ├── 按 weight 比例选择实例                                    │
  │                                                                  │
  │  方案二：Dubbo Tag Routing                                        │
  │    → Provider 注册时打 tag（gray / stable）                       │
  │    → Consumer 调用时指定 tag → 只路由到对应 tag 的 Provider       │
  │                                                                  │
  │    实现方式：                                                      │
  │      ├── RpcContext.setAttachment("dubbo.tag", "gray")            │
  │      ├── TagRouter.match() → 只选择 tag=gray 的 Invoker          │
  │      ├── 如果没有 gray 实例 → fallback 到 stable 实例            │
  │                                                                  │
  │  方案三：全链路灰度（Gateway + Dubbo + MyBatis）                  │
  │    → Gateway 根据 Header/Cookie 判断灰度用户                      │
  │    → Gateway 传递灰度标记到下游服务                                │
  │    → 下游服务 Dubbo 调用时传递灰度 tag                            │
  │    → Dubbo Provider 根据 tag 路由到灰度实例                       │
  │    → 灰度实例连接灰度数据库                                       │
  │                                                                  │
  │    全链路标记传递：                                                │
  │      HTTP Header: X-Gray-Tag=gray                                │
  │      → Gateway → Ribbon → Service → Dubbo RpcContext            │
  │      → Dubbo tag routing → Provider gray instance                │
  │                                                                  │
  │    ┌──────────────────────────────────────────────────────┐      │
  │    │                  全链路灰度流程图                     │      │
  │    │                                                      │      │
  │    │  灰度用户（Header: X-Gray-Tag=gray）                 │      │
  │    │    │                                                  │      │
  │    │    ▼ Gateway                                          │      │
  │    │    │  识别灰度标记                                     │      │
  │    │    │  路由到灰度实例（Nacos weight）                    │      │
  │    │    │                                                  │      │
  │    │    ▼ 灰度 OrderService                                │      │
  │    │    │  Dubbo RPC + tag=gray                            │      │
  │    │    │                                                  │      │
  │    │    ▼ 灰度 UserService（Dubbo TagRouter）              │      │
  │    │    │  MyBatis → 灰度数据库                            │      │
  │    │    │                                                  │      │
  │    │  正式用户（无灰度标记）                                │      │
  │    │    │                                                  │      │
  │    │    ▼ Gateway → 正式 OrderService → 正式 UserService  │      │
  │    │    → MyBatis → 正式数据库                             │      │
  │    └──────────────────────────────────────────────────────┘      │
  └──────────────────────────────────────────────────────────────────┘
```

## 7.7 容灾与降级方案

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                  容灾与降级三层防护                                 │
  │                                                                  │
  │  第一层：Gateway 入口防护                                         │
  │    ├── Sentinel 全局流控（QPS 限流）                               │
  │    ├── Sentinel 系统保护（CPU / Load / RT）                       │
  │    ├── 熔断降级 → 返回默认响应                                    │
  │    ├── 黑名单 IP 过滤                                             │
  │    ├── WAF（Web Application Firewall）                            │
  │                                                                  │
  │  第二层：服务内部防护                                              │
  │    ├── @Transactional 超时回滚                                    │
  │    ├── @SentinelResource 方法级流控                                │
  │    ├── Dubbo 集群容错（Failover / Failsafe）                      │
  │    ├── Dubbo Mock 降级（return null / return default）            │
  │    ├── 服务隔离（线程池隔离 / 信号量隔离）                         │
  │                                                                  │
  │  第三层：基础设施防护                                              │
  │    ├── MySQL 主从切换 → 读写分离 → 故障自动切换                   │
  │    ├── Redis 集群 → 主从 + 哨兵 / Cluster                        │
  │    ├── Nacos 集群 → 多节点 + 本地缓存 failover                   │
  │    ├── MQ → RocketMQ 集群 → 主从同步                             │
  │                                                                  │
  │  ──────────────────────────────────────────────────────────      │
  │                                                                  │
  │  降级策略矩阵：                                                   │
  │                                                                  │
  │  │ 场景               │ 降级策略               │ 恢复策略        │ │
  │  │─────────────────────│─────────────────────────│────────────────│ │
  │  │ DB 压力大           │ 读请求走缓存           │ 缓存 miss 后恢复│ │
  │  │ 远程服务超时         │ Dubbo Failfast + Mock  │ 超时恢复后重试  │ │
  │  │ 流量突增            │ Sentinel 流控 + 排队   │ 流量回落后放开  │ │
  │  │ 服务完全宕机        │ 返回兜底数据           │ 服务重启后恢复  │ │
  │  │ 依赖链故障          │ 熔断 → HALF_OPEN 探测 │ 探测成功 → 闭环│ │
  │                                                                  │
  │  ──────────────────────────────────────────────────────────      │
  │                                                                  │
  │  容灾演练 Checklist：                                             │
  │    1. 拔掉注册中心 → 服务是否依赖本地缓存继续运行？                 │
  │    2. 拔掉 DB → 是否有缓存兜底？                                  │
  │    3. 拔掉 Redis → 是否降级到本地缓存？                           │
  │    4. 拔掉 MQ → 是否有本地暂存方案？                              │
  │    5. 某服务宕机 → Dubbo Failover 是否自动切换？                  │
  │    6. 流量翻倍 → Sentinel 流控是否生效？                          │
  │    7. 网关宕机 → 是否有备用网关？                                  │
  │    8. 配置中心不可用 → 本地 failover 文件是否可用？               │
  └──────────────────────────────────────────────────────────────────┘
```

---

# 附录 A Spring 全家桶核心类速查表

## A.1 IoC/DI 核心类

| 类名 | 包 | 作用 |
|------|----|------|
| `DefaultListableBeanFactory` | spring-beans | Bean 容器核心实现 |
| `AbstractApplicationContext` | spring-context | 应用上下文骨架（refresh 12步） |
| `AnnotationConfigApplicationContext` | spring-context | 注解配置启动入口 |
| `BeanDefinitionBuilder` | spring-beans | BeanDefinition 构建器 |
| `AutowiredAnnotationBeanPostProcessor` | spring-beans | @Autowired/@Value 注入处理器 |
| `CommonAnnotationBeanPostProcessor` | spring-context | @Resource/@PostConstruct 处理器 |
| `DefaultSingletonBeanRegistry` | spring-beans | 三级缓存管理 |
| `SimpleAutowireCandidateResolver` | spring-beans | 依赖候选解析器 |

## A.2 AOP/代理 核心类

| 类名 | 包 | 作用 |
|------|----|------|
| `AbstractAutoProxyCreator` | spring-aop | BeanPostProcessor 创建代理 |
| `AnnotationAwareAspectJAutoProxyCreator` | spring-aop | @Aspect 代理创建器 |
| `ReflectiveMethodInvocation` | spring-aop | Advice Chain 递归执行 |
| `TransactionInterceptor` | spring-tx | @Transactional 代理拦截器 |
| `JdkDynamicAopProxy` | spring-aop | JDK Proxy AOP 实现 |
| `CglibAopProxy.DynamicAdvisedInterceptor` | spring-aop | CGLIB AOP 实现 |
| `ReflectiveAspectJAdvisorFactory` | spring-aop | @Aspect → Advisor 转换器 |
| `DefaultAopProxyFactory` | spring-aop | 代理选择策略（JDK vs CGLIB） |

## A.3 事务 核心类

| 类名 | 包 | 作用 |
|------|----|------|
| `DataSourceTransactionManager` | spring-jdbc | JDBC 事务管理器 |
| `TransactionSynchronizationManager` | spring-tx | ThreadLocal 绑定 Connection |
| `SpringManagedTransaction` | mybatis-spring | 从 ThreadLocal 获取 Connection |
| `TransactionInterceptor` | spring-tx | @Transactional 代理拦截器 |
| `TransactionalCacheManager` | mybatis | L2 缓存暂存区管理器 |

## A.4 Nacos 核心类

| 类名 | 包 | 作用 |
|------|----|------|
| `NacosNamingService` | nacos-client | 服务注册/发现/心跳 |
| `NacosConfigService` | nacos-client | 配置获取/监听/长轮询 |
| `NacosServiceRegistry` | spring-cloud-alibaba | Spring Cloud 注册适配 |
| `NacosServiceInstance` | spring-cloud-alibaba | 服务实例信息封装 |
| `NacosConfigListener` | nacos-client | 配置变更监听器 |

## A.5 Sentinel 核心类

| 类名 | 包 | 作用 |
|------|----|------|
| `SentinelResourceAspect` | sentinel-annotation | @SentinelResource 切面 |
| `SlotChainBuilder` | sentinel-core | Slot Chain 构建器 |
| `LeapArray` | sentinel-core | 滑动窗口统计核心 |
| `FlowSlot` | sentinel-core | 流控规则检查 |
| `DegradeSlot` | sentinel-core | 熔断规则检查 |
| `StatisticSlot` | sentinel-core | 数据统计收集 |
| `SentinelGatewayFilter` | sentinel-gateway | Gateway 集成过滤器 |

## A.6 Gateway 核心类

| 类名 | 包 | 作用 |
|------|----|------|
| `RoutePredicateHandlerMapping` | spring-cloud-gateway | 路由匹配 |
| `DefaultGatewayFilterChain` | spring-cloud-gateway | Filter Chain 执行 |
| `ReactiveLoadBalancerClientFilter` | spring-cloud-gateway | 负载均衡路由 |
| `NettyRoutingFilter` | spring-cloud-gateway | HTTP 路由转发 |
| `RouteDefinition` | spring-cloud-gateway | 路由定义 |

## A.7 Dubbo 核心类

| 类名 | 包 | 作用 |
|------|----|------|
| `ExtensionLoader` | dubbo-common | SPI 扩展加载器 |
| `ServiceBean` | dubbo-config-spring | @DubboService Spring 集成 |
| `ReferenceBean` | dubbo-config-spring | @DubboReference Spring 集成 |
| `DubboProtocol` | dubbo-rpc-dubbo | Dubbo 协议实现 |
| `HeaderExchangeClient` | dubbo-remoting | 请求-响应语义 |
| `DefaultFuture` | dubbo-remoting | 基于 Request ID 的异步匹配 |
| `FailoverClusterInvoker` | dubbo-cluster | 失败重试策略 |
| `RandomLoadBalance` | dubbo-cluster | 加权随机负载均衡 |
| `ProtocolFilterWrapper` | dubbo-rpc | Filter Chain 构建器 |
| `RegistryProtocol` | dubbo-registry | 注册中心协议 |

## A.8 MyBatis 核心类

| 类名 | 包 | 作用 |
|------|----|------|
| `MapperProxy` | mybatis | @Mapper JDK Proxy 代理 |
| `MapperMethod` | mybatis | SQL 方法映射 |
| `SqlSessionTemplate` | mybatis-spring | 线程安全 SqlSession |
| `CachingExecutor` | mybatis | 二级缓存装饰器 |
| `SimpleExecutor` | mybatis | 基础执行器 |
| `RoutingStatementHandler` | mybatis | Statement 路由器 |
| `DefaultResultSetHandler` | mybatis | 结果集映射 |
| `MapperFactoryBean` | mybatis-spring | Mapper 接口 FactoryBean |
| `DynamicSqlSource` | mybatis | 动态 SQL 解析 |

---

# 附录 B 13 份源码文档索引与衔接关系图

## B.1 文档索引

| # | 文档名 | 核心主题 | 行数 |
|---|--------|---------|------|
| 1 | HashMap源码深度解析.md | 数组+链表+红黑树、resize高低位拆分 | ~1000 |
| 2 | ConcurrentHashMap源码深度解析.md | CAS+synchronized、transfer多线程扩容 | ~1500 |
| 3 | ThreadPoolExecutor源码深度解析.md | ctl状态控制、Worker不可重入锁 | ~1600 |
| 4 | synchronized_AQS_ReentrantLock源码深度解析.md | Mark Word锁升级、CLH队列、公平/非公平锁 | 1251 |
| 5 | volatile_JMM_单例模式源码深度解析.md | happens-before、内存屏障、6种单例 | ~1500 |
| 6 | Java基础源码深度解析_String_equals_泛型_反射_异常.md | 不可变性、契约、擦除、Inflation | ~2000 |
| 7 | Java8新特性源码深度解析_Stream_Optional_CompletableFuture.md | 流水线、Treiber Stack | ~1800 |
| 8 | Java与Tomcat类加载机制源码深度解析.md | 双亲委派、SPI、WebAppClassLoader | ~1500 |
| 9 | Spring_IoC_DI源码深度解析.md | refresh 12步、Bean生命周期、循环依赖 | ~3500 |
| 10 | Spring_AOP源码深度解析_JDKProxy_CGLIB_Transactional.md | 代理创建、Advice链、@Transactional | 4600 |
| 11 | Spring_Cloud_MyBatis源码深度解析_Nacos_Sentinel_Gateway_MyBatis.md | Nacos+Sentinel+Gateway+MyBatis | 4984 |
| 12 | Dubbo源码深度解析_SPI_服务治理_协议_SpringCloud对比.md | SPI+Export/Refer+协议+对比 | 6296 |
| 13 | 并发同步工具源码深度解析_Future_CompletableFuture_CountDownLatch_CyclicBarrier_Semaphore.md | Future+CompletableFuture+并发工具 | ~2000 |
| **14** | **Spring全家桶综合串讲_从IoC到微服务全链路.md** | **综合串讲** | **本文档** |

## B.2 衔接关系图

```
                    ┌──────────────────────┐
                    │  Java 基础层（底层）   │
                    │                      │
                    │  #1 HashMap          │
                    │  #2 ConcurrentHashMap│ ←── Spring IoC 内部用了 ConcurrentHashMap
                    │  #3 ThreadPool      │ ←── Dubbo ThreadPool 是 Spring 线程池的扩展
                    │  #4 synchronized/AQS│ ←── Spring @Transactional 底层用 synchronized
                    │  #5 volatile/JMM    │ ←── 三级缓存 double-check 用了 volatile
                    │  #6 Java基础         │ ←── 所有框架的底层（反射、泛型、异常）
                    │  #7 Java8新特性      │ ←── Dubbo 3.x 异步用了 CompletableFuture
                    │  #8 类加载           │ ←── Spring IoC Bean 加载的基础
                    │  #13 并发同步工具     │ ←── CompletableFuture + 线程同步
                    └──────────────┬───────┘
                                   │
                                   │  基础 → 应用
                                   │
                    ┌──────────────▼───────┐
                    │  Spring 框架层（核心） │
                    │                      │
                    │  #9 IoC/DI           │ ←── 一切的底座
                    │  #10 AOP/代理        │ ←── IoC → AOP → @Transactional
                    │                      │
                    │  IoC 创建 Bean       │
                    │  AOP 在 Bean 初始化后│
                    │    创建代理          │
                    │  @Transactional      │
                    │    代理控制事务       │
                    └──────────────┬───────┘
                                   │
                                   │  单体 → 微服务
                                   │
                    ┌──────────────▼───────┐
                    │  微服务层（分布式）    │
                    │                      │
                    │  #11 Spring Cloud    │
                    │    ├── Nacos 注册    │ ←── 和 Dubbo 共用注册中心
                    │    ├── Sentinel 流控 │ ←── 和 Dubbo 共用流控
                    │    ├── Gateway 网关  │ ←── 入口流量控制
                    │    └── MyBatis ORM   │ ←── 和 @Transactional 串联
                    │                      │
                    │  #12 Dubbo           │
                    │    ├── SPI 机制       │ ←── 和 Spring FactoryBean 类似但更强
                    │    ├── 服务治理       │ ←── 和 Nacos 互补
                    │    ├── 协议通信       │ ←── 和 Gateway HTTP 互补
                    │    └── 与SC对比       │ ←── 选型依据
                    └──────────────┬───────┘
                                   │
                                   │  串讲整合
                                   │
                    ┌──────────────▼───────┐
                    │  综合串讲（全局视角） │
                    │                      │
                    │  #14 本文档           │
                    │                      │
                    │  串联所有机制：        │
                    │  Bean → 代理 → 事务   │
                    │  → 缓存 → RPC → 流控 │
                    │  → 网关 → 全链路      │
                    └──────────────────────┘
```

## B.3 推荐阅读顺序

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                  推荐阅读路线（三条线）                             │
  │                                                                  │
  │  线路A：Java 基础 → Spring 核心 → 微服务（渐进式）               │
  │                                                                  │
  │    #1 HashMap → #2 ConcurrentHashMap → #5 volatile/JMM          │
  │    → #9 IoC/DI → #10 AOP → #11 Spring Cloud + MyBatis          │
  │    → #12 Dubbo → #14 综合串讲                                    │
  │                                                                  │
  │    ★ 适合：从零开始系统学习                                       │
  │                                                                  │
  │  线路B：面试突击（高频优先）                                     │
  │                                                                  │
  │    #9 IoC/DI → #10 AOP → #4 synchronized/AQS                   │
  │    → #5 volatile → #11 Spring Cloud → #12 Dubbo                 │
  │    → #14 综合串讲（面试50题）                                     │
  │                                                                  │
  │    ★ 适合：面试前快速突击                                         │
  │                                                                  │
  │  线路C：源码深度（硬核路线）                                      │
  │                                                                  │
  │    #8 类加载 → #9 IoC/DI → #10 AOP → #13 并发工具               │
  │    → #3 ThreadPool → #4 AQS → #7 Java8新特性                    │
  │    → #12 Dubbo SPI → #11 Spring Cloud → #14 综合串讲            │
  │                                                                  │
  │    ★ 适合：深入源码，理解底层机制                                 │
  │                                                                  │
  │  ──────────────────────────────────────────────────────────      │
  │                                                                  │
  │  ★ 无论哪条路线，最终都要读到 #14 综合串讲                        │
  │  ★ 综合串讲把所有零散知识点串成一条线                              │
  │  ★ 面试时用"一条线"回答比零散知识点更有说服力                      │
  └──────────────────────────────────────────────────────────────────┘
```

---

> **全文完**  
> 这份文档是 13 份源码解析的"终章"——不是补充，而是串联。  
> 它回答的不是"某个框架的源码怎么实现的"，而是"所有框架的源码如何协作"。  
> 建议配合之前的 13 份文档一起阅读，这份串讲提供全局视角，其他文档提供细节深度。