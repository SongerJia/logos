---
title: MyBatis面试理论-答案版
tags:
  - Framework
  - Interview-answer
---
#flashcards/Framework/Mybatis/theory
## 一、MyBatis 核心原理

### **Q1** MyBatis 的工作原理完整流程？MyBatis 的插件（Interceptor / Plugin）在整个流程中拦截哪几层？
?
1. MyBatis 的工作原理可以分为几个核心步骤。第一步，加载配置文件。MyBatis 读取 mybatis-config.xml 和 Mapper XML 文件，把 SQL 和映射关系解析成 MappedStatement 对象，缓存在 Configuration 里面。第二步，获取 SqlSession。SqlSessionFactory 通过数据源信息创建一个 SqlSession，它是应用和数据库交互的入口。第三步，通过动态代理调用 Mapper 接口。你调用的 Mapper 接口方法实际上被 MapperProxy 拦截，根据接口全限定名加方法名找到对应的 MappedStatement。第四步，Executor 执行 SQL。Executor 负责实际的 SQL 执行，处理一级缓存、二级缓存、事务等逻辑。第五步，参数处理。ParameterHandler 把 Java 对象的属性映射到 SQL 中的占位符。第六步，JDBC 执行。StatementHandler 创建 PreparedStatement，设置参数，执行 SQL。第七步，结果映射。ResultSetHandler 把 JDBC 返回的 ResultSet 映射成 Java 对象，根据 resultMap 或自动映射规则处理每一行数据。
2. 插件机制可以拦截 MyBatis 的四个核心组件，分别是 Executor、ParameterHandler、StatementHandler、ResultSetHandler。它本质是 JDK 动态代理，通过责任链模式把多个插件层层包装。每个插件必须用 @Intercepts 和 @Signature 指定要拦截的组件、方法和参数类型。最常用的拦截点是 Executor 的 query 和 update 方法，分页插件、慢 SQL 监控都是在这里做的。StatementHandler 也是常用拦截点，比如 SQL 改写、加租户过滤条件。

### **Q2** MyBatis 的一级缓存和二级缓存的区别？为什么默认不推荐开二级缓存？
?
1. 一级缓存是 SqlSession 级别的缓存，默认开启，无法关闭。同一个 SqlSession 内，执行相同的查询语句和参数时，MyBatis 会直接从缓存返回结果，不再查数据库。一级缓存在 SqlSession 执行 insert、update、delete 操作时会自动清空，因为这些操作可能改变数据。SqlSession 关闭时，一级缓存被销毁。
2. 二级缓存是 Mapper 级别的缓存，多个 SqlSession 共享。默认不开启，需要在 mapper XML 里加 `<cache/>` 标签。二级缓存的生命周期和 SqlSessionFactory 一样长，查询结果存入二级缓存后，同一个 namespace 内的所有 SqlSession 都可以共享。二级缓存同样会在 insert、update、delete 时清空。
3. 不推荐开二级缓存的原因有这么几个。第一，脏数据问题。如果另外一个模块直接改数据库，MyBatis 感知不到，二级缓存里的还是旧数据。第二，序列化开销。开启二级缓存要求实体类实现 Serializable 接口，序列化和反序列化有性能开销。第三，缓存粒度不好控制。二级缓存默认是整个 namespace 级别的，很难做到只缓存某几条 SQL，不缓存另几条。第四，分布式环境下不适用。MyBatis 的二级缓存是本地缓存，多个应用实例之间不共享，数据容易出现不一致。所以现在一般用 Redis 这类集中式缓存来做，可控性和一致性都好得多。

