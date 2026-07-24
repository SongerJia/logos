# 面试模拟 - Day 54

> 日期：2026-07-24（周五） | 模拟岗位：华为（杭州研究所）- 企业金融业务部 - Java开发工程师
> 建议时长：85分钟（一面55分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day54，"查漏补缺"阶段第四周。模拟华为杭州研究所企业金融业务部——为银行/保险/证券提供IT基础设施和核心系统。华为面试特点：计算机基础功底要求高、注重设计原理而非框架使用、追问底层"为什么"、手写代码要求规范。今天引入 Java 异常体系与最佳实践、MySQL 索引下推(ICP)与覆盖索引优化、Spring MVC DispatcherServlet 请求处理流程、Redis 大Key/热Key/慢查询排查、Java ForkJoinPool 工作窃取算法 5 个全新话题——都是高频考点但之前没有作为独立话题系统考过的内容。

---

# 一面（55分钟）

## 话题一：Java 异常体系与最佳实践（11分钟）

**面试官：先聊个基础。Java 的异常体系你了解吗？Error 和 Exception 有什么区别？Checked Exception 和 Unchecked Exception 呢？**

> 你回答...

**追问1：** 先画一下 Java 异常体系的继承树。Throwable 下面怎么分的？

> 你回答...（提示：Java 异常体系继承树 / `Throwable` → 顶层父类 → 有两个分支：Error 和 Exception / `Error`：①表示 JVM 级别的严重错误 → 程序无法恢复 → 不应该被 catch ②常见 Error → `OutOfMemoryError`（堆溢出/元空间溢出/直接内存溢出）→ `StackOverflowError`（栈溢出 → 递归太深）→ `VirtualMachineError`（虚拟机内部错误）③Error 是 unchecked → 编译器不强制处理 → 也不应该处理 → 让它崩 → 因为程序已经不正常了 → catch 了也没用 → 比如都 OOM 了 → 你 catch 住能干什么 → 内存都没了 / `Exception`：①程序级别的异常 → 可以被捕获和处理 ②分两支 → `RuntimeException`（运行时异常 → unchecked）→ 其他 Exception（编译时异常 → checked）/ `RuntimeException`（unchecked）：①编译器不强制处理 → 因为太多了 → 每个方法都可能抛 NullPointerException → 如果都 catch → 代码没法写 ②常见 → `NullPointerException` / `ClassCastException` / `ArrayIndexOutOfBoundsException` / `ArithmeticException` / `IllegalArgumentException` / `ConcurrentModificationException` ③本质 → 编程错误 → 空指针是你代码写错了 → 应该修代码而不是 catch / `Checked Exception`（非 RuntimeException 的 Exception）：①编译器强制处理 → 要么 try-catch 要么 throws → 否则编译不通过 ②常见 → `IOException` / `SQLException` / `ClassNotFoundException` / `InterruptedException` ③本质 → 外部环境导致的异常 → 文件不存在/网络断了/数据库挂了 → 不是代码错误 → 无法避免 → 必须处理 / 面试重点：Throwable → Error（JVM错误不catch）+ Exception → RuntimeException（unchecked 编程错误）+ Checked Exception（强制处理 外部异常））

**追问2：** `@Transactional` 默认回滚哪些异常？如果我 throw 一个 checked Exception，事务会回滚吗？

> 你回答...（提示：@Transactional 的回滚规则 —— 这是个经典坑 / 默认行为：①`@Transactional` 默认只回滚 `RuntimeException` 和 `Error` ②如果你 throw `IOException`（checked Exception）→ 事务**不会回滚** → 数据已经提交 → 这是一个非常隐蔽的 bug / 原因：①Spring 的 `RuleBasedTransactionAttribute` → 默认回滚规则 → `rollbackOn(Throwable ex)` → `return (ex instanceof RuntimeException || ex instanceof Error)` ②checked Exception 不在默认回滚范围 → Spring 认为_checked Exception 是"业务可预期的异常" → 不应该回滚 → 这是一种保守设计 / 实际场景：①你在 @Transactional 方法里 → 读文件 → 文件不存在 → throw IOException → Spring 不回滚 → 数据库的修改已经提交了 → 脏数据 ②这是生产环境最常见的事务 bug 之一 / 解决方案：①`@Transactional(rollbackFor = Exception.class)` → 显式指定回滚所有异常 → 包括 checked ②`@Transactional(rollbackFor = {IOException.class, SQLException.class})` → 指定回滚特定异常 ③阿里规范强制 → `@Transactional` 必须加 `rollbackFor = Exception.class` → 不加就是 bug ④`noRollbackFor` → 指定不回滚的异常 → 很少用 / 面试重点：@Transactional 默认只回滚 RuntimeException + Error → throw checked Exception 不回滚 → 生产必须加 rollbackFor = Exception.class → 这是阿里规范强制的）

**追问3：** try-with-resources 你用过吗？它解决什么问题？底层是怎么实现的？

> 你回答...（提示：try-with-resources —— Java 7 引入 / 解决什么问题：①传统方式 → 手动在 finally 里 close → 容易忘 → 资源泄漏 → 而且 close 也可能抛异常 → 嵌套 try → 代码丑 ②传统写法：
```java
BufferedReader reader = null;
try {
    reader = new BufferedReader(new FileReader("file.txt"));
    // 使用 reader
} catch (IOException e) {
    e.printStackTrace();
} finally {
    if (reader != null) {
        try {
            reader.close();  // close 也可能抛异常
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
}
```
③try-with-resources → 自动关闭 → 代码简洁：
```java
try (BufferedReader reader = new BufferedReader(new FileReader("file.txt"))) {
    // 使用 reader
} catch (IOException e) {
    e.printStackTrace();
}
// reader 自动 close → 不需要 finally
```
/ 底层实现：①try-with-resources 要求资源实现 `AutoCloseable` 接口 → `void close() throws Exception` ②Java 7+ 编译器自动生成 finally → 调用 close() → 编译后等价于传统写法 → 但是自动的 ③多个资源 → 分号分隔 → 声明顺序的逆序关闭（后声明的先 close）→ 类似栈的销毁顺序 ④Java 9+ → 可以引用外部已声明的 effectively final 变量 → 不需要重新声明 / 异常处理增强：①如果 try 块和 close 都抛异常 → try 块的异常是主异常 → close 的异常被 `addSuppressed()` 挂到主异常上 → `Throwable.getSuppressed()` 获取 → 不丢失 ②传统方式 → close 的异常会覆盖 try 块的异常 → 信息丢失 / 和 Connection/Statement/ResultSet 的关系：①JDBC 资源 → Connection/Statement/ResultSet 都实现了 AutoCloseable ②传统 → 三个 finally 嵌套 → 丑 ③try-with-resources → 三个资源一行搞定 → 自动逆序关闭 / 面试重点：try-with-resources=Java7+自动close → 要求AutoCloseable → 编译器生成finally → 多资源逆序关闭 → close异常被suppressed不丢失）

**追问4：** 自定义异常你设计过吗？在金融系统里，你怎么设计异常体系的？

> 你回答...（提示：金融系统异常设计 / 自定义异常原则：①继承 RuntimeException → 不强制调用者 catch → checked Exception 在框架层会导致到处 throws → 侵入性大 → Spring/JDBC 早期用 checked Exception → 后来越来越多转向 RuntimeException ②错误码 + 消息 → 不要只 throw new RuntimeException("余额不足") → 应该 `throw new BizException("ACCOUNT_BALANCE_NOT_ENOUGH", "账户余额不足")` ③错误码规范化 → 如 ACCOUNT_001 / TRANSFER_002 → 前缀按业务域 / 金融系统异常分层：①`BaseException extends RuntimeException` → 基类 → code + message + timestamp + traceId ②`BizException extends BaseException` → 业务异常 → 余额不足/限额/状态不允许 → HTTP 400 → 前端展示 ③`SysException extends BaseException` → 系统异常 → DB异常/MQ异常/第三方调用失败 → HTTP 500 → 日志告警 ④`ParamException extends BaseException` → 参数校验异常 → 字段为空/格式错误 → HTTP 400 → 前端展示 ⑤`AuthException extends BaseException` → 认证授权异常 → token过期/无权限 → HTTP 401/403 / 异常处理：①`@RestControllerAdvice` + `@ExceptionHandler` → 全局异常处理 ②`BizException` → 返回 HTTP 400 + 错误码 + message → 前端展示 ③`SysException` → 返回 HTTP 500 → 记录 ERROR 日志 → 告警 ④`Exception`（兜底）→ 返回 "系统繁忙，请稍后重试" → 不暴露内部细节 / 和事务的关系：①`BizException extends RuntimeException` → @Transactional 默认回滚 → 但有时业务异常不应该回滚 → 如"查询无数据" ②方案 → `@Transactional(noRollbackFor = NoDataFoundException.class)` → 或把这类异常不继承 RuntimeException ③实际 → 金融核心操作（转账/扣款）的异常都应该回滚 → 参数校验在事务外做 → 进了事务就要保证原子性 / 面试加分：能说出"自定义异常继承RuntimeException+错误码 → 全局@RestControllerAdvice统一处理 → BizException返回400给前端 → SysException返回500记日志告警 → @Transactional默认回滚RuntimeException"→ 展示对异常设计的工程化理解）

