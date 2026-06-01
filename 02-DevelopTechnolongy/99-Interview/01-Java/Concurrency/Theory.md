---
title: Java 并发面试理论
tags:
  - Java
  - Interview
---

## 一、volatile & JMM（基础中的基础）

> **Q1** `volatile` 的两大语义是什么？它是怎么保证可见性的？（提示：内存屏障、MESI 缓存一致性协议）

> **Q2** `volatile` 能保证原子性吗？`volatile int count = 0`，10 个线程各 `count++` 1000 次，最终结果是多少？为什么？

> **Q3** DCL（双重检查锁定）单例中，`instance` 为什么要加 `volatile`？不加会有什么问题？

> **Q4** JMM 的 `happens-before` 规则有哪些？`volatile` 写和读之间满足什么 happens-before 关系？写一个用 volatile 做"开关"的线程间通信示例。

---

## 二、synchronized & 锁升级（必问源码级）

> **Q5** `synchronized` 锁的对象到底存在哪里？对象头的 Mark Word 在不同锁状态下分别存什么内容？

> **Q6** `synchronized` 的锁升级过程：无锁 → 偏向锁 → 轻量级锁 → 重量级锁，每次升级的触发条件是什么？

> **Q7** 偏向锁在 JDK15 被默认关闭、JDK18 被标记废弃，为什么？偏向锁有什么性能问题？

> **Q8** `synchronized` 修饰普通方法和静态方法，锁的对象分别是什么？两个同步方法之间会互斥吗？

---

## 三、Lock & AQS（高级必问）

> **Q9** `synchronized` 和 `ReentrantLock` 的区别，至少说 5 点。JDK6 之后 `synchronized` 性能大幅优化了，什么场景还推荐用 `ReentrantLock`？

> **Q10** AQS 的核心数据结构是什么？`state` 字段在不同锁实现中分别代表什么？（`ReentrantLock`、`CountDownLatch`、`Semaphore`）

> **Q11** AQS 的独占模式和共享模式有什么区别？`acquire()` 和 `acquireShared()` 的流程对比。

> **Q12** `ReentrantLock` 的公平锁和非公平锁在 AQS 层面实现的区别？非公平锁"插队"发生在哪里？

> **Q13** `ReentrantReadWriteLock` 的读写锁怎么实现的？读锁可以升级为写锁吗？写锁可以降级为读锁吗？

> **Q14** `StampedLock` 相比 `ReentrantReadWriteLock` 有什么改进？乐观读锁 `tryOptimisticRead()` 怎么用的？有什么坑？

---

## 四、CAS & Atomic（原理必修）

> **Q15** CAS 的底层是怎么实现的？（`Unsafe.compareAndSwapInt` → CPU `cmpxchg` 指令 → `lock` 前缀锁定总线/缓存行）

> **Q16** CAS 的 ABA 问题是什么？`AtomicStampedReference` 和 `AtomicMarkableReference` 分别怎么解决？各自的区别？

> **Q17** `AtomicLong` 和 `LongAdder` 的区别？为什么高并发下 `LongAdder` 性能更好？`Cell` 数组的扩容机制？

---

## 五、线程池（实际项目最常用）

> **Q18** 线程池的 7 个核心参数是什么？从提交任务到执行的完整流程说清楚。

> **Q19** 4 种拒绝策略分别是什么？`CallerRunsPolicy` 有什么风险？你在项目中用什么策略？

> **Q20** 为什么不推荐用 `Executors` 创建线程池？`newFixedThreadPool` 和 `newCachedThreadPool` 各自的 OOM 风险在哪里？

> **Q21** 线程池的线程是如何实现复用的？`Worker` 的内部 `runWorker()` 方法里做了什么？（`getTask` → `while` 循环 → `beforeExecute` → `task.run()` → `afterExecute`）

> **Q22** 线程池的 `corePoolSize` 设为 0 会怎样？`keepAliveTime` 设为 0 呢？`allowCoreThreadTimeOut(true)` 的作用？

> **Q23** 线上线程池突然大量拒绝任务，你怎么排查？可能的原因有哪些？

---

## 六、ThreadLocal（经典内存泄漏考点）

> **Q24** `ThreadLocal` 的底层数据结构是怎样的？为什么 `ThreadLocalMap` 的 Key 用弱引用？

> **Q25** `ThreadLocal` 内存泄漏的原因？Key（弱引用）被 GC 后，Value 为什么还在？`remove()` 方法为什么必须调用？

> **Q26** 线程池中使用 `ThreadLocal` 有什么额外风险？怎么解决？（线程复用导致上次请求的 ThreadLocal 残留）

> **Q27** `InheritableThreadLocal` 是做什么的？线程池场景下它能正常工作吗？`TransmittableThreadLocal`（阿里开源）解决了什么？

---

## 七、并发工具类

> **Q28** `CountDownLatch` 和 `CyclicBarrier` 的区别？（使用次数、计数方向、等待线程角色三个维度）

> **Q29** `Semaphore` 的 `acquire()` 和 `release()` 底层是怎么用 AQS 共享模式实现的？如果你用 Semaphore 做限流，怎么设计？

> **Q30** `Exchanger` 做什么用的？用过吗？`Phaser` 相比 `CyclicBarrier` 有什么优势？

---

## 八、CompletableFuture（现代异步编程）

> **Q31** `Future` 的局限性是什么？`CompletableFuture` 解决了什么问题？

> **Q32** `thenApply()`、`thenAccept()`、`thenRun()` 的区别？`thenCompose()` 和 `thenCombine()` 分别用于什么场景？

> **Q33** `CompletableFuture.allOf()` 返回的是什么？如何获取 `allOf` 之后所有任务的结果？

> **Q34** `CompletableFuture` 默认用的是什么线程池？为什么生产环境不推荐用默认的 `ForkJoinPool.commonPool()`？

> **Q35** `CompletableFuture` 的 `completeExceptionally()` 和 `handle()` / `exceptionally()` 有什么区别？异常传播链是怎样的？

---

## 九、并发容器

> **Q36** `ConcurrentHashMap` 的 `computeIfAbsent()` 方法内部是怎么保证原子性的？为什么不能在里面做耗时操作？

> **Q37** `ConcurrentLinkedQueue` 是怎么实现无锁的？CAS 操作的是哪个字段？和 `LinkedBlockingQueue` 的使用场景有什么区别？

> **Q38** `CopyOnWriteArrayList` 的迭代器为什么不需要加锁就能保证不抛 `ConcurrentModificationException`？但是它读到的一定是最新数据吗？

---

## 十、虚拟线程 & 现代并发（JDK21 拉开分差）

> **Q39** 虚拟线程（Virtual Thread）是什么？和平台线程（Platform Thread）的本质区别？它是怎么实现"一个 OS 线程承载多个虚拟线程"的？

> **Q40** 虚拟线程适合什么场景，不适合什么场景？为什么不要在虚拟线程里用 `synchronized` 做长时间持锁？

> **Q41** 结构化并发（Structured Concurrency，JDK21 预览）的核心思想是什么？`StructuredTaskScope` 和 `ExecutorService` 的区别？

---

## 十一、实战场景

> **Q42** 设计一个"多线程批量处理 100 万条数据"的方案。要求：分批拉取、并行处理、结果汇总、支持中断、异常重试。说出你的技术选型和关键代码结构。
