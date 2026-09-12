# Create and deploy the Cloud Run MCP server

[Guide home](README.md) | **Create server** | [Configure OAuth](configure-oauth.md) | [Troubleshooting](troubleshooting.md)

Use Google's maintained documentation:

- [Host MCP servers on Cloud Run](https://docs.cloud.google.com/run/docs/host-mcp-servers)
- [Build and deploy a Python service](https://docs.cloud.google.com/run/docs/quickstarts/build-and-deploy/deploy-python-service)

## Server requirements

- Expose MCP Streamable HTTP over HTTPS, normally at `POST /mcp`.
- Read an access token from `Authorization: Bearer <token>`.
- Validate the Google token before executing tools.
- Verify the token audience equals `<GOOGLE_OAUTH_CLIENT_ID>`.
- Return `401 Unauthorized` for missing, invalid, expired, or wrong-audience tokens.
- Expose only the tools required by the application.

An OAuth protected-resource metadata endpoint is recommended:

```text
GET /.well-known/oauth-protected-resource
```

## Cloud Run access model

Allow unauthenticated invocation at the Cloud Run infrastructure layer when
the application validates Google OAuth tokens. This permits requests to reach
the application; it does not make tools anonymous. Cloud Run IAM authentication
can reject the request before the application sees the OAuth token.

## Deploy and record the endpoint

Deploy with a bounded maximum instance count. Read the assigned URL back:

```bash
gcloud run services describe <SERVICE_NAME> \
  --project <GOOGLE_CLOUD_PROJECT_ID> \
  --region <REGION> \
  --format='value(status.url)'
```

The complete endpoint is normally `<MCP_SERVER_BASE_URL>/mcp`.

## Pin the OAuth client audience

After creating the OAuth client, update Cloud Run so it accepts only tokens
issued for that client. The reference server uses:

```text
ALLOWED_CLIENT_IDS=<GOOGLE_OAUTH_CLIENT_ID>
```

Do not leave the allowlist empty in production.

## Checkpoint

- `GET <MCP_SERVER_BASE_URL>/` returns the health response.
- Unauthenticated `POST <MCP_ENDPOINT>` returns `401`, not `200`.
- A valid token issued for another client returns `401`.
- `<MCP_ENDPOINT>` is recorded for the integration guide.

Next: [Configure Google OAuth](configure-oauth.md).
