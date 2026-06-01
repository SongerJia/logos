---
title: Redis 面试理论
tags:
  - Database
  - Interview
---

## 一、数据结构 & 底层编码（必问基础）

> **Q1** Redis 的 5 种基本数据类型，每种至少说 2 个应用场景。String 除了缓存还能做什么？

> **Q2** `String` 的三种底层编码：`int`、`embstr`、`raw`，分别在什么条件下切换？`embstr` 为什么比 `raw` 省内存？

> **Q3** `Hash` 的两种底层编码：`listpack`（Redis 7）和 `hashtable`，什么时候从 `listpack` 升级为 `hashtable`？

> **Q4** `ZSet` 的底层编码：`listpack`（Redis 7）+ `skiplist` + `hashtable`，为什么跳表 + 哈希表要一起用？各解决了什么问题？

> **Q5** 跳表（SkipList）的查询、插入、删除时间复杂度？为什么 Redis 用跳表不用红黑树或 B+ 树？（至少说 2 个理由）

> **Q6** 3 种特殊数据类型：Bitmap、HyperLogLog、GEO，各自做什么的？HyperLogLog 的误差率是多少？底层用了什么算法？

---

## 二、过期 & 淘汰策略

> **Q7** Redis 的过期删除策略是什么？惰性删除 + 定期删除如何配合？定期删除的频率和每次扫描数量？

> **Q8** 8 种内存淘汰策略分别是什么？`allkeys-lru` 和 `volatile-lru` 的区别？LRU 和 LFU 的区别？Redis 的近似 LRU 和标准 LRU 有什么不同？

> **Q9** 一个 key 设置了 TTL 但从未被访问，过期后一定会立刻删除吗？如果没有设置淘汰策略，内存满了怎么办？

---

## 三、缓存经典三兄弟（穿透/击穿/雪崩）

> **Q10** 缓存穿透：描述场景、原因、至少 3 种解决方案。布隆过滤器（Bloom Filter）的原理是什么？为什么能判断"一定不存在"，但只能说"可能存在"？

> **Q11** 缓存击穿：一个热点 key 过期瞬间大量请求打到 DB，你怎么处理？互斥锁方案和"逻辑过期"方案各自的优缺点？

> **Q12** 缓存雪崩：大量 key 同时过期或 Redis 宕机，分别怎么应对？过期时间加随机值有效吗？多级缓存怎么搭？

---

## 四、缓存一致性 & 读写策略

> **Q13** Cache Aside（旁路缓存）模式：先删缓存再写 DB，还是先写 DB 再删缓存？为什么？延迟双删又是什么？每种方案有什么风险？

> **Q14** 如果业务要求"强一致性"，Redis 缓存能做到吗？Canal 订阅 `binlog` 异步更新缓存的方案是什么？和 Cache Aside 比有哪些优劣？

> **Q15** 缓存预热怎么做？新服务上线时，冷缓存导致 DB 压力暴增，你有哪些预热手段？

---

## 五、持久化（RDB / AOF / 混合）

> **Q16** RDB 和 AOF 的区别？各有什么优缺点？RDB 的 `save` 和 `bgsave` 区别？`bgsave` 过程中 fork 子进程，如果数据 10G，fork 会阻塞多久？

> **Q17** AOF 重写（Rewrite）的流程？为什么不直接覆盖原来的 AOF 文件？重写期间新的写命令怎么处理？

> **Q18** Redis 4.0 混合持久化：RDB + AOF 混合，格式是什么？解决了什么问题？

> **Q19** `appendfsync` 的三种策略（always / everysec / no）各自的优缺点？默认 `everysec` 丢数据最多丢多少？

---

## 六、主从 & Sentinel

> **Q20** Redis 主从复制的完整流程：全量同步（`SYNC` → RDB → 发送 + replication buffer）和增量同步（`repl_backlog_buffer` → `PSYNC`），什么情况下会触发全量同步？

> **Q21** Sentinel 哨兵模式下，主观下线（SDOWN）和客观下线（ODOWN）的区别？哨兵选主（Failover）的流程是怎样的？

> **Q22** 主从 + 哨兵模式有什么缺陷？为什么很多大厂用 Cluster 而不只用哨兵？脑裂（Split-Brain）发生时会发生什么？

---

## 七、Cluster 集群

> **Q23** Redis Cluster 的 16384 个哈希槽怎么分配的？`CRC16(key) % 16384` 后，客户端怎么知道该去哪个节点？MOVED 和 ASK 重定向的区别？

> **Q24** Cluster 的节点间通信用什么协议？Gossip 协议的优势和劣势？

> **Q25** Cluster 模式下，一个 key 的所有操作都必须落在同一个节点吗？事务（MULTI）和 Lua 脚本在 Cluster 下有什么限制？`hash_tag {}` 怎么用的？

---

## 八、线程模型 & 性能

> **Q26** Redis 为什么单线程还这么快？（至少说 4 个原因：纯内存、IO 多路复用、单线程无锁、高效数据结构）

> **Q27** Redis 6.0 的多线程到底是什么？命令执行还是单线程吗？多线程用在什么环节？为什么不是全链路多线程？

> **Q28** Redis 大 Key 的危害？怎么发现大 Key（`BIGKEYS`、`MEMORY USAGE`）？大 Key 必须 `DEL` 时，为什么可能阻塞？怎么优雅删除？

---

## 九、分布式锁 & 实战

> **Q29** Redis 分布式锁：`SET key value NX PX 30000`，一个命令为什么比 `SETNX` + `EXPIRE` 两步好？解锁为什么必须用 Lua 脚本？

> **Q30** Redisson 的"看门狗"（Watchdog）机制是怎么实现锁自动续期的？如果 Redisson 节点宕机了，看门狗还能续期吗？

> **Q31** RedLock 算法（Redis 官方推荐的分布式锁）的流程？为什么 Martin Kleppmann 说 RedLock 不安全？争议的核心是什么？

---

## 十、Redis 新版本 & 现代生态

> **Q32** Redis 7.0 有哪些重要的新特性？Redis Functions（lua 脚本替代）、ACL v2、`SHRINK`命令、AOF v2 等，挑 3 个说清楚。

> **Q33** Redis Stack 是什么？RediSearch、RedisJSON、RedisTimeSeries、RedisBloom 分别解决什么问题？什么时候选 Redis Stack 而不是单独的 Elasticsearch？

---

## 十一、实战场景

> **Q34** 你设计一个秒杀系统，怎么用 Redis 做库存扣减？`DECR` 直接扣 vs Lua 脚本原子扣减 + 预扣库存方案，对比优劣。如何处理"超卖"和"少卖"？

> **Q35** Redis 突然响应变慢，你在排查吗？可能的原因有哪些？（大 Key/慢查询/持久化 fork/内存 swap/CPU 竞争/网络延迟），你的排查流程是什么？
