---
title: Java 基础面试理论-答案版
tags:
  - Java
  - Interview-answer
---
#flashcards/Java/basic/theory
## 一、值传递 & 基本概念（经典必考）

### **Q1** 为什么说 Java 中只有值传递？如果传的是引用类型，能在方法内改变原始对象的值吗？写一段代码证明。
?
Java 只有值传递，意思是方法调用时传递的是实参的副本，而不是实参本身。基本类型传递的是数值的副本，引用类型传递的是引用地址的副本。对于引用类型，通过这个副本引用可以修改对象内部的状态，比如修改对象的属性，外部能感知到这个变化。但是如果在方法内让这个引用副本指向新的对象，不会影响外部的原始引用。证明方法很简单：写一个方法接收一个对象参数，在方法内部将参数赋值为 null 或指向新对象，方法返回后外部变量仍然指向原来的对象。这就说明传递的是引用的副本，不是引用本身。

### **Q2** `int` 和 `Integer` 的区别？自动装箱拆箱怎么实现的？`Integer` 缓存范围是多少？`new Integer(100)` 和 `Integer.valueOf(100)` 用 `==` 比较会怎样？
?
int 是基本类型，存储在栈上，不占堆内存，没有方法可以调用。Integer 是包装类，存储在堆上，可以为 null，提供了很多工具方法。自动装箱拆箱是编译器在编译阶段自动插入 Integer.valueOf 和 intValue 调用实现的，从字节码层面能看到这些方法的调用。Integer 默认缓存范围是 -128 到 127，可以通过 JVM 参数调整上限。new Integer(100) 和 Integer.valueOf(100) 用 == 比较结果为 false，因为 new Integer(100) 每次在堆上创建新对象，而 Integer.valueOf(100) 从缓存中取值。100 在缓存范围内，所以 valueOf 返回的是同一个缓存对象。

---

## 二、面向对象（经典 + JDK8/9）

### **Q3** 多态的实现机制是什么？静态绑定和动态绑定的区别？为什么说「父类引用指向子类对象」？
?
多态的实现依赖于动态绑定机制。编译时，编译器只知道引用变量的声明类型，不确定实际指向哪个子类对象。运行时，JVM 根据对象的实际类型从方法表中查找对应的方法实现来调用。静态绑定发生在编译期，适用于私有方法、静态方法和 final 方法，它们没有多态，调用地址在编译时就确定了。动态绑定发生在运行期，适用于可被重写的实例方法，JVM 通过虚方法表在运行时确定具体调用哪个版本。"父类引用指向子类对象"就是说声明类型和实际类型可以不同，声明类型决定了能调用哪些方法，实际类型决定了调用哪个实现版本。这种设计实现了系统对扩展开放、对修改关闭。

### **Q4** 重载（Overload）和重写（Override），从方法签名、绑定时机、访问修饰符、返回类型、异常五个维度对比。
?
方法签名上，重载要求方法名相同但参数列表不同，重写要求方法签名完全一致。绑定时机上，重载是静态绑定，编译期就确定调用哪个方法，看的是引用类型；重写是动态绑定，运行期根据实际对象类型确定，看的是对象类型。访问修饰符上，重载没有限制；重写的方法访问修饰符不能比父类更严格，但可以更宽松。返回类型上，重载可以完全不同；重写在 JDK5 之后允许返回协变类型，即子类方法的返回值可以是父类方法返回值的子类型。异常上，重载没有限制；重写的方法不能抛出比父类更宽泛的受检异常。

### **Q5** 接口和抽象类的区别？JDK8 `default` 方法解决了什么问题？JDK9 `private` 方法又解决了什么？
?
抽象类可以有构造方法、成员变量和已实现的方法，一个类只能继承一个抽象类，表达的是"是什么"的关系。接口在 JDK8 之前只能有抽象方法和常量，一个类可以实现多个接口，表达的是"能做什么"的能力。JDK8 引入 default 方法是为了解决接口演进问题：当需要在已有接口中添加新方法时，如果只能加抽象方法，所有实现类都必须修改。default 方法提供默认实现，实现类可以不重写，保证了向后兼容。JDK9 引入 private 方法是为了在接口内部复用代码：多个 default 方法之间可能有公共逻辑需要抽取，private 方法提供了这个能力而不会暴露给实现类。

