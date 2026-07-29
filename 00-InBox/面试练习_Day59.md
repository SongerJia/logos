# 面试模拟 - Day 59

> 日期：2026-07-29（周三） | 模拟岗位：顺丰科技（杭州）- 供应链金融科技部 - Java开发工程师
> 建议时长：100分钟（一面70分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day59，"查漏补缺"阶段第八周。模拟顺丰科技杭州研发中心——供应链金融科技部。顺丰有支付牌照、保理牌照、小贷牌照，做供应链金融（应收账款融资/保理/仓单质押）、顺丰支付（企业钱包/代收代付）。面试特点：偏工程实战、追问连环深挖、系统设计和供应链场景强相关。今天引入 **消息积压处理、Redis Lua 脚本、Spring Cloud OpenFeign 原理、Redlock 算法争议、Java 注解处理器(APT)、MySQL 读写分离架构、Spring 定时任务与分布式调度** 7个全新技术话题 + 供应链金融业务 + 拓扑排序手写代码——覆盖之前碎片提到但没有作为独立话题系统考过的高频核心考点。每话题3-4个追问，模拟真实面试连环深挖。

---

# 一面（70分钟）

## 话题一：消息积压处理与消费者优化（10分钟）

**面试官：你用过 Kafka 和 RocketMQ 吧？生产环境消息积压过吗？怎么处理的？**

> 你回答...

**追问1：** 先说说怎么发现积压。你们监控了哪些指标？积压到什么程度告警？

> 你回答...（提示：积压发现与监控 / 核心指标：①`ConsumerLag`（Kafka）= 消费者已消费的 offset 与分区最新 offset（HW）的差值 → lag > 0 说明消费跟不上生产 ②RocketMQ 用 `消息堆积量` → 控制台看消费者组的堆积条数 ③监控维度：每个分区/每个消费者实例/每个 Topic → 不能只看总量 → 某个分区积压而其他正常 → 说明分区不均衡 / 某个消费者卡住 / 告警阈值：①根据业务 SLA 设定 → 如实时风控消息延迟 > 5s 告警 / 营销消息 > 1小时告警 ②堆积量阈值 → 如 > 10万条告警 / > 100万条严重告警 ③消费者 TPS 突降 → 正常 5000 TPS → 突然降到 100 → 立刻告警 ④生产 TPS 突增 → 营销活动流量突增 → 生产量远超消费能力 / 监控工具：①Kafka → Kafka Manager / KafkaDrop / Prometheus + kafka_exporter ②RocketMQ → RocketMQ Console + Prometheus + rocketmq_exporter ③告警 → Grafana 阈值告警 / 钉钉/企微机器人通知 / 面试重点：ConsumerLag=消费offset与HW差值→lag>0=积压 → 监控=每个分区/消费者/Topic维度 → 告警=延迟阈值+堆积量+TPS突降+生产突增 → 工具=Prometheus+exporter+Grafana）

**追问2：** 积压的原因有哪些？你怎么排查是哪个原因？

> 你回答...（提示：积压原因排查 / 消费慢的原因分类：①消费者处理慢 → 最常见 → 单条消息处理耗时过长 → 如 DB 慢查询 / 外部接口超时 / 大对象序列化 ②消费者实例不够 → 生产 TPS 50000 → 消费者只有 2 个 → 每个要处理 25000 TPS → 处理不过来 ③分区数不够 → Kafka 分区 = 消费者并发上限 → 6 分区最多 6 个消费者并发 → 生产 TPS 远超 6 个消费者能力 ④消费者异常 → OOM / GC 停顿 / 线程池满 / 死锁 → 消费者存活但不处理 ⑤Rebalance 频繁 → 消费者加入/退出 → 触发 Rebalance → STW → 消费暂停 ⑥消息不均衡 → 某个分区消息特别多（按 userId hash → 大客户消息集中在一个分区）→ 该分区积压 / 排查流程：①先看 ConsumerLag 趋势 → 突然飙升 vs 缓慢增长 → 突然 = 消费者挂了 / 缓慢 = 消费能力不足 ②看消费者实例状态 → 存活数 / TPS / 延迟 → 如果 TPS=0 → 消费者卡住了 → jstack 看线程在干什么 ③看单条消息处理耗时 → 如正常 10ms → 现在 500ms → 下游依赖慢了 ④看 DB / Redis / 下游接口 → 慢查询 / 连接池满 / 接口超时 ⑤看 GC → jstat → Full GC 频繁 → STW 消费暂停 ⑥看 Rebalance 日志 → 频繁 Rebalance → 消费者心跳超时 → 调大 session.timeout / 面试重点：原因=消费慢(下游依赖慢)/实例不够/分区不够/消费者异常(GC/OOM)/Rebalance频繁/消息不均衡 → 排查=ConsumerLag趋势(突然=挂了/缓慢=不够)+消费者TPS+单条耗时+下游依赖+GC+Rebalance日志）

**追问3：** 确认是消费能力不足，怎么快速恢复？消费者怎么扩容？

> 你回答...（提示：快速恢复与扩容 / 临时方案（紧急恢复）：①增加消费者实例 → 但受分区数限制 → Kafka 分区 6 个 → 消费者 > 6 也没用 → 多余的空闲 ②如果分区不够 → 临时增加分区 → `kafka-topics.sh --alter --partitions 12` → 但注意：增加分区后消息路由变了 → 旧分区消息继续按旧路由 → 新分区只接收新消息 → 消费者要重新分配 ③消费者内部线程池扩容 → 单个消费者实例内部用线程池并行消费 → 如 1 个消费者 20 个线程 → 相当于 20 个虚拟消费者 → 但注意消息顺序性（同 key 要同线程）④跳过非关键消息 → 如日志类消息 → 直接 skip → 先消化关键业务消息 ⑤临时降级 → 消费者只做核心处理 → 跳过非核心步骤（如通知/日志/统计）→ 后台补偿 / 根本方案（长期）：①增加分区数 → 和消费者实例数对齐 → 分区 12 + 消费者 12 = 并行 12 ②消费者多线程消费 → 内部线程池 → 按 key hash 保证同 key 顺序 ③批量消费 → `max.poll.records=500` → 一次拉 500 条 → 批量处理 → 减少网络往返 ④优化单条处理耗时 → 慢 SQL 优化 / 缓存 / 异步化非核心步骤 ⑤下游限流 → 如果下游 DB 扛不住 → 消费者侧限流 → 控制消费速率 → 不压垮下游 ⑥扩容消费者实例 → K8s 动态扩缩 → HPA 根据 ConsumerLag 自动扩容 / 面试重点：临时=加消费者实例(受分区限制)/加分区/内部线程池扩容/跳过非关键消息/临时降级 → 根本=分区和消费者对齐/多线程/批量消费(max.poll.records)/优化单条耗时/下游限流/K8s自动扩缩 → 注意分区数=消费者并发上限）

**追问4：** 积压了 1000 万条消息，消费完要 2 小时，但业务要求 10 分钟内处理完。除了加消费者还能怎么办？

> 你回答...（提示：极端积压处理 / "一个消费者写 + 多个消费者读"方案：①场景 → 1000 万条积压 → 正常消费 TPS 5000 → 需要 2000 秒 ≈ 33 分钟 → 要求 10 分钟 → 需要 TPS 16667 → 常规扩容不够 ②方案 → 临时 Topic + 多消费者组 → 写一个"中转消费者" → 快速从积压 Topic 消费 → 不做业务处理 → 直接转发到一个新 Topic（分区数 = 50）→ 新 Topic 有 50 个分区 → 50 个消费者并行消费 → TPS 大幅提升 ③流程 → 积压 Topic（6 分区）→ 中转消费者（只转发不做业务，TPS 极高）→ 新临时 Topic（50 分区）→ 50 个业务消费者并行处理 → 处理完后删除临时 Topic ④本质 → 用中转把消息打散到更多分区 → 突破原 Topic 分区数限制 / 其他方案：①批量处理 → 如果是写入 ES → 批量 bulk 写入 → 500 条一批 → 一次请求 → 比逐条快 100 倍 ②跳过历史消息 → 如果消息有时效性 → 超过 1 小时的消息 → 推到死信 → 不处理 → 先消化最新的 ③消费者降级 → 只做最核心的处理 → 如只写 DB → 跳过 ES 同步/通知/统计 → 后台补偿 ④Flink 临时消费 → Flink 读取 Kafka → 并行度设高 → 处理后写回 → 处理完销毁 Flink 任务 ⑤多消费者组 → 同一 Topic → 启动多个消费者组 → 但要注意幂等 → 同一消息被多个组消费 → 只有一个组真正处理 → 其他组做辅助 / 注意事项：①消息顺序性 → 转发到新 Topic 时 → 按 key hash 分区 → 保证同 key 顺序 ②幂等 → 扩容后可能重复消费 → 必须幂等 ③下游压力 → 消费速度突增 → 可能压垮 DB → 要配合下游限流 ④资源回收 → 临时方案处理完 → 及时回收资源 → 删除临时 Topic / 销毁临时消费者 / 面试重点：极端积压=中转Topic+多消费者组(6分区→中转→50分区→50消费者)打破分区限制 + 批量处理 + 跳过历史消息 + 降级核心处理 + Flink临时消费 → 注意=顺序性(按key hash分区)+幂等+下游限流+资源回收）

---

## 话题二：Redis Lua 脚本与原子操作（9分钟）

**面试官：你之前提到过用 Redis 做库存扣减、限流。Redis 单条命令是原子的，但多条命令组合怎么保证原子性？Lua 脚本你了解吗？**

> 你回答...

**追问1：** 先说说为什么需要 Lua 脚本。Redis 的 MULTI/EXEC 事务不也能保证原子性吗？它们有什么区别？

> 你回答...（提示：为什么需要 Lua / Redis 事务（MULTI/EXEC）的局限：①MULTI 开始事务 → 后续命令入队 → EXEC 执行所有命令 → 期间不会被其他命令插入 → 原子性 ②问题一：没有条件判断 → 比如库存扣减 → "如果库存 >= 1 则扣减" → MULTI/EXEC 做不了 → 因为不能在事务内做条件判断 → 你只能 `GET stock` → 判断 → `DECR stock` → 但 GET 和 DECR 之间可能有其他客户端修改了 stock → 竞态 ③问题二：WATCH 乐观锁 → `WATCH stock` → `GET stock` 得到 10 → `MULTI` → `DECR stock` → `EXEC` → 如果 stock 在 WATCH 后被改了 → EXEC 返回 nil → 事务失败 → 重试 → 但高并发下重试率高 → 效率低 ④问题三：不能中间结果传递 → 比如先 GET 一个值 → 用这个值算一下 → 再 SET → MULTI/EXEC 做不了 → 命令只能预先入队 → 不能拿中间结果 / Lua 脚本的优势：①Lua 脚本在 Redis 服务端执行 → 整个脚本是一个原子操作 → 期间不会执行其他命令 → Redis 单线程保证 ②可以做条件判断 → `if redis.call('GET', key) >= 1 then return redis.call('DECR', key) else return -1 end` → 条件 + 操作在一个原子操作内 ③中间结果传递 → Lua 变量存中间结果 → 后续命令使用 ④减少网络往返 → 多条命令打包成一个脚本 → 一次网络往返 → 省多次 RTT / 面试重点：MULTI/EXEC局限=无条件判断(不能if-then)/无中间结果传递/WATCH乐观锁高并发重试率高 → Lua=服务端原子执行+条件判断+中间变量+减少网络往返 → 核心区别=MULTI是命令打包执行但不能条件判断/Lua是完整逻辑在服务端原子执行）

