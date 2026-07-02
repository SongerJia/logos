# Netty 底层原理与源码深度解析

> **本文档定位**：不看 Netty 源码项目，也能系统理解 Netty 的核心架构、线程模型、事件驱动机制、内存管理和零拷贝原理。
>
> **源码版本**：Netty 4.1.x（JDK NIO 封装层）
>
> **前置知识**：Java NIO（Selector/Channel/ByteBuffer）、Reactor 模式、责任链模式

---

## 目录

- [一、Netty 架构全景与核心组件](#一netty-架构全景与核心组件)
- [二、Reactor 线程模型](#二reactor-线程模型)
- [三、NIO 基础与 Netty 封装](#三nio-基础与-netty-封装)
- [四、EventLoop 与 EventLoopGroup 源码](#四eventloop-与-eventloopgroup-源码)
- [五、Channel 体系源码](#五channel-体系源码)
- [六、Pipeline 与 ChannelHandler 源码](#六pipeline-与-channelhandler-源码)
- [七、ByteBuf 源码深度解析](#七bytebuf-源码深度解析)
- [八、Netty 服务端启动流程全链路](#八netty-服务端启动流程全链路)
- [九、Netty 客户端启动流程](#九netty-客户端启动流程)
- [十、NIO 空轮询 Bug 与 Netty 解决方案](#十nio-空轮询-bug-与-netty-解决方案)
- [十一、零拷贝机制](#十一零拷贝机制)
- [十二、编解码器源码](#十二编解码器源码)
- [十三、心跳机制与 IdleStateHandler](#十三心跳机制与-idlestatehandler)
- [十四、FastThreadLocal 源码](#十四fastthreadlocal-源码)
- [十五、Recycler 对象池源码](#十五recycler-对象池源码)
- [十六、内存分配器 PooledByteBufAllocator 源码](#十六内存分配器-pooledbytebufallocator-源码)
- [十七、Netty vs Tomcat vs Nginx 对比](#十七netty-vs-tomcat-vs-nginx-对比)
- [十八、面试高频题 20 问](#十八面试高频题-20-问)
- [附录 A：Netty 核心类速查表](#附录-a-netty-核心类速查表)
- [附录 B：Netty 线程模型全景图](#附录-b-netty-线程模型全景图)
- [附录 C：推荐阅读路线](#附录-c-推荐阅读路线)

---

## 一、Netty 架构全景与核心组件

### 1.1 为什么需要 Netty

JDK 原生 NIO 有三大痛点，Netty 就是为解决这些痛点而生的：

```
JDK NIO 痛点                          Netty 解决方案
─────────────────────────────────────────────────────────────────
1. API 复杂易错                        → 简洁的 API 设计
   - Selector.select() 返回 0          → 封装空轮询检测
   - ByteBuffer flip() 忘记调用        → ByteBuf 读写指针分离
   - 需要手动处理半包问题               → 内置拆包器

2. 空轮询 Bug（epoll bug）             → 检测+重建 Selector
   - select() 醒了但没有事件           → 阈值检测，自动迁移
   - CPU 100%

3. 线程模型不完善                      → Reactor 模型封装
   - 需要手动管理线程                  → EventLoopGroup 自动分配
   - 业务线程与 IO 线程耦合             → 线程切换机制
```

### 1.2 Netty 核心组件一览

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Netty 核心架构                                    │
│                                                                         │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐               │
│  │ EventLoop     │   │ Channel       │   │ ByteBuf       │               │
│  │ (事件循环)     │   │ (网络通道)     │   │ (字节缓冲区)   │               │
│  │               │   │               │   │               │               │
│  │ ·execute()   │   │ ·read()      │   │ ·readByte()   │               │
│  │ ·run()       │   │ ·write()     │   │ ·writeByte()  │               │
│  │ ·任务队列     │   │ ·pipeline    │   │ ·引用计数      │               │
│  └──────┬───────┘   └──────┬───────┘   └───────────────┘               │
│         │                  │                                             │
│         │    ┌─────────────┘                                             │
│         ▼    ▼                                                            │
│  ┌──────────────────────────────────────────────────────┐               │
│  │              ChannelPipeline (事件管道)                  │              │
│  │                                                        │              │
│  │  Head ←→ Handler1 ←→ Handler2 ←→ ... ←→ Tail           │              │
│  │                                                        │              │
│  │  入站事件: Head → Tail 方向传播                          │              │
│  │  出站事件: Tail → Head 方向传播                          │              │
│  └──────────────────────────────────────────────────────┘               │
│                                                                         │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐               │
│  │ Bootstrap      │   │ EventLoopGroup │   │ Future/Promise │               │
│  │ (启动引导)      │   │ (事件循环组)    │   │ (异步回调)      │               │
│  └──────────────┘   └──────────────┘   └──────────────┘               │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.3 核心组件职责

| 组件 | 职责 | 对应 JDK NIO |
|------|------|-------------|
| **EventLoop** | 事件循环，执行 IO 操作和任务 | Selector + Thread |
| **EventLoopGroup** | EventLoop 集合，分配 EventLoop | Selector 管理者 |
| **Channel** | 网络连接封装，读写数据 | java.nio.Channel |
| **ChannelPipeline** | 处理器链，事件传播通道 | 无对应 |
| **ChannelHandler** | 业务处理器 | 无对应 |
| **ByteBuf** | 字节缓冲区 | ByteBuffer |
| **Bootstrap** | 客户端/服务端启动引导 | 无对应 |
| **Future/Promise** | 异步操作结果回调 | java.util.concurrent.Future |

### 1.4 Netty 的设计哲学

```
设计原则                              体现
───────────────────────────────────────────────────────
1. 异步 + 事件驱动          → 所有 IO 操作都是异步的，通过 Future/Promise 回调
   - channel.writeAndFlush() 返回 ChannelFuture
   - 不阻塞调用线程

2. 责任链模式               → ChannelPipeline 是双向链表
   - 入站事件从 Head 到 Tail
   - 出站事件从 Tail 到 Head
   - 每个 Handler 只关注自己的逻辑

3. 零拷贝                   → 多层次零拷贝
   - CompositeByteBuf（逻辑合并）
   - FileRegion（sendfile）
   - Unpooled.wrappedBuffer（共享数组）

4. 内存池                   → PooledByteBufAllocator
   - 类似 jemalloc 的内存分配算法
   - 减少 GC 压力
   - 引用计数管理

5. 无锁串行化设计            → 每个 Channel 绑定一个 EventLoop
   - 同一 Channel 的所有操作都在同一线程执行
   - 无需加锁
   - 避免 ThreadLocal 滥用
```

---

## 二、Reactor 线程模型

### 2.1 三种 Reactor 模型

#### 2.1.1 单线程 Reactor

```
┌─────────────────────────────────────┐
│           Reactor (单线程)            │
│                                     │
│  ┌─────────┐  ┌──────────────────┐  │
│  │ Selector │  │ 事件分发           │  │
│  └────┬────┘  │                  │  │
│       │       │ · accept         │  │
│       ▼       │ · read           │  │
│  ┌─────────┐  │ · decode         │  │
│  │ Acceptor│  │ · business logic │  │
│  └─────────┘  │ · encode         │  │
│       │       │ · send           │  │
│       ▼       └──────────────────┘  │
│  ┌─────────────────────────────┐    │
│  │      所有 Handler            │    │
│  │  Handler1  Handler2  Handler3│    │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘

特点：一个线程完成所有工作（accept → read → 处理 → write）
优点：简单，无线程切换开销，无线程安全问题
缺点：一个连接的处理阻塞所有连接，无法利用多核
```

#### 2.1.2 多线程 Reactor

```
┌─────────────────────────────────────────────────┐
│                 Reactor 多线程模型                │
│                                                 │
│  ┌─────────────────────┐                       │
│  │  Main Reactor        │                       │
│  │  (单线程)             │                       │
│  │  · accept 连接        │                       │
│  └──────────┬──────────┘                       │
│             │                                   │
│             ▼                                   │
│  ┌─────────────────────────────────────┐       │
│  │        Sub Reactor (线程池)           │       │
│  │                                      │       │
│  │  ┌──────┐ ┌──────┐ ┌──────┐       │       │
│  │  │Thread1│ │Thread2│ │Thread3│  ...   │       │
│  │  │      │ │      │ │      │       │       │
│  │  │ read │ │ read │ │ read │       │       │
│  │  │ 处理  │ │ 处理  │ │ 处理  │       │       │
│  │  │ write│ │ write│ │ write│       │       │
│  │  └──────┘ └──────┘ └──────┘       │       │
│  └─────────────────────────────────────┘       │
└─────────────────────────────────────────────────┘

特点：一个线程负责 accept，线程池负责 IO 读写和业务处理
优点：利用多核 CPU，提升处理能力
缺点：单个 Handler 可能阻塞 IO 线程
```

#### 2.1.3 主从 Reactor（Main-Sub Reactor）

```
┌─────────────────────────────────────────────────────────────┐
│                   主从 Reactor 模型                           │
│                                                             │
│  ┌───────────────────────────┐                             │
│  │  Boss Group (Acceptor)      │                             │
│  │  · 1 个线程                  │                             │
│  │  · 只负责 accept 新连接      │                             │
│  │  · 将连接分配给 Worker       │                             │
│  └──────────┬────────────────┘                             │
│             │                                               │
│             │  分配 SocketChannel                            │
│             ▼                                               │
│  ┌──────────────────────────────────────────────────┐       │
│  │              Worker Group (IO + 业务)               │       │
│  │                                                    │       │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐           │       │
│  │  │Worker 1  │ │Worker 2  │ │Worker 3  │  ...       │       │
│  │  │EventLoop │ │EventLoop │ │EventLoop │           │       │
│  │  │          │ │          │ │          │           │       │
│  │  │ Selector │ │ Selector │ │ Selector │           │       │
│  │  │ Channel A│ │ Channel C│ │ Channel E│           │       │
│  │  │ Channel B│ │ Channel D│ │ Channel F│           │       │
│  │  └─────────┘ └─────────┘ └─────────┘           │       │
│  └──────────────────────────────────────────────────┘       │
│                                                             │
│  特点：Boss Group 负责 accept，Worker Group 负责 IO 读写      │
│  优点：职责分离，IO 线程不被业务逻辑阻塞                        │
│  这是 Netty 推荐的模式                                        │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Netty 中的 Reactor 模型对应

```java
// 主从 Reactor 模型代码示例
EventLoopGroup bossGroup = new NioEventLoopGroup(1);     // Boss: 1个线程，负责 accept
EventLoopGroup workerGroup = new NioEventLoopGroup();    // Worker: 默认 CPU核心数×2，负责 IO

ServerBootstrap b = new ServerBootstrap();
b.group(bossGroup, workerGroup)                          // 设置主从 Reactor
 .channel(NioServerSocketChannel.class)
 .childHandler(new ChannelInitializer<SocketChannel>() {
     @Override
     protected void initChannel(SocketChannel ch) {
         ch.pipeline().addLast(new MyDecoder());
         ch.pipeline().addLast(new MyHandler());
     }
 });

// 源码对应关系：
// Boss Group    →  accept 事件处理
// Worker Group  →  read/write 事件处理
// ChannelPipeline →  Handler 链
```

### 2.3 Netty 的线程模型本质

```
一个 EventLoop 绑定一个线程 + 一个 Selector + 多个 Channel

EventLoop {
    Thread thread;           // 独立的线程
    Selector selector;       // Java NIO Selector
    Queue<Runnable> tasks;  // 任务队列
    
    // 核心：一个 Channel 在生命周期内只绑定一个 EventLoop
    // → 所有操作都在同一线程执行 → 无锁 → 无线程安全问题
}
```

---

## 三、NIO 基础与 Netty 封装

### 3.1 Java NIO 三大核心

```
┌──────────────────────────────────────────────────────────┐
│                    Java NIO 三大核心                       │
│                                                          │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐       │
│  │ Selector  │     │ Channel  │     │ ByteBuffer│       │
│  │ (选择器)   │     │ (通道)    │     │ (缓冲区)   │       │
│  │           │     │           │     │           │       │
│  │ select()  │◄───│ register  │     │ position  │       │
│  │           │     │ (注册)     │     │ limit     │       │
│  │ selected  │     │           │     │ capacity  │       │
│  │ keys()    │     │ read/write│◄───│ flip()    │       │
│  └──────────┘     └──────────┘     └──────────┘       │
│                                                          │
│  工作流程：                                               │
│  1. Channel 向 Selector 注册感兴趣的事件（OP_READ 等）      │
│  2. Selector.select() 阻塞等待事件就绪                     │
│  3. 事件就绪后，Selector 返回就绪的 SelectionKey            │
│  4. 从 SelectionKey 获取 Channel，执行 read/write           │
│  5. 数据读写到 ByteBuffer                                  │
└──────────────────────────────────────────────────────────┘
```

### 3.2 Selector 事件类型

```java
// Java NIO 四种事件
public interface SelectionKey {
    public static final int OP_READ    = 1 << 0;   // 0001 读就绪
    public static final int OP_WRITE   = 1 << 1;   // 0010 写就绪
    public static final int OP_CONNECT  = 1 << 2;   // 0100 连接就绪
    public static final int OP_ACCEPT   = 1 << 3;   // 1000 接收就绪
}
```

### 3.3 ByteBuffer 的痛点和 Netty ByteBuf 的改进

```
JDK ByteBuffer 的痛点：

┌──────────────────────────────────────────┐
│          ByteBuffer 结构                   │
│                                          │
│  position    limit     capacity          │
│    ↓          ↓          ↓               │
│    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]     │
│                                          │
│  痛点1: 读写共用一个 position             │
│  → 写完必须 flip() 切换到读模式           │
│  → 忘记 flip() 导致数据错乱               │
│                                          │
│  痛点2: 没有 dynamic 扩容                │
│  → 超出 capacity 直接报错                 │
│  → 需要手动分配新 Buffer 并复制           │
│                                          │
│  痛点3: 没有引用计数                      │
│  → 不知道何时可以释放堆外内存              │
│  → 容易内存泄漏                           │
└──────────────────────────────────────────┘

Netty ByteBuf 的改进：

┌──────────────────────────────────────────────────┐
│            ByteBuf 结构                           │
│                                                  │
│  discardable     readable      writable           │
│  bytes           bytes         bytes              │
│  ┌──────┐    ┌──────────┐    ┌──────────┐      │
│  │      │    │          │    │          │      │
│  0    readerIndex  writerIndex    capacity        │
│                                                  │
│  改进1: 读写指针分离                              │
│  → readerIndex 和 writerIndex 独立                │
│  → 不需要 flip()                                 │
│  → 读和写可以同时进行                             │
│                                                  │
│  改进2: 动态扩容                                  │
│  → writeBytes() 自动扩容                          │
│  → 容量 = 64 → 128 → 256 → ...                   │
│                                                  │
│  改进3: 引用计数                                  │
│  → ReferenceCounted 接口                          │
│  → retain() / release()                           │
│  → 自动内存管理                                   │
│                                                  │
│  改进4: 池化                                      │
│  → PooledByteBufAllocator                         │
│  → 减少 GC                                       │
│                                                  │
│  改进5: 零拷贝                                    │
│  → CompositeByteBuf 逻辑合并多个 ByteBuf          │
│  → 不需要物理复制                                 │
└──────────────────────────────────────────────────┘
```

---

## 四、EventLoop 与 EventLoopGroup 源码

### 4.1 EventLoop 继承体系

```
ScheduledExecutorService (JDK)
    ↑
EventExecutorGroup (Netty 接口)
    ↑
EventExecutor (Netty 接口)
    ↑
OrderedEventExecutor (Netty 接口, 保证事件顺序执行)
    ↑
SingleThreadEventExecutor (Netty 抽象类)
    ↑
SingleThreadEventLoop (Netty 抽象类)
    ↑
NioEventLoop (Netty 实现，基于 NIO Selector)
```

### 4.2 NioEventLoop 核心字段

```java
public final class NioEventLoop extends SingleThreadEventLoop {
    
    // 核心：Java NIO Selector
    private Selector selector;
    private Selector unwrappedSelector;
    
    // 已注册的 SelectionKey 数量
    private int cancelledKeys;
    
    // 空轮询计数器（解决 JDK 空轮询 Bug）
    private int selectCnt;
    
    // 处理 IO 事件的时间占比（默认 50%）
    // ioRatio = 50 表示 IO 操作和任务执行各占一半时间
    private int ioRatio = 50;
    
    // 任务队列（继承自 SingleThreadEventExecutor）
    // Queue<Runnable> taskQueue;
}
```

### 4.3 EventLoopGroup 创建过程

```java
// NioEventLoopGroup 创建
EventLoopGroup group = new NioEventLoopGroup();

// 源码：NioEventLoopGroup 构造方法
public class NioEventLoopGroup extends MultithreadEventLoopGroup {
    
    public NioEventLoopGroup() {
        this(0);
    }
    
    public NioEventLoopGroup(int nThreads) {
        this(nThreads, (Executor) null);
    }
    
    public NioEventLoopGroup(int nThreads, Executor executor) {
        this(nThreads, executor, SelectorProvider.provider());
    }
}

// 父类 MultithreadEventExecutorGroup 构造方法
public abstract class MultithreadEventExecutorGroup 
    extends AbstractEventExecutorGroup {
    
    private final EventExecutor[] children;
    private final AtomicInteger childIndex = new AtomicInteger();
    
    protected MultithreadEventExecutorGroup(int nThreads, Executor executor,
                                             EventExecutorChooserFactory chooserFactory, Object... args) {
        // 1. 确定线程数：如果传入 0，则默认为 CPU 核心数 × 2
        if (nThreads == 0) {
            nThreads = DEFAULT_EVENT_LOOP_THREADS;  // = NettyRuntime.availableProcessors() * 2
        }
        
        // 2. 创建 Executor（如果为 null）
        if (executor == null) {
            executor = new ThreadPerTaskExecutor(newDefaultThreadFactory());
        }
        
        // 3. 创建 nThreads 个 EventLoop
        children = new EventExecutor[nThreads];
        for (int i = 0; i < nThreads; i++) {
            children[i] = newChild(executor, args);  // → new NioEventLoop(...)
        }
        
        // 4. 创建 EventExecutorChooser（选择器）
        //    用于决定下一个 Channel 由哪个 EventLoop 处理
        chooser = chooserFactory.newChooser(children);
    }
}
```

### 4.4 EventExecutorChooser 选择策略

```java
// 当有新的 Channel 注册时，需要选择一个 EventLoop
// chooser 的作用就是决定选哪个 EventLoop

public final class DefaultEventExecutorChooserFactory {
    
    public EventExecutorChooser newChooser(EventExecutor[] executors) {
        // 判断 EventLoop 数量是否是 2 的幂次方
        if (isPowerOfTwo(executors.length)) {
            return new PowerOfTwoEventExecutorChooser(executors);
        } else {
            return new GenericEventExecutorChooser(executors);
        }
    }
    
    // 2的幂次方：用位运算（性能更高）
    private static final class PowerOfTwoEventExecutorChooser {
        private final AtomicInteger idx = new AtomicInteger();
        private final EventExecutor[] executors;
        
        public EventExecutor next() {
            // idx.getAndIncrement() & (executors.length - 1)
            // 位运算代替取模，更快
            return executors[idx.getAndIncrement() & executors.length - 1];
        }
    }
    
    // 非2的幂次方：用取模
    private static final class GenericEventExecutorChooser {
        private final AtomicInteger idx = new AtomicInteger();
        private final EventExecutor[] executors;
        
        public EventExecutor next() {
            // Math.abs(idx.getAndIncrement() % executors.length)
            return executors[Math.abs(idx.getAndIncrement() % executors.length)];
        }
    }
}

// 为什么 EventLoop 数量推荐 2 的幂次方？
// → 位运算 & 比 取模 % 快 3~5 倍
```

### 4.5 NioEventLoop.run() 核心源码

这是 Netty 最核心的方法，事件循环的入口：

```java
@Override
protected void run() {
    int selectCnt = 0;
    for (;;) {
        try {
            int strategy;
            try {
                // 1. 计算 select 策略
                // - 如果有任务在队列中 → SELECT_NOW（立即返回）
                // - 如果没有任务 → SELECT（阻塞等待）
                strategy = selectStrategy.calculateStrategy(selectNowSupplier, hasTasks());
            } catch (IOException e) {
                // 重建 Selector（处理 Selector 异常）
                rebuildSelector();
                selectCnt = 0;
                continue;
            }
            
            switch (strategy) {
                case SelectStrategy.CONTINUE:   // -2: 继续
                    selectCnt = 0;
                    continue;
                case SelectStrategy.BUSY_WAIT:  // -3: 忙等待（NIO 不支持）
                    // fall through
                case SelectStrategy.SELECT:     // -1: 阻塞等待
                    // 2. 执行 select()，设置超时
                    long curDeadlineNanos = nextScheduledTaskDeadlineNanos();
                    if (curDeadlineNanos == -1L) {
                        curDeadlineNanos = NONE;  // 没有定时任务
                    }
                    // 默认等待 0.5 秒
                    strategy = curDeadlineNanos == NONE 
                        ? selector.select()          // 无限等待
                        : selector.selectNowMillisDelayed(...);  // 带超时等待
                    
                    // 3. 空轮询检测
                    if (strategy == 0) {
                        // select() 返回 0 但有可能是 Bug
                        selectCnt++;
                        if (selectCnt >= SELECTOR_AUTO_REBUILD_THRESHOLD) {
                            // 450 次 → 触发空轮询 Bug
                            // 重建 Selector
                            rebuildSelector();
                            selector = this.unwrappedSelector;
                            selectCnt = 0;
                            continue;
                        }
                    } else {
                        selectCnt = 0;  // 有事件，重置计数器
                    }
                    break;
                default:
                    // 有任务，执行 selectNow()
            }
            
            // 4. 处理 IO 事件
            if (strategy > 0) {
                processSelectedKeys();  // 处理就绪的 SelectionKey
            }
            
            // 5. 执行任务队列中的任务
            // ioRatio 控制时间和任务时间的比例
            runAllTasks(ioTimeNano);  // ioTimeNano = 限制任务执行时间
            
        } catch (Throwable t) {
            handleLoopException(t);
        }
        
        // 6. 检查是否正在关闭
        if (isShuttingDown()) {
            closeAll();
            // 确认所有任务都执行完
            if (confirmShutdown()) {
                break;
            }
        }
    }
}
```

### 4.6 processSelectedKeys 源码

```java
private void processSelectedKeys() {
    if (selectedKeys != null) {
        // 优化的处理路径（Netty 用 SelectedSelectionKeySet 替代 JDK 的 HashSet）
        processSelectedKeysOptimized();
    } else {
        // 原始处理路径
        processSelectedKeysPlain(selector.selectedKeys());
    }
}

// Netty 优化：用数组替代 HashSet
private void processSelectedKeysOptimized() {
    for (int i = 0; i < selectedKeys.size; i++) {
        final SelectionKey k = selectedKeys.keys[i];
        selectedKeys.keys[i] = null;  // 帮助 GC
        
        // 获取 SelectionKey 附加的对象（NioChannel）
        final Object a = k.attachment();
        
        if (a instanceof AbstractNioChannel) {
            // 处理 Channel 的 IO 事件
            processSelectedKey(k, (AbstractNioChannel) a);
        } else {
            // 处理 NioTask
            NioTask<SelectableChannel> task = (NioTask<SelectableChannel>) a;
            processSelectedKey(k, task);
        }
    }
}

private void processSelectedKey(SelectionKey k, AbstractNioChannel ch) {
    final AbstractNioChannel.NioUnsafe unsafe = ch.unsafe();
    
    // 检查 SelectionKey 是否有效
    if (!k.isValid()) {
        final EventLoop eventLoop = ch.eventLoop();
        if (eventLoop != this) {
            return;
        }
        unsafe.close(unsafe.voidPromise());  // 关闭 Channel
        return;
    }
    
    try {
        int readyOps = k.readyOps();
        
        // 处理 CONNECT 事件（客户端连接成功）
        if ((readyOps & SelectionKey.OP_CONNECT) != 0) {
            int ops = k.interestOps();
            ops &= ~SelectionKey.OP_CONNECT;  // 移除 OP_CONNECT
            k.interestOps(ops);
            unsafe.finishConnect();
        }
        
        // 处理 WRITE 事件（可写）
        if ((readyOps & SelectionKey.OP_WRITE) != 0) {
            ch.unsafe().forceFlush();
        }
        
        // 处理 READ 或 ACCEPT 事件
        // 这两个事件共用同一处理逻辑
        if ((readyOps & (SelectionKey.OP_READ | SelectionKey.OP_ACCEPT)) != 0 
            || readyOps == 0) {
            unsafe.read();  // → AbstractNioByteChannel.NioByteUnsafe.read()
                            //   或 AbstractNioMessageChannel.NioMessageUnsafe.read()
        }
    } catch (CancelledKeyException ignored) {
        unsafe.close(unsafe.voidPromise());
    }
}
```

### 4.7 SelectedSelectionKeySet 优化

```java
// Netty 用数组替代 JDK 的 HashSet 来存储 SelectionKey
// 原因：HashSet 的 add/remove 性能不如数组

final class SelectedSelectionKeySet extends AbstractSet<SelectionKey> {
    
    // 用数组存储
    private SelectionKey[] keysA;
    private SelectionKey[] keysB;
    private int sizeA;
    private int sizeB;
    
    SelectedSelectionKeySet() {
        keysA = new SelectionKey[1024];
        keysB = new SelectionKey[1024];
    }
    
    @Override
    public boolean add(SelectionKey o) {
        if (o == null) return false;
        
        // 双缓冲设计：A 和 B 交替使用
        if (isA) {
            if (sizeA == keysA.length) {
                keysA = Arrays.copyOf(keysA, keysA.length << 1);  // 扩容
            }
            keysA[sizeA++] = o;
        } else {
            if (sizeB == keysB.length) {
                keysB = Arrays.copyOf(keysB, keysB.length << 1);
            }
            keysB[sizeB++] = o;
        }
        return true;
    }
    
    // 重置方法：在每次 select() 后调用
    // 返回当前填满的数组，同时切换到另一个数组
    SelectionKey[] flip() {
        if (isA) {
            isA = false;
            keysA[sizeA] = null;  // 帮助 GC
            return keysA;
        } else {
            isA = true;
            keysB[sizeB] = null;
            return keysB;
        }
    }
}
```

### 4.8 任务队列机制

```java
// SingleThreadEventExecutor 的任务执行
protected boolean runAllTasks(long timeoutNanos) {
    // 1. 合并定时任务到普通任务队列
    fetchFromScheduledTaskQueue();
    
    // 2. 从任务队列中取出所有任务
    Runnable task = pollTask();
    if (task == null) {
        return false;  // 没有任务
    }
    
    // 3. 计算任务执行截止时间
    final long deadline = ScheduledFutureTask.nanoTime() + timeoutNanos;
    long runTasks = 0;
    long lastExecutionTime;
    
    // 4. 循环执行任务
    for (;;) {
        safeExecute(task);          // 执行任务（try-catch 包裹）
        runTasks++;
        
        // 每执行 64 个任务，检查是否超时
        // 64 是为了平衡精度和性能
        if ((runTasks & 0x3F) == 0) {
            lastExecutionTime = ScheduledFutureTask.nanoTime();
            if (lastExecutionTime >= deadline) {
                break;  // 超时了，停止执行
            }
        }
        
        task = pollTask();
        if (task == null) {
            lastExecutionTime = ScheduledFutureTask.nanoTime();
            break;  // 没有更多任务了
        }
    }
    
    // 5. 收尾
    afterRunningAllTasks(lastExecutionTime);
    return true;
}

// ioRatio 的作用
// ioRatio = 50（默认）
// → IO 时间 : 任务时间 = 50 : 50
// → ioTimeNano = ioTime * (100 / ioRatio - 1) = ioTime * 1
// → 任务时间 = IO 时间

// ioRatio = 100
// → IO 时间 : 任务时间 = 100 : ∞
// → 任务时间无限制（IO 完成后执行所有任务）

// 推荐设置：
// - IO 密集型：ioRatio = 50（默认即可）
// - 业务密集型：ioRatio = 100 或适当降低
```

---

## 五、Channel 体系源码

### 5.1 Channel 继承体系

```
Channel (Netty 顶层接口)
    ↑
AbstractChannel (抽象基类)
    ↑
AbstractNioChannel (NIO Channel 基类)
    ↑
┌───────────────────────┬───────────────────────┐
│                       │                       │
AbstractNioMessageChannel    AbstractNioByteChannel
    ↑                       ↑
NioServerSocketChannel       NioSocketChannel
NioDatagramChannel
```

### 5.2 AbstractChannel 核心字段

```java
public abstract class AbstractChannel extends DefaultAttributeMap implements Channel {
    
    // 父 Channel（服务端的 SocketChannel 的 parent 是 ServerSocketChannel）
    private final Channel parent;
    
    // Channel 唯一 ID
    private final ChannelId id;
    
    // 底层 JDK Channel
    private final ChannelUnsafe unsafe;  // Unsafe 接口实现
    
    // ChannelPipeline（处理器链）
    private final DefaultChannelPipeline pipeline;
    
    // 绑定的 EventLoop
    private volatile EventLoop eventLoop;
    
    // 注册状态
    private volatile boolean registered;
}

// Unsafe 接口：Channel 的实际 IO 操作封装
interface Unsafe {
    void connect(SocketAddress remoteAddress, ...);
    void bind(SocketAddress localAddress, ...);
    void disconnect(...);
    void close(...);
    void beginRead();
    void write(Object msg, ...);
    void flush();
}
```

### 5.3 NioServerSocketChannel 创建

```java
public class NioServerSocketChannel extends AbstractNioMessageChannel 
    implements io.netty.channel.socket.ServerSocketChannel {
    
    private static ServerSocketChannel newSocket(SelectorProvider provider) {
        try {
            // 创建 JDK 的 ServerSocketChannel
            return provider.openServerSocketChannel();
        } catch (IOException e) {
            throw new ChannelException("...");
        }
    }
    
    public NioServerSocketChannel() {
        this(newSocket(DEFAULT_SELECTOR_PROVIDER));
    }
    
    public NioServerSocketChannel(ServerSocketChannel channel) {
        // OP_ACCEPT: 只关心 accept 事件
        super(null, channel, SelectionKey.OP_ACCEPT);
        config = new NioServerSocketChannelConfig(this, channel.socket());
    }
}

// 父类 AbstractNioChannel 构造方法
protected AbstractNioChannel(Channel parent, SelectableChannel ch, int readInterestOp) {
    super(parent);
    this.ch = ch;                    // 保存 JDK Channel
    this.readInterestOp = readInterestOp;  // 保存关注的事件
    try {
        ch.configureBlocking(false);  // 设置为非阻塞模式
    } catch (IOException e) {
        throw new ChannelException("...");
    }
}
```

### 5.4 NioMessageUnsafe.read()（服务端 accept）

```java
// NioServerSocketChannel 的 Unsafe 实现
private final class NioMessageUnsafe extends AbstractNioUnsafe {
    
    private final List<Object> readBuf = new ArrayList<Object>();
    
    @Override
    public void read() {
        assert eventLoop().inEventLoop();
        final ChannelConfig config = config();
        final ChannelPipeline pipeline = pipeline();
        // 一次最多接收 16 个连接（默认，可配置）
        final int maxMessagesPerRead = maxMessagesPerRead();
        
        int readMessages = 0;
        do {
            // 调用 JDK accept()，接收新连接
            int localRead = doReadMessages(readBuf);
            if (localRead == 0 || localRead == -1) {
                break;
            }
            readMessages += localRead;
            
            // 每次只读 maxMessagesPerRead 个，避免阻塞太久
        } while (readMessages < maxMessagesPerRead);
        
        // 依次触发 pipeline 事件
        int size = readBuf.size();
        for (int i = 0; i < size; i++) {
            readPending = false;
            // 触发 channelRead 事件
            // → pipeline 中的 ServerBootstrapAcceptor 会处理
            pipeline.fireChannelRead(readBuf.get(i));
        }
        
        readBuf.clear();
        pipeline.fireChannelReadComplete();
    }
}

// doReadMessages 实现
@Override
protected int doReadMessages(List<Object> buf) throws Exception {
    SocketChannel ch = SocketUtils.accept(javaChannel());
    
    try {
        if (ch != null) {
            // 将新连接的 SocketChannel 加入列表
            buf.add(new NioSocketChannel(this, ch));
            return 1;
        }
    } catch (Throwable t) {
        // ...
    }
    return 0;
}
```

### 5.5 NioByteUnsafe.read()（客户端读数据）

```java
// NioSocketChannel 的 Unsafe 实现
public abstract class AbstractNioByteChannel extends AbstractNioChannel {
    
    private final class NioByteUnsafe extends AbstractNioUnsafe {
        
        @Override
        public final void read() {
            final ChannelConfig config = config();
            final ByteBufAllocator allocator = config.getAllocator();
            // 分配 ByteBuf 的策略
            final RecvByteBufAllocator.Handle allocHandle = recvBufAllocHandle();
            
            ByteBuf byteBuf = null;
            int messages = 0;
            boolean close = false;
            
            try {
                do {
                    // 1. 分配 ByteBuf（自适应大小）
                    byteBuf = allocHandle.allocate(allocator);
                    // 2. 从 Channel 读取数据到 ByteBuf
                    allocHandle.lastBytesRead(doReadBytes(byteBuf));
                    
                    if (allocHandle.lastBytesRead() <= 0) {
                        // 没有数据，释放 ByteBuf
                        byteBuf.release();
                        byteBuf = null;
                        close = allocHandle.lastBytesRead() < 0;
                        break;
                    }
                    
                    // 3. 触发 pipeline.channelRead
                    pipeline.fireChannelRead(byteBuf);
                    byteBuf = null;
                    
                    messages++;
                } while (allocHandle.continueReading());
                
                // 4. 触发 channelReadComplete
                pipeline.fireChannelReadComplete();
                
                if (close) {
                    closeOnRead(pipeline);
                }
            } catch (Throwable t) {
                // 异常处理
            } finally {
                allocHandle.readComplete();
            }
        }
    }
}
```

### 5.6 AdaptiveRecvByteBufAllocator 自适应缓冲区

```java
// Netty 根据历史读取量自动调整下一次的 ByteBuf 大小
public class AdaptiveRecvByteBufAllocator {
    
    // 缓冲区大小序列（16 → 65536）
    private static final int[] SIZE_TABLE;
    static {
        List<Integer> sizeTable = new ArrayList<Integer>();
        // 16 ~ 512，每次 +16
        for (int i = 16; i < 512; i += 16) {
            sizeTable.add(i);
        }
        // 512 ~ ?, 每次 *2
        for (int i = 512; i > 0; i <<= 1) {
            sizeTable.add(i);
        }
        SIZE_TABLE = sizeTable.stream().mapToInt(i -> i).toArray();
    }
    
    // 自适应逻辑
    // 如果连续两次读取量 >= 预分配大小 → 增大预分配
    // 如果连续两次读取量 < 预分配大小的 1/4 → 减小预分配
    // → 自适应，避免分配过大（浪费内存）或过小（需要多次读取）
}
```

---

## 六、Pipeline 与 ChannelHandler 源码

### 6.1 ChannelPipeline 双向链表结构

```
┌──────────────────────────────────────────────────────────────────┐
│                      ChannelPipeline 双向链表                       │
│                                                                  │
│     ┌────────┐                                                    │
│     │ Head   │ ← 出站事件的起点 / 入站事件的终点                    │
│     │Context │                                                    │
│     └───┬────┘                                                    │
│         │                                                          │
│    ┌────▼─────┐     ┌──────────┐     ┌──────────┐             │
│    │ Context 1 │◄──►│ Context 2 │◄──►│ Context 3 │             │
│    │(Decoder)  │    │(Handler)  │    │(Encoder)  │             │
│    │ 入站: in   │    │ 入站: in   │    │ 出站: out  │             │
│    └──────────┘     └──────────┘     └────┬─────┘             │
│                                            │                     │
│     ┌────────┐                              │                     │
│     │ Tail   │ ◄── 入站事件的起点 / 出站事件的终点                  │
│     │Context │◄─────────────────────────────┘                     │
│     └────────┘                                                    │
│                                                                  │
│  入站事件传播方向: Head → Context1 → Context2 → Tail               │
│  出站事件传播方向: Tail → Context3 → Context2 → Context1 → Head    │
└──────────────────────────────────────────────────────────────────┘
```

### 6.2 DefaultChannelPipeline 核心字段

```java
public class DefaultChannelPipeline implements ChannelPipeline {
    
    final AbstractChannelHandlerContext head;  // 链表头
    final AbstractChannelHandlerContext tail;  // 链表尾
    final Channel channel;
    
    DefaultChannelPipeline(AbstractChannel channel) {
        this.channel = channel;
        
        // 创建 Head 和 Tail 节点
        tail = new TailContext(this);
        head = new HeadContext(this);
        
        // 构建双向链表
        head.next = tail;
        tail.prev = head;
    }
    
    // Head 节点：出站操作的最终执行者
    // 它会把出站操作委托给 Channel 的 Unsafe 执行实际的 IO
    final class HeadContext extends AbstractChannelHandlerContext 
        implements ChannelOutboundHandler, ChannelInboundHandler {
        
        @Override
        public void write(ChannelHandlerContext ctx, Object msg, ...) {
            // 委托给 Unsafe 执行真正的写操作
            unsafe.write(msg, promise);
        }
        
        @Override
        public void flush(ChannelHandlerContext ctx) {
            unsafe.flush();
        }
    }
    
    // Tail 节点：入站事件的终点
    final class TailContext extends AbstractChannelHandlerContext 
        implements ChannelInboundHandler {
        
        @Override
        public void channelRead(ChannelHandlerContext ctx, Object msg) {
            // 到达 Tail 表示消息没有被任何 Handler 消费
            // 释放 ByteBuf，避免内存泄漏
            ReferenceCountUtil.release(msg);
        }
    }
}
```

### 6.3 入站事件传播源码

```java
// 以 fireChannelRead 为例，分析入站事件传播过程

// 调用入口：pipeline.fireChannelRead(byteBuf)
@Override
public final ChannelPipeline fireChannelRead(Object msg) {
    // 从 Head 开始传播
    AbstractChannelHandlerContext.invokeChannelRead(head, msg);
    return this;
}

// AbstractChannelHandlerContext 的静态方法
static void invokeChannelRead(final AbstractChannelHandlerContext next, Object msg) {
    final Object m = next.pipeline.touch(ObjectUtil.checkNotNull(msg, "msg"), next);
    // 获取 next 的 Executor
    EventExecutor executor = next.executor();
    
    if (executor.inEventLoop()) {
        // 当前线程就是 EventLoop 线程，直接执行
        invokeChannelRead0(next, m);
    } else {
        // 不在 EventLoop 线程，提交到任务队列异步执行
        executor.execute(new Runnable() {
            public void run() {
                invokeChannelRead0(next, m);
            }
        });
    }
}

private static void invokeChannelRead0(AbstractChannelHandlerContext next, Object msg) {
    try {
        // 调用 Handler 的 channelRead 方法
        ((ChannelInboundHandler) next.handler()).channelRead(next, msg);
    } catch (Throwable t) {
        next.invokeExceptionCaught(t);
    }
}

// 在 Handler 的 channelRead 中，需要手动调用 ctx.fireChannelRead(msg) 来传播给下一个
public class MyHandler extends ChannelInboundHandlerAdapter {
    @Override
    public void channelRead(ChannelHandlerContext ctx, Object msg) {
        // 处理逻辑...
        
        // 传递给下一个 Inbound Handler
        ctx.fireChannelRead(msg);
    }
}

// ctx.fireChannelRead 的实现
@Override
public ChannelHandlerContext fireChannelRead(Object msg) {
    // findContextInbound() 从当前节点开始往前找下一个 Inbound Handler
    invokeChannelRead(findContextInbound(), msg);
    return this;
}

private AbstractChannelHandlerContext findContextInbound() {
    AbstractChannelHandlerContext ctx = this;
    do {
        ctx = ctx.next;
    } while (!ctx.inbound);  // 跳过 Outbound Handler
    return ctx;
}
```

### 6.4 出站事件传播源码

```java
// 以 write 为例，分析出站事件传播过程

// 调用入口：channel.writeAndFlush(msg)
// 实际调用的是：pipeline.writeAndFlush(msg)
@Override
public final ChannelFuture writeAndFlush(Object msg) {
    return tail.writeAndFlush(msg);
}

// 从 Tail 开始往前传播（与入站方向相反）
@Override
public ChannelFuture writeAndFlush(Object msg) {
    return writeAndFlush(msg, newPromise());
}

private ChannelFuture writeAndFlush(Object msg, ChannelPromise promise) {
    // ...
    final AbstractChannelHandlerContext next = findContextOutbound();
    // 找到下一个 Outbound Handler
    invokeWriteAndFlush(next, promise, msg);
    return promise;
}

private AbstractChannelHandlerContext findContextOutbound() {
    AbstractChannelHandlerContext ctx = this;
    do {
        ctx = ctx.prev;
    } while (!ctx.outbound);  // 跳过 Inbound Handler
    return ctx;
}

// 最终传播到 Head 节点
// HeadContext.write() 调用 unsafe.write() 执行真正的 IO 写入
```

### 6.5 Inbound 和 Outbound Handler 的区别

```java
// Inbound Handler（入站处理器）
// → 处理从网络读入的数据
// → 继承 ChannelInboundHandlerAdapter
// → 方法：channelRead, channelActive, channelInactive, ...

public class MyDecoder extends ChannelInboundHandlerAdapter {
    @Override
    public void channelRead(ChannelHandlerContext ctx, Object msg) {
        ByteBuf buf = (ByteBuf) msg;
        // 解码
        Object decoded = decode(buf);
        // 传递给下一个 Handler
        ctx.fireChannelRead(decoded);
    }
}

// Outbound Handler（出站处理器）
// → 处理要写出到网络的数据
// → 继承 ChannelOutboundHandlerAdapter
// → 方法：write, flush, bind, connect, ...

public class MyEncoder extends ChannelOutboundHandlerAdapter {
    @Override
    public void write(ChannelHandlerContext ctx, Object msg, ChannelPromise promise) {
        // 编码
        ByteBuf encoded = encode(msg);
        // 传递给下一个 Handler
        ctx.write(encoded, promise);
    }
}

// 注意：
// 1. Inbound Handler 从 Head 到 Tail 传播
// 2. Outbound Handler 从 Tail 到 Head 传播
// 3. 跳过与自己类型不同的 Handler
//    → Inbound Handler 不会被 Outbound 事件触发
//    → Outbound Handler 不会被 Inbound 事件触发
```

### 6.6 事件传播完整流程图

```
客户端发送数据 → 服务端处理 → 服务端返回响应

入站（读数据）：
  ┌──────────────────────────────────────────────────────────────┐
  │                                                              │
  │  Head ──channelRead──► Decoder ──channelRead──► Handler      │
  │                                                              │
  │  → 触发 fireChannelRead                                      │
  │  → 入站事件从 Head 向 Tail 传播                               │
  └──────────────────────────────────────────────────────────────┘

出站（写数据）：
  ┌──────────────────────────────────────────────────────────────┐
  │                                                              │
  │  Head ◄──write── Encoder ◄──write── Handler (ctx.write)      │
  │   │                                                          │
  │   └──unsafe.write()──► Socket                                │
  │                                                              │
  │  → 触发 ctx.write()                                          │
  │  → 出站事件从 Tail 向 Head 传播                               │
  └──────────────────────────────────────────────────────────────┘

完整流程：
  [1] 客户端发送数据
       ↓
  [2] NioEventLoop 检测到 OP_READ 事件
       ↓
  [3] NioByteUnsafe.read() 读取数据到 ByteBuf
       ↓
  [4] pipeline.fireChannelRead(byteBuf)
       ↓
  [5] Head → Decoder（入站）→ 解码 → Object
       ↓
  [6] Decoder → Handler（入站）→ 业务处理 → ctx.write(response)
       ↓
  [7] Tail ← Encoder（出站）← 编码 → ByteBuf
       ↓
  [8] Head.unsafe.write(byteBuf) → 写入 ChannelOutboundBuffer
       ↓
  [9] Head.unsafe.flush() → 写入 Socket
       ↓
  [10] 客户端收到响应
```

---

## 七、ByteBuf 源码深度解析

### 7.1 ByteBuf 分类

```
                    ByteBuf
                      │
          ┌───────────┴───────────┐
          │                       │
      Pooled                  Unpooled
     (池化)                   (非池化)
          │                       │
    ┌─────┴─────┐           ┌─────┴─────┐
    │           │           │           │
  Heap      Direct         Heap      Direct
  (堆内)    (堆外)         (堆内)    (堆外)

PooledHeapByteBuf    PooledDirectByteBuf    UnpooledHeapByteBuf    UnpooledDirectByteBuf
```

### 7.2 ByteBuf 核心结构

```java
public abstract class AbstractByteBuf extends ByteBuf {
    
    // 读指针
    int readerIndex;
    // 写指针
    int writerIndex;
    // 标记的读指针（用于 mark/reset）
    int markedReaderIndex;
    // 标记的写指针
    int markedWriterIndex;
    // 最大容量
    private int maxCapacity;
    
    @Override
    public ByteBuf writeByte(int value) {
        ensureWritable0(1);  // 确保有足够空间
        _setByte(writerIndex++, value);  // 写入并移动 writerIndex
        return this;
    }
    
    @Override
    public byte readByte() {
        checkReadableBytes0(1);  // 检查是否有数据可读
        int i = readerIndex;
        byte b = _getByte(i);
        readerIndex = i + 1;  // 移动 readerIndex
        return b;
    }
    
    // 动态扩容算法
    private int calculateNewCapacity(int minNewCapacity, int maxCapacity) {
        // 阈值：4MB
        int threshold = 1048576 * 4;  // 4MB
        
        if (minNewCapacity > threshold) {
            // 超过 4MB，每次 +4MB
            int newCapacity = minNewCapacity / threshold * threshold;
            if (newCapacity > maxCapacity - threshold) {
                newCapacity = maxCapacity;
            } else {
                newCapacity += threshold;
            }
            return newCapacity;
        }
        
        // 小于 4MB，倍增策略
        // 64 → 128 → 256 → 512 → 1024 → ... → 4194304
        int newCapacity = 64;
        while (newCapacity < minNewCapacity) {
            newCapacity <<= 1;  // 每次翻倍
        }
        return newCapacity;
    }
}
```

### 7.3 ByteBuf 读写指针操作

```
                    ByteBuf 读写指针

  discardable     readable      writable
  bytes           bytes         bytes
  ┌──────┐    ┌──────────┐    ┌──────────┐
  │ 0..r │    │   r..w   │    │  w..cap   │
  └──────┘    └──────────┘    └──────────┘
  ↑           ↑    ↑          ↑         ↑
  0    readerIndex   writerIndex    capacity

  操作：
  ┌──────────────────────────────────────────────────────────┐
  │ readByte()       → 读取 readerIndex 处字节，readerIndex++ │
  │ writeByte(b)     → 写入 writerIndex 处，writerIndex++     │
  │ markReaderIndex()→ 保存当前 readerIndex 到 markedReader  │
  │ resetReaderIndex()→ 恢复 readerIndex 到 markedReader     │
  │ skipBytes(n)     → readerIndex += n                       │
  │ clear()          → readerIndex = writerIndex = 0          │
  │ discardReadBytes()→ 丢弃已读部分，readerIndex = 0          │
  └──────────────────────────────────────────────────────────┘
```

### 7.4 引用计数

```java
// ByteBuf 实现 ReferenceCounted 接口
public interface ReferenceCounted {
    
    int refCnt();                    // 获取引用计数
    ReferenceCounted retain();       // 引用 +1
    ReferenceCounted retain(int increment);  // 引用 +n
    boolean release();               // 引用 -1，如果为 0 则释放
    boolean release(int decrement);  // 引用 -n
}

// 使用规范：
// 1. 谁创建谁释放
//    ByteBuf buf = ctx.alloc().buffer();
//    try { ... } finally { buf.release(); }

// 2. 谁消费谁释放
//    public void channelRead(ChannelHandlerContext ctx, Object msg) {
//        ByteBuf buf = (ByteBuf) msg;
//        try { ... } finally {
//            ReferenceCountUtil.release(msg);  // 消费后释放
//        }
//    }

// 3. 传递时 retain
//    public void channelRead(ChannelHandlerContext ctx, Object msg) {
//        ByteBuf buf = (ByteBuf) msg;
//        buf.retain();  // 引用 +1
//        asyncExecutor.submit(() -> {
//            try { ... } finally {
//                buf.release();  // 异步处理完后释放
//            }
//        });
//        ctx.fireChannelRead(msg);  // 继续传递
//    }

// 4. 不处理时直接传递（不需要 release）
//    public void channelRead(ChannelHandlerContext ctx, Object msg) {
//        ctx.fireChannelRead(msg);  // 不 release，交给下一个 Handler
//    }
```

### 7.5 内存泄漏检测

```java
// Netty 的内存泄漏检测机制
// 通过 ResourceLeakDetector 实现

public class ResourceLeakDetector<T> {
    
    // 检测级别
    public enum Level {
        DISABLED,    // 禁用
        SIMPLE,      // 简单（默认）：1% 抽样
        ADVANCED,   // 高级：默认 1% 抽样，但记录更多栈信息
        PARANOID    // 偏执：100% 抽样（影响性能，仅用于测试）
    }
    
    // 检测原理：
    // 1. 在 ByteBuf 创建时，以一定概率（默认 1%）创建 WeakReference
    // 2. 记录 ByteBuf 创建时的调用栈
    // 3. 当 GC 回收 ByteBuf 时，WeakReference 被放入 ReferenceQueue
    // 4. 如果 ByteBuf 被正确 release()，WeakReference 会从 ReferenceQueue 移除
    // 5. 如果 ByteBuf 被 GC 回收但未 release()，说明有内存泄漏
    // 6. 打印泄漏报告（创建时的调用栈）
    
    // 配置方式：
    // -Dio.netty.leakDetection.level=SIMPLE
    // -Dio.netty.leakDetection.level=ADVANCED
    // -Dio.netty.leakDetection.level=PARANOID
    
    // 最佳实践：
    // - 开发/测试环境：ADVANCED 或 PARANOID
    // - 生产环境：SIMPLE（默认）或 DISABLED
}
```

### 7.6 CompositeByteBuf（零拷贝合并）

```java
// CompositeByteBuf 将多个 ByteBuf 逻辑上合并为一个
// 不做物理复制，只维护一个 ByteBuf 数组

public class CompositeByteBuf extends AbstractReferenceCountedByteBuf {
    
    // 内部存储多个 ByteBuf 的组件
    private Component[] components;
    private int componentCount;
    
    // 读取数据时，自动跨组件读取
    @Override
    public byte getByte(int index) {
        // 找到 index 属于哪个组件
        Component c = findComponent(index);
        // 在该组件中读取（减去偏移量）
        return c.buf.getByte(index - c.offset);
    }
    
    // 使用场景：HTTP 响应 = Header + Body
    // 传统方式（复制）：
    //   ByteBuf all = ctx.alloc().buffer(header.readableBytes() + body.readableBytes());
    //   all.writeBytes(header).writeBytes(body);  // 物理复制
    
    // CompositeByteBuf（零拷贝）：
    //   CompositeByteBuf all = ctx.alloc().compositeBuffer();
    //   all.addComponents(true, header, body);  // 逻辑合并，无复制
    //   ctx.writeAndFlush(all);  // 写出时自动处理跨组件
}
```

---

## 八、Netty 服务端启动流程全链路

### 8.1 服务端启动代码

```java
// 标准服务端启动代码
EventLoopGroup bossGroup = new NioEventLoopGroup(1);
EventLoopGroup workerGroup = new NioEventLoopGroup();

try {
    ServerBootstrap b = new ServerBootstrap();
    b.group(bossGroup, workerGroup)
     .channel(NioServerSocketChannel.class)
     .option(ChannelOption.SO_BACKLOG, 1024)
     .childHandler(new ChannelInitializer<SocketChannel>() {
         @Override
         protected void initChannel(SocketChannel ch) {
             ChannelPipeline p = ch.pipeline();
             p.addLast(new StringDecoder());
             p.addLast(new StringEncoder());
             p.addLast(new MyServerHandler());
         }
     });

    // 绑定端口并启动
    ChannelFuture f = b.bind(8888).sync();
    
    // 等待服务端关闭
    f.channel().closeFuture().sync();
} finally {
    bossGroup.shutdownGracefully();
    workerGroup.shutdownGracefully();
}
```

### 8.2 bind() 全链路源码

```java
// 1. AbstractBootstrap.bind()
public ChannelFuture bind(int inetPort) {
    return bind(new InetSocketAddress(inetPort));
}

public ChannelFuture bind(SocketAddress localAddress) {
    validate();  // 验证配置
    return doBind(localAddress);
}

// 2. AbstractBootstrap.doBind()
private ChannelFuture doBind(final SocketAddress localAddress) {
    // 2.1 初始化并注册 Channel
    final ChannelFuture regFuture = initAndRegister();
    final Channel channel = regFuture.channel();
    
    if (regFuture.cause() != null) {
        return regFuture;  // 注册失败
    }
    
    // 2.2 如果注册完成（同步等待）
    if (regFuture.isDone()) {
        ChannelPromise promise = channel.newPromise();
        doBind0(regFuture, channel, localAddress, promise);
        return promise;
    } else {
        // 注册未完成，添加监听器异步执行
        final PendingRegistrationPromise promise = new PendingRegistrationPromise(channel);
        regFuture.addListener(new ChannelFutureListener() {
            @Override
            public void operationComplete(ChannelFuture future) throws Exception {
                // 注册完成后执行 doBind0
                doBind0(regFuture, channel, localAddress, promise);
            }
        });
        return promise;
    }
}
```

### 8.3 initAndRegister() 源码

```java
final ChannelFuture initAndRegister() {
    Channel channel = null;
    try {
        // 1. 创建 Channel
        channel = channelFactory.newChannel();
        // → reflect.newInstance(NioServerSocketChannel.class)
        // → 内部调用 JDK 的 SelectorProvider.openServerSocketChannel()
        
        // 2. 初始化 Channel
        init(channel);  // → ServerBootstrap.init()
    } catch (Throwable t) {
        if (channel != null) {
            channel.unsafe().closeForcursively();
        }
        return new DefaultChannelPromise(channel).setFailure(t);
    }
    
    // 3. 注册 Channel 到 EventLoop
    // config().group() 返回 BossGroup
    ChannelFuture regFuture = config().group().register(channel);
    
    if (regFuture.cause() != null) {
        if (channel.isRegistered()) {
            channel.close();
        } else {
            channel.unsafe().closeForcursively();
        }
    }
    return regFuture;
}
```

### 8.4 ServerBootstrap.init() 源码

```java
@Override
void init(Channel channel) {
    // 1. 设置 Channel 的 Option（SO_BACKLOG 等）
    setChannelOptions(channel, options0(), logger);
    
    // 2. 设置 Channel 的 Attribute
    setAttributes(channel, attrs0());
    
    // 3. 获取 ChannelPipeline
    ChannelPipeline p = channel.pipeline();
    
    // 4. 获取 WorkerGroup
    final EventLoopGroup currentChildGroup = childGroup;
    final ChannelHandler currentChildHandler = childHandler;
    final Entry<ChannelOption<?>, Object>[] currentChildOptions = childOptions;
    final Entry<AttributeKey<?>, Object>[] currentChildAttrs = childAttrs;
    
    // 5. 添加一个 ChannelInitializer 到 Pipeline
    // 这个 Handler 的作用是：在 Channel 注册后，添加 ServerBootstrapAcceptor
    p.addLast(new ChannelInitializer<Channel>() {
        @Override
        public void initChannel(final Channel ch) {
            final ChannelPipeline pipeline = ch.pipeline();
            
            // 5.1 添加用户配置的 Handler
            ChannelHandler handler = config.handler();
            if (handler != null) {
                pipeline.addLast(handler);
            }
            
            // 5.2 添加 ServerBootstrapAcceptor
            // 这是一个特殊 Handler，用于处理 accept 到的新连接
            ch.eventLoop().execute(new Runnable() {
                @Override
                public void run() {
                    pipeline.addLast(
                        new ServerBootstrapAcceptor(
                            ch, currentChildGroup, currentChildHandler,
                            currentChildOptions, currentChildAttrs));
                }
            });
        }
    });
}
```

### 8.5 Channel 注册到 EventLoop

```java
// MultithreadEventLoopGroup.register()
@Override
public ChannelFuture register(Channel channel) {
    // 1. 从 EventLoopGroup 中选择一个 EventLoop
    // 2. 由该 EventLoop 执行注册
    return next().register(channel);
}

// AbstractUnsafe.register()（核心注册方法）
@Override
public final void register(EventLoop eventLoop, final ChannelPromise promise) {
    // 1. 确保 EventLoop 不为 null
    ObjectUtil.checkNotNull(eventLoop, "eventLoop");
    
    // 2. 检查是否已注册
    if (isRegistered()) {
        promise.setFailure(new IllegalStateException("..."));
        return;
    }
    
    // 3. 绑定 EventLoop
    AbstractChannel.this.eventLoop = eventLoop;
    
    // 4. 如果当前线程不是 EventLoop 线程
    //    提交到 EventLoop 的任务队列异步执行
    if (eventLoop.inEventLoop()) {
        register0(promise);
    } else {
        try {
            eventLoop.execute(new Runnable() {
                @Override
                public void run() {
                    register0(promise);
                }
            });
        } catch (Throwable t) {
            // ...
        }
    }
}

// register0 核心方法
private void register0(ChannelPromise promise) {
    try {
        // 1. 检查是否已关闭
        if (!promise.setUncancellable() || !ensureOpen(promise)) {
            return;
        }
        
        // 2. 执行真正的注册（doRegister）
        // → AbstractNioChannel.doRegister()
        // → javaChannel().register(selector, 0, this)
        doRegister();
        
        // 3. 标记为已注册
        neverRegistered = false;
        registered = true;
        
        // 4. 执行 pipeline 中 pending 的 Handler（handlerAdded）
        pipeline.invokeHandlerAddedIfNeeded();
        
        // 5. 设置 promise 成功
        safeSetSuccess(promise);
        
        // 6. 触发 channelRegistered 事件（入站）
        pipeline.fireChannelRegistered();
        
        // 7. 如果是第一次注册且 Channel 是 Active 状态
        //    触发 channelActive 事件
        if (isActive()) {
            if (firstRegistration) {
                pipeline.fireChannelActive();
            } else if (config().isAutoRead()) {
                beginRead();
            }
        }
    } catch (Throwable t) {
        safeSetFailure(promise, t);
        closeForcibly();
    }
}
```

### 8.6 doBind0() 和 channelActive

```java
private static void doBind0(
    final ChannelFuture regFuture, final Channel channel,
    final SocketAddress localAddress, final ChannelPromise promise) {
    
    // 提交到 EventLoop 执行
    channel.eventLoop().execute(new Runnable() {
        @Override
        public void run() {
            if (regFuture.isSuccess()) {
                // 调用 Channel 的 bind 方法
                // → pipeline.bind() → 出站事件传播 → Head.bind()
                // → unsafe.bind() → doBind()
                channel.bind(localAddress, promise).addListener(
                    ChannelFutureListener.CLOSE_ON_FAILURE);
            } else {
                promise.setFailure(regFuture.cause());
            }
        }
    });
}

// channelActive → 开始 accept
// HeadContext.channelActive()
@Override
public void channelActive(ChannelHandlerContext ctx) {
    ctx.fireChannelActive();
    readIfIsAutoRead();
}

private void readIfIsAutoRead() {
    if (channel.config().isAutoRead()) {
        // → Channel.read() → pipeline.read() → Head.read()
        // → unsafe.beginRead() → doBeginRead()
        // → selectionKey.interestOps(interestOps | readInterestOp)
        // → 设置 OP_ACCEPT 事件
        channel.read();
    }
}

// 到这一步，ServerSocketChannel 已经：
// 1. 创建完成
// 2. 注册到 Selector
// 3. 绑定端口
// 4. 设置关注 OP_ACCEPT 事件
// → EventLoop 的 select() 就能检测到新连接了
```

### 8.7 ServerBootstrapAcceptor（新连接处理）

```java
// 当 BossGroup 的 EventLoop 检测到 OP_ACCEPT 事件
// → NioMessageUnsafe.read() → accept 新连接
// → pipeline.fireChannelRead(newChannel) 
// → 到达 ServerBootstrapAcceptor.channelRead()

private static class ServerBootstrapAcceptor extends ChannelInboundHandlerAdapter {
    
    private final EventLoopGroup childGroup;
    private final ChannelHandler childHandler;
    
    @Override
    @SuppressWarnings("unchecked")
    public void channelRead(ChannelHandlerContext ctx, Object msg) {
        final Channel child = (Channel) msg;
        
        // 1. 给新连接添加 childHandler（用户配置的 Handler）
        child.pipeline().addLast(childHandler);
        
        // 2. 设置 childOptions 和 childAttrs
        setChannelOptions(child, childOptions, logger);
        setAttributes(child, childAttrs);
        
        try {
            // 3. 将新连接注册到 WorkerGroup
            // → 从 WorkerGroup 选择一个 EventLoop
            // → 该 EventLoop 负责这个新连接的所有 IO 操作
            childGroup.register(child);
        } catch (Throwable t) {
            forceClose(child, t);
        }
    }
}
```

### 8.8 服务端启动完整流程图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Netty 服务端启动全链路                                   │
│                                                                         │
│  [1] new NioEventLoopGroup(1)        // 创建 Boss Group                   │
│       └── 创建 1 个 NioEventLoop                                         │
│           └── 每个 EventLoop 包含一个 Selector                           │
│                                                                         │
│  [2] new NioEventLoopGroup()         // 创建 Worker Group                │
│       └── 创建 CPU核心数×2 个 NioEventLoop                               │
│                                                                         │
│  [3] new ServerBootstrap()           // 创建启动引导                      │
│       └── group(boss, worker)       // 设置主从 Reactor                  │
│       └── channel(NioServerSocketChannel.class)                         │
│       └── childHandler(...)          // 设置子 Channel Handler            │
│                                                                         │
│  [4] bind(8888)                                                            │
│       │                                                                 │
│       ├── [4.1] channelFactory.newChannel()                              │
│       │    └── 创建 NioServerSocketChannel                               │
│       │    └── JDK ServerSocketChannel.configureBlocking(false)          │
│       │                                                                 │
│       ├── [4.2] init(channel)                                           │
│       │    └── 设置 Option/Attribute                                    │
│       │    └── Pipeline 添加 ChannelInitializer                          │
│       │                                                                 │
│       ├── [4.3] group().register(channel)                                │
│       │    └── BossGroup 选择一个 EventLoop                              │
│       │    └── eventLoop.execute(() -> register0())                      │
│       │    └── doRegister()                                             │
│       │    └── javaChannel().register(selector, 0, this)               │
│       │    └── pipeline.fireChannelRegistered()                         │
│       │    └── pipeline.fireChannelActive()                              │
│       │    └── Head.readIfIsAutoRead()                                  │
│       │    └── doBeginRead() → 设置 OP_ACCEPT                           │
│       │                                                                 │
│       └── [4.4] doBind0()                                                │
│            └── unsafe.bind() → doBind(localAddress)                      │
│            └── JDK ServerSocket.bind(8888)                               │
│            └── pipeline.fireChannelActive()                              │
│                                                                         │
│  [5] NioEventLoop.run() 开始事件循环                                     │
│       └── selector.select()  // 等待事件                                  │
│       └── processSelectedKeys()                                          │
│       └── processSelectedKey(OP_ACCEPT)                                  │
│       └── NioMessageUnsafe.read()                                       │
│            └── doReadMessages() → accept() → new NioSocketChannel      │
│            └── pipeline.fireChannelRead(newChannel)                     │
│            └── ServerBootstrapAcceptor.channelRead()                    │
│                 └── childGroup.register(newChannel)                    │
│                 └── WorkerGroup 选择 EventLoop                          │
│                 └── 新连接注册到 Worker EventLoop                       │
│                 └── doBeginRead() → 设置 OP_READ                        │
│                                                                         │
│  → 服务端开始接收数据                                                     │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 九、Netty 客户端启动流程

### 9.1 客户端启动代码

```java
EventLoopGroup group = new NioEventLoopGroup();

try {
    Bootstrap b = new Bootstrap();
    b.group(group)
     .channel(NioSocketChannel.class)
     .option(ChannelOption.TCP_NODELAY, true)
     .handler(new ChannelInitializer<SocketChannel>() {
         @Override
         protected void initChannel(SocketChannel ch) {
             ch.pipeline().addLast(new StringDecoder());
             ch.pipeline().addLast(new StringEncoder());
             ch.pipeline().addLast(new MyClientHandler());
         }
     });
    
    // 连接服务端
    ChannelFuture f = b.connect("127.0.0.1", 8888).sync();
    
    // 等待关闭
    f.channel().closeFuture().sync();
} finally {
    group.shutdownGracefully();
}
```

### 9.2 connect() 源码

```java
public ChannelFuture connect(String inetHost, int inetPort) {
    return connect(InetSocketAddress.createUnresolved(inetHost, inetPort));
}

private ChannelFuture doConnect(final SocketAddress remoteAddress,
                                 final SocketAddress localAddress) {
    // 1. 初始化并注册 Channel
    final ChannelFuture regFuture = initAndRegister();
    final Channel channel = regFuture.channel();
    
    if (regFuture.cause() != null) {
        return regFuture;
    }
    
    // 2. 注册完成后执行 connect
    if (regFuture.isDone()) {
        doConnect0(regFuture, channel, remoteAddress, localAddress, promise);
    } else {
        regFuture.addListener(new ChannelFutureListener() {
            @Override
            public void operationComplete(ChannelFuture future) {
                doConnect0(regFuture, channel, remoteAddress, localAddress, promise);
            }
        });
    }
    return promise;
}

// doConnect0
private static void doConnect0(...) {
    channel.eventLoop().execute(new Runnable() {
        @Override
        public void run() {
            if (regFuture.isSuccess()) {
                // 调用 pipeline.connect() → 出站传播 → Head.connect()
                // → unsafe.connect() → doConnect()
                channel.connect(remoteAddress, localAddress, promise);
            }
        }
    });
}
```

### 9.3 NioSocketChannel.doConnect()

```java
@Override
protected boolean doConnect(SocketAddress remoteAddress, SocketAddress localAddress) throws Exception {
    if (localAddress != null) {
        javaChannel().socket().bind(localAddress);  // 绑定本地地址
    }
    
    boolean success = false;
    try {
        // 调用 JDK SocketChannel.connect()
        // 非阻塞模式下，connect() 可能返回 false（连接未完成）
        boolean connected = javaChannel().connect(remoteAddress);
        
        if (!connected) {
            // 设置 OP_CONNECT 事件，等待连接完成
            selectionKey.interestOps(SelectionKey.OP_CONNECT);
        }
        success = true;
        return connected;
    } finally {
        if (!success) {
            doClose();
        }
    }
}
```

### 9.4 客户端 vs 服务端启动对比

```
┌──────────────────────────────────────────────────────────────────┐
│                  客户端 vs 服务端启动对比                           │
│                                                                  │
│  服务端:                          客户端:                         │
│  ServerBootstrap                  Bootstrap                       │
│  boss + worker 两个 Group          一个 Group                     │
│  NioServerSocketChannel            NioSocketChannel               │
│  bind(port) → 监听端口              connect(host, port) → 连接     │
│  childHandler → 新连接的 Handler    handler → 自己的 Handler       │
│  注册 OP_ACCEPT                   注册 OP_CONNECT                │
│                                                                  │
│  共同点:                                                         │
│  - 都通过 initAndRegister() 创建+注册 Channel                     │
│  - 都通过 ChannelPipeline 处理事件                                 │
│  - 都绑定一个 EventLoop                                           │
└──────────────────────────────────────────────────────────────────┘
```

---

## 十、NIO 空轮询 Bug 与 Netty 解决方案

### 10.1 什么是空轮询 Bug

```
JDK NIO 的 Epoll Bug：
  - Selector.select() 在某些情况下即使没有事件也会返回
  - 导致 CPU 100%
  - 这是一个 JDK 的已知 Bug（JDK-6403933）
  - 在 Linux 上更容易出现

  正常情况:
  select() → 阻塞等待 → 有事件 → 返回 > 0 → 处理事件

  Bug 情况:
  select() → 立即返回 0 → 没有事件 → 空转 → 再次 select() → 返回 0
  → 无限循环 → CPU 100%
```

### 10.2 Netty 的解决方案

```java
// NioEventLoop.run() 中的空轮询检测

@Override
protected void run() {
    int selectCnt = 0;
    for (;;) {
        try {
            // ... select 逻辑 ...
            
            if (strategy == 0) {
                // select() 返回 0
                selectCnt++;
                
                if (selectCnt >= SELECTOR_AUTO_REBUILD_THRESHOLD) {
                    // 默认阈值 = 450
                    // 连续 450 次 select() 返回 0
                    // → 判定为空轮询 Bug
                    // → 重建 Selector
                    rebuildSelector();
                    selector = this.unwrappedSelector;
                    selectCnt = 0;
                    continue;
                }
            } else {
                selectCnt = 0;  // 有事件，重置
            }
            
            // ... 处理事件和任务 ...
        } catch (Throwable t) {
            // ...
        }
    }
}

// rebuildSelector 重建过程
public void rebuildSelector() {
    // 1. 创建新的 Selector
    final Selector newSelector;
    newSelector = Selector.open();
    
    // 2. 将旧的 Selector 上所有注册的 Channel 迁移到新 Selector
    for (SelectionKey key : selector.keys()) {
        Object a = key.attachment();
        if (a instanceof AbstractNioChannel) {
            AbstractNioChannel ch = (AbstractNioChannel) a;
            // 在新 Selector 上重新注册
            ch.doRegisterWithNewSelector(newSelector);
            // 设置原来的 interestOps
            ch.selectionKey = newSelector.register(
                newSelector, key.interestOps(), a);
        }
    }
    
    // 3. 关闭旧 Selector
    selector.close();
    
    // 4. 替换为新的 Selector
    selector = newSelector;
}
```

### 10.3 空轮询检测的阈值

```
// 默认阈值
SELECTOR_AUTO_REBUILD_THRESHOLD = 450;

// 为什么是 450？
// - 太小：正常的 select 返回 0 也会触发重建（误判）
//   正常情况：select(timeout) 超时返回 0
//   每次超时 = 0.5s，450 次超时 = 225 秒
//   → 足够区分"正常超时"和"空轮询 Bug"
//   
// - 太大：空轮询期间 CPU 100% 时间太长
//   450 次空轮询 ≈ 几百毫秒 → 可接受

// 可配置：
// -Dio.netty.selectorAutoRebuildThreshold=512
```

---

## 十一、零拷贝机制

### 11.1 Netty 的四种零拷贝

```
┌──────────────────────────────────────────────────────────────────┐
│                    Netty 四种零拷贝                                │
│                                                                  │
│  1. 操作系统层面：FileRegion（sendfile）                          │
│     → 文件传输不经过用户态                                         │
│     → 内核态直接从文件描述符拷贝到 Socket                           │
│                                                                  │
│  2. ByteBuf 层面：CompositeByteBuf                               │
│     → 多个 ByteBuf 逻辑合并为一个                                   │
│     → 不做物理复制                                                 │
│                                                                  │
│  3. ByteBuf 层面：Unpooled.wrappedBuffer()                        │
│     → 多个 byte[] 包装为 ByteBuf                                   │
│     → 共享数组引用，不复制                                         │
│                                                                  │
│  4. ByteBuf 层面：ByteBuf.slice() / duplicate()                 │
│     → 创建视图，共享底层缓冲区                                      │
│     → 修改一个会影响另一个                                         │
└──────────────────────────────────────────────────────────────────┘
```

### 11.2 FileRegion 源码

```java
// FileRegion 使用 sendfile 零拷贝
// 数据不经过用户态，直接从文件到 Socket

public class DefaultFileRegion extends AbstractReferenceCounted implements FileRegion {
    
    private final File f;
    private final long position;
    private final long count;
    private long transferred;
    
    @Override
    public long transferTo(WritableByteChannel target, long position) throws IOException {
        // 调用 java.nio.FileChannel.transferTo()
        // → 底层调用 sendfile() 系统调用
        long count = this.count - position;
        if (count < 0) {
            return 0L;
        }
        if (count == 0) {
            return 0L;
        }
        
        long transferred = file.transferTo(this.position + position, count, target);
        this.transferred += transferred;
        return transferred;
    }
}

// 使用示例：
File file = new File("data.txt");
RandomAccessFile raf = new RandomAccessFile(file, "r");
FileChannel fc = raf.getChannel();

// 零拷贝传输文件
ctx.writeAndFlush(new DefaultFileRegion(fc, 0, fc.size()));

// 对比传统方式：
// 1. 从文件 read 到用户态 ByteBuf
// 2. 从 ByteBuf write 到 Socket
// → 2 次用户态-内核态切换 + 2 次数据复制

// sendfile 方式：
// → 0 次用户态-内核态切换 + 0 次数据复制（OS 直接 DMA 到 Socket）
// → 性能提升 2~3 倍
```

### 11.3 CompositeByteBuf 使用

```java
// 场景：HTTP 响应 = Header + Body
ByteBuf header = ctx.alloc().buffer(128);
header.writeBytes("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n".getBytes());

ByteBuf body = ctx.alloc().buffer(1024);
body.writeBytes("Hello World".getBytes());

// 方式 1：物理复制（有拷贝开销）
ByteBuf response1 = ctx.alloc().buffer(header.readableBytes() + body.readableBytes());
response1.writeBytes(header);
response1.writeBytes(body);
ctx.writeAndFlush(response1);

// 方式 2：CompositeByteBuf（零拷贝）
CompositeByteBuf response2 = ctx.alloc().compositeBuffer();
response2.addComponents(true, header, body);  // 逻辑合并
ctx.writeAndFlush(response2);
// → 不做物理复制，多个 ByteBuf 逻辑上视为一个
```

### 11.4 Unpooled.wrappedBuffer 和 slice

```java
// Unpooled.wrappedBuffer：将多个 byte[] 包装为 ByteBuf，不复制
byte[] header = "GET / HTTP/1.1\r\n".getBytes();
byte[] body = "Hello".getBytes();

// 零拷贝包装
ByteBuf buf = Unpooled.wrappedBuffer(header, body);
// → 直接引用原始数组，不复制
// → 注意：修改 byte[] 会影响 ByteBuf

// slice：创建视图，共享底层数组
ByteBuf buf2 = Unpooled.buffer(1024);
buf2.writeBytes("Hello World".getBytes());

ByteBuf slice1 = buf2.slice(0, 5);   // "Hello"
ByteBuf slice2 = buf2.slice(6, 5);   // "World"

// 修改 slice 会影响原始 buf
slice1.setByte(0, 'h');  // buf2 现在是 "hello World"

// duplicate：完整视图
ByteBuf dup = buf2.duplicate();
// → readerIndex/writerIndex 独立，但底层数组共享
```

---

## 十二、编解码器源码

### 12.1 ByteToMessageDecoder 源码

```java
// 解码器基类：将 ByteBuf 解码为 Java 对象
public abstract class ByteToMessageDecoder extends ChannelInboundHandlerAdapter {
    
    // 累积缓冲区
    ByteBuf cumulation;
    // 累积器：如何合并新到达的 ByteBuf
    private Cumulator cumulator = MERGE_CUMULATOR;
    
    @Override
    public void channelRead(ChannelHandlerContext ctx, Object msg) throws Exception {
        if (msg instanceof ByteBuf) {
            // 1. 创建累积缓冲区（如果不存在）
            ByteBuf data = (ByteBuf) msg;
            if (cumulation == null) {
                cumulation = data;  // 第一次直接赋值
            } else {
                // 2. 将新数据合并到累积缓冲区
                cumulation = cumulator.cumulate(ctx.alloc(), cumulation, data);
            }
            
            // 3. 调用 decode 方法尝试解码
            callDecode(ctx, cumulation, out);
            
            // 4. 如果累积缓冲区没有被消费
            if (cumulation != null && !cumulation.isReadable()) {
                // 全部消费完，释放
                cumulation.release();
                cumulation = null;
            }
        } else {
            ctx.fireChannelRead(msg);  // 非 ByteBuf，直接传递
        }
    }
    
    // 子类实现 decode 方法
    // protected abstract void decode(ChannelHandlerContext ctx, ByteBuf in, List<Object> out)
    
    // 示例：固定长度解码器
    // public class FixedLengthFrameDecoder extends ByteToMessageDecoder {
    //     private final int frameLength;
    //     @Override
    //     protected void decode(ctx, in, out) {
    //         while (in.readableBytes() >= frameLength) {
    //             ByteBuf frame = in.readBytes(frameLength);
    //             out.add(frame);  // 输出解码后的对象
    //         }
    //     }
    // }
}
```

### 12.2 LengthFieldBasedFrameDecoder（长度字段拆包器）

```java
// 最常用的拆包器：通过消息头中的长度字段来确定消息边界
public class LengthFieldBasedFrameDecoder extends ByteToMessageDecoder {
    
    private final int maxFrameLength;        // 最大帧长度
    private final int lengthFieldOffset;     // 长度字段偏移量
    private final int lengthFieldLength;     // 长度字段长度（1/2/3/4/8）
    private final int lengthAdjustment;     // 长度调整值
    private final int initialBytesToStrip;   // 跳过的字节数
    
    protected Object decode(ChannelHandlerContext ctx, ByteBuf in) throws Exception {
        // 1. 检查是否有足够的字节读取长度字段
        if (in.readableBytes() < lengthFieldOffset + lengthFieldLength) {
            return null;  // 不够，等更多数据
        }
        
        // 2. 读取实际帧长度
        int actualLengthFieldOffset = in.readerIndex() + lengthFieldOffset;
        long frameLength = getUnadjustedFrameLength(in, actualLengthFieldOffset,
            lengthFieldLength, byteOrder);
        
        // 3. 计算调整后的帧长度
        long frameLengthAfterAdjustment = frameLength + lengthAdjustment;
        
        // 4. 计算完整帧的长度
        long fullFrameLength = lengthFieldOffset + lengthFieldLength 
            + frameLengthAfterAdjustment;
        
        // 5. 检查是否超过最大长度
        if (fullFrameLength > maxFrameLength) {
            fail(in.readerIndex() + (int) fullFrameLength);
            return null;
        }
        
        // 6. 检查是否有完整的帧
        if (in.readableBytes() < fullFrameLength) {
            return null;  // 数据不完整，等更多
        }
        
        // 7. 跳过不需要的字节
        if (initialBytesToStrip > 0) {
            in.skipBytes(initialBytesToStrip);
        }
        
        // 8. 读取一帧数据
        int frameLengthToRead = (int)(fullFrameLength - initialBytesToStrip);
        ByteBuf frame = extractFrame(in, in.readerIndex(), frameLengthToRead);
        in.skipBytes(frameLengthToRead);
        
        return frame;
    }
}

// 消息格式示例：
// ┌─────────┬──────────────┬───────────┐
// │ Header  │ LengthField  │  Body     │
// │ (可选)   │ (4字节)      │ (N字节)   │
// └─────────┴──────────────┴───────────┘
//
// lengthFieldOffset = 0（长度字段在最前面）
// lengthFieldLength = 4（4字节长度）
// lengthAdjustment = 0（长度值就是 Body 长度）
// initialBytesToStrip = 0（不跳过，保留长度字段）
```

### 12.3 MessageToByteEncoder 源码

```java
// 编码器基类：将 Java 对象编码为 ByteBuf
public abstract class MessageToByteEncoder<I> extends ChannelOutboundHandlerAdapter {
    
    private final Class<? extends I> outboundMessageType;
    
    @Override
    public void write(ChannelHandlerContext ctx, Object msg, ChannelPromise promise) throws Exception {
        ByteBuf buf = null;
        try {
            // 1. 检查消息类型是否匹配
            if (acceptOutboundMessage(msg)) {
                @SuppressWarnings("unchecked")
                I cast = (I) msg;
                
                // 2. 分配 ByteBuf
                buf = allocateBuffer(ctx, cast, preferDirect);
                
                // 3. 调用子类的 encode 方法编码
                encode(ctx, cast, buf);
                
                // 4. 写入 Pipeline
                ctx.write(buf, promise);
            } else {
                // 类型不匹配，传递给下一个 Handler
                ctx.write(msg, promise);
            }
        } catch (EncoderException e) {
            throw e;
        } catch (Throwable e) {
            throw new EncoderException(e);
        } finally {
            if (buf != null) {
                buf.release();  // 释放
            }
        }
    }
    
    // 子类实现
    // protected abstract void encode(ChannelHandlerContext ctx, I msg, ByteBuf out)
    
    // 示例：String 编码器
    // public class StringEncoder extends MessageToByteEncoder<String> {
    //     @Override
    //     protected void encode(ctx, String msg, ByteBuf out) {
    //         out.writeCharSequence(msg, CharsetUtil.UTF_8);
    //     }
    // }
}
```

### 12.4 常见拆包器对比

```
┌──────────────────────────────────────────────────────────────────┐
│                    常见拆包器对比                                   │
│                                                                  │
│  拆包器                    原理                   适用场景          │
│  ─────────────────────────────────────────────────────────────   │
│  FixedLengthFrameDecoder   固定长度                 定长协议       │
│  LineBasedFrameDecoder     按换行符\n\r\n           文本协议       │
│  LengthFieldBasedFrameDecoder 按长度字段             最常用         │
│  DelimiterBasedFrameDecoder 按自定义分隔符           自定义协议     │
│                                                                  │
│  选择建议：                                                      │
│  - 自定义协议：LengthFieldBasedFrameDecoder（最灵活）              │
│  - 文本协议：LineBasedFrameDecoder                                │
│  - 简单场景：FixedLengthFrameDecoder                             │
└──────────────────────────────────────────────────────────────────┘
```

---

## 十三、心跳机制与 IdleStateHandler

### 13.1 IdleStateHandler 原理

```java
// IdleStateHandler 用于检测空闲状态
public class IdleStateHandler extends ChannelDuplexHandler {
    
    private final long readerIdleTimeNanos;  // 读空闲时间
    private final long writerIdleTimeNanos;  // 写空闲时间
    private final long allIdleTimeNanos;     // 读写空闲时间
    
    private ScheduledFuture<?> readerIdleTimeout;
    private ScheduledFuture<?> writerIdleTimeout;
    private ScheduledFuture<?> allIdleTimeout;
    
    private long lastReadTime;   // 最后一次读时间
    private long lastWriteTime;  // 最后一次写时间
    
    @Override
    public void channelAdded(ChannelHandlerContext ctx) throws Exception {
        // 初始化空闲检测任务
        if (readerIdleTimeNanos > 0) {
            // 添加定时任务：readerIdleTimeNanos 后检查
            readerIdleTimeout = ctx.executor().schedule(
                new ReaderIdleTimeoutTask(ctx), 
                readerIdleTimeNanos, TimeUnit.NANOSECONDS);
        }
        if (writerIdleTimeNanos > 0) {
            writerIdleTimeout = ctx.executor().schedule(
                new WriterIdleTimeoutTask(ctx),
                writerIdleTimeNanos, TimeUnit.NANOSECONDS);
        }
        if (allIdleTimeNanos > 0) {
            allIdleTimeout = ctx.executor().schedule(
                new AllIdleTimeoutTask(ctx),
                allIdleTimeNanos, TimeUnit.NANOSECONDS);
        }
    }
    
    // 读超时任务
    private final class ReaderIdleTimeoutTask implements Runnable {
        @Override
        public void run() {
            if (!channel.isOpen()) return;
            
            long nextDelay = readerIdleTimeNanos;
            if (!reading) {
                // 计算距离上次读取的时间
                nextDelay -= (System.nanoTime() - lastReadTime);
            }
            
            if (nextDelay <= 0) {
                // 读空闲超时
                // 1. 触发 IdleStateEvent 事件
                IdleStateEvent event = newIdleStateEvent(IdleState.READER_IDLE, true);
                channelIdle(ctx, event);
                
                // 2. 重新调度
                readerIdleTimeout = ctx.executor().schedule(
                    this, readerIdleTimeNanos, TimeUnit.NANOSECONDS);
            } else {
                // 未超时，下次检查
                readerIdleTimeout = ctx.executor().schedule(
                    this, nextDelay, TimeUnit.NANOSECONDS);
            }
        }
    }
}
```

### 13.2 常见心跳方案

```
方案 1：客户端定时发送心跳
  客户端 → 每 30 秒发送心跳包 → 服务端
  服务端 → 收到心跳后回复

  IdleStateHandler(0, 0, 60)
  → 60 秒没有读写 → 判定连接断开

方案 2：服务端发送心跳探测
  服务端 → 每 30 秒发送心跳 → 客户端
  IdleStateHandler(60, 0, 0)
  → 60 秒没有收到客户端数据 → 判定客户端断开

方案 3：双向心跳
  IdleStateHandler(30, 30, 0)
  → 读空闲 30 秒 + 写空闲 30 秒
  
  pipeline:
    IdleStateHandler(30, 30, 0)
    → 心跳 Handler（读空闲发心跳，写空闲关闭连接）
    → 业务 Handler
```

### 13.3 心跳使用示例

```java
// 服务端心跳配置
pipeline.addLast(new IdleStateHandler(60, 0, 0));  // 60秒读空闲
pipeline.addLast(new HeartbeatServerHandler());

// 服务端心跳处理
public class HeartbeatServerHandler extends ChannelInboundHandlerAdapter {
    @Override
    public void userEventTriggered(ChannelHandlerContext ctx, Object evt) throws Exception {
        if (evt instanceof IdleStateEvent) {
            IdleStateEvent e = (IdleStateEvent) evt;
            if (e.state() == IdleState.READER_IDLE) {
                // 读空闲 → 客户端可能断线
                System.out.println("客户端 60 秒未发送数据，关闭连接");
                ctx.close();
            }
        }
    }
}

// 客户端心跳配置
pipeline.addLast(new IdleStateHandler(0, 30, 0));  // 30秒写空闲
pipeline.addLast(new HeartbeatClientHandler());

// 客户端心跳处理
public class HeartbeatClientHandler extends ChannelInboundHandlerAdapter {
    @Override
    public void userEventTriggered(ChannelHandlerContext ctx, Object evt) throws Exception {
        if (evt instanceof IdleStateEvent) {
            IdleStateEvent e = (IdleStateEvent) evt;
            if (e.state() == IdleState.WRITER_IDLE) {
                // 写空闲 → 发送心跳
                ctx.writeAndFlush(new HeartbeatPacket());
            }
        }
    }
}
```

---

## 十四、FastThreadLocal 源码

### 14.1 为什么需要 FastThreadLocal

```
JDK ThreadLocal 的性能问题：
  - ThreadLocalMap 使用开放定址法（线性探测）解决哈希冲突
  - 每次 get/set 需要计算 hash 并可能线性探测
  - 在高并发下性能不理想

Netty FastThreadLocal 优化：
  - 每个线程维护一个 FastThreadLocalThread
  - InternalThreadLocalMap 使用数组存储（类似 ArrayList）
  - 每个 FastThreadLocal 有一个固定的 index
  - get/set 直接通过 index 访问 → O(1)
  - 没有 hash 冲突
```

### 14.2 FastThreadLocal 源码

```java
public class FastThreadLocal<V> {
    
    // 每个 FastThreadLocal 的唯一索引
    private final int index;
    
    public FastThreadLocal() {
        // 从 InternalThreadLocalMap 获取下一个可用索引
        index = InternalThreadLocalMap.nextVariableIndex();
    }
    
    public final V get() {
        // 1. 获取当前线程的 InternalThreadLocalMap
        InternalThreadLocalMap threadLocalMap = InternalThreadLocalMap.get();
        // 2. 通过 index 直接获取
        Object v = threadLocalMap.indexedVariable(index);
        if (v != InternalThreadLocalMap.UNSET) {
            return (V) v;
        }
        // 3. 没有初始化，调用 initialize()
        return initialize(threadLocalMap);
    }
    
    public final void set(V value) {
        // 1. 获取 ThreadLocalMap
        InternalThreadLocalMap threadLocalMap = InternalThreadLocalMap.get();
        // 2. 直接通过 index 设置
        if (value != InternalThreadLocalMap.UNSET) {
            threadLocalMap.setIndexedVariable(index, value);
        } else {
            remove();
        }
    }
}

// InternalThreadLocalMap.get()
public static InternalThreadLocalMap get() {
    Thread thread = Thread.currentThread();
    if (thread instanceof FastThreadLocalThread) {
        // FastThreadLocalThread 直接持有 map
        return ((FastThreadLocalThread) thread).threadLocalMap();
    } else {
        // 普通 Thread 使用 JDK ThreadLocal 存储
        return slowGet();
    }
}

// InternalThreadLocalMap
static final class InternalThreadLocalMap {
    // 数组存储
    private Object[] indexedVariables;
    
    // nextVariableIndex：全局递增的原子计数器
    private static final AtomicInteger nextIndex = new AtomicInteger();
    
    public static int nextVariableIndex() {
        int index = nextIndex.getAndIncrement();
        if (index < 0) {
            nextIndex.decrementAndGet();
            throw new IllegalStateException("too many thread-local variables");
        }
        return index;
    }
    
    // 通过 index 直接访问
    public Object indexedVariable(int index) {
        Object[] lookup = indexedVariables;
        if (index < lookup.length) {
            return lookup[index];
        } else {
            // 扩容
            return UNSET;
        }
    }
}
```

### 14.3 性能对比

```
              JDK ThreadLocal         FastThreadLocal
get()         hash + 线性探测           index 直接访问
set()         hash + 线性探测           index 直接设置
冲突处理       开放定址法              无冲突
扩容          Entry[] 扩容            Object[] 扩容
内存          每个 Entry 是弱引用       直接存对象
性能          ~50ns/get              ~10ns/get（快 3~5 倍）
```

---

## 十五、Recycler 对象池源码

### 15.1 为什么需要对象池

```
问题：
  - Netty 高频创建/销毁 ByteBuf 等对象 → GC 压力大
  - 临时对象在 Eden 区创建 → Minor GC 频繁

解决：
  - 对象池：对象用完不销毁，放回池中复用
  - 下次需要时从池中获取，避免创建新对象
  - 减少 GC 压力
```

### 15.2 Recycler 源码

```java
public abstract class Recycler<T> {
    
    // 每个 Recycler 有一个 ID
    private final int id;
    
    // 默认最大容量
    private static final int DEFAULT_INITIAL_MAX_CAPACITY = 32768;
    private static final int DEFAULT_MAX_CAPACITY_PER_THREAD;
    private static final int RATIO;  // 默认 8，每 8 个回收 1 个
    
    // 核心方法：获取对象
    public final T get() {
        if (maxCapacityPerThread == 0) {
            return newObject(handle);  // 不回收
        }
        
        // 1. 获取当前线程的 Stack
        Stack<T> stack = threadLocal.get();
        
        // 2. 从 Stack 的 DefaultHandle 数组中弹出一个
        DefaultHandle<T> handle = stack.pop();
        if (handle == null) {
            // 池中没有，创建新对象
            handle = stack.newHandle();
            handle.value = newObject(handle);
        }
        return (T) handle.value;
    }
    
    // 回收对象
    public final boolean recycle(T o, Handle<T> handle) {
        if (handle == null) return false;
        
        DefaultHandle<T> h = (DefaultHandle<T>) handle;
        h.lastRecycledId = id;  // 标记回收来源
        h.recycle();  // 放回 Stack
        
        return true;
    }
}
```

### 15.3 Recycler 工作流程

```
线程 A 创建对象 → 使用 → 回收
                                    │
                        ┌───────────┘
                        ▼
                ┌──────────────┐
                │ 线程 A 的 Stack │
                │ [Handle1]      │
                │ [Handle2]      │
                │ [Handle3]      │
                └──────────────┘
                        
线程 B 回收 A 创建的对象
                │
                ▼
        ┌───────────────────┐
        │ WeakOrderQueue      │
        │ (在线程 A 的 Stack 中) │
        │ → 多线程回收的暂存区   │
        └───────────────────┘
                │
                ▼ （线程 A 下次 pop 时）
        scavenge() → 从 Queue 转移到 Stack
                │
                ▼
        线程 A 复用对象
        
关键设计：
1. 每个 Stack 属于一个线程 → 无锁
2. 其他线程回收 → 放入 WeakOrderQueue → 不阻塞
3. 当 Stack 为空 → scavenge 从 Queue 转移
4. WeakOrderQueue 是 WeakReference → 线程结束时自动回收
```

---

## 十六、内存分配器 PooledByteBufAllocator 源码

### 16.1 内存分配层次

```
┌──────────────────────────────────────────────────────────────────┐
│                    PooledByteBufAllocator 内存分配层次                │
│                                                                  │
│  PooledByteBufAllocator                                          │
│  ├── PoolArena[] heapArenas       (堆内 Arena 数组)               │
│  ├── PoolArena[] directArenas     (堆外 Arena 数组)               │
│  │                                                              │
│  每个 PoolArena:                                                  │
│  ├── PoolChunkList<T> qInit       (已使用 0~25%)                 │
│  ├── PoolChunkList<T> q000        (已使用 0~50%)                 │
│  ├── PoolChunkList<T> q025        (已使用 25~75%)                │
│  ├── PoolChunkList<T> q050        (已使用 50~100%)               │
│  ├── PoolChunkList<T> q075        (已使用 75~100%)               │
│  ├── PoolChunkList<T> q100        (已使用 100%)                  │
│  ├── PoolSubpage<T>[] tinySubpages  (Tiny 小页面池)              │
│  └── PoolSubpage<T>[] smallSubpages (Small 小页面池)              │
│  │                                                              │
│  每个 PoolChunk:                                                  │
│  ├── 默认 16MB 内存                                                │
│  ├── 按 2048B 为单位拆分（PageRun）                                 │
│  └── 每个 PageRun 进一步拆分为 Subpage                              │
│  │                                                              │
│  每个 PoolSubpage:                                                │
│  ├── 按 elementSize 拆分                                           │
│  └── 通过 bitmap 记录哪些被分配                                      │
└──────────────────────────────────────────────────────────────────┘

分配流程：
  ByteBuf buf = allocator.directBuffer(1024);
  
  [1] allocator → 选择一个 PoolArena
      → 通过 ThreadLocal 缓存，每个线程绑定一个 PoolArena
      → 如果绑定的 Arena 不可用，轮询选择
      
  [2] PoolArena → 根据分配大小选择路径
      → Tiny (< 512B): tinySubpages
      → Small (512B~8KB): smallSubpages
      → Normal (> 8KB): PoolChunkList
      
  [3] PoolChunk → 分配 PageRun 或 Subpage
      → Subpage: 从 bitmap 中找到空闲的 elementSize
      → PageRun: 从 PageRun 数组中找到连续的 Page
      
  [4] 返回 ByteBuf（PooledByteBuf）
      → 持有 chunk、offset、length 信息
      → 引用计数 = 1
```

### 16.2 PooledByteBufAllocator 核心源码

```java
public class PooledByteBufAllocator extends AbstractByteBufAllocator {
    
    // 堆内 Arena 数组
    private final PoolArena<byte[]>[] heapArenas;
    // 堆外 Arena 数组
    private final PoolArena<ByteBuffer>[] directArenas;
    
    // 默认参数
    private static final int DEFAULT_PAGE_SIZE = 8192;         // 8KB
    private static final int DEFAULT_MAX_ORDER = 11;            // 11 层
    private static final int DEFAULT_CHUNK_SIZE = 16777216;     // 16MB
    
    public PooledByteBufAllocator() {
        this(DEFAULT_NUM_HEAP_ARENA, DEFAULT_NUM_DIRECT_ARENA, 
             DEFAULT_PAGE_SIZE, DEFAULT_MAX_ORDER);
    }
    
    // 分配堆外 ByteBuf
    @Override
    protected ByteBuf newDirectBuffer(int initialCapacity, int maxCapacity) {
        // 1. 获取当前线程的 PoolThreadCache
        PoolThreadCache cache = threadCache.get();
        // 2. 从 cache 获取 PoolArena
        PoolArena<ByteBuffer> directArena = cache.directArena;
        
        if (directArena != null) {
            // 3. 从 Arena 分配
            return directArena.allocate(cache, initialCapacity, maxCapacity);
        } else {
            // 兜底：使用非池化的堆外 ByteBuf
            return PlatformDependent.hasUnsafe()
                ? new UnpooledUnsafeDirectByteBuf(this, initialCapacity, maxCapacity)
                : new UnpooledDirectByteBuf(this, initialCapacity, maxCapacity);
        }
    }
}

// PoolThreadCache：每个线程一个缓存
final class PoolThreadCache {
    
    final PoolArena<byte[]> heapArena;
    final PoolArena<ByteBuffer> directArena;
    
    // MemoryRegionCache：按不同大小缓存
    // tiny/small 子页缓存
    private final MemoryRegionCache<byte[]>[] tinySubPageHeapCaches;
    private final MemoryRegionCache<ByteBuffer>[] tinySubPageDirectCaches;
    private final MemoryRegionCache<byte[]>[] smallSubPageHeapCaches;
    private final MemoryRegionCache<ByteBuffer>[] smallSubPageDirectCaches;
    
    // normal 缓存
    private final MemoryRegionCache<byte[]>[] normalHeapCaches;
    private final MemoryRegionCache<ByteBuffer>[] normalDirectCaches;
    
    // 分配时先从 ThreadCache 查找（无锁，快）
    // 找不到再从 Arena 分配
}
```

### 16.3 内存分配大小分类

```
┌──────────────────────────────────────────────────────────────────┐
│                    Netty 内存分配大小分类                            │
│                                                                  │
│  Tiny:    16B ~ 496B    → 从 TinySubpage 分配                    │
│  Small:   512B ~ 4KB   → 从 SmallSubpage 分配                   │
│  Normal:  8KB ~ 16MB   → 从 PoolChunk 的 Page 分配              │
│  Huge:    > 16MB       → 不池化，直接分配                         │
│                                                                  │
│  Tiny 详细分类（16 的倍数）：                                       │
│  16, 32, 48, 64, 80, ..., 496 (共 32 个规格)                     │
│                                                                  │
│  Small 详细分类（2 的幂次方）：                                      │
│  512, 1024, 2048, 4096 (共 4 个规格)                             │
│                                                                  │
│  Normal 详细分类（Chunk 的 Run 分配）：                             │
│  8KB, 16KB, 32KB, 64KB, ..., 16MB                               │
│                                                                  │
│  规格化逻辑：                                                      │
│  - 请求 1B → 规格化为 16B                                           │
│  - 请求 20B → 规格化为 32B                                         │
│  - 请求 600B → 规格化为 1024B                                      │
│  - 请求 9KB → 规格化为 16KB                                        │
└──────────────────────────────────────────────────────────────────┘
```

### 16.4 PoolChunk 的二叉树结构

```
PoolChunk 默认 16MB = 8KB × 2048 Pages
按 11 层完全二叉树管理（类似伙伴系统）：

层级    Page数量    大小
─────────────────────────────
 0       1         16MB     (整块)
 1       2          8MB     (各一半)
 2       4          4MB
 3       8          2MB
 4      16          1MB
 5      32        512KB
 6      64        256KB
 7     128        128KB
 8     256         64KB
 9     512         32KB
10    1024         16KB
11    2048          8KB     (单个 Page)

分配 16KB → 在第 9 层找一个空闲节点
分配 32KB → 在第 8 层找一个空闲节点
分配 8KB → 在第 11 层找一个空闲节点

通过 byte[] memoryMap 记录每个节点的状态
- 初始值 = 11（未分配）
- 分配后 = 12（不可用）
- 部分分配 = 对应层级值
```

---

## 十七、Netty vs Tomcat vs Nginx 对比

### 17.1 三者定位对比

```
┌──────────────────────────────────────────────────────────────────┐
│                    三者定位对比                                      │
│                                                                  │
│  Nginx         Netty              Tomcat                        │
│  ─────         ─────              ──────                        │
│  HTTP 服务器    网络框架            Servlet 容器                  │
│  反向代理      通用网络编程         Web 应用服务器                 │
│                                                                  │
│  ┌──────────┐  ┌──────────┐     ┌──────────┐                  │
│  │ 处理 HTTP │  │ 处理任意   │     │ 处理 HTTP │                  │
│  │ 反向代理  │  │ 网络协议   │     │ 运行 Java │                  │
│  │ 静态资源  │  │ TCP/UDP   │     │ Web 应用  │                  │
│  │ 负载均衡  │  │ HTTP/WS   │     │ Servlet   │                  │
│  └──────────┘  └──────────┘     └──────────┘                  │
│                                                                  │
│  事件模型      事件模型            线程模型                        │
│  epoll         epoll+NIO           BIO/NIO                      │
│  多进程        多线程              线程池                          │
│                                                                  │
│  编程语言      编程语言            编程语言                        │
│  C             Java               Java                           │
│                                                                  │
│  应用场景      应用场景            应用场景                        │
│  Web 服务器    RPC 框架            Web 应用                      │
│  API 网关      游戏服务器          REST API                      │
│  CDN           即时通讯            传统 Web                       │
│  负载均衡      物联网               企业应用                      │
└──────────────────────────────────────────────────────────────────┘
```

### 17.2 线程模型对比

```
┌────────────────────────────────────────────────────────────────────┐
│                      线程模型对比                                     │
│                                                                    │
│  Nginx (多进程 + 事件驱动):                                          │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │  Master Process                                           │      │
│  │  ┌────────┐ ┌────────┐ ┌────────┐                     │      │
│  │  │Worker 1│ │Worker 2│ │Worker N│  (单线程 + epoll)       │      │
│  │  └────────┘ └────────┘ └────────┘                     │      │
│  └──────────────────────────────────────────────────────────┘      │
│  → 每个 Worker 单线程，epoll 事件驱动                                │
│  → 无锁，进程隔离                                                    │
│                                                                    │
│  Netty (多线程 + 事件驱动):                                          │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │  BossGroup (1 线程)                                       │      │
│  │  ┌────────┐                                               │      │
│  │  │  Boss  │  (accept)                                     │      │
│  │  └───┬────┘                                               │      │
│  │      │                                                    │      │
│  │  WorkerGroup (N 线程)                                      │      │
│  │  ┌────────┐ ┌────────┐ ┌────────┐                          │      │
│  │  │Worker 1│ │Worker 2│ │Worker N│  (每线程一个 epoll)        │      │
│  │  │+任务队列│ │+任务队列│ │+任务队列│                          │      │
│  │  └────────┘ └────────┘ └────────┘                          │      │
│  └──────────────────────────────────────────────────────────┘      │
│  → Boss 负责 accept，Worker 负责 IO                                 │
│  → 每个 Worker 单线程 + epoll + 任务队列                              │
│                                                                    │
│  Tomcat (线程池):                                                    │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │  Acceptor 线程 (1~2)                                      │      │
│  │  ┌──────────┐                                             │      │
│  │  │ Acceptor │  → accept 后丢给线程池                        │      │
│  │  └────┬─────┘                                             │      │
│  │       │                                                   │      │
│  │  Poller 线程 (2~4)                                        │      │
│  │  ┌──────────┐                                             │      │
│  │  │ Poller   │  → epoll 检测可读                            │      │
│  │  └────┬─────┘                                             │      │
│  │       │                                                   │      │
│  │  Worker 线程池 (200~1000)                                 │      │
│  │  ┌────────┐ ┌────────┐ ┌────────┐                          │      │
│  │  │Thread 1│ │Thread 2│ │Thread N│  (每个请求一个线程)         │      │
│  │  │ Servlet│ │ Servlet│ │ Servlet│                          │      │
│  │  └────────┘ └────────┘ └────────┘                          │      │
│  └──────────────────────────────────────────────────────────┘      │
│  → 每个请求占用一个线程                                               │
│  → 并发数受线程池大小限制                                              │
└────────────────────────────────────────────────────────────────────┘
```

### 17.3 选型建议

```
场景                              推荐方案        原因
─────────────────────────────────────────────────────────────────────
HTTP Web 应用                      Tomcat         成熟的 Servlet 容器
REST API                           Tomcat/Spring  生态完善
RPC 框架                           Netty          自定义协议、高性能
即时通讯（IM）                      Netty          长连接、推送
游戏服务器                          Netty          自定义协议、低延迟
物联网（IoT）                      Netty          TCP/MQTT 协议
反向代理/负载均衡                   Nginx          成熟、高性能
静态资源/CDN                       Nginx          高效文件传输
API 网关                           Nginx/Gateway   按需求选择
```

---

## 十八、面试高频题 20 问

### Q1: Netty 的线程模型是什么？

**答**：Netty 采用主从 Reactor 多线程模型：
- Boss Group（1 个线程）负责 accept 新连接
- Worker Group（CPU 核心数×2 个线程）负责 IO 读写
- 每个 Channel 绑定一个 EventLoop，所有操作在同一个线程执行，无需加锁
- 业务耗时操作可以提交到业务线程池，避免阻塞 IO 线程

### Q2: EventLoop 和 EventLoopGroup 的关系？

**答**：
- EventLoopGroup 是 EventLoop 的集合，创建时分配 N 个 EventLoop
- 当有新 Channel 注册时，EventLoopGroup 通过 Chooser 选择一个 EventLoop
- Channel 在生命周期内绑定同一个 EventLoop，所有 IO 操作由该 EventLoop 执行
- EventLoop 内部有一个 Selector 和任务队列，负责事件循环和任务执行

### Q3: Netty 如何解决 JDK 空轮询 Bug？

**答**：
- 检测：每次 select() 返回 0 时计数器 +1，连续 450 次（默认）判定为空轮询 Bug
- 解决：重建 Selector——创建新 Selector，将旧 Selector 上的所有 Channel 迁移到新 Selector，关闭旧 Selector
- 阈值可配置：`-Dio.netty.selectorAutoRebuildThreshold=512`

### Q4: ByteBuf 和 ByteBuffer 的区别？

**答**：
| 特性 | ByteBuffer | ByteBuf |
|------|-----------|---------|
| 读写指针 | 共用一个 position | readerIndex + writerIndex 分离 |
| flip | 需要 flip() 切换读写 | 不需要 |
| 扩容 | 不支持 | 自动扩容 |
| 引用计数 | 无 | retain/release |
| 池化 | 无 | PooledByteBufAllocator |
| 零拷贝 | 无 | CompositeByteBuf |

### Q5: ByteBuf 的引用计数是什么？

**答**：
- ByteBuf 实现了 ReferenceCounted 接口
- 创建时引用计数 = 1
- retain() 计数 +1，release() 计数 -1
- 计数为 0 时释放底层内存（堆外内存尤其重要）
- 谁消费谁释放：Tail 节点会自动 release 未消费的 ByteBuf
- 内存泄漏检测：ResourceLeakDetector 通过 WeakReference 检测未 release 的 ByteBuf

### Q6: ChannelPipeline 的事件传播机制？

**答**：
- ChannelPipeline 是双向链表，包含 Head 和 Tail 两个特殊节点
- 入站事件（channelRead/channelActive）从 Head 向 Tail 传播
- 出站事件（write/bind/connect）从 Tail 向 Head 传播
- Inbound Handler 只处理入站事件，Outbound Handler 只处理出站事件
- 传播过程中通过 findContextInbound/Outbound 跳过不匹配的 Handler

### Q7: Netty 的零拷贝有哪些？

**答**：
1. **OS 层面**：FileRegion 使用 sendfile 系统调用，数据不经过用户态
2. **CompositeByteBuf**：多个 ByteBuf 逻辑合并，不做物理复制
3. **Unpooled.wrappedBuffer**：多个 byte[] 包装为 ByteBuf，共享数组引用
4. **slice/duplicate**：创建 ByteBuf 视图，共享底层缓冲区

### Q8: Netty 服务端启动流程？

**答**：
1. 创建 BossGroup 和 WorkerGroup
2. 创建 ServerBootstrap，配置 group、channel、handler
3. bind(port) → initAndRegister()
4. init：创建 NioServerSocketChannel → 设置 Option → 添加 ChannelInitializer
5. register：选择 EventLoop → doRegister（注册到 Selector）
6. doBind：JDK ServerSocket.bind(port)
7. channelActive → doBeginRead → 设置 OP_ACCEPT
8. NioEventLoop.run() 开始事件循环 → 等待 accept

### Q9: NioEventLoop.run() 的核心流程？

**答**：
1. select 策略：有任务 → selectNow()，无任务 → select(timeout)
2. 空轮询检测：select() 返回 0 计数 +1，达到阈值重建 Selector
3. processSelectedKeys：处理就绪的 SelectionKey（OP_READ/ACCEPT/WRITE/CONNECT）
4. runAllTasks：执行任务队列中的任务，受 ioRatio 控制时间占比
5. 循环以上步骤

### Q10: Netty 的内存分配器是怎么工作的？

**答**：
- PooledByteBufAllocator 管理 PoolArena（堆内/堆外）
- 每个 Thread 通过 PoolThreadCache 绑定一个 Arena
- 分配时先从 ThreadCache 查找（无锁快路径），找不到再从 Arena 分配
- Arena 内部：Tiny/Small 从 Subpage 分配，Normal 从 Chunk 的 Page 分配
- 内存释放后回到 ThreadCache 或 Arena，供下次复用
- 类似 jemalloc 算法，减少内存碎片和 GC 压力

### Q11: 什么是 Channel 的 Unsafe？

**答**：
- Unsafe 是 Channel 的内部接口，封装了实际的 IO 操作
- 定义了 connect/bind/disconnect/close/beginRead/write/flush 等方法
- 不同类型的 Channel 有不同的 Unsafe 实现（NioMessageUnsafe/NioByteUnsafe）
- Pipeline 的 Head 节点最终委托给 Unsafe 执行真正的网络 IO
- 之所以叫 Unsafe 是因为它不应该被用户直接调用

### Q12: Netty 如何处理半包/粘包问题？

**答**：Netty 提供了多种拆包器：
- **FixedLengthFrameDecoder**：固定长度拆包
- **LineBasedFrameDecoder**：按换行符拆包
- **LengthFieldBasedFrameDecoder**：按长度字段拆包（最常用）
- **DelimiterBasedFrameDecoder**：按自定义分隔符拆包

原理：ByteToMessageDecoder 累积数据，每次尝试解码，不够则等待更多数据

### Q13: Netty 的心跳机制怎么实现？

**答**：
- 使用 IdleStateHandler 检测空闲状态
- 三个参数：readerIdleTime（读空闲）、writerIdleTime（写空闲）、allIdleTime（读写空闲）
- 原理：通过 EventLoop 的 ScheduledTask 定时检测
- 超时触发 IdleStateEvent，在 userEventTriggered 中处理
- 常见方案：客户端定时发心跳，服务端读空闲超时则关闭连接

### Q14: FastThreadLocal 为什么比 ThreadLocal 快？

**答**：
- JDK ThreadLocal：ThreadLocalMap 用开放定址法（线性探测），有 hash 冲突
- FastThreadLocal：每个 FastThreadLocal 有固定 index，InternalThreadLocalMap 用数组存储
- get/set 直接通过 index 访问数组 → O(1)，无 hash 计算，无冲突
- 性能提升 3~5 倍

### Q15: Netty 的 Recycler 对象池怎么工作？

**答**：
- 每个 Stack 属于一个线程，存储回收的对象
- 同线程回收：直接放入 Stack（无锁）
- 跨线程回收：放入 WeakOrderQueue（避免 Stack 的并发访问）
- 当 Stack 为空时，scavenge 从 WeakOrderQueue 转移对象到 Stack
- WeakOrderQueue 是 WeakReference，线程结束时自动回收

### Q16: 什么是 ChannelOutboundBuffer？

**答**：
- 每个 Channel 关联一个 ChannelOutboundBuffer（出站缓冲区）
- write() 时数据先写入 ChannelOutboundBuffer（Entry 链表）
- flush() 时将 Entry 链表中的数据真正写入 Socket
- 支持批量写入（减少系统调用次数）
- 有高低水位线控制，防止 OOM

### Q17: Netty 中 write 和 flush 的区别？

**答**：
- **write(msg)**：将数据写入 ChannelOutboundBuffer，不立即发送
- **flush()**：将 ChannelOutboundBuffer 中的数据真正写入 Socket
- **writeAndFlush(msg)**：write + flush，立即发送
- 性能考虑：批量 write 后一次 flush，减少系统调用

### Q18: Netty 如何实现异步回调？

**答**：
- ChannelFuture/Promise 机制
- writeAndFlush() 返回 ChannelFuture
- 添加 GenericFutureListener 回调：
  ```java
  future.addListener(f -> {
      if (f.isSuccess()) { /* 成功 */ }
      else { /* 失败 */ }
  });
  ```
- 也可以 sync() 同步等待（不推荐在生产使用）

### Q19: Netty 的 ioRatio 是什么？

**答**：
- 控制 IO 操作和任务执行的时间比例
- ioRatio = 50（默认）：IO 时间 : 任务时间 = 50 : 50
- ioRatio = 100：IO 优先，任务在 IO 空闲时执行
- 作用：平衡 IO 处理和业务任务，防止任务执行过久阻塞 IO
- IO 密集型用默认值，业务密集型可调高

### Q20: Dubbo 和 Spring Cloud Gateway 中的 Netty 分别扮演什么角色？

**答**：
- **Dubbo**：Netty 作为底层通信框架，DubboProtocol 基于 Netty 实现 RPC 通信
  - NettyServer：接收请求
  - NettyClient：发送请求
  - 通过 Codec2 编解码 Dubbo 协议
  - 业务线程和 IO 线程分离（Dispatcher）

- **Spring Cloud Gateway**：
  - 基于 Netty + WebFlux 实现响应式网关
  - 底层用 Reactor Netty（Netty 的响应式封装）
  - Route Predicate 匹配 + Filter Chain 处理
  - 异步非阻塞，高并发性能优于 Tomcat

---

## 附录 A：Netty 核心类速查表

| 类名 | 职责 |
|------|------|
| EventLoop | 事件循环，执行 IO 和任务 |
| EventLoopGroup | EventLoop 集合 |
| NioEventLoop | 基于 NIO 的 EventLoop 实现 |
| NioEventLoopGroup | NioEventLoop 集合 |
| Channel | 网络连接 |
| NioServerSocketChannel | 服务端 Channel |
| NioSocketChannel | 客户端 Channel |
| ChannelPipeline | 处理器链 |
| ChannelHandler | 处理器接口 |
| ChannelInboundHandler | 入站处理器 |
| ChannelOutboundHandler | 出站处理器 |
| ChannelHandlerContext | 处理器上下文 |
| ByteBuf | 字节缓冲区 |
| CompositeByteBuf | 合并 ByteBuf |
| PooledByteBufAllocator | 池化分配器 |
| Bootstrap | 客户端启动 |
| ServerBootstrap | 服务端启动 |
| ChannelFuture | 异步结果 |
| ChannelPromise | 可写的 ChannelFuture |
| IdleStateHandler | 空闲检测 |
| ByteToMessageDecoder | 解码器基类 |
| MessageToByteEncoder | 编码器基类 |
| LengthFieldBasedFrameDecoder | 长度字段拆包器 |
| FastThreadLocal | 快速 ThreadLocal |
| Recycler | 对象池 |
| FileRegion | 文件零拷贝 |
| ChannelOutboundBuffer | 出站缓冲区 |

---

## 附录 B：Netty 线程模型全景图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Netty 线程模型全景图                                  │
│                                                                         │
│  Boss Group (1 Thread)                                                  │
│  ┌───────────────────────────────────────────┐                         │
│  │  NioEventLoop                              │                         │
│  │  ┌─────────────────────────────────────┐  │                         │
│  │  │  Selector (epoll/select)             │  │                         │
│  │  │  ┌───────────────────┐              │  │                         │
│  │  │  │  OP_ACCEPT          │              │  │                         │
│  │  │  │  ServerSocketChannel │              │  │                         │
│  │  │  └───────────────────┘              │  │                         │
│  │  │                                      │  │                         │
│  │  │  Task Queue (普通 + 定时)             │  │                         │
│  │  └─────────────────────────────────────┘  │                         │
│  │                                           │                         │
│  │  职责: accept 新连接                       │                         │
│  │  → NioMessageUnsafe.read()               │                         │
│  │  → pipeline.fireChannelRead(newChannel)  │                         │
│  │  → ServerBootstrapAcceptor               │                         │
│  │  → 分配给 Worker Group                    │                         │
│  └───────────────────────────────────────────┘                         │
│                      │                                                   │
│                      │ 分配 SocketChannel                                │
│                      ▼                                                   │
│  Worker Group (N Threads)                                              │
│  ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐      │
│  │  NioEventLoop 1   │ │  NioEventLoop 2   │ │  NioEventLoop N   │      │
│  │                    │ │                    │ │                    │      │
│  │  ┌──────────────┐ │ │  ┌──────────────┐ │ │  ┌──────────────┐ │      │
│  │  │  Selector     │ │ │  │  Selector     │ │ │  │  Selector     │ │      │
│  │  │  OP_READ     │ │ │  │  OP_READ     │ │ │  │  OP_READ     │ │      │
│  │  │  Channel A    │ │ │  │  Channel C    │ │ │  │  Channel E    │ │      │
│  │  │  Channel B    │ │ │  │  Channel D    │ │ │  │  Channel F    │ │      │
│  │  └──────────────┘ │ │  └──────────────┘ │ │  └──────────────┘ │      │
│  │                    │ │                    │ │                    │      │
│  │  Task Queue        │ │  Task Queue        │ │  Task Queue        │      │
│  │  ┌──────────────┐ │ │  ┌──────────────┐ │ │  ┌──────────────┐ │      │
│  │  │ Runnable      │ │ │  │ Runnable      │ │ │  │ Runnable      │ │      │
│  │  │ ScheduledTask │ │ │  │ ScheduledTask │ │ │  │ ScheduledTask │ │      │
│  │  └──────────────┘ │ │  └──────────────┘ │ │  └──────────────┘ │      │
│  │                    │ │                    │ │                    │      │
│  │  Pipeline:         │ │  Pipeline:         │ │  Pipeline:         │      │
│  │  Head → Decoder    │ │  Head → Decoder    │ │  Head → Decoder    │      │
│  │     → Handler      │ │     → Handler      │ │     → Handler      │      │
│  │     → Encoder      │ │     → Encoder      │ │     → Encoder      │      │
│  │     → Tail         │ │     → Tail         │ │     → Tail         │      │
│  └──────────────────┘ └──────────────────┘ └──────────────────┘      │
│                                                                         │
│  每个 Channel 绑定一个 EventLoop:                                        │
│  → 同一 Channel 的所有操作在同一线程执行                                    │
│  → 无锁，无线程安全问题                                                   │
│  → IO 操作和任务执行交替进行                                              │
│                                                                         │
│  事件循环 (run):                                                         │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │  while (true) {                                                 │   │
│  │    [1] select(timeout)           // 等待 IO 事件               │   │
│  │    [2] if 空轮询 > 450 → rebuildSelector()  // 重建 Selector    │   │
│  │    [3] processSelectedKeys()     // 处理就绪事件                │   │
│  │         → OP_READ: NioByteUnsafe.read() → 读取数据              │   │
│  │         → OP_ACCEPT: NioMessageUnsafe.read() → accept 新连接    │   │
│  │         → OP_WRITE: unsafe.forceFlush() → 刷写数据             │   │
│  │         → OP_CONNECT: unsafe.finishConnect() → 连接完成        │   │
│  │    [4] runAllTasks(ioTimeNano)   // 执行任务队列               │   │
│  │         → 普通任务 + 定时任务                                   │   │
│  │         → ioRatio 控制 IO:任务 时间比                            │   │
│  │  }                                                              │   │
│  └────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 附录 C：推荐阅读路线

### 与已有文档的衔接关系

```
                    Netty 在技术栈中的位置
                    ═════════════════════

┌─────────────────────────────────────────────────────────────┐
│                     请求全链路                                │
│                                                             │
│  浏览器                                                     │
│    ↓                                                        │
│  Nginx（反向代理 + 负载均衡）                                 │
│    ↓                                                        │
│  Spring Cloud Gateway                                      │
│    ├── 基于 Netty + WebFlux（响应式网关）                     │
│    ├── Route Predicate → 匹配路由                            │
│    └── Filter Chain → 过滤处理                               │
│    ↓                                                        │
│  下游服务                                                    │
│    ├── Spring IoC/DI（Bean 管理）                            │
│    ├── Spring AOP（@Transactional 事务代理）                  │
│    ├── MyBatis（SQL 执行）                                   │
│    └── MySQL（B+Tree 索引、MVCC 事务锁）                     │
│    ↓                                                        │
│  Dubbo RPC 调用                                             │
│    ├── 基于 Netty 通信                                       │
│    ├── Dubbo SPI 扩展                                        │
│    └── Cluster 容错 + LoadBalance 负载均衡                   │
│    ↓                                                        │
│  注册中心（Nacos / Zookeeper）                               │
│    ├── 服务注册与发现                                        │
│    └── 配置中心                                              │
└─────────────────────────────────────────────────────────────┘

Netty 是底层通信基座：
- Spring Cloud Gateway 基于 Netty 实现响应式网关
- Dubbo 基于 Netty 实现 RPC 通信
- Nacos 基于 Netty 实现 gRPC 通信
- MQTT、WebSocket 等协议基于 Netty 实现
```

### 推荐阅读顺序

```
1. Java NIO 基础（Selector/Channel/ByteBuffer）
   → 理解 NIO 三大核心

2. Reactor 模式
   → 理解事件驱动架构

3. Netty 架构
   → 理解 EventLoop/Channel/Pipeline/ByteBuf 四大核心

4. Netty 源码
   → 本文：从启动流程到事件循环到内存管理

5. 应用层
   → Dubbo 源码解析（基于 Netty 的 RPC）
   → Spring Cloud Gateway 源码解析（基于 Netty 的网关）
   → Nacos 源码解析（基于 Netty 的注册中心）
```

---

> **文档结束**
>
> 本文从 Netty 架构全景、Reactor 线程模型、NIO 封装、EventLoop/Channel/Pipeline/ByteBuf 源码、服务端/客户端启动流程、空轮询 Bug 解决方案、零拷贝机制、编解码器、心跳机制、FastThreadLocal、Recycler 对象池、PooledByteBufAllocator 内存分配器、与 Tomcat/Nginx 对比等方面系统解析了 Netty 的底层原理与源码实现。建议配合 Dubbo 和 Spring Cloud Gateway 的源码文档一起阅读，理解 Netty 作为底层通信基座在上层框架中的应用。
