|序号|知识点|笔记写什么|重要度|
|---|---|---|---|
|2.1|HikariCP 为什么快（核心优势）|无锁 ConcurrentBag 设计 / 字节码精简(javassist) / 自定义 FastList / arraylist 替代 Vector / Javassist字节码优化|🔥🔥🔥 **绝对高频**|
|2.2|ConcurrentBag 并发容器原理|内部结构：ThreadLocal(sharedList) + copyOnWriteArrayList(threadList) + BlockingQueue(handoffQueue)；borrow/return 流程|核|
|2.3|连接的创建与回收流程|`HikariPool.createPoolEntry()` → fillPool() → addConnectionExecutor 异步创建；return 时 idleTimeoutMillis 判断|核|
|2.4|连接泄漏检测（leakDetectionThreshold）|开启条件（必须 >0 且小于 maxLifetime）；原理：ProxyConnection 注册到 HouseKeeper 定时检测|热|

**📌 架构追问**：为什么 Spring Boot 从 Tomcat JDBC Pool 切换到 HikariCP 作为默认？ benchmark 对比数据是什么？