# Nginx 底层原理深度解析
——从多进程架构到事件驱动，从 HTTP 处理阶段到负载均衡

> **阅读目标**：不翻 Nginx 源码，也能掌握 Nginx 的多进程架构、epoll 事件驱动模型、HTTP 请求处理的 11 个阶段、负载均衡算法、反向代理与缓存机制的底层原理。
>
> **前置知识**：Linux epoll、多进程、HTTP 协议基础、负载均衡概念。

---

## 文档导航

```
┌─────────────────────────────────────────────────────┐
│            Nginx 底层原理深度解析                  │
├─────────────────────────────────────────────────┤
│  第一部分：架构与进程模型                        │
│    1. Nginx 架构全景图                          │
│    2. Master-Worker 多进程模型                  │
│    3. 热部署与平滑升级                          │
│    4. Worker 进程的数量与亲和性                  │
├─────────────────────────────────────────────────┤
│  第二部分：事件驱动模型                          │
│    5. epoll 事件驱动核心原理                    │
│    6. Nginx 事件循环（ngx_event_core_module）    │
│    7. 连接池与请求内存管理                      │
│    8. 惊群问题与 accept_mutex 解决方案          │
├─────────────────────────────────────────────────┤
│  第三部分：HTTP 请求处理 11 个阶段              │
│    9. HTTP 处理阶段全景图                       │
│   10. post-read 阶段（读取请求头）              │
│   11. uri rewrite 阶段（URL 重写）              │
│   12. find-config 阶段（配置查找）               │
│   13. pre-access 阶段（访问预处理）              │
│   14. access 阶段（访问控制）                   │
│   15. access-content 阶段（内容访问）            │
│   16. content 阶段（内容生成）                   │
│   17. log 阶段（日志记录）                      │
├─────────────────────────────────────────────────┤
│  第四部分：负载均衡与反向代理                    │
│   18. 反向代理原理（proxy_pass）                │
│   19. 负载均衡 6 种算法                       │
│   20. upstream 模块源码分析                     │
│   21. 健康检查与故障转移                        │
├─────────────────────────────────────────────────┤
│  第五部分：缓存机制                            │
│   22. proxy_cache 原理                         │
│   23. 缓存失效策略（proxy_cache_valid）          │
│   24. 缓存命中率优化                           │
├─────────────────────────────────────────────────┤
│  第六部分：限流与安全                          │
│   25. limit_req（漏桶算法）                    │
│   26. limit_conn（连接数限制）                  │
│   27. 与 Spring Cloud Gateway 对比             │
├─────────────────────────────────────────────────┤
│  第七部分：面试高频题                          │
│   28. Nginx 面试 15 问                        │
├─────────────────────────────────────────────────┤
│  附录                                          │
│   附录 A：Nginx vs Spring Cloud Gateway 对比     │
│   附录 B：Nginx 配置优化参数速查表              │
│   附录 C：本文档与之前文档的衔接关系            │
└─────────────────────────────────────────────────┘
```

---

# 第一部分：架构与进程模型

## 1. Nginx 架构全景图

### 1.1 核心架构

```
Nginx 多进程架构全景图：

    ┌──────────────────────────────────────────────────────┐
    │                   Master 进程                         │
    │  （管理员，不处理请求）                             │
    │  - 读取配置文件                                    │
    │  - 管理 Worker 进程（启动/停止/热部署）             │
    │  - 接收信号（HUP/USR1/USR2/WINCH）              │
    └────────────┬─────────────┬─────────────┬───────────┘
                 │             │             │
                 ▼             ▼             ▼
    ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
    │ Worker 进程 1 │ │ Worker 进程 2 │ │ Worker 进程 N │
    │               │ │               │ │               │
    │ epoll 事件循环│ │ epoll 事件循环│ │ epoll 事件循环│
    │ ↓             │ │ ↓             │ │ ↓             │
    │ 处理请求      │ │ 处理请求      │ │ 处理请求      │
    └──────────────┘ └──────────────┘ └──────────────┘
                 │             │             │
                 ▼             ▼             ▼
    ┌──────────────────────────────────────────────────────┐
    │              共享内存（SHM）                          │
    │  - 缓存数据                                        │
    │  - 限流计数器                                      │
    │  - upstream 健康状态                                │
    └──────────────────────────────────────────────────────┘
```

### 1.2 为什么用多进程而不是多线程？

| 特性               | 多进程（Nginx）     | 多线程（Apache/Tomcat） |
|--------------------|----------------------|--------------------------|
| 稳定性              | 高（进程隔离）        | 低（线程共享内存，一个崩溃影响所有） |
| 内存占用            | 低（共享代码段）      | 高（每个线程独立栈）        |
| 上下文切换          | 高（进程切换）        | 低（线程切换）              |
| 利用多核            | 支持（worker_processes auto） | 支持                |
| 开发复杂度          | 低（无锁）           | 高（需要线程安全）          |

**Nginx 的选择**：多进程 + 事件驱动（每个进程内部单线程），兼顾稳定性和高性能。

---

## 2. Master-Worker 多进程模型

### 2.1 Master 进程的职责

**Master 进程不处理任何请求**，它只负责管理 Worker 进程：

```c
// nginx.c → ngx_master_process_cycle()
void ngx_master_process_cycle(ngx_cycle_t *cycle) {
    // 1. 设置信号监听（HUP/USR1/USR2/WINCH/TERM/QUIT）
    ngx_setup_signals();
    
    // 2. 启动 Worker 进程
    ngx_start_workers(cycle);
    
    // 3. 进入信号循环（不退出）
    for (;;) {
        // 监听信号
        sigsuspend(&set);
        
        // 处理信号
        switch (signo) {
            case SIGHUP:
                // 重新读取配置文件，启动新 Worker
                ngx_reconfigure = 1;
                break;
            case SIGUSR1:
                // 重新打开日志文件
                ngx_reopen = 1;
                break;
            case SIGUSR2:
                // 热部署：启动新版本的 Worker
                ngx_change_binary = 1;
                break;
            case SIGWINCH:
                // 优雅关闭 Worker（不接收新连接）
                ngx_noaccept = 1;
                break;
            case SIGTERM:
            case SIGQUIT:
                // 立即停止/优雅停止
                ngx_terminate = 1;
                break;
        }
        
        // 根据信号执行对应操作
        if (ngx_reconfigure)
            ngx_reconfigure_workers();
        if (ngx_reopen)
            ngx_reopen_files();
        if (ngx_change_binary)
            ngx_exec_new_binary();
        // ...
    }
}
```

### 2.2 Worker 进程的启动

