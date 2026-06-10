### 为什么这个模块最重要

**Security 本质上是一个"超级过滤器链"**。不理解 FilterChain，后面所有认证/授权都无从谈起。这是面试第一问："Spring Security 的核心组件有哪些？"

### 知识点表

|序号|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|1.1|**Security 整体架构：DelegatingFilterProxy**|🔴必背|① DelegatingFilterProxy 是 Spring 和 Servlet Filter 之间的桥梁（Web.xml 里配的 `filter-name` 就是它）② 内部委托给 FilterChainProxy → 维护一组 SecurityFilterChain（每个 URL 模式一条链）③ 面试：画一下 Spring Security 的请求处理流程图|→ Spring MVC FilterChain（Servlet 规范）/ Nginx Location（类比路由匹配）|
|1.2|**默认过滤器链顺序（15+ 个 Filter）**|🔴必背|① 核心过滤器的执行顺序：ChannelEncodingFilter → WebAsyncMgmtFilter → SecurityContextPersistenceFilter → HeaderWriterFilter → CsrfFilter → LogoutFilter → **UsernamePasswordAuthFilter(认证)** → BasicAuthFilter → **RequestCacheAwareFilter** → **SecurityContextHolderAwareReqFilter** → **AnonymousAuthFilter** → **SessionMgmtFilter** → **ExceptionTranslationFilter(异常)** → **FilterSecurityInterceptor(授权)** ② 面试：Security 默认有哪些过滤器？哪个负责认证、哪个负责授权？|→ Servlet Filter API / Spring MVC Interceptor（对比）|
|1.3|**FilterSecurityInterceptor — 授权决策的核心**|🔴必背|① 它是整个链条中最后一个 Filter，负责最终的"能不能访问"判断 ② 工作方式：从 SecurityMetadataSource 获取访问权限要求（ConfigAttribute）→ 从 Authentication 提取当前用户信息 → 委托 AccessDecisionManager 做投票决策 ③ 三种决策策略：Affirmative(一票通过) / Consensus(多数同意) / Unanimous(全票通过) ④ 面试：详细讲一下 FilterSecurityInterceptor 的工作原理？AccessDecisionManager 有哪些实现？|→ S3 授权流程详解|
|1.4|**SecurityContext & SecurityContextHolder**|🔴必背|① SecurityContext = 当前安全上下文（存了 Authentication 对象）② SecurityContextHolder = 存储上下文的容器，支持三种策略（ThreadLocal/InheritableThreadLocal/全局）③ 典型用法：`SecurityContextHolder.getContext().getAuthentication().getPrincipal()` ④ 面试：SecurityContextHolder 的三种存储策略分别适用什么场景？（单线程用 ThreadLocal，子线程用 InheritableThreadLocal，跨线程用全局或自定义）|→ Java ThreadLocal（并发基础）/ Redis Session 共享|
|1.5|**Security 配置体系（HttpSecurity / WebSecurityConfigurerAdapter vs SecurityFilterChain）**|🟡应掌握|① 旧版：`@EnableWebSecurity + extends WebSecurityConfigurerAdapter`（已废弃）② 新版：`SecurityFilterChain Bean + HttpSecurity DSL`（推荐）③ 配置项：`.authorizeHttpRequests()` / `.formLogin()` / `.httpBasic()` / `.csrf().disable()` / `.sessionManagement()` ④ 面试：新旧版 Security 配置有什么区别？|→ Spring Boot 自动配置（Starter 机制）|

> **🏗️ 架构追问**：如果让你设计一个"支持多租户（Multi-Tenant）"的安全框架扩展层，你会怎么改造 FilterChain？提示：需要在认证前解析租户 ID，在授权时加入租户隔离。