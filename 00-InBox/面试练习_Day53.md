# 面试模拟 - Day 53

> 日期：2026-07-23（周四） | 模拟岗位：蚂蚁集团（杭州总部）- 三面/终面 - 高级Java开发工程师
> 建议时长：85分钟（一面55分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day53，"查漏补缺"阶段第三周。模拟蚂蚁集团三面/终面——高级架构师或技术总监面。蚂蚁三面特点：不再问"是什么"而问"为什么这么设计"，追问极深且连环，考的是你是真理解还是背的八股文。一个话题能聊15分钟以上。今天引入 MySQL InnoDB 锁机制全景、Redis 数据结构底层实现、Spring AOP 原理深入、ReentrantLock 源码、分布式理论 CAP/BASE 五个之前没有作为独立话题系统考过的高频核心话题——都是面试中"能答出来但一追问就露馅"的典型。

---

# 一面（55分钟）

## 话题一：MySQL InnoDB 锁机制全景（13分钟）

**面试官：你做过金融系统，金融系统对数据一致性要求很高。MySQL InnoDB 的锁机制你了解多少？行锁、间隙锁、临键锁分别是什么？**

> 你回答...

**追问1：** 先说说 InnoDB 有哪些锁？按粒度和类型怎么分类？

> 你回答...（提示：InnoDB 锁分类 —— 两个维度：粒度 + 类型 / 按粒度：①表锁 → 意向锁（IS/IX）→ 表级 → 不锁数据行 → 只锁"表的元数据" → 目的是快速判断表里有没有行锁 → 避免逐行扫描 ②行锁 → 记录锁（Record Lock）/ 间隙锁（Gap Lock）/ 临键锁（Next-Key Lock）→ 行级 → 锁的是索引记录 / 按类型：①共享锁（S锁）→ 读锁 → `SELECT ... LOCK IN SHARE MODE` → 多个事务可同时持有 S 锁 → 但不能加 X 锁 ②排他锁（X锁）→ 写锁 → `SELECT ... FOR UPDATE` / `UPDATE` / `DELETE` → 只有持有 X 锁的事务能操作 → 其他事务的 S/X 锁都阻塞 / 意向锁：①意向共享锁（IS）→ 事务想加 S 锁前 → 先加表级 IS 锁 → 表示"表里可能有行级 S 锁" ②意向排他锁（IX）→ 事务想加 X 锁前 → 先加表级 IX 锁 ③为什么需要意向锁 → 事务A 想加表锁 → 需要检查表里有没有行锁 → 如果没有意向锁 → 要逐行扫描 → 性能灾难 → 有意向锁 → 只看表级标志位 → O(1) → 意向锁是"行锁的快捷标记" ④意向锁之间兼容 → IS 和 IS 兼容 → IS 和 IX 兼容 → IX 和 IX 兼容 → 因为都只是"想加行锁" → 不冲突 → 真正冲突在行锁 / 面试重点：表锁=意向锁（IS/IX 标记行锁）→ 行锁=记录锁/间隙锁/临键锁 → S/X 是读写语义）

**追问2：** 记录锁、间隙锁、临键锁分别是什么？它们在可重复读（RR）隔离级别下是怎么配合工作的？

> 你回答...（提示：三种行锁 —— InnoDB 在 RR 隔离级别下的核心锁机制 / 记录锁（Record Lock）：①锁的是索引记录本身 → 精确锁定一行 ②如 `SELECT * FROM t WHERE id = 10 FOR UPDATE` → id 是主键 → 加记录锁 → 只锁 id=10 这一行 → 其他行不受影响 ③如果查询条件没有命中索引 → 退化为全表扫描 → 每行都加临键锁 → 等于锁全表 → 这就是"没有索引导致锁升级" / 间隙锁（Gap Lock）：①锁的是两个索引记录之间的"间隙" → 不锁记录本身 → 锁的是"不存在的空间" ②如索引有值 10, 20, 30 → 间隙 (10, 20) → 锁住这个区间 → 其他事务不能在这个区间插入新记录 → 如 INSERT id=15 → 阻塞 ③间隙锁的唯一目的 → 防止幻读 → 两个事务同时持有相同间隙的间隙锁 → 不冲突 → 因为间隙锁只防 INSERT → 不防 SELECT ④间隙锁在 RC 隔离级别下关闭（`innodb_locks_unsafe_for_binlog`）→ 所以 RC 有幻读 / 临键锁（Next-Key Lock）：①记录锁 + 间隙锁的组合 → 锁一个记录 + 它前面的间隙 ②如索引有 10, 20, 30 → 临键锁锁 (10, 20] → 即间隙 (10,20) + 记录 20 ③InnoDB 在 RR 下默认用临键锁 → 防止幻读 → ④等值查询命中索引 → 退化为记录锁（只锁那一行）→ 等值查询没命中 → 退化为间隙锁（锁住间隙）→ 范围查询用临键锁 / RR 防幻读的原理：①事务A SELECT WHERE id BETWEEN 10 AND 30 → 加临键锁 (10,20], (20,30] → 间隙 (10,20) 和 (20,30) 也被锁 ②事务B INSERT id=15 → 命中间隙锁 → 阻塞 ③事务B INSERT id=25 → 命中间隙锁 → 阻塞 ④所以事务A 再次 SELECT → 结果一样 → 没有幻读 / 面试重点：记录锁=锁一行 → 间隙锁=锁一段空间防INSERT → 临键锁=记录锁+间隙锁 → RR默认用临键锁 → 防幻读）

**追问3：** 你说等值查询命中索引会退化为记录锁。那如果是等值查询命中唯一索引呢？和非唯一索引有什么区别？

> 你回答...（提示：唯一索引 vs 非唯一索引的锁差异 —— 这是个深水区 / 唯一索引等值查询：①`SELECT * FROM t WHERE id = 10 FOR UPDATE` → id 是唯一索引（或主键）→ 命中记录 → 临键锁退化为记录锁 → 只锁 id=10 这一行 → 不锁间隙 ②原因 → 唯一索引保证不会有第二条 id=10 → 不需要防幻读 → 间隙锁没意义 → 所以退化为记录锁 → 减少锁范围 / 非唯一索引等值查询：①`SELECT * FROM t WHERE name = '张三' FOR UPDATE` → name 是非唯一索引 → 可能有多条 → ②InnoDB 加临键锁 → 锁住 name='张三' 的记录 + 前面的间隙 → 还要锁住下一条不等于 '张三' 的记录前面的间隙 → ③如索引值有 ... '张三', '张三', '李四' ... → 锁住第一个'张三'前面的间隙 + 两个'张三'记录 + '张三'和'李四'之间的间隙 → ④原因 → 非唯一索引 → 可能有新的 name='张三' 插入 → 需要间隙锁防幻读 / 实际差异：①唯一索引 → 锁1条记录 → 影响小 ②非唯一索引 → 锁N条记录 + N+1个间隙 → 影响大 → 可能阻塞其他范围操作 ③这就是为什么金融系统用唯一索引做精确查询 → 锁范围小 → 并发好 / 真实案例：①转账系统 → 按 account_no 查账户 → account_no 是唯一索引 → 只锁一行 → 其他账户不受影响 ②如果 account_no 不是唯一索引 → 查一个账户 → 锁住多个间隙 → 可能阻塞其他账户的转账 / 面试加分：能说出"唯一索引等值命中→退化为记录锁→只锁一行→非唯一索引→加临键锁→锁间隙"→ 展示对锁机制的深入理解）

**追问4：** 间隙锁会导致什么问题？你在实际项目中遇到过死锁吗？怎么排查的？

