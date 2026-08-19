# APIM Policy Reference

This document describes every APIM policy XML file in `infra/policies`, where
it is deployed, and how requests flow through it.

## Policy inventory

| Policy XML | APIM scope | Purpose |
| --- | --- | --- |
| `foundry-agent-ingress-policy.xml` | Hosted-agent API | Authenticate callers, derive the trusted user key, and apply IP rate limiting |
| `foundry-agent-content-safety-policy.xml` | Hosted-agent `/responses` operation | Apply inbound and outbound Content Safety |
| `foundry-hosted-admin-model-policy.xml` | Integrated Admin-connected model API | Authenticate the project identity and select the Cognitive Services backend |
| `foundry-hosted-direct-responses-policy.xml` | Integrated model API `createResponses` operation | Authenticate the hosted identity, apply per-user limits, and select the project backend |
| `foundry-model-user-level-policy.xml` | Policy fragment | Validate the propagated user key and apply per-user token limits |
| `foundry-tool-learn-mcp-policy.xml` | Microsoft Learn MCP API | Apply CORS, caller rate limiting, and the shared tool Content Safety fragment |
| `foundry-tool-github-mcp-policy.xml` | GitHub MCP API | Validate GitHub OAuth, enforce username and exact-tool denylists, rate-limit by GitHub user ID, and apply tool Content Safety |
| `foundry-tool-content-safety-policy.xml` | Policy fragment | Provide shared inbound/outbound MCP harm filtering and Prompt Shield configuration |

## Named-value inventory

APIM exposes 14 administrator-facing policy named values:

| Configuration area | Named values |
| --- | --- |
| Agent request rate | `policy-agent-rate-limit-requests`, `policy-agent-rate-limit-window-seconds` |
| Per-user model tokens | `policy-user-token-limit-per-minute`, `policy-user-token-quota`, `policy-user-token-quota-period` |
| MCP request rate | `policy-tool-rate-limit-requests`, `policy-tool-rate-limit-window-seconds` |
| GitHub governance | `policy-github-blocked-users`, `policy-github-blocked-tools` |
| Content Safety | `policy-content-safety-hate-threshold`, `policy-content-safety-self-harm-threshold`, `policy-content-safety-sexual-threshold`, `policy-content-safety-violence-threshold`, `policy-content-safety-prompt-shield-enabled` |

Admin-connection tenant, project-principal, hosted-agent principal, and backend
values are deployment wiring.

`azd provision --no-prompt` reapplies Bicep-owned values and can overwrite
manual named-value edits. Change the corresponding Bicep value before
provisioning when a setting must persist.

## Agent policies

### `foundry-agent-ingress-policy.xml`

The policy is attached to the hosted-agent API. It rate-limits requests by
source IP, validates a Microsoft Entra bearer token for the
`https://ai.azure.com` audience, hashes `tid:oid` as
`platform/<sha256>`, and overwrites `x-client-end-user-key` before forwarding
the request to Foundry.

The separate `foundry-agent-content-safety-policy.xml` operation policy applies
`llm-content-safety` to inbound and non-streaming outbound content. Streaming
SSE output bypasses outbound scanning. The four harm thresholds and Prompt Shield
setting come from the five `policy-content-safety-*` named values. The ingress policy uses `policy-agent-rate-limit-requests` and
`policy-agent-rate-limit-window-seconds`. The tenant ID is embedded by Bicep.
Neither policy detects or redacts PII.

## Model policies

### Portal subscription-key API

APIM validates the Product subscription key before policy execution. A minimal
inline API policy selects the managed-identity Foundry backend; no separate XML
policy or aggregate token policy is deployed.

The API definition matches the Foundry portal-generated shape:

- `subscriptionRequired: true`
- subscription key header: `api-key`
- subscription key query parameter: `subscription-key`
- wildcard operations for the Foundry project model paths
- managed-identity backend authentication to `https://ai.azure.com/`
- an active Product-scoped subscription whose name matches the Product

For key retrieval and request examples, see
[Foundry-managed model API](FOUNDRY-MANAGED-MODEL-API.md).

Callers send an APIM Product subscription key, not a Foundry model key:

```http
POST https://<apim>.azure-api.net/<account>/api/projects/<project>/openai/v1/responses
api-key: <APIM subscription primary-or-secondary key>
Content-Type: application/json
```

### Admin model policies

The integrated template uses `foundry-hosted-admin-model-policy.xml`. It
validates a Microsoft Entra token for the
`https://cognitiveservices.azure.com` audience and requires the `oid` claim to
match the project identity used by the Admin connection. The policy then selects
the APIM backend that authenticates to the Foundry account with the APIM
system-assigned managed identity and the same Cognitive Services audience.

