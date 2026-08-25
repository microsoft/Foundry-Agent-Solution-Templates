# Troubleshooting

Use this page as a triage router. Detailed procedures remain in the specialized
guides so fixes do not diverge.

Never enable public access, local/key authentication, anonymous ACR pull, or
broader RBAC to make a diagnostic pass.

| Symptom | First action | Continue with |
|---|---|---|
| Unified deployment stops at a named stage | Keep the same command, environment name, and group. Fix the reported prerequisite, then rerun; partial resources are retained. | [Safe reruns and failures](deployment.md#safe-reruns-and-failures) |
| ARM provisioning fails for any resource | For Bicep, use the printed ARM leaf diagnostics. For the default Terraform path, use the Terraform diagnostic and Azure Activity Log. Rerun only when the guidance says it is appropriate. | [Safe reruns and failures](deployment.md#safe-reruns-and-failures) |
| `-NoPrompt` stops after VPN profile export | Connect the generated resource-scoped profile; noninteractive mode does not bypass private DNS validation. | [VPN handoff](deployment.md#vpn-handoff) |
| Existing private ACR handoff is incomplete | Give both printed principals, the role, exact registry scope, and repository to the ACR owner, then rerun after propagation. | [Existing private ACR](existing-private-acr.md) |
| Required provider preflight failure | Register the exact provider namespace reported by `scripts/preflight.ps1`; do not provision yet. | [Register a required resource provider](#register-a-required-resource-provider) |
| Model, quota, Search region, S2S, or peering preflight failure | Fix the exact prerequisite reported by `scripts/preflight.ps1`; do not provision yet. | [Configuration reference](configuration.md) |
| Terraform or Bicep preview shows unexpected deletes or replacements | Stop and verify the selected provider, azd environment, resource group, parameters, and ownership. | [First deployment](deployment.md) |
| Foundry, Search, or Key Vault resolves publicly or not at all | Keep the configured private access path connected and validate DNS/routing. | [Connectivity, DNS, and routing](connectivity.md) |
| Managed corporate device resolves a synthetic address or resets private TLS | Compare UDP/TCP DNS and work with the endpoint/network security owner. Do not bypass the security agent locally. | [Enterprise DNS and TLS interception](connectivity.md#enterprise-dns-and-tls-interception) |
| Private endpoint is missing or unapproved | Inspect the management-plane validation result and selected Terraform or Bicep deployment. | [Validation](validation.md) |
| Search seeding returns `Forbidden` | Confirm private reachability and bootstrap Search roles; allow RBAC propagation rather than broadening permissions. | [Unified deployment](deployment.md) |
| Agent cannot query Search | Confirm the dedicated Agent identity has `Search Index Data Reader` and no write roles. | [Security controls](security.md) |
| Agent invocation returns 403 | Verify both private connectivity and `Foundry Agent Consumer` on the project. | [Invoke-only test](deployment.md#invoke-only-test) |
| Agent invocation returns 424 `session_not_ready` | Wait 15-30 seconds, retry once, then inspect Agent status and logs. | [Invoke-only test](deployment.md#invoke-only-test) |
| Agent answer lacks the expected fact or citation | Confirm the sample index exists, contains the expected schema/data, and the Agent can query it. | [Customize the template](customization.md#replace-the-sample-knowledge) |
| `azd show` says the app is not provisioned after successful infrastructure deployment | Use provider state, azd environment outputs, project coordinates, exact-version validation, and successful invocation as combined evidence. | [Validation](validation.md) |
| Existing private ACR Agent fails to become active | Run the dedicated fail-closed preflight and query the exact Agent version. | [Private ACR troubleshooting](troubleshooting-existing-private-acr.md) |

## Register a required resource provider

When preflight stops with `Provider '<namespace>' is '<state>'`, use the exact
namespace from the error. Select the deployment subscription, inspect the current
state, register the provider, and wait for registration to complete:

```powershell
$ProviderNamespace = "<provider-from-preflight-error>"

az account set --subscription $SubscriptionId
az provider show `
  --namespace $ProviderNamespace `
  --query "{namespace:namespace,state:registrationState}" `
  -o table
az provider register `
  --namespace $ProviderNamespace `
  --wait
```

If registration returns `AuthorizationFailed`, stop and ask a subscription
administrator to register the provider or grant the required provider
registration permission. Do not broaden deployment RBAC or security controls as
a workaround.

Rerun `scripts/preflight.ps1` with the same deployment values and continue only
after it reaches `[OK] Preflight completed without changing Azure resources.`
See Microsoft's
[resource provider registration guidance](https://learn.microsoft.com/azure/azure-resource-manager/troubleshooting/error-register-resource-provider)
for Azure CLI and portal procedures.

`Microsoft.Quota` is optional for this template's default source deployment.
When preflight reports it as a warning, Microsoft.Quota-specific validation is
skipped while model availability and regional Standard quota are still checked
through `Microsoft.CognitiveServices`; the warning does not block provisioning.

## ARM deployment failure categories

The unified workflow performs read-only diagnostics for every failed ARM leaf
resource. It does not delete or change resources. It retries the unchanged
provision command at most once only when every leaf failure is either a
recognized transient Azure Firewall service error or a Foundry private endpoint
waiting for its account to finish provisioning. Use the printed category:

| Category | Rerun guidance | Required review |
|---|---|---|
| `Conflict` | Do not rerun until reviewed. | Inspect existing, soft-deleted, and `Failed` resources with the same name; verify ownership. |
| `Authorization` | Do not rerun until access is corrected. | Check principal, scope, RBAC, deny assignments, and ABAC conditions without broadening template permissions. |
| `QuotaOrCapacity` | Do not rerun unchanged. | Check regional quota/capacity; request quota or choose an approved supported region. |
| `Policy` | Do not rerun unchanged. | Inspect the policy assignment and compliance reason; obtain approved remediation or exemption. |
| `InvalidConfiguration` | Rerun only after correction. | Fix the named template parameter, API contract, or resource property. |
| `ServiceOrTransient` | One later rerun is reasonable after state review. | First check whether the resource already exists or is `Failed`; if the same 5xx/timeout repeats, stop. |
| `TerminalFailedState` | Do not rerun blindly. | Review the existing `Failed` resource, dependencies, ownership, and approved recovery procedure. |
| `Unknown` | Rerun safety is unknown. | Inspect existing/soft-deleted/`Failed` resources, deployment operations, and Activity Log before deciding. |

For every category, use these Azure Portal paths:

- **Deployment operations:** Resource group > Deployments > failed deployment
  > Deployment details > Operation details. For subscription-scope deployments,
  use Subscriptions > selected subscription > Deployments > failed deployment >
  Operation details.
- **Activity Log:** Monitor > Activity log, filtered by subscription, resource
  ID, Failed status, and the UTC diagnostic time printed by the script.

In an authenticated Azure Support case, provide the exact leaf resource ID,
correlation ID, UTC time, and subscription ID needed to investigate the Azure
resource. Do not include tokens, claims, secrets, shared keys, or other
credentials.

## Collect support evidence

Collect the following evidence:

- exact commit or release and azd extension versions;
- azd environment name, subscription, region, and deployment operation ID;
- failing step, command, timestamp, sanitized error code, and request ID;
- connectivity mode and whether the check ran from the configured private
  access path;
- relevant validation result and exact Agent version.

Never attach tokens, credentials, S2S shared keys, VPN profiles, private keys,
Docker auth files, customer prompts, or sensitive Search documents. Follow
[`SUPPORT.md`](../SUPPORT.md) for the correct support channel. Share exact
tenant and resource identifiers only through the authenticated Azure Support or
customer-approved channel; sanitize them before opening a public repository
issue.
