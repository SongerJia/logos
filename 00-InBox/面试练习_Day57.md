# 面试模拟 - Day 57

> 日期：2026-07-27（周一） | 模拟岗位：微众银行（杭州研发中心）- 分布式核心系统部 - Java开发工程师
> 建议时长：85分钟（一面55分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day57，"查漏补缺"阶段第六周。模拟微众银行杭州研发中心——国内首家数字银行，无实体网点，全线上运营。微众面试特点：技术栈非常前沿（JDK 17/21、Spring Boot 3、云原生K8s全面容器化）、分布式核心系统设计能力要求高、追问"你关注新技术吗"考察技术敏感度、系统设计题偏向分布式银行核心场景。今天引入 Java 21 虚拟线程、Spring Boot 3 / Spring 6 新特性、Redis 7.0 新特性、MySQL 组提交深入、分布式链路追踪 Trace/Span 模型 5 个全新话题——都是高频前沿考点但之前没有作为独立话题系统考过的内容。

---

# 一面（55分钟）

## 话题一：Java 21 虚拟线程（Virtual Thread / Project Loom）（12分钟）

**面试官：微众目前在试点 JDK 21 的虚拟线程。你了解虚拟线程吗？它和传统平台线程有什么区别？为什么 JVM 领域这么关注它？**

> 你回答...

**追问1：** 先说说传统线程有什么问题。为什么 Java 一个线程要映射一个 OS 线程？这带来了什么瓶颈？

> 你回答...（提示：传统线程的问题 / 平台线程（Platform Thread / OS Thread）：①JDK 21 之前 → Java 的 `Thread` 就是平台线程 → 1:1 映射到 OS 线程 ②创建一个 Java 线程 → JVM 调用 `pthread_create`（Linux）→ OS 分配一个内核线程 → 分配栈空间（默认 1MB）→ 调度由 OS 内核管理 ③问题一：内存开销大 → 1 个线程 = 1MB 栈 → 1 万个线程 = 10GB 内存 → 4 万个线程 = 40GB → 机器扛不住 ④问题二：上下文切换开销 → OS 线程切换 = 保存/恢复寄存器 + 切换内核栈 + TLB 刷新 → 微秒级 → 线程多了切换频繁 → CPU 浪费在切换而非执行 ⑤问题三：IO 阻塞浪费 → 线程在 `socket.read()` 时阻塞 → 整个 OS 线程被挂起 → 如果一个请求一个线程 → 1000 个请求等 DB → 1000 个线程都在 BLOCKED → 没在干活但占着内存 ⑥这就是为什么传统 Java Web 容器用线程池（Tomcat 200 线程）→ 而不是每请求一线程 → 池化复用减少开销 ⑦但池化有上限 → 200 线程 → 如果 200 个请求都在等 DB（每个 100ms）→ 第 201 个请求排队 → 高并发就慢了 / 为什么传统 Java 用 BIO 线程模型：①历史原因 → Java 1.0 的 `Thread` 就映射 OS 线程 → 当时并发不高 → 够用 ②简单 → 开发者写同步代码（`socket.read()` 阻塞等）→ 直观 → 不用回调 ③但要高并发 → 必须减少线程数 → 引入 NIO/Netty/Reactor → 异步回调 → 代码复杂 → 虽然能用更少线程处理更多连接 → 但"回调地狱"可读性差 ④CompletableFuture → 链式调用 → 比回调好一点 → 但还是异步思维 → 调试困难（栈信息丢失）→ 这就是"同步代码的易用性 vs 异步代码的性能"矛盾 / 面试重点：传统线程=1:1映射OS线程→1万线程=10GB内存扛不住→上下文切换微秒级→IO阻塞线程挂起浪费→线程池200上限→高并发排队 → 异步回调复杂但性能好→这就是矛盾根源）

**追问2：** 虚拟线程是怎么解决这个问题的？它的底层原理是什么？

> 你回答...（提示：虚拟线程原理 / 虚拟线程（Virtual Thread / Project Loom / JEP 444 JDK 21 GA）：①核心思想 → 多个虚拟线程映射到少量平台线程（M:N 模型）→ 虚拟线程由 JVM 调度 → 不依赖 OS ②虚拟线程的栈在堆上（不是 OS 栈）→ 用 continuance（续体）→ 遇到 IO 阻塞 → JVM 把虚拟线程的执行状态（栈帧）→ 暂存到堆上 → 释放载体线程（carrier thread = 平台线程）→ 载体线程去执行下一个虚拟线程 ③IO 结束 → JVM 恢复虚拟线程的栈帧 → 重新 mount 到载体线程 → 继续执行 ④整个过程 → 对开发者透明 → 写的代码还是同步的 `socket.read()` → 但 JVM 内部不阻塞载体线程 → 而是 unmount → 让载体线程去干别的 → read 返回后再 mount 回来 / 和传统线程对比：
| | 平台线程 | 虚拟线程 |
|---|---|---|
| 映射 | 1:1 OS 线程 | M:N（多个虚拟线程映射少量载体线程）|
| 栈空间 | OS 栈 1MB 固定 | 堆上动态（初始几百B → 按需扩展）|
| 创建成本 | 微秒级（pthread_create）| 纳秒级（Java 对象）|
| 内存 | 1MB/线程 → 1万=10GB | 几KB/线程 → 100万=几GB |
| 上下文切换 | OS 切换 ~1μs | JVM 切换 ~100ns |
| IO 阻塞 | 线程 BLOCKED 浪费 | unmount → 载体线程复用 |
| 代码风格 | 同步 | 同步（透明！）|
/ 使用方式：
```java
// 方式一：直接创建
Thread.startVirtualThread(() -> {
    // 这就是虚拟线程
    String result = httpClient.get(url);  // 阻塞调用 → 但不阻塞载体线程
    System.out.println(result);
});

// 方式二：线程池（每个任务一个虚拟线程）
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    // 提交 10000 个任务 → 创建 10000 个虚拟线程 → 但只用几十个载体线程
    Future<String> future = executor.submit(() -> {
        return db.query("SELECT ...");  // 同步阻塞 → 透明异步
    });
}

// 方式三：虚拟线程 + ThreadLocal
Thread.Builder.ofVirtual().name("vt-").start(() -> { ... });
```
/ 为什么"同步写法、异步性能"：①关键 → `socket.read()` 在虚拟线程中 → JVM 检测到这是阻塞 IO → 把虚拟线程 unmount → 载体线程执行其他虚拟线程 → read 完成后 mount 回来 ②开发者写的同步代码 → 不需要回调/thenApply/thenCompose → 但运行时性能接近异步 ③这就是"协程"思路（Go 的 goroutine / Kotlin 协程 / Python asyncio）→ Java 终于在 JDK 21 官方支持 / 面试重点：虚拟线程=M:N映射→虚拟线程栈在堆上→IO阻塞时JVM unmount虚拟线程释放载体线程→IO完成后mount回来→开发者写同步代码但运行时接近异步性能→创建成本纳秒级→100万虚拟线程只需几GB→载体线程由ForkJoinPool管理）

**追问3：** 虚拟线程这么好，有什么限制？是不是所有场景都适合用虚拟线程？有没有"坑"？

