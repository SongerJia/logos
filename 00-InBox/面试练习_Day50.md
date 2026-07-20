# 面试模拟 - Day 50

> 日期：2026-07-20（周一） | 模拟岗位：字节跳动（杭州）- 抖音支付/金融业务线 - Java开发工程师
> 建议时长：85分钟（一面55分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day50 里程碑！模拟字节跳动杭州研发中心——抖音支付/金融业务线。字节面试特点：计算机基础要求极扎实、追问底层原理到源码级别、系统设计题考架构思维而非堆技术名词。字节不问太多金融业务细节（不像银行系），但技术深度要求高，追问链长且连环。今天引入 MySQL 三大日志深入、Java 引用类型与 GC、Spring 循环依赖三级缓存、Redis 过期与淘汰机制、熔断器状态机原理等全新话题。

---

# 一面（55分钟）

## 话题一：MySQL 三大日志 - redo log / undo log / binlog（13分钟）

**面试官：你做过 MySQL 优化。MySQL 里有三个重要的日志——redo log、undo log、binlog。你能分别讲一下它们的作用和区别吗？**

> 你回答...

**追问1：** 先说 redo log。为什么要有 redo log？它解决了什么问题？

> 你回答...（提示：redo log = InnoDB 引擎层的日志 → 记录的是物理日志 → "在哪个页哪个偏移量做了什么修改" / 为什么需要 redo log：①Buffer Pool → InnoDB 修改数据先改内存中的 Buffer Pool → 不是直接写磁盘 → 如果宕机 → 内存数据丢失 → 已提交的事务数据丢失 ②WAL = Write-Ahead Logging → 先写日志再写数据 → 事务提交时 → 先把 redo log 刷盘 → 再异步刷数据页到磁盘 → 保证 Crash Safe / redo log 是循环写 → 固定大小 → 如配置 4 个文件每个 1GB → 共 4GB → 写满就从头开始 → 旧的可覆盖 / 为什么循环写：redo log 不是永久保存 → 只是保证宕机恢复 → 数据页刷盘后 redo log 就不需要了 → 循环写省空间 / binlog 是追加写 → 永久保存 → 用于主从复制和数据恢复 / redo log 是 InnoDB 独有 → binlog 是 Server 层 → 所有引擎都有）

**追问2：** 你说 WAL 先写日志再写数据。具体流程是什么？事务提交时先刷 redo log 还是先写 binlog？

> 你回答...（提示：事务执行流程：①修改 Buffer Pool 中的数据页 → ②生成 redo log 写入 redo log buffer → ③生成 undo log（用于回滚）→ ④执行器生成 binlog 写入 binlog cache → ⑤提交事务 / 两阶段提交（2PC）：①Prepare 阶段 → redo log 写入磁盘 + 标记 prepare → ②Commit 阶段 → binlog 写入磁盘 + redo log 标记 commit / 为什么两阶段提交：保证 redo log 和 binlog 的一致性 → 如果不用两阶段 → ①先写 redo log 后宕机 → binlog 没写 → 恢复后主库有数据但从库没有 → 主从不一致 ②先写 binlog 后宕机 → redo log 没写 → 恢复后主库回滚了事务但从库执行了 → 主从不一致 / 两阶段提交：①redo log prepare 后宕机 → 恢复时检查 binlog 有没有完整 → 有 → 提交 / 没有 → 回滚 ②binlog 写完但 redo log 没 commit → 恢复时检查 redo log 是 prepare 状态 → 检查 binlog → 有完整 binlog → commit redo log / 这就是为什么用两阶段提交 → 保证"要么都成功要么都失败"）

**追问3：** undo log 呢？它的作用是什么？和 MVCC 有什么关系？

> 你回答...（提示：undo log = 回滚日志 → InnoDB 引擎层 → 记录的是逻辑日志 → "修改前的数据是什么" → 反向操作 / 两个作用：①事务回滚 → 事务执行失败 → 用 undo log 恢复修改前的数据 ②MVCC → 多版本并发控制 → 读操作通过 undo log 构建数据的历史版本 → 实现快照读 / undo log 和 MVCC：每行数据有两个隐藏字段 → trx_id（最后修改的事务ID）+ roll_pointer（指向 undo log 的指针）→ undo log 记录旧版本 → 通过 roll_pointer 串成版本链 → ReadView 判断哪个版本可见 / insert 的 undo log → 事务提交后就可以删除（因为 insert 不需要 MVCC）→ update/delete 的 undo log → 要等没有事务再用这个旧版本时才能删除 → 所以长事务持有大量 undo log → 占空间 + 慢 / undo log 也会写满 → undo 表空间 → 独立表空间或系统表空间 → `innodb_undo_log_truncate=ON` 自动回收）

**追问4：** binlog 有哪些格式？各自的优缺点是什么？

> 你回答...（提示：binlog = Server 层日志 → 记录逻辑日志 → "执行了什么SQL" → 用于主从复制和数据恢复 / 三种格式：①Statement = 记录 SQL 语句 → 小 → 但某些函数如 NOW()/UUID() 在不同机器上结果不同 → 主从不一致 ②Row = 记录每行的变更前和变更后 → 大 → 但精确 → 不会不一致 ③Mixed = 混合 → 一般用 Statement → 遇到不安全的语句自动用 Row / 生产推荐 Row → 精确 → 但日志大 → 对于大量行的 update/delete → binlog 体积大 → 影响主从复制速度 / Statement → 小 → 但不安全 → MySQL 默认已不推荐 / binlog 主从复制流程：①主库写 binlog → ②dump 线程发给从库 → ③从库 IO 线程写 relay log → ④从库 SQL 线程重放 relay log → 数据一致 / 主从延迟 → 从库单线程重放 → 大事务（一个事务包含大量SQL）→ 从库要慢慢重放 → 延迟 / MySQL 5.7+ 并行复制 → 基于组提交 → 多线程重放）

**追问5：** 如果 MySQL 宕机重启，怎么恢复数据？redo log 和 binlog 的恢复顺序是什么？

