### 为什么这个模块

**WebSocket 是 Netty 的经典应用场景**。很多面试会问："用 Netty 做过什么项目？"——WebSocket 推送服务是最容易讲出亮点的回答。

### 知识点表

|序号|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|7.1|**WebSocket 协议基础**|🟡应掌握|① HTTP Upgrade 机制：客户端发 `Upgrade: websocket` → 服务端 101 Switching Protocols ② 数据帧：Opcode（文本/二进制/ping/pong/close）③ 和 HTTP 长轮询（Long Polling）对比：实时性更好，但穿透代理/CDN 需要额外处理 ④ 面试：WebSocket 和 HTTP 长轮询的区别？各自适用场景？|→ HTTP/1.1 协议 / Nginx WebSocket 代理配置|
|7.2|**Netty WebSocket 开发**|🟡应掌握|① 需要的 Handler：`WebSocketServerProtocolHandler`（处理握手和帧）+ `TextWebSocketFrame` / `BinaryWebSocketFrame`（消息类型）② 心跳：Ping/Pong 帧 ③ 群发消息：维护 ChannelGroup（Netty 提供的 Channel 集合）④ 面试：用 Netty 写一个 WebSocket 聊天室，核心代码怎么写？|→ N4 Pipeline / ChannelGroup|
|7.3|**心跳检测 & 空闲检测**|🟡应掌握|① `IdleStateHandler`：读空闲（服务端检测客户端是否 alive）/ 写空闲 / 读写空闲 ② 超时后触发 `userEventTriggered(ctx, IdleStateEvent)` → 发送 Ping 或关闭连接 ③ 典型参数：读空闲 60s → 发送 Ping → 再 10s 没 Pong → 关闭 ④ 面试：Netty 怎么保持长连接不中断？心跳机制怎么实现？|→ TCP KeepAlive（系统层对比）/ ZooKeeper 心跳（Session 机制）|
|7.4|**Netty 做 HTTP/WebSocket Server 对比 Tomcat**|🟢了解|① Tomcat：基于 Servlet 规范，阻塞 I/O 模型（BIO/NIO），适合传统 Web 应用 ② Netty：纯异步事件驱动，适合长连接/高并发推送/自定义协议 ③ 选型：REST API 用 Spring Boot + Tomcat；IM/推送/游戏用 Netty ④ 面试：什么场景用 Netty 做 Web 服务器？什么场景用 Tomcat？|→ Spring Boot 嵌入式 Tomcat / Nginx（反向代理对比）|