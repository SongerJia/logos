# 面试模拟 - Day 61

> 日期：2026-07-31（周五） | 模拟岗位：中信银行（杭州分行）- 信息科技部 - Java开发工程师
> 建议时长：100分钟（一面70分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day61，"查漏补缺"阶段第九周。模拟中信银行杭州分行信息科技部——中信银行是全国性股份制商业银行，信用卡发卡量行业前三，财富管理和对公业务强。杭州分行科技部主要做数字化运营平台、信用卡积分系统、开放银行 API 网关。面试特点：偏工程体系化思维、关注分布式事务落地、重视监控告警和可观测性、追问会从"你了解 X 吗"一路追到"你们生产怎么用 X 的"。今天引入 **TCC 分布式事务深入实现、Redis Stream 消息模型、Prometheus + Grafana 监控告警体系、gRPC 与 Protobuf、ELK 日志体系、Java 线程池监控与动态调参、Saga 分布式事务模式** 7个全新技术话题 + 开放银行（Open Banking）业务 + 前 K 个高频元素手写代码——覆盖之前碎片提到但没有作为独立话题系统考过的高频核心考点。每话题3-4个追问，模拟真实面试连环深挖。

---

# 一面（70分钟）

## 话题一：TCC 分布式事务深入实现（10分钟）

**面试官：你提到过分布式事务，Seata AT 模式你们用过吧？AT 模式有什么问题？TCC 模式你们了解吗？TCC 的三个阶段具体怎么做？**

> 你回答...

**追问1：** 先说说 AT 模式有什么局限，为什么需要 TCC？TCC 三个阶段分别做什么？

> 你回答...（提示：AT 局限与 TCC 原理 / AT 模式回顾：①Seata AT（Automatic Transaction）→ 一阶段拦截 SQL → 执行前生成 before image → 执行后生成 after image → 写 undo_log → 获取全局锁 → 提交本地事务 ②二阶段 Commit → 删 undo_log ③二阶段 Rollback → 校验 after image → 用 before image 反向 SQL 回滚 ④AT 的问题 → ①脏读：AT 一阶段就提交了本地事务 → 其他事务能读到未全局提交的数据 → 需要加 @GlobalLock 或 SELECT FOR UPDATE 防脏读 ②全局锁竞争：一阶段持有全局锁 → 其他全局事务等 → 高并发下性能差 ③只支持 SQL → 不支持非数据库操作（如调外部接口/发 MQ）→ 业务侵入性低但灵活性差 / TCC 三阶段：①**T（Try）** → 资源预留 → 如扣款场景 → 不直接扣钱 → 冻结额度（账户余额 - 冻结额度 = 可用余额）→ 相当于"预扣" ②**C（Confirm）** → 确认扣款 → 把冻结的额度实际扣除 → 冻结额度减少 → 余额减少 → 幂等（可能重试多次）③**C（Cancel）** → 取消预留 → 把冻结的额度释放 → 冻结额度减少 → 余额不变 → 幂等 / TCC vs AT 对比：AT 侵入低（拦截SQL自动）/ 一阶段提交→脏读 / 全局锁竞争 / 只支持SQL。TCC 侵入高（手写三阶段）/ 隔离好（冻结） / 无全局锁性能好 / 支持非DB操作 / 举例——转账 TCC：Try→A账户冻结100元（冻结额度+100）+ B账户预加冻结+100。Confirm→A余额-100冻结-100 → B余额+100冻结-100。Cancel→A冻结-100释放 → B冻结-100释放）

**追问2：** TCC 有几个经典坑？空回滚、悬挂、幂等分别是什么？怎么解决？

> 你回答...（提示：TCC 三大经典问题 / 1. 空回滚（Null Rollback）：①场景 → Try 阶段未执行（如网络超时 → TCC 框架认为 Try 失败 → 直接调 Cancel）→ Cancel 被调了但 Try 没执行 ②问题 → Cancel 需要"回滚"Try 的预留 → 但 Try 没执行 → 没东西可回滚 → 如果 Cancel 不管 → 业务状态不一致 ③解决 → Cancel 前检查 → 查事务日志表 → 有没有 Try 的记录 → 没有 → 空回滚 → 记录一条"空回滚"标记 → 直接返回成功 / 2. 悬挂（Suspended）：①场景 → Try 请求网络超时 → TCC 框架认为失败 → 调 Cancel → Cancel 成功 → 但 Try 请求最终到达了（网络恢复）→ Try 又执行了 → 预留资源被冻结 → 但不会再有 Confirm/Cancel → 资源永久"悬挂"②问题 → 冻结额度永远不释放 → 资源泄漏 ③解决 → Try 前检查 → 查事务日志表 → 有没有 Cancel 的记录 → 有 → 说明已经 Cancel 了 → Try 不执行 → 直接返回 / 3. 幂等（Idempotency）：①场景 → Confirm 或 Cancel 可能被重试多次 → 如果不幂等 → 重复扣款/重复释放 ②解决 → 记录事务状态 → Confirm 前检查 → 已 Confirm → 跳过 → Cancel 前检查 → 已 Cancel → 跳过 / 三大问题的核心——事务日志表：每个分支事务记录 → xid（全局事务ID）+ branchId + status（Try/Confirm/Cancel）+ create_time。Try→插入。Confirm→更新status。Cancel→先查有没有Try记录→没有则空回滚标记→有则更新status。Try前查→有Cancel记录→悬挂→拒绝执行）

**追问3：** Seata TCC 和 Hmily 框架有什么区别？TCC 框架需要提供什么能力？你们实际怎么选？

> 你回答...（提示：TCC 框架对比 / TCC 框架核心能力：①全局事务管理→开启全局事务→生成xid→传播到各分支 ②分支事务注册→Try时注册分支 ③超时控制→全局事务超时→自动Cancel ④重试→Confirm/Cancel失败→定时重试 ⑤事务日志→记录Try/Confirm/Cancel状态→防三大坑 ⑥异常处理→Try失败→Cancel全部已Try分支→Confirm失败→重试 / Seata TCC：和AT共用TC（Transaction Coordinator）→同步Confirm/Cancel→一致性好→但TC是单点（集群但状态同步）。Hmily（好未来开源）：独立TCC框架→不依赖TC→用本地事务日志表+异步Confirm/Cancel→Try同步执行+记录日志→Confirm/Cancel异步执行→无TC单点→性能好→但一致性窗口长→需对账兜底 / 实际选型：银行场景→一致性要求高→Seata TCC（同步Confirm/Cancel→数据一致性窗口短）。互联网高并发→Hmily（异步Confirm→性能好→但一致性窗口长→需对账兜底）。简单场景→不用框架→手写本地消息表+定时补偿→最可控）

**追问4：** TCC 模式在金融场景下有什么特别注意的？冻结额度这个设计怎么落地？

> 你回答...（提示：TCC 金融场景落地 / 冻结额度表设计：
```sql
CREATE TABLE account (
    id BIGINT PRIMARY KEY,
    user_id VARCHAR(32) NOT NULL,
    balance BIGINT NOT NULL,           -- 余额（分）
    frozen_amount BIGINT DEFAULT 0,    -- 冻结额度（分）
    version INT DEFAULT 0,            -- 乐观锁
    INDEX idx_user_id (user_id)
);
-- 可用余额 = balance - frozen_amount
-- Try: UPDATE account SET frozen_amount = frozen_amount + 100, version = version + 1 
--      WHERE user_id = ? AND balance - frozen_amount >= 100 AND version = ?
-- Confirm: UPDATE account SET balance = balance - 100, frozen_amount = frozen_amount - 100 
--          WHERE user_id = ? AND version = ?
-- Cancel: UPDATE account SET frozen_amount = frozen_amount - 100 
--         WHERE user_id = ? AND version = ?
```
/ 注意事项：①金额用分（BIGINT）→ 不用 double/float → 避免精度问题 ②Try 的 WHERE 条件 → `balance - frozen_amount >= amount` → 检查可用余额是否够 → 防超扣 ③乐观锁 version → 防 concurrent 修改 ④幂等 → Confirm/Cancel 前查事务日志表 → 已执行则跳过 ⑤空回滚 → Cancel 前查 → 没有 Try 记录 → 空回滚标记 ⑥悬挂 → Try 前查 → 有 Cancel 记录 → 拒绝 ⑦审计 → 每步操作记审计日志 → 可追溯 / 跨行转账 TCC：Try→冻结本行扣款账户+调对方行接口（预记账）。Confirm→本行扣款+调对方行接口（确认入账）。Cancel→本行解冻+调对方行接口（取消预记账）。对方行接口也要幂等→如果对方行不支持TCC→退化为本行TCC+本地消息表→最终一致）

---

## 话题二：Redis Stream 消息模型（9分钟）

**面试官：你们用 Redis 做什么？缓存？分布式锁？Redis 5.0 引入了 Stream 你了解吗？它和 Kafka 有什么区别？什么场景下你会用 Redis Stream 而不是 Kafka？**

> 你回答...

**追问1：** 先说说 Redis Stream 是什么。它解决了 Redis 之前什么问题？List 做消息队列有什么不行？

