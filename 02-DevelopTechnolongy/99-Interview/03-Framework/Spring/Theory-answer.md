---
title: Spring / Spring Boot 面试理论-答案版
tags:
  - Framework
  - Interview-answer
---
#flashcards/Framework/Spring/theory 
## 一、IoC & DI（必问基础）

### **Q1** IoC 控制反转和 DI 依赖注入的关系是什么？"控制"指的是什么被反转了？不用 Spring，你自己怎么实现一个简单的 IoC 容器？
?
1. IoC 和 DI 不是同一个东西，但是相互配合。IoC 是一种设计思想，DI 是实现 IoC 的手段。传统编程里，对象自己控制自己依赖的创建——比如在构造方法里 new 一个依赖对象，这叫"正向控制"。IoC 则把控制权反转了：对象不再自己创建依赖，而是被动地接受外部传递进来的依赖。"控制"反转的就是"谁来创建和管理依赖对象"这个权力。
2. 实现一个简单 IoC 容器大概三步：第一，定义一个 Map 作为 Bean 的注册中心；第二，用配置文件或注解声明 Bean 的定义信息，包括类名、是否单例等；第三，在容器启动时，遍历所有 Bean 定义，通过反射创建实例，并把它们之间的依赖关系注入进去——先实例化所有 Bean，再根据依赖关系做 set 注入或字段赋值。核心就是一个反射 + 容器 Map，做完这三步就得到了一个最简 IoC 容器。

### **Q2** Spring 有哪几种依赖注入方式？构造器注入、Setter 注入、`@Autowired` 字段注入，为什么 Spring 官方推荐构造器注入？字段注入有什么坏处？
?
1. Spring 有三种注入方式。构造器注入是通过构造方法的参数把依赖传进来；Setter 注入是通过 setter 方法设值；字段注入是直接在字段上加 @Autowired 或 @Resource。
2. 官方推荐构造器注入，主要有三个原因。第一，依赖不可变——构造器注入的字段可以声明为 final，对象创建后依赖就不会被中途篡改。第二，依赖不缺失——构造器要求创建对象时必须传入所有依赖，如果缺了某个依赖，编译期或启动期就会报错，不会等到运行时才发现空指针。第三，方便单元测试——测试时直接 new 对象传 mock 依赖就行，不需要启动 Spring 容器。
3. 字段注入的坏处也很明显。首先，字段不能声明 final，意味着对象创建后可以被随意 set 修改，破坏了不可变性。其次，依赖是隐藏的——一个类有多少依赖，看字段看不全，容易越加越多导致类职责不清。最后，单元测试麻烦——必须依赖 Spring 容器或反射来注入 mock，不能直接用构造器传参。所以生产代码里优先用构造器注入，字段注入只在测试类或非核心配置类里偶尔用。

### **Q3** `@Autowired` 和 `@Resource` 的区别？按类型注入 vs 按名称注入，如果同时有多个同类型 Bean，Spring 怎么处理？
?
1. 核心区别在注入策略。@Autowired 是 Spring 的注解，默认按类型注入。@Resource 是 JDK 的注解（javax.annotation），默认按名称注入——先根据字段名或指定的 name 属性找 Bean，找不到再退化按类型。
2. 当同一个类型有多个 Bean 时，@Autowired 的处理分三步。第一步，按类型匹配所有候选 Bean。第二步，如果只有一个候选就直接注入；如果有多个，它再按名称匹配——用字段名或 @Qualifier 指定的名称去找。第三步，如果还匹配不到唯一的，就抛 NoUniqueBeanDefinitionException。可以通过 @Primary 指定首选 Bean，或者用 @Qualifier 明确指定名称来解决。

### **Q4** `ApplicationContext` 和 `BeanFactory` 的区别？`ApplicationContext` 比 `BeanFactory` 多了哪些功能？
?
1. BeanFactory 是 Spring 最底层的 IoC 容器接口，只提供最基本的 Bean 管理能力——获取 Bean、判断 Bean 是否存在、检查 Bean 类型等。它是懒加载的，只有在调用 getBean 时才创建 Bean 实例。
2. ApplicationContext 继承自 BeanFactory，在它的基础上做了大量增强。多了的功能包括：国际化支持（MessageSource）、事件发布机制（ApplicationEventPublisher）、资源加载（ResourceLoader，可以直接加载 classpath 下的文件）、环境抽象（Environment，可以获取配置文件和系统属性）、以及 AOP、事务、自动装配等高级功能的集成。另外 ApplicationContext 默认是启动时预加载所有非懒加载的单例 Bean，而不是等到使用时才创建。生产环境都用 ApplicationContext，BeanFactory 只存在一些内存极度敏感的场景里。

---

## 二、Bean 的生命周期 & 作用域

### **Q5** Bean 的完整生命周期：从实例化到销毁，每一步发生了什么？`BeanFactoryPostProcessor` 和 `BeanPostProcessor` 分别在哪个阶段介入？
?
1. Bean 的完整生命周期大致分四个阶段。
2. 第一阶段是 Bean 定义加载。Spring 扫描配置文件或注解，把每个 Bean 的元数据（类名、作用域、依赖、初始化方法等）解析成 BeanDefinition，注册到 BeanDefinitionRegistry 里。注意此时还没创建任何实例。
3. 第二阶段是 BeanFactoryPostProcessor 介入。在 Bean 实例化之前，BeanFactoryPostProcessor 可以读取和修改所有 BeanDefinition，比如 PropertySourcesPlaceholderConfigurer 把 ${} 占位符替换成真实配置值。这一步发生在所有 Bean 实例化之前。
4. 第三阶段是实例化和属性填充。Spring 通过反射调用构造器创建 Bean 实例，然后根据 BeanDefinition 里的依赖信息，给属性赋值——这里包括依赖注入和普通属性设置。
5. 第四阶段是初始化。Spring 依次执行这几步：注入 Aware 接口（比如 BeanNameAware、ApplicationContextAware），然后执行所有 BeanPostProcessor 的 postProcessBeforeInitialization 方法，接着执行 InitializingBean 的 afterPropertiesSet 方法或 @PostConstruct 标注的方法或 init-method，最后执行 BeanPostProcessor 的 postProcessAfterInitialization 方法——AOP 代理就是在这最后一步生成的。
6. 销毁阶段：容器关闭时，执行 DisposableBean 的 destroy 方法或 @PreDestroy 或 destroy-method。
7. BeanPostProcessor 在 Bean 初始化前后介入，影响的是已经实例化的 Bean；BeanFactoryPostProcessor 在 Bean 实例化之前介入，影响的是 BeanDefinition 元数据。两者作用阶段完全不同。

