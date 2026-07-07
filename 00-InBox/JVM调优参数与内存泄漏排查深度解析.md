# JVM 调优参数 + 内存泄漏排查深度解析

> **定位**：本文是《JVM_GC底层原理深度解析_分代_CMS_G1》的实战姊妹篇——前者讲 GC **原理**，本文讲 GC **调优**和**内存泄漏排查**。
>
> **前置阅读**：建议先阅读 GC 原理文档，理解分代假说、CMS/G1 回收流程、三色标记等概念。

---

## 目录

| 部分 | 标题 | 关键词 |
|------|------|--------|
| 第一部分 | JVM 参数分类体系 | 标准参数 / -X参数 / -XX参数 |
| 第二部分 | 堆内存调优参数详解 | -Xms/-Xmx/-Xmn/Eden/Survivor |
| 第三部分 | 元空间与直接内存调优 | Metaspace / DirectMemory / Stack |
| 第四部分 | GC 收集器参数选型 | Serial/Parallel/CMS/G1/ZGC 参数 |
| 第五部分 | JVM 监控工具（命令行） | jstat/jmap/jstack/jcmd/jhat |
| 第六部分 | 可视化工具 | JConsole/VisualVM/JProfiler/MAT |
| 第七部分 | Arthas 在线诊断 | dashboard/thread/jad/watch/trace |
| 第八部分 | JFR 飞行记录器 + 火焰图 | JFR/async-profiler/火焰图 |
| 第九部分 | 内存泄漏定义与四大类型 | 堆/栈/方法区/直接内存泄漏 |
| 第十部分 | 内存泄漏排查方法论 | 发现→定位→修复→验证 四步法 |
| 第十一部分 | 常见内存泄漏场景（12种） | 静态集合/ThreadLocal/缓存/监听器 |
| 第十二部分 | OOM 八种类型与排查 | Java heap/GC overhead/Metaspace |
| 第十三部分 | Full GC 频繁排查 | 大对象/内存泄漏/参数不当 |
| 第十四部分 | CPU 飙高排查 | 死循环/GC频繁/锁竞争 |
| 第十五部分 | 生产环境在线诊断流程 | SOP 标准操作流程 |
| 第十六部分 | 15 个真实案例分析 | 真实排查全过程 |
| 第十七部分 | JVM 调优实战清单 | 上线前 Check List |
| 第十八部分 | 面试高频题 30 问 | |
| 附录 A | JVM 参数速查表 | |
| 附录 B | 工具命令速查表 | |
| 附录 C | 内存泄漏代码模式速查 | |

---

# 第一部分：JVM 参数分类体系

## 1.1 三类参数总览

JVM 参数分为三大类，通过前缀区分：

```
┌──────────────────────────────────────────────────────────────┐
│                    JVM 参数分类体系                           │
├──────────┬───────────────────────────────────────────────────┤
│ 标准参数  │ -version / -help / -showversion / -D             │
│ (-)      │ 所有 JVM 实现必须支持，向后兼容                    │
├──────────┼───────────────────────────────────────────────────┤
│ -X 参数  │ -Xms / -Xmx / -Xmn / -Xss                        │
│ (-X)     │ 非标准参数，多数 JVM 支持，不保证向后兼容           │
├──────────┼───────────────────────────────────────────────────┤
│ -XX 参数 │ -XX:+UseG1GC / -XX:MaxGCPauseMillis=200          │
│ (-XX)    │ 高级参数，HotSpot 专用，用于调优和行为控制          │
└──────────┴───────────────────────────────────────────────────┘
```

## 1.2 -XX 参数的两种写法

```
# Boolean 类型：+ 开启，- 关闭
-XX:+UseG1GC          # 开启 G1 收集器
-XX:-UseBiasedLocking  # 关闭偏向锁

# Key-Value 类型：= 赋值
-XX:MaxGCPauseMillis=200   # 设置最大 GC 停顿时间
-XX:NewRatio=2              # 新生代:老年代 = 1:2
```

## 1.3 参数查看与验证

```bash
# 查看所有默认参数
java -XX:+PrintFlagsFinal -version | head -100

# 查看 JVM 当前生效的所有参数（运行中的进程）
jcmd <pid> VM.flags

# 查看某个进程的 JVM 参数
jinfo -flags <pid>

# 查看某个参数的值
jinfo -flag MaxHeapSize <pid>

# 查看系统属性
jcmd <pid> VM.system_properties

# 查看 JVM 版本和基本信息
java -version
java -XshowSettings:all    # JDK 11+
```

### PrintFlagsFinal 输出解读

```bash
$ java -XX:+PrintFlagsFinal -version | grep -i "heapsize"
   size_t MaxHeapSize                              = 4294967296                                {product} {command line}
   size_t InitialHeapSize                          = 268435456                                 {product} {ergonomic}
   size_t HeapBaseMinAddress                       = 0                                         {product} {default}

# 列含义：
# [类型]    [参数名]    = [值]    {类别}    {来源}
# 类型: size_t/bool/int/uintx/ccstr/double
# 类别: product(标准)/develop/notproduct/pd_product
# 来源: default(默认)/ergonomic(自动计算)/command line(命令行指定)
```

## 1.4 参数优先级

```
命令行指定 (-XX) > 环境变量 > JVM 自动计算 (ergonomic) > 默认值 (default)
```

> **关键理解**：`{ergonomic}` 表示 JVM 根据系统 CPU 和内存自动计算的值。比如 `-Xmx` 未指定时，JDK 8 默认取物理内存的 1/4（最大 1GB），JDK 11+ 取 1/4（最大可到 16GB）。

---

# 第二部分：堆内存调优参数详解

## 2.1 堆内存布局回顾

```
┌────────────────────────────────────────────────────────────────┐
│                         JVM 堆内存                              │
│                                                                │
│  ┌────────────────────────────────────────────┐  ┌──────────┐  │
│  │               新生代 (-Xmn)                │  │          │  │
│  │                                            │  │  老年代   │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐    │  │          │  │
│  │  │  Eden    │ │ S0(from) │ │ S1(to)   │    │  │          │  │
│  │  │  8份     │ │  1份     │ │  1份     │    │  │          │  │
│  │  └──────────┘ └──────────┘ └──────────┘    │  │          │  │
│  └────────────────────────────────────────────┘  └──────────┘  │
│  │←────────── -Xmn ──────────→│←─── 老年代 ───→│←─ 总堆 -Xmx ─→││
│  │←──────── 新生代+老年代 = -Xmx ────────→│                    │
│  │←─────────── -Xms (初始堆) ─────────────→│                    │
└────────────────────────────────────────────────────────────────┘

  Metaspace (JDK 8+ 替代永久代，使用本地内存，不在堆内)
  Code Cache (JIT 编译后的代码缓存，不在堆内)
  Direct Memory (NIO 直接内存缓冲区，不在堆内)
```

## 2.2 核心堆参数

### 2.2.1 -Xms 和 -Xmx（初始堆 / 最大堆）

```bash
# 生产环境推荐：-Xms 和 -Xmx 设为相同值
-Xms4g -Xmx4g
```

| 参数 | 含义 | 默认值 | 建议值 |
|------|------|--------|--------|
| `-Xms` | 初始堆大小 | 物理内存 1/64 | 与 -Xmx 相同 |
| `-Xmx` | 最大堆大小 | 物理内存 1/4 | 物理内存的 60%~70% |

**为什么 -Xms 和 -Xmx 要设为相同？**

```
场景：-Xms256m -Xmx4g

时间线：
  启动     → 堆大小 = 256MB
  压力增大 → 堆扩容到 1GB  ← 需要向 OS 申请内存 + 堆内存重映射（STW!）
  压力减小 → 堆缩容到 512MB ← 堆内存释放（可能触发 Full GC!）

问题：
  1. 扩容/缩容时触发 GC，增加停顿
  2. 内存抖动频繁 → GC 频繁
  3. 缩容后再扩容 → 反复申请/释放 → 内存碎片
  4. 预测困难 → 系统行为不稳定

解决方案：-Xms = -Xmx
  → 堆大小固定，启动时一次性申请
  → 无需扩容/缩容 → 减少不必要的 GC
  → 行为可预测
```

### 2.2.2 -Xmn（新生代大小）

```bash
# 方式1：直接指定新生代大小
-Xmn1g

# 方式2：通过 NewRatio 指定
-XX:NewRatio=2    # 新生代:老年代 = 1:2
```

| 设置方式 | 参数 | 计算 |
|----------|------|------|
| 直接指定 | `-Xmn1g` | 新生代 = 1GB，老年代 = 4 - 1 = 3GB |
| 比例指定 | `-XX:NewRatio=2` | 新生代 = 堆/3，老年代 = 堆*2/3 |
| 默认 | 不指定 | NewRatio 默认 = 2（ParallelGC）/ 动态（G1） |

> **注意**：-Xmn 和 -XX:NewRatio 不能同时使用。如果同时指定，-Xmn 优先。

**新生代大小的影响：**

```
新生代太小：
  → Minor GC 频繁（Eden 很快填满）
  → 但每次 GC 很快（新生代小）
  → 对象过早晋升老年代 → Full GC 频繁

新生代太大：
  → Minor GC 很少（Eden 不容易满）
  → 但每次 GC 停顿长（新生代大）
  → 老年代变小 → 容易 Full GC

经验值：
  互联网应用：新生代 : 老年代 = 1 : 2 或 1 : 3
  计算密集型：新生代 : 老年代 = 1 : 3 或 1 : 4
  缓存服务：新生代 : 老年代 = 1 : 4 或更小
```

### 2.2.3 Eden 与 Survivor 比例

```bash
# Eden : S0 : S1 = 8 : 1 : 1
-XX:SurvivorRatio=8
```

```
SurvivorRatio = 8 的含义：

新生代 = Eden + S0 + S1
Eden / Survivor = 8 / 1

所以：
  Eden = 新生代 × 8/10 = 80%
  S0  = 新生代 × 1/10 = 10%
  S1  = 新生代 × 1/10 = 10%

默认值：JDK 8 = 8，G1 = 6（G1 动态调整）
```

| SurvivorRatio | Eden占比 | Survivor占比 | 适用场景 |
|---------------|----------|-------------|----------|
| 6 (G1默认) | 60% | 20% | G1 |
| 8 (默认) | 80% | 10% | 大多数应用 |
| 4 | 67% | 16.5% | 对象存活率高 |
| 16 | 89% | 5.5% | 对象存活率极低 |

### 2.2.4 晋升阈值

```bash
# 对象年龄达到该值时晋升老年代
-XX:MaxTenuringThreshold=15

# Survivor 区使用率超过此值时，对象提前晋升
-XX:TargetSurvivorRatio=50
```

```
对象晋升老年代的条件：

1. 年龄达到 MaxTenuringThreshold（默认 15，CMS = 6，G1 = 15）
   → 每次 Minor GC 后存活，年龄 +1
   → 年龄达到阈值 → 晋升老年代

2. 动态年龄判断（无需等到 MaxTenuringThreshold）
   → Minor GC 后，Survivor 中某年龄段的对象大小 > Survivor × TargetSurvivorRatio(50%)
   → 该年龄及以上的对象全部晋升老年代
   → 这是 JVM 的自适应策略，防止 Survivor 溢出

3. 大对象直接进入老年代
   -XX:PretenureSizeThreshold=1048576   # 超过 1MB 的对象直接进老年代
   → 避免 Eden → Survivor 之间的复制开销
   → 注意：只对 Serial 和 ParNew 生效，ParallelGC 和 G1 不支持

4. 空间分配担保失败
   → Minor GC 前检查：老年代连续可用空间 > 新生代所有对象总空间？
   → 不满足 → 检查 -XX:-HandlePromotionFailure（JDK 6 Update 24 后废弃，默认允许）
   → 允许担保 → Minor GC 继续 → 如果担保失败（存活对象放不下）→ Full GC
   → 不允许担保 → 直接 Full GC
```

## 2.3 堆内存参数推荐配置

### 2.3.1 小型应用（4GB 物理内存）

```bash
-Xms2g -Xmx2g -Xmn768m -XX:SurvivorRatio=8 -XX:MaxTenuringThreshold=15
```

### 2.3.2 中型应用（8GB 物理内存，CMS）

```bash
-Xms4g -Xmx4g -Xmn1g -XX:SurvivorRatio=8 -XX:MaxTenuringThreshold=15
-XX:+UseConcMarkSweepGC -XX:+UseParNewGC
-XX:CMSInitiatingOccupancyFraction=70 -XX:+UseCMSInitiatingOccupancyOnly
-XX:+PrintGCDetails -Xloggc:/var/log/gc/gc.log -XX:+UseGCLogFileRotation
-XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=100M
```

### 2.3.3 大型应用（16GB+ 物理内存，G1）

```bash
-Xms8g -Xmx8g
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200
-XX:G1HeapRegionSize=16m
-XX:InitiatingHeapOccupancyPercent=45
-XX:G1NewSizePercent=20
-XX:G1MaxNewSizePercent=60
-XX:G1MixedGCCountTarget=8
-XX:G1MixedGCLiveThresholdPercent=90
-XX:G1RSetUpdatingPauseTimePercent=5
-XX:SurvivorRatio=6
-XX:MaxTenuringThreshold=15
```

### 2.3.4 容器化环境（Docker/K8s）

```bash
# JDK 8u191+ / JDK 11+
# 注意：容器内 JVM 需要正确识别容器内存限制

# JDK 8u191+ 需要手动指定（容器识别默认开启但有限制）
-Xmx2g -Xms2g -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0

# JDK 11+ 自动识别容器
-Xmx2g -Xms2g -XX:MaxRAMPercentage=75.0

# JDK 8u131~191 需要以下参数
-XX:+UnlockExperimentalVMOptions -XX:+UseCGroupMemoryLimitForHeap
```

> **容器内存陷阱**：Docker `--memory=2g` 限制的是进程可用内存，但 JVM 堆 + Metaspace + 线程栈 + 直接内存 + JIT Code Cache + GC 内部结构 都要占用。如果 -Xmx 设为 2g，实际进程可能用到 2.5g+ → 被 OOM Killer 杀死。**建议：-Xmx ≤ 容器内存的 70%~75%**。

---

# 第三部分：元空间与直接内存调优

## 3.1 Metaspace 参数

```bash
# 元空间初始大小（JDK 8+）
-XX:MetaspaceSize=256m

# 元空间最大大小（不限制则只受物理内存限制）
-XX:MaxMetaspaceSize=512m

# 元空间最小剩余空间（触发 GC 的阈值）
-XX:MinMetaspaceFreeRatio=40

# 元空间最大剩余空间比例
-XX:MaxMetaspaceFreeRatio=70
```

### MetaspaceSize 的特殊行为

```
-XX:MetaspaceSize=256m 的含义：

  MetaspaceSize 不是"初始大小"，而是"触发 Metaspace GC 的初始阈值"！

  实际行为：
  1. 启动时 Metaspace 从 0 开始增长
  2. 当 Metaspace 使用量达到 256MB 时，触发第一次 Metaspace GC
  3. GC 后根据 Min/MaxMetaspaceFreeRatio 调整新的阈值
  4. 如果类加载不多，阈值可能上调到 512MB
  5. 如果继续加载类，再次达到阈值 → 再次 GC

  问题：如果第一次 GC 后类都还活着（不会卸载）
  → Metaspace 继续增长 → 再次 GC → 频繁 Full GC

  建议：把 MetaspaceSize 设得足够大（如 256m），避免启动初期的频繁 GC
```

## 3.2 栈参数

```bash
# 每个线程的栈大小
-Xss512k
```

| -Xss 值 | 适用场景 | 说明 |
|---------|----------|------|
| 256k | 线程数极多 | 微服务网关、消息消费 |
| 512k（默认 64 位） | 大多数应用 | JDK 8 默认 1m，部分平台 512k |
| 1m | 递归调用深 | 默认值 |
| 2m | 特殊场景 | 极少需要 |

**栈大小的影响：**

```
-Xss 越大：
  → 每个线程能调用的方法栈更深（不易 StackOverflowError）
  → 但每个线程占用内存更多
  → 能创建的线程数越少

-Xss 越小：
  → 更多线程可以创建
  → 但容易 StackOverflowError（递归深/方法嵌套深）

计算：可创建线程数 ≈ (进程总内存 - 堆 - Metaspace - 其他) / Xss
```