> 你回答...（提示：Redis Stream 引入背景 / List 做消息队列的问题：①LPUSH + RPOP → 生产者 LPUSH → 消费者 RPOP → 简单 ②问题一——无 ACK → 消费者 RPOP 取走消息 → 如果处理过程中崩溃 → 消息丢了 → 没有"未确认"机制 ③问题二——无消费组 → 多个消费者各自 RPOP → 无法分工 → 无法保证一条消息只被一个消费者处理 ④问题三——无历史 → RPOP 取走就没了 → 新消费者上线看不到之前的历史消息 → 无法回溯 ⑤Pub/Sub → 广播模式 → 所有订阅者都收到 → 不是队列模式 → 且消息不持久 → 订阅者不在线就丢 / Redis Stream 解决：①消息持久化 → Stream 是 Redis 的数据类型 → 消息存在内存 → 可持久化（RDB/AOF）→ 不丢 ②消费组（Consumer Group）→ 多个消费者组成组 → 每条消息只被组内一个消费者处理 → 负载均衡 ③ACK 机制 → 消费者取走消息 → 进入 Pending Entry List（PEL）→ 处理完 XACK → 才从 PEL 移除 → 崩溃不丢 ④历史回溯 → 消费者可以指定起始位置 → `XRANGE key - +` ⑤阻塞读取 → `XREAD BLOCK 5000` → 没有消息时阻塞等待 → 类似 Kafka 的 poll / 基本命令：`XADD mystream * name zhang age 18`→生产消息（`*`自动生成ID时间戳-序号）。`XREAD COUNT 10 STREAMS mystream 0`→读消息。`XREADGROUP GROUP mygroup consumer1 COUNT 1 STREAMS mystream >`→消费组读取（`>`表示从未分配消息中取）。`XACK mystream mygroup 1234567890-0`→确认处理完。`XPENDING mystream mygroup`→查看未确认消息。`XCLAIM mystream mygroup consumer2 60000 1234567890-0`→转移超时未ACK消息给另一个消费者）

**追问2：** 消费者崩溃后消息怎么处理？Pending Entry List 和 XCLAIM 机制是什么？

> 你回答...（提示：PEL 与 XCLAIM 机制 / Pending Entry List（PEL）：①消费者 `XREADGROUP` 取走消息 → 消息从"未分配"区移到该消费者的 PEL → PEL = 该消费者已取但未 ACK 的消息列表 ②消费者处理完 → `XACK` → 从 PEL 移除 ③如果消费者崩溃 → PEL 中的消息不丢 → 等消费者恢复后继续处理 ④PEL 是 per-consumer 的 / 消费者崩溃恢复：①方案一→等消费者恢复→自己继续处理PEL ②方案二→如果消费者永远不恢复→需要`XCLAIM`把消息转给其他消费者 ③`XCLAIM`→后台监控→检查PEL→发现某消费者有消息超过N分钟没ACK→转移给空闲消费者 ④流程→`XPENDING`查看未确认→找超时的→`XCLAIM`转移→新消费者处理→`XACK` / 和 Kafka 的 Rebalance 对比：Redis Stream=PEL保留+XCLAIM单条转移快。Kafka=Rebalance重新分配分区级别→有STW。Redis Stream内存+单条转移。Kafka磁盘日志+分区转移。Redis Stream万级QPS。Kafka百万级。Redis Stream不丢靠PEL+ACK。Kafka不丢靠offset提交。Redis Stream转移粒度=单条消息。Kafka=分区级别 / XAUTOCLAIM（Redis 6.2+）：`XAUTOCLAIM mystream mygroup consumer2 60000 0`→自动转移超时60秒未ACK的消息→后台定时执行→不需要手动监控PEL）

**追问3：** Redis Stream 和 Kafka/RocketMQ 相比，什么场景用 Stream 更合适？什么场景不该用？

> 你回答...（提示：Redis Stream 选型场景 / 适合 Redis Stream 的场景：①轻量级消息队列→不想单独部署Kafka集群→Redis已有→直接用Stream→运维成本低 ②QPS万级→Redis Stream单机万级QPS→足够大多数业务 ③消息量不大→消息在内存→不能像Kafka一样存TB级→适合小量 ④需要ACK语义→List做不到→Stream有ACK ⑤短生命周期消息→Redis可以设置`MAXLEN`→自动裁剪→消息不堆积 ⑥延迟队列场景→Redis Stream+ZSET→或用ZSET做延迟队列更简单 / 不适合的场景：①高吞吐→百万级QPS→Kafka ②大数据量→TB级消息→Kafka磁盘存储 ③消息回溯→Kafka存几天到几周→Redis Stream在内存→存不了那么多 ④严格顺序→Kafka分区顺序保证→Redis Stream也有顺序但单机限制 ⑤集群扩展→Kafka水平扩展（加Broker）→Redis Cluster分片但Stream不跨节点 ⑥事务消息→RocketMQ事务消息→Redis Stream没有 / 实际选型经验：订单状态变更通知→消息量小+需要可靠+已有Redis→用Stream。日志采集→大量+需要存→Kafka。金融交易→事务消息+高可靠→RocketMQ。秒杀异步→短时大量+可丢→Redis List就够了。延迟队列→Stream或ZSET→ZSET更简单（score=执行时间）)

**追问4：** Redis Stream 的 MAXLEN 裁剪策略是什么？内存怎么控制？

> 你回答...（提示：Stream 内存控制 / MAXLEN 裁剪：`XADD mystream MAXLEN 1000 * name zhang`→保留最新1000条→超出自动删除最旧的。`XADD mystream MAXLEN ~ 1000 * name zhang`→`~`近似裁剪→不精确保证1000条→性能更好（不每条都检查）→推荐用`~`。MINID裁剪（Redis 6.2+）：`XADD mystream MINID 1234567890 * ...`→删除ID小于指定值的消息→按时间裁剪→比MAXLEN更灵活 / 内存控制策略：①设置`MAXLEN`→限制消息数量 ②设置`MAXLEN ~`→近似裁剪→性能好 ③配合`maxmemory-policy`→Redis内存满→淘汰策略→但Stream不参与LRU/LFU淘汰→可能被Redis直接拒绝写入 ④监控→`XLEN mystream`→消息数→`MEMORY USAGE mystream`→内存占用→告警 ⑤定时清理→后台定时`XTRIM mystream MAXLEN 1000`→主动裁剪 / 内存满了的风险：①Redis `maxmemory`满→Stream写入报错（OOM命令拒绝）→消息丢失 ②如果是`noeviction`（默认）→Redis拒绝写→Stream写失败 ③如果是`allkeys-lru`→可能淘汰其他Key→但Stream大Key大概率不被淘汰→不靠谱 / 最佳实践：MAXLEN~10000限制消息数+maxmemory+70%告警+不当持久化存储用Kafka+处理完立即ACK减PEL内存+定期XTRIM清理）

---

## 话题三：Prometheus + Grafana 监控告警体系（9分钟）

**面试官：你们生产环境怎么监控的？用什么看指标？Prometheus 了解吗？它和传统的日志排查有什么区别？你们怎么做的告警？**

> 你回答...

**追问1：** 先说说 Prometheus 的整体架构。它和 ELK 有什么区别？Pull 模式和 Push 模式有什么区别？

> 你回答...（提示：Prometheus 架构 / 核心组件：①Prometheus Server→核心→含TSDB（时序数据库存指标数据）+Retriever（Pull拉取指标）+HTTP Server（查询接口/api/v1/query）②Exporter→被监控应用暴露`/metrics`端点→Prometheus拉取→如`node_exporter`（主机指标）/`mysql_exporter`/`jmx_exporter`（JVM指标）③Pushgateway→短生命周期任务（Cron Job）推送指标→Prometheus从Pushgateway拉取 ④Alertmanager→告警管理→收到Prometheus告警→去重→分组→路由→发送通知（邮件/钉钉/PagerDuty）⑤Grafana→可视化→查询Prometheus→画图看板 / Pull vs Push：Pull（Prometheus）=Prometheus主动拉→控制拉取频率不会打爆应用/拉不到=应用挂了=自然告警/需要服务发现/短任务不适合（用Pushgateway）。Push（StatsD/InfluxDB）=应用主动推→应用控制何时推/短任务适合/但应用不推=可能挂了/可能推太快 / Prometheus和ELK区别：ELK=日志（非结构化文本）→全文搜索/错误排查。Prometheus=指标（数值时间序列）→聚合/趋势/告警。互补→ELK看日志细节→Prometheus看指标趋势→一起用）

**追问2：** Prometheus 的四种指标类型是什么？Counter 和 Gauge 有什么区别？Histogram 和 Summary 呢？

> 你回答...（提示：四种指标类型 / 1. Counter（计数器）：只增不减→如HTTP请求总数→`http_requests_total`→从0开始→只能+=→不会减。查询增长率→`rate(http_requests_total[5m])`→每秒请求数QPS。重启归零→需要注意。2. Gauge（仪表盘）：可增可减→如当前活跃线程数→`jvm_threads_live_threads`→上下波动。如CPU使用率/内存使用量/连接池活跃连接数/队列长度。查询当前值→直接看→不需要rate。3. Histogram（直方图）：分布→把值分桶（bucket）→如P99延迟→`http_request_duration_seconds_bucket`。如`<0.1s`请求数/`<0.5s`/`<1s`/`<5s`/`<+Inf`。计算分位数→`histogram_quantile(0.99, rate(...))`→P99延迟。服务端计算→可跨实例聚合→推荐。4. Summary（摘要）：类似Histogram→但在客户端直接计算分位数→`http_request_duration_seconds{quantile="0.99"}`→直接给P99。精确但不可跨实例聚合→两个实例各算P99→合并后不对→不推荐 / Counter vs Gauge：只增不减 vs 可增可减。请求总数/错误总数 vs CPU/内存/线程数。rate()求增长率 vs 直接看当前值。重启归零 vs 恢复真实值 / Histogram vs Summary：服务端计算 vs 客户端计算。跨实例聚合支持 vs 不支持。桶近似 vs 客户端精确。推荐Histogram（可聚合） vs 不推荐Summary（不可聚合）)