### **Q6** Bean 的作用域有哪些？singleton、prototype、request、session、application，prototype 的 Bean 为什么不能完全由 Spring 管理生命周期？
?
1. Spring 有五种作用域。singleton 是默认的，整个容器里只有一个实例。prototype 每次获取都创建一个新实例。request 每个 HTTP 请求一个实例。session 每个 HTTP 会话一个实例。application 整个 ServletContext 一个实例——和 singleton 的区别是 singleton 是 Spring 容器级别的，application 是 Servlet 容器级别的，如果部署多个 war 可能有多个 Spring 容器但只有一个 application 作用域。
2. prototype 的 Bean 不能被 Spring 完全管理生命周期，原因是 Spring 创建完 prototype Bean 并注入依赖后就把它交给调用方了，不再持有它的引用。这意味着销毁回调不会自动触发——容器关闭时 Spring 只销毁自己持有的 singleton Bean。如果你的 prototype Bean 持有需要释放的资源（比如数据库连接），你必须自己在用完时手动调用销毁方法，否则资源泄漏。

### **Q7** Spring 如何解决循环依赖？三级缓存分别存什么？（`singletonObjects` / `earlySingletonObjects` / `singletonFactories`）为什么必须三级，两级不行吗？
?
1. Spring 通过三级缓存解决 singleton 的 setter 注入循环依赖，构造器注入的循环依赖无法解决。
2. 三级缓存的内容是：一级缓存 singletonObjects 存放完全初始化好的成品 Bean。二级缓存 earlySingletonObjects 存放提前暴露的半成品 Bean——已经实例化但还没完成属性填充和初始化的。三级缓存 singletonFactories 存放对象工厂，这个工厂可以生成 Bean 的早期引用，也就是可以返回半成品的代理对象。
3. 解决循环依赖的关键步骤是这样的：A 创建时，实例化后先把自己放入三级缓存（一个 ObjectFactory，可以返回 A 的提前引用）。然后 A 填充属性时发现依赖 B，去创建 B。B 实例化后也类似放入三级缓存，然后 B 填充属性时发现需要 A。此时 Spring 从三级缓存里找到 A 的 ObjectFactory，调用它拿到 A 的提前引用（如果 A 需要 AOP，这里拿到的就是代理对象），然后把提前引用放入二级缓存，再注入给 B。B 完成初始化后放入一级缓存。最后 A 继续完成属性填充和初始化，放入一级缓存。
4. 为什么必须三级而不是两级？关键在 AOP。如果 A 需要被代理，那么 B 注入的 A 必须是代理对象，不能是原始对象。三级缓存里的 ObjectFactory 提供了这样一个时机：可以在获取提前引用时判断是否需要创建代理对象，如果需要就返回代理对象。如果把三级缓存去掉，只保留二级缓存存放原始对象，那 B 拿到的就是未代理的 A，AOP 就失效了。所以三级缓存的本质是给 AOP 代理留了一个后门。

### **Q8** `@Lazy` 懒加载的原理？什么时候 Bean 才真正初始化？prototype + 懒加载有什么用？
?
1. @Lazy 的原理是阻止 Spring 在容器启动时预初始化这个 Bean。正常情况，singleton Bean 在容器刷新阶段就会被创建。加了 @Lazy 后，Spring 不会立即实例化它，而是生成一个代理对象或延迟引用放在容器里。只有当这个 Bean 第一次被真正使用——比如被其他 Bean 依赖注入、或者通过 getBean 获取、或者被 @Lazy 的 Bean 所在类的方法被调用——这时才会触发实际的实例化。
2. prototype 加 @Lazy 的情况比较特殊。prototype 本身就是懒的——每次获取才创建，所以 @Lazy 在 prototype Bean 本身上没有实际意义。但 @Lazy 可以用在注入 prototype Bean 的地方：比如一个 singleton Bean 注入了 prototype Bean，如果不加 @Lazy，singleton 创建时就会立刻创建一个 prototype 实例并注入，之后每次用的都是同一个实例，prototype 就变相成了 singleton。加了 @Lazy 后，每次使用时才通过代理去获取新的 prototype 实例，真正实现了每次获取都不同的语义。

---

## 三、AOP（必问源码级）

### **Q9** AOP 的核心概念：切面（Aspect）、切点（Pointcut）、通知（Advice）、连接点（Join Point）、织入（Weaving）各是什么？用你项目里的一个例子说明。
?
1. 切面是横切关注点的模块化，包含了切点和通知的定义。切点是匹配连接点的表达式，定义了"在哪里切入"。通知是切面在切点处要执行的逻辑，定义了"做什么"。连接点是程序执行过程中可以切入的点，比如方法调用、异常抛出——Spring AOP 只支持方法级别的连接点。织入是把切面应用到目标对象并创建代理对象的过程。
2. 举个例子：我们项目里有个操作日志切面。切面就是 LogAspect 这个类，切点是用 @Pointcut 定义的表达式匹配所有 Controller 方法，通知是 @Around 里写记录请求参数和响应的逻辑，连接点是每个 Controller 方法的执行，织入是 Spring 在启动时通过 JDK 动态代理或 CGLIB 把 LogAspect 织入到 Controller 的代理对象里。

### **Q10** JDK 动态代理和 CGLIB 的原理对比？Spring 什么时候用 JDK 代理，什么时候用 CGLIB？Spring Boot 2.x 为什么默认改为 CGLIB？
?
1. JDK 动态代理要求目标类必须实现接口。它的原理是利用 Proxy.newProxyInstance 在运行时动态生成一个实现了目标接口的代理类，这个代理类持有 InvocationHandler 的引用。每次调用代理对象的方法时，实际上调到了 InvocationHandler 的 invoke 方法里，在这里可以执行增强逻辑，然后通过反射调用目标对象的方法。
2. CGLIB 不要求接口，它通过字节码技术在运行时生成目标类的子类。原理是 CGLIB 创建目标类的子类，重写其中的方法，在重写的方法里插入增强逻辑，再通过 FastClass 机制直接调用父类方法——fastclass 比反射快。
3. Spring 的选择策略：如果目标类实现了接口，默认用 JDK 动态代理；如果没实现接口，用 CGLIB。也可以通过 proxyTargetClass = true 强制使用 CGLIB。
4. Spring Boot 2.x 把默认改成了 CGLIB，原因是实际开发中经常出现这样的问题：Controller 本来没实现接口，有一天给它加了个接口，结果 AOP 突然失效——因为 Spring 检测到接口后自动从 CGLIB 切换到了 JDK 代理，导致注入方式不兼容。统一用 CGLIB 后就没有这个切换带来的困扰了。另外 CGLIB 性能也足够好，不需要纠结这两个代理方式的性能差异。

