### 为什么这个模块

**OAuth2 是"第三方授权登录"的标准协议**（微信登录/QQ登录/Google 登录都是 OAuth2）。理解它能让你搞清楚"登录"和"授权"的区别。

### 知识点表

|序号|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|5.1|**OAuth2 四种角色 & 核心概念**|🔴必背|① **Resource Owner**（资源所有者=用户）→ **Client**（第三方应用=你的网站）→ **Authorization Server**（授权服务器=微信/支付宝）→ **Resource Server**（资源服务器=微信用户信息API）② 核心概念：Authorization Code（授权码） / AccessToken（访问令牌） / RefreshToken（刷新令牌） / Scope（授权范围）/ RedirectURI（回调地址）③ 面试：解释 OAuth2 的四个角色各自的角色？|→ JWT（AccessToken 常用 JWT 格式）|
|5.2|**授权码流程（Authorization Code）— 最常用最安全**|🔴必背|① 完整流程：用户点击"微信登录" → 跳转到微信授权页 → 用户同意 → 微信回调带 code → 你的服务器用 code 换 access_token → 用 access_token 获取用户信息 → 登录完成 ② 为什么安全？code 只能用一次（短期有效），access_token 在服务端获取（不暴露给前端）③ 面试：画出完整的 OAuth2 授权码流程图？为什么授权码模式比隐式模式安全？|→ HTTP 协议（302 重定向）/ HTTPS（必须！）|
|5.3|**四种授权模式对比**|🔴必背|① **授权码码模式**（推荐）：最安全，有 code 中转 ② **简化模式（Implicit）**：纯前端，Token 直接暴露在 URL（不推荐，已被废弃）③ **密码模式（Password）**：客户端直接传密码（适合自家应用信任度高）④ **客户端凭据模式（Client Credentials）**：无用户参与，机器间通信（如 Server-to-Server API 调用）⑤ 面试：四种模式分别适用什么场景？为什么隐式模式不推荐？|→ S4 JWT RefreshToken（与授权码模式的联系）|
|5.4|**Spring Authorization Server（替代已弃用的 Security OAuth2）**|🟡应掌握|① Spring Security OAuth2 项目已停止维护（2020年） ② 新方案：**Spring Authorization Server**（独立项目，由社区驱动） ③ 核心：ClientRegistration（注册客户端） / TokenSettings（Token 配置） / AuthorizationServerSettings ④ 面试：你们项目用什么做 OAuth2 服务端？为什么不用旧的 Security OAuth2？|→ Spring Boot Starter（自动配置）|