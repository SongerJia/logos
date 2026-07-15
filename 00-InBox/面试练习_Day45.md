# 面试模拟 - Day 45

> 日期：2026-07-15（周三） | 模拟岗位：杭银消费金融股份有限公司（杭州）- Java开发工程师
> 建议时长：85分钟（一面55分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day45，模拟杭银消费金融——杭州银行旗下的消费金融公司，主做消费贷、现金贷、场景分期。消费金融和银行信贷不同：额度小（几千到20万）、高频（日放款万笔）、重风控（实时审批）、场景化（教育/医美/3C分期）。今天引入 Java 反射与动态代理、JVM 调优实战、Kafka 高级特性、Spring Boot 自动配置原理深入等新话题，核心设计题围绕消费信贷风控系统展开。

---

# 一面（55分钟）

## 话题一：Java 反射与动态代理（12分钟）

**面试官：你简历上写了 Spring AOP。AOP 底层用到了动态代理，你了解反射和动态代理吗？**

→ 你回答...

**追问1：** Java 反射是什么？它能在运行时做什么？性能问题你怎么看？

→ 你回答...（提示：运行时获取类信息/创建实例/调用方法/访问字段 / 核心 API：Class.forName() / getDeclaredMethods() / method.invoke() / field.setAccessible(true) / 性能比直接调用慢 1-10 倍 / JIT 优化后差距缩小 / Spring 里大量用反射但通过缓存 Method 对象优化 / 不在热路径上用反射就没问题）

**追问2：** JDK 动态代理和 CGLIB 代理有什么区别？Spring 什么时候用哪个？

→ 你回答...（提示：JDK 动态代理：基于接口 / Proxy.newProxyInstance / 被代理类必须实现接口 / 生成 $Proxy0 类 / CGLIB：基于继承 / 生成子类 / 不需要接口 / 不能代理 final 类和方法 / Spring 默认：有接口用 JDK 代理（proxyTargetClass=false）/ 没接口或强制配置用 CGLIB / Spring Boot 2.x 默认 proxyTargetClass=true → 都用 CGLIB）

**追问3：** CGLIB 底层用的什么技术？为什么不能代理 final 方法？

→ 你回答...（提示：CGLIB 用 ASM 字节码框架生成子类 / 子类重写父类方法织入增强逻辑 / final 方法不能被重写 → 无法代理 / private 方法也不能 / static 方法也不能 / JDK 动态代理也没有这个限制但只限接口方法）

**追问4：** 你在项目里有没有自己写过动态代理？什么场景下用的？

→ 你回答...（提示：实际场景：①日志切面：记录方法执行时间 / ②权限校验：方法调用前检查权限 / ③远程调用：Feign/Sentinel 底层都是动态代理 / ④自定义注解处理：@RateLimiter / 写法：实现 InvocationHandler 接口 / invoke 方法里加增强逻辑 / 或者直接用 Spring AOP @Aspect 更方便）

**追问5：** 反射能破坏单例吗？你写的 DCL 单例，别人用反射能不能 new 出第二个实例？

→ 你回答...（提示：可以 / 反射 setAccessible(true) 后可以调用 private 构造器 / 破坏单例 / 防御：①构造器里判断如果实例已存在抛异常 ②用枚举实现单例——枚举的构造器 JVM 保证不被反射调用 / 枚举单例是《Effective Java》推荐的最佳实践 / 反射对枚举无效）

**追问6：** `getMethod` 和 `getDeclaredMethod` 有什么区别？`setAccessible(true)` 做了什么？

→ 你回答...（提示：getMethod 只能获取 public 方法包括继承的 / getDeclaredMethod 获取本类声明的所有方法包括 private 不包括继承的 / setAccessible(true) 绕过访问控制 / 拿到 private 方法的访问权 / Java 9 模块系统后 setAccessible 受 Module 系统限制 / --add-opens 参数开放模块访问）

---

## 话题二：Kafka 高级特性（10分钟）

**面试官：你们有用 Kafka 吗？Kafka 和 RocketMQ 你觉得核心区别在哪？Kafka 怎么保证消息不丢？**

→ 你回答...

**追问1：** Kafka 的 ISR 机制你了解吗？它和 RocketMQ 的主从同步有什么区别？

→ 你回答...（提示：ISR = In-Sync Replicas / Leader 维护一个 ISR 列表 / ISR 里的副本和 Leader 数据同步在阈值内 / 只有 ISR 里的副本有资格被选为新 Leader / 如果 ISR 为空可以选未同步的副本（unclean.leader.election.enable=true）但会丢数据 / vs RocketMQ：RocketMQ 同步刷盘/异步刷盘 + Master-Slave / Kafka 更灵活——ISR 动态伸缩）

