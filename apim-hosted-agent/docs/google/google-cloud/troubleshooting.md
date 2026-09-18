# Google MCP troubleshooting and cleanup

[Guide home](README.md) | [Configure OAuth](configure-oauth.md) | [Create server](create-cloud-run-mcp.md) | **Troubleshooting**

## OAuth and consent errors

| Symptom | Likely cause | Resolution |
| --- | --- | --- |
| `redirect_uri_mismatch` | Google callback differs from the Foundry output | Compare scheme, host, path, case, and trailing slash with `GOOGLE_OAUTH_REDIRECT_URL` |
| Consent URL returns 404 | URL expired, was already used, or belongs to an older request | Send a new stateless request and use only its newest consent URL |
| `Code ... not found` | The one-time authorization code was consumed or expired | Discard the old URL and generate a new consent request |
| Browser reports success but the agent asks again | Authorization belongs to another connection/caller, or state has not propagated | Confirm the target environment and distinguish hosted-agent from direct Toolbox consent |
| Direct `tools/list` asks for consent after hosted-agent success | Direct Toolbox calls use a separate developer identity | Complete the developer-identity consent separately |
| Hosted agent asks for consent after direct Toolbox success | Hosted caller context is not authorized | Complete consent through the hosted-agent response |
| `Access blocked` | External application is in Testing and the account is not allowed | Add it under **Audience > Test users**, or publish after meeting requirements |
| `invalid_scope` | Scope is misspelled, unavailable, or API is disabled | Enable the required API and copy the exact scope from **Data access** |
| OAuth returns no refresh token | Offline access was not requested or consent was already granted | Request offline access when supported; revoke the prior grant before retesting when appropriate |
| `mcp_approval_request` | OAuth succeeded, but the tool requires approval | Continue with a client that supports the Foundry Responses MCP approval flow |

Consent URLs are short-lived and single-use. With `store=false`, every retry is
a new response. Never reuse a URL from an earlier response and never attach an
old `previous_response_id`.

## Cloud Run and token errors

| Symptom | Likely cause | Resolution |
| --- | --- | --- |
| Cloud Run returns infrastructure `403` | Cloud Run IAM rejects public invocation | Allow unauthenticated infrastructure access when application OAuth is enforced |
| MCP returns `401` with no token | Expected application behavior | Complete OAuth and retry with the platform-injected token |
| MCP returns `401` after OAuth | Token expired, bearer header missing, or audience mismatch | Confirm `ALLOWED_CLIENT_IDS` and that Foundry uses the same OAuth client |
| MCP returns `200` without a token | Application endpoint is not enforcing OAuth | Fix server authentication before exposing tools |
| Client secret is unavailable | Secret was not stored | Create a replacement, test it, then disable and delete the old secret |

## Azure deployment errors

| Symptom | Likely cause | Resolution |
| --- | --- | --- |
| Google Toolbox entry fails to deploy | Google endpoint or OAuth values are incomplete | Set all required azd values before adding the Toolbox entry |
| Provision succeeds but resource-link check fails once | ARM resource links have not propagated | Wait, then rerun `scripts/sync-gateway-links.ps1` |
| Agent is active but Google is absent | Google entry was not added to the active manifest | Verify the selected Bicep/Terraform manifest and redeploy |
| Terraform commands affect the wrong state | Manifest filenames or azd environment are wrong | Restore filenames, select the intended environment, then reactivate Terraform |

## Security checklist

- Store client secrets and refresh tokens in an approved secret store.
- Protect the local `.azure/` directory.
- Never include tokens or secrets in screenshots, Markdown, logs, or tickets.
- Pin tokens to `<GOOGLE_OAUTH_CLIENT_ID>`.
- Request only scopes required by deployed tools.
- Use separate OAuth clients for development and production.
- Remove temporary redirect URIs after validation.
- Remove unused test users.
- Cap Cloud Run instances and configure budgets or alerts.
- Rotate any secret that might have been exposed.

## Cleanup boundaries

Azure, local azd state, Cloud Run, and Google OAuth are separate lifecycle
boundaries:

| Goal | Action | Does not affect |
| --- | --- | --- |
| Hide Google from the hosted agent | Remove the Google Toolbox entry and run `azd deploy tools --no-prompt` | Azure infrastructure, Cloud Run, OAuth client |
| Delete the Azure environment | Run `azd down --force --purge --no-prompt` | Cloud Run and Google OAuth client |
| Remove local azd credentials | After Azure cleanup, run `azd env remove <AZD_ENVIRONMENT_NAME> --force` | Azure and Google Cloud resources |
| Delete Cloud Run | Run the `gcloud run services delete` command below | Azure resources and OAuth client |
| Retire OAuth | Remove callbacks/test users and disable or delete the client/secret | Azure and Cloud Run unless separately removed |

Delete the Cloud Run service only when it is no longer shared:

```bash
gcloud run services delete <SERVICE_NAME> \
  --project <GOOGLE_CLOUD_PROJECT_ID> \
  --region <REGION>
```

Also remove unused images, secrets, test users, redirect URIs, and project
permissions.

## Official references

- [Host MCP servers on Cloud Run](https://docs.cloud.google.com/run/docs/host-mcp-servers)
- [OAuth 2.0 for Web Server Applications](https://developers.google.com/identity/protocols/oauth2/web-server)
- [Google Auth Platform](https://console.cloud.google.com/auth/overview)

Back to the [Google Cloud guide](README.md) or
[Azure integration guide](../README.md).
