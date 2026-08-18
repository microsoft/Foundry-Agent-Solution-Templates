# APIM Policy Reference

This document describes every APIM policy XML file in `infra/policies`, where
it is deployed, and how requests flow through it.

## Policy inventory

| Policy XML | APIM scope | Purpose |
| --- | --- | --- |
| `foundry-agent-ingress-policy.xml` | Hosted-agent API | Authenticate callers, derive the trusted user key, and apply IP rate limiting |
| `foundry-agent-content-safety-policy.xml` | Hosted-agent `/responses` operation | Apply inbound and outbound Content Safety |
| `foundry-project-model-key-auth-policy.xml` | Subscription-key model API | Select the model backend and enforce Product-configured aggregate project limits |
| `foundry-model-oauth-policy.xml` | OAuth model API | Authenticate the hosted agent and select the model backend |
| `foudnry-model-content-safety-policy.xml` | OAuth model POST operation | Apply per-user token limits and model Content Safety |
| `foundry-model-user-level-policy.xml` | Policy fragment | Validate the propagated end-user key and apply per-user token limits |
| `foundry-project-token-policy.xml` | Portal Product | Publish model token-limit metadata for Foundry Portal |
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

`foundry-agent-principal-id` is deployment wiring rather than administrator
policy configuration. Aggregate project token settings are rendered into the
Product and subscription-key API policies and are not named values.

`azd provision --no-prompt` reapplies Bicep-owned values and can overwrite
manual named-value edits. Change the corresponding Bicep value before
provisioning when a setting must persist.

## Agent policies

### `foundry-agent-ingress-policy.xml`

The policy is attached to the hosted-agent API. It rate-limits requests by
source IP, validates a Microsoft Entra bearer token for the
`https://ai.azure.com` audience, requires the token's `tid` and `oid` claims, and
derives `platform/<sha256(tid:oid)>`. It overwrites `x-client-end-user-key` with
that value before forwarding the request to Foundry, so callers cannot choose a
different model quota bucket through the APIM route.

The separate `foundry-agent-content-safety-policy.xml` operation policy applies
`llm-content-safety` to inbound and non-streaming outbound content. Streaming
SSE output bypasses outbound scanning. The four harm thresholds and Prompt Shield
setting come from the five `policy-content-safety-*` named values. The ingress policy uses `policy-agent-rate-limit-requests` and
`policy-agent-rate-limit-window-seconds`. The tenant ID is embedded by Bicep.
Neither policy detects or redacts PII.

## Model policies

### `foundry-project-model-key-auth-policy.xml`

This policy is attached to the subscription-key model API. APIM validates the subscription
key before policy execution. The policy selects the managed-identity Foundry
backend and reads the configured deployment limit and quota from the associated
Product Policy.

The aggregate counter key is:

```text
product/<product-id>/deployment/<deployment-name>/limit/<limit>/quota/<quota>/period/<period>
```

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

### `foundry-model-oauth-policy.xml`

This policy is attached to the separate OAuth model API used by the hosted
agent. It validates the agent's Microsoft Entra identity and selects the same
managed-identity backend. It does not apply aggregate project limits or Content
Safety.

The OAuth POST operation separately includes the
`foundry-model-user-level` fragment and scans model content through
`foudnry-model-content-safety-policy.xml`. It does not force a Foundry RAI
policy.

### `foundry-model-user-level-policy.xml`

#### End-user identity flow

APIM derives the end-user key from the authenticated Entra token. It combines
the tenant ID and user object ID as `tid:oid`, hashes that value with SHA-256,
and forwards only `platform/<sha256>` in `x-client-end-user-key`. The raw claims
are not sent to the hosted agent or model gateway through this header. Tokens
without both claims are rejected with HTTP 403, so application-only tokens do
not share a user quota bucket.

Foundry forwards `x-client-*` headers to the hosted container. The hosting SDK
places them in `context.client_headers`; the agent validates the key format,
scopes it to the response stream, and overwrites the model request's
`x-client-end-user-key`. When a request arrives directly through Foundry without
the APIM header, the agent uses `default_user`. An invalid supplied header still
fails closed.

The policy fragment validates that internal key and applies a separate token
counter per end user and deployment:

```text
project/<project-name>/end-user/platform/<sha256>/deployment/<deployment-name>/user-token-limit/<tpm>/quota/<quota>/period/<period>
```

Repeated calls by the same tenant/user pair use the same counter. A different
tenant or user uses a separate counter. Changing a user-limit value starts a new counter bucket
so an increased limit takes effect immediately. The Foundry playground and
direct Foundry endpoint bypass this APIM ingress derivation and therefore cannot
be used to validate the sample's APIM-based per-user model limit; those calls
share the `default_user` counter.

`x-client-end-user-key` is an internal transport. APIM always overwrites a
caller-supplied value. The hosted agent accepts an APIM-provided
`platform/<64 lowercase hex>` value, uses `default_user` only when the header is
absent, and never treats the request body as an identity source.

It uses `policy-user-token-limit-per-minute`, `policy-user-token-quota`, and
`policy-user-token-quota-period`. Prompt tokens are estimated before forwarding
the request so an over-limit request is rejected immediately.

### `foundry-project-token-policy.xml`

This Product Policy publishes `tokenlimit-<deployment>` and
`tokenquota-<deployment>` metadata for the Foundry portal. Bicep renders and
deploys the same project-limit values enforced by the subscription-key model
API. These values are not APIM named values.

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
