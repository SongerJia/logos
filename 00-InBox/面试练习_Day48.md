# 面试模拟 - Day 48

> 日期：2026-07-18（周六） | 模拟岗位：海康威视（杭州总部）- 金融科技事业部 - Java开发工程师
> 建议时长：85分钟（一面55分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day48，模拟海康威视——杭州本土科技巨头，全球安防行业龙头。海康金融科技事业部为银行、证券提供智能安防、智慧网点、视频AI分析等解决方案。和之前做的金融软件公司不同，海康面试更看重计算机基础功底（网络/操作系统/数据结构与算法），技术原理要求扎实但不一定追问太多金融业务细节。今天引入 TCP/IP 三次握手四次挥手、Java IO 模型(BIO/NIO/AIO)、K8s 基础与容器编排、一致性 Hash 算法、设计模式在源码中的应用等全新话题。

---

# 一面（55分钟）

## 话题一：TCP/IP 三次握手四次挥手（12分钟）

**面试官：你是做后端的，网络基础得扎实。TCP 建立连接为什么是三次握手，不是两次或者四次？**

> 你回答...

**追问1：** 三次握手的具体过程讲一下。SYN、ACK 这些标志位分别是什么意思？

> 你回答...（提示：第一次握手：客户端发送 SYN=1, seq=x → 进入 SYN_SENT 状态 / 第二次握手：服务端收到 SYN → 回复 SYN=1, ACK=1, seq=y, ack=x+1 → 进入 SYN_RCVD 状态 / 第三次握手：客户端收到 SYN+ACK → 发送 ACK=1, seq=x+1, ack=y+1 → 进入 ESTABLISHED 状态 / 服务端收到 ACK → 进入 ESTABLISHED / SYN = Synchronize Sequence Numbers 同步序列号 / ACK = Acknowledgment 确认 / seq = 自己的序列号 / ack = 确认收到对方的序列号+1 / 三次握手的核心目的：双方确认收发能力都正常 → 第一次：服务端确认客户端能发 → 第二次：客户端确认服务端能收能发 → 第三次：服务端确认客户端能收）

**追问2：** 为什么不是两次握手？两次能不能建立连接？

> 你回答...（提示：两次握手的问题：无法防止历史连接（已失效的 SYN）/ 场景：客户端发送 SYN1 → 网络延迟 → 超时 → 客户端重发 SYN2 → 建立连接 → 传输完毕 → 关连接 → 此时 SYN1 到达服务端 → 服务端以为要建立新连接 → 回复 SYN+ACK → 等待客户端数据 → 但客户端根本没想连 → 服务端一直等 → 浪费资源 / 三次握手：服务端回复 SYN+ACK → 等客户端第三次 ACK → 如果客户端发现不是自己发起的连接 → 发 RST 中止 → 避免历史连接 / 另一个原因：两次握手只能确认客户端→服务端方向的收发能力 → 不能确认服务端→客户端方向 → 三次才能双向确认 / 四次也行但没必要 → 三次已经够了 → 多一次浪费）

**追问3：** 四次挥手讲一下。为什么断开连接要四次，不是三次？

> 你回答...（提示：四次挥手：①客户端发送 FIN=1, seq=u → 进入 FIN_WAIT_1 ②服务端收到 FIN → 回复 ACK=1, ack=u+1 → 进入 CLOSE_WAIT ③服务端处理完未发送的数据 → 发送 FIN=1, seq=w → 进入 LAST_ACK ④客户端收到 FIN → 回复 ACK=1, ack=w+1 → 进入 TIME_WAIT → 等待 2MSL 后关闭 / 为什么四次：TCP 是全双工 → 两个方向各关一次 / 第一次 FIN：客户端说"我没数据了" → 但服务端可能还有数据要发 / 第二次 ACK：服务端说"我知道你没数据了" → 但服务端还可以继续发 / 第三次 FIN：服务端数据发完了 → 说"我也没数据了" / 第四次 ACK：客户端说"收到" / 三次不行：第二步和第三步不能合并 → 因为服务端收到客户端 FIN 后 → 可能还有数据没发完 → 先回 ACK → 等数据发完再发 FIN → 所以是两步 / 什么时候可以三次：服务端收到 FIN 时刚好没有数据要发 → ACK 和 FIN 合并发送 → 变成三次 → 这是特殊情况不是常态）

**追问4：** TIME_WAIT 状态为什么要等 2MSL？MSL 是什么？

> 你回答...（提示：MSL = Maximum Segment Lifetime → 报文最大生存时间 → Linux 默认 30 秒 / 2MSL = 60 秒 → TIME_WAIT 持续时间 / 两个原因：①确保最后一个 ACK 到达对方 → 如果 ACK 丢失 → 对方超时重发 FIN → 重新发 ACK → 如果不等就关了 → 对方一直收不到 ACK → 重发 FIN → 无效 → 等待 2MSL → 如果对方重发 FIN 到了 → 可以重新发 ACK ②防止历史报文影响新连接 → 旧连接的报文在网络中最多存活 MSL → 等 2MSL → 旧报文一定消失 → 新连接不会收到旧报文 / TIME_WAIT 问题：高并发短连接 → 大量 TIME_WAIT → 端口耗尽 → 解决：长连接 / SO_REUSEADDR / 调小 tcp_fin_timeout）

**追问5：** 你能解释一下 TCP 粘包/拆包吗？怎么解决？

> 你回答...（提示：TCP 是面向字节流的协议 → 没有消息边界的概念 → 发送方连续发两条消息 → 接收方可能一次读到两条粘在一起（粘包）→ 或者一条消息被拆成两次读（拆包）/ 原因：①应用层写入速度 > socket 缓冲区大小 → 拆包 ②接收方读取速度 < 发送方写入速度 → 粘包 ③MSS 最大报文段长度限制 → 大包被拆 / 解决方案：①消息定长 → 每条消息固定长度 → 不足补齐 ②用分隔符 → 如 \n → 按分隔符切分 ③消息头包含长度字段 → 先读长度 → 再按长度读消息体 → 最常用 / Netty 提供了现成解码器：FixedLengthFrameDecoder / LineBasedFrameDecoder / LengthFieldBasedFrameDecoder / LengthFieldBasedFrameDecoder 最常用 → 消息头放消息体长度）