---

## 话题二：MySQL 索引下推(ICP)与覆盖索引优化（12分钟）

**面试官：你做过 SQL 优化。MySQL 5.6 引入了一个叫"索引下推"的优化，你了解吗？它解决了什么问题？**

> 你回答...

**追问1：** 先说说什么是索引下推（Index Condition Pushdown, ICP）？在没有 ICP 之前，联合索引的查询是怎么执行的？

> 你回答...（提示：ICP 原理 —— 索引下推 / 背景：联合索引 `INDEX(name, age)` → 最左前缀原则 → `WHERE name LIKE '张%' AND age = 25` → name 走索引 → age 能不能走索引？/ 没有 ICP（MySQL 5.6 之前）：①存储引擎层 → 用联合索引的 name 前缀匹配 → 找到所有 name LIKE '张%' 的记录 → 比如找到 1000 条 ②每条记录 → 回表 → 从聚簇索引取完整行数据 → 传给 Server 层 ③Server 层 → 再用 `age = 25` 过滤 → 最终只剩 10 条 ④问题 → 回表了 1000 次 → 但最终只有 10 条满足 → 990 次回表是浪费的 → 随机 IO 性能差 / 有 ICP（MySQL 5.6+）：①存储引擎层 → 用联合索引的 name 前缀匹配 → 找到 1000 条 ②在索引上 → 直接判断 `age = 25`（age 在联合索引里 → 不需要回表就能拿到）→ 过滤后只剩 10 条 ③只对这 10 条回表 → 从聚簇索引取完整行 ④回表次数从 1000 降到 10 → 减少 99% 的随机 IO / 本质：把 Server 层的 WHERE 过滤条件 → "下推"到存储引擎层 → 在索引上提前过滤 → 减少回表次数 / EXPLAIN 查看：①`Extra: Using index condition` → 表示使用了 ICP ②`Extra: Using where` → 没有使用 ICP → Server 层过滤 ③`Extra: Using index` → 覆盖索引 → 不需要回表 / 面试重点：ICP = 把 WHERE 条件下推到存储引擎层 → 在联合索引上提前过滤 → 减少回表次数 → EXPLAIN 看 Using index condition）

**追问2：** 那覆盖索引是什么？它和 ICP 是什么关系？有了覆盖索引还需要 ICP 吗？

> 你回答...（提示：覆盖索引 vs ICP / 覆盖索引：①查询的所有列都在索引中 → 不需要回表 → 直接从索引返回数据 ②如 `INDEX(name, age)` → `SELECT name, age FROM t WHERE name LIKE '张%'` → name 和 age 都在索引里 → 不需要回表 → `Extra: Using index` ③回表 = 从二级索引拿到主键 → 再从聚簇索引取完整行 → 覆盖索引跳过了这一步 / 覆盖索引 vs ICP：①覆盖索引 → 彻底不需要回表 → 最优 ②ICP → 还需要回表 → 但减少了回表次数 ③如果查询用了覆盖索引 → 不需要回表 → ICP 没有意义（因为不回表 → 减少回表次数没意义）④如果查询没有用覆盖索引（SELECT * 或有其他列）→ ICP 有意义 → 在索引上提前过滤 → 减少回表 / 实际优化优先级：①覆盖索引 > ICP > 无优化 ②先想能不能用覆盖索引 → `SELECT name, age FROM t WHERE name = '张三'` → INDEX(name, age) → 覆盖索引 → 最优 ③如果必须 SELECT * → 无法覆盖 → 用 ICP → INDEX(name, age) WHERE name LIKE '张%' AND age = 25 → 减少回表 ④如果连联合索引都没有 → 全表扫描 → 优化索引 / 怎么建覆盖索引：①分析 SQL → WHERE 条件 + SELECT 列 + ORDER BY/GROUP BY 列 ②联合索引顺序 → 等值条件在前 → 范围条件在后 → `INDEX(status, name, age)` → WHERE status = 1 AND name LIKE '张%' ③如果 SELECT 的列太多 → 索引太大 → 写入性能差 → 索引列一般不超过 5 个 → 覆盖索引不是万能的 → 要权衡 ④`SELECT *` → 基本无法覆盖 → 所以规范要求避免 SELECT * → 只查需要的列 / 面试重点：覆盖索引=查询列全在索引中不回表(Using index) → ICP=在索引上提前过滤减少回表(Using index condition) → 覆盖索引最优 → 有了覆盖索引ICP无意义 → SELECT*导致无法覆盖）

**追问3：** 你提到 `SELECT *` 无法用覆盖索引。那在实际项目中，你怎么排查和优化慢 SQL？完整的流程是什么？

> 你回答...（提示：慢 SQL 优化完整流程 / 第一步：发现慢 SQL ①开启慢查询日志 → `slow_query_log = ON` → `long_query_time = 1`（超过1秒记录）→ 生产建议 0.5 秒甚至 0.1 秒 ②阿里 Druid / p6spy → 应用层监控 → 慢 SQL 告警 ③SkyWalking / Prometheus → APM → 接口维度的慢查询 ④MySQL 5.7+ → `performance_schema.events_statements_summary_by_digest` → 按SQL指纹聚合 → 找最慢的 / 第二步：EXPLAIN 分析 ①`type` → 访问类型 → ALL(全表扫描)最差 → const(主键等值)最优 → ref > range > index > ALL ②`key` → 实际使用的索引 → NULL 表示没用索引 ③`rows` → 预估扫描行数 → 越少越好 ④`Extra` → `Using index`(覆盖索引好) → `Using where`(Server层过滤) → `Using temporary`(临时表 必须优化) → `Using filesort`(文件排序 必须优化) ⑤`key_len` → 索引使用的字节数 → 判断联合索引用了几个字段 / 第三步：针对性优化 ①没有索引 → 加索引 → 看WHERE条件 → 联合索引顺序（等值在前范围在后）②有索引但没用 → 索引失效 → 隐式类型转换(字符串列传了int) → 函数操作(`WHERE DATE(create_time)=...`) → `!=`/`NOT IN`(可能不走索引) → `OR`(两边都有索引才走) ③回表太多 → 覆盖索引 / ICP → 减少 SELECT 列 ④Using filesort → ORDER BY 的列加索引 → 或调整索引顺序让 ORDER BY 列在索引中 ⑤Using temporary → GROUP BY 的列加索引 ⑥大表分页 → 深分页 `LIMIT 1000000, 10` → 延迟关联 `SELECT * FROM t t1 INNER JOIN (SELECT id FROM t LIMIT 1000000, 10) t2 ON t1.id = t2.id` → 子查询走覆盖索引只取id → 再回表10次 ⑦数据量太大 → 分库分表 → 历史数据归档 / 第四步：验证 ①EXPLAIN → 确认 type/key/rows/Extra 改善 ②实际执行时间 → 对比优化前后 ③`SHOW PROFILE` → 查看各阶段耗时 → System/Executing/Sorting 等 / 结合你的经验：①你简历写了"将批量查询耗时从5分钟优化至1分钟以内"②面试官会追问：5分钟是什么场景？→ 批量查询10万条账户数据 → 每条单独查 → N+1 问题 ③怎么优化 → 批量查 `WHERE id IN (...)` → 一次性查回 → 或分页查（每次1000条）→ 减少 DB 交互次数 ④这是 N+1 经典问题 → MyBatis 里 `<foreach>` + IN → 或用 MyBatis 的 `@ResultMap` 延迟加载 / 面试重点：慢日志发现→EXPLAIN四字段(type/key/rows/Extra)→针对性优化(加索引/覆盖索引/ICP/延迟关联/分库分表)→验证）

---

## 话题三：手写代码 - 最长无重复字符子串（8分钟）

**面试官：写一个函数，给定一个字符串，找出其中不含有重复字符的最长子串的长度。比如 "abcabcbb" 答案是 3（"abc"）。写完说说你的思路。**

