---
title: JVM 面试理论
tags:
  - Java
  - Interview
---

## 一、内存区域（必问基础）

> **Q1** JVM 运行时数据区域有哪些？每个区域存什么，线程私有还是共享，会抛什么异常？

> **Q2** 方法区 / 元空间（Metaspace）的区别？JDK8 为什么用元空间替代永久代？元空间有大小限制吗？

> **Q3** 字符串常量池在 JDK6、JDK7、JDK8 分别放在哪个区域？为什么要迁移？

> **Q4** 直接内存（Direct Memory）是什么？属于 JVM 运行时数据区吗？NIO 的 `ByteBuffer.allocateDirect()` 和 Heap Buffer 的区别？怎么回收？

> **Q5** 栈溢出（StackOverflowError）和堆溢出（OutOfMemoryError: Java heap space）分别什么场景触发？`-Xss` 参数设置过小和递归过深有什么区别？

---

## 二、对象创建 & 内存布局

> **Q6** 一个 Java 对象从 `new` 到创建完成经历了哪些步骤？分配内存时"指针碰撞"和"空闲列表"分别对应什么 GC 算法？

> **Q7** 对象在堆内存中的布局是怎样的？Mark Word、Klass Pointer、实例数据、对齐填充各自存什么？

> **Q8** 判断对象是否存活的两种方式？GC Roots 包括哪些？可以作为 GC Roots 的对象类型说全。

---

## 三、引用的四种类型

> **Q9** 强引用、软引用、弱引用、虚引用的区别？各自的回收时机和使用场景？

> **Q10** `WeakHashMap` 里的 Entry 继承了 `WeakReference`，key 被 GC 后 value 会自动清理吗？

> **Q11** 虚引用（`PhantomReference`）必须和 `ReferenceQueue` 一起用，它到底有什么用？NIO 的 `Cleaner` 是怎么用虚引用管理直接内存的？

---

## 四、GC 算法 & 分代模型

> **Q12** 标记-清除、标记-整理、复制算法各自的优缺点？为什么新生代用复制算法，老年代用标记-整理？

> **Q13** 分代收集理论中，"跨代引用"是怎么解决的？卡表（Card Table）和写屏障（Write Barrier）是什么？

> **Q14** Minor GC、Major GC、Full GC 的区别？什么时候会触发 Full GC？Full GC 一定是 STW 的吗？

---

## 五、垃圾收集器深度对比

> **Q15** 7 种经典垃圾收集器的组合关系？Serial / ParNew / Parallel Scavenge / Serial Old / Parallel Old / CMS / G1，哪些是新生代，哪些是老年代？

> **Q16** CMS 的四个阶段是什么？哪些阶段 STW？并发标记阶段用了什么算法（三色标记），"漏标"是怎么处理的？（增量更新 Incretal Update）

> **Q17** CMS 有哪些缺点？（内存碎片 / 浮动垃圾 / Concurrent Mode Failure → 降级 Serial Old）

> **Q18** G1 的堆内存布局是怎样的？Region 的四种类型？Humongous 大对象的分配规则？

> **Q19** G1 的回收流程？Young GC（STW）→ 并发标记 → 最终标记（STW）→ 筛选回收（STW）。SATB（Snapshot At The Beginning）和 CMS 的增量更新有什么区别？

---

## 六、ZGC & Shenandoah（低延迟划重点）

> **Q20** ZGC 的核心目标是什么？它凭什么能把 STW 控制在亚毫秒级？染色指针（Colored Pointer）和读屏障（Load Barrier）分别做了什么？

> **Q21** ZGC 的分代回收（JDK21）和非分代回收（JDK11-17）有什么区别？为什么要引入分代？

> **Q22** 你的项目现在用什么垃圾收集器？如果要升级到 ZGC，需要满足什么条件？有什么风险？

---

## 七、类加载 & 双亲委派

> **Q23** 类加载的五个阶段各自做了什么？准备阶段和初始化阶段分别给静态变量赋了什么值？

> **Q24** 双亲委派模型的工作流程？`loadClass()` 源码说清楚。为什么需要双亲委派？

> **Q25** 什么场景需要打破双亲委派？Tomcat 的 `WebappClassLoader` 是怎么打破的？JDBC 的 SPI 又是怎么用线程上下文类加载器打破的？

---

## 八、JVM 参数 & 调优

> **Q26** 这些 JVM 参数分别控制什么？`-Xms`、`-Xmx`、`-Xmn`、`-XX:SurvivorRatio`、`-XX:MetaspaceSize`、`-XX:MaxMetaspaceSize`、`-XX:MaxDirectMemorySize`

> **Q27** `-XX:+UseG1GC`、`-XX:MaxGCPauseMillis`、`-XX:G1HeapRegionSize`、`-XX:InitiatingHeapOccupancyPercent` 分别怎么用的？

> **Q28** 一个线上服务：堆 4G、QPS 3000、RT P99 100ms，GC 日志显示 Young GC 频繁且耗时长，你会怎么调优？

---

## 九、线上排查工具 & 流程

> **Q29** `jps`、`jstat`、`jmap`、`jstack`、`jinfo` 各自的用途？`jstat -gcutil` 输出哪些关键指标？

> **Q30** 线上突然 CPU 飙到 100%，你的排查流程是什么？（`top -Hp` → `printf '%x'` → `jstack` → 定位线程和代码行）

> **Q31** 线上 OOM（`java.lang.OutOfMemoryError: Java heap space`），你手上只有一台挂掉的机器，怎么排查？（`-XX:+HeapDumpOnOutOfMemoryError` 参数、MAT/JProfiler 分析 Dump）

---

## 十、JIT 编译优化

> **Q32** JIT 即时编译和解释执行的区别？C1（Client Compiler）和 C2（Server Compiler）的分工？分层编译（Tiered Compilation，JDK8 默认开启）是怎么逐层升级的？

> **Q33** 逃逸分析（Escape Analysis）是什么？标量替换（Scalar Replacement）、栈上分配（Stack Allocation）、同步消除（Lock Elision）分别是基于逃逸分析的什么优化？

---

## 十一、实战场景

> **Q34** 你现在负责一个 8C16G 的服务，JDK11、G1、堆 10G，Young GC 平均 80ms 每 3 秒一次，Mixed GC 平均 200ms 每 15 分钟一次，Full GC 从不触发。老板要求 GC 暂停时间 P99.9 降到 50ms 以下，你有哪些手段？
