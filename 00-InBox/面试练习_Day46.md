# 面试模拟 - Day 46

> 日期：2026-07-16（周四） | 模拟岗位：邦盛科技（杭州）- Java开发工程师
> 建议时长：85分钟（一面55分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day46，模拟邦盛科技——杭州本土金融科技公司，专注实时风控引擎和决策引擎，服务全国300+银行、支付机构、保险公司。和之前做的金融机构不同，邦盛是"卖技术给金融机构"的技术公司，面试更看重高并发实时处理能力和底层原理深度。今天引入 MySQL MVCC 深度原理、Java 内存模型(JMM)深入、Docker 容器化原理、Nginx 反向代理与负载均衡等新话题，核心设计题围绕实时风控决策引擎展开。

---

# 一面（55分钟）

## 话题一：MySQL MVCC 深度原理（12分钟）

**面试官：你刚才提到你们用 MySQL。MySQL 的 InnoDB 引擎在 RR 隔离级别下是怎么解决不可重复读问题的？你了解 MVCC 吗？**

 你回答...

**追问1：** MVCC 是什么？它在 InnoDB 里是怎么实现的？依赖哪些底层结构？

> 你回答...（提示：MVCC = Multi-Version Concurrency Control 多版本并发控制 / 核心思想：读不加锁，通过版本链让事务看到自己应该看到的数据版本 / 不加锁→读写不互相阻塞→高并发 / 三个底层结构：①隐藏字段 trx_id（最近修改的事务ID）、roll_pointer（指向 undo log 的指针）②undo log 版本链（每条记录的历史版本通过 roll_pointer 串成链表）③ReadView（读视图，决定当前事务能看到哪个版本））

**追问2：** ReadView 里有什么？它是怎么决定一个事务能看到哪个版本的？

> 你回答...（提示：ReadView 包含四个关键字段：①m_ids（生成 ReadView 时活跃事务ID列表）②min_trx_id（m_ids 中最小值）③max_trx_id（下一个要分配的事务ID）④creator_trx_id（创建 ReadView 的事务自己的 ID）/ 可见性判断规则：遍历版本链，对每个版本的 trx_id 判断：①trx_id == creator_trx_id → 自己修改的，可见 ②trx_id < min_trx_id → 修改已提交，可见 ③trx_id >= max_trx_id → 修改在 ReadView 之后开始，不可见 ④min_trx_id <= trx_id < max_trx_id 且在 m_ids 中 → 活跃事务，不可见 / 不在 m_ids 中 → 已提交，可见 / 沿 roll_pointer 找下一个版本直到可见）

**追问3：** RC 和 RR 隔离级别下，MVCC 的行为有什么不同？

> 你回答...（提示：核心区别在于 ReadView 生成的时机 / RC（读已提交）：每次 SELECT 都生成新的 ReadView → 每次读都能看到最新已提交的数据 → 不可重复读 / RR（可重复读）：只在第一次 SELECT 时生成 ReadView，后续复用 → 同一事务内多次读结果一致 → 解决了不可重复读 / 但 RR 下用的是"快照读"，当前读（SELECT ... FOR UPDATE / UPDATE / DELETE）不走 MVCC，走加锁 / RR 下通过 Next-Key Lock 解决幻读）

**追问4：** 你说的"快照读"和"当前读"有什么区别？哪些操作是当前读？

> 你回答...（提示：快照读：普通 SELECT / 走 MVCC / 读 undo log 版本链 / 不加锁 / 当前读：SELECT ... FOR UPDATE / SELECT ... LOCK IN SHARE MODE / UPDATE / DELETE / INSERT / 读的是最新数据 / 加锁（记录锁/间隙锁/Next-Key Lock）/ 当前读不走 MVCC / 所以 UPDATE 和 SELECT 看到的数据版本可能不一样）

**追问5：** 你能举一个实际的例子吗？事务 A 开启后先读了一条数据，事务 B 修改了这条数据并提交，事务 A 再读——RC 和 RR 下分别看到什么？

> 你回答...（提示：RC：事务 A 第一次读生成 ReadView1，能看到事务 B 修改前的版本 / 事务 B 修改并提交 / 事务 A 第二次读生成 ReadView2，此时事务 B 已提交不在活跃列表 → 读到事务 B 修改后的值 → 不可重复读 / RR：事务 A 第一次读生成 ReadView1 / 事务 B 修改并提交 / 事务 A 第二次读复用 ReadView1，事务 B 的 trx_id 仍然在 ReadView1 的判断范围内（如果 B 在 A 之后开启）→ 读到旧版本 → 可重复读 / 这就是 RR 解决不可重复读的原理）

**追问6：** MVCC 解决了读写冲突，但它有没有什么代价或者问题？