> 你回答...（提示：Crash Recovery 流程：①MySQL 重启 → 读取 redo log → 找到所有已提交但未刷盘的数据页 → 重做（redo）→ 恢复到宕机前状态 ②检查 redo log 中处于 prepare 状态的事务 → 检查 binlog → binlog 完整 → 提交事务 / binlog 不完整 → 回滚事务 ③用 undo log 回滚未提交的事务 / 恢复顺序：先 redo（重做已提交的）→ 再 undo（回滚未提交的）→ 最后检查两阶段提交的悬挂事务 / redo log 是物理日志 → 重放快 → 直接改页 → undo log 是逻辑日志 → 逐条反向操作 → 慢 / 所以 Crash Recovery 主要是 redo log 的工作 → undo log 处理未提交事务 / 为什么 binlog 不能用于 Crash Recovery：binlog 是逻辑日志 → 没有记录"哪个页改了什么" → 无法直接恢复物理页 → binlog 是给从库用的 → redo log 才是 Crash Recovery 的核心 / `innodb_flush_log_at_trx_commit=1` → 每次提交都刷盘 → 最安全 → `sync_binlog=1` → binlog 每次提交都刷盘 → 双1配置 → 生产标准）

**追问6：** 你说的"双1配置"是什么意思？`innodb_flush_log_at_trx_commit` 设成 0 或 2 有什么风险？

> 你回答...（提示：双1 = `innodb_flush_log_at_trx_commit=1` + `sync_binlog=1` → 每次事务提交都把 redo log 和 binlog 刷到磁盘 → 最安全 / `innodb_flush_log_at_trx_commit`：①=1 → 每次提交刷盘 → 最安全 → 性能低 → 生产必选 ②=0 → 每秒刷盘 → 性能高 → 但宕机丢1秒数据 ③=2 → 每次提交写到 OS Cache → 每秒刷盘 → MySQL 崩溃不丢（OS Cache 还在）→ 但 OS 崩溃或断电丢1秒 / `sync_binlog`：①=1 → 每次提交刷盘 → 最安全 ②=0 → 由 OS 决定刷盘 → 性能高 → 断电丢 binlog ③=N → 攒 N 个事务刷一次 / 生产场景：①金融/核心 → 双1 → 安全第一 ②非核心 → =2 + sync_binlog=0 → 性能换安全 → 可接受秒级丢失 / 面试重点：知道双1是生产标准 + 理解 0/2 的风险 → 丢数据 → 哪怕1秒 → 金融也不可接受）

---

## 话题二：Java 引用类型与 GC（10分钟）

**面试官：Java 里有强引用、软引用、弱引用、虚引用四种引用类型。你了解它们吗？分别用在什么场景？**

> 你回答...

**追问1：** 强引用是什么？为什么我们平时写的代码都是强引用？

> 你回答...（提示：强引用 = Strong Reference → `Object obj = new Object()` → 默认就是强引用 → 只要强引用还在 → GC 绝不回收 → 即使 OOM 也不回收 → 宁可 OOM 也不回收强引用 / 强引用导致内存泄漏 → 长生命周期对象持有短生命周期对象的强引用 → 短对象无法回收 → 内存泄漏 → 如静态集合持有大量对象引用 / 防止泄漏 → 用完置 null → `obj = null` → 断开强引用 → 或用弱引用替代）

**追问2：** 软引用是什么？什么场景用软引用？

> 你回答...（提示：软引用 = SoftReference → `SoftReference<byte[]> ref = new SoftReference<>(new byte[1024*1024])` → 内存充足时不回收 → 内存不足时（快要 OOM）→ 才回收 / 特点：不是立刻回收 → 而是"内存不够了才回收" → 比 WeakReference 生命力强 / 场景：①内存敏感的缓存 → 如图片缓存 → Bitmap 占内存大 → 内存够用就留着 → 不够用就回收 → 自动适配内存 ②大对象缓存 → 如大文件内容 / 和弱引用区别：弱引用 → 下次 GC 就回收 → 不管内存够不够 → 软引用 → 内存够不回收 → 不够才回收 → 软引用更"舍不得"回收 / Java 的 -XX:SoftRefLRUPolicyMSPerMB → 控制软引用存活时间 → 堆越大软引用活得越久 / 实际项目：图片缓存框架（如 Glide）底层用软引用 + LRU → 软引用做二级缓存 → 内存不够自动释放图片）

**追问3：** 弱引用呢？ThreadLocal 里的 key 是什么引用？

> 你回答...（提示：弱引用 = WeakReference → 下次 GC 就回收 → 不管内存够不够 → 只要没有强引用指向对象 / `WeakReference<Object> weakRef = new WeakReference<>(new Object())` → 如果没有其他强引用指向这个 Object → 下次 GC 就被回收 / WeakHashMap → key 是弱引用 → key 没有强引用时 → entry 被自动清除 → 适合"关联对象和元数据" → 如 ClassLoader 缓存 / ThreadLocal 的 ThreadLocalMap → key 是弱引用 → `Entry extends WeakReference<ThreadLocal<?>>` → key 弱引用指向 ThreadLocal 对象 / ThreadLocal key 为什么用弱引用：①如果用强引用 → ThreadLocal 对象永远不会被回收 → 即使外部没有引用了 → 内存泄漏 ②用弱引用 → 外部 ThreadLocal 变量被置 null → ThreadLocalMap 的 key 弱引用 → 下次 GC 回收 key → key 变 null / 但问题：key 被回收了 → value 还是强引用 → value 不会被回收 → ThreadLocalMap 的 Entry(key=null, value=Object) → value 泄漏 → 解决：①用完 ThreadLocal 调 remove() → 主动清除 ②ThreadLocalMap 在 get/set 时清理 key=null 的 entry → 但不是实时的 / 所以 ThreadLocal 内存泄漏的核心：key 弱引用回收了但 value 没清理 → 必须 remove()）

**追问4：** 虚引用是什么？它有什么用？为什么感觉很少用到？

> 你回答...（提示：虚引用 = PhantomReference → 最弱的引用 → 形同虚设 → 通过 get() 永远返回 null → 无法通过虚引用获取对象 / 唯一作用：对象被 GC 回收时 → 收到一个通知（ReferenceQueue）→ 知道"这个对象被回收了" → 可以做清理工作 / 和其他引用区别：①强/软/弱引用 → get() 能拿到对象 ②虚引用 → get() 返回 null → 必须配合 ReferenceQueue 使用 / 场景：①NIO DirectByteBuffer → 堆外内存 → 不受 GC 管理 → 用虚引用 + Cleaner → 当 DirectByteBuffer 被 GC 回收时 → Cleaner 通知 → 释放堆外内存 → 否则堆外内存泄漏 ②资源清理 → 确保对象回收后释放关联资源 / 虚引用很少直接用 → 但 NIO 底层用了 → 面试能说出 DirectByteBuffer + Cleaner 就够 / 虚引用 vs finalize()：finalize() 也有"对象回收前清理"的功能 → 但 finalize() 已废弃（Java 9+）→ 不可靠（不确定何时执行）→ 用虚引用 + Cleaner 替代 → 更可控 / ReferenceQueue 工作原理：GC 回收弱/虚引用指向的对象时 → 把 Reference 对象放入 ReferenceQueue → 应用程序检查 Queue → 执行清理）