```c
// nginx.c → ngx_start_workers()
static void ngx_start_workers(ngx_cycle_t *cycle) {
    ngx_int_t i;
    ngx_channel_t ch;
    
    // 根据 worker_processes 配置，启动对应数量的 Worker
    for (i = 0; i < ccf->worker_processes; i++) {
        // fork() 创建子进程
        pid = fork();
        
        if (pid == 0) {
            // 子进程：Worker 进程
            ngx_worker_process_cycle(cycle, i);
            // 不会返回
        }
        
        // 父进程（Master）：记录 Worker 的 pid
        ngx_processes[i].pid = pid;
        ngx_processes[i].exited = 0;
    }
}
```

### 2.3 Worker 进程的事件循环

**Worker 进程的核心是一个事件循环**（详见第 6 节）：

```c
// nginx.c → ngx_worker_process_cycle()
void ngx_worker_process_cycle(ngx_cycle_t *cycle, ngx_int_t worker) {
    // 1. 初始化：设置 CPU 亲和性、打开监听 socket
    ngx_worker_process_init(cycle, worker);
    
    // 2. 进入事件循环（不退出）
    for (;;) {
        // 处理事件（epoll_wait）
        ngx_process_events_and_timers(cycle);
        
        // 检查是否需要退出
        if (ngx_terminate || ngx_quit)
            break;
    }
    
    // 3. 清理资源
    ngx_worker_process_exit(cycle);
}
```

---

## 3. 热部署与平滑升级

### 3.1 热部署原理（不停机升级）

**问题**：如何升级 Nginx 二进制文件，但不中断正在处理的请求？

**Nginx 的解决方案**：Master 进程启动**新版本的 Worker**，旧版本的 Worker 优雅退出。

**热部署步骤**：

```
Step 1：替换 Nginx 二进制文件
  $ cp nginx nginx.old
  $ cp new_nginx nginx

Step 2：向 Master 进程发送 USR2 信号
  $ kill -USR2 $(cat /var/run/nginx.pid)
  Master 进程：
    - 重命名 pid 文件为 nginx.pid.oldbin
    - 启动新版本的 Master + Worker

Step 3：向旧 Master 发送 WINCH 信号（优雅关闭旧 Worker）
  $ kill -WINCH $(cat /var/run/nginx.pid.oldbin)
  旧 Worker 不再接收新连接，处理完现有请求后退出

Step 4：验证新版本是否正常
  $ nginx -v   # 确认新版本
  $ curl localhost  # 确认服务正常

Step 5：如果正常，向旧 Master 发送 QUIT 信号（彻底退出）
  $ kill -QUIT $(cat /var/run/nginx.pid.oldbin)

  （如果新版本有问题，可以回滚：向新 Master 发送 QUIT，向旧 Master 发送 HUP）
```

### 3.2 平滑重载配置（SIGHUP）

```
$ nginx -s reload
  # 等价于：kill -HUP $(cat /var/run/nginx.pid)

Master 进程收到 HUP 信号后：
  1. 重新读取配置文件（nginx.conf）
  2. 启动新 Worker 进程（使用新配置）
  3. 向旧 Worker 发送 QUIT 信号（优雅退出）
  4. 旧 Worker 处理完现有请求后退出

# 整个过程不停机！
```

---

## 4. Worker 进程的数量与亲和性

### 4.1 worker_processes 配置

```nginx
# nginx.conf
worker_processes auto;  # 自动设置为 CPU 核心数
```

**为什么是 CPU 核心数？**
- 每个 Worker 是单线程的，同一时刻只能利用一个 CPU 核心
- 设置多于 CPU 核心数 → 进程切换开销
- 设置少于 CPU 核心数 → CPU 浪费

### 4.2 worker_cpu_affinity（CPU 亲和性）

```nginx
# 绑定每个 Worker 到特定 CPU 核心（避免进程切换）
worker_processes 4;
worker_cpu_affinity 0001 0010 0100 1000;
#                      ↑    ↑    ↑    ↑
#                    CPU0 CPU1 CPU2 CPU3
```

**作用**：减少 CPU 缓存失效（Cache Miss），提升性能。

---

# 第二部分：事件驱动模型

## 5. epoll 事件驱动核心原理

### 5.1 为什么需要事件驱动？

**传统阻塞 I/O 模型的问题**：

```
Apache/Tomcat 的多线程模型：

  每个连接 → 一个线程
  线程在 I/O 时阻塞（等待客户端发送数据）
  10K 连接 → 10K 线程 → 内存耗尽 + 上下文切换开销

  内存占用：每个线程 1 MB 栈 → 10K 线程 = 10 GB 内存！
```

**事件驱动模型的优势**：

```
Nginx 的事件驱动模型：

  所有连接共享一个线程（每个 Worker 单线程）
  线程不阻塞在 I/O 上，而是：
    1. 调用 epoll_wait() 等待事件（阻塞，但只阻塞一个线程）
    2. 有事件到达 → 处理事件
    3. 处理完 → 回到 epoll_wait()

  10K 连接 → 1 个线程 → 内存占用 < 10 MB
```

### 5.2 epoll vs select/poll

| 特性               | select       | poll          | epoll                |
|--------------------|--------------|---------------|----------------------|
| 最大连接数          | 1024（固定） | 无限制        | 无限制                |
| 性能（活跃连接少）  | O(N)         | O(N)          | O(1)（只返回活跃连接） |
| 性能（活跃连接多）  | O(N)         | O(N)          | O(N)                 |
| 内核与用户空间拷贝  | 每次调用都拷贝 | 每次调用都拷贝 | 只拷贝一次（epoll_ctl） |
| 适合场景            | 跨平台        | 跨平台         | Linux 高性能服务器     |

**epoll 的核心优势**：只关心**活跃连接**，不关心所有连接。

### 5.3 epoll 的 3 个系统调用

```c
// 1. 创建 epoll 实例（返回 epoll 文件描述符）
int epfd = epoll_create1(0);

// 2. 注册/修改/删除 监听事件
struct epoll_event ev;
ev.events = EPOLLIN;   // 监听可读事件
ev.data.fd = sockfd;  // 绑定文件描述符
epoll_ctl(epfd, EPOLL_CTL_ADD, sockfd, &ev);

// 3. 等待事件（阻塞，直到有事件发生）
struct epoll_event events[MAX_EVENTS];
int nfds = epoll_wait(epfd, events, MAX_EVENTS, timeout);
// nfds = 活跃连接数
for (i = 0; i < nfds; i++) {
    // 只处理活跃连接（events[i]）
}
```

---

## 6. Nginx 事件循环

### 6.1 事件循环核心函数

