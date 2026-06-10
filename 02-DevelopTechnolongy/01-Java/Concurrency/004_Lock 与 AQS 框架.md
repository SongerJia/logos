AQS 核心原理 CLH 变体队列

热ReentrantLock 公平/非公平实现

热synchronized vs ReentrantLock 对比

热ReentrantReadWriteLock

核Condition await/signal 原理

LockSupport park/unpark

StampedLock 乐观读模式

tryLock 超时与非阻塞获取

共享模式 vs 独占模式

acquire/release 完整流程



| #     | 知识点                          | 重要度 | 三层笔记建议                                                                                                                                                                          | 面试追问                                                | FlowPulse 结合                  |
| ----- | ---------------------------- | --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | ----------------------------- |
| B2-14 | **AQS 核心思想与数据结构**            | ★★★ | L1: state volatile int + CLH双向队列(Node prev/next/waitStatus/thread)；L2: 独占模式(ReentrantLock) vs 共享模式(Semaphore/CountDownLatch)；L3: 模板方法模式：子类只需实现tryAcquire/tryRelease等protected方法 | AQS的CLH队列和原始CLH有什么区别？state的设计巧妙之处？                  | 理解所有JUC锁的基础                   |
| B2-15 | **ReentrantLock 公平 vs 非公平锁** | ★★★ | L1: FairSync(检查是否有前驱节点) vs NonfairSync(直接CAS抢锁)；L2: 非公平锁性能更好(减少上下文切换)，但可能饥饿；L3: hasQueuedPredecessors()公平性检查的实现                                                                 | 非公平锁一定不公平吗？什么情况下非公平锁也会排队？                           | FlowPulse分布式锁本地竞争时选非公平(性能优先)  |
| B2-16 | **ReentrantLock 可重入原理**      | ★★★ | L1: 通过state计数实现可重入——同一线程多次获取lock则state++；L2: release时每释放一次state--直到0才真正释放锁；L3: getHoldCount()/isHeldByCurrentThread()查询当前持有次数                                                   | 可重入有什么好处？如果不用可重入会发生死锁吗？举例                           | 流程嵌套调用同一把锁的场景                 |
| B2-17 | **Condition 条件变量**           | ★★☆ | L1: await()释放锁进入条件队列，signal()唤醒后重新抢锁；L2: ReentrantLock支持多Condition(比synchronized的单一wait/notify灵活)；L3: ArrayBlockingQueue中put/takeCondition的使用模式                                 | Condition.await和Object.wait的区别？signalAll vs signal？ | 流程引擎的生产者-消费者模式(任务队列)          |
| B2-18 | **ReadWriteLock 读写锁**        | ★★☆ | L1: ReadWriteLock接口(读共享/写独占)；L2: ReentrantReadWriteLock实现：读锁(state高16位) + 写锁(state低16位)；L3: 锁降级(写锁→读锁合法) vs 锁升级(读锁→写锁会导致死锁)                                                     | 为什么不能锁升级？读写锁适用于什么比例的读写场景？                           | 流程模板定义缓存(多读少写)适用ReadWriteLock |
| B2-19 | **AQS 中断响应方式**               | ★☆☆ | L1: acquire/acquireInterruptibly(响应中断)/tryAcquireNanos(超时可中断)；L2: 中断后在CLH队列中将Node标记CANCELLED；L3: shouldParkAfterFailedAcquire中的中断检查逻辑                                           | lockInterruptibly()和lock()的区别？park时收到中断信号怎么办？       | 可中断的工作流锁获取                    |