**追问5：** 你能总结一下四种引用的 GC 行为和应用场景吗？

> 你回答...（提示：| 引用类型 | GC 行为 | 应用场景 | / | 强引用 | 绝不回收，OOM 也不回收 | 默认所有引用 / | 软引用 | 内存不足时回收 | 图片缓存、大对象缓存 / | 弱引用 | 下次 GC 回收 | ThreadLocal key、WeakHashMap、缓存 / | 虚引用 | 对象回收时通知 | NIO 堆外内存清理、资源释放 / 记忆口诀：强→不回收 / 软→不够才回收 / 弱→下次就回收 / 虚→回收了告诉我 / 面试加分：能结合 ThreadLocal 讲弱引用 + 内存泄漏 + remove() → 能结合 DirectByteBuffer 讲虚引用 + 堆外内存清理 → 展示底层理解）

---

## 话题三：手写代码 - 反转链表（迭代+递归）（8分钟）

**面试官：反转一个单链表。先写迭代版本，再写递归版本。说思路再写。**

你在纸上/白板上写代码...

**追问1：** 迭代版本的思路是什么？用了几个指针？

> 你回答...（提示：迭代思路：三个指针 prev / curr / next / ①prev = null → curr = head ②遍历 → next = curr.next（保存下一个）→ curr.next = prev（反转指向）→ prev = curr（prev 前移）→ curr = next（curr 前移）③循环结束 → 返回 prev（新头节点）/ 时间 O(n) 空间 O(1) / 关键：先存 next 再改指向 → 不然改了 curr.next 后找不到原来的下一个 / 边界：空链表 → 返回 null / 单节点 → 不进循环 → 返回自己 / 面试标准答案 → 3分钟写完）

**追问2：** 递归版本怎么写？递归的思路是什么？

> 你回答...（提示：递归思路：reverseList(head) → 递归到最后一个节点 → 从后往前反转 / `ListNode reverseList(ListNode head) { if (head == null || head.next == null) return head; ListNode newHead = reverseList(head.next); head.next.next = head; head.next = null; return newHead; }` / 核心逻辑：reverseList(head) → 反转 head 之后的所有节点 → 返回新头（最后一个节点）/ 然后 head.next.next = head → 让下一个节点指向自己 → 反转 / head.next = null → 断开自己指向下一个 → 防止成环 / 时间 O(n) 空间 O(n) → 递归栈深度 / 递归版本更好理解但空间 O(n) → 迭代 O(1) 空间更优 → 生产用迭代）

**追问3：** 递归版本 `head.next.next = head` 这行代码是什么意思？为什么不会 NPE？

> 你回答...（提示：执行到这行时 → head.next 一定不为 null → 因为递归终止条件是 `head.next == null` 时直接返回 → 只有 head.next != null 才会走到 head.next.next = head / 例子：1→2→3→null / 递归到 3 → head.next == null → 返回 3 / 回到 2 → head.next = 3 → head.next.next = head → 3.next = 2 → 反转 2←3 / head.next = null → 2.next = null → 断开 / 回到 1 → head.next = 2 → head.next.next = head → 2.next = 1 → 2←1 / head.next = null → 1.next = null / 最终：3→2→1→null → 返回 newHead = 3 / 这行代码的含义：让"我的下一个"指向"我" → 实现反转）

**追问4：** 如果要求只反转链表的一部分（如从第 m 到第 n 个节点），你怎么做？

> 你回答...（提示：部分反转 = Reverse Linked List II / 思路：①遍历到第 m-1 个节点 → 记录 prev（m-1 节点）②从第 m 个开始反转 → 反转 n-m+1 个节点 → ③反转完后 → 第 m 个节点的 next 接第 n+1 个节点 → prev 的 next 接第 n 个节点（反转后的新头）/ 关键：记录反转段的前驱和后继 → 反转完拼接 / 边界：m == 1 → 没有前驱 → 用 dummy 虚拟头节点 → dummy.next = head → prev = dummy / 复杂度 O(n) 空间 O(1) / 面试能说出"加 dummy 处理 m=1 边界"就够 → 核心还是反转链表的能力）

**追问5：** 如果是 k 个一组反转链表（LeetCode 25）呢？思路？

> 你回答...（提示：k 个一组反转 → 每 k 个节点反转一次 → 不足 k 个不反转 / 思路：①遍历 → 数 k 个节点 → 如果不足 k → 不反转 → 返回 ②反转这 k 个 → 返回新头 ③上一个组的尾接这组的新头 → 递归处理剩余 / 关键：先判断够不够 k 个 → 够才反转 → 不够直接返回 / 反转 k 个：复用反转链表代码 → 但要记录反转段的头尾 → 尾接下一段的头 / 复杂度 O(n) → 每个节点访问一次 / k 个一组是反转链表的进阶版 → 面试常考 → 能写出基础反转 + k 个一组的思路就够 / 提示：先写基础反转保证对 → 再改 k 个一组 → 不要一上来就写 k 个一组容易出错）

---

## 话题四：Spring 循环依赖与三级缓存（12分钟）

**面试官：Spring 怎么解决循环依赖的？三级缓存你了解吗？**

> 你回答...

**追问1：** 什么是循环依赖？能举一个代码例子吗？

> 你回答...（提示：循环依赖 = A 依赖 B，B 依赖 A → 互相引用 / `@Service class A { @Autowired B b; }` / `@Service class B { @Autowired A a; }` / Spring 创建 A → 发现需要 B → 创建 B → 发现需要 A → 但 A 还没创建完 → 死循环 / Spring 用三级缓存解决 → 不是所有循环依赖都能解决）

**追问2：** 三级缓存分别是什么？每一级存的是什么？