### **Q11** 五种通知类型：`@Before` / `@After` / `@AfterReturning` / `@AfterThrowing` / `@Around`，如果同时存在，执行顺序是什么？`@Around` 不调用 `proceed()` 会怎样？
?
1. 五种通知的执行顺序，正常情况是：@Around 的前半部分先执行，然后是 @Before，然后是目标方法，然后是 @AfterReturning，然后是 @After，最后是 @Around 的后半部分。如果抛异常了：@Around 前半 → @Before → 目标方法抛异常 → @AfterThrowing → @After → @Around 后半。
2. 注意 @After 无论正常还是异常都会执行，它在逻辑上相当于 try-catch-finally 里的 finally。@AfterReturning 只在正常返回时执行，@AfterThrowing 只在抛异常时执行。
3. 如果 @Around 里不调用 proceed()，目标方法根本不会执行。这意味着整个调用链在 @Around 这里就断了——后面的 @Before、目标方法、返回值处理全部被跳过。这时候如果你返回了一个自定义值，调用方拿到的就是这个自定义值；如果你返回 null，调用方就拿到 null。所以 @Around 不调 proceed 本质上是一种拦截阻断，适用于权限校验不通过直接返回的场景。

### **Q12** 为什么 AOP 切面里 `@Around` 拿不到 `@Transactional` 代理？代理嵌套的顺序问题——多层 AOP 时，Spring 怎么组织代理链的？
?
1. 这是代理嵌套的优先级问题。Spring 中有多个 AOP 切面时，会按照一定的顺序包裹——外层先执行，内层后执行。但是 @Transactional 不是一个普通的 AOP 切面，它是通过 InfrastructureAdvisor 和事务拦截器实现的，优先级通常高于自定义切面。
2. 具体来说，代理嵌套的顺序是：外层是自定义切面（比如日志切面），内层是事务切面，最里面才是目标方法。所以在 @Around 日志切面里，通过 JoinPoint 拿到的是"事务代理 + 目标对象"的包裹体，你在 @Around 里调用 proceed() 才会进入事务拦截器，事务拦截器里才开启事务。
3. 如果你在 @Around 切面里直接调用目标对象的方法而不是 proceed()，那就绕过了所有后续代理链——包括事务代理。所以你会拿不到事务，因为事务还没开始。
4. 多层 AOP 时，Spring 通过 Advisor 的 Order 来决定包裹顺序：Order 值越小越外层。事务切面的 Order 通常是 Ordered.LOWEST_PRECEDENCE 附近，优先级很高，所以它在内层。如果你想让 @Around 拿到已经开启了事务的连接，需要把自己的切面 Order 调得比事务切面更大（更内层），但这通常不推荐——更好的做法是在 @Around 切面里正常调 proceed()，把事务相关的操作放在 Service 层处理。

---

## 四、Spring 事务（面试高频）

### **Q13** Spring 事务的 7 种传播行为，重点说清 `REQUIRED`、`REQUIRES_NEW`、`NESTED` 的区别。`NESTED` 和 `REQUIRES_NEW` 在回滚时有什么不同？
?
1. REQUIRED 是最常用的，如果当前有事务就加入，没有就新建。REQUIRES_NEW 是无论当前有没有事务，都新建一个独立事务，并且把当前事务挂起。NESTED 是嵌套事务——如果当前有事务，就在当前事务里创建一个保存点，内部作为一个嵌套子事务运行；如果当前没有事务，行为和 REQUIRED 一样。
2. REQUIRES_NEW 和 NESTED 在回滚时的关键区别：REQUIRES_NEW 的内层事务和外层事务是完全独立的两个物理事务。内层事务回滚不影响外层，外层回滚也不影响内层（内层已经提交了）。NESTED 不同，它是一个物理事务内的逻辑子事务。内层子事务回滚时，只回滚到保存点，外层事务不受影响继续执行；但如果外层事务最终回滚，内层子事务也会一并回滚——因为它和外层在同一个物理事务里。
3. 所以选型上：如果你需要内外彻底隔离、互不影响，用 REQUIRES_NEW；如果你只想让内层可以独立回滚但最终必须和外部共进退，用 NESTED。需要注意 NESTED 只对 JDBC 事务有效，JTA 不支持，而且需要数据库支持保存点。

### **Q14** `@Transactional` 失效的 6 种场景？自调用为什么失效（`this.method()` 不经过代理）？怎么解决自调用事务？
?
1. 六种失效场景。第一，注解加在非 public 方法上——Spring 事务基于 AOP 代理，代理只能拦截 public 方法，protected 或 private 方法不会被拦截。第二，自调用——同一个类里的方法 A 调用方法 B，A 有事务但 B 没有，或者反过来，B 的事务都不会生效。原因是 this.method() 调用的是原始对象的方法，绕过了代理对象。第三，异常被 try-catch 吞掉了——事务回滚依赖抛出异常，如果 catch 块里没重新抛出来，Spring 感知不到异常就不会回滚。第四，rollbackFor 没配对——默认只回滚 RuntimeException 和 Error，如果抛了 Checked Exception 不会回滚。第五，数据库引擎不支持事务——比如 MySQL 的 MyISAM 引擎不支持事务，加 @Transactional 也没用。第六，多线程环境——Spring 事务通过 ThreadLocal 绑定数据库连接，子线程拿不到父线程的事务上下文，所以新线程里的事务是独立的。
2. 自调用失效的原因在于 AOP 的实现机制。@Transactional 是通过 AOP 代理实现的，Spring 容器里注入的是代理对象。外部调用代理对象的方法时，代理对象先执行事务拦截器，然后反射调用目标对象的方法。但在目标对象内部用 this 调用自己的另一个方法时，this 指向的是目标对象自己，不是代理对象，所以直接跳过了代理，事务拦截器根本没机会执行。
3. 解决方法有三种。最简单的是把被调用的方法抽到另一个 Bean 里，通过注入的方式调用，这样就走代理了。第二种是在当前类里注入自己——用 @Autowired 注入自身，通过这个注入的代理对象来调用。第三种是用 AopContext.currentProxy() 获取当前代理对象来调用，需要在配置类上加 @EnableAspectJAutoProxy(exposeProxy = true)。第三种最灵活但代码可读性差，优先用前两种。