```c
// event/ngx_event.c → ngx_process_events_and_timers()
void ngx_process_events_and_timers(ngx_cycle_t *cycle) {
    // 1. 尝试获取 accept_mutex（避免惊群，详见第 8 节）
    if (ngx_use_accept_mutex) {
        if (ngx_accept_disabled > 0) {
            // 当前 Worker 的连接数过多，暂时不抢 accept_mutex
            ngx_accept_disabled--;
        } else {
            ngx_shmtx_lock(&ngx_accept_mutex);
            // 获取锁成功，可以接收新连接
        }
    }
    
    // 2. 处理事件（调用 epoll_wait）
    (void) ngx_process_events(cycle, timer, flags);
    // 底层调用：epoll_wait(epfd, events, MAX_EVENTS, timeout)
    
    // 3. 处理定时事件（检查是否有定时器到期）
    ngx_event_expire_timers();
    
    // 4. 释放 accept_mutex
    if (ngx_use_accept_mutex)
        ngx_shmtx_unlock(&ngx_accept_mutex);
}
```

### 6.2 事件处理流程

```
Nginx 事件处理流程：

    epoll_wait() 返回活跃事件
           ↓
    ┌──────────────────────────────────────────────┐
    │  遍历所有活跃事件                            │
    │  1. 如果是新连接事件（EPOLLIN on listen fd）│
    │     → 调用 accept() 接受连接               │
    │     → 将新连接加入 epoll 监听               │
    │  2. 如果是数据到达事件（EPOLLIN on client fd）│
    │     → 读取数据（recv()）                   │
    │     → 解析 HTTP 请求                       │
    │     → 进入 HTTP 处理阶段（详见第三部分）      │
    │  3. 如果是数据可写事件（EPOLLOUT）         │
    │     → 发送数据（send()）                   │
    └──────────────────────────────────────────────┘
           ↓
    处理完所有事件
           ↓
    检查定时器（过期定时器回调）
           ↓
    回到 epoll_wait()
```

### 6.3 超时机制

Nginx 使用**红黑树**管理定时事件：

```c
// 定时事件管理（红黑树，按超时时间排序）
ngx_rbtree_t  ngx_event_timer_rbtree;
ngx_rbtree_node_t  ngx_event_timer_sentinel;

// 添加定时器
void ngx_event_add_timer(ngx_event_t *ev, ngx_msec_t timer) {
    ngx_msec_t  key;
    key = ngx_current_msec + timer;  // 超时时间 = 当前时间 + 延迟
    
    ev->timer.key = key;
    ngx_rbtree_insert(&ngx_event_timer_rbtree, &ev->timer);
}

// epoll_wait 的 timeout 计算
ngx_msec_t timer = ngx_event_find_timer();  // 找到最近的定时器
// 如果最近定时器 100ms 后到期，timeout = 100
// 如果没有定时器，timeout = -1（永久阻塞）
int nfds = epoll_wait(epfd, events, MAX_EVENTS, timer);
```

---

## 7. 连接池与请求内存管理

### 7.1 连接池

Nginx 预先分配**连接池**（避免频繁分配内存）：

```c
// 在 Worker 启动时，预先分配 connection 数组
ngx_connection_t *ngx_get_connection(ngx_socket_t s, ngx_log_t *log) {
    ngx_connection_t *c;
    
    // 从连接池获取一个空闲连接
    c = ngx_cycle->free_connections;
    if (c == NULL) {
        // 连接池耗尽（达到 worker_connections 上限）
        ngx_log_error(NGX_LOG_ALERT, log, 0,
                      "worker_connections are not enough");
        return NULL;
    }
    
    ngx_cycle->free_connections = c->data;
    ngx_cycle->free_connection_n--;
    
    // 初始化连接
    c->fd = s;
    c->read = &ngx_cycle->read_events[c->id];
    c->write = &ngx_cycle->write_events[c->id];
    
    return c;
}
```

**连接池大小配置**：

```nginx
worker_connections 1024;  # 每个 Worker 最大并发连接数
# 总并发 = worker_processes * worker_connections
# 如果是反向代理，需要 ×2（前端连接 + 后端连接）
```

### 7.2 请求内存池

每个 HTTP 请求有独立的**内存池**（请求结束自动释放）：

```c
// 请求内存池
typedef struct {
    ngx_pool_t *pool;  // 内存池
    ngx_buf_t *buf;     // 缓冲区
    // ...
} ngx_http_request_t;

// 请求开始时创建内存池
r->pool = ngx_create_pool(ngx_http_request_body_chunked,
                           ngx_http_request_body);
// 请求处理完后，一次性释放所有内存（避免内存泄漏）
ngx_destroy_pool(r->pool);
```

**优势**：不需要手动 free() 每个分配的内存，请求结束自动清理。

---

## 8. 惊群问题与 accept_mutex

### 8.1 惊群问题

**问题**：多个 Worker 进程都在 listen 同一个 socket，当新连接到达时，**所有 Worker 都被唤醒**，但只有一个能 accept 成功。

```
惊群问题图解：

    新连接到达
         ↓
    ┌────┬────┬────┐
    │ W1 │ W2 │ W3 │  ← 所有 Worker 都被 epoll_wait 唤醒
    └────┴────┴────┘
         ↓
    W1：accept() 成功
    W2：accept() 失败（返回 EAGAIN）
    W3：accept() 失败（返回 EAGAIN）
    ↑
    无效的进程唤醒（浪费 CPU）
```

### 8.2 accept_mutex 解决方案

Nginx 使用 **accept_mutex（互斥锁）** 保证同一时刻只有一个 Worker 能 accept 新连接：

```c
// 在 ngx_process_events_and_timers() 中
if (ngx_use_accept_mutex) {
    // 尝试获取 accept_mutex
    if (ngx_shmtx_trylock(&ngx_accept_mutex)) {
        // 获取成功：可以 accept 新连接
        ngx_accept_mutex_held = 1;
        // 将 listen socket 加入 epoll 监听
        ngx_enable_accept_events(cycle);
    } else {
        // 获取失败：不能 accept 新连接
        ngx_accept_mutex_held = 0;
        // 将 listen socket 从 epoll 移除
        ngx_disable_accept_events(cycle);
    }
}
```

**accept_mutex 的阈值控制**：

```c
// 当 Worker 的连接数超过 worker_connections 的 7/8 时，
// 暂时不抢 accept_mutex（让给其他 Worker）
if (ngx_cycle->connection_n / 8 > ngx_cycle->free_connection_n) {
    ngx_accept_disabled = 1;
}
```

### 8.3 Linux 4.5+ 的 EPOLLEXCLUSIVE

**新方案**：Linux 4.5+ 支持 `EPOLLEXCLUSIVE` 标志，内核保证**只有一个进程被唤醒**：

```c
// 新版本 Nginx（1.11.3+）支持 EPOLLEXCLUSIVE
ev.events = EPOLLIN | EPOLLEXCLUSIVE;
epoll_ctl(epfd, EPOLL_CTL_ADD, listen_fd, &ev);
// 内核保证：新连接到达时，只唤醒一个 Worker
```

