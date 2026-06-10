Location 规则看似简单但**细节全是坑**，配置错误会导致路由混乱。

|#|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|3.1|**Location 四种匹配类型及优先级**|🔴 必背|① **精确匹配(=)** > **正则匹配(~, ~*)** > **前缀匹配(最长优先）** ② 完整排序：`= /path` (最高) > `^~ /path` (禁止正则) > `~ \.php$` (正则) > `/path` (普通前缀) ③ 面试：以下 location 顺序，请求 `/api/user` 匹配哪个？（经典手写题）|→ M2 proxy_pass（不同 location 不同 upstream）|
|3.2|**rewrite 重写规则**|🟡 应掌握|① `rewrite regex replacement [flag]`；四种 flag：last（重写后重新匹配 location）/ break（停止匹配）/ redirect（302临时）/ permanent（301永久）② 常见场景：URL 规范化、去斜杠、http→https 跳转、API 版本路由 ③ 面试：rewrite 的 last 和 break 区别？（高频陷阱题）|→ M5 HTTPS（强制跳转 https）|
|3.3|**if 指令的陷阱**|🟡 应掌握|① Nginx 的 if 是 "evil of nginx"——部分场景下行为反直觉（if 内的指令不一定按预期执行）② 安全用法：只用于 return / rewrite 这种简单指令，不要把 proxy_pass 放 if 里 ③ 面试：Nginx 的 if 指令有什么坑？正确的替代方案是什么？|→ M8 排障（配置调试技巧）|
|3.4|**try_files 指令**|🟡 应掌握|① `try_files $uri $uri/ /index.html;` — SPA 应用部署标配（Vue/React 前端路由）② 依次尝试：文件存在直接返回 → 目录 → fallback ③ 面试：前端 SPA 项目用 Nginx 部署，刷新 404 怎么解决？|→ 前端方向（SPA 路由 / history mode）|
|3.5|**动静分离配置实践**|🟡 应掌握|① 静态资源（js/css/img/html）由 Nginx 直接返回，动态 API 请求 proxy_pass 到后端 ② 典型配置结构：`location /api { proxy_pass ... }` + `location ~* \.(jpg\|css)$ { root ... }` ③ 面试：什么是动静分离？为什么要做？实际效果怎么样？|→ CDN（M4 缓存延伸）、→ 浏览器缓存策略|

> **🏗️ 架构追问**：现在很多团队用 Gateway（Spring Cloud Gateway）做路由而不是 Nginx Location。你觉得什么情况下应该选 Nginx 做路由？什么情况该用 API Gateway？两者能否共存？