**追问2：** HW 和 LEO 是什么？消费者能消费到哪里？

→ 你回答...（提示：LEO = Log End Offset / 每个副本的最后一条消息的 offset+1 / HW = High Watermark / ISR 中最小 LEO / 消费者只能消费到 HW 之前的消息 / HW 保证了消费者不会读到未完全同步的消息 / Leader 收到生产者消息后等 ISR 所有副本确认 → 更新 HW / Follower 拉取 Leader 数据同步 LEO）

**追问3：** Kafka 怎么实现"精确一次"（Exactly-Once）语义？默认是什么语义？

→ 你回答...（提示：默认 At-Least-Once / 生产者可能重试导致重复 / 消费者手动提交 offset 前宕机导致重复消费 / 精确一次方案：①生产者幂等（enable.idempotence=true）/ PID + sequence number 去重 / ②事务（transactional.id）/ 跨分区原子写入 / 消费者 read_committed 隔离级别 / ③消费端业务幂等 / 真正生产环境靠业务幂等兜底 / 不能只依赖 MQ 的精确一次）

**追问4：** Kafka 的 Rebalance 你遇到过吗？什么情况下会触发？有什么问题？

→ 你回答...（提示：Rebalance 在消费者加入/退出/分区数变化时触发 / 问题：Rebalance 期间所有消费者停止消费（Stop The World）/ 大量消费者同时 Rebalance 会导致长时间停顿 / 优化：①sticky.assignment 粘性分配减少分区迁移 ②心跳超时调大 ③避免频繁加入退出 / Kafka 2.4+ Incremental Cooperative Rebalance 渐进式重平衡 / 减少停顿）

**追问5：** 你们 Kafka 的消息积压怎么处理的？消费者怎么扩容？

→ 你回答...（提示：积压 = 生产速度 > 消费速度 / 排查：消费者处理慢 / 消费者数 < 分区数（消费者数不能超过分区数）/ 处理：①增加消费者（不能超分区数）②增加分区数（需要重新 Rebalance）③临时消费者只消费不处理先存下来 / ④如果是处理慢→优化消费逻辑/异步化/批量 / ⑤监控告警：积压超阈值告警 / ⑥根本解法：扩容分区 + 消费者 / 分区数一开始就设够）

---

## 话题三：手写代码 - 有效括号（8分钟）

**面试官：给你一个字符串，包含 `(` `)` `{` `}` `[` `]`，判断括号是否有效配对。比如 `"()[]{}"` 是 true，`"([)]"` 是 false。写一下。**

你在纸上/白板上写代码...

**追问1：** 你用的什么数据结构？为什么用栈？

→ 你回答...（提示：栈 / 后进先出 / 遇到左括号入栈 / 遇到右括号弹出栈顶判断是否匹配 / 最后栈空 = 有效 / 栈是处理嵌套结构的天然选择）

**追问2：** 如果不用栈，能不能用计数器？比如 `(` +1，`)` -1，最后为0？

→ 你回答...（提示：只有一种括号可以 / 多种括号不行 / `"([)]"` 计数器都是0但无效 / 必须用栈匹配括号类型 / 计数器无法区分括号的嵌套层级 / 这就是为什么要用栈）

**追问3：** 时间和空间复杂度？能不能优化到 O(1) 空间？

→ 你回答...（提示：O(n) 时间 / O(n) 空间最坏情况全是左括号 / 不能优化到 O(1) / 必须存储未匹配的左括号 / 如果字符串只有一种括号可以用计数器 O(1) / 但通用场景必须用栈）

**追问4：** 如果要扩展，支持更多类型的括号（比如 `<` `>`），你的代码需要改哪里？

→ 你回答...（提示：加一个映射表 Map<Character, Character> / key=右括号 value=对应的左括号 / 遇到右括号查 Map 判断栈顶是否匹配 / 扩展只需要往 Map 加条目 / 符合开闭原则）

---

## 话题四：JVM 调优实战（10分钟）

**面试官：你们线上 JVM 参数怎么配的？有没有做过 GC 调优？说一下具体过程。**

→ 你回答...

**追问1：** 你们用的什么垃圾回收器？为什么选它？