> 你回答...（提示：①undo log 版本链越长，查找可见版本的代价越大 → 长事务会导致版本链很长 → 查询变慢 / ②长事务导致 undo log 不能回收 → 回滚段膨胀 → 占用表空间 / ③MVCC 只解决了快照读的并发，当前读还是要加锁 / ④RR 下 ReadView 复用，如果事务很长，期间大量事务提交，本事务看到的"快照"越来越旧 → 业务逻辑可能基于过期数据做判断 / 实践：避免长事务，定期提交，监控 undo log 大小）

---

## 话题二：Java 内存模型(JMM)深入（10分钟）

**面试官：你简历上写了多线程并发编程。Java 的内存模型你了解吗？volatile 关键字除了可见性还有什么作用？**

 你回答...

**追问1：** JMM 是什么？它和 JVM 内存结构（堆/栈/方法区）是什么关系？

> 你回答...（提示：JMM（Java Memory Model）≠ JVM 内存结构 / JMM 是一种抽象模型：规定线程之间的共享变量存储在主内存（Main Memory）中 / 每个线程有自己的本地内存（Working Memory，CPU 缓存的抽象）/ 线程不能直接读写主内存，必须通过本地内存 / JMM 定义了什么情况下一个线程对共享变量的修改对另一个线程可见 / 和 JVM 内存结构的关系：JVM 堆/栈/方法区是运行时数据区域划分 / JMM 是并发编程的抽象模型 / 两者正交，不是一回事）

**追问2：** 可见性问题的本质是什么？为什么一个线程修改变量另一个线程看不到？

> 你回答...（提示：CPU 多级缓存（L1/L2/L3）+ 指令重排 / 线程在工作内存（CPU 缓存）修改变量 / 还没刷回主内存 / 另一个线程从自己的工作内存读旧值 / 这就是可见性问题 / 加 volatile 后：①写操作后立刻刷回主内存 ②读操作强制从主内存读 ③底层通过内存屏障（Memory Barrier）实现）

**追问3：** 你提到指令重排。什么是指令重排？volatile 怎么防止指令重排？

> 你回答...（提示：编译器和 CPU 为了优化性能会重排指令顺序 / 单线程下重排不影响结果（as-if-serial）/ 多线程下重排会破坏语义 / 经典案例：双重检查锁定（DCL）单例 / `instance = new Singleton()` 实际分三步：①分配内存 ②初始化对象 ③引用指向内存 / 重排成 ①③② → 另一个线程在②之前看到 instance != null → 拿到未初始化的对象 → NPE / volatile 通过内存屏障防止重排：①写操作前插入 StoreStore 屏障 ②写操作后插入 StoreLoad 屏障 ③保证写操作之前的写操作对后续读操作可见 / 这就是为什么 DCL 单例的 instance 要加 volatile）

**追问4：** happens-before 原则你了解吗？它和 JMM 是什么关系？

> 你回答...（提示：happens-before 是 JMM 的核心概念 / 不是说"前一个操作发生在后一个之前" / 而是"前一个操作的结果对后一个操作可见" / 六大规则：①程序顺序规则：单线程内代码顺序前的操作 happens-before 后的 ②volatile 变量规则：volatile 写 happens-before 后续的 volatile 读 ③锁规则：unlock happens-before 后续 lock ④线程启动规则：Thread.start() happens-before 线程内所有操作 ⑤线程终止规则：线程内所有操作 happens-before Thread.join() 返回 ⑥传递性：A happens-before B，B happens-before C → A happens-before C / volatile 的 happens-before：写 volatile 变量 happens-before 后续读该变量 / 这保证了可见性 + 防止重排）

**追问5：** synchronized 和 volatile 有什么区别？什么场景用 volatile，什么场景用 synchronized？

> 你回答...（提示：volatile：①保证可见性 + 防止指令重排 ②不保证原子性（i++ 仍然不安全）③轻量级不阻塞线程 / synchronized：①保证可见性 + 原子性 + 有序性 ②重量级会阻塞线程 / volatile 适用场景：①状态标志位 boolean ②DCL 单例 ③发布初始化完成的引用 / synchronized 适用场景：①复合操作（i++/check-then-act）②需要互斥的临界区 / volatile 不能替代 synchronized / 但 synchronized 可以替代 volatile / 选择原则：能用 volatile 就不用 synchronized）

**追问6：** 你说 volatile 不保证原子性，那 `i++` 加 volatile 线程安全吗？为什么？

> 你回答...（提示：不安全 / i++ 不是原子操作 = 读 i + i+1 + 写回 / 三步之间可能被其他线程打断 / volatile 只保证每次读都能看到最新值 / 但读到最新值后计算+写回之间其他线程可能已经修改了 / 两个线程都读到 i=1，各自+1，都写回 2 → 丢失一次更新 / 解决：①AtomicInteger（CAS）②synchronized ③LongAdder（高并发下比 Atomic 更好——分段累加））

