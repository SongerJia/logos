|序号|知识点|笔记写什么|important|
|---|---|---|---|
|6.1|Elasticsearch Java 客户端演进|TransportClient（已废弃）→ RestHighLevelClient（ES 7 主力，8 弃用）→ Elasticsearch Java Client（ES 8 推荐）；版本对应关系|热|
|6.2|Spring Data Elasticsearch|`ElasticsearchRepository` CRUD / `@Document` / `@Field` 注解；与 MyBatis 共存时的注意事项|🔥🔥 **Spring 项目最常用**|
|6.3|批量操作 Bulk API|bulk request 组装（index/create/update/delete）；一次 bulk 建议 5-15MB / 1000-5000 条；bulk reject 异常处理|核|
|6.4|ES 与 MySQL 数据同步方案|同步双写 / MQ异步 / Canal binlog 解析（推荐）三种方案对比；延迟一致性容忍度讨论|🔥🔥🔥 **实战必问**|