# 面试模拟 - Day 62

> 日期：2026-08-01（周六） | 模拟岗位：中国农业银行（杭州分行）- 信息科技部 - Java开发工程师
> 建议时长：100分钟（一面70分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day62，"查漏补缺"阶段第十周。模拟中国农业银行杭州分行信息科技部——农行是国有大型商业银行，三农金融特色突出（"惠农e贷"、农户贷款、数字农业平台），杭州分行科技部主要做智慧网点、农村信贷数字化、涉农补贴发放。面试特点：大行偏稳健保守、等保安全要求高（等保三级）、关注系统稳定性和数据安全、追问偏实战落地。今天引入 **Java 21 虚拟线程、Caffeine 本地缓存、限流算法深入、ZooKeeper 深入、Elasticsearch 倒排索引、Java 引用类型与 GC、XXL-JOB 分布式调度** 7个全新技术话题 + 数字农业与三农金融业务 + 合并有序链表手写代码——继续覆盖之前碎片提到但没有作为独立话题系统考过的高频核心考点。每话题3-4个追问，模拟真实面试连环深挖。

---

# 一面（70分钟）

## 话题一：Java 21 虚拟线程（Project Loom）（9分钟）

**面试官：JDK 21 你们上了吗？虚拟线程了解吗？它和普通线程有什么区别？你们项目中用了没有？**

> 你回答...

**追问1：** 先说说虚拟线程是什么。它和平台线程有什么本质区别？为什么说它"轻量"？

> 你回答...（提示：平台线程 vs 虚拟线程 / 平台线程（Platform Thread）：1:1映射OS线程 → 每个线程约1MB栈空间 → 创建/销毁开销约1-2ms → OS线程上限通常几千个 → 线程多了CPU切换开销大。虚拟线程（Virtual Thread）：JDK 21正式特性（JEP 444）→ N:M映射 → N个虚拟线程映射到M个载体线程（Carrier Thread/平台线程）→ 栈存储在堆上（Continuation机制）→ 初始栈仅几KB → 可创建百万级虚拟线程 / 轻量原因：①不直接绑定OS线程 → VT在载体线程上运行 → 遇到IO阻塞 → VT的栈从载体线程复制到堆 → VT unmount → 载体线程释放 → 去执行其他VT → IO完成后VT从堆恢复到载体线程 → 重新mount继续执行 ②栈在堆上按需分配 → 不预分配1MB ③创建开销约几微秒 → 平台线程约1-2ms ④调度 → JVM自己调度（ForkJoinPool共享池作为载体线程池）→ 不靠OS调度 / 结构示意：
```
平台线程（1:1）：Thread-1 → OS Thread1（1MB栈）→ 10000线程=10GB内存 → 不现实
虚拟线程（N:M）：VT-1,VT-2,VT-3 → Carrier Thread1（ForkJoinPool worker）
                VT-4,VT-5,VT-6 → Carrier Thread2
                100万VT → 仅CPU核心数个载体线程 → 内存几GB
```
/ 虚拟线程实现核心：Continuation → JVM底层机制 → VT执行到阻塞点（IO/sleep/wait）→ 调用Continuation.yield → VT栈从载体线程复制到堆 → 载体线程释放 → 阻塞完成 → Continuation.run → VT栈从堆恢复 → 重新mount到某个载体线程 → 继续 → 整个过程对代码透明 → 写同步代码得异步效果）

**追问2：** 虚拟线程的适用场景和不适用场景？什么情况下虚拟线程反而更差？

> 你回答...（提示：适用/不适用场景 / 适用：①IO密集型 → 大量阻塞操作（HTTP调用/DB查询/Redis）→ VT阻塞时释放载体线程 → 载体线程执行其他VT → 高并发 ②请求响应模型 → 每个请求一个VT → 不需要线程池 → 不需要回调/CompletableFuture → 同步代码写异步效果 → 如Web服务器每请求一个VT → 10万并发 → Tomcat/Loom支撑 ③任务数大但每个任务IO等待长 → 如爬虫/批量调外部API / 不适用：①CPU密集型 → VT不阻塞 → 占着载体线程 → 和平台线程没区别 → 没有优势 ②需要精确控制并发数 → VT无限创建 → 可能压垮下游 → 需要Semaphore限制 ③大量ThreadLocal → 每个VT都有ThreadLocal → 内存膨胀 / 反而更差的情况：①synchronized导致pinning → VT无法unmount → 载体线程被占 → 退化成平台线程 ②大量CPU计算 → VT切换开销>平台线程 ③内存敏感 → 百万VT每个栈虽小 → 但总量仍可能GB级 / 真实数字：1万平台线程≈10GB内存（1MB×10000），100万虚拟线程≈几GB内存（每个约2-4KB×100万=2-4GB），载体线程池=ForkJoinPool默认CPU核心数（如8核=8个载体线程）→ 8个载体线程支撑百万VT）

**追问3：** synchronized 在虚拟线程中有什么问题？怎么解决？

> 你回答...（提示：Pinning问题 / synchronized在VT中的问题：synchronized块 → JVM在monitor上pin住VT → VT无法unmount → 如果synchronized块内做了IO阻塞 → VT被pin在载体线程上 → 载体线程被占 → 不能执行其他VT → 退化成平台线程 / 原因：synchronized用OS monitor → JVM无法在synchronized块内unmount VT → 因为unmount后如果其他线程拿到了锁 → 状态不一致 / 解决：①用ReentrantLock替代synchronized → ReentrantLock是JUC实现 → 不pin → VT可以正常unmount ②JDK 24（JEP 491）完全修复synchronized pinning → 但JDK 21仍有限制 ③检测pinning → `-Djdk.tracePinnedThreads=full` → 打印pin的堆栈 → 排查 / 踩坑：生产上用VT + synchronized + HTTP调用 → 载体线程被耗尽 → 请求堆积 → 排查发现synchronized导致pinning → 改ReentrantLock → 解决
```java
// 有问题：synchronized + VT + IO
public void badExample() throws Exception {
    synchronized (this) {           // ← pin住VT
        String result = httpCall(); // ← 阻塞IO → VT无法unmount → 载体线程被占
    }
}
// 正确：ReentrantLock + VT
private final ReentrantLock lock = new ReentrantLock();
public void goodExample() throws Exception {
    lock.lock();
    try {
        String result = httpCall(); // ← VT正常unmount → 载体线程释放
    } finally {
        lock.unlock();
    }
}
```
/ 举一反三：ThreadLocal也要注意 → 每个VT都有ThreadLocal → 百万VT × 大对象 → 内存爆炸 → 用ScopedValue（JDK 21预览）替代ThreadLocal → 不可变 → 共享 → 不膨胀）

**追问4：** 用了虚拟线程还需要线程池吗？虚拟线程和线程池怎么配合？

> 你回答...（提示：VT与线程池 / 用了VT还需要线程池吗：①不需要池化VT → VT很轻 → 创建开销小 → 不需要复用 → `Thread.startVirtualThread(() -> {...})` → 用完即弃 ②但需要限制并发数 → 不能无限创建VT → 虽然VT轻 → 但无限创建会压垮下游（DB连接池/Redis/外部API）→ 需要Semaphore限制 / 线程池场景：①载体线程池 → ForkJoinPool → 默认CPU核心数 → 不需要配 ②业务并发控制 → Semaphore → 控制同时有多少VT在执行IO / 最佳实践：`Executors.newVirtualThreadPerTaskExecutor()` → 每个任务一个VT → 替代固定线程池 → +Semaphore限制下游并发
```java
ExecutorService vtPool = Executors.newVirtualThreadPerTaskExecutor();
Semaphore semaphore = new Semaphore(200); // 限制最多200个并发IO
public void task() {
    vtPool.submit(() -> {
        semaphore.acquire();
        try {
            httpCall();
        } finally {
            semaphore.release();
        }
    });
}
```
/ 迁移经验：原来ThreadPoolExecutor(200) → 改成newVirtualThreadPerTaskExecutor()+Semaphore(200) → 200个并发IO不变 → 但排队任务不再阻塞在队列 → 而是排队在Semaphore → 不需要调corePoolSize/maxPoolSize/queueCapacity → 简化配置 / 小张一句到位：虚拟线程不是银弹 → IO密集才划算 → CPU密集别用 → synchronized会pin → 改ReentrantLock → 无限创建会打爆下游 → 加Semaphore兜底）