---

## 话题三：手写代码 - 数组中第K个最大元素（8分钟）

**面试官：给你一个整数数组 nums 和一个整数 k，请返回数组中第 k 个最大的元素。比如 `[3,2,1,5,6,4]`，k=2，返回 5。写一下。**

你在纸上/白板上写代码...

**追问1：** 你用的什么方法？时间复杂度是多少？

> 你回答...（提示：两种解法：①排序法：Arrays.sort() 后取第 k 个 → O(n log n) / ②小顶堆：维护大小为 k 的小顶堆，遍历数组，比堆顶大就替换 → 堆大小 k，调整 O(log k) → 总 O(n log k) → 空间 O(k) / 堆方法在 k 远小于 n 时更快 / ③快速选择（Quick Select）：类似快排的 partition，每次只递归一侧 → 平均 O(n)，最坏 O(n²) / 面试优先写堆方法，清晰好实现）

**追问2：** 为什么用小顶堆而不是大顶堆？

> 你回答...（提示：要第 k 个最大的 → 维护大小为 k 的堆 → 堆里存当前最大的 k 个元素 → 小顶堆的堆顶是这 k 个里最小的 → 也就是第 k 大 / 如果用大顶堆，堆大小要是 n-k+1 才能找到第 k 大 → 堆更大 / 或者全部入大顶堆再 pop k 次 → 空间 O(n) / 小顶堆更优：只需 O(k) 空间）

**追问3：** 如果数据量特别大，内存放不下怎么办？

> 你回答...（提示：外部排序 / 数据分成多个文件 → 每个文件排序 → 多路归并 → 但求 Top K 不需要全排序 / 改进：分批读取 → 每批维护 Top K → 最后合并所有批的 Top K → 仍然是小顶堆 / 如果是流式数据 → 用大小为 k 的堆实时维护 / 如果 k 也很大 → 改用分桶计数（类似计数排序）：先采样估算数据分布 → 按值域分桶 → 找到第 K 大所在的桶 → 桶内精确查找）

**追问4：** 快速选择方法最坏情况 O(n²)，怎么优化？

> 你回答...（提示：最坏情况：每次选的 pivot 都是最大或最小 → 退化为 O(n²) / 优化：①随机选 pivot → 期望 O(n) / ②三数取中法：取首、中、尾的中位数作为 pivot / ③Intro Select：递归深度超过 2log n 时切换到堆方法 → 保证最坏 O(n log k) / Java 的 Arrays.sort() 对基本类型用双轴快排，对对象用 TimSort / 实际面试写堆方法最稳妥）

**追问5：** PriorityQueue 你了解底层实现吗？add 和 poll 的时间复杂度？

> 你回答...（提示：PriorityQueue 底层是数组实现的小顶堆（默认） / add/offer：先加到末尾 → 上浮（siftUp）→ O(log n) / poll：取堆顶 → 末尾移到堆顶 → 下沉（siftDown）→ O(log n) / peek：O(1) / 构造方法：如果传入 Collection → heapify → 从最后一个非叶子节点开始下沉 → O(n) 不是 O(n log n) / 自定义比较器：Comparator.reverseOrder() 变大顶堆 / 线程不安全 → PriorityBlockingQueue 线程安全）

---

## 话题四：Docker 容器化原理（8分钟）

**面试官：你们线上用 Docker 部署吗？你了解 Docker 底层是怎么实现隔离的吗？**

 你回答...

**追问1：** Docker 和传统虚拟机有什么本质区别？

> 你回答...（提示：虚拟机：每个 VM 有完整的操作系统 → Hypervisor 层 → 资源开销大 → 启动慢（分钟级）→ 隔离强 / Docker：共享宿主机内核 → 容器只是隔离的进程 → 资源开销小 → 启动快（秒级）→ 隔离弱（共享内核）/ Docker 不是虚拟机，是"带资源限制的进程隔离" / 所以容器里装 CentOS 和装 Ubuntu 本质一样——都是用宿主机内核 / 容器里的 init 进程就是你的应用进程）

**追问2：** Docker 的隔离靠什么技术？你说说 Namespace。

> 你回答...（提示：Namespace 实现资源隔离 / 六大 Namespace：①PID Namespace → 进程隔离（容器内 PID 从 1 开始）②NET Namespace → 网络隔离（独立网卡/IP/路由表/端口）③IPC Namespace → 进程间通信隔离 ④MNT Namespace → 文件系统挂载点隔离 ⑤UTS Namespace → 主机名隔离 ⑥USER Namespace → 用户和用户组隔离 / Docker run 时通过 clone() 系统调用 + CLONE_NEWPID 等标志创建新 Namespace / 容器内看到的是隔离后的视图 / 但共享内核——内核漏洞影响所有容器）

