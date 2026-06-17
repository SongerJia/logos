# Java 并发锁机制源码深度解析
## synchronized · AQS · ReentrantLock

> 基于 JDK 8 版本，JVM 层深入到 HotSpot 源码级别；覆盖 JDK 15/17 的锁变化

---

## 目录

**Part 1 — synchronized**
1. [对象头与 Mark Word](#1-对象头与-mark-word)
2. [锁升级全流程（偏向锁 → 轻量级锁 → 重量级锁）](#2-锁升级全流程)
3. [Monitor 重量级锁的实现](#3-monitor-重量级锁的实现)
4. [字节码层面：monitorenter / monitorexit](#4-字节码层面monitorenter--monitorexit)

**Part 2 — AQS（AbstractQueuedSynchronizer）**
5. [AQS 整体架构](#5-aqs-整体架构)
6. [核心字段：state 与 CLH 队列](#6-核心字段state-与-clh-队列)
7. [独占模式 acquire / release](#7-独占模式-acquire--release)
8. [共享模式 acquireShared / releaseShared](#8-共享模式-acquireshared--releaseshared)
9. [ConditionObject（条件队列）](#9-conditionobject条件队列)

**Part 3 — ReentrantLock**
10. [整体架构与继承关系](#10-整体架构与继承关系)
11. [NonfairSync 非公平锁 lock/unlock](#11-nonfairsync-非公平锁-lockunlock)
12. [FairSync 公平锁 lock/unlock](#12-fairsync-公平锁-lockunlock)
13. [ReentrantLock 的可重入实现](#13-reentrantlock-的可重入实现)
14. [lockInterruptibly / tryLock](#14-lockinterruptibly--trylock)

**Part 4 — 综合对比与面试题**
15. [synchronized vs ReentrantLock](#15-synchronized-vs-reentrantlock)
16. [常见面试题](#16-常见面试题)

---

# Part 1 — synchronized

## 1. 对象头与 Mark Word

### 1.1 Java 对象的内存布局

```
┌─────────────────────────────────────────────┐
│             Java 对象内存布局                 │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │         对象头 (Object Header)        │   │
│  │  ┌─────────────────────────────────┐ │   │
│  │  │  Mark Word (8 字节，64位JVM)     │ │   │  ← 存储锁状态、hashCode、GC信息
│  │  └─────────────────────────────────┘ │   │
│  │  ┌─────────────────────────────────┐ │   │
│  │  │  Klass Pointer (4/8 字节)        │ │   │  ← 指向类元数据
│  │  └─────────────────────────────────┘ │   │
│  │  ┌─────────────────────────────────┐ │   │
│  │  │  数组长度 (4 字节，仅数组对象有)  │ │   │
│  │  └─────────────────────────────────┘ │   │
│  └──────────────────────────────────────┘   │
│  ┌──────────────────────────────────────┐   │
│  │         实例数据 (Instance Data)      │   │
│  └──────────────────────────────────────┘   │
│  ┌──────────────────────────────────────┐   │
│  │         对齐填充 (Padding)            │   │  ← 保证8字节对齐
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### 1.2 Mark Word 的结构（64位JVM）

Mark Word 是实现 synchronized 锁升级的关键，不同锁状态下布局不同：

```
64位 Mark Word 格式（低2位为锁标志位）：

┌─────────────────────────────────────────────────────────────────────────┐
│ 锁状态        │ 高位信息                                    │ 标志位      │
├───────────────┼───────────────────────────────────────────┼─────────────┤
│ 无锁          │ 25位unused │ 31位hashCode │ 1位unused │ 4位分代GC │ 01 │
├───────────────┼───────────────────────────────────────────┼─────────────┤
│ 偏向锁        │ 54位线程ID │ 2位Epoch │ 1位unused │ 4位分代GC │ 1 │ 01 │
├───────────────┼───────────────────────────────────────────┼─────────────┤
│ 轻量级锁      │ 62位 指向线程栈中 LockRecord 的指针          │ 00          │
├───────────────┼───────────────────────────────────────────┼─────────────┤
│ 重量级锁      │ 62位 指向 Monitor 对象的指针                  │ 10          │
├───────────────┼───────────────────────────────────────────┼─────────────┤
│ GC标记        │ 全0                                         │ 11          │
└─────────────────────────────────────────────────────────────────────────┘

标志位含义：
  01（偏向位=0）: 无锁
  01（偏向位=1）: 偏向锁
  00: 轻量级锁
  10: 重量级锁
  11: GC 标记
```

---

## 2. 锁升级全流程

### 2.1 升级路径

```
           无锁 (Unlocked)
               │
               │ 第一个线程加锁
               ▼
           偏向锁 (Biased Locking)
               │  ← 单线程反复获取，只需CAS一次
               │
               │ 其他线程尝试获取（竞争出现）
               ▼
           轻量级锁 (Lightweight Lock)
               │  ← 多线程短暂交替加锁，CAS自旋
               │
               │ 自旋超过阈值（默认10次）或等待线程 > 1
               ▼
           重量级锁 (Heavyweight Lock)
               │  ← 真正的 Monitor，阻塞等待
               │
               ▼
           GC后回到无锁（对象被回收）

⚠️ 锁升级是单向的，不能降级（GC 除外）
```

### 2.2 偏向锁（Biased Locking）

**设计思路**：大多数情况下，锁总是由同一线程反复获取。偏向锁通过在 Mark Word 中记录线程 ID，使同一线程再次加锁时无需任何同步操作。

```
┌────────────────────────────────────────────────────────────┐
│ 偏向锁的工作流程                                             │
│                                                            │
│ 线程A 第一次加锁：                                          │
│   CAS 将 Mark Word 中线程ID 设为线程A的ID                   │
│   成功 → 获取偏向锁                                         │
│                                                            │
│ 线程A 再次加锁：                                            │
│   检查 Mark Word 中线程ID == 自己？                          │
│   是 → 直接进入同步块（无需任何 CAS / 原子操作！）             │
│                                                            │
│ 线程B 尝试加锁（竞争）：                                     │
│   检查 Mark Word 中线程ID == 自己？                          │
│   否 → 触发偏向锁撤销                                       │
└────────────────────────────────────────────────────────────┘
```

**偏向锁撤销（Revocation）**：

```
线程B 尝试获取线程A持有的偏向锁
    │
    ▼
等待 Global Safe Point（所有线程暂停）
    │
    ▼
检查线程A 是否还活着且在同步块内？
    ├─ 是 → 升级为轻量级锁（线程A持有）
    └─ 否 → 根据是否有其他竞争决定：
           ├─ 无竞争 → 重置为无锁或新偏向锁
           └─ 有竞争 → 升级为轻量级锁
```

**⚠️ JDK 15 废弃偏向锁**（JEP 374）：

偏向锁的维护成本（复杂的撤销逻辑）在现代应用中得不偿失，JDK 15 默认禁用，JDK 18 彻底移除。

### 2.3 轻量级锁（Lightweight Locking）

**设计思路**：多线程**交替**而不是**同时**加锁时，用 CAS 代替真正的互斥，避免线程阻塞。

```
加锁过程：

线程A 进入同步块
    │
    ▼
在线程A的栈帧中创建 Lock Record
    │ Mark Word 拷贝 + 指针初始化
    ▼
CAS 将对象的 Mark Word 替换为指向 Lock Record 的指针
    │
    ├─ CAS 成功 → 获取轻量级锁
    └─ CAS 失败
           │
           ├─ 是同一线程的重入？→ 新建 Lock Record（递归深度）
           └─ 其他线程竞争 → 自旋等待
                   │
                   └─ 超过阈值（JDK 8: 自适应自旋）→ 升级重量级锁
```

**Lock Record 的结构**：

```
线程栈帧中的 Lock Record（轻量级锁记录）：

┌─────────────────────────────────────┐
│ displaced Mark Word                  │ ← 保存对象原始 Mark Word 的备份
│（对象无锁时的 Mark Word）              │
├─────────────────────────────────────┤
│ object pointer                       │ ← 指向被锁对象
└─────────────────────────────────────┘

加锁后：
  对象 Mark Word → 指向 Lock Record（标志位 00）
  Lock Record → 保存原始 Mark Word
  形成一个双向链接
```

**解锁过程**：

```
CAS 将 Lock Record 的 displaced Mark Word 写回对象 Mark Word
    │
    ├─ 成功 → 解锁完成
    └─ 失败（对象 Mark Word 已变为重量级锁指针）→ 进入重量级锁解锁流程
```

### 2.4 重量级锁（Heavyweight Lock / Monitor）

自旋仍然失败 → CAS 将 Mark Word 改为指向 Monitor 的指针（标志位 10）→ 进入 Monitor 的 EntryList 等待，线程被真正挂起（OS 级别阻塞）。

---

## 3. Monitor 重量级锁的实现

### 3.1 Monitor 结构（HotSpot ObjectMonitor）

```java
// HotSpot JVM 中 C++ 实现的 ObjectMonitor
// objectMonitor.hpp 关键字段：

class ObjectMonitor {
    void* _header;          // Mark Word 备份
    void* _object;          // 关联的 Java 对象
    Thread* _owner;         // 当前持有锁的线程
    int _recursions;        // 重入次数
    int _count;             // 竞争线程数（_count + 1 = 活跃监视者数量）

    ObjectWaiter* _EntryList;   // 阻塞等待获取锁的线程（Blocked 状态）
    ObjectWaiter* _WaitSet;     // 调用 wait() 后等待的线程（Waiting 状态）
    ObjectWaiter* _cxq;         // 最近进入 EntryList 的线程（竞争队列）
};
```

```
ObjectMonitor 示意图：

┌───────────────────────────────────────┐
│           ObjectMonitor               │
│                                       │
│  _owner: ThreadA                      │  ← 持有锁的线程
│  _recursions: 1                       │  ← 重入次数
│                                       │
│  ┌────────────────────────────────┐   │
│  │  _EntryList（阻塞等待队列）      │   │
│  │  ThreadB → ThreadC → null       │   │  ← BLOCKED 线程
│  └────────────────────────────────┘   │
│                                       │
│  ┌────────────────────────────────┐   │
│  │  _WaitSet（等待通知队列）        │   │
│  │  ThreadD → ThreadE → null       │   │  ← 调用了 wait() 的线程
│  └────────────────────────────────┘   │
│                                       │
│  ┌────────────────────────────────┐   │
│  │  _cxq（竞争队列）               │   │
│  │  ThreadF → null                 │   │  ← 刚尝试获取锁的线程
│  └────────────────────────────────┘   │
└───────────────────────────────────────┘
```

### 3.2 notify / notifyAll 的底层机制

```
调用 notify()：
  从 _WaitSet 取出一个线程（通常是头部）
  根据策略转移到 _EntryList 或 _cxq
  被移出的线程仍需竞争锁（不是直接获取）

调用 notifyAll()：
  将 _WaitSet 中所有线程移到 _EntryList
  所有线程开始竞争锁

释放锁时（monitorexit）：
  从 _EntryList 或 _cxq 中选择一个线程唤醒
  被唤醒线程重新竞争锁
```

---

## 4. 字节码层面：monitorenter / monitorexit

### 4.1 同步方法 vs 同步块的字节码

```java
// Java 源码
synchronized (this) {
    count++;
}
```

对应字节码：

```
monitorenter    // 进入同步块，获取 this 对象的 Monitor
// ... 执行 count++ ...
monitorexit     // 正常退出
goto L
L: monitorexit  // 异常退出（编译器自动插入的 finally 块）
```

```java
// 同步方法
public synchronized void increment() { count++; }
```

对应字节码（方法访问标志）：

```
ACC_SYNCHRONIZED  // 方法访问标志，JVM 自动在进入/退出方法时加/解锁
                  // 不是 monitorenter/monitorexit，而是方法调用机制保证
```

### 4.2 锁对象的选择

```java
synchronized (this) { ... }         // 锁 this 对象
synchronized (MyClass.class) { ... } // 锁类对象（Class 对象）
synchronized (someObject) { ... }    // 锁指定对象

public synchronized void method() { ... }         // 等价于 synchronized(this)
public static synchronized void method() { ... }  // 等价于 synchronized(MyClass.class)
```

---

# Part 2 — AQS（AbstractQueuedSynchronizer）

## 5. AQS 整体架构

AQS 是 Java 并发包（java.util.concurrent）中大量同步器的基础框架：

```
                  AbstractQueuedSynchronizer (AQS)
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
   ReentrantLock      Semaphore        CountDownLatch
   (独占模式)          (共享模式)        (共享模式)
         │
   ReentrantReadWriteLock
   (独占+共享)
```

**AQS 提供的核心抽象**：

| 方法 | 子类实现 | 作用 |
|------|----------|------|
| `tryAcquire(int)` | 独占锁 | 尝试获取锁（非阻塞） |
| `tryRelease(int)` | 独占锁 | 尝试释放锁 |
| `tryAcquireShared(int)` | 共享锁 | 尝试获取共享资源 |
| `tryReleaseShared(int)` | 共享锁 | 尝试释放共享资源 |
| `isHeldExclusively()` | 独占锁 | 是否被当前线程独占 |

---

## 6. 核心字段：state 与 CLH 队列

### 6.1 state 状态变量

```java
public abstract class AbstractQueuedSynchronizer {

    // 核心同步状态，volatile 保证可见性
    // 子类赋予不同含义：
    //   ReentrantLock: 0=未锁, n=重入次数
    //   Semaphore:     剩余许可数
    //   CountDownLatch: 计数器值
    private volatile int state;

    protected final int getState() { return state; }
    protected final void setState(int newState) { state = newState; }
    protected final boolean compareAndSetState(int expect, int update) {
        return unsafe.compareAndSwapInt(this, stateOffset, expect, update);
    }
}
```

### 6.2 CLH 队列（双向链表）

AQS 使用了改良版的 CLH（Craig, Landin, Hagersten）队列来管理等待线程：

```
head (虚节点)                                           tail
 ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
 │ Node     │←─→ │ Node     │←─→ │ Node     │←─→ │ Node     │
 │SIGNAL    │    │ Thread B │    │ Thread C │    │ Thread D │
 │(无线程)   │    │SIGNAL    │    │SIGNAL    │    │SIGNAL    │
 └──────────┘    └──────────┘    └──────────┘    └──────────┘
      ↑                                                ↑
  head 指针                                        tail 指针

每个等待线程持有一个 Node，形成双向链表
前驱节点负责唤醒后继节点（状态传播）
为什么有虚拟节点
1.每个节点在park时，会把前驱节点的waitStatus设为 SIGNAL，使用虚拟节点统一所有节点的前置处理逻辑。head是虚拟节点，后续节点在获取到锁后，那么会把节点设为head节点，但会清掉线程信息，让它看起来是一个虚拟节点。
2.队列永远非空，不用考虑队列空和非空的边界情况，清除首节点边界判断。
```

### 6.3 Node 的结构

```java
static final class Node {

    // 共享模式的标记节点
    static final Node SHARED = new Node();
    // 独占模式的标记
    static final Node EXCLUSIVE = null;

    // waitStatus 的取值：
    static final int CANCELLED =  1;  // 线程已取消等待
    static final int SIGNAL    = -1;  // 后继节点需要被唤醒（park）
    static final int CONDITION = -2;  // 节点在条件队列中
    static final int PROPAGATE = -3;  // 共享模式的传播标志

    volatile int waitStatus;    // 节点等待状态
    volatile Node prev;         // 前驱节点
    volatile Node next;         // 后继节点
    volatile Thread thread;     // 该节点对应的线程
    Node nextWaiter;            // 条件队列中的下一个节点（或 SHARED/EXCLUSIVE 标记）
}
```

**waitStatus 含义速查**：

| 值 | 常量 | 含义 |
|----|------|------|
| 0 | 初始值 | 刚入队，无特殊状态 |
| 1 | CANCELLED | 线程已取消，该节点会被跳过 |
| -1 | SIGNAL | 当我释放锁时，需要唤醒后继节点 |
| -2 | CONDITION | 在条件队列中等待（await） |
| -3 | PROPAGATE | 共享模式下，释放需要向后传播 |

---

## 7. 独占模式 acquire / release

### 7.1 acquire 完整源码 + 逐行注释

```java
public final void acquire(int arg) {
    // ① 调用子类的 tryAcquire，尝试直接获取锁（不阻塞）
    if (!tryAcquire(arg) &&
    // ② tryAcquire 失败 → 创建节点加入队列，并阻塞等待
        acquireQueued(addWaiter(Node.EXCLUSIVE), arg))
        // ③ acquireQueued 返回 true 说明等待中被中断过
        selfInterrupt(); // 补上中断（restore interrupt flag）
}
```

### 7.2 addWaiter —— 入队

```java
private Node addWaiter(Node mode) {
    Node node = new Node(Thread.currentThread(), mode); // 创建节点

    Node pred = tail;
    if (pred != null) {
        node.prev = pred;
        // ① 快速路径：CAS 尝试直接设置为 tail
        if (compareAndSetTail(pred, node)) {
            pred.next = node;
            return node;
        }
    }
    // ② 快速路径失败（队列为空或 CAS 竞争）→ 自旋入队
    enq(node);
    return node;
}

private Node enq(final Node node) {
    for (;;) { // 自旋，直到成功
        Node t = tail;
        if (t == null) {
            // 队列为空 → 初始化虚节点（head）
            if (compareAndSetHead(new Node()))
                tail = head;
        } else {
            node.prev = t;
            if (compareAndSetTail(t, node)) {
                t.next = node;
                return t;
            }
        }
    }
}
```

### 7.3 acquireQueued —— 排队等待

```java
final boolean acquireQueued(final Node node, int arg) {
    boolean failed = true;
    try {
        boolean interrupted = false;

        for (;;) {
            final Node p = node.predecessor(); // 获取前驱节点

            // ① 前驱是 head → 自己是队列中第一个等待线程 → 尝试获取锁
            if (p == head && tryAcquire(arg)) {
                setHead(node);  // 获取成功 → 自己变成 head
                p.next = null;  // 帮助 GC 回收旧 head
                failed = false;
                return interrupted;
            }

            // ② 判断是否需要 park（阻塞）
            if (shouldParkAfterFailedAcquire(p, node) &&
                parkAndCheckInterrupt())  // park 当前线程
                interrupted = true; // 记录被中断过
        }
    } finally {
        if (failed)
            cancelAcquire(node); // 取消（异常情况）
    }
}
```

### 7.4 shouldParkAfterFailedAcquire —— 是否需要阻塞

```java
private static boolean shouldParkAfterFailedAcquire(Node pred, Node node) {
    int ws = pred.waitStatus;

    if (ws == Node.SIGNAL)
        // ① 前驱已经是 SIGNAL 状态 → 可以安全 park
        return true;

    if (ws > 0) {
        // ② 前驱被取消了（CANCELLED）→ 跳过所有取消节点，找到有效前驱
        do {
            node.prev = pred = pred.prev;
        } while (pred.waitStatus > 0);
        pred.next = node;
    } else {
        // ③ 前驱是初始状态 → CAS 设为 SIGNAL（下次再 park）
        compareAndSetWaitStatus(pred, ws, Node.SIGNAL);
    }
    return false; // 返回 false → 不 park，再循环一次
}
```

**park 前再循环一次的意义**：

```
第1次循环：tryAcquire 失败 → shouldPark 将前驱设为 SIGNAL → 返回 false
第2次循环：tryAcquire 再试一次（可能前驱恰好刚释放）→ 失败 → shouldPark 返回 true → park
```

### 7.5 release 完整源码

```java
public final boolean release(int arg) {
    // ① 调用子类的 tryRelease
    if (tryRelease(arg)) {
        Node h = head;
        // ② head 不为空 且 waitStatus != 0（有等待线程）
        if (h != null && h.waitStatus != 0)
            unparkSuccessor(h); // 唤醒后继节点
        return true;
    }
    return false;
}

private void unparkSuccessor(Node node) {
    int ws = node.waitStatus;
    if (ws < 0)
        compareAndSetWaitStatus(node, ws, 0); // 清除 SIGNAL 状态

    Node s = node.next;
    // 如果后继节点取消了，从 tail 往前找最近的有效节点
    if (s == null || s.waitStatus > 0) {
        s = null;
        for (Node t = tail; t != null && t != node; t = t.prev)
            if (t.waitStatus <= 0)
                s = t;
    }
    if (s != null)
        LockSupport.unpark(s.thread); // 唤醒！
}
```

### 7.6 acquire 完整流程图

```
acquire(arg)
    │
    ▼
tryAcquire(arg) ────成功────→ 直接返回（获取锁）
    │
    失败
    │
    ▼
addWaiter(EXCLUSIVE) → 创建 Node，CAS 入队尾
    │
    ▼
┌─→ acquireQueued()
│       │
│       ▼
│   前驱是 head？──是──→ tryAcquire(arg)
│       │                   │
│       │             成功 ──→ 设自己为 head，返回
│       │             失败 ──↓
│       │
│       ▼
│   shouldParkAfterFailedAcquire()
│       ├─ 前驱 CANCELLED → 跳过取消节点，继续
│       ├─ 前驱初始状态 → 设前驱为 SIGNAL，继续
│       └─ 前驱已是 SIGNAL → 可以 park
│
│       ▼
│   parkAndCheckInterrupt() → LockSupport.park()
│   [线程阻塞，等待 unpark]
│       │
│       │ 被 unpark / interrupted
│       │
└── ─ ──┘ 继续自旋
```

---

## 8. 共享模式 acquireShared / releaseShared

### 8.1 acquireShared

```java
public final void acquireShared(int arg) {
    // 返回值 < 0 表示获取失败
    if (tryAcquireShared(arg) < 0)
        doAcquireShared(arg);
}

private void doAcquireShared(int arg) {
    final Node node = addWaiter(Node.SHARED); // 共享节点入队
    boolean failed = true;
    try {
        boolean interrupted = false;
        for (;;) {
            final Node p = node.predecessor();
            if (p == head) {
                int r = tryAcquireShared(arg);
                if (r >= 0) {
                    setHeadAndPropagate(node, r); // ★ 关键：传播共享
                    p.next = null;
                    if (interrupted)
                        selfInterrupt();
                    failed = false;
                    return;
                }
            }
            if (shouldParkAfterFailedAcquire(p, node) &&
                parkAndCheckInterrupt())
                interrupted = true;
        }
    } finally {
        if (failed)
            cancelAcquire(node);
    }
}
```

### 8.2 setHeadAndPropagate —— 共享传播

```java
// 共享模式的核心：一次释放可能唤醒多个线程
private void setHeadAndPropagate(Node node, int propagate) {
    Node h = head;
    setHead(node); // 设置为新的 head

    // 如果还有剩余资源（propagate > 0），继续唤醒后续共享节点
    if (propagate > 0 || h == null || h.waitStatus < 0 ||
        (h = head) == null || h.waitStatus < 0) {
        Node s = node.next;
        if (s == null || s.isShared())
            doReleaseShared(); // 唤醒下一个共享等待节点
    }
}
```

---

## 9. ConditionObject（条件队列）

### 9.1 Condition 的使用场景

```java
// 经典生产者消费者模型
ReentrantLock lock = new ReentrantLock();
Condition notEmpty = lock.newCondition(); // "非空"条件
Condition notFull  = lock.newCondition(); // "非满"条件

// 消费者
lock.lock();
try {
    while (queue.isEmpty())
        notEmpty.await(); // 等待"非空"信号
    queue.poll();
    notFull.signal(); // 通知生产者
} finally {
    lock.unlock();
}
```

### 9.2 等待队列 vs 同步队列

```
等待队列（Condition Queue）:
  await() 时，线程从 AQS 同步队列移入 Condition 的等待队列

  ┌─────┐   ┌─────┐   ┌─────┐
  │  A  │ → │  B  │ → │  C  │    （单向链表，用 nextWaiter）
  └─────┘   └─────┘   └─────┘
  conditionHead                conditionTail

signal() 时，线程从 Condition 等待队列移回 AQS 同步队列（tail）
```

### 9.3 await 完整源码 + 逐行注释

```java
public final void await() throws InterruptedException {
    if (Thread.interrupted())
        throw new InterruptedException();

    // ① 加入条件队列（等待队列）
    Node node = addConditionWaiter();

    // ② 完全释放锁（state 降为 0，支持可重入）
    int savedState = fullyRelease(node);

    int interruptMode = 0;

    // ③ 循环：只要不在同步队列中，就 park
    while (!isOnSyncQueue(node)) {
        LockSupport.park(this); // 挂起，等待 signal

        // ④ 检查中断
        if ((interruptMode = checkInterruptWhileWaiting(node)) != 0)
            break;
    }

    // ⑤ 重新竞争锁（阻塞直到获取）
    if (acquireQueued(node, savedState) && interruptMode != THROW_IE)
        interruptMode = REINTERRUPT;

    if (node.nextWaiter != null)
        unlinkCancelledWaiters(); // 清理取消的等待节点

    // ⑥ 处理中断
    if (interruptMode != 0)
        reportInterruptAfterWait(interruptMode);
}
```

### 9.4 signal 完整源码

```java
public final void signal() {
    if (!isHeldExclusively())
        throw new IllegalMonitorStateException();

    Node first = firstWaiter;
    if (first != null)
        doSignal(first); // 唤醒等待队列的第一个节点
}

private void doSignal(Node first) {
    do {
        if ((firstWaiter = first.nextWaiter) == null)
            lastWaiter = null;
        first.nextWaiter = null; // 与条件队列断开
    } while (!transferForSignal(first) && // 转移到同步队列
             (first = firstWaiter) != null);
}

final boolean transferForSignal(Node node) {
    // 将 waitStatus 从 CONDITION 改为 0
    if (!compareAndSetWaitStatus(node, Node.CONDITION, 0))
        return false;
    // 入同步队列尾部
    Node p = enq(node);
    int ws = p.waitStatus;
    // 将前驱设置为 SIGNAL（确保会被唤醒）
    if (ws > 0 || !compareAndSetWaitStatus(p, ws, Node.SIGNAL))
        LockSupport.unpark(node.thread); // 前驱已取消，直接唤醒
    return true;
}
```

### 9.5 await/signal 流程图

```
await():
  线程持有锁 → 加入条件队列 → fullyRelease(释放锁)
  → LockSupport.park() 挂起
  → [等待 signal()]
  → 从条件队列移到同步队列 → 重新竞争锁 → 获取锁后继续执行

signal():
  持有锁 → 从条件队列取出第一个节点 → 移到同步队列 → unpark
  → 被唤醒的线程重新竞争锁（与普通等待线程公平竞争）

┌──────────────────────────────────────────────────────────────┐
│  AQS 同步队列                          Condition 等待队列      │
│                                                              │
│  head → [A(owner)] → B → C →tail      first→ D → E → last   │
│           ↑持有锁                                             │
│                                                              │
│  A 调用 await():                                              │
│    D 从条件队列转到同步队列尾部:                                 │
│  head→[A(await)]→B→C→D→tail           first→ E → last        │
│    A 释放锁，B 竞争获取...                                      │
└──────────────────────────────────────────────────────────────┘
```

---

# Part 3 — ReentrantLock

## 10. 整体架构与继承关系

```
ReentrantLock
    └── Sync extends AQS        ← 锁的核心逻辑
            ├── NonfairSync     ← 非公平锁实现
            └── FairSync        ← 公平锁实现

使用委托模式：
  ReentrantLock.lock() → sync.lock()
  ReentrantLock.unlock() → sync.release(1)
```

```java
public class ReentrantLock implements Lock, java.io.Serializable {

    private final Sync sync; // 核心

    // 默认非公平锁
    public ReentrantLock() {
        sync = new NonfairSync();
    }

    // 可选择公平/非公平
    public ReentrantLock(boolean fair) {
        sync = fair ? new FairSync() : new NonfairSync();
    }

    // lock 委托给 sync
    public void lock() { sync.lock(); }

    // unlock 委托给 sync
    public void unlock() { sync.release(1); }
}
```

---

## 11. NonfairSync 非公平锁 lock/unlock

### 11.1 非公平锁 lock 源码

```java
static final class NonfairSync extends Sync {

    final void lock() {
        // ★ 关键：直接 CAS 抢锁，不管队列中是否有等待线程！
        if (compareAndSetState(0, 1))
            setExclusiveOwnerThread(Thread.currentThread()); // 设置持有者
        else
            acquire(1); // 抢失败，走 AQS 流程
    }

    // AQS 回调：尝试获取锁（非公平版本）
    protected final boolean tryAcquire(int acquires) {
        return nonfairTryAcquire(acquires);
    }
}
```

### 11.2 nonfairTryAcquire

```java
// Sync 中的共享实现
final boolean nonfairTryAcquire(int acquires) {
    final Thread current = Thread.currentThread();
    int c = getState();

    // ① state == 0 → 锁空闲
    if (c == 0) {
        // ★ 直接 CAS，不检查队列中是否有等待线程（非公平！）
        if (compareAndSetState(0, acquires)) {
            setExclusiveOwnerThread(current);
            return true;
        }
    }
    // ② 锁被当前线程持有 → 重入
    else if (current == getExclusiveOwnerThread()) {
        int nextc = c + acquires; // 重入计数 +1
        if (nextc < 0)
            throw new Error("Maximum lock count exceeded");
        setState(nextc); // 直接 set（不需要 CAS，已持有锁，无竞争）
        return true;
    }
    return false; // 锁被其他线程持有 → 失败
}
```

### 11.3 非公平锁 unlock（tryRelease）

```java
// Sync 中，公平和非公平共用同一个 tryRelease
protected final boolean tryRelease(int releases) {
    int c = getState() - releases;
    if (Thread.currentThread() != getExclusiveOwnerThread())
        throw new IllegalMonitorStateException();

    boolean free = false;
    // ① state 降为 0 → 完全释放（所有重入层级都退出）
    if (c == 0) {
        free = true;
        setExclusiveOwnerThread(null); // 清除持有者
    }
    setState(c);
    return free; // true 表示完全释放，AQS 会唤醒后继节点
}
```

---

## 12. FairSync 公平锁 lock/unlock

### 12.1 公平锁 lock 源码

```java
static final class FairSync extends Sync {

    final void lock() {
        // ★ 公平锁：没有抢先的 CAS，直接走 AQS 流程
        acquire(1);
    }

    // 公平版 tryAcquire
    protected final boolean tryAcquire(int acquires) {
        final Thread current = Thread.currentThread();
        int c = getState();

        if (c == 0) {
            // ★ 关键区别：先检查队列中是否有等待更久的线程
            if (!hasQueuedPredecessors() &&  // ← 非公平没有这个检查
                compareAndSetState(0, acquires)) {
                setExclusiveOwnerThread(current);
                return true;
            }
        }
        else if (current == getExclusiveOwnerThread()) {
            // 重入逻辑与非公平相同
            int nextc = c + acquires;
            if (nextc < 0)
                throw new Error("Maximum lock count exceeded");
            setState(nextc);
            return true;
        }
        return false;
    }
}
```

### 12.2 hasQueuedPredecessors —— 公平性的核心

```java
public final boolean hasQueuedPredecessors() {
    Node t = tail;
    Node h = head;
    Node s;
    // 返回 true 表示：有等待更久的线程
    // 条件：h != t（队列非空）且 head 的后继不是当前线程
    return h != t &&
        ((s = h.next) == null || s.thread != Thread.currentThread());
}
```

---

## 13. ReentrantLock 的可重入实现

```java
// 可重入的关键：state 表示重入次数

// 第一次获取锁：
state: 0 → 1
setExclusiveOwnerThread(current)

// 第二次 lock（重入）：
current == getExclusiveOwnerThread()  // true
state: 1 → 2  // 递增，不阻塞

// 第三次 lock（重入）：
state: 2 → 3

// 第一次 unlock：
state: 3 → 2  // free = false，不释放锁

// 第二次 unlock：
state: 2 → 1  // free = false

// 第三次 unlock：
state: 1 → 0  // free = true，setExclusiveOwnerThread(null)，唤醒后继

⚠️ 重入几次就要 unlock 几次，否则 state 不为 0，锁不会释放！
```

---

## 14. lockInterruptibly / tryLock

### 14.1 lockInterruptibly —— 响应中断的锁

```java
public void lockInterruptibly() throws InterruptedException {
    sync.acquireInterruptibly(1); // AQS 的可中断版 acquire
}

// AQS 中的实现：
public final void acquireInterruptibly(int arg) throws InterruptedException {
    if (Thread.interrupted())
        throw new InterruptedException();
    if (!tryAcquire(arg))
        doAcquireInterruptibly(arg); // 可中断版的排队等待
}

// 与普通 acquire 的区别：
// acquireQueued:          中断仅设标志，不抛异常
// doAcquireInterruptibly: 检测到中断立即抛 InterruptedException
```

### 14.2 tryLock —— 非阻塞尝试

```java
// tryLock()：立即返回，不阻塞
public boolean tryLock() {
    return sync.nonfairTryAcquire(1); // 注意：即使是公平锁也用非公平尝试
}

// tryLock(long timeout, TimeUnit unit)：超时尝试
public boolean tryLock(long timeout, TimeUnit unit) throws InterruptedException {
    return sync.tryAcquireNanos(1, unit.toNanos(timeout));
}

// 使用示例：避免死锁
if (lock.tryLock(5, TimeUnit.SECONDS)) {
    try {
        // 执行操作
    } finally {
        lock.unlock();
    }
} else {
    // 超时未获取锁，执行降级逻辑
}
```

---

# Part 4 — 综合对比与面试题

## 15. synchronized vs ReentrantLock

| 特性 | synchronized | ReentrantLock |
|------|-------------|---------------|
| 实现层面 | JVM 内置，字节码级别 | Java 语言层，AQS |
| 可重入 | ✅ | ✅ |
| 公平锁 | ❌ 非公平 | ✅ 可配置 |
| 条件变量 | `wait()/notify()`（只有1个等待队列） | `Condition`（可多个等待队列） |
| 响应中断 | ❌ 不可响应 | ✅ `lockInterruptibly()` |
| 超时获取 | ❌ | ✅ `tryLock(timeout)` |
| 非阻塞尝试 | ❌ | ✅ `tryLock()` |
| 锁释放 | 自动（退出同步块） | 手动（必须 finally unlock） |
| 锁状态查询 | ❌ | ✅ `isLocked()`, `getQueueLength()` 等 |
| 性能 | JDK 6 之后差距不大 | 高竞争场景略好 |
| 锁升级 | ✅ 偏向→轻量级→重量级 | 无（全程 AQS） |
| 使用场景 | 简单同步、代码简洁 | 需要高级特性时 |

### 什么时候选 ReentrantLock？

```
需要以下特性时选 ReentrantLock：
  1. 公平锁
  2. 可中断等待
  3. 超时等待
  4. 多条件变量（如生产者/消费者需要两个条件）
  5. tryLock 的非阻塞尝试

其他情况优先选 synchronized：
  - 代码更简洁（无需手动 unlock）
  - JVM 可以做更多优化
  - 不容易出现忘记 unlock 的 bug
```

---

## 16. 常见面试题

### Q1: synchronized 的锁升级过程？

无锁 → 偏向锁 → 轻量级锁 → 重量级锁

- **偏向锁**：CAS 写入线程ID，同一线程重入无开销
- **轻量级锁**：创建 Lock Record，CAS 替换 Mark Word；多线程交替时高效
- **重量级锁**：进入 ObjectMonitor，线程被 OS 挂起，适合高竞争场景

JDK 15 起偏向锁默认禁用（JEP 374），JDK 18 彻底移除。

### Q2: 为什么 JDK 15 废弃了偏向锁？

1. 偏向锁的撤销（Revocation）需要 Stop-the-World，代价高
2. 现代应用大量使用并发容器（HashMap 等），偏向锁反而增加了撤销开销
3. 轻量级锁的 CAS 开销在现代 CPU 上已经很低，偏向锁优势不明显

### Q3: AQS 的 CLH 队列为什么是双向链表？

1. **prev 指针**：`shouldParkAfterFailedAcquire` 需要找到最近的非取消节点（前驱）
2. **next 指针**：`unparkSuccessor` 需要快速唤醒后继节点
3. 单向链表无法在 O(1) 内找到前驱，需要从 tail 往前扫

### Q4: 公平锁和非公平锁的区别和适用场景？

| | 公平锁 | 非公平锁 |
|---|--------|---------|
| 线程等待顺序 | FIFO，先等先得 | 随机，可能插队 |
| 吞吐量 | 低（频繁上下文切换） | 高（减少切换次数） |
| 饥饿 | 不会（保证顺序） | 可能（某线程一直插队） |
| 适用场景 | 每个线程必须被服务 | 高吞吐量、可容忍少量饥饿 |

### Q5: ReentrantLock 为什么 tryLock() 不管是否是公平锁都用非公平模式？

```java
public boolean tryLock() {
    return sync.nonfairTryAcquire(1); // FairSync 也调用这个
}
```

`tryLock()` 的语义是"尝试立即获取，不等待"。如果用公平版，发现队列有等待线程就要放弃，这不符合"尝试获取"的语义。在超时 `tryLock(timeout)` 中则使用了公平模式，尊重队列顺序。

### Q6: AQS 的 state 是如何保证可见性的？

`state` 是 `volatile int`，加上 `compareAndSetState` 使用 Unsafe 的 CAS 操作（底层是 `lock cmpxchg` 指令），保证：
1. **可见性**：volatile 读写内存屏障
2. **原子性**：CAS 保证 compare 和 swap 是原子的
3. **有序性**：volatile 禁止重排序

### Q7: LockSupport.park() 和 Thread.sleep() 的区别？

| | LockSupport.park() | Thread.sleep() |
|---|---|---|
| 中断响应 | 不抛异常，仅返回（保留中断标志） | 抛 InterruptedException（清除中断标志） |
| 唤醒方式 | unpark(Thread) 或 中断 | 超时 / 中断 |
| 调用条件 | 无需持有锁 | 无需持有锁 |
| 许可机制 | unpark 可以先于 park 调用 | sleep 必须在调用后等待 |

### Q8: 什么是虚假唤醒（Spurious Wakeup）？如何处理？

操作系统底层可能在没有 `signal/notify` 的情况下唤醒阻塞线程（虚假唤醒）。

```java
// 错误写法（if）：虚假唤醒后条件未满足就继续执行
if (queue.isEmpty())
    condition.await();
queue.poll();

// 正确写法（while）：唤醒后重新检查条件
while (queue.isEmpty())
    condition.await();
queue.poll();
```

### Q9: ReentrantLock 的锁如果忘记 unlock 会怎样？

锁永远不会被释放，等待该锁的线程将永久阻塞，造成**死锁**。

正确写法：

```java
lock.lock();
try {
    // 操作...
} finally {
    lock.unlock(); // 必须在 finally 中
}
```

### Q10: synchronized 和 volatile 的区别？

| | synchronized | volatile |
|---|---|---|
| 原子性 | ✅ 整个同步块 | ❌（只保证单个读/写的原子性） |
| 可见性 | ✅ | ✅ |
| 有序性 | ✅ | ✅（禁止重排序） |
| 阻塞 | 会阻塞其他线程 | 不阻塞 |
| 使用范围 | 方法 / 代码块 | 变量 |
| 适用场景 | 复合操作（check-then-act） | 单变量的状态标志 |

---

## 附录 A：锁相关重要工具类

| 工具类 | 基于 | 用途 |
|--------|------|------|
| `ReentrantLock` | AQS（独占） | 可重入互斥锁 |
| `ReentrantReadWriteLock` | AQS（独占+共享） | 读写分离锁 |
| `Semaphore` | AQS（共享） | 限流、资源池 |
| `CountDownLatch` | AQS（共享） | 一次性计数器 |
| `CyclicBarrier` | ReentrantLock + Condition | 循环屏障 |
| `Phaser` | AQS（增强版 CyclicBarrier） | 多阶段协同 |
| `StampedLock` | 自研（非 AQS） | 乐观读锁 |

## 附录 B：关键 LockSupport 方法

```java
// 阻塞当前线程
LockSupport.park();
LockSupport.park(Object blocker);       // blocker 用于监控诊断
LockSupport.parkNanos(long nanos);      // 限时阻塞
LockSupport.parkUntil(long deadline);   // 绝对时间限时阻塞

// 唤醒指定线程
LockSupport.unpark(Thread thread);
// ★ unpark 可以在 park 之前调用（许可机制）
// 如果先 unpark，后 park 会立即返回（不阻塞）
```

## 附录 C：Mark Word 锁状态速查

```
初始化对象（无锁）:   mark = [hashCode: ?, age: 0, biased: 0, lock: 01]
偏向锁:              mark = [threadId: TID, epoch: EE, age: ?, biased: 1, lock: 01]
轻量级锁:            mark = [LockRecord*: ADDR, lock: 00]
重量级锁:            mark = [Monitor*: ADDR, lock: 10]
GC 标记:             mark = [lock: 11]
```

---

> 本文档涵盖 synchronized 从 Mark Word 到 Monitor 的 JVM 级实现，AQS 的 CLH 队列设计与 state 状态机，以及 ReentrantLock 公平/非公平两种模式的完整源码。
> 建议按 **synchronized → AQS → ReentrantLock** 的顺序学习，AQS 理解了，ReentrantLock 只是一层薄薄的封装。
