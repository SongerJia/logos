---
title: Java 集合面试理论
tags:
  - Java
  - Interview
---

## 一、HashMap（最常考，跟源码死磕）

> **Q1** HashMap 底层数据结构是什么？JDK7 和 JDK8 有什么变化？为什么要引入红黑树？

> **Q2** HashMap 的默认初始容量是多少？负载因子是多少？为什么负载因子是 0.75 而不是 0.5 或 1.0？

> **Q3** HashMap 扩容机制讲一下。什么条件下触发扩容？扩容的时候数据是怎么迁移的？（JDK7 和 JDK8 有区别）

> **Q4** HashMap 链表转红黑树的阈值为什么是 8？红黑树转回链表的阈值为什么是 6？为什么不是同一个值？

> **Q5** HashMap 的 `put()` 方法的完整流程是什么？源码能说清楚吗？

> **Q6** HashMap 的 `hash()` 方法是怎么算 hash 值的？为什么要高 16 位异或低 16 位？

> **Q7** HashMap 为什么线程不安全？JDK7 和 JDK8 分别有什么问题？

> **Q8** HashMap 的 key 可以用可变对象吗？为什么推荐用 String、Integer 做 key？

> **Q9** `HashMap` vs `Hashtable` vs `ConcurrentHashMap` 的区别（至少 5 点）？

---

## 二、ConcurrentHashMap（并发场景核心）

> **Q10** ConcurrentHashMap 在 JDK7 和 JDK8 的线程安全实现有什么区别？为什么 JDK8 放弃了分段锁？

> **Q11** ConcurrentHashMap 的 `sizeCtl` 字段在不同阶段分别代表什么意思？这个字段非常关键。

> **Q12** ConcurrentHashMap 在扩容期间，其他线程来 put 会发生什么？「扩容协助」是怎么实现的？

> **Q13** ConcurrentHashMap 的 `get()` 方法为什么不需要加锁？

> **Q14** ConcurrentHashMap 的 `put()` 在遇到哈希冲突时，如果冲突节点正在被迁移（`ForwardingNode`），会怎么处理？

---

## 三、ArrayList & LinkedList

> **Q15** ArrayList 底层用什么实现的？扩容机制是什么？默认容量多少，每次扩容多少倍？`System.arraycopy()` 和 `Arrays.copyOf()` 有什么区别？

> **Q16** ArrayList 和 LinkedList 的区别？从底层结构、随机访问、增删效率、内存占用四个维度说清楚。

> **Q17** ArrayList 和 LinkedList 遍历性能对比：for 循环、增强 for、Iterator、forEach 在 ArrayList 和 LinkedList 上分别表现如何？为什么？

> **Q18** 为什么说「ArrayList 增删慢」其实是不准确的？什么情况下 ArrayList 增删比 LinkedList 还快？

> **Q19** ArrayList 和 Vector 的区别？

---

## 四、其他集合 & 陷阱题

> **Q20** `ArrayBlockingQueue` 和 `LinkedBlockingQueue` 区别？各自的锁机制有什么不同？

> **Q21** `PriorityQueue` 底层是什么？默认是最小堆还是最大堆？入队和出队的时间复杂度？

> **Q22** `CopyOnWriteArrayList` 读写分离怎么实现的？适合什么场景？为什么不适合写多读少？

> **Q23** `Arrays.asList()` 返回的 List 和普通的 ArrayList 有什么不同？有什么坑？

> **Q24** `List.subList()` 有什么坑？

> **Q25** 什么是 fail-fast 机制？哪些集合支持？底层怎么实现的？fail-safe 又是什么？

> **Q26** `LinkedHashMap` 如何实现 LRU 缓存？`accessOrder` 参数起什么作用？

---

## 五、综合性问题

> **Q27** 现在有一个超大的 ArrayList，中间频繁插入删除，性能很差。你可以从哪些角度优化？

> **Q28** 如果让你设计一个本地缓存，要求支持 LRU 淘汰策略，最大 10000 条，你会怎么实现？用什么数据结构？

