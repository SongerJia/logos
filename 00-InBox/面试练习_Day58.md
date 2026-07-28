# 面试模拟 - Day 58

> 日期：2026-07-28（周二） | 模拟岗位：度小满科技（杭州研发中心）- 消费金融技术部 - Java开发工程师
> 建议时长：85分钟（一面55分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day58，"查漏补缺"阶段第七周。模拟度小满科技杭州研发中心——原百度金融，2018年拆分独立，旗下"有钱花"消费信贷、"百度理财"财富管理、度小满支付。度小满面试特点：AI+金融场景多、大数据风控技术栈深、追问偏工程落地而非纯理论、喜欢考"你在项目中遇到过什么坑"。今天引入 CompletableFuture 异步编程、MySQL 间隙锁与死锁分析、MyBatis 缓存机制、ThreadLocal 原理与内存泄漏、Canal 原理与数据同步 5 个全新话题——都是高频考点但之前没有作为独立话题系统考过的内容。

---

# 一面（55分钟）

	## 话题一：CompletableFuture 异步编程（12分钟）
	
	**面试官：你简历上写了用过多线程。Java 8 的 CompletableFuture 你了解吗？它解决了什么问题？和 Future 有什么区别？**
	
> 	你回答...
	
	**追问1：** 先说说 Future 有什么局限。为什么有了 Future 还要 CompletableFuture？
	
> 	你回答...（提示：Future 的三个局限 / Future 接口（JDK 5）：①`Future` 表示一个异步计算的结果 → `executor.submit(callable)` 返回 `Future<T>` → 主线程可以继续做别的 → 之后 `future.get()` 阻塞拿结果 ②支持的方法 → `get()`（阻塞获取结果）/ `get(timeout)`（超时获取）/ `isDone()`（是否完成）/ `cancel()`（取消）/ `isCancelled()`（是否取消）③看起来够用 → 但有三个致命局限 / 局限一：`get()` 阻塞 ①`future.get()` 是阻塞的 → 主线程调用后必须等结果 → 等的时候什么都干不了 ②如果有 3 个异步任务 → 必须串行 `get()` → `f1.get()` 阻塞等完 → `f2.get()` 阻塞等完 → `f3.get()` 阻塞等完 → 总耗时 = f1 + f2 + f3 → 没有并行优势 ③理想 → f1 完成后自动回调 → 不用阻塞等 / 局限二：不能链式调用 ①场景 → 先查用户 → 再查订单 → 再查物流 → 三个串行依赖 ②用 Future → `Future<User> fu = executor.submit(查用户)` → `user = fu.get()` 阻塞 → `Future<Order> fo = executor.submit(查订单)` → `order = fo.get()` 阻塞 → ... ③每次 `get()` 都阻塞 → 而且要手动编排 ④理想 → `fu.thenApply(user -> 查订单)` → 链式 → 自动串联 → 不阻塞 / 局限三：不能组合多个异步任务 ①场景 → 同时查用户服务和订单服务 → 两个都完成后再合并 ②用 Future → 只能 `f1.get()` + `f2.get()` → 还是要分别阻塞 ③理想 → `CompletableFuture.allOf(f1, f2).thenRun(合并)` → 两个都完成后自动执行合并 ④没有回调机制 → 不能"完成了通知我" → 只能主动轮询 `isDone()` 或阻塞 `get()` / 面试重点：Future三个局限 = get()阻塞(不能回调)/不能链式调用(手动编排)/不能组合多个异步任务(allOf/anyOf) → CompletableFuture解决这三个问题 → 回调驱动(不阻塞)/链式编排(thenApply)/组合(allOf/anyOf)）
	
	**追问2：** CompletableFuture 的常用 API 你说说。thenApply、thenCompose、thenCombine 有什么区别？
	
> 	你回答...（提示：CompletableFuture 核心 API / 创建：①`CompletableFuture.supplyAsync(() -> { 查DB; return result; })` → 异步执行 → 默认用 ForkJoinPool.commonPool() ②`CompletableFuture.supplyAsync(() -> ..., executor)` → 指定线程池 → 生产建议指定 → 共享 commonPool 的坑（Day54提过）③`CompletableFuture.completedFuture(value)` → 直接返回已完成的 → 测试用 / 回调方法（then 系列）：①`thenApply(Function<T, R>)` → 拿到上一步结果 → 同步转换 → 返回 `R` → 如 `.thenApply(user -> user.getName())` → 返回 String ②`thenCompose(Function<T, CompletableFuture<R>>)` → 拿到上一步结果 → 异步转换 → 返回 `CompletableFuture<R>` → 如 `.thenCompose(user -> CompletableFuture.supplyAsync(() -> 查订单(user.getId())))` → 链式异步 → 类比 `Stream.map` vs `Stream.flatMap` ③`thenCombine(CompletableFuture<U>, BiFunction<T, U, R>)` → 等两个 CF 都完成 → 合并结果 → 如 `userCF.thenCombine(orderCF, (user, order) -> merge(user, order))` / thenApply vs thenCompose vs thenCombine：①`thenApply` → 同步转换 → `T → R` → 内部不返回 CF → 如 `user -> user.getName()` ②`thenCompose` → 异步转换 → `T → CompletableFuture<R>` → 内部返回 CF → 扁平化 → 如 `user -> CompletableFuture.supplyAsync(查订单)` ③`thenCombine` → 等两个 CF → 合并 → `(T, U) → R` → 如 `(user, order) -> merge` ④类比 → `thenApply` = Stream.map（一对一同步）→ `thenCompose` = Stream.flatMap（一对一异步扁平化）→ `thenCombine` = 合并两个独立流 / 回调变体（Async 后缀）：①`thenApply(fn)` → 回调在上一步完成的线程执行 → 可能是主线程也可能是异步线程 ②`thenApplyAsync(fn)` → 回调提交到 ForkJoinPool 异步执行 ③`thenApplyAsync(fn, executor)` → 回调提交到指定线程池 ④生产建议 → `Async` + 指定线程池 → 不用共享 commonPool / 组合方法：①`allOf(cf1, cf2, cf3...)` → 所有都完成才完成 → 返回 `CompletableFuture<Void>` → 需要 `.join()` 拿结果 ②`anyOf(cf1, cf2, cf3...)` → 任意一个完成就完成 → 返回最快的结果 ③`allOf` 场景 → 并行查多个服务 → 都完成后合并 → `CompletableFuture.allOf(userCF, orderCF, logiCF).thenRun(() -> merge())` ④`anyOf` 场景 → 多渠道查询 → 最快的返回 → 如同时查两个缓存源 → 最快的拿数据 / 异常处理：①`exceptionally(ex -> defaultValue)` → 发生异常时 → 返回默认值 → 类似 try-catch ②`handle((result, ex) -> ex != null ? defaultValue : result)` → 同时处理正常和异常 → 类似 try-catch-finally ③`whenComplete((result, ex) -> 记日志)` → 完成时执行（不管成功失败）→ 不改变结果 → 类似 finally / 面试重点：thenApply=同步转换(T→R)/thenCompose=异步转换(T→CF<R>扁平化)/thenCombine=合并两个CF → Async后缀=提交到线程池(生产建议指定executor不用commonPool) → allOf=全完成/anyOf=任一完成 → exceptionally/handle/whenComplete=异常处理)
	
	**追问3：** CompletableFuture 默认用 ForkJoinPool.commonPool()，有什么坑？生产环境怎么用？
	
> 	你回答...（提示：commonPool 的坑与生产实践 / commonPool 的问题：①所有 `supplyAsync()` 不指定线程池 → 默认用 `ForkJoinPool.commonPool()` → 全局唯一 → 所有 CompletableFuture 共享 ②问题一：CPU 密集任务拖慢 IO 任务 → 如果某个 CF 任务是 CPU 密集（加密/计算）→ 占着 commonPool 线程 → 其他 IO 密集的 CF 排队等 → 互相影响 ③问题二：阻塞操作导致线程耗尽 → 如果 CF 里 `Thread.sleep(5000)` 或 DB 慢查询 → commonPool 线程被阻塞 → 其他 CF 没线程用 → 全局卡顿 ④问题三：parallelStream 也用 commonPool → `list.parallelStream().map(...)` 和 `CompletableFuture.supplyAsync()` 共享同一个池 → 互相干扰 ⑤commonPool 大小 = `Runtime.getRuntime().availableProcessors() - 1` → 8核只有7个线程 → 不够用 / 生产环境最佳实践：①为不同场景创建独立线程池 → IO 密集用大池（核心20/最大50）→ CPU 密集用小池（核心=CPU核数）②`CompletableFuture.supplyAsync(task, ioExecutor)` → 指定线程池 ③线程池隔离 → 查询服务用一个池 / 写入服务用另一个池 → 互不影响 ④监控 → 线程池的 activeCount / queueSize / 拒绝次数 → Prometheus + Micrometer / 完整示例：
	```java
	// 线程池定义
	@Bean("ioExecutor")
	public ExecutorService ioExecutor() {
	    return new ThreadPoolExecutor(
	        20, 50, 60, TimeUnit.SECONDS,
	        new LinkedBlockingQueue<>(1000),
	        new ThreadFactoryBuilder().setNameFormat("io-async-%d").build(),
	        new ThreadPoolExecutor.CallerRunsPolicy()  // 队列满 → 调用线程执行 → 背压
	    );
	}
	
	// 使用
	public UserDTO getUserInfo(Long userId) {
	    CompletableFuture<User> userCF =
	        CompletableFuture.supplyAsync(() -> userService.getById(userId), ioExecutor);
	
	    CompletableFuture<Integer> creditCF =
	        CompletableFuture.supplyAsync(() -> creditService.getScore(userId), ioExecutor);
	
	    CompletableFuture<List<Order>> orderCF =
	        CompletableFuture.supplyAsync(() -> orderService.getByUserId(userId), ioExecutor);
	
	    // 三个并行查询 → 都完成后合并
	    return CompletableFuture.allOf(userCF, creditCF, orderCF)
	        .thenApply(v -> {
	            UserDTO dto = new UserDTO();
	            dto.setUser(userCF.join());      // 此时已完成，join不阻塞
	            dto.setCreditScore(creditCF.join());
	            dto.setOrders(orderCF.join());
	            return dto;
	        })
	        .orTimeout(500, TimeUnit.MILLISECONDS)  // 超时保护
	        .exceptionally(ex -> {
	            log.error("获取用户信息失败", ex);
	            return UserDTO.degraded();  // 降级返回
	        })
	        .join();  // 最终阻塞获取（对外同步接口）
	}
	```
	/ 和虚拟线程对比（Day57提过）：①CompletableFuture → 异步回调 → 代码链式 → 调试困难（栈不完整）→ 但 JDK 8+ 都能用 ②虚拟线程 → 同步代码 → 透明异步 → 调试容易 → 但要 JDK 21+ ③未来 → 虚拟线程可能替代 CompletableFuture → 但过渡期 CompletableFuture 依然是主流 / 面试重点：commonPool坑=全局共享/CPU密集拖慢IO/阻塞操作耗尽线程/parallelStream也用commonPool → 生产=为不同场景创建独立线程池(ioExecutor/cpuExecutor)+指定executor+监控+超时保护+降级 → orTimeout防超时+exceptionally降级 → 虚拟线程可能替代但过渡期CompletableFuture仍主流）

