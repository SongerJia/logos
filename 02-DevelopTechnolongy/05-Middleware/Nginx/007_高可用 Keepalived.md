|#|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|7.1|**Keepalived + VRRP 原理**|🟡 应掌握|① VRRP（虚拟路由冗余协议）：主备两台 Nginx 共享一个虚拟 IP（VIP），主挂了 VIP 自动漂移到备 ② Keepalived 做健康检查 + VIP 管理；状态机：MASTER ↔ BACKUP ③ 面试：Keepalived 实现高可用的原理是什么？VIP 漂移需要多少时间？|→ TC Server 高可用（Seata M6）、→ 注册中心高可用（Nacos AP 模式）|
|7.2|**双机热备架构**|🟡 应掌握|① 主备模式（Active-Standby）vs 双主模式（Active-Active，需注意脑裂风险）② 典型拓扑：Client → VIP → [Master Nginx / Backup Nginx] → Upstream ③ 面试：Nginx 高可用方案有哪些？（Keepalived / DNS 轮询 / LVS+F5 / 云 SLB）|→ LVS 四层负载均衡（更底层方案）|
|7.3|**脑裂问题及防护**|🟢 了解|① 脑裂原因：主备之间心跳线断开，两边都认为自己是 MASTER，出现双 VIP ② 防护：增加检测脚本（ping 网关 / 检测自身服务状态）、仲裁机制（第三台机器）③ 面试：什么是脑裂？怎么防止？|→ 分布式理论（CAP / ZooKeeper ZAB）|
|7.4|**Nginx 与云厂商 SLB/ALB 对比**|🟢 了解|① 自建 Keepalived vs 阿里云 SLB（四层）vs ALB（七层）② 云方案的优点：免运维、自动扩缩容、集成监控告警；缺点：费用、灵活性受限 ③ 面试：你们生产环境用的是自建 Nginx 还是云 LB？为什么这么选？|→ 架构方向（技术选型：自建 vs 托管）|