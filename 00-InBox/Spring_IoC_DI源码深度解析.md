# Spring IoC/DI 源码深度解析

> 版本基准：Spring Framework 5.3.x（JDK 8+ 兼容）  
> 学习路径：容器启动 → BeanDefinition → Bean生命周期 → 循环依赖 → 整体串联  
> 阅读建议：每章结合文中的源码片段在 IDE 中对照 Spring 对应版本的源码断点调试

---

## 目录

- [Part 1 整体架构](#part-1-整体架构)
  - [1.1 核心接口层次图](#11-核心接口层次图)
  - [1.2 BeanFactory 与 ApplicationContext](#12-beanfactory-与-applicationcontext)
  - [1.3 AnnotationConfigApplicationContext 启动入口](#13-annotationconfigapplicationcontext-启动入口)
- [Part 2 容器启动：refresh() 十二步](#part-2-容器启动refresh-十二步)
  - [2.1 refresh() 源码全貌](#21-refresh-源码全貌)
  - [2.2 prepareRefresh — 环境准备](#22-preparerefresh--环境准备)
  - [2.3 obtainFreshBeanFactory — 获取/刷新 BeanFactory](#23-obtainfreshbeanfactory--获取刷新-beanfactory)
  - [2.4 invokeBeanFactoryPostProcessors — BFPP 执行](#24-invokebeanfactorypostprocessors--bfpp-执行)
  - [2.5 registerBeanPostProcessors — BPP 注册](#25-registerbeanpostprocessors--bpp-注册)
  - [2.6 finishBeanFactoryInitialization — 实例化所有单例](#26-finishbeanfactoryinitialization--实例化所有单例)
- [Part 3 BeanDefinition：Bean 的出生证明](#part-3-beandefinition-bean-的出生证明)
  - [3.1 BeanDefinition 核心字段](#31-beandefinition-核心字段)
  - [3.2 注解扫描：ClassPathBeanDefinitionScanner](#32-注解扫描-classpathbeandefinitionscanner)
  - [3.3 ConfigurationClassPostProcessor — @Configuration 解析](#33-configurationclasspostprocessor--configuration-解析)
- [Part 4 Bean 生命周期](#part-4-bean-生命周期)
  - [4.1 生命周期全流程图](#41-生命周期全流程图)
  - [4.2 createBean — 入口](#42-createbean--入口)
  - [4.3 doCreateBean — 核心三步](#43-docreatebean--核心三步)
  - [4.4 实例化：instantiateBean](#44-实例化-instantiatebean)
  - [4.5 属性注入：populateBean](#45-属性注入-populatebean)
  - [4.6 初始化：initializeBean](#46-初始化-initializebean)
  - [4.7 销毁：DisposableBean & @PreDestroy](#47-销毁-disposablebean--predestroy)
- [Part 5 @Autowired 注入原理](#part-5-autowired-注入原理)
  - [5.1 AutowiredAnnotationBeanPostProcessor](#51-autowiredannotationbeanpostprocessor)
  - [5.2 @Qualifier 与按名注入](#52-qualifier-与按名注入)
  - [5.3 @Value 与 EL 表达式注入](#53-value-与-el-表达式注入)
- [Part 6 循环依赖与三级缓存](#part-6-循环依赖与三级缓存)
  - [6.1 什么是循环依赖](#61-什么是循环依赖)
  - [6.2 三级缓存数据结构](#62-三级缓存数据结构)
  - [6.3 getSingleton — 缓存查找](#63-getsingleton--缓存查找)
  - [6.4 三级缓存工作流程详解](#64-三级缓存工作流程详解)
  - [6.5 为什么需要第三级缓存（singletonFactories）](#65-为什么需要第三级缓存-singletonfactories)
  - [6.6 哪些循环依赖 Spring 解决不了](#66-哪些循环依赖-spring-解决不了)
- [Part 7 FactoryBean vs BeanFactory](#part-7-factorybean-vs-beanfactory)
  - [7.1 FactoryBean 接口源码](#71-factorybean-接口源码)
  - [7.2 getBean("&myBean") 获取原始 FactoryBean](#72-getbeanmybean-获取原始-factorybean)
  - [7.3 典型应用：MyBatis MapperFactoryBean](#73-典型应用mybatis-mapperfactorybean)
- [Part 8 BeanPostProcessor 全家族](#part-8-beanpostprocessor-全家族)
  - [8.1 BeanPostProcessor 执行位置](#81-beanpostprocessor-执行位置)
  - [8.2 InstantiationAwareBeanPostProcessor](#82-instantiationawarebeanpostprocessor)
  - [8.3 SmartInstantiationAwareBeanPostProcessor](#83-smartinstantiationawarebeanpostprocessor)
  - [8.4 DestructionAwareBeanPostProcessor](#84-destructionawarebeanpostprocessor)
- [Part 9 Spring 整体流程串联](#part-9-spring-整体流程串联)
  - [9.1 从 new ApplicationContext 到第一个 Bean 可用](#91-从-new-applicationcontext-到第一个-bean-可用)
  - [9.2 关键调用栈](#92-关键调用栈)
  - [9.3 AOP 代理在哪里介入（预告）](#93-aop-代理在哪里介入预告)
- [Part 10 高频面试题 12 道](#part-10-高频面试题-12-道)
- [附录 A Spring IoC 核心类速查](#附录-a-spring-ioc-核心类速查)
- [附录 B 生命周期各扩展点汇总表](#附录-b-生命周期各扩展点汇总表)

---

## Part 1 整体架构

### 1.1 核心接口层次图

```
BeanFactory                          ← 最基础的 IoC 容器接口
  ├── HierarchicalBeanFactory        ← 支持父子容器
  ├── ListableBeanFactory            ← 支持枚举所有 Bean
  └── AutowireCapableBeanFactory     ← 支持自动装配

ConfigurableBeanFactory              ← 可配置化（添加BPP/BFPP/Scope等）
  └── ConfigurableListableBeanFactory ← 综合接口（DefaultListableBeanFactory 实现它）

ApplicationContext                   ← 企业级容器（继承 ListableBeanFactory）
  ├── AnnotationConfigApplicationContext   ← 注解驱动
  ├── ClassPathXmlApplicationContext       ← XML 驱动
  └── GenericWebApplicationContext         ← Web 环境

AbstractApplicationContext           ← 模板方法模式，定义 refresh() 骨架
  └── AbstractRefreshableApplicationContext
        └── AbstractXmlApplicationContext
              └── ClassPathXmlApplicationContext

GenericApplicationContext            ← 持有单个 DefaultListableBeanFactory
  └── AnnotationConfigApplicationContext
```

**核心关系**：ApplicationContext 不继承 BeanFactory，而是**聚合**了一个 `DefaultListableBeanFactory`（通过 `getBeanFactory()` 暴露）。对外 ApplicationContext 也委托给它完成 `getBean` 等操作。

---

### 1.2 BeanFactory 与 ApplicationContext

| 特性 | BeanFactory | ApplicationContext |
|------|------------|-------------------|
| 基础 getBean | ✅ | ✅（委托 DefaultListableBeanFactory） |
| 国际化（MessageSource） | ❌ | ✅ |
| 事件发布（ApplicationEvent） | ❌ | ✅ |
| 资源加载（ResourceLoader） | ❌ | ✅ |
| AOP 自动代理 | 需手动 | ✅（BPP自动触发） |
| 初始化时机 | 懒加载（getBean才初始化） | 启动时预实例化所有单例 |

---

### 1.3 AnnotationConfigApplicationContext 启动入口

```java
// 用法
ApplicationContext ctx = new AnnotationConfigApplicationContext(AppConfig.class);
UserService us = ctx.getBean(UserService.class);

// 构造方法源码
public AnnotationConfigApplicationContext(Class<?>... componentClasses) {
    this();                          // 1. 调用无参构造：创建 reader 和 scanner
    register(componentClasses);      // 2. 注册配置类为 BeanDefinition
    refresh();                       // 3. 刷新容器（核心！）
}

public AnnotationConfigApplicationContext() {
    // 创建注解 BeanDefinition 读取器
    // 内部注册了 6 个基础 BeanDefinition（ConfigurationClassPostProcessor 等）
    this.reader = new AnnotatedBeanDefinitionReader(this);
    // 创建类路径 BeanDefinition 扫描器
    this.scanner = new ClassPathBeanDefinitionScanner(this);
}
```

**关键点**：无参构造中注册的 6 个基础 `BeanDefinition`：

```java
// AnnotationConfigUtils.registerAnnotationConfigProcessors()
// 注册的核心处理器（都是 BeanDefinitionRegistryPostProcessor 或 BeanPostProcessor）：

1. ConfigurationClassPostProcessor         (BFPP) ← 解析 @Configuration/@ComponentScan/@Bean
2. AutowiredAnnotationBeanPostProcessor    (BPP)  ← 处理 @Autowired/@Value
3. CommonAnnotationBeanPostProcessor       (BPP)  ← 处理 @Resource/@PostConstruct/@PreDestroy
4. PersistenceAnnotationBeanPostProcessor  (BPP)  ← 处理 @PersistenceContext（JPA）
5. EventListenerMethodProcessor            (BPP)  ← 处理 @EventListener
6. DefaultEventListenerFactory
```

---

## Part 2 容器启动：refresh() 十二步

### 2.1 refresh() 源码全貌

```java
// AbstractApplicationContext.refresh()
@Override
public void refresh() throws BeansException, IllegalStateException {
    synchronized (this.startupShutdownMonitor) {  // 防并发刷新
        
        // ① 准备刷新
        prepareRefresh();
        
        // ② 获取（或创建）BeanFactory，加载 BeanDefinition
        ConfigurableListableBeanFactory beanFactory = obtainFreshBeanFactory();
        
        // ③ 对 BeanFactory 进行标准化配置
        //    注册 ClassLoader、BPP（ApplicationContextAwareProcessor 等）、忽略的依赖接口
        prepareBeanFactory(beanFactory);
        
        // ④ 子类扩展点：允许 ApplicationContext 子类对 BeanFactory 做后处理
        postProcessBeanFactory(beanFactory);
        
        // ⑤ 调用所有 BeanFactoryPostProcessor（BFPP）
        //    重要：ConfigurationClassPostProcessor 在此解析 @Configuration 类
        invokeBeanFactoryPostProcessors(beanFactory);
        
        // ⑥ 注册所有 BeanPostProcessor（BPP）
        //    注意：此时只是注册，不会调用，Bean 还没有被实例化
        registerBeanPostProcessors(beanFactory);
        
        // ⑦ 初始化 MessageSource（国际化）
        initMessageSource();
        
        // ⑧ 初始化事件广播器
        initApplicationEventMulticaster();
        
        // ⑨ 子类扩展点（Web 容器在此初始化 Servlet 相关组件）
        onRefresh();
        
        // ⑩ 注册事件监听器
        registerListeners();
        
        // ⑪ 实例化所有非懒加载的单例 Bean ← 核心！Bean 生命周期在此触发
        finishBeanFactoryInitialization(beanFactory);
        
        // ⑫ 完成刷新：发布 ContextRefreshedEvent 事件
        finishRefresh();
    }
}
```

---

### 2.2 prepareRefresh — 环境准备

```java
protected void prepareRefresh() {
    this.startupDate = System.currentTimeMillis();         // 记录启动时间
    this.closed.set(false);
    this.active.set(true);
    
    // 子类可以在此验证必需的环境变量
    initPropertySources();
    getEnvironment().validateRequiredProperties();
    
    // 保存早期的 ApplicationEvent（在广播器初始化之前发布的事件）
    this.earlyApplicationEvents = new LinkedHashSet<>();
}
```

---

### 2.3 obtainFreshBeanFactory — 获取/刷新 BeanFactory

对于 `AnnotationConfigApplicationContext`（extends `GenericApplicationContext`）：

```java
// GenericApplicationContext.refreshBeanFactory()
@Override
protected final void refreshBeanFactory() throws IllegalStateException {
    // 只能 refresh 一次，CAS 保证原子性
    if (!this.refreshed.compareAndSet(false, true)) {
        throw new IllegalStateException("GenericApplicationContext 不支持多次 refresh");
    }
    this.beanFactory.setSerializationId(getId());
}

@Override
protected final ConfigurableListableBeanFactory getBeanFactory() {
    return this.beanFactory;  // 直接返回构造时创建的 DefaultListableBeanFactory
}
```

对于 `ClassPathXmlApplicationContext`（extends `AbstractRefreshableApplicationContext`）：
- 会销毁旧的 BeanFactory，创建新的 `DefaultListableBeanFactory`，并重新加载 XML 中的 BeanDefinition。

---

### 2.4 invokeBeanFactoryPostProcessors — BFPP 执行

这是 refresh() 最复杂的一步，核心是执行 `ConfigurationClassPostProcessor`。

```java
// PostProcessorRegistrationDelegate.invokeBeanFactoryPostProcessors()
// 分为两类：
// BeanDefinitionRegistryPostProcessor (extends BFPP) → 先执行，可以注册新 BeanDefinition
// BeanFactoryPostProcessor                           → 后执行，只能修改已有 BeanDefinition

// 执行顺序：
// 1. 已注册的 BDRegistryPostProcessor（实现 PriorityOrdered）
// 2. 已注册的 BDRegistryPostProcessor（实现 Ordered）
// 3. 已注册的 BDRegistryPostProcessor（其他）
// 4. 普通 BeanFactoryPostProcessor（PriorityOrdered → Ordered → 其他）

// ConfigurationClassPostProcessor 实现了 BeanDefinitionRegistryPostProcessor + PriorityOrdered
// 所以它在第 1 步就被执行
```

**ConfigurationClassPostProcessor 做了什么？**

```java
// ConfigurationClassPostProcessor.processConfigBeanDefinitions()
// 核心逻辑（简化）：

// 1. 找到所有 @Configuration 类（包括 @Component 带 @Bean 方法的 "lite" 配置类）
// 2. 用 ConfigurationClassParser 递归解析：
//    - @ComponentScan → 扫描包路径，注册所有 @Component
//    - @Import → 导入配置类 / ImportSelector / ImportBeanDefinitionRegistrar
//    - @Bean → 注册方法返回值为 BeanDefinition
//    - @ImportResource → 加载 XML
//    - @PropertySource → 加载 .properties 文件
// 3. 用 ConfigurationClassBeanDefinitionReader 把解析结果写入 BeanFactory
// 4. 对 @Configuration(full=true) 的类用 CGLIB 增强（保证 @Bean 方法调用返回同一实例）
```

---

### 2.5 registerBeanPostProcessors — BPP 注册

```java
// PostProcessorRegistrationDelegate.registerBeanPostProcessors()

// 注册顺序（不影响执行顺序，执行顺序取决于 beanFactory 内部的 beanPostProcessors 列表顺序）：
// 1. PriorityOrdered 的 BPP（如 AutowiredAnnotationBeanPostProcessor）
// 2. Ordered 的 BPP
// 3. 普通 BPP
// 4. MergedBeanDefinitionPostProcessor（内部 BPP）
// 5. ApplicationListenerDetector（最后追加，用于检测 ApplicationListener Bean）

// 注意：BPP 的实例化是在这一步，但 BPP 本身的 @Autowired 不会被处理
// （因为处理 @Autowired 的 BPP 还没注册完）
// Spring 的解决方案：BPP 只能通过构造器注入，不能依赖其他 Bean
```

---

### 2.6 finishBeanFactoryInitialization — 实例化所有单例

```java
protected void finishBeanFactoryInitialization(ConfigurableListableBeanFactory beanFactory) {
    // 初始化 ConversionService（类型转换服务）
    if (beanFactory.containsBean(CONVERSION_SERVICE_BEAN_NAME) && ...) {
        beanFactory.setConversionService(...);
    }
    
    // 注册 EmbeddedValueResolver（用于 @Value 的 ${} 解析）
    if (!beanFactory.hasEmbeddedValueResolver()) {
        beanFactory.addEmbeddedValueResolver(strVal -> getEnvironment().resolvePlaceholders(strVal));
    }
    
    // 提前初始化 LoadTimeWeaverAware（AspectJ LTW）
    String[] weaverAwareNames = beanFactory.getBeanNamesForType(LoadTimeWeaverAware.class, false, false);
    for (String weaverAwareName : weaverAwareNames) {
        getBean(weaverAwareName);
    }
    
    // 停止使用临时 ClassLoader（LTW用）
    beanFactory.setTempClassLoader(null);
    
    // 冻结 BeanDefinition（此后不允许再注册新的 BeanDefinition）
    beanFactory.freezeConfiguration();
    
    // ★ 预实例化所有非懒加载的单例 Bean
    beanFactory.preInstantiateSingletons();
}

// DefaultListableBeanFactory.preInstantiateSingletons()
@Override
public void preInstantiateSingletons() throws BeansException {
    // 拿到所有 BeanDefinition 的名称（此时已全部注册完毕）
    List<String> beanNames = new ArrayList<>(this.beanDefinitionNames);
    
    for (String beanName : beanNames) {
        RootBeanDefinition bd = getMergedLocalBeanDefinition(beanName);
        
        // 非抽象 + 单例 + 非懒加载 → 触发实例化
        if (!bd.isAbstract() && bd.isSingleton() && !bd.isLazyInit()) {
            if (isFactoryBean(beanName)) {
                // FactoryBean 先实例化 FactoryBean 本身，再根据 isEagerInit 决定是否实例化目标
                Object bean = getBean(FACTORY_BEAN_PREFIX + beanName);  // "&beanName"
                if (bean instanceof SmartFactoryBean<?> smartFactoryBean && smartFactoryBean.isEagerInit()) {
                    getBean(beanName);
                }
            } else {
                getBean(beanName);  // 触发完整的 Bean 生命周期
            }
        }
    }
    
    // 所有单例初始化完毕后，触发 SmartInitializingSingleton.afterSingletonsInstantiated()
    for (String beanName : beanNames) {
        Object singletonInstance = getSingleton(beanName);
        if (singletonInstance instanceof SmartInitializingSingleton smartSingleton) {
            smartSingleton.afterSingletonsInstantiated();
        }
    }
}
```

---

## Part 3 BeanDefinition：Bean 的出生证明

### 3.1 BeanDefinition 核心字段

```java
// BeanDefinition 接口的核心属性（AbstractBeanDefinition 实现）

public abstract class AbstractBeanDefinition extends BeanMetadataAttributeAccessor
        implements BeanDefinition, Cloneable {

    // Bean 的 Class 或 className（支持懒加载解析）
    @Nullable
    private volatile Object beanClass;

    // 作用域：singleton / prototype / request / session
    @Nullable
    private String scope = SCOPE_DEFAULT;  // 默认空字符串（等同 singleton）

    // 是否抽象（不可实例化，通常作为父 BeanDefinition）
    private boolean abstractFlag = false;

    // 是否懒加载
    @Nullable
    private Boolean lazyInit;

    // 自动装配模式：NO / BY_NAME / BY_TYPE / CONSTRUCTOR
    private int autowireMode = AUTOWIRE_NO;

    // 依赖检查模式（Spring 5 已基本废弃）
    private int dependencyCheck = DEPENDENCY_CHECK_NONE;

    // 显式指定的依赖（@DependsOn）：确保这些 Bean 先初始化
    @Nullable
    private String[] dependsOn;

    // 是否作为自动装配候选
    private boolean autowireCandidate = true;

    // 是否作为首选候选（@Primary）
    private boolean primary = false;

    // 构造器参数值
    @Nullable
    private ConstructorArgumentValues constructorArgumentValues;

    // 属性值（XML property 标签 / @Bean 方法参数映射）
    @Nullable
    private MutablePropertyValues propertyValues;

    // 初始化方法名（@Bean(initMethod) / XML init-method）
    @Nullable
    private String initMethodName;

    // 销毁方法名（@Bean(destroyMethod) / XML destroy-method）
    @Nullable
    private String destroyMethodName;

    // 是否由 Spring 基础设施合成（不由用户定义）
    private boolean synthetic = false;

    // 来源：APPLICATION / INFRASTRUCTURE / SUPPORT
    private int role = BeanDefinition.ROLE_APPLICATION;
}
```

---

### 3.2 注解扫描：ClassPathBeanDefinitionScanner

```java
// ClassPathBeanDefinitionScanner.doScan(basePackages)
protected Set<BeanDefinitionHolder> doScan(String... basePackages) {
    Set<BeanDefinitionHolder> beanDefinitions = new LinkedHashSet<>();
    for (String basePackage : basePackages) {
        // 1. 找到所有 @Component 候选类（通过 ASM 读取字节码，不需要 Class.forName）
        Set<BeanDefinition> candidates = findCandidateComponents(basePackage);
        
        for (BeanDefinition candidate : candidates) {
            // 2. 解析 @Scope
            ScopeMetadata scopeMetadata = this.scopeMetadataResolver.resolveScopeMetadata(candidate);
            candidate.setScope(scopeMetadata.getScopeName());
            
            // 3. 生成 beanName（@Component value 或类名首字母小写）
            String beanName = this.beanNameGenerator.generateBeanName(candidate, this.registry);
            
            // 4. 设置默认值（lazyInit / autowireMode / dependencyCheck 等）
            if (candidate instanceof AbstractBeanDefinition abd) {
                postProcessBeanDefinition(abd, beanName);
            }
            
            // 5. 解析 @Lazy / @Primary / @DependsOn / @Role / @Description
            if (candidate instanceof AnnotatedBeanDefinition abd) {
                AnnotationConfigUtils.processCommonDefinitionAnnotations(abd);
            }
            
            // 6. 检查是否已存在（重名处理）
            if (checkCandidate(beanName, candidate)) {
                BeanDefinitionHolder definitionHolder = new BeanDefinitionHolder(candidate, beanName);
                // 7. 处理 Scope 代理（ScopedProxyMode）
                definitionHolder = AnnotationConfigUtils.applyScopedProxyMode(
                        scopeMetadata, definitionHolder, this.registry);
                beanDefinitions.add(definitionHolder);
                // 8. 注册到 BeanFactory
                registerBeanDefinition(definitionHolder, this.registry);
            }
        }
    }
    return beanDefinitions;
}
```

---

### 3.3 ConfigurationClassPostProcessor — @Configuration 解析

```java
// 关键：@Configuration(proxyBeanMethods = true) 的 CGLIB 增强

// 为什么需要 CGLIB 增强？
@Configuration
public class AppConfig {
    @Bean
    public A a() { return new A(b()); }  // 调用 b() 方法
    
    @Bean
    public B b() { return new B(); }
}

// 如果不增强：a() 方法里调用 b() 会直接 new B()，得到一个新实例
// 如果有增强：CGLIB 代理拦截 b() 调用，转为 beanFactory.getBean("b")，保证单例

// @Configuration(proxyBeanMethods = false) ← "lite" 模式，不代理，性能更好
// 代价：@Bean 方法之间的相互调用不再保证单例
```

---

## Part 4 Bean 生命周期

### 4.1 生命周期全流程图

```
[BeanDefinition 已注册]
         |
         v
getBean(beanName)
         |
         v
AbstractBeanFactory.doGetBean()
    ├── 1. getSingleton() 查三级缓存（循环依赖处理）
    ├── 2. 处理 dependsOn（先实例化依赖的 Bean）
    └── 3. getSingleton(beanName, singletonFactory)
               |
               v
         createBean(beanName, mbd, args)
               |
               ├── InstantiationAwareBPP.postProcessBeforeInstantiation()  ← 可返回代理对象短路
               |
               v
         doCreateBean(beanName, mbd, args)
               |
               ├─── [实例化] instantiateBean() 或 autowireConstructor()
               |         通过反射或 CGLIB 创建原始对象
               |
               ├─── [早期引用] addSingletonFactory()  ← 放入三级缓存（解决循环依赖）
               |
               ├─── [MergedBPP] applyMergedBeanDefinitionPostProcessors()
               |         AutowiredAnnotationBPP 在此收集 @Autowired 注入元数据
               |
               ├─── [属性注入] populateBean()
               |         ├── IBP.postProcessAfterInstantiation()  ← 可阻止属性注入
               |         ├── IBP.postProcessProperties()          ← @Autowired/@Resource 注入
               |         └── applyPropertyValues()                ← XML property 注入
               |
               └─── [初始化] initializeBean()
                         ├── invokeAwareMethods()         ← BeanNameAware/BeanFactoryAware
                         ├── BPP.postProcessBeforeInitialization()  ← @PostConstruct（CommonAnnotationBPP）
                         ├── invokeInitMethods()
                         |     ├── InitializingBean.afterPropertiesSet()
                         |     └── custom initMethod
                         └── BPP.postProcessAfterInitialization()   ← AOP 代理在此创建！
                                   |
                                   v
                         [返回最终 Bean（可能是代理）]
                                   |
                                   v
                         [加入一级缓存 singletonObjects]

[容器关闭时]
         |
         v
destroySingletons()
    ├── @PreDestroy（CommonAnnotationBPP）
    ├── DisposableBean.destroy()
    └── custom destroyMethod
```

---

### 4.2 createBean — 入口

```java
// AbstractAutowireCapableBeanFactory.createBean()
@Override
protected Object createBean(String beanName, RootBeanDefinition mbd, @Nullable Object[] args)
        throws BeanCreationException {

    RootBeanDefinition mbdToUse = mbd;
    
    // 确保 beanClass 已经解析（可能是 className 字符串，需要 Class.forName）
    Class<?> resolvedClass = resolveBeanClass(mbd, beanName);
    if (resolvedClass != null && !mbd.hasBeanClass() && mbd.getBeanClassName() != null) {
        mbdToUse = new RootBeanDefinition(mbd);
        mbdToUse.setBeanClass(resolvedClass);
    }
    
    // 处理 lookup-method 和 replaced-method（方法注入，较少用）
    mbdToUse.prepareMethodOverrides();
    
    try {
        // ★ 给 InstantiationAwareBPP 一个机会直接返回代理对象（短路整个实例化流程）
        // 典型用途：AbstractAutoProxyCreator 可在此为某些类创建代理（罕见情况）
        Object bean = resolveBeforeInstantiation(beanName, mbdToUse);
        if (bean != null) {
            return bean;  // 短路！直接返回
        }
    } catch (Throwable ex) { ... }
    
    try {
        // ★ 真正的创建逻辑
        Object beanInstance = doCreateBean(beanName, mbdToUse, args);
        return beanInstance;
    } catch (BeanCreationException | ImplicitlyAppearedSingletonException ex) {
        throw ex;
    }
}
```

---

### 4.3 doCreateBean — 核心三步

```java
// AbstractAutowireCapableBeanFactory.doCreateBean()
protected Object doCreateBean(String beanName, RootBeanDefinition mbd, @Nullable Object[] args)
        throws BeanCreationException {

    // ①【实例化】
    BeanWrapper instanceWrapper = null;
    if (mbd.isSingleton()) {
        instanceWrapper = this.factoryBeanInstanceCache.remove(beanName);
    }
    if (instanceWrapper == null) {
        instanceWrapper = createBeanInstance(beanName, mbd, args);
    }
    Object bean = instanceWrapper.getWrappedInstance();
    Class<?> beanType = instanceWrapper.getWrappedClass();
    
    // 收集 MergedBeanDefinitionPostProcessor 信息（@Autowired 字段/方法元数据）
    synchronized (mbd.postProcessingLock) {
        if (!mbd.postProcessed) {
            applyMergedBeanDefinitionPostProcessors(mbd, beanType, beanName);
            mbd.postProcessed = true;
        }
    }
    
    // 【循环依赖关键步骤】将早期引用工厂放入三级缓存
    boolean earlySingletonExposure = (mbd.isSingleton() 
            && this.allowCircularReferences 
            && isSingletonCurrentlyInCreation(beanName));
    if (earlySingletonExposure) {
        addSingletonFactory(beanName, () -> getEarlyBeanReference(beanName, mbd, bean));
        // Lambda 被存入 singletonFactories（三级缓存）
        // getEarlyBeanReference 会触发 SmartInstantiationAwareBPP.getEarlyBeanReference()
        // AOP 代理在此时机决定：如果 Bean 需要代理且已被循环引用，提前返回代理对象
    }
    
    // ②【属性注入】
    Object exposedObject = bean;
    populateBean(beanName, mbd, instanceWrapper);
    
    // ③【初始化】
    exposedObject = initializeBean(beanName, exposedObject, mbd);
    
    // 循环依赖后处理：检查早期引用与最终对象是否一致
    if (earlySingletonExposure) {
        Object earlySingletonReference = getSingleton(beanName, false);  // 从二级缓存取
        if (earlySingletonReference != null) {
            if (exposedObject == bean) {
                // 初始化后对象未被替换（无代理），使用早期引用即可
                exposedObject = earlySingletonReference;
            } else if (!this.allowRawInjectionDespiteWrapping && hasDependentBean(beanName)) {
                // 对象被替换（如 AOP 代理），但已有 Bean 注入了早期引用，报错
                String[] dependentBeans = getDependentBeans(beanName);
                ...
                throw new BeanCurrentlyInCreationException(beanName, ...);
            }
        }
    }
    
    // 注册 DisposableBean（用于容器关闭时的销毁回调）
    registerDisposableBeanIfNecessary(beanName, bean, mbd);
    
    return exposedObject;
}
```

---

### 4.4 实例化：instantiateBean

```java
// createBeanInstance() 决策逻辑（简化）：
protected BeanWrapper createBeanInstance(String beanName, RootBeanDefinition mbd, Object[] args) {
    
    // 1. 如果有 @Bean 工厂方法，走工厂方法实例化
    if (mbd.getFactoryMethodName() != null) {
        return instantiateUsingFactoryMethod(beanName, mbd, args);
    }
    
    // 2. 如果已经确定了构造器（缓存），直接使用
    Constructor<?>[] ctors = determineConstructorsFromBeanPostProcessors(beanClass, beanName);
    if (ctors != null || mbd.getResolvedAutowireMode() == AUTOWIRE_CONSTRUCTOR
            || mbd.hasConstructorArgumentValues() || !ObjectUtils.isEmpty(args)) {
        // 构造器注入（autowireConstructor）
        return autowireConstructor(beanName, mbd, ctors, args);
    }
    
    // 3. 默认无参构造器
    return instantiateBean(beanName, mbd);
}

// instantiateBean：反射调用无参构造
protected BeanWrapper instantiateBean(String beanName, RootBeanDefinition mbd) {
    Object beanInstance;
    if (System.getSecurityManager() != null) {
        beanInstance = AccessController.doPrivileged(
                (PrivilegedAction<Object>) () -> getInstantiationStrategy().instantiate(mbd, beanName, this),
                getAccessControlContext());
    } else {
        // SimpleInstantiationStrategy.instantiate()
        // 如果没有 method overrides → BeanUtils.instantiateClass(ctor)（反射）
        // 如果有 method overrides → CglibSubclassingInstantiationStrategy（CGLIB）
        beanInstance = getInstantiationStrategy().instantiate(mbd, beanName, this);
    }
    BeanWrapper bw = new BeanWrapperImpl(beanInstance);
    initBeanWrapper(bw);
    return bw;
}
```

---

### 4.5 属性注入：populateBean

```java
// AbstractAutowireCapableBeanFactory.populateBean()
protected void populateBean(String beanName, RootBeanDefinition mbd, @Nullable BeanWrapper bw) {
    if (bw == null) {
        if (mbd.hasPropertyValues()) throw new BeanCreationException(...);
        return;
    }
    
    // 1. InstantiationAwareBPP.postProcessAfterInstantiation()
    //    返回 false 可以阻止属性注入（很少用）
    if (!mbd.isSynthetic() && hasInstantiationAwareBeanPostProcessors()) {
        for (InstantiationAwareBeanPostProcessor bp : getBeanPostProcessorCache().instantiationAware) {
            if (!bp.postProcessAfterInstantiation(bw.getWrappedInstance(), beanName)) {
                return;  // 阻止后续注入
            }
        }
    }
    
    PropertyValues pvs = (mbd.hasPropertyValues() ? mbd.getPropertyValues() : null);
    
    // 2. autowireMode 处理（XML 的 autowire="byName/byType"，注解方式不走这里）
    int resolvedAutowireMode = mbd.getResolvedAutowireMode();
    if (resolvedAutowireMode == AUTOWIRE_BY_NAME || resolvedAutowireMode == AUTOWIRE_BY_TYPE) {
        MutablePropertyValues newPvs = new MutablePropertyValues(pvs);
        if (resolvedAutowireMode == AUTOWIRE_BY_NAME) autowireByName(beanName, mbd, bw, newPvs);
        if (resolvedAutowireMode == AUTOWIRE_BY_TYPE) autowireByType(beanName, mbd, bw, newPvs);
        pvs = newPvs;
    }
    
    // 3. ★ InstantiationAwareBPP.postProcessProperties()
    //    AutowiredAnnotationBPP 在此处理 @Autowired / @Value
    //    CommonAnnotationBPP   在此处理 @Resource
    if (hasInstantiationAwareBeanPostProcessors()) {
        for (InstantiationAwareBeanPostProcessor bp : getBeanPostProcessorCache().instantiationAware) {
            PropertyValues pvsToUse = bp.postProcessProperties(pvs, bw.getWrappedInstance(), beanName);
            if (pvsToUse == null) {
                // 兼容旧版 postProcessPropertyValues
                pvsToUse = bp.postProcessPropertyValues(pvs, ..., bw.getWrappedInstance(), beanName);
            }
            pvs = pvsToUse;
        }
    }
    
    // 4. 应用 PropertyValues（XML property 标签，BeanWrapper 反射设置）
    if (pvs != null) {
        applyPropertyValues(beanName, mbd, bw, pvs);
    }
}
```

---

### 4.6 初始化：initializeBean

```java
// AbstractAutowireCapableBeanFactory.initializeBean()
protected Object initializeBean(String beanName, Object bean, @Nullable RootBeanDefinition mbd) {
    
    // 1. Aware 接口回调
    if (System.getSecurityManager() != null) {
        AccessController.doPrivileged((PrivilegedAction<Object>) () -> {
            invokeAwareMethods(beanName, bean);
            return null;
        }, getAccessControlContext());
    } else {
        invokeAwareMethods(beanName, bean);  // BeanNameAware / BeanClassLoaderAware / BeanFactoryAware
    }
    
    // 2. BPP.postProcessBeforeInitialization()
    //    CommonAnnotationBPP 在此执行 @PostConstruct 方法
    //    ApplicationContextAwareProcessor 在此注入 ApplicationContext 等 Aware
    Object wrappedBean = bean;
    if (mbd == null || !mbd.isSynthetic()) {
        wrappedBean = applyBeanPostProcessorsBeforeInitialization(wrappedBean, beanName);
    }
    
    // 3. 执行初始化方法
    try {
        invokeInitMethods(beanName, wrappedBean, mbd);
    } catch (Throwable ex) { ... }
    
    // 4. BPP.postProcessAfterInitialization()
    //    ★ AbstractAutoProxyCreator 在此为 Bean 创建 AOP 代理！
    if (mbd == null || !mbd.isSynthetic()) {
        wrappedBean = applyBeanPostProcessorsAfterInitialization(wrappedBean, beanName);
    }
    
    return wrappedBean;  // 可能是代理对象
}

// invokeInitMethods 执行顺序：
protected void invokeInitMethods(String beanName, Object bean, @Nullable RootBeanDefinition mbd)
        throws Throwable {
    
    // ① InitializingBean.afterPropertiesSet()
    boolean isInitializingBean = (bean instanceof InitializingBean);
    if (isInitializingBean && (mbd == null || !mbd.hasAnyExternallyManagedInitMethod("afterPropertiesSet"))) {
        ((InitializingBean) bean).afterPropertiesSet();
    }
    
    // ② 自定义 init-method / @Bean(initMethod="xxx")
    if (mbd != null && bean.getClass() != NullBean.class) {
        String[] initMethodNames = mbd.getInitMethodNames();
        if (initMethodNames != null) {
            for (String initMethodName : initMethodNames) {
                if (StringUtils.hasLength(initMethodName) 
                        && !(isInitializingBean && "afterPropertiesSet".equals(initMethodName))
                        && !mbd.hasAnyExternallyManagedInitMethod(initMethodName)) {
                    invokeCustomInitMethod(beanName, bean, mbd, initMethodName);
                }
            }
        }
    }
}
```

**初始化方法执行顺序（重要！）**：
1. `@PostConstruct`（由 BPP.postProcessBeforeInitialization 触发）
2. `InitializingBean.afterPropertiesSet()`
3. 自定义 `initMethod`

---

### 4.7 销毁：DisposableBean & @PreDestroy

```java
// 销毁方法执行顺序（与初始化相反）：
// 1. @PreDestroy（由 DestructionAwareBPP 触发）
// 2. DisposableBean.destroy()
// 3. 自定义 destroyMethod

// 注册销毁回调：
// AbstractBeanFactory.registerDisposableBeanIfNecessary()
// → 如果 Bean 有任何销毁回调，包装为 DisposableBeanAdapter，注册到 disposableBeans Map

// 容器关闭时触发：
// AbstractApplicationContext.close() 
//   → doClose()
//     → destroyBeans()
//       → DefaultSingletonBeanRegistry.destroySingletons()
//         → DisposableBeanAdapter.destroy()
//           → CommonAnnotationBPP 处理 @PreDestroy
//           → DisposableBean.destroy()
//           → 自定义 destroyMethod
```

---

## Part 5 @Autowired 注入原理

### 5.1 AutowiredAnnotationBeanPostProcessor

```java
// AutowiredAnnotationBeanPostProcessor 处理 @Autowired 分两步：

// 步骤一：applyMergedBeanDefinitionPostProcessors 时（实例化之后，注入之前）
// 收集注入元数据（字段 + 方法）
@Override
public void postProcessMergedBeanDefinition(RootBeanDefinition beanDefinition, 
        Class<?> beanType, String beanName) {
    // 调用 findAutowiringMetadata()
    // 扫描 beanType 的所有字段和方法，找 @Autowired / @Value / @Inject
    // 结果缓存到 injectionMetadataCache
    InjectionMetadata metadata = findAutowiringMetadata(beanName, beanType, null);
    metadata.checkConfigMembers(beanDefinition);
}

// 步骤二：populateBean 时
@Override
public PropertyValues postProcessProperties(PropertyValues pvs, Object bean, String beanName) {
    InjectionMetadata metadata = findAutowiringMetadata(beanName, bean.getClass(), pvs);
    metadata.inject(bean, beanName, pvs);  // 执行实际注入
    return pvs;
}

// 注入执行（AutowiredFieldElement.inject）：
@Override
protected void inject(Object bean, String beanName, PropertyValues pvs) throws Throwable {
    Field field = (Field) this.member;
    Object value;
    if (this.cached) {
        // 从缓存取（多例 Bean 每次创建都需要注入，所以有缓存）
        value = resolvedCachedArgument(beanName, this.cachedFieldValue);
    } else {
        // DependencyDescriptor 封装字段信息
        DependencyDescriptor desc = new DependencyDescriptor(field, this.required);
        desc.setContainingClass(bean.getClass());
        Set<String> autowiredBeanNames = new LinkedHashSet<>(1);
        TypeConverter typeConverter = beanFactory.getTypeConverter();
        
        // ★ 核心：解析依赖
        value = beanFactory.resolveDependency(desc, beanName, autowiredBeanNames, typeConverter);
        
        // 缓存结果
        synchronized (this) {
            if (!this.cached) {
                if (value != null || this.required) {
                    this.cachedFieldValue = desc;
                    registerDependentBeans(beanName, autowiredBeanNames);
                    if (autowiredBeanNames.size() == 1) {
                        String autowiredBeanName = autowiredBeanNames.iterator().next();
                        if (beanFactory.containsBean(autowiredBeanName) 
                                && beanFactory.isTypeMatch(autowiredBeanName, field.getType())) {
                            this.cachedFieldValue = new ShortcutDependencyDescriptor(desc, autowiredBeanName, field.getType());
                        }
                    }
                } else {
                    this.cachedFieldValue = null;
                }
                this.cached = true;
            }
        }
    }
    if (value != null) {
        ReflectionUtils.makeAccessible(field);
        field.set(bean, value);  // 反射注入
    }
}
```

**resolveDependency 解析流程（按类型注入）**：

```
resolveDependency(desc, beanName, ...)
  │
  ├── 特殊类型处理（Optional / ObjectFactory / Provider / lazy 注入）
  │
  └── doResolveDependency(desc, beanName, ...)
          │
          ├── 1. @Value 处理：resolveEmbeddedValue → 占位符替换 → EL 表达式求值
          │
          ├── 2. 按类型查找候选 Bean：findAutowireCandidates(beanName, type, desc)
          │       ├── getBeanNamesForType(type)         ← 按类型找所有候选
          │       ├── resolvableDependencies 查找（注册的固定对象，如 ApplicationContext）
          │       └── 过滤 @Qualifier / @Primary / generic type matching
          │
          ├── 3. 多个候选时：determineAutowireCandidate()
          │       ├── @Primary Bean 优先
          │       ├── @Priority 值最小优先
          │       └── beanName 匹配字段名（最后兜底）
          │
          └── 4. 触发 getBean(beanName) 实例化目标 Bean（可能触发循环依赖）
```

---

### 5.2 @Qualifier 与按名注入

```java
// @Qualifier 匹配逻辑：
// QualifierAnnotationAutowireCandidateResolver.isAutowireCandidate()

// 1. 候选 BeanDefinition 上有 @Qualifier("xxx")
// 2. 注入点上有 @Qualifier("xxx")
// 3. 两者值相同 → 匹配

// @Resource 与 @Autowired 的区别：
// @Autowired = 按类型（Type），多个时再按名字
// @Resource  = 先按名字（name），再按类型（type）
// @Resource  = 由 CommonAnnotationBPP 处理（JSR-250）
// @Autowired = 由 AutowiredAnnotationBPP 处理（Spring 专有）
```

---

### 5.3 @Value 与 EL 表达式注入

```java
// @Value("${app.name}") → 占位符替换
// 由 EmbeddedValueResolver → PropertySourcesPropertyResolver → Environment 处理

// @Value("#{systemProperties['os.name']}") → SpEL 表达式
// 由 BeanExpressionResolver → SpelExpressionParser 解析
// 在 beanFactory.evaluateBeanDefinitionString() 中触发

// 完整链路：
// postProcessProperties()
//   → resolveDependency()
//     → resolveEmbeddedValue("${app.name}")
//       → PropertySourcesPropertyResolver.resolveRequiredPlaceholders()
//         → 从 Environment 的 PropertySources 链中查找（application.properties / 环境变量 / 系统属性等）
```

---

## Part 6 循环依赖与三级缓存

### 6.1 什么是循环依赖

```java
// 场景：A 注入 B，B 注入 A
@Component
public class A {
    @Autowired
    private B b;
}

@Component
public class B {
    @Autowired
    private A a;
}

// 如果没有三级缓存，实例化流程会死锁：
// 创建 A → 注入 B → 创建 B → 注入 A → 创建 A → ... 无限递归
```

---

### 6.2 三级缓存数据结构

```java
// DefaultSingletonBeanRegistry 中的三个 Map：

/** 一级缓存：完全初始化好的单例 Bean（可直接使用） */
private final Map<String, Object> singletonObjects = new ConcurrentHashMap<>(256);

/** 二级缓存：早期暴露的 Bean 引用（已实例化但未初始化，或已是代理对象） */
private final Map<String, Object> earlySingletonObjects = new ConcurrentHashMap<>(16);

/** 三级缓存：ObjectFactory，调用时返回早期引用（可能触发 AOP 代理创建） */
private final Map<String, ObjectFactory<?>> singletonFactories = new HashMap<>(16);

/** 正在创建中的 Bean 名称集合（用于检测循环依赖） */
private final Set<String> singletonsCurrentlyInCreation = Collections.newSetFromMap(new ConcurrentHashMap<>(16));
```

---

### 6.3 getSingleton — 缓存查找

```java
// DefaultSingletonBeanRegistry.getSingleton(beanName, allowEarlyReference)
@Nullable
protected Object getSingleton(String beanName, boolean allowEarlyReference) {
    // 快速路径：先查一级缓存（大多数情况，无锁）
    Object singletonObject = this.singletonObjects.get(beanName);
    
    if (singletonObject == null && isSingletonCurrentlyInCreation(beanName)) {
        // Bean 正在创建中（存在循环依赖可能），查二级缓存
        singletonObject = this.earlySingletonObjects.get(beanName);
        
        if (singletonObject == null && allowEarlyReference) {
            synchronized (this.singletonObjects) {  // 加锁防并发
                // 双重检查
                singletonObject = this.singletonObjects.get(beanName);
                if (singletonObject == null) {
                    singletonObject = this.earlySingletonObjects.get(beanName);
                    if (singletonObject == null) {
                        // 查三级缓存，调用 ObjectFactory.getObject()
                        ObjectFactory<?> singletonFactory = this.singletonFactories.get(beanName);
                        if (singletonFactory != null) {
                            singletonObject = singletonFactory.getObject();
                            // 升级到二级缓存，删除三级缓存
                            this.earlySingletonObjects.put(beanName, singletonObject);
                            this.singletonFactories.remove(beanName);
                        }
                    }
                }
            }
        }
    }
    return singletonObject;
}
```

---

### 6.4 三级缓存工作流程详解

以 A → B → A 循环依赖为例，完整时序：

```
[线程执行，以创建 A 为起点]

Step 1: getBean("A")
  └── singletonsCurrentlyInCreation.add("A")      // 标记 A 正在创建
  └── createBeanInstance(A)                        // 反射创建 A 的原始对象（a_raw）
  └── addSingletonFactory("A", () -> getEarlyBeanReference("A", mbd, a_raw))
                                                   // ★ A 的工厂函数放入三级缓存
  └── populateBean(A) → 注入 B → getBean("B")

Step 2: getBean("B")  (在 A 的属性注入过程中触发)
  └── singletonsCurrentlyInCreation.add("B")
  └── createBeanInstance(B)                        // 反射创建 B 的原始对象（b_raw）
  └── addSingletonFactory("B", () -> getEarlyBeanReference("B", mbd, b_raw))
                                                   // B 的工厂函数放入三级缓存
  └── populateBean(B) → 注入 A → getBean("A")

Step 3: getBean("A")  (在 B 的属性注入过程中触发)
  └── getSingleton("A", true)
        ├── 一级缓存：无（A 还没完成初始化）
        ├── 二级缓存：无（A 还没被升级）
        └── 三级缓存：有！调用 ObjectFactory.getObject()
              └── getEarlyBeanReference("A", mbd, a_raw)
                    └── SmartInstantiationAwareBPP.getEarlyBeanReference(a_raw, "A")
                          └── AbstractAutoProxyCreator:
                                如果 A 需要 AOP 代理 → 此时提前创建代理 a_proxy
                                否则 → 直接返回 a_raw
              └── earlySingletonObjects.put("A", a_early)  // 升到二级缓存
              └── singletonFactories.remove("A")            // 从三级缓存移除
  └── 返回 a_early 给 B（B.a = a_early）

Step 4: B 完成属性注入
  └── initializeBean(B) → B 完全初始化
  └── addSingleton("B", b)                        // B 移入一级缓存
  └── 返回 b 给 A（A.b = b）

Step 5: A 完成属性注入（注入了 b）
  └── initializeBean(A)
        └── BPP.postProcessAfterInitialization()
              └── AbstractAutoProxyCreator:
                    ★ 检查 earlyProxyReferences —— 发现 A 已在 Step 3 创建了代理
                    → 直接返回 a_early（已是代理），不重复创建代理
  └── exposedObject = a_early（而非 a_raw）
  └── addSingleton("A", a_early)                  // A 移入一级缓存

[最终状态]
一级缓存: {"A": a_proxy/a_raw, "B": b}
二级缓存: {}  (清空)
三级缓存: {}  (清空)
```

---

### 6.5 为什么需要第三级缓存（singletonFactories）

**核心问题**：为什么不直接用二级缓存（提前创建好代理放进去）？

```java
// 原因：
// 1. 如果没有循环依赖，Spring 不希望提前创建 AOP 代理
//    正常流程：代理应该在 initializeBean → postProcessAfterInitialization 时创建
//    如果提前创建，违背了 AOP 的设计意图，且打乱了初始化顺序

// 2. 三级缓存的 ObjectFactory（Lambda）是懒执行的：
//    - 只有真的被循环依赖引用时，才会触发 getObject()
//    - 没有循环依赖的 Bean，三级缓存的 Lambda 永远不会被调用

// 3. 如果用二级缓存提前暴露，意味着：
//    ✗ 必须在实例化之后立刻为所有 Bean 创建代理（即使不需要）
//    ✗ 打乱了 BPP 的执行时序
//    ✗ 某些 BPP 需要完整的初始化才能决定是否代理

// 三级缓存的精妙之处：
// ✓ 正常情况（无循环依赖）：ObjectFactory 不被调用，代理在正常时机创建
// ✓ 循环依赖情况：ObjectFactory 被调用，提前创建代理，保证引用一致性

// 一句话：第三级缓存是为了延迟代理创建时机，同时又能在循环依赖时提前暴露引用
```

---

### 6.6 哪些循环依赖 Spring 解决不了

```java
// ❌ 构造器循环依赖（无法解决）
@Component
public class A {
    public A(B b) { ... }  // 构造器注入 B
}
@Component
public class B {
    public B(A a) { ... }  // 构造器注入 A
}
// 原因：实例化时就需要对方，但三级缓存在实例化之后才放入

// ❌ 多例（prototype）Bean 的循环依赖（无法解决）
// 原因：prototype Bean 不放入缓存，每次都新建，Spring 检测到后抛出 BeanCurrentlyInCreationException

// ❌ 开启了 spring.main.allow-circular-references=false（Spring Boot 2.6+ 默认禁用）
// Spring Boot 2.6 开始默认关闭循环依赖，需要显式开启

// ✅ 可以解决的：
// 单例（singleton）Bean 的 setter/字段注入循环依赖

// 解决构造器循环依赖的方法：
// 1. @Lazy：@Autowired @Lazy A a → 注入代理，延迟初始化真正的 A
// 2. 重构代码，消除循环依赖（最推荐）
// 3. @PostConstruct + setter 注入
```

---

## Part 7 FactoryBean vs BeanFactory

### 7.1 FactoryBean 接口源码

```java
// FactoryBean<T> — 工厂模式的 Bean
public interface FactoryBean<T> {
    
    // 返回工厂生产的对象（Spring 缓存这个对象）
    @Nullable
    T getObject() throws Exception;
    
    // 返回工厂生产的对象的类型（用于按类型注入）
    @Nullable
    Class<?> getObjectType();
    
    // 是否单例（默认 true）
    default boolean isSingleton() {
        return true;
    }
}

// 关键规则：
// getBean("myBean")    → 返回 FactoryBean.getObject() 的结果
// getBean("&myBean")   → 返回 FactoryBean 本身（用 FACTORY_BEAN_PREFIX = "&" 前缀）

// Spring 如何判断 getObject() 的缓存：
// AbstractBeanFactory.getObjectForBeanInstance()
// → 单例 + 非 SmartFactoryBean(isPrototype=false) → 放入 factoryBeanObjectCache
// → 多次 getBean 返回同一个 getObject() 结果
```

---

### 7.2 getBean("&myBean") 获取原始 FactoryBean

```java
// 使用示例：
ApplicationContext ctx = ...;
MyFactoryBean factory = (MyFactoryBean) ctx.getBean("&myFactoryBean");
MyProduct product = (MyProduct) ctx.getBean("myFactoryBean");

// 源码（AbstractBeanFactory.doGetBean）
protected <T> T doGetBean(String name, ...) {
    // beanName 处理：去掉 "&" 前缀，但记录是否是 FactoryBean 引用
    final String beanName = transformedBeanName(name);
    boolean isFactoryDereference = BeanFactoryUtils.isFactoryDereference(name);  // name 以 "&" 开头
    
    Object beanInstance = getSingleton(beanName);
    
    if (beanInstance != null) {
        // 处理 FactoryBean 解引用
        return (T) getObjectForBeanInstance(beanInstance, name, beanName, null);
    }
    ...
}
```

---

### 7.3 典型应用：MyBatis MapperFactoryBean

```java
// MyBatis-Spring 的 MapperFactoryBean 就是 FactoryBean 的典型应用
public class MapperFactoryBean<T> extends SqlSessionDaoSupport implements FactoryBean<T> {
    private Class<T> mapperInterface;  // 如 UserMapper.class
    
    @Override
    public T getObject() throws Exception {
        // 通过 SqlSession 创建 Mapper 代理
        return getSqlSession().getMapper(this.mapperInterface);
    }
    
    @Override
    public Class<T> getObjectType() {
        return this.mapperInterface;
    }
    
    @Override
    public boolean isSingleton() {
        return true;
    }
}

// 当你 @Autowired UserMapper userMapper 时：
// Spring 按类型 UserMapper.class 查找 Bean
// 找到了 MapperFactoryBean（其 getObjectType() 返回 UserMapper）
// 调用 getObject() 返回真正的 Mapper 代理对象注入
```

---

## Part 8 BeanPostProcessor 全家族

### 8.1 BeanPostProcessor 执行位置

```java
// BeanPostProcessor — 最基础的扩展接口
public interface BeanPostProcessor {
    // 在初始化方法（afterPropertiesSet/initMethod）之前调用
    // 时机：Aware 回调之后，@PostConstruct 等由具体 BPP 决定
    @Nullable
    default Object postProcessBeforeInitialization(Object bean, String beanName) throws BeansException {
        return bean;
    }
    
    // 在初始化方法之后调用
    // ★ AOP 代理在此创建（AbstractAutoProxyCreator）
    @Nullable
    default Object postProcessAfterInitialization(Object bean, String beanName) throws BeansException {
        return bean;
    }
}
```

---

### 8.2 InstantiationAwareBeanPostProcessor

```java
// extends BeanPostProcessor，额外关注实例化阶段
public interface InstantiationAwareBeanPostProcessor extends BeanPostProcessor {
    
    // createBean 开始时调用，返回非 null 则短路整个实例化流程
    // 用途：AbstractAutoProxyCreator 极少情况下在此返回代理（如 TargetSourceCreator）
    @Nullable
    default Object postProcessBeforeInstantiation(Class<?> beanClass, String beanName) throws BeansException {
        return null;
    }
    
    // 实例化之后，属性注入之前调用
    // 返回 false 阻止属性注入
    default boolean postProcessAfterInstantiation(Object bean, String beanName) throws BeansException {
        return true;
    }
    
    // 属性注入时调用（取代 postProcessPropertyValues）
    // ★ AutowiredAnnotationBPP 在此执行 @Autowired 注入
    @Nullable
    default PropertyValues postProcessProperties(PropertyValues pvs, Object bean, String beanName)
            throws BeansException {
        return pvs;
    }
}
```

---

### 8.3 SmartInstantiationAwareBeanPostProcessor

```java
// extends InstantiationAwareBPP，额外关注循环依赖和构造器推断
public interface SmartInstantiationAwareBeanPostProcessor extends InstantiationAwareBeanPostProcessor {
    
    // 预测 Bean 的最终类型（代理后的类型）
    @Nullable
    default Class<?> predictBeanType(Class<?> beanClass, String beanName) throws BeansException {
        return null;
    }
    
    // 推断构造器（多构造器时决定用哪个）
    @Nullable
    default Constructor<?>[] determineCandidateConstructors(Class<?> beanClass, String beanName)
            throws BeansException {
        return null;
    }
    
    // ★ 循环依赖时返回早期引用（AOP 代理在此提前创建）
    default Object getEarlyBeanReference(Object bean, String beanName) throws BeansException {
        return bean;  // 默认返回原对象
    }
}

// AbstractAutoProxyCreator.getEarlyBeanReference()：
@Override
public Object getEarlyBeanReference(Object bean, String beanName) {
    Object cacheKey = getCacheKey(bean.getClass(), beanName);
    this.earlyProxyReferences.put(cacheKey, bean);  // 记录已提前代理
    return wrapIfNecessary(bean, beanName, cacheKey);  // 创建代理
}
```

---

### 8.4 DestructionAwareBeanPostProcessor

```java
// 关注销毁阶段
public interface DestructionAwareBeanPostProcessor extends BeanPostProcessor {
    
    // 容器关闭时，在 DisposableBean.destroy() 之前调用
    // CommonAnnotationBPP 在此执行 @PreDestroy 方法
    void postProcessBeforeDestruction(Object bean, String beanName) throws BeansException;
    
    // 是否需要对此 Bean 执行销毁回调
    default boolean requiresDestruction(Object bean) {
        return true;
    }
}
```

---

## Part 9 Spring 整体流程串联

### 9.1 从 new ApplicationContext 到第一个 Bean 可用

```
new AnnotationConfigApplicationContext(AppConfig.class)
│
├── this()
│   └── new AnnotatedBeanDefinitionReader(this)
│       └── AnnotationConfigUtils.registerAnnotationConfigProcessors()
│           └── 注册 6 个基础 BeanDefinition（ConfigurationClassPostProcessor 等）
│
├── register(AppConfig.class)
│   └── AnnotatedBeanDefinitionReader.register()
│       └── doRegisterBean(AppConfig.class)
│           └── AppConfig 的 BeanDefinition 注册到 DefaultListableBeanFactory
│
└── refresh()
    │
    ├── [Step 5] invokeBeanFactoryPostProcessors()
    │   └── ConfigurationClassPostProcessor.postProcessBeanDefinitionRegistry()
    │       └── 解析 AppConfig：
    │           ├── @ComponentScan("com.example") → 扫描，注册 UserService/OrderService/...
    │           ├── @Bean methods → 注册 DataSource/TransactionManager/...
    │           └── @Import → 导入其他配置类
    │
    ├── [Step 6] registerBeanPostProcessors()
    │   └── 实例化并注册：AutowiredAnnotationBPP / CommonAnnotationBPP / AOP相关BPP
    │
    └── [Step 11] finishBeanFactoryInitialization()
        └── preInstantiateSingletons()
            └── for beanName in beanDefinitionNames:
                └── getBean(beanName)
                    └── doGetBean(beanName)
                        └── getSingleton(beanName, singletonFactory)
                            └── createBean(beanName, mbd)
                                └── doCreateBean(beanName, mbd)
                                    ├── createBeanInstance()      // 反射创建
                                    ├── addSingletonFactory()     // 放入三级缓存
                                    ├── populateBean()            // @Autowired 注入
                                    └── initializeBean()
                                        ├── invokeAwareMethods()  // Aware 回调
                                        ├── postProcessBeforeInit // @PostConstruct
                                        ├── afterPropertiesSet()  // InitializingBean
                                        └── postProcessAfterInit  // AOP 代理创建
```

---

### 9.2 关键调用栈

```
// 以 UserService 创建为例（假设有 @Autowired private OrderService orderService）：

getBean("userService")
  AbstractBeanFactory.doGetBean("userService")
    DefaultSingletonBeanRegistry.getSingleton("userService", singletonFactory)
      AbstractAutowireCapableBeanFactory.createBean("userService", mbd, null)
        AbstractAutowireCapableBeanFactory.doCreateBean("userService", mbd, null)
          // 1. 实例化
          AbstractAutowireCapableBeanFactory.createBeanInstance()
            SimpleInstantiationStrategy.instantiate()
              BeanUtils.instantiateClass(UserService.class.getDeclaredConstructor())
                // → UserService 对象创建完成（字段全为 null）
          
          // 2. 放入三级缓存
          addSingletonFactory("userService", () -> getEarlyBeanReference(...))
          
          // 3. 收集注入元数据
          AutowiredAnnotationBPP.postProcessMergedBeanDefinition()
            findAutowiringMetadata("userService", UserService.class)
              // 扫描 orderService 字段，缓存 InjectionMetadata
          
          // 4. 属性注入
          AbstractAutowireCapableBeanFactory.populateBean()
            AutowiredAnnotationBPP.postProcessProperties()
              InjectionMetadata.inject()
                AutowiredFieldElement.inject()
                  DefaultListableBeanFactory.resolveDependency(orderService 字段描述符)
                    doResolveDependency()
                      findAutowireCandidates("userService", OrderService.class, desc)
                        getBeanNamesForType(OrderService.class)  → ["orderService"]
                      getBean("orderService")  // 触发 OrderService 的完整生命周期
                        // ... （递归同样的流程）
                  field.set(userServiceInstance, orderServiceInstance)
          
          // 5. 初始化
          AbstractAutowireCapableBeanFactory.initializeBean()
            invokeAwareMethods()          // 如实现了 BeanNameAware
            postProcessBeforeInit()       // CommonAnnotationBPP → @PostConstruct
            afterPropertiesSet()          // 如实现了 InitializingBean
            postProcessAfterInit()        // AbstractAutoProxyCreator → AOP 代理（如需要）
          
          // 6. 放入一级缓存
          DefaultSingletonBeanRegistry.addSingleton("userService", userServiceBean)
```

---

### 9.3 AOP 代理在哪里介入（预告）

```java
// Spring AOP 入口：AnnotationAwareAspectJAutoProxyCreator
// 继承链：
// AnnotationAwareAspectJAutoProxyCreator
//   └── AspectJAwareAdvisorAutoProxyCreator
//         └── AbstractAdvisorAutoProxyCreator
//               └── AbstractAutoProxyCreator
//                     └── SmartInstantiationAwareBeanPostProcessor ← 实现了 BPP

// 介入时机：
// 1. 正常情况（无循环依赖）：
//    initializeBean → postProcessAfterInitialization → wrapIfNecessary()
//      → 找到匹配的 Advisor → 创建 JDK 动态代理 or CGLIB 代理 → 返回代理对象

// 2. 循环依赖情况：
//    getEarlyBeanReference → wrapIfNecessary()
//      → 提前创建代理 → 存入 earlyProxyReferences
//    initializeBean → postProcessAfterInitialization
//      → 发现 earlyProxyReferences 中已有记录 → 直接返回已有代理，不重复创建

// AOP 代理详细原理见《Spring AOP 源码深度解析》文档（后续篇）
```

---

## Part 10 高频面试题 12 道

**Q1：Spring IoC 容器启动的核心流程是什么？**

> **A**：核心是 `AbstractApplicationContext.refresh()` 的十二步。最关键的是：
> - **Step 5** `invokeBeanFactoryPostProcessors`：`ConfigurationClassPostProcessor` 解析 `@Configuration`、`@ComponentScan`、`@Bean`，将所有 BeanDefinition 注册到 BeanFactory
> - **Step 6** `registerBeanPostProcessors`：注册所有 BPP（包括处理 `@Autowired` 的 `AutowiredAnnotationBPP`）
> - **Step 11** `finishBeanFactoryInitialization`：触发所有非懒加载单例 Bean 的完整生命周期

---

**Q2：Spring Bean 的生命周期？**

> **A**：完整顺序：
> 1. **实例化**：反射调用构造方法
> 2. **三级缓存注册**：将 ObjectFactory 放入 `singletonFactories`（为循环依赖做准备）
> 3. **属性注入**：`populateBean` → `AutowiredAnnotationBPP.postProcessProperties`
> 4. **Aware 回调**：`BeanNameAware` / `BeanClassLoaderAware` / `BeanFactoryAware`
> 5. **BPP.before**：`CommonAnnotationBPP` 执行 `@PostConstruct`
> 6. **InitializingBean.afterPropertiesSet()**
> 7. **自定义 initMethod**
> 8. **BPP.after**：AOP 代理在此创建
> 9. **使用中...**
> 10. **容器关闭时**：`@PreDestroy` → `DisposableBean.destroy()` → 自定义 destroyMethod

---

**Q3：@PostConstruct、afterPropertiesSet、initMethod 执行顺序？**

> **A**：`@PostConstruct` → `afterPropertiesSet` → `initMethod`
> 对应销毁：`@PreDestroy` → `destroy()` → `destroyMethod`

---

**Q4：Spring 如何解决循环依赖？为什么需要三级缓存而不是两级？**

> **A**：
> - 一级缓存（`singletonObjects`）：完全初始化好的 Bean
> - 二级缓存（`earlySingletonObjects`）：早期引用（实例化但未初始化，可能已是代理）
> - 三级缓存（`singletonFactories`）：ObjectFactory Lambda，懒执行，按需创建代理
> 
> **为什么需要三级**：如果只有二级缓存，必须在实例化后立刻为每个 Bean 创建 AOP 代理（即使没有循环依赖），违背了代理的设计意图，且打乱了 BPP 的执行时序。三级缓存用 Lambda 做延迟处理：只有真的发生循环依赖，才触发提前代理创建。

---

**Q5：哪些循环依赖 Spring 解决不了？**

> **A**：
> 1. **构造器注入的循环依赖**：实例化时就需要对方，但三级缓存在实例化之后才建立
> 2. **prototype 作用域的循环依赖**：prototype Bean 不缓存，Spring 检测后直接报错
> 3. **Spring Boot 2.6+ 默认禁用**：需显式设置 `spring.main.allow-circular-references=true`

---

**Q6：BeanFactory 和 ApplicationContext 的区别？**

> **A**：
> - `BeanFactory`：基础 IoC 容器，只提供 `getBean` 等基础功能，**懒加载**（调用 getBean 时才初始化）
> - `ApplicationContext`：企业级容器，**聚合** BeanFactory，额外提供事件发布、国际化、资源加载，**启动时预实例化**所有单例 Bean
> - `ApplicationContext` 并不继承 `BeanFactory`，而是通过 `getBeanFactory()` 持有一个 `DefaultListableBeanFactory`

---

**Q7：BeanFactoryPostProcessor 和 BeanPostProcessor 的区别？**

> **A**：
> - `BFPP`：作用于 **BeanDefinition 阶段**，在 Bean 实例化之前执行，可以修改或增加 BeanDefinition（如 `ConfigurationClassPostProcessor` 扫描注解，`PropertyPlaceholderConfigurer` 替换占位符）
> - `BPP`：作用于 **Bean 实例阶段**，在 Bean 实例化之后、初始化前后各调用一次，可以修改或替换 Bean 实例（如 `AutowiredAnnotationBPP` 注入依赖，`AbstractAutoProxyCreator` 创建代理）

---

**Q8：@Autowired 按类型还是按名字注入？**

> **A**：先按**类型**（`byType`）找所有候选 Bean，如果只有一个直接注入。多个候选时：
> 1. 有 `@Primary` 的优先
> 2. 有 `@Priority` 的按值排序
> 3. 最后按**字段名/参数名**匹配 Bean 名
> 
> 可以用 `@Qualifier("beanName")` 显式指定按名注入。`@Resource` 默认按名注入（JSR-250）。

---

**Q9：FactoryBean 是什么？和 BeanFactory 有什么区别？**

> **A**：
> - `BeanFactory`：IoC 容器接口，管理所有 Bean 的创建和获取
> - `FactoryBean<T>`：特殊的 Bean，本身是工厂，`getBean("myBean")` 返回的是 `getObject()` 的结果，不是 FactoryBean 本身
> - 获取 FactoryBean 本身：`getBean("&myBean")`
> - 典型应用：MyBatis 的 `MapperFactoryBean`，通过 `getObject()` 返回 Mapper 代理对象

---

**Q10：@Configuration 和 @Component 的区别？**

> **A**：
> - `@Component` 标注的配置类是 **"lite" 模式**：`@Bean` 方法没有 CGLIB 增强，方法间相互调用会 `new` 新对象（每次调用 `@Bean` 方法都是新实例）
> - `@Configuration(proxyBeanMethods=true)`（默认）是 **"full" 模式**：类被 CGLIB 增强，方法间调用被拦截为 `beanFactory.getBean()`，保证单例
> - `@Configuration(proxyBeanMethods=false)` 类似 `@Component`，性能更好，适合 `@Bean` 方法没有相互调用的场景

---

**Q11：Spring 的 Bean 默认是线程安全的吗？**

> **A**：不一定。Spring 默认 Bean 作用域是 `singleton`，多线程共享同一个实例。如果 Bean 有**可变的成员变量**，就存在线程安全问题。Spring 不会自动保证线程安全，需要开发者自行处理（同步、使用无状态 Bean、或改为 `prototype` 作用域）。

---

**Q12：如何控制 Bean 的初始化顺序？**

> **A**：
> 1. `@DependsOn("beanA")`：显式声明依赖，保证 beanA 先初始化
> 2. `@Order` / `PriorityOrdered` / `Ordered`：控制 `BPP` 和 `BFPP` 的执行顺序，不直接控制普通 Bean
> 3. 构造器 / 字段注入：被注入的 Bean 自然先初始化
> 4. `SmartInitializingSingleton.afterSingletonsInstantiated()`：所有单例初始化完成后回调
> 5. `ApplicationListener<ContextRefreshedEvent>`：容器刷新完毕后触发（所有 Bean 已就绪）

---

## 附录 A Spring IoC 核心类速查

| 类/接口 | 所在包 | 职责 |
|---------|--------|------|
| `BeanFactory` | `beans.factory` | IoC 容器基础接口 |
| `DefaultListableBeanFactory` | `beans.factory.support` | 最强大的 BeanFactory 实现，支持枚举、按类型查找 |
| `AbstractApplicationContext` | `context.support` | ApplicationContext 模板类，定义 `refresh()` 骨架 |
| `AnnotationConfigApplicationContext` | `context.annotation` | 注解驱动的 ApplicationContext |
| `BeanDefinition` | `beans.factory.config` | Bean 元数据接口 |
| `RootBeanDefinition` | `beans.factory.support` | 合并后的 BeanDefinition（继承关系已解析） |
| `ConfigurationClassPostProcessor` | `context.annotation` | 解析 @Configuration/@ComponentScan/@Bean |
| `AutowiredAnnotationBeanPostProcessor` | `beans.factory.annotation` | 处理 @Autowired/@Value/@Inject |
| `CommonAnnotationBeanPostProcessor` | `context.annotation` | 处理 @Resource/@PostConstruct/@PreDestroy |
| `AbstractAutoProxyCreator` | `aop.framework.autoproxy` | AOP 代理创建的核心 BPP |
| `DefaultSingletonBeanRegistry` | `beans.factory.support` | 三级缓存所在类 |
| `AbstractAutowireCapableBeanFactory` | `beans.factory.support` | Bean 实例化/注入/初始化的核心实现 |

---

## 附录 B 生命周期各扩展点汇总表

| 时机 | 扩展点 | 常见用途 |
|------|--------|---------|
| BeanDefinition 注册后 | `BeanDefinitionRegistryPostProcessor` | 动态注册新的 BeanDefinition（如 MyBatis Mapper 扫描） |
| 所有 BD 注册完成后 | `BeanFactoryPostProcessor` | 修改 BeanDefinition（如替换占位符、修改属性） |
| Bean 实例化之前 | `IBP.postProcessBeforeInstantiation` | 返回代理对象，短路实例化（极少用） |
| Bean 实例化之后 | `IBP.postProcessAfterInstantiation` | 阻止属性注入（极少用） |
| 属性注入时 | `IBP.postProcessProperties` | **@Autowired / @Resource 注入（核心）** |
| 收集注入元数据 | `MergedBeanDefinitionPostProcessor` | 缓存注入点元数据 |
| 初始化之前 | `BPP.postProcessBeforeInitialization` | **@PostConstruct、ApplicationContextAware 等** |
| 初始化（主动）| `InitializingBean.afterPropertiesSet` | Bean 自己的初始化逻辑 |
| 初始化（主动）| 自定义 `initMethod` | Bean 自己的初始化逻辑（XML / @Bean(initMethod)） |
| 初始化之后 | `BPP.postProcessAfterInitialization` | **AOP 代理创建（AbstractAutoProxyCreator）** |
| 循环依赖早期引用 | `SIABPP.getEarlyBeanReference` | 循环依赖时提前创建 AOP 代理 |
| 所有单例初始化完 | `SmartInitializingSingleton.afterSingletonsInstantiated` | 容器启动完成后的初始化逻辑 |
| 容器刷新完毕 | `ApplicationListener<ContextRefreshedEvent>` | 容器就绪后的启动任务 |
| 容器关闭时 | `DestructionAwareBPP.postProcessBeforeDestruction` | **@PreDestroy** |
| 容器关闭时 | `DisposableBean.destroy` | Bean 自己的销毁逻辑 |
| 容器关闭时 | 自定义 `destroyMethod` | Bean 自己的销毁逻辑（XML / @Bean(destroyMethod)） |

---

*文档版本：Spring Framework 5.3.x | 整理时间：2026-06*  
*上一篇：Java 与 Tomcat 类加载机制源码深度解析*  
*下一篇：Spring AOP 源码深度解析（Advisor/Pointcut/Advice/动态代理）*
