主内存与工作内存交互

热可见性 / 原子性 / 有序性

热happens-before 规则（8条）

热指令重排序 & 内存屏障

热volatile 的实现原理

as-if-serial 语义

final 域的可见性保证

long/double 非原子读写




|#|知识点|重要度|三层笔记建议|面试追问|FlowPulse 结合|
|---|---|---|---|---|---|
|B2-37|**指令重排序典型案例：DCL失效**|★★★|L1: instance = new Singleton() 编译为：①分配内存②构造对象③指向引用；②③可能重排导致其他线程看到半初始化对象；L2: JDK5+volatile修复(插入Memory Barrier禁止重排序)；L3: JSR-133内存模型规范明确此行为|DCL不加volatile在什么条件下出问题？概率有多大？|单例组件(Dubbo Reference/Nacos Config)的DCL安全声明|
|B2-38|**long/double 非原子读写问题**|★★☆|L1: JVM规范允许long/double分两次32位操作；L2: 64位JVM上大多数实现原子化(但规范仍不保证)；L3: 解决方案：AtomicLong/volatile long/加synchronized|64位HotSpot上还需要担心这个问题吗？Volatile long的开销？|Snowflake ID生成器的long型返回值安全|
|B2-39|**happens-before 实战分析**|★★☆|L1: 分析一段代码中是否存在HB关系来判断是否需要同步；L2: 常见误区：volatile修饰引用不代表引用内部字段的可见性；L3: JMM Cookbook中的经典案例集|这段代码需要加volatile吗？两个volatile变量之间有HB吗？|分布式事务Seata中锁状态的可见性分析|
|B2-40|**伪共享(False Sharing)与@Contended**|★★☆|L1: Cache Line通常64字节——两个无关变量在同一行会导致"伪共享"(互相invalidate对方cache line)；L2: LongAdder的Cell数组用@Contended注解填充避免伪共享；L3: -XX:-RestrictContended开启@Contended(默认JDK8受限)|怎么发现伪共享问题？填充字节的代价？|FlowPulse高频计数器的缓存行隔离设计|