---

## 话题二：Caffeine 本地缓存（9分钟）

**面试官：你们缓存怎么用的？Redis？有没有用本地缓存？Caffeine 了解吗？它和 Guava Cache 有什么区别？**

> 你回答...

**追问1：** 先说说 Caffeine 是什么。它和 Guava Cache/Redis 有什么区别？为什么选 Caffeine？

> 你回答...（提示：Caffeine 对比 / Caffeine：Java本地缓存库 → Spring Boot 2.0+默认缓存实现 → 替代Guava Cache → 作者也是Guava Cache原作者（Ben Manes）→ 性能比Guava Cache高30%-50% / 和Guava Cache区别：①API几乎兼容 → 迁移成本低 ②淘汰算法 → Guava用LRU → Caffeine用W-TinyLFU → 命中率高 ③性能 → Caffeine用RingBuffer+异步维护 → 读写不阻塞 → Guava用ConcurrentHashMap+同步维护 → 高并发有竞争 ④异步 → Caffeine支持AsyncLoadingCache → Guava不支持 / 和Redis区别：①Caffeine=本地缓存（堆内）→ 每个JVM实例独立 → 微服务多实例缓存不共享 ②Redis=分布式缓存 → 所有实例共享 → 一致性好 → 但网络开销 → Caffeine纳秒级(~100ns) → Redis毫秒级(~1ms) ③Caffeine=内存受限 → Redis可集群扩展 / 为什么选Caffeine：①读多写少的热点数据 → 本地纳秒级 → 减少Redis访问 ②配置字典/静态数据 → 不频繁变 ③多级缓存 → Caffeine(L1)+Redis(L2) → L1命中就不查Redis
| 维度 | Caffeine | Guava Cache | Redis |
|------|----------|-------------|-------|
| 位置 | JVM堆内 | JVM堆内 | 独立进程 |
| 延迟 | ~100ns | ~200ns | ~1ms |
| 容量 | 受JVM堆限制 | 受JVM堆限制 | 可集群扩展 |
| 共享 | 不共享 | 不共享 | 共享 |
| 淘汰 | W-TinyLFU | LRU | LRU/LFU/random |
| 持久化 | 不支持 | 不支持 | RDB/AOF |
）

**追问2：** Caffeine 的 W-TinyLFU 淘汰算法是什么？为什么比 LRU 好？

> 你回答...（提示：W-TinyLFU / LRU的问题：①全量扫描 → 遍历10万Key → LRU把热点数据挤出 → 命中率暴跌 ②只看最近 → 不看频率 → 某Key经常访问但不是最近 → LRU可能淘汰它 ③LinkedHashMap双向链表 → 每次访问移到头部 → 并发有锁竞争 / W-TinyLFU = Window + TinyLFU：
```
W-TinyLFU 结构：
┌──────────────────────────────────────────────┐
│            Window (1%)                        │ ← 新数据进入 → LRU淘汰
│  [新Key1] [新Key2] [新Key3]                  │
├──────────────────────────────────────────────┤
│            Main (99%)                         │
│  ┌──────────────┐  ┌───────────────────────┐ │
│  │ Probation 20% │  │  Protection 80%       │ │ ← 频繁访问→提升/长期不访问→降级
│  │ [Key4][Key5]  │  │ [Key1][Key2][Key3]    │ │
│  └──────────────┘  └───────────────────────┘ │
└──────────────────────────────────────────────┘
         ↑ TinyLFU (Count-Min Sketch) 估算频率 → 决定保留
```
①Window（窗口区1%）→ 新数据先进Window → LRU淘汰 → 防全量扫描冲刷 ②TinyLFU → Count-Min Sketch → 多个hash函数+多个计数器 → 固定空间估算访问频率 → 不存所有Key ③Main区（99%）→ Probation(试用期20%)+Protection(保护区80%)→ 在Probation的Key如果被再次访问 → 提升到Protection → 长期不访问降到Probation / 为什么比LRU好：①抗扫描冲刷 → Window区隔离新数据 ②频率+近因 → TinyLFU看频率 → 热点更稳定 ③空间效率 → Count-Min Sketch固定空间 → 不随Key数增长 / 真实数字：W-TinyLFU命中率比LRU高约30%（Caffeine官方基准测试）→ 在扫描场景下命中率差距更大）

**追问3：** 多级缓存（Caffeine + Redis）怎么设计？缓存一致性怎么保证？

> 你回答...（提示：多级缓存一致性 / 多级缓存架构：请求→Caffeine(L1)→命中返回/未命中→Redis(L2)→命中回填L1返回/未命中→DB→回填L1+L2 / 一致性问题：微服务多实例 → 实例A更新数据 → A的L1+Redis更新 → 但实例B的L1还是旧值 → 脏读 / 解决方案：①TTL过期 → Caffeine设短TTL（如30s）→ 最多脏30s → 简单但不够实时 ②Redis Pub/Sub → 更新时发布消息 → 各实例订阅 → 收到后清L1 → 近实时 → 但Pub/Sub不保证送达 ③MQ广播 → 更新时发MQ → 各实例消费 → 清L1 → 可靠 → 但延迟+复杂度 ④Canal监听binlog → Canal→MQ→各实例→清L1 → 解耦 / 最佳实践：L1=Caffeine(TTL 30s, maxSize 10000) + L2=Redis(TTL 30min) + 更新时MQ广播失效L1
```java
// 多级缓存
LoadingCache<String, User> l1 = Caffeine.newBuilder()
    .maximumSize(10_000)
    .expireAfterWrite(30, TimeUnit.SECONDS)  // L1短TTL
    .build(key -> getFromRedis(key));
private User getFromRedis(String key) {
    User user = redis.get(key);
    if (user == null) { user = db.get(key); redis.set(key, user, 30, MINUTES); }
    return user;
}
// 更新时MQ广播失效L1
public void updateUser(User user) {
    db.update(user);
    redis.set("user:" + user.getId(), user, 30, MINUTES);
    mq.send("cache-invalidate", "user:" + user.getId());
}
@KafkaListener(topics = "cache-invalidate")
public void onInvalidate(String key) { l1.invalidate(key); }
```
/ 踩坑：多级缓存 + 只用TTL → 实例A更新 → 实例B读旧值30秒 → 配置类数据→影响大 → 加MQ广播 → 实例B1秒内收到 → 清L1 → 下次读新值 → 延迟从30s降到1s）

**追问4：** Caffeine 的异步刷新怎么做？refreshAfterWrite 和 expireAfterWrite 有什么区别？

> 你回答...（提示：异步刷新 / LoadingCache（同步）：get(key)→未命中→同步调load→阻塞当前线程。AsyncLoadingCache（异步）：get(key)→返回CompletableFuture→不阻塞 / refreshAfterWrite vs expireAfterWrite：
```
expireAfterWrite(10min) → 到期 → 清除 → 下次get阻塞加载新值（同步）
refreshAfterWrite(5min) → 到期 → 下次get返回旧值 → 后台异步刷新 → 不阻塞读
```
→ 最佳实践：refreshAfterWrite(短) + expireAfterWrite(长) → 先异步刷新 → 如果刷新失败 → 过期兜底
```java
LoadingCache<String, Config> cache = Caffeine.newBuilder()
    .maximumSize(10_000)
    .refreshAfterWrite(5, TimeUnit.MINUTES)   // 5分钟异步刷新
    .expireAfterWrite(30, TimeUnit.MINUTES)    // 30分钟兜底过期
    .build(key -> loadFromDB(key));
```
/ 举一反三：refreshAfterWrite的异步刷新 → 用Caffeine内置ForkJoinPool → 也可以自定义线程池 → `Caffeine.executor(scheduledExecutor)` → 控制刷新线程数 / 小张一句到位：多级缓存不是加层就完事 → 一致性才是核心 → TTL兜底+MQ广播实时清 → 30秒+1秒双保险）

---

## 话题三：限流算法深入（8分钟）

**面试官：你们限流怎么做的？Sentinel？用的什么算法？令牌桶了解吗？漏桶呢？滑动窗口？**

