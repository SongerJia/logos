|序号|知识点|笔记写什么|important|
|---|---|---|---|
|2.1|Agent 工作机制：Java Agent + Byte Buddy|`-javaagent:skywalking-agent.jar` 启动参数 → JVM 在 `premain`/`agentmain` 回调中加载 Agent → 使用 **Byte Buddy** 库进行字节码增强（修改 class 字节码，插入拦截逻辑）；**为什么叫"探针"而不叫"SDK"**|🔥🔥🔥🔨 **绝对核心，面试深挖题**|
|2.2|Byte Buddy 字节码增强原理|Byte Buddy 对目标类的 Method 进行拦截 → 在方法入口和出口插入代码（记录开始时间 / 收集参数 / 记录结束时间 / 上报数据）；与 JDK 动态代理的区别（动态代理只能接口，Byte Buddy 可以改任何类）；运行时增强 vs 编译时增强|🔥🔥🔥|
|2.3|插件(Plugin)体系|SkyWalking 通过插件实现对不同框架的自动埋点：Spring MVC 插件（拦截 Controller）/ Dubbo 插件（拦截 RPC 调用）/ MySQL 插件（拦截 JDBC 执行）/ RocketMQ 插件 / Redis 插件 / Tomcat 插件；插件是如何发现和加载的（SPI 机制）；**自定义插件开发**（当官方插件不满足时）|🔥🔥🔥|
|2.4|Agent 性能影响评估|Agent 带来的开销：CPU（字节码增强+序列化）/ 内存（Trace 数据缓存）/ 网络（上报数据到OAP）；性能损耗通常在 **3%~10%** 以内（取决于采样率）；生产环境调优：降低采样率 / 异步批量上报 / 本地缓存合并|核|