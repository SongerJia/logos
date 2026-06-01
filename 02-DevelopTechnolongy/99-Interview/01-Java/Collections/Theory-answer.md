---
title: Java 集合面试理论-答案版
tags:
  - Java
  - Interview-answer
---
#flashcards/Java/collection/theory
## 一、HashMap（最常考，跟源码死磕）

### **Q1** HashMap 底层数据结构是什么？JDK7 和 JDK8 有什么变化？为什么要引入红黑树？
?
JDK7 的 HashMap 底层是数组加链表，每个数组位置称为一个桶，发生哈希冲突时新的节点追加到链表后面。JDK8 做了一个重要改进，增加了红黑树，变成数组加链表加红黑树的结构。引入红黑树的原因有两个层面：性能层面，如果大量 key 的哈希值碰撞到同一个桶，链表会变得很长，查询的时间复杂度从 O(1) 退化到 O(n)；安全层面，攻击者可以刻意构造一批哈希碰撞的 key，让服务端 HashMap 的链表极长，CPU 被查询操作打满，这就是哈希碰撞攻击。红黑树将最坏情况的查询复杂度控制在 O(log n)，同时解决了性能退化问题和安全性隐患。

### **Q2** HashMap 的默认初始容量是多少？负载因子是多少？为什么负载因子是 0.75 而不是 0.5 或 1.0？
?
默认初始容量是 16，负载因子是 0.75。选择 0.75 是在空间利用率和查询效率之间取的平衡点。如果设为 0.5，数组刚使用一半就会扩容，空间利用率只有 50%，而且扩容本身也有不小的性能开销。如果设为 1.0，空间倒是充分利用了，但元素密度太高导致哈希碰撞的概率大幅增加，链表变长，查询效率下降。HashMap 源码注释中有基于泊松分布的推算：当负载因子为 0.75 时，链表长度达到 8 的概率已经低于千万分之六，所以 0.75 是一个经过数学验证的经验最优值。

### **Q3** HashMap 扩容机制讲一下。什么条件下触发扩容？扩容的时候数据是怎么迁移的？（JDK7 和 JDK8 有区别）
?
扩容的触发条件是当前元素数量超过了容量乘以负载因子得到的阈值 threshold。每次扩容容量翻倍，所有已存在的节点需要重新计算下标并迁移到新数组。JDK7 和 JDK8 的迁移方式有本质区别。JDK7 使用头插法，也就是逐个取出旧链表的节点，插入到新数组对应位置链表的头部。这种方式在多线程场景下会导致链表反转，可能形成环形链表，后续 get 操作会陷入死循环。JDK8 改为尾插法，并且做了一个优化：扩容后每个节点的新下标只有两种可能，要么保持在原位置，要么移至原位置加上旧数组长度的位置。基于这个规律，JDK8 将同一个桶的链表拆分为高位链和低位链，低位链整体保留在原下标，高位链整体移至原下标加旧容量的位置。这样既维持了节点顺序，也从根本上避免了 JDK7 的死循环问题。

### **Q4** HashMap 链表转红黑树的阈值为什么是 8？红黑树转回链表的阈值为什么是 6？为什么不是同一个值？
?
树化阈值设为 8 的依据是 HashMap 源码中的泊松分布计算：在负载因子 0.75 的前提下，链表长度超过 8 的概率不到千万分之六，属于极小概率事件。因此正常情况下几乎不会触发树化，一旦触发，通常说明 hashCode 实现有问题或正在遭受哈希碰撞攻击。退化回链表的阈值设为 6 而不是 8，是为了留出一个缓冲区间。如果树化和退化的阈值相同，当元素数量在阈值附近波动时，会频繁触发红黑树与链表的相互转换。树化和链表化的开销都不小，这个差值可以避免性能抖动。

### **Q5** HashMap 的 `put()` 方法的完整流程是什么？源码能说清楚吗？
?
put 方法的完整流程分为以下步骤。第一步，调用 hash 方法计算 key 的哈希值。第二步，判断底层数组 table 是否为空或长度为 0，如果是则调用 resize 初始化数组。第三步，通过 (n-1) & hash 计算该 key 对应的桶下标。第四步，如果该桶为空，直接新建 Node 放入。第五步，如果桶不为空，先判断桶内第一个节点的 key 是否与待插入 key 相等，相等则替换 value。第六步，如果第一个节点是 TreeNode 类型，说明该桶已经树化，走红黑树的插入逻辑。第七步，否则遍历链表，逐个比较 key，找到相等的就替换，遍历到末尾仍未找到则使用尾插法添加新节点。添加后判断链表长度是否达到 8，达到则调用 treeifyBin 进行树化。需要注意 treeifyBin 内部还会判断数组长度是否达到 64，未达到的话优先扩容而不是树化。最后一步，插入完成后判断 size 是否超过 threshold，超过则触发扩容。整个流程可以概括为：计算哈希，定位桶，判断桶状态，处理冲突，检查扩容。

### **Q6** HashMap 的 `hash()` 方法是怎么算 hash 值的？为什么要高 16 位异或低 16 位？
?
HashMap 的 hash 方法对 key 的 hashCode 做了扰动处理：将 hashCode 的高 16 位与低 16 位进行异或运算，即 h ^ (h >>> 16)。这样做的原因是，HashMap 计算桶下标使用的是 (n - 1) & hash，当数组长度 n 较小时，比如默认容量 16，n-1 的二进制只有低 4 位为 1，高位全部为 0，与运算的结果只取决于 hash 的低位，高位信息完全被忽略。如果两个 hashCode 高位不同但低位相同，就会碰撞到同一个桶。通过高 16 位异或低 16 位，高位特征被混合到低位中，使得最终参与下标计算的低位同时携带了高位的信息，哈希分布更加均匀，从而减少碰撞。

