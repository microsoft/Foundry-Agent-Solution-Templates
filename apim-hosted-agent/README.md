# APIM-hosted Foundry agent

This sample focuses on the API gateway pattern for enterprise AI agents. It deploys a Microsoft Foundry hosted agent with Azure API Management (APIM).
It provides:
- **Agent protection**: Secures agent access through JWT token validation, and DDoS protection.
- **Model token metering and budget control**: Measures token consumption before and after inference and enforces budget pre-checks
- **Tool permission policy**: Uses policies to allow or block tool calls and restrict access to approved tools
- **AI content safety**: Blocks harmful content and prompt-injection attacks at APIM boundaries

## Architecture

![End-to-end request flow through API Management policies and Microsoft Foundry](image/flow.jpg)

The sample includes:

- **Four or five APIM APIs:** a hosted-agent ingress API, a portal-compatible
  model API, a separate OAuth model API used by the agent, one Microsoft Learn
  MCP API, and one GitHub MCP API when GitHub OAuth is configured;

- **Agent ingress policies:** rate-limit requests by source IP, validate
  Microsoft Entra ID bearer tokens for the `https://ai.azure.com` audience,
  derive a trusted per-user key from the token's `tid` and `oid` claims, and
  forward requests to Foundry. The `/responses` operation applies inbound
  prompt-injection detection and harm-category filtering, plus outbound
  harm-category filtering;
- **Model gateway policies:** enforce Bicep-configured aggregate project limits
  on a subscription-key API, and expose a separate managed-identity OAuth API
  for the hosted agent with per-user limits derived by APIM
  from the caller's Entra `tid` and `oid`. Model request and response harm
  input and non-streaming output safety is enforced at the APIM agent boundary.
  Streaming SSE output passes through unchanged because Content Safety buffering
  would consume the event stream. The model
  operation scans non-streaming model output only; streaming model traffic is
  not scanned because scanning Responses streams there breaks event emission.
  No custom Foundry RAI policy is provisioned or forced;
- **Microsoft Learn MCP policies:** provide CORS, per-caller rate limiting, and
  inbound and outbound harm-category filtering with Prompt Shield enabled;
- **GitHub MCP policies:** enabled by default, validate each user's GitHub OAuth
  token against `GET https://api.github.com/user`, deny configured usernames,
  rate-limit by GitHub user ID, and apply
  inbound and outbound harm-category filtering with Prompt Shield enabled. All
  Content Safety harm categories use severity threshold 4.
  Both MCP APIs reference the shared `foundry-tool-content-safety` policy
  fragment, whose XML is maintained once in
  `infra/policies/foundry-tool-content-safety-policy.xml`.

## Run the agent

Run every command from the sample directory:

```powershell
Set-Location .\apim-hosted-agent
```

### 1. Prerequisites

You need:

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli);
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd);
- **Owner**, or both **Contributor** and **User Access Administrator**, at the
  subscription or target resource-group scope;
- **Foundry User** at the subscription scope, or on the new Foundry resource
  before deploying and invoking the agent. **Foundry Owner** is not required;
- Permission and available quota to deploy and use a model in Microsoft Foundry.
  The example configuration below uses `gpt-5-mini` version `2025-08-07` with
  10 Data Zone Standard capacity units.

> **Note:** Change the model and SKU under `services.project.deployments` in
> `azure.yaml`, but keep the deployment name `agent-model`.

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
$location = 'eastus2'
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
azd env set GITHUB_BLOCKED_TOOL_NAMES ''

azd env select $environmentName
```

> [!DETAILS]
> **Create the GitHub OAuth App:** In **GitHub Settings > Developer settings >
> OAuth Apps**, create one app per environment. Use any valid homepage and set
> the initial callback URL to `https://localhost`. Generate a client secret,
> then use its client ID and secret in the commands above. The client secret is
> stored as a normal value in the local `.azure` azd environment, which this
> repository ignores. The Bicep inputs remain marked secure so Azure does not
> include the value in deployment logs. Step 5 replaces the temporary callback
> with the connection's generated redirect URL.