---

## 话题二：MySQL 间隙锁与死锁分析（11分钟）

**面试官：你之前提到过 InnoDB 的行锁。间隙锁是什么？什么场景下会产生死锁？怎么排查和预防？**

> 你回答...

**追问1：** 先说说间隙锁是什么。它解决了什么问题？什么情况下会加间隙锁？

> 你回答...（提示：间隙锁原理 / 回顾（Day53考过锁机制全景）：①记录锁（Record Lock）→ 锁住索引上的一条记录 ②间隙锁（Gap Lock）→ 锁住两个索引记录之间的"间隙" → 防止 INSERT 进入这个间隙 ③临键锁（Next-Key Lock）→ 记录锁 + 间隙锁 → 锁住一条记录 + 它前面的间隙 ④InnoDB 默认 RR 隔离级别 → 用临键锁解决幻读 / 间隙锁解决幻读：①幻读 = 同一事务内两次查询 → 第二次多了一行（被其他事务 INSERT）②RR 隔离级别 → 快照读走 MVCC（Day46考过）→ 不会幻读 ③但当前读（`SELECT ... FOR UPDATE` / `UPDATE` / `DELETE`）→ 需要加锁 → 如果只锁已有记录 → 别人还能 INSERT 新记录 → 幻读 ④间隙锁 → 锁住记录之间的间隙 → 别人 INSERT 不进来 → 解决当前读的幻读 / 什么情况下加间隙锁：①唯一索引等值查询 → 命中记录 → 退化为记录锁（只锁一行）→ 不加间隙锁 ②唯一索引等值查询 → 未命中记录 → 加间隙锁（锁住查询位置的间隙）③非唯一索引等值查询 → 加临键锁（记录 + 间隙）④范围查询 → 加临键锁（锁住范围内的所有记录 + 间隙）⑤RR 隔离级别才有间隙锁 → RC（Read Committed）没有间隙锁 → 因为 RC 允许幻读 / 示例：
```sql
-- 表数据：id=1, 5, 10, 15（id 是主键）
-- 事务A（RR）：
BEGIN;
SELECT * FROM t WHERE id BETWEEN 5 AND 10 FOR UPDATE;
-- 锁：(−∞,1) (1,5] (5,10] (10,15) → 临键锁 + 间隙锁
-- 锁住了 5~10 之间的所有间隙 → 包括 6,7,8,9 这些不存在的位置

-- 事务B（RR）：
BEGIN;
INSERT INTO t VALUES (7);  -- 阻塞！7 在 (5,10) 间隙锁范围内
-- 等待事务A释放间隙锁
```
①事务A `FOR UPDATE` → 当前读 → 范围查询 → 加临键锁 (1,5] + (5,10] + (10,15) ②间隙 (5,10) 被锁 → 事务B INSERT 7 → 7 在间隙内 → 阻塞 / 面试重点：间隙锁=锁两个索引记录之间的间隙→防INSERT→解决RR下当前读的幻读 → 唯一索引等值命中=退化为记录锁(不加间隙)/未命中=加间隙锁 → 非唯一索引=加临键锁 → 范围查询=锁范围内所有记录+间隙 → RC没有间隙锁)

**追问2：** 间隙锁导致的死锁场景。两个事务怎么互相等死锁？

> 你回答...（提示：间隙锁死锁场景 / 死锁场景一：相同间隙的 INSERT：①两个事务 → 都想往同一个间隙 INSERT → 间隙锁是兼容的（多个事务可以同时持有同一间隙的间隙锁）→ 但 INSERT 需要插入意向锁 → 和间隙锁冲突 → 互相等待 → 死锁
```sql
-- 表数据：id=1, 5, 10（id 主键唯一索引）
-- 事务A                     -- 事务B
BEGIN;                      BEGIN;
-- 先用 SELECT FOR UPDATE 持有间隙锁
SELECT * FROM t              SELECT * FROM t
  WHERE id = 7 FOR UPDATE;    WHERE id = 7 FOR UPDATE;
-- 都没命中 → 都加了 (5,10) 间隙锁
-- 间隙锁兼容 → 两个都成功加了锁

INSERT INTO t VALUES (7);   INSERT INTO t VALUES (7);
-- A 要插入 7 → 需要 (5,10) 间隙的插入意向锁
-- 但 B 持有 (5,10) 间隙锁 → A 等 B 释放
-- B 要插入 7 → 也需要插入意向锁
-- 但 A 持有 (5,10) 间隙锁 → B 等 A 释放
-- A 等 B，B 等 A → 死锁！
```
②这个场景 → `SELECT ... FOR UPDATE` 查不存在的记录 → 加间隙锁 → 然后各自 INSERT → 死锁 / 死锁场景二：不同间隙的交叉：①事务A → `SELECT * FROM t WHERE id = 7 FOR UPDATE` → 锁 (5,10) ②事务B → `SELECT * FROM t WHERE id = 12 FOR UPDATE` → 锁 (10,15) ③事务A → `INSERT INTO t VALUES (12)` → 12 在 (10,15) → 等B ④事务B → `INSERT INTO t VALUES (7)` → 7 在 (5,10) → 等A ⑤死锁 / 死锁场景三：唯一索引冲突重试：①事务A → INSERT id=5 → 持有记录锁 ②事务B → INSERT id=5 → 唯一冲突 → 等A（持有S锁检查唯一性）③事务A → 又 INSERT id=5 → 等B（B持有S锁在检查）④死锁（MySQL 8.0.20 优化减少了这类死锁）/ 死锁检测机制：①InnoDB 有主动死锁检测 → 发现死锁 → 选一个事务回滚（选 undo 量小的回滚）→ 报错 `ERROR 1213 (40001): Deadlock found when trying to get lock; try restarting transaction` ②死锁检测有性能开销 → 高并发下检测本身成为瓶颈 → `innodb_deadlock_detect` 可以关闭 → 但关闭后要靠 `innodb_lock_wait_timeout` 超时 / 排查方法：①`SHOW ENGINE INNODB STATUS` → 看 `LATEST DETECTED DEADLOCK` → 打印两个事务的 SQL + 持有的锁 + 等待的锁 ②`information_schema.innodb_trx` → 当前所有事务 ③`information_schema.innodb_locks` → 当前所有锁（MySQL 8.0 改为 `performance_schema.data_locks`）④`performance_schema.data_lock_waits` → 谁在等谁的锁 ⑤开启死锁日志 → `SET GLOBAL innodb_print_all_deadlocks = ON` → 所有死锁都打到 error log / 面试重点：死锁场景=相同间隙INSERT(间隙锁兼容但INSERT需要插入意向锁→互相等待)/不同间隙交叉(各持一段间隙→各INSERT对方间隙)/唯一索引冲突重试 → InnoDB有主动死锁检测→选undo小的事务回滚→报错1213 → 排查=SHOW ENGINE INNODB STATUS看LATEST DETECTED DEADLOCK + data_locks/data_lock_waits + 开启innodb_print_all_deadlocks）

**追问3：** 生产环境怎么预防死锁？你有没有遇到过死锁？

