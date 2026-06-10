|#|知识点|重要度|笔记三层建议|跨模块关联|
|---|---|---|---|---|
|5.1|**SSL/TLS 证书配置流程**|🟡 应掌握|① 申请证书（Let's Encrypt 免费 / 购买证书）→ Nginx 配置 ssl_certificate / ssl_certificate_key → 80 强制跳转 443 ② 证书链要完整（fullchain.pem）③ 面试：HTTPS 握手过程？TLS 1.2 和 1.3 区别？|→ 密码学基础（对称/非对称加密）|
|5.2|**HSTS & 安全 Header**|🟢 了解|① `add_header Strict-Transport-Security` 防 SSL 剥离攻击；X-Frame-Options / X-Content-Type-Options 等 ② CSP（Content-Security-Policy）防 XSS ③ 面试：你知道哪些 Web 安全相关的 HTTP Header？|→ 安全架构方向（OWASP Top 10）|
|5.3|**HTTP/2 & gRPC 代理**|🟢 了解|① Nginx 支持 HTTP/2（`listen 443 http2`）：多路复用 / 头部压缩 / 服务端推送 ② Nginx 可以做 gRPC 反向代理（`grpc_pass`）③ 面试：HTTP/2 相比 HTTP/1.1 有哪些优势？gRPC 能过 Nginx 吗？|→ 微服务通信（gRPC vs RESTful）|