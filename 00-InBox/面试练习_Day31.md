# 面试模拟 - Day 31

> 日期：2026-07-01 | 模拟公司：兴业证券（杭州研发中心）
> 模拟岗位：Java高级开发工程师 | 建议时长：85分钟
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实对话节奏
>
> **说明：** 兴业证券杭州研发中心偏财富管理与投顾系统，面试风格偏实战，喜欢从线上问题反推原理。二面会考察你对系统可维护性和技术债的认知。

---

## 开场

> "先做个自我介绍吧，重点说说你最近这一年做的事情。"

**→ 你的自我介绍（1.5分钟，突出时代银通集中交易平台 + 架构设计经验 + 金融IT 7年）**

---

## 话题一：Java 并发集合（12分钟）

**面试官：你说你做多线程开发比较多，Java 里有哪些线程安全的集合？**

你回答（ConcurrentHashMap、CopyOnWriteArrayList、CopyOnWriteArraySet、ConcurrentLinkedQueue、BlockingQueue系列）...

**追问1：** CopyOnWriteArrayList 的原理是什么？为什么叫"写时复制"？它适合什么场景？

你回答（写时复制副本、读无锁、写加锁、适合读多写少、不适合写频繁场景）...

**追问2：** CopyOnWriteArrayList 写操作的时候，如果同时有线程在读，读线程读到的是旧数据还是新数据？

你回答（读到旧数据、弱一致性、最终一致、写完替换引用）...

**追问3：** ConcurrentLinkedQueue 是怎么保证线程安全的？它用了什么机制？

你回答（CAS无锁、Michael-Scott算法、head/tail节点、入队出队都是CAS操作）...

**追问4：** ConcurrentLinkedQueue 的 size() 方法是 O(1) 还是 O(n)？为什么？

你回答（O(n)、没有维护size变量、遍历计数、因为CAS无法原子更新size）...

**追问5：** 那如果需要一个线程安全的队列，又需要阻塞等待，用哪个？BlockingQueue 有哪些实现？

你回答（BlockingQueue、ArrayBlockingQueue有界数组、LinkedBlockingQueue链表、SynchronousQueue直接传递、PriorityBlockingQueue优先级）...

**追问6：** ArrayBlockingQueue 和 LinkedBlockingQueue 的底层实现有什么区别？哪个性能更好？

你回答（Array一把锁、Linked两把锁put/take分离、Linked吞吐更高但内存开销大、Array内存连续）...

---

## 话题二：MySQL binlog 与数据恢复（10分钟）

**面试官：MySQL 的 binlog 了解吗？它和 redo log 有什么区别？**

你回答（binlog是Server层逻辑日志、redo log是InnoDB引擎层物理日志、binlog用于复制和恢复、redo log用于崩溃恢复）...

**追问1：** binlog 有几种格式？各有什么优缺点？

你回答（Statement记录SQL、Row记录行变更、Mixed混合模式、Statement可能有函数不一致问题、Row数据量大但准确）...

**追问2：** 你们生产环境用的哪种格式？为什么？

你回答（Row、数据一致性最好、虽然日志大但存储便宜、Statement在跨库复制时可能不一致）...

**追问3：** 如果有人误删了一张表的数据，用 binlog 怎么恢复？

你回答（找到误删前的全量备份、用mysqlbinlog解析binlog重放到误删前的时间点、或者基于GTID定位）...

**追问4：** redo log 和 binlog 之间怎么保证一致性？两阶段提交是什么？

你回答（prepare→写redo log、commit→写binlog、崩溃恢复时判断redo log状态、prepare且binlog完整则提交否则回滚）...

**追问5：** 如果 binlog 写成功了但 redo log 还没 commit，崩溃后会怎样？反过来呢？

你回答（binlog成功redo未commit：崩溃恢复时检查binlog完整则提交、不完整则回滚；redo commit binlog未写：不会发生、两阶段提交保证）...

---

## 话题三：手写代码 - 合并K个有序链表（8分钟）

**面试官：前面聊到链表，写一道题吧。给你K个有序链表，合并成一个有序链表。**

```java
public class ListNode {
    int val;
    ListNode next;
    ListNode(int val) { this.val = val; }
}

// 合并K个有序链表
public ListNode mergeKLists(ListNode[] lists) {
    // 你来实现
}
```

**追问1：** 你用的是什么方法？时间复杂度是多少？

你回答（小顶堆/优先队列、每个元素入堆一次、O(N log K)、N是总元素数、K是链表数）...

