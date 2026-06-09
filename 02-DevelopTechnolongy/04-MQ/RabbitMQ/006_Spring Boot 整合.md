|序号|知识点|笔记写什么|important|
|---|---|---|---|
|6.1|spring-boot-starter-amqp 使用|RabbitTemplate 发送API / @RabbitListener 注解消费 / MessageConverter（JSON序列化）；常用配置项（publisher-confirm/publisher-return/listener/acknowledge-mode）|🔥🔥🔥 **日常开发必备**|
|6.2|消费者工厂定制化|SimpleRabbitListenerContainerFactory 配置：并发数(concurrency) / prefetch / 重试策略 / 错误处理器(ErrorHandler)；不同Consumer组配不同Factory|核|
|6.3|消息转换器(MessageConverter)|Java默认序列化问题（安全漏洞+不可读）；推荐 Jackson2JsonMessageConverter / 自定义Converter；消息体格式约定|热|