> 你回答...（提示：间隙锁的问题 —— 死锁 / 间隙锁导致的死锁场景：①事务A：`SELECT * FROM t WHERE id = 15 FOR UPDATE` → id=15 不存在 → 加间隙锁 (10, 20) ②事务B：`SELECT * FROM t WHERE id = 15 FOR UPDATE` → id=15 不存在 → 也加间隙锁 (10, 20) → 间隙锁之间兼容 → 不阻塞 ③事务A：`INSERT INTO t VALUES (15, ...)` → 要加插入意向锁 → 被事务B 的间隙锁阻塞 ④事务B：`INSERT INTO t VALUES (15, ...)` → 要加插入意向锁 → 被事务A 的间隙锁阻塞 ⑤A 等 B 释放间隙锁 → B 等 A 释放间隙锁 → 死锁 ⑥InnoDB 检测到死锁 → 回滚代价较小的事务 → 报 `Deadlock found when trying to get lock; try restarting transaction` / 死锁排查：①`SHOW ENGINE INNODB STATUS` → 查看 LATEST DETECTED DEADLOCK 段 → 包含两个事务的信息 → 锁等待关系 → 死锁原因 ②`information_schema.INNODB_LOCKS` → 查看当前锁信息 → `INNODB_LOCK_WAITS` → 查看锁等待关系 ③MySQL 8.0 → `performance_schema.data_locks` 和 `data_lock_waits` → 替代 information_schema ④开启死锁日志 → `innodb_print_all_deadlocks = ON` → 所有死锁写入 error log / 实际项目案例（结合你的经验）：①金融系统 → 两个用户同时操作同一批账户 → 一个按 id 范围查 → 加临键锁 → 另一个 INSERT 新账户 → 命中间隙锁 → 死锁 ②解决 → 缩小事务范围 → 先查再快速提交 → 不要在事务里做耗时操作 → 减少锁持有时间 ③最终方案 → 用乐观锁替代悲观锁 → version 字段 → 大部分场景不需要 SELECT FOR UPDATE / 面试重点：间隙锁死锁 = 两个事务对同一段间隙加间隙锁（兼容）→ 再各自 INSERT → 互相等待 → 死锁 → 排查用 SHOW ENGINE INNODB STATUS）

**追问5：** 你提到乐观锁。乐观锁和悲观锁怎么选？金融场景下哪个更合适？

> 你回答...（提示：乐观锁 vs 悲观锁 / 悲观锁：①先锁再操作 → `SELECT ... FOR UPDATE` → 加行锁 → 操作 → 提交释放锁 ②适合写多读少 → 竞争激烈 → 先锁住不会冲突 ③缺点 → 锁持有期间 → 其他事务阻塞 → 吞吐量低 → 可能死锁 ④金融场景 → 转账 → 先查账户余额 → FOR UPDATE 锁行 → 修改余额 → 提交 → 保证不超扣 / 乐观锁：①先操作再检查冲突 → 版本号/时间戳 → UPDATE 时 WHERE version = old_version → CAS 思想 ②适合读多写少 → 竞争不激烈 → 大部分时候不冲突 → 不加锁 → 性能好 ③缺点 → 冲突重试 → 高并发下重试多 → 可能活锁（一直失败重试）→ 需要限制重试次数 ④金融场景 → 账户余额修改 → `UPDATE account SET balance = balance - 100, version = version + 1 WHERE id = 1 AND version = ?` → 如果返回 0 → 有人改过 → 重试 / 选择策略：①写多读少 / 竞争激烈 → 悲观锁 → 先锁住 → 不会冲突 → 转账/库存扣减（秒杀场景除外）②读多写少 / 竞争不激烈 → 乐观锁 → 不加锁 → 性能好 → 用户信息修改/配置更新 ③金融核心交易 → 悲观锁 → 确保数据正确 → 宁可慢不能错 ④高频交易（如秒杀）→ 乐观锁 + 重试 + Redis 预扣 → DB 层用乐观锁兜底 / 真实选型：①银行核心 → 悲观锁 → FOR UPDATE → 数据绝对正确 → 性能可接受（银行交易量没那么高）②互联网高频 → 乐观锁 → version → 高吞吐 → 冲突重试 ③混合 → 热点账户 → 悲观锁 → 冷账户 → 乐观锁 / 面试加分：能说出"金融核心用悲观锁保正确 → 互联网高频用乐观锁保吞吐 → 秒杀场景 Redis 预扣 + DB 乐观锁兜底"→ 展示对业务场景和技术选型的理解）

---

## 话题二：Redis 数据结构底层实现（12分钟）

**面试官：你说 Redis 快。Redis 快不仅仅是内存操作，底层的数据结构设计也很关键。你能说说 Redis 常用数据类型的底层实现吗？**

> 你回答...

**追问1：** Redis 有 5 种基础数据类型，它们的底层分别用什么数据结构实现的？

> 你回答...（提示：Redis 5种基础类型 → 底层数据结构 / String → SDS（Simple Dynamic String）：①不是 C 语言的 char[] → 而是自定义的 SDS ②SDS 结构：`len`（已用长度）+ `alloc`（分配总长度）+ `flags`（类型标记）+ `buf[]`（数据）③为什么不用 C 字符串 → ①O(1) 获取长度 → C 字符串要 strlen 遍历 → O(n) ②二进制安全 → C 字符串遇 \0 截断 → SDS 用 len 判断结束 → 可存图片/序列化数据 ③空间预分配 → 修改时多分配 → 减少频繁 realloc ④惰性释放 → 缩短时不立即释放 → 以后复用 ④Redis 3.2 后 → SDS 分5种类型 → sdshdr5/8/16/32/64 → 不同长度用不同结构 → 小字符串节省内存 / List → quicklist（Redis 3.2+）：①Redis 3.2 前 → ziplist（小列表）+ linkedlist（大列表）→ 根据元素数量和大小切换 ②Redis 3.2 后 → 统一用 quicklist → 双向链表 + 每个节点是 ziplist ③quicklist = 双向链表的节点 → 每个节点存一个 ziplist → 结合链表的灵活 + ziplist 的紧凑 → 减少指针开销 / Hash → ziplist / listpack（Redis 7.0+）→ hashtable：①元素少且短 → ziplist/listpack → 紧凑存储 → 省内存 ②元素多或长 → hashtable → Redis 自己实现的 dict → 渐进式 rehash ③切换阈值 → `hash-max-listpack-entries=128` / `hash-max-listpack-value=64` / Set → intset / hashtable：①全是整数且数量少 → intset → 有序数组 → 紧凑 ②有非整数或数量多 → hashtable ③阈值 → `set-max-intset-entries=512` / ZSet → listpack / skiplist + hashtable：①元素少 → listpack（Redis 7.2 前 ziplist）②元素多 → skiplist（跳表）+ hashtable → 跳表按分数排序 → hashtable 快速查找成员 ③阈值 → `zset-max-listpack-entries=128` / `zset-max-listpack-value=64` / 面试重点：String=SDS → List=quicklist → Hash=ziplist/listpack+hashtable → Set=intset+hashtable → ZSet=listpack+skiplist+hashtable → 小数据紧凑存储 → 大数据用高效结构）

**追问2：** 跳表（SkipList）是什么？Redis 的 ZSet 为什么用跳表不用红黑树？

