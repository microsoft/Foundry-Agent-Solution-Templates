# 为 Foundry Google MCP 连接配置 Google OAuth

[English](../google-oauth.md) | [Azure APIM 和 Foundry 指南](README.md)

外部 MCP 服务器在验证令牌 audience 前需要 OAuth 客户端 ID，但 Foundry 的
最终回调只有在 Azure 预配后才可用。因此 OAuth 分两个阶段配置。

## 阶段 A：创建 OAuth 客户端

1. 在托管 MCP 服务器的 Google Cloud 项目中打开
   [Google Auth Platform](https://console.cloud.google.com/auth/overview)。
2. 创建应用。组织内部应用选择 **Internal**；其他 Google 账号选择
   **External**。
3. 对处于 Testing 状态的 External 应用，在
   **Audience > Test users** 中添加所有测试账号。
4. 在 **Data access** 中注册：

   ```text
   openid
   https://www.googleapis.com/auth/userinfo.email
   https://www.googleapis.com/auth/userinfo.profile
   ```

   ![Google Auth Platform 中的身份 scopes](../images/google-oauth-identity-scopes.png)

5. 在 **Clients** 中创建 **Web application** 客户端。
6. 在 **Authorized redirect URIs** 中添加临时 URI。

   ![授权重定向 URI](../images/google-oauth-foundry-redirect-uri.png)

7. 安全保存客户端 ID 和机密。切勿将机密写入源代码、文档、截图、日志或工单。
8. 为外部 MCP 服务器配置：

   ```text
   ALLOWED_CLIENT_IDS=<GOOGLE_OAUTH_CLIENT_ID>
   ```

使用 Google 官方文档部署和验证服务器：

- [在 Cloud Run 上托管 MCP 服务器](https://docs.cloud.google.com/run/docs/host-mcp-servers)
- [构建并部署 Python 服务到 Cloud Run](https://docs.cloud.google.com/run/docs/quickstarts/build-and-deploy/deploy-python-service)

未认证的应用层 MCP 请求应返回 `401`。

模板只请求上述三个身份 scopes。如果已部署工具需要其他 Google API，请启用
该 API，并同时更新 Google Data Access 与 Bicep/Terraform Foundry 连接 scopes。

返回 [Azure 指南](README.md)预配 APIM 和 Foundry。

## 阶段 B：添加 Foundry 回调地址

`azd provision` 导出 `GOOGLE_OAUTH_REDIRECT_URL` 后：

1. 打开同一个 Web 客户端。
2. 将准确的 `GOOGLE_OAUTH_REDIRECT_URL` 添加到
   **Authorized redirect URIs**。
3. 保存客户端并通过 Foundry 完成授权。
4. 验证成功后删除临时重定向 URI。

Google 要求完全匹配，包括协议、主机、路径、大小写和结尾斜杠。切勿复制其他
环境的回调地址。

返回 [Azure 部署步骤](README.md#3-部署)。

## 常见 OAuth 问题

| 现象 | 解决方法 |
| --- | --- |
| `redirect_uri_mismatch` | 将配置的 URI 与 Foundry 输出逐字符比较 |
| `Access blocked` | 在 **Audience > Test users** 中添加账号 |
| `invalid_scope` | 启用所需 API，并从 Data Access 复制准确 scope |
| 同意 URL 返回 404 | 生成新请求；同意 URL 短时有效且只能使用一次 |
| `Code ... not found` | 丢弃已消费/过期 URL并生成新请求 |
| 浏览器成功但重复授权 | 确认环境和调用者是托管还是直接 Toolbox |
| OAuth 后 MCP 返回 `401` | 确认 Foundry 和服务器使用同一客户端 ID |