### **Q3** MyBatis 的 `#{}` 和 `${}` 的区别？`${}` 的使用前提是什么？
?
1. 核心区别就一句话：`#{}` 是预编译参数占位符，`${}` 是字符串替换。
2. `#{}` 会把参数值以 `?` 的形式拼到 SQL 中，然后用 PreparedStatement 的 setXxx 方法设置参数值。这个过程由 JDBC 驱动完成，天然防 SQL 注入，因为参数值不会被当做 SQL 的一部分执行。
3. `${}` 是直接把参数值拼接到 SQL 字符串中，相当于字符串拼接。如果参数值是用户输入的，攻击者可以注入恶意 SQL，存在严重的 SQL 注入风险。
4. 使用 `${}` 的前提有三条。第一，参数值必须是你自己控制的，不能是用户输入或者任何不可信的外部数据。第二，场景确实只能用它，比如动态表名、动态列名、ORDER BY 排序字段，这些位置 `#{}` 是不支持的，因为表名列名不能作为预编译参数。第三，需要做好白名单校验，比如 ORDER BY 的字段名必须在一个允许的列表内，不在列表内就拒绝请求或者走默认值。

---

## 二、MyBatis 插件 & 拦截器

### **Q4** MyBatis 插件的四大拦截点？你实际用插件做过什么？
?
1. 四大拦截点对应 MyBatis 的四个核心组件。Executor 的拦截点最常用，可以拦截 query、update、commit、rollback 等方法，适合做分页、读写分离、缓存增强。ParameterHandler 拦截参数设置过程，适合做参数加密脱敏。StatementHandler 拦截 SQL 构建和执行，适合做 SQL 改写、加租户过滤、加注释。ResultSetHandler 拦截结果集处理，适合做结果统一脱敏、数据加密解密。
2. 我实际用插件做过几件事。第一，慢 SQL 监控。拦截 Executor 的 query 和 update，记录执行时间，超过阈值就打印 SQL 和参数，告警或者记日志。第二，数据权限过滤。拦截 StatementHandler，在 SQL 上追加租户 ID 或者数据范围的过滤条件。第三，分页，这个常见的就是 PageHelper，它拦截的是 Executor 的 query 方法，在执行 SQL 前先查总数，然后拼上 limit 子句。

### **Q5** MyBatis 的分页插件 PageHelper 的原理是什么？为什么说它是"物理分页"而不是"逻辑分页"？
?
1. PageHelper 的原理是在 MyBatis 的 Executor 层面做拦截。它的工作分五步。第一步，你在代码里调用 PageHelper.startPage(pageNum, pageSize)，PageHelper 把分页参数存到当前线程的 ThreadLocal 里。第二步，你的查询方法执行时，PageHelper 的拦截器检测到有分页参数。第三步，拦截器先执行一条 COUNT SQL，把原始 SQL 包装成 SELECT COUNT(*) FROM (...) tmp_count，拿到总记录数。第四步，拦截器根据 pageNum 和 pageSize 计算出 limit 偏移，在原始 SQL 后面拼上 LIMIT offset, size。第五步，执行分页后的 SQL，把结果和总记录数一起封装成 Page 对象返回。
2. 说它是"物理分页"是因为最终执行的 SQL 确实带了 LIMIT 子句，数据库只返回那几条记录，不是把所有数据查出来再在内存里截取。"逻辑分页"是指一次查出所有数据，然后在应用层做分页截取，PageHelper 显然不是。
3. 不过 PageHelper 也有局限性。COUNT 查询是在原始 SQL 外层嵌套子查询做的，如果原始 SQL 比较复杂，比如有多层子查询或者 UNION，COUNT 语句可能会报错。另外，PageHelper 依赖 ThreadLocal，如果查询是异步执行的，ThreadLocal 里存的分页参数可能传不过去。

---

## 三、MyBatis 性能 & 最佳实践

### **Q6** MyBatis 中批量插入怎么实现？`<foreach>` 批量插入的 SQL 长度有上限吗？
?
1. 批量插入有三种常见方式。第一种是用 `<foreach>` 标签拼一条 INSERT INTO ... VALUES (...), (...), (...) 的 SQL，一次性插入多条。第二种是用 BatchExecutor，设置执行器类型为 BATCH，然后循环调用 insert 方法，最后 flushStatements 提交批量。第三种是直接 JDBC 批处理，不经过 MyBatis 的封装。
2. `<foreach>` 方式的 SQL 长度确实有上限，但这个上限不是 MyBatis 的，而是数据库的限制。MySQL 默认的 max_allowed_packet 是 4MB，如果批量插入的 SQL 超过这个值就会报 Packet too large 错误。另外 MySQL 还有单条 SQL 的语法解析限制，如果 VALUES 列表太长，解析开销很大，性能会下降。
3. 所以批量插入不要一味贪多，一般建议每批 500 到 1000 条，具体数值需要根据单条记录的大小来调。如果数据量特别大，比如几十万条，建议分批次提交，每批次独立一个事务，避免长事务锁表。