你在纸上/白板上写代码...

**追问1：** 先说说你的思路。什么是滑动窗口？为什么不用暴力破解？

> 你回答...（提示：滑动窗口 / 暴力破解 O(n³)：①枚举所有子串 → O(n²) ②对每个子串判断是否有重复字符 → O(n) ③总共 O(n³) → n=10000 → 10^12 → 超时 / 滑动窗口 O(n)：①两个指针 left 和 right → 维护一个窗口 [left, right] → 窗口内没有重复字符 ②right 向右扩展 → 加入新字符 ③如果新字符和窗口内已有字符重复 → left 跳到重复字符上次出现的下一位 → 收缩窗口 ④记录窗口最大长度 / 代码：
```java
public int lengthOfLongestSubstring(String s) {
    Map<Character, Integer> map = new HashMap<>();
    int left = 0, max = 0;
    for (int right = 0; right < s.length(); right++) {
        char c = s.charAt(right);
        if (map.containsKey(c) && map.get(c) >= left) {
            left = map.get(c) + 1;  // 跳到重复字符的下一个位置
        }
        map.put(c, right);  // 更新字符的最新位置
        max = Math.max(max, right - left + 1);
    }
    return max;
}
```
/ 核心逻辑：①HashMap 存每个字符最后出现的位置 → `map.get(c)` = 字符 c 上次出现的下标 ②`map.containsKey(c) && map.get(c) >= left` → 字符出现过 **且** 在当前窗口内 → 重复了 ③`left = map.get(c) + 1` → left 跳到重复字符的下一位 → 窗口收缩 → 去掉了重复字符 ④`map.get(c) >= left` 这个条件很关键 → 如果字符上次出现在 left 之前 → 不在窗口内 → 不算重复 → 不需要移动 left / 为什么 `map.get(c) >= left` 这个判断必要：①比如 "abba" → right=2 遇到第二个 'b' → left 跳到 2（第一个 b 的下一位）→ right=3 遇到 'a' → map.get('a') = 0 → 但 0 < left(2) → 'a' 上次出现在窗口之前 → 不在当前窗口 → 不算重复 → left 不动 ②如果没有这个判断 → left 会倒退 → 从 2 回到 1 → 窗口变大 → 但中间可能有其他重复 → 结果错误 / 时间复杂度 O(n) → right 只增不减 → 最多遍历 n 次 / 空间复杂度 O(min(m, n)) → m 是字符集大小 → 如果是 ASCII → 最多 128 个 → 如果是 Unicode → 最多 n 个）

**追问2：** 如果字符集已知是 ASCII（128个字符），你能优化吗？

> 你回答...（提示：用数组替代 HashMap / 优化：
```java
public int lengthOfLongestSubstring(String s) {
    int[] index = new int[128];  // ASCII 128个字符
    Arrays.fill(index, -1);  // 初始化为 -1 表示未出现
    int left = 0, max = 0;
    for (int right = 0; right < s.length(); right++) {
        char c = s.charAt(right);
        if (index[c] >= left) {
            left = index[c] + 1;
        }
        index[c] = right;
        max = Math.max(max, right - left + 1);
    }
    return max;
}
```
/ 为什么数组更快：①数组访问是 O(1) → 直接下标 → 比 HashMap 的 hash + equals 快 ②没有装箱拆箱 → char 直接转 int 当下标 → HashMap 的 key 是 Character → 装箱开销 ③没有扩容 → 数组固定大小 128 → HashMap 有扩容和 rehash / 如果是 Unicode → 用 HashMap → 因为 Unicode 字符太多 → 数组太大 / 面试重点：ASCII用int[128]数组替代HashMap → O(1)访问无装箱开销 → Unicode用HashMap）

**追问3：** 滑动窗口这个思想还能解决什么问题？举几个例子。

> 你回答...（提示：滑动窗口应用场景 / 滑动窗口适用场景：①连续子数组/子串问题 → 满足某种条件的最长/最短/恰好K个 ②核心思想 → 维护窗口 [left, right] → right 扩展探索 → left 收缩满足条件 ③"找最长" → right 扩展 → 不满足时收缩 left → 记录最大 / 常见题型：①无重复字符的最长子串 → 本题 → 窗口内无重复 → right 遇到重复收缩 left ②最小覆盖子串 → 给你 s 和 t → 找 s 中包含 t 所有字符的最短子串 → 窗口扩展直到包含所有字符 → 再收缩 left 找最短 ③长度最小的子数组 → 正整数数组 → 和 ≥ target 的最短子数组 → 窗口扩展 → 和超过 target → 收缩 left ④水果成篮 → 最多两种字符的最长子串 → 窗口内最多2种字符 → 超过收缩 left ⑤最多K个不同字符的最长子串 → 同上 → K 种 ⑥替换后的最长重复子串 → 可以替换K个字符 → 找最长全相同子串 / 模板：
```java
// 滑动窗口通用模板
int left = 0, result = 0;
Map<Character, Integer> window = new HashMap<>();
for (int right = 0; right < s.length(); right++) {
    char c = s.charAt(right);
    // 1. right 扩展 → 加入窗口
    window.put(c, window.getOrDefault(c, 0) + 1);
    // 2. 不满足条件时 → 收缩 left
    while (不满足条件) {
        char d = s.charAt(left);
        window.put(d, window.get(d) - 1);
        if (window.get(d) == 0) window.remove(d);
        left++;
    }
    // 3. 更新结果
    result = Math.max(result, right - left + 1);
}
```
/ 核心区别：①"找最长" → 先扩展再收缩 → while 不满足时收缩 → 收缩后更新结果 ②"找最短" → 先扩展直到满足 → 再收缩到不满足为止 → 收缩前更新结果 ③这就是为什么"找最长"和"找最短"的代码位置不同 / 面试重点：滑动窗口=连续子串/子数组问题 → right扩展left收缩 → 找最长先扩展后收缩 → 找最短先满足再收缩）

---

## 话题四：Spring MVC DispatcherServlet 请求处理流程（12分钟）

**面试官：你用 Spring Boot 写接口。一个 HTTP 请求从浏览器发出来，到你的 Controller 方法执行完返回 JSON，中间经过了哪些步骤？DispatcherServlet 你了解吗？**

> 你回答...

**追问1：** 先说说 DispatcherServlet 的核心组件有哪些？请求是怎么流转的？

> 你回答...（提示：Spring MVC 请求处理流程 / DispatcherServlet = Front Controller 模式 → 所有请求的统一入口 / 核心组件：①`DispatcherServlet` → 前端控制器 → 接收所有请求 → 分发 ②`HandlerMapping` → 处理器映射 → 根据 URL 找到对应的 Controller 方法 → `RequestMappingHandlerMapping` 解析 `@RequestMapping` ③`HandlerAdapter` → 处理器适配器 → 调用 Controller 方法 → `RequestMappingHandlerAdapter` 处理 `@RequestMapping` 方法 → 负责参数解析和返回值处理 ④`HandlerInterceptor` → 拦截器 → preHandle/postHandle/afterCompletion ⑤`HandlerExceptionResolver` → 异常解析器 → 处理 Controller 抛出的异常 ⑥`ViewResolver` → 视图解析器 → 如果返回视图名 → 解析成 View 对象 ⑦`HttpMessageConverter` → 消息转换器 → `@RequestBody` 反序列化 / `@ResponseBody` 序列化 → Jackson 的 `MappingJackson2HttpMessageConverter` / 请求处理流程（9步）：①请求到达 → `DispatcherServlet.doService()` → 调用 `doDispatch()` ②`doDispatch()` → `getHandler()` → 遍历所有 `HandlerMapping` → 根据 URL 找到 `HandlerExecutionChain`（Controller 方法 + 拦截器链）③`getHandlerAdapter()` → 根据 Handler 类型找到对应的 `HandlerAdapter` ④拦截器 `preHandle()` → 返回 false → 直接返回 → 不执行 Controller ⑤`HandlerAdapter.handle()` → 调用 Controller 方法 → ⑥参数解析 → `@RequestBody` → `RequestResponseBodyMethodProcessor` → Jackson 反序列化 JSON → Java 对象 ⑦Controller 方法执行 → 返回值 ⑧返回值处理 → `@ResponseBody` → `RequestResponseBodyMethodProcessor` → Jackson 序列化 Java 对象 → JSON → 写入 Response ⑨拦截器 `postHandle()` → `afterCompletion()` / 关键细节：①`@RequestBody` 和 `@ResponseBody` 是通过 `HttpMessageConverter` 实现的 → 不是 Spring MVC 的 view 机制 → 而是 RESTful 方式 → 直接写 JSON 到响应体 ②如果方法返回 String（视图名）→ 走 `ViewResolver` → 渲染 HTML → 前后端分离基本不用了 ③`@RestController = @Controller + @ResponseBody` → 类级别 → 所有方法都返回 JSON / 面试重点：DispatcherServlet=前端控制器 → HandlerMapping找Controller → HandlerAdapter调Controller → 参数解析(@RequestBody→Jackson反序列化) → 返回值处理(@ResponseBody→Jackson序列化) → 拦截器前后包裹）