**为什么 Nginx 还保留 accept_mutex？**
- 兼容性：老版本 Linux 不支持 EPOLLEXCLUSIVE
- 负载均衡：accept_mutex 的阈值控制可以实现更精细的负载均衡

---

---

## 9. HTTP 处理阶段全景图

### 9.1 HTTP 11 个处理阶段

Nginx 将 HTTP 请求处理分为 **11 个阶段**，每个阶段由不同的模块处理：

```
HTTP 请求处理 11 个阶段（按执行顺序）：

    ┌───────┬──────────────────────────────────────────────────────┐
    │ 阶段   │ 名称                │ 常用模块                     │
    ├───────┼──────────────────────────────────────────────────────┤
    │  1     │ post-read           │ ngx_http_realip_module       │
    │  2     │ server-rewrite     │ ngx_http_rewrite_module      │
    │  3     │ find-config         │ ngx_http_core_module         │
    │  4     │ rewrite             │ ngx_http_rewrite_module      │
    │  5     │ post-rewrite        │ ngx_http_rewrite_module      │
    │  6     │ preaccess           │ ngx_http_limit_conn_module   │
    │  7     │ access              │ ngx_http_access_module       │
    │        │                     │ ngx_http_auth_basic_module   │
    │  8     │ post-access         │ ngx_http_access_module       │
    │  9     │ precontent          │ （预留，少用）                │
    │ 10     │ content             │ ngx_http_proxy_module        │
    │        │                     │ ngx_http_fastcgi_module      │
    │        │                     │ ngx_http_static_module        │
    │ 11     │ log                 │ ngx_http_log_module          │
    └───────┴──────────────────────────────────────────────────────┘
```

### 9.2 阶段执行流程图

```
HTTP 请求处理完整流程：

    客户端请求到达
         ↓
    ┌──────────────────────────────────────────────────────┐
    │  Phase 1：post-read（读取请求头）                   │
    │  - 读取 HTTP 请求行 + 请求头                       │
    │  - realip 模块：获取真实客户端 IP（X-Forwarded-For）│
    └──────────────────────┬─────────────────────────────┘
                           ↓
    ┌──────────────────────────────────────────────────────┐
    │  Phase 2：server-rewrite（Server 块内重写）         │
    │  - 执行 server {} 块内的 rewrite 指令              │
    └──────────────────────┬─────────────────────────────┘
                           ↓
    ┌──────────────────────────────────────────────────────┐
    │  Phase 3：find-config（查找 Location 配置）         │
    │  - 根据 URI 匹配 location {} 块                    │
    │  - 找到最具体的 location                            │
    └──────────────────────┬─────────────────────────────┘
                           ↓
    ┌──────────────────────────────────────────────────────┐
    │  Phase 4：rewrite（Location 块内重写）             │
    │  - 执行 location {} 块内的 rewrite 指令            │
    │  - 如果重写后 URI 变化，回到 Phase 3（重新匹配）  │
    └──────────────────────┬─────────────────────────────┘
                           ↓
    ┌──────────────────────────────────────────────────────┐
    │  Phase 5：post-rewrite（重写后处理）               │
    │  - 如果重写了 URI，发起内部跳转（internal redirect） │
    └──────────────────────┬─────────────────────────────┘
                           ↓
    ┌──────────────────────────────────────────────────────┐
    │  Phase 6：preaccess（访问预处理）                  │
    │  - limit_conn（限制连接数）                        │
    │  - limit_req（限制请求速率）                       │
    └──────────────────────┬─────────────────────────────┘
                           ↓
    ┌──────────────────────────────────────────────────────┐
    │  Phase 7：access（访问控制）                        │
    │  - allow/deny（IP 白名单/黑名单）                 │
    │  - auth_basic（HTTP 基本认证）                     │
    └──────────────────────┬─────────────────────────────┘
                           ↓
    ┌──────────────────────────────────────────────────────┐
    │  Phase 8：post-access（访问后处理）                 │
    │  - 如果 access 阶段返回非 200，处理拒绝逻辑        │
    └──────────────────────┬─────────────────────────────┘
                           ↓
    ┌──────────────────────────────────────────────────────┐
    │  Phase 9：precontent（内容预处理，预留）            │
    │  - 通常不使用                                     │
    └──────────────────────┬─────────────────────────────┘
                           ↓
    ┌──────────────────────────────────────────────────────┐
    │  Phase 10：content（内容生成）                      │
    │  - 静态文件：ngx_http_static_module                 │
    │  - 反向代理：ngx_http_proxy_module（proxy_pass）    │
    │  - FastCGI：ngx_http_fastcgi_module                │
    │  - 生成 HTTP 响应体                                │
    └──────────────────────┬─────────────────────────────┘
                           ↓
    ┌──────────────────────────────────────────────────────┐
    │  Phase 11：log（日志记录）                          │
    │  - 写入 access.log                                 │
    │  - 写入 error.log（如果有错误）                     │
    └──────────────────────┴─────────────────────────────┘
                           ↓
    发送响应给客户端
```

---

## 10. post-read 阶段（读取请求头）

### 10.1 请求头读取过程

```c
// http/ngx_http_parse.c → ngx_http_parse_request_line()
ngx_int_t ngx_http_parse_request_line(ngx_http_request_t *r, ngx_buf_t *b) {
    // 解析请求行（GET /uri HTTP/1.1）
    // 状态机解析，支持流式读取（不要求一次读完）
    
    switch (state) {
        case sw_start:
            // 读取方法（GET/POST/...）
            r->method_start = p;
            break;
        case sw_uri:
            // 读取 URI
            r->uri_start = p;
            break;
        case sw_version:
            // 读取版本（HTTP/1.0 或 HTTP/1.1）
            r->http_major = major;
            r->http_minor = minor;
            break;
    }
}

// http/ngx_http_parse.c → ngx_http_parse_header_line()
ngx_int_t ngx_http_parse_header_line(ngx_http_request_t *r, ngx_buf_t *b) {
    // 解析请求头（Key: Value\r\n）
    // 存储在 r->headers_in 哈希表中
}
```

### 10.2 realip 模块（获取真实客户端 IP）

**问题**：当 Nginx 前面有负载均衡器（如 ELB、CDN）时，`$remote_addr` 是负载均衡器的 IP，不是真实客户端 IP。

**解决方案**：从 `X-Forwarded-For` 或 `X-Real-IP` 请求头中提取真实 IP。

```nginx
# 配置示例
set_real_ip_from  10.0.0.0/8;     # 信任的代理 IP 段
real_ip_header    X-Forwarded-For;  # 从哪个请求头获取真实 IP
real_ip_recursive on;                # 递归排除信任的代理 IP
```