**追问3：** PromQL 基本语法你了解吗？怎么查 QPS？怎么查 P99 延迟？怎么做多实例聚合？

> 你回答...（提示：PromQL 基础 / 即时查询：`http_requests_total`→当前值。`http_requests_total{method="GET"}`→按label筛选。`http_requests_total{status=~"2.."}`→正则匹配2xx。范围查询：`http_requests_total[5m]`→最近5分钟所有数据点。常用PromQL：①QPS→`rate(http_requests_total[5m])`→每秒增长率 ②错误率→`rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])`→5xx占比 ③P99延迟→`histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))`→跨实例聚合P99 ④CPU使用率→`100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` ⑤多实例聚合→`sum(rate(http_requests_total[5m]))`→所有实例QPS总和 ⑥分组聚合→`sum(rate(http_requests_total[5m])) by (instance)`→按实例分组 / histogram_quantile解析：rate(桶)→sum by(le)分组求和（多实例同bucket相加）→histogram_quantile(0.99,...)从桶分布计算P99→找到99%的请求落在哪个桶→线性插值估算精确值 / 告警规则（Alerting Rules）：`alert: HighLatency`+`expr: histogram_quantile(0.99,...) > 1`+`for: 1m`（持续1分钟满足才告警→防瞬时波动误报）+`labels: severity=critical`+`annotations: summary="P99 latency > 1s"`. `for`参数=持续N分钟满足条件才告警→防止GC等瞬时波动误报）

**追问4：** 服务发现怎么做？K8s 环境下 Prometheus 怎么自动发现新 Pod？告警怎么去重和分组？

> 你回答...（提示：服务发现与告警管理 / 服务发现配置：①静态配置→手动写IP→不可扩展 ②文件发现→读JSON/YAML→外部脚本更新→半自动 ③K8s发现→自动发现K8s中的Pod/Service→最常用 ④Consul/Eureka发现→自动发现注册中心的服务 / K8s服务发现工作原理：①Prometheus调K8s API→List Pod→获取所有Pod的IP+端口 ②筛选→有`prometheus.io/scrape=true` annotation的Pod才抓 ③新Pod启动→下一次发现周期（默认5s）→自动加入监控 ④Pod下线→自动移除→不需要手动改配置 / Alertmanager告警去重和分组：①去重→同一个告警多个Prometheus副本都发了→Alertmanager去重→只发一次 ②分组→按标签分组→如`alertname=HighLatency + instance=pod-xxx`→同一实例多个告警合并成一条通知 ③抑制（Inhibit）→高级别告警抑制低级别→如critical发出后→抑制同实例的warning→不重复打扰 ④静默（Silence）→临时静默→如维护期间→不收到告警 ⑤路由→按标签路由到不同通知渠道→critical→PagerDuty+短信→warning→钉钉+邮件 / Alertmanager配置：group_by=[alertname,instance]分组+group_wait=30s收集同组告警+group_interval=5m同组告警间隔+repeat_interval=4h重复告警间隔+routes按severity路由+inhibit_rules(critical抑制同实例warning))

---

## 话题四：gRPC 与 Protobuf（8分钟）

**面试官：你们微服务之间用 Feign 调用？有没有考虑过 gRPC？gRPC 和 REST 有什么区别？Protobuf 序列化为什么快？**

> 你回答...

**追问1：** 先说说 gRPC 是什么。它和 REST/HTTP 有什么本质区别？为什么说 gRPC 性能比 REST 好？

> 你回答...（提示：gRPC vs REST / gRPC 核心：Google开源→基于HTTP/2+Protobuf→高性能RPC框架。定义服务→`.proto`文件→定义接口和消息格式→生成多语言代码（Java/Go/Python）→跨语言。gRPC四种服务类型：Unary（一元：请求→响应，类似REST）/Server Streaming（服务端流：请求→多个响应）/Client Streaming（客户端流：多个请求→响应）/Bidirectional Streaming（双向流：双向实时）/ 和REST本质区别：传输协议→gRPC用HTTP/2→REST用HTTP/1.1。序列化→gRPC用Protobuf（二进制）→REST用JSON（文本）。接口定义→gRPC用.proto（强类型/代码生成）→REST用OpenAPI/Swagger（文档/非强类型）。调用方式→gRPC是RPC（像调本地方法）→REST是HTTP资源操作。流式→gRPC原生支持双向流→REST不支持 / 性能对比：Protobuf二进制→体积小（字段编号+值）→序列化快（二进制直接读写比JSON快10-100倍）→强类型（.proto编译检查）。HTTP/2多路复用→一个TCP连接同时处理多个请求→Stream每请求一个ID→并发传输→不需要多个连接。HTTP/2头部压缩（HPACK）→二进制帧→比HTTP/1.1文本头部小）

**追问2：** Protobuf 的编码原理是什么？字段编号有什么用？Varint 编码是什么？

> 你回答...（提示：Protobuf 编码原理 / Protobuf消息格式：
```protobuf
message Person {
    string name = 1;     // 字段编号1
    int32 age = 2;        // 字段编号2
    bool active = 3;     // 字段编号3
    repeated string emails = 4;
}
```
/ 编码原理——Tag-Length-Value（TLV）：每个字段编码为Tag（字段编号+WireType）+Value。Tag=`(field_number << 3) | wire_type`→Varint编码。WireType：0=Varint(int32/int64/bool/enum) 1=64-bit(fixed64/double) 2=Length-delimited(string/bytes/嵌套message) 5=32-bit(fixed32/float) / Varint编码：核心思想→小数字用少字节→大数字用多字节→变长。每个字节最高位→1=后面还有字节→0=最后一个字节。如数字150→Varint`96 01`（2字节）→而固定int32用4字节。数字1→Varint`01`（1字节） / 字段编号的作用：①不用字段名→用编号→体积小 ②编号1-15→Tag只占1字节→16-2047→Tag占2字节→所以常用字段用小编号 ③字段可以增删→只要编号不变→向前/向后兼容→旧代码不认识新字段→跳过（WireType已知长度）→新代码不认识旧字段→有默认值 ④reserved→删除的字段编号要reserved→防复用 / 和JSON对比编码Person{name="zhang",age=18}：JSON=`{"name":"zhang","age":18}`→24字节。Protobuf=`0A 05 7A 68 61 6E 67 10 24`→10字节→省58%）

**追问3：** gRPC 的拦截器是什么？和 Spring AOP 有什么关系？怎么实现链式调用？

> 你回答...（提示：gRPC 拦截器 / gRPC拦截器（Interceptor）：类似Servlet Filter / Spring AOP→在gRPC调用前后插入逻辑。两种→Server Interceptor（服务端）/ Client Interceptor（客户端）。用途→鉴权/日志/链路追踪（注入traceId）/限流/重试/指标监控 / 服务端拦截器示例：
```java
public class AuthInterceptor implements ServerInterceptor {
    @Override
    public <ReqT, RespT> ServerCall.Listener<ReqT> interceptCall(
            ServerCall<ReqT, RespT> call, Metadata metadata,
            ServerCallHandler<ReqT, RespT> next) {
        String token = metadata.get(Metadata.Key.of("authorization",
            Metadata.ASCII_STRING_MARSHALLER));
        if (token == null || !validateToken(token)) {
            call.close(Status.UNAUTHENTICATED.withDescription("Invalid token"), metadata);
            return new ServerCall.Listener<>() {};
        }
        return next.startCall(call, metadata);
    }
}
```
/ 客户端拦截器→注入traceId到Metadata（类似HTTP Header）→跨服务传递 / 和Spring AOP对比：本质相同→都是"在方法调用前后插入逻辑"。gRPC拦截器是gRPC框架原生→Spring AOP是Spring框架。gRPC用Metadata传递数据→Spring AOP用ThreadLocal/参数。gRPC拦截器链式→多个拦截器顺序执行→类似Filter Chain→逆序返回。Spring Boot gRPC Starter可结合@Component注册拦截器 / 链式调用顺序：客户端→Client Interceptor1→Client Interceptor2→发送请求→服务端→Server Interceptor1（鉴权）→Server Interceptor2（日志）→Server Interceptor3（追踪）→业务方法→响应逆序返回）

**追问4：** gRPC 在浏览器里不能直接用，怎么办？gRPC-Web 是什么？实际项目中 gRPC 和 REST 怎么共存？

> 你回答...（提示：gRPC-Web 与 REST 共存 / gRPC浏览器问题：gRPC基于HTTP/2→浏览器原生不支持HTTP/2的Trailers→不能直接调gRPC。Protobuf二进制→浏览器不能直接编解码→需要JS库（protobuf.js）/ gRPC-Web方案：gRPC-Web=gRPC的浏览器适配层。架构→浏览器（gRPC-Web客户端）→Envoy Proxy（gRPC-Web→gRPC转换）→gRPC服务端。Envoy做协议转换→浏览器发HTTP/1.1→Envoy转成HTTP/2 gRPC→服务端处理→返回→Envoy转成HTTP/1.1→浏览器。前端用`@grpc/grpc-web`库→生成JS代码 / REST和gRPC共存方案：①方案一→gRPC-Gateway→一个.proto文件→生成gRPC代码+生成REST代理→代理把HTTP/JSON转成gRPC调用→内部走gRPC→外部走REST→浏览器友好 ②方案二→Envoy双协议→Envoy同时监听gRPC和HTTP/REST→内部服务间走gRPC→外部客户端走REST→Envoy做转换 ③方案三→gRPC-Web→前端直连→需要Envoy转换 / 实际→内部服务间用gRPC（高性能）→前端用REST或gRPC-Web→网关层做转换。.proto文件可加`option (google.api.http)`标注→gRPC-Gateway自动生成REST端点）

