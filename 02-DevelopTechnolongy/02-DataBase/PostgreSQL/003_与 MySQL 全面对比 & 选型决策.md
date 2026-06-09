|序号|知识点|笔记写什么|important|
|---|---|---|---|
|P3.1|SQL 标准兼容性对比|PG更接近SQL标准（CHECK约束生效 / 外键强制 / 窗口函数 / CTE / LATERAL join）；MySQL的历史遗留不兼容点|核|
|P3.2|并发性能对比|PG MVCC（XID/VACUUM）vs MySQL MVCC（UndoLog）；锁粒度对比；高并发OLTP场景谁更强；高并发写PG的VACUUM调优|🔥🔥🔥|
|P3.3|复制与高可用对比|PG流复制(Streaming Replication) vs MySQL Binlog 主从；PG Patroni（HA管理）vs MySQL MHA/Orchestrator；故障切换速度对比|核|
|P3.4|适用场景选型矩阵|选MySQL：OLTP业务系统 / 互联网Web应用 / 团队熟悉度高 / 生态工具成熟选PostgreSQL：复杂数据分析 / GIS应用 / JSON文档混合查询 / 对SQL标准要求高 / 数据一致性要求极高|🔥🔥🔥|
|P3.5|技术迁移考量|从MySQL迁移到PG的工具（pgloader / AWS DMS /阿里云DTS）；兼容性问题清单（自增策略/日期格式/字符串大小写/注释语法）；双写过渡方案|热|