> 你回答...（提示：跳表原理 + Redis 选型理由 / 跳表是什么：①多层有序链表 → 最底层是完整链表 → 每往上一层 → 抽取部分节点 → 形成索引层 → 查找时从最高层开始 → 逐层下降 → 类似二分查找 ②查找过程 → 从最高层头节点出发 → 如果下一个节点值 < 目标 → 往右走 → 如果 > 目标 → 往下一层 → 直到找到或确认不存在 ③时间复杂度 → 查找/插入/删除 O(log n) → 和红黑树一样 ④空间复杂度 → O(n) → 每个节点平均 1.33 个指针（p=0.25 时）→ 额外空间约 33% / Redis 跳表实现：①每个节点 → `ele`（成员）+ `score`（分数）+ `backward`（后退指针）+ `level[]`（前进指针数组 → 每层一个）②`level[]` 的长度 → 随机生成 → `ZSKIPLIST_MAXLEVEL=32` → 最多32层 → `ZSKIPLIST_P=0.25` → 每层晋升概率 1/4 ③为什么用随机层数 → 不需要手动维护平衡 → 插入时随机决定层数 → 期望高度 log n → 概率保证平衡 / Redis 为什么用跳表不用红黑树：①范围查询 → ZRANGEBYSCORE → 跳表找到起点 → 沿最底层链表遍历 → O(log n + M) → 红黑树范围查询要中序遍历 → 更复杂 ②实现简单 → 跳表代码约300行 → 红黑树代码复杂 → 旋转/着色逻辑多 → 维护成本高 ③内存可控 → 跳表每个节点平均1.33指针 → 红黑树每个节点2个指针+颜色位 → 差不多 → 但跳表更直观 ④并发友好 → 跳表修改只需局部加锁 → 红黑树旋转影响范围大 → 但Redis单线程不需要 → 这条不适用 ⑤作者 antirez 原话 → "They are simpler to implement, memory efficient, and good for range queries" / 面试加分：能说出"跳表O(log n)查找+范围查询沿链表遍历 → 实现简单 → Redis ZSet选跳表不选红黑树"→ 展示对数据结构的深入理解）

**追问3：** 你提到 hashtable 的渐进式 rehash。Redis 的 dict 是怎么做 rehash 的？为什么是"渐进式"？

> 你回答...（提示：Redis dict 渐进式 rehash / dict 结构：①`dictht ht[2]` → 两个 hash 表 → 正常用 ht[0] → rehash 时用 ht[1] ②`rehashidx` → rehash 进度 → -1 表示没在 rehash → ≥0 表示正在 rehash → 当前迁移到哪个桶 / rehash 触发：①负载因子 = used / size → 已用/总桶数 ②没在 BGSAVE/BGREWRITEAOF → 负载因子 ≥ 1 → rehash 扩容 ③在 BGSAVE/BGREWRITEAOF → 负载因子 ≥ 5 → rehash 扩容 → 为什么 → BGSAVE 时子进程在用内存 → 此时扩容会 COW 大量页 → 推迟 ④缩容 → 负载因子 < 0.1 → rehash 缩容 / 渐进式 rehash 过程：①分配 ht[1] → 大小 = 第一个 ≥ used*2 的 2^n ②rehashidx = 0 → 开始 rehash ③每次 dict 操作（增删改查）→ 顺便迁移 ht[0] 中 rehashidx 位置的桶 → 所有节点迁移到 ht[1] → rehashidx++ ④如果 ht[0][rehashidx] 为空 → 也++ → 但最多跳 100 个空桶 → 避免卡太久 ⑤同时 Redis 定时任务 → 每次执行 1ms → 迁移 100 个桶 → 加速 rehash ⑥全部迁移完 → ht[0] = ht[1] → ht[1] = null → rehashidx = -1 → 完成 / 为什么渐进式：①如果一次性 rehash → 几百万 key → 一次性迁移 → 卡几秒 → Redis 单线程 → 阻塞所有请求 → 不可接受 ②渐进式 → 每次操作迁移一个桶 → 分摊到多次请求 → 每次请求多一点点开销 → 用户无感 ③类比 JVM G1 的并发标记 → 把停顿分摊 → 不一次性 STW / rehash 期间的读写：①读 → 先查 ht[0] → 没找到 → 查 ht[1] ②写 → 直接写 ht[1] → ht[0] 只读不写 → 新数据不会在 ht[0] → 迁移只减不增 ③删 → 两个表都要查 / 面试重点：两个ht表 → rehashidx 渐进迁移 → 每次操作迁移一个桶 → 读查两个表 → 写只写ht[1] → 避免一次性 rehash 阻塞）

**追问4：** Redis 7.0 把 ziplist 换成了 listpack。为什么要换？ziplist 有什么问题？

> 你回答...（提示：ziplist 的问题 → listpack 的改进 / ziplist 结构：①紧凑的连续内存块 → 每个 entry 包含：prevlen（前一个entry长度）+ encoding（编码类型）+ data（数据）②prevlen → 如果前一个 entry < 254 字节 → 1 字节存 → 如果 ≥ 254 → 5 字节存 / ziplist 的问题——连锁更新（Cascade Update）：①如果删除/修改了一个 entry → 导致后一个 entry 的 prevlen 从 5 字节变成 1 字节 → 这个 entry 变小了 → 它的后一个 entry 的 prevlen 也要变 → 5→1 → 连锁触发 → 最坏 O(n²) ②极端场景 → 中间有大量 ≥ 254 字节的 entry → 删除一个 → 后面所有 entry 都要改 prevlen → 从 5 字节→1 字节 → 每个都变小 → 连锁反应 → 大量内存拷贝 → 性能问题 ③实际触发概率低 → 但一旦触发 → 延迟飙升 → Redis 作者一直在修这个 / listpack 改进：①去掉 prevlen → 每个 entry 只存自己的长度 → 不依赖前一个 entry → 不再有连锁更新 ②entry 结构：encoding + data + backlen（自身长度 → 反向遍历用）③backlen → 变长整数 → 记录当前 entry 总长度 → 不依赖前一个 → 修改不影响其他 entry ④牺牲 → 不能反向遍历前一个 entry 的 prevlen → 但用 backlen 可以反向计算 → 功能不变 / 为什么 Redis 7.0 换：①彻底消除连锁更新 → 性能更稳定 ②代码更简洁 → ziplist 实现复杂 → listpack 简单 ③ziplist 在 hash/list/zset 小数据时都用 → 换成 listpack → 全局受益 / 面试加分：能说出"ziplist 的 prevlen 导致连锁更新 O(n²) → listpack 去掉 prevlen 用 backlen → 彻底解决"→ 展示对 Redis 版本演进和底层优化的理解）

---

## 话题三：手写代码 - 二分查找变体（8分钟）

**面试官：写一个二分查找。但不是普通的二分——在一个有序数组里，找到第一个大于等于 target 的元素位置。写完说说你的思路。**

你在纸上/白板上写代码...

**追问1：** 先说说你的思路。和普通二分查找有什么区别？为什么要 `right = mid` 而不是 `right = mid - 1`？