**追问6：** TCP 和 UDP 的区别？什么场景用 UDP？

> 你回答...（提示：TCP：面向连接 → 可靠传输 → 字节流 → 有序 → 有流量控制/拥塞控制 → 开销大 → HTTP/FTP/SMTP / UDP：无连接 → 不可靠 → 数据报 → 无序 → 无流量控制 → 开销小 → 速度快 / TCP 三次握手有延迟 → UDP 不需要 → 实时性要求高用 UDP / UDP 场景：①DNS 查询 → 一次请求一次响应 → 不需要建连接 ②视频/语音通话 → 实时性 > 可靠性 → 丢几帧不影响 → WebRTC ②QUIC（HTTP/3 底层）→ UDP 之上实现可靠性 → Google 开发 → 解决 TCP 队头阻塞 ③游戏同步 → 实时位置更新 → 丢包没关系 / 面试高频对比：TCP 重传机制（超时重传 + 快速重传）/ UDP 不重传）

---

## 话题二：Java IO 模型 BIO/NIO/AIO（10分钟）

**面试官：Java 的 IO 模型你了解吗？BIO、NIO、AIO 有什么区别？**

> 你回答...

**追问1：** BIO 是什么？为什么 BIO 在高并发下性能差？

> 你回答...（提示：BIO = Blocking IO → 同步阻塞 IO / 传统 java.io 包 → ServerSocket.accept() 阻塞 → InputStream.read() 阻塞 / 一个连接一个线程 → 连接不做事情也占着线程 → 线程资源浪费 / 高并发问题：①每个连接一个线程 → 1万连接1万线程 → 线程切换开销大 → 线程栈默认 1MB → 1万连接 = 10GB 内存 ②大部分连接大部分时间在等待 → 线程都在阻塞 → 真正干活的少 / BIO 适合连接数少且固定的场景 → 传统 C/S 架构 → 不适合高并发）

**追问2：** NIO 是怎么解决 BIO 的问题的？核心组件有哪些？

> 你回答...（提示：NIO = Non-blocking IO → 同步非阻塞 IO / java.nio 包 → 核心：Channel + Buffer + Selector / Channel：双向通道 → 可读可写 → 替代 Stream 的单向流 / Buffer：缓冲区 → 数据先读到 Buffer → 不直接操作 Channel → flip() 切换读写模式 → position/limit/capacity 三个指针 / Selector：多路复用器 → 一个线程管理多个 Channel → Channel 注册到 Selector → Selector.select() 返回就绪的 Channel → 只处理有数据的 Channel → 没数据的不管 / 核心优势：一个线程处理多个连接 → 1个线程管理几万连接 → 不需要每连接一线程 / 工作流程：①ServerSocketChannel 注册到 Selector → 关注 OP_ACCEPT ②Selector.select() → 有连接来了 → accept() 得到 SocketChannel → 注册 OP_READ ③有数据可读 → read() → 处理 → 注册 OP_WRITE 写回 / select() 是阻塞的（可设超时）→ 但阻塞时线程可以做别的 → epoll_wait 底层 / NIO 适合连接数多但连接空闲时间长的场景 → 聊天/推送/IM）

**追问3：** Selector 底层用的什么系统调用？select、poll、epoll 的区别？

> 你回答...（提示：Linux 下 Selector 底层用 epoll / select：①1024 个 fd 限制 ②每次调用遍历所有 fd → O(n) ③fd 从用户态拷贝到内核态 → 开销 ④返回后需要遍历找出就绪的 fd / poll：去掉 1024 限制 → 但其他问题一样 / epoll：①没有 fd 数量限制 ②事件驱动 → 只有就绪的 fd 回调 → O(1) 查找就绪 fd ③fd 只在注册时拷贝一次 → 不每次拷贝 ④支持水平触发(LT)和边缘触发(ET) / epoll 三步：epoll_create() → epoll_ctl() 注册 fd → epoll_wait() 等待就绪 / epoll 为什么高效：内核维护红黑树存所有 fd + 就绪列表存就绪 fd → epoll_wait 直接读就绪列表 → 不遍历 / Java NIO 在 Linux 自动用 epoll → Windows 用 select → 所以 Java NIO 在 Linux 性能更好 / Netty 封装了 NIO → 解决了 epoll 空轮询 bug（Java NIO 的 epoll bug → select() 不阻塞 → CPU 100% → Netty 重建 Selector 解决））

**追问4：** AIO 是什么？为什么 Java AIO 在 Linux 上没有普及？

> 你回答...（提示：AIO = Asynchronous IO → 异步非阻塞 IO / NIO 是同步非阻塞 → 调用 read() 还是得自己读数据 → 只是能知道什么时候有数据可读 / AIO → 调用 read() → 系统读完数据后回调通知 → 用户线程完全不用管 → 真正的异步 / Windows IOCP 是真正的 AIO → 系统线程池完成 IO → 回调通知 / Linux AIO：①POSIX AIO（aio_read）→ 用户态实现 → 本质还是用线程模拟 ②io_uring → Linux 5.1+ 新特性 → 真正的内核级异步 IO → 但 Java 标准库不支持 / Java AIO（NIO.2 AsynchronousChannel）：Windows 上用 IOCP → 性能好 / Linux 上用 epoll 模拟 → 没有比 NIO 更好 / 所以 Linux 上 AIO 没有普及 → 主流还是 NIO + Netty / Netty 曾经支持 AIO → 但 Linux 上和 NIO 一样 → 删除了 AIO 支持 → 只保留 NIO）