### **Q6** 匿名内部类为什么只能引用「effectively final」的外部变量？这个限制在 JDK8 之后发生了什么变化？Lambda 表达式有同样的限制吗？
?
匿名内部类之所以有 effectively final 的限制，根本原因是内部类和外部类访问的是不同变量——内部类持有的是外部变量的副本。如果外部变量可以被修改，内部类中的副本和外部原始变量的值就会不一致，造成语义上的混乱。所以 Java 强制要求外部变量不可变，以保证两者一致。JDK8 引入了 effectively final 的概念：变量即使没有被 final 修饰，只要实际上没有被重新赋值，编译器也会将其视为最终变量。这个限制对 Lambda 表达式同样适用，Lambda 捕获的外部变量也必须是 effectively final。如果不满足，编译器会直接报错。

### **Q7** 静态内部类和非静态内部类的区别？什么场景用静态内部类（比如 Builder 模式）？
?
静态内部类和非静态内部类最核心的区别在于是否持有外部类的引用。静态内部类不持有外部类的引用，可以独立存在，它的实例化和静态方法调用与普通类一样。非静态内部类隐式持有外部类的 this 引用，必须先有外部类实例才能创建。这个区别导致了几个重要差异：静态内部类可以定义静态成员，非静态内部类不能；静态内部类不会导致外部类无法被 GC，非静态内部类如果还活着外部类就回收不了。Builder 模式使用静态内部类就是因为 Builder 不需要访问外部对象的状态，它只需要收集参数然后构造目标对象。如果用了非静态内部类，会多一个无用的外部类引用，既不必要还可能阻止 GC。

---

## 三、equals / hashCode / String（经典必考）

### **Q8** 为什么重写 `equals()` 必须重写 `hashCode()`？如果只重写 `equals`，存到 HashMap 里会发生什么？画个流程说明。
?
原因在于 Object 规范中的约定：如果两个对象 equals 相等，它们的 hashCode 也必须相等。HashMap 判断 key 是否重复时先比较 hashCode，hashCode 不等直接判定为不同 key，不会走到 equals 比较。如果只重写 equals 不重写 hashCode，两个 equals 相等的对象可能因为 hashCode 不同被 HashMap 放进两个不同的桶里，导致 containsKey 返回 false，get 返回 null，这违反了 HashSet 和 HashMap 的语义约定。举个例子，如果两个内容完全相同的自定义对象，hashCode 默认是 Object 的内存地址哈希，它们会被分配到不同桶，用其中一个做 key put 进去，用另一个去 get 永远返回 null，哪怕它们 equals 返回 true。

### **Q9** `String` 为什么设计成不可变的？从安全性、线程安全、字符串常量池、HashMap key 四个角度说清楚。
?
安全性方面，String 广泛用于类名、文件路径、网络连接参数等，如果可变，恶意代码可能篡改这些关键信息。比如数据库连接 URL 如果在传递过程中被修改，后果很严重。线程安全方面，不可变性天然保证了多线程环境下的安全性，任何线程读取同一个 String 都不会看到中间状态，不需要加锁。字符串常量池方面，不可变性使得字符串常量池成为可能：不同引用可以共享同一个字符串对象，如果可变，一处修改会影响到所有引用者。HashMap key 方面，String 作为最常用的 key 类型，不可变保证了 hashCode 永远不变，不会出现前面说的存进去取不出来的问题。

### **Q10** `String s = new String("hello")` 创建了几个对象？每个对象在 JVM 什么区域？换成 `String s = "hello"` 呢？
?
new String("hello") 创建了两个对象。首先 "hello" 本身是一个字符串常量，在类加载时被创建并放入字符串常量池，存储在方法区的运行时常量池中（JDK8 之后在堆中的元空间关联区域）。然后 new String 在堆上又创建了一个新的 String 对象，这个对象的内部 char 数组指向常量池中 "hello" 的字符数组。如果常量池中已经存在 "hello"，那就只创建一个对象，即堆上的 new String 实例。String s = "hello" 则只在常量池中查找，如果已存在则直接返回引用，不创建新对象；如果不存在则创建一个对象放入常量池。