GitHub individual-tool controls are documented in
[APIM Policy Reference](APIM-POLICIES.md#github-tool-controls).

### 3. Provision infrastructure and connections

```powershell
azd provision --no-prompt
```

Provisioning creates the resource group, Foundry account/project/model, Learn
and GitHub connections, RBAC, and APIM service, backends, APIs, policies, named
values, product, and resource links. The Learn and GitHub connections are
declared in `infra/foundry.bicep`. The postprovision hook only canonicalizes
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

This single command deploys the toolbox and hosted agent. For the
Foundry-managed subscription-key model API, including key retrieval and request
examples, see [Foundry-managed model API](FOUNDRY-MANAGED-MODEL-API.md).

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

APIM derives the model rate-limit key from the authenticated user. Use the same
user to test one counter, or sign in as another user to test a separate counter.
See [APIM Policy Reference](APIM-POLICIES.md#end-user-identity-flow) for details.

> [!IMPORTANT]
> Do not use the Foundry playground to validate this sample's per-user model
> limit. The playground bypasses the APIM agent ingress that derives the trusted
> user key, so direct Foundry and playground calls share the `default_user`
> model-limit counter.

If the agent contains an OAuth MCP, the first request that uses it returns an
`oauth_consent_request` with a one-time consent URL. Open that URL, authorize
the OAuth app, and repeat the request. Foundry stores and injects the user's
OAuth token for subsequent tool calls.

## Customize limits

Change per-user limits in **API Management > Named values**. Named-value changes
affect policy execution without changing policy XML. Aggregate project limits
are rendered from Bicep into both the subscription-key model API runtime policy
and the Foundry portal Product Policy.

`azd provision --no-prompt` overwrites manual named-value changes. Update the
corresponding Bicep value before provisioning when a change must persist.

## Policy Defaults

APIM exposes exactly 14 administrator-facing named values. Deployment wiring
such as tenant ID, managed-identity principal ID, backend ID, project name, and
model deployment name is embedded by Bicep and is not shown as policy
configuration.

| Policy XML | APIM scope and purpose | Named values (default) |
| --- | --- | --- |
| `foundry-agent-ingress-policy.xml` | Agent API: validate the bearer token, derive the trusted user key from `tid` and `oid`, and rate-limit by source IP | <ul><li>`policy-agent-rate-limit-requests` (`60`)</li><li>`policy-agent-rate-limit-window-seconds` (`60`)</li></ul> |
| `foundry-agent-content-safety-policy.xml` | Agent `/responses` operation: inbound prompt-injection and harm filtering, plus outbound harm filtering | <ul><li>Five shared `policy-content-safety-*` values</li></ul> |
| `foundry-project-model-key-auth-policy.xml` | Subscription-key model API: select the Foundry backend and enforce Product-configured aggregate project limits | <ul><li>No named values; callers use the `api-key` APIM subscription-key header</li></ul> |
| `foundry-model-oauth-policy.xml` | OAuth model API: authorize the hosted-agent identity and select the Foundry backend | <ul><li>No named values except deployment wiring</li></ul> |
| `foundry-model-content-safety-policy.xml` | OAuth model POST operation: enforce per-user limits and scan model content | <ul><li>Three user-limit values through the fragment</li><li>Four shared harm thresholds</li></ul> |
| `foundry-model-user-level-policy.xml` | Policy fragment: validate the propagated end-user key and enforce per-user token limits | <ul><li>`policy-user-token-limit-per-minute` (`1000000`)</li><li>`policy-user-token-quota` (`10000000`)</li><li>`policy-user-token-quota-period` (`Hourly`)</li></ul> |
| `foundry-project-token-policy.xml` | Product policy: publish the same deployment token metadata in the Foundry portal | <ul><li>No named values; Bicep renders `modelTokenLimit`, `modelTokenQuota`, and `modelTokenQuotaPeriod` into the XML</li></ul> |
| `foundry-tool-learn-mcp-policy.xml` | Microsoft Learn MCP API: CORS, per-caller rate limiting, and the shared Content Safety fragment | <ul><li>`policy-tool-rate-limit-requests` (`60`)</li><li>`policy-tool-rate-limit-window-seconds` (`60`)</li><li>Five shared Content Safety values through the fragment</li></ul> |
| `foundry-tool-github-mcp-policy.xml` | GitHub MCP API: validate GitHub OAuth, apply the username/tool denylists, rate-limit by GitHub user ID, and include the shared Content Safety fragment | <ul><li>`policy-github-blocked-users` (`__none__`)</li><li>`policy-github-blocked-tools` (`__none__`)</li><li>`policy-tool-rate-limit-requests` (`60`)</li><li>`policy-tool-rate-limit-window-seconds` (`60`)</li><li>Five shared Content Safety values through the fragment</li></ul> |
| `foundry-tool-content-safety-policy.xml` | Shared MCP policy fragment: harm-category filtering and Prompt Shield | <ul><li>`policy-content-safety-hate-threshold` (`4`)</li><li>`policy-content-safety-self-harm-threshold` (`4`)</li><li>`policy-content-safety-sexual-threshold` (`4`)</li><li>`policy-content-safety-violence-threshold` (`4`)</li><li>`policy-content-safety-prompt-shield-enabled` (`true`)</li></ul> |

For request flow, counter keys, OAuth scopes, Content Safety behavior, and
deployment details for every policy, see [APIM Policy Reference](APIM-POLICIES.md).

## Current limitations

### Authorization remains in Foundry RBAC

APIM currently validates the caller's bearer token and forwards that same token
to Microsoft Foundry. It does not exchange the caller token for a new Foundry
access token or replace it with a separate downstream identity. Consequently,
access to the Foundry project and agent must still be authorized through Azure
RBAC on the Foundry resources; APIM authentication and authorization policies
alone cannot grant that downstream access. A future version is expected to use
token exchange or another delegated downstream identity pattern.

### Foundry shows only project-linked model policy metadata

The current Foundry and APIM integration exposes only the model token metadata
created by `foundry-project-token-policy.xml` in the Foundry APIM gateway/model
experience. The other policies in `infra/policies`—including agent ingress,
operation-level Content Safety, per-user limits, and MCP governance—are not
shown or managed there. Administrators must manage those policies in the
standard API Management policy experience rather than the APIM AI model view.
This separation is a current limitation of the Foundry–APIM connection and may
change as the integration evolves.


## Troubleshooting

### Provisioning fails with `InsufficientQuota`

The example model configuration requests 10 `gpt-5-mini` Data Zone Standard
capacity units in `eastus2`. The failure can come from either the Foundry
account-count quota or the model quota. Inspect both:

```powershell
az cognitiveservices usage list `
  --location eastus2 `
  --query "[?name.value=='AIServices.S0.AccountCount' || name.value=='OpenAI.DataZoneStandard.gpt-5-mini'].{Quota:name.value,Current:currentValue,Limit:limit}" `
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

Run `scripts/bind-agent-identity.ps1` after deploying the agent and
confirm that the deployed agent identity has the required Azure RBAC role on
the Foundry project.

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
