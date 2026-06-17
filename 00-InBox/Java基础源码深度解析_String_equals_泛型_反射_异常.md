# Java 基础源码深度解析 — String / equals / 泛型 / 反射 / 异常

> 基于 JDK 8+ 源码，从底层实现到设计哲学，系统拆解 Java 基础中最常被问到的五大主题。

---

## 目录

**Part 1 — String**
1. [String 不可变性与核心字段](#1-string-不可变性与核心字段)
2. [String 的构造方法](#2-string-的构造方法)
3. [String 核心方法源码](#3-string-核心方法源码)
4. [字符串常量池与 intern](#4-字符串常量池与-intern)
5. [StringBuilder 与 StringBuffer](#5-stringbuilder-与-stringbuffer)
6. [JDK 9+ compact strings](#6-jdk-9-compact-strings)

**Part 2 — equals 与 hashCode**
7. [Object.equals 源码与重写原则](#7-objectequals-源码与重写原则)
8. [String.equals 源码](#8-stringequals-源码)
9. [hashCode 契约与 String.hashCode 源码](#9-hashcode-契约与-stringhashcode-源码)
10. [HashMap 中 equals/hashCode 的配合](#10-hashmap-中-equalshashcode-的配合)
11. [Objects 工具类](#11-objects-工具类)

**Part 3 — 泛型**
12. [泛型的本质：类型擦除](#12-泛型的本质类型擦除)
13. [擦除的源码证据：桥方法](#13-擦除的源码证据桥方法)
14. [泛型与数组的协变问题](#14-泛型与数组的协变问题)
15. [泛型通配符与 PECS 原则](#15-泛型通配符与-pecs-原则)
16. [TypeToken 与 Super Type Token 模式](#16-typetoken-与-super-type-token-模式)

**Part 4 — 反射**
17. [Class 对象与类加载](#17-class-对象与类加载)
18. [反射 API 全景](#18-反射-api-全景)
19. [Constructor 反射源码](#19-constructor-反射源码)
20. [Method 反射源码](#20-method-反射源码)
21. [反射的性能开销与优化](#21-反射的性能开销与优化)
22. [setAccessible 与安全管理](#22-setaccessible-与安全管理)

**Part 5 — 异常**
23. [异常体系类图](#23-异常体系类图)
24. [Throwable 核心源码](#24-throwable-核心源码)
25. [try-with-resources 源码原理](#25-try-with-resources-源码原理)
26. [suppressed exceptions](#26-suppressed-exceptions)
27. [异常表与异常处理的字节码](#27-异常表与异常处理的字节码)

**Part 6 — 综合**
28. [常见面试题](#28-常见面试题)

---

# Part 1 — String

---

## 1. String 不可变性与核心字段

### JDK 8 源码

```java
public final class String
    implements java.io.Serializable, Comparable<String>, CharSequence {

    /** The value is used for character storage. */
    private final char value[];    // JDK 8: char[]
    // JDK 9+: private final byte[] value;  → 见第 6 章

    /** Cache the hash code for the string */
    private int hash;     // Default to 0，延迟计算

    /** use serialVersionUID from JDK 1.0.2 for interoperability */
    private static final long serialVersionUID = -6849794470754667710L;
}
```

### 不可变性的四层保证

```
① 类声明为 final          → 不能被子类覆盖方法
② value 数组声明为 final   → 引用不可变（不能指向新数组）
③ value 数组声明为 private → 外部无法直接访问
④ 所有修改方法都返回新对象  → 从不修改原 value

为什么 String 要设计为不可变？
  1. 字符串常量池：多个引用指向同一个 String 对象，可变会导致互相影响
  2. hashCode 缓存：不可变才能安全地延迟计算并缓存 hash
  3. 线程安全：不可变对象天然线程安全，不需要同步
  4. 安全性：String 常用作参数（类名、文件路径、网络连接），可变会被篡改
  5. 实现 String.hashCode() 的缓存优化
```

### 不可变的"漏洞"

```java
// 通过反射可以修改 String 内部的 value 数组！
String s = "Hello";
Field valueField = String.class.getDeclaredField("value");
valueField.setAccessible(true);
char[] value = (char[]) valueField.get(s);
value[0] = 'J';  // s 变成了 "Jello"

// 但这是非常规操作，实际开发中不要这样做
// JDK 9+ 的 byte[] + coder 机制让这种 hack 更复杂
```

---

## 2. String 的构造方法

### 核心构造方法源码

```java
// ① 从 char[] 构造（最基础）
public String(char value[]) {
    this.value = Arrays.copyOf(value, value.length);  // ★ 防御性拷贝
}

// ② 从 byte[] 构造（指定字符集）
public String(byte bytes[], int offset, int length, String charsetName)
        throws UnsupportedEncodingException {
    this.value = StringCoding.decode(charsetName, bytes, offset, length);
}

// ③ 从 StringBuilder 构造
public String(StringBuilder builder) {
    this.value = Arrays.copyOf(builder.getValue(), builder.length());
}

// ④ 从 StringBuffer 构造（synchronized 拷贝）
public String(StringBuffer buffer) {
    synchronized(buffer) {   // ★ 加锁读取，保证一致性
        this.value = Arrays.copyOf(buffer.getValue(), buffer.length());
    }
}

// ⑤ 原生 String 构造（直接共享数组，包私有）
// 这个构造方法在 JDK 8 中存在但被 @Deprecated
// JDK 9 移除
String(char[] value, boolean share) {
    // assert share : "unshared not supported";
    this.value = value;  // ★ 直接赋值，不做拷贝（性能优化）
}
```

### 面试陷阱：两种创建方式的区别

```java
String s1 = "hello";              // 字符串常量池
String s2 = new String("hello");  // 堆上新对象 + 常量池

// 内存布局：
// ┌──────────────┐
// │ 字符串常量池   │ → "hello" (char[])
// └──────────────┘
//        ↑
//        │ s1
//
// ┌──────────────┐      ┌──────────────┐
// │ 堆 - String  │ ──→  │ char[] "hello"│  ← s2 指向堆上的 String
// └──────────────┘      └──────────────┘
//                               ↑
//                        value 指向常量池的 char[]?
//                        不！new String() 会拷贝一份新的 char[]

// 源码证据：new String("hello") 调用的是
public String(String original) {
    this.value = original.value;   // ★ JDK 8 直接共享 char[]
    this.hash = original.hash;     // 共享 hash 缓存
}
// 注意：JDK 8 的 String(String) 不拷贝 value，因为 String 不可变，共享是安全的
// JDK 9+ 改为 this.coder = original.coder; this.value = original.value;
```

---

## 3. String 核心方法源码

### substring

```java
// JDK 6 的 substring（有内存泄漏风险）
public String substring(int beginIndex, int endIndex) {
    return new String(offset + beginIndex, endIndex - beginIndex, value);
    // ★ 共享原 char[]，只改 offset 和 count
    // 问题：一个大字符串截取一个小子串，大 char[] 无法被 GC
}

// JDK 7+ 的 substring（修复了内存泄漏）
public String substring(int beginIndex, int endIndex) {
    int subLen = endIndex - beginIndex;
    // ...
    return new String(value, beginIndex, subLen);
    // ★ 创建新 char[]，不共享原数组
}

// String(char[], offset, count) 的实现
public String(char value[], int offset, int count) {
    // 边界检查 ...
    this.value = Arrays.copyOfRange(value, offset, offset + count);
    // ★ 拷贝！不再共享原数组
}
```

### indexOf

```java
// 简化版 indexOf(char, int)
public int indexOf(int ch, int fromIndex) {
    final char value[] = this.value;   // 局部变量，避免 getfield
    final int max = value.length;
    if (fromIndex < 0) fromIndex = 0;
    // ...
    for (int i = fromIndex; i < max; i++) {
        if (value[i] == ch) {
            return i;                  // 朴素遍历，O(n)
        }
    }
    return -1;
}

// ★ JDK 没有在 String.indexOf 中使用 KMP / Boyer-Moore
// 原因：短字符串朴素算法更快（无预处理开销）
// 长字符串搜索建议用 Pattern（正则）或手动实现 BM
```

### concat

```java
public String concat(String str) {
    int otherLen = str.length();
    if (otherLen == 0) {
        return this;                    // ★ 空字符串直接返回 this
    }
    int len = value.length;
    char buf[] = Arrays.copyOf(value, len + otherLen);
    str.getChars(buf, len);            // 把 str 追加到 buf 末尾
    return new String(buf, true);      // 包私有构造，直接共享 buf
}
```

### replace

```java
public String replace(char oldChar, char newChar) {
    if (oldChar != newChar) {
        char[] val = value;   // 局部变量优化
        int len = val.length;
        int i = -1;
        // 先找到第一个匹配的位置
        while (++i < len) {
            if (val[i] == oldChar) break;
        }
        if (i < len) {
            char buf[] = new char[len];
            for (int j = 0; j < i; j++) {
                buf[j] = val[j];       // 拷贝不匹配的前半段
            }
            while (i < len) {
                char c = val[i];
                buf[i] = (c == oldChar) ? newChar : c;  // 逐字符替换
                i++;
            }
            return new String(buf, true);
        }
    }
    return this;   // ★ 没有匹配或 old==new，直接返回 this
}
```

---

## 4. 字符串常量池与 intern

### intern 源码

```java
/**
 * Returns a canonical representation for the string object.
 * <p>
 * A pool of strings, initially empty, is maintained privately by the
 * class {@code String}.
 * <p>
 * When the intern method is invoked, if the pool already contains a
 * string equal to this {@code String} object as determined by
 * the {@link #equals(Object)} method, then the string from the pool is
 * returned. Otherwise, this {@code String} object is added to the
 * pool and a reference to this {@code String} object is returned.
 */
public native String intern();
```

### intern 的 JVM 实现

```cpp
// hotspot/share/classfile/stringTable.cpp 简化逻辑

oop StringTable::intern(Handle string_or_null, jchar* chars, int length, TRAPS) {
    // ① 计算哈希
    unsigned int hash = java_lang_String::hash_code(chars, length);

    // ② 在 StringTable 中查找
    oop found = lookup(chars, length, hash);
    if (found != NULL) {
        return found;         // 常量池中已存在，直接返回
    }

    // ③ 不存在，创建新 String 对象并放入 StringTable
    Handle string;
    if (string_or_null.is_null()) {
        string = java_lang_String::create_from_unicode(chars, length, CHECK_NULL);
    } else {
        string = string_or_null;
    }
    add(string, hash);        // 加入 StringTable（全局哈希表）

    return string();
}
```

### 经典面试题

```java
String s1 = new String("he") + new String("llo");
// 上面这行创建了几个对象？
// ① 常量池 "he"
// ② 堆上 String("he")
// ③ 常量池 "llo"
// ④ 堆上 String("llo")
// ⑤ StringBuilder（编译器优化 + 变为 StringBuilder.append）
// ⑥ 堆上 String "hello"（StringBuilder.toString 生成）
// 注意：toString 生成的 "hello" 不在常量池中！
// → 共 5~6 个对象（取决于 StringBuilder 实现细节）

s1.intern();
// 将 s1 指向的 "hello" 放入常量池
// JDK 6：复制一份到 PermGen 常量池
// JDK 7+：常量池在堆中，直接记录 s1 的引用（不需要拷贝）

String s2 = "hello";
System.out.println(s1 == s2);
// JDK 6:  false（s1 在堆，s2 在 PermGen）
// JDK 7+: true （s2 指向常量池中的引用，就是 s1）
```

### StringTable 的位置变化

```
JDK 6：               JDK 7+：
┌─────────────┐      ┌─────────────────────┐
│   PermGen    │      │       Heap          │
│  ┌────────┐ │      │  ┌───────────────┐  │
│  │String  │ │      │  │  StringTable  │  │
│  │Table   │ │      │  │  (HashMap)    │  │
│  └────────┘ │      │  └───────────────┘  │
│  容易 OOM   │      │  受 GC 管理，空间更大  │
└─────────────┘      └─────────────────────┘

JDK 7 的好处：
  ① 字符串常量池移到堆中，不再受 PermGen 大小限制
  ② intern 可以直接存堆上引用，不需要拷贝
  ③ 常量池中的字符串也能被 GC 回收
```

---

## 5. StringBuilder 与 StringBuffer

### 继承关系

```
┌───────────────────┐
│  AbstractStringBuilder │  ← 核心实现
│  (包私有)             │
│  char[] value         │
│  int count            │
└─────────┬─────────┘
          │ extends
    ┌─────┴──────┐
    │            │
┌───┴────┐  ┌───┴────────┐
│StringBuilder│  │StringBuffer │
│ 非线程安全  │  │ synchronized│
│ JDK 1.5    │  │ JDK 1.0     │
└────────────┘  └─────────────┘
```

### 核心源码：append 与扩容

```java
// AbstractStringBuilder.append(String)
public AbstractStringBuilder append(String str) {
    if (str == null)
        return appendNull();
    int len = str.length();
    ensureCapacityInternal(count + len);  // ★ 确保容量
    str.getChars(0, len, value, count);   // 拷贝到 value 末尾
    count += len;
    return this;
}

// 扩容逻辑
private void ensureCapacityInternal(int minimumCapacity) {
    if (minimumCapacity - value.length > 0)
        expandCapacity(minimumCapacity);
}

void expandCapacity(int minimumCapacity) {
    int newCapacity = value.length * 2 + 2;   // ★ 新容量 = 旧容量 × 2 + 2
    if (newCapacity - minimumCapacity < 0)
        newCapacity = minimumCapacity;          // 仍不够就用所需容量
    if (newCapacity < 0) { /* overflow check */ }
    value = Arrays.copyOf(value, newCapacity);  // 拷贝到新数组
}
```

### StringBuffer 的 synchronized

```java
// StringBuffer 的所有公开方法都加了 synchronized
@Override
public synchronized StringBuffer append(String str) {
    toStringCache = null;   // ★ 清除 toString 缓存
    super.append(str);
    return this;
}

@Override
public synchronized String toString() {
    if (toStringCache == null) {
        toStringCache = Arrays.copyOfRange(value, 0, count);
    }
    return new String(toStringCache, true);
}
```

### 性能对比

```java
// ① String 拼接（每次都创建新对象）
String s = "";
for (int i = 0; i < 10000; i++) {
    s += i;   // 每次循环：new StringBuilder().append(i).toString()
}             // 创建 10000 个 StringBuilder + 10000 个 String

// ② StringBuilder 拼接（同一个对象）
StringBuilder sb = new StringBuilder();
for (int i = 0; i < 10000; i++) {
    sb.append(i);   // 只有一个 StringBuilder，自动扩容
}
String result = sb.toString();

// ③ StringBuffer 拼接（同 StringBuilder，但每次 append 都加锁）
StringBuffer sbf = new StringBuffer();
for (int i = 0; i < 10000; i++) {
    sbf.append(i);   // synchronized 开销
}

// 性能：StringBuilder >> StringBuffer >> String 拼接
```

---

## 6. JDK 9+ compact strings

### 设计动机

```
JDK 8 的 String 内部是 char[]，每个字符占 2 字节
但大多数字符串是 LATIN-1（ASCII），只需要 1 字节
→ 浪费了 50% 的内存

JDK 9 的改进：
  根据 String 内容动态选择编码：
  - LATIN-1（纯 ASCII）→ byte[]，每字符 1 字节
  - UTF-16（含中文等多字节字符）→ byte[]，每字符 2 字节
```

### JDK 9+ 源码

```java
public final class String implements java.io.Serializable, Comparable<String>, CharSequence {

    private final byte[] value;   // ★ 不再是 char[]

    /**
     * The identifier of the encoding used to encode the bytes in
     * {@code value}. Supported values are LATIN1 and UTF16.
     */
    private final byte coder;     // ★ 编码标识

    static final byte LATIN1 = 0;
    static final byte UTF16  = 1;

    // 判断是否使用压缩存储
    static final boolean COMPACT_STRINGS;
    static {
        COMPACT_STRINGS = true;   // 默认开启
    }

    // 长度计算
    public int length() {
        return value.length >> coder;   // LATIN1: >>0, UTF16: >>1
    }

    // charAt
    public char charAt(int index) {
        if (isLatin1()) {
            return StringLatin1.charAt(value, index);  // 直接取 byte
        } else {
            return StringUTF16.charAt(value, index);   // 取两个 byte
        }
    }
}
```

### 内存节省效果

```
示例："Hello World"
  JDK 8:  char[11] → 22 字节 + 对象头
  JDK 9:  byte[11] + coder=0 → 12 字节 + 对象头
  节省：约 45%

示例："你好世界"
  JDK 8:  char[4] → 8 字节
  JDK 9:  byte[8] + coder=1 → 9 字节
  差异：多 1 字节（coder），基本持平

→ 对 LATIN-1 字符串效果显著，对中文等 UTF-16 字符串影响不大
→ 整体堆内存占用可降低 10%~15%（大多数字符串是 LATIN-1）
```

---

# Part 2 — equals 与 hashCode

---

## 7. Object.equals 源码与重写原则

### Object.equals 源码

```java
// java.lang.Object
public boolean equals(Object obj) {
    return (this == obj);   // ★ 默认就是 ==，比较引用地址
}
```

### 重写 equals 的标准模板

```java
// 以 Person 为例
public class Person {
    private String name;
    private int age;

    @Override
    public boolean equals(Object o) {
        // ① 自反性：x.equals(x) == true
        if (this == o) return true;

        // ② null 检查 + 类型检查
        if (o == null || getClass() != o.getClass()) return false;

        // ③ 类型转换
        Person person = (Person) o;

        // ④ 逐字段比较
        return age == person.age && Objects.equals(name, person.name);
    }

    // ★ 必须同时重写 hashCode！
    @Override
    public int hashCode() {
        return Objects.hash(age, name);
    }
}
```

### equals 的五大契约

```
自反性：   x.equals(x) == true
对称性：   x.equals(y) ↔ y.equals(x)
传递性：   x.equals(y) && y.equals(z) → x.equals(z)
一致性：   多次调用结果不变（字段不变的前提下）
非空性：   x.equals(null) == false
```

### 常见违反对称性的例子

```java
// 错误示范：IgnoreCaseString 与 String 的 equals
public class IgnoreCaseString {
    private String s;

    @Override
    public boolean equals(Object o) {
        if (o instanceof IgnoreCaseString) {
            return s.equalsIgnoreCase(((IgnoreCaseString) o).s);
        }
        if (o instanceof String) {
            return s.equalsIgnoreCase((String) o);  // 与 String 互通
        }
        return false;
    }
}

// 问题：
IgnoreCaseString ics = new IgnoreCaseString("Hello");
String s = "hello";
ics.equals(s) → true    // IgnoreCaseString 能识别 String
s.equals(ics) → false   // String 不认识 IgnoreCaseString → 违反对称性！
```

---

## 8. String.equals 源码

```java
// java.lang.String
public boolean equals(Object anObject) {
    if (this == anObject) {              // ① 同一对象，直接返回 true
        return true;
    }
    if (anObject instanceof String) {    // ② 类型检查
        String anotherString = (String) anObject;
        int n = value.length;
        if (n == anotherString.value.length) {   // ③ 先比长度
            char v1[] = value;
            char v2[] = anotherString.value;
            int i = 0;
            while (n-- != 0) {                   // ④ 逐字符比较
                if (v1[i] != v2[i])
                    return false;
                i++;
            }
            return true;
        }
    }
    return false;
}

// JDK 9+ 版本
public boolean equals(Object anObject) {
    if (this == anObject) return true;
    if (anObject instanceof String) {
        String anotherString = (String) anObject;
        if (coder() == anotherString.coder()) {   // ★ 先比编码
            return StringLatin1.equals(value, anotherString.value)
                || StringUTF16.equals(value, anotherString.value);
        }
    }
    return false;
    // 不同编码（LATIN1 vs UTF16）直接返回 false → 长度就不可能相等
}
```

### String 的比较方法全家福

| 方法 | 比较方式 | 用途 |
|------|---------|------|
| `equals` | 逐字符精确比较 | 判断内容相等 |
| `equalsIgnoreCase` | 忽略大小写 | 不区分大小写的比较 |
| `compareTo` | 字典序比较 | 排序 |
| `contentEquals` | 与任何 CharSequence 比较 | 更通用的内容比较 |
| `regionMatches` | 局部比较 | 子串匹配 |

---

## 9. hashCode 契约与 String.hashCode 源码

### hashCode 的三大契约

```
① 一致性：同一对象多次调用 hashCode 必须返回同一整数（equals 比较的信息不变）
② equals 相等 → hashCode 必须相等
③ hashCode 相等 → equals 不一定相等（允许碰撞）

违反契约 ② 的后果：
  两个 equals 相等的对象 hash 不同 → 在 HashMap 中分成两个桶 → get 找不到！
```

### String.hashCode 源码

```java
// java.lang.String
public int hashCode() {
    int h = hash;                          // 读取缓存
    if (h == 0 && value.length > 0) {      // 未计算且非空字符串
        char val[] = value;
        for (int i = 0; i < value.length; i++) {
            h = 31 * h + val[i];           // ★ 核心公式：h = s[0]*31^(n-1) + s[1]*31^(n-2) + ... + s[n-1]
        }
        hash = h;                          // 缓存
    }
    return h;
}
```

### 为什么选 31 作为乘数？

```
① 31 是质数 → 减少哈希碰撞
② 31 * i == (i << 5) - i → 可以用位运算优化
③ 实证：31 在常见字符串集上碰撞率低
④ 历史原因：String.hashCode 从 JDK 1.0 就用 31，改不了（兼容性）

碰撞演示：
  "Aa" 和 "BB" 的 hashCode 相同！
  'A' = 65, 'a' = 97  →  31*65 + 97 = 2112
  'B' = 66, 'B' = 66  →  31*66 + 66 = 2112
```

### hashCode 碰撞攻击

```
如果攻击者知道你用的是 HashMap + String.hashCode，
可以构造大量 hashCode 相同的字符串，让 HashMap 退化为链表：

  "AaAa", "BBBB", "AaBB", "BBAa" → hashCode 都是 2035074
  这些字符串的任意两两组合也相同

防护：
  JDK 7u6+ ：HashMap 使用 hash 扰动（二次哈希）+ 链表树化
  JDK 8+   ：链表长度 ≥ 8 且数组 ≥ 64 时自动树化为红黑树
  替代方案 ：使用 SecureRandom 初始化的 HashCode（如 IdentityHashMap）
```

---

## 10. HashMap 中 equals/hashCode 的配合

### 源码回顾

```java
// HashMap 的 getNode（get 操作的核心）
final Node<K,V> getNode(int hash, Object key) {
    Node<K,V>[] tab; Node<K,V> first, e; int n; K k;
    if ((tab = table) != null && (n = tab.length) > 0 &&
        (first = tab[(n - 1) & hash]) != null) {    // ① 定位桶

        if (first.hash == hash &&                    // ② 先比 hash
            ((k = first.key) == key ||               // ③ 再比引用
             (key != null && key.equals(k))))         // ④ 最后比 equals
            return first;

        while ((e = first.next) != null) {
            if (e.hash == hash &&
                ((k = e.key) == key || key.equals(k)))
                return e;
        }
    }
    return null;
}
```

### 只重写 equals 不重写 hashCode 的灾难

```java
public class BadKey {
    private String id;

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof BadKey)) return false;
        return Objects.equals(id, ((BadKey) o).id);
    }
    // ★ 没有 hashCode！用的是 Object 默认的内存地址哈希
}

BadKey k1 = new BadKey("A");
BadKey k2 = new BadKey("A");
map.put(k1, "value");

map.get(k2);   // → null！
// k1.equals(k2) == true，但 k1.hashCode() != k2.hashCode()
// 它们落在不同的桶里，永远找不到

// 正确做法：equals 和 hashCode 必须一起重写
```

---

## 11. Objects 工具类

```java
// java.util.Objects（JDK 7+）
public final class Objects {

    // 空安全的 equals
    public static boolean equals(Object a, Object b) {
        return (a == b) || (a != null && a.equals(b));
    }

    // 深度 equals（数组逐元素比较）
    public static boolean deepEquals(Object a, Object b) {
        if (a == b) return true;
        if (a == null || b == null) return false;
        // 数组分支...
        return a.equals(b);
    }

    // 哈希计算（可变参数）
    public static int hash(Object... values) {
        return Arrays.hashCode(values);
    }

    // 非 null 检查
    public static <T> T requireNonNull(T obj) {
        if (obj == null) throw new NullPointerException();
        return obj;
    }

    // 非 null 检查（带消息）
    public static <T> T requireNonNull(T obj, String message) {
        if (obj == null) throw new NullPointerException(message);
        return obj;
    }

    // JDK 9+：requireNonNullElse
    public static <T> T requireNonNullElse(T obj, T defaultObj) {
        return (obj != null) ? obj : requireNonNull(defaultObj, "defaultObj");
    }
}
```

---

# Part 3 — 泛型

---

## 12. 泛型的本质：类型擦除

### 编译前 vs 编译后

```java
// 编译前（源码）
public class Box<T> {
    private T value;

    public void set(T value) { this.value = value; }
    public T get() { return value; }
}

// 编译后（字节码，类型擦除）
public class Box {
    private Object value;           // T → Object

    public void set(Object value) { this.value = value; }
    public Object get() { return value; }
}
```

### 擦除规则

```
┌──────────────────────────────┬─────────────────────┐
│ 泛型类型                      │ 擦除后               │
├──────────────────────────────┼─────────────────────┤
│ T（无界类型参数）              │ Object              │
│ T extends Comparable<T>      │ Comparable           │
│ T extends Number             │ Number              │
│ List<String>                 │ List                │
│ Map<String, Integer>         │ Map                 │
│ T[]                          │ Object[]            │
│ List<String>[]               │ List[]              │
└──────────────────────────────┴─────────────────────┘
```

### 擦除的证据：反编译

```java
// 源码
List<String> list = new ArrayList<>();
list.add("hello");
String s = list.get(0);

// 字节码（javap -c）
   0: new           #2  // class java/util/ArrayList
   3: dup
   4: invokespecial #3  // Method java/util/ArrayList."<init>":()V
   7: astore_1
   8: aload_1
   9: ldc           #4  // String hello
  11: invokeinterface #5  // Method java/util/List.add:(Object;)Z  ← Object
  ...
  20: invokeinterface #6  // Method java/util/List.get:(I)Object   ← 返回 Object
  25: checkcast     #7  // class java/lang/String   ← 编译器插入的强制转换！
  28: astore_2
```

> `checkcast` 指令就是类型擦除后编译器自动插入的强制类型转换。

---

## 13. 擦除的源码证据：桥方法

### 问题场景

```java
class MyComparator implements Comparable<MyComparator> {
    @Override
    public int compareTo(MyComparator o) {
        return 0;
    }
}
```

### 编译器生成的桥方法

```java
// 擦除后 Comparable 的方法签名是 compareTo(Object)
// MyComparator 只实现了 compareTo(MyComparator)
// 类型系统需要一个 compareTo(Object) 的实现

// 编译器自动生成桥方法：
class MyComparator implements Comparable<MyComparator> {
    public int compareTo(MyComparator o) { return 0; }

    // ★ 桥方法（编译器生成）
    public int compareTo(Object o) {
        return compareTo((MyComparator) o);   // 强转后调用真正的方法
    }
}
```

### 反编译验证

```
$ javap -v MyComparator.class

  public int compareTo(MyComparator);
    descriptor: (LMyComparator;)I

  public int compareTo(java.lang.Object);
    descriptor: (Ljava/lang/Object;)I
    flags: ACC_BRIDGE, ACC_SYNTHETIC   ← 桥方法标志
    Code:
      0: aload_0
      1: aload_1
      2: checkcast     #2  // class MyComparator  ← 强转
      5: invokevirtual #3  // Method compareTo:(LMyComparator;)I
      8: ireturn
```

### 桥方法与泛型多态

```java
// 另一个经典例子：泛型继承
abstract class Processor<T> {
    abstract T process(T input);
}

class StringProcessor extends Processor<String> {
    @Override
    String process(String input) {
        return input.toUpperCase();
    }

    // 编译器生成桥方法：
    // Object process(Object input) {
    //     return process((String) input);
    // }
}

// 多态调用
Processor p = new StringProcessor();
p.process("hello");   // 调用的是桥方法 process(Object) → process(String)
```

---

## 14. 泛型与数组的协变问题

### 数组是协变的

```java
Object[] arr = new String[3];    // ✓ 编译通过
arr[0] = 123;                    // ✗ 运行时 ArrayStoreException

// 数组在运行时知道自己的元素类型，可以做检查
```

### 泛型不是协变的

```java
List<Object> list = new ArrayList<String>();  // ✗ 编译错误！

// 如果允许的话：
list.add(123);                // 往 String 列表里放 Integer
String s = list.get(0);      // ClassCastException!
```

### 泛型数组创建的限制

```java
// ✗ 不允许
new T[]();                    // 不能创建泛型数组
new List<String>[]();         // 不能创建参数化类型数组
new E[10];                    // 类型参数不能 new 数组

// ✓ 允许
new List<?>[10];              // 无界通配符数组
(List<String>[]) new List[10]; // 原生类型强转（有 unchecked 警告）

// 为什么不允许？
// 如果允许 List<String>[]：
List<String>[] stringLists = new List<String>[1];
Object[] objects = stringLists;             // 数组协变
objects[0] = Arrays.asList(42);             // 放入 List<Integer>
String s = stringLists[0].get(0);          // ClassCastException 但无法在数组层检查！
```

---

## 15. 泛型通配符与 PECS 原则

### 三种通配符

```
<? extends T>   上界通配符   → 只读（生产者）
<? super T>     下界通配符   → 只写（消费者）
<?>             无界通配符   → 只能读 Object
```

### PECS 原则（Producer Extends, Consumer Super）

```java
// 从 src 读（生产者）→ extends
// 往 dest 写（消费者）→ super

// Collections.copy 的签名
public static <T> void copy(
    List<? super T> dest,    // 消费者：只往里写
    List<? extends T> src    // 生产者：只从里读
) {
    for (int i = 0; i < src.size(); i++) {
        dest.set(i, src.get(i));
    }
}

// 为什么 dest 不能是 List<T>？
List<Object> dest = new ArrayList<>();
List<String> src = Arrays.asList("a", "b");
// 如果签名是 List<T> dest，推断 T=String，
// List<Object> 不是 List<String> 的子类型 → 编译错误！
// 用 <? super T> 后，T=String，List<Object> 是 List<? super String> 的子类型 ✓
```

### 通配符的捕获

```java
// 这个方法为什么能编译？
public static void swap(List<?> list, int i, int j) {
    // list.set(i, list.get(j));  ← 编译错误！不能往 <?> 写
    swapHelper(list, i, j);
}

// 通过辅助方法捕获通配符
private static <E> void swapHelper(List<E> list, int i, int j) {
    list.set(i, list.get(j));  // ✓ E 是具体类型，可以读写
}
```

---

## 16. TypeToken 与 Super Type Token 模式

### 问题：运行时获取泛型类型

```java
// 由于类型擦除，这样做拿不到泛型参数
List<String> list = new ArrayList<>();
// list.getClass() → ArrayList.class，拿不到 String

// 方案 1：TypeToken（Guava）
TypeToken<List<String>> typeToken = new TypeToken<List<String>>() {};
Type type = typeToken.getType();
// type → java.util.List<java.lang.String>  ← 拿到了完整泛型信息！
```

### 原理：利用类声明的泛型签名不会被擦除

```java
// 为什么能拿到泛型信息？
// JVM 规范：类文件的 Signature 属性保存了泛型签名
// Class.getGenericSuperclass() 可以读取父类的泛型参数

// TypeToken 的核心原理
abstract class TypeToken<T> {
    private final Type type;

    protected TypeToken() {
        // getGenericSuperclass() 返回的是 ParameterizedType
        // 包含了完整的泛型参数信息
        Type superclass = getClass().getGenericSuperclass();
        if (superclass instanceof ParameterizedType) {
            this.type = ((ParameterizedType) superclass).getActualTypeArguments()[0];
        } else {
            throw new RuntimeException("Missing type parameter");
        }
    }
}

// 使用
TypeToken<List<String>> token = new TypeToken<List<String>>() {};
// 创建了一个匿名子类
// 匿名子类的父类是 TypeToken<List<String>>
// 通过 getGenericSuperclass() 可以拿到 List<String> 这个完整类型
```

### Super Type Token 在 Gson 中的应用

```java
// Gson 反序列化 List
List<String> list = gson.fromJson(json, new TypeToken<List<String>>() {}.getType());

// Gson 源码中的 TypeToken
public class TypeToken<T> {
    final Type type;

    protected TypeToken() {
        this.type = ((ParameterizedType) getClass().getGenericSuperclass())
            .getActualTypeArguments()[0];
    }

    public Type getType() { return type; }
}
```

---

# Part 4 — 反射

---

## 17. Class 对象与类加载

### Class 对象的本质

```java
// 每个 .class 文件加载后都会创建一个唯一的 java.lang.Class 对象
// Class 对象是反射的入口

// 获取 Class 对象的 4 种方式
Class<?> c1 = String.class;                         // ① 类字面量
Class<?> c2 = "hello".getClass();                   // ② 对象的 getClass()
Class<?> c3 = Class.forName("java.lang.String");    // ③ 全限定名（最常用）
Class<?> c4 = Thread.currentThread().getContextClassLoader()
              .loadClass("java.lang.String");        // ④ 类加载器
```

### Class.forName 的源码

```java
// java.lang.Class
public static Class<?> forName(String className)
            throws ClassNotFoundException {
    Class<?> caller = Reflection.getCallerClass();
    return forName0(className, true, caller);    // ★ initialize=true
}

public static Class<?> forName(String name, boolean initialize,
                               ClassLoader loader)
            throws ClassNotFoundException {
    // ...
    return forName0(name, initialize, loader);   // ★ 可以控制是否初始化
}

private static native Class<?> forName0(String name, boolean initialize,
                                         ClassLoader loader,
                                         Class<?> caller)
    throws ClassNotFoundException;
```

```
forName vs loadClass 的区别：
  Class.forName("com.mysql.cj.jdbc.Driver")
    → 加载 + 初始化（执行 static 代码块）→ 注册 Driver

  ClassLoader.loadClass("com.mysql.cj.jdbc.Driver")
    → 加载 + 不初始化（不执行 static 代码块）→ 不注册 Driver

→ JDBC 注册驱动用 Class.forName，Spring 延迟加载用 loadClass
```

---

## 18. 反射 API 全景

```
Class 对象
  ├── 字段
  │   ├── getDeclaredField(String)     → 本类声明的字段（含 private）
  │   ├── getField(String)             → 本类 + 父类的 public 字段
  │   ├── getDeclaredFields()          → 本类所有声明字段
  │   └── getFields()                  → 本类 + 父类所有 public 字段
  │
  ├── 方法
  │   ├── getDeclaredMethod(String, Class<?>...) → 本类声明的方法
  │   ├── getMethod(String, Class<?>...)         → 本类 + 父类的 public 方法
  │   ├── getDeclaredMethods()                    → 本类所有声明方法
  │   └── getMethods()                            → 本类 + 父类所有 public 方法
  │
  ├── 构造方法
  │   ├── getDeclaredConstructor(Class<?>...) → 本类声明的构造方法
  │   ├── getConstructor(Class<?>...)         → 本类的 public 构造方法
  │   ├── getDeclaredConstructors()            → 本类所有构造方法
  │   └── getConstructors()                    → 本类所有 public 构造方法
  │
  └── 其他
      ├── getInterfaces()             → 实现的接口
      ├── getSuperclass()             → 父类
      ├── getAnnotations()            → 注解
      ├── isArray() / isEnum() / ...  → 类型判断
      └── newInstance()               → 创建实例（JDK 9 deprecated）
```

---

## 19. Constructor 反射源码

```java
// java.lang.reflect.Constructor

// newInstance 的核心逻辑
public T newInstance(Object... initargs)
    throws InstantiationException, IllegalAccessException,
           IllegalArgumentException, InvocationTargetException {

    // ① 权限检查
    if (!override) {
        if (!Reflection.quickCheckMemberAccess(clazz, modifiers)) {
            // 慢路径：调用安全管理层
            Reflection.ensureMemberAccess(
                caller, clazz, null, modifiers);
        }
    }

    // ② 枚举类检查
    if ((clazz.getModifiers() & Modifier.ENUM) != 0)
        throw new IllegalArgumentException("Cannot reflectively create enum objects");

    // ③ 获取 ConstructorAccessor（反射调用的真正实现）
    ConstructorAccessor ca = acquireConstructorAccessor();
    if (ca == null) {
        ca = generateConstructorAccessor();
    }

    // ④ 通过 ConstructorAccessor 调用
    return (T) ca.newInstance(initargs);
}
```

### ConstructorAccessor 的两种实现

```
① NativeConstructorAccessorImpl
   使用 JVM 的 native 方法分配对象 + 调用构造方法
   每次调用都要经过 JNI → 较慢

② GeneratedConstructorAccessorImpl（动态生成）
   ASM 动态生成字节码，直接 new + invokespecial
   生成后缓存 → 后续调用极快（接近直接调用）

切换策略：
  前 16 次（默认）用 Native 版本
  第 17 次调用后触发 Inflation → 生成字节码版本
  由 -Dsun.reflect.inflationThreshold=16 控制
```

---

## 20. Method 反射源码

```java
// java.lang.reflect.Method

public Object invoke(Object obj, Object... args)
    throws IllegalAccessException, IllegalArgumentException,
           InvocationTargetException {

    // ① 权限检查
    if (!override) {
        // 检查方法是否可访问
        // ...
    }

    // ② 获取 MethodAccessor
    MethodAccessor ma = methodAccessor;
    if (ma == null) {
        ma = acquireMethodAccessor();
    }

    // ③ 通过 MethodAccessor 调用
    return ma.invoke(obj, args);
}
```

### MethodAccessor 的 Inflation 机制

```
调用次数 ≤ inflationThreshold（默认 16）：
  → NativeMethodAccessorImpl
  → 使用 JVM native 方法调用
  → 每次调用都要经过 JNI 栈切换

调用次数 > inflationThreshold：
  → GeneratedMethodAccessor<N>
  → ASM 动态生成类，直接调用目标方法
  → 生成后缓存，后续调用接近直接调用的速度

// 生成的字节码大致等价于：
public Object invoke(Object obj, Object[] args) {
    TargetClass target = (TargetClass) obj;
    return target.targetMethod((String) args[0], (int) args[1]);
}
```

### Inflation 的源码

```java
// sun.reflect.NativeMethodAccessorImpl
class NativeMethodAccessorImpl extends MethodAccessorImpl {
    private int numInvocations;

    public Object invoke(Object obj, Object[] args) {
        // ★ Inflation 检查
        if (++numInvocations > ReflectionFactory.inflationThreshold()) {
            // 超过阈值，生成字节码版本
            MethodAccessor generated = generateMethodAccessor();
            // 替换 parent 的 methodAccessor
            setDelegate(generated);
            return generated.invoke(obj, args);
        }
        // 使用 native 调用
        return invoke0(method, obj, args);
    }

    private static native Object invoke0(Method m, Object obj, Object[] args);
}
```

---

## 21. 反射的性能开销与优化

### 性能对比

```java
// 测试：调用同一个方法 1000 万次

// ① 直接调用：              ~5 ms
// ② Method.invoke（首次）：  ~800 ms   ← native + 参数装箱 + 检查
// ③ Method.invoke（热身后）：~50 ms    ← GeneratedMethodAccessor
// ④ MethodHandle：          ~10 ms    ← JDK 7+，更接近直接调用

// 性能瓶颈分析：
//   a. 方法访问检查（每次 invoke 都做）
//   b. 参数装箱/拆箱（Object[] ↔ 基本类型）
//   c. JNI 开销（native 版本）
//   d. 自动拆箱可能抛异常
```

### 优化手段

```java
// ① setAccessible(true) → 跳过访问检查
Method method = clazz.getDeclaredMethod("targetMethod", String.class);
method.setAccessible(true);   // ★ 关闭访问控制检查，性能提升 20%~30%

// ② 缓存 Method 对象
// 错误：每次都 getDeclaredMethod → 反复查找 + 权限检查
// 正确：static final 缓存
private static final Method TARGET_METHOD;
static {
    try {
        TARGET_METHOD = TargetClass.class.getDeclaredMethod("targetMethod", String.class);
        TARGET_METHOD.setAccessible(true);
    } catch (NoSuchMethodException e) {
        throw new ExceptionInInitializerError(e);
    }
}

// ③ JDK 7+ MethodHandle（方法句柄）
MethodHandles.Lookup lookup = MethodHandles.lookup();
MethodHandle mh = lookup.findVirtual(TargetClass.class, "targetMethod",
    MethodType.methodType(void.class, String.class));
mh.invokeExact(target, "arg");   // 接近直接调用的性能

// ④ JDK 8+ Lambda Metafactory
// Spring Framework 的方案：用 Lambda 替代反射
// 代码略，核心是 MethodHandles.lambdaMetafactory()
```

---

## 22. setAccessible 与安全管理

```java
// java.lang.reflect.AccessibleObject
public class AccessibleObject implements AnnotatedElement {

    boolean override;   // ★ 是否跳过访问检查

    public void setAccessible(boolean flag) {
        // 安全检查：是否有 SuppressAccessChecks 权限
        SecurityManager sm = System.getSecurityManager();
        if (sm != null) {
            sm.checkPermission(ReflectPermission("suppressAccessChecks"));
        }
        setAccessible0(flag);
    }

    private void setAccessible0(boolean flag) {
        this.override = flag;
        // ...
    }
}
```

### JDK 9+ 模块系统的限制

```
JDK 9 引入模块系统（JPMS）后，即使 setAccessible(true)，
也可能因为模块的 opens 声明而被拒绝：

// 模块描述文件 module-info.java
module com.example {
    // 只对指定模块开放反射权限
    opens com.example.internal to com.example.test;
}

// 反射其他模块的非 opens 包中的类
// → InaccessibleObjectException

// 启动参数绕过
--add-opens java.base/java.lang=ALL-UNNAMED
--add-opens java.base/java.util=ALL-UNNAMED

// Spring / Hibernate 等框架大量使用此参数
```

---

# Part 5 — 异常

---

## 23. 异常体系类图

```
                        ┌───────────┐
                        │  Object   │
                        └─────┬─────┘
                              │ extends
                        ┌─────┴─────┐
                        │ Throwable  │
                        └─────┬─────┘
                              │
                 ┌────────────┴────────────┐
                 │                         │
           ┌─────┴──────┐          ┌───────┴──────┐
           │  Error     │          │  Exception   │
           │ (不可恢复)  │          │  (可恢复)     │
           └─────┬──────┘          └───────┬──────┘
                 │                         │
        ┌────────┼────────┐       ┌────────┼─────────┐
        │        │        │       │                  │
  ┌─────┴──┐ ┌──┴───┐ ┌──┴───┐ ┌─┴──────────┐ ┌───┴──────────┐
  │StackOver│ │OOM  │ │Linkage│ │RuntimeException│ │检查异常      │
  │flowError│ │Error │ │Error  │ │(非检查异常)    │ │(checked)    │
  └─────────┘ └──────┘ └──────┘ └──────┬───────┘ └──────────────┘
                                         │
                              ┌──────────┼──────────┐
                              │          │          │
                        ┌─────┴──┐ ┌────┴───┐ ┌────┴────┐
                        │NullPtr │ │IndexOut│ │ClassCast│
                        │Exception│ │OfBounds│ │Exception│
                        └────────┘ └────────┘ └─────────┘
```

### 检查异常 vs 非检查异常

```
检查异常（Checked Exception）：
  - 继承自 Exception（不包含 RuntimeException）
  - 编译器强制要求 try-catch 或 throws 声明
  - 例子：IOException, SQLException, ClassNotFoundException
  - 设计意图：调用者必须处理的异常情况

非检查异常（Unchecked Exception）：
  - 继承自 RuntimeException 或 Error
  - 编译器不强制要求处理
  - 例子：NullPointerException, ArrayIndexOutOfBoundsException
  - 设计意图：编程错误，不应该通过异常机制恢复
```

---

## 24. Throwable 核心源码

```java
public class Throwable implements Serializable {

    /** 具体的异常消息 */
    private String detailMessage;

    /** cause：异常链（JDK 1.4+ 引入） */
    private Throwable cause = this;   // ★ 默认是自身（表示没有独立 cause）

    /** 堆栈跟踪 */
    private StackTraceElement[] stackTrace = UNASSIGNED_STACK;

    /** 被抑制的异常（try-with-resources 产生） */
    private List<Throwable> suppressedExceptions = SUPPRESSED_SENTINEL;

    // ========== 构造方法 ==========

    public Throwable() {
        fillInStackTrace();   // ★ 捕获当前线程的堆栈
    }

    public Throwable(String message) {
        fillInStackTrace();
        detailMessage = message;
    }

    public Throwable(String message, Throwable cause) {
        fillInStackTrace();
        detailMessage = message;
        this.cause = cause;
    }

    public Throwable(Throwable cause) {
        fillInStackTrace();
        detailMessage = (cause == null ? null : cause.toString());
        this.cause = cause;
    }

    // ========== fillInStackTrace ==========

    /**
     * Fills in the execution stack trace.
     * This method records within this Throwable object
     * information about the current state of the stack frames.
     */
    public synchronized Throwable fillInStackTrace() {
        if (stackTrace != null) {
            fillInStackTrace(0);   // native 方法，获取 JVM 堆栈
            stackTrace = null;     // 置空，延迟解析
        }
        return this;
    }

    // ========== getStackTrace ==========

    public StackTraceElement[] getStackTrace() {
        return getOurStackTrace().clone();  // ★ 防御性拷贝
    }

    private synchronized StackTraceElement[] getOurStackTrace() {
        // 延迟初始化
        if (stackTrace == UNASSIGNED_STACK ||
            (stackTrace == null && backtrace != null)) {
            // 从 JVM 的 backtrace 转换为 StackTraceElement[]
            int depth = getStackTraceDepth();
            stackTrace = new StackTraceElement[depth];
            for (int i = 0; i < depth; i++)
                stackTrace[i] = getStackTraceElement(i);
        }
        return stackTrace;
    }
}
```

### 异常链（Chained Exceptions）

```java
// 典型用法：低层异常包装为高层异常
try {
    // 数据库操作
} catch (SQLException e) {
    throw new ServiceException("数据库操作失败", e);   // ← cause = e
}

// 解开异常链
Throwable t = exception;
while (t != null) {
    System.out.println(t.getClass() + ": " + t.getMessage());
    t = t.getCause();
}

// 或者用 JDK 封装的方法
for (Throwable t : exception.getStackTrace()) { /* ... */ }
```

### 性能提示：不需要堆栈时跳过 fillInStackTrace

```java
// 对于频繁抛出的异常，fillInStackTrace 开销很大
// 如果不需要堆栈信息，可以覆盖它

public class FastException extends RuntimeException {
    @Override
    public synchronized Throwable fillInStackTrace() {
        return this;   // ★ 跳过堆栈捕获，性能提升 100 倍+
    }
}

// 适用场景：流程控制中的异常（不推荐，但某些框架这样做）
// 如 JVMCI、Graal 等高性能场景
```

---

## 25. try-with-resources 源码原理

### 语法糖解密

```java
// 源码
try (FileInputStream fis = new FileInputStream("test.txt");
     BufferedReader br = new BufferedReader(new FileReader("test.txt"))) {
    // 使用资源
} catch (IOException e) {
    // 处理异常
}

// 编译后等价代码（反编译结果）
{
    FileInputStream fis = null;
    BufferedReader br = null;
    try {
        fis = new FileInputStream("test.txt");
        br = new BufferedReader(new FileReader("test.txt"));
        // 使用资源
    } catch (IOException e) {
        // 处理异常
    } finally {
        // ★ 注意：关闭顺序与声明顺序相反！
        if (br != null) {
            br.close();             // 可能抛异常
        }
        if (fis != null) {
            fis.close();            // 可能抛异常
        }
    }
}
```

### AutoCloseable 接口

```java
// java.lang.AutoCloseable（JDK 7+）
public interface AutoCloseable {
    void close() throws Exception;
}

// java.io.Closeable extends AutoCloseable
public interface Closeable extends AutoCloseable {
    void close() throws IOException;   // 缩小异常范围
}
```

### 带异常的 try-with-resources 编译细节

```java
// 源码
try (FileInputStream fis = new FileInputStream("test.txt")) {
    int data = fis.read();          // 可能抛 IOException-A
} catch (IOException e) {
    // ...
}

// 编译后的完整逻辑（简化版）
FileInputStream fis = new FileInputStream("test.txt");
Throwable primaryException = null;    // ★ 主异常
try {
    int data = fis.read();           // 可能抛出 IOException-A
} catch (Throwable t) {
    primaryException = t;            // 记住主异常
    throw t;
} finally {
    if (fis != null) {
        if (primaryException != null) {
            try {
                fis.close();         // close 可能抛 IOException-B
            } catch (Throwable closeException) {
                // ★ 主异常已经存在，close 异常作为 suppressed
                primaryException.addSuppressed(closeException);
            }
        } else {
            fis.close();             // 没有主异常，close 异常正常抛出
        }
    }
}
```

---

## 26. suppressed exceptions

### Throwable 中的 suppressed 管理源码

```java
// java.lang.Throwable

// 添加被抑制的异常
public final synchronized void addSuppressed(Throwable exception) {
    if (exception == this)
        throw new IllegalArgumentException("Self-suppression not permitted");
    if (exception == null)
        throw new NullPointerException;

    if (suppressedExceptions == SUPPRESSED_SENTINEL)
        suppressedExceptions = new ArrayList<>(1);

    suppressedExceptions.add(exception);
}

// 获取被抑制的异常
public final synchronized Throwable[] getSuppressed() {
    if (suppressedExceptions == SUPPRESSED_SENTINEL)
        return EMPTY_THROWABLE_ARRAY;
    return suppressedExceptions.toArray(new Throwable[0]);
}
```

### 实际场景

```java
// 资源关闭时的 suppressed 异常
static class Resource implements AutoCloseable {
    @Override
    public void close() {
        throw new RuntimeException("close exception");
    }
}

public static void main(String[] args) {
    try (Resource r = new Resource()) {
        throw new RuntimeException("business exception");  // 主异常
    } catch (RuntimeException e) {
        System.out.println("主异常: " + e.getMessage());
        // 输出：主异常: business exception

        for (Throwable suppressed : e.getSuppressed()) {
            System.out.println("被抑制: " + suppressed.getMessage());
            // 输出：被抑制: close exception
        }
    }
}
```

---

## 27. 异常表与异常处理的字节码

### 异常表

```java
// 源码
public static void demo() {
    try {
        riskyMethod();
    } catch (IOException e) {
        handleIO(e);
    } catch (Exception e) {
        handleGeneral(e);
    } finally {
        cleanup();
    }
}

// 字节码中的异常表（javap -v 输出）
// Exception table:
//    from    to  target  type
//       0     4      10  Class java/io/IOException
//       0     4      20  Class java/lang/Exception
//       0    30      38  any          ← finally
//      10    30      38  any          ← finally (catch 分支)
//      20    30      38  any          ← finally (catch 分支)

// 含义：
//   from=0, to=4:   监控字节码偏移 0~4（try 块）
//   target=10:       匹配时跳转到偏移 10（第一个 catch）
//   type=IOException: 只捕获 IOException
```

### finally 的字节码实现

```
finally 块会被编译器复制到每个可能的出口路径上：

  try 正常结束 → finally
  try 抛异常 → catch → finally
  try 抛异常（未捕获）→ finally → 重新抛出

这就解释了为什么 finally 总会执行（除非 JVM 退出或线程被杀），
也解释了为什么 finally 中的 return 会吞掉 try 中的异常。
```

### finally 吞异常的反例

```java
// 反例：finally 中的 return 会吞掉 try 中抛出的异常
public static int bad() {
    try {
        throw new RuntimeException("try exception");
    } finally {
        return 1;   // ★ 吞掉了 try 中的异常！
    }
}

// 字节码层面：
//   try: athrow → 被异常表捕获 → finally 块
//   finally 块中执行 ireturn(1)
//   athrow 被丢弃，方法正常返回 1
```

---

# Part 6 — 综合

---

## 28. 常见面试题

### Q1：String 为什么是不可变的？有什么好处？

```
不可变原因：
  ① final 类 → 不可继承
  ② final char[] value → 引用不可变
  ③ private → 外部无法访问
  ④ 所有修改方法返回新对象

好处：
  ① 字符串常量池安全（多个引用可共享同一对象）
  ② hashCode 可缓存（不可变才能安全缓存）
  ③ 天然线程安全
  ④ 安全性（类名、路径、URL 等参数不会被篡改）
```

### Q2：String s = new String("abc") 创建了几个对象？

```
最多 2 个：
  ① 常量池中的 "abc"（如果常量池中不存在）
  ② 堆上的 String 对象（new 创建）

最少 1 个：
  如果常量池中已有 "abc"，则只创建堆上的 String 对象

注意：JDK 8 的 String(String) 构造方法直接共享 value 数组，
不创建新的 char[]。JDK 9+ 共享 byte[]。
```

### Q3：equals 和 == 的区别？

```
==：
  - 基本类型：比较值
  - 引用类型：比较引用地址

equals：
  - Object 默认：和 == 一样比较引用
  - String/Integer 等：重写后比较内容

注意：
  - equals 相等 → hashCode 必须相等
  - hashCode 相等 → equals 不一定相等
```

### Q4：什么是泛型擦除？有什么影响？

```
泛型擦除：编译后泛型类型参数被替换为其上界（默认 Object）
影响：
  ① 运行时无法获取泛型类型（new T() 不行）
  ② 不能创建泛型数组（new T[] 不行）
  ③ 不能用 instanceof 检查泛型类型
  ④ 编译器自动插入 checkcast 强转
  ⑤ 编译器生成桥方法保证多态

但泛型签名保存在类文件的 Signature 属性中，
可以通过反射（ParameterizedType）获取 → TypeToken 模式
```

### Q5：什么是 PECS 原则？

```
Producer Extends, Consumer Super

<? extends T>：只读（从里面取数据）→ 生产者用 extends
<? super T>：  只写（往里面放数据）→ 消费者用 super

记忆口诀："如果你只需要从集合中获取类型 T，使用 ? extends T"
         "如果你只需要将类型 T 放入集合中，使用 ? super T"
         "如果你既要获取又要放入，不要使用通配符"
```

### Q6：反射的性能为什么差？怎么优化？

```
性能差的原因：
  ① 方法查找（每次 getDeclaredMethod 都要遍历）
  ② 访问控制检查（每次 invoke 都做权限检查）
  ③ 参数装箱/拆箱（Object[] ↔ 基本类型）
  ④ Native 调用开销（JNI 栈切换）
  ⑤ 无法被 JIT 内联

优化方案：
  ① 缓存 Method/Field 对象
  ② setAccessible(true) 跳过访问检查
  ③ 用 MethodHandle 替代反射
  ④ 用 LambdaMetafactory 生成动态调用点
  ⑤ 高频场景考虑代码生成（如 ASM/CGLIB）
```

### Q7：什么是桥方法？为什么需要它？

```
桥方法：编译器自动生成的方法，用于保证泛型擦除后的多态性。

场景 1：泛型接口实现
  Comparable<T> 擦除后变成 Comparable
  MyComparable implements Comparable<MyComparable>
  编译器生成桥方法：int compareTo(Object o) { return compareTo((MyComparable)o); }

场景 2：协变返回类型
  class Parent { Object foo() { return null; } }
  class Child extends Parent { String foo() { return ""; } }
  编译器生成桥方法：Object foo() { return foo(); /* 调用返回 String 的版本 */ }
```

### Q8：try-with-resources 的原理是什么？

```
语法糖，编译后转为 try-catch-finally：
  ① 声明的资源在 finally 中按逆序关闭
  ② 如果 try 块抛异常，close 也抛异常，
     close 异常通过 addSuppressed 附加到主异常上
  ③ 资源必须实现 AutoCloseable 接口
  ④ 关闭顺序与声明顺序相反（最后声明的最先关闭）
```

### Q9：Java 的异常体系是怎样的？Error 和 Exception 有什么区别？

```
Throwable 是所有异常的根类
  ├── Error：JVM 级别的严重问题，不应该被捕获
  │   例：StackOverflowError, OutOfMemoryError
  │
  └── Exception：应用程序可以处理的问题
      ├── RuntimeException：非检查异常，编译器不强制处理
      │   例：NullPointerException, ClassCastException
      │
      └── 其他 Exception：检查异常，编译器强制 try-catch 或 throws
          例：IOException, SQLException

Error vs Exception：
  - Error 不可恢复，Exception 可恢复
  - Error 不应该捕获，Exception 应该捕获处理
  - 两者都继承 Throwable，都可以 throw
```

### Q10：String 的 intern 方法在 JDK 6 和 JDK 7+ 有什么区别？

```
JDK 6：
  - 字符串常量池在 PermGen 中
  - intern 时：如果池中不存在，复制一份到 PermGen
  - 堆上的 String 和池中的 String 是不同的对象

JDK 7+：
  - 字符串常量池移到 Heap 中
  - intern 时：如果池中不存在，直接记录堆上 String 的引用
  - 堆上的 String 和池中的引用指向同一个对象

经典面试代码：
  String s1 = new String("he") + new String("llo");
  s1.intern();
  String s2 = "hello";
  s1 == s2 → JDK 6: false, JDK 7+: true
```

---

> 本文档覆盖 Java 基础中最核心的五大主题：String 的不可变设计与内存优化、equals/hashCode 的契约与实现、泛型擦除的底层机制、反射的 Inflation 性能模型、以及异常体系的字节码级实现。
> 每个主题都从"为什么这样设计"出发，配合 JDK 源码逐层拆解，建议按序阅读。