---

## 四、异常体系（经典 + Spring 实战）

### **Q11** 受检异常（Checked）和非受检异常（Unchecked）的设计意图是什么？Spring 的 `@Transactional` 对两种异常的回滚行为有什么不同？为什么这么设计？
?
受检异常的设计意图是强制调用方处理可预见的异常情况，比如文件不存在、网络超时，这些是调用方可以恢复或重试的。非受检异常通常是编程错误或不可恢复的运行时错误，比如空指针、数组越界，这些不应该被捕获处理，应该让程序快速失败、暴露问题。Spring 的 @Transactional 默认只对非受检异常（RuntimeException 及其子类）和 Error 进行回滚，对受检异常默认不回滚。这是因为 Spring 认为受检异常通常是业务异常，调用方有意处理就会主动捕获，事务不应随意回滚；而非受检异常意味着意料之外的错误，事务应该回滚以保证数据一致性。也可以通过 rollbackFor 属性显式指定对哪些受检异常回滚。

### **Q12** `finally` 中如果有 `return`，`try` 里的 `return` 还会执行吗？从字节码层面解释发生了什么。
?
finally 中的 return 会覆盖 try 中的 return。从字节码层面来看，try 块中的 return 指令会先将返回值压入操作数栈，然后跳转到 finally 块执行。如果 finally 块中也有 return，它会在操作数栈上压入自己的返回值，原来的返回值就被覆盖了。最终返回的是 finally 中 return 的值。更极端的情况，如果 try 中抛出了异常但 finally 中有 return，这个异常会被吞掉，不会向上抛出，调用方完全感知不到异常。因此 finally 中写 return 是一个不推荐的做法。

### **Q13** `try-with-resources` 的原理？实现 `AutoCloseable` 接口后，多个资源的关闭顺序是怎样的？如果 `close()` 本身抛异常会怎样？
?
try-with-resources 是 JDK7 引入的语法糖。编译后会在 finally 中自动生成 close 调用，同时会处理关闭时可能抛出的异常。实现 AutoCloseable 接口后，多个资源的关闭顺序与声明顺序相反，后声明的先关闭。如果 close 方法本身抛出异常，这个异常会被压制（suppressed）。如果 try 块正常执行但 close 抛异常，这个异常会作为主异常抛出。如果 try 块先抛了异常然后 close 也抛异常，try 块的异常是主异常，close 的异常会被压制成 suppressed 异常追加到主异常后面，可以通过 Throwable.getSuppressed 获取。这个机制保证了不会因为关闭操作丢失原始异常信息。

---

## 五、泛型（经典必考）

### **Q14** Java 泛型的类型擦除是什么？为什么会有擦除？擦除后泛型信息真的完全消失吗？（提示：反射能拿到部分信息吗？）
?
类型擦除指的是编译器在编译期间将泛型类型参数替换为限定类型（没有限定就是 Object），生成的字节码中不包含具体的泛型类型信息。之所以需要擦除，是为了向后兼容 JDK5 之前没有泛型的代码，让老版本字节码能运行在新版本 JVM 上。但擦除后泛型信息并非完全消失。编译器会在字节码的 Signature 属性和局部变量类型表中保留泛型声明信息，通过反射的 ParameterizedType 可以拿到类或方法上的泛型参数声明，比如获取某个字段的泛型类型。但运行时的具体泛型实参是无法获取的，比如一个 `List<String>` 在运行时就是一个普通的 List。