**追问2：** Lua 脚本的原子性原理是什么？为什么不会被打断？有没有什么坑？

> 你回答...（提示：Lua 原子性原理与坑 / 原子性原理：①Redis 是单线程执行命令（6.0 多线程 IO 但命令执行仍单线程）→ Lua 脚本作为一个整体在 Redis 主线程执行 → 执行期间 → 不会穿插其他客户端命令 → 原子性保证 ②类比 → Lua 脚本 = 一个"超长命令" → Redis 把整个脚本当成一个命令执行 → 期间不切换 / 坑一：脚本执行时间过长 → 阻塞 Redis → 如果 Lua 脚本里有循环/复杂计算 → 执行 5 秒 → Redis 卡 5 秒 → 所有其他命令排队 → 服务不可用 ②Redis 有保护 → `lua-time-limit` 默认 5000ms → 超过 → Redis 不强制中断（不是真正杀死）→ 但标记为 BUSY → 之后只允许 `SCRIPT KILL` 和 `SHUTDOWN NOSAVE` → 其他命令返回 BUSY 错误 ③`SCRIPT KILL` → 杀死正在执行的 Lua 脚本 → 但如果脚本已经执行了写操作 → kill 不掉 → 只能 `SHUTDOWN NOSAVE` → 丢数据 → 所以 Lua 脚本要短小精悍 / 坑二：脚本太大 → 网络传输慢 → 每次发整个脚本 → 如果脚本 10KB → 每次请求都发 10KB → 浪费带宽 → 用 EVALSHA 解决 / 坑三：集群模式下跨 slot → Redis Cluster → 不同 key 可能在不同节点 → Lua 脚本操作多个 key → 如果 key 不在同一 slot → 报错 → 解决：用 hash tag `{user}:stock` `{user}:info` → 保证同一 slot / 坑四：不可回滚 → Lua 脚本执行中途出错 → 已经执行的写操作不会回滚 → 不像 DB 事务 → 所以脚本里要先判断再写 / 面试重点：原子性=单线程执行整个脚本=一个超长命令 → 坑=执行过长阻塞Redis(lua-time-limit=5000ms/SCRIPT KILL/已写不能kill只能SHUTDOWN)/脚本太大用EVALSHA/集群跨slot用hash tag/不可回滚先判断再写）

**追问3：** EVAL 和 EVALSHA 有什么区别？为什么要用 SHA？生产环境怎么用？

> 你回答...（提示：EVAL vs EVALSHA / EVAL：①`EVAL script numkeys key1 key2 ...` → 每次请求都发送完整 Lua 脚本 → Redis 每次都要解析编译 Lua → 如果脚本 5KB → 每次请求 5KB → 浪费网络 + CPU / EVALSHA：①`EVALSHA sha1 numkeys key1 key2 ...` → 只发送脚本的 SHA1 哈希值（40 字符）→ Redis 根据 SHA1 查缓存 → 如果找到 → 直接执行编译好的脚本 → 省网络 + 省编译 ②前提 → 脚本要先加载到 Redis → `SCRIPT LOAD script` → 返回 SHA1 → 之后用 EVALSHA 执行 / 生产用法：①应用启动时 → `SCRIPT LOAD` 加载所有 Lua 脳本 → 拿到 SHA1 → 缓存在内存 ②运行时 → 用 EVALSHA + SHA1 执行 → 40 字符 → 快 ③如果 Redis 重启 → 脚本缓存丢失 → EVALSHA 返回 NOSCRIPT 错误 → 自动降级为 EVAL → 发送完整脚本 → 重新加载 → 后续继续用 EVALSHA ④Redisson 框架 → 自动处理 EVALSHA → 如果 NOSCRIPT → 自动 fallback 到 EVAL → 开发者无感 / Spring Boot 中使用：
```java
// 应用启动时加载脚本
@Bean
public String luaScriptSha(RedisTemplate<String, Object> redisTemplate) {
    String script = "if redis.call('GET', KEYS[1]) >= ARGV[1] then " +
                    "  return redis.call('DECRBY', KEYS[1], ARGV[1]) " +
                    "else return -1 end";
    return redisTemplate.execute((RedisCallback<String>) conn ->
        conn.scriptLoad(script.getBytes()));
}

// 运行时用 EVALSHA
public boolean deductStock(String key, int amount) {
    Long result = redisTemplate.execute((RedisCallback<Long>) conn ->
        conn.evalSha(scriptSha.getBytes(), ReturnType.INTEGER, 1,
                     key.getBytes(), String.valueOf(amount).getBytes()));
    return result != null && result >= 0;
}
```
/ 常见场景：①库存扣减（秒杀）→ 原子判断 + 扣减 ②限流（令牌桶）→ 原子取令牌 + 补充 ③分布式锁释放 → 原子判断 value + DEL（防止误解锁别人的锁）④排行榜更新 → ZADD + ZREVRANGE 原子 / 面试重点：EVAL=每次发完整脚本/EVALSHA=只发SHA1(40字符)省网络+省编译 → 生产=启动时SCRIPT LOAD+运行时EVALSHA+NOSCRIPT自动降级EVAL → Redisson自动处理 → 场景=库存扣减/限流/分布式锁释放/排行榜）

**追问4：** 你提到分布式锁释放要用 Lua。为什么？不加 Lua 直接 DEL 会有什么问题？

> 你回答...（提示：分布式锁释放的原子性 / 问题场景：①线程 A 获取锁 → `SET lock value EX 30` → value = "A的标识" ②线程 A 执行业务 → 超过 30 秒 → 锁自动过期 ③线程 B 获取锁 → `SET lock valueB EX 30` → value = "B的标识" ④线程 A 执行完 → 准备释放锁 → 直接 `DEL lock` → 把线程 B 的锁删了！⑤线程 B 还在执行 → 但锁被删了 → 线程 C 又能获取锁 → 并发问题 / Lua 解决：①释放锁前先判断 → 锁的 value 是不是自己的 → 如果是 → DEL → 如果不是 → 不删 ②但"判断 + 删除"是两步 → 如果不用 Lua → 先 GET → 判断 → 再 DEL → GET 和 DEL 之间可能有其他客户端操作 → 仍然有竞态 ③Lua 脚本：
```lua
if redis.call('GET', KEYS[1]) == ARGV[1] then
    -- 是我的锁 → 释放
    return redis.call('DEL', KEYS[1])
else
    -- 不是我的锁 → 不释放
    return 0
end
```
④`ARGV[1]` = 当前线程的唯一标识（如 UUID）→ 只有持有者能释放 → 原子判断 + 删除 / 完整流程：①获取锁 → `SET lock uuid EX 30 NX` → NX 保证不存在才设置 ②业务执行 ③释放锁 → `EVALSHA release_script 1 lock uuid` → 原子判断 + 删除 ④如果锁过期了 → GET 返回的不是自己的 uuid → 不删除 → 安全 ⑤Redisson 的 `lock.unlock()` → 底层就是 EVALSHA → 自动处理 / 面试重点：直接DEL的问题=锁过期后别人获取了锁→你DEL把别人的锁删了→并发问题 → Lua=先GET判断value是不是自己的→是则DEL→不是则不删→原子操作 → 完整流程=SET NX EX获取+EVALSHA判断+删除释放 → Redisson自动处理）

---

## 话题三：Spring Cloud OpenFeign 原理（9分钟）

**面试官：你们微服务之间怎么调用的？用的 Feign？Feign 的原理你了解吗？它是怎么把一个接口变成 HTTP 调用的？**

> 你回答...

**追问1：** Feign 的核心是动态代理。具体是怎么实现的？@FeignClient 注解的接口，Spring 是怎么生成代理对象的？

> 你回答...（提示：Feign 动态代理原理 / 整体流程：①`@FeignClient(name = "user-service")` 标注接口 `UserService` ②Spring 扫描到 `@EnableFeignClients` → FeignClientsRegistrar 扫描所有 `@FeignClient` 接口 ③为每个接口创建 JDK 动态代理 → `FeignClientFactoryBean` → `getObject()` → `Feign.builder().target(UserService.class, url)` → 返回代理对象 ④代理对象的 `InvocationHandler` = `FeignInvocationHandler` → 拦截所有方法调用 ⑤调用 `userService.getById(1)` → 代理拦截 → `InvocationHandler.invoke()` → 根据 Method 找到对应的 `MethodHandler` → 构建 HTTP 请求 → 执行 → 解析响应 / MethodHandler：①Feign 为每个方法创建一个 `SynchronousMethodHandler` ②它根据 `@GetMapping` / `@PostMapping` 等注解 → 构建 HTTP Request → `RequestTemplate` ③包含：URL（name 替换为服务名 → 负载均衡选实例 → 替换为真实 IP:Port）/ Method（GET/POST）/ Headers / Body ④执行 → `client.execute(request)` → 底层 HTTP 客户端（默认 HttpURLConnection / 可换 OkHttp / Apache HttpClient）/ 接口→HTTP 映射：①`@GetMapping("/users/{id}")` + `@PathVariable Long id` → HTTP GET `/users/1` ②`@PostMapping("/users")` + `@RequestBody User user` → HTTP POST `/users` + Body = JSON(user) ③`@RequestHeader("X-User-Id") Long userId` → HTTP Header ④`@RequestParam("name") String name` → URL Query Parameter / 面试重点：@FeignClient→FeignClientsRegistrar扫描→FeignClientFactoryBean创建JDK动态代理→FeignInvocationHandler拦截→SynchronousMethodHandler根据注解构建RequestTemplate→替换服务名为IP(负载均衡)→HTTP客户端执行→解析响应 → 接口注解映射到HTTP Method/URL/Header/Body）

**追问2：** Feign 怎么集成负载均衡的？name 是服务名，怎么变成 IP:Port 的？

> 你回答...（提示：Feign + LoadBalancer 集成 / 流程：①`@FeignClient(name = "user-service")` → name = 服务名 ②Feign 构建 RequestTemplate → URL = `http://user-service/users/1` → 此时还是服务名 → 不是 IP ③Feign 的 Client 接口 → 默认实现 `Default.Client`（HttpURLConnection）→ 直接用 URL 发请求 → 但 `http://user-service` DNS 解析不了 ④Spring Cloud 集成 LoadBalancer → 用 `LoadBalancerClient` → 先把 URL 中的服务名替换为真实实例 IP:Port → 再发请求 ⑤`FeignBlockingLoadBalancerClient`（Spring Cloud LoadBalancer）→ 拦截 Feign 请求 → `choose("user-service")` → 从注册中心拿到实例列表 → 负载均衡策略选一个 → 替换 URL → 发请求 / Spring Cloud Netflix Ribbon → Spring Cloud LoadBalancer：①Ribbon（Netflix）→ 2020 停止维护 → Spring Cloud 2020+ 用 Spring Cloud LoadBalancer 替代 ②LoadBalancer 接口 → `ReactorLoadBalancerExchangeFilterFunction` → 响应式 → 非阻塞 ③负载均衡策略 → RoundRobin（默认）/ Random / 基于响应时间权重 / 自定义 / 服务名→IP 的完整链路：
```
@FeignClient(name="user-service")
    ↓ Feign 代理
RequestTemplate: http://user-service/users/1
    ↓ LoadBalancerClient 拦截
choose("user-service") → Nacos 拉取实例列表 → [10.0.0.1:8080, 10.0.0.2:8080]
    ↓ RoundRobin 选一个
http://10.0.0.1:8080/users/1
    ↓ HTTP Client 发请求
Response
```
/ 面试重点：name=服务名→Feign构建RequestTemplate(URL含服务名)→LoadBalancerClient拦截→从注册中心拉实例列表→负载均衡策略选一个→替换URL为IP:Port→HTTP Client执行 → Ribbon已废弃/Spring Cloud LoadBalancer替代)

