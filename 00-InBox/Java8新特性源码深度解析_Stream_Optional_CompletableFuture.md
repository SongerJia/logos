# Java 8+ 新特性源码深度解析 — Stream / Optional / CompletableFuture

> 基于 JDK 8~21 源码，从流水线架构到异步编程模型，系统拆解 Java 8 函数式编程三大核心组件。

---

## 目录

**Part 1 — Stream**
1. [Stream 整体架构](#1-stream-整体架构)
2. [AbstractPipeline 流水线基类](#2-abstractpipeline-流水线基类)
3. [ReferencePipeline 与 Sink 链](#3-referencepipeline-与-sink-链)
4. [中间操作：filter / map / flatMap](#4-中间操作filter--map--flatmap)
5. [终端操作：forEach / collect / reduce](#5-终端操作foreach--collect--reduce)
6. [短路操作：findAny / anyMatch / limit](#6-短路操作findany--anymatch--limit)
7. [并行流：parallelStream 与 ForkJoinPool](#7-并行流parallelstream-与-forkjoinpool)
8. [Spliterator 分割迭代器](#8-spliterator-分割迭代器)
9. [Stream 的陷阱与最佳实践](#9-stream-的陷阱与最佳实践)

**Part 2 — Optional**
10. [Optional 设计哲学](#10-optional-设计哲学)
11. [Optional 核心源码](#11-optional-核心源码)
12. [Optional 的正确使用姿势](#12-optional-的正确使用姿势)
13. [Optional 的反模式](#13-optional-的反模式)
14. [JDK 9~11 Optional 增强](#14-jdk-911-optional-增强)

**Part 3 — CompletableFuture**
15. [CompletableFuture 整体架构](#15-completablefuture-整体架构)
16. [核心字段与栈结构](#16-核心字段与栈结构)
17. [supplyAsync / runAsync 源码](#17-supplyasync--runasync-源码)
18. [thenApply / thenAccept / thenRun 源码](#18-thenapply--thenaccept--thenrun-源码)
19. [thenCompose 与 thenCombine](#19-thencompose-与-thencombine)
20. [异常处理：exceptionally / handle / whenComplete](#20-异常处理exceptionally--handle--whencomplete)
21. [allOf / anyOf 批量组合](#21-allof--anyof-批量组合)
22. [CompletableFuture 与线程池](#22-completablefuture-与线程池)
23. [JDK 9~12 CompletableFuture 增强](#23-jdk-912-completablefuture-增强)

**Part 4 — 综合**
24. [常见面试题](#24-常见面试题)

---

# Part 1 — Stream

---

## 1. Stream 整体架构

### 类图

```
                        ┌───────────────────┐
                        │ AutoCloseable      │
                        └─────────┬─────────┘
                                  │ extends
                        ┌─────────┴─────────┐
                        │ BaseStream<T,S>    │  ← 接口
                        └─────────┬─────────┘
                                  │ extends
                        ┌─────────┴─────────┐
                        │ Stream<T>          │  ← 用户最常接触的接口
                        └─────────┬─────────┘
                                  │ implements
                   ┌──────────────┴──────────────┐
                   │                             │
          ┌────────┴─────────┐          ┌────────┴─────────┐
          │AbstractPipeline  │          │ReferencePipeline  │
          │(流水线骨架)       │──────────│(引用类型流水线)    │
          └──────────────────┘          └────────┬─────────┘
                                                 │ extends
                                    ┌────────────┼────────────┐
                                    │            │            │
                              ┌─────┴────┐ ┌─────┴────┐ ┌────┴────┐
                              │Head      │ │StatelessOp│ │StatefulOp│
                              │(数据源)   │ │(无状态操作)│ │(有状态操作)│
                              └──────────┘ └──────────┘ └─────────┘
```

### 流水线设计思想

```
Stream 采用"惰性求值 + 融合执行"的设计：

  ① 中间操作（filter/map/sorted...）：不立即执行，只构建操作链
  ② 终端操作（collect/forEach/count...）：触发执行，整条链一次性跑完
  ③ 每个元素依次通过整条操作链（垂直执行），而非每个操作遍历全量数据（水平执行）

垂直执行（Stream 实际方式）：
  元素1 → filter → map → collect → 结果
  元素2 → filter → map → collect → 结果
  ...

水平执行（Stream 不会这样）：
  所有元素 → filter → 中间结果 → map → 中间结果 → collect
```

---

## 2. AbstractPipeline 流水线基类

### 核心字段

```java
// java.util.stream.AbstractPipeline

abstract class AbstractPipeline<E_IN, E_OUT, S extends BaseStream<E_OUT, S>>
        extends PipelineHelper<E_OUT> implements BaseStream<E_OUT, S> {

    // ★ 双向链表：流水线的结构
    @SuppressWarnings("rawtypes")
    private final AbstractPipeline sourceStage;     // 头节点（数据源阶段）

    @SuppressWarnings("rawtypes")
    private final AbstractPipeline previousStage;   // 前一个阶段

    @SuppressWarnings("rawtypes")
    private AbstractPipeline nextStage;             // 下一个阶段

    // 操作信息
    private final int sourceOrOpFlags;              // 操作标志位
    private int combinedFlags;                      // 组合标志位
    private int depth;                              // 操作深度（影响并行拆分策略）

    // 并行相关
    private Spliterator<?> sourceSpliterator;       // 数据源的分割迭代器
    private boolean sourceAnyStateful;              // 是否有有状态操作
    private boolean linkedOrConsumed;               // 是否已被终端操作消费

    // ★ 构造方法：创建 Head（数据源阶段）
    protected AbstractPipeline(Spliterator<?> source,
                               int sourceFlags, boolean parallel) {
        this.previousStage = null;
        this.sourceSpliterator = source;
        this.sourceStage = this;
        this.sourceOrOpFlags = sourceFlags & StreamOpFlag.STREAM_MASK;
        this.combinedFlags = StreamOpFlag.combine(
            StreamOpFlag.INITIAL_OPS_VALUE, sourceOrOpFlags);
        this.depth = 0;
        this.parallel = parallel;
    }

    // ★ 构造方法：创建中间操作阶段
    protected AbstractPipeline(AbstractPipeline<?, E_IN, ?> previousStage,
                               int opFlags) {
        if (previousStage.linkedOrConsumed)
            throw new IllegalStateException("stream has already been operated upon");
        previousStage.linkedOrConsumed = true;
        previousStage.nextStage = this;           // 前驱 → 当前

        this.previousStage = previousStage;       // 当前 → 前驱
        this.sourceStage = previousStage.sourceStage;
        this.sourceOrOpFlags = opFlags & StreamOpFlag.OP_MASK;
        this.combinedFlags = StreamOpFlag.combine(
            previousStage.combinedFlags, sourceOrOpFlags);
        this.depth = previousStage.depth + 1;     // 深度 +1
    }
}
```

### 流水线的构建过程

```java
List<String> result = list.stream()            // ① 创建 Head
    .filter(s -> s.length() > 3)              // ② 创建 StatelessOp(filter)
    .map(String::toUpperCase)                  // ③ 创建 StatelessOp(map)
    .sorted()                                  // ④ 创建 StatefulOp(sorted)
    .collect(Collectors.toList());             // ⑤ 终端操作，触发执行

// 构建出的双向链表：
// Head ←→ StatelessOp(filter) ←→ StatelessOp(map) ←→ StatefulOp(sorted)
//                                                                   ↓
//                                                             collect 触发执行
```

---

## 3. ReferencePipeline 与 Sink 链

### Sink 接口

```java
// java.util.stream.Sink
// Sink 是 Stream 内部数据传递的核心接口，同时继承 Consumer

interface Sink<T> extends Consumer<T> {
    // ★ 开始之前调用（可以做一些初始化）
    default void begin(long size) {}

    // ★ 所有元素处理完后调用
    default void end() {}

    // ★ 是否可以取消后续操作（短路）
    default boolean cancellationRequested() { return false; }

    // 判断是否为有状态操作
    default boolean cancellationRequested() { return false; }
}

// Sink 的四种实现层次
abstract static class ChainedReference<T, E_OUT> implements Sink<T> {
    protected final Sink<? super E_OUT> downstream;   // ★ 下游 Sink

    ChainedReference(Sink<? super E_OUT> downstream) {
        this.downstream = downstream;
    }
}
```

### Sink 链的组装过程

```java
// 当终端操作触发时，AbstractPipeline.wrapSink 从后向前组装 Sink 链

// list.stream().filter(...).map(...).collect(...) 的 Sink 链：
//
//   Head (Spliterator)
//     │
//     ▼
//   Sink.filter (ChainedReference)
//     │ downstream
//     ▼
//   Sink.map (ChainedReference)
//     │ downstream
//     ▼
//   Sink.collect (TerminalSink)
//
// 数据流向：Head → filter → map → collect

// AbstractPipeline.wrapSink 源码
final <P_IN> Sink<P_IN> wrapSink(Sink<E_OUT> sink) {
    Objects.requireNonNull(sink);

    // ★ 从后向前遍历，依次包装
    for ( @SuppressWarnings("rawtypes") AbstractPipeline p=AbstractPipeline.this;
          p.depth > 0;  // depth=0 是 Head，不需要包装
          p=p.previousStage) {
        sink = p.opWrapSink(p.previousStage.combinedFlags, sink);
        // 每个 opWrapSink 返回一个 Sink，其 downstream 指向传入的 sink
    }
    return (Sink<P_IN>) sink;
}
```

### 数据拉取过程

```java
// AbstractPipeline.wrapAndCopyInto
final <P_IN> Sink<P_IN> wrapAndCopyInto(Sink<E_OUT> sink,
                                          Spliterator<P_IN> spliterator) {
    Sink<P_IN> wrappedSink = wrapSink(sink);       // ① 组装 Sink 链
    wrappedSink.begin(spliterator.estimateSize()); // ② 通知 begin
    copyInto(wrappedSink, spliterator);             // ③ 拉取数据
    wrappedSink.end();                              // ④ 通知 end
    return wrappedSink;
}

// copyInto：实际拉取数据
static <P_IN> void copyInto(Sink<P_IN> sink, Spliterator<P_IN> spliterator) {
    if (spliterator.hasCharacteristics(Spliterator.SIZED)) {
        // 精确大小 → 用 forEachRemaining
        spliterator.forEachRemaining(sink);
    } else {
        // 不确定大小 → 用 tryAdvance 逐个
        do { } while (!sink.cancellationRequested() && spliterator.tryAdvance(sink));
    }
}
```

---

## 4. 中间操作：filter / map / flatMap

### filter 源码

```java
// java.util.stream.ReferencePipeline.StatelessOp

@Override
public final Stream<P_OUT> filter(Predicate<? super P_OUT> predicate) {
    Objects.requireNonNull(predicate);
    // 创建一个无状态操作，opWrapSink 负责包装下游 Sink
    return new StatelessOp<P_OUT, P_OUT>(this, StreamShape.REFERENCE,
            StreamOpFlag.NOT_SIZED) {
        @Override
        Sink<P_OUT> opWrapSink(int flags, Sink<P_OUT> sink) {
            return new Sink.ChainedReference<P_OUT, P_OUT>(sink) {
                @Override
                public void begin(long size) {
                    downstream.begin(-1);   // ★ filter 后大小不确定，传 -1
                }

                @Override
                public void end() {
                    downstream.end();
                }

                @Override
                public void accept(P_OUT u) {
                    if (predicate.test(u))      // ★ 谓词测试
                        downstream.accept(u);   // 通过才传给下游
                    // 不通过则直接丢弃
                }
            };
        }
    };
}
```

### map 源码

```java
@Override
@SuppressWarnings("unchecked")
public final <R> Stream<R> map(Function<? super P_OUT, ? extends R> mapper) {
    Objects.requireNonNull(mapper);
    return new StatelessOp<P_OUT, R>(this, StreamShape.REFERENCE,
            StreamOpFlag.NOT_SORTED | StreamOpFlag.NOT_DISTINCT) {
        @Override
        Sink<P_OUT> opWrapSink(int flags, Sink<R> sink) {
            return new Sink.ChainedReference<P_OUT, R>(sink) {
                @Override
                public void accept(P_OUT u) {
                    downstream.accept(mapper.apply(u));   // ★ 映射后传给下游
                }
            };
        }
    };
}
```

### flatMap 源码

```java
@Override
public final <R> Stream<R> flatMap(Function<? super P_OUT, ? extends Stream<? extends R>> mapper) {
    Objects.requireNonNull(mapper);
    return new StatelessOp<P_OUT, R>(this, StreamShape.REFERENCE,
            StreamOpFlag.NOT_SORTED | StreamOpFlag.NOT_DISTINCT | StreamOpFlag.NOT_SIZED) {
        @Override
        Sink<P_OUT> opWrapSink(int flags, Sink<R> sink) {
            return new Sink.ChainedReference<P_OUT, R>(sink) {
                // ★ 用于检测 flatMap 中是否重复消费
                @Override
                public void begin(long size) {
                    downstream.begin(-1);  // flatMap 后大小完全不确定
                }

                @Override
                public void accept(P_OUT u) {
                    try (Stream<? extends R> result = mapper.apply(u)) {
                        // ★ 将映射出的每个 Stream 展平，逐个传给下游
                        if (result != null)
                            result.sequential().forEach(downstream);
                    }
                }

                @Override
                public void end() {
                    downstream.end();
                }
            };
        }
    };
}
```

### sorted 源码（有状态操作）

```java
@Override
public final Stream<P_OUT> sorted(Comparator<? super P_OUT> comparator) {
    return SortedOps.makeRef(this, comparator);
}

// SortedOps.makeRef 简化
static <T> Sink<T> makeRef(AbstractPipeline<?, T, ?> upstream,
                            Comparator<? super T> comparator) {
    return new Sink.ChainedReference<T, T>(null) {
        private ArrayList<T> list;   // ★ 必须缓存所有元素才能排序！

        @Override
        public void begin(long size) {
            list = (size >= 0) ? new ArrayList<>((int) size) : new ArrayList<>();
        }

        @Override
        public void end() {
            list.sort(comparator);        // ★ 排序
            downstream.begin(list.size());
            list.forEach(downstream::accept);  // 排序后传给下游
            downstream.end();
            list = null;
        }

        @Override
        public void accept(T t) {
            list.add(t);                  // ★ 先全部收集
        }
    };
}
```

> **关键区别**：无状态操作（filter/map）在 accept 中直接处理并传递；有状态操作（sorted/distinct/limit）需要缓存元素后再处理。

---

## 5. 终端操作：forEach / collect / reduce

### forEach 源码

```java
// ReferencePipeline
@Override
public void forEach(Consumer<? super P_OUT> action) {
    evaluate(ForEachOps.makeRef(action, false));
}

// ForEachOps.makeRef
public static <T> TerminalOp<T, Void> makeRef(Consumer<? super T> action,
                                               boolean ordered) {
    Objects.requireNonNull(action);
    return new ForEachOp<>(action, ordered);
}

// ForEachOp 是 TerminalOp 的实现
static class ForEachOp<T> implements TerminalOp<T, Void> {
    private final Consumer<? super T> consumer;
    private final boolean ordered;   // 是否保持顺序

    @Override
    public <S> Void evaluateSequential(PipelineHelper<T> helper,
                                        Spliterator<S> spliterator) {
        return helper.wrapAndCopyInto(this, spliterator);
        // ★ 顺序流：直接 wrapAndCopyInto，Sink 链拉取
    }

    @Override
    public <S> Void evaluateParallel(PipelineHelper<T> helper,
                                      Spliterator<S> spliterator) {
        if (ordered)
            // 有序并行：使用 ForEachOrderedTask
            return new ForEachOrderedTask<>(helper, spliterator, consumer).invoke();
        else
            // 无序并行：使用 ForEachTask
            return new ForEachTask<>(helper, spliterator, consumer).invoke();
    }
}
```

### collect 源码

```java
// ReferencePipeline
@Override
public final <R, A> R collect(Collector<? super P_OUT, A, R> collector) {
    A container;
    if (isParallel()
        && (collector.characteristics().contains(Collector.Characteristics.CONCURRENT))
        && (!isOrdered() || collector.characteristics()
              .contains(Collector.Characteristics.UNORDERED))) {
        // ★ 并行 + CONCURRENT + UNORDERED → 单容器并发累积
        container = collector.supplier().get();
        BiConsumer<A, ? super P_OUT> accumulator = collector.accumulator();
        forEach(e -> accumulator.accept(container, e));
    } else {
        // ★ 顺序流 或 不满足并发条件 → 逐个累积 + combiner 合并
        container = evaluate(ReduceOps.makeRef(collector));
    }
    return collector.finisher().apply(container);
}

// Collector 的三个泛型：
// T - 元素类型, A - 累积容器类型, R - 最终结果类型

// Collector 的五个方法：
// supplier()     → 创建累积容器
// accumulator()  → 累积元素到容器
// combiner()     → 合并两个容器（并行）
// finisher()     → 容器 → 最终结果
// characteristics() → 特征集合
```

### Collectors.toList 源码

```java
// java.util.stream.Collectors
public static <T> Collector<T, ?, List<T>> toList() {
    return new CollectorImpl<>(
        (Supplier<List<T>>) ArrayList::new,   // supplier: 创建 ArrayList
        List::add,                              // accumulator: 添加元素
        (left, right) -> {                      // combiner: 合并两个列表
            left.addAll(right);
            return left;
        },
        CH_ID                                   // characteristics: IDENTITY_FINISH
    );
}

// toUnmodifiableList (JDK 10+)
public static <T> Collector<T, ?, List<T>> toUnmodifiableList() {
    return new CollectorImpl<>(
        ArrayList::new,
        List::add,
        (left, right) -> { left.addAll(right); return left; },
        list -> Collections.unmodifiableList(list),   // ★ finisher 包装
        CH_NOID                                        // 无 IDENTITY_FINISH
    );
}
```

### reduce 源码

```java
// 三种 reduce 形式

// 1. 无初始值（返回 Optional）
@Override
public Optional<P_OUT> reduce(BinaryOperator<P_OUT> accumulator) {
    return evaluate(ReduceOps.makeRef(accumulator));
    // 空流时返回 Optional.empty()
}

// 2. 有初始值
@Override
public P_OUT reduce(P_OUT identity, BinaryOperator<P_OUT> accumulator) {
    return evaluate(ReduceOps.makeRef(identity, accumulator, accumulator));
    // identity 是数学意义上的单位元：对于任何 x，accumulator(identity, x) == x
}

// 3. 可分治的 reduce（map-reduce 模式）
@Override
public <U> U reduce(U identity,
                    BiFunction<U, ? super P_OUT, U> accumulator,
                    BinaryOperator<U> combiner) {
    return evaluate(ReduceOps.makeRef(identity, accumulator, combiner));
    // ★ combiner 用于并行合并各线程的部分结果
    // 示例：求字符串总长度
    //   identity: 0
    //   accumulator: (sum, str) -> sum + str.length()
    //   combiner: (sum1, sum2) -> sum1 + sum2
}
```

---

## 6. 短路操作：findAny / anyMatch / limit

### findAny 源码

```java
@Override
public Optional<P_OUT> findAny() {
    return evaluate(TerminalOps.makeFindAny());
}

// FindOps.makeFindAny
private static final TerminalOp<?, Optional<?>> FIND_ANY =
    new FindOp<>(false, Optional.empty(), Optional::of, StreamShape.REFERENCE);

// FindOp 的 Sink 实现
static class FindSink<T, O> implements TerminalSink<T, O> {
    boolean hasValue;
    T value;

    @Override
    public void accept(T t) {
        if (!hasValue) {
            hasValue = true;
            value = t;
        }
    }

    @Override
    public boolean cancellationRequested() {
        return hasValue;   // ★ 找到一个就请求取消
    }

    @Override
    public O get() {
        return hasValue ? Optional.of(value) : Optional.empty();
    }
}
```

### anyMatch 源码

```java
@Override
public boolean anyMatch(Predicate<? super P_OUT> predicate) {
    return evaluate(MatchOps.makeRef(predicate, MatchOps.MatchKind.ANY));
}

// MatchOps 的 Sink
static class MatchSink<T> implements Sink<T> {
    private final Predicate<? super T> predicate;
    private final MatchKind kind;
    private boolean stop;   // ★ 是否可以停止

    @Override
    public void accept(T t) {
        if (!stop) {
            boolean p = predicate.test(t);
            if (kind == MatchKind.ANY && p) {
                stop = true;    // ★ any: 匹配一个就停
            } else if (kind == MatchKind.ALL && !p) {
                stop = true;    // ★ all: 有一个不匹配就停
            } else if (kind == MatchKind.NONE && p) {
                stop = true;    // ★ none: 有一个匹配就停
            }
        }
    }

    @Override
    public boolean cancellationRequested() {
        return stop;   // ★ 请求取消
    }
}
```

### limit 源码

```java
// SliceOps.makeRef 简化
static <T> Sink<T> opWrapSink(long maxSize, Sink<T> sink) {
    return new Sink.ChainedReference<T, T>(sink) {
        long n = 0;

        @Override
        public void begin(long size) {
            downstream.begin(size >= 0 ? Math.min(size, maxSize) : maxSize);
        }

        @Override
        public void accept(T t) {
            if (n < maxSize) {
                n++;
                downstream.accept(t);   // ★ 只传递前 maxSize 个
            }
        }

        @Override
        public boolean cancellationRequested() {
            return n >= maxSize || downstream.cancellationRequested();
            // ★ 达到限制就请求取消
        }
    };
}
```

---

## 7. 并行流：parallelStream 与 ForkJoinPool

### 并行流的执行框架

```
parallelStream() 的执行流程：

  ① 数据源被 Spliterator 递归拆分为多个子任务
  ② 每个 ForkJoinTask 处理一个子任务
  ③ 子任务结果通过 combiner 合并
  ④ 最终汇总到终端操作

┌─────────────────────────────────────┐
│          ForkJoinPool               │
│                                     │
│  ┌───────────┐  ┌───────────┐      │
│  │Task-1     │  │Task-2     │      │
│  │[a,b,c,d]  │  │[e,f,g,h] │      │
│  │filter→map  │  │filter→map │      │
│  │collect     │  │collect    │      │
│  └─────┬─────┘  └─────┬─────┘      │
│        │               │            │
│        └───────┬───────┘            │
│                │ combiner           │
│                ▼                    │
│          最终结果                    │
└─────────────────────────────────────┘
```

### 并行流使用的线程池

```java
// 默认使用 ForkJoinPool.commonPool()
// 线程数 = Runtime.getRuntime().availableProcessors() - 1

// 也可以指定自定义线程池
ForkJoinPool customPool = new ForkJoinPool(4);
customPool.submit(() -> {
    List<Integer> result = list.parallelStream()
        .filter(x -> x > 10)
        .collect(Collectors.toList());
}).get();
```

### 并行流的 ABORT 陷阱

```java
// ★ 陷阱 1：ArrayList vs LinkedList
// ArrayList: Spliterator.SIZED + SUBSIZED → 高效拆分
// LinkedList: 没有这些特征 → 拆分效率极差 → 并行可能更慢

// ★ 陷阱 2：装箱开销
// Stream<Integer> 有装箱开销，并行也不快
// IntStream / LongStream / DoubleStream 无装箱 → 并行效果更好

// ★ 陷阱 3：共享可变状态
List<Integer> shared = new ArrayList<>();
IntStream.range(0, 10000).parallel().forEach(shared::add);
// shared 的大小可能 < 10000（ArrayList 非线程安全）
// 正确做法：用 collect(Collectors.toList())

// ★ 陷阱 4：NQ 模型
// N = 数据量, Q = 每个元素的操作耗时
// N * Q 足够大时并行才有收益
// 简单的 filter + map，N < 10万时并行反而更慢
```

---

## 8. Spliterator 分割迭代器

### Spliterator 接口

```java
// java.util.Spliterator
public interface Spliterator<T> {

    // 逐个处理元素，还有剩余返回 true
    boolean tryAdvance(Consumer<? super T> action);

    // 批量处理剩余元素
    default void forEachRemaining(Consumer<? super T> action) {
        do { } while (tryAdvance(action));
    }

    // ★ 拆分：将一部分元素分出去，返回新的 Spliterator
    // 无法拆分时返回 null
    Spliterator<T> trySplit();

    // 估算剩余元素数量
    long estimateSize();

    // 特征值
    int characteristics();

    // 特征常量
    static final int ORDERED    = 0x00000010;  // 有序
    static final int DISTINCT   = 0x00000001;  // 去重
    static final int SORTED     = 0x00000004;  // 已排序
    static final int SIZED      = 0x00000040;  // 大小已知
    static final int NONNULL    = 0x00000100;  // 元素非 null
    static final int IMMUTABLE  = 0x00000400;  // 不可变
    static final int CONCURRENT = 0x00001000;  // 并发安全
    static final int SUBSIZED   = 0x00004000;  // 子 Spliterator 也是 SIZED
}
```

### ArrayList Spliterator 的 trySplit

```java
// java.util.ArrayList.ArrayListSpliterator
static final class ArrayListSpliterator<E> implements Spliterator<E> {
    private final ArrayList<E> list;
    private int index;          // 当前位置
    private final int fence;    // 结束位置（不可变）
    private final int expectedModCount;

    public ArrayListSpliterator<E> trySplit() {
        int lo = index, mid = (lo + fence) >>> 1;
        // ★ 从中间一分为二
        return (lo >= mid)
            ? null   // 元素太少，不再拆分
            : new ArrayListSpliterator<E>(list, lo, index = mid, expectedModCount);
        // 前半部分 [lo, mid) 给新的 Spliterator
        // 后半部分 [mid, fence) 留给自己（index 前移到 mid）
    }
}
```

### Spliterator 拆分示意

```
原始数据：[1, 2, 3, 4, 5, 6, 7, 8]

第 1 次 trySplit：
  Spliterator-A: [1, 2, 3, 4]     → 可以继续 trySplit
  Spliterator-B: [5, 6, 7, 8]     → 可以继续 trySplit

第 2 次 trySplit（A 和 B 各自再拆）：
  A1: [1, 2]    A2: [3, 4]
  B1: [5, 6]    B2: [7, 8]

最终每个 Spliterator 处理一小块数据 → 分配给 ForkJoinTask
```

---

## 9. Stream 的陷阱与最佳实践

### 常见陷阱

```java
// ① 流只能消费一次
Stream<String> stream = list.stream();
stream.filter(s -> s.length() > 3).count();  // OK
stream.map(String::toUpperCase).count();      // IllegalStateException: stream has already been operated upon

// ② 不要在 forEach 中修改数据源
list.stream().forEach(list::remove);  // ConcurrentModificationException

// ③ peek 不是为了副作用而设计的
// 反例：用 peek 修改元素
list.stream().peek(e -> e.setValue(1)).collect(toList());
// 正解：用 map
list.stream().map(e -> e.withValue(1)).collect(toList());

// ④ 自动装箱
// 反例：Stream<Integer> 有装箱开销
Stream<Integer> stream = IntStream.range(0, 100).boxed();
// 正解：直接用 IntStream
IntStream stream = IntStream.range(0, 100);

// ⑤ sorted 是有状态操作，需要全量缓存
// 如果只需要 Top N，用 limit(N) 配合 PriorityQueue 而非 sorted
```

### 最佳实践

```
1. 优先使用原始类型流（IntStream / LongStream / DoubleStream）
2. 短路操作优先（findAny / anyMatch 比 collect 后判断更高效）
3. 并行流仅用于大数据量 + CPU 密集型操作
4. 永远不要在流操作中修改共享状态
5. 集合转流用 Collection.stream()，数组用 Arrays.stream()
6. 需要 index 时用 IntStream.range + mapToObj
7. 调试时用 peek() 观察中间值（但生产代码去掉）
```

---

# Part 2 — Optional

---

## 10. Optional 设计哲学

### 为什么引入 Optional

```
Brian Goetz（Java 语言架构师）的原话：

"Optional was primarily designed for use as a method return type
 where there is a clear need to represent 'no result',
 and where using null would cause errors."

Optional 的设计目标：
  ① 明确表达"可能没有值"的语义（比 null 更显式）
  ② 强制调用者处理空值情况
  ③ 链式调用替代嵌套 null 检查

Optional 的定位：
  ✓ 方法返回值：表示可能没有结果
  ✗ 类字段：不推荐（增加内存开销，序列化问题）
  ✗ 方法参数：不推荐（增加了调用方负担）
  ✗ 集合元素：不推荐（集合本身可以表达空）
```

---

## 11. Optional 核心源码

```java
// java.util.Optional（JDK 8）
public final class Optional<T> {

    // ★ 共享的单例，表示空值
    private static final Optional<?> EMPTY = new Optional<>(null);

    // 内部持有的值
    private final T value;

    // 私有构造
    private Optional(T value) {
        this.value = value;
    }

    // ===== 静态工厂方法 =====

    // 返回空的 Optional
    public static<T> Optional<T> empty() {
        @SuppressWarnings("unchecked")
        Optional<T> t = (Optional<T>) EMPTY;
        return t;
    }

    // 返回包含值的 Optional（value 不能为 null）
    public static <T> Optional<T> of(T value) {
        return new Optional<>(Objects.requireNonNull(value));
        // ★ 传入 null 会抛 NPE
    }

    // 返回包含值的 Optional（可以为 null）
    public static <T> Optional<T> ofNullable(T value) {
        return value == null ? empty() : of(value);
    }

    // ===== 实例方法 =====

    // 获取值（为空抛 NoSuchElementException）
    public T get() {
        if (value == null) {
            throw new NoSuchElementException("No value present");
        }
        return value;
    }

    // 是否有值
    public boolean isPresent() {
        return value != null;
    }

    // 有值时执行 Consumer
    public void ifPresent(Consumer<? super T> consumer) {
        if (value != null)
            consumer.accept(value);
    }

    // 有值时过滤
    public Optional<T> filter(Predicate<? super T> predicate) {
        Objects.requireNonNull(predicate);
        if (!isPresent()) return this;
        return predicate.test(value) ? this : empty();
    }

    // 有值时映射
    public<U> Optional<U> map(Function<? super T, ? extends U> mapper) {
        Objects.requireNonNull(mapper);
        if (!isPresent()) return empty();
        return Optional.ofNullable(mapper.apply(value));
        // ★ mapper 返回 null 时变成 empty
    }

    // 有值时扁平映射
    public<U> Optional<U> flatMap(Function<? super T, Optional<U>> mapper) {
        Objects.requireNonNull(mapper);
        if (!isPresent()) return empty();
        return Objects.requireNonNull(mapper.apply(value));
        // ★ mapper 返回的 Optional 直接作为结果（不再包装）
    }

    // 有值返回值，无值返回 other
    public T orElse(T other) {
        return value != null ? value : other;
    }

    // 有值返回值，无值调用 Supplier 获取默认值
    public T orElseGet(Supplier<? extends T> other) {
        return value != null ? value : other.get();
    }

    // 无值时抛异常
    public <X extends Throwable> T orElseThrow(Supplier<? extends X> exceptionSupplier)
            throws X {
        if (value != null) return value;
        throw exceptionSupplier.create();
    }

    // equals / hashCode / toString
    @Override
    public String toString() {
        return value != null
            ? String.format("Optional[%s]", value)
            : "Optional.empty";
    }
}
```

---

## 12. Optional 的正确使用姿势

### 链式调用替代嵌套 null 检查

```java
// 嵌套 null 检查（反模式）
String city = null;
if (user != null) {
    Address address = user.getAddress();
    if (address != null) {
        City c = address.getCity();
        if (c != null) {
            city = c.getName();
        }
    }
}

// Optional 链式调用
String city = Optional.ofNullable(user)
    .map(User::getAddress)
    .map(Address::getCity)
    .map(City::getName)
    .orElse("Unknown");
```

### 与 Stream 配合

```java
// 用 Optional 处理集合查找
List<User> users = getUsers();
User admin = users.stream()
    .filter(u -> "admin".equals(u.getRole()))
    .findFirst()              // 返回 Optional<User>
    .orElseThrow(() -> new RuntimeException("No admin found"));

// Optional → Stream（JDK 9+）
// flatMap 中使用 Optional::stream
List<String> emails = users.stream()
    .map(User::getEmail)        // Optional<String>
    .flatMap(Optional::stream)  // Stream<String>（空 Optional 变成空 Stream）
    .collect(Collectors.toList());
```

---

## 13. Optional 的反模式

```java
// ★ 反模式 1：直接调用 get() 不检查
Optional<User> opt = findUser(id);
User user = opt.get();   // 如果为空 → NoSuchElementException
// 正解：用 orElse / orElseThrow

// ★ 反模式 2：用 isPresent + get 替代 null 检查
if (opt.isPresent()) {
    return opt.get().getName();
} else {
    return "default";
}
// 这和 if (x != null) 没区别，没有利用 Optional 的优势
// 正解：opt.map(User::getName).orElse("default")

// ★ 反模式 3：Optional 作为字段
class User {
    private Optional<String> nickname;  // ✗ 不推荐
    // ① 占用额外内存（Optional 对象本身）
    // ② 不支持序列化
    // ③ 字段可以为 null 本身就是语义表达
}
// 正解：字段用普通类型 + @Nullable 注解

// ★ 反模式 4：Optional 作为方法参数
public void setName(Optional<String> name) { ... }  // ✗
// 调用方必须包装：setName(Optional.ofNullable(name))
// 正解：方法参数用普通类型 + 重载或 @Nullable

// ★ 反模式 5：Optional 包装集合
Optional<List<String>> getNames();  // ✗
// 空集合就能表达"没有结果"
// 正解：List<String> getNames(); 返回空集合而非 null
```

---

## 14. JDK 9~11 Optional 增强

### JDK 9 新增

```java
// ① ifPresentOrElse
optional.ifPresentOrElse(
    value -> System.out.println("Got: " + value),
    ()   -> System.out.println("No value")
);

// ② or（无值时返回备选 Optional）
Optional<String> result = optional.or(() -> Optional.of("default"));

// ③ stream（转为 Stream）
// 有值 → 单元素 Stream，空 → 空 Stream
optional.stream()
    .filter(s -> s.length() > 3)
    .collect(Collectors.toList());
```

### JDK 10 新增

```java
// orElseThrow（无参版，抛 NoSuchElementException）
// JDK 8 的 get() 等价于 orElseThrow()，但 orElseThrow 语义更明确
T value = optional.orElseThrow();  // 比 get() 更推荐
```

### JDK 11 新增

```java
// isEmpty（JDK 11+）
if (optional.isEmpty()) {   // 比 !optional.isPresent() 更直观
    System.out.println("No value");
}
```

---

# Part 3 — CompletableFuture

---

## 15. CompletableFuture 整体架构

### 继承关系

```
┌──────────────┐
│  Future<V>   │  ← 基础接口：get/cancel/isDone
└──────┬───────┘
       │ extends
┌──────┴──────────────┐
│ CompletionStage<T>  │  ← 链式异步编程接口
└──────┬──────────────┘
       │ extends
┌──────┴──────────────┐
│ CompletableFuture<T>│  ← 实现类
└─────────────────────┘
```

### CompletionStage 的方法分类

```
转换类：
  thenApply / thenApplyAsync           → 结果映射
  thenCompose / thenComposeAsync       → 结果扁平映射
  thenCombine / thenCombineAsync       → 合并两个结果

消费类：
  thenAccept / thenAcceptAsync         → 消费结果（无返回值）
  thenRun / thenRunAsync               → 不关心结果，执行动作

组合类：
  whenComplete / whenCompleteAsync     → 结果+异常都处理（不影响结果）
  handle / handleAsync                 → 结果+异常都处理（可改变结果）
  exceptionally                        → 异常处理

二元组合：
  thenAcceptBoth / thenAcceptBothAsync → 消费两个结果
  runAfterBoth / runAfterBothAsync     → 两个都完成后执行

二选一：
  applyToEither / applyToEitherAsync   → 取先完成的映射
  acceptEither / acceptEitherAsync     → 取先完成的消费
  runAfterEither / runAfterEitherAsync → 任一完成就执行

多选一：
  anyOf                                → 任一完成
  allOf                                → 全部完成
```

---

## 16. 核心字段与栈结构

```java
// java.util.concurrent.CompletableFuture

public class CompletableFuture<T> implements Future<T>, CompletionStage<T> {

    // ★ 结果：要么是 AltResult（异常），要么就是实际值
    volatile Object result;    // null → 未完成; AltResult → 异常或 null 值; 其他 → 正常结果

    // ★ 依赖栈：当前 CompletableFuture 完成后需要触发的后续操作
    volatile Completion completions;   // 栈顶（Treiber Stack）

    // 内部结果封装
    static final class AltResult {
        final Throwable ex;        // null 表示正常完成的 null 值
        AltResult(Throwable ex) { this.ex = ex; }
    }

    // ★ Completion 是栈节点（Treiber Stack）
    // 每个后续操作被包装为一个 Completion 压入栈
    // 当前 Future 完成时，依次弹出并执行

    static abstract class Completion extends ForkJoinTask<Void>
            implements Runnable, AsynchronousCompletionTask {
        volatile Completion next;   // ★ 下一个节点（栈的链表）

        abstract CompletableFuture<?> tryFire(int mode);
        // mode: SYNC=0, ASYNC=1, NESTED=-1
    }
}
```

### 栈结构示意

```java
CompletableFuture<String> cf = supplyAsync(() -> fetch())
    .thenApply(s -> s.toUpperCase())
    .thenAccept(System.out::println);

// cf (supplyAsync) 的 completions 栈：
//
//   completions → UniApply(s -> s.toUpperCase())
//                    │ next
//                    ▼
//                  UniAccept(System.out::println)
//                    │ next
//                    ▼
//                   null

// supplyAsync 完成后：
//   依次弹出 UniApply → 执行 → 将结果传给下游 → 弹出 UniAccept → 执行
```

---

## 17. supplyAsync / runAsync 源码

```java
// 有返回值的异步任务
public static <U> CompletableFuture<U> supplyAsync(Supplier<U> supplier) {
    return asyncSupplyStage(AsyncPool.HEAPPOOL, supplier);
    // ★ 默认使用 ForkJoinPool.commonPool()
}

public static <U> CompletableFuture<U> supplyAsync(Supplier<U> supplier,
                                                    Executor executor) {
    return asyncSupplyStage(screenExecutor(executor), supplier);
    // ★ 自定义线程池
}

// asyncSupplyStage 核心逻辑
static <U> CompletableFuture<U> asyncSupplyStage(Executor e, Supplier<U> f) {
    CompletableFuture<U> d = new CompletableFuture<U>();   // 创建依赖的 Future
    e.execute(new AsyncSupply<U>(d, f));                   // 提交任务
    return d;
}

// AsyncSupply 是实际执行的任务
static final class AsyncSupply<T> extends ForkJoinTask<Void>
        implements Runnable, AsynchronousCompletionTask {
    CompletableFuture<T> dep;   // 依赖的 Future
    Supplier<? extends T> fn;

    public void run() {
        CompletableFuture<T> d; Supplier<? extends T> f;
        if ((d = dep) != null && (f = fn) != null) {
            try {
                T t = f.get();                   // ★ 执行 Supplier
                d.completeValue(t);              // ★ 设置结果
            } catch (Throwable ex) {
                d.completeThrowable(ex);         // ★ 设置异常
            }
        }
    }
}

// completeValue：CAS 设置结果
final boolean completeValue(T t) {
    return UNSAFE.compareAndSwapObject(this, RESULT, null,
        (t == null) ? NIL : t);    // null 值用 NIL (AltResult) 封装
}

// completeThrowable：CAS 设置异常
final boolean completeThrowable(Throwable x) {
    return UNSAFE.compareAndSwapObject(this, RESULT, null,
        new AltResult(x));
}
```

### 设置结果后触发依赖栈

```java
// 完成后触发所有依赖
final void postComplete() {
    CompletableFuture<?> f = this;   // 当前完成的 Future
    Completion h;                     // 栈顶 Completion

    while ((h = f.completions) != null || f != this) {
        // CAS 弹出栈顶
        if (f.completions == h && UNSAFE.compareAndSwapObject(f, COMPLETIONS, h, h.next)) {
            // ★ 执行 Completion
            CompletableFuture<?> d = h.tryFire(NESTED);
            if (d != null) {
                // 下游也完成了，继续处理下游的依赖
                f = d;
            }
        }
    }
}
```

---

## 18. thenApply / thenAccept / thenRun 源码

### thenApply

```java
public <U> CompletableFuture<U> thenApply(Function<? super T,? extends U> fn) {
    return uniApplyStage(null, fn);
    // ★ null 表示同步执行（在当前线程）
}

public <U> CompletableFuture<U> thenApplyAsync(Function<? super T,? extends U> fn) {
    return uniApplyStage(asyncPool, fn);
    // ★ asyncPool 表示异步执行
}

// uniApplyStage 核心
private <U> CompletableFuture<U> uniApplyStage(Executor e, Function<? super T,? extends U> f) {
    CompletableFuture<U> d = new CompletableFuture<U>();   // 创建下游 Future

    if (result == null) {
        // ★ 当前未完成，压入依赖栈
        UniApply<T,U> c = new UniApply<T,U>(e, d, this, f);
        push(c);           // 压栈
        c.tryFire(SYNC);   // 尝试立即执行（如果当前已完成）
    } else {
        // ★ 当前已完成，直接执行
        UniApply<T,U> c = new UniApply<T,U>(e, d, this, f);
        c.tryFire(SYNC);
    }
    return d;
}

// UniApply.tryFire
final CompletableFuture<Void> tryFire(int mode) {
    CompletableFuture<? super T> a;   // 上游
    if ((a = src) == null || a.result == null) return null;  // 上游未完成

    // 上游已完成，执行函数
    T t = a.result instanceof AltResult ? null : (T) a.result;
    U u = fn.apply(t);                // ★ 执行映射函数
    d.completeValue(u);               // 设置下游结果
    src = null; fn = null;            // 清理引用
    return d;                          // 返回下游 Future
}
```

### thenAccept

```java
public CompletableFuture<Void> thenAccept(Consumer<? super T> action) {
    return uniAcceptStage(null, action);
}

// 与 thenApply 类似，但返回 CompletableFuture<Void>
// 执行 action 后，d.completeValue(null)
```

### thenRun

```java
public CompletableFuture<Void> thenRun(Runnable action) {
    return uniRunStage(null, action);
}

// 不关心上游结果，直接执行 action
// d.completeValue(null)
```

---

## 19. thenCompose 与 thenCombine

### thenCompose（flatMap 语义）

```java
// thenApply:  T → U
// thenCompose: T → CompletableFuture<U>  → 扁平化

public <U> CompletableFuture<U> thenCompose(
        Function<? super T, ? extends CompletionStage<U>> fn) {
    return uniComposeStage(null, fn);
}

// uniComposeStage 简化
private <U> CompletableFuture<U> uniComposeStage(
        Executor e, Function<? super T, ? extends CompletionStage<U>> f) {
    CompletableFuture<U> d = new CompletableFuture<U>();

    // 当上游完成时：
    // ① 执行 fn 得到一个新的 CompletionStage
    // ② 将这个 CompletionStage 的结果传递给 d
    // → 类似 Optional.flatMap / Stream.flatMap

    if (result == null) {
        UniCompose<T,U> c = new UniCompose<T,U>(e, d, this, f);
        push(c);
        c.tryFire(SYNC);
    } else {
        // 上游已完成
        T t = result instanceof AltResult ? null : (T) result;
        CompletionStage<U> cs = f.apply(t);   // ★ 得到新的 Stage
        cs.whenComplete((u, ex) -> {
            if (ex != null) d.completeThrowable(ex);
            else d.completeValue(u);
        });
    }
    return d;
}
```

### thenCombine（合并两个结果）

```java
public <U, V> CompletableFuture<V> thenCombine(
        CompletionStage<? extends U> other,
        BiFunction<? super T, ? super U, ? extends V> fn) {
    return biApplyStage(null, other, fn);
}

// 示例：并行请求两个服务，合并结果
CompletableFuture<String> nameFuture  = supplyAsync(() -> fetchName());
CompletableFuture<Integer> ageFuture  = supplyAsync(() -> fetchAge());

CompletableFuture<String> result = nameFuture.thenCombine(ageFuture,
    (name, age) -> name + " is " + age + " years old");

// biApplyStage 简化逻辑：
// ① 等待两个 Future 都完成
// ② 用 BiFunction 合并两个结果
// ③ 设置到下游 Future
```

---

## 20. 异常处理：exceptionally / handle / whenComplete

### exceptionally

```java
public CompletableFuture<T> exceptionally(Function<Throwable, ? extends T> fn) {
    return uniExceptionallyStage(null, fn);
}

// 只在异常时触发，正常结果直接透传
// 示例
CompletableFuture<String> cf = supplyAsync(() -> {
    if (Math.random() > 0.5) throw new RuntimeException("random error");
    return "success";
}).exceptionally(ex -> {
    System.out.println("Error: " + ex.getMessage());
    return "fallback";   // ★ 异常时返回默认值
});
```

### handle

```java
public <U> CompletableFuture<U> handle(
        BiFunction<? super T, Throwable, ? extends U> fn) {
    return uniHandleStage(null, fn);
}

// ★ 正常和异常都会触发
// 正常时：ex == null，t 有值
// 异常时：t == null，ex 有值
// 可以在 handle 中恢复异常

CompletableFuture<String> cf = supplyAsync(() -> riskyCall())
    .handle((result, ex) -> {
        if (ex != null) {
            log.error("Failed", ex);
            return "fallback";
        }
        return result;
    });
```

### whenComplete

```java
public CompletableFuture<T> whenComplete(
        BiConsumer<? super T, ? super Throwable> action) {
    return uniWhenCompleteStage(null, action);
}

// ★ 和 handle 类似，但不改变结果
// 正常：结果透传
// 异常：异常透传
// 通常用于日志记录、资源清理等副作用

CompletableFuture<String> cf = supplyAsync(() -> fetchData())
    .whenComplete((result, ex) -> {
        if (ex != null) {
            log.error("Request failed", ex);
        } else {
            log.info("Request succeeded: {}", result);
        }
    });
// ★ 即使 whenComplete 中不抛异常，原异常仍然会传递
```

### 三者对比

```
                  正常时          异常时         能否改变结果
exceptionally     透传结果        调用 fn         ✓ (返回默认值)
handle            调用 fn         调用 fn         ✓
whenComplete      调用 action     调用 action     ✗ (结果/异常透传)
```

---

## 21. allOf / anyOf 批量组合

### allOf

```java
public static CompletableFuture<Void> allOf(CompletableFuture<?>... cfs) {
    // ★ 等待所有 Future 完成（不管成功还是异常）
    // 返回 Void，需要手动获取各 Future 的结果
}

// 示例：并行请求，全部完成后处理
CompletableFuture<String> f1 = supplyAsync(() -> fetchUser());
CompletableFuture<String> f2 = supplyAsync(() -> fetchOrder());
CompletableFuture<String> f3 = supplyAsync(() -> fetchProduct());

CompletableFuture<Void> all = CompletableFuture.allOf(f1, f2, f3);
all.thenRun(() -> {
    // ★ 三个请求都完成了
    String user = f1.join();      // 不会阻塞，已完成
    String order = f2.join();
    String product = f3.join();
    System.out.println(user + order + product);
});
```

### anyOf

```java
public static CompletableFuture<Object> anyOf(CompletableFuture<?>... cfs) {
    // ★ 任一 Future 完成就返回（不管成功还是异常）
    // 返回的是最先完成的 Future 的结果
}

// 示例：竞速请求
CompletableFuture<String> fast1 = supplyAsync(() -> service1());
CompletableFuture<String> fast2 = supplyAsync(() -> service2());
CompletableFuture<String> fast3 = supplyAsync(() -> service3());

CompletableFuture<Object> winner = CompletableFuture.anyOf(fast1, fast2, fast3);
winner.thenAccept(result -> {
    System.out.println("Fastest result: " + result);
});
```

### allOf 源码简析

```java
static CompletableFuture<Void> allOf(CompletableFuture<?>[] cfs) {
    int n = cfs.length;
    if (n == 0) return completedFuture(null);

    CompletableFuture<Void> d = new CompletableFuture<>();

    // 用一个计数器跟踪完成数量
    // 每个子 Future 完成时计数器 -1
    // 计数器归零时 d.completeValue(null)

    // 实际实现用 BiRelay（二元关系）构建二叉树
    // 避免了 O(n) 的计数器竞争

    // 简化理解：
    // 每个子 cf 注册 whenComplete → 检查是否全部完成 → 是则 d.complete
    return d;
}
```

---

## 22. CompletableFuture 与线程池

### 线程池使用规则

```
方法后缀规则：
  无 Async 后缀 → 在当前线程执行（上游完成所在的线程）
  有 Async 后缀 → 在指定线程池执行

  thenApply(fn)         → 上游线程执行
  thenApplyAsync(fn)    → 默认线程池（ForkJoinPool.commonPool()）
  thenApplyAsync(fn, e) → 自定义线程池 e
```

### 默认线程池的问题

```java
// ForkJoinPool.commonPool() 的问题：
// ① 全局共享，所有并行流和 CompletableFuture 都用
// ② 线程数 = CPU 核数 - 1，IO 密集型场景不够
// ③ 一个任务阻塞会影响其他任务

// 正确做法：为 IO 密集型任务使用自定义线程池
ExecutorService ioPool = new ThreadPoolExecutor(
    10, 50, 60, TimeUnit.SECONDS,
    new LinkedBlockingQueue<>(1000),
    new ThreadFactoryBuilder().setNameFormat("io-pool-%d").build(),
    new ThreadPoolExecutor.CallerRunsPolicy()
);

CompletableFuture<String> cf = supplyAsync(() -> httpClient.get(url), ioPool)
    .thenApplyAsync(resp -> parseResponse(resp), ioPool)
    .thenAcceptAsync(data -> saveToDb(data), ioPool);
```

### 线程切换示意

```java
// 同步链（默认线程）
supplyAsync(() -> fetch(), pool)   // pool 线程
    .thenApply(s -> process(s))    // ★ pool 线程（上游完成的线程）
    .thenAccept(s -> save(s));     // ★ pool 线程

// 异步链
supplyAsync(() -> fetch(), pool1)       // pool1 线程
    .thenApplyAsync(s -> process(s), pool2)   // ★ pool2 线程
    .thenAcceptAsync(s -> save(s), pool3);    // ★ pool3 线程

// 混合链
supplyAsync(() -> fetch(), pool)         // pool 线程
    .thenApply(s -> process(s))          // pool 线程
    .thenAcceptAsync(s -> save(s), pool2); // ★ 切换到 pool2
```

---

## 23. JDK 9~12 CompletableFuture 增强

### JDK 9 新增

```java
// ① orTimeout：超时自动完成（异常）
completableFuture.orTimeout(5, TimeUnit.SECONDS);
// 超时后 result = AltResult(TimeoutException)

// ② completeOnTimeout：超时自动完成（默认值）
completableFuture.completeOnTimeout("default", 5, TimeUnit.SECONDS);
// 超时后 result = "default"

// ③ defaultExecutor：可覆盖默认线程池
// 子类可覆盖 defaultExecutor() 方法

// ④ newIncompleteFuture：可返回子类实例
// 子类可覆盖此方法返回自身类型，保持链式调用的类型

// ⑤ copy：创建一个独立的副本
CompletableFuture<String> copy = cf.copy();

// ⑥ minimalCompletionStage：只暴露 CompletionStage 接口
CompletionStage<String> stage = cf.minimalCompletionStage();
// 不暴露 get/join 等方法
```

### JDK 12 新增

```java
// ① exceptionallyCompose：异常时切换到另一个 CompletableFuture
cf.exceptionallyCompose(ex -> fallbackFuture());

// ② exceptionallyComposeAsync：异步版本
cf.exceptionallyComposeAsync(ex -> fallbackFuture(), executor);
```

### 超时机制源码

```java
// orTimeout 实现
public CompletableFuture<T> orTimeout(long timeout, TimeUnit unit) {
    if (result == null) {
        // ★ 创建一个延迟任务，超时后完成当前 Future
        ScheduledFuture<?> f = Delayer.delay(
            new Timeout(this), timeout, unit);
        // Timeout 是一个 Runnable：
        //   run() → cf.completeThrowable(new TimeoutException())
    }
    return this;
}

// Delayer 使用一个全局的 ScheduledThreadPoolExecutor
// 核心线程数=1，daemon=true，专门用于超时调度
static final class Delayer {
    static final ScheduledThreadPoolExecutor delayer;

    static {
        delayer = new ScheduledThreadPoolExecutor(1, daemonThreadFactory);
        delayer.setRemoveOnCancelPolicy(true);
    }

    static ScheduledFuture<?> delay(Runnable command, long delay, TimeUnit unit) {
        return delayer.schedule(command, delay, unit);
    }
}
```

---

# Part 4 — 综合

---

## 24. 常见面试题

### Q1：Stream 的底层实现原理是什么？

```
Stream 采用"惰性求值 + 融合执行"模型：

  ① 中间操作：创建 StatelessOp/StatefulOp，构建双向链表
  ② 终端操作：从后向前 wrapSink，组装 Sink 链
  ③ 数据拉取：Spliterator 遍历数据源，每个元素垂直通过 Sink 链
  ④ 短路操作：Sink.cancellationRequested() 返回 true 时停止遍历

关键设计：
  - 惰性求值：中间操作不执行，只有终端操作触发
  - 融合执行：多个操作合并为一次遍历，避免多次迭代
  - Sink 链：每个操作包装为 Sink，通过 downstream 引用传递数据
```

### Q2：Stream 的 sorted 是怎么实现的？为什么是有状态操作？

```
sorted 需要在所有元素收集完毕后才能排序，因此：
  ① begin 时创建 ArrayList
  ② accept 时将每个元素加入 list
  ③ end 时排序，然后逐个传给下游

这就是"有状态"的含义：操作的结果依赖所有输入元素，
无法在单次 accept 中完成，需要缓存中间状态。

对比 filter/map：
  filter/map 在 accept 中就能决定是否传递 / 如何变换，
  不依赖之前或之后的元素 → 无状态。
```

### Q3：parallelStream 的原理？什么场景下使用？

```
原理：
  ① 数据源被 Spliterator.trySplit 递归拆分
  ② 拆分后的子任务提交给 ForkJoinPool
  ③ 每个子任务独立执行 Sink 链
  ④ 通过 combiner 合并结果

适用场景（NQ 模型）：
  N（数据量）× Q（每个元素操作耗时）足够大
  - 数据量 > 1万
  - 每个元素操作耗时 > 微秒级
  - 数据源支持高效拆分（ArrayList > LinkedList > Stream.iterate）

不适用：
  - 数据量小（拆分开销 > 并行收益）
  - IO 密集（阻塞线程池）
  - 共享可变状态
  - 需要严格顺序保证
```

### Q4：Optional 的设计初衷是什么？有哪些使用限制？

```
设计初衷：
  ① 作为方法返回值，显式表达"可能没有值"
  ② 强制调用者处理空值情况
  ③ 支持链式调用替代嵌套 null 检查

使用限制：
  ① 不推荐作为类字段（额外内存 + 序列化问题）
  ② 不推荐作为方法参数（增加调用方负担）
  ③ 不推荐包装集合（空集合本身就能表达"没有"）
  ④ 不推荐直接 get() 不检查（用 orElse/orElseThrow）
  ⑤ 不推荐用 isPresent + get 替代 null 检查（用 map/flatMap）
```

### Q5：CompletableFuture 的底层实现原理？

```
核心数据结构：
  - result：存储结果或异常（CAS 更新）
  - completions：Treiber Stack，存储后续依赖操作

执行流程：
  ① supplyAsync 创建 CompletableFuture + 提交任务到线程池
  ② 任务完成 → CAS 设置 result → postComplete() 触发依赖栈
  ③ 依次弹出 Completion → tryFire() → 执行回调
  ④ tryFire 可能产生新的完成事件 → 递归触发下游

线程模型：
  - 不带 Async：在触发完成的线程执行回调
  - 带 Async：在指定线程池执行回调
  - 默认线程池：ForkJoinPool.commonPool()
```

### Q6：thenApply 和 thenCompose 的区别？

```
thenApply：  T → U           （同步映射，类似 Stream.map）
thenCompose：T → CF<U> → CF<U>（异步映射，类似 Stream.flatMap）

// thenApply：映射结果直接包装
cf.thenApply(s -> s.length())   // CompletableFuture<Integer>

// thenCompose：映射结果是另一个 CF，会"展平"
cf.thenCompose(s -> asyncFetch(s))  // CompletableFuture<Result>
// 不会变成 CompletableFuture<CompletableFuture<Result>>

选择：
  同步转换 → thenApply
  异步链式调用 → thenCompose
```

### Q7：CompletableFuture 如何处理异常？exceptionally 和 handle 的区别？

```
exceptionally：
  - 只在异常时触发
  - 正常结果直接透传
  - 可以返回默认值恢复

handle：
  - 正常和异常都触发
  - BiFunction<T, Throwable, U> 两个参数
  - 可以根据结果/异常返回不同的值

whenComplete：
  - 正常和异常都触发
  - BiConsumer<T, Throwable> 只消费，不改结果
  - 异常会继续透传

推荐用法：
  链式调用中 → exceptionally 处理可恢复异常
  最终汇总   → handle 统一处理
  日志记录   → whenComplete 不影响结果
```

### Q8：CompletableFuture.allOf 返回 Void，怎么获取各任务的结果？

```
// allOf 只保证全部完成，不聚合结果
// 需要手动获取各 Future 的结果

CompletableFuture<String> f1 = supplyAsync(() -> fetch1());
CompletableFuture<String> f2 = supplyAsync(() -> fetch2());
CompletableFuture<String> f3 = supplyAsync(() -> fetch3());

// 方案 1：allOf + join
CompletableFuture.allOf(f1, f2, f3).join();
String r1 = f1.join();  // 不阻塞，已完成
String r2 = f2.join();
String r3 = f3.join();

// 方案 2：收集到 List
List<String> results = Stream.of(f1, f2, f3)
    .map(CompletableFuture::join)   // allOf 之后 join 不阻塞
    .collect(Collectors.toList());

// 方案 3：JDK 9+ 使用 gather（预览）或自定义 Collector
```

### Q9：CompletableFuture 的超时怎么处理？

```
JDK 9+ 提供了两个超时方法：

orTimeout(duration, unit)：
  超时后以 TimeoutException 异常完成
  cf.orTimeout(5, SECONDS)
    .exceptionally(ex -> "timeout fallback");

completeOnTimeout(value, duration, unit)：
  超时后以指定默认值完成
  cf.completeOnTimeout("default", 5, SECONDS);

JDK 8 没有，需要手动实现：
  CompletableFuture<String> cf = supplyAsync(() -> fetch());
  ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(1);
  scheduler.schedule(() -> cf.complete("default"), 5, SECONDS);
```

### Q10：Stream 和 for 循环哪个性能更好？

```
简单遍历：for 循环更快
  - Stream 有对象创建（Sink 链、Spliterator）开销
  - Lambda 调用有额外开销（invokedynamic 首次慢，后续有缓存）
  - 简单操作（如求和、计数）for 循环比 Stream 快 2~5 倍

复杂操作：Stream 更优雅，性能差距可忽略
  - 多步 filter/map/reduce 融合为一次遍历
  - 并行流在大数据量下有优势
  - 代码可读性和可维护性 > 微小的性能差异

结论：
  - 性能关键路径 + 简单操作 → for 循环
  - 复杂数据处理 + 可读性优先 → Stream
  - 大数据量 + CPU 密集 → parallelStream
  - 不要为了用 Stream 而用 Stream
```

---

> 本文档系统拆解了 Java 8 函数式编程三大核心组件：Stream 的 Sink 链式流水线、Optional 的防御性空值处理、CompletableFuture 的异步回调栈。
> 建议学习路径：**Stream → Optional → CompletableFuture**。Stream 培养函数式思维，Optional 掌握链式调用模式，CompletableFuture 将异步编程从回调地狱中解放出来。