### **Q15** 上界通配符 `<? extends T>` 和下界通配符 `<? super T>` 的区别？为什么 `List<? extends Fruit>` 不能 add 元素？PECS 原则怎么用？
?
? extends T 表示类型是 T 或 T 的某个子类，但具体是哪个子类编译器不知道，所以只能从中获取元素（返回类型是 T），不能添加元素——因为不知道实际类型，编译器无法保证类型安全。? super T 表示类型是 T 或 T 的某个父类，可以添加 T 及其子类型的元素，但获取时只能得到 Object 类型。为什么 `List<? extends Fruit>` 不能 add？假设实际类型是 `List<Apple>`，你往里放一个 Banana，就破坏了类型安全。编译器为了杜绝这种可能性，直接禁止 add（除了 null）。PECS 原则是 Producer Extends, Consumer Super，即如果集合用于提供数据给外部使用，用 extends；如果集合用于接收外部数据，用 super。

### **Q16** 泛型方法、泛型类、泛型接口的区别？写一个泛型方法 `<T> T getFirst(List<T> list)` 的完整声明。
?
泛型类是在类声明时定义类型参数，例如 class `Box<T>`，这个 T 在整个类的范围内有效。泛型方法是独立于类泛型声明的方法，自己的类型参数只在方法范围内有效，即使类本身没有泛型参数也可以有泛型方法。泛型接口与泛型类相同，定义在接口层面。一个关键的区别是泛型方法的类型参数可以独立推断，与类无关。getFirst 方法的完整声明是：public `<T>` T getFirst(`List<T>` list)，类型参数 T 声明在返回值类型之前，方法的泛型参数由调用时传入的实参自动推断。如果方法声明为 static，不能用类的泛型参数，必须定义自己的泛型参数。

---

## 六、反射 & 代理 & SPI（经典必考）

### **Q17** `Class.forName()` 和 `ClassLoader.loadClass()` 的区别？会触发静态初始化吗？JDBC 驱动加载为什么用 `forName`？
?
Class.forName 默认会触发类的静态初始化，即执行静态代码块和静态变量初始化；而 ClassLoader.loadClass 只加载类，不触发初始化。JDBC 驱动加载之所以用 Class.forName，是因为驱动类中通常有一个静态代码块，在该块中调用 DriverManager.registerDriver 将自己注册到驱动管理器中。如果不执行这个静态代码块，驱动就不会被注册，后续创建连接时会找不到合适的驱动。不过从 JDK6 开始，JDBC 4.0 引入了 SPI 机制，通过 META-INF/services 下的配置文件自动加载驱动，不再需要手动调用 Class.forName。

### **Q18** JDK 动态代理和 CGLIB 的区别？Spring AOP 什么时候用 JDK 代理，什么时候用 CGLIB？Spring Boot 2.x 为什么默认改为 CGLIB？
?
JDK 动态代理基于接口，被代理的类必须实现至少一个接口，通过 Proxy.newProxyInstance 在运行时动态生成代理类，代理类实现了与被代理类相同的接口。CGLIB 基于继承，通过 ASM 字节码技术生成被代理类的子类，在子类中拦截方法调用。Spring AOP 的默认策略是：如果目标对象实现了接口，使用 JDK 动态代理；如果没有实现接口，使用 CGLIB。也可以强制使用 CGLIB。Spring Boot 2.x 默认改为 CGLIB 的原因是，基于接口的代理在某些场景下会导致类型转换问题，而且配置起来更繁琐。统一使用 CGLIB 后，代理逻辑更一致，同时避免了因忘记配置导致的代理失效问题。CGLIB 的局限是无法代理 final 类和 final 方法。

### **Q19** Java SPI 的加载机制，`ServiceLoader` 有什么缺点？Dubbo SPI 做了哪些改进？（至少说 3 点）
?
Java SPI 通过在 META-INF/services 目录下以接口全限定名命名的文件中写入实现类全限定名，ServiceLoader 读取这些文件并实例化所有实现类。它的缺点包括：会一次性加载并实例化所有实现类，无法按需加载；不支持加载时的依赖注入，所有实现类必须有无参构造；不支持实现类的别名和优先级等元信息；加载失败时缺少详细的错误信息。Dubbo SPI 的改进主要有：支持按名称按需加载，通过 @SPI 注解指定默认实现，配置文件中 key=value 格式支持别名；支持 AOP 和 IOC，扩展点之间可以互相注入；支持扩展点自适应，可以通过 @Adaptive 动态生成代理类，根据 URL 参数选择实现；提供了扩展点的包装机制和激活机制。