**追问5：** Netty 的 IO 模型和 Java 原生 NIO 有什么区别？Netty 做了哪些优化？

> 你回答...（提示：Netty 基于 NIO → 但做了大量优化 / ①Boss/Worker 线程模型 → Boss 负责接受连接 → Worker 负责读写 → 职责分离 / ②EventLoop → 一个 EventLoop 管一组 Channel → 一个 Channel 只绑定一个 EventLoop → 一个 EventLoop 一个线程 → 无锁 / ③无锁化串行设计 → 同一个 Channel 的所有操作都在同一个线程 → 不需要加锁 → 避免竞争 / ④ByteBuf → 替代 ByteBuffer → 池化 → 减少 GC → 支持零拷贝（CompositeByteBuf 合并多个 Buffer 不拷贝）/ ⑤解决 epoll 空轮询 bug → 检测到空轮询 → 重建 Selector / ⑥Pipeline 责任链 → ChannelHandler 链式处理 → 编解码/业务逻辑解耦 / ⑦内存池 → PooledByteBufAllocator → 对象复用 → 减少 GC / Java 原生 NIO → 直接用 → 要自己处理以上所有问题 → 容易出错 / 生产环境基本都用 Netty 而不是直接用 NIO）

---

## 话题三：手写代码 - 快速排序（8分钟）

**面试官：快速排序写一下。说下你的思路再写。**

你在纸上/白板上写代码...

**追问1：** 快速排序的时间复杂度是多少？最坏情况是什么？怎么避免？

> 你回答...（提示：平均时间 O(n log n) → 最坏 O(n²) → 每次 partition 选到最大或最小值 → 一边为空 / 最坏场景：①已排序数组 → 每次选第一个元素做 pivot → 所有元素都在一边 → 退化成 O(n²) ②所有元素相同 → 也是 O(n²) / 避免方法：①随机选 pivot → 随机化避免恶意输入 ②三数取中法 → 取第一个、中间、最后一个的中位数做 pivot ③小数组用插入排序 → 元素少于 10-15 个时插入排序更快 → Java Arrays.sort() 就是这么做的 / 空间复杂度 O(log n) → 递归栈深度 → 最坏 O(n)）

**追问2：** partition 过程详细讲一下。你是怎么选 pivot 的？

> 你回答...（提示：partition 核心目标：选一个 pivot → 把数组分成两部分 → 左边都 ≤ pivot → 右边都 > pivot → 返回 pivot 的最终位置 / 两种 partition 方式：①Hoare 分区（双指针对向走）→ 原始版本 → 左指针从左往右找 > pivot → 右指针从右往左找 < pivot → 交换 → 直到指针相遇 ②Lomuto 分区（单指针）→ 选最后一个元素做 pivot → 维护一个分界点 i → 遍历 j 从 0 到 n-2 → 如果 arr[j] < pivot → i++ → 交换 arr[i] 和 arr[j] → 最后交换 arr[i+1] 和 pivot → 返回 i+1 / Lomuto 更容易理解但性能稍差 → 不平衡分区概率更高 / Hoare 交换次数更少 → 更平衡 / 实际代码用 Lomuto 居多 → 因为简单）

**追问3：** 快排和归并排序有什么区别？各自的适用场景？

> 你回答...（提示：快排：①不稳定排序 ②原地排序 O(1) 空间 ③平均 O(n log n) ④最坏 O(n²) ⑤实际中通常最快 → 常数因子小 → 缓存友好（原地操作数据局部性好）→ 大多数库的默认排序 / 归并：①稳定排序 ②需要 O(n) 额外空间 ③始终 O(n log n) → 没有最坏情况 ④适合链表排序（不需要额外空间）→ 适合外部排序（大文件）→ 适合稳定排序需求 / Java Arrays.sort()：基本类型用快排（双轴快排 Dual-Pivot QuickSort）→ 对象用 TimSort（归并+插入排序的混合）→ 因为对象需要稳定排序 / 选择：内存排序用快排 → 稳定排序用归并 → 大数据外部排序用归并）

**追问4：** 双轴快速排序是什么？Java 为什么用它？

> 你回答...（提示：双轴快排 = Dual-Pivot QuickSort → 2009 年 Vladimir Yaroslavskiy 提出 → Java 7 开始使用 / 普通快排：一个 pivot → 分成两部分 / 双轴快排：两个 pivot（P1 < P2）→ 分成三部分：①< P1 ②P1 ≤ x ≤ P2 ③> P2 / 每次分区三部分 → 递归深度更浅 → 比较次数更少 → 实测比单轴快 10-20% / Java Arrays.sort(int[]) 基本类型用双轴快排 / 对象数组用 TimSort → 因为 TimSort 是稳定排序 / 了解即可 → 面试能说出双轴分三区就够）

---

## 话题四：K8s 基础与容器编排（12分钟）

**面试官：你们用 Docker 做容器化了。K8s 了解吗？K8s 解决了什么 Docker 没解决的问题？**

> 你回答...

**追问1：** K8s 的核心组件有哪些？各自做什么？

> 你回答...（提示：K8s = Kubernetes → 容器编排平台 → 管理大规模容器集群 / Docker 的问题：①单机 → 容器跨多台机器需要手动管理 ②没有自动调度 → 哪台机器跑哪个容器 ③没有自愈 → 容器挂了不会自动重启 ④没有自动扩缩容 / K8s 核心组件（控制面 Control Plane）：①API Server → 所有操作的入口 → kubectl 命令通过 API Server → 唯一入口 → 其他组件通过 API Server 通信 ②etcd → 分布式 KV 存储 → 存储集群所有状态 → 类似 ZK → Raft 协议 ③Scheduler → 调度器 → 新 Pod 创建时 → 决定放在哪个 Node → 根据资源/CPU/内存/亲和性 ④Controller Manager → 运行各种控制器 → Deployment Controller / ReplicaSet Controller / Node Controller → 监控状态 → 调谐到期望状态 ⑤Cloud Controller Manager → 和云厂商交互 / 数据面 Node 上：①kubelet → 和 API Server 通信 → 管理本节点 Pod 生命周期 → 启动/停止容器 ②kube-proxy → 网络代理 → 管理 Service 的负载均衡 → iptables/ipvs 规则 ③Container Runtime → 容器运行时 → containerd / CRI-O / Docker（已弃用，K8s 1.24 移除 dockershim））