**追问2：** `@RequestBody` 底层是怎么把 JSON 转成 Java 对象的？这个过程中参数校验（`@Valid`）是在哪一步发生的？

> 你回答...（提示：@RequestBody 原理 + @Valid / @RequestBody 原理：①`HandlerAdapter` 找到参数解析器 → `RequestResponseBodyMethodProcessor`（实现了 `HandlerMethodArgumentResolver`）②`resolveArgument()` → 从请求体读取 InputStream → 调用 `HttpMessageConverter.read()` ③遍历所有 `HttpMessageConverter` → 找到能处理的 → `MappingJackson2HttpMessageConverter`（Jackson）→ `ObjectMapper.readValue(inputStream, parameterType)` → JSON → Java 对象 ④Spring Boot 默认注册了多个 converter → ByteArray/String/Resource/Form/Jackson → 按顺序匹配 → `Content-Type: application/json` → 匹配 Jackson ⑤如果 JSON 格式错误 → `HttpMessageNotReadableException` → 被 `HandlerExceptionResolver` 捕获 → 返回 400 / @Valid 的位置：①`@Valid` 在参数解析**之后** → 对象已经反序列化好了 → 再做校验 ②`RequestResponseBodyMethodProcessor.validate()` → 如果参数有 `@Valid` 或 `@Validated` → 调用 `Validator.validate()` ③Hibernate Validator → 执行校验 → `@NotNull` / `@NotBlank` / `@Size` / `@Pattern` / `@Min` / `@Max` ④校验失败 → `MethodArgumentNotValidException` → 全局异常处理 → 返回 400 + 错误信息 / 执行顺序：①JSON → Java 对象（反序列化）②@Valid 校验（字段级）③Controller 方法执行 ④如果校验失败 → 不执行 Controller → 直接返回 400 / 嵌套校验：①`@Valid` 可以嵌套 → 对象A里有对象B → A 的 B 字段加 `@Valid` → 递归校验 B ②如 `Order { @Valid Customer customer; }` → 校验 Order 时也会校验 Customer / 面试重点：@RequestBody=RequestResponseBodyMethodProcessor→Jackson反序列化JSON→Java对象 → @Valid在反序列化之后校验 → 校验失败MethodArgumentNotValidException→全局异常处理返回400）

**追问3：** 如果 Controller 方法抛出了一个异常，Spring MVC 是怎么处理的？`@ExceptionHandler` 是怎么生效的？

> 你回答...（提示：Spring MVC 异常处理流程 / 异常处理流程：①Controller 方法抛出异常 ②`DispatcherServlet` 的 `doDispatch()` 中 catch → `processDispatchResult()` → 调用 `HandlerExceptionResolver` ③Spring Boot 默认注册了多个 resolver → 优先级：`ExceptionHandlerExceptionResolver`（处理 @ExceptionHandler）→ `ResponseStatusExceptionResolver`（处理 @ResponseStatus）→ `DefaultHandlerExceptionResolver`（Spring 内置异常）④`ExceptionHandlerExceptionResolver` → 在 `@RestControllerAdvice` 标注的类中 → 找匹配的 `@ExceptionHandler` 方法 ⑤找到 → 执行 `@ExceptionHandler` 方法 → 返回自定义响应 ⑥没找到 → 交给下一个 resolver ⑦都没处理 → Spring Boot 的默认错误页 → `/error` → `BasicErrorController` → 返回默认 JSON / @ExceptionHandler 原理：①`@RestControllerAdvice` → Spring 启动时扫描 → 注册到 `ExceptionHandlerExceptionResolver` 的 `ExceptionHandlerMethod` 缓存 ②异常发生时 → 按异常类型匹配 → 优先匹配最精确的类型 → `BizException` 优先于 `RuntimeException` 优先于 `Exception` ③匹配到 → 反射调用 `@ExceptionHandler` 方法 → 返回值走 `@ResponseBody` → JSON 响应 / 典型全局异常处理：
```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(BizException.class)
    public Result handleBiz(BizException e) {
        return Result.fail(e.getCode(), e.getMessage());  // 400
    }

    @ExceptionHandler(Exception.class)
    public Result handleException(Exception e) {
        log.error("系统异常", e);
        return Result.fail("SYSTEM_ERROR", "系统繁忙");  // 500
    }
}
```
/ 异常匹配规则：①精确匹配优先 → 抛 `BizException` → 找到 `@ExceptionHandler(BizException.class)` → 不找父类 ②如果没有精确匹配 → 找父类 → `@ExceptionHandler(RuntimeException.class)` → 如果还没有 → `@ExceptionHandler(Exception.class)` ③所以兜底的 `@ExceptionHandler(Exception.class)` 一定要有 → 防止异常泄漏到用户端 / @ControllerAdvice vs @RestControllerAdvice：①`@ControllerAdvice` → 返回视图 → 需要 `@ResponseBody` ②`@RestControllerAdvice` = `@ControllerAdvice + @ResponseBody` → 直接返回 JSON → 前后端分离用这个 / 面试重点：异常→DispatcherServlet→HandlerExceptionResolver→ExceptionHandlerExceptionResolver找@RestControllerAdvice里的@ExceptionHandler→精确匹配优先→返回JSON→兜底Exception.class必须要有）

---

## 话题五：Redis 大Key/热Key/慢查询排查实战（12分钟）

**面试官：你做金融系统，Redis 用得多。生产环境 Redis 出现大 Key 和热 Key 你遇到过吗？怎么排查和解决？**

> 你回答...

**追问1：** 先说说什么是大 Key？多大的 Key 算大？大 Key 会带来什么问题？

> 你回答...（提示：大 Key 问题 / 大 Key 定义：①String 类型 → 单个 value > 10KB（有些标准是 1MB）②Hash/List/Set/ZSet → 元素数量 > 5000（或总大小 > 10MB）③没有绝对标准 → 取决于业务场景和 Redis 配置 → 但一般 10KB 以上就要关注 / 大 Key 的危害：①内存不均 → Redis Cluster → 16384 个 slot → 大 Key 落在一个 slot → 单节点内存远超其他节点 → 水平扩展失效 ②删除阻塞 → `DEL` 大 Key → Redis 单线程 → 删除一个百万元素的 Hash → 耗时几百毫秒 → 期间所有请求阻塞 → 类似 STW ③网络带宽 → 读取大 Key → 一次传输几 MB → 占满带宽 → 其他请求变慢 ④过期阻塞 → 大 Key 设置了过期时间 → 过期时触发删除 → 同步删除阻塞 ⑤持久化阻塞 → BGSAVE/AOF rewrite → fork 子进程 → 大 Key 导致 COW 大量内存页 → 内存翻倍 ⑥缓存雪崩 → 大 Key 过期 → 大量请求同时回源 DB → DB 瞬间压力 / 排查方法：①`redis-cli --bigkeys` → 扫描所有 Key → 按类型统计最大的 → 但只能看 top → 不能看全部 ②`MEMORY USAGE key` → 查看单个 Key 的内存占用 → 精确 ③`SCAN` + `DEBUG OBJECT key` → SCAN 遍历 + 逐个查看 → 适合自定义脚本 ④RDB 离线分析 → `rdb-tools` → 解析 RDB 文件 → 分析大 Key → 不影响线上 ⑤云厂商监控 → 阿里云 Redis → 控制台 → 大 Key 分析 / 解决方案：①拆分 → 大 Hash → 按 field 分桶 → `user:1000:info` → `user:1000:info:basic` + `user:1000:info:detail` → 分散到多个 Key ②压缩 → value 用 JSON → 考虑 Protobuf/Snappy 压缩 → 减小体积 ③异步删除 → `UNLINK` 替代 `DEL` → Redis 4.0+ → 异步删除 → 不阻塞主线程 → 大 Key 专用 ④Lazy Free → `lazyfree-lazy-expire yes` → 过期 Key 异步删除 → `lazyfree-lazy-eviction yes` → 淘汰 Key 异步删除 ⑤业务层面 → 不往 Redis 存大对象 → 如果必须存 → 设置合理的 TTL → 定期清理 → 不要让 Key 无限增长 / 结合你的经验：①营销活动平台 → 活动配置缓存 → 活动规则多 → 一个 Hash 存了整个活动配置 → 5000+ field → 大 Key ②解决 → 按模块拆分 → `activity:1000:basic` + `activity:1000:rules` + `activity:1000:prizes` → 每个 Hash 几百个 field ③监控 → 定期用 `redis-cli --bigkeys` 扫描 → 大于阈值告警 / 面试重点：大Key=String>10KB/集合>5000元素 → 危害：内存不均/删除阻塞/网络带宽 → 排查：--bigkeys/MEMORY USAGE/SCAN → 解决：拆分分桶/UNLINK异步删除/Lazy Free）

