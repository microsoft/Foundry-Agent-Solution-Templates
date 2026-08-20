# APIM-hosted Foundry agent

This sample focuses on the API gateway pattern for enterprise AI agents. It deploys a Microsoft Foundry hosted agent with Azure API Management (APIM).
It provides:
- **Agent protection**: Uses Azure platform DDoS protection, APIM rate limiting, and Microsoft Entra token validation.
- **Model token metering and budget control**: Enforces per-platform-user tokens-per-minute and hourly token quotas.
- **Tool permission policy**: Applies governed MCP policies and optional GitHub user and tool denylists.
- **AI content safety**: Explicitly blocks harmful Responses model prompts and applies shared safety policies to agent and MCP boundaries.

## Architecture

![End-to-end request flow through API Management policies and Microsoft Foundry](image/flow.jpg)

The sample includes:

- **Three APIM APIs:** a hosted-agent ingress API, a direct hosted-agent model API, and governed MCP tool APIs for Microsoft Learn and GitHub;
- **Agent ingress policies:** rate-limit requests by source IP, validate Microsoft Entra ID bearer tokens for the `https://ai.azure.com` audience, and forward requests to Foundry without adding a custom user header. The `/responses` operation retains generic inbound safety and non-streaming outbound harm filtering; the model gateway performs the explicit Responses prompt extraction and harmful-content check;
- **Model gateway policies:** authenticate the hosted agent, enforce harmful-content checks and per-user token limits, and route Responses requests to Foundry with managed identity;
- **Microsoft Learn MCP policies:** provide CORS, per-caller rate limiting, and
  inbound and outbound harm-category filtering with Prompt Shield enabled;
- **GitHub MCP policies:** validate GitHub OAuth, enforce user and tool denylists,
  rate-limit callers, and apply shared Content Safety checks.

## Run the agent

Run every command from the `apim-hosted-agent` directory.

### 1. Prerequisites

You need:

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli);
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd);
- **Owner**, or both **Contributor** and **User Access Administrator**, at the
  subscription or target resource-group scope;
- **Foundry Owner** on the Foundry resource;
- Permission and available quota to deploy and use a model in Microsoft Foundry.
  The example configuration uses `gpt-5.6-luna` version `2026-07-09` with one
  Data Zone Standard capacity unit.

Sign in to both CLIs with the same tenant:

```powershell
az login
azd auth login
```

### 2. Create an azd environment

Choose a new environment name, subscription, APIM name, and publisher details.
Use the environment name as the resource-group name.

```powershell
$environmentName = '<environment-name>'
$subscriptionId = '<subscription-id>'
$location = 'eastus'
$apimName = '<globally-unique-apim-name>'
$publisherEmail = 'you@example.com'
$publisherName = 'Your organization'

azd env new $environmentName `
  --subscription $subscriptionId `
  --location $location

azd env set AZURE_RESOURCE_GROUP $environmentName
azd env set APIM_NAME $apimName
azd env set APIM_PUBLISHER_EMAIL $publisherEmail
azd env set APIM_PUBLISHER_NAME $publisherName

azd env set GITHUB_OAUTH_CLIENT_ID '<github-oauth-client-id>'
azd env set GITHUB_OAUTH_CLIENT_SECRET '<github-oauth-client-secret>'

azd env set GITHUB_BLOCKED_USER_NAMES 'octocat,another-user' # Exact GitHub usernames, comma-separated; case-insensitive; use '' for none.
azd env set GITHUB_BLOCKED_TOOL_NAMES 'get_me,delete_file' # Exact MCP tool names, comma-separated; case-insensitive; use '' for none.

azd env select $environmentName
```

> [!DETAILS]
> **Create the GitHub OAuth App:** In **GitHub Settings > Developer settings >
> OAuth Apps**, create one app per environment. Use any valid homepage and set
> the initial callback URL to `https://localhost`. Generate a client secret,
> then use its client ID and secret in the commands above. Step 5 replaces the
> temporary callback with the connection's generated redirect URL.

