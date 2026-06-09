|知识点|笔记时重点写什么|
|---|---|
|**Sentinel 核心概念**|热 Resource（资源，即被保护的代码/API）/ Rule（规则）/ Context（上下文，一次调用的入口）/ Entry（资源入口，SphU.entry()）/ Node（统计节点，记录 QPS/RT 等指标）。理解这几个概念的关系图|
|**限流规则详解**|热 三种流控模式：**直接**（针对当前资源）、**关联**（当关联资源达到阈值时限流当前资源，典型的"支付"关联"下单"场景）、**链路**（只记录从入口资源进来的流量）。三种阈值类型：QPS / 线程数|
|**滑动窗口算法原理**|核 Sentinel 用**滑动窗口**做数据统计（不是固定窗口！避免了边界突发问题）。LeapArray 数组 + WindowWrap 窗口格 + Metric 统计值。窗口长度默认 500ms，数组长度 2（即 1 秒采样区间）|
|**熔断规则与状态机**|热 三种熔断策略：慢调用比例（RT > 阈值的比例）、异常比例（异常数/总数）、异常数（绝对值）。三态转换：**CLOSED → OPEN → HALF-OPEN → CLOSED/OPEN**。HALF-OPEN 放行一个探测请求，成功则恢复，失败则重新打开|
|**热点参数限流**|热 `@SentinelResource` + `blockHandler`。可以针对某个参数的特定值单独设阈值（如用户 ID=VIP 用户给更高的 QPS 配额）。支持参数索引和例外项|
|**系统自适应限流**|基于 SystemRule 自适应调整，综合考虑 CPU 使用率 / load1 / 平均 RT / 入口 QPS / 并发线程数五项指标。适合在系统整体负载过高时作为兜底保护|
|**@SentinelResource 注解**|热 value（资源名）、entryType（EntryType.IN/OUT）、blockHandler（限流/熔断时的降级方法）、fallback（业务异常时的兜底方法）。**注意 blockHandler 和 fallback 的区别**：前者是 Sentinel 规则触发的，后者是代码抛异常的|
|**Sentinel Dashboard 与规则持久化**|规则默认存在内存，重启就丢。生产环境必须持久化：推模式（Dashboard 推送到 Nacos/ZooKeeper）或拉模式（客户端从配置中心定期拉取）。推荐 Nacos 作为规则数据源|

> **笔记技巧**：熔断状态机必须画成图——CLOSED → OPEN（触发条件）→ HALF-OPEN（sleepWindowInMs 时间后自动进入）→ 探测请求成功回 CLOSED / 失败回 OPEN。这张图覆盖了熔断题的 80%。