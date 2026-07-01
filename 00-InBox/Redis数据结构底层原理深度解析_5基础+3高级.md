# Redis 数据结构底层原理深度解析
——5 种基础类型 + 3 种高级类型，从 redisObject 到编码转换

> **阅读目标**：不翻 Redis 源码，也能掌握所有数据结构的底层实现、编码转换规则、内存布局和优化策略。
>
> **前置知识**：C 语言基础（指针、结构体）、哈希表、跳表、压缩列表。

---

## 文档导航

```
┌─────────────────────────────────────────────────────┐
│          Redis 数据结构底层原理                    │
├─────────────────────────────────────────────────────┤
│  第一部分：对象系统（redisObject）                 │
│    1. redisObject 结构体                           │
│    2. 5 种基础类型 + 8 种编码                    │
│    3. 编码转换规则                                │
├─────────────────────────────────────────────────────┤
│  第二部分：5 种基础类型底层实现                    │
│    4. String（SDS）                               │
│    5. List（quicklist/listpack）                  │
│    6. Hash（listpack/dict）                       │
│    7. Set（intset/dict）                          │
│    8. ZSet（listpack/skiplist+dict）              │
├─────────────────────────────────────────────────────┤
│  第三部分：底层数据结构源码                        │
│    9. SDS（简单动态字符串）                       │
│   10. dict（哈希表）                              │
│   11. skiplist（跳表）                           │
│   12. intset（整数集合）                          │
│   13. listpack（紧凑列表，替代 ziplist）           │
│   14. quicklist（快速列表）                        │
├─────────────────────────────────────────────────────┤
│  第四部分：3 种高级类型底层实现                    │
│   15. Bitmap（位图）                              │
│   16. HyperLogLog（基数估算）                      │
│   17. Geo（地理位置）                             │
├─────────────────────────────────────────────────────┤
│  第五部分：内存优化与实战                         │
│   18. 编码选择参数详解                            │
│   19. 内存优化最佳实践                            │
│   20. 面试高频题                                  │
└─────────────────────────────────────────────────────┘
```

---

# 第一部分：对象系统（redisObject）

## 1. redisObject 结构体 —— 所有数据类型的"身份证"

Redis 所有键值对的值都是一个 `redisObject`，定义在 `server.h`：

```c
struct redisObject {
    unsigned type:4;        // 类型（5 种基础类型）
    unsigned encoding:4;     // 编码方式（8 种底层实现）
    unsigned lru:LRU_BITS;  // LRU 时间 / LFU 数据（24 bits）
    int refcount;            // 引用计数（内存共享）
    void *ptr;               // 指向底层数据结构的指针
};
```

**内存布局（共 16 字节）**：

```
┌──────────────────────────────────────────────────────────┐
│                  redisObject（16 bytes）                 │
├──────┬──────┬──────────────────────┬─────────┬────────┤
│type  │encod │ lru                  │refcount  │  ptr   │
│(4b)  │ing   │                      │ (4B)     │  (8B) │
│      │(4b)  │      (24b)           │           │        │
└──────┴──────┴──────────────────────┴─────────┴────────┘
```

### 1.1 type 字段（4 bits）—— 5 种基础类型

```c
#define OBJ_STRING     0    // String
#define OBJ_LIST       1    // List
#define OBJ_SET        2    // Set
#define OBJ_ZSET       3    // Sorted Set
#define OBJ_HASH       4    // Hash
```

**注意**：Redis 命令不区分编码，只区分 type。同一个 `TYPE` 命令返回的类型，底层可能是不同编码。

### 1.2 encoding 字段（4 bits）—— 8 种编码方式

```c
#define OBJ_ENCODING_RAW      0    // SDS 动态字符串
#define OBJ_ENCODING_INT      1    // long 类型整数（直接存在 ptr）
#define OBJ_ENCODING_HT       2    // dict（哈希表）
#define OBJ_ENCODING_ZIPLIST  3    // ziplist（已废弃，被 listpack 替代）
#define OBJ_ENCODING_LISTPACK 4    // listpack（紧凑列表，Redis 7+ 默认）
#define OBJ_ENCODING_INTSET   5    // intset（整数集合）
#define OBJ_ENCODING_SKIPLIST 6    // skiplist + dict（跳表 + 字典）
#define OBJ_ENCODING_QUICKLIST 7   // quicklist（快速列表）
#define OBJ_ENCODING_STREAM   8    // listpack（Stream 类型）
```

### 1.3 ptr 字段 —— 指向真实数据

`ptr` 的类型由 `encoding` 决定：

| encoding            | ptr 指向的类型                |
|---------------------|-------------------------------|
| `OBJ_ENCODING_INT`  | 直接存储 `long`（ptr 本身）  |
| `OBJ_ENCODING_RAW`  | `sdshdr*`（SDS 结构体指针）  |
| `OBJ_ENCODING_HT`   | `dict*`（哈希表指针）         |
| `OBJ_ENCODING_LISTPACK` | `unsigned char*`（listpack 指针） |
| `OBJ_ENCODING_INTSET`   | `intset*`（整数集合指针）     |
| `OBJ_ENCODING_SKIPLIST` | `zset*`（zset 结构体指针）    |
| `OBJ_ENCODING_QUICKLIST`| `quicklist*`（快速列表指针）   |

**关键优化**：当值是 `long` 类型整数时，`ptr` 直接存储整数值（指针压缩），节省内存：

```c
// 存储 long 整数时
if (len <= 20 && string2l(s, len, &value)) {
    // ptr 直接存储 value，不分配 SDS
    o->encoding = OBJ_ENCODING_INT;
    o->ptr = (void*)value;  // 直接把 long 存在指针位置
}
```

---

## 2. 5 种基础类型的编码组合

每种基础类型可以有多种编码方式，Redis 根据数据特征自动选择：

### 2.1 String 的 3 种编码

| 编码                | 触发条件                          | 底层结构      |
|---------------------|-----------------------------------|---------------|
| `OBJ_ENCODING_INT`  | 值可以表示为 64-bit 有符号整数   | `long`（ptr） |
| `OBJ_ENCODING_EMBSTR` | 字符串长度 ≤ 44 字节（Redis 7）| 嵌入式 SDS    |
| `OBJ_ENCODING_RAW` | 字符串长度 > 44 字节             | 独立 SDS      |

**EMBSTR vs RAW 的区别**（详见第 9 节）：
- `EMBSTR`：redisObject 和 SDS **连续存储**（一次内存分配）
- `RAW`：redisObject 和 SDS **分开存储**（两次内存分配）

### 2.2 List 的编码演进

| Redis 版本 | 编码 1       | 编码 2         | 说明                      |
|-------------|---------------|-----------------|---------------------------|
| < 3.2       | ziplist       | linkedlist      | 小数据用 ziplist，大数据用链表 |
| 3.2 ~ 6.x   | quicklist     | （单一编码）    | quicklist 统一替代         |
| 7.0+       | listpack      | quicklist       | 小数据用 listpack          |

**当前（Redis 7+）编码规则**：
- 元素数 ≤ `list-max-listpack-entries`（默认 512）且每个元素 ≤ `list-max-listpack-value`（默认 64） → `OBJ_ENCODING_LISTPACK`
- 否则 → `OBJ_ENCODING_QUICKLIST`

### 2.3 Hash 的 2 种编码

| 编码                      | 触发条件                                              | 底层结构  |
|---------------------------|-------------------------------------------------------|-----------|
| `OBJ_ENCODING_LISTPACK`   | 字段数 ≤ `hash-max-listpack-entries`（默认 128）且每个字段/值 ≤ `hash-max-listpack-value`（默认 64） | listpack  |
| `OBJ_ENCODING_HT`         | 不满足上述条件                                         | dict      |

### 2.4 Set 的 2 种编码

| 编码                      | 触发条件                                              | 底层结构  |
|---------------------------|-------------------------------------------------------|-----------|
| `OBJ_ENCODING_INTSET`     | 所有元素都是整数且元素数 ≤ `set-max-intset-entries`（默认 512） | intset    |
| `OBJ_ENCODING_HT`         | 不满足上述条件                                         | dict（value 为 NULL） |

### 2.5 ZSet 的 2 种编码

| 编码                      | 触发条件                                              | 底层结构              |
|---------------------------|-------------------------------------------------------|-----------------------|
| `OBJ_ENCODING_LISTPACK`   | 元素数 ≤ `zset-max-listpack-entries`（默认 128）且每个元素 ≤ `zset-max-listpack-value`（默认 64） | listpack（按 score 排序） |
| `OBJ_ENCODING_SKIPLIST`   | 不满足上述条件                                         | `skiplist + dict`     |

**ZSet 的 skiplist 编码** 实际是一个 `zset` 结构体，同时包含跳表和字典：

```c
typedef struct zset {
    dict *dict;          // member → score（O(1) 查分）
    zskiplist *zsl;     // 按 score 排序（范围查询）
} zset;
```

**为什么同时用跳表和字典？**
- 字典：O(1) 查找某个 member 的 score（`ZSCORE`）
- 跳表：O(log N) 范围查询（`ZRANGE`/`ZRANGEBYSCORE`）
- 空间共享：跳表和字典**共享 member 和 score 的内存**（不重复存储）

---

## 3. 编码转换规则与触发条件

Redis 在数据量增长时**自动转换编码**，这不是配置项，而是**硬编码在源码中的阈值**。

### 3.1 完整编码转换矩阵

```
String:
  INT（整数）→ 对字符串执行 APPEND → RAW
  EMBSTR（≤44B）→ 修改后长度仍 ≤44 → EMBSTR
  EMBSTR（≤44B）→ 修改后长度 >44 → RAW

List:
  listpack → 元素数 > list-max-listpack-entries → quicklist
  listpack → 任意元素 > list-max-listpack-value → quicklist

Hash:
  listpack → 字段数 > hash-max-listpack-entries → HT
  listpack → 任意字段/值 > hash-max-listpack-value → HT

Set:
  intset → 插入非整数元素 → HT
  intset → 元素数 > set-max-intset-entries → HT

ZSet:
  listpack → 元素数 > zset-max-listpack-entries → skiplist+dict
  listpack → 任意元素 > zset-max-listpack-value → skiplist+dict
```

### 3.2 查看编码方式

```bash
redis> SET msg "hello"
OK
redis> OBJECT ENCODING msg
"embstr"                    # ≤44 字节，嵌入式 SDS

redis> SET long "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaz"
OK
redis> OBJECT ENCODING long
"raw"                       # >44 字节，独立 SDS

redis> SADD nums 1 2 3
(integer) 3
redis> OBJECT ENCODING nums
"intset"                    # 全是整数，用 intset

redis> SADD nums "abc"
(integer) 1
redis> OBJECT ENCODING nums
"hashtable"                 # 插入非整数，转换为 HT
```

---

# 第二部分：5 种基础类型底层实现

## 4. String（字符串）—— SDS 简单动态字符串

### 4.1 SDS 结构体

Redis 不直接使用 C 字符串（以 `\0` 结尾的 char 数组），而是自己实现了 **SDS（Simple Dynamic String）**。

**SDS 结构（Redis 7，sds.h）**：

```c
struct __attribute__((__packed__)) sdshdr {
    uint8_t len;        // 已使用的字节数（Redis 7 优化为多种类型）
    uint8_t alloc;      // 分配的总字节数（不包括 header 和 \0）
    unsigned char flags; // 低 3 位表示类型（sdshdr5/8/16/32/64）
    char buf[];         // 柔性数组，实际存储字符串（末尾自动加 \0）
};
```

**Redis 7 的 5 种 SDS 类型**（根据字符串长度选择，节省 header 空间）：

