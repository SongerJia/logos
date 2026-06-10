|#|知识点|核心内容|对比/细节|面试追问|FlowPulse 实现|
|---|---|---|---|---|---|
|**6.1.1**|**JWT (JSON Web Token) ★**|三段式：Header(算法).Payload(声明).Signature(签名)；无状态认证，服务端不存Session；自包含用户信息|Access Token(短期15min) + Refresh Token(长期7天) 双Token机制|"JWT的优缺点？和Session相比安全性如何？Token被盗了怎么办？"|**★ auth-service 核心**: JJWT生成 / RSA256签名 / 双Token轮换|
|**6.1.2**|**OAuth2.0 授权框架**|四种授权模式：授权码(Authorization Code, 最安全) / 隐式(Implicit, 已废弃) / 密码式(Resource Owner, 仅信任客户端) / 客户端凭证(Client Credentials, 服务间调用)|授权码+PKCE(移动端安全增强) 是当前最佳实践|"OAuth2是认证还是授权？OIDC和OAuth2什么关系？"|内部系统用密码模式(服务间Dubbo调用凭Token)；未来对接企业微信/钉钉走授权码模式|
|**6.1.3**|**OIDC (OpenID Connect)**|在OAuth2之上增加身份层；ID Token(JWT格式，含用户身份信息) + UserInfo Endpoint + Discovery端点(`/.well-known/openid-configuration`)|OAuth2解决"能干什么"(授权)，OIDC解决"你是谁"(认证)|"ID Token和Access Token的区别？"|V2.0 规划：支持企业微信SSO登录(OIDC协议)|
|**6.1.4**|**SSO 单点登录**|一次登录处处访问；CAS(Central Authentication Service)协议 / SAML 2.0 / OIDC Session Management；共享Domain或跨域方案|同域: Cookie共享；跨域: Ticket/Token中继/PostMessage|"同域SSO和跨域SSO分别怎么实现？"|auth-service 作为统一认证中心 → Gateway JWT校验 → 各微服务信任Token|

> **🔥 FlowPulse 认证架构全景**

```
┌──────────┐                                     ┌──────────────┐
│  Browser  │  ① POST /auth/login               │  Gateway      │
│  (Vue3)   │ ─────────────────────────────────→ │  (JWT校验层)  │
└──────────┘                                     │              │
         ② 返回 {accessToken, refreshToken}     └──────┬───────┘
         ←────────────────────────────────────          │ ③ 转发+附加Header(X-User-ID)
                                                            ▼
                                                     ┌──────────────┐
                                                     │ 业务微服务     │
                                                     │ (信任Gateway) │
                                                     └──────────────┘

Token 结构:
{
  "sub": "user-10086",           // Subject: 用户唯一标识
  "iss": "flowpulse-auth",       // Issuer: 签发者
  "aud": "flowpulse-gateway",    // Audience: 受众
  "exp": 1740000000,             // Expiration: 过期时间
  "iat": 1739999100,             // IssuedAt: 签发时间
  "jti": "uuid-xxxxx",           // JWT ID: 唯一标识(防重放)
  "roles": ["admin","approver"], // 自定义: 角色
  "perms": ["process:start"]     // 自定义: 权限
```