> 你回答...（提示：死锁预防实践 / 预防策略：①统一加锁顺序 → 多个表/多行加锁时 → 统一按某个顺序（如主键升序）→ 避免交叉等待 → 这是银行核心账务的标准做法 ②缩短事务 → 事务越长 → 持锁时间越久 → 死锁概率越大 → 把非必要操作移出事务 ③用 RC 隔离级别 → 如果业务允许幻读 → RC 没有间隙锁 → 减少死锁场景 → 很多互联网公司用 RC 代替 RR ④避免 `SELECT FOR UPDATE` 查不存在的记录 → 先查存在性 → 存在再 `FOR UPDATE` → 不存在直接返回 → 不加间隙锁 ⑤批量操作分批 → 大事务拆小 → 减少锁持有时间 ⑥INSERT 用 `INSERT ... ON DUPLICATE KEY UPDATE` → 替代 `SELECT FOR UPDATE` + INSERT → 减少间隙锁 / RC vs RR 的选型（实际争议）：①RR（MySQL 默认）→ 有间隙锁 → 防幻读 → 但死锁概率高 ②RC → 没有间隙锁 → 死锁少 → 但有幻读（当前读）→ 需要业务处理 ③阿里/美团 → 很多核心系统用 RC → 死锁少 + 性能好 → 幻读由业务层处理（乐观锁/唯一约束）④金融系统 → 倾向 RR → 严格隔离 → 但要注意死锁 / 实际案例：①银行转账 → 两个用户互相转账 → 如果按用户ID加锁 → 顺序不同 → 死锁 → 解决：统一按两个账户号排序后加锁 ②营销活动 → 先 `SELECT FOR UPDATE` 查库存 → 不够返回 → 够了 INSERT 订单 → 如果多个请求同时查同一商品 → 间隙锁 → INSERT 互相等 → 死锁 → 解决：用 Redis 预扣减 → DB 层用乐观锁版本号 ③消费金融授信 → 先查征信 → 再写授信 → 多个请求并发 → 行锁 → 死锁 → 解决：拆事务 → 查询在事务外 → 写入在事务内 → 缩短锁持有 / 死锁发生后的处理：①InnoDB 自动检测 → 回滚一个事务 → 应用层捕获 `DeadlockLoserDataAccessException` → 重试 → 注意重试要幂等 ②监控告警 → 死锁次数 > 阈值 → 告警 → 排查 ③日志 → 死锁 SQL → 定位代码 → 修复 / 面试重点：预防=统一加锁顺序(主键升序)+缩短事务+RC代替RR(互联网公司常用RC)+避免SELECT FOR UPDATE查不存在+批量分批 → 死锁后=InnoDB自动回滚+应用层重试(幂等)+监控告警 → 实际案例=转账按账户排序加锁/营销活动用Redis预扣减+DB乐观锁/授信拆事务缩短锁）

---

## 话题三：MyBatis 缓存机制与 Spring 集成（10分钟）

**面试官：你用 MyBatis 吧？MyBatis 有一级缓存和二级缓存。它们是什么？为什么在 Spring 环境下一级缓存基本失效了？**

> 你回答...

**追问1：** 先说说一级缓存的原理。它的作用范围是什么？

> 你回答...（提示：一级缓存原理 / 一级缓存（Local Cache）：①一级缓存 = SqlSession 级别的缓存 → 同一个 SqlSession 内 → 相同查询只查一次 DB → 第二次从缓存取 ②底层 → `PerpetualCache` → 内部就是 `HashMap` → key = `CacheKey`（statementId + parameter + boundSql + offset + limit）→ value = 查询结果 ③流程 → 第一次查询 → 查 DB → 结果放入一级缓存 → 第二次相同查询 → 先查缓存 → 命中 → 返回缓存 → 不查 DB ④任何 `INSERT/UPDATE/DELETE` → 自动清空一级缓存 → 防脏读 / 作用范围：①作用域 = SqlSession → 不同 SqlSession 之间不共享缓存 ②在原生 MyBatis（非 Spring）→ 一个 SqlSession 对应一次会话 → 手动 `openSession()` / `close()` → 同一会话内一级缓存生效 ③示例：
```java
// 原生 MyBatis（非 Spring）
SqlSession session = sqlSessionFactory.openSession();
User user1 = session.selectOne("selectUserById", 1);  // 查DB → 放入一级缓存
User user2 = session.selectOne("selectUserById", 1);  // 命中一级缓存 → 不查DB
System.out.println(user1 == user2);  // true！同一个对象实例
session.close();
```
④`user1 == user2` → true → 一级缓存返回的是同一个对象 → 如果修改 user1 → user2 也变 → 脏数据风险 / 一级缓存清空时机：①执行 `INSERT/UPDATE/DELETE` → 清空整个一级缓存（不是只清被修改的表）②调用 `sqlSession.clearCache()` → 手动清空 ③`sqlSession.close()` → 随 SqlSession 销毁 ④事务 commit/rollback → 清空（防脏读） / 面试重点：一级缓存=SqlSession级别+HashMap存储+相同查询只查一次DB+返回同一对象实例 → 清空=任何写操作/手动clearCache/close/事务提交回滚 → 原生MyBatis中一个SqlSession=一次会话→缓存生效）

**追问2：** 在 Spring + MyBatis 环境下，一级缓存为什么基本失效了？

> 你回答...（提示：Spring 环境下一级缓存失效 / Spring 整合 MyBatis 的机制：①Spring + MyBatis → 每次 Mapper 方法调用 → `SqlSessionTemplate` → 创建一个新的 `SqlSession` → 执行查询 → 关闭 SqlSession ②即 → 每次 Mapper 调用 = 一个新的 SqlSession → 一级缓存作用域 = SqlSession → SqlSession 每次新建 → 缓存每次清空 → 基本不生效 ③流程 → `userMapper.getById(1)` → `SqlSessionTemplate` → `getSqlSession()` → 新建 SqlSession → 查 DB → 关闭 SqlSession → 缓存没了 → 下次再查 `userMapper.getById(1)` → 又新建 SqlSession → 又查 DB / 为什么 Spring 要这么做：①Spring 的声明式事务 → `@Transactional` → 事务范围内 → SqlSession 复用 → 一级缓存生效 ②但非事务方法 → 每次 Mapper 调用 → 新建 SqlSession → 缓存失效 ③所以 → 一级缓存只在 `@Transactional` 方法内多次查询同一数据时生效 → 大部分场景（Service 调 Mapper 一次查一行）→ 不生效 / 一级缓存的问题（即使生效也有坑）：①脏数据 → 同一 SqlSession 内 → 查了 user → 别的事务改了 user → 你再查 → 从缓存拿旧数据 → 脏读 ②返回同一对象 → 修改缓存对象 → 影响其他地方拿到的"同一对象" → 难排查的 bug ③分布式环境 → 每个节点自己的 SqlSession → 缓存不共享 → 意义不大 / Spring 环境下一级缓存配置：①`localCacheScope` → `SESSION`（默认，SqlSession 级别）/ `STATEMENT`（语句级别 → 每次查询后清空 → 相当于关闭一级缓存）②生产建议 → `localCacheScope=STATEMENT` → 关闭一级缓存 → 避免脏数据 → 用 Spring 的 `@Transactional` + 二级缓存替代 / 面试重点：Spring下=每次Mapper调用新建SqlSession→一级缓存每次清空→基本失效 → 只有@Transactional方法内多次查询同一数据才生效 → localCacheScope=STATEMENT关闭一级缓存防脏数据 → Spring用@Transactional让SqlSession在事务内复用→但非事务方法失效）

**追问3：** 二级缓存呢？MyBatis 二级缓存有什么坑？为什么很多人不用？

> 你回答...（提示：二级缓存原理与坑 / 二级缓存（Namespace 级别）：①二级缓存 = Mapper namespace 级别 → 跨 SqlSession 共享 → 不同 SqlSession 可以共享二级缓存 ②开启 → `mybatis.configuration.cache-enabled=true` + Mapper 加 `@CacheNamespace` 或 XML 加 `<cache/>` ③底层 → 默认 `PerpetualCache`（HashMap）→ 可换 Redis / Ehcache / Caffeine ④流程 → SqlSession 查询 → 先查二级缓存 → 再查一级缓存 → 再查 DB → 结果放入两级缓存 ⑤写入 → `INSERT/UPDATE/DELETE` → 清空整个 namespace 的二级缓存 / 二级缓存的坑：①坑一：跨 namespace 更新不感知 → MapperA 的 `update` → 只清 MapperA 的二级缓存 → 如果 MapperB 查了 MapperA 的表（多表 JOIN）→ MapperB 的缓存还是旧数据 → 脏数据 ②坑二：分布式环境不一致 → 每个节点自己的二级缓存 → 节点A更新 → 清了节点A的缓存 → 但节点B的缓存还是旧的 → 如果不用 Redis 分布式缓存 → 多节点数据不一致 ③坑三：缓存粒度粗 → 任何写操作清空整个 namespace → 如果 namespace 下有100个查询 → 一次 UPDATE 全清 → 缓存命中率低 ④坑四：序列化开销 → 默认二级缓存要求对象 `Serializable` → 序列化/反序列化 → 如果对象大 → 开销不小 ⑤坑五：事务未提交的数据不会进缓存 → 但如果在事务内查 → 再查 → 一级缓存返回 → 提交后一级缓存清空 → 下次查走二级缓存 → 如果事务回滚 → 二级缓存可能不一致 / 为什么很多人不用二级缓存：①MyBatis 二级缓存 → 设计上有缺陷 → 跨 namespace 不感知 → 多表 JOIN 场景脏数据 ②Spring 环境 → 一级缓存基本失效 → 二级缓存也有坑 → 不如直接用 Spring Cache + Redis / Caffeine → 更可控 ③企业实践 → 普遍关闭 MyBatis 二级缓存 → 用业务层缓存（Spring Cache @Cacheable + Redis/Caffeine）→ 可以精确控制缓存 key + 失效策略 + 分布式一致 / 推荐做法：①关闭 MyBatis 一级缓存（`localCacheScope=STATEMENT`）②关闭 MyBatis 二级缓存（`cache-enabled=false`）③用 Spring Cache + Redis / Caffeine → `@Cacheable` / `@CacheEvict` → 精确控制 key + 过期 + 更新策略 ④多级缓存 → Caffeine（本地一级）+ Redis（分布式二级）→ Caffeine 快但单机 → Redis 慢但共享 → 配合使用 / 面试重点：二级缓存=namespace级别跨SqlSession共享 → 坑=跨namespace更新不感知(多表JOIN脏数据)/分布式不一致/粒度粗(一次UPDATE全清)/序列化开销/事务回滚不一致 → 企业实践=关闭MyBatis两级缓存+用Spring Cache(@Cacheable/@CacheEvict)+Redis/Caffeine精确控制 → 多级缓存=Caffeine本地+Redis分布式）

