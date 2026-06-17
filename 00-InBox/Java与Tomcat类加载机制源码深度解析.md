# Java 与 Tomcat 类加载机制源码深度解析

> 基于 JDK 8~21 + Tomcat 9 源码，从 JVM 原生类加载到 Web 容器隔离，系统拆解类加载的完整链路。

---

## 目录

**Part 1 — Java 类加载体系**
1. [类加载的完整生命周期](#1-类加载的完整生命周期)
2. [三 built-in 类加载器](#2-三-built-in-类加载器)
3. [ClassLoader 核心源码](#3-classloader-核心源码)
4. [双亲委派模型](#4-双亲委派模型)
5. [打破双亲委派的经典场景](#5-打破双亲委派的经典场景)

**Part 2 — SPI 与上下文类加载器**
6. [SPI 机制源码](#6-spi-机制源码)
7. [线程上下文类加载器](#7-线程上下文类加载器)
8. [JDBC 加载驱动的完整链路](#8-jdbc-加载驱动的完整链路)

**Part 3 — Tomcat 类加载器架构**
9. [Tomcat 类加载器全景图](#9-tomcat-类加载器全景图)
10. [WebAppClassLoader 源码](#10-webappclassloader-源码)
11. [Tomcat 如何实现 Web 应用隔离](#11-tomcat-如何实现-web-应用隔离)
12. [Tomcat 如何加载 Servlet / Spring](#12-tomcat-如何加载-servlet--spring)
13. [Tomcat 热加载与热部署](#13-tomcat-热加载与热部署)

**Part 4 — 自定义 ClassLoader 与热替换**
14. [自定义 ClassLoader 的步骤](#14-自定义-classloader-的步骤)
15. [热替换（HotSwap）原理](#15-热替换hotswap原理)
16. [Arthas 热更新原理](#16-arthas-热更新原理)

**Part 5 — 综合**
17. [常见面试题](#17-常见面试题)

---

# Part 1 — Java 类加载体系

---

## 1. 类加载的完整生命周期

```
.java 源文件
    │ javac 编译
    ▼
.class 字节码文件（存储在磁盘/JAR 中）
    │
    ▼
┌──────────────────────────────────────────────┐
│                类的生命周期                     │
│                                              │
│  ┌──────┐   ┌────────┐   ┌───────┐   ┌──────┐   ┌──────┐   ┌──────┐  │
│  │加载  │──→│ 验证   │──→│ 准备  │──→│ 解析 │──→│初始化 │──→│ 使用 │  │
│  │Loading│   │Verifying│   │Preparing│  │Resolving│ │Init  │   │Using │  │
│  └──────┘   └────────┘   └───────┘   └──────┘   └──────┘   └──────┘  │
│                                              │                     │    │
│                       ┌───────────────────────────────────────────┘    │
│                       ▼                                                │
│                 ┌──────────┐                                          │
│                 │  卸载     │                                          │
│                 │Unloading │                                          │
│                 └──────────┘                                          │
└──────────────────────────────────────────────┘
```

### 加载（Loading）

```
JVM 需要完成三件事：
  ① 通过全限定名获取该类的二进制字节流（可以从 ZIP/JAR/网络/动态生成等）
  ② 将字节流所代表的静态存储结构转化为方法区的运行时数据结构
  ③ 在堆中生成一个 java.lang.Class 对象，作为方法区数据的访问入口
```

### 验证（Verification）

```
验证字节码的正确性和安全性：
  ① 文件格式验证：魔数 0xCAFEBABE、版本号、常量池
  ② 元数据验证：是否有父类、是否继承了 final 类、是否实现抽象方法
  ③ 字节码验证：数据流分析、控制流分析、类型检查
  ④ 符号引用验证：引用的类/方法/字段是否存在、是否可访问
```

### 准备（Preparation）

```
为类变量（static）分配内存并设置零值初始值：

  public static int value = 123;

  准备阶段：value = 0    ← 零值
  初始化阶段：value = 123 ← 真正值

例外：static final（常量）在准备阶段就会赋值：
  public static final int CONSTANT = 123;
  准备阶段：CONSTANT = 123  ← ConstantValue 属性直接赋值
```

### 解析（Resolution）

```
将常量池中的符号引用替换为直接引用：

  符号引用：字面量（如 "java/lang/Object"）
  直接引用：内存地址/偏移量/句柄

解析的时机：
  - 类加载时解析（eager）：JVM 默认
  - 使用时解析（lazy）：Java 支持延迟解析
```

### 初始化（Initialization）

```
执行 <clinit> 方法（类构造器）：
  ① 收集所有 static 变量赋值和 static 代码块
  ② 按源码顺序合并为 <clinit> 方法
  ③ JVM 保证 <clinit> 在多线程下被正确同步

触发初始化的 6 种情况：
  ① new / getstatic / putstatic / invokestatic 指令
  ② java.lang.reflect 包的反射调用
  ③ 初始化子类时，父类未初始化
  ④ JVM 启动时的主类（包含 main 方法）
  ⑤ JDK 7+ 的 MethodHandle 解析结果为 REF_getStatic 等的方法句柄
  ⑥ default 方法的接口实现类初始化
```

---

## 2. 三 built-in 类加载器

```
┌─────────────────────────────────────────────────────────┐
│                    启动类加载器                            │
│            Bootstrap ClassLoader                          │
│        (C++ 实现，JVM 的一部分，非 Java 类)                │
│                                                          │
│  加载路径：                                               │
│    ${JAVA_HOME}/lib                                      │
│    rt.jar, resources.jar, charsets.jar 等                │
│    -Xbootclasspath 指定的路径                             │
│                                                          │
│  只加载能被 JVM 识别的包名（如 java.lang.*）               │
│  ★ ClassLoader.getSystemClassLoader().getParent()        │
│    返回 null（表示 Bootstrap）                             │
├─────────────────────────────────────────────────────────┤
│                    扩展类加载器                            │
│            Extension ClassLoader                          │
│        (JDK 8: sun.misc.Launcher$ExtClassLoader)         │
│        (JDK 9+: PlatformClassLoader)                     │
│                                                          │
│  加载路径：                                               │
│    ${JAVA_HOME}/lib/ext                                   │
│    java.ext.dirs 系统属性指定的路径                        │
│                                                          │
│  父加载器：Bootstrap（在代码中 getParent() 返回 null）     │
├─────────────────────────────────────────────────────────┤
│                    应用类加载器                            │
│            Application ClassLoader                        │
│        (sun.misc.Launcher$AppClassLoader)                 │
│                                                          │
│  加载路径：                                               │
│    classpath（用户类路径）                                 │
│    java.class.path 系统属性                               │
│                                                          │
│  父加载器：Extension ClassLoader                          │
│  ★ ClassLoader.getSystemClassLoader() 返回的就是它        │
└─────────────────────────────────────────────────────────┘
```

### 验证代码

```java
public class ClassLoaderDemo {
    public static void main(String[] args) {
        // String 由 Bootstrap 加载
        System.out.println(String.class.getClassLoader());
        // → null（Bootstrap 用 C++ 实现，Java 层看不到）

        // SQLDriverManager 由 Extension 加载（JDK 8）
        // JDK 9+ 由 PlatformClassLoader 加载
        System.out.println(sun.security.provider.Sun.class.getClassLoader());
        // → sun.misc.Launcher$ExtClassLoader@...

        // 自定义类由 AppClassLoader 加载
        System.out.println(ClassLoaderDemo.class.getClassLoader());
        // → sun.misc.Launcher$AppClassLoader@...

        // 打印类加载器层级
        ClassLoader cl = ClassLoaderDemo.class.getClassLoader();
        while (cl != null) {
            System.out.println(cl);
            cl = cl.getParent();
        }
        System.out.println("Bootstrap ClassLoader (null)");
        // 输出：
        // sun.misc.Launcher$AppClassLoader@...
        // sun.misc.Launcher$ExtClassLoader@...
        // Bootstrap ClassLoader (null)
    }
}
```

### Launcher 源码

```java
// sun.misc.Launcher（JDK 8）
public class Launcher {

    private static Launcher launcher = new Launcher();
    private static String bootClassPath = System.getProperty("sun.boot.class.path");

    private ClassLoader loader;

    public Launcher() {
        // ① 创建 ExtClassLoader
        ExtClassLoader extClassLoader;
        try {
            extClassLoader = ExtClassLoader.getExtClassLoader();
        } catch (IOException e) { throw new InternalError(...); }

        // ② 创建 AppClassLoader，parent = ExtClassLoader
        try {
            loader = AppClassLoader.getAppClassLoader(extClassLoader);
        } catch (IOException e) { throw new InternalError(...); }

        // ③ 设置线程上下文类加载器为 AppClassLoader
        Thread.currentThread().setContextClassLoader(loader);
    }

    public ClassLoader getClassLoader() { return loader; }

    // ===== ExtClassLoader =====
    static class ExtClassLoader extends URLClassLoader {
        static {
            // 加载 ${JAVA_HOME}/lib/ext 目录
        }

        public ExtClassLoader(File[] dirs) throws IOException {
            super(getURLs(dirs), null);   // ★ parent = null（不是 Bootstrap）
            // parent 在代码层面是 null，但 JVM 会让它委托给 Bootstrap
        }
    }

    // ===== AppClassLoader =====
    static class AppClassLoader extends URLClassLoader {
        public AppClassLoader(URL[] urls, ExtClassLoader parent) {
            super(urls, parent);   // ★ parent = ExtClassLoader
        }
    }
}
```

---

## 3. ClassLoader 核心源码

### loadClass（双亲委派的核心）

```java
// java.lang.ClassLoader
protected Class<?> loadClass(String name, boolean resolve)
    throws ClassNotFoundException
{
    synchronized (getClassLoadingLock(name)) {   // ★ 加锁，防止并发重复加载
        // ① 检查是否已加载
        Class<?> c = findLoadedClass(name);
        if (c == null) {
            try {
                if (parent != null) {
                    // ② 委托给父加载器加载
                    c = parent.loadClass(name, false);
                } else {
                    // ③ 父加载器为 null，委托给 Bootstrap
                    c = findBootstrapClassOrNull(name);
                }
            } catch (ClassNotFoundException e) {
                // 父加载器抛异常 → 找不到 → 不处理
            }

            if (c == null) {
                // ④ 父加载器都找不到，自己加载
                c = findClass(name);
            }
        }

        if (resolve) {
            resolveClass(c);   // 解析类（可选）
        }
        return c;
    }
}
```

### findClass（自定义加载逻辑的扩展点）

```java
// java.lang.ClassLoader
protected Class<?> findClass(String name) throws ClassNotFoundException {
    // ★ 默认实现直接抛异常
    // JDK 鼓励子类覆盖此方法而非 loadClass（保持双亲委派）
    throw new ClassNotFoundException(name);
}

// URLClassLoader 的 findClass 实现
// java.net.URLClassLoader
protected Class<?> findClass(final String name) {
    // ① 从 URL 列表中查找 .class 文件
    String path = name.replace('.', '/').concat(".class");
    Resource res = ucp.getResource(path, false);

    if (res != null) {
        // ② 读取字节码
        byte[] b = res.getBytes();
        // ③ 调用 defineClass 将字节码转为 Class 对象
        return defineClass(name, b, 0, b.length);
    }
    throw new ClassNotFoundException(name);
}
```

### defineClass（字节码 → Class 对象）

```java
// java.lang.ClassLoader
protected final Class<?> defineClass(String name, byte[] b, int off, int len)
    throws ClassFormatError
{
    return defineClass(name, b, off, len, null);
}

protected final Class<?> defineClass(String name, byte[] b, int off, int len,
                                      ProtectionDomain protectionDomain)
    throws ClassFormatError
{
    // ① 前置检查
    checkName(name);           // 名称合法性
    checkCertCVE(name, protectionDomain);  // 安全检查

    // ② 调用 native 方法将字节码转为方法区的数据结构
    // 并在堆中创建 Class 对象
    Class<?> c = defineClass0(name, b, off, len, protectionDomain);

    return c;
}

// native 方法
private native Class<?> defineClass0(String name, byte[] b, int off, int len,
                                      ProtectionDomain pd);
// JVM 内部实现：
//   ① 解析字节码格式
//   ② 验证字节码
//   ③ 在方法区创建 InstanceKlass
//   ④ 在堆中创建 java.lang.Class 对象
//   ⑤ 注册到 ClassLoader 的 classes 表
```

### findLoadedClass

```java
// java.lang.ClassLoader
protected final Class<?> findLoadedClass(String name) {
    // ★ 检查是否已加载（从 JVM 的类加载记录中查找）
    // 每个类加载器维护一个已加载类的缓存
    if (!checkName(name)) return null;
    return findLoadedClass0(name);
}

private native final Class<?> findLoadedClass0(String name);
// JVM 内部：遍历 SystemDictionary 查找
// key = (类名, 类加载器) → 唯一确定一个类
```

---

## 4. 双亲委派模型

### 模型示意

```
         ┌─────────────────────┐
         │ Bootstrap ClassLoader│
         │   (rt.jar 等核心库)   │
         └──────────┬──────────┘
                    │ parent
         ┌──────────┴──────────┐
         │ Extension ClassLoader│
         │   (lib/ext 目录)     │
         └──────────┬──────────┘
                    │ parent
         ┌──────────┴──────────┐
         │ Application ClassLoader│
         │   (classpath)        │
         └──────────┬──────────┘
                    │ parent
         ┌──────────┴──────────┐
         │  Custom ClassLoader  │
         │   (自定义加载路径)    │
         └─────────────────────┘

加载顺序（自底向上委托）：
  Custom → App → Extension → Bootstrap

查找顺序（自顶向下尝试）：
  Bootstrap → Extension → App → Custom
```

### 双亲委派的核心目的

```
① 安全性：防止核心类被篡改
  用户自己写一个 java.lang.String，双亲委派保证加载的是 rt.jar 中的
  → 即使自定义了 java.lang.String，也由 Bootstrap 先加载

② 避免重复加载：父加载器已加载的类，子加载器不需要再加载
  → 保证同一个类在整个 JVM 中只有一个 Class 对象

③ 层次清晰：每一层加载器负责不同范围的类
```

### 全盘委托

```java
// 当一个类由某个 ClassLoader 加载时，
// 它引用的其他类也由同一个 ClassLoader 加载（除非显式指定）

public class MyClass {
    private OtherClass other;  // OtherClass 也由加载 MyClass 的 ClassLoader 加载
}

// 源码层面：
// JVM 在解析类的符号引用时，使用发起引用的类的 ClassLoader 来加载目标类
// Class.getClassLoader() 返回的就是加载该类的 ClassLoader
```

---

## 5. 打破双亲委派的经典场景

### 场景 1：JNDI / JDBC（SPI 机制）

```
问题：
  java.sql.DriverManager 由 Bootstrap 加载
  但具体的 Driver 实现（如 com.mysql.cj.jdbc.Driver）在 classpath 下
  Bootstrap 找不到 classpath 下的类

解决：
  线程上下文类加载器（Thread Context ClassLoader）
  → 详见 Part 2
```

### 场景 2：Tomcat（Web 应用隔离）

```
问题：
  两个 Web 应用依赖同一个库的不同版本
  如 app1 用 spring-4, app2 用 spring-5
  双亲委派只会加载第一个找到的版本

解决：
  每个 Web 应用有自己的 WebAppClassLoader
  优先加载 Web 应用自己的类，再委托给父加载器
  → 详见 Part 3
```

### 场景 3：OSGi（模块化热部署）

```
问题：
  OSGi 的每个 Bundle 有自己的类加载器
  Bundle 之间可以相互引用（不是简单的父子关系）
  类加载器之间是网状结构而非树状

解决：
  每个 Bundle 有自己的 ClassLoader
  通过 Export-Package / Import-Package 声明依赖关系
  类加载时先查自己 → 再查依赖的 Bundle → 最后委托给父加载器

OSGi 类加载顺序：
  ① 检查是否已加载
  ② 检查是否在 Import-Package 中 → 委托给导出 Bundle 的 ClassLoader
  ③ 检查是否在 Export-Package 中 → 自己加载
  ④ 委托给父 ClassLoader
  ⑤ 检查是否在 Require-Bundle 中
  ⑥ 查找 Fragment
  ⑗ 失败 → ClassNotFoundException
```

### 场景 4：自定义 ClassLoader 覆写 loadClass

```java
// ★ 覆写 loadClass 而非 findClass 就可以打破双亲委派
public class BreakParentClassLoader extends ClassLoader {

    private byte[] classBytes;

    @Override
    public Class<?> loadClass(String name, boolean resolve)
            throws ClassNotFoundException {
        // ① 不委托给父加载器，直接自己加载
        // （仅对特定类打破，其他类仍走双亲委派）
        if (name.startsWith("com.example.")) {
            return findClass(name);  // ★ 自己加载
        }
        return super.loadClass(name, resolve);  // 其他类走双亲委派
    }

    @Override
    protected Class<?> findClass(String name) throws ClassNotFoundException {
        byte[] bytes = loadClassBytes(name);  // 自定义字节码来源
        return defineClass(name, bytes, 0, bytes.length);
    }
}
```

---

# Part 2 — SPI 与上下文类加载器

---

## 6. SPI 机制源码

### SPI 是什么

```
SPI (Service Provider Interface)：
  JDK 定义接口，第三方提供实现，运行时动态发现实现类

  接口定义在 rt.jar（Bootstrap 加载）
  实现类在 classpath（AppClassLoader 加载）

  核心问题：Bootstrap 的 ClassLoader 无法访问 classpath
  → 需要线程上下文类加载器桥接
```

### ServiceLoader 源码

```java
// java.util.ServiceLoader（JDK 6+）
public final class ServiceLoader<S> implements Iterable<S> {

    private static final String PREFIX = "META-INF/services/";

    // ★ 核心字段
    private final Class<S> service;          // 接口类型
    private final ClassLoader loader;        // ★ 类加载器
    private final AccessControlContext acc;

    // 静态工厂方法
    public static <S> ServiceLoader<S> load(Class<S> service) {
        // ★ 使用线程上下文类加载器
        ClassLoader cl = Thread.currentThread().getContextClassLoader();
        return new ServiceLoader<>(service, cl);
    }

    public static <S> ServiceLoader<S> load(Class<S> service, ClassLoader loader) {
        return new ServiceLoader<>(service, loader);
    }

    // 懒加载迭代器
    private class LazyIterator implements Iterator<S> {
        Set<String> providers;
        Enumeration<URL> configs;
        Iterator<String> pending;

        @Override
        public S next() {
            String cn = pending.next();   // 实现类的全限定名
            try {
                // ★ 用 loader 加载实现类
                Class<?> c = Class.forName(cn, false, loader);
                //   ↑ 注意：这里用的是 SPI 的 loader，不是接口的 ClassLoader
                Object p = service.cast(c.newInstance());
                return service.cast(p);
            } catch (ClassNotFoundException x) {
                fail(service, "Provider " + cn + " not found");
            }
        }
    }
}
```

### SPI 配置文件格式

```
文件路径：META-INF/services/接口全限定名
文件内容：每行一个实现类的全限定名

示例：META-INF/services/java.sql.Driver
com.mysql.cj.jdbc.Driver
com.alibaba.druid.proxy.DruidDriver
org.postgresql.Driver
```

---

## 7. 线程上下文类加载器

### 源码

```java
// java.lang.Thread
public class Thread implements Runnable {

    // ★ 每个线程持有一个上下文类加载器
    private volatile ClassLoader contextClassLoader;

    public ClassLoader getContextClassLoader() {
        return contextClassLoader;
    }

    public void setContextClassLoader(ClassLoader cl) {
        contextClassLoader = cl;
    }

    // 默认值：在 Launcher 构造方法中设置
    // Thread.currentThread().setContextClassLoader(loader);
    // loader = AppClassLoader
}
```

### 为什么需要上下文类加载器

```
问题场景：

  Bootstrap ClassLoader 加载了 DriverManager（rt.jar）
  DriverManager 需要加载 classpath 下的 MySQL Driver
  但 Bootstrap 找不到 classpath 下的类！

  双亲委派是单向的：
  Bootstrap ← Extension ← App
  子加载器能看到父加载器的类，但父加载器看不到子加载器的类

解决：

  在 DriverManager 中使用线程上下文类加载器：
  ClassLoader cl = Thread.currentThread().getContextClassLoader();
  // cl = AppClassLoader（在 Launcher 中设置的）
  Class.forName(driverClass, true, cl);
  // 用 AppClassLoader 加载 MySQL Driver → 成功！

本质：
  上下文类加载器是一种"逆向委派"机制
  父加载器通过子加载器来加载它看不到的类
```

---

## 8. JDBC 加载驱动的完整链路

### DriverManager 初始化

```java
// java.sql.DriverManager
public class DriverManager {

    // ★ 静态初始化块：加载所有 JDBC 驱动
    static {
        loadInitialDrivers();
        println("JDBC DriverManager initialized");
    }

    private static void loadInitialDrivers() {
        String drivers;
        try {
            drivers = AccessController.doPrivileged(
                (PrivilegedAction<String>) () -> System.getProperty("jdbc.drivers"));
        } catch (Exception ex) { drivers = null; }

        // ★ 使用 ServiceLoader 加载 SPI 驱动
        AccessController.doPrivileged(
            (PrivilegedAction<Void>) () -> {
                ServiceLoader<Driver> loadedDrivers =
                    ServiceLoader.load(Driver.class);
                // ↑ 内部使用 Thread.currentThread().getContextClassLoader()
                // → AppClassLoader

                Iterator<Driver> driversIterator = loadedDrivers.iterator();

                try {
                    while (driversIterator.hasNext()) {
                        // ★ 触发 LazyIterator.next() → Class.forName(cn, false, loader)
                        driversIterator.next();
                    }
                } catch (Throwable t) { /* ... */ }
                return null;
            }
        );
    }
}
```

### 完整链路图

```
1. 应用启动
   │
   ▼
2. Launcher 初始化
   │  创建 ExtClassLoader → 创建 AppClassLoader
   │  Thread.currentThread().setContextClassLoader(AppClassLoader)
   │
   ▼
3. 应用代码首次使用 JDBC
   │  Class.forName("java.sql.DriverManager") → 触发 <clinit>
   │
   ▼
4. DriverManager.<clinit> → loadInitialDrivers()
   │
   ▼
5. ServiceLoader.load(Driver.class)
   │  使用 Thread.currentThread().getContextClassLoader()
   │  = AppClassLoader
   │
   ▼
6. 扫描 META-INF/services/java.sql.Driver
   │  发现 com.mysql.cj.jdbc.Driver
   │
   ▼
7. Class.forName("com.mysql.cj.jdbc.Driver", false, AppClassLoader)
   │  ★ 用 AppClassLoader 加载，而不是 Bootstrap
   │
   ▼
8. MySQL Driver 的 static 块执行
   │  DriverManager.registerDriver(new Driver())
   │
   ▼
9. 驱动注册完成，getConnection() 可用
```

---

# Part 3 — Tomcat 类加载器架构

---

## 9. Tomcat 类加载器全景图

```
                ┌──────────────────────────┐
                │   Bootstrap ClassLoader   │
                │     (JDK 核心库)          │
                └────────────┬─────────────┘
                             │
                ┌────────────┴─────────────┐
                │   Extension ClassLoader   │
                │     (JDK 扩展库)          │
                └────────────┬─────────────┘
                             │
                ┌────────────┴─────────────┐
                │   Application ClassLoader │
                │     (classpath)           │
                └────────────┬─────────────┘
                             │
                ┌────────────┴─────────────┐
                │   Common ClassLoader      │
                │  (Tomcat 公共库: lib/)    │
                └────────────┬─────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
    ┌─────────┴─────────┐       ┌───────────┴──────────┐
    │ Catalina ClassLoader│     │ Shared ClassLoader    │
    │ (Tomcat 内部类)     │     │ (所有 Web 应用共享)    │
    └───────────────────┘       └───────────┬──────────┘
                                            │
                               ┌────────────┴────────────┐
                               │                         │
                    ┌──────────┴──────────┐  ┌───────────┴──────────┐
                    │ WebApp1 ClassLoader │  │ WebApp2 ClassLoader  │
                    │  (WEB-INF/classes)  │  │  (WEB-INF/classes)   │
                    │  (WEB-INF/lib)      │  │  (WEB-INF/lib)       │
                    └─────────────────────┘  └──────────────────────┘
```

### 各类加载器的职责

```
┌────────────────────┬────────────────────────────────────────────┐
│ 类加载器            │ 加载路径                                     │
├────────────────────┼────────────────────────────────────────────┤
│ Bootstrap          │ JDK 核心库（rt.jar 等）                      │
│ Extension          │ JDK 扩展库（lib/ext）                        │
│ Application        │ Tomcat 启动脚本中的 classpath                │
│ Common             │ ${catalina.home}/lib/*.jar                  │
│                    │   servlet-api.jar, jsp-api.jar 等            │
│ Catalina           │ Tomcat 自身的内部类                          │
│ Shared             │ 所有 Web 应用共享的类                         │
│ WebApp             │ WEB-INF/classes + WEB-INF/lib/*.jar         │
│ JspClassLoader     │ JSP 编译后的 Servlet 类                      │
└────────────────────┴────────────────────────────────────────────┘
```

### Catalina 类加载器的创建源码

```java
// org.apache.catalina.startup.Bootstrap

public final class Bootstrap {

    // ★ Tomcat 入口
    public static void main(String args[]) {
        // 初始化类加载器
        if (daemon == null) {
            Bootstrap bootstrap = new Bootstrap();
            bootstrap.init();   // ★ 创建类加载器层级
            daemon = bootstrap;
        }
    }

    public void init() throws Exception {
        // 初始化类加载器
        initClassLoaders();

        // ★ 设置线程上下文类加载器为 CatalinaClassLoader
        Thread.currentThread().setContextClassLoader(catalinaLoader);

        // 加载 Catalina 类并用反射调用 start
        Class<?> startupClass = catalinaLoader.loadClass("org.apache.catalina.startup.Catalina");
        Object startupInstance = startupClass.getConstructor().newInstance();
        // ...
    }

    private void initClassLoaders() {
        // ① Common ClassLoader
        commonLoader = createClassLoader("common", null);
        // parent = null → 委托给 AppClassLoader

        // ② Catalina ClassLoader（Tomcat 内部类）
        catalinaLoader = createClassLoader("server", commonLoader);
        // parent = CommonClassLoader

        // ③ Shared ClassLoader（Web 应用共享）
        sharedLoader = createClassLoader("shared", commonLoader);
        // parent = CommonClassLoader
    }

    private ClassLoader createClassLoader(String name, ClassLoader parent) {
        // 从 catalina.properties 读取配置
        String value = CatalinaProperties.getProperty(name + ".loader");

        // 解析路径，创建 URLClassLoader
        // 本质是 new URLClassLoader(urls, parent)
        return ClassLoaderFactory.createClassLoader(array, classPaths, parent);
    }
}
```

---

## 10. WebAppClassLoader 源码

### 核心源码（Tomcat 9）

```java
// org.apache.catalina.loader.WebappClassLoaderBase

public abstract class WebappClassLoaderBase extends URLClassLoader {

    // ★ 核心：Web 应用自己的类缓存
    protected final Map<String, ResourceEntry> resourceEntries = new ConcurrentHashMap<>();

    // ★ 核心：类加载的委托策略
    protected boolean delegate = false;   // 默认 false → 先自己找，再委托父加载器

    // ============================================================
    // ★★★ loadClass — Tomcat 类加载的核心 ★★★
    // ============================================================
    @Override
    public Class<?> loadClass(String name, boolean resolve)
            throws ClassNotFoundException {

        synchronized (getClassLoadingLock(name)) {
            // ① 检查是否已加载
            Class<?> clazz = findLoadedClass0(name);
            if (clazz != null) {
                if (resolve) resolveClass(clazz);
                return clazz;
            }

            // ② 委托给 JVM 缓存
            clazz = findLoadedClass(name);
            if (clazz != null) {
                if (resolve) resolveClass(clazz);
                return clazz;
            }

            // ③ ★ 检查是否是 JVM 核心类（java. 开头）
            //    核心类必须由 Bootstrap 加载，不允许覆盖
            if (name.startsWith("java.")) {
                // 委托给父加载器 → 最终由 Bootstrap 加载
                clazz = getSystemClassLoader().loadClass(name);
                // ...
            }

            // ④ ★ Tomcat 的特殊处理：某些包必须由父加载器加载
            //    如 javax.servlet.* 必须由 Common 加载，保证 API 一致性
            if (securityManager != null && name.startsWith("javax.")) {
                // ...
            }

            // ⑤ ★★★ 根据委托策略决定加载顺序 ★★★
            boolean delegateLoad = delegate || name.startsWith("javax.");

            if (delegateLoad) {
                // 委托模式：先问父加载器
                clazz = super.loadClass(name, resolve);
                if (clazz != null) return clazz;
            }

            // ⑥ ★ 自己找（WEB-INF/classes + WEB-INF/lib）
            clazz = findClass(name);
            if (clazz != null) {
                if (resolve) resolveClass(clazz);
                return clazz;
            }

            // ⑦ 如果委托模式未启用，自己找不到再问父加载器
            if (!delegateLoad) {
                clazz = super.loadClass(name, resolve);
                if (clazz != null) return clazz;
            }

            throw new ClassNotFoundException(name);
        }
    }
}
```

### Tomcat 加载顺序总结

```
默认策略（delegate=false）：

  ① 检查已加载缓存
  ② java.* 核心类 → 委托给 Bootstrap
  ③ javax.* 等 API 类 → 委托给父加载器（保证 API 一致）
  ④ ★ 自己的 WEB-INF/classes + WEB-INF/lib → 优先加载
  ⑤ 自己找不到 → 委托给父加载器（Common → App → Ext → Bootstrap）

关键点：
  Web 应用自己的类（WEB-INF 下的）优先于父加载器加载！
  这就打破了标准双亲委派（标准双亲委派是先问父加载器再自己找）

为什么这么做？
  Web 应用 A 用 Spring 4，Web 应用 B 用 Spring 5
  如果先问父加载器，Spring 4 和 Spring 5 只能有一个被加载
  → 让 Web 应用优先加载自己的版本 → 实现隔离
```

---

## 11. Tomcat 如何实现 Web 应用隔离

### 隔离的核心机制

```
隔离原理：
  每个类在 JVM 中由 (类全限定名, 定义类加载器) 唯一标识

  即使两个类全限定名相同，只要定义它们的 ClassLoader 不同，
  JVM 就认为它们是不同的类

  app1 的 WebAppClassLoader 加载的 org.springframework.context.ApplicationContext
  app2 的 WebAppClassLoader 加载的 org.springframework.context.ApplicationContext
  → 两个不同的 Class 对象！→ 互不影响
```

### 实例演示

```java
// 两个 Web 应用各自有自己的 ClassLoader
WebappClassLoader loader1 = new WebappClassLoader(sharedLoader);
loader1.addRepository("file:/app1/WEB-INF/classes/");
loader1.addRepository("file:/app1/WEB-INF/lib/spring-core-4.3.jar");

WebappClassLoader loader2 = new WebappClassLoader(sharedLoader);
loader2.addRepository("file:/app2/WEB-INF/classes/");
loader2.addRepository("file:/app2/WEB-INF/lib/spring-core-5.3.jar");

Class<?> spring1 = loader1.loadClass("org.springframework.util.StringUtils");
Class<?> spring2 = loader2.loadClass("org.springframework.util.StringUtils");

System.out.println(spring1 == spring2);  // → false！不同的类
System.out.println(spring1.getClassLoader());  // WebappClassLoader-1
System.out.println(spring2.getClassLoader());  // WebappClassLoader-2
```

### 隔离的边界

```
★ 并非所有类都是隔离的

隔离的（每个 Web 应用独立）：
  - WEB-INF/classes 下的类
  - WEB-INF/lib 下的 JAR

共享的（所有 Web 应用共享）：
  - JDK 核心类（Bootstrap 加载）
  - ${catalina.home}/lib 下的类（CommonClassLoader 加载）
    如 servlet-api.jar, jsp-api.jar

设计原则：
  - API 接口 → 共享（servlet-api 由 Common 加载）
  - API 实现 → 隔离（Spring MVC 等由 WebApp 加载）
  → 所有 Web 应用看到的 Servlet API 是同一个，
    但各自的 Spring 版本可以不同
```

---

## 12. Tomcat 如何加载 Servlet / Spring

### Servlet 加载链路

```
1. 请求到达 Tomcat
   │
   ▼
2. Connector 解析 HTTP 请求
   │
   ▼
3. Engine → Host → Context 路由
   │
   ▼
4. Context（= Web 应用）的 Wrapper 管理 Servlet
   │
   ▼
5. Wrapper.loadServlet()
   │  Class<?> clazz = webappClassLoader.loadClass(servletClassName);
   │  Servlet servlet = (Servlet) clazz.getConstructor().newInstance();
   │
   ▼
6. servlet.init(config)
```

### Spring 的加载链路

```
1. Tomcat 启动，扫描 WEB-INF/lib
   │
   ▼
2. 发现 spring-web 的 SpringServletContainerInitializer
   │  （实现了 ServletContainerInitializer 接口）
   │  标注了 @HandlesTypes(WebApplicationInitializer.class)
   │
   ▼
3. Tomcat 用 WebAppClassLoader 加载 SpringServletContainerInitializer
   │  扫描 WebApplicationInitializer 的所有实现类
   │
   ▼
4. 调用 onStartup()
   │  创建 AnnotationConfigWebApplicationContext
   │  注册配置类
   │  refresh() 容器
   │
   ▼
5. DispatcherServlet 注册到 Tomcat
   │  Spring MVC 就绪
```

### ServletContainerInitializer 的加载

```java
// org.apache.catalina.startup.ContextConfig

// Tomcat 启动时扫描 ServletContainerInitializer
protected void processServletContainerInitializers() {
    // ★ 使用 WebAppClassLoader 加载 SCI
    // 扫描所有 JAR 中的 META-INF/services/javax.servlet.ServletContainerInitializer
    ServiceLoader<ServletContainerInitializer> serviceLoader =
        ServiceLoader.load(ServletContainerInitializer.class, contextClassLoader);
    // ↑ contextClassLoader = WebAppClassLoader

    for (ServletContainerInitializer sci : serviceLoader) {
        // 加载 SCI 实现类
        // 获取 @HandlesTypes 指定的类型
        // 扫描 Web 应用中该类型的实现类
        initializerList.add(sci);
    }
}
```

---

## 13. Tomcat 热加载与热部署

### 热加载（Hot Loading）

```
热加载：不重启 Tomcat，重新加载某个 Web 应用

触发条件：
  ① 监控 WEB-INF/classes 和 WEB-INF/lib 的文件变化
  ② 默认 reloadable=false，开发时设为 true

  <Context reloadable="true">

执行过程：
  ① 检测到文件变化
  ② 调用 StandardContext.reload()
  ③ 停止当前 Context（销毁所有 Servlet/Filter/Listener）
  ④ ★ 创建新的 WebAppClassLoader
  ⑤ 用新的 ClassLoader 重新加载所有类
  ⑥ 重新初始化 Servlet/Filter/Listener

关键：创建新的 ClassLoader
  旧的 ClassLoader 加载的类无法卸载（GC 根可达）
  只有创建新的 ClassLoader，才能加载修改后的类
  旧 ClassLoader 及其加载的类会被 GC 回收（如果没有其他引用）
```

### StandardContext.reload 源码

```java
// org.apache.catalina.core.StandardContext

@Override
public synchronized void reload() {
    // 验证状态
    if (!getState().isAvailable()) return;

    // ① 停止当前 Context
    stop();

    // ② ★ 创建新的 ClassLoader
    // 旧 WebAppClassLoader 被丢弃
    // 新 WebAppClassLoader 加载修改后的类
    // （在 start() 中重建）
    start();

    // ③ 通知监听器
    fireLifecycleEvent(Lifecycle.RELOAD_EVENT, null);
}
```

### 热部署（Hot Deployment）

```
热部署：不重启 Tomcat，重新部署整个 Web 应用（WAR 包）

触发条件：
  ① 监控 app.war 的文件变化
  ② 管理界面手动部署

执行过程：
  ① 检测到 WAR 文件变化
  ② 卸载旧 Context
    - 停止所有 Servlet/Filter/Listener
    - 丢弃旧 WebAppClassLoader
    - 删除解压后的目录
  ③ 重新解压 WAR
  ④ 创建新的 Context + WebAppClassLoader
  ⑤ 启动新 Context

与热加载的区别：
  热加载：只替换 ClassLoader，Context 对象不变
  热部署：整个 Context 重建，包括解压 WAR
```

### 内存泄漏防护

```java
// org.apache.catalina.loader.WebappClassLoaderBase

// ★ Tomcat 主动清理线程和资源的内存泄漏
@Override
public void clearReferences() {
    // ① 清理线程池（Web 应用创建但未销毁的线程）
    clearReferencesThreads();

    // ② 清理 ThreadLocal（Web 应用设置但未清除的 ThreadLocal）
    clearReferencesThreadLocals();

    // ③ 清理 JDBC 驱动注册
    clearReferencesJdbc();

    // ④ 清理 RMI 目标
    clearReferencesRmiTargets();

    // ⑤ 清理其他资源
    // ...

    // ⑥ 检查 ClassLoader 泄漏
    // 如果旧 WebAppClassLoader 的类还被引用，打印警告
}

// 线程泄漏检测
protected void clearReferencesThreads() {
    // 获取 JVM 中所有线程
    Set<Thread> threads = Thread.getAllStackTraces().keySet();

    for (Thread thread : threads) {
        // 如果线程的 ContextClassLoader 是当前的 WebAppClassLoader
        // 说明 Web 应用创建的线程没被销毁 → 潜在泄漏
        if (thread.getContextClassLoader() == this) {
            // 尝试停止线程
            thread.interrupt();
            log.warn("Web application created thread: " + thread.getName()
                   + " but failed to stop it.");
        }
    }
}
```

---

# Part 4 — 自定义 ClassLoader 与热替换

---

## 14. 自定义 ClassLoader 的步骤

### 模板代码

```java
public class CustomClassLoader extends ClassLoader {

    private final String classPath;   // 类文件根目录

    public CustomClassLoader(String classPath) {
        // 不指定 parent → 默认 parent = AppClassLoader
        this.classPath = classPath;
    }

    public CustomClassLoader(String classPath, ClassLoader parent) {
        super(parent);
        this.classPath = classPath;
    }

    // ★★★ 关键：覆盖 findClass 而非 loadClass（保持双亲委派）
    @Override
    protected Class<?> findClass(String name) throws ClassNotFoundException {
        // ① 将类名转换为路径
        String path = name.replace('.', '/').concat(".class");

        // ② 读取字节码
        byte[] classBytes;
        try {
            classBytes = loadClassBytes(path);
        } catch (IOException e) {
            throw new ClassNotFoundException(name, e);
        }

        // ③ 解密（如果有加密）
        classBytes = decrypt(classBytes);

        // ④ defineClass：将字节码转为 Class 对象
        return defineClass(name, classBytes, 0, classBytes.length);
    }

    private byte[] loadClassBytes(String path) throws IOException {
        File file = new File(classPath, path);
        try (InputStream is = new FileInputStream(file);
             ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int len;
            while ((len = is.read(buffer)) != -1) {
                baos.write(buffer, 0, len);
            }
            return baos.toByteArray();
        }
    }

    private byte[] decrypt(byte[] data) {
        // 自定义解密逻辑
        return data;
    }
}

// 使用
CustomClassLoader loader = new CustomClassLoader("/path/to/classes");
Class<?> clazz = loader.loadClass("com.example.MyClass");
Object obj = clazz.getConstructor().newInstance();
Method method = clazz.getMethod("hello");
method.invoke(obj);
```

### 两个注意点

```
① 覆写 findClass 而非 loadClass
  findClass：只改变"去哪找类"的逻辑，保持双亲委派
  loadClass：改变"整个加载流程"，打破双亲委派

② 避免重复 defineClass
  同一个 ClassLoader 对同一个类只能 defineClass 一次
  重复调用会抛 LinkageError
  如果需要重新加载，必须创建新的 ClassLoader
```

---

## 15. 热替换（HotSwap）原理

### 基本原理

```
热替换的核心：
  ① 创建新的 ClassLoader
  ② 用新 ClassLoader 加载修改后的类
  ③ 新实例使用新类，旧实例仍使用旧类

限制：
  - 旧 ClassLoader 加载的旧类对象不会被自动替换
  - 必须重建所有使用旧类的对象
  - 方法区中的旧类需要等 GC 回收
```

### 实现热替换

```java
public class HotSwapDemo {

    public static void main(String[] args) throws Exception {
        while (true) {
            // ① 每次循环创建新的 ClassLoader
            CustomClassLoader loader = new CustomClassLoader("/path/to/classes");

            // ② 加载类
            Class<?> clazz = loader.loadClass("com.example.HotService");

            // ③ 创建新实例
            Object service = clazz.getConstructor().newInstance();

            // ④ 调用方法
            Method method = clazz.getMethod("process");
            method.invoke(service);

            Thread.sleep(3000);  // 每 3 秒检查一次
        }
    }
}

// 修改 com.example.HotService 的源码 → 重新编译
// 下次循环时新 ClassLoader 会加载新的字节码
// → 热替换成功！
```

### JVM 内置 HotSwap（Instrumentation）

```java
// JDK 5+ 的 Instrumentation API 支持"方法体级别"的热替换
// 可以在不创建新 ClassLoader 的情况下替换方法体

// 限制：只能替换方法体，不能增删字段/方法
// → DCEVM 补丁可以突破这个限制

public class HotSwapAgent {
    public static void premain(String args, Instrumentation inst) {
        // inst.redefineClasses(new ClassDefinition(clazz, newBytes));
        // ↑ 只能替换方法体
    }

    public static void agentmain(String args, Instrumentation inst) {
        // 运行时 attach
    }
}
```

---

## 16. Arthas 热更新原理

### Arthas 热更新的完整链路

```
1. 用户执行 jad 命令反编译目标类
   │
   ▼
2. 用户修改反编译后的代码
   │
   ▼
3. 用户执行 mc 命令编译修改后的代码
   │
   ▼
4. 用户执行 redefine 命令热更新
   │  ① 通过 Attach API 连接到目标 JVM
   │  ② 加载 Arthas Agent（Instrumentation）
   │  ③ 读取编译后的 .class 字节码
   │  ④ inst.redefineClasses(new ClassDefinition(clazz, newBytes))
   │
   ▼
5. JVM 替换方法体
   ★ 只替换方法体，不替换类结构
   ★ 已有对象的方法调用会立即使用新逻辑
```

### Attach API 源码

```java
// com.sun.tools.attach.VirtualMachine

public abstract class VirtualMachine {

    // Attach 到目标 JVM
    public static VirtualMachine attach(String id) throws AttachNotSupportedException, IOException {
        // id = 目标 JVM 的 PID
        // 通过 Unix Socket / Windows Pipe 与目标 JVM 通信
        List<AttachProvider> providers = AttachProvider.providers();
        for (AttachProvider provider : providers) {
            try {
                return provider.attachVirtualMachine(new VmIdentifier(id));
            } catch (AttachNotSupportedException e) {
                // 继续尝试下一个 provider
            }
        }
        throw new AttachNotSupportedException();
    }

    // 加载 Agent
    public abstract void loadAgent(String agentPath) throws AgentLoadException, AgentInitializationException;
    // → 目标 JVM 执行 Agent_OnAttach → 启动 arthas-core
    // → arthas-core 调用 Instrumentation API
}
```

### redefine 的限制

```
Instrumentation.redefineClasses 的限制：
  ✓ 可以替换方法体
  ✗ 不能增删方法
  ✗ 不能增删字段
  ✗ 不能更改类继承关系
  ✗ 不能更改方法签名

DCEVM（Dynamic Code Evolution VM）补丁：
  突破了以上限制，支持"结构化"热替换
  可以增删方法/字段/类
  → IntelliJ IDEA 的 HotSwap 默认使用 DCEVM
```

---

# Part 5 — 综合

---

## 17. 常见面试题

### Q1：什么是双亲委派模型？为什么需要它？

```
双亲委派模型：
  当类加载器收到加载请求时，先委托给父加载器加载
  父加载器加载不了，自己才加载

为什么需要：
  ① 安全：防止核心类被篡改（自定义 java.lang.String 不会被加载）
  ② 唯一：保证同一个类在 JVM 中只有一个 Class 对象
  ③ 效率：避免重复加载，父加载器已加载的类不需要再加载

源码体现：
  ClassLoader.loadClass() 中先调用 parent.loadClass()
  parent 为 null 时调用 findBootstrapClassOrNull()
  都找不到才调用自己的 findClass()
```

### Q2：有哪些打破双亲委派的场景？

```
① JDBC / SPI：
  DriverManager 由 Bootstrap 加载，但要加载 classpath 下的 Driver 实现
  → 使用线程上下文类加载器（Thread Context ClassLoader）

② Tomcat：
  每个 Web 应用有自己的 WebAppClassLoader
  优先加载 WEB-INF 下的类，再委托给父加载器
  → 实现 Web 应用之间的类隔离

③ OSGi：
  每个 Bundle 有自己的 ClassLoader
  类加载器之间是网状关系（而非树状）
  → 实现模块级的热部署

④ 自定义 ClassLoader：
  覆写 loadClass 方法，改变委托逻辑
  → 实现热替换、类隔离等

⑤ JDK 9 模块化：
  PlatformClassLoader 替代 ExtClassLoader
  模块化加载（ModulePath）改变了类的查找方式
```

### Q3：Tomcat 的类加载器为什么要打破双亲委派？

```
原因 1：Web 应用隔离
  两个 Web 应用可能依赖同一个库的不同版本
  如 app1 用 Spring 4，app2 用 Spring 5
  双亲委派只会加载第一个找到的 → 版本冲突

原因 2：Web 应用优先
  Web 应用自己的类应该优先于 Tomcat 公共库中的同名类
  如 Web 应用用了新版的某个工具库

原因 3：JSP 热加载
  JSP 编译后的 Servlet 需要被反复加载
  每次 JSP 修改后创建新的 JspClassLoader 加载新版本
```

### Q4：JDBC 是如何打破双亲委派的？

```
问题：
  DriverManager 在 rt.jar 中（Bootstrap 加载）
  MySQL Driver 在 classpath 中（AppClassLoader 加载）
  Bootstrap 看不到 AppClassLoader 的类

解决：
  ① Launcher 初始化时设置线程上下文类加载器 = AppClassLoader
  ② DriverManager 使用 ServiceLoader.load(Driver.class)
  ③ ServiceLoader 使用 Thread.currentThread().getContextClassLoader()
  ④ 通过 AppClassLoader 加载 classpath 下的 Driver 实现

本质：
  父加载器通过"线程上下文类加载器"逆向使用子加载器
  是双亲委派模型的一个"后门"
```

### Q5：如何自定义 ClassLoader？需要注意什么？

```
步骤：
  ① 继承 ClassLoader
  ② 覆写 findClass()（推荐）或 loadClass()（会打破双亲委派）
  ③ 在 findClass 中读取字节码 → 调用 defineClass()

注意事项：
  ① 推荐覆写 findClass 而非 loadClass（保持双亲委派）
  ② 同一个 ClassLoader 不能重复 defineClass 同一个类
  ③ 如果要重新加载类，必须创建新的 ClassLoader
  ④ 注意不要违反安全策略（不要加载 java. 开头的核心类）
  ⑤ 保证双亲委派对核心类仍然生效
```

### Q6：Tomcat 热加载的原理是什么？

```
原理：
  ① 监控 WEB-INF/classes 和 WEB-INF/lib 的文件变化
  ② 检测到变化 → StandardContext.reload()
  ③ 停止当前 Context（销毁 Servlet/Filter/Listener）
  ④ 丢弃旧的 WebAppClassLoader
  ⑤ 创建新的 WebAppClassLoader
  ⑥ 用新 ClassLoader 重新加载所有类
  ⑦ 重新初始化 Servlet/Filter/Listener

关键点：
  - 旧 ClassLoader 加载的类无法被卸载（除非 ClassLoader 本身被 GC）
  - 创建新 ClassLoader 是热加载的唯一方式
  - 旧 ClassLoader 及其加载的类会在 GC 时被回收

内存泄漏风险：
  - Web 应用创建的线程未销毁（持有旧 ClassLoader 引用）
  - ThreadLocal 未清理
  - JDBC Driver 未注销
  → Tomcat 的 clearReferences() 会主动检测和清理
```

### Q7：Class.forName 和 ClassLoader.loadClass 的区别？

```
Class.forName(String className)：
  ① 使用调用者的 ClassLoader 加载
  ② ★ 会执行类的初始化（<clinit>）
  ③ 等价于 Class.forName(className, true, classLoader)

ClassLoader.loadClass(String name)：
  ① 使用指定的 ClassLoader 加载
  ② ★ 不会执行类的初始化（只加载 + 链接）
  ③ 需要额外调用 Class.forName(name, true, loader) 才会初始化

典型场景：
  // JDBC 注册驱动：需要执行 static 块 → 用 forName
  Class.forName("com.mysql.cj.jdbc.Driver");  // 触发 static { DriverManager.registerDriver(...) }

  // Spring 延迟加载：不需要立即初始化 → 用 loadClass
  ClassLoader.loadClass("com.example.MyService");  // 不触发 <clinit>
```

### Q8：为什么 Bootstrap ClassLoader 不是 Java 类？

```
鸡和蛋的问题：
  ClassLoader 本身也是 Java 类，需要被 ClassLoader 加载
  如果 Bootstrap 是 Java 类，谁来加载它？

解决：
  Bootstrap ClassLoader 由 JVM 的 C++ 代码实现
  它是 JVM 启动时由 C++ 创建的，不需要被 Java 的 ClassLoader 加载

证据：
  String.class.getClassLoader() → null
  Bootstrap 在 Java 层面不存在，返回 null 表示"不适用"
```

### Q9：JDK 9 的模块化对类加载有什么影响？

```
JDK 9 的变化：

1. ExtClassLoader → PlatformClassLoader
   - 加载路径变为模块路径（module path）而非 lib/ext
   - 不再自动加载 lib/ext 下的 JAR

2. AppClassLoader 不再是 URLClassLoader
   - 改为 InternalClassLoader（内部实现）
   - 使用模块路径（module path）查找类

3. 模块化类加载
   - 每个模块有自己的类加载器
   - 模块通过 requires / exports 控制可见性
   - 未 export 的包对其他模块不可见

4. 层级关系不变
   Bootstrap → Platform → App
   双亲委派仍然有效

5. --add-opens / --add-exports
   用于打开模块的反射权限
   框架（Spring/Hibernate）大量使用
```

### Q10：如何排查 ClassNotFoundException 和 NoClassDefFoundError？

```
ClassNotFoundException：
  异常：java.lang.ClassNotFoundException
  抛出时机：类加载时找不到 .class 文件
  抛出者：ClassLoader.loadClass() / Class.forName()
  原因：
    ① 类路径下没有对应的 .class 文件
    ② JAR 包没有包含该类
    ③ ClassLoader 配置错误
  排查：
    - 检查 classpath / JAR 包中是否存在该类
    - jar tf xxx.jar | grep ClassName
    - 检查 ClassLoader 的 URL 列表

NoClassDefFoundError：
  错误：java.lang.NoClassDefFoundError
  抛出时机：类已成功加载过，但运行时找不到（或初始化失败）
  抛出者：JVM 运行时
  原因：
    ① 类的静态初始化块抛异常 → 初始化失败
    ② 类曾经存在但被删除（热部署场景）
    ③ 依赖的类找不到（A 依赖 B，B 找不到）
  排查：
    - 检查是否有 ExceptionInInitializerError（静态块异常）
    - 检查依赖类是否都存在
    - 检查是否有 ClassLoader 泄漏（旧 ClassLoader 未释放）

区别：
  ClassNotFoundException = 从来没找到过
  NoClassDefFoundError = 曾经找到过但现在找不到了（或初始化失败）
```

---

> 本文档从 JVM 原生类加载体系出发，经过 SPI 的逆向委派桥接，深入到 Tomcat 的 Web 应用隔离与热加载机制，最后覆盖了自定义 ClassLoader 与 Arthas 热更新的实践。
> 建议学习路径：**Java 类加载基础 → SPI/上下文类加载器 → Tomcat 类加载器 → 热替换**。理解了双亲委派的设计意图和打破场景，Tomcat 的类加载架构就是水到渠成的应用。
