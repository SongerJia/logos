---
title: Java 并发面试理论_答案版
tags:
  - Java
  - Interview-answer
---
#flashcards/Java/concurrency/theory 
## 一、volatile & JMM（基础中的基础）

### **Q1** `volatile` 的两大语义是什么？它是怎么保证可见性的？（提示：内存屏障、MESI 缓存一致性协议）
?
volatile 有两大语义：第一是保证可见性，第二是禁止指令重排序。可见性怎么保证的呢？从 JVM 层面看，volatile 变量的写操作前后会插入内存屏障——写之前加 StoreStore 屏障，写之后加 StoreLoad 屏障——确保写入的值立即刷新到主内存，并且让其他线程能读到最新值。从硬件层面看，内存屏障最终会触发 CPU 的 lock 前缀指令，lock 前缀会导致缓存行失效，触发 MESI 协议的缓存一致性流量，其他 CPU 核心发现自己缓存的那个缓存行被标记为 Invalid 了，下次读取就必须从主内存重新加载。所以 volatile 的可见性实际上是一个从 JVM 内存屏障到 CPU 缓存一致性协议的完整链路。

### **Q2** `volatile` 能保证原子性吗？`volatile int count = 0`，10 个线程各 `count++` 1000 次，最终结果是多少？为什么？
?
volatile 不能保证原子性。count++ 实际上是三个操作：读取 count 的当前值、加一、写回。volatile 只能保证每次读到的都是最新的值，但不能保证这三个操作之间不被其他线程打断。举个例子，线程 A 读到 count=5，还没执行加一操作，线程 B 也读到 count=5，然后两个线程各自加一写回 6。本来应该加两次变成 7，结果只加了一次。所以 10 个线程各执行 1000 次 count++，最终结果一定小于 10000，通常在几千到九千多之间，每次运行结果还不一样。要保证原子性，应该用 AtomicInteger 或者 synchronized。

### **Q3** DCL（双重检查锁定）单例中，`instance` 为什么要加 `volatile`？不加会有什么问题？
?
双重检查锁定单例的核心是两次判空加同步块。如果不加 volatile，问题出在指令重排序上。new 一个对象在 JVM 层面不是原子操作，大致分三步：分配内存空间、初始化对象、把引用指向内存空间。第二步和第三步可能被重排序，如果引用先指向了内存空间但对象还没初始化完，另一个线程在第一次判空时发现引用不为 null，直接返回了一个半成品对象去用，就会出现空指针或者状态不一致的问题。加上 volatile 之后，volatile 写操作后面的 StoreLoad 屏障禁止了第二步和第三步的重排序，保证对象完全初始化之后引用才对其他线程可见。

### **Q4** JMM 的 `happens-before` 规则有哪些？`volatile` 写和读之间满足什么 happens-before 关系？写一个用 volatile 做"开关"的线程间通信示例。
?
1. happens-before 规则主要有这么几条：程序次序规则，同一个线程内前面的操作 happens-before 后面的操作；volatile 变量规则，对一个 volatile 变量的写 happens-before 后续对这个变量的读；锁规则，解锁 happens-before 后续的加锁；线程启动规则，start 方法 happens-before 线程内的任何操作；线程终止规则，线程内的所有操作 happens-before join 返回；传递性规则，如果 A happens-before B，B happens-before C，那么 A happens-before C。
2. volatile 写和读之间满足的是：对一个 volatile 变量的写操作 happens-before 后续任意线程对这个变量的读操作。这意味着写线程在写 volatile 变量之前的所有操作，对读线程在读到这个 volatile 变量之后都是可见的。这也就是为什么 volatile 能当线程间通信的开关用。
3. 典型的开关模式：一个工作线程用一个 while 循环判断 volatile boolean 变量，主线程在某个时刻把这个变量设为 false，工作线程下一次循环就能看到变化并退出。因为 volatile 的 happens-before 关系保证了主线程设 false 之前的所有操作，对工作线程读到 false 之后都是可见的，不需要额外加锁。

---

## 二、synchronized & 锁升级（必问源码级）

### **Q5** `synchronized` 锁的对象到底存在哪里？对象头的 Mark Word 在不同锁状态下分别存什么内容？
?
synchronized 锁信息存在 Java 对象头的 Mark Word 里。每个 Java 对象在堆内存中都有一个对象头，其中 Mark Word 部分根据锁状态的不同存放不同的内容。无锁状态下，Mark Word 存的是对象的 hashCode、分代年龄、是否偏向锁的标志位。偏向锁状态下，存的是持有偏向锁的线程 ID、Epoch、分代年龄。轻量级锁状态下，存的是指向当前线程栈中 Lock Record 的指针。重量级锁状态下，存的是指向操作系统互斥量的指针。不同状态通过 Mark Word 最后几位的锁标志位来区分：无锁是 01，偏向锁也是 01 但前面有偏向标记，轻量级锁是 00，重量级锁是 10。

### **Q6** `synchronized` 的锁升级过程：无锁 → 偏向锁 → 轻量级锁 → 重量级锁，每次升级的触发条件是什么？
?
1. 无锁到偏向锁：当第一个线程访问同步块时，JVM 会在 Mark Word 中记录这个线程的 ID，并把偏向标志设为 1，锁就进入了偏向锁状态。这个过程的触发条件是当前没有其他线程竞争。
2. 偏向锁到轻量级锁：当第二个线程尝试获取这个偏向锁时，JVM 会检查 Mark Word 中的线程 ID。发现不是自己持有，说明出现了竞争。这时候 JVM 会暂停持有偏向锁的线程，检查它是否还在同步块内。如果已经退出了，就把偏向锁撤销，升级到轻量级锁。轻量级锁的本质是自旋 CAS 竞争，每个线程在自己的栈帧中创建 Lock Record，通过 CAS 尝试把 Mark Word 替换为指向自己 Lock Record 的指针。
3. 轻量级锁到重量级锁：当一个线程自旋了多次仍然抢不到锁，或者同时有超过一个线程在自旋等待，JVM 认为竞争激烈，就会把锁膨胀为重量级锁。重量级锁会调用操作系统的互斥量，线程进入阻塞状态，让出 CPU。这个升级是不可逆的，一旦升到重量级锁就不会退回去了。

