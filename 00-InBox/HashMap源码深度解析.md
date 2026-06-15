# Java HashMap 源码深度解析

> 基于 JDK 8 版本，覆盖 JDK 7/8/11/17 关键差异标注

---

## 目录

1. [整体架构](#1-整体架构)
2. [核心字段](#2-核心字段)
3. [构造方法](#3-构造方法)
4. [hash 计算与扰动](#4-hash-计算与扰动)
5. [put 流程（核心）](#5-put-流程核心)
6. [resize 扩容机制](#6-resize-扩容机制)
7. [树化与反树化](#7-树化与反树化)
8. [get 流程](#8-get-流程)
9. [remove 流程](#9-remove-流程)
10. [遍历机制](#10-遍历机制)
11. [序列化](#11-序列化)
12. [线程安全问题](#12-线程安全问题)
13. [JDK 版本演进对比](#13-jdk-版本演进对比)
14. [常见面试题](#14-常见面试题)

---

## 1. 整体架构

HashMap 本质是一个 **数组 + 链表 + 红黑树** 的组合结构：

```
┌─────────────────────────────────────────────────────────────────┐
│  table[] (Node<K,V> 数组)                                       │
│  ┌─────┐                                                        │
│  │  0  │ → null                                                  │
│  ├─────┤                                                        │
│  │  1  │ → Node → Node → Node  (链表, 长度 < 8)                  │
│  ├─────┤                                                        │
│  │  2  │ → null                                                  │
│  ├─────┤                                                        │
│  │  3  │ → TreeNode → TreeNode → TreeNode → ... (红黑树, ≥ 8)    │
│  ├─────┤                                                        │
│  │ ... │                                                        │
│  ├─────┤                                                        │
│  │ n-1 │ → Node                                                 │
│  └─────┘                                                        │
└─────────────────────────────────────────────────────────────────┘
```

**关键设计决策：**
- 数组是主体，下标由 `(n-1) & hash` 决定（n 为数组长度，始终为 2 的幂）
- 链表在哈希冲突时使用，JDK 8 引入红黑树优化长链表查询
- 负载因子 0.75 是时间与空间的折中

---

## 2. 核心字段

```java
public class HashMap<K,V> extends AbstractMap<K,V>
    implements Map<K,V>, Cloneable, Serializable {

    // 默认初始容量 16
    static final int DEFAULT_INITIAL_CAPACITY = 1 << 4; // aka 16

    // 最大容量 2^30
    static final int MAXIMUM_CAPACITY = 1 << 30;

    // 默认负载因子 0.75
    static final float DEFAULT_LOAD_FACTOR = 0.75f;

    // 链表转红黑树的阈值（链表长度 ≥ 8 时触发）
    static final int TREEIFY_THRESHOLD = 8;

    // 红黑树退回链表的阈值（扩容后树节点 ≤ 6 时退回）
    static final int UNTREEIFY_THRESHOLD = 6;

    // 树化的另一个条件：数组长度必须 ≥ 64，否则只扩容不树化
    static final int MIN_TREEIFY_CAPACITY = 64;

    // 哈希桶数组，长度始终为 2 的幂
    transient Node<K,V>[] table;

    // 键值对总数
    transient int size;

    // 结构修改次数（用于 fail-fast）
    transient int modCount;

    // 扩容阈值 = capacity * loadFactor
    int threshold;

    // 负载因子
    final float loadFactor;
}
```

### 为什么是 0.75？

- 太小（如 0.5）：空间浪费严重，频繁扩容
- 太大（如 1.0）：哈希冲突增多，链表变长，查询变慢
- 0.75 是泊松分布下链表长度超过 8 的概率极小（≈0.00000006）的理论依据

### 为什么链表转红黑树是 8？

根据泊松分布，负载因子 0.75 时，桶中元素个数的概率：

| 长度 | 概率 |
|------|------|
| 0 | 0.60653066 |
| 1 | 0.30326533 |
| 2 | 0.07581633 |
| 3 | 0.01263606 |
| 4 | 0.00157952 |
| 5 | 0.00015795 |
| 6 | 0.00001316 |
| 7 | 0.00000094 |
| **8** | **0.00000006** |

长度达到 8 的概率仅为千万分之六，属于极端情况，此时红黑树的 O(log n) 比链表的 O(n) 更优。

---

## 3. 构造方法

### 3.1 无参构造

```java
public HashMap() {
    this.loadFactor = DEFAULT_LOAD_FACTOR; // 0.75
    // 注意：此时不分配 table，延迟到第一次 put 时
}
```

### 3.2 指定初始容量

```java
public HashMap(int initialCapacity) {
    this(initialCapacity, DEFAULT_LOAD_FACTOR);
}
```

### 3.3 指定容量和负载因子

```java
public HashMap(int initialCapacity, float loadFactor) {
    if (initialCapacity < 0)
        throw new IllegalArgumentException("Illegal initial capacity: " + initialCapacity);
    if (initialCapacity > MAXIMUM_CAPACITY)
        initialCapacity = MAXIMUM_CAPACITY;
    if (loadFactor <= 0 || Float.isNaN(loadFactor))
        throw new IllegalArgumentException("Illegal load factor: " + loadFactor);

    this.loadFactor = loadFactor;
    // tableSizeFor: 将容量向上取整为最接近的 2 的幂
    this.threshold = tableSizeFor(initialCapacity);
}
```

### 3.4 tableSizeFor —— 容量对齐为 2 的幂

```java
static final int tableSizeFor(int cap) {
    int n = cap - 1;
    n |= n >>> 1;
    n |= n >>> 2;
    n |= n >>> 4;
    n |= n >>> 8;
    n |= n >>> 16;
    return (n < 0) ? 1 : (n >= MAXIMUM_CAPACITY) ? MAXIMUM_CAPACITY : n + 1;
}
```

**原理**：通过无符号右移 + 按位或，把最高位 1 之后的所有位都填 1，最后 +1 就得到 2 的幂。

```
例：cap = 13
n = 12 (0000 1100)
n |= n>>>1  → 0000 1110
n |= n>>>2  → 0000 1111
n |= n>>>4  → 0000 1111  (后续不变)
n + 1 = 16
```

---

## 4. hash 计算与扰动

```java
static final int hash(Object key) {
    int h;
    // key 为 null → hash = 0（永远放在桶 0）
    // 否则：高 16 位异或低 16 位
    return (key == null) ? 0 : (h = key.hashCode()) ^ (h >>> 16);
}
```

### 为什么需要扰动？

桶下标的计算是 `(n-1) & hash`，当 n 较小（如 16）时，`n-1 = 15 = 0000 1111`，只有低 4 位参与运算。如果两个 key 的 hashCode 高位不同但低位相同，就会冲突。扰动把高位信息"混合"到低位，减少冲突。

```
未扰动：  hash = 0b xxxx xxxx xxxx xxxx xxxx xxxx xxxA aaaa
n-1   =  0b 0000 0000 0000 0000 0000 0000 0000 1111
结果只看低4位 → 容易冲突

扰动后：  hash' = hash ^ (hash >>> 16)
高位信息被"搅"进低位 → 分布更均匀
```

---

## 5. put 流程（核心）

### 5.1 入口

```java
public V put(K key, V value) {
    return putVal(hash(key), key, value, false, true);
}
```

### 5.2 putVal 完整源码 + 逐行注释

```java
final V putVal(int hash, K key, V value, boolean onlyIfAbsent, boolean evict) {
    Node<K,V>[] tab; Node<K,V> p; int n, i;

    // ① table 为空或长度为 0 → 首次 put，触发 resize 初始化
    if ((tab = table) == null || (n = tab.length) == 0)
        n = (tab = resize()).length;

    // ② 计算桶下标：(n-1) & hash，如果该桶为空 → 直接放入
    if ((p = tab[i = (n - 1) & hash]) == null)
        tab[i] = newNode(hash, key, value, null);

    else {
        Node<K,V> e; K k;

        // ③ 桶不为空，检查首节点是否匹配（hash 相同 且 key 相等）
        if (p.hash == hash &&
            ((k = p.key) == key || (key != null && key.equals(k))))
            e = p; // 找到相同 key，记录下来

        // ④ 首节点不匹配，检查是否是红黑树节点
        else if (p instanceof TreeNode)
            e = ((TreeNode<K,V>)p).putTreeVal(this, tab, hash, key, value);

        // ⑤ 不是红黑树 → 遍历链表
        else {
            for (int binCount = 0; ; ++binCount) {
                // 到达链表尾部 → 尾插新节点
                if ((e = p.next) == null) {
                    p.next = newNode(hash, key, value, null);
                    // 链表长度达到树化阈值 → 尝试树化
                    if (binCount >= TREEIFY_THRESHOLD - 1) // -1 因为从0计数
                        treeifyBin(tab, hash);
                    break;
                }
                // 链表中找到相同 key
                if (e.hash == hash &&
                    ((k = e.key) == key || (key != null && key.equals(k))))
                    break;
                p = e;
            }
        }

        // ⑥ 找到了已存在的 key → 覆盖 value
        if (e != null) {
            V oldValue = e.value;
            if (!onlyIfAbsent || oldValue == null)
                e.value = value;
            afterNodeAccess(e); // LinkedHashMap 用的钩子
            return oldValue;
        }
    }

    ++modCount;

    // ⑦ 检查是否需要扩容
    if (++size > threshold)
        resize();

    afterNodeInsertion(evict); // LinkedHashMap 用的钩子
    return null;
}
```

### 5.3 流程图

```
put(key, value)
    │
    ▼
table 为空？──是──→ resize() 初始化
    │
    否
    ▼
桶 (n-1)&hash 为空？──是──→ 直接放入新 Node
    │
    否
    ▼
首节点 key 匹配？──是──→ 记录 e = p
    │
    否
    ▼
是 TreeNode？──是──→ putTreeVal() 红黑树插入
    │
    否（链表）
    ▼
遍历链表：
  ├─ 找到相同 key → 记录 e
  └─ 到达尾部 → 尾插新 Node
       └─ 长度 ≥ 8？→ treeifyBin()
    │
    ▼
e != null？（key 已存在）──是──→ 覆盖 value，返回旧值
    │
    否
    ▼
size++ > threshold？──是──→ resize()
    │
    ▼
返回 null（新插入）
```

### 5.4 关键细节

**Q: 为什么用 `(n-1) & hash` 而不是 `hash % n`？**

当 n 为 2 的幂时，`(n-1) & hash` 等价于 `hash % n`，但位运算更快。这也是容量必须为 2 的幂的原因。

**Q: JDK 7 是头插，JDK 8 为什么改成尾插？**

JDK 7 多线程扩容时，头插会导致链表反转，可能形成环链 → 死循环。尾插保持原有顺序，扩容后不会反转。

---

## 6. resize 扩容机制

### 6.1 完整源码 + 逐行注释

```java
final Node<K,V>[] resize() {
    Node<K,V>[] oldTab = table;
    int oldCap = (oldTab == null) ? 0 : oldTab.length;
    int oldThr = threshold;
    int newCap, newThr = 0;

    // ====== 第一部分：确定新容量和新阈值 ======

    if (oldCap > 0) {
        // 已有数据的情况
        if (oldCap >= MAXIMUM_CAPACITY) {
            threshold = Integer.MAX_VALUE; // 无法再扩
            return oldTab;
        }
        // 新容量 = 旧容量 × 2
        else if ((newCap = oldCap << 1) < MAXIMUM_CAPACITY &&
                 oldCap >= DEFAULT_INITIAL_CAPACITY)
            newThr = oldThr << 1; // 新阈值也 × 2
    }
    else if (oldThr > 0)
        // 构造时指定了 initialCapacity，threshold 已经被 tableSizeFor 计算过
        newCap = oldThr;
    else {
        // 无参构造，首次 put
        newCap = DEFAULT_INITIAL_CAPACITY; // 16
        newThr = (int)(DEFAULT_LOAD_FACTOR * DEFAULT_INITIAL_CAPACITY); // 12
    }

    if (newThr == 0) {
        float ft = (float)newCap * loadFactor;
        newThr = (newCap < MAXIMUM_CAPACITY && ft < MAXIMUM_CAPACITY ?
                  (int)ft : Integer.MAX_VALUE);
    }
    threshold = newThr;

    // ====== 第二部分：创建新数组 + 数据迁移 ======

    @SuppressWarnings({"rawtypes","unchecked"})
    Node<K,V>[] newTab = (Node<K,V>[])new Node[newCap];
    table = newTab;

    if (oldTab != null) {
        for (int j = 0; j < oldCap; ++j) {
            Node<K,V> e;
            if ((e = oldTab[j]) != null) {
                oldTab[j] = null; // 帮助 GC

                if (e.next == null)
                    // ① 单节点：直接重新计算下标
                    newTab[e.hash & (newCap - 1)] = e;

                else if (e instanceof TreeNode)
                    // ② 红黑树：拆分树
                    ((TreeNode<K,V>)e).split(this, newTab, j, oldCap);

                else {
                    // ③ 链表：拆分为低位链和高位链
                    Node<K,V> loHead = null, loTail = null; // 低位链（留在原位）
                    Node<K,V> hiHead = null, hiTail = null; // 高位链（移到 原位+oldCap）
                    Node<K,V> next;

                    do {
                        next = e.next;
                        // 关键判断：hash & oldCap
                        // 如果为 0 → 低位链（新下标 = j）
                        // 如果非 0 → 高位链（新下标 = j + oldCap）
                        if ((e.hash & oldCap) == 0) {
                            if (loTail == null)
                                loHead = e;
                            else
                                loTail.next = e;
                            loTail = e;
                        }
                        else {
                            if (hiTail == null)
                                hiHead = e;
                            else
                                hiTail.next = e;
                            hiTail = e;
                        }
                    } while ((e = next) != null);

                    if (loTail != null) {
                        loTail.next = null;
                        newTab[j] = loHead;
                    }
                    if (hiTail != null) {
                        hiTail.next = null;
                        newTab[j + oldCap] = hiHead;
                    }
                }
            }
        }
    }
    return newTab;
}
```

### 6.2 扩容时链表拆分的精髓

扩容后容量翻倍，每个桶的数据可能留在原位，也可能移到 `原位 + oldCap`。

**原理**：

```
扩容前：n = 16,  n-1 = 0b 0000 1111,  下标 = hash & 0b0000 1111
扩容后：n = 32,  n-1 = 0b 0001 1111,  下标 = hash & 0b0001 1111

区别只在于多了一位（第5位）参与运算。
如果 hash 的第5位为0 → 下标不变
如果 hash 的第5位为1 → 下标 = 原下标 + 16

而 hash 第5位是否为1，恰好等于 (hash & oldCap) != 0
```

**示例**：

```
hash1 = 0b xxxx 0000 aaaa  →  (hash1 & 16) == 0  →  低位链，留在桶 j
hash2 = 0b xxxx 0001 aaaa  →  (hash2 & 16) != 0  →  高位链，移到桶 j+16
```

这样就不需要重新计算每个节点的下标，只需一次位运算即可确定归属。

---

## 7. 树化与反树化

### 7.1 树化触发条件

```java
final void treeifyBin(Node<K,V>[] tab, int hash) {
    int n, index; Node<K,V> e;
    // 关键：数组长度 < 64 时，只扩容，不树化
    if (tab == null || (n = tab.length) < MIN_TREEIFY_CAPACITY)
        resize();
    else if ((e = tab[index = (n - 1) & hash]) != null) {
        // 将链表转为 TreeNode 双向链表
        TreeNode<K,V> hd = null, tl = null;
        do {
            TreeNode<K,V> p = replacementTreeNode(e, null);
            if (tl == null)
                hd = p;
            else {
                p.prev = tl;
                tl.next = p;
            }
            tl = p;
        } while ((e = e.next) != null);

        // 将双向链表转为红黑树
        if ((tab[index] = hd) != null)
            hd.treeify(tab);
    }
}
```

**双条件**：链表长度 ≥ 8 **且** 数组长度 ≥ 64 才真正树化，否则优先扩容。

### 7.2 为什么需要数组长度 ≥ 64 的限制？

- 数组太小时，哈希冲突本身就多，树化只是治标
- 扩容能让数据更分散，从根本上减少冲突
- 红黑树节点占用更多内存（TreeNode ≈ Node 的 2 倍），小数组时划不来

### 7.3 TreeNode 结构

```java
static final class TreeNode<K,V> extends LinkedHashMap.Entry<K,V> {
    TreeNode<K,V> parent;  // 红黑树父节点
    TreeNode<K,V> left;    // 左子节点
    TreeNode<K,V> right;   // 右子节点
    TreeNode<K,V> prev;    // 链表前驱（删除时需要）
    boolean red;           // 颜色
    // 继承自 Node：hash, key, value, next
}
```

TreeNode 同时维护了链表结构（next/prev）和树结构（parent/left/right），方便在树和链表之间转换。

### 7.4 反树化

扩容时，如果拆分后树的节点数 ≤ `UNTREEIFY_THRESHOLD`（6），则退回链表：

```java
// 在 TreeNode.split() 中
if (lc <= UNTREEIFY_THRESHOLD)
    tab[index] = loHead.untreeify(map);
else {
    tab[index] = loHead;
    if (hiHead != null)
        loHead.treeify(tab);
}
```

**为什么阈值是 6 而不是 8？**

避免频繁在链表和红黑树之间切换（边界震荡）。如果都是 8，一个桶在 7-9 之间反复增删就会反复转换。6 和 8 之间留了缓冲区。

---

## 8. get 流程

```java
public V get(Object key) {
    Node<K,V> e;
    return (e = getNode(hash(key), key)) == null ? null : e.value;
}

final Node<K,V> getNode(int hash, Object key) {
    Node<K,V>[] tab; Node<K,V> first, e; int n; K k;

    // ① table 不为空 且 桶不为空
    if ((tab = table) != null && (n = tab.length) > 0 &&
        (first = tab[(n - 1) & hash]) != null) {

        // ② 检查首节点
        if (first.hash == hash &&
            ((k = first.key) == key || (key != null && key.equals(k))))
            return first;

        // ③ 首节点不匹配，有后续节点
        if ((e = first.next) != null) {
            if (first instanceof TreeNode)
                // ④ 红黑树查找 O(log n)
                return ((TreeNode<K,V>)first).getTreeNode(hash, key);

            // ⑤ 链表遍历 O(n)
            do {
                if (e.hash == hash &&
                    ((k = e.key) == key || (key != null && key.equals(k))))
                    return e;
            } while ((e = e.next) != null);
        }
    }
    return null;
}
```

### 流程图

```
get(key)
  │
  ▼
计算 hash → 定位桶 (n-1)&hash
  │
  ▼
桶为空？──是──→ 返回 null
  │
  否
  ▼
首节点匹配？──是──→ 返回 value
  │
  否
  ▼
是红黑树？──是──→ O(log n) 树查找
  │
  否（链表）
  ▼
遍历链表 O(n) 查找
  ├─ 找到 → 返回 value
  └─ 未找到 → 返回 null
```

---

## 9. remove 流程

```java
public V remove(Object key) {
    Node<K,V> e;
    return (e = removeNode(hash(key), key, null, false, true)) == null ?
        null : e.value;
}

final Node<K,V> removeNode(int hash, Object key, Object value,
                           boolean matchValue, boolean movable) {
    Node<K,V>[] tab; Node<K,V> p; int n, index;

    // ① 定位桶
    if ((tab = table) != null && (n = tab.length) > 0 &&
        (p = tab[index = (n - 1) & hash]) != null) {

        Node<K,V> node = null, e; K k; V v;

        // ② 检查首节点
        if (p.hash == hash &&
            ((k = p.key) == key || (key != null && key.equals(k))))
            node = p;

        else if ((e = p.next) != null) {
            if (p instanceof TreeNode)
                // ③ 红黑树查找
                node = ((TreeNode<K,V>)p).getTreeNode(hash, key);
            else {
                // ④ 链表遍历
                do {
                    if (e.hash == hash &&
                        ((k = e.key) == key ||
                         (key != null && key.equals(k)))) {
                        node = e;
                        break;
                    }
                    p = e; // p 始终是 node 的前驱
                } while ((e = e.next) != null);
            }
        }

        // ⑤ 找到节点，执行删除
        if (node != null && (!matchValue || (v = node.value) == value ||
                             (value != null && value.equals(v)))) {
            if (node instanceof TreeNode)
                // 红黑树删除
                ((TreeNode<K,V>)node).removeTreeNode(this, tab, movable);
            else {
                // 链表删除
                if (node == p)
                    tab[index] = node.next; // 删除首节点
                else
                    p.next = node.next;     // 删除中间/尾部节点
            }
            ++modCount;
            --size;
            afterNodeRemoval(node); // LinkedHashMap 钩子
            return node;
        }
    }
    return null;
}
```

---

## 10. 遍历机制

### 10.1 核心遍历器

```java
abstract class HashIterator {
    Node<K,V> next;        // 下一个要返回的节点
    Node<K,V> current;     // 当前节点
    int expectedModCount;  // 期望的 modCount（fail-fast）
    int index;             // 当前桶下标

    HashIterator() {
        expectedModCount = modCount;
        Node<K,V>[] t = table;
        current = next = null;
        index = 0;
        // 找到第一个非空桶
        if (t != null && size > 0) {
            do {} while (index < t.length && (next = t[index++]) == null);
        }
    }

    public final boolean hasNext() {
        return next != null;
    }

    final Node<K,V> nextNode() {
        Node<K,V>[] t; Node<K,V> e = next;
        // fail-fast 检查
        if (modCount != expectedModCount)
            throw new ConcurrentModificationException();
        if (e == null)
            throw new NoSuchElementException();

        // 当前链表/树遍历完，找下一个非空桶
        if ((next = (current = e).next) == null && (t = table) != null) {
            do {} while (index < t.length && (next = t[index++]) == null);
        }
        return e;
    }
}
```

### 10.2 fail-fast 机制

遍历过程中如果 HashMap 发生结构修改（put 新 key、remove、resize），`modCount` 会改变，与 `expectedModCount` 不一致，抛出 `ConcurrentModificationException`。

**注意**：`put` 覆盖已有 key 的 value 不算结构修改，不会触发。

---

## 11. 序列化

```java
// 序列化时只保存真实数据，不保存空桶
private void writeObject(java.io.ObjectOutputStream s) throws IOException {
    int buckets = capacity();
    s.defaultWriteObject();
    s.writeInt(buckets);
    s.writeInt(size);
    // 只遍历非空节点
    for (Iterator<Map.Entry<K,V>> it = entrySet().iterator(); it.hasNext(); ) {
        Map.Entry<K,V> e = it.next();
        s.writeObject(e.getKey());
        s.writeObject(e.getValue());
    }
}

// 反序列化时重新构建 table
private void readObject(java.io.ObjectInputStream s)
    throws IOException, ClassNotFoundException {
    s.defaultReadObject();
    // 重建，重新 hash
    ...
}
```

**为什么不直接序列化 table 数组？** table 中大量空桶浪费空间，序列化只存有效数据更紧凑。

---

## 12. 线程安全问题

### 12.1 HashMap 本身不是线程安全的

以下场景可能导致问题：

| 场景 | 问题 |
|------|------|
| 多线程同时 put | 数据丢失（覆盖） |
| 多线程同时 put + resize | JDK 7 头插导致环链 → 死循环；JDK 8 尾插不会环链，但仍可能数据丢失 |
| 一个线程遍历，另一个线程修改 | ConcurrentModificationException |
| 多线程同时 resize | 扩容后数据丢失 |

### 12.2 线程安全替代方案

| 方案 | 特点 |
|------|------|
| `ConcurrentHashMap` | 推荐。分段锁（JDK 7）/ CAS + synchronized（JDK 8） |
| `Collections.synchronizedMap()` | 全局锁，性能差 |
| `Hashtable` | 全局锁，已过时，不推荐 |

### 12.3 JDK 7 扩容死循环复现

```
线程A 和 线程B 同时扩容，假设某桶有 A→B→null

线程A 执行到 e=A, next=B 被挂起
线程B 完成扩容，头插法导致链表反转 B→A→null

线程A 恢复执行：
1. 插入 A（头插）→ A→null
2. e=B, 插入 B（头插）→ B→A→null
3. e=A（从next取）, 插入 A（头插）→ A→B→A→B→... 环链！
```

JDK 8 尾插法保持了原有顺序，不会反转，避免了这个问题。但仍然不保证线程安全。

---

## 13. JDK 版本演进对比

| 特性 | JDK 7 | JDK 8 | JDK 11/17 |
|------|-------|-------|-----------|
| 链表插入方式 | 头插法 | 尾插法 | 尾插法 |
| 哈希冲突优化 | 纯链表 | 链表 + 红黑树 | 同 JDK 8 |
| hash 扰动 | 4 次移位 + 5 次异或 | 1 次移位 + 1 次异或 | 同 JDK 8 |
| 扩容迁移 | 重新计算下标 | 高低位拆分（e.hash & oldCap） | 同 JDK 8 |
| 初始化 | 构造时分配 table | 延迟到首次 put | 同 JDK 8 |
| 节点类型 | Entry<K,V> | Node<K,V> + TreeNode<K,V> | 同 JDK 8 |
| 树化阈值 | 无 | 8 | 同 JDK 8 |
| 反树化阈值 | 无 | 6 | 同 JDK 8 |
| forEach | 无 | 有默认方法 | 同 JDK 8 |

### JDK 7 的 hash 扰动（更复杂）

```java
// JDK 7
static int hash(int h) {
    h ^= (h >>> 20) ^ (h >>> 12);
    return h ^ (h >>> 7) ^ (h >>> 4);
}
```

JDK 8 认为一次扰动就够了，因为现代哈希算法（如 String 的 hash）本身分布已经比较均匀。

---

## 14. 常见面试题

### Q1: HashMap 的 key 可以是 null 吗？

可以。null key 的 hash 固定为 0，放在桶 0。但只能有一个 null key。

### Q2: HashMap 的 key 可以是可变对象吗？

技术上可以，但**强烈不推荐**。如果 key 放入后修改了影响 hashCode 的字段，将无法再 get 到该 entry，造成内存泄漏。

### Q3: HashMap 和 Hashtable 的区别？

| | HashMap | Hashtable |
|---|---------|-----------|
| 线程安全 | 否 | 是（synchronized） |
| null key/value | 允许 | 不允许（NPE） |
| 初始容量 | 16 | 11 |
| 扩容倍数 | 2 倍 | 2 倍 + 1 |
| 继承 | AbstractMap | Dictionary（已过时） |
| 性能 | 高 | 低（全局锁） |

### Q4: 为什么 String 适合做 HashMap 的 key？

1. **不可变**：放入后 hashCode 不会变
2. **hashCode 有缓存**：String 的 hash 字段是懒加载并缓存的，多次调用不重复计算
3. **equals 实现正确**：满足 equals 相等 → hashCode 相等的契约

### Q5: HashMap 的容量为什么必须是 2 的幂？

1. `(n-1) & hash` 等价于 `hash % n`（仅当 n 为 2 的幂时成立），位运算更快
2. 扩容时可以用 `hash & oldCap` 快速判断节点归属高位还是低位
3. `tableSizeFor` 保证构造时传入的容量也会被对齐

### Q6: put 时如果 key 已存在，会替换 value 吗？

会。除非使用 `putIfAbsent()`，它只在 value 为 null 时才替换。

### Q7: HashMap 的 size 和 capacity 的区别？

- **capacity**：桶数组的长度（始终为 2 的幂）
- **size**：实际键值对数量
- **threshold** = capacity × loadFactor，size 超过 threshold 触发扩容

### Q8: new HashMap(1000) 会创建多大的数组？

不会立即创建数组（延迟初始化）。首次 put 时，`threshold = tableSizeFor(1000) = 1024`，数组大小为 1024。

### Q9: 两个 key 的 hashCode 相同但 equals 不同，会怎样？

哈希冲突，它们会放在同一个桶的链表/红黑树中。get 时会通过 equals 逐个比较找到正确的 key。

### Q10: HashMap 是有序的吗？

不是。遍历顺序不保证与插入顺序一致。如果需要有序，使用：
- **LinkedHashMap**：维护插入顺序或访问顺序
- **TreeMap**：按 key 自然排序或自定义排序

---

## 附录：Node 核心数据结构

```java
static class Node<K,V> implements Map.Entry<K,V> {
    final int hash;       // key 的扰动后 hash 值
    final K key;
    V value;
    Node<K,V> next;       // 链表后继

    Node(int hash, K key, V value, Node<K,V> next) {
        this.hash = hash;
        this.key = key;
        this.value = value;
        this.next = next;
    }

    public final K getKey()   { return key; }
    public final V getValue() { return value; }
    public final String toString() { return key + "=" + value; }

    public final int hashCode() {
        return Objects.hashCode(key) ^ Objects.hashCode(value);
    }

    public final V setValue(V newValue) {
        V oldValue = value;
        value = newValue;
        return oldValue;
    }

    public final boolean equals(Object o) {
        if (o == this) return true;
        if (o instanceof Map.Entry) {
            Map.Entry<?,?> e = (Map.Entry<?,?>)o;
            return Objects.equals(key, e.getKey()) &&
                   Objects.equals(value, e.getValue());
        }
        return false;
    }
}
```

---

> 本文档基于 JDK 8 源码整理，涵盖核心流程、设计原理和面试高频考点。
> 建议配合实际调试，在关键方法打断点，观察数据变化，效果更佳。
