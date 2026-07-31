# 面试模拟 - Day 60

> 日期：2026-07-30（周四） | 模拟岗位：邮储银行软件研发中心（杭州）- 后端开发工程师
> 建议时长：100分钟（一面70分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day60，"查漏补缺"阶段第八周。模拟邮储银行软件研发中心杭州分中心——中国邮政储蓄银行是六大国有行之一，网点最多（近4万个），下沉到县乡，普惠金融是其核心战略。邮储面试特点：偏稳重型、重基础功底、关注银行核心系统设计能力、追问深而不偏。今天引入 **Spring Boot 启动流程、Kafka 消费者 Rebalance 深入、WebSocket 原理、Java 泛型深入、MySQL Online DDL、分布式限流、JVM 字节码基础** 7个全新技术话题 + 普惠金融与个人养老金业务 + 合并区间手写代码——覆盖之前碎片提到但没有作为独立话题系统考过的高频核心考点。每话题3-4个追问，模拟真实面试连环深挖。

---

# 一面（70分钟）

## 话题一：Spring Boot 启动流程（10分钟）

**面试官：你们项目用的是 Spring Boot 吧？SpringApplication.run() 启动的时候，内部到底做了哪些事？**

> 你回答...

**追问1：** 先说说 SpringApplication 的构造阶段做了什么。new SpringApplication() 里面发生了哪些事？

> 你回答...（提示：SpringApplication 构造阶段 / `new SpringApplication(primarySources)` 做了什么：①推断应用类型 → `WebApplicationType.deduceFromClasspath()` → 检查 classpath 有没有 `DispatcherServlet`（SERVLET）/ `WebFlux`（REACTIVE）/ 都没有（NONE）→ 决定创建什么类型的 ApplicationContext ②加载 ApplicationContextInitializer → 从 `META-INF/spring.factories` 中读取 `ApplicationContextInitializer` 的实现类 → 用于在 refresh 之前对 ApplicationContext 做初始化（如注册一些 Bean）③加载 ApplicationListener → 同样从 spring.factories 读取 → 监听启动过程中的事件（如 ApplicationStartingEvent / ApplicationEnvironmentPreparedEvent / ApplicationReadyEvent）④推断主类 → `deduceMainApplicationClass()` → 通过 `RuntimeException().getStackTrace()` 拿到调用栈 → 找到 main 方法所在的类 → 设置为 mainApplicationClass / 核心设计思想：构造阶段只做"推断和加载"→ 不创建任何对象 → 真正的初始化在 run() 方法里 → 类似"准备阶段"→ 分离关注点 / 面试重点：构造阶段=①推断应用类型(检查classpath有DispatcherServlet→SERVLET)②从spring.factories加载Initializer和Listener③推断主类(通过调用栈找main方法所在类) → 只推断不创建→真正初始化在run())

**追问2：** run() 方法的核心流程是什么？从开始到 Tomcat 启动，经过了哪些关键步骤？

> 你回答...（提示：run() 方法核心流程 / 完整流程（12步）：
```
SpringApplication.run()
  ① 创建 StopWatch → 计时开始
  ② 获取 SpringApplicationRunListeners → 发布 ApplicationStartingEvent
     → Spring Boot 2.4+ 用 EventPublishingRunListener 包装 → 发布到前面加载的 ApplicationListener
  ③ 准备 Environment → 加载 application.yml/properties + 命令行参数
     → 发布 ApplicationEnvironmentPreparedEvent
     → 此时 ConfigFileApplicationListener 加载配置文件
  ④ 打印 Banner → SpringApplicationBannerPrinter → 控制台打印 Spring Boot logo
  ⑤ 创建 ApplicationContext → 根据 WebApplicationType：
     SERVLET → AnnotationConfigServletWebServerApplicationContext
     REACTIVE → AnnotationConfigReactiveWebServerApplicationContext
     NONE → AnnotationConfigApplicationContext
  ⑥ prepareContext() → 准备上下文
     → 设置 Environment → 调用 ApplicationContextInitializer（构造阶段加载的）
     → 注册 BeanDefinition（主配置类）→ 发布 ApplicationContextPreparedEvent
  ⑦ refreshContext() → 核心！调用 ApplicationContext.refresh()
     → invokeBeanFactoryPostProcessors → 处理 @Configuration + 自动配置
     → @EnableAutoConfiguration → 加载 spring.factories 中 AutoConfiguration 类
     → @Conditional 条件判断 → 决定哪些自动配置类生效
     → registerBeanPostProcessors → 注册 BeanPostProcessor
     → 实例化所有非 lazy 的单例 Bean（IoC 容器初始化）
     → onRefresh() → 创建内嵌 Tomcat（createWebServer）
     → finishBeanFactoryInitialization → 完成所有单例 Bean 创建
  ⑧ afterRefresh() → 注册 ShutdownHook（JVM 关闭时回调 destroy）
  ⑨ 发布 ApplicationStartedEvent → 所有 Bean 创完了但还没 Ready
  ⑩ 调用 ApplicationRunner / CommandLineRunner → 自定义启动后逻辑
  ⑪ 发布 ApplicationReadyEvent → 启动完成
  ⑫ StopWatch.stop() → 打印启动耗时
```
/ 自动配置发生在 refreshContext 的 invokeBeanFactoryPostProcessors 阶段 → `AutoConfigurationImportSelector` → 读取 `META-INF/spring.factories`（2.7-）或 `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`（2.7+）→ 加载所有自动配置类 → `@Conditional` 决定是否生效 → 内嵌 Tomcat 在 onRefresh 阶段创建 → 所有单例 Bean 在 finishBeanFactoryInitialization 完成 / 面试重点：run()=①StopWatch计时②RunListeners发布StartingEvent③准备Environment(加载yml+命令行)④Banner⑤创建ApplicationContext(按类型)⑥prepareContext(设Environment+Initializer+注册主类)⑦refreshContext(核心→自动配置+创建Bean+启动Tomcat)⑧afterRefresh(ShutdownHook)⑨StartedEvent⑩ApplicationRunner/CommandLineRunner⑪ReadyEvent⑫计时结束 → 自动配置在refresh的invokeBeanFactoryPostProcessors→AutoConfigurationImportSelector读spring.factories→@Conditional判断→Tomcat在onRefresh创建→单例Bean在finishBeanFactoryInitialization完成）

**追问3：** @EnableAutoConfiguration 是怎么生效的？自动配置类是怎么加载和筛选的？

> 你回答...（提示：自动配置机制 / 完整链路：①`@SpringBootApplication` = `@SpringBootConfiguration` + `@EnableAutoConfiguration` + `@ComponentScan` ②`@EnableAutoConfiguration` → `@Import(AutoConfigurationImportSelector.class)` → 导入选择器 ③`AutoConfigurationImportSelector.selectImports()` → 调用 `getCandidateConfigurations()` → 读取 `META-INF/spring.factories`（Spring Boot 2.6及以前）或 `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`（2.7+）④拿到所有自动配置类全类名（如 `RedisAutoConfiguration` / `DataSourceAutoConfiguration` / `WebMvcAutoConfiguration` 等，Spring Boot 2.x 有 130+ 个）⑤去重 → 排除（`@SpringBootApplication(exclude=...)` 手动排除）→ 过滤（`@Conditional` 条件判断）/ @Conditional 条件注解：①`@ConditionalOnClass` → classpath 有没有这个类 → 如 `RedisAutoConfiguration` 上有 `@ConditionalOnClass({RedisOperations.class})` → 没有 Redis 依赖就不加载 ②`@ConditionalOnMissingBean` → 容器中没有这个 Bean 才自动配置 → 用户自定义的优先 → 这就是为什么你定义了 `RedisTemplate` 后 Spring Boot 的默认就不生效 ③`@ConditionalOnProperty` → 配置文件有某个属性才生效 → 如 `spring.cache.type=redis` 才加载缓存配置 ④`@ConditionalOnWebApplication` → 是不是 Web 应用 / 自动配置类举例——RedisAutoConfiguration：①`@ConditionalOnClass({RedisOperations.class})` → classpath 有 Redis ②`@Import({RedisConfiguration.class})` → 导入 Redis 配置 ③`RedisConfiguration` → `@Bean RedisTemplate` → `@ConditionalOnMissingBean` → 用户没定义才创建默认的 ④默认 RedisTemplate 用 JDK 序列化 → 序列化乱码 → 所以你总是要自定义 RedisTemplate 配置 Jackson 序列化 → 这就是"自动配置的默认值不满足需求时覆盖" / 面试重点：@EnableAutoConfiguration→@Import(AutoConfigurationImportSelector)→读spring.factories/imports文件→拿到130+配置类→@ConditionalOnClass(有依赖才加载)/@ConditionalOnMissingBean(用户优先)/@ConditionalOnProperty(配置开关)/@ConditionalOnWebApplication → 用户自定义Bean覆盖默认→这就是为什么RedisTemplate总是要自定义序列化）

**追问4：** Spring Boot 2.7 和 3.0 的自动配置加载方式有什么变化？为什么要改？

> 你回答...（提示：spring.factories vs imports 文件 / Spring Boot 2.6 及以前：①自动配置类写在 `META-INF/spring.factories` 文件中 ②格式 → `org.springframework.boot.autoconfigure.EnableAutoConfiguration=\
    com.xxx.AutoConfig1,\
    com.xxx.AutoConfig2` ③问题 → spring.factories 被滥用 → 除了 AutoConfiguration，还有 ApplicationContextInitializer / EnvironmentPostProcessor / EnableAutoConfiguration 等多种类型都写在同一个文件 → 一个文件存了所有扩展点 → 启动时全部读取 → 即使大部分不需要 → 浪费 / Spring Boot 2.7+：①AutoConfiguration 改为独立的文件 `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` ②每行一个全类名 → 不需要 key → 简化 ③其他扩展点（Initializer/Listener）仍在 spring.factories → 分离关注点 ④好处 → 启动时只读 imports 文件加载 AutoConfiguration → spring.factories 只加载需要的扩展点 → 减少不必要的类加载 ⑤Spring Boot 3.0 完全移除 spring.factories 中的 AutoConfiguration 支持 → 必须用 imports 文件 / 面试重点：2.6-用spring.factories(所有扩展点混在一起→启动全读浪费)→2.7+改用独立的imports文件(每行一个类名→简化→只读需要的)→3.0完全移除spring.factories的AutoConfiguration支持 → 原因=spring.factories被滥用+所有类型混在一个文件+启动时全部读取浪费 → 改进=AutoConfiguration独立文件+其他扩展点留在spring.factories+按需加载）

---

## 话题二：Kafka 消费者 Rebalance 深入（10分钟）

**面试官：你提到过 Kafka 消费者组的 Rebalance。Rebalance 到底是什么？什么时候触发？为什么说它是 Kafka 的痛点？**

> 你回答...

**追问1：** 先说说 Rebalance 是什么。消费者组和分区是什么关系？为什么需要 Rebalance？

> 你回答...（提示：Rebalance 基本概念 / 消费者组与分区关系：①一个 Topic 有 N 个分区 → 一个消费者组有 M 个消费者 → 每个分区只能被组内一个消费者消费 → 所以最多 min(N, M) 个消费者同时消费 ②如 Topic 有 6 个分区 → 消费者组有 3 个消费者 → 每个消费者消费 2 个分区 ③如果消费者组有 8 个消费者 → 6 个消费 + 2 个空闲（分区不够分）/ Rebalance 是什么：①Rebalance = 重新分配分区和消费者的映射关系 ②当消费者组成员变化（加入/退出/崩溃）→ 或分区数变化（增加分区）→ 或订阅的 Topic 变化 → 触发 Rebalance → 重新分配分区 / Rebalance 的必要性：①消费者崩溃 → 它消费的分区没人消费了 → 需要重新分配给其他消费者 ②消费者加入 → 新消费者需要分担负载 → 重新分配 ③消费者退出 → 和崩溃类似 → 重新分配 / 面试重点：分区和消费者组关系=一个分区只被组内一个消费者消费→最多min(分区数,消费者数)个并发 → Rebalance=消费者组成员变化/分区数变化/Topic变化时重新分配分区 → 必要性=消费者崩溃/加入/退出→分区没人消费或需要重新分担）

**追问2：** Rebalance 的触发条件有哪些？具体说说每种情况。

