### 为什么这个模块重要

**EventLoop 是 Netty 的"发动机"**。理解 EventLoop 的线程模型，才能写出正确且高性能的 Netty 应用。这也是 Netty 面试中"调优类问题"的知识基础。

### 知识点表

|序号|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|5.1|**EventLoop 的本质**|🔴必背|① 一个 EventLoop = 一个线程 + 一个 Selector + 一个任务队列 ② EventLoop 运行在一个死循环里：`select() → processSelectedKeys() → runAllTasks()` ③ 这种设计的优点：无锁（单个线程处理多个 Channel）/ 缺点：Handler 里不能阻塞（会卡住所有 Channel）④ 面试：EventLoop 的核心循环里做了哪三件事？|→ N1 Reactor 模型 / Redis 事件循环（类比）|
|5.2|**EventLoopGroup 的线程分配策略**|🔴必背|① 多个 Channel 如何分配到多个 EventLoop？**轮询（Round-Robin）**② 一旦分配，这个 Channel 的生命周期内都由同一个 EventLoop 处理（线程安全！）③ 引申：不能在 Handler 里调用 `synchronized`，因为本来就是单线程 ④ 面试：一个 EventLoop 管多少个 Channel？为什么这样设计？|→ Java 线程池（任务分配策略对比）|
|5.3|**TaskQueue & 定时任务**|🟡应掌握|① EventLoop 自带任务队列：`ctx.channel().eventLoop().execute(Runnable)` ② 定时任务：`ctx.channel().eventLoop().schedule(Runnable, delay, unit)` ③ 典型场景：延迟关闭连接 / 定时心跳 ④ 面试：Netty 里怎么提交一个异步任务到 EventLoop 线程？|→ Java ScheduledExecutorService（类比）|
|5.4|**Handler 中的线程安全陷阱**|🔴必背|① **正确**：在 Handler 里直接操作 ChannelHandlerContext（同一个 EventLoop 线程）② **错误**：启动新线程操作 Channel（跨线程！需要 `eventLoop().execute()`）③ **错误**：Handler 里有共享变量且有写操作（竞态条件）④ 面试：Netty Handler 里能开新线程吗？如果不能，应该怎么做？|→ Java 并发（线程安全）/ N4 @Sharable|
|5.5|**EventLoop 的 I/O 比例调优**|🟢了解|① `ioRatio` 参数：控制 EventLoop 花在 I/O 事件 vs 任务队列的时间比例（默认 50%）② 如果任务队列很忙（大量异步任务），可以适当降低 ioRatio ③ 监控指标：任务队列积压数 / EventLoop 处理延迟 ④ 面试：Netty 的 EventLoop 既处理 I/O 又处理任务，怎么调优？|→ N8 性能调优|

> **🏗️ 架构追问**：如果让你设计一个"支持阻塞操作的 Netty Handler"（比如 Handler 里需要调用一个慢速外部服务），你会怎么设计才能不阻塞 EventLoop？提示：业务线程池 + `eventLoop().execute()` 回传结果。