---
title: Java IO面试理论
tags:
  - Java
  - Interview
---


## 一、IO 模型基础

> **Q1** 什么是同步/异步？什么是阻塞/非阻塞？这四个概念两两组合，分别对应什么 IO 模型？给一个生活化的例子说清楚。

> **Q2** BIO（Blocking IO）的工作方式是什么？一个连接一个线程有什么问题？`ServerSocket.accept()` 和 `Socket.read()` 分别阻塞在哪？

> **Q3** NIO（Non-blocking IO / New IO）和 BIO 的本质区别是什么？NIO 的三个核心组件（`Channel` / `Buffer` / `Selector`）分别起什么作用？

> **Q4** AIO（Asynchronous IO）和 NIO 的区别？异步 IO 的「回调」和「Future」两种模式分别怎么用？AIO 在 Linux 上依托什么内核机制？

> **Q5** 五种 IO 模型（阻塞 IO / 非阻塞 IO / IO 多路复用 / 信号驱动 IO / 异步 IO）的演进脉络是什么样的？画图说清楚各阶段数据流。

---

## 二、IO 多路复用（select / poll / epoll）

> **Q6** `select` 的工作原理是什么？它有哪些缺陷（FD_SETSIZE 限制、O(n) 遍历、内核态-用户态拷贝开销）？

> **Q7** `poll` 相比 `select` 改进了什么？还有什么没解决？

> **Q8** `epoll` 为什么比 `select/poll` 快？`epoll_create` / `epoll_ctl` / `epoll_wait` 三条命令分别做了什么？（红黑树 + 就绪链表 + 回调机制）

> **Q9** epoll 的 LT（水平触发）和 ET（边缘触发）区别？ET 模式为什么必须搭配非阻塞 IO？为什么要循环 read 直到 EAGAIN？

> **Q10** epoll 的「惊群效应」是什么？`EPOLLEXCLUSIVE` 怎么解决？Nginx 和 Netty 各自怎么处理惊群的？

---

## 三、Java NIO 核心

> **Q11** `Buffer` 的三个核心属性 `capacity` / `position` / `limit` 分别是什么？在读写模式下各自指向哪里？`flip()` 和 `clear()` 方法做了什么？

> **Q12** `ByteBuffer` 的 allocate（堆内存）和 allocateDirect（直接内存）区别？直接内存的优缺点？什么时候用直接内存？

> **Q13** `Selector` 的 `select()` / `selectNow()` / `select(long timeout)` 区别？Selector 怎么注册 Channel？`SelectionKey` 的四个事件（OP_READ / OP_WRITE / OP_CONNECT / OP_ACCEPT）什么时候触发？

> **Q14** `FileChannel` 的 `transferTo()` 和 `transferFrom()` 底层做了什么？这和操作系统零拷贝是什么关系？

> **Q15** Java NIO 的「空轮询」Bug（epoll bug）是什么现象？JDK 是怎么修复的？Netty 又是怎么处理的？

---

## 四、零拷贝

> **Q16** 传统 IO 的一次 `read()` + `write()`，数据在用户态和内核态之间经历了几次拷贝？几次上下文切换？画出完整的数据流向图。

> **Q17** Linux 的 `mmap` + `write` 实现了零拷贝吗？它减少了什么？

> **Q18** Linux 的 `sendfile()` 零拷贝是怎么做到的？DMA 拷贝、SG-DMA（Scatter-Gather DMA）在这个流程中起了什么作用？

> **Q19** Kafka 为什么用零拷贝？它在什么场景下用了零拷贝，什么场景下用了 `mmap`？这跟它的「顺序写盘」策略是什么关系？

---

## 五、Netty（面试标配）

> **Q20** Netty 的线程模型：「主从 Reactor 多线程」，画图说清楚 BossGroup / WorkerGroup 的分工，一个连接从建立到读写的完整流程。

> **Q21** Netty 的 `ChannelPipeline` 和 `ChannelHandler` 是什么关系？入站事件（`ChannelInboundHandler`）和出站事件（`ChannelOutboundHandler`）在 Pipeline 中的传播顺序？

> **Q22** Netty 的 `ByteBuf` 和 Java NIO 的 `ByteBuffer` 对比，有哪些优势？（读写双指针 / 零拷贝 / 引用计数 / 池化）

> **Q23** Netty 的零拷贝体现在哪些方面？（CompositeByteBuf / wrap / slice / FileRegion）

> **Q24** Netty 的心跳机制（`IdleStateHandler`）怎么用？读空闲 / 写空闲 / 读写空闲分别怎么处理？

> **Q25** Netty 的拆包粘包问题：`LineBasedFrameDecoder` / `DelimiterBasedFrameDecoder` / `FixedLengthFrameDecoder` / `LengthFieldBasedFrameDecoder` 分别解决什么场景？

---

## 六、序列化（IO 层视角）

> **Q26** Java 原生序列化（`ObjectOutputStream`）的缺陷是什么？（跨语言、版本兼容、性能、安全）为什么分布式场景基本不用它？

> **Q27** Protobuf / Thrift / Avro / Kryo / Hessian / Fastjson 这些序列化框架，从「编解码速度 / 序列化后大小 / 跨语言 / 可读性」四个维度怎么选型？

> **Q28** 为什么 Netty + Protobuf 是高性能 RPC（如 gRPC）的标配？`LengthFieldBasedFrameDecoder` + `ProtobufDecoder` 怎么组合解决拆包？

---

## 七、实战场景

> **Q29** 你要设计一个百万长连接的 IM 系统，为什么用 Netty？BossGroup 和 WorkerGroup 分别设几个线程？心跳间隔设多少？什么情况下连接数高但 QPS 低，怎么排查？

> **Q30** 大文件上传（2GB+）不用 OOM，服务端怎么设计？`HttpServletRequest.getInputStream()` 是会把整个文件读进内存吗？分片上传断点续传怎么做？
