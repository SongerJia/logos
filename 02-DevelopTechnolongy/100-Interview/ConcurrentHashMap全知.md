
### 基础层

**Q1. ConcurrentHashMap 的底层数据结构是什么？和 HashMap 一样吗？**

考察点：JDK 1.8 同样是 数组+链表+红黑树，但多了几个关键概念——Node（普通节点）、TreeNode（树节点）、TreeBin（包装红黑树根节点并持有一把读写锁）、ForwardingNode（扩容标记节点）。知不知道这些节点类型的区别。

---

**Q2. JDK 1.7 和 JDK 1.8 的 ConcurrentHashMap 实现有什么区别？**

考察点：这是必问题。1.7 是分段锁（Segment 继承 ReentrantLock，默认 16 个段，锁粒度是 Segment 级别）；1.8 放弃了分段锁，改为 CAS + synchronized 对单个桶加锁，锁粒度细化到桶级别。为什么要改？因为1.7 的分段锁粒度不够细，一个段下面可能管多个桶，竞争时仍然会阻塞无关操作。

---

### 并发安全机制层

**Q3. ConcurrentHashMap 的 put 流程是怎样的？（源码级）**

考察点：能完整走一遍——① key/value 不能为 null（否则抛 NPE）；② 计算 hash → 死循环 CAS；③ 桶为空：CAS 尝试写入，成功就结束；④ 桶正在扩容（hash == MOVED，即 ForwardingNode）：当前线程帮忙扩容（helpTransfer）；⑤ 对桶首节点加 synchronized → 判断是链表还是红黑树 → 遍历查找/插入 → 判断是否树化 → 最后 addCount 更新计数 + 可能触发扩容。这题答不好直接 pass。

---

**Q4. ConcurrentHashMap 的 get 操作为什么不加锁？**

考察点：Node 的 val 和 next 都用 volatile 修饰，保证多线程可见性；同时 get 不涉及结构修改，读的是快照效果。顺便考你知不知道 Unsafe 类的 getObjectVolatile 方法。

---

**Q5. ConcurrentHashMap 的 size() 是怎么实现的？**

考察点：不是直接遍历计算。1.8 用 baseCount + CounterCell 数组（类似 LongAdder 的思想），分片统计减少 CAS 竞争。addCount 时先 CAS 更新 baseCount，失败就落到 CounterCell。size() 就是 baseCount + 所有 CounterCell 的和。能讲出这个设计思路的，说明真正看过源码。

---

### 扩容机制层

**Q6. ConcurrentHashMap 的扩容和 HashMap 有什么不同？**

考察点：最大的区别是**多线程协同扩容**。ConcurrentHashMap 会把待迁移的桶分段（stride），每个线程负责一段，用 transferIndex 原子变量分配任务。扩容过程中 ForwardingNode 标记已迁移的桶，遇到读请求直接在新数组查。HashMap 就是单线程慢慢搬。

---

**Q7. ForwardingNode 的作用是什么？**

考察点：扩容期间，旧数组中已迁移完成的桶位置会放一个 ForwardingNode，hash 值为 MOVED(-1)。其他线程执行 put/get 时发现这个节点：put 线程会加入帮助扩容（helpTransfer），get 线程会去新数组（nextTable）里查找。这是协同扩容的枢纽。

---

**Q8. helpTransfer 是怎么工作的？**

考察点：当前线程发现桶上有 ForwardingNode → 检查是否扩容完毕 → 如果还在扩容中，参与进来，领取一段 strided 的桶进行迁移 → 迁移完继续领下一段 → 直到 transferIndex <= 0。最后一个线程负责收尾（检查所有桶、设置新数组为新 table、sizeCtl 更新）。

---

**Q9. sizeCtl 变量的含义是什么？（面试最爱问）**

考察点：一个变量，多种含义——① 初始化时：-1 表示正在初始化；② 正常运行时：扩容阈值（容量 × 负载因子）；③ 扩容中：高 16 位记录扩容标识版本号，低 16 位记录参与扩容的线程数 + 1。把正数、-N、小负数三种情况说清楚，顺手就能带走 JUC 其他组件里类似多义变量的设计套路。

---

### 高性能设计层

**Q10. ConcurrentHashMap 初始化时做了什么优化？**

考察点：延迟初始化，构造方法里不分配数组，在第一次 put 时才用 sizeCtl CAS 竞争初始化。避免构造完不用造成的浪费。问"如何保证只有一个线程初始化"——CAS 把 sizeCtl 从 0 改成 -1，成功就执行 initTable()，没抢到就 Thread.yield()。