> 你回答...（提示：三级缓存 → 三个 Map → DefaultSingletonBeanRegistry 中 / 一级缓存 singletonObjects：存完整的 Bean → 完成实例化+属性注入+初始化 → 可以直接用 / 二级缓存 earlySingletonObjects：存"提前暴露的半成品 Bean" → 只完成实例化 → 还没属性注入和初始化 / 三级缓存 singletonFactories：存 ObjectFactory → 对象工厂 → 调用 getObject() 才创建半成品 → 支持 AOP 代理 / 为什么三级不是两级：核心是为了处理 AOP → 如果没有 AOP → 两级就够了（一级完整+二级半成品）→ 三级缓存的 ObjectFactory → 调用时才判断要不要创建代理 → 延迟代理创建）

**追问3：** 解决循环依赖的完整流程是什么？A 依赖 B，B 依赖 A，走一遍。

> 你回答...（提示：①创建 A → 实例化 A（调构造器）→ A 是半成品 ②把 A 的 ObjectFactory 放入三级缓存 singletonFactories ③填充 A 的属性 → 发现需要 B ④去一级缓存找 B → 没有 → 创建 B ⑤实例化 B → B 是半成品 ⑥把 B 的 ObjectFactory 放入三级缓存 ⑦填充 B 的属性 → 发现需要 A ⑧去一级缓存找 A → 没有 → 去二级缓存找 A → 没有 → 去三级缓存找 A 的 ObjectFactory → 找到 → 调用 getObject() → 得到半成品 A（如果有 AOP → 这里创建代理）→ 放入二级缓存 → 删除三级缓存中的 A ⑨B 拿到半成品 A → 完成属性注入 → B 初始化完成 → B 放入一级缓存 → 删除二三级缓存中的 B ⑩回到 A → 拿到完成的 B → 完成属性注入 → A 初始化完成 → A 放入一级缓存 / 关键：A 提前暴露半成品 → B 能拿到 A 的半成品 → 打破循环 / 注意：B 拿到的是 A 的半成品引用 → A 后续完成初始化 → B 持有的引用自动指向完成的 A → 因为是同一个对象引用）

**追问4：** 三级缓存中的 ObjectFactory 是什么？为什么需要它？

> 你回答...（提示：ObjectFactory = 对象工厂 → lambda 表达式 → `() -> getEarlyBeanReference(beanName, mbd, bean)` / getEarlyBeanReference 做什么：①检查有没有 AOP 代理需要创建 ②如果有 AOP → 提前创建代理对象 → 返回代理 ③如果没有 AOP → 直接返回原始对象 / 为什么需要 ObjectFactory 而不是直接存半成品：①如果没有 AOP → 可以直接存半成品到二级缓存 → 不需要三级 ②有 AOP 时 → A 需要 B 注入的是代理对象而不是原始对象 → 但 A 还没到初始化完成阶段 → AOP 代理通常在初始化后创建（BeanPostProcessor.postProcessAfterInitialization）→ 但循环依赖时 B 需要 A → B 需要的是代理后的 A → 所以必须提前创建代理 → ObjectFactory 就是"延迟到需要时才创建代理" / 如果直接存半成品 → B 注入的是原始 A → 后续 A 被 AOP 代理了 → B 持有的还是原始 A → 不一致 / ObjectFactory 解决：需要时才创建代理 → 保证 B 拿到的是代理后的 A）

**追问5：** 什么情况下 Spring 无法解决循环依赖？

> 你回答...（提示：三种无法解决的情况：①构造器循环依赖 → A 的构造器需要 B → B 的构造器需要 A → 实例化阶段就需要对方 → 还没到暴露半成品的阶段 → 无法解决 → Spring 启动报错 / ②prototype 作用域循环依赖 → prototype 每次创建新实例 → 不缓存 → 没有三级缓存 → 无法解决 / ③@Async 循环依赖 → @Async 在初始化后创建代理 → 和三级缓存提前创建代理冲突 → Spring 6.0 之前可能报错 → 需要加 @Lazy / 构造器循环依赖的解决：①加 @Lazy → 注入代理 → 真正使用时才创建 ②重构 → 避免构造器互相依赖 ③用 setter/字段注入代替构造器注入 / 面试加分：能说出"只有 setter 注入和字段注入的单例 Bean 循环依赖才能解决 → 构造器注入不行" → 展示对 Spring 生命周期的理解 / Spring 4.3+ → 构造器注入如果是 @Autowired(required=false) → 可以回退到 setter 注入 → 但不推荐）

**追问6：** Spring Boot 2.6+ 默认禁止了循环依赖，你知道吗？为什么？

> 你回答...（提示：`spring.main.allow-circular-references=false` → Spring Boot 2.6 默认 false → 禁止循环依赖 / 原因：①循环依赖是设计问题 → 说明类之间的耦合不合理 → 应该重构 ②三级缓存解决循环依赖是 Spring 的"妥协"→ 不是好的设计 → 官方不鼓励 ③@Async/AOP 场景 → 三级缓存不完全可靠 → 可能出现诡异问题 / 如果确实需要循环依赖 → 手动设 `allow-circular-references=true` → 但建议重构 → 用事件机制/中间层解耦 / 面试能说出"循环依赖是设计缺陷 → Spring 官方也不鼓励 → 2.6+ 默认禁止" → 展示对设计原则的理解）

---

## 话题五：Redis 过期策略与内存淘汰机制（12分钟）

**面试官：你前面讲了 Redis 持久化。Redis 里设置了过期时间的 key，Redis 是怎么过期的？内存满了怎么办？**

> 你回答...

**追问1：** Redis 怎么判断 key 过期了？是到时间了立刻删除吗？

> 你回答...（提示：Redis 过期策略 = 定期删除 + 惰性删除 / 定期删除：Redis 每秒执行 10 次 → 每次随机抽取 20 个设置了过期时间的 key → 检查是否过期 → 过期的删除 → 如果这 20 个中超过 25% 过期 → 再抽 20 个继续删 → 直到比例下降或时间用完 / 为什么不是全部检查：如果所有 key 都检查 → 性能差 → 所以随机抽样 → 概率上大部分过期 key 会被删到 / 惰性删除：客户端访问某个 key → Redis 检查是否过期 → 过期了 → 删除并返回 null / 为什么需要惰性删除：定期删除是概率性的 → 可能有些过期 key 没被抽到 → 还留在内存 → 等下次被访问时 → 惰性删除兜底 / 两者结合 → 定期删除主动清 + 惰性删除被动清 → 但还是可能有"漏网之鱼"→ 既没被定期删到也没被访问 → 一直占内存 → 这时就需要内存淘汰机制）