> 你回答...（提示：Rebalance 触发条件 / 四类触发条件：①消费者组成员变化 → 加入：新消费者启动加入组 → 退出：消费者优雅关闭（调用 `consumer.close()` → 发送 LeaveGroup 请求 → Coordinator 触发 Rebalance）→ 崩溃：消费者未在 `session.timeout.ms`（默认 10s/45s）内发送心跳 → Coordinator 认为它崩溃 → 触发 Rebalance ②分区数变化 → Topic 分区数增加 → 触发 Rebalance → 新分区需要分配 ③订阅的 Topic 变化 → 用正则订阅 `subscribe(Pattern.compile("test.*"))` → 新建了匹配的 Topic → 触发 Rebalance ④消费者组订阅的 Topic 元数据变化 → 如 Topic 被删除 / 心跳机制：①消费者 → 定期向 GroupCoordinator 发送心跳 → `heartbeat.interval.ms`（默认 3s）→ 证明自己还活着 ②`session.timeout.ms`（默认 10s in Kafka 2.x / 45s in Kafka 3.x）→ 超过这个时间没收到心跳 → 认为崩溃 ③`max.poll.interval.ms`（默认 300s/5min）→ 两次 `poll()` 之间最大间隔 → 如果处理消息太慢超过这个时间 → 也触发 Rebalance → 因为消费者"看起来卡死了" ④坑 → `max.poll.interval.ms` 太短 → 消息处理慢 → 频繁 Rebalance → 恶性循环：Rebalance → 重新分配 → 又处理慢 → 又 Rebalance / 面试重点：触发条件=①成员变化(加入/退出/崩溃→session.timeout没心跳)②分区数变化③Topic变化(正则订阅匹配新Topic)④max.poll.interval.ms超时(poll间隔太长→认为卡死→触发) → 心跳=heartbeat.interval.ms(3s)+session.timeout.ms(10/45s没心跳崩)+max.poll.interval.ms(300s poll间隔超时) → 坑=max.poll.interval太短→处理慢→频繁Rebalance→恶性循环）

**追问3：** 为什么说 Rebalance 是 Kafka 的痛点？Rebalance 过程中发生了什么？对业务有什么影响？

> 你回答...（提示：Rebalance 的痛点——Stop-The-World / Rebalance 过程：①触发 → Coordinator（某个 Broker 被选为消费者组的协调器）检测到需要 Rebalance → 在心跳响应中返回 `REBALANCE_IN_PROGRESS` ②消费者收到 → 发送 `JoinGroup` 请求 → Coordinator 选一个消费者作为 Leader → Leader 收到所有成员信息 ③Leader 执行分区分配策略 → `Assignor.assign()` → 计算分配方案 → 返回给 Coordinator ④Coordinator 发送分配方案给所有消费者 → 消费者发送 `SyncGroup` → 确认分配 ⑤消费者开始消费新分配的分区 / 痛点——Stop-The-World：①Rebalance 期间 → 所有消费者停止消费 → 等待分配完成 → 类似 JVM 的 STW ②Rebalance 耗时 → 通常几秒到几十秒 → 大消费者组（100+ 消费者）→ 可能几分钟 ③期间所有消息堆积 → 消费暂停 → 消息延迟飙升 ④如果频繁 Rebalance → 不断 STW → 消费一直跟不上 → 消息积压 / 痛点——重复消费：①Rebalance 前正在处理的消息 → 还没提交 offset → Rebalance 后新消费者从上次 commit 的 offset 开始消费 → 重复消费 ②如 → 消费者处理了消息 1-100 → 还没 commit → Rebalance → 新消费者从 commit 的 offset 0 开始 → 重新消费 1-100 ③必须幂等 → 否则重复处理 / 痛点——Rebalance 风暴：①消费者崩溃 → Rebalance → 分配更多分区给其他消费者 → 处理更慢 → max.poll.interval 超时 → 更多消费者"看起来卡死"→ 又触发 Rebalance → 恶性循环 ②大消费者组 → 一个消费者崩溃 → 全组 Rebalance → 所有消费者暂停 → 恢复后又崩 → 又 Rebalance / 面试重点：Rebalance过程=①Coordinator返回REBALANCE_IN_PROGRESS②消费者JoinGroup→选Leader③Leader分配分区④SyncGroup确认⑤开始消费 → 痛点=STW(所有消费者停止消费→几秒到几分钟→消息堆积)+重复消费(处理了没commit→Rebalance后重新消费→必须幂等)+Rebalance风暴(崩溃→分配更多→处理慢→超时→又Rebalance→恶性循环)）

**追问4：** Cooperative Rebalance（Kafka 2.4+）解决了什么问题？和 Eager Rebalance 有什么区别？

> 你回答...（提示：Eager vs Cooperative Rebalance / Eager Rebalance（默认，Kafka 2.3 及以前）：①Rebalance 时 → 所有消费者 → 撤销全部分区 → 等待重新分配 → 再消费 ②问题 → 即使某个消费者的分区不变 → 也要先撤销再重新分配 → 全部停止 → STW ③类比 → "推倒重建"→ 不管你要不要变 → 全部重来 / Cooperative Rebalance（Kafka 2.4+，Sticky Assignor）：①增量式 Rebalance → 只撤销需要变更的分区 → 其他分区继续消费 ②流程 → 第一轮 → Coordinator 告诉消费者"需要变更的分区"→ 消费者只撤销变更的分区 → 其他继续消费 → 第二轮 → 分配新分区 → 消费者开始消费新分区 ③类比 → "精装修"→ 只改需要改的房间 → 其他房间正常住 ④结果 → 大部分消费者不暂停 → 只有一小部分受影响 → STW 大幅缩小 / Sticky Assignor（粘性分配）：①Rebalance 时尽量保持原有分配 → 只移动必要的分区 ②好处 → 消费者大部分分区不变 → 减少重复消费 ③配合 Cooperative → 增量 Rebalance + 粘性分配 → 最小化影响 / 使用方式：
```properties
# Kafka 消费者配置
partition.assignment.strategy=
  org.apache.kafka.clients.consumer.CooperativeStickyAssignor
# 2.4+ 默认 RangeAssignor（Eager），需要手动切换
```
/ Eager vs Cooperative 对比：
| 维度 | Eager | Cooperative |
|------|-------|-------------|
| 撤销分区 | 全部撤销 | 只撤销变更的 |
| 消费暂停 | 所有消费者 | 只受影响的消费者 |
| STW 时间 | 长（全组） | 短（增量） |
| 重复消费 | 多 | 少（粘性保持） |
/ 面试重点：Eager=全部撤销分区→全部停止→推倒重建→全组STW → Cooperative(2.4+)=增量Rebalance→只撤销变更的分区→其他继续消费→精装修→STW大幅缩小 → StickyAssignor=尽量保持原有分配→只移必要分区→减少重复消费 → 生产建议=切换CooperativeStickyAssignor→大消费者组效果明显）

---

## 话题三：WebSocket 原理（9分钟）

**面试官：你们系统有实时推送的需求吗？用的什么方案？WebSocket 了解吗？和 HTTP 有什么区别？**

> 你回答...

**追问1：** 先说说 HTTP 做实时推送有什么问题。为什么需要 WebSocket？

> 你回答...（提示：HTTP 推送的局限 / HTTP 的请求-响应模型：①HTTP 是请求-响应模型 → 客户端请求 → 服务端响应 → 连接关闭 ②服务端不能主动推送 → 必须客户端先请求 ③要实现"实时"→ 轮询 / 长轮询 / SSE / 轮询（Polling）：①客户端定时发请求 → 如每 5 秒查一次 → 服务端有新数据就返回 ②问题 → 实时性差（最大 5 秒延迟）→ 大部分请求无数据 → 浪费带宽和服务器资源 → 高并发下服务器扛不住 / 长轮询（Long Polling）：①客户端发请求 → 服务端 hold 住不返回 → 有数据了才返回 → 客户端收到后立即发下一个请求 ②比轮询好 → 实时性高 → 但每次请求都要建立 HTTP 连接 → 开销大 → 且每个客户端占一个服务端线程 ③WebSocket 之前的主流方案 → 如微信网页版早期 / SSE（Server-Sent Events）：①服务端推 → 客户端只接收 → 单向 ②基于 HTTP → `Content-Type: text/event-stream` → 服务端持续推送数据 ③问题 → 只能服务端→客户端 → 客户端不能发消息 → 不适合双向通信 ④浏览器支持好 → 简单 / WebSocket 的优势：①全双工 → 客户端和服务端都可以随时发消息 → 双向实时通信 ②持久连接 → 一次握手 → 后续通信不用重新建连 → 开销小 ③协议轻量 → WebSocket 帧头 2-14 字节 → HTTP 头部几百字节 → 省带宽 ④不用轮询 → 服务端有数据直接推 → 实时性高 → 不浪费请求 / 面试重点：HTTP局限=请求-响应模型→服务端不能主动推送 → 轮询(实时性差+浪费资源)/长轮询(实时但开销大)/SSE(单向只能服务端推) → WebSocket=全双工双向+持久连接+帧头2-14字节省带宽+服务端主动推不轮询）

**追问2：** WebSocket 的握手过程是怎样的？它是怎么从 HTTP 升级到 WebSocket 的？

> 你回答...（提示：WebSocket 握手 / 握手过程（HTTP Upgrade）：①客户端发 HTTP GET 请求 → 带 Upgrade 头：
```
GET /ws/chat HTTP/1.1
Host: server.example.com
Upgrade: websocket          ← 请求升级协议
Connection: Upgrade           ← 表示这是升级请求
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==  ← 客户端生成的随机 Base64
Sec-WebSocket-Version: 13     ← WebSocket 版本
```
②服务端返回 101 Switching Protocols → 同意升级：
```
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=  ← 服务端用 Key 算出的
```
③Sec-WebSocket-Accept 计算 → 服务端拿 `Sec-WebSocket-Key` + 固定 GUID（`258EAFA5-E914-47DA-95CA-C5AB0DC85B11`）→ SHA-1 → Base64 → 返回 → 客户端验证 → 确认服务端理解 WebSocket ④握手成功后 → TCP 连接不关闭 → 后续不再用 HTTP 协议 → 改用 WebSocket 帧格式通信 / WebSocket 帧格式：①FIN（1 bit）→ 是否最后一帧 ②opcode（4 bits）→ 0x1 文本帧 / 0x2 二进制帧 / 0x8 关闭 / 0x9 Ping / 0xA Pong ③Mask（1 bit）→ 客户端→服务端必须掩码 / 服务端→客户端不掩码 ④Payload Length（7/16/64 bits）→ 负载长度 ⑤Masking Key（32 bits）→ 掩码密钥 ⑥Payload Data → 实际数据 / 帧头只有 2-14 字节 → 比 HTTP 头部（几百字节）小很多 → 高频通信省带宽 / 面试重点：握手=HTTP GET+Upgrade:websocket+Sec-WebSocket-Key → 服务端101 Switching+Sec-WebSocket-Accept(Key+GUID→SHA1→Base64) → 成功后TCP不关→改用WebSocket帧通信 → 帧=FIN+opcode(文本/二进制/关闭/Ping/Pong)+Mask(客户端必须掩码)+Payload+数据 → 帧头2-14字节比HTTP省带宽）

**追问3：** WebSocket 的心跳保活怎么做？如果客户端网络断了但 TCP 没感知到怎么办？

> 你回答...（提示：WebSocket 心跳与断线检测 / 问题——假死连接：①客户端网络断开（WiFi 切换 / 进入电梯 / 网线拔了）→ TCP 层可能没立即感知到（TCP keepalive 默认 2 小时）→ 服务端以为连接还在 → 但实际客户端已断 → 消息发出去没人收 → 消息丢失 ②服务端也要检测 → 如果不检测 → 假死连接越来越多 → 内存泄漏 / 心跳机制：①Ping/Pong 帧 → WebSocket 协议内置 → 客户端定时发 Ping → 服务端收到自动回 Pong ②流程 → 客户端每 30 秒发 Ping → 服务端 60 秒没收到 Ping → 认为断线 → 关闭连接 → 释放资源 ③服务端也可主动 Ping → 检测客户端是否存活 ④Ping/Pong 帧很小（2 字节）→ 不占带宽 / 实际实现：
```java
// Spring Boot WebSocket 心跳配置
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {
    @Override
    public void configureWebSocketTransport(WebSocketMessageBrokerRegistry registry) {
        // 服务端心跳 = 30秒发一次 Ping
        registry.setTaskScheduler(heartBeatScheduler());
    }
}

// 客户端（JS）
const ws = new WebSocket("ws://server/ws/chat");
// 浏览器自动处理 Ping/Pong → 但前端可以检测
let heartCheck = {
    timeout: 30000,
    timeoutObj: null,
    reset: function() {
        clearTimeout(this.timeoutObj);
        this.start();
    },
    start: function() {
        this.timeoutObj = setTimeout(() => {
            ws.send("heartbeat");  // 发心跳消息
            this.reset();
        }, this.timeout);
    }
};
ws.onopen = function() { heartCheck.start(); };
ws.onmessage = function() { heartCheck.reset(); };  // 收到消息重置计时
```
/ 断线重连：①客户端检测到断线 → 自动重连 → 带上上次的 `lastMessageId` → 服务端从该 ID 之后补发消息 ②指数退避 → 第 1 次等 1s → 第 2 次等 2s → 第 3 次等 4s → 避免大量客户端同时重连打崩服务端 ③重连失败超过 N 次 → 提示用户 → 停止重连 / 面试重点：假死连接=网络断但TCP没感知→服务端以为还在→消息丢失+内存泄漏 → 心跳=Ping/Pong帧(内置协议/2字节不占带宽)→30秒Ping→60秒没收到=断线→关闭释放 → 断线重连=带lastMessageId补发+指数退避(1s/2s/4s避免同时重连打崩)+N次停止 → Spring Boot用setTaskScheduler配心跳）

