### 为什么这个模块重要

**这是你真正在项目中用 Seata 的方式**。一行 `@GlobalTransactional` 就能开启分布式事务——但背后的坑远不止这一行注解。

### 知识点表

|序号|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|7.1|**快速接入：依赖 + 配置 + 注解**|🔴必背|① seata-spring-boot-starter 引入 ② application.yml 关键配置(tx-service-group/vgroup-mapping) ③ @GlobalTransactional 用法 ④ 面试：描述一下Seata的接入步骤|→ Spring Boot Starter机制(M7框架)|
|7.2|**@GlobalTransactional 源码解析**|🔴🔴核心|① AOP拦截 → 开启全局事务 → 注册TC → 执行业务逻辑 → 提交/回滚 ② TM和RM的角色切换时机 ③ 面试：@GlobalTransactional的底层执行流程是什么？|→ Spring AOP源码(M5框架)|
|7.3|**DataSourceProxy 自动代理机制**|🔴🔴核心|① Seata如何自动包装DataSource ② DataSourceProxy的职责（连接代理/SQL解析/undo log管理） ③ 自动装配类：SeataAutoConfiguration ④ 面试：Seata是怎么做到对业务代码无侵入的？|→ Spring Boot自动配置(M7框架)|
|7.4|**Feign/RPC调用中的事务上下文传播**|🔴必背|① XID如何在服务间传递（HTTP Header: TX_XID） ② Feign Interceptor拦截注入 ③ 面试：XID是怎么从一个服务传到另一个服务的？|→ Feign远程调用(M8框架)|
|7.5|**常见集成坑 & 最佳实践**|🟡应掌握|① 包扫描路径问题（@SeataDataSourceProxy没扫到） ② 主键回填问题（MP的insert后id为null） ③ 不支持的场景汇总 ④ 面试：你用Seata踩过哪些坑？|→ MyBatis-Plus ID策略(M9框架)|