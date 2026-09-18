# Configure the optional Google MCP gateway

Google MCP is disabled by default. This sample assumes a separately deployed
Streamable HTTP MCP server on Google Cloud Run that accepts Google OAuth access
tokens at an HTTPS endpoint ending in `/mcp`.

Start with the [Google Cloud preparation guide](google-cloud/README.md) to
deploy the server and configure Google Auth Platform. Return here with the MCP
endpoint, OAuth client ID, and OAuth client secret.

## 1. Prepare the Google OAuth application

In Google Auth Platform:

1. Configure an Internal application, or an External application with the
   intended users added as test users.
2. Create a **Web application** OAuth client.
3. Add a temporary HTTPS redirect URI. Foundry generates the final URI only
   after the Azure connection exists.
4. Register these scopes:

   - `openid`
   - `https://www.googleapis.com/auth/userinfo.email`
   - `https://www.googleapis.com/auth/userinfo.profile`

Keep the client ID and secret outside source control. External applications in
Testing status can require re-consent when Google expires their refresh tokens.
The connection uses Google's standard authorization endpoint. Verify whether
your Foundry version requests offline access before relying on long-lived
refresh tokens in production.

## 2. Prepare the Cloud Run MCP server

Deploy the OAuth-protected MCP server and record its full `/mcp` URL. Configure
the server's `ALLOWED_CLIENT_IDS` environment variable with the same Web OAuth
client ID that will be supplied to Foundry. This audience pin is required even
though APIM also validates the access token with Google user info.

The MCP server defines its own tool inventory. Do not assume specific tool
names; discover the available tools at runtime after authentication. The server
must remain reachable from APIM; Cloud Run can allow unauthenticated network
access because the application itself rejects requests without a valid Google
bearer token.

## 3. Enable Google MCP in the azd environment

Run from `apim-hosted-agent`:

```powershell
azd env set GOOGLE_MCP_ENABLED 'true'
azd env set GOOGLE_MCP_ENDPOINT 'https://<cloud-run-service-host>/mcp'
azd env set GOOGLE_OAUTH_CLIENT_ID '<google-web-oauth-client-id>'
azd env set GOOGLE_OAUTH_CLIENT_SECRET '<google-web-oauth-client-secret>'
```

Optional APIM denylists accept comma-separated, case-insensitive exact values:

```powershell
azd env set GOOGLE_BLOCKED_EMAILS 'blocked-user@example.com'
azd env set GOOGLE_BLOCKED_TOOL_NAMES '<tool-name-1>,<tool-name-2>'
```

Set all values before adding Google to the toolbox. With incomplete values, the
IaC templates do not create the Google connection and a toolbox entry that
references `google` cannot deploy.

The committed manifests intentionally contain no Google toolbox entry. To
enable the tool, manually add the Google toolbox entry to
`services.tools.tools` in whichever `azure.yaml` is selected:

```yaml
- connection: google
  name: google
  require_approval: always
  server_label: google
  type: mcp
```

## 4. Provision and register the callback

Choose one infrastructure path:

- **Bicep:** keep the committed `azure.yaml` active.
- **Terraform:** temporarily rename `azure.yaml` to `azure-bicep.yaml`, then
  rename `azure-terraform.yaml` to `azure.yaml`. Restore both filenames after
  deployment. Use a separate azd environment so Terraform state does not
  overlap a Bicep validation environment.

Provision with the selected manifest, then retrieve the generated callback:

```powershell
azd provision --no-prompt
azd env get-value GOOGLE_OAUTH_REDIRECT_URL
```

Replace the temporary redirect URI in the Google Web OAuth client with the
exact exported value. Keep `ALLOWED_CLIENT_IDS` on Cloud Run equal to
`GOOGLE_OAUTH_CLIENT_ID`.

![Foundry redirect URL registered as an authorized Google OAuth redirect URI](images/google-mcp-foundry-redirect.png)

After saving the callback, deploy the toolbox and hosted agent:

```powershell
azd deploy --no-prompt
azd ai agent show --output json
```

The provision and deploy steps create the following only while Google MCP is
enabled:

