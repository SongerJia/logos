# 面试模拟 - Day 52

> 日期：2026-07-22（周三） | 模拟岗位：阿里云（杭州总部）- 金融云事业部 - Java开发工程师
> 建议时长：85分钟（一面55分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day52，"查漏补缺"阶段第二周。模拟阿里云金融云——为银行/证券/保险机构提供云计算解决方案。面试特点：分布式系统原理深挖 + 中间件源码理解 + 云原生架构。今天引入 Spring 事务传播机制、CAS 原理与 ABA 问题、MySQL Explain 执行计划、Java 8 Stream API 深入、消息队列选型对比 5 个全新话题——都是高频考点但之前没有作为独立话题系统考过。

---

# 一面（55分钟）

## 话题一：Spring 事务传播机制（12分钟）

**面试官：你简历上写了 Spring 事务。Spring 的事务传播机制你了解吗？有哪几种？**

> 你回答...

**追问1：** 先说说什么是事务传播？Spring 提供了哪几种传播行为？

> 你回答...（提示：事务传播 = 一个事务方法调用另一个事务方法时 → 当前事务如何传播 → 是加入当前事务 / 新开事务 / 嵌套事务 / 不开事务 / 强制要求事务 / 7种传播行为：①PROPAGATION_REQUIRED → 默认 → 有事务加入 → 没有就新建 ②PROPAGATION_REQUIRES_NEW → 总是新建 → 挂起当前事务 → 新开独立事务 → 新事务提交/回滚不影响挂起的事务 ③PROPAGATION_NESTED → 嵌套事务 → 有事务 → 创建 savepoint → 子事务回滚到 savepoint → 父事务可以继续 → 没有事务 → 等同 REQUIRED ④PROPAGATION_SUPPORTS → 有事务加入 → 没有事务就以非事务方式执行 ⑤PROPAGATION_NOT_SUPPORTED → 以非事务方式执行 → 如果有事务 → 挂起 ⑥PROPAGATION_MANDATORY → 必须在事务中 → 没有事务 → 抛异常 ⑦PROPAGATION_NEVER → 不能有事务 → 有事务 → 抛异常 / 最常用的三种：REQUIRED（默认，大多数场景）→ REQUIRES_NEW（独立事务，如日志记录不受主事务影响）→ NESTED（嵌套，部分回滚 / 面试重点：7 种 → REQUIRED/REQUIRES_NEW/NESTED 最常用 → 能说清区别就行）

**追问2：** REQUIRED 和 REQUIRES_NEW 的区别是什么？能举个实际场景吗？

> 你回答...（提示：REQUIRED → 加入当前事务 → A 方法调 B 方法 → B 用 REQUIRED → A 和 B 在同一个事务 → B 抛异常 → A 也回滚 → 因为是同一个事务 / REQUIRES_NEW → 新建独立事务 → A 方法调 B 方法 → B 用 REQUIRES_NEW → A 事务挂起 → B 新开事务 → B 提交后 → A 事务恢复 → B 回滚不影响 A / 实际场景：①主流程 + 日志记录 → 主方法（REQUIRED）→ 调日志方法（REQUIRES_NEW）→ 主流程回滚 → 日志已经提交 → 不受影响 → 方便排查问题 ②主流程 + 发通知 → 主方法失败 → 但通知已经发出 → 用户知道操作失败了 → 合理 ③转账 + 记录手续费 → 转账失败 → 手续费不应扣 → 用 REQUIRED → 一起回滚 / 坑：REQUIRES_NEW 会挂起当前事务 → 占用数据库连接 → 如果嵌套层级多 → 连接池耗尽 → 生产事故 / 面试重点：REQUIRED = 同一个事务（一起回滚）→ REQUIRES_NEW = 独立事务（互不影响）→ 日志/通知用 REQUIRES_NEW → 但注意连接池耗尽风险）

**追问3：** NESTED 嵌套事务是怎么实现的？和 REQUIRES_NEW 有什么区别？

> 你回答...（提示：NESTED → 嵌套事务 → 依赖数据库的 savepoint 机制 / 实现：①A 方法（REQUIRED）→ 开启事务 → 调 B 方法（NESTED）→ 在当前事务内创建 savepoint → B 执行 → B 抛异常 → 回滚到 savepoint → B 的操作回滚 → 但 A 的事务还在 → A 可以 catch B 的异常 → 继续执行 → A 提交 → B 的操作已经回滚 → 不影响 A ②B 回滚到 savepoint → 不影响 A 已执行的操作 → A 可以选择继续或回滚整个事务 / NESTED vs REQUIRES_NEW：①NESTED → 一个物理事务 → 多个 savepoint → B 回滚不影响 A → 但 A 回滚 → B 也回滚（因为同一个事务）→ 子事务依赖父事务 ②REQUIRES_NEW → 两个物理事务 → A 事务挂起 → B 独立事务 → B 回滚不影响 A → A 回滚也不影响 B（B 已经提交了）→ 完全独立 ③NESTED → B 的回滚是部分回滚 → A 还能继续 ④REQUIRES_NEW → B 是独立事务 → B 提交了就永久了 / 场景：NESTED → 批量处理 → 1000 条数据 → 每条一个 savepoint → 第 500 条失败 → 回滚到第 500 条的 savepoint → 前 499 条保留 → 继续处理 501-1000 → 比 REQUIRES_NEW 性能好（一个连接）→ 但 MySQL 的 savepoint 会让事务变长 → 锁持有时间长 / 面试重点：NESTED = savepoint → 一个事务内的部分回滚 → 父回滚子也回滚 → 子回滚父不受影响 → REQUIRES_NEW = 两个独立事务 → 互不影响）

**追问4：** Spring 事务有个经典的坑——同一个类里方法 A 调方法 B，B 上加了 @Transactional，事务会生效吗？为什么不生效？

> 你回答...（提示：不生效 → 经典的"自调用失效"问题 / 原因：①Spring 事务基于 AOP 代理 → @Transactional 生效 → 需要通过代理对象调用 → ②方法 A 调方法 B → 是 `this.B()` → this 是目标对象 → 不是代理对象 → 不经过代理 → @Transactional 不生效 → B 没有事务 ③只有从外部通过代理对象调用 → 才经过事务拦截器 → @Transactional 才生效 / 为什么 this 不是代理：①Spring 注入的是代理对象 → 外部调用 `proxy.A()` → 代理拦截 → 进入 A 方法 → A 方法内部 `this.B()` → this 是目标对象（被代理的对象）→ 不是代理 → 直接调用 → 跳过代理 ②AOP 代理 → 在方法调用前后加逻辑 → 自调用绕过了代理 → 无法拦截 / 解决方案：①把 B 移到另一个类 → 外部调用 → 经过代理 ②注入自己 → `@Autowired private XxxService self; self.B()` → self 是代理对象 → 经过代理 → 但可能有循环依赖问题（Spring 4.3+ 支持 self-injection）③AopContext.currentProxy() → `((XxxService) AopContext.currentProxy()).B()` → 获取当前代理对象 → 但需要 `@EnableAspectJAutoProxy(exposeProxy = true)` 开启 ④最推荐 → 拆分到不同类 → 架构清晰 / 面试重点：自调用失效 = this 不是代理 → 不经过事务拦截器 → 解决：拆类 / self-injection / AopContext.currentProxy）