**追问2：** 如果过期 key 既没被定期删除删到，也没被访问（惰性删除），内存占用越来越高怎么办？

> 你回答...（提示：这就是内存淘汰机制的作用 / 当 Redis 内存使用达到 `maxmemory` 限制时 → 触发淘汰策略 / Redis 有 8 种淘汰策略（Redis 4.0+）：①noeviction → 不淘汰 → 写操作报错 → 读正常 → 默认 ②allkeys-lru → 所有 key 中淘汰最近最少使用的 ③allkeys-lfu → 所有 key 中淘汰最不经常使用的（Redis 4.0+）④allkeys-random → 随机淘汰 ⑤volatile-lru → 有过期时间的 key 中淘汰 LRU ⑥volatile-lfu → 有过期时间的 key 中淘汰 LFU ⑦volatile-random → 有过期时间的 key 中随机淘汰 ⑧volatile-ttl → 有过期时间的 key 中淘汰 TTL 最短的（快过期的优先删）/ 生产推荐：①缓存场景 → allkeys-lru 或 allkeys-lfu → 缓存淘汰 ②混合使用 → 有持久数据+缓存 → volatile-lru → 只淘汰有过期时间的 → 不影响持久数据 ③纯缓存 → allkeys-lru / noeviction 不推荐 → 内存满了写报错 → 影响业务 / Redis 7.0 新增 LFU 实现 → 更精确统计访问频率 → 比 LRU 更好 → 但 LRU 更简单 → 大多数场景 LRU 够用）

**追问3：** Redis 的 LRU 是怎么实现的？和标准 LRU 算法有什么区别？

> 你回答...（提示：标准 LRU → LinkedHashMap → 双向链表 + HashMap → O(1) get/put → 淘汰链表尾部 / Redis LRU → 不是标准 LRU → 近似 LRU → ①每个 key 有一个 LRU 时钟 → 记录最后访问时间 → 24bit 时间戳 ②淘汰时 → 随机采样 N 个 key → 淘汰其中最久没用的 → `maxmemory-samples` 默认 5 → 可以调大到 10 提高精度 / 为什么不用标准 LRU：①标准 LRU 需要维护双向链表 → 内存开销大 → 每个 key 额外指针 ②Redis 数据量大 → 百万级 key → 链表操作性能差 ③近似 LRU → 采样 → 精度够用 → 内存开销小 / 采样数越大 → 越接近标准 LRU → 但 CPU 开销越大 → 5 是性能和精度的平衡 / Redis 4.0 LFU → 每个 key 维护一个计数器 → 记录访问频率 → 按频率淘汰 → 但计数器会衰减 → 防止"曾经热现在冷"的 key 永远不被淘汰 → 8bit 计数器 + 衰减因子 / 面试能说出"Redis 用近似 LRU → 采样而不是链表 → 内存开销小但精度够" → 就够）

**追问4：** volatile-lru 和 allkeys-lru 怎么选？什么场景用哪个？

> 你回答...（提示：volatile-lru → 只在设置了过期时间的 key 中淘汰 → 持久数据（没设过期的）不会被淘汰 / allkeys-lru → 所有 key 都可能被淘汰 / 选择：①纯缓存 → allkeys-lru → 所有 key 都是缓存 → 都可以淘汰 ②缓存+持久数据混用 → volatile-lru → 只淘汰缓存（有过期的）→ 不影响持久数据 ③有持久数据但不想混 → 分两个 Redis 实例 → 一个做缓存（allkeys-lru）→ 一个做持久（noeviction + 持久化）/ 常见误区：①以为 Redis 是缓存 → 但有些项目把 Redis 当数据库用 → 不设过期 → allkeys-lru 会淘汰持久数据 → 数据丢失 ②以为 volatile-lru 只淘汰快过期的 → 不是 → volatile-lru 在有过期时间的 key 中淘汰最近最少使用的 → 不是淘汰快过期的 → volatile-ttl 才是淘汰快过期的 / 面试能区分 volatile-lru（LRU 在过期key中）和 volatile-ttl（TTL最短优先）→ 就够）

**追问5：** 如果 Redis 内存满了但淘汰策略是 noeviction，写操作报错了怎么办？生产怎么处理？

> 你回答...（提示：noeviction → 写操作返回 OOM 错误 → `(error) OOM command not allowed when used memory > 'maxmemory'` / 生产处理：①监控内存使用率 → 告警阈值 80% → 提前扩容 ②调大 maxmemory → 临时方案 → 如果机器内存还有 ③换成淘汰策略 → allkeys-lru → 让 Redis 自动淘汰 / 根本原因：noeviction 不适合做缓存 → 做缓存应该用淘汰策略 → noeviction 适合做持久存储（配合 AOF/RDB）/ 生产建议：①Redis 做缓存 → 设 maxmemory + allkeys-lru → 自动管理内存 ②Redis 做持久存储 → 设 maxmemory + noeviction + 开 AOF → 内存不够时加节点 → 不是靠淘汰 ③监控 → Prometheus + Grafana → 内存使用率 + 淘汰次数 + 过期 key 数量 → 持续关注 / 内存淘汰导致的问题：①缓存雪崩 → 大量 key 被淘汰 → 请求穿透到 DB → 解决：限流 + 互斥锁 ②数据丢失 → volatile-lru 淘汰了不该淘汰的 → 解决：调大采样数 + 合理设过期时间）

---

# 二面（30分钟）

## 话题六：熔断器原理与断路器状态机（10分钟）

**面试官：你们用 Sentinel 做熔断降级。熔断器的状态机你了解吗？半开状态是干什么用的？**

> 你回答...

**追问1：** 熔断器有哪几个状态？各自什么含义？