---

## 话题四：ThreadLocal 原理与内存泄漏（11分钟）

**面试官：ThreadLocal 你用过吧？它的原理是什么？为什么会内存泄漏？怎么解决？**

> 你回答...

**追问1：** 先说说 ThreadLocal 的底层结构。ThreadLocalMap 是什么？为什么 key 用弱引用？

> 你回答...（提示：ThreadLocal 底层结构 / 常见误解：①误解 → `ThreadLocal` 内部维护一个 Map → `Thread` 为 key → value 为存储的值 ②实际 → 反过来 → 每个 `Thread` 对象内部维护一个 `ThreadLocalMap` → `ThreadLocal` 实例为 key → value 为存储的值 ③即 → `Thread.threadLocals` → 是一个 `ThreadLocal.ThreadLocalMap` → map 的 key 是 `ThreadLocal` 对象 → value 是你 set 的值 / 数据结构：
```java
class Thread {
    ThreadLocal.ThreadLocalMap threadLocals;  // 每个线程一个
}

class ThreadLocalMap {
    // 继承 WeakReference → key 是弱引用
    static class Entry extends WeakReference<ThreadLocal<?>> {
        Object value;  // value 是强引用！
        Entry(ThreadLocal<?> k, Object v) {
            super(k);  // key 弱引用
            value = v;  // value 强引用
        }
    }
    private Entry[] table;  // 数组（不是 HashMap）
}
```
①每个 Thread → 有一个 `threadLocals` → 是 `ThreadLocalMap` ②`ThreadLocalMap` → 内部是 `Entry[]` 数组 → 不是 HashMap → 没有链表 → 用开放寻址（线性探测）解决冲突 ③`Entry` → 继承 `WeakReference<ThreadLocal<?>>` → key（ThreadLocal 对象）是弱引用 → value 是强引用 / 为什么 key 用弱引用：①场景 → `ThreadLocal tl = new ThreadLocal(); tl.set(bigObject);` → 如果 ThreadLocal 对象被回收 → 但 Thread 还活着（线程池）→ `threadLocals` 里的 Entry → key 是 ThreadLocal → 如果 key 是强引用 → ThreadLocal 对象永远不会被回收 → 内存泄漏 ②key 弱引用 → ThreadLocal 对象只有弱引用指向 → GC 时 → 如果没有其他强引用指向 ThreadLocal → ThreadLocal 被回收 → Entry 的 key 变成 null → 但 value 还在 → value 是强引用 → 大对象不被回收 → 泄漏 ③所以 → 弱引用 key → 解决的是 ThreadLocal 对象本身的泄漏 → 但没有解决 value 的泄漏 / ThreadLocalMap 不是 HashMap：①HashMap → 数组 + 链表/红黑树 → hash 冲突用链表 ②ThreadLocalMap → 只有数组 → hash 冲突用线性探测（往下找下一个空位）③原因 → ThreadLocal 数量通常不多 → 线性探测简单高效 → 不需要链表 ④初始容量 16 → 扩容阈值 2/3 → 扩容翻倍 / 面试重点：ThreadLocal底层=Thread.threadLocals(ThreadLocalMap) → key=ThreadLocal弱引用(WeakReference) → value=强引用 → ThreadLocalMap是数组+线性探测(不是HashMap) → key弱引用=ThreadLocal对象没有外部强引用时GC回收→但value强引用仍在→泄漏根源）

**追问2：** 那内存泄漏具体怎么发生的？线程池场景下为什么更严重？

> 你回答...（提示：内存泄漏过程 / 泄漏过程（线程池场景）：①线程池 → 核心线程不会销毁 → Thread 对象一直活着 → `threadLocals` 一直存在 ②使用 ThreadLocal：
```java
// 业务代码
ThreadLocal<BigObject> tl = new ThreadLocal<>();
tl.set(new BigObject());  // 10MB
// ... 使用 ...
// 忘了 tl.remove()！
```
③ThreadLocal 对象 → 在方法栈中 → 方法执行完 → 栈帧弹出 → ThreadLocal 的强引用消失 → 只剩 ThreadLocalMap 的弱引用 key → 下次 GC → ThreadLocal 对象被回收 → Entry.key = null ④但 value（BigObject）→ 是强引用 → 在 Entry 中 → Entry 在 ThreadLocalMap 中 → ThreadLocalMap 在 Thread 中 → Thread 活着（线程池）→ value 不会被回收 → 泄漏 ⑤下次线程被复用 → 新的 ThreadLocal → 又 set 新 value → 旧的 value 还在 → 泄漏累积 / 为什么线程池更严重：①非线程池 → 方法执行完 → 线程销毁 → Thread 对象被回收 → `threadLocals` 一起回收 → value 也回收 → 不泄漏 ②线程池 → 核心线程不销毁 → Thread 一直活着 → `threadLocals` 一直存在 → value 一直不回收 → 泄漏 ③线程池复用 → 线程1 先处理用户A的请求 → set 了用户A的数据 → 忘了 remove → 线程1 回到池中 → 下次处理用户B的请求 → 线程1 的 `threadLocals` 还有用户A的数据 → 用户B 可能拿到用户A的数据 → 数据串号 → 严重 bug / ThreadLocal 的清理机制（不完全）：①`set()` → 会清理 key=null 的 Entry（启发式清理）→ 但只清当前位置附近的 → 不一定全清 ②`get()` → 也会触发清理 → 但同样不彻底 ③这些清理是"尽力而为" → 如果不再 set/get → 不会触发清理 → value 一直泄漏 / 实际危害：①内存 → 每个 ThreadLocal 泄漏一个大对象 → 线程池 200 线程 → 200 × 10MB = 2GB → OOM ②数据串号 → 线程复用 → 用户A的数据被用户B看到 → 安全事故 ③排查困难 → ThreadLocal 泄漏 → 不容易发现 → Heap Dump 看 ThreadLocalMap 才能定位 / 面试重点：泄漏=线程池核心线程不死→Thread.threadLocals存在→ThreadLocal被GC(key弱引用)但value强引用不回收→泄漏累积 → 危害=内存OOM+数据串号(用户A数据被用户B看到) → ThreadLocal自带清理不彻底(set/get启发式清理) → 线程池下必remove）

**追问3：** 怎么解决？InheritableThreadLocal 有什么用？线程池场景下要用什么？

> 你回答...（提示：解决方案 / 基本解决：①`tl.remove()` → 用完必 remove → finally 块 → 这是最佳实践
```java
ThreadLocal<UserContext> tl = new ThreadLocal<>();
try {
    tl.set(context);
    // 业务逻辑
} finally {
    tl.remove();  // 必须！
}
```
②Spring 的 `@Transactional` → 事务管理器内部用 ThreadLocal 存事务 → 方法结束自动清理 → 框架帮你 remove ③但自己 new 的 ThreadLocal → 必须手动 remove / InheritableThreadLocal：①普通 ThreadLocal → 父线程 set 的值 → 子线程拿不到 → 因为子线程是新 Thread → 新的 `threadLocals` ②`InheritableThreadLocal` → 子线程创建时 → 会继承父线程的值 → `Thread.init()` → 如果父线程有 `inheritableThreadLocals` → 复制到子线程 ③场景 → 主线程 set 了用户上下文 → 创建子线程 → 子线程能拿到用户上下文 ④局限 → 只在**创建子线程时**复制一次 → 线程池场景 → 线程复用 → 不会重新复制 → 线程1 处理用户A → set 上下文 → 处理完 → 线程1 回池 → 下次处理用户B → 但线程1 的 InheritableThreadLocal 还是用户A的（创建时复制的）→ 数据串号 / TransmittableThreadLocal（阿里 TTL）：①解决线程池场景下的上下文传递 → 线程池复用线程 → 每次任务执行前 → 自动从提交任务的线程复制 ThreadLocal → 任务执行后 → 清理 → 恢复 ②原理 → 用 `TtlRunnable` 包装 Runnable → `submit(() -> { ... })` → `TtlRunnable.get(() -> { ... })` → 在 run 前复制 / run 后清理 ③场景 → 微服务链路追踪 traceId 传递 → 父线程的 traceId → 提交到线程池 → 子线程拿到 traceId → 链路不中断 ④使用 → `TransmittableThreadLocal<String> traceIdTl = new TransmittableThreadLocal<>();` → 配合 `TtlExecutors.getTtlExecutorService(executor)` 包装线程池 / 和 ScopedValue 对比（Day57提过虚拟线程）：①ThreadLocal → 可变 + 线程隔离 → 线程池需手动 remove / TTL ②InheritableThreadLocal → 子线程继承一次 → 线程池不适用 ③TTL → 线程池场景传递 → 需要包装 ④ScopedValue（JDK 21 预览）→ 不可变 + 自动清理 + 虚拟线程友好 → `ScopedValue.where("USER", context).run(() -> { ... })` → 自动传递 + 自动清理 → 未来替代 ThreadLocal / 实际应用场景：①用户上下文 → 请求线程 set 用户信息 → Service 层 get → 不用每次传参 ②链路追踪 traceId → 请求线程 set → 日志 get → 自动带 traceId ③事务管理 → Spring `@Transactional` → ThreadLocal 存事务连接 → 同一线程内复用连接 ④数据库连接 → ThreadLocal 存 Connection → 同事务内复用 → 但 Spring 事务管理器帮你做了 → 不需要手动 / 面试重点：解决=finally中remove(必须!) → InheritableThreadLocal=子线程创建时继承一次(线程池不适用) → TTL(阿里TransmittableThreadLocal)=线程池场景每次任务前自动复制/后清理 → ScopedValue(JDK21)=不可变+自动清理+虚拟线程友好→未来替代ThreadLocal → 场景=用户上下文/traceId/事务连接/DB连接）