**追问5：** @Transactional 加在 private 方法上会生效吗？为什么？rollbackFor 默认回滚什么异常？

> 你回答...（提示：@Transactional 加在 private → 不生效 / 原因：①Spring AOP 用 CGLIB 或 JDK 动态代理 → JDK 代理只能代理接口方法（public）→ CGLIB 代理通过继承 → 子类不能覆盖父类的 private 方法 → ②所以 @Transactional 在 private/protected 方法上不生效 → 必须 public（protected 在某些版本可以但不推荐）→ 标准：加在 public 方法上 / rollbackFor 默认行为：①Spring @Transactional 默认只回滚 RuntimeException 和 Error → 不回滚 checked Exception ②如 `@Transactional` → 抛 IOException → 不回滚 → 数据已提交 ③需要回滚 checked Exception → `@Transactional(rollbackFor = Exception.class)` → 指定回滚异常类型 ④生产建议 → 一律加 `rollbackFor = Exception.class` → 避免漏回滚 / 为什么默认只回滚 RuntimeException：①Spring 设计哲学 → checked Exception 是业务可预期的 → 不应该回滚 → RuntimeException 是不可预期的 → 应回滚 ②但实际开发 → checked Exception 也可能需要回滚 → 所以生产建议显式指定 / 面试重点：private 不生效（CGLIB 不能覆盖）→ public 方法 → rollbackFor 默认只回滚 RuntimeException → 生产加 `rollbackFor = Exception.class`）

**追问6：** 如果方法 A 有事务，调用方法 B（REQUIRES_NEW），B 执行过程中 A 的数据会怎样？B 能看到 A 未提交的数据吗？

> 你回答...（提示：B 看不到 A 未提交的数据 / 原因：①A 事务开启 → 修改数据 → 未提交 → 调 B（REQUIRES_NEW）→ A 事务挂起 → B 新开事务 → ②B 是新事务 → 数据库隔离级别（如 RC/RR）→ 一个事务看不到另一个未提交事务的数据 → B 看不到 A 的修改 ③如果 A 修改了 id=1 的记录 → B 查 id=1 → 看到的是 A 修改前的值 → 因为 A 没提交 → B 读的是快照（MVCC）→ ④B 提交后 → A 恢复 → A 能看到 B 的修改（如果隔离级别允许）→ 但 A 回滚 → A 的修改回滚 → B 已经提交 → 不受影响 / 潜在死锁：①A 修改了 id=1 的记录 → 持有行锁 → 调 B → B 也想修改 id=1 → 等 A 释放锁 → 但 A 挂起了 → A 不会提交也不会回滚 → B 一直等 → 死锁 ②所以 REQUIRES_NEW → 子事务不要操作和父事务相同的行 → 否则可能死锁 / 生产注意：①REQUIRES_NEW 会挂起父事务 → 占两个数据库连接 → 连接池要够 ②避免父子操作同一行 → 死锁 ③日志/通知等独立操作 → 用 REQUIRES_NEW → 主业务用 REQUIRED / 面试加分：能说出"B 看不到 A 未提交数据（MVCC 快照）→ 可能死锁（A 持锁 B 等锁）→ 避免操作同一行"→ 展示对事务+锁+MVCC的综合理解）

---

## 话题二：CAS 原理与 ABA 问题（10分钟）

**面试官：你提到过 ConcurrentHashMap 用 CAS。CAS 是什么？它的原理是什么？**

> 你回答...

**追问1：** 先说说 CAS 是什么？它是怎么保证原子性的？

> 你回答...（提示：CAS = Compare And Swap → 比较并交换 → 无锁原子操作 / 原理：①三个参数 → 内存位置 V → 期望值 A → 新值 B ②如果 V 的当前值 == A → 把 V 设为 B → 返回 true ③如果 V 的当前值 != A → 说明被其他线程修改了 → 不做任何操作 → 返回 false ④整个操作是原子的 → CPU 指令级别保证 → x86 的 CMPXCHG 指令 / Java 中的 CAS：①`sun.misc.Unsafe` 类 → `compareAndSwapInt/Object/Long` → 直接调用 native 方法 → 底层是 CPU 指令 ②JDK 9+ → `VarHandle` → 替代 Unsafe → 更安全 ③AtomicInteger → `compareAndSet(expect, update)` → 封装了 Unsafe 的 CAS / 为什么 CAS 能保证原子性：①CAS 是一条 CPU 指令（CMPXCHG）→ 不可被打断 → 原子的 ②不是用锁 → 没有线程阻塞/唤醒的开销 → 性能高 ③CAS 是乐观锁的核心思想 → 先操作 → 冲突了再重试 → 不先加锁 / 面试重点：CAS = 比较+交换 → CPU 指令保证原子性 → Unsafe 调用 → AtomicInteger.compareAndSet 封装）

**追问2：** CAS 有什么问题？ABA 问题是什么？怎么解决？

> 你回答...（提示：CAS 的三个问题：①ABA 问题 → 值从 A → B → A → CAS 认为没变 → 实际变了 → 可能有问题 ②自旋开销 → CAS 失败 → 自旋重试 → 如果竞争激烈 → 长时间自旋 → 浪费 CPU ③只能保证一个变量的原子操作 → 多个变量不能一起 CAS / ABA 问题：①线程1 读到值 A → 准备 CAS(A → C) → ②线程2 把 A 改成 B → 再改成 A → ③线程1 CAS → 发现还是 A → 认为没被修改 → CAS 成功 → ④但实际上值被修改过 → ABA 问题 / ABA 的实际危害：①栈场景 → 栈顶 A → 线程1 弹出 A → 准备 CAS(A → B) → 线程2 弹出 A → 弹出 B → 压入 A → 线程1 CAS 成功 → 但 B 已经被弹出 → 栈数据丢失 ②转账 → 余额 100 → 转 50 → CAS(100 → 50) → 中间有人存50再取50 → 余额还是100 → CAS 成功 → 但中间有交易记录 / 解决：①版本号 → 每次修改 → 版本号+1 → CAS 比较值+版本号 → `AtomicStampedReference` → 每个引用带一个 stamp（版本号）→ `compareAndSet(expectedReference, newReference, expectedStamp, newStamp)` → 值和版本号都匹配才能 CAS ②`AtomicMarkableReference` → 用 boolean 标记 → 只有 marked/unmarked 两种 → 更轻量 / 面试重点：ABA = A→B→A → CAS 误判 → 用 AtomicStampedReference 加版本号解决 → 自旋开销 + 单变量局限）

**追问3：** AtomicInteger 的 incrementAndGet 是怎么实现的？能说说自旋的流程吗？

