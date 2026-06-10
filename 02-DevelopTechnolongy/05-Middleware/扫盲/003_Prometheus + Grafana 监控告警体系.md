现代微服务的"眼睛"，面试问"你做过监控吗"的标准答案技术栈。

|#|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|3.1|**监控体系四黄金指标**|🔴 必背|① **Latency**（延迟 P99/P95/P50）② **Traffic**（QPS/TPS）③ **Errors**（错误率 5xx 比例）④ **Saturation**（饱和度 CPU/内存/连接池使用率）⑤ 再加一个 **Availability**（可用性 SLA）⑥ 面试：你们系统监控了哪些指标？发现异常的处理流程是什么？|→ SkyWalking（APM 链路监控互补）|
|3.2|**Prometheus 核心架构**|🔴 必背|① **Pull 模型**：Prometheus 主动拉取目标 metrics（vs Push 模型 Pushgateway 中转）② **TSDB**：时序数据库，按 metric + labels 组织数据，本地存储 + 远程持久化（Thanos/VictoriaMetrics）③ **PromQL**：查询语言，rate() / histogram_quantile() / agg_over_time() 等 ④ 面试：Prometheus 为什么选 Pull 模型？Push 有什么问题？|→ ELK（日志 vs 指标两种可观测维度）|
|3.3|**四大 Exporter（数据采集）**|🟡 应掌握|① **Node Exporter**：主机层面（CPU/内存/磁盘/网络/文件描述符）② **JMX Exporter**：JVM 层面（GC 时间/堆内存/线程数）③ **MySQL Exporter**：数据库层（连接数/QPS/慢查询/主从延迟）④ **自定义 Exporter**：业务指标（订单量/注册人数/支付成功率），用 Prometheus client 库暴露 ⑤ 面试：你们采集了哪些层面的指标？|→ JVM 调优（GC/内存指标对应）|
|3.4|**Grafana 可视化 & Dashboard**|🟡 应掌握|① Dashboard 设计：概览面板（全局健康度）→ 服务详情 → 告警历史 ② 常用 Panel 类型：Graph（折线图）/ Stat（单值大数字）/ Table / Heatmap（热力图看 QPS 分布）③ 变量模板化：一个 Dashboard 切换环境/实例 ④ 面试：你们的 Grafana Dashboard 有哪些面板？|→ Kibana（ELK 可视化对比）|
|3.5|**AlertManager 告警机制**|🟡 应掌握|① 告警流程：Prometheus 触发规则 → AlertManager 分组/抑制/静默/路由 → 通知渠道（钉钉/企微/邮件/短信）② 告警分级：P0 立即处理（服务宕机）→ P1 小时内（错误率飙升）→ P2 当天（资源预警）③ 面试：告警太多导致"狼来了"怎么办？（阈值合理设置 + 告警聚合 + 抑制规则）|→ XXL-JOB（告警回调）|
|3.6|**PromQL 常用查询语句**|🟡 应掌握|① `rate(http_requests_total[5m])` — QPS 速率 ② `histogram_quantile(0.99, http_request_duration_seconds_bucket)` — P99 延迟 ③ `up == 0` — 探测存活 ④ `process_cpu_seconds_total` — CPU 占用 ⑤ 面试现场写 PromQL：查过去 5 分钟接口错误率超过 1% 的实例|→ SQL 类比思维|
|3.7|**服务发现集成**|🟢 了解|① Prometheus 支持多种服务发现：static / file_sd / consul / kubernetes / ec2 / openstack ② 微服务场景下通常用 Consul 或 Kubernetes SD 动态发现新实例 ③ 面试：新上线一台服务实例，Prometheus 怎么自动发现并开始采集？|→ Nacos 注册中心、→ Consul|
|3.8|**与 Spring Boot Actuator 整合**|🟡 应掌握|① Spring Boot 2.x 内置 `/actuator/prometheus` 端点（需引入 micrometer-registry-prometheus）② micrometer 库统一 metrics 收集，支持切换后端（Prometheus/InfluxDB/JMX）③ 自定义业务 Counter/Gauge/Timer/Histogram ④ 面试：Spring Boot 项目怎么接入 Prometheus 监控？|→ Spring Boot Actuator（M7）|
|3.9|**Prometheus vs Zabbix vs ELK 选型**|🟡 应掌握|① **Prometheus**：指标监控（数值型），强项告警和趋势分析 ② **Zabbix**：传统运维监控（硬件/网络/基础服务），功能全面但扩展性一般 ③ **ELK**：日志聚合分析，文本型，强项搜索和关联分析 ④ 三者互补而非替代：指标 + 日志 + 链路 = 可观测性三支柱 ⑤ 面试：监控系统选型的考虑因素？|→ ELK 日志平台、→ SkyWalking APM|

> **🏗️ 架构追问**：如果让你从零搭建一套中型微服务的监控体系（10+ 个服务，日活 50w），你会怎么设计整体架构？技术选型和落地节奏是什么？