| 序号  | 知识点                  | 笔记写什么                                                                                                                        | 重要度    |
| --- | -------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------ |
| 6.1 | Controller 选举与管理     | 第一个成功在 ZK 创建 /controller 节点的 Broker 成为 Controller（KRaft 模式下是 Quorum 选举）；Controller 负责 Partition Leader 选举和元数据管理              | 热      |
| 6.2 | 多副本下的数据一致性           | min.insync.replicas 参数（最少写入副本数，与 acks=all 配合）；ACK 级别 + ISR 大小共同决定数据可靠性；生产环境推荐配置（acks=all + min.isr=2 + replication.factor=3） | 🔥🔥🔥 |
| 6.3 | 机架感知(Rack Awareness) | broker.rack 参数；Partition 副本分布在不同机架；防止整个机架故障导致 Partition 不可用；云环境（AWS AZ / 阿里云可用区）的配置方式                                        | 热      |
| 6.4 | KRaft 模式深入           | 去 ZK 后元数据存在哪（`__cluster_metadata` Topic）；Controller 节点 Quorum 基于 Raft；迁移步骤（ZK → KRaft 混合模式 → 纯 KRaft）；KRaft 的优缺点             | 核      |