**追问2：** 如果不用堆，还有别的方案吗？各有什么优缺点？

你回答（两两合并O(NK)、分治合并O(N log K)、堆方案空间O(K)、分治方案空间O(logK)递归栈）...

**追问3：** 如果 K 非常大（比如10万个链表），堆方案还合适吗？有什么问题？

你回答（堆太大内存压力、可以分批处理、或者分治合并减少同时处理的链表数）...

---

## 话题四：Spring Boot 启动流程与自动配置（10分钟）

**面试官：Spring Boot 的自动配置原理能讲一下吗？@SpringBootApplication 做了什么？**

你回答（@SpringBootApplication = @Configuration + @EnableAutoConfiguration + @ComponentScan、spring.factories加载配置类、@Conditional条件装配）...

**追问1：** @EnableAutoConfiguration 具体是怎么加载配置类的？通过什么机制？

你回答（AutoConfigurationImportSelector、读取META-INF/spring.factories（2.7之前）或META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports（2.7之后）、加载AutoConfiguration类）...

**追问2：** @Conditional 系列注解有哪些？@ConditionalOnMissingBean 是什么意思？

你回答（@ConditionalOnClass、@ConditionalOnBean、@ConditionalOnMissingBean、@ConditionalOnProperty、MissingBean表示容器中没有该Bean时才创建）...

**追问3：** 如果你自己写一个 Starter，要怎么做？关键步骤是什么？

你回答（写AutoConfiguration类加@Conditional、写spring.factories或imports文件、打包、引入即可用）...

**追问4：** Spring Boot 启动时，自动配置类和用户自定义的 @Configuration 谁优先？用户定义的 Bean 会覆盖自动配置的吗？

你回答（用户优先、@ConditionalOnMissingBean保证、SpringBoot自动配置是兜底、用户显式定义则覆盖）...

**追问5：** Spring Boot 的启动流程大致是怎样的？从 main 方法到容器就绪，经历了哪些关键步骤？

你回答（SpringApplication.run→创建ApplicationContext→prepareContext→refreshContext→refresh中完成Bean创建和初始化→afterRefresh→CommandLineRunner）...

---

## 话题五：Redis 过期策略与内存回收（10分钟）

**面试官：Redis 的 key 设置了过期时间后，是怎么过期的？**

你回答（定期删除+惰性删除、定期删除每秒执行10次随机抽样、惰性删除访问时检查）...

**追问1：** 为什么不同时用这两种策略？只用定期删除行不行？

你回答（定期删除无法保证所有过期key及时清理、惰性删除兜底、两者配合才不会内存泄漏）...

**追问2：** 如果定期删除和惰性删除都没清掉，Redis 内存满了怎么办？

你回答（内存淘汰策略、maxmemory配置、noeviction/allkeys-lru/volatile-lru/allkeys-lfu等8种策略）...

**追问3：** LRU 和 LFU 有什么区别？Redis 的 LRU 是精确的吗？

你回答（LRU最近最少使用、LFU最不经常使用、Redis LRU是近似LRU、采样5个key选最久未用的、不是全局精确LRU）...

**追问4：** maxmemory-samples 参数是干什么的？设大设小有什么影响？

你回答（采样数量、默认5、越大越精确但CPU开销越大、越小越快但淘汰质量下降）...

**追问5：** volatile-lru 和 allkeys-lru 在生产环境怎么选？有什么坑？

你回答（volatile只淘汰设了过期的、allkeys淘汰所有、volatile如果大量key没设过期可能导致OOM、allkeys更激进但可能淘汰重要数据）...

---

## 话题六：项目深挖 - 组件化营销活动（10分钟）

**面试官：你说做了组件化营销活动，"组件化"具体是什么意思？怎么拆分的？**

你回答（把营销活动拆成独立组件：奖品组件、规则组件、渠道组件、人群组件、组件可组合复用、配置化上线活动）...

**追问1：** 组件之间是怎么交互的？直接调用还是通过某种机制？

你回答（定义统一接口、组件之间通过上下文对象传递数据、或事件驱动、策略模式+责任链组合）...

**追问2：** 如果业务方要新增一种全新的活动玩法，你的组件化架构需要改哪些地方？多久能上线？

你回答（新增组件实现接口、配置活动模板、不需要改核心流程、从7人天缩到4人天就是因为这个）...

**追问3：** 组件的版本管理怎么做？一个组件改了，引用它的活动都受影响吗？