> 你回答...（提示：虚拟线程的限制和坑 / 限制一：CPU 密集型不适合 ①虚拟线程优势在 IO 阻塞时 unmount → 释放载体线程 ②如果任务是 CPU 密集计算（加密/排序/计算）→ 不阻塞 IO → 不会 unmount → 虚拟线程一直占着载体线程 → 100 个 CPU 密集虚拟线程 → 只用几个载体线程 → 排队 → 不如直接用平台线程 ③虚拟线程适合 IO 密集型（HTTP 调用 / DB 查询 / 文件读写）→ 不适合 CPU 密集型 ④CPU 密集 → 用平台线程 + ForkJoinPool / 限制二：synchronized 阻塞载体线程 ①虚拟线程在 `synchronized` 块内 → 如果 IO 阻塞 → JVM 无法 unmount（因为 `synchronized` 用 OS monitor）→ 载体线程被阻塞 → 和传统线程一样 ②JDK 21 的虚拟线程在 `synchronized` 块内 IO 阻塞 → 会 pin 载体线程（固定）→ 不能 unmount → 性能退化为传统线程 ③JDK 24 修复 → JEP 491 → synchronized 也能 unmount（但 JDK 21 还有这个限制）→ 替代 → 用 `ReentrantLock`（不会 pin）/ 限制三：ThreadLocal 滥用 ①虚拟线程可以创建几百万个 → 如果每个都有 ThreadLocal → ThreadLocal 占用大量内存 ②`ScopedValue`（JEP 446 预览）→ 替代 ThreadLocal → 不可变 + 自动清理 → 适合虚拟线程 ③建议 → 虚拟线程中谨慎用 ThreadLocal → 避免 `ThreadLocal<BigObject>` → 用参数传递 / 限制四：第三方库兼容性 ①第三方库在虚拟线程中 `synchronized` + IO → pin 载体线程 → 如 JDBC 驱动（有些用 synchronized）→ 需要确认驱动版本支持虚拟线程 ②MySQL JDBC 8.0.37+ 支持 ③建议 → 生产用前测试所有依赖 / 实际应用场景：①Web 服务器 → Tomcat / Jetty 配置使用虚拟线程 → `spring.threads.virtual.enabled=true`（Spring Boot 3.2+）→ 每个请求一个虚拟线程 → 不再受 200 线程池限制 → 轻松支持几万并发 ②微服务调用 → Feign + 虚拟线程 → 每个 HTTP 调用一个虚拟线程 → 不阻塞线程池 → 削峰能力大幅提升 ③不适合 → 批处理大计算 / 加密 / 排序 / 视频处理 → 这些用平台线程 / 和 Reactive 编程对比：①Reactive（WebFlux）→ 异步回调 + 事件循环 → 性能好 → 但代码复杂 → 调试困难 → Mono/Flux 链式 → 学习曲线陡 ②虚拟线程 → 同步代码 → 性能接近 Reactive → 调试容易（栈完整）→ 学习成本低 ③未来趋势 → 虚拟线程可能替代 Reactive → Spring Boot 3.2+ 已支持虚拟线程 → WebFlux 的优势在缩小 / 面试重点：虚拟线程限制=CPU密集不适合（不unmount）/synchronized会pin载体线程（JDK21限制/JDK24修复→用ReentrantLock替代）/ThreadLocal滥用内存（用ScopedValue替代）/第三方库synchronized+IO要测试 → 适合IO密集Web请求/微服务调用 → 不适合CPU密集计算 → 可能替代Reactive（同步代码+接近异步性能+调试容易））

---

## 话题二：Spring Boot 3 / Spring 6 新特性（11分钟）

**面试官：你用 Spring Boot 3 吗？和 2.x 有什么区别？Spring Boot 3 最重要的变化是什么？**

> 你回答...

**追问1：** 先说说 Spring Boot 3 最核心的变化——基线升级。为什么要求 JDK 17？Java 模块化（JPMS）带来了什么影响？

> 你回答...（提示：Spring Boot 3 / Spring 6 核心变化 / 基线升级：①Spring Boot 3 → 要求 JDK 17+（Spring 6 基线）→ Spring Boot 2.x 支持 JDK 8/11 ②Jakarta EE 9+ → `javax.*` → `jakarta.*` → 包名变更 → 所有 import 要改 `javax.servlet` → `jakarta.servlet` / `javax.persistence` → `jakarta.persistence` / `javax.validation` → `jakarta.validation` ③原因 → Oracle 把 Java EE 捐给 Eclipse → 改名 Jakarta EE → 但 `javax.*` 包名 Oracle 还拥有商标权 → 不能继续用 → 必须改 `jakarta.*` → 迁移成本：改 import / 升级依赖 ④这是"破坏性变更"（breaking change）→ 但只改包名 → API 基本不变 → IDE 批量替换即可 / 为什么 JDK 17：①Spring 6 大量用 Java 17 新特性 → Records / Switch 模式匹配 / Sealed Classes / Text Block ②JDK 17 是 LTS → 长期支持 → 生产稳定 ③JDK 8 → 11 → 17 → 21 是 LTS 版本链 → Spring Boot 3 选择 17 而非 21 → 因为 3.0 发布时 21 还没 GA → Spring Boot 3.2+ 开始支持 21 / Jakarta EE 迁移影响：①所有用 `javax.*` 的代码 → 改 `jakarta.*` ②第三方库 → 要升到支持 Jakarta 的版本 → Hibernate 6 / MyBatis 3.x / Tomcat 10 ③不升 → 编译报错 → Spring Boot 3 用不了老的 javax 依赖 / 面试重点：Spring Boot 3=JDK17基线+Jakarta包名变更(javax→jakarta)+大量用Java17新特性 → 迁移成本=改import+升级依赖 → JDK17是LTS稳定版）

**追问2：** Spring Boot 3 的原生镜像支持（GraalVM Native Image）你了解吗？它解决了什么问题？有什么代价？

> 你回答...（提示：GraalVM Native Image / 传统 JVM 启动慢的问题：①JVM 启动 → 加载 class → 解释执行 → JIT 编译热点代码 → 需要时间"预热"②Spring Boot 启动 → 扫描 Bean → 依赖注入 → 初始化 → 加上 JVM 预热 → 启动 2-10 秒 ③问题 → 云原生时代 → K8s Pod 频繁扩缩容 → 实例创建就要能用 → 启动 5 秒 → K8s 认为健康检查失败 → 重启 → 恶性循环 ④Serverless → 请求来才启动 → 冷启动 5 秒 → 用户体验差 ⑤Go / Rust 编译成原生二进制 → 启动毫秒级 → Java 在云原生场景劣势 / GraalVM Native Image：①GraalVM → Oracle 开源的高性能 JDK 发行版 ②Native Image → AOT（Ahead-Of-Time）编译 → 把 Java 字节码 → 编译成原生机器码 → 生成单一可执行文件（不需要 JVM）③启动 → 直接运行机器码 → 不需要 class 加载 / JIT 预热 → 毫秒级启动 ④内存 → 不需要 JVM 运行时 → 内存占用大幅降低 → 传统 Spring Boot 200MB+ → Native Image 50MB ⑤效果 → 启动 0.1 秒（传统 3 秒）→ 内存 50MB（传统 300MB）→ 接近 Go/Rust / Spring Boot 3 对 Native Image 的支持：①Spring Boot 3 + Spring Native → 官方支持 Native Image ②`spring-boot-maven-plugin` → `process-aot` goal → 生成 AOT 配置 → GraalVM 编译 ③命令 → `mvn native:compile -Pnative` → 生成 native 二进制 ④Spring AOT → 启动时不再做大量反射（反射不能 AOT 优化）→ 改为编译时生成 → Bean 定义 / 配置类 → 编译时确定 → 运行时不需要扫描 / Native Image 的代价（限制）：①编译慢 → AOT 编译 → 要分析整个应用 → 编译 2-5 分钟（传统 mvn package 30 秒）②闭世界假设（Closed World）→ 编译时必须知道所有类 → 不能运行时动态加载类 / 动态代理 → Spring 的 CGLIB 代理 → AOT 要预先生成 ③反射要配置 → 反射不在编译时可见 → 需要配置文件（reflect-config.json）→ Spring Boot 3 AOT 自动生成大部分配置 → 但第三方库可能需要手动配 ④JIT 优化没了 → Native Image 没有 JIT → 不能根据运行时热点优化 → 长期运行性能可能不如 JIT → 适合短生命周期（Serverless / K8s Pod）→ 不适合长期运行的服务 ⑤调试困难 → 没有 JVM → 不能 jstack / arthas / jmap / GC 日志 → 可观测性差 ⑥动态字节码 → CGLIB / ByteBuddy → 可能不兼容 → 要用 GraalVM 兼容版本 / 适用场景：①Serverless / FaaS → 冷启动毫秒级 → 请求处理完销毁 → 优势最大 ②K8s Pod 频繁扩缩容 → 快速启动 → 水平扩展快 ③CLI 工具 → 一次运行 → 不需要 JVM 预热 ④不适合 → 长期运行的核心服务（JIT 更优）→ 数据库连接池预热 / JIT 优化后的吞吐量 / 运行时监控 / 面试重点：Native Image=AOT编译→Java字节码→原生机器码→不需要JVM→毫秒级启动+50MB内存 → 代价=编译慢(2-5min)/闭世界(不能动态加载)/反射要配置/无JIT(长期运行不如JIT)/调试困难(无jstack/arthas) → 适合Serverless/K8s扩缩容 → 不适合长期运行核心服务)

