|知识点|笔记时重点写什么|
|---|---|
|**OpenFeign 声明式调用原理**|热 写一个接口 + `@FeignClient` → 启动时 JDK 动态代理生成实现类 → 调用时走 `ReflectiveFeign.invoke()` → 编码 HTTP 请求（RequestTemplate）→ 通过底层 HttpClient 发送 → 解码响应返回。整个过程对调用方透明|
|**@FeignClient 核心属性**|value/name（服务名）、url（直接指定 URL 绕过注册中心）、fallback（降级处理类）、fallbackFactory（获取异常信息的降级工厂）、configuration（自定义配置类）、path（统一前缀）|
|**Feign 的拦截器 RequestInterceptor**|核 在每次 Feign 请求发出前统一添加 Header（如 Token、TraceId）。典型场景：认证令牌透传、链路追踪 ID 传递。`apply(RequestTemplate template)` 方法中操作|
|**Feign 超时与重试配置**|connectTimeout（连接超时，默认 10s）、readTimeout（读取超时，默认 60s）。注意：**如果配置了 Ribbon，Ribbon 的超时会覆盖 Feign 的**——这是常见坑。重试次数通过 `ribbon.MaxAutoRetries` 控制|
|**Feign 性能优化**|核 ①替换 HTTP 客户端：默认 HttpURLConnection → OkHttp 或 Apache HttpClient（性能提升 15%~30%）②启用连接池 ③开启 gzip 压缩 ④日志级别设为 BASIC 或 HEADERS（不要 FULL）|
|**Dubbo vs OpenFeign 选型对比**|Dubbo（基于 TCP 长连接，性能更高，适合内部高性能调用）；OpenFeign（基于 HTTP RESTful，通用性好，适合跨语言/对外暴露）。阿里系内部 Dubbo 多，外部接口 Feign 多|
|**负载均衡策略**|Feign 底层默认整合 Ribbon（或 Spring Cloud LoadBalancer）。轮询（RoundRobin）、随机（Random）、加权响应时间（WeightedResponse）。如何自定义？如何针对某个服务单独配置？|

> **连接点提醒**：OpenFeign 的服务发现依赖 01 模块的 Nacos，它的熔断保护依赖 03 模块的 Sentinel。笔记里要显式标注这两条线。