> 你回答...（提示：AtomicInteger.incrementAndGet → CAS 自旋 / 源码流程：①`public final int incrementAndGet() { return unsafe.getAndAddInt(this, valueOffset, 1) + 1; }` ②Unsafe.getAndAddInt → `int v; do { v = getIntVolatile(obj, offset); } while (!compareAndSwapInt(obj, offset, v, v + delta)); return v;` ③流程：读当前值 v → CAS(v, v+1) → 成功 → 返回 v+1 → 失败 → 重新读 v → 重试 CAS → 循环直到成功 / 自旋 = do-while 循环 → CAS 失败不阻塞 → 不停重试 → 乐观策略 / 为什么用 do-while 不用 while：①do-while → 先执行一次 → 至少读一次值 → 保证 v 有初值 ②while → 可能先判断不执行 → v 没有值 → NPE / 自旋的代价：①低竞争 → CAS 几乎一次成功 → 性能比锁好 → 没有阻塞/唤醒开销 ②高竞争 → 多个线程同时 CAS → 大量失败重试 → CPU 空转 → 性能可能比锁差 → 因为锁会让线程休眠 → 不占 CPU → 自旋占 CPU / JDK 8 的优化：LongAdder → 用分段 CAS → 多个 Cell → 每个线程 hash 到不同 Cell → 各自 CAS → 最后 sum → 减少竞争 → 适合高并发计数器 / 面试重点：incrementAndGet = CAS 自旋（do-while + compareAndSwapInt）→ 低竞争高性能 → 高竞争用 LongAdder 分段）

**追问4：** CAS 和 synchronized 有什么区别？什么时候该用 CAS，什么时候该用锁？

> 你回答...（提示：CAS vs synchronized / 区别：①实现方式 → CAS = 无锁 → CPU 指令 → 乐观策略 → synchronized = 有锁 → OS mutex → 悲观策略 ②竞争低 → CAS 好 → 无阻塞 → 无开销 → synchronized 有加锁/释放开销 ③竞争高 → CAS 差 → 自旋浪费 CPU → synchronized 好 → 线程休眠不占 CPU ④公平性 → CAS 不公平 → 先到的可能后成功 → synchronized 可以公平（ReentrantLock fair=true）⑤功能 → CAS 只能原子更新一个变量 → synchronized 可以保护临界区（多条语句）→ 复杂逻辑用锁 / 什么时候用 CAS：①简单原子操作 → 计数器 → AtomicInteger/LongAdder ②低竞争场景 → 偶尔并发 → CAS 一次成功 ③无锁数据结构 → ConcurrentLinkedQueue → CAS 链表操作 / 什么时候用锁：①复杂临界区 → 多条语句需要原子性 → CAS 无法保证多变量 ②高竞争 → 自旋开销大 → 锁让线程休眠 ③需要公平性/条件等待 → ReentrantLock + Condition / 实际选择：①AtomicInteger → 低竞争计数 → CAS ②ConcurrentHashMap → 桶级 synchronized → 锁粒度小 → 高并发 ③ReentrantLock → 需要公平/超时/条件 → 用锁 / 面试重点：CAS 无锁乐观适合低竞争简单操作 → synchronized 有锁悲观适合高竞争复杂临界区 → ConcurrentHashMap 结合 CAS + synchronized）

**追问5：** Unsafe 类你了解吗？为什么 JDK 要限制对它的访问？

> 你回答...（提示：Unsafe = sun.misc.Unsafe → 直接操作内存和 CAS 的底层工具 / 功能：①CAS 操作 → compareAndSwapInt/Long/Object → 所有 Atomic 类的基础 ②直接内存操作 → allocateMemory/freeMemory/putLong → 绕过 JVM 堆 → 直接操作堆外内存 → NIO DirectByteBuffer 的基础 ③对象操作 → objectFieldOffset → 获取字段偏移量 → CAS 需要知道字段在内存中的位置 ④park/unpark → 线程阻塞/唤醒 → AQS/LockSupport 的基础 ⑤类加载 → defineClass → 动态定义类 / 为什么叫 Unsafe：①直接操作内存 → 不受 JVM 管理 → 容易内存泄漏 → 忘记 freeMemory → 堆外内存泄漏 ②绕过安全检查 → 可以做很多危险操作 → 破坏 JVM 安全模型 ③不是标准 API → sun.misc 包 → JDK 内部使用 → 不保证兼容性 → 版本升级可能消失 / JDK 9+ 模块化 → 封装 Unsafe → 外部代码不能直接使用 → 用 VarHandle 替代 → 正式 API → 功能类似但安全 / 为什么很多框架还在用 Unsafe：①性能 → Unsafe 比 VarHandle 快 → 直接 native 调用 → VarHandle 有多态开销 ②历史原因 → 大量框架（Netty/Spring/Cassandra）依赖 Unsafe → 短期无法迁移 ③JDK 提供兼容 → `--add-opens java.base/sun.misc=ALL-UNNAMED` → 模块化开放 → 但最终要迁移 / 面试重点：Unsafe = CAS + 堆外内存 + park/unpark → 直接操作内存不安全 → JDK 9+ 用 VarHandle 替代 → 框架因性能还在用）

---

## 话题三：手写代码 - 单例模式 DCL（8分钟）

**面试官：写一个线程安全的单例模式，用双重检查锁（DCL）。写完说说每一步为什么这么写。**

你在纸上/白板上写代码...

**追问1：** 先说说你的代码结构。为什么叫"双重检查"？两次 check 各检查什么？

> 你回答...（提示：DCL 单例代码：
```java
public class Singleton {
    private static volatile Singleton instance;

    private Singleton() {}

    public static Singleton getInstance() {
        if (instance == null) {                    // 第一次检查
            synchronized (Singleton.class) {
                if (instance == null) {            // 第二次检查
                    instance = new Singleton();     // 创建实例
                }
            }
        }
        return instance;
    }
}
```
/ 双重检查 = 两次 if (instance == null)：①第一次检查 → 不加锁 → 如果已经创建 → 直接返回 → 避免每次都加锁 → 性能好 ②第二次检查 → 加锁后 → 防止多个线程同时通过第一次检查 → 都等锁 → 第一个线程创建实例 → 释放锁 → 第二个线程拿到锁 → 如果不检查 → 又创建一个 → 不行 → 所以第二次检查 → 确保只创建一次 / 为什么不直接全加锁：①如果整个方法加 synchronized → 每次调用都加锁 → 即使实例已创建 → 性能差 ②第一次检查 → 实例已创建 → 直接返回 → 不加锁 → 99% 的情况不需要加锁 → 性能好 / 面试重点：第一次检查避免不必要的加锁 → 第二次检查防止重复创建）

**追问2：** 为什么 instance 要加 volatile？不加会怎样？

> 你回答...（提示：instance 必须加 volatile → 不加有线程安全问题 / 原因：`instance = new Singleton()` 不是原子操作 → 分三步：①分配内存空间 → ②初始化对象（调用构造器）→ ③把内存地址赋给 instance → 指令重排可能导致 ①③② → 分配内存 → 赋值给 instance → 但还没初始化 / 问题场景：①线程A 执行到 ①③ → instance 不为 null → 但还没执行 ② → 对象还没初始化 ②线程B 第一次检查 → instance != null → 直接返回 instance → 但对象还没初始化 → 线程B 使用未初始化的对象 → NPE / volatile 的作用：①禁止指令重排 → 保证 ①②③ 顺序执行 → ②保证可见性 → 线程A 创建完 → 线程B 立即可见 → 不需要等主内存同步 / 为什么 synchronized 不能替代 volatile：①synchronized 保证原子性和可见性 → 但在锁内 → 锁外不保证 ②第一次检查在锁外 → 没有 synchronized 保护 → 可能读到未初始化的对象 ③volatile 保证锁外的可见性和有序性 → 第一次检查时 → 要么是 null → 要么是完整初始化的对象 / 面试重点：`new Singleton()` 不是原子操作 → 指令重排 ①③② → volatile 禁止重排 → 保证可见性 → 第一次检查（锁外）安全）

