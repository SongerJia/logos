---
title: MyBatis面试理论
tags:
  - Framework
  - Interview
---

## 一、MyBatis 核心原理

> **Q1** MyBatis 的工作原理完整流程？MyBatis 的插件（Interceptor / Plugin）在整个流程中拦截哪几层？

> **Q2** MyBatis 的一级缓存和二级缓存的区别？为什么默认不推荐开二级缓存？

> **Q3** MyBatis 的 `#{}` 和 `${}` 的区别？`${}` 的使用前提是什么？

---

## 二、MyBatis 插件 & 拦截器

> **Q4** MyBatis 插件的四大拦截点？你实际用插件做过什么？

> **Q5** MyBatis 的分页插件（PageHelper）的原理是什么？为什么说 PageHelper 是"物理分页"而不是"逻辑分页"？

---

## 三、MyBatis 性能 & 最佳实践

> **Q6** MyBatis 中批量插入怎么实现？`<foreach>` 批量插入的 SQL 长度有上限吗？

> **Q7** MyBatis 中实体属性和数据库字段名不一致怎么处理？你倾向哪种？为什么？

> **Q8** MyBatis 中 `#{}` 的源码细节？自定义 TypeHandler 的应用场景？

---

## 四、动态 SQL & DAO 层设计

> **Q9** MyBatis 的动态 SQL 标签？`<where>` 标签的好处是什么？

> **Q10** 为什么 MyBatis 的 Mapper 接口不需要实现类？如果不写 XML 而是用 `@Select` 注解，MyBatis 内部怎么处理？

---

## 五、MyBatis-Plus

> **Q11** MyBatis-Plus 相比原生 MyBatis 多了什么？MyBatis-Plus 有坑吗？

---

## 六、综合对比 & 场景

> **Q12** MyBatis vs JPA / Hibernate 的选型思考？

> **Q13** MyBatis 的一个查询，SQL 打印出来了有值但实际查 DB 为 0 行，可能是什么原因？

> **Q14** 你们项目里 MyBatis 的 SQL 写在 XML 还是注解？怎么管理 XML 文件？
