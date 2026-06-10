|#|组件|使用的模式|具体位置|源码关键类|
|---|---|---|---|---|
|**1.7.1**|**IOC 容器**|工厂 + 单例 + 注册表|Bean创建管理|`DefaultListableBeanFactory`, `SingletonBeanRegistry`|
|**1.7.2**|**AOP 代理**|代理 + 责任链 + 适配器|方法拦截|`JdkDynamicAopProxy`, `CglibAopProxy`, `ReflectiveMethodInvocation`|
|**1.7.3**|**BeanPostProcessor**|观察者 + 职责链|Bean生命周期钩子|`AutowiredAnnotationBeanPostProcessor`(依赖注入), `CommonAnnotationBeanPostProcessor`|
|**1.7.4**|**HandlerAdapter**|适配器|MVC处理器适配|`RequestMappingHandlerAdapter`, `HttpRequestHandlerAdapter`, `SimpleControllerHandlerAdapter`|
|**1.7.5**|**ViewResolver**|策略|视图解析选择|`InternalResourceViewResolver`, `FreeMarkerViewResolver`, `ContentNegotiatingViewResolver`|
|**1.7.6**|**JdbcTemplate**|模板方法|数据库操作骨架|`JdbcTemplate.query()/update()`定义骨架，回调接口留扩展|
|**1.7.7**|**EventListener**|观察者|事件驱动|`ApplicationEventPublisher.publishEvent()` → `@EventListener`|
|**1.7.8**|**Resource**|策略 + 抽象工厂|资源加载|`ClassPathResource`, `FileSystemResource`, `UrlResource`|
|**1.7.9**|**FactoryBean**|工厂 + 代理|复杂Bean构建|`MapperFactoryBean`(MyBatis整合), `ProxyFactoryBean`(AOP)|
|**1.7.10**|**Environment**|桥接 + 策略|配置属性源|`PropertySource`(文件/Nacos/Git) → `Environment`统一访问|