**追问3：** Spring Boot 3 还有其他重要新特性吗？比如对可观测性（Observability）的支持？

> 你回答...（提示：Spring Boot 3 其他新特性 / 可观测性（Observability）：①Spring Boot 3 内置 Micrometer → 统一可观测性 API → Metrics（指标）+ Tracing（链路追踪）+ Logging（日志）三合一 ②以前 → Spring Boot Actuator（Metrics）+ Zipkin/SkyWalking（Tracing）+ ELK（Logging）→ 三套独立的系统 ③Spring Boot 3 → Micrometer Observation API → 统一接口 → 一次埋点 → 同时输出 Metrics + Tracing + Logs ④自动埋点 → Spring Boot 3 自动给 HTTP 请求 / Feign 调用 / DB 查询加埋点 → 不需要手动加 ⑤对接 → Micrometer → Prometheus（Metrics）+ Tempo/Zipkin（Tracing）+ Loki/ELK（Logs）/ 其他重要变化：①`@RestControllerAdvice` 异常处理增强 → `ProblemDetail`（RFC 7807 标准）→ 统一错误响应格式 ②`@SpringBootApplication` 默认包含 `@Configuration` + `@EnableAutoConfiguration` + `@ComponentScan` → Spring Boot 3 更灵活的扫描配置 ③HTTP Interface → `@HttpExchange` 声明式 HTTP 客户端 → 类似 Feign 但 Spring 原生 → 不需要 OpenFeign 依赖 ④WebClient → 响应式 HTTP 客户端 → Spring Boot 3 推荐 WebClient + 虚拟线程替代 RestTemplate ⑤Java Records 支持 → DTO 用 Record → 简洁 → Spring Boot 3 完美支持 Record 作为 `@RequestBody` / `@ConfigurationProperties` / 面试重点：Spring Boot 3=Micrometer统一可观测性(Metrics+Tracing+Logs三合一)+ProblemDetail标准错误+@HttpExchange声明式HTTP+WebClient+Record支持 → 基线JDK17+Jakarta+Native Image+Observability是四大核心变化）

---

## 话题三：Redis 7.0 新特性（11分钟）

**面试官：Redis 7 你了解吗？7.0 有什么重要变化？和 6.0 有什么区别？**

> 你回答...

**追问1：** 先说说 Redis 6.0 的多线程 IO 是怎么回事。之前 Redis 不是单线程吗？为什么 6.0 要引入多线程？

> 你回答...（提示：Redis 多线程 IO / Redis 单线程模型回顾：①Redis 6.0 之前 → 纯单线程 → 所有命令执行在一个线程里 → 串行 ②单线程为什么也快 → 内存操作 + IO 多路复用（epoll）+ 简单数据结构 + 避免上下文切换 + 加锁 ③单线程的瓶颈 → 不在 CPU → 在 IO → 大量连接的 read/write → 网络读写成为瓶颈 → 单线程读 socket / 写 socket → 如果 10 万连接 → 光 IO 就忙不过来 → 命令执行其实很快（纳秒级）→ 但 read()/write() 是系统调用 → 10 万个连接 → 单线程串行读写 → 吞吐量上不去 / Redis 6.0 多线程 IO：①核心思路 → 命令执行还是单线程（保证线程安全 + 简单）→ 但网络读写（read socket / write socket）用多线程 ②流程 → IO 线程池（默认不开启）→ 主线程 epoll_wait → 发现有数据 → 分发给 IO 线程 read → IO 线程读完后 → 主线程串行执行命令（单线程保证安全）→ 执行完 → IO 线程 write 回客户端 ③即 → read/write 多线程 → 命令执行单线程 ④配置 → `io-threads 4`（建议 CPU 核数的一半）→ `io-threads-do-reads yes`（开启读多线程）⑤效果 → 在大连接数场景 → 吞吐提升 1-2 倍 → 但不是所有命令都快 → 简单命令（GET/SET）提升大 → 复杂命令（SORT/ZUNIONSTORE）还是单线程瓶颈 / Redis 7.0 的多线程增强：①Redis 7.0 → 多线程 IO 更稳定 → 默认配置优化 → 性能比 6.0 更好 ②但核心还是 → 命令执行单线程 → 7.0 没有改成命令多线程执行 → 保持简单 ③如果命令执行是瓶颈 → 还是只能分片（Cluster）/ 读写分离（副本）/ 面试重点：Redis 6.0多线程IO=read/write多线程+命令执行单线程 → 单线程瓶颈在IO不在CPU → 6.0用IO线程池加速网络读写 → 7.0增强更稳定 → 命令执行始终单线程 → 要加速命令执行还是分片/副本）

**追问2：** Redis 7.0 有哪些重要新特性？Sharded PubSub 你了解吗？为什么 7.0 要引入它？

> 你回答...（提示：Redis 7.0 新特性 / 特性一：Sharded PubSub（分片发布订阅）①Redis Cluster 中 → `PUBLISH` 命令 → 把消息发到所有节点（广播）→ 即使订阅者在某个分片 → 消息要在所有节点转发 → 浪费网络 ②Redis 7.0 → `SPUBLISH` → 消息只发到 key 所在的分片 → `SSUBSCRIBE` → 只在 key 所在分片订阅 → 不广播 → 省网络 ③场景 → 在 Cluster 模式下做发布订阅 → 7.0 之前效率低 → 7.0 之后高效 / 特性二：Redis Functions ①Redis 7.0 → 引入 Functions → 类似存储过程 → 用 Lua 写 → 但比 EVAL/EVALSHA 更好 ②EVAL 的问题 → 每次发送脚本 → 或 EVALSHA 用 hash → 但 hash 可能被 evict → 不稳定 ③Functions → `FUNCTION LOAD` → 注册函数 → 持久化 → 重启不丢 → 可以在函数里做复杂逻辑 → 原子执行 ④场景 → 复杂的原子操作（扣库存 + 记录 + 判断）→ 以前用 Lua → 现在用 Functions → 更持久更可管理 / 特性三：listpack 替代 ziplist ①Redis 7.0 → List / Hash / ZSet 的底层 → 小数据用 listpack → 替代 ziplist ②ziplist 问题 → `prevlen` 字段 → 导致连锁更新 O(n²) → 插入一个元素 → 如果触发 prevlen 变长 → 后面所有元素都要更新 → 最坏 O(n²) ③listpack → 用 `backlen` → 从后往前解析 → 不需要 prevlen → 消除连锁更新 → 性能更稳定 ④效果 → 小数据存储更高效 → 无连锁更新 / 特性四：ACL v2（访问控制增强）①Redis 6.0 → 引入 ACL → 用户+权限 ②Redis 7.0 → ACL 增强 → 更细粒度的权限控制 → 按命令 / 按 key pattern / 按 channel ③场景 → 多租户 / 多团队共用 Redis → 隔离权限 / 特性五：多部分 AOF（Multi-Part AOF）①Redis 7.0 → AOF 重写改为多文件 → base file（RDB 格式）+ 增量 AOF → 类似 4.0 的混合持久化但更规范 ②好处 → 重写时不阻塞 → 重启加载更快 → 减少 AOF 重写期间的性能抖动 / 面试重点：Redis 7.0新特性=Sharded PubSub(分片发布订阅不广播省网络)+Functions(持久化Lua函数/替代EVALSHA)+listpack替代ziplist(消除连锁更新)+ACL v2(细粒度权限)+多部分AOF(重写不阻塞) → listpack消除ziplist连锁更新O(n²)是底层最重要的变化）

