# Configure the optional Google MCP gateway

Google MCP is disabled by default. This guide enables a separately deployed
Streamable HTTP MCP server on Google Cloud Run, protects it with Google OAuth,
routes it through API Management (APIM), and exposes it to the Foundry hosted
agent through a Toolbox connection.

Use this page as the end-to-end procedure. The
[Google Cloud preparation guide](google-cloud/README.md) contains the detailed
Google console and Cloud Run steps.

## Workflow at a glance

| Stage | Action | Checkpoint |
| --- | --- | --- |
| 1 | Create a Google OAuth Web client with a temporary redirect URI | Client ID and secret are stored securely |
| 2 | Deploy the OAuth-protected Cloud Run MCP server | Full HTTPS `/mcp` endpoint returns 401 without a token |
| 3 | Configure the azd environment and Google Toolbox entry | All required Google values are present |
| 4 | Run `azd provision` | Azure resources exist and the final callback is exported |
| 5 | Add the final callback to Google | Exact `GOOGLE_OAUTH_REDIRECT_URL` is saved |
| 6 | Run `azd deploy` | Hosted agent reports `active` |
| 7 | Test hosted-agent OAuth and tools | Latest consent URL is authorized; a safe advertised tool can run |
| 8 | Optionally test the Toolbox directly | Developer identity is authorized separately |

## Values worksheet

Record these values as you complete the workflow. Never put secrets in source
control, documentation, screenshots, logs, or tickets.

| Value | Source | Available after |
| --- | --- | --- |
| `<GOOGLE_CLOUD_PROJECT_ID>` | Your Google Cloud project | Before starting |
| `<GOOGLE_OAUTH_CLIENT_ID>` | Google OAuth Web client | Step 1 |
| `<GOOGLE_OAUTH_CLIENT_SECRET>` | Google OAuth Web client | Step 1 |
| `<MCP_ENDPOINT>` | Cloud Run service URL plus `/mcp` | Step 2 |
| `<AZD_ENVIRONMENT_NAME>` | Your azd environment | Step 3 |
| `GOOGLE_OAUTH_REDIRECT_URL` | `azd env get-value` | Step 4 |
| `APIM_NAME` | azd environment | Step 4 |
| Agent gateway | `https://<APIM_NAME>.azure-api.net/agent/responses` | Step 6 |

## 1. Check prerequisites

