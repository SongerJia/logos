# DDD 核心概念深度解析

> 领域驱动设计：从业务出发建模，让代码结构与业务结构对齐

---

## 目录

- [第一章 为什么需要 DDD](#第一章为什么需要-ddd)
- [第二章 战略设计 — 领域与子域](#第二章战略设计领域与子域)
- [第三章 战略设计 — 限界上下文](#第三章战略设计限界上下文)
- [第四章 战略设计 — 上下文映射](#第四章战略设计上下文映射)
- [第五章 战术设计 — 实体与值对象](#第五章战术设计实体与值对象)
- [第六章 战术设计 — 聚合与聚合根](#第六章战术设计聚合与聚合根)
- [第七章 战术设计 — 领域服务](#第七章战术设计领域服务)
- [第八章 战术设计 — 领域事件](#第八章战术设计领域事件)
- [第九章 战术设计 — 工厂与仓储](#第九章战术设计工厂与仓储)
- [第十章 代码架构落地](#第十章代码架构落地)
- [第十一章 CQRS 与事件溯源](#第十一章cqrs-与事件溯源)
- [第十二章 DDD 与微服务](#第十二章ddd-与微服务)
- [第十三章 DDD 实战案例 — 电商订单](#第十三章ddd-实战案例电商订单)
- [第十四章 DDD 常见误区与最佳实践](#第十四章ddd-常见误区与最佳实践)
- [第十五章 10 道面试高频题](#第十五章10-道面试高频题)

---

## 第一章 为什么需要 DDD

### 1.1 传统开发的痛点

```
┌──────────────────────────────────────────────────────────────┐
│           传统数据驱动开发（贫血模型）                         │
│                                                              │
│  // Service 层承载所有业务逻辑                                │
│  public class OrderService {                                 │
│      public void createOrder(Long userId, List<Item> items) {│
│          // 100行业务逻辑全在Service里                        │
│          Order order = new Order();                          │
│          order.setUserId(userId);        // setter           │
│          order.setStatus("CREATED");     // setter           │
│          order.setItems(items);          // setter           │
│          BigDecimal total = BigDecimal.ZERO;                 │
│          for (Item item : items) {                           │
│              total = total.add(item.getPrice());             │
│          }                                                   │
│          order.setTotalAmount(total);    // setter           │
│          // 校验、计算折扣、库存扣减... 全在Service            │
│          orderRepository.save(order);                        │
│      }                                                       │
│  }                                                           │
│                                                              │
│  // Order 只是数据容器（贫血模型）                             │
│  public class Order {                                        │
│      private Long userId;                                    │
│      private String status;                                  │
│      private BigDecimal totalAmount;                         │
│      // 只有 getter/setter，没有业务行为                      │
│  }                                                           │
│                                                              │
│  问题：                                                      │
│  ❌ Order 失去表达能力 — "setStatus" 不如 "pay" 直观          │
│  ❌ Service 膨胀 — 所有逻辑堆在一个类，几千行                 │
│  ❌ 业务散落 — 同一业务概念在不同Service中重复                 │
│  ❌ 难以演进 — 加字段改Service改DTO改Mapper改接口             │
│  ❌ 无法对齐 — 代码结构与业务结构严重偏离                     │
└──────────────────────────────────────────────────────────────┘
```

### 1.2 DDD 的核心思想

```
┌──────────────────────────────────────────────────────────────┐
│              DDD 核心公式                                     │
│                                                              │
│  代码结构 ≈ 业务结构                                         │
│                                                              │
│  让软件的"语言"和业务的"语言"统一：                           │
│  - 业务说"下单" → 代码有 Order.create()                      │
│  - 业务说"支付" → 代码有 Order.pay()                         │
│  - 业务说"发货" → 代码有 Order.deliver()                     │
│  - 业务说"取消" → 代码有 Order.cancel()                      │
│                                                              │
│  而不是：                                                    │
│  - 业务说"下单" → 代码有 OrderService.createOrder()          │
│    然后里面是 100 行 setter 和 if-else                        │
│                                                              │
│  DDD = Domain-Driven Design                                 │
│  Domain = 颢域 = 业务知识的边界                               │
│  Driven = 驱动 = 业务决定技术，技术不决定业务                  │
│  Design = 设计 = 战略设计 + 战术设计                          │
│                                                              │
│  Eric Evans 2003年提出，核心三部曲：                          │
│  1. 统一语言（Ubiquitous Language）                          │
│  2. 战略设计（Strategic Design）                             │
│  3. 战术设计（Tactical Design）                              │
└──────────────────────────────────────────────────────────────┘
```

### 1.3 统一语言（Ubiquitous Language）

```
统一语言 = 开发团队和业务团队使用同一套术语

  ┌──────────────────────────────────────────────────────────┐
  │  ❌ 没有统一语言：                                       │
  │                                                          │
  │  业务说"客户" → 开发叫"User"                             │
  │  业务说"下订单" → 开发叫"insertOrderRecord"              │
  │  业务说"支付完成" → 开发叫"updateOrderStatus(2)"         │
  │  业务说"退款" → 开发叫"refundProcess"                    │
  │                                                          │
  │  同一个概念有不同的名字 → 沟通成本极高                    │
  │                                                          │
  │  ✅ 有统一语言：                                         │
  │                                                          │
  │  业务说"客户" → 代码叫 Customer                          │
  │  业务说"下订单" → 代码叫 Order.place()                   │
  │  业务说"支付完成" → 代码叫 Order.markPaid()              │
  │  业务说"退款" → 代码叫 Order.refund()                    │
  │                                                          │
  │  代码本身就是业务文档 → 沟通成本为零                      │
  └──────────────────────────────────────────────────────────┘

  统一语言来源：
  1. 与业务专家面对面讨论（事件风暴 Event Storming）
  2. 从需求文档中提取核心术语
  3. 在代码中直接使用业务术语命名
  4. 持续维护术语表（ glossary ）

  ⚠️ 统一语言是 DDD 的第一前提，没有统一语言就没有 DDD
```

### 1.4 贫血模型 vs 充血模型

```
┌──────────────────────────────────────────────────────────────┐
│              贫血模型 vs 充血模型                              │
│                                                              │
│  贫血模型（Anemic Model）：                                  │
│  对象只有属性（数据），没有行为（逻辑）                       │
│  所有逻辑在 Service 层                                       │
│  = 数据库表的对象化映射                                      │
│                                                              │
│  充血模型（Rich Model）：                                    │
│  对象既有属性又有行为                                        │
│  业务逻辑封装在领域对象内部                                  │
│  = 业务概念的代码化表达                                      │
│                                                              │
│  ┌─ 贫血 ────────────────────────────────────┐              │
│  │ class Order {                              │              │
│  │     private String status;                 │              │
│  │     // getter/setter only                  │              │
│  │ }                                          │              │
│  │                                            │              │
│  │ class OrderService {                       │              │
│  │     void pay(Order order) {                │              │
│  │         if (order.getStatus() != "CREATED")│              │
│  │             throw new BizException();      │              │
│  │         order.setStatus("PAID");           │              │
│  │     }                                      │              │
│  │ }                                          │              │
│  └────────────────────────────────────────────┘              │
│                                                              │
│  ┌─ 充血 ────────────────────────────────────┐              │
│  │ class Order {                              │              │
│  │     private OrderStatus status;            │              │
│  │                                           │              │
│  │     void pay() {                           │              │
│  │         // 业务规则封装在领域对象内         │              │
│  │         if (status != OrderStatus.CREATED) │              │
│  │             throw new OrderStateException( │              │
│  │                 "只能支付已创建的订单");    │              │
│  │         this.status = OrderStatus.PAID;    │              │
│  │         // 领域事件                        │              │
│  │         registerEvent(new OrderPaidEvent(  │              │
│  │             this.id));                     │              │
│  │     }                                      │              │
│  │ }                                          │              │
│  └────────────────────────────────────────────┘              │
│                                                              │
│  关键区别：                                                  │
│  贫血 → OrderService 告诉 Order "你被支付了"                │
│  充血 → Order 自己知道 "我该怎么支付"                       │
│                                                              │
│  DDD 推崇充血模型，但注意：                                  │
│  不是所有对象都需要充血 — 值对象可以纯粹是数据               │
│  不是充血 = 业务逻辑全塞到 Entity — 要合理分配              │
└──────────────────────────────────────────────────────────────┘
```

---

## 第二章 战略设计 — 领域与子域

### 2.1 领域的定义

```
领域（Domain）= 一个组织所做的事情及其所包含的一切知识

  电商领域：
    商品、订单、支付、物流、评价、促销...

  银行领域：
    账户、转账、贷款、风控、报表...

领域 = 业务问题的边界
子域 = 领域内更小的问题边界

为什么需要划分子域？
  一个大领域太复杂 → 拆成更小的子域 → 每个子域独立建模
```

### 2.2 三种子域

```
┌──────────────────────────────────────────────────────────────┐
│              三种子域分类                                      │
│                                                              │
│  ┌─ 核心域（Core Domain）─────────────────────────────┐     │
│  │ 业务核心竞争力，必须自己做，不能外包               │     │
│  │ 投入最多资源，建模最精细                           │     │
│  │                                                   │     │
│  │ 电商例：商品搜索推荐、秒杀、动态定价               │     │
│  │ 银行例：风控模型、信贷评估                         │     │
│  │ 社交例：Feed流排序、内容推荐                       │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  ┌─ 支撑域（Supporting Subdomain）────────────────────┐     │
│  │ 不是核心竞争力，但核心域依赖它                     │     │
│  │ 可以自己做，也可以外包                             │     │
│  │                                                   │     │
│  │ 电商例：订单管理、支付接入、物流对接               │     │
│  │ 银行例：短信通知、文件存储                         │     │
│  │ 社交例：消息推送、举报审核                         │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  ┌─ 通用域（Generic Subdomain）────────────────────────┐     │
│  │ 所有组织都需要的通用能力，无差异化                 │     │
│  │ 优先使用现成方案/SaaS，不值得自己投入               │     │
│  │                                                   │     │
│  │ 电商例：用户认证、权限管理、邮件发送               │     │
│  │ 银行例：组织架构、审批流程                         │     │
│  │ 社交例：短信验证码、OAuth登录                      │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  ⚠️ 分类原则：                                               │
│  同一功能在不同企业可能属于不同子域                           │
│  - 物流对京东 = 核心域（自建物流是竞争力）                   │
│  - 物流对普通电商 = 支撑域（对接第三方即可）                 │
│  - 物流对物流公司 = 核心域（这就是他们的主业）               │
│                                                              │
│  子域决定投入策略：                                           │
│  核心域 → 精细建模 + 最优团队 + 不外包                       │
│  支撑域 → 合理建模 + 可外包 + 按需投入                       │
│  通用域 → 粗糙建模 + 用开源/SaaS + 最少投入                  │
└──────────────────────────────────────────────────────────────┘
```

### 2.3 子域划分方法

```
子域划分 = 从业务流程中识别独立的问题空间

方法一：事件风暴（Event Storming）

  ┌──────────────────────────────────────────────────────────┐
  │  1. 识别领域事件（橙色便利贴）                            │
  │     "订单已创建"、"支付已完成"、"商品已发货"              │
  │                                                          │
  │  2. 识别命令（蓝色便利贴）触发领域事件                    │
  │     "创建订单" → 触发 → "订单已创建"                     │
  │                                                          │
  │  3. 识别聚合（黄色便利贴）执行命令                        │
  │     "Order" 聚合 执行 "创建订单" 命令                    │
  │                                                          │
  │  4. 识别外部系统/策略/读模型                              │
  │     支付网关、风控策略、订单列表                          │
  │                                                          │
  │  5. 按业务边界分组 → 子域识别                             │
  │     订单相关 → 订单子域                                   │
  │     支付相关 → 支付子域                                   │
  │     物流相关 → 物流子域                                   │
  └──────────────────────────────────────────────────────────┘

方法二：业务流程分析

  完整购买流程：
  浏览商品 → 加入购物车 → 下单 → 支付 → 发货 → 确收 → 评价

  按业务能力拆分：
  商品子域：浏览/搜索/详情
  购物车子域：加购/修改/清空
  订单子域：下单/取消/修改
  支付子域：支付/退款/对账
  物流子域：发货/配送/签收
  评价子域：评价/评分/追评
```

---

## 第三章 战略设计 — 限界上下文

### 3.1 什么是限界上下文

```
┌──────────────────────────────────────────────────────────────┐
│              限界上下文（Bounded Context）                     │
│                                                              │
│  定义：一个明确的语义边界，在这个边界内                       │
│  统一语言的每个术语有且只有一个确切含义                       │
│                                                              │
│  为什么需要？                                                │
│  同一个词在不同业务语境中含义不同：                           │
│                                                              │
│  "Product" 的含义：                                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ 在商品上下文中：                                      │   │
│  │   Product = SKU、价格、描述、图片、库存               │   │
│  │   → 关注展示和搜索                                    │   │
│  │                                                      │   │
│  │ 在订单上下文中：                                      │   │
│  │   Product = 订单行项目、购买数量、成交价格             │   │
│  │   → 关注交易和计算                                    │   │
│  │                                                      │   │
│  │ 在物流上下文中：                                      │   │
│  │   Product = 包裹、重量、体积、配送要求                 │   │
│  │   →关注配送和仓储                                     │   │
│  │                                                      │   │
│  │ 在评价上下文中：                                      │   │
│  │   Product = 被评价对象、评分、评论数                   │   │
│  │   → 关注反馈和口碑                                    │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  如果只有一个 Product 类 → 所有属性混在一起                   │
│  → 类膨胀 → 不知道哪些属性属于哪个业务 → 贫血加剧            │
│                                                              │
│  限界上下文解决：                                             │
│  商品上下文有自己的 Product 类（含价格/描述/图片）            │
│  订单上下文有自己的 OrderItem 类（含数量/成交价）             │
│  物流上下文有自己的 PackageItem 类（含重量/体积）             │
│  → 各自建模，各自演进，互不干扰                               │
│                                                              │
│  ⚠️ 关键理解：                                               │
│  限界上下文 ≠ 子域                                           │
│  子域 = 问题空间（业务需要什么）                              │
│  限界上下文 = 解决空间（软件如何实现）                        │
│  通常 1个子域 ≈ 1个限界上下文，但并非必须                    │
└──────────────────────────────────────────────────────────────┘
```

### 3.2 限界上下文的划分原则

```
限界上下文划分五原则：

  1. 语言一致性原则
     同一上下文内，术语含义统一无歧义
     如果一个词在讨论中产生歧义 → 划分边界

  2. 业务变化速率原则
     变化频率不同的业务不应放在同一上下文
     商品展示经常变 → 评价逻辑很少变 → 分开

  3. 业务关联度原则
     强关联的业务放一起，弱关联的分开
     下单+支付 = 流程紧密 → 可以同一上下文
     商品+评价 = 独立逻辑 → 不同上下文

  4. 团队归属原则
     不同团队负责的业务 → 不同上下文
     避免跨团队修改同一代码 → 减少协作摩擦

  5. 技术差异原则
     技术栈差异大的业务 → 不同上下文
     推荐引擎用Python → 订单引擎用Java → 分开

  划分粒度参考：
  ┌──────────────────────────────────────────┐
  │ 粒度   │ 上下文数 │ 适用               │
  │──────────────────────────────────────────│
  │ 过粗   │ 3~5     │ 小团队，业务简单   │
  │ 合适   │ 8~15    │ 中型团队，核心业务 │
  │ 过细   │ 20+     │ 过度拆分，协调成本 │
  └──────────────────────────────────────────┘
```

### 3.3 电商系统的限界上下文划分

```
┌──────────────────────────────────────────────────────────────┐
│              电商系统限界上下文示例                             │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  商品上下文 (Product Context)                          │  │
│  │  统一语言: Product/SKU/Category/Price/Inventory       │  │
│  │  核心域: 商品搜索与推荐                               │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  订单上下文 (Order Context)                            │  │
│  │  统一语言: Order/OrderItem/Place/Cancel/Modify        │  │
│  │  支撑域: 订单管理与流程                               │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  支付上下文 (Payment Context)                          │  │
│  │  统一语言: Payment/Refund/Channel/Transaction         │  │
│  │  支撑域: 支付接入与对账                               │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  物流上下文 (Shipping Context)                         │  │
│  │  统一语言: Shipment/Tracking/Delivery/Package         │  │
│  │  支撑域: 物流对接                                     │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  用户上下文 (User Context)                             │  │
│  │  统一语言: Customer/Address/Profile/Auth              │  │
│  │  通用域: 用户认证与信息管理                            │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  促销上下文 (Promotion Context)                        │  │
│  │  统一语言: Coupon/Discount/Activity/Rule              │  │
│  │  核心域: 促销策略                                     │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  每个上下文：                                                │
│  - 有自己的统一语言（术语表）                                │
│  - 有自己的领域模型（实体/聚合）                             │
│  - 有自己的持久化（数据库/表）                               │
│  - 有自己的代码模块/微服务                                  │
└──────────────────────────────────────────────────────────────┘
```

---

## 第四章 战略设计 — 上下文映射

### 4.1 上下文之间的关系模式

```
┌──────────────────────────────────────────────────────────────┐
│          上下文映射（Context Map）9种关系模式                   │
│                                                              │
│  ┌─ 1. 合作关系（Partnership）────────────────────────┐     │
│  │ 两个团队密切协作，接口同步演进                       │     │
│  │ 适合：紧密耦合的业务流程（下单+支付）                │     │
│  │ 风险：协调成本高                                    │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  ┌─ 2. 共享内核（Shared Kernel）───────────────────────┐     │
│  │ 两个上下文共享一部分模型（如枚举/DTO）               │     │
│  │ 适合：小型共享概念（订单状态枚举）                   │     │
│  │ 风险：共享部分变化影响双方                           │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  ┌─ 3. 客户-供应商（Customer-Supplier）────────────────┐     │
│  │ 下游(客户)依赖上游(供应商)的接口                     │     │
│  │ 上游按自己的计划发布，下游需要适配                   │     │
│  │ 适合：下游可接受上游的演进节奏                       │     │
│  │ 例：订单上下文(下游)依赖用户上下文(上游)的Customer   │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  ┌─ 4. 遵奉者（Conformist）────────────────────────────┐     │
│  │ 下游完全遵循上游的模型，不做任何翻译                 │     │
│  │ 适合：上游是标准/平台（如OAuth2协议）                │     │
│  │ 风险：下游失去自主性                                │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  ┌─ 5. 防腐层（Anti-Corruption Layer, ACL）────────────┐     │
│  │ ⭐ 最重要模式！                                      │     │
│  │ 下游建立翻译层，将上游模型翻译为自己的模型           │     │
│  │ 保护自己的领域模型不被上游"腐蚀"                    │     │
│  │ 适合：上游模型不适合下游业务语义                     │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  ┌─ 6. 开放主机服务（Open Host Service, OHS）──────────┐     │
│  │ 上游发布标准化协议/API供下游使用                     │     │
│  │ 适合：上游是平台型服务（如支付网关API）               │     │
│  │ 例：支付上下文发布标准PaymentAPI                     │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  ┌─ 7. 发布语言（Published Language）──────────────────┐     │
│  │ OHS + 标准文档/协议格式（REST/事件/protobuf）        │     │
│  │ 适合：跨组织集成                                    │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  ┌─ 8. 各行其道（Separate Ways）───────────────────────┐     │
│  │ 两个上下文完全独立，不做集成                         │     │
│  │ 适合：无直接业务依赖                                │     │
│  │ 例：商品上下文和物流上下文可以暂时各行其道           │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  ┌─ 9. 大泥球（Big Ball of Mud）───────────────────────┐     │
│  │ ❌ 最糟糕模式！                                      │     │
│  │ 混乱的边界，所有模型纠缠在一起                       │     │
│  │ 没有统一语言，没有明确边界                           │     │
│  │ 目标：逐步从大泥球拆出限界上下文                     │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  ⚠️ 防腐层（ACL）是最关键的实践：                            │
│  下游绝不直接使用上游的领域模型                               │
│  通过 ACL 翻译 → 保护自己的模型纯洁性                        │
└──────────────────────────────────────────────────────────────┘
```

### 4.2 防腐层实现

```java
// 订单上下文需要用户信息，但不能直接依赖用户上下文的 User 实体

// ❌ 错误做法：直接使用上游模型
class OrderService {
    void placeOrder(User user) {  // 直接用User上下文的User类
        // User类包含密码、角色等订单不需要的信息 → 被腐蚀
    }
}

// ✅ 正确做法：通过防腐层翻译
// 订单上下文有自己的 Customer 概念
class Customer {  // 订单上下文的模型
    private CustomerId id;
    private String name;
    private Address shippingAddress;
    // 只包含订单需要的字段
}

// 防腐层：将用户上下文的 User 翻译为订单上下文的 Customer
class UserToCustomerAdapter {  // Anti-Corruption Layer
    private UserServiceClient userServiceClient;  // 调用上游接口

    public Customer getCustomer(UserId userId) {
        // 获取上游的 User DTO
        UserDTO userDTO = userServiceClient.getUser(userId);
        // 翻译为下游的 Customer
        return new Customer(
            new CustomerId(userDTO.getId()),
            userDTO.getName(),
            new Address(userDTO.getProvince(), userDTO.getCity(),
                        userDTO.getDetail())
        );
    }
}

// 订单上下文内部只使用 Customer，不接触 User
class OrderApplicationService {
    private UserToCustomerAdapter acl;  // 防腐层

    public void placeOrder(UserId userId, List<OrderItemRequest> items) {
        Customer customer = acl.getCustomer(userId);  // 通过ACL获取
        Order order = Order.place(customer, items);
        orderRepository.save(order);
    }
}
```

### 4.3 上下文映射图

```
电商系统上下文映射图：

  ┌─────────────────────────────────────────────────────────┐
  │                                                         │
  │   用户上下文 ──── OHS+PL ────→ 订单上下文              │
  │    (上游)        (标准API)    (下游，通过ACL翻译)       │
  │                                                         │
  │   商品上下文 ──── OHS+PL ────→ 订单上下文              │
  │    (上游)        (商品API)    (下游，ACL翻译Product→    │
  │                              OrderItemProduct)          │
  │                                                         │
  │   订单上下文 ──── Partnership ─→ 支付上下文             │
  │    (密切协作)      (共享流程)   (密切协作)              │
  │                                                         │
  │   订单上下文 ──── Customer-Supplier ─→ 物流上下文       │
  │    (供应商)        (提供订单信息)  (客户，适配)          │
  │                                                         │
  │   促销上下文 ──── OHS+PL ────→ 订单上下文              │
  │    (上游)        (优惠规则API)  (下游，ACL翻译)         │
  │                                                         │
  │   评价上下文 ──── Separate Ways ─→ 其他上下文           │
  │    (暂不集成)                              │            │
  │                                                         │
  └─────────────────────────────────────────────────────────┘

  映射图使用方法：
  1. 画出所有限界上下文
  2. 用箭头标注依赖方向（A依赖B → A→B）
  3. 在箭头上标注关系模式（ACL/OHS/Partnership等）
  4. 标注组织边界（同一团队/不同团队/外部系统）
```

---

## 第五章 战术设计 — 实体与值对象

### 5.1 实体（Entity）

```
┌──────────────────────────────────────────────────────────────┐
│              实体（Entity）                                    │
│                                                              │
│  定义：有唯一标识符（ID）的对象，ID不变则实体不变             │
│  两个实体相等 = 它们的ID相等                                 │
│                                                              │
│  特征：                                                      │
│  1. 有唯一标识（ID/业务编号）                                │
│  2. 生命周期内属性可变（但ID不变）                            │
│  3. 可通过ID追踪和引用                                       │
│  4. 比较相等性基于ID而非属性                                 │
│                                                              │
│  示例：                                                      │
│  Order（订单） — 订单号不变，但状态/金额/地址可以变           │
│  Customer（客户） — 客户ID不变，但姓名/地址可以变             │
│  Account（账户） — 账号不变，但余额/状态可以变                │
│                                                              │
│  代码实现：                                                  │
│  public class Order extends Entity {                         │
│      private OrderId id;           // 唯一标识               │
│      private OrderStatus status;   // 可变属性               │
│      private BigDecimal totalAmount; // 可变属性             │
│                                                              │
│      @Override                                               │
│      public boolean equals(Object o) {                       │
│          if (this == o) return true;                         │
│          if (!(o instanceof Order)) return false;            │
│          Order other = (Order) o;                            │
│          return id.equals(other.id);  // 基于ID比较          │
│      }                                                       │
│                                                              │
│      @Override                                               │
│      public int hashCode() {                                 │
│          return id.hashCode();                               │
│      }                                                       │
│                                                              │
│      // 行为方法                                             │
│      public void pay(PaymentMethod method) { ... }           │
│      public void cancel() { ... }                            │
│  }                                                           │
│                                                              │
│  ⚠️ 实体的 equals/hashCode 必须基于ID                       │
│     不是基于属性 → 因为属性可以变，但实体还是同一个           │
└──────────────────────────────────────────────────────────────┘
```

### 5.2 值对象（Value Object）

```
┌──────────────────────────────────────────────────────────────┐
│              值对象（Value Object）                            │
│                                                              │
│  定义：没有唯一标识符的对象，通过属性值判断相等               │
│  两个值对象相等 = 所有属性相等                                │
│                                                              │
│  特征：                                                      │
│  1. 无唯一标识（不需要ID）                                   │
│  2. 不可变（Immutable）— 创建后不可修改                      │
│  3. 通过属性值判断相等性                                     │
│  4. 可以自由替换（相等的值对象可以互换）                      │
│  5. 比实体更安全（不可变 = 无副作用）                        │
│                                                              │
│  示例：                                                      │
│  Address（地址） — 省+市+区+详情 = 地址的唯一描述             │
│  Money（金额） — 100元人民币 = 100元人民币（完全相同）       │
│  DateRange（日期范围） — 开始+结束 = 时间段的描述             │
│  EmailAddress — 邮箱格式验证+值 = 邮箱的描述                  │
│                                                              │
│  代码实现：                                                  │
│  public final class Money {  // final = 不可继承             │
│      private final BigDecimal amount;    // final = 不可变   │
│      private final Currency currency;    // final = 不可变   │
│                                                              │
│      // 构造器创建，无setter                                 │
│      public Money(BigDecimal amount, Currency currency) {    │
│          this.amount = amount;                               │
│          this.currency = currency;                           │
│      }                                                       │
│                                                              │
│      // 需要修改时返回新对象                                  │
│      public Money add(Money other) {                         │
│          if (!currency.equals(other.currency))                │
│              throw new CurrencyMismatchException();           │
│          return new Money(amount.add(other.amount), currency);│
│      }                                                       │
│                                                              │
│      // 基于所有属性比较相等性                                │
│      @Override                                               │
│      public boolean equals(Object o) {                       │
│          if (this == o) return true;                         │
│          if (!(o instanceof Money)) return false;            │
│          Money other = (Money) o;                            │
│          return amount.equals(other.amount)                  │
│              && currency.equals(other.currency);              │
│      }                                                       │
│  }                                                           │
│                                                              │
│  Address 值对象：                                            │
│  public final class Address {                                │
│      private final String province;                          │
│      private final String city;                              │
│      private final String district;                          │
│      private final String detail;                            │
│                                                              │
│      // 构造时验证                                           │
│      public Address(String province, String city,             │
│                     String district, String detail) {         │
│          if (province == null || city == null)                │
│              throw new IllegalArgumentException();            │
│          this.province = province;                           │
│          this.city = city;                                   │
│          this.district = district;                           │
│          this.detail = detail;                               │
│      }                                                       │
│                                                              │
│      // 需要修改时返回新对象                                  │
│      public Address changeDetail(String newDetail) {         │
│          return new Address(province, city, district,         │
│                              newDetail);                     │
│      }                                                       │
│  }                                                           │
│                                                              │
│  ⚠️ 值对象不可变的原因：                                    │
│  1. 安全共享 — 多处引用同一值对象不会出问题                  │
│  2. 无副作用 — 不会意外修改别人持有的值                      │
│  3. 自验证 — 构造器验证所有属性，保证值对象总是合法的        │
│  4. 简化测试 — 不可变对象测试更简单                          │
└──────────────────────────────────────────────────────────────┘
```

### 5.3 实体 vs 值对象选择

```
┌──────────────────────────────────────────────────────────────┐
│          实体 vs 值对象 选择决策                               │
│                                                              │
│  问：这个概念需要追踪它的生命周期吗？                         │
│                                                              │
│  需要追踪 → 实体（有ID）                                     │
│    例：订单（从创建到支付到发货，需要追踪每一步）             │
│    例：客户（注册→活跃→冻结→注销，需要追踪状态变化）         │
│                                                              │
│  不需要追踪 → 值对象（无ID）                                 │
│    例：地址（"北京市朝阳区XX路"就是描述，不需要ID追踪）       │
│    例：金额（100元就是100元，不需要区分哪个100元）           │
│    例：颜色（红色就是红色，不需要追踪红色的一生）             │
│                                                              │
│  优先选择值对象：                                             │
│  值对象比实体更简单、更安全                                   │
│  只在确实需要追踪生命周期时才用实体                           │
│                                                              │
│  常见选择示例：                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ 概念          │ 类型    │ 原因                         │   │
│  │──────────────────────────────────────────────────────│   │
│  │ 订单          │ 实体    │ 需追踪生命周期               │   │
│  │ 订单行项目    │ 实体    │ 需独立追踪（同一订单多行）   │   │
│  │ 订单金额      │ 值对象  │ 只是金额描述                 │   │
│  │ 收货地址      │ 值对象  │ 只是地址描述                 │   │
│  │ 订单状态      │ 值对象  │ 枚举，不可变                 │   │
│  │ 客户          │ 实体    │ 需追踪生命周期               │   │
│  │ 客户姓名      │ 值对象  │ 只是姓名描述                 │   │
│  │ 商品          │ 实体    │ 需追踪生命周期               │   │
│  │ 商品价格      │ 值对象  │ 只是价格描述                 │   │
│  │ 评价          │ 实体    │ 需追踪生命周期               │   │
│  │ 评分          │ 值对象  │ 1~5星，不可变                │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ⚠️ 值对象在数据库中的存储：                                 │
│  1. 内嵌存储：和实体在同一表（Address字段直接存在Order表）    │
│  2. 值对象序列化：整个值对象存为一个JSON字段                  │
│  3. 拆列存储：Address拆为province/city/district/detail列     │
│  → 不需要单独建表（值对象没有ID，不需要独立表）              │
└──────────────────────────────────────────────────────────────┘
```

---

## 第六章 战术设计 — 聚合与聚合根

### 6.1 聚合（Aggregate）

```
┌──────────────────────────────────────────────────────────────┐
│              聚合（Aggregate）                                 │
│                                                              │
│  定义：一组相关对象的集合，作为数据修改的单元                  │
│  每个聚合有一个根（Aggregate Root）和一个边界                 │
│                                                              │
│  聚合的三大规则：                                             │
│  1. 聚合内的对象必须一起修改（事务一致性）                    │
│  2. 外部只能通过聚合根访问聚合内对象                          │
│  3. 聚合之间不能直接引用内部对象，只能引用聚合根ID            │
│                                                              │
│  图解：                                                      │
│                                                              │
│  ┌─ Order 聚合 ────────────────────────────┐                │
│  │                                          │                │
│  │  Order (聚合根) ←── 外部唯一入口          │                │
│  │    │                                     │                │
│  │    ├── OrderItem (内部实体)               │                │
│  │    │     ├── productId                   │                │
│  │    │     ├── quantity                    │                │
│  │    │     └── unitPrice                   │                │
│  │    │                                     │                │
│  │    ├── Money (值对象: totalAmount)        │                │
│  │    ├── Address (值对象: shippingAddress)  │                │
│  │    ├── OrderStatus (值对象: status)       │                │
│  │                                          │                │
│  │  聚合边界：Order + OrderItems + 值对象    │                │
│  │  必须一起修改：修改OrderItems → 通过Order │                │
│  └──────────────────────────────────────────┘                │
│                                                              │
│  外部引用规则：                                               │
│  ┌──────────────────────────────────────────────────┐        │
│  │ ❌ 错误：Payment直接引用Order内部的OrderItem      │        │
│  │ ✅ 正确：Payment只持有Order的ID（orderId）         │        │
│  │                                                  │        │
│  │  因为OrderItem的生命周期属于Order聚合             │        │
│  │  外部不应直接操作聚合内部的实体                    │        │
│  └──────────────────────────────────────────────────┘        │
│                                                              │
│  聚合边界 = 一致性边界                                       │
│  职合内的修改必须一次性完成（一个事务）                       │
│  聚合间的修改通过领域事件异步保证最终一致                     │
└──────────────────────────────────────────────────────────────┘
```

### 6.2 聚合根（Aggregate Root）

```
聚合根 = 聚合的入口对象，也是聚合的管理者

聚合根的职责：
  1. 保护聚合内所有对象的一致性（业务规则校验）
  2. 控制聚合内对象的创建和修改
  3. 是外部访问聚合的唯一入口
  4. 发布领域事件

代码实现：

  public class Order extends AggregateRoot {  // 聚合根
      private OrderId id;
      private CustomerId customerId;
      private List<OrderItem> items;       // 聚合内实体
      private Money totalAmount;           // 值对象
      private Address shippingAddress;     // 值对象
      private OrderStatus status;          // 值对象（枚举）

      // ⚠️ 构造器 = 工厂方法，保证创建时就是合法的
      public static Order place(CustomerId customerId,
                                List<OrderItemRequest> itemRequests,
                                Address shippingAddress) {
          // 业务规则校验
          if (itemRequests == null || itemRequests.isEmpty())
              throw new OrderItemRequiredException("订单必须有商品");
          if (shippingAddress == null)
              throw new AddressRequiredException("订单必须有收货地址");

          Order order = new Order();
          order.id = OrderId.generate();
          order.customerId = customerId;
          order.status = OrderStatus.CREATED;

          // 聚合根控制内部对象的创建
          List<OrderItem> items = itemRequests.stream()
              .map(req -> new OrderItem(order.id,
                  req.getProductId(), req.getQuantity(),
                  req.getUnitPrice()))
              .collect(Collectors.toList());
          order.items = items;

          // 聚合根负责计算和一致性
          order.totalAmount = order.calculateTotal();
          order.shippingAddress = shippingAddress;

          // 发布领域事件
          order.registerEvent(new OrderPlacedEvent(order.id, order.customerId));

          return order;
      }

      // 聚合根保护业务规则
      public void pay() {
          if (status != OrderStatus.CREATED)
              throw new OrderStateException("只能支付已创建的订单");
          status = OrderStatus.PAID;
          registerEvent(new OrderPaidEvent(id));
      }

      public void cancel() {
          if (status == OrderStatus.PAID || status == OrderStatus.DELIVERING)
              throw new OrderStateException("已支付/已发货订单不能取消");
          status = OrderStatus.CANCELLED;
          registerEvent(new OrderCancelledEvent(id));
      }

      // 内部方法：聚合根管理内部一致性
      private Money calculateTotal() {
          BigDecimal sum = BigDecimal.ZERO;
          for (OrderItem item : items) {
              sum = sum.add(item.getSubtotal().getAmount());
          }
          return new Money(sum, Currency.getInstance("CNY"));
      }

      // ⚠️ 不暴露内部对象的修改方法
      // 没有 addItem/removeItem — 聚合根控制一切
  }
```

### 6.3 聚合设计原则

```
┌──────────────────────────────────────────────────────────────┐
│              聚合设计四大原则                                  │
│                                                              │
│  原则一：聚合尽量小                                           │
│  ─────────────────────                                       │
│  小聚合 = 更少的锁冲突 + 更少的事务范围 + 更好扩展            │
│                                                              │
│  ❌ 大聚合：Order包含OrderItem+Address+Payment+Logistics     │
│     → 修改任何一个字段都要锁整个Order → 性能差                │
│                                                              │
│  ✅ 小聚合：Order只包含OrderItem+核心值对象                   │
│     Payment是独立聚合 → 可以独立修改 → 性能好                 │
│                                                              │
│  原则二：通过ID引用其他聚合                                   │
│  ──────────────────────                                      │
│  聚合间不持有其他聚合的对象引用，只持有聚合根ID               │
│                                                              │
│  ❌ Order持有Payment对象 → 两个聚合强耦合                    │
│  ✅ Order持有paymentId → 需要时通过Repository加载            │
│                                                              │
│  原则三：聚合内强一致，聚合间最终一致                         │
│  ──────────────────────                                      │
│  聚合内的修改 = 一个事务（强一致性）                          │
│  聚合间的修改 = 领域事件（最终一致性）                        │
│                                                              │
│  例：下单成功 → 发布OrderPlacedEvent                         │
│       → 库存上下文监听 → 扣减库存（异步，最终一致）          │
│       → 促销上下文监听 → 核销优惠券（异步，最终一致）        │
│                                                              │
│  原则四：每次事务只修改一个聚合                               │
│  ──────────────────────                                      │
│  一个事务只应该修改一个聚合根                                 │
│  如果需要跨聚合修改 → 用领域事件异步                          │
│                                                              │
│  ❌ 一个事务修改Order + Inventory + Promotion                │
│     → 长事务 + 锁冲突 + 级联失败                             │
│                                                              │
│  ✅ 一个事务修改Order，然后发布事件                           │
│     → Inventory和Promotion各自监听并修改                     │
│     → 短事务 + 最终一致 + 可扩展                             │
└──────────────────────────────────────────────────────────────┘
```

### 6.4 聚合 vs 传统模型的区别

```
┌──────────────────────────────────────────────────────────────┐
│          传统模型 vs 聚合模型                                  │
│                                                              │
│  传统模型（数据驱动）：                                       │
│  ┌─ Order 表 ───────────────────────────────────────────┐   │
│  │ id | user_id | status | total | shipping_address     │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌─ Order_Item 表 ─────────────────────────────────────┐   │
│  │ id | order_id | product_id | quantity | price        │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌─ Payment 表 ────────────────────────────────────────┐   │
│  │ id | order_id | channel | amount | status            │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  → Order、OrderItem、Payment 只是数据库表映射               │
│  → Service 层操作三个Repository → 逻辑散落                  │
│                                                              │
│  聚合模型（领域驱动）：                                       │
│  Order聚合: Order(根) + OrderItem(内部) + Money/Address    │
│  Payment聚合: Payment(根) + PaymentChannel + Money          │
│                                                              │
│  → Order聚合自己管理OrderItem的生命周期                      │
│  → Payment聚合独立于Order聚合                                │
│  → 修改OrderItem只能通过Order聚合根                          │
│  → Order和Payment之间通过orderId引用                         │
│                                                              │
│  关键转变：                                                  │
│  从"表之间的关系"到"聚合之间的边界"                           │
│  从"Service操作多个表"到"聚合根保护内部一致性"               │
│  从"数据库是核心"到"领域模型是核心"                          │
└──────────────────────────────────────────────────────────────┘
```

---

## 第七章 战术设计 — 领域服务

### 7.1 什么是领域服务

```
┌──────────────────────────────────────────────────────────────┐
│              领域服务（Domain Service）                        │
│                                                              │
│  定义：不属于任何实体/值对象的业务逻辑                        │
│  当一个操作：                                                │
│  1. 不自然属于任何实体或值对象                               │
│  2. 涉及多个聚合的协调                                      │
│  3. 是纯业务计算（无状态）                                   │
│  → 放到领域服务                                              │
│                                                              │
│  领域服务 vs 应用服务的区别：                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ 维度       │ 领域服务          │ 应用服务              │   │
│  │──────────────────────────────────────────────────────│   │
│  │ 位置       │ 领域层            │ 应用层                │   │
│  │ 逻辑类型   │ 纯业务逻辑        │ 编排/协调/基础设施    │   │
│  │ 状态       │ 无状态            │ 无状态                │   │
│  │ 依赖       │ 只依赖领域对象    │ 依赖领域+基础设施     │   │
│  │ 跨聚合     │ 同一限界上下文内  │ 可跨限界上下文        │   │
│  │ 事务       │ 不管理事务        │ 管理事务              │   │
│  │ 发布事件   │ 通常不发布        │ 可发布事件            │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  什么逻辑属于领域服务：                                      │
│  1. 跨聚合的业务规则（但仍在同一上下文内）                   │
│  2. 纯计算/转换（不修改任何聚合状态）                         │
│  3. 需要外部信息的业务决策（但不含技术实现）                  │
│                                                              │
│  什么逻辑不属于领域服务：                                    │
│  1. 自然属于某个实体的行为 → 放到实体                        │
│  2. 纯技术操作（发MQ/调HTTP）→ 放到应用服务                  │
│  3. 跨限界上下文的协调 → 放到应用服务                        │
│  4. 事务管理 → 放到应用服务                                  │
└──────────────────────────────────────────────────────────────┘
```

### 7.2 领域服务实现

```java
// 领域服务：转账业务规则（不自然属于Account实体）

public class TransferService {  // 领域服务

    // 纯业务逻辑，不涉及技术实现
    public void transfer(Account source, Account target, Money amount) {
        // 业务规则校验
        if (source.getBalance().lessThan(amount))
            throw new InsufficientBalanceException("余额不足");
        if (source.isFrozen())
            throw new AccountFrozenException("账户已冻结");
        if (!source.getCurrency().equals(amount.getCurrency()))
            throw new CurrencyMismatchException("币种不匹配");

        // 业务操作（聚合根自己管理状态）
        source.debit(amount);   // Account实体自己扣款
        target.credit(amount);  // Account实体自己入账
    }
}

// ⚠️ 注意：领域服务只做业务规则和协调
// 不做事务管理、不发MQ、不调HTTP → 这些是应用服务的职责

// 对比：如果转账规则很简单，可以放在Account实体内
// 只有当操作跨多个聚合且逻辑复杂时才提取领域服务

// ❌ 常见错误：把所有逻辑都塞到领域服务 → 又回到了贫血模型
// ✅ 正确做法：优先放实体/值对象，实在不属于才提取领域服务
```

### 7.3 三层服务职责划分

```
┌──────────────────────────────────────────────────────────────┐
│          Application Service / Domain Service / 聿合根        │
│                                                              │
│  三层职责清晰划分：                                           │
│                                                              │
│  ┌─ Application Service（应用服务）─────────────────────┐    │
│  │ 编排和协调，不包含业务逻辑                          │    │
│  │                                                    │    │
│  │ 职责：                                              │    │
│  │ 1. 接收外部请求（DTO → 领域对象翻译）              │    │
│  │ 2. 加载聚合根（通过Repository）                     │    │
│  │ 3. 调用聚合根的业务方法                             │    │
│  │ 4. 调用领域服务（如果需要）                         │    │
│  │ 5. 保存聚合根（通过Repository）                     │    │
│  │ 6. 管理事务                                         │    │
│  │ 7. 发布领域事件                                     │    │
│  │ 8. 调用基础设施（发MQ/调HTTP/写日志）              │    │
│  └───────────────────────────────────────────────────┘    │
│                                                              │
│  ┌─ Domain Service（领域服务）─────────────────────────┐    │
│  │ 纯业务逻辑，不包含技术实现                          │    │
│  │                                                    │    │
│  │ 职责：                                              │    │
│  │ 1. 跨聚合的业务规则                                 │    │
│  │ 2. 不属于任何实体的业务计算                         │    │
│  │ 3. 纯业务决策                                       │    │
│  └───────────────────────────────────────────────────┘    │
│                                                              │
│  ┌─ Aggregate Root（聚合根）───────────────────────────┐    │
│  │ 聚合内业务逻辑                                      │    │
│  │                                                    │    │
│  │ 职责：                                              │    │
│  │ 1. 保护聚合内一致性                                 │    │
│  │ 2. 聚合内的业务规则和状态变更                       │    │
│  │ 3. 发布领域事件                                     │    │
│  └───────────────────────────────────────────────────┘    │
│                                                              │
│  完整调用链示例：                                             │
│                                                              │
│  Controller                                                  │
│    → OrderApplicationService.placeOrder()                    │
│      // 1. DTO翻译为领域对象                                 │
│      // 2. Customer aclAdapter.getCustomer(userId)           │
│      // 3. Order.place(customer, items) ← 聚合根业务方法    │
│      // 4. orderRepository.save(order) ← 事务+持久化        │
│      // 5. eventPublisher.publish(order.getEvents()) ← 事件  │
│                                                              │
│  业务逻辑全在 Order.place()（聚合根）                        │
│  应用服务只做编排，不含任何if-else业务逻辑                   │
└──────────────────────────────────────────────────────────────┘
```

---

## 第八章 战术设计 — 领域事件

### 8.1 什么是领域事件

```
┌──────────────────────────────────────────────────────────────┐
│              领域事件（Domain Event）                          │
│                                                              │
│  定义：领域中发生的有意义的业务事件                           │
│  用过去时态命名："OrderPlaced"（订单已被放置）               │
│                                                              │
│  领域事件解决的核心问题：                                    │
│  聚合间不强一致 → 如何保证最终一致？                         │
│  → 领域事件！                                                │
│                                                              │
│  事件的产生和消费：                                          │
│  ┌──────────────────────────────────────────────────┐        │
│  │ Order聚合                          Payment聚合   │        │
│  │                                    (事件消费者)   │        │
│  │  Order.place()                    ← 监听事件     │        │
│  │    → 产生 OrderPlacedEvent       ←  处理支付     │        │
│  │    → 产生 OrderPaidEvent         ←  更新支付状态 │        │
│  │                                                   │        │
│  │  Inventory聚合                    Promotion聚合   │        │
│  │  (事件消费者)                      (事件消费者)   │        │
│  │  ← 监听 OrderPlacedEvent         ← 监听事件     │        │
│  │  → 扣减库存                       → 核销优惠券   │        │
│  └──────────────────────────────────────────────────┘        │
│                                                              │
│  事件命名规则：                                              │
│  ✅ 过去时态：OrderPlaced / OrderPaid / OrderCancelled       │
│  ❌ 现在时态：OrderPlace / OrderPay / OrderCancel            │
│  ❌ 命令式：CreateOrder / PayOrder / CancelOrder             │
│                                                              │
│  事件 = 事实（已经发生的事），不是命令（要求做的事）          │
│  事件是不可变的 — 一旦发生就不能撤销                         │
└──────────────────────────────────────────────────────────────┘
```

### 8.2 领域事件实现

```java
// 领域事件基类
public abstract class DomainEvent {
    private final DateTime occurredOn;   // 事件发生时间
    private final String eventId;         // 事件唯一ID

    protected DomainEvent() {
        this.occurredOn = DateTime.now();
        this.eventId = UUID.randomUUID().toString();
    }
}

// 具体领域事件
public class OrderPlacedEvent extends DomainEvent {
    private final OrderId orderId;
    private final CustomerId customerId;
    private final List<OrderItemInfo> items;
    private final Money totalAmount;

    public OrderPlacedEvent(OrderId orderId, CustomerId customerId,
                            List<OrderItemInfo> items, Money totalAmount) {
        super();
        this.orderId = orderId;
        this.customerId = customerId;
        this.items = items;
        this.totalAmount = totalAmount;
    }
}

// 聚合根中产生事件
public class Order extends AggregateRoot {
    private List<DomainEvent> events = new ArrayList<>();

    public static Order place(CustomerId customerId,
                              List<OrderItemRequest> items,
                              Address address) {
        Order order = new Order();
        // ... 业务逻辑 ...
        order.registerEvent(new OrderPlacedEvent(order.id,
            customerId, order.itemInfos(), order.totalAmount));
        return order;
    }

    public void pay() {
        // ... 业务逻辑 ...
        this.status = OrderStatus.PAID;
        registerEvent(new OrderPaidEvent(this.id));
    }

    // 事件注册方法
    protected void registerEvent(DomainEvent event) {
        events.add(event);
    }

    // 获取并清除事件（发布后清空）
    public List<DomainEvent> getEvents() {
        return Collections.unmodifiableList(events);
    }

    public void clearEvents() {
        events.clear();
    }
}

// 应用服务发布事件
public class OrderApplicationService {
    private OrderRepository orderRepository;
    private DomainEventPublisher eventPublisher;

    @Transactional
    public void placeOrder(PlaceOrderCommand cmd) {
        Order order = Order.place(cmd.getCustomerId(),
                                  cmd.getItems(), cmd.getAddress());
        orderRepository.save(order);
        // 发布聚合根产生的事件
        eventPublisher.publishAll(order.getEvents());
        order.clearEvents();
    }
}
```

### 8.3 事件发布机制

```
┌──────────────────────────────────────────────────────────────┐
│              三种事件发布机制                                  │
│                                                              │
│  方案一：进程内发布（Spring Event）                           │
│  ────────────────────────────────                            │
│  简单但不可靠（事务回滚事件丢失）                             │
│                                                              │
│  @TransactionalEventListener(phase = AFTER_COMMIT)           │
│  // 只在事务提交后才发布 → 解决事务回滚问题                  │
│                                                              │
│  方案二：MQ发布（推荐）                                      │
│  ────────────────────────                                    │
│  事务提交后发MQ → 消费者异步处理 → 最终一致                  │
│                                                              │
│  ⚠️ 问题：事务成功但MQ发送失败 → 事件丢失                    │
│  解决：事件表模式（Event Sourcing Table）                    │
│                                                              │
│  方案三：事件表 + MQ（最可靠）                                │
│  ─────────────────────────────                               │
│  1. 业务操作和事件记录在同一个事务写入DB                      │
│  2. 定时任务扫描未发布的事件                                  │
│  3. 发布到MQ后标记为已发布                                    │
│  4. 消费者确认后标记为已消费                                  │
│                                                              │
│  ┌─ 事件表模式 ──────────────────────────────────┐         │
│  │ CREATE TABLE domain_event (                     │         │
│  │   id BIGINT PRIMARY KEY,                        │         │
│  │   event_type VARCHAR(100),                      │         │
│  │   aggregate_type VARCHAR(100),                  │         │
│  │   aggregate_id VARCHAR(100),                    │         │
│  │   event_data JSON,                              │         │
│  │   status ENUM('PENDING','PUBLISHED','CONSUMED'),│         │
│  │   created_at TIMESTAMP,                         │         │
│  │   published_at TIMESTAMP NULL                   │         │
│  │ );                                              │         │
│  └────────────────────────────────────────────────┘         │
│                                                              │
│  优点：                                                      │
│  - 事件绝不丢失（和业务数据同事务写入DB）                     │
│  - 可重试（扫描PENDING状态的事件重新发布）                    │
│  - 可审计（所有事件都有记录）                                 │
│                                                              │
│  ⚠️ 事件表扫描要注意：                                      │
│  - 扫描频率要够快（1~5秒一次）                               │
│  - 发布失败要重试但有上限                                    │
│  - 已发布事件定期清理                                        │
└──────────────────────────────────────────────────────────────┘
```

---

## 第九章 战术设计 — 工厂与仓储

### 9.1 工厂（Factory）

```
┌──────────────────────────────────────────────────────────────┐
│              工厂（Factory）                                   │
│                                                              │
│  定义：负责创建复杂聚合根的对象                               │
│  聚合根的创建可能涉及大量规则 → 提取为工厂                    │
│                                                              │
│  什么时候需要工厂：                                          │
│  1. 创建聚合根涉及复杂业务规则                               │
│  2. 创建需要组装多个内部对象                                 │
│  3. 创建需要外部信息（如从其他聚合获取数据）                  │
│                                                              │
│  什么时候不需要工厂：                                        │
│  1. 简单创建（new Order()，无复杂规则）                      │
│  2. 重建（从Repository加载已有聚合根）                       │
│                                                              │
│  三种工厂形式：                                              │
│                                                              │
│  1. 聚合根静态工厂方法（最推荐）                             │
│     Order order = Order.place(customerId, items, address);    │
│     // 创建逻辑封装在聚合根内部                              │
│     // 保证创建出来的Order一定是合法的                        │
│                                                              │
│  2. 独立工厂类                                               │
│     OrderFactory orderFactory;                                │
│     Order order = orderFactory.create(cmd);                  │
│     // 创建逻辑太复杂时提取为独立工厂类                      │
│                                                              │
│  3. 构造器                                                   │
│     Order order = new Order(customerId, items, address);      │
│     // 只在创建简单时使用                                    │
│     // ⚠️ 构造器不能表达业务语义（"place"比"new"更有意义）   │
│                                                              │
│  ⚠️ 工厂只负责创建，不负责持久化                             │
│     创建 → ApplicationService.save → Repository              │
│     不要在工厂里调Repository！                               │
└──────────────────────────────────────────────────────────────┘
```

### 9.2 仓储（Repository）

```
┌──────────────────────────────────────────────────────────────┐
│              仓储（Repository）                                │
│                                                              │
│  定义：聚合根的持久化和重建接口                               │
│  模拟"聚合根集合"——像操作内存中的List一样操作数据库           │
│                                                              │
│  Repository 只做两件事：                                     │
│  1. save(aggregate) → 持久化聚合根                           │
│  2. findById(id) → 从存储重建聚合根                          │
│                                                              │
│  ⚠️ Repository 是领域层的接口，实现在基础设施层               │
│  领域层定义接口 → 基础设施层实现 → 依赖倒置                  │
│                                                              │
│  接口定义（领域层）：                                        │
│  public interface OrderRepository {                          │
│      Order findById(OrderId id);                             │
│      void save(Order order);                                 │
│      // ⚠️ 不暴露查询方法！只有按ID查找                     │
│      // 查询需求用专门的 QueryService 或 CQRS               │
│  }                                                           │
│                                                              │
│  实现类（基础设施层）：                                      │
│  public class JpaOrderRepository implements OrderRepository { │
│      private SpringDataOrderJpaRepository jpaRepo;           │
│                                                              │
│      @Override                                               │
│      public Order findById(OrderId id) {                     │
│          OrderPO po = jpaRepo.findById(id.getValue())        │
│              .orElseThrow(() ->                              │
│                  new OrderNotFoundException(id));             │
│          // PO → 领域对象翻译                                │
│          return OrderConverter.toDomain(po);                 │
│      }                                                       │
│                                                              │
│      @Override                                               │
│      public void save(Order order) {                         │
│          // 领域对象 → PO 翻译                               │
│          OrderPO po = OrderConverter.toPO(order);            │
│          jpaRepo.save(po);                                   │
│      }                                                       │
│  }                                                           │
│                                                              │
│  ⚠️ 关键原则：                                               │
│  1. Repository 只存取聚合根，不存取内部实体                  │
│     OrderItem 不需要单独的 Repository → 通过 Order 获取      │
│  2. 不要在 Repository 里写查询逻辑                           │
│     复杂查询 → 专门的 QueryService（读模型）                 │
│  3. 领域对象和持久化对象（PO）要分离                          │
│     Order（领域对象）≠ OrderPO（数据库映射对象）             │
│     → 之间需要翻译层（Converter）                            │
│  4. 不要让领域对象依赖持久化框架                              │
│     Order 不应该有 JPA @Entity 注解！                        │
│     → 领域对象应该纯粹，PO才标注注解                        │
└──────────────────────────────────────────────────────────────┘
```

### 9.3 领域对象与持久化对象的分离

```
┌──────────────────────────────────────────────────────────────┐
│          领域对象 vs 持久化对象 vs DTO                         │
│                                                              │
│  三种对象的职责：                                             │
│                                                              │
│  ┌─ 领域对象（Domain Object）────────────────────────┐      │
│  │ 纯业务表达，不依赖任何框架                         │      │
│  │ 无JPA注解、无MyBatis注解、无JSON注解               │      │
│  │ 例：Order, OrderItem, Money, Address               │      │
│  └───────────────────────────────────────────────────┘      │
│                                                              │
│  ┌─ 持久化对象（Persistence Object, PO）──────────────┐     │
│  │ 数据库表映射，有框架注解                           │     │
│  │ @Entity, @Table, @Column 等                       │     │
│  │ 例：OrderPO, OrderItemPO                           │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  ┌─ 数据传输对象（Data Transfer Object, DTO）─────────┐     │
│  │ API层传输，有序列化注解                            │     │
│  │ @JsonProperty, @Valid 等                           │     │
│  │ 例：PlaceOrderRequest, OrderResponseDTO             │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
│  三者转换流程：                                              │
│                                                              │
│  入站：DTO → 领域对象 → PO → DB                             │
│  PlaceOrderRequest → Order.place() → OrderPO → INSERT       │
│                                                              │
│  出站：DB → PO → 领域对象 → DTO                             │
│  SELECT → OrderPO → OrderConverter.toDomain() → ResponseDTO │
│                                                              │
│  ⚠️ 为什么需要分离？                                         │
│  1. 领域对象不依赖框架 → 可以在不同框架间切换               │
│  2. 领域对象不被数据库结构限制 → 可以自由设计               │
│  3. PO可以有多个持久化映射 → 同一领域对象可存不同表结构      │
│  4. DTO可以有不同版本 → API演进不影响领域模型               │
│                                                              │
│  ❌ 常见错误：领域对象直接加JPA注解                           │
│  @Entity                                                     │
│  public class Order { ... }                                  │
│  → 领域对象被框架绑架 → 无法独立演进                        │
│                                                              │
│  ✅ 正确做法：领域对象和PO分开，Converter翻译                 │
│  Order（纯业务）← OrderConverter → OrderPO（纯数据映射）     │
└──────────────────────────────────────────────────────────────┘
```

---

## 第十章 代码架构落地

### 10.1 分层架构

```
┌──────────────────────────────────────────────────────────────┐
│              DDD 四层架构                                     │
│                                                              │
│  ┌─ 用户界面/展示层（Interface Layer）──────────────┐        │
│  │ Controller / DTO /Assembler                     │        │
│  │ 职责：接收请求、返回响应、DTO转换                │        │
│  │ 不含业务逻辑                                     │        │
│  └─────────────────────────────────────────────────┘        │
│                    ↓                                         │
│  ┌─ 应用层（Application Layer）─────────────────────┐        │
│  │ ApplicationService / Command / EventHandler      │        │
│  │ 职责：编排、协调、事务管理、事件发布              │        │
│  │ 不含业务逻辑（只调用领域对象）                    │        │
│  └─────────────────────────────────────────────────┘        │
│                    ↓                                         │
│  ┌─ 领域层（Domain Layer）⭐核心 ────────────────────┐        │
│  │ Entity / ValueObject / AggregateRoot             │        │
│  │ DomainService / DomainEvent / Repository(接口)   │        │
│  │ 职责：纯业务逻辑、业务规则                        │        │
│  │ ⚠️ 不依赖任何技术框架                             │        │
│  └─────────────────────────────────────────────────┘        │
│                    ↓                                         │
│  ┌─ 基础设施层（Infrastructure Layer）───────────────┐        │
│  │ RepositoryImpl / MQPublisher / HttpClient        │        │
│  │ 职责：技术实现、持久化、消息、外部调用            │        │
│  │ ⚠️ 实现领域层定义的接口（依赖倒置）               │        │
│  └─────────────────────────────────────────────────┘        │
│                                                              │
│  依赖方向：                                                  │
│  Interface → Application → Domain ← Infrastructure           │
│                                                              │
│  ⚠️ 关键：领域层不依赖基础设施层！                           │
│  Domain层定义Repository接口                                  │
│  Infrastructure层实现Repository接口                          │
│  → 依赖倒置原则（DIP）                                      │
│                                                              │
│  目录结构（Maven模块化）：                                    │
│  order-context/                                              │
│  ├── order-api/           ← Interface层                     │
│  │   ├── controller/                                       │
│  │   ├── dto/                                              │
│  │   └ assembler/                                          │
│  ├── order-application/   ← Application层                   │
│  │   ├── service/                                          │
│  │   ├── command/                                          │
│  │   ├── eventhandler/                                     │
│  ├── order-domain/        ← Domain层 ⭐                     │
│  │   ├── model/                                            │
│  │   │   ├── aggregate/  (Order, OrderItem)                │
│  │   │   ├── entity/                                       │
│  │   │   ├── valueobject/ (Money, Address, OrderStatus)    │
│  │   ├── service/        (TransferDomainService)            │
│  │   ├── event/          (OrderPlacedEvent)                 │
│  │   ├── repository/     (OrderRepository 接口)            │
│  ├── order-infrastructure/ ← Infrastructure层               │
│  │   ├── repository/     (JpaOrderRepository 实现)          │
│  │   ├── messaging/      (RocketMQEventPublisher)          │
│  │   ├── gateway/        (UserACLClient)                   │
│  │   ├── persistence/    (OrderPO, OrderItemPO)            │
└──────────────────────────────────────────────────────────────┘
```

### 10.2 六边形架构（Ports & Adapters）

```
┌──────────────────────────────────────────────────────────────┐
│              六边形架构（Hexagonal Architecture）              │
│                                                              │
│  Alistair Cockburn 提出，又称 Ports and Adapters             │
│                                                              │
│  核心思想：                                                  │
│  领域模型在中心，不依赖任何外部技术                          │
│  通过"端口"（接口）与外部交互                                │
│  通过"适配器"（实现）连接具体技术                            │
│                                                              │
│           ┌─ REST Adapter ──┐                                │
│           │  (左适配器)      │                                │
│           │  Controller      │                                │
│           └──→ Port ──┐     │                                │
│                          │   │                                │
│    ┌─ MQ Adapter ───→ Port ─┤   │                            │
│    │  (左适配器)       │    │ D │                            │
│    │                   │    │ O │                            │
│    └──→ Port ─────────┤    │ M │                            │
│                         │   │ A │                            │
│    ┌─ DB Adapter ──→ Port ─ │ I │                            │
│    │  (右适配器)      │    │ N │                            │
│    │  RepositoryImpl   │    │   │                            │
│    └──→ Port ─────┤   │    │   │                            │
│                    │   │    │   │                            │
│    ┌─ Email Adapter → Port  │                            │
│    │  (右适配器)      │    │                            │
│    └──→ Port ─────┤   │    │                            │
│                    │   │                                │
│                              │                            │
│           ┌─ Test Adapter ──┘                                │
│           │  (测试可以用内存 │                                │
│           │   适配器替换)    │                                │
│           └──────────────┘                                │
│                                                              │
│  左侧适配器（Driving Adapters）：驱动应用                    │
│  REST Controller、MQ消费者、定时任务、CLI                    │
│                                                              │
│  右侧适配器（Driven Adapters）：被应用驱动                   │
│  RepositoryImpl、MQ生产者、邮件发送、外部HTTP                │
│                                                              │
│  端口 = 领域层定义的接口                                     │
│  适配器 = 基础设施层对接口的实现                             │
│                                                              │
│  优势：                                                      │
│  1. 领域模型纯粹 — 不依赖任何技术                            │
│  2. 技术可替换 — 适配器可以随时换（JPA→MyBatis→MongoDB）     │
│  3. 测试友好 — 左适配器可以用内存右适配器                    │
│  4. 清晰边界 — 左是入口，右是出口                            │
└──────────────────────────────────────────────────────────────┘
```

---

## 第十一章 CQRS 与事件溯源

### 11.1 CQRS（命令查询职责分离）

```
┌──────────────────────────────────────────────────────────────┐
│              CQRS（Command Query Responsibility Segregation） │
│                                                              │
│  核心思想：读和写使用不同的模型                               │
│                                                              │
│  传统模式：同一个模型既负责读又负责写                         │
│  ┌─ Order ──→ 写（创建/修改）                               │
│  └─ Order ──→ 读（查询/列表）                               │
│  → 写模型需要完整业务规则 → 查询需要扁平结构                 │
│  → 两者互相掣肘                                              │
│                                                              │
│  CQRS 模式：读和写分离                                       │
│                                                              │
│  ┌─ Command Side（命令端）──────────────────────────┐       │
│  │ 写操作                                             │       │
│  │ 聚合根 + Repository + 领域事件                     │       │
│  │ 关注业务规则和一致性                                │       │
│  │ 数据源：写数据库（优化写）                          │       │
│  └───────────────────────────────────────────────────┘       │
│                        │                                     │
│                        │ 领域事件                             │
│                        ↓                                     │
│  ┌─ Query Side（查询端）────────────────────────────┐       │
│  │ 读操作                                             │       │
│  │ 读模型 + QueryService + DTO                       │       │
│  │ 关注查询性能和用户体验                              │       │
│  │ 数据源：读数据库/ES/Redis（优化读）                │       │
│  └───────────────────────────────────────────────────┘       │
│                                                              │
│  架构图：                                                    │
│                                                              │
│  Command → CommandHandler → Aggregate → Event →             │
│     → EventHandler → ReadModelStore（同步到读库）            │
│                                                              │
│  Query → QueryService → ReadModelStore → Response            │
│                                                              │
│  读库选择：                                                  │
│  - MySQL 读库（主从分离）                                    │
│  - Elasticsearch（全文搜索）                                 │
│  - Redis（实时热点）                                         │
│  - ClickHouse（统计分析）                                    │
│                                                              │
│  CQRS 适用场景：                                             │
│  ✅ 读多写少（读写比例 > 10:1）                              │
│  ✅ 读模型复杂（需要多种查询维度）                           │
│  ✅ 写模型复杂（需要严格业务规则）                           │
│  ✅ 性能要求高（读写分别优化）                               │
│                                                              │
│  CQRS 不适用场景：                                           │
│  ❌ 简单CRUD（读写模型差不多，没必要分离）                   │
│  ❌ 强一致读（CQRS的读是最终一致的）                         │
│  ❌ 小团队（维护两个模型的成本太高）                         │
└──────────────────────────────────────────────────────────────┘
```

### 11.2 事件溯源（Event Sourcing）

```
┌──────────────────────────────────────────────────────────────┐
│              事件溯源（Event Sourcing）                        │
│                                                              │
│  核心思想：不存储聚合的当前状态，而是存储所有变更事件          │
│  重建聚合 = 重放所有历史事件                                 │
│                                                              │
│  传统模式：                                                  │
│  ┌────────────────────────────────────────────┐              │
│  │ Order表：id=1, status=PAID, amount=100    │              │
│  │ → 只存当前状态，历史轨迹丢失              │              │
│  │ → 不知道这个订单经历了什么变化            │              │
│  └────────────────────────────────────────────┘              │
│                                                              │
│  事件溯源模式：                                              │
│  ┌────────────────────────────────────────────┐              │
│  │ Event表：                                  │              │
│  │ 1. OrderPlacedEvent   → status=CREATED    │              │
│  │ 2. OrderPaidEvent     → status=PAID       │              │
│  │ 3. OrderAddressChangedEvent → address=新  │              │
│  │ → 所有变更都有记录                        │              │
│  │ → 重建 = 依次应用事件到空Order            │              │
│  └────────────────────────────────────────────┘              │
│                                                              │
│  聚合根重建过程：                                            │
│                                                              │
│  Order order = new Order();     // 空聚合根                  │
│  order.apply(OrderPlacedEvent); // → CREATED                 │
│  order.apply(OrderPaidEvent);   // → PAID                   │
│  order.apply(OrderAddressChangedEvent); // → address changed │
│  // 现在 order 的状态和传统模式存储的一样                     │
│                                                              │
│  事件溯源优势：                                              │
│  1. 完整审计追踪（所有变更都有记录）                         │
│  2. 时间旅行（可以回到任意时间点的状态）                     │
│  3. 自然的事件驱动（事件就是存储本身）                       │
│  4. 无ORM映射问题（不需要PO/领域对象转换）                   │
│                                                              │
│  事件溯源挑战：                                              │
│  1. 事件数量增长 → 重建慢 → 需要快照（Snapshot）            │
│  2. 事件结构变化 → 需要事件升级（Upcasting）                │
│  3. 查询困难 → 需要投影（Projection）到读模型               │
│  4. 调试复杂 → 不能直接看数据库看当前状态                   │
│                                                              │
│  ⚠️ 事件溯源 和 CQRS 天然搭配：                              │
│  事件溯源负责写（存储事件）                                  │
│  CQRS查询端负责读（投影到读模型）                            │
│                                                              │
│  何时使用事件溯源：                                          │
│  ✅ 需要完整审计（金融交易、医疗记录）                      │
│  ✅ 需要时间旅行（分析历史趋势）                             │
│  ✅ 事件是核心业务资产（工作流引擎）                         │
│                                                              │
│  ❌ 不适合简单CRUD应用                                       │
│  ❌ 不适合不需要历史追踪的业务                               │
│  ❌ 不适合团队没有事件思维的情况                              │
└──────────────────────────────────────────────────────────────┘
```

---

## 第十二章 DDD 与微服务

### 12.1 限界上下文 = 微服务边界

```
┌──────────────────────────────────────────────────────────────┐
│              限界上下文与微服务的关系                          │
│                                                              │
│  理论：一个限界上下文 = 一个微服务                           │
│                                                              │
│  但实际中需要灵活处理：                                      │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ 场景                     │ 建议                     │   │
│  │──────────────────────────────────────────────────────│   │
│  │ 初期团队小（5人以下）     │ 多个上下文 = 一个服务   │   │
│  │                          │ 模块化代码，先不分服务   │   │
│  │                          │                         │   │
│  │ 中期团队中等（10~20人）   │ 核心域 = 独立微服务     │   │
│  │                          │ 支撑域/通用域按需拆分   │   │
│  │                          │                         │   │
│  │ 后期团队大（20+人）      │ 每个上下文 = 微服务     │   │
│  │                          │ 完全独立部署            │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ⚠️ 不要一开始就拆成微服务！                                │
│  先用模块化（Maven多模块）验证限界上下文边界                 │
│  边界稳定后再拆为微服务                                     │
│                                                              │
│  演进路径：                                                  │
│  单体模块化 → 模块化单体 → 核心域拆微服务 → 全微服务        │
│                                                              │
│  模块化单体（Modular Monolith）：                            │
│  一个部署单元，但代码按限界上下文分模块                      │
│  模块间通过接口通信，不直接依赖                              │
│  → 可以随时将某个模块拆为独立微服务                         │
│                                                              │
│  order-system/                                              │
│  ├── product-module/     ← 商品上下文模块                   │
│  ├── order-module/       ← 订单上下文模块                   │
│  ├── payment-module/     ← 支付上下文模块                   │
│  ├── user-module/        ← 用户上下文模块                   │
│  └── starter/            ← Spring Boot启动器                │
│                                                              │
│  每个模块内部是完整的四层结构                                │
│  模块间只通过接口依赖（类似微服务的API调用）                 │
│  可以随时将 payment-module 拆为独立微服务                   │
└──────────────────────────────────────────────────────────────┘
```

### 12.2 微服务拆分策略

```
┌──────────────────────────────────────────────────────────────┐
│              微服务拆分 DDD 驱动策略                           │
│                                                              │
│  Step 1：识别限界上下文（战略设计）                           │
│  Step 2：模块化单体验证（先不分服务）                         │
│  Step 3：核心域优先拆分（核心域先独立部署）                   │
│  Step 4：逐步拆分支撑域（按业务变化频率拆分）                 │
│  Step 5：通用域最后处理（用开源/SaaS替代）                   │
│                                                              │
│  拆分验证标准：                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ 验证点             │ 通过标准                       │   │
│  │──────────────────────────────────────────────────────│   │
│  │ 独立部署           │ 可以独立发布不影响其他          │   │
│  │ 独立数据库         │ 不共享数据库表                  │   │
│  │ 独立团队           │ 一个团队可以独立维护            │   │
│  │ 独立演进           │ 可以自由修改不影响其他          │   │
│  │ API契约稳定        │ 对外接口版本化                  │   │
│  │ 故障隔离           │ 一个服务挂不影响其他            │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ⚠️ 拆分后的数据一致性：                                    │
│  单体 → 共享数据库 → 强一致                                 │
│  微服务 → 各自数据库 → 最终一致（领域事件）                 │
│                                                              │
│  拆分前要准备好：                                            │
│  1. 领域事件机制（跨服务最终一致）                           │
│  2. API契约定义（服务间通信）                                │
│  3. 防腐层（避免服务间模型腐蚀）                             │
│  4. 分布式事务方案（关键场景的强一致需求）                   │
│  5. 可观测性（跨服务链路追踪）                               │
└──────────────────────────────────────────────────────────────┘
```

---

## 第十三章 DDD 实战案例 — 电商订单

### 13.1 订单限界上下文设计

```
┌──────────────────────────────────────────────────────────────┐
│              订单限界上下文完整设计                            │
│                                                              │
│  统一语言：                                                   │
│  Order / OrderItem / place / pay / cancel / modify           │
│  OrderStatus / Money / Address / CustomerId                  │
│                                                              │
│  聚合设计：                                                   │
│  Order 聚合：                                                │
│  - Order（聚合根）                                           │
│  - OrderItem（内部实体）                                     │
│  - Money（值对象：金额）                                     │
│  - Address（值对象：地址）                                   │
│  - OrderStatus（值对象：状态枚举）                           │
│                                                              │
│  领域事件：                                                   │
│  - OrderPlacedEvent                                          │
│  - OrderPaidEvent                                            │
│  - OrderCancelledEvent                                       │
│  - OrderDeliveredEvent                                       │
│                                                              │
│  状态流转：                                                  │
│  CREATED → PAID → DELIVERING → DELIVERED → COMPLETED        │
│  CREATED → CANCELLED                                        │
│  PAID → REFUNDING → REFUNDED                                │
│                                                              │
│  上下文映射：                                                 │
│  ← 商品上下文（OHS+PL，通过ACL翻译Product为OrderItemProduct）│
│  ← 用户上下文（OHS+PL，通过ACL翻译User为Customer）          │
│  ← 促销上下文（OHS+PL，通过ACL翻译Discount为OrderDiscount） │
│  → 支付上下文（Partnership，密切协作）                       │
│  → 物流上下文（Customer-Supplier，提供订单信息）             │
└──────────────────────────────────────────────────────────────┘
```

### 13.2 完整代码结构

```java
// ====== Domain Layer ======

// 1. 值对象
public final class OrderStatus {
    public static final OrderStatus CREATED = new OrderStatus("CREATED");
    public static final OrderStatus PAID = new OrderStatus("PAID");
    public static final OrderStatus DELIVERING = new OrderStatus("DELIVERING");
    public static final OrderStatus DELIVERED = new OrderStatus("DELIVERED");
    public static final OrderStatus COMPLETED = new OrderStatus("COMPLETED");
    public static final OrderStatus CANCELLED = new OrderStatus("CANCELLED");
    // 不可变枚举，无setter
}

public final class Money {
    private final BigDecimal amount;
    private final Currency currency;
    public Money add(Money other) { ... }  // 返回新对象
    public Money subtract(Money other) { ... }
    public boolean lessThan(Money other) { ... }
}

public final class Address {
    private final String province;
    private final String city;
    private final String district;
    private final String detail;
    public Address changeDetail(String newDetail) {
        return new Address(province, city, district, newDetail);
    }
}

// 2. 聚合根
public class Order extends AggregateRoot {
    private OrderId id;
    private CustomerId customerId;
    private List<OrderItem> items;
    private Money totalAmount;
    private Address shippingAddress;
    private OrderStatus status;

    // 静态工厂方法
    public static Order place(CustomerId customerId,
                              List<OrderItemRequest> itemRequests,
                              Address address) {
        // 校验+创建+事件 → 详见第六章
    }

    // 行为方法（充血模型）
    public void pay() {
        if (status != OrderStatus.CREATED)
            throw new OrderStateException("只能支付已创建的订单");
        status = OrderStatus.PAID;
        registerEvent(new OrderPaidEvent(id));
    }

    public void cancel() {
        if (status == OrderStatus.DELIVERING || status == OrderStatus.COMPLETED)
            throw new OrderStateException("已发货/已完成订单不能取消");
        status = OrderStatus.CANCELLED;
        registerEvent(new OrderCancelledEvent(id));
    }

    public void deliver() {
        if (status != OrderStatus.PAID)
            throw new OrderStateException("只能发货已支付的订单");
        status = OrderStatus.DELIVERING;
        registerEvent(new OrderDeliveredEvent(id));
    }
}

// 3. 聚合内实体
public class OrderItem {
    private OrderItemId id;
    private ProductId productId;
    private int quantity;
    private Money unitPrice;

    public Money getSubtotal() {
        return unitPrice.multiply(quantity);
    }
}

// 4. 领域事件
public class OrderPlacedEvent extends DomainEvent {
    private final OrderId orderId;
    private final CustomerId customerId;
    private final List<OrderItemInfo> items;
    private final Money totalAmount;
}

// 5. Repository接口（领域层定义）
public interface OrderRepository {
    Order findById(OrderId id);
    void save(Order order);
}

// ====== Application Layer ======

public class OrderApplicationService {
    private OrderRepository orderRepository;
    private DomainEventPublisher eventPublisher;
    private CustomerAclAdapter customerAcl;     // 防腐层
    private ProductAclAdapter productAcl;       // 防腐层

    @Transactional
    public OrderId placeOrder(PlaceOrderCommand cmd) {
        // 1. 通过防腐层获取跨上下文信息
        Customer customer = customerAcl.getCustomer(cmd.getUserId());
        List<OrderItemRequest> items = productAcl.translate(cmd.getItems());

        // 2. 调用聚合根工厂方法（业务逻辑全在聚合根）
        Order order = Order.place(customer.getId(), items, cmd.getAddress());

        // 3. 持久化
        orderRepository.save(order);

        // 4. 发布领域事件
        eventPublisher.publishAll(order.getEvents());
        order.clearEvents();

        return order.getId();
    }

    @Transactional
    public void payOrder(OrderId orderId, PaymentMethod method) {
        Order order = orderRepository.findById(orderId);
        order.pay();  // 业务逻辑在聚合根
        orderRepository.save(order);
        eventPublisher.publishAll(order.getEvents());
        order.clearEvents();
    }
}

// ====== Infrastructure Layer ======

public class JpaOrderRepository implements OrderRepository {
    private OrderJpaRepository jpaRepo;

    @Override
    public Order findById(OrderId id) {
        OrderPO po = jpaRepo.findById(id.getValue())
            .orElseThrow(() -> new OrderNotFoundException(id));
        return OrderConverter.toDomain(po);
    }

    @Override
    public void save(Order order) {
        OrderPO po = OrderConverter.toPO(order);
        jpaRepo.save(po);
    }
}

public class CustomerAclAdapter {  // 防腐层实现
    private UserServiceClient userServiceClient;

    public Customer getCustomer(UserId userId) {
        UserDTO user = userServiceClient.getUser(userId);
        // 翻译：User上下文 → Order上下文
        return new Customer(
            new CustomerId(user.getId()),
            user.getName(),
            new Address(user.getProvince(), user.getCity(),
                        user.getDistrict(), user.getDetail())
        );
    }
}

// ====== Interface Layer ======

@RestController
public class OrderController {
    private OrderApplicationService orderAppService;
    private OrderAssembler assembler;  // DTO组装器

    @PostMapping("/orders")
    public OrderResponseDTO placeOrder(@RequestBody PlaceOrderRequest request) {
        PlaceOrderCommand cmd = assembler.toCommand(request);
        OrderId orderId = orderAppService.placeOrder(cmd);
        return assembler.toResponse(orderId);
    }
}
```

---

## 第十四章 DDD 常见误区与最佳实践

### 14.1 常见误区

```
┌──────────────────────────────────────────────────────────────┐
│              DDD 常见 8 大误区                                │
│                                                              │
│  误区一："DDD 就是充血模型"                                  │
│  ────────────────────────────                                │
│  ❌ 只把Entity从贫血改成充血 → 不是DDD                       │
│  ✅ DDD = 统一语言 + 战略设计 + 战术设计                     │
│  充血模型只是战术设计的一部分                                │
│                                                              │
│  误区二："每个微服务就是限界上下文"                          │
│  ───────────────────────────────                              │
│  ❌ 先拆微服务再定义限界上下文 → 本末倒置                    │
│  ✅ 先做战略设计识别限界上下文 → 再决定是否拆微服务           │
│                                                              │
│  误区三："聚合越大越好"                                      │
│  ────────────────────                                        │
│  ❌ 把所有相关对象都放进一个聚合 → 事务范围大 + 性能差        │
│  ✅ 聚合尽量小，只包含必须一起修改的对象                     │
│                                                              │
│  误区四："所有逻辑都放聚合根"                                │
│  ────────────────────────                                    │
│  ❌ 聚合根变成几千行的巨型类 → 又回到 Service 膨胀问题       │
│  ✅ 单一职责：聚合根只管聚合内规则                           │
│  跨聚合逻辑放领域服务，编排放应用服务                        │
│                                                              │
│  误区五："领域对象必须加JPA注解"                             │
│  ────────────────────────                                    │
│  ❌ Order加@Entity → 领域对象被框架绑架                     │
│  ✅ 领域对象纯粹无注解 → PO单独做数据映射                    │
│                                                              │
│  误区六："DDD只适合复杂业务"                                 │
│  ────────────────────────                                    │
│  ❌ CRUD简单业务也要DDD → 过度设计                           │
│  ✅ 核心域用DDD精细建模，通用域用简单CRUD                    │
│                                                              │
│  误区七："必须用CQRS和事件溯源"                              │
│  ────────────────────────                                    │
│  ❌ 每个限界上下文都CQRS → 维护成本爆炸                     │
│  ✅ 只在高读写比/审计需求场景用CQRS+ES                       │
│                                                              │
│  误区八："DDD一步到位"                                      │
│  ────────────────                                            │
│  ❌ 项目一开始就完整DDD设计 → 过度设计                       │
│  ✅ 先模块化单体 → 验证边界 → 逐步拆分                      │
│  DDD是渐进式方法，不是一步到位                                │
└──────────────────────────────────────────────────────────────┘
```

### 14.2 最佳实践

```
┌──────────────────────────────────────────────────────────────┐
│              DDD 最佳实践 10 条                               │
│                                                              │
│  1. 统一语言先行                                             │
│  先和业务专家建立术语表，再写代码                             │
│  代码命名 = 业务术语 = 文档术语                              │
│                                                              │
│  2. 战略设计先于战术设计                                     │
│  先画限界上下文图 → 再设计聚合/实体                          │
│  战略方向错了 → 战术再精细也白搭                             │
│                                                              │
│  3. 从核心域开始                                             │
│  核心域 = 业务竞争力 = 最值得精细建模                       │
│  通用域用现成方案，不需要DDD                                 │
│                                                              │
│  4. 聚合尽量小                                               │
│  小聚合 = 小事务 = 少锁冲突 = 高性能                        │
│  聚合间通过ID引用 + 领域事件异步一致                         │
│                                                              │
│  5. 值对象优先                                               │
│  能用值对象就不用实体                                        │
│  值对象不可变 = 更安全 = 更简单                              │
│                                                              │
│  6. 防腐层必建                                               │
│  消费上游数据必通过ACL翻译                                   │
│  保护自己的领域模型不被上游腐蚀                              │
│                                                              │
│  7. 领域对象与PO分离                                         │
│  领域对象无框架注解 → 可以自由设计                          │
│  PO/DTO/领域对象各自独立 → 通过Converter翻译                │
│                                                              │
│  8. 渐进式演进                                               │
│  先模块化单体 → 验证边界 → 再拆微服务                       │
│  不要一开始就追求完整DDD                                     │
│                                                              │
│  9. 事件风暴工作坊                                           │
│  和业务专家一起做事件风暴 → 发现领域事件和聚合              │
│  形成统一语言和限界上下文                                    │
│                                                              │
│  10. 测试驱动                                                │
│  领域逻辑必须有单元测试                                     │
│  Application Service有集成测试                               │
│  Repository实现有基础设施测试                                │
└──────────────────────────────────────────────────────────────┘
```

---

## 第十五章 10 道面试高频题

### Q1：什么是DDD？它解决什么问题？

```
标准回答：

  DDD（Domain-Driven Design）是Eric Evans 2003年提出的软件设计方法。
  核心公式：代码结构 ≈ 业务结构

  它解决三大问题：
  1. 贫血模型 → Service膨胀，对象只是数据容器，失去表达能力
  2. 业务与技术脱节 → 代码术语和业务术语不一致，沟通成本高
  3. 架构与业务不对齐 → 微服务拆分凭技术直觉而非业务边界

  DDD三部曲：
  1. 统一语言 — 开发和业务用同一套术语
  2. 战略设计 — 识别子域、划分限界上下文、定义上下文映射
  3. 战术设计 — 实体/值对象/聚合/领域服务/领域事件/工厂/仓储

  DDD不是一步到位的框架，而是渐进式的设计方法论。
  核心域精细建模，通用域简单CRUD，不要过度设计。
```

### Q2：限界上下文是什么？为什么需要？

```
标准回答：

  限界上下文 = 一个明确的语义边界，边界内统一语言无歧义。

  为什么需要：
  同一个词在不同业务语境含义不同。
  "Product"在商品上下文=SKU/价格/描述，
  在订单上下文=购买数量/成交价/订单行项目，
  在物流上下文=重量/体积/配送要求。

  如果只有一个Product类 → 所有属性混在一起 → 类膨胀。

  限界上下文解决：
  每个上下文有自己的模型 → 商品上下文的Product只含商品属性
  订单上下文的OrderItem只含交易属性 → 各自演进互不干扰

  ⚠️ 限界上下文 ≠ 子域
  子域 = 问题空间（业务需要什么）
  限界上下文 = 解决空间（软件怎么实现）
  通常1个子域≈1个限界上下文，但并非必须。
```

### Q3：实体和值对象有什么区别？怎么选择？

```
标准回答：

  实体（Entity）：有唯一ID，生命周期内属性可变，相等性基于ID
  值对象（Value Object）：无ID，不可变，相等性基于所有属性值

  选择决策：这个概念需要追踪生命周期吗？
  需要追踪 → 实体（如Order、Customer）
  不需要追踪 → 值对象（如Money、Address、OrderStatus）

  优先选择值对象：更安全（不可变=无副作用）、更简单

  面试追问：值对象在数据库怎么存？
  → 不需要独立表（值对象没有ID）
  → 内嵌在实体表：Address字段直接存在Order表
  → 或序列化为JSON字段
  → 或拆为多列province/city/district/detail
```

### Q4：聚合和聚合根是什么？设计原则？

```
标准回答：

  聚合 = 一组相关对象的集合，作为数据修改的单元
  聚合根 = 聚合的入口对象和管理者

  聚合三大规则：
  1. 聚合内必须一起修改（事务一致性）
  2. 外部只能通过聚合根访问聚合内对象
  3. 聚合间通过ID引用，不直接引用内部对象

  聚合设计四大原则：
  1. 聚合尽量小 → 小事务+少锁冲突+高性能
  2. 通过ID引用其他聚合 → Order持有paymentId而非Payment对象
  3. 聚合内强一致，聚合间最终一致 → 领域事件保证
  4. 每次事务只修改一个聚合 → 跨聚合用事件异步

  面试追问：聚合边界怎么定？
  → 找"必须一起修改"的对象组 → 如果两个对象不需要在同一个事务里修改 → 分为不同聚合
```

### Q5：防腐层是什么？为什么需要？

```
标准回答：

  防腐层（Anti-Corruption Layer, ACL）= 下游上下文的翻译层
  将上游模型翻译为下游自己的领域模型，防止被"腐蚀"

  为什么需要：
  上游模型不适合下游业务语义 → 如果直接使用上游模型
  → 下游领域模型被污染 → 失去自己的业务表达能力

  例：订单上下文需要用户信息
  ❌ 直接用User上下文的User类 → User包含密码/角色等订单不需要的信息
  ✅ 通过ACL翻译 → User翻译为Customer → 只含订单需要的字段

  实现：Adapter模式 → UserToCustomerAdapter将UserDTO翻译为Customer

  防腐层是DDD最关键的实践模式：
  保护领域模型纯洁性 → 确保每个上下文有自己独立的模型
```

### Q6：领域服务和应用服务有什么区别？

```
标准回答：

  领域服务（Domain Service）：
  - 在领域层，纯业务逻辑
  - 不属于任何实体/值对象的跨聚合业务规则
  - 只依赖领域对象，无技术依赖

  应用服务（Application Service）：
  - 在应用层，编排和协调
  - 不含业务逻辑（只调用领域对象）
  - 管理事务、发布事件、调用基础设施
  - 可跨限界上下文（通过ACL）

  职责清晰划分：
  应用服务 → 加载聚合根 → 调用聚合根方法 → 保存 → 发布事件
  业务逻辑全在聚合根和领域服务 → 应用服务只编排不决策

  ❌ 常见错误：把业务逻辑塞到应用服务 → 又回到贫血模式
  ✅ 正确做法：应用服务不含if-else业务判断
```

### Q7：领域事件是什么？怎么实现跨聚合一致性？

```
标准回答：

  领域事件 = 颟域中发生的有意义的业务事件
  用过去时态命名：OrderPlaced / OrderPaid

  跨聚合一致性方案：
  聚合内 → 强一致（一个事务）
  聚合间 → 最终一致（领域事件）

  例：下单 → Order聚合发布OrderPlacedEvent
  → 库存聚合监听 → 扣减库存（异步）
  → 促销聚合监听 → 核销优惠券（异步）

  事件发布可靠方案：事件表模式
  1. 业务操作+事件记录同一事务写入DB
  2. 定时任务扫描PENDING事件 → 发MQ → 标记PUBLISHED
  → 事件绝不丢失，可重试，可审计

  面试追问：领域事件和MQ消息的区别？
  → 颟域事件是业务概念（OrderPlaced），MQ消息是技术实现
  → 一个领域事件可能对应多条MQ消息
  → 颟域事件在领域层产生，MQ在基础设施层发布
```

### Q8：CQRS是什么？什么时候用？

```
标准回答：

  CQRS = Command Query Responsibility Segregation
  读和写使用不同的模型

  命令端：聚合根+Repository+领域事件 → 关注业务规则
  查询端：读模型+QueryService+DTO → 关注查询性能

  数据同步：命令端变更 → 颟域事件 → 投影到读库

  适用场景：
  ✅ 读多写少（比例>10:1）
  ✅ 读模型复杂（需要多维度查询）
  ✅ 写模型复杂（需要严格业务规则）
  ✅ 性能要求高（读写分别优化）

  不适用：
  ❌ 简单CRUD（读写模型差不多）
  ❌ 强一致读（CQRS读是最终一致）
  ❌ 小团队（维护两个模型成本高）

  ⚠️ CQRS不等于事件溯源，两者独立但天然搭配
```

### Q9：DDD怎么落地到微服务？

```
标准回答：

  落地路径：模块化单体 → 核心域拆分 → 全微服务

  Step 1：战略设计识别限界上下文
  Step 2：模块化单体验证边界（Maven多模块，模块间接口依赖）
  Step 3：核心域优先拆微服务（核心竞争力先独立部署）
  Step 4：支撑域按需拆分（按变化频率）
  Step 5：通用域用开源/SaaS替代

  关键：不要一开始就拆微服务！
  先模块化验证 → 边界稳定后再拆 → 避免拆错

  拆分验证标准：
  独立部署 + 独立数据库 + 独立团队 + 独立演进 + 故障隔离

  拆分前准备：
  颟域事件机制 + API契约 + 防腐层 + 分布式事务方案 + 可观测性
```

### Q10：DDD常见的坑有哪些？怎么避免？

```
标准回答：

  8大误区：
  1. DDD=充血模型 → 实际DDD是统一语言+战略设计+战术设计
  2. 先拆微服务再定义上下文 → 本末倒置，应该先战略设计
  3. 聚合越大越好 → 应该聚合尽量小
  4. 所有逻辑放聚合根 → 应该合理分配到领域服务/应用服务
  5. 领域对象加JPA注解 → 应该领域对象和PO分离
  6. DDD只适合复杂业务 → 核心域用DDD，通用域用CRUD
  7. 必须用CQRS+ES → 只在高读写比/审计场景用
  8. DDD一步到位 → 应该渐进式演进

  避坑指南：
  - 核心域精细DDD，通用域简单CRUD
  - 先模块化单体，再拆微服务
  - 聚合尽量小，值对象优先
  - 必建防腐层，领域对象和PO分离
  - 不追求一步到位，渐进式演进
```

---

> 📌 **核心概念速查表**

| 概念 | 定义 | 关键规则 |
|------|------|----------|
| 统一语言 | 开发和业务用同一套术语 | 代码命名=业务术语 |
| 子域 | 核心域/支撑域/通用域 | 核心域精细建模，通用域用现成方案 |
| 限界上下文 | 语义边界，边界内术语无歧义 | 1子域≈1上下文 |
| 上下文映射 | 上下文间的关系模式 | ACL防腐层最关键 |
| 实体 | 有ID，可变，equals基于ID | 需要追踪生命周期时用 |
| 值对象 | 无ID，不可变，equals基于属性 | 优先选择，比实体更安全 |
| 聚合 | 一组相关对象，数据修改单元 | 聚合尽量小 |
| 聚合根 | 聚合的入口和管理者 | 外部只通过根访问 |
| 领域服务 | 不属于实体/值对象的业务逻辑 | 只做跨聚合规则 |
| 应用服务 | 编排协调，不含业务逻辑 | 只调用领域对象 |
| 领域事件 | 有意义的业务事件 | 过去时态命名 |
| 工厂 | 创建复杂聚合根 | 创建不持久化 |
| 仓储 | 聚合根的存取接口 | 只存取聚合根，只按ID查找 |
| 防腐层 | 上游→下游模型翻译 | 保护领域模型纯洁性 |
| CQRS | 读和写分离 | 读多写少场景适用 |
| 事件溯源 | 存事件不存状态 | 审计追踪场景适用 |
| 四层架构 | Interface/App/Domain/Infra | Domain不依赖Infra |
| 六边形架构 | Ports & Adapters | 领域中心+端口+适配器 |
