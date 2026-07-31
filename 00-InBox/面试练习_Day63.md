# 面试模拟 - Day 63

> 日期：2026-08-02（周日） | 模拟岗位：阿里钉钉（杭州总部）- Java开发工程师
> 建议时长：100分钟（一面70分钟 + 二面30分钟）
> 使用方法：找个人帮你念追问（或自己读完主问题后，想30秒再翻追问），模拟真实面试对话节奏
>
> **今日特点**：Day63，"查漏补缺"阶段第十周。模拟钉钉（阿里巴巴集团）——钉钉是企业级智能移动办公平台，杭州总部。核心业务：企业IM（百万级长连接）、开放平台、低代码（宜搭/酷应用）、智能人事。技术栈：Java/Spring Cloud/Dubbo/RocketMQ/Netty。面试特点：阿里系面试偏深、追问到源码层、重视系统设计和并发、要求技术广度+深度。今天引入 **Netty Reactor 模型、Spring AOP 原理深入、Arthas 线上诊断、HikariCP 连接池、CompletableFuture 异步编排、Java 泛型擦除与桥接方法、Spring Cloud Gateway 源码** 7个全新技术话题 + 企业级 IM 技术架构 + 反转链表 II 手写代码——继续覆盖之前碎片提到但没有作为独立话题系统考过的高频核心考点。每话题3-4个追问，模拟真实面试连环深挖。

---

# 一面（70分钟）

## 话题一：Netty Reactor 模型与 EventLoop（9分钟）

**面试官：你们有用 Netty 吗？或者用过哪些基于 Netty 的框架？Netty 的 Reactor 模型了解吗？EventLoop 是什么？**

> 你回答...

**追问1：** 先说说 Netty 是什么。为什么不用 Java 原生 NIO？

> 你回答...（提示：Netty vs 原生NIO / Netty：Java网络编程框架→基于NIO→异步事件驱动→高性能→广泛用于RPC(Dubbo)/MQ(RocketMQ)/IM(钉钉)/网关 / 为什么不用原生NIO：①NIO API复杂→Selector+SelectionKey+Channel→要自己处理OP_READ/OP_WRITE/OP_CONNECT/OP_ACCEPT→200行代码才能写一个Echo Server ②NIO有epoll空轮询bug→Linux上select()返回0但不清除→CPU 100%→JDK Bug(JDK-6403933)→Netty通过重建Selector解决 ③NIO没有编解码框架→要自己处理半包/粘包→Netty提供LengthFieldBasedFrameDecoder等现成解码器 ④NIO没有线程模型→要自己设计Reactor→Netty提供主从Reactor+EventLoop ⑤NIO的ByteBuffer难用→flip()/compact()容易出错→Netty用ByteBuf→读写指针分离→不需要flip / Netty封装→ChannelHandler链+ByteBuf+EventLoop→简化开发→从200行变成20行）

**追问2：** Reactor 模型是什么？主从 Reactor 模型怎么理解？Netty 用的是哪种？

> 你回答...（提示：Reactor三种模型 / Reactor模型：事件驱动→一个或多个线程监听事件→事件来了→分发到Handler处理 / 三种Reactor：
```
①单线程Reactor（单线程做所有事）
  Reactor Thread → Accept + Read + Write + 业务
  → 简单 → 但不能利用多核 → 一个连接慢影响所有

②多线程Reactor（Accept单线程+IO线程池）
  Acceptor Thread → Accept → 分配到Worker Thread
  Worker Thread Pool → Read/Write/业务
  → 利用多核 → 但Accept单线程 → 高连接数时瓶颈

③主从Reactor（Netty用的）
  MainReactor(BossGroup) → Accept → 分配连接
  SubReactor(WorkerGroup) → Read/Write → IO处理
  BusinessThreadPool → 业务逻辑（不阻塞IO线程）
  → Accept和IO分离 → 各不阻塞 → Netty推荐
```
/ Netty对应：
```
主从Reactor（Netty）：
BossGroup（MainReactor）        WorkerGroup（SubReactor）
  ├── BossThread1                ├── WorkerThread1 → 连接1,2,3
  └── BossThread2                ├── WorkerThread2 → 连接4,5,6
       ↓ 轮询分配                └── WorkerThread3 → 连接7,8,9
                    ↓
              BusinessThreadPool → 处理业务
```
→ BossGroup通常1个线程（Accept不需要多线程）→ WorkerGroup默认CPU×2个线程 → 业务线程池单独配）

**追问3：** EventLoop 是什么？它和线程什么关系？一个连接怎么绑定到一个 EventLoop？

> 你回答...（提示：EventLoop / EventLoop：Netty核心→一个EventLoop=一个线程+一个任务队列(MPSC Queue)→绑定一个Selector→处理IO事件+执行任务 / 一个连接绑定到一个EventLoop：①ServerBootstrap.accept→BossGroup的EventLoop Accept ②注册到WorkerGroup的某个EventLoop→该连接的所有IO事件都由这个EventLoop处理→从生到死→一个连接一个EventLoop / 为什么绑定：①一个连接一个EventLoop→不需要锁→单线程处理→线程安全 ②EventLoop串行执行→IO事件+任务队列→FIFO→不需要同步 ③如果连接在多个EventLoop间切换→需要同步→性能差 / NioEventLoop.run()三步：①select()→阻塞等IO事件(默认1s超时) ②processSelectedKeys()→处理IO事件(OP_READ→read/OP_WRITE→write) ③runAllTasks()→执行任务队列中的任务(非IO任务)→ioRatio控制IO/非IO时间比(默认50%) / 真实数字：一个EventLoop可处理约10万连接（取决于内存和业务复杂度）→8核→WorkerGroup默认16个EventLoop→可维持160万连接→实际加上心跳/业务开销→约50-100万）

**追问4：** ChannelPipeline 和 ChannelHandler 是什么？怎么实现自定义编解码？

> 你回答...（提示：Pipeline与Handler / ChannelPipeline：管道→每个Channel有一个Pipeline→Pipeline中是一串ChannelHandler→入站(Inbound)和出站(Outbound)→数据在Pipeline中流转→每个Handler处理一层 / ChannelHandler：InboundHandler处理入站(读)→OutboundHandler处理出站(写)→DualHandler两个都处理
```
入站数据流向（读）：
Socket → HeadContext → Decoder → BusinessHandler → TailContext

出站数据流向（写）：
BusinessHandler → Encoder → HeadContext → Socket
```
/ 自定义编解码：
```java
// 解码器(Decoder) → ByteToMessageDecoder → 半包/粘包处理
public class MyDecoder extends ByteToMessageDecoder {
    @Override
    protected void decode(ChannelHandlerContext ctx, ByteBuf in, List<Object> out) {
        if (in.readableBytes() < 4) return; // 不够读长度字段
        in.markReaderIndex();
        int length = in.readInt();
        if (in.readableBytes() < length) {
            in.resetReaderIndex(); // 不够读body→回退→等下次
            return;
        }
        byte[] body = new byte[length];
        in.readBytes(body);
        out.add(deserialize(body)); // 传给下一个Handler
    }
}
// 编码器(Encoder) → MessageToByteEncoder
public class MyEncoder extends MessageToByteEncoder<MyMessage> {
    @Override
    protected void encode(ChannelHandlerContext ctx, MyMessage msg, ByteBuf out) {
        byte[] body = serialize(msg);
        out.writeInt(body.length); // 长度字段
        out.writeBytes(body);       // body
    }
}
```
/ 常用现成解码器：①LengthFieldBasedFrameDecoder→长度字段解半包 ②LineBasedFrameDecoder→换行符分包 ③DelimiterBasedFrameDecoder→自定义分隔符 / 踩坑：①解码器忘了markReaderIndex/resetReaderIndex→半包时读指针错位→数据错乱 ②解码器抛异常→会触发exceptionCaught→如果不close→连接泄漏→建议异常时ctx.close() / 小张一句到位：Netty的Pipeline就是责任链模式→数据从Head到Tail流→Inbound从前往后→Outbound从后往前→每个Handler处理一层→像流水线）

---

## 话题二：Spring AOP 原理深入（9分钟）

**面试官：Spring AOP 你们用过吗？@Transactional、@Async 这些都是 AOP。AOP 底层原理是什么？JDK 动态代理和 CGLIB？**