**追问3：** 除了 DCL，还有哪些实现单例的方式？各有什么优缺点？

> 你回答...（提示：5 种单例实现：①饿汉式 → 类加载时就创建 → `private static Singleton instance = new Singleton();` → 线程安全（类加载保证）→ 但不能延迟加载 → 如果不用就浪费 ②懒汉式（非线程安全）→ 第一次调用时创建 → `if (instance == null) instance = new Singleton();` → 多线程不安全 → 不推荐 ③DCL → 双重检查锁 + volatile → 延迟加载 + 线程安全 → 推荐 ④静态内部类 → `private static class Holder { static final Singleton INSTANCE = new Singleton(); }` → `public static Singleton getInstance() { return Holder.INSTANCE; }` → 利用了类加载机制 → Holder 类在 getInstance 调用时才加载 → 延迟加载 → 类加载线程安全 → 不需要 volatile → 推荐 ⑤枚举 → `public enum Singleton { INSTANCE; }` → 枚举天然线程安全 → 防反射破坏 → Effective Java 推荐 → 但不能延迟加载 → 不灵活 / 选型：①不需要延迟加载 → 枚举（最安全）→ 或饿汉式 ②需要延迟加载 → 静态内部类（推荐）→ 或 DCL ③需要传参 → DCL（静态内部类和枚举不好传参）→ 但单例传参本身是反模式 / 面试重点：DCL + volatile → 静态内部类（类加载延迟+线程安全）→ 枚举（防反射→Effective Java推荐）→ 三种推荐方式）

**追问4：** 枚举单例为什么能防反射破坏？DCL 能被反射破坏吗？

> 你回答...（提示：枚举防反射：①反射创建对象 → `Constructor.newInstance()` → ②Constructor 源码 → 如果是枚举 → `if ((clazz.getModifiers() & Modifier.ENUM) != 0) throw new IllegalArgumentException("Cannot reflectively create enum objects");` → ③JVM 层面禁止反射创建枚举对象 → 枚举天然单例 / DCL 被反射破坏：①反射获取构造器 → `constructor.setAccessible(true)` → `constructor.newInstance()` → 创建新实例 → 单例被破坏 ②可以构造器内检查 → `if (instance != null) throw new RuntimeException("单例已存在");` → 但反射可以绕过 ③序列化/反序列化 → DCL 实现 Serializable → 反序列化创建新对象 → 单例破坏 → 枚举的序列化由 JVM 保证 → 反序列化返回同一个实例 / 面试加分：①枚举天然防反射 + 防序列化 → Effective Java 第一选择 ②DCL 能被反射破坏 → 可以加构造器检查 → 但不是绝对安全 ③实际项目 → Spring Bean 默认单例 → 容器管理 → 不需要自己写单例 → 但面试必考）

---

## 话题四：MySQL Explain 执行计划详解（12分钟）

**面试官：你说做过慢 SQL 优化。你用 EXPLAIN 分析执行计划时，主要看哪些字段？**

> 你回答...

**追问1：** EXPLAIN 的输出有很多字段，你觉得最重要的几个是什么？分别代表什么？

> 你回答...（提示：EXPLAIN 重要字段（按重要程度排）：①type → 访问类型 → 表示 MySQL 怎么找到数据 → 从好到差：system > const > eq_ref > ref > range > index > ALL → 越靠左越好 → ALL = 全表扫描 → 最差 ②key → 实际使用的索引 → 如果是 NULL → 没用索引 → 全表扫描 ③key_len → 索引使用的字节数 → 可以判断联合索引用了几个字段 → 越短越好（用最少的索引字段满足查询）④rows → MySQL 估算要扫描的行数 → 越小越好 → 不是精确值 → 是估算 ⑤Extra → 额外信息 → 非常重要 → Using index（覆盖索引→好）→ Using where（需要回表→差）→ Using temporary（临时表→很差）→ Using filesort（文件排序→很差）⑥possible_keys → 可能用到的索引 → 如果有但 key 是 NULL → 索引没生效 ⑦ref → 索引比较的值 → 如 const / 列名 / func / 面试重点：type（访问类型）→ key（实际索引）→ rows（扫描行数）→ Extra（额外信息）→ 这4个最关键）

**追问2：** type 字段的几种类型你详细说说？从 const 到 ALL 分别什么意思？

> 你回答...（提示：type 类型从好到差：①system → 表只有一行 → 系统表 → 几乎不出现 ②const → 通过主键或唯一索引等值查询 → 最多一条匹配 → 如 `WHERE id = 1` → 最快 ③eq_ref → JOIN 时 → 被驱动表用主键或唯一索引等值匹配 → 最多一条 → 如 `JOIN b ON a.id = b.id` → b.id 是主键 → eq_ref ④ref → 非唯一索引等值查询 → 可能多条匹配 → 如 `WHERE name = '张三'` → name 有非唯一索引 → ref ⑤range → 索引范围查询 → `WHERE id BETWEEN 1 AND 100` → `WHERE id IN (1,2,3)` → `WHERE create_time > '2026-01-01'` → 有索引 → ⑥index → 扫描整个索引树 → 不回表 → 比 ALL 好 → 但还是全扫描 → 如 `SELECT COUNT(*) FROM users` → 有二级索引 → 扫索引不扫数据 ⑦ALL → 全表扫描 → 没用索引 → 最差 → 必须优化 / 面试标准：①const/eq_ref → 最优 → 主键/唯一索引 ②ref/range → 良好 → 非唯一索引/范围查询 ③index → 一般 → 扫索引不扫数据 ④ALL → 差 → 全表扫描 → 必须优化 → 加索引 / 生产要求：type 至少 range → 最好 ref/const → 不允许 ALL / 面试重点：const（主键等值）→ eq_ref（JOIN唯一索引）→ ref（非唯一索引等值）→ range（范围）→ index（扫索引）→ ALL（全表扫描）→ 生产不允许 ALL）

**追问3：** Extra 字段的 Using index 和 Using where 有什么区别？Using temporary 和 Using filesort 意味着什么？