| 类型        | 宏定义          | len/alloc 类型 | 最大支持长度 | header 大小 |
|-------------|-----------------|----------------|--------------|-------------|
| sdshdr5     | `SDS_TYPE_5`    | 无（存在 flags）| 2^5 - 1      | 1 byte      |
| sdshdr8     | `SDS_TYPE_8`    | uint8_t        | 2^8 - 1      | 3 bytes     |
| sdshdr16    | `SDS_TYPE_16`   | uint16_t       | 2^16 - 1     | 5 bytes     |
| sdshdr32    | `SDS_TYPE_32`   | uint32_t       | 2^32 - 1     | 9 bytes     |
| sdshdr64    | `SDS_TYPE_64`   | uint64_t       | 2^64 - 1     | 17 bytes    |

**内存布局**：

```
Redis 7 的 SDS（sdshdr8 示例，字符串 "Redis"）：

    ┌─────┬─────┬───────┬───────┬───────┬───────┬─────┐
    │ len │allo │flags  │  'R'  │  'e'  │  'd'  │ \0  │
    │(1B)│(1B) │(1B)   │       │       │       │(1B) │
    └─────┴─────┴───────┴───────┴───────┴───────┴─────┘
      ↑     ↑      ↑
     5     5      5           字符串内容（5 bytes）
     字节   字节   字节

buf 实际长度 = len + 1（\0）
```

### 4.2 SDS vs C 字符串

| 特性                 | C 字符串           | SDS                      |
|----------------------|---------------------|--------------------------|
| 获取长度              | O(n)（遍历到 \0）  | O(1)（len 字段）        |
| 缓冲区溢出            | 容易发生            | 不会（自动扩容）          |
| 修改 N 次内存分配次数 | 必定 N 次           | 最多 N 次（预分配）      |
| 二进制安全            | 否（不能存 \0）    | 是（用 len 判断结束）    |
| 兼容 C 字符串函数     | —                   | 是（buf 末尾自动加 \0）  |

### 4.3 SDS 预分配策略（空间换时间）

当 SDS 需要扩容时，Redis 采用**预分配**策略减少内存分配次数：

```c
// sds.c → sdsMakeRoomFor()
newlen = (len + addlen);
// 如果新长度 < 1MB，预分配 2 倍
if (newlen < SDS_MAX_PREALLOC)    // SDS_MAX_PREALLOC = 1024*1024 = 1MB
    newlen *= 2;
else
    // 如果新长度 ≥ 1MB，预分配 新长度 + 1MB
    newlen += SDS_MAX_PREALLOC;
```

**示例**：

```
初始：SDS 存储 "Hello"（len=5，alloc=5）
执行：APPEND s " World!!!!!"

第 1 次扩容：
  需要长度 = 5 + 10 = 15 < 1MB
  预分配 = 15 * 2 = 30
  结果：len=15，alloc=30

第 2 次扩容（假设追加到超过 1MB）：
  需要长度 = 1MB + 100
  预分配 = (1MB + 100) + 1MB = 2MB + 100
```

**惰性空间释放**：缩短字符串时，不立即释放内存，只修改 `len`（可供后续 APPEND 复用）：

```c
// sds.c → sdsclear()
void sdsclear(sds s) {
    sdssetlen(s, 0);  // 只修改 len = 0，不释放 buf
    s[0] = '\0';      // buf[0] = '\0'
}
// 内存没有释放，下次 APPEND 可以直接使用
```

### 4.4 EMBSTR 编码（嵌入式 SDS）

当字符串很短（≤ 44 字节）时，Redis 将 `redisObject` 和 `SDS` **连续存储**，减少一次内存分配和缓存不友好：

```
EMBSTR 内存布局（一次分配）：

    ┌──────────────────────────────────────────────────────┐
    │  redisObject（16B）  │  SDS header + buf（≤44B）    │
    └──────────────────────────────────────────────────────┘
    ↑                      ↑
    一次性 malloc          连续存储

RAW 内存布局（两次分配）：

    ┌─────────────────┐    ┌──────────────────────────┐
    │ redisObject(16B)│    │ SDS header + buf         │
    └─────────────────┘    └──────────────────────────┘
    ↑                      ↑
    第一次 malloc           第二次 malloc（不连续）
```

**为什么是 44 字节？**

```
redisObject: 16 bytes
SDS sdshdr8 header: 3 bytes（len + alloc + flags）
buf 末尾 \0: 1 byte
────────────────────────────
已用：16 + 3 + 1 = 20 bytes

Redis 对象最大分配：64 bytes（jemalloc 分配规格）
剩余给字符串：64 - 20 = 44 bytes
```

### 4.5 String 底层原理总结

```
┌──────────────────────────────────────────────────────────┐
│                      String 编码选择                      │
├──────────────────────────────────────────────────────────┤
│  值 = 整数且可以用 long 表示？                           │
│      YES → OBJ_ENCODING_INT（ptr 直接存值）              │
│      NO  ↓                                              │
│  字符串长度 ≤ 44 字节？                                  │
│      YES → OBJ_ENCODING_EMBSTR（连续存储）               │
│      NO  → OBJ_ENCODING_RAW（独立 SDS）                 │
└──────────────────────────────────────────────────────────┘
```

---

## 5. List（列表）—— quicklist + listpack

### 5.1 List 的演进历史

```
Redis 版本演进：

< 3.2：  ziplist  ←→  linkedlist
         （小数据）   （大数据）

3.2+：   ziplist  ←→  quicklist
         （小数据）   （大数据，统一编码）

7.0+：   listpack ←→  quicklist
         （小数据）   （大数据）
```

### 5.2 quicklist 结构体

`quicklist` 是 Redis 3.2 引入的	List 底层实现，它结合了 **ziplist 的内存连续** 和 **linkedlist 的插入高效**：

```c
typedef struct quicklist {
    quicklistNode *head;    // 头节点
    quicklistNode *tail;    // 尾节点
    unsigned long count;     // 所有 listpack 中的元素总数
    unsigned long len;      // quicklistNode 节点数
    int fill : QL_FILL_BITS;       // 每个节点最大大小（list-max-listpack-size）
    unsigned int compress : QL_COMP_BITS;  // 两端不压缩的节点数
    // ...
} quicklist;
```

**quicklistNode**（每个节点是一个 listpack）：

```c
typedef struct quicklistNode {
    struct quicklistNode *prev;  // 前驱
    struct quicklistNode *next;  // 后继
    unsigned char *entry;        // 指向 listpack（压缩列表）
    unsigned int sz;             // listpack 的字节大小
    unsigned int count : 16;     // listpack 中的元素个数
    unsigned int encoding : 2;   // 编码方式（RAW = 1, LZF = 2）
    unsigned int container : 2;  // 容器类型（NONE = 1, LISTPACK = 2）
    unsigned int recompress : 1; // 是否被压缩过（临时解压标记）
    unsigned int attempted_compress : 1; // 测试用
    unsigned int extra : 10;     // 预留位
} quicklistNode;
```

**内存布局**：

```
quicklist 内存布局：

    quicklist
    ┌─────────┬─────────┬──────────┬─────────┐
    │  head   │  tail   │  count   │   len    │
    │  (ptr)  │  (ptr)  │ (元素数) │ (节点数) │
    └────┬────┴────┬────┴──────────┴────┬────┘
         │         │                     │
         ▼         ▼                     ▼
    ┌────────┐ ┌────────┐         ┌────────┐
    │ Node 1 │→│ Node 2 │   ...   │ Node N │
    │(listpack│ │(listpack│         │(listpack│
    │  16KB) │ │  16KB) │         │  16KB) │
    └────────┘ └────────┘         └────────┘
         │             │                   │
         ▼             ▼                   ▼
    ┌──────────┐  ┌──────────┐      ┌──────────┐
    │[a,12,b,c]│  │[x,99,y,] │      │[p,1,q,2]│
    │  元素1~4  │  │  元素5~7  │      │ 元素N-2~N│
    └──────────┘  └──────────┘      └──────────┘
```

### 5.3 listpack（紧凑列表，Redis 7+ 替代 ziplist）

`listpack` 是 `ziplist` 的改进版，解决了 ziplist 的**级联更新问题**。

**ziplist 的级联更新问题**：
- ziplist 中每个 entry 的 `prev_entry_len` 字段（前一个 entry 的长度）占用 1 或 5 字节
- 如果前一个 entry 长度从 <254 变为 ≥254，当前 entry 的 `prev_entry_len` 需要从 1 字节扩展到 5 字节
- 这可能导致**连锁反应**：后续所有 entry 的 `prev_entry_len` 都需要更新

**listpack 的改进**：
- 去掉了 `prev_entry_len` 字段
- 每个 entry 自己记录自己的长度（`entry-len`）
- 遍历时通过 `entry-len` 向前计算前一个 entry 的位置（不需要 `prev_entry_len`）

**listpack entry 格式**：

```
┌──────────┬──────────────┬────────────┬──────────────┬──────┐
│ prevlen  │ encoding+data│ entry-len  │  backlen     │ ...  │
│（可选，   │ （数据）      │（本 entry  │（entry-len   │      │
│  某些实现 │              │  长度，    │  的长度，     │      │
│  保留）   │              │  1~5B）   │  用于反向遍历）│      │
└──────────┴──────────────┴────────────┴──────────────┴──────┘
```

**listpack vs ziplist 核心区别**：

| 特性               | ziplist                    | listpack                |
|--------------------|----------------------------|-------------------------|
| prev_entry_len      | 有（导致级联更新）         | 无                      |
| 遍历方向            | 只能正向（靠 prev_entry_len）| 正反双向               |
| 级联更新            | 有                         | 无                      |
| 内存效率            | 略高（无 entry-len）       | 略低（多了 entry-len）  |

### 5.4 List 核心操作源码

**LPUSH（头插）**：

```c
// t_list.c → pushGenericCommand()
void pushGenericCommand(redisClient *c, int where) {
    robj *lobj = lookupKeyWrite(c->db, c->argv[1]);
    
    // 如果列表不存在，创建 listpack 编码的列表
    if (lobj == NULL) {
        lobj = createListpackObject();
        dbAdd(c->db, c->argv[1], lobj);
    }
    
    // 逐个插入元素
    for (j = 2; j < c->argc; j++) {
        // listpack 编码：直接插入 listpack
        if (lobj->encoding == OBJ_ENCODING_LISTPACK) {
            lobj->ptr = listpackPush(lobj->ptr, ..., where);
            
            // 检查是否需要转换为 quicklist
            if (listpackLen(lobj->ptr) > server.list_max_listpack_entries)
                listTypeConvert(lobj, OBJ_ENCODING_QUICKLIST);
        }
        // quicklist 编码：插入 quicklist
        else {
            quicklistPush((quicklist*)lobj->ptr, ..., where);
        }
    }
}
```

**LINDEX（按索引访问）**：

```c
// 在 quicklist 中，LINDEX 需要遍历节点
// 时间复杂度：O(N)，N = 索引值
// 因为 quicklist 是双向链表，不支持 O(1) 随机访问

// t_list.c → listTypeIndex()
robj *listTypeIndex(robj *subject, long index) {
    if (subject->encoding == OBJ_ENCODING_LISTPACK) {
        // listpack：直接遍历 listpack 找到第 index 个 entry
        return listpackGetElement(subject->ptr, index, &vstr, &vlen);
    }
    else if (subject->encoding == OBJ_ENCODING_QUICKLIST) {
        // quicklist：先找到对应节点，再在该节点的 listpack 中查找
        quicklistEntry entry;
        quicklistIndex((quicklist*)subject->ptr, index, &entry);
        return createStringObject(entry.value, entry.sz);
    }
}
```

### 5.5 List 底层原理总结

```
┌──────────────────────────────────────────────────────────┐
│                    List 编码选择                         │
├──────────────────────────────────────────────────────────┤
│  元素数 ≤ list-max-listpack-entries（512）               │
│  AND 每个元素 ≤ list-max-listpack-value（64 字节）？      │
│      YES → OBJ_ENCODING_LISTPACK                        │
│      NO  → OBJ_ENCODING_QUICKLIST                      │
│                                                        │
│  quicklist 特点：                                       │
│  - 每个节点是一个 listpack（默认最大 8KB）               │
│  - 支持两端不压缩（compress 参数）                       │
│  - 插入/删除 O(1)（链表特性）                          │
│  - 按索引访问 O(N)（需要遍历节点）                       │
└──────────────────────────────────────────────────────────┘
```