---

## 话题五：手写代码 - 三数之和（8分钟）

**面试官：写一个函数，给定一个整数数组，找出所有和为 0 的不重复三元组。**

你在纸上/白板上写代码...

**追问1：** 先说说你的思路。暴力怎么做？怎么优化到 O(n²)？

> 你回答...（提示：三数之和 / 暴力：①三重循环 → O(n³) → 对每个 `nums[i]` → 对每个 `nums[j]`（j > i）→ 对每个 `nums[k]`（k > j）→ 如果 `nums[i] + nums[j] + nums[k] == 0` → 记录 → 但要去重 / 优化：排序 + 双指针 → O(n²) ①先排序 → O(n log n) ②固定一个数 `nums[i]` → 在 `i+1` 到 `n-1` 范围内用双指针找两数之和 = `-nums[i]` ③双指针 → left = i+1 → right = n-1 → 如果 `nums[left] + nums[right] < -nums[i]` → left++ → 如果 > → right-- → 如果 == → 记录 → left++ / right-- ④去重 → 固定的 `nums[i]` 如果和前一个相同 → skip（避免重复三元组）→ 找到一组后 → left 和 right 也要跳过相同值 / 代码：
```java
public List<List<Integer>> threeSum(int[] nums) {
    List<List<Integer>> result = new ArrayList<>();
    if (nums == null || nums.length < 3) return result;

    Arrays.sort(nums);  // O(n log n)

    for (int i = 0; i < nums.length - 2; i++) {
        // 剪枝：最小的数 > 0 → 不可能和为 0
        if (nums[i] > 0) break;
        // 去重：跳过相同的 nums[i]
        if (i > 0 && nums[i] == nums[i - 1]) continue;

        int left = i + 1, right = nums.length - 1;
        while (left < right) {
            int sum = nums[i] + nums[left] + nums[right];
            if (sum < 0) {
                left++;
            } else if (sum > 0) {
                right--;
            } else {
                result.add(Arrays.asList(nums[i], nums[left], nums[right]));
                // 去重：跳过相同的 left
                while (left < right && nums[left] == nums[left + 1]) left++;
                // 去重：跳过相同的 right
                while (left < right && nums[right] == nums[right - 1]) right--;
                left++;
                right--;
            }
        }
    }
    return result;
}
```
/ 核心要点：①排序是关键 → 排序后才能用双指针 → 小了 left++ / 大了 right-- ②去重是难点 → 三层去重 → nums[i] 去重 + nums[left] 去重 + nums[right] 去重 ③剪枝 → `nums[i] > 0` → 后面都 > 0 → 不可能和为 0 → break ④时间 O(n²) → 排序 O(n log n) + 外层 O(n) × 内层双指针 O(n) → 总 O(n²) ⑤空间 O(1) → 不算输出数组 / 面试重点：排序+双指针O(n²) → 固定一个数+双指针找两数之和=-nums[i] → 去重=三层(nums[i]跳相同/找到后left跳相同/right跳相同) → 剪枝=nums[i]>0 break → 排序是双指针的前提）

**追问2：** 如果数组里有重复元素，去重的关键是什么？为什么 `nums[i] == nums[i-1]` 要 continue 而不是 `nums[i] == nums[i+1]`？

> 你回答...（提示：去重的方向 / `nums[i] == nums[i-1]` continue（正确）vs `nums[i] == nums[i+1]` continue（错误）：①`nums[i] == nums[i-1]` → 当前和前一个比较 → 如果相同 → 说明前一个已经处理过了 → skip 当前 → 不重复 ②`nums[i] == nums[i+1]` → 当前和后一个比较 → 如果相同 → skip 当前 → 但这会跳过第一个 → 只处理最后一个 → 可能漏解 ③示例 → `[-1, -1, 2]` → i=0 时 nums[0]=-1 → 如果用 `nums[0] == nums[1]` → -1 == -1 → true → skip → 漏掉了 `[-1, -1, 2]` 这个解 ④正确 → i=0 处理 → 找到 [-1, -1, 2] → i=1 → `nums[1] == nums[0]` → skip → 不重复处理 / 面试重点：去重=和前一个比(nums[i]==nums[i-1]→前一个已处理→skip当前) → 不能和后一个比(会跳过第一个→漏解) → 这是双指针去重的标准写法 → left/right找到后也跳相同值(left++/right--跳过连续相同)）

---

# 二面（30分钟）

## 话题六：Canal 原理与数据同步（12分钟）

**面试官：你做过数据同步吗？MySQL 到 ES / Redis 的数据同步怎么做的？Canal 你了解吗？**

> 你回答...

**追问1：** 先说说 Canal 的原理。它怎么监听 MySQL 的数据变更？底层是什么机制？

> 你回答...（提示：Canal 原理 / Canal 是什么：①Canal → 阿里开源的 MySQL binlog 增量订阅和消费组件 ②核心用途 → 监听 MySQL 数据变更 → 同步到 ES / Redis / Kafka / 其他数据源 ③为什么用 Canal → 业务代码不用改 → 不用在每次写 DB 后手动同步 ES → Canal 自动监听 binlog → 异步同步 → 业务解耦 / Canal 伪装成 MySQL 从库：①Canal 的原理 → 伪装成 MySQL Slave（从库）→ 向 MySQL Master 发送 dump 请求 → MySQL 推送 binlog → Canal 解析 binlog → 转换成结构化数据 → 下游消费 ②流程 → Canal Server → 连接 MySQL → 注册为 Slave → 发送 `COM_BINLOG_DUMP` 命令 → MySQL 开始推送 binlog 事件 → Canal 接收 → 解析 → 存储 → 客户端订阅 / MySQL 主从复制原理（Canal 模仿的就是这个）：①Master 写 binlog → binlog 是 MySQL 的变更日志 → 所有写操作（INSERT/UPDATE/DELETE）都记入 binlog ②Master 的 dump 线程 → 监听有 Slave 连接 → 读取 binlog → 发送给 Slave ③Slave 的 IO 线程 → 接收 binlog → 写入 relay log（中继日志）④Slave 的 SQL 线程 → 读 relay log → 重放 SQL → 更新从库数据 ⑤Canal → 相当于 Slave 的 IO 线程 → 接收 binlog → 但不重放 SQL → 而是解析成结构化数据 → 给业务消费 / Canal 架构：
```
MySQL Master
    │ binlog (dump)
    ▼
Canal Server (伪装 Slave)
    │ 解析 binlog → Entry/RowChange
    ▼
Canal Client (业务代码)
    │ 消费变更事件
    ▼
ES / Redis / Kafka / 其他
```
①Canal Server → 连接 MySQL → 伪装 Slave → 接收 binlog → 解析 ②Canal Client → 消费 Canal Server 的数据 → 写入 ES / Redis / Kafka ③Canal Server → 支持集群 → ZooKeeper 做高可用 + 协调 ④Canal 1.1+ → 支持 Canal-Adapter → 直接同步到 ES / Redis / RDB → 不用写 Client / binlog 格式：①Statement → 记录 SQL 语句 → Canal 解析 SQL → 但不知道具体哪些行变了 → 不适合同步 ②Row → 记录每行的变更前/变更后数据 → Canal 能拿到完整的行数据 → 最适合同步 ③Mixed → 混合 → 不推荐 → Canal 要求 binlog_format=ROW ④配置 → `binlog_format=ROW` + `binlog_row_image=FULL`（记录完整的前后镜像）/ Canal 解析 binlog 后的数据结构：①`Entry` → 一个 binlog 事件 → 包含数据库名 / 表名 / 事件类型（INSERT/UPDATE/DELETE）②`RowChange` → 行级变更 → `rowDatas` 列表 → 每行有 `beforeColumns`（变更前）和 `afterColumns`（变更后）③业务拿到 RowChange → 转成 ES 文档 → 写入 ES / 面试重点：Canal=伪装MySQL Slave→发dump请求→MySQL推binlog→Canal解析→结构化数据→下游消费 → 模仿主从复制的IO线程 → binlog_format=ROW+binlog_row_image=FULL → Entry→RowChange(before/after columns) → Canal-Adapter直接同步ES/Redis）

**追问2：** Canal + ES 同步方案有什么坑？怎么保证数据一致性？延迟怎么处理？

