# 限流算法 + IO模型/Netty/Reactor 底层原理深度解析

> 本文从底层原理出发，系统解析限流四大经典算法、分布式限流实践，以及 IO 模型演进与 Reactor/Netty 的架构实现，让你不翻源码也能彻底搞懂这两大核心基础设施。

---

## 目录

- [第一篇：限流算法底层原理](#第一篇限流算法底层原理)
  - [一、为什么需要限流](#一为什么需要限流)
  - [二、固定窗口计数器](#二固定窗口计数器)
  - [三、滑动窗口计数器](#三滑动窗口计数器)
  - [四、漏桶算法](#四漏桶算法)
  - [五、令牌桶算法](#五令牌桶算法)
  - [六、四种算法对比与选型](#六四种算法对比与选型)
  - [七、分布式限流：Redis + Lua](#七分布式限流redis--lua)
  - [八、Sentinel 限流源码级解析](#八sentinel-限流源码级解析)
- [第二篇：IO模型/Netty/Reactor底层原理](#第二篇io模型nettyreactor底层原理)
  - [九、IO模型演进五阶段](#九io模型演进五阶段)
  - [十、select / poll / epoll 底层实现](#十select--poll--epoll-底层实现)
  - [十一、Reactor 模式三种架构](#十一reactor-模式三种架构)
  - [十二、Netty 如何实现 Reactor](#十二netty-如何实现-reactor)
  - [十三、Netty NIO EventLoop 源码解析](#十三netty-nio-eventloop-源码解析)
  - [十四、Netty Pipeline 与 ChannelHandler](#十四netty-pipeline-与-channelhandler)
- [十五、面试高频问题与标准回答](#十五面试高频问题与标准回答)

---

# 第一篇：限流算法底层原理

## 一、为什么需要限流

### 1.1 限流的核心目的

```
限流 = 控制单位时间内的请求/流量数量，保护系统不被过载冲垮

三大保护维度：
  ┌──────────────────────────────────────────────────┐
  │ 1. 保护自己：防止突发流量压垮服务                    │
  │    → QPS 超过系统承载力 → 响应变慢 → OOM → 宕机    │
  │                                                    │
  │ 2. 保护下游：防止自己把下游服务打爆                  │
  │    → 批量调用第三方API → 对方限流/封禁              │
  │                                                    │
  │ 3. 保护共享资源：防止某一方占用过多资源              │
  │    → 某租户QPS暴增 → 其他租户无资源可用             │
  └──────────────────────────────────────────────────┘
```

### 1.2 限流的层级

```
                    流量进入方向 →
                    
  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐
  │ DNS层   │→│ CDN层   │→│ Nginx层 │→│ Gateway │→│ 应用层  │
  │限流     │  │限流     │  │限流     │  │限流     │  │限流     │
  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘
  
  DNS层：     域名解析级别的流量调度（GSLB）
  CDN层：     边缘节点的请求频率控制
  Nginx层：   limit_req / limit_conn（漏桶/连接数限制）
  Gateway层： Spring Cloud Gateway + Sentinel
  应用层：    Semaphore / RateLimiter / 自研限流器
```

### 1.3 限流的关键指标

| 指标 | 全称 | 含义 |
|------|------|------|
| **QPS** | Queries Per Second | 每秒请求数（限流最常用指标） |
| **TPS** | Transactions Per Second | 每秒事务数 |
| **RPS** | Requests Per Second | 每秒请求数 |
| **并发数** | Concurrency | 同时处理的请求数量 |
| **RT** | Response Time | 响应时间 |

---

## 二、固定窗口计数器

### 2.1 原理

```
固定窗口 = 将时间划分为固定长度的窗口，每个窗口内独立计数

  时间轴 →
  ┌─────────┬─────────┬─────────┬─────────┐
  │ 0-60s  │ 60-120s │120-180s │180-240s │
  │ 窗口1  │ 窗口2   │ 窗口3   │ 窗口4   │
  │ 计数=23│ 计数=45 │ 计数=38 │ 计数=20 │
  └─────────┴─────────┴─────────┴─────────┘
  
  限流阈值 = 50 QPS
  窗口1：23 < 50 → 通过
  窗口2：45 < 50 → 通过
  窗口3：38 < 50 → 通过
  窗口4：20 < 50 → 通过
```

### 2.2 实现

```java
// 固定窗口计数器实现
public class FixedWindowRateLimiter {

    private final long windowSize;        // 窗口大小（毫秒）
    private final int maxRequests;        // 窗口内最大请求数
    private long windowStart;             // 当前窗口起始时间
    private int counter;                  // 当前窗口计数器

    public FixedWindowRateLimiter(long windowSizeMs, int maxRequests) {
        this.windowSize = windowSizeMs;
        this.maxRequests = maxRequests;
        this.windowStart = System.currentTimeMillis();
        this.counter = 0;
    }

    public boolean tryAcquire() {
        long now = System.currentTimeMillis();

        // 检查是否进入新窗口
        if (now - windowStart >= windowSize) {
            windowStart = now;   // 重置窗口起始时间
            counter = 0;         // 重置计数器
        }

        // 判断是否超过阈值
        if (counter < maxRequests) {
            counter++;
            return true;   // 允许通过
        }
        return false;      // 拒绝请求
    }
}
```

### 2.3 致命问题：临界突发效应

```
固定窗口的临界问题：

  时间轴 →
  ┌─────────┬─────────┐
  │ 0-60s  │ 60-120s │
  │ 窥口1  │ 窥口2   │
  └─────────┴─────────┘

  实际请求分布：
       50请求 ↓                  ↓ 50请求
  ┌───────────────┬───────────────────┐
  │ 0-60s        │ 60-120s          │
  │ 前30s:0请求  │ 60s瞬间:50请求   │
  │ 59s瞬间:50请求│ 61s瞬间:50请求 │
  └───────────────┴───────────────────┘

  窗口1尾部(59s)：50请求 → 通过（≤阈值）
  窗口2头部(61s)：50请求 → 通过（≤阈值）
  
  但在 59s-61s 这 2秒内 → 100请求通过！
  → 系统瞬间承受2倍流量 → 可能被打爆！

  根因：窗口边界处两个窗口各自合法，但合并后超限
```

---

## 三、滑动窗口计数器

### 3.1 原理

```
滑动窗口 = 窗口不是固定的，而是随时间滑动

  固定窗口（窗口边界是硬的）：
  ┌─────────┬─────────┐
  │ 窗口1   │ 窗口2   │  ← 边界固定在0s和60s
  └─────────┴─────────┘

  滑动窗口（窗口边界是滑动的）：
       ┌──────────────────┐ ← 当前窗口覆盖 [now-60s, now]
       │ 滑动窗口         │ ← 随时间不断向右滑动
       └──────────────────┘

  任意时刻检查：过去60秒内的请求总数 ≤ 阈值
  → 不会出现"两个窗口各合法但合并超限"的问题
```

### 3.2 细粒度滑动窗口（子窗口方案）

```
将一个大窗口划分为多个小子窗口，滑动时逐个子窗口移动

  60秒窗口，划分为6个10秒子窗口：

  子窗口: [0-10] [10-20] [20-30] [30-40] [40-50] [50-60]
  计数:    3      5       8       12      15      7
  总计: 3+5+8+12+15+7 = 50 ≤ 100 → 通过

  滑动到 [10-70]：
  子窗口: [10-20] [20-30] [30-40] [40-50] [50-60] [60-70]
  计数:    5       8       12      15      7       20
  总计: 5+8+12+15+7+20 = 67 ≤ 100 → 通过

  关键：始终检查"当前窗口范围内所有子窗口的总和"
  → 窗口边界问题被子窗口粒度消解
```

### 3.3 实现

```java
// 滑动窗口计数器实现（子窗口方案）
public class SlidingWindowRateLimiter {

    private final int windowSizeMs;       // 大窗口大小（毫秒）
    private final int subWindowCount;     // 子窗口数量
    private final int maxRequests;        // 大窗口内最大请求数
    private final int subWindowSizeMs;    // 子窗口大小
    private final int[] counters;         // 各子窗口的计数器
    private long windowStart;             // 大窗口起始时间

    public SlidingWindowRateLimiter(int windowSizeMs, int subWindowCount, int maxRequests) {
        this.windowSizeMs = windowSizeMs;
        this.subWindowCount = subWindowCount;
        this.maxRequests = maxRequests;
        this.subWindowSizeMs = windowSizeMs / subWindowCount;
        this.counters = new int[subWindowCount];
        this.windowStart = System.currentTimeMillis();
    }

    public boolean tryAcquire() {
        long now = System.currentTimeMillis();

        // 计算当前子窗口索引
        int currentIndex = (int) ((now - windowStart) / subWindowSizeMs) % subWindowCount;

        // 计算需要滑动的子窗口数（从上次到现在经过的子窗口数）
        long elapsedWindows = (now - windowStart) / subWindowSizeMs;
        long lastWindowStart = windowStart;
        windowStart = now - (now - windowStart) % subWindowSizeMs;

        // 重置过期子窗口的计数器
        long windowsToClear = elapsedWindows - subWindowCount + 1;
        if (windowsToClear > 0) {
            for (int i = 0; i < Math.min(windowsToClear, subWindowCount); i++) {
                int clearIndex = (int) ((lastWindowStart / subWindowSizeMs + i) % subWindowCount);
                counters[clearIndex] = 0;
            }
        }

        // 计算当前大窗口内的总请求数
        int totalRequests = 0;
        for (int counter : counters) {
            totalRequests += counter;
        }

        // 判断是否超过阈值
        if (totalRequests < maxRequests) {
            counters[currentIndex]++;
            return true;
        }
        return false;
    }
}
```

### 3.4 滑动窗口的优势

```
与固定窗口对比：

  场景：60秒内限制100请求

  固定窗口临界问题：
    59s: 50请求 → 通过
    61s: 50请求 → 通过
    59s-61s共100请求 → 2秒内承受2倍流量

  滑动窗口解决方案：
    59s时刻 → 检查[59s-60s前]的总请求数
    → 如果过去60秒内已达100 → 拒绝
    → 不会出现边界突发问题

  但注意：
    滑动窗口只是比固定窗口更平滑
    仍然无法处理"匀速到达"的精确控制
    → 漏桶和令牌桶解决的是匀速问题
```

---

## 四、漏桶算法

### 4.1 原理

```
漏桶 = 无论进水多快，出水始终匀速

  ┌──────────────────────────────────────┐
  │                漏桶                   │
  │                                      │
  │  突发请求 ──→ ┌─────────┐            │
  │  (不规则)      │         │            │
  │                │  桶中   │ ──→ 匀速流出│
  │                │  水量   │    (恒定速率)│
  │                │         │            │
  │                └────┬────┘            │
  │                     │                 │
  │               桶满 → 溢出(拒绝)       │
  │                                      │
  └──────────────────────────────────────┘

  核心参数：
    · 桶容量（burst capacity）：桶最多存多少水
    · 流出速率（leak rate）：每秒恒定流出多少水
    · 进水：请求到来 → 加入桶中
    · 桶满：溢出 → 拒绝请求
    · 桶未满：排队等待 → 以恒定速率被处理
```

### 4.2 实现

```java
// 漏桶算法实现
public class LeakyBucketRateLimiter {

    private final int capacity;           // 桶容量（最多缓存多少请求）
    private final double leakRate;        // 流出速率（每秒流出多少请求）
    private double water;                 // 当前桶中水量
    private long lastLeakTime;            // 上次漏水时间

    public LeakyBucketRateLimiter(int capacity, double leakRatePerSec) {
        this.capacity = capacity;
        this.leakRate = leakRatePerSec;
        this.water = 0;
        this.lastLeakTime = System.currentTimeMillis();
    }

    public boolean tryAcquire() {
        long now = System.currentTimeMillis();

        // 1. 先漏水：计算从上次到现在流出了多少水
        double elapsedSec = (now - lastLeakTime) / 1000.0;
        double leakedWater = elapsedSec * leakRate;
        water = Math.max(0, water - leakedWater);  // 水量不能为负
        lastLeakTime = now;

        // 2. 判断桶是否已满
        if (water < capacity) {
            water += 1;    // 加一滴水（一个请求）
            return true;   // 桶未满 → 允许进入（排队等待匀速流出）
        }
        return false;      // 桶已满 → 溢出拒绝
    }
}
```

### 4.3 漏桶的特性

```
特性1：强制匀速输出
  ┌──────────────────────────────────────────────────┐
  │ 输入：不规则突发流量                                │
  │   ──┬──┬──┬──┬──┬──┬──┬──────────┬──┬──┬──      │
  │     ↓  ↓  ↓  ↓  ↓  ↓  ↓         ↓  ↓  ↓        │
  │                                                    │
  │ 漏桶处理后：                                        │
  │   ──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──        │
  │     ↓  ↓  ↓  ↓  ↓  ↓  ↓  ↓  ↓  ↓  ↓  ↓         │
  │   匀速流出，每秒固定速率                             │
  └──────────────────────────────────────────────────┘

特性2：不允许突发
  即使桶中有10个请求排队，流出速率仍然是恒定的
  → 无法在短时间内处理突发流量
  → 对需要"允许短暂突发"的场景不友好

特性3：请求排队等待
  桶未满时请求进入排队，等待匀速被处理
  → 响应时间可能变长（排队延迟）
```

---

## 五、令牌桶算法

### 5.1 原理

```
令牌桶 = 桶中匀速生成令牌，请求消耗令牌，无令牌则拒绝

  ┌──────────────────────────────────────┐
  │              令牌桶                    │
  │                                      │
  │        ┌─── 令牌生成 ───┐            │
  │        │ (匀速放入令牌) │            │
  │        └──→ ┌─────────┐ ←── 请求来  │
  │             │         │     消耗令牌 │
  │             │  令牌桶  │             │
  │             │ (最多N个)│ ──→ 有令牌? │
  │             │         │     Yes→通过│
  │             └─────────┘     No→拒绝  │
  │                                      │
  └──────────────────────────────────────┘

  核心参数：
    · 桶容量（maxTokens）：桶最多存多少令牌
    · 令牌生成速率（tokenRate）：每秒生成多少令牌
    · 请求到来 → 消耗1个令牌 → 通过
    · 无令牌 → 拒绝
    · 令牌可积累 → 空闲时桶满 → 突发时一次性消耗大量令牌
```

### 5.2 令牌桶的关键：允许突发

```
与漏桶的核心区别：

  漏桶：强制匀速流出 → 不允许任何突发
  令牌桶：令牌可积累 → 允许短暂突发

  场景：桶容量=100，令牌速率=10/s

  空闲10秒：
    令牌生成: 10/s × 10s = 100 → 桶满
    突发100请求 → 消耗100令牌 → 全部通过！
    → 允许瞬间处理100个请求

  但长期看：
    突发后桶空 → 后续只能 10/s 通过
    → 平均速率不超过 10/s

  这就是令牌桶的精髓：
    长期平均速率受限（≤ tokenRate）
    短期允许突发（≤ maxTokens）
```

### 5.3 实现

```java
// 令牌桶算法实现
public class TokenBucketRateLimiter {

    private final int maxTokens;          // 桶最大令牌数
    private final double tokenRate;       // 令牌生成速率（每秒）
    private double tokens;                // 当前令牌数
    private long lastRefillTime;          // 上次填充时间

    public TokenBucketRateLimiter(int maxTokens, double tokenRatePerSec) {
        this.maxTokens = maxTokens;
        this.tokenRate = tokenRatePerSec;
        this.tokens = maxTokens;          // 初始桶满
        this.lastRefillTime = System.currentTimeMillis();
    }

    public boolean tryAcquire() {
        long now = System.currentTimeMillis();

        // 1. 填充令牌：计算从上次到现在生成的令牌数
        double elapsedSec = (now - lastRefillTime) / 1000.0;
        double newTokens = elapsedSec * tokenRate;
        tokens = Math.min(maxTokens, tokens + newTokens);  // 不超过桶容量
        lastRefillTime = now;

        // 2. 判断是否有令牌
        if (tokens >= 1) {
            tokens -= 1;     // 消耗1个令牌
            return true;     // 有令牌 → 通过
        }
        return false;        // 无令牌 → 拒绝
    }

    // 支持一次消耗多个令牌（批量请求场景）
    public boolean tryAcquire(int permits) {
        long now = System.currentTimeMillis();

        double elapsedSec = (now - lastRefillTime) / 1000.0;
        double newTokens = elapsedSec * tokenRate;
        tokens = Math.min(maxTokens, tokens + newTokens);
        lastRefillTime = now;

        if (tokens >= permits) {
            tokens -= permits;
            return true;
        }
        return false;
    }
}
```

### 5.4 Google Guava RateLimiter 源码解析

Guava 的 `RateLimiter` 是令牌桶的工业级实现，核心类是 `SmoothRateLimiter`。

```java
// Guava RateLimiter 核心源码（简化版）

public abstract class SmoothRateLimiter extends RateLimiter {

    // 两个子类：
    // SmoothBursty：允许突发（令牌桶，存储令牌最多1秒的量）
    // SmoothWarmingUp：预热期（冷启动时速率从低到高渐增）

    // 核心字段
    double storedPermits;         // 当前存储的令牌数
    double maxPermits;            // 最大令牌数
    double stableIntervalMicros;  // 稳定期间两个令牌之间的微秒间隔
    long nextFreeTicketMicros;    // 下一个可用令牌的时间（微秒）

    // 预存令牌填充
    void resync(long nowMicros) {
        // 如果当前时间已超过 nextFreeTicketMicros
        if (nowMicros > nextFreeTicketMicros) {
            // 计算新生成的令牌数
            double newPermits = (nowMicros - nextFreeTicketMicros) / stableIntervalMicros;
            storedPermits = Math.min(maxPermits, storedPermits + newPermits);
            nextFreeTicketMicros = nowMicros;
        }
    }

    // 获取令牌核心方法
    final long reserveNextTicket(double storedPermitsToConsume, double freshPermits) {
        // 1. 消耗存储的令牌
        storedPermits -= storedPermitsToConsume;

        // 2. 计算需要等待的时间
        //    存储令牌消耗 = 0等待时间（已有令牌）
        //    新生成令牌 = 需要等待 stableIntervalMicros × freshPermits
        long waitMicros = storedPermitsToWaitTime(storedPermitsToConsume)
                        + (long) (freshPermits * stableIntervalMicros);

        // 3. 更新下一个可用令牌时间
        nextFreeTicketMicros += waitMicros;

        return nextFreeTicketMicros;
    }

    // tryAcquire 核心流程
    public boolean tryAcquire(int permits, long timeout, TimeUnit unit) {
        long timeoutMicros = unit.toMicros(timeout);
        long nowMicros = readSafeMicros();

        // 1. 填充令牌
        resync(nowMicros);

        // 2. 计算可用令牌
        double storedPermitsToConsume = Math.min(storedPermits, permits);
        double freshPermits = permits - storedPermitsToConsume;

        // 3. 计算等待时间
        long waitMicros = reserveNextTicket(storedPermitsToConsume, freshPermits);

        // 4. 判断是否超时
        if (waitMicros <= timeoutMicros + nowMicros) {
            // 未超时 → 可以获取令牌
            return true;
        }
        // 超时 → 无法获取
        return false;
    }

    // SmoothBursty 的存储令牌消耗时间计算
    // 存储令牌消耗时间为0 → 突发请求直接消耗存储令牌，无等待
    @Override
    double storedPermitsToWaitTime(double storedPermits) {
        return 0;  // ← 关键：存储的令牌不产生等待时间！
    }

    // SmoothWarmingUp 的存储令牌消耗时间计算
    // 冷启动时消耗存储令牌需要等待（预热期）
    @Override
    double storedPermitsToWaitTime(double storedPermits) {
        // 预热曲线：storedPermits 越多（越冷）→ 等待时间越长
        double thresholdPermits = maxPermits * 0.5;  // 阈值
        if (storedPermits <= thresholdPermits) {
            // 稳定区 → 等待时间接近 stableIntervalMicros
            return storedPermits * stableIntervalMicros;
        } else {
            // 预热区 → 等待时间更长（冷启动保护）
            double aboveThreshold = storedPermits - thresholdPermits;
            return (long) (aboveThreshold * warmupIntervalMicros + thresholdPermits * stableIntervalMicros);
        }
    }
}
```

**Guava RateLimiter 的关键设计**：

```
关键1：nextFreeTicketMicros（预支机制）
  ┌──────────────────────────────────────────────────┐
  │ 传统令牌桶：每次 tryAcquire → 实际等待令牌生成    │
  │                                                    │
  │ Guava RateLimiter：预支机制                        │
  │                                                    │
  │ 场景：令牌速率=5/s，桶中有3个存储令牌              │
  │   请求1需要5个令牌：                               │
  │     消耗3个存储令牌（0等待）                       │
  │     消耗2个新生成令牌（需等2×200ms=400ms）         │
  │     nextFreeTicketMicros += 400ms                  │
  │                                                    │
  │   请求2到达（立即）：                              │
  │     当前令牌=0，需要等到 nextFreeTicketMicros      │
  │     如果允许等待 → 消耗令牌，nextFreeTicketMicros  │
  │     继续往后推                                     │
  │                                                    │
  │   关键：请求1"预支"了2个令牌 → 请求2需要等请求1    │
  │   的令牌全部生成后才能获取                          │
  │                                                    │
  │   效果：平均速率严格控制在5/s                       │
  │   突发请求会"预支"未来令牌 → 后续请求需要等待       │
  └──────────────────────────────────────────────────┘

关键2：SmoothBursty vs SmoothWarmingUp
  SmoothBursty：存储令牌消耗时间为0 → 允许突发
    → 适合：API限流（大多数场景）
  
  SmoothWarmingUp：存储令牌消耗需要等待 → 冷启动保护
    → 适合：数据库连接池、远程服务调用（冷启动时避免瞬间打爆下游）
    
    预热曲线：
    等待时间 ─────────────→
      高  │          ╱  ← 预热区（冷启动）
          │        ╱
          │      ╱    ← 阈值
          │    ╱
      低  │──╱      ← 稳定区
          └──────────────
          0   threshold   maxPermits
          存储令牌数 →
```

---

## 六、四种算法对比与选型

### 6.1 对比表

| 维度 | 固定窗口 | 滑动窗口 | 漏桶 | 令牌桶 |
|------|---------|---------|------|--------|
| **突发容忍** | ❌（临界突发） | ⚠️（子窗口粒度内可） | ❌（强制匀速） | ✅（令牌积累允许突发） |
| **匀速输出** | ❌ | ❌ | ✅（恒定速率流出） | ⚠️（突发时不匀速） |
| **精度** | 低（窗口边界问题） | 中（子窗口粒度） | 高（毫秒级匀速） | 高（毫秒级令牌） |
| **实现复杂度** | 低 | 中 | 低 | 中 |
| **内存开销** | O(1) | O(子窗口数) | O(1) | O(1) |
| **适用场景** | 简单限流 | 精确限流 | 匀速消费场景 | API限流（最常用） |

### 6.2 选择指南

```
API限流（对外接口）：
  → 令牌桶（允许突发 + 长期平均速率受限）
  → Guava RateLimiter / Sentinel

匀速消费（消息队列消费速率控制）：
  → 漏桶（强制匀速，防止下游被打爆）
  → Nginx limit_req

精确统计（监控 + 计费）：
  → 滑动窗口（精度最高，可统计QPS趋势）
  → Sentinel滑动窗口

简单场景（内部服务粗粒度限流）：
  → 固定窗口（实现最简单）
  → Redis INCR + EXPIRE
```

### 6.3 漏桶 vs 令牌桶的终极对比

```
         ┌──────────────────────────────────────────┐
         │                漏桶                      │
         │  输入： ─┬──┬──┬──┬──┬──┬────────        │
         │          ↓  ↓  ↓  ↓  ↓  ↓               │
         │  输出： ─┬──┬──┬──┬──┬──┬──┬──┬──       │
         │          ↓  ↓  ↓  ↓  ↓  ↓  ↓  ↓  ↓      │
         │  特点：强制匀速输出，完全平滑              │
         │  缺点：无法处理突发，多余请求被浪费         │
         └──────────────────────────────────────────┘

         ┌──────────────────────────────────────────┐
         │              令牌桶                       │
         │  输入： ─┬──┬──┬──┬──┬──┬────────        │
         │          ↓  ↓  ↓  ↓  ↓  ↓               │
         │  输出： ─┬──────────┬──┬──┬──┬──        │
         │          ↓ (突发)    ↓  ↓  ↓  ↓  ↓      │
         │  特点：允许突发（消耗积累令牌）             │
         │  缺点：突发时下游可能瞬间承受压力           │
         └──────────────────────────────────────────┘

  关键区别：
    漏桶 = 保护下游（匀速输出，下游不会被打爆）
    令牌桶 = 保护自己（允许突发，用户体验更好）
    
  实际选型：
    保护下游 → 漏桶（Nginx limit_req, MQ消费限速）
    保护自己 → 令牌桶（API限流, Guava RateLimiter, Sentinel）
```

---

## 七、分布式限流：Redis + Lua

### 7.1 为什么需要分布式限流

```
单机限流的问题：
  ┌──────┐  ┌──────┐  ┌──────┐
  │ 实例1 │  │ 实例2 │  │ 实例3 │  ← 3个服务实例
  │ 50QPS│  │ 50QPS│  │ 50QPS│  ← 各自限流50
  └──────┘  └──────┘  └──────┘
  
  单机总和: 150QPS
  但全局要求: 100QPS → 超限50QPS！

  根因：各实例独立计数 → 无法协调全局总量

  解决：共享计数器 → Redis
```

### 7.2 Redis + Lua 固定窗口限流

```lua
-- Redis + Lua 固定窗口限流脚本
-- KEYS[1] = 限流key（如 "rate_limit:api:/order"）
-- ARGV[1] = 窗口大小（秒）
-- ARGV[2] = 最大请求数

local key = KEYS[1]
local window = tonumber(ARGV[1])
local max_count = tonumber(ARGV[2])

-- 获取当前计数
local current = tonumber(redis.call('GET', key) or "0")

if current >= max_count then
    -- 超限 → 拒绝
    return 0
end

-- 未超限 → 计数+1 并设置过期时间
current = redis.call('INCR', key)
if current == 1 then
    -- 第一次请求 → 设置过期时间（窗口到期自动清除）
    redis.call('EXPIRE', key, window)
end

return 1  -- 允许通过
```

```java
// Java 调用 Redis + Lua 限流
public class RedisFixedWindowRateLimiter {

    private final RedisTemplate redisTemplate;
    private final DefaultRedisScript<Long> script;

    public RedisFixedWindowRateLimiter(RedisTemplate redisTemplate) {
        this.redisTemplate = redisTemplate;
        this.script = new DefaultRedisScript<>();
        this.script.setScriptSource(new ResourceScriptSource(
            new ClassPathResource("lua/fixed_window_rate_limit.lua")));
        this.script.setResultType(Long.class);
    }

    public boolean tryAcquire(String key, int windowSeconds, int maxRequests) {
        Long result = (Long) redisTemplate.execute(script,
            Collections.singletonList(key),
            String.valueOf(windowSeconds),
            String.valueOf(maxRequests));
        return result != null && result == 1;
    }
}
```

### 7.3 Redis + Lua 滑动窗口限流

```lua
-- Redis + Lua 滺动窗口限流（基于 Sorted Set + 时间戳）
-- KEYS[1] = 限流key
-- ARGV[1] = 窗口大小（毫秒）
-- ARGV[2] = 最大请求数
-- ARGV[3] = 当前时间戳（毫秒）
-- ARGV[4] = 唯一请求ID（用于去重）

local key = KEYS[1]
local window_ms = tonumber(ARGV[1])
local max_count = tonumber(ARGV[2])
local now_ms = tonumber(ARGV[3])
local request_id = ARGV[4]

-- 1. 移除窗口外的旧记录
local window_start = now_ms - window_ms
redis.call('ZREMRANGEBYSCORE', key, '-inf', window_start)

-- 2. 统计当前窗口内的请求数
local current_count = redis.call('ZCARD', key)

if current_count >= max_count then
    -- 超限 → 拒绝
    return 0
end

-- 3. 加入当前请求（score=时间戳, value=请求ID）
redis.call('ZADD', key, now_ms, request_id)

-- 4. 设置key过期时间（防止僵尸数据）
redis.call('PEXPIRE', key, window_ms + 1000)

return 1  -- 允许通过
```

**滑动窗口的 Sorted Set 方案原理**：

```
  Sorted Set 存储结构：
    key = "rate_limit:api:/order"
    score = 请求时间戳（毫秒）
    value = 请求唯一ID（UUID）

  时间轴 →
  ┌──────────────────────────────────────┐
  │  now-60s                             │  now
  │  ├── req_a (ts=now-55s)             │  ├── req_e (ts=now-3s)
  │  ├── req_b (ts=now-40s)             │  ├── req_f (ts=now-1s)
  │  ├── req_c (ts=now-30s)             │  ├── req_g (ts=now) ← 新加入
  │  ├── req_d (ts=now-20s)             │
  └──────────────────────────────────────┘

  ZREMRANGEBYSCORE: 移除 score < (now-60s) 的记录
  → 清除窗口外的 req_a 等旧记录

  ZCARD: 统计剩余记录数 → 当前窗口请求数
  
  → 精确的滑动窗口，无边界问题
```

### 7.4 Redis + Lua 令牌桶限流

```lua
-- Redis + Lua 令牌桶限流脚本
-- KEYS[1] = 令牌桶key
-- ARGV[1] = 桶最大令牌数
-- ARGV[2] = 令牌生成速率（每秒）
-- ARGV[3] = 当前时间戳（秒）
-- ARGV[4] = 请求消耗令牌数

local key = KEYS[1]
local max_tokens = tonumber(ARGV[1])
local rate = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local requested = tonumber(ARGV[4])

-- 获取桶状态
local bucket = redis.call('HMGET', key, 'tokens', 'last_time')
local tokens = tonumber(bucket[1]) or max_tokens  -- 初始桶满
local last_time = tonumber(bucket[2]) or now

-- 计算新生成的令牌
local elapsed = math.max(0, now - last_time)
local new_tokens = elapsed * rate
tokens = math.min(max_tokens, tokens + new_tokens)

-- 判断是否有足够令牌
if tokens < requested then
    -- 令牌不足 → 拒绝
    redis.call('HMSET', key, 'tokens', tokens, 'last_time', now)
    return 0
end

-- 消耗令牌
tokens = tokens - requested
redis.call('HMSET', key, 'tokens', tokens, 'last_time', now)
redis.call('EXPIRE', key, math.ceil(max_tokens / rate) + 10)

return 1  -- 允许通过
```

### 7.5 Lua 保证原子性

```
为什么必须用 Lua？

  方案A：多条Redis命令（非原子）
    GET key → 检查 → INCR key → EXPIRE key
    → 并发请求时 INCR 和 EXPIRE 之间可能被打断
    → 计数不准确

  方案B：Lua脚本（原子）
    Redis 执行 Lua 脚本时：
    1. 整个脚本作为一个原子命令执行
    2. 执行期间不会被其他命令打断
    3. 单线程执行 → 保证一致性

  → 分布式限流必须用 Lua 脚本保证原子性
```

---

## 八、Sentinel 限流源码级解析

### 8.1 Sentinel 概述

Sentinel 是阿里开源的流量防护组件，核心能力：
- **限流**（Flow Control）
- **熔断降级**（Circuit Breaking）
- **系统保护**（System Protection）

### 8.2 Sentinel 核心架构

```
  ┌──────────────────────────────────────────────────────┐
  │              Sentinel 核心处理链                       │
  │                                                        │
  │  Entry → Slot Chain → Entry                           │
  │                                                        │
  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐ │
  │  │Node     │→│Cluster  │→│Flow     │→│Degrade  │ │
  │  │Selector │  │Builder  │  │Slot     │  │Slot     │ │
  │  │Slot     │  │Slot     │  │         │  │         │ │
  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘ │
  │     ↓             ↓            ↓            ↓        │
  │  构建统计节点   构建集群统计   限流检查     熔断检查   │
  │                                                        │
  │  ┌─────────┐  ┌─────────┐  ┌─────────┐               │
  │  │System   │→│Authority │→│Statistic │               │
  │  │Slot     │  │Slot     │  │Slot     │               │
  │  │         │  │         │  │         │               │
  │  └─────────┘  └─────────┘  └─────────┘               │
  │     ↓            ↓            ↓                       │
  │  系统保护      授权控制      统计数据采集               │
  └──────────────────────────────────────────────────────┘
```

### 8.3 Sentinel 限流核心：FlowSlot

```java
// FlowSlot — Sentinel 限流检查的核心 Slot
public class FlowSlot extends AbstractLinkedProcessorSlot<DefaultNode> {

    private final FlowRuleChecker checker;

    @Override
    public void entry(Context context, ResourceWrapper resourceWrapper,
                      DefaultNode node, int count, boolean prioritized,
                      Object... args) throws Throwable {

        // 检查所有限流规则
        checkFlow(resourceWrapper, context, node, count, prioritized);

        // 通过 → 继续下一个 Slot
        fireEntry(context, resourceWrapper, node, count, prioritized, args);
    }

    void checkFlow(ResourceWrapper resource, Context context,
                    DefaultNode node, int count, boolean prioritized) {

        // 获取该资源的所有限流规则
        Collection<FlowRule> rules = FlowRuleManager.getRulesForResource(resource.getName());

        for (FlowRule rule : rules) {
            if (!checker.canPassCheck(rule, context, node, count, prioritized)) {
                // 限流触发 → 抛出 FlowException
                throw new FlowException(rule.getLimitApp(), rule);
            }
        }
    }
}
```

### 8.4 Sentinel 四种限流算法实现

#### FlowRule 的流控模式

```java
// FlowRule 数据结构
public class FlowRule {
    private String resource;              // 资源名
    private int count;                    // 限流阈值（QPS）
    private GradeEnum grade;              // 限流类型：QPS或并发数
    private ControlBehaviorEnum controlBehavior;  // 流控效果
    private int warmUpPeriodSec;          // 预热时长（秒）
    private int maxQueueingTimeMs;        // 最大排队等待时间（毫秒）
    private ClusterMode clusterMode;      // 集群限流模式
}

// ControlBehavior 枚举
public enum ControlBehaviorEnum {
    DEFAULT,           // 直接拒绝（滑动窗口）
    WARM_UP,           // 预热/冷启动（令牌桶+预热曲线）
    RATE_LIMITER,      // 匀速排队（漏桶）
    WARM_UP_RATE_LIMITER  // 预热+匀速排队
}
```

#### 默认模式：滑动窗口（直接拒绝）

```java
// DefaultController — 滑动窗口限流（直接拒绝）
public class DefaultController implements TrafficShapingController {

    private final int count;              // QPS阈值
    private final double ratio;           // 预热比率
    private final RuleConstant.GradeEnum grade;

    @Override
    public boolean canPass(Node node, int acquireCount, boolean prioritized) {
        // 获取当前QPS（滑动窗口统计）
        int currentQps = (int) node.passQps();

        // 判断是否超过阈值
        if (currentQps + acquireCount > count) {
            // 超限 → 拒绝
            return false;
        }

        // 未超限 → 通过
        return true;
    }
}
```

#### 预热模式：令牌桶 + 预热曲线

```java
// WarmUpController — 预热限流（冷启动令牌桶）
// 类似 Guava SmoothWarmingUp

public class WarmUpController implements TrafficShapingController {

    private double storedPermits;         // 存储令牌数
    private double maxPermits;            // 最大令牌数
    private double stableInterval;        // 稳定间隔（毫秒）
    private double coldInterval;          // 冷启动间隔（毫秒）
    private double thresholdPermits;      // 预热阈值令牌数
    private long lastFetchTime;           // 上次获取令牌时间

    @Override
    public boolean canPass(Node node, int acquireCount, boolean prioritized) {
        long now = TimeUtil.currentTimeMillis();

        // 1. 填充令牌
        resync(now);

        // 2. 计算消耗令牌的等待时间
        double waitTime = calculateWaitTime(acquireCount);

        // 3. 判断是否超时
        if (waitTime > 0) {
            // 预热期 → 需要等待 → 排队
            lastFetchTime += waitTime;
            return prioritized;  // 优先请求可能通过
        }

        // 4. 消耗令牌
        storedPermits -= acquireCount;
        return true;
    }

    // 预热曲线计算等待时间
    private double calculateWaitTime(double requiredPermits) {
        double storedPermitsToConsume = Math.min(storedPermits, requiredPermits);
        double freshPermits = requiredPermits - storedPermitsToConsume;

        // 存储令牌在预热区消耗时间 > 0
        double warmupTime = storedPermitsToWaitTime(storedPermitsToConsume);
        double stableTime = freshPermits * stableInterval;

        return warmupTime + stableTime;
    }

    // 存储令牌消耗时间（预热曲线）
    private double storedPermitsToWaitTime(double storedPermits) {
        if (storedPermits <= thresholdPermits) {
            // 稳定区 → 等待时间≈stableInterval
            return storedPermits * stableInterval;
        } else {
            // 预热区 → 等待时间更长
            double above = storedPermits - thresholdPermits;
            return above * coldInterval + thresholdPermits * stableInterval;
        }
    }
}
```

#### 匀速排队模式：漏桶

```java
// RateLimiterController — 匀速排队（漏桶）
public class RateLimiterController implements TrafficShapingController {

    private final int maxQueueingTimeMs;  // 最大排队等待时间
    private final double intervalInMs;     // 两个请求之间的最小间隔

    private AtomicLong nextAvailableTime = new AtomicLong(0);

    @Override
    public boolean canPass(Node node, int acquireCount, boolean prioritized) {
        long currentTime = TimeUtil.currentTimeMillis();

        // 计算下一个可用时间
        long nextAvailable = nextAvailableTime.get();

        // 1. 如果当前时间 >= nextAvailable → 立即可通过
        if (currentTime >= nextAvailable) {
            // 更新下一个可用时间 = 当前时间 + 间隔
            nextAvailableTime.set(currentTime + intervalInMs * acquireCount);
            return true;
        }

        // 2. 当前时间 < nextAvailable → 需要排队等待
        long waitTime = nextAvailable - currentTime;

        // 3. 等待时间 > 最大排队时间 → 拒绝
        if (waitTime > maxQueueingTimeMs) {
            return false;
        }

        // 4. 等待时间 ≤ 最大排队时间 → 排队通过
        // 尝试更新 nextAvailable（CAS保证原子性）
        long newNextAvailable = nextAvailable + intervalInMs * acquireCount;
        if (nextAvailableTime.compareAndSet(nextAvailable, newNextAvailable)) {
            // 排队等待 waitTime 毫秒
            // 实际等待由 Sentinel 的 SentinelThreadPool 实现
            return true;
        }
        return false;
    }
}
```

### 8.5 Sentinel 统计核心：滑动窗口 LeapArray

```java
// LeapArray — Sentinel 滑动窗口统计核心
// 将1秒划分为2个子窗口（每个500ms）

public class LeapArray<T> {

    private final int windowLengthInMs;    // 子窗口长度（500ms）
    private final int sampleCount;         // 子窗口数量（2）
    private final int intervalInMs;        // 统计区间（1000ms=1s）
    private final AtomicReferenceArray<WindowWrap<T>> array;  // 子窗口数组

    public LeapArray(int sampleCount, int intervalInMs) {
        this.windowLengthInMs = intervalInMs / sampleCount;
        this.sampleCount = sampleCount;
        this.intervalInMs = intervalInMs;
        this.array = new AtomicReferenceArray<>(sampleCount);
    }

    // 获取当前子窗口
    public WindowWrap<T> currentWindow(long timeMillis) {
        // 计算当前时间对应的子窗口索引
        int idx = calculateTimeIdx(timeMillis);
        // 计算当前子窗口的起始时间
        long windowStart = calculateWindowStart(timeMillis);

        // 循环获取当前子窗口（CAS保证原子性）
        while (true) {
            WindowWrap<T> old = array.get(idx);

            if (old == null) {
                // 子窗口不存在 → 创建新窗口
                WindowWrap<T> window = new WindowWrap<>(windowLengthInMs, windowStart, newWindow());
                if (array.compareAndSet(idx, null, window)) {
                    return window;
                }
            } else if (windowStart == old.windowStart()) {
                // 子窗口存在且时间匹配 → 直接返回
                return old;
            } else if (windowStart > old.windowStart()) {
                // 子窗口存在但已过期 → 重置
                if (array.compareAndSet(idx, old,
                    new WindowWrap<>(windowLengthInMs, windowStart, newWindow()))) {
                    return array.get(idx);
                }
            }
        }
    }

    // 统计所有有效子窗口的数据
    public List<WindowWrap<T>> values() {
        List<WindowWrap<T>> result = new ArrayList<>();
        for (int i = 0; i < sampleCount; i++) {
            WindowWrap<T> windowWrap = array.get(i);
            if (windowWrap != null && !windowWrap.isExpired()) {
                result.add(windowWrap);
            }
        }
        return result;
    }
}
```

```
LeapArray 滑动窗口示意：

  1秒划分为2个子窗口（500ms/个）

  子窗口数组: [Window0, Window1]
  
  时间轴 →
  ┌────────────┬────────────┐
  │ 0-500ms   │ 500-1000ms │
  │ Window0   │ Window1    │
  │ pass=23   │ pass=27    │
  └────────────┴────────────┘
  
  当前QPS = Window0.pass + Window1.pass = 50

  滑动到下一秒：
  ┌────────────┬────────────┐
  │ 1000-1500ms│ 1500-2000ms│
  │ Window0   │ Window1    │
  │ (新的)    │ (新的)     │
  └────────────┴────────────┘
  
  旧窗口被过期清除 → 新窗口从0开始计数
```

---

# 第二篇：IO模型/Netty/Reactor底层原理

## 九、IO模型演进五阶段

### 9.1 从操作系统视角看 IO

```
一次网络 IO 的完整过程：

  ┌──────────────────────────────────────────────────────┐
  │ 应用进程                                               │
  │                                                        │
  │   ┌──────┐                                            │
  │   │ 调用 │──recv(fd, buf)──→                          │
  │   │ read │                          │                  │
  │   └──────┘                          │                  │
  │                                      │                  │
  │  ┌─────────────────────────────────┐ │                  │
  │  │ 内核空间                          │ │                  │
  │  │                                   │ │                  │
  │  │  ① 等待数据到达网卡               │←│ ← 网卡DMA        │
  │  │  ② 将数据从网卡拷贝到内核缓冲区   │  │                  │
  │  │  ③ 将数据从内核缓冲区拷贝到用户缓冲区(buf) │           │
  │  │                                   │  │                  │
  │  └─────────────────────────────────┘  │                  │
  │                                      │                  │
  │   ┌──────┐ ←── 返回数据 ─────────────│                  │
  │   │ 处理 │                                             │
  │   └──────┘                                             │
  └──────────────────────────────────────────────────────┘

  两个等待阶段：
    ① 等待数据就绪（数据从网络到达内核缓冲区）
    ② 等待数据拷贝（从内核缓冲区拷贝到用户缓冲区）
```

### 9.2 五种 IO 模型（POSIX 定义）

#### 模型1：阻塞 IO（Blocking IO — BIO）

```
  应用进程调用 recv() → 一直阻塞 → 直到数据拷贝完成

  时间轴 →
  ┌──────────────────────────────────────────────────┐
  │ 应用进程                                          │
  │                                                    │
  │   recv(fd) ──→  [阻塞等待数据就绪] ──→ [拷贝数据] │
  │                  │                    │            │
  │                  └─── 两个阶段都阻塞 ──┘            │
  │                                                    │
  │   ←── 返回 ──→ 处理 ──→ recv(fd) ──→ [阻塞]      │
  └──────────────────────────────────────────────────┘

  特点：
    ✓ 实现最简单
    ✗ 一个连接一个线程 → 线程数 = 连接数 → C10K问题
    ✗ 线程阻塞等待 → 资源浪费

  典型应用：传统 Tomcat（默认模式）
```

#### 模型2：非阻塞 IO（Non-blocking IO — NIO）

```
  应用进程调用 recv() → 如果数据未就绪 → 立即返回 EAGAIN
  → 进程不断轮询（recv → EAGAIN → recv → EAGAIN → ...）

  时间轴 →
  ┌──────────────────────────────────────────────────┐
  │ 应用进程                                          │
  │                                                    │
  │   recv → EAGAIN → recv → EAGAIN → recv → OK!    │
  │   ↓       ↓        ↓       ↓        ↓       ↓     │
  │   轮询   轮询     轮询   轮询     轮询   拷贝     │
  │                                                    │
  │   ←── 数据就绪 → 拷贝阶段仍阻塞 ──→              │
  └──────────────────────────────────────────────────┘

  特点：
    ✓ 第一阶段不阻塞（轮询）
    ✗ 第二阶段（拷贝）仍阻塞
    ✗ 轮询消耗CPU → 空转浪费
    ✗ 轮询间隔难以设定（太短耗CPU，太长延迟高）

  注意：这里的NIO是操作系统层面的non-blocking IO
       不是Java NIO（Java NIO = IO多路复用 + Buffer + Channel）
```

#### 模型3：IO 多路复用（IO Multiplexing）

```
  一个线程同时监控多个 fd 的就绪状态 → 就绪后才调用 recv()

  时间轴 →
  ┌──────────────────────────────────────────────────┐
  │ 应用进程                                          │
  │                                                    │
  │   select(fd1,fd2,fd3) ──→ [阻塞等待任一fd就绪]   │
  │                           │                       │
  │                           ↓ fd2就绪               │
  │   recv(fd2) ──→ [拷贝数据（阻塞）] ──→ 返回      │
  │                                                    │
  │   继续select ──→ [等待...] ──→ fd1就绪            │
  │   recv(fd1) ──→ [拷贝] ──→ 返回                   │
  └──────────────────────────────────────────────────┘

  特点：
    ✓ 一个线程管理多个连接 → 解决C10K
    ✓ 第一阶段不空转（select阻塞等待，不消耗CPU）
    ✗ 第二阶段（拷贝）仍阻塞
    ✗ select/poll 有性能瓶颈（详见第十章）

  典型应用：Java NIO、Redis、Nginx
```

#### 模型4：信号驱动 IO（Signal-driven IO）

```
  先注册SIGIO信号 → 内核数据就绪时发送信号 → 进程在信号处理函数中recv()

  时间轴 →
  ┌──────────────────────────────────────────────────┐
  │ 应用进程                                          │
  │                                                    │
  │   sigaction(SIGIO) ──→ 注册信号处理函数           │
  │                                                    │
  │   [进程做其他事...] ──→ 收到SIGIO信号 ──→         │
  │                           │                       │
  │   recv(fd) ──→ [拷贝数据（阻塞）] ──→ 返回       │
  └──────────────────────────────────────────────────┘

  特点：
    ✓ 第一阶段完全不阻塞（信号通知）
    ✗ 第二阶段仍阻塞
    ✗ 信号处理复杂（信号不可靠、可能丢失）
    ✗ TCP场景信号过于频繁（每个事件都触发信号）
    ✗ 实际几乎不用于网络IO

  主要用途：UDP socket（数据到达时触发一次信号）
```

#### 模型5：异步 IO（Asynchronous IO — AIO）

```
  进程调用 aio_read() → 立即返回 → 内核完成所有操作后通知进程

  时间轴 →
  ┌──────────────────────────────────────────────────┐
  │ 应用进程                                          │
  │                                                    │
  │   aio_read(fd) ──→ 立即返回 ──→ [做其他事...]    │
  │                                                    │
  │   [内核完成: 等待数据+拷贝到用户缓冲区]            │
  │                                                    │
  │   ←── 内核通知（信号/回调）──→ 处理数据           │
  │                                                    │
  │   两个阶段都不阻塞！                               │
  └──────────────────────────────────────────────────┘

  特点：
    ✓ 两个阶段都不阻塞 → 真正的异步
    ✓ 进程完全不需要等待
    ✗ Linux AIO 实现不完善（glibc AIO 用线程池模拟）
    ✗ Windows IOCP 是真正的内核级AIO
    ✗ Netty 不使用 Linux AIO（性能不如epoll多路复用）

  注意：Java 7 的 AsynchronousSocketChannel 用 Windows IOCP
       但 Linux 上仍然是 epoll 模拟
```

### 9.3 五种模型对比图

```
                阶段1：等数据就绪     阶段2：拷贝数据
                ──────────────     ──────────────

BIO             阻塞                阻塞
                (进程等)            (进程等)

非阻塞IO        不阻塞(轮询)        阻塞
                (进程反复调用)       (进程等)

IO多路复用      不阻塞(select等)    阻塞
                (内核通知就绪)       (进程等)

信号驱动IO      不阻塞(信号通知)    阻塞
                (内核发信号)         (进程等)

AIO             不阻塞              不阻塞
                (内核完成全部)       (内核通知完成)

                    ↓                  ↓

              阻塞程度 ─────────────→ 减小

              实际使用频率 ─────────→
              BIO(少) IO多路复用(最主流) AIO(少)
```

---

## 十、select / poll / epoll 底层实现

### 10.1 select

```c
// select 系统调用
int select(int nfds,                          // 最大fd+1
           fd_set *readfds,                   // 关注可读的fd集合
           fd_set *writefds,                  // 关注可写的fd集合
           fd_set *exceptfds,                 // 关注异常的fd集合
           struct timeval *timeout);          // 超时时间

// fd_set 结构（位数组）
// 每个fd用一个bit表示
// FD_SETSIZE = 1024（硬编码上限）

typedef struct {
    unsigned long fds_bits[FD_SETSIZE / (8 * sizeof(unsigned long))];
} fd_set;
```

#### select 的三次遍历

```
select 的完整流程：

  ┌──────────────────────────────────────────────────┐
  │ Step 1：用户态 → 内核态拷贝                       │
  │                                                    │
  │   用户态 fd_set（1024个bit）──拷贝──→ 内核态       │
  │   → 每次调用都要拷贝整个 fd_set                    │
  │   → 1024个fd → 拷贝128字节                        │
  │                                                    │
  │ Step 2：内核遍历所有fd                             │
  │                                                    │
  │   for (fd = 0; fd < nfds; fd++) {                 │
  │       if (fd in readfds) {                         │
  │           // 检查fd是否有数据可读                  │
  │           // 调用 vfs_poll() 检查 socket 状态     │
  │           if (socket有数据) → 标记就绪              │
  │       }                                            │
  │   }                                                │
  │   → O(n)遍历所有fd，即使大部分无数据               │
  │                                                    │
  │ Step 3：内核态 → 用户态拷贝+结果                   │
  │                                                    │
  │   内核修改 fd_set（清除未就绪的bit）               │
  │   ──拷贝──→ 用户态                                 │
  │   → 用户需要再次遍历 fd_set 找到就绪的fd           │
  │   → 又一次 O(n)遍历                               │
  │                                                    │
  │ 总遍历：3次 O(n)                                   │
  │   ① 用户态→内核态拷贝                              │
  │   ② 内核遍历检查就绪                               │
  │   ③ 内核态→用户态拷贝 + 用户遍历找就绪fd           │
  └──────────────────────────────────────────────────┘
```

#### select 的致命缺陷

| 缺陷 | 说明 |
|------|------|
| **fd数量上限** | FD_SETSIZE=1024（硬编码），无法扩展 |
| **三次O(n)遍历** | 每次调用都要遍历全部fd |
| **每次拷贝fd_set** | 用户态→内核态→用户态，两次全量拷贝 |
| **无法区分就绪fd** | 返回整个fd_set，用户还需遍历找就绪fd |
| **水平触发** | 只报告fd就绪，不记录哪些fd就绪 |

### 10.2 poll

```c
// poll 系统调用
int poll(struct pollfd *fds,      // pollfd数组
         nfds_t nfds,              // 数组长度
         int timeout);             // 超时时间（毫秒）

// pollfd 结构
struct pollfd {
    int fd;           // 文件描述符
    short events;     // 关注的事件（POLLIN/POLLOUT等）
    short revents;    // 返回的事件（内核填充）
};
```

#### poll vs select

```
改进1：无数量上限
  select: fd_set位数组 → FD_SETSIZE=1024上限
  poll: pollfd数组 → 数组长度由用户指定 → 无硬编码上限

改进2：结构更清晰
  select: 每种事件一个fd_set → 3个位数组
  poll: 每个fd一个pollfd → events+revents分离 → 更清晰

未改进1：仍是O(n)遍历
  poll 内核仍需遍历所有 pollfd 检查就绪
  → 10000个fd → 遍历10000次

未改进2：仍需拷贝
  pollfd数组仍需用户态→内核态→用户态拷贝

未改进3：仍需用户遍历找就绪fd
  返回时revents标记就绪 → 用户仍需遍历数组

未改进4：仍是水平触发
  与select相同，只报告fd就绪状态
```

### 10.3 epoll — IO 多路复用的终极方案

```c
// epoll 三步 API

// Step 1：创建 epoll 实例
int epoll_create(int size);    // size：预期fd数量（仅提示，不影响上限）

// Step 2：注册/修改/删除 fd
int epoll_ctl(int epfd,                 // epoll实例fd
              int op,                   // 操作：EPOLL_CTL_ADD/MOD/DEL
              int fd,                   // 目标fd
              struct epoll_event *event); // 事件配置

// Step 3：等待就绪事件
int epoll_wait(int epfd,                // epoll实例fd
               struct epoll_event *events,  // 就绪事件数组（输出）
               int maxevents,            // 数组最大长度
               int timeout);             // 超时时间（毫秒）

// epoll_event 结构
struct epoll_event {
    uint32_t events;     // 事件类型：EPOLLIN/EPOLLOUT/EPOLLET等
    epoll_data_t data;   // 用户数据：可存fd或指针
};

typedef union epoll_data_t {
    int fd;               // 直接存fd
    void *ptr;            // 存指针（Netty用此方式）
};
```

#### epoll 的三大核心机制

**机制1：红黑树管理 fd**

```
  epoll 内核数据结构：

  ┌──────────────────────────────────────────────────┐
  │ epoll 实例（struct eventpoll）                     │
  │                                                    │
  │   ┌─────────────────────────────────────────┐    │
  │   │ 红黑树（rbr）                             │    │
  │   │                                           │    │
  │   │    ┌─fd3──┐                              │    │
  │   │    │      │                              │    │
  │   │  ┌─fd1──┐ ┌─fd7──┐                      │    │
  │   │  │      │ │      │                      │    │
  │   │ fd0  fd2  fd5  fd9                      │    │
  │   │                                           │    │
  │   │ → O(log n) 查找/插入/删除                 │    │
  │   │ → 不需要每次重传所有fd                    │    │
  │   └─────────────────────────────────────────┘    │
  │                                                    │
  │   ┌─────────────────────────────────────────┐    │
  │   │ 就绪队列（rdllist）                       │    │
  │   │                                           │    │
  │   │   fd3 → fd7 → fd9 → ...                  │    │
  │   │                                           │    │
  │   │ → 只包含就绪的fd                          │    │
  │   │ → epoll_wait 只返回就绪的fd               │    │
  │   │ → O(1) 获取就绪事件                       │    │
  │   └─────────────────────────────────────────┘    │
  └──────────────────────────────────────────────────┘

  epoll_ctl(ADD) → 红黑树插入一个 epitem → O(log n)
  epoll_ctl(MOD) → 红黑树更新 → O(log n)
  epoll_ctl(DEL) → 黑树删除 → O(log n)

  vs select/poll：
    select：每次传入全部fd → 内核每次重建 → O(n)拷贝
    poll：每次传入pollfd数组 → 内核每次遍历 → O(n)拷贝
    epoll：fd只在红黑树中注册一次 → 后续只传就绪列表 → O(1)拷贝
```

**机制2：回调通知（回调函数唤醒）**

```
  epoll 的就绪检测机制：

  传统 select/poll：
    每次调用 → 内核遍历所有fd → 调用 vfs_poll 检查 → O(n)

  epoll：
    epoll_ctl 注册 fd 时 → 在 socket 的等待队列上注册回调函数

    ┌──────────────────────────────────────────────────┐
    │ 网卡收到数据 → DMA写入内核缓冲区 → 中断触发      │
    │                                                    │
    │ 中断处理程序：                                     │
    │   1. 找到对应的 socket                             │
    │   2. 调用 socket 的等待队列上的回调                 │
    │   3. 回调 = ep_poll_callback                      │
    │   4. ep_poll_callback 将 epitem 加入 rdllist      │
    │   5. 唤醒在 epoll_wait 上等待的进程               │
    │                                                    │
    │ → 数据到达时自动触发 → 不需要遍历所有fd            │
    │ → 就绪检测从 O(n) 变为 O(1)                       │
    └──────────────────────────────────────────────────┘

  ep_poll_callback 源码（简化）：
    static int ep_poll_callback(wait_queue_entry_t *wait, unsigned mode, ...) {
        struct epitem *epi = container_of(wait, struct epitem, wait);
        struct eventpoll *ep = epi->ep;

        // 将就绪的 epitem 加入就绪队列
        list_add_tail(&epi->rdllink, &ep->rdllist);

        // 唤醒在 epoll_wait 上等待的进程
        if (waitqueue_active(&ep->wq))
            wake_up_locked(&ep->wq);

        return 1;
    }
```

**机制3：就绪队列（rdllist）**

```
  epoll_wait 的返回：

  传统 select/poll：
    返回全部 fd_set/pollfd → 用户遍历找就绪 → O(n)

  epoll：
    内核维护 rdllist（就绪队列） → 只包含就绪的 epitem

    epoll_wait 流程：
      1. 检查 rdllist 是否有就绪事件
      2. 有 → 将就绪事件拷贝到用户空间 → 返回就绪数量
      3. 无 → 进程阻塞等待 → 被回调唤醒后重新检查

    → 只返回就绪的fd → 不需要遍历 → O(就绪fd数)
    → 即使有10000个fd，只有3个就绪 → 只返回3个
```

### 10.4 epoll 的两种触发模式

#### 水平触发（Level Triggered — LT）

```
  LT = 只要fd有数据可读 → 每次epoll_wait都通知

  场景：socket中有10KB数据未读

  第1次 epoll_wait → 通知fd可读
  → 用户只读了4KB → socket中还剩6KB

  第2次 epoll_wait → 仍然通知fd可读 ← 缓冲区仍有数据
  → 用户又读了4KB → socket中还剩2KB

  第3次 epoll_wait → 仍然通知fd可读 ← 缓冲区仍有数据
  → 用户读了2KB → socket空了

  第4次 epoll_wait → 不通知 ← 缓冲区无数据

  特点：
    ✓ 安全：不会丢事件（每次都通知直到读完）
    ✗ 效率低：可能重复通知同一个fd
    ✓ 默认模式
```

#### 边缘触发（Edge Triggered — ET）

```
  ET = 只在fd状态变化时通知一次 → 从不可读变为可读时通知

  场景：socket从无数据→有数据

  第1次 epoll_wait → 通知fd可读 ← 状态变化！
  → 用户只读了4KB → socket中还剩6KB
  → 但没有新的数据到达 → 状态未变化

  第2次 epoll_wait → 不通知 ← 状态未变化！
  → ⚠ 剩余6KB无人处理！

  解决：ET模式必须一次性读完所有数据
    while (recv(fd) > 0) { ... }  // 循环读直到EAGAIN

  第1次 epoll_wait → 通知fd可读
  → 用户循环读 → 读4KB → 读4KB → 读2KB → EAGAIN → 停止
  → socket空了 → 完成

  特点：
    ✓ 效率高：每个事件只通知一次
    ✗ 风险高：如果没读完 → 后续不再通知 → 数据丢失
    ✓ 需要非阻塞IO + 循环读（recv直到EAGAIN）

  epoll ET 的内部机制：
    ep_poll_callback 不仅将 epitem 加入 rdllist
    还检查：如果之前就已在 rdllist → 不重复加入
    → 同一个事件只通知一次
```

### 10.5 select/poll/epoll 性能对比

```
  10个fd，3个就绪：
    select: 遍历10 → 返回10 → 用户遍历10 → 总共遍历20+
    poll:   遍历10 → 返回10 → 用户遍历10 → 总共遍历20+
    epoll:  回调通知3 → 返回3 → 用户处理3 → 总共遍历3

  10000个fd，100个就绪：
    select: 遍历10000 → 拷贝10000 → 用户遍历10000 → 30000次操作
    poll:   遍历10000 → 拷贝10000 → 用户遍历10000 → 30000次操作
    epoll:  回调通知100 → 返回100 → 用户处理100 → 100次操作

  100000个fd，1000个就绪：
    select: ✗ 超过FD_SETSIZE上限(1024)
    poll:   300000次操作 → 极慢
    epoll:  1000次操作 → 极快

  结论：fd越多，epoll优势越明显
    小量fd(<100): select/poll够用
    大量fd(>1000): epoll碾压
```

| 维度 | select | poll | epoll |
|------|--------|------|-------|
| **fd上限** | 1024 | 无限制 | 无限制 |
| **就绪检测** | O(n)遍历 | O(n)遍历 | O(1)回调 |
| **内存拷贝** | 每次全量 | 每次全量 | 只拷贝就绪 |
| **触发模式** | LT | LT | LT+ET |
| **适用规模** | <100 | <1000 | 任意 |

---

## 十一、Reactor 模式三种架构

### 11.1 Reactor 模式起源

Reactor 模式由 Doug Schmidt 在 1995 年论文《Reactor: An Object Behavioral Pattern for Demultiplexed Event Dispatching》中提出。

核心思想：**将 IO 多路复用 + 事件分发 + 业务处理解耦**。

```
  Reactor 的三个角色：
    ┌──────────────────────────────────────────────────┐
    │ Reactor（反应器）：                                │
    │   调用 epoll_wait/select → 获取就绪事件           │
    │   将事件分发给对应的 Handler                       │
    │                                                    │
    │ Handler（处理器）：                                │
    │   与特定事件绑定的处理逻辑                         │
    │   如：readHandler / writeHandler / acceptHandler  │
    │                                                    │
    │ Acceptor（接收器）：                               │
    │   处理新连接接入 → 创建对应 Handler                │
    └──────────────────────────────────────────────────┘
```

### 11.2 单 Reactor 单线程

```
  ┌──────────────────────────────────────────────────┐
  │ 单线程                                             │
  │                                                    │
  │   Reactor                                          │
  │   ├── epoll_wait() → 获取就绪事件                  │
  │   ├── accept → Acceptor处理新连接                  │
  │   ├── read → Handler处理读事件                     │
  │   ├── write → Handler处理写事件                    │
  │   ├── 业务逻辑 → Handler处理业务                   │
  │                                                    │
  │   全部在同一个线程中！                               │
  └──────────────────────────────────────────────────┘

  流程：
  ┌──────────────┐
  │ Reactor线程   │
  │              │
  │  while(True) │
  │    │         │
  │    ↓         │
  │  epoll_wait  │ ← 获取就绪事件
  │    │         │
  │    ↓         │
  │  事件分发     │ ← accept? read? write?
  │    │         │
  │    ↓         │
  │  处理事件     │ ← accept → read → decode → compute → encode → send
  │    │         │
  │    ↓         │
  │  回到epoll_wait│
  └──────────────┘

  优点：简单、无线程切换开销
  缺点：
    ⚠ 一个Handler慢 → 整个Reactor阻塞 → 所有连接等待
    ⚠ 无法利用多核CPU
    ⚠ 不适合计算密集型业务

  代表：Redis（单线程Reactor + epoll）
    Redis为什么用单Reactor？
    → 纯内存操作，计算极快 → Handler不会慢
    → 单线程避免锁和并发问题
```

### 11.3 单 Reactor 多线程

```
  ┌──────────────────────────────────────────────────┐
  │                                                    │
  │   Reactor线程（主线程）                             │
  │   ├── epoll_wait → accept/read/send               │
  │   │                                                │
  │   │  accept → Acceptor → 创建Handler              │
  │   │                                                │
  │   │  read → Handler读取数据                        │
  │   │     ↓                                          │
  │   │  将数据提交给 Worker线程池                      │
  │   │     ↓                                          │
  │   │  ┌──────────┐                                  │
  │   │  │ Worker线程池 │                              │
  │   │  │ ├── 线程1 │ decode + compute + encode      │
  │   │  │ ├── 线程2 │ decode + compute + encode      │
  │   │  │ ├── 线程3 │ decode + compute + encode      │
  │   │  │ └── ...  │                                  │
  │   │  └──────────┘                                  │
  │   │     ↓                                          │
  │   │  Worker完成 → 主线程 send响应                  │
  │   │                                                │
  │   │  write → Handler发送编码后的响应               │
  └──────────────────────────────────────────────────┘

  优点：
    ✓ 业务处理不阻塞Reactor → accept/read/write不受影响
    ✓ 利用多核CPU

  缺点：
    ⚠ Reactor线程仍处理所有IO → 高并发时Reactor成为瓶颈
    ⚠ Worker线程和Reactor线程共享数据 → 需要同步机制

  代表：Memcached（部分版本）
```

### 11.4 主从 Reactor 多线程（Netty采用）

```
  ┌──────────────────────────────────────────────────────┐
  │                                                        │
  │   Main Reactor（主Reactor线程/线程组）                  │
  │   ├── epoll_wait → 只负责 accept                      │
  │   │                                                    │
  │   │  新连接到达 → accept → 创建SocketChannel          │
  │   │     ↓                                              │
  │   │  将SocketChannel分配给Sub Reactor                  │
  │                                                        │
  │   ┌─────────────┐  ┌─────────────┐                    │
  │   │ Sub Reactor1 │  │ Sub Reactor2 │  ...             │
  │   │ (IO线程1)    │  │ (IO线程2)    │                  │
  │   │              │  │              │                   │
  │   │ epoll_wait   │  │ epoll_wait   │                  │
  │   │ read → Handler│ │ read → Handler│                 │
  │   │ write → Handler│ │ write → Handler│               │
  │   └─────────────┘  └─────────────┘                    │
  │                                                        │
  │   ┌──────────────────────────────┐                    │
  │   │ Worker线程池                  │                    │
  │   │ ├── 线程1 │ decode+compute   │                    │
  │   │ ├── 线程2 │ decode+compute   │                    │
  │   │ └── ...  │                    │                    │
  │   └──────────────────────────────┘                    │
  │                                                        │
  └──────────────────────────────────────────────────────┘

  关键分工：
    Main Reactor：只处理 accept → 接收新连接
    Sub Reactor：只处理 read/write → IO读写
    Worker线程池：只处理 decode/compute/encode → 业务计算

  优点：
    ✓ 三层完全分离 → 各层不互相阻塞
    ✓ Main Reactor不被IO阻塞 → 新连接接入快
    ✓ Sub Reactor各管一组Channel → IO并发高
    ✓ Worker可利用多核 → 计算并发高
    ✓ 最适合高并发场景

  代表：Netty、Nginx（多进程版本）
```

### 11.5 三种 Reactor 对比

| 维度 | 单Reactor单线程 | 单Reactor多线程 | 主从Reactor多线程 |
|------|---------------|---------------|-----------------|
| **Reactor数** | 1 | 1 | 多（Main+Sub） |
| **IO线程** | 1 | 1 | 多（Sub Reactor） |
| **计算线程** | 0 | 多（Worker） | 多（Worker） |
| **并发能力** | 低 | 中 | 高 |
| **复杂度** | 低 | 中 | 高 |
| **适用场景** | 低并发/快速计算 | 中并发 | 高并发 |
| **代表** | Redis | Memcached | Netty/Nginx |

---

## 十二、Netty 如何实现 Reactor

### 12.1 Netty 的线程模型

```
  Netty 采用主从 Reactor 多线程模型：

  ┌──────────────────────────────────────────────────────┐
  │                                                        │
  │  bossGroup（Main Reactor）                              │
  │  ┌───┬───┬───┬───┐                                    │
  │  │B1 │B2 │B3 │B4 │  ← 通常1个boss线程即可             │
  │  └───┴───┴───┴───┘                                    │
  │   每个boss线程一个EventLoop                             │
  │   只负责 accept → 创建 NioSocketChannel               │
  │   将Channel注册到workerGroup                           │
  │                                                        │
  │  workerGroup（Sub Reactor）                             │
  │  ┌───┬───┬───┬───┬───┬───┬───┬───┐                   │
  │  │W1 │W2 │W3 │W4 │W5 │W6 │W7 │W8 │ ← 通常CPU核数×2  │
  │  └───┴───┴───┴───┴───┴───┴───┴───┘                   │
  │   每个worker线程一个EventLoop                           │
  │   负责 read/write → IO读写                             │
  │   通过Pipeline链式处理                                 │
  │                                                        │
  │  注意：Netty 默认没有单独的Worker线程池                 │
  │  → IO操作和业务处理都在 worker EventLoop 中            │
  │  → 如果业务计算慢 → 应将计算提交到自定义线程池         │
  │                                                        │
  └──────────────────────────────────────────────────────┘
```

### 12.2 NioEventLoop 的职责

```
  一个 NioEventLoop 的完整职责：

  ┌──────────────────────────────────────────────────┐
  │ NioEventLoop                                     │
  │                                                    │
  │  ① IO操作：                                       │
  │    epoll_wait → 获取就绪事件                       │
  │    accept / read / write → IO处理                  │
  │                                                    │
  │  ② 任务执行：                                     │
  │    定时任务（ScheduledTask）                       │
  │    普通任务（Task）                                │
  │    → 在IO空闲时执行                               │
  │                                                    │
  │ ③ 任务比例控制：                                   │
  │    ioRatio = 50（默认）                            │
  │    → 50%时间处理IO，50%时间处理任务                 │
  │    → 可调整：ioRatio=100 → 只处理IO               │
  │                                                    │
  │ ④ 单线程保证：                                     │
  │    一个EventLoop = 一个线程                        │
  │    → 所有Channel注册到同一个EventLoop              │
  │    → 无锁竞争 → 无并发问题                        │
  └──────────────────────────────────────────────────┘

  EventLoop 的运行循环（简化）：
  for (;;) {
      // 1. 检查是否有IO事件或任务
      if (hasIOEvents || hasTasks) {
          // 2. 处理IO事件（epoll_wait + 事件分发）
          processIOEvents();
          
          // 3. 处理所有任务
          runAllTasks(ioTime * (100 - ioRatio) / ioRatio);
      } else {
          // 4. 无事可做 → 等待（策略取决于是否允许阻塞）
          waitForWakeup();
      }
  }
```

### 12.3 Channel 与 EventLoop 的绑定

```
  Channel 注册到 EventLoop 的过程：

  ┌──────────────────────────────────────────────────┐
  │  ServerBootstrap 启动时：                          │
  │                                                    │
  │  1. bossGroup 中的某个 EventLoop                   │
  │     → 创建 NioServerSocketChannel                  │
  │     → 注册到该 EventLoop 的 Selector               │
  │     → 监听 OP_ACCEPT 事件                          │
  │                                                    │
  │  2. 新连接到达时：                                  │
  │     → accept → 创建 NioSocketChannel               │
  │     → 从 workerGroup 中选一个 EventLoop             │
  │     → 注册到该 EventLoop 的 Selector               │
  │     → 监听 OP_READ 事件                            │
  │                                                    │
  │  3. EventLoop 选择策略（轮询）：                    │
  │     EventLoop[] = [W1, W2, W3, W4, W5, W6]        │
  │     Channel1 → W1                                  │
  │     Channel2 → W2                                  │
  │     Channel3 → W3                                  │
  │     Channel4 → W4                                  │
  │     Channel5 → W5                                  │
  │     Channel6 → W6                                  │
  │     Channel7 → W1 ← 轮询回到第一个                 │
  │     ...                                            │
  │                                                    │
  │  → 每个Channel绑定一个EventLoop                    │
  │  → 一个EventLoop管理多个Channel                    │
  │  → Channel的IO操作都在其绑定的EventLoop中执行      │
  │  → 无跨线程访问 → 无锁                             │
  └──────────────────────────────────────────────────┘
```

---

## 十三、Netty NIO EventLoop 源码解析

### 13.1 NioEventLoop 核心类

```java
// NioEventLoop 继承体系
NioEventLoop
  extends SingleThreadEventLoop
    extends SingleThreadEventExecutor
      extends AbstractEventExecutor

// 核心字段
public final class NioEventLoop extends SingleThreadEventLoop {

    private Selector selector;          // NIO Selector（epoll包装）
    private Selector unwrappedSelector; // 原始Selector
    private SelectedSelectionKeySet selectedKeys; // 就绪SelectionKey集合
    private volatile int ioRatio = 50;  // IO时间占比（默认50%）

    // Netty 对 Selector 的优化：
    // SelectedSelectionKeySet 用数组替代 HashSet
    // → 遍历数组比遍历HashSet快（减少哈希冲突开销）
}
```

### 13.2 NioEventLoop.run() — 核心循环

```java
// NioEventLoop 的主循环（Netty最核心的方法之一）
@Override
protected void run() {
    for (;;) {
        try {
            // Step 1：选择策略
            // strategy = selectStrategy.calculateStrategy(selectSupplier, hasTasks)
            int strategy = selectStrategy.calculateStrategy(selectSupplier, hasTasks());

            switch (strategy) {
                case SelectStrategy.CONTINUE:  // 需要重试select
                    continue;

                case SelectStrategy.BUSY_WAIT: // 不支持busy-wait
                    // fall through to SELECT

                case SelectStrategy.SELECT:    // 执行select等待IO事件
                    // 如果有定时任务 → 计算select超时时间
                    long curDeadlineNanos = nextScheduledTaskDeadlineNanos();
                    if (curDeadlineNanos == -1L) {
                        curDeadlineNanos = NONE;  // 无定时任务 → 无限等待
                    }
                    // 等待IO事件
                    select(curDeadlineNanos);
                    break;
            }

            // Step 2：处理IO事件
            processSelectedKeys();

            // Step 3：处理任务（根据ioRatio分配时间）
            runAllTasks(ioTime * (100 - ioRatio) / ioRatio);

        } catch (Throwable t) {
            handleLoopException(t);
        }
    }
}
```

### 13.3 select() — IO事件等待

```java
// NioEventLoop.select() — 等待IO事件
private void select(long deadlineNanos) throws IOException {
    // 优化：如果 wakeupInProgress → 直接空转一次
    // 防止不必要的 selectNow 调用

    long timeoutNanos = deadlineNanos - System.nanoTime();
    int selectCnt = 0;  // 连续空select次数（用于检测epoll bug）

    for (;;) {
        // 计算超时时间
        long timeoutMillis = timeoutNanos / 1000000L;

        if (timeoutMillis <= 0) {
            // 超时时间为0 → 立即返回（有定时任务到期）
            if (selectCnt == 0) {
                selectNow();
                selectCnt = 1;
            }
            break;
        }

        // 执行 select(timeout)
        int selected = selector.select(timeoutMillis);

        selectCnt++;

        if (selected > 0) {
            // 有就绪事件 → 退出select循环
            break;
        }

        if (selectCnt >= SELECTOR_AUTO_REBUILD_THRESHOLD) {
            // ⚠ Netty的epoll bug检测机制！
            // 连续空select超过阈值 → 可能触发了JDK的epoll bug
            // → 重建Selector（解决JDK epoll空轮询bug）
            rebuildSelector();
            selector = this.selector;
            selectCnt = 0;
            break;
        }
    }
}
```

### 13.4 processSelectedKeys() — IO事件处理

```java
// 处理就绪的IO事件
private void processSelectedKeys() {
    if (selectedKeys != null) {
        // 优化版：使用Netty自定义的SelectedSelectionKeySet（数组）
        processSelectedKeysOptimized();
    } else {
        // 未优化版：使用原生Selector的selectedKeys（HashSet）
        processSelectedKeysPlain(selector.selectedKeys());
    }
}

// 优化版处理
private void processSelectedKeysOptimized() {
    SelectionKey[] keys = selectedKeys.flip();  // 获取就绪Key数组

    for (int i = 0; i < keys.length; i++) {
        final SelectionKey k = keys[i];

        // 从数组中移除（防止下次重复处理）
        selectedKeys.keys[i] = null;

        final Object a = k.attachment();  // 获取Channel附件

        if (a instanceof AbstractNioChannel) {
            // Channel的IO事件 → 由Channel处理
            processSelectedKey(k, (AbstractNioChannel) a);
        } else if (a instanceof NioTask) {
            // NioTask事件 → 由Task处理
            processSelectedKey(k, (NioTask<?>) a);
        }
    }
}

// 单个SelectionKey处理
private void processSelectedKey(SelectionKey k, AbstractNioChannel ch) {
    final AbstractNioChannel.NioUnsafe unsafe = ch.unsafe();

    if (!k.isValid()) {
        // Key无效 → 关闭连接
        unsafe.close(ch.newPromise());
        return;
    }

    int readyOps = k.readyOps();

    // OP_CONNECT → 完成连接
    if ((readyOps & SelectionKey.OP_CONNECT) != 0) {
        int ops = k.interestOps();
        ops &= ~SelectionKey.OP_CONNECT;  // 移除OP_CONNECT
        k.interestOps(ops);
        unsafe.finishConnect();
    }

    // OP_WRITE → 写数据
    if ((readyOps & SelectionKey.OP_WRITE) != 0) {
        ch.unsafe().forceFlush();
    }

    // OP_READ / OP_ACCEPT → 读数据或接受连接
    if ((readyOps & (SelectionKey.OP_READ | SelectionKey.OP_ACCEPT)) != 0
        || readyOps == 0) {
        unsafe.read();  // ← 核心：读取数据进入Pipeline
    }
}
```

### 13.5 Netty 的 epoll bug 修复机制

```
  JDK 的 epoll 空轮询 bug：
    在某些条件下，selector.select() 应该阻塞等待
    但实际立即返回 0 → 进程空转 → CPU 100%

  根因：JDK 的 epoll 实现中，当 fd 被从 epoll 中删除时
    内核可能产生一个 EPOLL_CTL_DEL 事件
    JDK 没有正确处理 → select 立即返回0

  Netty 的检测与修复：
    ┌──────────────────────────────────────────────────┐
    │ 检测：连续空select次数超过阈值                     │
    │   SELECTOR_AUTO_REBUILD_THRESHOLD = 512（默认）   │
    │                                                    │
    │ 修复：重建Selector                                 │
    │   1. 创建新的Selector                              │
    │   2. 将旧Selector上注册的所有Key重新注册到新Selector│
    │   3. 关闭旧Selector                                │
    │   4. 重置selectCnt = 0                             │
    │                                                    │
    │ 效果：空轮询bug被自动修复 → CPU不会空转            │
    └──────────────────────────────────────────────────┘

  rebuildSelector() 源码：
    public void rebuildSelector() {
        Selector newSelector = SelectorUtil.openSelector();  // 创建新Selector

        // 将旧Selector的所有SelectionKey注册到新Selector
        for (SelectionKey key : oldSelector.keys()) {
            Object a = key.attachment();
            if (a instanceof AbstractNioChannel) {
                AbstractNioChannel ch = (AbstractNioChannel) a;
                ch.unregister(oldSelector);  // 从旧Selector取消注册
                ch.register(newSelector);    // 注册到新Selector
            }
        }

        // 关闭旧Selector
        oldSelector.close();

        // 替换Selector引用
        this.selector = newSelector;
    }
```

---

## 十四、Netty Pipeline 与 ChannelHandler

### 14.1 Pipeline 的设计思想

```
  Pipeline = ChannelHandler 的链式调用链

  责任链模式 + 入站/出站双向链表

  ┌──────────────────────────────────────────────────────┐
  │ ChannelPipeline                                      │
  │                                                        │
  │  入站事件流向 →（从左到右）                            │
  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐ │
  │  │Head  │→ │解码  │→ │业务  │→ │日志  │→ │Tail  │ │
  │  │Context│  │Handler│  │Handler│  │Handler│  │Context│ │
  │  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘ │
  │                                                        │
  │  出站事件流向 ←（从右到左）                            │
  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐ │
  │  │Head  │← │编码  │← │压缩  │← │加密  │← │Tail  │ │
  │  │Context│  │Handler│  │Handler│  │Handler│  │Context│ │
  │  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘ │
  │                                                        │
  │  HeadContext：Pipeline头 → 入站事件从这里开始         │
  │  TailContext：Pipeline尾 → 出站事件从这里开始         │
  └──────────────────────────────────────────────────────┘
```

### 14.2 ChannelHandler 分类

```java
// ChannelHandler 两大子接口

// 入站处理器（处理读入数据）
public interface ChannelInboundHandler extends ChannelHandler {
    void channelRegistered(ChannelHandlerContext ctx);
    void channelUnregistered(ChannelHandlerContext ctx);
    void channelActive(ChannelHandlerContext ctx);        // 连接建立
    void channelInactive(ChannelHandlerContext ctx);      // 连接断开
    void channelRead(ChannelHandlerContext ctx, Object msg);  // 读取数据 ← 核心
    void channelReadComplete(ChannelHandlerContext ctx);
    void userEventTriggered(ChannelHandlerContext ctx, Object evt);
    void exceptionCaught(ChannelHandlerContext ctx, Throwable cause);
}

// 出站处理器（处理写出数据）
public interface ChannelOutboundHandler extends ChannelHandler {
    void bind(ChannelHandlerContext ctx, SocketAddress localAddress);
    void connect(ChannelHandlerContext ctx, SocketAddress remoteAddress);
    void disconnect(ChannelHandlerContext ctx);
    void close(ChannelHandlerContext ctx);
    void read(ChannelHandlerContext ctx);                  // 注册OP_READ
    void write(ChannelHandlerContext ctx, Object msg);    // 写数据 ← 核心
    void flush(ChannelHandlerContext ctx);                // 刷新写出缓冲
}

// 常用Handler：
// ByteToMessageDecoder    → 入站，解码（字节→对象）
// MessageToByteEncoder    → 出站，编码（对象→字节）
// IdleStateHandler        → 入站，空闲检测
// LoggingHandler          → 入站，日志
// HttpObjectDecoder       → 入站，HTTP解码
// HttpClientCodec         → 入站+出站，HTTP编解码
```

### 14.3 Pipeline 事件传播机制

```java
// 入站事件传播：channelRead
// 从HeadContext开始 → 按顺序经过每个InboundHandler

public class DefaultChannelPipeline implements ChannelPipeline {

    // HeadContext 的 channelRead → 触发入站事件
    final class HeadContext extends AbstractChannelHandlerContext {
        @Override
        public void channelRead(ChannelHandlerContext ctx, Object msg) {
            // 调用下一个InboundHandler
            ctx.fireChannelRead(msg);
        }
    }

    // AbstractChannelHandlerContext 的事件传播
    @Override
    public ChannelHandlerContext fireChannelRead(Object msg) {
        // 找到下一个InboundHandler
        AbstractChannelHandlerContext next = findContextInbound(MASK_CHANNEL_READ);
        // 调用下一个Handler的channelRead
        next.invokeChannelRead(msg);
        return this;
    }

    private void invokeChannelRead(Object msg) {
        ChannelInboundHandler handler = (ChannelInboundHandler) handler();
        handler.channelRead(this, msg);  // 调用业务Handler
    }
}

// 出站事件传播：write
// 从调用点开始 → 反向经过每个OutboundHandler → 最终到达HeadContext

@Override
public ChannelFuture write(Object msg) {
    // 找到前一个OutboundHandler
    AbstractChannelHandlerContext prev = findContextOutbound(MASK_WRITE);
    // 调用前一个Handler的write
    prev.invokeWrite(msg);
    return prev.newPromise();
}

// HeadContext 的 write → 最终写出数据到Channel
final class HeadContext extends AbstractChannelHandlerContext {
    @Override
    public void write(ChannelHandlerContext ctx, Object msg) {
        // 调用Unsafe的write → 写到Channel的发送缓冲区
        unsafe.write(msg, ctx.newPromise());
    }
}
```

### 14.4 Netty 启动流程源码

```java
// Netty 服务端启动流程
public class ServerBootstrap extends AbstractBootstrap<ServerBootstrap, ServerChannel> {

    public ChannelFuture bind(int port) {
        return bind(new InetSocketAddress(port));
    }

    public ChannelFuture bind(SocketAddress localAddress) {
        // 1. 校验配置
        validate();

        // 2. 注册到EventLoop → 创建Channel → 绑定端口
        return doBind(localAddress);
    }

    private ChannelFuture doBind(SocketAddress localAddress) {
        // 2.1 初始化Channel → 注册到bossGroup的EventLoop
        ChannelFuture regFuture = initAndRegister();

        // 2.2 注册成功后 → 绑定端口
        if (regFuture.isDone()) {
            Channel channel = regFuture.channel();
            channel.bind(localAddress);
        } else {
            // 注册尚未完成 → 等注册完成后绑定
            regFuture.addListener(future -> {
                channel.bind(localAddress);
            });
        }
    }

    final ChannelFuture initAndRegister() {
        // 1. 创建Channel（通过反射）
        Channel channel = channelFactory.newChannel();

        // 2. 初始化Channel（配置Pipeline、选项等）
        init(channel);

        // 3. 注册到bossGroup的EventLoop
        ChannelFuture regFuture = group().register(channel);

        return regFuture;
    }

    // 初始化NioServerSocketChannel
    void init(Channel channel) {
        // 设置Channel选项
        setChannelOptions(channel, options);

        // 设置Channel属性
        setChannelAttributes(channel, attrs);

        // 配置Pipeline
        ChannelPipeline p = channel.pipeline();
        p.addLast(new ServerBootstrapAcceptor(group, childGroup, childHandler, childOptions));

        // 添加用户配置的Handler
        if (handler != null) {
            p.addLast(handler);
        }
    }
}
```

### 14.5 ServerBootstrapAcceptor — 连接分发器

```java
// ServerBootstrapAcceptor — 将新连接分配给workerGroup
private static class ServerBootstrapAcceptor extends ChannelInboundHandlerAdapter {

    private final EventLoopGroup childGroup;    // workerGroup
    private final ChannelHandler childHandler;  // 业务Handler
    private final ChannelOption[] childOptions;

    @Override
    public void channelRead(ChannelHandlerContext ctx, Object msg) {
        // msg = 新接入的 NioSocketChannel
        Channel child = (Channel) msg;

        // 配置子Channel的Pipeline
        child.pipeline().addLast(childHandler);

        // 设置子Channel选项
        setChannelOptions(child, childOptions);

        // 将子Channel注册到workerGroup
        childGroup.register(child);  // ← 关键：分配给worker的EventLoop
    }
}
```

---

## 十五、面试高频问题与标准回答

### Q1：限流算法怎么选？

```
选型原则：

  保护下游（匀速消费） → 漏桶
    场景：消息队列消费速率、调用第三方API
    特点：强制匀速，防止突发打爆下游

  保护自己（允许突发） → 令牌桶
    场景：对外API限流、用户请求限流
    特点：允许短暂突发，长期平均速率受限

  精确统计 → 滑动窗口
    场景：监控QPS趋势、计费统计
    特点：无边界问题，精度高

  简单场景 → 固定窗口
    场景：内部服务粗粒度限流
    特点：实现简单，但有临界突发问题

一句话：大多数API限流用令牌桶，匀速场景用漏桶
```

### Q2：漏桶和令牌桶的核心区别？

```
漏桶：强制匀速输出
  → 请求排队 → 以恒定速率被处理
  → 不允许任何突发
  → 保护下游

令牌桶：令牌可积累，允许突发
  → 空闲时令牌积累 → 突发时一次性消耗
  → 长期平均速率受限
  → 保护自己

关键区别：
  漏桶关注"流出速率"（匀速流出）
  令牌桶关注"流入速率"（长期平均不超限）

选型：
  调第三方API → 漏桶（对方受不了突发）
  自己对外API → 令牌桶（用户体验好）
```

### Q3：为什么分布式限流要用 Lua 脚本？

```
Redis 的单线程 + Lua 原子性

  不用Lua：多条Redis命令 → 非原子
    GET → 检查 → INCR → EXPIRE
    并发时：INCR和EXPIRE之间被打断 → 计数不准

  用Lua：整个脚本原子执行
    Redis执行Lua时：
    1. 单线程执行 → 不会被其他命令打断
    2. 整个脚本作为一个命令 → 原子性
    3. 无锁 → 性能好

  → 分布式限流必须用Lua保证计数原子性
```

### Q4：BIO/NIO/AIO 有什么区别？

```
BIO（阻塞IO）：
  recv()阻塞 → 等数据+等拷贝 → 一个连接一个线程
  适合：低并发、连接数少

NIO（IO多路复用）：
  select/epoll → 一个线程管理多个连接
  等数据不阻塞 → 等拷贝阻塞
  适合：高并发、连接多但IO操作少

AIO（异步IO）：
  aio_read()立即返回 → 内核完成全部后通知
  两个阶段都不阻塞 → 真正异步
  Linux实现不完善 → Netty不用Linux AIO
  Windows IOCP是真正AIO

注意：
  Java NIO ≠ 操作系统NIO
  Java NIO = IO多路复用（epoll/select） + Buffer + Channel
  操作系统NIO = 非阻塞IO（轮询模式，几乎不用）
```

### Q5：epoll 比 select/poll 好在哪里？

```
三大核心优势：

  1. 红黑树管理fd → O(log n)增删改查
     select/poll每次传入全部fd → O(n)拷贝+遍历
     epoll只注册一次 → 后续只返回就绪列表

  2. 回调通知机制 → 数据到达自动触发回调
     select/poll每次遍历所有fd检查就绪 → O(n)
     epoll回调自动将就绪fd加入队列 → O(1)

  3. 就绪队列 → 只返回就绪的fd
     select/poll返回全部fd → 用户再遍历找就绪 → O(n)
     epoll只返回就绪fd → O(就绪数)

  性能对比：
    10000个fd, 100个就绪：
    select: 30000次操作
    epoll: 100次操作 → 300倍差距

  epoll还支持：
    ET模式（边缘触发）→ 效率更高
    无fd上限
    每次调用无需拷贝全部fd_set
```

### Q6：Netty 为什么不用 Linux AIO？

```
三个原因：

  1. Linux AIO实现不完善
    glibc AIO用线程池模拟 → 不是真正的内核级AIO
    性能反而不如epoll多路复用

  2. epoll + 非阻塞IO已经够好
    Netty的IO多路复用模式：
    epoll_wait → 获取就绪事件 → 非阻塞read/write
    → 拷贝阶段虽然"阻塞" → 但非阻塞模式下拷贝极快
    → 数据已在内核缓冲区 → 拷贝到用户缓冲区微秒级

  3. 统一跨平台
    Netty在Linux用epoll → 在Mac用kqueue
    用AIO → Windows/Linux行为不一致 → 维护困难
    用epoll多路复用 → 统一模型 → 跨平台一致
```

### Q7：Netty 的 Reactor 模型是怎样的？

```
主从Reactor多线程模型：

  bossGroup（Main Reactor）：
    1个EventLoop → 负责accept → 接收新连接
    → 将新Channel分配给workerGroup

  workerGroup（Sub Reactor）：
    CPU核数×2个EventLoop → 负责read/write
    → 每个EventLoop管理多个Channel
    → 通过Pipeline链式处理

  分工明确：
    boss只管accept → 不被IO阻塞 → 新连接接入快
    worker管IO → epoll_wait+非阻塞读写 → 高并发
    业务计算 → 在Pipeline的Handler中 → 或提交到自定义线程池

  核心保证：
    一个Channel绑定一个EventLoop → 所有IO在同一线程 → 无锁
```

### Q8：Netty 如何解决 JDK epoll 空轮询 bug？

```
JDK bug：
  selector.select()应该阻塞 → 但在某些条件下立即返回0
  → 进程空转 → CPU 100%

  根因：JDK的epoll实现中，fd被删除时内核产生的事件
  JDK没正确处理 → select立即返回

  Netty检测：
    连续空select次数 ≥ 512（默认阈值）→ 触发bug

  Netty修复：
    rebuildSelector()：
    1. 创建新Selector
    2. 将旧Selector的所有Key重新注册到新Selector
    3. 关闭旧Selector
    4. 替换引用

  效果：空轮询bug被自动修复 → 不需要人工干预
```

### Q9：Reactor 三种模式的适用场景？

```
单Reactor单线程：
  → Redis（纯内存操作极快）
  → 低并发/IO操作快的场景
  → 优点：简单无锁 → 缺点：单核瓶颈

单Reactor多线程：
  → 中等并发场景
  → IO在Reactor线程 → 计算在Worker线程池
  → 缺点：Reactor线程仍是IO瓶颈

主从Reactor多线程：
  → Netty、Nginx（高并发场景）
  → Main Reactor只accept → Sub Reactor做IO → Worker做计算
  → 优点：三层分离不互相阻塞
  → 缺点：实现复杂

选型原则：
  低并发(<1000) → 单Reactor单线程
  中并发(1000-10000) → 单Reactor多线程
  高并发(>10000) → 主从Reactor多线程
```

### Q10：Sentinel 的四种流控效果分别对应什么算法？

```
DEFAULT（直接拒绝） → 滑动窗口
  统计QPS → 超限直接拒绝
  实现：LeapArray滑动窗口统计 + DefaultController

WARM_UP（预热/冷启动） → 令牌桶+预热曲线
  冷启动时QPS从低到高渐增 → 防止瞬间打爆
  实现：WarmUpController（类似Guava SmoothWarmingUp）

RATE_LIMITER（匀速排队） → 漏桶
  强制匀速通过 → 请求排队等待
  实现：RateLimiterController + CAS更新nextAvailableTime

WARM_UP_RATE_LIMITER → 预热+匀速排队
  先预热 → 再匀速 → 两种算法叠加

一句话：
  直接拒绝=滑动窗口, 预热=令牌桶, 匀速排队=漏桶
```

---

## 附录：关键术语速查表

| 术语 | 含义 |
|------|------|
| **固定窗口** | 时间划分为固定长度窗口，每窗口独立计数 |
| **滑动窗口** | 窗口随时间滑动，始终检查过去N秒的总量 |
| **漏桶** | 强制匀速流出的限流算法 |
| **令牌桶** | 匀速生成令牌，请求消耗令牌，允许突发 |
| **预支机制** | Guava RateLimiter的核心：突发请求预支未来令牌 |
| **预热曲线** | 冷启动时消耗存储令牌需要等待时间，渐增到稳态 |
| **LeapArray** | Sentinel滑动窗口统计核心（子窗口数组） |
| **BIO** | 阻塞IO：recv阻塞直到数据拷贝完成 |
| **NIO** | 非阻塞IO/IO多路复用（语境不同含义不同） |
| **AIO** | 异步IO：两阶段都不阻塞 |
| **select** | IO多路复用（位数组，上限1024，O(n)遍历） |
| **poll** | IO多路复用（数组，无上限，O(n)遍历） |
| **epoll** | IO多路复用（红黑树+回调+就绪队列，O(1)） |
| **LT** | 水平触发：有数据就通知（默认模式） |
| **ET** | 边缘触发：状态变化时只通知一次 |
| **Reactor** | 事件驱动的IO分发模式 |
| **EventLoop** | Netty的事件循环（一个线程循环处理IO+任务） |
| **Pipeline** | Netty的Handler链（入站+出站双向链表） |
| **Channel** | Netty的网络连接抽象 |
| **bossGroup** | Main Reactor线程组（负责accept） |
| **workerGroup** | Sub Reactor线程组（负责read/write） |
| **FlowSlot** | Sentinel限流检查Slot |
| **LeapArray** | Sentinel滑动窗口统计核心 |

---

> **学习路线建议**：
> 1. 限流篇：先理解四种算法 → 重点令牌桶+漏桶 → Guava RateLimiter源码 → Sentinel → 分布式限流Redis+Lua
> 2. IO篇：先搞清五种IO模型 → 重点IO多路复用 → select/poll/epoll对比 → Reactor三种模式 → Netty实现
> 3. 衔接已学文档：
>    - **Netty底层原理文档** → 本文档IO篇是其前置理论基础，结合学习更通透
>    - **Nginx底层原理文档** → Nginx也用epoll+Reactor（多进程版），对比学习
>    - **Redis底层原理文档** → Redis用单Reactor单线程+epoll，理解为什么够用
>    - **Sentinel相关文档（Spring Cloud）** → Sentinel限流是其核心功能之一
>    - **RocketMQ底层原理文档** → MQ消费限速用漏桶思想

---

*本文为 Java 后端全栈学习系列第 29 篇，前序文档涵盖 HashMap → ConcurrentHashMap → 线程池 → AQS → volatile/JMM → Java基础 → Java8新特性 → 并发同步工具 → 类加载 → Spring IoC → Spring AOP → Spring Cloud → Dubbo → Spring全家桶串讲 → MySQL索引 → EXPLAIN → MySQL事务锁 → Redis数据结构 → Redis缓存 → Nginx → Netty → Elasticsearch → Zookeeper → RocketMQ → Kafka → JVM GC → JVM调优 → 分布式事务*