### **Q7** HashMap 为什么线程不安全？JDK7 和 JDK8 分别有什么问题？
?
HashMap 在 JDK7 和 JDK8 中都不是线程安全的，但表现形式不同。JDK7 最严重的问题是扩容时的环形链表导致死循环。JDK7 迁移数据使用头插法，多线程同时扩容时，可能一个线程将 A 指向 B，另一个线程将 B 指向 A，形成环形链表。后续 get 操作遍历到这个环时陷入死循环，CPU 占用持续拉满。JDK8 改用尾插法后，环形链表的问题不存在了，但出现了新的问题：put 操作不是原子操作。两个线程可能同时判断某个桶为空，各自创建 Node 写入，后写入的会覆盖先写入的数据，造成元素丢失。另外 size 字段的递增也不是原子操作，多线程环境下 size 的值可能小于实际元素数量。因此无论 JDK7 还是 JDK8，多线程场景必须使用 ConcurrentHashMap。

### **Q8** HashMap 的 key 可以用可变对象吗？为什么推荐用 String、Integer 做 key？
?
技术上可以用可变对象做 key，但非常不推荐。如果将一个对象作为 key 放入 HashMap 之后修改了它的属性导致 hashCode 变化，那么这个 key 在新的哈希值下会去另一个桶查找，永远找不到原来的 entry。这个 entry 占据着内存但无法被访问，实质上造成了内存泄漏。String 和 Integer 被推荐的理由有三点：它们是不可变类，hashCode 一经计算就不会改变；它们的 hashCode 实现经过精心设计，分布均匀；它们都实现了 Comparable 接口，在各种比较场景下使用方便。所以结论是：应该用不可变且 hashCode 分布良好的类作为 HashMap 的 key。

### **Q9** `HashMap` vs `Hashtable` vs `ConcurrentHashMap` 的区别（至少 5 点）？
?
第一，线程安全方面：HashMap 非线程安全；Hashtable 对所有方法加 synchronized，线程安全但并发性能很差；ConcurrentHashMap 在 JDK8 中使用 CAS 加 synchronized 锁桶头节点，锁粒度细，并发性能远优于 Hashtable。第二，null 值方面：HashMap 允许一个 null key 和多个 null value；Hashtable 和 ConcurrentHashMap 都不允许 key 或 value 为 null。第三，初始容量和扩容方面：HashMap 默认容量 16，扩容为 2 倍；Hashtable 默认容量 11，扩容为 2n+1。第四，哈希算法方面：HashMap 做了高 16 位异或的扰动处理；Hashtable 直接使用 hashCode 取模。第五，历史地位方面：Hashtable 是 JDK 1.0 遗留类，已不推荐使用；ConcurrentHashMap 是 JDK5 引入的现代并发容器，官方推荐替代 Hashtable。第六，迭代器方面：HashMap 的迭代器是 fail-fast 的，ConcurrentHashMap 的迭代器是弱一致性的，遍历时允许并发修改。

---

## 二、ConcurrentHashMap（并发场景核心）

### **Q10** ConcurrentHashMap 在 JDK7 和 JDK8 的线程安全实现有什么区别？为什么 JDK8 放弃了分段锁？
?
JDK7 的 ConcurrentHashMap 采用分段锁机制，内部维护一个 Segment 数组，每个 Segment 继承 ReentrantLock，锁住的是 Segment 下面的一段 HashEntry 数组。默认 16 个段，意味着理论上最多支持 16 个线程同时并发写入。JDK8 完全舍弃了分段锁，改为对每个桶的头节点加 synchronized 锁，配合 CAS 操作实现无锁化的读取和桶初始化。放弃分段锁的原因有几个：JDK8 引入了红黑树，如果沿用 Segment 结构，红黑树的跨 Segment 操作实现非常复杂；分段锁的并发度在初始化时就固定了，无法动态扩展，而 JDK8 的粒度细化到桶级别，理论并发度等于桶的数量，扩展性更好；另外 JDK7 需要两次哈希——先定位 Segment 再定位桶，JDK8 一次哈希直接定位桶，计算路径更短。

### **Q11** ConcurrentHashMap 的 `sizeCtl` 字段在不同阶段分别代表什么意思？这个字段非常关键。
?
sizeCtl 是 ConcurrentHashMap 中的一个多义字段，它在不同阶段有不同含义。在表未初始化时，sizeCtl 等于构造时指定的初始容量，未指定则为 0。在表初始化完成后，sizeCtl 变为下一次扩容的阈值，等于当前容量乘以负载因子，相当于 HashMap 中的 threshold。当扩容正在进行时，sizeCtl 变为负数，其高位存储扩容版本戳，低 16 位记录当前参与扩容的线程数。扩容完成后，sizeCtl 恢复为下一次扩容的阈值。这个字段通过正负值和位运算同时承载了容量、阈值和扩容状态三种信息，是理解 ConcurrentHashMap 扩容机制的核心。

### **Q12** ConcurrentHashMap 在扩容期间，其他线程来 put 会发生什么？「扩容协助」是怎么实现的？
?
当其他线程在扩容期间执行 put 操作时，如果发现目标桶已经被替换为 ForwardingNode，说明该桶的数据已经或正在被迁移到新数组。此时这个线程不会等待，而是通过 helpTransfer 方法主动参与扩容。具体的协助流程是：计算当前的扩容戳，通过 CAS 将 sizeCtl 加 1，表示新增一个协助线程；然后从 transferIndex 领取一段待迁移的桶区间，逐个桶迁移数据；迁移完成后通过 CAS 将 sizeCtl 减 1；如果发现自己是最后一个完成的线程，负责收尾——将新数组赋值给 table 字段，并重新设置 sizeCtl 为扩容阈值。这个机制使得扩容过程中写入操作不会被阻塞，反而多线程协同工作加速了扩容。

### **Q13** ConcurrentHashMap 的 `get()` 方法为什么不需要加锁？
?
get 方法不需要加锁的根本原因在于 ConcurrentHashMap 的关键字段都使用了 volatile 修饰。table 数组是 volatile 的，保证扩容后新数组对所有线程立即可见。Node 内部的 val 和 next 字段也是 volatile 的，保证一个线程的写入对另一个线程的读取可见。如果 get 时发现当前桶是 ForwardingNode，说明该桶正在被迁移，ForwardingNode 内部持有新数组的引用，get 会自动到新数组中查找。迁移过程中是先创建新节点，再把旧桶标记为 ForwardingNode，volatile 的 happens-before 语义确保迁移完成后的状态对 get 线程可见。整个设计利用 volatile 的内存语义在保证可见性的前提下完全避免了加锁开销。