> 你回答...（提示：Extra 关键值：①Using index → 覆盖索引 → 查询的列都在索引中 → 不需要回表 → 性能好 → 如 `SELECT id, name FROM users WHERE name = '张三'` → name 有索引 → 索引存了 name 和 id（主键）→ 不用回表 → Using index ②Using where → 需要回表 → 在存储引擎返回数据后 → MySQL Server 层再过滤 → 性能差 → 如 `SELECT * FROM users WHERE name = '张三' AND age > 20` → name 有索引 → 但 age 不在索引中 → 用 name 索引找到行 → 回表取完整数据 → 再过滤 age > 20 → Using where ③Using index condition → 索引下推（ICP）→ MySQL 5.6+ → 在存储引擎层就用索引过滤 → 减少回表次数 → 比 Using where 好 → 如 `SELECT * FROM users WHERE name LIKE '张%' AND age > 20` → name+age 联合索引 → 在索引层就过滤 age → 不用回表再过滤 ④Using temporary → 用了临时表 → 通常出现在 GROUP BY / DISTINCT / ORDER BY → 如果内存放不下 → 写磁盘 → 性能差 → 优化：加索引让 GROUP BY 走索引 ⑤Using filesort → 文件排序 → ORDER BY 的字段没有索引 → 需要额外排序 → 性能差 → 优化：给 ORDER BY 字段加索引 → 或让 filesort 在内存完成（sort_buffer_size）/ 面试重点：Using index（覆盖索引→好）→ Using where（回表→差）→ Using temporary（临时表→必须优化）→ Using filesort（排序→加索引）→ Using index condition（索引下推→好））

**追问4：** 你说做过慢 SQL 优化。讲一个具体的案例，从 EXPLAIN 分析到优化的全过程。

> 你回答...（提示：实际案例 → 你的简历提到"将批量查询耗时从5分钟优化到1分钟以内" → 用这个案例 / 优化流程：①发现慢 SQL → 慢查询日志 → `slow_query_log = ON` → `long_query_time = 1` → 超过1秒记录 ②EXPLAIN 分析 → `EXPLAIN SELECT * FROM t_account WHERE cust_id = ? AND status = '1' ORDER BY create_time DESC LIMIT 20;` → 发现 type = ALL（全表扫描）→ key = NULL（没用索引）→ rows = 500万（扫全表）→ Extra = Using filesort（排序没走索引）→ 5分钟 ③分析原因 → cust_id 没有索引 → 全表扫描 → create_time 没有索引 → filesort ④优化方案 → 创建联合索引 → `idx_cust_status_time (cust_id, status, create_time)` → 覆盖 WHERE + ORDER BY ⑤优化后 → EXPLAIN → type = ref（非唯一索引等值）→ key = idx_cust_status_time → rows = 20（只扫20条）→ Extra = Using index（覆盖索引→不用回表）→ 0.5秒 ⑥进一步优化 → 如果 SELECT 的列不在索引中 → 回表 → 可以用覆盖索引 → 把 SELECT 的列加入索引 → 或用延迟关联（SELECT id FROM ... LIMIT 20 → 再 JOIN 取完整数据）/ 优化效果：5分钟 → 0.5秒 → 600倍提升 / 面试加分：能说完整流程 → 慢日志发现 → EXPLAIN 分析（type/key/rows/Extra）→ 加联合索引 → 覆盖索引/延迟关联 → 量化效果）

**追问5：** 什么是覆盖索引？什么是回表？怎么判断一个查询是否用了覆盖索引？

> 你回答...（提示：覆盖索引 = 查询的列都在索引中 → 不需要回表 / 回表 = 二级索引找到主键 → 再用主键查聚簇索引拿完整数据 → 两次 IO / 覆盖索引示例：①`SELECT id, name FROM users WHERE name = '张三'` → name 有索引 → 二级索引存了 name + id（主键）→ 查询只需要 id 和 name → 都在索引中 → 不用回表 → Extra = Using index ②`SELECT id, name, age FROM users WHERE name = '张三'` → 如果索引只有 (name) → age 不在索引中 → 需要回表取 age → Extra = Using where ③如果把索引改成 (name, age) → name 和 age 都在索引中 → id 是主键自动在索引中 → 覆盖索引 → Using index / 判断方法：EXPLAIN → Extra 有 Using index → 覆盖索引 → 没有 Using where → 不需要回表 / 覆盖索引的好处：①减少 IO → 不用回表 → 少一次随机 IO ②性能好 → 特别是数据量大时 → 回表是随机 IO → 慢 / 实际优化：①高频查询 → 把 SELECT 的列加入索引 → 覆盖索引 ②但不要加太多列 → 索引变长 → 写入变慢 → 索引占空间 ③权衡 → 高频查询覆盖索引 → 低频查询回表可以接受 / 面试重点：覆盖索引 = 查询列都在索引中 → 不回表 → Using index → 高频查询优化手段）

---

# 二面（30分钟）

## 话题五：Java 8 Stream API 深入（10分钟）

**面试官：Java 8 的 Stream 你用过吧。Stream 的中间操作和终端操作有什么区别？什么是惰性求值？**

> 你回答...

**追问1：** 先说说 Stream 的操作分类。哪些是中间操作，哪些是终端操作？

> 你回答...（提示：Stream 操作分两类：①中间操作 → 返回 Stream → 可以链式调用 → 不触发执行 → 惰性求值 → 如 filter / map / flatMap / sorted / distinct / limit / skip / peek ②终端操作 → 返回非 Stream（值/集合/void）→ 触发执行 → 如 collect / forEach / count / reduce / anyMatch / allMatch / findFirst / findAny / min / max / toArray / 惰性求值 = 中间操作不立即执行 → 直到遇到终端操作 → 整个流水线才执行 → 如 `stream.filter(x -> x > 0).map(x -> x * 2).count()` → filter 和 map 不会执行 → 直到 count() → 整个流水线一起执行 / 为什么惰性求值：①性能 → 如果提前知道只要前3个 → `stream.filter(...).limit(3)` → filter 只需处理到找到3个为止 → 不用处理所有元素 → 短路 ②可以融合操作 → filter + map 可以在一次遍历中完成 → 不用先 filter 一遍再 map 一遍 → 减少遍历次数 / 面试重点：中间操作返回 Stream 不执行（惰性）→ 终端操作触发执行 → 惰性求值实现短路和操作融合）

**追问2：** map 和 flatMap 的区别是什么？什么时候用 flatMap？

> 你回答...（提示：map vs flatMap / map → 一对一转换 → 一个元素 → 映射成一个新元素 → `stream.map(x -> x * 2)` → [1,2,3] → [2,4,6] / flatMap → 一对多转换 + 拍平 → 一个元素 → 映射成多个新元素（Stream）→ flatMap 把多个 Stream 拍平成一个 → `stream.flatMap(x -> Stream.of(x, x*10))` → [1,2,3] → [1,10,2,20,3,30] / 典型场景：①嵌套 List 拍平 → `List<List<Integer>>` → `list.stream().flatMap(List::stream).collect(toList())` → 拆成一层 ②字符串拆分 → `["hello world", "hi there"]` → `stream.flatMap(s -> Arrays.stream(s.split(" ")))` → ["hello", "world", "hi", "there"] ③一对多关系 → 订单列表 → 每个订单有多个商品 → flatMap → 所有商品列表 / map vs flatMap 本质：①map → `Function<T, R>` → 输入一个 → 输出一个 → ②flatMap → `Function<T, Stream<R>>` → 输入一个 → 输出一个 Stream → flatMap 把所有 Stream 拍平 → 如果 map 返回 Stream → 结果是 `Stream<Stream<R>>` → 嵌套 → flatMap 拍平成 `Stream<R>` / 面试重点：map 一对一 → flatMap 一对多+拍平 → 嵌套结构拆平用 flatMap）