**追问3：** Feign 怎么集成熔断的？Sentinel 或 Resilience4j 怎么和 Feign 配合？fallback 是怎么触发的？

> 你回答...（提示：Feign + 熔断集成 / Feign 熔断集成机制：①Feign 自己不实现熔断 → 通过 `Feign.Builder` 注入熔断组件 ②Sentinel 集成 → `SentinelFeignClient` → 包装 Feign 的 Client → 每次调用先过 Sentinel 的 Entry → 如果熔断 → 抛 `BlockException` → Feign 捕获 → 走 fallback ③Resilience4j 集成 → `CircuitBreakerFeignClient` → 包装 Client → 熔断器 Open → 抛 `CircuitBreakerOpenException` → 走 fallback / fallback 触发：①`@FeignClient(name = "user-service", fallback = UserServiceFallback.class)` → 指定 fallback 类 ②fallback 类实现 `UserService` 接口 → 每个方法返回降级值 ③当 Feign 调用 → 超时 / 异常 / 熔断 → Feign 不抛异常 → 而是调用 fallback 类的对应方法 → 返回降级数据 ④`fallbackFactory` → 比 fallback 更灵活 → 可以拿到异常信息 → 根据不同异常返回不同降级策略
```java
@FeignClient(name = "user-service", fallbackFactory = UserServiceFallbackFactory.class)
public interface UserService {
    @GetMapping("/users/{id}")
    User getById(@PathVariable Long id);
}

@Component
public class UserServiceFallbackFactory implements FallbackFactory<UserService> {
    @Override
    public UserService create(Throwable cause) {
        return new UserService() {
            @Override
            public User getById(Long id) {
                log.error("调用用户服务失败", cause);
                if (cause instanceof ReadTimeoutException) {
                    return User.degraded("用户服务响应超时");
                }
                return User.degraded("用户服务不可用");
            }
        };
    }
}
```
/ 熔断触发条件：①异常率 > 阈值 → 如 50% 请求异常 → 熔断 ②慢调用比例 > 阈值 → 如 RT > 1s 的请求 > 30% → 熔断 ③熔断后 → 所有请求直接走 fallback → 不发 HTTP → 快速失败 ④Half-Open → 试探性放少量请求 → 成功 → 关闭熔断 → 失败 → 重新熔断 / 面试重点：Feign自己不熔断→通过Builder注入熔断组件(Sentinel/Resilience4j)→包装Client→熔断时抛异常→Feign捕获走fallback → fallback=实现接口返回降级值/fallbackFactory=可拿异常信息按异常类型降级 → 熔断条件=异常率/慢调用比例 → Open后直接fallback不发HTTP)

**追问4：** Feign 的超时和重试怎么配置？有什么坑？

> 你回答...（提示：Feign 超时重试坑 / 超时配置层次：①Feign 自己的超时 → `feign.client.config.default.connectTimeout=5000` / `readTimeout=10000` ②Ribbon/LoadBalancer 超时 → `ribbon.ReadTimeout=3000`（Ribbon 时代）→ Spring Cloud LoadBalancer 不设超时 → 用 Feign 的 ③Sentinel 超时 → 如果用 Sentinel → Sentinel 也有超时控制 → 可能和 Feign 冲突 ④坑：多层超时 → 最里层（Feign 10s）> 最外层（Sentinel 3s）→ Sentinel 先超时 → Feign 还在等 → 但 Sentinel 已经走 fallback → Feign 线程浪费 / 重试坑：①Feign Retryer → 默认 `Retryer.NEVER_RETRY` → 不重试 ②配 `feign.Retryer.Default` → `maxAttempts=3` → 会重试 3 次 ③坑一：GET 请求重试 OK → POST 请求重试 → 可能重复下单/重复扣款 → 非幂等接口重试 = 灾难 ④坑二：Feign 重试 + 负载均衡重试 → 两层重试 → 总重试次数 = 3 × 3 = 9 次 → 把下游打崩 ⑤坑三：超时 + 重试 → 超时 5s + 重试 3 次 → 总耗时 15s → 调用方早超时了 → 重试无意义 / 最佳实践：①Feign 超时 → connectTimeout=2s / readTimeout=5s → 合理 ②重试 → 只对幂等接口（GET）重试 → 非幂等（POST/PUT/DELETE）不重试 → 或者用业务幂等保证 ③Spring Cloud LoadBalancer → `spring.cloud.loadbalancer.retry.enabled=true` → 重试时换一个实例 → 不要重试同一个挂掉的实例 ④熔断 → 超时/重试后还失败 → 走 fallback → 快速降级 ⑤避免多层重试 → 只在 Feign 层重试 → Ribbon/LoadBalancer 层关闭重试 / 面试重点：超时坑=多层超时(Feign/LoadBalancer/Sentinel)冲突→最外层先超时→内层线程浪费 → 重试坑=POST非幂等重试重复下单+两层重试放大+超时+重试总耗时过长 → 最佳=Feign超时2s/5s+只重试幂等GET+换实例重试+熔断fallback+只在Feign层重试)

---

## 话题四：Redlock 算法与分布式锁争议（9分钟）

**面试官：Redis 分布式锁你用过。除了单节点 SETNX，还听过 Redlock 吗？Antirez 提出的那个。它解决了什么问题？**

> 你回答...

**追问1：** 先说说单节点 Redis 分布式锁有什么问题。为什么需要 Redlock？

> 你回答...（提示：单节点锁的问题 / 单节点 Redis 分布式锁：①`SET lock value NX PX 30000` → 获取锁 → value = 唯一标识（UUID）→ PX 30000 过期 30s → NX 不存在才设置 ②释放锁 → Lua 脚本判断 value + DEL（话题二讲过）③问题一：单点故障 → Redis 挂了 → 锁全丢 → 所有客户端都能获取锁 → 并发问题 ④用主从 → Master 获取锁 → 还没同步到 Slave → Master 挂了 → Slave 提升为 Master → 新 Master 上没有锁 → 别人也能获取锁 → 锁失效 ⑤问题二：锁过期 + GC 停顿 → 线程获取锁 → STW 10 秒 → 锁过期 → 别人获取锁 → STW 结束 → 两个线程都以为持锁 → 并发 ⑥问题三：时钟跳跃 → 如果 Redis 机器时钟跳跃 → 锁提前过期 / Redlock 的思路：①不用主从复制 → 用多个独立 Redis 节点（通常 5 个）→ 没有关联 ②向所有 5 个节点都请求加锁 → 超过半数（3 个）成功 → 且耗时小于锁过期时间 → 加锁成功 ③任何一个节点挂了 → 还有 4 个 → 仍能 majority → 不影响 ④核心思想 → 用多数派替代主从复制 → 避免 Master-Slave 同步延迟导致的锁丢失 / 面试重点：单节点问题=单点故障(Master挂了锁全丢)+主从同步延迟(Master获取锁还没同步到Slave→Master挂→Slave提升→锁丢失)+GC停顿+时钟跳跃 → Redlock=多个独立Redis节点(5个)+多数派(3个)+无主从复制→避免同步延迟问题）

**追问2：** Redlock 的完整流程是什么？5 步是哪些？

> 你回答...（提示：Redlock 5步流程 / Redlock 算法流程：①获取当前时间 T1 ②依次向 5 个 Redis 节点发送加锁请求 → `SET lock value NX PX TTL` → 每个节点设置超时（如 50ms）→ 防止某个节点卡住拖慢整体 ③获取当前时间 T2 → 计算总耗时 = T2 - T1 ④判断：成功加锁的节点数 >= 3（majority）且 总耗时 < TTL（锁还没过期）→ 加锁成功 → 实际有效时间 = TTL - 总耗时 ⑤如果加锁失败（少于 3 个成功 或 总耗时 > TTL）→ 向所有节点发送释放锁请求（包括没成功的节点 → 防止边界情况）/ 关键设计点：①为什么依次而不是并行 → 实现简单 → 5 个节点依次请求 → 每个超时 50ms → 最慢 250ms → 可接受 ②为什么总耗时 < TTL → 如果加锁耗时 5s → 但锁 TTL 只有 10s → 实际有效时间只剩 5s → 可能不够业务执行 ③为什么失败要向所有节点释放 → 第一个节点可能加锁成功了但你以为没成功（网络延迟）→ 不释放 → 锁一直占着 → 别人拿不到 ④锁续期 → 和 Redisson WatchDog 一样 → 后台线程定时续期 → 防止业务执行超过 TTL / Redisson 实现：①`RedissonRedLock(lock1, lock2, lock3, lock4, lock5)` → 传入 5 个 Redisson 的 `RLock` ②`redLock.lock()` → 底层自动执行 Redlock 算法 ③`redLock.unlock()` → 向所有节点释放 ④Redisson 3.x 支持 → 但 Redisson 官方推荐用普通 `RLock`（单节点 + WatchDog）→ 足够大部分场景 / 面试重点：5步=①T1开始时间②依次向5节点SET NX PX(每节点超时50ms)③T2计算耗时④判断>=3成功且耗时<TTL→成功(有效时间=TTL-耗时)⑤失败向所有节点释放 → 关键=依次请求/总耗时<TTL/失败全释放/续期WatchDog）

**追问3：** Martin Kleppmann（《DDIA》作者）为什么质疑 Redlock？他的核心论点是什么？你怎么看？