---

## 话题五：ELK 日志体系（8分钟）

**面试官：你们日志怎么收集的？线上出问题怎么查日志？是不是登到服务器上 tail -f？有没有用 ELK？**

> 你回答...

**追问1：** 先说说传统日志排查有什么问题。为什么需要 ELK？ELK 的整体架构是什么？

> 你回答...（提示：传统日志问题与 ELK 架构 / 传统日志排查问题：①登服务器tail -f→微服务几十个实例→一个请求可能跨多个实例→要逐个登→费时 ②grep→文本搜索→不结构化→难统计/聚合 ③日志分散→多台机器→每台一份→找一个请求要全找一遍 ④无法关联→请求A的日志在instance-1→调instance-2→instance-2的日志怎么和A关联？→没有traceId→无法串联 / ELK架构：应用实例→Filebeat（轻量采集器，Go写的，资源少）→Kafka（缓冲→削峰填谷→Logstash处理不过来时积压→不丢日志）→Logstash（过滤/解析Grok正则/JSON解析/加字段traceId/serviceName）→Elasticsearch（存储+全文检索→倒排索引）→Kibana（可视化/查日志/聚合统计/仪表盘）/ 为什么加Kafka：不用Kafka→Filebeat直连Logstash→Logstash处理慢→Filebeat积压→可能丢日志。高峰→日志量大→Logstash处理不过来→Kafka缓冲→削峰→Logstash按自己速度消费→不丢。Logstash挂了→Kafka积压→恢复后继续消费→不丢。Kafka还可以做日志路由→不同应用日志发不同Topic→Logstash分别处理 / EFK（Filebeat替代Logstash做部分处理）：Filebeat 7.0+内置简单日志解析能力→可以替代部分Logstash→减少一层→架构简化→但复杂解析仍需Logstash）

**追问2：** 日志怎么结构化？结构化日志和非结构化日志有什么区别？怎么把 traceId 注入日志？

> 你回答...（提示：结构化日志与traceId / 非结构化日志（传统）：`log.info("用户{}下单，金额{}", userId, amount)`→输出文本→要grep→要正则解析→不能直接统计→Logstash Grok解析→正则脆弱→日志格式变了→Grok匹配不上→维护成本高 / 结构化日志（JSON）：用Logback+`LogstashEncoder`→输出JSON：
```json
{
    "@timestamp":"2026-07-31T10:00:00.000Z",
    "level":"INFO",
    "logger":"com.xxx.OrderService",
    "traceId":"a1b2c3d4",
    "spanId":"e5f6g7h8",
    "userId":"12345",
    "action":"createOrder",
    "amount":100,
    "message":"用户下单"
}
```
Filebeat采集→直接送ES→ES自动识别JSON字段→Kibana可以按userId/amount聚合/统计→不需要Grok→格式稳定维护低 / traceId注入日志：①MDC（Mapped Diagnostic Context）→线程上下文→`MDC.put("traceId", traceId)`→Logback自动从MDC取traceId→写入日志 ②跨服务传递→服务A的traceId→通过HTTP Header/Feign/gRPC Metadata→传到服务B→服务B从请求头取traceId→`MDC.put`→服务B日志也有相同traceId ③Spring Cloud Sleuth/Micrometer Tracing→自动注入→自动生成traceId/spanId→自动通过HTTP Header传递→不需要手动 ④跨线程传递→MDC是ThreadLocal→线程池场景→子线程没有traceId→需要`MDC.getCopyOfContextMap()`传给子线程→`MDC.setContextMap(map)`→Spring的`TaskDecorator`自动包装Runnable→传递MDC→Java 21虚拟线程用ScopedValue替代）

**追问3：** 日志量太大怎么办？ES 存不下怎么处理？日志采样是什么？

> 你回答...（提示：日志量控制 / 日志量大的问题：微服务几十个→每秒万级QPS→每个请求多条日志→日志量TB级→ES存TB贵→搜索慢→每层都可能瓶颈 / 日志量控制策略：①日志级别→生产用INFO→不用DEBUG→DEBUG量大且没什么用→异常用ERROR ②日志采样→不是每条都记→如10%采样→只记10%的INFO日志→ERROR全记 ③异步日志→Logback AsyncAppender→日志写入异步队列→不阻塞业务线程→但可能丢（队列满丢弃）④日志裁剪→Filebeat设置`max_bytes`→截断超长日志 ⑤ES索引生命周期管理（ILM）：hot→近7天→SSD→快速搜索。warm→7-30天→HDD→可以搜索但慢。cold→30-90天→压缩→很少搜。delete→90天+→删除。配置ILM Policy→自动rollover→自动从hot→warm→cold→delete / 日志采样实现：INFO日志10%采样（每10条记1条）→ERROR全记→日志量减少80%+ / ES分片与存储优化：按天建索引`logs-2026.07.31`→方便按天删除/归档。分片数根据数据量→每个分片30-50GB最佳。副本1→高可用但存储翻倍。`index.codec: best_compression`→压缩→省空间。冷日志归档到S3/OSS→需要时恢复）

**追问4：** 查一个慢请求的完整链路怎么做？从 Kibana 怎么查到 traceId 关联的所有服务日志？

> 你回答...（提示：链路日志排查 / 排查流程：①入口→用户反馈"下单慢"→或告警"P99延迟高"②找traceId→如果有traceId→直接搜→如果没有→按时间+用户ID+操作类型搜→找到入口服务日志→拿到traceId ③Kibana搜索traceId→在Kibana Discover→搜索`traceId: "a1b2c3d4"`→按时间排序→看到所有服务关于这个traceId的日志→串联完整链路 ④找慢在哪→看每条日志的时间戳→找时间间隔最大的→如10:00:00→10:00:05→间隔5秒→这段是在调外部接口→定位外部接口慢 ⑤下钻→如果是DB慢→查DB慢日志→Redis慢→查SLOWLOG→下游服务慢→查下游traceId日志 / 多种排查方式：①按traceId→最准→但需要日志中有traceId ②按时间+关键词→`@timestamp:[...] AND message:"createOrder" AND userId:"12345"`→没有traceId时的替代方案 ③按spanId→链路追踪系统（SkyWalking/Jaeger）→更精确→看每个span耗时 ④聚合统计→Kibana按serviceName分组统计错误数→某服务日志突增→可能异常 / 和Prometheus分工：ELK=看日志细节→文本搜索→"出了什么问题"。Prometheus=看指标趋势→数值聚合→"问题多严重/多久一次"。一起用→Prometheus发现问题（QPS下降告警）→ELK查原因（搜日志找错误）→链路追踪定位慢请求）

---

## 话题六：Java 线程池监控与动态调参（8分钟）

**面试官：你们用线程池吗？怎么配的参数？生产环境线程池参数能动态调整吗？不用重启服务那种？**

> 你回答...

**追问1：** 先说说线程池的核心参数怎么配。CPU 密集型和 IO 密集型分别怎么配？

> 你回答...（提示：线程池参数配置 / 核心参数回顾：corePoolSize→核心线程数→常驻。maximumPoolSize→最大线程数→队列满后扩到最大。workQueue→任务队列→常用LinkedBlockingQueue（无界！坑）/ArrayBlockingQueue（有界）/SynchronousQueue（不存）。keepAliveTime→非核心线程空闲存活时间。rejectedExecutionHandler→拒绝策略→AbortPolicy（抛异常）/CallerRunsPolicy（调用者执行）/DiscardPolicy（丢弃）/DiscardOldestPolicy（丢最旧）/ Brian Goetz公式：CPU密集型→`Nthreads = Ncpu + 1`→+1因为偶尔的页面缺失→不需要太多线程→线程多了反而切换开销。IO密集型→`Nthreads = Ncpu * (1 + W/C)`→W=等待时间（IO/网络）/C=计算时间→如W/C=10（90%时间在等IO）→8核→88线程 / 常见配置错误：Executors.newFixedThreadPool(10)→队列LinkedBlockingQueue（无界）→任务堆积→OOM。Executors.newCachedThreadPool()→最大Integer.MAX_VALUE→创建大量线程→OOM。核心线程数设太大→CPU切换开销>计算开销→反而慢。阿里巴巴规范→禁止用Executors→必须new ThreadPoolExecutor→手动配参数)

**追问2：** 生产环境怎么监控线程池？有哪些指标需要关注？线程池满了怎么发现？

> 你回答...（提示：线程池监控 / 监控指标：①getActiveCount()→活跃线程数→正在执行任务的线程→反映繁忙程度 ②getQueue().size()→队列积压数→队列满了→下一步就要拒绝→预警 ③getCompletedTaskCount()→已完成任务数→吞吐量 ④getTaskCount()→总任务数（已完成+队列中+正在执行）⑤getLargestPoolSize()→历史最大线程数→反映峰值 ⑥rejectedCount→拒绝次数→需要自己计数（ThreadPoolExecutor不直接暴露）/ 自定义可监控线程池：继承ThreadPoolExecutor→重写beforeExecute/afterExecute/rejectedExecution→记录任务耗时/异常/拒绝次数→getMetrics()暴露给Prometheus / 监控告警规则：活跃线程数=最大线程数→线程池满载→告警。队列积压>阈值（如80%容量）→预警→即将拒绝。拒绝次数>0→有任务被拒绝→告警。任务平均耗时飙升→任务变慢→可能下游慢 / 动态暴露给Prometheus：Micrometer Gauge.builder("threadpool.active", pool, ThreadPoolExecutor::getActiveCount).tag("name","orderPool").register(registry)→还有queue.size/completed/rejected等)