### **Q7** 偏向锁在 JDK15 被默认关闭、JDK18 被标记废弃，为什么？偏向锁有什么性能问题？
?
偏向锁的设计初衷是优化单线程重复获取锁的场景，省掉 CAS 操作的开销。但它在高并发场景下反而成为性能负担。原因有两点。第一，偏向锁的撤销需要在安全点暂停持有偏向锁的线程，这个暂停操作本身开销不小，而且会拖慢所有线程。第二，现代应用大量使用线程池，线程不断复用，一个锁被不同线程获取的概率很高，偏向锁频繁撤销再升级，额外开销完全抵消了它带来的收益。加上 JDK6 之后轻量级锁的自旋优化已经足够快，偏向锁就成了一个弊大于利的设计，所以 JDK15 开始默认关闭，JDK18 直接废弃了。

### **Q8** `synchronized` 修饰普通方法和静态方法，锁的对象分别是什么？两个同步方法之间会互斥吗？
?
synchronized 修饰普通方法时，锁的是当前实例对象，也就是 this。修饰静态方法时，锁的是这个类的 Class 对象。两个普通同步方法之间会互斥，因为它们争的是同一把实例锁。普通同步方法和静态同步方法之间不会互斥，因为它们锁的是不同的对象——一个锁实例，一个锁 Class，根本不在一个竞争维度上。两个静态同步方法之间又会互斥，因为它们锁的是同一个 Class 对象。

---

## 三、Lock & AQS（高级必问）

### **Q9** `synchronized` 和 `ReentrantLock` 的区别，至少说 5 点。JDK6 之后 `synchronized` 性能大幅优化了，什么场景还推荐用 `ReentrantLock`？
?
1. 可以从这几个方面来说。第一，synchronized 是 JVM 层面的关键字，ReentrantLock 是 JDK 层面的类。第二，synchronized 不需要手动释放锁，出了同步块自动释放，ReentrantLock 必须在 finally 里手动 unlock，否则会死锁。第三，ReentrantLock 支持公平锁和非公平锁，synchronized 只能是非公平的。第四，ReentrantLock 提供了 tryLock 方法，可以尝试获取锁并指定超时时间，synchronized 只能一直阻塞等。第五，ReentrantLock 可以通过 newCondition 创建多个条件队列，实现精确的线程唤醒，synchronized 只有一个隐式的 wait/notify 条件队列。
2. JDK6 之后 synchronized 确实做了大量优化，锁升级机制让它在大多数场景下性能和 ReentrantLock 差不多。但需要高级特性的时候还是得用 ReentrantLock，比如需要尝试获取锁并设置超时的场景、需要公平锁的场景、需要多个条件变量的场景，以及需要知道锁是否被持有的监控场景。

### **Q10** AQS 的核心数据结构是什么？`state` 字段在不同锁实现中分别代表什么？（`ReentrantLock`、`CountDownLatch`、`Semaphore`）
?
1. AQS 的核心数据结构就是一个用 volatile 修饰的 int 类型 state 字段，加上一个 CLH 变体的双向链表等待队列。state 表示同步状态，通过 CAS 来修改。等待队列中的每个节点代表一个等待获取锁的线程。
2. state 在不同实现中的含义不同。在 ReentrantLock 中，state 等于 0 表示锁未被持有，等于 1 表示被持有了，如果同一个线程重入多次，state 会递增，释放时递减，到 0 才真正释放锁。在 CountDownLatch 中，state 就是构造函数传入的倒计数值，每次 countDown 把 state 减 1，减到 0 时所有等待线程被唤醒。在 Semaphore 中，state 代表剩余可用的许可数量，acquire 时减一，release 时加一。

### **Q11** AQS 的独占模式和共享模式有什么区别？`acquire()` 和 `acquireShared()` 的流程对比。
?
1. 独占模式下，同一时刻只有一个线程能获取到同步状态，比如 ReentrantLock。共享模式下，多个线程可以同时获取同步状态，比如 Semaphore 和 CountDownLatch。
2. acquire 的流程是：先调用 tryAcquire 尝试获取锁，如果获取成功就返回；失败了就把当前线程包装成独占模式的 Node 节点，加入等待队列尾部，然后调用 acquireQueued，在队列里自旋或阻塞，等前驱节点释放锁后唤醒它。
3. acquireShared 的流程类似但关键区别在唤醒环节：先调用 tryAcquireShared 尝试获取共享资源，返回值大于等于 0 表示成功，否则把当前线程包装成共享模式的 Node 加入队列。当共享模式节点被唤醒获得资源后，它不只会唤醒后继节点，还会向后传播，只要后继节点也是共享模式的，就可以连锁唤醒。这个传播机制是共享模式和独占模式最核心的区别。