### **Q15** `@Transactional` 默认只回滚 RuntimeException，如果业务抛了 Checked Exception，怎么做能让它回滚？`rollbackFor` 和 `noRollbackFor` 怎么配？
?
1. 默认回滚策略是：RuntimeException 及其子类 + Error 及其子类会回滚，Checked Exception 不会回滚。这个设计的逻辑是，RuntimeException 通常表示程序错误（比如空指针、参数校验失败），应该回滚；Checked Exception 通常表示可预期的业务异常，由开发人员决定是否回滚。
2. 如果想让 Checked Exception 也回滚，用 rollbackFor 属性：@Transactional(rollbackFor = Exception.class)，这样所有异常都回滚。如果想让某个 RuntimeException 不回滚，用 noRollbackFor：@Transactional(noRollbackFor = IllegalArgumentException.class)。这两个属性可以同时使用，数组形式。

### **Q16** 事务的隔离级别在 Spring 里怎么设置？`@Transactional(isolation = Isolation.REPEATABLE_READ)` 设置的是 Spring 层面的还是数据库层面的？
?
1. Spring 定义了五种隔离级别：DEFAULT 使用数据库默认隔离级别；READ_UNCOMMITTED 读未提交；READ_COMMITTED 读已提交；REPEATABLE_READ 可重复读；SERIALIZABLE 串行化。
2. 通过 @Transactional(isolation = Isolation.XXX) 设置。这个隔离级别设置的是数据库层面的——Spring 只是把这个参数传递给底层数据库连接，在获取连接时设置 Connection.setTransactionIsolation()。如果数据库不支持你指定的隔离级别，效果取决于数据库的实现——MySQL 默认是 REPEATABLE_READ，如果设置 SERIALIZABLE 它会生效；但如果数据库驱动不抛异常只是忽略，那就不生效。所以隔离级别的本质是数据库行为，Spring 只是传递指令。

---

## 五、Spring Boot 自动装配（必问）

### **Q17** `@SpringBootApplication` 这个注解包含哪三个核心注解？`@EnableAutoConfiguration` 的底层原理说清楚。
?
1. @SpringBootApplication 包含三个注解：@SpringBootConfiguration（本质就是 @Configuration，标注这是一个配置类）、@EnableAutoConfiguration（开启自动装配）、@ComponentScan（开启组件扫描，默认扫描当前包和子包下的组件）。
2. @EnableAutoConfiguration 的底层原理：这个注解通过 @Import 导入了 AutoConfigurationImportSelector。在容器启动时，AutoConfigurationImportSelector 会扫描所有 jar 包下的 META-INF/spring.factories 文件（Spring Boot 2.x）或 META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports 文件（Spring Boot 3.x），从中读取所有自动配置类的全限定名。然后根据每个自动配置类上的 @Conditional 条件注解做过滤——比如 @ConditionalOnClass 检查类路径上是否存在某个类，存在才加载——过滤掉不满足条件的配置类，最终把符合条件的自动配置类加载到 Spring 容器中。
3. 所以自动装配的本质就是：SPI 机制 + 条件过滤 + 自动配置类。你只需要引入 starter 依赖，starter 里包含了对应的 META-INF 配置文件和自动配置类，Spring Boot 启动时自动发现并加载。

### **Q18** 自动装配的 SPI 机制：`spring.factories`（Spring Boot 2.x）和 `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`（Spring Boot 3.x）有什么区别？为什么 3.x 要换掉 `spring.factories`？
?
1. 区别在于两点。第一，文件格式不同。spring.factories 是 key-value 格式，一个 key 下面可以列很多自动配置类，同一个文件里还可以配置其他类型的 SPI（比如 ApplicationListener、FailureAnalyzer 等），所有 SPI 混在一起。3.x 的文件是纯文本格式，每行一个自动配置类全限定名，一个文件只干一件事——声明自动配置类，职责更单一。第二，加载方式不同。2.x 通过 SpringFactoriesLoader 加载，3.x 通过 ImportCandidates 加载，3.x 的加载不涉及解析 key-value，性能更好。
2. 为什么换掉？最核心的原因是 spring.factories 设计上是一刀切的——所有自动配置类都在一个 key 下，Spring Boot 必须全部加载进来再根据 @Conditional 逐一过滤。3.x 的新文件格式支持更精细的按需加载，而且避免了与其他 SPI 共用一个文件带来的混乱。另外 3.x 配合 AOT 编译时，新格式也更容易做静态分析。

### **Q19** `@Conditional` 条件注解家族：`@ConditionalOnClass`、`@ConditionalOnMissingBean`、`@ConditionalOnProperty` 分别怎么用？自定义 Starter 时必须注意什么？
?
1. @ConditionalOnClass 根据类路径上是否存在指定类来决定是否装配。比如 @ConditionalOnClass(name = "com.mysql.cj.jdbc.Driver")，有了 MySQL 驱动才装配数据源配置。
2. @ConditionalOnMissingBean 根据容器中是否缺少指定类型的 Bean 来决定。常用在"用户没配就自动配默认的"场景，比如：如果用户自己没定义 RestTemplate，就自动创建一个默认的，一旦用户定义了就不创建。
3. @ConditionalOnProperty 根据配置文件中的属性值来决定。比如 @ConditionalOnProperty(name = "cache.enabled", havingValue = "true")，只有当 cache.enabled=true 时才启用缓存配置。
4. 自定义 Starter 时的注意事项：第一，自动配置类不要加 @ComponentScan，要用 @Configuration + @Bean 的方式，通过 META-INF 文件声明加载。第二，所有自动配置 Bean 都要加 @ConditionalOnMissingBean，让用户能覆盖。第三，配置属性用 @ConfigurationProperties 封装，并在自动配置类上通过 @EnableConfigurationProperties 引入。第四，配置类上要加 @ConditionalOnClass 检查所依赖的第三方库是否存在。第五，不要在 Starter 里引入过多依赖，用 optional 声明依赖，让用户自己决定引入什么版本。

### **Q20** Spring Boot 启动流程的核心步骤？`SpringApplication.run()` 里做了什么？
?
1. run 方法里大概做了七件事。第一步，创建 SpringApplication 实例，推断应用类型（Servlet/Reactive），加载所有 ApplicationListener 和 ApplicationContextInitializer。第二步，创建并启动 StopWatch 计时。第三步，准备 Environment 环境对象，加载配置文件中的属性。第四步，打印 Banner。第五步，根据应用类型创建对应的 ApplicationContext（Servlet 应用创建 AnnotationConfigServletWebServerApplicationContext）。第六步，准备上下文：执行所有 ApplicationContextInitializer，加载主配置类，注册 Bean。第七步，刷新上下文 refresh——这是 Spring 最核心的步骤，完成 Bean 的实例化、依赖注入、初始化、启动内嵌 Web 服务器等。最后一步，发布 ApplicationStartedEvent 和 ApplicationReadyEvent 事件，表示应用启动完成。
2. 其中 refresh 是最关键的一步，它来自 Spring Framework 的 AbstractApplicationContext.refresh() 方法，包含十几个子步骤：prepareRefresh、obtainFreshBeanFactory、prepareBeanFactory、postProcessBeanFactory、invokeBeanFactoryPostProcessors、registerBeanPostProcessors、initMessageSource、initApplicationEventMulticaster、onRefresh（Spring Boot 在这里启动内嵌 Tomcat）、registerListeners、finishBeanFactoryInitialization（核心：实例化所有非懒加载单例 Bean）、finishRefresh。

