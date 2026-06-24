# Spring AOP 源码深度解析（JDK Proxy vs CGLIB + @Transactional）

> 本文档基于 Spring Framework 5.3.x 源码，系统解析 Spring AOP 的代理创建机制、Advice 链执行流程、AspectJ 注解处理、以及 @Transactional 声明式事务的完整源码实现。
>
> 阅读建议：先通读第一部分建立整体认知，再按顺序深入各部分源码。第九部分 @Transactional 是前八部分知识的综合应用，建议在理解代理机制后再读。

---

## 目录

- [第一部分：AOP 核心概念与整体架构](#第一部分aop-核心概念与整体架构)
- [第二部分：JDK 动态代理源码深度解析](#第二部分jdk-动态代理源码深度解析)
- [第三部分：CGLIB 代理源码深度解析](#第三部分cglib-代理源码深度解析)
- [第四部分：Spring AOP 代理创建流程](#第四部分spring-aop-代理创建流程)
- [第五部分：Advice 链构建与执行](#第五部分advice-链构建与执行)
- [第六部分：Pointcut/Advisor/Advice 体系](#第六部分pointcutadvisoradvice-体系)
- [第七部分：@EnableAspectJAutoProxy 与 BeanPostProcessor](#第七部分enableaspectjautoproxy-与-beanpostprocessor)
- [第八部分：AspectJ 注解处理](#第八部分aspectj-注解处理)
- [第九部分：@Transactional 事务源码深度解析](#第九部分transactional-事务源码深度解析)
- [第十部分：面试高频考点与总结](#第十部分面试高频考点与总结)
- [附录 A：Spring AOP 核心接口索引表](#附录-aspring-aop-核心接口索引表)
- [附录 B：@Transactional 事务传播行为速查表](#附录-btransactional-事务传播行为速查表)

---

## 第一部分：AOP 核心概念与整体架构

### 1.1 AOP 术语详解

| 术语 | 英文 | 含义 | Spring 中的对应 |
|------|------|------|----------------|
| 连接点 | JoinPoint | 程序执行中的某个点（方法调用、字段访问、异常抛出等） | Spring AOP 仅支持方法级别连接点 |
| 切点 | Pointcut | 匹配 JoinPoint 的表达式 | `Pointcut` 接口 |
| 通知/增强 | Advice | 在 JoinPoint 上执行的动作 | `Advice` 接口 |
| 切面 | Aspect | Pointcut + Advice 的模块化 | `@Aspect` 注解标记的类 |
| 织入 | Weaving | 将 Aspect 应用到目标对象的过程 | 运行时通过动态代理织入 |
| 目标对象 | Target Object | 被代理的原始对象 | Bean 实例 |
| 代理对象 | Proxy Object | 织入 Advice 后创建的对象 | JDK Proxy / CGLIB Proxy |
| 引介 | Introduction | 给类增加新的接口和方法 | `IntroductionAdvisor` |

**核心关系图：**

```
┌─────────────────────────────────────────────────────┐
│                    Aspect（切面）                      │
│  ┌─────────────────────┐  ┌──────────────────────┐  │
│  │   Pointcut（切点）    │  │   Advice（通知）       │  │
│  │  "匹配哪些方法"       │  │  "做什么增强"          │  │
│  │  execution(*        │  │  @Before / @After     │  │
│  │  com.foo.*.*(..))   │  │  @Around / ...        │  │
│  └─────────────────────┘  └──────────────────────┘  │
│           │                          │               │
│           └──────────┬───────────────┘               │
│                      ▼                               │
│              Advisor（顾问）                          │
│         Pointcut + Advice 的封装                      │
└─────────────────────────────────────────────────────┘
                      │
                      ▼ 织入（Weaving）
┌─────────────────────────────────────────────────────┐
│              Target Object（目标对象）                  │
│                  被代理的 Bean                         │
└─────────────────────────────────────────────────────┘
                      │
                      ▼ 动态代理
┌─────────────────────────────────────────────────────┐
│              Proxy Object（代理对象）                  │
│    ┌─────────────────────────────────────────┐       │
│  │  方法调用 → Advice链执行 → 目标方法 → 返回  │       │
│  └─────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────┘
```

### 1.2 Spring AOP vs AspectJ

| 对比维度 | Spring AOP | AspectJ |
|---------|-----------|---------|
| 织入时机 | 运行时（动态代理） | 编译时 / 加载时（字节码织入） |
| 实现方式 | JDK Proxy / CGLIB | ajc 编译器 / Java Agent |
| JoinPoint | 仅方法执行 | 方法调用、字段访问、构造器、静态初始化等 |
| 性能 | 每次调用经过代理，有开销 | 编译期织入，运行时无额外开销 |
| 切点表达式 | 支持 AspectJ 切点表达式子集 | 完整的 AspectJ 切点语法 |
| 适用场景 | 企业级应用（事务、日志、安全等） | 需要细粒度 AOP 的场景 |

**关键区别：** Spring AOP 借用了 AspectJ 的注解语法（`@Aspect`、`@Pointcut` 等）和切点表达式语言，但底层实现完全不同——Spring AOP 是运行时动态代理，AspectJ 是编译时/加载时字节码织入。

### 1.3 Spring AOP 整体架构

```
                        Spring AOP 架构全景
 ┌──────────────────────────────────────────────────────────────┐
 │                        用户层                                  │
 │   @Aspect / @Before / @Around / @Transactional 等             │
 └──────────────────────┬───────────────────────────────────────┘
                        │ 解析
                        ▼
 ┌──────────────────────────────────────────────────────────────┐
 │                    切面解析层                                   │
 │  AnnotationAwareAspectJAutoProxyCreator (BeanPostProcessor)   │
 │  ┌──────────────────────────────────────────────────────┐    │
 │  │  AspectJAdvisorFactory                                │    │
 │  │  → 解析 @Aspect 类，将每个 Advice 方法包装成 Advisor    │    │
 │  └──────────────────────────────────────────────────────┘    │
 │  ┌──────────────────────────────────────────────────────┐    │
 │  │  BeanFactoryAspectJAdvisorsBuilder                    │    │
 │  │  → 扫描容器中所有 @Aspect，构建 Advisor 列表            │    │
 │  └──────────────────────────────────────────────────────┘    │
 └──────────────────────┬───────────────────────────────────────┘
                        │ 为每个 Bean 创建代理
                        ▼
 ┌──────────────────────────────────────────────────────────────┐
 │                    代理创建层                                   │
 │  ┌──────────────────────────────────────────────────────┐    │
 │  │  AopProxyFactory                                      │    │
 │  │  → 决定使用 JDK Proxy 还是 CGLIB                      │    │
 │  └──────────────────────┬───────────────────────────────┘    │
 │                         │                                     │
 │           ┌─────────────┴─────────────┐                      │
 │           ▼                           ▼                      │
 │  ┌──────────────┐            ┌───────────────┐              │
 │  │ JdkDynamic   │            │   CglibAop    │              │
 │  │ AopProxy     │            │   Proxy       │              │
 │  │ (JDK Proxy)  │            │   (CGLIB)     │              │
 │  └──────────────┘            └───────────────┘              │
 └──────────────────────┬───────────────────────────────────────┘
                        │ 方法调用时执行
                        ▼
 ┌──────────────────────────────────────────────────────────────┐
 │                    拦截执行层                                   │
 │  ┌──────────────────────────────────────────────────────┐    │
 │  │  ReflectiveMethodInvocation / CglibMethodInvocation  │    │
 │  │  → 责任链模式，依次执行 Advice 链                      │    │
 │  └──────────────────────────────────────────────────────┘    │
 │  ┌──────────────────────────────────────────────────────┐    │
 │  │  拦截器链：                                            │    │
 │  │  ExposeInvocationInterceptor                          │    │
 │  │  → AspectJAroundAdvice                                │    │
 │  │  → AspectJMethodBeforeAdvice                          │    │
 │  │  → AspectJAfterAdvice                                 │    │
 │  │  → AspectJAfterReturningAdvice                        │    │
 │  │  → AspectJAfterThrowingAdvice                         │    │
 │  │  → 目标方法                                            │    │
 │  └──────────────────────────────────────────────────────┘    │
 └──────────────────────────────────────────────────────────────┘
```

### 1.4 AOP 在 Spring 中的核心接口体系

```
ProxyConfig (代理配置基类)
  │  proxyTargetAccess = false   是否强制使用 CGLIB
  │  optimize = false            是否激进的优化（通常也导致 CGLIB）
  │  opaque = false              是否不暴露代理类型
  │  exposeProxy = false         是否将代理暴露到 ThreadLocal
  │  frozen = false              是否冻结 Advisor 列表
  │
  └── AdvisedSupport (继承 ProxyConfig，持有 Advisor 和 TargetSource)
        │
        ├── ProxyCreatorSupport (添加 AopProxyFactory)
        │     │
        │     ├── ProxyFactory (最基础的代理工厂)
        │     │
        │     └── AspectJProxyFactory (基于 AspectJ 切面的代理工厂)
        │
        └── Advised (接口，暴露代理配置)

AdvisedSupport 持有：
  ├── Advisor[] advisorArray        顾问列表
  ├── TargetSource targetSource     目标来源
  ├── Class<?>[] proxiedInterfaces  代理接口
  └── List<Class<?>> interfaces     接口列表
```

---

## 第二部分：JDK 动态代理源码深度解析

### 2.1 JDK 动态代理概述

JDK 动态代理是 Java 标准库提供的代理机制（`java.lang.reflect.Proxy`），它有以下特点：

- **只能代理接口**：目标类必须实现至少一个接口
- **运行时生成字节码**：在运行时动态生成代理类的 `.class`，然后加载到 JVM
- **基于反射调用**：每次方法调用通过 `InvocationHandler.invoke()` 反射执行

### 2.2 Proxy.newProxyInstance() 入口

```java
// java.lang.reflect.Proxy
public static Object newProxyInstance(ClassLoader loader,
                                      Class<?>[] interfaces,
                                      InvocationHandler h) {
    // 1. 空检查
    Objects.requireNonNull(h);

    final Class<?> caller = System.getCallerClass(Reflection.getCallerClass());

    // 2. 获取/生成代理类
    /*
     * getProxyClass0() 是核心：
     * - 先从缓存 WeakCache 中查找
     * - 缓存未命中则通过 ProxyClassFactory 生成
     */
    Constructor<?>[] cons = getProxyConstructor(caller, loader, interfaces);

    // 3. 通过反射创建代理实例
    return newProxyInstance(caller, cons, h);
}
```

**getProxyClass0() 查找/生成代理类：**

```java
// java.lang.reflect.Proxy
private static Class<?> getProxyClass0(ClassLoader loader,
                                       Class<?>... interfaces) {
    // 接口数量不能超过 65535
    if (interfaces.length > 65535) {
        throw new IllegalArgumentException("interface limit exceeded");
    }

    /*
     * 从缓存中查找代理类
     *
     * WeakCache 的 key = ClassLoader
     * WeakCache 的 subKey = 接口列表的哈希值
     * WeakCache 的 value = 生成的代理类 Class 对象
     *
     * 如果缓存中不存在，会调用 ProxyClassFactory.apply() 生成
     */
    return proxyClassCache.get(loader, interfaces);
}
```

### 2.3 ProxyClassFactory —— 代理类生成工厂

`ProxyClassFactory` 是 `Proxy` 的内部类，实现了 `BiFunction` 接口，负责真正生成代理类。

```java
// java.lang.reflect.Proxy.ProxyClassFactory
private static final class ProxyClassFactory
        implements BiFunction<ClassLoader, Class<?>[], Class<?>>
{
    // 所有代理类的前缀
    private static final String proxyClassNamePrefix = "$Proxy";

    // 原子计数器，用于生成唯一的类名
    private static final AtomicLong nextUniqueNumber = new AtomicLong();

    @Override
    public Class<?> apply(ClassLoader loader, Class<?>[] interfaces) {
        // ... 省略部分校验逻辑

        /*
         * 1. 验证所有接口
         * - 确保是接口（不是类）
         * - 确保对当前 ClassLoader 可见
         * - 确保没有重复接口
         * - 处理非公开接口的特殊情况
         */
        for (Class<?> intf : interfaces) {
            // ... 校验逻辑
        }

        /*
         * 2. 选择包名
         * - 如果所有接口都是 public 的，代理类放在 com.sun.proxy 包下
         * - 如果有非 public 接口，代理类放在非 public 接口所在的包下
         */
        String proxyPkg;
        int accessFlags = Modifier.PUBLIC | Modifier.FINAL;
        // ... 包名选择逻辑

        /*
         * 3. 生成代理类的唯一名称
         *    格式：包名.$Proxy0、包名.$Proxy1、包名.$Proxy2 ...
         */
        long num = nextUniqueNumber.getAndIncrement();
        String proxyName = proxyPkg + proxyClassNamePrefix + num;

        /*
         * 4. 生成代理类的字节码（核心！）
         *    ProxyGenerator.generateProxyClass() 负责生成 .class 文件的字节码
         *
         *    生成的代理类结构：
         *    - 继承 java.lang.reflect.Proxy
         *    - 实现所有传入的接口
         *    - 每个接口方法生成一个 Method 字段 + 重写的方法
         *    - 所有方法体都是调用 InvocationHandler.invoke()
         */
        byte[] proxyClassFile = ProxyGenerator.generateProxyClass(
            proxyName, interfaces, accessFlags);
        try {
            // 5. 加载字节码到 JVM
            return defineClass0(loader, proxyName,
                    proxyClassFile, 0, proxyClassFile.length);
        } catch (ClassFormatError e) {
            throw new IllegalArgumentException(e.toString());
        }
    }
}
```

### 2.4 代理类的字节码结构

生成的代理类 `$Proxy0` 大致结构如下（反编译后的伪代码）：

```java
public final class $Proxy0 extends java.lang.reflect.Proxy
        implements UserService, OrderService {

    // ===== 每个方法对应一个 Method 静态字段 =====
    // 通过反射获取目标 Method 对象，缓存在静态字段中
    private static Method m1;   // Object.equals(Object)
    private static Method m3;   // UserService.findById(Long)
    private static Method m4;   // UserService.save(User)
    private static Method m0;   // Object.hashCode()
    private static Method m2;   // Object.toString()
    // ...

    static {
        try {
            m1 = Class.forName("java.lang.Object")
                      .getMethod("equals", Class.forName("java.lang.Object"));
            m3 = Class.forName("com.example.UserService")
                      .getMethod("findById", Class.forName("java.lang.Long"));
            m4 = Class.forName("com.example.UserService")
                      .getMethod("save", Class.forName("com.example.User"));
            m0 = Class.forName("java.lang.Object").getMethod("hashCode");
            m2 = Class.forName("java.lang.Object").getMethod("toString");
        } catch (NoSuchMethodException | ClassNotFoundException e) {
            throw new NoSuchMethodError(e.getMessage());
        }
    }

    // ===== 构造函数：传入 InvocationHandler =====
    public $Proxy0(InvocationHandler var1) {
        super(var1);  // Proxy 父类的 h 字段保存 InvocationHandler
    }

    // ===== 重写接口方法 =====
    public final User findById(Long var1) {
        try {
            /*
             * 核心逻辑：所有方法调用都委托给 InvocationHandler.invoke()
             *
             * 参数：
             *   this      —— 代理对象本身
             *   m3        —— Method 对象（UserService.findById）
             *   var1      —— 方法参数
             */
            return (User) super.h.invoke(this, m3, new Object[]{var1});
        } catch (RuntimeException | Error e) {
            throw e;
        } catch (Throwable e) {
            throw new UndeclaredThrowableException(e);
        }
    }

    public final void save(User var1) {
        try {
            super.h.invoke(this, m4, new Object[]{var1});
        } catch (RuntimeException | Error e) {
            throw e;
        } catch (Throwable e) {
            throw new UndeclaredThrowableException(e);
        }
    }

    // equals / hashCode / toString 同理 ...
}
```

**关键点：**
1. 代理类继承 `Proxy`，`Proxy` 中有一个 `protected InvocationHandler h` 字段
2. 每个接口方法都被重写，方法体统一调用 `h.invoke(this, method, args)`
3. `Method` 对象在静态块中通过反射获取并缓存，避免每次调用都反射
4. 返回值需要强制类型转换

### 2.5 InvocationHandler.invoke() 回调机制

用户实现 `InvocationHandler` 接口：

```java
// 示例：最简单的 InvocationHandler
public class MyInvocationHandler implements InvocationHandler {
    private Object target;  // 目标对象

    public MyInvocationHandler(Object target) {
        this.target = target;
    }

    @Override
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        // 前置增强
        System.out.println("Before: " + method.getName());

        // 执行目标方法
        Object result = method.invoke(target, args);

        // 后置增强
        System.out.println("After: " + method.getName());

        return result;
    }
}

// 使用
UserService target = new UserServiceImpl();
UserService proxy = (UserService) Proxy.newProxyInstance(
    target.getClass().getClassLoader(),
    target.getClass().getInterfaces(),
    new MyInvocationHandler(target)
);
proxy.findById(1L);
// 输出：
// Before: findById
// （执行目标方法）
// After: findById
```

### 2.6 WeakCache 缓存机制

```java
// java.lang.reflect.WeakCache（简化版）
class WeakCache<K, P, V> {
    // 二级缓存结构
    //   一级 map: key → (subKeyFactory, valuesMap)
    //   二级 map: subKey → (referent, value)
    private final ConcurrentMap<Object, ConcurrentMap<Object, Supplier<V>>> map;

    public V get(K key, P parameter) {
        // 1. 计算 subKey（通过 subKeyFactory，这里是 keyFactory）
        Object subKey = subKeyFactory.apply(key, parameter);

        // 2. 从二级 map 中查找
        ConcurrentMap<Object, Supplier<V>> valuesMap = map.get(key);
        if (valuesMap == null) {
            valuesMap = new ConcurrentHashMap<>();
            // CAS 插入
            map.putIfAbsent(key, valuesMap);
        }

        // 3. 查找或创建 Supplier
        Supplier<V> supplier = valuesMap.get(subKey);
        if (supplier == null) {
            // 创建 Factory（Supplier 实现），内部调用 valueFactory.apply()
            // valueFactory 就是 ProxyClassFactory
            Factory factory = new Factory(key, parameter, subKey, valuesMap);
            supplier = valuesMap.putIfAbsent(subKey, factory);
            if (supplier == null) {
                supplier = factory;
            }
        }

        // 4. 获取值（可能阻塞等待其他线程生成）
        return supplier.get();
    }
}
```

**缓存设计要点：**
- 使用 `WeakReference` 引用 ClassLoader，避免内存泄漏
- 二级缓存避免在生成代理类时重复创建
- `Factory` 实现了 `Supplier`，内部用 `synchronized` 保证只有一个线程生成代理类

### 2.7 JDK 动态代理的局限性

1. **只能代理接口**：如果目标类没有实现任何接口，JDK 动态代理无法使用
2. **性能开销**：每次方法调用都通过反射 `Method.invoke()`，相比直接调用有性能损失
3. **final 方法**：`final` 方法不会被重写，代理无法拦截
4. **基本类型装箱**：方法参数会被装箱为 `Object[]`，增加 GC 压力

---

## 第三部分：CGLIB 代理源码深度解析

### 3.1 CGLIB 概述

CGLIB（Code Generation Library）是一个第三方字节码生成库，特点：

- **通过继承代理**：生成目标类的子类，不需要接口
- **运行时生成字节码**：使用 ASM 库在运行时生成 `.class` 文件
- **FastClass 加速**：通过方法索引避免反射调用，性能更高
- **不能代理 final 类/方法**：因为是通过继承实现的

### 3.2 CGLIB 核心类体系

```
CGLIB 代理核心类关系：

Enhancer (入口)
  │
  ├── GeneratorStrategy (字节码生成策略)
  │     └── DefaultGeneratorStrategy
  │           └── 使用 ASM 的 ClassWriter 生成字节码
  │
  ├── Callback (回调接口，等价于 InvocationHandler)
  │     ├── MethodInterceptor (最常用，环绕通知)
  │     ├── InvocationHandler (兼容 JDK 风格)
  │     ├── LazyLoader (懒加载)
  │     ├── Dispatcher (分发器)
  │     ├── FixedValue (固定返回值)
  │     ├── NoOp (不做任何拦截)
  │     └── CallbackFilter (决定每个方法用哪个 Callback)
  │
  └── FastClass (索引加速机制)
        ├── FastClassByCGLIB (目标类的 FastClass)
        └── FastClassByCGLIB (代理类的 FastClass)
```

### 3.3 Enhancer.create() 流程

```java
// net.sf.cglib.proxy.Enhancer（简化版）
public class Enhancer extends AbstractClassGenerator {

    public Object create() {
        // 校验
        classOnly = false;
        argumentTypes = null;
        return createHelper();
    }

    private Object createHelper() {
        // 1. 校验回调配置
        validate();
        if (superclass != null) {
            setNamePrefix(superclass.getName());
        }
        if (superclass != null) {
            setNamePrefix(superclass.getName());
        }

        // 2. 生成 Callback 的唯一 key
        //    key 包含：父类信息、接口信息、Callback 类型、CallbackFilter 等
        Object key = KEY_FACTORY.newInstance(
            (superclass != null) ? superclass.getName() : null,
            ReflectUtils.getNames(interfaces),
            filter == ALL_ZERO ? null : new WeakCacheKey(filter),
            callbackTypes,
            useFactory,
            interceptDuringConstruction,
            serialVersionUID
        );

        // 3. 调用父类 create() 生成代理类并创建实例
        return super.create(key);
    }
}
```

**AbstractClassGenerator.create()（父类，负责字节码生成和缓存）：**

```java
// net.sf.cglib.core.AbstractClassGenerator（简化版）
protected Object create(Object key) {
    try {
        ClassLoader loader = getClassLoader();

        // 1. 从缓存中查找已生成的代理类
        Map<ClassLoader, ClassLoaderData> cache = CACHE;
        ClassLoaderData data = cache.get(loader);
        if (data == null) {
            data = new ClassLoaderData(loader);
            cache.putIfAbsent(loader, data);
        }

        Object obj = data.getGeneratedClasses().get(key);
        if (obj == null) {
            synchronized (data.getGeneratedClasses()) {
                obj = data.getGeneratedClasses().get(key);
                if (obj == null) {
                    // 2. 缓存未命中，生成代理类
                    Class gen = null;
                    gen = generate(loader, data);
                    data.getGeneratedClasses().put(key, new WeakReference(gen));
                    obj = gen;
                }
            }
        }
        // 3. 通过反射创建代理实例
        return firstInstance((Class) obj);
    } catch (RuntimeException e) {
        throw e;
    } catch (Error e) {
        throw e;
    } catch (Exception e) {
        throw new CodeGenerationException(e);
    }
}

private Class generate(ClassLoader loader, ClassLoaderData data) {
    Class gen;
    // 1. 调用 GeneratorStrategy 生成字节码
    byte[] b = strategy.generate(this);
    // 2. 解析类名
    String className = ClassNameReader.getClassName(new ClassReader(b));
    // 3. 定义类（加载到 JVM）
    gen = ReflectUtils.defineClass(className, b, loader);
    return gen;
}
```

### 3.4 MethodInterceptor 拦截机制

```java
// net.sf.cglib.proxy.MethodInterceptor
public interface MethodInterceptor extends Callback {
    /**
     * @param obj       代理对象（CGLIB 生成的子类实例）
     * @param method    被拦截的方法
     * @param args      方法参数
     * @param proxy     MethodProxy，用于调用原始方法
     */
    Object intercept(Object obj, Method method, Object[] args,
                     MethodProxy proxy) throws Throwable;
}

// 使用示例
Enhancer enhancer = new Enhancer();
enhancer.setSuperclass(UserServiceImpl.class);  // 目标类作为父类
enhancer.setCallback(new MethodInterceptor() {
    @Override
    public Object intercept(Object obj, Method method, Object[] args,
                            MethodProxy proxy) throws Throwable {
        System.out.println("Before: " + method.getName());
        // 调用父类（原始）方法
        Object result = proxy.invokeSuper(obj, args);
        System.out.println("After: " + method.getName());
        return result;
    }
});

UserServiceImpl proxy = (UserServiceImpl) enhancer.create();
proxy.findById(1L);
```

### 3.5 生成的 CGLIB 代理类结构

CGLIB 生成的代理类大致结构（反编译伪代码）：

```java
// 继承目标类 UserServiceImpl
public class UserServiceImpl$$EnhancerByCGLIB$$1a2b3c4d
        extends UserServiceImpl
        implements Factory {

    // ===== Callback 字段 =====
    private MethodInterceptor CGLIB$CALLBACK_0;
    private static final ThreadLocal CGLIB$THREAD_CALLBACKS;
    private static final Callback[] CGLIB$STATIC_CALLBACKS;

    // ===== 缓存 Method 和 MethodProxy =====
    // 每个被拦截的方法都有对应的 Method 和 MethodProxy 静态字段
    static Method CGLIB$findById$0$Method;          // 原始 Method
    static MethodProxy CGLIB$findById$0$Proxy;       // MethodProxy
    static Class CGLIB$emptyArgs[];

    static {
        CGLIB$STATIC_OFFSET_0();
    }

    private static void CGLIB$STATIC_OFFSET_0() {
        // 通过反射获取原始方法
        CGLIB$findById$0$Method = ReflectUtils.findMethods(
            new String[]{"findById", "(Ljava/lang/Long;)Lcom/example/User;"},
            UserServiceImpl.class.getDeclaredMethods()
        )[0];
        // 创建 MethodProxy
        CGLIB$findById$0$Proxy = MethodProxy.create(
            UserServiceImpl.class,         // 被代理类
            UserServiceImpl$$EnhancerByCGLIB$$1a2b3c4d.class, // 代理类
            "findById",                    // 方法名
            "CGLIB$findById$0",            // 代理类中调用原始方法的方法名
            "(Ljava/lang/Long;)Lcom/example/User;"  // 方法签名
        );
    }

    // ===== 重写方法：走拦截器 =====
    @Override
    public final User findById(Long var1) {
        MethodInterceptor interceptor = this.CGLIB$CALLBACK_0;
        if (interceptor == null) {
            CGLIB$BIND_CALLBACKS(this);
            interceptor = this.CGLIB$CALLBACK_0;
        }
        if (interceptor != null) {
            /*
             * 调用 MethodInterceptor.intercept()
             * 传入 MethodProxy，内部可以调用 invokeSuper() 执行原始方法
             */
            return (User) interceptor.intercept(
                this,
                CGLIB$findById$0$Method,
                new Object[]{var1},
                CGLIB$findById$0$Proxy
            );
        }
        return super.findById(var1);
    }

    // ===== CGLIB$ 方法：直接调用父类原始方法 =====
    // 这个方法不会被拦截，是 invokeSuper() 的最终调用目标
    final User CGLIB$findById$0(Long var1) {
        return super.findById(var1);
    }
}
```

### 3.6 FastClass 索引加速机制

**FastClass 是 CGLIB 性能优于 JDK 动态代理的核心原因。**

JDK 动态代理每次调用都通过 `Method.invoke()` 反射调用，而 CGLIB 通过 FastClass 为代理类和目标类各生成一个索引类，通过方法签名计算出 `int` 索引，然后通过 `switch-case` 直接调用方法，完全避免反射。

```java
// 目标类 UserServiceImpl 的 FastClass（反编译伪代码）
public class UserServiceImpl$$FastClassByCGLIB$$5a6b7c8d extends FastClass {

    public int getIndex(Signature sig) {
        String name = sig.getName();
        String desc = sig.getDescriptor();
        // 通过方法名+签名计算索引
        if ("findById".equals(name) && "(Ljava/lang/Long;)Lcom/example/User;".equals(desc)) {
            return 0;
        }
        if ("save".equals(name) && "(Lcom/example/User;)V".equals(desc)) {
            return 1;
        }
        if ("equals".equals(name) && "(Ljava/lang/Object;)Z".equals(desc)) {
            return 2;
        }
        // ...
        return -1;
    }

    @Override
    public Object invoke(int index, Object obj, Object[] args) throws InvocationTargetException {
        // 通过 switch-case 直接调用方法，不需要反射！
        switch (index) {
        case 0:
            return ((UserServiceImpl) obj).findById((Long) args[0]);
        case 1:
            ((UserServiceImpl) obj).save((User) args[0]);
            return null;
        case 2:
            return ((UserServiceImpl) obj).equals(args[0]);
        // ...
        }
        return null;
    }

    @Override
    public Object newInstance(int index, Object[] args) {
        switch (index) {
        case 0:
            return new UserServiceImpl();
        // ...
        }
        return null;
    }
}
```

### 3.7 MethodProxy.invokeSuper() vs invoke()

```java
// net.sf.cglib.proxy.MethodProxy（简化版）
public class MethodProxy {
    private Signature sig1;              // 原始方法签名
    private Signature sig2;              // CGLIB$ 方法签名
    private CreateInfo createInfo;       // 创建信息
    private FastClassInfo fastClassInfo; // FastClass 缓存

    private static class FastClassInfo {
        FastClass f1;  // 目标类的 FastClass
        FastClass f2;  // 代理类的 FastClass
        int i1;        // 目标方法的索引（在 f1 中的 index）
        int i2;        // CGLIB$ 方法的索引（在 f2 中的 index）
    }

    /**
     * 调用原始（父类）方法
     * 使用目标类的 FastClass（f1），通过索引 i1 直接调用
     */
    public Object invokeSuper(Object obj, Object[] args) throws Throwable {
        try {
            init();  // 懒加载 FastClass
            // 通过 FastClass 的索引直接调用，不需要反射！
            return fastClassInfo.f1.invoke(fastClassInfo.i1, obj, args);
        } catch (InvocationTargetException e) {
            throw e.getTargetException();
        }
    }

    /**
     * 调用代理对象的方法（会再次进入拦截器！）
     * 使用代理类的 FastClass（f2），通过索引 i2 调用
     *
     * 注意：这会再次触发 MethodInterceptor.intercept()！
     * 如果在 intercept() 内部调用 invoke()，会导致无限递归！
     */
    public Object invoke(Object obj, Object[] args) throws Throwable {
        try {
            init();
            return fastClassInfo.f2.invoke(fastClassInfo.i2, obj, args);
        } catch (InvocationTargetException e) {
            throw e.getTargetException();
        }
    }

    private void init() {
        if (fastClassInfo == null) {
            synchronized (initLock) {
                if (fastClassInfo == null) {
                    CreateInfo ci = createInfo;
                    FastClassInfo fci = new FastClassInfo();
                    // 为目标类生成 FastClass
                    fci.f1 = helper(ci, ci.c1);
                    // 为代理类生成 FastClass
                    fci.f2 = helper(ci, ci.c2);
                    // 计算方法索引
                    fci.i1 = fci.f1.getIndex(sig1);
                    fci.i2 = fci.f2.getIndex(sig2);
                    fastClassInfo = fci;
                    createInfo = null;
                }
            }
        }
    }
}
```

**invokeSuper vs invoke 的区别：**

| 方法 | 调用目标 | 是否经过拦截器 | 典型使用场景 |
|------|---------|--------------|-------------|
| `invokeSuper(obj, args)` | 目标类的父类方法（`CGLIB$xxx$0`） | **否**，直接执行原始方法 | 在 `intercept()` 中调用原始方法 |
| `invoke(obj, args)` | 代理对象的重写方法 | **是**，会再次进入 `intercept()` | 不常使用，容易导致死循环 |

### 3.8 CGLIB vs JDK 动态代理对比

| 对比维度 | JDK 动态代理 | CGLIB |
|---------|-------------|-------|
| 代理方式 | 实现接口 | 继承目标类 |
| 是否需要接口 | **必须**有接口 | **不需要**接口 |
| final 类/方法 | 可以代理（接口方法非 final） | 不能代理 final 类和方法 |
| 方法调用机制 | 反射 `Method.invoke()` | FastClass 索引 + switch-case |
| 性能（创建） | 较快 | 较慢（需要生成更多类） |
| 性能（调用） | 较慢（每次反射） | 较快（索引直接调用） |
| 生成的类数量 | 1 个代理类 | 1 代理类 + 2 个 FastClass = 3 个类 |
| 依赖 | JDK 内置 | 需要引入 cglib + asm |

---

## 第四部分：Spring AOP 代理创建流程

### 4.1 AopProxy 接口体系

Spring AOP 在 JDK 动态代理和 CGLIB 之上做了一层抽象：

```
AopProxyFactory (接口)
  │  createAopProxy(AdvisedSupport config) → AopProxy
  │
  └── DefaultAopProxyFactory (默认实现)
        │
        │  根据 config 的配置决定创建哪种代理
        │
        ├── AopProxy (接口)
        │     │  getProxy() → Object
        │     │  getProxy(ClassLoader) → Object
        │     │
        │     ├── JdkDynamicAopProxy
        │     │     实现 InvocationHandler
        │     │     使用 JDK Proxy
        │     │
        │     ├── CglibAopProxy
        │     │     使用 CGLIB
        │     │
        │     └── ObjenesisCglibAopProxy (CglibAopProxy 子类)
        │           使用 Objenesis 绕过构造器创建实例
```

### 4.2 DefaultAopProxyFactory.createAopProxy() —— 代理选择策略

```java
// org.springframework.aop.framework.DefaultAopProxyFactory
public class DefaultAopProxyFactory implements AopProxyFactory {

    private static final int SERIALIZED_INVOCATION_SIMPLE_INTERFACES = 6;

    @Override
    public AopProxy createAopProxy(AdvisedSupport config) {
        /*
         * 判断是否使用 CGLIB 的条件（满足任一即可）：
         * 1. config.isOptimize() == true
         *    → 用户显式要求优化（激进模式）
         * 2. config.isProxyTargetClass() == true
         *    → 用户显式要求强制使用 CGLIB（@EnableAspectJAutoProxy(proxyTargetClass=true)）
         * 3. hasNoUserSuppliedProxyInterfaces(config)
         *    → 目标类没有实现任何用户自定义接口
         *    （只有 Object 等接口不算）
         *
         * 注意：Spring 5.x 后（Spring Boot 2.x+）默认 proxyTargetClass=true
         *       所以 Spring Boot 中默认使用 CGLIB！
         */
        if (!NativeDetector.inNativeImage() &&
                (config.isOptimize() || config.isProxyTargetClass() ||
                 hasNoUserSuppliedProxyInterfaces(config))) {
            Class<?> targetClass = config.getTargetClass();
            if (targetClass == null) {
                throw new AopConfigException(
                    "Either an interface or a target is required for proxy creation");
            }

            /*
             * 如果目标类本身就是接口，或者目标类已经被代理过了（Proxy 类）
             * 仍然使用 JDK 动态代理
             */
            if (targetClass.isInterface() || Proxy.isProxyClass(targetClass)) {
                return new JdkDynamicAopProxy(config);
            }
            // 否则使用 CGLIB
            return new ObjenesisCglibAopProxy(config);
        }
        else {
            // 默认使用 JDK 动态代理
            return new JdkDynamicAopProxy(config);
        }
    }

    /**
     * 判断是否没有用户自定义的接口
     */
    private boolean hasNoUserSuppliedProxyInterfaces(AdvisedSupport config) {
        Class<?>[] ifcs = config.getProxiedInterfaces();
        for (Class<?> ifc : ifcs) {
            // 排除 SpringAdvice 接口（内部接口）
            if (!ifc.isInterface() ||
                    ifc.getMethods().length == 0 && !ifc.isAnnotation()) {
                continue;
            }
            // 如果有 SpringProxy / Advised 等接口，不算用户接口
            if (ifc != SpringProxy.class && ifc != Advised.class &&
                    ifc != DecoratingProxy.class) {
                return false;  // 有用户自定义接口
            }
        }
        return true;  // 没有用户自定义接口
    }
}
```

**选择策略流程图：**

```
                    createAopProxy(config)
                           │
                           ▼
          ┌────────────────────────────────────┐
          │ optimize || proxyTargetClass ||     │
          │ hasNoUserSuppliedProxyInterfaces?   │
          └──────────────┬─────────────────────┘
               │                          │
           Yes │                      No  │
               ▼                          ▼
    ┌─────────────────┐          ┌──────────────────┐
    │ targetClass 是   │   No     │                  │
    │ 接口或 Proxy类?  │─────────▶│ JdkDynamicAopProxy│
    └────────┬────────┘          │ (JDK 动态代理)     │
         │Yes│                   └──────────────────┘
         ▼   │
┌─────────────────────────────┐
│ ObjenesisCglibAopProxy       │
│ (CGLIB 代理)                 │
└─────────────────────────────┘
```

### 4.3 JdkDynamicAopProxy 源码

`JdkDynamicAopProxy` 同时实现了 `AopProxy` 和 `InvocationHandler` 接口：

```java
// org.springframework.aop.framework.JdkDynamicAopProxy
final class JdkDynamicAopProxy implements AopProxy, InvocationHandler,
        Serializable {

    private final AdvisedSupport advised;

    // 是否需要暴露代理到 ThreadLocal
    private final boolean equalsDefined;
    private final boolean hashCodeDefined;

    public JdkDynamicAopProxy(AdvisedSupport config) throws AopConfigException {
        this.advised = config;
        // 检查目标是否自己定义了 equals/hashCode
        this.equalsDefined = ...;
        this.hashCodeDefined = ...;
    }

    @Override
    public Object getProxy() {
        return getProxy(ClassUtils.getDefaultClassLoader());
    }

    @Override
    public Object getProxy(@Nullable ClassLoader classLoader) {
        if (logger.isTraceEnabled()) {
            logger.trace("Creating JDK dynamic proxy: " +
                    this.advised.getTargetClass());
        }
        // 1. 获取代理需要实现的接口
        //    = 用户接口 + SpringProxy + Advised + DecoratingProxy
        Class<?>[] proxiedInterfaces = AopProxyUtils.completeProxiedInterfaces(
            this.advised, true);

        // 2. 查找 equals/hashCode 方法
        findDefinedEqualsAndHashCodeMethods(proxiedInterfaces);

        // 3. 调用 JDK 的 Proxy.newProxyInstance()
        //    this 就是 InvocationHandler（this 实现了 InvocationHandler）
        return Proxy.newProxyInstance(classLoader, proxiedInterfaces, this);
    }

    /**
     * 核心方法：所有代理方法调用都进入这里
     * 这就是 InvocationHandler.invoke() 的实现
     */
    @Override
    @Nullable
    public Object invoke(Object proxy, Method method, Object[] args)
            throws Throwable {

        Object oldProxy = null;
        boolean setProxyContext = false;

        // 获取目标来源
        TargetSource targetSource = this.advised.targetSource;
        Object target = null;

        try {
            // ===== 1. 特殊方法处理 =====

            // equals / hashCode 的特殊处理
            if (!this.equalsDefined && AopUtils.isEqualsMethod(method)) {
                return equals(args[0]);
            }
            if (!this.hashCodeDefined && AopUtils.isHashCodeMethod(method)) {
                return hashCode();
            }
            // 如果是 Advised 接口的方法，直接在 advised 上调用
            if (method.getDeclaringClass() == DecoratingProxy.class) {
                return AopProxyUtils.ultimateTargetClass(this.advised);
            }
            if (!this.advised.opaque && method.getDeclaringClass().isInterface() &&
                    method.getDeclaringClass().isAssignableFrom(Advised.class)) {
                // 直接服务调用
                return AopUtils.invokeJoinpointUsingReflection(
                    this.advised, method, args);
            }

            Object retVal;

            // ===== 2. 是否暴露代理到 ThreadLocal =====
            if (this.advised.exposeProxy) {
                oldProxy = AopContext.setCurrentProxy(proxy);
                setProxyContext = true;
            }

            // ===== 3. 获取目标对象 =====
            target = targetSource.getTarget();
            Class<?> targetClass = (target != null ? target.getClass() : null);

            // ===== 4. 获取拦截器链 =====
            /*
             * getInterceptorsAndDynamicInterceptionAdvice() 是核心：
             * 遍历所有 Advisor，找到匹配当前方法的拦截器
             * 返回 MethodInterceptor 数组
             */
            List<Object> chain = this.advised.getInterceptorsAndDynamicInterceptionAdvice(
                method, targetClass);

            // ===== 5. 执行拦截器链 =====
            if (chain.isEmpty()) {
                // 没有拦截器，直接调用目标方法
                Object[] argsToUse = AopProxyUtils.adaptArgumentsIfNecessary(
                    method, args);
                retVal = AopUtils.invokeJoinpointUsingReflection(
                    target, method, argsToUse);
            }
            else {
                // 有拦截器，创建 ReflectiveMethodInvocation 执行责任链
                MethodInvocation invocation =
                    new ReflectiveMethodInvocation(
                        proxy, target, method, args, targetClass, chain);
                // proceed() 启动责任链
                retVal = invocation.proceed();
            }

            // ===== 6. 处理返回值 =====
            Class<?> returnType = method.getReturnType();
            if (retVal != null && retVal == target &&
                    returnType != Object.class && returnType.isInstance(proxy) &&
                    !RawTargetAccess.class.isAssignableFrom(method.getDeclaringClass())) {
                // 如果返回值是 target 本身，且返回类型可以接收代理，返回代理
                retVal = proxy;
            }
            else if (retVal == null && returnType != Void.TYPE &&
                    returnType.isPrimitive()) {
                throw new AopInvocationException(
                    "Null return value from advice does not match primitive return type");
            }
            return retVal;
        }
        finally {
            if (target != null && !targetSource.isStatic()) {
                targetSource.releaseTarget(target);
            }
            if (setProxyContext) {
                AopContext.setCurrentProxy(oldProxy);
            }
        }
    }
}
```

### 4.4 CglibAopProxy 源码

```java
// org.springframework.aop.framework.CglibAopProxy（简化版）
class CglibAopProxy implements AopProxy, Serializable {

    protected final AdvisedSupport advised;

    @Override
    public Object getProxy(@Nullable ClassLoader classLoader) {
        if (logger.isTraceEnabled()) {
            logger.trace("Creating CGLIB proxy: " + this.advised.getTargetClass());
        }

        try {
            Class<?> rootClass = this.advised.getTargetClass();

            // 1. 创建 Enhancer
            Enhancer enhancer = createEnhancer();
            enhancer.setSuperclass(rootClass);  // 目标类作为父类
            enhancer.setInterfaces(AopProxyUtils.completeProxiedInterfaces(this.advised));
            enhancer.setNamingPolicy(SpringNamingPolicy.INSTANCE);
            enhancer.setStrategy(new ClassLoaderAwareGeneratorStrategy(classLoader));

            // 2. 获取 Callback
            Callback[] callbacks = getCallbacks(rootClass);
            Class<?>[] callbackTypes = new Class<?>[callbacks.length];
            for (int i = 0; i < callbacks.length; i++) {
                callbackTypes[i] = callbacks[i].getClass();
            }

            // 3. 设置 CallbackFilter
            //    决定每个方法使用哪个 Callback
            enhancer.setCallbackFilter(new ProxyCallbackFilter(
                this.advised.getConfigurationOnlyCopy(),
                this.fixedInterceptorMap,
                this.fixedInterceptorOffset));
            enhancer.setCallbackTypes(callbackTypes);

            // 4. 生成代理实例
            return createProxyClassAndInstance(enhancer, callbacks);
        }
        catch (CodeGenerationException | IllegalArgumentException ex) {
            throw new AopConfigException("Could not generate CGLIB subclass", ex);
        }
    }

    protected Object createProxyClassAndInstance(Enhancer enhancer, Callback[] callbacks) {
        enhancer.setInterceptDuringConstruction(false);
        enhancer.setCallbacks(callbacks);
        return enhancer.create();
    }

    /**
     * 获取所有 Callback
     * CGLIB 中每个方法可以对应不同的 Callback（通过 CallbackFilter）
     */
    private Callback[] getCallbacks(Class<?> rootClass) throws Exception {
        boolean exposeProxy = this.advised.isExposeProxy();
        boolean isFrozen = this.advised.isFrozen();
        boolean isStatic = this.advised.getTargetSource().isStatic();

        // DynamicAdvisedInterceptor：拦截用户方法，执行 Advice 链
        Callback aopInterceptor = new DynamicAdvisedInterceptor(this.advised);

        // 处理目标对象不可变的情况
        Callback targetInterceptor;
        if (exposeProxy) {
            targetInterceptor = isStatic ?
                new StaticUnadvisedExposedInterceptor(this.advised.getTargetSource().getTarget()) :
                new DynamicUnadvisedExposedInterceptor(this.advised);
        } else {
            targetInterceptor = isStatic ?
                new StaticUnadvisedInterceptor(this.advised.getTargetSource().getTarget()) :
                new DynamicUnadvisedInterceptor(this.advised);
        }

        // 各种特殊方法的 Callback
        Callback targetDispatcher = ...;
        Callback[] callbacks = new Callback[] {
            aopInterceptor,           // 0: 用户方法拦截器（核心！）
            targetInterceptor,        // 1: 不需要 Advice 的方法
            new SerializableNoOp(),   // 2: 无操作（finalize 等）
            targetDispatcher,         // 3: 目标分发
            this.advisedDispatcher,   // 4: Advised 接口方法
            new EqualsInterceptor(this.advised),       // 5: equals
            new HashCodeInterceptor(this.advised)       // 6: hashCode
        };
        return callbacks;
    }
}
```

### 4.5 DynamicAdvisedInterceptor —— CGLIB 的核心拦截器

```java
// org.springframework.aop.framework.CglibAopProxy.DynamicAdvisedInterceptor
private static class DynamicAdvisedInterceptor implements MethodInterceptor,
        Serializable {

    private final AdvisedSupport advised;

    @Override
    @Nullable
    public Object intercept(Object proxy, Method method, Object[] args,
                            MethodProxy methodProxy) throws Throwable {

        Object oldProxy = null;
        boolean setProxyContext = false;
        Object target = null;
        TargetSource targetSource = this.advised.getTargetSource();

        try {
            if (this.advised.exposeProxy) {
                oldProxy = AopContext.setCurrentProxy(proxy);
                setProxyContext = true;
            }
            target = targetSource.getTarget();
            Class<?> targetClass = (target != null ? target.getClass() : null);

            // ===== 获取拦截器链 =====
            List<Object> chain = this.advised.getInterceptorsAndDynamicInterceptionAdvice(
                method, targetClass);

            Object retVal;
            if (chain.isEmpty() && CglibMethodInvocation.isMethodProxyCompatible(method)) {
                // 没有拦截器，直接通过 MethodProxy 调用
                Object[] argsToUse = AopProxyUtils.adaptArgumentsIfNecessary(method, args);
                retVal = invokeMethod(target, method, argsToUse, methodProxy);
            }
            else {
                // 有拦截器，创建 CglibMethodInvocation 执行责任链
                retVal = new CglibMethodInvocation(
                    proxy, target, method, args, targetClass, chain, methodProxy
                ).proceed();
            }
            return processReturnType(proxy, target, method, retVal);
        }
        finally {
            if (target != null && !targetSource.isStatic()) {
                targetSource.releaseTarget(target);
            }
            if (setProxyContext) {
                AopContext.setCurrentProxy(oldProxy);
            }
        }
    }
}
```

### 4.6 代理创建完整流程图

```
                    BeanPostProcessor.postProcessAfterInitialization()
                                           │
                                           ▼
                          wrapIfNecessary(bean, beanName, cacheKey)
                                           │
                                           ▼
                    getAdvicesAndAdvisorsForBean(bean.getClass(), beanName)
                                           │
                                    ┌──────┴──────┐
                                    │ 有 Advisor?  │
                                    └──────┬──────┘
                                     │Yes      │No
                                     ▼          ▼
                          createProxy()    返回原 Bean
                                     │
                                     ▼
                    ProxyFactory 配置：
                    setTarget(target)
                    addAdvisors(advisors)
                    setProxyTargetClass(...)
                                     │
                                     ▼
                    ProxyFactory.getProxy()
                                     │
                                     ▼
                    createAopProxy() ──── DefaultAopProxyFactory
                                     │
                         ┌───────────┴───────────┐
                         ▼                       ▼
                  JdkDynamicAopProxy        CglibAopProxy
                         │                       │
                         ▼                       ▼
                  Proxy.newProxyInstance    Enhancer.create()
                         │                       │
                         ▼                       ▼
                  生成 $Proxy0 代理类       生成 $$EnhancerByCGLIB$$ 代理类
                         │                       │
                         └───────────┬───────────┘
                                     ▼
                              返回代理对象
                                     │
                                     ▼
                       后续方法调用 → 拦截器链执行
```

---

## 第五部分：Advice 链构建与执行

### 5.1 获取拦截器链

```java
// org.springframework.aop.framework.AdvisedSupport
public List<Object> getInterceptorsAndDynamicInterceptionAdvice(
        Method method, @Nullable Class<?> targetClass) {

    MethodCacheKey cacheKey = new MethodCacheKey(method, targetClass);

    // 从缓存中查找
    List<Object> cached = this.methodCache.get(cacheKey);
    if (cached == null) {
        /*
         * advisorChainFactory 是 DefaultAdvisorChainFactory
         * 核心逻辑：遍历所有 Advisor，匹配 Pointcut，返回拦截器列表
         */
        cached = this.advisorChainFactory.getInterceptorsAndDynamicInterceptionAdvice(
            this, method, targetClass);
        this.methodCache.put(cacheKey, cached);
    }
    return cached;
}
```

```java
// org.springframework.aop.framework.DefaultAdvisorChainFactory
@Override
public List<Object> getInterceptorsAndDynamicInterceptionAdvice(
        Advised config, Method method, @Nullable Class<?> targetClass) {

    // 获取 Advisor 适配器注册表（用于将 Advice 转为 MethodInterceptor）
    AdvisorAdapterRegistry registry = GlobalAdvisorAdapterRegistry.getInstance();

    // 获取所有 Advisor
    Advisor[] advisors = config.getAdvisors();
    List<Object> interceptorList = new ArrayList<>(advisors.length);

    Class<?> actualClass = (targetClass != null ? targetClass : method.getDeclaringClass());
    Boolean hasIntroductions = null;

    // 遍历所有 Advisor
    for (Advisor advisor : advisors) {
        if (advisor instanceof PointcutAdvisor) {
            PointcutAdvisor pointcutAdvisor = (PointcutAdvisor) advisor;

            // 1. ClassFilter 匹配
            if (pointcutAdvisor.getPointcut().getClassFilter().matches(actualClass)) {
                // 2. MethodMatcher 匹配
                MethodMatcher mm = pointcutAdvisor.getPointcut().getMethodMatcher();
                boolean match;
                if (mm.isRuntime()) {
                    // 运行时匹配（需要方法参数才能判断）
                    match = mm.matches(method, actualClass) ||
                            mm.matches(method, actualClass, null);
                } else {
                    // 静态匹配（不需要参数）
                    match = mm.matches(method, actualClass);
                }

                if (match) {
                    // 3. 通过 AdvisorAdapterRegistry 将 Advice 转为 MethodInterceptor
                    MethodInterceptor[] interceptors = registry.getInterceptors(advisor);
                    if (mm.isRuntime()) {
                        // 运行时匹配的拦截器，包装为 InterceptorAndDynamicMethodMatcher
                        for (MethodInterceptor interceptor : interceptors) {
                            interceptorList.add(
                                new InterceptorAndDynamicMethodMatcher(interceptor, mm));
                        }
                    } else {
                        interceptorList.addAll(Arrays.asList(interceptors));
                    }
                }
            }
        }
        else if (advisor instanceof IntroductionAdvisor) {
            IntroductionAdvisor ia = (IntroductionAdvisor) advisor;
            // IntroductionAdvisor 只有 ClassFilter
            if (ia.getClassFilter().matches(actualClass)) {
                MethodInterceptor[] interceptors = registry.getInterceptors(advisor);
                interceptorList.addAll(Arrays.asList(interceptors));
            }
        }
        else {
            // 其他类型的 Advisor，直接获取拦截器
            MethodInterceptor[] interceptors = registry.getInterceptors(advisor);
            interceptorList.addAll(Arrays.asList(interceptors));
        }
    }

    return interceptorList;
}
```

### 5.2 AdvisorAdapterRegistry —— Advice 到 MethodInterceptor 的转换

Spring 的 Advice 有多种类型（`BeforeAdvice`、`AfterAdvice`、`AroundAdvice`），但执行时统一需要 `MethodInterceptor`。`AdvisorAdapterRegistry` 负责这个转换：

```java
// org.springframework.aop.framework.adapter.DefaultAdvisorAdapterRegistry
public class DefaultAdvisorAdapterRegistry implements AdvisorAdapterRegistry, Serializable {

    // 注册的适配器列表
    private final List<AdvisorAdapter> adapters = new ArrayList<>(3);

    public DefaultAdvisorAdapterRegistry() {
        // 注册三种内置适配器
        registerAdvisorAdapter(new MethodBeforeAdviceAdapter());
        registerAdvisorAdapter(new AfterReturningAdviceAdapter());
        registerAdvisorAdapter(new ThrowsAdviceAdapter());
    }

    @Override
    public MethodInterceptor[] getInterceptors(Advisor advisor) throws UnknownAdviceTypeException {
        List<MethodInterceptor> interceptors = new ArrayList<>(3);

        Advice advice = advisor.getAdvice();
        if (advice instanceof MethodInterceptor) {
            // 如果 Advice 本身就是 MethodInterceptor（如 AroundAdvice），直接用
            interceptors.add((MethodInterceptor) advice);
        }

        // 遍历适配器，看哪种适配器能处理这个 Advice
        for (AdvisorAdapter adapter : this.adapters) {
            if (adapter.supportsAdvice(advice)) {
                // 转换为 MethodInterceptor
                interceptors.add(adapter.getInterceptor(advisor));
            }
        }

        if (interceptors.isEmpty()) {
            throw new UnknownAdviceTypeException(advisor.getAdvice());
        }
        return interceptors.toArray(new MethodInterceptor[0]);
    }
}
```

**三种 Advice 适配器：**

| 适配器 | 支持的 Advice 类型 | 生成的 Interceptor |
|--------|-------------------|-------------------|
| `MethodBeforeAdviceAdapter` | `MethodBeforeAdvice` | `MethodBeforeAdviceInterceptor` |
| `AfterReturningAdviceAdapter` | `AfterReturningAdvice` | `AfterReturningAdviceInterceptor` |
| `ThrowsAdviceAdapter` | `ThrowsAdvice` | `ThrowsAdviceInterceptor` |

### 5.3 各种 Advice 的拦截器适配

#### 5.3.1 MethodBeforeAdviceInterceptor

```java
// org.springframework.aop.framework.adapter.MethodBeforeAdviceInterceptor
public class MethodBeforeAdviceInterceptor implements MethodInterceptor, Serializable {

    private final MethodBeforeAdvice advice;

    public MethodBeforeAdviceInterceptor(MethodBeforeAdvice advice) {
        this.advice = advice;
    }

    @Override
    public Object invoke(MethodInvocation mi) throws Throwable {
        // 先执行前置通知
        this.advice.before(mi.getMethod(), mi.getArguments(), mi.getThis());
        // 然后继续执行责任链
        return mi.proceed();
    }
}
```

#### 5.3.2 AfterReturningAdviceInterceptor

```java
// org.springframework.aop.framework.adapter.AfterReturningAdviceInterceptor
public class AfterReturningAdviceInterceptor implements MethodInterceptor, Serializable {

    private final AfterReturningAdvice advice;

    @Override
    public Object invoke(MethodInvocation mi) throws Throwable {
        // 先执行责任链（包含目标方法）
        Object retVal = mi.proceed();
        // 后置通知在返回值之后执行
        this.advice.afterReturning(retVal, mi.getMethod(),
            mi.getArguments(), mi.getThis());
        return retVal;
    }
}
```

#### 5.3.3 AspectJAroundAdvice（环绕通知本身就是 MethodInterceptor）

```java
// org.springframework.aop.aspectj.AspectJAroundAdvice
// 直接实现了 MethodInterceptor，不需要适配器
public class AspectJAroundAdvice extends AbstractAspectJAdvice
        implements MethodInterceptor, Serializable {

    @Override
    public Object invoke(MethodInvocation mi) throws Throwable {
        // 直接执行 Around 通知
        // ProceedingJoinPoint 的 proceed() 会调用 MethodInvocation.proceed()
        return invokeAdviceMethod(getJoinPointMatch(), null, null);
    }
}
```

### 5.4 ReflectiveMethodInvocation —— 责任链执行核心

```java
// org.springframework.aop.framework.ReflectiveMethodInvocation
public class ReflectiveMethodInvocation implements ProxyMethodInvocation, Cloneable {

    protected final Object proxy;           // 代理对象
    protected final Object target;          // 目标对象
    protected final Method method;          // 被调用的方法
    protected Object[] arguments;           // 方法参数
    protected final Class<?> targetClass;   // 目标类
    protected final List<Object> interceptorsAndDynamicMethodMatchers;  // 拦截器链
    private int currentInterceptorIndex = -1;  // 当前执行到第几个拦截器

    @Override
    public Object proceed() throws Throwable {
        /*
         * 核心：递归调用责任链
         *
         * 当拦截器链执行完毕（currentInterceptorIndex == interceptors.size() - 1）
         * 调用目标方法
         */
        if (this.currentInterceptorIndex == this.interceptorsAndDynamicMethodMatchers.size() - 1) {
            // 拦截器链全部执行完毕，调用目标方法
            return invokeJoinpoint();
        }

        // 获取下一个拦截器
        Object interceptorOrInterceptionAdvice =
            this.interceptorsAndDynamicMethodMatchers.get(++this.currentInterceptorIndex);

        if (interceptorOrInterceptionAdvice instanceof InterceptorAndDynamicMethodMatcher) {
            // 动态匹配（运行时需要参数）
            InterceptorAndDynamicMethodMatcher dm =
                (InterceptorAndDynamicMethodMatcher) interceptorOrInterceptionAdvice;
            Class<?> targetClass = (this.targetClass != null ? this.targetClass : null);
            // 运行时匹配检查
            if (dm.methodMatcher.matches(this.method, targetClass, this.arguments)) {
                return dm.interceptor.invoke(this);
            }
            else {
                // 不匹配，跳过此拦截器，继续下一个
                return proceed();
            }
        }
        else {
            // 普通 MethodInterceptor，直接调用
            // 拦截器内部会再次调用 proceed() 继续责任链
            return ((MethodInterceptor) interceptorOrInterceptionAdvice).invoke(this);
        }
    }

    /**
     * 调用目标方法
     */
    protected Object invokeJoinpoint() throws Throwable {
        return AopUtils.invokeJoinpointUsingReflection(
            this.target, this.method, this.arguments);
    }
}

// AopUtils.invokeJoinpointUsingReflection
public static Object invokeJoinpointUsingReflection(
        @Nullable Object target, Method method, Object[] args) throws Throwable {
    try {
        // 设置可访问（如果是 private 方法）
        ReflectionUtils.makeAccessible(method);
        // 反射调用目标方法
        return method.invoke(target, args);
    }
    catch (InvocationTargetException ex) {
        throw ex.getTargetException();
    }
    catch (IllegalArgumentException ex) {
        throw new AopInvocationException(
            "AOP configuration seems to be invalid: tried calling method '" +
            method + "' on target [" + target + "]", ex);
    }
    catch (IllegalAccessException ex) {
        throw new AopInvocationException(
            "Could not access method [" + method + "]", ex);
    }
}
```

### 5.5 责任链执行流程图

假设有以下切面配置：

```java
@Aspect
public class MyAspect {
    @Around("execution(* com.example.UserService.*(..))")
    public Object around(ProceedingJoinPoint pjp) throws Throwable {
        System.out.println("Around-Before");
        Object result = pjp.proceed();
        System.out.println("Around-After");
        return result;
    }

    @Before("execution(* com.example.UserService.*(..))")
    public void before() {
        System.out.println("Before");
    }

    @After("execution(* com.example.UserService.*(..))")
    public void after() {
        System.out.println("After");
    }

    @AfterReturning("execution(* com.example.UserService.*(..))")
    public void afterReturning() {
        System.out.println("AfterReturning");
    }
}
```

执行流程（调用 `proxy.findById(1L)`）：

```
proxy.findById(1L)
    │
    ▼
JdkDynamicAopProxy.invoke() / DynamicAdvisedInterceptor.intercept()
    │
    │  获取拦截器链：
    │  [0] ExposeInvocationInterceptor
    │  [1] AspectJAroundAdvice（@Around）
    │  [2] MethodBeforeAdviceInterceptor（@Before）
    │  [3] AspectJAfterAdvice（@After）
    │  [4] AfterReturningAdviceInterceptor（@AfterReturning）
    │
    ▼
ReflectiveMethodInvocation.proceed()  index=-1
    │
    ├──► index=0: ExposeInvocationInterceptor.invoke()
    │         │
    │         └──► proceed() index=1
    │               │
    │               ├──► index=1: AspectJAroundAdvice.invoke()
    │               │         │
    │               │         │  执行 @Around 前半部分
    │               │         │  → 输出: "Around-Before"
    │               │         │
    │               │         │  调用 pjp.proceed()
    │               │         │
    │               │         └──► proceed() index=2
    │               │               │
    │               │               ├──► index=2: MethodBeforeAdviceInterceptor.invoke()
    │               │               │         │
    │               │               │         │  执行 @Before
    │               │               │         │  → 输出: "Before"
    │               │               │         │
    │               │               │         └──► proceed() index=3
    │               │               │               │
    │               │               │               ├──► index=3: AspectJAfterAdvice.invoke()
    │               │               │               │         │
    │               │               │               │         └──► proceed() index=4
    │               │               │               │               │
    │               │               │               │               ├──► index=4: AfterReturningAdviceInterceptor.invoke()
    │               │               │               │               │         │
    │               │               │               │               │         └──► proceed() index=5
    │               │               │               │               │               │
    │               │               │               │               │               ├──► index=5 == size-1
    │               │               │               │               │               │  调用目标方法 invokeJoinpoint()
    │               │               │               │               │               │  → target.findById(1L)
    │               │               │               │               │               │  返回结果
    │               │               │               │               │               ▼
    │               │               │               │               │  执行 @AfterReturning
    │               │               │               │               │  → 输出: "AfterReturning"
    │               │               │               │               │  返回结果
    │               │               │               │               ▼
    │               │               │               │  执行 @After
    │               │               │               │  → 输出: "After"
    │               │               │               │  返回结果
    │               │               │               ▼
    │               │               │  返回结果
    │               │               ▼
    │               │  返回结果
    │               ▼
    │  执行 @Around 后半部分
    │  → 输出: "Around-After"
    │  返回结果
    ▼
最终输出：
  Around-Before
  Before
  （目标方法执行）
  AfterReturning
  After
  Around-After
```

### 5.6 执行顺序总结

Spring 5.3+ 的 Advice 执行顺序（同一 Aspect 内）：

```
@Around 前半部分
    @Before
        目标方法
    @AfterReturning（如果正常返回）
    @AfterThrowing（如果抛异常）
    @After（无论如何都执行）
@Around 后半部分
```

> **注意**：Spring 4.x 和 5.x 的执行顺序有差异。Spring 5.2.7+ 对 @After 和 @AfterReturning/@AfterThrowing 的顺序做了调整。如果多个 Aspect 之间有顺序依赖，可以通过 `@Order` 注解控制。

---

## 第六部分：Pointcut/Advisor/Advice 体系

### 6.1 Pointcut 体系

```java
// org.springframework.aop.Pointcut
public interface Pointcut {
    // 类过滤器：匹配哪些类
    ClassFilter getClassFilter();
    // 方法匹配器：匹配哪些方法
    MethodMatcher getMethodMatcher();

    // 常量：匹配所有
    Pointcut TRUE = TruePointcut.INSTANCE;
}

// ClassFilter
public interface ClassFilter {
    boolean matches(Class<?> clazz);
    ClassFilter TRUE = TrueClassFilter.INSTANCE;
}

// MethodMatcher
public interface MethodMatcher {
    // 静态匹配（不需要参数）
    boolean matches(Method method, Class<?> targetClass);
    // 是否运行时匹配（需要参数）
    boolean isRuntime();
    // 运行时匹配（需要参数）
    boolean matches(Method method, Class<?> targetClass, Object... args);
}
```

**Pointcut 实现类层次：**

```
Pointcut
  │
  ├── TruePointcut（匹配所有）
  │
  ├── NameMatchMethodPointcut（方法名匹配）
  │     │  mappedNames = {"save*", "delete*"}
  │     └── matches: method.getName().startsWith("save")
  │
  ├── JdkRegexpMethodPointcut（正则表达式匹配）
  │     └── Pattern[] patterns
  │
  ├── AspectJExpressionPointcut（AspectJ 切点表达式，最常用）
  │     │  expression = "execution(* com.example..*.*(..))"
  │     └── 使用 AspectJ 的 PointcutParser 解析表达式
  │
  ├── ComposablePointcut（组合切点，AND/OR 操作）
  │
  ├── ControlFlowPointcut（控制流匹配，匹配调用栈）
  │
  └── AnnotationMatchingPointcut（注解匹配）
        │  @Transactional → 匹配所有标注了 @Transactional 的方法
        └── ClassLevelAnnotationMatchingPointcut / MethodLevelAnnotationMatchingPointcut
```

### 6.2 Advice 类型体系

```
Advice (标记接口)
  │
  ├── BeforeAdvice (标记接口)
  │     └── MethodBeforeAdvice
  │           │  before(Method method, Object[] args, Object target)
  │           └── AspectJMethodBeforeAdvice
  │                 │  @Before 注解对应的 Advice
  │                 └── 被适配为 MethodBeforeAdviceInterceptor
  │
  ├── AfterAdvice (标记接口)
  │     ├── AfterReturningAdvice
  │     │     │  afterReturning(Object returnValue, Method method, Object[] args, Object target)
  │     │     └── AspectJAfterReturningAdvice
  │     │           │  @AfterReturning 注解对应的 Advice
  │     │           └── 被适配为 AfterReturningAdviceInterceptor
  │     │
  │     ├── ThrowsAdvice
  │     │     │  afterThrowing(Method, Object[], Object, Throwable)
  │     │     └── 被适配为 ThrowsAdviceInterceptor
  │     │
  │     └── AfterAdvice (Spring 自己的)
  │           └── AspectJAfterAdvice
  │                 │  @After 注解对应的 Advice
  │                 └── 直接实现 MethodInterceptor（finally 块执行）
  │
  ├── Interceptor (直接实现 MethodInterceptor 的 Advice)
  │     ├── MethodInterceptor
  │     │     │  invoke(MethodInvocation invocation)
  │     │     ├── AspectJAroundAdvice
  │     │     │     @Around 注解对应的 Advice
  │     │     ├── AspectJAfterAdvice
  │     │     │     @After 注解对应的 Advice
  │     │     ├── ExposeInvocationInterceptor
  │     │     │     将 MethodInvocation 暴露到 ThreadLocal
  │     │     └── TransactionInterceptor
  │     │           @Transactional 的事务拦截器（详见第九部分）
  │     │
  │     ├── ConstructorInterceptor
  │     └── FieldInterceptor
  │
  └── IntroductionInfo (引介通知，给类增加接口)
        └── IntroductionInterceptor
              └── DelegatePerTargetObjectIntroductionInterceptor
```

### 6.3 Advisor 体系

```java
// org.springframework.aop.Advisor（标记接口）
public interface Advisor {
    Advice getAdvice();
    boolean isAdviceIntroduction();
}

// PointcutAdvisor：包含 Pointcut
public interface PointcutAdvisor extends Advisor {
    Pointcut getPointcut();
}

// IntroductionAdvisor：引入新接口
public interface IntroductionAdvisor extends Advisor, IntroductionInfo {
    ClassFilter getClassFilter();
    // 没有 MethodMatcher，因为 Introduction 是类级别的
}
```

**Advisor 实现类：**

```
PointcutAdvisor
  │
  ├── DefaultPointcutAdvisor
  │     │  最通用的实现，Pointcut + Advice 任意组合
  │     └── pointcut = TruePointcut.INSTANCE (默认匹配所有)
  │
  ├── NameMatchMethodPointcutAdvisor
  │     │  内部持有 NameMatchMethodPointcut
  │     └── setMappedNames({"save*", "delete*"})
  │
  ├── RegexpMethodPointcutAdvisor
  │     │  内部持有 JdkRegexpMethodPointcut / Perl5RegexpMethodPointcut
  │     └── setPattern("com\.example\.service\..*")
  │
  ├── AspectJPointcutAdvisor
  │     │  内部持有 AspectJExpressionPointcut
  │     └── InstantiationModelAwarePointcutAdvisorImpl
  │           │  AspectJ 注解解析后的最终 Advisor
  │           ├── pointcut = AspectJExpressionPointcut
  │           ├── advice = AspectJAroundAdvice / AspectJMethodBeforeAdvice / ...
  │           └── aspectJAdviceMethod = @Around/@Before 等标注的方法
  │
  ├── BeanNameAutoProxyCreator（按 Bean 名自动代理）
  │     │  不是严格的 PointcutAdvisor，是 ProxyCreator
  │     └── interceptorNames = {"transactionInterceptor"}
  │
  └── DefaultBeanFactoryPointcutAdvisor
        │  BeanFactory 中的 Advisor，Advice 通过 BeanName 懒加载
        └── adviceBeanName = "transactionInterceptor"
```

### 6.4 AspectJExpressionPointcut

```java
// org.springframework.aop.aspectj.AspectJExpressionPointcut
public class AspectJExpressionPointcut extends AbstractExpressionPointcut
        implements ClassFilter, MethodMatcher, BeanFactoryAware {

    // AspectJ 的切点解析器
    private transient PointcutParser pointcutParser;

    // AspectJ 的切点表达式
    private transient PointcutExpression pointcutExpression;

    @Override
    public boolean matches(Class<?> clazz) {
        // 初始化表达式（懒加载）
        obtainPointcutExpression();
        // 使用 AspectJ 的阴影匹配（Shadow Match）
        // 即使类上没有对应方法，也能匹配继承的方法
        return this.pointcutExpression.couldMatchJoinPointsInType(clazz);
    }

    @Override
    public boolean matches(Method method, Class<?> targetClass) {
        obtainPointcutExpression();
        // 方法级别的匹配
        ShadowMatch shadowMatch = getShadowMatch(method);
        return shadowMatch.matches();
    }

    @Override
    public boolean isRuntime() {
        // 检查是否有 args()、@args()、target() 等运行时切点
        // 如果有，返回 true，表示需要运行时匹配
        obtainPointcutExpression();
        return this.pointcutExpression.mayNeedDynamicTest();
    }

    private void obtainPointcutExpression() {
        if (this.pointcutExpression == null) {
            // 创建 AspectJ 的 PointcutParser
            this.pointcutParser = PointcutParser
                .getPointcutParserSupportingAllPrimitivesAndUsingSpecifiedClassloaderForResolution(
                    getClassLoader());
            // 解析表达式字符串
            this.pointcutExpression = this.pointcutParser.parsePointcutExpression(
                replaceBooleanOperators(getExpression()),
                this.declaredScope, this.pointcutParameterTypes);
        }
    }
}
```

**常见的 AspectJ 切点表达式：**

```
execution(modifiers-pattern? ret-type-pattern declaring-type-pattern? name-pattern(param-pattern) throws-pattern?)

示例：
execution(public * com.example.service..*.*(..))         // service 包下所有 public 方法
execution(* com.example..*Service.*(..))                  // 所有 Service 类的所有方法
execution(* *.save*(..))                                  // 所有 save 开头的方法
@within(org.springframework.transaction.annotation.Transactional)  // 类上有 @Transactional
@annotation(org.springframework.transaction.annotation.Transactional)  // 方法上有 @Transactional
execution(* *..*Service.*(..)) && args(String,..)         // Service 方法且第一个参数是 String
target(com.example.service.UserService)                    // 目标对象是 UserService 类型
this(com.example.service.UserService)                      // 代理对象是 UserService 类型
bean(userService)                                          // 名为 userService 的 Bean
```

---

## 第七部分：@EnableAspectJAutoProxy 与 BeanPostProcessor

### 7.1 @EnableAspectJAutoProxy 注解解析

```java
// org.springframework.context.annotation.EnableAspectJAutoProxy
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
// 通过 @Import 导入 AspectJAutoProxyRegistrar
@Import(AspectJAutoProxyRegistrar.class)
public @interface EnableAspectJAutoProxy {

    /**
     * 是否强制使用 CGLIB（proxyTargetClass = true）
     * false（默认）= 有接口用 JDK Proxy，没接口用 CGLIB
     * true = 一律用 CGLIB
     */
    boolean proxyTargetClass() default false;

    /**
     * 是否暴露代理对象到 ThreadLocal
     * 设为 true 后，可通过 AopContext.currentProxy() 获取当前代理对象
     * 用于解决"同类方法内部调用不走代理"的问题
     */
    boolean exposeProxy() default false;
}
```

### 7.2 AspectJAutoProxyRegistrar 注册流程

```java
// org.springframework.context.annotation.AspectJAutoProxyRegistrar
class AspectJAutoProxyRegistrar implements ImportBeanDefinitionRegistrar {

    @Override
    public void registerBeanDefinitions(
            AnnotationMetadata importingClassMetadata, BeanDefinitionRegistry registry) {

        // 1. 注册 AnnotationAwareAspectJAutoProxyCreator
        AopConfigUtils.registerAspectJAutoProxyCreatorIfNecessary(registry);

        // 2. 读取 @EnableAspectJAutoProxy 的属性
        AnnotationAttributes enableAspectJAutoProxy =
            AnnotationConfigUtils.attributesFor(importingClassMetadata,
                EnableAspectJAutoProxy.class);

        if (enableAspectJAutoProxy != null) {
            // 设置 proxyTargetClass
            if (enableAspectJAutoProxy.getBoolean("proxyTargetClass")) {
                AopConfigUtils.forceAutoProxyCreatorToUseClassProxying(registry);
            }
            // 设置 exposeProxy
            if (enableAspectJAutoProxy.getBoolean("exposeProxy")) {
                AopConfigUtils.forceAutoProxyCreatorToExposeProxy(registry);
            }
        }
    }
}
```

```java
// org.springframework.aop.config.AopConfigUtils
public static void registerAspectJAutoProxyCreatorIfNecessary(BeanDefinitionRegistry registry) {
    registerAspectJAutoProxyCreatorIfNecessary(registry, null);
}

public static void registerAspectJAutoProxyCreatorIfNecessary(
        BeanDefinitionRegistry registry, @Nullable Object source) {

    // 注册或升级 BeanDefinition
    // BeanName = "org.springframework.aop.config.internalAutoProxyCreator"
    // BeanClass = AnnotationAwareAspectJAutoProxyCreator.class
    BeanDefinition beanDefinition = BeanDefinitionBuilder
        .genericBeanDefinition(AnnotationAwareAspectJAutoProxyCreator.class)
        .getBeanDefinition();

    registry.registerBeanDefinition(
        AUTO_PROXY_CREATOR_BEAN_NAME, beanDefinition);

    // 设置 proxyTargetClass 和 exposeProxy
    // ...
}
```

### 7.3 AnnotationAwareAspectJAutoProxyCreator 类层次

```
AnnotationAwareAspectJAutoProxyCreator (最终实现类)
  │  处理 @AspectJ 注解，扫描 @Aspect 类
  │
  └── AspectJAwareAdvisorAutoProxyCreator
        │  处理 AspectJ 排序（@DeclarePrecedence）
        │
        └── AbstractAdvisorAutoProxyCreator
              │  自动扫描所有 Advisor，为匹配的 Bean 创建代理
              │
              │  核心方法：
              │  - postProcessBeforeInstantiation()  → 提前创建代理（targetSource）
              │  - postProcessAfterInitialization()  → 正常创建代理
              │  - getAdvicesAndAdvisorsForBean()    → 获取匹配的 Advisor
              │
              └── AbstractAutoProxyCreator
                    │  实现了 SmartInstantiationAwareBeanPostProcessor
                    │  核心方法：
                    │  - wrapIfNecessary()  → 判断并创建代理
                    │  - createProxy()      → 创建代理对象
                    │
                    └── ProxyProcessorSupport
                          │  实现 Ordered 接口，控制 BeanPostProcessor 优先级
                          │
                          └── ProxyConfig (代理配置)
```

### 7.4 BeanPostProcessor 在 IoC 中的执行时机

```
Spring IoC 容器启动流程中 AOP 的参与点：

refresh() {
    1. prepareRefresh()                          ← 准备阶段
    2. obtainFreshBeanFactory()                  ← 获取 BeanFactory
    3. prepareBeanFactory()                      ← 配置 BeanFactory
    4. postProcessBeanFactory()                  ← 子类扩展
    5. invokeBeanFactoryPostProcessors()         ← 执行 BFPP
    6. registerBeanPostProcessors()              ← ★注册 BeanPostProcessor
       │  ← AnnotationAwareAspectJAutoProxyCreator 在这里被注册
       │    它实现了 Ordered，优先级较高
       ▼
    7. initMessageSource()                       ← 国际化
    8. initApplicationEventMulticaster()         ← 事件广播器
    9. onRefresh()                               ← 子类初始化
    10. registerListeners()                      ← 注册监听器
    11. finishBeanFactoryInitialization()        ← ★实例化所有单例 Bean
        │
        │  对每个 Bean：
        │  1. createBeanInstance()  → 构造器创建实例
        │  2. populateBean()        → 依赖注入
        │  3. initializeBean():
        │     a. applyBeanPostProcessorsBeforeInitialization()
        │        │  → postProcessBeforeInitialization()
        │        │  → AnnotationAwareAspectJAutoProxyCreator.postProcessBeforeInstantiation()
        │        │    （注意：这里是 BeforeInstantiation，在实例化之前）
        │        │
        │     b. invokeInitMethods()  → @PostConstruct / InitializingBean / init-method
        │     c. applyBeanPostProcessorsAfterInitialization()  ← ★AOP 在这里
        │        │  → postProcessAfterInitialization()
        │        │  → AnnotationAwareAspectJAutoProxyCreator.postProcessAfterInitialization()
        │        │    → wrapIfNecessary()
        │        │    → 如果匹配，创建代理对象替换原始 Bean
        │        ▼
        │  最终放入容器的可能是代理对象而非原始对象
        ▼
    12. finishRefresh()                          ← 发布刷新事件
}
```

### 7.5 postProcessBeforeInstantiation() —— 提前创建代理

```java
// org.springframework.aop.framework.autoproxy.AbstractAutoProxyCreator
@Override
public Object postProcessBeforeInstantiation(Class<?> beanClass, String beanName) {
    // 1. 获取 cacheKey
    Object cacheKey = getCacheKey(beanClass, beanName);

    // 2. 检查是否已经在 targetSourcedBeans 中（避免重复）
    if (!StringUtils.hasLength(beanName) || !this.targetSourcedBeans.contains(beanName)) {
        if (this.advisedBeans.containsKey(cacheKey)) {
            return null;  // 已经处理过
        }
        // 3. 判断是否应该跳过
        // shouldSkip() 在 AnnotationAwareAspectJAutoProxyCreator 中被重写
        // → 用于扫描和解析 @Aspect，构建 Advisor 列表
        if (isInfrastructureClass(beanClass) || shouldSkip(beanClass, beanName)) {
            this.advisedBeans.put(cacheKey, Boolean.FALSE);
            return null;
        }
    }

    // 4. 检查是否有自定义 TargetSource
    TargetSource targetSource = getCustomTargetSource(beanClass, beanName);
    if (targetSource != null) {
        // 有自定义 TargetSource，提前创建代理
        if (StringUtils.hasLength(beanName)) {
            this.targetSourcedBeans.add(beanName);
        }
        // 获取 Advisor
        Object[] specificInterceptors = getAdvicesAndAdvisorsForBean(
            beanClass, beanName, targetSource);
        // 创建代理
        Object proxy = createProxy(beanClass, beanName, specificInterceptors, targetSource);
        this.proxyTypes.put(cacheKey, proxy.getClass());
        return proxy;  // 返回代理对象，跳过后续 Bean 创建
    }

    return null;  // 返回 null，走正常 Bean 创建流程
}
```

### 7.6 shouldSkip() —— 扫描 @Aspect 构建 Advisor 列表

```java
// org.springframework.aop.aspectj.annotation.AnnotationAwareAspectJAutoProxyCreator
@Override
protected boolean shouldSkip(Class<?> beanClass, String beanName) {
    /*
     * findCandidateAdvisors() 是关键：
     * 1. 调用父类 AbstractAdvisorAutoProxyCreator.findCandidateAdvisors()
     *    → 从容器中获取所有实现了 Advisor 接口的 Bean
     * 2. 调用 BeanFactoryAspectJAdvisorsBuilder.buildAspectJAdvisors()
     *    → 扫描所有标注了 @Aspect 的 Bean，解析其中的 @Before/@After/@Around 等
     *    → 将每个通知方法包装成 InstantiationModelAwarePointcutAdvisorImpl
     */
    List<Advisor> candidateAdvisors = findCandidateAdvisors();

    // 遍历，检查当前 Bean 是否是 Aspect（避免对 Aspect 自身创建代理）
    for (Advisor advisor : candidateAdvisors) {
        if (advisor instanceof AspectJPointcutAdvisor &&
                ((AspectJPointcutAdvisor) advisor).getAspectName().equals(beanName)) {
            return true;  // 跳过 Aspect 自身
        }
    }
    return super.shouldSkip(beanClass, beanName);
}
```

### 7.7 postProcessAfterInitialization() —— 正常创建代理

```java
// org.springframework.aop.framework.autoproxy.AbstractAutoProxyCreator
@Override
public Object postProcessAfterInitialization(@Nullable Object bean, String beanName) {
    if (bean != null) {
        Object cacheKey = getCacheKey(bean.getClass(), beanName);
        if (this.earlyProxyReferences.remove(cacheKey) != bean) {
            // ★ 核心：如果有需要，包装成代理
            return wrapIfNecessary(bean, beanName, cacheKey);
        }
    }
    return bean;
}

protected Object wrapIfNecessary(Object bean, String beanName, Object cacheKey) {
    // 1. 如果已有自定义 TargetSource（在 BeforeInstantiation 中已处理），直接返回
    if (StringUtils.hasLength(beanName) && this.targetSourcedBeans.contains(beanName)) {
        return bean;
    }

    // 2. 如果之前标记为不需要代理
    if (Boolean.FALSE.equals(this.advisedBeans.get(cacheKey))) {
        return bean;
    }

    // 3. 如果是基础设施类（Advisor、Advice、AopInfrastructureBean），跳过
    if (isInfrastructureClass(bean.getClass()) || shouldSkip(bean.getClass(), beanName)) {
        this.advisedBeans.put(cacheKey, Boolean.FALSE);
        return bean;
    }

    // ★ 4. 获取匹配当前 Bean 的 Advisor（核心！）
    Object[] specificInterceptors = getAdvicesAndAdvisorsForBean(
        bean.getClass(), beanName, null);

    if (specificInterceptors != DO_NOT_PROXY) {
        this.advisedBeans.put(cacheKey, Boolean.TRUE);

        // ★ 5. 创建代理
        Object proxy = createProxy(
            bean.getClass(), beanName, specificInterceptors, new SingletonTargetSource(bean));
        this.proxyTypes.put(cacheKey, proxy.getClass());

        // 返回代理对象，替换原始 Bean
        return proxy;
    }

    // 没有匹配的 Advisor，标记为不需要代理
    this.advisedBeans.put(cacheKey, Boolean.FALSE);
    return bean;
}
```

### 7.8 getAdvicesAndAdvisorsForBean() —— 获取匹配的 Advisor

```java
// org.springframework.aop.framework.autoproxy.AbstractAdvisorAutoProxyCreator
@Override
protected Object[] getAdvicesAndAdvisorsForBean(
        Class<?> beanClass, String beanName, @Nullable TargetSource targetSource) {

    // 查找匹配的 Advisor
    List<Advisor> advisors = findEligibleAdvisors(beanClass, beanName);
    if (advisors.isEmpty()) {
        return DO_NOT_PROXY;  // 没有匹配的，不创建代理
    }
    return advisors.toArray();
}

protected List<Advisor> findEligibleAdvisors(Class<?> beanClass, String beanName) {
    // 1. 获取所有候选 Advisor
    //    包括：容器中的 Advisor Bean + @Aspect 解析出的 Advisor
    List<Advisor> candidateAdvisors = findCandidateAdvisors();

    // 2. 筛选出匹配当前 Bean 的 Advisor
    //    通过 Pointcut 的 ClassFilter 和 MethodMatcher 判断
    List<Advisor> eligibleAdvisors = findAdvisorsThatCanApply(
        candidateAdvisors, beanClass, beanName);

    // 3. 扩展 Advisor 链（添加 ExposeInvocationInterceptor）
    extendAdvisors(eligibleAdvisors);

    // 4. 排序
    if (!eligibleAdvisors.isEmpty()) {
        eligibleAdvisors = sortAdvisors(eligibleAdvisors);
    }
    return eligibleAdvisors;
}
```

```java
// org.springframework.aop.framework.autoproxy.AbstractAdvisorAutoProxyCreator
protected List<Advisor> findAdvisorsThatCanApply(
        List<Advisor> candidateAdvisors, Class<?> beanClass, String beanName) {

    ProxyCreationUtils.validateProxyInterfaces(beanClass);
    List<Advisor> eligibleAdvisors = new ArrayList<>();

    // 1. 先处理 IntroductionAdvisor（类级别匹配）
    for (Advisor candidate : candidateAdvisors) {
        if (candidate instanceof IntroductionAdvisor &&
                ((IntroductionAdvisor) candidate).getClassFilter().matches(beanClass)) {
            eligibleAdvisors.add(candidate);
        }
    }

    // 2. 处理 PointcutAdvisor（方法级别匹配）
    boolean hasIntroductions = !eligibleAdvisors.isEmpty();
    for (Advisor candidate : candidateAdvisors) {
        if (candidate instanceof IntroductionAdvisor) {
            continue;  // 已经处理过
        }
        // ★ AopUtils.canApply() 是核心匹配逻辑
        if (canApply(candidate, beanClass, hasIntroductions)) {
            eligibleAdvisors.add(candidate);
        }
    }
    return eligibleAdvisors;
}
```

```java
// org.springframework.aop.support.AopUtils
public static boolean canApply(Advisor advisor, Class<?> targetClass,
                                boolean hasIntroductions) {
    if (advisor instanceof IntroductionAdvisor) {
        return ((IntroductionAdvisor) advisor).getClassFilter().matches(targetClass);
    }
    else if (advisor instanceof PointcutAdvisor) {
        PointcutAdvisor pca = (PointcutAdvisor) advisor;
        // ★ 委托给 canApply(Pointcut, Class, boolean)
        return canApply(pca.getPointcut(), targetClass, hasIntroductions);
    }
    else {
        // 没有 Pointcut 的 Advisor，默认可以应用
        return true;
    }
}

public static boolean canApply(Pointcut pc, Class<?> targetClass,
                                boolean hasIntroductions) {
    // 1. ClassFilter 匹配
    if (!pc.getClassFilter().matches(targetClass)) {
        return false;
    }

    MethodMatcher methodMatcher = pc.getMethodMatcher();

    // 2. 如果 MethodMatcher 匹配所有方法，直接返回 true
    if (methodMatcher == MethodMatcher.TRUE) {
        return true;
    }

    // 3. 遍历目标类的所有接口和方法，看是否有匹配的
    IntroductionAwareMethodMatcher introductionAwareMethodMatcher = null;
    if (methodMatcher instanceof IntroductionAwareMethodMatcher) {
        introductionAwareMethodMatcher = (IntroductionAwareMethodMatcher) methodMatcher;
    }

    Set<Class<?>> classes = new LinkedHashSet<>();
    if (!Proxy.isProxyClass(targetClass)) {
        classes.add(ClassUtils.getUserClass(targetClass));
    }
    classes.addAll(ClassUtils.getAllInterfacesForClassAsSet(targetClass));

    for (Class<?> clazz : classes) {
        Method[] methods = ReflectionUtils.getAllDeclaredMethods(clazz);
        for (Method method : methods) {
            // 只要有一个方法匹配，就返回 true
            if (introductionAwareMethodMatcher != null ?
                    introductionAwareMethodMatcher.matches(method, targetClass, hasIntroductions) :
                    methodMatcher.matches(method, targetClass)) {
                return true;
            }
        }
    }

    return false;  // 没有任何方法匹配
}
```

### 7.9 createProxy() —— 创建代理

```java
// org.springframework.aop.framework.autoproxy.AbstractAutoProxyCreator
protected Object createProxy(Class<?> beanClass, @Nullable String beanName,
        @Nullable Object[] specificInterceptors, TargetSource targetSource) {

    if (this.beanFactory instanceof ConfigurableListableBeanFactory) {
        AutoProxyUtils.exposeTargetClass((ConfigurableListableBeanFactory)
            this.beanFactory, beanName, beanClass);
    }

    // 1. 创建 ProxyFactory
    ProxyFactory proxyFactory = new ProxyFactory();
    proxyFactory.copyFrom(this);

    // 2. 判断是否使用 proxyTargetClass
    if (!proxyFactory.isProxyTargetClass()) {
        // 检查是否有用户接口
        if (shouldProxyTargetClass(beanClass, beanName)) {
            proxyFactory.setProxyTargetClass(true);
        }
        else {
            // 评估接口
            Class<?>[] targetInterfaces = ClassUtils.getAllInterfacesForClass(
                beanClass, true);
            for (Class<?> targetInterface : targetInterfaces) {
                proxyFactory.addInterface(targetInterface);
            }
        }
    }

    // 3. 构建 Advisor 链
    Advisor[] advisors = buildAdvisors(beanName, specificInterceptors);
    proxyFactory.addAdvisors(advisors);
    proxyFactory.setTargetSource(targetSource);

    // 4. 自定义代理工厂
    customizeProxyFactory(proxyFactory);

    // 5. 设置冻结
    proxyFactory.setFrozen(this.freezeProxy);
    proxyFactory.setPreFiltered(isPreFiltered());

    // 6. 获取代理对象
    //    → DefaultAopProxyFactory.createAopProxy()
    //    → JdkDynamicAopProxy 或 CglibAopProxy
    //    → getProxy()
    return proxyFactory.getProxy(getProxyClassLoader());
}
```

---

## 第八部分：AspectJ 注解处理

### 8.1 @Aspect 解析流程

```java
// org.springframework.aop.aspectj.annotation.BeanFactoryAspectJAdvisorsBuilder
public List<Advisor> buildAspectJAdvisors() {
    List<String> aspectNames = this.aspectBeanNames;

    if (aspectNames == null) {
        synchronized (this) {
            aspectNames = this.aspectBeanNames;
            if (aspectNames == null) {
                List<Advisor> advisors = new ArrayList<>();
                aspectNames = new ArrayList<>();

                // 1. 获取所有标注了 @Aspect 的 Bean 名称
                String[] beanNames = BeanFactoryUtils.beanNamesForTypeIncludingAncestors(
                    this.beanFactory, Object.class, true, false);

                for (String beanName : beanNames) {
                    Class<?> beanType = this.beanFactory.getType(beanName);
                    if (beanType == null) {
                        continue;
                    }

                    // 2. 检查是否有 @Aspect 注解
                    if (this.advisorFactory.isAspect(beanType)) {
                        // 是 @Aspect
                        aspectNames.add(beanName);
                        AspectMetadata amd = new AspectMetadata(beanType, beanName);

                        // 3. 检查是单例还是 perthis/pertarget
                        if (amd.getAjType().getPerClause().getKind() == PerClauseKind.SINGLETON) {
                            // 单例切面
                            MetadataAwareAspectInstanceFactory factory =
                                new BeanFactoryAspectInstanceFactory(
                                    this.beanFactory, beanName);

                            // ★ 4. 解析切面中的 Advice 方法，生成 Advisor 列表
                            List<Advisor> classAdvisors =
                                this.advisorFactory.getAdvisors(factory);

                            // 缓存
                            if (this.beanFactory.isSingleton(beanName)) {
                                this.advisorsCache.put(beanName, classAdvisors);
                            }
                            else {
                                this.aspectFactoryCache.put(beanName, factory);
                            }
                            advisors.addAll(classAdvisors);
                        }
                        else {
                            // perthis/pertarget 模式（每个目标一个切面实例）
                            MetadataAwareAspectInstanceFactory factory =
                                new PrototypeAspectInstanceFactory(
                                    this.beanFactory, beanName);
                            this.aspectFactoryCache.put(beanName, factory);
                            advisors.addAll(this.advisorFactory.getAdvisors(factory));
                        }
                    }
                }
                this.aspectBeanNames = aspectNames;
                return advisors;
            }
        }
    }

    // 后续调用从缓存中获取
    if (aspectNames.isEmpty()) {
        return Collections.emptyList();
    }

    List<Advisor> advisors = new ArrayList<>();
    for (String aspectName : aspectNames) {
        if (this.advisorsCache.containsKey(aspectName)) {
            advisors.addAll(this.advisorsCache.get(aspectName));
        }
        else {
            MetadataAwareAspectInstanceFactory factory =
                this.aspectFactoryCache.get(aspectName);
            advisors.addAll(this.advisorFactory.getAdvisors(factory));
        }
    }
    return advisors;
}
```

### 8.2 ReflectiveAspectJAdvisorFactory.getAdvisors()

```java
// org.springframework.aop.aspectj.annotation.ReflectiveAspectJAdvisorFactory
@Override
public List<Advisor> getAdvisors(MetadataAwareAspectInstanceFactory aspectInstanceFactory) {
    Class<?> aspectClass = aspectInstanceFactory.getAspectMetadata().getAspectClass();
    String aspectName = aspectInstanceFactory.getAspectMetadata().getAspectName();
    validate(aspectClass);

    // 包装为 LazySingletonAspectInstanceFactoryDecorator（懒加载单例）
    MetadataAwareAspectInstanceFactory lazySingletonAspectInstanceFactory =
        new LazySingletonAspectInstanceFactoryDecorator(aspectInstanceFactory);

    List<Advisor> advisors = new ArrayList<>();

    // 1. 遍历所有方法（不含 @Pointcut 方法）
    for (Method method : getAdvisorMethods(aspectClass)) {
        // 2. 为每个 Advice 方法创建 Advisor
        Advisor advisor = getAdvisor(method, lazySingletonAspectInstanceFactory,
            0, aspectName);
        if (advisor != null) {
            advisors.add(advisor);
        }
    }

    // 3. 如果没有 Advice，添加一个 SyntheticInstantiationAdvisor
    if (!advisors.isEmpty() && lazySingletonAspectInstanceFactory.getAspectMetadata()
            .isLazilyInstantiated()) {
        Advisor instantiationAdvisor = new SyntheticInstantiationAdvisor(
            lazySingletonAspectInstanceFactory);
        advisors.add(0, instantiationAdvisor);
    }

    // 4. 添加引介通知（@DeclareParents）
    for (Field field : aspectClass.getDeclaredFields()) {
        Advisor advisor = getDeclareParentsAdvisor(field);
        if (advisor != null) {
            advisors.add(advisor);
        }
    }

    return advisors;
}

@Override
public Advisor getAdvisor(Method candidateAdviceMethod,
        MetadataAwareAspectInstanceFactory aspectInstanceFactory,
        int declarationOrderInAspect, String aspectName) {

    validate(aspectInstanceFactory.getAspectMetadata().getAspectClass());

    // 1. 获取切点表达式
    //    解析 @Before/@After/@Around 等注解中的 value（切点表达式）
    AspectJExpressionPointcut expressionPointcut = getPointcut(
        candidateAdviceMethod, aspectInstanceFactory.getAspectMetadata().getAspectClass());

    if (expressionPointcut == null) {
        return null;
    }

    // 2. 创建 InstantiationModelAwarePointcutAdvisorImpl
    //    这是最终包含 Pointcut + Advice 的 Advisor
    return new InstantiationModelAwarePointcutAdvisorImpl(
        expressionPointcut, candidateAdviceMethod,
        this, aspectInstanceFactory, declarationOrderInAspect, aspectName);
}
```

### 8.3 getPointcut() —— 解析通知注解

```java
// org.springframework.aop.aspectj.annotation.ReflectiveAspectJAdvisorFactory
private static final Class<?>[] ASPECTJ_ANNOTATION_CLASSES = new Class<?>[] {
    Pointcut.class,      // @Pointcut
    Before.class,        // @Before
    After.class,         // @After
    AfterReturning.class,// @AfterReturning
    AfterThrowing.class, // @AfterThrowing
    Around.class         // @Around
};

protected AspectJExpressionPointcut getPointcut(Method candidateAdviceMethod,
        Class<?> candidateAspectClass) {
    // 1. 查找方法上的 AspectJ 注解
    AspectJAnnotation<?> aspectJAnnotation =
        AbstractAspectJAdvisorFactory.findAspectJAnnotationOnMethod(candidateAdviceMethod);

    if (aspectJAnnotation == null) {
        return null;
    }

    // 2. 创建 AspectJExpressionPointcut
    AspectJExpressionPointcut ajexp =
        new AspectJExpressionPointcut(candidateAspectClass, new String[0], new Class<?>[0]);

    // 3. 设置切点表达式
    //    对于 @Before("execution(...)")，取注解中的 value
    //    对于 @Before("pointcutName()")，引用 @Pointcut 定义的表达式
    ajexp.setExpression(aspectJAnnotation.getPointcutExpression());

    // 4. 设置 BeanFactory（用于解析 @Pointcut 引用）
    if (this.beanFactory != null) {
        ajexp.setBeanFactory(this.beanFactory);
    }
    return ajexp;
}
```

### 8.4 InstantiationModelAwarePointcutAdvisorImpl

```java
// org.springframework.aop.aspectj.annotation.InstantiationModelAwarePointcutAdvisorImpl
public class InstantiationModelAwarePointcutAdvisorImpl
        implements InstantiationModelAwarePointcutAdvisor, AspectJPrecedenceInformation, Serializable {

    private final Advice advice;                    // 通知（懒加载）
    private final AspectJExpressionPointcut pointcut;  // 切点
    private final AspectJAdvisorFactory advisorFactory;
    private final MetadataAwareAspectInstanceFactory aspectInstanceFactory;
    private final int declarationOrder;
    private final String aspectName;
    private final Pointcut preInstantiationPointcut;

    public InstantiationModelAwarePointcutAdvisorImpl(AspectJExpressionPointcut declaredPointcut,
            Method aspectJAdviceMethod, AspectJAdvisorFactory aspectJAdvisorFactory,
            MetadataAwareAspectInstanceFactory aspectInstanceFactory,
            int declarationOrder, String aspectName) {

        this.pointcut = declaredPointcut;
        this.aspectJAdviceMethod = aspectJAdviceMethod;
        this.advisorFactory = aspectJAdvisorFactory;
        this.aspectInstanceFactory = aspectInstanceFactory;
        this.declarationOrder = declarationOrder;
        this.aspectName = aspectName;

        // 判断是否是懒加载模式（单例切面不是懒加载）
        if (aspectInstanceFactory.getAspectMetadata().isLazilyInstantiated()) {
            Pointcut preInstantiationPointcut = ...;
            this.preInstantiationPointcut = preInstantiationPointcut;
        } else {
            this.preInstantiationPointcut = null;
        }

        // ★ 懒加载获取 Advice
        this.advice = instantiateAdvice(this);
    }

    @Override
    public synchronized Advice getAdvice() {
        if (this.advice == null) {
            this.advice = instantiateAdvice(this);
        }
        return this.advice;
    }

    private Advice instantiateAdvice(InstantiationModelAwarePointcutAdvisorImpl iam) {
        // ★ 根据注解类型创建对应的 Advice
        return advisorFactory.getAdvice(this.aspectJAdviceMethod,
            iam.pointcut, this.aspectInstanceFactory, this.declarationOrder, this.aspectName);
    }
}
```

### 8.5 ReflectiveAspectJAdvisorFactory.getAdvice()

```java
// org.springframework.aop.aspectj.annotation.ReflectiveAspectJAdvisorFactory
@Override
public Advice getAdvice(Method candidateAdviceMethod, AspectJExpressionPointcut aspectJExpressionPointcut,
        MetadataAwareAspectInstanceFactory aspectInstanceFactory,
        int declarationOrder, String aspectName) {

    Class<?> candidateAspectClass = aspectInstanceFactory.getAspectMetadata().getAspectClass();
    validate(candidateAspectClass);

    // 1. 查找通知注解
    AspectJAnnotation<?> aspectJAnnotation =
        AbstractAspectJAdvisorFactory.findAspectJAnnotationOnMethod(candidateAdviceMethod);

    // 2. 根据注解类型创建不同的 Advice
    AbstractAspectJAdvice springAdvice;

    switch (aspectJAnnotation.getAnnotationType()) {
        case AtBefore:
            // @Before → AspectJMethodBeforeAdvice
            springAdvice = new AspectJMethodBeforeAdvice(
                candidateAdviceMethod, aspectJExpressionPointcut, aspectInstanceFactory);
            break;
        case AtAfter:
            // @After → AspectJAfterAdvice（finally 执行）
            springAdvice = new AspectJAfterAdvice(
                candidateAdviceMethod, aspectJExpressionPointcut, aspectInstanceFactory);
            break;
        case AtAfterReturning:
            // @AfterReturning → AspectJAfterReturningAdvice
            springAdvice = new AspectJAfterReturningAdvice(
                candidateAdviceMethod, aspectJExpressionPointcut, aspectInstanceFactory);
            // 处理 returning 属性
            String returningName = ((AfterReturning) aspectJAnnotation.getAnnotation()).returning();
            if (StringUtils.hasText(returningName)) {
                springAdvice.setReturningName(returningName);
            }
            break;
        case AtAfterThrowing:
            // @AfterThrowing → AspectJAfterThrowingAdvice
            springAdvice = new AspectJAfterThrowingAdvice(
                candidateAdviceMethod, aspectJExpressionPointcut, aspectInstanceFactory);
            // 处理 throwing 属性
            String throwingName = ((AfterThrowing) aspectJAnnotation.getAnnotation()).throwing();
            if (StringUtils.hasText(throwingName)) {
                springAdvice.setThrowingName(throwingName);
            }
            break;
        case AtAround:
            // @Around → AspectJAroundAdvice
            springAdvice = new AspectJAroundAdvice(
                candidateAdviceMethod, aspectJExpressionPointcut, aspectInstanceFactory);
            break;
        default:
            throw new UnsupportedOperationException(
                "Unsupported advice type on method: " + candidateAdviceMethod);
    }

    // 3. 设置公共属性
    springAdvice.setAspectName(aspectName);
    springAdvice.setDeclarationOrder(declarationOrder);

    // 4. 处理参数名（用于绑定切点表达式中的参数）
    String[] argNames = this.parameterNameDiscoverer.getParameterNames(candidateAdviceMethod);
    if (argNames != null) {
        springAdvice.setParameterNames(argNames);
    }
    springAdvice.calculateArgumentBindings();

    return springAdvice;
}
```

### 8.6 AspectJMethodBeforeAdvice 的 before() 方法

```java
// org.springframework.aop.aspectj.AspectJMethodBeforeAdvice
public class AspectJMethodBeforeAdvice extends AbstractAspectJAdvice
        implements MethodBeforeAdvice, Serializable {

    @Override
    public void before(Method method, Object[] args, @Nullable Object target) throws Throwable {
        // 调用切面方法（用户写的 @Before 方法）
        invokeAdviceMethod(getJoinPointMatch(), null, null);
    }
}
```

```java
// org.springframework.aop.aspectj.AbstractAspectJAdvice
protected Object invokeAdviceMethod(
        @Nullable JoinPointMatch jpMatch, @Nullable Object returnValue,
        @Nullable Throwable ex) throws Throwable {

    // 绑定参数
    AspectJExpressionPointcut pointcut = getPointcut();
    if (jpMatch != null) {
        // 设置绑定参数（args()、this()、target() 等）
    }

    // 反射调用切面方法
    return invokeAdviceMethodWithGivenArgs(argValues);
}

protected Object invokeAdviceMethodWithGivenArgs(Object[] args) throws Throwable {
    Object[] actualArgs = args;
    if (this.aspectJAdviceMethod.getParameterCount() == 0) {
        actualArgs = null;
    }
    try {
        ReflectionUtils.makeAccessible(this.aspectJAdviceMethod);
        // 通过反射调用用户的 @Before/@After/@Around 方法
        return this.aspectJAdviceMethod.invoke(
            this.aspectInstanceFactory.getAspectInstance(), actualArgs);
    }
    catch (IllegalArgumentException ex) {
        throw new AopInvocationException(
            "Mismatch on arguments to advice method", ex);
    }
    catch (InvocationTargetException ex) {
        throw ex.getTargetException();
    }
}
```

### 8.7 @Around 的 ProceedingJoinPoint

```java
// org.springframework.aop.aspectj.AspectJAroundAdvice
public class AspectJAroundAdvice extends AbstractAspectJAdvice
        implements MethodInterceptor, Serializable {

    @Override
    public Object invoke(MethodInvocation mi) throws Throwable {
        // ProceedingJoinPoint 包装 MethodInvocation
        // 用户在 @Around 方法中调用 pjp.proceed() → mi.proceed()
        ProceedingJoinPoint pjp = lazyGetProceedingJoinPoint(mi);
        JoinPointMatch jpm = getJoinPointMatch(pjp);
        return invokeAdviceMethod(jpm, null, null);
    }

    protected ProceedingJoinPoint lazyGetProceedingJoinPoint(MethodInvocation mi) {
        return new MethodInvocationProceedingJoinPoint(mi);
    }
}
```

```java
// org.springframework.aop.aspectj.MethodInvocationProceedingJoinPoint
public Object proceed() throws Throwable {
    // ★ 这里调用的是 MethodInvocation.proceed()
    //    即继续执行拦截器链中的下一个拦截器
    return this.methodInvocation.proceed();
}
```

**@Around 的执行原理：**

```
@Around 通知方法执行时：
  1. 创建 ProceedingJoinPoint（包装 MethodInvocation）
  2. 调用用户的 @Around 方法
  3. 用户代码执行 @Around 前半部分
  4. 用户调用 pjp.proceed()
     → MethodInvocation.proceed()
     → 继续执行下一个拦截器
     → 最终执行目标方法
     → 返回结果
  5. 用户代码执行 @Around 后半部分
  6. 返回最终结果
```

### 8.8 切面织入完整时序图

```
Spring 启动阶段（容器初始化时）：

registerBeanPostProcessors()
    │
    ▼
注册 AnnotationAwareAspectJAutoProxyCreator 到 BeanFactory
    │
    ▼
finishBeanFactoryInitialization() → 实例化所有单例 Bean
    │
    │  ┌─── 首次触发 AOP 时（shouldSkip 被调用）───┐
    │  │                                              │
    │  │  AnnotationAwareAspectJAutoProxyCreator      │
    │  │    .shouldSkip()                             │
    │  │      │                                       │
    │  │      ▼                                       │
    │  │  findCandidateAdvisors()                      │
    │  │      │                                       │
    │  │      ├── 父类：从容器获取所有 Advisor Bean      │
    │  │      │                                       │
    │  │      └── BeanFactoryAspectJAdvisorsBuilder    │
    │  │            .buildAspectJAdvisors()            │
    │  │              │                               │
    │  │              ├── 扫描所有 @Aspect 类            │
    │  │              │                               │
    │  │              └── ReflectiveAspectJAdvisorFactory│
    │  │                    .getAdvisors()             │
    │  │                      │                       │
    │  │                      ├── 遍历 @Before 方法     │
    │  │                      │   → getAdvisor()       │
    │  │                      │   → InstantiationModelAware│
    │  │                      │     PointcutAdvisorImpl│
    │  │                      │   → getAdvice()        │
    │  │                      │   → AspectJMethodBeforeAdvice│
    │  │                      │                       │
    │  │                      ├── 遍历 @Around 方法     │
    │  │                      │   → AspectJAroundAdvice│
    │  │                      │                       │
    │  │                      └── ...（其他通知类型）     │
    │  │                                              │
    │  │  结果：List<Advisor> 被缓存                    │
    │  └──────────────────────────────────────────────┘
    │
    ▼
对每个 Bean 执行 postProcessAfterInitialization()
    │
    ▼
wrapIfNecessary(bean, beanName, cacheKey)
    │
    ├── getAdvicesAndAdvisorsForBean()
    │     │
    │     ├── findCandidateAdvisors()  ← 从缓存获取
    │     ├── findAdvisorsThatCanApply() ← Pointcut 匹配
    │     │     └── AopUtils.canApply(pointcut, beanClass)
    │     │           ├── ClassFilter.matches()
    │     │           └── MethodMatcher.matches()
    │     └── 返回匹配的 Advisor 列表
    │
    ├── 有匹配的 Advisor？
    │     │
    │   Yes│
    │     ▼
    │   createProxy()
    │     ├── new ProxyFactory()
    │     ├── proxyFactory.addAdvisors(advisors)
    │     ├── proxyFactory.setTargetSource(target)
    │     └── proxyFactory.getProxy()
    │           └── DefaultAopProxyFactory.createAopProxy()
    │                 ├── JdkDynamicAopProxy → JDK Proxy
    │                 └── CglibAopProxy → CGLIB
    │
    └── 返回代理对象（替换原始 Bean 存入容器）
```

---

## 第九部分：@Transactional 事务源码深度解析

### 9.1 声明式事务 vs 编程式事务

| 对比维度 | 声明式事务 | 编程式事务 |
|---------|-----------|-----------|
| 使用方式 | `@Transactional` 注解 | `TransactionTemplate` / `PlatformTransactionManager` API |
| 底层实现 | AOP 代理 + `TransactionInterceptor` | 手动编码 |
| 侵入性 | 无侵入 | 有侵入 |
| 灵活性 | 固定的传播行为和隔离级别 | 完全可编程控制 |
| 适用场景 | 常见 CRUD 场景 | 复杂事务控制场景 |

**声明式事务的本质：**

```
@Transactional 标注在方法上
    → Spring 创建代理对象
    → 方法调用被 TransactionInterceptor 拦截
    → 拦截器在方法前后执行事务管理逻辑
    → 开启事务 → 执行目标方法 → 提交或回滚
```

### 9.2 @Transactional 注解

```java
// org.springframework.transaction.annotation.Transactional
@Target({ElementType.TYPE, ElementType.METHOD})
@Retention(RetentionPolicy.RUNTIME)
@Inherited
@Documented
public @interface Transactional {

    /** 事务管理器 Bean 名称（多数据源时指定） */
    @AliasFor("transactionManager")
    String value() default "";

    @AliasFor("value")
    String transactionManager() default "";

    /**
     * 事务传播行为（7种）
     * 默认 REQUIRED：如果当前没有事务，就新建一个；如果有，就加入当前事务
     */
    Propagation propagation() default Propagation.REQUIRED;

    /**
     * 事务隔离级别
     * 默认 ISOLATION_DEFAULT：使用数据库默认隔离级别
     */
    Isolation isolation() default Isolation.DEFAULT;

    /** 事务超时时间（秒），默认 -1 表示使用数据库默认 */
    int timeout() default -1;

    /** 是否只读事务，默认 false */
    boolean readOnly() default false;

    /**
     * 需要回滚的异常类型（默认只回滚 RuntimeException 和 Error）
     * 设置后，指定的异常也会回滚
     */
    Class<? extends Throwable>[] rollbackFor() default {};

    String[] rollbackForClassName() default {};

    /**
     * 不需要回滚的异常类型
     * 设置后，指定的异常不回滚
     */
    Class<? extends Throwable>[] noRollbackFor() default {};

    String[] noRollbackForClassName() default {};
}
```

### 9.3 事务自动配置（Spring Boot）

```java
// org.springframework.boot.autoconfigure.transaction.TransactionAutoConfiguration
@AutoConfiguration
@ConditionalOnClass(PlatformTransactionManager.class)
public class TransactionAutoConfiguration {

    @Configuration(proxyBeanMethods = false)
    @ConditionalOnBean(PlatformTransactionManager.class)
    protected static class TransactionTemplateConfiguration {
        @Bean
        @ConditionalOnMissingBean(TransactionTemplate.class)
        public TransactionTemplate transactionTemplate(PlatformTransactionManager transactionManager) {
            return new TransactionTemplate(transactionManager);
        }
    }

    @Configuration(proxyBeanMethods = false)
    @ConditionalOnBean(PlatformTransactionManager.class)
    protected static class EnableTransactionManagementConfiguration {
        @Bean
        // ★ 注册 InfrastructureAdvisorAutoProxyCreator
        // 这个 BeanPostProcessor 会在 Bean 创建后检查是否有事务相关的 Advisor
        @ConditionalOnMissingBean(name = "transactionInterceptor")
        public TransactionInterceptor transactionInterceptor(
                TransactionProperties properties) {
            TransactionProperties.TransactionInterceptorProperties interceptorProps =
                properties.getInterceptor();
            TransactionInterceptor interceptor = new TransactionInterceptor();
            // 设置事务属性源
            interceptor.setTransactionAttributeSource(...);
            // 设置事务管理器
            interceptor.setTransactionManagerBeanName(...);
            return interceptor;
        }
    }
}
```

**关键 Bean 注册：**

```
Spring Boot 自动配置注册的关键 Bean：

1. DataSourceTransactionManager (PlatformTransactionManager 实现)
   → 管理数据源的事务

2. TransactionInterceptor (MethodInterceptor 实现)
   → 事务拦截器，拦截 @Transactional 方法
   → 持有 TransactionAttributeSource（解析 @Transactional 属性）
   → 持有 TransactionManager（事务管理器）

3. BeanFactoryTransactionAttributeSourceAdvisor (PointcutAdvisor)
   → pointcut = TransactionAttributeSourcePointcut
   │   → 匹配标注了 @Transactional 的类/方法
   → advice = TransactionInterceptor

4. InfrastructureAdvisorAutoProxyCreator (BeanPostProcessor)
   → 等价于 AnnotationAwareAspectJAutoProxyCreator
   → 扫描容器中的 Advisor，为匹配的 Bean 创建代理
```

### 9.4 事务相关的 PointcutAdvisor

```java
// org.springframework.transaction.interceptor.BeanFactoryTransactionAttributeSourceAdvisor
public class BeanFactoryTransactionAttributeSourceAdvisor
        extends AbstractBeanFactoryPointcutAdvisor {

    private TransactionAttributeSource transactionAttributeSource;

    private final TransactionAttributeSourcePointcut pointcut = new
        TransactionAttributeSourcePointcut() {
        @Override
        @Nullable
        protected TransactionAttributeSource getTransactionAttributeSource() {
            return transactionAttributeSource;
        }
    };

    public void setTransactionAttributeSource(
            TransactionAttributeSource transactionAttributeSource) {
        this.transactionAttributeSource = transactionAttributeSource;
    }

    @Override
    public Pointcut getPointcut() {
        return this.pointcut;
    }
}
```

```java
// org.springframework.transaction.interceptor.TransactionAttributeSourcePointcut
abstract class TransactionAttributeSourcePointcut extends StaticMethodMatcherPointcut {

    protected TransactionAttributeSourcePointcut() {
        setClassFilter(new TransactionAttributeSourceClassFilter());
    }

    @Override
    public boolean matches(Method method, Class<?> targetClass) {
        // 获取 TransactionAttributeSource
        TransactionAttributeSource tas = getTransactionAttributeSource();
        // ★ 如果能从方法上解析出 @Transactional 属性，说明匹配
        return (tas == null || tas.getTransactionAttribute(method, targetClass) != null);
    }

    private class TransactionAttributeSourceClassFilter implements ClassFilter {
        @Override
        public boolean matches(Class<?> clazz) {
            // 优化：排除明显的非事务类
            if (TransactionalProxy.class.isAssignableFrom(clazz) ||
                    TransactionManager.class.isAssignableFrom(clazz) ||
                    PersistenceExceptionTranslator.class.isAssignableFrom(clazz)) {
                return false;
            }
            TransactionAttributeSource tas = getTransactionAttributeSource();
            // ★ 检查类级别是否有 @Transactional
            return (tas == null || tas.isCandidateClass(clazz));
        }
    }
}
```

### 9.5 AnnotationTransactionAttributeSource —— 解析 @Transactional

```java
// org.springframework.transaction.annotation.AnnotationTransactionAttributeSource
public class AnnotationTransactionAttributeSource
        extends AbstractFallbackTransactionAttributeSource
        implements Serializable {

    private final boolean publicMethodsOnly;
    private final Set<TransactionAnnotationParser> annotationParsers;

    public AnnotationTransactionAttributeSource() {
        this(true);
    }

    public AnnotationTransactionAttributeSource(boolean publicMethodsOnly) {
        this.publicMethodsOnly = publicMethodsOnly;
        // 注册注解解析器
        this.annotationParsers = new LinkedHashSet<>(2);
        // Spring 的 @Transactional 解析器
        this.annotationParsers.add(new SpringTransactionAnnotationParser());
        // 如果类路径有 javax.transaction.Transactional（JTA），也注册
        if (jtaTransactionPresent) {
            this.annotationParsers.add(new JtaTransactionAnnotationParser());
        }
        // 如果有 EJB 的 TransactionAttribute，也注册
        if (ejb3TransactionPresent) {
            this.annotationParsers.add(new Ejb3TransactionAnnotationParser());
        }
    }

    @Override
    public boolean isCandidateClass(Class<?> targetClass) {
        for (TransactionAnnotationParser parser : this.annotationParsers) {
            if (parser.isCandidateClass(targetClass)) {
                return true;
            }
        }
        return false;
    }

    @Override
    @Nullable
    protected TransactionAttribute computeTransactionAttribute(
            Method method, @Nullable Class<?> targetClass) {

        // 1. 如果只允许 public 方法，且方法不是 public，跳过
        if (this.publicMethodsOnly && !Modifier.isPublic(method.getModifiers())) {
            return null;
        }

        // 2. 获取最具体的方法（可能来自接口）
        Method specificMethod = AopUtils.getMostSpecificMethod(method, targetClass);

        // 3. 先从方法上找 @Transactional
        TransactionAttribute txAttr = findTransactionAttribute(specificMethod);
        if (txAttr != null) {
            return txAttr;
        }

        // 4. 方法上没有，从类上找 @Transactional
        txAttr = findTransactionAttribute(specificMethod.getDeclaringClass());
        if (txAttr != null && ClassUtils.isUserLevelMethod(method)) {
            return txAttr;
        }

        // 5. 如果是接口方法，检查实现类
        if (specificMethod != method) {
            txAttr = findTransactionAttribute(method);
            if (txAttr != null) {
                return txAttr;
            }
            txAttr = findTransactionAttribute(method.getDeclaringClass());
            if (txAttr != null && ClassUtils.isUserLevelMethod(method)) {
                return txAttr;
            }
        }

        return null;
    }

    @Override
    @Nullable
    protected TransactionAttribute findTransactionAttribute(Class<?> clazz) {
        return determineTransactionAttribute(clazz);
    }

    @Override
    @Nullable
    protected TransactionAttribute findTransactionAttribute(Method method) {
        return determineTransactionAttribute(method);
    }

    protected TransactionAttribute determineTransactionAttribute(AnnotatedElement element) {
        // 遍历注解解析器，找到 @Transactional 并解析
        for (TransactionAnnotationParser parser : this.annotationParsers) {
            TransactionAttribute attr = parser.parseTransactionAnnotation(element);
            if (attr != null) {
                return attr;
            }
        }
        return null;
    }
}
```

### 9.6 SpringTransactionAnnotationParser

```java
// org.springframework.transaction.annotation.SpringTransactionAnnotationParser
public class SpringTransactionAnnotationParser
        implements TransactionAnnotationParser, Serializable {

    @Override
    public boolean isCandidateClass(Class<?> targetClass) {
        return AnnotationUtils.isCandidateClass(targetClass, Transactional.class);
    }

    @Override
    @Nullable
    public TransactionAttribute parseTransactionAnnotation(AnnotatedElement element) {
        // 获取方法/类上的 @Transactional 注解
        Transactional ann = AnnotatedElementUtils.findMergedAnnotation(element, Transactional.class);
        if (ann != null) {
            // 解析注解属性
            return parseTransactionAnnotation(ann);
        }
        return null;
    }

    public TransactionAttribute parseTransactionAnnotation(Transactional ann) {
        RuleBasedTransactionAttribute rbta = new RuleBasedTransactionAttribute();

        // 解析传播行为
        rbta.setPropagationBehavior(ann.propagation().value());

        // 解析隔离级别
        rbta.setIsolationLevel(ann.isolation().value());

        // 解析超时
        rbta.setTimeout(ann.timeout());

        // 解析只读
        rbta.setReadOnly(ann.readOnly());

        // 解析事务管理器
        rbta.setQualifier(ann.transactionManager());

        // 解析回滚规则
        List<RollbackRuleAttribute> rollbackRules = new ArrayList<>();
        for (Class<?> rbRule : ann.rollbackFor()) {
            rollbackRules.add(new RollbackRuleAttribute(rbRule));
        }
        for (String rbRule : ann.rollbackForClassName()) {
            rollbackRules.add(new RollbackRuleAttribute(rbRule));
        }
        for (Class<?> rbRule : ann.noRollbackFor()) {
            rollbackRules.add(new NoRollbackRuleAttribute(rbRule));
        }
        rbta.setRollbackRules(rollbackRules);

        return rbta;
    }
}
```

### 9.7 TransactionInterceptor —— 事务拦截器

`TransactionInterceptor` 是整个声明式事务的核心，它实现了 `MethodInterceptor`，在方法调用时管理事务。

```java
// org.springframework.transaction.interceptor.TransactionInterceptor
public class TransactionInterceptor extends TransactionAspectSupport
        implements MethodInterceptor, Serializable {

    @Override
    @Nullable
    public Object invoke(MethodInvocation invocation) throws Throwable {
        // 1. 获取目标类
        Class<?> targetClass = (invocation.getThis() != null ?
                AopUtils.getTargetClass(invocation.getThis()) : null);

        // 2. ★ 调用父类的 invokeWithinTransaction()
        return invokeWithinTransaction(invocation.getMethod(), targetClass,
            new CoroutinesInvocationCallback() {
                @Override
                @Nullable
                public Object proceedWithInvocation() throws Throwable {
                    return invocation.proceed();  // 继续执行拦截器链（最终执行目标方法）
                }
                // ...
            });
    }
}
```

### 9.8 invokeWithinTransaction() —— 核心事务流程

这是整个声明式事务最核心的方法，理解了它就理解了 @Transactional 的全部原理：

```java
// org.springframework.transaction.interceptor.TransactionAspectSupport
@Nullable
protected Object invokeWithinTransaction(Method method, @Nullable Class<?> targetClass,
        final InvocationCallback invocation) throws Throwable {

    // ===== 1. 获取事务属性（@Transactional 的配置） =====
    // TransactionAttributeSource 解析 @Transactional 注解
    TransactionAttributeSource tas = getTransactionAttributeSource();
    final TransactionAttribute txAttr = (tas != null ?
            tas.getTransactionAttribute(method, targetClass) : null);

    // ===== 2. 获取事务管理器 =====
    final TransactionManager tm = determineTransactionManager(txAttr);

    // ===== 3. 准备事务信息 =====
    // 创建 TransactionInfo，包含事务管理器、事务属性、方法标识
    PlatformTransactionManager ptm = asPlatformTransactionManager(tm);
    final String joinpointIdentification = methodIdentification(method, targetClass, txAttr);

    // ===== 4. 根据传播行为决定是否创建事务 =====
    TransactionInfo txInfo = createTransactionIfNecessary(ptm, txAttr, joinpointIdentification);

    Object retVal;
    try {
        // ===== 5. 执行目标方法 =====
        // This is an around advice: invoke the next interceptor in the chain.
        // This will normally result in a target object being invoked.
        retVal = invocation.proceedWithInvocation();
    }
    catch (Throwable ex) {
        // ===== 6a. 异常处理：回滚或提交 =====
        // completeTransactionAfterThrowing 会检查异常是否匹配回滚规则
        completeTransactionAfterThrowing(txInfo, ex);
        throw ex;
    }
    finally {
        // ===== 6b. 清理事务信息 =====
        cleanupTransactionInfo(txInfo);
    }

    // ===== 7. 正常返回：提交事务 =====
    if (retVal != null && vavrPresent && ... ) {
        // Vavr Try 类型处理（特殊场景）
    }

    // ★ 提交事务
    commitTransactionAfterReturning(txInfo);

    return retVal;
}
```

**流程图：**

```
invokeWithinTransaction()
    │
    ▼
1. 获取 TransactionAttribute（@Transactional 属性）
    │
    ▼
2. 获取 PlatformTransactionManager
    │
    ▼
3. createTransactionIfNecessary()
    │  ├── 根据 propagation 决定是否开启新事务
    │  ├── getTransaction() → doBegin() → 开启数据库事务
    │  ├── bind Resources → DataSource → Connection 绑定到 ThreadLocal
    │  └── 返回 TransactionInfo
    │
    ▼
4. invocation.proceedWithInvocation()  → 执行目标方法
    │
    ├─── 正常返回 ──────────────────────┐
    │                                    │
    │                                    ▼
    │                          5a. commitTransactionAfterReturning()
    │                              ├── txInfo.getTransactionManager().commit()
    │                              │   ├── doCommit() → 数据库 COMMIT
    │                              │   └── doCleanupAfterCompletion()
    │                              │       → 解绑 ThreadLocal 中的 Connection
    │                              └── 返回结果
    │
    └─── 抛出异常 ──────────────────────┐
                                         │
                                         ▼
                               5b. completeTransactionAfterThrowing()
                                   ├── 检查异常是否匹配回滚规则
                                   │   ├── rollbackFor 中有此异常 → 回滚
                                   │   ├── noRollbackFor 中有此异常 → 提交
                                   │   └── 默认：RuntimeException/Error → 回滚
                                   ├── 需要回滚：
                                   │   ├── rollback()
                                   │   │   ├── doRollback() → 数据库 ROLLBACK
                                   │   │   └── doCleanupAfterCompletion()
                                   │   └── 触发 TransactionSynchronization.afterCompletion(ROLLED_BACK)
                                   └── 不需要回滚：
                                       └── commit()
    │
    ▼
6. cleanupTransactionInfo()
    └── 恢复旧的事务信息（ThreadLocal 回退）
```

### 9.9 createTransactionIfNecessary()

```java
// org.springframework.transaction.interceptor.TransactionAspectSupport
protected TransactionInfo createTransactionIfNecessary(
        @Nullable PlatformTransactionManager tm,
        @Nullable TransactionAttribute txAttr, final String joinpointIdentification) {

    // 如果没有指定事务名，用方法标识作为事务名
    if (txAttr != null && txAttr.getName() == null) {
        txAttr = new DelegatingTransactionAttribute(txAttr) {
            @Override
            public String getName() {
                return joinpointIdentification;
            }
        };
    }

    TransactionStatus status = null;
    if (txAttr != null) {
        if (tm != null) {
            // ★ 获取事务状态（核心！内部会调用 doBegin 开启事务）
            status = tm.getTransaction(txAttr);
        }
        else {
            // 没有事务管理器，只记录
        }
    }

    // 创建 TransactionInfo，保存当前状态和旧状态
    // prepareTransactionInfo 会将 txInfo 绑定到 ThreadLocal
    return prepareTransactionInfo(tm, txAttr, joinpointIdentification, status);
}
```

### 9.10 AbstractPlatformTransactionManager.getTransaction()

```java
// org.springframework.transaction.support.AbstractPlatformTransactionManager
@Override
public final TransactionStatus getTransaction(@Nullable TransactionDefinition definition)
        throws TransactionException {

    // 使用默认的事务定义
    TransactionDefinition def = (definition != null ? definition :
            TransactionDefinition.withDefaults());

    // ★ 1. 获取当前事务（doGetTransaction 由子类实现）
    Object transaction = doGetTransaction();

    // 2. 检查是否已存在事务（嵌套调用时）
    if (isExistingTransaction(transaction)) {
        // ★ 存在事务，根据传播行为处理
        return handleExistingTransaction(def, transaction, debugEnabled);
    }

    // 3. 没有已存在的事务

    // 检查超时
    if (def.getTimeout() < TransactionDefinition.TIMEOUT_DEFAULT) {
        throw new InvalidTimeoutException("Invalid transaction timeout", def.getTimeout());
    }

    // ★ 4. 处理特殊传播行为
    if (def.getPropagationBehavior() == TransactionDefinition.PROPAGATION_MANDATORY) {
        // MANDATORY：必须在事务中，但当前没有事务 → 抛异常
        throw new IllegalTransactionStateException(
            "No existing transaction found for transaction marked with propagation 'mandatory'");
    }
    else if (def.getPropagationBehavior() == TransactionDefinition.PROPAGATION_REQUIRED ||
             def.getPropagationBehavior() == TransactionDefinition.PROPAGATION_REQUIRES_NEW ||
             def.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NESTED) {

        // ★ REQUIRED / REQUIRES_NEW / NESTED：没有事务就新建一个
        // 挂起当前事务（如果有）
        SuspendedResourcesHolder suspendedResources = suspend(null);
        try {
            // 开启新事务
            return startTransaction(def, transaction, debugEnabled, suspendedResources);
        }
        catch (RuntimeException | Error ex) {
            resume(null, suspendedResources);
            throw ex;
        }
    }
    else {
        // PROPAGATION_SUPPORTS / PROPAGATION_NOT_SUPPORTED / PROPAGATION_NEVER
        // 这些传播行为不需要实际开启事务
        boolean newSynchronization = (getTransactionSynchronization() ==
            SYNCHRONIZATION_ALWAYS);
        return prepareTransactionStatus(def, null, true, newSynchronization,
            debugEnabled, null);
    }
}

private TransactionStatus startTransaction(TransactionDefinition definition,
        Object transaction, boolean debugEnabled,
        @Nullable SuspendedResourcesHolder suspendedResources) {

    boolean newSynchronization = (getTransactionSynchronization() != SYNCHRONIZATION_NEVER);
    // ★ 创建新的事务状态
    DefaultTransactionStatus status = newTransactionStatus(
        definition, transaction, true,
        newSynchronization, debugEnabled, suspendedResources);

    // ★ 执行 doBegin（由子类实现，真正开启事务）
    doBegin(transaction, definition);
    prepareSynchronization(status, definition);
    return status;
}
```

### 9.11 handleExistingTransaction() —— 处理嵌套事务

```java
// org.springframework.transaction.support.AbstractPlatformTransactionManager
private TransactionStatus handleExistingTransaction(
        TransactionDefinition definition, Object transaction, boolean debugEnabled)
        throws TransactionException {

    // ★ 1. PROPAGATION_NEVER：已有事务，不允许 → 抛异常
    if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NEVER) {
        throw new IllegalTransactionStateException(
            "Existing transaction found for transaction marked with propagation 'never'");
    }

    // ★ 2. PROPAGATION_NOT_SUPPORTED：以非事务方式执行，挂起当前事务
    if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NOT_SUPPORTED) {
        Object suspendedResources = suspend(transaction);
        boolean newSynchronization = (getTransactionSynchronization() == SYNCHRONIZATION_ALWAYS);
        return prepareTransactionStatus(definition, null, false,
            newSynchronization, debugEnabled, suspendedResources);
    }

    // ★ 3. PROPAGATION_REQUIRES_NEW：总是新建事务，挂起当前事务
    if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_REQUIRES_NEW) {
        SuspendedResourcesHolder suspendedResources = suspend(transaction);
        try {
            return startTransaction(definition, transaction, debugEnabled, suspendedResources);
        }
        catch (RuntimeException | Error beginEx) {
            resumeAfterBeginException(transaction, suspendedResources, beginEx);
            throw beginEx;
        }
    }

    // ★ 4. PROPAGATION_NESTED：嵌套事务（保存点）
    if (definition.getPropagationBehavior() == TransactionDefinition.PROPAGATION_NESTED) {
        if (!isNestedTransactionAllowed()) {
            throw new NestedTransactionNotSupportedException(
                "Transaction manager does not allow nested transactions");
        }
        if (useSavepointForNestedTransaction()) {
            // ★ 使用保存点（Savepoint）实现嵌套事务
            DefaultTransactionStatus status = prepareTransactionStatus(
                definition, transaction, false, false, debugEnabled, null);
            status.createAndHoldSavepoint();  // 创建保存点
            return status;
        }
        else {
            // 使用 JTA 嵌套事务
            return startTransaction(definition, transaction, debugEnabled, null);
        }
    }

    // ★ 5. PROPAGATION_REQUIRED / PROPAGATION_SUPPORTS：
    //    加入当前事务（不新建）
    boolean newSynchronization = (getTransactionSynchronization() != SYNCHRONIZATION_NEVER);
    return prepareTransactionStatus(definition, transaction, false,
        newSynchronization, debugEnabled, null);
}
```

### 9.12 七种事务传播行为总结

```java
// org.springframework.transaction.TransactionDefinition
int PROPAGATION_REQUIRED = 0;      // 默认
int PROPAGATION_SUPPORTS = 1;
int PROPAGATION_MANDATORY = 2;
int PROPAGATION_REQUIRES_NEW = 3;
int PROPAGATION_NOT_SUPPORTED = 4;
int PROPAGATION_NEVER = 5;
int PROPAGATION_NESTED = 6;
```

| 传播行为 | 当前有事务 | 当前无事务 | 说明 |
|---------|-----------|-----------|------|
| **REQUIRED**（默认） | 加入当前事务 | 新建事务 | 最常用，支持事务复用 |
| **SUPPORTS** | 加入当前事务 | 以非事务方式执行 | 只读场景适用 |
| **MANDATORY** | 加入当前事务 | 抛异常 | 强制要求在事务中 |
| **REQUIRES_NEW** | 挂起当前事务，新建事务 | 新建事务 | 独立事务，不受外层影响 |
| **NOT_SUPPORTED** | 挂起当前事务，以非事务方式执行 | 以非事务方式执行 | 不需要事务的场景 |
| **NEVER** | 抛异常 | 以非事务方式执行 | 强制要求不在事务中 |
| **NESTED** | 创建保存点（嵌套事务） | 新建事务 | 可独立回滚的子事务 |

**传播行为执行流程图（以 REQUIRED 和 REQUIRES_NEW 为例）：**

```
场景：methodA() 调用 methodB()，methodA 有 @Transactional(propagation=REQUIRED)
      methodB 有 @Transactional(propagation=REQUIRES_NEW)

methodA() 调用代理对象
    │
    ▼
TransactionInterceptor.invoke()
    │
    ├── 获取事务属性 → REQUIRED
    ├── 当前无事务 → 新建事务 A
    │   ├── Connection.setAutoCommit(false)
    │   └── 绑定 Connection 到 ThreadLocal
    │
    ├── 执行 methodA 代码
    │   │
    │   │  调用 methodB()（也走代理）
    │   │      │
    │   │      ▼
    │   │  TransactionInterceptor.invoke()
    │   │      │
    │   │      ├── 获取事务属性 → REQUIRES_NEW
    │   │      ├── 当前有事务 A → 挂起事务 A
    │   │      │   ├── 保存旧 Connection，从 ThreadLocal 移除
    │   │      │   └── 新建事务 B
    │   │      │       ├── 获取新 Connection
    │   │      │       ├── Connection.setAutoCommit(false)
    │   │      │       └── 绑定新 Connection 到 ThreadLocal
    │   │      │
    │   │      ├── 执行 methodB 代码
    │   │      │   └── 使用新 Connection（事务 B）
    │   │      │
    │   │      ├── methodB 正常返回 → 提交事务 B
    │   │      │   ├── Connection.commit()
    │   │      │   └── 恢复事务 A 的 Connection 到 ThreadLocal
    │   │      │
    │   │      └── 返回结果给 methodA
    │   │
    │   ├── methodA 继续执行（使用事务 A 的 Connection）
    │   │
    ├── methodA 正常返回 → 提交事务 A
    │   └── Connection.commit()
    │
    └── 返回结果
```

**关键点：** REQUIRES_NEW 会**挂起**外层事务（从 ThreadLocal 移除 Connection），创建一个全新的 Connection 和事务。内层事务的提交/回滚完全独立于外层事务。

### 9.13 DataSourceTransactionManager.doBegin() —— 真正开启事务

```java
// org.springframework.jdbc.datasource.DataSourceTransactionManager
@Override
protected void doBegin(Object transaction, TransactionDefinition definition) {
    DataSourceTransactionObject txObject = (DataSourceTransactionObject) transaction;
    Connection con = null;

    try {
        // 1. 获取数据库连接
        if (!txObject.hasConnectionHolder() ||
                txObject.getConnectionHolder().isSynchronizedWithTransaction()) {
            Connection newCon = obtainDataSource().getConnection();
            txObject.setConnectionHolder(new ConnectionHolder(newCon), true);
        }

        txObject.getConnectionHolder().setSynchronizedWithTransaction(true);
        con = txObject.getConnectionHolder().getConnection();

        // 2. 设置隔离级别和只读
        Integer previousIsolationLevel = DataSourceUtils.prepareConnectionForTransaction(
            con, definition);
        txObject.setPreviousIsolationLevel(previousIsolationLevel);

        // 3. 设置是否自动提交（关闭自动提交 = 开启事务）
        if (con.getAutoCommit()) {
            txObject.setMustRestoreAutoCommit(true);
            con.setAutoCommit(false);  // ★ 关键：关闭自动提交
        }

        // 4. 如果是只读事务，执行 SET TRANSACTION READ ONLY
        prepareTransactionalConnection(con, definition);
        txObject.getConnectionHolder().setTransactionActive(true);

        // 5. 将 Connection 绑定到 ThreadLocal
        // ★ 这是事务管理的核心：通过 ThreadLocal 实现"同一事务用同一连接"
        if (txObject.isNewConnectionHolder()) {
            TransactionSynchronizationManager.bindResource(
                obtainDataSource(), txObject.getConnectionHolder());
        }
    }
    catch (Throwable ex) {
        // 异常处理：释放连接
        if (txObject.isNewConnectionHolder()) {
            DataSourceUtils.releaseConnection(con, obtainDataSource());
            txObject.setConnectionHolder(null, false);
        }
        throw new CannotCreateTransactionException(
            "Could not open JDBC Connection for transaction", ex);
    }
}

@Override
protected Object doGetTransaction() {
    DataSourceTransactionObject txObject = new DataSourceTransactionObject();
    txObject.setSavepointAllowed(isNestedTransactionAllowed());

    // ★ 从 ThreadLocal 中获取已绑定的 ConnectionHolder
    // 如果当前线程已绑定了 Connection，说明已有事务
    ConnectionHolder conHolder = (ConnectionHolder) TransactionSynchronizationManager
        .getResource(obtainDataSource());
    txObject.setConnectionHolder(conHolder, false);
    return txObject;
}

@Override
protected boolean isExistingTransaction(Object transaction) {
    DataSourceTransactionObject txObject = (DataSourceTransactionObject) transaction;
    // ★ 判断是否已有事务：ConnectionHolder 不为 null 且标记为事务活跃
    return (txObject.hasConnectionHolder() &&
            txObject.getConnectionHolder().isTransactionActive());
}
```

### 9.14 TransactionSynchronizationManager —— 事务同步管理器

`TransactionSynchronizationManager` 是整个事务体系的核心枢纽，它通过 ThreadLocal 管理事务资源：

```java
// org.springframework.transaction.support.TransactionSynchronizationManager
public abstract class TransactionSynchronizationManager {

    // ★ 核心 ThreadLocal：事务资源
    // key = DataSource, value = ConnectionHolder
    // 通过这个 Map，同一个线程在同一事务中获取到的是同一个 Connection
    private static final ThreadLocal<Map<Object, Object>> resources =
        new NamedThreadLocal<>("Transactional resources");

    // 事务同步回调列表
    private static final ThreadLocal<Set<TransactionSynchronization>> synchronizations =
        new NamedThreadLocal<>("Transaction synchronizations");

    // 当前事务名称
    private static final ThreadLocal<String> currentTransactionName =
        new NamedThreadLocal<>("Current transaction name");

    // 当前事务是否只读
    private static final ThreadLocal<Boolean> currentTransactionReadOnly =
        new NamedThreadLocal<>("Current transaction read-only status");

    // 当前事务隔离级别
    private static final ThreadLocal<Integer> currentTransactionIsolationLevel =
        new NamedThreadLocal<>("Current transaction isolation level");

    // 当前事务是否活跃
    private static final ThreadLocal<Boolean> actualTransactionActive =
        new NamedThreadLocal<>("Actual transaction active");

    // 绑定资源（DataSource → ConnectionHolder）
    public static void bindResource(Object key, Object value) throws IllegalStateException {
        Object actualKey = TransactionSynchronizationUtils.unwrapResourceIfNecessary(key);
        Map<Object, Object> map = resources.get();
        if (map == null) {
            map = new HashMap<>();
            resources.set(map);
        }
        Object oldValue = map.put(actualKey, value);
        // ...
    }

    // 获取资源
    @Nullable
    public static Object getResource(Object key) {
        Object actualKey = TransactionSynchronizationUtils.unwrapResourceIfNecessary(key);
        return doGetResource(actualKey);
    }

    private static Object doGetResource(Object actualKey) {
        Map<Object, Object> map = resources.get();
        if (map == null) {
            return null;
        }
        return map.get(actualKey);
    }

    // 解绑资源
    public static Object unbindResource(Object key) {
        Object actualKey = TransactionSynchronizationUtils.unwrapResourceIfNecessary(key);
        Map<Object, Object> map = resources.get();
        Object value = map.remove(actualKey);
        if (map.isEmpty()) {
            resources.remove();
        }
        return value;
    }
}
```

**事务资源绑定流程：**

```
doBegin() 开启事务时：
    ┌─────────────────────────────────────────────────────┐
    │ ThreadLocal<Map<Object, Object>> resources           │
    │                                                      │
    │  ┌────────────────┬─────────────────────────────┐   │
    │  │ Key            │ Value                        │   │
    │  ├────────────────┼─────────────────────────────┤   │
    │  │ DataSource     │ ConnectionHolder             │   │
    │  │ (HikariDS)     │  ├── Connection (conn1)      │   │
    │  │                │  ├── transactionActive=true  │   │
    │  │                │  └── ...                     │   │
    │  └────────────────┴─────────────────────────────┘   │
    └─────────────────────────────────────────────────────┘
                            ▲
                            │ 绑定
                            │
    同一事务中的所有 DAO 通过 DataSourceUtils.getConnection()
    从 ThreadLocal 获取同一个 Connection
```

**为什么需要 ThreadLocal？**

因为 Spring 的事务管理是基于 AOP 代理的，代理层开启事务后，实际执行 SQL 的 DAO 层需要获取同一个 Connection 才能保证在同一事务中。ThreadLocal 保证了同一线程内的 Connection 共享。

### 9.15 completeTransactionAfterThrowing() —— 异常回滚

```java
// org.springframework.transaction.interceptor.TransactionAspectSupport
protected void completeTransactionAfterThrowing(
        @Nullable TransactionInfo txInfo, Throwable ex) {

    if (txInfo != null && txInfo.getTransactionStatus() != null) {
        if (logger.isTraceEnabled()) {
            logger.trace("Completing transaction for [" + txInfo.getJoinpointIdentification() +
                    "] after exception: " + ex);
        }

        // ★ 检查是否需要回滚
        if (txInfo.transactionAttribute != null &&
                txInfo.transactionAttribute.rollbackOn(ex)) {
            try {
                // ★ 执行回滚
                txInfo.getTransactionManager().rollback(txInfo.getTransactionStatus());
            }
            catch (TransactionSystemException tse) {
                logger.error("Application exception overridden by rollback exception", ex);
                throw tse;
            }
            catch (RuntimeException | Error rre) {
                logger.error("Application exception overridden by rollback exception", ex);
                throw rre;
            }
        }
        else {
            // 异常不匹配回滚规则，仍然提交
            try {
                txInfo.getTransactionManager().commit(txInfo.getTransactionStatus());
            }
            catch (TransactionSystemException tse) {
                logger.error("Application exception overridden by commit exception", ex);
                throw tse;
            }
            catch (RuntimeException | Error rre) {
                logger.error("Application exception overridden by commit exception", ex);
                throw rre;
            }
        }
    }
}
```

**回滚规则判断：**

```java
// org.springframework.transaction.interceptor.RuleBasedTransactionAttribute
@Override
public boolean rollbackOn(Throwable ex) {
    // ★ 检查回滚规则列表
    RollbackRuleAttribute winner = null;
    int deepest = Integer.MAX_VALUE;

    if (this.rollbackRules != null) {
        for (RollbackRuleAttribute rule : this.rollbackRules) {
            int depth = rule.getDepth(ex);
            if (depth >= 0 && depth < deepest) {
                deepest = depth;
                winner = rule;
            }
        }
    }

    if (winner == null) {
        // ★ 没有匹配的规则，使用默认规则
        // 默认：RuntimeException 和 Error 回滚
        return super.rollbackOn(ex);
    }

    // ★ 如果匹配的是 NoRollbackRuleAttribute，不回滚
    return !(winner instanceof NoRollbackRuleAttribute);
}

// 父类 DefaultTransactionAttribute
@Override
public boolean rollbackOn(Throwable ex) {
    // ★ 默认行为：RuntimeException 和 Error 回滚
    return (ex instanceof RuntimeException || ex instanceof Error);
}
```

**回滚规则匹配优先级：**

```
异常继承链深度（ex 到 rollbackFor 声明的异常类的距离）越小，优先级越高

示例：
@Transactional(rollbackFor = IOException.class, noRollbackFor = FileNotFoundException.class)

抛出 FileNotFoundException 时：
  - rollbackFor 中 IOException 的 depth = 1（FileNotFoundException → IOException）
  - noRollbackFor 中 FileNotFoundException 的 depth = 0（精确匹配）
  → depth 0 更浅 → winner = NoRollbackRuleAttribute → 不回滚

抛出 SocketException 时：
  - rollbackFor 中 IOException 的 depth = 1（SocketException → IOException）
  - noRollbackFor 中无匹配
  → winner = RollbackRuleAttribute → 回滚
```

### 9.16 AbstractPlatformTransactionManager.rollback() —— 执行回滚

```java
// org.springframework.transaction.support.AbstractPlatformTransactionManager
@Override
public final void rollback(TransactionStatus status) throws TransactionException {
    if (status.isCompleted()) {
        throw new IllegalTransactionStateException(
            "Transaction is already completed - do not call commit or rollback");
    }

    DefaultTransactionStatus defStatus = (DefaultTransactionStatus) status;

    processRollback(defStatus, false);
}

private void processRollback(DefaultTransactionStatus status, boolean unexpected) {
    try {
        boolean unexpectedRollback = unexpected;

        try {
            // 1. 触发 beforeCompletion 回调
            triggerBeforeCompletion(status);

            // 2. 如果有保存点，回滚到保存点
            if (status.hasSavepoint()) {
                status.releaseHeldSavepoint();
            }
            // 3. 如果是新事务，执行回滚
            else if (status.isNewTransaction()) {
                // ★ doRollback 由子类实现
                doRollback(status);
            }
            else {
                // 4. 不是新事务（加入了已有事务），标记为全局回滚
                if (status.hasTransaction()) {
                    if (status.isLocalRollbackOnly() || isGlobalRollbackOnParticipationFailure()) {
                        doSetRollbackOnly(status);
                    }
                }
                else {
                    // 没有事务，只是同步
                }
                unexpectedRollback = false;
            }
        }
        catch (RuntimeException | Error ex) {
            triggerAfterCompletion(status, TransactionSynchronization.STATUS_UNKNOWN);
            throw ex;
        }
        catch (Throwable ex) {
            triggerAfterCompletion(status, TransactionSynchronization.STATUS_UNKNOWN);
            throw new UnexpectedRollbackException(
                "Transaction rolled back because it has been marked as rollback-only", ex);
        }

        // 5. 触发 afterCompletion 回调
        triggerAfterCompletion(status, TransactionSynchronization.STATUS_ROLLED_BACK);

        // 6. 清理
        if (status.isNewSynchronization()) {
            transactionSynchronizationManager.clearSynchronization();
        }

        // 7. 如果是挂起的事务，恢复
        if (status.isNewTransaction()) {
            doCleanupAfterCompletion(status);
        }

        if (unexpectedRollback) {
            throw new UnexpectedRollbackException(
                "Transaction rolled back because it has been marked as rollback-only");
        }
    }
    finally {
        cleanupAfterCompletion(status);
    }
}
```

```java
// DataSourceTransactionManager.doRollback()
@Override
protected void doRollback(DefaultTransactionStatus status) {
    DataSourceTransactionObject txObject = (DataSourceTransactionObject) status.getTransaction();
    Connection con = txObject.getConnectionHolder().getConnection();
    if (status.isDebug()) {
        logger.debug("Rolling back JDBC transaction on Connection [" + con + "]");
    }
    try {
        // ★ 执行数据库 ROLLBACK
        con.rollback();
    }
    catch (SQLException ex) {
        throw new TransactionSystemException("Could not roll back JDBC transaction", ex);
    }
}

@Override
protected void doCleanupAfterCompletion(Object transaction) {
    DataSourceTransactionObject txObject = (DataSourceTransactionObject) transaction;

    // 1. 解绑 DataSource → ConnectionHolder
    if (txObject.isNewConnectionHolder()) {
        TransactionSynchronizationManager.unbindResource(obtainDataSource());
    }

    // 2. 恢复 Connection 配置
    Connection con = txObject.getConnectionHolder().getConnection();
    try {
        // 恢复自动提交
        if (txObject.isMustRestoreAutoCommit()) {
            con.setAutoCommit(true);
        }
        // 恢复隔离级别
        DataSourceUtils.resetConnectionAfterTransaction(
            con, txObject.getPreviousIsolationLevel());
    }
    catch (Throwable ex) {
        logger.debug("Could not reset JDBC Connection after transaction", ex);
    }

    // 3. 如果是新连接，释放回连接池
    if (txObject.isNewConnectionHolder()) {
        DataSourceUtils.releaseConnection(con, obtainDataSource());
    }

    // 4. 清理 ConnectionHolder
    txObject.getConnectionHolder().clear();
}
```

### 9.17 commitTransactionAfterReturning() —— 正常提交

```java
// org.springframework.transaction.interceptor.TransactionAspectSupport
protected void commitTransactionAfterReturning(@Nullable TransactionInfo txInfo) {
    if (txInfo != null && txInfo.getTransactionStatus() != null) {
        if (logger.isTraceEnabled()) {
            logger.trace("Completing transaction for [" + txInfo.getJoinpointIdentification() + "]");
        }
        // ★ 执行提交
        txInfo.getTransactionManager().commit(txInfo.getTransactionStatus());
    }
}
```

```java
// org.springframework.transaction.support.AbstractPlatformTransactionManager
@Override
public final void commit(TransactionStatus status) throws TransactionException {
    if (status.isCompleted()) {
        throw new IllegalTransactionStateException(
            "Transaction is already completed");
    }

    DefaultTransactionStatus defStatus = (DefaultTransactionStatus) status;

    // ★ 检查是否被标记为 rollback-only
    // 如果内层方法（REQUIRED 传播行为）抛出异常但没有提交（只是标记），
    // 外层方法正常返回时会检查这个标记
    if (defStatus.isLocalRollbackOnly()) {
        processRollback(defStatus, false);
        return;
    }

    if (!shouldCommitOnGlobalRollbackOnly() && defStatus.isGlobalRollbackOnly()) {
        processRollback(defStatus, true);
        return;
    }

    processCommit(defStatus);
}

private void processCommit(DefaultTransactionStatus status) throws TransactionException {
    try {
        boolean unexpectedRollback = false;

        try {
            // 1. 触发 beforeCommit 回调
            triggerBeforeCommit(status);
            // 2. 触发 beforeCompletion 回调
            triggerBeforeCompletion(status);

            // 3. 有保存点：释放保存点
            if (status.hasSavepoint()) {
                releaseHeldSavepoint(status);
            }
            // 4. 新事务：执行提交
            else if (status.isNewTransaction()) {
                // ★ doCommit 由子类实现
                doCommit(status);
            }
            else if (isFailEarlyOnGlobalRollbackOnly()) {
                unexpectedRollback = status.isGlobalRollbackOnly();
            }

            // 5. 触发 afterCommit 回调
            triggerAfterCommit(status);
            // 6. 触发 afterCompletion 回调
            triggerAfterCompletion(status, TransactionSynchronization.STATUS_COMMITTED);

        }
        catch (UnexpectedRollbackException ex) {
            triggerAfterCompletion(status, TransactionSynchronization.STATUS_ROLLED_BACK);
            throw ex;
        }
        catch (TransactionException | RuntimeException | Error ex) {
            // 提交失败，执行回滚
            if (!status.isCompleted()) {
                doRollbackOnCommitException(status, ex);
            }
            throw ex;
        }
        finally {
            cleanupAfterCompletion(status);
        }

        if (unexpectedRollback) {
            throw new UnexpectedRollbackException(
                "Transaction silently rolled back");
        }
    }
    // ...
}
```

```java
// DataSourceTransactionManager.doCommit()
@Override
protected void doCommit(DefaultTransactionStatus status) {
    DataSourceTransactionObject txObject = (DataSourceTransactionObject) status.getTransaction();
    Connection con = txObject.getConnectionHolder().getConnection();
    if (status.isDebug()) {
        logger.debug("Committing JDBC transaction on Connection [" + con + "]");
    }
    try {
        // ★ 执行数据库 COMMIT
        con.commit();
    }
    catch (SQLException ex) {
        throw new DataAccessException("Could not commit JDBC transaction", ex);
    }
}
```

### 9.18 声明式事务完整调用链

```
用户调用 service.methodA()
    │
    ▼
代理对象（JDK Proxy / CGLIB Proxy）
    │
    ▼
拦截器链执行 → TransactionInterceptor.invoke()
    │
    ▼
TransactionAspectSupport.invokeWithinTransaction()
    │
    ├── 1. AnnotationTransactionAttributeSource.getTransactionAttribute()
    │       └── SpringTransactionAnnotationParser.parseTransactionAnnotation()
    │           → 解析 @Transactional 注解，获取 RuleBasedTransactionAttribute
    │
    ├── 2. determineTransactionManager() → DataSourceTransactionManager
    │
    ├── 3. createTransactionIfNecessary()
    │       │
    │       └── AbstractPlatformTransactionManager.getTransaction()
    │             │
    │             ├── doGetTransaction()
    │             │   └── TransactionSynchronizationManager.getResource(DataSource)
    │             │       → 从 ThreadLocal 获取 ConnectionHolder（null = 无事务）
    │             │
    │             ├── isExistingTransaction() → false（无已有事务）
    │             │
    │             ├── startTransaction()
    │             │   └── DataSourceTransactionManager.doBegin()
    │             │       ├── DataSource.getConnection() → 获取新 Connection
    │             │       ├── Connection.setAutoCommit(false) → 关闭自动提交
    │             │       └── TransactionSynchronizationManager.bindResource()
    │             │           → DataSource → ConnectionHolder 绑定到 ThreadLocal
    │             │
    │             └── prepareSynchronization()
    │                 → 初始化事务同步 ThreadLocal
    │
    ├── 4. invocation.proceedWithInvocation()
    │       │
    │       └── 执行目标方法
    │           │
    │           ├── DAO 操作使用 DataSourceUtils.getConnection()
    │           │   └── TransactionSynchronizationManager.getResource(DataSource)
    │           │       → 从 ThreadLocal 获取同一个 Connection
    │           │       → 所有 SQL 在同一个 Connection 上执行
    │           │
    │           └── 可能调用其他 @Transactional 方法（嵌套事务）
    │
    ├── 5a. 正常返回 → commitTransactionAfterReturning()
    │       └── AbstractPlatformTransactionManager.commit()
    │           └── DataSourceTransactionManager.doCommit()
    │               └── Connection.commit() → 数据库 COMMIT
    │
    └── 5b. 抛出异常 → completeTransactionAfterThrowing()
        ├── transactionAttribute.rollbackOn(ex)
        │   ├── RuleBasedTransactionAttribute.rollbackOn()
        │   │   ├── 检查 rollbackFor / noRollbackFor 规则
        │   │   └── 默认：RuntimeException/Error → true
        │   └── 需要回滚 → AbstractPlatformTransactionManager.rollback()
        │       └── DataSourceTransactionManager.doRollback()
        │           └── Connection.rollback() → 数据库 ROLLBACK
        └── 不需要回滚 → commit()
            └── Connection.commit() → 数据库 COMMIT

    无论提交还是回滚，最终都会执行 doCleanupAfterCompletion()：
    ├── TransactionSynchronizationManager.unbindResource(DataSource)
    │   → 从 ThreadLocal 移除 ConnectionHolder
    ├── Connection.setAutoCommit(true) → 恢复自动提交
    └── DataSourceUtils.releaseConnection()
        → 释放 Connection 回连接池
```

### 9.19 @Transactional 失效的 6 大场景

理解了源码后，这些失效场景都是顺理成章的：

#### 场景 1：同类方法内部调用（最常见）

```java
@Service
public class UserService {

    @Transactional
    public void methodA() {
        // ★ 内部调用不走代理，methodB 的事务不生效！
        this.methodB();
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void methodB() {
        // 这个方法不会在新事务中执行
    }
}
```

**原因：** `this.methodB()` 是直接调用原始对象的方法，没有经过代理对象，所以不会触发 `TransactionInterceptor`。

**解决方案：**
1. 注入自身代理：`@Autowired private UserService self;` 然后调用 `self.methodB()`
2. 使用 `AopContext.currentProxy()`（需要开启 `exposeProxy = true`）
3. 将方法拆分到不同的类中

#### 场景 2：方法不是 public

```java
@Service
public class UserService {

    @Transactional
    void methodA() {  // ★ 包级可见，非 public，事务不生效！
    }

    @Transactional
    private void methodB() {  // ★ private，事务不生效！
    }
}
```

**原因：** `AnnotationTransactionAttributeSource` 默认 `publicMethodsOnly = true`，非 public 方法的 `@Transactional` 会被忽略。CGLIB 代理也不会拦截 private 方法（子类无法重写父类的 private 方法）。

#### 场景 3：异常被 catch 吞掉

```java
@Service
public class UserService {

    @Transactional
    public void methodA() {
        try {
            dao.insert(record);  // 抛出 RuntimeException
        } catch (Exception e) {
            log.error("error", e);  // ★ 异常被吞掉，事务不会回滚！
        }
    }
}
```

**原因：** `invokeWithinTransaction()` 中的 `completeTransactionAfterThrowing()` 只在目标方法抛出异常时执行。如果异常被 catch 了，拦截器看不到异常，会正常提交。

#### 场景 4：异常类型不匹配

```java
@Service
public class UserService {

    @Transactional  // 默认只回滚 RuntimeException 和 Error
    public void methodA() throws IOException {
        throw new IOException("file error");  // ★ 受检异常，默认不回滚！
    }
}
```

**原因：** 默认回滚规则是 `super.rollbackOn(ex)` → `ex instanceof RuntimeException || ex instanceof Error`。`IOException` 是受检异常，不匹配。

**解决方案：** `@Transactional(rollbackFor = IOException.class)`

#### 场景 5：未被 Spring 管理

```java
// 没有 @Service / @Component 注解
public class UserService {

    @Transactional
    public void methodA() {
        // ★ 不是 Spring Bean，不会被代理，事务不生效！
    }
}
```

**原因：** 没有被 Spring 容器管理，就不会经过 `BeanPostProcessor`，自然不会创建代理对象。

#### 场景 6：传播行为误用

```java
@Service
public class UserService {

    @Transactional
    public void methodA() {
        // methodB 用 NOT_SUPPORTED，会挂起事务 A，以非事务方式执行
        self.methodB();
    }

    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    public void methodB() {
        dao.insert(record);  // ★ 不在事务中，异常不会回滚
    }
}
```

---

## 第十部分：面试高频考点与总结

### 10.1 JDK 动态代理 vs CGLIB 对比

| 对比维度 | JDK 动态代理 | CGLIB |
|---------|-------------|-------|
| 实现原理 | 实现接口，`Proxy.newProxyInstance()` | 继承目标类，`Enhancer.create()` |
| 是否需要接口 | **必须** | 不需要 |
| 方法调用 | `InvocationHandler.invoke()` 反射 | `MethodInterceptor.intercept()` + FastClass |
| 性能（创建） | 较快 | 较慢（生成 3 个类） |
| 性能（调用） | 较慢（反射 Method.invoke） | 较快（FastClass 索引 switch-case） |
| final 限制 | 接口方法不能是 final | 不能代理 final 类和 final 方法 |
| 依赖 | JDK 内置 | 需引入 cglib + asm |
| Spring Boot 默认 | 否（5.x 后默认 CGLIB） | **是** |

**面试口诀：** JDK 靠接口靠反射，CGLIB 靠继承靠 FastClass。Spring Boot 2.x+ 默认 CGLIB。

### 10.2 Spring AOP 的执行流程

```
面试回答框架：

1. 启动阶段：
   @EnableAspectJAutoProxy 注册 AnnotationAwareAspectJAutoProxyCreator
   → 它是 BeanPostProcessor
   → 扫描 @Aspect，通过 ReflectiveAspectJAdvisorFactory 解析
   → 每个 @Before/@Around 等方法包装成 InstantiationModelAwarePointcutAdvisorImpl

2. Bean 创建阶段：
   每个单例 Bean 在初始化后执行 postProcessAfterInitialization()
   → wrapIfNecessary()
   → findEligibleAdvisors()：找到匹配的 Advisor
   → createProxy()：通过 ProxyFactory 创建代理
   → DefaultAopProxyFactory 根据条件选择 JDK Proxy 或 CGLIB

3. 方法调用阶段：
   调用代理对象方法 → JdkDynamicAopProxy.invoke() / DynamicAdvisedInterceptor.intercept()
   → 获取拦截器链 getInterceptorsAndDynamicInterceptionAdvice()
   → 创建 ReflectiveMethodInvocation
   → proceed() 责任链执行
   → 最终调用目标方法
```

### 10.3 @Transactional 失效场景

1. **同类内部调用** → 不走代理
2. **非 public 方法** → 默认不解析
3. **异常被 catch** → 拦截器看不到异常
4. **异常类型不匹配** → 默认只回滚 RuntimeException/Error
5. **未被 Spring 管理** → 不创建代理
6. **传播行为误用** → NOT_SUPPORTED/NEVER 等

### 10.4 事务传播行为面试题

**Q: REQUIRED 和 REQUIRES_NEW 的区别？**
- REQUIRED：有事务就加入，没有就新建。共用同一个 Connection，内层异常会导致外层也回滚。
- REQUIRES_NEW：总是新建事务，挂起当前事务。使用不同的 Connection，内层提交/回滚不影响外层。

**Q: NESTED 和 REQUIRES_NEW 的区别？**
- NESTED：使用保存点实现，内层回滚到保存点，外层仍可继续提交。共用同一个 Connection。
- REQUIRES_NEW：独立事务，使用不同的 Connection。内层先提交，外层后提交。

**Q: 外层方法用 REQUIRED，内层方法用 REQUIRED，内层抛异常被 catch，外层还能提交吗？**
- 不能。内层抛异常时，事务被标记为 `globalRollbackOnly = true`。外层正常返回尝试提交时，`commit()` 检测到该标记，会执行回滚并抛出 `UnexpectedRollbackException`。

### 10.5 AOP 代理对象创建时机

**Q: Spring AOP 代理对象是在什么时候创建的？**

在 Bean 生命周期的 **初始化后** 阶段：
```
createBeanInstance() → 构造器创建实例
populateBean() → 依赖注入
initializeBean():
  ├── applyBeanPostProcessorsBeforeInitialization() → @PostConstruct
  ├── invokeInitMethods() → InitializingBean.afterPropertiesSet()
  └── applyBeanPostProcessorsAfterInitialization() → ★ AOP 代理在这里创建
```

具体是 `AnnotationAwareAspectJAutoProxyCreator.postProcessAfterInitialization()` → `wrapIfNecessary()` → `createProxy()`。

**Q: 循环依赖和 AOP 的关系？**

Spring 通过三级缓存解决循环依赖时，会提前暴露一个"早期引用"。如果 Bean 需要 AOP 代理，Spring 会在获取早期引用时通过 `getEarlyBeanReference()` 提前创建代理对象（而不是等到 `postProcessAfterInitialization`）。

### 10.6 常见面试题汇总

**Q1: Spring AOP 和 AspectJ 的区别？**
- Spring AOP 是运行时动态代理（JDK Proxy / CGLIB），只支持方法级别的 JoinPoint。
- AspectJ 是编译时/加载时字节码织入，支持更丰富的 JoinPoint（字段、构造器等），性能更好。
- Spring AOP 借用了 AspectJ 的注解语法和切点表达式。

**Q2: @Around 中不调用 proceed() 会怎样？**
- 目标方法不会执行。@Around 是最强大的通知，它完全控制是否执行目标方法、何时执行、是否修改返回值。

**Q3: 多个 Aspect 的执行顺序？**
- 通过 `@Order` 注解或实现 `Ordered` 接口控制。数值小的先执行（外层），数值大的后执行（内层）。
- 同一个 Aspect 内：@Around 前 → @Before → 目标方法 → @AfterReturning/@AfterThrowing → @After → @Around 后。

**Q4: CGLIB 的 FastClass 机制是什么？**
- CGLIB 为目标类和代理类各生成一个 FastClass 子类，通过方法签名计算 int 索引，然后通过 switch-case 直接调用方法，避免反射开销。这是 CGLIB 比 JDK 动态代理快的原因。

**Q5: @Transactional 注解可以放在接口上吗？**
- 可以，但**不推荐**。Spring 官方建议放在具体类上。因为 CGLIB 代理（Spring Boot 默认）不会代理接口，接口上的 @Transactional 可能被忽略。只有 JDK 动态代理才能识别接口上的 @Transactional。

**Q6: 事务的隔离级别有哪些？**
- DEFAULT：使用数据库默认隔离级别
- READ_UNCOMMITTED：读未提交
- READ_COMMITTED：读已提交
- REPEATABLE_READ：可重复读
- SERIALIZABLE：串行化

---

## 附录 A：Spring AOP 核心接口索引表

| 接口/类 | 包路径 | 作用 |
|---------|--------|------|
| `Pointcut` | `org.springframework.aop` | 切点，定义匹配规则 |
| `ClassFilter` | `org.springframework.aop` | 类过滤器 |
| `MethodMatcher` | `org.springframework.aop` | 方法匹配器 |
| `Advice` | `org.springframework.aop` | 通知标记接口 |
| `MethodInterceptor` | `org.springframework.aop` | 方法拦截器（环绕通知） |
| `MethodBeforeAdvice` | `org.springframework.aop` | 前置通知 |
| `AfterReturningAdvice` | `org.springframework.aop` | 后置返回通知 |
| `ThrowsAdvice` | `org.springframework.aop` | 异常通知 |
| `Advisor` | `org.springframework.aop` | 顾问（Pointcut + Advice） |
| `PointcutAdvisor` | `org.springframework.aop` | 包含 Pointcut 的 Advisor |
| `IntroductionAdvisor` | `org.springframework.aop` | 引介 Advisor |
| `AopProxy` | `org.springframework.aop.framework` | 代理接口 |
| `AopProxyFactory` | `org.springframework.aop.framework` | 代理工厂接口 |
| `DefaultAopProxyFactory` | `org.springframework.aop.framework` | 默认代理工厂 |
| `JdkDynamicAopProxy` | `org.springframework.aop.framework` | JDK 动态代理实现 |
| `CglibAopProxy` | `org.springframework.aop.framework` | CGLIB 代理实现 |
| `ProxyFactory` | `org.springframework.aop.framework` | 代理工厂 |
| `AdvisedSupport` | `org.springframework.aop.framework` | 代理配置支持 |
| `ReflectiveMethodInvocation` | `org.springframework.aop.framework` | JDK 代理的责任链执行 |
| `AdvisorChainFactory` | `org.springframework.aop.framework` | 拦截器链工厂 |
| `AdvisorAdapter` | `org.springframework.aop.framework.adapter` | Advice 适配器 |
| `AdvisorAdapterRegistry` | `org.springframework.aop.framework.adapter` | 适配器注册表 |
| `AnnotationAwareAspectJAutoProxyCreator` | `org.springframework.aop.aspectj.annotation` | AspectJ 自动代理创建器 |
| `AspectJExpressionPointcut` | `org.springframework.aop.aspectj` | AspectJ 表达式切点 |
| `AspectJAroundAdvice` | `org.springframework.aop.aspectj` | @Around 通知 |
| `AspectJMethodBeforeAdvice` | `org.springframework.aop.aspectj` | @Before 通知 |
| `AspectJAfterAdvice` | `org.springframework.aop.aspectj` | @After 通知 |
| `AspectJAfterReturningAdvice` | `org.springframework.aop.aspectj` | @AfterReturning 通知 |
| `AspectJAfterThrowingAdvice` | `org.springframework.aop.aspectj` | @AfterThrowing 通知 |
| `InstantiationModelAwarePointcutAdvisorImpl` | `org.springframework.aop.aspectj.annotation` | AspectJ Advisor 实现 |
| `ReflectiveAspectJAdvisorFactory` | `org.springframework.aop.aspectj.annotation` | AspectJ Advisor 工厂 |
| `TransactionInterceptor` | `org.springframework.transaction.interceptor` | 事务拦截器 |
| `TransactionAttributeSource` | `org.springframework.transaction.interceptor` | 事务属性源 |
| `AnnotationTransactionAttributeSource` | `org.springframework.transaction.annotation` | @Transactional 解析 |
| `PlatformTransactionManager` | `org.springframework.transaction` | 事务管理器接口 |
| `DataSourceTransactionManager` | `org.springframework.jdbc.datasource` | 数据源事务管理器 |
| `AbstractPlatformTransactionManager` | `org.springframework.transaction.support` | 事务管理器抽象基类 |
| `TransactionSynchronizationManager` | `org.springframework.transaction.support` | 事务同步管理器（ThreadLocal） |
| `TransactionDefinition` | `org.springframework.transaction` | 事务定义（传播行为、隔离级别等） |
| `TransactionStatus` | `org.springframework.transaction` | 事务状态 |
| `RuleBasedTransactionAttribute` | `org.springframework.transaction.interceptor` | 基于规则的事务属性 |

---

## 附录 B：@Transactional 事务传播行为速查表

| 传播行为 | 当前有事务 | 当前无事务 | 典型场景 | 注意事项 |
|---------|-----------|-----------|---------|---------|
| **REQUIRED**（默认） | 加入当前事务 | 新建事务 | 绝大多数 CRUD | 内层异常标记 rollback-only，外层无法提交 |
| **SUPPORTS** | 加入当前事务 | 以非事务方式执行 | 只读查询 | 无事务时不保证原子性 |
| **MANDATORY** | 加入当前事务 | **抛异常** | 强制要求在事务中调用 | 直接调用会抛 IllegalTransactionStateException |
| **REQUIRES_NEW** | 挂起当前事务，**新建独立事务** | 新建事务 | 日志记录（无论是否成功都要记录） | 使用不同的 Connection，注意连接池耗尽 |
| **NOT_SUPPORTED** | 挂起当前事务，**以非事务方式执行** | 以非事务方式执行 | 耗时操作（不影响主事务） | 挂起的事务资源仍然占用 |
| **NEVER** | **抛异常** | 以非事务方式执行 | 强制要求不在事务中 | 在事务中调用会抛异常 |
| **NESTED** | 创建**保存点**（嵌套事务） | 新建事务 | 部分失败可回滚到保存点 | 需要数据库支持保存点（如 MySQL InnoDB） |

---

> **文档说明：** 本文基于 Spring Framework 5.3.x 源码编写，涵盖了 Spring AOP 的代理创建机制（JDK Proxy / CGLIB）、Advice 链构建与执行、Pointcut/Advisor/Advice 体系、@EnableAspectJAutoProxy 机制、AspectJ 注解处理、以及 @Transactional 声明式事务的完整源码实现。建议配合之前整理的《Spring_IoC_DI源码深度解析》一起阅读，两者共同构成了 Spring 框架的核心。