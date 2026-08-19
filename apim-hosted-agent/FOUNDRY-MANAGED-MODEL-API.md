# Foundry-managed model APIs

The deployment creates two APIM paths to the same Foundry model backend:

- a portal-compatible subscription-key API for direct consumers; and
- a managed-identity API exposed as an account-level Foundry Admin-connected
  model, with an additional project-compatible Responses route used directly by
  the hosted agent.

APIM uses its system-assigned managed identity to call the Foundry account on
both paths. The identity receives **Cognitive Services User** on the account.

## Shared managed-identity model API

The Bicep deployment registers the model gateway as an account-level Admin
connection with these important properties:

```text
authType: ProjectManagedIdentity
audience: https://cognitiveservices.azure.com
target: https://<apim>.azure-api.net/ai-gateway/models
deploymentInPath: false
inferenceAPIVersion: 2024-05-01-preview
isSharedToAll: true
```

It is created at Foundry account scope, not project scope. This is required for
it to appear in **Foundry resource > Admin > Connected models**. The connection
uses the project managed identity.

The hosted agent uses its deployment name and points `FoundryChatClient` at:

```text
https://<apim>.azure-api.net/ai-gateway/api/projects/<project>
```

1. Middleware adds `x-client-end-user-key` to the Responses request.
2. APIM validates the hosted identity for the `https://ai.azure.com` audience.
3. APIM validates the user key and applies the per-user token counter.
4. APIM calls the Foundry project Responses API using its managed identity.

The account-level Admin connection remains visible and continues to use
`POST /ai-gateway/models/chat/completions`, but it is not the hosted runtime path.

The hosted-agent identity receives **Foundry User** so it can call the project.
Anonymous callers, user tokens, and unrelated identities are rejected by the
model API. No APIM subscription key or model key is stored in the agent.

## Subscription-key model API

The portal-compatible model API is a separate path for direct API consumers. It
requires an API Management Product subscription key:

- Header: `api-key`
- Query parameter alternative: `subscription-key`

The key authenticates the caller to APIM; it is not a Foundry model key. APIM
removes the key before calling the backend.

### Retrieve the subscription key

Run these commands from the repository root after provisioning:

```powershell
$subscriptionId = (azd env get-value AZURE_SUBSCRIPTION_ID).Trim()
$resourceGroup = (azd env get-value AZURE_RESOURCE_GROUP).Trim()
$apimName = (azd env get-value APIM_NAME).Trim()
$subscriptionName = (azd env get-value APIM_FOUNDRY_SUBSCRIPTION_NAME).Trim()

$apiKey = az rest `
  --method post `
  --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/subscriptions/$subscriptionName/listSecrets?api-version=2024-05-01" `
  --query primaryKey `
  --output tsv
```

### Call the subscription-key API

```powershell
$accountName = (azd env get-value AZURE_AI_ACCOUNT_NAME).Trim()
$projectName = (azd env get-value AZURE_AI_PROJECT_NAME).Trim()
$modelGateway = "https://$apimName.azure-api.net/$accountName/api/projects/$projectName/openai/v1/responses"
$body = @{
  model = 'gpt-5.6-luna'
  input = 'What is Azure API Management?'
  store = $false
} | ConvertTo-Json -Compress

$body | curl.exe --request POST $modelGateway `
  --header "api-key: $apiKey" `
  --header 'Content-Type: application/json' `
  --data-binary '@-'
```

A missing or invalid subscription key returns HTTP `401`.

## Portal registration

The subscription-key API remains associated with an APIM Product, active
Product-scoped subscription, and Foundry resource links. APIM performs built-in
subscription-key authentication and uses a minimal inline policy to select the
managed-identity model backend. No Product token policy or aggregate token quota
is applied.

Hosted-agent Responses calls continue to use the separate `modelUserToken*`
per-user settings. A request without a valid `x-client-end-user-key` is rejected
with `403`.

See [APIM Policy Reference](APIM-POLICIES.md) for the complete policy map.