**追问2：** Pod 是什么？为什么不直接管理容器？

> 你回答...（提示：Pod = K8s 最小调度单位 → 一个或多个紧密耦合的容器 / 为什么不直接管理容器 → ①容器之间需要共享资源 → 共享网络（同一 Pod 内容器共享 IP 和端口）→ 共享存储卷 → localhost 互相访问 ②容器需要作为一个整体调度 → 不应该一个在 Node A 一个在 Node B ③生命周期管理 → 一起创建一起销毁 / Pod 的典型场景：①主容器 + Sidecar → 主容器跑业务 → Sidecar 做日志收集/监控/代理 ②Init Container → 初始化容器 → 先运行做准备工作（如等数据库就绪）→ 完成后主容器才启动 / Pod 是临时的 → IP 会变 → 所以需要 Service 提供固定访问入口 / 一个 Pod 一个 IP → Pod 内容器 localhost 互通 → Pod 之间通过 Service 通信）

**追问3：** Deployment、Service、Ingress 分别是什么？它们的关系？

> 你回答...（提示：Deployment → 管理无状态应用 → 定义 Pod 模板 + 副本数 → 滚动更新/回滚 → 期望3个副本始终运行 → Pod 挂了自动创建新的 / Deployment → ReplicaSet → Pod 三层关系 / Deployment 创建 ReplicaSet → ReplicaSet 创建 Pod / Service → 为一组 Pod 提供固定访问入口 → Pod IP 会变 → Service 提供固定 ClusterIP + DNS 名 → 负载均衡到后端 Pod / Service 类型：ClusterIP（集群内部访问）/ NodePort（暴露端口到节点）/ LoadBalancer（云厂商负载均衡器）/ Ingress → 七层路由 → HTTP 域名/路径路由到不同 Service → 类似 Nginx 反向代理 → 需要部署 Ingress Controller（如 Nginx Ingress）→ Ingress 定义路由规则 / 关系：外部请求 → Ingress（域名路由）→ Service（负载均衡）→ Pod（实际容器）→ 内部应用 / 简化记忆：Deployment 管 Pod 多少个、Service 管 Pod 怎么访问、Ingress 管外部怎么进来）

**追问4：** K8s 的滚动更新是怎么实现的？怎么保证更新过程中不中断服务？

> 你回答...（提示：滚动更新 = Rolling Update → 逐步替换旧 Pod → 不是一次性全部替换 / 过程：①Deployment 创建新 ReplicaSet → 启动1个新 Pod → ②新 Pod 就绪后 → 销毁1个旧 Pod → ③重复直到全部替换 / maxSurge：最多超出期望副本数几个 → 默认 25% → 控制新建速度 / maxUnavailable：最多不可用几个 → 默认 25% → 控制销毁速度 / 就绪检查 readinessProbe：新 Pod 启动后 → 探针检查是否就绪 → 就绪后才加入 Service Endpoints → 流量才进来 → 旧 Pod 才能被销毁 / 三个探针：①readinessProbe → 就绪探针 → 不通过不接流量 ②livenessProbe → 存活探针 → 不通过重启容器 ③startupProbe → 启动探针 → 慢启动应用专用 / 回滚：kubectl rollout undo → 切回旧 ReplicaSet → 也是滚动回滚 / 蓝绿发布/金丝雀发布在 K8s 中也是通过多 Deployment + Service 权重实现）

**追问5：** K8s 的 Service 负载均衡和 Nginx 有什么区别？kube-proxy 怎么工作的？

> 你回答...（提示：Service 负载均衡：四层（TCP/UDP）→ 在内核态工作 → iptables/ipvs 规则 / Nginx 负载均衡：七层（HTTP）→ 在用户态工作 → 功能更强（URL 路由/Header 处理） / kube-proxy 工作模式：①iptables 模式（默认）→ kube-proxy 监听 Service 和 Endpoints 变化 → 写 iptables 规则 → DNAT 转发 → 请求到 ClusterIP → iptables DNAT → 转发到某个 Pod IP → 随机选（rr 策略）②ipvs 模式 → 性能更好 → 大量 Service 时 iptables 规则太多 → 线性查找 → ipvs 用哈希表 → O(1) → 大集群用 ipvs / Service 负载均衡是概率性的 → 不是轮询 → iptables 随机选 → 可能不均匀 / 所以通常 Service + Ingress 两层 → Service 做四层负载 → Ingress（Nginx）做七层路由 / 金丝雀发布用 Ingress 做 → 按 Header/Cookie 路由 → Service 做不了）

---

## 话题五：一致性 Hash 算法与数据分片（13分钟）

**面试官：你们 Redis Cluster 用了 16384 个 hash slot 做分片。但有些场景需要更灵活的分片，比如有状态服务。你了解一致性 Hash 吗？**

> 你回答...

**追问1：** 一致性 Hash 是什么？它解决了什么问题？

