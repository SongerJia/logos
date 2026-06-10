### 为什么这个模块是技术深度天花板

**ByteBuf 是 Netty 最引以为傲的设计之一**，也是和 Kafka/RocketMQ 零拷贝概念形成知识网络的关键节点。不懂 ByteBuf 就等于不懂 Netty 的内存设计哲学。

### 知识点表

|序号|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|2.1|**ByteBuf vs Java ByteBuffer**|🔴必背|① ByteBuffer 的痛点：Position/Limit/Mark 容易搞混、长度固定、只读或只写模式切换麻烦 ② ByteBuf 的改进：读写索引分离（readerIndex/writerIndex）、自动扩容、池化支持、支持复合缓冲区 ③ 面试：ByteBuf 相比 ByteBuffer 有哪些优势？（至少说出 3 点）|→ Java NIO Buffer / N5 内存池化|
|2.2|**ByteBuf 三种内存类型**|🔴必背|① **堆内内存（HeapByteBuf）**：分配快但受 GC 影响，I/O 读写需要一次复制 ② **堆外内存（DirectByteBuf）**：零拷贝基础，I/O 直接操作，但分配/回收成本高 ③ **池化堆外（PooledDirectByteBuf）**：Netty 默认，性能最优 ④ 面试：什么场景用堆内？什么场景用堆外？（大文件传输用堆外，小消息用堆内）|→ JVM 直接内存（Metaspace 外） / Kafka 零拷贝|
|2.3|**零拷贝的两种含义**|🔴🔴核心|① **OS 层面**：sendfile() 系统调用，数据不经过用户态（Kafka/RocketMQ 用的这种）② **Netty 层面**：CompositeByteBuf（合并多个 ByteBuf 不复制）/ DefaultFileRegion（包装 FileChannel.transferTo）③ 面试：Netty 的零拷贝和 OS 的零拷贝是一回事吗？（不是，Netty 是在用户态减少复制次数）|→ Kafka 零拷贝（M18）/ RocketMQ 零拷贝|
|2.4|**ByteBuf 的引用计数 & 内存泄漏检测**|🔴必背|① Netty 4+ 使用引用计数管理 ByteBuf（retain()/release()）② 内存泄漏检测级别：Disabled/Simple/Advanced/Paranoid（开发用 Advanced，生产用 Simple）③ 典型泄漏场景：Handler 里忘了 release()，或者抛异常时没释放 ④ 面试：Netty 怎么检测内存泄漏？你在项目中遇到过吗？怎么解决的？|→ JVM GC（引用计数 vs GC 根搜索）|
|2.5|**CompositeByteBuf 复合缓冲区**|🟡应掌握|① 可以将多个 ByteBuf 逻辑上合并成一个，物理上不复制 ② 典型场景：协议头 + 协议体 分别编码后合并发送 ③ 面试：CompositeByteBuf 的应用场景？和手工 copy 有什么区别？|→ N3 协议设计|
|2.6|**ByteBufAllocator & 池化深入**|🟡应掌握|① **PooledByteBufAllocator**（默认）：对象池复用，减少 GC 压力，ThreadLocal 缓存 ② **UnpooledByteBufAllocator**：每次新建，适合低并发场景 ③ 池化实现原理：类似内存分配器（Buddy Allocation），Page/SubPage 层级管理 ④ 面试：PooledByteBufAllocator 为什么快？内部怎么管理内存的？|→ N6 内存管理深入 / PostgreSQL 共享内存管理（类比）|

> **🏗️ 架构追问**：如果让你设计一个"通用高性能缓冲区"，你会怎么平衡以下矛盾：池化（快但复杂）vs 非池化（简单但有 GC 压力）/ 堆内（快分配）vs 堆外（零拷贝）？