### **Q14** ConcurrentHashMap 的 `put()` 在遇到哈希冲突时，如果冲突节点正在被迁移（`ForwardingNode`），会怎么处理？
?
当 put 操作在目标桶上发现节点类型是 ForwardingNode 时，说明该桶正在或已经完成迁移。此时 put 线程不会在旧桶上执行写入，而是调用 helpTransfer 方法加入扩容协助。待扩容完成后，table 已经指向新数组，put 会在新数组上重新计算桶位置，正常执行插入。可能存在一个疑问：如果该 key 的旧数据尚未被迁移，会不会丢失？答案是不会。因为迁移是按从后往前的顺序逐个桶进行的，ForwardingNode 的标记意味着该桶已经在迁移范围内，迁移线程会负责完成该桶所有数据的搬迁。put 线程协助完成扩容后在新数组上操作，自然能看到已迁移的数据。

---

## 三、ArrayList & LinkedList

### **Q15** ArrayList 底层用什么实现的？扩容机制是什么？默认容量多少，每次扩容多少倍？`System.arraycopy()` 和 `Arrays.copyOf()` 有什么区别？
?
ArrayList 底层是一个 Object 数组 elementData。默认构造时是一个空数组，在第一次 add 时才真正分配容量，默认分配 10。扩容的触发条件是 add 时 size 等于数组长度，也就是数组已满。新容量为旧容量的 1.5 倍，计算方式是 oldCapacity + (oldCapacity >> 1)，右移一位即除以二。然后通过 Arrays.copyOf 将旧数组数据拷贝到新数组。System.arraycopy 和 Arrays.copyOf 的区别在于：System.arraycopy 是 native 方法，需要调用者自行创建目标数组并指定拷贝的起始位置和长度，更底层更灵活；Arrays.copyOf 是对 System.arraycopy 的封装，内部自动创建新数组并完成拷贝，调用者只需传入原数组和新长度，使用更简洁。

### **Q16** ArrayList 和 LinkedList 的区别？从底层结构、随机访问、增删效率、内存占用四个维度说清楚。
?
底层结构方面，ArrayList 基于动态数组，内存连续；LinkedList 基于双向链表，每个节点通过前后指针连接。随机访问方面，ArrayList 通过下标直接定位，时间复杂度 O(1)；LinkedList 需要从头遍历到目标位置，O(n)。增删效率方面需要分情况讨论：尾部操作 ArrayList 更快，因为它只需在数组末尾赋值；头部操作 LinkedList 更快，因为只需调整指针，而 ArrayList 需要搬移整个数组。不能一概而论地说 ArrayList 增删慢。内存占用方面，ArrayList 只有数组本身和少量预留空间；LinkedList 的每个节点需要额外存储前驱和后继两个引用，同等数据量下内存开销更大。总体上，ArrayList 适合需要频繁随机访问和尾部操作的场景，LinkedList 适合头部频繁插入和无法预知插入位置的场景。

### **Q17** ArrayList 和 LinkedList 遍历性能对比：for 循环、增强 for、Iterator、forEach 在 ArrayList 和 LinkedList 上分别表现如何？为什么？
?
对于 ArrayList，四种遍历方式性能差异不大。普通 for 循环通过下标直接访问，没有额外开销，略微最快。增强 for 和 Iterator 底层都是 Iterator 实现，多了一层方法调用但差异很小。对于 LinkedList，区别则非常显著。普通 for 循环每次 get(i) 都会从头开始遍历链表，整体时间复杂度为 O(n²)，数据量稍大性能就会严重下降。增强 for、Iterator 和 forEach 内部维护一个当前节点指针，每次 next 只移动一步，总复杂度为 O(n)。因此遍历 LinkedList 时必须使用迭代器或增强 for，不能使用普通 for 循环加 get(i)。

### **Q18** 为什么说「ArrayList 增删慢」其实是不准确的？什么情况下 ArrayList 增删比 LinkedList 还快？
?
"ArrayList 增删慢"这个说法不够准确，因为它只在非尾部位置成立。在非尾部位置，ArrayList 需要将后续元素整体搬移，时间复杂度 O(n)。但在尾部追加时，ArrayList 只需要在数组末尾赋值，非常高效。LinkedList 无论从哪个位置插入，都先要遍历到目标位置，这个查找就是 O(n)，并且还需要创建 Node 对象。实际上有基准测试表明，在数据量不大的情况下，ArrayList 即使在中间位置增删也可能比 LinkedList 快。原因是数组内存连续，CPU 缓存命中率高，System.arraycopy 又是 native 级别的内存批量操作，效率远高于 LinkedList 的指针跳转。正确的表述应该是：ArrayList 在尾部操作最快，非尾部需要搬移时才慢；LinkedList 任何位置都需要先遍历定位，且指针操作在缓存友好性上不如数组搬移。

### **Q19** ArrayList 和 Vector 的区别？
?
最主要的区别是线程安全。Vector 的所有方法都用 synchronized 修饰，线程安全但并发性能差；ArrayList 不做任何同步。扩容策略也不同：ArrayList 每次扩容 1.5 倍，Vector 默认扩容 2 倍，且 Vector 可以在构造时指定扩容增量。版本历史上，Vector 是 JDK 1.0 的类，ArrayList 是 JDK 1.2 加入集合框架的。现在 Vector 已基本被淘汰，如果需要线程安全的列表，可以优先考虑 CopyOnWriteArrayList，或者用 Collections.synchronizedList 包装。

---

## 四、其他集合 & 陷阱题