**追问3：** 你用 Redis 做分布式锁。Redis 7.0 对分布式锁有什么影响？Redlock 还有人用吗？

> 你回答...（提示：Redis 分布式锁与 7.0 / 分布式锁回顾：①SETNX + 过期时间 → 最简单 → 但有续期问题 → Redisson 看门狗自动续期 ②Redlock → antirez 提出 → 在多个 Redis 实例上 SETNX → 多数成功才算获取锁 → 防单点故障 ③Martin Kleppmann 批评 → Redlock 依赖时钟 → 时钟漂移 → 不安全 → 如果 GC 暂停 → 锁过期但客户端不知道 → 两个客户端同时持有锁 → 不安全 / Redis 7.0 对分布式锁的影响：①7.0 没有专门改变分布式锁机制 → SETNX + Redisson 看门狗 → 依然是主流方案 ②Functions → 可以用 Functions 实现更复杂的锁逻辑 → 原子执行 → 但本质上和 Lua 脚本一样 → 只是更持久可管理 ③Sharded PubSub → 锁通知 → 获取锁失败 → 订阅锁释放通知 → 7.0 之前 PUBLISH 广播 → 7.0 SPUBLISH 精准 → 节省网络 → 对锁通知有优化 / 实际选型建议：①非金融场景 → Redisson SETNX → 够用 → 性能好 → 最终一致 ②金融强一致场景 → ZooKeeper（CP）→ 临时顺序节点 → 更安全但慢 ③数据库锁 → `SELECT ... FOR UPDATE` → 最安全但性能差 ④Redlock → 争议大 → 不推荐 → 要么 Redisson（够用）→ 要么 ZK（强一致）→ Redlock 两头不靠 / 面试重点：Redis 7.0对分布式锁=没有根本变化→SETNX+Redisson看门狗依然主流→Functions可做更复杂原子锁逻辑→Sharded PubSub优化锁通知省网络 → Redlock有争议(时钟漂移+GC暂停导致不安全)→建议Redisson(够用)或ZK(强一致)→Redlock不推荐）

---

## 话题四：MySQL 组提交与 redo log 刷盘策略（11分钟）

**面试官：你之前提到过 MySQL 的 redo log。redo log 的刷盘策略你了解吗？什么是组提交（Group Commit）？它解决了什么问题？**

> 你回答...

**追问1：** 先说说 redo log 的刷盘流程。`innodb_flush_log_at_trx_commit` 有什么作用？为什么金融系统必须设为 1？

> 你回答...（提示：redo log 刷盘 / redo log 刷盘流程：①事务提交 → 写 redo log buffer（内存）→ ②redo log buffer → 写到 OS Page Cache（write）→ ③OS Page Cache → 刷到磁盘（fsync）→ 这才真正持久化 ④步骤②③之间 → 数据在 Page Cache → 如果 OS 崩溃 → 丢数据 / `innodb_flush_log_at_trx_commit` 三选项：
| 值 | write（写到OS Page Cache）| fsync（刷到磁盘）| 安全性 | 性能 |
|---|---|---|---|---|
| 0（延迟写）| 每秒一次 | 每秒一次 | 最差（宕机丢1秒数据）| 最好 |
| 1（默认，每次提交fsync）| 每次提交 | 每次提交 | 最好（宕机不丢）| 最差（每次IO）|
| 2（每次提交write，每秒fsync）| 每次提交 | 每秒一次 | 中等（OS崩溃丢1秒数据）| 中等 |
/ 金融系统必须设为 1：①事务提交 → 立即 fsync → 数据写到磁盘 → 宕机不丢 ②设为 0 或 2 → 宕机可能丢 1 秒事务 → 金融不可接受 ③代价 → 性能差 → 每次提交 fsync → 磁盘 IO → 高并发下成为瓶颈 ④解决方案 → 组提交（Group Commit）→ 多个事务的 fsync 合并成一次 → 减少 IO 次数 / 和 binlog 的关系：①`sync_binlog` 也有类似配置 → `sync_binlog=1` → 每次提交 fsync binlog → 安全 ②双 1 配置 → `innodb_flush_log_at_trx_commit=1` + `sync_binlog=1` → 最安全 → 金融标配 ③双 0 → 性能最好 → 但宕机丢数据 → 不推荐 / 面试重点：redo log刷盘=log buffer→write到OS Page Cache→fsync到磁盘 → innodb_flush_log_at_trx_commit: 0=每秒刷(丢1s)/1=每次提交fsync(最安全)/2=每次write每秒fsync(OS崩丢1s) → 金融必须=1+sync_binlog=1双1配置 → 代价=性能差→组提交优化）

**追问2：** 组提交具体是怎么工作的？多个事务的 fsync 怎么合并？两阶段提交（2PC）和组提交什么关系？

> 你回答...（提示：组提交原理 / 组提交解决的问题：①高并发 → 每秒 1000 个事务提交 → 每个事务 fsync 一次 → 1000 次磁盘 IO → 磁盘扛不住 → 性能瓶颈 ②组提交 → 多个事务 → 一次 fsync → 1000 个事务 → 可能只需 50-100 次 fsync → IO 减少 10 倍 / 组提交流程（两阶段提交中的组提交）：①事务提交 → 第一阶段 → Prepare → 写 redo log（write 到 Page Cache）→ 不 fsync → 先等着 ②多个事务 → 都在 Prepare 阶段 → 陆续写 redo log buffer → InnoDB 发现有多个事务在等 → 把它们的 redo log 合并 → 一次 fsync → 这就是组提交 ③第二阶段 → Commit → 写 binlog → binlog 也可以组提交 → `binlog_group_commit_sync_delay` → 延迟一点 → 等更多事务一起 fsync binlog → 再一起 commit ④组提交的核心 → "先攒一批 → 一次刷盘 → 一起提交" → 减少 fsync 次数 / MySQL 两阶段提交（2PC）回顾：①第一阶段（Prepare）→ 写 redo log（记录"准备提交"）→ 写到 Page Cache → 不 fsync ②第二阶段（Commit）→ 写 binlog → fsync binlog → 标记 redo log 为"已提交"→ fsync redo log ③保证 redo log 和 binlog 一致 → 如果宕机 → 恢复时 → redo log 有 Prepare 但 binlog 没有 → 回滚 / redo log 有 Prepare 且 binlog 有 → 提交 / 两阶段提交 + 组提交：①两阶段提交保证一致性 → 组提交提升性能 ②Prepare 阶段 → 多个事务攒一批 → 一次 fsync redo log ③Commit 阶段 → 多个事务攒一批 → 一次 fsync binlog + 一次 fsync redo log ④这就是 MySQL 5.7+ 的"组提交优化"→ 让双 1 配置（最安全）的性能不那么差 / 组提交的性能数据：①不开组提交 → 双 1 → 1000 TPS → fsync 瓶颈 ②开组提交 → 双 1 → 5000-10000 TPS → 5-10 倍提升 ③代价 → 提交延迟略增（等攒批）→ 但吞吐大幅提升 → 值得 ④参数 → `binlog_group_commit_sync_delay` = 0（不开）→ 设为 1000（1ms 延迟攒批）→ `binlog_group_commit_sync_no_delay_count` = 10（攒够 10 个就提交）/ 面试重点：组提交=多个事务攒一批→一次fsync→减少IO次数 → 在两阶段提交中Prepare阶段组合并redo log fsync + Commit阶段组合并binlog fsync → 双1配置+组提交→安全性和性能兼得 → 5-10倍吞吐提升但提交延迟略增）

**追问3：** 如果金融系统要求最高安全性，但组提交会延迟，怎么平衡？有没有更好的方案？

