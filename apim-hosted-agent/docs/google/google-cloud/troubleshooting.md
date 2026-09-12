# Google Cloud troubleshooting and cleanup

[Guide home](README.md) | [Create server](create-cloud-run-mcp.md) | [Configure OAuth](configure-oauth.md) | **Troubleshooting**

## Common errors

| Symptom | Likely cause | Resolution |
| --- | --- | --- |
| `redirect_uri_mismatch` | Callback differs from the client entry | Compare scheme, host, path, case, and trailing slash |
| `Access blocked` | External app is in Testing and the account is not allowed | Add it under **Audience > Test users**, or publish after meeting requirements |
| `invalid_scope` | Scope is misspelled or unavailable | Copy the full URI from **Data access** and enable any required API |
| Cloud Run returns `403` before the app responds | Cloud Run IAM rejects public invocation | Allow unauthenticated infrastructure access when OAuth is enforced in the app |
| MCP returns `401` with a Google token | Missing bearer header, expired token, or audience mismatch | Confirm the token was issued for `<GOOGLE_OAUTH_CLIENT_ID>` |
| OAuth returns no refresh token | Offline access was not requested or consent was already granted | Request offline access when supported; revoke the prior grant before retesting when appropriate |
| Client secret is unavailable | Secret was not stored | Create a replacement, test it, then disable and delete the old secret |

## Security checklist

- Store client secrets and refresh tokens in a secret store.
- Never include tokens or secrets in screenshots, Markdown, logs, or tickets.
- Pin tokens to `<GOOGLE_OAUTH_CLIENT_ID>`.
- Request only required scopes.
- Use separate OAuth clients for development and production.
- Remove temporary test users and redirect URIs.
- Cap Cloud Run instances and configure budgets or alerts.
- Rotate any secret that might have been exposed.

## Cleanup

1. Remove unused redirect URIs.
2. Disable and delete obsolete OAuth clients or client secrets.
3. Delete the Cloud Run service when it is no longer needed:

```bash
gcloud run services delete <SERVICE_NAME> \
  --project <GOOGLE_CLOUD_PROJECT_ID> \
  --region <REGION>
```

4. Remove unused images, secrets, test users, and project permissions.

## Official references

- [Host MCP servers on Cloud Run](https://docs.cloud.google.com/run/docs/host-mcp-servers)
- [OAuth 2.0 for Web Server Applications](https://developers.google.com/identity/protocols/oauth2/web-server)
- [Google Auth Platform](https://console.cloud.google.com/auth/overview)

Back to [guide home](README.md).
