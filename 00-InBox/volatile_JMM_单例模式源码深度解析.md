# volatile · JMM · 单例模式 — 源码深度解析

> 基于 JDK 8+ 源码，从 JVM 规范到硬件层面，系统拆解 Java 内存模型与可见性保证机制，以及单例模式的线程安全实现。

---

## 目录

**Part 1 — JMM（Java 内存模型）**
1. [为什么需要 JMM](#1-为什么需要-jmm)
2. [主内存与工作内存](#2-主内存与工作内存)
3. [happens-before 规则](#3-happens-before-规则)
4. [内存屏障（Memory Barrier）](#4-内存屏障memory-barrier)
5. [as-if-serial 与顺序一致性](#5-as-if-serial-与顺序一致性)

**Part 2 — volatile**
6. [volatile 的两大语义](#6-volatile-的两大语义)
7. [volatile 可见性：从 JVM 到 CPU 缓存](#7-volatile-可见性从-jvm-到-cpu-缓存)
8. [volatile 禁止重排序：内存屏障插入规则](#8-volatile-禁止重排序内存屏障插入规则)
9. [volatile 不保证原子性：经典反例 i++](#9-volatile-不保证原子性经典反例-i)
10. [volatile 在 JDK 中的应用](#10-volatile-在-jdk-中的应用)
11. [LongAdder vs volatile long：分散计数的设计](#11-longadder-vs-volatile-long分散计数的设计)

**Part 3 — 单例模式**
12. [饿汉式](#12-饿汉式)
13. [懒汉式（线程不安全 / 同步方法 / DCL）](#13-懒汉式线程不安全--同步方法--dcl)
14. [DCL 单例：为什么需要 volatile](#14-dcl-单例为什么需要-volatile)
15. [静态内部类_holder](#15-静态内部类holder)
16. [枚举单例](#16-枚举单例)
17. [CAS 单例（枚举替代方案）](#17-cas-单例枚举替代方案)
18. [单例的反射与序列化破坏及防御](#18-单例的反射与序列化破坏及防御)

**Part 4 — 综合**
19. [volatile vs synchronized vs Lock 对比](#19-volatile-vs-synchronized-vs-lock-对比)
20. [常见面试题](#20-常见面试题)

---

# Part 1 — JMM（Java 内存模型）

---

## 1. 为什么需要 JMM

### 问题背景

现代 CPU 和编译器会对程序做两类优化，导致多线程下的行为不可预期：

```
① 编译器 / 处理器重排序（Instruction Reordering）
   源码顺序 ≠ 字节码顺序 ≠ 执行顺序 ≠ 内存可见顺序

② CPU 缓存层次（Store Buffer / L1 / L2 / L3）
   线程 A 写入的值可能还在 Store Buffer 中，线程 B 读不到
```

### JMM 的目标

```
JMM 定义了一套规则，在"尽可能优化性能"与"提供可预测的线程间行为"之间取平衡：
  - 对程序员：提供 happens-before 语义，只要满足规则，就能得到正确的可见性保证
  - 对编译器/CPU：在不违反 happens-before 的前提下，可以自由重排
```

### JMM 的三层抽象

```
┌─────────────────────────────────────────┐
│        程序员视角：happens-before 规则     │  ← 写程序的契约
├─────────────────────────────────────────┤
│        JMM 规范：内存屏障插入规则          │  ← 编译器的约束
├─────────────────────────────────────────┤
│        硬件层：CPU 缓存协议 + 屏障指令      │  ← 物理实现
└─────────────────────────────────────────┘
```

---

## 2. 主内存与工作内存

### JMM 的抽象模型

```
                    ┌─────────────┐
                    │   主内存      │
                    │  (Main Memory)│
                    │              │
                    │  共享变量 v    │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │ save/load  │ save/load  │ save/load
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ 工作内存  │ │ 工作内存  │ │ 工作内存  │
        │ Thread-A │ │ Thread-B │ │ Thread-C │
        │  v 的副本 │ │  v 的副本 │ │  v 的副本 │
        └──────────┘ └──────────┘ └──────────┘
```

### 8 种原子操作

JMM 定义了 8 种操作来完成主内存与工作内存之间的交互：

| 操作 | 作用于 | 说明 |
|------|--------|------|
| **lock** | 主内存 | 把变量标识为线程独占状态 |
| **unlock** | 主内存 | 解除独占，其他线程可 lock |
| **read** | 主内存 → 工作内存 | 把变量值从主内存传输到工作内存 |
| **load** | 工作内存 | 把 read 读到的值放入工作内存的变量副本 |
| **use** | 工作内存 | 把变量值传给执行引擎（虚拟机栈） |
| **assign** | 工作内存 | 把执行引擎收到的值赋给变量副本 |
| **store** | 工作内存 → 主内存 | 把变量值从工作内存传输到主内存 |
| **write** | 主内存 | 把 store 传来的值写入主内存变量 |

> **read-load**、**store-write** 必须成对出现，顺序执行，不允许单独出现。

### volatile 的特殊规则

对 volatile 变量的 read/load/use 和 assign/store/write 必须连续出现：

```
普通变量：  read → load ... （中间可以穿插其他操作）... use
volatile：  read → load → use  必须连续
           assign → store → write  必须连续
```

这意味着 volatile 变量每次 use 前都必须从主内存刷新，每次 assign 后都必须立即同步回主内存。

---

## 3. happens-before 规则

happens-before 是 JMM 向程序员提供的**可见性保证**：如果 A happens-before B，则 A 的操作结果对 B 可见。

### 八大规则

```
┌──────────────────────────────────────────────────────────────┐
│  ① 程序顺序规则：同一线程中，前面的操作 hb 后面的操作            │
│  ② volatile 规则：volatile 写 hb 后续对该变量的读               │
│  ③ 锁规则：unlock 操作 hb 后续对同一把锁的 lock                 │
│  ④ 线程启动规则：Thread.start() hb 该线程的所有操作             │
│  ⑤ 线程终止规则：线程的所有操作 hb Thread.join() 的返回          │
│  ⑥ 线程中断规则：interrupt() hb 被中断线程检测到中断             │
│  ⑦ 对象终结规则：构造函数执行完毕 hb finalize()                  │
│  ⑧ 传递性：A hb B 且 B hb C ⇒ A hb C                         │
└──────────────────────────────────────────────────────────────┘
```

### 传递性示例

```java
// 线程 A
data = 1;                // A1
ready = true;            // A2 (volatile 写)

// 线程 B
if (ready) {             // B1 (volatile 读)
    int x = data;        // B2 → x == 1 ✓
}

// 推导过程：
// A1 hb A2    （程序顺序规则）
// A2 hb B1    （volatile 规则：volatile 写 hb volatile 读）
// B1 hb B2    （程序顺序规则）
// A1 hb B2    （传递性）→ data == 1 对 B2 可见
```

> **关键洞察**：volatile 变量本身只保证自身的可见性，但通过 happens-before 传递性，可以把 volatile 写之前的所有操作"顺便"带给读线程。这就是 DCL 单例中 volatile 的核心作用。

---

## 4. 内存屏障（Memory Barrier）

### 四种屏障类型

JMM 定义了四种内存屏障，它们是编译器和处理器必须遵守的约束：

| 屏障类型 | 指令示意 | 作用 |
|----------|---------|------|
| **LoadLoad** | Load1; **LoadLoad**; Load2 | Load1 必须在 Load2 之前完成读 |
| **StoreStore** | Store1; **StoreStore**; Store2 | Store1 必须在 Store2 之前对其他处理器可见 |
| **LoadStore** | Load1; **LoadStore**; Store2 | Load1 必须在 Store2 之前完成读 |
| **StoreLoad** | Store1; **StoreLoad**; Load2 | Store1 必须对其他处理器可见后，才能执行 Load2 |

> **StoreLoad 是开销最大的屏障**，因为它要等待 Store Buffer 刷新到缓存，同时使其他处理器缓存行失效。它同时也是唯一能防止"Store 被 Load 跳过"的屏障。

### 各处理器的屏障支持

```
处理器       所需屏障
──────────────────────────
x86 (Intel)  只需 StoreLoad（其他三种由硬件保证了）
ARM          需要全部四种
PowerPC      需要全部四种
SPARC        只需 StoreLoad
```

> 这就是为什么同样的 Java 代码在 x86 上可能不会出问题（硬件较强），但在 ARM 上会暴露并发 bug。

### x86 的实际屏障指令

```c
// x86 平台上 JMM 屏障对应的实际指令
StoreStore → 空操作（x86 不允许 Store-Store 重排）
LoadLoad  → 空操作（x86 不允许 Load-Load 重排）
LoadStore → 空操作（x86 不允许 Load-Store 重排）
StoreLoad → mfence / lock addl $0x0, (%rsp)  ← 唯一真正需要的屏障
```

---

## 5. as-if-serial 与顺序一致性

### as-if-serial 语义

> 不管怎么重排序，**单线程**的执行结果不能被改变。编译器和处理器必须遵守此规则。

```java
// 以下重排不影响单线程结果，是合法的：
int a = 1;    // A
int b = 2;    // B    → A 和 B 可以互换顺序
int c = a + b;// C    → C 必须在 A、B 之后（数据依赖）

// 以下重排影响多线程结果，但在单线程下合法：
boolean ready = false;

// 线程 1
a = 1;          // A
ready = true;   // B    → A 和 B 没有数据依赖，可以重排！

// 线程 2
if (ready) {    // C
    int i = a;  // D    → 如果 B 被提前，D 可能读到 0
}
```

### 顺序一致性内存模型（理论参考）

JMM 不保证顺序一致性，但提供了"顺序一致性参考模型"：

```
顺序一致性模型：
  - 所有操作完全按程序顺序执行
  - 每个操作立即对所有线程可见
  - 不存在重排序，不存在缓存延迟

JMM 实际行为：
  - 未同步的程序：可能重排，可能不可见
  - 正确同步的程序：效果等价于顺序一致性模型
```

---

# Part 2 — volatile

---

## 6. volatile 的两大语义

```
┌────────────────────────────────────────────┐
│           volatile 的两大保证              │
│                                            │
│  ① 可见性：写入立即刷新到主内存，           │
│            读取立即从主内存加载              │
│                                            │
│  ② 有序性：禁止编译器和处理器对             │
│            volatile 变量的重排序             │
│                                            │
│  ✗ 不保证原子性：volatile int i; i++ 仍不安全 │
└────────────────────────────────────────────┘
```

### 字节码层面

```java
// Java 代码
volatile boolean ready = false;

// 字节码
 0: iconst_0
 1: putstatic     #2  // Field ready:Z   ← 写 volatile
 ...
 5: getstatic     #2  // Field ready:Z   ← 读 volatile

// javap -verbose 输出中，volatile 变量带有 ACC_VOLATILE 标志
// flag: ACC_VOLATILE (0x0040)
```

JIT 编译器看到 `ACC_VOLATILE` 标志后，会在生成的机器码中插入内存屏障。

---

## 7. volatile 可见性：从 JVM 到 CPU 缓存

### 完整的可见性保证链路

```
线程 A 执行 volatile 写
    │
    ▼
JIT 插入 StoreStore + StoreLoad 屏障
    │
    ▼
CPU 执行：
  ① 将 Store Buffer 中的脏数据刷入 L1 Cache
  ② 通过 MESI 协议发送 Invalidate 消息给其他 CPU
  ③ 等待其他 CPU 的 Invalidate Acknowledge
  ④ 执行 mfence / lock 指令确保全局可见
    │
    ▼
其他 CPU 的缓存行被标记为 Invalid
    │
    ▼
线程 B 执行 volatile 读时，缓存未命中，从主内存（或通过
缓存一致性协议从其他 CPU 的 Cache）重新加载最新值
```

### MESI 缓存一致性协议

```
缓存行状态（Cache Line 4 种状态）：

M (Modified)  — 数据已修改，与主内存不一致，只在本 Cache 中
E (Exclusive) — 数据与主内存一致，只在本 Cache 中
S (Shared)    — 数据与主内存一致，多个 Cache 中都有
I (Invalid)   — 缓存行无效，读操作必须从主内存重新加载

状态转换关键场景：
  CPU-A 写入 volatile 变量：
    S → M  （向其他 CPU 发 Invalidate，等 ACK）
    
  CPU-B 读取 volatile 变量：
    I → S  （缓存未命中，从主内存或其他 Cache 获取最新值）
```

### Store Buffer 与 Invalidate Queue

```
现实问题：CPU-A 写入后等所有 CPU 返回 ACK 太慢

解决方案：
  ┌──────────┐     Invalidate      ┌──────────────┐
  │  CPU-A   │ ──────────────────→  │   CPU-B      │
  │          │                      │              │
  │ 写入Store│     Invalidate ACK   │ 写入Invalidate│
  │ Buffer   │ ←──────────────────  │ Queue        │
  └──────────┘                      └──────────────┘

CPU-A：写入 Store Buffer 后继续执行（不阻塞等待 ACK）
CPU-B：收到 Invalidate 消息后放入 Invalidate Queue，立即返回 ACK

代价：
  - CPU-A 的写入可能暂时只有自己可见（Store Buffer）
  - CPU-B 可能短暂读到旧值（Invalidate Queue 还没处理）

内存屏障的作用：
  - StoreLoad 屏障 → 刷 Store Buffer
  - LoadLoad 屏障 → 刷 Invalidate Queue
```

### 代码验证：可见性问题

```java
public class VisibilityDemo {
    // 不加 volatile，子线程可能永远读不到 flag 的变化
    // 加上 volatile，子线程能立即感知 flag 变为 true
    private static volatile boolean flag = false;

    public static void main(String[] args) throws Exception {
        new Thread(() -> {
            while (!flag) {
                // 空转等待
                // 不加 volatile 时，JIT 可能优化为：
                // if (!flag) while (true) {}  ← 不会再去读 flag
            }
            System.out.println("子线程: 检测到 flag = true");
        }).start();

        Thread.sleep(1000);
        flag = true;
        System.out.println("主线程: 设置 flag = true");
    }
}
```

---

## 8. volatile 禁止重排序：内存屏障插入规则

### JMM 的 volatile 屏障插入策略

```
每个 volatile 写操作前面插入一个 StoreStore 屏障：
  ┌──────────────┐
  │ 普通写        │
  │ StoreStore    │ ← 确保前面的普通写对其他处理器可见后，才做 volatile 写
  │ volatile 写   │
  └──────────────┘

每个 volatile 写操作后面插入一个 StoreLoad 屏障：
  ┌──────────────┐
  │ volatile 写   │
  │ StoreLoad     │ ← 确保 volatile 写对其他处理器可见后，才做后续的读
  │ 后续读        │
  └──────────────┘

每个 volatile 读操作后面插入一个 LoadLoad + LoadStore 屏障：
  ┌──────────────┐
  │ volatile 读   │
  │ LoadLoad      │ ← 确保 volatile 读先于后续的读
  │ LoadStore     │ ← 确保 volatile 读先于后续的写
  │ 后续读/写     │
  └──────────────┘
```

### 示例：DCL 单例的屏障插入

```java
// DCL 单例中的 volatile 写
instance = new Singleton();  // instance 是 volatile

// JMM 插入屏障后的效果：
//   1. 分配内存空间
//   2. 初始化对象（调用构造方法）     ← 普通写
//   【StoreStore 屏障】               ← 保证 2 在 3 之前完成
//   3. 将引用指向分配好的内存地址     ← volatile 写
//   【StoreLoad 屏障】               ← 保证 3 对后续读可见
```

### OpenJDK 源码层面（C2 编译器）

```cpp
// hotspot/share/opto/bytecodeInfo.cpp 简化逻辑
// 当 C2 编译器遇到 volatile 字段的 putstatic/putfield 时：

void GraphKit::volatile_store(...) {
    // 在 volatile 写之前插入 MemBarReleaseNode（等价于 StoreStore）
    insert_mem_bar(Op_MemBarRelease);

    // 执行实际的 store 操作
    store_to_memory(ctrl, adr, val, type, ...);

    // 在 volatile 写之后插入 MemBarVolatileNode（等价于 StoreLoad）
    insert_mem_bar(Op_MemBarVolatile);
}

void GraphKit::volatile_load(...) {
    // 执行实际的 load 操作
    load_from_memory(ctrl, adr, val, type, ...);

    // 在 volatile 读之后插入 MemBarAcquireNode（等价于 LoadLoad + LoadStore）
    insert_mem_bar(Op_MemBarAcquire);
}
```

### 汇编层面验证

```java
// 测试代码
private static volatile int vol = 0;
public static void write() { vol = 1; }
public static int read()   { return vol; }

// x86 上 JIT 编译后的汇编（-XX:+PrintAssembly -XX:+UnlockDiagnosticVMOptions）
// volatile 写：
mov    dword ptr [rsp+0x10], 0x1     // 将 1 写入 vol
lock addl dword ptr [rsp], 0x0       // ← StoreLoad 屏障！lock 前缀指令
                                       // 等价于 mfence，刷 Store Buffer

// volatile 读：
mov    eax, dword ptr [rsp+0x10]     // 直接读（x86 硬件保证了 LoadLoad/LoadStore）
                                       // 不需要额外屏障指令
```

> **x86 特殊性**：由于 x86 是强内存模型（TSO），只允许 Store-Load 重排，所以 volatile 写只需要加 `lock addl`（等价 StoreLoad），volatile 读不需要任何屏障指令。但在 ARM 等弱内存模型上，读写两侧都需要屏障。

---

## 9. volatile 不保证原子性：经典反例 i++

### 问题演示

```java
public class VolatileAtomicDemo {
    private static volatile int count = 0;

    public static void main(String[] args) throws Exception {
        Runnable task = () -> {
            for (int i = 0; i < 10000; i++) {
                count++;    // ← 不是原子操作！
            }
        };

        Thread t1 = new Thread(task);
        Thread t2 = new Thread(task);
        t1.start(); t2.start();
        t1.join();  t2.join();

        System.out.println(count);  // 结果 < 20000，每次不同
    }
}
```

### 为什么 volatile 不能保证 i++ 的原子性

```
count++ 实际上是 3 步操作：
  ① 读：读取 count 的当前值     (getstatic)
  ② 改：count + 1               (iadd)
  ③ 写：写回 count              (putstatic)

volatile 只保证 ① 读到最新值、③ 写立即可见，
但 ①→②→③ 之间可以被打断：

时间线：
  Thread-A                    Thread-B
  ① 读 count = 0
                              ① 读 count = 0   ← 也读到了 0
                              ② 0 + 1 = 1
                              ③ 写 count = 1
  ② 0 + 1 = 1                ← 用的是旧值 0
  ③ 写 count = 1              ← 覆盖了 B 的写入！

结果：两次 ++，但 count 只增加了 1
```

### 解决方案

```java
// 方案 1：synchronized
synchronized (lock) { count++; }

// 方案 2：AtomicInteger（CAS）
private static AtomicInteger count = new AtomicInteger(0);
count.incrementAndGet();   // CAS + 自旋，无锁

// 方案 3：LongAdder（分散计数，高并发最优）
private static LongAdder count = new LongAdder();
count.increment();
```

---

## 10. volatile 在 JDK 中的应用

### 1）状态标志位

```java
// JDK 源码：java.util.concurrent.ThreadPoolExecutor
// 线程池的运行状态用 ctl 表示，ctl 本身是 AtomicInteger
// 但在很多场景中，简单的 volatile boolean 就够了

// 经典模式：用 volatile 做停止标志
private volatile boolean running = true;

public void run() {
    while (running) {    // 其他线程设置 running = false 后能立即感知
        doWork();
    }
}

public void shutdown() {
    running = false;
}
```

### 2）DCL 单例（详见 Part 3）

```java
private volatile static Singleton instance;
```

### 3）ConcurrentHashMap 的 sizeCtl

```java
// java.util.concurrent.ConcurrentHashMap
// sizeCtl 用 volatile 修饰，多个线程通过 CAS 竞争修改它
private transient volatile int sizeCtl;

// sizeCtl 的不同值代表不同状态：
// -1    : 正在初始化
// -(1+n): 有 n 个线程正在扩容
// 0     : 未初始化，使用默认容量
// >0    : 下一次扩容的阈值（或初始化容量）
```

### 4）AQS 的 state

```java
// java.util.concurrent.locks.AbstractQueuedSynchronizer
// state 是 volatile 的，ReentrantLock/Semaphore/CountDownLatch 都依赖它
private volatile int state;
```

### 5）Reference 的 pending 链表

```java
// java.lang.ref.Reference
// GC 将要回收的引用对象挂到 pending 链表上
// ReferenceHandler 线程从 pending 取出放入 ReferenceQueue
volatile Reference<?> pending;
```

### 6）StampedLock 的乐观读

```java
// java.util.concurrent.locks.StampedLock
// validate 时只读 state（volatile），不需要 CAS
long stamp = lock.tryOptimisticRead();
// ... 执行读操作 ...
if (!lock.validate(stamp)) {
    // 乐观读失败，升级为悲观读锁
}
```

---

## 11. LongAdder vs volatile long：分散计数的设计

### 问题：高并发下 AtomicInteger 的瓶颈

```
AtomicInteger.incrementAndGet() 使用 CAS：
  while (!CAS(value, old, old+1)) { old = value; }

当 N 个线程同时 CAS 同一个变量时：
  - 只有 1 个成功，其余 N-1 个自旋重试
  - 缓存行频繁失效（乒乓效应）
  - 线程越多，吞吐量越低
```

### LongAdder 的解决思路

```
                    ┌──────────────┐
                    │  baseCount   │  ← 无竞争时直接 CAS
                    └──────┬───────┘
                           │ 竞争时
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │Cell[0]   │ │Cell[1]   │ │Cell[2]   │
        │ thread-A │ │ thread-B │ │ thread-C │
        │  value   │ │  value   │ │  value   │
        └──────────┘ └──────────┘ └──────────┘

sum() = baseCount + Cell[0] + Cell[1] + Cell[2] + ...
         ↑ 注意：sum 不是强一致的（遍历过程中可能有增量）
```

### LongAdder 核心源码

```java
// java.util.concurrent.atomic.Striped64（LongAdder 的父类）

// 每个 Cell 用 @Contended 避免 false sharing
@sun.misc.Contended
static final class Cell {
    volatile long value;
    Cell(long x) { value = x; }

    final boolean cas(long cmp, long val) {
        return UNSAFE.compareAndSwapLong(this, valueOffset, cmp, val);
    }
}

// 核心累加方法
public void increment() {
    Cell[] as; long b, v; int m; Cell a;
    // ① 先尝试对 base 做 CAS
    if ((as = cells) != null || !casBase(b = base, b + 1L)) {
        // ② CAS 失败 → 有竞争 → 尝试对当前线程对应的 Cell 做 CAS
        boolean uncontended = true;
        if (as == null || (m = as.length - 1) < 0 ||
            (a = as[getProbe() & m]) == null ||     // 定位 Cell
            !(uncontended = a.cas(v = a.value, v + 1L))) {
            // ③ Cell CAS 也失败 → 扩容或重试
            longAccumulate(1L, null, uncontended);
        }
    }
}
```

### Cell 的 @Contended 注解与 False Sharing

```
False Sharing 问题：
  CPU 缓存行通常 64 字节，一个 long 占 8 字节
  如果 Cell[0] 和 Cell[1] 在同一个缓存行：
  
  ┌──────────────── 64 字节缓存行 ────────────────┐
  │ Cell[0].value(8B) │ Cell[1].value(8B) │ ...   │
  └───────────────────────────────────────────────┘
  
  Thread-A 修改 Cell[0] → 整个缓存行失效 → Thread-B 的 Cell[1] 也要重新加载
  两个互不相关的变量互相拖慢！

@Contended 的解决：
  在变量前后各填充 128 字节（@Contended 默认），
  确保 Cell[0] 和 Cell[1] 不在同一个缓存行：

  ┌─── 128B padding ───┐┌─ Cell[0] 8B ─┐┌─── 128B padding ───┐
  │  unused...         ││  value       ││  unused...         │
  └────────────────────┘└──────────────┘└────────────────────┘
```

### 性能对比

```
线程数    synchronized    AtomicInteger    LongAdder
  1          35M ops/s       80M ops/s      85M ops/s
  4           8M ops/s       25M ops/s      70M ops/s
  16          2M ops/s        6M ops/s      60M ops/s
  32          1M ops/s        3M ops/s      55M ops/s

LongAdder 在高并发下吞吐量远超 AtomicInteger，
代价是 sum() 不保证强一致性，且内存占用更大。
```

---

# Part 3 — 单例模式

---

## 12. 饿汉式

### 实现

```java
public class EagerSingleton {

    // 类加载时就创建实例（JVM 保证类加载的线程安全）
    private static final EagerSingleton INSTANCE = new EagerSingleton();

    private EagerSingleton() {}

    public static EagerSingleton getInstance() {
        return INSTANCE;
    }
}
```

### 线程安全分析

```
线程安全保证来自 JVM 的类初始化机制（<clinit>）：
  ① JVM 在类初始化阶段会获取初始化锁
  ② 同一时刻只有一个线程能执行 <clinit>
  ③ 其他线程会阻塞等待初始化完成

因此 INSTANCE 的创建是在类加载时由 JVM 保证线程安全的，
不需要 volatile，不需要 synchronized。
```

### 静态代码块变体

```java
public class EagerSingleton2 {

    private static final EagerSingleton2 INSTANCE;

    static {
        INSTANCE = new EagerSingleton2();
        // 可以在静态代码块中做更复杂的初始化逻辑
    }

    private EagerSingleton2() {}
    public static EagerSingleton2 getInstance() { return INSTANCE; }
}
```

### 缺点

```
① 不管用不用，类加载时就创建实例 → 可能浪费内存
② 如果构造方法依赖运行时参数，无法延迟初始化
③ 如果初始化很耗时，会导致类加载变慢
```

---

## 13. 懒汉式（线程不安全 / 同步方法 / DCL）

### 13.1 线程不安全的懒汉式

```java
public class LazySingletonUnsafe {

    private static LazySingletonUnsafe instance;

    private LazySingletonUnsafe() {}

    public static LazySingletonUnsafe getInstance() {
        if (instance == null) {                     // ① 检查
            instance = new LazySingletonUnsafe();   // ② 创建
        }
        return instance;
    }
}
```

```
竞态条件：
  Thread-A                     Thread-B
  ① instance == null ✓
                               ① instance == null ✓  ← 还没被赋值
  ② new LazySingletonUnsafe()
                               ② new LazySingletonUnsafe()  ← 创建了两个实例！
```

### 13.2 同步方法懒汉式（synchronized 整个方法）

```java
public class LazySingletonSync {

    private static LazySingletonSync instance;

    private LazySingletonSync() {}

    // 每次 getInstance 都要获取锁，性能差
    public synchronized static LazySingletonSync getInstance() {
        if (instance == null) {
            instance = new LazySingletonSync();
        }
        return instance;
    }
}
```

```
问题：
  实例创建后，后续所有调用都不需要同步了，
  但 synchronized 方法每次都要获取类锁 → 不必要的性能开销
```

### 13.3 同步代码块懒汉式（错误！）

```java
// 错误示范！仍然不安全！
public static LazySingletonSync getInstance() {
    if (instance == null) {
        synchronized (LazySingletonSync.class) {
            instance = new LazySingletonSync();  // ← 没有二次检查
        }
    }
    return instance;
}

// 竞态条件：
//   Thread-A 通过 null 检查，进入 synchronized
//   Thread-B 也通过 null 检查（在 A 拿锁之前），等待锁
//   A 创建实例释放锁
//   B 拿到锁，又创建一个实例！
```

---

## 14. DCL 单例：为什么需要 volatile

### DCL 完整实现

```java
public class DCLSingleton {

    // ★★★ volatile 是关键 ★★★
    private static volatile DCLSingleton instance;

    private DCLSingleton() {}

    public static DCLSingleton getInstance() {
        if (instance == null) {                          // ① 第一次检查（无锁）
            synchronized (DCLSingleton.class) {          // ② 加锁
                if (instance == null) {                  // ③ 第二次检查（锁内）
                    instance = new DCLSingleton();       // ④ 创建实例
                }
            }
        }
        return instance;
    }
}
```

### 如果不加 volatile 会怎样？

**核心问题：`new DCLSingleton()` 不是原子操作，可能发生指令重排序。**

```
new DCLSingleton() 在 JVM 中实际分 3 步：

  A. 分配内存空间                         (new)
  B. 调用构造方法初始化成员变量              (invokespecial)
  C. 将 instance 引用指向分配的内存地址      (putstatic)

正常顺序：A → B → C
重排顺序：A → C → B  ← 编译器/CPU 可能这样优化！
```

### 重排序导致的半初始化问题

```
假设 instance 没有 volatile，发生了 A → C → B 重排：

Thread-A                         Thread-B
  A. 分配内存空间
  C. instance = 内存地址
  （instance != null 了！）
                                  ① instance != null ✓  ← 跳过 synchronized
                                  ⑤ return instance     ← 返回了半初始化的对象！
                                  ⑥ 使用 instance.xxx   ← NPE 或读到默认值！
  B. 初始化成员变量

Thread-B 在 ⑤ 处拿到的对象：内存已分配，引用已赋值，但构造方法还没执行！
成员变量都是默认值（int=0, Object=null），使用时出错。
```

### volatile 如何解决这个问题

```
volatile 的 StoreStore 屏障：
  ① A. 分配内存空间
  ② B. 初始化成员变量（普通写）
  ③ 【StoreStore 屏障】         ← 保证 ② 在 ④ 之前完成
  ④ C. instance = 内存地址（volatile 写）

有了 volatile，B 不会被重排到 C 后面，
Thread-B 要么看到 null（还没创建），要么看到完全初始化的对象。
```

### 使用 ovl 工具验证重排序

```java
// 以下代码可以验证 new Object() 的指令重排
public class DCLReorderDemo {
    static class Singleton {
        int x, y;
        Singleton() { x = 1; y = 2; }
    }

    static volatile Singleton s;

    public static void main(String[] args) throws Exception {
        for (int i = 0; ; i++) {
            // 两个线程并发
            Thread t1 = new Thread(() -> s = new Singleton());  // 写
            Thread t2 = new Thread(() -> {
                Singleton o = s;  // 读
                if (o != null && (o.x != 1 || o.y != 2)) {
                    // 不加 volatile 时，可能走到这里！
                    System.out.println("检测到半初始化！x=" + o.x + ", y=" + o.y);
                    System.exit(0);
                }
            });
            t1.start(); t2.start();
            t1.join();  t2.join();
            s = null;
        }
    }
}
```

---

## 15. 静态内部类 Holder

### 实现

```java
public class HolderSingleton {

    private HolderSingleton() {}

    // 静态内部类在外部类加载时不会被加载
    // 只有调用 getInstance() 时才会触发 Holder 类的加载和初始化
    private static class Holder {
        private static final HolderSingleton INSTANCE = new HolderSingleton();
    }

    public static HolderSingleton getInstance() {
        return Holder.INSTANCE;   // 触发 Holder 类的初始化
    }
}
```

### 线程安全分析

```
线程安全保证链路：

  ① HolderSingleton 加载时，Holder 不会被加载（延迟性 ✓）
  ② 第一次调用 getInstance() → 访问 Holder.INSTANCE
  ③ 触发 Holder 类的初始化 → JVM 获取初始化锁
  ④ JVM 保证只有一个线程执行 Holder 的 <clinit>
  ⑤ <clinit> 中 new HolderSingleton() → 实例创建
  ⑥ 其他线程等待初始化完成后读取 INSTANCE

  → 延迟加载 ✓  线程安全 ✓  不需要 volatile ✓  不需要 synchronized ✓
```

### JVM 类初始化锁机制源码（HotSpot 简化）

```cpp
// hotspot/share/runtime/classInitBarrier.cpp
// InstanceKlass::initialize_impl() 的简化逻辑

void InstanceKlass::initialize_impl(TRAPS) {
    // ① 检查初始化状态
    if (is_initialized()) return;          // 已初始化，直接返回

    // ② 获取初始化锁
    lock_init_thread();                     // CAS 设置 init_thread 为当前线程

    if (init_thread != current_thread) {
        // ③ 其他线程正在初始化，等待
        wait_init_thread(current_thread);
        return;
    }

    // ④ 当前线程执行 <clinit>
    call_class_initializer();               // 执行静态初始化块

    // ⑤ 标记为已初始化，唤醒等待线程
    set_init_state(fully_initialized);
    notify_all_waiting_threads();
}
```

### 与 DCL 的对比

```
               Holder         DCL
延迟加载       ✓              ✓
线程安全       ✓ (JVM保证)    ✓ (volatile+synchronized)
需要 volatile  ✗              ✓
需要 synchronized ✗           ✓
可传参         ✗              ✓
可防御反射     ✗ (同DCL)      ✗
可防御序列化   ✗ (同DCL)      ✗
代码复杂度     低             中

→ 没有参数需求时，Holder 是最佳选择
```

---

## 16. 枚举单例

### 实现

```java
public enum EnumSingleton {

    INSTANCE;

    // 可以有成员变量和方法
    private AtomicInteger counter = new AtomicInteger(0);

    public int increment() {
        return counter.incrementAndGet();
    }
}

// 使用
EnumSingleton.INSTANCE.increment();
```

### 为什么枚举单例是最优解

```
枚举单例的保证来自 JVM 的枚举类加载机制：

  ① 枚举类的每个实例在类加载时由 JVM 创建
  ② JVM 保证枚举实例的唯一性（不允许反射创建枚举实例）
  ③ 枚举类天然实现 Serializable，readResolve 由 JVM 保证返回同一实例
  ④ 无法通过反射破坏（Constructor.newInstance 内部检查）
  ⑤ 无法通过序列化破坏（枚举的序列化机制特殊）
  ⑥ 代码最简洁
```

### 反射防御的 JVM 源码

```java
// java.lang.reflect.Constructor.newInstance()
public T newInstance(Object... initargs) {
    // ...
    if ((clazz.getModifiers() & Modifier.ENUM) != 0) {
        // ★ 枚举类禁止通过反射创建实例！
        throw new IllegalArgumentException(
            "Cannot reflectively create enum objects");
    }
    // ...
}
```

### 序列化防御的 JVM 源码

```java
// java.io.ObjectInputStream.readObject()
// 枚举类的反序列化不走普通逻辑
private Object readOrdinaryObject() {
    // ...
    if (desc.isEnum()) {
        // ★ 枚举使用 readEnum 代替 readOrdinaryObject
        return readEnum(desc);
    }
    // ...
}

private Object readEnum(ObjectStreamClass desc) {
    // 枚举实例通过 Enum.valueOf(name) 获取
    // 而不是 new 一个新对象
    String name = readString();
    Enum<?> result = Enum.valueOf(desc.clazz, name);
    // → 返回的是已有的枚举实例，不会创建新对象
    return result;
}
```

### Effective Java 的推荐

> "This approach is functionally equivalent to the public field approach, except that it is more concise, provides the serialization machinery for free, and provides an ironclad guarantee against multiple instantiation, even in the face of sophisticated serialization or reflection attacks."
> — Joshua Bloch, *Effective Java* 3rd Edition, Item 3

---

## 17. CAS 单例（枚举替代方案）

如果不想用枚举（比如需要继承其他类），可以用 CAS 实现线程安全的懒加载：

```java
public class CASSingleton {

    private static final AtomicReference<CASSingleton> REF = new AtomicReference<>();

    private CASSingleton() {}

    public static CASSingleton getInstance() {
        CASSingleton current = REF.get();
        if (current == null) {
            CASSingleton created = new CASSingleton();
            if (REF.compareAndSet(null, created)) {
                current = created;
            } else {
                current = REF.get();  // 其他线程已创建，直接用
            }
        }
        return current;
    }
}
```

```
特点：
  ✓ 无锁，CAS 保证只有一个线程创建成功
  ✓ 延迟加载
  ✗ 可能创建多个对象（CAS 失败的线程也 new 了），但只有一个被引用
  ✗ 不能防御反射和序列化

→ 适用于对锁敏感、对创建额外对象不敏感的场景
```

---

## 18. 单例的反射与序列化破坏及防御

### 18.1 反射破坏

```java
// 攻击代码
Constructor<DCLSingleton> ctor = DCLSingleton.class.getDeclaredConstructor();
ctor.setAccessible(true);
DCLSingleton fake = ctor.newInstance();  // 创建了第二个实例！
```

### 防御：构造方法中检查

```java
public class DCLSingleton {

    private static volatile DCLSingleton instance;

    private DCLSingleton() {
        // ★ 防御反射攻击
        if (instance != null) {
            throw new IllegalStateException("单例已存在，不允许反射创建");
        }
    }

    public static DCLSingleton getInstance() {
        if (instance == null) {
            synchronized (DCLSingleton.class) {
                if (instance == null) {
                    instance = new DCLSingleton();
                }
            }
        }
        return instance;
    }
}
```

```
注意：
  这种防御不是完美的——如果反射调用在 getInstance() 之前，
  此时 instance 还是 null，检查不生效。

  真正完美的防御只有枚举（JVM 层面禁止反射创建枚举实例）。
```

### 18.2 序列化破坏

```java
// 攻击代码
ByteArrayOutputStream bos = new ByteArrayOutputStream();
ObjectOutputStream oos = new ObjectOutputStream(bos);
oos.writeObject(DCLSingleton.getInstance());

ObjectInputStream ois = new ObjectInputStream(
    new ByteArrayInputStream(bos.toByteArray()));
DCLSingleton fake = (DCLSingleton) ois.readObject();
// fake 和 DCLSingleton.getInstance() 不是同一个对象！
```

### 防御：readResolve 方法

```java
public class DCLSingleton implements Serializable {

    private static volatile DCLSingleton instance;

    private DCLSingleton() {}

    // ★ 防御序列化攻击
    // ObjectInputStream.readObject() 检测到 readResolve 方法后，
    // 用其返回值替代反序列化创建的新对象
    private Object readResolve() {
        return instance;   // 返回已有的单例实例
    }

    public static DCLSingleton getInstance() { /* ... */ }
}
```

### readResolve 的 JVM 源码

```java
// java.io.ObjectInputStream.readOrdinaryObject() 简化
private Object readOrdinaryObject() {
    Object obj = desc.newInstance();           // 创建新对象

    // 检查是否有 readResolve 方法
    Object rep = desc.invokeReadResolve(obj);  // 调用 readResolve
    if (rep != null) {
        // ★ 用 readResolve 返回的对象替代新创建的对象
        handles.setObject(passHandle, rep);
        return rep;
    }
    return obj;
}
```

### 各种单例模式的防御能力

| 单例模式 | 反射防御 | 序列化防御 | 额外代码 |
|----------|---------|-----------|---------|
| 饿汉式 | ❌（需加构造检查） | ❌（需加 readResolve） | 中 |
| DCL | ❌（需加构造检查） | ❌（需加 readResolve） | 多 |
| Holder | ❌（需加构造检查） | ❌（需加 readResolve） | 中 |
| 枚举 | ✅（JVM 保证） | ✅（JVM 保证） | 无 |
| CAS | ❌ | ❌（需加 readResolve） | 中 |

---

# Part 4 — 综合

---

## 19. volatile vs synchronized vs Lock 对比

### 三者对比表

| 维度 | volatile | synchronized | Lock (ReentrantLock) |
|------|----------|-------------|---------------------|
| **原子性** | ❌ 单次读/写 | ✅ 同步块内全部操作 | ✅ 锁保护范围内 |
| **可见性** | ✅ | ✅ | ✅ |
| **有序性** | ✅（禁止 volatile 变量重排） | ✅（happens-before） | ✅（happens-before） |
| **是否阻塞** | ❌ 不阻塞 | ✅ 阻塞竞争线程 | ✅ 阻塞竞争线程 |
| **使用方式** | 变量修饰符 | 方法 / 代码块 | lock()/unlock() |
| **可中断** | — | 不可中断 | lockInterruptibly() 可中断 |
| **超时获取** | — | 不支持 | tryLock(timeout) 支持 |
| **公平性** | — | 非公平 | 可选公平/非公平 |
| **条件变量** | — | wait/notify | Condition (多个) |
| **性能（低竞争）** | 最优 | 较优 | 较优 |
| **性能（高竞争）** | 最优（无锁） | 较差（重量级锁） | 较优（AQS 队列） |
| **典型场景** | 状态标志、DCL | 复合操作、互斥 | 复合操作、高级功能 |

### 使用决策树

```
需要保证什么？
  │
  ├─ 只需要可见性（一个线程写，其他线程读）
  │   └─ volatile ✅
  │       ├─ boolean 状态标志 → volatile boolean
  │       └─ DCL 单例 → volatile + synchronized
  │
  ├─ 需要原子性（复合操作 check-then-act）
  │   ├─ 简单的 count++ / CAS → AtomicInteger / AtomicLong
  │   ├─ 高并发计数 → LongAdder
  │   └─ 复杂的复合操作
  │       ├─ 不需要高级功能 → synchronized
  │       └─ 需要中断/超时/公平/多条件 → ReentrantLock
  │
  └─ 需要互斥（同一时刻只有一个线程执行）
      ├─ 不需要高级功能 → synchronized
      └─ 需要高级功能 → ReentrantLock / ReentrantReadWriteLock
```

---

## 20. 常见面试题

### Q1：volatile 能保证线程安全吗？

```
不一定。volatile 只保证可见性和有序性，不保证原子性。

线程安全需要三要素：原子性 + 可见性 + 有序性
  volatile 读/写本身是原子的（JMM 保证）
  但 i++ 这种复合操作不是原子的

结论：
  - 一个线程写、多个线程读 → volatile 足够
  - 多个线程写 → 需要 synchronized / Atomic / Lock
```

### Q2：volatile 和 synchronized 的区别？

```
volatile：
  - 轻量级，不阻塞
  - 只保证可见性 + 有序性
  - 适用于状态标志、DCL 单例
  - 不能用于 count++ 等复合操作

synchronized：
  - 重量级（锁升级后可能轻量）
  - 保证原子性 + 可见性 + 有序性
  - 适用于互斥、复合操作
  - 可重入、可配合 wait/notify
```

### Q3：为什么 DCL 单例需要 volatile？不加会怎样？

```
不加 volatile 时，new Singleton() 可能被指令重排序：
  正常：分配内存 → 初始化对象 → 赋值引用
  重排：分配内存 → 赋值引用 → 初始化对象

重排后，其他线程可能读到非 null 但未初始化完成的对象（半初始化），
导致 NPE 或读到成员变量的默认值。

volatile 通过 StoreStore 屏障禁止初始化操作被重排到赋值操作之后。
```

### Q4：为什么枚举单例是最好的？和 Holder 有什么区别？

```
枚举单例的优势：
  ① JVM 保证实例唯一
  ② 天然防反射（Constructor.newInstance 内部检查枚举修饰符）
  ③ 天然防序列化（ObjectInputStream.readEnum 返回已有实例）
  ④ 代码最简洁

Holder 的优势：
  ① 可以继承其他类（枚举不能继承，已经继承了 Enum）
  ② 可以传参初始化

如果不需要继承和传参，枚举是最优选择。
```

### Q5：什么是 happens-before？volatile 写和读之间的关系是什么？

```
happens-before 是 JMM 提供的可见性保证规则：
  如果 A happens-before B，则 A 的操作结果对 B 可见。

volatile 的 happens-before 关系：
  volatile 写 hb 后续对该变量的 volatile 读

这条规则是 DCL 单例的基石：
  构造方法中的初始化 hb volatile 写 hb volatile 读
  → 通过传递性，初始化操作 hb 读操作 → 读线程能看到完整初始化的对象
```

### Q6：volatile 在 x86 和 ARM 上的实现有什么区别？

```
x86（强内存模型 TSO）：
  - 只允许 Store-Load 重排
  - volatile 写：只需加 lock 前缀指令（等价 StoreLoad 屏障）
  - volatile 读：不需要任何屏障指令
  - 性能开销较小

ARM（弱内存模型）：
  - 允许所有四种重排
  - volatile 写：需要 dmb ishst（StoreStore）+ dmb ish（StoreLoad）
  - volatile 读：需要 dmb ishld（LoadLoad + LoadStore）
  - 性能开销较大

这就是为什么某些并发 bug 在 x86 上跑不出，部署到 ARM 就暴露了。
```

### Q7：LongAdder 为什么比 AtomicLong 快？sum() 有什么问题？

```
快的原因：分散热点
  AtomicLong：N 个线程 CAS 竞争同一个 value → 大量自旋
  LongAdder：每个线程 CAS 自己的 Cell → 几乎无竞争

sum() 的问题：
  sum() 遍历 base + 所有 Cell 求和，不加锁
  遍历过程中可能有其他线程在修改 Cell
  → sum() 返回的是近似值，不是强一致快照

适用场景：
  ✓ 统计计数（如 ConcurrentHashMap 的 size）
  ✗ 需要精确值的场景（如账户余额）
```

### Q8：什么是 false sharing？怎么解决？

```
False Sharing：不同 CPU 核心修改同一缓存行中的不同变量，
导致缓存行频繁失效，产生乒乓效应。

解决方法：
  ① @Contended 注解（JDK 8+）
     @sun.misc.Contended  // 需要 -XX:-RestrictContended
     volatile long value;

  ② 手动填充
     public class PaddedAtomicLong {
         volatile long p1, p2, p3, p4, p5, p6;  // 6 × 8 = 48 字节填充
         volatile long value;                      // 被隔离在单独的缓存行
         volatile long q1, q2, q3, q4, q5, q6;  // 后面也填充
     }

  ③ @jdk.internal.vm.annotation.Contended（JDK 9+）
     JDK 内部使用，用户代码一般用 @sun.misc.Contended
```

### Q9：JMM 中的 8 种原子操作是什么？volatile 有什么特殊规则？

```
8 种操作：lock / unlock / read / load / use / assign / store / write

volatile 的特殊规则：
  ① read-load-use 必须连续出现（每次 use 前都从主内存刷新）
  ② assign-store-write 必须连续出现（每次 assign 后立即同步回主内存）
  ③ 不允许 volatile 变量与任何操作重排序（由内存屏障保证）
```

### Q10：单例模式有哪几种写法？各有什么优缺点？

```
1. 饿汉式
   ✓ 线程安全（JVM 保证）  ✗ 不能延迟加载

2. 懒汉式 synchronized 方法
   ✓ 线程安全  ✗ 每次调用都加锁，性能差

3. DCL（双重检查锁）
   ✓ 延迟加载  ✓ 只初始化时加锁
   ✗ 必须加 volatile  ✗ 代码复杂

4. 静态内部类 Holder
   ✓ 延迟加载  ✓ 线程安全（JVM 保证）✓ 无锁
   ✗ 不能传参  ✗ 不能防反射/序列化

5. 枚举单例
   ✓ 线程安全  ✓ 防反射  ✓ 防序列化  ✓ 代码简洁
   ✗ 不能继承其他类  ✗ 不能延迟加载

推荐：
  - 一般场景 → 枚举（Effective Java 推荐）
  - 需要延迟加载 → Holder
  - 需要传参 → DCL + volatile
```

---

> 本文档从 JMM 的理论框架出发，向下深入到 CPU 缓存协议与内存屏障的硬件实现，向上覆盖 volatile 的 JDK 源码应用与单例模式的线程安全保证。
> 建议学习路径：**JMM → volatile → DCL 单例**。理解了 JMM 的 happens-before 和内存屏障，volatile 和 DCL 都是水到渠成。
