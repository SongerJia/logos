### 为什么这个模块重要

**Pipeline 是 Netty 的"责任链模式"实现**，理解它就理解了 Netty 如何处理请求的完整生命周期。这也是和 Spring MVC 的 Filter 链、Servlet 的 Filter 链形成知识网络的地方。

### 知识点表

|序号|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|4.1|**Pipeline & Handler 整体设计**|🔴必背|① Pipeline 是双向链表，Head（入站起点）→ 自定义 Handler → Tail（出站终点）② **入站（Inbound）**：数据从网络来到应用（channelRead/exceptionCaught）③ **出站（Outbound）**：数据从应用发到网络（write/flush/close）④ 面试：画一下 Pipeline 的结构，标注入站和出站方向|→ Spring MVC 拦截器链（类比） / Servlet Filter|
|4.2|**ChannelHandler 的生命周期**|🔴必背|① `handlerAdded()` → `channelRegistered()` → `channelActive()` → `channelRead()` → `channelReadComplete()` → `channelInactive()` → `handlerRemoved()` ② `exceptionCaught()` 异常处理 ③ 面试：ChannelHandler 的完整生命周期是什么？|→ Java 生命周期回调（类比）|
|4.3|**ChannelHandlerContext & 传播机制**|🟡应掌握|① `ctx.write()` vs `ctx.channel().write()` 的区别：前者从当前 Handler 开始，后者从 Tail 开始 ② `ctx.fireChannelRead()` 触发下一个 Inbound Handler ③ 性能优化：尽量用 `ctx.write()` 减少不必要的 Handler 执行 ④ 面试：`ctx.write()` 和 `channel().write()` 有什么区别？|→ 责任链模式（GoF 设计模式）|
|4.4|**@Sharable 注解的深层含义**|🟡应掌握|① 标注 Handler 可以被多个 Pipeline 共享（无状态 Handler）② 典型场景：统计 Handler（ConnectionCountHandler）③ 坑：有成员变量的 Handler 千万不能标 @Sharable，会导致并发问题 ④ 面试：什么情况下用 @Sharable？不用会怎样？|→ N8 并发问题 / Java 线程安全|
|4.5|**常见的内置 Handler**|🟡应掌握|① `LoggingHandler`：日志 ② `IdleStateHandler`：心跳检测（读空闲/写空闲/读写空闲）③ `SslHandler`：TLS 加密 ④ `HttpRequestDecoder/HttpResponseEncoder`：HTTP 协议 ⑤ 面试：Netty 怎么做心跳检测？用了哪个 Handler？|→ N7 心跳机制 / WebSocket Ping/Pong|

> **🏗️ 架构追问**：如果让你设计一个"可热插拔的协议层"（运行时动态切换协议，如从 HTTP 切换到自定义二进制协议），你会怎么利用 Pipeline 的动态增删 Handler 能力？