> 你回答...（提示：金融系统刷盘策略平衡 / 双 1 + 组提交 → 标准方案：①安全性 → 双 1 保证不丢 ②性能 → 组提交补偿 → 5000+ TPS → 金融核心系统够用 ③延迟 → 1ms 攒批 → 用户无感知 → 可接受 / 进一步优化：①SSD/NVMe → fsync 从毫秒级降到微秒级 → 磁盘不再是瓶颈 → 不需要过度攒批 ②RDMA → 远程直接内存访问 → 网络延迟降到微秒级 → 分布式事务更快 ③MySQL 8.0 → 并行 redo log → 多个线程并行写 redo log → 减少锁竞争 ④写多读少 → 分库分表 → 分散写入压力 / 极端安全方案：①同步复制 → MySQL 半同步复制 → 主库写 binlog → 至少一个从库收到 ACK → 主库才返回成功 → 保证主从都有 ②MGR（MySQL Group Replication）→ Paxos 协议 → 多数派写入 → 强一致 → 但性能差 ③金融核心 → 双 1 + 组提交 + 半同步复制 → 最常用的安全方案 → 不需要 MGR（太重）/ 面试重点：金融=双1+组提交+半同步复制 → 安全+性能+主从一致 → SSD/NVMe让fsync微秒级不再瓶颈 → MGR太重不常用 → 分库分表分散写压力）

---

## 话题五：手写代码 - 验证二叉搜索树（8分钟）

**面试官：写一个函数，验证一棵二叉树是否是合法的二叉搜索树（BST）。**

你在纸上/白板上写代码...

**追问1：** 先说说你的思路。BST 的定义是什么？最容易犯什么错？

> 你回答...（提示：验证 BST / BST 定义：①左子树所有节点值 < 根节点值 ②右子树所有节点值 > 根节点值 ③左右子树各自也是 BST / 最容易犯的错：①只比较节点和左右子节点 → `node.left.val < node.val && node.right.val > node.val` → 这是错的 ②反例：
```
        5
       / \
      4   6
         / \
        3   7
```
→ 6 的左子 3 < 6 ✓ → 6 的右子 7 > 6 ✓ → 但 3 在 5 的右子树 → 3 < 5 → 不合法 → 但上面的错误检查会漏掉 ③正确 → 每个节点要满足 → 所有左子树 < 根 → 所有右子树 > 根 → 不仅仅是直接子节点 / 正确解法一：递归 + 上下界 → 时间 O(n) 空间 O(h)
```java
public boolean isValidBST(TreeNode root) {
    return validate(root, null, null);
}

private boolean validate(TreeNode node, Long min, Long max) {
    if (node == null) return true;
    // 当前节点值必须在 (min, max) 范围内
    if (min != null && node.val <= min) return false;
    if (max != null && node.val >= max) return false;
    // 左子树：上界 = 当前值（所有左子树 < 当前值）
    // 右子树：下界 = 当前值（所有右子树 > 当前值）
    return validate(node.left, min, (long) node.val)
        && validate(node.right, (long) node.val, max);
}
```
/ 核心思想：①传上下界 → min/max → 当前节点必须在 (min, max) 范围内 ②左子树 → 上界 = 当前值 → 因为左子树所有节点 < 当前 ③右子树 → 下界 = 当前值 → 因为右子树所有节点 > 当前 ④用 Long 不用 int → 因为节点值可能是 Integer.MIN_VALUE/MAX_VALUE → 用 Long 避免 overflow 边界问题 / 正确解法二：中序遍历 → BST 中序遍历是升序 → 检查是否升序
```java
private TreeNode prev = null;  // 记录前一个节点

public boolean isValidBST(TreeNode root) {
    if (root == null) return true;
    // 左
    if (!isValidBST(root.left)) return false;
    // 当前 → 必须大于前一个
    if (prev != null && root.val <= prev.val) return false;
    prev = root;  // 更新 prev
    // 右
    return isValidBST(root.right);
}
```
/ 核心思想：①BST 性质 → 中序遍历（左→根→右）→ 输出是严格升序 ②如果中序遍历发现当前 <= 前一个 → 不是 BST ③递归 + 全局 prev 变量 → 每次比较当前和 prev / 两种解法对比：①上下界 → 直观 → 递归传参 → 空间 O(h) 栈深度 ②中序遍历 → 利用 BST 性质 → 代码更简洁 → 但 prev 要用全局/实例变量 → 非线程安全 ③面试 → 中序遍历更优雅 → 展示对 BST 性质的理解 / 面试重点：BST=左<根<右（不是只和直接子节点比/是和所有子树比）→ 错误=只比左右子节点→正确=上下界递归(左上界=当前值/右下界=当前值)或中序遍历(检查升序) → 用Long防int边界overflow）

**追问2：** 如果要求空间 O(1)，能怎么做？（提示：Morris 中序遍历）

> 你回答...（提示：Morris 遍历 / Morris 中序遍历原理：①普通中序遍历 → 递归/栈 → 空间 O(h) ②Morris → 不用栈 → 用线索指针（线索化）→ 空间 O(1) ③核心 → 对于每个节点 → 找它的前驱节点（中序前驱 = 左子树最右节点）→ 把前驱的右指针指向当前节点 → 形成线索 ④遍历时 → 沿线索走 → 走完恢复指针 → 不破坏树结构 / Morris 中序遍历代码：
```java
public boolean isValidBST(TreeNode root) {
    TreeNode prev = null;  // 局部变量（不用全局）
    TreeNode cur = root;
    while (cur != null) {
        if (cur.left == null) {
            // 没有左子树 → 访问当前
            if (prev != null && cur.val <= prev.val) return false;
            prev = cur;
            cur = cur.right;
        } else {
            // 找前驱（左子树最右节点）
            TreeNode predecessor = cur.left;
            while (predecessor.right != null && predecessor.right != cur) {
                predecessor = predecessor.right;
            }
            if (predecessor.right == null) {
                // 第一次访问 → 建线索 → 前驱右指针指向当前
                predecessor.right = cur;
                cur = cur.left;
            } else {
                // 第二次访问 → 线索已建 → 恢复 → 访问当前
                predecessor.right = null;  // 恢复
                if (prev != null && cur.val <= prev.val) return false;
                prev = cur;
                cur = cur.right;
            }
        }
    }
    return true;
}
```
/ 核心思想：①没有栈 → 用前驱节点的右指针做"回溯"线索 ②第一次到达节点 → 建线索（前驱→当前）→ 去左子树 ③第二次到达节点（通过线索回来）→ 恢复 → 访问 → 去右子树 ④时间 O(n)（每个节点访问两次）→ 空间 O(1)（只用几个变量）/ 面试重点：Morris=不用栈用线索指针→前驱右指针指向当前做回溯→O(1)空间→第一次建线索第二次恢复 → 了解原理即可→面试一般不要求Morris→展示对树遍历的深度理解）

---

# 二面（30分钟）

## 话题六：分布式链路追踪 Trace/Span 模型（12分钟）

**面试官：你用过 SkyWalking。链路追踪的底层原理你了解吗？Trace 和 Span 是什么？traceId 怎么跨服务传递？**

> 你回答...

**追问1：** 先说说 OpenTelemetry 的核心概念。Trace、Span、SpanContext 分别是什么？