> 你回答...（提示：三个状态：①Closed（关闭）→ 正常状态 → 请求正常通过 → 统计失败率 ②Open（打开）→ 熔断 → 请求直接拒绝/走降级 → 不调后端 ③Half-Open（半开）→ 探测 → 放少量请求通过 → 探测后端是否恢复 / 状态流转：Closed → 失败率超过阈值 → Open / Open → 等待一段时间（熔断恢复时间，如5秒）→ Half-Open / Half-Open → 探测成功 → Closed（恢复正常）→ 探测失败 → Open（继续熔断）/ 为什么需要 Half-Open：如果 Open → 等时间到 → 直接 Closed → 大量请求涌入 → 如果后端还没恢复 → 又打挂 → 又熔断 → 反复 → 资源浪费 / Half-Open → 只放少量请求 → 如果成功 → 说明恢复了 → 再全量恢复 → 如果失败 → 继续熔断 → 保护后端 / 这就是"试探性恢复"→ 避免后端刚恢复就被打回去）

**追问2：** 熔断和降级是一回事吗？有什么区别？

> 你回答...（提示：熔断 = Circuit Breaker → 主动保护机制 → 统计失败率 → 超阈值自动熔断 → 不调用后端 → 快速失败 → 保护调用方 / 降级 = Fallback → 熔断后或异常后的"退路"→ 返回默认值/缓存/友好提示 → 保证用户体验 / 关系：熔断是"触发条件" → 降级是"处理方式" / 熔断后走降级 → 熔断 + 降级配合使用 / 降级不一定要熔断触发 → 也可以主动降级：①大促期间 → 关闭非核心功能（如推荐/评论）→ 降级 ②依赖服务响应慢 → 主动降级 → 返回缓存 / 降级策略：①返回默认值 → 如默认推荐列表 ②返回缓存 → 如查询结果 ③返回空 → 如列表返回空 ④异步化 → 同步转异步 → "处理中，请稍后" / 面试能说出"熔断是触发 → 降级是处理 → 熔断后通常走降级" → 就够 / Sentinel 中：熔断规则 → 触发熔断 → 走 @SentinelResource 的 blockHandler 或 fallback → 就是降级）

**追问3：** Sentinel 的熔断策略有哪些？和 Hystrix 有什么区别？

> 你回答...（提示：Sentinel 熔断策略三种：①慢调用比例 → 响应时间 > 阈值的视为慢调用 → 慢调用比例 > 阈值 → 熔断 ②异常比例 → 异常比例 > 阈值 → 熔断 ③异常数 → 异常数 > 阈值 → 熔断 / Hystrix 熔断：主要基于异常比例 → 不支持慢调用比例 / Sentinel vs Hystrix：①Sentinel → 阿里 → 流控+熔断+系统自适应 → 更丰富 ②Hystrix → Netflix → 已停止维护 → 熔断+隔离（线程池/信号量）③Sentinel → 滑动窗口统计 → Hystrix → 滑动窗口 ④Sentinel → 支持慢调用比例 → Hystrix → 不支持 ⑤Sentinel → 控制台动态配置 → Hystrix → 配置在代码里 ⑥Sentinel → 没有线程隔离 → Hystrix → 有线程池隔离 / 隔离策略：Hystrix → 线程池隔离/信号量隔离 → 每个服务用独立线程池 → 故障不蔓延 → 但线程开销大 → Sentinel → 信号量隔离 → 不用额外线程 → 轻量 / 生产：Sentinel 逐步替代 Hystrix → Spring Cloud Alibaba 生态）

**追问4：** 熔断恢复时间怎么设置？设太短和设太长有什么问题？

> 你回答...（提示：熔断恢复时间 = Time Window → Open 状态持续时间 → 到了进入 Half-Open / 设置策略：①太短 → 后端还没恢复 → Half-Open 放请求 → 又失败 → 继续熔断 → 反复试探 → 浪费 / ②太长 → 后端恢复了但熔断还没解除 → 用户请求被拒绝 → 不必要的降级 → 影响体验 / 经验值：①一般 5-30 秒 → 根据后端恢复速度 ②如果是 DB 连接池打满 → 恢复快 → 5 秒 ③如果是下游服务重启 → 恢复慢 → 30 秒 ④如果是外部依赖（如第三方API）→ 不确定 → 10-15 秒 / Sentinel 默认熔断恢复时间 → `timeWindow` 参数 → 可动态调整 / 最佳实践：①先设短（5秒）→ 如果反复 Half-Open 失败 → 说明后端问题严重 → 调大 ②监控 → Half-Open 成功率 → 恢复后全量流量 → 不打回来 / 连锁熔断 → A 熔断 → B 依赖 A → B 也熔断 → 雪崩 → 解决：关键链路设合理的熔断 → 非关键降级 → 避免连锁 / 面试加分：能说出"熔断恢复时间要根据后端恢复速度设 → 太短反复试探 → 太长影响体验 → 经验值 5-30 秒"→ 展示工程经验）

**追问5：** 你说熔断保护调用方。但如果服务 A 调 B 调 C，B 熔断了，C 还在跑，怎么办？C 做的工作不是白做了？

> 你回答...（提示：场景：A → B → C → B 熔断 → A 的请求到 B → B 直接返回（熔断）→ 不到 C → 但 B 之前的请求还在 C 跑 → C 执行完返回 B → B 已熔断 → C 的结果浪费 / 问题：①C 的工作白做 → 资源浪费 ②C 如果有副作用（如扣库存/写DB）→ 操作已执行 → 但结果没返回给用户 → 不一致 / 解决：①超时控制 → A 调 B 设超时 → B 调 C 设超时 → B 熔断 → C 的请求超时 → C 放弃 → 减少浪费 ②Cancel 传播 → 类似 gRPC 的 cancellation → A 取消 → B 取消 → C 取消 → 链式取消 → 但 Java 原生不支持 → 需要框架支持 ③C 做幂等 → 即使 C 执行了 → 用户重试 → 幂等 → 不重复操作 / 实际：大多数微服务框架 → 熔断 + 超时配合 → 超时比熔断恢复快 → 超时先触发 → C 的请求超时 → 不会等到完成 / 最终一致：如果 C 有副作用 → 消息补偿 → 如果 C 扣了库存但 B 熔断了 → 定时对账 → 发现库存扣了但订单没创建 → 回退 / 面试重点：能说出"熔断只是保护调用方 → 被调用方的进行中操作可能浪费 → 需要超时+幂等+补偿配合"→ 展示分布式系统的复杂性理解）

---

## 话题七：核心设计题 - 分布式 ID 生成系统（20分钟）

**面试官：你们微服务架构下，不同服务都要生成唯一 ID（订单号、流水号、用户ID等）。如果让你设计一个分布式 ID 生成系统，要求全局唯一、趋势递增、高可用、每秒生成百万级 ID，你怎么设计？**

