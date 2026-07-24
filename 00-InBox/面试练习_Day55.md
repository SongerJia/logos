# 面试模拟 - Day 55

> 日期：2026-07-25（周六） | 模拟岗位：腾讯（杭州）- 微信支付/金融科技 - Java开发工程师
> 建议时长：85分钟（一面55分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day55，"查漏补缺"阶段第五周。模拟腾讯杭州研发中心——微信支付/金融科技线。腾讯面试特点：计算机基础功底要求极高（网络协议必考）、追问底层到"为什么这么设计"、系统设计题偏好海量并发场景、喜欢考"你有没有看过源码"。今天引入 HTTP/HTTPS 协议原理、Dubbo RPC 原理深入、Java 内存区域与 OOM 诊断、MySQL 分库分表实战、Java 并发容器 5 个全新话题——都是高频考点但之前没有作为独立话题系统考过的内容。

---

# 一面（55分钟）

## 话题一：HTTP/HTTPS 协议原理（12分钟）

**面试官：你做金融系统，接口安全很重要。HTTP 和 HTTPS 有什么区别？HTTPS 的加密过程你了解吗？TLS 握手是怎么做的？**

> 你回答...

**追问1：** 先说说 HTTP 协议本身有什么问题？为什么要引入 HTTPS？

> 你回答...（提示：HTTP 的问题 / HTTP（HyperText Transfer Protocol）：①明文传输 → 数据不加密 → 中间人能看到内容 → 银行卡号/密码裸奔 ②无身份验证 → 你以为访问的是银行网站 → 实际是钓鱼网站 → DNS 劫持 → 域名解析到假IP ③无完整性校验 → 数据传输过程中被篡改 → 你转100块 → 中间人改成10000块 → 你不知道 ④HTTP/1.1 的问题 → 明文 → 还有一个问题 → 请求头明文 → 每次 HTTP 请求都带 Cookie → 被中间人截获 → Cookie 泄露 → 伪造身份 / HTTPS = HTTP + SSL/TLS → 在 HTTP 和 TCP 之间加了一层加密 ①加密 → 数据传输加密 → 中间人看不到内容 ②身份验证 → 数字证书 → 证明你访问的是真正的服务器 → 防钓鱼 ③完整性校验 → MAC（消息认证码）→ 数据被篡改能检测到 / 端口区别 → HTTP 80 → HTTPS 443 / 面试重点：HTTP=明文+无身份验证+无完整性校验 → HTTPS=HTTP+TLS(加密+证书+MAC) → 端口80→443）

**追问2：** TLS 握手过程详细说一下。客户端和服务器之间交互了哪些消息？为什么要有这么多步？

> 你回答...（提示：TLS 1.2 握手过程（4次交互）/ 第一次：Client Hello ①客户端 → 发送 ClientHello → 包含：TLS版本号（如 1.2）、客户端随机数（Client Random，32字节）、加密套件列表（Cipher Suites，如 TLS_RSA_WITH_AES_256_CBC_SHA）、压缩方法 ②客户端随机数 → 后面用来生成会话密钥 → 两个随机数（客户端+服务端）才能生成不可预测的密钥 / 第二次：Server Hello + Certificate + ServerHelloDone ①服务器 → 返回 ServerHello → 包含：选择的TLS版本、服务器随机数（Server Random，32字节）、选择的加密套件（从客户端列表中选一个）②服务器 → 发送 Certificate → 服务器证书（X.509）→ 证书里包含：服务器的公钥、证书颁发机构(CA)签名、有效期、域名 ③服务器 → 发送 ServerKeyExchange（如果用 ECDHE 密钥交换 → 额外发送 DH 参数）④服务器 → 发送 ServerHelloDone → 通知客户端我发完了 / 证书验证：①客户端 → 用CA的公钥验证服务器证书的签名 → 验证通过 → 证书可信 ②检查域名匹配 → 证书里的域名 = 访问的域名 ③检查有效期 → 没过期 ④检查吊销列表(CRL/OCSP) → 没被吊销 / 第三次：Client Key Exchange + Change Cipher Spec + Finished ①客户端 → 生成 Pre-Master Secret（48字节随机数）→ 用服务器证书的公钥加密 → 发送 ClientKeyExchange ②服务器 → 用自己的私钥解密 → 得到 Pre-Master Secret ③双方 → 用 Client Random + Server Random + Pre-Master Secret → 生成 Master Secret → 再生成会话密钥（Session Key）④客户端 → 发送 ChangeCipherSpec → 通知服务器"后续消息我用加密了" ⑤客户端 → 发送 Finished → 用会话密钥加密的第一条消息 → 包含之前所有握手消息的Hash → 服务器验证完整性 / 第四次：Change Cipher Spec + Finished ①服务器 → 发送 ChangeCipherSpec → 通知客户端"后续我也用加密了" ②服务器 → 发送 Finished → 用会话密钥加密 → 包含之前所有握手消息的Hash → 客户端验证完整性 ③握手完成 → 后续用对称加密通信 / 密钥交换的核心思路：①非对称加密（RSA/ECC）→ 用来交换 Pre-Master Secret → 安全但慢 → 只在握手时用一次 ②对称加密（AES）→ 用 Session Key 加密通信数据 → 快 → 整个会话用 ③核心思想 → 用慢的非对称加密交换密钥 → 用快的对称加密传输数据 → 兼顾安全和性能 / TLS 1.3 优化（2次交互）：①TLS 1.3 把握手简化为 1-RTT → 甚至支持 0-RTT（Session Resumption）②去掉了 RSA 密钥交换 → 只用 ECDHE（前向安全：即使私钥泄露，之前的通信也解密不了）③TLS 1.2 要 2-RTT → TLS 1.3 只要 1-RTT → 甚至 0-RTT → 性能提升 / 面试重点：TLS 1.2 四次握手 → ClientHello(客户端随机数) → ServerHello(服务端随机数)+Certificate(公钥) → ClientKeyExchange(Pre-Master用公钥加密) → 双方用三个随机数生成SessionKey → ChangeCipherSpec+Finished → 后续对称加密通信。非对称交换密钥+对称传输数据）

**追问3：** 对称加密和非对称加密分别是什么？HTTPS 里用了哪种？为什么要这样组合？

> 你回答...（提示：对称加密 vs 非对称加密 / 对称加密：①加密和解密用同一个密钥 → A用key加密 → B用同一个key解密 ②常见算法 → AES（AES-128/AES-256）/ DES（已不安全）/ 3DES ③优点 → 快 → AES-256 每秒加密几百MB → 适合大数据量 ④缺点 → 密钥分发问题 → A怎么把key安全地给B → 如果通过网络传 → 中间人截获 → 加密就没意义了 ⑤场景 → 数据传输（HTTPS握手后）/ 文件加密 / 非对称加密：①一对密钥 → 公钥(Public Key)和私钥(Private Key) → 公钥加密 → 只有私钥能解密 → 私钥加密（签名）→ 公钥验证 ②常见算法 → RSA（2048位/4096位）/ ECC（椭圆曲线，256位ECC≈3072位RSA安全性）/ ③优点 → 解决了密钥分发问题 → 公钥随便公开 → 私钥自己保管 → 想给我发消息用我的公钥加密 → 只有我的私钥能解 ④缺点 → 慢 → RSA比AES慢1000倍 → 加密大数据量不现实 ⑤场景 → 密钥交换（HTTPS握手）/ 数字签名（验证身份）/ 证书 / HTTPS 的组合：①握手阶段 → 非对称加密 → 交换 Pre-Master Secret → 安全但慢 → 只用一次 ②通信阶段 → 对称加密 → 用 Session Key 加密所有数据 → 快 → 整个会话用 ③为什么组合 → 非对称解决密钥分发 → 对称解决传输速度 → 两个优点都拿到 / 数字签名：①私钥加密 → 公钥解密 → 证明"这确实是我发的" ②Hash → 私钥加密Hash → 公钥解密Hash → 对比 → 证明"没被篡改" ③证书 = 服务器公钥 + CA签名 → CA用CA私钥签名 → 客户端用CA公钥验签 → 证明证书可信 / 面试重点：对称(AES同一密钥/快但密钥分发难) + 非对称(RSA公私钥对/慢但解决分发) → HTTPS=握手用非对称交换密钥 + 通信用对称加密数据 → 兼顾安全和性能）

