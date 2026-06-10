|#|知识点|核心内容|面试追问|FlowPulse 对应|
|---|---|---|---|---|
|**2.1.1**|**CAP 定理**|Eric Brewer 2000年提出：Consistency(一致性)、Availability(可用性)、Partition tolerance(分区容错)，三者最多同时满足两个|"CAP说只能三选二，为什么很多系统号称CP+AP都支持？"|Nacos可切换CP/AP模式 / Seata在P发生时的取舍|
|**2.1.2**|**C - 强一致性 (Linearizability)**|任何时刻所有节点看到的数据一致；写入后立即可读；代价是延迟和可用性损失|"强一致性和最终一致性的本质区别？"|Seata TCC模式追求强一致 / MySQL主从同步|
|**2.1.3**|**A - 高可用性 (Availability)**|每个请求都能收到(非错误)响应，但不保证是最新的；强调"服务不挂"|"可用性达到99.99%意味着什么？怎么计算？"|Gateway多实例部署 + Sentinel熔断保活|
|**2.1.4**|**P - 分区容错 (Partition Tolerance)**|网络分区(节点间通信中断)是分布式系统的常态而非异常；必须面对的问题|"什么是网络分区？机房光纤被挖断算吗？"|Nacos集群跨机房部署应对分区|
|**2.1.5**|**CAP 的取舍实战：CP vs AP**|CP选一致(放弃可用)：ZooKeeper、Seata TC、etcd；AP选可用(放弃一致)：Nacos(AP模式)、Eureka、Cassandra|"注册中心应该选CP还是AP？"|FlowPulse注册中心用Nacos，临时实例=AP(可用优先)，持久实例=CP(一致优先)|
|**2.1.6**|**BASE 理论**|Basically Available(基本可用) + Soft state(软状态) + Eventually consistent(最终一致)；对CAP中AP方案的补充理论|"BASE是对CAP的补充还是替代？"|**Seata AT模式就是BASE思想的实践**：本地事务先提交(软状态)，异步回滚保证最终一致|
|**2.1.7**|**PACELC 定理（CAP延伸）**|Partition时：Availability vs Consistency；无Partition时：Latency vs Consistency；更细粒度的决策模型|"为什么说PACELC比CAP更准确？"|RocketMQ选择L(低延迟)+E(最终一致)：消息投递快但可能重复消费|

> **💡 面试金句**："CAP不是让你三选二，而是告诉你：当P发生时(网络分区)，你必须在C和A之间做选择。没有P的时候，你还要考虑延迟(L)和一致性的权衡(PACELC)。"