**追问3：** 光隔离还不够，容器资源怎么限制？Cgroups 了解吗？

> 你回答...（提示：Cgroups（Control Groups）限制资源使用 / 限制 CPU：--cpus=2（最多用 2 核）/ --cpu-shares（权重）/ 限制内存：--memory=2g（最大内存）/ --memory-swap / 限制磁盘 IO：--device-read-bps / Cgroups 子系统：cpu、memory、blkio、pids 等 / 和 Namespace 的关系：Namespace 做"看不到"，Cgroups 做"用不了" / 两者配合 = 容器 / 问题：OOM Killer 在容器内行为不同——容器内进程 OOM 可能被宿主机 OOM Killer 杀掉 / Docker --oom-kill-disable 可以禁用）

**追问4：** Docker 镜像是怎么存储的？为什么说镜像是分层的？

> 你回答...（提示：镜像分层靠 UnionFS（联合文件系统）/ 每条 Dockerfile 指令生成一层 / FROM → 一层 / RUN apt-get → 一层 / COPY → 一层 / 每层只存和上一层的差异 / 好处：①多镜像共享基础层 → 节省存储 ②构建缓存：未修改的层直接用缓存 → 加速构建 ③拉取时只传差异层 / 存储驱动：OverlayFS（Overlay2）是主流 / Lower Layer（只读）+ Upper Layer（读写）+ Workdir → 合并成容器根文件系统 / 容器写入 → 写入 Upper Layer（Copy-On-Write）→ 不影响 Lower Layer / 删除文件 → 在 Upper Layer 创建 whiteout 文件标记删除）

**追问5：** 你们 Dockerfile 有没有什么最佳实践？镜像怎么减小体积？