### **Q12** `ReentrantLock` 的公平锁和非公平锁在 AQS 层面实现的区别？非公平锁"插队"发生在哪里？
?
1. 区别就在 tryAcquire 的实现上。公平锁在尝试获取锁之前，会先调用 hasQueuedPredecessors 检查等待队列里有没有比自己更早的线程在排队。如果有，哪怕锁当前是空闲的，公平锁也不会去抢，老老实实去排队。非公平锁上来就直接 CAS 抢锁，不管队列里有没有人等。
2. 非公平锁的两次插队机会。第一次是在调用 lock 方法时，直接 CAS 尝试把 state 从 0 改成 1，这是最直接的插队。如果第一次 CAS 失败了，进入 acquire 方法，里面又会调用一次 tryAcquire，再次尝试抢锁，这是第二次插队机会。两次都失败之后，才老老实实加入等待队列排队。所以非公平锁的高性能就来自这两次插队减少了线程切换的开销。

### **Q13** `ReentrantReadWriteLock` 的读写锁怎么实现的？读锁可以升级为写锁吗？写锁可以降级为读锁吗？
?
1. ReentrantReadWriteLock 用一个 state 字段同时管理读锁和写锁的状态。state 的高 16 位表示读锁的持有计数，低 16 位表示写锁的重入次数。写锁是独占模式，和 ReentrantLock 的逻辑类似。读锁是共享模式，多个读线程可以同时获取，但每次获取读锁前都要检查是否有写线程在持有锁，有的话读线程就得排队等。
2. 读锁不能升级为写锁。如果一个线程先持有读锁，然后再尝试获取写锁，就会死锁。因为写锁要求所有读锁都释放才能获取，而这个线程自己就持有一个读锁，形成了一个自己等着自己释放的循环等待。
3. 写锁可以降级为读锁，而且这是推荐做法。一个线程持有写锁的时候，可以再获取读锁，然后释放写锁，这样就从写锁降级为了读锁。这个机制保证了在写操作完成之后、释放锁之前，还没有任何其他线程能执行写操作，读到的数据一定是最新的，实现了数据的一致性保证。

### **Q14** `StampedLock` 相比 `ReentrantReadWriteLock` 有什么改进？乐观读锁 `tryOptimisticRead()` 怎么用的？有什么坑？
?
1. StampedLock 最大的改进就是引入了乐观读模式。ReentrantReadWriteLock 的读锁虽然允许多个线程同时持有，但读锁本身也有开销——写线程要等所有读锁释放。StampedLock 的乐观读不阻塞写线程，它不实际加锁，只是获取一个版本号 stamp，读完数据之后用 validate 方法验证 stamp 是否还有效。如果有效，说明期间没有写操作，读到的数据一致；如果无效，需要升级为悲观读锁重读。
2. 使用方式就是三步：先调用 tryOptimisticRead 拿到 stamp，然后读取共享数据，最后调用 validate 检查 stamp。如果返回 true 说明数据一致，直接用；返回 false 说明读的过程中有写线程修改了数据，需要获取悲观读锁重新读取。
3. StampedLock 的坑主要有两个。第一，它不是可重入的，一个线程不能重复获取同一个锁，否则会死锁。第二，它没有 Condition 支持，无法做条件等待。另外如果使用不当，比如拿到 stamp 之后做了很耗时的操作再 validate，中间有写操作的概率就很大，乐观读就失去了意义。

---

## 四、CAS & Atomic（原理必修）

### **Q15** CAS 的底层是怎么实现的？（`Unsafe.compareAndSwapInt` → CPU `cmpxchg` 指令 → `lock` 前缀锁定总线/缓存行）
?
CAS 的全链路是这样的。Java 层面调用 Unsafe 类的 compareAndSwapInt 方法，这是一个 native 方法，它最终调用到 CPU 的 cmpxchg 指令。cmpxchg 的语义是：比较内存位置的值和期望值，如果相等就替换为新值，返回旧值。在多核 CPU 上，光靠 cmpxchg 不够，还要加 lock 前缀。lock 前缀的作用是保证这条指令的原子性和可见性——在早期的 CPU 上，lock 前缀会锁定整个总线，阻止其他 CPU 访问内存；现代 CPU 上，lock 前缀采用缓存锁定，只锁定被修改的那条缓存行，通过 MESI 协议让其他 CPU 的缓存行失效。所以整个 CAS 的底层链路就是 Java Unsafe → JNI → CPU cmpxchg+lock → 缓存行锁定。

### **Q16** CAS 的 ABA 问题是什么？`AtomicStampedReference` 和 `AtomicMarkableReference` 分别怎么解决？各自的区别？
?
1. ABA 问题是 CAS 操作的经典缺陷。线程 1 读到变量 A，准备 CAS 改成 C。但在这个时间窗口内，线程 2 把 A 改成了 B，又改回了 A。线程 1 的 CAS 操作看到还是 A，认为没变化，就成功更新了，但实际中间发生过状态变更。在一些场景下这会造成问题，比如链表的头结点被移除后又重新入栈了同一个节点。
2. AtomicStampedReference 通过加一个版本号来解决 ABA 问题。每次更新不仅比较引用值，还比较版本号，引用和版本号都匹配才更新，更新时版本号加一。AtomicMarkableReference 是简化版，它只用一个布尔标记来记录是否被修改过，不关心修改了几次。
3. 两者的区别在于，AtomicStampedReference 关心修改的次数，适用于需要知道"改了多少次"的场景；AtomicMarkableReference 只关心"有没有改过"，适用于只需要一个脏标记的简单场景。