**追问2：** 热 Key 呢？什么是热 Key？怎么排查？怎么解决？

> 你回答...（提示：热 Key 问题 / 热 Key 定义：①某个 Key 的访问 QPS 极高 → 远超其他 Key → 单 Key QPS > 1万就要关注 ②常见热 Key → 热门商品详情/热门活动配置/首页数据/实时排行榜 ③本质 → 访问集中在少数 Key → Redis Cluster 单节点 CPU 打满 → 其他节点空闲 / 热 Key 的危害：①单节点 CPU 瓶颈 → Redis 单线程 → 热 Key 的所有命令都在一个节点执行 → CPU 100% → 响应变慢 → 其他正常 Key 也受影响 ②网络带宽打满 → 大量请求集中到一个节点 ③Cluster 热点 → 一个节点过载 → 整个集群性能下降 / 排查方法：①`redis-cli --hotkeys` → 需要 `maxmemory-policy = allkeys-lfu` → LFU 模式记录访问频率 → 返回最热 Key ②`MONITOR` → 实时输出所有命令 → 生产慎用 → 会严重影响性能 → 只在测试环境用 ③代理层统计 → Codis/Twemproxy → 代理层记录每个 Key 的访问次数 ④业务日志 → 应用层 → 在代码里统计 Key 访问 → 上报到 Prometheus ⑤网络抓包 → tcpdump → 分析 Redis 协议 → 统计 Key 访问频率 / 解决方案：①本地缓存 → Caffeine/Guava Cache → 应用层缓存热 Key → 设置短 TTL（如 5 秒）→ 大部分请求不走 Redis → 直接从本地内存读 ②读副本 → Redis Cluster → 读从节点 → `READONLY` → 分散读压力 → 但写还是走主节点 ③拆分 Key → 热 Key → `hotkey_1` / `hotkey_2` / ... / `hotkey_N` → 随机选一个读 → 分散到不同 slot → 不同节点 ④限流 → 热 Key 的请求限流 → 超过阈值 → 返回降级数据 → 保护 Redis / 本地缓存方案（最常用）：①Caffeine → 高性能本地缓存 → 写后读延迟 < 100ns → 比 Redis 快 1000 倍 ②问题 → 本地缓存和 Redis 不一致 → 解决：短 TTL（5-10秒）+ Redis 发布/订阅通知失效 ③实现 → `Caffeine.newBuilder().expireAfterWrite(5, TimeUnit.SECONDS).maximumSize(1000).build()` → 只缓存热 Key ④适合 → 配置类数据 → 短时间不一致可接受 → 如活动配置/商品基本信息 / 结合你的经验：①营销活动 → 某活动突发流量 → 活动配置 Key QPS 10万 → 单节点 CPU 打满 ②解决 → Caffeine 本地缓存 5 秒 TTL → 90% 请求走本地 → Redis QPS 降到 1 万 → 正常 ③监控 → 应用层上报 Key 访问到 Prometheus → 超过阈值告警 / 面试重点：热Key=单Key高QPS → 危害：单节点CPU瓶颈 → 排查：--hotkeys(LFU)/代理层统计 → 解决：Caffeine本地缓存(最常用短TTL)/读副本/Key拆分随机读/限流降级）

**追问3：** 慢查询呢？Redis 的慢查询日志怎么看？怎么排查慢查询的原因？

> 你回答...（提示：Redis 慢查询 / Redis 慢查询日志：①`slowlog-log-slower-than` → 阈值 → 微秒 → 默认 10000（10ms）→ 生产建议设 5000（5ms）甚至 1000（1ms）②`slowlog-max-len` → 最多存多少条慢查询 → 默认 128 → 生产建议 1000 ③`SLOWLOG GET 10` → 获取最近 10 条慢查询 ④`SLOWLOG LEN` → 当前慢查询数量 ⑤`SLOWLOG RESET` → 清空慢查询日志 / 慢查询条目格式：①id → 唯一标识 ②timestamp → 发生时间戳 ③duration → 耗时（微秒）④command → 具体命令和参数 ⑤client_ip:port → 客户端地址 ⑥client_name → 客户端名称 / 常见慢查询原因：①`KEYS *` → 遍历所有 Key → O(n) → 生产禁用 → 用 `SCAN` 替代 ②`HGETALL` 大 Hash → 百万元素 → O(n) → 用 `HSCAN` ③`SMEMBERS` 大 Set → 同上 → 用 `SSCAN` ④`SORT` → 对大集合排序 → O(n + n log n) → 避免在 Redis 排序 ⑤`LRANGE 0 -1` 大 List → 返回所有元素 → O(n) → 分页查 ⑥`FLUSHALL` / `FLUSHDB` → 清空所有 → 阻塞 → 生产禁用 ⑦大 Key 的 DEL → 前面说过 → 用 UNLINK ⑧Lua 脚本太长 → 单线程执行 → 阻塞 / 排查流程：①SLOWLOG GET → 找到慢命令 ②看 command → 是什么命令 → 操作的什么 Key ③分析原因 → 是否大 Key / 复杂命令 / 不该用 Redis 做的操作 ④优化 → 替换命令（KEYS→SCAN）/ 拆分大 Key / 用 UNLINK / 分页 / 异步 / 监控告警：①Prometheus + redis_exporter → 采集慢查询指标 → 超过阈值告警 ②阿里云 Redis → 控制台 → 慢查询分析 → 自动告警 / 和大 Key 的关系：①大 Key 是慢查询的主要原因之一 → `HGETALL` 大 Hash → 慢查询 → 排查时先看是不是大 Key ②解决大 Key → 慢查询自然减少 / 面试重点：SLOWLOG GET看慢查询 → 常见原因：KEYS*/HGETALL大Hash/SORT/大Key DEL → 解决：SCAN替代KEYS/HSCAN替代HGETALL/UNLINK替代DEL/分页）

---

# 二面（30分钟）

## 话题六：Java ForkJoinPool 工作窃取算法（10分钟）

**面试官：你前面提到过 parallelStream。它的底层用的是 ForkJoinPool。工作窃取（Work Stealing）算法你了解吗？为什么不用普通线程池？**

> 你回答...

**追问1：** 先说说 ForkJoinPool 和普通 ThreadPoolExecutor 有什么区别？它适合什么场景？

