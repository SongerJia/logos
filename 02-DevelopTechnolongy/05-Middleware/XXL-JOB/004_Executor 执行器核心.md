|序号|知识点|笔记写什么|important|
|---|---|---|---|
|4.1|Executor 启动与自动注册|Executor 启动后向 Admin 发起注册请求（IP + Port +AppName）→ 写入 `xxl_job_registry` 表 → 每30秒心跳续期（auto-registry 机制）；Admin 通过查询 registry 获取在线 Executor 列表|🔥🔥🔥 **必须搞懂**|
|4.2|Executor 内部线程池模型|XxlJobExecutor 内置线程池（默认200线程）；`XxlJobHandler` 封装任务逻辑；任务超时控制（timeout 参数）；线程池拒绝策略（默认 CallerRunsPolicy）|🔥🔥🔥|
|4.3|任务执行模式|BEAN 模式（反射调用 Spring Bean 方法，类模式 / 方法模式）/ GLUE 模式（在线代码）；`@XxlJob("jobName")` 注解用法；Init / Destroy 生命周期方法|🔥🔥🔥 **日常开发必备**|
|4.4|Executor 与 Admin 交互接口|run（执行任务）/ log（回调日志）/ beat（心跳）/ idleBeat（空闲探测，判断是否真的空闲）；各接口的作用和调用时机|核|
|4.5|阻塞处理策略|**串行**（默认，排队等待）/ **丢弃后续调度**（覆盖之前未完成的）/ **覆盖之前调度**（丢弃旧的执行新的）；三种策略的场景选择|🔥🔥🔥🔥 **高频考点**|