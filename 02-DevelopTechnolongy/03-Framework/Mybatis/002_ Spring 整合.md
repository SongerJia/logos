|知识点|笔记时重点写什么|
|---|---|
|**SqlSessionFactoryBean（FactoryBean）**|热 Spring 通过 FactoryBean 模式创建 SqlSessionFactory 实例。`afterPropertiesSet()` 中解析 dataSource、mapperLocations、configLocation、typeAliasesPackage 等属性，最终 build 出 SqlSessionFactory。**这就是你在 Spring Core 里学的 FactoryBean 的经典应用场景**|
|**MapperScannerConfigurer**|热 自动扫描指定包路径下的 Mapper 接口，将它们注册为 Spring Bean。底层是 `ClassPathMapperScanner`（继承自 ClassPathBeanDefinitionScanner），扫描过程中为每个 Mapper 接口创建 `MapperFactoryBean`（又是 FactoryBean！），getObject() 返回的是 MapperProxy 代理对象|
|**@MapperScan 注解**|Spring Boot 下的简化写法，等价于 MapperScannerConfigurer。`@MapperScan("com.example.demo.mapper")`。可以指定 sqlSessionFactoryRef（多个数据源时指定用哪个工厂）、annotationClass（额外过滤条件）|
|**Mapper 接口如何被注入**|你在 Controller/Service 中 @Autowired 一个 UserMapper 接口 → Spring 容器中该接口对应的 Bean 是 MapperFactoryBean.getObject() 返回的 MapperProxy 代理 → 调用时走 invoke() → 最终委托给 DefaultSqlSession 执行。整条链路要能手画出来|
|**事务同步机制**|核 Spring 事务开启时，通过 `SqlSessionUtils.registerSessionHolder()` 将 SqlSession 绑定到当前线程（ThreadLocal）。后续同一线程的 Mapper 调用都复用这个 SqlSession。事务提交/回滚时自动 commit/rollback 并关闭 SqlSession。**这就是为什么 Spring + MyBatis 下一级缓存会在整个事务期间生效的原因**|

> **笔记技巧**：06 模块是 Spring Core 和 MyBatis 的交汇点，强烈建议画一张图展示：Spring IOC 容器启动 → SqlSessionFactoryBean 创建工厂 → MapperScannerConfigurer 注册 Mapper Bean → 用户 @Autowired 注入 → 调用时的完整链路。