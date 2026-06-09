|序号|知识点|笔记写什么|重要度|
|---|---|---|---|
|1.1|RabbitMQ 整体架构|Broker / Virtual Host（虚拟主机，多租户隔离）/ Exchange / Queue / Binding / Connection / Channel；画组件关系图|🔥🔥🔥 **入门基础**|
|1.2|AMQP 协议核心概念|为什么 RabbitMQ 要自己搞协议而不是用自定义协议（像 RMQ/Kafka）；AMQP 0-9-1 模型：Producer → Exchange → Binding → Queue → Consumer；协议分层|热|
|1.3|Connection vs Channel|一个 TCP Connection 复用多个 Channel（多路复用）；为什么需要 Channel 而不是每个操作一个连接（TCP开销大）；Channel 线程安全问题|核|
|1.4|Erlang 语言 & OTP 平台|RabbitMQ 用 Erlang 写的原因（电信级可靠性/OTP容错模型）；了解即可不需要深入 Erlang；热升级能力（不停机更新版本）|热|