## 3.3 直接内存参数

```bash
# 直接内存最大值（NIO ByteBuffer.allocateDirect 使用）
-XX:MaxDirectMemorySize=1g
```

```
直接内存 vs 堆内存：

  堆内存 ByteBuffer.allocate()：
  → 分配在 JVM 堆内
  → 受 GC 管理
  → I/O 时需要从堆拷贝到直接内存 → 多一次拷贝

  直接内存 ByteBuffer.allocateDirect()：
  → 分配在 JVM 堆外（系统内存）
  → 不受 GC 直接管理（通过 Cleaner 回收）
  → I/O 时零拷贝 → 性能高
  → 但分配/回收开销大

  使用直接内存的组件：
  - Netty PooledByteBufAllocator（堆外内存池）
  - NIO 文件传输（FileChannel.transferTo）
  - gRPC / Dubbo 的网络缓冲区
  - Unsafe.allocateMemory（直接系统调用）
```

**直接内存泄漏排查：**

```
症状：进程 RSS 持续增长，但堆内存正常，GC 也不频繁
原因：直接内存泄漏（ByteBuf 未 release）

排查：
  1. 查看 NMT（Native Memory Tracking）
     jcmd <pid> VM.native_memory summary

  2. 查看 DirectByteBuffer 统计
     jcmd <pid> VM.native_memory detail

  3. 查看进程 RSS
     top -p <pid>    # RES 列

  4. 查看 MaxDirectMemorySize
     jinfo -flag MaxDirectMemorySize <pid>

  5. Netty 场景：开启内存泄漏检测
     -Dio.netty.leakDetection.level=PARANOID
```

## 3.4 Code Cache 参数

```bash
# JIT 编译后的代码缓存大小
-XX:ReservedCodeCacheSize=256m

# 初始代码缓存大小
-XX:InitialCodeCacheSize=16m

# 代码缓存满了时是否停止编译
-XX:+UseCodeCacheFlushing    # JDK 8 默认开启
```

```
Code Cache 满了的表现：

  1. 编译器停止工作（所有热点代码只能解释执行）
  2. 性能急剧下降（可能慢 10 倍以上）
  3. 日志出现 "CodeCache is full. Compiler has been disabled"

建议：
  - JDK 8 默认 240MB，一般够用
  - 大型应用或大量 JIT 编译 → 设为 512MB
  - 监控 Code Cache 使用率
    jcmd <pid> Compiler.codecache
```

---

# 第四部分：GC 收集器参数选型

## 4.1 收集器选择策略

```
                    ┌─────────────────────┐
                    │  应用堆大小 + 停顿要求 │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
         < 4GB 堆         4~32GB 堆        > 32GB 堆
              │                │                │
              ▼                ▼                ▼
        ┌──────────┐    ┌──────────┐    ┌──────────┐
        │ Parallel  │    │   G1     │    │  ZGC     │
        │  GC       │    │          │    │ (JDK15+) │
        │ (JDK8默认) │    │ (JDK9+)  │    │          │
        └──────────┘    └──────────┘    └──────────┘
        吞吐量优先        停顿可预测        超低延迟
```

## 4.2 Parallel GC 参数

```bash
# JDK 8 Server 模式默认收集器
-XX:+UseParallelGC                # 新生代 = Parallel Scavenge，老年代 = Parallel Old

# 吞吐量目标（GC时间占比，默认 99）
-XX:GCTimeRatio=99                # GC时间 ≤ 1/(1+99) = 1%

# 最大 GC 停顿时间（毫秒）
-XX:MaxGCPauseMillis=200

# GC 线程数（默认 = CPU 核数）
-XX:ParallelGCThreads=8

# 并发 GC 线程数（默认 = ParallelGCThreads 的 1/4）
-XX:ConcGCThreads=2
```

**适用场景**：批处理、离线计算、对吞吐量要求高、对停顿不敏感。

## 4.3 CMS GC 参数（JDK 14 废弃）

```bash
-XX:+UseConcMarkSweepGC              # 开启 CMS
-XX:+UseParNewGC                     # 新生代用 ParNew（CMS 配套）
-XX:CMSInitiatingOccupancyFraction=70  # 老年代使用率达 70% 触发 CMS
-XX:+UseCMSInitiatingOccupancyOnly   # 只用设定的阈值，不动态调整
-XX:+CMSScavengeBeforeRemark         # 重新标记前先做一次 Minor GC
-XX:+CMSClassUnloadingEnabled        # CMS 阶段卸载类
-XX:CMSFullGCsBeforeCompaction=5    # 5 次 Full GC 后做一次空间整理
-XX:+UseCMSCompactAtFullCollection   # Full GC 时做空间整理（减少碎片）
```

### CMS 关键调优参数详解

```
1. CMSInitiatingOccupancyFraction（触发阈值）

  默认值：JDK 8 = 92（但需配合 UseCMSInitiatingOccupancyOnly 才生效）

  -XX:CMSInitiatingOccupancyFraction=70 -XX:+UseCMSInitiatingOccupancyOnly

  → 老年代使用率达到 70% 时触发 CMS

  值太低（如 50%）：
    → CMS 触发太频繁 → 消耗 CPU
    → 但有足够空间处理浮动垃圾

  值太高（如 90%）：
    → CMS 触发太晚 → 浮动垃圾来不及回收
    → 可能触发 Concurrent Mode Failure → 退化为 Serial Old → 长 STW

  建议值：
    堆 < 4GB → 70%
    堆 4~8GB → 75%
    堆 > 8GB → 80%
```

```
2. CMSScavengeBeforeRemark（重新标记前 Minor GC）

  -XX:+CMSScavengeBeforeRemark

  CMS 重新标记阶段需要扫描新生代引用老年代的对象
  → 如果不先做 Minor GC，新生代有很多对象 → 扫描慢
  → 先做 Minor GC → 清理新生代 → 重新标记快

  代价：多一次 Minor GC 的停顿
  收益：重新标记阶段大幅缩短

  建议：默认开启（大多数场景值得）
```

## 4.4 G1 GC 参数

```bash
# 开启 G1
-XX:+UseG1GC

# 目标停顿时间（毫秒），G1 尽力但不保证
-XX:MaxGCPauseMillis=200

# Region 大小（1~32MB，默认根据堆自动计算）
-XX:G1HeapRegionSize=16m

# 触发并发标记的堆使用率阈值（默认 45%）
-XX:InitiatingHeapOccupancyPercent=45

# 新生代最小占比（默认 5%）
-XX:G1NewSizePercent=20

# 新生代最大占比（默认 60%）
-XX:G1MaxNewSizePercent=60

# Mixed GC 次数目标（默认 8）
-XX:G1MixedGCCountTarget=8

# Mixed GC 时存活率超过此值的 Region 不回收（默认 85%）
-XX:G1MixedGCLiveThresholdPercent=90

# 更新 RSet 占用 GC 时间比例（默认 10%）
-XX:G1RSetUpdatingPauseTimePercent=5
```

### G1 关键调优要点

```
1. MaxGCPauseMillis（目标停顿）

  这是 G1 最重要的参数
  → G1 根据历史数据预测每个 Region 的回收成本
  → 在目标时间内选择回收价值最高的 Region

  设太低（如 50ms）：
    → G1 每次只能回收很少 Region → GC 频繁 → 吞吐量下降
    → 可能永远回收不完 → 退化为 Full GC

  设太高（如 500ms）：
    → 停顿长，但吞吐量好

  建议值：
    交互型应用：100~200ms
    后台服务：200~500ms


2. InitiatingHeapOccupancyPercent（IHOP，触发阈值）

  默认 45% → 整个堆使用率达 45% 时启动并发标记

  如果 Mixed GC 跟不上（老年代持续增长）：
    → 降低 IHOP（如 35%）→ 更早启动并发标记
    → 但并发标记消耗 CPU

  如果 Full GC 频繁：
    → 可能是 IHOP 太高 → 降 IHOP
    → 或者 Mixed GC 回收太少 → 增加 G1MixedGCCountTarget
```

## 4.5 ZGC 参数（JDK 15+ 生产可用）

```bash
# 开启 ZGC
-XX:+UseZGC

# 并发线程数
-XX:ConcGCThreads=4

# GC 线程数
-XX:ParallelGCThreads=16

# ZGC 不需要设置 MaxGCPauseMillis（设计目标 < 10ms）
# 但可以设置
-XX:MaxGCPauseMillis=10
```

**ZGC 适用场景**：
- 堆 > 32GB（G1 在大堆下停顿变长）
- 延迟敏感型应用（交易系统、实时推荐）
- 不想花时间调优的团队（ZGC 几乎不需要调参）

## 4.6 GC 日志参数

### JDK 8 GC 日志

```bash
# 开启 GC 日志
-XX:+PrintGCDetails
-XX:+PrintGCDateStamps
-XX:+PrintGCTimeStamps
-XX:+PrintGCApplicationStoppedTime    # 打印 STW 时间
-XX:+PrintGCApplicationConcurrentTime  # 打印并发时间
-XX:+PrintTenuringDistribution         # 打印晋升信息

# 日志文件
-Xloggc:/var/log/gc/gc.log
-XX:+UseGCLogFileRotation              # 日志滚动
-XX:NumberOfGCLogFiles=10
-XX:GCLogFileSize=100M
```

### JDK 9+ 统一日志（Xlog）

```bash
# 统一日志格式（JDK 9+ 替代 -XX:+PrintGCDetails）
-Xlog:gc*:file=/var/log/gc/gc.log:time,uptime,level,tags:filecount=10,filesize=100m

# 精细控制
-Xlog:gc=info:file=/var/log/gc/gc.log:time:filecount=10,filesize=100m
-Xlog:gc*=debug:file=/var/log/gc/gc.log:time:filecount=10,filesize=100m

# 同时输出到控制台和文件
-Xlog:gc*:stdout:time,level,tags -Xlog:gc*:file=/var/log/gc/gc.log:time:filecount=10,filesize=100m

# 打印 GC 原因
-Xlog:gc+cause=info
```

### JDK 11+ 关键参数

```bash
# 开启 NMT（Native Memory Tracking）
-XX:NativeMemoryTracking=summary

# 开启字符串去重（G1）
-XX:+UseStringDeduplication

# 开启压缩指针（64 位 JVM 但堆 < 32GB 时默认开启）
-XX:+UseCompressedOops

# 开启偏向锁（JDK 15+ 废弃，默认关闭）
-XX:+UseBiasedLocking    # JDK 15+ 不建议开启
```

---

# 第五部分：JVM 监控工具（命令行）

## 5.1 jps — 查看 Java 进程

```bash
# 列出所有 Java 进程
jps -lvm

# 输出示例
12345 org.example.MainApplication -Xms4g -Xmx4g -XX:+UseG1GC
12346 sun.tools.jps.Jps -lvm -Dapplication.home=/usr/lib/jvm/java-8
```

| 选项 | 含义 |
|------|------|
| `-q` | 只输出 PID |
| `-l` | 输出完整包名 / jar 路径 |
| `-m` | 输出 main 方法的参数 |
| `-v` | 输出 JVM 参数 |
| `-V` | 输出通过 flag 文件传递的参数 |

## 5.2 jstat — GC 统计信息

### 5.2.1 jstat -gcutil（最常用）

```bash
# 每隔 1000ms 输出一次 GC 统计，共输出 10 次
jstat -gcutil <pid> 1000 10
```

```
  S0     S1     E      O      M     CCS    YGC    YGCT   FGC   FGCT    GCT
  0.00  85.42  73.22  45.63  94.52  91.33   124  3.456    2   0.234   3.690
  0.00  85.42  85.31  45.63  94.52  91.33   124  3.456    2   0.234   3.690
 78.33   0.00   4.52  46.12  94.52  91.33   125  3.489    2   0.234   3.723
```

| 列 | 含义 | 解读 |
|----|------|------|
| S0 | Survivor 0 使用率 (%) | |
| S1 | Survivor 1 使用率 (%) | |
| E | Eden 使用率 (%) | |
| O | 老年代使用率 (%) | 持续增长 → 可能泄漏 |
| M | Metaspace 使用率 (%) | 持续增长 → 可能类泄漏 |
| CCS | 压缩类空间使用率 (%) | |
| YGC | Minor GC 次数 | |
| YGCT | Minor GC 总时间 (秒) | |
| FGC | Full GC 次数 | 持续增长 → 需排查 |
| FGCT | Full GC 总时间 (秒) | |
| GCT | GC 总时间 = YGCT + FGCT | |

**快速判断脚本：**

```bash
# 计算 GC 占比
jstat -gcutil <pid> 1000 5 | awk 'NR>1 {
  total_time += $11    # GCT
  total_elapsed += 1   # 每秒一次
}
END {
  printf "GC 占比: %.2f%%\n", total_time / total_elapsed * 100
}'
```

### 5.2.2 jstat -gc（详细内存信息）

```bash
jstat -gc <pid>
```

```
 S0C    S1C     S0U    S1U     EC      EU      OC       OU       MC      MUC     CCSC   CCSU    YGC   YGCT   FGC  FGCT   GCT
1024.0 1024.0  0.0    870.4  8192.0  6144.0  16384.0  7372.8  78336.0 75571.4 9216.0 8421.3  124  3.456  2  0.234  3.690
```

| 后缀 | 含义 |
|------|------|
| C | Capacity（容量，KB） |
| U | Used（已使用，KB） |

### 5.2.3 jstat -gccause（GC 原因）

```bash
jstat -gccause <pid>
```

```
  LGCC                 GCC
  Allocation Failure   No GC
```

| 列 | 含义 |
|----|------|
| LGCC | 最近一次 GC 原因 |
| GCC | 当前 GC 原因 |

常见 GC 原因：
- `Allocation Failure` — Eden 空间不足，触发 Minor GC
- `System.gc()` — 代码调用了 System.gc()
- `Metadata GC Threshold` — Metaspace 触发 GC
- `G1 Evacuation Pause` — G1 搬移存活对象
- `CMS Final Remark` — CMS 重新标记
- `Heap Inspection Initiated GC` — jmap -histo 触发
- `Heap Dump Initiated GC` — jmap -dump 触发

### 5.2.4 jstat -class（类加载统计）

```bash
jstat -class <pid>
```

```
Loaded  Bytes  Unloaded  Bytes     Time
  8543 16832.2       12   23.1      12.34
```

### 5.2.5 jstat -compiler（JIT 编译统计）

```bash
jstat -compiler <pid>
```

```
Compiled Failed Invalid   Time   FailedType FailedMethod
    5234      0       0    45.23          0
```

### 5.2.6 jstat -printcompilation（热点方法）

```bash
jstat -printcompilation <pid>
```

```
Compiled  Size  Type Method
    5234    128    1 java/util/HashMap get
```

## 5.3 jmap — 内存映射与堆 Dump

### 5.3.1 jmap -histo（对象直方图）

```bash
# 按对象大小排序，前 20 个
jmap -histo <pid> | head -30

# 只看存活对象（会触发 Full GC!）
jmap -histo:live <pid> | head -30

# 按类排序
jmap -histo <pid> | sort -k 2 -rn | head -20
```

```
 num     #instances         #bytes  class name
----------------------------------------------
   1:       1234567      123456784  [B                    ← byte 数组
   2:        567890       45671200  java.lang.String
   3:        234567       18765360  java.util.HashMap$Node
   4:        123456       11877776  [I                    ← int 数组
   5:         67890        8700320  java.util.HashMap
```

**解读要点：**

```
1. [B (byte[]) 通常是 #1 → String 内部的 value 数组
   → 如果 byte[] 异常大，检查 String 使用量

2. 看 instance 数量是否合理
   → 某个类的 instance 上百万 → 可能是泄漏

3. 对比两次 dump
   → jmap -histo <pid> > before.txt
   → 等待 5 分钟
   → jmap -histo <pid> > after.txt
   → diff before.txt after.txt    # 看增长最快的类

4. 注意 :live 选项会触发 Full GC
   → 生产环境慎用，建议在低峰期执行
```

### 5.3.2 jmap -dump（堆转储）

```bash
# Dump 整个堆到文件
jmap -dump:format=b,file=heap.hprof <pid>

# 只 dump 存活对象（会触发 Full GC）
jmap -dump:live,format=b,file=heap.hprof <pid>

# Dump 时压缩（JDK 8+）
jmap -dump:format=b,file=heap.hprof.gz <pid>
```