你在纸上画架构图/说思路...

**追问1：** 先说说你知道的分布式 ID 方案有哪些？各自的优缺点？

> 你回答...（提示：四种主流方案：①UUID → 优点：本地生成无网络开销 → 缺点：无序 → 不适合做数据库主键（B+树插入碎片页分裂）→ 太长（36字符）→ 占空间 / ②数据库自增 → 单点 → 性能瓶颈 → 主从延迟 → 从库ID重复 / ③号段模式（如美团 Leaf）→ 中心化发号 → 每次取一批号（如1000个）→ 用完再取 → 高性能 → 趋势递增 → 但中心化依赖 → 需要高可用 / ④雪花算法（Snowflake）→ 去中心化 → 本地生成 → 64位 → 时间戳+机器ID+序列号 → 趋势递增 → 但依赖时钟 → 时钟回拨问题 / 选型：①不需要递增 → UUID（如 traceId）②需要递增+高性能 → 雪花算法（大多数场景）③需要严格递增+号段管理 → Leaf 号段 ④超高并发+多机房 → Leaf Snowflake / 面试标准答案：能对比4种方案 → 选雪花或Leaf → 理由充分）

**追问2：** 雪花算法的 64 位怎么分配的？每一部分是什么？

> 你回答...（提示：64 位 = 1bit 符号位 + 41bit 时间戳 + 10bit 机器ID + 12bit 序列号 / ①符号位 1bit → 永远 0 → 正数 / ②时间戳 41bit → 毫秒级 → 41bit 可以表示 2^41 / 1000 / 3600 / 24 / 365 ≈ 69 年 → 够用 / ③机器ID 10bit → 2^10 = 1024 台机器 → 可以拆成 5bit 数据中心 + 5bit 机器 → 32 个机房 × 32 台机器 = 1024 / ④序列号 12bit → 2^12 = 4096 → 每台机器每毫秒最多生成 4096 个ID → 单机 QPS 400万 / 理论上：1024 台机器 × 每毫秒 4096 = 每秒 41 亿 ID → 完全够用 / 时间戳是高位 → ID 趋势递增 → 同一毫秒内序列号递增 → 局部有序 / 数据库主键友好 → B+树插入有序 → 页不分裂 → 性能好）

**追问3：** 雪花算法的时钟回拨问题是什么？怎么解决？

> 你回答...（提示：时钟回拨 = 机器时间突然倒退 → 如 NTP 同步 → 时间从 10:00:00 跳到 09:59:58 → 回拨2秒 / 问题：时间戳回退 → 新生成的ID比之前的ID小 → 不再递增 → 违反"趋势递增" → 更严重 → 可能和之前生成的ID重复（同时间戳+同序列号）/ 解决方案：①等待 → 回拨时间短（如<5ms）→ 等待回拨时间过去 → 再生成 → 简单但影响性能 ②使用历史最大时间戳 → 记录上次生成的时间戳 → 如果当前时间 < 上次 → 用上次时间戳+1 → 递增 → 但如果一直回拨 → 时间戳越来越大 → 偏离真实时间 ③备用机房/机器 → 时钟回拨严重 → 暂停服务 → 切到备用 ④Bits 拨用 → 一些变种方案：把时间戳精度降低 → 留出回拨缓冲 → 但减少可用时间 / 生产常用：方案② + 监控告警 → 回拨超过阈值（如1秒）→ 告警 → 运维介入 → NTP 配置 → `ntpdate` 不要大幅调整 → 用 `ntpd` 渐进同步 / Leaf Snowflake 方案 → 用 ZooKeeper 持久化上次时间戳 → 启动时对比 → 如果当前时间 < 上次 → 等待 → 解决重启后的时钟回拨 / 面试能说出"时钟回拨导致ID不递增或重复 → 记录上次时间戳 → 用上次+1 → 监控告警"→ 就够）

**追问4：** 美团 Leaf 号段模式是什么？和雪花算法有什么区别？

> 你回答...（提示：Leaf 有两种模式：①Leaf Segment（号段模式）②Leaf Snowflake / Leaf Segment 原理：①中心数据库存一个表 → biz_tag + max_id + step → 如 order 业务的 max_id=1000, step=1000 ②应用启动 → 从 DB 取一批号 → max_id ~ max_id+step → 用 max_id+step 更新 DB → 本地用这1000个号 ③用完再取 → 每次取一批 → DB 压力小 / 优点：①严格递增 → 不是趋势递增 → 是严格递增 ②高性能 → 本地发号 → 无网络开销 ③简单 → 不依赖时钟 / 缺点：①中心化 → DB 是瓶颈 → 但号段模式 → 每次取一批 → DB QPS 低 ②重启丢号 → 本地号段没发完 → 重启 → 丢掉 → 但可以接受 → 间隔大 → 不影响业务 ③ID 可预测 → 如果 step=1000 → ID 以 1000 为单位跳 → 不安全 → 解决：随机步长 / Leaf Segment 双 Buffer：①当前 Buffer 用到 10% → 异步加载下一个 Buffer ②切换时无缝 → 不停服 → 高可用 / Leaf Snowflake：解决时钟回拨 → 用 ZK 持久化 → 和普通雪花算法一样 + ZK 时间戳校验 / 选型：①要严格递增 → Leaf Segment ②要高性能+去中心化 → 雪花算法 ③要多机房+高可用 → Leaf Snowflake / 实际：美团/小米用 Leaf → 大多数公司用雪花算法变种 → 简单够用）

**追问5：** 如果要求 ID 不能被猜测（如优惠券码、分享链接），你怎么设计？

> 你回答...（提示：雪花算法 → 趋势递增 → 可以猜 → 如订单号 100001 → 下一个 100002 → 猜出单量 / 需要不规则ID：①雪花算法 → 打乱 → 把序列号和机器ID的位置互换 → 或加随机偏移 → 但破坏递增性 ②UUID → 天然不规则 → 但不适合DB主键 ③发号器 → 生成雪花ID → 再加密/混淆 → 如 Base62 编码 + 位运算混淆 → 不直接暴露原始ID ④业务层 → 生成内部ID → 用加密算法（如 AES/Hashids）→ 生成对外短码 → 内外映射 / 实际场景：①分享链接 → ID → Base62 → 短链接 → 如 t.cn/abc123 ②优惠券码 → 内部ID → 随机替换位 → 不规则 ③订单号 → 可以递增（用户看到订单号不影响安全）→ 但不能暴露总单量 → 加随机前缀 / Hashids → 开源库 → 把整数ID → 混淆成字符串 → 可解码 → 适合不暴露数量的场景 / 安全要求高 → 不用雪花算法 → 用 UUID 或加密混淆 → 但牺牲递增和性能 / 面试能说出"雪花ID可猜测 → 需要加密混淆或UUID → 但牺牲递增性 → 根据安全需求选"→ 展示安全意识）