> 你回答...（提示：Kleppmann 质疑 / 核心质疑一：GC 停顿导致锁失效：①客户端 1 获取 Redlock → 5 个节点都成功 → 持有锁 ②客户端 1 GC STW → 停顿 10 秒（Stop-The-World）③锁过期（TTL=10s）→ 5 个节点都自动释放 ④客户端 2 获取 Redlock → 成功 ⑤客户端 1 GC 结束 → 它不知道锁过期了 → 以为自己还持锁 → 继续操作 → 两个客户端同时操作 → 并发问题 ⑥Redlock 无法解决 GC 停顿问题 → 因为 GC 是客户端的问题 → 和 Redis 节点无关 / 核心质疑二：时钟跳跃：①Redlock 依赖时间戳 → T1/T2 计算 → 如果机器时钟跳跃（NTP 同步 / 容器时钟漂移）→ T2-T1 不准确 ②如 5 个节点时间不同步 → 节点 A 的 TTL 比节点 B 快 → A 的锁先过期 → majority 变化 → 锁失效 ③Redlock 假设时钟是"合理同步"的 → 但分布式系统中时钟不可靠 / Kleppmann 的结论：①Redlock 既不是 AP 也不是 CP → 它是一个"既不安全也不高效"的算法 ②如果需要正确性 → 用 ZK / etcd（基于 Raft / Paxos → 有 fencing token）③如果不需要强正确性 → 单 Redis + 过期时间足够了 → Redlock 多此一举 / fencing token 方案：①每次获取锁 → 返回一个单调递增的 token（ fencing token）②客户端操作存储时带上 token → 存储层检查 token → 如果 token 比当前的小 → 拒绝 ③即使 GC 停顿 → 旧 token 过期 → 新 token 更大 → 存储层拒绝旧 token 的操作 → 安全 ④但 Redlock 没有 fencing token → 无法实现 / Antirez 回应：①GC 偆顿 → 是客户端问题 → 任何分布式锁都有这个问题 → 不只是 Redlock ②时钟 → 可以用 NTP 精确同步 → 现代服务器时钟偏差很小 ③Redlock 比 ZK 快 → ZK 写入要走多数派 → 延迟高 → Redlock 5 个 Redis 并行 → 快 ④如果需要绝对正确 → 用 ZK → 但大部分场景 Redlock 够用 / 我的看法（面试表达）：①金融系统 → 数据一致性要求高 → 倾向用 ZK/etcd 分布式锁 → 有 fencing token → 绝对安全 ②大部分互联网场景 → 单 Redis + WatchDog + Lua 释放 → 够用 → 性能好 → Redlock 有点"鸡肋" ③Redlock 的问题不在算法本身 → 而在于"分布式锁的正确性依赖于客户端不被 GC 暂停"这个假设不现实 / 面试重点：Kleppmann质疑=①GC停顿(客户端STW→锁过期→另一个获取→GC结束→两个并发操作)Redlock解决不了 ②时钟跳跃(T1/T2不准/TTL不同步→majority变化) ③Redlock无fencing token(存储层无法拒绝旧token操作) → 结论=需正确性用ZK/etcd(有fencing token)/不需强正确性单Redis足够 → Antirez回应=GC是客户端问题/NTP可同步/Redlock比ZK快 → 我的看法=金融用ZK+etcd/互联网用单Redis+WatchDog/Redlock鸡肋）

**追问4：** 生产环境分布式锁你怎么选？Redis/ZK/DB 三种方案怎么对比？

> 你回答...（提示：分布式锁方案选型 / 三种方案对比：
| 维度 | Redis（SETNX+Lua） | ZK（临时顺序节点） | DB（SELECT FOR UPDATE / 唯一约束） |
|------|------|------|------|
| 性能 | 高（内存操作，万级 QPS） | 中（集群写入要走多数派，千级 QPS） | 低（DB 锁，百级 QPS） |
| 可靠性 | 中（主从切换可能丢锁） | 高（Raft 多数派，不丢锁） | 高（DB ACID） |
| 复杂度 | 低（SET NX + Lua） | 中（临时节点 + Watch） | 低（SQL 一行） |
| 一致性 | AP（最终一致） | CP（强一致） | CP（强一致） |
| 适用 | 高并发 + 可容忍偶尔失效 | 低并发 + 强一致要求 | 低并发 + 简单场景 |
①Redis → 性能最好 → 但主从切换可能丢锁 → 适合"偶尔失效可接受"的场景 → 如限流/防重复提交/缓存预热 ②ZK → 强一致 → 临时顺序节点 + Watch → 客户端断开 → 锁自动释放 → 不会丢锁 → 适合"绝对不能并发"的场景 → 如金融转账/定时任务调度 ③DB → 最简单 → 但性能差 → 适合低频操作 → 如配置更新/任务领取 / 选型建议：①高并发场景（秒杀/限流）→ Redis → 性能优先 → 失效概率低 + 业务可容忍 ②金融核心（转账/清算）→ ZK → 正确性优先 → 不能丢锁 ③简单低频（定时任务/配置）→ DB → 不引入额外组件 → 简单 ④实际项目 → 混合使用 → 限流用 Redis / 核心交易用 ZK / 简单场景用 DB ⑤Redisson → RLock（单节点）满足大部分需求 → 不需要 Redlock / 面试重点：Redis=高性能AP(主从切换可能丢锁/万级QPS/限流防重)→ZK=强一致CP(Raft多数派不丢锁/千级QPS/金融转账)→DB=最简单(性能差百级QPS/低频场景) → 选型=高并发用Redis/强一致用ZK/简单用DB/实际混合 → Redisson RLock够用不需要Redlock）

---

## 话题五：Java 注解处理器(APT)与编译时生成（8分钟）

**面试官：你们项目用 Lombok 吧？@Data 注解加上去就有 getter/setter 了。Lombok 是怎么实现的？它运行时反射生成的吗？**

> 你回答...

**追问1：** 注解处理器的原理是什么？Lombok 在编译时做了什么？

> 你回答...（提示：APT 原理 / 注解处理器（Annotation Processing Tool）：①APT = 编译时工具 → 在 Java 编译期间扫描和处理注解 → 可以生成新的 Java 文件 / 修改 AST（抽象语法树）②`javax.annotation.processing.Processor` 接口 → `process(annotations, roundEnv)` → 编译器调用 ③流程 → javac 编译 → 扫描所有注解 → 找到注册的 Processor → 调用 process → Processor 可以生成新文件 → 编译器再编译新文件 → 多轮处理直到没有新文件 / Lombok 的实现：①Lombok 不是标准 APT → 它用了"黑科技" → 直接修改 AST（抽象语法树）②标准 APT 只能生成新文件 → 不能修改已有类 → Lombok 通过反射调用 javac 内部 API（`com.sun.tools.javac.tree`）→ 直接在 AST 中插入 getter/setter 方法 ③流程 → javac 解析源码 → 生成 AST → Lombok 的 AnnotationProcessor 被调用 → 扫描 @Data → 在 AST 中对应的 ClassNode 插入 getter/setter/equals/hashCode/toString 方法 → javac 继续编译修改后的 AST → 字节码中有这些方法 ④所以 → 运行时 .class 文件里已经有 getter/setter → 不需要反射 → 性能和手写一样 / Lombok 的问题：①依赖 javac 内部 API → 不是标准 → Java 版本升级可能破坏 → JDK 16+ 需要额外配置 `--add-opens` ②IDE 集成 → 需要装 Lombok 插件 → 不然 IDEA 看不到生成的方法 → 报错 ③`@Data` 生成所有方法 → 有时不需要 → 如 JPA Entity 不应该有 setter → 用 `@Getter` 代替 `@Data` ④`@Builder` + `@AllArgsConstructor` + `@NoArgsConstructor` → 组合使用容易出 bug ⑤`@EqualsAndHashCode` 默认不调用父类 → 继承场景 bug / 面试重点：APT=编译时扫描注解+生成新文件(标准)/修改AST(Lombok黑科技) → Lombok=反射调javac内部API直接在AST插入方法→.class有方法→不需要反射→性能同手写 → 问题=依赖javac内部API(非标准/JDK16+要--add-opens)+IDE插件+@Data过度生成+继承bug）

**追问2：** MapStruct 也用注解处理器。它和 Lombok 有什么区别？为什么说 MapStruct 比 BeanUtils.copyProperties 好？

> 你回答...（提示：MapStruct vs Lombok vs BeanUtils / MapStruct 原理：①MapStruct = 编译时生成对象映射代码 → `@Mapper` 注解 → APT 生成实现类 → 编译时生成 `UserMapperImpl.java` ②生成的代码 → 直接 `target.setName(source.getName())` → 没有反射 → 性能最好 ③和 Lombok 区别 → Lombok 修改 AST（黑科技）→ MapStruct 生成新文件（标准 APT）→ MapStruct 更规范 / BeanUtils.copyProperties 的问题：①Spring/Apache 的 BeanUtils → 运行时反射 → 性能差（反射调 getter/setter）②字段名不同 → 不映射 → 需要手动处理 ③类型不同 → 不转换 → 需要自定义 Converter ④深拷贝/浅拷贝 → BeanUtils 是浅拷贝 → 嵌套对象共享引用 / MapStruct 优势：①编译时生成代码 → 无反射 → 性能最优 ②编译时报错 → 字段名不匹配 → 编译时发现 → 不是运行时才发现 NPE ③灵活映射 → `@Mapping(source="userName", target="name")` → 字段名不同也能映射 ④类型转换 → `@Mapping(source="createTime", target="createTime", dateFormat="yyyy-MM-dd")` → String ↔ Date ⑤嵌套映射 → 自动处理嵌套对象映射 / 性能对比：①BeanUtils.copyProperties → 1000 次映射 → ~50ms（反射开销）②MapStruct → 1000 次映射 → ~0.5ms（直接方法调用）→ 100 倍差距 ③手写 set/get → ~0.3ms → MapStruct 接近手写 / 面试重点：MapStruct=编译时APT生成映射实现类→直接set/get无反射→性能接近手写(比BeanUtils快100倍) → BeanUtils=运行时反射+字段名不匹配不映射+浅拷贝 → MapStruct优势=编译时报错(不是运行时NPE)+字段名映射+类型转换+嵌套映射 → Lombok修改AST(黑科技)/MapStruct生成新文件(标准APT)）

**追问3：** 除了 Lombok 和 MapStruct，APT 还有哪些应用场景？你在项目里用过自定义注解处理器吗？

> 你回答...（提示：APT 应用场景 / 常见 APT 应用：①Lombok → 生成 getter/setter/builder ②MapStruct → 生成对象映射代码 ③Dagger 2 / Hilt → 生成依赖注入代码（编译时生成 Component → 不用运行时反射 → 比 Spring 快）④ButterKnife（Android）→ 生成 View 绑定代码 ⑤Hibernate JPA Metamodel → 生成元模型类（类型安全的 Criteria 查询）⑥Google AutoValue → 生成不可变值对象 ⑦Spring Boot Configuration Processor → 生成 `spring-configuration-metadata.json` → IDE 自动补全配置 / 自定义 APT 场景：①DTO 校验 → 自定义 `@DtoValidator` → 编译时生成校验代码 → 不用运行时反射 ②RPC 接口生成 → 定义接口 → APT 生成 HTTP Client 代码 → 类似 Feign 但编译时生成 ③枚举映射 → `@EnumCode` → 编译时生成 code↔enum 映射 → 不用运行时反射 ④日志埋点 → `@LogMetric` → 编译时生成日志代码 → 零侵入 / 自定义 APT 基本步骤：①定义注解 → `@Target(METHOD)` `@Retention(SOURCE)` ②实现 Processor → `process()` 扫描注解 → 用 `Filer` 生成 Java 文件 ③注册 → `META-INF/services/javax.annotation.processing.Processor` 文件写 Processor 全类名 ④编译 → javac 自动调用 → 生成代码 ⑤使用 → 调用生成的类 / 和运行时注解对比：①编译时 APT → 代码在 .class 里 → 无反射 → 性能好 → 但只能编译时 ②运行时注解（`@Retention(RUNTIME)`）→ 运行时反射 → 灵活 → 但性能差 ③面试表达 → "我们项目里用 APT 做了枚举码值映射 → 编译时生成 `EnumMapper` → 比 DB 查表快 → 比反射安全" / 面试重点：APT应用=Lombok/MapStruct/Dagger2/Hilt(依赖注入编译时)/AutoValue(不可变对象)/Spring配置元数据 → 自定义=DTO校验/RPC接口生成/枚举映射/日志埋点 → 和运行时注解对比=编译时生成代码无反射(性能好)/运行时反射(灵活但慢)）