> 你回答...（提示：Canal 同步的坑与一致性 / 坑一：binlog 顺序消费 ①binlog 是顺序的 → Canal 按顺序推送 → 但如果 Canal Client 多线程消费 → 可能乱序 → 如 UPDATE A → UPDATE B → 多线程 → B 先执行 → A 后执行 → 如果 A 和 B 有依赖 → 数据不一致 ②解决 → 按 key hash 分配到同一线程 → 如按 userId hash → 同一用户的变更 → 同一线程顺序消费 / 坑二：Canal Server 单点 ①Canal Server 挂了 → binlog 停止消费 → MySQL binlog 不会删（等 Canal 来读）→ 但如果 Canal 挂太久 → binlog 被 MySQL 清理（expire_logs_days）→ Canal 重启 → binlog 已删 → 数据丢失 ②解决 → Canal 集群 + ZooKeeper 高可用 → 一个挂了 → 另一个接管 → 记录消费位点（binlog filename + position）→ 重启从断点继续 / 坑三：ES 更新幂等 ①同一 binlog 事件 → Canal 重推（Canal 重启 / 网络重试）→ ES 重复更新 → 如果 ES 文档有版本号 → 旧版本覆盖新版本 → 数据不一致 ②解决 → ES 用 `_id` = 主键 → 幂等写入 → 重复写 → 覆盖 → 结果一致（因为是同一份数据）→ 但要注意 → 如果有计算字段（如 count += 1）→ 非幂等 → 要用全量覆盖 / 坑四：多表 JOIN 同步 ①场景 → ES 需要宽表（user + order + address JOIN）→ Canal 只推送单表变更 → 不能 JOIN ②解决 → Canal 监听多张表 → 各自推到 Kafka → 下游 Flink/Spark Streaming 做 JOIN → 写入 ES / 一致性方案：①最终一致 → Canal 异步 → 有延迟 → 不是强一致 → 但最终数据一致 ②延迟 → 毫秒级（Canal 实时推送）到秒级（Kafka 缓冲 / ES 写入慢）③如果延迟大 → 检查 → Canal Server 是否积压 / ES 写入是否慢 / 网络是否抖动 ④业务层兜底 → 读 ES → 如果读不到（延迟）→ 回查 DB → 降级 / 全量 + 增量：①全量初始化 → 第一次同步 → 用 DataX / Spark 把 MySQL 全量数据导入 ES ②增量同步 → Canal 监听 binlog → 增量更新 ES ③切换时机 → 全量完成后 → Canal 从全量开始时的 binlog 位点开始消费 → 保证不丢 ④这是"全量 + 增量"的标准模式 / 和双写对比：①双写 → 业务代码写 DB 后 → 同步写 ES → 问题 → 不是事务（DB 成功 ES 失败 → 不一致）→ 或分布式事务（太重）→ 代码侵入 ②Canal → 业务只写 DB → Canal 异步同步 ES → 解耦 → 但有延迟 → 最终一致 ③Canal 更好 → 业务解耦 + 不侵入 → 但要接受最终一致 / 面试重点：坑=顺序消费(按key hash到同线程)/Canal单点(集群+ZK+记录binlog位点)/ES幂等(_id主键覆盖/计算字段非幂等)/多表JOIN(各推Kafka+Flink JOIN) → 一致性=最终一致(毫秒到秒延迟) → 全量+增量(全量初始化+Canal增量+从全量位点开始消费) → 和双写比=Canal解耦不侵入但最终一致/双写强一致但非事务不一致)

**追问3：** 如果不用 Canal，还有什么数据同步方案？各有什么优缺点？

> 你回答...（提示：数据同步方案对比 / 方案一：双写（业务代码同步写）①写 DB → 同步写 ES/Redis → 简单直观 ②问题 → 不是事务 → DB 成功 ES 失败 → 不一致 → 或用分布式事务（太重）→ 代码侵入 ③适合 → 数据量小 / 一致性要求不高 / 方案二：Canal（binlog 订阅）①Canal 监听 binlog → 异步同步 → 业务解耦 ②优点 → 不侵入业务 / 最终一致 / 自动同步 ③缺点 → 有延迟 / 架构复杂 / 需要维护 Canal ④适合 → 大部分场景 / 最终一致可接受 / 方案三：MQ 异步同步 ①写 DB → 发 MQ → 消费者写 ES/Redis ②优点 → 业务和同步解耦 → MQ 削峰 ③缺点 → 不是事务（DB 成功 MQ 发送失败 → 丢消息）→ 要用本地消息表保证 → 代码侵入（要发 MQ）④和 Canal 区别 → MQ 需要业务代码主动发消息 → Canal 不需要 → Canal 自动监听 / 方案四：定时任务全量同步 ①定时任务 → 每隔 N 分钟 → 查 MySQL → 对比 → 增量更新 ES ②优点 → 简单 / 不依赖 binlog ③缺点 → 延迟大（分钟级）→ 全量对比 → 性能差 → 不适合实时 ④适合 → 数据量小 / 延迟要求低 / 方案五：Flink CDC ①Flink CDC → 和 Canal 类似 → 监听 binlog → 但 Flink CDC 集成在 Flink 生态 → 可以做复杂 ETL / JOIN / 聚合 ②优点 → 强大的流处理能力 → 多表 JOIN / 窗口聚合 / 状态管理 ③缺点 → Flink 重量级 → 运维复杂 → 适合大数据场景 ④和 Canal 区别 → Canal 轻量（只做 binlog 订阅和转发）→ Flink CDC 重量（做流处理 + ETL）→ 小场景用 Canal / 大数据场景用 Flink CDC / 选型建议：①小数据量 + 一致性要求低 → 双写 ②大部分场景 → Canal → 解耦 + 最终一致 + 不侵入 ③需要多表 JOIN / 复杂 ETL → Flink CDC ④不需要实时 → 定时任务 ⑤需要事务性消息 → MQ + 本地消息表 / 面试重点：双写(简单但非事务不一致)/Canal(解耦不侵入但最终一致)/MQ异步(要本地消息表保证)/定时任务(延迟大)/Flink CDC(强大流处理但重量级) → 选型=Canal最常用(解耦+最终一致)/Flink CDC适合大数据ETL/双写适合小数据量)

---

## 话题七：核心设计题 - 消费金融授信引擎（18分钟）

**面试官：度小满做消费信贷，核心系统之一是授信引擎——用户申请借款，系统自动评估额度、利率、期限。每天几十万申请，要求秒级出结果。怎么设计？**

> 你回答...

**追问1：** 先说说授信流程。用户申请借款到出额度，中间经过哪些环节？

> 你回答...（提示：授信流程 / 授信全流程：①用户申请 → 填写基本信息（姓名/身份证/手机/收入）→ 提交 ②准入校验 → 年龄（18-55）/ 黑名单 / 同盾反欺诈 / 多头借贷检查 → 不通过直接拒 ③征信查询 → 调用央行征信 API / 百行征信 → 获取信用报告 → 查询记录数 / 逾期记录 / 负债情况 ④数据补充 → 调用第三方数据源 → 运营商数据 / 电商数据 / 社交数据 → 丰富用户画像 ⑤特征计算 → 根据征信 + 第三方数据 → 计算特征 → 近6个月逾期次数 / 信用卡使用率 / 负债收入比 / 查询次数 ⑥风控模型 → 信用评分模型（A卡）→ 输入特征 → 输出分数（300-850）→ 分数越高 → 风险越低 ⑦额度利率决策 → 根据分数 + 收入 + 负债 → 决定 → 额度（1000-20万）/ 利率（年化7-24%）/ 期限（3/6/12/24期）⑧审核结果 → 通过（出额度）→ 拒绝（告知原因）→ 转人工（灰度区间）/ 各环节耗时：①准入校验 → 10-50ms（内存查询）②征信查询 → 1-3s（外部 API）→ 最慢 ③第三方数据 → 500ms-2s（多数据源并行）④特征计算 → 10-50ms（规则引擎）⑤风控模型 → 50-200ms（模型推理）⑥总耗时 → 目标 < 5s → 关键路径是征信查询和第三方数据 / 面试重点：授信流程=准入校验→征信查询(最慢)→第三方数据补充(并行)→特征计算→模型评分(A卡)→额度利率决策 → 目标<5s秒级 → 关键路径=征信查询(1-3s)+第三方数据(并行减少)/模型推理(50-200ms)）

**追问2：** 征信查询 1-3 秒，多个第三方数据源各 500ms-2s，怎么做到总耗时 < 5 秒？