**追问4：** 50 万 WebSocket 连接怎么扛？服务端怎么设计才能支持高并发长连接？

> 你回答...（提示：高并发 WebSocket 架构 / 核心挑战：①50 万长连接 → 每个连接占内存 → 50 万 × 4KB ≈ 2GB → 内存够 ②但每个连接一个线程 → 50 万线程 → 每个线程 1MB 栈 → 500GB → 不可能 ③需要 NIO / Netty → 少量线程管理大量连接 / 架构设计：①接入层 → Netty + NIO → Boss 线程组（1-2 个）接受连接 → Worker 线程组（CPU 核数 × 2）处理 IO → 1 个 Worker 管理几千连接 → 50 万连接只需几十个 Worker 线程 ②连接路由 → 多台接入服务器 → 负载均衡 → 按用户 ID hash 到固定服务器 → 方便用户级管理 ③消息推送 → 用户 A 在 Server 1 → 消息要推给 A → 怎么找到 Server 1？→ Redis 存 `userId → serverId` 映射 → 消息发到对应 Server → Server 推给连接 ④广播 → 所有 Server 都收到 → 各自推给自己的连接 / Netty 核心配置：
```java
// Netty WebSocket Server
EventLoopGroup bossGroup = new NioEventLoopGroup(1);
EventLoopGroup workerGroup = new NioEventLoopGroup();  // 默认 CPU×2

ServerBootstrap b = new ServerBootstrap();
b.group(bossGroup, workerGroup)
 .channel(NioServerSocketChannel.class)
 .childHandler(new ChannelInitializer<SocketChannel>() {
     @Override
     protected void initChannel(SocketChannel ch) {
         ChannelPipeline pipeline = ch.pipeline();
         // HTTP 编解码（握手阶段是 HTTP）
         pipeline.addLast(new HttpServerCodec());
         pipeline.addLast(new HttpObjectAggregator(64 * 1024));
         // WebSocket 协议处理（自动完成握手 + 帧解析）
         pipeline.addLast(new WebSocketServerProtocolHandler("/ws"));
         // 业务处理
         pipeline.addLast(new WebSocketMessageHandler());
     }
 });
// 每 Channel 一个 pipeline → Worker 线程处理 IO 事件 → 不阻塞
```
/ JVM 调优：①50 万连接 → 堆内存增大 → `-Xmx4g -Xms4g` ②直接内存（DirectByteBuffer）→ Netty 用堆外内存 → `-XX:MaxDirectMemorySize=2g` ③GC → G1 或 ZGC → 减少 STW → 避免心跳超时 ④`-XX:+HeapDumpOnOutOfMemoryError` → OOM 时 dump / 面试重点：50万连接=NIO/Netty少量线程管大量连接(Boss 1-2个+Worker CPU×2个→每个Worker管几千连接) + 多台接入服务器负载均衡 + Redis存userId→serverId映射找连接 + 广播发所有Server各自推 → JVM=堆4g+直接内存2g+G1/ZGC减STW避免心跳超时+OOM dump）

---

## 话题四：Java 泛型深入（9分钟）

**面试官：泛型你天天用吧。List<String> 和 List<Integer> 在运行时是同一个类吗？类型擦除是什么意思？**

> 你回答...

**追问1：** 先说说类型擦除是什么。为什么 Java 的泛型叫"伪泛型"？和 C++ 的模板有什么区别？

> 你回答...（提示：类型擦除原理 / 类型擦除：①Java 泛型在编译时做类型检查 → 编译通过后 → 运行时擦除泛型类型信息 → `List<String>` 和 `List<Integer>` 运行时都是 `List` ②字节码层面 → `List<String>` 编译后就是 `List` → 元素类型 `String` 被擦除 → 方法参数变成 `Object` ③所以 → `List<String>.getClass() == List<Integer>.getClass()` → true → 运行时是同一个类 / 为什么叫"伪泛型"：①C++ 模板 → 真泛型 → `vector<int>` 和 `vector<string>` 编译后是两个不同的类 → 各有自己的代码 → 类型安全 + 无装箱拆箱 ②Java 泛型 → 伪泛型 → 编译后只有一个 `List` → 泛型信息擦除 → 运行时无法知道泛型类型 ③Java 选择擦除的原因 → 兼容性 → Java 5 引入泛型 → 要和 Java 4 的 `List` 兼容 → 擦除后字节码一样 → 旧代码不用改 / 擦除规则：①`<T>` → 擦除为 `Object` ②`<T extends Number>` → 擦除为 `Number`（有上界擦除为上界）③`<T extends Comparable<T>>` → 擦除为 `Comparable` ④`List<T[]>` → 擦除为 `List<Object[]>` / 擦除带来的问题：①不能 `new T()` → 运行时不知道 T 是什么 → 无法创建实例 ②不能 `new T[]` → 同理 ③不能用基本类型 → `List<int>` 不行 → 只能 `List<Integer>` → 装箱拆箱 ④不能 `instanceof List<String>` → 只能 `instanceof List` ⑤运行时无法获取泛型类型 → `list.getClass()` → 返回 `List` → 不知道元素类型 / 面试重点：类型擦除=编译时检查类型→运行时擦除→List<String>和List<Integer>运行时都是List → 伪泛型=C++模板是真泛型(两个不同类)/Java是伪泛型(运行时一个类) → 原因=兼容Java4 → 擦除规则=T→Object/T extends Number→Number → 问题=不能new T()/不能new T[]/不能用基本类型/不能instanceof泛型/运行时拿不到泛型类型）

**追问2：** PECS 原则是什么？`? extends T` 和 `? super T` 有什么区别？什么时候用哪个？

> 你回答...（提示：PECS 原则 / PECS = Producer Extends, Consumer Super：①`<? extends T>` → 生产者 → 从里面读 → 不能写 ②`<? super T>` → 消费者 → 往里面写 → 不能读（只能读 Object）/ `? extends T`（上界通配符）：①意思 → 泛型类型是 T 或 T 的子类 ②可以读 → `T t = list.get(0)` → 安全 → 因为不管实际是 T 的哪个子类 → 都能赋值给 T ③不能写 → `list.add(new T())` → 编译报错 → 因为编译器不知道实际类型 → 如果实际是 `List<Son>` → 你 add 一个 `Father` → 类型不安全 ④场景 → 函数只读不写 → 如 `void process(List<? extends Number> list)` → 读出来当 Number 用 / `? super T`（下界通配符）：①意思 → 泛型类型是 T 或 T 的父类 ②可以写 → `list.add(new T())` → 安全 → 因为实际类型是 T 或 T 的父类 → 加一个 T → 一定能放进去 ③不能读（精确读）→ `T t = list.get(0)` → 编译报错 → 因为实际可能是 `List<Object>` → 读出来是 Object → 不能赋值给 T ④只能读 Object → `Object o = list.get(0)` → 安全 / 典型应用——JDK 源码：
```java
// Collections.copy 方法
public static <T> void copy(List<? super T> dest, List<? extends T> src) {
    // src 是生产者 → ? extends T → 只读
    // dest 是消费者 → ? super T → 只写
    for (int i = 0; i < src.size(); i++) {
        dest.set(i, src.get(i));  // 从 src 读 → 写到 dest
    }
}
// 调用：把 List<Integer> 的数据拷到 List<Number>
Collections.copy(new ArrayList<Number>(), new ArrayList<Integer>());
// dest = List<? super Integer> → List<Number> 是 Integer 的父类 → OK
// src = List<? extends Integer> → List<Integer> 是 Integer 的子类 → OK
```
/ 面试重点：PECS=Producer Extends(读用?extends)/Consumer Super(写用?super) → ?extends T=读安全写不安全(实际可能是子类→加父类不安全) → ?super T=写安全读不安全(实际可能是父类→读出Object不能赋给T) → 典型=Collections.copy(dest=super只写/src=extends只读) → 记忆="读用extends写用super"）

**追问3：** 类型擦除会导致什么问题？桥接方法是什么？为什么编译器要生成它？

> 你回答...（提示：桥接方法 / 问题场景——继承泛型类后方法签名不匹配：①定义泛型父类：
```java
class Parent<T> {
    void set(T t) { ... }
}
// 子类指定泛型为 String
class Child extends Parent<String> {
    @Override
    void set(String t) { ... }  // 重写父类方法
}
```
②类型擦除后 → 父类 `set(T t)` 变成 `set(Object t)` → 子类 `set(String t)` 签名不同 ③多态调用 → `Parent p = new Child(); p.set("hello")` → JVM 找 `set(Object)` 方法 → 但子类只有 `set(String)` → 方法签名不匹配 → 找不到方法？/ 桥接方法解决：①编译器自动生成桥接方法 → 子类字节码中：
```java
// 编译器生成的桥接方法（合成方法）
void set(Object t) {  // 签名和擦除后的父类一致
    set((String) t);  // 强转后调用真正的 set(String)
}
```
②这样 → `p.set("hello")` → 找到 `set(Object)` → 桥接方法 → 强转 → 调用 `set(String)` → 多态正确 ③桥接方法是 `synthetic` 的 → 你在源码中看不到 → 但字节码里有 → `javap -v Child.class` 能看到 `bridge` 标志 / 其他擦除问题：①泛型方法重载冲突 → `void process(List<String>)` 和 `void process(List<Integer>)` → 擦除后都是 `process(List)` → 编译报错 ②泛型类型不能 catch → `catch (T e)` → 运行时不知道 T → 不能 catch 泛型异常 ③泛型数组 → `new List<String>[10]` → 编译报错 → 因为数组协变 + 泛型擦除 → 类型不安全 → `Object[] arr = new List<String>[10]; arr[0] = new List<Integer>()` → 运行时检查不到 / 面试重点：桥接方法=类型擦除后父类方法签名(Object)和子类方法签名(String)不匹配→编译器自动生成set(Object)→强转调用set(String)→保证多态正确 → 其他问题=泛型重载冲突(擦除后签名相同)/不能catch泛型异常/不能new泛型数组(数组协变+擦除=不安全)）

**追问4：** 你说不能 new T()。但 Spring 的 `@Autowired List<T>` 或者 Jackson 反序列化 `new TypeReference<List<User>>(){}` 是怎么拿到泛型类型的？运行时不是擦除了吗？