### **Q17** `AtomicLong` 和 `LongAdder` 的区别？为什么高并发下 `LongAdder` 性能更好？`Cell` 数组的扩容机制？
?
1. AtomicLong 底层就是一个 volatile long，所有线程通过 CAS 自旋去修改同一个变量。高并发下，大量线程同时 CAS 竞争同一个内存地址，只有一个线程能成功，其他全部自旋重试，CPU 开销巨大，性能急剧下降。
2. LongAdder 的设计思路是空间换时间，把热点分散。它内部维护一个 base 值和一个 Cell 数组，每个 Cell 里放一个 long。线程更新时先尝试 CAS 更新 base，如果失败了就通过线程的 probe 值哈希到一个 Cell，对这个 Cell 里的值做 CAS。这样竞争就从原来的一个热点分散到了多个热点上，高并发下冲突概率大大降低。
3. Cell 数组的扩容机制是这样的。初始是长度为 2 的数组，当发生 CAS 冲突时，LongAdder 通过一个冲突计数器来判断竞争是否激烈。如果某个 Cell 上的 CAS 连续失败，就会先尝试扩容，把数组长度翻倍，让线程分散到更多 Cell 上。扩容的上限是 CPU 核心数，因为超过核心数再扩也没意义了。获取值时，把 base 和所有 Cell 的值累加起来就是最终结果。

---

## 五、线程池（实际项目最常用）

### **Q18** 线程池的 7 个核心参数是什么？从提交任务到执行的完整流程说清楚。
?
1. 七个参数分别是 corePoolSize 核心线程数、maximumPoolSize 最大线程数、keepAliveTime 空闲线程存活时间、unit 时间单位、workQueue 工作队列、threadFactory 线程工厂、handler 拒绝策略。
2. 提交任务的执行流程是这样的。一个任务提交进来，先判断核心线程是否已满。不满的话直接创建核心线程执行任务。核心线程满了，任务会被放入工作队列排队。如果工作队列也满了，检查当前线程数是否达到最大线程数，没到就创建非核心线程来执行任务。如果达到了最大线程数，执行拒绝策略。整个流程就是 核心线程 → 队列 → 最大线程 → 拒绝 这个顺序。

### **Q19** 4 种拒绝策略分别是什么？`CallerRunsPolicy` 有什么风险？你在项目中用什么策略？
?
1. AbortPolicy 是默认策略，直接抛出 RejectedExecutionException 异常。CallerRunsPolicy 让提交任务的线程自己来执行这个任务，相当于把压力反推给调用方。DiscardPolicy 直接丢弃任务，什么也不做，不抛异常。DiscardOldestPolicy 丢弃队列里最老的那个任务，然后尝试重新提交当前任务。
2. CallerRunsPolicy 的风险在于：如果提交任务的线程是主线程或者关键线程，在队列满的时候主线程去执行任务，就无法继续提交新任务了，可能会拖慢整个调用链。而且它只是把压力转移了，并没有从根本上解决任务堆积的问题。
3. 我在项目中的策略看场景。一般用默认的 AbortPolicy，出问题了能及时发现，配合监控告警快速响应。如果场景允许丢弃一些非关键任务，会用 DiscardOldestPolicy。对核心链路的服务，我会在拒绝策略里加上告警，而不是默默丢弃。

### **Q20** 为什么不推荐用 `Executors` 创建线程池？`newFixedThreadPool` 和 `newCachedThreadPool` 各自的 OOM 风险在哪里？
?
1. 不推荐用 Executors 的原因是它创建的线程池在极端情况下容易 OOM，而且参数是默认的，不够透明。
2. newFixedThreadPool 的问题是它用的工作队列是 LinkedBlockingQueue，默认容量是 Integer.MAX_VALUE，几乎可以认为是无界的。如果任务提交速度远大于执行速度，队列会不断堆积，最终撑爆堆内存，导致 OOM。
3. newCachedThreadPool 的问题是它的最大线程数是 Integer.MAX_VALUE，队列是 SynchronousQueue。SynchronousQueue 不存储任务，每来一个任务如果没有空闲线程就创建新线程。如果任务提交速度很快，线程数会爆炸式增长，每个线程默认需要 1MB 左右的栈内存，大量线程很快就把内存耗光了，也会 OOM。
4. 正确的做法是用 ThreadPoolExecutor 自己指定参数，队列用有界的比如 ArrayBlockingQueue 或设置了容量的 LinkedBlockingQueue，明确控制住资源上限。

### **Q21** 线程池的线程是如何实现复用的？`Worker` 的内部 `runWorker()` 方法里做了什么？（`getTask` → `while` 循环 → `beforeExecute` → `task.run()` → `afterExecute`）
?
线程复用的核心在 Worker 类和 runWorker 方法里。Worker 本身是一个 Runnable，创建时把自己封装成一个线程。它的 runWorker 方法里是一个 while 循环，循环体里不断调用 getTask 从工作队列里取任务。getTask 会阻塞等待，取到任务后，执行 beforeExecute 钩子，然后调用 task.run() 执行任务，再执行 afterExecute 钩子。任务执行完后又回到循环开头，继续去队列里取下一个任务。只要 getTask 能取到任务或者线程还在存活时间内，这个 while 循环就不会退出，线程就不会销毁。这就是线程池线程复用——一个线程不停地从队列里拿任务执行，而不是执行完一个任务就死掉。

### **Q22** 线程池的 `corePoolSize` 设为 0 会怎样？`keepAliveTime` 设为 0 呢？`allowCoreThreadTimeOut(true)` 的作用？
?
1. corePoolSize 设为 0，意味着没有核心线程，所有线程都是非核心线程。如果没有任务，线程池里将没有任何线程存活，完全空闲。一旦有任务提交，线程池会先尝试放入队列（如果队列是空的），发现放不进去或者队列也满了，才会创建线程来执行。这个配置适合那种偶尔有任务、大部分时间空闲的场景，目的是不浪费线程资源。
2. keepAliveTime 设为 0，理论上意味着非核心线程在空闲时会立即被回收。但实际上代码里做了保护，如果队列里有任务在等，线程还是会继续活着去处理队列里的任务。
3. allowCoreThreadTimeOut(true) 的作用是让核心线程也会因为空闲而被回收。默认情况下核心线程一旦创建就不会销毁，开了这个参数后，核心线程在 keepAliveTime 时间内没有任务也会被回收，效果类似 corePoolSize 变成 0。这个参数可以用来让线程池在低负载时自动缩容到零，极致地节省资源。