> 你回答...（提示：ForkJoinPool vs ThreadPoolExecutor / 普通 ThreadPoolExecutor：①所有线程共享一个工作队列 → 生产者往队列放任务 → 空闲线程从队列取任务执行 ②问题 → 高并发下 → 多个线程竞争同一个队列 → 需要加锁 → 竞争激烈 → 吞吐量下降 ③适合 → 独立的、大小相近的任务 → 如 HTTP 请求处理 → 每个任务独立 → 执行时间相近 / ForkJoinPool：①每个线程有自己的工作队列（双端队列 Deque）→ 线程只操作自己的队列 → 不竞争 ②大任务 → fork → 拆成子任务 → 放到自己队列的头部（LIFO）③自己忙不过来 → 其他空闲线程 → 从队列尾部偷任务（FIFO）→ 工作窃取 ④因为自己从头部操作 → 偷的人从尾部偷 → 减少竞争 → 几乎不需要加锁 / 工作窃取的核心设计：①自己 push/pop 从 Deque 的一端（头部）→ LIFO → 最近的大任务先执行 → 递归拆分 ②偷的人从 Deque 的另一端（尾部）偷 → FIFO → 偷走的是最早的小任务 → 小任务执行快 → 偷的人很快就能完成 ③双端队列 → 两端操作 → 减少竞争 → 这就是为什么用 Deque 而不是普通 Queue ④窃取是被动触发 → 线程空闲时 → 随机选一个线程的队列 → 从尾部偷 → 如果没偷到 → 换一个线程偷 / 为什么 LIFO（自己）+ FIFO（偷的人）：①自己 push 大任务 → 立刻 pop 大任务 → 继续拆分 → 递归 → 深度优先 → 大任务先拆完 → 子任务快速完成 ②偷的人从尾部 → 拿到的是最早 push 的小任务 → 已拆好的 → 执行快 → 不用再拆 → 快速消化 ③如果自己也是 FIFO → 先 push 大任务 → 先拿大任务 → 但大任务要继续拆 → 而小任务在后面 → 拿不到 → 不如拿大任务先拆 / 适合场景：①分治任务 → 大任务可以拆成小任务 → 如归并排序/快速排序/矩阵乘法/大数组求和 ②RecursiveTask（有返回值）→ `compute()` 返回结果 → fork/join 合并 ③RecursiveAction（无返回值）→ `compute()` 无返回 → 如并行遍历处理 ④parallelStream → 底层用 ForkJoinPool.commonPool() → 对集合做并行操作 → filter/map/reduce / 不适合场景：①IO 密集型 → 任务执行时间长 → 阻塞线程 → 工作线程被占住 → 窃取没意义 → 因为大家都阻塞了 → 没人偷 ②独立任务 → 不需要拆分 → 用普通线程池更简单 ③任务执行时间差异大 → 长任务阻塞线程 → 短任务快速完成 → 负载不均 / 面试重点：ThreadPoolExecutor=共享队列竞争 → ForkJoinPool=每线程自己的双端队列+工作窃取 → 自己LIFO大任务先拆 → 偷的人FIFO小任务先执行 → 减少竞争 → 适合分治/CPU密集型）

**追问2：** parallelStream 的 commonPool 有什么坑？你在实际项目中遇到过吗？

> 你回答...（提示：parallelStream 的坑 / 坑一：共享 commonPool ①所有 parallelStream 共用 `ForkJoinPool.commonPool()` → 并行度 = CPU 核数（Runtime.availableProcessors()）②如果有人在 parallelStream 里执行阻塞操作（IO/Thread.sleep/远程调用）→ 占住 commonPool 的线程 → 其他 parallelStream 全部受影响 → 性能下降 ③示例 → 线程A 在 parallelStream 里调 HTTP 接口 → 8核CPU → 8个 commonPool 线程全在等 HTTP → 线程B 的 parallelStream → 没线程可用 → 串行执行 / 坑二：顺序不确定 ①parallelStream 是并行执行 → 元素处理顺序不确定 ②如果操作有状态依赖 → 如 `forEach` 里修改共享变量 → 线程安全问题 ③`forEach` 不能保证顺序 → 需要顺序用 `forEachOrdered` → 但 `forEachOrdered` 会失去并行优势 / 坑三：collect 线程不安全 ①`.collect(Collectors.toList())` → 底层用 ArrayList → 并行时多个线程往同一个 ArrayList 添加 → 不是线程安全的 ②但 Java 做了优化 → 并行流用 `collect` → 每个线程先收集到自己的容器 → 最后合并（combiner）→ 所以 `toList()` 是安全的 ③但如果用 `Collectors.toMap()` → 重复 key → 并行时可能抛 `IllegalStateException: Duplicate key` → 需要指定 merge function / 坑四：适合的数据量 ①数据量小 → 拆分和线程切换的开销 > 并行收益 → 反而更慢 ②一般 > 1万元素才考虑并行 → 但也要看任务复杂度 → 简单操作不值得并行 / 坑五：自定义 ForkJoinPool ①如果必须用 parallelStream 且有阻塞操作 → 自己创建 ForkJoinPool → 提交任务 → 不影响 commonPool ②`ForkJoinPool customPool = new ForkJoinPool(4); customPool.submit(() -> list.parallelStream().map(...).collect(...)).get()` ③但要注意 → parallelStream 内部还是用 commonPool → 除非通过 trick 让自定义池执行 / 实际经验：①营销系统 → 大批量用户数据过滤 → 10万条 → parallelStream.map() → 快了 3 倍 ②坑 → 有人在里面调了远程接口 → 阻塞 → 其他 parallelStream 变慢 → 排查半天 ③解决 → 拆成两步 → 先 parallelStream 做CPU计算 → 再普通线程池做异步IO / 面试重点：parallelStream共用commonPool → 阻塞操作影响所有parallelStream → 顺序不确定 → collect有combiner安全但toMap要指定merge → 数据量小不值得并行 → 阻塞操作要自定义ForkJoinPool）

**追问3：** ForkJoinPool 的 fork 和 join 是怎么配合的？写一个简单的并行求和示例。

> 你回答...（提示：fork/join 示例 / 并行求和：
```java
class SumTask extends RecursiveTask<Long> {
    private long[] array;
    private int start, end;
    private static final int THRESHOLD = 10000;  // 阈值

    SumTask(long[] array, int start, int end) {
        this.array = array;
        this.start = start;
        this.end = end;
    }

    @Override
    protected Long compute() {
        // 任务足够小 → 直接计算
        if (end - start <= THRESHOLD) {
            long sum = 0;
            for (int i = start; i < end; i++) {
                sum += array[i];
            }
            return sum;
        }
        // 任务大 → 拆分
        int mid = (start + end) >>> 1;
        SumTask left = new SumTask(array, start, mid);
        SumTask right = new SumTask(array, mid, end);
        // fork → 放入当前线程的工作队列 → 异步执行
        left.fork();   // 异步执行左半部分
        // right 直接 compute → 当前线程执行右半部分 → 不fork
        // 这样当前线程不闲着 → 一边等左边 → 一边执行右边
        Long rightResult = right.compute();  // 同步执行
        Long leftResult = left.join();       // 等待左边完成
        return leftResult + rightResult;
    }
}

// 使用
ForkJoinPool pool = new ForkJoinPool();
long[] array = new long[1000000];
// ... 填充数据
SumTask task = new SumTask(array, 0, array.length);
Long result = pool.invoke(task);
```
/ 关键点：①`fork()` → 把子任务放入当前线程的工作队列 → 异步执行 → 不阻塞 ②`join()` → 等待子任务完成 → 返回结果 → 如果子任务还没被偷 → 当前线程自己执行 ③优化技巧 → `left.fork()` + `right.compute()` → 不是 `left.fork()` + `right.fork()` → 因为 fork 后要 join → 如果两个都 fork → 当前线程闲着等两个 → 浪费 → 一个 fork 一个 compute → 当前线程执行一个 → 另一个被偷走或自己执行 → 充分利用 ④THRESHOLD → 任务小到直接算 → 不再拆分 → 避免过度拆分 → 拆分本身有开销 / fork/join 配合原理：①`fork()` → 把任务 push 到当前线程 Deque 的头部 → 不阻塞 → 当前线程继续执行 ②`join()` → 检查子任务是否完成 → 完成直接返回 → 没完成 → 当前线程不空等 → 从自己 Deque 头部 pop 另一个任务执行（帮助其他任务）→ 直到子任务完成 ③如果当前线程 Deque 空了 → 去偷别的线程的任务 → 一直工作不闲着 ④这就是 ForkJoinPool 高效的原因 → 线程不阻塞等待 → 有活干活 / 面试重点：fork=放入自己队列头部异步 → join=等待结果但不空等(帮助其他任务) → 优化:left.fork()+right.compute()不两个都fork → THRESHOLD阈值防过度拆分）

---

## 话题七：核心设计题 - 统一支付网关设计（20分钟）

**面试官：最后做一个系统设计题。假设你要设计一个统一支付网关，对接微信、支付宝、银联等多个支付渠道。商户通过你的网关发起支付请求，网关路由到合适的渠道完成支付，再异步通知商户支付结果。你怎么设计？**

> 你回答...

**追问1：** 先说说整体架构。你的支付网关需要哪些核心模块？