### **Q20** `ArrayBlockingQueue` 和 `LinkedBlockingQueue` 区别？各自的锁机制有什么不同？
?
ArrayBlockingQueue 底层是固定大小的数组，创建时必须指定容量且不可更改。LinkedBlockingQueue 底层是链表，可以指定容量上限，不指定则为无界队列。锁机制是两者最关键的区别。ArrayBlockingQueue 的 put 和 take 共用同一把 ReentrantLock，生产和消费操作互斥，同一时刻只能有一个线程执行操作。LinkedBlockingQueue 使用两把锁：putLock 控制生产者，takeLock 控制消费者。生产者之间竞争 putLock，消费者之间竞争 takeLock，生产和消费之间可以并行。因此在生产者和消费者都很频繁的场景下，LinkedBlockingQueue 的吞吐量通常更高。另外，LinkedBlockingQueue 每次插入都需要创建 Node 对象，存在 GC 压力；ArrayBlockingQueue 的数组提前分配，无此开销。

### **Q21** `PriorityQueue` 底层是什么？默认是最小堆还是最大堆？入队和出队的时间复杂度？
?
PriorityQueue 底层是二叉堆，使用数组存储，逻辑上是一棵完全二叉树，父子节点通过下标运算维护关系。默认是最小堆，队列头部始终是最小元素。如果需要最大堆，可以通过构造时传入自定义 Comparator 反转比较规则。入队操作（add / offer）将元素放在数组末尾后执行上浮（siftUp），时间复杂度 O(log n)。出队操作（poll）取出堆顶元素，将数组末尾元素移到堆顶后执行下沉（siftDown），时间复杂度也是 O(log n)。peek 只读取不删除，直接返回堆顶元素，O(1)。

### **Q22** `CopyOnWriteArrayList` 读写分离怎么实现的？适合什么场景？为什么不适合写多读少？
?
CopyOnWriteArrayList 的读写分离实现比较直接：读操作完全不加锁，直接读取当前数组；写操作（如 add）先加 ReentrantLock，然后用 Arrays.copyOf 拷贝整个数组，在副本上修改，修改完成后将底层数组引用指向新数组。这使得写操作不会阻塞读操作。适合的场景是读多写少，例如配置信息、白名单、事件监听器列表——写入频率极低，读取频率极高。不适合写多读少的场景，因为每次写入都要拷贝整个数组，内存开销大，拷贝本身也是 O(n)。另外，它的读操作可能读到旧数据，属于最终一致性模型，对实时性要求高的场景也不适用。

### **Q23** `Arrays.asList()` 返回的 List 和普通的 ArrayList 有什么不同？有什么坑？
?
Arrays.asList 返回的是 Arrays 内部类 ArrayList，不是 java.util.ArrayList，它的底层就是传入的那个数组。主要的坑有三个。第一，返回的 List 不支持 add 和 remove 操作，因为底层是固定长度数组，调用这些方法会抛出 UnsupportedOperationException。第二，对于基本类型数组，如 int[]，它会把整个数组当作一个元素，而不是拆开数组内的元素，这与直观预期不同。第三，返回的 List 是原数组的视图，对 List 做 set 操作，原数组也会被修改，这种联动关系可能导致难以排查的问题。Arrays.asList 更适合用来快速构造一个临时的只读列表。

### **Q24** `List.subList()` 有什么坑？
?
subList 返回的是原 List 的视图，不是拷贝。对 subList 的任何修改都会反映到原 List。反过来，如果对原 List 做了结构性修改（如在 subList 范围之外增减元素），再访问 subList 就会抛出 ConcurrentModificationException。另一个容易忽略的问题是，subList 内部持有原 List 的强引用。如果用一个很大的 List 取了很小的 subList，然后把大 List 的引用置空期望 GC 回收，实际上 subList 仍然持有原 List 的引用，导致内存无法回收。

### **Q25** 什么是 fail-fast 机制？哪些集合支持？底层怎么实现的？fail-safe 又是什么？
?
fail-fast 是一种错误检测机制，指迭代器在遍历过程中一旦检测到集合被结构性修改，立即抛出 ConcurrentModificationException，快速失败而非继续使用可能不一致的数据。ArrayList、HashMap 等非线程安全集合的迭代器都是 fail-fast 的。底层实现依赖于一个 modCount 字段，集合每次结构性修改时 modCount 自增。迭代器在创建时记录当时的 modCount 快照作为 expectedModCount，每次调用 next 或 remove 时比对两者是否一致，不一致则抛异常。fail-safe 则相反，迭代时允许并发修改而不抛异常。ConcurrentHashMap 和 CopyOnWriteArrayList 的迭代器是 fail-safe 的。ConcurrentHashMap 的迭代器是弱一致性的，可能看到也可能看不到并发修改的数据；CopyOnWriteArrayList 的迭代器遍历的是写操作前的数组快照，永远看不到新增元素。

### **Q26** `LinkedHashMap` 如何实现 LRU 缓存？`accessOrder` 参数起什么作用？
?
LinkedHashMap 在 HashMap 基础上维护了一个双向链表，默认按插入顺序维护元素，即 accessOrder 为 false。当 accessOrder 设为 true 时，改为按访问顺序维护：每次 get 一个元素，该元素会被移到链表末尾。这样链表头部就是最久未被访问的元素。实现 LRU 缓存需要三个条件：构造函数中 accessOrder 设为 true；继承 LinkedHashMap 并重写 removeEldestEntry 方法；在该方法中判断当前 size 是否超过缓存容量上限，超过则返回 true，LinkedHashMap 自动删除链表头部的最老元素。这三个条件组合后，缓存即可自动执行 LRU 淘汰。

---

## 五、综合性问题

### **Q27** 现在有一个超大的 ArrayList，中间频繁插入删除，性能很差。你可以从哪些角度优化？
?
第一个角度，如果插入删除集中在某个局部区域，可以将大 List 拆成多个小段，外加一个总索引，操作时只涉及其中一段，其余段不受影响。第二个角度，考虑更换数据结构：如果插入删除位置随机，LinkedList 也不一定更快，因为需要先 O(n) 遍历定位；可考虑跳表（ConcurrentSkipListMap）或树形结构。第三个角度，从业务层面考虑标记删除加延迟清理：先标记删除，然后在低峰时段批量整理。第四个角度，如果业务允许，将增删操作集中到尾部，ArrayList 尾部操作效率最高。第五个角度，在 Java 层面，使用 ensureCapacity 提前设置足够容量，减少扩容次数，扩容带来的数组搬移也是较大的开销。