> 你回答...

**追问1：** 先说说常见的限流算法有哪些。各有什么优缺点？

> 你回答...（提示：四种限流算法 / 1. 固定窗口计数法：时间分固定窗口（如1秒一个）→ 每窗口计数 → 超阈值拒绝。问题=临界突刺 → 0.9秒来100个+1.0秒（新窗口）又100个 → 0.1秒内200个 → 突刺 2. 滑动窗口计数法：窗口分N个小格子（1秒分10个100ms）→ 当前窗口=最近N个格子之和 → 超阈值拒绝。解决临界突刺 → 但格子数有限 → 仍有小突刺。Sentinel默认 3. 漏桶（Leaky Bucket）：请求进桶 → 桶满拒绝 → 桶底固定速率漏水（处理）。恒定速率 → 平滑 → 不允许突发。适合保护下游 4. 令牌桶（Token Bucket）：固定速率往桶放令牌 → 桶满丢弃 → 请求取令牌 → 有令牌通过 → 无拒绝。允许突发 → 桶里积累令牌 → 突发一次取多个。适合入口限流
| 算法 | 突发 | 平滑 | 实现 | 场景 |
|------|------|------|------|------|
| 固定窗口 | 临界突刺 | 差 | 最简单 | 粗略限流 |
| 滑动窗口 | 小突刺 | 中 | 中等 | Sentinel默认 |
| 漏桶 | 不允许 | 好 | 中等 | 保护下游 |
| 令牌桶 | 允许 | 中 | 中等 | 入口限流 |
）

**追问2：** 令牌桶和漏桶的区别？Sentinel 用的是什么？Guava RateLimiter 呢？

> 你回答...（提示：令牌桶 vs 漏桶 / 令牌桶 → 允许突发 → 桶里积累10个令牌 → 突然来10个 → 全过 → 后续等新令牌 → 长期速率=令牌生成速率。漏桶 → 不允许突发 → 恒定速率处理 → 不管来多少 → 处理速率恒定 / 场景：入口用令牌桶（允许突发→用户体验好）→ 下游保护用漏桶（恒定速率→不打爆下游） / Sentinel使用：①默认滑动窗口 → LeapArray → 每个样本一个Window → 统计窗口内通过数 ②也支持匀速排队（RateLimiter策略）→ 类似漏桶 → QPS匀速 → 削峰填谷 → 但有等待延迟 / Guava RateLimiter → 令牌桶 → `RateLimiter.create(100)` → 每秒100个令牌 → `acquire()`有令牌立即→无阻塞等待 → 突发用SmoothBursty → 允许预存令牌。预热用SmoothWarmup → 冷启动慢→逐渐到满速率→防冷启动打爆
```java
// Guava RateLimiter
RateLimiter limiter = RateLimiter.create(100); // 100 QPS
for (int i = 0; i < 200; i++) {
    limiter.acquire(); // 前100个立即→后100个每10ms一个
}
// 预热限流 → 冷启动慢
RateLimiter warm = RateLimiter.create(100, 10, TimeUnit.SECONDS, 0.5);
// 10秒预热 → 从50QPS逐渐到100QPS
```
）

**追问3：** 滑动窗口计数法怎么实现？Sentinel 的 LeapArray 是什么？

> 你回答...（提示：Sentinel LeapArray / LeapArray原理：①1秒分成2个500ms样本窗口（sampleCount=2, intervalInMs=1000）②每个样本=WindowWrap → 含windowStart（起始时间）+value（计数值）③请求来→算当前在哪个窗口→窗口内+1→统计QPS=当前窗口+前一个窗口的值 ④窗口过期→重置
```
时间轴：0ms     500ms   1000ms  1500ms  2000ms
        |--------|--------|--------|--------|
         Window0  Window1  Window2  Window3
当前=700ms → 在Window1 → 统计1秒QPS = Window0(0-500) + Window1(500-700)
```
/ LeapArray核心方法：currentWindow(timeMillis) → 算idx=calculateTimeIdx → 算windowStart → 如果窗口过期(windowStart不匹配)→重置窗口→CAS更新 → 如果同一窗口→直接返回 / 数据结构：AtomicReferenceArray<WindowWrap> → 环形数组 → sampleCount个元素 → 无锁CAS / 踩坑：sampleCount=2 → 每个窗口500ms → 如果请求在窗口边界 → 可能两个窗口都算 → 误差 → 增大sampleCount可以减少误差但增加内存 / Sentinel默认sampleCount=2 → 可以通过`SphEntry`配置 → 也可以自定义StatisticSlot）

**追问4：** 分布式限流怎么做？Redis + Lua 怎么实现令牌桶？

> 你回答...（提示：分布式限流 / 分布式需求：多实例 → 每个实例本地限流不准 → 总QPS超限 → 需要全局限流 → Redis统一计数 / Redis+Lua令牌桶：①Key存上次取令牌时间+当前令牌数 ②Lua原子执行→算时间差→补充令牌(时间差×速率)→令牌=min(补充后,桶容量)→够→扣减返回1→不够返回0 ③Redis单线程执行Lua→原子性→不会被其他请求打断
```lua
-- Redis Lua 令牌桶
local key = KEYS[1]
local rate = tonumber(ARGV[1])      -- 令牌生成速率（每秒）
local capacity = tonumber(ARGV[2])  -- 桶容量
local now = tonumber(ARGV[3])       -- 当前毫秒时间戳
local requested = tonumber(ARGV[4]) -- 请求令牌数
local info = redis.call('HMGET', key, 'last_time', 'tokens')
local last_time = tonumber(info[1]) or now
local tokens = tonumber(info[2]) or capacity
-- 补充令牌
local delta = math.max(0, now - last_time) / 1000
tokens = math.min(capacity, tokens + delta * rate)
-- 判断
if tokens >= requested then
    tokens = tokens - requested
    redis.call('HMSET', key, 'last_time', now, 'tokens', tokens)
    redis.call('EXPIRE', key, 60)
    return 1  -- 允许
else
    redis.call('HMSET', key, 'last_time', now, 'tokens', tokens)
    redis.call('EXPIRE', key, 60)
    return 0  -- 拒绝
end
```
/ 性能：Redis+Lua → 每次约1ms → 万级QPS够用 → 但更高QPS → Redis瓶颈 → 可以本地令牌桶+Redis定期校准 → 本地按速率生成令牌 → 每秒从Redis同步一次剩余令牌数 → 减少Redis访问 / 举一反三：Sentinel+集群限流 → TokenServer统一发令牌 → 各实例从TokenServer获取令牌额度 → 本地消耗 → 定期续借 → 和Redis+Lua思路类似但Sentinel自实现）

---

## 话题四：ZooKeeper 深入（8分钟）

**面试官：ZooKeeper 你们用过吗？做注册中心？还是分布式锁？ZAB 协议了解吗？Watcher 机制？**

> 你回答...

**追问1：** 先说说 ZooKeeper 是什么。它和 Nacos 有什么区别？为什么很多公司从 ZK 迁移到 Nacos？

> 你回答...（提示：ZK vs Nacos / ZooKeeper：Apache开源→分布式协调服务→树形结构（类似文件系统）→ZNode节点→临时/持久/顺序→CP模型→ZAB协议保证一致 / 和Nacos区别：
| 维度 | ZooKeeper | Nacos |
|------|-----------|-------|
| 一致性 | CP（强一致） | AP+CP（可切换） |
| 注册中心 | 临时节点+Watcher | 心跳+Push |
| 配置中心 | 支持（不友好） | 原生支持 |
| 健康检查 | Session超时 | 心跳/TCP/HTTP |
| 推送 | Watcher一次性 | UDP推送+长轮询 |
| 性能 | 万级写/十万级读 | 更高 |
| 运维 | 复杂 | 简单 |
/ 为什么迁移：①ZK的CP模型→Leader选举时不可用→注册中心不可用→服务发现失败→不适合注册中心（AP更好→可用性优先）②Watcher一次性→每次通知后要重新注册→通知量大时性能差→Nacos用UDP推送+长轮询更高效 ③ZK做配置中心不友好→没有namespace/group概念 ④运维复杂→ZK集群3/5台→Java→内存→GC→STW→不稳定）