---

## 6. Hash（哈希）—— listpack + dict

### 6.1 Hash 的 2 种编码

**listpack 编码**：
- 适用于字段少且字段名/值都短的 Hash
- 所有字段和值**连续存储**在一个 listpack 中

**HT（dict）编码**：
- 适用于字段多或字段名/值较长的 Hash
- 底层是 Redis 自己实现的**哈希表**（详见第 10 节）

### 6.2 listpack 编码的 Hash 存储格式

Hash 在 listpack 中**按插入顺序连续存储**键值对：

```
Hash {name: "Zhang", age: 30, city: "Beijing"} 的 listpack 存储：

    ┌──────────────────────────────────────────────────────┐
    │  [name]  [5]  [Zhang]  [age]  [2]  [30]  [city]  │
    │    ↑       ↑      ↑       ↑      ↑     ↑      ↑     │
    │  字段1   长度   值1    字段2  长度  值2   字段3    │
    │                      │
    │                      ▼                               │
    │             实际存储："name""5""Zhang"               │
    │             "age""2""30""city""7""Beijing"           │
    └──────────────────────────────────────────────────────┘
```

**HGET 的查找过程**（listpack 编码）：
1. 遍历 listpack，找到目标字段
2. 返回下一个 entry（即字段对应的值）
3. 时间复杂度：O(N)，N = 字段数

**为什么小 Hash 用 listpack 更高效？**
- 连续内存 → 缓存友好
- 无哈希冲突
- 节省 dict 的 table 数组和指针开销

### 6.3 HT（dict）编码的 Hash

当 Hash 不满足 listpack 条件时，转换为 **dict（哈希表）** 编码。

**dict 结构体**（详见第 10 节）：

```c
typedef struct dict {
    dictType *type;    // 类型特定函数（hashFunction、keyCompare 等）
    void *privdata;     // 私有数据
    dictht ht[2];      // 两个哈希表（ht[0] 日常使用，ht[1] rehash 时使用）
    long rehashidx;     // rehash 索引（-1 表示不在 rehash）
    unsigned long iterators; // 正在运行的迭代器数量
} dict;
```

**HSET 的底层调用**：

```c
// t_hash.c → hashTypeSet()
int hashTypeSet(robj *o, sds field, sds value) {
    // listpack 编码
    if (o->encoding == OBJ_ENCODING_LISTPACK) {
        // 查找 field 是否已存在
        if (listpackFind(o->ptr, field, sdslen(field), &pos)) {
            // 已存在：删除旧值，插入新值
            listpackDelete(o->ptr, pos);
            listpackInsert(o->ptr, pos, value, sdslen(value));
        } else {
            // 不存在：在末尾追加
            o->ptr = listpackAppend(o->ptr, field, sdslen(field));
            o->ptr = listpackAppend(o->ptr, value, sdslen(value));
        }
        
        // 检查是否需要转换
        if (listpackLen(o->ptr) > server.hash_max_listpack_entries)
            hashTypeConvertListpack(o, OBJ_ENCODING_HT);
    }
    // HT 编码
    else if (o->encoding == OBJ_ENCODING_HT) {
        dictEntry *de = dictFind(o->ptr, field);
        if (de) {
            // 已存在：覆盖旧值
            decrRefCount(dictGetVal(de));
            dictSetVal(o->ptr, de, value);
        } else {
            // 不存在：插入新键值对
            dictAdd(o->ptr, field, value);
        }
    }
}
```

### 6.4 Hash 底层原理总结

```
┌──────────────────────────────────────────────────────────┐
│                    Hash 编码选择                         │
├──────────────────────────────────────────────────────────┤
│  字段数 ≤ hash-max-listpack-entries（128）               │
│  AND 每个字段名 ≤ hash-max-listpack-value（64 字节）     │
│  AND 每个值 ≤ hash-max-listpack-value（64 字节）？        │
│      YES → OBJ_ENCODING_LISTPACK                        │
│      NO  → OBJ_ENCODING_HT（dict）                     │
│                                                        │
│  查找效率：                                             │
│  - listpack：O(N) 遍历（N = 字段数，小数据快）          │
│  - HT：O(1) 哈希查找（大数据快）                        │
└──────────────────────────────────────────────────────────┘
```

---

## 7. Set（集合）—— intset + dict

### 7.1 Set 的 2 种编码

**intset 编码**：
- 所有元素都是整数
- 元素数 ≤ `set-max-intset-entries`（默认 512）
- 底层是**整数集合**（详见第 12 节）

**HT（dict）编码**：
- 不满足上述条件
- 底层是**哈希表**，value 为 NULL（只关心 key 是否存在）

### 7.2 intset 编码的 Set

**intset 结构体**：

```c
typedef struct intset {
    uint32_t encoding;   // 编码方式（INTSET_ENC_INT16/32/64）
    uint32_t length;     // 元素个数
    int8_t contents[];   // 柔性数组，按值从小到大排序存储
} intset;
```

**特点**：
- **有序存储**：插入时保持升序（二分查找 + 插入）
- **升级机制**：当插入更大范围的整数时，自动升级 encoding
- **不支持降级**：升级后不会降级

**intset 的升级过程**（源码 `intset.c → intsetUpgradeAndAdd()`）：

```c
static intset *intsetUpgradeAndAdd(intset *is, int64_t value) {
    uint8_t curenc = intrev32ifbe(is->encoding);  // 当前编码
    uint8_t newenc = (curenc == INTSET_ENC_INT16) ? INTSET_ENC_INT32 :
                    (curenc == INTSET_ENC_INT32) ? INTSET_ENC_INT64 :
                    INTSET_ENC_INT64;  // 已经是最大，不应该到这里
    
    // 1. 设置新编码
    is->encoding = newenc;
    
    // 2. 重新分配内存（每个元素变大）
    is = intsetResize(is, intrev32ifbe(is->length), newenc);
    
    // 3. 从后向前迁移数据（避免覆盖）
    while (length--)
        _intsetSet(is, length, _intsetGet(is, length, curenc), newenc);
    
    // 4. 插入新元素
    if (value < 0)
        intsetInsert(is, value, NULL);  // 插入头部
    else
        intsetInsert(is, value, NULL);  // 插入尾部
    
    return is;
}
```

**升级的内存布局变化**：

```
升级前（INTSET_ENC_INT16，每个元素 2 字节）：
    ┌──────┬──────┬──────┬──────┐
    │  1   │  5   │ 100  │ 200  │  （都是 16-bit 整数）
    └──────┴──────┴──────┴──────┘

升级后（INTSET_ENC_INT32，每个元素 4 字节）：
    ┌──────┬──────┬──────┬──────┐
    │  1   │  5   │ 100  │ 200  │  （都升级为 32-bit 整数）
    │      │      │      │      │
    └──────┴──────┴──────┴──────┘
```

### 7.3 HT（dict）编码的 Set

当 Set 不满足 intset 条件时，转换为 **dict** 编码。

**特点**：
- dict 的 key 存储 Set 元素
- dict 的 value 为 NULL（不存储值，只判断 key 是否存在）
- 利用 dict 的 O(1) 查找特性实现 SADD/SREM/SISMEMBER

**SADD 的底层调用**：

```c
// t_set.c → setTypeAdd()
int setTypeAdd(robj *subject, sds value) {
    // intset 编码
    if (subject->encoding == OBJ_ENCODING_INTSET) {
        long long llval;
        // 尝试解析为整数
        if (isSdsRepresentingInteger(value, &llval)) {
            // 是整数：插入 intset
            uint8_t success = 0;
            subject->ptr = intsetAdd(subject->ptr, llval, &success);
            if (success) {
                // 检查是否需要转换为 HT
                if (intsetLen(subject->ptr) > server.set_max_intset_entries)
                    setTypeConvert(subject, OBJ_ENCODING_HT);
                return 1;
            }
        }
        // 不是整数 或 插入失败（intset 已满）→ 转换为 HT
        setTypeConvert(subject, OBJ_ENCODING_HT);
    }
    
    // HT 编码 或 已转换
    if (subject->encoding == OBJ_ENCODING_HT) {
        dictAdd(subject->ptr, value, NULL);  // value = NULL
    }
}
```

### 7.4 Set 底层原理总结

```
┌──────────────────────────────────────────────────────────┐
│                    Set 编码选择                          │
├──────────────────────────────────────────────────────────┤
│  所有元素都是整数？                                      │
│      YES → 元素数 ≤ set-max-intset-entries（512）？       │
│              YES → OBJ_ENCODING_INTSET                  │
│              NO  → OBJ_ENCODING_HT                     │
│      NO  → OBJ_ENCODING_HT                             │
│                                                        │
│  intset 特点：                                           │
│  - 有序存储（二分查找 O(log N)）                         │
│  - 支持升级（16→32→64 bit）不支持降级                   │
│  - 内存紧凑（无指针开销）                                │
└──────────────────────────────────────────────────────────┘
```

---

## 8. ZSet（有序集合）—— listpack + skiplist+dict

### 8.1 ZSet 的 2 种编码

**listpack 编码**：
- 元素数 ≤ `zset-max-listpack-entries`（默认 128）
- 每个元素 ≤ `zset-max-listpack-value`（默认 64）
- 所有元素按 score **升序**存储在 listpack 中

**skiplist + dict 编码**：
- 不满足上述条件
- 底层是**跳表**（按 score 排序，支持范围查询）+ **字典**（O(1) 查 score）

### 8.2 listpack 编码的 ZSet 存储格式

ZSet 在 listpack 中**按 score 升序连续存储**元素和分数：

```
ZSet {Zhang: 95.5, Alice: 88.0, Bob: 92.0} 的 listpack 存储：

    ┌──────────────────────────────────────────────────────┐
    │  [88.0]  [Alice]  [92.0]  [Bob]  [95.5]  [Zhang] │
    │    ↑        ↑        ↑       ↑       ↑        ↑      │
    │  score1   成员1   score2   成员2  score3   成员3    │
    │                                                      │
    │  按 score 升序排列！                                  │
    └──────────────────────────────────────────────────────┘
```

**ZADD 的插入过程**（listpack 编码）：
1. 计算新元素的 score
2. 遍历 listpack，找到第一个 score **大于**新元素 score 的位置
3. 在该位置**前**插入（新元素, score）
4. 时间复杂度：O(N)（需要遍历找到插入位置）

**ZRANGE 的查询过程**（listpack 编码）：
1. 从头遍历 listpack
2. 按序返回元素
3. 时间复杂度：O(N)（N = 返回元素个数）

### 8.3 skiplist + dict 编码的 ZSet

当 ZSet 不满足 listpack 条件时，转换为 **skiplist + dict** 编码。

**zset 结构体**：

```c
typedef struct zset {
    dict *dict;          // member → score（O(1) 查分）
    zskiplist *zsl;      // 按 score 排序（范围查询）
} zset;
```

**为什么需要两个结构？**

| 操作                | 只用跳表 | 只用字典 | 跳表+字典 |
|---------------------|----------|----------|-----------|
| ZSCORE（查分）       | O(log N) | O(1)     | **O(1)**（字典） |
| ZRANGE（范围查询）    | O(log N + M) | 不支持 | **O(log N + M)**（跳表） |
| ZADD（插入）         | O(log N) | O(1)     | O(log N)（跳表插入） + O(1)（字典插入） |

**内存共享**：
- 跳表和字典**共享 member 和 score 的内存**
- member 和 score 只存储一份，跳表和字典都引用它们