> 你回答...（提示：二分查找变体——查找第一个 ≥ target 的位置 / 代码：
```java
public int lowerBound(int[] nums, int target) {
    int left = 0, right = nums.length;
    while (left < right) {
        int mid = left + (right - left) / 2;  // 防溢出
        if (nums[mid] < target) {
            left = mid + 1;      // mid 一定不是答案 → 跳过
        } else {
            right = mid;          // mid 可能是答案 → 不能跳过
        }
    }
    return left;  // left == right → 第一个 >= target 的位置
}
```
/ 和普通二分的区别：①普通二分 → `nums[mid] == target` → 直接返回 mid → 找到就结束 ②变体 → 不找等于 → 找"第一个满足条件的" → 不能找到就返回 → 要继续往左找 → 看有没有更早的满足条件的 / 为什么 `right = mid` 而不是 `mid - 1`：①当 `nums[mid] >= target` → mid 可能是答案 → 但左边可能还有更小的满足条件的 → 所以搜索范围缩小到 `[left, mid]` → `right = mid` → mid 包含在搜索范围里 ②如果 `right = mid - 1` → 跳过了 mid → 如果 mid 恰好是答案 → 永远找不到了 ③核心思想 → "可能是答案"的 mid 不能跳过 → "一定不是答案"的 mid 可以跳过（`left = mid + 1`）/ 为什么 `right = nums.length` 而不是 `nums.length - 1`：①这是左闭右开区间 `[left, right)` → right 指向"末尾的后一个位置" → 不指向有效元素 ②如果所有元素都 < target → left 会走到 nums.length → 表示"没有满足条件的元素" → 返回 nums.length 作为"未找到" ③如果用闭区间 `[left, right]` → right 初始 `nums.length - 1` → 循环条件 `left <= right` → `right = mid - 1` → 也可以但容易写错 / 循环终止条件 `left < right` 而不是 `left <= right`：①左闭右开 → left == right 时 → 搜索范围为空 → `[left, left)` → 没有元素 → 退出 ②不会死循环 → 每次循环至少缩小范围（left右移或right左移）→ 最终 left == right / 面试重点：变体二分 → "可能是答案"的不跳过（right=mid）→ "不是答案"的跳过（left=mid+1）→ 左闭右开[left,right) → 终止 left==right）

**追问2：** 如果要找最后一个小于等于 target 的位置呢？怎么改？

> 你回答...（提示：最后一个 ≤ target 的位置 = 第一个 > target 的位置 - 1 / 思路一——直接改二分：①找最后一个 ≤ target → 等价于找第一个 > target 的位置 → 减 1 ②复用 lowerBound → `int pos = upperBound(nums, target); return pos - 1;` ③upperBound = 第一个 > target 的位置 → 和 lowerBound 几乎一样 → 把 `< target` 改成 `<= target` / 代码：
```java
public int upperBound(int[] nums, int target) {
    int left = 0, right = nums.length;
    while (left < right) {
        int mid = left + (right - left) / 2;
        if (nums[mid] <= target) {  // <= 而不是 <
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    return left;  // 第一个 > target 的位置
    // 最后一个 <= target 的位置 = left - 1
}
```
/ 思路二——用 lowerBound 直接推导：①最后一个 ≤ target = lowerBound(target + 1) - 1 → 因为 lowerBound(target+1) 找的是第一个 ≥ target+1 → 即第一个 > target → 减1 = 最后一个 ≤ target ②但 target + 1 可能溢出 → 如果 target 是 Integer.MAX_VALUE → 不安全 → 所以还是用 upperBound / 边界处理：①如果所有元素 > target → upperBound 返回 0 → 最后一个 ≤ target = -1 → 不存在 ②如果所有元素 ≤ target → upperBound 返回 nums.length → 最后一个 ≤ target = nums.length - 1 → 最后一个元素 / 面试重点：upperBound(第一个>target) → 最后一个≤target = upperBound - 1 → 和 lowerBound 只差一个等号 → 核心都是"可能是答案的不跳过"）

**追问3：** `mid = left + (right - left) / 2` 为什么要这么写？直接 `(left + right) / 2` 有什么问题？

> 你回答...（提示：整数溢出 / `(left + right) / 2` 的问题：①如果 left 和 right 都接近 Integer.MAX_VALUE → left + right 溢出 → 变成负数 → 负数/2 → 负数下标 → ArrayIndexOutOfBoundsException ②虽然实际中数组很少大到 21 亿 → 但面试和工程规范都要求防溢出 / `left + (right - left) / 2` 的原理：①right - left → 一定是非负数 → 不会溢出（因为 left ≤ right）②除以 2 → 得到偏移量 → 加上 left → 得到 mid → ③数学等价 → `left + (right - left) / 2 = left + right/2 - left/2 = (left + right) / 2` → 但不会溢出 / 另一种写法 `left + ((right - left) >> 1)`：①位运算替代除法 → 理论上更快 → 但现代编译器会自动优化 `/2` 为 `>>1` → 实际没区别 ②可读性 → `/2` 更直观 → 推荐用 `/2` / 无符号右移写法 `(left + right) >>> 1`：①Java 的 `>>>` 无符号右移 → 即使溢出成负数 → 右移后也是正数 → 也能得到正确结果 ②但只有 Java 有 `>>>` → C/C++ 没有 → 跨语言不通用 → 不推荐 / 面试重点：防溢出 → `left + (right - left) / 2` → 原因是 left+right 可能溢出）

---

## 话题四：ReentrantLock 深入（12分钟）

**面试官：你前面讲过 AQS。ReentrantLock 是 AQS 最经典的实现。公平锁和非公平锁的源码区别是什么？**

> 你回答...

**追问1：** 先说说 ReentrantLock 的基本结构。它怎么实现可重入的？

> 你回答...（提示：ReentrantLock 基于 AQS / 基本结构：①ReentrantLock → 内部有一个 Sync 继承 AQS → Sync 有两个子类 → FairSync（公平锁）和 NonfairSync（非公平锁）→ 默认非公平锁 ②`new ReentrantLock()` → 非公平锁 → `new ReentrantLock(true)` → 公平锁 / 可重入实现：①AQS 的 state 变量 → volatile int → CAS 修改 → state=0 表示锁空闲 → state>0 表示锁被持有 → state 的值 = 重入次数 ②第一次 lock → CAS(0→1) → 成功 → 记录当前线程（exclusiveOwnerThread = currentThread）③第二次 lock（同线程）→ 不 CAS → state++ → state=2 → 重入 ④unlock → state-- → state=0 → 释放锁 → 唤醒队列中第一个等待线程 / 非公平锁 lock 流程：①`lock()` → 先 CAS(0→1) → "上来就抢" → 不排队 ②如果 CAS 成功 → 获取锁 → 设置 ownerThread ③如果 CAS 失败 → `acquire(1)` → AQS 标准流程 → tryAcquire → 入队 → park / 公平锁 lock 流程：①`lock()` → 直接调 `acquire(1)` → 不先 CAS 抢 ②`acquire` → `tryAcquire` → 先检查队列有没有人排队 → `hasQueuedPredecessors()` → 如果有 → 不抢 → 入队 ③如果没有人排队 → CAS 获取 → 合理 → 没人等就我拿 / 核心区别：①非公平锁 → 上来 CAS 抢 → 不管队列 → 可能"插队" ②公平锁 → 先看队列 → 有人排队 → 老老实实排队 → 严格 FIFO / 面试重点：state=重入次数 → 非公平先CAS抢 → 公平先检查队列 → acquire → tryAcquire → 入队CLH）

**追问2：** 公平锁和非公平锁的 tryAcquire 源码有什么区别？为什么要设计非公平锁？