> 你回答...（提示：Trace/Span 模型 / OpenTelemetry（OTel）：①OpenTelemetry → CNCF 项目 → 统一可观测性标准 → Tracing + Metrics + Logs → 替代 OpenTracing + OpenCensus ②Spring Boot 3 的 Micrometer Tracing → 底层用 OTel / Trace：①Trace → 一次完整的请求链路 → 从用户请求到响应 → 跨多个服务 → 用一个全局唯一的 TraceId 标识 ②如 → 用户下单 → API Gateway → 订单服务 → 库存服务(扣减) → 支付服务(扣款) → 通知服务 → 整个链路是一个 Trace / Span：①Span → 一次操作 → 如一个 HTTP 请求 / 一次 DB 查询 / 一次 Redis 调用 → 是 Trace 中的一个节点 ②Span 包含 → 操作名 / 开始时间 / 结束时间 / SpanId / ParentSpanId / Tags(标签: HTTP方法/状态码) / Events(事件: 异常) / Status(状态: OK/ERROR) ③Span 之间有父子关系 → ParentSpanId 指向父 Span → 形成一棵调用树 / SpanContext：①SpanContext → Span 的上下文 → 包含 TraceId + SpanId + TraceFlags(采样标志) ②跨进程传递 → SpanContext 序列化 → 放在 HTTP Header / MQ 消息头 → 下游反序列化 → 创建子 Span → 继续链路 / 调用树示例：
```
Trace (TraceId=abc123)
├── Span1: API Gateway (spanId=1, parent=null)
│   ├── Span2: 订单服务.createOrder (spanId=2, parent=1)
│   │   ├── Span3: DB insert order (spanId=3, parent=2)
│   │   ├── Span4: 库存服务.deduct (spanId=4, parent=2)
│   │   │   └── Span5: DB update stock (spanId=5, parent=4)
│   │   └── Span6: 支付服务.pay (spanId=6, parent=2)
│   │       ├── Span7: Redis get (spanId=7, parent=6)
│   │       └── Span8: DB insert payment (spanId=8, parent=6)
│   └── Span9: 通知服务.send (spanId=9, parent=1)
│       └── Span10: MQ publish (spanId=10, parent=9)
```
①每个 Span 记录耗时 → 最慢的 Span 就是瓶颈 ②如 Span6 支付服务 500ms → 其他都 < 50ms → 瓶颈在支付服务 → 下钻看 Span7/8 → 是 Redis 慢还是 DB 慢 / 面试重点：Trace=一次完整请求链路(唯一TraceId) → Span=一次操作(SpanId+ParentSpanId形成调用树) → SpanContext=TraceId+SpanId+TraceFlags → 跨进程传递 → Span父子关系形成调用树 → 最慢Span=瓶颈定位）

**追问2：** traceId 怎么跨服务传递？HTTP 调用和 MQ 异步消息分别怎么传？

> 你回答...（提示：traceId 跨服务传递 / HTTP 调用传递（同步）：①上游服务 → 创建 Trace → 生成 TraceId + SpanId ②HTTP 调用下游 → 把 SpanContext 注入 HTTP Header → 注入器（Injector）③标准 Header → `traceparent: 00-{traceId}-{spanId}-{traceFlags}`（W3C Trace Context 标准）→ 如 `traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01` ④Spring Cloud → OpenFeign 拦截器 → 自动注入 Header → 不需要手动 ⑤下游服务 → 从 HTTP Header 提取 SpanContext → 提取器（Extractor）→ 创建子 Span（ParentSpanId = 上游 SpanId）→ 继续链路 ⑥如果下游不提取 → 链路断 → 下游会生成新的 TraceId → 无法关联 / MQ 异步消息传递（异步）：①上游 → 发 MQ 消息 → 把 SpanContext 注入消息 Header → 如 RocketMQ 的 `MessageProperties` → `traceparent` Header ②消费者 → 从消息 Header 提取 SpanContext → 创建子 Span → 但要注意 → 生产者和消费者之间是异步的 → 时间上不连续 → Span 的父子关系通过 Header 维持 ③RocketMQ → 可以配合 OpenTelemetry → 自动注入/提取 ④Kafka → Headers（key-value）→ 同样注入 `traceparent` / 跨线程传递（同进程）：①主线程创建 Span → 提交任务到线程池 → 子线程 → SpanContext 怎么传？ ②方案 → `Context` 对象 → 显式传递 → 主线程把 SpanContext 放入 Context → 子线程从 Context 取 ③Java → `ThreadLocal` 存 SpanContext → 但跨线程 → `InheritableThreadLocal` 或 `TransmittableThreadLocal`（阿里 TTL）→ 线程池场景 ④虚拟线程 → `ScopedValue`（JDK 21）→ 替代 ThreadLocal / traceId 生成：①TraceId → 全局唯一 → 通常 128 位（16 字节）→ 如 UUID / 雪花 ID ②SpanId → 链路内唯一 → 64 位 → 随机或递增 ③TraceFlags → 1 字节 → 01 = 采样（记录）/ 00 = 不采样（不记录）→ 减少开销 / 采样策略：①全量采样 → 每个请求都记录 → 性能开销大 → 高 QPS 不现实 ②概率采样 → 如 1% → 随机采样 → 大部分请求不记录 → 但可能漏掉关键请求 ③尾部采样（Tail-Based Sampling）→ 等整个 Trace 完成后 → 根据结果决定是否采样 → 如：有异常的 Trace 100% 采样 / 慢请求（>1s）100% 采样 / 正常请求 1% → 精准但有延迟和内存开销 / 面试重点：traceId跨服务=HTTP Header注入(traceparent W3C标准)/MQ消息头注入 → Feign拦截器自动注入/消费者自动提取 → 跨线程=ThreadLocal/TTL → 采样=概率采样(减少开销)或尾部采样(有异常/慢的全采) → TraceId全局唯一128位/SpanId链路内64位）

**追问3：** 如果你要排查一个"接口偶发慢"的问题，链路追踪怎么帮你定位？

> 你回答...（提示：链路追踪排查流程 / 排查步骤：①第一步 → 找慢 Trace → APM 系统（SkyWalking/Tempo）→ 按接口名过滤 → 按耗时排序 → 找到 > 1s 的 Trace ②看调用树 → 展开 Trace → 找最慢的 Span → 如支付服务 Span 800ms → 其他都 < 100ms → 瓶颈在支付服务 ③下钻 → 展开支付服务 Span → 看子 Span → DB 查询 700ms → Redis 50ms → 瓶颈是 DB ④DB Span 看 Tags → SQL 语句 / 查询行数 / 索引 → 如果 SQL 是全表扫描 → 加索引 ⑤如果不是 DB → 看 Span 状态 → 有没有 ERROR → 有异常 → 看异常堆栈 → 可能是超时重试导致慢 ⑥如果偶发 → 看多个慢 Trace → 比较共同点 → 都是同一时间段 → 可能是 GC → 都是同一个 DB → 可能是锁等待 → 都是同一台机器 → 可能是单机问题 / 关键能力：①调用链可视化 → 调用树 → 一眼看出哪层慢 ②Span Tags → SQL/HTTP方法/状态码/缓存命中 ③服务依赖图 → 哪个服务调谁 → 调用频率 → 找热点依赖 ④对比 → 正常 Trace vs 慢 Trace → 找差异 / 和日志关联：①TraceId → 关联日志 → 在 ELK/Loki 中搜 TraceId → 拿到整个链路的所有日志 → 看有没有异常日志 ②MDC（Mapped Diagnostic Context）→ 日志框架把 TraceId 放到 MDC → 日志自动带 TraceId → Spring Boot 3 + Micrometer 自动配置 / 实际排查案例：①接口偶发慢 → 查链路追踪 → 发现慢的时候都有一次额外的 DB 查询（缓存未命中）→ 查 Redis → 发现 key 设置了随机过期但某些热点 key 同时过期 → 缓存重建 → DB 查询 → 慢 → 解决 → 缓存预热 / 热点 key 不过期 / 面试重点：排查=APM找慢Trace→看调用树找最慢Span→下钻到DB/Redis Span看Tags(SQL/行数/缓存命中)→对比正常vs慢Trace找差异→TraceId关联日志搜ELK → 实际案例=缓存未命中导致额外DB查询→热点key同时过期→预热/不过期解决）

---

## 话题七：核心设计题 - 数字银行核心账务系统（18分钟）

**面试官：微众是数字银行，没有实体网点，所有业务线上化。核心账务系统要怎么设计？每天几百万笔交易，怎么保证账务准确、系统高可用、对账不出错？**

> 你回答...

**追问1：** 先说说银行核心账务系统的基本模型。和普通互联网系统的"扣减余额"有什么本质区别？

