|序号|知识点|笔记写什么|important|
|---|---|---|---|
|2.1|核心字段类型体系|text（全文检索）/ keyword（精确匹配/排序聚合）/ long/integer/date/boolean/nested/object/geo_point/ip；每个类型的典型使用场景|🔥🔥🔥 **text vs keyword 是坑王**|
|2.2|Dynamic Mapping 动态映射|true（自动推断类型）/ strict（遇到未知字段报错）/ false（忽略未知字段）；日期推断规则；生产环境为什么建议关闭 dynamic|核|
|2.3|Multi-Fields 多字段|同一字段同时建 text + keyword 子字段；`"title": { "type": "text", "fields": { "keyword": { "type": "keyword" } } }` 典型配置|🔥🔥 **实战必备**|
|2.4|Index Template & Component Template|模板优先级；通配符匹配规则；生产环境如何统一管控 mapping/settings|热|