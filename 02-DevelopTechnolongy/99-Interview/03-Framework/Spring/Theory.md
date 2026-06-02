---
title: Spring / Spring Boot 面试理论
tags:
  - Framework
  - Interview
---

## 一、IoC & DI（必问基础）

> **Q1** IoC 控制反转和 DI 依赖注入的关系是什么？"控制"指的是什么被反转了？不用 Spring，你自己怎么实现一个简单的 IoC 容器？

> **Q2** Spring 有哪几种依赖注入方式？构造器注入、Setter 注入、`@Autowired` 字段注入，为什么 Spring 官方推荐构造器注入？字段注入有什么坏处？

> **Q3** `@Autowired` 和 `@Resource` 的区别？按类型注入 vs 按名称注入，如果同时有多个同类型 Bean，Spring 怎么处理？

> **Q4** `ApplicationContext` 和 `BeanFactory` 的区别？`ApplicationContext` 比 `BeanFactory` 多了哪些功能？

---

## 二、Bean 的生命周期 & 作用域

> **Q5** Bean 的完整生命周期：从实例化到销毁，每一步发生了什么？`BeanFactoryPostProcessor` 和 `BeanPostProcessor` 分别在哪个阶段介入？

> **Q6** Bean 的作用域有哪些？singleton、prototype、request、session、application，prototype 的 Bean 为什么不能完全由 Spring 管理生命周期？

> **Q7** Spring 如何解决循环依赖？三级缓存分别存什么？（`singletonObjects` / `earlySingletonObjects` / `singletonFactories`）为什么必须三级，两级不行吗？

> **Q8** `@Lazy` 懒加载的原理？什么时候 Bean 才真正初始化？prototype + 懒加载有什么用？

---

## 三、AOP（必问源码级）

> **Q9** AOP 的核心概念：切面（Aspect）、切点（Pointcut）、通知（Advice）、连接点（Join Point）、织入（Weaving）各是什么？用你项目里的一个例子说明。

> **Q10** JDK 动态代理和 CGLIB 的原理对比？Spring 什么时候用 JDK 代理，什么时候用 CGLIB？Spring Boot 2.x 为什么默认改为 CGLIB？

> **Q11** 五种通知类型：`@Before` / `@After` / `@AfterReturning` / `@AfterThrowing` / `@Around`，如果同时存在，执行顺序是什么？`@Around` 不调用 `proceed()` 会怎样？

> **Q12** 为什么 AOP 切面里 `@Around` 拿不到 `@Transactional` 代理？代理嵌套的顺序问题——多层 AOP 时，Spring 怎么组织代理链的？

---

## 四、Spring 事务（面试高频）

> **Q13** Spring 事务的 7 种传播行为，重点说清 `REQUIRED`、`REQUIRES_NEW`、`NESTED` 的区别。`NESTED` 和 `REQUIRES_NEW` 在回滚时有什么不同？

> **Q14** `@Transactional` 失效的 6 种场景？自调用为什么失效（`this.method()` 不经过代理）？怎么解决自调用事务？

> **Q15** `@Transactional` 默认只回滚 RuntimeException，如果业务抛了 Checked Exception，怎么做能让它回滚？`rollbackFor` 和 `noRollbackFor` 怎么配？

> **Q16** 事务的隔离级别在 Spring 里怎么设置？`@Transactional(isolation = Isolation.REPEATABLE_READ)` 设置的是 Spring 层面的还是数据库层面的？

---

## 五、Spring Boot 自动装配（必问）

> **Q17** `@SpringBootApplication` 这个注解包含哪三个核心注解？`@EnableAutoConfiguration` 的底层原理说清楚。

> **Q18** 自动装配的 SPI 机制：`spring.factories`（Spring Boot 2.x）和 `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`（Spring Boot 3.x）有什么区别？为什么 3.x 要换掉 `spring.factories`？

> **Q19** `@Conditional` 条件注解家族：`@ConditionalOnClass`、`@ConditionalOnMissingBean`、`@ConditionalOnProperty` 分别怎么用？自定义 Starter 时必须注意什么？

> **Q20** Spring Boot 启动流程的核心步骤？`SpringApplication.run()` 里做了什么？（创建 ApplicationContext → 准备环境 → 打印 Banner → 刷新上下文 → afterRefresh → 发布事件）

---

## 六、Spring MVC