```c
// 插入元素时，member 和 score 只存储一份
// 跳表的节点和字典的 entry 都指向同一份 member 和 score

typedef struct zskiplistNode {
    sds ele;             // 成员（和 dict 中的 key 是同一个 sds）
    double score;        // 分数（和 dict 中的 value 是同一个 double）
    struct zskiplistNode *backward;
    struct zskiplistLevel {
        struct zskiplistNode *forward;
        unsigned long span;
    } level[];
} zskiplistNode;
```

### 8.4 跳表（skiplist）原理（详见第 11 节）

**跳表的核心思想**：
- 给有序链表加**多层索引**
- 每层索引是下层 sampling
- 查找/插入/删除时间复杂度：**O(log N)**

**Redis 跳表的特点**：
- 最高 32 层（Redis 6.0 之前是 32 层，7.0 是 64 层）
- 每层是一个**有序链表**
- 节点层数**随机生成**（幂次定理：1/4 概率晋升到下一层）

**跳表节点结构**：

```
zskiplistNode（最高 32 层）：

    ┌──────┬──────┬───────────────────────────────────────┐
    │ ele  │score │level[0]  │level[1]  │...│level[31] │
    │(sds) │(dbl)│forward   │forward   │    │forward   │
    │      │      │span=1    │span=2    │    │span=8    │
    └──────┴──────┴──────────┴──────────┴────┴──────────┘
                            │          │              │
                            ▼          ▼              ▼
                      下一节点    下下节点        8 个节点后
```

**查找过程**（查找 score = 2.5 的元素）：

```
层 3：从头节点层 3 开始，forward 指向 score=4 的节点（4 > 2.5，不下探）
层 2：在层 2，forward 指向 score=1 的节点（1 < 2.5，下探）
层 1：在层 1，forward 指向 score=2 的节点（2 < 2.5，下探）
层 0：在层 0，forward 指向 score=3 的节点（3 > 2.5，没找到）
```

### 8.5 ZSet 底层原理总结

```
┌──────────────────────────────────────────────────────────┐
│                   ZSet 编码选择                           │
├──────────────────────────────────────────────────────────┤
│  元素数 ≤ zset-max-listpack-entries（128）                │
│  AND 每个元素 ≤ zset-max-listpack-value（64 字节）？       │
│      YES → OBJ_ENCODING_LISTPACK                         │
│      NO  → OBJ_ENCODING_SKIPLIST（skiplist + dict）     │
│                                                        │
│  跳表 + 字典的特点：                                      │
│  - 字典：O(1) ZSCORE                                    │
│  - 跳表：O(log N + M) ZRANGE/ZRANGEBYSCORE             │
│  - 内存共享（member/score 只存一份）                      │
└──────────────────────────────────────────────────────────┘
```

---

# 第三部分：底层数据结构源码

## 9. SDS（简单动态字符串）源码详解

### 9.1 SDS 的 5 种类型选择策略

Redis 根据字符串长度**自动选择**最合适的 SDS 类型（节省 header 开销）：

```c
// sds.c → sdsnewlen()
sds sdsnewlen(const void *init, size_t initlen) {
    sds s;
    // 根据 initlen 选择合适的 SDS 类型
    char type = sdsReqType(initlen);
    
    // 空字符串用 sdshdr8（避免 sdshdr5 的缺陷）
    if (type == SDS_TYPE_5 && initlen == 0)
        type = SDS_TYPE_8;
    
    int hdrlen = sdsHdrSize(type);  // header 大小
    unsigned char *fp = ((unsigned char*)s) - 1;  // flags 指针
    
    // 分配内存：header + 字符串 + \0
    s = s_malloc(hdrlen + initlen + 1);
    
    // 设置 header
    switch(type) {
        case SDS_TYPE_5: {
            *fp = SDS_TYPE_5 | (initlen << SDS_TYPE_BITS);
            break;
        }
        case SDS_TYPE_8: {
            SDS_HDR_VAR(8,s);
            sh->len = initlen;
            sh->alloc = initlen;
            *fp = type;
            break;
        }
        // ... sdshdr16/sdshdr32/sdshdr64 类似
    }
    return s;
}
```

### 9.2 SDS 的扩容源码

```c
// sds.c → sdsMakeRoomFor()
sds sdsMakeRoomFor(sds s, size_t addlen) {
    size_t newlen = sdslen(s) + addlen;
    
    // 如果剩余空间足够，直接返回
    if (sdsavail(s) >= addlen)
        return s;
    
    // 计算新的 alloc（预分配策略）
    if (newlen < SDS_MAX_PREALLOC)    // < 1MB
        newlen *= 2;                  // 翻倍
    else
        newlen += SDS_MAX_PREALLOC;    // +1MB
    
    // 根据新长度选择合适的 SDS 类型
    type = sdsReqType(newlen);
    
    // 如果类型变化，需要重新分配（header 大小可能变化）
    if (type != oldtype) {
        // 重新分配内存（拷贝数据）
        s = s_realloc(s, hdrlen + newlen + 1);
    } else {
        // 类型不变，只扩展 buf
        s = s_realloc(s, hdrlen + newlen + 1);
    }
    
    // 更新 alloc
    sdssetalloc(s, newlen);
    return s;
}
```

### 9.3 SDS 的二进制安全

**C 字符串的问题**：不能存储包含 `\0` 的数据（因为 C 字符串以 `\0` 判断结束）

**SDS 的解决方案**：用 `len` 字段判断字符串结束，不看 `\0`

```c
// 存储二进制数据（包含 \0）
sds binary = sdsnewlen("\x00\x01\x02", 3);  // 正确存储 3 个字节
// C 字符串：char *cstr = "\x00\x01\x02";   // 只看到第 1 个字节（\0 截断）

sdslen(binary);  // = 3（正确）
strlen(cstr);    // = 0（错误，遇到 \0 就停）
```

---

---

## 10. dict（哈希表）源码详解

### 10.1 dictht 结构体

Redis 的 dict 是**自己实现的哈希表**，不依赖任何第三方库。

```c
typedef struct dictht {
    dictEntry **table;      // 哈希表数组（指针数组）
    unsigned long size;     // 数组大小（2 的幂）
    unsigned long sizemask; // size - 1（用于计算索引，位运算）
    unsigned long used;     // 已有节点数
} dictht;
```

**dictEntry 结构体**（哈希表节点）：

```c
typedef struct dictEntry {
    void *key;                  // 键
    union {
        void *val;              // 值（HT 编码的 Hash/Set）
        uint64_t u64;          // 整数值（某些场景）
        int64_t s64;           // 整数值
        double d;               // 浮点值
    } v;
    struct dictEntry *next;      // 下一个节点（拉链法解决冲突）
} dictEntry;
```

**内存布局**：

```
dictht 内存布局：

    dictht
    ┌─────────┬─────────┬──────────┬─────────┐
    │  table   │  size   │ sizemask │  used   │
    │  (ptr)   │ (8B)   │  (8B)   │  (8B)  │
    └────┬────┴─────────┴──────────┴─────────┘
         │
         ▼
    table[0] → NULL
    table[1] → entry1 → entry2 → NULL   （哈希冲突，拉链）
    table[2] → entry3 → NULL
    ...
    table[size-1] → NULL
```

### 10.2 哈希函数

Redis 使用 **MurmurHash2** 算法计算哈希值（均匀性好，速度快）：

```c
// dict.c → dictHashFunction()
uint64_t dictHashFunction(const void *key, size_t len) {
    return MurmurHash64A(key, len, 0xadc83b19ULL);
}
```

**索引计算**（位运算替代取模）：

```c
// 计算索引
index = hash & ht->sizemask;   // 等价于 hash % size，但更快
```

**为什么 size 必须是 2 的幂？**
- 只有 size 是 2 的幂时，`hash & (size-1)` 才等价于 `hash % size`
- 位运算比取模快得多

### 10.3 渐进式 rehash

Redis 的 dict 支持**渐进式 rehash**，避免在数据量大时阻塞主线程。

**为什么需要 rehash？**
- 负载因子 `used / size` 过大 → 哈希冲突多 → 查找效率低
- 负载因子过小 → 内存浪费

**rehash 触发条件**：

| 条件                               | 动作              |
|------------------------------------|-------------------|
| `used / size ≥ 1`（无 BGSAVE/RDB） | 扩容到 `size * 2` |
| `used / size ≥ 5`（有 BGSAVE/RDB） | 扩容到 `size * 2` |
| `used / size < 0.1`               | 缩容到 `size / 2` |

**渐进式 rehash 过程**：

```
Step 1：分配 ht[1]
  - ht[0].size = 4，ht[1].size = 8（扩容 2 倍）
  - rehashidx = 0（开始 rehash 第 0 个 bucket）

Step 2：每次增/删/改/查操作，顺带迁移一个 bucket
  - 将 ht[0].table[rehashidx] 上的所有节点 rehash 到 ht[1]
  - rehashidx++

Step 3：所有 bucket 迁移完毕
  - 释放 ht[0]
  - ht[0] = ht[1]
  - ht[1] = NULL
  - rehashidx = -1（rehash 结束）
```

**渐进式 rehash 源码**：

```c
// dict.c → dictRehash()
int dictRehash(dict *d, int n) {
    int empty_visits = n * 10;  // 最多访问 10*n 个空 bucket
    
    while (n-- && d->ht[0].used != 0) {
        dictEntry *de, *nextde;
        
        // 跳过空 bucket
        while (d->ht[0].table[d->rehashidx] == NULL) {
            d->rehashidx++;
            if (--empty_visits == 0)
                return 1;  // 这次 rehash 未完成
        }
        
        // 迁移当前 bucket 的所有节点
        de = d->ht[0].table[d->rehashidx];
        while (de) {
            unsigned int h;
            nextde = de->next;
            
            // 计算新索引（ht[1] 的 size）
            h = dictHashFunction(de->key, sdslen(de->key)) & d->ht[1].sizemask;
            
            // 插入到 ht[1] 的对应 bucket
            de->next = d->ht[1].table[h];
            d->ht[1].table[h] = de;
            
            d->ht[0].used--;
            d->ht[1].used++;
            de = nextde;
        }
        
        // 当前 bucket 已清空
        d->ht[0].table[d->rehashidx] = NULL;
        d->rehashidx++;
    }
    
    // 所有 bucket 迁移完毕
    if (d->ht[0].used == 0) {
        zfree(d->ht[0].table);
        d->ht[0] = d->ht[1];
        _dictReset(&d->ht[1]);
        d->rehashidx = -1;
        return 0;  // rehash 完成
    }
    
    return 1;  // rehash 未完成
}
```

**rehash 期间的查找**：

```c
// dict.c → dictFind()
dictEntry *dictFind(dict *d, const void *key) {
    unsigned int h, idx, table;
    
    // 先在 ht[0] 查找
    if (dictIsRehashing(d))
        _dictRehashStep(d);  // 顺带迁移一个 bucket
    
    h = dictHashFunction(key, sdslen(key));
    
    // 先查 ht[0]，再查 ht[1]（如果正在 rehash）
    for (table = 0; table <= 1; table++) {
        idx = h & d->ht[table].sizemask;
        de = d->ht[table].table[idx];
        while (de) {
            if (keyCompare(d, key, de->key))
                return de;
            de = de->next;
        }
        
        if (!dictIsRehashing(d))
            break;  // 不在 rehash，只查 ht[0]
    }
    
    return NULL;
}
```

---

## 11. skiplist（跳表）源码详解

### 11.1 跳表的核心思想

**为什么用跳表而不是平衡树？**
- 跳表实现简单（比红黑树简单得多）
- 范围查询高效（平衡树需要中序遍历，跳表直接线性扫描）
- 支持无锁并发（平衡树很难做到）

**跳表结构**：

```
最高 32 层的跳表：

    层 3：  head ─────────────────────────────────────────→  NIL
                 │
    层 2：  head ─────→ L2 ─────────────────→ L7 ─────→  NIL
                 │        │                    │
    层 1：  head ─────→ L2 ───→ L4 ───→ L7 ───→ L9 ─→  NIL
                 │        │       │       │       │
    层 0：  head ─→ L1 ─→ L2 ─→ L3 ─→ L4 ─→...─→ L9 ─→  NIL
                1        2       3       4       7       9

    L = 节点
    箭头 = forward 指针
```