### **Q28** 如果让你设计一个本地缓存，要求支持 LRU 淘汰策略，最大 10000 条，你会怎么实现？用什么数据结构？
?
首选方案是继承 LinkedHashMap。构造函数中 accessOrder 设为 true，重写 removeEldestEntry 方法，当 size 大于 10000 时返回 true。这是最简单且经过验证的实现方式。如果面试官要求不能使用 LinkedHashMap，可以手动实现：底层用 HashMap 提供 O(1) 查找，再维护一个双向链表表示访问顺序。get 操作时从 HashMap 获取节点，然后将节点从链表当前位置移到尾部。put 操作时如果 key 已存在则更新并移节点到尾部；如果不存在则创建节点同时加入 HashMap 和链表尾部，若超过容量上限则删除链表头部节点并从 HashMap 中移除。关键细节是维护好头尾指针，删除节点时注意处理前后指针，避免空指针异常。

### **Q29** 两个线程交替向同一个 ArrayList 添加元素，最终数量可能少于预期，从源码角度解释为什么。
?
从源码来看，ArrayList 的 add 方法不是原子操作。它分为两步：ensureCapacityInternal 检查容量并执行 size++，然后将元素赋值到 elementData[size]。问题出在 size++ 这一步。size++ 不是原子操作，包含读值、加一、写回三个步骤。两个线程可能同时读到相同的 size 值，例如都读到 5，各自加一后都写回 6，最终两个元素被写入 elementData[5] 同一位置，先写入的会被后写入的覆盖。同时 size 只增加了一次而不是两次，最终元素数量少于预期。另一个因素是 elementData 只是普通 Object 数组，没有 volatile 修饰，一个线程写入的值对另一个线程不一定可见。因此即使不发生覆盖，也可能出现读到 null 的情况。根本原因是多步操作非原子性和内存可见性问题共同导致。

### **Q30** 为什么 HashSet 是基于 HashMap 实现的？那它 value 存的是什么？
?
HashSet 内部聚合了一个 HashMap 实例，所有元素作为 HashMap 的 key 存储，value 统一使用一个名为 PRESENT 的静态 final Object 常量。这样设计的原因是，HashMap 天然提供了 key 不重复、O(1) 查找、O(1) 插入这些能力，正是 HashSet 所需要的语义。通过组合 HashMap 来复用这些能力，无需重新实现哈希表逻辑。add 方法内部调用 map.put(e, PRESENT)，返回 null 表示新增成功，返回非 null 表示 key 已存在。remove 委托给 map.remove，contains 委托给 map.containsKey。这是典型的组合复用模式。

---

## 六、TreeMap / TreeSet

### **Q31** TreeMap 底层数据结构是什么？红黑树的五个性质说清楚。为什么不用 AVL 树？
?
TreeMap 底层是红黑树，一种自平衡的二叉查找树。红黑树的五个性质：第一，每个节点非红即黑；第二，根节点必须是黑色；第三，所有叶子节点（NIL）都是黑色；第四，红色节点的两个子节点必须是黑色，即不能有两个红色节点直接相连；第五，从任一节点到其每个叶子节点的路径上，黑色节点数量必须相同，称为黑高。与 AVL 树相比，AVL 树追求严格平衡，左右子树高度差不超过 1，查找性能稍优，但插入和删除时需要更多的旋转操作来维持这个严格平衡。红黑树允许一定程度的不平衡，牺牲少量查找性能，换取更少的旋转次数。在 TreeMap 这种插入删除同样频繁的场景下，红黑树是更实用的选择。

### **Q32** TreeMap 的 `put()` 是如何保持有序的？插入过程中红黑树的旋转和变色怎么触发？
?
TreeMap 的 put 从根节点开始，将当前节点的 key 与待插入 key 比较，小则走左子树，大则走右子树，直到找到空位置插入新节点。新节点默认设为红色。这是因为插入红色不会违反黑高规则，最坏情况下只需修复红色相连的问题。当新节点的父节点也是红色时，违反了第四条规则，需要修复。修复分三种情况：第一种，叔叔节点是红色，将父亲和叔叔都染黑，爷爷染红，然后把爷爷当作新插入节点递归向上修复。第二种，叔叔是黑色，且当前节点是父节点的右孩子，则以父亲为轴左旋，转化为第三种情况。第三种，叔叔是黑色，且当前节点是父节点的左孩子，将父亲染黑、爷爷染红，以爷爷为轴右旋。这三种情况涵盖了所有红黑树插入后的自平衡调整。

### **Q33** `TreeMap` 的 key 是否可以为 null？为什么？`HashMap` 呢？
?
TreeMap 的 key 不能为 null。因为 TreeMap 依赖 key 的比较来维护有序性，无论 key 实现 Comparable 还是构造时传入 Comparator，插入 null 后在 compareTo 或 compare 调用时都会抛出 NullPointerException。这是设计上的硬约束。HashMap 允许一个 key 为 null，因为它的 hash 方法对 null 做了特殊处理——key 为 null 时 hash 值直接返回 0。因此 HashMap 中 null key 固定存放在下标为 0 的桶中。

### **Q34** `Comparable` 和 `Comparator` 的区别？TreeMap 如果同时传了 Comparator 和 key 实现了 Comparable，用哪个？
?
Comparable 是内部比较器，在类自身内部实现 compareTo 方法，属于侵入式设计，排序逻辑写定后不可改变。Comparator 是外部比较器，独立于被比较的类，实现 compare 方法，属于非侵入式设计，可以为同一个类创建多个不同排序维度的 Comparator。TreeMap 如果同时传入了 Comparator 且 key 实现了 Comparable，优先使用 Comparator。源码中 put 方法先检查 comparator 是否为 null，不为 null 则调用 comparator.compare，只有 comparator 为 null 时才使用 key 自身的 compareTo。

