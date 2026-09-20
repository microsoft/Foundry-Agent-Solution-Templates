# 在 Azure APIM 和 Foundry 中配置 Google MCP

[English](../README.md) | [配置 Google OAuth](google-oauth.md)

本指南将现有的、受 Google OAuth 保护的 Streamable HTTP MCP 服务器连接到
APIM 托管的 Foundry 智能体。Google MCP 默认处于禁用状态。

本仓库不部署 Cloud Run 服务器。请使用 Google 官方文档：

- [在 Cloud Run 上托管 MCP 服务器](https://docs.cloud.google.com/run/docs/host-mcp-servers)
- [构建并部署 Python 服务到 Cloud Run](https://docs.cloud.google.com/run/docs/quickstarts/build-and-deploy/deploy-python-service)

## 开始之前

准备：

- `GOOGLE_OAUTH_CLIENT_ID`；
- `GOOGLE_OAUTH_CLIENT_SECRET`；
- 以 `/mcp` 结尾的公共 HTTPS MCP 端点。

按照[配置 Google OAuth](google-oauth.md)创建带临时重定向 URI 的 Web 客户端。
配置外部服务器，使其验证同一个客户端 ID。未认证 MCP 请求应到达应用并返回
`401`。

完成主模板中的[先决条件](../../../README.md#1-prerequisites)。Terraform 用户
按照主 README 激活 `azure-terraform.yaml`，并使用与 Bicep 不同的 azd 环境。

## 1. 配置 azd 和 Toolbox

从 `apim-hosted-agent` 运行：

```powershell
azd env set GOOGLE_MCP_ENABLED 'true'
azd env set GOOGLE_MCP_ENDPOINT 'https://<cloud-run-service-host>/mcp'
azd env set GOOGLE_OAUTH_CLIENT_ID '<google-web-oauth-client-id>'
azd env set GOOGLE_OAUTH_CLIENT_SECRET '<google-web-oauth-client-secret>'
```

将机密保存在源代码之外，并保护本地 `.azure/` 目录。

可选精确匹配拒绝列表：

```powershell
azd env set GOOGLE_BLOCKED_EMAILS 'blocked-user@example.com'
azd env set GOOGLE_BLOCKED_TOOL_NAMES '<tool-name-1>,<tool-name-2>'
```

仅使用实时服务器通过 `tools/list` 返回的工具名称。

在生效的 `azure.yaml` 的 `services.tools.tools` 中添加 Google：

```yaml
- connection: google
  name: google
  require_approval: always
  server_label: google
  type: mcp
```

已提交的清单有意不包含此条目。部署前必须设置所有 Google 值。

## 2. 预配并注册回调地址

```powershell
azd provision --no-prompt
$googleRedirectUrl = (azd env get-value GOOGLE_OAUTH_REDIRECT_URL).Trim()
$googleRedirectUrl
```

预配会创建 Google APIM API/后端和 Foundry OAuth 连接。重定向 URL 必须为
非空 HTTPS URL。

打开同一个 Google Web 客户端，按照
[OAuth 阶段 B](google-oauth.md#阶段-b添加-foundry-回调地址)准确添加
`$googleRedirectUrl`。

![在 Google 中注册 Foundry 回调](../images/google-oauth-foundry-redirect-uri.png)

## 3. 部署

```powershell
azd deploy --no-prompt
azd ai agent show --output json
```

当智能体版本为 `active` 或 `deployed` 时继续。治理入口为：

```text
https://<APIM_NAME>.azure-api.net/agent/responses
```

## 4. 调用 Agent API

发送一个简单的无状态请求。智能体响应会直接包含普通消息或 OAuth 授权请求。

```powershell
$token = (az account get-access-token `
  --resource https://ai.azure.com/ `
  --query accessToken `
  --output tsv).Trim()
$apimName = (azd env get-value APIM_NAME).Trim()
$gateway = "https://$apimName.azure-api.net/agent/responses"

$body = @{
  input = 'Use Google MCP and return a short non-personal result.'
  store = $false
} | ConvertTo-Json -Compress

$json = $body | curl.exe --silent --show-error --fail-with-body `
  --request POST $gateway `
  --header "Authorization: Bearer $token" `
  --header 'Content-Type: application/json' `
  --data-binary '@-'

if ($LASTEXITCODE -ne 0) {
  throw "Request failed with curl exit code $LASTEXITCODE."
}

$response = ($json -join "`n") | ConvertFrom-Json
$response.status
$response.output | ConvertTo-Json -Depth 10
```

查看 `response.output`：

- `message`：智能体返回普通响应。
- `oauth_consent_request`：打开其中的 `consent_link`，等待
  **Authentication successful**，然后重新发送同一个请求。
- `mcp_approval_request`：OAuth 已成功，但工具仍需要审批。

每个请求都使用 `store=false`，彼此独立。如果再次请求授权，只使用最新链接。
切勿重复使用旧 URL，也不要使用 `previous_response_id`。

## 常见问题

| 现象 | 解决方法 |
| --- | --- |
| `redirect_uri_mismatch` | 与 `GOOGLE_OAUTH_REDIRECT_URL` 逐字符比较 |
| 同意 URL 返回 404 或 `Code ... not found` | 生成新的无状态请求并使用最新 URL |
| 浏览器成功后重复授权 | 确认环境和调用者身份；托管与直接 Toolbox 授权独立 |
| OAuth 后 MCP 返回 `401` | 确认外部服务器验证同一个客户端 ID |
| `mcp_approval_request` | 使用支持 Foundry MCP 审批的客户端继续 |

Google 应用、scope、回调和测试用户错误参见
[Google OAuth 故障排查](google-oauth.md#常见-oauth-问题)。