> 你回答...

**追问1：** 先说说 Spring AOP 是什么。它和 AspectJ 有什么区别？

> 你回答...（提示：Spring AOP vs AspectJ / Spring AOP：运行时织入(Runtime Weaving)→基于动态代理→只对Spring Bean生效→只支持方法级(不支持字段/构造器)→简单(注解即可) / AspectJ：编译时织入(CTW)或加载时织入(LTW)→用ajc编译器→字节码增强→支持方法/字段/构造器/静态→更强大→但复杂
| 维度 | Spring AOP | AspectJ |
|------|-----------|---------|
| 织入时机 | 运行时(动态代理) | 编译时/加载时(字节码增强) |
| 实现 | JDK/CGLIB代理 | ajc编译器 |
| 性能 | 代理有开销 | 直接字节码→无代理开销 |
| 功能 | 方法级 | 方法+字段+构造器 |
| 使用 | 简单(注解) | 复杂(ajc编译) |
/ Spring AOP底层=动态代理→如果目标类有接口→JDK动态代理→否则CGLIB→Spring 5.x+(Spring Boot 2.x+)默认CGLIB(proxyTargetClass=true)→不管有没有接口都用CGLIB）

**追问2：** JDK 动态代理和 CGLIB 有什么区别？Spring 怎么选？代码层面怎么实现的？

> 你回答...（提示：JDK vs CGLIB / JDK动态代理：基于接口→Proxy.newProxyInstance→生成$Proxy0(实现接口)→InvocationHandler.invoke→只能代理接口方法 / CGLIB：基于继承→生成目标类子类→MethodInterceptor.intercept→能代理类(不需要接口)→但不能代理final类/final方法
```java
// JDK动态代理
public class MyHandler implements InvocationHandler {
    private Object target;
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        before();
        Object result = method.invoke(target, args); // 反射调目标
        after();
        return result;
    }
}
MyInterface proxy = (MyInterface) Proxy.newProxyInstance(
    loader, new Class[]{MyInterface.class}, new MyHandler(target));

// CGLIB
public class MyInterceptor implements MethodInterceptor {
    public Object intercept(Object obj, Method method, Object[] args, MethodProxy proxy) {
        before();
        Object result = proxy.invokeSuper(obj, args); // 调父类(原始)
        after();
        return result;
    }
}
Enhancer enhancer = new Enhancer();
enhancer.setSuperclass(Target.class);
enhancer.setCallback(new MyInterceptor());
Target proxy = (Target) enhancer.create();
```
/ Spring怎么选：①Spring 5.x前→有接口JDK→没接口CGLIB ②Spring 5.x+→默认CGLIB(proxyTargetClass=true)→因为CGLIB性能追平JDK→且更通用 ③配`@EnableAspectJAutoProxy(proxyTargetClass=true)`强制CGLIB / 性能：CGLIB用FastClass机制→MethodProxy.invokeSuper→通过index直接调→不用反射→比JDK反射快（但CGLIB创建慢→生成子类比生成接口代理慢））

**追问3：** AOP 的切面执行顺序怎么控制？多个切面怎么排序？

> 你回答...（提示：切面排序 / @Order注解→值小的先执行(入站)→大的后执行→洋葱模型
```
@Order(1) AspectA → before
  @Order(2) AspectB → before
    目标方法()
  @Order(2) AspectB → after
@Order(1) AspectA → after
```
→ 入站(目标方法前)从外到内→出站(目标方法后)从内到外→类似洋葱→@Around包裹最外层 / 执行流程：
```
@Around → proceed()
  @Before → 目标方法
    目标方法执行
  @AfterReturning → 正常返回
  @AfterThrowing → 异常
@After → 不管成功失败都执行(finally)
```
/ @Around最外→包裹其他→proceed()调下一个切面或目标方法 / 没有@Order→默认Ordered.LOWEST_PRECEDENCE(Integer.MAX_VALUE)→最后执行 / 踩坑：@Transactional和@Async同时用→@Async优先级高→先异步→@Transactional在新线程→事务可能不生效→需要调整@Order或拆分）

**追问4：** @Transactional 怎么通过 AOP 实现的？事务传播原理是什么？什么情况下 @Transactional 不生效？

> 你回答...（提示：@Transactional AOP实现 / 实现：①Spring创建Bean→如果有@Transactional→创建代理 ②调方法→代理拦截→TransactionInterceptor.invoke→开启事务→调目标方法→成功提交→失败回滚 ③PlatformTransactionManager→DataSourceTransactionManager(JDBC)/JpaTransactionManager / 事务传播(7种)：
| 传播行为 | 说明 |
|---------|------|
| REQUIRED(默认) | 有事务加入→无事务新建 |
| REQUIRES_NEW | 总是新建→挂起当前事务 |
| NESTED | 嵌套事务→savepoint |
| SUPPORTS | 有加入→无非事务 |
| NOT_SUPPORTED | 非事务→挂起当前 |
| MANDATORY | 必须有→无则异常 |
| NEVER | 必须无→有则异常 |
/ @Transactional不生效的场景（踩坑）：
①self-invocation(自调用)→this.xxx()→不走代理→@Transactional不生效→解决：AopContext.currentProxy().xxx()或注入自己
```java
@Service
public class OrderService {
    @Transactional
    public void createOrder() { ... }
    
    public void batchCreate() {
        // this.createOrder() → 不走代理 → 事务不生效！
        // 解决1: AopContext.currentProxy().createOrder()
        // 解决2: 注入自己 @Autowired OrderService self; self.createOrder()
    }
}
```
②private方法→代理只能拦截public→private不生效 ③异常被catch→不回滚→要让异常抛出→或`TransactionAspectSupport.currentTransactionStatus().setRollbackOnly()` ④rollbackFor默认只回滚RuntimeException→checked异常不回滚→要`@Transactional(rollbackFor=Exception.class)` ⑤非Spring Bean→new出来的对象→没有代理→不生效 / 小张一句到位：@Transactional=代理+TransactionInterceptor→自调用走this不走代理→最坑→要么AopContext要么注入自己→private也不行→异常要抛出→rollbackFor要配全）

---

## 话题三：Arthas 线上诊断工具（8分钟）

**面试官：线上出问题怎么排查？jstack？jmap？有没有用过 Arthas？它比传统工具好在哪里？**

> 你回答...

**追问1：** 先说说 Arthas 是什么。它解决了什么问题？

> 你回答...（提示：Arthas / Arthas：阿里巴巴开源Java诊断工具→不重启应用→动态注入→查看方法调用/监控/反编译 / 解决的问题：①线上问题排查→不方便加日志→Arthas watch方法出入参 ②性能排查→哪个方法慢→trace追踪调用链耗时 ③类冲突→不知道加载了哪个版本→jad反编译看实际加载的类 ④动态修改日志级别→不重启→logger命令 ⑤查看JVM信息→dashboard/thread/jvm / 安装：`curl -O https://arthas.aliyun.com/arthas-boot.jar` → `java -jar arthas-boot.jar <PID>` → attach到目标JVM）

**追问2：** 常用命令有哪些？dashboard/watch/trace/jad 分别做什么？

> 你回答...（提示：常用命令 /
| 命令 | 作用 | 示例 |
|------|------|------|
| dashboard | 全局概览→线程/CPU/GC/堆 | dashboard |
| thread | 线程信息→找死锁/阻塞 | thread -n 3(看CPU最高3个) |
| thread -b | 找阻塞其他线程的线程 | thread -b |
| jad | 反编译→看实际加载的类 | jad com.xxx.OrderService |
| watch | 观察方法→出入参/返回值/异常 | watch com.xxx.OrderService createOrder '{params,returnObj,throwExp}' -x 2 |
| trace | 追踪方法调用链→每个子方法耗时 | trace com.xxx.OrderService createOrder |
| stack | 查看方法调用栈→谁调的 | stack com.xxx.OrderService createOrder |
| monitor | 方法执行统计→调用次数/成功率/RT | monitor com.xxx.OrderService createOrder -c 10 |
| logger | 动态修改日志级别 | logger --name ROOT --level DEBUG |
| vmtool | 查询堆内存中的对象 | vmtool --action getInstances --className java.lang.String --limit 10 |
/ 实际排查场景：①接口慢→trace追踪→发现某个子方法慢→继续trace→定位到DB/Redis/外部API ②方法返回值不对→watch看入参和返回值→判断是参数问题还是逻辑问题 ③类冲突→jad反编译→看实际加载的代码→发现maven依赖冲突→排除旧版本）

