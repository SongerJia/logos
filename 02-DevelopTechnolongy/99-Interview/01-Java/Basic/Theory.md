---
title: Java 基础面试理论
tags:
  - Java
  - Interview
---

## 一、值传递 & 基本概念（经典必考）

> **Q1** 为什么说 Java 中只有值传递？如果传的是引用类型，能在方法内改变原始对象的值吗？写一段代码证明。

> **Q2** `int` 和 `Integer` 的区别？自动装箱拆箱怎么实现的？`Integer` 缓存范围是多少？`new Integer(100)` 和 `Integer.valueOf(100)` 用 `==` 比较会怎样？

---

## 二、面向对象（经典 + JDK8/9）

> **Q3** 多态的实现机制是什么？静态绑定和动态绑定的区别？为什么说「父类引用指向子类对象」？

> **Q4** 重载（Overload）和重写（Override），从方法签名、绑定时机、访问修饰符、返回类型、异常五个维度对比。

> **Q5** 接口和抽象类的区别？JDK8 `default` 方法解决了什么问题？JDK9 `private` 方法又解决了什么？

> **Q6** 匿名内部类为什么只能引用「effectively final」的外部变量？这个限制在 JDK8 之后发生了什么变化？Lambda 表达式有同样的限制吗？

> **Q7** 静态内部类和非静态内部类的区别？什么场景用静态内部类（比如 Builder 模式）？

---

## 三、equals / hashCode / String（经典必考）

> **Q8** 为什么重写 `equals()` 必须重写 `hashCode()`？如果只重写 `equals`，存到 HashMap 里会发生什么？画个流程说明。

> **Q9** `String` 为什么设计成不可变的？从安全性、线程安全、字符串常量池、HashMap key 四个角度说清楚。

> **Q10** `String s = new String("hello")` 创建了几个对象？每个对象在 JVM 什么区域？换成 `String s = "hello"` 呢？

---

## 四、异常体系（经典 + Spring 实战）

> **Q11** 受检异常（Checked）和非受检异常（Unchecked）的设计意图是什么？Spring 的 `@Transactional` 对两种异常的回滚行为有什么不同？为什么这么设计？

> **Q12** `finally` 中如果有 `return`，`try` 里的 `return` 还会执行吗？从字节码层面解释发生了什么。

> **Q13** `try-with-resources` 的原理？实现 `AutoCloseable` 接口后，多个资源的关闭顺序是怎样的？如果 `close()` 本身抛异常会怎样？

---

## 五、泛型（经典必考）

> **Q14** Java 泛型的类型擦除是什么？为什么会有擦除？擦除后泛型信息真的完全消失吗？（提示：反射能拿到部分信息吗？）

> **Q15** 上界通配符 `<? extends T>` 和下界通配符 `<? super T>` 的区别？为什么 `List<? extends Fruit>` 不能 add 元素？PECS 原则怎么用？

> **Q16** 泛型方法、泛型类、泛型接口的区别？写一个泛型方法 `<T> T getFirst(List<T> list)` 的完整声明。

---

## 六、反射 & 代理 & SPI（经典必考）

> **Q17** `Class.forName()` 和 `ClassLoader.loadClass()` 的区别？会触发静态初始化吗？JDBC 驱动加载为什么用 `forName`？

> **Q18** JDK 动态代理和 CGLIB 的区别？Spring AOP 什么时候用 JDK 代理，什么时候用 CGLIB？Spring Boot 2.x 为什么默认改为 CGLIB？

> **Q19** Java SPI 的加载机制，`ServiceLoader` 有什么缺点？Dubbo SPI 做了哪些改进？（至少说 3 点）

---

## 七、序列化

> **Q20** `serialVersionUID` 不指定会怎样？`transient` 和 `static` 字段分别会被序列化吗？如果必须序列化 transient 字段，怎么绕过？

> **Q21** Java 原生序列化的缺点是什么？为什么现在流行 JSON / Protobuf？你在项目里怎么选型的？

---

## 八、Stream API（现代 Java 必问）

> **Q22** `Stream` 的中间操作和终端操作分别有哪些？`map`、`flatMap`、`filter`、`reduce`、`collect` 的区别？

> **Q23** Stream 的惰性求值是什么意思？给你一段代码：`list.stream().filter(...).map(...)`，如果不调用终端操作，前面的 filter 会执行吗？

> **Q24** `parallelStream` 的原理？底层用的是什么线程池？为什么不要在 `parallelStream` 里做阻塞 IO 操作？

> **Q25** 有一个 `List<String>` 用 `stream().distinct().count()` 去重计数，和用 `new HashSet<>(list).size()` 比，各自优缺点？

---

## 九、Lambda & Optional（现代 Java 必问）

> **Q26** 什么是函数式接口（`@FunctionalInterface`）？Java 内置了哪些常用的函数式接口？`Predicate`、`Function`、`Consumer`、`Supplier` 各自签名？

> **Q27** Lambda 表达式里的 `this` 和匿名内部类里的 `this` 指向一样吗？Lambda 是语法糖吗，底层怎么实现的？

> **Q28** `Optional` 的设计初衷是什么？`orElse()` 和 `orElseGet()` 有什么区别？什么情况下 Optional 反而成了反模式？

> **Q29** 给定 `Optional<String> opt = Optional.ofNullable(null)`，`opt.orElse(getDefault())` 和 `opt.orElseGet(() -> getDefault())` 执行结果有没有区别？`getDefault()` 会被调用吗？

---

## 十、Java 新版本特性（拉开分差）

> **Q30** `var`（JDK10）关键字的作用？什么场景适合用 var，什么场景不该用？`var` 能否用于 Lambda 参数（JDK11）？

> **Q31** Record（JDK14/16）是什么？它能替代 Lombok 的 `@Data` 吗？Record 的 `equals()`/`hashCode()`/`toString()` 是怎么生成的？和普通类有什么限制？

> **Q32** Sealed Class（JDK17）解决了什么问题？和 `final` 有什么区别？写一段 sealed class 的声明示例。

> **Q33** `switch` 表达式（JDK14）和 `instanceof` 模式匹配（JDK16）分别改进了什么？写一段 `instanceof` 模式匹配的示例代码。

> **Q34** Text Block（JDK15）的语法？它和普通字符串拼接有什么底层区别？用 Text Block 写 JSON 字符串有什么好处？

---

## 十一、其他高频基础

> **Q35** `BigDecimal` 为什么不能用 `new BigDecimal(double)`？`equals()` 和 `compareTo()` 比较 `BigDecimal("1.0")` 和 `BigDecimal("1.00")` 结果一样吗？

> **Q36** `final`、`finally`、`finalize` 的区别？`finalize` 在 JDK9 被标记为 `@Deprecated`，JDK18 彻底移除，替代方案是什么？

> **Q37** 深拷贝和浅拷贝的区别？手写一个 `User` 对象的深拷贝（`User` 里有个 `Address` 对象），至少给出两种实现方式。

> **Q38** JDK9 模块化系统（JPMS）解决了什么问题？`module-info.java` 里 `requires` 和 `exports` 的作用？Spring Boot 为什么没有强制用 JPMS？