> 你回答...（提示：传统 hash 分片：hash(key) % N → N 是节点数 / 问题：节点数变化（加减节点）→ N 变 → 几乎所有 key 的映射都变 → 大量数据迁移 → 缓存雪崩 / 一致性 Hash：把整个 hash 空间组织成一个虚拟的环 → 0 ~ 2³²-1 / 节点也 hash 到环上 → key 也 hash 到环上 → key 顺时针找到的第一个节点就是它的归属节点 / 节点变化时 → 只影响相邻段的数据 → 不是全部 → 迁移量小 / 举例：环上有 NodeA(100), NodeB(300), NodeC(500) → key hash 到 250 → 顺时针找 → NodeB(300) → 归 NodeB / 新增 NodeD(200) → 只影响 100-200 段的 key → 从 NodeB 迁移到 NodeD → 其他不变 / 核心：节点变化只影响相邻区间 → 不全局重分布）

**追问2：** 一致性 Hash 有什么问题？怎么解决？

> 你回答...（提示：问题：数据倾斜 → 节点少时 → hash 在环上分布不均匀 → 某个节点负责的区间特别大 → 大部分 key 都到这个节点 / 解决：虚拟节点（Virtual Node）→ 一个物理节点对应多个虚拟节点 → 均匀分布在环上 → 150-200 个虚拟节点 / 物理节点少时虚拟节点多 → 环上分布均匀 → 数据均匀 / 虚拟节点越多越均匀但管理开销越大 → 150-200 个够用 / Redis Cluster 没用一致性 Hash → 用固定 16384 slot → 更可控 → 每个节点负责一段连续 slot → 扩缩容时迁移 slot 而不是重新 hash / 但一致性 Hash 在：①Memcached 分片 ②负载均衡（Nginx hash 模块）③分布式存储（Cassandra/DynamoDB）④有状态服务路由 中广泛使用 / Java 实现：TreeMap<Long, String> → hash 匃围排序 → tailMap() 找顺时针下一个）

**追问3：** 一致性 Hash 在负载均衡场景怎么用？和轮询有什么区别？

> 你回答...（提示：轮询：请求1→A, 请求2→B, 请求3→C → 轮流分配 → 不关心请求内容 / 一致性 Hash 负载均衡：hash(请求标识) → 映射到环 → 找节点 / 请求标识：用户ID / SessionID / 客户端IP / 适用场景：①Session 粘性 → 同一用户的请求始终到同一节点 → 不需要 Session 共享 → hash(userID) → 同一用户同一节点 ②有状态服务 → 游戏服务器 → 同一玩家路由到同一服务器 ③缓存命中 → 同一 key 路由到同一缓存节点 → 缓存利用率高 / 和轮询区别：轮询不关心内容 → 一致性 Hash 根据内容路由 → 保证同一标识到同一节点 / Nginx 配置：ip_hash → hash 客户端IP → 同一IP到同一后端 → 解决 Session 问题 / hash $request_uri → 同一URL缓存到同一节点 → 提高缓存命中率）

**追问4：** Redis Cluster 为什么不用一致性 Hash 而用 hash slot？

> 你回答...（提示：Redis Cluster 选择 16384 固定 slot 而不是一致性 Hash / 原因：①可控性 → slot 手动分配 → 明确知道每个节点负责哪些 slot → 运维可控 → 一致性 Hash 是自动的 → 难以预测 ②迁移精确 → 迁移时迁移指定 slot → 精确控制 → 一致性 Hash 加节点是迁移一段连续区间 → 但虚拟节点让迁移范围不明确 ③slot 数据结构小 → 16384 bit = 2KB → 每个节点维护一份 slot 映射 → 很小 → Gossip 传输开销小 ④如果用一致性 Hash → 节点信息变化 → 所有节点要更新环 → Gossip 开销大 / slot 迁移过程：源节点标记 slot 正在迁移 → 新请求重定向到目标节点 → 数据逐步迁移 → 完成 → 更新集群 slot 映射 / 一致性 Hash 适合节点动态变化的场景 → Redis Cluster 节点相对固定 → slot 更适合）

**追问5：** 你们实际项目中有用到一致性 Hash 吗？什么场景？

> 你回答...（提示：常见使用场景：①Nginx ip_hash → 同一IP路由到同一后端 → Session 粘性 → 但后端挂了 → 自动切换到下一个 ②Memcached 客户端 → SpyMemcached / XMemcached → 一致性 Hash 分片 → 加减节点时只迁移相邻数据 ③有状态服务路由 → 游戏服务器/聊天服务器 → 同一用户路由到同一服务器 → 减少状态同步 ④分库分表路由 → 按用户ID hash → 分配到不同数据库 → 加库时迁移量小 / 项目中：如果做过分库分表 → 可以说按用户ID一致性Hash分库 → 加节点时只迁移部分用户数据 → 不全量迁移 / 如果没实际用过 → 说"了解原理，在实际项目里用的是 Redis Cluster slot 分片 + Nginx ip_hash Session 粘性，但原理和一致性 Hash 类似"）

---

# 二面（30分钟）

## 话题六：设计模式在 JDK/Spring 源码中的应用（12分钟）

**面试官：你简历上写了"熟悉常用设计模式"。你说说设计模式在 JDK 和 Spring 源码里有哪些应用？举几个你印象最深的例子。**

> 你回答...

**追问1：** 先说说单例模式在 JDK 里的应用。Runtime 类是怎么实现单例的？

> 你回答...（提示：java.lang.Runtime → 饿汉式单例 → private static final Runtime instance = new Runtime() → public static Runtime getRuntime() 返回 / 饿汉式 → 类加载时创建 → 线程安全 → 但不能延迟加载 / 为什么不用 DCL：JDK 核心类 → 越简单越好 → 饿汉式足够 → Runtime 不重 → 启动时创建没问题 / System.gc() 底层就是 Runtime.getRuntime().gc() → 一个 JVM 一个 Runtime / 另外 java.lang.System 也有类似单例设计 → 但 System 全是静态方法 → 不是对象单例 → 是工具类）

**追问2：** 责任链模式在哪里见过？Spring 里有吗？