**追问4：** 你提到证书。数字证书的验证过程是怎样的？如果证书被伪造了怎么办？

> 你回答...（提示：数字证书验证链 / 证书结构（X.509）：①版本号、序列号 ②签名算法（SHA256-RSA）③颁发者(Issuer) → 如 DigiCert ④有效期 ⑤主体(Subject) → 如 `*.weixin.qq.com` ⑥主体公钥 → 服务器的公钥 ⑦CA的数字签名 → CA用私钥对证书内容的Hash签名 / 验证过程：①收到服务器证书 ②找到颁发者 → 找到CA证书（CA的公钥在操作系统/浏览器预装）③用CA公钥验证签名 → 对比证书内容的Hash和签名解密后的Hash → 一致 → 证书没被篡改 ④检查域名匹配 → 证书的Subject的域名 = 访问的域名 ⑤检查有效期 → 当前时间在有效期内 ⑥检查吊销 → CRL(Certificate Revocation List)或OCSP(Online Certificate Status Protocol)→ 查证书有没有被吊销 → 如私钥泄露后CA会吊销证书 / 证书链：①根证书(Root CA) → 自签名 → 操作系统/浏览器预装 → 如 DigiCert Root CA ②中间证书(Intermediate CA) → 根证书签发 → 如 DigiCert SHA2 Secure Server CA ③终端证书(End-entity) → 中间证书签发 → 如 `*.weixin.qq.com` ④验证链 → 终端证书 → 中间证书签名验证 → 中间证书 → 根证书签名验证 → 根证书 → 自签名 → 预装信任 → 链路完整 / 证书伪造问题：①中间人伪造证书 → 但中间人没有CA私钥 → 无法生成合法签名 → 客户端验签失败 → 浏览器报"证书不受信任" ②中间人自己建一个CA → 但这个CA不在操作系统预装列表 → 客户端不信任 → 验证失败 ③中间人入侵CA机构 → 获取CA私钥 → 可以伪造任何证书 → 这就是CA机构安全的重要性 → DigiNotar事件 → 2011年被黑 → 签发了`*.google.com`的假证书 → 导致破产 / HTTP 证书固定(Certificate Pinning)：①App内置服务器证书的Hash → 只信任这个证书 → 即使CA被入侵也安全 ②银行App/微信 → 证书固定 → 不信任系统CA列表 → 只信任自己的证书 / 面试重点：证书=X.509(公钥+CA签名) → 验证=CA公钥验签+域名匹配+有效期+吊销检查 → 证书链=终端→中间→根(预装信任) → 伪造=没有CA私钥无法签名 → 固定=App内置证书Hash防CA入侵）

---

## 话题二：Dubbo RPC 原理深入（11分钟）

**面试官：你了解过 Dubbo 吗？你们微服务用 Feign 还是 Dubbo？Dubbo 和 Feign（HTTP 调用）有什么本质区别？**

> 你回答...

**追问1：** 先说说 Dubbo 的整体架构。Provider、Consumer、Registry、Monitor 各自的角色是什么？

> 你回答...（提示：Dubbo 架构 / 核心角色：①Provider → 服务提供者 → 暴露服务 → 注册到注册中心 → 等待Consumer调用 ②Consumer → 服务消费者 → 订阅注册中心 → 获取Provider列表 → 调用服务 ③Registry → 注册中心 → Nacos/ZooKeeper → 存储服务地址 → 变更推送 ④Monitor → 监控中心 → 统计调用次数/耗时/成功率 → 定期上报 / 调用流程：①Provider启动 → `export()` → 把接口信息(接口名/版本/IP:port)注册到Registry ②Consumer启动 → `refer()` → 从Registry订阅 → 获取Provider列表 → 在本地生成代理对象(Proxy) ③Consumer调用 → 调代理对象 → 代理对象选一个Provider → 发起RPC调用 → 序列化请求 → 网络传输(Netty/TCP) → Provider接收 → 反序列化 → 反射调用本地实现 → 返回结果 → 序列化 → 网络传输 → Consumer反序列化 → 返回 ④Provider下线 → Registry感知(心跳)→ 推送变更通知 → Consumer更新本地Provider列表 / 和Feign(HTTP)的区别：①协议 → Feign用HTTP(应用层) → Dubbo用TCP自定义协议(传输层)→ ②序列化 → Feign用JSON(文本/大) → Dubbo用Hessian2(二进制/小/快)→ 同一个对象JSON 200字节 → Hessian2 60字节 → 带宽省3倍 ③连接 → Feign每次HTTP请求可能新建连接(Keep-Alive但短连接)→ Dubbo用长连接(TCP持久)→ 减少连接建立开销 ④性能 → Dubbo比Feign快3-5倍 → 金融系统内部高频调用用Dubbo → 对外接口用HTTP ⑤服务治理 → Dubbo内置丰富(集群容错/负载均衡/路由规则)→ Feign依赖Spring Cloud组件 / Dubbo 3.x → Triple协议(基于HTTP/2+gRPC)→ 兼容HTTP → 既快又能跨语言 / 面试重点：Dubbo=Provider注册+Consumer订阅+Registry通知+TCP长连接+Hessian2序列化 → 比Feign(HTTP+JSON)快3-5倍 → 金融内部用Dubbo外部用HTTP）

**追问2：** Dubbo 的集群容错策略有哪些？默认是哪种？Failover 是怎么重试的？

> 你回答...（提示：Dubbo 集群容错 / 容错策略：①Failover（默认）→ 失败自动重试 → 默认重试2次 → 共3次调用 → 适合读操作/幂等操作 → 但不适合写操作 → 重试可能导致重复写入 ②Failfast → 快速失败 → 失败立即报错 → 不重试 → 适合非幂等写操作（如新增记录）→ 重试会导致重复创建 ③Failsafe → 失败安全 → 出异常直接忽略 → 返回空结果 → 适合写审计日志/监控上报 → 不重要不怕丢 ④Failback → 失败自动恢复 → 失败后记录到失败队列 → 后台定时重试 → 适合实时性不高的消息通知 ⑤Forking → 并行调用 → 同时调N个Provider → 一个成功就返回 → 用多线程 → 适合实时性要求极高的读 → 资源浪费但快 ⑥Broadcast → 广播 → 逐个调所有Provider → 任意一个报错就算失败 → 适合刷新所有节点的本地缓存 / Failover 重试机制：①第一次调用失败（网络超时/服务端异常）→ 自动切换到另一个Provider重试 ②默认 retries=2 → 最多重试2次 → 加上第一次 → 共3次 ③重试会重新选择Provider → 不在失败的Provider上重试 → 从Provider列表中选另一个 ④配置 → `@DubboReference(retries = 3)` → 或XML `<dubbo:reference retries="3" />` ⑤幂等性问题 → 如果是扣款操作 → 第一次调用可能服务端已经扣了 → 但网络超时Consumer不知道 → 重试 → 扣两次 → 所以非幂等操作不能用Failover → 用Failfast / 负载均衡策略（选Provider）：①Random（默认）→ 按权重随机 → 权重高的被选概率大 → 均匀分布 ②RoundRobin → 轮询 → 按权重轮询 → 公平但慢Provider拖累整体 ③LeastActive → 最少活跃数 → 谁处理得快就给谁 → 慢的Provider少分配 → 最公平 ④ConsistentHash → 一致性Hash → 同一个请求参数路由到同一个Provider → 有状态场景（如Session） / 面试重点：Failover(默认/重试2次/共3次/适合读幂等) vs Failfast(快速失败/不重试/适合非幂等写) vs Forking(并行/N个取最快) → 负载均衡=Random默认/LeastActive最快/ConsistentHash有状态）

**追问3：** Dubbo 的 SPI 和 Java 的 SPI 有什么区别？Dubbo 为什么要自己搞一套？