> **生产环境建议**：使用 `-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/data/dumps/` 自动在 OOM 时 dump，避免手动 dump 的 STW 问题。

### 5.3.3 jmap -finalizerinfo

```bash
# 查看 F-Queue 中等待执行 finalize 的对象
jmap -finalizerinfo <pid>
```

```
Number of objects pending for finalization: 234
```

> 如果这个数字持续增长 → finalize 方法执行太慢或卡死 → 对象无法回收 → 内存泄漏。

### 5.3.4 jmap -clstats（类加载器统计）

```bash
jmap -clstats <pid>
```

## 5.4 jstack — 线程栈分析

### 5.4.1 基本用法

```bash
# 打印所有线程栈
jstack <pid>

# 强制打印（进程无响应时）
jstack -F <pid>

# 打印锁信息
jstack -l <pid>
```

### 5.4.2 线程状态解读

```
"http-nio-8080-exec-1" #15 daemon prio=5 os_prio=0 tid=0x00007f8b3c00a000 nid=0x1234 waiting on condition [0x00007f8b2c5e8000]
   java.lang.Thread.State: WAITING (parking)
    at jdk.internal.misc.Unsafe.park(Native Method)
    - parking to wait for  <0x000000076b8c5e10> (a java.util.concurrent.locks.AbstractQueuedSynchronizer$ConditionObject)
    at java.util.concurrent.locks.LockSupport.park(LockSupport.java:194)
    at java.util.concurrent.locks.AbstractQueuedSynchronizer$ConditionObject.await(AbstractQueuedSynchronizer.java:2081)
    at java.util.concurrent.LinkedBlockingQueue.take(LinkedBlockingQueue.java:433)
    at org.apache.tomcat.util.threads.TaskQueue.take(TaskQueue.java:107)
    at org.apache.tomcat.util.threads.TaskQueue.take(TaskQueue.java:33)
    ...
```

| 状态 | 含义 | 可能原因 |
|------|------|----------|
| `RUNNABLE` | 运行中或等待 CPU | 正常 / 死循环 / 网络 I/O 阻塞 |
| `BLOCKED` | 等待 monitor 锁 | 锁竞争 |
| `WAITING` | 无限等待（需要 notify） | Object.wait / Thread.join / LockSupport.park |
| `TIMED_WAITING` | 限时等待 | Thread.sleep / Object.wait(timeout) / LockSupport.parkNanos |
| `TERMINATED` | 已终止 | 正常 |

### 5.4.3 死锁检测

```bash
jstack -l <pid> | grep -A 5 "Found .* deadlock"
```

```
Found 1 deadlock.
====================
"Thread-1":
  waiting to lock monitor 0x00007f8b3c0032a8 (object 0x000000076b8c5e10, a java.lang.Object),
  which is held by "Thread-0"
"Thread-0":
  waiting to lock monitor 0x00007f8b3c0028a8 (object 0x000000076b8c5e20, a java.lang.Object),
  which is held by "Thread-1"
```

### 5.4.4 找 CPU 最高的线程

```bash
# 步骤 1：找出 CPU 最高的 Java 进程
top -c
# 假设 PID = 12345

# 步骤 2：找出该进程中 CPU 最高的线程
top -Hp 12345
# 假设线程 PID = 12350

# 步骤 3：将线程 PID 转为十六进制
printf "%x\n" 12350
# 输出：304e

# 步骤 4：在 jstack 中查找该线程
jstack 12345 | grep "0x304e" -A 30
```

### 5.4.5 找 BLOCKED 的线程

```bash
# 统计各状态线程数
jstack <pid> | grep "java.lang.Thread.State:" | sort | uniq -c | sort -rn

# 输出示例：
#    45 java.lang.Thread.State: WAITING (parking)
#    23 java.lang.Thread.State: RUNNABLE
#    12 java.lang.Thread.State: TIMED_WAITING (parking)
#     3 java.lang.Thread.State: BLOCKED (on object monitor)

# 查看 BLOCKED 线程详情
jstack <pid> | grep -B 1 "BLOCKED" -A 20
```

## 5.5 jcmd — 统一管理工具（推荐）

```bash
# 列出所有 JVM 进程
jcmd -l

# 列出指定进程支持的所有命令
jcmd <pid> help

# 常用命令：
jcmd <pid> VM.flags              # 查看 JVM 参数
jcmd <pid> VM.uptime             # 运行时间
jcmd <pid> VM.version            # JVM 版本
jcmd <pid> VM.system_properties  # 系统属性
jcmd <pid> VM.command_line       # 启动命令行
jcmd <pid> Thread.print          # 线程栈（= jstack）
jcmd <pid> GC.class_histogram    # 对象直方图（= jmap -histo）
jcmd <pid> GC.heap_info          # 堆信息
jcmd <pid> GC.run                # 调用 System.gc()
jcmd <pid> GC.run_finalization   # 调用 System.runFinalization()
jcmd <pid> Compiler.codecache    # Code Cache 使用情况
jcmd <pid> Compiler.directives_print  # JIT 编译指令
jcmd <pid> VM.native_memory      # 原生内存跟踪
jcmd <pid> Thread.dump_to_file -format=text /tmp/thread.dump  # 线程 dump 到文件
jcmd <pid> GC.heap_dump /tmp/heap.hprof   # 堆 dump
jcmd <pid> JFR.start duration=60s filename=/tmp/flight.jfr  # 启动 JFR
```

### jcmd vs jstack/jmap

```
jcmd 是 JDK 7+ 引入的统一管理工具
→ 所有 jstack/jmap/jstat 能做的，jcmd 都能做
→ jcmd 功能更全（JFR 启动、NMT、Compiler 指令等）
→ jcmd 更安全（不会意外触发 Full GC）

建议：优先使用 jcmd，jstack/jmap 作为兼容
```

## 5.6 jinfo — JVM 信息与动态修改

```bash
# 查看所有 JVM 参数
jinfo -flags <pid>

# 查看某个参数
jinfo -flag MaxHeapSize <pid>

# 动态修改 Boolean 参数（标记为 manageable 的参数才能动态修改）
jinfo -flag +PrintGCDetails <pid>
jinfo -flag -PrintGCDetails <pid>

# 动态修改值参数
jinfo -flag MaxHeapFreeRatio=70 <pid>

# 查看哪些参数可以动态修改
java -XX:+PrintFlagsFinal -version | grep manageable
```

---

# 第六部分：可视化工具

## 6.1 JConsole（JDK 自带）

```bash
# 启动 JConsole
jconsole

# 远程连接
# 需要 JVM 参数：-Dcom.sun.management.jmxremote.port=9010
#               -Dcom.sun.management.jmxremote.authenticate=false
#               -Dcom.sun.management.jmxremote.ssl=false
```

**JConsole 功能：**
- Overview（概览）：堆/线程/类/CPU 四合一图
- Memory（内存）：各内存区域使用率实时图
- Threads（线程）：线程数 + 死锁检测
- Classes（类）：类加载数量
- VM（虚拟机）：JVM 信息
- MBeans：JMX MBean 管理

## 6.2 VisualVM（JDK 自带，JDK 9+ 需单独下载）

```bash
# 启动 VisualVM
jvisualvm

# 或下载：https://visualvm.github.io/
```

**VisualVM 比 JConsole 强在：**
- 插件系统（GC、Sampler、Profiler 插件）
- CPU/内存 Profiler（方法级别耗时分析）
- 堆 dump 分析（集成 MAT Lite）
- 线程 dump 分析
- BTrace 脚本支持

## 6.3 JProfiler（商业，推荐）

```
JProfiler 功能：
1. CPU Profiling → 方法级耗时 + 调用树
2. Heap Profiling → 对象分配追踪
3. Thread Profiling → 线程状态分析
4. GC Monitor → GC 实时监控
5. Database → SQL 执行分析
6. Socket → 网络连接分析

使用场景：
  → 本地开发调试（集成 IDE）
  → 远程 attach 到生产环境（Agent 模式）
  → 内存泄漏排查（Heap Walker）
```

## 6.4 MAT（Eclipse Memory Analyzer，强烈推荐）

### 6.4.1 MAT 打开 Heap Dump

```bash
# 方式 1：jmap 生成 dump 后用 MAT 打开
jmap -dump:format=b,file=heap.hprof <pid>

# 方式 2：OOM 时自动生成
-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/data/dumps/

# 方式 3：MAT 直接 attach（需要 MAT 配置 jmap 路径）
```

### 6.4.2 MAT 核心功能

```
MAT 分析堆 dump 的四大武器：

1. Leak Suspects Report（泄漏嫌疑报告）
   → 自动分析可能的内存泄漏
   → 生成 HTML 报告
   → 精确到持有引用的对象

2. Dominator Tree（支配树）
   → 按 Retained Size 排序
   → 找出"占用内存最多"的对象
   → 直观看到谁占了大头

3. Histogram（直方图）
   → 按类统计对象数量和大小
   → 对比 Shallow Size vs Retained Size
   → 正则过滤类名

4. Path to GC Roots（到 GC Roots 的路径）
   → 选中一个对象
   → 右键 → Path To GC Roots → exclude weak/soft references
   → 找到为什么这个对象无法被回收
   → 精确定位泄漏源
```

### 6.4.3 关键概念：Shallow Size vs Retained Size

```
Shallow Size（浅大小）：
  → 对象本身占用的内存（不包含引用的对象）
  → 比如一个 HashMap 只计算 HashMap 对象头 + 字段（约 48 字节）

Retained Size（保留大小）：
  → 对象本身 + 被它引用的所有对象（如果它被回收，能释放多少内存）
  → 比如一个 HashMap 如果持有 10000 个 Entry
  → Retained Size = 48 + 10000 × (Entry 大小 + Key + Value)

  这就是为什么 Dominator Tree 按 Retained Size 排序
  → 能找到真正"占用内存大"的对象
```

```
图解：

  对象 A
  ├── 引用 → 对象 B (只有 A 引用 B)
  ├── 引用 → 对象 C (A 和 D 都引用 C)
  └── 引用 → 对象 E (只有 A 引用 E)

  Shallow Size(A) = A 自身大小
  Retained Size(A) = A + B + E (不包含 C，因为 D 也引用 C)

  → 如果 A 被回收 → B 和 E 也能被回收 → C 不能被回收
```

### 6.4.4 MAT 排查内存泄漏实战流程

```
Step 1: 打开 Heap Dump → 自动运行 Leak Suspects Report
  ↓
Step 2: 查看 Leak Suspects → 通常会指出嫌疑对象
  ↓
Step 3: 打开 Dominator Tree → 按 Retained Size 排序
  ↓
Step 4: 找到 Retained Size 异常大的对象
  ↓
Step 5: 右键 → List Objects → with incoming references
  → 找出谁持有这个对象的引用
  ↓
Step 6: 右键 → Path To GC Roots → exclude weak/soft references
  → 找到 GC Roots 引用链
  → 这就是对象无法回收的原因
  ↓
Step 7: 根据引用链定位代码
  → 通常是一个静态变量 / 集合 / 缓存持有引用
```

## 6.5 GCEasy（在线 GC 日志分析）

```
网址：https://gceasy.io/

使用方式：
  1. 将 GC 日志文件上传
  2. 自动分析生成可视化报告
  3. 包含：GC 吞吐量、平均停顿、最大停顿、GC 频率、内存趋势图

适用场景：
  → 快速分析线上 GC 日志
  → 对比调优前后效果
  → 无需安装工具
```

---

# 第七部分：Arthas 在线诊断

## 7.1 Arthas 简介

Arthas 是阿里巴巴开源的 Java 在线诊断工具，**不需要重启应用**，直接 attach 到运行中的 JVM。

```
Arthas 核心能力：
  1. 查看方法执行耗时（无需改代码）
  2. 动态查看方法入参/出参
  3. 动态修改日志级别
  4. 查看 JVM 信息
  5. 反编译类（检查部署的版本是否正确）
  6. 火焰图
  7. 热更新（通过 redefine）

安装：
  curl -O https://arthas.aliyun.com/arthas-boot.jar
  java -jar arthas-boot.jar
  → 选择目标 Java 进程 → 回车
```

## 7.2 核心命令详解

### 7.2.1 dashboard — 仪表盘

```bash
[arthas@12345]$ dashboard
```

```
线程面板：
ID   NAME                     GROUP   PRIORITY  STATE      %CPU   DELTA  TIME    INTERRUPTED DAEMON
1    main                     main    5         RUNNABLE   0.0    0.000  12:34.5 false       false
2    Reference Handler        system  10        WAITING    0.0    0.000   0:00.1 false       true

内存面板：
Memory                                  used       total      max       usage     GC
heap                                    1234M      4096M      4096M     30.13%    gc.ps_marksweep
g1_eden_space                           200M       300M       -1         66.67%    -
g1_survivor_space                       50M        50M        -1         100.00%   -
g1_old_gen                              984M       3746M      4096M     26.26%    gc.ps_marksweep
nonheap                                  120M      256M       -1         46.88%    -
```

### 7.2.2 thread — 线程分析

```bash
# 查看所有线程
thread

# 查看 CPU 最高的 3 个线程
thread -n 3

# 查看指定线程的栈
thread 15

# 找出 BLOCKED 的线程
thread -b

# 查看死锁
thread --deadlock
```

**thread -b 输出示例：**

```
thread -b
"http-nio-8080-exec-2" Id=23 BLOCKED on java.lang.Object@5e8c123  owned by "http-nio-8080-exec-1" Id=22
    at com.example.service.OrderService.process(OrderService.java:45)
    - waiting to lock <0x000000076b8c5e10> (a java.lang.Object)
    - locked <0x000000076b8c5e20> (a java.lang.Object)
    at com.example.controller.OrderController.create(OrderController.java:20)
```

→ 线程 23 被 线程 22 持有的锁阻塞。

### 7.2.3 jad — 反编译

```bash
# 反编译指定类
jad com.example.service.OrderService

# 反编译指定方法
jad com.example.service.OrderService process
```

**用途**：检查线上运行的是否是最新代码，排查"明明改了代码为什么没生效"。

### 7.2.4 watch — 方法执行观测

```bash
# 观察方法入参、出参、异常
watch com.example.service.OrderService process "{params, returnObj, throwExp}" -x 2

# 观察方法执行耗时
watch com.example.service.OrderService process "#cost > 0.5" -x 2

# 条件过滤：只看第一个参数为 "VIP" 的调用
watch com.example.service.OrderService process "{params[0], returnObj}" "params[0] == 'VIP'" -x 2
```

**输出示例：**

```
method=com.example.service.OrderService.process location=AtExit
ts=2026-07-07 10:00:00; [cost=234.56ms] result=@ArrayList[
    @Object[][
        @String[ORDER12345],
    ],
    @OrderResult[
        status=@String[SUCCESS],
        amount=@Long[10000],
    ],
    null,
]
```

### 7.2.5 trace — 方法调用链耗时

```bash
# 追踪方法内部调用链的耗时
trace com.example.service.OrderService process

# 只追踪耗时超过 50ms 的
trace com.example.service.OrderService process "#cost > 50"

# 追踪指定类的所有方法
trace com.example.service.OrderService *
```

**输出示例：**

```
`---[234.56ms] com.example.service.OrderService:process()
    +---[120.34ms] com.example.dao.OrderDao:findById()
    +---[80.12ms] com.example.service.InventoryService:deduct()
    +---[15.67ms] com.example.service.PaymentService:charge()
    `---[10.23ms] com.example.event.EventPublisher:publish()
```

→ 一眼看出 `OrderDao:findById` 耗时最长（120ms）。

### 7.2.6 monitor — 方法执行统计

```bash
# 每 10 秒统计一次方法的调用次数和成功率
monitor com.example.service.OrderService process -c 10
```

```
 timestamp            class                              method   total  success  fail  avg-rt(ms)  fail-rate
 2026-07-07 10:00:10  com.example.service.OrderService  process  1234   1230     4     45.6        0.32%
 2026-07-07 10:00:20  com.example.service.OrderService  process  1456   1450     6     43.2        0.41%
```

### 7.2.7 profiler — 火焰图