### **Q35** `HashSet` 底层是什么？如何保证不重复？`add()` 方法的源码流程说清楚。
?
HashSet 底层是 HashMap，所有元素作为 HashMap 的 key 存储，value 统一为静态常量 PRESENT。add 方法内部调用 map.put(e, PRESENT)，返回 null 说明 HashMap 中此前没有该 key，插入成功；返回 PRESENT 说明 key 已存在，插入失败。HashSet 判断重复的逻辑就是 HashMap 判断 key 相等的逻辑：先比较 hashCode，hashCode 相等后再比较 equals。因此，使用自定义对象作为 HashSet 元素时，必须同时重写 hashCode 和 equals 方法，且两者要保持一致性——equals 相等的两个对象 hashCode 也必须相等。否则会出现元素能够存入但 contains 返回 false 的问题。

### **Q36** `TreeSet` 和 `HashSet` 的区别？各自适用场景？
?
底层结构不同：HashSet 基于 HashMap（哈希表），TreeSet 基于 TreeMap（红黑树）。有序性不同：HashSet 无序，遍历顺序不保证与插入顺序一致；TreeSet 有序，按自然顺序或自定义 Comparator 排序。时间复杂度不同：HashSet 增删查平均 O(1)，TreeSet 增删查 O(log n)。null 值处理不同：HashSet 允许一个 null 元素，TreeSet 不允许。适用场景方面，需要快速去重、对顺序无要求时用 HashSet；需要排序或范围查找（如 ceiling、floor、subSet 等操作）时用 TreeSet。

---

## 七、LinkedHashMap 深入

### **Q37** `LinkedHashMap` 是如何维护插入顺序的？底层数据结构是怎样的？（双向链表 + HashMap）
?
LinkedHashMap 继承 HashMap，在其 Node 基础上做了扩展。它定义了内部类 Entry，继承 HashMap.Node 并额外添加了 before 和 after 两个指针。所有 Entry 通过这些指针串成一个双向链表，head 指向链表头部，tail 指向尾部。每次 put 新元素时，LinkedHashMap 除了走 HashMap 的插入逻辑将节点放入哈希桶外，还会调用 linkNodeLast 将新节点挂到双向链表末尾。如果是覆盖已有 key，则调用 afterNodeAccess 按需调整链表顺序。每个节点同时存在于哈希表和双向链表中，因此 LinkedHashMap 兼具 HashMap 的 O(1) 查找能力和链表维护的插入顺序。

### **Q38** `LinkedHashMap` 实现 LRU 缓存：`accessOrder=true` 之后，每次 `get()` 操作底层做了什么？源码流程说清楚。
?
accessOrder 设为 true 后，LinkedHashMap 切换为按访问顺序维护链表。get 方法先调用父类 HashMap 的 getNode 通过哈希表获取节点。获取后，LinkedHashMap 重写的 afterNodeAccess 方法被调用，该方法判断 accessOrder 是否为 true，如果是则将该节点从双向链表当前位置移除，然后重新挂到链表末尾，操作代价为 O(1)。这样链表头部始终是最久未被访问的节点，链表尾部是最近被访问的节点。结合 removeEldestEntry，当缓存满时自动淘汰链表头部元素，即实现了 LRU。

### **Q39** 用 LinkedHashMap 写一个固定大小的 LRU 缓存，`removeEldestEntry()` 怎么重写？
?
实现分为两步。第一步，构造 LinkedHashMap 时将 accessOrder 设为 true，例如使用构造方法 LinkedHashMap(capacity, 0.75f, true)。第二步，重写 removeEldestEntry 方法。该方法在每次 put 或 putAll 之后被调用，参数为 Map.Entry 类型的最老元素（即链表头部节点）。在方法体中判断 size() 是否超过预设的最大容量，超过则返回 true，LinkedHashMap 会自动删除该最老元素。例如 return size() > maxSize。这样，缓存在 get 和 put 时都会正确维护访问顺序并自动淘汰。

---

## 八、BlockingQueue 家族

### **Q40** `SynchronousQueue` 的特点是什么？它和 `ArrayBlockingQueue(size=1)` 的区别？工作窃取（`Executors.newCachedThreadPool`）为什么用它？
?
SynchronousQueue 是一个没有内部容量的阻塞队列。数据不经过队列暂存，必须是生产者 put 的同时消费者在 take，两者直接在队列上交汇。ArrayBlockingQueue 即使容量为 1，也有一格缓冲空间，生产者可以先放入，消费者稍后再取。这是本质区别：SynchronousQueue 是直接传递模式，ArrayBlockingQueue 是有缓冲的队列模式。Executors.newCachedThreadPool 使用 SynchronousQueue 的原因与它的设计理念一致：有新任务时如果没有空闲线程就立即创建新线程，因为队列没有容量，任务不会被缓存。如果用有容量的队列，任务就会被暂存，达不到 CachedThreadPool 快速响应、动态扩展的目的。

### **Q41** `LinkedTransferQueue` 和普通 `LinkedBlockingQueue` 的区别？`transfer()` 和 `put()` 有什么区别？
?
LinkedTransferQueue 在 LinkedBlockingQueue 的基础上增加了 transfer 模式：生产者可以检查是否有消费者正在等待，如果有则直接将数据传递给等待的消费者，不经过队列。transfer 和 put 的关键区别在于：transfer 是同步的，调用后必须等待有消费者取走数据才返回，生产者在此期间被阻塞；put 是异步的，数据放入队列后立即返回，不关心是否有消费者。LinkedBlockingQueue 没有 transfer 方法，完全依赖队列缓冲。LinkedTransferQueue 利用自旋和松弛机制在高并发场景下避免了不必要的队列操作，吞吐量更高。