> 你回答...（提示：Dubbo SPI vs Java SPI / Java SPI（ServiceLoader）：①在 `META-INF/services/` 目录下放文件 → 文件名是接口全限定名 → 内容是实现类全限定名 ②`ServiceLoader.load(接口.class)` → 遍历文件 → 全部实例化 → 返回所有实现 ③问题一 → 全部实例化 → 即使你只需要一个 → 浪费资源 → 如有10个序列化实现 → 全部new → 只用一个 ④问题二 → 没法按需加载 → 不能根据参数选择具体实现 ⑤问题三 → 没法IOC → 实现类依赖其他组件 → Java SPI不帮你注入 / Dubbo SPI（ExtensionLoader）：①在 `META-INF/dubbo/` 目录下放文件 → 文件名是接口全限定名 → 内容是 `key=实现类` → 如 `dubbo=org.apache.dubbo.rpc.protocol.dubbo.DubboProtocol` ②按需加载 → `ExtensionLoader.getExtensionLoader(Protocol.class).getExtension("dubbo")` → 只实例化你指定的那个 → 不全部加载 ③自适应扩展(@Adaptive)→ 运行时根据参数动态选择实现 → 如 `@Adaptive("protocol")` → 根据URL里的protocol参数 → 选对应的Protocol实现 → 运行时生成动态代理 ④Wrapper(包装类)→ AOP → 如果实现类有拷贝构造函数(参数是接口类型)→ Dubbo认为是Wrapper → 自动包装 → 如 ProtocolFilterWrapper包Protocol → 添加Filter链 → 类似AOP ⑤IOC注入 → 实现类的setter方法 → Dubbo自动注入依赖 → 如 setProtocol(Protocol p) → Dubbo帮你找到Protocol扩展注入 / Dubbo SPI 的核心设计思想：①Dubbo 的所有组件都是SPI → Protocol/Serialization/LoadBalance/Registry/Cluster/Filter → 全部可扩展 ②你想替换序列化 → 写一个实现 → 放在 `META-INF/dubbo/` → 配置 → 替换 → 不改源码 ③和Spring的关系 → Spring的@Bean也是可扩展 → 但Spring需要在Spring容器里 → Dubbo SPI不依赖Spring → 可以脱离Spring独立运行 ④Dubbo 3.x → 也支持Spring的@Bean → 双轨制 / 为什么不用Spring而搞SPI：①Dubbo设计之初 → 不强制依赖Spring → 可以独立运行 → 所以自己搞SPI ②SPI更轻量 → 不需要启动Spring容器 → 性能更好 ③Dubbo核心组件 → Protocol→Registry→Cluster → 用SPI加载 → 不依赖Spring / 面试重点：Java SPI=全部实例化/不能按需/不能IOC → Dubbo SPI=key=实现按需加载/@Adaptive运行时动态选择/Wrapper自动AOP/setter注入IOC → Dubbo所有组件都是SPI可扩展）

**追问4：** 一次 Dubbo RPC 调用，从 Consumer 发起调用到 Provider 返回结果，中间经过了哪些步骤？

> 你回答...（提示：Dubbo 调用链路 / Consumer 端：①Consumer调用代理对象 → `proxy.sayHello("world")` → 代理对象是Dubbo用Javassist/ByteBuddy生成的 ②InvokerInvocationHandler.invoke() → 封装成RpcInvocation(方法名/参数类型/参数值/附件)→ 调MockClusterInvoker ③集群层(Cluster)→ 路由 → 过滤不可用的Provider → 负载均衡选一个 → FailoverClusterInvoker ④过滤链(Filter)→ ContextFilter/ConsumerContextFilter/EchoFilter → 类似拦截器 ⑤协议层(Protocol)→ DubboProtocol → 组装Request(requestId/数据) ⑥序列化 → Hessian2 → 对象→字节 ⑦交换层(Exchange)→ HeaderExchangeClient → Request放入队列 ⑧传输层(Transport)→ NettyClient → Netty的Channel.write() → TCP发送 / 网络传输：①Netty → EventLoop → Channel → TCP长连接 → 字节流 → Provider端 / Provider 端：①NettyServer → 接收 → EventLoop读取字节 ②反序列化 → Hessian2 → 字节→RpcInvocation对象 ③协议层 → DubboProtocol → 找到对应Exporter ④过滤链 → ContextFilter/ExceptionFilter/TimeoutFilter ⑤反射调用 → `method.invoke(impl, args)` → 调用真正的服务实现 ⑥返回结果 → 序列化 → Response → Netty发送回Consumer ⑦Consumer → 反序列化 → 返回给调用方 / 关键设计：①异步转同步 → Consumer调用是同步的 → 但底层Netty是异步的 → DefaultFuture → 用请求ID关联请求和响应 → `DefaultFuture.get(requestId)` → 阻塞等待 → Response回来后唤醒 ②超时 → 默认1000ms → 超时抛TimeoutException → 底层用Netty的HashedWheelTimer做超时检测 ③线程模型 → Provider端 → Dubbo用固定线程池(默认200)→ IO线程(Netty EventLoop)只负责读 → 业务线程负责执行 → IO和业务隔离 → 防止IO阻塞 / 面试重点：Consumer→代理→集群(路由+负载均衡)→Filter链→Protocol组装Request→Hessian2序列化→Netty TCP传输 → Provider→Netty接收→反序列化→Filter链→反射调用→返回 → 异步转同步用DefaultFuture+requestId → 默认超时1000ms → IO线程和业务线程隔离）

---

## 话题三：Java 内存区域与 OOM 诊断（11分钟）

**面试官：JVM 的内存区域你了解吗？堆、栈、方法区各存什么？不同区域的 OOM 你怎么排查？**

> 你回答...

**追问1：** 先画一下 JVM 内存结构。每个区域存什么？谁是线程共享的，谁是线程私有的？

> 你回答...（提示：JVM 内存区域 / 线程私有：①程序计数器(Program Counter Register)→ 当前线程执行的字节码行号 → 如果执行Java方法 → 记录字节码地址 → 如果执行Native方法 → 为空(Undefined) → 唯一不会OOM的区域 → 内存极小 ②虚拟机栈(VM Stack)→ 每个方法执行时创建一个栈帧(Stack Frame)→ 栈帧包含：局部变量表(方法参数+局部变量)→ 操作数栈(计算中间结果)→ 动态链接(指向运行时常量池的方法引用)→ 方法出口(返回地址)→ StackOverflowError：递归太深 → 栈帧太多 → 默认栈大小512KB-1MB → `-Xss` 调整 → OOM：栈无法扩展（但很少见）③本地方法栈(Native Method Stack)→ 和VM栈一样 → 但服务的是Native方法(C/C++)→ HotSpot把本地方法栈和VM栈合二为一 / 线程共享：①堆(Heap)→ 存对象实例和数组 → GC主要区域 → 分新生代(Eden+S0+S1=8:1:1)→ 老年代 → `-Xms`初始堆 / `-Xmx`最大堆 → OOM: `java.lang.OutOfMemoryError: Java heap space` ②方法区(Method Area)→ 存类信息(类名/字段/方法/构造器)→ 运行时常量池(字符串常量/符号引用)→ 静态变量 → JDK 7之前 → 叫"永久代"(PermGen)→ 在堆中 → `-XX:PermSize` / `-XX:MaxPermSize` → JDK 8+ → 改名"元空间"(Metaspace)→ 移到本地内存(Native Memory)→ `-XX:MetaspaceSize` / `-XX:MaxMetaspaceSize` → 原因：永久代大小固定容易OOM(如大量动态生成类:CGLIB/字节码增强)→ 元空间用本地内存 → 大小随物理内存 → 不容易OOM ③直接内存(Direct Memory)→ NIO的ByteBuffer.allocateDirect()→ 堆外内存 → 不受GC管理 → 适合大文件传输/零拷贝 → `-XX:MaxDirectMemorySize` → OOM: `java.lang.OutOfMemoryError: Direct buffer memory` / 各区域OOM类型：①堆 → `Java heap space` → 对象太多/内存泄漏 ②栈 → `StackOverflowError` → 递归太深 → `Unable to create new native thread` → 线程太多(每个线程1MB栈)③元空间 → `Metaspace space` → 动态生成类太多(CGLIB/Groovy)④直接内存 → `Direct buffer memory` → NIO堆外内存泄漏 / 面试重点：线程私有=PC(行号不OOM)+VM栈(栈帧SOE递归)+本地方法栈 → 线程共享=堆(对象GC)+方法区(类信息/常量池→JDK8元空间移本地内存)+直接内存(NIO)）

