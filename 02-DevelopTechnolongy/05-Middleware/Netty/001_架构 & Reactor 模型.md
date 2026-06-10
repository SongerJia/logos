### 为什么这个模块最重要

**不理解 Reactor 模型，就等于没学 Netty。** 这是 Netty 所有设计的根源，也是面试第一问："讲一下 Netty 的线程模型"。

### 知识点表

|序号|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|1.1|**BIO/NIO/AIO 三兄弟回顾**|🔴必背|① BIO：一连接一线程，C10K 直接崩；NIO：多路复用，一个线程管多个连接；AIO：异步回调，Linux 支持不好 Netty 未采用 ② 面试：BIO 和 NIO 的根本区别是什么？（阻塞 vs 非阻塞，同步 vs 异步）|→ Java NIO（Selector/Channel/Buffer）|
|1.2|**Reactor 三种线程模型**|🔴🔴核心|① **单线程 Reactor**：所有操作一个线程（Redis 早期）→ ② **多线程 Reactor**：Acceptor 单独线程 + Worker 线程池 → ③ **主从多线程 Reactor**：Main Reactor 管连接 + Sub Reactor 管 I/O（Netty 默认） ③ 面试：画一下主从 Reactor 模型图，并解释各部分职责|→ Nginx Master-Worker（类比） / Redis 事件循环|
|1.3|**Netty 整体架构图**|🔴必背|① 核心组件：Bootstrap/ServerBootstrap → EventLoopGroup → EventLoop → Channel → Pipeline → Handler ② 启动流程图：创建 EventLoopGroup → 绑定端口 → 注册 Channel → 开始事件循环 ③ 面试：描述一下 Netty Server 的启动流程|→ Spring Boot 启动流程（类比）|
|1.4|**EventLoopGroup 设计哲学**|🔴必背|① BossGroup（Accept 连接）→ WorkerGroup（处理 I/O 读写）② 一个 EventLoop 绑定一个线程，一个 EventLoop 管理多个 Channel ③ 这种设计避免了锁竞争，但也意味着 Handler 里不能阻塞 ④ 面试：BossGroup 和 WorkerGroup 分别干啥？默认线程数多少？（CPU 核数×2）|→ N5 EventLoop 深入|
|1.5|**Java NIO 的坑 & Netty 怎么修**|🟡应掌握|① JDK NIO 的 epoll 空轮询 Bug（select 不阻塞一直返回）② Netty 的解决方案：重建 Selector ③ JDK NIO 的 API 难用（ByteBuffer 只读/写、Position/Limit 容易错）④ 面试：Netty 相比 JDK NIO 有哪些改进？|→ N2 ByteBuf 改进|
|1.6|**Netty 为什么不推荐 AIO**|🟢了解|① AIO 在 Linux 上底层还是 epoll 模拟，性能无优势反而增加复杂度 ② Netty 作者 Norman Maurer 的解释：AIO 在 Windows 有用，但服务器不用 Windows ③ 面试：Netty 支持 AIO 吗？为什么？（考察技术选型判断力）|→ 操作系统 I/O 模型|

> **🏗️ 架构追问**：如果让你实现一个"高性能 RPC 框架的 I/O 层"，你会选 Reactor 还是 Proactor 模型？各自适合什么场景？