---

## 七、序列化

### **Q20** `serialVersionUID` 不指定会怎样？`transient` 和 `static` 字段分别会被序列化吗？如果必须序列化 transient 字段，怎么绕过？
?
如果不指定 serialVersionUID，JVM 会根据类的结构（类名、成员、方法签名等）自动生成一个哈希值。这意味着如果类的结构发生任何变化，新旧版本的 serialVersionUID 就不一致了，反序列化时会抛出 InvalidClassException。transient 字段不会被默认序列化，反序列化后该字段为默认值。static 字段属于类级别，不属于对象实例，所以不会被序列化。如果必须序列化 transient 字段，可以自定义 writeObject 和 readObject 方法，在 writeObject 中调用 defaultWriteObject 后手动序列化 transient 字段，在 readObject 中使用 defaultReadObject 后再手动反序列化这些字段。

### **Q21** Java 原生序列化的缺点是什么？为什么现在流行 JSON / Protobuf？你在项目里怎么选型的？
?
Java 原生序列化有几个明显的缺点：序列化后体积大，包含了大量类元信息；性能差，反射操作开销大；安全性差，反序列化漏洞频发，可以构造恶意数据执行任意代码；跨语言不友好，仅限于 Java 生态；版本兼容性弱，类结构变化容易导致反序列化失败。JSON 可读性好、跨语言、生态成熟，适合 Web API 和需要人工调试的场景。Protobuf 二进制编码，体积小速度快，IDL 定义强类型契约，天然支持前后向兼容，适合高性能 RPC 和数据存储场景。项目选型上，内部微服务间通信优先选 Protobuf，对外 API 和前端交互用 JSON，跨系统消息队列的数据格式也倾向于 Protobuf 或 Avro。

---

## 八、Stream API（现代 Java 必问）

### **Q22** `Stream` 的中间操作和中间操作分别有哪些？`map`、`flatMap`、`filter`、`reduce`、`collect` 的区别？
?
Stream 的操作分为中间操作和终端操作。中间操作返回一个新的 Stream，可以链式调用，属于惰性求值，常见的有 map、flatMap、filter、distinct、sorted、limit、skip、peek 等。终端操作触发实际计算并返回结果或副作用，常见的有 forEach、collect、reduce、count、findFirst、anyMatch、allMatch、noneMatch。map 是一对一转换，输入一个元素输出一个新元素；flatMap 是一对多转换，将每个元素展开为一个 Stream 再合并，常用于嵌套集合的扁平化；filter 是过滤筛选；reduce 是归约操作，将流中元素按二元操作聚合为一个值；collect 是收集操作，将流元素汇总到集合或进行分组、分区等复杂聚合。

### **Q23** Stream 的惰性求值是什么意思？给你一段代码：`list.stream().filter(...).map(...)`，如果不调用终端操作，前面的 filter 会执行吗？
?
惰性求值指的是中间操作不会立即执行，只是构建了一个操作流水线，记录了每一步要做什么。只有在终端操作被调用时，整个流水线才会被触发执行。因此 list.stream().filter().map() 如果不接终端操作，不会执行任何过滤或映射逻辑，连一次迭代都不会发生。这个设计的优势在于可以进行短路优化，比如 findFirst 操作在找到第一个满足条件的元素后就停止遍历，不需要处理整个流。也支持融合优化，将相邻的中间操作合并为一个遍历过程。

### **Q24** `parallelStream` 的原理？底层用的是什么线程池？为什么不要在 `parallelStream` 里做阻塞 IO 操作？
?
parallelStream 底层使用 ForkJoinPool，默认线程数是 CPU 核心数减一。它通过 RecursiveTask 将数据分片，递归地将任务分解为小任务并行执行，然后合并结果。不能在里面做阻塞 IO 操作的原因是，ForkJoinPool 采用工作窃取算法，线程数量有限。如果一个线程在阻塞 IO 上等待，它占着线程位置不干活，其他任务就得排队，严重削弱并行效果。更危险的是如果阻塞操作依赖并行流本身的结果，可能因为线程全被阻塞而导致死锁。阻塞 IO 操作应该放在自定义线程池中执行。