---

## 六、Spring MVC

### **Q21** 一个 HTTP 请求进入 Spring MVC 后的完整处理流程？从 `DispatcherServlet` → `HandlerMapping` → `HandlerAdapter` → `Handler`（Controller）→ `ViewResolver` 说清楚。
?
1. 完整流程是这样的。请求首先到达 DispatcherServlet，它是整个 MVC 的前端控制器。DispatcherServlet 拿到请求后，第一步，通过 HandlerMapping 找到请求对应的 Handler——HandlerMapping 根据 URL、请求方法等匹配到具体的 Controller 和方法，返回一个 HandlerExecutionChain，里面包含了 Handler 和一串拦截器。第二步，通过 HandlerAdapter 执行 Handler——不同的 Handler 有不同的适配器，比如 @RequestMapping 注解的方法用 RequestMappingHandlerAdapter，它会做参数解析、数据绑定、校验等。第三步，Handler 执行完后返回 ModelAndView（或者通过 @ResponseBody 直接写响应体）。第四步，如果有视图名，通过 ViewResolver 解析视图名找到具体的视图模板（比如 Thymeleaf 模板），渲染成 HTML 返回。如果是前后端分离的 @RestController，则直接把返回值序列化为 JSON 写入响应体。
2. 这中间拦截器的 preHandle 在 HandlerMapping 之后、HandlerAdapter 之前执行，postHandle 在 Handler 执行之后、视图渲染之前执行，afterCompletion 在视图渲染完之后执行。

### **Q22** 拦截器（Interceptor）和过滤器（Filter）的区别？执行顺序是怎样的？如果 Filter 返回了错误码，Interceptor 还会执行吗？
?
1. 根本区别在于两者属于不同规范。Filter 是 Servlet 规范的一部分，工作在 Servlet 容器层面，在请求进入 DispatcherServlet 之前和之后执行。Interceptor 是 Spring MVC 自己的机制，工作在 DispatcherServlet 内部，在 Handler 执行前后执行。
2. 执行顺序是：Filter 前置 → DispatcherServlet → Interceptor preHandle → Handler（Controller）→ Interceptor postHandle → 视图渲染 → Interceptor afterCompletion → Filter 后置。
3. 功能上也有区别：Filter 可以修改请求和响应对象（比如包装 Request 做 XSS 过滤），Interceptor 在这方面能力有限。Filter 由 Servlet 容器管理，Interceptor 由 Spring 容器管理，所以 Interceptor 可以使用 Spring 的依赖注入。
4. 如果 Filter 在进入 DispatcherServlet 之前就返回了错误码（比如认证 Filter 返回 401），那请求根本不会到 DispatcherServlet，Interceptor 自然也不会执行。Filter 是整个请求链的第一道门，它挡住了，后面的全走不到。

### **Q23** `@RestController` 和 `@Controller` 的区别？`@ResponseBody` 做了什么？JSON 序列化用的是哪个框架？
?
1. @RestController 等于 @Controller + @ResponseBody。@Controller 标注的类是一个 MVC 控制器，方法可以返回视图名交给 ViewResolver 解析渲染。@RestController 标注的类，所有方法默认都会把返回值序列化写入 HTTP 响应体，不再走视图解析，适合前后端分离的 RESTful API。
2. @ResponseBody 的作用是告诉 Spring：这个方法的返回值不要解析为视图名，直接通过 HttpMessageConverter 转换为 HTTP 响应体。具体的转换规则取决于请求头中的 Accept 和返回值类型——如果返回的是对象，默认用 Jackson 框架序列化为 JSON 写入响应体。JSON 序列化默认用的是 Jackson，Spring Boot 的 spring-boot-starter-web 自动引入了 jackson-databind。如果 classpath 上有 Gson 或 fastjson 也会自动识别，但 Jackson 是默认的。

### **Q24** Spring MVC 的参数绑定原理？`@RequestParam`、`@PathVariable`、`@RequestBody` 各从请求的哪个位置取值？
?
1. 参数绑定的核心是 HandlerMethodArgumentResolver 接口，每一种参数注解都有对应的解析器实现。
2. @RequestParam 从 URL 的 Query String 或 POST 表单数据中取值。比如 /user?id=123，@RequestParam("id") 拿到 123。@PathVariable 从 URL 路径中取值——比如 /user/{id}，@PathVariable("id") 拿到路径模板变量。@RequestBody 从 HTTP 请求体中取值，通常用于接收 JSON 格式的 POST 请求体，通过 HttpMessageConverter 反序列化为 Java 对象。
3. 还有一个最常用的：不加任何注解的普通参数，会根据参数名从 Query String 或表单数据中取值，相当于隐式的 @RequestParam，但参数名需要编译时保留或者通过 -parameters 编译参数开启。

---

## 七、配置 & 属性绑定

### **Q25** Spring Boot 配置文件的加载优先级？`application.yml` vs `bootstrap.yml`（Spring Cloud），命令行参数 vs 配置文件 vs 环境变量，谁覆盖谁？
?
1. Spring Boot 的配置加载优先级从高到低是：命令行参数最高，然后是 JNDI 属性（java:comp/env），然后是 Java 系统属性（System.getProperties()），然后是操作系统环境变量，然后是 jar 包外的 application-{profile}.properties/yml，然后是 jar 包内的 application-{profile}.properties/yml，然后是 jar 包外的 application.properties/yml，最后是 jar 包内的 application.properties/yml。
2. 也就是说，命令行参数覆盖一切，jar 包内的配置优先级最低。环境变量在多项之间排在中间偏上位置。
3. bootstrap.yml 是 Spring Cloud 的概念，不是 Spring Boot 原生的。bootstrap.yml 的加载在 application.yml 之前，由 Bootstrap ApplicationContext 加载。它通常用于配置 Spring Cloud Config 远程配置的地址和应用名。应用启动时先加载 bootstrap.yml 连接配置中心拿到远程配置，再加载 application.yml 合并本地配置。bootstrap.yml 优先级高于 application.yml，但低于命令行参数。Spring Cloud 2020.0 之后默认不启用 bootstrap，需要引入 spring-cloud-starter-bootstrap 依赖。