**追问3：** 线程池参数怎么动态调整？不重启服务能不能改？美团动态线程池方案了解吗？

> 你回答...（提示：动态线程池 / ThreadPoolExecutor支持运行时改参：setCorePoolSize(int)→动态调整核心线程数→立即生效。setMaximumPoolSize(int)→动态调整最大线程数→立即生效。但队列容量→LinkedBlockingQueue的capacity是final→不能改→这是最大限制 / 美团动态线程池（DynamicTp）方案：配置中心（Nacos/Apollo）存线程池参数→修改配置中心→应用监听变更→动态调用setCorePoolSize/setMaximumPoolSize→不重启。还支持反射修改队列capacity（ResizableLinkedBlockingQueue）→或自定义队列提供setCapacity。监听配置变更→解析新参数→调用set方法→反射改队列capacity→更新拒绝策略。还支持告警→参数变更通知→队列满告警→拒绝告警 / 动态调参注意：调大简单→新线程立即创建。调小复杂→超过的线程不会立即停→等空闲到keepAliveTime后回收。队列调大→反射改capacity→新容量要>当前元素数。拒绝策略→setRejectedExecutionHandler立即生效。回滚→配置中心改回去→自动回滚 / 不用框架的简单方案：①暴露管理接口HTTP `/admin/threadpool?core=10&max=50`→不安全（无鉴权）②JMX→ThreadPoolExecutor实现了JMX MBean→JConsole/VisualVM动态改→但生产不方便 ③Spring @RefreshScope+配置中心→监听变更→重建线程池→但重建会丢队列中任务→不如动态调参)

**追问4：** 线程池参数调优的实际经验是什么？怎么找到最优参数？有没有公式可以套？

> 你回答...（提示：线程池调优实战 / 实际经验：①没有万能公式→Brian Goetz公式只是起点→实际要看业务→压测找最优 ②先分类→CPU密集（计算/加密/序列化）→少线程→Ncpu+1。IO密集（DB/Redis/HTTP）→多线程→Ncpu×2~Ncpu×10 ③压测→用JMeter/wrk→逐步增加线程数→看QPS和RT→找拐点→线程数再增加QPS不升但RT升→过了拐点 ④队列→有界→大小=峰值QPS×最大可容忍延迟→如1000QPS×1秒=1000 ⑤拒绝策略→关键业务用CallerRunsPolicy（不丢）→非关键用DiscardPolicy（丢弃）⑥监控→上线后看活跃线程数/队列积压/拒绝次数→持续调整 / 调优流程：确定业务类型→公式给起点→压测找拐点→设队列→上线监控→动态调整→复盘 / 真实案例：①订单系统→IO密集（DB+Redis+下游）→8核→估算Ncpu×(1+10)=88→压测→64线程时QPS最高RT可接受→用64→不用88（88时RT飙升）②搜索系统→CPU密集→8核→Ncpu+1=9→压测→8线程最好→用8 ③异步通知→短任务→队列大→线程少→16线程+1000队列→削峰）

---

## 话题七：Saga 分布式事务模式（8分钟）

**面试官：你们分布式事务用了什么？Seata AT？TCC？Saga 了解吗？Saga 和 TCC 有什么区别？什么场景用 Saga？**

> 你回答...

**追问1：** 先说说 Saga 是什么。它和 2PC/TCC 有什么本质区别？为什么要引入 Saga？

> 你回答...（提示：Saga 原理 / Saga核心思想：长事务→拆成N个短事务（子事务）→每个子事务有对应的补偿事务→如果某个子事务失败→执行之前已成功子事务的补偿事务→回滚。不需要全局锁→每个子事务独立提交→没有全局锁→性能好→但中间状态可见→最终一致 / 和2PC/TCC对比：2PC=2阶段（Prepare+Commit）→全局锁→强一致→性能差→短事务。TCC=3阶段（Try+Confirm+Cancel）→资源冻结→中一致→高侵入→短事务。Saga=N阶段（N个子事务+补偿）→无锁→弱一致（最终一致）→中侵入→长事务/多步骤 / Saga两种实现方式：①编排式（Orchestration）→有一个中央协调器（Orchestrator）→按顺序调用各子事务→成功继续→失败调补偿→逆序执行补偿→Seata Saga用这种 ②协调式（Choreography/舞蹈式）→没有中央协调器→每个子事务完成后发事件→下一个子事务监听事件触发→失败发补偿事件→前面的监听补偿事件执行补偿→类似事件驱动架构 / Saga适用场景：长流程事务（旅行预订：机票+酒店+租车→每步独立→不需要全局锁→不阻塞）。跨多个不同系统（下单+扣库存+扣积分+发券→每步独立）。不适合强一致性→中间状态可见→如果业务不能接受中间状态→用TCC / Saga示例——旅行预订：子事务1→预订机票（Commit）。子事务2→预订酒店（Commit）。子事务3→预订租车（Commit）→失败！补偿2→取消酒店。补偿1→取消机票。最终→机票和酒店都取消了→回到初始)

**追问2：** Saga 的补偿事务怎么设计？补偿能"完美回滚"吗？什么情况补偿不了？

> 你回答...（提示：Saga 补偿设计 / 补偿事务设计原则：①补偿≠回滚→补偿是业务层面的"反向操作"→不是数据库层的undo ②补偿必须幂等→可能被重试 ③补偿必须可执行→即使原事务的部分效果已经传播→补偿也要能执行 ④补偿的顺序→逆序执行→最后成功的先补偿→逐个往前 / 举例——下单流程的补偿：子事务1→创建订单（INSERT）→补偿：UPDATE status='CANCELLED'（不是DELETE→保留记录→审计）。子事务2→扣库存（UPDATE stock-1）→补偿：UPDATE stock+1（加回去）。子事务3→扣余额（UPDATE balance-100）→补偿：UPDATE balance+100。子事务4→发积分（INSERT points）→补偿：UPDATE points status='REVOKED'（不DELETE→保留记录）。补偿顺序→逆序→先撤销积分→回滚余额→回滚库存→取消订单 / 补偿不能"完美回滚"的场景：①已发送的外部消息→如发了短信/邮件→不能"取消发送"→补偿=发一条"取消"通知→但用户已经看到了 ②已调用的外部接口→如调了银行扣款→补偿=调银行退款接口→但退款可能失败/延迟→最终一致 ③已通知下游→如发了MQ消息→下游已经消费了→补偿=发一条"取消"消息→下游自己处理 ④人工操作→如已经通知了仓库发货→补偿=通知仓库"别发了"→但如果已经发了→只能召回→不可逆 / 补偿失败处理：重试→补偿失败→重试3次。人工介入→重试仍失败→告警→人工处理。兜底→对账→定时对账发现不一致→人工修正 / Seata Saga状态机：用状态机定义流程→JSON定义状态→每个状态是一个子事务→有正向和补偿。状态机引擎→按定义执行→成功跳下一个→失败跳补偿→逆序)

**追问3：** Saga 有没有隔离性问题？脏读怎么解决？Saga 和本地消息表有什么关系？

> 你回答...（提示：Saga 隔离性 / Saga隔离性问题——中间状态可见：子事务1→创建订单（Commit）→此时另一个请求能看到这个订单→但整个Saga还没完成→可能会Cancel。子事务2→扣库存（Commit）→库存已扣→但如果后面Cancel→库存要加回去→期间其他请求看到库存已扣→可能影响下单决策。这就是"脏读"→但Saga不保证隔离性→中间状态对其他事务可见 / 解决方案：①业务层加锁→在订单上加状态锁→SELECT FOR UPDATE→但这又回到了全局锁→Saga的优势没了 ②状态机控制→订单状态=PENDING→其他请求看到PENDING→知道还没完成→不依赖→等COMMITTED ③语义锁→子事务1的数据加"临时"标记→其他请求看到"临时"→不依赖→补偿后移除标记 ④TCC的冻结是更好的隔离→但Saga不想冻结→只能用状态控制 / Saga vs 本地消息表：本地消息表→也是最终一致→也是补偿思路→但本地消息表只有2步（业务+消息）→Saga有N步。本地消息表→强依赖MQ→MQ保证最终送达→Saga可以不依赖MQ→直接调接口。本质上→本地消息表是Saga的简化版→2步Saga→一步业务+一步消息（消息的补偿=发取消消息）。选型→简单2步用本地消息表→复杂多步用Saga)

**追问4：** 实际项目中你们用过 Saga 吗？什么场景用的？和 Seata AT/TCC 怎么选型？