The `createResponses` operation overrides that API-level policy with
`foundry-hosted-direct-responses-policy.xml`. It validates the hosted identity
for the `https://ai.azure.com` audience, includes
`foundry-model-user-level-policy.xml` to validate `x-client-end-user-key`, and
selects the project-compatible Foundry backend.

The API exposes the exact routes used by the connection:

- `POST /models/chat/completions`
- `GET /models/{deploymentName}`
- `POST /api/projects/{projectName}/openai/v1/responses`

The connection target ends in `/ai-gateway/models`, uses
`ProjectManagedIdentity`, and is shared at account scope so it appears in
**Admin > Connected models**. The hosted agent uses `FoundryChatClient` and the
direct project-compatible APIM endpoint, so `x-client-end-user-key` reaches the
operation policy without traversing the Admin connection.

The hosted-agent counter key is:

```text
project/<project>/end-user/<trusted-key>/deployment/<deployment>/user-token-limit/<tpm>/quota/<quota>/period/<period>
```

## MCP tool policies

### `foundry-tool-learn-mcp-policy.xml`

The Microsoft Learn MCP policy configures CORS, rate-limits by APIM subscription
ID when present, and otherwise uses the caller IP. It includes the shared
`foundry-tool-content-safety` fragment for inbound and outbound traffic. It uses
`policy-tool-rate-limit-requests` and `policy-tool-rate-limit-window-seconds`.

### `foundry-tool-github-mcp-policy.xml`

The GitHub MCP request flow is:

1. Require an `Authorization: Bearer ...` header; otherwise return `401`.
2. Validate the token with `GET https://api.github.com/user`; otherwise return
   `401`.
3. Compare the returned GitHub `login` with the case-insensitive,
   comma-separated `policy-github-blocked-users` denylist; a match returns `403`.
4. For an MCP `tools/call` request, read `params.name` and compare it with the
   case-insensitive, comma-separated `policy-github-blocked-tools` denylist; an
   exact match returns `403` before the request reaches GitHub MCP.
5. For `tools/list`, add an empty `params` object only when the MCP client omits
   it. JSON-RPC permits omitted parameters, but this keeps the request compatible
   with GitHub MCP instances that require `params`.
6. Rate-limit using the returned immutable GitHub user ID.
7. Apply the shared inbound Content Safety fragment and forward the request.
8. Add `X-GitHub-MCP-Governed: github-user-oauth` and apply outbound Content
   Safety to the response.

#### GitHub tool controls

The azd value below flows through Bicep into an APIM named value:

| azd environment value | Bicep parameter | APIM named value | Effective default | Effect |
| --- | --- | --- | --- | --- |
| `GITHUB_BLOCKED_TOOL_NAMES` | `githubBlockedToolNames` | `policy-github-blocked-tools` | empty in azd (`__none__` in APIM) | Denies exact, case-insensitive MCP `tools/call` names with HTTP `403`. Example: `get_me,delete_file`. |

`infra/apim.parameters.json` supplies an empty string when
`GITHUB_BLOCKED_TOOL_NAMES` is missing. Bicep converts it to the sentinel
`__none__`, which cannot match a normal tool name. An
`azd provision --no-prompt` run recreates these values from the azd environment,
so manual APIM portal changes are not durable configuration.

The exact-tool denylist is enforced by APIM before forwarding the call. Run
`azd provision --no-prompt` after changing the azd value. Provisioning is also
required after a manual portal edit because Bicep remains the source of truth.

#### Configuration examples

Block selected individual tools. During validation,
blocking `get_me` caused its `tools/call` request to return `403`; restoring an
empty denylist allowed the same request with `200`:

```powershell
azd env set GITHUB_BLOCKED_TOOL_NAMES 'get_me,delete_file'
azd provision --no-prompt
```

Tool names must match the `name` values returned by MCP `tools/list`; display
labels are not used.

The GitHub connection requests the `offline_access`, `repo`, and `read:user`
OAuth scopes. Actual access is limited by those scopes and the permissions of
the authenticated GitHub user. The `repo` scope includes read and write access
to public and private repositories.

### `foundry-tool-content-safety-policy.xml`

This reusable fragment is included by both MCP APIs. It applies the four harm
category thresholds and Prompt Shield configured by the five
`policy-content-safety-*` named values. Prompt Shield may reject benign agent
instructions. The fragment does not detect or redact PII.

## Deployment behavior

Azure Resource Manager deployments are incremental. Removing optional GitHub
credentials later does not delete GitHub resources or toolbox versions that
were already created. A clean environment without both GitHub OAuth values
skips creation of the GitHub connection and its APIM resources.