### **Q23** 线上线程池突然大量拒绝任务，你怎么排查？可能的原因有哪些？
?
1. 大量拒绝说明线程池被打满了。排查思路分三步。第一步，先看监控，确认是业务流量上涨还是下游响应变慢导致的。如果 QPS 正常，大概率是下游问题。第二步，看线程池的活跃线程数、队列积压量、任务平均执行时间的趋势。如果活跃线程数已经顶到最大线程数，而且队列持续堆积，说明任务执行变慢了，线程来不及消化。第三步，顺着任务执行变慢这条线去查——是不是下游接口响应时间变长了？是不是依赖的数据库慢查询变多了？是不是发生了 GC 停顿？
2. 可能的原因有这几个。一是上游流量突增，超过了线程池的处理能力。二是下游服务响应变慢，线程全卡在等待下游返回上，新的任务进不来。三是线程池参数配置不合理，核心线程数和最大线程数设得太小。四是某个任务执行特别慢或者死循环了，长时间占着线程不释放，慢慢把其他正常任务也拖死了。五是服务器的 CPU 或内存资源不足，线程调度和 GC 开销增大，导致整体处理能力下降。

---

## 六、ThreadLocal（经典内存泄漏考点）

### **Q24** `ThreadLocal` 的底层数据结构是怎样的？为什么 `ThreadLocalMap` 的 Key 用弱引用？
?
1. 每个 Thread 对象内部都有一个 ThreadLocalMap，ThreadLocalMap 是 ThreadLocal 的静态内部类。它的 Entry 数组用来存储数据，每个 Entry 的 Key 是 ThreadLocal 对象的弱引用，Value 是存储的值。当调用 ThreadLocal 的 get 方法时，先获取当前线程，再拿到当前线程的 ThreadLocalMap，然后用当前 ThreadLocal 对象作为 key 去查找对应的 value。
2. Key 用弱引用的原因是，如果 Key 是强引用，只要 ThreadLocal 对象还被 ThreadLocalMap 引用着，即使业务代码里已经把 ThreadLocal 置为 null，它也不会被 GC 回收。用弱引用的话，一旦业务代码不再持有 ThreadLocal 的强引用，下次 GC 就可以把 Key 回收掉。这是为了在线程生命周期较长的情况下，尽量减轻 ThreadLocal 对象本身的内存占用。

### **Q25** `ThreadLocal` 内存泄漏的原因？Key（弱引用）被 GC 后，Value 为什么还在？`remove()` 方法为什么必须调用？
?
1. 问题就出在 Key 和 Value 的生命周期不对称上。ThreadLocalMap 的 Entry 继承了 WeakReference，Key 是用弱引用包装的。当外部不再有 ThreadLocal 对象的强引用时，GC 会把 Key 回收掉，Entry 里的 Key 变成 null。但 Value 是强引用，它直接关联在 Entry 对象上，而 Entry 对象又被当前线程的 ThreadLocalMap 持有，只要线程还活着，ThreadLocalMap 就在，Entry 就在，Value 就永远无法被 GC。这就是内存泄漏的根源——大量 Key 为 null 但 Value 还活着的 Entry 占着内存不放。
2. remove 方法必须调用，就是因为它会清除当前 ThreadLocal 对应的 Entry，同时还会触发一次启发式清理，顺带清理其他 Key 为 null 的 Entry。如果不主动调用 remove，这些脏 Entry 只能等下一次调用 set 或 get 时才有可能被清理，而这个"下一次"很可能永远不来，尤其是在线程池的场景下。

### **Q26** 线程池中使用 `ThreadLocal` 有什么额外风险？怎么解决？（线程复用导致上次请求的 ThreadLocal 残留）
?
1. 线程池的线程是复用的，一个线程处理完当前请求后会回到池里等待下一个请求。如果第一个请求在 ThreadLocal 里存了用户信息，处理完后没有调用 remove，那这个线程被拿去处理第二个请求时，ThreadLocal 里还残留着上一个用户的信息。第二个请求可能误读到前一个用户的数据，轻则数据错乱，重则产生安全问题，比如用户 A 看到了用户 B 的数据。
2. 解决方法就是在 finally 块里强制调用 remove。无论是用 try-finally 包住整个请求处理逻辑，还是在拦截器或者过滤器的 afterCompletion 里统一清理，核心原则就是保证请求结束时执行 remove。

### **Q27** `InheritableThreadLocal` 是做什么的？线程池场景下它能正常工作吗？`TransmittableThreadLocal`（阿里开源）解决了什么？
?
1. InheritableThreadLocal 的作用是让子线程可以继承父线程的 ThreadLocal 值。当一个线程创建子线程时，子线程的 ThreadLocalMap 会拷贝父线程 InheritableThreadLocal 中的值。典型的应用场景是链路追踪中传递 traceId。
2. 但是在线程池场景下它不能正常工作。因为线程池里的线程不是每次任务都新创建的，子线程只在线程第一次创建的时候从父线程拷贝一次。之后这个线程被复用，ThreadLocal 里的值就是旧的，不会随着每次任务提交而更新。
3. TransmittableThreadLocal 就是解决这个问题的。它在提交任务给线程池时做了拦截，在任务执行前把父线程的 ThreadLocal 值传递到子线程，执行后再恢复子线程原来的值。这样即使线程被复用，每次执行任务时都能拿到正确的父线程上下文。它的核心机制就是包装 Runnable 和 Callable，在执行前后自动做值的传递和恢复。

---

## 七、并发工具类

