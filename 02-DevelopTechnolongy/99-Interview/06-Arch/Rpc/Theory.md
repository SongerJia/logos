---
title: RPC 面试理论
tags:
  - Arch
  - Interview
---

## 一、RPC 基础概念

> **Q1** 什么是 RPC（Remote Procedure Call）？RPC 和 HTTP 调用的本质区别是什么？

> **Q2** RPC 调用的一次完整链路？这里的动态代理在 Dubbo 中是怎么实现的？

> **Q3** 为什么微服务内部调用倾向 RPC，对外 API 倾向 HTTP/RESTful？

---

## 二、Dubbo 核心架构

> **Q4** Dubbo 的四大核心组件和调用流程? Dubbo 的服务注册和发现是"推"还是"拉"？

> **Q5** Dubbo 的服务暴露过程? 服务引用的过程?

> **Q6** Dubbo 的 URL 总线设计? 为什么 Dubbo 要用 URL 作为配置总线？

---

## 三、Dubbo SPI 扩展机制

> **Q7** Dubbo SPI 和 Java SPI 有什么区别？Dubbo SPI 的"自适应扩展"（Adaptive Extension）是什么？怎么通过 `@Adaptive` 注解动态选择实现？

> **Q8** Dubbo 的 SPI 扩展机制中，"Wrapper 类"（包装类 / AOP 增强）是怎么工作的？"Wrapper" 类必须满足什么条件？

---

## 四、注册中心

> **Q9** Dubbo 支持哪些注册中心？为什么 Dubbo 早期默认 ZK，现在推荐 Nacos？

> **Q10** ZooKeeper 作为注册中心时，网络分区导致 Provider 节点被 ZK 删除了，但实际上 Provider 还活着，怎么办？怎么缓解？

---

## 五、负载均衡策略

> **Q11** Dubbo 内置的 5 种负载均衡策略分别是什么？什么场景用哪个？

> **Q12** Dubbo 的加权随机负载均衡，"权重"是怎么发挥作用、怎么配置的？如果权重配置 200 : 100，实际流量分布会是严格的 2:1 吗？

---

## 六、集群容错

> **Q13** Dubbo 的 6 种集群容错模式? 每个模式的典型应用场景是什么？

> **Q14** Failover + 重试 3 次 = 什么问题？这是一个典型的"非幂等操作 + 重试 = 重复数据"问题。怎么解决？

> **Q15** Dubbo 的熔断机制（Circuit Breaker）在 2.7+ 版本中怎么实现的？这和 Sentinel 的熔断有什么区别？

---

## 七、通信协议与序列化

> **Q16** Dubbo 支持哪些通信协议？什么时候该换协议？

> **Q17** Dubbo 支持哪些序列化方式？Kryo 比 Hessian2 快在哪？Kryo 的缺点是什么？

> **Q18** 序列化协议选型对比? 什么时候选 JSON？

---

## 八、Dubbo 的线程模型

> **Q19** Dubbo 的服务端线程模型? 如果所有业务线程都在处理，新来的请求会怎样？怎么根据业务特点配置线程池？

> **Q20** Dubbo 的"Dispatcher 策略"? 为什么默认是 `all`？什么时候用 `direct`？

---

## 九、Dubbo 服务治理

> **Q21** Dubbo 怎么实现服务的"版本管理"和"灰度发布"？Dubbo 3.x 的"应用级服务发现"对灰度有什么改进？

> **Q22** Dubbo 的参数回调（Callback）和事件通知（oninvoke / onreturn / onthrow）是干什么的？参数回调有什么坑？

---

## 十、Dubbo 3.x 新特性

> **Q23** Dubbo 3.x 的"应用级服务发现"（Application-Level Service Registry）和 Dubbo 2.x 的"接口级服务发现"有什么区别？这解决了 2.x 的什么痛点？接口→应用的映射是怎么维护的？

> **Q24** Dubbo 3.x 的"Triple 协议"是什么？和 Dubbo 2.x 的 `dubbo://` 协议比，Triple 协议解决了什么问题？

> **Q25** Dubbo 3.x 对云原生（Kubernetes / Service Mesh）的支持? 这和传统的 Dubbo + ZK/Nacos 有什么区别？

---

## 十一、RPC vs HTTP / gRPC / Spring Cloud

> **Q26** RPC 框架（Dubbo）和 HTTP 框架（Spring Cloud + Feign + Ribbon）」选型对比。什么时候选 Dubbo？什么时候选 Spring Cloud？

> **Q27** gRPC 的四大核心特性? gRPC 和 Dubbo Triple 协议的区别？

> **Q28** 一个接口用 HTTP RESTful ID 足够清晰，为什么要加一层 RPC？

---

## 十二、综合场景

> **Q29** Dubbo Provider 突然挂了，Consumer 多久能感知到？怎么加快？

> **Q30** Dubbo Consumer 调 Provider 超时，到底是因为什么？怎么定位是哪个原因？

> **Q31** 设计一个 RPC 框架，需要考虑哪些方面？


