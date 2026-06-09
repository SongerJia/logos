|知识点|笔记时重点写什么|
|---|---|
|**BaseMapper 通用 CRUD**|热 继承 BaseMapper<T> 即可获得：insert / deleteById / deleteByMap / updateById / selectById / selectBatchIds / selectByMap / selectList / selectPage 等方法。无需手写 XML。泛型 T 就是实体类，MP 通过反射获取表名和字段映射|
|**条件构造器 QueryWrapper / UpdateWrapper**|热 以链式调用构建 WHERE 条件：`.eq("name", "张三") .ge("age", 18) .like("email", "@qq.com") .orderByDesc("create_time")`。UpdateWrapper 支持 `.set("status", 0)` 直接设置更新值。**LambdaQueryWrapper** 可以避免硬编码字符串（用 `User::getName` 代替 `"name"`）推荐使用|
|**分页插件 PaginationInnerInterceptor**|MP 3.4+ 版本内置的分页拦截器（不再依赖 PageHelper）。配置方式：`MybatisPlusInterceptor.addInnerInterceptor(new PaginationInnerInterceptor(DbType.MYSQL))`。用法：`page(new Page<>(1, 10))`，返回 Page 对象包含 records（数据列表）、total（总数）、pages（总页数）|
|**代码生成器 AutoGenerator / FastAutoGenerator**|根据数据库表结构自动生成 Entity / Mapper / Service / Controller 四层代码。配置数据源 URL、包路径、策略（是否 Lombok / Swagger / REST 风格）、模板引擎（Velocity / Freemarker / Beetl）。**跳槽时可以提一句"搭建过代码生成脚手架"加分**|
|**逻辑删除**|热 实体字段加 `@TableLogic`，配置 logic-delete-value（已删除值，通常 1）和 logic-not-delete-value（未删除值，通常 0）。MP 自动在所有查询 SQL 后面追加 `WHERE deleted=0`，delete 操作变成 UPDATE SET deleted=1。**注意：物理表要有 deleted 字段**|
|**自动填充（MetaObjectHandler）**|热 `@TableField(fill = FieldFill.INSERT)` 标注创建时间/创建人字段，`fill = FieldFill.INSERT_UPDATE` 标注更新时间/更新人字段。实现 MetaObjectHandler 接口的 `insertFill()` 和 `updateFill()` 方法统一填充。**避免了每处手写 new Date() 的重复代码**|
|**MP 底层增强原理简述**|MP 通过 ISqlInjector 注入通用 CRUD 的 MappedStatement（相当于动态往 Configuration 里注册 SQL）。BaseMapper 的方法调用最终走的还是 MyBatis 原生的 Executor 链路，只是 SQL 由 MP 自动生成而非你手写。**理解这一点就知道 MP 不是魔法，而是 MyBatis 插件机制的深度应用**|