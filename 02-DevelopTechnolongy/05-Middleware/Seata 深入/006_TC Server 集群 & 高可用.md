### 为什么这个模块重要

**TC (Transaction Coordinator) 是 Seata 的大脑**。如果 TC 挂了，所有分布式事务都瘫痪。理解 TC 的高可用设计是生产落地的关键。

### 知识点表

|序号|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|6.1|**Server端三种存储模式**|🔴必背|① **file**：开发用，内存+文件，重启丢失 ② **db**：生产推荐，MySQL存储 ③ **redis**：高性能场景 ④ 面试：生产环境用什么存储模式？为什么？|→ MySQL主从复制(M10) / Redis高可用(M11)|
|6.2|**Server端核心配置详解**|🟡应掌握|① server.port/transport type ② store.mode/db/redis 配置项 ③ 面试：TC Server的关键配置有哪些？|→ Nginx负载均衡(M待做)|
|6.3|**TC 高可用部署方案**|🔴必背|① 多TC实例 + Nginx/LB前置 ② 共享存储(DB/Redis)保证状态一致 ③ 面试：画一下TC的高可用架构图|→ Nginx(M待做) / MySQL MHA(M10)|
|6.4|**TC 故障恢复 & 数据一致性保障**|🟡应掌握|① TC宕机后的恢复流程（读取未完成事务继续处理） ② HA模式下的一致性问题 ③ 面试：TC宕机了正在进行的分布式事务怎么办？|→ M2 AT模式 Phase2 / Redis哨兵(M11)|
|6.5|**Registry & Config Center 集成**|🟡应掌握|① 支持：Nacos/Eureka/Consul/ZK/ETCD 作为注册中心 ② Config支持：Nacos/Apollo/ZK ③ 面试：TC怎么和服务发现结合？|→ Nacos注册中心(M8)|