### **Q42** `DelayQueue` 底层是什么？`take()` 方法的等待机制是什么？`Delayed` 接口怎么实现？
?
DelayQueue 底层使用 PriorityQueue 优先队列，元素按到期时间排序，队头是最早到期的元素。每个元素必须实现 Delayed 接口，Delayed 继承 Comparable，因此需要实现两个方法：getDelay 返回剩余延迟时间，compareTo 定义排序规则。take 方法的等待机制采用了 leader-follower 模式：取出队头元素，如果队头为空或未到期，当前线程作为 leader 通过 available.awaitNanos 等待剩余时间，其他线程无限等待；队头到期后 leader 被唤醒并取出元素，同时唤醒所有等待线程竞争下一个元素。这种模式避免了所有线程都做定时唤醒的资源浪费，是一种高效的线程协作设计。

### **Q43** 用 BlockingQueue 实现生产者-消费者模式，手写伪代码。如果生产速度远超消费速度，会出什么问题？怎么解决？
?
实现方式是定义一个共享的 BlockingQueue，生产者线程循环调用 put 放入数据，消费者线程循环调用 take 取出数据。BlockingQueue 自动处理阻塞和唤醒：队列满时 put 阻塞，队列空时 take 阻塞。如果生产速度远超消费速度，使用无界 LinkedBlockingQueue 会导致队列无限增长，最终内存溢出；使用有界 ArrayBlockingQueue 则生产者被阻塞，不会内存崩溃但吞吐量受限于消费者。解决方案包括：增加消费者线程数实现并行消费；引入拒绝策略，在生产过快时丢弃或限流；更彻底的方案是引入消息中间件如 Kafka，将生产和消费完全解耦，消费者可水平扩展。

---

## 九、Collections 工具类

### **Q44** `Collections.synchronizedList()` 返回的线程安全 List 和 `CopyOnWriteArrayList` 的区别？各自适用场景？
?
实现机制不同：synchronizedList 使用装饰器模式，在原有 List 的每个方法外加 synchronized 块，用 mutex 对象锁住所有操作，同一时间只有一个线程能执行。CopyOnWriteArrayList 使用写时复制，读操作不加锁，写操作复制整个数组后替换引用。性能特征不同：synchronizedList 读写都互斥，包括读读互斥，高并发下形成瓶颈；CopyOnWriteArrayList 读完全无锁，写操作有数组拷贝开销。适用场景不同：synchronizedList 适合读写频率接近且对数据一致性要求高的场景；CopyOnWriteArrayList 适合读远多于写的场景。写操作较多时应使用 synchronizedList，因为 CopyOnWriteArrayList 频繁拷贝整数组的性能代价不可接受。

### **Q45** `Collections.unmodifiableList()` 返回的不可变 List 底层怎么实现的？真的完全不可变吗？有什么坑？
?
底层使用装饰器模式，返回的 UnmodifiableList 持有原 List 引用。读取方法（get、size 等）直接委托给原 List。修改方法（add、remove、set 等）全部重写为抛出 UnsupportedOperationException。但它并非真正不可变。第一，它持有的仍是原 List 的引用，如果原 List 在其他地方被修改，这个"不可变" List 的内容也会随之变化。第二，如果 List 中存储的是可变对象，虽然不能对 List 进行增删，但可以获取到元素后修改元素自身的属性。因此 unmodifiableList 只阻止了对 List 结构的修改，并未实现深层不可变。

### **Q46** `Collections.sort()` 底层用的是什么排序算法？对 ArrayList 和 LinkedList 分别怎么排的？
?
Collections.sort 底层调用的是 List 自身的 sort 方法。对于 ArrayList，使用的是 DualPivotQuickSort，即双轴快速排序，用两个轴点将数组分为三段，是经典快排的优化版本。对于 LinkedList，由于链表不支持随机访问，直接排序效率很低，因此先将链表转为数组，对数组排序，再将排序结果写回链表的节点值。这种策略多了一次数组拷贝的内存开销，但整体上比在链表上直接排序高效很多。

---

## 十、迭代器深入

### **Q47** `Iterator` 和 `ListIterator` 的区别？（至少 3 点）
?
第一，遍历方向：Iterator 只能单向从前向后遍历；ListIterator 支持双向遍历，有 hasPrevious 和 previous 方法。第二，修改能力：Iterator 只有 remove 方法；ListIterator 额外提供 add 和 set 方法，可以在遍历过程中添加或替换元素。第三，索引获取：Iterator 无法获取当前位置索引；ListIterator 有 nextIndex 和 previousIndex 方法。第四，适用范围：Iterator 适用于所有 Collection；ListIterator 仅适用于 List，Set 和 Queue 都没有。总结来说，Iterator 是只读单向光标，ListIterator 是可读可写的双向光标。

### **Q48** `ConcurrentHashMap` 的迭代器是 fail-fast 还是 fail-safe？为什么？遍历过程中别的线程修改了数据，迭代器能看到吗？
?
ConcurrentHashMap 的迭代器是 fail-safe 的，更准确地说是弱一致性。遍历过程中即使有其他线程修改了 ConcurrentHashMap，迭代器也不会抛出 ConcurrentModificationException。原因是它不依赖 modCount 做并发检测，而是直接遍历底层的数组和链表，读取的是创建迭代器时间点或遍历过程中某个时间点的实际数据。关于能否看到其他线程的修改，答案是可能看到也可能看不到。如果修改的桶在迭代器已遍历过的位置，则不可见；如果在尚未遍历的位置，则可能可见。它不保证读到最新数据，但保证不会因并发修改而崩溃。这与 HashMap 的 fail-fast 是不同的设计取舍。

### **Q49** 用 foreach 遍历 List 时删除元素会报什么错？怎么正确删除？
?
使用 foreach 遍历 List 时直接调用 list.remove 会抛出 ConcurrentModificationException。因为 foreach 底层是 Iterator，Iterator 内部维护 expectedModCount，每次 next 时都会比对 expectedModCount 和集合的 modCount 是否一致。list.remove 会使 modCount 自增但 expectedModCount 不变，下次 next 时发现不一致即抛异常。正确做法有两种：一是使用 Iterator 自身的 remove 方法，它删除元素的同时会同步更新 expectedModCount；二是使用 JDK8 的 Collection.removeIf 方法，传入 Predicate，内部也是通过 Iterator 安全删除的。

