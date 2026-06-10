  
ThreadPoolExecutor 七大参数详解

热线程池完整工作流程

热四种拒绝策略

热Executors 四种内置池及缺陷

热四种阻塞队列类型选择

核五种状态机转换流程

ForkJoinPool 工作窃取算法

ScheduledThreadPoolExecutor 定时调度

线程池监控指标与动态调参

线程池最佳实践与大小估算公式


|#|知识点|重要度|三层笔记建议|面试追问|FlowPulse 结合|
|---|---|---|---|---|---|
|B2-06|**ThreadPoolExecutor 七大参数详解**|★★★|L1: corePoolSize/maxPoolSize/keepAliveTime/unit/workQueue/threadFactory/rejectedHandler；L2: 提交任务时的判断逻辑：core满→队列满→max满→拒绝策略；L3: prestartAllCoreThreads()预创建核心线程 vs 默认懒创建|核心线程数怎么定？CPU密集型vs IO密集型的配置差异？|**FlowPulse工作流引擎线程池：core=CPU_2, max=CPU_4, queue=LinkedBlockingQueue(2000)**|
|B2-07|**四种拒绝策略 + 自定义**|★★★|L1: AbortPolicy(抛异常)/CallerRunsPolicy(调用者执行)/DiscardOldestPolicy(丢弃最旧)/DiscardPolicy(静默丢弃)；L2: CallerRunsPolicy如何实现背压(backpressure)；L3: 自定义拒绝策略：记录日志+降级处理+告警通知|生产环境选哪种？自定义拒绝策略要注意什么？|流程任务溢出时降级为同步执行并记录告警|
|B2-08|**BlockingQueue 四种实现选型**|★★★|L1: ArrayBlockingQueue(有界)/LinkedBlockingQueue(可选有界)/SynchronousQueue(直接交接)/PriorityBlockingQueue(优先级)；L2: 有界vs无界的风险(无界可能导致OOM)；L3: 为什么Executors.newFixedThreadPool会OOM？(用的是Integer.MAX_VALUE无界队列)|newCachedThreadPool为什么可能创建大量线程？SynchronousQueue适合什么场景？|FlowPulse根据不同业务选择队列类型|
|B2-09|**线程池如何优雅关闭**|★★★|L1: shutdown()(不再接收新任务，等待已提交完成) vs shutdownNow()(中断正在执行的+返回未执行的)；L2: awaitTermination(timeout)配合使用 + isShutdown/isTerminated状态判断；L3: Spring @PreDestroy中关闭线程池的标准模板代码|shutdownNow一定能停止吗？任务中catch了InterruptedException怎么办？|**FlowPulse Spring Boot优雅关闭时线程池的正确关闭顺序**|
|B2-10|**execute() vs submit() 区别**|★★☆|L1: execute执行Runnable无返回值，submit可提交Callable返回Future；L2: submit的Future.get()会包装ExecutionException；L3: submit(Runnable)返回Future<?>的get()返回null|submit抛出的异常去哪了？如何获取execute中的异常？|流程任务结果收集用submit+Future|
|B2-11|**线程池监控指标**|★★☆|L1: getActiveCount/getPoolSize/getQueueSize/getCompletedTaskCount/getTaskCount；L2: 关键健康指标：活跃率=active/max，队列使用率=size/capacity；L3: Micrometer + Prometheus暴露线程池Metrics + Grafana面板|线程池哪些指标说明有问题？队列持续增长说明什么？|**FlowPulse可观测性：线程池指标纳入Prometheus**|
|B2-12|**Executors 工厂方法的陷阱**|★★☆|L1: newFixedThreadPool/newSingleThreadExecutor → LinkedBlockingQueue(Integer.MAX_VALUE) OOM风险；L2: newCachedThreadPool → SynchronousQueue + 无限创建线程(可能耗尽文件描述符)；L3: newScheduledThreadPool → ScheduledThreadPoolExecutor(同样OOM风险)|阿里规范为什么禁止Executors？自己创建要配哪些参数？|FlowPulse全部自定义ThreadPoolExecutor|
|B2-13|**ForkJoinPool 与工作窃取**|★★☆|L1: 分治任务框架，每个线程有自己的双端工作队列；L2: 工作窃取(Work Stealing)：空闲线程从其他队列尾部取任务执行；L3: commonPool()默认线程数=CPU核数，parallelStream底层使用|ForkJoinPool和ThreadPoolExecutor的区别？什么时候用ForkJoin？|