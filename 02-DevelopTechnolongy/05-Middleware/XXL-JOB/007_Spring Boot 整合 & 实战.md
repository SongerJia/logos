|序号|知识点|笔记写什么|important|
|---|---|---|---|
|7.1|xxl-job-core Spring Boot Starter 使用|Maven 依赖 / yaml 配置（admin-addresses / executor.appname / executor.ip / executor.port / executor.logpath / accessToken）/ `@XxlJob` 注解开发任务；完整配置示例|🔥🔥🔥 **日常开发必备**|
|7.2|生产环境最佳实践|安全配置（accessToken 防止非法调用）/ 日志保留策略 / 任务分组按微服务划分 / 避免任务间互相依赖（不要A任务完成触发B，容易级联失败）/ 大批量数据处理用分片广播|🔥🔥🔨 **经验之谈**|