> 你回答...（提示：责任链 = Chain of Responsibility → 请求沿着链传递 → 每个节点决定处理还是传递 / JDK：①java.util.logging.Logger → 日志级别判断 → 传递给父 Logger ②Throwable.cause → 异常链 → getCause() 传递 / Spring：①SpringMVC DispatcherServlet → HandlerInterceptor 链 → preHandle → 目标方法 → postHandle → afterCompletion → 拦截器链 ②Spring AOP → Advice 链 → @Around/@Before/@After 按顺序执行 → ReflectiveMethodInvocation.proceed() → 责任链传递 ③Spring WebFlux → WebFilter 链 → 和 Gateway 一样 / Netty：ChannelPipeline → ChannelHandler 链 → 入站和出站事件沿链传递 → 最经典的责任链 / 实际项目：①Gateway/过滤器链 → 鉴权→日志→限流→路由 → 责任链 ②审批流 → 不同金额不同审批人 → 责任链 / 责任链的好处：①解耦 → 发送者不需要知道谁处理 ②灵活 → 可以动态增删节点 ③符合开闭原则）

**追问3：** 模板方法模式在哪里？你在项目里用过吗？

> 你回答...（提示：模板方法 = 定义算法骨架 → 子类实现具体步骤 / JDK：①AbstractList → get/add/remove 是抽象的 → ArrayList/LinkedList 各自实现 → 但 indexOf/isEmpty 等在父类实现 ②InputStream → read(byte[], int, int) 是模板方法 → 调用 read() 抽象方法 → 子类 FileInputStream/ByteArrayInputStream 实现 read() ③AbstractQueuedSynchronizer → tryAcquire/tryRelease 是抽象的 → ReentrantLock/Semaphore 各自实现 → acquire/release 在父类 / Spring：①JdbcTemplate → execute() 模板方法 → 打开连接→执行→关闭→异常处理 都在父类 → 子类只需要实现回调 ②RestTemplate / RedisTemplate → 同理 → 模板处理资源管理 → 业务逻辑用回调 ③AbstractApplicationContext.refresh() → 模板方法 → 定义 Spring 容器初始化流程 → 子类可以重写 onRefresh() 等钩子方法 / 项目里：如果有做过类似的 → DAO 层基类 → 公共 CRUD 在基类 → 子类只需要指定实体类和表名 / 模板方法的好处：①代码复用 → 公共逻辑在父类 ②扩展性好 → 子类只改变化的部分 ③控制反转 → 父类控制流程 → 子类实现细节）

**追问4：** 观察者模式在 Spring 里怎么用的？

> 你回答...（提示：观察者 = Subject 状态变化 → 通知所有 Observer / JDK：①java.util.Observable / Observer → 已废弃（Java 9）→ 因为不够灵活 → 推荐用 PropertyChangeListener / Spring：①ApplicationContextEvent → 事件机制 → publishEvent() → ApplicationListener 监听 → 经典观察者 ②@EventListener 注解 → 方法级别监听 → 更简洁 ③ApplicationEventPublisher → 发布事件 → 异步可以用 @Async / Spring 事件流程：①定义事件 extends ApplicationEvent ②定义监听 implements ApplicationListener 或 @EventListener ③发布 context.publishEvent(event) → ④Spring 事件广播器 ApplicationEventMulticaster → 遍历所有监听器 → 调用 onApplicationEvent / 异步事件：@EventListener + @Async → 线程池异步处理 → 不阻塞主流程 / 实际应用：①用户注册成功后发邮件/发短信 → 发事件 → 异步处理 ②状态变更通知 → 订单完成 → 通知库存/积分/通知 / 观察者 vs 发布订阅：观察者 → Subject 直接知道 Observer → 同步通知 / 发布订阅 → 中间有 EventBus/Message Broker → 解耦更彻底 → 异步）

**追问5：** 你能再说一个策略模式在源码里的应用吗？

> 你回答...（提示：策略模式 = 定义一系列算法 → 封装起来 → 可互换 / JDK：①Comparator → Arrays.sort(arr, comparator) → 不同的 comparator 就是不同的策略 → 比较策略可替换 ②ThreadPoolExecutor.RejectedExecutionHandler → 4 种拒绝策略：AbortPolicy(抛异常) / CallerRunsPolicy(调用者执行) / DiscardPolicy(静默丢弃) / DiscardOldestPolicy(丢最老的) → 不同策略不同行为 / Spring：①Resource → 不同资源类型 → ClassPathResource/FileSystemResource/UrlResource → 统一接口不同策略 ②InstantiationStrategy → 对象实例化策略 → SimpleInstantiationStrategy / CglibSubclassingInstantiationStrategy ③@Qualifier → 多个实现时选择策略 / 实际项目：①支付方式选择 → 微信支付/支付宝支付/银行卡支付 → PaymentStrategy 接口 → 不同实现 ②限流策略 → 令牌桶/漏桶/滑动窗口 → 不同策略实现 / 策略模式的好处：①消除 if-else → 用多态替代 ②开闭原则 → 新增策略不改旧代码 ③配合工厂模式 → 工厂创建策略 / 和状态模式区别：策略 → 客户端选择策略 → 策略之间独立 / 状态 → 状态自动转换 → 状态之间有关联）

---

## 话题七：核心设计题 - 金融智能视频监控平台（18分钟）

**面试官：海康给银行做智慧网点解决方案。假设要设计一个金融智能视频监控平台，银行全国有 1 万个网点，每个网点 10-50 个摄像头，视频数据需要实时分析（人脸识别、行为异常检测），并在发现异常时实时告警。你怎么设计这个系统？**

你在纸上画架构图/说思路...

**追问1：** 1万个网点，每个网点几十个摄像头，视频数据量非常大。你是选择把视频传到中心分析，还是在边缘分析？为什么？