Complete the main template [prerequisites](../../README.md#1-prerequisites).
You also need:

- a Google Cloud project with billing enabled;
- permission to configure Google Auth Platform and deploy Cloud Run;
- MCP server source code, or an existing compatible Cloud Run MCP server;
- an allowed Google account when the OAuth application is External and in
  Testing status.

The MCP server defines its own tool inventory. This template does not assume
any tool name. Tool names and input schemas must be discovered at runtime.

## 2. Prepare Google OAuth and Cloud Run

Follow the [Google Cloud preparation guide](google-cloud/README.md). The setup
is intentionally two-stage:

1. Create the OAuth Web client with a temporary redirect URI.
2. Deploy Cloud Run with
   `ALLOWED_CLIENT_IDS=<GOOGLE_OAUTH_CLIENT_ID>`.
3. Return here with the client ID, client secret, and full `/mcp` endpoint.
4. Add the Foundry-generated final redirect URI after Azure provisioning.

Before continuing, verify that an unauthenticated MCP request reaches the
application and returns `401`, not a Cloud Run infrastructure `403`.

## 3. Select the infrastructure manifest

Run every command from `apim-hosted-agent`.

- **Bicep:** keep the committed `azure.yaml` active.
- **Terraform:** activate `azure-terraform.yaml` before running azd:

  ```powershell
  Rename-Item azure.yaml azure-bicep.yaml
  Rename-Item azure-terraform.yaml azure.yaml
  ```

  Run all Terraform azd commands while the Terraform manifest is named
  `azure.yaml`. Restore the filenames when the operation is finished:

  ```powershell
  Rename-Item azure.yaml azure-terraform.yaml
  Rename-Item azure-bicep.yaml azure.yaml
  ```

Use separate azd environments for Bicep and Terraform so their state never
overlaps.

## 4. Configure the azd environment

Create or select an environment as described by the main README. Set the
Google endpoint and enable flag:

```powershell
azd env set GOOGLE_MCP_ENABLED 'true'
azd env set GOOGLE_MCP_ENDPOINT 'https://<cloud-run-service-host>/mcp'
```

Enter the OAuth values without placing the secret in shell history:

```powershell
$googleClientId = Read-Host 'Google OAuth client ID'
$secureSecret = Read-Host 'Google OAuth client secret' -AsSecureString
$plainSecret = [System.Net.NetworkCredential]::new('', $secureSecret).Password

azd env set GOOGLE_OAUTH_CLIENT_ID $googleClientId
azd env set GOOGLE_OAUTH_CLIENT_SECRET $plainSecret

$plainSecret = $null
$secureSecret.Dispose()
```

The secret is stored in the local azd environment under `.azure/`. Protect
that directory and remove the environment when it is no longer needed.

Optional APIM denylists accept comma-separated, case-insensitive exact values:

```powershell
azd env set GOOGLE_BLOCKED_EMAILS 'blocked-user@example.com'
azd env set GOOGLE_BLOCKED_TOOL_NAMES '<tool-name-1>,<tool-name-2>'
```

Only configure tool names returned by the live MCP server's `tools/list`.

Add Google to `services.tools.tools` in the currently active `azure.yaml`:

```yaml
- connection: google
  name: google
  require_approval: always
  server_label: google
  type: mcp
```

The committed manifests intentionally omit this entry. With incomplete Google
values, the IaC templates do not create the Google connection, and a Toolbox
entry that references `google` cannot deploy.

### Configuration checkpoint

- `GOOGLE_MCP_ENABLED` is `true`.
- `GOOGLE_MCP_ENDPOINT` is the complete HTTPS `/mcp` URL.
- Google client ID and secret are present in the selected azd environment.
- The active manifest contains Google and uses the intended IaC provider.
- `ALLOWED_CLIENT_IDS` on Cloud Run contains the same client ID.

## 5. Provision Azure and retrieve the final callback

Provision infrastructure without deploying the Toolbox or agent:

```powershell
azd provision --no-prompt
$googleRedirectUrl = (azd env get-value GOOGLE_OAUTH_REDIRECT_URL).Trim()
$googleRedirectUrl
```

Provisioning creates the following only while Google MCP is enabled:

- APIM backend `google-mcp`;
- APIM MCP API `tool-<foundry-project>-google-mcp` and its policy;
- Google governance named values;
- Foundry custom OAuth connection `google`.

### Provisioning checkpoint

- `GOOGLE_OAUTH_REDIRECT_URL` is a non-empty HTTPS URL.
- The Google Foundry connection exists.
- The Google APIM API and backend exist.
- GitHub resources are present or absent according to the selected scenario.

## 6. Register the final callback and deploy

In **Google Auth Platform > Clients**, open the Web client created in step 2.
Add `$googleRedirectUrl` under **Authorized redirect URIs** exactly as emitted.
Keep the temporary URI until end-to-end validation succeeds, then remove it.

Google requires an exact match, including scheme, host, path, case, and trailing
slash.

![Foundry redirect URL registered as an authorized Google OAuth redirect URI](images/google-mcp-foundry-redirect.png)

After saving the callback, deploy:

```powershell
azd deploy --no-prompt
azd ai agent show --output json
```

The deployed agent is ready when its version reports `active` or `deployed`.
Its governed endpoint is:

```text
https://<APIM_NAME>.azure-api.net/agent/responses
```

## 7. Test hosted-agent consent and tool use

Hosted-agent requests in this guide are stateless. Every request uses
`store=false`. Every retry creates a new response and, when consent is needed,
a new short-lived, single-use consent URL. Never reuse an older URL.

```powershell
$apimName = (azd env get-value APIM_NAME).Trim()
$agentGateway = "https://$apimName.azure-api.net/agent/responses"
$inputText = @'
Use the Google MCP connection. Discover its currently advertised tools dynamically,
then choose a non-destructive tool whose result contains no personal data.
Do not assume any tool name.
'@

function Invoke-GoogleAgentRequest {
  $token = (az account get-access-token `
    --resource https://ai.azure.com/ `
    --query accessToken `
    --output tsv).Trim()

  $body = @{
    input = $inputText
    store = $false
  } | ConvertTo-Json -Compress

  $json = $body | curl.exe `
    --silent `
    --show-error `
    --fail-with-body `
    --request POST $agentGateway `
    --header "Authorization: Bearer $token" `
    --header 'Content-Type: application/json' `
    --data-binary '@-'

  if ($LASTEXITCODE -ne 0) {
    throw "Hosted-agent request failed with curl exit code $LASTEXITCODE."
  }

  ($json -join "`n") | ConvertFrom-Json
}

