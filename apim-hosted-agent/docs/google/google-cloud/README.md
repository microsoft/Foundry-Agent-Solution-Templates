# Prepare Google Cloud for the MCP gateway

This guide prepares Google OAuth and an OAuth-protected Streamable HTTP MCP
server on Cloud Run. Return to the
[Azure integration guide](../README.md) after completing the checkpoints.

## Why setup happens in two stages

The Google OAuth client ID is needed before Cloud Run can pin token audiences,
but Foundry generates its final OAuth redirect URI only after Azure
provisioning.

Use this order:

1. Create the Google OAuth application and Web client with a temporary redirect
   URI.
2. Store the client ID and secret securely.
3. Deploy Cloud Run with `ALLOWED_CLIENT_IDS` set to that client ID.
4. Configure and provision the Azure integration.
5. Add the Foundry-generated final redirect URI to the same Google client.
6. Remove the temporary redirect URI after end-to-end validation succeeds.

## What you will produce

- a Google OAuth Web client ID and secret;
- a public HTTPS MCP endpoint such as
  `https://<SERVICE_HOST>/mcp`;
- a Cloud Run service that accepts tokens only for the configured client ID;
- an OAuth application whose final redirect URI will be supplied by Foundry.

## Before you start

- A Google Cloud project with billing enabled.
- Permission to configure Google Auth Platform and deploy Cloud Run.
- MCP server source code, or a server based on Google's maintained guidance.
- A temporary redirect URI controlled by you for initial client creation.

The final Foundry redirect URI is not required yet.

## Guide

1. [Configure Google OAuth and create the Web client](configure-oauth.md).
2. [Create and deploy the Cloud Run MCP server](create-cloud-run-mcp.md).
3. Return to the [Azure integration guide](../README.md) to provision Azure and
   obtain the final callback.
4. Use [troubleshooting and cleanup](troubleshooting.md) when needed.

## Placeholder convention

| Placeholder | Meaning |
| --- | --- |
| `<GOOGLE_CLOUD_PROJECT_ID>` | Google Cloud project ID |
| `<REGION>` | Cloud Run region |
| `<SERVICE_NAME>` | Cloud Run service name |
| `<MCP_SERVER_BASE_URL>` | Cloud Run service URL without `/mcp` |
| `<MCP_ENDPOINT>` | Complete MCP URL |
| `<TEMPORARY_REDIRECT_URI>` | Temporary URI used only during initial client setup |
| `<GOOGLE_OAUTH_CLIENT_ID>` | Google Web application client ID |
| `<GOOGLE_OAUTH_CLIENT_SECRET>` | Google client secret; never commit it |
| `<GOOGLE_OAUTH_REDIRECT_URL>` | Final callback exported by azd after provisioning |

## Google Cloud checkpoint

Before returning to Azure, confirm:

- the OAuth Web client exists;
- its client ID and secret are stored securely;
- intended test users and identity scopes are configured;
- Cloud Run is deployed;
- `ALLOWED_CLIENT_IDS` contains the OAuth client ID;
- unauthenticated MCP requests return application-level `401`;
- the full `<MCP_ENDPOINT>` is recorded.