> 你回答...（提示：源码对比 / 非公平锁 tryAcquire：
```java
// NonfairSync
final boolean nonfairTryAcquire(int acquires) {
    final Thread current = Thread.currentThread();
    int c = getState();
    if (c == 0) {
        // 不检查队列 → 直接 CAS 抢
        if (compareAndSetState(0, acquires)) {
            setExclusiveOwnerThread(current);
            return true;
        }
    }
    else if (current == getExclusiveOwnerThread()) {
        // 可重入
        int nextc = c + acquires;
        if (nextc < 0) throw new Error("Maximum lock count exceeded");
        setState(nextc);
        return true;
    }
    return false;
}
```
/ 公平锁 tryAcquire：
```java
// FairSync
protected final boolean tryAcquire(int acquires) {
    final Thread current = Thread.currentThread();
    int c = getState();
    if (c == 0) {
        // 先检查队列有没有人排队
        if (!hasQueuedPredecessors() &&
            compareAndSetState(0, acquires)) {
            setExclusiveOwnerThread(current);
            return true;
        }
    }
    else if (current == getExclusiveOwnerThread()) {
        int nextc = c + acquires;
        if (nextc < 0) throw new Error("Maximum lock count exceeded");
        setState(nextc);
        return true;
    }
    return false;
}
```
/ 唯一区别 → `hasQueuedPredecessors()` → 公平锁在 CAS 前先检查队列有没有人排队 → 有就不抢 → 非公平锁不检查 → 直接 CAS 抢 / 为什么设计非公平锁：①性能更好 → 线程B 刚释放锁 → 唤醒队列中的线程A → A 从 park 到 runnable 需要时间 → 这段时间 → 如果线程C 来了 → 非公平锁直接给 C → C 不用排队 → 不用等 A 唤醒 → 吞吐量高 ②公平锁 → 必须等 A 唤醒 → A 唤醒期间锁空闲 → 浪费 → 且 A 唤醒后 → context switch → 开销大 ③非公平锁 → "插队" → 但刚释放锁的线程更可能再次获取 → 缓存命中率高 → 性能好 ④公平锁 → 严格 FIFO → 但吞吐量低 → 适合严格要求公平的场景 / 非公平锁的"不公平"：①线程A 在队列等锁 → 线程C 来了 → CAS 直接拿到 → A 还在等 → C "插队" ②但 C 释放后 → A 还有机会 → 不是"饿死" → 因为 C 不一定每次都抢到 → CAS 失败就入队 ③极端情况 → 如果 C 持续来 → 可能导致 A 长时间拿不到锁 → 但概率低 → 因为线程执行完释放 → 下次来需要时间 / 面试加分：能说出"非公平锁不检查队列直接CAS → 刚释放锁的线程缓存命中率高 → 减少唤醒开销 → 吞吐量高 → 公平锁严格FIFO但吞吐量低"→ 展示对锁设计的深入理解）

**追问3：** ReentrantLock 的 Condition 是什么？和 synchronized 的 wait/notify 有什么区别？

> 你回答...（提示：Condition = ReentrantLock 的条件变量 / Condition 基本用法：
```java
ReentrantLock lock = new ReentrantLock();
Condition notFull = lock.newCondition();   // 队列不满
Condition notEmpty = lock.newCondition();  // 队列不空

// 生产者
lock.lock();
try {
    while (queue.isFull()) notFull.await();  // 等待不满
    queue.add(item);
    notEmpty.signal();                       // 通知不空
} finally {
    lock.unlock();
}
```
/ Condition vs wait/notify：①依赖 → Condition 依赖 ReentrantLock → wait/notify 依赖 synchronized ②多条件 → 一个 Lock 可以创建多个 Condition → 一个 synchronized 只有一个等待队列 → wait/notify 无法区分"队列不满"和"队列不空" → 只能 notifyAll → 唤醒所有 → 精准唤醒需要多个 Condition → 只有 ReentrantLock 能做到 ③精准唤醒 → notFull.signal() 只唤醒等 notFull 的线程 → notEmpty.signal() 只唤醒等 notEmpty 的 → wait/notify 唤醒所有等待的线程 → 可能虚假唤醒 ④超时 → Condition.await(time) → wait(timeout) → 都有 ⑤不响应中断 → Condition.awaitUninterruptibly() → wait 没有 ⑥截止时间 → Condition.awaitNanos() / awaitUntil() → 更灵活 / Condition 底层实现：①每个 Condition 维护一个自己的等待队列 → 单向链表 → 和 AQS 的 CLH 同步队列分离 ②await() → 当前线程构造 Node → 加入 Condition 等待队列 → 释放锁（fullyRelease）→ park → 被唤醒后 → 从 Condition 队列移到 CLH 同步队列 → 重新竞争锁 ③signal() → 取 Condition 等待队列的第一个节点 → 移到 CLH 同步队列 → 唤醒 → 线程被唤醒后重新竞争锁 / 生产者消费者用 Condition 的优势：①两个 Condition → notFull 和 notEmpty → 生产者等 notFull → 消费者等 notEmpty ②生产者入队后 → signal(notEmpty) → 只唤醒消费者 → 不唤醒其他生产者 → 精准 → 减少无效唤醒 ③synchronized → 只能 notifyAll → 唤醒所有 → 生产者也被唤醒 → 白白竞争 → 性能差 / 面试重点：Condition多条件精准唤醒 → 一个Lock多个Condition → await释放锁入等待队列 → signal移到CLH队列 → 比wait/notify精准）

**追问4：** tryLock(timeout) 是怎么实现的？和 lock() 有什么区别？

> 你回答...（提示：tryLock 超时机制 / tryLock 两种形式：①`tryLock()` → 立即返回 → 尝试 CAS → 成功返回 true → 失败返回 false → 不阻塞 ②`tryLock(timeout, unit)` → 尝试获取 → 超时返回 false → 阻塞但有超时 / tryLock() 实现：①直接调 tryAcquire → CAS(0→1) → 成功返回 true → 失败返回 false → 不入队 → 不阻塞 ②公平锁 → tryAcquire → 检查队列 → 有排队 → 返回 false → 不插队 / tryLock(timeout) 实现：①`tryAcquireNanos` → 先 tryAcquire → 成功就返回 ②失败 → 入队 → `doAcquireNanos` → 在 CLH 队列里自旋 + park ③park 用 `LockSupport.parkNanos(this, nanosTimeout)` → 带超时的 park → 超时自动唤醒 ④每次被唤醒 → 检查是否到超时 → 到了 → 取消节点（cancelAcquire）→ 返回 false ⑤如果前驱是头节点 → 再 tryAcquire → 成功 → 返回 true / lock() vs tryLock(timeout)：①lock() → 无限等待 → 抢不到就 park → 被唤醒继续抢 → 直到拿到 → 不响应中断 ②lockInterruptibly() → 响应中断 → 被中断抛 InterruptedException ③tryLock(timeout) → 超时返回 → 不死等 → 超时后取消排队 / 实际场景：①死锁避免 → tryLock + 超时 → 超时后放弃 → 释放已持有的锁 → 避免死锁 ②限时操作 → 用户等不了太久 → 超时返回"系统繁忙" → 降级 ③避免队列堆积 → 大量请求抢锁 → tryLock 快速失败 → 不堆积在 CLH 队列 / 面试重点：tryLock=CAS不阻塞 → tryLock(timeout)=入队+parkNanos带超时 → 超时取消节点返回false → 死锁避免用tryLock+超时）

---

# 二面（30分钟）

## 话题五：Spring AOP 原理深入（10分钟）

**面试官：你简历上写了 AOP。Spring AOP 的底层原理是什么？JDK 动态代理和 CGLIB 有什么区别？**

> 你回答...

**追问1：** 先说说 Spring AOP 是什么？它的核心概念有哪些？

> 你回答...（提示：Spring AOP 核心概念 / AOP = Aspect-Oriented Programming → 面向切面编程 → 将横切关注点（日志/事务/权限/缓存）从业务逻辑中分离 / 核心概念：①Aspect（切面）→ 一个类 → 包含多个通知和切点 → `@Aspect` 标注 ②Pointcut（切点）→ 定义"在哪些方法上"织入通知 → 表达式 `execution(* com.xxx.service.*.*(..))` → 匹配方法 ③Advice（通知/增强）→ 定义"做什么" → 5种 → @Before / @After / @AfterReturning / @AfterThrowing / @Around ④JoinPoint（连接点）→ 程序执行中的某个点 → Spring AOP 只支持方法级别的连接点 → 每一个被匹配到的方法都是一个连接点 ⑤Weaving（织入）→ 将切面应用到目标对象 → Spring AOP 用运行时动态代理织入 → AspectJ 用编译时织入（更强大但更复杂）⑥Target Object（目标对象）→ 被代理的原始对象 ⑦Proxy（代理对象）→ Spring 创建的代理 → 包含目标对象 + 切面逻辑 / 5种通知执行顺序：①正常情况 → @Around（前半）→ @Before → 目标方法 → @Around（后半）→ @AfterReturning → @After ②异常情况 → @Around（前半）→ @Before → 目标方法（抛异常）→ @AfterThrowing → @After ③@Around 最强 → 包裹整个方法 → 可以决定是否执行目标方法 → 可以修改参数和返回值 / 面试重点：Pointcut=在哪里 → Advice=做什么 → 5种通知 → @Around最强包裹全部 → Spring AOP=运行时动态代理）