**追问2：** 生产环境突然 OOM 了，你怎么排查？不同类型的 OOM 排查思路一样吗？

> 你回答...（提示：OOM 排查流程 / 前提：OOM时自动dump → `-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/log/heapdump.hprof` → OOM时自动生成堆dump → 生产必须配 / 堆 OOM（`Java heap space`）排查：①现象 → 应用报OOM → 停止或重启 ②第一步 → 拿到heapdump.hprof → 用MAT(Memory Analyzer Tool)打开 ③MAT分析 → Leak Suspects报告 → 自动分析可能的泄漏点 → 如"一个HashMap占了80%内存" ④Dominator Tree → 按对象持有内存大小排序 → 找最大的对象 ⑤Histogram → 按类统计对象数量 → 如 `byte[]` 有100万个 → 不正常 ⑥Path to GC Roots → 找到对象的引用链 → 看谁持有了它 → 为什么没被GC ⑦常见原因 → 内存泄漏(静态集合不断增长/ThreadLocal没remove/缓存无淘汰)→ 内存溢出(一次性加载太多数据: SELECT * FROM big_table无分页)→ 解决：修代码/加缓存淘汰/分页查询/加内存 / 元空间 OOM（`Metaspace space`）排查：①现象 → 大量加载类 → 元空间涨满 → OOM ②常见原因 → 动态生成类(CGLIB代理/字节码增强/Groovy脚本/反射大量生成代理类)→ 类加载器泄漏(自定义ClassLoader没释放)③排查 → `jmap -clstats <pid>` → 看类加载器数量 → 如果有几千个ClassLoader → 泄漏了 → 每个ClassLoader加载的类无法卸载 → 元空间涨 ④解决 → 找到不断创建ClassLoader的代码 → 限制/缓存ClassLoader → 增大MaxMetaspaceSize → 临时方案 / 栈 OOM（`StackOverflowError`）排查：①现象 → 线程栈溢出 → 递归调用 ②排查 → `jstack <pid>` → 看线程栈 → 找到递归调用的方法 ③解决 → 修复递归 → 改为迭代 → 或增大栈大小 `-Xss2m` / `Unable to create new native thread` 排查：①现象 → 无法创建新线程 → 线程数太多 ②原因 → 线程池没限制 → 每个请求创建线程 → 或线程泄漏 → 线程不退出 ③排查 → `jstack <pid> | grep "java.lang.Thread.State" | wc -l` → 数线程数 → 如果几万个 → 泄漏 ④解决 → 限制线程池大小 → 修复线程泄漏 → 调整OS线程数限制 `ulimit -u` / 直接内存 OOM 排查：①现象 → NIO堆外内存泄漏 ②原因 → ByteBuffer.allocateDirect()使用后没释放 → 或Netty的ByteBuf没release → 引用计数泄漏 ③排查 → `-XX:NativeMemoryTracking=detail` → `jcmd <pid> VM.native_memory` → 查看本地内存使用 → 或Netty的 `ResourceLeakDetector` → `-Dio.netty.leakDetection.level=ADVANCED` → 检测ByteBuf泄漏 ④解决 → 确保ByteBuf.release()→ 用引用计数管理 → 或用Netty的SimpleLeakAwareByteBuf自动检测 / GC overhead 排查：①现象 → `GC overhead limit exceeded` → GC花太多时间但回收很少 → 98%时间GC但只回收2%内存 ②原因 → 内存几乎满 → GC不停回收但回收不了 → 对象都被引用了 ③排查 → 和堆OOM一样 → dump → MAT分析 → 找泄漏 ④解决 → 修泄漏 / 加内存 / 调GC参数 / 面试重点：堆OOM→MAT分析Leak Suspects+Dominator Tree找最大对象+Path to GC Roots找引用链 → 元空间OOM→jmap -clstats看ClassLoader → 栈SOE→jstack看递归 → 线程OOM→jstack数线程 → 直接内存OOM→NativeMemoryTracking+Netty ResourceLeakDetector）

**追问3：** 你提到运行时常量池。`String.intern()` 你了解吗？JDK 6 和 JDK 7+ 的 intern 有什么区别？

> 你回答...（提示：String.intern() / intern() 方法：①`String.intern()` → 如果字符串常量池中已有相等字符串 → 返回常量池中的引用 → 否则 → 把字符串放入常量池 → 返回引用 ②作用 → 减少重复字符串的内存占用 → 如读取了100万个"SUCCESS" → intern后 → 100万个引用指向同一个"SUCCESS" → 省内存 / JDK 6 vs JDK 7+ 区别：①JDK 6 → 字符串常量池在永久代(PermGen)→ intern() → 把字符串拷贝到永久代 → 如果intern太多 → 永久代OOM ②JDK 7+ → 字符串常量池移到了堆中 → intern() → 不再拷贝字符串 → 只存引用(指向堆中的String对象)→ 省内存 → 且不会撑爆永久代 / 经典面试题：
```java
// JDK 7+
String s1 = new String("hello");          // s1 → 堆中new的String对象(内容"hello")
String s2 = s1.intern();                  // s2 → 常量池中的"hello"引用 → 但JDK7不拷贝 → 存的是s1的引用
String s3 = "hello";                       // s3 → 常量池中的"hello" → 即s1的引用
System.out.println(s1 == s2);             // JDK6: false(一个堆一个永久代) JDK7+: true(都是堆中同一个)
System.out.println(s2 == s3);             // true

// 更经典
String s4 = new String("a") + new String("b");  // s4 → 堆中"ab" → 但常量池没有"ab"
s4.intern();                                     // JDK7 → 常量池存s4的引用 → 不拷贝
String s5 = "ab";                                // s5 → 常量池中的"ab" → 即s4的引用
System.out.println(s4 == s5);                     // JDK6: false JDK7+: true
```
/ intern 使用建议：①不要大量intern → 常量池也是堆内存 → 占满还是会OOM ②适合 → 有限个重复字符串 → 如状态码(HTTP 200/404)、枚举名 → 重复几百万次 → intern后只存一份 ③不适合 → 用户输入 → 每个都不一样 → intern没意义还浪费 ④Google Guava的Interners.newWeakInterner() → 用WeakReference → GC时自动清理 → 比JDK intern安全 / 面试重点：intern()=常量池有就返回没有就加入 → JDK6在永久代拷贝 → JDK7+在堆中存引用不拷贝 → `s1==s1.intern()` JDK7+可能true → 适合有限重复字符串不适合用户输入）

---

## 话题四：手写代码 - 手写简易阻塞队列（8分钟）

**面试官：写一个简单的阻塞队列。要求：put 时如果队列满了就等待，take 时如果队列空了就等待。用 ReentrantLock + Condition 实现。**

你在纸上/白板上写代码...

**追问1：** 先说说你的思路。为什么不用 synchronized + wait/notify？