> 你回答...（提示：Saga 实际选型 / 选型决策树：①业务能接受最终一致？→不能→2PC/TCC（强一致）②长事务/多步骤？→是→Saga ③短事务/纯DB？→是→AT ④含非DB操作（接口/MQ）→TCC ⑤跨多个不同系统→Saga ⑥2个系统→本地消息表 / 实际使用经验：①银行核心→转账是短事务→用AT或TCC（需要冻结）②电商下单→创建订单+扣库存+扣积分+发券→4步→可以用Saga→但中间状态可见（订单PENDING）→业务能接受→用Saga ③旅行预订→机票+酒店+租车→3个不同系统→Saga编排式→中央协调器按顺序调→失败逆序补偿 ④贷款审批→征信查询+额度计算+合同签署+放款→长流程→Saga→但放款不能回滚（已打款）→补偿=发起冲正→最终一致 / 分布式事务选型总结：2PC/XA→强一致/差性能/低侵入/数据库内部。Seata AT→弱一致（最终）/中性能/低侵入/纯DB短事务。TCC→强一致（冻结）/好性能/高侵入/含非DB/金融。Saga→弱一致（最终）/好性能/中侵入/长事务多系统。本地消息表→弱一致/好性能/中侵入/2系统MQ。事务消息→弱一致/好性能/中侵入/RocketMQ。大部分场景→本地消息表/事务消息→简单够用。需要冻结/预留→TCC→金融。长流程多步骤→Saga→旅行/审批。纯DB短事务→AT→开发效率高。不用框架→手写本地消息表→最可控)

---

## 话题八：手写代码 - 前 K 个高频元素（8分钟）

**面试官：给你一个整数数组和一个整数 K，返回出现频率最高的前 K 个元素。比如 [1,1,1,2,2,3]，K=2，返回 [1,2]。写一下。**

你在纸上/白板上写代码...

**追问1：** 先说说思路。有哪些方法？最直观的是什么？最优的是什么？

> 你回答...（提示：前K高频元素思路 / 方法一：排序法→统计频率HashMap→按频率排序降序→取前K→O(n log n)。方法二：最小堆→统计频率HashMap→遍历HashMap维护大小为K的最小堆→堆顶是K个里频率最低的→如果当前频率>堆顶→替换堆顶→堆化O(log k)→遍历完堆中就是TopK→O(n log k)。方法三：桶排序→统计频率HashMap→按频率分桶bucket[freq]=[num1,num2]→从高到低遍历桶→取前K→O(n) / 最小堆代码：
```java
public int[] topKFrequent(int[] nums, int k) {
    // 1. 统计频率
    Map<Integer, Integer> freq = new HashMap<>();
    for (int num : nums) {
        freq.merge(num, 1, Integer::sum);
    }
    // 2. 最小堆（按频率排序）
    PriorityQueue<Integer> heap = new PriorityQueue<>(
        (a, b) -> freq.get(a) - freq.get(b)  // 小顶堆：频率小的在堆顶
    );
    // 3. 遍历维护大小为K的堆
    for (int num : freq.keySet()) {
        heap.offer(num);
        if (heap.size() > k) {
            heap.poll();  // 堆顶（最小的）出堆
        }
    }
    // 4. 堆中就是TopK
    int[] result = new int[k];
    for (int i = 0; i < k; i++) {
        result[i] = heap.poll();
    }
    return result;
}
```
/ 为什么用最小堆而不是最大堆：我们只要前K个→不需要全部排序。最小堆→堆顶是K个里最小的→来了新的→比堆顶大→替换→否则跳过→每次只O(log k)。最大堆→要全部入堆→O(n log n)→然后取K个→不如最小堆。类比→找100个人中最高的3个→你只需要维护3个最矮的"候选"→新来的和最矮的比→比他高就替换→最后这3个就是最高的 / 桶排序：频率做index→bucket[freq]存该频率的所有数字→从高到低遍历桶取K个→O(n)但频率分布不均时空间浪费 / 三种对比：排序法O(nlogn)/最小堆O(nlogk)/桶排序O(n)。K远小于n用最小堆。频率均匀用桶排序）

**追问2：** 如果数据量特别大（比如流式数据，内存放不下），怎么办？

> 你回答...（提示：海量数据 Top K / 问题：10亿条数据→内存放不下HashMap→不能全部统计频率 / 方案一：分治+堆→把数据分成N块→每块内存能放下→每块分别统计频率+求该块的TopK（最小堆）→N个TopK→合并→再求一次TopK→最终结果。类似MapReduce→Map阶段分块统计→Reduce阶段合并求全局TopK / 方案二：Count-Min Sketch（近似统计）→概率数据结构→类似布隆过滤器→多个hash函数→多个计数器→空间固定（如1MB）→估算频率→有误差（高估）→适合数据量极大→精确频率不重要→近似就够。streaming场景→实时统计TopK→不可能全量精确 / 方案三：分桶+外部排序→按hash分到多个文件→同一元素在同一文件→每个文件分别求TopK→合并→全局TopK→类似分治。精确用分治/近似用Count-Min Sketch）

**追问3：** 如果 K 很大（比如 K = n/2，求前一半），最小堆还合适吗？

> 你回答...（提示：大K场景 / 最小堆在大K时的问题：K=n/2→堆大小n/2→每次O(log(n/2))→总O(n log(n/2))≈O(n log n)→和排序法一样了→没有优势。K很大→最小堆退化为排序→没意义 / 大K场景更优方案：①快速选择（QuickSelect）→类似快速排序的partition→每次选pivot→分两区→看pivot位置→递归只处理一边→平均O(n)→最坏O(n²)（随机pivot避免）②桶排序→O(n)→但前提是频率分布均匀 ③直接排序→O(n log n)→K大时和最小堆差不多→简单直接 / QuickSelect核心：找第K大→升序排第K大在len-k位置→partition→pivotIndex==k则找到→pivotIndex<k在右边递归→pivotIndex>k在左边递归→只递归一边→平均O(n) / 面试重点：K小用最小堆O(nlogk)→K大用QuickSelect O(n)→K=n直接排序）

---

# 二面（30分钟）

## 话题九：开放银行（Open Banking）业务（10分钟）

**面试官：你了解开放银行吗？中信银行在推开放银行平台。Open Banking 和传统银行接口有什么区别？技术上要解决什么问题？**

> 你回答...

**追问1：** 先说说开放银行是什么。它和传统的银企直连有什么区别？

> 你回答...（提示：开放银行概念 / 开放银行（Open Banking）：核心思想→银行把金融服务能力封装成API→通过开放平台暴露给第三方（fintech/电商/政企）→第三方调用API→嵌入自己的场景→银行服务"走出银行"。如→电商平台调银行API→用户在电商付款时直接看到银行分期选项→不用跳银行App→银行服务嵌入场景 / 和银企直连的区别：银企直连→一对一→每个企业单独对接→私有协议→专线→慢但安全。开放银行→一对多→标准API→互联网→自助接入→快→但安全挑战大。对接方式=点对点专线 vs 互联网API。合作方=少数大企业 vs 多种第三方。接入效率=月级 vs 天级。标准=私有协议 vs 标准API+OAuth2。安全=专线/白名单 vs OAuth2+签名+加密 / 开放银行技术挑战：①标准化→API统一规范→行业标准（PSD2/人行标准）②安全→互联网暴露→OAuth2授权+API签名+数据加密+风控 ③多租户→不同合作方→不同权限→不同配额→限流 ④版本管理→API升级→不能影响存量→多版本共存→废弃通知 ⑤运维→大量合作方→API调用监控→计费→对账)

**追问2：** 开放银行的安全怎么做？第三方怎么接入？OAuth2 在这里怎么用？

> 你回答...（提示：开放银行安全设计 / 接入流程：①注册→第三方在开放平台注册→审核→获取API Key+Secret ②创建应用→选择需要的API→申请权限→审批 ③获取Token→OAuth2→客户端凭证模式（Client Credentials）→服务对服务调用→不需要用户参与→用API Key+Secret换Token→Token有效期2小时 ④调用API→带Token→签名→调用 ⑤如果是用户授权场景→授权码模式（Authorization Code）→用户在银行页面授权→第三方拿到授权码→换Token→调用户相关API / OAuth2两种模式：客户端凭证=服务对服务(无用户)→API Key+Secret→Token。授权码=用户授权场景→用户授权→授权码→Token。如查公开汇率→客户端凭证（不需要用户信息）。查用户余额→授权码（需要用户授权）/ API签名：签名=请求参数+时间戳+Nonce+API Secret→HMAC-SHA256→生成签名。服务端验签→同样计算→对比→防篡改。时间戳→防重放→超过5分钟的请求拒绝。Nonce→防重放→一次性随机数→Redis存5分钟→重复拒绝 / 安全层级：①API Gateway→限流（每合作方不同配额）②Token验证→OAuth2校验→过期/无效拒绝 ③签名验证→HMAC-SHA256→防篡改 ④权限校验→合作方有没有调这个API的权限 ⑤数据脱敏→敏感字段脱敏（手机号138****5678）⑥审计→记录调用日志（合作方/API/参数/结果/耗时）→业务处理)

**追问3：** API 的版本管理和废弃怎么做？不能影响存量合作方？

> 你回答...（提示：API版本管理 / 版本管理策略：①URL版本→`/v1/account/query`→`/v2/account/query`→多版本共存→新功能加v2→不改v1→存量不受影响 ②Header版本→`Accept: application/vnd.bank.v1+json`→不在URL体现→但不直观 ③实际→URL版本最常用→简单直观 / 废弃流程：①标记废弃→API文档标注`@Deprecated`→响应Header加`Sunset: Sat, 31 Dec 2026 23:59:59 GMT`→告知废弃时间 ②通知→邮件/短信/站内信→提前6个月通知合作方 ③过渡期→v1和v2共存→6个月→合作方迁移 ④监控→监控v1调用量→当v1调用量<阈值→可以下线 ⑤下线→v1返回410 Gone→合作方必须用v2→但如果还有大客户没迁→不能下线 / 兼容性原则：加字段→兼容→新版本可以加字段→旧版本忽略→不影响。删字段→不兼容→旧版本依赖这个字段→不能直接删→先标记废弃→等人不用→再删。改字段类型→不兼容→必须新版本。改语义→不兼容→如v1的status=1表示成功→v2改成status=SUCCESS→不能改→新版本用新字段)