**追问3：** Stream 的并行流 parallelStream 是怎么实现的？有什么坑？

> 你回答...（提示：parallelStream = 并行流 → 用 ForkJoinPool.commonPool() → 多线程并行处理 / 实现原理：①把数据源分成多个分片 → 每个分片由一个线程处理 → 最后合并结果 ②用 ForkJoinPool → 分治 → Fork（拆分）→ Join（合并）③默认线程数 = CPU 核心数 → 可以通过 `ForkJoinPool.commonPool()` 的并行度设置 / 坑：①共享 ForkJoinPool → 所有 parallelStream 共用一个线程池 → 如果一个 parallelStream 任务阻塞 → 整个 JVM 的 parallelStream 都阻塞 → 影响其他并行流 ②线程安全 → 并行处理 → 共享变量修改不安全 → 如 `parallelStream().forEach(x -> list.add(x))` → ArrayList 不安全 → 可能丢数据 → 要用线程安全集合或 collect ③顺序不保证 → 并行处理 → 元素顺序可能变 → 如果需要顺序 → 用 `forEachOrdered` ④不一定快 → 数据量小时 → 线程切换开销 > 并行收益 → 反而更慢 → 建议 >1万条数据才用 ⑤IO 密集型不适合 → 并行流用 CPU 线程 → IO 阻塞 → 浪费 CPU → 用自定义线程池 / 安全使用：①大数据量 + CPU 密集 → 可以用 ②用 collect 而不是 forEach 修改共享变量 ③不要在 parallelStream 里做 IO → 阻塞线程池 ④如果需要自定义线程池 → `stream.parallel().collect(...)` → 或 ForkJoinPool.submit → 在自定义池中执行 / 面试重点：parallelStream 用 ForkJoinPool.commonPool → 共享线程池是最大坑 → 线程安全 → 顺序不保证 → 大数据量+CPU密集才用）

**追问4：** Stream 的 toMap 方法有个常见异常，你知道是什么吗？怎么解决？

> 你回答...（提示：toMap 常见异常：`IllegalStateException: Duplicate key` → 重复 key / 原因：`stream.collect(Collectors.toMap(User::getId, User::getName))` → 如果两个 User 的 id 相同 → toMap 不知道用哪个 value → 抛异常 / 解决：①指定 merge function → `Collectors.toMap(User::getId, User::getName, (oldVal, newVal) -> newVal)` → 重复时用新值覆盖旧值 ②`(oldVal, newVal) -> oldVal` → 保留旧值 ③用 groupingBy → `Collectors.groupingBy(User::getId, Collectors.mapping(User::getName, Collectors.toList()))` → 一个 key 对应多个 value → List / 其他坑：①toMap value 为 null → NPE → `Collectors.toMap` 内部用 `Map.merge` → merge 不允许 null value → 如果 value 可能为 null → 用 `HashMap` 手动处理 ②HashMap 无序 → `Collectors.toMap` 默认用 HashMap → 顺序不保证 → 需要有序 → `Collectors.toMap(k, v, merge, LinkedHashMap::new)` / 面试重点：toMap 重复 key 抛异常 → 指定 merge function 解决 → value 为 null 会 NPE → 用 LinkedHashMap 保证顺序）

**追问5：** Stream 的短路操作有哪些？findAny 和 findFirst 有什么区别？

> 你回答...（提示：短路操作 = 遇到满足条件的结果 → 提前结束 → 不处理剩余元素 / Stream 短路操作：①anyMatch → 任意一个匹配 → 返回 true → 遇到第一个匹配就结束 ②allMatch → 全部匹配 → 遇到第一个不匹配 → 返回 false → 结束 ③noneMatch → 全部不匹配 → 遇到第一个匹配 → 返回 false → 结束 ④findFirst → 返回第一个元素 → 串行流 → 第一个 → 遇到就结束 ⑤findAny → 返回任意一个 → 并行流 → 找到任意一个就返回 → 性能更好 ⑥limit(n) → 取前 n 个 → 取够就结束 / findFirst vs findAny：①findFirst → 返回流中第一个元素 → 串行流和并行流都返回第一个 → 并行流需要跨线程合并 → 性能差 ②findAny → 返回任意一个 → 串行流 → 通常也是第一个 → 并行流 → 任意线程先找到就返回 → 不需要等第一个 → 性能好 ③语义 → findFirst → 有序 → 需要第一个 → findAny → 无序 → 任意一个都行 / 实际场景：①筛选第一个满足条件的 → findFirst → 如"找到第一个年龄>18的用户" ②判断是否存在 → anyMatch → 如"是否有年龄>18的用户" → 比 filter + findFirst + isPresent 更简洁 ③并行处理 → findAny → 不关心顺序 → 性能好 / 面试重点：短路操作提前结束 → anyMatch/allMatch/noneMatch/findFirst/findAny/limit → findFirst 有序（并行差）→ findAny 无序（并行好））

---

## 话题六：消息队列选型对比 + 核心设计题：金融云多租户数据隔离方案（20分钟）

**面试官：你用过 RocketMQ 和 Kafka。如果让你做技术选型，你会怎么选？它们各自的适用场景是什么？**

> 你回答...

**追问1：** 先对比一下 Kafka、RocketMQ、RabbitMQ 三者的核心区别。

> 你回答...（提示：三者对比 / Kafka：①LinkedIn 开源 → Apache 顶级项目 → 分布式流处理平台 ②高吞吐 → 百万级 TPS → 日志/大数据场景 ③顺序消息 → 分区内有序 ④持久化 → 磁盘顺序写 → 零拷贝 ⑤缺点 → 功能简单 → 不支持事务消息（0.11版本后支持但不如 RocketMQ）→ 不支持延迟消息 → 消费模式单一 → 运维复杂 / RocketMQ：①阿里开源 → 基于 Kafka 改进 → 金融级消息中间件 ②事务消息 → 半消息机制 → DB+MQ 跨系统一致性 → 金融场景 ③延迟消息 → 18个延迟级别 → 定时任务 ④顺序消息 → 分区有序 ⑤消息过滤 → Tag/SQL92 → 服务端过滤 → 减少网络传输 ⑥死信队列 → 消费失败 → 进入死信 → 人工处理 ⑦缺点 → 吞吐量比 Kafka 略低 → 社区不如 Kafka 活跃 / RabbitMQ：①Erlang 开发 → AMQP 协议 → 传统消息中间件 ②路由灵活 → Exchange + Queue → 4种 Exchange 类型 → Direct/Fanout/Topic/Headers → 复杂路由 ③确认机制 → 生产者确认 + 消费者 ACK → 消息可靠性高 ④缺点 → 吞吐量低 → 万级 TPS → Erlang 运维难 → 不适合大数据 / 选型总结：①大数据/日志 → Kafka → 高吞吐 ②金融/电商 → RocketMQ → 事务消息/延迟消息/可靠性 ③复杂路由/小规模 → RabbitMQ → 路由灵活 ④云原生 → 各云厂商 MQ → 如阿里云 RocketMQ / 面试重点：Kafka 高吞吐 → RocketMQ 金融级（事务/延迟/过滤）→ RabbitMQ 路由灵活但吞吐低）