> 你回答...（提示：阻塞队列实现 / 用 ReentrantLock + 两个 Condition：
```java
public class MyBlockingQueue<T> {
    private final Object[] items;
    private int putIndex, takeIndex, count;
    private final ReentrantLock lock = new ReentrantLock();
    private final Condition notFull = lock.newCondition();   // 队列不满
    private final Condition notEmpty = lock.newCondition();  // 队列不空

    public MyBlockingQueue(int capacity) {
        items = new Object[capacity];
    }

    public void put(T item) throws InterruptedException {
        lock.lockInterruptibly();
        try {
            while (count == items.length) {
                notFull.await();  // 队列满了 → 等待"不满"
            }
            items[putIndex] = item;
            if (++putIndex == items.length) putIndex = 0;  // 环形数组
            count++;
            notEmpty.signal();  // 通知"不空" → 唤醒take
        } finally {
            lock.unlock();
        }
    }

    @SuppressWarnings("unchecked")
    public T take() throws InterruptedException {
        lock.lockInterruptibly();
        try {
            while (count == 0) {
                notEmpty.await();  // 队列空了 → 等待"不空"
            }
            T item = (T) items[takeIndex];
            items[takeIndex] = null;  // 帮助GC
            if (++takeIndex == items.length) takeIndex = 0;  // 环形数组
            count--;
            notFull.signal();  // 通知"不满" → 唤醒put
            return item;
        } finally {
            lock.unlock();
        }
    }
}
```
/ 为什么用两个 Condition 而不是 wait/notify：①wait/notify → 所有等待的线程都在同一个wait set → put和take混在一起 → notify随机唤醒 → 可能唤醒同类（put唤醒put）→ 没意义 → 还得继续等 ②两个Condition → notFull的wait set只放put线程 → notEmpty的wait set只放take线程 → signal精准唤醒对方 → 不浪费 ③这就是ReentrantLock + Condition比synchronized + wait/notify强的核心原因 → 精准唤醒 / 为什么用 while 不用 if：①虚假唤醒(spurious wakeup)→ 线程可能在没有被signal的情况下醒来 → OS层面的不确定行为 → Java规范允许 ②如果用 if → 虚假醒来 → 不检查条件 → 直接往下执行 → 队列可能还是满的/空的 → 出错 ③用 while → 醒来后再检查一次条件 → 如果条件不满足 → 继续await → 安全 ④这也是Java规范要求的 → `wait()`和`await()`必须在while循环中 / 环形数组：①putIndex 和 takeIndex → 都从0开始 → put往前走 → take往前走 → 到数组末尾绕回0 → 环形 ②count 记录元素个数 → 不用区分put和take谁在前 → 只看count → 满了put等 → 空了take等 ③比链表实现快 → 数组连续内存 → 缓存友好 → 无需创建Node对象 / 和 ArrayBlockingQueue 源码对比：①上面的实现 ≈ ArrayBlockingQueue 的核心逻辑 ②ArrayBlockingQueue → 用 ReentrantLock + notEmpty/notFull 两个Condition → 环形数组 → while循环检查 ③ArrayBlockingQueue 默认非公平锁 → `new ReentrantLock(false)` → 性能优先 / 面试重点：ReentrantLock+两个Condition(notFull/notEmpty)精准唤醒 → while防虚假唤醒 → 环形数组 → 这就是ArrayBlockingQueue的核心实现）

**追问2：** 如果要你实现一个优先级阻塞队列（PriorityBlockingQueue），思路是什么？

> 你回答...（提示：优先级阻塞队列 / 思路：①用堆(Heap)→ 最小堆或最大堆 → 入队时插入堆尾 → 上浮(siftUp)调整 → 出队时取堆顶 → 堆尾移到堆顶 → 下沉(siftDown)调整 ②数组实现堆 → 节点i的左子节点 `2i+1` → 右子节点 `2i+2` → 父节点 `(i-1)/2` ③put → 加锁 → 放到数组末尾 → siftUp上浮 → 如果比父节点小(最小堆)→ 交换 → 直到根 ④take → 加锁 → 取根(最小值)→ 末尾移到根 → siftDown下沉 → 和较小的子节点交换 → 直到叶子 ⑤阻塞 → 队列为空时take阻塞 → 用Condition等待 / 和 PriorityQueue 的区别：①PriorityQueue 不是线程安全的 → 单线程用 ②PriorityBlockingQueue = PriorityQueue + ReentrantLock + Condition → 线程安全 ③PriorityBlockingQueue 的 take → 队列空 → await → put后signal → 唤醒 ④但 PriorityBlockingQueue 是无界的 → 默认初始容量11 → 自动扩容(grow)→ 不需要notFull的Condition → put不阻塞 ⑤如果要有界 → 自己加容量检查 / 面试重点：优先级阻塞队列=堆(数组)→put加锁siftUp→take取堆顶siftDown→空时await→PriorityQueue+ReentrantLock=PriorityBlockingQueue）

---

## 话题五：Java 并发容器（13分钟）

**面试官：Java 并发包里有哪些并发容器？ConcurrentHashMap 我们之前聊过，说说 CopyOnWriteArrayList 和 ConcurrentLinkedQueue？**

> 你回答...

**追问1：** CopyOnWriteArrayList 的原理是什么？"写时复制"具体怎么做的？适合什么场景？

> 你回答...（提示：CopyOnWriteArrayList 原理 / 核心思想：写时复制(Copy-On-Write)→ 读操作完全无锁 → 写操作先复制一份新数组 → 修改新数组 → 再把引用指向新数组 / 数据结构：①内部用一个 `volatile Object[] array` → volatile保证可见性 → 写完后 → 读线程立刻能看到新数组 ②用 ReentrantLock 保护写操作 → 防止并发写 / 读操作 get()：
```java
// CopyOnWriteArrayList 的 get
public E get(int index) {
    return (E) array[index];  // 直接读 → 无锁
}
```
①读不加锁 → 直接读volatile数组 → 线程安全(volatile保证可见性)②效率极高 → 没有任何竞争 / 写操作 add()：
```java
// CopyOnWriteArrayList 的 add
public boolean add(E e) {
    final ReentrantLock lock = this.lock;
    lock.lock();  // 加锁
    try {
        Object[] elements = array;     // 读当前数组
        int len = elements.length;
        Object[] newElements = Arrays.copyOf(elements, len + 1);  // 复制新数组
        newElements[len] = e;          // 写新数组
        array = newElements;           // 指向新数组
        return true;
    } finally {
        lock.unlock();
    }
}
```
①加锁 → 防止并发写 ②复制整个数组 → 新数组长度+1 ③新数组写入元素 ④array指向新数组(volatile写 → 读线程立即可见)⑤释放锁 / 弱一致性：①写完后 → 旧线程可能还在读旧数组 → 不会立刻看到新数据 → 弱一致性 ②但最终一致 → 旧读操作很快完成 → 新读操作读新数组 ③不适合实时性要求高的场景 / 适合场景：①读多写少 → 如配置列表/监听器列表(Listener)/事件订阅者 → 读远多于写 ②写很少 → 如初始化时写 → 之后几乎不写 → 全是读 ③允许短暂不一致 → 配置更新后 → 过几秒才生效 → 可以接受 / 不适合场景：①写多 → 每次写都复制整个数组 → O(n) → 写性能差 → 内存浪费(两份数组)②实时性要求高 → 弱一致性 → 读到旧数据 / 和 Collections.synchronizedList 的区别：①synchronizedList → 读写都加锁(synchronized)→ 读也阻塞 → 但强一致 ②CopyOnWriteArrayList → 读无锁 → 弱一致 → 读快但写慢 ③读多写少用COW → 读写都多用synchronizedList → 但后者已被淘汰 → 一般用ConcurrentHashMap或加锁 / 面试重点：COW=读无锁(volatile数组)/写加锁复制新数组替换 → 读多写少(配置/监听器)→ 弱一致性(最终一致)→ 不适合写多(每次O(n)复制)→ get直接读array无锁/add=lock+copyOf+写+替换引用）

**追问2：** ConcurrentLinkedQueue 呢？它怎么做到无锁的？CAS 在这里是怎么用的？