---

## 话题六：MySQL 读写分离架构（8分钟）

**面试官：你们 MySQL 做了读写分离吗？怎么做的？主从延迟遇到过吗？怎么处理的？**

> 你回答...

**追问1：** 先说说读写分离的架构。为什么需要读写分离？ShardingSphere-JDBC 和 Proxy 模式有什么区别？

> 你回答...（提示：读写分离架构 / 为什么读写分离：①写走主库 → 读走从库 → 减轻主库压力 → 读多写少场景效果明显 ②主库负责写 → 从库负责读 → 读写不互相阻塞 → 性能提升 ③从库可以水平扩展 → 加从库提升读能力 / ShardingSphere 两种模式：
| 维度 | ShardingSphere-JDBC | ShardingSphere-Proxy |
|------|------|------|
| 部署 | 应用内 JDBC 增强 | 独立中间件进程 |
| 性能 | 高（直连 DB） | 中（多一跳网络） |
| 语言 | 只支持 Java | 支持多语言 |
| 运维 | 无额外组件 | 需维护 Proxy |
①JDBC 模式 → 应用内增强 → 每个 Microservice 引入 jar → 直接连 MySQL → 性能最好 → 但只支持 Java ②Proxy 模式 → 独立部署 → 应用连 Proxy → Proxy 路由到主/从 → 对应用透明 → 支持多语言 → 但多一跳 / 路由规则：①默认 → 写走主库（INSERT/UPDATE/DELETE）→ 读走从库（SELECT）②事务内 → 全部走主库（保证一致性）③`HintManager.getInstance().addMasterRouteOnly()` → 强制走主库 / 面试重点：读写分离=写主读从减轻压力+从库水平扩展 → ShardingSphere-JDBC=应用内直连(高性能/只Java)/Proxy=独立中间件(多语言/多一跳) → 路由=默认写主读从+事务内全走主+Hint强制走主）

**追问2：** 写完立即读，读到旧数据怎么办？你们怎么解决主从延迟问题？

> 你回答...（提示：主从延迟问题 / 主从延迟原因：①主库写 binlog → 从库 IO 线程拉取 binlog → 写 relay log → SQL 线程重放 → 有延迟 ②延迟来源 → 网络传输 + SQL 重放 → 如果主库写入量大 → 从库跟不上 ③通常延迟 → 毫秒级到秒级 → 网络抖动或大事务可达分钟级 / 写后读旧数据场景：①用户注册 → 写主库 → 立即查询 → 走从库 → 从库还没同步 → 查不到 → 用户以为注册失败 ②修改密码 → 写主库 → 立即登录 → 走从库 → 从库还是旧密码 → 登录失败 ③下单 → 写主库 → 立即查订单列表 → 走从库 → 查不到新订单 / 解决方案：①方案一：写后强制走主库 → `HintManager.addMasterRouteOnly()` → 写完后的一段时间内（如 5 秒）读走主库 → 但实现复杂（要跟踪哪个用户写了什么）→ 可以用 ThreadLocal 标记 → 写操作后设置标记 → 后续读走主库 → 一定时间后清除 ②方案二：半同步复制 → 主库写 binlog → 至少一个从库 ACK → 主库才返回成功 → 保证至少一个从库有数据 → 但降低写性能（多等 ACK）③方案三：读从库 + 失败重试主库 → 先读从库 → 如果读不到 → 回查主库 → 简单但增加 RT ④方案四：业务设计避免写后立即读 → 写操作返回结果 → 不再查询 → 如注册直接返回用户信息 → 不再查 DB ⑤方案五：缓存 → 写 DB 后同步写缓存 → 读走缓存 → 不走从库 → 但缓存和 DB 一致性问题 / 实际项目方案：①注册/登录 → 写后强制走主库（ThreadLocal 标记 + 5 秒内走主库）②查询列表 → 从库读 → 查不到不报错 → 延迟可接受 ③关键业务（支付/转账）→ 全走主库 → 不读写分离 ④非关键业务 → 从库读 → 偶尔延迟可接受 / 面试重点：延迟原因=binlog传输+SQL重放(毫秒到秒级) → 写后读旧=注册查不到/密码旧/订单查不到 → 解决=①强制走主库(Hint+ThreadLocal标记+5秒)②半同步复制(从库ACK再返回但降性能)③读从库失败回查主库④业务避免写后读⑤缓存 → 实际=注册登录强制走主/查询列表从库延迟可接受/关键业务全走主库）

**追问3：** 如果从库挂了怎么办？读写分离的故障转移怎么做？

> 你回答...（提示：从库故障转移 / 从库故障场景：①从库宕机 → 读请求全部失败 → 降级到主库读 → 主库压力突增 ②从库延迟过大 → 读到太旧的数据 → 业务异常 ③从库网络抖动 → 间歇性超时 / 故障转移策略：①从库健康检查 → ShardingSphere 配置健康检查 → 从库不可用 → 自动摘除 → 读走主库 ②多从库 → 配 2-3 个从库 → 一个挂了 → 读其他 → 读取负载分摊 ③降级到主库 → 所有从库不可用 → 读全部走主库 → 主库要能扛住 → 可能需要限流 ④告警 → 从库故障 → 立即告警 → 运维处理 ⑤故障恢复 → 从库修复 → 数据同步追上 → 重新加入 → 读流量切回 / 主库故障更严重：①主库挂了 → 写全部失败 → 需要主从切换 → 提升一个从库为新主库 ②MHA / Orchestrator / MGR → 自动主从切换 ③切换时间 → 通常 10-60 秒 → 期间写不可用 → 业务要兜底（写请求排队/重试/降级）④切换后 → 应用感知新主库地址 → ShardingSphere 动态配置 → Nacos 推送新地址 → 不重启应用 / 面试重点：从库故障=健康检查摘除+多从库分摊+降级主库+限流+告警 → 主库故障=自动主从切换(MHA/Orchestrator/MGR)+10-60秒写不可用+动态配置推送新地址 → 关键=主库故障比从库严重得多→写不可用→业务兜底）

---

## 话题七：Spring 定时任务与分布式调度（8分钟）

**面试官：你们项目有定时任务吗？用的什么？@Scheduled 用过吧？在集群环境下有什么问题？**

> 你回答...

**追问1：** @Scheduled 在多个节点同时部署时，会执行多次。怎么保证只有一个节点执行？

> 你回答...（提示：@Scheduled 集群问题 / 问题：①`@Scheduled(cron = "0 0 2 * * ?")` → 每天凌晨 2 点执行 ②部署 3 个节点 → 3 个节点同时触发 → 重复执行 ③如跑批生成账单 → 3 个节点各跑一次 → 重复生成 / 解决方案一：分布式锁 → @Scheduled + Redis 分布式锁：①任务触发 → 先获取分布式锁 → 获取到才执行 → 没获取到跳过 ②
```java
@Scheduled(cron = "0 0 2 * * ?")
public void generateBill() {
    String lockKey = "scheduled:generateBill";
    try {
        boolean locked = redisTemplate.opsForValue()
            .setIfAbsent(lockKey, "locked", 30, TimeUnit.MINUTES);
        if (!locked) return;  // 其他节点在执行 → 跳过
        // 执行任务
        doGenerateBill();
    } finally {
        redisTemplate.delete(lockKey);
    }
}
```
③问题 → 锁过期 + 任务没执行完 → 锁释放 → 另一个节点获取锁 → 重复执行 → 要用 WatchDog 续期 / 解决方案二：XXL-JOB → 分布式任务调度平台：①调度中心统一调度 → 只调度一个执行器 → 执行器执行任务 ②不需要分布式锁 → 调度中心保证只有一个节点执行 ③支持分片广播 → 大数据量分片并行执行 ④支持失败重试 / 失败告警 / 任务日志 / 解决方案三：ShedLock → 专门解决 @Scheduled 集群问题：①`@SchedulerLock(name = "generateBill", lockAtMostFor = "30m")` ②底层用 DB/Redis/Mongo 存锁 → 简单轻量 → 适合小项目 / 面试重点：@Scheduled集群问题=多节点同时执行重复 → 解决=①Redis分布式锁(setIfAbsent+WatchDog续期)②XXL-JOB(调度中心统一调度只一个执行器+分片+重试+日志)③ShedLock(@SchedulerLock注解+DB/Redis锁+轻量)）

**追问2：** XXL-JOB 和 @Scheduled + 分布式锁各有什么优缺点？什么时候用哪个？

> 你回答...（提示：选型对比 / @Scheduled + 分布式锁 vs XXL-JOB：
| 维度 | @Scheduled + 锁 | XXL-JOB |
|------|------|------|
| 复杂度 | 低（Spring 原生） | 中（需要部署调度中心） |
| 可观测 | 差（没有日志/监控） | 好（Web 控制台） |
| 动态调度 | 不支持（改 cron 要重启） | 支持（控制台改 cron） |
| 失败重试 | 需自己实现 | 内置 |
| 分片执行 | 不支持 | 支持（分片广播） |
| 任务依赖 | 不支持 | 支持（子任务） |
| 告警 | 需自己实现 | 内置（邮件/钉钉） |
①简单场景（定时清理/数据同步）→ @Scheduled + Redis 锁 → 不引入额外组件 → 足够 ②复杂场景（跑批/数据补偿/多步骤依赖）→ XXL-JOB → 调度中心 + 执行器 → 可观测 + 可控 / XXL-JOB 核心特性：①调度中心 → 集群部署 → 高可用 → 统一管理所有任务 ②执行器 → 自动注册 → 调度中心发现执行器 → 负载均衡选择 ③路由策略 → FIRST（第一个）/ LAST（最后一个）/ ROUND（轮询）/ RANDOM（随机）/ CONSISTENT_HASH（一致性哈希）/ LEAST_FREQUENTLY_USED（最不经常使用）/ SHARDING_BROADCAST（分片广播）④分片广播 → 所有执行器都执行 → 每个执行器处理一部分数据 → 如 1000 万数据 → 10 个执行器各处理 100 万 → 并行 ⑤失败重试 → 任务失败 → 自动重试 N 次 → 超过 → 告警 ⑥任务日志 → 调度中心查看执行日志 → 排查问题 / 面试重点：@Scheduled+锁=简单无额外组件但无可观测/动态调度/重试/分片 → XXL-JOB=调度中心+执行器+Web控制台+动态cron+分片广播+失败重试+任务日志+告警 → 简单用@Scheduled+锁/复杂用XXL-JOB）

**追问3：** 任务执行到一半，节点挂了怎么办？怎么保证任务不丢、不重复执行？