---

## 十一、刁钻追问（拉开分差）

### **Q50** HashMap 扩容时，JDK8 用了高位链和低位链分开迁移——如果旧数组长度是 16，一个 key 的 hash 是 `0b...01001`（二进制），扩容到 32 后它会在哪个下标？怎么判断的？
?
JDK8 扩容迁移的判断逻辑是：将 key 的 hash 值与旧数组长度做与运算。旧数组长度 16 的二进制是 10000，与 hash 的 01001 做与运算的结果为 0，因此这个节点分到低位链，下标保持不变。如果与运算结果为 1，则分到高位链，下标等于原位置加旧数组长度。所以判断方式是：看 hash 值中与旧数组长度最高位对应的那一位是 0 还是 1。旧容量 16 的二进制是 10000，对应第 5 位，本题 hash 的第 5 位是 0，因此留在原下标。这个方法的巧妙之处在于，一次按位与运算就完成了所有节点的重新分配，而不需要重新计算每个节点的 hash 并取模。

### **Q51** 为什么 HashMap 的容量必须是 2 的幂？如果构造时传了 `new HashMap(10)`，实际容量是多少？`tableSizeFor` 怎么算的？
?
容量必须是 2 的幂是因为 HashMap 使用 (n - 1) & hash 来计算桶下标，这本质上等价于 hash % n，但仅当 n 是 2 的幂时成立。n 为 2 的幂时，n - 1 的二进制全部为 1，与运算的结果在 0 到 n-1 之间均匀分布。如果 n 不是 2 的幂，n - 1 的某些二进制位为 0，这些位永远无法在结果中为 1，导致部分桶永远为空，碰撞概率增大。new HashMap(10) 实际容量是 16。构造方法会调用 tableSizeFor 方法，它通过一系列右移和按位或运算，将传入值变为大于等于它的最小 2 的幂。10 的二进制是 1010，经过运算变为 1111 即 15，再加 1 得到 16。tableSizeFor 的核心思路是将最高位 1 之后的所有位全部置为 1，再加 1 得到下一个 2 的幂。

### **Q52** 为什么 `ConcurrentHashMap` 不支持 key 或 value 为 null？`HashMap` 支持 null，它不支持的设计考量是什么？
?
ConcurrentHashMap 不允许 null 既是设计选择也有并发语义的必要性。在单线程环境下，HashMap 可以用 containsKey 区分"key 不存在"和"key 存在但 value 为 null"这两种情况。但在并发环境下，这个区分没有意义——containsKey 返回 true 的瞬间，另一个线程可能已经将 key 删除，导致紧接着 get 的结果仍是 null。这种二义性在并发场景下无法消除。与其让开发者写出有隐患的代码，不如在 API 层面直接拒绝 null。此外，Doug Lea 的设计理念认为，null 值通常意味着程序错误，应当在放入时尽早暴露，而不是藏在 Map 中等待将来被触发。

### **Q53** `WeakHashMap` 是什么？它和普通 HashMap 的区别？Entry 继承了 `WeakReference`，GC 时会发生什么？
?
WeakHashMap 的 Entry 继承自 WeakReference，对 key 使用弱引用持有。当 key 对象在外部没有任何强引用时，下一次 GC 会将其回收。WeakHashMap 内部维护一个 ReferenceQueue 来跟踪已被回收 key 的 Entry。在每次调用 get、put、size 等方法时，WeakHashMap 会检查 ReferenceQueue，将那些 key 已被回收的 Entry 从 Map 中清理掉，对应的 value 也随之被释放。这种清理是惰性的。与普通 HashMap 的区别在于引用强度：HashMap 使用强引用，key 只要在 Map 中就永远不会被 GC 回收，可能导致内存泄漏；WeakHashMap 使用弱引用，key 没有外部引用时会被自动回收，适合做缓存或存储与对象生命周期绑定的元数据。

### **Q54** JDK7 HashMap 多线程扩容死循环是怎么产生的？画图说明环形链表的形成过程。
?
JDK7 扩容死循环的根源是头插法迁移。假设旧数组某个桶中有 A 指向 B 两个节点。线程一和线程二同时触发扩容。线程一先开始迁移，用头插法将 A 移到新数组后 A 的 next 为 null；继续迁移 B 时，头插法让 B 的 next 指向 A。此时在线程一的视角中，新数组该桶已经形成 B 指向 A 的结构。线程一在此时挂起。线程二开始执行，它读取的旧数组链表依然是 A 指向 B，也用头插法：先将 A 移到新数组，A 的 next 为 null；再将 B 移到新数组，B 的 next 指向 A。线程二完成后，新数组该桶是 B 指向 A。当线程一恢复继续执行时，它持有的局部变量还指向旧的引用关系，在线程二的修改影响下，A 的 next 变成了 B，而 B 的 next 又指向 A，环形链表形成。后续 get 遍历到这个桶时，陷入无限循环。JDK8 改为尾插法配合高低位链拆分后，这个问题被从根本上解决。

### **Q55** `BitSet` 是什么？什么场景用它？跟 `boolean[]` 比有什么优势？
?
BitSet 是一个用位存储布尔值的集合，每个 bit 表示 true 或 false。底层使用 long 数组，每个 long 可表示 64 个布尔状态。与 boolean 数组相比，boolean 数组每个元素占 1 字节即 8 bit，BitSet 每个元素仅占 1 bit，内存占用约为 boolean 数组的八分之一。此外 BitSet 支持批量位运算，如 and、or、xor 操作一次处理一个 long（64 位），远快于逐个遍历 boolean 数组。典型应用场景包括：大量用户 ID 的去重统计（配合布隆过滤器）；权限系统中用一个 BitSet 表示所有权限位；数据排序去重——将数据值作为位索引置位后按序输出。在这些场景下 BitSet 在内存和速度上均优于 boolean 数组。