**追问3：** 线上 CPU 飙高怎么排查？OOM 怎么排查？Arthas 怎么帮上忙？

> 你回答...（提示：CPU飙高与OOM排查 / CPU飙高传统流程：①top→找CPU高的Java进程PID ②top -Hp PID→找CPU高的线程TID ③printf "%x\n" TID→转16进制 ④jstack PID | grep nid=0xXXX→找线程堆栈→定位代码 → Arthas更简单：`thread -n 5`→直接看CPU最高的5个线程+堆栈→一步到位
```
[arthas@12345]$ thread -n 3
# 展示CPU最高的3个线程
# 会显示线程名/CPU%/状态/堆栈
```
/ OOM排查：①先看OOM类型→Java heap space(堆不够)/Metaspace(元空间)/Direct buffer memory(堆外)/GC overhead limit exceeded ②传统→jmap -dump:format=b,file=heap.hprof PID→MAT分析 ③Arthas→dashboard看堆使用→`heapdump /tmp/heap.hprof`导出→MAT分析→或`vmtool --action getInstances --className com.xxx.BigObject --limit 100`直接看大对象 / 常见OOM原因：①堆→内存泄漏(集合只加不删)/大对象(一次性加载大List)/缓存无上限 ②Metaspace→动态生成类(ASM/CGLIB)不卸载 ③Direct buffer→Netty ByteBuf泄漏(没有release) ④GC overhead→对象创建太快→GC跟不上→最终OOM / 举一反三：线上CPU飙高→先排除GC→如果是Full GC频繁→看堆→如果是业务线程CPU高→thread -n看堆栈→如果是大量线程→thread看线程状态→死锁用thread -b）

**追问4：** Arthas 的原理是什么？为什么能不重启应用就诊断？

> 你回答...（提示：Arthas原理 / Arthas原理：①Java Agent→Arthas用Java Instrumentation API→attach到目标JVM→注入Agent ②字节码增强→Arthas用ASM修改目标类字节码→在方法前后插入监控代码→不改源码→改的是运行时字节码 ③attach→VirtualMachine.attach(PID)→动态连接到目标JVM→加载arthas-agent ④Instrumentation API→retransformClasses→运行时修改已加载类→不需要重启 ⑤退出→恢复原字节码→不影响应用 / 为什么不重启：①Instrumentation API支持运行时retransform→JVM在运行中修改已加载类 ②ASM→操作字节码→动态织入watch/trace的逻辑 ③修改后→JIT重新编译→生效 / watch原理：①Arthas找到目标类→retransform→在方法前后插入`AdviceWeaver`代码→存入参/返回值到Advice→watch命令从Advice读取→展示 ②trace原理→在方法入口/出口插入耗时统计→递归到子方法→形成调用树 / 踩坑：①Arthas增强类会持有引用→可能导致类不被GC→用完exit ②生产上谨慎用watch→大对象出入参→打印到控制台→内存消耗 ③trace深层调用→栈深→输出巨大→限制depth / 小张一句到位：Arthas=Instrumentation+ASM→运行时改字节码→不重启→是线上排查的神器→但用完记得exit→不然一直持有增强后的类引用→可能影响GC）

---

## 话题四：HikariCP 连接池原理（8分钟）

**面试官：你们数据库连接池用什么？HikariCP？为什么说它是最快的？它快在哪里？**

> 你回答...

**追问1：** HikariCP 是什么？为什么说它是最快的连接池？它快在哪里？

> 你回答...（提示：HikariCP快的原因 / HikariCP：Spring Boot 2.0+默认数据库连接池→作者Brett Wooldridge→号称最快Java连接池 / 为什么快：①字节码精简→HikariProxyConnection/Statement→用Javassist字节码生成而非反射→方法调用少→每次getConnection/prepareStatement少几层代理 ②FastList替代ArrayList→不做范围检查(rangeCheck)→ArrayList每次add/get都检查index→FastList去掉→微优化→但百万次调用→累计可观 ③ConcurrentBag→无锁并发集合→减少线程竞争 ④精简设计→功能少→只有连接池→没有监控/SQL解析→代码少→没有多余开销 / vs Druid：①Druid功能多(监控/SQL解析WallFilter/防注入)→但开销大 ②HikariCP功能少(只有连接池)→但快 ③Spring Boot选HikariCP=快+简单→如果需要监控用Druid→可以两者结合(HikariCP + Druid的StatFilter) / 真实数字：HikariCP vs Druid→getConnection约快2-3倍→HikariCP约~100ns→Druid约~300ns→高并发下差距明显）

**追问2：** 连接池的核心参数有哪些？怎么配？有什么坑？

> 你回答...（提示：核心参数 /
| 参数 | 说明 | 推荐值 |
|------|------|--------|
| maximumPoolSize | 最大连接数 | (核心数×2)+磁盘数 或根据DB max_connections |
| minimumIdle | 最小空闲 | =maximumPoolSize(避免频繁创建/销毁) |
| connectionTimeout | 获取连接超时 | 5s(默认30s太长) |
| idleTimeout | 空闲超时 | 10min(默认)→超过minimumIdle的空闲连接回收 |
| maxLifetime | 连接最大生命 | 29min(比DB的wait_timeout短1min) |
| leakDetectionThreshold | 连接泄漏检测 | 60s(默认0关)→借出超60s没还→告警 |
/ 踩坑：①maximumPoolSize设太大→如50×10实例=500→MySQL默认max_connections=151→超了→连接拒绝→应该`(DB max_connections - 管理连接) / 应用实例数` ②minimumIdle设太小→低峰回收→高峰重建→创建连接开销(约10ms/TCP握手+认证)→推荐minimumIdle=maximumPoolSize→保持常驻 ③maxLifetime不设或设太大→DB主动断连(wait_timeout默认8h)→连接池还以为有效→用了报错→HikariCP自动检测 ④connectionTimeout默认30s→太长→连接池满→用户等30s→体验差→改5s快速失败）

**追问3：** HikariCP 的 FastList 和 ConcurrentBag 是什么？

> 你回答...（提示：FastList与ConcurrentBag / FastList：替代ArrayList→①不做范围检查(rangeCheck)→ArrayList每次add/get都checkIndex→FastList去掉→微优化 ②remove从尾部开始→Statement的关闭通常是LIFO(Last In First Out)→从尾部遍历更快 ③不线程安全→但Connection是线程隔离的→每个Connection的Statement列表只有持有该Connection的线程访问→不需要线程安全 / ConcurrentBag：HikariCP自研无锁并发集合→连接的借用和归还
```
borrow(借连接)流程：
1. 先从ThreadLocal的列表(ready)中找 → 命中率高(线程倾向于重用上次连接)
2. 没有→从shared queue(共享队列)中CAS拿 → 无锁
3. 还没有→从其他线程的ThreadLocal"偷"(handoff) → 试几次
4. 都没有→等待新连接创建
```
→ ThreadLocal优先→减少竞争→CAS无锁→比synchronized快 / 为什么不用普通的连接池(如BlockingQueue)：BlockingQueue的take/put用ReentrantLock→多线程竞争→CAS无锁性能好 / 真实数字：16线程并发→LinkedBlockingQueue约50万ops/s→ConcurrentBag约100万ops/s→2倍差距）

**追问4：** 连接泄漏检测怎么做？连接池满了怎么办？生产排查经验？

> 你回答...（提示：泄漏检测与连接池满 / 连接泄漏检测：leakDetectionThreshold→连接借出后超过指定时间未归还→日志打印泄漏堆栈→定位哪个代码没close / 常见原因：①try-catch里忘了close ②在异步线程里用了连接但没归还 ③Spring事务管理异常导致连接不归还 ④手动getConnection但没close / 连接池满了：①获取连接阻塞→超过connectionTimeout→抛SQLTransientConnectionException ②原因通常是慢SQL→一个SQL执行很久→占着连接不还→其他请求等 ③解决→排查慢SQL(show processlist看DB端)→加超时→限流(防打爆)→增大连接池(治标) / 生产排查经验：①接口大量超时→Grafana看DB连接池→active=maximum→连接池满→Arthas thread看→都在等连接→show processlist→发现一个慢SQL→30秒→explain→全表扫描→加索引→解决 ②leakDetectionThreshold=60s→日志报泄漏→堆栈定位到代码→ThreadLocal+连接没归还→修复 / 举一反三：连接池满=下游(DB)慢→上游(应用)等→连锁反应→一定要有超时+熔断→不能让一个慢SQL拖垮整个应用 / 小张一句到位：HikariCP快在精简→FastList不做检查→ConcurrentBag无锁→Druid功能多但慢→Spring Boot默认HikariCP够用→需要监控再加Druid StatFilter）