### 11.2 zskiplist 结构体

```c
typedef struct zskiplist {
    struct zskiplistNode *header, *tail;  // 头尾节点
    unsigned long length;                   // 节点数（不含头节点）
    int level;                             // 最大层数（不含头节点）
} zskiplist;
```

**zskiplistNode 结构体**：

```c
typedef struct zskiplistNode {
    sds ele;             // 成员
    double score;         // 分数
    struct zskiplistNode *backward;  // 后退指针（层 0 的后继）
    struct zskiplistLevel {
        struct zskiplistNode *forward;  // 前进指针
        unsigned long span;              // 跨度（到下一个节点的距离）
    } level[];          // 柔性数组，大小在创建节点时确定
} zskiplistNode;
```

**span 字段的作用**：
- 用于计算**排名**（ZRANK 命令）
- `ZRANK key member` = 从头节点到目标节点的 span 之和

### 11.3 节点层数随机生成

Redis 使用**幂次定理**随机生成节点层数：

```c
// t_zset.c → zslRandomLevel()
int zslRandomLevel(void) {
    int level = 1;
    // 每次有 1/4 概率晋升到下一层
    while ((rand() & 0xFFFF) < (ZSKIPLIST_P * 0xFFFF))
        level++;
    return (level < ZSKIPLIST_MAXLEVEL) ? level : ZSKIPLIST_MAXLEVEL;
}
// ZSKIPLIST_P = 0.25（1/4 概率）
// ZSKIPLIST_MAXLEVEL = 32（Redis 6.0 之前）/ 64（Redis 7.0）
```

**层数分布**：

| 层数 | 概率    | 期望节点数（100 万节点） |
|------|----------|--------------------------|
| 1    | 75%      | 750,000                  |
| 2    | 18.75%   | 187,500                  |
| 3    | 4.69%    | 46,875                   |
| 4    | 1.17%    | 11,719                   |
| ...  | ...      | ...                      |
| 32   | ~1e-19   | ~0                       |

### 11.4 跳表插入过程

```c
// t_zset.c → zslInsert()
zskiplistNode *zslInsert(zskiplist *zsl, double score, sds ele) {
    zskiplistNode *update[ZSKIPLIST_MAXLEVEL];  // 每层的前驱节点
    unsigned int rank[ZSKIPLIST_MAXLEVEL];       // 每层的排名
    zskiplistNode *x;
    int i, level;
    
    x = zsl->header;
    // 从最高层开始，找到每层的插入位置
    for (i = zsl->level-1; i >= 0; i--) {
        rank[i] = (i == zsl->level-1) ? 0 : rank[i+1];
        while (x->level[i].forward &&
               (x->level[i].forward->score < score ||
                (x->level[i].forward->score == score &&
                 sdscmp(x->level[i].forward->ele, ele) < 0))) {
            rank[i] += x->level[i].span;
            x = x->level[i].forward;
        }
        update[i] = x;  // 记录前驱
    }
    
    // 随机生成新节点的层数
    level = zslRandomLevel();
    if (level > zsl->level) {
        for (i = zsl->level; i < level; i++) {
            rank[i] = 0;
            update[i] = zsl->header;
            update[i]->level[i].span = zsl->length;
        }
        zsl->level = level;
    }
    
    // 创建新节点
    x = zslCreateNode(level, score, ele);
    
    // 插入到每层的链表中
    for (i = 0; i < level; i++) {
        x->level[i].forward = update[i]->level[i].forward;
        update[i]->level[i].forward = x;
        
        // 更新 span
        x->level[i].span = update[i]->level[i].span - (rank[0] - rank[i]);
        update[i]->level[i].span = (rank[0] - rank[i]) + 1;
    }
    
    // 更新高层 span
    for (i = level; i < zsl->level; i++) {
        update[i]->level[i].span++;
    }
    
    // 设置后退指针
    x->backward = (update[0] == zsl->header) ? NULL : update[0];
    if (update[0]->level[0].forward)
        update[0]->level[0].forward->backward = x;
    else
        zsl->tail = x;
    
    zsl->length++;
    return x;
}
```

**插入过程图解**：

```
插入 score=3.5 的节点，随机生成层数=2：

层 2：  head ─────────→ L7 ─────→ NIL
               │
层 1：  head ─→ L2 ─→ [新节点] ─→ L7 ─→ NIL
               │       │           │
层 0：  ... ─→ L2 ─→ [新节点] ─→ L3 ─→ ...
               
update[0] = L2  （层 0 前驱）
update[1] = head（层 1 前驱）
```

---

## 12. intset（整数集合）源码详解

### 12.1 intset 的结构

```c
typedef struct intset {
    uint32_t encoding;   // 编码方式
    uint32_t length;     // 元素个数
    int8_t contents[];   // 柔性数组，按值升序存储
} intset;
```

**encoding 的 3 种取值**：

```c
#define INTSET_ENC_INT16  (sizeof(int16_t))   // 2 字节
#define INTSET_ENC_INT32  (sizeof(int32_t))   // 4 字节
#define INTSET_ENC_INT64  (sizeof(int64_t))   // 8 字节
```

### 12.2 升级机制

当插入一个超出当前 encoding 范围的整数时，intset **自动升级**：

```c
// intset.c → intsetUpgradeAndAdd()
static intset *intsetUpgradeAndAdd(intset *is, int64_t value) {
    uint8_t curenc = intrev32ifbe(is->encoding);
    uint8_t newenc = (curenc == INTSET_ENC_INT16) ? INTSET_ENC_INT32 :
                    (curenc == INTSET_ENC_INT32) ? INTSET_ENC_INT64 :
                    INTSET_ENC_INT64;
    
    int length = intrev32ifbe(is->length);
    is->encoding = newenc;
    
    // 重新分配内存
    is = intsetResize(is, length, newenc);
    
    // 从后向前迁移（避免覆盖）
    while (length--)
        _intsetSet(is, length, _intsetGet(is, length, curenc), newenc);
    
    // 插入新元素（头部或尾部）
    if (value < 0)
        intsetInsert(is, value, NULL);
    else
        intsetInsert(is, value, NULL);
    
    return is;
}
```

**升级示例**：

```
升级前（INTSET_ENC_INT16，每个元素 2 字节，共 4 个元素）：
    contents: [1][5][100][200]  （8 字节）

升级后（INTSET_ENC_INT32，每个元素 4 字节，共 4 个元素）：
    contents: [1][5][100][200]  （16 字节）
    每个元素占用空间翻倍
```

### 12.3 查找过程（二分查找）

```c
// intset.c → intsetFind()
uint8_t intsetFind(intset *is, int64_t value) {
    // 快速判断：value 是否在 [contents[0], contents[length-1]] 范围内
    if (value < 0 && intrev32ifbe(is->length) == 0)
        return 0;
    if (value < _intsetGet(is, 0, intrev32ifbe(is->encoding)))
        return 0;
    if (value > _intsetGet(is, intrev32ifbe(is->length)-1, intrev32ifbe(is->encoding)))
        return 0;
    
    // 二分查找
    return intsetSearch(is, value, NULL);
}

static uint8_t intsetSearch(intset *is, int64_t value, uint32_t *pos) {
    int min = 0, max = intrev32ifbe(is->length) - 1, mid = -1;
    int cur = -1;
    uint32_t encoding = intrev32ifbe(is->encoding);
    
    while (max >= min) {
        mid = (min + max) / 2;
        cur = _intsetGet(is, mid, encoding);
        if (value > cur) {
            min = mid + 1;
        } else if (value < cur) {
            max = mid - 1;
        } else {
            if (pos) *pos = mid;
            return 1;  // 找到
        }
    }
    
    if (pos) *pos = min;
    return 0;  // 没找到
}
```

---

## 13. listpack（紧凑列表）源码详解

### 13.1 listpack 的设计目标

listpack 是 ziplist 的**无级联更新版本**：

**ziplist 的问题**：
- 每个 entry 有 `prev_entry_len`（1 或 5 字节）
- 当前一个 entry 长度从 <254 变为 ≥254 时，当前 entry 的 `prev_entry_len` 需要从 1 字节扩展到 5 字节
- 这可能导致**连锁更新**（后续所有 entry 都需要更新）

**listpack 的解决方案**：
- 去掉 `prev_entry_len`
- 每个 entry 自己记录自己的长度（`entry-len`）
- 反向遍历时，通过 `entry-len` 计算前一个 entry 的位置

### 13.2 listpack entry 格式

```
listpack entry 格式：

    ┌────────────────┬──────────────────┬───────────────┐
    │ encoding+data  │ entry-len       │ backlen        │
    │ （数据）        │ （本 entry 长度） │ （entry-len   │
    │                │                  │  的长度）       │
    └────────────────┴──────────────────┴───────────────┘
```

**encoding+data**：
- 整数：用 1 字节 encoding 表示（省空间）
- 字符串：encoding 表示长度 + 实际字符串

**entry-len**：
- 用 1~5 字节存储本 entry 的总长度
- 反向遍历时，用这个字段定位前一个 entry

**backlen**：
- 存储 `entry-len` 字段的长度
- 用于**快速反向遍历**

### 13.3 listpack 查找过程

**正向查找**（遍历 listpack）：

```c
// listpack.c → lpFirst()/lpNext()
unsigned char *lpNext(unsigned char *lp, unsigned char *p) {
    // p 当前指向某个 entry
    // 找到 p 的 entry-len 字段
    unsigned char *next = lpGetEntryLen(p);
    // 跳过当前 entry，就是下一个 entry
    return next;
}
```

**反向查找**（利用 backlen）：

```c
// listpack.c → lpPrev()
unsigned char *lpPrev(unsigned char *lp, unsigned char *p) {
    // p 当前指向某个 entry
    // 找到 p 的 backlen 字段（在 entry 头部）
    unsigned char *prev = lpGetBacklen(p);
    // 根据 backlen 计算出前一个 entry 的起始位置
    return prev;
}
```

---

## 14. quicklist（快速列表）源码详解

### 14.1 quicklist 的设计思想

quicklist 是 **ziplist/listpack** 和 **双向链表**的结合：

- **ziplist/listpack**：内存连续，缓存友好，但修改效率低（需要内存拷贝）
- **双向链表**：修改效率高（O(1) 插入/删除），但内存不连续，缓存不友好

**quicklist 的折中**：
- 每个节点是一个 **listpack**（内存连续，小数据高效）
- 节点之间用**双向链表**连接（修改高效）

### 14.2 quicklist 节点压缩

quicklist 支持**LZF 压缩**，可以压缩中间的节点（两端不压缩，方便快速访问）：

```c
typedef struct quicklistNode {
    struct quicklistNode *prev;
    struct quicklistNode *next;
    unsigned char *entry;        // 指向 listpack 或压缩后的数据
    unsigned int sz;             // 未压缩时的 listpack 大小
    unsigned int count : 16;     // listpack 中的元素个数
    unsigned int encoding : 2;   // RAW = 1, LZF = 2
    unsigned int container : 2;   // NONE = 1, LISTPACK = 2
    unsigned int recompress : 1; // 是否被解压过（临时标记）
    // ...
} quicklistNode;
```

**compress 参数**：
- `compress = 0`：不压缩任何节点
- `compress = 1`：除两端各 1 个节点外，其余节点压缩
- `compress = 2`：除两端各 2 个节点外，其余节点压缩
- ...

**压缩/解压过程**：

```c
// 压缩节点
void __quicklistCompressNode(quicklistNode *node) {
    if (node->encoding == QUICKLIST_NODE_ENCODING_RAW) {
        // 用 LZF 算法压缩
        node->entry = lzf_compress(node->entry, node->sz, ...);
        node->encoding = QUICKLIST_NODE_ENCODING_LZF;
    }
}

// 解压节点
void __quicklistDecompressNode(quicklistNode *node) {
    if (node->encoding == QUICKLIST_NODE_ENCODING_LZF) {
        // 解压
        node->entry = lzf_decompress(node->entry, ...);
        node->encoding = QUICKLIST_NODE_ENCODING_RAW;
    }
}
```

