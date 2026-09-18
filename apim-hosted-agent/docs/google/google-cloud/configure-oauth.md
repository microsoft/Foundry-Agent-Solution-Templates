# Configure Google OAuth

[Guide home](README.md) | **Configure OAuth** | [Create server](create-cloud-run-mcp.md) | [Troubleshooting](troubleshooting.md)

Complete this configuration in the Google Cloud project that hosts the MCP
server.

## Stage A: create the OAuth client

### Open Google Auth Platform

Open the [Google Cloud console](https://console.cloud.google.com/), select
`<GOOGLE_CLOUD_PROJECT_ID>`, open **Google Auth Platform > Overview**, and
choose **Get started** when the project is not configured.

![Google Auth Platform before configuration](images/05-auth-platform-get-started.webp)

### Configure the application

Enter a recognizable app name and monitored support address.

![App information](images/06-app-information.webp)

Choose **Internal** for an organization-only application when available, or
**External** for other Google accounts. External applications in Testing
status restrict access to configured test users.

![Audience selection](images/08-audience-choice.webp)

Enter a monitored developer contact address.

![Developer contact information](images/09-contact-information.webp)

Review the Google API Services User Data Policy and create the application.

![Finish the app configuration](images/10-finish-agree-policy.webp)

![OAuth configuration created](images/11-oauth-config-created.webp)

### Register identity scopes

Open **Google Auth Platform > Data access**, choose **Add or remove scopes**,
and select:

```text
openid
https://www.googleapis.com/auth/userinfo.email
https://www.googleapis.com/auth/userinfo.profile
```

![Data Access page](images/21-data-access.webp)

![Scope picker](images/22-scope-picker.webp)

![Identity scopes selected](images/23-scopes-selected.webp)

Confirm the scopes appear under non-sensitive scopes.

![Saved identity scopes](images/24-scopes-saved.webp)

The template requests only these identity scopes. If the MCP server exposes
tools that require Drive, Gmail, Calendar, or another Google API:

1. enable the required Google API;
2. register only the required additional scopes in Data Access;
3. update the OAuth scopes in both the Bicep and Terraform Foundry connection
   definitions.

Do not add scopes merely because a server might expose a tool in the future.

### Add test users when required

For an External application in Testing, open **Audience > Test users** and add
every account that will test the connection. Skip this for an Internal
application or a published application without the test-user restriction.

### Create the Web application client

Open **Google Auth Platform > Clients**, choose **Create client**, and select
**Web application**.

![Create OAuth client](images/12-create-client-application-type.webp)

![Application type list](images/13-application-type-list.webp)

![Web application selected](images/14-web-application-selected.webp)

Enter a descriptive name. Leave Authorized JavaScript origins empty unless a
browser application requires one. Add `<TEMPORARY_REDIRECT_URI>` under
**Authorized redirect URIs**.

![Authorized redirect URI section](images/15-redirect-uris-section.webp)

Create the client and immediately store its ID and secret in an approved secret
store. Never place secrets in documentation, logs, tickets, screenshots, or
source control.

### Stage A checkpoint

- The OAuth application exists.
- Required test users are configured.
- Identity scopes are registered.
- The Web client has a temporary redirect URI.
- Client ID and secret are stored securely.

Next: [deploy Cloud Run](create-cloud-run-mcp.md).

## Stage B: add the Foundry callback

Complete this stage only after the Azure integration guide runs
`azd provision` and exports `GOOGLE_OAUTH_REDIRECT_URL`.

1. Open **Google Auth Platform > Clients**.
2. Select the same Web client.
3. Add `<GOOGLE_OAUTH_REDIRECT_URL>` under **Authorized redirect URIs** exactly
   as emitted.
4. Save the client.
5. Complete end-to-end authorization through Foundry.
6. Remove the temporary redirect URI after validation succeeds.

Google requires an exact redirect match, including scheme, host, path, case,
and trailing slash. Never copy a callback from an example or another
environment.

### Stage B checkpoint

- The exact Foundry callback is registered.
- The temporary redirect remains only until validation succeeds.
- Cloud Run still pins tokens to the same Web client ID.

Return to the [Azure integration guide](../README.md) to deploy and test.