```bash
# 生成 CPU 火焰图（采样 30 秒）
profiler start
# 等待 30 秒
profiler stop --format html

# 生成内存分配火焰图
profiler start --event alloc
profiler stop --format html
```

### 7.2.8 vmtool — 查找对象

```bash
# 查找指定类的所有实例
vmtool --action getInstances --className java.lang.String --limit 10

# 查找并显示对象的地址
vmtool --action getInstances --className java.util.HashMap --limit 5 -x 1
```

### 7.2.9 heapdump — 堆转储

```bash
# 生成堆 dump
heapdump /tmp/heap.hprof

# 只 dump 存活对象
heapdump --live /tmp/heap.hprof
```

### 7.2.10 其他常用命令

```bash
# 查看 JVM 信息
vmtool --action getInstances --className java.lang.String

# 查看已加载的类
sc -d com.example.service.OrderService

# 查看方法信息
sm com.example.service.OrderService

# 查看类加载器
classloader

# 查看系统属性
sysprop

# 查看环境变量
sysenv

# 查看方法被哪些类调用
stack com.example.service.OrderService process

# 动态更新日志级别
logger --name com.example --level DEBUG

# 热更新（危险！）
redefine /tmp/OrderService.class
```

## 7.3 Arthas 排查问题流程

```
┌─────────────────────────────────────────────────────────┐
│              Arthas 在线排查标准流程                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  问题：接口慢 / CPU高 / 内存泄漏                         │
│         ↓                                               │
│  1. dashboard → 看整体 CPU/内存/线程/GC 概况            │
│         ↓                                               │
│  2. thread -n 3 → 找 CPU 最高的线程                     │
│         ↓                                               │
│  3. trace → 追踪方法内部调用链耗时                      │
│         ↓                                               │
│  4. watch → 观察入参出参，确认数据是否异常               │
│         ↓                                               │
│  5. jad → 反编译确认线上代码版本                        │
│         ↓                                               │
│  6. heapdump → 如果是内存问题，dump 堆分析              │
│         ↓                                               │
│  7. profiler → 生成火焰图定位热点方法                   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

# 第八部分：JFR 飞行记录器 + 火焰图

## 8.1 JFR（Java Flight Recorder）

JFR 是 JDK 内置的低开销事件记录器，适合生产环境持续开启。

```bash
# 方式 1：JVM 启动参数开启
-XX:StartFlightRecording=duration=60s,filename=/tmp/flight.jfr

# 方式 2：jcmd 动态开启
jcmd <pid> JFR.start duration=60s filename=/tmp/flight.jfr

# 方式 3：jcmd 持续记录
jcmd <pid> JFR.start name=continuous settings=profile
# 一段时间后 dump
jcmd <pid> JFR.dump name=continuous filename=/tmp/flight.jfr
# 停止
jcmd <pid> JFR.stop name=continuous
```

### JFR 分析

```
JFR 文件分析方式：

1. JDK Mission Control（JMC）→ 图形界面分析
   → 下载：https://adoptium.net/jmc

2. 命令行分析
   jfr print --events jdk.GCPhasePause /tmp/flight.jfr

3. 在线分析
   https://console.azul.com/jfr-viewer/ (Azul Zulu)

JFR 能看到的信息：
  → GC 事件（每次 GC 的时间、原因、回收量）
  → 内存分配（哪个方法分配了最多对象）
  → 方法执行（耗时最长的调用栈）
  → 锁竞争（哪个锁等待最久）
  → I/O 事件（文件/网络操作耗时）
  → 类加载统计
  → 线程统计
```

### JFR 排查内存泄漏

```bash
# 开启 JFR 记录（profile 模式记录更多事件）
jcmd <pid> JFR.start duration=600s filename=/tmp/leak.jfr settings=profile

# 分析对象分配热点
jfr print --events jdk.ObjectAllocationSample /tmp/leak.jfr | \
  awk '{print $5}' | sort | uniq -c | sort -rn | head -10

# 输出示例：
#  15234 java.lang.String
#  12345 java.util.HashMap$Node
#   5678 byte[]
#   3456 com.example.dto.OrderDTO
```

## 8.2 async-profiler（火焰图）

async-profiler 是一个低开销的 Linux/macOS 性能分析工具，能生成火焰图。

```bash
# 安装
git clone https://github.com/async-profiler/async-profiler.git
cd async-profiler
make

# 或直接下载预编译版本
wget https://github.com/async-profiler/async-profiler/releases/download/v3.0/async-profiler-3.0-linux-x64.tar.gz
tar xzf async-profiler-3.0-linux-x64.tar.gz
```

### 8.2.1 CPU 火焰图

```bash
# 采样 60 秒，生成 CPU 火焰图
./profiler.sh -d 60 -f /tmp/cpu-flame.html <pid>

# 指定采样频率（默认 10MHz）
./profiler.sh -d 60 -f /tmp/cpu-flame.html --freq 1000 <pid>
```

### 8.2.2 内存分配火焰图

```bash
# 采样内存分配（不采样 CPU）
./profiler.sh -d 60 -e alloc -f /tmp/alloc-flame.html <pid>
```

### 8.2.3 锁竞争火焰图

```bash
# 采样锁等待
./profiler.sh -d 60 -e lock -f /tmp/lock-flame.html <pid>
```

### 火焰图解读

```
火焰图示例：

█ JVM_System.arraycopy()
█ █ java.util.Arrays.copyOf()
█ █ █ java.lang.String.<init>()
█ █ █ █ com.example.service.OrderService.buildOrder()
█ █ █ █ █ com.example.controller.OrderController.create()
█ █ █ █ █ █ org.springframework.web.method.support.InvocableHandlerMethod.doInvoke()
█ █ █ █ █ █ █ org.springframework.web.servlet.DispatcherServlet.doDispatch()

解读：
  → 横轴：方法在调用栈中的位置（不是时间）
  → 纵轴：调用深度（顶层调用在下层）
  → 宽度：CPU 时间占比（越宽越耗 CPU）
  → 最宽的方法就是瓶颈 → 优先优化

注意：
  → "平顶"（顶部很宽）= 该方法是热点 → 优化它
  → "窄而深" = 调用链长但不一定慢
  → GC 相关的 "栈帧" 占比大 → GC 是瓶颈
```

## 8.3 Arthas profiler 火焰图

```bash
# Arthas 内置 profiler（底层也是 async-profiler）
[arthas@12345]$ profiler start
# 等待 30 秒
[arthas@12345]$ profiler stop --format html
# 自动在浏览器打开火焰图
```

---

---

# 第九部分：内存泄漏定义与四大类型

## 9.1 什么是内存泄漏

```
┌─────────────────────────────────────────────────────────────────┐
│                      内存泄漏 vs 内存溢出                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  内存泄漏（Memory Leak）:                                       │
│    对象不再被使用，但仍被 GC Roots 引用 → 无法回收              │
│    → 堆内存逐渐减少                                              │
│    → 最终导致 OOM                                                │
│                                                                 │
│    图示：                                                         │
│    [GC Roots] → A → B → C → D                                   │
│                          ↑                                      │
│                    D 不再使用了                                    │
│                    但 A→B→C→D 的引用链还在 → D 无法回收          │
│                                                                 │
│  内存溢出（OOM）:                                               │
│    JVM 无法分配更多内存 → 抛出 OutOfMemoryError                 │
│    → 内存泄漏的最终结果                                          │
│    → 也可能是内存确实不够（对象太多而非泄漏）                     │
│                                                                 │
│  区分：                                                           │
│    泄漏 → 修复引用链（代码问题）                                 │
│    不足 → 加内存或优化对象创建（容量问题）                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 9.2 四大类型

### 9.2.1 堆内存泄漏（最常见）

```
原因：对象被长期持有的引用（静态变量、集合、缓存等）持有

  静态集合：static List<Object> cache = new ArrayList<>();
  → 类不会被卸载 → 静态变量永远存在 → 集合中的对象永远无法回收

  ThreadLocal：threadLocal.set(userSession);
  → 线程不销毁 → ThreadLocalMap 中的 Entry 不被清理
  → 线程池场景尤其严重（线程复用，ThreadLocal 不清除）

  未关闭的资源：
  InputStream in = new FileInputStream(file);
  → 使用后忘记 in.close()
  → InputStream 持有文件描述符 → 泄漏

  监听器/回调：
  button.addListener(listener);
  → 忘记 removeListener(listener)
  → 发布者持有监听器引用 → 监听器持有外部类引用 → 泄漏

  缓存无淘汰策略：
  Map<String, Object> cache = new HashMap<>();
  cache.put(key, value); // 只 put 不 remove
  → 缓存无限增长
```

### 9.2.2 栈内存泄漏（StackOverflowError）

```
原因：递归调用过深 / 方法调用栈溢出

  无限递归：
  public void recursive() {
      recursive();  // 没有终止条件 → 栈溢出
  }

  正常递归但深度过大：
  public int factorial(int n) {
      if (n <= 1) return 1;
      return n * factorial(n - 1);  // n = 100000 → 栈溢出
  }

  排查：
  → StackOverflowError 的异常栈本身就告诉你哪个方法递归了
  → 检查终止条件
  → 如果确实需要深度递归 → 改为迭代 / 尾递归

  调优：
  → 增大 -Xss（如 -Xss2m），但会减少线程数
  → 根本的解决方案是改代码
```

### 9.2.3 方法区/Metaspace 泄漏

```
原因：类加载器泄漏 / 动态生成类不卸载

  场景 1：自定义 ClassLoader 未正确回收
  → 热部署/热加载框架动态加载类
  → ClassLoader 被 GC 回收需要满足：ClassLoader 对象无引用 + 它加载的所有类无引用
  → 如果有一个类的实例还活着 → ClassLoader 无法卸载 → 类无法卸载 → Metaspace 泄漏

  场景 2：cglib / Javassist 动态代理生成类
  → 每次创建代理都生成新类 → 积累在 Metaspace
  → 如果缓存失效 → 不断生成新类 → Metaspace 增长

  场景 3：JSP 重新编译
  → 每次修改 JSP → 编译新类 → 旧类未卸载

  排查：
  → jstat -gcutil <pid> 查看 M 列（Metaspace 使用率）是否持续增长
  → jmap -clstats <pid> 查看类加载器数量
  → MAT → 搜索 ClassLoader → 查看 ClassLoader 实例数
  → -XX:+TraceClassUnloading 打印类卸载日志

  调优：
  → -XX:MaxMetaspaceSize=512m 限制上限（防止无限增长导致 OOM）
  → 修复代码：确保 ClassLoader 无引用后能被 GC 回收
```

### 9.2.4 直接内存泄漏（堆外内存）

```
原因：NIO DirectByteBuffer / Netty ByteBuf 未释放

  场景 1：ByteBuffer.allocateDirect 未手动释放
  ByteBuffer buf = ByteBuffer.allocateDirect(1024 * 1024);  // 1MB
  → 直接内存不受 GC 直接管理
  → 只有当 DirectByteBuffer 对象被 GC 回收时，Cleaner 才释放直接内存
  → 如果 DirectByteBuffer 被引用持有 → 不被 GC → 直接内存泄漏

  场景 2：Netty ByteBuf 未 release
  ByteBuf buf = ctx.alloc().buffer();
  buf.writeBytes(data);
  // 使用后忘记 buf.release();
  → Netty 默认使用池化堆外内存
  → 未 release 的 ByteBuf 不会归还池 → 内存泄漏

  场景 3：gRPC / Dubbo 堆外内存
  → RPC 框架使用堆外内存做网络缓冲区
  → 如果缓冲区未释放 → 泄漏

  症状：
  → JVM 堆内存正常（jstat -gcutil O 列不高）
  → 但进程 RSS（物理内存）持续增长
  → top -p <pid> 显示 RES 列不断增大
  → 最终被 OOM Killer 杀死（不是 Java OOM）

  排查：
  → -XX:NativeMemoryTracking=summary 开启 NMT
  → jcmd <pid> VM.native_memory summary 查看 Internal/Direct 段
  → 查看进程 RSS：top -p <pid>
  → Netty 场景：-Dio.netty.leakDetection.level=PARANOID
```

---

# 第十部分：内存泄漏排查方法论

## 10.1 四步排查法

```
┌──────────────────────────────────────────────────────────────┐
│              内存泄漏排查四步法                                 │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Step 1: 发现（怎么知道有泄漏？）                              │
│    → 监控：堆内存趋势图（持续增长不下降）                      │
│    → 报警：Old Gen 使用率持续 > 80%                            │
│    → 症状：Full GC 频繁但回收效果差                            │
│    → 最终：OOM / 被重启                                        │
│                                                              │
│  Step 2: 定位（泄漏的对象是什么？）                             │
│    → jmap -histo 看对象数量趋势                               │
│    → 做两次 dump 对比增长                                      │
│    → 堆 dump → MAT 分析                                       │
│                                                              │
│  Step 3: 修复（为什么泄漏？）                                   │
│    → MAT → Path to GC Roots 找引用链                          │
│    → 定位到代码中持有引用的变量                                 │
│    → 修改代码（移除引用 / 使用弱引用 / 加清理逻辑）              │
│                                                              │
│  Step 4: 验证（修复了吗？）                                    │
│    → 部署后观察内存趋势（是否稳定不增长）                       │
│    → 压测验证                                                  │
│    → 持续监控 24~48 小时                                       │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## 10.2 Step 1: 发现泄漏

### 10.2.1 监控指标

```
关键监控指标（使用 Prometheus + Grafana 或 Zabbix）：

  1. JVM 堆内存使用率
     → Old Gen 持续增长且 Full GC 后不下降 → 可疑
     → 公式：old_used / old_max

  2. GC 频率和耗时
     → Full GC 间隔越来越短 → 可疑
     → Full GC 耗时越来越长 → 可疑

  3. GC 后内存回收率
     → Full GC 后 Old Gen 下降很少 → 可疑
     → 正常：Full GC 后 Old Gen 显著下降
     → 泄漏：Full GC 后 Old Gen 几乎不降

  4. 进程 RSS（物理内存）
     → RSS 持续增长 → 可能直接内存泄漏

  5. 线程数
     → 线程数持续增长 → 可能线程泄漏

报警阈值建议：
  → Old Gen > 85% 持续 5 分钟 → 报警
  → Full GC > 5 次/小时 → 报警
  → Full GC 耗时 > 1 秒 → 报警
```

### 10.2.2 jstat 趋势分析

```bash
# 每隔 5 秒采样，观察 5 分钟
jstat -gcutil <pid> 5000 60
```

```
正常趋势：
  O    FGC
  35%   0
  40%   0
  65%   0
  35%   1    ← Full GC 后 O 从 65% 降到 35%（正常回收）
  45%   1
  60%   1
  32%   2    ← Full GC 后从 60% 降到 32%（正常回收）

泄漏趋势：
  O    FGC
  35%   0
  45%   0
  65%   1    ← Full GC 后只降了一点点
  58%   1    ← 58% 说明只回收了 7%
  72%   2    ← 再次 Full GC
  68%   2    ← 只降了 4%
  85%   3    ← 越来越高，GC 越来越频繁
  82%   3    ← 几乎不降了
  95%   4    ← 即将 OOM
```

## 10.3 Step 2: 定位泄漏对象

### 10.3.1 jmap 对比法

```bash
# 第一次采样
jmap -histo <pid> | sort -k 2 -rn > /tmp/histo_before.txt

# 等待 5~10 分钟（让泄漏对象积累）

# 第二次采样
jmap -histo <pid> | sort -k 2 -rn > /tmp/histo_after.txt

# 对比差异
diff /tmp/histo_before.txt /tmp/histo_after.txt | head -30
```

**输出示例：**

```
<   1:       12345       98760  com.example.dto.OrderDTO
---
>   1:       45678      365424  com.example.dto.OrderDTO    ← 数量从 12345 增到 45678！
```

→ `OrderDTO` 对象在 5 分钟内从 12345 个增到 45678 个，增长 370%。高度可疑。

### 10.3.2 MAT 分析法

```bash
# 生成堆 dump（建议在低峰期，避免 STW 影响）
jmap -dump:format=b,file=/tmp/heap.hprof <pid>

# 或使用 jcmd（更安全）
jcmd <pid> GC.heap_dump /tmp/heap.hprof
```

**MAT 分析步骤：**

```
1. 打开 dump → 自动运行 Leak Suspects Report