### **Q25** 有一个 `List<String>` 用 `stream().distinct().count()` 去重计数，和用 `new HashSet<>(list).size()` 比，各自优缺点？
?
new HashSet<>(list).size() 直接将所有元素放入 HashSet 中再去取大小。优点是实现简洁，利用 HashSet 天然的去重能力。缺点是需要额外的内存持有整个去重后的集合，数据量大时内存占用高。stream().distinct().count() 也是利用 HashSet 去重，底层实现和前者几乎一致，distinct 操作内部维护了一个 LinkedHashSet 来记录已出现的元素。两者的区别更多在于代码风格和管道可组合性：Stream 方式可以和 filter、map 等操作组合成更复杂的数据处理管道，但单纯去重计数场景下两者性能差异微乎其微。

---

## 九、Lambda & Optional（现代 Java 必问）

### **Q26** 什么是函数式接口（`@FunctionalInterface`）？Java 内置了哪些常用的函数式接口？`Predicate`、`Function`、`Consumer`、`Supplier` 各自签名？
?
函数式接口是只有一个抽象方法的接口，可以用 Lambda 表达式或方法引用来实现。@FunctionalInterface 注解不是必须的，但加上后编译器会检查接口是否符合函数式接口的定义。Java 内置的常用函数式接口包括：`Predicate<T>`，方法签名是 boolean test(T t)，用于条件判断；`Function<T, R>`，签名是 R apply(T t)，用于类型转换；`Consumer<T>`，签名是 void accept(T t)，用于消费数据不返回结果；`Supplier<T>`，签名是 T get()，用于提供数据无输入有输出。此外还有 BiFunction、BiConsumer、UnaryOperator、BinaryOperator 等变体。

### **Q27** Lambda 表达式里的 `this` 和匿名内部类里的 `this` 指向一样吗？Lambda 是语法糖吗，底层怎么实现的？
?
指向不一样。匿名内部类中 this 指向匿名内部类实例本身，而 Lambda 表达式没有自己的 this，它内部的 this 指向的是定义 Lambda 的包围类的实例。这是两者很重要的语义区别。Lambda 不是简单的语法糖，它不是编译成匿名内部类，而是通过 invokedynamic 指令在运行时动态生成实现。JDK 在运行时利用 LambdaMetafactory 和 MethodHandle 将 Lambda 绑定到对应的函数式接口上，生成一个内部类，但这个过程是在运行时发生的，比传统的编译期匿名内部类更高效。这也是为什么 Lambda 表达式的字节码体积更小。

### **Q28** `Optional` 的设计初衷是什么？`orElse()` 和 `orElseGet()` 有什么区别？什么情况下 Optional 反而成了反模式？
?
Optional 的设计初衷是提供一种更优雅的方式来处理可能为 null 的值，明确表达"这个值可能不存在"的语义，避免到处做 null 检查。orElse 和 orElseGet 的关键区别在于参数求值时机：orElse 的参数无论 Optional 是否有值都会执行；orElseGet 的参数（一个 Supplier）只有在 Optional 为空时才会执行。所以如果获取默认值的操作开销大，应该用 orElseGet 而不是 orElse。Optional 成为反模式的场景包括：作为方法参数传递，这增加了调用方的负担；在集合中使用，比如 List<`Optional<T>`>，通常用空集合或者过滤后的集合更合理；用作类的字段，特别是在序列化时会有问题。Optional 最适合作为返回值来声明可能为空的结果。

### **Q29** 给定 `Optional<String> opt = Optional.ofNullable(null)`，`opt.orElse(getDefault())` 和 `opt.orElseGet(() -> getDefault())` 执行结果有没有区别？`getDefault()` 会被调用吗？
?
两者的返回结果没有区别，都是返回 getDefault() 的值。但 getDefault() 的执行情况不同。opt.orElse(getDefault()) 中，getDefault() 会立即执行，无论 opt 是否有值。因为 orElse 接收的是一个已经计算好的值，参数必须先求值再传递。而 opt.orElseGet(() -> getDefault()) 中，getDefault() 只有在 opt 为空时才会执行，因为传入的是一个 Supplier，延迟求值。如果 getDefault() 是一个昂贵的操作，或者有副作用，这两者的行为差异就很重要了。用 orElseGet 可以避免不必要的计算。