> **Q21** 一个 HTTP 请求进入 Spring MVC 后的完整处理流程？从 `DispatcherServlet` → `HandlerMapping` → `HandlerAdapter` → `Handler`（Controller）→ `ViewResolver` 说清楚。

> **Q22** 拦截器（Interceptor）和过滤器（Filter）的区别？执行顺序是怎样的？如果 Filter 返回了错误码，Interceptor 还会执行吗？

> **Q23** `@RestController` 和 `@Controller` 的区别？`@ResponseBody` 做了什么？JSON 序列化用的是哪个框架？（默认 Jackson）

> **Q24** Spring MVC 的参数绑定原理？`@RequestParam`、`@PathVariable`、`@RequestBody` 各从请求的哪个位置取值？

---

## 七、配置 & 属性绑定

> **Q25** Spring Boot 配置文件的加载优先级？`application.yml` vs `bootstrap.yml`（Spring Cloud），命令行参数 vs 配置文件 vs 环境变量，谁覆盖谁？

> **Q26** `@ConfigurationProperties` 和 `@Value` 的区别？为什么推荐 `@ConfigurationProperties` 做批量属性绑定？松散绑定（Relaxed Binding）是什么意思？

> **Q27** 多环境配置怎么管理？`spring.profiles.active` 怎么用？`application-{profile}.yml` 和主配置文件的关系？

---

## 八、事件 & 异步

> **Q28** Spring 的事件机制（`ApplicationEvent` + `ApplicationListener` + `ApplicationEventPublisher`）怎么用？默认是同步还是异步？怎么改成异步？

> **Q29** `@Async` 的原理？默认线程池是什么？为什么不推荐用默认线程池？自定义线程池后，`@Async` 怎么指定？

> **Q30** `@Scheduled` 定时任务的原理？`cron`、`fixedDelay`、`fixedRate` 的区别？如果有 3 个 `@Scheduled` 任务，默认是串行还是并行？怎么改并行？

---

## 九、设计模式 & 扩展点

> **Q31** Spring 中用到了哪些设计模式？（至少说 8 种，每种对应 Spring 什么功能）代理模式（AOP）、模板方法（`JdbcTemplate`）、工厂（`BeanFactory`）、单例（Bean 作用域 singleton）、观察者（事件机制）、策略（`InstantiationStrategy`）、适配器（`HandlerAdapter`）、责任链（`HandlerInterceptor`）

> **Q32** `BeanFactory` 和 `FactoryBean` 的区别？`FactoryBean` 在什么场景用？（MyBatis 的 `SqlSessionFactoryBean`、Dubbo 的 `ReferenceBean`）

> **Q33** `ImportBeanDefinitionRegistrar` 和 `BeanDefinitionRegistryPostProcessor` 是做什么的？Spring Boot 的 `@EnableXxx` 注解底层是怎么工作的？

---

## 十、测试 & Actuator 监控

> **Q34** `@SpringBootTest` 和 `@WebMvcTest` 的区别？`@MockBean` 做了什么？单元测试和集成测试怎么分层？

> **Q35** Spring Boot Actuator 提供了哪些端点？`/health`、`/metrics`、`/env`、`/loggers` 各做了什么？生产环境怎么安全暴露 Actuator 端点？

---

## 十一、Spring Boot 3.x / Spring 6.x 新特性

> **Q36** Spring Boot 3.x 基于 Jakarta EE 而不是 Java EE，`javax.*` 全部变成 `jakarta.*`，迁移时最大的坑是什么？

> **Q37** Spring Boot 3.x 支持 GraalVM AOT 编译，AOT 和 JIT 的区别？AOT 编译成 Native Image 有什么好处和限制？哪些 Spring 特性在 Native Image 下不可用？

> **Q38** Spring Boot 3.x 引入的"虚拟线程"支持（`spring.threads.virtual.enabled=true`），和之前的平台线程池有什么不同？什么时候该开？

---

## 十二、实战场景

> **Q39** 你有一个复杂的业务流程：创建订单 → 扣库存 → 扣优惠券 → 创建支付单 → 发消息。如果扣优惠券失败需要回滚前面的扣库存，但发消息失败不能回滚业务，用 Spring 事务怎么设计？

> **Q40** 线上服务 @Transactional 没生效，导致数据不一致，你怎么定位问题？列出排查清单。