> 你回答...（提示：方案对比：①中心分析 → 所有视频传到中心 → 带宽：1万网点 × 30摄像头 × 4Mbps(H.264) = 1.2 Tbps → 不现实 → 带宽成本极高 → 中心计算压力大 ②边缘分析 → 网点部署边缘计算设备（如海康IPC自带AI芯片或边缘NVR）→ 视频本地分析 → 只传结果（告警事件+关键帧）到中心 → 带宽：1万网点 × 偶发告警 = 很小 → 可行 / 选边缘分析 → ①带宽：视频不传 → 只传结构化数据和关键帧 → 带宽降1000倍 ②延迟：本地分析 → 毫秒级响应 → 不受网络影响 ③隐私：视频不出网点 → 合规 ④中心只做：告警聚合/分析/展示/联动 / 架构：边缘AI盒子(人脸/行为检测) → MQ → 中心平台(告警/分析/展示) / 边缘设备选型：海康IPC自带AI → 或华为/英伟达边缘盒子（Jetson）→ 模型下发到边缘设备）

**追问2：** 边缘设备检测到异常（如陌生人闯入、异常行为），需要将告警实时推送到中心。这个消息通道你怎么设计？

> 你回答...（提示：需求：1万网点 → 告警实时 → 高可靠 → 不丢 / 方案：边缘设备 → MQTT → 消息网关 → Kafka → 告警处理服务 / MQTT：轻量级物联网协议 → 适合边缘设备 → 低带宽 → QoS 1 保证至少一次送达 / 为什么不用 HTTP：①HTTP 长轮询 → 延迟高 → 浪费连接 ②HTTP 短连接 → 每次建连开销大 ③边缘设备资源有限 → MQTT 更轻量 / 为什么用 Kafka 做中间层：①MQTT Broker（如 EMQX）做接入 → 大量边缘设备连接 → 转发到 Kafka ②Kafka 做缓冲 → 告警洪峰削峰 → 比如某时段大量网点同时告警 → Kafka 缓冲 → 不压垮下游 ③Kafka 分区并行处理 → 不同网点不同分区 → 并行消费 / 消息格式：Protobuf → 小 → 边缘设备带宽敏感 → 比JSON小3-5倍 / 告警消息：网点ID + 设备ID + 告警类型 + 置信度 + 时间戳 + 关键帧URL → 关键帧存在边缘或OSS → 中心按需拉取）

**追问3：** 中心收到告警后，需要做实时展示和联动处理（如通知安保、联动门禁、报警110）。这个告警分发怎么设计？

> 你回答...（提示：告警处理服务 → 消费 Kafka → 处理 → 分发 / 处理流程：①告警去重 → 同一事件短时间内多次触发 → 只保留最严重的 → 用 Redis 做窗口去重（5秒内同网点同类型告警合并）②告警分级 → 严重程度：低/中/高/紧急 → 不同级别不同处理 ③规则引擎 → 根据告警类型+网点+时间 → 匹配处置规则 → 如"金库区域陌生人→紧急→联动门禁+报警+通知行长" ④实时推送 → WebSocket 推送到监控大屏 → 安保人员看到 → ⑤联动执行 → 通过接口调用门禁/报警系统 / 规则引擎选型：Drools / Aviator / 自研 → 规则可配置 → 不改代码 → 不同网点不同规则 / 告警通道：①紧急 → 电话/短信 + App推送 + 大屏弹窗 ②高 → App推送 + 大屏 ③中 → 大屏展示 ④低 → 记录日志 → 日报 / 幂等性：同一告警可能被消费多次（Kafka at-least-once）→ 告警ID做幂等 → Redis SET 去重 / 告警不丢：Kafka 消费成功才提交 offset → 处理失败不提交 → 重试）

**追问4：** 1万个网点的设备怎么管理？设备掉线怎么发现？固件和AI模型怎么升级？

> 你回答...（提示：设备管理：①设备注册 → 边缘设备首次启动 → 向中心注册 → 分配设备ID + 网点归属 → 存数据库 ②心跳机制 → 边缘设备每30秒上报心跳 → 中心更新最后在线时间 → 超过3分钟没心跳 → 标记离线 → 告警运维 ③设备状态 → CPU/内存/温度/存储/网络 → 实时上报 → 异常预警 / 固件升级（OTA）：①中心发布新版本 → 推送升级通知 → 边缘设备拉取 → 灰度升级（先10% → 验证 → 全量）②升级失败回滚 → 保留旧版本 → 新版本启动失败自动回滚 / AI模型升级：①新模型训练 → 中心发布 → 边缘设备下载 → 热加载不停机 → 旧模型继续工作 → 新模型加载完切换 ②AB 测试 → 部分网点用新模型 → 对比效果 → 全量推送 ③模型版本管理 → 每个网点的当前模型版本 → 可追溯 / 设备管理平台：类似 IoT 平台 → 设备注册/心跳/状态/远程配置/OTA → 可以参考阿里云IoT/华为云IoT设计 / 高可用：设备管理服务集群 → 设备量大 → 用分片 → 按网点ID hash → 不同网点的设备在不同实例管理）

**追问5：** 如果某个网点发生紧急情况（如抢劫），需要立即调取该网点的实时视频。但视频在边缘设备上，你怎么实现低延迟的实时视频拉取？

> 你回答...（提示：需求：紧急情况 → 中心实时调取网点视频 → 低延迟（<2秒）/ 挑战：视频在边缘设备 → 中心拉取 → 跨广域网 → 延迟和带宽 / 方案：①WebRTC → P2P → 中心直接连边缘设备 → 建立点对点连接 → 延迟最低 → 但NAT穿透可能需要TURN ②RTSP/RTMP 拉流 → 边缘设备提供RTSP流 → 中心拉流 → 延迟1-3秒 → 但需要公网IP或VPN ③边缘设备推流 → 紧急时边缘设备主动推流到中心流媒体服务器（如SRS/ZLMediaKit）→ 中心观看 → 适合没有公网IP的场景 / 推荐：平时不传视频 → 节省带宽 → 紧急时边缘设备推流到中心流媒体服务器 → 中心Web端播放 / 流媒体服务器：SRS / ZLMediaKit → 接收RTMP → 转WebRTC/HLS → Web端播放 / 延迟优化：WebRTC → UDP → 延迟<1秒 → 但UDP可能被防火墙拦 → 需要网络规划 / 录像存储：边缘设备本地存7天 → 超过上传OSS冷存储 → 紧急回放从边缘或OSS拉取 / 安全：视频传输加密 → TLS → 视频水印 → 防截屏泄露）