---

## 十、Java 新版本特性（拉开分差）

### **Q30** `var`（JDK10）关键字的作用？什么场景适合用 var，什么场景不该用？`var` 能否用于 Lambda 参数（JDK11）？
?
var 关键字用于局部变量的类型推断，编译器根据右侧的初始化表达式自动推断出变量类型，编译后的字节码中仍然是强类型的。适合用 var 的场景包括：右侧类型非常明显时，比如 new `ArrayList<String>`()，可以减少重复的类型声明；复杂泛型类型时，让代码更简洁。不该用的场景是：右侧表达式不够明确时，比如 var result = process()，阅读代码时无法直接知道 result 的类型，降低了可读性。JDK11 开始支持在 Lambda 参数上使用 var，主要用途是可以给 Lambda 参数添加注解，因为只用参数名无法加注解，而显式类型加注解又太冗余，var 提供了一个折中方案。

### **Q31** Record（JDK14/16）是什么？它能替代 Lombok 的 `@Data` 吗？Record 的 `equals()`/`hashCode()`/`toString()` 是怎么生成的？和普通类有什么限制？
?
Record 是一种透明的数据载体，用一行声明定义不可变的数据类，编译器自动生成构造方法、equals、hashCode、toString 和访问器方法。Record 不能完全替代 Lombok 的 @Data，因为 @Data 生成的是可变类，有 setter 方法；Record 是不可变的，所有字段都是 final，更接近于 @Value。Record 的 equals 和 hashCode 基于所有组件字段生成，toString 也包含所有组件。Record 的限制包括：不能继承其他类（隐式继承 java.lang.Record），不能被继承（隐式 final），字段全部 final 不可变，不能声明额外的实例字段。Record 适用于数据传输对象、配置载体、复合键值等纯数据的场景。

### **Q32** Sealed Class（JDK17）解决了什么问题？和 `final` 有什么区别？写一段 sealed class 的声明示例。
?
Sealed Class 解决的是继承控制问题：它允许类的作者显式声明哪些类可以继承自己，其他外部类不能继承。和 final 的区别在于，final 彻底禁止继承，而 sealed 允许指定的子类继承，是一种有限开放。Sealed Class 的声明示例：public sealed class Shape permits Circle, Rectangle, Triangle。permits 子句列出了所有允许的子类。被 permits 的类必须声明为 final、sealed 或 non-sealed。non-sealed 表示重新打开继承，允许任意子类。Sealed Class 配合 switch 表达式和模式匹配使用时，编译器可以进行穷举性检查，确保所有子类都被覆盖。

### **Q33** `switch` 表达式（JDK14）和 `instanceof` 模式匹配（JDK16）分别改进了什么？写一段 `instanceof` 模式匹配的示例代码。
?
switch 表达式的主要改进是可以用箭头语法直接返回值，避免了传统 switch 中 break 的遗漏导致的 fall-through 问题；支持使用 yield 关键字在代码块中返回值；编译器对 enum 进行穷举检查。instanceof 模式匹配的改进是消除了强制类型转换的模板代码：以前需要 if (obj instanceof String) { String s = (String) obj; ... }，现在可以直接写 if (obj instanceof String s) { ... }，在判断成功后 s 变量直接可用，类型推断和绑定一步完成。这个语法在条件判断、equals 方法实现等场景中大大简化了代码。