**追问2：** 你选了 RocketMQ 做金融场景。RocketMQ 的事务消息和 Kafka 的事务有什么区别？

> 你回答...（提示：RocketMQ 事务消息 vs Kafka 事务 / RocketMQ 事务消息：①场景 → 跨系统一致性 → 本地 DB 操作 + 发 MQ → 要么都成功要么都失败 ②机制 → 半消息 → 发送半消息（消费者不可见）→ 执行本地事务 → COMMIT/ROLLBACK → 超时回查 ③回查 → RocketMQ 回调 `checkLocalTransaction()` → 检查本地事务状态 → 重新 COMMIT/ROLLBACK ④最终一致 → 不是强一致 → 半消息 COMMIT → 消费者消费 → 最终一致 / Kafka 事务：①场景 → 多分区原子写入 → 一次事务 → 写多个 Topic/Partition → 要么全成功要么全失败 ②机制 → TransactionalId → initTransactions → beginTransaction → send → sendOffsets → commitTransaction ③和 RocketMQ 区别 → Kafka 事务是"多个 Kafka 写入的原子性" → 不涉及外部 DB → RocketMQ 事务是"DB + MQ 跨系统一致性" ④Kafka 事务更严格 → 但只能保证 Kafka 内部一致 → 不能保证 DB+MQ 一致 / 本质区别：①RocketMQ → 半消息 + 本地事务 + 回查 → 解决 DB+MQ 跨系统一致性 → 最终一致 ②Kafka → 事务协调器 + TransactionalId → 解决多分区原子写入 → Kafka 内部一致 ③如果需求是"操作 DB + 发 MQ" → 用 RocketMQ 事务消息 ④如果需求是"写多个 Topic 要么全成功" → 用 Kafka 事务 / 面试重点：RocketMQ 事务 = DB+MQ 跨系统最终一致 → 半消息+回查 → Kafka 事务 = Kafka 内部多分区原子写入 → 场景不同）

**追问3：** 好。现在一个实际的设计题：阿里云金融云要服务多家银行，每家银行的数据必须完全隔离。你怎么设计多租户数据隔离方案？

> 你回答...（提示：多租户数据隔离三种模式：①独立数据库 → 每个租户一个 DB → 物理隔离 → 安全性最高 → 成本最高 → 适合大客户（大银行）②共享数据库 + 独立 Schema → 一个 DB → 每个 Schema 一个租户 → 逻辑隔离 → 中等安全 → 中等成本 ③共享数据库 + 共享 Schema + 租户字段 → 所有数据在一个表 → 用 tenant_id 字段区分 → 成本最低 → 安全性最差 → 适合小客户 → 但 SQL 必须带 tenant_id → 漏了就串数据 / 阿里云金融云选型：①大银行 → 独立 DB → 物理隔离 → 满足监管要求 → 银行核心数据不能和其他银行混 ②中小银行 → 共享 DB + 独立 Schema → 逻辑隔离 → 成本可控 ③微服务架构 → 每个租户独立命名空间 → K8s Namespace 隔离 → 网络隔离 → NetworkPolicy / 技术实现：①租户路由 → API Gateway → 从请求头/Token 提取 tenant_id → 路由到对应租户的数据源 ②数据源动态切换 → AbstractRoutingDataSource → 根据 TenantContext 切换数据源 → ThreadLocal 存储当前租户 ③MyBatis 拦截器 → 自动在 SQL 加 WHERE tenant_id = ? → 防止漏写 ④Redis 隔离 → key 加 tenant_id 前缀 → `tenant_1:session:xxx` ⑤MQ 隔离 → Topic 加 tenant_id → 或用 Tag 过滤 / 安全隔离：①网络隔离 → VPC → 每个大租户独立 VPC → 安全组规则 ②权限隔离 → RBAC → 租户管理员 → 只能管理自己租户 ③审计 → 所有操作记录 tenant_id → 审计日志按租户查询 / 面试重点：独立DB（大银行）→ 独立Schema（中小）→ 租户字段（小客户）→ 路由用 AbstractRoutingDataSource → MyBatis 拦截器自动加 tenant_id → Redis/MQ 加前缀）

**追问4：** 共享数据库 + 租户字段模式下，怎么防止某个查询漏了 tenant_id 导致串数据？

> 你回答...（提示：防止漏 tenant_id 的方案：①MyBatis 拦截器 → 拦截所有 SQL → 自动注入 `WHERE tenant_id = ?` → 从 ThreadLocal 获取当前租户 → 如果 ThreadLocal 没有 tenant_id → 拦截器抛异常 → 拒绝执行 → 强制要求设置租户 ②SQL 解析 → 用 JSqlParser 解析 SQL → 检查 WHERE 子句有没有 tenant_id → 没有 → 自动加上 → 或抛异常 ③ORM 层强制 → Hibernate 的 `@FilterDef` + `@Filter` → 自动加过滤条件 → MyBatis 的 SQL 构建器 → 强制传入 tenant_id ④数据库层 → 视图 → 创建视图只暴露当前租户数据 → 应用只查视图 → 不查原表 → 视图自动过滤 tenant_id / MyBatis 拦截器实现：①实现 `Interceptor` 接口 → `@Intercepts(@Signature(type = Executor.class, method = "query", args = {...}))` ②拦截 query 方法 → 获取 BoundSql → 解析 SQL → 如果没有 tenant_id → 用 JSqlParser 加上 → `WHERE tenant_id = ?` → 设置参数 ③从 `TenantContext.get()` 获取当前租户 ID → 如果为 null → 抛异常 → "未设置租户上下文" ④更新/删除同理 → 拦截 update/delete → 自动加 tenant_id / 测试保障：①代码审查 → 检查所有 SQL 有没有 tenant_id ②单元测试 → 多租户场景 → 租户 A 查不到租户 B 的数据 ③集成测试 → 自动化 → 模拟多租户 → 验证隔离 / 兜底方案：①数据库层 → 行级安全 → PostgreSQL 的 RLS（Row Level Security）→ 数据库强制过滤 → 最安全 → 但 MySQL 不支持 ②MySQL 替代 → 视图 + 权限控制 → 应用连的数据库用户只能查视图 → 视图自动过滤 / 面试重点：MyBatis 拦截器自动注入 tenant_id → ThreadLocal 存租户 → 没有就抛异常 → 视图兜底 → 代码审查+测试保障）

**追问5：** 如果某个大银行租户的数据量很大，单库扛不住，怎么做分库分表？怎么和租户隔离结合？