GitHub individual-tool controls are documented in
[APIM Policy Reference](APIM-POLICIES.md#github-tool-controls).

### 3. Provision infrastructure and connections

```powershell
azd provision --no-prompt
```

Provisioning creates the resource group, Foundry account/project/model, Learn
connection, RBAC, and APIM service, backends, APIs, policies, named values,
and resource links. When both GitHub OAuth values are configured, it
also creates the GitHub APIM resources and Foundry connection. The connections
are declared in `infra/foundry.bicep`. The postprovision hook canonicalizes
resource links. Step 4 deploys the toolbox and agent.

> [!NOTE]
> To deploy without GitHub, remove the GitHub object from
> `services.tools.tools` and do not set `GITHUB_OAUTH_CLIENT_ID` or
> `GITHUB_OAUTH_CLIENT_SECRET`. With both values absent or empty, Bicep skips
> the GitHub connection and its APIM backend, API, and policy.

### 4. Deploy the toolbox and agent

```powershell
azd deploy --no-prompt
```

This single command deploys the toolbox and hosted agent.

### 5. Configure the OAuth MCP

This sample uses GitHub as the OAuth MCP example. Bicep exports the generated
redirect URL to the selected azd environment, so retrieve it after provisioning:

```powershell
azd env get-value GITHUB_OAUTH_REDIRECT_URL
```

Replace the temporary callback in the GitHub OAuth App with this exact URL and
save the app. The callback is configuration only: do not open it directly
because it does not contain the OAuth `state` parameter.

For deployments without GitHub, skip this step.

### 6. Test the agent

Call the governed agent through APIM:

```powershell
$token = (az account get-access-token `
  --resource https://ai.azure.com/ `
  --query accessToken `
  --output tsv).Trim()

$apimName = (azd env get-value APIM_NAME).Trim()
$agentGateway = "https://$apimName.azure-api.net/agent/responses"
$body = @{
  input = 'What is Azure API Management?'
  store = $false
} | ConvertTo-Json -Compress

$body | curl.exe --request POST $agentGateway `
  --header "Authorization: Bearer $token" `
  --header 'Content-Type: application/json' `
  --data-binary '@-'
```

The hosted agent points `FoundryChatClient` at the project-compatible APIM
endpoint and uses the deployment name directly. The runtime requires Foundry's
platform-provided `user_id_key`; middleware hashes it into the trusted
`x-client-end-user-key` sent only to the APIM model endpoint. The model API
policy applies a separate token counter for each platform user identity.

If the agent contains an OAuth MCP, the first request that uses it returns an
`oauth_consent_request` with a one-time consent URL. Open that URL, authorize
the OAuth app, and repeat the request. Foundry stores and injects the user's
OAuth token for subsequent tool calls.

## Customize limits

Change per-user model limits, request-rate, GitHub governance, and Content
Safety settings in **API Management > Named values**. Named-value changes affect
policy execution without changing policy XML. Rate-limit and token-limit values
are included in their counter keys, so changing a configured limit starts a
fresh counter namespace.

`azd provision --no-prompt` overwrites manual named-value changes. Update the
corresponding Bicep value before provisioning when a change must persist.

## Policy Defaults

APIM exposes exactly 13 administrator-facing named values. Deployment wiring
such as tenant ID, project managed-identity principal ID, backend ID, project
name, and model deployment name is embedded by Bicep and is not shown as policy
configuration.

| Policy XML | APIM scope and purpose | Named values (default) |
| --- | --- | --- |
| `foundry-agent-ingress-policy.xml` | Agent API: validate the bearer token and rate-limit by source IP; no custom user header is added | <ul><li>`policy-agent-rate-limit-requests` (`60`)</li><li>`policy-agent-rate-limit-window-seconds` (`60`)</li></ul> |
| `foundry-agent-content-safety-policy.xml` | Agent `/responses` operation: generic inbound safety and non-streaming outbound harm filtering | <ul><li>Five shared `policy-content-safety-*` values</li></ul> |
| `foundry-model-gateway-policy.xml` | Direct hosted-agent model API: authorize the hosted identity, apply model safety and per-user quota fragments, and select the Foundry project backend | <ul><li>`foundry-agent-principal-id` plus two user-limit values through the quota fragment</li></ul> |
| `foundry-model-content-safety-policy.xml` | Apply Content Safety to the model Responses request | <ul><li>Five shared `policy-content-safety-*` values</li></ul> |
| `foundry-model-user-level-policy.xml` | Validate `x-client-end-user-key` and enforce its per-user token counter | <ul><li>`policy-user-tokens-per-minute` (`1000`)</li><li>`policy-user-token-quota-per-hour` (`100`)</li></ul> |
| `foundry-tool-learn-mcp-policy.xml` | Microsoft Learn MCP API: CORS, per-caller rate limiting, and the shared Content Safety fragment | <ul><li>`policy-tool-rate-limit-requests` (`60`)</li><li>`policy-tool-rate-limit-window-seconds` (`60`)</li><li>Five shared Content Safety values through the fragment</li></ul> |
| `foundry-tool-github-mcp-policy.xml` | GitHub MCP API: validate GitHub OAuth, apply the username/tool denylists, rate-limit by GitHub user ID, and include the shared Content Safety fragment | <ul><li>`policy-github-blocked-users` (`__none__`)</li><li>`policy-github-blocked-tools` (`__none__`)</li><li>`policy-tool-rate-limit-requests` (`60`)</li><li>`policy-tool-rate-limit-window-seconds` (`60`)</li><li>Five shared Content Safety values through the fragment</li></ul> |
| `foundry-tool-content-safety-policy.xml` | Shared MCP policy fragment: harm-category filtering and Prompt Shield | <ul><li>`policy-content-safety-hate-threshold` (`4`)</li><li>`policy-content-safety-self-harm-threshold` (`4`)</li><li>`policy-content-safety-sexual-threshold` (`4`)</li><li>`policy-content-safety-violence-threshold` (`4`)</li><li>`policy-content-safety-prompt-shield-enabled` (`true`)</li></ul> |

For request flow, counter keys, managed-identity trust, OAuth scopes, Content Safety behavior, and
deployment details for every policy, see [APIM Policy Reference](APIM-POLICIES.md).

## Current limitations

> **Note:** APIM plans to release new capabilities for these scenarios. This
> sample will be updated when those features become available, and parts of the
> current custom implementation may be removed.

### Per-user token control uses custom middleware

The hosted agent currently uses custom middleware to derive a trusted user key
from Foundry's platform user identity and forward it to APIM for per-user token
control. A native APIM per-user token-control feature is planned for a future
release. After that capability is available, applications can use the native
feature instead of this custom middleware.

### Authorization remains in Foundry RBAC

APIM currently validates the caller's bearer token and forwards that same token
to Microsoft Foundry. It does not exchange the caller token for a new Foundry
access token or replace it with a separate downstream identity. Consequently,
access to the Foundry project and agent must still be authorized through Azure
RBAC on the Foundry resources; APIM authentication and authorization policies
alone cannot grant that downstream access. A future release is planned to
improve this identity flow so applications do not need to rely on the current
RBAC-dependent forwarding pattern.

### Custom policies are managed in API Management

The Foundry portal retains the linked APIM model API, but it does not expose
the custom agent ingress, operation-level Content Safety,
per-user quota, or MCP governance policies.
Administrators manage those policies in the standard API Management policy
experience.

## Troubleshooting

### Model deployment configuration does not match

Keep `services.project.deployments` in `azure.yaml` and `modelDeploymentName`
in `infra/apim.parameters.json` aligned.

### Provisioning fails with `InsufficientQuota`

The example model configuration requests one `gpt-5.6-luna` Data Zone Standard
capacity unit. The failure can come from either the Foundry account-count quota
or the model quota. Inspect both in the selected environment region:

```powershell
$location = (azd env get-value AZURE_LOCATION).Trim()

az cognitiveservices usage list `
  --location $location `
  --query "[?name.value=='AIServices.S0.AccountCount' || name.value=='OpenAI.DataZoneStandard.gpt-5.6-luna'].{Quota:name.value,Current:currentValue,Limit:limit}" `
  --output table
```

If the account count is at its limit, use a region with available
`AIServices.S0.AccountCount` quota. If the model quota is insufficient, free
capacity, reduce `sku.capacity` in `azure.yaml`, or use a subscription, region,
model, and SKU with enough quota before provisioning again.

Resource-group locations are immutable. If provisioning creates the resource
group but fails for regional quota, choose another region and create a new azd
environment with a new resource-group name instead of changing
`AZURE_LOCATION` on the failed environment.

### Commands target the wrong environment

```powershell
azd env list
azd env select '<environment-name>'
azd env get-values
```

### Agent invocation returns HTTP 401

Acquire a token for `https://ai.azure.com/` and include it as a bearer token.
An ARM token is not valid for the agent ingress.

### Model calls return HTTP 401

Confirm the hosted-agent identity has **Foundry User**, the
`foundry-agent-principal-id` APIM named value matches that identity, and the
agent uses the `/ai-gateway/api/projects/<project>` endpoint. Run
`./scripts/bind-agent-identity.ps1` after reprovisioning the APIM layer.

### Model calls return HTTP 403

`Quota Exceeded` means the per-user hourly quota is consumed. The default
`policy-user-token-quota-per-hour` value is `100`, which is intentionally small
and can be consumed by one model call. Changing the TPM or hourly quota named
value creates a new counter key and starts a fresh counter. `Blocked by Content
Safety` means the model harmful-content policy rejected the prompt.

## Cleanup

```powershell
azd down
```

Review the resource group and Foundry/APIM links before confirming deletion.

## References

- [Microsoft Foundry hosted agents](https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agents)
- [Azure API Management AI gateway](https://learn.microsoft.com/azure/api-management/genai-gateway-capabilities)
- [APIM `llm-content-safety` policy](https://learn.microsoft.com/azure/api-management/llm-content-safety-policy)
- [APIM `llm-token-limit` policy](https://learn.microsoft.com/azure/api-management/llm-token-limit-policy)
- [Azure AI Content Safety](https://learn.microsoft.com/azure/ai-services/content-safety/overview)