→ 你回答...（提示：JDK 8 默认 Parallel GC（吞吐量优先）/ G1 适合大堆内存（6GB+）/ ZGC/Shenandoah 低延迟（JDK 11+）/ 金融系统一般用 G1 / G1 可设最大停顿时间 -XX:MaxGCPauseMillis=200 / 兼顾吞吐和延迟 / CMS 已废弃 JDK 14 移除 / 选型看：小堆用 Parallel / 大堆用 G1 / 超低延迟用 ZGC）

**追问2：** 你们 JVM 内存怎么分配的？堆大小、新生代老年代比例怎么设？

→ 你回答...（提示：-Xms = -Xmx 初始堆=最大堆避免动态扩缩 / 一般 4-8G / -Xmn 新生代大小 / 新生代:老年代 = 1:2（默认）/ 或用 G1 不用手动设 -XX:G1HeapRegionSize / Metaspace 大小 -XX:MaxMetaspaceSize=256m / 栈大小 -Xss=512k / 不要设太大——GC 停顿时间和堆大小正相关）

**追问3：** 如果线上 Full GC 频繁，你怎么排查和解决？

→ 你回答...（提示：排查步骤：①jstat -gcutil 看 GC 频率和各区内存 / ②jmap -histo:live 看对象分布 / ③jmap -dump 导出堆 dump / ④MAT 分析大对象和内存泄漏 / 常见原因：①大对象进老年代（数组/大List）②内存泄漏（缓存不清理/ThreadLocal不remove）③Metaspace溢出（动态生成类）④System.gc() 被调用 / 解决：调大新生代/加缓存淘汰/修复泄漏/禁用 System.gc）

**追问4：** 你说的 jstat 和 jmap，如果生产环境不能直接连（容器化部署），你怎么看 JVM 状态？

→ 你回答...（提示：①Spring Boot Actuator 暴露 JVM 指标 / ②Prometheus + Grafana 采集 JMX 指标 / ③Arthas 在线诊断工具 / ④JFR (Java Flight Recorder) 录制分析 / ⑤容器挂载 dump 目录 / jmap dump 后导出 / ⑥sidecar 采集 JVM 指标 / K8s 环境下常用 Prometheus JMX Exporter）

**追问5：** 有没有遇到过 OOM？最后怎么解决的？

→ 你回答...（提示：实际案例：①堆 OOM——大查询结果全加载到内存 → 改成分页/流式处理 / ②Metaspace OOM——CGLIB 动态代理生成大量类 → 排查是否有类泄漏 / ③Direct Memory OOM——Netty 堆外内存泄漏 → -XX:MaxDirectMemorySize 限制 / ④GC overhead——GC 占 98% 时间但回收不到 2% → 内存泄漏需要 dump 分析 / 通用解法：-XX:+HeapDumpOnOutOfMemoryError 自动 dump → MAT 分析）

---

## 话题五：Spring Boot 自动配置原理深入（8分钟）

**面试官：你们用 Spring Boot，自动配置的原理你了解吗？它是怎么"约定大于配置"的？**

→ 你回答...

**追问1：** `@SpringBootApplication` 注解里包含了什么？自动配置入口在哪？

→ 你回答...（提示：@SpringBootApplication = @SpringBootConfiguration + @EnableAutoConfiguration + @ComponentScan / @EnableAutoConfiguration 通过 @Import(AutoConfigurationImportSelector.class) 导入 / AutoConfigurationImportSelector 读取 META-INF/spring.factories（Spring Boot 2.x）/ Spring Boot 3.x 改用 META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports / 加载所有自动配置类）

**追问2：** 自动配置类加载了那么多，是不是全部生效？怎么判断生效不生效？

→ 你回答...（提示：不是全部生效 / 用 @Conditional 系列注解判断 / @ConditionalOnClass：classpath 有指定类才生效 / @ConditionalOnMissingBean：容器没有指定 Bean 才生效 / @ConditionalOnProperty：配置项满足条件才生效 / @ConditionalOnWebApplication：Web 环境才生效 / 排除：@SpringBootApplication(exclude = XxxAutoConfiguration.class) 或配置文件 spring.autoconfigure.exclude）

**追问3：** 你看过 RedisAutoConfiguration 的源码吗？它是怎么自动配置 RedisTemplate 的？

→ 你回答...（提示：@ConditionalOnClass(RedisOperations.class) / @ConditionalOnSingleCandidate(RedisConnectionFactory.class) / @Bean @ConditionalOnMissingBean RedisTemplate<Object,Object> / 注意默认 RedisTemplate 用 JdkSerializationRedisSerializer → 中文乱码 / 所以我们自己配 RedisTemplate 用 Jackson 序列化 / 这就是为什么经常要"覆盖"自动配置）