> 你回答...（提示：运行时获取泛型类型的方法 / 类型擦除的"漏洞"——泛型信息不是完全丢失：①擦除的是字节码中的方法签名和字段类型 → 但类的泛型签名信息存在 Class 文件的结构表里（Signature 属性）②父类/接口的泛型参数 → 存在字节码中 → 可以通过反射获取 ③局部变量的泛型 → 完全擦除 → 无法获取 / 方法一：Class.getGenericSuperclass() → 获取父类的泛型类型
```java
// Jackson 的 TypeReference 原理
public abstract class TypeReference<T> {
    private final Type type;
    
    protected TypeReference() {
        // 获取父类的泛型参数
        Type superClass = getClass().getGenericSuperclass();
        ParameterizedType pt = (ParameterizedType) superClass;
        this.type = pt.getActualTypeArguments()[0];  // 拿到 T 的实际类型
    }
    public Type getType() { return type; }
}

// 使用 → 创建匿名子类
TypeReference<List<User>> ref = new TypeReference<List<User>>() {};
// getClass() = 匿名子类 → getGenericSuperclass() = TypeReference<List<User>>
// getActualTypeArguments()[0] = List<User> → 拿到了！
```
/ 方法二：Spring ResolvableType
```java
// Spring 封装的泛型解析工具
ResolvableType t = ResolvableType.forClass(MyService.class);
// 获取父类泛型
Class<?> generic = t.getSuperType().getGeneric(0).resolve();
// 获取字段泛型
Field field = MyService.class.getDeclaredField("list");
ResolvableType ft = ResolvableType.forField(field);
Class<?> elementType = ft.getGeneric(0).resolve();  // List<User> → User
```
/ 方法三：Spring 的 `@Autowired List<T>` → Spring 在注入时 → 知道字段/方法的泛型参数 → 通过 `ResolvableType` 解析 → 找到所有 T 类型的 Bean → 注入 / 为什么匿名内部类能拿到泛型：①`new TypeReference<List<User>>() {}` → 创建匿名子类 → 匿名子类的父类是 `TypeReference<List<User>>` ②子类编译后 → 字节码中记录了父类的泛型参数 → `Signature: LTypeReference<Ljava/util/List<LUser;>;>;` ③运行时 `getGenericSuperclass()` → 读取 Signature 属性 → 拿到 `List<User>` → 反射可以解析 / 面试重点：擦除有漏洞=字节码Signature属性存了泛型签名→父类/接口泛型可获取→局部变量擦除无法获取 → 获取方法=①getGenericSuperclass()+ParameterizedType.getActualTypeArguments()→Jackson TypeReference原理(匿名子类父类泛型存字节码) ②Spring ResolvableType封装解析(字段/方法/父类泛型) → 核心=匿名内部类父类泛型存在字节码Signature属性→运行时可读）

---

## 话题五：MySQL Online DDL（8分钟）

**面试官：你们有没有在生产环境给大表加过字段？一张 5000 万行的表加个字段，怎么操作？直接 ALTER TABLE 吗？**

> 你回答...

**追问1：** 直接 ALTER TABLE 加字段会发生什么？为什么大表不能直接加？

> 你回答...（提示：DDL 的问题 / 直接 ALTER TABLE 的问题：①MySQL 5.6 之前 → ALTER TABLE = 创建新表（新结构）→ 旧表数据逐行复制到新表 → 旧表加写锁 → 整个过程表不可写 → 5000 万行复制可能几十分钟 → 期间所有写请求阻塞 ②MySQL 5.6+ → Online DDL → 部分操作可以"在线"执行 → 不锁表或只锁很短时间 ③但不是所有 DDL 都能 Online → 有些操作仍需锁表 / DDL 执行方式分类：①`ALGORITHM=COPY` → 创建新表 + 复制数据 → 锁表（最慢）②`ALGORITHM=INPLACE` → 原地修改 → 不复制数据 → 不锁表或短锁（MySQL 5.6+）③`ALGORITHM=INSTANT` → 瞬间完成 → 只修改元数据 → 不锁表（MySQL 8.0.12+）/ 哪些 DDL 能 Online：
| 操作 | COPY | INPLACE | INSTANT |
|------|------|---------|---------|
| 加列（默认末尾）| ✗ | ✓ | ✓(8.0.12+) |
| 加列（中间）| ✓(复制) | ✗ | ✗ |
| 删列 | ✓(复制) | ✗ | ✗ |
| 修改列类型 | ✓(复制) | ✗ | ✗ |
| 加索引 | ✗ | ✓ | ✗ |
| 改列默认值 | ✗ | ✓ | ✓(8.0.12+) |
| 重命名列 | ✗ | ✓ | ✗ |
①加列在末尾 → MySQL 8.0+ INSTANT → 秒级完成 → 不锁表 ②加列在中间 → 必须 COPY → 锁表复制 ③删列 → 必须 COPY → 锁表 ④加索引 → INPLACE → 不复制数据但需要构建索引 → 期间可读写但不快 / 面试重点：直接ALTER=5.6前创建新表+复制数据+锁表写不可用(5000万行几十分钟) → Online DDL=INPLACE(原地改不复制)/INSTANT(改元数据秒级/8.0.12+) → 能Online=加末尾列(INSTANT)/加索引(INPLACE)/改默认值 → 不能Online=加中间列/删列/改类型(必须COPY复制+锁表)）

**追问2：** 如果不能直接 ALTER（比如删列、改类型），大表怎么办？用什么工具？

> 你回答...（提示：第三方 DDL 工具 / pt-online-schema-change（Percona Toolkit）：①原理 → 创建新表（影子表 shadow table）→ 创建触发器（INSERT/UPDATE/DELETE 触发器）→ 旧表每次写操作 → 触发器同步到新表 → 后台分批拷贝数据 → 拷贝完成 → RENAME 旧表→新表 → 删除旧表 ②流程 → ①创建影子表 ` CREATE TABLE _t_new LIKE t` ②ALTER 影子表加字段 ③创建触发器（INSERT/UPDATE/DELETE → 同步到影子表）④分批拷贝 `INSERT INTO _t_new SELECT * FROM t WHERE id BETWEEN x AND x+1000` ⑤拷贝完成 → RENAME TABLE t TO _t_old, _t_new TO t ⑥删除旧表 ③优点 → 不锁表 → 读写正常 → 可以暂停恢复 ④缺点 → 触发器有性能开销 → 拷贝期间占额外空间（新表+旧表）→ RENAME 瞬间有短暂锁（毫秒级）/ GH-OST（GitHub Online Schema Change）：①原理 → 类似 pt-osc → 但不用触发器 → 用 binlog 同步 → 解析 binlog → 应用到影子表 ②优点 → 不用触发器 → 无触发器性能开销 → 可暂停 → 可动态调整速率 → 更安全 ③缺点 → 要求 binlog_format=ROW → 配置更复杂 ④GitHub 开源 → 比 pt-osc 新 → 逐渐成为首选 / 选型对比：
| 工具 | 原理 | 优点 | 缺点 |
|------|------|------|------|
| 原生 Online DDL | INPLACE/INSTANT | 无额外工具 | 部分操作不支持 |
| pt-osc | 影子表+触发器 | 成熟稳定 | 触发器开销 |
| GH-OST | 影子表+binlog | 无触发器/可暂停 | 需ROW binlog |
/ 实际操作流程（5000万行加字段）：①先查能不能 INSTANT → `ALTER TABLE t ADD COLUMN c INT, ALGORITHM=INSTANT` → 如果支持 → 秒级完成 → 不需要工具 ②不支持 INSTANT → INPLACE → `ALTER TABLE t ADD COLUMN c INT, ALGORITHM=INPLACE, LOCK=NONE` → 尝试在线 ③INPLACE 也不支持 → 用 GH-OST → 后台分批 + binlog 同步 → 不影响业务 ④极端情况 → 如果表太大（10亿+）→ 分时段执行 → 低峰期执行 → 监控延迟 / 面试重点：pt-osc=影子表+触发器同步写+分批拷贝+RENAME(不锁表但触发器有开销+占双倍空间) → GH-OST=影子表+binlog同步(无触发器开销+可暂停+更安全)→需ROW binlog → 实际操作=先试INSTANT(秒级)→再试INPLACE→不行用GH-OST→10亿+低峰期分时段执行）

**追问3：** DDL 执行过程中如果失败了怎么办？会不会丢数据？有什么风险？

> 你回答...（提示：DDL 风险与回滚 / 原生 DDL 失败：①COPY 模式 → 创建新表失败 / 复制到一半失败 → MySQL 自动回滚 → 删除影子表 → 不影响原表 ②INPLACE → 失败 → 原表不变 ③INSTANT → 修改元数据 → 失败概率极低 / pt-osc / GH-OST 风险：①拷贝到一半 → 工具被 kill → 影子表残留 → 触发器残留 → 需要手动清理 → `DROP TABLE _t_new; DROP TRIGGER ...` ②RENAME 瞬间 → 如果数据库挂了 → 可能旧表已改名但新表还没改名 → 表"消失" → 需要手动 RENAME 恢复 ③空间不足 → 拷贝需要影子表 → 占双倍空间 → 空间不足 → 拷贝失败 / 常见风险：①锁表 → 即使 Online DDL → 某些阶段仍需要短暂的 MDL（元数据锁）→ 如果此时有长事务持有 MDL → DDL 被阻塞 → 后续所有请求被阻塞 → 连接池耗尽 → 服务不可用 ②主从延迟 → DDL 在主库执行完后 → 从库也要执行 → 如果从库性能差 → 从库延迟 → 读写分离读到旧结构 ③触发器性能 → pt-osc 的触发器 → 每行写操作额外执行触发器 → 写性能下降 20-50% → 高写入表影响大 / 安全措施：①先在测试环境执行 → 验证 ②低峰期执行 → 减少影响 ③监控 → MDL 等待 / 主从延迟 / 慢查询 ④设置超时 → `lock_wait_timeout=30` → MDL 等 30 秒 → 超时放弃 → 不阻塞后续请求 ⑤预留空间 → 确保磁盘空间足够（旧表 + 新表 = 双倍）⑥准备回滚方案 → 记录 DDL → 失败时手动恢复 / 面试重点：原生DDL失败=自动回滚不影响原表 → pt-osc/GH-OST风险=拷贝到一半kill→影子表/触发器残留→手动清理 + RENAME瞬间数据库挂→表消失→手动恢复 + 空间不足失败 → 常见风险=MDL锁(长事务持有→DDL阻塞→后续全阻塞→连接池耗尽)+主从延迟+触发器性能下降20-50% → 安全=测试环境先验+低峰期+监控MDL/延迟/慢查询+lock_wait_timeout=30+预留双倍空间+准备回滚方案）

---

## 话题六：分布式限流（9分钟）

**面试官：你们做过限流吗？单机限流和分布式限流有什么区别？分布式限流怎么实现？**

> 你回答...

**追问1：** 先说说单机限流有哪些算法。Guava RateLimiter 是什么算法？有什么局限？

> 你回答...（提示：单机限流算法回顾 / 四种限流算法：①计数器（固定窗口）→ 每秒计数 → 超了拒绝 → 边界问题：0.9s 来 100 个 + 1.1s 来 100 个 → 0.2 秒内 200 个 → 突破限制 ②滑动窗口 → Sentinel 的 LeapArray → 把窗口分成更小的格子 → 每格独立计数 → 滑动统计 → 解决边界问题 ③漏桶 → 固定速率输出 → 超出排队或丢弃 → 不允许突发 ④令牌桶 → 固定速率生成令牌 → 请求取令牌 → 有令牌通过 → 桶满令牌丢弃 → 允许突发（桶里有积攒的令牌）/ Guava RateLimiter：①令牌桶算法 → `RateLimiter.create(100)` → 每秒生成 100 个令牌 → `acquire()` → 取一个令牌 → 如果没令牌 → 等待 ②预计算（懒计算）→ 不用后台线程发令牌 → `acquire()` 时计算上次到现在应该生成了多少令牌 → `elapsedTime × rate` → 如果够 → 直接返回 → 如果不够 → 等待 / 单机限流的局限：①只限本机 → 微服务有 10 个实例 → 每个限 100 QPS → 总共 1000 QPS → 但下游只能扛 500 QPS → 打爆下游 ②无法全局限流 → 有些限流是全局的 → 如"全局限流 500 QPS 保护下游"→ 单机限不了 ③实例数变化 → K8s 弹性扩容 → 实例从 5 变 10 → 每个实例配额要动态调整 → 单机不好做 / 面试重点：四种算法=计数器(固定窗口/边界问题)/滑动窗口(Sentinel LeapArray/解决边界)/漏桶(固定速率不允许突发)/令牌桶(Guava RateLimiter/允许突发/预计算懒计算) → 局限=只限本机→多实例总QPS超下游承受/无法全局限流/实例数变化配额要动态调整）

**追问2：** 分布式限流怎么实现？Redis+Lua 方案的核心原理是什么？有什么性能瓶颈？

