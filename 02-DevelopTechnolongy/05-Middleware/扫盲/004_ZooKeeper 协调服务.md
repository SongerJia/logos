虽然 Spring Cloud Alibaba 主推 Nacos，但 ZK 在面试中仍然是**分布式协调的经典考题**。

|#|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|4.1|**ZAB 协议 & 数据模型**|🔴 必背|① 数据模型：树形层级结构（类似文件系统），每个节点 znode 可存数据（< 1MB）② 四种节点类型：持久 / 持久顺序 / 临时 / 临时顺序 ③ ZAB 协议：原子广播（写操作通过 Leader 广播）+ 崩溃恢复（选举新 Leader）④ 面试：ZooKeeper 的 ZAB 协议和 Raft 有什么区别？|→ 分布式共识算法（Raft/Paxos）|
|4.2|**Leader 选举机制**|🟡 应掌握|① 基于 zxid（事务ID 最大优先）+ myid（SID 大者优先）② 过半原则：获得超半数投票才当选 Leader ③ 选举过程：Looking → Following / Leading ④ 面试：ZK 集群为什么推荐奇数个节点？3 个和 5 个分别能容忍几个挂掉？|→ CAP 理论（CP 系统）|
|4.3|**Watch 监听机制**|🔴 必背|① 一次性触发（One-time trigger）：监听一次事件后 Watch 自动移除，需要重新注册 ② 客户端监听 → 服务端变更 → 通知客户端 → 客户端回调 ③ 典型用途：配置变更感知 / 服务上下线感知 / 分布式锁释放通知 ④ 面试：ZK 的 Watch 机制有什么特点？为什么是一次性的？（服务端无状态、减少内存）|→ Redis Pub/Sub（发布订阅对比）|
|4.4|**分布式锁实现（Curator）**|🟡 应掌握|① **InterProcessMutex**：可重入锁，基于临时顺序节点 + 最小节点获锁模式 ② 获取锁：创建临时顺序节点 → 判断是否最小 → 是则获锁，否则 watch 前一个节点 ③ 释放锁：删除节点（连接断开自动删除，防死锁）④ 面试：用 ZK 实现分布式锁和用 Redis（Redisson）有什么区别？各自优劣？|→ Redis 分布式锁（RedLock/Lua脚本）|
|4.5|**ZK vs Nacos vs Etcd vs Consul 对比**|🔴 必背||① **Zookeeper**：CP 强一致，成熟稳定但重（Java 实现，维护成本高）② **Nacos**：AP + CP 可切换，Spring Cloud Alibaba 一等公民，配置中心+注册中心一体 ③ **Etcd**：CP，Go 实现（K8s 底层），Raft 协议，轻量高性能 ④ **Consul**：CP，HashiCorp 出品，Service Mesh 生态好 ⑤ 面试：你们项目用的什么注册中心？为什么选它？|
|4.6|**ZK 集群部署 & 注意事项**|🟢 了解|① 集群角色：Leader（1个）+ Follower（多个）+ Observer（只读副本，不参与投票，提升读性能）② 部署建议：至少 3 节点（容忍 1 个故障），生产 5 节点（容忍 2 个）③ 常见坑：dataLogDir 和 dataDir 分盘（写分离）、JVM 堆设置（不建议 > 4G）|→ Seata TC Server HA（同样依赖 ZK/Nacos）|
|4.7|**Curator 客户端使用**|🟢 了解|① Apache Curator：ZK 客户端封装，提供 Recipes（分布式锁/Leader选举/屏障/缓存）② 常用 API：create / getData / setData / getChildren / watch + 重试策略 ③ 面试：你在项目中用过 ZK 做什么？用的原生客户端还是 Curator？|→ Java API 使用习惯|