### **Q28** `CountDownLatch` 和 `CyclicBarrier` 的区别？（使用次数、计数方向、等待线程角色三个维度）
?
1. 有三个关键区别。第一，使用次数。CountDownLatch 是一次性的，计数器减到零之后就不能重置了，不能复用。CyclicBarrier 可以复用，当所有线程都到达屏障后，计数器自动重置，可以用于下一轮。
2. 第二，计数方向。CountDownLatch 的计数是递减的，外部线程调用 countDown 把计数减一，等待线程调用 await 等计数到零。CyclicBarrier 的计数是递增的，每个线程调用 await 把计数加一，直到达到设定的参与线程数，所有线程同时释放。
3. 第三，等待线程的角色。CountDownLatch 中，调用 countDown 的线程和调用 await 的线程可以是不同的线程，典型场景是一个主线程等待多个工作线程完成。CyclicBarrier 中，所有线程都是参与者，它们彼此等待，任何一个线程先到屏障都得等其他人，大家一起走。

### **Q29** `Semaphore` 的 `acquire()` 和 `release()` 底层是怎么用 AQS 共享模式实现的？如果你用 Semaphore 做限流，怎么设计？
?
1. Semaphore 内部基于 AQS 共享模式实现。构造时传入的许可数赋值给 AQS 的 state。acquire 方法调用 AQS 的 acquireSharedInterruptibly，最终走到 Semaphore 自己实现的 tryAcquireShared，用 CAS 自旋把 state 减一。如果 state 大于零说明还有许可，减一成功返回剩余许可数；如果 state 已经为零，线程就会被包装成共享模式节点放入等待队列阻塞。release 方法调用 releaseShared，走到 tryReleaseShared，用 CAS 自旋把 state 加一，然后触发共享模式的后继节点传播唤醒。
2. 用 Semaphore 做限流的思路：初始化时设定许可数等于允许的最大并发数。每个请求进来先 acquire 获取一个许可，拿到了就执行业务逻辑，执行完在 finally 里 release 归还许可。如果许可用完了，acquire 会阻塞，请求就被限流了。为了更好的用户体验，可以用 tryAcquire 设置超时时间，超时了直接返回"系统繁忙"而不是让用户一直等。

### **Q30** `Exchanger` 做什么用的？用过吗？`Phaser` 相比 `CyclicBarrier` 有什么优势？
?
1. Exchanger 是一个线程间交换数据的同步点。两个线程在 Exchanger 的 exchange 方法处相遇，各自把自己持有的数据交给对方。它基于 CAS 和自旋实现，内部有一个槽位，先到的线程把自己的数据放进去然后自旋等待，后到的线程读取槽位里的数据，把自己的数据也放进去。不过实际项目中用得比较少。
2. Phaser 是 CyclicBarrier 和 CountDownLatch 的超集，它有几个显著优势。第一，参与者数量可以动态变化，支持线程在运行过程中注册和注销，CyclicBarrier 的参与者数是固定的。第二，Phaser 支持多阶段协同，每一阶段所有参与者到达后再一起进入下一阶段，而且可以指定是否要在阶段切换时执行回调。第三，Phaser 不需要手动重置，每一阶段完成后自动进入下一阶段。这些特性让 Phaser 在复杂的多阶段并行计算场景中比 CyclicBarrier 更灵活。

---

## 八、CompletableFuture（现代异步编程）

### **Q31** `Future` 的局限性是什么？`CompletableFuture` 解决了什么问题？
?
1. Future 有几个明显的局限。第一，它只提供了 isDone 和 get 方法，get 是阻塞的，如果任务没完成，调用线程会被卡住。第二，多个 Future 之间无法编排依赖关系，没办法自然地表达"任务 A 做完后做任务 B"这种流程。第三，没有异常处理机制，任务抛异常了，get 时才会抛 ExecutionException，不方便做异常恢复。第四，不支持回调，不能任务完成后自动触发后续逻辑。
2. CompletableFuture 解决了上面所有问题。它实现了 Future 和 CompletionStage 接口，支持链式调用和组合编排。任务完成后可以自动触发下一个任务，不需要阻塞等待。支持异常处理和恢复，提供了 exceptionally、handle 等方法。还支持多个任务的组合，比如 allOf 等待所有完成、anyOf 等待任意一个完成。本质上就是把命令式的异步编程变成了声明式的流水线编排。

### **Q32** `thenApply()`、`thenAccept()`、`thenRun()` 的区别？`thenCompose()` 和 `thenCombine()` 分别用于什么场景？
?
1. thenApply 接收上一个任务的结果，做一些转换，然后返回一个新的结果，有输入有输出。thenAccept 接收上一个任务的结果，做一些消费型操作，但没有返回值，有输入无输出。thenRun 不关心上一个任务的结果，也不返回结果，只是单纯在上个任务完成后执行一段逻辑，无输入无输出。三者的区别就是有没有输入、有没有输出。
2. thenCompose 用于扁平化的任务串联，上一个任务的结果作为下一个任务的输入，而且下一个任务本身也返回一个 CompletableFuture。比如根据查询到的用户 ID 再去查用户的订单信息，两个都是异步操作。thenCompose 会把嵌套的 CompletableFuture 扁平化，避免出现 CompletableFuture<`CompletableFuture<T>`> 这种嵌套结构。
3. thenCombine 用于并行任务的结果合并。两个独立的异步任务同时执行，都完成之后把两个结果合并处理。典型场景是同时查用户信息和商品信息，两个查询不依赖彼此，都返回后用 thenCombine 合并结果。

