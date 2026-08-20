# APIM Policy Reference

This document describes every APIM policy XML file in `infra/policies`, where
it is deployed, and how requests flow through it.

## Policy inventory

| Policy XML | APIM scope | Purpose |
| --- | --- | --- |
| `foundry-agent-ingress-policy.xml` | Hosted-agent API | Authenticate callers and apply IP rate limiting |
| `foundry-agent-content-safety-policy.xml` | Hosted-agent `/responses` operation | Apply inbound and outbound Content Safety |
| `foundry-model-gateway-policy.xml` | Hosted-agent model API | Authenticate the hosted identity, apply per-user limits, and select the project backend |
| `foundry-model-content-safety-policy.xml` | Policy fragment | Apply Content Safety to model Responses requests |
| `foundry-model-user-level-policy.xml` | Policy fragment | Validate the propagated user key and apply per-user token limits |
| `foundry-tool-learn-mcp-policy.xml` | Microsoft Learn MCP API | Apply caller rate limiting and the shared tool Content Safety fragment |
| `foundry-tool-github-mcp-policy.xml` | GitHub MCP API | Validate GitHub OAuth, enforce username and exact-tool denylists, rate-limit by GitHub user ID, and apply tool Content Safety |
| `foundry-tool-content-safety-policy.xml` | Policy fragment | Provide shared inbound/outbound MCP harm filtering |

## Named-value inventory

APIM exposes 13 administrator-facing policy named values:

| Configuration area | Named values |
| --- | --- |
| Agent request rate | `policy-agent-rate-limit-requests`, `policy-agent-rate-limit-window-seconds` |
| Per-user model tokens | `policy-user-tokens-per-minute`, `policy-user-token-quota-per-hour` |
| MCP request rate | `policy-tool-rate-limit-requests`, `policy-tool-rate-limit-window-seconds` |
| GitHub governance | `policy-github-blocked-users`, `policy-github-blocked-tools` |
| Content Safety thresholds and Prompt Shield | `policy-content-safety-hate-threshold`, `policy-content-safety-self-harm-threshold`, `policy-content-safety-sexual-threshold`, `policy-content-safety-violence-threshold`, `policy-content-safety-prompt-shield-enabled` |

Hosted-agent principal and backend values are deployment wiring.

`azd provision --no-prompt` reapplies Bicep-owned values and can overwrite
manual named-value edits. Change the corresponding Bicep value before
provisioning when a setting must persist.

## Agent policies

### `foundry-agent-ingress-policy.xml`

The policy is attached to the hosted-agent API. The hosted agent points
`FoundryChatClient` at the project-compatible APIM endpoint and uses the model
deployment name directly. The policy rate-limits requests by
source IP, validates a Microsoft Entra bearer token for the
`https://ai.azure.com` audience, and forwards the request to Foundry. The hosted runtime reads Foundry's
platform-provided `user_id_key`, hashes it as `platform/<sha256>`, and sends
that derived key on its downstream APIM model request.

The separate `foundry-agent-content-safety-policy.xml` operation policy applies
`llm-content-safety` to inbound and non-streaming outbound content. The four harm thresholds and Prompt Shield
setting come from the five `policy-content-safety-*` named values. The ingress policy uses `policy-agent-rate-limit-requests` and
`policy-agent-rate-limit-window-seconds`. The tenant ID is embedded by Bicep.

The agent rate-limit counter key includes the configured request count and
renewal window. Changing either named value starts a fresh counter namespace.

## Model policies

### Hosted-agent model policy

The direct model API is registered in APIM with the `aimodel` tag and an
Azure-resource-backed Foundry backend, so it appears under **AI Gateway >
Models**. It uses `foundry-model-gateway-policy.xml` at API scope and
validates the hosted identity
for the `https://ai.azure.com` audience, includes
`foundry-model-user-level-policy.xml` to validate `x-client-end-user-key`, and
selects the project-compatible Foundry backend.

Before quota enforcement, `foundry-model-content-safety-policy.xml` stores the
original model request, serializes its `input` property, and applies
`llm-content-safety` to the first 10,000 characters. It then restores the
original request for quota enforcement and backend forwarding.
Prompt Shield uses the shared named value at this model boundary, and all four
harm categories use the shared threshold named values, which default to `7`.
Agent ingress and model policies enable Prompt Shield.

The API operation is:

- `POST /api/projects/{projectName}/openai/v1/responses`

The hosted-agent counter key is:

```text
project/<project>/end-user/<trusted-key>/tpm/<tokens-per-minute>/quota-hour/<hourly-quota>
```

The fragment applies one `llm-token-limit` rule with a fixed hourly period.
Changing either configured token limit creates a new counter key, so the new
limit starts with a fresh counter.

## MCP tool policies

### `foundry-tool-learn-mcp-policy.xml`

The Microsoft Learn MCP policy rate-limits by APIM subscription ID when present,
and otherwise uses the caller IP. It includes the shared
`foundry-tool-content-safety` fragment for inbound and outbound traffic. It uses
`policy-tool-rate-limit-requests` and
`policy-tool-rate-limit-window-seconds`.
The counter key includes both configured values, so changing either one starts
a fresh counter namespace.

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
6. Rate-limit using the returned immutable GitHub user ID plus the configured
   request count and renewal window, so changing either limit starts a fresh
   counter namespace.
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
`__none__`, which represents an empty denylist. An
`azd provision --no-prompt` run recreates these values from the azd environment,
with Bicep and azd as the configuration source of truth.

The exact-tool denylist is enforced by APIM before forwarding the call. Run
`azd provision --no-prompt` after changing the azd value.

#### Configuration examples

Block selected individual tools. During validation,
blocking `get_me` caused its `tools/call` request to return `403`; restoring an
empty denylist allowed the same request with `200`:

```powershell
azd env set GITHUB_BLOCKED_TOOL_NAMES 'get_me,delete_file'
azd provision --no-prompt
```

Configure tool names with the `name` values returned by MCP `tools/list`.

The GitHub connection requests the `offline_access`, `repo`, and `read:user`
OAuth scopes. Actual access is limited by those scopes and the permissions of
the authenticated GitHub user. The `repo` scope includes read and write access
to public and private repositories.

### `foundry-tool-content-safety-policy.xml`

This reusable fragment is included by both MCP APIs. It applies the four harm
category thresholds configured by the `policy-content-safety-*-threshold` named
values.