### **Q7** MyBatis 中实体属性和数据库字段名不一致怎么处理？你倾向哪种？为什么？
?
1. 有三种处理方式。第一种是 SQL 层面用别名，SELECT user_name AS userName FROM user。简单直接，但每个 SQL 都要写别名，重复劳动多。第二种是开启 MyBatis 的驼峰命名自动映射，在配置文件里设置 mapUnderscoreToCamelCase 为 true，这样 user_name 会自动映射到 userName，不需要额外配置。第三种是用 resultMap 显式指定映射关系，通过 `<result column="user_name" property="userName"/>` 来配置。
2. 我倾向用驼峰命名自动映射加 resultMap 的组合方案。大部分字段命名规范、只是下划线转驼峰的场景，开 mapUnderscoreToCamelCase 就够了，零配置。但如果涉及复杂映射，比如一对一、一对多关联查询，或者字段名和属性名差别太大无法自动映射，这种情况下必须用 resultMap，而且 resultMap 可以复用，性能也最好。
3. 不推荐在每个 SQL 里写别名的方式，维护成本高，字段名一改就要改很多地方。

### **Q8** MyBatis 中 `#{}` 的源码细节？自定义 TypeHandler 的应用场景？
?
1. `#{}` 在源码层面是这样工作的。首先，XML 解析阶段，MyBatis 把 `#{xxx}` 替换为 `?`，同时构建一个 ParameterMapping 对象，记录参数名、JavaType、JdbcType、TypeHandler 等信息。然后，执行阶段，ParameterHandler 遍历所有 ParameterMapping，根据参数名从传入的 Java 对象中取出值，调用对应的 TypeHandler 的 setParameter 方法，把 Java 类型的值转换成 JDBC 类型，设置到 PreparedStatement 上。
2. TypeHandler 就是用来做 Java 类型和 JDBC 类型之间的双向转换的。MyBatis 内置了 StringTypeHandler、IntegerTypeHandler、DateTypeHandler 等常见类型的处理器。
3. 自定义 TypeHandler 的典型应用场景有这么几个。第一，枚举映射。比如数据库存 0 或 1，Java 端想用 ENABLED / DISABLED 枚举，可以写一个 TypeHandler 做双向转换。第二，JSON 字段。数据库里存 JSON 字符串，Java 端想用对象或者 Map，TypeHandler 在写入时序列化、读取时反序列化。第三，加密脱敏。比如手机号存到数据库自动加密，读出来自动解密，TypeHandler 里集中处理，业务代码无感知。第四，非标准类型，比如数据库里是 PG 的 INET 类型，Java 端想用 String，写个 TypeHandler 处理转换。

---

## 四、动态 SQL & DAO 层设计

### **Q9** MyBatis 的动态 SQL 标签？`<where>` 标签的好处是什么？
?
1. MyBatis 常用的动态 SQL 标签有这么几个。`<if test="">` 条件判断，最基础也是最常用的。`<choose>`、`<when>`、`<otherwise>` 相当于 if-else if-else 的分支选择。`<foreach>` 遍历集合，用来做 IN 查询或者批量插入。`<trim>`、`<where>`、`<set>` 用来处理前缀后缀的拼接过剩问题。`<bind>` 创建一个变量，在 SQL 中复用。`<sql>` 和 `<include>` 抽取公共的 SQL 片段。
2. `<where>` 标签的好处有两层。第一层是它能自动处理第一个条件的 AND 或 OR 前缀。比如你有三个 `<if>` 条件，如果第一个条件不成立，SQL 会变成 WHERE AND xxx，这是语法错误。`<where>` 标签会智能地把多余的 AND 或 OR 去掉。第二层是它能自动判断是否需要 WHERE 关键字。如果所有条件都不成立，WHERE 根本就不会出现在 SQL 里。这比手写 `WHERE 1=1` 然后一个个拼 `AND` 优雅得多，`WHERE 1=1` 虽然也能解决问题，但不够干净，而且有些数据库的优化器看到 `1=1` 可能放弃索引。