> 你回答...（提示：统一支付网关架构 / 整体架构分层：①接入层 → 接收商户请求 → 验签 → 幂等校验 → 限流 ②路由层 → 根据规则选择支付渠道 → 优先级/费率/可用性/限额 ③渠道适配层 → 每个渠道一个 Adapter → 统一接口 → 屏蔽渠道差异 ④核心服务层 → 创建支付订单 → 调用渠道 → 处理支付结果 ⑤异步通知层 → 接收渠道异步回调 → MQ → 通知商户 ⑥对账层 → T+1 下载渠道对账文件 → 逐笔核对 → 差异处理 / 核心模块：①`PayGatewayController` → 统一下单接口 → `/api/pay/create` ②`RouteService` → 路由选择 → 输入：金额/币种/商户配置 → 输出：渠道 ③`ChannelAdapter` → 统一接口 → `createPayment(PayRequest)` → `queryPayment(PayQuery)` → `refund(RefundRequest)` ④`WechatAdapter implements ChannelAdapter` → 调微信支付API → 签名/验签/格式转换 ⑤`AlipayAdapter implements ChannelAdapter` → 调支付宝API ⑥`UnionPayAdapter implements ChannelAdapter` → 调银联API ⑦`PayOrderService` → 创建支付订单 → 记录流水 → 状态管理 ⑧`NotifyService` → 异步通知商户 → MQ → 重试机制 ⑨`ReconcileService` → T+1 对账 → 差异处理 / 请求流程：①商户 → POST /api/pay/create → 请求体：商户号/订单号/金额/币种/回调URL ②接入层 → 验签（商户公钥验签）→ 幂等（订单号+商户号去重）→ 限流（令牌桶） ③路由层 → 根据金额/商户配置/渠道可用性 → 选微信 ④渠道适配 → WechatAdapter → 调微信下单API → 微信返回预支付ID ⑤核心服务 → 创建支付订单（status=待支付）→ 返回预支付信息给商户 ⑥用户 → 在微信完成支付 → 微信异步回调网关 → `/api/pay/notify/wechat` ⑦渠道适配 → 验签（微信公钥验签）→ 解析支付结果 → 更新订单状态（status=已支付） ⑧异步通知 → 发MQ → NotifyService 消费 → 通知商户 → 商户返回SUCCESS → 完成 ⑨如果商户没返回SUCCESS → 重试（1min/5min/10min/30min/1h/2h/...共8次）→ 超过次数 → 告警 / 渠道适配层设计要点：①统一接口 → `ChannelAdapter` → 每个渠道实现 → 新增渠道只需新增 Adapter → 开闭原则 ②签名/验签 → 每个渠道算法不同 → 微信用 HMAC-SHA256 → 支付宝用 RSA2 → 银联用 SHA256 → 在各自 Adapter 内处理 ③请求格式 → 微信用 XML（新版本JSON）→ 支付宝用 JSON → 银联用 ISO8583 → Adapter 做格式转换 ④错误码映射 → 每个渠道的错误码不同 → Adapter 映射成统一错误码 / 面试重点：接入层(验签/幂等/限流) → 路由层(选渠道) → 渠道适配层(Adapter统一接口/签名验签/格式转换) → 核心服务(订单/流水/状态) → 异步通知(MQ+重试) → 对账(T+1)）

**追问2：** 幂等你怎么保证？如果用户重复点击支付按钮，或者网络重试，怎么防止重复扣款？

> 你回答...（提示：支付幂等设计 / 幂等的必要性：①用户重复点击 → 连续提交两次 → 不能扣两次 ②网络重试 → 超时重试 → 不能重复处理 ③渠道回调 → 微信可能重复通知 → 不能重复更新 / 幂等方案：①请求级幂等 → 商户请求带 `requestId`（唯一流水号）→ 网关收到 → 先查 Redis `SET requestId NX EX 86400`（24小时）→ 设置成功 → 首次请求 → 处理 → 设置失败 → 重复请求 → 返回上次的结果 ②订单级幂等 → 商户订单号 + 商户号 → 唯一约束 → DB 层面保证 → 同一个订单号只能创建一笔支付 ③状态机幂等 → 支付订单有状态 → 待支付 → 已支付 → 已关闭 → 只有"待支付"状态才能发起支付 → 如果已经"已支付"→ 直接返回已支付的结果 → 不再调渠道 ④回调幂等 → 渠道异步通知 → 先查订单状态 → 如果已经"已支付"→ 直接返回 SUCCESS → 不再更新 / 幂等实现细节：①Redis SETNX → `SET requestId value NX EX 86400` → 原子操作 → 成功=首次 → 失败=重复 ②首次请求 → 处理 → 把结果存 Redis → `SET requestId:result {"status":"success","payUrl":"..."}` ③重复请求 → 从 Redis 取上次结果 → 直接返回 → 不再处理 ④Redis 过期 → 24小时 → 24小时内的重复请求都能幂等 → 超过24小时 → 视为新请求 ⑤DB 兜底 → 即使 Redis 挂了 → DB 的唯一约束（merchant_no + out_trade_no）也能防止重复创建 / 分布式幂等的边界：①Redis SETNX → 并发两个请求同时到 → Redis 单线程 → 只有一个成功 → 保证幂等 ②但 Redis 和 DB 不在同一个事务 → 如果 Redis 成功 → DB 失败 → Redis 已标记 → 请求返回失败 → 用户重试 → Redis 拒绝 → 死锁 ③解决 → 如果 DB 失败 → 删除 Redis 的标记 → `DEL requestId` → 让用户可以重试 ④或者 → Redis 设短 TTL（如 30秒）→ 30秒内重复请求幂等 → 30秒后可以重试 → 但 30 秒内不能重试 → 对用户来说可接受 / 结合你的经验：①营销活动 → 用户领券 → 并发点击 → 幂等 → Redis SETNX + DB唯一约束 → 双重保证 ②支付场景比营销更严格 → 幂等必须做到100% → Redis + DB + 状态机 三重保证 / 面试重点：幂等=Redis SETNX(请求级) + DB唯一约束(订单级) + 状态机(只有待支付才能发起) + 回调幂等(查状态已支付直接返回) → DB失败要删Redis标记防死锁）

**追问3：** 路由策略怎么设计？什么情况下切渠道？比如微信挂了怎么办？

> 你回答...（提示：支付路由策略 / 路由规则（按优先级）：①商户配置 → 商户签约了哪些渠道 → 只能路由到已签约的渠道 ②渠道限额 → 微信单笔限额 5万 → 支付宝 5万 → 如果金额 > 5万 → 路由到银联 ③费率 → 微信 0.6% → 支付宝 0.55% → 优先选费率低的 → 但商户可能指定渠道 ④渠道可用性 → 健康检查 → 微信不可用 → 路由到支付宝 ⑤优先级 → 商户配置优先级 → 微信优先 → 微信不可用 → 支付宝 → 都不可用 → 返回"暂无可用渠道" / 渠道健康检查：①主动探测 → 每隔 30 秒 → 调渠道的 health check 接口 → 超时/失败 → 标记不可用 ②被动统计 → 滑动窗口统计 → 最近 1 分钟渠道的成功率 → 低于阈值（如 95%）→ 降级 ③熔断 → Sentinel → 渠道接口的调用 → 错误率 > 50% → 熔断 30 秒 → 半开探测 → 成功恢复 → 失败继续熔断 / 微信挂了的处理：①熔断器检测到微信不可用 → 标记微信为"不可用" ②路由层 → 跳过微信 → 选支付宝 ③如果用户已经创建了微信支付订单 → 还在"待支付"状态 → 微信不可用 → 用户无法完成支付 → ④方案 → 订单超时关闭 → 5分钟未支付 → 关闭微信订单 → 用户重新发起 → 路由到支付宝 ⑤或者 → 主动查询微信订单状态 → 如果未支付 → 关闭 → 通知用户重新发起 / 路由配置存储：①Nacos → 路由规则 → 热更新 → 不重启 ②DB → 渠道配置 → 限额/费率/优先级 → 管理后台修改 ③Redis → 渠道可用性 → 实时更新 → 健康检查/熔断结果 ④缓存 → 路由规则 + 渠道配置 → Caffeine 本地缓存 5秒 → 减少 DB 和 Redis 访问 / 实际场景：①大促 → 微信限流 → 支付成功率下降 → 自动切到支付宝 → 但可能支付宝也限流 → 银联兜底 ②日常 → 费率优先 → 支付宝费率低 → 优先支付宝 → 但用户可能想用微信 → 尊重用户选择 → 如果用户指定渠道 → 路由到指定渠道 ③监控 → 每个渠道的成功率/耗时/错误率 → Prometheus → 低于阈值告警 / 面试加分：能说出"路由=商户配置+限额+费率+可用性+优先级 → 渠道健康检查=主动探测+被动统计+熔断 → 微信挂了=熔断+切渠道+已创建订单超时关闭重发 → 路由配置Nacos热更新"→ 展示对支付路由的理解）

**追问4：** 最后一个问题。对账怎么做？如果网关记录支付成功了，但渠道那边说没收到，怎么处理？