### **Q33** `CompletableFuture.allOf()` 返回的是什么？如何获取 `allOf` 之后所有任务的结果？
?
1. allOf 返回的是一个 `CompletableFuture<Void>`，它本身不包含任何结果值，只是作为一个信号——当所有传入的 CompletableFuture 都完成时，这个 Void 类型的 Future 也完成。
2. 要获取所有任务的结果，通常的做法是在 allOf 后面用 thenApply 或 thenAccept 回调，在回调里对之前保存的每个 CompletableFuture 引用逐个调用 join 方法取出结果。因为 allOf 完成时已经保证了所有任务都执行完了，join 不会阻塞。另外也可以配合 stream 用 CompletableFuture 的 join 收集结果，比如把所有 Future 放进一个 List，allOf 完成后对 List 做 stream map join 收集。

### **Q34** `CompletableFuture` 默认用的是什么线程池？为什么生产环境不推荐用默认的 `ForkJoinPool.commonPool()`？
?
1. CompletableFuture 如果不显式指定线程池，默认用的是 ForkJoinPool.commonPool。这个线程池的线程数默认是 CPU 核心数减一，它是 JVM 级别的共享线程池，所有使用默认线程池的 CompletableFuture 和并行流都在这里执行。
2. 不推荐用 commonPool 的原因主要是它被整个 JVM 进程共享。如果你某个业务的 CompletableFuture 里执行了阻塞操作，比如数据库查询或者调用第三方接口，线程就会被阻塞住。commonPool 的线程数本来就少，一旦几个线程都被阻塞了，就会影响其他所有依赖 commonPool 的异步任务，甚至拖慢整个系统。正确的做法是自己创建线程池，根据业务特点配置合适的参数，做到线程池隔离。

### **Q35** `CompletableFuture` 的 `completeExceptionally()` 和 `handle()` / `exceptionally()` 有什么区别？异常传播链是怎样的？
?
1. completeExceptionally 是主动把一个 CompletableFuture 标记为异常完成，通常在异步回调中遇到无法恢复的错误时使用。调用它之后，所有依赖这个 Future 的后续阶段都会感知到这个异常。
2. exceptionally 和 handle 是消费异常的方式，但角色不同。exceptionally 只能处理异常，正常结果直接透传，它的入参是异常，出参是恢复后的正常值。handle 是通用的，无论正常还是异常都会执行，入参是结果和异常两个参数，可以同时处理两种路径。
3. 异常传播链是这样的。如果某个阶段抛出异常，它会沿着依赖链向下传递，跳过所有不处理异常的 thenApply、thenAccept 这类回调，直到遇到 handle 或 exceptionally 截住这个异常。如果整条链上都没有异常处理器，最终调用 join 或 get 时会抛 CompletionException，把原始异常包装在里面。

---

## 九、并发容器

### **Q36** `ConcurrentHashMap` 的 `computeIfAbsent()` 方法内部是怎么保证原子性的？为什么不能在里面做耗时操作？
?
1. computeIfAbsent 的执行逻辑是：先检查 key 对应的值是否存在，如果已经有值就直接返回；如果没有，用传入的 Function 计算新值，然后通过 CAS 或 synchronized 把新值放入。整个过程在 ConcurrentHashMap 内部对目标桶加了同步控制，避免了多个线程同时对同一个 key 执行 computeIfAbsent 时的重复计算问题。JDK8 中会对桶的第一个节点加 synchronized，确保同一时刻只有一个线程在计算和插入。
2. 不能在 computeIfAbsent 的 Function 里做耗时操作，原因是 Function 是在持有桶级锁的情况下执行的。如果 Function 里调了远程接口或者做了大量计算，这个桶就被长时间锁住，其他所有要操作这个桶的线程都会被阻塞。而且这个锁是桶级别的，影响范围虽然比全局锁小，但在高并发下仍然会造成明显的性能瓶颈。

### **Q37** `ConcurrentLinkedQueue` 是怎么实现无锁的？CAS 操作的是哪个字段？和 `LinkedBlockingQueue` 的使用场景有什么区别？
?
1. ConcurrentLinkedQueue 是基于 Michael-Scott 无锁队列算法实现的，完全不用锁。它的入队操作是：把新节点加到尾节点后面，通过 CAS 更新尾节点的 next 字段指向新节点，然后通过 CAS 更新尾指针 tail 指向新节点。出队操作是：通过 CAS 更新头节点 head 指向下一个节点，把原头节点的值取出来返回。CAS 操作的具体字段就是节点的 next 指针和队列的 head、tail 指针。
2. LinkedBlockingQueue 内部用了两把锁，putLock 和 takeLock，入队和出队各用各的锁，所以生产和消费可以并行。它是阻塞队列，队列空时消费者会阻塞等，队列满时生产者会阻塞等。
3. 两者的使用场景完全不同。ConcurrentLinkedQueue 是非阻塞的，适合高并发、无阻塞要求的场景，但消费者需要自己处理空队列的情况，通常配合轮询使用。LinkedBlockingQueue 适合生产者消费者模式，有天然的背压机制，消费者没活干就阻塞等着，不至于空转浪费 CPU。

### **Q38** `CopyOnWriteArrayList` 的迭代器为什么不需要加锁就能保证不抛 `ConcurrentModificationException`？但是它读到的一定是最新数据吗？
?
1. CopyOnWriteArrayList 的迭代器不会抛 ConcurrentModificationException，原因是它的迭代器在创建时拿到的是底层数组的一个快照引用。迭代过程中，即使其他线程对这个列表做了增删改操作，底层会复制出一个新数组来修改，然后把引用指向新数组。但迭代器还拿着旧数组的引用，所以迭代器遍历的数据始终保持一致，不会因为并发修改抛出异常。这就是写时复制——写操作不影响读操作，读操作也看不到写操作的结果。
2. 但它读到的不一定是最新数据。因为迭代器持有的是创建时刻的快照，后续的写操作都发生在新数组上，迭代器完全感知不到。如果要读到最新数据，需要重新获取迭代器或者用其他方式。这也是 CopyOnWriteArrayList 的经典取舍：保证读的一致性，但牺牲实时性。