**执行阶段**：post-read（Phase 1），在读取请求头后立即执行。

---

## 11. uri rewrite 阶段（URL 重写）

### 11.1 rewrite 指令原理

`rewrite` 指令使用 **PCRE 正则表达式**匹配 URI，并重写为新 URI：

```nginx
# 语法
rewrite <regex> <replacement> [flag];

# 示例
rewrite ^/old/(.*)$ /new/$1 permanent;  # 301 重定向
rewrite ^/api/(.*)$ /$1 last;          # 内部跳转，重新匹配 location
```

**flag 的 4 种取值**：

| flag        | 含义                                      | 是否重新匹配 location |
|-------------|-------------------------------------------|----------------------|
| `last`      | 用重写后的 URI 重新发起 location 匹配        | 是                   |
| `break`     | 不再重新匹配，在当前 location 继续执行        | 否                   |
| `redirect`  | 返回 302 临时重定向                        | —                    |
| `permanent` | 返回 301 永久重定向                        | —                    |

### 11.2 rewrite 执行源码

```c
// http/ngx_http_rewrite_module.c → ngx_http_rewrite_handler()
ngx_int_t ngx_http_rewrite_handler(ngx_http_request_t *r) {
    ngx_http_rewrite_ctx_t *ctx;
    ngx_http_script_code_t *code;
    ngx_str_t uri;
    
    // 1. 遍历 rewrite 规则
    for (i = 0; i < rlcf->codes->nelts; i++) {
        code = rlcf->codes->elts[i];
        
        // 2. 执行正则表达式匹配
        rc = ngx_http_script_run(r, &uri, code->ip, ...);
        
        if (rc == NGNX_DECLINED) {
            // 不匹配，继续下一条 rewrite 规则
            continue;
        }
        
        if (rc == NGNX_OK) {
            // 匹配成功，重写 URI
            r->uri = uri;
            r->internal = 1;  // 标记为内部跳转
            
            // 3. 根据 flag 处理
            if (code->flags & NGX_HTTP_SCRIPT_REWRITE_LAST) {
                // last：重新发起 location 匹配
                r->phase_hendler = ngx_http_core_find_location_phase;
                return NGX_DECLINED;
            }
            if (code->flags & NGX_HTTP_SCRIPT_REWRITE_BREAK) {
                // break：停止重写，继续执行当前 location
                break;
            }
            // redirect/permanent：返回重定向响应
            return ngx_http_send_redirect(r);
        }
    }
}
```

---

## 12. find-config 阶段（配置查找）

### 12.1 location 匹配规则

Nginx 使用**前缀树 + 正则表达式**匹配 location：

```nginx
# 匹配优先级（从高到低）：

# 1. = 精确匹配（最高优先级）
location = /uri { ... }

# 2. ^~ 前缀匹配（如果匹配，不再检查正则）
location ^~ /static/ { ... }

# 3. ~ 或 ~* 正则表达式匹配（按配置文件顺序，第一个匹配即停止）
location ~ \.php$ { ... }       # 区分大小写
location ~* \.(jpg|png)$ { ... }  # 不区分大小写

# 4. 普通前缀匹配（最长前缀）
location /static/ { ... }
location / { ... }
```

**匹配过程源码**：

```c
// http/ngx_http_core_module.c → ngx_http_find_location()
ngx_int_t ngx_http_find_location(ngx_http_request_t *r) {
    ngx_http_core_loc_conf_t *clcf;
    ngx_queue_t *q;
    ngx_http_location_queue_t *lq;
    
    // 1. 先检查精确匹配（=）
    if (ngx_http_find_location_exact(r) != NULL) {
        return NGX_OK;  // 精确匹配成功，不再检查其他
    }
    
    // 2. 检查前缀匹配（包括 ^~）
    clcf = ngx_http_find_location_prefix(r);
    
    // 3. 如果不是 ^~，继续检查正则表达式匹配（~ 或 ~*）
    if (!clcf->exact_match && !clcf->noregex) {
        clcf = ngx_http_find_location_regex(r);
    }
    
    // 4. 找到最终 location
    r->loc_conf = clcf->loc_conf;
    return NGX_OK;
}
```

---

## 13. pre-access / access / post-access 阶段（访问控制）

### 13.1 限流模块（limit_req / limit_conn）

**limit_req（漏桶算法）**：限制请求速率

```nginx
# 定义限流区域（10 MB 内存，每秒 10 个请求）
limit_req_zone $binary_remote_addr zone=one:10m rate=10r/s;

server {
    location /api/ {
        # 应用限流（突发最多 20 个请求）
        limit_req zone=one burst=20 nodelay;
    }
}
```

**漏桶算法原理**：

```
漏桶算法图解：

    请求到达 →  │●│●│●│●│●│  （请求队列，最多 burst 个）
                ↓
              漏桶（速率 = rate）
                ↓
              处理请求（匀速）

    如果队列满了（超过 burst），拒绝请求（返回 503）
    如果指定 nodelay：允许突发请求立即处理（不排队）
```

**limit_conn（连接数限制）**：

```nginx
# 限制每个 IP 的并发连接数（最多 10 个）
limit_conn_zone $binary_remote_addr zone=addr:10m;
limit_conn addr 10;
```

### 13.2 访问控制模块（allow / deny）

```nginx
location /admin/ {
    # 只允许内网 IP 访问
    allow 10.0.0.0/8;
    allow 192.168.0.0/16;
    deny all;
}
```

**执行阶段**：access（Phase 7）

```c
// http/ngx_http_access_module.c → ngx_http_access_handler()
ngx_int_t ngx_http_access_handler(ngx_http_request_t *r) {
    ngx_http_access_loc_conf_t *alcf;
    struct sockaddr_in *sin;
    in_addr_t addr;
    
    alcf = ngx_http_get_module_loc_conf(r, ngx_http_access_module);
    
    // 获取客户端 IP
    sin = (struct sockaddr_in *) r->connection->sockaddr;
    addr = sin->sin_addr.s_addr;
    
    // 遍历 allow/deny 规则（按配置文件顺序）
    for (i = 0; i < alcf->rules->nelts; i++) {
        rule = alcf->rules->elts[i];
        
        if ((addr & rule->mask) == rule->net) {
            // 匹配规则
            if (rule->deny)
                return NGX_HTTP_FORBIDDEN;  // 403
            else
                return NGX_DECLINED;  // 允许，继续处理
        }
    }
    
    // 默认拒绝（如果最后一条是 deny all）
    return NGX_HTTP_FORBIDDEN;
}
```

---

## 14. content 阶段（内容生成）

### 14.1 静态文件服务

Nginx 作为静态文件服务器时，content 阶段由 `ngx_http_static_module` 处理：