### **Q34** Text Block（JDK15）的语法？它和普通字符串拼接有什么底层区别？用 Text Block 写 JSON 字符串有什么好处？
?
Text Block 用三个双引号开头和结尾，中间可以跨多行书写文本，缩进会被自动处理，编译器会在编译时去除公共的前导空白。和普通字符串拼接的区别在于底层处理方式不同：Text Block 在编译期就处理完了缩进和转义，运行时就是一个普通的字符串对象，不存在运行时拼接开销。用 Text Block 写 JSON 的好处是：不需要用加号拼接和手动加换行符，不需要转义内部的引号，缩进自动对齐。代码的可读性大幅提升，写出的 JSON 在源码中就是它实际的样子，维护和理解都更直观。

---

## 十一、其他高频基础

### **Q35** `BigDecimal` 为什么不能用 `new BigDecimal(double)`？`equals()` 和 `compareTo()` 比较 `BigDecimal("1.0")` 和 `BigDecimal("1.00")` 结果一样吗？
?
new BigDecimal(double) 会产生精度问题，因为 double 本身是近似值，不能精确表示很多小数。比如 new BigDecimal(0.1) 的结果是 0.100000000000000005551...，而不是精确的 0.1。正确做法是用 new BigDecimal("0.1") 字符串构造，或者用 BigDecimal.valueOf(0.1)。equals 和 compareTo 比较 BigDecimal("1.0") 和 BigDecimal("1.00") 的结果不一样。equals 比较会同时考虑数值和精度，1.0 和 1.00 精度不同就返回 false。compareTo 只比较数值大小，忽略精度差异，所以返回 0 表示相等。通常在 HashSet 或 HashMap 中用 BigDecimal 做 key 时要注意这个区别。

### **Q36** `final`、`finally`、`finalize` 的区别？`finalize` 在 JDK9 被标记为 `@Deprecated`，JDK18 彻底移除，替代方案是什么？
?
final 是修饰符，可以修饰类（不可继承）、方法（不可重写）、变量（不可修改）。finally 是异常处理的一部分，保证无论是否抛出异常都会执行的代码块，通常用于释放资源。finalize 是 Object 类的方法，在对象被 GC 回收前由 JVM 调用，用于最后的清理工作。finalize 被废弃和移除的原因包括：执行时机不确定，完全依赖 GC，可能很久才执行甚至不执行；性能开销大，需要 JVM 额外的跟踪和处理；存在复活对象的安全隐患，finalize 中可以重新引用对象导致无法回收。替代方案是使用 Cleaner 和 PhantomReference，或实现 AutoCloseable 接口配合 try-with-resources 进行显式资源释放。

### **Q37** 深拷贝和浅拷贝的区别？手写一个 `User` 对象的深拷贝（`User` 里有个 `Address` 对象），至少给出两种实现方式。
?
浅拷贝只复制对象本身，基本类型字段复制值，引用类型字段复制引用，这意味着拷贝后的对象和原对象共享引用类型的字段。深拷贝则递归地复制整个对象图，拷贝出的对象和原对象在内存中完全独立。实现深拷贝的常见方式有：通过序列化和反序列化，将对象序列化为字节流再从字节流恢复，利用序列化天然递归遍历对象图的特性；通过克隆构造方法，在 User 的拷贝构造方法中 new 一个新的 Address 赋值；通过 BeanUtils.copyProperties 或手动逐个字段复制。序列化方式最彻底但性能开销最大，构造方法方式最可控但需要逐个处理嵌套对象。

### **Q38** JDK9 模块化系统（JPMS）解决了什么问题？`module-info.java` 里 `requires` 和 `exports` 的作用？Spring Boot 为什么没有强制用 JPMS？
?
JPMS 解决的几个核心问题：可靠的配置和强封装。传统的 classpath 没有模块边界的概念，所有 public 类对所有 jar 可见，内部 API 常被外部意外依赖，导致框架升级困难。JPMS 通过模块声明限制哪些包对外暴露，哪些模块可以访问。module-info.java 中 requires 声明当前模块依赖哪些外部模块，exports 声明当前模块的哪些包允许外部访问。Spring Boot 没有强制使用 JPMS 的主要原因是生态兼容性：大量第三方库还没有模块化，强制 JPMS 会导致大量兼容性问题。Spring Boot 的策略是提供一个兼容层：有 module-info 的 jar 自动识别，没有的就用自动模块处理，保证逐步迁移的平滑性。