> 你回答...（提示：Redis+Lua 分布式限流 / 核心原理：①Redis 做全局限流计数器 → 所有实例共享 → 原子操作保证准确 ②Lua 脚本 → 原子执行"判断 + 更新"→ 防止并发问题 / 滑动窗口实现（Redis + Lua）：
```lua
-- KEYS[1] = 限流key 如 rate_limit:user:123
-- ARGV[1] = 窗口大小(毫秒) 如 1000
-- ARGV[2] = 最大请求数 如 100
-- ARGV[3] = 当前时间戳(毫秒)
-- ARGV[4] = 当前请求ID(唯一标识)

local key = KEYS[1]
local window = tonumber(ARGV[1])
local maxRequests = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local requestId = ARGV[4]

-- 窗口起始时间
local windowStart = now - window

-- 1. 移除窗口外的旧请求
redis.call('ZREMRANGEBYSCORE', key, 0, windowStart)

-- 2. 当前窗口内的请求数
local current = redis.call('ZCARD', key)

-- 3. 判断是否超过限制
if current < maxRequests then
    -- 未超限 → 添加当前请求
    redis.call('ZADD', key, now, requestId)
    -- 设置过期时间（窗口大小 + 缓冲）
    redis.call('PEXPIRE', key, window + 1000)
    return 1  -- 允许
else
    return 0  -- 拒绝
end
```
/ 工作原理：①用 Redis ZSET → score = 时间戳 → value = 请求唯一 ID ②每次请求 → Lua 脚本原子执行：移除窗口外的旧请求 → 统计当前请求数 → 未超限则 ZADD → 超限则拒绝 ③ZREMRANGEBYSCORE → 移除 score < (now - window) 的请求 → 滑动窗口 ④ZCARD → 统计窗口内请求数 / 性能瓶颈：①Redis 单点 → 所有限流请求都走 Redis → Redis 成了瓶颈 → 高 QPS（万级）→ Redis 压力大 ②网络延迟 → 每次请求 → Redis 一次往返 → 增加延迟 → 原本 1ms 的请求 → 加 Redis 限流 → 2-3ms ③Lua 脚本执行 → 虽然 Lua 原子 → 但高并发下 → 大量 ZADD/ZREMRANGEBYSCORE → Redis CPU 飙升 / 优化方案：①本地预消费 → 每个实例从 Redis 批量获取令牌（如一次取 100 个）→ 本地消费 → 减少 Redis 请求次数 → 但精度降低（本地消费完才去取 → 可能有短暂超限）②多级限流 → 网关限流（粗粒度）+ 应用限流（细粒度）+ Redis 全局限流（兜底）→ 减少全局限流压力 / 面试重点：Redis+Lua=ZSET存(score=时间戳/value=请求ID)→Lua原子执行(移除窗口外旧请求→统计当前数→未超限ZADD/超限拒绝) → 瓶颈=Redis单点(万级QPS压力大)+网络延迟(每次往返+2-3ms)+Lua执行CPU飙升 → 优化=本地预消费(批量取令牌减Redis请求)+多级限流(网关粗+应用细+Redis兜底)）

**追问3：** Sentinel 的集群限流（Token Server）是怎么做的？和 Redis+Lua 方案有什么区别？

> 你回答...（提示：Sentinel Token Server / Sentinel 集群限流架构：
```
                     ┌─────────────────────┐
                     │   Token Server      │
                     │  (独立部署/嵌入式)   │
                     │  维护全局限流规则    │
                     │  计算令牌/配额      │
                     └──────────┬──────────┘
                                │ TCP 长连接
              ┌─────────────────┼─────────────────┐
              │                 │                 │
     ┌────────┴───┐    ┌───────┴────┐    ┌───────┴────┐
     │ Client 1   │    │ Client 2   │    │ Client 3   │
     │ 本地限流    │    │ 本地限流    │    │ 本地限流    │
     │ 批量取令牌  │    │ 批量取令牌  │    │ 批量取令牌  │
     └────────────┘    └────────────┘    └────────────┘
```
/ 工作流程：①Token Server 独立部署 → 维护全局限流规则 ②Client（应用）启动 → 连接 Token Server → 注册 ③请求来 → Client 先过本地限流（单机）→ 如果本地通过 → 向 Token Server 申请令牌 ④Token Server → 全局计算 → 有令牌 → 批量发放（如一次发 50 个）→ Client 本地消费 ⑤Client 本地令牌用完 → 再向 Server 申请 → 如果 Server 拒绝（全局限流）→ Client 本地也拒绝 / 和 Redis+Lua 的区别：
| 维度 | Redis+Lua | Sentinel Token Server |
|------|-----------|----------------------|
| 存储 | Redis ZSET | 内存（Token Server 内存） |
| 通信 | Redis 协议 | TCP 长连接 |
| 性能 | 中（Redis网络+Lua） | 高（内存+长连接+批量） |
| 精度 | 高（每次精确） | 中（批量预取有误差） |
| 可靠性 | Redis 挂了限流失效 | Server 挂了降级为本地限流 |
| 限流算法 | 自己实现（Lua） | 内置（滑动窗口/令牌桶） |
①Redis+Lua → 每次请求都走 Redis → 精确但慢 → 适合精度要求高、QPS 适中的场景 ②Token Server → 批量预取 → 快但精度低 → 适合高 QPS、可容忍少量误差的场景 ③Token Server 挂了 → 降级为本地限流 → 不会完全失效 → 比 Redis 挂了好 / 降级策略：①Token Server 不可用 → Client 降级为本地限流 → 每个实例按 `全局配额 / 实例数` 做本地限流 → 不会完全不限流 → 但精度降低 ②Token Server 恢复 → Client 重新连接 → 恢复全局限流 / 面试重点：Token Server=独立部署维护全局规则→Client TCP长连接→批量取令牌(一次50个)→本地消费→用完再取 → vs Redis+Lua=内存+长连接+批量→性能高但精度中(批量预取误差) → 降级=Server挂了降级本地限流(全局配额/实例数)→不失效但精度降低 → 选型=高QPS用Token Server/高精度用Redis+Lua）

**追问4：** 网关层限流（Nginx/Spring Cloud Gateway）和应用层限流（Sentinel）怎么配合？多级限流怎么设计？

> 你回答...（提示：多级限流架构 / 多级限流设计：
```
请求 → Nginx(粗粒度/IP限流) → Gateway(中粒度/API限流) → 应用(细粒度/业务限流) → 下游服务(保护限流)
```
/ 第一级：Nginx 限流（接入层）：
①`limit_req` → 漏桶 → 固定速率 → 按 IP 限流 → 防恶意请求
```nginx
limit_req_zone $binary_remote_addr zone=ip_limit:10m rate=10r/s;
location /api/ {
    limit_req zone=ip_limit burst=20 nodelay;
    # 每秒10个请求/IP → 突发20个
}
```
②作用 → 在最外层拦截恶意流量 → 保护后端所有服务 → 粗粒度
/ 第二级：Spring Cloud Gateway 限流（网关层）：
①基于 Redis + Lua → 按 API 路径 / 用户 ID 限流
②`RequestRateLimiter` → 内置 Redis 令牌桶
```yaml
spring:
  cloud:
    gateway:
      routes:
        - id: user-service
          filters:
            - name: RequestRateLimiter
              args:
                redis-rate-limiter.replenishRate: 100  # 令牌生成速率
                redis-rate-limiter.burstCapacity: 200   # 桶容量
                key-resolver: "#{@userKeyResolver}"     # 按用户限流
```
③作用 → 全局 API 级别限流 → 防止某个 API 过载 → 中粒度
/ 第三级：应用层 Sentinel（业务层）：
①按接口 / 资源 / 用户 → 细粒度限流
②`@SentinelResource("queryUser")` → QPS > 100 → 拒绝/排队/降级
③可以按参数限流 → 如 `queryUser(userId)` → 每个用户 10 QPS
④熔断 + 降级 → 限流后走 fallback → 返回默认值
/ 第四级：下游服务自我保护：
①调用下游 → 设置超时 + 重试限制 → 不打爆下游
②Sentinel 熔断 → 下游异常率高 → 熔断 → 快速失败
/ 设计原则：①粗→细 → Nginx(IP级) → Gateway(API级) → Sentinel(接口/参数级) → 下游(超时/熔断) ②就近拒绝 → 越早拒绝越好 → Nginx 拒绝 → 不占用 Gateway 资源 → Gateway 拒绝 → 不占用应用资源 ③不同维度 → Nginx 限 IP（防刷）/ Gateway 限 API（防过载）/ Sentinel 限接口+用户（精细化）/ 下游超时+熔断（保护下游） ④降级链路 → 限流后 → 返回降级数据（缓存/默认值）→ 不是直接报错 / 面试重点：多级限流=Nginx(IP级/漏桶/防恶意)→Gateway(API级/Redis令牌桶/防过载)→Sentinel(接口+参数级/细粒度/降级)→下游(超时+熔断保护) → 原则=粗到细+就近拒绝(Nginx拒绝不占Gateway资源)+不同维度(IP/API/接口/下游)+限流后降级(缓存/默认值不报错)）

---

## 话题七：JVM 字节码基础（8分钟）

**面试官：你了解 Java 字节码吗？.class 文件的结构是什么样的？javap 看到的东西你看得懂吗？**

> 你回答...

**追问1：** 先说说 .class 文件的结构。一个编译后的 .class 文件包含哪些部分？

> 你回答...（提示：.class 文件结构 / Class 文件格式（按顺序）：①魔数 → `0xCAFEBABE`（咖啡宝贝）→ 4 字节 → 固定值 → 确认是 .class 文件 ②版本号 → minor_version + major_version → 2+2 字节 → 如 JDK 8 = 52.0 → JDK 17 = 61.0 → 高版本 JDK 能运行低版本 class → 反过来不行 ③常量池 → constant_pool_count + constant_pool → 存字面量（字符串/数字）+ 符号引用（类名/方法名/字段名）→ 最重要的一部分 → 后面所有引用都通过常量池索引 ④访问标志 → access_flags → public/final/abstract/interface/annotation/enum 等 ⑤类信息 → this_class（当前类）+ super_class（父类）+ interfaces（接口列表）⑥字段表 → fields → 类的字段 → 每个字段有 access_flags + name_index + descriptor_index + attributes ⑦方法表 → methods → 类的方法 → 每个方法有 access_flags + name_index + descriptor_index + Code 属性（字节码指令在 Code 里）⑧属性表 → attributes → 附加信息 → 如 SourceFile（源文件名）/ InnerClasses（内部类）/ Signature（泛型签名）/ BootstrapMethods（ invokedynamic 引导方法）/ 常量池的作用：①存所有"常量" → 字符串字面量 / 数字常量 / 类名 / 方法名 / 字段名 / 方法描述符 ②用索引引用 → 如方法调用 → 字节码 `invokevirtual #2` → #2 是常量池索引 → 指向一个 MethodRef → 包含类名 + 方法名 + 描述符 ③减少重复 → 同一个字符串只存一份 → 多处引用同一个索引 / 方法描述符：①格式 → `(参数类型)返回类型` → 如 `(Ljava/lang/String;I)V` → 参数 String + int → 返回 void ②基本类型 → B=byte/C=char/D=double/F=float/I=int/J=long/S=short/Z=boolean/V=void ③对象 → `L类名;` → 如 `Ljava/lang/String;` ④数组 → `[` 前缀 → 如 `[I` = int[] / `[Ljava/lang/String;` = String[] / 面试重点：.class=魔数(CAFEBABE)+版本号+常量池(字面量+符号引用/索引引用/减少重复)+访问标志+类信息(this/super/interfaces)+字段表+方法表(含Code字节码)+属性表(Signature泛型/BootstrapMethods) → 描述符=(参数类型)返回类型→I=int/J=long/L类名;/[数组）

**追问2：** 常见的字节码指令有哪些？`iadd` 和 `ladd` 有什么区别？`invokevirtual` 和 `invokeinterface` 有什么区别？