```c
// http/ngx_http_static_module.c → ngx_http_static_handler()
ngx_int_t ngx_http_static_handler(ngx_http_request_t *r) {
    ngx_buf_t *b;
    ngx_chain_t out;
    ngx_open_file_info_t of;
    
    // 1. 拼接文件路径（root + URI）
    path = ngx_http_map_uri_to_path(r, &path, &root, 0);
    
    // 2. 打开文件
    ngx_open_cached_file(clcf->open_file_cache, ...
    
    // 3. 设置响应头（Content-Type、Content-Length、Last-Modified）
    r->headers_out.content_type = ...
    r->headers_out.content_length_n = of.size;
    
    // 4. 使用 sendfile() 零拷贝发送文件（如果支持）
    if (clcf->sendfile) {
        r->allow_zero_size = 1;
        b->file = ngx_pcalloc(r->pool, sizeof(ngx_file_t));
        b->file_pos = 0;
        b->file_last = of.size;
        b->in_file = 1;  // 标记为文件内容（使用 sendfile）
    }
    
    // 5. 发送响应
    ngx_http_send_header(r);
    ngx_http_output_filter(r, &out);
}
```

**sendfile() 零拷贝**：

```
传统文件发送（4 次拷贝）：

    磁盘 → 内核缓冲区 → 用户缓冲区 → Socket 缓冲区 → 网卡

sendfile() 零拷贝（2 次拷贝）：

    磁盘 → 内核缓冲区 ──────────────→ 网卡
                              ↑
                        无需拷贝到用户空间
```

### 14.2 反向代理（proxy_pass）

`proxy_pass` 是 Nginx 作为反向代理的核心指令，content 阶段由 `ngx_http_proxy_module` 处理：

```nginx
location /api/ {
    proxy_pass http://backend;  # 转发到 upstream "backend"
    
    # 传递请求头
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    
    # 超时设置
    proxy_connect_timeout 5s;   # 连接后端超时
    proxy_read_timeout 30s;      # 读取后端响应超时
    proxy_send_timeout 30s;      # 发送请求到后端超时
}
```

**proxy_pass 执行流程**（详见第 18 节）：

```
1. 解析 proxy_pass 指令（获取 upstream 名称或具体 IP）
2. 负载均衡选择后端服务器（详见第 19 节）
3. 建立到后端的连接（或复用连接池中的连接）
4. 将客户端请求转发到后端
5. 读取后端响应
6. 将后端响应返回给客户端
```

---

---

## 15. upstream 模块（负载均衡）

### 15.1 upstream 结构体

```c
typedef struct {
    ngx_str_t name;           // upstream 名称（对应 upstream.conf 中的名称）
    ngx_addr_t *addrs;        // 后端服务器地址列表
    ngx_uint_t naddrs;         // 地址数量
    ngx_http_upstream_init_pt init_upstream;  // 初始化函数（选择负载均衡算法）
    ngx_http_upstream_init_peer_pt init;      // 初始化 peer（选择具体后端）
    void *data;                // 负载均衡算法数据（如轮询状态、权重等）
} ngx_http_upstream_srv_conf_t;
```

### 15.2 负载均衡 6 种算法

| 算法 | 指令 | 原理 | 适用场景 |
|------|------|------|----------|
| 轮询（默认） | 无（默认） | 按顺序依次选择后端 | 后端性能相近 |
| 加权轮询 | `server ... weight=N` | 按权重比例选择 | 后端性能不同 |
| IP Hash | `ip_hash;` | 根据客户端 IP 的 Hash 选择后端 | 需要会话保持 |
| 最少连接 | `least_conn;` | 选择当前连接数最少的后端 | 请求处理时间差异大 |
| Hash | `hash $key [consistent];` | 根据指定 Key 的 Hash 选择后端 | 需要会话保持（比 IP Hash 灵活） |
| Random | `random [two];` | 随机选择后端（two：选两个，选连接数少的） | 分布式缓存 |

#### 加权轮询算法源码（smooth weighted round-robin）

Nginx 使用**平滑加权轮询**（避免集中请求压到同一台）：

```c
// http/ngx_http_upstream_round_robin.c → ngx_http_upstream_get_peer()
ngx_int_t ngx_http_upstream_get_peer(...) {
    ngx_uint_t i, n;
    ngx_http_upstream_rr_peer_t *peer;
    
    // 1. 遍历所有后端，选择当前权重最高的
    for (i = 0; i < rrp->number; i++) {
        peer = &rrp->peer[i];
        
        if (peer->current_weight > best->current_weight) {
            best = peer;
            n = i;
        }
    }
    
    // 2. 选中的后端：current_weight -= total_weight
    best->current_weight -= rrp->total_weight;
    
    // 3. 所有后端：current_weight += weight（恢复权重）
    for (i = 0; i < rrp->number; i++) {
        rrp->peer[i].current_weight += rrp->peer[i].weight;
    }
    
    return n;
}
```

**示例**（3 台后端，权重 5:3:2）：

```
初始：current_weight = [5, 3, 2], total = 10

第 1 次：选中的是 Server1（5 最大）
  Server1: current_weight = 5 - 10 = -5
  恢复权重：[5, 3, 2] → [-5+5, -5+3, -5+2] = [0, -2, -3]
  
第 2 次：选出的是 Server2（0 > -2 > -3）
  Server2: current_weight = -2 - 10 = -12
  恢复权重：[0, -2, -3] → [0+5, -12+3, -12+2] = [5, -9, -10]
  
第 3 次：选中的是 Server1（5 最大）
  ...
  
执行序列：1, 2, 1, 3, 1, 2, 1, 2, 1, 3  （10 次内，1 出现 5 次，2 出现 3 次，3 出现 2 次）
```

### 15.3 健康检查

Nginx 开源版**没有主动健康检查**，只有被动健康检查（失败计数）：

```nginx
upstream backend {
    server 10.0.0.1:8080 max_fails=3 fail_timeout=30s;
    server 10.0.0.2:8080 max_fails=3 fail_timeout=30s;
}
```

**参数含义**：
- `max_fails`：在 `fail_timeout` 时间内，最多允许失败 `max_fails` 次
- `fail_timeout`：失败后，暂停使用该后端 `fail_timeout` 秒

**商业版 Nginx Plus** 才有主动健康检查：

```nginx
# Nginx Plus 才有
health_check interval=5s fails=3 passes=2;
```

---

## 16. 反向代理缓存机制

### 16.1 proxy_cache 原理

Nginx 反向代理可以缓存后端响应，减少后端压力：