> 你回答...（提示：ConcurrentLinkedQueue 原理 / 核心思想：CAS 无锁队列 → 基于 Michael & Scott 算法 → 用 CAS 操作实现线程安全的入队和出队 → 不用锁 / 数据结构：①Node → `volatile E item` + `volatile Node<E> next` ②head → 指向头节点(哨兵)③tail → 指向尾节点 → 初始 head=tail=new Node(null) / 入队 offer()：①找到尾节点 t = tail ②创建新节点 n = new Node(e) ③CAS设置 t.next = n → `CAS(t.next, null, n)` → 如果t.next是null(没人插入)→ CAS成功 → 设为n ④CAS成功 → 再尝试 CAS(tail, t, n) → 把tail指向新节点 → 如果失败没关系 → 说明别的线程已经更新了tail → tail最终会更新 ⑤CAS失败(有人先插了)→ 重新找尾节点 → 重试 / 出队 poll()：①找到头节点 h = head ②读取 h.next 的 item → CAS(h.next.item, item, null) → 把item设为null → 标记已出队 ③CAS成功 → 推进head = h.next → 返回item ④CAS失败 → 重试 / 为什么 tail 不是每次都更新：①offer → 先CAS设置t.next → 再CAS更新tail → 但第二步可能失败(别的线程已更新)→ tail可能滞后 ②没关系 → 下次offer → 发现tail.next != null → tail滞后了 → 先推进tail = tail.next → 再插入 → 自修复 ③这是设计上的优化 → 减少CAS次数 → 提高吞吐量 → tail不需要实时精确 → 最终会追上 / 和 LinkedBlockingQueue 的区别：①ConcurrentLinkedQueue → 无锁(CAS)→ 无界 → 不阻塞 → 适合高并发非阻塞场景 ②LinkedBlockingQueue → 用锁(ReentrantLock)→ 有界 → 阻塞(满/空时await)→ 适合生产者-消费者模型 ③ConcurrentLinkedQueue 更快(CAS比锁快)→ 但无界 → 可能OOM → 需要自己控制大小 ④LinkedBlockingQueue → 有界 → 阻塞 → 安全 → 但锁竞争 → 稍慢 / size() 的问题：①ConcurrentLinkedQueue 的 size() → O(n) → 要遍历整个队列 → 不准确(并发修改)→ 非阻塞 ②不要用size()判断空/满 → 用 isEmpty() / peek() == null ③和 ConcurrentHashMap 一样 → size只是近似值 / 面试重点：ConcurrentLinkedQueue=CAS无锁队列 → offer=CAS设t.next+CAS推进tail(可能滞后自修复)→ poll=CAS设item为null+推进head → 比LinkedBlockingQueue快(CAS vs Lock)→ 但无界不阻塞 → size()是O(n)近似值不要用来判空）

**追问3：** BlockingQueue 家族有哪些成员？它们各自适合什么场景？

> 你回答...（提示：BlockingQueue 家族 / ①ArrayBlockingQueue → 有界数组 → 一把锁(put/take共用)→ 公平/非公平 → 生产者消费者 → 吞吐量中等 ②LinkedBlockingQueue → 可选有界链表 → 两把锁(put锁+take锁)→ 两端各一 → 高并发吞吐量高(双锁并行)→ 默认Integer.MAX_VALUE(无界)→ 生产建议设容量 → Executors.newFixedThreadPool()用它 → 容易OOM ③SynchronousQueue → 容量为0 → 每个put必须等一个take → 直接传递 → 不存储 → Executors.newCachedThreadPool()用它 → 适合高吞吐直接传递 ④PriorityBlockingQueue → 无界 → 堆 → 元素有优先级 → 任务调度(优先级高的先执行)⑤DelayQueue → 无界 → 元素过期才能取 → 延迟任务/定时任务 → 缓存过期/订单超时关闭 ⑥LinkedTransferQueue → 无界 → transfer()直接传递(不等入队)→ 比SynchronousQueue更灵活 → 高性能场景 ⑦LinkedBlockingDeque → 双端 → 可以两端put/take → 工作窃取(Work Stealing)→ ForkJoinPool用 / 线程池和阻塞队列的关系：①newFixedThreadPool → LinkedBlockingQueue(无界)→ 队列无界 → 任务堆积 → OOM风险 → 阿里规范禁止用Executors ②newCachedThreadPool → SynchronousQueue(0容量)→ 任务直接传递给线程 → 没有线程就新建 → 最大线程Integer.MAX_VALUE → OOM风险 ③newSingleThreadExecutor → LinkedBlockingQueue(无界)→ 单线程 → 任务堆积 → OOM ④newScheduledThreadPool → DelayQueue(延迟队列)→ 定时任务 → 延迟执行 / 实际选型：①生产者-消费者 → LinkedBlockingQueue(有界)②直接传递/不留存 → SynchronousQueue ③优先级任务 → PriorityBlockingQueue ④延迟任务 → DelayQueue ⑤高并发无阻塞 → ConcurrentLinkedQueue(不用BlockingQueue) / 面试重点：ArrayBQ(有界/一锁/中吞吐) → LinkedBQ(有界/两锁/高吞吐/FixedThreadPool用) → SynchronousQ(0容量/直接传递/CachedThreadPool用) → PriorityBQ(堆/优先级) → DelayQ(延迟/定时) → 选型看场景）

---

# 二面（30分钟）

## 话题六：MySQL 分库分表实战（10分钟）

**面试官：你的金融系统数据量大了之后怎么分库分表？分片键怎么选？跨库查询怎么处理？**

> 你回答...

**追问1：** 先说说什么时候该分库分表？垂直拆分和水平拆分有什么区别？

> 你回答...（提示：分库分表时机和方式 / 什么时候分：①单表数据量 > 1000万 → B+树索引3-4层 → 查询变慢 → 但不是绝对 → 如果索引设计好 → 5000万也能扛 ②单库数据量 > 100GB → 备份恢复慢 → DDL变更锁表时间长 ③并发量 > 单库上限 → MySQL单机QPS约5000-10000(读)/2000-5000(写)→ 超过就要拆 ④但分库分表是最后手段 → 先优化：索引优化/SQL优化/缓存/读写分离/归档历史数据 → 都试了还不行 → 再分 / 垂直拆分：①垂直分库 → 按业务拆 → 用户库/订单库/支付库 → 不同业务放不同库 → 减少单库压力/耦合 → 微服务天然对应 ②垂直分表 → 按字段拆 → 把不常用的字段拆到副表 → `order(id, no, amount, status)` + `order_detail(id, content, remark, image)` → 减少单行大小 → 缓存更多行 → 但跨表查询要JOIN ③本质 → 垂直 = 按维度拆 → 库按业务/表按字段 / 水平拆分：①水平分库 → 同一个表的数据 → 按规则分散到多个库 → 如 order_db_0/order_db_1 → 每个库都有 order 表 → 但存不同的行 ②水平分表 → 同一个库 → 把一个大表拆成多个小表 → order_0/order_1/order_2 → 每个表存不同的行 ③本质 → 水平 = 按行拆 → 数据分散到多个物理节点 → 解决单表数据量过大 / 垂直+水平组合：①先垂直分库(按业务)→ 再水平分表(按数据量)→ 如 payment_db → payment_0/payment_1/... → 每个payment表存一部分支付记录 / 面试重点：先优化(索引/缓存/读写分离/归档)→不行再分 → 垂直=按业务拆库/按字段拆表 → 水平=按行拆到多库多表 → 实际先垂直再水平）

**追问2：** 水平分表怎么选分片键？有哪些分片策略？各有什么优缺点？

> 你回答...（提示：分片键和策略 / 分片键选择原则：①数据分布均匀 → 每个分片数据量相近 → 不能一个分片90%数据 → 没意义 ②查询能定位 → 大部分查询带分片键 → 直接路由到对应分片 → 不用广播(查所有分片)→ 性能好 ③避免热点 → 不能所有请求集中到一个分片 / 常见分片策略：①范围分片(Range)→ 按ID范围 → 0-1000万分片1 → 1000万-2000万分片2 → 优点：范围查询友好(查ID>500万 → 只查分片1+2)→ 缺点：热点(最新数据在最右分片 → 写入集中)②Hash分片 → hash(分片键) % N → 如 hash(user_id) % 4 → 优点：均匀分布 → 缺点：范围查询差(查所有分片)→ 扩容麻烦(N变了 → 所有数据要重新hash → 迁移)③一致性Hash → 和Day48讲的一样 → 节点变化只影响相邻区间 → 虚拟节点解决倾斜 → 但范围查询差 ④按日期分片 → 按月/日 → 如 payment_202607 → 优点：按时间查询直接定位 → 归档方便(直接删旧表/移到归档库)→ 缺点：当月数据可能热点 ⑤查找表(Routing Table)→ 单独一张表记录 `user_id → shard` → 优点：灵活 → 缺点：查找表是瓶颈 → 要缓存 / 金融系统实际选型：①用户ID → hash(user_id) % N → 用户数据均匀分布 → 查询带user_id直接路由 ②订单ID → 如果用雪花算法 → ID里有机器ID → 可以用ID取模 → 但范围查询差 ③时间 → 交易流水按月分表 → 查询按月定位 → 归档方便 → 但跨月查询要查多表 / 分片键不带在查询中的问题：①如分片键是 user_id → 但查询是 `WHERE phone = '138xxx'` → 没有user_id → 不知道路由到哪个分片 → 必须广播(查所有分片)→ 合并结果 → 性能差 ②解决 → 建立映射表 `phone → user_id` → 先查映射 → 拿到user_id → 再路由 → 多一次查询 ③或 → 基因法 → 把user_id的一部分"基因"嵌入到订单ID → 如 `order_id = timestamp + userId后4位 + sequence` → 查订单时从order_id提取user_id基因 → 直接路由 → 不用查映射表 / 面试重点：分片键=数据均匀+查询带分片键+避免热点 → 策略=范围(范围友好但热点)/Hash(均匀但扩容难)/日期(按时间归档)/查找表 → 不带分片键的查询要广播或映射表或基因法）