**追问2：** ZAB 协议是什么？它和 Raft 有什么区别？

> 你回答...（提示：ZAB协议 / ZAB（ZooKeeper Atomic Broadcast）：ZK的崩溃可恢复原子广播协议 → 保证所有副本数据一致 → 两阶段：①崩溃恢复 ②消息广播 / 消息广播（简化版2PC）：①Leader收到写请求→生成ZXID→发Proposal给所有Follower ②Follower写本地日志→ACK ③Leader收到半数以上ACK→Commit→发Commit给Follower ④Follower收到Commit→应用变更。和2PC区别：不需要所有ACK→半数即可→更快 / 崩溃恢复：①Leader崩溃→Follower进入Looking状态 ②选举→ZXID最大的→ZXID相同选myid最大的→成为Leader ③新Leader→同步数据→和Follower对齐ZXID ④同步完成→进入广播状态 / 和Raft区别：
| 维度 | ZAB | Raft |
|------|-----|------|
| 编号 | ZXID（epoch+counter） | Term+Index |
| 选举 | ZXID最大+myid最大 | Term最大+Log最长 |
| Commit | 半数ACK Leader Commit | 半数ACK Leader Commit |
| 日志 | 每个Follower独立日志 | Leader维护Log |
| 心跳 | Leader→Follower ping | Leader→Follower AppendEntries |
| 应用 | ZooKeeper | etcd/Consul |
/ 本质：都是Paxos变体→半数ACK→Leader→强一致→CP模型→选举期间不可用）

**追问3：** Watcher 机制是什么？有什么局限？怎么解决？

> 你回答...（提示：Watcher机制 / Watcher特点：客户端注册Watcher→监听ZNode变化→变化时ZK通知客户端→客户端执行回调 / 三个特点：①一次性→注册后只触发一次→触发后失效→需重新注册 ②轻量→只通知"发生了变化"→不通知内容→需主动getData ③客户端串行→同一客户端多个Watcher串行执行→回调慢→阻塞后续 / 局限：①一次性→重新注册间隙可能漏通知 ②不通知内容→额外getData往返 ③串行→回调慢阻塞 / 解决：Curator框架→NodeCache/PathCache/TreeCache→底层自动重新注册→持续监听→对开发者透明
```java
// 原生ZK Watcher（一次性）
zookeeper.getData("/config", new Watcher() {
    public void process(WatchedEvent event) {
        // 触发后失效 → 需重新注册
        zookeeper.getData("/config", this, null); // 重新注册
    }
}, null);
// Curator NodeCache（自动重注册）
NodeCache nodeCache = new NodeCache(client, "/config");
nodeCache.getListenable().addListener(() -> {
    ChildData data = nodeCache.getCurrentData();
    // 持续监听 → 不需手动重注册
});
nodeCache.start(true);
```
/ 踩坑：原生ZK Watcher → 忘记重新注册 → 配置变更后不再收到通知 → 配置不一致 → 改用Curator → 自动重注册 → 解决）

**追问4：** ZK 的临时节点和顺序节点有什么用？分布式锁怎么实现？为什么不用临时节点直接做锁？

> 你回答...（提示：临时顺序节点分布式锁 / 节点类型：①持久节点→永久存在→主动删除 ②临时节点→Session失效自动删除 ③顺序节点→创建时ZK自动加递增序号 / 临时节点直接做锁的问题：所有客户端创建同一个临时节点→创建成功=获锁→失败=等待→监听节点→删除→所有等待者同时创建→"惊群"→大量请求冲击ZK / 顺序节点解决惊群：
```
/lock
  ├── node-0001  ← 客户端A（最小→获锁）
  ├── node-0002  ← 客户端B（监听node-0001）
  ├── node-0003  ← 客户端C（监听node-0002）
  └── node-0004  ← 客户端D（监听node-0003）
A释放→删node-0001→B的Watcher触发→B最小→获锁
```
→ 每个等待者只监听前一个→前一个删除→只唤醒一个→不惊群 / Curator InterProcessMutex封装：
```java
InterProcessMutex lock = new InterProcessMutex(client, "/lock");
if (lock.acquire(5, TimeUnit.SECONDS)) {
    try {
        // 业务逻辑
    } finally {
        lock.release();
    }
}
```
/ 和Redis分布式锁对比：ZK锁=CP（强一致）→但性能差（ZK写入慢~ms级）→Redis锁=AP（最终一致）→性能好（~微秒级）→大部分场景用Redis→ZK锁适合强一致要求 / 小张一句到位：ZK分布式锁用临时顺序节点 → 每个等的人只盯前面那个 → 不惊群 → 但性能不如Redis → 强一致选ZK → 高并发选Redis）

---

## 话题五：Elasticsearch 倒排索引与搜索原理（8分钟）

**面试官：你们用 ES 做什么？全文检索？ES 的倒排索引了解吗？它和 MySQL 的索引有什么区别？**

> 你回答...

**追问1：** 先说说 ES 的倒排索引是什么。它和 MySQL 的 B+ 树索引有什么区别？

> 你回答...（提示：倒排索引 / 正向索引：文档ID→文档内容→搜索遍历所有文档→慢。倒排索引：词项(Term)→文档ID列表→搜索查词→直接得文档ID→快 / 结构：Term Dictionary（词项字典）→Term+Posting List(文档ID列表)→FST压缩存储Term→Posting List用Frame of Reference压缩
```
倒排索引示例：
文档1：Hello World
文档2：Hello Java
文档3：World Java

Term      → Posting List
"Hello"   → [1, 2]
"World"   → [1, 3]
"Java"    → [2, 3]

搜索 "Hello World" → [1,2] ∩ [1,3] = [1] → 文档1
```
/ 和B+树索引区别：
| 维度 | 倒排索引(ES) | B+树索引(MySQL) |
|------|-------------|----------------|
| 搜索 | 词→文档ID→全文检索 | 值→行指针→精确/范围 |
| 适合 | 模糊/全文/多词组合 | 精确等值/范围查询 |
| 分词 | 需分词器 | 不分词 |
| 更新 | 重建索引慢 | B+树插入快 |
| 排序 | 相关性打分(BM25) | 索引排序 |
| 聚合 | Bucket聚合 | GROUP BY |
/ 什么时候用ES vs MySQL：①全文/模糊搜索→ES（LIKE '%xx%'走不了索引）②多字段组合搜索→ES（B+树只能用一个索引）③精确查询/事务→MySQL ④关联查询→MySQL（ES不支持JOIN））

**追问2：** 分词器是什么？IK 分词器怎么用？中文搜索怎么做？

> 你回答...（提示：分词器 / 分词器(Analyzer)组成：①Character Filter（字符过滤→去HTML标签）②Tokenizer（分词→切词）③Token Filter（词过滤→小写/停用词/同义词） / ES内置：①Standard→按Unicode分词→中文按字分（"你好"→"你","好"）→不适合中文 ②Simple→按非字母 ③Whitespace→按空格 / IK分词器（中文）：①ik_smart→粗粒度→"我是中国人"→"我"/"是"/"中国人"→适合搜索 ②ik_max_word→细粒度→"我是中国人"→"我"/"是"/"中国"/"国人"→适合索引 ③实际→索引用ik_max_word（多分词提高召回）→搜索用ik_smart（少分词提高精确）④自定义词典→金融术语"银联在线"不分词
```json
PUT /articles {
  "settings": {
    "analysis": {"analyzer": {"ik_smart_analyzer": {"type":"custom","tokenizer":"ik_smart","filter":["lowercase"]}}}
  },
  "mappings": {"properties": {
    "title": {"type":"text","analyzer":"ik_max_word","search_analyzer":"ik_smart"},
    "content": {"type":"text","analyzer":"ik_max_word"}
  }}
}
```
）

**追问3：** ES 的搜索流程是什么？相关性打分是什么？BM25 了解吗？