### **Q10** 为什么 MyBatis 的 Mapper 接口不需要实现类？如果不写 XML 而是用 `@Select` 注解，MyBatis 内部怎么处理？
?
1. Mapper 接口不需要实现类是因为 MyBatis 用了 JDK 动态代理。核心流程是这样的：SqlSession.getMapper 方法调用时，MyBatis 通过 MapperProxyFactory 创建一个 MapperProxy 代理对象。你调用 Mapper 接口的任何方法，都会被 MapperProxy 的 invoke 方法拦截。invoke 方法拿到接口全限定名和方法名，拼接成 statementId，比如 com.xxx.UserMapper.findById，然后从 Configuration 中找到对应的 MappedStatement，最后通过 SqlSession 执行对应的 SQL。
2. 用 `@Select` 注解时，MyBatis 的处理方式本质上和 XML 一样，只是解析来源不同。启动时 MyBatis 扫描 Mapper 接口，遇到 `@Select`、`@Insert` 等注解，通过 AnnotationMethodParser 把注解里的 SQL 解析成 MappedStatement，同样存入 Configuration。后续执行流程和 XML 方式完全相同，都是通过 statementId 找 MappedStatement 再执行。
3. 但注解方式有局限性：复杂的动态 SQL 写在注解里可读性很差，而且 SQL 变更需要重新编译，不像 XML 改完重启就行。所以一般简单的增删改查用注解，复杂的查询用 XML，两者可以共存。

---

## 五、MyBatis-Plus

### **Q11** MyBatis-Plus 相比原生 MyBatis 多了什么？MyBatis-Plus 有坑吗？
?
1. MyBatis-Plus 是对 MyBatis 的增强，核心是减少重复的 CRUD 代码。它提供 BaseMapper 接口，内置了 insert、deleteById、updateById、selectById、selectList 等通用方法，继承它就不用每个表都写基础 CRUD 的 XML。还提供了条件构造器 Wrapper，用链式 API 构建查询条件，LambdaQueryWrapper 基于 Lambda 表达式做类型安全的字段引用，字段名改了代码编译就报错，不会运行时才发现。另外还有自动分页插件，不需要额外引入 PageHelper。代码生成器可以根据表结构自动生成 Entity、Mapper、Service、Controller，项目初期能省很多时间。还有逻辑删除、乐观锁、自动填充这些常用功能的注解支持。
2. 坑也有几个。第一，LambdaQueryWrapper 的 getLambdaColumn 本质是反射解析 Lambda 表达式的序列化信息，如果 JVM 禁用了 SerializedLambda 的安全策略，会直接报错。第二，自动生成的代码可能和团队规范不一致，需要定制生成模板，否则生成出来还得手动改。第三，BaseMapper 提供的 updateById 会更新所有字段，包括你不想更新的字段，如果字段值是 null，除非加了 @TableField 的 updateStrategy，否则会把数据库字段刷成 null。第四，对复杂查询的支持不如手写 SQL 灵活，联表查询、子查询、聚合函数这些还是得自己写 XML 或者注解 SQL。第五，版本升级时接口偶尔有不兼容变更，比如 3.x 到最新版的 API 调整。

---

## 六、综合对比 & 场景