> 你回答...（提示：银行账务模型 / 银行核心账务和互联网余额扣减的本质区别：①互联网（如支付宝余额）→ 只有一个余额字段 → `UPDATE account SET balance = balance - 100 WHERE id = 1` → 简单 ②银行 → 复式记账（Double Entry Bookkeeping）→ 每笔交易至少两条记录 → 借方和贷方必须相等 → 有借必有贷，借贷必相等 ③银行不用"余额扣减"→ 用"记账" → 每笔交易 → 记一条流水 → 余额 = 历史所有流水求和 → 不直接 UPDATE 余额 / 复式记账模型：①每笔交易 → 至少两个账户 → 借方账户（Debit）+ 贷方账户（Credit）→ 金额相等 ②如 → A 转 B 100 元 → 借：B 账户 100（增加）→ 贷：A 账户 100（减少）→ 借贷相等 ③流水表（分户账）→ 每条记录 → 账户 / 借贷方向 / 金额 / 摘要 / 对方账户 / 日期 ④余额 → 不存储 → 每次从流水计算 → 或者定期计算余额缓存到账户表（日终批量）⑤账户表 → 存账户信息 + 上日余额 + 今日余额 / 为什么用复式记账不用余额扣减：①审计 → 每笔交易有完整记录 → 借贷关系清晰 → 可追溯 ②对账 → 所有流水借贷合计 = 0 → 如果不等 → 有错 ③防止直接改余额 → 没有"改余额"的操作 → 只能记账 → 余额 = 流水求和 → 无法篡改 ④这和互联网"直接 UPDATE 余额"的本质区别 → 银行从不直接改余额 → 只记账 / 表结构设计：
```sql
-- 分户账（流水表）
CREATE TABLE account_journal (
    id BIGINT PRIMARY KEY,
    account_no VARCHAR(32) NOT NULL,    -- 账户号
    dc_flag CHAR(1) NOT NULL,            -- D=借(Debit) C=贷(Credit)
    amount DECIMAL(18,2) NOT NULL,      -- 金额
    balance_after DECIMAL(18,2),         -- 记账后余额
    opposite_account VARCHAR(32),       -- 对方账户
    summary VARCHAR(128),               -- 摘要
    voucher_no VARCHAR(32) NOT NULL,     -- 凭证号（交易号）
    trade_date DATE NOT NULL,            -- 交易日期
    create_time DATETIME NOT NULL,
    INDEX idx_account_date (account_no, trade_date),
    INDEX idx_voucher (voucher_no)
);

-- 账户表
CREATE TABLE account (
    account_no VARCHAR(32) PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    account_type VARCHAR(16),            -- 活期/定期/贷款
    currency VARCHAR(8),                 -- 币种
    balance DECIMAL(18,2),               -- 当前余额
    available_balance DECIMAL(18,2),     -- 可用余额（扣除冻结）
    status VARCHAR(8),                   -- 正常/冻结/销户
    last_trade_date DATE,
    ...
);
```
/ 面试重点：银行=复式记账(有借必有贷/借贷必相等)→每笔交易至少两条流水→余额=流水求和不直接UPDATE → 互联网=直接扣减余额 → 银行记账=审计可追溯+对账借贷=0验证+无法篡改余额 → 流水表(分户账)+账户表分离）

**追问2：** 几百万笔交易/天，记账性能怎么保证？高峰期 TPS 可能上万，DB 怎么扛？

> 你回答...（提示：记账性能设计 / 性能挑战：①每笔交易 → 2+ 条流水 → 100 万笔 = 200 万条流水 → DB 写入 200 万 ②高峰 → 每秒 1 万笔 → 2 万条流水/秒 → MySQL 单机写 ~5000 TPS → 扛不住 ③还要更新余额 → 每笔交易 → 查余额 + 计算 + 写流水 + 更新余额 → 多次 DB 操作 / 优化方案：①分库分表 → 按账户号分片 → 流水表分散到多个库 → 写入压力分散 ②批量记账 → 不是每笔交易实时写 → 攒批 → 100 笔一批 → 批量 INSERT → 减少 DB 往返 ③异步化 → 交易先写消息 → 消费者异步记账 → 削峰 → 但有延迟 ④余额缓存 → Redis 缓存余额 → 查余额从 Redis → 减少 DB 读 → 但余额要和 DB 一致 → 事务保证 / 银行实际做法——日间+日终双轨：①日间（实时）→ 每笔交易 → 实时记账 → 写流水 + 更新余额 → 但只更新"分户账余额"（当日余额）→ 保证实时可查 ②日终（批量）→ 每天 23:00 → 跑批 → ①汇总当日所有流水 → 计算各账户最终余额 → ②更新总账（科目余额表）→ ③和总账核对 → 确保日间分户账汇总 = 总账 ③日终批处理 → 是银行核心的"跑批"→ 大量数据 → 分片并行 → 几个小时跑完 → 这就是为什么银行晚上 23:00-次日 5:00 系统维护（"日终切日"）④日间切日 → 日终跑批前 → 做日终处理 → 切换会计日期 → 所有交易归到新的会计日 / 流水写入优化：①顺序写 → redo log + binlog 顺序写 → 快 → 但流水表 INSERT 是随机写（B+树索引）②用 TokuDB / RocksDB → LSM 树 → 顺序写 → 写入快 → 但读慢 ③分库分表 → 按账户号分 → 同一账户的流水在同一分片 → 顺序写 → 快 / 余额一致性保证：①实时记账 → DB 事务 → 写流水 + 更新余额 → 原子 ②`balance_after` → 每条流水记录"记账后余额"→ 形成余额链 → 如果中间断了 → 可以从任何一条流水恢复 ③幂等 → 凭证号（voucher_no）唯一约束 → 防重复记账 ④余额 = 最后一条流水的 `balance_after` → 如果不一致 → 从头计算 / 面试重点：记账性能=分库分表(按账户号)+批量INSERT+异步削峰+Redis余额缓存 → 银行双轨=日间实时记账(分户账余额)+日终批量跑批(汇总到总账+核对) → 流水写balance_after形成余额链→凭证号唯一防重复→余额=最后一条流水的balance_after）

**追问3：** 对账怎么设计？银行对账和互联网对账有什么不同？怎么保证"一分钱都不差"？

> 你回答...（提示：银行对账设计 / 对账的层次：①内部对账 → 分户账 vs 总账 → 各账户余额汇总 = 总账科目余额 → 借贷平衡 ②外部对账 → 本行 vs 央行/银联/他行 → 跨行交易 → 双方记录一致 ③系统间对账 → 账务系统 vs 支付系统 vs 清算系统 → 数据一致 / 对账流程：①日终跑批 → 汇总当日所有流水 → 计算各账户余额 → 写入总账 ②内部对账 → 分户账余额汇总 vs 总账 → 借方合计 = 贷方合计 → 如果不等 → 有错 → 定位 ③外部对账 → 下载他行/银联对账文件 → 逐笔比对 → 差异 → 长款（我多他少）→ 查原因 → 短款（我少他多）→ 查原因 ④差异处理 → ①系统延迟 → 次日到账 → 次日对账消除 ②重复记账 → 冲正 ③漏记 → 补记 ④金额不符 → 人工核实 / 一分钱不差的保证：①金额用 DECIMAL → 不用 float/double → 避免浮点精度问题 ②每笔交易借贷必相等 → 系统强制校验 → `if (debitAmount != creditAmount) throw` ③流水 balance_after 形成余额链 → 每条流水 → 记录记账后余额 → 如果余额对不上 → 从任何一条流水恢复 ④日终对账 → 借贷合计 = 0 → 不等于 0 → 有错 → 全量重算 ⑤数据库事务 → 每笔交易 → DB 事务保证原子性 → 要么全成功要么全回滚 → 不会出现只记借方不记贷方 / 异常处理：①记账失败 → 事务回滚 → 不影响已有数据 ②对账差异 → 自动定位 → 是哪笔交易 → 人工核实 → 冲正/补记 ③"总分不符"→ 最严重 → 总账和分户账对不上 → 可能是记账 bug / 并发 bug / 数据丢失 → 全量重算 → 从最早流水重新计算 / 和互联网对账的区别：①互联网 → 互联网对账 → 双方记录一致 → 差异 = 可能丢消息/重复处理 → 幂等解决 ②银行 → 借贷平衡 + 分户账 vs 总账 + 外部对账 → 多层校验 → 任何一层不对都要定位 ③银行更严格 → "一分钱都不能差"→ 借贷必须相等 → 不等 = 系统 bug → 不能"忽略" / 面试重点：银行对账=三层(内部分户账vs总账/外部vs他行/系统间) → 日终跑批汇总→借贷合计=0校验→不一致全量重算 → DECIMAL不用float/借贷必等强制校验/balance_after余额链/凭证号唯一 → 异常=冲正/补记/人工核实 → 总分不符=最严重→全量重算）