> 你回答...（提示：搜索流程与BM25 / ES搜索两阶段：①Query Phase→协调节点收到请求→分发到所有Shard→每个Shard本地搜索→返回docID+score列表→协调节点合并→排序→取TopN ②Fetch Phase→协调节点根据TopN的docID→向对应Shard请求文档内容→返回
```
搜索流程：
Client → Coordinating Node
  → Shard1: [doc5:0.8, doc2:0.6]
  → Shard2: [doc8:0.9, doc1:0.5]
  → Shard3: [doc9:0.7, doc3:0.4]
协调节点合并排序→取Top2→[doc8,doc5]
  → 向Shard2请求doc8内容→返回
  → 向Shard1请求doc5内容→返回
  → 返回Client
```
→ 两阶段减少网络传输→Query只传docID（轻量）→Fetch只取需要的 / 相关性打分（BM25）：①TF（词频）→词在文档中出现越多→分数越高→但有饱和 ②IDF（逆文档频率）→词在所有文档中越少→越稀有→分数越高→"的"分数低→"虚拟线程"分数高 ③文档长度归一→短文档含词比长文档含词更相关 / BM25公式→`score=IDF×(TF×(k1+1))/(TF+k1×(1-b+b×docLen/avgDocLen))`→k1=1.2控制TF饱和→b=0.75控制文档长度影响 / 举一反三：ES默认就是BM25→之前是TF-IDF→BM25有TF饱和→防止一个词出现100次就分数爆炸→更合理）

**追问4：** ES 的深分页问题是什么？怎么解决？

> 你回答...（提示：深分页 / 深分页问题：`from+size`→如from=10000,size=10→ES要取10010条→排序→取后10条→每个Shard取10010→协调节点合并→排序→取后10→浪费99.9%数据→内存CPU浪费。ES限制`from+size<=10000`（默认max_result_window） / 解决方案：①search_after→用上一页最后一条的sort值→下一页从这个值之后查→每次只查size条→不浪费→但不能跳页（只能向前翻）②Scroll API→建立快照→每次取size→用scroll_id继续→适合批量导出→但占资源→ES 7.0+推荐search_after替代 ③限制翻页深度→产品限制→如只翻100页
```json
// search_after
// 第一页
GET /articles/_search {"size":10,"sort":[{"timestamp":"desc"},{"_id":"asc"}]}
// 返回最后一条sort值：[1690848000000,"abc123"]
// 第二页
GET /articles/_search {
  "size":10,
  "sort":[{"timestamp":"desc"},{"_id":"asc"}],
  "search_after":[1690848000000,"abc123"]
}
```
/ 踩坑：产品要翻第200页 → from=1990,size=10 → ES报错 → 改search_after → 但产品要跳页 → 和产品沟通 → 深页改为条件搜索（缩小范围）→ 不翻到200页 → 合理的产品设计）

---

## 话题六：Java 引用类型与 GC（8分钟）

**面试官：Java 有几种引用类型？强引用、软引用、弱引用、虚引用了解吗？ThreadLocal 里的弱引用你注意过吗？**

> 你回答...

**追问1：** 先说说 Java 有哪几种引用类型。各有什么区别？

> 你回答...（提示：四种引用 / JDK 1.2引入java.lang.ref包 / ①强引用（Strong）→ `Object obj=new Object()` → 只要强引用存在→GC绝不回收→OOM也不回收→默认引用 ②软引用（SoftReference）→ `new SoftReference<>(obj)` → 内存不足时才回收→适合缓存 ③弱引用（WeakReference）→ `new WeakReference<>(obj)` → 下次GC就回收→不管内存够不够→适合ThreadLocal/WeakHashMap ④虚引用（PhantomReference）→ `new PhantomReference<>(obj,queue)` → get()永远返回null→不影响对象生命周期→唯一作用→对象被回收时收到通知→配合ReferenceQueue做资源清理
```
引用强度：强 > 软 > 弱 > 虚
GC回收时机：
强引用 → 不回收（OOM也不回收）
软引用 → 内存不足时回收
弱引用 → 下次GC就回收
虚引用 → 随时可回收（不影响生命周期）
```
）

**追问2：** 软引用和弱引用在缓存中怎么用？WeakHashMap 是什么？ThreadLocal 里的弱引用你注意过吗？

> 你回答...（提示：引用实战 / 软引用做缓存：
```java
Map<String, SoftReference<byte[]>> cache = new HashMap<>();
cache.put("image1", new SoftReference<>(loadImage("image1")));
SoftReference<byte[]> ref = cache.get("image1");
byte[] image = ref.get();  // 被GC回收→返回null→重新加载
if (image == null) {
    image = loadImage("image1");
    cache.put("image1", new SoftReference<>(image));
}
```
→ 内存够时不回收→内存不足时回收→防OOM / WeakHashMap：Entry的key是弱引用→key被GC→Entry自动移除→适合临时缓存/附加数据
```java
WeakHashMap<Object, String> map = new WeakHashMap<>();
Object key = new Object();
map.put(key, "data");
key = null; // 强引用断开→GC回收key→Entry自动移除
System.gc();
// map.size() == 0
```
/ ThreadLocal的弱引用：ThreadLocalMap的Entry→`extends WeakReference<ThreadLocal<?>>`→key（ThreadLocal实例）是弱引用→防止ThreadLocal实例无法回收 → 但value是强引用→如果不remove→value不会回收→内存泄漏 → 解决：用完必须`threadLocal.remove()` / 举一反三：为什么ThreadLocalMap的key用弱引用？→ 如果用强引用→ThreadLocal实例被外部=null→但ThreadLocalMap还强引用→ThreadLocal实例无法回收 → 用弱引用→ThreadLocal实例=null后→key可被GC→但value仍强引用→需手动remove）

**追问3：** 虚引用的作用是什么？ReferenceQueue 是什么？堆外内存清理怎么用虚引用？

> 你回答...（提示：虚引用与ReferenceQueue / 虚引用：get()永远返回null→不能获取对象→唯一作用→对象被GC回收时→GC把虚引用放入ReferenceQueue→代码从Queue取出→知道对象被回收了→做清理 / ReferenceQueue：GC回收引用关联的对象时→把Reference对象放入关联的ReferenceQueue→代码从Queue取出→做后续处理
```java
ReferenceQueue<Object> queue = new ReferenceQueue<>();
PhantomReference<Object> phantomRef = new PhantomReference<>(new Object(), queue);
// 后台线程监听Queue
new Thread(() -> {
    while (true) {
        Reference<?> ref = queue.remove(); // 阻塞→直到有引用入队
        if (ref == phantomRef) {
            System.out.println("对象被回收→清理资源");
            // 清理堆外内存/文件句柄
        }
    }
}).start();
```
/ 应用场景：①DirectByteBuffer→分配堆外内存→Cleaner（虚引用）→ByteBuffer被GC→Cleaner入队→后台线程调Unsafe.freeMemory释放堆外内存 ②Netty ByteBuf→用虚引用检测→如果没有release就被GC→报泄漏 / 举一反三：Cleaner是JDK内部用的虚引用 → `sun.misc.Cleaner` → DirectByteBuffer分配堆外内存时创建Cleaner → `Cleaner.create(this, new CleanerImpl(unsafe, address))` → this被GC → Cleaner入队 → 后台Cleaner线程执行清理 → 释放堆外内存 → 所以DirectByteBuffer不用担心堆外内存泄漏（只要DirectByteBuffer本身被GC））

**追问4：** GC 怎么处理不同引用类型？可达性分析中怎么判断？

> 你回答...（提示：GC与引用类型 / 可达性分析：从GC Roots出发→遍历引用链→有路径=可达=不回收。无路径=候选回收 / 四种引用在可达性分析：①强引用→有强引用链→可达→不回收 ②软引用→只有软引用→内存够→软引用可达→不回收→内存不足→不可达→回收 ③弱引用→只有弱引用→下次GC→不可达→回收 ④虚引用→虚引用不算可达性→有没有虚引用不影响→只靠虚引用→立即可回收 / GC实际过程：①标记→从GC Roots遍历→强引用可达不标→软引用根据内存标记→弱引用标不可达→虚引用标不可达 ②回收→不可达对象回收→软/弱/虚引用对象放入ReferenceQueue→应用可感知 ③Finalizer→如果有finalize→放F-Queue→Finalizer线程执行→可能复活但只一次→下次直接回收 / 小张一句到位：强引用是铁链子→死不松手→软引用是橡皮筋→内存不够才断→弱引用是纸糊的→GC就碎→虚引用是幽灵→只看不碰→只告诉你"人没了"）

