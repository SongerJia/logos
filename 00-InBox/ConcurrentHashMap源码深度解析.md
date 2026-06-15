# Java ConcurrentHashMap 源码深度解析

> 基于 JDK 8 版本，覆盖 JDK 7/8/9/17 关键差异标注

---

## 目录

1. [整体架构](#1-整体架构)
2. [核心字段](#2-核心字段)
3. [构造方法](#3-构造方法)
4. [并发控制核心机制](#4-并发控制核心机制)
5. [put 流程（核心）](#5-put-流程核心)
6. [initTable 初始化](#6-inittable-初始化)
7. [get 流程](#7-get-流程)
8. [remove 流程](#8-remove-流程)
9. [transfer 扩容机制](#9-transfer-扩容机制)
10. [helpTransfer 协助扩容](#10-helptransfer-协助扩容)
11. [树化与反树化](#11-树化与反树化)
12. [size 计数机制](#12-size-计数机制)
13. [forEach / search / reduce 并发批量操作](#13-foreach--search--reduce-并发批量操作)
14. [JDK 版本演进对比](#14-jdk-版本演进对比)
15. [ConcurrentHashMap vs HashMap vs Hashtable](#15-concurrenthashmap-vs-hashmap-vs-hashtable)
16. [常见面试题](#16-常见面试题)

---

## 1. 整体架构

JDK 8 的 ConcurrentHashMap 与 HashMap 结构类似，都是 **数组 + 链表 + 红黑树**，但在并发控制上做了彻底重设计：

```
┌──────────────────────────────────────────────────────────────────────┐
│  table[] (Node<K,V> 数组，volatile)                                  │
│                                                                      │
│  ┌────────────┐                                                      │
│  │     0      │ → null                                               │
│  ├────────────┤                                                      │
│  │     1      │ → Node → Node → Node        (链表，synchronized 锁头) │
│  ├────────────┤                                                      │
│  │     2      │ → ForwardingNode (fwd)      (扩容标记节点)            │
│  ├────────────┤                                                      │
│  │     3      │ → TreeBin → TreeNode→...   (红黑树，synchronized 锁  │
│  ├────────────┤                           TreeBin 节点)              │
│  │    ...     │                                                      │
│  ├────────────┤                                                      │
│  │    n-1     │ → Node                                               │
│  └────────────┘                                                      │
│                                                                      │
│  sizeCtl: 控制初始化和扩容的状态变量                                    │
│  CounterCell[]: 分散计数的原子单元格数组                                │
└──────────────────────────────────────────────────────────────────────┘
```

### JDK 7 vs JDK 8 架构对比

```
JDK 7:  Segment[] → HashEntry[] → 链表
        ┌─────────┐
        │Segment 0│ → HashEntry[] → 链表
        │Segment 1│ → HashEntry[] → 链表
        │  ...     │
        │Segment15│ → HashEntry[] → 链表
        └─────────┘
        分段锁，锁粒度为 Segment（默认16段）

JDK 8:  Node[] → 链表 / 红黑树
        ┌──────────────┐
        │   Node[]     │
        │  每个桶独立锁  │  synchronized 锁头节点
        │  CAS 无锁操作  │  初始化/计数等
        └──────────────┘
        锁粒度为单个桶，并发度 = 桶数量
```

**核心改进：**
- 锁粒度从 Segment（默认16段）细化到每个桶 → 并发度大幅提升
- 引入红黑树 → 长链表查询从 O(n) 优化到 O(log n)
- CAS + synchronized 替代 ReentrantLock → 内存占用更小
- 多线程协助扩容 → 扩容不再由单线程承担

---

## 2. 核心字段

```java
public class ConcurrentHashMap<K,V> extends AbstractMap<K,V>
    implements ConcurrentMap<K,V>, Serializable {

    // 最大容量 2^30
    private static final int MAXIMUM_CAPACITY = 1 << 30;

    // 默认初始容量 16
    private static final int DEFAULT_CAPACITY = 16;

    // 默认并发级别（JDK 7 遗留，JDK 8 仅影响初始容量计算）
    private static final int DEFAULT_CONCURRENCY_LEVEL = 16;

    // 负载因子 0.75（固定，不可修改）
    private static final float LOAD_FACTOR = 0.75f;

    // 链表转红黑树阈值
    static final int TREEIFY_THRESHOLD = 8;

    // 红黑树退回链表阈值
    static final int UNTREEIFY_THRESHOLD = 6;

    // 树化要求的最小数组长度
    static final int MIN_TREEIFY_CAPACITY = 64;

    // 扩容时每个线程迁移的最小桶数
    private static final int MIN_TRANSFER_STRIDE = 16;

    // 扩容时生成的新数组
    private transient volatile Node<K,V>[] nextTable;

    // 哈希桶数组
    transient volatile Node<K,V>[] table;

    // ★ 核心控制字段，多种含义：
    //   -1    : table 正在初始化
    //   -N    : 有 N-1 个线程正在扩容（高16位为扩容标识，低16位为线程数+1）
    //    0    : table 未初始化，使用默认容量
    //   >0    : 未初始化时为初始容量；已初始化时为扩容阈值
    private transient volatile int sizeCtl;

    // 扩容时分配迁移任务的索引（从大到小分配）
    private transient volatile int transferIndex;

    // 计数基础值
    private transient volatile long baseCount;

    // 分散计数单元格数组
    private transient volatile CounterCell[] counterCells;
}
```

### sizeCtl 状态机

```
                    ┌──────────────┐
                    │  sizeCtl = 0 │  未初始化，默认容量
                    └──────┬───────┘
                           │ 构造时指定容量
                    ┌──────▼───────┐
                    │ sizeCtl > 0  │  初始容量 / 扩容阈值
                    └──────┬───────┘
                           │ 首次 put
                    ┌──────▼───────┐
             ┌──No──│  CAS(0,-1)   │
             │      └──────┬───────┘
             │             │ 成功
             │      ┌──────▼───────┐
             │      │  正在初始化   │  sizeCtl = -1
             │      └──────┬───────┘
             │             │ 初始化完成
             │      ┌──────▼───────┐
             │      │ sizeCtl =    │
             │      │ 0.75*n       │  扩容阈值
             │      └──────┬───────┘
             │             │ 需要扩容
             │      ┌──────▼───────────────┐
             │      │ sizeCtl =            │
             │      │ (resizeStamp(n)<<16) │
             │      │ + 2                  │  首个扩容线程
             │      └──────┬───────────────┘
             │             │ 更多线程加入
             │      ┌──────▼───────┐
             │      │ sizeCtl +=1  │  协助扩容
             │      └──────┬───────┘
             │             │ 扩容完成
             │      ┌──────▼───────┐
             └──→  │ sizeCtl =    │
                   │ 0.75*2n      │  新的扩容阈值
                   └──────────────┘
```

---

## 3. 构造方法

### 3.1 无参构造

```java
public ConcurrentHashMap() {
    // 什么都不做，延迟到首次 put 时初始化
}
```

### 3.2 指定初始容量

```java
public ConcurrentHashMap(int initialCapacity) {
    if (initialCapacity < 0)
        throw new IllegalArgumentException();
    // tableSizeFor：如果 initialCapacity 超过当前容量一半，则取最近的 2 的幂
    // 否则取 initialCapacity + initialCapacity/2 + 1 对应的 2 的幂
    // 目的是确保 putAll 等批量操作不需要立即扩容
    int cap = ((initialCapacity >= (MAXIMUM_CAPACITY >>> 1)) ?
               MAXIMUM_CAPACITY :
               tableSizeFor(initialCapacity + (initialCapacity >>> 1) + 1));
    this.sizeCtl = cap;
}
```

### 3.3 tableSizeFor

```java
private static final int tableSizeFor(int c) {
    int n = c - 1;
    n |= n >>> 1;
    n |= n >>> 2;
    n |= n >>> 4;
    n |= n >>> 8;
    n |= n >>> 16;
    return (n < 0) ? 1 : (n >= MAXIMUM_CAPACITY) ? MAXIMUM_CAPACITY : n + 1;
}
```

与 HashMap 相同，将容量向上取整为最接近的 2 的幂。

---

## 4. 并发控制核心机制

### 4.1 三种原子操作

```java
// ① CAS 操作
static final <K,V> boolean casTabAt(Node<K,V>[] tab, int i,
                                     Node<K,V> c, Node<K,V> v) {
    return U.compareAndSwapObject(tab, ((long)i << ASHIFT) + ABASE, c, v);
}

// ② volatile 读
static final <K,V> Node<K,V> tabAt(Node<K,V>[] tab, int i) {
    return (Node<K,V>)U.getObjectVolatile(tab, ((long)i << ASHIFT) + ABASE);
}

// ③ volatile 写
static final <K,V> void setTabAt(Node<K,V>[] tab, int i, Node<K,V> v) {
    U.putObjectVolatile(tab, ((long)i << ASHIFT) + ABASE, v);
}
```

**为什么不能直接 `tab[i]`？**

虽然 `table` 是 volatile 的，但 volatile 只保证引用本身的可见性，不保证数组元素的可见性。需要通过 `Unsafe` 的 `getObjectVolatile` 来保证读到最新值。

### 4.2 synchronized 锁桶头节点

```java
// 锁住桶的头节点
synchronized (f) {
    // 在锁内操作链表/红黑树
}
```

**为什么选 synchronized 而不是 ReentrantLock？**

1. **内存占用**：每个 ReentrantLock 对象约 24 字节，synchronized 不需要额外对象
2. **JVM 优化**：现代 JVM 对 synchronized 有偏向锁、轻量级锁、锁升级等优化
3. **锁粒度**：只锁单个桶，不会影响其他桶的并发访问

### 4.3 何时用 CAS，何时用 synchronized？

| 操作 | 方式 | 原因 |
|------|------|------|
| 桶为空时插入新节点 | CAS | 无竞争，轻量 |
| 初始化 table | CAS sizeCtl | 只允许一个线程初始化 |
| 计数更新 | CAS baseCount → CAS CounterCell | 分散竞争 |
| 链表/红黑树操作 | synchronized | 涉及多步操作，需要互斥 |
| 扩容状态标记 | CAS sizeCtl | 协调多线程扩容 |

---

## 5. put 流程（核心）

### 5.1 入口

```java
public V put(K key, V value) {
    return putVal(key, value, false);
}
```

### 5.2 putVal 完整源码 + 逐行注释

```java
final V putVal(K key, V value, boolean onlyIfAbsent) {
    // ① key/value 不能为 null
    if (key == null || value == null) throw new NullPointerException();

    // ② 计算 hash（与 HashMap 类似但略有不同）
    int hash = spread(key.hashCode());

    // ③ 记录链表长度，用于判断是否需要树化
    int binCount = 0;

    for (Node<K,V>[] tab = table;;) {
        Node<K,V> f; int n, i, fh;

        // ④ table 为空 → 初始化
        if (tab == null || (n = tab.length) == 0)
            tab = initTable();

        // ⑤ 桶为空 → CAS 尝试插入
        else if ((f = tabAt(tab, i = (n - 1) & hash)) == null) {
            if (casTabAt(tab, i, null, new Node<K,V>(hash, key, value, null)))
                break;  // CAS 成功，插入完成
            // CAS 失败（其他线程抢先插入了），继续自旋
        }

        // ⑥ 桶头节点的 hash 为 MOVED(-1) → 正在扩容，协助迁移
        else if ((fh = f.hash) == MOVED)
            tab = helpTransfer(tab, f);

        // ⑦ 桶不为空且不在扩容 → 锁住头节点操作
        else {
            V oldVal = null;
            synchronized (f) {
                // 双重检查：确认 f 仍然是头节点
                // （锁住 f 之前，f 可能已经被其他线程修改）
                if (tabAt(tab, i) == f) {

                    // ⑧ 头节点 hash >= 0 → 链表节点
                    if (fh >= 0) {
                        binCount = 1;
                        for (Node<K,V> e = f;; ++binCount) {
                            K ek;
                            // 找到相同 key → 覆盖 value
                            if (e.hash == hash &&
                                ((ek = e.key) == key ||
                                 (ek != null && key.equals(ek)))) {
                                oldVal = e.value;
                                if (!onlyIfAbsent)
                                    e.value = value;
                                break;
                            }
                            Node<K,V> pred = e;
                            // 到达尾部 → 尾插新节点
                            if ((e = e.next) == null) {
                                pred.next = new Node<K,V>(hash, key,
                                                          value, null);
                                break;
                            }
                        }
                    }

                    // ⑨ 头节点是 TreeBin → 红黑树操作
                    else if (f instanceof TreeBin) {
                        Node<K,V> p;
                        binCount = 2;
                        if ((p = ((TreeBin<K,V>)f).putTreeVal(hash, key,
                                                               value)) != null) {
                            oldVal = p.value;
                            if (!onlyIfAbsent)
                                p.value = value;
                        }
                    }
                }
            }

            // ⑩ 链表长度达到树化阈值
            if (binCount != 0) {
                if (binCount >= TREEIFY_THRESHOLD)
                    treeifyBin(tab, i);
                if (oldVal != null)
                    return oldVal;
                break;
            }
        }
    }

    // ⑪ 更新计数，检查是否需要扩容
    addCount(1L, binCount);
    return null;
}
```

### 5.3 流程图

```
put(key, value)
    │
    ▼
key/value 为 null？──是──→ 抛 NullPointerException
    │
    否
    ▼
计算 hash = spread(key.hashCode())
    │
    ▼
┌─→ table 为空？──是──→ initTable() 初始化
│       │
│      否
│       ▼
│   桶为空？──是──→ CAS 插入新节点 ──成功──→ break
│       │                           │
│      否                       失败（竞争）
│       ▼                           │
│   头节点 hash == MOVED？──是──→ helpTransfer() 协助扩容
│       │                           │
│      否                           │
│       ▼                           │
│   synchronized(头节点)             │
│     ├─ 链表：遍历找/插             │
│     └─ 红黑树：putTreeVal          │
│       │                           │
│       ▼                           │
│   binCount ≥ 8？──是──→ treeifyBin()
│       │                           │
│      否                           │
│       ▼                           │
└─── break ←────────────────────────┘
    │
    ▼
addCount(1, binCount) → 更新计数 + 检查扩容
    │
    ▼
返回 null / 旧值
```

### 5.4 关键细节：为什么不允许 null key/value？

```java
if (key == null || value == null) throw new NullPointerException();
```

**原因**：如果 `get(key)` 返回 null，在并发场景下无法区分：
- key 不存在 → 真的 null
- key 存在但 value 为 null → 也是 null

HashMap 是单线程的，可以用 `containsKey()` 再次确认。ConcurrentHashMap 在并发下，`containsKey()` 和 `get()` 之间可能被其他线程修改，结果不可靠。所以干脆禁止 null。

---

## 6. initTable 初始化

```java
private final Node<K,V>[] initTable() {
    Node<K,V>[] tab; int sc;

    while ((tab = table) == null || tab.length == 0) {
        // ① sizeCtl < 0 → 其他线程正在初始化，让出 CPU
        if ((sc = sizeCtl) < 0)
            Thread.yield(); // 自旋等待

        // ② CAS 将 sizeCtl 从 sc 改为 -1（拿到初始化权）
        else if (U.compareAndSwapInt(this, SIZECTL, sc, -1)) {
            try {
                if ((tab = table) == null || tab.length == 0) {
                    // sc > 0 说明构造时指定了容量，否则使用默认 16
                    int n = (sc > 0) ? sc : DEFAULT_CAPACITY;
                    @SuppressWarnings("unchecked")
                    Node<K,V>[] nt = (Node<K,V>[])new Node[n];
                    table = tab = nt;
                    // sc = 0.75 * n，等价于 n - n/4
                    sc = n - (n >>> 2);
                }
            } finally {
                sizeCtl = sc; // 设置扩容阈值
            }
            break;
        }
    }
    return tab;
}
```

**为什么用 `Thread.yield()` 而不是 `LockSupport.park()`？**

初始化很快（只是分配数组），用 yield 让出 CPU 片刻即可，park/unpark 的开销反而更大。

---

## 7. get 流程

### 7.1 完整源码

```java
public V get(Object key) {
    Node<K,V>[] tab; Node<K,V> e, p; int n, eh; K ek;
    int h = spread(key.hashCode());

    // ① table 不为空 且 桶不为空
    if ((tab = table) != null && (n = tab.length) > 0 &&
        (e = tabAt(tab, (n - 1) & h)) != null) {

        // ② 检查头节点
        if ((eh = e.hash) == h) {
            if ((ek = e.key) == key || (ek != null && key.equals(ek)))
                return e.value;
        }

        // ③ hash < 0 → 特殊节点
        else if (eh < 0)
            // ForwardingNode(eh==-1)：到新数组中查找
            // TreeBin(eh==-2)：在红黑树中查找
            // ReservedNode(eh==-3)：计算型映射占位
            return (p = e.find(h, key)) != null ? p.value : null;

        // ④ 遍历链表
        while ((e = e.next) != null) {
            if (e.hash == h &&
                ((ek = e.key) == key || (ek != null && key.equals(ek))))
                return e.value;
        }
    }
    return null;
}
```

### 7.2 流程图

```
get(key)
    │
    ▼
计算 hash = spread(key.hashCode())
    │
    ▼
table 为空 或 桶为空？──是──→ 返回 null
    │
    否
    ▼
头节点 hash 匹配 且 key 匹配？──是──→ 返回 value
    │
    否
    ▼
头节点 hash < 0？──是──→ 特殊节点的 find()
    │                      ├─ ForwardingNode → 到 nextTable 查找
    │                      └─ TreeBin → 红黑树查找
    否
    ▼
遍历链表查找
    ├─ 找到 → 返回 value
    └─ 未找到 → 返回 null
```

### 7.3 get 为什么不需要加锁？

1. **Node 的 val 和 next 是 volatile 的**，保证可见性
2. **tabAt 使用 volatile 语义读取**数组元素
3. **ForwardingNode 的 find 方法**会自动路由到新数组，保证扩容期间也能读到数据

```java
static class Node<K,V> implements Map.Entry<K,V> {
    final int hash;
    final K key;
    volatile V val;       // ★ volatile
    volatile Node<K,V> next;  // ★ volatile
}
```

---

## 8. remove 流程

```java
public V remove(Object key) {
    return replaceNode(key, null, null);
}

final V replaceNode(Object key, V value, Object cv) {
    int hash = spread(key.hashCode());

    for (Node<K,V>[] tab = table;;) {
        Node<K,V> f; int n, i, fh;

        // ① table 为空 或 桶为空 → 退出
        if (tab == null || (n = tab.length) == 0 ||
            (f = tabAt(tab, i = (n - 1) & hash)) == null)
            break;

        // ② 桶头节点为 ForwardingNode → 协助扩容
        else if ((fh = f.hash) == MOVED)
            tab = helpTransfer(tab, f);

        // ③ 锁住头节点操作
        else {
            V oldVal = null;
            boolean validated = false;
            synchronized (f) {
                if (tabAt(tab, i) == f) {
                    if (fh >= 0) {
                        // ④ 链表删除
                        validated = true;
                        for (Node<K,V> e = f, pred = null;;) {
                            K ek;
                            if (e.hash == hash &&
                                ((ek = e.key) == key ||
                                 (ek != null && key.equals(ek)))) {
                                V ev = e.value;
                                // cv 为 null 表示无条件删除
                                if (cv == null || cv == ev ||
                                    (ev != null && cv.equals(ev))) {
                                    oldVal = ev;
                                    if (value != null)
                                        e.value = value; // 替换
                                    else if (pred != null)
                                        pred.next = e.next; // 删除中间节点
                                    else
                                        tabAt(tab, i, Node.class, f); // 不，应该用 setTabAt
                                    setTabAt(tab, i, e.next); // 删除头节点
                                }
                                break;
                            }
                            pred = e;
                            if ((e = e.next) == null)
                                break;
                        }
                    }
                    else if (f instanceof TreeBin) {
                        // ⑤ 红黑树删除
                        validated = true;
                        TreeBin<K,V> t = (TreeBin<K,V>)f;
                        TreeNode<K,V> r, p;
                        if ((r = t.root) != null &&
                            (p = r.findTreeNode(hash, key, null)) != null) {
                            V pv = p.val;
                            if (cv == null || cv == pv ||
                                (pv != null && cv.equals(pv))) {
                                oldVal = pv;
                                if (value != null)
                                    p.val = value;
                                else
                                    t.removeTreeNode(p);
                            }
                        }
                    }
                }
            }
            if (validated) {
                if (oldVal != null) {
                    // value 为 null 表示删除，更新计数
                    if (value == null)
                        addCount(-1L, -1);
                    return oldVal;
                }
                break;
            }
        }
    }
    return null;
}
```

---

## 9. transfer 扩容机制

### 9.1 核心设计思想

1. **多线程协作**：每个线程领取一段桶（stride=16）进行迁移
2. **transferIndex 从大到小分配**：避免线程冲突
3. **ForwardingNode 占位**：已迁移的桶放入 ForwardingNode，其他线程的 put 操作遇到它会协助扩容
4. **高低位拆分**：与 HashMap 相同，`(hash & oldCap) == 0` 留低位，否则移高位

### 9.2 迁移任务分配示意

```
旧数组长度 n = 32，stride = 16

transferIndex 初始 = 32

线程A 领取 [16, 31]，transferIndex = 16
线程B 领取 [0, 15]， transferIndex = 0  → 迁移完成

每个线程处理自己领取的桶区间，互不干扰
```

### 9.3 transfer 核心源码（精简 + 注释）

```java
private final void transfer(Node<K,V>[] tab, Node<K,V>[] nextTab) {
    int n = tab.length, stride;

    // ① 计算每个线程迁移的步长
    if ((stride = (NCPU > 1) ? (n >>> 3) / NCPU : n) < MIN_TRANSFER_STRIDE)
        stride = MIN_TRANSFER_STRIDE; // 最少 16 个桶

    // ② 第一个发起扩容的线程创建新数组
    if (nextTab == null) {
        try {
            @SuppressWarnings("unchecked")
            Node<K,V>[] nt = (Node<K,V>[])new Node[n << 1]; // 2倍
            nextTab = nt;
        } catch (Throwable ex) {
            sizeCtl = Integer.MAX_VALUE;
            return;
        }
        nextTable = nextTab;
        transferIndex = n; // 从旧数组末尾开始分配
    }

    int nextn = nextTab.length;
    // ③ 创建 ForwardingNode，hash = -1，指向新数组
    ForwardingNode<K,V> fwd = new ForwardingNode<K,V>(nextTab);

    // advance: 是否可以继续向前推进
    // finishing: 是否所有桶都迁移完成
    boolean advance = true;
    boolean finishing = false;

    for (int i = 0, bound = 0;;) {
        Node<K,V> f; int fh;

        // ④ 领取任务区间 [bound, i]
        while (advance) {
            int nextIndex, nextBound;
            if (--i >= bound || finishing)
                advance = false;
            else if ((nextIndex = transferIndex) <= 0) {
                i = -1; // 所有桶已分配完
                advance = false;
            }
            else if (U.compareAndSwapInt
                     (this, TRANSFERINDEX, nextIndex,
                      nextBound = (nextIndex > stride ?
                                   nextIndex - stride : 0))) {
                bound = nextBound;
                i = nextIndex - 1;
                advance = false;
            }
        }

        // ⑤ 退出条件
        if (i < 0 || i >= n || i + n >= nextn) {
            int sc;
            if (finishing) {
                nextTable = null;
                table = nextTab;        // 切换到新数组
                sizeCtl = (n << 1) - (n >>> 1); // 新阈值 = 0.75 * 2n
                return;
            }
            // 当前线程完成自己负责的桶，CAS 将线程数减 1
            if (U.compareAndSwapInt(this, SIZECTL, sc = sizeCtl, sc - 1)) {
                if ((sc - 2) != resizeStamp(n) << RESIZE_STAMP_SHIFT)
                    return; // 还有其他线程在扩容，当前线程退出
                finishing = advance = true; // 最后一个线程，做最终检查
                i = n; // 从头再检查一遍
            }
        }

        // ⑥ 桶为空 → 放入 ForwardingNode
        else if ((f = tabAt(tab, i)) == null)
            advance = casTabAt(tab, i, null, fwd);

        // ⑦ 桶已经被迁移 → 跳过
        else if ((fh = f.hash) == MOVED)
            advance = true;

        // ⑧ 迁移数据
        else {
            synchronized (f) {
                if (tabAt(tab, i) == f) {
                    Node<K,V> ln, hn;
                    if (fh >= 0) {
                        // 链表拆分（与 HashMap 相同）
                        int runBit = fh & n;
                        Node<K,V> lastRun = f;
                        for (Node<K,V> p = f.next; p != null; p = p.next) {
                            int b = p.hash & n;
                            if (b != runBit) {
                                runBit = b;
                                lastRun = p;
                            }
                        }
                        if (runBit == 0) {
                            ln = lastRun;
                            hn = null;
                        }
                        else {
                            hn = lastRun;
                            ln = null;
                        }
                        for (Node<K,V> p = f; p != lastRun; p = p.next) {
                            int ph = p.hash; K pk = p.key; V pv = p.val;
                            if ((ph & n) == 0)
                                ln = new Node<K,V>(ph, pk, pv, ln);
                            else
                                hn = new Node<K,V>(ph, pk, pv, hn);
                        }
                        // 低位链放入新数组原位置
                        setTabAt(nextTab, i, ln);
                        // 高位链放入新数组 i+n 位置
                        setTabAt(nextTab, i + n, hn);
                        // 旧桶放入 ForwardingNode
                        setTabAt(tab, i, fwd);
                        advance = true;
                    }
                    else if (f instanceof TreeBin) {
                        // 红黑树拆分
                        TreeBin<K,V> t = (TreeBin<K,V>)f;
                        TreeNode<K,V> lo = null, loTail = null;
                        TreeNode<K,V> hi = null, hiTail = null;
                        int lc = 0, hc = 0;
                        for (Node<K,V> e = t.first; e != null; e = e.next) {
                            int h = e.hash;
                            TreeNode<K,V> p = new TreeNode<K,V>
                                (h, e.key, e.val, null, null);
                            if ((h & n) == 0) {
                                if ((p.prev = loTail) == null)
                                    lo = p;
                                else
                                    loTail.next = p;
                                loTail = p;
                                ++lc;
                            }
                            else {
                                if ((p.prev = hiTail) == null)
                                    hi = p;
                                else
                                    hiTail.next = p;
                                hiTail = p;
                                ++hc;
                            }
                        }
                        // 拆分后节点数 ≤ 6 → 退回链表
                        ln = (lc <= UNTREEIFY_THRESHOLD) ? untreeify(lo) :
                            (hc != 0) ? new TreeBin<K,V>(lo) : t;
                        hn = (hc <= UNTREEIFY_THRESHOLD) ? untreeify(hi) :
                            (lc != 0) ? new TreeBin<K,V>(hi) : t;
                        setTabAt(nextTab, i, ln);
                        setTabAt(nextTab, i + n, hn);
                        setTabAt(tab, i, fwd);
                        advance = true;
                    }
                }
            }
        }
    }
}
```

### 9.4 ForwardingNode

```java
static final class ForwardingNode<K,V> extends Node<K,V> {
    final Node<K,V>[] nextTable;

    ForwardingNode(Node<K,V>[] tab) {
        super(MOVED, null, null, null);  // hash = -1 (MOVED)
        this.nextTable = tab;
    }

    // 在新数组中查找
    Node<K,V> find(int h, Object k) {
        // 外循环：防止 nextTable 也在扩容
        outer: for (Node<K,V>[] tab = nextTable;;) {
            Node<K,V> e; int n;
            if (k == null || tab == null || (n = tab.length) == 0 ||
                (e = tabAt(tab, (n - 1) & h)) == null)
                return null;
            for (;;) {
                int eh; K ek;
                if ((eh = e.hash) == h &&
                    ((ek = e.key) == k || (ek != null && k.equals(ek))))
                    return e;
                if (eh < 0) {
                    if (e instanceof ForwardingNode) {
                        tab = ((ForwardingNode<K,V>)e).nextTable;
                        continue outer; // 继续在新表中查找
                    }
                    else
                        return e.find(h, k); // TreeBin 的 find
                }
                if ((e = e.next) == null)
                    return null;
            }
        }
    }
}
```

### 9.5 多线程扩容时序图

```
时间 ──────────────────────────────────────────────►

线程A:  [领取桶16-31] [迁移桶16] [迁移桶17] ... [迁移桶31] [退出]
线程B:  [领取桶0-15]  [迁移桶0]  [迁移桶1]  ... [迁移桶15] [退出]
线程C:            [put→桶5→协助] [领取桶8-15] [迁移] ... [退出]

每个桶迁移完成后，放置 ForwardingNode 占位：
  - put 操作遇到 ForwardingNode → 调用 helpTransfer 协助扩容
  - get 操作遇到 ForwardingNode → 转发到 nextTable 查找
```

---

## 10. helpTransfer 协助扩容

```java
final Node<K,V>[] helpTransfer(Node<K,V>[] tab, Node<K,V> f) {
    Node<K,V>[] nextTab; int sc;

    if (tab != null && (f instanceof ForwardingNode) &&
        (nextTab = ((ForwardingNode<K,V>)f).nextTable) != null) {

        // resizeStamp 生成扩容标识
        int rs = resizeStamp(tab.length);

        // 循环：只要还在扩容，就持续协助
        while (nextTab == nextTable && table == tab &&
               (sc = sizeCtl) < 0) {

            // 退出条件：
            // 1. sizeCtl 没变（不是同一个扩容周期）
            // 2. 扩容已完成
            // 3. 默认并发级别已满
            if ((sc >>> RESIZE_STAMP_SHIFT) != rs || sc == rs + 1 ||
                sc == rs + MAX_RESIZERS || transferIndex <= 0)
                break;

            // CAS 将 sizeCtl + 1（增加一个协助线程）
            if (U.compareAndSwapInt(this, SIZECTL, sc, sc + 1)) {
                transfer(tab, nextTab);
                break;
            }
        }
        return nextTab;
    }
    return table;
}
```

---

## 11. 树化与反树化

### 11.1 treeifyBin

```java
private final void treeifyBin(Node<K,V>[] tab, int index) {
    Node<K,V> b; int n, sc;

    if (tab != null) {
        // ① 数组长度 < 64 → 优先扩容，不树化
        if ((n = tab.length) < MIN_TREEIFY_CAPACITY)
            tryPresize(n << 1);

        // ② 桶不为空 且 头节点 hash ≥ 0（链表）
        else if ((b = tabAt(tab, index)) != null && b.hash >= 0) {
            synchronized (b) { // 锁住头节点
                if (tabAt(tab, index) == b) {
                    TreeNode<K,V> hd = null, tl = null;
                    for (Node<K,V> e = b; e != null; e = e.next) {
                        TreeNode<K,V> p =
                            new TreeNode<K,V>(e.hash, e.key, e.val,
                                              null, null);
                        if ((p.prev = tl) == null)
                            hd = p;
                        else
                            tl.next = p;
                        tl = p;
                    }
                    // 用 TreeBin 包装红黑树根节点
                    setTabAt(tab, index, new TreeBin<K,V>(hd));
                }
            }
        }
    }
}
```

### 11.2 TreeBin —— 红黑树的"外壳"

```java
static final class TreeBin<K,V> extends Node<K,V> {
    TreeNode<K,V> root;          // 红黑树根节点
    volatile TreeNode<K,V> first; // 链表首节点
    volatile Thread waiter;       // 等待锁的线程
    volatile int lockState;       // 锁状态

    // lockState 位含义：
    // 1 (WRITER)   : 写锁
    // 2 (WAITER)   : 有线程等待写锁
    // 4 (READER)   : 读锁，每多一个读线程 +4

    static final int WRITER = 1;
    static final int WAITER = 2;
    static final int READER = 4;
}
```

**TreeBin 的读写锁机制：**
- **写操作**（putTreeVal/removeTreeNode）：获取写锁，阻塞其他读写
- **读操作**（find）：乐观读，如果无写锁直接读；有写锁则遍历链表（next 字段是 volatile 的）

```java
// TreeBin.find 的乐观读
final Node<K,V> find(int h, Object k) {
    if (k != null) {
        for (Node<K,V> e = first; e != null; ) {
            int s; K ek;
            // 如果锁状态没有写锁 → 直接读红黑树
            if (((s = lockState) & ~WAITER) != 0) {
                // 有写锁 → 退化为遍历链表
                if (e.hash == h && ((ek = e.key) == k || (ek != null && k.equals(ek))))
                    return e;
                e = e.next;
            }
            else if (U.compareAndSwapInt(this, LOCKSTATE, s, s + READER)) {
                // 获取读锁成功 → 遍历红黑树
                TreeNode<K,V> r, p;
                try {
                    p = ((r = root) == null ? null :
                         r.findTreeNode(h, k, null));
                } finally {
                    // 释放读锁
                    if (U.getAndAddInt(this, LOCKSTATE, -READER) == (READER|WAITER))
                        LockSupport.unpark(waiter); // 唤醒等待的写线程
                }
                return p;
            }
        }
    }
    return null;
}
```

### 11.3 为什么 ConcurrentHashMap 的树化比 HashMap 更复杂？

1. TreeBin 自带读写锁，保证并发安全
2. 读操作可以无锁遍历链表（降级方案），避免与写操作竞争
3. TreeBin 的 hash 为 -2，get 时通过 `f.find()` 查找

---

## 12. size 计数机制

### 12.1 整体思路

仿照 LongAdder 的分散计数思想：

```
┌──────────────────────────────────────────┐
│            baseCount (volatile long)      │  ← 无竞争时直接 CAS 更新
│                                           │
│  CounterCell[] (volatile)                 │  ← 有竞争时分散到各 cell
│  ┌──────────┬──────────┬──────────┐       │
│  │ cell[0]  │ cell[1]  │ cell[2]  │ ...   │  ← 每个线程映射到一个 cell
│  │  value   │  value   │  value   │       │
│  └──────────┴──────────┴──────────┘       │
│                                           │
│  总 size = baseCount + Σ cell[i].value    │
└──────────────────────────────────────────┘
```

### 12.2 addCount 源码

```java
private final void addCount(long x, int check) {
    CounterCell[] as; long b, v; int s;

    // ① 尝试 CAS 更新 baseCount
    if ((as = counterCells) != null ||
        !U.compareAndSwapLong(this, BASECOUNT, b = baseCount, s = (long)(b + x))) {

        // ② baseCount CAS 失败 → 分散到 CounterCell
        CounterCell a; long v; int m;
        boolean uncontended = true;
        if (as == null || (m = as.length - 1) < 0 ||
            (a = as[ThreadLocalRandom.getProbe() & m]) == null ||
            !(uncontended =
              U.compareAndSwapLong(a, CELLVALUE, v = a.value, v + x))) {
            // ③ 对应 cell 也竞争失败 → fullAddCount（创建/扩容 CounterCell）
            fullAddCount(x, uncontended);
            return;
        }
    }

    // ④ 检查是否需要扩容
    if (check >= 0) {
        Node<K,V>[] tab, nt; int n, sc;
        while (s >= (long)(sc = sizeCtl) && (tab = table) != null &&
               (n = tab.length) < MAXIMUM_CAPACITY) {
            int rs = resizeStamp(n);
            if (sc < 0) {
                // 正在扩容，尝试协助
                if ((sc >>> RESIZE_STAMP_SHIFT) != rs || sc == rs + 1 ||
                    sc == rs + MAX_RESIZERS || (nt = nextTable) == null ||
                    transferIndex <= 0)
                    break;
                if (U.compareAndSwapInt(this, SIZECTL, sc, sc + 1))
                    transfer(tab, nt);
            }
            // 触发扩容
            else if (U.compareAndSwapInt(this, SIZECTL, sc,
                                         (rs << RESIZE_STAMP_SHIFT) + 2))
                transfer(tab, null);
            s = size();
        }
    }
}
```

### 12.3 size() 方法

```java
public int size() {
    long n = sumCount();
    return ((n < 0L) ? 0 :
            (n > (long)Integer.MAX_VALUE) ? Integer.MAX_VALUE :
            (int)n);
}

final long sumCount() {
    CounterCell[] as = counterCells;
    long sum = baseCount;
    if (as != null) {
        for (CounterCell a : as) {
            if (a != null)
                sum += a.value;
        }
    }
    return sum;
}
```

**注意**：`size()` 返回的是一个近似值！遍历 baseCount 和 counterCells 的过程中，其他线程可能正在修改。

### 12.4 mappingCount —— 更精确的计数

```java
public long mappingCount() {
    long n = sumCount();
    if (transientHarmonics != null)
        n += transientHarmonics.sum();
    return n;
}
```

---

## 13. forEach / search / reduce 并发批量操作

JDK 8 引入了三个并发批量操作方法，每个都有 xKey / xValue / xEntry 变体：

### 13.1 forEach

```java
public void forEach(BiConsumer<? super K, ? super V> action) {
    if (action == null) throw new NullPointerException();
    Node<K,V>[] t;
    if ((t = table) != null) {
        Traverser<K,V> it = new Traverser<K,V>(t, t.length, 0, t.length);
        for (Node<K,V> p; (p = it.advance()) != null; ) {
            action.accept(p.key, p.val);
        }
    }
}
```

### 13.2 search

```java
// 并行搜索，找到第一个非 null 结果即返回
public <U> U search(long parallelism,
                     Function<? super Map.Entry<K,V>, ? extends U> searchFunction) {
    // 使用 ForkJoinPool 并行执行
    // 某个线程找到结果后，其他线程尽快退出
}
```

### 13.3 reduce

```java
// 并行归约
public V reduceValues(long parallelism,
                       BiFunction<? super V, ? super V, ? extends V> reducer) {
    // 每个线程处理一段桶，局部 reduce
    // 最终合并所有线程的结果
}
```

---

## 14. JDK 版本演进对比

| 特性 | JDK 7 | JDK 8 | JDK 9+ |
|------|-------|-------|--------|
| 并发策略 | Segment 分段锁 | CAS + synchronized 桶锁 | 同 JDK 8 |
| 锁粒度 | Segment（默认16段） | 单个桶 | 单个桶 |
| 数据结构 | HashEntry[] 链表 | Node[] + 链表 + 红黑树 | 同 JDK 8 |
| null key/value | 不允许 | 不允许 | 不允许 |
| 扩容 | 单线程扩容 | 多线程协助扩容 | 同 JDK 8 |
| 计数 | Segment.count 累加 | baseCount + CounterCell | 同 JDK 8 |
| 批量操作 | 无 | forEach/search/reduce | 同 JDK 8 |
| 序列化 | 支持 | 支持 | JDK 9+: 基于 Lambda 的不可序列化 |
| 只读视图 | 无 | 无 | JDK 10+: readOnlyMap() |
| JDK 9 特有 | - | - | k/v 偏向（JEP 254 紧凑字符串相关优化不直接相关） |

### JDK 7 Segment 分段锁详细结构

```
ConcurrentHashMap
  ├── Segment[0]  (ReentrantLock)
  │     └── HashEntry[] → 链表
  ├── Segment[1]
  │     └── HashEntry[] → 链表
  │  ...
  └── Segment[15]
        └── HashEntry[] → 链表

每个 Segment 是一个独立的 HashMap
锁住 Segment → 该 Segment 下所有桶都被锁住
并发度 = Segment 数量（默认16）
```

---

## 15. ConcurrentHashMap vs HashMap vs Hashtable

| 特性 | ConcurrentHashMap | HashMap | Hashtable |
|------|-------------------|---------|-----------|
| 线程安全 | ✅ CAS + synchronized | ❌ | ✅ 全局 synchronized |
| null key | ❌ NPE | ✅ 允许1个 | ❌ NPE |
| null value | ❌ NPE | ✅ 允许多个 | ❌ NPE |
| 锁粒度 | 单桶 | 无锁 | 整个 Map |
| 并发度 | ≈ 桶数量 | 0 | 1 |
| 扩容 | 多线程协助 | 单线程 | 单线程 |
| 红黑树 | ✅ JDK 8+ | ✅ JDK 8+ | ❌ |
| 迭代器 | 弱一致性（Weakly consistent） | fail-fast | fail-fast（enumerator 弱一致） |
| 性能 | 高 | 最高（无锁开销） | 最低 |
| 推荐场景 | 多线程共享 | 单线程 | 已过时，不推荐 |

### 弱一致性迭代器

ConcurrentHashMap 的迭代器不会抛出 `ConcurrentModificationException`，但：
- 可能看到也可能看不到迭代开始后的修改
- 不会返回在迭代开始后被删除的条目
- 可能返回在迭代开始后新增的条目

```java
// 弱一致性的体现
ConcurrentHashMap<String, Integer> map = new ConcurrentHashMap<>();
map.put("a", 1);
Iterator<String> it = map.keySet().iterator();
map.put("b", 2);  // 迭代器可能看到也可能看不到 "b"
// 但绝不会抛 ConcurrentModificationException
```

---

## 16. 常见面试题

### Q1: ConcurrentHashMap 的 key 可以是 null 吗？

不可以。key 和 value 都不允许为 null，否则抛出 `NullPointerException`。原因是在并发环境下，`get(key)` 返回 null 无法区分"key 不存在"和"value 为 null"。

### Q2: JDK 7 和 JDK 8 的 ConcurrentHashMap 有什么区别？

| | JDK 7 | JDK 8 |
|---|-------|-------|
| 实现 | Segment + HashEntry | Node + CAS + synchronized |
| 锁 | ReentrantLock（Segment级） | synchronized（桶级） |
| 并发度 | 固定（默认16） | 动态（=桶数量） |
| 哈希冲突 | 纯链表 | 链表 + 红黑树 |
| 扩容 | 单线程 | 多线程协助 |
| 计数 | 遍历 Segment | baseCount + CounterCell |

### Q3: ConcurrentHashMap 的 size() 方法是精确的吗？

不是。`size()` 是一个近似值，因为 `sumCount()` 遍历 baseCount 和 counterCells 时不是原子操作。如果需要更精确的值，使用 `mappingCount()`，但它也不保证完全精确。

### Q4: ConcurrentHashMap 如何保证扩容时的读写？

- **读（get）**：遇到 ForwardingNode 会自动转发到 nextTable 查找，不阻塞
- **写（put）**：遇到 ForwardingNode 会调用 `helpTransfer()` 协助扩容，扩容完成后再写入新表
- **核心**：扩容期间不会阻塞任何操作

### Q5: 为什么用 synchronized 而不是 ReentrantLock？

1. **内存效率**：synchronized 不需要额外对象（ReentrantLock 每个实例 ≈ 24 字节）
2. **JVM 优化**：偏向锁 → 轻量级锁 → 重量级锁的锁升级机制
3. **锁粒度**：只锁单个桶，冲突概率极低，大部分时候偏向锁/轻量级锁就够了

### Q6: CAS 是什么？为什么 ConcurrentHashMap 大量使用？

CAS（Compare And Swap）：比较并交换，是一种无锁算法。

```java
// 伪代码
boolean cas(内存地址, 期望值, 新值) {
    if (当前值 == 期望值) {
        当前值 = 新值;
        return true;
    }
    return false; // 其他线程已修改，重试
}
```

优势：无锁操作，不会阻塞线程，适合低冲突场景（如桶为空时插入）。

### Q7: ConcurrentHashMap 的并发度是多少？

- JDK 7：并发度 = Segment 数量，默认 16，构造后不可变
- JDK 8：并发度 = 桶数量，随扩容动态增长，理论上无上限

### Q8: resizeStamp 是什么？

```java
static final int resizeStamp(int n) {
    return Integer.numberOfLeadingZeros(n) | (1 << (RESIZE_STAMP_BITS - 1));
}
```

它生成一个与数组长度 n 相关的唯一标识，高 16 位用于标识扩容周期，低 16 位记录参与扩容的线程数。确保不同扩容周期的 sizeCtl 不会混淆。

### Q9: ConcurrentHashMap 在什么场景下性能不如 HashMap？

1. **单线程场景**：CAS 和 synchronized 有额外开销
2. **大量写冲突**：多个线程频繁写同一个桶，synchronized 会退化为串行
3. **低并发度**：并发线程数远小于桶数量时，锁竞争少，但 CAS 开销仍存在

### Q10: 如何选择 ConcurrentHashMap 的初始容量？

与 HashMap 类似，如果能预估数据量，建议在构造时指定，避免频繁扩容：

```java
// 预计 1000 个元素
// 1000 / 0.75 ≈ 1334，取最近的 2 的幂 = 2048
ConcurrentHashMap<String, Integer> map = new ConcurrentHashMap<>(2048);
```

注意：ConcurrentHashMap 的构造方法会额外增加 50% 的容量余量：

```java
int cap = tableSizeFor(initialCapacity + (initialCapacity >>> 1) + 1);
// 所以传入 1000 → cap = tableSizeFor(1501) = 2048
```

---

## 附录 A：核心内部类一览

| 类 | hash 值 | 作用 |
|----|---------|------|
| `Node<K,V>` | ≥ 0 | 普通链表节点 |
| `TreeNode<K,V>` | ≥ 0 | 红黑树节点（继承自 Node） |
| `TreeBin<K,V>` | -2 | 红黑树包装器，管理树的读写锁 |
| `ForwardingNode<K,V>` | -1 | 扩容占位节点，指向 nextTable |
| `ReservationNode<K,V>` | -3 | computeIfAbsent 的占位节点 |

## 附录 B：hash 值含义速查

```
hash >= 0    → 正常节点（链表节点 / 树节点）
hash == -1   → ForwardingNode（MOVED，扩容中）
hash == -2   → TreeBin（红黑树根）
hash == -3   → ReservationNode（计算型占位）
```

## 附录 C：spread 方法

```java
static final int spread(int h) {
    // 与 HashMap 的扰动类似，但多了一个 & HASH_BITS
    // HASH_BITS = 0x7fffffff，确保结果为正数
    // 因为负数 hash 有特殊含义（MOVED、TREEBIN 等）
    return (h ^ (h >>> 16)) & HASH_BITS;
}
```

**为什么需要 `& HASH_BITS`？**

ConcurrentHashMap 中 hash < 0 有特殊含义（ForwardingNode、TreeBin 等），所以普通节点的 hash 必须保证 ≥ 0。`& 0x7fffffff` 将最高位置 0，确保结果非负。

---

> 本文档基于 JDK 8 源码整理，重点讲解并发控制机制、多线程扩容、分散计数等核心设计。
> 建议配合实际调试，在 putVal、transfer、addCount 打断点，观察多线程交互过程。