> 你回答...（提示：异步并行优化 / 串行 vs 并行：①串行 → 准入(50ms) → 征信(2s) → 第三方数据(2s) → 特征(50ms) → 模型(200ms) → 总 4.3s → 勉强 ②但征信查询和第三方数据 → 没有依赖关系 → 可以并行 → 征信(2s) || 第三方数据(2s) → 取最大 2s → 总 2.3s → 秒级 / CompletableFuture 并行（今天话题一学的）：①征信和第三方数据 → 互相独立 → 并行查询
```java
public CreditResult apply(CreditApplyRequest req) {
    // 1. 准入校验（同步，必须先做）
    if (!checkEligibility(req)) {
        return CreditResult.reject("准入不通过");
    }

    // 2. 征信查询 + 第三方数据 → 并行（CompletableFuture）
    CompletableFuture<CreditReport> creditCF =
        CompletableFuture.supplyAsync(() -> creditService.query(req.getIdCard()), creditExecutor)
                         .orTimeout(3, TimeUnit.SECONDS)
                         .exceptionally(ex -> CreditReport.empty());  // 超时降级

    CompletableFuture<ThirdPartyData> thirdPartyCF =
        CompletableFuture.supplyAsync(() -> thirdPartyService.query(req.getPhone()), thirdPartyExecutor)
                         .orTimeout(2, TimeUnit.SECONDS)
                         .exceptionally(ex -> ThirdPartyData.empty());  // 超时降级

    // 3. 等两个都完成 → 合并 → 计算特征 → 跑模型
    return CompletableFuture.allOf(creditCF, thirdPartyCF)
        .thenApply(v -> {
            CreditReport credit = creditCF.join();      // 已完成
            ThirdPartyData data = thirdPartyCF.join();   // 已完成
            // 特征计算
            Features features = featureService.calculate(credit, data);
            // 模型评分
            Score score = modelService.predict(features);
            // 决策
            return decisionEngine.decide(score, features, req);
        })
        .orTimeout(5, TimeUnit.SECONDS)
        .exceptionally(ex -> {
            log.error("授信超时", ex);
            return CreditResult.reject("系统繁忙，请稍后重试");  // 超时拒绝
        })
        .join();  // 对外同步接口
}
```
②关键 → 独立步骤并行 + 超时保护 + 降级策略 ③降级 → 征信查询超时 → 返回空报告 → 用其他数据兜底 → 但风控要求"征信必须查到"→ 如果降级 → 可能 fail-closed（拒绝）→ 看业务要求 / 异步非关键路径：①非关键数据（运营商/电商）→ 异步 → 不阻塞主流程 → 后台补全 → 更新额度 ②关键数据（征信）→ 同步等 → 必须拿到才能决策 / 缓存优化：①征信报告 → 同一人短期内不变 → 缓存 1 小时 → 第二次申请 → 从缓存取 → 跳过外部查询 ②第三方数据 → 缓存 30 分钟 → 减少外部调用 / 数据源健康检查 + 熔断：①某个数据源频繁超时 → Sentinel 熔断 → 跳过该数据源 → 降级 ②不影响整体流程 → 用其他数据源补偿 / 面试重点：并行=CompletableFuture并行独立步骤(征信||第三方)+orTimeout超时+exceptionally降级 → 关键数据同步等/非关键异步补 → 缓存(征信1h/第三方30min) → 数据源熔断+降级补偿 → 目标<5s）

**追问3：** 风控模型（A卡）是 Python 训练的。Java 系统怎么调用？PMML 和服务化调用各有什么优缺点？

> 你回答...（提示：Python 模型与 Java 集成 / 方案一：PMML（预测模型标记语言）①PMML → XML 格式描述模型 → 跨语言 → Python 训练 → 导出 PMML → Java 加载 PMML → 本地推理 ②流程 → Python（scikit-learn / xgboost）→ 训练 → `sklearn2pmml` 导出 PMML 文件 → Java 用 `JPMML-Evaluator` 加载 → 输入特征 → 输出预测 ③优点 → 无网络调用 → 延迟低（毫秒级）→ 无外部依赖 → Java 进程内推理 ④缺点 → 只支持部分模型类型 → 深度学习不支持 → PMML 文件更新要重新部署 Java → 热更新难 → PMML 解析有性能开销（首次加载慢） / 方案二：服务化调用（Python Flask/FastAPI）①Python 训练 → 保存模型（pickle/joblib）→ Flask/FastAPI 加载 → 提供 REST API → Java HTTP 调用 ②优点 → 支持所有模型（深度学习 / 复杂模型）→ 模型更新只需重启 Python 服务 → 不影响 Java → 技术栈独立 ③缺点 → 网络调用 → 延迟高（10-50ms）→ 要维护 Python 服务 → 多一个故障点 ④优化 → gRPC 代替 HTTP → 序列化更快 → 延迟降到 1-5ms / 方案三：ONNX（开放神经网络交换）①ONNX → 跨框架模型格式 → Python 训练 → 导出 ONNX → Java 用 ONNX Runtime 加载 ②优点 → 支持深度学习 → 跨框架 → 性能好（C++ 底层）③缺点 → 生态不如 PMML 成熟 → 部分模型不支持 / 选型建议：①逻辑回归 / 决策树 / XGBoost → PMML → 本地推理 → 毫秒级 → 不依赖 Python ②深度学习 / 复杂模型 → 服务化调用 → gRPC → 1-5ms ③A卡（信用评分）→ 通常是逻辑回归 / XGBoost → PMML 最合适 → 本地推理 → 0 网络延迟 / 架构设计：①模型管理 → Python 训练平台 → 训练 → 评估 → 发布（导出 PMML 上传到配置中心）②Java 加载 → 启动时 / 配置变更时 → 从配置中心下载 PMML → 加载到内存 → 本地推理 ③模型热更新 → Nacos 配置变更 → 监听 → 重新加载 PMML → 不重启 Java → 类似规则引擎热加载（Day51 提过）④版本管理 → A/B 测试 → 新模型灰度 → 10% 流量用新模型 → 对比效果 → 全量切换 / 面试重点：PMML=XML格式跨语言→Python导出/Java加载→本地推理毫秒级(但只支持部分模型/热更新难) → 服务化=Python提供API/Java调用→支持所有模型但网络延迟(10-50ms/gRPC降到1-5ms) → ONNX=跨框架+深度学习但生态不成熟 → A卡(逻辑回归/XGBoost)→PMML最合适 → 模型热更新=Nacos监听+重新加载PMML+灰度A/B测试）

**追问4：** 授信引擎的高可用怎么设计？如果模型服务挂了、征信查不到、某个数据源超时，怎么办？

> 你回答...（提示：授信引擎高可用 / 核心原则 → fail-closed（安全第一）：①风控系统 → 宁可拒绝 → 不能放行 → 如果系统挂了 → 不能"默认通过"→ 必须"默认拒绝" ②和普通系统不同 → 电商系统挂了 → 降级到缓存 → 用户还能买 → 风控系统挂了 → 不能降级到"通过"→ 要降级到"拒绝"或"转人工" / 各环节降级策略：①征信查询超时 → 策略一：fail-closed → 拒绝（"征信查询失败，请稍后重试"）→ 安全但用户体验差 → 策略二：转人工 → 灰度 → 人工审核 → 但人工处理慢 → 策略三：用缓存 → 之前查过 → 缓存内的征信 → 但可能过期 → 看业务要求 ②第三方数据源超时 → 降级 → 跳过该数据源 → 用已有数据 → 但模型精度下降 → 如果关键数据源 → fail-closed ③模型服务挂了 → 策略一：降级到规则引擎 → 规则引擎（硬编码规则）→ 如"负债收入比 > 50% → 拒绝"→ 简单但不如模型精准 → 策略二：用旧模型 → 如果新模型挂了 → 切回上一个版本 → 策略三：转人工 ④决策引擎挂了 → 转人工 → 人工审核 / 高可用架构：①多副本 → 授信引擎多实例 → 无状态 → 横向扩展 → 一个挂了其他继续 ②依赖隔离 → 征信查询 / 第三方数据 / 模型服务 → 各自独立线程池（CompletableFuture 指定 executor）→ 一个超时不影响其他 ③熔断 → Sentinel → 依赖频繁超时 → 熔断 → 快速失败 → 降级 ④超时控制 → 每个环节设置超时 → 征信 3s / 第三方 2s / 模型 500ms / 总体 5s → 超时降级 ⑤重试 → 外部 API → 可重试（但要幂等）→ 但不能无限重试 → 限制重试次数 ⑥异步补偿 → 非关键数据 → 异步补全 → 不阻塞主流程 ⑦监控 → 每个环节耗时 / 成功率 / 降级次数 → Prometheus + 告警 / 和普通系统降级的区别：①普通系统 → 降级到缓存 → 用户无感 → 继续服务 ②风控系统 → 降级到"拒绝"或"转人工"→ 不能降级到"通过"→ 安全优先 ③这就是 fail-closed vs fail-open 的区别 → 风控=必须 fail-closed / 面试重点：高可用核心=fail-closed(风控挂了不能放行→默认拒绝/转人工) → 各环节降级=征信超时拒绝或转人工/第三方跳过用已有数据/模型挂了降级到规则引擎或旧模型/决策挂了转人工 → 架构=多副本无状态+独立线程池隔离+Sentinel熔断+每环节超时+异步补偿+监控告警 → 和普通系统区别=风控必须fail-closed不能fail-open）

**追问5：** 额度和利率是怎么定的？模型给出一个分数，怎么转换成具体的额度和利率？

> 你回答...（提示：额度利率决策 / 决策流程：①模型评分 → 300-850 分 → 分数越高 → 风险越低 ②分数分段 → 如 → 750+（A类优质）/ 650-749（B类良好）/ 550-649（C类一般）/ 450-549（D类次级）/ < 450（E类拒绝）③每个分段 → 对应不同的额度 / 利率 / 期限策略 → 策略表（规则）：
| 分数段 | 额度范围 | 年化利率 | 可选期限 | 风险等级 |
|--------|---------|---------|---------|---------|
| 750+ | 5万-20万 | 7%-12% | 3/6/12/24期 | A优质 |
| 650-749 | 2万-10万 | 12%-18% | 3/6/12期 | B良好 |
| 550-649 | 5000-5万 | 18%-24% | 3/6期 | C一般 |
| 450-549 | 1000-2万 | 24% | 3期 | D次级 |
| <450 | 拒绝 | - | - | E拒绝 |
④额度 → 还要结合收入和负债 → 如月收入 1万 → 月还款不超过收入 50% → 最大月供 5000 → 根据期限和利率 → 反推最大额度 ⑤利率 → 监管要求 → 年化利率不能超过 24%（LPR 4倍）→ 消费金融公司 → 通常 7%-24% ⑥决策引擎 → 输入 → 分数 + 收入 + 负债 + 期限偏好 → 输出 → 额度 + 利率 + 期限 / 额度计算逻辑：①基础额度 → 由分数段决定 → 如 A 类基础额度 20 万 ②收入调整 → 月收入 / 月还款比 → 如月收入 1万 → 月供上限 5000 → 24 期 → 利率 12% → 反推额度 ≈ 10 万 ③负债扣减 → 现有负债 → 如已有 2 万贷款 → 额度扣减 → 10 万 - 2 万 = 8 万 ④最终额度 → min(基础额度, 收入反推额度) - 负债 → 取小的 → 风控保守 ⑤额度还要考虑 → 多头借贷（在其他平台也有借款）→ 征信查询次数多 → 额度降低 / 利率定价：①基础利率 → 分数段决定 → A 类 7%-12% ②风险溢价 → 风险越高 → 利率越高 → 覆盖坏账成本 ③资金成本 → 度小满的资金来源 → 银行存款 / 发行债券 → 资金成本 3%-5% → 利率 > 资金成本 + 运营成本 + 风险成本 = 盈利 ④监管上限 → 年化 24% → 不能超过 ⑤定价模型 → 利率 = 资金成本 + 运营成本 + 风险溢价 + 利润 → 动态定价 → 根据用户风险动态调整 / 面试重点：额度利率=模型分数分段→策略表(额度/利率/期限) → 额度=min(基础额度,收入反推)-负债(保守取小) → 利率=资金成本+运营成本+风险溢价+利润(年化<24%监管上限) → 动态定价(风险越高利率越高/覆盖坏账) → 多头借贷查征信→额度扣减）