- APIM backend `google-mcp`;
- APIM MCP API `tool-<foundry-project>-google-mcp` and its policy;
- two Google governance named values;
- Foundry custom OAuth connection `google`;
- a published toolbox version containing the manually configured `google`
  entry.

## 5. Test consent and tools

Call the hosted agent through the APIM agent endpoint and ask it to discover
and use a safe Google tool. Keep each request stateless:

```powershell
$token = (az account get-access-token `
  --resource https://ai.azure.com/ `
  --query accessToken `
  --output tsv).Trim()

$apimName = (azd env get-value APIM_NAME).Trim()
$agentGateway = "https://$apimName.azure-api.net/agent/responses"
$inputText = @'
Use the Google MCP connection. Discover its currently advertised tools dynamically,
then choose a non-destructive tool whose result contains no personal data.
Do not assume any tool name.
'@

$initialBody = @{
  input = $inputText
  store = $false
} | ConvertTo-Json -Compress

$initialJson = $initialBody | curl.exe `
  --silent `
  --show-error `
  --fail-with-body `
  --request POST $agentGateway `
  --header "Authorization: Bearer $token" `
  --header 'Content-Type: application/json' `
  --data-binary '@-'

if ($LASTEXITCODE -ne 0) {
  throw "Initial hosted-agent request failed with curl exit code $LASTEXITCODE."
}

$initialResponse = ($initialJson -join "`n") | ConvertFrom-Json
$consentRequests = @(
  $initialResponse.output |
    Where-Object { $_.type -eq 'oauth_consent_request' }
)

if ($consentRequests.Count -gt 0) {
  if ($consentRequests.Count -ne 1 -or
      [string]::IsNullOrWhiteSpace([string]$consentRequests[0].consent_link)) {
    throw 'The response did not contain exactly one usable OAuth consent link.'
  }

  # Print only the newest link from this response.
  [string]$consentRequests[0].consent_link
} else {
  $initialResponse.status
  @($initialResponse.output | ForEach-Object { $_.type })
}
```

Open `$consentUrl`, sign in as an allowed/test user, grant consent, and wait for
**Authentication successful**. Then rerun the preceding request as a new
independent request. If consent is requested again, use only the new
`consent_link` returned by that response. Consent URLs are short-lived and
single-use; never reuse an older URL. Stateless requests do not use
`previous_response_id`.

Foundry can request consent separately for the developer identity calling the
toolbox and for the hosted-agent caller context. A direct toolbox test can pass
while the hosted agent still returns `oauth_consent_request`. Open the fresh
link returned by each caller, check **I have verified this request and trust the
source**, and choose **Allow access**. A successful flow ends on a Microsoft
Foundry page headed **Authentication successful**.

After consent, discover the server's current inventory with MCP `tools/list`.
Select an advertised, non-destructive tool whose inputs and output can be
validated without exposing personal data. Do not invoke tools by an assumed
name, and do not log identity-bearing tool output.

Because the toolbox entry requires approval, a request after OAuth can return
an `mcp_approval_request`. Complete that approval through the client experience
before expecting tool output.

If consent reports `redirect_uri_mismatch`, compare the Google Web client URI
with `GOOGLE_OAUTH_REDIRECT_URL`. If the MCP request returns `401`, confirm the
Cloud Run audience allowlist contains the configured client ID and that the
requested scopes are registered.

## 6. Disable the integration

To stop exposing Google to the agent while retaining the provisioned Azure
resources, remove the Google toolbox block from the selected `azure.yaml` and
deploy only the toolbox:

```powershell
azd deploy tools --no-prompt
```

There is no custom cleanup script. The sample does not delete previously
deployed Google resources through imperative cleanup. Keep
`GOOGLE_MCP_ENABLED=true` and retain the OAuth
values when the Azure resources must remain. Setting the flag to false and
provisioning again invokes the selected provider's native lifecycle: Bicep can
retain earlier resources, while Terraform can destroy resources removed from
its configuration. The external Cloud Run service and Google
OAuth application are not managed by this Azure sample.