---

**Q11. ConcurrentHashMap 的红黑树和 HashMap 的红黑树有什么不同？**

考察点：ConcurrentHashMap 引入了 TreeBin 代理节点。它是红黑树的包装器，root 是 TreeNode 但 slot 里存的是 TreeBin。读可以无锁，写对 TreeBin 加 synchronized。而 HashMap 直接 TreeNode 放在 slot 里。这题能看出来你对并发场景下红黑树读写分离有没有概念。

---

**Q12. addCount 和 transfer（扩容触发）的配合机制是怎么样的？**

考察点：addCount 不只是计数，它还承担"检查是否需要扩容"的职责。插入后调用 addCount，检查链表长度是否超过阈值（实际上是 sizeCtl 的扩容阈值），如果超过就扩容。并发下可能发现正在扩容就进去帮忙，或者 CAS 竞争 sizeCtl 做第一个扩容发起者。这是 put 收尾最关键的逻辑。

---

**Q13. ConcurrentHashMap 是强一致性还是弱一致性？**

考察点：弱一致性。get 不加锁，读到的是瞬时快照，不保证读到最新写入。put/迭代器也是弱一致的，迭代过程中发生的增删不一定反映到迭代结果。但它的弱一致性是故意的，用一致性换性能。

---

### 扩展设计层

**Q14. ConcurrentHashMap 为什么不支持 key/value 为 null？**

考察点：和 HashMap 的对比题。因为并发场景下 `get(null)` 返回 null 无法区分是 key 不存在、value 为 null、还是还没初始化完。这个二义性在单线程场景下可以忍受（HashMap 允许 null key 也就一个），但在多线程下是灾难。

---

**Q15. ConcurrentHashMap 的 computeIfAbsent 和 putIfAbsent 有什么区别？**

考察点：putIfAbsent 传的是现成的值，无论用不用都会先创建；computeIfAbsent 传的是 Function，只有 key 不存在时才执行，惰性计算，在高开销 value 场景下更优。源码里 computeIfAbsent 对 Function 的执行也加了锁，保证原子性。面试官追问：为什么 computeIfAbsent 内部对同一个 key 可能执行两次 Function？——因为第一次 CAS 失败了会重试。

---

**Q16. ConcurrentHashMap 扩容期间，put 和 get 怎么处理？**

考察点：put 遇到 ForwardingNode → 加入 helpTransfer；扩容期间新的 put 直接进新数组。get 遇到 ForwardingNode → 去 nextTable 查。这部分逻辑写在 putVal 和 get 各自的分支里，读源码时很容易漏掉。

---

### 实战对比层

**Q17. ConcurrentHashMap vs Hashtable vs Collections.synchronizedMap 的区别？**

考察点：Hashtable 全表锁（synchronized 方法级别），并发度极低；Collections.synchronizedMap 包装了一层 synchronized 块，本质也是全表锁；ConcurrentHashMap 桶级别锁 + CAS，高并发下性能碾压前两者。这题答不出来说明你对并发容器的选型没有基本判断。

---

**Q18. ConcurrentHashMap vs HashMap（线程安全改造）？什么时候该用哪个？**

考察点：数据量小、并发低 → HashMap + 外部加锁也行；高并发大量读写 → ConcurrentHashMap。如果问"HashMap 加读写锁改造行不行"——行，但性能不如 CHM，因为 CHM 的桶级锁粒度比读写锁更细。

---

**Q19. ConcurrentHashMap 在 JDK 1.8 中为什么用 synchronized 而不是 ReentrantLock？**

考察点：这是个经典问题。两个原因：① synchronized 经过 JDK 1.6+ 的锁升级优化（偏向锁→轻量级锁→重量级锁），在低竞争场景下性能已经和 ReentrantLock 持平甚至更好；② synchronized 是 JVM 原生支持，没有 ReentrantLock 的内存开销（AQS 节点），且锁升级/降级 JVM 替你做了，代码更简洁。

---

**Q20. 你项目里用 ConcurrentHashMap 遇到过什么问题？**

考察点：开放题。常见坑：① 误以为它是强一致性，get 读不到刚 put 的数据；② computeIfAbsent 里 Function 执行了两遍导致副作用；③ 迭代时修改了数据（弱一致性迭代器可能反映也可能不反映）；④ 忘了它不支持 null。讲得出实际踩过的坑说明真的用过。