---

## 话题七：XXL-JOB 分布式任务调度（8分钟）

**面试官：你们定时任务怎么做的？Spring 的 @Scheduled？XXL-JOB 用过吗？分布式任务调度怎么保证不重复执行？**

> 你回答...

**追问1：** 先说说 XXL-JOB 是什么。它和 @Scheduled/Quartz 有什么区别？

> 你回答...（提示：对比 / @Scheduled问题：①单机→多实例都执行→重复 ②不能动态修改→改Cron要重启 ③无监控→失败不知道 / XXL-JOB架构：
```
XXL-JOB 架构：
┌──────────────┐       HTTP        ┌──────────────┐
│  调度中心     │ ──────────────→  │  执行器(实例1) │
│  (Admin)     │ ←──────────────  │              │
│              │       HTTP        ┌──────────────┐
│  - 任务管理   │ ──────────────→  │  执行器(实例2) │
│  - 调度日志   │ ←──────────────  │              │
│  - 告警      │       HTTP        ┌──────────────┐
│              │ ──────────────→  │  执行器(实例3) │
└──────────────┘                  └──────────────┘
```
①调度中心（Admin）→独立部署→管理任务配置(Cron/参数)→负责调度→按Cron触发→向执行器发HTTP调度请求 ②执行器（Executor）→嵌入业务应用→注册到调度中心→接收调度→执行任务→回调结果 / 对比表：
| 维度 | @Scheduled | Quartz | XXL-JOB |
|------|-----------|--------|---------|
| 分布式 | 不支持 | 支持(复杂) | 支持(简单) |
| 调度中心 | 无 | 嵌入式 | 独立中心 |
| 可视化 | 无 | 无 | Web控制台 |
| 动态调度 | 不支持 | 支持 | 支持 |
| 任务分片 | 不支持 | 不支持 | 支持 |
| 告警 | 无 | 无 | 邮件/钉钉 |
| 故障转移 | 不支持 | 有限 | 支持 |
）

**追问2：** XXL-JOB 怎么保证不重复执行？多实例怎么选一个执行？

> 你回答...（提示：防重复执行 / 调度中心是单点调度→只有调度中心决定谁执行→向一个执行器发调度→只有一个执行→不会重复 / 调度中心集群→DB锁（SELECT FOR UPDATE）→只有一个节点触发 / 路由策略（选哪个执行器）：
| 策略 | 说明 |
|------|------|
| FIRST | 第一个 |
| LAST | 最后一个 |
| ROUND | 轮询 |
| RANDOM | 随机 |
| CONSISTENT_HASH | 一致性哈希 |
| LEAST_FREQUENTLY_USED | 最少使用 |
| LEAST_RECENTLY_USED | 最近最久未使用 |
| FAILOVER | 故障转移（不可用跳过） |
| BUSYOVER | 忙碌转移（忙碌跳过） |
| SHARDING_BROADCAST | 分片广播（所有都执行，各执行不同分片） |
/ 踩坑：多实例+@Scheduled → 3个实例→任务执行3次→数据重复→改XXL-JOB→只一个执行→解决）

**追问3：** 任务分片广播是什么？怎么做并行调度？

> 你回答...（提示：分片广播 / 分片广播（SHARDING_BROADCAST）：调度中心向所有执行器发调度→每个都执行→但各执行不同分片→并行处理 / 原理：调度中心告诉执行器→总分片数=执行器数→当前分片号=序号→执行器根据分片号处理对应数据
```
分片广播示例：3个执行器处理100万条数据
调度中心→向3个执行器都发调度
  执行器1：shardIdx=0, shardTotal=3 → id % 3 == 0
  执行器2：shardIdx=1, shardTotal=3 → id % 3 == 1
  执行器3：shardIdx=2, shardTotal=3 → id % 3 == 2
每个约33万条→3个并行→总耗时=1/3
```
```java
@XxlJob("dataProcessHandler")
public void dataProcess() {
    int shardIdx = XxlJobHelper.getShardIndex();
    int shardTotal = XxlJobHelper.getShardTotal();
    // 只处理自己分片 → SQL: WHERE id % #{shardTotal} = #{shardIdx}
    List<Data> list = dataMapper.selectByShard(shardIdx, shardTotal);
    for (Data data : list) { process(data); }
}
```
/ 举一反三：如果执行器数量变化→分片数变化→数据要重新分配→所以分片广播适合可重复执行的任务（幂等）→如果任务不幂等→分片变化可能重复/遗漏→需谨慎）

**追问4：** 任务失败了怎么办？重试和告警怎么设计？有什么坑？

> 你回答...（提示：失败处理 / 失败处理：①任务失败→执行器返回失败→调度中心记录日志→状态=失败 ②失败重试→调度中心配retryCount→失败后等→重新调度→可能不同执行器 ③执行器内部重试→代码try-catch→失败重试N次→再返回 / 告警：①调度中心监控→失败/超时→发告警 ②方式→邮件/钉钉Webhook ③内容→任务名/时间/失败原因/日志 / 踩坑：①任务超时→大数据量执行很久→设超时→超时kill→但可能数据不一致→建议幂等+断点续传 ②任务重复→调度中心集群+网络问题→可能触发两次→任务要幂等 ③执行器离线→下线→调度失败→FAILOVER到其他→但如果全离线→任务积压 ④日志积压→调度中心记录每次调度日志→日积月累→DB膨胀→定期清理 / 最佳实践：任务幂等+重试3次+超时30分钟+告警钉钉+日志保留30天+断点续传（记录处理到哪条→失败后从断点继续））

---

## 话题八：手写代码 - 合并两个有序链表（8分钟）

**面试官：给你两个有序链表，合并成一个有序链表。比如 1->3->5 和 2->4->6，合并后 1->2->3->4->5->6。写一下。**

你在纸上/白板上写代码...

**追问1：** 先说说思路。有哪些方法？最优的是什么？

> 你回答...（提示：合并有序链表思路 / 方法一：迭代法→双指针→每次取较小的→接到结果→O(n+m)时间→O(1)空间。方法二：递归法→比较两个头节点→较小的.next=递归合并剩余→O(n+m)时间→O(n+m)栈空间 / 最优=迭代法→O(1)空间→递归有栈开销→链表长→栈溢出）

**追问2：** 写迭代法代码。

> 你回答...（提示：迭代法代码
```java
public ListNode mergeTwoLists(ListNode l1, ListNode l2) {
    ListNode dummy = new ListNode(0); // 哨兵节点→简化头处理
    ListNode cur = dummy;
    while (l1 != null && l2 != null) {
        if (l1.val <= l2.val) {
            cur.next = l1;
            l1 = l1.next;
        } else {
            cur.next = l2;
            l2 = l2.next;
        }
        cur = cur.next;
    }
    cur.next = (l1 != null) ? l1 : l2; // 剩余接上
    return dummy.next;
}
```
/ 哨兵节点dummy的作用：不需要单独处理头节点→统一逻辑→最后返回dummy.next / 递归法：
```java
public ListNode mergeTwoLists(ListNode l1, ListNode l2) {
    if (l1 == null) return l2;
    if (l2 == null) return l1;
    if (l1.val <= l2.val) {
        l1.next = mergeTwoLists(l1.next, l2);
        return l1;
    } else {
        l2.next = mergeTwoLists(l1, l2.next);
        return l2;
    }
}
```
）

**追问3：** 如果是合并 K 个有序链表呢？怎么做最优？

> 你回答...（提示：合并K个链表 / 方法一：两两合并→合并1和2→结果和3→...→O(kN)→k为链表数N为总节点数。方法二：最小堆→K个头节点入堆→每次取最小→接到结果→取完的链表下一个入堆→O(N log k)。方法三：分治→两两合并→类似归并→O(N log k)
```java
// 最小堆法
public ListNode mergeKLists(ListNode[] lists) {
    PriorityQueue<ListNode> heap = new PriorityQueue<>((a, b) -> a.val - b.val);
    for (ListNode node : lists) {
        if (node != null) heap.offer(node);
    }
    ListNode dummy = new ListNode(0), cur = dummy;
    while (!heap.isEmpty()) {
        ListNode min = heap.poll();
        cur.next = min;
        cur = cur.next;
        if (min.next != null) heap.offer(min.next); // 下一个入堆
    }
    return dummy.next;
}
```
）