### 14.3 quicklist 插入过程

```c
// quicklist.c → quicklistPush()
void quicklistPush(quicklist *quicklist, void *value, const size_t sz, int where) {
    // where = 0：头插；where = 1：尾插
    
    if (where == QUICKLIST_HEAD) {
        quicklistNode *head = quicklist->head;
        
        // 如果头节点还有空间
        if (head && head->sz < server.list_max_listpack_size) {
            // 直接插入头节点的 listpack
            head->entry = listpackPush(head->entry, value, sz, 0);
        } else {
            // 创建新节点
            quicklistNode *node = quicklistNewNode();
            node->entry = listpackPush(NULL, value, sz, 0);
            // 插入到链表头部
            head->prev = node;
            node->next = head;
            quicklist->head = node;
        }
    }
    // 尾插类似
}
```

---

---

## 15. Bitmap（位图）底层实现

### 15.1 Bitmap 的本质

**Bitmap 不是独立的数据类型**，它是对 **String（SDS）** 的位操作封装。

```
Bitmap 命令：
  SETBIT key offset value    →  对 String 的 offset 位设值
  GETBIT key offset         →  获取 String 的 offset 位
  BITCOUNT key [start end] →  统计 String 中 1 的个数
  BITOP op dest key [key ...] →  对多个 String 做位运算
```

**为什么用 String 实现 Bitmap？**
- String 的 SDS 是**字节数组**，天然支持按位操作
- SDS 支持**动态扩容**（SETBIT 可以自动扩展字符串长度）

### 15.2 SETBIT 的底层实现

```c
// bitops.c → setbitCommand()
void setbitCommand(redisClient *c) {
    robj *o;
    char *err = "bit is not an integer or out of range";
    long offset;
    long on;
    
    // 1. 解析 offset（位偏移量）
    if (getLongFromObjectOrReply(c, c->argv[2], &offset, err) != REDIS_OK)
        return;
    if (offset < 0 || offset > 511999999) {  // 最大 512 MB * 8 = 4.29 亿位
        addReplyError(c, err);
        return;
    }
    
    // 2. 解析 value（0 或 1）
    if (getLongFromObjectOrReply(c, c->argv[3], &on, err) != REDIS_OK)
        return;
    
    // 3. 获取或创建 String 对象
    o = lookupKeyWrite(c->db, c->argv[1]);
    if (o == NULL) {
        // 不存在：创建 SDS（按需分配，不预先分配全部空间）
        o = createObject(REDIS_STRING, sdsempty());
        dbAdd(c->db, c->argv[1], o);
    }
    
    // 4. 计算需要的字节数
    bytes_needed = (offset / 8) + 1;
    
    // 5. 如果 SDS 长度不够，扩容
    if (bytes_needed > sdslen(o->ptr)) {
        o->ptr = sdsgrowzero(o->ptr, bytes_needed);
    }
    
    // 6. 计算位所在的位置
    byte = offset / 8;          // 第几个字节
    bit = 7 - (offset % 8);   // 该字节的第几位（高位在前）
    
    // 7. 读取旧值
    oldbit = ((o->ptr)[byte] & (1 << bit)) != 0;
    
    // 8. 设置新值
    if (on)
        (o->ptr)[byte] |= (1 << bit);   // 置 1
    else
        (o->ptr)[byte] &= ~(1 << bit);  // 置 0
    
    // 9. 返回旧值
    addReply(c, oldbit ? shared.cone : shared.czero);
}
```

**位偏移量计算示例**：

```
SETBIT mybit 10 1

offset = 10
byte = 10 / 8 = 1    （第 1 个字节，0-indexed）
bit  = 7 - (10 % 8) = 7 - 2 = 5  （该字节的第 5 位）

字节布局（byte[1]）：
  位：  7   6   5   4   3   2   1   0
       [x] [x] [1] [x] [x] [x] [x] [x]
            ↑
          offset=10 的位
```

### 15.3 BITCOUNT 的底层实现

`BITCOUNT` 统计字符串中 1 的个数，Redis 使用了**查表法**优化：

```c
// bitops.c → bitcount()
long long bitcount(robj *o) {
    sds s = o->ptr;
    long long bitlen = sdslen(s) * 8;
    return redisPopCount((unsigned char*)s, sdslen(s));
}

// 使用 8-bit 查表法（256 个条目，每个条目是对应字节的 1 的个数）
static const unsigned char popcount_table[256] = {
    0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4,
    // ... 共 256 个值
};

long long redisPopCount(unsigned char *s, unsigned long count) {
    long long bits = 0;
    // 每次查表处理 1 个字节（8 位）
    while (count--) {
        bits += popcount_table[*s++];
    }
    return bits;
}
```

**优化**：Redis 还使用了 **SWAR 算法**（SIMD Within A Register）进一步加速：

```c
// SWAR 算法：一次处理 4 个字节（32 位）
uint32_t swar_popcount(uint32_t x) {
    x = x - ((x >> 1) & 0x55555555);  // 每 2 位一组，统计 1 的个数
    x = (x & 0x33333333) + ((x >> 2) & 0x33333333);  // 每 4 位一组
    x = (x + (x >> 4)) & 0x0F0F0F0F;  // 每 8 位一组
    x = (x * 0x01010101) >> 24;  // 将每 8 位的和加到最高字节
    return x;
}
```

### 15.4 Bitmap 实战场景

**1. 用户签到**（每个用户 365 位 = 46 字节）：

```bash
# 用户 1001 在 2026 年第 180 天签到
SETBIT sign:1001:2026 180 1

# 检查是否签到
GETBIT sign:1001:2026 180  →  1

# 统计 2026 年签到次数
BITCOUNT sign:1001:2026  →  120
```

**2. 活跃用户统计**（每天 1 位，1 亿用户 = 12.5 MB）：

```bash
# 2026-07-01 的活跃用户
SETBIT active:2026-07-01  user_id  1

# 统计 2026-07-01 的活跃用户数
BITCOUNT active:2026-07-01

# 统计连续 7 天活跃的用户（AND 运算）
BITOP AND 7days user_id user_id user_id ...
BITCOUNT 7days
```

---

## 16. HyperLogLog（基数估算）底层实现

### 16.1 HyperLogLog 的原理

**问题**：如何估算一个集合中**不重复元素**的个数（基数）？

**传统方法**：
- HashSet：精确，但内存随基数线性增长
- Bitmap：需要为每个元素分配 1 位，稀疏时浪费空间

**HyperLogLog 的思路**：
- 利用**伯努利过程**（抛硬币直到第一次正面朝上）
- 观察所有元素的哈希值，**最长的连续 0 的个数**可以估算基数

**直观理解**：
```
假设哈希值是 64-bit 随机数：
  元素 1 的哈希：...001011（尾部连续 0 个数 = 1）
  元素 2 的哈希：...000101（尾部连续 0 个数 = 2）
  元素 3 的哈希：...000001（尾部连续 0 个数 = 5）
  ...
  最大连续 0 个数 = 5

估算公式：基数 ≈ 2^5 = 32
（实际用多个桶取调和平均，更准确）
```

### 16.2 HyperLogLog 的存储结构

Redis 的 HyperLogLog 使用 **16384 个 6-bit 寄存器**（2^14 = 16384）：

```
HyperLogLog 存储结构：

    ┌──────────────────────────────────────────────────────┐
    │  magic（2B）│ encoding（1B）│ registers（12KB）     │
    │   "HY"       │  稀疏/密集    │  16384 * 6 bit       │
    └──────────────────────────────────────────────────────┘
                                │
                                12 KB（固定大小）
```

**为什么是 16384 个寄存器？**
- 标准误差 = `1.04 / sqrt(m)`，m = 16384 → 误差 ≈ 0.81%
- 16384 * 6 bit = 98304 bit = 12288 byte ≈ **12 KB**

### 16.3 稀疏寄存器 vs 密集寄存器

HyperLogLog 有两种编码方式，**自动转换**：

**稀疏寄存器（Sparse）**：
- 初始状态，所有寄存器都是 0
- 用**压缩格式**存储（只存储非零寄存器）
- 格式：`ZERO` 标记（连续 0 的个数）+ `VAL` 标记（寄存器值）

```
稀疏格式示例（只有 3 个非零寄存器）：
    [ZERO, 100]  [VAL, 5, 3]  [ZERO, 50]  [VAL, 2, 7]  [ZERO, ...]
      ↑                ↑                              ↑
    100 个 0        寄存器 100 值=3                寄存器 150 值=7
```

**密集寄存器（Dense）**：
- 当非零寄存器增多时，自动转换为**密集格式**
- 每个寄存器占用 6 bit（固定位置）

**转换触发条件**：
```
稀疏 → 密集：
  - 稀疏格式的大小超过 `hll-sparse-max-bytes`（默认 3000 字节）
  - 或执行了 PF COUNT（需要读取所有寄存器，稀疏格式读取慢）
```

### 16.4 PFADD 的底层实现

```c
// hyperloglog.c → pfaddCommand()
void pfaddCommand(redisClient *c) {
    robj *o;
    int updated = 0;
    
    // 1. 获取或创建 HyperLogLog 对象
    o = lookupKeyWrite(c->db, c->argv[1]);
    if (o == NULL) {
        // 创建稀疏格式的 HyperLogLog（初始 2+1+0 = 3 字节）
        o = createObject(REDIS_STRING, hllCreate());
        dbAdd(c->db, c->argv[1], o);
    }
    
    // 2. 对每个元素，计算哈希值
    for (j = 2; j < c->argc; j++) {
        unsigned char *ele = c->argv[j]->ptr;
        size_t elesize = sdslen(c->argv[j]->ptr);
        
        // 3. 计算 64-bit 哈希值（MurmurHash64A）
        uint64_t h = MurmurHash64A(ele, elesize, 0xadc83b19ULL);
        
        // 4. 取低 14 位作为寄存器索引
        unsigned int index = h & 0x3FFF;  // 0x3FFF = 16383
        
        // 5. 取高 50 位中，第一个 1 出现的位置（从左边数）
        uint8_t rank = 1;
        while (h & 0x4000000000000) {  // 从 bit 50 开始往左找
            rank++;
            h <<= 1;
        }
        
        // 6. 更新寄存器（如果 rank 更大）
        updated |= hllDenseSet(o->ptr, index, rank);
    }
    
    // 7. 如果更新了，标记脏
    if (updated)
        signalModifiedKey(c->db, c->argv[1]);
}
```

### 16.5 PFCOUNT 的底层实现

```c
// hyperloglog.c → pfcountCommand()
void pfcountCommand(redisClient *c) {
    // 1. 如果只有一个 key，直接读取寄存器估算
    if (c->argc == 2) {
        robj *o = lookupKeyRead(c->db, c->argv[1]);
        if (o == NULL) {
            addReplyBulkCString(c, "0");
            return;
        }
        
        // 2. 读取所有寄存器的值
        int i;
        double sum = 0;
        for (i = 0; i < HLL_REGISTERS; i++) {
            uint8_t val = hllDenseGet(o->ptr, i);
            sum += 1.0 / (1 << val);  // 调和平均
        }
        
        // 3. 应用估算公式
        double alpha = 0.7213 / (1 + 1.079 / HLL_REGISTERS);
        double estimate = alpha * HLL_REGISTERS * HLL_REGISTERS / sum;
        
        // 4. 小范围修正（当估算值 < 2.5 * m 时）
        if (estimate < 2.5 * HLL_REGISTERS) {
            // 用 Linear Counting 修正
            estimate = hllCount(hllDenseGet, o->ptr);
        }
        
        addReplyBulkCString(c, estimate);
    }
    // 如果多个 key，先合并再估算
    else {
        // ... 合并多个 HyperLogLog（取每个寄存器的最大值）
    }
}
```