**追问6：** 这个系统的监控和运维怎么做？怎么知道系统是不是健康的？

> 你回答...（提示：监控分层：①边缘设备监控 → 心跳/CPU/内存/温度/存储/网络 → 异常告警 ②网络监控 → 网点到中心的网络质量 → 延迟/丢包/带宽 ③服务监控 → 中心各服务 → QPS/延迟/错误率 → Prometheus + Grafana ④业务监控 → 告警量趋势 → 突增可能是设备误报或真实安全事件 → 对比历史基线 / 告警监控：①设备离线率 → 某区域大量离线 → 可能网络故障 ②告警延迟 → 从事件发生到中心收到 → 端到端延迟 ③AI 准确率 → 抽检告警是否准确 → 误报率/漏报率 → 模型优化依据 ④链路追踪 → 告警从边缘→MQTT→Kafka→处理→展示 → 全链路 → SkyWalking / 容量规划：①网点增长趋势 → 设备增长 → 资源扩容 ②告警洪峰 → 节假日/夜间 → 告警量波动 → 弹性扩容 / 运维自动化：①设备故障自动工单 → 派单运维 ②服务自愈 → K8s Pod 挂了自动重启 ③灰度发布 → 新版本先灰度10%网点 → 验证 → 全量 / SLA：告警端到端延迟 < 30秒 → 可用性 99.9% → 关键告警不丢）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| TCP/IP 三次握手四次挥手 | 能讲清 / 讲不全 / 不会★ | |
| Java IO 模型 BIO/NIO/AIO | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（快速排序） | 能讲清 / 讲不全 / 不会★ | |
| K8s 基础与容器编排 | 能讲清 / 讲不全 / 不会★ | |
| 一致性 Hash 算法与数据分片 | 能讲清 / 讲不全 / 不会★ | |
| 设计模式在源码中的应用 | 能讲清 / 讲不全 / 不会★ | |
| 金融智能视频监控平台设计 | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **TCP/IP 三次握手**是网络基础面试必考题。核心：三次而不是两次的原因 = 防止历史连接（已失效的SYN到达服务端导致无效连接）+ 双向确认收发能力。四次而不是三次的原因 = TCP全双工，两个方向各关一次，ACK和FIN不能合并因为收到FIN时可能还有数据要发。TIME_WAIT 等 2MSL = 确保最后ACK到达 + 防止旧报文影响新连接。粘包/拆包 = TCP面向字节流无消息边界 → 解决：消息头含长度字段（LengthFieldBasedFrameDecoder）
> 2. **Java IO 模型**要分清三个层次：BIO = 同步阻塞（一连接一线程，线程浪费在等待上）/ NIO = 同步非阻塞（Channel+Buffer+Selector，一个线程管理多连接，但read()还是得自己读）/ AIO = 异步非阻塞（系统读完数据回调通知，Linux上用epoll模拟=没有比NIO更好）。select/poll/epoll区别：epoll事件驱动O(1)查找就绪fd，select遍历O(n)且有1024限制。Netty = NIO的封装 + Boss/Worker模型 + ByteBuf池化 + 解决epoll空轮询bug
> 3. **快速排序**：partition选pivot→分两区→递归。平均O(n log n)最坏O(n²)（已排序数组选首尾元素做pivot）。避免：随机pivot或三数取中。双轴快排(Dual-Pivot)分三区→Java Arrays.sort()基本类型用它。快排vs归并：快排原地不稳定但快，归并稳定但要O(n)空间
> 4. **K8s**核心：Pod是最小调度单位（共享网络和存储的容器组）。控制面：API Server(入口) + etcd(状态存储) + Scheduler(调度) + Controller Manager(调谐)。数据面：kubelet + kube-proxy + 容器运行时。Deployment→ReplicaSet→Pod三层管理。Service提供固定IP+负载均衡（四层iptables/ipvs）。Ingress做七层路由。滚动更新靠maxSurge/maxUnavailable+readinessProbe保证不中断。K8s Service vs Nginx：Service是四层内核态，Nginx是七层用户态
> 5. **一致性Hash**：hash环→节点和key都hash到环上→key顺时针找第一个节点。节点变化只影响相邻区间→迁移量小。问题：数据倾斜→解决：虚拟节点(150-200个)。Redis Cluster不用一致性Hash而用固定16384 slot→可控性+迁移精确+Gossip开销小。一致性Hash场景：Memcached分片、Nginx ip_hash、有状态服务路由
> 6. **设计模式在源码中**：单例(Runtime饿汉式)、责任链(Netty ChannelPipeline/Spring HandlerInterceptor/AOP Advice链)、模板方法(InputStream.read/JdbcTemplate/AbstractQueuedSynchronizer)、观察者(Spring ApplicationEvent/@EventListener)、策略(Comparator/ThreadPoolExecutor拒绝策略)。面试时要能说出"在哪个类里怎么用的"而不只是背定义
> 7. **金融智能视频监控平台**设计要点：边缘计算(视频不传中心只传告警)→MQTT接入→Kafka缓冲→告警处理(去重+分级+规则引擎)→实时推送(WebSocket)+联动。设备管理(心跳+OTA+模型热加载)。紧急视频(WebRTC/RTMP推流)。监控分层(设备/网络/服务/业务)。核心权衡：实时性vs带宽成本→边缘分析+结果上传