**追问4：** 时间复杂度分析？K 很大时有什么优化？

> 你回答...（提示：复杂度 / 两个链表→O(n+m)→遍历一次。K个最小堆→O(N log k)→每次堆操作log k→N个节点→N log k。K个分治→O(N log k)→每层合并O(N)→log k层 / K很大时优化：①分治比堆快→分治每层N→log k层→常数因子小→堆每次log k→N次→常数大 ②外部排序思路→如果K极大（内存放不下）→分块→每块合并→再合并 / 类比归并排序→归并排序就是分治合并→O(N log N)→和分治合并K链表思路一致）

---

# 二面（30分钟）

## 话题九：数字农业与三农金融（10分钟）

**面试官：你了解三农金融吗？农行的三农业务有哪些？涉农信贷和普通信贷有什么区别？技术上要解决什么问题？**

> 你回答...

**追问1：** 先说说三农金融是什么。农行的三农业务有哪些？

> 你回答...（提示：三农金融 / 三农金融：服务"三农"（农村/农业/农民）→农行定位→面向"三农"、服务城乡 / 农行三农业务：①惠农e贷→农户信用贷款→线上申请→基于农户信用+土地确权→额度5-30万→期限随生产周期 ②农户贷款→种植/养殖贷款→需实地调查→期限随生产周期（如春耕秋收）③涉农企业贷→农业企业/合作社→供应链金融 ④数字农业平台→卫星遥感+物联网→监测作物长势→指导贷款决策 ⑤涉农补贴发放→粮食补贴/农机补贴→直接打到农户惠农卡 / 技术要解决的问题：①数据少→农户没有银行流水/社保/公积金→传统风控不适用 ②地域分散→农村网点少→实地调查成本高→线上化 ③风险高→天灾/病虫害/市场波动→收入不稳定→需要替代数据 ④等保合规→银行系统等保三级→数据加密/审计/灾备）

**追问2：** 涉农信贷和普通信贷有什么区别？风控有什么特殊？

> 你回答...（提示：涉农信贷特殊风控 / 区别：①数据少→农户无银行流水/社保/公积金→传统风控模型不适用 ②风险高→天灾/病虫害/市场波动→收入不稳定 ③地域分散→农村网点少→实地调查成本高 ④抵押物特殊→土地经营权/林权/农机→评估难、处置难 / 风控特殊：①替代数据→土地确权数据+作物种植数据+补贴数据→替代银行流水 ②卫星遥感→监测作物面积/长势→验证种植真实性→如农户说种了50亩玉米→卫星遥感验证 ③物联网→智能农机/传感器→实时监测→温湿度/土壤/作物生长 ④政府增信→涉农补贴/农业保险→信用增信→如农户有农业保险→风险降低 ⑤整村授信→以村为单位→村集体信用→批量授信→降低单户调查成本）

**追问3：** 数字农业怎么落地？技术怎么赋能？

> 你回答...（提示：数字农业技术落地 / 卫星遥感→NDVI（归一化植被指数）→通过卫星图片计算→反映作物长势→绿度越高长势越好→判断是否受灾。遥感+AI→作物识别（玉米/水稻/小麦）→面积测算→估产。物联网→智能农机（插秧机/收割机装GPS和传感器）→作业轨迹→耕了多大面积→多久完成。气象数据→天气预报+历史气象→预警。区块链→农产品溯源→从种植到销售全程上链→消费者扫码看全流程 / 落地场景：①贷前→遥感验证种植面积+作物类型→核实经营真实性 ②贷中→物联网监测作物长势→预警灾害→提前调整授信 ③贷后→估产→预测收入→判断还款能力 / 举一反三：农村金融的最大难点是信息不对称→农户和银行之间信息差大→卫星遥感+物联网+政府数据→补齐信息→降低风险→这是农行做三农金融的技术壁垒）

---

## 话题十：核心设计题 - 农村信贷风控系统设计（20分钟）

**面试官：农行要建一个农村信贷风控系统。支持惠农 e 贷线上审批，覆盖 5000 万农户，日均申请 10 万笔。怎么设计？**

> 你回答...

**追问1：** 先说说整体架构。从申请到放款经过哪些层？

> 你回答...（提示：整体架构 / 分层架构：
```
┌─────────────────────────────────────────────────────┐
│ 接入层：手机银行 / 微信小程序 / 客户经理PAD              │
├─────────────────────────────────────────────────────┤
│ 申请层：信息采集→基本信息+经营信息+影像资料              │
├─────────────────────────────────────────────────────┤
│ 风控层：规则引擎(准入/限额)→信用评分(模型)→反欺诈→决策    │
│         (通过/拒绝/转人工)                              │
├─────────────────────────────────────────────────────┤
│ 数据层：内部(存款/流水) + 外部(征信/土地确权/遥感/保险)   │
│        →实时特征(特征工程平台)                         │
├─────────────────────────────────────────────────────┤
│ 放款层：合同生成(e签宝)→支付(打款到惠农卡)→贷后管理      │
└─────────────────────────────────────────────────────┘
```
/ 技术选型：接入层→Spring Cloud Gateway。申请层→微服务。风控层→Drools规则引擎+模型服务(Python Flask)。数据层→Kafka实时特征+Flink流计算。放款层→流程引擎(Activiti)。5000万农户→数据量大→分库分表。日均10万申请→QPS约1-2→不高但要求稳定 →等保三级→全链路加密+审计+灾备）

**追问2：** 信用评分模型怎么做？用什么数据？为什么用 LR 而不是深度学习？

> 你回答...（提示：信用评分模型 / 评分模型数据：①内部数据→存款余额/转账流水/贷款记录(还款行为) ②征信数据→人行征信→贷款余额/逾期记录/查询次数 ③涉农数据→土地确权(亩数/类型)→补贴记录→农业保险 ④行为数据→手机银行活跃度→交易频次 ⑤遥感数据→作物面积/长势→估算产值 / 模型：LR（逻辑回归）→可解释性强（监管要求→银保监会要求模型可解释→必须能说明为什么拒绝）→或GBDT+LR→GBDT自动特征交叉→LR可解释 → 为什么不用深度学习：①监管要求可解释→深度学习是黑盒→拒绝原因说不清→合规问题 ②数据量不够→农户数据稀疏→深度学习容易过拟合 ③运维成本→深度学习需要GPU→推理慢→LR一个服务器万级QPS / 评分卡→WOE编码（Weight of Evidence）→IV值筛选特征→分箱→LR→输出分数→如600分以上通过→500-600转人工→500以下拒绝）

**追问3：** 反欺诈怎么做？多头借贷怎么发现？团伙欺诈怎么识别？

> 你回答...（提示：反欺诈 / 反欺诈：①多头借贷→查征信→多家机构贷款记录→短期多处借款→风险高→如30天内查询次数>5→多头嫌疑 ②虚假材料→OCR识别+影像比对→土地证真伪→与政府不动产系统核验 ③设备指纹→同一设备多账户申请→团伙欺诈→设备ID+IP+行为模式 ④社交网络→图数据库(Neo4j)→关联关系→如果A和B同一地址/同一手机段/互转资金→关联→一个欺诈→可能团伙 / 图数据库反欺诈：
```
农户A --[同地址]-- 农户B --[互转资金]-- 农户C
  |                                         |
  └──[同设备]-- 农户D --[同IP]-- 农户E ────┘
→ A,B,C,D,E 关联 → 如果其中一个有欺诈标记 → 其他人风险升高
```
/ 实时反欺诈→Flink流计算→实时计算设备聚集度/地址聚集度→超过阈值→拦截→转人工）

**追问4：** 贷后管理怎么做？逾期预警怎么设计？