---

## 十、虚拟线程 & 现代并发（JDK21 拉开分差）

### **Q39** 虚拟线程（Virtual Thread）是什么？和平台线程（Platform Thread）的本质区别？它是怎么实现"一个 OS 线程承载多个虚拟线程"的？
?
1. 虚拟线程是 JDK21 正式发布的轻量级线程实现，由 JVM 管理而不是操作系统管理。平台线程就是传统的 Java 线程，一对一映射到操作系统线程，每个线程消耗约 1MB 栈空间，上下文切换由操作系统调度。
2. 本质区别在于映射关系和调度方式。平台线程是操作系统资源，创建和切换成本高；虚拟线程是 JVM 管理的对象，创建成本极低，几百万个都不是问题，而且调度由 JVM 在用户态完成，不需要陷入内核态。
3. 一个 OS 线程承载多个虚拟线程是通过"挂载"和"卸载"机制实现的。虚拟线程运行在载体线程（就是平台线程）上。当虚拟线程执行到阻塞操作时，比如 IO 等待，JVM 会把它从载体线程上卸载下来，保存栈帧状态到堆内存中，然后载体线程就可以去执行另一个就绪的虚拟线程。等阻塞操作完成，这个虚拟线程再被重新挂载到某个空闲的载体线程上继续执行。通过这种"阻塞即卸载"的机制，少量平台线程就可以支撑海量虚拟线程。

### **Q40** 虚拟线程适合什么场景，不适合什么场景？为什么不要在虚拟线程里用 `synchronized` 做长时间持锁？
?
1. 虚拟线程最适合 IO 密集型场景，比如高并发的 HTTP 请求处理、数据库查询、远程服务调用等。这类场景中线程大部分时间在等待 IO，虚拟线程可以在等待时自动释放载体线程，让载体线程去执行其他虚拟线程，极大提升吞吐量。
2. 不适合的场景是 CPU 密集型计算。如果任务一直在做计算，没有 IO 等待，虚拟线程就不会卸载，一直占着载体线程，跟平台线程没有区别，反而多了虚拟线程调度的开销。
3. 不要用 synchronized 长时间持锁的原因是，JDK21 的虚拟线程在 synchronized 块内阻塞时，会"钉住"载体线程，无法卸载。也就是说载体线程只能干等着，不能被释放去执行其他虚拟线程。这会让虚拟线程的优势大打折扣，甚至在极端情况下导致所有载体线程都被钉住，系统陷入饥饿。所以虚拟线程场景下推荐用 ReentrantLock 代替 synchronized。

### **Q41** 结构化并发（Structured Concurrency，JDK21 预览）的核心思想是什么？`StructuredTaskScope` 和 `ExecutorService` 的区别？
?
1. 结构化并发的核心思想是把并发任务的边界和代码块的作用域对应起来。一个方法里启动的所有子任务都在这个方法返回之前完成，不会出现"任务泄漏"——也就是线程还在后台跑但代码已经继续往下走了的情况。它让并发任务的生命周期像普通变量一样，受到代码块的约束。
2. StructuredTaskScope 和 ExecutorService 的区别在于生命周期管理。ExecutorService 提交任务后，任务的生命周期和提交者是解耦的，你需要在 finally 里手动 shutdown，否则任务可能继续跑。StructuredTaskScope 使用 try-with-resources 模式，当代码块结束时自动等待所有子任务完成或者取消未完成的任务，确保没有任务泄漏。另外，StructuredTaskScope 提供了两种失败策略，ShutdownOnSuccess 模式是任意一个成功就取消其他任务，ShutdownOnFailure 模式是任意一个失败就取消其他任务，这些策略都是声明式的，代码更简洁清晰。

---

## 十一、实战场景

### **Q42** 设计一个"多线程批量处理 100 万条数据"的方案。要求：分批拉取、并行处理、结果汇总、支持中断、异常重试。说出你的技术选型和关键代码结构。
?
1. 整体技术选型：线程池用 ThreadPoolExecutor，队列用 ArrayBlockingQueue 并指定合理容量，避免无界堆积。分批拉取用分页查询，每批比如 1000 条。并行处理用 CompletableFuture 做编排。中断支持用 CountDownLatch 配合 volatile 标记位。异常重试用 CompletableFuture 的 exceptionally 加递归重试逻辑。
2. 关键流程是这样的。主线程用一个循环分批拉取数据，每批拿到后封装成 Callable 提交给线程池，返回一个 Future。同时用一个 AtomicInteger 记录成功数和失败数。所有批次的 Future 收集到一个 List 里，用 CompletableFuture.allOf 等待全部完成。
3. 中断机制用 volatile boolean 做全局开关，每次提交新批次前检查这个标记。如果外部触发中断，设为 true，主线程不再提交新批次，已提交的批次用 Future.cancel 尝试取消。
4. 异常重试在单个任务的层面上做。每个批次任务内部用 try-catch 包裹，捕获异常后如果有重试次数，把当前批次重新包装再提交给线程池。重试次数可以用一个 AtomicInteger 做计数器，不超过 3 次。
5. 结果汇总等所有 Future 完成之后，遍历结果，统计成功和失败批次的 ID、耗时等信息，输出汇总报告。超时控制可以给 allOf 的 join 方法设置超时时间，超时了还没完成就触发中断流程。
6. 数据一致性方面，如果每批之间有依赖，需要确保提交顺序和结果汇总的一致性。如果没有依赖，各批次完全独立并行处理，效率最高。