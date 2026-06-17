# Java 线程池（ThreadPoolExecutor）源码深度解析

> 基于 JDK 8 版本，覆盖 JDK 8/11/17 关键差异标注

---

## 目录

1. [整体架构](#1-整体架构)
2. [核心字段与 ctl 状态控制](#2-核心字段与-ctl-状态控制)
3. [构造方法与七大参数](#3-构造方法与七大参数)
4. [execute 流程（核心）](#4-execute-流程核心)
5. [addWorker 添加工作线程](#5-addworker-添加工作线程)
6. [Worker 内部类与 runWorker](#6-worker-内部类与-runworker)
7. [getTask 与线程回收](#7-gettask-与线程回收)
8. [processWorkerExit 线程退出处理](#8-processworkerexit-线程退出处理)
9. [线程池状态转换](#9-线程池状态转换)
10. [拒绝策略](#10-拒绝策略)
11. [shutdown 与 shutdownNow](#11-shutdown-与-shutdownnow)
12. [ScheduledThreadPoolExecutor 定时线程池](#12-scheduledthreadpoolexecutor-定时线程池)
13. [Executors 工厂方法与坑](#13-executors-工厂方法与坑)
14. [线程池调优实践](#14-线程池调优实践)
15. [JDK 版本演进对比](#15-jdk-版本演进对比)
16. [常见面试题](#16-常见面试题)

---

## 1. 整体架构

ThreadPoolExecutor 是 Java 线程池的核心实现，本质上是一个**生产者-消费者模型**：

```
┌─────────────────────────────────────────────────────────────────┐
│                    ThreadPoolExecutor                            │
│                                                                  │
│  ┌──────────────┐     ┌─────────────────────────────────────┐   │
│  │  提交任务     │     │  任务队列 (BlockingQueue<Runnable>)  │   │
│  │  execute()   │────▶│                                     │   │
│  │  submit()    │     │  task1 ← task2 ← task3 ← task4 ...  │   │
│  └──────────────┘     └──────────────┬──────────────────────┘   │
│                                      │ getTask() 取任务          │
│                       ┌──────────────▼──────────────────────┐   │
│                       │         工作线程集合                   │   │
│                       │     HashSet<Worker> workers          │   │
│                       │                                     │   │
│                       │  ┌───────┐ ┌───────┐ ┌───────┐      │   │
│                       │  │Worker1│ │Worker2│ │Worker3│      │   │
│                       │  │Thread │ │Thread │ │Thread │      │   │
│                       │  └───────┘ └───────┘ └───────┘      │   │
│                       │   core线程   core线程  非core线程     │   │
│                       └─────────────────────────────────────┘   │
│                                                                  │
│  ctl: 原子整数，高3位=运行状态，低29位=线程数                       │
│  状态: RUNNING → SHUTDOWN → STOP → TIDYING → TERMINATED         │
└─────────────────────────────────────────────────────────────────┘
```

**核心角色：**

| 角色 | 对应组件 | 作用 |
|------|----------|------|
| 生产者 | 调用 execute/submit 的线程 | 提交任务到队列 |
| 消费者 | Worker 线程 | 从队列取任务执行 |
| 缓冲区 | BlockingQueue | 任务队列，解耦生产消费 |
| 管理者 | ThreadPoolExecutor | 控制线程数、状态、拒绝策略 |

---

## 2. 核心字段与 ctl 状态控制

### 2.1 ctl —— 一个整数存两个信息

```java
// 原子整数，同时存储 运行状态（高3位） 和 线程数量（低29位）
private final AtomicInteger ctl = new AtomicInteger(ctlOf(RUNNING, 0));

// 29 位用于存储线程数
private static final int COUNT_BITS = Integer.SIZE - 3;  // 29
// 最大线程数 = 2^29 - 1 ≈ 5 亿
private static final int CAPACITY   = (1 << COUNT_BITS) - 1;

// ========== 运行状态（高3位） ==========
// 111 00000...000  → -536870912
private static final int RUNNING    = -1 << COUNT_BITS;
// 000 00000...000  → 0
private static final int SHUTDOWN   =  0 << COUNT_BITS;
// 001 00000...000  → 536870912
private static final int STOP       =  1 << COUNT_BITS;
// 010 00000...000  → 1073741824
private static final int TIDYING    =  2 << COUNT_BITS;
// 011 00000...000  → 1610612736
private static final int TERMINATED =  3 << COUNT_BITS;
```

### 2.2 ctl 的位运算工具方法

```java
// 取运行状态（高3位）
private static int runStateOf(int c)     { return c & ~CAPACITY; }

// 取线程数量（低29位）
private static int workerCountOf(int c)  { return c & CAPACITY; }

// 组合状态和数量
private static int ctlOf(int rs, int wc) { return rs | wc; }
```

**示例：**

```
ctl = -536870912 (RUNNING, 0个线程)
  二进制: 1110 0000 0000 0000 0000 0000 0000 0000
  runStateOf → 1110 0000 ... → RUNNING
  workerCountOf → 0

ctl = -536870911 (RUNNING, 1个线程)
  二进制: 1110 0000 0000 0000 0000 0000 0000 0001
  runStateOf → 1110 0000 ... → RUNNING
  workerCountOf → 1
```

### 2.3 五种运行状态

| 状态 | 值 | 含义 | 接受新任务 | 处理队列任务 |
|------|----|------|-----------|-------------|
| **RUNNING** | -1 | 正常运行 | ✅ | ✅ |
| **SHUTDOWN** | 0 | 调用 shutdown() | ❌ | ✅（处理完队列中已有任务） |
| **STOP** | 1 | 调用 shutdownNow() | ❌ | ❌（中断正在执行的任务） |
| **TIDYING** | 2 | 所有任务完成，线程数为0 | ❌ | ❌（执行 terminated 钩子） |
| **TERMINATED** | 3 | terminated() 执行完毕 | ❌ | ❌ |

### 2.4 状态大小关系

```java
// 状态值越大，越接近终止
// 可以用 < / > 比较状态
private static boolean runStateLessThan(int c, int s) {
    return c < s;
}
private static boolean runStateAtLeast(int c, int s) {
    return c >= s;
}
private static boolean isRunning(int c) {
    return c < SHUTDOWN; // RUNNING 是负数，SHUTDOWN 是 0
}
```

### 2.5 其他核心字段

```java
// 工作线程集合
private final HashSet<Worker> workers = new HashSet<Worker>();

// 任务队列
private final BlockingQueue<Runnable> workQueue;

// 线程工厂
private volatile ThreadFactory threadFactory;

// 拒绝策略
private volatile RejectedExecutionHandler handler;

// 非核心线程的空闲存活时间
private volatile long keepAliveTime;

// 是否允许核心线程超时回收
private volatile boolean allowCoreThreadTimeOut;

// 核心线程数
private volatile int corePoolSize;

// 最大线程数
private volatile int maximumPoolSize;

// 已完成任务数
private volatile long completedTaskCount;

// 线程池达到的最大容量（用于监控）
private int largestPoolSize;
```

---

## 3. 构造方法与七大参数

### 3.1 完整构造方法

```java
public ThreadPoolExecutor(
    int corePoolSize,                  // ① 核心线程数
    int maximumPoolSize,               // ② 最大线程数
    long keepAliveTime,                // ③ 非核心线程空闲存活时间
    TimeUnit unit,                     // ④ 时间单位
    BlockingQueue<Runnable> workQueue, // ⑤ 任务队列
    ThreadFactory threadFactory,       // ⑥ 线程工厂
    RejectedExecutionHandler handler   // ⑦ 拒绝策略
) {
    if (corePoolSize < 0 ||
        maximumPoolSize <= 0 ||
        maximumPoolSize < corePoolSize ||
        keepAliveTime < 0)
        throw new IllegalArgumentException();
    if (workQueue == null || threadFactory == null || handler == null)
        throw new NullPointerException();
    this.corePoolSize = corePoolSize;
    this.maximumPoolSize = maximumPoolSize;
    this.workQueue = workQueue;
    this.keepAliveTime = unit.toNanos(keepAliveTime);
    this.threadFactory = threadFactory;
    this.handler = handler;
}
```

### 3.2 七大参数详解

```
                    corePoolSize
                    │
    ┌───────────────┼───────────────┐
    │   核心线程区   │   弹性线程区   │
    │  (常驻不回收)  │  (空闲回收)    │
    │               │               │
    │  ←── 线程数 ──→               │
    │           maximumPoolSize      │
    └───────────────────────────────┘

    keepAliveTime: 弹性线程区的线程空闲超过此时间 → 被回收
    allowCoreThreadTimeOut=true: 核心线程也可以被回收
```

| 参数 | 含义 | 常用值 |
|------|------|--------|
| corePoolSize | 核心线程数，即使空闲也不回收（默认） | CPU密集: N+1; IO密集: 2N |
| maximumPoolSize | 最大线程数 | 按业务峰值设置 |
| keepAliveTime | 非核心线程空闲存活时间 | 60s |
| unit | keepAliveTime 的时间单位 | TimeUnit.SECONDS |
| workQueue | 任务等待队列 | 见下表 |
| threadFactory | 创建线程的工厂，可自定义线程名 | 自定义命名工厂 |
| handler | 队列满+线程满时的拒绝策略 | AbortPolicy |

### 3.3 常用任务队列

| 队列类型 | 特点 | 适用场景 |
|----------|------|----------|
| `LinkedBlockingQueue` | 无界（默认 Integer.MAX_VALUE） | FixedThreadPool |
| `SynchronousQueue` | 不存储，直接交付 | CachedThreadPool |
| `ArrayBlockingQueue` | 有界 | 需要控制队列长度 |
| `PriorityBlockingQueue` | 优先级排序 | 任务有优先级 |
| `DelayQueue` | 延迟执行 | ScheduledThreadPool |

**⚠️ 重要**：使用无界队列时，maximumPoolSize 将永远不会生效（队列永远不会满），可能导致 OOM！

---

## 4. execute 流程（核心）

### 4.1 完整源码 + 逐行注释

```java
public void execute(Runnable command) {
    if (command == null)
        throw new NullPointerException();

    int c = ctl.get();

    // ① 当前线程数 < corePoolSize → 创建核心线程执行任务
    if (workerCountOf(c) < corePoolSize) {
        if (addWorker(command, true)) // true 表示核心线程
            return;
        c = ctl.get(); // CAS 失败，重新获取 ctl
    }

    // ② 线程数 ≥ corePoolSize → 任务入队
    if (isRunning(c) && workQueue.offer(command)) {
        int recheck = ctl.get();

        // ②-1 双重检查：入队后池子可能被 shutdown 了
        if (!isRunning(recheck) && remove(command))
            reject(command);

        // ②-2 入队成功，但可能没有工作线程了（比如线程刚因超时退出）
        else if (workerCountOf(recheck) == 0)
            addWorker(null, false); // 创建一个非核心线程来处理队列任务
    }

    // ③ 队列满了 → 尝试创建非核心线程
    else if (!addWorker(command, false)) // false 表示非核心线程
        // ③-1 线程数已达 maximumPoolSize → 执行拒绝策略
        reject(command);
}
```

### 4.2 流程图

```
execute(command)
    │
    ▼
线程数 < corePoolSize？──是──→ addWorker(command, true) 创建核心线程
    │                              │
    │                        成功 → return
    │                        失败 → 继续（CAS竞争失败）
    ▼
任务入队 workQueue.offer(command)
    │
    ├─ 入队成功
    │     │
    │     ▼
    │   双重检查：池子还在运行吗？
    │     ├─ 已 shutdown + remove 成功 → reject()
    │     ├─ 线程数 == 0 → addWorker(null, false) 创建空闲线程消费队列
    │     └─ 正常 → return
    │
    ├─ 入队失败（队列满了）
    │     │
    │     ▼
    │   addWorker(command, false) 创建非核心线程
    │     ├─ 成功 → return
    │     └─ 失败（线程数 ≥ maximumPoolSize）→ reject() 拒绝策略
    │
    ▼
结束
```

### 4.3 三层递进策略

```
任务提交顺序：

  第1层：核心线程        ← 线程数 < corePoolSize 时直接创建
  第2层：任务队列        ← 核心线程满了，任务放入队列等待
  第3层：非核心线程      ← 队列也满了，创建非核心线程
  第4层：拒绝策略        ← 线程数已达 maximumPoolSize，执行拒绝策略
```

这就是线程池的**核心设计哲学**：先用核心线程，再排队，再扩容，最后拒绝。

---

## 5. addWorker 添加工作线程

### 5.1 完整源码 + 逐行注释

```java
private boolean addWorker(Runnable firstTask, boolean core) {
    // ====== 第一部分：CAS 递增线程数 ======
    retry:
    for (;;) {
        int c = ctl.get();
        int rs = runStateOf(c);

        // ① 状态检查：
        //    - rs >= SHUTDOWN：池子不在 RUNNING 状态
        //    - 但有一个例外：SHUTDOWN 状态下仍可创建线程来处理队列中的任务
        //      条件：rs == SHUTDOWN && firstTask == null && !workQueue.isEmpty()
        if (rs >= SHUTDOWN &&
            !(rs == SHUTDOWN && firstTask == null && !workQueue.isEmpty()))
            return false;

        for (;;) {
            int wc = workerCountOf(c);
            // ② 线程数上限检查
            if (wc >= CAPACITY || wc >= (core ? corePoolSize : maximumPoolSize))
                return false;
            // ③ CAS 递增线程数
            if (compareAndIncrementWorkerCount(c))
                break retry; // 成功，跳出外层循环
            // ④ CAS 失败，检查是否状态变了
            if (runStateOf(ctl.get()) != rs)
                continue retry; // 状态变了，重试外层循环
            // 状态没变，只是线程数 CAS 失败，重试内层循环
        }
    }

    // ====== 第二部分：创建 Worker 并启动线程 ======
    boolean workerStarted = false;
    boolean workerAdded = false;
    Worker w = null;
    try {
        // ⑤ 创建 Worker（内部创建 Thread）
        w = new Worker(firstTask);
        Thread t = w.thread;
        if (t != null) {
            final ReentrantLock mainLock = this.mainLock;
            mainLock.lock();
            try {
                // ⑥ 再次检查状态（获取锁期间状态可能变化）
                int rs = runStateOf(ctl.get());
                if (rs < SHUTDOWN ||
                    (rs == SHUTDOWN && firstTask == null)) {
                    if (t.isAlive()) // 线程已经启动了？不应该
                        throw new IllegalThreadStateException();
                    workers.add(w); // 加入工作线程集合
                    int s = workers.size();
                    if (s > largestPoolSize)
                        largestPoolSize = s; // 更新最大线程数记录
                    workerAdded = true;
                }
            } finally {
                mainLock.unlock();
            }
            if (workerAdded) {
                t.start();      // ⑦ 启动线程
                workerStarted = true;
            }
        }
    } finally {
        if (!workerStarted)
            addWorkerFailed(w); // 清理：从 workers 移除，递减线程数
    }
    return workerStarted;
}
```

### 5.2 关键细节

**Q: 为什么 addWorker 需要先 CAS 递增线程数，再创建 Worker？**

如果先创建 Worker 再递增线程数，可能导致线程数超过限制（多个线程同时创建 Worker）。先 CAS 递增相当于"占位"，确保不超过上限。

**Q: mainLock 是什么？**

```java
private final ReentrantLock mainLock = new ReentrantLock();
```

用于保护 workers 集合的并发访问。大多数操作是无锁的（CAS），只有修改 workers 集合时才加锁。

---

## 6. Worker 内部类与 runWorker

### 6.1 Worker 结构

```java
private final class Worker
    extends AbstractQueuedSynchronizer  // 实现了不可重入的独占锁
    implements Runnable
{
    // 工作线程
    final Thread thread;
    // 初始任务（可能为 null）
    Runnable firstTask;
    // 已完成任务数
    volatile long completedTasks;

    Worker(Runnable firstTask) {
        // 设置 AQS state = -1，禁止在 runWorker 前被中断
        setState(-1);
        this.firstTask = firstTask;
        this.thread = getThreadFactory().newThread(this); // Worker 自己就是 Runnable
    }

    public void run() {
        runWorker(this);
    }

    // ====== 不可重入锁的实现 ======
    // 0: 未锁定    1: 已锁定
    protected boolean tryAcquire(int unused) {
        if (compareAndSetState(0, 1)) {
            setExclusiveOwnerThread(Thread.currentThread());
            return true;
        }
        return false;
    }

    protected boolean tryRelease(int unused) {
        setExclusiveOwnerThread(null);
        setState(0);
        return true;
    }

    // 为什么不可重入？
    // 如果可重入，线程在执行任务时调用 shutdown() 会中断自己
    // 不可重入锁使得 shutdown() 的 interruptWorkers() 能够正确判断：
    //   - 锁被持有 → 线程正在执行任务 → 不中断
    //   - 锁未被持有 → 线程在等待任务 → 可以中断
}
```

### 6.2 Worker 不可重入锁的精妙设计

```
Worker 锁状态与线程状态的关系：

lock() 成功（获取到锁）  → 线程正在执行任务
lock() 失败（锁被占用）  → 线程正在执行任务（同一线程重入）
unlock()                → 任务执行完毕，准备获取下一个任务

shutdown() 的 interruptIdleWorkers() 逻辑：
  tryLock() 成功 → 线程空闲（未在执行任务）→ 中断
  tryLock() 失败 → 线程忙碌（正在执行任务）→ 不中断

如果锁是可重入的：
  线程在执行任务时获取了锁 → tryLock() 因为可重入会成功 → 误中断正在执行的任务！
  不可重入锁保证了：执行任务期间 tryLock() 一定失败 → 不会被误中断
```

### 6.3 runWorker 完整源码 + 逐行注释

```java
final void runWorker(Worker w) {
    Thread wt = Thread.currentThread();
    Runnable task = w.firstTask;
    w.firstTask = null;
    w.unlock(); // 将 AQS state 从 -1 重置为 0（允许中断）

    boolean completedAbruptly = true; // 是否异常退出
    try {
        // ① 循环获取任务：
        //    - firstTask 不为 null → 先执行初始任务
        //    - firstTask 为 null → 从队列获取 (getTask)
        while (task != null || (task = getTask()) != null) {
            w.lock(); // 标记：线程正在执行任务

            // ② 中断检查：
            //    如果池子正在 STOP 及以上状态 → 确保线程被中断
            //    如果池子正在 SHUTDOWN → 确保线程不被中断
            if ((runStateAtLeast(ctl.get(), STOP) ||
                 (Thread.interrupted() &&
                  runStateAtLeast(ctl.get(), STOP))) &&
                !wt.isInterrupted())
                wt.interrupt();

            try {
                beforeExecute(wt, task); // ③ 前置钩子（可重写）
                Throwable thrown = null;
                try {
                    task.run();          // ④ 执行任务！
                } catch (RuntimeException x) {
                    thrown = x; throw x;
                } catch (Error x) {
                    thrown = x; throw x;
                } catch (Throwable x) {
                    thrown = x; throw new Error(x);
                } finally {
                    afterExecute(task, thrown); // ⑤ 后置钩子（可重写）
                }
            } finally {
                task = null;
                w.completedTasks++;
                w.unlock(); // 标记：任务执行完毕
            }
        }

        completedAbruptly = false; // 正常退出（getTask 返回 null）
    } finally {
        // ⑥ 线程退出处理
        processWorkerExit(w, completedAbruptly);
    }
}
```

### 6.4 runWorker 流程图

```
runWorker(Worker w)
    │
    ▼
unlock()  ← 将 state 从 -1 重置为 0
    │
    ▼
┌─→ task = firstTask 或 getTask()
│       │
│    task == null？──是──→ processWorkerExit() 线程退出
│       │
│      否
│       ▼
│   lock() ← 标记线程忙碌
│       │
│       ▼
│   检查中断状态（STOP 时确保被中断）
│       │
│       ▼
│   beforeExecute() ← 钩子
│       │
│       ▼
│   task.run() ← 执行任务！
│       │
│       ▼
│   afterExecute() ← 钩子
│       │
│       ▼
│   unlock() ← 标记线程空闲
│       │
└─── ← 循环
```

---

## 7. getTask 与线程回收

### 7.1 完整源码 + 逐行注释

```java
private Runnable getTask() {
    boolean timedOut = false; // 上次 poll 是否超时

    for (;;) {
        int c = ctl.get();
        int rs = runStateOf(c);

        // ① 状态检查：SHUTDOWN 且队列为空 → 返回 null，线程退出
        //             STOP 及以上 → 返回 null，线程退出
        if (rs >= SHUTDOWN && (rs >= STOP || workQueue.isEmpty())) {
            decrementWorkerCount();
            return null;
        }

        int wc = workerCountOf(c);

        // ② 是否需要超时控制
        //    timed = true 的条件：
        //    - allowCoreThreadTimeOut = true（核心线程也超时回收）
        //    - 当前线程数 > corePoolSize（非核心线程，需要超时回收）
        boolean timed = allowCoreThreadTimeOut || wc > corePoolSize;

        // ③ 线程退出条件：
        //    - 线程数 > maximumPoolSize（maximumPoolSize 被动态调小了）
        //    - 超时 且 (线程数 > 1 或 队列为空)
        //    且 (线程数 > 1 或 队列为空) → 保证至少有一个线程处理剩余任务
        if ((wc > maximumPoolSize || (timed && timedOut))
            && (wc > 1 || workQueue.isEmpty())) {
            if (compareAndDecrementWorkerCount(c))
                return null; // 递减线程数，返回 null → 线程退出
            continue;
        }

        // ④ 从队列获取任务
        try {
            Runnable r = timed ?
                workQueue.poll(keepAliveTime, TimeUnit.NANOSECONDS) : // 超时获取
                workQueue.take();  // 阻塞获取（核心线程永久等待）
            if (r != null)
                return r;
            timedOut = true; // poll 超时，设置标志
        } catch (InterruptedException retry) {
            timedOut = false; // 被中断，重试
        }
    }
}
```

### 7.2 线程回收机制详解

```
核心线程（timed = false）:
  workQueue.take() → 永久阻塞等待任务 → 不会被回收
  （除非 allowCoreThreadTimeOut = true）

非核心线程（timed = true）:
  workQueue.poll(keepAliveTime) → 等待 keepAliveTime 后超时
  → timedOut = true → 下次循环满足退出条件 → return null → 线程退出

线程退出流程：
  getTask() 返回 null
    → runWorker 的 while 循环结束
    → processWorkerExit(w, false)
    → 线程自然终止
```

### 7.3 核心线程预热

```java
// JDK 提供的预热方法，创建核心线程等待任务
public int prestartCoreThread() {
    return workerCountOf(ctl.get()) < corePoolSize ?
        addWorker(null, true) : 0;
}

// 预热所有核心线程
public int prestartAllCoreThreads() {
    int n = 0;
    while (addWorker(null, true))
        ++n;
    return n;
}
```

---

## 8. processWorkerExit 线程退出处理

```java
private void processWorkerExit(Worker w, boolean completedAbruptly) {
    // ① 如果是异常退出，线程数还没递减，需要手动递减
    if (completedAbruptly)
        decrementWorkerCount();

    final ReentrantLock mainLock = this.mainLock;
    mainLock.lock();
    try {
        // ② 从 workers 集合中移除
        completedTaskCount += w.completedTasks;
        workers.remove(w);
    } finally {
        mainLock.unlock();
    }

    // ③ 尝试终止线程池
    tryTerminate();

    int c = ctl.get();
    // ④ 如果池子还在运行（RUNNING 或 SHUTDOWN）
    if (runStateLessThan(c, STOP)) {
        if (!completedAbruptly) {
            // 正常退出时，确保最少保留 min 个线程
            int min = allowCoreThreadTimeOut ? 0 : corePoolSize;
            if (min == 0 && !workQueue.isEmpty())
                min = 1; // 队列不空，至少保留1个线程
            if (workerCountOf(c) >= min)
                return; // 线程数足够，不需要补充
        }
        // 异常退出 或 线程数不足 → 补充一个线程
        addWorker(null, false);
    }
}
```

---

## 9. 线程池状态转换

### 9.1 完整状态转换图

```
                    execute()
                       │
                       ▼
              ┌──────────────┐
              │   RUNNING    │  接受新任务，处理队列任务
              │   ctl < 0    │
              └──────┬───────┘
                     │ shutdown()
                     ▼
              ┌──────────────┐
         ┌───▶│   SHUTDOWN   │  不接受新任务，处理队列中的已有任务
         │    │   ctl = 0    │
         │    └──────┬───────┘
         │           │ 队列为空 且 线程数为0
         │           ▼
         │    ┌──────────────┐
         │    │   TIDYING    │  所有任务完成，线程数为0
         │    │              │  执行 terminated() 钩子
         │    └──────┬───────┘
         │           │ terminated() 执行完毕
         │           ▼
         │    ┌──────────────┐
         │    │  TERMINATED  │  终止完成
         │    │              │
         │    └──────────────┘
         │
         │    shutdownNow()
         │           │
         │           ▼
         │    ┌──────────────┐
         └────│     STOP     │  不接受新任务，不处理队列，中断正在执行的任务
              │   ctl > 0    │
              └──────┬───────┘
                     │ 线程数为0
                     ▼
              ┌──────────────┐
              │   TIDYING    │  →  TERMINATED
              └──────────────┘
```

### 9.2 tryTerminate

```java
final void tryTerminate() {
    for (;;) {
        int c = ctl.get();
        // 以下情况不需要终止：
        // 1. 还在 RUNNING
        // 2. 已经 TERMINATED
        // 3. SHUTDOWN 但队列不为空（还有任务要处理）
        if (isRunning(c) || runStateAtLeast(c, TIDYING) ||
            (runStateOf(c) == SHUTDOWN && !workQueue.isEmpty()))
            return;

        // 可以终止，但还有工作线程
        if (workerCountOf(c) != 0) {
            // 中断一个空闲线程，触发连锁反应
            // 每个线程退出时都会调用 tryTerminate
            interruptIdleWorkers(ONLY_ONE);
            return;
        }

        final ReentrantLock mainLock = this.mainLock;
        mainLock.lock();
        try {
            // CAS 将状态改为 TIDYING
            if (ctl.compareAndSet(c, ctlOf(TIDYING, 0))) {
                try {
                    terminated(); // 钩子方法
                } finally {
                    ctl.set(ctlOf(TERMINATED, 0)); // 改为 TERMINATED
                    termination.signalAll(); // 唤醒 awaitTermination 的线程
                }
                return;
            }
        } finally {
            mainLock.unlock();
        }
    }
}
```

---

## 10. 拒绝策略

### 10.1 触发时机

```
1. 线程数 ≥ maximumPoolSize 且 队列已满 → 新任务被拒绝
2. 线程池已关闭（SHUTDOWN/STOP/...） → 新任务被拒绝
```

### 10.2 四种内置拒绝策略

```java
// ① AbortPolicy（默认）—— 抛出 RejectedExecutionException
public static class AbortPolicy implements RejectedExecutionHandler {
    public void rejectedExecution(Runnable r, ThreadPoolExecutor e) {
        throw new RejectedExecutionException("Task " + r.toString() +
                                             " rejected from " + e.toString());
    }
}

// ② CallerRunsPolicy —— 由提交任务的线程自己执行
public static class CallerRunsPolicy implements RejectedExecutionHandler {
    public void rejectedExecution(Runnable r, ThreadPoolExecutor e) {
        if (!e.isShutdown()) {
            r.run(); // 提交线程自己执行，起到负反馈作用
        }
    }
}

// ③ DiscardPolicy —— 静默丢弃，不抛异常
public static class DiscardPolicy implements RejectedExecutionHandler {
    public void rejectedExecution(Runnable r, ThreadPoolExecutor e) {
        // 什么都不做
    }
}

// ④ DiscardOldestPolicy —— 丢弃队列中最老的任务，重新提交当前任务
public static class DiscardOldestPolicy implements RejectedExecutionHandler {
    public void rejectedExecution(Runnable r, ThreadPoolExecutor e) {
        if (!e.isShutdown()) {
            e.getQueue().poll();   // 丢弃队列头部（最老的任务）
            e.execute(r);          // 重新提交当前任务
        }
    }
}
```

### 10.3 拒绝策略对比

| 策略 | 行为 | 适用场景 |
|------|------|----------|
| **AbortPolicy** | 抛异常 | 默认策略，需要感知拒绝 |
| **CallerRunsPolicy** | 提交线程执行 | 不丢弃任务，自动降速 |
| **DiscardPolicy** | 静默丢弃 | 可接受任务丢失 |
| **DiscardOldestPolicy** | 丢最老任务 | 优先处理新任务 |

### 10.4 CallerRunsPolicy 的负反馈机制

```
线程池满 → CallerRunsPolicy → 提交线程自己执行任务
                               │
                               ▼
                    提交线程忙于执行任务，无法继续提交
                               │
                               ▼
                    自动降低提交速率，给线程池喘息时间
```

### 10.5 自定义拒绝策略

```java
// 示例：记录日志 + 持久化到数据库
public class LogAndPersistPolicy implements RejectedExecutionHandler {
    @Override
    public void rejectedExecution(Runnable r, ThreadPoolExecutor executor) {
        log.warn("Task rejected: {}, pool size: {}", r, executor.getPoolSize());
        // 持久化到数据库，后续恢复执行
        saveToDatabase(r);
    }
}
```

---

## 11. shutdown 与 shutdownNow

### 11.1 shutdown —— 优雅关闭

```java
public void shutdown() {
    final ReentrantLock mainLock = this.mainLock;
    mainLock.lock();
    try {
        checkShutdownAccess();          // 安全检查
        advanceRunState(SHUTDOWN);      // CAS 将状态改为 SHUTDOWN
        interruptIdleWorkers();         // 中断所有空闲线程
        onShutdown();                   // 钩子（ScheduledThreadPoolExecutor 用）
    } finally {
        mainLock.unlock();
    }
    tryTerminate(); // 尝试终止
}
```

### 11.2 shutdownNow —— 立即关闭

```java
public List<Runnable> shutdownNow() {
    List<Runnable> tasks;
    final ReentrantLock mainLock = this.mainLock;
    mainLock.lock();
    try {
        checkShutdownAccess();
        advanceRunState(STOP);           // CAS 将状态改为 STOP
        interruptWorkers();              // 中断所有工作线程（包括忙碌的）
        tasks = drainQueue();            // 取出队列中剩余的任务
    } finally {
        mainLock.unlock();
    }
    tryTerminate();
    return tasks; // 返回未执行的任务列表
}
```

### 11.3 interruptIdleWorkers vs interruptWorkers

```java
// 只中断空闲线程（tryLock 成功 = 线程空闲）
private void interruptIdleWorkers(boolean onlyOne) {
    for (Worker w : workers) {
        Thread t = w.thread;
        if (w.tryLock()) {  // 尝试获取 Worker 锁
            try {
                t.interrupt();
            } catch (SecurityException ignore) {
            } finally {
                w.unlock();
            }
        }
    }
}

// 中断所有线程（包括正在执行任务的）
private void interruptWorkers() {
    for (Worker w : workers) {
        Thread t = w.thread;
        if (t != null && !t.isInterrupted()) {
            try {
                t.interrupt();
            } catch (SecurityException ignore) {
            }
        }
    }
}
```

### 11.4 shutdown vs shutdownNow 对比

| | shutdown | shutdownNow |
|---|----------|-------------|
| 状态 | SHUTDOWN | STOP |
| 新任务 | 拒绝 | 拒绝 |
| 队列任务 | 继续执行完 | 不执行，返回 |
| 正在执行的任务 | 不中断 | 发送中断 |
| 返回值 | void | List\<Runnable\>（未执行的任务） |
| 场景 | 优雅关闭 | 立即停止 |

### 11.5 优雅关闭最佳实践

```java
public void gracefulShutdown(ExecutorService pool) {
    pool.shutdown(); // 不再接受新任务
    try {
        // 等待 60 秒让已有任务完成
        if (!pool.awaitTermination(60, TimeUnit.SECONDS)) {
            pool.shutdownNow(); // 超时后强制关闭
            // 再等 60 秒
            if (!pool.awaitTermination(60, TimeUnit.SECONDS)) {
                log.error("Pool did not terminate");
            }
        }
    } catch (InterruptedException ie) {
        pool.shutdownNow();
        Thread.currentThread().interrupt();
    }
}
```

---

## 12. ScheduledThreadPoolExecutor 定时线程池

### 12.1 类层次结构

```
ExecutorService
    └── AbstractExecutorService
            └── ThreadPoolExecutor
                    └── ScheduledThreadPoolExecutor

ScheduledExecutorService（接口，定义定时/周期方法）
                    └── ScheduledThreadPoolExecutor（实现）
```

### 12.2 核心数据结构

```java
public class ScheduledThreadPoolExecutor
        extends ThreadPoolExecutor
        implements ScheduledExecutorService {

    // 延迟队列（按延迟时间排序的优先级队列）
    static class DelayedWorkQueue extends AbstractQueue<Runnable>
        implements BlockingQueue<Runnable> {
        // 最小堆，按 time 排序
        // time 小的（快到期）在堆顶
    }
}
```

### 12.3 ScheduledFutureTask

```java
private class ScheduledFutureTask<V>
        extends FutureTask<V> implements RunnableScheduledFuture<V> {

    // 任务下次执行的时间（纳秒）
    private long time;

    // 周期任务的间隔（纳秒）
    // > 0: 固定速率（scheduleAtFixedRate）
    // < 0: 固定延迟（scheduleWithFixedDelay）
    // = 0: 非周期任务
    private final long period;

    // 在堆中的索引，用于快速删除
    int heapIndex;
}
```

### 12.4 四个调度方法

```java
// ① 延迟执行一次（非周期）
public ScheduledFuture<?> schedule(Runnable command, long delay, TimeUnit unit);

// ② 延迟执行一次（带返回值）
public <V> ScheduledFuture<V> schedule(Callable<V> callable, long delay, TimeUnit unit);

// ③ 固定速率执行
//    上次开始时间 + period = 下次开始时间
//    如果任务执行时间 > period，则立即开始下一次
public ScheduledFuture<?> scheduleAtFixedRate(
    Runnable command, long initialDelay, long period, TimeUnit unit);

// ④ 固定延迟执行
//    上次结束时间 + delay = 下次开始时间
public ScheduledFuture<?> scheduleWithFixedDelay(
    Runnable command, long initialDelay, long delay, TimeUnit unit);
```

### 12.5 固定速率 vs 固定延迟

```
scheduleAtFixedRate（period = 3s，任务执行 1s）：
  ├──执行1s──┤          ├──执行1s──┤          ├──执行1s──┤
  0          3          3          6          6          9
  ↑                     ↑                     ↑
  开始                  开始                  开始
  间隔固定 = period

scheduleAtFixedRate（period = 3s，任务执行 5s）：
  ├──────执行5s──────┤├──执行5s──┤
  0                   5           8
  ↑                               ↑
  开始                            立即开始（来不及等3s）

scheduleWithFixedDelay（delay = 2s，任务执行 1s）：
  ├──执行1s──┤   ├──执行1s──┤   ├──执行1s──┤
  0         1 3  4         5 7  8         9 11
  ↑              ↑              ↑
  开始           开始           开始
  间隔 = 执行时间 + delay
```

### 12.6 周期任务的重新入队

```java
// 在 run() 中，周期任务执行完后会重新设置 time 并入队
public void run() {
    boolean periodic = isPeriodic();
    if (!canRunInCurrentRunState(periodic))
        cancel(false);
    else if (!periodic)
        ScheduledFutureTask.super.run(); // 非周期任务，执行一次
    else if (ScheduledFutureTask.super.runAndReset()) { // 周期任务，执行并重置
        setNextRunTime();   // 设置下次执行时间
        reExecutePeriodic(outerTask); // 重新入队
    }
}
```

---

## 13. Executors 工厂方法与坑

### 13.1 六种常用线程池

```java
// ① FixedThreadPool —— 固定大小线程池
public static ExecutorService newFixedThreadPool(int nThreads) {
    return new ThreadPoolExecutor(nThreads, nThreads,
                                  0L, TimeUnit.MILLISECONDS,
                                  new LinkedBlockingQueue<Runnable>());
    // core = max，无超时回收
    // ⚠️ 队列无界（Integer.MAX_VALUE），可能 OOM！
}

// ② SingleThreadExecutor —— 单线程线程池
public static ExecutorService newSingleThreadExecutor() {
    return new FinalizableDelegatedExecutorService
        (new ThreadPoolExecutor(1, 1,
                                0L, TimeUnit.MILLISECONDS,
                                new LinkedBlockingQueue<Runnable>()));
    // core = max = 1，保证顺序执行
    // ⚠️ 队列无界，可能 OOM！
}

// ③ CachedThreadPool —— 缓存线程池
public static ExecutorService newCachedThreadPool() {
    return new ThreadPoolExecutor(0, Integer.MAX_VALUE,
                                  60L, TimeUnit.SECONDS,
                                  new SynchronousQueue<Runnable>());
    // core = 0, max = 无限
    // ⚠️ 线程数无上限，高并发下可能创建大量线程 → OOM！
}

// ④ ScheduledThreadPool —— 定时线程池
public static ScheduledExecutorService newScheduledThreadPool(int corePoolSize) {
    return new ScheduledThreadPoolExecutor(corePoolSize);
}

// ⑤ SingleThreadScheduledExecutor —— 单线程定时线程池
public static ScheduledExecutorService newSingleThreadScheduledExecutor() {
    return new DelegatedScheduledExecutorService(
        new ScheduledThreadPoolExecutor(1));
}

// ⑥ WorkStealingPool —— 工作窃取线程池（JDK 8+）
public static ExecutorService newWorkStealingPool() {
    return new ForkJoinPool(Runtime.getRuntime().availableProcessors(),
                            ForkJoinPool.defaultForkJoinWorkerThreadFactory,
                            null, true);
}
```

### 13.2 阿里巴巴 Java 开发手册的规约

> 【强制】线程池不允许使用 Executors 去创建，而是通过 ThreadPoolExecutor 的方式。

| 工厂方法 | 问题 | 替代方案 |
|----------|------|----------|
| newFixedThreadPool | 队列无界 → OOM | 自定义 ThreadPoolExecutor + 有界队列 |
| newSingleThreadExecutor | 队列无界 → OOM | 同上 |
| newCachedThreadPool | 线程数无上限 → OOM | 设置合理的 maximumPoolSize |

### 13.3 正确的自定义线程池姿势

```java
ThreadPoolExecutor executor = new ThreadPoolExecutor(
    4,                                    // corePoolSize
    8,                                    // maximumPoolSize
    60, TimeUnit.SECONDS,                 // keepAliveTime
    new ArrayBlockingQueue<>(100),         // 有界队列，容量100
    new ThreadFactory() {                  // 自定义线程工厂
        private final AtomicInteger counter = new AtomicInteger(0);
        @Override
        public Thread newThread(Runnable r) {
            return new Thread(r, "my-pool-" + counter.incrementAndGet());
        }
    },
    new ThreadPoolExecutor.CallerRunsPolicy() // 拒绝策略：调用者执行
);
```

---

## 14. 线程池调优实践

### 14.1 核心线程数设置

```
CPU 密集型任务（计算、加密、压缩等）：
  corePoolSize = CPU 核心数 + 1
  原因：+1 是为了在某个线程因页缺失等原因暂停时，仍能利用 CPU

IO 密集型任务（网络请求、数据库、文件读写等）：
  corePoolSize = CPU 核心数 × 2
  或更精确：corePoolSize = CPU 核心数 × (1 + IO等待时间/CPU计算时间)

混合型任务：
  拆分为 CPU 密集型和 IO 密集型两个线程池
```

### 14.2 队列选择

| 场景 | 推荐队列 | 原因 |
|------|----------|------|
| 任务量可控 | ArrayBlockingQueue | 有界，防止 OOM |
| 任务量波动大 | LinkedBlockingQueue | 设置合理容量 |
| 任务执行快、提交频繁 | SynchronousQueue | 直接交付，不排队 |
| 任务有优先级 | PriorityBlockingQueue | 按优先级排序 |

### 14.3 动态调参

```java
// 运行时动态调整核心线程数
executor.setCorePoolSize(newCoreSize);

// 运行时动态调整最大线程数
executor.setMaximumPoolSize(newMaxSize);

// 注意：新的 corePoolSize 如果比当前线程数大
// 会立即创建新线程来消费队列中的任务
public void setCorePoolSize(int corePoolSize) {
    if (corePoolSize < 0)
        throw new IllegalArgumentException();
    int delta = corePoolSize - this.corePoolSize;
    this.corePoolSize = corePoolSize;
    if (workerCountOf(ctl.get()) > corePoolSize)
        interruptIdleWorkers();     // 缩小：中断多余的空闲线程
    else if (delta > 0)
        // 增大：我们需要尽快启动新线程
        addWorker(null, true);
}
```

### 14.4 监控指标

```java
// 线程池监控常用方法
executor.getPoolSize();          // 当前线程数
executor.getActiveCount();       // 活跃线程数（正在执行任务的）
executor.getCorePoolSize();      // 核心线程数
executor.getMaximumPoolSize();   // 最大线程数
executor.getQueue().size();      // 队列中的任务数
executor.getQueue().remainingCapacity(); // 队列剩余容量
executor.getCompletedTaskCount(); // 已完成任务数
executor.getTaskCount();          // 总任务数（包括正在执行的）
executor.getLargestPoolSize();    // 历史最大线程数
```

---

## 15. JDK 版本演进对比

| 特性 | JDK 8 | JDK 9+ | JDK 17+ |
|------|-------|--------|---------|
| 核心实现 | ThreadPoolExecutor | 同 JDK 8 | 同 JDK 8 |
| 提交方式 | execute/submit | + CompletableFuture | 同 JDK 9 |
| 虚拟线程 | 无 | 无 | JDK 21+: Executors.newVirtualThreadPerTaskExecutor() |
| WorkStealingPool | ForkJoinPool | 同 JDK 8 | 同 JDK 8 |
| 关闭方法 | shutdown/shutdownNow | + close()（实现 AutoCloseable） | 同 JDK 9 |
| 优雅关闭 | 手写 | + executor.close() | 同 JDK 9 |
| Future | FutureTask | + CompletableFuture | 同 JDK 9 |

### JDK 9+ 的 close() 方法

```java
// JDK 9: ThreadPoolExecutor 实现了 AutoCloseable
try (var executor = Executors.newFixedThreadPool(4)) {
    executor.execute(task1);
    executor.execute(task2);
} // 自动调用 close()，等效于 shutdown() + awaitTermination()

// close() 的实现
public void close() {
    shutdown();
    boolean terminated = isTerminated();
    if (!terminated) {
        try {
            awaitTermination(Long.MAX_VALUE, TimeUnit.NANOSECONDS);
        } catch (InterruptedException e) {
            shutdownNow();
            Thread.currentThread().interrupt();
        }
    }
}
```

---

## 16. 常见面试题

### Q1: 线程池的 execute 和 submit 有什么区别？

| | execute | submit |
|---|---------|--------|
| 参数 | Runnable | Runnable / Callable |
| 返回值 | void | Future<?> / Future<T> |
| 异常处理 | 任务中的异常直接抛出 | 异常被 Future.get() 捕获，包装为 ExecutionException |
| 失败感知 | 不容易感知 | 通过 Future.get() 感知 |

```java
// execute：异常直接在 Worker 线程中抛出，任务静默失败
executor.execute(() -> { throw new RuntimeException("fail"); });

// submit：异常被封装在 Future 中
Future<?> future = executor.submit(() -> { throw new RuntimeException("fail"); });
try {
    future.get(); // 抛出 ExecutionException
} catch (ExecutionException e) {
    System.out.println(e.getCause()); // RuntimeException: fail
}
```

### Q2: 核心线程会被回收吗？

默认不会。核心线程通过 `workQueue.take()` 永久阻塞等待任务。

但如果设置 `allowCoreThreadTimeOut = true`，核心线程也会使用 `workQueue.poll(keepAliveTime)` 获取任务，超时后退出。

```java
executor.allowCoreThreadTimeOut(true);
```

### Q3: 线程池中抛出异常后，线程会怎样？

**任务抛出异常 → Worker 线程终止 → 线程池创建新线程补充**

```java
// runWorker 中的异常路径：
try {
    task.run();
} catch (RuntimeException x) {
    thrown = x; throw x;  // 异常向上抛
} finally {
    processWorkerExit(w, true);  // completedAbruptly = true
    // 补充新线程
}
```

**注意**：`execute()` 提交的任务，异常会在 Worker 线程中打印，但不会传播到调用者。`submit()` 的异常封装在 Future 中。

### Q4: 如何合理配置线程池参数？

```
1. 分析任务类型：CPU密集 or IO密集 or 混合
2. 分析任务量：每秒提交多少？每个任务执行多久？
3. 分析容忍度：能接受多少延迟？能丢弃任务吗？

公式参考：
  CPU密集型：corePoolSize = N_cpu + 1
  IO密集型：corePoolSize = N_cpu × 2（或 N_cpu × (1 + W/C)）

  N_cpu = Runtime.getRuntime().availableProcessors()
  W = 等待时间
  C = 计算时间

实践建议：
  - 先用公式估算，再通过压测调整
  - 使用有界队列，防止 OOM
  - 监控队列长度和活跃线程数
  - 考虑使用动态调参（美团的 DynamicTp 思路）
```

### Q5: 为什么要用线程池而不是每次 new Thread？

1. **降低资源消耗**：重复利用线程，避免频繁创建/销毁的开销
2. **提高响应速度**：任务到达时无需等线程创建，直接使用已有线程
3. **提高可管理性**：统一调优、监控、限流
4. **防止资源耗尽**：限制最大线程数，避免无限创建线程

### Q6: FixedThreadPool 的队列为什么是无界的？

设计意图是确保所有提交的任务都能被接受，不会丢失。但在实际生产中，无界队列是 OOM 的隐患——任务堆积时内存会被撑爆。生产环境务必使用有界队列。

### Q7: 线程池的 Worker 继承 AQS 而不是 ReentrantLock 的原因？

Worker 需要一个**不可重入**的独占锁：
- 可重入锁会导致 `interruptIdleWorkers()` 误判线程状态
- Worker 的锁仅用于标识"线程是否在执行任务"，不需要重入
- AQS 的轻量级实现比 ReentrantLock 更高效

### Q8: shutdownNow 之后，正在执行的任务会被立即停止吗？

不一定。`shutdownNow()` 调用 `t.interrupt()`，但：
- 如果任务不响应中断（如 CPU 密集计算不检查中断标志），任务会继续执行
- 如果任务在 `Thread.sleep()` / `Object.wait()` / 阻塞 IO 中，会收到 `InterruptedException`

**最佳实践**：任务内部应该定期检查 `Thread.interrupted()` 或正确处理 `InterruptedException`。

### Q9: 线程池中线程的创建顺序是什么？

1. 任务到来时，先创建核心线程（直到 corePoolSize）
2. 核心线程满了，任务进入队列
3. 队列满了，创建非核心线程（直到 maximumPoolSize）
4. 线程也满了，执行拒绝策略

### Q10: 如何实现线程池的动态调参？

```java
// 方案1：直接调用 set 方法
executor.setCorePoolSize(newCore);
executor.setMaximumPoolSize(newMax);

// 方案2：基于配置中心（Nacos / Apollo）
@NacosValue(value = "${thread.pool.core:4}", autoRefreshed = true)
private int corePoolSize;

@PostConstruct
public void init() {
    // 定期检查配置变化
    scheduledExecutor.scheduleAtFixedRate(() -> {
        if (executor.getCorePoolSize() != corePoolSize) {
            executor.setCorePoolSize(corePoolSize);
        }
    }, 0, 5, TimeUnit.SECONDS);
}

// 方案3：美团 DynamicTp 框架
// 参考文章：https://tech.meituan.com/2020/04/02/java-pooling-pratice-in-meituan.html
```

---

## 附录 A：submit 的实现原理

```java
// AbstractExecutorService.submit()
public Future<?> submit(Runnable task) {
    if (task == null) throw new NullPointerException();
    RunnableFuture<Void> ftask = newTaskFor(task, null); // 包装为 FutureTask
    execute(ftask);  // 仍然是调用 execute
    return ftask;
}

public <T> Future<T> submit(Callable<T> task) {
    if (task == null) throw new NullPointerException();
    RunnableFuture<T> ftask = newTaskFor(task); // Callable → FutureTask
    execute(ftask);
    return ftask;
}
```

**FutureTask 的状态机**：

```
NEW → COMPLETING → NORMAL       (正常完成)
                  → EXCEPTIONAL  (异常)
     → CANCELLED                 (取消)
     → INTERRUPTING → INTERRUPTED (中断)
```

## 附录 B：线程池相关 UML 类图

```
                    ┌──────────────────┐
                    │   Executor       │ ← 顶层接口
                    │  +execute(Runnable)│
                    └────────┬─────────┘
                             │ extends
                    ┌────────▼─────────┐
                    │ ExecutorService  │ ← 增加生命周期管理
                    │ +shutdown()      │
                    │ +submit()        │
                    └────────┬─────────┘
                             │ extends
              ┌──────────────▼───────────────┐
              │  AbstractExecutorService      │ ← submit 的默认实现
              └──────────────┬───────────────┘
                             │ extends
              ┌──────────────▼───────────────┐
              │   ThreadPoolExecutor          │ ← 核心实现
              │   +execute()                  │
              │   +addWorker()                │
              │   +runWorker()                │
              └──────────────┬───────────────┘
                             │ extends
              ┌──────────────▼───────────────┐
              │ ScheduledThreadPoolExecutor   │ ← 定时/周期任务
              │ +schedule()                   │
              │ +scheduleAtFixedRate()        │
              │ +scheduleWithFixedDelay()     │
              └──────────────────────────────┘
```

## 附录 C：线程池参数速查表

| 参数 | 含义 | 建议 |
|------|------|------|
| corePoolSize | 核心线程数 | CPU密集: N+1; IO密集: 2N |
| maximumPoolSize | 最大线程数 | 按峰值设置，不宜过大 |
| keepAliveTime | 非核心线程存活时间 | 60s（默认够用） |
| unit | 时间单位 | TimeUnit.SECONDS |
| workQueue | 任务队列 | 必须有界！ |
| threadFactory | 线程工厂 | 自定义命名 |
| handler | 拒绝策略 | CallerRunsPolicy（推荐） |

---

> 本文档基于 JDK 8 源码整理，重点讲解 ctl 状态控制、execute 三层递进策略、Worker 不可重入锁设计、线程回收机制、多线程扩容协助等核心设计。
> 建议配合实际调试，在 execute、addWorker、runWorker、getTask 打断点，观察任务提交和线程回收的全过程。
