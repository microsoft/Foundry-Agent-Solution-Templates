# Configure Google MCP in Azure APIM and Foundry

[Configure Google OAuth](google-oauth.md)

This guide connects an existing Google OAuth-protected Streamable HTTP MCP
server to the APIM-hosted Foundry agent. Google MCP is disabled by default.

This repository does not deploy the Cloud Run server. Follow Google's official
guides:

- [Host MCP servers on Cloud Run](https://docs.cloud.google.com/run/docs/host-mcp-servers)
- [Build and deploy a Python service to Cloud Run](https://docs.cloud.google.com/run/docs/quickstarts/build-and-deploy/deploy-python-service)

## Before you begin

Prepare:

- `GOOGLE_OAUTH_CLIENT_ID`;
- `GOOGLE_OAUTH_CLIENT_SECRET`;
- a public HTTPS MCP endpoint ending in `/mcp`.

Create the Web client with a temporary redirect URI by following
[Configure Google OAuth](google-oauth.md). Configure the external server to
validate tokens for the same client ID. An unauthenticated MCP request should
reach the application and return `401`.

Complete the main template [prerequisites](../../README.md#1-prerequisites).
Terraform users must activate `azure-terraform.yaml` as described in the main
README and use a separate azd environment from Bicep.

## 1. Configure azd and the Toolbox

Run from `apim-hosted-agent`:

```powershell
azd env set GOOGLE_MCP_ENABLED 'true'
azd env set GOOGLE_MCP_ENDPOINT 'https://<cloud-run-service-host>/mcp'
azd env set GOOGLE_OAUTH_CLIENT_ID '<google-web-oauth-client-id>'
azd env set GOOGLE_OAUTH_CLIENT_SECRET '<google-web-oauth-client-secret>'
```

Keep the secret outside source control and protect the local `.azure/`
directory.

Optional exact-match denylists:

```powershell
azd env set GOOGLE_BLOCKED_EMAILS 'blocked-user@example.com'
azd env set GOOGLE_BLOCKED_TOOL_NAMES '<tool-name-1>,<tool-name-2>'
```

Only use tool names returned by the live server's `tools/list`.

Add Google to `services.tools.tools` in the active `azure.yaml`:

```yaml
- connection: google
  name: google
  require_approval: always
  server_label: google
  type: mcp
```

The committed manifests intentionally omit this entry. All Google values must
be present before it can deploy.

> [!IMPORTANT]
> In an existing Bicep deployment, `GOOGLE_MCP_ENABLED=false` does not delete
> previously created Google APIM or Foundry resources because ARM deploys
> incrementally. Remove the Toolbox entry to hide Google, then delete those
> resources explicitly or run `azd down`. Terraform can remove its
> state-managed Google resources on reprovision.

## 2. Provision and register the callback

```powershell
azd provision --no-prompt
$googleRedirectUrl = (azd env get-value GOOGLE_OAUTH_REDIRECT_URL).Trim()
$googleRedirectUrl
```

Provisioning creates the Google APIM API/backend and Foundry OAuth connection.
The redirect URL must be a non-empty HTTPS URL.

Open the same Google Web client and follow
[OAuth stage B](google-oauth.md#stage-b-add-the-foundry-callback). Add
`$googleRedirectUrl` exactly as emitted.

![Foundry redirect URL registered in Google](images/google-oauth-foundry-redirect-uri.png)

## 3. Deploy

```powershell
azd deploy --no-prompt
azd ai agent show --output json
```

Continue when the agent version is `active` or `deployed`. The governed
endpoint is:

```text
https://<APIM_NAME>.azure-api.net/agent/responses
```

## 4. Call the agent API

Send one simple stateless request. The agent response will contain either a
normal message or an OAuth consent request.

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

Interpret `response.output`:

- `message`: the agent returned a normal response.
- `oauth_consent_request`: open its `consent_link`, wait for
  **Authentication successful**, then rerun the same request.
- `mcp_approval_request`: OAuth succeeded, but the tool still requires approval.

Each request uses `store=false` and is independent. If consent is requested
again, use only the newest link. Never reuse an older URL or use
`previous_response_id`.

## Common issues

| Symptom | Resolution |
| --- | --- |
| `redirect_uri_mismatch` | Compare Google configuration with `GOOGLE_OAUTH_REDIRECT_URL` exactly |
| Consent URL returns 404 or `Code ... not found` | Generate a new stateless request and use its newest URL |
| Consent repeats after browser success | Confirm the environment and caller identity; hosted and direct Toolbox consent are separate |
| MCP returns `401` after OAuth | Verify the external server validates the same client ID |
| `mcp_approval_request` | Continue with a client that supports Foundry MCP approval |

See [Google OAuth troubleshooting](google-oauth.md#common-oauth-issues) for
Google application, scope, callback, and test-user errors.
