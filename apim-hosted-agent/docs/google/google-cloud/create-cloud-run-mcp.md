# Create and deploy the Cloud Run MCP server

[Guide home](README.md) | [Configure OAuth](configure-oauth.md) | **Create server** | [Troubleshooting](troubleshooting.md)

Complete [OAuth stage A](configure-oauth.md#stage-a-create-the-oauth-client)
first so the server can pin token audiences to
`<GOOGLE_OAUTH_CLIENT_ID>`.

Use Google's maintained documentation:

- [Host MCP servers on Cloud Run](https://docs.cloud.google.com/run/docs/host-mcp-servers)
- [Build and deploy a Python service](https://docs.cloud.google.com/run/docs/quickstarts/build-and-deploy/deploy-python-service)

## Server requirements

- Expose MCP Streamable HTTP over HTTPS, normally at `POST /mcp`.
- Read the bearer token from the `Authorization` header.
- Validate the Google token before executing tools.
- Verify that the token audience equals `<GOOGLE_OAUTH_CLIENT_ID>`.
- Return `401 Unauthorized` for missing, invalid, expired, or wrong-audience
  tokens.
- Expose only the tools required by the application.
- Do not rely on the Azure template knowing the server's tool names.

An OAuth protected-resource metadata endpoint is recommended:

```text
GET /.well-known/oauth-protected-resource
```

## Cloud Run access model

Allow unauthenticated invocation at the Cloud Run infrastructure layer when
the application validates Google OAuth tokens. This permits requests to reach
the application; it does not make the tools anonymous.

If Cloud Run IAM authentication is enabled instead, it can reject the request
before the MCP application sees the Google OAuth token.

## Deploy and record the endpoint

Deploy with a bounded maximum instance count. Read the assigned URL back:

```bash
gcloud run services describe <SERVICE_NAME> \
  --project <GOOGLE_CLOUD_PROJECT_ID> \
  --region <REGION> \
  --format='value(status.url)'
```

The complete endpoint is normally:

```text
<MCP_SERVER_BASE_URL>/mcp
```

## Pin the OAuth client audience

Configure the service with:

```text
ALLOWED_CLIENT_IDS=<GOOGLE_OAUTH_CLIENT_ID>
```

Deploy a new revision after changing the audience allowlist. Do not leave the
allowlist empty in production.

## Verify network and application authentication

Verify the health route:

```bash
curl --fail-with-body "https://<SERVICE_HOST>/"
```

Verify an unauthenticated MCP initialization request reaches the application
and returns HTTP 401:

```bash
curl --include \
  --request POST "https://<SERVICE_HOST>/mcp" \
  --header "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"preflight","version":"1.0"}}}'
```

Interpret the result:

- `401`: expected; the application received and rejected the missing token.
- Cloud Run `403`: infrastructure IAM rejected the request before application
  OAuth validation.
- `200`: unsafe unless the application intentionally implements an anonymous
  MCP surface.

Testing a valid token for another OAuth client should also return 401. Treat
that as an advanced server-security test; never print or store the token.

## Checkpoint

- Health route responds.
- Unauthenticated MCP request returns application-level 401.
- Wrong-audience tokens are rejected when tested.
- `ALLOWED_CLIENT_IDS` contains the intended Web client ID.
- Full `<MCP_ENDPOINT>` is recorded.
- Tool names remain server-defined and are not copied into the Azure template.

Return to the [Azure integration guide](../README.md).