### 16.6 HyperLogLog 误差分析

| 基数范围 | 理论误差 | 实际误差（Redis 实现） |
|----------|-----------|--------------------------|
| < 10^3   | 较高       | 用 Linear Counting 修正    |
| 10^3~10^6 | ~0.81%    | ~0.81%                   |
| > 10^6   | ~0.81%    | ~0.81%                   |

**内存占用**：固定 **12 KB**（无论基数是多少）

---

## 17. Geo（地理位置）底层实现

### 17.1 Geo 的本质

**Geo 不是独立的数据类型**，它是对 **ZSet（有序集合）** 的封装。

**核心思路**：
- 将（经度，纬度）编码为 **52-bit Geohash 整数**
- 将 Geohash 整数作为 ZSet 的 **score**
- 将成员名作为 ZSet 的 **member**

### 17.2 Geohash 编码原理

**Geohash 是一种地理编码**，将二维坐标编码为一维字符串/整数：

```
Geohash 编码过程：

Step 1：经度（-180° ~ 180°）二分
  -180 ~ 0：0
  0 ~ 180：1
  继续二分，得到经度二进制码（26 bit）

Step 2：纬度（-90° ~ 90°）二分
  同理，得到纬度二进制码（26 bit）

Step 3：交叉组合
  经度 bit0，纬度 bit0，经度 bit1，纬度 bit1，...
  得到 52-bit 整数

Step 4：Base32 编码（可选）
  每 5 个 bit 编码为一个字符
```

**Geohash 的特点**：
- **前缀相似性原则**：距离近的地点，Geohash 值也相近
- **精度可调**：Geohash 字符串长度越长，精度越高

| Geohash 长度 | 精度（误差） |
|---------------|--------------|
| 1 个字符      | ± 2500 km    |
| 2 个字符      | ± 630 km     |
| 3 个字符      | ± 78 km      |
| 4 个字符      | ± 20 km      |
| 5 个字符      | ± 2.4 km     |
| 6 个字符      | ± 0.61 km    |

### 17.3 GEOADD 的底层实现

```c
// geo.c → geoaddCommand()
void geoaddCommand(redisClient *c) {
    robj *o;
    int elements = (c->argc - 2) / 3;  // 每个元素：经度 纬度 名称
    
    // 1. 获取或创建 ZSet 对象
    o = lookupKeyWrite(c->db, c->argv[1]);
    if (o == NULL) {
        o = createObject(REDIS_ZSET, zsetCreate());
        dbAdd(c->db, c->argv[1], o);
    }
    
    // 2. 对每个位置
    for (i = 0; i < elements; i++) {
        double longitude, latitude;
        char *member;
        
        // 3. 解析经纬度
        longitude = strtod(c->argv[2+i*3]->ptr, NULL);
        latitude  = strtod(c->argv[3+i*3]->ptr, NULL);
        
        // 4. 验证经纬度合法性
        if (!isLongitude(longitude) || !isLatitude(latitude)) {
            addReplyError(c, "invalid longitude or latitude");
            return;
        }
        
        // 5. 编码为 Geohash 整数（作为 ZSet 的 score）
        uint64_t geohash = geohashEncode(longitude, latitude);
        
        // 6. 添加到 ZSet
        zsetAdd(o, (double)geohash, member);
    }
}
```

**geohashEncode() 源码**：

```c
// geo.c → geohashEncode()
uint64_t geohashEncode(double longitude, double latitude) {
    uint64_t bits = 0;
    double min_lon = -180, max_lon = 180;
    double min_lat = -90,  max_lat = 90;
    int i;
    
    // 26 次二分（经度 26 bit + 纬度 26 bit = 52 bit）
    for (i = 0; i < 26; i++) {
        uint64_t bit = 0;
        double mid;
        
        // 经度二分
        mid = (min_lon + max_lon) / 2;
        if (longitude >= mid) {
            bit = 1;
            min_lon = mid;
        } else {
            bit = 0;
            max_lon = mid;
        }
        bits = (bits << 1) | bit;
        
        // 纬度二分
        mid = (min_lat + max_lat) / 2;
        if (latitude >= mid) {
            bit = 1;
            min_lat = mid;
        } else {
            bit = 0;
            max_lat = mid;
        }
        bits = (bits << 1) | bit;
    }
    
    return bits;
}
```

### 17.4 GEORADIUS 的底层实现

`GEORADIUS` 查找指定半径内的所有位置，核心思路是**九宫格扩展**：

```c
// geo.c → georadiusCommand()
void georadiusCommand(redisClient *c) {
    double longitude, latitude, radius;
    int radius_unit;
    
    // 1. 解析参数
    longitude = strtod(c->argv[2]->ptr, NULL);
    latitude  = strtod(c->argv[3]->ptr, NULL);
    radius    = strtod(c->argv[4]->ptr, NULL);
    
    // 2. 计算九宫格的 Geohash 范围
    GeoHashRadius georadius = geohashGetAreasByRadius(longitude, latitude, radius);
    
    // 3. 对每个格子，查询 ZSet
    for (i = 0; i < 9; i++) {
        GeoHashBits area = georadius.areas[i];
        
        // 4. 计算该格子的 score 范围（Geohash 值范围）
        uint64_t min_geohash = area.bits << (52 - area.step * 2);
        uint64_t max_geohash = min_geohash + (1 << (52 - area.step * 2)) - 1;
        
        // 5. 用 ZRANGEBYSCORE 查询（底层是跳表范围查询）
        zset ZRANGEBYSCORE key min_geohash max_geohash;
        
        // 6. 对查询结果，逐一计算精确距离（过滤掉九宫格边缘外的位置）
        for (j = 0; j < results.size(); j++) {
            double dist = geodist(results[j], longitude, latitude);
            if (dist <= radius)
                reply_results.push_back(results[j]);
        }
    }
}
```

**九宫格扩展图解**：

```
以查询点为中心，扩展为 3x3 的格子：

    ┌─────┬─────┬─────┐
    │  6  │  7  │  8  │
    ├─────┼─────┼─────┤
    │  3  │  X  │  5  │   ← X = 查询点
    ├─────┼─────┼─────┤
    │  0  │  1  │  2  │
    └─────┴─────┴─────┘

对每个格子，计算 Geohash 范围，用 ZRANGEBYSCORE 查询
```

### 17.5 Geo 底层原理总结

```
┌──────────────────────────────────────────────────────────┐
│                   Geo 底层实现                          │
├──────────────────────────────────────────────────────────┤
│  GEOADD key longitude latitude member                  │
│      ↓                                                 │
│  geohashEncode(longitude, latitude) → 52-bit 整数    │
│      ↓                                                 │
│  ZADD key <52-bit整数> member                         │
│                                                        │
│  GEORADIUS key lng lat radius m                       │
│      ↓                                                 │
│  计算九宫格 Geohash 范围                              │
│      ↓                                                 │
│  ZRANGEBYSCORE key min_geohash max_geohash            │
│      ↓                                                 │
│  精确距离过滤（Haversine 公式）                        │
└──────────────────────────────────────────────────────────┘
```

---

---

## 18. 编码选择参数详解

Redis 提供了一系列**配置参数**，控制何时从紧凑编码转换为高效编码。

### 18.1 String 相关参数

| 参数                        | 默认值  | 说明                          |
|------------------------------|----------|-------------------------------|
| `proto-max-bulk-len`         | 512MB    | String 最大长度                |
| `hash-max-listpack-entries`  | 128      | Hash 使用 listpack 的最大字段数 |
| `hash-max-listpack-value`     | 64       | Hash 字段/值最大字节数        |

### 18.2 List 相关参数

| 参数                              | 默认值  | 说明                                    |
|-----------------------------------|----------|-----------------------------------------|
| `list-max-listpack-entries`        | 512      | List 使用 listpack 的最大元素数           |
| `list-max-listpack-value`          | 64       | List 元素最大字节数                      |
| `list-max-listpack-size`           | -2       | quicklist 节点最大大小（-2 = 8KB）       |
| `list-compress-depth`              | 0        | quicklist 两端不压缩的节点数              |

**`list-max-listpack-size` 的特殊含义**：
```
正数 N：每个节点最大 N 个 entry
负数 -N：每个节点最大 2^(-N) KB
  -1 = 4 KB
  -2 = 8 KB（默认）
  -3 = 16 KB
  -4 = 32 KB
  -5 = 64 KB
```

### 18.3 Hash/Set/ZSet 相关参数

| 参数                              | 默认值  | 说明                                    |
|-----------------------------------|----------|-----------------------------------------|
| `hash-max-listpack-entries`        | 128      | Hash 使用 listpack 的最大字段数           |
| `hash-max-listpack-value`         | 64       | Hash 字段/值最大字节数                    |
| `set-max-intset-entries`          | 512      | Set 使用 intset 的最大元素数              |
| `zset-max-listpack-entries`        | 128      | ZSet 使用 listpack 的最大元素数           |
| `zset-max-listpack-value`         | 64       | ZSet 元素最大字节数                      |

### 18.4 参数调优建议

**场景 1：小数据（社交关系、计数器）**
```
hash-max-listpack-entries 128   →  512  （更多 Hash 用 listpack）
hash-max-listpack-value 64      →  128  （支持更长的字段名/值）
set-max-intset-entries 512      →  1024 （更多 Set 用 intset）
```

**场景 2：大数据（海量小 Key）**
```
# 减少 listpack 使用，避免频繁编码转换
hash-max-listpack-entries 128   →  64
set-max-intset-entries 512      →  256
```

**场景 3：内存敏感（容器化部署）**
```
# 减小 listpack 大小，降低单个 Key 的内存占用
list-max-listpack-size -2        →  -1   （4 KB 而不是 8 KB）
```

---

## 19. 内存优化最佳实践

### 19.1 使用恰当的数据类型

**错误示例**：用 String 存储多个字段

```bash
# 错误：每个用户 3 个 Key
SET user:1001:name "Zhang"
SET user:1001:age  30
SET user:1001:city "Beijing"
# 内存：3 个 redisObject + 3 个 SDS = ~200 字节

# 正确：用 Hash 存储
HSET user:1001 name "Zhang" age 30 city "Beijing"
# 内存：1 个 redisObject + 1 个 listpack = ~80 字节
```

**错误示例**：用 String 存储位图

```bash
# 错误：每个用户 1 个 String
SETBIT online:2026-07-01 1001 1
# 内存：如果用户 ID 是 1~1000000，需要 122 KB

# 正确：用 Bitmap
SETBIT online:2026-07-01 1001 1
# 同上，但 Redis 的 Bitmap 就是 String，这里正确
# 关键是：用 SETBIT 而不是多个 SET
```

### 19.2 避免 Big Key

**Big Key 的危害**：
- 阻塞主线程（删除大 Key 耗时）
- 网络拥塞（一次传输大量数据）
- 复制延迟（主从同步慢）

**Big Key 的诊断**：

```bash
# 1. 扫描 Big Key
redis-cli --bigkeys

# 2. 查看 Key 的内存占用
MEMORY USAGE keyname

# 3. 查看 Key 的编码和元素数
DEBUG OBJECT keyname
```

**Big Key 的拆分策略**：

```
场景：一个 Hash 有 100 万个字段

拆分前：
  HSET bighash field1 value1 ... field1000000 value1000000
  → 1 个 Key，内存 ~200 MB

拆分后：
  HSET bighash:0  field1 value1 ... field1000 value1000
  HSET bighash:1  field1001 value1001 ... field2000 value2000
  ...
  HSET bighash:999 field999001 value999001 ... field1000000 value1000000
  → 1000 个 Key，每个 ~200 KB
```

### 19.3 使用 Hash 的 listpack 编码优化

**利用 Hash tag 强制多个 Key 在同一个 slot**（Redis Cluster）：

