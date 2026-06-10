|序号|知识点|笔记写什么|重要度|
|---|---|---|---|
|2.1|Topic 与 Partition 的关系|一个 Topic = N 个 Partition（可动态增加）；Partition 是并行度的基本单位；Partition 数量决定最大并发消费数|🔥🔥🔥 **基础中的基础**|
|2.2|Partition 副本(Replica)机制|Leader Replica（对外读写）/ Follower Replica（只同步不对外）/ ISR(In-Sync Replicas) 集合；AR = ISR + OSR；副本数建议 ≥3|🔥🔥🔥|
|2.3|Leader 选举与故障转移|Controller 负责 Partition Leader 选举；Preferred Leader（副本列表第一个）优先；unclean.leader.election.enable（是否允许非ISR节点成为Leader，数据丢失风险）|核|
|2.4|Partition 均匀分布策略|创建 Topic 时 Broker 间 Partition 均匀分布算法；分区重分配(reassign partitions) 工具使用场景|热|
|2.5|消费者组(Consumer Group)与Partition 的关系|一个 Partition 只能被同一个 CG 内的一个 Consumer 消费；CG 内：负载均衡 / CG 间：广播（Pub-Sub）；**CG 数量 ≠ Partition 数量时的分配情况**|🔥🔥🔥🔥 **超高频考点**|
|2.6|消息有序性保证|Partition 内有序（offset 递增）/ 跨 Partition 无序；需要全局有序 → 只能一个 Partition；需要业务有序 → 相同 Key 的 msg 进同一 Partition|🔥🔥🔥|