---

## 话题五：CompletableFuture 异步编排（8分钟）

**面试官：你们异步编程怎么做的？CompletableFuture？和 Future 有什么区别？多个异步任务怎么编排？**

> 你回答...

**追问1：** 先说说 CompletableFuture 是什么。和 Future 有什么区别？

> 你回答...（提示：CompletableFuture vs Future / Future局限：①get()阻塞→必须等结果→不能回调→调用方干等 ②isDone()轮询→浪费CPU→不优雅 ③不能组合→不能thenCombine/allOf→多个Future无法编排 / CompletableFuture：JDK 8→异步编排→非阻塞→回调→组合→回调式编程→不用等→完成后自动执行下一步 / 对比：
| 维度 | Future | CompletableFuture |
|------|--------|-------------------|
| 获取结果 | get()阻塞 | 回调(thenApply等) |
| 组合 | 不支持 | thenCombine/allOf/anyOf |
| 异常处理 | get抛异常 | exceptionally/handle |
| 取消 | cancel() | 可取消 |
| 回调 | 不支持 | 多种回调 |
）

**追问2：** 常用 API 有哪些？thenApply/thenCompose/thenCombine 有什么区别？

> 你回答...（提示：CompletableFuture API /
| API | 说明 | 等价 |
|-----|------|------|
| supplyAsync(Supplier) | 异步执行→有返回值 | ExecutorService.submit |
| runAsync(Runnable) | 异步执行→无返回值 | ExecutorService.execute |
| thenApply(Function<T,R>) | 转换结果T→R | map |
| thenApplyAsync(Function, executor) | 转换→指定线程池 | |
| thenCompose(Function<T,CF<R>>) | flat→拆嵌套 | flatMap |
| thenCombine(CF<T2>, BiFunction) | 合并两个独立结果 | zip |
| whenComplete(BiConsumer) | 完成时回调→不改结果 | peek |
| exceptionally(Function) | 异常→兜底值 | onErrorResumeNext |
| handle(BiFunction) | 成功+异常都处理→可改结果 | |
/ thenApply vs thenCompose：
```java
// thenApply → 结果嵌套！
CompletableFuture<CompletableFuture<User>> bad =
    getUserIdAsync().thenApply(id -> getUserAsync(id)); // 返回CF<CF<User>>

// thenCompose → flat拆嵌套
CompletableFuture<User> good =
    getUserIdAsync().thenCompose(id -> getUserAsync(id)); // 返回CF<User>

// thenCombine → 合并两个独立结果
CompletableFuture<User> userFuture = getUserAsync(userId);
CompletableFuture<Order> orderFuture = getOrderAsync(orderId);
CompletableFuture<UserOrderDTO> combined = 
    userFuture.thenCombine(orderFuture, (user, order) -> new UserOrderDTO(user, order));
```
→ thenApply=map(一对一)→thenCompose=flatMap(一对一但拆嵌套)→thenCombine=zip(两个独立→合一)）

**追问3：** 异常处理怎么做？whenComplete/exceptionally/handle 有什么区别？

> 你回答...（提示：异常处理 /
| API | 触发条件 | 能否改结果 |
|-----|---------|-----------|
| whenComplete | 成功+失败都触发 | 不能→异常继续传 |
| exceptionally | 只异常时触发 | 能→返回兜底值 |
| handle | 成功+失败都触发 | 能→可改结果 |
```java
CompletableFuture.supplyAsync(() -> riskyCall())
    .thenApply(data -> process(data))      // 正常处理
    .exceptionally(ex -> {                 // 异常→兜底
        log.error("失败", ex);
        return defaultValue;
    })
    .whenComplete((result, ex) -> {        // 不管成功失败→记录
        metrics.record(result, ex);
    });
// 链路：riskyCall成功→process→whenComplete记录
//       riskyCall失败→exceptionally兜底→whenComplete记录
```
/ whenComplete不改结果→如果上游异常→whenComplete的ex非null→但下游依然异常 / exceptionally只处理异常→正常则跳过 / handle两个都处理→可以改 → 使用建议：记录用whenComplete→兜底用exceptionally→复杂处理用handle / 踩坑：①exceptionally只捕获上游异常→如果thenApply里异常→exceptionally能捕获→但如果exceptionally之后又异常→需要再exceptionally ②whenComplete里抛异常→下游也会收到异常→要注意不要在whenComplete里抛）

**追问4：** 多个异步任务编排怎么做？allOf/anyOf？线程池有什么坑？

> 你回答...（提示：编排与线程池坑 / allOf→等所有完成→返回CF<Void>→需要join获取结果
```java
// 并行调3个服务→等所有完成
CompletableFuture<User> f1 = getUserAsync(id1);
CompletableFuture<User> f2 = getUserAsync(id2);
CompletableFuture<User> f3 = getUserAsync(id3);
CompletableFuture.allOf(f1, f2, f3).join(); // 等所有
List<User> users = List.of(f1.join(), f2.join(), f3.join());
```
/ anyOf→任一完成→返回CF<Object>
```java
// 3个超时重试→任一成功即用
CompletableFuture.anyOf(
    callServiceA(),
    callServiceB(),
    callServiceC()
).join();
```
/ 线程池坑（最常见）：①supplyAsync没传executor→默认ForkJoinPool.commonPool()→线程数=CPU-1→不够用→可能阻塞→高并发下commonPool打满→任务排队→延迟 ②thenApplyAsync没传executor→commonPool ③串行链太长→一个线程从头到尾→如果某个环节阻塞→整链阻塞 / 解决：所有异步操作都传自定义线程池
```java
ExecutorService ioPool = Executors.newFixedThreadPool(50,
    new ThreadFactoryBuilder().setNameFormat("io-pool-%d").build());

CompletableFuture.supplyAsync(() -> httpCall(), ioPool) // ← 传线程池
    .thenApply(data -> process(data), ioPool)           // ← 传线程池
    .thenCompose(result -> saveAsync(result), ioPool)   // ← 传线程池
    .exceptionally(ex -> defaultValue);
```
/ 踩坑：生产上CompletableFuture链→commonPool只有7个线程(CPU-1=7)→高并发→commonPool打满→任务排队→延迟飙升→改为自定义线程池(50)→解决 / 举一反三：CompletableFuture + 虚拟线程(JDK21)→supplyAsync传newVirtualThreadPerTaskExecutor()→每个任务一个VT→不阻塞→不需要调线程池大小 / 小张一句到位：CompletableFuture最大的坑=默认commonPool→7个线程→高并发打满→必须传自定义线程池→不然同步代码还不如异步）

---

## 话题六：Java 泛型擦除与桥接方法（8分钟）

**面试官：Java 泛型了解吗？泛型擦除是什么？为什么 Java 要擦除泛型？桥接方法是什么？**

> 你回答...

**追问1：** 泛型擦除是什么？为什么 Java 要擦除泛型？擦除过程是什么？

> 你回答...（提示：泛型擦除 / 泛型擦除：Java泛型只在编译期检查→编译后擦除→运行时没有泛型信息→`List<String>`和`List<Integer>`运行时都是`List`(raw type) / 为什么擦除：①兼容性→JDK 5引入泛型→要和JDK 1.4的原始类型兼容→擦除保证二进制兼容→旧代码不用改 ②简单→擦除后只有一种字节码→不需要为每个泛型参数生成不同类（C++模板为每个类型生成一份代码→代码膨胀） / 擦除规则：①`List<String>`→擦除为`List` ②`T`(无限界)→擦除为Object ③`T extends Number`→擦除为Number ④`T extends Comparable<T>`→擦除为Comparable ⑤`Map.Entry<K,V>`→擦除为`Map.Entry`
```java
// 编译前
List<String> list = new ArrayList<>();
list.add("hello");
String s = list.get(0);

// 擦除后（实际字节码）
List list = new ArrayList();
list.add("hello");
String s = (String) list.get(0); // 编译器自动插入checkcast
```
→ 编译器在边界(方法入参/返回值)自动插入checkcast→保证类型安全）