> 你回答...（提示：字节码指令 / 指令分类（按功能）：①加载/存储 → `iload`（局部变量→操作数栈）/ `istore`（栈→局部变量）/ `aload`（对象引用加载）/ `astore` ②算术 → `iadd`（int 加）/ `ladd`（long 加）/ `imul`（int 乘）/ `idiv`（int 除）/ `ineg`（取负）③类型转换 → `i2l`（int→long）/ `i2d`（int→double）/ `l2i` ④对象操作 → `new`（创建对象）/ `getfield`（读字段）/ `putfield`（写字段）/ `arraylength` ⑤方法调用 → `invokevirtual`（虚方法/动态分派）/ `invokestatic`（静态方法）/ `invokeinterface`（接口方法）/ `invokespecial`（构造方法/private/super.method）/ `invokedynamic`（动态调用/lambda）⑥控制流 → `if_icmpeq`（int 比较 ==）/ `goto` / `return` / `ireturn`（返回 int）/ `areturn`（返回引用）/ `invokevirtual` vs `invokeinterface`：①`invokevirtual` → 调用虚方法 → 对象有确切的类 → 通过类的 vtable（虚方法表）查找 → 直接索引 → 快 ②`invokeinterface` → 调用接口方法 → 对象可能是任何实现类 → 要搜 itable（接口方法表）→ 先找接口 → 再找方法 → 比 invokevirtual 慢 ③如 `list.size()` → 如果 List 是 ArrayList → 编译器生成 `invokeinterface #MethodRef(List.size)` → 运行时通过 ArrayList 的 itable 找 size 方法 → 比 `invokevirtual` 多一次搜索 ④所以接口调用比类调用略慢 → 但 JVM 优化后差距很小 / `iadd` vs `ladd`：①`iadd` → 操作数栈弹两个 int → 相加 → 结果压栈（32 位）②`ladd` → 弹两个 long → 相加 → 压栈（64 位）→ long 占两个栈位 ③JVM 操作数栈以 32 位为单位 → long/double 占两个 slot → 所以指令不同 / 一段简单代码的字节码：
```java
// 源码
public int add(int a, int b) {
    int c = a + b;
    return c;
}

// 字节码
iload_1    // 局部变量1(a) → 操作数栈
iload_2    // 局部变量2(b) → 操作数栈
iadd       // 弹出两个int → 相加 → 压入结果
istore_3   // 栈顶 → 局部变量3(c)
iload_3    // c → 栈
ireturn    // 返回栈顶int
```
/ 面试重点：指令分类=加载存储(iload/istore)+算术(iadd/ladd/类型不同指令不同)+类型转换(i2l)+对象(new/getfield/putfield)+方法调用(invokevirtual虚方法vtable/invokestatic/invokeinterface接口itable慢/invokespecial构造private/invokedynamic lambda)+控制流(if_icmpeq/goto/return) → invokevirtual=类vtable直接索引快/invokeinterface=搜itable多一步慢 → iadd=32位/ladd=64位占两slot指令不同）

**追问3：** `invokedynamic` 是什么？为什么 Lambda 表达式要用它？和匿名内部类有什么区别？

> 你回答...（提示：invokedynamic 与 Lambda / invokedynamic 引入：①Java 7 引入 → 允许动态语言在 JVM 上运行 → 方法调用在运行时决定 → 不在编译时绑定 ②`invokedynamic` → 通过 `BootstrapMethods`（引导方法）→ 第一次执行时 → 调用引导方法 → 生成 `CallSite`（调用点）→ 确定要调用的方法 → 后续直接调用 → 不会每次都动态查找 / Lambda 表达式为什么用 invokedynamic：①Java 8 前 → Lambda 用匿名内部类实现 → 编译时生成额外的 .class 文件 → 每个 Lambda 一个内部类 → 类加载开销 + 内存占用 ②Java 8 Lambda → 不生成内部类 → 用 `invokedynamic` + `LambdaMetafactory` → 运行时动态生成实现类 → 编译时不生成额外 .class / Lambda 编译过程：①源码：
```java
Runnable r = () -> System.out.println("hello");
```
②编译后 → 不生成匿名内部类 → 字节码：
```
invokedynamic #2  // 引导方法 = LambdaMetafactory.metafactory()
                 // 方法签名 = ()Runnable
                 // 实际方法 = lambda$main$0() → 编译器生成的方法
```
③`LambdaMetafactory.metafactory()` → 运行时 → 用 `MethodHandle` 生成一个实现 Runnable 的类 → 调用 `lambda$main$0()` ④生成的类 → 可能是内部类（`$$Lambda$1`）→ 但只在运行时生成 → 不占编译产物 → 且 JVM 有缓存 → 同一个 Lambda 只生成一次 / 和匿名内部类区别：
| 维度 | 匿名内部类 | Lambda + invokedynamic |
|------|-----------|----------------------|
| 编译产物 | 生成额外 .class | 不生成(运行时动态) |
| 类加载 | 编译时加载 | 运行时首次加载 |
| this 引用 | 有 this | 无 this（除非用 this） |
| 性能 | 类加载开销 | 首次稍慢/后续快 |
| 序列化 | 支持 | 默认不支持(SerializableLambda) |
/ 面试重点：invokedynamic=Java7引入→运行时通过BootstrapMethods引导方法确定调用方法→不编译时绑定 → Lambda=不用匿名内部类(不生成额外.class)→invokedynamic+LambdaMetafactory运行时动态生成实现类→JVM缓存只生成一次 → 和匿名内部类区别=编译时不生成.class/运行时动态生成/this引用不同/序列化默认不支持）

---

## 话题八：手写代码 - 合并区间（8分钟）

**面试官：给你一组区间，合并所有重叠的区间。比如 [[1,3],[2,6],[8,10],[15,18]] → [[1,6],[8,10],[15,18]]。写一下。**

你在纸上/白板上写代码...

**追问1：** 先说说思路。这题的本质是什么？怎么判断两个区间重叠？

> 你回答...（提示：合并区间思路 / 思路：①先按区间起始位置排序 → 排序后 → 只需和前一个比较 → 不用两两比较 ②遍历 → 当前区间和结果中最后一个区间比较 → 如果重叠（当前.start <= 末尾.end）→ 合并（end = max(末尾.end, 当前.end)）→ 如果不重叠 → 加入结果 ③重叠判断 → 排序后 → 当前.start <= 末尾.end → 重叠 → 否则不重叠 / 代码：
```java
public int[][] merge(int[][] intervals) {
    if (intervals == null || intervals.length == 0) return new int[0][];
    
    // 1. 按起始位置排序
    Arrays.sort(intervals, (a, b) -> a[0] - b[0]);
    
    // 2. 合并
    List<int[]> merged = new ArrayList<>();
    for (int[] interval : intervals) {
        // 如果结果为空 或 当前区间不重叠
        if (merged.isEmpty() || merged.get(merged.size() - 1)[1] < interval[0]) {
            merged.add(interval);  // 不重叠 → 直接加入
        } else {
            // 重叠 → 合并（更新末尾的 end）
            merged.get(merged.size() - 1)[1] = 
                Math.max(merged.get(merged.size() - 1)[1], interval[1]);
        }
    }
    
    return merged.toArray(new int[0][]);
}
```
/ 核心要点：①排序 → 按起始位置 → O(n log n) ②遍历 → 和末尾比较 → 重叠则合并 end → 不重叠则加入 ③时间 O(n log n)（排序占大头）→ 空间 O(n)（结果数组）/ 面试重点：思路=按起始排序→遍历和末尾比较→重叠(current.start <= last.end)则合并end=max→不重叠则加入 → 时间O(nlogn)排序占大头 → 核心=排序后只需和前一个比较不用两两比较）

**追问2：** 如果区间不能排序（比如区间是流式输入），怎么做？或者如果是要判断一个新区间能否插入已有区间列表中呢？

> 你回答...（提示：插入区间 / 插入区间思路：①已排序的区间列表 → 插入一个新区间 → 合并重叠的 ②三段处理 → ①新区间左边的（end < newInterval.start）→ 直接加入 ②和新区间重叠的 → 合并（start = min / end = max）→ 循环合并所有重叠的 ③新区间右边的（start > merged.end）→ 直接加入 / 代码：
```java
public int[][] insert(int[][] intervals, int[] newInterval) {
    List<int[]> result = new ArrayList<>();
    int i = 0;
    int n = intervals.length;
    
    // 1. 左边不重叠的 → 直接加入
    while (i < n && intervals[i][1] < newInterval[0]) {
        result.add(intervals[i]);
        i++;
    }
    
    // 2. 重叠的 → 合并
    while (i < n && intervals[i][0] <= newInterval[1]) {
        newInterval[0] = Math.min(newInterval[0], intervals[i][0]);
        newInterval[1] = Math.max(newInterval[1], intervals[i][1]);
        i++;
    }
    result.add(newInterval);  // 合并后的新区间
    
    // 3. 右边不重叠的 → 直接加入
    while (i < n) {
        result.add(intervals[i]);
        i++;
    }
    
    return result.toArray(new int[0][]);
}
```
/ 流式输入场景：①如果区间是流式来的 → 不能排序 → 维护一个已合并的区间列表 → 每来一个新区间 → 用插入区间的方式合并 → O(n) 单次插入 ②如果有大量区间 → 用线段树 / 区间树 → 区间查询 + 合并 → 更高效 / 面试重点：插入=三段处理(左边不重叠直接加/重叠的合并start=min end=max循环合并/右边不重叠直接加) → 流式=维护已合并列表→每次插入合并→O(n)单次 → 大量区间=线段树/区间树高效查询合并）

**追问3：** 如果不是合并重叠区间，而是求重叠最多的区间数（同时重叠的最大数量）？比如会议室问题——最多同时需要多少个会议室？

> 你回答...（提示：会议室问题 / 会议室问题（最多重叠区间数）：①本质 → 找同一时间点 → 最多有多少个区间重叠 ②思路 → 扫描线 → 把所有区间拆成事件（开始事件 + 结束事件）→ 按时间排序 → 遍历 → 遇到开始 → count++ → 遇到结束 → count-- → 最大 count 就是答案 / 代码：
```java
public int minMeetingRooms(int[][] intervals) {
    if (intervals == null || intervals.length == 0) return 0;
    
    // 1. 拆成事件 → 开始 +1 / 结束 -1
    int n = intervals.length;
    int[] starts = new int[n];
    int[] ends = new int[n];
    for (int i = 0; i < n; i++) {
        starts[i] = intervals[i][0];
        ends[i] = intervals[i][1];
    }
    
    // 2. 分别排序
    Arrays.sort(starts);
    Arrays.sort(ends);
    
    // 3. 双指针扫描
    int rooms = 0;     // 当前会议室数
    int maxRooms = 0;   // 最大值
    int s = 0, e = 0;   // starts 和 ends 的指针
    while (s < n) {
        if (starts[s] < ends[e]) {
            rooms++;  // 一个会议开始 → 需要一个房间
            s++;
        } else {
            rooms--;  // 一个会议结束 → 释放一个房间
            e++;
        }
        maxRooms = Math.max(maxRooms, rooms);
    }
    return maxRooms;
}
```
/ 为什么这样做对：①starts 和 ends 分别排序 → 按时间顺序遍历所有事件 ②`starts[s] < ends[e]` → 有一个会议在当前最早结束的会议结束之前开始 → 需要新房间 → rooms++ ③否则 → 有一个会议结束了 → 释放房间 → rooms-- ④不需要处理同时开始和结束 → 如果 starts[s] == ends[e] → 先释放（else 分支）→ 不需要额外房间 → 因为结束的释放了 → 开始的可以用这个房间 / 应用场景：①会议室分配 → 最多需要多少个会议室 ②并发控制 → 同时有多少个事务在执行 → 决定资源池大小 ③区间调度 → 最大重叠数 = 资源峰值 / 面试重点：扫描线=拆事件(开始+1/结束-1)→按时间排序→遍历遇开始count++遇结束count--→最大count=答案 → 双指针=starts和ends分别排序→starts[s]<ends[e]则rooms++→否则rooms-- → 应用=会议室/并发控制/资源峰值）

---

# 二面（30分钟）

## 话题九：普惠金融与个人养老金业务（10分钟）

**面试官：你在银行做了这么多年，了解普惠金融吗？邮储的普惠金融和城商行有什么不同？个人养老金（第三支柱）你了解吗？**

> 你回答...

**追问1：** 先说说普惠金融是什么。为什么国有大行要做普惠金融？

> 你回答...（提示：普惠金融概念 / 定义：①普惠金融 = 以可负担的成本 → 为社会各阶层和群体提供适当、有效的金融服务 → 特别是农民、城镇低收入人群、小微企业、残疾人、老年人等"金融弱势群体"②核心 → "普"（覆盖面广）+ "惠"（成本可负担）→ 不是慈善 → 是可持续的商业金融 / 为什么国有大行要做：①政策要求 → "两增两控" → 增加小微贷款 → 国有大行有普惠金融考核指标 → 贷款增速不低于各项贷款平均增速 ②社会责任 → 国有大行 → 服务实体经济 → 支持小微企业 → 促进就业 ③邮储优势 → 4 万个网点 → 覆盖全国 99% 的县乡 → 天然下沉到农村 → 做普惠金融有网点优势 / 邮储 vs 城商行做普惠：
| 维度 | 邮储银行 | 城商行 |
|------|---------|-------|
| 网点 | 4万+，覆盖县乡 | 集中在城市 |
| 客群 | 农民/小微企业/县域 | 城市小微/个体 |
| 风控 | 数据多+大行信评 | 熟人社会+本地化 |
| 资金成本 | 低（储蓄存款多） | 中 |
| 贷款利率 | 相对低 | 相对高 |
①邮储 → 网点多 → 覆盖农村 → 但单个网点效率低 → 管理成本高 → 需要数字化降本 ②城商行 → 本地化 → 熟人社会 → 信息不对称少 → 但规模小 / 面试重点：普惠金融=可负担成本为弱势群体(农民/小微/低收入)提供金融服务→普+惠→不是慈善是可持续商业 → 国有大行做=政策要求(两增两控)+社会责任+邮储4万网点天然下沉 → 邮储vs城商行=网点多覆盖县乡vs城市集中/资金成本低vs中/但管理成本高需数字化降本）