---

## 话题十：核心设计题 - 银行开放平台系统（20分钟）

**面试官：中信银行要建一个开放银行平台。支持 500+ 合作方接入，1000+ API，日均调用量亿级。怎么设计这个系统？**

> 你回答...

**追问1：** 先说说整体架构。开放平台从接入到业务处理经过哪些层？

> 你回答...（提示：整体架构 / 分层架构：①API Gateway层→统一入口→Nginx/Spring Cloud Gateway→限流（按合作方配额）→鉴权（Token验证）→路由（API路径路由到适配层）→签名验证（HMAC-SHA256）→IP白名单 ②开放平台层→合作方管理（注册/审核/上下线）→应用管理（创建应用/分配Key+Secret/选API）→API管理（API注册/版本/文档）→权限管理（合作方+应用+API三级权限）→计费（按调用量计费）→审计（调用日志）→监控（调用量/成功率/RT）③适配层→协议转换（开放标准API→银行内部接口）→数据脱敏（手机号/身份证号脱敏）→参数校验→细粒度限流→降级→熔断 ④核心业务→银行已有系统→不改 / 技术选型：Gateway→Spring Cloud Gateway（WebFlux非阻塞）或Apisix（高性能）。合作方管理→MySQL+Redis缓存→微服务。限流→Gateway层粗粒度+Sentinel细粒度。审计→Kafka→ES→Kibana→日志检索→Kafka削峰→不直接写ES。计费→Kafka消息→消费者聚合→日/月账单)

**追问2：** 限流怎么做？500+ 合作方，不同合作方不同配额。日均亿级调用，怎么扛？

> 你回答...（提示：限流设计 / 限流维度：①合作方级别→每个合作方每秒/每天配额→大客户1000QPS/小客户100QPS ②API级别→不同API不同限流→查询类500QPS/交易类50QPS ③合作方+API级别→组合→精确控制 / 多级限流：①Gateway层→粗粒度→按合作方IP/Token→Redis令牌桶→防止一个合作方打爆网关 ②应用层Sentinel→细粒度→按合作方+API→Sentinel规则→动态调整 ③下游保护→调核心业务→超时+熔断→不打爆核心 / Redis限流方案：令牌桶→按合作方配额生成令牌→取令牌→有则通过→无则拒绝。多维度→`rate_limit:{partnerId}`合作方级→`rate_limit:{partnerId}:{apiCode}`API级。Lua脚本原子执行 / 应对亿级调用：①Gateway无状态→横向扩展→N台→分担流量 ②Redis集群→分片→不单点 ③缓存→Token验证结果缓存→不每次查DB→Redis缓存合作方信息 ④异步审计→不阻塞请求→Kafka→后台写ES ⑤降级→核心业务不可用→返回降级数据)

**追问3：** 审计日志怎么做？每天亿级调用，怎么存？怎么查？怎么计费？

> 你回答...（提示：审计与计费 / 审计日志设计：①记录什么→合作方ID/应用ID/API路径/请求参数(脱敏)/响应状态/耗时/时间戳/TraceId ②写哪里→Kafka（异步不阻塞请求）→消费者→ES（检索）+MySQL（计费聚合）③不直接写ES→亿级/天→ES写入慢→Kafka削峰→消费者慢慢写 / Kafka→ES→Kibana：请求完成→发Kafka消息→不等→立即返回响应给合作方。消费者从Kafka读→写ES→按天索引`audit-2026.07.31`。Kibana→搜日志→按合作方/API/时间/状态搜索→排查问题。ILM→7天热→30天温→90天删 / 计费设计：Kafka消息→消费者聚合→每合作方每API每天调用量。按调用量计费→如0.01元/次→或包月/阶梯价。日账单→每天跑批→聚合当天调用量→计算费用→生成账单。月账单→月初→上月日账单汇总→发账单→开票。对账→调用日志（ES）vs计费记录（MySQL）→对比→差异处理)

**追问4：** 安全方面，如果合作方的 API Secret 泄露了怎么办？怎么发现和应急？

> 你回答...（提示：安全应急 / Secret泄露的风险：攻击者拿到API Key+Secret→可以生成Token→调用所有该合作方有权限的API→查用户数据/发起交易 / 发现机制：①异常调用检测→IP异常（合作方通常从固定IP调用→突然从陌生IP）→调用量异常（突然激增）→调用模式异常（突然调大量查询接口）②合作方主动报告→发现内部泄露→通知银行 ③安全审计→定期审计→Secret没有硬编码→日志没有打印 / 应急流程：①立即禁用→`UPDATE partner_app SET status='DISABLED' WHERE app_id=?`→Token立即失效→调用被拒 ②通知合作方→通知→重新生成Secret→合作方用新Secret ③排查→查异常期间的调用日志→看有没有数据泄露→有则上报→数据保护法 ④改进→Secret轮换→每90天强制换→Secret加密存储→不明文→日志脱敏 / 多重安全保障：①Secret不明文存储→加密（AES）→DB中存密文→用时解密 ②Token短时效→2小时过期→即使Token泄露→2小时后失效 ③IP白名单→合作方IP固定→只允许白名单IP→泄露的Secret从其他IP用不了 ④数据脱敏→手机号/身份证号/卡号→脱敏返回→38****5678 ⑤风控→异常调用检测→实时告警→自动降级（限制QPS）或自动禁用 ⑥双因素→敏感API（如交易）→除了Token→还需要二次验证（短信验证码/动态口令）→仿冒支付验证)

**追问5：** 如果核心业务系统出了问题，开放平台怎么降级？不能让合作方的请求全部超时？

> 你回答...（提示：降级设计 / 降级策略：①读类API→缓存降级→查余额→核心不可用→返回缓存的上次余额+标记"数据可能不是最新"→合作方知道是降级→不当准确数据用 ②写类API→快速失败→不能降级→如转账→核心不可用→直接返回"服务暂不可用"→不能假成功→宁可拒绝也不能错误处理 ③非核心API→直接降级→如查公告/查网点→返回空或默认 ④核心API→熔断→连续失败→熔断→快速失败→不等超时→减少核心压力 / 降级实现：Sentinel→@SentinelResource(fallback=...)→降级方法→返回降级数据。熔断→熔断器状态机（Closed→Open→Half-Open）→Open时快速失败。超时→设短超时（如3s）→不等核心→3s超时→降级。网关层降级→Gateway→如果后端不可用→返回503+降级数据 / 降级数据规范：统一降级响应→`{"code":"DEGRADED","message":"服务降级","data":{...},"degraded":true}`→合作方看`degraded=true`→知道是降级数据→不当准确数据。不同API不同降级数据→查余额→缓存值→查网点→默认列表→转账→不降级→返回失败)

**追问6：** 整个平台的高可用怎么设计？如果开放平台自身挂了，合作方怎么办？