2. 查看 Leak Suspect：
   "Problem Suspect 1: 2.3GB (57.50%) of Java heap is used by
    java.util.concurrent.ConcurrentHashMap$Node[], which is
    retained by com.example.cache.OrderCache"

3. 查看 Dominator Tree → 按 Retained Size 排序
   → 找到占用最大的对象（如 OrderCache 实例）

4. 右键 → Path to GC Roots → exclude weak/soft references
   → 看到引用链：
   OrderCache.<static> cache → ConcurrentHashMap → Node[] → Node → OrderDTO

5. 定位代码：OrderCache 的静态 cache 变量持有所有 OrderDTO
```

## 10.4 Step 3: 修复泄漏

### 常见修复方案

```
┌──────────────────────────────────────────────────────────────┐
│              常见内存泄漏修复方案                                │
├──────────────┬───────────────────────────────────────────────┤
│ 泄漏类型      │ 修复方案                                       │
├──────────────┼───────────────────────────────────────────────┤
│ 静态集合      │ 1. 用 WeakHashMap 替代 HashMap                │
│              │ 2. 定期清理（如 Guava Cache + 过期时间）        │
│              │ 3. 改为实例变量（随对象销毁而释放）             │
├──────────────┼───────────────────────────────────────────────┤
│ ThreadLocal  │ 1. 使用后 threadLocal.remove()                │
│              │ 2. try-finally 确保清除                        │
│              │ 3. 使用 TransmittableThreadLocal（阿里 TTL）   │
├──────────────┼───────────────────────────────────────────────┤
│ 未关闭资源    │ 1. try-with-resources 语法                    │
│              │ 2. try-finally 手动 close                      │
│              │ 3. 使用连接池（自动管理生命周期）               │
├──────────────┼───────────────────────────────────────────────┤
│ 监听器        │ 1. 不用时 removeListener                      │
│              │ 2. 使用弱引用包装监听器                        │
│              │ 3. Spring @PreDestroy 中注销                  │
├──────────────┼───────────────────────────────────────────────┤
│ 缓存无淘汰    │ 1. 使用 Caffeine/Guava Cache（自带淘汰策略）  │
│              │ 2. 设置 maximumSize 或 expireAfterWrite        │
│              │ 3. 定期清理不活跃的 Key                        │
├──────────────┼───────────────────────────────────────────────┤
│ 内部类引用    │ 1. 非静态内部类隐式持有外部类引用              │
│              │ 2. 改为静态内部类 + 显式传引用                 │
│              │ 3. 匿名内部类同理                              │
└──────────────┴───────────────────────────────────────────────┘
```

## 10.5 Step 4: 验证修复

```
验证清单：
  □ 部署后观察 Old Gen 趋势 24 小时（不再持续增长）
  □ Full GC 频率恢复正常（对比修复前）
  □ Full GC 后 Old Gen 显著下降（回收有效）
  □ 压测验证（模拟峰值流量 1 小时，内存不溢出）
  □ NMT 报告 Internal/Direct 段不异常增长
  □ 持续监控 48 小时无异常
```

---

# 第十一部分：常见内存泄漏场景（12种）

## 11.1 静态集合持有对象

```java
// ❌ 泄漏代码
public class OrderCache {
    private static final Map<String, Order> cache = new HashMap<>();

    public static void put(Order order) {
        cache.put(order.getId(), order);
    }
    // 只 put 不 remove → 无限增长
}

// ✅ 修复方案 1：使用 Caffeine
public class OrderCache {
    private static final Cache<String, Order> cache = Caffeine.newBuilder()
        .maximumSize(10000)
        .expireAfterWrite(30, TimeUnit.MINUTES)
        .build();
}

// ✅ 修复方案 2：使用 WeakHashMap
// → Key 被 GC 回收后，Entry 自动移除
private static final Map<WeakReference<Order>, Object> cache = new WeakHashMap<>();
```

## 11.2 ThreadLocal 未清除

```java
// ❌ 泄漏代码
public class UserContextHolder {
    private static final ThreadLocal<User> holder = new ThreadLocal<>();

    public void handleRequest(User user) {
        holder.set(user);
        // 业务逻辑...
        // 忘记 holder.remove() → 线程池线程复用 → User 对象泄漏
    }
}

// ✅ 修复方案
public void handleRequest(User user) {
    try {
        holder.set(user);
        // 业务逻辑...
    } finally {
        holder.remove();  // 必须清除
    }
}
```

## 11.3 未关闭的资源

```java
// ❌ 泄漏代码
public void readFile(String path) throws IOException {
    FileInputStream fis = new FileInputStream(path);
    // 如果这里抛异常 → fis 未关闭 → 文件描述符泄漏
    byte[] data = fis.readAllBytes();
    fis.close();
}

// ✅ 修复方案 1：try-with-resources
public void readFile(String path) throws IOException {
    try (FileInputStream fis = new FileInputStream(path)) {
        byte[] data = fis.readAllBytes();
    }  // 自动 close，即使抛异常也会关闭
}

// ✅ 修复方案 2：try-finally
public void readFile(String path) throws IOException {
    FileInputStream fis = null;
    try {
        fis = new FileInputStream(path);
        byte[] data = fis.readAllBytes();
    } finally {
        if (fis != null) fis.close();
    }
}
```

## 11.4 监听器/回调未注销

```java
// ❌ 泄漏代码
public class EventManager {
    private List<EventListener> listeners = new CopyOnWriteArrayList<>();

    public void register(EventListener listener) {
        listeners.add(listener);
    }
    // 没有 unregister 方法 → 监听器永远在列表中 → 泄漏
}

// ✅ 修复方案
public class EventManager {
    private List<EventListener> listeners = new CopyOnWriteArrayList<>();

    public void register(EventListener listener) {
        listeners.add(listener);
    }

    public void unregister(EventListener listener) {
        listeners.remove(listener);
    }
}

// 使用时确保注销
@PostConstruct
public void init() {
    eventManager.register(this);
}

@PreDestroy
public void destroy() {
    eventManager.unregister(this);  // Bean 销毁时注销
}
```

## 11.5 内部类隐式持有外部类引用

```java
// ❌ 泄漏代码
public class Outer {
    private byte[] bigData = new byte[100 * 1024 * 1024];  // 100MB

    // 非静态内部类 → 隐式持有 Outer.this 引用
    class Inner {
        public void doSomething() {
            // 即使 Outer 不再使用，只要 Inner 还在
            // → Outer 无法被 GC → bigData 无法回收
        }
    }
}

// ✅ 修复方案：改为静态内部类
public class Outer {
    private byte[] bigData = new byte[100 * 1024 * 1024];

    static class Inner {  // 静态内部类 → 不持有 Outer 引用
        public void doSomething() {
            // 不依赖 Outer 的实例变量
        }
    }
}
```

## 11.6 缓存无淘汰策略

```java
// ❌ 泄漏代码
public class LocalCache {
    private static final Map<String, Object> cache = new ConcurrentHashMap<>();

    public static void put(String key, Object value) {
        cache.put(key, value);
        // 无上限、无过期 → 内存无限增长
    }
}

// ✅ 修复方案：Caffeine
public class LocalCache {
    private static final Cache<String, Object> cache = Caffeine.newBuilder()
        .maximumSize(10000)
        .expireAfterWrite(10, TimeUnit.MINUTES)
        .expireAfterAccess(5, TimeUnit.MINUTES)
        .recordStats()  // 开启统计
        .build();

    public static void put(String key, Object value) {
        cache.put(key, value);
    }

    public static Object get(String key) {
        return cache.getIfPresent(key);
    }
}
```

## 11.7 连接池泄漏

```java
// ❌ 泄漏代码
public void queryData() {
    Connection conn = dataSource.getConnection();
    // 如果这里抛异常 → conn 未归还 → 连接泄漏
    PreparedStatement ps = conn.prepareStatement("SELECT * FROM orders");
    ResultSet rs = ps.executeQuery();
    // 忘记 conn.close()
}

// ✅ 修复方案：try-with-resources
public void queryData() {
    try (Connection conn = dataSource.getConnection();
         PreparedStatement ps = conn.prepareStatement("SELECT * FROM orders");
         ResultSet rs = ps.executeQuery()) {
        // 自动关闭所有资源
    } catch (SQLException e) {
        // 处理异常
    }
}
```

## 11.8 ScheduledExecutorService 任务无限堆积

```java
// ❌ 泄漏代码
ScheduledExecutorService executor = Executors.newSingleThreadScheduledExecutor();

// 每个请求创建一个定时任务但不取消
public void process(Request req) {
    executor.scheduleAtFixedRate(() -> {
        checkTimeout(req);
    }, 0, 1, TimeUnit.SECONDS);
    // 不取消 → Runnable 持有 req → req 无法回收
    // 任务越来越多 → 内存泄漏
}

// ✅ 修复方案：使用 ScheduledFuture 管理生命周期
private Map<String, ScheduledFuture<?>> tasks = new ConcurrentHashMap<>();

public void process(Request req) {
    ScheduledFuture<?> future = executor.scheduleAtFixedRate(() -> {
        checkTimeout(req);
    }, 0, 1, TimeUnit.SECONDS);
    tasks.put(req.getId(), future);
}

public void complete(String reqId) {
    ScheduledFuture<?> future = tasks.remove(reqId);
    if (future != null) future.cancel(false);
}
```

## 11.9 String.intern() 大量调用

```java
// ❌ 泄漏代码
public void process(String data) {
    String interned = data.intern();
    // intern() 将字符串放入 String Pool（方法区/Metaspace）
    // String Pool 中的字符串不会被 GC（JDK 6）/ 很难被 GC（JDK 7+）
    // 大量不同字符串 intern → Metaspace/堆泄漏
}

// ✅ 修复方案：使用 Caffeine 替代
private Cache<String, String> stringCache = Caffeine.newBuilder()
    .maximumSize(100000)
    .build();

public void process(String data) {
    String cached = stringCache.get(data, k -> k);
    // 有上限，不会无限增长
}
```

## 11.10 ClassLoader 泄漏

```java
// ❌ 泄漏代码：JSP 热加载
// 每次修改 JSP → 容器创建新的 ClassLoader 加载新编译的类
// 如果旧的 ClassLoader 未被回收 → Metaspace 泄漏

// 常见场景：
// 1. JDBC DriverManager 持有 Driver 引用
// 2. ThreadLocal 中存储了自定义 ClassLoader 加载的对象
// 3. 静态变量持有自定义 ClassLoader 加载的类

// ✅ 修复方案
// 1. 确保 ClassLoader 加载的类的实例都被释放
// 2. 使用 WeakReference 持有
// 3. 在 undeploy 时手动清理
```

## 11.11 Netty ByteBuf 泄漏

```java
// ❌ 泄漏代码
public void channelRead(ChannelHandlerContext ctx, Object msg) {
    ByteBuf buf = (ByteBuf) msg;
    byte[] data = new byte[buf.readableBytes()];
    buf.readBytes(data);
    // 忘记 buf.release() → Netty 堆外内存泄漏
}

// ✅ 修复方案
public void channelRead(ChannelHandlerContext ctx, Object msg) {
    ByteBuf buf = (ByteBuf) msg;
    try {
        byte[] data = new byte[buf.readableBytes()];
        buf.readBytes(data);
        // 处理 data...
    } finally {
        buf.release();  // 必须释放
    }
}

// 或使用 SimpleChannelInboundHandler（自动释放）
public class MyHandler extends SimpleChannelInboundHandler<ByteBuf> {
    @Override
    protected void channelRead0(ChannelHandlerContext ctx, ByteBuf buf) {
        // 处理完后 SimpleChannelInboundHandler 自动 release
    }
}
```

## 11.12 日志框架泄漏

```java
// ❌ 泄漏代码：大量 DEBUG 日志
if (logger.isDebugEnabled()) {
    logger.debug("Processing order: {}", JSON.toJSONString(largeOrderList));
}
// 如果 isDebugEnabled() 返回 true 但日志级别被错误修改
// 或在循环中调用 → 生成大量临时字符串

// ✅ 修复方案
// 1. 使用占位符 {} 而非字符串拼接
logger.debug("Order: {}", order);  // OK，不启用时不会调用 toString

// 2. 循环外判断
if (logger.isDebugEnabled()) {
    for (Order order : orders) {
        logger.debug("Order: {}", order);
    }
}

// 3. 避免在循环中做大量序列化
```

---

# 第十二部分：OOM 八种类型与排查

## 12.1 OOM 类型总览

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        8 种 OutOfMemoryError                            │
├──────────────────────┬──────────────────────────────────────────────────┤
│ OOM 类型              │ 触发原因                                          │
├──────────────────────┼──────────────────────────────────────────────────┤
│ 1. Java heap space    │ 堆内存不足，无法分配新对象                         │
│ 2. GC overhead limit  │ GC 占用 > 98% CPU 且回收 < 2% 堆                  │
│ 3. Metaspace          │ 元空间不足（类加载过多）                          │
│ 4. Direct buffer      │ 直接内存不足                                     │
│ 5. Unable to create   │ 无法创建新线程（线程数过多 / native 内存不足）    │
│    new native thread  │                                                  │
│ 6. Requested array    │ 请求的数组大小超过限制                             │
│    size exceeds VM    │                                                  │
│    limit             │                                                  │
│ 7. Out of swap space  │ 操作系统交换空间不足                               │
│ 8. Out of memory:     │ POSIX 的 mmap 失败                               │
│    kill process or    │ → Linux OOM Killer 杀死了进程                    │
│    sacrifice child   │                                                  │
└──────────────────────┴──────────────────────────────────────────────────┘
```

## 12.2 逐个排查

### 12.2.1 java.lang.OutOfMemoryError: Java heap space

```
原因：
  → 堆内存不足，无法分配新对象
  → 可能是内存泄漏（对象无法回收）
  → 也可能是对象太多（业务量真的需要更大堆）

排查步骤：
  1. 查看是否泄漏
     → jstat -gcutil <pid> 5000 20
     → 如果 Full GC 后 Old Gen 不降 → 泄漏
     → 如果 Full GC 后 Old Gen 下降但很快又满 → 对象太多

  2. 如果是泄漏 → jmap -dump → MAT 分析
  3. 如果是容量不足 → 加大 -Xmx

参数：
  → 堆大小：-Xms4g -Xmx4g
  → 自动 dump：-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/data/dumps/
  → 关闭 GC overhead 检查（调试时用）：-XX:-UseGCOverheadLimit
```

### 12.2.2 java.lang.OutOfMemoryError: GC overhead limit exceeded

```
原因：
  → GC 占用 > 98% CPU 时间
  → 且每次 GC 回收 < 2% 堆内存
  → 连续 5 次 → 抛出此错误
  → JVM 认为在做无用功（GC 太频繁但回收太少）

本质：这通常是内存泄漏的表现

排查：
  → 同 Java heap space
  → 检查是否有大量不可回收的对象

参数：
  → -XX:-UseGCOverheadLimit  关闭此检查（治标不治本，不推荐）
  → 正确做法：排查内存泄漏
```

### 12.2.3 java.lang.OutOfMemoryError: Metaspace

```
原因：
  → 元空间（Metaspace）不足
  → 类加载过多（动态代理/CGLIB/反射/热部署）

排查步骤：
  1. jstat -gcutil <pid> → 看 M 列是否持续增长
  2. jmap -clstats <pid> → 查看类加载器数量
  3. -XX:+TraceClassLoading -XX:+TraceClassUnloading → 打印类加载/卸载日志
  4. MAT → 搜索 ClassLoader → 查看实例数

常见场景：
  → CGLIB 动态代理创建过多类（每次创建代理都生成新类）
  → 反射 Method.invoke 在阈值以上动态生成字节码类
  → Groovy 脚本动态编译
  → JSP 重新编译

修复：
  → 查找并修复类加载器泄漏
  → -XX:MaxMetaspaceSize=512m 限制上限（防止无限增长）
```

### 12.2.4 java.lang.OutOfMemoryError: Direct buffer memory