你回答（组件版本号、活动绑定特定版本、灰度发布新版本、回滚到旧版本）...

**追问4：** 你怎么保证组件化后的代码质量？组件之间会不会有隐式依赖？

你回答（接口契约、单元测试、集成测试、Code Review、依赖通过配置显式声明）...

**追问5：** 如果现在让你重新设计，你觉得这个组件化方案有什么不足？会怎么改进？

你回答（可能过度拆分、组件粒度不好把握、可以引入规则引擎替代硬编码组件、配置中心动态管理）...

---

## 二面（架构师，30分钟）

> "一面聊得差不多了，我问几个偏设计和工程实践的问题。"

---

## 二面话题一：线上问题排查体系（12分钟）

**面试官：你在简历里写了"具备线上问题排查与日志分析能力"，说说你遇到过印象最深的线上问题，怎么排查的？**

你回答（具体案例：接口超时/CPU飙高/OOM/数据库慢查询、排查思路、定位过程、解决方案）...

**追问1：** 如果线上接口突然变慢，从你接到告警到定位原因，你的排查路径是什么？

你回答（看监控告警→确认影响范围→看应用日志→看JVM状态jstack/jmap→看数据库慢查询→看中间件→网络排查）...

**追问2：** 如果 jstack 发现大量线程都卡在同一个地方，你会怎么分析？

你回答（看线程状态BLOCKED/WAITING→看堆栈定位代码→判断是不是锁竞争或死锁→看数据库连接或HTTP调用超时）...

**追问3：** 你们有没有用 APM 工具？比如 SkyWalking、Pinpoint、Jaeger？链路追踪的原理是什么？

你回答（Trace ID贯穿全链路、Span表示一个操作、Agent无侵入埋点、通过ThreadLocal或HTTP Header传递TraceId）...

**追问4：** 如果是数据库层面的问题，你怎么判断是 SQL 的问题还是数据库本身的压力问题？

你回答（看慢查询日志、看MySQL的processlist、看InnoDB状态、看锁等待、看CPU/IO/连接数、区分是单条SQL慢还是整体慢）...

**追问5：** 排查完问题后，你怎么做复盘？怎么避免同类问题再次发生？

你回答（故障复盘文档、根因分析、改进措施落地、加监控告警、代码review加强、应急预案）...

---

## 二面话题二：技术债与系统可维护性（10分钟）

**面试官：做了7年金融IT，你对技术债怎么看？你们项目里有哪些技术债？**

你回答（技术债不可避免、快速交付牺牲质量积累的、补测试、补文档、重构、还债要有计划）...

**追问1：** 如果领导让你还技术债，但同时又催进度，你怎么平衡？

你回答（技术债分级、关键路径优先还、每个迭代分配20%时间还债、把还债和功能开发结合、用数据说服领导）...

**追问2：** 你觉得什么样的代码算是"烂代码"？你接手别人的代码时怎么处理？

你回答（命名混乱、超长方法、重复代码、硬编码、无注释无测试、接手时先补测试再改、不盲目重构）...

**追问3：** 微服务架构下的技术债有哪些？和单体架构比有什么不同？

你回答（服务边界不清晰、接口契约不统一、分布式事务未处理、监控告警缺失、数据冗余不一致、链路复杂排查困难）...

**追问4：** 如果让你评估一个系统的"健康度"，你会从哪些维度看？

你回答（代码质量、测试覆盖率、监控完备度、文档完整度、技术栈是否过时、线上故障频率、团队认知负载）...

---

## 面试结束

> "好，今天就到这里。你有什么问题想问我的？"

**→ 你可以问的问题（准备1-2个）**
- 兴业证券杭州研发中心主要做哪些业务系统？财富管理方向还是交易方向？
- 团队的 DevOps 成熟度怎么样？有完整的 CI/CD 和监控体系吗？

---

## 答题自评

| 话题 | 整体感觉（顺畅/吃力/卡住） | 最薄弱的点 |
|------|---------------------------|-----------|
| Java 并发集合 | | |
| MySQL binlog 与数据恢复 | | |
| 手写代码（合并K个有序链表） | | |
| Spring Boot 启动流程与自动配置 | | |
| Redis 过期策略与内存回收 | | |
| 组件化营销活动深挖 | | |
| 线上问题排查体系 | | |
| 技术债与系统可维护性 | | |

### 今天要补的知识点
1. _______________
2. _______________
3. _______________
4. _______________
5. _______________

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________