### **Q26** `@ConfigurationProperties` 和 `@Value` 的区别？为什么推荐 `@ConfigurationProperties` 做批量属性绑定？松散绑定（Relaxed Binding）是什么意思？
?
1. 区别在四个方面。@ConfigurationProperties 是批量绑定——一个类一次性绑定所有前缀匹配的属性，适合一组相关配置。@Value 是单个绑定，每个需要单独写，适合少量配置。@ConfigurationProperties 支持 JSR303 校验（@Validated + @NotNull 等），@Value 不支持。@ConfigurationProperties 支持自定义类型安全转换，@Value 只能用 SpEL 表达式。
2. 推荐 @ConfigurationProperties 的原因：类型安全——绑定时自动做类型转换；结构化——一组相关配置放在一个类里，不分散；可复用——可以在不同地方注入同一个配置类。
3. 松散绑定就是属性名不要求精确匹配。比如配置文件里写 datasource.max-idle-time，Java 类里可以写 maxIdleTime，也可以写 MAX_IDLE_TIME 或者 max-idle-time，Spring 会自动匹配。这是 @ConfigurationProperties 的特性，@Value 不支持松散绑定，必须精确匹配。

### **Q27** 多环境配置怎么管理？`spring.profiles.active` 怎么用？`application-{profile}.yml` 和主配置文件的关系？
?
1. 通过 spring.profiles.active 指定当前激活的环境。比如 spring.profiles.active=dev，Spring Boot 就会加载 application-dev.yml。可以在主配置文件里设置，也可以通过命令行 --spring.profiles.active=dev 设置，或者环境变量 SPRING_PROFILES_ACTIVE=dev。
2. application.yml 是主配置文件，存放所有环境通用的默认配置。application-{profile}.yml 是环境专用配置，只覆盖当前环境需要不同的项。Spring 的合并规则是：先加载主配置，再加载 profile 专用配置，后者覆盖前者的同名属性。所以通用的留在主配置里，环境差异的放在各自 profile 配置里。
3. 常用的做法是：application.yml 放通用配置（端口号、公共数据源参数），application-dev.yml 放开发数据库地址和开发专用开关，application-prod.yml 放生产数据库地址和敏感信息（通常配合环境变量或配置中心使用）。

---

## 八、事件 & 异步

### **Q28** Spring 的事件机制（`ApplicationEvent` + `ApplicationListener` + `ApplicationEventPublisher`）怎么用？默认是同步还是异步？怎么改成异步？
?
1. 使用方式：第一步，定义一个事件类继承 ApplicationEvent。第二步，定义一个监听器实现 ApplicationListener 接口，或者在方法上加 @EventListener 注解。第三步，通过 ApplicationEventPublisher 的 publishEvent 方法发布事件，所有匹配的监听器就会被触发。
2. 默认是同步的——发布事件后，当前线程会逐个调用所有监听器的处理方法，等所有监听器执行完才继续往下走。这意味着如果某个监听器做了耗时操作（比如发邮件、写日志到磁盘），会阻塞业务线程。
3. 改成异步有两种方式。最简单的是在监听方法上加 @Async 注解，配合配置类上加 @EnableAsync。第二种是在 Spring Boot 配置文件里设置 spring.application.event.executor 为一个自定义线程池。两种方式的本质都是让监听器的执行脱离发布事件的线程。

### **Q29** `@Async` 的原理？默认线程池是什么？为什么不推荐用默认线程池？自定义线程池后，`@Async` 怎么指定？
?
1. @Async 的原理还是 AOP 代理。Spring 创建代理对象时，如果检测到方法上有 @Async，就会在代理里把这个方法的调用提交给线程池异步执行，主线程立即返回不等待结果。
2. 默认线程池是 SimpleAsyncTaskExecutor，它的问题是：每次任务来都创建一个新线程，没有线程复用，也没有最大线程数限制。高并发场景下会创建大量线程，每个线程默认 1MB 栈空间，可能瞬间耗尽内存导致 OOM。所以生产环境绝对不能直接用默认线程池。
3. 自定义线程池后，@Async 可以通过 value 属性指定 Bean 名：@Async("myTaskExecutor")。如果没有指定，Spring 会按优先级查找：先找唯一的 TaskExecutor Bean，再找名为 taskExecutor 的 Bean，最后才用默认的。最稳妥的方式是自定义一个 ThreadPoolTaskExecutor 并设置合理的核心线程数、最大线程数、队列大小和拒绝策略，然后在 @Async 上显式指定。

### **Q30** `@Scheduled` 定时任务的原理？`cron`、`fixedDelay`、`fixedRate` 的区别？如果有 3 个 `@Scheduled` 任务，默认是串行还是并行？怎么改并行？
?
1. @Scheduled 的原理是：Spring 在容器启动时注册一个 ScheduledAnnotationBeanPostProcessor，它会扫描所有 @Scheduled 方法，为每个方法创建一个定时任务注册到 TaskScheduler 里，由 TaskScheduler 按照指定的时间规则触发执行。
2. 三种时间策略的区别：cron 表达式——指定具体时间点执行，比如"每天凌晨 2 点"。fixedDelay 是上一次执行结束后等待指定时间再执行下一次，两次执行之间有间隔，单次执行时间过长会自动推迟下一次。fixedRate 是固定频率执行——不管上一次执行完没完，到了时间就启动下一次。如果 fixedRate 指定的间隔小于任务执行时间，可能会导致任务堆积。
3. 默认是串行的——所有 @Scheduled 任务由一个单线程的线程池执行，一个任务阻塞了后面的全部排队等着。改并行只需要自定义一个 TaskScheduler Bean 并设置线程池大小，Spring Boot 检测到自定义的 TaskScheduler 后就会用多线程去执行定时任务。

---

## 九、设计模式 & 扩展点

### **Q31** Spring 中用到了哪些设计模式？（至少说 8 种，每种对应 Spring 什么功能）
?
代理模式——AOP 就是通过动态代理实现的，不管是 JDK 代理还是 CGLIB。模板方法模式——JdbcTemplate、RestTemplate、RedisTemplate 这些 Template 类，定义了算法骨架，把可变部分留给子类或回调实现。工厂模式——BeanFactory 和 ApplicationContext 就是工厂模式，通过 getBean 方法来创建和管理 Bean 实例。单例模式——Spring 管理的 Bean 默认作用域是 singleton，整个容器只维护一个实例。观察者模式——Spring 的事件机制，ApplicationEvent 是事件对象，ApplicationListener 是观察者，通过 ApplicationEventPublisher 发布事件。策略模式——Spring 的 Resource 接口有不同的实现类，比如 ClassPathResource、FileSystemResource、UrlResource，根据资源类型选择不同的策略。适配器模式——Spring MVC 的 HandlerAdapter，不同的 Controller 类型有不同的 Adapter（比如 RequestMappingHandlerAdapter 处理 @RequestMapping 注解）。责任链模式——Spring MVC 的拦截器链，请求依次经过多个 HandlerInterceptor，每个都可以选择放行或拦截。