**追问3：** 分库分表后，跨库 JOIN、聚合统计、分页查询怎么解决？

> 你回答...（提示：分库分表后的核心难题 / 跨库 JOIN：①问题 → 订单库分4个分片 → 用户库分2个分片 → `SELECT * FROM order o JOIN user u ON o.user_id = u.id` → 订单和用户在不同库 → 无法JOIN ②绑定表(Binding Table)→ order 和 user 都用 user_id 分片 → ShardingSphere 配置绑定关系 → 同一个 user_id 的 order 和 user 在同一个分片 → JOIN变成单库JOIN → ③广播表(Broadcast Table)→ 小表(如配置表/字典表)→ 每个分片都存一份 → JOIN时本地JOIN → 但更新要同步所有分片 ④应用层JOIN → 先查订单 → 拿到user_id → 再查用户 → 代码里组装 → 多一次查询 ⑤宽表/汇总表 → 用Canal监听binlog → 把多表数据聚合到一张宽表 → 查询直接查宽表 → 但有延迟(最终一致)⑥ES → 把数据同步到ES → 用ES做复杂查询/JOIN → DB只做简单CRUD / 聚合统计：①问题 → `SELECT COUNT(*) FROM order WHERE create_time > '2026-07-01'` → 订单分4个分片 → 每个分片COUNT → 再加起来 ②简单聚合(COUNT/SUM/MAX/MIN)→ 各分片聚合 → 合并结果 → 但AVG不能直接合并(要算权重)③复杂聚合(GROUP BY)→ 各分片GROUP BY → 合并 → 可能重复key → 再聚合一次 → 性能差 ④预计算 → 定时任务 → 每天凌晨把各分片数据汇总到统计表 → 查询直接查统计表 / 分页查询：①问题 → `SELECT * FROM order ORDER BY create_time LIMIT 1000000, 10` → 分4个分片 → 每个分片取100万+10条 → 合并4×(100万+10)→ 排序 → 取10条 → 内存爆炸 ②禁止跨分页 → 业务限制 → 只能翻前100页 → 超过 → 让用户缩小范围(选日期/选条件)③全局视图 → 每个分片取 offset+limit → 内存排序 → 取10条 → 数据量小还可以 → 大了不行 ④禁止跳页 → 只能下一页/上一页 → 用游标 → `WHERE id > last_id ORDER BY id LIMIT 10` → 每次用上一页最后一条的ID → 不需要offset ⑤汇总表 → 热门查询预计算 → 存到汇总表/Redis / 面试重点：跨库JOIN→绑定表(同分片键)/广播表(小表)/应用层组装/宽表(Canal binlog)/ES → 聚合→各分片聚合后合并(注意AVG)→预计算汇总表 → 分页→禁止跨分页/游标分页(id>last_id)/预计算）

---

## 话题七：核心设计题 - 微信红包系统（20分钟）

**面试官：最后做一个经典设计题。微信红包——除夕夜峰值 QPS 几十亿，你要设计一个红包系统。发红包、抢红包、拆红包、红包记录查询，你怎么设计？**

> 你回答...

**追问1：** 先说说整体架构。发红包和抢红包的核心流程是什么？

> 你回答...（提示：微信红包系统架构 / 核心流程：①发红包 → 用户发100块/10个 → 微信支付扣100块 → 生成红包记录(总金额/总个数/已抢数)→ 红包数据写DB+Redis ②抢红包 → 用户点击 → Redis DECR扣减剩余个数 → 成功 → 拆红包 → 随机金额 → 更新红包记录(已抢+1/剩余金额-随机金额)→ 写入领取记录 → 微信支付把钱转到领取人零钱 ③查询 → 红包详情 → 已抢列表 → 金额/时间/领取人 / 架构分层：①接入层 → Nginx/L5(腾讯内部负载)→ 微信接入层 ②逻辑层 → 红包服务(发/抢/拆/查)→ 异步写入MQ ③存储层 → DB(分库分表)→ Redis(缓存/预扣减)→ MQ(异步削峰)④资金层 → 微信支付系统 → 扣款/入账 / 核心数据表：①红包表(red_packet)→ id/发送者/总金额/总个数/剩余个数/剩余金额/状态(未抢完/已抢完/已过期)②领取记录表(red_packet_record)→ id/红包id/领取人/金额/时间 ③分库分表 → 按红包id分片 → 同一个红包的记录在同一个分片 / 面试重点：发红包=支付扣款+写DB+Redis预存 → 抢红包=Redis DECR原子扣减+抢成功拆红包 → 拆红包=随机金额+更新记录+转账入账 → 查询=红包详情+领取记录）

**追问2：** 抢红包的并发量巨大。你怎么保证不超发？如果 10 个红包，100 万人同时抢，怎么处理？

> 你回答...（提示：防超发设计 / 核心问题：100万人抢10个 → 只有10个人成功 → 999990人失败 → 但请求全打到DB → DB撑不住 / 方案一：Redis 预扣减（核心方案）①发红包时 → Redis预存 → `SET red:{id}:count 10` + `SET red:{id}:amount 10000`(分)②抢红包 → `DECR red:{id}:count` → 原子操作 → 返回值 > 0 → 抢到了 → 返回值 ≤ 0 → 没抢到(直接返回"手慢了")③DECR是原子操作 → Redis单线程 → 不会超发 → 100万DECR → 只有10个返回>0 → 其余返回≤0 → 快速失败 ④抢到的 → 异步拆红包 → MQ → 消费者计算随机金额 → 更新DB → 转账 ⑤没抢到的 → 直接返回 → 不查DB → 不写DB → 保护DB / 方案二：MQ削峰 ①所有抢红包请求 → 先入MQ → 消费者串行处理 → 自然限流 → 但延迟高(用户等不了)②实际 → Redis DECR先过滤 → 抢到的才入MQ → 99%的失败请求被Redis挡住 → MQ只处理0.01%的成功请求 / 防刷：①频率限制 → 同一个用户同一红包只能抢一次 → Redis `SET red:{id}:user:{userId} NX EX 86400` → 防重复抢 ②设备指纹 → 防外挂/脚本 → 设备ID+用户ID+IP → 综合判断 ③行为分析 → 正常用户点击间隔 > 200ms → 脚本 < 50ms → 识别拦截 / 为什么不用DB扣减：①DB → `UPDATE red_packet SET count = count - 1 WHERE id = ? AND count > 0` → 行锁 → 串行 → 100万并发 → 一个一个执行 → 死慢 ②Redis DECR → 单线程内存操作 → 10万QPS轻松 → 100万请求1秒处理完 → 快速失败99% / 面试重点：防超发=Redis DECR原子扣减(内存单线程不超发)→ 100万只10个成功 → 成功的入MQ异步拆红包 → 失败的直接返回不碰DB → Redis挡住99%请求保护DB）

**追问3：** 拆红包的金额怎么随机？如果第一个就拆走了99块，后面的人体验很差，怎么保证公平？