```nginx
# 定义缓存区域
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=my_cache:10m max_size=1g inactive=60m;

server {
    location /api/ {
        proxy_pass http://backend;
        proxy_cache my_cache;           # 启用缓存
        proxy_cache_key "$method$request_uri";  # 缓存 Key
        proxy_cache_valid 200 302 10m;   # 200/302 缓存 10 分钟
        proxy_cache_valid 404 1m;        # 404 缓存 1 分钟
        proxy_cache_use_stale error timeout updating;  # 后端异常时使用过期缓存
    }
}
```

**缓存存储结构**：

```
/var/cache/nginx/
├── a/                    # 一级目录（levels=1:2，取 Key 的 MD5 最后 1 位）
│   └── bc/               # 二级目录（取 MD5 倒数 2~3 位）
│       └── <cache_file>  # 缓存文件（内容 + 元数据）
└── ...
```

### 16.2 缓存命中判断

```c
// http/ngx_http_proxy_module.c → ngx_http_proxy_cache()
ngx_int_t ngx_http_proxy_cache(ngx_http_request_t *r) {
    ngx_http_cache_t *c;
    ngx_str_t key;
    
    // 1. 计算缓存 Key（proxy_cache_key 指令）
    key = ngx_http_proxy_cache_key(r);
    
    // 2. 查找缓存（先查共享内存中的 Key 索引，再查磁盘文件）
    c = ngx_http_cache_new(r);
    rc = ngx_http_file_cache_open(r);
    
    if (rc == NGX_OK) {
        // 缓存命中！
        r->cached = 1;
        return ngx_http_cache_send(r);  // 直接返回缓存内容
    }
    
    if (rc == NGX_DECLINED) {
        // 缓存未命中，转发到后端
        return NGX_DECLINED;
    }
}
```

### 16.3 缓存失效策略

| 指令 | 含义 |
|------|------|
| `proxy_cache_valid <code> <time>` | 指定 HTTP 状态码的缓存时间 |
| `proxy_cache_key <key>` | 自定义缓存 Key（默认 `$scheme$request_method$host$request_uri`） |
| `proxy_cache_bypass $condition` | 满足条件时跳过缓存（直接到后端） |
| `proxy_cache_use_stale <events>` | 后端异常时，使用过期缓存（error/timeout/updating/http_500 等） |
| `proxy_cache_lock on` | 多个请求同时访问未缓存的内容时，只让一个请求去后端，其余等待 |

---

## 17. 热加载与平滑升级

### 17.1 配置文件热加载

```bash
# 重新加载配置（不中断服务）
nginx -s reload

# 等价于向 Master 进程发送 SIGHUP 信号
kill -SIGHUP $(cat /var/run/nginx.pid)
```

**reload 过程**：
1. Master 进程收到 SIGHUP
2. 重新读取 `nginx.conf`
3. 启动新的 Worker 进程（使用新配置）
4. 向旧 Worker 发送 SIGQUIT（优雅关闭）
5. 旧 Worker 处理完现有请求后退出

### 17.2 二进制热升级

```bash
# Step 1：备份旧二进制
cp /usr/sbin/nginx /usr/sbin/nginx.old

# Step 2：替换新二进制
cp /path/to/new/nginx /usr/sbin/nginx

# Step 3：向 Master 发送 SIGUSR2（启动新 Master）
kill -SIGUSR2 $(cat /var/run/nginx.pid)
# 此时有 2 个 Master 进程（旧 + 新），新 Master 启动了新 Worker

# Step 4：优雅关闭旧 Worker
kill -SIGWINCH $(cat /var/run/nginx.pid.oldbin)
# 旧 Worker 不再接收新连接，逐渐退出

# Step 5：确认新版本正常后，关闭旧 Master
kill -SIGQUIT $(cat /var/run/nginx.pid.oldbin)
```

---

## 18. Nginx 限流实战

### 18.1 limit_req（漏桶算法）

```nginx
# 定义限流区域：以客户端 IP 为 Key，每秒 10 个请求
limit_req_zone $binary_remote_addr zone=req_limit:10m rate=10r/s;

server {
    location /api/ {
        # 突发最多 20 个请求（放在队列里等待处理）
        limit_req zone=req_limit burst=20 nodelay;
    }
}
```

**参数说明**：
- `rate=10r/s`：每秒最多 10 个请求（即每 100ms 处理 1 个）
- `burst=20`：允许排队 20 个请求
- `nodelay`：排队的请求不延迟处理（超过 burst 的直接返回 503）

### 18.2 limit_conn（并发连接限制）

```nginx
# 定义连接数限制区域
limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

server {
    location /api/ {
        # 每个 IP 最多 10 个并发连接
        limit_conn conn_limit 10;
    }
}
```

---

## 19. Nginx 与 Spring Cloud Gateway 对比

详见附录 A。

---

## 20. 面试高频题

### 20.1 Nginx 面试 15 问

**Q1：Nginx 为什么采用多进程而不是多线程？**

```
答：
1. 稳定性：进程隔离，一个 Worker 崩溃不影响其他 Worker
2. 无锁：每个 Worker 单线程，不需要线程同步（无锁开销）
3. 内存：多进程共享代码段，只私有数据段，内存占用可控
4. 利用多核：每个 Worker 绑定一个 CPU 核心（worker_cpu_affinity）
```

**Q2：Nginx 的事件驱动模型是如何工作的？**

```
答：
1. Worker 进程启动后，进入事件循环（epoll_wait）
2. 新连接到达 → 唯一的 Worker（通过 accept_mutex 或 EPOLLEXCLUSIVE 抢到）调用 accept()
3. 将新连接的 socket 加入 epoll 监听
4. 客户端发送请求 → epoll 通知 Worker
5. Worker 读取请求、解析、处理、发送响应（全程非阻塞）
6. 处理完 → 回到 epoll_wait 等待下一个事件
```

**Q3：Nginx 如何处理 10K 并发连接？**

```
答：
1. 事件驱动：10K 连接共享一个 Worker 线程（而不是 10K 线程）
2. epoll：只关心活跃连接，不遍历所有连接（O(1) 复杂度）
3. 内存池：连接对象预分配（避免频繁 malloc/free）
4. 零拷贝：sendfile() 直接把文件从磁盘发送到 Socket（不过用户空间）
```

**Q4：Nginx 的惊群问题是如何解决的？**

```
答：
两种方案（Nginx 同时支持）：
1. accept_mutex：Worker 争抢文件锁，只有抢到的才能 accept 新连接
2. EPOLLEXCLUSIVE（Linux 4.5+）：内核保证只有一个 Worker 被唤醒
```

**Q5：Nginx 的 HTTP 处理阶段有哪些？**

```
答：共 11 个阶段：
post-read → server-rewrite → find-config → rewrite → post-rewrite
→ pre-access → access → post-access → precontent → content → log
```

**Q6：Nginx 的 rewrite 指令中 last 和 break 的区别？**