> 你回答...（提示：任务幂等与容错 / 节点挂了的问题：①任务执行到一半 → 节点 OOM / 容器被驱逐 / 机器宕机 → 任务中断 ②中断状态 → 数据可能不一致 → 如跑了 50 万条 → 第 50 万 1 条挂了 → 没跑完 ③重启后 → 从头跑 → 前 50 万条重复 → 如果不幂等 → 重复生成 / 解决方案：①幂等设计 → 每条记录处理前检查状态 → 已处理跳过 → 如 `UPDATE task SET status='done' WHERE id=? AND status='pending'` → 只处理 pending 的 ②断点续传 → 记录处理进度 → 如 `last_processed_id` → 重启后从 `last_processed_id + 1` 继续 ③XXL-JOB 分片 → 每个分片处理一段 → 某个分片挂了 → 其他分片不受影响 → 挂的分片重试 ④任务状态机 → PENDING → RUNNING → SUCCESS / FAILED → FAILED 的可以手动重跑 ⑤对账 → 跑批完成后 → 对账检查 → 确认数据完整 / 实际设计：
```java
@XxlJob("generateBillHandler")
public void generateBill() {
    // 1. 获取上次处理的进度
    Long lastId = getLastProcessedId("generateBill");
    
    // 2. 分页处理 → 每页 1000 条
    while (true) {
        List<User> users = userMapper.selectUnprocessed(lastId, 1000);
        if (users.isEmpty()) break;
        
        for (User user : users) {
            try {
                // 幂等：检查是否已处理
                if (billMapper.exists(user.getId(), today())) {
                    continue;  // 已生成 → 跳过
                }
                // 生成账单
                generateBillForUser(user);
                // 标记已处理
                markProcessed(user.getId());
            } catch (Exception e) {
                log.error("生成账单失败 userId={}", user.getId(), e);
                // 记录失败 → 后台补偿
                recordFailure(user.getId(), e.getMessage());
            }
        }
        // 更新进度
        lastId = users.get(users.size() - 1).getId();
        updateLastProcessedId("generateBill", lastId);
    }
}
```
/ 面试重点：节点挂了=任务中断+数据不一致+重启重复 → 解决=①幂等(处理前检查状态→已处理跳过)②断点续传(记录last_processed_id→重启从断点继续)③XXL-JOB分片(某分片挂了其他不受影响)④任务状态机(PENDING→RUNNING→SUCCESS/FAILED→FAILED手动重跑)⑤对账(跑批后检查数据完整) → 核心设计=分页处理+幂等检查+进度记录+失败补偿+对账校验）

---

## 话题八：手写代码 - 拓扑排序（8分钟）

**面试官：写一个函数，给你一些课程的依赖关系，判断能不能完成所有课程。比如 [1,0] 表示要上课程 1 必须先上课程 0。如果有循环依赖就完成不了。**

你在纸上/白板上写代码...

**追问1：** 先说说思路。这本质是什么问题？用什么算法？

> 你回答...（提示：拓扑排序思路 / 本质：①课程依赖 = 有向图 → 课程 = 节点 → 依赖 = 有向边（A → B 表示要先上 A 再上 B）②判断能否完成所有课程 = 判断有向图是否有环 → 有环则不能完成 → 无环则可以 ③拓扑排序 = 对 DAG（有向无环图）排序 → 输出一个合法的线性顺序 → 如果能排完所有节点 → 无环 → 能完成 / 两种方法：①BFS（Kahn 算法）→ 入度法 → 入度 = 0 的节点先入队 → 取出 → 邻居入度 -1 → 入度变 0 入队 → 如果最后所有节点都出队 → 无环 ②DFS → 深度优先 → 访问节点 → 递归访问邻居 → 如果遇到正在访问的节点 → 有环 → 三色标记法（白/灰/黑）/ BFS（Kahn）代码：
```java
public boolean canFinish(int numCourses, int[][] prerequisites) {
    // 建图 + 入度数组
    List<List<Integer>> graph = new ArrayList<>();
    int[] inDegree = new int[numCourses];
    for (int i = 0; i < numCourses; i++) {
        graph.add(new ArrayList<>());
    }
    // [1,0] = 要上1先上0 → 0→1
    for (int[] pre : prerequisites) {
        graph.get(pre[1]).add(pre[0]);
        inDegree[pre[0]]++;
    }
    
    // 入度为 0 的先入队
    Queue<Integer> queue = new LinkedList<>();
    for (int i = 0; i < numCourses; i++) {
        if (inDegree[i] == 0) queue.offer(i);
    }
    
    // BFS
    int count = 0;  // 已排序的节点数
    while (!queue.isEmpty()) {
        int course = queue.poll();
        count++;
        for (int next : graph.get(course)) {
            inDegree[next]--;  // 邻居入度 -1
            if (inDegree[next] == 0) queue.offer(next);
        }
    }
    
    return count == numCourses;  // 全部排序 = 无环 = 能完成
}
```
/ 核心要点：①建图 → 邻接表 + 入度数组 ②入度 = 0 的先入队 → 没有前置依赖 ③取出节点 → 邻居入度 -1 → 如果变 0 → 入队 ④如果 count == numCourses → 无环 → 能完成 ⑤时间 O(V+E) → 空间 O(V+E) / 面试重点：本质=有向图判环→拓扑排序 → BFS(Kahn)=入度法(入度0入队→取出→邻居-1→变0入队→count==numCourses则无环) → 入度=前置依赖数量 → 建图用邻接表+入度数组 → 时间O(V+E)）

**追问2：** DFS 怎么做？三色标记法是什么？

> 你回答...（提示：DFS 三色标记 / 三色标记法：①白色（0）= 未访问 ②灰色（1）= 正在访问（在当前递归栈中）③黑色（2）= 已访问完成 / 检测环：①DFS 访问节点 → 标记灰色 → 递归访问邻居 ②如果邻居是灰色 → 说明在当前递归路径中 → 有环 → 返回 false ③如果邻居是黑色 → 已访问完 → 跳过 ④所有邻居访问完 → 标记黑色 → 返回 / 代码：
```java
public boolean canFinish(int numCourses, int[][] prerequisites) {
    List<List<Integer>> graph = new ArrayList<>();
    for (int i = 0; i < numCourses; i++) graph.add(new ArrayList<>());
    for (int[] pre : prerequisites) {
        graph.get(pre[1]).add(pre[0]);
    }
    
    int[] color = new int[numCourses];  // 0=白 1=灰 2=黑
    
    for (int i = 0; i < numCourses; i++) {
        if (color[i] == 0) {  // 未访问
            if (!dfs(graph, i, color)) return false;  // 有环
        }
    }
    return true;
}

private boolean dfs(List<List<Integer>> graph, int node, int[] color) {
    color[node] = 1;  // 标记灰色（正在访问）
    for (int next : graph.get(node)) {
        if (color[next] == 1) return false;  // 遇到灰色 → 环！
        if (color[next] == 0) {  // 白色 → 递归
            if (!dfs(graph, next, color)) return false;
        }
        // 黑色 → 跳过
    }
    color[node] = 2;  // 标记黑色（已完成）
    return true;
}
```
/ BFS vs DFS：①BFS（Kahn）→ 直观 → 入度法 → 容易理解 ②DFS → 三色标记 → 遇到灰色 = 环 → 更通用（可以找环的具体路径）③两者时间复杂度都是 O(V+E) ④面试一般 BFS（Kahn）更常见 → 更容易写对 / 面试重点：DFS三色=白(未访问)/灰(正在访问→在递归栈中)/黑(已完成) → 遇到灰色=环 → BFS更直观常用/DFS更通用可找环路径 → 时间都是O(V+E)）

**追问3：** 如果不只判断能否完成，还要输出一个合法的选课顺序呢？

> 你回答...（提示：输出拓扑序列 / BFS 输出序列：①Kahn 算法天然输出拓扑序列 → 节点出队的顺序就是拓扑排序 ②只要把 `count++` 改成 `result.add(course)` ③
```java
public int[] findOrder(int numCourses, int[][] prerequisites) {
    List<List<Integer>> graph = new ArrayList<>();
    int[] inDegree = new int[numCourses];
    for (int i = 0; i < numCourses; i++) graph.add(new ArrayList<>());
    for (int[] pre : prerequisites) {
        graph.get(pre[1]).add(pre[0]);
        inDegree[pre[0]]++;
    }
    
    Queue<Integer> queue = new LinkedList<>();
    for (int i = 0; i < numCourses; i++) {
        if (inDegree[i] == 0) queue.offer(i);
    }
    
    int[] result = new int[numCourses];
    int index = 0;
    while (!queue.isEmpty()) {
        int course = queue.poll();
        result[index++] = course;  // 出队顺序 = 拓扑序列
        for (int next : graph.get(course)) {
            inDegree[next]--;
            if (inDegree[next] == 0) queue.offer(next);
        }
    }
    
    return index == numCourses ? result : new int[0];  // 有环返回空数组
}
```
/ DFS 输出序列：①DFS 后序（节点标记黑色时）→ 逆序就是拓扑序列 ②即 → 先访问完所有邻居 → 再把自己加入结果 → 最后反转 ③因为 → DFS 后序 → 最深的节点先标记黑色 → 但拓扑排序要求依赖在前 → 所以逆序 / 应用场景：①编译器 → 编译顺序 = 拓扑排序（依赖的库先编译）②任务调度 → 任务有依赖关系 → 拓扑排序决定执行顺序 ③课程表 → 选课顺序 ④Spring Bean 初始化 → Bean 依赖关系 → 拓扑排序决定初始化顺序 / 面试重点：BFS输出序列=出队顺序就是拓扑序列(把count++改成result.add) → DFS后序逆序=节点标记黑色时加入result→最后反转 → 应用=编译顺序/任务调度/课程表/Spring Bean初始化顺序）

---

# 二面（30分钟）

## 话题九：供应链金融业务（10分钟）

**面试官：你之前做银行和支付。顺丰做的是供应链金融，和传统信贷不一样。你了解供应链金融吗？保理是什么？**

> 你回答...

**追问1：** 先说说供应链金融是什么。和传统信贷有什么本质区别？

> 你回答...（提示：供应链金融概念 / 定义：①供应链金融 = 以核心企业为依托 → 用自偿性贸易融资的方式 → 为供应链上下游中小企业提供融资服务 ②核心 → "信用传递" → 核心企业（如顺丰/大品牌）信用好 → 银行愿意给 → 但中小企业信用不够 → 银行不愿意给 → 供应链金融让核心企业的信用传递到上下游 / 和传统信贷区别：
| 维度 | 传统信贷 | 供应链金融 |
|------|------|------|
| 还款来源 | 借款人自身经营收入 | 贸易项下应收账款/货物 |
| 风控核心 | 借款人信用评级 | 交易真实性+核心企业信用 |
| 融资主体 | 中小企业（信用弱） | 供应链整体（核心企业背书） |
①传统信贷 → 看借款人自己 → 中小企业没抵押没信用 → 融资难融资贵 ②供应链金融 → 看交易关系 → 有核心企业付款承诺/有真实贸易背景 → 风险可控 / 三种模式：①应收账款融资 → 上游供应商 → 对核心企业有应收账款 → 用应收账款做抵押融资 ②保兑仓融资 → 下游经销商 → 向核心企业采购 → 银行垫付货款 → 货物销售后还款 ③融通仓融资 → 用仓库存货做抵押融资 / 顺丰做供应链金融的优势：①物流数据 → 顺丰有真实物流数据 → 运单/仓储/配送 → 验证贸易真实性 → 供应链金融最大风险是虚假贸易 → 物流数据验证 ②仓储资源 → 顺丰有大量仓库 → 仓单质押 → 货物在顺丰仓库 → 控制货物 ③供应链关系 → 顺丰服务大量企业客户 → 了解上下游交易关系 → 信用评估 / 面试重点：供应链金融=核心企业信用传递到上下游中小企业→用贸易项下应收/货物做还款来源 → 和传统信贷区别=看交易关系不看借款人信用 → 三种模式=应收账款融资/保兑仓/融通仓 → 顺丰优势=物流数据验证贸易真实性+仓储控制货物+供应链关系评估信用）

