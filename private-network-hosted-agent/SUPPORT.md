# Support

This template is not a Microsoft support entitlement or
a service-level commitment.

## Choose the correct channel

| Issue | Channel |
|---|---|
| Reproducible defect in unmodified template code or documentation | Open a repository issue without sensitive data. |
| Azure service incident, quota, capacity, region, preview, billing, or platform behavior | Use the Azure support channel associated with the target subscription. |
| Security vulnerability in the template | Follow the repository [Security Policy](https://github.com/microsoft/Foundry-Agent-Solution-Templates/security/policy); do not open a public issue. |
| Customer customization, application behavior, policy, networking, or data design | Use the customer's engineering and support process. |

This template does not define a supported-version window, response SLA, or
support commitment for modified forks. Adopters must define those policies
before production delivery.

## Before filing a template issue

Run the applicable preflight and validation, then include:

- exact repository commit or release;
- Azure CLI, azd, Bicep, PowerShell, Python, and azd extension versions;
- sanitized azd environment name, Azure region, connectivity mode, and exact Agent
  version;
- failing step and sanitized command/error;
- timestamp, deployment operation ID, request/correlation ID, and whether the
  caller was connected through the configured private access path;
- expected versus actual behavior.

Do not include credentials, access tokens, S2S shared keys, VPN profiles,
private keys, Docker auth, tenant-sensitive configuration, customer prompts, or
sensitive Search documents.

Microsoft is responsible for platform behavior. Where the issue depends on a
Microsoft service capability or limit, link the current Microsoft Learn page
and retain the Azure support request ID.
