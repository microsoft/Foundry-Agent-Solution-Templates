# APIM-hosted Foundry agent

This sample focuses on the API gateway pattern for enterprise AI agents. It deploys a Microsoft Foundry hosted agent with Azure API Management (APIM).
It provides:
- **Agent protection**: Secures agent access through mTLS authentication, JWT token validation, and DDoS protection.
- **Model token metering and budget control**: Measures token consumption before and after inference and enforces budget pre-checks
- **Tool permission policy**: Uses policies to allow or block tool calls and restrict access to approved tools
- **AI guardrails**: Detects prompt-injection attacks and masks PII

## Architecture

![End-to-end request flow through API Management policies and Microsoft Foundry guardrails](image/flow.jpg)

The sample includes:

- **Agent-level APIM control:** validates Microsoft Entra ID bearer tokens for
  the `https://ai.azure.com` audience and rate-limits requests by source IP;
- **Model-level APIM control:** restricts the keyless model gateway to the
  hosted agent's managed identity and enforces token-per-minute limits and
  fixed-period token quotas per project, agent principal, and deployment;
- **Tool-level APIM control:** governs the Microsoft Learn MCP route with per-caller rate limiting
- **Guardrails:** apply blocking Foundry RAI filters for harmful content at
  every agent and tool stage, jailbreak attempts before agent execution, task
  adherence before tool calls, indirect attacks in tool output, and protected
  text or code in final model output.

## Run the agent

Run every command from the repository root.

### 1. Prerequisites

You need:

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli);
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd);
- **Contributor** or **Owner** on the target Azure resource group;
- **Foundry Account Owner** or **Foundry Owner** on the Foundry resource;
- Permission and available quota to deploy and use a model in Microsoft Foundry.
  This sample defaults to `gpt-5-mini` with 10 Global Standard capacity units in `eastus2`.

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
$apimName = '<globally-unique-apim-name>'
$publisherEmail = 'you@example.com'
$publisherName = 'Your organization'

azd env new $environmentName `
  --subscription $subscriptionId `
  --location eastus2

azd env set AZURE_RESOURCE_GROUP $environmentName
azd env set APIM_NAME $apimName
azd env set APIM_PUBLISHER_EMAIL $publisherEmail
azd env set APIM_PUBLISHER_NAME $publisherName
```

When `azd env new` asks whether to make the environment the default, select
**Yes**. To switch environments later, run:

```powershell
azd env select $environmentName
```

### 3. Provision infrastructure

```powershell
azd provision --no-prompt
```

### 4. Set the hosted-agent RAI policy

Get the full ARM resource ID of the provisioned RAI policy:

```powershell
azd env get-value GUARDRAIL_POLICY_ID
```

Copy the command output. In `azure.yaml`, find
`services.agent.policies[0].raiPolicyName` and replace
`REPLACE_WITH_FULL_RAI_POLICY_ARM_ID` with the copied value. The value must be
the complete ARM ID ending in `/raiPolicies/<policy-name>`.

This manual step is required before each environment's first deployment because
the current `azure.ai.agents` extension doesn't expand an azd environment value
inside `raiPolicyName`.

### 5. Deploy the connection, toolbox, and agent

```powershell
azd deploy --no-prompt
```

### 6. Call the remote agent

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

## Policy Defaults

| Route | Authentication | Policies | Default limit |
| --- | --- | --- | --- |
| `/agent/responses` | Foundry bearer token | Per-IP rate limit | 60 calls per 60 seconds |
| `/<account>-keyless/api/projects/<project>/openai/v1/*` | Hosted-agent Entra identity | `llm-token-limit` | 1,000,000 TPM and 100,000 tokens/hour |
| `/<account>/api/projects/<project>/openai/v1/*` | No subscription provisioned | No model policy; retained for the Foundry project link | Not a runtime route |
| `/tool-<project>-mcp` | No APIM subscription | Rate limit and `llm-content-safety` | 60 calls per 60 seconds; harm threshold 4 |

Hosted-agent model counters use:

```text
project/<project-name>/principal/<agent-oid>/deployment/<deployment-name>
```

The MCP counter uses the caller IP when no APIM subscription is present.


## Troubleshooting

### Provisioning fails with `InsufficientQuota`

The default deployment requests 10 `gpt-5-mini` Global Standard capacity
units in `eastus2`. Free capacity or use a subscription/region with enough
quota before provisioning again.

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

Run `scripts/configure-keyless-model-gateway.ps1` after deploying the agent and
confirm the `foundry-agent-principal-id` APIM named value matches the agent
instance identity.

## Cleanup

```powershell
azd down
```

Review the resource group and Foundry/APIM links before confirming deletion.

## References

- [Microsoft Foundry hosted agents](https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agents)
- [Azure API Management AI gateway](https://learn.microsoft.com/azure/api-management/genai-gateway-capabilities)
- [APIM `llm-token-limit` policy](https://learn.microsoft.com/azure/api-management/llm-token-limit-policy)
- [APIM `llm-content-safety` policy](https://learn.microsoft.com/azure/api-management/llm-content-safety-policy)