**追问2：** 保理是什么？正向保理和反向保理有什么区别？

> 你回答...（提示：保理业务 / 保理（Factoring）：①企业把应收账款转让给保理商（银行/保理公司）→ 保理商提供融资+催收+坏账担保服务 ②核心 → 应收账款转让 → 企业提前拿到钱 → 不用等核心企业付款 / 正向保理：①供应商 → 主动找保理商 → "我对核心企业有 100 万应收账款 → 3 个月到期 → 你先给我 90 万 → 到期你找核心企业收 100 万" ②流程 → 供应商发起 → 保理商评估核心企业信用 → 融资给供应商 → 到期保理商找核心企业收款 ③问题 → 保理商要评估核心企业 → 如果核心企业不配合 → 不好做 / 反向保理（Reverse Factoring）：①核心企业主导 → "我是大企业 → 我的供应商需要融资 → 银行你直接给我的供应商融资 → 到期我来付款" ②流程 → 核心企业和银行签约 → 核心企业确认应付账款 → 供应商凭确认的应付账款融资 → 到期核心企业直接付给银行 ③优势 → 核心企业主动参与 → 信用背书 → 银行风险低 → 供应商融资成本低 ④典型 → 顺丰保理 → 顺丰确认对供应商的应付 → 供应商凭此融资 → 顺丰到期付给银行 / 保理的功能：①融资 → 提前拿到应收账款 ②催收 → 保理商负责催收 ③坏账担保 → 如果核心企业不付 → 保理商承担 ④账务管理 → 保理商管理应收账款 / 面试重点：保理=应收账款转让给保理商→提前融资→保理商到期收款 → 正向保理=供应商主动找保理商→保理商评估核心企业 → 反向保理=核心企业主导→确认应付→供应商融资→核心企业到期付银行→风险低 → 顺丰保理=反向保理模式）

**追问3：** 仓单质押是什么？怎么控制风险？如果质押的货物跌价了怎么办？

> 你回答...（提示：仓单质押 / 仓单质押：①企业把货物存入指定仓库 → 仓库开具仓单 → 企业用仓单做抵押融资 ②核心 → 货物在仓库 → 控制货物 → 如果企业不还款 → 拍卖货物 / 流程：①企业 → 把货物存入顺丰仓库 ②顺丰仓库 → 开具仓单（电子仓单/标准仓单）③企业 → 用仓单向银行/保理公司融资 ④银行 → 评估货物价值 → 放款（通常 50-70% 货值）⑤到期 → 企业还款 → 释放仓单 → 取回货物 ⑥不还款 → 银行拍卖货物 / 风险控制：①货物真实 → 顺丰仓库验货 → 确保货物真实存在 ②货物价值评估 → 第三方评估 → 设定质押率（50-70%）③跌价处理 → 设定预警线 → 货值/融资金额 < 1.2 → 追加保证金 → 不追加 → 强行平仓拍卖 ④货物变现 → 选择流动性好的货物 → 大宗商品（钢材/铜/铝）→ 容易拍卖 / 跌价处理：①预警线 → 货值/融资额 = 1.5 → 安全 → 1.2 → 预警 → 要求企业追加保证金 ②平仓线 → 货值/融资额 = 1.1 → 强行平仓 → 拍卖货物 → 偿还融资 ③追加保证金 → 企业补钱 → 恢复到安全线 ④类似期货的保证金制度 → 每日盯市 → 货值变化 → 追保或平仓 / 面试重点：仓单质押=货物存仓库→仓单抵押融资→不还款拍卖货物 → 风控=货物真实(仓库验货)+价值评估(质押率50-70%)+跌价预警(预警线1.2追保/平仓线1.1拍卖)+流动性(选大宗商品容易变现) → 跌价=每日盯市+预警线追加保证金+平仓线强行拍卖→类似期货保证金制度）

---

## 话题十：核心设计题 - 供应链金融平台（20分钟）

**面试官：顺丰要做一个供应链金融平台，支持应收账款融资（保理）。核心企业（顺丰）的供应商可以凭应付账款融资。每天几千笔融资申请，要求自动化审批+秒级放款。怎么设计？**

> 你回答...

**追问1：** 先说说融资的完整流程。从供应商申请到放款，经过哪些环节？

> 你回答...（提示：融资流程 / 完整流程：①核心企业确认应付 → 顺丰（核心企业）→ 确认对供应商的应付账款 → 签署应付确认书 → 上链存证（区块链/存证平台）②供应商申请融资 → 供应商凭确认的应付账款 → 向保理平台申请融资 → 选择融资金额/期限 ③平台审核 → 自动审核 → ①交易真实性校验（物流数据+合同+发票交叉验证）②供应商资质校验（工商/涉诉/经营异常）③核心企业信用评估（顺丰信用 → AAA）④额度计算 → 根据应付金额 × 融资比例（80-90%） ④放款 → 审核通过 → 资金方放款 → 供应商收款 ⑤到期还款 → 到期日 → 核心企业（顺丰）直接付款给资金方 → 不经过供应商 → 反向保理核心 / 自动化审核：①交易真实性 → 物流单号验证（顺丰运单系统）+ 合同验签 + 发票验真 ②资质校验 → 调天眼查/企查查 API → 自动判断 ③额度计算 → 规则引擎 → 应付金额 × 80% → 自动放款 ④异常转人工 → 如果校验不通过/金额异常 → 转人工审核 / 面试重点：流程=①核心企业确认应付(上链存证)②供应商申请③自动审核(交易真实性+资质+信用+额度)④放款⑤到期核心企业直接付资金方(反向保理) → 自动化=物流数据验证+发票验真+天眼查API+规则引擎 → 异常转人工）

**追问2：** 怎么防止同一笔应收账款重复融资？供应商可能拿同一笔应付去多个平台融资。

> 你回答...（提示：防重复融资 / 问题的严重性：①供应商 A → 对顺丰有 100 万应收 → 在平台 1 融资 80 万 → 又在平台 2 融资 80 万 → 总融资 160 万 > 100 万应收 → 超融 → 到期还不上 / 解决方案：①应收账款登记 → 中登网（中国人民银行征信中心动产融资统一登记公示系统）→ 每笔应收账款融资 → 在中登网登记 → 其他平台融资前 → 查中登网 → 已登记 → 拒绝 ②平台内防重 → 同一应付账款编号 → DB 唯一约束 → 不可重复融资 ③区块链存证 → 应收账款确认 → 上链 → 不可篡改 → 所有平台共享 → 一查就知道是否已融资 ④核心企业配合 → 顺丰确认应付时 → 标记"已用于融资"→ 不再确认第二次 / 技术实现：①中登网登记 → 调用中登网 API → 登记融资信息 → 融资前查中登网 → ②DB 唯一约束 → `UNIQUE KEY uk_payable_no (payable_no)` → 同一应付编号只能融资一次 ③分布式锁 → 融资申请 → `Redis SETNX payable:lock:{payableNo}` → 防并发重复 ④状态机 → 应付账款状态 → CONFIRMED → FINANCING → FINANCED → REPAID → 只在 CONFIRMED 状态才能发起融资 / 面试重点：防重复融资=①中登网登记(央行征信中心→所有平台共享→融资前查)②DB唯一约束(应付编号唯一)③区块链存证(不可篡改→所有平台共享)④核心企业标记+状态机(CONFIRMED→FINANCING→FINANCED→REPAID)→分布式锁防并发 → 核心=中登网登记是行业标准+平台内唯一约束+状态机）

**追问3：** 风控怎么设计？融资审批的规则引擎怎么实现？

> 你回答...（提示：风控设计 / 风控分层：①准入规则（硬条件）→ 供应商经营异常/失信被执行/涉诉 → 直接拒 ②交易真实性 → 物流数据匹配+合同验签+发票验真 → 不通过拒 ③信用评估 → 核心企业（顺丰）信用评级 → AAA → 优质 → 融资比例 90% / BB → 限制 50% ④动态风控 → 供应商经营变化/应付账款到期前核心企业经营异常 → 预警 → 提前回收 / 规则引擎实现：①规则存储 → MySQL 存规则 → `rule_id/rule_name/rule_expression/priority/status` ②规则执行 → Aviator/Drools 表达式引擎 → 输入交易数据 → 输出通过/拒绝 ③热加载 → 规则变更 → Nacos 配置变更 → 监听 → 重新加载规则 → 不重启 ④规则版本 → 灰度发布 → 新规则 10% 流量 → 验证 → 全量 / 规则示例：
```
规则1: if supplier.creditRating == 'D' then REJECT
规则2: if payable.amount > 10000000 then MANUAL_REVIEW  // >1000万转人工
规则3: if logistics.matchRate < 0.8 then REJECT  // 物流匹配率<80%拒
规则4: if coreEnterprise.creditRating == 'AAA' then financingRatio = 0.9
规则5: if supplier.lawsuitCount > 3 then REJECT
```
/ 风控和消费金融的区别：①消费金融 → 个人 → 征信+行为评分 → 模型为主 ②供应链金融 → 企业 → 交易真实性+核心企业信用 → 规则为主+模型辅助 ③供应链金融风控核心 = 交易真实性验证（防欺诈）→ 比信用评估更重要 / 面试重点：风控分层=准入(失信/涉诉拒)+交易真实性(物流+合同+发票)+信用评估(核心企业评级定融资比例)+动态预警 → 规则引擎=MySQL存规则+Aviator/Drools执行+Nacos热加载+版本灰度 → 和消费金融区别=供应链金融重交易真实性验证(防欺诈)>信用评估 → 规则为主模型辅助）

**追问4：** 资金方怎么对接？多个资金方（银行/信托/保理公司）怎么路由？

> 你回答...（提示：多资金方路由 / 资金方类型：①银行 → 资金成本低 → 但审批慢、额度有限 ②保理公司 → 资金成本中 → 审批快 ③信托/资管 → 资金成本高 → 灵活 / 路由策略：①优先级 → 按资金成本排序 → 先匹配低成本资金方 → 降低供应商融资成本 ②额度 → 每个资金方有额度限制 → 额度用完 → 匹配下一个 ③偏好 → 供应商可以选择资金方（指定银行）④可用性 → 资金方接口超时/不可用 → 熔断 → 切换其他资金方 ⑤费率 → 不同资金方费率不同 → 匹配最优费率 / 路由设计：
```
融资请求 → 路由引擎 → 匹配资金方 → 推送融资申请 → 资金方审批 → 放款
                ↓
         资金方候选列表（按成本排序）
         1. 工商银行（成本4%）
         2. 招商银行（成本5%）
         3. 顺丰保理（成本6%）
         4. 信托A（成本8%）
```
①先匹配工行 → 额度够 → 推工行 → 工行审批 → 放款 ②工行额度用完 → 匹配招行 ③工行接口超时 → 熔断 → 切招行 ④供应商指定"我要用招行"→ 直接推招行 / 资金方接口适配：①Adapter 模式 → 统一接口 → 适配不同资金方 API（REST/SOAP/文件）②异步 → 资金方审批 → 回调通知 → 不阻塞 / 对账：①每日对账 → 平台记录 vs 资金方记录 → 金额/笔数一致 ②差异处理 → 多扣/少扣 → 冲正/补单 / 面试重点：多资金方路由=按成本排序优先匹配低成本+额度限制+可用性熔断切换+供应商可指定+费率最优 → 接口适配(Adapter统一接口+异步回调) → 对账(每日T+1+差异冲正)）