> 你回答...（提示：开放平台高可用 / 高可用分层：①Gateway→多副本+负载均衡→无状态→挂了不影响其他→自动剔除 ②开放平台服务→微服务→多副本→注册中心→挂了自动转移 ③Redis→集群→主从+哨兵→高可用 ④MySQL→主从+MHA→主挂了自动切换从 ⑤Kafka→集群→多副本→高可用 ⑥核心业务→银行核心系统→自身高可用 / 合作方降级方案：①开放平台挂了→合作方调不通→超时→合作方应该有自己的降级→如电商付款→银行API不可用→引导用户用其他支付方式→不影响电商主流程 ②SDK→银行提供SDK→内置超时+重试+降级→合作方接入SDK→不用自己处理 ③本地缓存→合作方缓存非实时数据→如网点列表→API不可用→用本地缓存 ④告警通知→开放平台故障→主动通知合作方→"平台故障，预计30分钟恢复"→合作方知道→做降级 / RTO/RPO：Gateway/服务→RTO<30s→自动切换→无数据丢失。Redis→RTO<10s→哨兵切换→少量数据丢失（异步复制）。MySQL→RTO<30s→MHA切换→RPO≈0（半同步复制）。Kafka→RTO<30s→副本切换→RPO≈0（多副本同步）)

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| TCC 分布式事务（AT局限/Try-Confirm-Cancel/空回滚/悬挂/幂等/事务日志表/Seata vs Hmily/冻结额度落地） | 能讲清 / 讲不全 / 不会★ | |
| Redis Stream（List问题/消费组/PEL/XCLAIM/选型/MAXLEN内存控制） | 能讲清 / 讲不全 / 不会★ | |
| Prometheus + Grafana（架构/Pull vs Push/四种指标/PromQL/服务发现/Alertmanager去重分组抑制） | 能讲清 / 讲不全 / 不会★ | |
| gRPC 与 Protobuf（vs REST/HTTP2多路复用/TLV编码/Varint/字段编号/拦截器/gRPC-Web/REST共存） | 能讲清 / 讲不全 / 不会★ | |
| ELK 日志体系（架构/Filebeat+Kafka+Logstash+ES/结构化JSON/MDC traceId/日志采样/ILM/链路排查） | 能讲清 / 讲不全 / 不会★ | |
| 线程池监控与动态调参（Goetz公式/监控指标/MonitorableThreadPool/美团DynamicTp/调优实战） | 能讲清 / 讲不全 / 不会★ | |
| Saga 分布式事务（vs 2PC/TCC/编排式vs协调式/补偿设计/不能完美回滚/隔离性/选型决策树） | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（前K高频元素/最小堆O(nlogk)/桶排序O(n)/海量数据分治/QuickSelect大K） | 能讲清 / 讲不全 / 不会★ | |
| 开放银行（概念/银企直连对比/OAuth2两种模式/API签名/版本管理/废弃流程） | 能讲清 / 讲不全 / 不会★ | |
| 银行开放平台系统设计（四层架构/多级限流/审计Kafka→ES/计费聚合/Secret泄露应急/降级策略/高可用） | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **TCC 分布式事务**：AT局限=脏读(一阶段提交)+全局锁竞争+只支持SQL。TCC=Try(资源预留/冻结额度)→Confirm(确认扣款/幂等)→Cancel(取消预留/幂等)。三大坑=①空回滚(Try没执行但Cancel被调→查日志表没Try记录→空回滚标记) ②悬挂(Try超时→先Cancel→后Try到达→Try前查有Cancel→拒绝) ③幂等(Confirm/Cancel重试→查status已执行→跳过)。核心=事务日志表(xid+branchId+status)。Seata TCC(和AT共用TC/同步Confirm/一致性好/TC单点) vs Hmily(无TC/异步Confirm/性能好/一致性窗口长)。银行选Seata TCC。冻结额度=account表(balance+frozen_amount+version乐观锁)→可用=balance-frozen
> 2. **Redis Stream**：List问题=无ACK(崩溃丢)+无消费组+无历史+Pub/Sub不持久。Stream=持久化+消费组(每条只一个消费者)+ACK机制(PEL未确认列表→XACK后移除→崩溃不丢)+历史回溯(XRANGE)+阻塞读(XREAD BLOCK)。PEL=per-consumer已取未ACK列表→崩溃等恢复或XCLAIM转移(检查超时未ACK→转移给空闲消费者)→XAUTOCLAIM(6.2+)自动转移。选型=轻量级(不部署Kafka)+万级QPS+小量+需ACK→不适合高吞吐(Kafka)/大数据量(TB)/事务消息(RocketMQ)。MAXLEN~N裁剪+内存控制
> 3. **Prometheus + Grafana**：架构=Server(TSDB+Pull+HTTP)+Exporter(/metrics)+Pushgateway(短任务)+Alertmanager(去重分组路由通知)+Grafana。Pull vs Push=Prometheus控制拉取(拉不到=告警/不会打爆) vs 应用控制推送(可能推太快)。四种指标=Counter(只增不减→rate()算QPS)+Gauge(可增可减→直接看)+Histogram(分桶/服务端算分位数/跨实例聚合→推荐)+Summary(客户端算分位数/精确/不可聚合→不推荐)。PromQL：QPS=rate(total[5m])→P99=histogram_quantile(0.99,sum(rate(bucket[5m]))by(le))→多实例=sum(rate())→告警=expr+for(持续N分钟防误报)。服务发现=K8s(Prometheus调API→List Pod→筛选annotation→自动加入/下线移除)。Alertmanager=去重+分组(group_by)+抑制(critical抑制同实例warning)+静默+路由(severity→不同渠道)
> 4. **gRPC 与 Protobuf**：gRPC=HTTP/2+Protobuf+跨语言(.proto生成代码)→vs REST=HTTP/2多路复用 vs HTTP/1.1/Protobuf二进制 vs JSON文本/强类型 vs 弱/原生双向流。Protobuf编码=TLV(Tag=字段编号+WireType+Value)→Tag=(field_number<<3)|wire_type→WireType:0 Varint/1 64-bit/2 Length-delimited/5 32-bit→Varint=小数字少字节(最高位1=还有/0=最后)→字段编号1-15占1字节Tag→增删兼容(旧代码跳过新字段/新代码默认值)→reserved防复用。拦截器=类似Filter/AOP→Server(鉴权/日志/追踪)+Client(注入traceId)→Metadata类似HTTP Header→链式顺序执行逆序返回。gRPC-Web=浏览器→Envoy转换→gRPC服务端。REST共存=gRPC-Gateway(.proto生成gRPC+REST代理→内部gRPC外部REST)
> 5. **ELK 日志体系**：架构=Filebeat(轻量采集)→Kafka(缓冲削峰不丢)→Logstash(过滤解析Grok/JSON+加字段)→ES(倒排索引全文检索)→Kibana(可视化)。加Kafka=Logstash处理慢时缓冲→不丢→Logstash挂了恢复后继续。结构化日志=JSON(Logback LogstashEncoder)→Filebeat直送ES自动识别字段→Kibana按字段聚合→不需要Grok正则→格式稳定。traceId=MDC.put→Logback自动取→跨服务HTTP Header/Feign/gRPC Metadata传递→Spring Cloud Sleuth自动→跨线程MDC.getCopyOfContextMap+setContextMap/TaskDecorator。日志量控制=级别(INFO不用DEBUG)+采样(10%INFO/ERROR全记)+异步(AsyncAppender)+ES ILM(hot7天SSD→warm30天HDD→cold90天压缩→delete)。排查=traceId搜Kibana→时间排序串联链路→找时间间隔最大段→下钻(DB慢日志/Redis SLOWLOG/下游traceId)。和Prometheus=ELK看日志细节"什么问题"+Prometheus看指标趋势"多严重"
> 6. **线程池监控与动态调参**：Goetz公式=CPU密集Ncpu+1/IO密集Ncpu×(1+W/C)。错误=Executors无界队列OOM+MAX线程OOM+核心太大切换开销→阿里规范禁止Executors。监控=getActiveCount(活跃)+queue.size(积压预警)+completedTaskCount(吞吐)+rejectedCount(拒绝→需自己计数)。自定义线程池=继承ThreadPoolExecutor+重写beforeExecute/afterExecute/rejectedExecution+getMetrics暴露Prometheus。动态调参=setCorePoolSize/setMaxPoolSize(立即生效)→但队列capacity是final改不了。美团DynamicTp=Nacos存参数→监听变更→set方法+反射改队列capacity→不重启。调大简单→调小等keepAliveTime回收。调优=没有万能公式→Goetz是起点→压测找拐点→队列=峰值QPS×可容忍延迟→关键业务CallerRunsPolicy不丢→上线监控→动态调整→复盘
> 7. **Saga 分布式事务**：Saga=长事务拆N个短子事务→每个有补偿→失败逆序执行补偿→无全局锁→最终一致。vs 2PC=无锁vs全局锁/最终vs强一致/性能好vs差。vs TCC=N阶段vs3阶段/无锁vs冻结/长事务vs短事务。两种实现=编排式(中央协调器→Seata Saga)vs协调式(事件驱动→无中央)。补偿=≠回滚(业务反向操作)+幂等+逆序。不能完美回滚=已发短信/已调银行/已发MQ/已通知仓库。隔离性问题=中间状态可见→解决=状态机控制(PENDING不依赖等COMMITTED)+语义锁。vs本地消息表=本质2步Saga(业务+消息)。选型=最终一致→长事务多步用Saga→纯DB短事务用AT→含非DB用TCC→2系统用本地消息表
> 8. **前K高频元素**：三种=排序法O(nlogn)+最小堆O(nlogk)+桶排序O(n)。最小堆=维护K大小小顶堆→当前>堆顶替换→O(logk)。为什么小顶堆不大顶堆=只要前K→维护K个最矮候选→新来比最矮高则替换。桶排序=频率做index→O(n)但分布不均时空间浪费。海量数据=分治+堆(分N块→每块TopK→合并→再求TopK→MapReduce)或Count-Min Sketch(多hash+固定空间→估算频率)。大K=最小堆退化为排序→用QuickSelect(快排partition→只递归一边→平均O(n))
> 9. **开放银行**：银行金融服务封装API→开放平台暴露给第三方→嵌入场景(电商付款看银行分期不跳App)。vs银企直连=一对一专线私有协议慢→一对多标准API互联网自助快。安全=OAuth2(客户端凭证=服务对服务/授权码=用户授权)+API签名(参数+时间戳+Nonce+Secret→HMAC-SHA256→防篡改+防重放)+IP白名单+数据脱敏+风控异常检测+敏感API二次验证。版本=URL版本(/v1/→/v2/共存→存量不影响)。废弃=@Deprecated+Sunset Header→提前6月通知→过渡期→监控v1调用量<阈值→下线410 Gone。兼容=加字段兼容/删字段不兼容先废弃
> 10. **银行开放平台设计**：四层=API Gateway(限流+鉴权+路由+签名+IP白名单)→开放平台(合作方/应用/API/权限/计费/审计/监控)→适配层(协议转换+脱敏+校验+细粒度限流+降级熔断)→核心业务(已有不改)。限流=多级(Gateway粗Redis令牌桶→Sentinel细合作方+API→下游超时熔断)。审计=Kafka异步不阻塞→消费者写ES(按天索引)+Kibana搜索→ILM(7/30/90天)。计费=Kafka消息→消费者聚合(每合作方每API每天调用量)→日账单跑批→月账单汇总→对账。Secret泄露=异常检测(IP/调用量/模式)+立即禁用+重新生成Secret+排查日志+改进(90天轮换/加密存储/日志脱敏)。降级=读类缓存降级+写类快速失败(不假成功)+非核心返回默认+核心熔断→统一降级响应(degraded=true标记)。高可用=Gateway无状态横向扩展+Redis集群+MySQL主从MHA+Kafka多副本→合作方降级(SDK内置超时重试+本地缓存+主动通知故障)