```
答：
last：重写 URI 后，重新发起 location 匹配（可能匹配到另一个 location）
break：重写 URI 后，不再重新匹配，在当前 location 内继续执行
```

**Q7：Nginx 的 upstream 负载均衡算法有哪些？**

```
答：
1. 轮询（默认）
2. 加权轮询（weight）
3. IP Hash（ip_hash）
4. 最少连接（least_conn）
5. Hash（hash $key）
6. Random（random）
```

**Q8：Nginx 的平滑升级是如何实现的？**

```
答：
1. 替换 Nginx 二进制文件
2. 向旧 Master 发送 SIGUSR2（启动新 Master + 新 Worker）
3. 向旧 Master 发送 SIGWINCH（旧 Worker 优雅退出）
4. 确认新版本正常后，向旧 Master 发送 SIGQUIT
```

**Q9：Nginx 的反向代理缓存是如何工作的？**

```
答：
1. 第一次请求：Nginx 转发到后端，拿到响应后存入缓存
2. 后续请求：Nginx 直接返回缓存内容（不转发到后端）
3. 缓存 Key：由 proxy_cache_key 定义（默认是 $request_uri）
4. 缓存失效：由 proxy_cache_valid 定义（按 HTTP 状态码设置 TTL）
```

**Q10：Nginx 的 limit_req 是如何实现的？**

```
答：
使用漏桶算法（Leaky Bucket）：
1. 每个 IP 有一个"桶"，桶里是允许的请求数
2. 请求到达时，从桶里取一个"令牌"
3. 如果桶空了，拒绝请求（返回 503）
4. 桶以固定速率填充（rate=10r/s → 每 100ms 填充 1 个令牌）
```

---

# 附录

## 附录 A：Nginx vs Spring Cloud Gateway 对比

| 维度 | Nginx | Spring Cloud Gateway |
|------|-------|----------------------|
| 语言/运行时 | C + epoll（进程级） | Java + Netty（JVM） |
| 线程模型 | 多进程 + 事件驱动（每 Worker 单线程） | 多线程 + Reactor（EventLoop） |
| 性能 | 极高（静态文件 ~10 万 QPS） | 较高（~1~2 万 QPS） |
| 配置方式 | 配置文件（nginx.conf） | Java DSL / YAML |
| 动态路由 | 需 reload（或 OpenResty Lua） | 动态（配合 Nacos） |
| 协议支持 | HTTP/1.0/1.1、HTTPS、HTTP/2、gRPC | HTTP/1.1、HTTPS、WebSocket、gRPC |
| 负载均衡 | 内置（6 种算法） | 配合 Ribbon / Spring Cloud LoadBalancer |
| 限流 | limit_req / limit_conn（本地） | RequestRateLimiter（配合 Redis） |
| 熔断 | 无（需 Nginx Plus 或 OpenResty） | 内置（配合 Resilience4j / Sentinel） |
| 认证/鉴权 | 基本（auth_basic） | 丰富（配合 Spring Security / OAuth2） |
| 可扩展性 | 低（需写 C 模块或 Lua） | 高（Java 代码，易扩展） |
| 适合场景 | 边缘网关（接入层）、静态文件、SSL 终结 | 微服务内部网关、复杂业务逻辑 |

---

## 附录 B：Nginx 配置优化参数速查表

```
┌──────────────────────────────────────────────────────────────────────┐
│                  Nginx 配置优化参数速查表                           │
├────────────────────────────┬──────────┬──────────────────────────┤
│ 参数                           │ 默认值    │ 调优建议                      │
├────────────────────────────┼──────────┼──────────────────────────┤
│ worker_processes              │ auto      │ CPU 核心数                    │
│ worker_connections           │ 1024      │ 65535（配合 ulimit -n）       │
│ worker_cpu_affinity         │ off       │ on（绑定 CPU，减少 Cache Miss）│
│ epoll_events                │ 512       │ 1024（高并发场景）             │
│ multi_accept               │ off       │ on（一次 accept 多个连接）     │
│ sendfile                    │ off       │ on（零拷贝发送文件）            │
│ tcp_nopush                 │ off       │ on（合并 TCP 包，提升吞吐量）  │
│ tcp_nodelay                │ on        │ on（禁用 Nagle，低延迟）       │
│ keepalive_timeout           │ 75s       │ 65s（配合上游）                │
│ keepalive_requests          │ 100       │ 1000（减少连接重建开销）        │
│ proxy_cache                │ off       │ on（启用反向代理缓存）          │
│ proxy_cache_min_uses       │ 1         │ 3（访问 3 次后才缓存）        │
│ proxy_cache_use_stale      │ off       │ error timeout updating         │
│ limit_req_zone             │ —         │ 按 IP 限流（10r/s）           │
│ limit_conn_zone            │ —         │ 按 IP 限连接（10 个）         │
│ client_max_body_size       │ 1m        │ 100m（支持大文件上传）         │
│ proxy_read_timeout         │ 60s       │ 30s（快速失败）                │
│ proxy_connect_timeout      │ 60s       │ 5s（快速失败）                 │
└────────────────────────────┴──────────┴──────────────────────────┘
```

---

## 附录 C：本文档与之前文档的衔接关系

```
┌──────────────────────────────────────────────────────────────────────┐
│                  Nginx 文档在知识链路中的位置                         │
├──────────────────────────────────────────────────────────────────────┤
│  前置文档：                                                         │
│  - Spring Cloud Gateway 源码 → 理解反向代理和网关                   │
│  - Redis 数据结构 → 理解 Nginx 的 limit_req 配合 Redis 实现分布式限流 │
│  - MySQL 索引 → 理解 Nginx 作为接入层如何保护数据库               │
│                                                                      │
│  本文档：                                                             │
│  - Nginx 多进程架构、事件驱动、HTTP 处理阶段、负载均衡、反向代理缓存   │
│                                                                      │
│  后续建议学习的文档：                                                   │
│  - Nginx 高级功能（OpenResty Lua、gRPC 代理、HTTP/2 配置）         │
│  - 微服务接入层设计（Nginx + Gateway 双层网关架构）                 │
│  - 分布式限流/降级（Nginx limit_req + Redis + Sentinel）            │
└──────────────────────────────────────────────────────────────────────┘
```

---

*文档结束*

> **下一步学习建议**：
> 1. 如果关注**高性能接入层**：学习 Nginx + OpenResty（Lua 脚本扩展）
> 2. 如果关注**微服务网关**：学习 Nginx + Spring Cloud Gateway 双层架构
> 3. 如果关注**面试**：重点掌握事件驱动模型、HTTP 处理阶段、负载均衡算法、平滑升级原理
> 4. 如果关注**运维**：学习 Nginx 日志分析、性能调优、健康检查配置