> 你回答...（提示：红包金额随机算法 / 方案一：二倍均值法（微信实际用）①剩余N个人 → 剩余M分钱 → 每人随机范围 [1, M/N × 2] ②即 → `random(1, M/N × 2)` → 不超过平均值的2倍 → 不会有人抢太多 ③最后一个 → 剩余全部 ④示例 → 100块10个人 → 第一个 [1, 20] → 假设抢15 → 剩85/9个人 → 第二个 [1, 18.8] → ... → 最后一个拿剩余 ⑤数学期望 → 每个人期望M/N → 均值 → 公平 ⑥但每次随机 → 实际金额有波动 → 有趣 → 微信红包的"惊喜感" / 方案二：线段切割法 ①100块 → 画一条线段 → 随机切9刀 → 分成10段 → 每段一个红包 ②问题 → 可能切出0 → 要限制最小值 → 复杂 ③不如二倍均值法均匀 / 为什么不用正态分布：①正态分布 → 金额集中在均值附近 → 波动小 → 不有趣 ②二倍均值法 → 均匀分布但上限2倍 → 既有波动又不太极端 → 平衡公平和趣味 / 精度问题：①金额用"分"做单位 → `int` → 不用double → 避免浮点精度 ②`random.nextInt(max - min + 1) + min` → 范围[min, max] → 金额以分为单位 → `randomAmount = random.nextInt(2 * remainingAmount / remainingCount - 1) + 1` ③最后一个 → `remainingAmount` → 剩余全部 / 预先生成 vs 实时计算：①预先生成 → 发红包时算好10个金额 → 存Redis List → 抢到后 LPOP → 取出金额 ②实时计算 → 每次拆红包时算 → 但并发时 → 多人同时算 → 可能不一致 → 要加锁 → 不如预先生成 ③微信 → 预先生成(猜测)→ 发红包时算好 → 存起来 → 抢到后取出 → 性能好 / 面试重点：二倍均值法=每人随机[1, 剩余均值×2]→ 期望=均值 → 公平+有波动+有趣 → 金额用"分"int不用double → 预先生成存Redis List抢时LPOP → 性能好）

**追问4：** 红包24小时没抢完，剩下的钱要退回。这个退回怎么实现？

> 你回答...（提示：红包过期退款 / 定时任务方案：①XXL-JOB → 每隔1分钟扫描 → `WHERE status = '未抢完' AND expire_time < NOW()` → 找到过期红包 ②问题 → 红包量大 → 扫描慢 → 分片并行 ③退回 → 剩余金额 → 微信支付退款 → 更新红包状态为"已退回" / 延迟队列方案：①发红包时 → 投递延迟消息到MQ → 24小时后消费 ②消费者收到 → 检查红包状态 → 未抢完 → 退回 → 已抢完 → 忽略 ③RocketMQ延迟消息(18个固定级别)→ 或时间轮 → 精确到期 ④比定时任务好 → 不需要扫描 → 到期精确触发 / 退回流程：①查红包 → 剩余金额 → 退款到发送者零钱 ②更新红包状态 → 已退回 ③写退款记录 ④如果退款失败 → 重试 → 超过次数 → 告警 → 人工处理 / 资金安全：①退回前 → 再次确认红包状态 → 防止并发(有人在抢的同时退回)②用状态机 → 只有"未抢完"才能退回 → "已退回"的不能再退 ③加分布式锁 → `SETNX red:{id}:refund NX` → 防重复退回 / 面试重点：定时任务扫描过期红包+分片并行 → 或延迟队列精确触发 → 退回=查剩余+退款+更新状态+退款记录 → 资金安全=状态机+分布式锁防重复退回）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| HTTP/HTTPS 协议（HTTP问题/TLS 1.2四次握手/对称+非对称组合/证书链验证/证书固定） | 能讲清 / 讲不全 / 不会★ | |
| Dubbo RPC 原理（架构角色/Feign对比/集群容错6种/负载均衡/SPI自适应扩展/调用链路） | 能讲清 / 讲不全 / 不会★ | |
| Java 内存区域与 OOM（堆/栈/方法区/元空间/直接内存/OOM排查/String.intern） | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（阻塞队列ReentrantLock+Condition/环形数组/优先级阻塞队列思路） | 能讲清 / 讲不全 / 不会★ | |
| Java 并发容器（CopyOnWriteArrayList写时复制/ConcurrentLinkedQueue CAS无锁/BlockingQueue家族选型） | 能讲清 / 讲不全 / 不会★ | |
| MySQL 分库分表（垂直vs水平/分片键选择/范围Hash日期策略/跨库JOIN绑定表广播表/聚合/分页游标） | 能讲清 / 讲不全 / 不会★ | |
| 微信红包系统设计（发/抢/拆/查/Redis DECR防超发/二倍均值法/延迟队列退回） | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **HTTP/HTTPS**：HTTP=明文+无身份验证+无完整性校验 → HTTPS=HTTP+TLS(加密+证书+MAC)。**TLS 1.2 四次握手**：ClientHello(客户端随机数+加密套件) → ServerHello(服务端随机数)+Certificate(服务器公钥) → ClientKeyExchange(Pre-Master用公钥加密) → 双方用 Client Random + Server Random + Pre-Master 生成 Session Key → ChangeCipherSpec + Finished → 后续对称加密通信。**非对称加密交换密钥(RSA慢) + 对称加密传输数据(AES快)**。证书验证 = CA公钥验签 + 域名匹配 + 有效期 + 吊销检查。证书链 = 终端 → 中间 → 根(预装信任)
> 2. **Dubbo RPC**：Provider注册 + Consumer订阅 + Registry推送 + TCP长连接 + Hessian2序列化 → 比Feign(HTTP+JSON)快3-5倍。集群容错：Failover(默认/重试2次/适合读幂等) vs Failfast(快速失败/非幂等写) vs Forking(并行取最快)。负载均衡：Random默认/LeastActive最快/ConsistentHash有状态。**Dubbo SPI** = key=实现按需加载 + @Adaptive运行时动态选择 + Wrapper自动AOP + setter注入IOC → 所有组件可扩展
> 3. **Java 内存区域**：线程私有 = PC(行号不OOM) + VM栈(栈帧SOE递归) + 本地方法栈。线程共享 = 堆(对象GC) + 方法区/元空间(JDK8移本地内存/类信息常量池) + 直接内存(NIO)。**OOM排查**：堆OOM→MAT分析Leak Suspects+Path to GC Roots → 元空间OOM→jmap -clstats看ClassLoader → 栈SOE→jstack看递归 → 线程OOM→jstack数线程 → 直接内存OOM→NativeMemoryTracking+Netty ResourceLeakDetector。**String.intern()** JDK6永久代拷贝 vs JDK7+堆中存引用
> 4. **阻塞队列**：ReentrantLock + 两个Condition(notFull/notEmpty)精准唤醒 → while防虚假唤醒 → 环形数组 → 这就是ArrayBlockingQueue核心实现。**CopyOnWriteArrayList** = 读无锁(volatile数组)/写加锁复制新数组替换 → 读多写少(配置/监听器)→ 弱一致性。**ConcurrentLinkedQueue** = CAS无锁(Michael-Scott算法)→ 比锁快 → 但无界不阻塞 → size()是O(n)近似值。BlockingQueue家族：ArrayBQ(有界/一锁)→LinkedBQ(两锁/高吞吐/FixedThreadPool用)→SynchronousQ(0容量/CachedThreadPool用)→DelayQ(延迟定时)
> 5. **MySQL 分库分表**：先优化(索引/缓存/读写分离/归档)→ 不行再分。垂直=按业务拆库/按字段拆表。水平=按行拆到多库多表。分片键 = 数据均匀 + 查询带分片键 + 避免热点。跨库JOIN → 绑定表(同分片键) / 广播表(小表) / 应用层组装 / 宽表(Canal binlog) / ES。分页 → 禁止跨分页 / 游标分页(id > last_id) / 预计算
> 6. **微信红包**：发红包=支付扣款+写DB+Redis预存(count+amount) → 抢红包=**Redis DECR原子扣减**(100万只10个成功/快速失败99%不碰DB)→ 成功入MQ异步拆 → 拆红包=**二倍均值法**随机[1, 剩余均值×2](公平+有趣/金额用分不用double)→ 过期退回=延迟队列24h触发+状态机+分布式锁防重复