```
原因：
  → 直接内存（NIO DirectByteBuffer）不足
  → 通常是 Netty ByteBuf 或 NIO ByteBuffer 未释放

排查步骤：
  1. 检查 MaxDirectMemorySize
     jinfo -flag MaxDirectMemorySize <pid>

  2. 开启 NMT 查看
     -XX:NativeMemoryTracking=summary
     jcmd <pid> VM.native_memory summary | grep "Internal"

  3. 查看进程 RSS
     top -p <pid>  → RES 列持续增长

  4. Netty 内存泄漏检测
     -Dio.netty.leakDetection.level=PARANOID

修复：
  → 确保 ByteBuf.release() / try-with-resources
  → -XX:MaxDirectMemorySize=1g 设置上限
  → Netty 检查 ByteBuf 引用计数
```

### 12.2.5 java.lang.OutOfMemoryError: unable to create new native thread

```
原因：
  → 无法创建新操作系统线程
  → 不是 JVM 堆内存不足，而是操作系统级别的限制
  → 线程数超过系统限制 / native 内存不足

排查步骤：
  1. 查看当前线程数
     jstack <pid> | grep "java.lang.Thread.State:" | wc -l
     # 或
     jcmd <pid> Thread.print | grep "java.lang.Thread.State:" | wc -l

  2. 查看系统线程限制
     ulimit -u        # 用户最大进程/线程数
     cat /proc/sys/kernel/threads-max  # 系统最大线程数
     cat /proc/<pid>/status | grep Threads  # 进程当前线程数

  3. 常见原因：
     → 线程池配置过大（如 newFixedThreadPool(10000)）
     → 每个请求创建新线程（未使用线程池）
     → 线程泄漏（线程不退出）

修复：
  → 使用合理的线程池配置
  → -Xss256k 减小每个线程的栈大小
  → 调高系统限制：ulimit -u 65535
  → 使用虚拟线程（JDK 21+）
```

### 12.2.6 java.lang.OutOfMemoryError: Requested array size exceeds VM limit

```
原因：
  → 尝试创建一个超过 JVM 限制的数组
  → 通常是因为 Integer.MAX_VALUE 附近的 size 被错误传入

示例：
  byte[] data = new byte[Integer.MAX_VALUE];  // 2GB 数组 → 可能触发

修复：
  → 检查数组大小的计算逻辑
  → 分块处理（如分页查询代替一次性查全部）
```

### 12.2.7 java.lang.OutOfMemoryError: Out of swap space

```
原因：
  → 操作系统交换空间（swap）不足
  → JVM 申请 native 内存时系统无法满足

排查：
  → free -m  → 查看 swap 使用情况
  → 增加系统 swap 空间
  → 减少 JVM 堆大小
```

### 12.2.8 Out of memory: Kill process or sacrifice child (OOM Killer)

```
原因：
  → 不是 JVM 报错，是 Linux 内核 OOM Killer 杀死了进程
  → 进程使用内存超过系统限制
  → 内核选择内存占用最高的进程杀死

排查：
  1. 查看系统日志
     dmesg | grep -i "out of memory"
     dmesg | grep -i "killed process"

  2. 日志示例：
     "Out of memory: Kill process 12345 (java) score 800 or sacrifice child"

  3. 查看进程内存使用
     top → 按 RES 排序

修复：
  → 减少 JVM 堆大小（-Xmx）
  → 检查直接内存泄漏
  → 增加 Docker 内存限制：--memory=4g
  → 调整 OOM 评分：echo -1000 > /proc/<pid>/oom_score_adj
  → 设置 swap
```

---

# 第十三部分：Full GC 频繁排查

## 13.1 Full GC 常见原因

```
┌──────────────────────────────────────────────────────────────┐
│              Full GC 频繁原因分类                              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 内存泄漏                                                  │
│     → Old Gen 持续增长 → 反复 Full GC 但回收效果差           │
│                                                              │
│  2. 大对象直接进老年代                                        │
│     → -XX:PretenureSizeThreshold 设置不当                   │
│     → 或确实有大对象分配                                      │
│     → 每次大对象分配 → 老年代快速增长 → Full GC              │
│                                                              │
│  3. 空间分配担保失败                                          │
│     → Minor GC 前检查老年代空间是否足够                      │
│     → 不够 → Full GC                                         │
│     → 通常因为新生代太大或老年代太小                          │
│                                                              │
│  4. Metaspace 不足                                           │
│     → 类加载触发 GC                                          │
│     → MetaspaceSize 设太小                                   │
│                                                              │
│  5. System.gc() 被调用                                        │
│     → 代码中显式调用 System.gc()                              │
│     → 框架（如 RMI 默认每小时调一次）                         │
│     → -XX:+DisableExplicitGC 禁用                            │
│                                                              │
│  6. CMS Concurrent Mode Failure                              │
│     → CMS 回收速度跟不上分配速度                              │
│     → 退化为 Serial Old Full GC                             │
│     → 调低 CMSInitiatingOccupancyFraction                   │
│                                                              │
│  7. G1 分配速率过高                                           │
│     → 对象分配速度快于 Mixed GC 回收速度                    │
│     → 调低 InitiatingHeapOccupancyPercent                    │
│     → 或增大堆                                               │
│                                                              │
│  8. 内存碎片（CMS）                                           │
│     → CMS 使用标记-清除 → 碎片化                             │
│     → 大对象分配时空间不足 → Full GC + 整理                  │
│     → -XX:+UseCMSCompactAtFullCollection                    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## 13.2 排查流程

```
Step 1: 确认 Full GC 类型
  jstat -gccause <pid> 5000 10
  → LGCC 列显示最近一次 GC 原因

Step 2: 如果原因是 "Allocation Failure"
  → 是 Minor GC 不是 Full GC
  → 如果 Full GC 原因是 "System.gc()" → 查谁调用了 System.gc()

Step 3: 如果原因是 "System.gc()"
  → -XX:+DisableExplicitGC 禁用
  → 或检查代码中哪里调用了 System.gc()

Step 4: 如果原因是 "Metadata GC Threshold"
  → Metaspace 触发
  → -XX:MetaspaceSize=256m 提高初始阈值

Step 5: 如果原因是 "CMS Final Remark" 或 "G1 Evacuation"
  → 正常的 GC，检查频率是否合理
  → 调优 GC 参数

Step 6: 如果 Old Gen 持续增长不下降
  → 内存泄漏 → jmap -dump → MAT 分析
```

## 13.3 System.gc() 排查

```bash
# 方式 1：禁用 System.gc()
-XX:+DisableExplicitGC

# 方式 2：Arthas 查看 System.gc() 的调用栈
stack java.lang.System gc

# 方式 3：JFR 记录
jfr print --events jdk.GCConfiguration /tmp/flight.jfr | grep -i "system"

# 常见来源：
# 1. RMI 默认 1 小时调用一次 → -Dsun.rmi.dgc.client/server.gcInterval=3600000
# 2. 某些库在操作后调 System.gc()（如 NIO ByteBuffer 清理）
# 3. 代码中手写 System.gc()
```

---

# 第十四部分：CPU 飙高排查

## 14.1 CPU 飙高的常见原因

```
┌──────────────────────────────────────────────────────────────┐
│              CPU 飙高原因分类                                  │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. GC 频繁                                                   │
│     → Full GC 占用大量 CPU                                   │
│     → CMS/G1 并发标记消耗 CPU                                │
│     → 排查：jstat -gcutil 看 GC 频率                         │
│                                                              │
│  2. 死循环 / 死递归                                           │
│     → 代码 bug → 线程空转                                     │
│     → 排查：jstack 查看线程栈                                 │
│                                                              │
│  3. 锁竞争 / 自旋                                             │
│     → 大量线程争抢同一把锁 → 自旋消耗 CPU                     │
│     → 排查：jstack 看 BLOCKED 线程                            │
│                                                              │
│  4. 大量计算                                                 │
│     → 正常业务计算密集 → 加机器 / 优化算法                    │
│     → 排查：profiler 火焰图                                  │
│                                                              │
│  5. 正则表达式                                                │
│     → 灾难性回溯（ReDoS）→ CPU 100%                          │
│     → 排查：jstack 查看 Pattern.match 栈帧                   │
│                                                              │
│  6. 线程太多                                                  │
│     → 上下文切换开销大                                       │
│     → 排查：jstack 统计线程数                                │
│                                                              │
│  7. 序列化/反序列化                                           │
│     → JSON 序列化大对象                                       │
│     → 排查：profiler 火焰图                                  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## 14.2 CPU 飙高排查流程

```bash
# Step 1: 确认是 Java 进程 CPU 高
top -c
# 找到 CPU 最高的 Java 进程 PID

# Step 2: 确认是 GC 还是业务代码
jstat -gcutil <pid> 1000 5
# 如果 FGC 快速增长或 YGC 极其频繁 → GC 问题
# 如果 GC 不频繁但 CPU 高 → 业务代码问题

# Step 3a: 如果是 GC 问题
# → 按 Full GC 排查流程处理

# Step 3b: 如果是业务代码问题
# → 找 CPU 最高的线程
top -Hp <pid>
# 记录 TID（线程 ID）

# Step 4: 转换 TID 为十六进制
printf "%x\n" <tid>
# 输出如：304e

# Step 5: 在 jstack 中查找
jstack <pid> | grep "0x304e" -A 30
# 或用 Arthas
# thread -n 3  # 直接看 CPU 最高的 3 个线程栈
```

## 14.3 Arthas 排查 CPU 飙高

```bash
# 方法 1：直接看 CPU 最高的线程
[arthas@pid]$ thread -n 5

# 方法 2：看 BLOCKED 线程
[arthas@pid]$ thread -b

# 方法 3：火焰图
[arthas@pid]$ profiler start
# 等 30 秒
[arthas@pid]$ profiler stop --format html

# 方法 4：trace 方法耗时
[arthas@pid]$ trace com.example.service.HotService * '#cost > 10'
```

---

# 第十五部分：生产环境在线诊断流程

## 15.1 SOP 标准操作流程

```
┌──────────────────────────────────────────────────────────────────────┐
│            生产环境 JVM 诊断 SOP（标准操作流程）                      │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  接到报警 / 用户反馈 "服务慢 / 报错 / CPU高 / 内存高"                  │
│                                                                      │
│  Step 1: 快速评估影响                                                │
│    → 是否影响核心业务？                                               │
│    → 是否需要立即重启？                                               │
│    → 是否可以摘除流量（灰度/降级）？                                   │
│                                                                      │
│  Step 2: 收集基础信息                                                │
│    → jcmd <pid> VM.flags      → JVM 参数                            │
│    → jstat -gcutil <pid> 1000 10 → GC 统计                          │
│    → jstack <pid> > /tmp/jstack.txt → 线程栈                        │
│    → jmap -histo <pid> | head -30 → 对象直方图                      │
│    → top -Hp <pid> → CPU 最高的线程                                  │
│                                                                      │
│  Step 3: 初步定位                                                    │
│    ├─ GC 频繁？                                                      │
│    │   → Old Gen 是否持续增长 → 内存泄漏？                           │
│    │   → Full GC 原因是什么？                                        │
│    │   → Metaspace 是否增长？                                        │
│    │                                                                  │
│    ├─ CPU 高？                                                       │
│    │   → 是 GC 线程还是业务线程？                                     │
│    │   → 有死循环 / 死锁？                                           │
│    │   → 火焰图定位热点方法                                          │
│    │                                                                  │
│    ├─ 线程 BLOCKED？                                                 │
│    │   → 哪个锁被争抢？                                               │
│    │   → 是否有死锁？                                                │
│    │   → 数据库连接池是否耗尽？                                       │
│    │                                                                  │
│    └─ 直接内存增长？                                                 │
│        → NMT 查看直接内存使用                                         │
│        → Netty ByteBuf 泄漏检测                                       │
│                                                                      │
│  Step 4: 深入分析                                                    │
│    → jmap -dump → MAT 分析（内存问题）                               │
│    → profiler 火焰图（CPU 问题）                                     │
│    → Arthas trace/watch（方法级定位）                                │
│                                                                      │
│  Step 5: 修复                                                        │
│    → 代码修复 → 发版                                                 │
│    → 临时措施：重启 / 降级 / 扩容                                    │
│                                                                      │
│  Step 6: 复盘                                                        │
│    → 记录排查全过程                                                   │
│    → 补充监控和报警                                                   │
│    → 建立预防机制（代码审查 / 压测）                                 │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## 15.2 一键诊断脚本

```bash
#!/bin/bash
# jvm-diagnose.sh - JVM 一键诊断脚本
PID=$1
if [ -z "$PID" ]; then
    echo "Usage: $0 <pid>"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DIR="/tmp/jvm-diagnose-${PID}-${TIMESTAMP}"
mkdir -p "$DIR"

echo "=== JVM 诊断开始 ==="
echo "PID: $PID"
echo "输出目录: $DIR"

# 1. JVM 参数
jcmd "$PID" VM.flags > "$DIR/vm_flags.txt" 2>&1
echo "[1/8] JVM 参数已收集"

# 2. GC 统计（5 秒 × 10 次）
jstat -gcutil "$PID" 1000 10 > "$DIR/gc_stat.txt" 2>&1
echo "[2/8] GC 统计已收集"

# 3. GC 原因
jstat -gccause "$PID" > "$DIR/gc_cause.txt" 2>&1
echo "[3/8] GC 原因已收集"

# 4. 线程栈
jstack -l "$PID" > "$DIR/jstack.txt" 2>&1
echo "[4/8] 线程栈已收集"

# 5. 对象直方图
jmap -histo "$PID" > "$DIR/histo.txt" 2>&1
echo "[5/8] 对象直方图已收集"

# 6. 堆信息
jcmd "$PID" GC.heap_info > "$DIR/heap_info.txt" 2>&1
echo "[6/8] 堆信息已收集"

# 7. CPU 最高的线程
top -Hbn 1 -p "$PID" > "$DIR/top_threads.txt" 2>&1
echo "[7/8] 线程 CPU 使用已收集"

# 8. 线程统计
jstack "$PID" | grep "java.lang.Thread.State:" | \
  sort | uniq -c | sort -rn > "$DIR/thread_stats.txt" 2>&1
echo "[8/8] 线程统计已收集"

echo ""
echo "=== 诊断完成 ==="
echo "所有文件位于: $DIR"
echo ""
echo "快速分析："
echo "  1. 看 GC: cat $DIR/gc_stat.txt"
echo "  2. 看线程: cat $DIR/thread_stats.txt"
echo "  3. 看对象: head -20 $DIR/histo.txt"
echo "  4. 看堆: cat $DIR/heap_info.txt"
```

---

# 第十六部分：15 个真实案例分析

## 案例 1：HashMap 导致内存泄漏

```
现象：线上服务每隔 2~3 天 OOM 重启

排查过程：
  1. jstat -gcutil → Old Gen 持续增长，Full GC 后不降
  2. jmap -histo → byte[] 和 String 最多，持续增长
  3. jmap -dump → MAT 分析
  4. Dominator Tree → ConcurrentHashMap 占 1.5GB
  5. Path to GC Roots → static UserSessionManager.sessions
  6. 代码：用户登录后 put 到 session map，登出后未 remove

根因：UserSessionManager 使用 static ConcurrentHashMap 存储用户会话，
     用户登出时未调用 remove → 会话对象泄漏

修复：
  → 使用 Caffeine Cache 替代 ConcurrentHashMap
  → 设置 expireAfterAccess(30, TimeUnit.MINUTES) 自动过期
  → 增加登录/登出时的 put/remove 配对检查

教训：永远不要使用无上限的静态集合做缓存
```

## 案例 2：ThreadLocal 在线程池中泄漏

```
现象：Tomcat 处理一段时间后内存缓慢增长

排查过程：
  1. jmap -histo 对比 → UserContext 对象持续增长
  2. MAT → Path to GC Roots → ThreadLocalMap
  3. ThreadLocalMap 是 Thread 的字段
  4. Tomcat 使用线程池 → 线程复用
  5. 每次请求 ThreadLocal.set(userContext) 但不 remove
  6. ThreadLocalMap 中的 Entry 持有 UserContext

根因：ThreadLocal.set 后未 remove，线程池线程复用导致积累

修复：
  → try-finally 中 ThreadLocal.remove()
  → 使用 Filter/Interceptor 统一清理
  → 或使用 TransmittableThreadLocal（阿里 TTL）

教训：线程池 + ThreadLocal = 定时炸弹，必须 remove
```

## 案例 3：数据库连接泄漏

```
现象：服务运行 6 小时后报 "Cannot get a connection, pool error"