**追问4：** 你自己写过 Starter 吗？怎么让别人的项目引入你的 jar 就自动配置好？

→ 你回答...（提示：①写 AutoConfiguration 类 + @Conditional 条件 / ②写 @ConfigurationProperties 配置属性类 / ③META-INF/spring.factories 写 EnableAutoConfiguration=你的配置类（2.x）/ 或 META-INF/spring/...imports（3.x）/ ④打包成 jar / 别人引入依赖 + 配置文件写参数 → 自动生效 / ⑤@AutoConfiguration 注解标记 / ⑥可以加 @ConfigurationPropertiesScan 自动扫描属性类）

**追问5：** Spring Boot 3.x 和 2.x 在自动配置上有什么变化？

→ 你回答...（提示：①spring.factories 废弃 → 改用 .imports 文件 / ②@AutoConfiguration 替代 @Configuration / ③Jakarta EE 9+ javax → jakarta / ④GraalVM Native Image 支持 / AOT 编译 / ⑤Java 17+ 最低版本 / 迁移成本主要在 javax → jakarta 包名替换）

---

## 话题六：消费金融业务与风控（7分钟）

**面试官：你在百信做过银行系统。消费金融和银行信贷有什么区别？你了解消费金融的核心业务吗？**

→ 你回答...

**追问1：** 消费金融和传统银行贷款最大的区别是什么？

→ 你回答...（提示：①额度小：几千到20万 / 银行贷款几十万到几百万 / ②高频：日放款万笔以上 / 银行日几十笔 / ③无抵押：信用贷为主 / 银行有抵押 / ④秒批：实时风控自动审批 / 银行人工审核 / ⑤场景化：教育分期/医美分期/3C分期 / 银行贷款用途不限定 / ⑥利率高：年化10-24% / 银行4-8% / ⑦客群下沉：征信较薄的人群 / 银行优选优质客户）

**追问2：** 消费贷的审批流程是怎样的？风控在哪些环节介入？

→ 你回答...（提示：申请→准入规则→反欺诈→信用评分→授信决策→放款 / 准入规则：年龄/征信/黑名单硬规则 / 反欺诈：设备指纹/团伙欺诈/IP聚集 / 信用评分：多维度评分模型→授信额度 / 授信决策：规则引擎+模型联合决策 / 放款后监控：贷后风险预警 / 全流程秒级完成）

**追问3：** 你说的"信用评分"是什么？如果系统要根据用户数据算一个分数，技术方案怎么设计？

→ 你回答...（提示：评分卡模型 / 数据维度：征信/多头借贷/消费行为/社交关系 / 评分卡分为 A卡（申请）、B卡（行为）、C卡（催收）/ 技术方案：特征工程→模型训练→在线推理 / 在线推理可以用规则引擎+模型服务 / 模型服务用 Python 训练导出 PMML/ONNX → Java 加载推理 / 或调用模型服务的 HTTP 接口 / Java 端做特征组装）

---

# 二面（30分钟）

## 话题七：消费信贷风控系统设计（18分钟）

**面试官：如果让你设计一个消费信贷的风控决策系统，支持实时审批、规则配置化、模型可插拔、贷后监控，你怎么设计？**

你在纸上画架构图/说思路...

**追问1：** 用户提交贷款申请后，系统第一步做什么？准入规则和风控模型是什么关系？

→ 你回答...（提示：第一步：准入规则（硬规则）→ 不通过直接拒绝 / 第二步：反欺诈 / 第三步：风控模型评分 / 准入规则：黑白名单/年龄限制/征信硬查询次数 / 是 if-else 硬条件不需要模型 / 模型评分是概率判断给额度利率 / 两层过滤：规则挡住明确不合规的，模型评估灰色地带）

**追问2：** 规则引擎你选什么？规则频繁变化怎么做到不重启生效？

→ 你回答...（提示：规则引擎选型：Drools（功能强重）/ Aviator/QLExpress（轻量）/ 或自研简单规则引擎 / 规则配置化：规则存数据库/配置中心 / 规则变更→推送→热加载 / 不重启生效 / 规则版本管理：灰度发布新规则 / A/B 测试 / 回滚机制 / 规则审核流程防误操作）

**追问3：** 模型服务怎么集成？风控模型是 Python 训练的，Java 系统怎么调用？