**追问2：** Spring AOP 用 JDK 动态代理还是 CGLIB？选择标准是什么？

> 你回答...（提示：Spring 的代理选择策略 / JDK 动态代理：①基于接口 → `Proxy.newProxyInstance()` → 目标类必须实现接口 ②原理 → 运行时动态生成一个实现了目标接口的代理类 → 代理类持有一个 InvocationHandler → 调用方法时 → InvocationHandler.invoke() → 在这里织入切面逻辑 → 再调目标方法 ③生成的代理类 → `$Proxy0` → implements 目标接口 → 方法调用转发给 InvocationHandler / CGLIB：①基于继承 → 运行时用 ASM 生成目标类的子类 → 子类覆盖方法 → 在方法前后织入逻辑 ②不要求接口 → 任何类都可以代理 ③原理 → Enhancer.create() → ASM 生成字节码 → 生成子类 → MethodInterceptor.intercept() → 织入逻辑 ④不能代理 final 类和 final 方法 → 继承不了 → CGLIB 无法覆盖 / Spring 的选择策略：①如果目标类实现了接口 → 默认用 JDK 动态代理（Spring 5.0 前）②如果目标类没有实现接口 → 用 CGLIB ③Spring 5.0+ → `spring.aop.proxy-target-class=true` → 默认 CGLIB → 不管有没有接口都用 CGLIB → 因为 JDK 代理有"类型转换"问题 → 注入时如果用实现类类型 → 代理对象是接口类型 → 注入失败 → 用 CGLIB → 代理对象是子类 → 可以注入为实现类类型 / 区别总结：①JDK 动态代理 → 接口 → `Proxy` + `InvocationHandler` → 代理对象是接口类型 ②CGLIB → 继承 → `Enhancer` + `MethodInterceptor` → 代理对象是子类类型 ③性能 → CGLIB 创建代理慢（生成字节码）→ 执行快（FastClass 机制避免反射）→ JDK 创建快 → 执行慢（反射调用）④Spring Boot 2.x+ → 默认 CGLIB → proxy-target-class=true / 面试重点：JDK代理=接口+InvocationHandler → CGLIB=继承+MethodInterceptor → Spring Boot 2.x默认CGLIB → 不能代理final类/方法）

**追问3：** Spring AOP 和 AspectJ 有什么区别？为什么 Spring 不直接用 AspectJ？

> 你回答...（提示：Spring AOP vs AspectJ / 织入时机不同：①Spring AOP → 运行时织入（Runtime Weaving）→ 通过动态代理 → 每次调用代理方法 → 额外一层方法调用开销 ②AspectJ → 编译时织入（Compile-Time Weaving CTW）或加载时织入（Load-Time Weaving LTW）→ 在编译时或类加载时修改字节码 → 运行时无代理开销 ③Spring AOP 的代理 → 每次方法调用 → 代理对象 → InvocationHandler/MethodInterceptor → 目标方法 → 多一层间接 → 性能开销 ④AspectJ → 字节码直接修改 → 方法调用是直接的 → 没有代理层 → 性能更好 / 功能差异：①Spring AOP → 只支持方法级别的连接点 → 不能对字段、构造器、静态方法做切面 ②AspectJ → 支持方法/字段/构造器/静态初始化器等 → 更细粒度 → call（调用点）/ execution（执行点）/ set（字段写）/ get（字段读）等 ③Spring AOP → 只能在 Spring Bean 上用 → AspectJ → 任何 Java 对象 / 为什么 Spring 不直接用 AspectJ：①简单 → Spring AOP 用动态代理 → 不需要特殊编译器 → 不需要 java agent → 开箱即用 ②AspectJ → 需要 ajc 编译器（CTW）或 java agent（LTW）→ 部署复杂 ③80% 场景 → 方法级别切面够用 → Spring AOP 足够 ④Spring AOP 可以用 AspectJ 的注解语法 → `@Aspect` / `@Pointcut` / `@Before` → 底层还是动态代理 → 兼顾了开发体验和简洁性 / Spring AOP 的性能开销：①每次方法调用 → 代理 → 反射/MethodInterceptor → 额外开销约 100ns-1μs ②高频调用场景 → 如循环内调用 → 累积开销 → 但大部分业务场景 → 不敏感 ③如果对性能极致要求 → 用 AspectJ CTW → 编译时织入 → 运行时零开销 / 面试加分：能说出"Spring AOP运行时动态代理→方法级→简单开箱即用 → AspectJ编译时/加载时字节码修改→更强大→需要ajc或agent→Spring用AspectJ注解语法但底层动态代理"→ 展示对AOP生态的理解）

**追问4：** 你说 Spring 事务用的 AOP。那如果在一个 @Transactional 方法里，自己 new 一个对象调它的方法，事务会生效吗？

> 你回答...（提示：不生效 → 和 Day52 讲的自调用失效类似但不完全一样 / 分析：①@Transactional 基于 AOP 代理 → 只有通过 Spring 容器管理的 Bean → 注入到其他 Bean → 调用时经过代理 → 事务才生效 ②自己在方法里 `new XxxService()` → 这个对象不是 Spring 创建的 → 没有经过代理 → 是原始对象 → 方法调用直接到目标方法 → 不经过代理 → @Transactional 不生效 ③即使 XxxService 是 Spring Bean → 但 `new` 出来的不是容器里的那个 → 是一个新的普通对象 → 没有被代理 / 和自调用失效的区别：①自调用 → 同一个 Bean 内 → A.B() → this 不是代理 → 不经过代理 ②new 对象 → 完全绕过 Spring → 连 Bean 都不是 → 更不可能有代理 ③本质都是 → 绕过了代理对象 → 直接调用目标方法 → AOP 不生效 / 解决方案：①从容器获取 → `@Autowired XxxService xxxService` → 注入的是代理对象 → `xxxService.method()` → 经过代理 → 生效 ②ApplicationContext.getBean() → 从容器拿 → 是代理对象 ③不要 new → Spring 管理的 Bean 应该由容器创建 → new 出来的是脱离容器的 / 更深层理解：①Spring AOP 只能拦截 → Spring 容器管理的 Bean → 经过代理对象调用的方法 ②非 Spring 管理的对象 → Spring 创建的代理 → new 出来的对象 → 都不受 AOP 保护 ③这就是为什么 → Spring 强调"不要自己 new" → 用 DI（依赖注入）→ 容器管理生命周期 + 代理 / 面试重点：new的对象不是代理 → @Transactional不生效 → 和自调用失效本质一样（绕过代理）→ 解决：从容器获取/注入）

---

## 话题六：分布式理论 CAP/BASE + 核心设计题：金融跨行转账一致性方案（20分钟）

**面试官：最后聊个架构题。CAP 理论你一定听过。你觉得 CAP 的'三选二'这个说法准确吗？**

> 你回答...

**追问1：** 先说说 CAP 分别是什么？为什么说"三选二"是一个误解？