**追问2：** 个人养老金（第三支柱）是什么？和社保（第一支柱）有什么区别？技术上需要设计什么系统？

> 你回答...（提示：个人养老金 / 三支柱体系：①第一支柱 → 基本养老保险 → 政府主导 → 强制缴纳 → 社保 → 覆盖广但替代率低（约40-50%）→ 退休后可能不够用 ②第二支柱 → 企业年金/职业年金 → 企业主导 → 自愿 → 只有部分企业有 ③第三支柱 → 个人养老金 → 个人自愿 → 自己缴费 → 自己投资 → 自己领 → 补充第一支柱 / 个人养老金核心规则：①每人每年最多缴 12000 元 → 税前扣除 → 降低当期税负 ②封闭运行 → 只有退休/完全丧失劳动能力/出国定居才能取 ③自主投资 → 选储蓄/理财/基金/保险产品 → 自负盈亏 ④领取 → 退休后按月/分次/一次性领取 → 按 3% 税率缴个税 / 和社保区别：
| 维度 | 第一支柱(社保) | 第三支柱(个人养老金) |
|------|--------------|-------------------|
| 缴费 | 强制(单位+个人) | 自愿(个人) |
| 管理 | 政府 | 个人自主 |
| 投资 | 统一管理 | 自选产品 |
| 收益 | 保底 | 自负盈亏 |
| 领取 | 按月发 | 按月/分次/一次 |
| 税率 | 不交税(已扣) | 领取时3% |
/ 需要设计的系统：①账户系统 → 开立个人养老金账户（唯一性 → 一个人一个账户 → 跨行只能选一家）②缴费系统 → 每年 12000 额度控制 → 税前扣除凭证 → 个税 APP 同步 ③投资系统 → 对接产品平台（储蓄/理财/基金/保险）→ 交易 → 份额管理 → 净值更新 ④领取系统 → 条件校验（退休/丧失能力/出国）→ 按月/分次/一次性 → 3% 扣税 ⑤税务系统 → 缴费时生成税前扣除凭证 → 领取时代扣 3% 个税 → 汇算清缴 / 面试重点：第三支柱=个人自愿缴费(每年12000)→税前扣除→封闭运行→自主投资→退休领取3%税率 → 和社保区别=自愿vs强制/自选产品vs统一管理/自负盈亏vs保底 → 系统=账户(唯一性)+缴费(额度控制+税前扣除凭证)+投资(对接产品+份额+净值)+领取(条件校验+3%扣税)+税务(凭证+代扣+汇算)）

**追问3：** 个人养老金账户的资金安全怎么保障？如果投资亏损了怎么办？

> 你回答...（提示：养老金资金安全 / 资金安全保障：①资金隔离 → 个人养老金资金 → 独立账户 → 和银行自有资金隔离 → 银行破产不影响 → 存保制度保障 ②产品准入 → 不是所有金融产品都能进 → 监管准入 → 只有低风险产品（特定储蓄/理财/养老基金 Y 份额/养老保险）→ 控制风险 ③投资限制 → 养老基金 Y 份额 → 专门为养老金设计 → 费率低（管理费打折）→ 持仓相对稳健 ④信息披露 → 定期公布净值 → 透明 ⑤风险提示 → 开户时风险测评 → 只能买匹配风险等级的产品 / 投资亏损处理：①个人养老金 ≠ 保本 → 自己选产品 → 自负盈亏 → 亏损自己承担 ②但产品准入控制风险 → 只有中低风险产品 → 不会出现大幅亏损 ③长期投资 → 养老金是长期资金 → 20-30 年 → 短期波动 → 长期大概率正收益 ④默认投资 → 如果用户不主动选 → 默认投目标日期基金 → 按退休年份自动调整股债比例 → 越接近退休越保守 ⑤风险等级匹配 → 开户风险测评 → 保守型 → 只能买储蓄 → 不能买基金 / 面试重点：资金安全=独立账户隔离(银行破产不影响)+存保制度+产品准入(只低风险)+投资限制(Y份额费率低)+信息披露透明+风险提示 → 亏损=不保本自负盈亏→但产品准入控制(中低风险)→长期投资大概率正收益→默认投目标日期基金(按退休自动调仓)→风险等级匹配(保守型只能买储蓄)）

---

## 话题十：核心设计题 - 个人养老金账户管理系统（20分钟）

**面试官：邮储要做一个个人养老金账户管理系统。支持千万级用户开户、缴费、投资、领取全流程。每年缴费期集中爆发（年底前抢着缴满 12000），怎么设计？**

> 你回答...

**追问1：** 先说说账户开立的流程。怎么保证一个人只能开一个养老金账户？

> 你回答...（提示：账户开立设计 / 开户流程：①用户身份核验 → 实名认证 → 人脸识别 + 身份证 OCR → 调用公安联网核验 ②唯一性校验 → 一个人只能在一个银行开一个养老金账户 → 需要跨行校验 → 调用人社部"个人养老金信息平台"API → 检查是否已开户 ③如果未开户 → 开立账户 → 生成养老金账号 → 同步到人社部平台 ④绑定银行卡 → 用于缴费和领取 ⑤风险测评 → 评估风险等级 → 决定可买产品范围 / 唯一性保障：①人社部平台 → 一个人一个养老金账户 → 开户前查 → 已开户 → 拒绝 ②银行内 → DB 唯一约束 → `UNIQUE KEY uk_id_card (id_card_no)` → 防并发重复开户 ③分布式锁 → 开户时 → `Redis SETNX pension:lock:{idCard}` → 防同一用户并发提交 ④异步 → 人社部平台校验 → 如果平台慢 → 先本地开户（pending 状态）→ 异步校验 → 失败 → 关户 → 退款 / 面试重点：开户=身份核验(人脸+公安联网)+唯一性校验(人社部平台跨行查)+未开户则开立+绑定银行卡+风险测评 → 唯一性=人社部平台跨行校验+DB唯一约束(id_card)+Redis分布式锁防并发 → 异步=人社部平台慢→先pending开户→异步校验→失败关户退款）

**追问2：** 缴费期集中爆发怎么扛？年底前一个月大量用户集中缴费，怎么设计高并发？

> 你回答...（提示：缴费高并发设计 / 场景分析：①每年 12000 额度 → 很多人年底前抢着缴满（个税扣除）→ 12 月集中爆发 ②预估 → 千万级用户 → 集中在 11-12 月 → QPS 可能万级 ③核心操作 → 扣银行卡 → 加养老金账户 → 生成税前扣除凭证 / 高并发设计：①异步化 → 缴费请求 → 先入 MQ → 异步处理 → 用户先收到"处理中" → 后台扣款+入账 → 完成通知 ②缓存额度 → 用户额度（已缴金额）缓存 Redis → 查询走缓存 → 不走 DB ③扣减额度 → Redis Lua 原子扣减剩余额度 → 防超限 ④分库分表 → 按用户 ID 分库 → 分散写压力 ⑤限流 → 缴费接口限流 → 保护 DB ⑥对账 → 每日对账 → 银行卡扣款记录 vs 养老金入账记录 / 流程设计：
```
用户发起缴费
    ↓
网关限流（Token Bucket）
    ↓
校验额度（Redis Lua：已缴+本次 <= 12000）
    ↓
MQ 发送缴费消息（异步）
    ↓ 返回"处理中"
消费者收到消息
    ↓
调用银行卡扣款（银行渠道）
    ↓
养老金账户入账（DB事务）
    ↓
更新缓存额度（Redis DECRBY）
    ↓
生成税前扣除凭证
    ↓
通知用户（短信/APP推送）
```
/ 扣款失败处理：①银行卡余额不足 → 扣款失败 → MQ 重试 → 重试 3 次仍失败 → 标记失败 → 通知用户 ②养老金账户入账失败（DB 异常）→ 扣款已成功 → 需要退款 → 事务+对账发现 → 退款 ③幂等 → 每笔缴费有唯一流水号 → SETNX 防重复 → 重试不会重复入账 / 面试重点：高并发=异步化(MQ先入队→返回处理中→后台扣款入账)→缓存额度(Redis查不走DB)→Lua原子扣减防超限→分库分表分散写→限流保护DB→每日对账 → 流程=限流→校验额度(Redis Lua)→MQ→消费者扣款→入账→更新缓存→生成凭证→通知 → 失败=余额不足重试3次→入账失败退款→幂等唯一流水号防重复）

**追问3：** 投资产品怎么对接？用户买了基金，份额和净值怎么管理？

> 你回答...（提示：投资系统设计 / 产品对接：①产品类型 → 养老储蓄（银行存款类）/ 养老理财（理财产品）/ 养老基金（基金 Y 份额）/ 养老保险（保险产品）②对接方式 → 每类产品对接不同的系统 → 基金对接基金公司 TA 系统 → 理财对接理财登记中心 → 保险对接保险公司 ③统一接口 → Adapter 模式 → 统一的产品交易接口（申购/赎回/查询份额/查询净值）→ 适配不同产品系统 / 份额管理：①用户申购 → 调用产品系统 → 确认份额 → 记录到养老金账户 ②净值更新 → 每日更新 → 基金净值由基金公司发布 → 批量拉取 → 更新缓存 ③持仓查询 → 汇总用户所有产品的份额 × 净值 → 总资产 ④收益计算 → 每日收益 = 持仓份额 × (今日净值 - 昨日净值) / 昨日净值 / 数据流：
```
用户申购基金
    ↓
养老金系统 → 调用基金TA系统（申购请求）
    ↓
基金TA系统确认 → 返回确认份额
    ↓
养老金系统记录份额（DB）
    ↓
每日批量拉取基金净值 → 更新Redis缓存
    ↓
用户查询持仓 → 份额 × 净值 → 总资产
```
/ 净值更新策略：①定时拉取 → 每天晚上基金公司发布净值后 → 批量拉取 → 更新缓存 ②推送 → 基金公司主动推送 → 实时性更好 ③缓存 → Redis 缓存最新净值 → `fund:nav:{fundCode}` → TTL 1 天 ④收益计算 → T+1 → 基金 T 日确认 → T+1 日开始算收益 → T+1 晚上净值出来后算 / 面试重点：产品=4类(储蓄/理财/基金Y份额/保险)→Adapter统一接口(申购/赎回/份额/净值)适配不同系统 → 份额=申购调TA确认份额→记录DB→每日拉净值更新Redis→持仓=份额×净值总资产→收益=(今净值-昨净值)/昨净值×份额 → 净值更新=每日批量拉取/基金公司推送→Redis缓存TTL1天→T+1确认→T+1算收益）

**追问4：** 领取阶段怎么设计？退休后按月领取，怎么保证每月按时发？如果账户里还有投资份额怎么办？

> 你回答...（提示：领取系统设计 / 领取条件校验：①达到法定退休年龄 → 人社部数据校验 ②完全丧失劳动能力 → 需要证明 ③出国定居 → 需要证明 ④领取方式 → 按月 / 分次 / 一次性 / 按月领取设计（类似年金）：①用户选择按月领取 → 确定每月领取金额 → 系统每月固定日扣款 ②如果账户有现金 → 直接扣现金 → 转入绑定银行卡 ③如果现金不够 → 需要赎回投资份额 → 调用产品系统赎回 → T+1 资金到账 → 再转银行卡 ④税 → 每次领取按 3% 税率代扣个税 → 扣税后到账 ⑤月度跑批 → 每月 15 号 → 自动执行领取 → 扣款/赎回/扣税/转账/通知 / 份额处理：①如果用户选择一次性领取 → 全部赎回所有投资份额 → 基金 T+1 赎回 → 到账后一次性转出 ②如果按月领取 → 每月需要计算可领取金额 → 现金 + 需要赎回的份额 → 赎回一部分 → 剩余继续投资 ③赎回策略 → 按比例赎回 → 或者先赎回低风险产品 → 保留高风险产品继续增值 ④类似"年金" → 每月领取 = 账户总资产 / 预期月数 → 或者固定金额 → 不足时赎回 / 完整流程：
```
每月 15 号 → 月度跑批
    ↓
遍历需要领取的用户
    ↓
计算领取金额 → 用户设定的月领金额
    ↓
检查账户现金 → 够 → 直接转出
    ↓ 不够
赎回投资份额 → 调用TA系统赎回
    ↓ T+1 到账
计算个税 → 领取金额 × 3%
    ↓
转账到用户银行卡（领取金额 - 个税）
    ↓
通知用户
    ↓
更新账户余额 → 如果余额耗尽 → 标记"领取完毕"
```
/ 跑批设计：①千万级用户 → 不是所有都在领取 → 在领取的可能几十万 → 分批跑 → 每批 1000 人 → 多线程并行 ②幂等 → 每月每用户只领一次 → `pension:withdraw:{userId}:{month}` 唯一约束 → 防重复 ③失败重试 → 赎回失败 → 重试 → 3 次失败 → 告警 → 人工处理 ④对账 → 每月跑批后 → 对账 → 总扣款 = 总转出 + 总扣税 / 面试重点：领取=条件校验(退休/丧失能力/出国)→按月/分次/一次性 → 按月=月度跑批(15号)→现金够直接转→不够赎回份额T+1→扣3%税→转账→通知 → 份额=一次性全部赎回/按月按比例赎回部分→剩余继续投资 → 跑批=分批1000人并行+幂等(userId+month唯一)+失败重试3次+月度对账(总扣=总转+总税)）