> 你回答...（提示：大租户分库分表 + 租户隔离结合 / 方案：①大租户独立 DB → 每个大银行一个 DB → 在 DB 内做分库分表 → tenant_id 不需要分片键 → 因为整个 DB 只有一个租户 ②共享 DB 的小租户 → 按 tenant_id 分片 → ShardingSphere → tenant_id 作为分片键 → 不同租户路由到不同库 ③混合模式 → 大租户独立 DB → 小租户共享 DB + tenant_id 分片 / 大租户分库分表：①分片键 → 用 user_id / account_id → 而不是 tenant_id → 因为只有一个租户 → 按 user_id 分片 ②ShardingSphere 配置 → 精确分片算法 → `user_id % 4` → 4个库 ③跨库查询 → 尽量避免 → 用绑定表/广播表 → 跨库 JOIN 用应用层组装 ④扩容 → 4库→8库 → 数据迁移 → 双写 → 切换 / 多租户 + 分库分表：①分片键 = tenant_id + user_id → 联合分片 → 先按 tenant_id 路由到租户的库组 → 再按 user_id 分片 ②或者 → 大租户单独分配库组 → 小租户共享 → 按 tenant_id 路由 ③ShardingSphere → 支持分片键路由 → 配置分片规则 → tenant_id 在哪个范围 → 路由到哪个库组 / 实际架构：①Gateway → 提取 tenant_id ②路由层 → 大租户 → 独立 DB 集群 → 小租户 → 共享 DB 集群（tenant_id 分片）③AbstractRoutingDataSource → 动态切换数据源 → 大租户的数据源 → 小租户的数据源 ④ShardingSphere → 在数据源内 → 再做 user_id 分片 ⑤MyBatis 拦截器 → 共享 DB 的 SQL 自动加 tenant_id → 独立 DB 不需要 / 面试加分：能说出"大租户独立DB+内部按user_id分片 → 小租户共享DB+tenant_id分片 → 混合路由"→ 展示对多租户+分库分表的综合理解）

**追问6：** 最后一个问题：多租户场景下，缓存怎么隔离？如果两个租户的缓存串了怎么办？

> 你回答...（提示：多租户缓存隔离 / 方案：①Key 前缀 → 所有 Redis key 加 tenant_id 前缀 → `t:{tenantId}:user:{userId}` → 最简单 → 最常用 ②Redis 独立 DB → `SELECT tenantId` → 每个 tenant 一个 Redis DB（0-15）→ 但 Redis Cluster 不支持 SELECT ③独立 Redis 实例 → 大租户独立 Redis → 物理隔离 → 成本高 / Key 前缀方案实现：①工具类 → 封装 RedisTemplate → 自动加前缀 → `redisTemplate.opsForValue().get("t:" + TenantContext.get() + ":" + key)` ②或者 → RedisTemplate 配置 KeySerializer → 自动加前缀 → 对业务透明 ③所有 key 都走工具类 → 不允许直接调 RedisTemplate → 代码审查保障 / 防止串缓存：①TenantContext → ThreadLocal → 每个请求设置 tenant_id → 请求结束清理 → 防止线程池复用 → ThreadLocal 串数据 ②工具类强制 → 不传 tenant_id → 不允许操作 Redis → 编译/运行时拦截 ③测试 → 多租户场景 → 租户 A 写 → 租户 B 读 → 读不到 → 验证隔离 ④监控 → Redis 监控 → 如果某个租户的 key 出现在另一个租户的查询中 → 告警 / 本地缓存隔离：①Caffeine / Guava → key 加 tenant_id 前缀 → 和 Redis 同理 ②注意 → 线程池 → ThreadLocal 传递 → 异步线程 → 需要手动传 TenantContext → 或用 TransmittableThreadLocal / 面试重点：Key 加 tenant_id 前缀（最常用）→ 封装工具类对业务透明 → ThreadLocal 请求结束清理防串 → 大租户独立 Redis 物理隔离）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| Spring 事务传播机制（7种/REQUIRED vs REQUIRES_NEW/NESTED/自调用失效） | 能讲清 / 讲不全 / 不会★ | |
| CAS 原理与 ABA 问题（Unsafe/AtomicStampedReference/自旋） | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（单例DCL/volatile原理/5种单例实现） | 能讲清 / 讲不全 / 不会★ | |
| MySQL Explain 执行计划（type/key/rows/Extra/覆盖索引） | 能讲清 / 讲不全 / 不会★ | |
| Java 8 Stream API（中间/终端操作/惰性求值/map vs flatMap/parallelStream/toMap） | 能讲清 / 讲不全 / 不会★ | |
| 消息队列选型对比（Kafka vs RocketMQ vs RabbitMQ） | 能讲清 / 讲不全 / 不会★ | |
| 金融云多租户数据隔离设计（3种模式/MyBatis拦截器/分库分表/缓存隔离） | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **Spring 事务传播**：7种行为 → REQUIRED（默认，同事务一起回滚）→ REQUIRES_NEW（独立事务，日志/通知不受主事务影响）→ NESTED（savepoint部分回滚）。自调用失效 = this不是代理对象 → 解决：拆类/self-injection/AopContext.currentProxy()。private方法不生效（CGLIB不能覆盖）。rollbackFor默认只回滚RuntimeException → 生产加`rollbackFor = Exception.class`
> 2. **CAS 原理**：Compare And Swap → CPU指令（CMPXCHG）保证原子性 → Unsafe类调用。ABA问题 = A→B→A → CAS误判 → AtomicStampedReference加版本号。自旋 = do-while CAS → 低竞争好/高竞争浪费CPU → LongAdder分段CAS。CAS vs synchronized：无锁乐观适合低竞争简单操作 → 有锁悲观适合高竞争复杂临界区。Unsafe = CAS+堆外内存+park/unpark → JDK 9+用VarHandle替代
> 3. **单例DCL**：双重检查 = 第一次检查避免不必要加锁 + 第二次检查防止重复创建。volatile必须加 → `new Singleton()`不是原子操作 → ①分配内存②初始化③赋值 → 指令重排①③② → volatile禁止重排+保证可见性。5种实现：饿汉/懒汉(不安全)/DCL/静态内部类(推荐)/枚举(防反射→Effective Java推荐)
> 4. **MySQL Explain**：4个关键字段 → type（ALL最差→const最优）→ key（实际索引）→ rows（扫描行数）→ Extra（Using index好/Using where差/Using temporary+filesort必须优化）。覆盖索引 = 查询列都在索引中 → 不回表 → Using index。慢SQL优化流程：慢日志→EXPLAIN→加联合索引→覆盖索引/延迟关联
> 5. **Stream API**：中间操作惰性求值（filter/map/flatMap）→ 终端操作触发执行（collect/forEach/count）。map一对一 → flatMap一对多+拍平。parallelStream用共享ForkJoinPool → 最大坑是阻塞其他并行流。toMap重复key抛异常 → 指定merge function。短路操作：anyMatch/findFirst/findAny/limit
> 6. **消息队列选型**：Kafka高吞吐（大数据/日志）→ RocketMQ金融级（事务消息/延迟消息/消息过滤/死信队列）→ RabbitMQ路由灵活（4种Exchange）但吞吐低。RocketMQ事务 = 半消息+本地事务+回查 → DB+MQ跨系统最终一致。Kafka事务 = 多分区原子写入 → Kafka内部一致
> 7. **多租户数据隔离**：独立DB（大银行物理隔离）→ 独立Schema（中小银行逻辑隔离）→ 共享表+tenant_id（小客户成本低）。实现：AbstractRoutingDataSource动态数据源 → MyBatis拦截器自动注入tenant_id → 没有就抛异常。缓存隔离：key加`t:{tenantId}:`前缀 → 工具类封装对业务透明。大租户分库分表：按user_id分片 → 小租户按tenant_id分片 → 混合路由