> 你回答...（提示：CAP 理论 / CAP 三要素：①C（Consistency 一致性）→ 所有节点在同一时刻看到的数据相同 → 写操作完成后 → 任何后续读都能读到最新值 → 强一致性 ②A（Availability 可用性）→ 系统一直可用 → 每个请求都能收到非错误响应 → 不保证是最新数据 → 但不能超时拒绝 ③P（Partition Tolerance 分区容错）→ 网络分区时系统仍能运行 → 网络断开导致节点间无法通信 → 系统不能挂 / "三选二"的误解：①CAP 不是"三选二" → P 不是可选的 → 在分布式系统中 → 网络分区一定会发生 → P 是客观存在 → 不能选择"不要P" ②真正的选择 → 当分区发生时 → 在 C 和 A 之间选 → ①选 C → 分区时拒绝服务（不可用）→ 等数据一致后恢复 ②选 A → 分区时继续服务（可能返回旧数据）→ 分区恢复后再同步 ③所以准确的表述 → "分区发生时 → 在 C 和 A 之间二选一" → 而不是"CAP三选二" ④没有分区时 → C 和 A 可以同时满足 → 正常运行 / 实际系统：①ZooKeeper → CP → 分区时 → 少数派不服务 → 保证一致 → 丢弃可用性 ②Eureka → AP → 分区时 → 所有节点继续服务 → 可能返回旧数据 → 丢弃一致性 ③Nacos → 支持AP和CP → 临时实例AP → 持久实例CP → 可选 ④MySQL 主从 → 异步复制 → AP → 主写后从可能还没同步 → 读到旧数据 → 但系统可用 / BASE 理论：①Basically Available（基本可用）→ 允许损失部分可用性 → 响应时间增加 / 非核心功能降级 → 但系统不挂 ②Soft State（软状态）→ 允许数据存在中间状态 → 不要求时时一致 → 如"支付中"→"支付成功"中间状态 ③Eventually Consistent（最终一致性）→ 系统保证最终数据一致 → 不保证实时一致 → 但在没有新写入后 → 最终所有副本一致 ④BASE 是 CAP 中 AP 的延伸 → 放弃强一致 → 换可用性 → 但保证最终一致 → 互联网系统的核心理论 / 面试重点：P不是可选的 → 分区时在C和A之间选 → ZK=CP/Eureka=AP → BASE=AP的延伸 → 最终一致）

**追问2：** 你说金融系统对一致性要求高。那跨行转账怎么做？两家银行用不同的数据库，怎么保证要么都成功要么都失败？

> 你回答...（提示：跨行转账一致性方案 —— 综合设计题 / 场景：A银行账户扣款 → B银行账户加款 → 跨两个数据库 → 要么都成功要么都失败 / 方案一——两阶段提交（2PC/XA）：①协调者 → 通知A银行prepare → 通知B银行prepare → 都OK → commit → 有一方失败 → rollback ②问题 → 协调者单点故障 → 阻塞 → A银行prepare后锁住资源 → 等B银行 → B慢 → A锁很久 → 性能差 ③跨银行 → 没有一个"超级协调者" → 银行间不信任 → 不会把自己的锁交给别人管 ④实际不用 → XA 太重 → 银行不用 / 方案二——TCC（Try-Confirm-Cancel）：①Try → A银行冻结金额 → B银行预加款（或不动）②Confirm → A银行扣减冻结 → B银行正式加款 ③Cancel → A银行解冻 → B银行回滚预加 ④问题 → 侵入大 → 每个接口要写三套逻辑 → B银行可能不支持TCC → 跨行很难 ⑤金融场景 → 如果是同一银行内部 → 可以用TCC → 跨行不现实 / 方案三——本地消息表（最终一致）→ 最常用：①A银行 → 本地事务：扣款 + 写消息表（status=待发送）→ 一个DB事务 → 原子 ②消息表 → MQ发送 → B银行消费 → B加款 → B银行回复ACK → A银行更新消息表 status=已完成 ③如果B消费失败 → MQ重试 → 幂等 → B银行用唯一流水号去重 ④如果MQ丢失 → A银行定时扫描消息表 → status=待发送 超时 → 重新发送 ⑤最终一致 → A扣款 → B可能延迟几秒加款 → 但最终一致 / 方案四——Saga 模式：①长事务拆成多个子事务 → 每个子事务有正向操作和补偿操作 ②转账 → T1: A扣款 → T2: B加款 → 如果T2失败 → C1: A加回款（补偿T1）③和TCC区别 → Saga没有Try阶段 → 直接执行 → 失败补偿 → TCC先Try预留 ④适合长链路 → 如旅行预订 → 订机票→订酒店→租车 → 某步失败 → 反向补偿 / 跨行转账实际方案 → 央行清算 + 对账：①实际跨行转账 → 不是A直接调B的DB → 通过央行清算系统 ②A银行 → 记录扣款 → 发送清算报文 → 央行清算 ③央行 → 净额清算 → 通知B银行 ④B银行 → 加款 → 如果失败 → 下一个清算周期补偿 ⑤对账 → 每日日终对账 → 差异挂账 → 人工处理 ⑥本质 → 本地消息表 + 最终一致 + 对账兜底 / 面试加分：能说出"跨行转账本质=本地消息表+最终一致+日终对账 → 不用2PC（太重不可控）→ 不用TCC（跨行不现实）→ 央行清算做中间层"→ 展示对金融系统实际架构的理解）

**追问3：** 你提到本地消息表。如果消息发出去后，B银行一直不ACK，A银行怎么办？钱扣了但B没加，客户投诉了。

> 你回答...（提示：消息发送失败/超时的处理 / 问题分析：①A扣款 → 写消息表 → 发MQ → B消费 → B处理成功 → ACK → A更新消息表=已完成 → 正常 ②异常1 → MQ发送失败 → 消息表 status=待发送 → A定时扫描 → 重发 ③异常2 → MQ发送成功 → B消费失败 → B不ACK → MQ重试 → B一直失败 → 死信队列 → 人工处理 ④异常3 → B消费成功 → ACK丢失 → MQ认为没ACK → 重试 → B收到重复消息 → 需要幂等 ⑤异常4 → B消费成功 → ACK成功 → A更新消息表失败 → A认为没完成 → 重发 → B收到重复 → 幂等 / B一直不ACK的处理：①MQ层面 → RocketMQ → 消费失败 → 重试16次 → 仍然失败 → 进入死信队列 → 告警 → 人工介入 ②A银行层面 → 定时扫描消息表 → status=待发送 且 超时（如5分钟）→ 重发 → 但重发有次数限制（如3次）→ 超过 → 告警 ③重发N次仍失败 → 标记为"异常" → 进入人工处理流程 → 运营人员排查 → 联系对方银行 ④客户层面 → 客户看到"转账处理中"→ 不是"失败" → 给客户预期 → T+1到账 / 客户投诉的处理：①查询 → A银行查消息表 → 有扣款记录 → 消息状态=待发送/已发送/已完成 → 告诉客户状态 ②如果消息发了很多次都没ACK → 说明对方银行有问题 → A银行主动发起冲正 → A银行加回客户的钱 → 状态=已冲正 → 告诉客户"对方银行处理异常 → 已退回" ③冲正 = 反向交易 → 把扣的款加回去 → 和原交易关联 → 会计上平账 ④如果B已经加了款 → 不能冲正 → 否则B端客户多了一笔钱 → 所以冲正前要确认B没加 → 通过对账确认 / 对账兜底：①日终对账 → A银行发文件 → B银行收文件 → 逐笔核对 ②A有扣款 B没加款 → 差异 → A冲正退款给客户 ③A有扣款 B有加款 → 一致 → 正常 ④A没扣款 B有加款 → B冲正 → B减回 ⑤对账是最终兜底 → 即使消息全部丢了 → 对账能发现差异 → 人工修正 / 面试重点：MQ重试→死信→告警 → 定时重发→超限→人工 → 冲正退款给客户 → 日终对账兜底 → "转账处理中"给客户预期）