### **Q32** `BeanFactory` 和 `FactoryBean` 的区别？`FactoryBean` 在什么场景用？
?
1. 名字很像但完全不是一回事。BeanFactory 是 Spring 的 IoC 容器，负责管理所有 Bean 的生命周期。FactoryBean 是一个创建复杂对象的工厂接口。
2. FactoryBean 也是一个 Bean，但它不是直接返回自己，而是通过 getObject() 方法创建另一个 Bean。当你从容器中获取 FactoryBean 类型时，加上 & 前缀才能拿到 FactoryBean 本身，不加 & 拿到的是 getObject() 返回的对象。
3. 典型场景有：MyBatis 的 SqlSessionFactoryBean，它通过 FactoryBean 接口来创建复杂的 SqlSessionFactory；Dubbo 的 ReferenceBean，用来创建远程服务的代理对象；还有 Spring 自己的 ProxyFactoryBean，用来创建 AOP 代理对象。这些对象的创建过程很复杂，不适合简单地 new 一个出来，用 FactoryBean 把这个复杂创建过程封装起来，对调用方来说就像普通的 Bean 注入一样简单。

### **Q33** `ImportBeanDefinitionRegistrar` 和 `BeanDefinitionRegistryPostProcessor` 是做什么的？Spring Boot 的 `@EnableXxx` 注解底层是怎么工作的？
?
1. ImportBeanDefinitionRegistrar 是在 @Import 注解里使用的，它允许你以编程方式向 Spring 容器注册额外的 BeanDefinition。典型应用是 @EnableAspectJAutoProxy，它通过 @Import 导入 AspectJAutoProxyRegistrar，在 registerBeanDefinitions 方法里注册 AnnotationAwareAspectJAutoProxyCreator。
2. BeanDefinitionRegistryPostProcessor 是 BeanFactoryPostProcessor 的子接口，在所有 BeanDefinition 加载完成后、Bean 实例化之前执行，可以修改或注册新的 BeanDefinition。它比 ImportBeanDefinitionRegistrar 更通用和强大，是 MyBatis MapperScannerConfigurer 的实现基础——在 postProcessBeanDefinitionRegistry 里扫描指定包下的 Mapper 接口，动态注册为 BeanDefinition。
3. @EnableXxx 注解的底层流程是三步。第一步，定义 @EnableXxx 注解，通过 @Import 导入一个配置类或 ImportBeanDefinitionRegistrar 实现类。第二步，被导入的实现类中，读取 @EnableXxx 上的属性值作为配置参数。第三步，根据这些参数，扫描或创建相应的 BeanDefinition 注册到容器。比如 @EnableAsync 通过 @Import 导入 AsyncConfigurationSelector，选择器根据用户的 adviceMode 配置决定导入哪个配置类。

---

## 十、测试 & Actuator 监控

### **Q34** `@SpringBootTest` 和 `@WebMvcTest` 的区别？`@MockBean` 做了什么？单元测试和集成测试怎么分层？
?
1. @SpringBootTest 是集成测试注解，启动完整的 Spring Boot 容器，加载所有 Bean。@WebMvcTest 是切片测试注解，只加载 MVC 相关的 Bean（@Controller、@ControllerAdvice 等），不加载 Service 和 Repository，所以启动速度远快于 @SpringBootTest。
2. @MockBean 的作用是在 Spring 容器里把一个 Bean 替换成 Mockito 的 Mock 对象。比如 Controller 依赖 UserService，用 @MockBean 把 UserService 替换成 mock，测试时就可以通过 Mockito.when() 控制行为，不依赖真实数据库。
3. 分层策略：Controller 层用 @WebMvcTest + @MockBean，只测参数绑定、返回值格式、异常处理，Service 用 mock。Service 层用普通的单元测试，不启动 Spring 容器，只测业务逻辑，依赖通过构造函数传入 mock。Repository 层用 @DataJpaTest，测自定义 SQL。最后用 @SpringBootTest 做一到两个端到端的集成测试，覆盖关键业务流程，确保各层配合正确。这个金字塔结构能让测试既充分又不过慢。

### **Q35** Spring Boot Actuator 提供了哪些端点？`/health`、`/metrics`、`/env`、`/loggers` 各做了什么？生产环境怎么安全暴露 Actuator 端点？
?
1. Actuator 提供的常用端点有：/health 健康检查——返回应用的健康状态，包括数据库连接、磁盘空间、Redis 连接等指标，可以自定义 HealthIndicator。/metrics 指标信息——返回 JVM 内存、GC、线程池、HTTP 请求数等详细指标，支持按名称过滤。/env 环境信息——返回所有配置属性、系统属性、环境变量的值，注意会暴露敏感信息。/loggers 日志管理——可以动态查看和修改某个包的日志级别，不需要重启应用。/info 应用信息——返回自定义的应用描述信息。还有 /beans 查看所有 Bean、/threaddump 线程转储、/heapdump 内存转储、/mappings 查看所有请求映射等。
2. 生产环境安全策略：第一，引入 spring-boot-starter-security，给 Actuator 端点加上认证。第二，通过 management.endpoints.web.exposure.include 只暴露必要的端点，不要 include=*。第三，敏感端点（/env、/heapdump）绝对不要暴露。第四，management.server.port 配置独立端口，不和业务端口混用。第五，如果用了 Prometheus，只暴露 /actuator/prometheus 就够了，其他端点关掉。第六，/health 的 details 用 management.endpoint.health.show-details=when-authorized 限制有权限的用户才能看详情。

---

## 十一、Spring Boot 3.x / Spring 6.x 新特性

### **Q36** Spring Boot 3.x 基于 Jakarta EE 而不是 Java EE，`javax.*` 全部变成 `jakarta.*`，迁移时最大的坑是什么？
?
1. 最大的坑是依赖兼容性问题。Spring Boot 3.x 要求 Jakarta EE 9+，所有 javax.* 的包都变成了 jakarta.*。如果你项目里有第三方库还在用 javax.servlet、javax.persistence 这些 javax 包，会和新的 jakarta 包冲突，导致 ClassNotFoundException 或 NoClassDefFoundError。
2. 具体表现：Tomcat 升级到了 10.x，只认 jakarta.servlet，不认 javax.servlet；Hibernate 6.x 只认 jakarta.persistence；所有 Servlet Filter、Listener 的 import 都需要从 javax 改成 jakarta。
3. 迁移时的几个重点：用 IDE 的批量替换功能把 javax 改成 jakarta，但要小心 javax.sql、javax.crypto 这些不属于 Jakarta EE 的包不能改。检查所有第三方依赖版本是否支持 Jakarta EE。Spring Cloud 的版本要同步升级到对应的兼容版本。最大的坑其实是那些间接依赖——你引用的某个 jar 包里可能嵌入了 javax.servlet 的类，等运行时才发现不兼容。