> **Q29** 两个线程交替向同一个 ArrayList 添加元素，最终数量可能少于预期，从源码角度解释为什么。

> **Q30** 为什么 HashSet 是基于 HashMap 实现的？那它 value 存的是什么？

---

## 六、TreeMap / TreeSet

> **Q31** TreeMap 底层数据结构是什么？红黑树的五个性质说清楚。为什么不用 AVL 树？

> **Q32** TreeMap 的 `put()` 是如何保持有序的？插入过程中红黑树的旋转和变色怎么触发？

> **Q33** `TreeMap` 的 key 是否可以为 null？为什么？`HashMap` 呢？

> **Q34** `Comparable` 和 `Comparator` 的区别？TreeMap 如果同时传了 Comparator 和 key 实现了 Comparable，用哪个？

> **Q35** `HashSet` 底层是什么？如何保证不重复？`add()` 方法的源码流程说清楚。

> **Q36** `TreeSet` 和 `HashSet` 的区别？各自适用场景？

---

## 七、LinkedHashMap 深入

> **Q37** `LinkedHashMap` 是如何维护插入顺序的？底层数据结构是怎样的？（双向链表 + HashMap）

> **Q38** `LinkedHashMap` 实现 LRU 缓存：`accessOrder=true` 之后，每次 `get()` 操作底层做了什么？源码流程说清楚。

> **Q39** 用 LinkedHashMap 写一个固定大小的 LRU 缓存，`removeEldestEntry()` 怎么重写？

---

## 八、BlockingQueue 家族

> **Q40** `SynchronousQueue` 的特点是什么？它和 `ArrayBlockingQueue(size=1)` 的区别？工作窃取（`Executors.newCachedThreadPool`）为什么用它？

> **Q41** `LinkedTransferQueue` 和普通 `LinkedBlockingQueue` 的区别？`transfer()` 和 `put()` 有什么区别？

> **Q42** `DelayQueue` 底层是什么？`take()` 方法的等待机制是什么？`Delayed` 接口怎么实现？

> **Q43** 用 BlockingQueue 实现生产者-消费者模式，手写伪代码。如果生产速度远超消费速度，会出什么问题？怎么解决？

---

## 九、Collections 工具类

> **Q44** `Collections.synchronizedList()` 返回的线程安全 List 和 `CopyOnWriteArrayList` 的区别？各自适用场景？

> **Q45** `Collections.unmodifiableList()` 返回的不可变 List 底层怎么实现的？真的完全不可变吗？有什么坑？

> **Q46** `Collections.sort()` 底层用的是什么排序算法？对 ArrayList 和 LinkedList 分别怎么排的？

---

## 十、迭代器深入

> **Q47** `Iterator` 和 `ListIterator` 的区别？（至少 3 点）

> **Q48** `ConcurrentHashMap` 的迭代器是 fail-fast 还是 fail-safe？为什么？遍历过程中别的线程修改了数据，迭代器能看到吗？

> **Q49** 用 foreach 遍历 List 时删除元素会报什么错？怎么正确删除？

---

## 十一、刁钻追问（拉开分差）

> **Q50** HashMap 扩容时，JDK8 用了高位链和低位链分开迁移——如果旧数组长度是 16，一个 key 的 hash 是 `0b...01001`（二进制），扩容到 32 后它会在哪个下标？怎么判断的？

> **Q51** 为什么 HashMap 的容量必须是 2 的幂？如果构造时传了 `new HashMap(10)`，实际容量是多少？`tableSizeFor` 怎么算的？

> **Q52** 为什么 `ConcurrentHashMap` 不支持 key 或 value 为 null？`HashMap` 支持 null，它不支持的设计考量是什么？

> **Q53** `WeakHashMap` 是什么？它和普通 HashMap 的区别？Entry 继承了 `WeakReference`，GC 时会发生什么？

> **Q54** JDK7 HashMap 多线程扩容死循环是怎么产生的？画图说明环形链表的形成过程。

> **Q55** `BitSet` 是什么？什么场景用它？跟 `boolean[]` 比有什么优势？