**追问4：** 最后一个问题：Raft 协议你了解吗？和 ZooKeeper 的 ZAB 协议有什么区别？Nacos 为什么选 Raft？

> 你回答...（提示：Raft vs ZAB / Raft 协议：①分布式一致性算法 → 解决多副本一致性问题 → 和 Paxos 同类但更易理解 ②核心 → Leader 选举 + 日志复制 → 所有写操作通过 Leader → Leader 复制到 Follower → 多数派确认 → 提交 ③Leader 选举 → 三个状态：Follower / Candidate / Leader → 超时未收到心跳 → Follower 变 Candidate → 请求投票 → 多数同意 → 变 Leader ④日志复制 → Leader 收到写请求 → 写本地日志 → 复制到 Follower → 多数确认 → commit → 回复客户端 ⑤安全性保证 → term（任期号）→ 每次选举 term+1 → 日志带 term → 如果 Leader 换了 → 新 Leader 有更高 term → 旧日志不覆盖 → ⑥Raft 强调"可理解性"→ 比 Paxos 简单 → 工业界广泛使用 / ZAB 协议：①ZooKeeper 的协议 → 和 Raft 类似 → Leader 选举 + 崩溃恢复 + 消息广播 ②阶段：①Discovery → 发现Leader ②Synchronization → 同步数据 ③Broadcast → 广播写请求 → Leader → Proposal → Follower ACK → Leader Commit ③和 Raft 的区别 → ZAB 的编号 → zxid（64位 = epoch 32位 + counter 32位）→ 类似 Raft 的 term + index ④ZAB 强调"Primary-backup"→ Leader 是唯一写入口 → 和 Raft 一样 / Raft vs ZAB 区别：①选举 → Raft 随机超时 → 先超时的 Candidate 发起投票 → ZAB 固定超时 → 节点ID最大的优先 ②日志 → Raft 日志是连续的 → 日志匹配 → ZAB 用 zxid → epoch + counter ③成员变更 → Raft 支持在线成员变更 → ZAB 不支持（需要重启）④实现复杂度 → Raft 更简洁 → 有大量开源实现（etcd / Consul / Nacos CP模式）/ Nacos 为什么选 Raft：①Raft 更简洁 → 社区实现多 → Nacos 持久实例用 Raft（CP模式）②Nacos 临时实例用 Distro 协议（AP模式）→ 自己设计的 → 每个节点负责一部分数据 → 异步同步 → 最终一致 ③Nacos 双模式 → 临时实例（服务发现）→ AP → Distro → 可用性优先 → 持久实例（配置管理）→ CP → Raft → 一致性优先 ④选择理由 → 服务发现 → 节点临时 → 挂了就摘 → AP够用 → 配置管理 → 不能丢 → CP必须 / 面试加分：能说出"Raft和ZAB都是Leader+多数派 → Raft随机超时选举/可理解性强 → ZAB固定超时/zxid → Nacos持久实例CP用Raft → 临时实例AP用Distro"→ 展示对一致性协议的理解）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| MySQL InnoDB 锁机制（记录锁/间隙锁/临键锁/意向锁/死锁排查） | 能讲清 / 讲不全 / 不会★ | |
| Redis 数据结构底层实现（SDS/quicklist/skiplist/dict渐进式rehash/listpack） | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（二分查找变体/lowerBound/upperBound/防溢出） | 能讲清 / 讲不全 / 不会★ | |
| ReentrantLock 源码（公平/非公平/Condition/tryLock超时） | 能讲清 / 讲不全 / 不会★ | |
| Spring AOP 原理（JDK代理/CGLIB/5种通知/AspectJ对比/new对象不生效） | 能讲清 / 讲不全 / 不会★ | |
| 分布式理论CAP/BASE（P不是可选的/BASE最终一致/Raft vs ZAB） | 能讲清 / 讲不全 / 不会★ | |
| 跨行转账一致性方案（本地消息表/MQ重试/死信/冲正/日终对账） | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **InnoDB 锁机制**：意向锁（IS/IX）= 行锁的表级标记 → 快速判断有没有行锁避免逐行扫描。行锁三兄弟：记录锁（锁一行）→ 间隙锁（锁间隙防INSERT防幻读）→ 临键锁（记录+间隙）。唯一索引等值命中→退化为记录锁→只锁一行。非唯一索引→加临键锁→锁间隙。间隙锁死锁场景：两个事务对同一段间隙加间隙锁（兼容）→ 各自INSERT → 互相等待 → 死锁。排查用 `SHOW ENGINE INNODB STATUS`。金融场景：核心交易用悲观锁（FOR UPDATE）→ 高频场景用乐观锁（version CAS）
> 2. **Redis 数据结构底层**：String=SDS（O(1)长度/二进制安全/空间预分配）→ List=quicklist（链表+ziplist）→ Hash=ziplist+hashtable → Set=intset+hashtable → ZSet=ziplist+skiplist+hashtable。跳表=多层有序链表O(log n)→范围查询沿链表遍历→实现简单(300行)→Redis选跳表不选红黑树。dict渐进式rehash=两个ht表+每次操作迁移一个桶→避免一次性rehash阻塞。ziplist的prevlen导致连锁更新O(n²)→Redis 7.0换listpack用backlen解决
> 3. **二分查找变体**：lowerBound(第一个≥target) → "可能是答案"的mid不跳过(right=mid) → "不是答案"的跳过(left=mid+1) → 左闭右开[left,right) → 终止left==right。upperBound(第一个>target) → 最后一个≤target = upperBound-1。防溢出 `left+(right-left)/2`
> 4. **ReentrantLock**：state=重入次数(CAS)。非公平锁=先CAS抢不检查队列(刚释放锁的线程缓存命中率高→吞吐量高) → 公平锁=先hasQueuedPredecessors检查队列(严格FIFO但吞吐量低)。Condition=多条件变量精准唤醒(notFull/notEmpty) → await释放锁入等待队列 → signal移到CLH队列。tryLock=CAS不阻塞 → tryLock(timeout)=入队+parkNanos带超时 → 死锁避免用tryLock+超时
> 5. **Spring AOP**：Pointcut=在哪里 → Advice=做什么(5种:@Before/@After/@AfterReturning/@AfterThrowing/@Around,@Around最强)。JDK代理=接口+InvocationHandler → CGLIB=继承+MethodInterceptor → Spring Boot 2.x默认CGLIB(proxy-target-class=true)。Spring AOP=运行时动态代理(方法级) → AspectJ=编译时字节码修改(支持字段/构造器,零运行时开销但需ajc)。new出来的对象不是代理→@Transactional不生效→本质和自调用失效一样(绕过代理)
> 6. **CAP/BASE**：P不是可选的→分区时在C和A之间选→ZK=CP(少数派不服务)/Eureka=AP(可能返回旧数据)。BASE=AP延伸→基本可用+软状态+最终一致。Raft=Leader选举+多数派日志复制+term保证安全→比Paxos简单→Nacos CP用Raft。ZAB=ZK协议→zxid(epoch+counter)→固定超时选举。Nacos双模式:临时实例AP(Distro)/持久实例CP(Raft)
> 7. **跨行转账一致性**：不用2PC(太重+跨行不信任)→不用TCC(跨行不现实)→用本地消息表(扣款+消息表一个事务→MQ→B消费→ACK→重试+幂等+死信告警)→B一直不ACK→MQ重试16次→死信→人工→冲正退款→日终对账兜底。实际跨行=央行清算+对账