### **Q12** MyBatis vs JPA / Hibernate 的选型思考？
?
1. 两者的设计哲学完全不同。MyBatis 是 SQL 为中心的半自动化框架，你写 SQL，它帮你做参数映射和结果映射，你对 SQL 有完全的控制权。JPA 是对象为中心的自动化框架，你定义实体关系，它根据 HQL 或方法名自动生成 SQL，SQL 对你是透明的。
2. 选 MyBatis 的场景有这些。第一，业务需求多变，SQL 需要精细调优，比如报表、数据平台、复杂的多表关联查询，你需要控制每一个 JOIN、每一个索引的使用，JPA 自动生成的 SQL 大概率不是最优的。第二，团队对 SQL 很熟，希望直接写 SQL 而不是学一套新的 ORM 语法。第三，数据库已经存在，表结构不规则，有些表连主键都没有，JPA 在这种情况下很难映射。
3. 选 JPA 的场景有这些。第一，标准的企业级 CRUD 应用，表结构规范，业务逻辑简单，JPA 的方法命名查询和自动 DDL 能提升开发效率。第二，项目初期需要快速迭代，频繁改表结构，JPA 的自动建表改表能力省去很多手写 DDL 的时间。第三，团队偏向面向对象思维，不想直接和 SQL 打交道。
4. 实际项目中，两者也可以混用，核心业务流程用 MyBatis 做精细控制，简单的 CRUD 管理后台用 JPA 或 MyBatis-Plus 提效。

### **Q13** MyBatis 的一个查询，SQL 打印出来了有值但实际查 DB 为 0 行，可能是什么原因？
?
1. 这种问题有几个常见方向排查。
2. 第一，参数类型不匹配。比如数据库字段是 VARCHAR 类型，但 MyBatis 传参用了 INTEGER 类型。MySQL 在某些情况下会做隐式类型转换，可能导致索引失效或者匹配不上。你要确认参数类型和字段类型是否一致。
3. 第二，参数带有不可见字符。比如前端传来的参数带有首尾空格、换行符、全角半角混用，肉眼看到的值和实际值不一样。用 `length()` 确认字符串实际长度，用 `hex()` 查看字节内容。
4. 第三，事务隔离级别的问题。如果查询在一个未提交的事务中执行，而这个查询用的数据和另一个事务正在修改的数据有关，可能因为 MVCC 机制读到的是旧版本的数据。比如你先查一次有值，另一个事务改了还没提交，你再查可能就是 0 行。检查当前事务隔离级别，特别是可重复读下比较容易踩这个坑。
5. 第四，MyBatis 的 `#{}` 和 `${}` 用混了。如果本应该用 `${}` 的动态表名或列名用了 `#{}`，会被当成字符串参数而不是标识符，导致 SQL 语义错误。反过来，该用 `#{}` 的地方用了 `${}`，值加了引号，拼接后反而破坏了 SQL 语法。
6. 第五，数据库连接指向了错误的库。多数据源配置时，可能 A 库的 SQL 打在了 B 库的连接上。验证一下日志里的数据源 ID 和实际要查的库是否一致。

### **Q14** 你们项目里 MyBatis 的 SQL 写在 XML 还是注解？怎么管理 XML 文件？
?
1. 我们项目里是 XML 和注解混用。简单的增删改查放注解，用 MyBatis-Plus 的 BaseMapper 更省事。复杂的多表关联查询、动态条件查询都放在 XML 里，因为 SQL 结构复杂，XML 里用 `<choose>`、`<foreach>` 这些标签写起来清晰，可读性远好于注解。
2. XML 文件的管理策略有这么几条。第一，XML 和 Mapper 接口放在同一层级目录下，接口在 src/main/java/com/xxx/mapper 下，XML 在 src/main/resources/mapper 下，按模块分子目录。第二，XML 的文件名和 Mapper 接口名一一对应，比如 UserMapper.java 对应 UserMapper.xml。第三，在 application.yml 里配置 mapper-locations 扫描路径，不用在 mybatis-config.xml 里一个个注册。
3. 另外我们还要求 SQL 的 id 命名规范，比如 insert、deleteById、selectById 这些基础操作的名字要和 MyBatis-Plus 保持一致，自定义查询用 selectByXxx、countByXxx 这种见名知义的格式。SQL 审核方面，我们要求每条 SQL 必须能在 Navicat 或 DataGrip 中独立运行，方便调试和 DBA 审核。SQL 格式统一用大写关键字、小写表名列名的风格，提高可读性。