→ 你回答...（提示：两种方案：①模型导出 PMML/ONNX → Java 加载本地推理 / 优点：低延迟无网络开销 / 缺点：模型更新要重新部署 / ②模型服务化 → Python Flask/FastAPI 部署 → Java HTTP/gRPC 调用 / 优点：模型独立更新 / 缺点：网络延迟+服务依赖 / 选型：高并发低延迟用本地推理 / 模型迭代频繁用服务化 / 折中：模型服务 + 本地缓存推理结果）

**追问4：** 审批结果怎么保证和征信系统一致？如果征信查询失败怎么办？

→ 你回答...（提示：征信查询是外部依赖 / 超时/失败处理：①降级：征信查不到用内部数据兜底（保守授信）②缓存：征信结果短时缓存（如1天）减少外部调用 / ③异步：先预审批→征信异步回填→最终决策 / ④限流：征信接口有限流保护 / ⑤重试：网络异常自动重试 / ⑥告警：征信查询失败率超阈值告警 / 核心：不能因为征信查不到就拒绝所有用户 → 降级策略）

**追问5：** 贷后监控你怎么设计？用户借钱后跑路了怎么提前发现？

→ 你回答...（提示：贷后风险预警 / ①行为监控：还款行为变化/多头借贷/新增逾期 / ②外部数据监控：征信变化/司法涉诉/法院被执行 / ③模型预警：B卡行为评分下降→触发预警 / ④催收分级：M1短信→M2电话→M3委外 / ⑤额度管控：风险用户降额/冻结 / ⑥大数据：设备变更/IP异常/关联人风险 / ⑦实时流处理 Flink 做实时风控规则 / ⑧预警≠直接动作，人工复核）

**追问6：** 风控系统的高可用怎么保证？如果风控系统挂了，贷款申请怎么办？

→ 你回答...（提示：风控是核心链路不能挂 / ①多机房部署：同城双活 / ②降级策略：风控挂了→保守授信（给最低额度或不放款）→人工补审 / ③缓存：最近审批结果缓存 / ④限流：保护风控系统不被打垮 / ⑤熔断：下游模型服务不可用时熔断走兜底逻辑 / ⑥监控：审批成功率/耗时/异常率大盘 / 关键：降级比可用性更重要——风控挂了不能随便放款）

---

## 话题八：数据库设计与索引优化实战（12分钟）

**面试官：你们数据库表设计是怎么做的？有没有遇到过索引设计的问题？**

→ 你回答...

**追问1：** 你设计一张用户表，有哪些字段你会建索引？为什么？

→ 你回答...（提示：主键自增 ID 聚簇索引 / 手机号唯一索引（登录查询）/ 身份证号唯一索引（风控查重）/ status 状态字段——低选择性不单独建索引但可做联合索引 / 创建时间——范围查询 / 联合索引：(status, create_time) 查"某状态最新记录" / 不要：性别/是否删除等低选择性字段单独索引没意义）

**追问2：** 什么是最左前缀原则？联合索引 `(a, b, c)` 能命中哪些查询？

→ 你回答...（提示：最左前缀：索引从最左列开始匹配 / 能命中：WHERE a=? / WHERE a=? AND b=? / WHERE a=? AND b=? AND c=? / 不能命中：WHERE b=? / WHERE c=? / WHERE b=? AND c=? / 优化器会做索引下推（ICP）但前提是最左列在条件中 / 范围查询后的列不走索引：WHERE a>? AND b=? → b 不走索引）

**追问3：** 什么是覆盖索引？它为什么快？

→ 你回答...（提示：覆盖索引 = 查询的列都在索引里 / 不需要回表（回聚簇索引查完整行）/ 索引树直接返回结果 / Extra 列显示 Using index / 比 Using where + 回表快 / 设计技巧：把查询字段加入联合索引 / 但索引不能太宽——写入慢+索引大 / 权衡：高频查询做覆盖索引，低频不做）

**追问4：** `EXPLAIN` 你平时怎么看？重点关注哪些字段？

→ 你回答...（提示：type：至少 range 级别，ALL 是全表扫描 / key：实际用的索引 / rows：预估扫描行数越少越好 / Extra：Using index（覆盖索引好）/ Using filesort（需要额外排序）/ Using temporary（临时表很慢）/ key_len：索引用了多少字节→判断联合索引用了几列 / 建议把 EXPLAIN 结果截图贴在慢 SQL 工单里）

**追问5：** 你们有没有遇到过索引失效的场景？最后怎么解决的？