**追问2：** 擦除带来什么问题？不能 new T()？不能 getClass()？怎么解决？

> 你回答...（提示：擦除的问题 / 问题：
①不能new T()→运行时不知道T是什么→new T()不知道调哪个构造器
②不能`new ArrayList<String>().getClass()`区分→都是ArrayList.class
③不能instanceof泛型→`if (obj instanceof List<String>)`→编译报错→运行时无法区分
④不能创建泛型数组→`new T[10]`→编译报错→类型不安全
⑤静态方法/字段不能使用类的泛型参数→泛型属于实例→静态属于类→类不知道T是什么
/ 解决：
①new T()→传Class<T>→`clazz.getDeclaredConstructor().newInstance()`
```java
// 不能 new T()
public <T> T create() {
    return new T(); // 编译报错！
}
// 解决：传Class<T>
public <T> T create(Class<T> clazz) throws Exception {
    return clazz.getDeclaredConstructor().newInstance();
}
```
②泛型数组→`Array.newInstance(clazz, size)`
③instanceof→用Class→`clazz.isInstance(obj)`
④静态方法→自己定义泛型参数→`public static <T> T doSomething(T t)`

**追问3：** 桥接方法是什么？为什么要生成桥接方法？

> 你回答...（提示：桥接方法 / 桥接方法(Bridge Method)：编译器自动生成→保证泛型擦除后的多态正确 / 场景：
```java
class Node<T> {
    T value;
    void setValue(T value) { this.value = value; } // 擦除→setValue(Object)
}
class StringNode extends Node<String> {
    @Override
    void setValue(String value) { ... } // setValue(String) → 和父类签名不同！
}
```
→ 擦除后：Node.setValue(Object)→StringNode.setValue(String)→签名不同→不构成重写→多态失效！
→ `Node<String> node = new StringNode(); node.setValue("hello")` → 调setValue(Object)→但StringNode没有setValue(Object)→应该调setValue(String)→但多态找不到→编译器生成桥接方法：
```java
// 编译器在StringNode中自动生成
void setValue(Object value) {     // 桥接方法→签名和父类一样(Object)
    setValue((String) value);      // 内部调setValue(String)→强转
}
```
→ 桥接方法签名=父类(Object)→构成重写→内部强转调子类方法→保证多态 / 怎么发现桥接方法：①反射getMethods()→能看到setValue(Object)→即使源码没写 ②javap -v StringNode→能看到`bridge`标志的合成方法 / 桥接方法的坑：①@Override注解→如果子类方法签名和擦除后父类不匹配→@Override报错→但桥接方法本身不是源码方法 ②反射调用→如果用反射调setValue(Object)→走的是桥接方法→不是你写的setValue(String)→需要注意 / 举一反三：桥接方法不仅泛型有→协变返回类型也有→如父类返回Object→子类返回String→编译器生成桥接`Object method()`调`String method()`）

**追问4：** 泛型通配符？PECS 原则？实际怎么用？

> 你回答...（提示：PECS / PECS = Producer Extends, Consumer Super / `<? extends T>`(上界)→Producer→读→可以读T→但不能写→因为不知道具体是什么子类→写入不安全
`<? super T>`(下界)→Consumer→写→可以写T及子类→但读只能Object→因为不知道具体是什么父类
```java
// Producer Extends → 读
List<? extends Number> list = new ArrayList<Integer>();
Number n = list.get(0);  // 可以读→编译通过
list.add(1);             // 不能写→编译报错！→不知道具体是Integer还是Double

// Consumer Super → 写
List<? super Integer> list = new ArrayList<Number>();
list.add(1);             // 可以写Integer→编译通过
Object o = list.get(0);   // 读只能Object→不知道具体是Number还是Object
```
/ Collections.copy签名→完美PECS：
```java
public static <T> void copy(
    List<? super T> dest,    // Consumer Super → 写
    List<? extends T> src    // Producer Extends → 读
)
```
/ 实际使用：①方法参数→如果只读→`<? extends T>` ②如果只写→`<? super T>` ③既读又写→`<T>`不用通配符 ④Comparable/Comparator→通常`<? super T>`→如`Collections.sort(list, Comparator<? super T>)`→比较器可以接受T的父类型 / 小张一句到位：泛型擦除=运行时没泛型→new T()不行→传Class→桥接方法=编译器自动生成保证多态→PECS=生产者用extends(只读)→消费者用super(只写)→Collections.copy是教科书级PECS）

---

## 话题七：Spring Cloud Gateway 源码分析（8分钟）

**面试官：你们网关用什么？Spring Cloud Gateway？它的请求处理流程是什么？源码看过吗？动态路由怎么实现？**

> 你回答...

**追问1：** Gateway 的请求处理流程是什么？它和 Zuul 有什么区别？

> 你回答...（提示：Gateway流程 / Gateway基于Spring WebFlux(Reactor+Netty)→非阻塞→高性能 / 请求流程：
```
请求 → Gateway(Netty Server)
  → RoutePredicateHandlerMapping → 匹配Route(根据Predicate)
  → Filter Chain（GlobalFilter + GatewayFilter）
    → 前置Filter: 鉴权/限流/日志
    → NettyRoutingFilter: 转发到后端微服务(Netty Client)
    → 后置Filter: 修改响应/记录
  → 返回响应
```
①Gateway接收HTTP请求→RoutePredicateHandlerMapping→匹配Route(根据Path/Method/Header等Predicate) ②匹配到Route→过Filter链(GlobalFilter全局+GatewayFilter路由级) ③Filter链→前置Filter(鉴权/限流/日志)→NettyRoutingFilter(转发到后端)→后置Filter(修改响应/记录) ④返回响应 / vs Zuul：①Zuul 1.x→基于Servlet→同步阻塞→一个请求一个线程 ②Zuul 2.x→基于Netty→异步非阻塞 ③Gateway→基于WebFlux(Reactor)→异步非阻塞→天然支持背压 ④Spring Cloud推荐Gateway→Zuul 2.x迟迟不发布→Spring自己做了Gateway / 性能：Gateway比Zuul 1.x快约2倍（非阻塞vs阻塞→高并发差距更大）

**追问2：** RoutePredicateFactory 和 GatewayFilterFactory 是什么？怎么自定义？