**追问6：** 用户授信通过后，额度是永久的吗？额度管理怎么做？动态调额怎么设计？

> 你回答...（提示：额度管理 / 额度有效期：①授信额度 → 有有效期 → 通常 6 个月-1 年 → 过期要重新授信 ②有效期内 → 可以多次借款 → 不超过总额度 ③每次借款 → 扣减可用额度 → 还款 → 恢复额度 / 动态调额（B卡）：①B卡（行为评分卡）→ 贷后行为评分 → 根据用户的还款行为 → 动态调整额度 ②输入 → 还款记录（按时/逾期）/ 借款频率 / 借款金额变化 / 提前还款 / 信用卡使用率变化 ③如 → 用户每次按时还款 → B 卡分数上升 → 额度提升（提额）→ 利率降低（优质客户）④如 → 用户逾期 → B 卡分数下降 → 额度降低 → 利率上升 → 甚至冻结额度 ⑤B卡定期跑 → 每月一次 → 批量计算 → 更新额度 / 额度冻结/解冻：①冻结场景 → 逾期 / 欺诈嫌疑 / 监管要求 / 用户主动申请冻结 ②冻结 → 可用额度 = 0 → 不能新借 → 但已有借款继续按计划还款 ③解冻 → 风控审核通过 → 恢复额度 / 额度并发控制：①用户同时多笔借款 → 可用额度要并发扣减 → 防超借 ②Redis DECR 原子扣减 → 0 → 拒绝 → 和秒杀防超发一样（Day49提过）③DB 记录 → 流水 + 可用额度 → 定期对账 / 额度版本管理：①每次额度变更 → 记录版本号 → 旧版本作废 ②额度变更 → 审核 → 审批通过 → 生效 ③审计 → 额度变更记录 → 谁改的 / 为什么改 / 什么时候改 / 面试重点：额度有效期(6个月-1年/过期重新授信) → 动态调额=B卡(行为评分/还款行为→提额或降额) → 冻结(逾期/欺诈/监管) → 并发控制=Redis DECR防超借 → 版本管理+审计 → 额度管理是贷后核心+持续风控）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| CompletableFuture 异步编程（Future三个局限/thenApply vs thenCompose vs thenCombine/allOf/anyOf/exceptionally/commonPool坑/独立线程池） | 能讲清 / 讲不全 / 不会★ | |
| MySQL 间隙锁与死锁分析（间隙锁防幻读/唯一索引退化/死锁场景/排查SHOW ENGINE INNODB STATUS/预防统一加锁顺序/RC替代RR） | 能讲清 / 讲不全 / 不会★ | |
| MyBatis 缓存机制（一级缓存SqlSession级/Spring下失效/localCacheScope=STATEMENT/二级缓存namespace级/跨namespace脏数据/企业用Spring Cache替代） | 能讲清 / 讲不全 / 不会★ | |
| ThreadLocal 原理与内存泄漏（Thread.threadLocals/ThreadLocalMap弱引用key强引用value/线程池泄漏/remove/InheritableThreadLocal/TTL/ScopedValue） | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（三数之和/排序+双指针O(n²)/三层去重/剪枝） | 能讲清 / 讲不全 / 不会★ | |
| Canal 原理与数据同步（伪装Slave/binlog订阅/Row格式/Entry→RowChange/顺序消费/单点高可用/ES幂等/全量+增量/方案对比） | 能讲清 / 讲不全 / 不会★ | |
| 消费金融授信引擎（授信流程/CompletableFuture并行优化/PMML模型集成/额度利率定价/fail-closed高可用/B卡动态调额） | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **CompletableFuture**：Future 三个局限 = `get()` 阻塞 / 不能链式 / 不能组合。CompletableFuture 解决：回调驱动（thenApply/thenCompose/thenCombine）+ 组合（allOf/anyOf）+ 异常处理（exceptionally/handle）。`thenApply` = 同步转换 `T→R`，`thenCompose` = 异步转换 `T→CompletableFuture<R>`（扁平化，类比 flatMap），`thenCombine` = 合并两个独立 CF。**坑**：默认 commonPool 全局共享 → CPU 密集拖慢 IO / 阻塞操作耗尽线程 / parallelStream 也用它。**生产**：为不同场景创建独立线程池 + `orTimeout` 超时保护 + `exceptionally` 降级
> 2. **间隙锁与死锁**：间隙锁 = 锁两个索引记录之间的间隙 → 防 INSERT → 解决 RR 下当前读幻读。唯一索引等值命中 → 退化为记录锁（不加间隙锁）；非唯一索引 → 加临键锁。**死锁场景**：两个事务对同一间隙加间隙锁（兼容）→ 各自 INSERT（需要插入意向锁，和间隙锁冲突）→ 互相等待 → 死锁。**排查**：`SHOW ENGINE INNODB STATUS` 看 `LATEST DETECTED DEADLOCK`。**预防**：统一加锁顺序（主键升序）+ 缩短事务 + RC 代替 RR（RC 无间隙锁）
> 3. **MyBatis 缓存**：一级缓存 = SqlSession 级别（HashMap）。Spring 下每次 Mapper 调用新建 SqlSession → 一级缓存基本失效 → 只有 `@Transactional` 方法内多次查同一数据才生效。二级缓存 = namespace 级别跨 SqlSession → **坑**：跨 namespace 更新不感知（多表 JOIN 脏数据）/ 分布式不一致 / 粒度粗。**企业实践**：关闭 MyBatis 两级缓存（`localCacheScope=STATEMENT` + `cache-enabled=false`）→ 用 Spring Cache `@Cacheable` + Redis/Caffeine 精确控制
> 4. **ThreadLocal**：底层 = `Thread.threadLocals`（ThreadLocalMap）→ key = ThreadLocal 弱引用 → value = 强引用。**泄漏根因**：线程池核心线程不死 → ThreadLocal 被 GC（弱引用 key）→ 但 value 强引用不回收 → 泄漏累积。**危害**：内存 OOM + 数据串号（线程复用 → 用户 A 数据被用户 B 看到）。**解决**：`finally { tl.remove(); }`（必须！）。`InheritableThreadLocal` = 子线程创建时继承一次（线程池不适用）→ 用阿里 **TTL**（TransmittableThreadLocal）线程池场景传递 → `ScopedValue`（JDK 21 预览）未来替代
> 5. **Canal**：伪装 MySQL Slave → 发 dump 请求 → MySQL 推 binlog → Canal 解析 → 结构化数据（Entry→RowChange）→ 下游消费 ES/Redis/Kafka。要求 `binlog_format=ROW`。**坑**：顺序消费（按 key hash 同线程）/ Canal 单点（集群+ZK+记录 binlog 位点）/ ES 幂等（`_id`=主键覆盖）/ 多表 JOIN（各推 Kafka + Flink JOIN）。**方案对比**：Canal（解耦不侵入，最终一致）> 双写（非事务不一致）> 定时任务（延迟大）> Flink CDC（重量级 ETL）
> 6. **三数之和**：排序 + 双指针 O(n²)。固定 `nums[i]` → 双指针找两数之和 = `-nums[i]`。**去重关键**：`nums[i] == nums[i-1]` continue（和前一个比，前一个已处理 → skip），不能 `== nums[i+1]`（会跳过第一个 → 漏解）。剪枝：`nums[i] > 0` → break。left/right 找到后也要跳过连续相同值
> 7. **消费金融授信引擎**：流程 = 准入校验 → 征信查询（最慢 1-3s）→ 第三方数据（并行）→ 特征计算 → 模型评分（A 卡）→ 额度利率决策。**并行优化**：CompletableFuture 并行征信和第三方数据 + `orTimeout` + `exceptionally` 降级。**模型集成**：A 卡（逻辑回归/XGBoost）→ PMML 本地推理（毫秒级）/ 复杂模型 → 服务化 gRPC（1-5ms）。**高可用**：fail-closed（风控挂了不能放行 → 默认拒绝/转人工）→ 各环节降级 + 独立线程池隔离 + Sentinel 熔断。**额度定价**：分数分段 → 策略表 → 额度 = min(基础额度, 收入反推) - 负债 → 利率 = 资金成本 + 运营 + 风险溢价 + 利润（年化 < 24%）。**额度管理**：有效期 6-12 月 → B 卡（行为评分）动态调额 → Redis DECR 防超借 → 版本管理 + 审计