> 你回答...（提示：①用 slim/alpine 基础镜像 → 体积从 800MB → 100MB / ②多阶段构建：builder 阶段编译 → runtime 阶段只 COPY 产物 → 不带编译工具 / ③合并 RUN 指令 → 减少层数 / ④.dockerignore 排除不必要文件 / ⑤清理缓存：apt-get install 后 rm -rf /var/lib/apt/lists/* / ⑥不把 secrets 打进镜像 → 用环境变量 / ⑦固定版本：FROM openjdk:11-jre-slim 而不是 latest / ⑧JVM 在容器中：Java 8u131+ 才正确识别容器 CPU/内存限制 → 之前 JVM 看到的是宿主机内存 → 容器内存限制 2G 但 JVM 看到 32G → 堆设太大 → OOM Killer）

---

## 话题五：Nginx 反向代理与负载均衡（8分钟）

**面试官：你们微服务前面有 Nginx 吗？Nginx 做什么用？你了解 Nginx 的工作原理吗？**

 你回答...

**追问1：** 正向代理和反向代理有什么区别？Nginx 是哪种？

> 你回答...（提示：正向代理：代理客户端 → 客户端知道目标服务器 → 代理帮客户端访问 → 服务器不知道真实客户端 → 场景：VPN/翻墙/公司出口代理 / 反向代理：代理服务端 → 客户端不知道真实服务器 → 代理转发到后端 → 场景：Nginx/LB / Nginx 是反向代理：用户访问 Nginx → Nginx 转发到后端 Tomcat → 用户只知道 Nginx 地址 / 正向代理隐藏客户端，反向代理隐藏服务端）

**追问2：** Nginx 的事件驱动模型你了解吗？为什么 Nginx 能支撑高并发？

> 你回答...（提示：Nginx 用 epoll（Linux）事件驱动 / 一个 master 进程 + 多个 worker 进程 / master 负责管理 worker / worker 负责处理请求 / 一个 worker 可以处理数千个连接 / 不像 Tomcat 一个请求一个线程 / Nginx worker 数一般设为 CPU 核心数 / worker 用非阻塞 IO + epoll → 单线程处理大量连接 → 不需要线程切换开销 / 这就是为什么 Nginx 能扛 C10K 甚至 C100K / epoll vs select：epoll 只返回就绪的 fd → O(1) / select 轮询所有 fd → O(n)）

**追问3：** Nginx 负载均衡有哪些策略？你们用的哪种？

> 你回答...（提示：①轮询（默认）：按顺序分配 / ②weight：按权重分配 → 配合服务器性能差异 / ③ip_hash：同一 IP 固定到同一后端 → 解决 session 问题 / 但后端挂了需要重新分配 / ④least_conn：最少连接数优先 → 更均衡 / ⑤fair（第三方）：按响应时间分配 → 最智能但需安装模块 / 实际用法：多数用 weight + health check / session 粘性用 ip_hash 但有坑——NAT 后大量用户同一 IP → 全压到一台 / 更好用 sticky cookie 或 session 共享到 Redis）

**追问4：** Nginx 怎么做健康检查？后端某台挂了怎么处理？

> 你回答...（提示：开源 Nginx 被动健康检查：请求失败 → 标记为 down → 一段时间内不再转发 → 过 max_fails 次失败后标记 / fail_timeout 后重试 / 主动健康检查需要 Nginx Plus（商业版）或第三方模块（nginx_upstream_check_module）/ 开源方案：①Consul + consul-template 动态更新 upstream ②OpenResty + lua 做主动健康检查 / 实际架构：Nginx + Consul 做服务发现 → 后端挂了 Consul 自动摘除 → Nginx upstream 更新）

**追问5：** Nginx 限流怎么做？你了解 limit_req 吗？

> 你回答...（提示：limit_req_zone + limit_req / 漏桶算法：请求进队列 → 固定速率处理 → 超过队列容量直接拒绝 / 配置：`limit_req_zone $binary_remote_addr zone=one:10m rate=100r/s` / `limit_req zone=one burst=200 nodelay` / rate=100r/s：每秒 100 请求 / burst=200：允许突发 200 个 / nodelay：突发请求不延迟直接处理 / 没有 nodelay → 突发请求排队等待 / 429 Too Many Requests / 也可以用 OpenResty + lua 做更灵活的限流 → 和 Sentinel 互补：Nginx 层做入口限流，Sentinel 做服务级限流）

---

## 话题六：实时风控引擎业务（9分钟）

**面试官：邦盛的核心产品是实时风控引擎。你了解风控引擎是做什么的吗？和你们在银行做的系统有什么不同？**

 你回答...

**追问1：** 实时风控引擎的核心目标是什么？它在一个交易链路里处于什么位置？

> 你回答...（提示：核心目标：在交易发生前实时判断风险，决定放行/拦截/人工审核 / 位置：用户发起交易 → 风控引擎实时评估 → 决策 → 放行/拦截/转人工 → 后续交易处理 / 典型场景：①银行卡刷卡反欺诈 ②支付通道风险评估 ③贷款申请实时审批 ④营销反薅羊毛 / 核心 SLA：响应时间 < 50ms（不能让用户等）/ 7×24 可用 / 日处理千万到亿级请求）

**追问2：** 风控引擎里"规则"和"模型"是什么关系？和你在消费金融做的风控有什么区别？

> 你回答...（提示：规则：人工配置的 if-else 逻辑 → "单日转账超过 50 万拦截" / "凌晨 3 点异地交易告警" / 模型：机器学习训练的概率模型 → 给一个风险分 0-100 / 两者配合：规则做硬拦截（确定性判断），模型做风险评估（概率判断）/ 和消费金融的区别：消费金融风控在申请环节（低频，几百 ms 可接受），交易风控在每一笔交易（高频，必须 < 50ms）/ 交易风控更强调实时性和吞吐量 / 交易风控需要实时聚合——"过去 5 分钟该卡交易了 3 次"这种滑动窗口统计）

**追问3：** 你说的"实时聚合"是什么？怎么实现"过去 5 分钟交易 3 次"这种统计？

> 你回答...（提示：这是风控引擎的核心难点 / 方案：①实时流处理 Flink → 滑动窗口统计 → 结果写 Redis → 风控引擎读 Redis / ②自研内存聚合引擎 → 交易进来实时累加 → 滑动窗口过期 / ③Redis 做实时统计：Sorted Set 按时间戳存交易 → ZREMRANGEBYSCORE 删除过期 → ZCARD 计数 / 但 Redis 方案在海量交易下性能瓶颈 / 邦盛的方案：自研流式计算引擎（大数据量场景）+ Redis（小数据量场景）/ 关键：聚合必须在内存中完成 → 不能查数据库 → 50ms 响应时间不允许 IO / 聚合数据要持久化 → 重启后恢复 / 多节点共享 → 用分布式缓存或 Hazelcast）

---

# 二面（30分钟）

## 话题七：实时风控决策引擎系统设计（18分钟）

**面试官：如果让你设计一个实时风控决策引擎，要求日处理 1 亿笔交易、响应时间 < 50ms、规则可配置、模型可插拔，你怎么设计？**

你在纸上画架构图/说思路...

**追问1：** 1 亿笔/天，平均 QPS 多少？峰值怎么估？你的架构怎么扛住？

> 你回答...（提示：1 亿/天，假设 10 小时活跃 → 平均 QPS = 1亿 / 36000 ≈ 2800 / 峰值按 5-10 倍 → 峰值 QPS 1.5万-3万 / 单机处理能力 2000-5000 QPS → 需要 5-10 台机器 / 水平扩展：无状态服务 + 负载均衡 / 50ms 响应时间意味着：不能做 DB 查询（RT 10-50ms）/ 不能调外部接口 / 数据全在内存或 Redis / 决策引擎是 CPU 密集型 → 不做 IO）

**追问2：** 规则引擎你怎么选？1000 条规则，每条可能有 10 个条件，怎么在 50ms 内全部执行完？

> 你回答...（提示：规则引擎选型：①Drools（功能强大但重）②Aviator/QLExpress（轻量表达式引擎）③自研规则引擎 / 1000 条规则 × 10 条件 = 1 万次判断 → 50ms 内完成 / 优化：①规则索引：按条件预筛选 → 只执行相关规则 → 比如交易类型=转账 只执行转账类规则（可能 200 条）②规则编译：规则配置后编译成 Java 代码或字节码 → 不用每次解析表达式 ③并行执行：无依赖的规则并行执行 ④短路：条件不满足直接跳过后续条件 / 实际方案：规则预热编译 + 规则索引 + 并行执行 → 200 条规则 5ms 内完成 / 剩余 45ms 给模型推理 + 聚合数据查询）

**追问3：** 实时聚合数据怎么存？前面说的"过去 5 分钟交易 3 次"，数据量大了怎么办？

> 你回答...（提示：方案分层：①热数据（当前实时窗口）→ 内存/Hazelcast 分布式内存 → 最快 / ②温数据（近 1 小时/1 天）→ Redis → 秒级查询 / ③冷数据（历史统计）→ 预计算后存 Redis / ES / 查询 → 50ms 预算分配：聚合数据查询 10ms / 规则执行 5ms / 模型推理 20ms / 网络+序列化 15ms / 内存聚合引擎设计：每个设备/卡号一个窗口 → 滑动窗口用时间轮算法 → 过期自动清理 / 多节点：用 Hazelcast/ignite 分布式内存网格 → 数据分片 → 每节点维护一部分 / 数据恢复：定期快照 + WAL 日志 → 节点重启后恢复内存状态）

**追问4：** 规则修改后怎么不重启生效？线上正在跑 3 万 QPS，规则变更怎么灰度？

> 你回答...（提示：规则热加载：①规则配置存储在配置中心（Nacos/Apollo）②规则变更 → 推送到所有节点 → 节点收到后重新编译规则 → 原子替换规则集 → 无锁切换 / 不停机 / 灰度方案：①规则版本管理 → 新规则先在 10% 流量上灰度 → 比较拦截率是否异常 → 全量发布 ②影子流量 → 线上请求复制一份走新规则 → 比较新旧规则结果差异 → 不影响线上交易 ③回滚：规则版本回退 → 秒级生效 / 规则审核流程：配置 → 审核 → 灰度 → 全量 → 监控 → 回滚全链路）

**追问5：** 风控引擎的高可用怎么保证？如果引擎挂了，交易怎么办？

> 你回答...（提示：风控挂了的两种策略：①fail-open（放行）→ 风控不可用时放行交易 → 用户体验好但有风险 ②fail-closed（拒绝）→ 风控不可用时拒绝交易 → 安全但影响业务 / 选型看业务：①支付交易 → fail-closed（宁可拒绝不放风险）②营销活动 → fail-open（少送点权益无所谓）/ 高可用方案：①多机房部署 → 同城双活 ②服务多副本 → N+1 冗余 ③降级链路：引擎挂 → 降级到本地规则缓存（基础规则）→ 再挂 → 走 fail 策略 ④熔断：下游模型服务不可用 → 走兜底规则 ⑤监控：引擎响应时间/拦截率/异常率实时告警 → 拦截率突降可能引擎异常放行了所有请求）

**追问6：** 风控效果怎么评估？你怎么知道一条规则拦截的是对的？

> 你回答...（提示：①规则准确率：拦截的案件中实际欺诈的比例 → 查准率 ②规则覆盖率：实际欺诈中被规则拦截的比例 → 查全率 ③误报率：被拦截但实际正常的交易比例 → 太高影响用户体验 ④规则命中率：规则触发次数/总交易数 → 命中率太低考虑下线 ⑤人工复核：拦截案件抽样人工审核 → 评估准确率 ⑥离线回测：新规则上线前用历史数据回测 → 看会拦截多少 + 误报多少 ⑦A/B 测试：新旧规则并行 → 对比效果 ⑧业务指标：欺诈损失金额下降 + 客户投诉率 / 核心矛盾：风控太严 → 用户体验差 → 客户流失 / 风控太松 → 欺诈损失大 / 持续调优平衡点）

---

## 话题八：Java 线程池深入 - ThreadPoolExecutor 源码（12分钟）

**面试官：你简历上写了线程池。ThreadPoolExecutor 的核心参数有哪些？任务提交后的执行流程你了解吗？**

 你回答...

**追问1：** 七个核心参数分别是什么？每个参数的作用？

> 你回答...（提示：①corePoolSize：核心线程数 → 即使空闲也不回收（除非 allowCoreThreadTimeOut=true）②maximumPoolSize：最大线程数 → 包括核心线程 ③keepAliveTime：非核心线程空闲存活时间 ④unit：时间单位 ⑤workQueue：任务队列 → 阻塞队列 ⑥threadFactory：线程工厂 → 创建线程 ⑦handler：拒绝策略 / 常见队列搭配：LinkedBlockingQueue（无界→容易 OOM）/ ArrayBlockingQueue（有界）/ SynchronousQueue（不存任务→直接交给线程）

**追问2：** 一个任务提交到线程池后，执行流程是什么？为什么是先到队列再到最大线程数？

> 你回答...（提示：流程：①线程数 < corePoolSize → 创建核心线程执行 ②线程数 >= corePoolSize → 任务入队列 ③队列满 → 创建非核心线程直到 maximumPoolSize ④线程数 = maximumPoolSize 且队列满 → 执行拒绝策略 / 为什么先队列再扩线程？：创建线程有开销（栈内存约 1MB/线程）/ 入队列成本低 / JDK 设计者认为：先复用已有线程（队列排队）→ 不够再扩容 / 而不是一有任务就开新线程 / 但实际使用中经常需要改成"先扩线程后入队列"→ 自己实现或用 ElasticThreadPool）

**追问3：** 四种拒绝策略分别是什么？你们用的哪种？

> 你回答...（提示：①AbortPolicy（默认）：抛 RejectedExecutionException → 调用方感知 → 自行处理 ②CallerRunsPolicy：由提交任务的线程执行 → 背压（backpressure）→ 不拒绝但变慢 → 生产者降速 ③DiscardPolicy：直接丢弃 → 静默丢弃 → 有风险 ④DiscardOldestPolicy：丢弃队列头部最旧的任务 → 执行新任务 / 实际选择：①核心业务 → AbortPolicy + 调用方重试/降级 ②非核心（日志/统计）→ DiscardPolicy ③削峰 → CallerRunsPolicy / 自己实现 RejectedExecutionHandler 做更精细的处理 → 比如记录日志+告警+降级到 MQ）

**追问4：** 线程池源码里 `ctl` 变量你了解吗？它怎么同时表示线程状态和线程数？

> 你回答...（提示：ctl 是 AtomicInteger / 32 位 = 高 3 位表示线程池状态 + 低 29 位表示线程数 / 状态：RUNNING（-1）→ SHUTDOWN（0）→ STOP（1）→ TIDYING（2）→ TERMINATED（3）/ RUNNING：接收新任务 + 处理队列任务 / SHUTDOWN：不接收新任务 + 处理队列任务（shutdown()触发）/ STOP：不接收新任务 + 不处理队列 + 中断正在执行的任务（shutdownNow()触发）/ TIDYING：所有任务终止 + 工作线程数为 0 → 调 terminated() / TERMINATED：terminated() 执行完 / 用位运算同时操作状态和数量 → 一次 CAS 保证原子性）

**追问5：** 你们线程池参数怎么设的？有没有遇到过线上问题？

> 你回答...（提示：CPU 密集型：核心线程数 = CPU 核心数 + 1 / IO 密集型：CPU 核心数 × 2 或更多（公式：N = CPU数 × (1 + IO等待时间/CPU时间)）/ 队列大小：不要太大 → 请求堆积导致 RT 变长 → 用户等待超时 / 实际做法：先压测 → 观察队列堆积/线程活跃数/拒绝次数 → 调优 / 常见线上问题：①用了 Executors.newFixedThreadPool → LinkedBlockingQueue 无界 → OOM / ②用了 Executors.newCachedThreadPool → 最大线程数 Integer.MAX_VALUE → 创建大量线程 → OOM / ③线程池没有名字 → 线程 dump 看不出是哪个池 / ④核心线程数为 0 → 低延迟场景每次创建线程 → 改 corePoolSize > 0 / 阿里规约：禁止用 Executors 创建线程池 → 必须手动 new ThreadPoolExecutor）

**追问6：** `execute()` 方法提交任务和 `submit()` 有什么区别？Future 的原理你了解吗？

> 你回答...（提示：execute()：提交 Runnable → 无返回值 → 失败抛异常 / submit()：提交 Runnable 或 Callable → 返回 Future → 可以 get() 获取结果 / Future 底层：submit() 把 Runnable/Callable 包装成 FutureTask → FutureTask 实现 Runnable + Future 接口 → execute(futureTask) / FutureTask 内部用 state 字段表示任务状态：NEW → COMPLETING → NORMAL/EXCEPTIONAL / get() 时如果未完成 → LockSupport.park() 阻塞 → 任务执行完 → set() 唤醒 / FutureTask 的 run() 执行完后调 set() → 修改 state → 唤醒等待线程 / CompletableFuture 是 Future 的增强 → 支持回调/链式 → 不会阻塞 get()）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| MySQL MVCC 深度原理 | 能讲清 / 讲不全 / 不会★ | |
| Java 内存模型(JMM)深入 | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（第K个最大元素） | 能讲清 / 讲不全 / 不会★ | |
| Docker 容器化原理 | 能讲清 / 讲不全 / 不会★ | |
| Nginx 反向代理与负载均衡 | 能讲清 / 讲不全 / 不会★ | |
| 实时风控引擎业务 | 能讲清 / 讲不全 / 不会★ | |
| 实时风控决策引擎系统设计 | 能讲清 / 讲不全 / 不会★ | |
| Java 线程池深入(ThreadPoolExecutor源码) | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **MVCC 深度原理**是 MySQL 高频面试题的深水区。核心三要素：隐藏字段（trx_id + roll_pointer）→ undo log 版本链 → ReadView。可见性判断规则要能画图讲清楚——遍历版本链，用 ReadView 的四个字段判断每个版本是否可见。RC vs RR 的本质区别：ReadView 生成时机不同（RC 每次 SELECT 生成，RR 只第一次生成）。快照读走 MVCC，当前读（FOR UPDATE/UPDATE/DELETE）走加锁不走 MVCC。长事务的代价：版本链膨胀 + undo log 不能回收
> 2. **JMM（Java Memory Model）**是并发编程的理论基础。核心概念：主内存 vs 工作内存（CPU 缓存的抽象）→ 可见性问题本质是 CPU 缓存 + 指令重排。volatile 三个语义：可见性（写后刷主内存，读时从主内存读）+ 防指令重排（内存屏障）+ 不保证原子性（i++ 仍然不安全）。happens-before 六大规则要能列举。DCL 单例为什么加 volatile——防止 ①③② 重排导致拿到未初始化对象
> 3. **第K个最大元素**经典 Top K 问题。堆方法：维护大小 k 的小顶堆 → O(n log k) → 小顶堆因为堆顶是 k 个里最小的 = 第 K 大。快速选择平均 O(n) 但最坏 O(n²)。海量数据用分批堆或分桶计数。PriorityQueue 底层是数组小顶堆，add/poll 是 O(log n)，heapify 构造是 O(n) 不是 O(n log n)
> 4. **Docker 容器化原理**第一次系统考察。本质：Docker 不是虚拟机，是"带资源限制的进程隔离"。Namespace 六大类型做"看不到"（PID/NET/IPC/MNT/UTS/USER），Cgroups 做"用不了"（CPU/内存/IO 限制）。镜像分层靠 UnionFS（Overlay2），每条 Dockerfile 指令一层，容器写入走 Copy-On-Write。Java 8u131+ 才正确识别容器内存限制——之前 JVM 看到宿主机内存会 OOM。多阶段构建减小镜像体积是高频追问
> 5. **Nginx** 是反向代理 + 负载均衡 + 高并发标杆。正向代理隐藏客户端，反向代理隐藏服务端。Nginx 高并发靠 epoll 事件驱动 + master/worker 多进程模型 + 非阻塞 IO。负载均衡策略：轮询/weight/ip_hash/least_conn。被动健康检查 max_fails + fail_timeout，主动检查需第三方模块。limit_req 漏桶限流：rate + burst + nodelay。实际架构 Nginx + Consul 做动态服务发现
> 6. **邦盛科技**是"卖技术给金融机构"的金融科技公司，和银行科技子公司不同。核心产品实时风控引擎：日处理亿级交易，响应 < 50ms，规则 + 模型双引擎。核心难点：实时聚合（过去 N 分钟的统计）必须全内存，规则引擎要在 5ms 内执行数百条规则。规则热加载 + 灰度 + 回滚是工程化能力考察。fail-open vs fail-closed 是业务决策题——放行 vs 拒取决于是支付还是营销
> 7. **实时风控决策引擎设计**是今天的核心设计题。6个追问覆盖全链路：①QPS 估算与水平扩展 ②规则引擎选型与优化（规则索引 + 编译 + 并行 + 短路）③实时聚合数据分层（内存/Redis/预计算）④规则热加载与灰度（影子流量 + A/B 测试）⑤高可用与降级（fail-open/closed + 多机房 + 熔断）⑥效果评估（查准率/查全率/误报率 + 离线回测 + 人工复核）
> 8. **ThreadPoolExecutor 源码**是线程池的终极考察。执行流程：核心线程 → 队列 → 非核心线程 → 拒绝。核心设计决策：先入队列后扩线程（JDK 认为复用比扩容成本低）。ctl 变量用 32 位高 3 位存状态 + 低 29 位存线程数，一次 CAS 保证原子性。线程池五状态流转：RUNNING → SHUTDOWN → STOP → TIDYING → TERMINATED。阿里规约禁止 Executors 创建线程池——newFixedThreadPool 无界队列 OOM，newCachedThreadPool 无限线程 OOM