→ 你回答...（提示：常见索引失效：①函数操作：WHERE YEAR(create_time)=2024 → 改为范围查询 WHERE create_time >= '2024-01-01' / ②隐式类型转换：字段是 varchar 传了 int → MySQL 转换函数加在字段上索引失效 / ③OR 条件一侧没索引 → 改 UNION / ④LIKE '%xxx' 前模糊 → 用 ES 或反向索引 / ⑤ != 和 NOT IN → 范围太大优化器选择全表扫描 / 排查：EXPLAIN 看 type 是否为 ALL）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| Java 反射与动态代理 | 能讲清 / 讲不全 / 不会★ | |
| Kafka 高级特性 | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（有效括号） | 能讲清 / 讲不全 / 不会★ | |
| JVM 调优实战 | 能讲清 / 讲不全 / 不会★ | |
| Spring Boot 自动配置原理 | 能讲清 / 讲不全 / 不会★ | |
| 消费金融业务与风控 | 能讲清 / 讲不全 / 不会★ | |
| 消费信贷风控系统设计 | 能讲清 / 讲不全 / 不会★ | |
| 数据库设计与索引优化 | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **反射与动态代理**第一次系统考察，是 Spring AOP 的底层基础。核心主线：反射（运行时获取类信息）→ JDK 动态代理（基于接口）vs CGLIB（基于继承）→ Spring AOP 选择策略。高频追问：①反射破坏单例（枚举防御）②getMethod vs getDeclaredMethod（public vs 全部）③setAccessible(true) 绕过访问控制。CGLIB 用 ASM 生成子类所以不能代理 final 方法
> 2. **Kafka 高级特性**在之前消息可靠性基础上深入。ISR（In-Sync Replicas）是 Kafka 高可用的核心——只有 ISR 里的副本有资格当 Leader。HW（High Watermark）和 LEO（Log End Offset）要能画图讲清楚——消费者只能读到 HW 之前的消息。"精确一次"靠三件套：生产者幂等 + 事务 + 消费端业务幂等，不能只依赖 MQ。Rebalance 的 Stop-The-World 问题是 Kafka 运维痛点
> 3. **有效括号**是经典栈题。核心要点：①栈是处理嵌套结构的天然选择 ②多种括号必须用栈不能用计数器 ③扩展性用 Map 做括号映射表。时间 O(n) 空间 O(n) 是最优解。面试中要能解释"为什么不能用计数器"——这是考察你对数据结构理解深度的追问
> 4. **JVM 调优实战**是 Day5/JVM 基础的进阶。GC 选型：小堆 Parallel / 大堆 G1 / 超低延迟 ZGC。-Xms=-Xmx 是基础最佳实践。Full GC 频繁排查三板斧：jstat 看 GC → jmap 看对象 → MAT 分析 dump。容器化环境用 Prometheus + JMX Exporter 替代 jstat/jmap。-XX:+HeapDumpOnOutOfMemoryError 是生产必备参数
> 5. **Spring Boot 自动配置**在之前 Spring 话题基础上深入原理。核心链路：@SpringBootApplication → @EnableAutoConfiguration → AutoConfigurationImportSelector → 读取 spring.factories/.imports → @Conditional 条件判断 → 按需生效。@ConditionalOnClass/MissingBean/Property 是三个最常用的条件注解。RedisAutoConfiguration 默认用 JDK 序列化导致乱码——这就是为什么经常需要覆盖自动配置
> 6. **消费金融**是继银行/证券/基金/期货/保险/支付清算之后第7个金融子领域。核心特征：小额、高频、无抵押、秒批、场景化。风控是消费金融的核心——准入规则（硬条件）+ 反欺诈 + 信用评分模型（概率判断）三层过滤。评分卡 A卡（申请）/B卡（行为）/C卡（催收）是行业术语要记住
> 7. **消费信贷风控系统设计**是今天的核心设计题。6个追问覆盖完整风控链路：①准入规则与模型的关系 ②规则引擎选型与热加载 ③Python模型与Java系统集成 ④外部依赖降级 ⑤贷后监控与预警 ⑥高可用与降级策略。核心原则："风控挂了不能随便放款"——降级比可用性更重要
> 8. **数据库索引优化**是实战型问题。最左前缀原则要能脱口而出。覆盖索引（Using index）比回表（Using where）快——高频查询设计覆盖索引。索引失效五大场景（函数操作/隐式类型转换/OR/LIKE前模糊/!=）是高频面试题。EXPLAIN 五个关键字段（type/key/rows/Extra/key_len）要能解读