排查过程：
  1. 异常栈指向 Druid 连接池
  2. jstack → 多个线程 WAITING（等连接）
  3. Druid 监控页面 → 活跃连接数 = 最大连接数
  4. 代码审查 → 某方法中 getConnection() 在异常路径未 close
  5. 异常时跳过了 close() → 连接未归还 → 池耗尽

根因：异常路径未释放数据库连接

修复：
  → 全部改为 try-with-resources
  → 配置 Druid removeAbandoned=true 自动回收泄漏连接
  → 增加单元测试覆盖异常路径

教训：任何资源获取都必须 try-finally 或 try-with-resources
```

## 案例 4：Full GC 每小时触发一次

```
现象：每小时准时一次 Full GC

排查过程：
  1. jstat -gccause → LGCC = "System.gc()"
  2. 每小时一次 → 定时任务
  3. stack java.lang.System gc → 调用栈指向 RMI
  4. RMI 默认 1 小时调用 System.gc()

根因：RMI 的 DGC（分布式 GC）默认每小时调用 System.gc()

修复：
  → -Dsun.rmi.dgc.client.gcInterval=9223372036854775807
  → -Dsun.rmi.dgc.server.gcInterval=9223372036854775807
  → 或 -XX:+DisableExplicitGC 禁用 System.gc()

教训：了解框架的默认行为，System.gc() 的影响很大
```

## 案例 5：Metaspace 泄漏

```
现象：Metaspace 持续增长，最终 Metaspace OOM

排查过程：
  1. jstat -gcutil → M 列持续增长
  2. jmap -clstats → 类加载器数量异常多
  3. -XX:+TraceClassLoading → 大量类被加载
  4. MAT → ClassLoader 实例数 = 200+
  5. 代码：每次报表导出都动态创建 ClassLoader 加载编译 Groovy 脚本

根因：Groovy 脚本每次创建新 ClassLoader，旧 ClassLoader 未回收

修复：
  → 缓存 GroovyClassLoader，脚本不变时不重新编译
  → 使用 GroovyShell 缓存编译结果
  → -XX:MaxMetaspaceSize=512m 设上限

教训：动态类生成必须缓存 ClassLoader
```

## 案例 6：CPU 100% — ReDoS 正则回溯

```
现象：某个接口 CPU 突然 100%，服务假死

排查过程：
  1. top -Hp → 某线程 CPU 100%
  2. jstack → 栈帧在 java.util.regex.Pattern.match()
  3. 定位到输入校验的正则表达式
  4. 正则：^(a+)+$，输入 "aaaaaaaaaaaaaaaaaaaa!"
  5. 灾难性回溯（指数级）

根因：正则表达式设计缺陷 → ReDoS 攻击

修复：
  → 优化正则表达式（避免嵌套量词）
  → 使用预编译 Pattern + 超时控制
  → 输入长度限制

教训：用户输入的正则校验要注意回溯风险
```

## 案例 7：Netty 堆外内存泄漏

```
现象：进程 RSS 持续增长，但 JVM 堆正常

排查过程：
  1. jstat -gcutil → 堆正常
  2. top -p → RES 持续增长
  3. -XX:NativeMemoryTracking=summary → Internal 段增长
  4. jcmd VM.native_memory → Direct 段异常
  5. -Dio.netty.leakDetection.level=PARANOID → 检测到泄漏
  6. 日志显示 ByteBuf 未 release

根因：自定义 ChannelHandler 中 ByteBuf 未 release

修复：
  → 继承 SimpleChannelInboundHandler（自动 release）
  → 或在 finally 中 buf.release()
  → 添加 ReferenceCountUtil.release(msg)

教训：Netty ByteBuf 的引用计数必须配对，泄漏不会导致 Java OOM
```

## 案例 8：大对象直接进老年代

```
现象：Minor GC 很少，但 Full GC 频繁

排查过程：
  1. jstat -gcutil → YGC 少，FGC 多
  2. GC 日志 → Full GC 前有 "humongous allocation"（G1）
  3. 代码 → 每次查询加载所有结果到 List
  4. SELECT * FROM big_table → 50 万行 → 200MB List 对象

根因：大对象（List 超过 Region 的一半）直接进 Old Region

修复：
  → 分页查询（每次 1000 条）
  → 流式处理（MyBatis Cursor / JPA Stream）
  → -XX:G1HeapRegionSize=32m 增大 Region

教训：避免一次性加载大量数据到内存
```

## 案例 9：Concurrent Mode Failure

```
现象：CMS 服务偶尔出现长时间停顿

排查过程：
  1. GC 日志 → "Concurrent Mode Failure"
  2. CMS 回收速度跟不上分配速度
  3. 老年代在 CMS 回收期间就被填满 → 退化为 Serial Old

根因：CMSInitiatingOccupancyFraction 设置太高（92%）

修复：
  → -XX:CMSInitiatingOccupancyFraction=70
  → -XX:+UseCMSInitiatingOccupancyOnly
  → 增大老年代或改用 G1

教训：CMS 阈值宁低勿高，留足浮动垃圾空间
```

## 案例 10：死锁导致服务假死

```
现象：所有接口超时，但 CPU 不高

排查过程：
  1. jstack → 发现死锁
  2. Thread-A 持有 lock1 等 lock2
  3. Thread-B 持有 lock2 等 lock1
  4. 代码：两个方法以不同顺序获取锁

根因：锁顺序不一致导致死锁

修复：
  → 全局统一锁获取顺序
  → 使用 tryLock(timeout) 替代 synchronized
  → 使用细粒度锁替代粗粒度锁

教训：多锁场景必须保证获取顺序一致
```

## 案例 11：Lambda 捕获 this 导致泄漏

```
现象：某个 Controller 的对象无法被 GC

排查过程：
  1. MAT → Controller 被 ScheduledExecutorService 持有
  2. 代码：executor.scheduleAtFixedRate(this::cleanup, ...)
  3. Lambda this::cleanup 隐式捕获 this
  4. this = Controller 实例 → 被 ScheduledFuture 持有

根因：Lambda 方法引用捕获外部类 this 引用

修复：
  → 改为静态方法引用：MyService::cleanup
  → 或使用独立对象，不引用 Controller
  → 确保定时任务有取消机制

教训：Lambda/方法引用的 this 捕获要小心
```

## 案例 12：CGLIB 代理类 Metaspace 泄漏

```
现象：频繁热加载后 Metaspace OOM

排查过程：
  1. jmap -clstats → ClassLoader 数量 500+
  2. 每个 ClassLoader 加载了 CGLIB 代理类
  3. 动态配置中心每次更新都重新创建代理
  4. 旧 ClassLoader 未回收（有引用持有）

根因：动态代理重新生成时旧 ClassLoader 未释放

修复：
  → 缓存代理类，配置不变时不重新生成
  → 确保旧 ClassLoader 无引用后能被 GC
  → 使用 Spring AOP（内部有代理缓存）

教训：动态代理类要缓存，避免重复创建
```

## 案例 13：finalize 方法导致 GC 问题

```
现象：Full GC 耗时很长

排查过程：
  1. GC 日志 → Final Reference 相关耗时
  2. jmap -finalizerinfo → 2000+ 对象在 F-Queue
  3. 代码：某类覆写了 finalize()，且 finalize 执行很慢（I/O 操作）

根因：finalize 方法执行慢，F-Queue 堆积，影响 GC

修复：
  → 删除 finalize 方法，改用 try-with-resources
  → 或使用 Cleaner/PhantomReference 替代
  → JDK 9+ finalize 已标记 @Deprecated

教训：永远不要使用 finalize，JDK 18 已移除
```

## 案例 14：Spring Boot DevTools 导致 Metaspace 泄漏

```
现象：开发环境频繁重启后 Metaspace OOM

排查过程：
  1. Metaspace 持续增长
  2. jmap -clstats → DevTools 的 ClassLoader
  3. Spring Boot DevTools 热加载创建新 ClassLoader
  4. 旧 ClassLoader 因 ThreadLocal/静态变量持有无法回收

根因：热加载时旧 ClassLoader 未正确释放

修复：
  → 生产环境移除 DevTools（scope=runtime,optional=true）
  → 开发环境定期手动重启
  → 避免在热加载的类中使用静态变量持有外部引用

教训：DevTools 只用于开发环境，生产环境必须移除
```

## 案例 15：Docker 容器 OOM Killed

```
现象：容器被 OOM Killer 杀死，但 Java 没有 OOM

排查过程：
  1. dmesg → "Out of memory: Kill process 12345 (java)"
  2. Docker --memory=2g，JVM -Xmx1800m
  3. 堆 1.8GB + Metaspace + 线程栈 + Code Cache + 直接内存 > 2GB
  4. 进程总内存超过容器限制 → 被 OOM Killer 杀

根因：JVM 总内存 > 堆内存，容器限制未留足够余量

修复：
  → -Xmx1.4g（堆 ≤ 容器内存的 70%）
  → -XX:MaxMetaspaceSize=256m
  → -XX:MaxDirectMemorySize=256m
  → -Xss512k
  → Docker --memory=2g → 实际可用约 1.6GB

教训：容器内存 = 堆 + Metaspace + 栈 × 线程数 + 直接内存 + Code Cache + 预留
```

---

# 第十七部分：JVM 调优实战清单

## 17.1 上线前 Check List

```
┌──────────────────────────────────────────────────────────────┐
│              JVM 上线前 Check List                            │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  □ 1. 堆参数                                                 │
│     □ -Xms = -Xmx（避免扩容缩容）                            │
│     □ -Xmx ≤ 容器内存的 70%~75%                              │
│     □ -Xmn 或 NewRatio 合理                                  │
│     □ -XX:SurvivorRatio=8                                   │
│     □ -XX:MaxTenuringThreshold=15                            │
│                                                              │
│  □ 2. Metaspace                                              │
│     □ -XX:MetaspaceSize=256m                                 │
│     □ -XX:MaxMetaspaceSize=512m                              │
│                                                              │
│  □ 3. 线程栈                                                 │
│     □ -Xss512k（或 256k 如果线程数多）                       │
│                                                              │
│  □ 4. GC 收集器                                              │
│     □ JDK 8: -XX:+UseG1GC 或 CMS                            │
│     □ JDK 11+: -XX:+UseG1GC（默认）                         │
│     □ JDK 15+: -XX:+UseZGC（大堆或超低延迟）                │
│                                                              │
│  □ 5. GC 日志                                                │
│     □ 开启 GC 日志                                            │
│     □ 日志滚动（NumberOfGCLogFiles=10, GCLogFileSize=100M） │
│     □ 日志路径正确且有写入权限                                │
│                                                              │
│  □ 6. OOM 自动 Dump                                         │
│     □ -XX:+HeapDumpOnOutOfMemoryError                       │
│     □ -XX:HeapDumpPath=/data/dumps/                         │
│     □ dump 目录有足够磁盘空间                                │
│                                                              │
│  □ 7. 直接内存                                               │
│     □ -XX:MaxDirectMemorySize=1g（如果用 NIO/Netty）       │
│     □ Netty: -Dio.netty.leakDetection.level=SIMPLE         │
│                                                              │
│  □ 8. NMT（Native Memory Tracking）                         │
│     □ -XX:NativeMemoryTracking=summary                      │
│                                                              │
│  □ 9. 其他                                                   │
│     □ -XX:+DisableExplicitGC（禁用 System.gc()）            │
│     □ -XX:+AlwaysPreTouch（启动时预分配物理内存）           │
│     □ -Dfile.encoding=UTF-8                                 │
│     □ -Duser.timezone=Asia/Shanghai                         │
│                                                              │
│  □ 10. 监控                                                  │
│      □ Prometheus + Grafana JVM 监控                       │
│      □ Old Gen > 85% 报警                                   │
│      □ Full GC > 5次/小时 报警                              │
│      □ Full GC 耗时 > 1s 报警                               │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## 17.2 推荐的 JVM 参数模板

### 17.2.1 中型应用（8GB 容器，G1）

```bash
# 堆
-Xms4g -Xmx4g
-XX:MaxMetaspaceSize=256m
-Xss512k

# GC
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200
-XX:G1HeapRegionSize=16m
-XX:InitiatingHeapOccupancyPercent=45
-XX:G1NewSizePercent=20
-XX:G1MaxNewSizePercent=60

# 直接内存
-XX:MaxDirectMemorySize=512m

# GC 日志
-Xlog:gc*:file=/data/log/gc/gc.log:time,uptime,level,tags:filecount=10,filesize=100m

# OOM Dump
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/data/dumps/

# 其他
-XX:+DisableExplicitGC
-XX:+AlwaysPreTouch
-XX:NativeMemoryTracking=summary
-Dfile.encoding=UTF-8
-Duser.timezone=Asia/Shanghai
```

### 17.2.2 大型应用（32GB 物理机，G1）

```bash
-Xms16g -Xmx16g
-XX:MaxMetaspaceSize=512m
-Xss512k

-XX:+UseG1GC
-XX:MaxGCPauseMillis=200
-XX:G1HeapRegionSize=32m
-XX:InitiatingHeapOccupancyPercent=40
-XX:ParallelGCThreads=16
-XX:ConcGCThreads=4

-XX:MaxDirectMemorySize=2g

-Xlog:gc*:file=/data/log/gc/gc.log:time,uptime,level,tags:filecount=20,filesize=200m
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/data/dumps/

-XX:+DisableExplicitGC
-XX:+AlwaysPreTouch
-XX:NativeMemoryTracking=summary
-Dfile.encoding=UTF-8
-Duser.timezone=Asia/Shanghai
```

### 17.2.3 低延迟应用（ZGC，JDK 17+）

```bash
-Xms8g -Xmx8g
-XX:MaxMetaspaceSize=256m
-Xss512k

-XX:+UseZGC
-XX:ConcGCThreads=4
-XX:ParallelGCThreads=16

-Xlog:gc*:file=/data/log/gc/gc.log:time,uptime,level,tags:filecount=10,filesize=100m
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/data/dumps/

-XX:+DisableExplicitGC
-XX:+AlwaysPreTouch
-XX:NativeMemoryTracking=summary
```

---

# 第十八部分：面试高频题 30 问

### Q1: -Xms 和 -Xmx 为什么要设为相同？

**答**：避免 JVM 运行期间堆的扩容和缩容。扩容需要向 OS 申请内存、重映射堆空间（可能触发 STW），缩容可能触发额外 GC。设为相同后堆大小固定，行为可预测，减少不必要的 GC。

### Q2: JVM 调优最重要的参数是什么？

**答**：`-Xmx`（最大堆）和 GC 收集器选择。先确定堆大小（根据物理内存的 60%~70%），再选收集器（4GB 以下用 Parallel，4~32GB 用 G1，32GB 以上或超低延迟用 ZGC）。其他参数都是微调。

### Q3: 什么时候用 CMS、什么时候用 G1？

**答**：CMS 适合 4~8GB 堆、对停顿敏感的应用（但 JDK 14 已废弃）。G1 适合 4~32GB 堆、需要可预测停顿的应用。ZGC 适合 32GB 以上堆或需要 < 10ms 停顿的场景。JDK 9+ 默认 G1。

### Q4: -XX:MaxGCPauseMillis 设为多少合适？

**答**：交互型应用 100~200ms，后台服务 200~500ms。设太低（如 50ms）会导致 G1 每次 GC 只回收很少 Region，反而更频繁甚至 Full GC。

### Q5: 说说你对 -XX:NewRatio 的理解？

**答**：NewRatio 控制新生代与老年代的比例。NewRatio=2 表示新生代:老年代=1:2。默认值 ParallelGC 是 2，G1 动态调整。新生代太小 → Minor GC 频繁；太大 → 老年代不足 → Full GC。一般 1:2 或 1:3。

### Q6: 什么是内存泄漏？和内存溢出什么区别？

**答**：内存泄漏是对象不再使用但仍被引用，无法被 GC 回收。内存溢出是 JVM 无法分配内存，抛出 OOM。泄漏是渐进的——逐渐积累最终导致 OOM。OOM 是泄漏的终态，也可能是容量不足（非泄漏）。

### Q7: 怎么排查内存泄漏？

**答**：四步法——发现（监控 Old Gen 持续增长）、定位（jmap -histo 对比 + 堆 dump + MAT 分析）、修复（Path to GC Roots 找引用链 → 修改代码）、验证（部署后观察趋势）。

