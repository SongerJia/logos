|知识点|笔记时重点写什么|
|---|---|
|**配置中心解决的问题**|热 配置散落在各服务 → 修改配置需要重启 → 不同环境配置难以管理。集中化、动态化、版本化管理配置|
|**Nacos Config 使用方式**|引入依赖 → bootstrap.yml 中配 `spring.cloud.nacos.config.server-addr` + `namespace` → Data ID（格式：`${prefix}-${spring.profile.active}.${file-extension}`）→ Group → 在 Nacos 控制台编辑配置 → 发布后客户端自动刷新|
|**配置动态刷新机制**|热 客户端长轮询监听配置变更（默认 30s 间隔）→ Nacos 服务端配置 MD5 变化推送变更事件 → 客户端收到后重新拉取最新配置 → 更新 Environment 中的 PropertySource → **标注了 `@RefreshScope` 的 Bean 会被销毁重建以应用新值**|
|**@RefreshScope 原理与坑**|核 被 @RefreshScope 标注的 Bean 会创建为懒加载代理。配置刷新时销毁旧 Bean 下次使用时创建新 Bean。**坑**：不要在 @Configuration 类上使用（会导致配置类重复加载）；静态变量/常量不会刷新|
|**共享配置与扩展配置**|`shared-configs`（多个服务共享的基础配置，如 Redis/MQ 地址）、`extension-configs`（某几个服务共享的扩展配置）。加载顺序：主配置 > 扩展配置 > 共享配置，后者覆盖前者|
|**配置加密与安全**|敏感信息（数据库密码 / API Key）不能明文存 Nacos。方案：①Nacos 自带的加密插件 ②Jasypt 加密（运行时解密）③外部密钥管理服务（如 Vault）。生产环境必须考虑|