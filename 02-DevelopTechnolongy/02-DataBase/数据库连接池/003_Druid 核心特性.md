| 序号  | 知识点                | 笔记写什么                                                                                          | important            |
| --- | ------------------ | ---------------------------------------------------------------------------------------------- | -------------------- |
| 3.1 | Druid 的整体架构        | DataSource → DruidPooledConnection → DruidConnectionHolder；DruidAbstractDataSource 抽象层设计       | 核                    |
| 3.2 | SQL 监控体系           | FilterChain 责任链模式（StatFilter / LogFilter / WallFilter）；DruidStatManagerFacade 数据采集；Web页面监控集成方式 | 🔥🔥🔥 **Druid招牌功能** |
| 3.3 | 防SQL注入（WallFilter） | SQL语法解析 + 白名单/黑名单规则；多数据库方言支持；与 MyBatis #{}防注入的关系和互补                                            | 热                    |
| 3.4 | Druid 连接池内部实现      | DruidConnectionHolder 数组存储；数组淘汰策略（LRU-like via evictionRunnable）；与 HikariCP ConcurrentBag 的对比  | 核                    |