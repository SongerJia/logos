|序号|知识点|笔记写什么|important|
|---|---|---|---|
|3.1|Trace 核心概念体系|**Trace**（一次完整的请求链路，全局唯一 TraceId）/ **Span**（链路上的一个操作单元）/ **Segment**（同一 JVM 内的一组 Span）/ **Tag**（KV 键值对，业务自定义标注）/ **Log**（带时间戳的日志事件）；画一张"一次 HTTP 请求经过 3 个微服务"的完整 Trace/Span/Segment 关系图|🔥🔥🔥🔥 **必须能手画**|
|3.2|TraceId 与 SpanId 的生成规则|TraceId = 全局唯一（基于 UUID 或雪花算法）；SpanId = 同一 Trace 内递增（0 为入口 Span）；ParentSpanId = 当前 Span 的父 Span ID（形成树形关系）；**跨服务传播：HTTP Header 传递 Trace 上下文**（sw8/sw8-x 等协议 header）|🔥🔥🔥 **理解跨服务追踪的关键**|
|3.3|Span 类型与层级关系|Entry Span（服务入口，如 Controller）/ Local Span（服务内部方法调用）/ Exit Span（服务出口，如 RPC/HTTP/MySQL 出站调用）；一个 Segment = 1 个 Entry + N 个 Local + N 个 Exit；**为什么分三种类型？→ 为了构建服务拓扑图**|🔥🔥🔥|