```bash
# 错误：3 个 Key 可能在 3 个 slot
HSET user:1001 name "Zhang"
HSET user:1001 age 30
HSET user:1001 city "Beijing"

# 正确：用 Hash tag 确保在同一个 slot
HSET user:{1001} name "Zhang"
HSET user:{1001} age 30
HSET user:{1001} city "Beijing"
# {} 内的部分用于计算 slot，所以 3 个命令都到同一个 slot
```

### 19.4 避免频繁编码转换

**编码转换的代价**：
- 需要**遍历所有元素**
- 需要**重新分配内存**
- 阻塞主线程

**避免策略**：

```bash
# 错误：先插入小数据，再插入大数据
SADD myset 1 2 3              # intset 编码
SADD myset "very_long_string"  # 转换为 HT 编码（O(N)）

# 正确：预估数据大小，提前用 HT 编码
# （但 Redis 不支持强制编码，只能接受转换）
```

---

## 20. 面试高频题

### 20.1 redisObject 相关

**Q1：redisObject 的好处是什么？**

```
答：redisObject 是 Redis 所有数据类型的"包装器"，好处有：
1. 统一接口：所有数据类型都是 redisObject，命令处理统一
2. 类型安全：type 字段防止对 String 执行 HGET
3. 编码灵活：encoding 字段允许同一种类型有多种底层实现
4. 内存优化：refcount 引用计数支持共享、lru 字段支持 LRU 淘汰
5. 直接存储整数：encoding=INT 时，ptr 直接存 long，不分配 SDS
```

**Q2：EMBSTR 和 RAW 编码的区别？**

```
答：
- EMBSTR：redisObject 和 SDS 连续存储（一次 malloc），≤44 字节时用
- RAW：redisObject 和 SDS 分开存储（两次 malloc），>44 字节时用
- 44 字节的来源：64 字节（jemalloc）- 16 字节（redisObject）- 3 字节（SDS header）- 1 字节（\0）= 44
```

### 20.2 SDS 相关

**Q3：SDS 对比 C 字符串有哪些优势？**

```
答：
1. O(1) 获取长度（len 字段）
2. 二进制安全（用 len 判断结束，不依赖 \0）
3. 预分配策略（减少内存分配次数）
4. 惰性空间释放（缩短时不立即释放内存）
5. 兼容 C 字符串（buf 末尾自动加 \0）
```

**Q4：SDS 的预分配策略是什么？**

```
答：
- 扩容时，如果新长度 < 1MB，预分配 2 倍
- 如果新长度 ≥ 1MB，预分配 新长度 + 1MB
- 目的：减少内存分配次数（N 次修改最多 N 次分配）
```

### 20.3 哈希表相关

**Q5：Redis 的 dict 如何扩容？**

```
答：
1. 触发条件：负载因子 ≥ 1（无 BGSAVE）或 ≥ 5（有 BGSAVE）
2. 扩容大小：size * 2（保持 2 的幂）
3. 渐进式 rehash：不是一次性迁移所有节点，而是每次增/删/改/查操作时顺带迁移一个 bucket
4. 为什么要渐进式：避免数据量大时阻塞主线程
```

**Q6：渐进式 rehash 期间，字典的查找/插入/删除如何工作？**

```
答：
1. 查找：先查 ht[0]，再查 ht[1]（如果正在 rehash）
2. 插入：只插入 ht[1]（不在 ht[0] 插入，避免 rehash 无限进行）
3. 删除：先删 ht[0]，再删 ht[1]
4. 每次操作都顺带迁移一个 bucket（dictRehashStep()）
```

### 20.4 跳表相关

**Q7：为什么 Redis 用跳表而不是红黑树实现 ZSet？**

```
答：
1. 实现简单：跳表实现比红黑树简单得多
2. 范围查询高效：跳表支持 O(log N + M) 范围查询，红黑树需要中序遍历
3. 支持无锁并发：跳表可以做到无锁并发（虽然 Redis 是单线程，但这是未来扩展的考虑）
4. 内存占用可控：跳表节点大小固定（不含数据），红黑树需要额外存储颜色位
```

**Q8：跳表节点的层数是怎么确定的？**

```
答：
1. 随机生成，使用幂次定理
2. 每次有 1/4 概率晋升到下一层
3. 最高 32 层（Redis 6.0 之前）/ 64 层（Redis 7.0）
4. 期望每层节点数：层 1 = 75%，层 2 = 18.75%，层 3 = 4.69%...
```

### 20.5 压缩列表相关

**Q9：ziplist 的级联更新问题是什么？listpack 如何解决的？**

```
答：
ziplist 的问题：
1. 每个 entry 有 prev_entry_len 字段（1 或 5 字节）
2. 如果前一个 entry 长度从 <254 变为 ≥254，当前 entry 的 prev_entry_len 需要从 1 字节扩展到 5 字节
3. 这可能导致连锁反应：后续所有 entry 的 prev_entry_len 都需要更新

listpack 的解决方案：
1. 去掉 prev_entry_len 字段
2. 每个 entry 有 entry-len 字段（记录本 entry 的长度）
3. 反向遍历时，通过 entry-len 计算前一个 entry 的位置
4. 彻底解决了级联更新问题
```

### 20.6 编码转换相关

**Q10：什么情况下 Hash 会从 listpack 转换为 HT 编码？**

```
答：满足以下任一条件时转换：
1. 字段数 > hash-max-listpack-entries（默认 128）
2. 任意字段名长度 > hash-max-listpack-value（默认 64 字节）
3. 任意值长度 > hash-max-listpack-value（默认 64 字节）

转换代价：O(N)，需要遍历所有字段并重新插入到 dict
```

---

# 附录

## 附录 A：5 种基础类型编码转换速查表

```
┌──────────────────────────────────────────────────────────────────────┐
│                   Redis 数据类型编码转换速查表                         │
├────────┬──────────────┬──────────────────────────────────────────────┤
│ 类型    │ 编码 1        │ 编码 2（转换触发条件）                      │
├────────┼──────────────┼──────────────────────────────────────────────┤
│ String │ INT（整数）    │ → RAW（执行字符串操作，如 APPEND）          │
│        │ EMBSTR（≤44B）│ → RAW（修改后长度 >44 或 执行写操作）       │
├────────┼──────────────┼──────────────────────────────────────────────┤
│ List   │ listpack      │ → quicklist（元素数 > 512 或 元素 >64B）  │
├────────┼──────────────┼──────────────────────────────────────────────┤
│ Hash   │ listpack      │ → HT（字段数 >128 或 字段/值 >64B）        │
├────────┼──────────────┼──────────────────────────────────────────────┤
│ Set    │ intset        │ → HT（插入非整数 或 元素数 >512）           │
├────────┼──────────────┼──────────────────────────────────────────────┤
│ ZSet   │ listpack      │ → skiplist+dict（元素数 >128 或 元素 >64B）│
└────────┴──────────────┴──────────────────────────────────────────────┘
```

---

## 附录 B：Redis 7 vs Redis 6 编码差异

```
┌──────────────────────────────────────────────────────────────────────┐
│                  Redis 7 vs Redis 6 编码差异                        │
├────────────┬─────────────────────────┬────────────────────────────┤
│ 特性         │ Redis 6                  │ Redis 7                     │
├────────────┼─────────────────────────┼────────────────────────────┤
│ List 编码   │ quicklist（单一）        │ listpack ←→ quicklist       │
│            │                         │ （小数据用 listpack）        │
├────────────┼─────────────────────────┼────────────────────────────┤
│ ziplist    │ 仍支持（已废弃）         │ 完全移除，只用 listpack      │
│            │                         │ （配置文件不再有 ziplist 参数）│
├────────────┼─────────────────────────┼────────────────────────────┤
│ SDS 类型   │ sdshdr5/8/16/32/64     │ 同左                        │
│            │ （sdshdr5 可用于短字符串）│ （sdshdr5 仍可用于短字符串） │
├────────────┼─────────────────────────┼────────────────────────────┤
│ 跳表层数   │ 最高 32 层               │ 最高 64 层                   │
├────────────┼─────────────────────────┼────────────────────────────┤
│ 配置参数   │ list-max-ziplist-entries │ list-max-listpack-entries    │
│            │ list-max-ziplist-value   │ list-max-listpack-value      │
│            │ （ziplist 参数仍可用）    │ （ziplist 参数已移除）       │
└────────────┴─────────────────────────┴────────────────────────────┘
```

**升级建议**：
- 如果用 Redis 7，配置文件中的 `*-max-ziplist-*` 参数需要改为 `*-max-listpack-*`
- 数据兼容：Redis 7 可以读取 Redis 6 的 RDB 文件（自动转换 ziplist → listpack）

---

## 附录 C：内存优化参数速查表

```
┌──────────────────────────────────────────────────────────────────────┐
│                  Redis 内存优化参数速查表                             │
├────────────────────────┬──────────┬───────────────────────────────┤
│ 参数                   │ 默认值    │ 调优建议                      │
├────────────────────────┼──────────┼───────────────────────────────┤
│ hash-max-listpack-entries        │ 128      │ 小 Hash 多：→ 512             │
│ hash-max-listpack-value          │ 64       │ 长字段名：→ 128               │
│ set-max-intset-entries         │ 512      │ 整数 Set 多：→ 1024           │
│ zset-max-listpack-entries       │ 128      │ 小 ZSet 多：→ 512             │
│ zset-max-listpack-value         │ 64       │ 长成员名：→ 128               │
│ list-max-listpack-entries       │ 512      │ 小 List 多：→ 1024            │
│ list-max-listpack-value         │ 64       │ 长元素：→ 128                 │
│ list-max-listpack-size          │ -2       │ 内存敏感：→ -1（4KB）        │
│ list-compress-depth             │ 0        │ 大 List：→ 1（压缩中间节点）   │
│ hll-sparse-max-bytes           │ 3000     │ 精确计数：→ 10000（延迟转换） │
└────────────────────────┴──────────┴───────────────────────────────┘
```

**参数查看**：

```bash
redis> CONFIG GET "*-max-*"
 1) "hash-max-listpack-entries"
 2) "128"
 3) "hash-max-listpack-value"
 4) "64"
 5) "set-max-intset-entries"
 6) "512"
 7) "zset-max-listpack-entries"
 8) "128"
 9) "zset-max-listpack-value"
10) "64"
```

**参数修改**（运行时）：

```bash
redis> CONFIG SET hash-max-listpack-entries 512
redis> CONFIG REWRITE   # 写入配置文件（永久生效）
```

---

## 附录 D：本文档与之前文档的衔接关系

```
┌──────────────────────────────────────────────────────────────────────┐
│                  Redis 文档在知识链路中的位置                          │
├──────────────────────────────────────────────────────────────────────┤
│  前置文档：                                                         │
│  - MySQL 索引底层原理 → 理解 B+Tree（Redis 跳表类似但更简单）       │
│  - MySQL 事务与锁 → 理解并发控制（Redis 单线程不需要锁）            │
│                                                                      │
│  本文档：                                                             │
│  - Redis 数据结构底层原理                                           │
│                                                                      │
│  后续建议学习的文档：                                                   │
│  - Redis 持久化（RDB/AOF）                                           │
│  - Redis 主从复制 + 哨兵                                           │
│  - Redis Cluster（数据分片）                                         │
│  - Redis 缓存策略（缓存穿透/击穿/雪崩）                              │
│  - Redis 分布式锁（SETNX/Redlock）                                  │
└──────────────────────────────────────────────────────────────────────┘
```

---

*文档结束*

> **下一步学习建议**：
> 1. 如果关注**高并发**：学习 Redis 分布式锁、缓存策略
> 2. 如果关注**高可用**：学习 Redis 主从复制、哨兵、Cluster
> 3. 如果关注**性能调优**：学习 Redis 内存优化、慢查询分析
> 4. 如果关注**面试**：重点掌握 redisObject、SDS、dict 渐进式 rehash、跳表