> 你回答...（提示：对账系统设计 / 对账流程：①T+1 → 网关生成自己的交易流水文件 → 每笔交易：商户号/订单号/渠道订单号/金额/状态/时间 ②下载渠道对账文件 → 微信/支付宝/银联 → 各自下载 → 格式不同 → 解析成统一格式 ③逐笔核对 → 网关有渠道有 → 一致 → 标记已对平 ④网关有渠道无 → 长款 → 网关认为支付成功但渠道没有 → 可能是渠道延迟 → 或者是渠道丢了 → 挂账 → 人工核实 ⑤渠道有网关无 → 短款 → 渠道有交易但网关没有 → 可能是回调丢了 → 主动查询渠道 → 补单 ⑥金额不一致 → 差异 → 挂账 → 人工核实 / 差异类型和处理：①长款（网关有渠道无）→ 原因：a. 渠道异步通知延迟 → 但 T+1 对账文件还没出 → 等下一轮对账 b. 渠道真的没收到 → 但网关认为成功了 → 可能是网络超时但渠道处理了 → 主动查询渠道确认 c. 如果渠道确实没有这笔 → 网关误判 → 冲正 → 退给客户 ②短款（渠道有网关无）→ 原因：a. 回调通知丢了 → 网关没收到渠道的支付成功通知 → 主动查询 → 补单 → 更新订单状态 b. 网关宕机 → 丢数据 → 从渠道补 ③金额不一致 → 原因：a. 退款金额不一致 → 退款和原交易的金额对不上 b. 手续费计算不一致 → 网关和渠道的手续费算法不同 → 以渠道为准 / 对账系统设计：①定时任务 → XXL-JOB → 每天 T+1 凌晨 2 点执行 ②分渠道对账 → 每个渠道一个对账任务 → 并行执行 ③大数据量 → 分片 → 按日期分片 → 并行对账 ④差异处理 → 自动重试 + 人工介入 → 差异挂到"对账差异表"→ 运营人员处理 ⑤告警 → 差异数量超过阈值 → 飞书/钉钉告警 / 容灾考虑：①对账文件下载失败 → 渠道 API 超时 → 重试 → 超过3次 → 告警 → 人工下载 ②文件格式变更 → 渠道升级 → 解析失败 → 告警 → 适配 ③对账延迟 → T+1 对不上 → T+2 再对 → 保留多天 / 和日常运维的关系：①日常监控 → 每天的差异数 → 应该趋近于 0 → 突然增多 → 告警 → 排查 ②差异类型分布 → 如果都是"短款"→ 回调通知有问题 → 检查回调处理逻辑 ③如果都是"长款"→ 网关误判 → 检查支付状态判断逻辑 / 面试重点：对账=T+1流水文件比对 → 长款(网关有渠道无)→查渠道确认→冲正退客户 → 短款(渠道有网关无)→回调丢了→主动查询补单 → 金额不一致→挂账人工处理 → XXL-JOB定时+分片并行+差异告警）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| Java 异常体系（Error/Exception/checked/unchecked/try-with-resources/自定义异常/@Transactional回滚） | 能讲清 / 讲不全 / 不会★ | |
| MySQL 索引下推ICP与覆盖索引（ICP减少回表/覆盖索引不回表/慢SQL优化流程） | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（最长无重复字符子串/滑动窗口/HashMap优化为int数组） | 能讲清 / 讲不全 / 不会★ | |
| Spring MVC DispatcherServlet（9步请求流程/HandlerMapping/HandlerAdapter/@RequestBody Jackson反序列化/@Valid位置/异常处理@ExceptionHandler） | 能讲清 / 讲不全 / 不会★ | |
| Redis 大Key/热Key/慢查询（大Key拆分UNLINK/热Key本地缓存Caffeine/慢查询SLOWLOG KEYS替代SCAN） | 能讲清 / 讲不全 / 不会★ | |
| ForkJoinPool 工作窃取（双端队列/自己LIFO偷FIFO/parallelStream坑/fork+join示例） | 能讲清 / 讲不全 / 不会★ | |
| 统一支付网关设计（渠道适配Adapter/路由策略/幂等三重保证/异步通知MQ重试/对账T+1） | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **Java 异常体系**：Throwable → Error（JVM错误不catch：OOM/StackOverflow）+ Exception → RuntimeException（unchecked 编程错误：NPE/ClassCast）+ Checked Exception（强制处理外部异常：IO/SQL）。**@Transactional 默认只回滚 RuntimeException + Error → throw checked Exception 不回滚 → 生产必须加 `rollbackFor = Exception.class`**。try-with-resources（Java 7+）= AutoCloseable 自动 close → 编译器生成 finally → 多资源逆序关闭 → close 异常被 suppressed 不丢失。自定义异常：继承 RuntimeException + 错误码 → `@RestControllerAdvice` + `@ExceptionHandler` 全局处理 → BizException 返回 400 / SysException 返回 500
> 2. **MySQL ICP 与覆盖索引**：ICP（索引下推）= 把 WHERE 条件下推到存储引擎层 → 在联合索引上提前过滤 → 减少回表次数（EXPLAIN: Using index condition）。覆盖索引 = 查询列全在索引中 → 不需要回表（EXPLAIN: Using index）。覆盖索引 > ICP > 无优化。实际优化流程：慢日志发现 → EXPLAIN 四字段（type/key/rows/Extra）→ 加索引/覆盖索引/ICP/延迟关联 → 验证。**`SELECT *` 基本无法覆盖 → 避免 SELECT *** 
> 3. **滑动窗口**：核心 = right 扩展 + left 收缩 → 维护窗口 [left, right]。HashMap 存字符最后出现位置 → 遇到重复（在窗口内）→ left 跳到重复字符 +1。`map.get(c) >= left` 判断关键：只关心窗口内的重复。ASCII 用 int[128] 数组替代 HashMap 更快。模板：找最长先扩展后收缩，找最短先满足再收缩
> 4. **Spring MVC DispatcherServlet**：9步流程：DispatcherServlet → getHandler(HandlerMapping找Controller) → getHandlerAdapter → 拦截器preHandle → HandlerAdapter.handle(调Controller) → 参数解析(@RequestBody→RequestResponseBodyMethodProcessor→Jackson反序列化) → Controller执行 → 返回值处理(@ResponseBody→Jackson序列化) → 拦截器postHandle/afterCompletion。**@Valid 在反序列化之后校验** → 校验失败 MethodArgumentNotValidException → 全局异常处理返回 400。异常处理：Controller抛异常 → DispatcherServlet → HandlerExceptionResolver → ExceptionHandlerExceptionResolver 找 @RestControllerAdvice 里的 @ExceptionHandler → 精确匹配优先 → 兜底 Exception.class
> 5. **Redis 大Key/热Key/慢查询**：大Key（String>10KB/集合>5000元素）→ 危害：内存不均/删除阻塞/网络带宽 → 排查：`--bigkeys`/`MEMORY USAGE` → 解决：拆分分桶/UNLINK异步删除/Lazy Free。热Key（单Key高QPS）→ 危害：单节点CPU瓶颈 → 排查：`--hotkeys`(LFU)/代理层统计 → 解决：Caffeine本地缓存(短TTL最常用)/读副本/Key拆分。慢查询 → `SLOWLOG GET` → 常见原因：KEYS*/HGETALL大Hash/SORT/大Key DEL → 解决：SCAN替代KEYS/HSCAN/UNLINK/分页
> 6. **ForkJoinPool 工作窃取**：每线程自己的双端队列（Deque）→ 自己 LIFO（头部push/pop大任务先拆）→ 偷的人 FIFO（尾部偷小任务先执行）→ 减少竞争。fork=放入队列异步不阻塞 → join=等待结果但不空等（帮助其他任务）。优化：`left.fork() + right.compute()` 不两个都fork。**parallelStream 共用 commonPool → 阻塞操作影响所有 parallelStream → 顺序不确定 → toMap 重复key要指定merge → 数据量小不值得并行**
> 7. **统一支付网关**：接入层(验签/幂等SETNX/限流) → 路由层(商户配置+限额+费率+可用性+优先级/熔断切渠道) → 渠道适配层(Adapter统一接口/各渠道签名验签格式转换) → 核心服务(订单/流水/状态机) → 异步通知(MQ+重试8次+死信告警) → 对账(T+1流水比对/长款查渠道冲正/短款回调丢补单/金额不一致挂账人工)。幂等三重保证：Redis SETNX(请求级) + DB唯一约束(订单级) + 状态机(只有待支付才能发起) + 回调幂等(查状态直接返回)