$response = Invoke-GoogleAgentRequest
$consentRequests = @(
  $response.output |
    Where-Object { $_.type -eq 'oauth_consent_request' }
)
$consentUrl = $null

if ($consentRequests.Count -gt 0) {
  if ($consentRequests.Count -ne 1 -or
      [string]::IsNullOrWhiteSpace([string]$consentRequests[0].consent_link)) {
    throw 'The response did not contain exactly one usable OAuth consent link.'
  }

  $consentUrl = [string]$consentRequests[0].consent_link
  $consentUrl
} else {
  $response.status
  @($response.output | ForEach-Object { $_.type })
}
```

When `$consentUrl` is returned:

1. Open it immediately.
2. Sign in as an allowed/test user.
3. Check **I have verified this request and trust the source**.
4. Choose **Allow access**.
5. Wait for **Authentication successful**.
6. Run the request block again as a new independent request.

If consent is requested again, use only the new `consent_link` from that
response. Stateless requests do not use `previous_response_id`.

Because the Toolbox entry uses `require_approval: always`, a request after
OAuth can return `mcp_approval_request`. OAuth and tool approval are separate
steps. Complete approval with a client that supports the Foundry Responses MCP
approval flow before expecting final tool output.

### Hosted-agent success criteria

- APIM returns HTTP 200.
- The agent no longer returns `oauth_consent_request` for the authorized caller.
- A tool is selected from the runtime-advertised inventory.
- The chosen tool is non-destructive and produces no personal output.
- The response contains the expected tool result or a clearly identified
  approval request.

## 8. Optionally test the Toolbox directly

Direct Toolbox calls use the developer identity. Hosted-agent calls use the
hosted caller context. Foundry can require separate OAuth consent for each
identity:

- Hosted-agent consent does not authorize a direct Toolbox client.
- Direct Toolbox consent does not authorize the hosted-agent caller.

Use an MCP-capable client to call `tools/list` only after completing the
developer-identity consent flow. Select a tool from the returned inventory and
schema; never assume a name or arguments. Do not invoke or log identity-bearing
tool output.

## 9. Troubleshoot

See [Google Cloud troubleshooting](google-cloud/troubleshooting.md) for callback,
scope, audience, consent-state, approval, and Cloud Run errors.

Quick checks:

- `redirect_uri_mismatch`: compare Google configuration with
  `GOOGLE_OAUTH_REDIRECT_URL` exactly.
- `401` from MCP: verify the bearer token, expiry, and
  `ALLOWED_CLIENT_IDS`.
- `403` before the MCP application responds: verify Cloud Run permits
  unauthenticated infrastructure invocation.
- `404` or `Code ... not found`: discard the old single-use URL and generate a
  new stateless request.
- repeated consent: confirm whether the caller is the hosted agent or a direct
  Toolbox developer identity.

## 10. Disable or clean up

Choose the action that matches your goal:

| Goal | Action |
| --- | --- |
| Hide Google from the agent but retain Azure resources | Remove the Google Toolbox entry and run `azd deploy tools --no-prompt` |
| Delete the Azure environment | Run `azd down --force --purge --no-prompt` |
| Remove local azd credentials after Azure cleanup | Run `azd env remove <AZD_ENVIRONMENT_NAME> --force` |
| Delete Cloud Run | Follow the Google Cloud cleanup guide |
| Retire Google OAuth | Remove callbacks/test users, then disable or delete the client and secret |

Setting `GOOGLE_MCP_ENABLED=false` and provisioning again invokes the selected
provider's native lifecycle: Bicep can retain earlier resources, while
Terraform can destroy resources removed from its configuration.

`azd down` and `azd env remove` do not delete the external Cloud Run service or
Google OAuth application.