> 你回答...（提示：Predicate与Filter / RoutePredicateFactory→路由断言工厂→判断请求是否匹配某个Route→内置：
| Predicate | 说明 | 示例 |
|----------|------|------|
| Path | 路径匹配 | Path=/api/** |
| Method | HTTP方法 | Method=GET,POST |
| Header | 请求头 | Header=X-Req-Id,\d+ |
| Query | 查询参数 | Query=token,.+ |
| Host | 域名 | Host=**.example.com |
| After/Before | 时间 | After=2026-01-01... |
| RemoteAddr | IP | RemoteAddr=192.168.1.1/24 |
/ GatewayFilterFactory→网关过滤器工厂→对请求/响应处理→内置：
| Filter | 说明 |
|--------|------|
| AddRequestHeader | 加请求头 |
| RewritePath | 重写路径 |
| RequestRateLimiter | 限流(基于Redis) |
| CircuitBreaker | 熔断(Resilience4j) |
| PrefixPath | 加前缀 |
| StripPrefix | 去前缀 |
/ 自定义Filter：
```java
// 自定义GlobalFilter
@Component
public class AuthFilter implements GlobalFilter, Ordered {
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String token = exchange.getRequest().getHeaders().getFirst("token");
        if (token == null || !validate(token)) {
            exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
            return exchange.getResponse().setComplete();
        }
        return chain.filter(exchange); // 传递给下一个Filter
    }
    @Override
    public int getOrder() { return -100; } // 值小先执行
}
```
/ 自定义GatewayFilter→实现GatewayFilterFactory→配置文件用）

**追问3：** Gateway 的 Filter 链怎么执行？前置和后置怎么实现？

> 你回答...（提示：Filter链执行 / Filter链=GlobalFilter(全局)+GatewayFilter(路由级)→都实现Ordered接口→getOrder()→值小的先执行→洋葱模型
```
请求 → 前置逻辑(鉴权) → 前置逻辑(限流) → 转发(NettyRoutingFilter)
                                                     ↓
响应 ← 后置逻辑(日志) ← 后置逻辑(响应改写) ← 后端响应
```
/ 前置+后置→Reactor的Mono.then():
```java
@Override
public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
    // 前置 → 鉴权/限流
    String token = exchange.getRequest().getHeaders().getFirst("token");
    if (token == null) {
        return Mono.error(new ResponseStatusException(HttpStatus.UNAUTHORIZED));
    }
    // 传递给下一个Filter → 完成后执行后置
    return chain.filter(exchange).then(Mono.fromRunnable(() -> {
        // 后置 → 记录日志/修改响应
        HttpStatus status = exchange.getResponse().getStatusCode();
        log.info("请求完成: {} → {}", 
            exchange.getRequest().getURI(), status);
    }));
}
```
→ chain.filter(exchange)→传递给下一个Filter→返回Mono→完成后.then()执行后置 / NettyRoutingFilter→order=0→转发到后端→是链的最后一环 / 踩坑：①异步非阻塞→不能在Filter里做阻塞操作(Thread.sleep/同步DB)→会阻塞EventLoop→性能下降→阻塞操作要放业务线程池 ②Filter执行顺序→getOrder值小先→如果鉴权Filter在限流Filter后面→限流先执行→没鉴权就限流→浪费→鉴权应该order更小→先鉴权）

**追问4：** Gateway 的动态路由怎么实现？不重启网关怎么加路由？

> 你回答...（提示：动态路由 / 动态路由：不重启Gateway→动态新增/修改/删除Route→新服务上线自动路由 / 实现：
①RouteDefinitionWriter→写路由定义→存DB/配置中心
②RouteDefinitionLocator→从DB/配置中心读取→转RouteDefinition
③监听配置中心变更→Nacos/Apollo→变更→发RefreshRoutesEvent→重新加载
④自定义RouteDefinitionRepository→从DB加载
```java
// 自定义从Nacos加载路由
public class NacosRouteDefinitionRepository implements RouteDefinitionRepository {
    @Override
    public Flux<RouteDefinition> getRouteDefinitions() {
        // 从Nacos读取路由配置(JSON)
        String config = nacosConfig.get("gateway-routes");
        List<RouteDefinition> routes = parseRoutes(config);
        return Flux.fromIterable(routes);
    }
    // 监听Nacos变更
    @NacosConfigListener(dataId = "gateway-routes")
    public void onRouteChange(String config) {
        // 发刷新事件→Gateway重新加载路由
        publisher.publishEvent(new RefreshRoutesEvent(this));
    }
}
```
/ 路由配置格式(JSON)：
```json
[{
  "id": "order-service",
  "uri": "lb://order-service",
  "predicates": [{"name":"Path","args":{"pattern":"/order/**"}}],
  "filters": [{"name":"StripPrefix","args":{"parts":"1"}}]
}]
```
→ Nacos变更→onRouteChange→RefreshRoutesEvent→RouteLocator.refresh()→重新getRouteDefinitions()→路由生效→不重启 / 举一反三：生产实践→Nacos存路由配置→Gateway监听变更→动态生效→新服务上线→Nacos加路由→Gateway自动路由→不需要改配置文件→不需要重启→自动化 / 小张一句到位：Gateway动态路由=RouteDefinitionRepository(从Nacos读)+RefreshRoutesEvent(监听变更刷新)→Nacos改→Gateway自动更新→不重启→运维零成本）

---

## 话题八：手写代码 - 反转链表 II（区间反转）（8分钟）

**面试官：给你一个链表和两个位置 left 和 right，反转从 left 到 right 的部分。比如 1->2->3->4->5，left=2，right=4，反转后 1->4->3->2->5。写一下。**

你在纸上/白板上写代码...

**追问1：** 先说说思路。有哪些方法？

> 你回答...（提示：反转链表II思路 / 方法一：头插法→找到left前一个节点pre→把left到right的节点逐个头插到pre后面→O(n)时间→O(1)空间 / 方法二：截取反转法→截取left到right→反转→重新连接→需要找三个断点→O(n)时间→O(1)空间→但实现稍复杂 / 最优=头插法→一遍遍历→O(n)时间→O(1)空间）

**追问2：** 写头插法代码。

> 你回答...（提示：头插法代码
```java
public ListNode reverseBetween(ListNode head, int left, int right) {
    ListNode dummy = new ListNode(0, head); // 哨兵→处理left=1
    ListNode pre = dummy;
    // 1. 移动到left前一个节点
    for (int i = 1; i < left; i++) {
        pre = pre.next;
    }
    // 2. cur=left位置→要反转的起点
    ListNode cur = pre.next;
    // 3. 头插法→把cur.next插到pre后面→重复(right-left)次
    //    每次把cur的下一个节点移到pre后面
    for (int i = 0; i < right - left; i++) {
        ListNode next = cur.next;    // 要移的节点
        cur.next = next.next;        // cur跳过next
        next.next = pre.next;        // next插到pre后面
        pre.next = next;
    }
    // 过程演示(1->2->3->4->5, left=2, right=4)：
    // 初始: dummy→1→[2]→3→4→5  pre=dummy→1, cur=2
    // i=0: 移3 → dummy→1→3→2→4→5  (3插到1后面→2后面)
    // i=1: 移4 → dummy→1→4→3→2→5  (4插到1后面→3前面)
    // 结果: 1→4→3→2→5 ✓
    return dummy.next;
}
```
/ 哨兵dummy作用：left=1时pre没有前一个节点→dummy充当→统一逻辑 / 头插法核心：cur不动→cur.next一直往后移→每次把cur.next摘出来插到pre后面→pre后面就是反转后的头）

**追问3：** 如果 left=1，right=链表长度（反转整个链表）呢？

> 你回答...（提示：反转整个链表 / left=1→pre=dummy→从头反转→和普通反转链表等价 / 也可以用递归法→但头插法更直观 / 反转整个链表的简洁写法：
```java
public ListNode reverseList(ListNode head) {
    ListNode pre = null, cur = head;
    while (cur != null) {
        ListNode next = cur.next;
        cur.next = pre;   // 反转指针
        pre = cur;        // pre前进
        cur = next;       // cur前进
    }
    return pre;
}
```
→ 反转链表II是反转链表的通用版→区间反转→left=1,right=n时退化为全反转）

**追问4：** 时间复杂度？空间复杂度？边界条件？

> 你回答...（提示：复杂度分析 / 时间O(n)→遍历到left→反转(right-left)次→最坏n / 空间O(1)→只用几个指针 / 边界条件：①left=right→不反转→原样返回 ②left=1→pre=dummy→不需要特殊处理 ③right=链表末尾→cur.next=null→正常处理 ④链表只有一个节点→left=right=1→不反转 ⑤left或right越界→题目保证1≤left≤right≤链表长度 / 踩坑：①忘记dummy→left=1时pre=null→NPE ②循环次数→right-left次→不是right-1次 ③cur.next=next.next→先改cur→再改next→顺序不能反→否则丢失引用 / 举一反三：反转链表→K个一组反转→两两交换→都是头插法变体→掌握头插法→这些题都会）

---

# 二面（30分钟）

## 话题九：企业级 IM 技术架构（10分钟）

**面试官：钉钉是做 IM 的，你了解 IM 系统的技术架构吗？IM 的核心难点是什么？消息怎么保证不丢？**

> 你回答...

**追问1：** 先说说 IM 系统的核心难点是什么。

> 你回答...（提示：IM核心难点 / 6大核心难点：①消息可靠投递→不丢/不重/不乱序 ②消息顺序→同一会话消息按时间排序 ③已读回执→发送方知道对方看了没 ④消息存储→海量消息怎么存怎么查 ⑤长连接管理→百万级TCP连接维持 ⑥离线推送→用户不在线时怎么送达 / 消息可靠投递：发送方→服务端→存消息→推给接收方→接收方ACK→服务端标记已送达→没ACK重推→消息ID防重 / 消息顺序：同一会话用递增序列号→服务端按序列号排序→接收方按序列号处理→如果乱序→缓存等待→序列号连续了再处理）

**追问2：** 钉钉的 IM 架构是什么样的？接入层怎么设计？

> 你回答...（提示：IM架构 / 分层架构：
```
┌─────────────────────────────────────────────────┐
│ 接入层：LVS/F5 → TCP长连接服务器(Netty)          │
│         一台维持约10万连接→弹性扩容→注册到ZK/Redis │
├─────────────────────────────────────────────────┤
│ 逻辑层：消息路由 → 消息存储 → 消息推送 → 已读回执  │
│         → 消息ID生成(Snowflake) → 序列号管理       │
├─────────────────────────────────────────────────┤
│ 存储层：消息存储(MongoDB/MySQL分库分表)            │
│         离线消息(Redis) → 热消息缓存(Redis)        │
└─────────────────────────────────────────────────┘
```
/ 接入层：①LVS→四层负载均衡→TCP连接分发到Netty服务器 ②Netty→维持长连接→心跳保活→30s心跳→5分钟没心跳断开 ③连接路由→用户连接哪台服务器→注册到Redis(userId→serverId)→发消息时查→路由到对应服务器→推送 / 百万长连接：①一台Netty约10万连接(内存+FD限制)→10台=100万→弹性扩缩容 ②单进程FD限制→ulimit -n调大→100万连接需要100万FD ③内存→每个连接约10-50KB(接收/发送缓冲区+Netty对象)→100万≈10-50GB→需要大内存 / 心跳：客户端30s发心跳→服务端回复→5分钟没心跳→认为离线→断开→释放资源）

**追问3：** 消息存储怎么做？读扩散 vs 写扩散？钉钉怎么选？

> 你回答...（提示：读扩散 vs 写扩散 / 读扩散(Read Diffusion)：消息存一份→存到会话的Timeline→每个用户读时→查自己所在会话的最新消息→读放大→大量读请求 / 写扩散(Write Diffusion)：消息存N份→每个接收者的收件箱(Inbox)都写一份→读时直接读自己的收件箱→写放大→但读快
```
单聊(2人)：写扩散 → 2份 → 读快
小群(10人)：写扩散 → 10份 → 可接受
大群(万人群)：写扩散 → 10000份 → 不现实！→ 读扩散 → 1份 → 读时查会话
```
/ 钉钉怎么选：①单聊/小群(≤500人)→写扩散→每人收件箱一份→读时直接查Inbox→快 ②大群(>500人)→读扩散→会话存一份→读时查会话Timeline→按时间分页 ③超大群(万人直播)→推拉结合→在线用户推送→不在线不存→上线拉取 / 存储：①MongoDB→适合写多读少→文档型→消息体灵活→分片(Shard)→按会话ID分片 ②MySQL→分库分表→按用户ID/会话ID分片→ShardingSphere ③热数据Redis→最近100条消息缓存→减少DB访问 ④历史消息→冷存→按时间归档→HBase/对象存储 / 真实数字：钉钉日均消息百亿级→写扩散→每条消息平均3份(单聊为主)→日均300亿写入→需要高吞吐存储→MongoDB分片集群）

---

## 话题十：核心设计题 - 钉钉 IM 消息系统设计（20分钟）

**面试官：设计钉钉的 IM 消息系统。支持千万级用户在线、百万级长连接、日均消息量百亿级。怎么设计？**

> 你回答...

**追问1：** 先说说整体架构。从发送到接收经过哪些环节？

> 你回答...（提示：整体架构 / 消息流转：
```
发送方App → 接入层(Netty) → 消息服务 → 存储 → 推送 → 接入层 → 接收方App

具体流程：
①发送方 → HTTP/TCP → 接入层(Netty Server)
②接入层 → 消息ID生成(Snowflake) → 序列号(会话级递增)
③消息服务 → 消息存储(写扩散/读扩散) → 存MongoDB/MySQL
④消息服务 → 查接收方连接 → 连接在哪台Netty → 推送
⑤接收方Netty → 推给接收方App
⑥接收方App → ACK → 服务端标记已送达
⑦离线 → 存离线消息 → 用户上线拉取
```
/ 技术选型：接入层→Netty+LVS。消息服务→Spring Cloud微服务。存储→MongoDB分片+MySQL分库分表+Redis热缓存。消息队列→RocketMQ(削峰+异步存储)。推送→Netty长连接+APNs/FCM(离线)。连接路由→Redis(userId→serverId)。序列号→Redis INCR(会话级)）

**追问2：** 消息投递可靠性怎么保证？消息顺序怎么保证？消息不丢不重怎么做？

> 你回答...（提示：可靠投递与顺序 / 可靠投递=消息ID+ACK+重推：
①发送方→发消息→clientMsgId(客户端生成UUID)→去重
②服务端→存消息→生成serverMsgId(Snowflake)→序列号(会话级递增)
③推送→发给接收方→带serverMsgId+seq
④接收方→收到→去重(查本地已收serverMsgId)→ACK
⑤服务端→收到ACK→标记已送达
⑥没ACK→定时检查→重推→最多重推3次→超时→离线消息
/ 消息顺序：①同一会话→单调递增序列号→Redis INCR `seq:{conversationId}` ②服务端→按seq推送→接收方→按seq排序处理 ③如果乱序→接收方缓存→等缺失的seq补齐→连续了再处理→类似TCP的滑动窗口 ④群消息→每个成员看到的顺序一致→服务端按seq推送→所有成员收到相同seq序列 / 不丢：①发送方→如果没收到服务端ACK→重发(带clientMsgId去重) ②服务端→消息持久化后才返回ACK→存失败→返回失败→发送方重发 ③推送→没收到接收方ACK→重推→超时→离线 / 不重：①clientMsgId→客户端去重→同一个clientMsgId只发一次 ②serverMsgId→接收方去重→同一个serverMsgId只处理一次 ③幂等→消息处理幂等(如点赞→查有没有点过)）

**追问3：** 消息存储怎么设计？百亿级消息怎么存？历史消息怎么查？

> 你回答...（提示：消息存储 / 存储：①写扩散(单聊/小群)→收件箱→按userId分片 ②读扩散(大群)→会话Timeline→按conversationId分片 ③MongoDB分片→按conversationId分片→同一会话消息在同一Shard→查询快 ④MySQL分库分表→按userId分库→inbox表→每库分表 / 消息表设计：
```sql
-- 写扩散→收件箱
CREATE TABLE inbox (
    user_id BIGINT,        -- 接收者
    conversation_id BIGINT, -- 会话ID
    msg_id BIGINT,          -- 消息ID
    seq BIGINT,             -- 序列号
    sender_id BIGINT,       -- 发送者
    content TEXT,           -- 消息内容
    create_time TIMESTAMP,
    INDEX idx_user_seq (user_id, seq)
);
-- 按user_id分库分表→ShardingSphere
```
/ 百亿级存储：①每天百亿→单表不可能→分库分表→按userId/月分表 ②冷热分离→近7天热数据MongoDB/Redis→7天前冷数据HBase/对象存储 ③TTL→MongoDB设置expire→自动删除超期数据 ④归档→定期归档到HBase→节省MongoDB空间 / 历史消息查询：①按会话+时间分页→游标分页(类似ES search_after)→`WHERE user_id=? AND seq < ? ORDER BY seq DESC LIMIT 20` ②先查Redis热缓存(最近100条)→没有查MongoDB→MongoDB没有查HBase→三级存储 ③群历史→读扩散→查会话Timeline→按seq分页）

**追问4：** 离线消息怎么处理？消息推送怎么做？APNs 限制怎么处理？

> 你回答...（提示：离线消息与推送 / 离线消息：①用户不在线→消息存到离线消息表(inbox)→用户上线→拉取→按seq排序→拉完ACK→删除离线消息 ②离线消息上限→最多存500条→超出的在服务端Timeline→上线后按seq拉取 ③离线消息Redis缓存→快速拉取→不查DB / 推送：①在线→通过长连接(Netty)推送→实时→毫秒级 ②离线→APNs(iOS)/FCM(Android国内用厂商通道)→离线推送→秒级→但有延迟 ③国内Android→各厂商推送通道→华为/小米/OPPO/vivo→到达率不同→需要多通道适配 / APNs限制：①APNs有QPS限制→大量离线推送→需要限流→排队推送 ②APNs推送内容→需要加密→不能明文 ③APNs推送→用户可能关了通知→推送送达但用户不点→需要在App内展示未读 / 离线推送优化：①合并推送→同一个会话多条消息→合并一条推送→"你有3条新消息" ②优先级→重要消息(@我/紧急)→优先推送 ③静默推送→content-available=1→不展示通知→App后台拉取→适合低频重要消息 / 举一反三：钉钉的已读回执→接收方看了消息→上报已读→服务端记录→通知发送方"已读"→群消息→谁看了谁没看→需要群成员已读状态管理→Redis Bitmap(群成员已读状态→每位代表一个成员)→高效 / 小张一句到位：IM消息系统的核心=可靠投递(ACK+重推+去重)+顺序(会话级seq)+存储(写扩散小群+读扩散大群+冷热分离)+离线(在线长连接+离线APNs)→钉钉日均百亿消息→靠MongoDB分片+RocketMQ削峰+Redis热缓存扛住）

---

## 今日总结

| 模块 | 自评 | 标记 |
|------|------|------|
| Netty Reactor（三种Reactor/主从Reactor/EventLoop绑定连接/Pipeline+Handler/自定义编解码） | 能讲清 / 讲不全 / 不会★ | |
| Spring AOP（vs AspectJ/JDK vs CGLIB/洋葱模型/@Transactional AOP实现/事务传播/不生效场景） | 能讲清 / 讲不全 / 不会★ | |
| Arthas诊断（watch/trace/jad/thread/CPU排查/OOM排查/Instrumentation+ASM原理） | 能讲清 / 讲不全 / 不会★ | |
| HikariCP（FastList/ConcurrentBag/参数配置/泄漏检测/连接池满排查） | 能讲清 / 讲不全 / 不会★ | |
| CompletableFuture（thenApply/thenCompose/thenCombine/异常处理/allOf+anyOf/commonPool坑） | 能讲清 / 讲不全 / 不会★ | |
| Java泛型擦除（擦除原理/new T()限制/桥接方法/PECS原则） | 能讲清 / 讲不全 / 不会★ | |
| Gateway源码（请求流程/Predicate+Filter/Filter链洋葱/动态路由Nacos+RefreshRoutesEvent） | 能讲清 / 讲不全 / 不会★ | |
| 手写代码（反转链表II/头插法/全反转/边界条件） | 能讲清 / 讲不全 / 不会★ | |
| IM技术架构（6大难点/接入层百万长连接/读扩散vs写扩散/消息可靠投递/离线推送） | 能讲清 / 讲不全 / 不会★ | |
| IM消息系统设计（消息流转/ACK+重推/序列号顺序/写扩散+读扩散/百亿级存储/离线+APNs） | 能讲清 / 讲不全 / 不会★ | |

### 今日统计
- 不会★：____道 | 讲不全：____道 | 能讲清：____道
- 今天重点补的知识点：_______________
- 明天模拟面试前先复习：_______________

---

> 💡 **今日重点提示**：
> 1. **Netty Reactor**：三种Reactor=单线程(一个线程全做)/多线程(Accept单线程+IO线程池)/主从(BossGroup Accept+WorkerGroup IO+业务线程池)。Netty用主从。EventLoop=一个线程+MPSC任务队列+Selector→一个连接绑定一个EventLoop→从生到死→不需要锁→串行执行。Pipeline=责任链→Inbound从Head到Tail→Outbound从Tail到Head→自定义编解码=ByteToMessageDecoder(半包markReaderIndex/resetReaderIndex)+MessageToByteEncoder
> 2. **Spring AOP**：vs AspectJ=运行时代理 vs 编译时字节码/方法级 vs 方法+字段+构造器。JDK动态代理=基于接口/CGLIB=基于继承→Spring 5.x+默认CGLIB。洋葱模型=@Order值小先执行(入站)。@Transactional=代理+TransactionInterceptor→7种传播(REQUIRED默认/REQUIRES_NEW/NESTED)。不生效=自调用(this不走代理)/private/异常被catch/rollbackFor没配全→解决=AopContext.currentProxy()或注入自己
> 3. **Arthas**：dashboard全局/thread -n看CPU高线程/jad反编译看实际加载类/watch方法出入参/trace调用链耗时/monitor统计。CPU飙高=thread -n直接看堆栈→一步到位。OOM=dashboard看堆+heapdump+MAT或vmtool看大对象。原理=Instrumentation API+ASM→运行时retransformClasses改字节码→不重启→用完exit防GC问题
> 4. **HikariCP**：快在=FastList(不做rangeCheck+remove从尾部LIFO)+ConcurrentBag(ThreadLocal优先+CAS无锁+handoff偷连接)+精简(只有连接池无监控)。参数=maximumPoolSize(核心×2+磁盘)/minimumIdle=maximumPoolSize(常驻)/connectionTimeout=5s/maxLifetime=29min(比DB wait_timeout短1min)/leakDetectionThreshold=60s。坑=maximumPoolSize太大超MySQL max_connections/慢SQL占连接→连接池满→加超时+限流
> 5. **CompletableFuture**：vs Future=非阻塞+回调+组合。API=thenApply(map)/thenCompose(flatMap拆嵌套)/thenCombine(合并两个)/whenComplete(完成回调不改结果)/exceptionally(异常兜底)/handle(成功+异常都可改)。编排=allOf(等所有)/anyOf(任一)。最大坑=默认commonPool(CPU-1=7个线程)→高并发打满→必须传自定义线程池→JDK21可用newVirtualThreadPerTaskExecutor
> 6. **泛型擦除**：编译期检查→运行时擦除→List<String>和List<Integer>都是List。原因=JDK5兼容JDK1.4。问题=new T()不行(传Class<T>)/不能instanceof泛型/不能new泛型数组(Array.newInstance)。桥接方法=编译器自动生成→保证擦除后多态→父类setValue(Object)子类setValue(String)签名不同→生成桥接setValue(Object)调setValue(String)。PECS=Producer Extends(读<? extends T>)/Consumer Super(写<? super T>)
> 7. **Gateway源码**：基于WebFlux(Reactor+Netty)→非阻塞→比Zuul1.x快2倍。流程=RoutePredicateHandlerMapping匹配Route→Filter链(GlobalFilter+GatewayFilter)→前置(鉴权/限流)→NettyRoutingFilter转发→后置(日志/响应改写)。Filter洋葱模型=getOrder值小先→chain.filter(exchange).then(后置)。动态路由=RouteDefinitionRepository(从Nacos读)+监听变更→RefreshRoutesEvent→重新加载→不重启。注意=不能在Filter做阻塞操作→会阻塞EventLoop
> 8. **反转链表II**：头插法→找pre(left前一个)→cur=pre.next→重复(right-left)次→cur.next摘出→插到pre后面→pre.next=next→cur.next=next.next→next.next=pre.next。dummy哨兵处理left=1。O(n)时间O(1)空间。边界=left=1→pre=dummy/left=right不反转/循环right-left次。头插法变体=全反转/K个一组/两两交换
> 9. **IM技术架构**：6大难点=可靠投递(ACK+重推)/顺序(会话级seq)/已读回执/存储(百亿级)/长连接(百万级)/离线推送。架构=接入层(LVS+Netty)→逻辑层(消息路由/存储/推送)→存储层(MongoDB分片+Redis)。读扩散vs写扩散=读扩散(会话存一份/读时查/大群)vs写扩散(每人一份/读快/单聊小群)。钉钉=单聊小群写扩散+大群读扩散。百亿级=MongoDB分片(按conversationId)+冷热分离(7天热Redis→冷HBase)
> 10. **IM消息系统设计**：消息流转=发送方→接入层→消息服务(存+推)→接收方→ACK。可靠=clientMsgId去重+serverMsgId+ACK+重推3次→超时转离线。顺序=Redis INCR会话级seq→服务端按seq推→接收方按seq处理(乱序缓存等连续)。存储=写扩散inbox(按userId分库分表)+读扩散Timeline(按conversationId分片)+三级(Redis热→MongoDB→HBase冷)。离线=在线长连接推送+离线APNs/FCM/厂商通道→合并推送+优先级+静默推送。已读回执=Redis Bitmap(群成员已读状态)