**追问5：** 税务处理怎么设计？缴费时的税前扣除和领取时的 3% 代扣怎么实现？

> 你回答...（提示：税务系统设计 / 缴费时税前扣除：①缴费时 → 生成税前扣除凭证 → 用户可在个税 APP 申报扣除 → 降低当期应纳税所得额 ②凭证 → 包含：用户信息 / 缴费金额 / 缴费日期 / 凭证编号 / 银行信息 ③同步 → 银行 → 人社部平台 → 个税系统 → 用户在个税 APP 自动看到扣除额度 ④年度限额 → 每年 12000 → 超过 → 拒绝缴费 → 或超额部分不享受税前扣除 / 领取时代扣 3%：①每次领取 → 按领取金额 × 3% 代扣个税 ②代扣 → 银行代扣 → 转入国库 ③凭证 → 生成完税凭证 → 用户留存 ④年度汇算 → 用户年度个税汇算 → 个人养老金领取部分已扣 3% → 不再并入综合所得 → 单独计税 / 税务系统设计：
```
缴费流程：
  缴费入账 → 生成税前扣除凭证 → 推送人社部/税务系统
  → 用户个税APP自动显示可扣除额度

领取流程：
  领取金额 → 计算 3% 个税 → 代扣 → 转国库
  → 生成完税凭证 → 用户留存
  → 年度汇算：单独计税（3% 已扣，不再并入综合所得）
```
/ 税务对账：①银行代扣 → 和税务局对账 → 每月对 → 代扣金额 = 入国库金额 ②差异处理 → 多扣 → 退税 → 少扣 → 补扣 ③年度清算 → 每年初 → 上一年度所有缴费扣除凭证 → 汇总 → 推送税务系统 / 面试重点：缴费税前扣除=生成凭证(用户信息+金额+日期+编号)→推送人社部/税务→个税APP自动显示→年度12000限额 → 领取代扣3%=领取金额×3%代扣→转国库→完税凭证→年度汇算单独计税(不再并入综合所得) → 税务对账=银行代扣vs税务局每月对→差异退税/补扣→年度清算汇总推送）

**追问6：** 整个系统的高可用怎么设计？养老金涉及用户"养老钱"，不能出错。

> 你回答...（提示：高可用设计 / 核心原则——养老金是"养老钱"：①数据准确性 > 一切 → 不能多扣/少扣/丢失 ②资金安全 > 可用性 → 宁可拒绝服务 → 不能错误处理资金 ③可追溯 → 每笔操作有完整审计链 / 高可用分层：①接入层 → 网关 → 限流 + 鉴权 + 幂等 ②应用层 → 微服务多副本 → 无状态 → 横向扩展 ③数据层 → MySQL 主从 + 分库分表 → Redis 集群 → MQ 集群 ④外部系统 → 人社部平台 / 银行卡渠道 / 基金 TA → 熔断 + 重试 + 降级 / 资金安全保障：①双写校验 → 扣款和入账必须一致 → 不一致 → 冲正 ②每日对账 → 银行卡扣款 vs 养老金入账 vs 人社部平台记录 → 三方对平 ③幂等 → 每笔交易唯一流水号 → SETNX 防重复 ④事务 → 扣款+入账+生成凭证 → 一个 DB 事务 → 要么全成功要么全失败 ⑤补偿 → 如果部分失败 → 补偿机制 → 退款/补扣 / 容灾：①两地三中心 → 主中心 + 同城灾备 + 异地灾备 ②RTO < 5min / RPO = 0（数据零丢失）③定期演练 → 灾备切换演练 / 监控告警：①业务监控 → 开户数/缴费金额/投资金额/领取金额 → 异常告警 ②资金监控 → 每日对账差异 → 0 差异 → 有差异立即告警 ③技术监控 → RT/错误率/GC/连接池/慢SQL ④审计 → 每笔操作审计日志 → 不可篡改 → 存证 / 面试重点：养老金高可用=数据准确>一切+资金安全>可用性+可追溯 → 资金安全=双写校验(扣款入账一致→不一致冲正)+每日三方对账(银行卡vs养老金vs人社部)+幂等(唯一流水号SETNX)+事务(扣款+入账+凭证一个事务)+补偿(部分失败退款/补扣) → 容灾=两地三中心+RTO<5min+RPO=0+定期演练 → 监控=业务(开户/缴费/投资/领取)+资金(对账差异=0告警)+技术(RT/错误率/GC)+审计(不可篡改存证)）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| Spring Boot 启动流程（构造阶段推断/WebApplicationType/spring.factories加载/run()12步/自动配置/2.7改imports文件） | 能讲清 / 讲不全 / 不会★ | |
| Kafka Rebalance 深入（消费者组分区关系/触发条件/STW痛点/重复消费/Rebalance风暴/Cooperative增量Rebalance） | 能讲清 / 讲不全 / 不会★ | |
| WebSocket 原理（HTTP轮询局限/握手HTTP Upgrade/帧格式/心跳Ping-Pong/50万连接Netty架构） | 能讲清 / 讲不全 / 不会★ | |
| Java 泛型深入（类型擦除/伪泛型vs真泛型/PECS原则/桥接方法/运行时获取泛型TypeReference） | 能讲清 / 讲不全 / 不会★ | |
| MySQL Online DDL（COPY/INPLACE/INSTANT/pt-osc/GH-OST/MDL锁风险/安全措施） | 能讲清 / 讲不全 / 不会★ | |
| 分布式限流（单机算法/Redis+Lua ZSET滑动窗口/Token Server批量预取/多级限流Nginx→Gateway→Sentinel） | 能讲清 / 讲不全 / 不会★ | |
| JVM 字节码基础（.class结构/常量池/指令分类/invokevirtual vs invokeinterface/invokedynamic Lambda） | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（合并区间/排序+贪心/插入区间三段/会议室扫描线） | 能讲清 / 讲不全 / 不会★ | |
| 普惠金融与个人养老金（三支柱/个人养老金规则/资金安全/投资亏损） | 能讲清 / 讲不全 / 不会★ | |
| 个人养老金系统设计（开户唯一性/缴费高并发MQ异步/投资份额净值/领取月度跑批/税务代扣/高可用对账） | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **Spring Boot 启动**：构造阶段（推断应用类型/加载Initializer+Listener/推断主类）→ run() 12步（StopWatch→Listeners→Environment→Banner→创建ApplicationContext→prepareContext→**refreshContext核心**→afterRefresh→StartedEvent→Runner→ReadyEvent）→ 自动配置在 refresh 的 invokeBeanFactoryPostProcessors → AutoConfigurationImportSelector 读 spring.factories/imports → @Conditional 筛选 → 2.7+ 改用独立 imports 文件分离关注点
> 2. **Kafka Rebalance**：消费者组成员变化/分区变化/Topic变化/max.poll.interval超时 → 触发。痛点=**STW**（所有消费者停止消费几秒到几十分钟）+ 重复消费（处理了没commit）+ Rebalance风暴（崩溃→分配更多→处理慢→超时→又Rebalance）。**Cooperative Rebalance**（2.4+）= 增量只撤销变更的分区 → 其他继续消费 → STW大幅缩小 → StickyAssignor 尽量保持原有分配
> 3. **WebSocket**：HTTP不能服务端主动推送（轮询实时差/长轮询开销大/SSE单向）→ WebSocket全双工+持久连接+帧头2-14字节。握手=HTTP GET+Upgrade:websocket+Sec-WebSocket-Key → 101 Switching+Sec-WebSocket-Accept(Key+GUID→SHA1→Base64)。心跳=Ping/Pong帧30秒→60秒没收到断线。50万连接=Netty NIO(Boss 1-2 + Worker CPU×2)+Redis存userId→serverId映射找连接+广播发所有Server
> 4. **泛型深入**：类型擦除=编译检查→运行擦除→List<String>和List<Integer>运行时都是List → 伪泛型(兼容Java4)→问题=不能new T()/不能new T[]/不能用基本类型。**PECS**=Producer Extends(读用?extends)/Consumer Super(写用?super)。桥接方法=擦除后父类set(Object)和子类set(String)签名不匹配→编译器自动生成set(Object)强转调用set(String)。运行时获取泛型=匿名子类父类泛型存字节码Signature属性→getGenericSuperclass()
> 5. **Online DDL**：COPY(锁表)/INPLACE(原地不复制)/INSTANT(改元数据秒级8.0.12+)。能Online=加末尾列(INSTANT)/加索引(INPLACE)/改默认值。不能Online=加中间列/删列/改类型(必须COPY)。大表用**GH-OST**(影子表+binlog同步→无触发器开销→可暂停)或**pt-osc**(影子表+触发器→成熟但有开销)。风险=MDL锁(长事务持有→DDL阻塞→后续全阻塞→连接池耗尽)+主从延迟+空间不足
> 6. **分布式限流**：单机=计数器/滑动窗口/漏桶/令牌桶(Guava RateLimiter预计算)。Redis+Lua=ZSET(score=时间戳/value=请求ID)→Lua原子执行(移除窗口外→统计→未超限ZADD/超限拒绝)。瓶颈=Redis单点+网络延迟+Lua CPU。**Sentinel Token Server**=独立部署→Client TCP长连接→批量取令牌(50个)→本地消费→Server挂降级本地限流。**多级限流**=Nginx(IP级)→Gateway(API级)→Sentinel(接口级)→下游(超时+熔断)→就近拒绝
> 7. **字节码基础**：.class=魔数CAFEBABE+版本+**常量池**(字面量+符号引用/索引引用)+访问标志+类信息+字段表+方法表(含Code)+属性表(Signature泛型)。指令=加载存储(iload/istore)+算术(iadd/ladd int和long指令不同)+方法调用(invokevirtual虚方法vtable快/invokeinterface接口itable搜一次慢/invokespecial构造private/invokedynamic Lambda动态)。**invokedynamic**=运行时BootstrapMethods引导方法确定调用→Lambda不生成匿名内部类→LambdaMetafactory运行时动态生成→JVM缓存只生成一次
> 8. **合并区间**：排序+贪心→排序后和末尾比较→重叠(start<=end)合并end=max→不重叠加入。插入区间=三段(左边不重叠直接加/重叠合并/右边不重叠直接加)。会议室=扫描线(拆事件+1/-1→排序→遇开始count++遇结束count--→最大count)
> 9. **个人养老金**：第三支柱=个人自愿缴费(每年12000)→税前扣除→封闭运行→自主投资(储蓄/理财/基金Y份额/保险)→退休领取3%税率。资金安全=独立账户隔离+产品准入只低风险+长期投资+默认目标日期基金。系统=账户(唯一性人社部跨行校验)+缴费(MQ异步+Redis Lua额度控制+税前扣除凭证)+投资(Adapter统一接口+份额+净值)+领取(月度跑批+赎回+3%代扣)+税务(代扣转国库+年度汇算单独计税)
> 10. **养老金系统设计**：高并发缴费=MQ异步化+Redis缓存额度+Lua原子扣减+分库分表+限流+每日对账。投资=Adapter对接4类产品TA系统+每日拉净值更新Redis+T+1确认。领取=月度跑批(15号)→现金够直接转→不够赎回份额T+1→扣3%税→转账→通知。高可用=资金准确>一切+双写校验+三方对账(银行卡vs养老金vs人社部)+幂等+事务+补偿+两地三中心RPO=0+审计不可篡改
