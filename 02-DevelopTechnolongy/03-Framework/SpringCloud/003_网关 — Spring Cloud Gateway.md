|知识点|笔记时重点写什么|
|---|---|
|**Gateway vs Zuul 1.x vs Zuul 2.x 对比**|热 Gateway 基于 Spring WebFlux（非阻塞异步，Netty 运行），性能远高于 Zuul 1.x（Servlet 阻塞）。Zuul 2.x 也是非阻塞但已停止维护。**Gateway 是目前唯一选择**|
|**Gateway 核心概念**|Route（路由 = id + uri + predicates + filters）、Predicate（断言，匹配条件，如 Path=/api/**、Method=GET、Header=X-Request-Id）、Filter（过滤器，GlobalFilter 全局 vs GatewayFilter 局部）。**路由就是「如果满足这些条件就转发到这个 URI 并经过这些过滤器」**|
|**Predicate 断言工厂**|After/Before/Between（时间）、Cookie（Cookie 值）、Header（请求头）、Host（主机名）、Method（HTTP 方法）、Path（路径）、Query（查询参数）、RemoteAddr（IP 地址）、Weight（权重路由）|
|**过滤器 Filter 链路**|核 pre 过滤器（请求到达路由前执行：鉴权/限流/日志/请求头增强）→ 路由转发 → post 过滤器（响应返回前执行：响应头修改/统计/错误处理）。**和 MVC 的 Interceptor 区别**：Filter 在网关层，Interceptor 在业务服务层|
|**Gateway 常见场景**|热 统一鉴权（JWT Token 校验）、灰度发布（基于 Header 版本号路由到不同版本服务）、限流（内置 RequestRateLimiter，基于 Redis 令牌桶）、日志追踪（传递 TraceId）、接口聚合（将多个微服务的接口合并为一个前端接口）|
|**Gateway 集成 Sentinel**|热 `spring-cloud-alibaba-sentinel-gateway` 依赖。可以在网关层做 API 级别的限流和熔断。两种粒度：route 维度（整条路由限流）和 custom API 维度（自定义 API 分组限流）。**网关限流是系统的第一道防线**|