> 你回答...（提示：贷后管理 / 贷后管理：①还款监控→每月还款日→到期未还→逾期→催收 ②风险预警→多头借贷监控→征信查询→新增贷款→风险升高→预警 ③遥感监测→作物长势→如NDVI下降→可能减产→还款能力下降→预警 ④资金监控→流水异常→大额转出→可能跑路→预警 ⑤整村监控→一个村多个逾期→可能系统性风险（如天灾）→批量处理 / 逾期预警模型→还款日前7天→预测还款概率→低→提前催收 / 催收分级：M1(1-30天)→短信/电话→M2(31-60天)→上门→M3(61-90天)→法律→M4(90天+)→核销 / 举一反三：涉农信贷的贷后特殊性→自然灾害→如旱灾/水灾→一个区域大量农户受灾→批量展期/延期→不能按城市贷款的逻辑催收→需要政策性处理→政府和银行共担风险 / 小张一句到位：三农金融核心不是技术多炫→而是数据替代→农户没有流水→用卫星+物联网+政府数据替代→把"看不见"的农户变成"看得清"的数据→这才是数字农业的真谛）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| Java 21虚拟线程（N:M映射/Continuation/IO密集适用/synchronized pinning/ReentrantLock/Semaphore限流） | 能讲清 / 讲不全 / 不会★ | |
| Caffeine本地缓存（vs Guava/W-TinyLFU/多级缓存一致性/refreshAfterWrite异步刷新） | 能讲清 / 讲不全 / 不会★ | |
| 限流算法（固定窗口/滑动窗口/漏桶/令牌桶/Sentinel LeapArray/Redis+Lua分布式限流） | 能讲清 / 讲不全 / 不会★ | |
| ZooKeeper深入（vs Nacos/ZAB协议/Watcher一次性局限/临时顺序节点分布式锁/惊群） | 能讲清 / 讲不全 / 不会★ | |
| ES倒排索引（vs B+树/IK分词器/两阶段搜索/BM25打分/深分页search_after） | 能讲清 / 讲不全 / 不会★ | |
| Java引用类型（强/软/弱/虚/WeakHashMap/ThreadLocal弱引用/虚引用堆外内存清理/可达性分析） | 能讲清 / 讲不全 / 不会★ | |
| XXL-JOB分布式调度（架构/路由策略/分片广播/失败重试告警） | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（合并有序链表/迭代+递归/合并K个最小堆/分治） | 能讲清 / 讲不全 / 不会★ | |
| 三农金融（惠农e贷/涉农信贷特殊风控/替代数据/卫星遥感/数字农业） | 能讲清 / 讲不全 / 不会★ | |
| 农村信贷风控系统设计（分层架构/评分卡LR可解释/图数据库反欺诈/贷后逾期预警） | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **Java 21虚拟线程**：N:M映射→N个VT映射到M个载体线程(ForkJoinPool)→栈在堆上(Continuation)→创建开销微秒级→百万级。轻量原理=遇到IO阻塞→VT栈从载体线程复制到堆→unmount→载体线程执行其他VT→IO完成→重新mount。适用=IO密集/请求响应模型→不适用=CPU密集/synchronized pinning(改ReentrantLock)/大量ThreadLocal(改ScopedValue)。不需要池化VT→用完即弃→但需Semaphore限制下游并发。`Executors.newVirtualThreadPerTaskExecutor()`+`Semaphore(200)`。synchronized会pin VT→`-Djdk.tracePinnedThreads=full`排查→改ReentrantLock
> 2. **Caffeine**：本地缓存→Spring Boot默认→vs Guava=W-TinyLFU(比LRU高30%命中率)+异步+RingBuffer无锁。W-TinyLFU=Window(1%新数据隔离)+Main(99%:Probation20%+Protection80%)+TinyLFU(Count-Min Sketch估算频率)→抗扫描冲刷+频率+近因。多级缓存=Caffeine(L1,30s)+Redis(L2,30min)+MQ广播清L1→TTL兜底+MQ实时。refreshAfterWrite=到期不阻塞→返回旧值→后台异步刷新→vs expireAfterWrite=到期清除→下次get阻塞→最佳=refresh(短)+expire(长)
> 3. **限流算法**：固定窗口(临界突刺)→滑动窗口(Sentinel LeapArray/N个小格子)→漏桶(恒定速率/不允许突发/保护下游)→令牌桶(允许突发/入口限流)。Guava RateLimiter=令牌桶→SmoothBursty突发+SmoothWarmup预热。Sentinel=LeapArray滑动窗口+匀速排队(类漏桶)。分布式=Redis+Lua令牌桶(HMSET last_time+tokens+时间差补充+半数不要求→Redis单线程原子)→万级QPS→更高用本地令牌桶+Redis校准
> 4. **ZooKeeper**：CP模型→ZAB协议(消息广播=简化2PC半数ACK+崩溃恢复=ZXID最大者当选)。vs Nacos=CP vs AP+CP/Watcher一次性 vs UDP推送/配置不友好 vs 原生。Watcher=一次性+轻量(不通知内容)+串行→局限=重新注册间隙漏通知→Curator NodeCache自动重注册。分布式锁=临时顺序节点→每个监听前一个→不惊群(vs临时节点直接锁=所有等同时唤醒=惊群)→Curator InterProcessMutex封装→vs Redis=CP强一致但慢 vs AP快
> 5. **ES倒排索引**：Term→文档ID列表→全文检索快。vs B+树=模糊搜索 vs 精确/分词 vs 不分词/重建慢 vs B+树快。IK分词=ik_max_word(索引/多分词/召回)+ik_smart(搜索/少分词/精确)。两阶段搜索=Query Phase(各Shard返回docID+score→协调合并排序TopN)+Fetch Phase(取TopN的文档内容)。BM25=TF饱和+IDF逆文档频率+文档长度归一。深分页=from+size≤10000→search_after(上一页sort值→不能跳页)或Scroll(快照→批量导出)
> 6. **Java引用类型**：强(不回收/OOM也不)→软(内存不足回收/缓存)→弱(下次GC回收/WeakHashMap/ThreadLocal key)→虚(get()=null/不影响生命周期/对象回收时入ReferenceQueue/堆外内存Cleaner)。ThreadLocalMap的Entry key=弱引用(防ThreadLocal泄漏)但value=强引用(不remove则泄漏→必须remove)。可达性分析=强引用链可达不回收→软引用看内存→弱引用下次GC→虚引用不影响。DirectByteBuffer+Cleaner=被GC→Cleaner入队→后台释放堆外内存
> 7. **XXL-JOB**：调度中心(Admin独立部署)+执行器(嵌入应用)→HTTP通信。防重复=调度中心单点+DB锁。路由策略10种(ROUND/FAILOVER/SHARDING_BROADCAST等)。分片广播=所有执行器都执行但各处理id%shardTotal==shardIdx的数据→并行。失败=重试retryCount+告警钉钉+日志保留30天。踩坑=任务幂等+超时kill可能不一致→断点续传+执行器离线FAILOVER+日志积压定期清理
> 8. **合并有序链表**：迭代法=哨兵dummy+双指针取较小→O(n+m)时间O(1)空间。递归=较小.next=递归合并剩余→O(n+m)栈空间。合并K个=最小堆(K个头节点入堆→取最小→下一个入堆→O(Nlogk))或分治(两两合并→O(Nlogk))。K大用分治(常数因子小)
> 9. **三农金融**：三农=农村/农业/农民。农行业务=惠农e贷(5-30万信用贷)+农户贷款+涉农企业贷+数字农业平台+补贴发放。特殊风控=数据少(替代数据:土地确权/补贴/遥感)+风险高(天灾)+地域分散(线上化)+抵押特殊(土地经营权)。数字农业=卫星遥感(NDVI作物长势)+物联网(智能农机GPS)+区块链(农产品溯源)。农村金融核心=信息不对称→技术补齐信息
> 10. **农村信贷风控系统**：五层=接入(手机/小程序/PAD)→申请(信息采集)→风控(规则引擎Drools+评分卡LR+反欺诈图数据库)→数据(内部+外部征信+遥感+实时特征Flink)→放款(合同e签宝+支付+贷后)。评分卡=LR(可解释/监管要求)+WOE编码+IV筛选。反欺诈=多头借贷(征信查询次数)+虚假材料(OCR+政府核验)+设备指纹+图数据库(Neo4j关联团伙)。贷后=还款监控+遥感预警+资金监控+整村监控+逾期分级催收(M1短信→M4核销)。等保三级→全链路加密+审计+灾备