**追问6：** 你设计这个分布式 ID 系统，怎么保证高可用？如果发号服务挂了怎么办？

> 你回答...（提示：方案对比：①雪花算法 → 去中心化 → 每台机器本地生成 → 服务挂了不影响 → 最高可用 → 但有时钟回拨问题 ②Leaf Segment → 中心化 DB → DB 挂 → 发不了号 → 但双 Buffer → 一段时间内不需要 DB → 缓冲 → 加 DB 主从 → 高可用 ③Leaf Snowflake → ZK + 本地 → ZK 挂 → 本地继续生成（但不持久化）→ 恢复后校验 / 高可用设计：①雪花算法 → 去中心化 → 每个服务本地生成 → 无单点 → 最高可用 → 推荐 ②Leaf → DB 主从 + 双 Buffer → 应用层高可用 → DB 挂 → Buffer 支撑 → DB 恢复 ③监控 → 发号延迟、ID 重复率、时钟偏差 → 告警 ④降级 → 发号服务完全不可用 → 本地 UUID → 牺牲递增 → 保证可用 / 容灾：①多机房 → 每个机房独立发号 → 机器ID不同 → 不冲突 ②ID 冲突检测 → 如果重复 → 告警 → 人工介入 ③审计 → ID 生成日志 → 可追溯 / 面试标准答案："雪花算法是去中心化的 → 天然高可用 → 不依赖中心服务 → 每台机器独立生成 → 每秒百万级 → 如果有时钟回拨 → 记录上次时间戳+监控告警 → Leaf 号段模式中心化但双Buffer缓冲 → DB 高可用 → 两种方案都能满足 → 根据是否需要严格递增选择"→ 展示系统设计能力）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| MySQL 三大日志（redo/undo/binlog） | 能讲清 / 讲不全 / 不会★ | |
| Java 引用类型与 GC | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（反转链表 迭代+递归） | 能讲清 / 讲不全 / 不会★ | |
| Spring 循环依赖三级缓存 | 能讲清 / 讲不全 / 不会★ | |
| Redis 过期策略与内存淘汰 | 能讲清 / 讲不全 / 不会★ | |
| 熔断器状态机原理 | 能讲清 / 讲不全 / 不会★ | |
| 分布式 ID 生成系统设计 | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **MySQL 三大日志**是数据库面试的深水区。redo log = InnoDB 物理日志 → WAL 先写日志再写数据 → 循环写 → Crash Safe。undo log = 逻辑日志 → 回滚 + MVCC 版本链。binlog = Server 层逻辑日志 → 主从复制 + 数据恢复 → 三种格式（Statement/Row/Mixed）→ 生产用 Row。两阶段提交：redo log prepare → binlog → redo log commit → 保证主从一致。Crash Recovery：先 redo（重做已提交）→ 再 undo（回滚未提交）→ 检查悬挂事务。双1配置 = `innodb_flush_log_at_trx_commit=1` + `sync_binlog=1` → 生产标准
> 2. **Java 四种引用**：强（不回收）、软（内存不足回收→图片缓存）、弱（下次GC回收→ThreadLocal key）、虚（回收通知→NIO堆外内存清理）。ThreadLocal 内存泄漏：key 弱引用被回收但 value 强引用没清理 → 必须 remove()。虚引用配合 ReferenceQueue + Cleaner → DirectByteBuffer 堆外内存释放
> 3. **反转链表**经典题。迭代：三指针 prev/curr/next → 存next → 反转指向 → 前移 → O(n) O(1)。递归：`head.next.next = head` → 让下一个指向自己 → O(n) O(n)递归栈。k个一组反转：先判断够不够k → 够才反转 → 复用反转代码
> 4. **Spring 循环依赖三级缓存**：一级 singletonObjects（完整Bean）→ 二级 earlySingletonObjects（半成品Bean）→ 三级 singletonFactories（ObjectFactory，延迟AOP代理）。流程：A实例化→放入三级缓存→A需要B→创建B→B需要A→三级缓存取A的ObjectFactory→调getObject()得到半成品A（如有AOP则创建代理）→放入二级缓存→B完成→B入一级缓存→A拿到B→A完成→A入一级缓存。无法解决：构造器循环依赖、prototype 作用域。Spring Boot 2.6+ 默认禁止循环依赖 → 设计缺陷
> 5. **Redis 过期与淘汰**：过期 = 定期删除（每秒10次×20个key抽样）+ 惰性删除（访问时检查）。淘汰 = 内存达 maxmemory 时触发 → 8种策略 → 生产推荐 allkeys-lru（纯缓存）或 volatile-lru（混合）。Redis 用近似 LRU（采样N个淘汰最旧）→ 不用标准LRU链表 → 省内存。LFU 按访问频率+衰减。noeviction 内存满写报错 → 适合持久存储不适合缓存
> 6. **熔断器三态**：Closed（正常统计）→ Open（熔断拒绝）→ Half-Open（探测恢复）。Half-Open 放少量请求试探 → 成功→Closed / 失败→Open。熔断是触发 → 降级是处理。Sentinel 三种策略：慢调用比例/异常比例/异常数。熔断恢复时间 5-30 秒 → 太短反复试探 → 太长影响体验。连锁熔断 → 雪崩 → 需要合理熔断+降级+超时配合
> 7. **分布式 ID 设计**：UUID（无序不适合DB主键）/ DB自增（单点瓶颈）/ 雪花算法（去中心化 64位=1+41+10+12 单机400万QPS 趋势递增 但时钟回拨）/ Leaf号段（中心化双Buffer 严格递增 但DB依赖）。雪花算法时钟回拨：记录上次时间戳→用上次+1→监控告警。不可猜测需求：雪花可猜测→加密混淆或UUID。高可用：雪花去中心化最高 → Leaf双Buffer+DB高可用。选型：一般用雪花 → 需要严格递增用Leaf