### Q8: MAT 的 Shallow Size 和 Retained Size 区别？

**答**：Shallow Size 是对象自身占用的内存（不含引用的对象）。Retained Size 是对象被回收后能释放的总内存（自身 + 只有它引用的对象）。排查泄漏时看 Retained Size，找出占用内存最大的对象。

### Q9: ThreadLocal 为什么会内存泄漏？

**答**：ThreadLocalMap 的 Entry 继承 WeakReference<ThreadLocal>，Key（ThreadLocal）是弱引用，但 Value 是强引用。ThreadLocal 被回收后 Key 变 null，但 Value 仍被 Entry 引用 → Value 无法回收。在线程池场景下，线程复用导致 ThreadLocalMap 积累。解决：使用后调用 remove()。

### Q10: Full GC 频繁怎么排查？

**答**：先看 GC 原因（jstat -gccause）。如果是 System.gc() → DisableExplicitGC。如果是内存泄漏 → dump 分析。如果是 Metaspace → 查类加载器。如果是大对象 → 查代码是否有大 List/数组。如果是 CMS CMF → 降低触发阈值。

### Q11: 生产环境怎么 dump 堆？

**答**：优先用 `-XX:+HeapDumpOnOutOfMemoryError` 自动 dump。手动 dump 用 `jcmd <pid> GC.heap_dump`，但会 STW，建议低峰期。不要用 `jmap -histo:live`（触发 Full GC）。

### Q12: jstack 怎么找 CPU 最高的线程？

**答**：`top -Hp <pid>` 找 CPU 最高的线程 TID → `printf "%x\n" TID` 转十六进制 → `jstack <pid> | grep "0xTID" -A 30` 看线程栈。或直接用 Arthas `thread -n 3`。

### Q13: CPU 飙高但 GC 不频繁，什么原因？

**答**：大概率是业务代码问题——死循环、死锁自旋、大量计算、正则回溯（ReDoS）。用 `top -Hp` + `jstack` 或 Arthas `thread -n 5` 定位线程，再 `profiler` 火焰图找热点方法。

### Q14: -XX:+HeapDumpOnOutOfMemoryError 的作用？

**答**：JVM 在抛出 OOM 前自动 dump 堆到文件。这是排查 OOM 的最佳实践，不需要人工介入就能拿到 dump 文件。配合 `-XX:HeapDumpPath` 指定 dump 文件路径。

### Q15: 容器环境下 JVM 怎么配置内存？

**答**：`-Xmx` 不超过容器内存的 70%~75%。因为 JVM 总内存 = 堆 + Metaspace + 线程栈 × 线程数 + 直接内存 + Code Cache。JDK 11+ 用 `-XX:MaxRAMPercentage=75.0` 自动按容器内存计算。

### Q16: Arthas 的 trace 和 watch 有什么区别？

**答**：trace 追踪方法内部调用链的耗时，适合定位"方法慢在哪里"。watch 观察方法入参出参和异常，适合"方法执行结果是什么"。trace 看耗时分布，watch 看数据。

### Q17: 什么是 NMT？什么时候用？

**答**：Native Memory Tracking，跟踪 JVM 原生内存使用（堆外）。用于排查直接内存泄漏、线程栈内存、Code Cache 等。`-XX:NativeMemoryTracking=summary` 开启，`jcmd <pid> VM.native_memory summary` 查看。开销约 5~10%，生产环境可以接受。

### Q18: GC overhead limit exceeded 是什么意思？

**答**：GC 占用 > 98% CPU 且每次回收 < 2% 堆，连续 5 次 → JVM 认为在做无用功。本质是内存泄漏的表现。可以用 `-XX:-UseGCOverheadLimit` 关闭但治标不治本，应该排查泄漏。

### Q19: 怎么预防内存泄漏？

**答**：代码层面——try-with-resources、ThreadLocal.remove()、缓存用 Caffeine、监听器成对注册/注销。测试层面——压测覆盖异常路径。监控层面——Old Gen 持续增长报警、Full GC 频率报警、OOM 自动 dump。Code Review 检查资源释放。

### Q20: JVM 常用监控工具有哪些？

**答**：命令行——jstat（GC 统计）、jmap（堆信息）、jstack（线程栈）、jcmd（统一管理）。可视化——JConsole/VisualVM（实时监控）、MAT（堆 dump 分析）、JProfiler（CPU/内存 profiling）。在线诊断——Arthas（无侵入 attach）、JFR（飞行记录器）、async-profiler（火焰图）。

### Q21: G1 的 IHOP 调到多少合适？

**答**：默认 45%。如果 Mixed GC 跟不上（老年代持续增长→Full GC）→ 降到 35%~40%。如果 Full GC 不频繁但 CPU 高 → 降到 35%。如果一切正常 → 不要动。

### Q22: -XX:+AlwaysPreTouch 是做什么的？

**答**：启动时预先分配并触摸所有堆内存页（写入零值）。好处是启动后所有堆内存已映射到物理内存，运行时不会有缺页中断。代价是启动变慢。适合容器环境（避免运行时 OOM Killer）和内存数据库。

### Q23: 怎么判断是内存泄漏还是容量不足？

**答**：Full GC 后看 Old Gen 是否下降。下降但很快又满 → 容量不足（加内存或优化对象创建）。不降或降很少 → 泄漏（查代码）。做两次 jmap -histo 对比，如果某类对象数量只增不减 → 泄漏。

### Q24: 什么是 CMS 的 Concurrent Mode Failure？

**答**：CMS 并发回收期间老年代被填满 → 无法继续并发回收 → 退化为 Serial Old 单线程 Full GC（长 STW）。原因：触发阈值太高、浮动垃圾太多、分配速率过高。解决：降低 CMSInitiatingOccupancyFraction、增大老年代、改用 G1。

### Q25: 怎么排查死锁？

**答**：`jstack -l <pid>` 末尾会自动检测死锁并打印。或 Arthas `thread --deadlock`。或 `jcmd <pid> Thread.print` 也会检测。看 "Found X deadlock" 和引用链。

### Q26: -XX:+DisableExplicitGC 有什么副作用？

**答**：禁用 System.gc()。好处是防止代码/框架调用 System.gc() 导致 Full GC。副作用：DirectByteBuffer 的释放依赖 System.gc() 触发 Cleaner → 禁用后直接内存可能延迟释放 → 建议同时设置 -XX:MaxDirectMemorySize 限制上限，或手动释放。

### Q27: 火焰图怎么读？

**答**：横轴是方法在调用栈中的位置（不是时间线），纵轴是调用深度（底层在下），宽度是 CPU 采样占比。最宽的"平顶"就是热点——优化它。如果 GC 相关栈帧占比大 → GC 是瓶颈。如果某个业务方法很宽 → 该方法是热点。

### Q28: ZGC 为什么能做到 < 10ms 停顿？

**答**：ZGC 使用染色指针 + 读屏障实现并发转移（对象移动时不 STW）。标记、转移、重定位都是并发的。STW 只在初始标记和初始转移阶段，且都很短。代价是吞吐量略低（读屏障开销）。

### Q29: JVM 调优的一般原则是什么？

**答**：① 先正确后优化——确保功能正确再调优。② 先监控后调优——有监控数据再动手。③ 一次只改一个参数——否则无法判断效果。④ 压测验证——调优前后做对比。⑤ 不过度调优——大部分应用默认参数就够了。

### Q30: 说说你实际排查过的一个 JVM 问题？

**答**：自由发挥。讲清楚：现象 → 排查过程 → 根因 → 修复 → 预防。重点体现排查方法论和工具使用。

---

# 附录 A：JVM 参数速查表

## A.1 堆参数

| 参数 | 含义 | 默认值 | 建议值 |
|------|------|--------|--------|
| `-Xms` | 初始堆 | 物理内存 1/64 | = -Xmx |
| `-Xmx` | 最大堆 | 物理内存 1/4 | 物理内存 60~70% |
| `-Xmn` | 新生代 | -Xmx 的 1/3 | NewRatio=2~3 |
| `-XX:NewRatio=` | 新生代:老年代 | 2 (Parallel) | 2~3 |
| `-XX:SurvivorRatio=` | Eden:Survivor | 8 | 6~8 |
| `-XX:MaxTenuringThreshold=` | 晋升年龄 | 15 | 15 |
| `-XX:PretenureSizeThreshold=` | 大对象阈值 | 1MB | 按业务调整 |

## A.2 非堆参数

| 参数 | 含义 | 默认值 | 建议值 |
|------|------|--------|--------|
| `-XX:MetaspaceSize=` | Metaspace 初始阈值 | 20MB | 256MB |
| `-XX:MaxMetaspaceSize=` | Metaspace 上限 | 无限制 | 512MB |
| `-Xss` | 线程栈大小 | 1MB | 512KB |
| `-XX:MaxDirectMemorySize=` | 直接内存上限 | = -Xmx | 512MB~2G |
| `-XX:ReservedCodeCacheSize=` | Code Cache | 240MB | 256MB |

## A.3 GC 收集器参数

| 参数 | 含义 |
|------|------|
| `-XX:+UseSerialGC` | Serial + Serial Old |
| `-XX:+UseParallelGC` | Parallel Scavenge + Parallel Old (JDK 8 默认) |
| `-XX:+UseConcMarkSweepGC` | ParNew + CMS + Serial Old(fallback) |
| `-XX:+UseG1GC` | G1 (JDK 9+ 默认) |
| `-XX:+UseZGC` | ZGC (JDK 15+) |
| `-XX:MaxGCPauseMillis=` | 目标停顿时间 |
| `-XX:ParallelGCThreads=` | GC 线程数 |
| `-XX:ConcGCThreads=` | 并发 GC 线程数 |
| `-XX:GCTimeRatio=` | GC 时间占比目标 |
| `-XX:+DisableExplicitGC` | 禁用 System.gc() |
| `-XX:+AlwaysPreTouch` | 启动时预分配内存 |

## A.4 CMS 专用参数

| 参数 | 含义 | 建议值 |
|------|------|--------|
| `-XX:CMSInitiatingOccupancyFraction=` | 触发阈值 | 70~80 |
| `-XX:+UseCMSInitiatingOccupancyOnly` | 固定阈值 | 开启 |
| `-XX:+CMSScavengeBeforeRemark` | 重标前 Minor GC | 开启 |
| `-XX:+CMSClassUnloadingEnabled` | CMS 卸载类 | 开启 |
| `-XX:CMSFullGCsBeforeCompaction=` | N 次后整理 | 5 |
| `-XX:+UseCMSCompactAtFullCollection` | Full GC 整理 | 开启 |

## A.5 G1 专用参数

| 参数 | 含义 | 默认 | 建议值 |
|------|------|------|--------|
| `-XX:G1HeapRegionSize=` | Region 大小 | 自动 | 8~32MB |
| `-XX:InitiatingHeapOccupancyPercent=` | IHOP | 45 | 35~50 |
| `-XX:G1NewSizePercent=` | 新生代最小 | 5 | 20 |
| `-XX:G1MaxNewSizePercent=` | 新生代最大 | 60 | 60 |
| `-XX:G1MixedGCCountTarget=` | Mixed GC 次数 | 8 | 8~16 |
| `-XX:G1MixedGCLiveThresholdPercent=` | 存活率阈值 | 85 | 85~90 |
| `-XX:G1RSetUpdatingPauseTimePercent=` | RSet 更新占比 | 10 | 5~10 |

## A.6 诊断参数

| 参数 | 含义 |
|------|------|
| `-XX:+HeapDumpOnOutOfMemoryError` | OOM 自动 dump |
| `-XX:HeapDumpPath=` | dump 文件路径 |
| `-XX:NativeMemoryTracking=` | NMT 开启 |
| `-XX:+PrintGCDetails` | GC 详情 (JDK 8) |
| `-Xlog:gc*` | GC 日志 (JDK 9+) |
| `-XX:+TraceClassLoading` | 打印类加载 |
| `-XX:+TraceClassUnloading` | 打印类卸载 |

---

# 附录 B：工具命令速查表

## B.1 jstat

```bash
jstat -gcutil <pid> 1000 10        # GC 使用率趋势
jstat -gc <pid>                     # 详细内存信息
jstat -gccause <pid>                # GC 原因
jstat -class <pid>                  # 类加载统计
jstat -compiler <pid>               # JIT 编译统计
```

## B.2 jmap

```bash
jmap -histo <pid> | head -30       # 对象直方图
jmap -histo:live <pid>             # 存活对象（触发 GC）
jmap -dump:format=b,file=heap.hprof <pid>  # 堆 dump
jmap -finalizerinfo <pid>           # F-Queue 对象
jmap -clstats <pid>                 # 类加载器统计
```

## B.3 jstack

```bash
jstack <pid>                        # 线程栈
jstack -l <pid>                     # 包含锁信息
jstack -F <pid>                     # 强制（进程无响应时）
jstack <pid> | grep "BLOCKED" -A 20 # 查看 BLOCKED 线程
jstack <pid> | grep "State:" | sort | uniq -c  # 线程状态统计
```

## B.4 jcmd

```bash
jcmd -l                              # 列出进程
jcmd <pid> help                      # 查看支持命令
jcmd <pid> VM.flags                  # JVM 参数
jcmd <pid> Thread.print              # 线程栈
jcmd <pid> GC.heap_info              # 堆信息
jcmd <pid> GC.class_histogram        # 对象直方图
jcmd <pid> GC.heap_dump /tmp/heap.hprof  # 堆 dump
jcmd <pid> VM.native_memory          # NMT
jcmd <pid> JFR.start duration=60s filename=/tmp/flight.jfr  # JFR
```

## B.5 Arthas

```bash
dashboard                            # 仪表盘
thread -n 3                          # CPU 最高的 3 个线程
thread -b                            # BLOCKED 线程
thread --deadlock                    # 死锁检测
jad com.example.Service              # 反编译
watch com.example.Service method "{params, returnObj}" -x 2  # 观察方法
trace com.example.Service method     # 调用链耗时
monitor com.example.Service method -c 10  # 执行统计
profiler start / profiler stop       # 火焰图
heapdump /tmp/heap.hprof             # 堆 dump
```

## B.6 一键诊断命令

```bash
# 快速查看 GC
jstat -gcutil <pid> 1000 10

# 快速查看线程
jstack <pid> | grep "State:" | sort | uniq -c | sort -rn

# 快速查看对象
jmap -histo <pid> | head -20

# 快速查看 CPU
top -Hbn 1 -p <pid> | head -20

# 快速查看堆信息
jcmd <pid> GC.heap_info

# 快速查看 JVM 参数
jcmd <pid> VM.flags
```

---

# 附录 C：内存泄漏代码模式速查

| 模式 | 泄漏代码 | 修复方案 |
|------|----------|----------|
| 静态集合 | `static Map cache = new HashMap()` 只 put | Caffeine + 过期淘汰 |
| ThreadLocal | `threadLocal.set(obj)` 不 remove | try-finally remove |
| 未关闭资源 | `new FileInputStream()` 异常不 close | try-with-resources |
| 监听器 | `addListener()` 不 remove | @PreDestroy 注销 |
| 内部类 | 非静态内部类持有外部类 | 改为 static class |
| 缓存无淘汰 | `ConcurrentHashMap` 无上限 | Caffeine maximumSize |
| 连接泄漏 | `getConnection()` 不 close | try-with-resources |
| 定时任务 | `scheduleAtFixedRate` 不 cancel | ScheduledFuture.cancel |
| String.intern | 大量 intern 到 String Pool | Caffeine 替代 |
| ClassLoader | 动态加载不卸载 | 缓存 ClassLoader |
| ByteBuf | Netty `buf` 不 release | SimpleChannelInboundHandler |
| finalize | finalize 执行慢 | Cleaner/PhantomReference |

---

> **文档总结**：本文是《JVM_GC底层原理深度解析》的实战姊妹篇。GC 原理文档讲"为什么"（分代假说、三色标记、CMS/G1 回收流程），本文讲"怎么做"（参数怎么配、工具怎么用、泄漏怎么查）。
>
> 建议两份文档配合阅读——先读 GC 原理理解机制，再读本文掌握实战排查方法论。面试时遇到 JVM 调优和内存泄漏问题，按"四步法"（发现→定位→修复→验证）组织回答，配合具体案例，基本能应对。