### **Q37** Spring Boot 3.x 支持 GraalVM AOT 编译，AOT 和 JIT 的区别？AOT 编译成 Native Image 有什么好处和限制？哪些 Spring 特性在 Native Image 下不可用？
?
1. AOT 是在应用启动之前把字节码编译成机器码，JIT 是在运行时把热点代码编译成机器码。AOT 的好处：启动速度极快——Native Image 启动时间从秒级降到毫秒级；内存占用低——不需要 JVM 运行时和 JIT 编译器元数据，镜像体积小很多；适合 Serverless 和容器化场景——快速弹性伸缩。代价是失去了 JIT 的运行时优化能力。
2. Native Image 的限制比较多。第一，不支持动态类加载和运行时反射——必须在编译期通过 reflect-config.json 声明所有需要反射的类。第二，不支持动态代理——JDK 动态代理和 CGLIB 都无法在 Native Image 下工作，必须用 AOT 代理处理。第三，不支持 @Profile 动态切换——因为配置在编译时就确定了。第四，不支持 JMX 和部分监控能力。第五，GC 策略不同，用的是 GraalVM 自带的 GC。
3. Spring 特性方面的限制：@Async、@Scheduled 等依赖 AOP 代理的特性需要额外的 AOT 提示配置。@ConditionalOnXXX 在 AOT 时就已经决定了，不能在运行时改变。JPA 的懒加载和某些 Hibernate 特性可能无法正常工作。所以 Native Image 虽然启动快，但需要反复测试验证所有功能是否可用，不是所有项目都能不加改造就迁移过去的。

### **Q38** Spring Boot 3.x 引入的"虚拟线程"支持（`spring.threads.virtual.enabled=true`），和之前的平台线程池有什么不同？什么时候该开？
?
1. 虚拟线程和平台线程的根本区别：平台线程是操作系统线程的一对一映射，每个线程占用约 1MB 栈空间，创建和切换开销大。虚拟线程是 JVM 层面的轻量级线程，没有一对一映射关系——大量虚拟线程共享少量操作系统线程。当虚拟线程遇到阻塞操作（比如 IO、sleep、锁等待）时，JVM 会把它从载体线程上卸载，载体线程去执行其他虚拟线程的任务，等阻塞结束再恢复执行。
2. 这意味着什么？以前我们用线程池限制并发数，是因为线程太贵了。有了虚拟线程，可以每请求一个线程——一个请求进来就创建一个虚拟线程去处理，处理完就销毁。不再需要池化和复杂的大小调优，代码从异步风格回归到同步风格，可读性大幅提升。
3. 什么时候该开：IO 密集型任务是最适合的场景——大量阻塞在数据库查询、HTTP 调用、消息队列等待上，虚拟线程能让少量 OS 线程支撑大量并发。CPU 密集型任务不适合——虚拟线程解决不了计算瓶颈，反而因为线程切换会增加开销。另外，如果代码里有大量 synchronized 块或 native 方法调用，虚拟线程会被"钉住"，无法从载体线程卸载，此时不推荐开启。

---

## 十二、实战场景

### **Q39** 你有一个复杂的业务流程：创建订单 → 扣库存 → 扣优惠券 → 创建支付单 → 发消息。如果扣优惠券失败需要回滚前面的扣库存，但发消息失败不能回滚业务，用 Spring 事务怎么设计？
?
1. 这个问题的核心是：有一部分操作需要事务性回滚（扣库存、扣优惠券），另一部分不需要也不应该回滚（发消息），还有一部分需要尽可能成功（创建支付单）。
2. 设计方案：在 Service 层用一个 @Transactional 的方法包裹创建订单、扣库存、扣优惠券、创建支付单这四个步骤。这四个操作要么都成功要么都失败——扣优惠券失败时，由于抛出 RuntimeException，事务回滚，库存恢复，订单回滚。
3. 发消息放在事务提交之后再发。具体做法有两种。第一种是用 TransactionSynchronizationManager.registerSynchronization() 注册一个 afterCommit 回调，在回调里发消息——只有事务真正提交了才触发，回滚了不会触发。第二种是用 @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)，发布一个事件，在事务提交后监听器异步发消息。
4. 为什么发消息不能放在事务里？如果放在事务里，消息可能发成功了但事务最后回滚了——消费方以为业务已经完成，但实际上数据已经回滚了，这是最危险的不一致。所以消息一定要在事务确认提交后再发，这是保证最终一致性的基本要求。

### **Q40** 线上服务 @Transactional 没生效，导致数据不一致，你怎么定位问题？列出排查清单。
?
1. 按以下清单逐项排查。
2. 第一项，检查方法是否是 public。打开对应的类，确认加了 @Transactional 的方法修饰符是 public。如果是 protected 或 private，事务不会生效。
3. 第二项，检查自调用。搜索类内部有没有用 this.xxx() 调用这个事务方法的地方。如果有，这就是典型的自调用失效——this 调用绕过了代理。
4. 第三项，检查异常处理。看看方法内部有没有 try-catch 吞掉了异常。特别是 catch(Exception e) 然后只打日志没有 throw 的情况。确认事务回滚需要的异常类型是否被抛出来了——默认只有 RuntimeException 和 Error 才回滚。
5. 第四项，检查数据库引擎。连上数据库，执行 SHOW TABLE STATUS 或 SHOW CREATE TABLE，确认表用的是 InnoDB 引擎而不是 MyISAM。InnoDB 才支持事务。
6. 第五项，检查 Spring 代理是否生效。打断点或者加日志，看这个方法进入的时候，调用栈里有没有 TransactionInterceptor。如果没有，说明代理没生成。检查配置类是否有 @EnableTransactionManagement（Spring Boot 自动配置了但手动配置可能没加）。
7. 第六项，检查多数据源。如果有多个数据源，确认 @Transactional 指定的 transactionManager 是否和操作的数据源对应。多数据源下事务不会跨数据源生效。
8. 第七项，检查线程。如果该方法在新线程中被调用，事务不会传播到新线程。日志里搜一下有没有 @Async 或显式的 new Thread。
9. 按这个顺序，一般前三项就能定位到 90% 的问题。
