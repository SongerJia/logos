# Java 并发同步工具源码深度解析

> 版本基准：JDK 8u60+（含 JDK 9~21 增强标注）  
> 涵盖：Future / FutureTask / CompletableFuture / CountDownLatch / CyclicBarrier / Semaphore / Exchanger / Phaser  
> 核心思想：**AQS 是底层骨架，每个工具都是在 AQS 之上的一层语义封装**

---

## 目录

- [Part 1 Future 与 FutureTask](#part-1-future-与-futuretask)
  - [1.1 Future 接口：五个方法](#11-future-接口五个方法)
  - [1.2 FutureTask 状态机](#12-futuretask-状态机)
  - [1.3 FutureTask.run — 执行任务](#13-futuretaskrun-执行任务)
  - [1.4 FutureTask.get — 阻塞等待](#14-futuretaskget-阻塞等待)
  - [1.5 FutureTask.cancel — 取消任务](#15-futuretaskcancel-取消任务)
  - [1.6 Future 的局限](#16-future-的局限)
- [Part 2 CompletableFuture：异步编程的终极方案](#part-2-completablefuture-异步编程的终极方案)
  - [2.1 整体架构与核心字段](#21-整体架构与核心字段)
  - [2.2 任务的创建：supplyAsync / runAsync](#22-任务的创建-supplyasync--runasync)
  - [2.3 结果的设置：complete / completeExceptionally](#23-结果的设置-complete--completeexceptionally)
  - [2.4 依赖链：thenApply / thenCompose / thenCombine](#24-依赖链-thenapply--thencompose--thencombine)
  - [2.5 异步变体：thenApplyAsync 与线程池规则](#25-异步变体-thenapplyasync-与线程池规则)
  - [2.6 thenApply vs thenCompose vs thenCombine 对比](#26-thenapply-vs-thencompose-vs-thencombine-对比)
  - [2.7 异常处理三件套](#27-异常处理三件套)
  - [2.8 allOf / anyOf：并行编排](#28-allof--anyof-并行编排)
  - [2.9 postComplete：依赖链的递归触发](#29-postcomplete-依赖链的递归触发)
  - [2.10 Treiber Stack 依赖栈详解](#210-treiber-stack-依赖栈详解)
  - [2.11 JDK 9+ 超时机制：orTimeout / completeOnTimeout](#211-jdk-9-超时机制-ortimeout--completeontimeout)
  - [2.12 CompletableFuture 完整使用范式](#212-completablefuture-完整使用范式)
- [Part 3 CountDownLatch：一次性倒计数门闩](#part-3-countdownlatch-一次性倒计数门闩)
  - [3.1 使用场景](#31-使用场景)
  - [3.2 基于 AQS 的实现原理](#32-基于-aqs-的实现原理)
  - [3.3 countDown 源码](#33-countdown-源码)
  - [3.4 await 源码](#34-await-源码)
  - [3.5 常见误用与最佳实践](#35-常见误用与最佳实践)
- [Part 4 CyclicBarrier：可重用的循环栅栏](#part-4-cyclicbarrier-可重用的循环栅栏)
  - [4.1 使用场景](#41-使用场景)
  - [4.2 核心字段与 Generation](#42-核心字段与-generation)
  - [4.3 await 源码（核心）](#43-await-源码核心)
  - [4.4 CyclicBarrier vs CountDownLatch 对比](#44-cyclicbarrier-vs-countdownlatch-对比)
  - [4.5 barrierAction 回调](#45-barrieraction-回调)
- [Part 5 Semaphore：信号量（许可计数器）](#part-5-semaphore-信号量许可计数器)
  - [5.1 使用场景](#51-使用场景)
  - [5.2 基于 AQS 的实现](#52-基于-aqs-的实现)
  - [5.3 acquire 源码（公平与非公平）](#53-acquire-源码公平与非公平)
  - [5.4 release 源码](#54-release-源码)
  - [5.5 公平 vs 非公平信号量](#55-公平-vs-非公平信号量)
  - [5.6 限流实战示例](#56-限流实战示例)
- [Part 6 Exchanger：线程间数据交换](#part-6-exchanger-线程间数据交换)
  - [6.1 使用场景](#61-使用场景)
  - [6.2 Slot + Arena 分层结构](#62-slot--arena-分层结构)
  - [6.3 exchange 源码流程](#63-exchange-源码流程)
- [Part 7 Phaser：灵活的阶段同步器](#part-7-phaser-灵活的阶段同步器)
  - [7.1 Phaser vs CyclicBarrier](#71-phaser-vs-cyclicbarrier)
  - [7.2 核心字段与 state 编码](#72-核心字段与-state-编码)
  - [7.3 arrive / arriveAndAwaitAdvance 源码](#73-arrive--arriveandawaitadvance-源码)
  - [7.4 动态注册与注销](#74-动态注册与注销)
  - [7.5 onAdvance 回调](#75-onadvance-回调)
- [Part 8 AQS 统一视角：所有工具的底层骨架](#part-8-aqs-统一视角所有工具的底层骨架)
  - [8.1 AQS state 在各工具中的语义](#81-aqs-state-在各工具中的语义)
  - [8.2 独占 vs 共享模式对应表](#82-独占-vs-共享模式对应表)
  - [8.3 一张图看清所有工具的底层联系](#83-一张图看清所有工具的底层联系)
- [Part 9 高频面试题 15 道](#part-9-高频面试题-15-道)
- [附录 A 并发同步工具速查表](#附录-a-并发同步工具速查表)
- [附录 B CountDownLatch / CyclicBarrier / Semaphore 使用场景决策树](#附录-b-使用场景决策树)

---

## Part 1 Future 与 FutureTask

### 1.1 Future 接口：五个方法

```java
public interface Future<V> {
    
    // 取消任务
    // mayInterruptIfRunning=true：如果任务正在执行，发送 interrupt
    // mayInterruptIfRunning=false：如果任务还没开始，就不执行了
    // 返回 true 表示取消成功；任务已完成/已取消/因其他原因无法取消 → 返回 false
    boolean cancel(boolean mayInterruptIfRunning);
    
    // 任务是否在完成前被取消
    boolean isCancelled();
    
    // 任务是否完成（正常完成、异常完成、取消 都算"完成"）
    boolean isDone();
    
    // 阻塞等待任务完成，返回结果
    // 如果任务被取消 → CancellationException
    // 如果任务异常 → ExecutionException（包装了实际异常）
    V get() throws InterruptedException, ExecutionException;
    
    // 超时等待
    // 超时 → TimeoutException
    V get(long timeout, TimeUnit unit)
            throws InterruptedException, ExecutionException, TimeoutException;
}
```

---

### 1.2 FutureTask 状态机

```java
// FutureTask 内部用 state 字段管理生命周期（volatile 保证可见性）
private volatile int state;

// 七种状态，严格有序：NEW → COMPLETING → NORMAL / EXCEPTIONAL
//                         NEW → CANCELLED
//                         NEW → INTERRUPTING → INTERRUPTED
private static final int NEW          = 0;  // 新建，任务还没执行
private static final int COMPLETING   = 1;  // 正在设置结果（瞬态，很快过渡到 NORMAL）
private static final int NORMAL       = 2;  // 正常完成
private static final int EXCEPTIONAL  = 3;  // 异常完成
private static final int CANCELLED    = 4;  // 被取消（任务还没开始，或 cancel(false))
private static final int INTERRUPTING = 5;  // 正在发送中断（瞬态）
private static final int INTERRUPTED  = 6;  // 已中断（cancel(true) 且任务正在运行）

// 状态转换图：
//
//   NEW ──→ COMPLETING ──→ NORMAL          (正常完成)
//         │
//         ├──→ EXCEPTIONAL                 (异常完成)
//         │
//         ├──→ CANCELLED                    (cancel(false) 或任务未开始时 cancel)
//         │
//         └─→ INTERRUPTING ──→ INTERRUPTED  (cancel(true) 且任务正在执行)
//
// COMPLETING 和 INTERRUPTING 是瞬态：
// 设置 result/exception 时先 CAS state→COMPLETING，再设值，再 CAS state→NORMAL
// 这两步之间极短，但此时 get() 仍应阻塞等待（不是最终态）
```

---

### 1.3 FutureTask.run — 执行任务

```java
public void run() {
    // ① CAS state 从 NEW→其他，保证只有一个线程能执行
    // 如果 state != NEW 或 CAS 失败 → 直接返回（防止重复执行）
    if (state != NEW ||
        !UNSAFE.compareAndSwapObject(this, runnerOffset, null, Thread.currentThread()))
        return;
    
    try {
        Callable<V> callable = this.callable;  // 保存局部变量防并发修改
        if (callable != null && state == NEW) {
            V result;
            boolean ran;
            try {
                result = callable.call();  // ② 执行 Callable
                ran = true;
            } catch (Throwable ex) {
                result = null;
                ran = false;
                // ③ 异常路径：CAS state→EXCEPTIONAL，保存异常
                setException(ex);
            }
            if (ran)
                // ④ 正常路径：CAS state→COMPLETING→NORMAL，保存结果
                set(result);
        }
    } finally {
        runner = null;  // 清除 runner 引用
        
        // ⑤ 处理中断：如果 state >= INTERRUPTING，等待中断完成
        int s = state;
        if (s >= INTERRUPTING)
            handlePossibleCancellationInterrupt(s);
    }
}

// set(result)：正常完成时的两步 CAS
protected void set(V v) {
    // 第一步：NEW → COMPLETING（瞬态，持有结果写入的"锁"）
    if (UNSAFE.compareAndSwapInt(this, stateOffset, NEW, COMPLETING)) {
        outcome = v;  // 保存结果到 outcome 字段
        // 第二步：COMPLETING → NORMAL（最终态）
        UNSAFE.putOrderedInt(this, stateOffset, NORMAL);  // lazySet，不立即刷新
        
        // ⑥ 唤醒所有等待线程（finishCompletion）
        finishCompletion();
    }
}

// setException(ex)：异常完成
protected void setException(Throwable t) {
    if (UNSAFE.compareAndSwapInt(this, stateOffset, NEW, COMPLETING)) {
        outcome = t;  // outcome 保存异常对象
        UNSAFE.putOrderedInt(this, stateOffset, EXCEPTIONAL);
        finishCompletion();
    }
}
```

---

### 1.4 FutureTask.get — 阻塞等待

```java
public V get() throws InterruptedException, ExecutionException {
    int s = state;
    // ① 如果还没完成，阻塞等待
    if (s <= COMPLETING)
        s = awaitDone(false, 0L);
    // ② 返回结果或抛异常
    return report(s);
}

// awaitDone：自旋 + LockSupport.park 阻塞
private int awaitDone(boolean timed, long nanos) throws InterruptedException {
    final long deadline = timed ? System.nanoTime() + nanos : 0L;
    WaitNode q = null;
    boolean queued = false;
    
    for (;;) {  // 自旋循环
        // ① 检查中断
        if (Thread.interrupted()) {
            removeWaiter(q);
            throw new InterruptedException();
        }
        
        int s = state;
        if (s > COMPLETING) {
            // ② 已完成（NORMAL/EXCEPTIONAL/CANCELLED/INTERRUPTED）
            if (q != null)
                q.thread = null;  // 清理 WaitNode
            return s;
        }
        else if (s == COMPLETING) {
            // ③ 瞬态 COMPLETING：结果正在写入，再自旋一次就好
            Thread.yield();  // 让出 CPU，等 CAS 完成
        }
        else if (q == null) {
            // ④ 第一次进入：创建 WaitNode
            q = new WaitNode();
        }
        else if (!queued) {
            // ⑤ WaitNode 入队（CAS 追加到 waiters 链表头部）
            queued = UNSAFE.compareAndSwapObject(this, waitersOffset, q.next = waiters, q);
        }
        else if (timed) {
            // ⑥ 超时等待：parkNanos
            nanos = deadline - System.nanoTime();
            if (nanos <= 0L) {
                removeWaiter(q);
                return state;
            }
            LockSupport.parkNanos(this, nanos);
        }
        else {
            // ⑦ 无限等待：park
            LockSupport.park(this);
        }
    }
}

// report：根据状态返回结果或抛异常
private V report(int s) throws ExecutionException {
    Object x = outcome;  // 正常结果或异常对象
    if (s == NORMAL)
        return (V)x;                  // 正常完成，返回结果
    if (s >= CANCELLED)
        throw new CancellationException();  // 被取消
    throw new ExecutionException((Throwable)x);  // 异常完成
}
```

**WaitNode 结构**：

```java
// FutureTask 内部等待节点（Treiber Stack，单向链表）
static final class WaitNode {
    volatile Thread thread;      // 等待的线程
    volatile WaitNode next;      // 下一个等待节点
    WaitNode() { thread = Thread.currentThread(); }
}

// waiters 是链表头指针，所有 get() 的线程以 Treiber Stack 方式入队
// finishCompletion() 从头遍历，unpark 每个线程
```

---

### 1.5 FutureTask.cancel — 取消任务

```java
public boolean cancel(boolean mayInterruptIfRunning) {
    // ① 只有 state == NEW 才能取消
    // mayInterruptIfRunning=false：CAS state NEW→CANCELLED
    // mayInterruptIfRunning=true：CAS state NEW→INTERRUPTING
    if (!(state == NEW &&
          UNSAFE.compareAndSwapInt(this, stateOffset, NEW,
              mayInterruptIfRunning ? INTERRUPTING : CANCELLED)))
        return false;  // 已经完成了，取消失败
    
    try {
        if (mayInterruptIfRunning) {
            // ② 中断正在执行的线程
            try {
                Thread t = runner;
                if (t != null)
                    t.interrupt();  // 发送 interrupt
            } finally {
                // ③ INTERRUPTING → INTERRUPTED（最终态）
                UNSAFE.putOrderedInt(this, stateOffset, INTERRUPTED);
            }
        }
    } finally {
        // ④ 唤醒所有等待线程
        finishCompletion();
    }
    return true;
}
```

---

### 1.6 Future 的局限

```
Future 的四大痛点：

❌ 1. 阻塞式获取结果
   get() 必须阻塞等待，无法回调/异步通知
   多个 Future 组合需要手动写循环等待

❌ 2. 无法链式组合
   FutureA 的结果作为 FutureB 的输入 → 需要手动 get() 再提交新任务
   没有类似 thenApply/map 的组合操作

❌ 3. 异常处理不友好
   ExecutionException 包装了实际异常，需要 getCause() 解包
   无法在链中间优雅地 handle 异常

❌ 4. 无法手动完成
   Future 结果由 Callable 决定，外部无法手动设置成功/失败

→ 这些痛点全部由 CompletableFuture 解决！
```

---

## Part 2 CompletableFuture：异步编程的终极方案

### 2.1 整体架构与核心字段

```java
public class CompletableFuture<T> implements Future<T>, CompletionStage<T> {

    // ★ 结果字段：保存正常值或异常对象
    // 用 volatile 保证可见性
    volatile Object result;  // null = 未完成; AltResult = null值封装; 其他 = 实际结果/异常
    
    // ★ 依赖栈：Treiber Stack，存储所有依赖此 Future 的 Completion 节点
    volatile Completion completions;  // 链表头指针
    
    // 内部 AltResult：用于封装 null 结果（因为 result==null 表示未完成）
    static final class AltResult {
        final Throwable ex;  // null 表示正常完成且值为 null
        AltResult(Throwable x) { this.ex = x; }
    }
    
    // 判断是否完成
    static final boolean isCancelled(Object r) {
        return (r instanceof AltResult) && ((AltResult)r).ex != null
            && ((AltResult)r).ex instanceof CancellationException;
    }
    
    static final boolean isCompletedExceptionally(Object r) {
        return r instanceof AltResult && ((AltResult)r).ex != null;
    }
    
    // 判断结果是否为 null 值（需要 AltResult 封装）
    static final Object encodeResult(Object r) {
        return r == null ? NIL : r;  // NIL = new AltResult(null)
    }
}
```

---

### 2.2 任务的创建：supplyAsync / runAsync

```java
// 四种创建方式：

// ① supplyAsync(Supplier) — 有返回值，用 ForkJoinPool.commonPool()
public static <U> CompletableFuture<U> supplyAsync(Supplier<U> supplier) {
    return asyncSupplyStage(AsyncSupply.ASYNC_POOL, supplier);
}

// ② supplyAsync(Supplier, Executor) — 有返回值，用自定义线程池
public static <U> CompletableFuture<U> supplyAsync(Supplier<U> supplier, Executor executor) {
    return asyncSupplyStage(executor, supplier);
}

// ③ runAsync(Runnable) — 无返回值，用 ForkJoinPool.commonPool()
public static CompletableFuture<Void> runAsync(Runnable runnable) {
    return asyncRunStage(AsyncSupply.ASYNC_POOL, runnable);
}

// ④ runAsync(Runnable, Executor) — 无返回值，用自定义线程池
public static CompletableFuture<Void> runAsync(Runnable runnable, Executor executor) {
    return asyncRunStage(executor, runnable);
}

// ★ asyncSupplyStage 源码（核心创建逻辑）
static <U> CompletableFuture<U> asyncSupplyStage(Executor e, Supplier<U> f) {
    if (f == null) throw new NullPointerException();
    CompletableFuture<U> d = new CompletableFuture<U>();  // 创建目标 CF
    e.execute(new AsyncSupply<U>(d, f));                  // 提交任务到线程池
    return d;                                              // 立即返回 CF（结果还没设置）
}

// ★ AsyncSupply 任务类
static final class AsyncSupply<T> extends ForkJoinTask<Void>
        implements Runnable, CompletableFuture.AsynchronousCompletionTask {
    final CompletableFuture<T> dep;   // 目标 CF
    final Supplier<T> fn;             // 供给函数
    
    public void run() {
        CompletableFuture<T> d; Supplier<T> f;
        if ((d = dep) != null && (f = fn) != null) {
            dep = null; fn = null;  // 清除引用防泄漏
            if (d.result == null) {  // 目标还没完成
                try {
                    d.completeValue(f.get());  // ★ 执行 Supplier，设置结果
                } catch (Throwable ex) {
                    d.completeThrowable(ex);   // 异常路径
                }
            }
            d.postComplete();  // ★ 触发依赖链执行
        }
    }
}

// completeValue / completeThrowable：
// CAS result 从 null → 实际值/异常，成功后调用 postComplete() 递归触发下游

static <T> boolean completeValue(CompletableFuture<T> t, T value) {
    return UNSAFE.compareAndSwapObject(t, RESULT, null,
            (value == null) ? NIL : value);
}

static <T> boolean completeThrowable(CompletableFuture<T> t, Throwable ex) {
    return UNSAFE.compareAndSwapObject(t, RESULT, null,
            new AltResult(ex));
}
```

---

### 2.3 结果的设置：complete / completeExceptionally

```java
// ★ 手动完成（外部可设置结果，这是 FutureTask 做不到的！）

// 正常完成
public boolean complete(T value) {
    return completeValue(this, value);  // CAS result null→value
    // 如果 result 已经不是 null（已完成）→ CAS 失败，返回 false
    // 否则 → CAS 成功，触发 postComplete() → 返回 true
}

// 异常完成
public boolean completeExceptionally(Throwable ex) {
    if (ex == null) throw new NullPointerException();
    return completeThrowable(this, ex);  // CAS result null→AltResult(ex)
}

// obtrudeValue / obtrudeException — 强制覆盖结果（不管是否已完成）
// 不用 CAS，直接 UNSAFE.putObject，慎用！
public void obtrudeValue(T value) {
    result = (value == null) ? NIL : value;
    postComplete();  // 仍然触发依赖链
}

// 判断是否完成
public boolean isDone() {
    return result != null;  // result 非 null = 已完成（正常/异常/取消）
}

// get — 阻塞等待
public T get() throws InterruptedException, ExecutionException {
    Object r;
    if ((r = result) == null)  // 未完成 → 等待
        r = waitingGet(true, 0L);  // Signaller + park
    return reportGet(r);  // 解包结果/异常
}

// join — 阻塞等待但不检查中断，异常直接抛 CompletionException（unchecked）
public T join() {
    Object r;
    if ((r = result) == null)
        r = waitingGet(false, 0L);
    return reportJoin(r);  // 不抛 InterruptedException
}
```

---

### 2.4 依赖链：thenApply / thenCompose / thenCombine

```java
// ===== thenApply — 同步映射（类似 Stream.map）=====
// 上游结果 → 函数 → 下游结果

public <U> CompletableFuture<U> thenApply(Function<? super T,? extends U> fn) {
    return uniApplyStage(null, fn);  // null = 在上游线程执行
}

public <U> CompletableFuture<U> thenApplyAsync(Function<? super T,? extends U> fn) {
    return uniApplyStage(ASYNC_POOL, fn);  // 在指定线程池执行
}

// ★ uniApplyStage 源码
static <U,T> CompletableFuture<U> uniApplyStage(
        Executor e, Function<? super T,? extends U> f) {
    if (f == null) throw new NullPointerException();
    CompletableFuture<U> d = new CompletableFuture<U>();  // 下游 CF
    
    // 如果上游已完成 → 立即执行（tryPush）
    Object r;
    if ((r = result) == null)
        // 上游未完成 → 创建 UniApply 节点，压入依赖栈
        d.unipush(new UniApply<T,U>(e, d, this, f));
    else
        // 上游已完成 → 直接在当前线程/指定线程池执行
        d.claim(e, new UniApply<T,U>(e, d, this, f));
    return d;
}

// ★ UniApply Completion 芡点
static final class UniApply<T,U> extends UniCompletion<T,U> {
    Function<? super T,? extends U> fn;  // 映射函数
    
    final CompletableFuture<U> tryFire(int mode) {
        CompletableFuture<T> a; CompletableFuture<U> d;
        if ((a = src) == null || (d = dep) == null
            || !d.uniApply(a, fn, mode > 0))  // 尝试执行
            return null;
        src = null; dep = null; fn = null;  // 清除引用
        return d.postFire(a, mode);  // 触发下游
    }
}

// ★ uniApply — 核心执行逻辑
final <U> boolean uniApply(CompletableFuture<T> a,
        Function<? super T,? extends U> fn, boolean claim) {
    Object r; Throwable x;
    if (a == null || (r = a.result) == null || r == NIL) return false;  // 上游未完成
    
    // 上游已完成，检查异常
    if (result != null) return true;  // 下游已完成（可能被其他线程抢先了）
    
    try {
        // 解包上游结果
        T t = (T)(r instanceof AltResult ? null : r);
        // ★ 执行映射函数
        U u = fn.apply(t);
        // 设置下游结果
        completeValue(u);
    } catch (Throwable ex) {
        completeThrowable(ex);
    }
    return true;
}

// ===== thenCompose — 异步 flatMap =====
// 上游结果 → 函数返回 CompletableFuture → 下游等待内层 CF 完成

public <U> CompletableFuture<U> thenCompose(
        Function<? super T, ? extends CompletionStage<U>> fn) {
    return uniComposeStage(null, fn);  // 同步版本
}

// ★ UniCompose 的 tryFire 逻辑比 UniApply 多一层：
// 1. 执行 fn.apply(t) 得到内层 CompletableFuture g
// 2. 如果 g 已完成 → 直接取结果设置到下游 d
// 3. 如果 g 未完成 → 把 d 作为 g 的依赖，等 g 完成后触发 d

// ===== thenCombine — 双源合并 =====
// 两个 CF 都完成 → BiFunction 合并两个结果

public <U,V> CompletableFuture<V> thenCombine(
        CompletionStage<? extends U> other,
        BiFunction<? super T,? super U,? extends V> fn) {
    return biApplyStage(null, other, fn);
}

// ★ BiApply 需要两个上游（src + snd）都完成才执行：
// 任一未完成 → 压入未完成那个的依赖栈
// 两个都完成 → 执行 fn.apply(t, u)
```

---

### 2.5 异步变体：thenApplyAsync 与线程池规则

```
线程池选择规则（关键面试题）：

┌─────────────────────────────────────────────────────────────┐
│ 方法名              │ 执行线程                              │
├─────────────────────────────────────────────────────────────┤
│ thenApply(fn)       │ ★ 在上游完成时的线程执行              │
│                     │   如果上游已完成 → 在调用线程执行      │
│ thenApplyAsync(fn)  │ 在 ForkJoinPool.commonPool() 执行     │
│ thenApplyAsync(fn,e)│ 在自定义 Executor e 执行              │
├─────────────────────────────────────────────────────────────┤
│ thenAccept(fn)      │ 同 thenApply，在上游线程              │
│ thenAcceptAsync     │ 同 thenApplyAsync                     │
├─────────────────────────────────────────────────────────────┤
│ thenRun(fn)         │ 同 thenApply，在上游线程              │
│ thenRunAsync        │ 同 thenApplyAsync                     │
└─────────────────────────────────────────────────────────────┤

★ 重要细节：thenApply（无 Async）在上游完成线程执行
  - supplyAsync 提交到 commonPool → thenApply 在 commonPool 线程执行
  - complete() 在主线程调用 → thenApply 在主线程执行
  - 上游已完成时调用 thenApply → 在调用 thenApply 的线程执行（立即执行）

★ 为什么要用 Async 变体？
  1. 避免在上游线程做耗时操作（阻塞上游的 postComplete 递归）
  2. 精确控制线程池（I/O 密集用 IO 线程池，CPU 密集用计算线程池）
  3. 防止链式操作全跑在 commonPool 线程（commonPool 是共享的）
```

---

### 2.6 thenApply vs thenCompose vs thenCombine 对比

```
                thenApply             thenCompose            thenCombine
                (同步 map)            (异步 flatMap)         (双源合并)
─────────────────────────────────────────────────────────────────────────
输入            T                     T                     T + U
函数签名        Function<T,U>         Function<T,CF<U>>     BiFunction<T,U,V>
输出            U                     U（等内层CF完成）      V
上游数量        1                     1                     2
嵌套CF          ❌ 不会嵌套           ★ 会展平              ❌ 不会嵌套
类比 Stream     .map()                .flatMap()            无直接对应

示例：

thenApply:
  CF<String> cf1 = CF.supplyAsync(() -> "hello");
  CF<Integer> cf2 = cf1.thenApply(s -> s.length());
  // cf2 = 5

thenCompose:
  CF<String> cf1 = CF.supplyAsync(() -> "hello");
  CF<Integer> cf2 = cf1.thenCompose(s -> CF.supplyAsync(() -> s.length()));
  // cf2 = 5（但 length() 在新线程池执行，异步链）

thenCombine:
  CF<Integer> cf1 = CF.supplyAsync(() -> 10);
  CF<Integer> cf2 = CF.supplyAsync(() -> 20);
  CF<Integer> cf3 = cf1.thenCombine(cf2, (a, b) -> a + b);
  // cf3 = 30（等 cf1 和 cf2 都完成）
```

---

### 2.7 异常处理三件套

```java
// ===== exceptionally — 只处理异常，类似 catch =====
public CompletableFuture<T> exceptionally(Function<Throwable, ? extends T> fn) {
    return uniExceptionallyStage(null, fn);
}

// 源码逻辑：
// 上游正常完成 → 透传结果到下游（fn 不执行）
// 上游异常完成 → fn.apply(ex) → 下游结果

// 示例：
CF.supplyAsync(() -> { throw new RuntimeException("error"); })
  .exceptionally(ex -> "fallback")    // 返回 "fallback"
  .thenApply(s -> s.length());        // 返回 8

// ===== handle — 正常+异常都触发，类似 try-catch-finally =====
public <U> CompletableFuture<U> handle(BiFunction<? super T, Throwable, ? extends U> fn) {
    return uniHandleStage(null, fn);
}

// 源码逻辑：
// 无论上游正常还是异常 → fn.apply(result, ex) 都执行
// ex == null 表示正常完成

// 示例：
CF.supplyAsync(() -> "hello")
  .handle((result, ex) -> {
      if (ex != null) return "fallback";
      return result + " world";
  });  // 返回 "hello world"

CF.supplyAsync(() -> { throw new RuntimeException(); })
  .handle((result, ex) -> {
      if (ex != null) return "fallback";
      return result + " world";
  });  // 返回 "fallback"

// ★ handle vs exceptionally 关键区别：
// handle 可以修改正常结果（类似 map + catch）
// exceptionally 只在异常时触发，正常结果原样透传

// ===== whenComplete — 正常+异常都触发，但透传结果 =====
public CompletableFuture<T> whenComplete(BiConsumer<? super T, ? super Throwable> action) {
    return uniWhenCompleteStage(null, action);
}

// 源码逻辑：
// fn.accept(result, ex) 执行（类似副作用）
// ★ 但结果不改变！异常也透传到下游
// 如果 action 本身抛异常 → 追加到上游异常（suppressed）或替代上游异常

// 示例：
CF.supplyAsync(() -> "hello")
  .whenComplete((result, ex) -> {
      System.out.println("result=" + result + ", ex=" + ex);
  })  // 打印 "result=hello, ex=null"，结果仍是 "hello"
  .thenApply(s -> s.length());  // 返回 5

// ★ 三件套对比表：
// ┌──────────────┬────────────┬──────────────┬──────────────┐
// │ 方法          │ 正常时执行  │ 异常时执行    │ 能否改变结果  │
// ├──────────────┼────────────┼──────────────┼──────────────┤
// │ exceptionally │ ❌          │ ✅            │ ✅（返回值）  │
// │ handle        │ ✅          │ ✅            │ ✅（返回值）  │
// │ whenComplete  │ ✅          │ ✅            │ ❌（透传）    │
// └──────────────┴────────────┴──────────────┴──────────────┘
```

---

### 2.8 allOf / anyOf：并行编排

```java
// ===== allOf — 等所有 CF 完成 =====
public static CompletableFuture<Void> allOf(CompletableFuture<?>... cfs) {
    return andTree(cfs, 0, cfs.length - 1);
}

// ★ andTree 源码：用树形结构组合多个 CF
// 两个 CF → BiRelay 合并
// 多个 CF → 递归二分合并（类似归并排序的树形结构）

// 为什么用树而不是链？
// 链式：CF1→CF2→CF3→...→CFn，每次只合并两个，触发链很长
// 树形：(CF1+CF2) + (CF3+CF4) + ...，并行触发，postComplete 递归深度 = log(n)

// 实际使用：
CF<Void> all = CF.allOf(cf1, cf2, cf3);
all.thenRun(() -> System.out.println("全部完成"));

// ★ 获取所有结果（allOf 返回 Void）：
List<CF<String>> cfs = List.of(cf1, cf2, cf3);
CF<Void> all = CF.allOf(cfs.toArray(new CF[0]));
CF<List<String>> results = all.thenApply(v ->
    cfs.stream().map(CF::join).collect(Collectors.toList()));  // join 安全（已全部完成）

// ===== anyOf — 任一 CF 完成 =====
public static CompletableFuture<Object> anyOf(CompletableFuture<?>... cfs) {
    return orTree(cfs, 0, cfs.length - 1);
}

// 返回最先完成的 CF 的结果（Object 类型）
// 其他 CF 仍在执行（anyOf 不取消其他 CF）

// 竞速场景：
CF<String> fastest = CF.anyOf(
    CF.supplyAsync(() -> queryService1()),
    CF.supplyAsync(() -> queryService2()),
    CF.supplyAsync(() -> queryService3())
);
fastest.thenAccept(result -> System.out.println("最快结果: " + result));
```

---

### 2.9 postComplete：依赖链的递归触发

```java
// ★ 这是 CompletableFuture 最核心的机制！
// 当一个 CF 完成时（result 被设置），需要触发所有依赖它的下游 CF

final void postComplete() {
    Completion h;
    // 从依赖栈头开始，逐个弹出并执行
    while ((h = completions) != null) {
        // CAS 弹出栈头
        if (!UNSAFE.compareAndSwapObject(this, COMPLETIONS, h, h.next))
            continue;  // CAS 失败（并发修改），重试
        
        // ★ tryFire 触发这个 Completion 节点
        CompletableFuture<?> d;
        if ((d = h.tryFire(NESTED)) == null)  // NESTED = 在 postComplete 递归中执行
            continue;  // 没触发（可能上游还没全完成，如 BiApply 需要两个源）
        
        // tryFire 返回了下游 CF，且下游也完成了
        // ★ 递归触发下游的 postComplete
        d.postComplete();  // 递归！
    }
}

// 执行模式（mode 参数）：
// SYNC    = 1  // 同步执行（调用线程直接 tryFire）
// ASYNC   = 2  // 异步执行（提交到线程池）
// NESTED  = 0  // 在 postComplete 递归中执行

// ★ postFire：Completion 芡点执行后的后处理
final CompletableFuture<?> postFire(CompletableFuture<?> a, int mode) {
    // 如果下游也完成了 → 触发下游的 postComplete
    if (mode == ASYNC) {
        // 异步模式：提交到线程池执行 postComplete
        a.postComplete();
        return null;
    }
    // 同步/嵌套模式：在当前线程继续
    return (result != null) ? this : null;
    // 如果 result != null → 返回 this，让上层 postComplete 递归触发
    // 如果 result == null → 返回 null，不触发（还没完成）
}
```

---

### 2.10 Treiber Stack 依赖栈详解

```java
// Treiber Stack = 无锁并发栈（CAS 入栈，CAS 弹出）
// 所有依赖此 CF 的 Completion 芡点以链表形式存储

// 入栈：unipush / bipush
final void unipush(Completion c) {
    if (c != null) {
        // ① CAS 压入栈头
        while (!UNSAFE.compareAndSwapObject(this, COMPLETIONS, completions, c))
            ;  // 自旋 CAS
        // ② 如果此 CF 已完成 → 立即 tryFire
        if (result != null) {
            c.tryFire(SYNC);  // 同步触发
        }
    }
}

// Treiber Stack 为什么适合并发场景？
// 1. 无锁入栈：CAS 操作，多线程可以同时 push 不同 Completion
// 2. 弹出与执行：postComplete 中 CAS 弹出，成功线程负责 tryFire
// 3. 失败线程：CAS 失败说明其他线程已弹出，继续循环取下一个

// 依赖栈结构示例：
// CF_A 完成后需要触发 CF_B、CF_C、CF_D
//
// completions 栈：
//   UniApply(A→B) → UniApply(A→C) → UniApply(A→D) → null
//
// postComplete 依次弹出：
//   1. 弹出 UniApply(A→B) → tryFire → B 完成 → B.postComplete()
//   2. 弹出 UniApply(A→C) → tryFire → C 完成 → C.postComplete()
//   3. 弹出 UniApply(A→D) → tryFire → D 完成 → D.postComplete()
```

---

### 2.11 JDK 9+ 超时机制：orTimeout / completeOnTimeout

```java
// JDK 9 新增（以前只能用 get(timeout) 阻塞等待）

// orTimeout — 超时后异常完成
public CompletableFuture<T> orTimeout(long timeout, TimeUnit unit) {
    if (unit == null) throw new NullPointerException();
    if (result == null) {
        // 创建一个延迟完成的 CF（ScheduledDelayer）
        CF<T> delayer = new CF<T>();
        // 延迟 timeout 后 → delayer.completeExceptionally(new TimeoutException())
        Delayer.delay(new Timeout(delayer, timeout, unit), timeout, unit);
        // orTree：此 CF 和 delayer 竞速
        // 此 CF 先完成 → 正常结果
        // delayer 先完成 → TimeoutException
        return orTree(this, delayer);
    }
    return this;  // 已完成，直接返回
}

// completeOnTimeout — 超时后返回默认值
public CompletableFuture<T> completeOnTimeout(T value, long timeout, TimeUnit unit) {
    if (unit == null) throw new NullPointerException();
    if (result == null) {
        CF<T> delayer = new CF<T>();
        Delayer.delay(new DelayedCompletion<T>(delayer, value, timeout, unit), timeout, unit);
        // 此 CF 先完成 → 正常结果
        // delayer 先完成 → value
        return orTree(this, delayer);
    }
    return this;
}

// ★ Delayer 内部实现：
// 用 ScheduledThreadExecutor（单线程）调度延迟任务
// static final ScheduledExecutorService delayer = Executors.newScheduledThreadPool(1, ...);

// 使用示例：
CF.supplyAsync(() -> slowRemoteCall())
  .orTimeout(3, TimeUnit.SECONDS)               // 3秒超时 → TimeoutException
  .exceptionally(ex -> "fallback")               // 超时降级
  .thenAccept(result -> process(result));
```

---

### 2.12 CompletableFuture 完整使用范式

```java
// ===== 范式1：串行异步链 =====
CF.supplyAsync(() -> getUserId(), ioPool)          // IO：查用户ID
  .thenApplyAsync(id -> getUserInfo(id), ioPool)   // IO：查用户信息
  .thenApplyAsync(info -> buildEmail(info), cpuPool)// CPU：构建邮件
  .thenApplyAsync(email -> sendEmail(email), ioPool)// IO：发邮件
  .exceptionally(ex -> {
      log.error("邮件发送失败", ex);
      return null;
  });

// ===== 范式2：并行汇总 =====
CF<String> cf1 = CF.supplyAsync(() -> queryDB1(), ioPool);
CF<String> cf2 = CF.supplyAsync(() -> queryDB2(), ioPool);
CF<String> cf3 = CF.supplyAsync(() -> queryCache(), ioPool);

CF.allOf(cf1, cf2, cf3)
  .thenApplyAsync(v -> {
      String r1 = cf1.join();
      String r2 = cf2.join();
      String r3 = cf3.join();
      return mergeResults(r1, r2, r3);
  }, cpuPool);

// ===== 范式3：竞速（最快返回） =====
CF<String> result = CF.anyOf(
    CF.supplyAsync(() -> callServiceA(), ioPool),
    CF.supplyAsync(() -> callServiceB(), ioPool)
).thenApply(obj -> (String) obj);

// ===== 范式4：超时降级 =====
CF.supplyAsync(() -> slowService())
  .orTimeout(2, TimeUnit.SECONDS)         // JDK 9+
  .completeOnTimeout("default", 2, TimeUnit.SECONDS)  // JDK 9+
  // JDK 8 替代方案：
  // CF.anyOf(slowServiceCF, CF.delayedExecutor(2, SECONDS).apply(() -> "default"))

// ===== 范式5：异常恢复链 =====
CF.supplyAsync(() -> primaryService())
  .exceptionally(ex -> fallbackService())    // 主服务失败 → 降级
  .handle((result, ex) -> {                  // 最终处理
      if (ex != null) return "error page";
      return result;
  });

// ===== 陷阱与注意 =====

// ❌ 1. 不要在 thenApply 中做阻塞操作
CF.supplyAsync(() -> data())
  .thenApply(d -> { Thread.sleep(5000); return process(d); });  // 阻塞上游线程！

// ✅ 改用 thenApplyAsync + 自定义线程池
CF.supplyAsync(() -> data())
  .thenApplyAsync(d -> { Thread.sleep(5000); return process(d); }, blockingPool);

// ❌ 2. 不要用 commonPool 做 IO（commonPool 线程数 = CPU核数-1）
// ✅ 用自定义线程池（IO 线程数可以远大于 CPU 核数）

// ❌ 3. 不要在 CF 链中吞掉异常
CF.supplyAsync(() -> throwException())
  .thenApply(x -> x + 1)  // 不会执行（上游异常透传）
  .thenApply(x -> x + 2)  // 不会执行
  .whenComplete((r, ex) -> {});  // ex 不为 null，但没有处理！

// ✅ 加 exceptionally 或 handle
```

---

## Part 3 CountDownLatch：一次性倒计数门闩

### 3.1 使用场景

```
场景1：主线程等待 N 个子任务完成
  ├── 多线程并发初始化资源
  ├── 并行执行多个查询后汇总
  └── 单元测试中等待异步操作完成

场景2：子线程等待主线程准备完毕
  ├── 运动会发令枪（所有运动员等待裁判）
  └── 数据加载完毕后开始处理
```

---

### 3.2 基于 AQS 的实现原理

```java
// CountDownLatch 内部持有一个 Sync（extends AQS）
// AQS.state = 初始计数值

// ★ 关键设计：
// state 表示剩余计数值
// countDown() → state - 1（releaseShared）
// await()     → state == 0 时放行，否则阻塞（acquireSharedInterruptibly）

public class CountDownLatch {
    private final Sync sync;
    
    public CountDownLatch(int count) {
        if (count < 0) throw new IllegalArgumentException("count < 0");
        this.sync = new Sync(count);  // AQS.state = count
    }
    
    // ★ Sync 实现
    private static final class Sync extends AbstractQueuedSynchronizer {
        Sync(int count) {
            setState(count);  // 设置 AQS.state = count
        }
        
        int getCount() {
            return getState();  // 返回当前计数值
        }
        
        // ★ 尝试获取共享锁：state == 0 时成功（所有 countDown 完成）
        protected int tryAcquireShared(int acquires) {
            return (getState() == 0) ? 1 : -1;
            // 返回 >= 0 → 获取成功，不阻塞
            // 返回 < 0  → 获取失败，进入 CLH 队列阻塞
        }
        
        // ★ 尝试释放共享锁：state - 1
        protected boolean tryReleaseShared(int releases) {
            for (;;) {  // 自旋 CAS
                int c = getState();
                if (c == 0)
                    return false;  // 已经归零，不能再减
                int nextc = c - 1;
                if (compareAndSetState(c, nextc))  // CAS state
                    return nextc == 0;  // ★ 归零时返回 true → 触发 doReleaseShared 唤醒所有等待线程
            }
        }
    }
}
```

---

### 3.3 countDown 源码

```java
public void countDown() {
    sync.releaseShared(1);  // AQS.releaseShared
}

// AQS.releaseShared 源码（调用链）：
public final boolean releaseShared(int arg) {
    // ① 尝试释放：Sync.tryReleaseShared(1) → state - 1
    if (sync.tryReleaseShared(1)) {
        // ② state 归零 → 唤醒所有等待线程
        doReleaseShared();
        return true;
    }
    return false;
}

// ★ doReleaseShared：唤醒 CLH 队列中的所有等待线程
private void doReleaseShared() {
    for (;;) {
        Node h = head;
        if (h != null && h != tail) {
            int ws = h.waitStatus;
            if (ws == Node.SIGNAL) {
                // head 状态为 SIGNAL → 唤醒后继节点
                if (!compareAndSetWaitStatus(h, Node.SIGNAL, 0))
                    continue;  // CAS 失败重试
                LockSupport.unpark(h.waitingThread);  // unpark 后继线程
            }
            else if (ws == 0 && !compareAndSetWaitStatus(h, 0, Node.PROPAGATE))
                continue;  // 传播模式
        }
        if (h == head)  // head 没变 → 退出
            break;
    }
    // ★ 共享模式：唤醒一个线程后，该线程也会尝试唤醒后续线程（传播唤醒）
}
```

---

### 3.4 await 源码

```java
public void await() throws InterruptedException {
    sync.acquireSharedInterruptibly(1);  // AQS.acquireSharedInterruptibly
}

// AQS.acquireSharedInterruptibly 源码：
public final void acquireSharedInterruptibly(int arg) throws InterruptedException {
    // ① 检查中断
    if (Thread.interrupted())
        throw new InterruptedException();
    
    // ② 尝试获取：Sync.tryAcquireShared → state == 0 ? 1 : -1
    if (tryAcquireShared(arg) < 0)
        // ③ state > 0 → 加入 CLH 队列，阻塞等待
        doAcquireSharedInterruptibly(arg);
}

// doAcquireSharedInterruptibly：
// 1. 创建 Node(SHARED) 加入 CLH 队列尾部
// 2. 自旋检查前驱是否 head
//    前驱是 head → tryAcquireShared
//    state == 0 → 获取成功 → setHead + propagate → 唤醒后续节点
//    state > 0  → 获取失败 → shouldParkAfterFailedAcquire → LockSupport.park

// ★ await 超时版本：
public boolean await(long timeout, TimeUnit unit) throws InterruptedException {
    return sync.tryAcquireSharedNanos(1, unit.toNanos(timeout));
}
```

---

### 3.5 常见误用与最佳实践

```java
// ❌ 误用1：countDown 次数不够 → await 永远阻塞
// 确保 countDown 被调用的次数 = 构造时传入的 count
// 在 try-finally 中调用 countDown！

ExecutorService pool = Executors.newFixedThreadPool(3);
CountDownLatch latch = new CountDownLatch(3);
for (int i = 0; i < 3; i++) {
    pool.submit(() -> {
        try {
            doWork();
        } finally {
            latch.countDown();  // ★ 必须在 finally 中！防异常导致 countDown 不执行
        }
    });
}
latch.await();  // 安全等待

// ❌ 误用2：在 await 中不设超时 → 如果某个线程卡死，主线程永远阻塞
// ✅ 加超时：
if (!latch.await(10, TimeUnit.SECONDS)) {
    log.warn("超时，部分任务未完成");
    // 降级处理
}

// ❌ 误用3：CountDownLatch 不可重用（一次性）
// countDown 归零后不能再重置
// 需要"可重用"的栅栏 → 用 CyclicBarrier

// ✅ 最佳实践：搭配 CompletableFuture 使用
List<CF<String>> tasks = ...;
CF.allOf(tasks.toArray(new CF[0])).join();  // 比 CountDownLatch 更简洁

// 但 CountDownLatch 的优势：
// - 不需要返回值时更轻量
// - 主线程等待子线程的语义更直观
// - 可以跨线程池使用（不依赖特定 Executor）
```

---

## Part 4 CyclicBarrier：可重用的循环栅栏

### 4.1 使用场景

```
场景1：多线程分步骤计算（每个步骤所有线程都完成后才进入下一步）
  ├── 多人协作游戏（回合制：每人走一步，全走完再下一回合）
  ├── 并行模拟（每轮迭代后汇总）

场景2：多线程数据加载（所有人到齐后一起处理）
  └── 类似 CountDownLatch 但需要重用
```

---

### 4.2 核心字段与 Generation

```java
public class CyclicBarrier {
    
    // ★ 锁对象（不是基于 AQS！用 ReentrantLock + Condition 实现）
    private final ReentrantLock lock = new ReentrantLock();
    
    // ★ 条件队列：线程到达栅栏后在此等待
    private final Condition trip = lock.newCondition();
    
    // 参与线程数（parties）
    private final int parties;
    
    // 栅栏动作：最后一个线程到达时执行（可选）
    private final Runnable barrierAction;
    
    // ★ Generation：代的概念（解决"可重用"的关键）
    private Generation generation = new Generation();
    
    // 当前代中已到达的线程数
    private int count;
    
    // Generation 类：标记栅栏的代
    private static class Generation {
        boolean broken = false;  // 栅栏是否被破坏（异常/超时/中断）
    }
    
    public CyclicBarrier(int parties, Runnable barrierAction) {
        if (parties <= 0) throw new IllegalArgumentException();
        this.parties = parties;
        this.barrierAction = barrierAction;
        this.count = parties;  // count 初始 = parties
    }
    
    public CyclicBarrier(int parties) {
        this(parties, null);  // 无 barrierAction
    }
}
```

---

### 4.3 await 源码（核心）

```java
public int await() throws InterruptedException, BrokenBarrierException {
    return dowait(false, 0L);  // 非超时版本
}

public int await(long timeout, TimeUnit unit)
        throws InterruptedException, BrokenBarrierException, TimeoutException {
    return dowait(true, unit.toNanos(timeout));  // 超时版本
}

// ★ dowait 源码（核心逻辑）
private int dowait(boolean timed, long nanos) throws InterruptedException,
        BrokenBarrierException, TimeoutException {
    
    final ReentrantLock lock = this.lock;
    lock.lock();  // ① 获取锁
    try {
        final Generation g = generation;  // ② 获取当前代
        
        // ③ 检查栅栏是否已破坏
        if (g.broken)
            throw new BrokenBarrierException();  // 之前有线程异常/超时/中断
        
        // ④ 检查中断
        if (Thread.interrupted()) {
            breakBarrier();  // ★ 破坏栅栏：设置 broken=true，唤醒所有等待线程
            throw new InterruptedException();
        }
        
        // ⑤ count - 1（已到达一个线程）
        int index = --count;
        
        // ★★★ ⑥ 如果 index == 0：最后一个线程到达！
        if (index == 0) {
            boolean ranAction = false;
            try {
                // 执行 barrierAction（如果有）
                final Runnable command = barrierAction;
                if (command != null)
                    command.run();  // 在最后一个到达的线程中执行
                ranAction = true;
                
                // ★ nextGeneration：唤醒所有等待线程 + 开启下一代
                trip.signalAll();  // 唤醒 Condition 队列所有线程
                nextGeneration();  // 重置 count 和 generation
                
                return 0;  // 返回到达索引
            } finally {
                if (!ranAction)
                    breakBarrier();  // barrierAction 异常 → 破坏栅栏
            }
        }
        
        // ★★★ ⑦ index > 0：非最后一个线程 → 等待
        for (;;) {
            try {
                if (!timed)
                    trip.await();  // ★ 无限等待（Condition.await）
                else if (nanos > 0L)
                    nanos = trip.awaitNanos(nanos);  // ★ 超时等待
            } catch (InterruptedException ie) {
                // 等待期间被中断
                if (g == generation && !g.broken) {
                    breakBarrier();  // 破坏栅栏
                    throw ie;
                } else {
                    // 已经进入下一代了（正常完成），设置中断标记
                    Thread.currentThread().interrupt();
                }
            }
            
            // ⑧ 检查退出条件
            if (g.broken)
                throw new BrokenBarrierException();  // 栅栏被破坏
            
            if (g != generation)
                return index;  // ★ 代已更新 → 正常通过栅栏，返回到达索引
            
            if (timed && nanos <= 0L) {
                breakBarrier();  // 超时 → 破坏栅栏
                throw new TimeoutException();
            }
        }
    } finally {
        lock.unlock();  // ⑨ 释放锁
    }
}

// ★ nextGeneration：开启下一代
private void nextGeneration() {
    trip.signalAll();  // 唤醒所有等待线程
    count = parties;   // 重置计数
    generation = new Generation();  // 新建 Generation 对象
}

// ★ breakBarrier：破坏栅栏
private void breakBarrier() {
    generation.broken = true;  // 标记破坏
    count = parties;           // 重置计数（下次可用）
    trip.signalAll();          // 唤醒所有等待线程（它们会抛 BrokenBarrierException）
}
```

---

### 4.4 CyclicBarrier vs CountDownLatch 对比

```
┌──────────────────┬─────────────────────┬─────────────────────┐
│ 特性              │ CountDownLatch       │ CyclicBarrier       │
├──────────────────┼─────────────────────┼─────────────────────┤
│ 可重用            │ ❌ 一次性             │ ✅ 可重用（自动代切换）│
│ 计数方向          │ 倒计数（N→0）        │ 正计数（0→N）        │
│ 等待方            │ 主线程 await         │ 所有线程都 await     │
│ 触发方            │ 子线程 countDown     │ 最后一个线程到达触发  │
│ 基于              │ AQS（共享模式）      │ ReentrantLock+Condition│
│ 异常处理          │ 异常不影响其他线程    │ ★ 一个线程异常/超时    │
│                  │                     │ → 整个栅栏 broken     │
│ barrierAction    │ ❌                   │ ✅ 最后到达线程执行    │
│ 参与线程数        │ 动态（countDown N次）│ 固定（构造时指定）     │
└──────────────────┴─────────────────────┴─────────────────────┘

★ 核心区别：
1. CountDownLatch 是"一个等N个"（主线程等子线程）
2. CyclicBarrier 是"N个互相等"（所有线程互相等待）

3. CyclicBarrier 一个线程异常会破坏整个栅栏
   CountDownLatch 一个线程异常不影响其他线程等待（countDown 在 finally 中就行）

4. CyclicBarrier 可重用：每轮自动重置
   CountDownLatch 不可重用：归零后就是废的
```

---

### 4.5 barrierAction 回调

```java
// barrierAction 在最后一个到达的线程中执行
// 用途：每轮汇总计算结果、切换数据源等

CyclicBarrier barrier = new CyclicBarrier(3, () -> {
    System.out.println("所有线程到达，开始汇总...");
    mergeResults();  // 在最后一个线程中执行
});

// 示例：多轮迭代计算
for (int round = 0; round < 5; round++) {
    // 每个线程做一轮计算，到达栅栏后汇总，然后开始下一轮
    barrier.await();  // 等所有人完成当前轮
    // 汇总结果由 barrierAction 处理
    // 自动进入下一代，开始下一轮
}
```

---

## Part 5 Semaphore：信号量（许可计数器）

### 5.1 使用场景

```
场景1：限流（控制并发访问数）
  ├── 数据库连接池（最多10个并发连接）
  ├── 接口限流（最多100个并发请求）
  └── 文件下载限速

场景2：资源池化
  ├── 对象池（最多N个对象同时使用）
  └── 停车场模型（车位有限）
```

---

### 5.2 基于 AQS 的实现

```java
public class Semaphore implements java.io.Serializable {
    private final Sync sync;
    
    // ★ 两种 Sync 实现：
    // NonfairSync — 非公平信号量（默认）
    // FairSync    — 公平信号量
    
    // AQS.state = 可用许可数（permits）
    
    // acquire(n) → state - n（获取 n 个许可）
    // release(n) → state + n（释放 n 个许可）
    
    public Semaphore(int permits) {
        sync = new NonfairSync(permits);  // 默认非公平
    }
    
    public Semaphore(int permits, boolean fair) {
        sync = fair ? new FairSync(permits) : new NonfairSync(permits);
    }
    
    // ★ Sync 实现
    abstract static class Sync extends AbstractQueuedSynchronizer {
        Sync(int permits) {
            setState(permits);  // AQS.state = permits
        }
        
        // ★ 非公平获取：直接 CAS state - acquires，不管 CLH 队列
        final int nonfairTryAcquireShared(int acquires) {
            for (;;) {
                int available = getState();        // 当前可用许可数
                int remaining = available - acquires; // 减去需要的
                if (remaining < 0 ||               // 不够 → 返回负数
                    compareAndSetState(available, remaining))  // CAS 减
                    return remaining;  // >=0 成功，<0 失败
            }
        }
        
        // ★ 释放：state + releases
        protected boolean tryReleaseShared(int releases) {
            for (;;) {
                int current = getState();
                int next = current + releases;
                if (next < current)  // 溢出
                    throw new Error("Maximum permit count exceeded");
                if (compareAndSetState(current, next))  // CAS 加
                    return true;
            }
        }
    }
    
    // ★ FairSync：公平获取，检查 CLH 队列中是否有前驱
    static final class FairSync extends Sync {
        protected int tryAcquireShared(int acquires) {
            for (;;) {
                // ★ 先检查是否有排队线程（公平性保证）
                if (hasQueuedPredecessors())
                    return -1;  // 有排队 → 直接失败，不抢
                int available = getState();
                int remaining = available - acquires;
                if (remaining < 0 ||
                    compareAndSetState(available, remaining))
                    return remaining;
            }
        }
    }
    
    // ★ NonfairSync：非公平获取
    static final class NonfairSync extends Sync {
        protected int tryAcquireShared(int acquires) {
            return nonfairTryAcquireShared(acquires);  // 直接 CAS，不管队列
        }
    }
}
```

---

### 5.3 acquire 源码（公平与非公平）

```java
// acquire(1) — 获取1个许可
public void acquire() throws InterruptedException {
    sync.acquireSharedInterruptibly(1);  // AQS 共享模式获取
}

// acquire(n) — 获取n个许可
public void acquire(int permits) throws InterruptedException {
    if (permits < 0) throw new IllegalArgumentException();
    sync.acquireSharedInterruptibly(permits);
}

// AQS.acquireSharedInterruptibly 流程：
// 1. tryAcquireShared(arg)
//    FairSync: hasQueuedPredecessors() → 有排队返回-1 → 否则 CAS state-acquires
//    NonfairSync: 直接 CAS state-acquires
// 2. 返回 >= 0 → 获取成功
// 3. 返回 < 0 → 进入 CLH 队列阻塞等待

// ★ tryAcquire — 不等待的获取（立即返回）
public boolean tryAcquire() {
    return sync.nonfairTryAcquireShared(1) >= 0;  // 非公平尝试
}

// ★ tryAcquire(long timeout, TimeUnit unit) — 超时获取
public boolean tryAcquire(long timeout, TimeUnit unit) throws InterruptedException {
    return sync.tryAcquireSharedNanos(1, unit.toNanos(timeout));
}
```

---

### 5.4 release 源码

```java
// release(1) — 释放1个许可
public void release() {
    sync.releaseShared(1);
}

// release(n) — 释放n个许可
public void release(int permits) {
    if (permits < 0) throw new IllegalArgumentException();
    sync.releaseShared(permits);
}

// AQS.releaseShared 流程：
// 1. tryReleaseShared(releases) → CAS state + releases
// 2. 成功 → doReleaseShared → 唤醒 CLH 队列中的等待线程

// ★ 重要：release 可以超过初始 permits 数
// Semaphore(5) 初始5个许可
// acquire(3) → state=2
// release(5) → state=7  ← 现在有7个许可了！
// 这在某些场景是合法的（动态增加许可数）
// 如果不允许 → 用 drainPermissions() 检查
```

---

### 5.5 公平 vs 非公平信号量

```
┌──────────────────┬─────────────────────┬─────────────────────┐
│ 特性              │ FairSemaphore       │ NonfairSemaphore    │
├──────────────────┼─────────────────────┼─────────────────────┤
│ 获取顺序          │ FIFO（先进先出）     │ 不保证，可能插队     │
│ 吞吐量            │ 较低（有队列检查）   │ ★ 较高（直接CAS）    │
│ 防饥饿            │ ✅                   │ ❌ 可能饥饿          │
│ 适用场景          │ 严格公平要求         │ ★ 大多数场景         │
└──────────────────┴─────────────────────┴─────────────────────┘

★ 实际开发中，非公平（默认）几乎总是更好的选择：
- 吞吐量更高（减少了线程切换开销）
- "刚释放的许可被新线程拿走"是正常行为
- 饥饿在实际中极少发生
```

---

### 5.6 限流实战示例

```java
// 示例：数据库连接限流（最多10个并发查询）
Semaphore dbSemaphore = new Semaphore(10);  // 10个许可

public List<Result> query(String sql) throws InterruptedException {
    dbSemaphore.acquire();  // 获取许可（阻塞等待）
    try {
        return executeQuery(sql);  // 执行查询
    } finally {
        dbSemaphore.release();  // ★ 必须在 finally 中释放！
    }
}

// 示例：接口限流（非阻塞，超时快速失败）
Semaphore rateLimiter = new Semaphore(100);  // 100 QPS

public Response handleRequest(Request req) {
    if (!rateLimiter.tryAcquire(500, TimeUnit.MILLISECONDS)) {
        return Response.error("服务繁忙，请稍后重试");  // 快速降级
    }
    try {
        return process(req);
    } finally {
        rateLimiter.release();
    }
}

// ★ Semaphore + CompletableFuture 组合：
Executor ioPool = new ThreadPoolExecutor(
    50, 50, 0L, SECONDS, new LinkedBlockingQueue<>(),
    r -> new Thread(r, "io-worker"));
Semaphore semaphore = new Semaphore(20);  // 最多20个并发IO

CF<List<Result>> allResults = CF.allOf(
    tasks.stream()
        .map(task -> CF.supplyAsync(() -> {
            semaphore.acquire();  // 获取许可
            try {
                return execute(task);
            } finally {
                semaphore.release();
            }
        }, ioPool))
        .toArray(CF[]::new)
).thenApply(v -> tasks.stream().map(CF::join).collect(Collectors.toList()));
```

---

## Part 6 Exchanger：线程间数据交换

### 6.1 使用场景

```
场景1：两个线程交换数据
  ├── 生产者-消费者交换缓冲区
  ├── 遗传算法（两个染色体交换基因片段）
  ├── 测试场景：线程A准备输入，线程B验证输出

特点：只支持两个线程之间交换，不是N个线程
```

---

### 6.2 Slot + Arena 分层结构

```java
public class Exchanger<V> {
    
    // ★ 高并发设计：Slot → Arena 分层
    // 单 Slot（ExchangeSlot）在低并发时足够
    // 高并发时扩展为 Arena（数组，多个 Slot 减少竞争）
    
    // arena 数组：每个元素是一个 Slot
    // Slot 是 Node 节点，包含：
    //   item — 线程要交换的数据
    //   match — 对方线程交换过来的数据
    
    // JDK 8 之后使用 Arena 分层：
    // arena = new Node[BOUND + 1]  // BOUND = 2^7 - 1 = 127
    // 每个 Slot 紧凑排列（@Contended 防伪共享）
    
    // 线程索引：每个线程通过 ThreadLocal 记录自己在 arena 中的位置
    private final Participant participant = new Participant();
    
    static final class Participant extends ThreadLocal<Integer> {
        public Integer initialValue() { return 0; }  // 初始位置 0（Slot 0）
    }
}
```

---

### 6.3 exchange 源码流程

```java
public V exchange(V x) throws InterruptedException {
    return doExchange(x, false, 0L);  // 非超时版本
}

public V exchange(V x, long timeout, TimeUnit unit) throws InterruptedException, TimeoutException {
    return doExchange(x, true, unit.toNanos(timeout));
}

// ★ doExchange 简化流程（实际源码极其复杂，这里提炼核心逻辑）：

// 1. 获取线程在 arena 中的位置 index
//    如果 index == 0（首次或低并发） → 尝试在 Slot 0 交换

// 2. 检查 Slot 是否有对方线程的数据：
//    a. Slot.match != null → 对方已经到达且已设置了数据 → 直接取 match
//    b. Slot.item == null → Slot 空的 → 把自己的 item CAS 设置进去，然后 park 等对方
//    c. Slot.item != null → 对方已经设置了 item → CAS 设置 match，unpark 对方线程

// 3. 如果 CAS 失败（竞争激烈） → 扩展 index，移动到 arena 中另一个 Slot
//    减少同一个 Slot 的竞争概率

// ★ 核心交换逻辑（伪代码）：
// 线程A到达：
//   slot.item = x_A  // CAS 设置自己的数据
//   LockSupport.park()  // 等待对方
//
// 线程B到达：
//   match = slot.item  // 取到 x_A
//   slot.item = null   // 清除
//   slot.match = x_B   // CAS 设置自己的数据作为匹配值
//   LockSupport.unpark(thread_A)  // 唤醒线程A
//
// 线程A被唤醒：
//   result = slot.match  // 取到 x_B
//   slot.match = null    // 清除

// ★ Arena 扩展：当 Slot 0 竞争激烈（CAS 连续失败）
// → 线程移动到 arena[1]、arena[2]... 等不同 Slot
// → 减少 CAS 冲突概率
// → 最多 arena[BOUND] 个 Slot
```

---

## Part 7 Phaser：灵活的阶段同步器

### 7.1 Phaser vs CyclicBarrier

```
┌──────────────────┬─────────────────────┬───────────────────────┐
│ 特性              │ CyclicBarrier       │ Phaser                │
├──────────────────┼─────────────────────┼───────────────────────┤
│ 阶段数            │ 1轮（手动重用）      │ ★ 多阶段（自动递增）   │
│ 参与者数          │ 固定（构造时指定）   │ ★ 动态（运行时注册/注销）│
│ 等待方式          │ await()             │ arriveAndAwaitAdvance │
│ 到达方式          │ await就到达+等待     │ arrive（只到达不等待） │
│ 回调              │ barrierAction       │ onAdvance（每阶段回调）│
│ 层级              │ ❌                   │ ★ 支持父子Phaser层级   │
│ 基于              │ ReentrantLock+Cond  │ ★ AQS 状态位编码       │
│ 异常处理          │ broken标记整个栅栏   │ ★ forceTermination    │
│ 等待超时          │ await(timeout)      │ awaitAdvanceInterruptibly│
└──────────────────┴─────────────────────┴───────────────────────┘

★ Phaser 是 JDK 7 引入的，是 CyclicBarrier 的增强版
  最大的优势：动态注册/注销参与者 + 多阶段自动推进
```

---

### 7.2 核心字段与 state 编码

```java
public class Phaser {
    // ★ state 是一个 long，用位编码保存所有信息
    // 不同于 AQS 的 int state，Phaser 用 long
    
    // state 的位布局：
    // ┌────────────────────┬────────────────────┬─────────────────────┐
    // │ 高32位：阶段号       │ 中16位：未到达数     │ 低16位：已注册数      │
    // │ phase               │ unarrived          │ parties             │
    // └────────────────────┴────────────────────┴─────────────────────┘
    //
    // state = (phase << 32) | (unarrived << 16) | parties
    //
    // 特殊值：
    //   parties == 0      → EMPTY（没有注册者）
    //   unarrived == 0    → 所有注册者都已到达，阶段即将推进
    //   state == -1       → TERMINATED（终止态）
    
    // 常量
    static final int MAX_PARTIES = 0xffff;  // 最大注册者数 65535
    static final int MAX_PHASE   = Integer.MAX_VALUE;  // 最大阶段号
    static final int EMPTY       = 1;  // unarrived=0 & parties=1（占位标记）
    
    // 核心字段
    private volatile long state;       // ★ 编码状态
    private final ReentrantLock lock;  // 注册/注销时的锁
    
    // 父子层级
    private final Phaser parent;       // 父 Phaser（可选）
    private final Phaser root;         // 根 Phaser
    
    // 等待队列（用 AtomicReference<QNode> 实现，不是 CLH 队列）
    private volatile AtomicReference<QNode> evenQ;  // 偶数阶段等待队列
    private volatile AtomicReference<QNode> oddQ;   // 奇数阶段等待队列
    
    // ★ 解码方法
    private static int unarrivedOf(long s) { return (int)(s & 0xffff); }      // 低16位
    private static int partiesOf(long s)   { return (int)((s >>> 16) & 0xffff); } // 中16位
    private static int phaseOf(long s)     { return (int)(s >>> 32); }            // 高32位
}
```

---

### 7.3 arrive / arriveAndAwaitAdvance 源码

```java
// arrive — 到达但不等待（只通知"我到了"，不阻塞）
public int arrive() {
    return doArrive(ONE_ARRIVAL);  // ONE_ARRIVAL = 1（只减unarrived）
}

// arriveAndDeregister — 到达并注销（退出后续阶段）
public int arriveAndDeregister() {
    return doArrive(ONE_ARRIVAL | ONE_DEREGISTER);  // 减unarrived + 减parties
}

// ★ doArrive 源码
private int doArrive(int adjust) {
    for (;;) {
        long s = state;
        int phase = phaseOf(s);
        if (phase < 0)  // 已终止
            return phase;
        
        int unarrived = unarrivedOf(s);
        if (unarrived == 0)  // 所有都已到达（此阶段正在推进）
            return phase;     // 直接返回当前阶段
        
        // ★ CAS state：state - adjust（减少 unarrived，可能还减 parties）
        if (U.compareAndSwapLong(this, STATE, s, s - adjust)) {
            if (unarrived == 1) {  // ★ 最后一个到达者！
                // 此阶段完成，推进到下一阶段
                long nextS = nextState(s);  // 计算下一阶段的 state
                
                // 调用 onAdvance 回调
                if (!onAdvance(phase, nextS))  // ★ onAdvance 返回 false → 继续
                    releaseWaiters(phase);  // 唤醒当前阶段的等待线程
                
                // 如果有父 Phaser → 通知父 Phaser
                if (parent != null)
                    parent.arrive();
                
                return phase;
            }
            return phase;  // 非最后一个，直接返回
        }
    }
}

// arriveAndAwaitAdvance — 到达并等待所有人到达
public int arriveAndAwaitAdvance() {
    // 先到达（arrive）
    int phase = doArrive(ONE_ARRIVAL);
    
    if (phase < 0)  // 已终止
        return phase;
    
    // 然后等待阶段推进
    return awaitAdvance(phase);
}

// ★ awaitAdvance 源码（等待指定阶段完成）
public int awaitAdvance(int phase) {
    if (phase < 0)  // 已终止
        return phase;
    
    for (;;) {
        long s = state;
        int p = phaseOf(s);
        if (p != phase)  // ★ 阶段已推进（p > phase）或已终止（p < 0）
            return p;
        
        // 阶段还没推进 → 加入等待队列
        QNode node = new QNode(this, phase, false, false, 0L);
        // 根据阶段奇偶性选择 evenQ 或 oddQ
        AtomicReference<QNode> queue = (phase & 1) == 0 ? evenQ : oddQ;
        
        // CAS 入队
        if (!queue.compareAndSet(null, node)) {
            // 队列已有等待者 → 用 spin + park 等待
            LockSupport.park(this);
        }
    }
}
```

---

### 7.4 动态注册与注销

```java
// ★ 这是 Phaser 最大的优势：运行时增减参与者

// register — 新增一个参与者
public int register() {
    return doRegister(1);
}

// bulkRegister — 批量注册
public int bulkRegister(int parties) {
    if (parties < 0) throw new IllegalArgumentException();
    if (parties == 0) return getPhase();  // 不注册
    return doRegister(parties);
}

// ★ doRegister 源码
private int doRegister(int registrations) {
    long adjustment = ((long)registrations << 16) + registrations;
    // adjustment = 增加 parties + 增加 unarrived
    
    for (;;) {
        long s = state;
        int phase = phaseOf(s);
        if (phase < 0)  // 已终止
            return phase;
        
        // ★ CAS state + adjustment
        if (U.compareAndSwapLong(this, STATE, s, s + adjustment)) {
            int unarrived = unarrivedOf(s + adjustment);
            if (unarrived == 1 && phaseOf(s) != phase) {
                // 注册后导致 unarrived=1 且阶段已推进 → 需要唤醒等待线程
                releaseWaiters(phase);
            }
            return phase;
        }
    }
}

// arriveAndDeregister — 到达并注销（减少 parties 和 unarrived）
// 适用于：线程完成工作后退出，后续阶段不再参与

// 示例：动态参与者
Phaser phaser = new Phaser(1);  // 只注册主线程
for (int i = 0; i < 10; i++) {
    phaser.register();  // 动态注册10个工作线程
    new Thread(() -> {
        doWork();
        phaser.arriveAndDeregister();  // 完成后注销
    }).start();
}
phaser.arriveAndAwaitAdvance();  // 主线程等待所有工作线程完成
```

---

### 7.5 onAdvance 回调

```java
// ★ onAdvance 在每个阶段推进时调用
// 返回 true → Phaser 终止（不再有下一阶段）
// 返回 false → 继续下一阶段

protected boolean onAdvance(int phase, int registeredParties) {
    return registeredParties == 0;  // 默认：没有注册者时终止
}

// 自定义 onAdvance：
Phaser phaser = new Phaser() {
    @Override
    protected boolean onAdvance(int phase, int registeredParties) {
        // 只执行3个阶段
        return phase >= 3 || registeredParties == 0;
    }
};

// ★ onAdvance 的用途：
// 1. 控制阶段总数（phase >= N 时终止）
// 2. 每阶段汇总（类似 CyclicBarrier 的 barrierAction）
// 3. 条件终止（registeredParties == 0 或满足特定条件）
```

---

## Part 8 AQS 统一视角：所有工具的底层骨架

### 8.1 AQS state 在各工具中的语义

```
┌───────────────────┬─────────────────────┬────────────────────┐
│ 工具               │ AQS.state 语义       │ state 变化方向      │
├───────────────────┼─────────────────────┼────────────────────┤
│ ReentrantLock      │ 锁持有次数           │ 加锁 +1，解锁 -1    │
│                    │ 0=未锁，1=锁定       │                    │
│                    │ >1=重入次数          │                    │
├───────────────────┼─────────────────────┼────────────────────┤
│ CountDownLatch     │ ★ 剩余倒计数         │ countDown -1       │
│                    │ 初始=N，归零=放行     │ 0时唤醒等待者       │
├───────────────────┼─────────────────────┼────────────────────┤
│ Semaphore          │ ★ 可用许可数         │ acquire -N         │
│                    │ 初始=permits         │ release +N         │
├───────────────────┼─────────────────────┼────────────────────┤
│ CyclicBarrier      │ ❌ 不用AQS           │ 用 Lock+Condition  │
│                    │ (ReentrantLock)      │                    │
├───────────────────┼─────────────────────┼────────────────────┤
│ Phaser             │ ❌ 用自己的long state │ 位编码 phase+parties│
│                    │ (不是AQS.state)      │                    │
├───────────────────┼─────────────────────┼────────────────────┤
│ FutureTask         │ ❌ 不用AQS           │ volatile int state │
│                    │ (自己的状态机)        │ 7种状态转换         │
├───────────────────┼─────────────────────┼────────────────────┤
│ CompletableFuture  │ ❌ 不用AQS           │ volatile Object    │
│                    │ (Treiber Stack)      │ result + completions│
├───────────────────┼─────────────────────┼────────────────────┤
│ Exchanger          │ ❌ 不用AQS           │ Slot/Arena Node    │
│                    │ (CAS + park)         │                    │
└───────────────────┴─────────────────────┴────────────────────┘

★ 总结：
- 用 AQS 的：ReentrantLock、CountDownLatch、Semaphore、ReentrantReadWriteLock
- 不用 AQS 的：CyclicBarrier（Lock+Condition）、Phaser（自己实现）、FutureTask/CF/Exchanger（CAS+park）
```

---

### 8.2 独占 vs 共享模式对应表

```
┌───────────────────┬────────────────────┬──────────────────────────────┐
│ 工具               │ AQS 模式            │ 原因                          │
├───────────────────┼────────────────────┼──────────────────────────────┤
│ ReentrantLock      │ ★ 独占（Exclusive） │ 只有一个线程持有锁             │
│ Semaphore          │ ★ 共享（Shared）    │ 多个线程可同时获取许可         │
│ CountDownLatch     │ ★ 共享（Shared）    │ 多个线程可同时 await 通过      │
│ ReentrantReadWrite │ ★ 独占+共享混合     │ 写锁独占，读锁共享             │
│ StampedLock        │ ❌ 不用AQS           │ 自己实现（乐观读+写锁）        │
└───────────────────┴────────────────────┴──────────────────────────────┘

★ 共享模式的传播唤醒（propagate）：
- Semaphore：一个线程 release → 唤醒一个等待线程 → 等待线程获取成功后又唤醒下一个
- CountDownLatch：state 归零 → 唤醒所有等待线程 → 所有线程同时通过

★ 独占模式的串行唤醒：
- ReentrantLock：一个线程 unlock → 唤醒一个等待线程 → 获取锁 → 其他继续等待
```

---

### 8.3 一张图看清所有工具的底层联系

```
                    ┌───────────────────┐
                    │     AQS 骨架       │
                    │  state + CLH队列   │
                    │  acquire / release │
                    └─────────┬─────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
     ┌────────┴───────┐ ┌────┴─────┐ ┌──────┴────────┐
     │  独占模式        │ │ 共享模式  │ │  不用AQS       │
     │  (Exclusive)    │ │(Shared) │ │                │
     └────────┬───────┘ └────┬─────┘ └──────┬────────┘
              │              │              │
     ┌────────┴───┐   ┌─────┴────┐  ┌──────┴──────────┐
     │ReentrantLock│   │Semaphore │  │CyclicBarrier     │
     │             │   │CountDown │  │Phaser            │
     │             │   │Latch     │  │FutureTask        │
     │             │   │RWLock   │  │CompletableFuture  │
     └─────────────┘   └──────────┘  │Exchanger         │
                                     └───────────────────┘

★ 所有工具都依赖一个底层机制：
   CAS（原子操作） + park/unpark（线程阻塞/唤醒）

   AQS 把这两个机制封装为统一骨架：
   - state 的 CAS 操作 → tryAcquire/tryRelease
   - CLH 队列 + park/unpark → 阻塞和唤醒

   不用 AQS 的工具也离不开 CAS + park/unpark：
   - CyclicBarrier：CAS（无） + Lock+Condition（底层也用 park）
   - FutureTask：CAS state + park/unpark（WaitNode Treiber Stack）
   - CompletableFuture：CAS result + Treiber Stack + park/unpark
   - Phaser：CAS long state + park/unpark
   - Exchanger：CAS item/match + park/unpark
```

---

## Part 9 高频面试题 15 道

**Q1：Future 和 CompletableFuture 的核心区别？**

> **A**：
> - `Future`：阻塞式获取结果（`get`）、无法链式组合、无法手动完成、异常处理不友好
> - `CompletableFuture`：非阻塞回调（`thenApply`等）、链式组合（`thenCompose`）、手动完成（`complete`）、异常处理链（`exceptionally/handle/whenComplete`）
> - `CompletableFuture` 实现了 `Future` 和 `CompletionStage`，是 `Future` 的增强版

---

**Q2：CompletableFuture 的 thenApply 和 thenApplyAsync 有什么区别？**

> **A**：
> - `thenApply(fn)`：在上游完成线程执行 fn（如果上游已完成 → 在调用线程执行）
> - `thenApplyAsync(fn)`：在 ForkJoinPool.commonPool 执行 fn
> - `thenApplyAsync(fn, executor)`：在指定线程池执行 fn
> - **注意**：无 Async 版本在上游线程执行，如果 fn 耗时，会阻塞上游的 `postComplete` 递归触发

---

**Q3：CompletableFuture 如何实现依赖链的触发？**

> **A**：用 **Treiber Stack** 存储所有依赖此 CF 的 Completion 芡点。当 CF 完成时（`result` 被设置），调用 `postComplete()` 从栈中逐个弹出 Completion 并 `tryFire` 执行。如果下游 CF 也完成了，递归调用 `postComplete` 触发更下游的节点。

---

**Q4：为什么 CompletableFuture 不用 AQS？**

> **A**：
> - AQS 设计用于"一等N"或"N互相等"的阻塞语义
> - CompletableFuture 是"异步回调"语义，不需要 CLH 队列阻塞
> - 用 Treiber Stack + CAS 更轻量：Completion 芡点不需要排队，只需在完成时被触发
> - `get()` 的阻塞等待用 Signaller + `LockSupport.park` 实现（比 AQS CLH 队列简单）

---

**Q5：CountDownLatch 和 CyclicBarrier 的核心区别？**

> **A**：
> 1. **可重用**：CountDownLatch 一次性（归零后废了）；CyclicBarrier 可重用（代切换自动重置）
> 2. **等待方式**：CountDownLatch 是"一个等N个"（主线程 await）；CyclicBarrier 是"N个互相等"（所有线程都 await）
> 3. **异常影响**：CountDownLatch 一个线程异常不影响其他线程；CyclicBarrier 一个线程异常/超时/中断会 **broken** 整个栅栏
> 4. **底层实现**：CountDownLatch 基于 AQS 共享模式；CyclicBarrier 基于 ReentrantLock+Condition
> 5. **回调**：CyclicBarrier 有 `barrierAction`；CountDownLatch 没有

---

**Q6：CountDownLatch 的 countDown 没被调用够次数会怎样？**

> **A**：`await()` 的线程会**永远阻塞**。最佳实践：
> 1. 在 `try-finally` 中调用 `countDown`（防异常漏调）
> 2. 使用 `await(timeout)` 加超时（防死锁）
> 3. 考虑用 `CompletableFuture.allOf` 替代（更简洁安全）

---

**Q7：CyclicBarrier 的 broken 是什么意思？如何修复？**

> **A**：
> - `broken` 表示栅栏被破坏：某个等待线程被中断、超时、或 `barrierAction` 抛异常
> - 破坏后所有等待线程抛 `BrokenBarrierException`
> - **修复**：调用 `reset()` 方法（重置 generation + count）
> - **注意**：`reset` 会在有线程等待时先破坏当前栅栏（`breakBarrier`），慎用

---

**Q8：Semaphore 公平和非公平的区别？**

> **A**：
> - 公平：`tryAcquireShared` 先检查 `hasQueuedPredecessors()`，有排队线程就不抢 → FIFO
> - 非公平：直接 CAS state-acquires，不管排队 → 可能插队
> - **默认非公平**，吞吐量更高。公平信号量防饥饿但吞吐低
> - `tryAcquire()` 方法**总是非公平**的（即使构造时指定了 fair）

---

**Q9：Semaphore 的 release 可以超过初始 permits 吗？**

> **A**：**可以**。`release` 增加的是 AQS.state，不受初始值限制。`Semaphore(5)` 初始5个许可，如果 `release(3)` 被多调了2次，state 就变成7。这在动态限流场景可能是有意为之；如果不想允许，需要额外逻辑控制。

---

**Q10：Phaser 相比 CyclicBarrier 有什么优势？**

> **A**：
> 1. **动态注册/注销**：运行时可以 `register()`/`arriveAndDeregister()`，不需要构造时固定参与者数
> 2. **多阶段自动推进**：阶段号自动递增（`phase++`），不需要手动 `reset()`
> 3. **分层**：支持父子 Phaser，子 Phaser 完成后通知父 Phaser
> 4. **灵活到达**：`arrive()` 只通知到达不等待；`arriveAndAwaitAdvance()` 到达并等待
> 5. **自定义终止**：`onAdvance` 回调决定何时终止

---

**Q11：CompletableFuture.allOf 返回 Void，怎么获取所有结果？**

> **A**：
> ```java
> List<CF<String>> cfs = List.of(cf1, cf2, cf3);
> CF<Void> all = CF.allOf(cfs.toArray(new CF[0]));
> CF<List<String>> results = all.thenApply(v ->
>     cfs.stream().map(CF::join).collect(Collectors.toList()));
> ```
> `allOf` 完成后所有 CF 都已完成，`join()` 不会阻塞，直接取结果。

---

**Q12：CompletableFuture 的异常会怎样传播？**

> **A**：
> - 异常会沿链**透传**到下游，直到被 `exceptionally/handle` 捕获
> - 中间的 `thenApply/thenCompose` **不会执行**（上游异常时跳过）
> - `whenComplete` **会执行**但异常不消化，继续透传
> - `get()` 抛 `ExecutionException`（包装实际异常）
> - `join()` 抛 `CompletionException`（unchecked，不检查中断）

---

**Q13：Exchanger 只支持两个线程吗？**

> **A**：**是的**。`Exchanger` 设计用于两个线程间交换数据。如果第三个线程调用 `exchange`，它会和其中一个等待线程交换，不是三方交换。多线程交换场景应该用 `Phaser` 或 `CyclicBarrier` + 共享数据结构。

---

**Q14：FutureTask 的 COMPLETING 瞬态有什么意义？**

> **A**：`COMPLETING` 是设置 `outcome` 字段时的"占位态"：
> - 先 CAS `state` NEW→COMPLETING（获取写入权）
> - 再写 `outcome = result`
> - 再 CAS `state` COMPLETING→NORMAL
> - 这两步 CAS 之间极短，但 `get()` 看到 `COMPLETING` 状态时知道结果即将写入，只需 `Thread.yield()` 等一下，不需要入队 park
> - 如果没有瞬态：`outcome` 写入和 `state` 更新之间的空隙可能导致 `get()` 读到 `NORMAL` 但 `outcome` 还是 null

---

**Q15：这些并发工具如何选择？**

> **A**：决策树：
> - 需要异步回调 → **CompletableFuture**（首选，功能最丰富）
> - 主线程等N个子任务 → **CountDownLatch**（简单一次性）
> - N个线程互相等待（需重用）→ **CyclicBarrier**（带 barrierAction）
> - 控制并发数 → **Semaphore**（限流/资源池）
> - 多阶段+动态参与者 → **Phaser**（CyclicBarrier 增强版）
> - 两个线程交换数据 → **Exchanger**（罕见场景）
> - 需要阻塞获取结果 → **FutureTask**（配合线程池 submit）

---

## 附录 A 并发同步工具速查表

| 工具 | JDK版本 | 基于 | 模式 | 可重用 | 核心方法 | 典型场景 |
|------|---------|------|------|--------|---------|---------|
| FutureTask | 1.5 | 自定义state | - | ❌ | get/cancel | 线程池submit返回值 |
| CompletableFuture | 1.8 | Treiber Stack | - | ✅ | supplyAsync/thenApply/complete | 异步编程首选 |
| CountDownLatch | 1.5 | AQS共享 | Shared | ❌ | countDown/await | 主线程等子任务 |
| CyclicBarrier | 1.5 | Lock+Condition | - | ✅ | await | 多线程互相等待 |
| Semaphore | 1.5 | AQS共享 | Shared | ✅ | acquire/release | 限流/资源池 |
| Exchanger | 1.5 | CAS+Slot/Arena | - | ✅ | exchange | 两线程交换数据 |
| Phaser | 1.7 | CAS+long state | - | ✅ | arrive/register | 多阶段+动态参与者 |

---

## 附录 B 使用场景决策树

```
需要同步/协调多个线程？
│
├── 异步回调式 → CompletableFuture（首选）
│   ├── 串行链：thenApply/thenCompose
│   ├── 并行汇总：allOf
│   ├── 竞速：anyOf
│   └── 超时：orTimeout（JDK9+）
│
├── 阻塞等待式
│   │
│   ├── 一个等N个
│   │   ├── 一次性 → CountDownLatch
│   │   ├── 需返回值 → FutureTask / CompletableFuture.allOf
│   │
│   ├── N个互相等
│   │   ├── 固定参与者 + 需重用 → CyclicBarrier
│   │   ├── 动态参与者 + 多阶段 → Phaser
│   │   ├── 两线程交换数据 → Exchanger
│   │
│   ├── 控制并发数
│   │   ├── 限流 → Semaphore（acquire/release）
│   │   ├── 资源池 → Semaphore + 对象池
│
├── 锁式（互斥）
│   ├── 简单互斥 → synchronized
│   ├── 可重入+可中断 → ReentrantLock
│   ├── 读写分离 → ReentrantReadWriteLock
│   ├── 乐观读 → StampedLock
```

---

*文档版本：JDK 8u60+ / JDK 9~21 增强标注 | 整理时间：2026-06*  
*与前序文档的关系：synchronized/AQS/ReentrantLock 文档讲了"AQS骨架"，本文讲"AQS之上的语义封装工具"*  
*下一篇：Spring AOP 源码深度解析*