**追问4：** 微众是数字银行，没有网点。如果核心账务系统要设计高可用，怎么保证 7x24 不停机？传统银行"日终跑批要停服务"，微众怎么做？

> 你回答...（提示：数字银行高可用设计 / 传统银行的问题：①日终跑批 → 停服务 → 23:00-5:00 维护 → 用户不能用 → 不适合数字银行 ②单数据中心 → 机房故障 → 全行停业 → 风险大 / 微众的高可用设计：①多活数据中心 → 同城双活 + 异地灾备 → 两个数据中心同时提供服务 → 不分主备 → 任何一个挂了另一个继续 ②核心系统微服务化 → 账务 / 支付 / 清算 / 风控 / 客户 → 各自独立 → 一个挂不影响其他 ③数据库 → 分布式数据库（TDSQL / TiDB / OceanBase）→ 多副本 + 自动故障转移 → 不依赖单机 MySQL / 日终跑批不停服务的方案：①分布式跑批 → 之前说了分片并行 → 每个分片独立跑 → 不影响其他分片 ②热备切换 → 跑批时 → 切到备库跑 → 主库继续服务 → 跑完切回 ③异步跑批 → 不阻塞实时交易 → 跑批任务优先级低 → 实时交易优先 → 资源隔离 ④微众实际 → 用 TDSQL（腾讯分布式数据库）→ 多副本一致 → 跑批和交易并行 → 资源隔离 / 7x24 不停机：①滚动升级 → K8s → 逐 Pod 滚动更新 → 不停服务 ②灰度发布 → 新版本 → 先灰度 10% 流量 → 观察 → 没问题 → 全量 ③故障自愈 → K8s → Pod 挂了 → 自动重启 → 健康检查 ④数据库故障转移 → TDSQL → 主库挂了 → 自动切从库 → 几秒切换 ⑤异地灾备 → 异地机房 → 同步/异步复制 → 同城全挂 → 异地接管 / 金融合规：①两地三中心 → 同城双活（两个机房同时服务）+ 异地灾备（异步复制）→ 央行要求 ②RPO（数据恢复点目标）→ 同城 = 0（不丢数据）→ 异地 < 30 秒 ③RTO（恢复时间目标）→ 同城 < 30 秒（快速切换）→ 异地 < 30 分钟 / 面试重点：数字银行高可用=多活数据中心(同城双活+异地灾备)+微服务化+分布式数据库(TDSQL/TiDB) → 日终跑批不停服务=分布式并行跑批/热备切换/异步优先低/资源隔离 → 7x24=滚动升级+灰度+故障自愈+数据库自动故障转移 → 合规=两地三中心/RPO+RTO达标）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| Java 21 虚拟线程（M:N映射/堆栈unmount/同步代码异步性能/synchronized pin限制/Reactive对比） | 能讲清 / 讲不全 / 不会★ | |
| Spring Boot 3 新特性（JDK17基线/Jakarta包名/GraalVM Native Image AOT/Micrometer可观测性） | 能讲清 / 讲不全 / 不会★ | |
| Redis 7.0 新特性（6.0多线程IO/Sharded PubSub/Functions/listpack替代ziplist/ACL v2/多部分AOF） | 能讲清 / 讲不全 / 不会★ | |
| MySQL 组提交（redo log刷盘/innodb_flush_log_at_trx_commit三选项/双1配置/组提交合并fsync/两阶段提交） | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（验证BST/上下界递归/中序遍历检查升序/Morris O(1)空间） | 能讲清 / 讲不全 / 不会★ | |
| 分布式链路追踪（Trace/Span/SpanContext/W3C traceparent Header/MQ消息头传递/采样策略/排查慢请求） | 能讲清 / 讲不全 / 不会★ | |
| 数字银行核心账务系统（复式记账/分户账+总账/日间实时+日终跑批双轨/三层对账借贷平衡/多活高可用不停机） | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **虚拟线程**：传统线程 1:1 映射 OS 线程 → 1 万线程 = 10GB 内存 → IO 阻塞浪费。虚拟线程 M:N 映射 → 栈在堆上 → IO 阻塞时 JVM unmount 虚拟线程释放载体线程 → IO 完成后 mount 回来 → 开发者写同步代码但运行时接近异步性能。限制：CPU 密集不适合（不 unmount）/ `synchronized` 会 pin 载体线程（JDK 21 限制，JDK 24 修复，用 `ReentrantLock` 替代）/ ThreadLocal 滥用内存（用 `ScopedValue`）。可能替代 Reactive 编程（同步代码 + 接近异步性能 + 调试容易）
> 2. **Spring Boot 3**：JDK 17 基线 + Jakarta `javax→jakarta` 包名 + GraalVM Native Image AOT（毫秒级启动/50MB 内存，代价：编译慢/闭世界/无 JIT/调试难）+ Micrometer 统一可观测性（Metrics+Tracing+Logs 三合一自动埋点）。四大核心变化：基线升级 / Native Image / Observability / 新 API（@HttpExchange/Record）
> 3. **Redis 7.0**：6.0 多线程 IO（read/write 多线程 + 命令执行单线程，瓶颈在 IO 不在 CPU）。7.0 新特性：Sharded PubSub（分片发布订阅不广播省网络）/ Functions（持久化 Lua 替代 EVALSHA）/ **listpack 替代 ziplist**（消除连锁更新 O(n²)，底层最重要）/ ACL v2（细粒度权限）/ 多部分 AOF（重写不阻塞）
> 4. **MySQL 组提交**：redo log 刷盘 = log buffer → write 到 OS Page Cache → fsync 到磁盘。`innodb_flush_log_at_trx_commit`：0=每秒刷（丢 1s）/ **1=每次提交 fsync（最安全，金融必须）** / 2=每次 write 每秒 fsync（OS 崩丢 1s）。组提交 = 多个事务攒一批 → 一次 fsync → 在两阶段提交的 Prepare 和 Commit 阶段分别合并 → 双 1 配置 + 组提交 = 安全 + 性能（5-10 倍吞吐提升）
> 5. **验证 BST**：错误 = 只比左右子节点（反例：右子树里有比根小的值）。正确 = 上下界递归（左子树上界=当前值 / 右子树下界=当前值）或中序遍历检查升序。Morris 遍历用线索指针 O(1) 空间（前驱右指针指向当前做回溯）
> 6. **链路追踪**：Trace = 一次完整请求（唯一 TraceId）→ Span = 一次操作（SpanId + ParentSpanId 形成调用树）→ SpanContext = TraceId + SpanId + TraceFlags。跨服务传递 = HTTP Header `traceparent`（W3C 标准）→ Feign 拦截器自动注入 / MQ 消息头注入 → 跨线程 = ThreadLocal/TTL。采样 = 概率采样（减少开销）/ 尾部采样（异常+慢的全采）。排查 = APM 找慢 Trace → 看调用树最慢 Span → 下钻 DB/Redis Span 看 Tags → TraceId 关联日志搜 ELK
> 7. **数字银行核心账务**：复式记账（有借必有贷/借贷必相等）→ 每笔交易 2+ 条流水 → 余额 = 流水求和不直接 UPDATE。分户账（流水表）+ 账户表分离。日间实时记账 + 日终批量跑批双轨制。三层对账（分户账 vs 总账 / 本行 vs 他行 / 系统间）→ 借贷合计 = 0 校验 → DECIMAL 不用 float → balance_after 余额链 → 凭证号唯一防重复。高可用 = 多活数据中心 + 分布式数据库（TDSQL）+ 日终跑批不停服务（分片并行/资源隔离）→ 两地三中心合规