**追问5：** 到期还款怎么处理？如果核心企业（顺丰）到期不付款怎么办？

> 你回答...（提示：还款与违约处理 / 正常还款（反向保理）：①到期日 → 核心企业（顺丰）直接付款给资金方 → 不经过供应商 ②这是反向保理的核心 → 顺丰确认应付 → 顺丰到期付款 → 供应商不参与还款 ③自动扣款 → 平台通知顺丰 → 顺丰付款 → 平台确认 → 更新融资状态 → REPAID / 核心企业不付款（违约）：①原因 → 顺丰经营恶化/资金链断裂/恶意拖欠 ②处理 → 有追索权保理 → 保理商向供应商追索 → 供应商还款 → 无追索权保理 → 保理商自己承担坏账 ③平台处理 → T+1 到期未付 → 标记逾期 → 催收 → 告警 ④信用降级 → 顺丰信用评级下降 → 后续融资 → 融资比例降低 → 或暂停 / 逾期处理流程：①T+1 逾期 → 标记逾期 → 通知顺丰 → 宽限期 3 天 ②T+3 → 催收 → 保理商向顺丰催收 → 记录逾期 ③T+7 → 升级 → 如果有追索权 → 向供应商追索 ④T+30 → 坏账 → 标记坏账 → 法律诉讼 → 资产保全 ⑤征信上报 → 核心企业逾期 → 上报央行征信 → 影响顺丰信用 / 对账与清算：①日终对账 → 平台融资记录 vs 资金方放款记录 vs 核心企业付款记录 → 三方对平 ②清算 → 到期日 → 核心企业付本金+利息给资金方 → 平台记账 → 借贷平衡 ③差异处理 → 多付/少付 → 冲正/补款 / 面试重点：正常还款=核心企业到期直接付资金方(反向保理核心)→平台通知→自动扣款→更新状态 → 违约=有追索权向供应商追索/无追索权保理商承担 → 逾期流程=T+1标记/宽限3天→T+3催收→T+7追索→T+30坏账诉讼+征信上报 → 对账=三方对平(平台vs资金方vs核心企业)+清算(本金+利息) → 借贷平衡）

**追问6：** 平台高可用怎么设计？每天几千笔融资，核心环节不能挂。

> 你回答...（提示：高可用设计 / 高可用分层：①接入层 → 网关 → 限流+鉴权+幂等 ②应用层 → 微服务多副本 → 无状态 → 横向扩展 ③数据层 → MySQL 主从+分库分表 → Redis 集群 → MQ 集群 ④资金方接口 → 熔断+降级+多资金方切换 / 核心环节保障：①融资申请 → 幂等（请求 ID + Redis SETNX + DB 唯一约束）→ 防重复申请 ②自动审批 → 规则引擎无状态 → 多副本 → 一个挂了其他继续 ③放款 → 资金方接口 → 超时重试+熔断+多资金方切换 → 保证放款不丢 ④还款 → 核心企业付款 → 如果平台挂了 → 顺丰直连资金方 → 不依赖平台 → 平台恢复后对账 ⑤对账 → 日终跑批 → 即使平台白天挂了 → 日终对账能发现差异 → 补偿 / 数据安全：①融资数据 → 加密存储（身份证/银行卡 AES 加密）②审计日志 → 每笔融资 → 完整审计链 → 谁申请/谁审批/谁放款/谁还款 ③容灾 → 两地三中心 → 主中心挂了 → 备中心接管 → RTO < 5min / 监控告警：①业务监控 → 融资申请数/通过率/放款金额/逾期率 → 异常告警 ②技术监控 → 服务 RT/错误率/GC/线程池/DB 慢查询 ③资金方接口 → 成功率/RT → 频繁超时告警 / 面试重点：高可用=接入层(限流+鉴权+幂等)+应用层(多副本无状态)+数据层(主从+分库+Redis集群+MQ集群)+资金方(熔断+降级+多资金方切换) → 核心环节=幂等防重复+规则引擎无状态+放款不丢(重试+熔断+切换)+还款不依赖平台(直连资金方)+日终对账补偿 → 数据安全=加密+审计+两地三中心+RTO<5min）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| 消息积压处理（ConsumerLag监控/原因排查/扩容受分区限制/中转Topic打散/批量消费/降级） | 能讲清 / 讲不全 / 不会★ | |
| Redis Lua 脚本（MULTI/EXEC局限/原子性原理/阻塞坑/EVAL vs EVALSHA/分布式锁释放原子性） | 能讲清 / 讲不全 / 不会★ | |
| Spring Cloud OpenFeign（动态代理FeignInvocationHandler/负载均衡集成/熔断fallback/超时重试坑） | 能讲清 / 讲不全 / 不会★ | |
| Redlock 算法争议（单节点问题/5步流程/Kleppmann质疑GC+时钟/fencing token/Redis vs ZK vs DB选型） | 能讲清 / 讲不全 / 不会★ | |
| Java 注解处理器 APT（编译时原理/Lombok修改AST黑科技/MapStruct生成代码/BeanUtils反射对比/应用场景） | 能讲清 / 讲不全 / 不会★ | |
| MySQL 读写分离（ShardingSphere-JDBC vs Proxy/主从延迟写后读旧/强制走主库/从库故障转移） | 能讲清 / 讲不全 / 不会★ | |
| Spring 定时任务（@Scheduled集群重复执行/Redis锁/XXL-JOB/ShedLock/节点挂了幂等+断点续传） | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（拓扑排序/BFS Kahn入度法/DFS三色标记/输出拓扑序列） | 能讲清 / 讲不全 / 不会★ | |
| 供应链金融业务（信用传递/保理正向反向/仓单质押/跌价预警线平仓线） | 能讲清 / 讲不全 / 不会★ | |
| 供应链金融平台设计（融资流程/防重复融资中登网/风控规则引擎/多资金方路由/还款违约/高可用） | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **消息积压**：监控 ConsumerLag → 原因排查（消费慢/实例不够/分区不够/Rebalance/消息不均衡）→ 扩容受分区数限制 → 极端方案 = 中转 Topic 打散到更多分区 + 多消费者并行。**批量消费** `max.poll.records=500` → 批量处理减少网络往返。跳过非关键消息 + 降级核心处理。注意：扩容后要幂等 + 下游限流
> 2. **Redis Lua**：MULTI/EXEC 做不了条件判断和中间结果传递 → Lua 在服务端原子执行条件+操作。**坑**：执行过长阻塞 Redis（`lua-time-limit=5000ms` → BUSY → `SCRIPT KILL`，已写不能 kill 只能 `SHUTDOWN NOSAVE`）。EVAL 每次发完整脚本 → EVALSHA 只发 SHA1（40 字符）→ 生产启动时 SCRIPT LOAD + 运行时 EVALSHA + NOSCRIPT 自动降级。**分布式锁释放必须 Lua**：先 GET 判断 value 是不是自己的 → 是则 DEL → 否则不删 → 防止删别人的锁
> 3. **OpenFeign**：`@FeignClient` → JDK 动态代理 → `FeignInvocationHandler` 拦截 → `SynchronousMethodHandler` 构建 `RequestTemplate` → 负载均衡替换服务名为 IP → HTTP Client 执行。熔断通过 Builder 注入 Sentinel/Resilience4j → 包装 Client → 熔断时走 fallback。**坑**：多层超时冲突（Feign/LoadBalancer/Sentinel）+ POST 非幂等重试重复下单 + 两层重试放大
> 4. **Redlock 争议**：5 步 = T1 → 依次向 5 节点 SET NX PX → T2 计算耗时 → ≥3 成功且耗时 < TTL → 失败向所有节点释放。**Kleppmann 质疑**：GC 停顿（客户端 STW → 锁过期 → 另一个获取 → GC 结束 → 两个并发）+ 时钟跳跃 + 无 fencing token。**结论**：金融用 ZK/etcd（有 fencing token）/ 互联网用单 Redis + WatchDog / Redlock 鸡肋
> 5. **APT**：编译时扫描注解 → 生成代码。Lombok = 黑科技修改 AST（反射调 javac 内部 API）→ .class 有方法不需要反射。MapStruct = 标准 APT 生成映射实现类 → 直接 set/get 无反射 → 比 BeanUtils 快 100 倍。应用：Dagger2/Hilt 依赖注入、AutoValue 不可变对象、Spring 配置元数据
> 6. **读写分离**：ShardingSphere-JDBC（应用内直连/只 Java/高性能）vs Proxy（独立中间件/多语言/多一跳）。**主从延迟**：写后强制走主库（Hint + ThreadLocal 标记 + 5 秒内走主库）/ 半同步复制（从库 ACK 再返回）/ 读从库失败回查主库。从库故障 = 健康检查摘除 + 多从库分摊 + 降级主库
> 7. **定时任务**：@Scheduled 集群 = 多节点重复执行 → Redis 分布式锁 / XXL-JOB 调度中心统一调度 / ShedLock 轻量方案。XXL-JOB 优势 = Web 控制台 + 动态 cron + 分片广播 + 失败重试 + 任务日志。**节点挂了**：幂等检查 + 断点续传（last_processed_id）+ 分片隔离 + 对账校验
> 8. **拓扑排序**：本质 = 有向图判环。BFS（Kahn）= 入度法 → 入度 0 入队 → 取出 → 邻居 -1 → 变 0 入队 → count == numCourses 则无环。DFS = 三色标记（白/灰/黑）→ 遇到灰色 = 环。输出拓扑序列 = BFS 出队顺序 / DFS 后序逆序
> 9. **供应链金融**：核心 = 信用传递（核心企业信用传递到上下游中小企业）。保理 = 应收账款转让融资。**反向保理** = 核心企业主导 → 确认应付 → 供应商融资 → 核心企业到期直接付资金方。仓单质押 = 货物存仓库 → 仓单抵押 → 跌价预警线 1.2 追保 / 平仓线 1.1 拍卖
> 10. **供应链金融平台**：融资流程 = 核心企业确认应付 → 供应商申请 → 自动审核（物流+发票+天眼查）→ 放款 → 到期核心企业付资金方。**防重复融资** = 中登网登记（央行征信中心）+ DB 唯一约束 + 状态机。风控 = 准入规则 + 交易真实性验证（核心）+ 信用评估。多资金方路由 = 按成本排序 + 额度 + 熔断切换。高可用 = 幂等 + 无状态多副本 + 资金方熔断切换 + 日终对账兜底 + 两地三中心
