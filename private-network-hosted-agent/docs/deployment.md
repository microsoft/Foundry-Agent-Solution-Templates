# Unified deployment

Choose the Agent package source and target subscription first. The unified
orchestrator performs preflight, preview, provisioning, VPN profile export,
Agent deployment, least-privilege Search access, sample seeding, and acceptance.

| Choice | Default Terraform project | Bicep companion project | Required input | What the template owns | Manual handoff |
|---|---|---|---|---|---|
| `Source` | Template root (`infra-terraform`) | `scenarios\bicep` (`infra-bicep`) | Subscription ID | Foundry solution and Python 3.13 source Agent built by Foundry with `remote_build` | Complete the selected connectivity handoff; for P2S, connect the exported VPN profile |
| `ExistingPrivateAcr` | `scenarios\existing-private-acr` (`infra-terraform`) | `scenarios\bicep-existing-private-acr` (`infra-bicep`) | Subscription ID, canonical ACR resource ID, exact login server, digest-pinned image | Foundry solution, Agent, and Foundry `ContainerRegistry` project connection only | Complete the selected connectivity and ACR network handoffs; have the ACR owner grant the printed pull role |

Do not combine the paths. Existing ACR, image, network, DNS, pipeline, and IAM
remain enterprise-owned.

## Before running

Install Git, Azure CLI, Terraform, Azure Developer CLI (`azd`), PowerShell 7,
Python, and Windows Azure VPN Client for the default P2S path. The Bicep
companion also requires Azure CLI with Bicep. Review
[Configuration](configuration.md), [Cost planning](cost.md), and
[Production adoption](production-readiness.md).

Authenticate if the tools are not already signed in:

```powershell
az login
azd auth login
```

The deploying identity needs resource creation permission and permission to
create the template's least-privilege role assignments at the selected scope.
The read-only preflight checks the effective
`Microsoft.Authorization/roleAssignments/write` permission before quota and
provisioning work begins. Azure preview remains authoritative for conditional
ABAC grants because the effective-permissions response does not prove that each
requested role definition satisfies those conditions. Keep time-bound or PIM
role-assignment access active through provisioning and its bounded retry.
Provider registration may require subscription-level permission.

The default core region and Azure AI Search region are both `westus3`. Before
accepting or overriding either value, apply the
[region and capacity selection requirements](configuration.md#region-and-capacity-selection).

## Source command

From the template root:

```powershell
./scripts/deploy.ps1 `
  -DeploymentMode Source `
  -SubscriptionId "<subscription-id>"
```

This is the default Terraform path through `infra-terraform`. It does not
require Docker or ACR. To deploy the equivalent `infra-bicep` implementation,
add:

```powershell
  -InfrastructureProvider Bicep
```

The script then selects `scenarios\bicep`.
The command uses the default `pointToSite` mode. See
[Connectivity deployment commands](connectivity.md#deployment-commands) for
executable `pointToSite`, `siteToSite`, and `vnetPeering` variants.

## Existing private ACR command

Confirm every prerequisite in
[Existing private ACR](existing-private-acr.md), then run:

```powershell
./scripts/deploy.ps1 `
  -DeploymentMode ExistingPrivateAcr `
  -SubscriptionId "<subscription-id>" `
  -ContainerRegistryResourceId "<canonical-acr-arm-id>" `
  -ContainerRegistryEndpoint "<exact-login-server>" `
  -ContainerImage "<login-server>/<repository>@sha256:<digest>"
```

This command defaults to Terraform and selects
`scenarios\existing-private-acr`. Add `-InfrastructureProvider Bicep` to select
the `scenarios\bicep-existing-private-acr` companion instead.

The script validates but never changes the external ACR. Provisioning creates
the Foundry project identity, and the first Agent creation establishes its
stable managed identity. The script announces this bootstrap before invoking
the first deployment. If the expected registry-authentication `ImageError`
occurs, it is classified as the IAM handoff rather than an unexpected workflow
failure. The script then prints both exact principals, the role, registry scope,
and repository. The ACR owner applies those assignments outside this template;
the script revalidates after propagation and continues the deployment. Other
initial deployment failures remain fatal.

At the network pause, follow the complete Portal or CLI checklist in
[Complete the external private network handoff](existing-private-acr.md#complete-the-external-private-network-handoff).
The deployment output prints this document path again at both the network and
ACR IAM pauses.

## Environment and dedicated resource group

`-EnvironmentName` names local azd state under `.azure/`, contributes to resource
names, and is the only resource-group naming input. The workflow and selected
infrastructure implementation always derive a dedicated
`rg-<environment-name>`.
There is no existing-resource-group deployment path.

Once the workflow records an environment's subscription, deployment mode, and
derived resource group, a mismatched rerun fails.
After resolving that binding, the workflow selects the target azd environment
before invoking any validator, VPN export, provision, or Agent deployment
command. This prevents a different local default environment from supplying
resource endpoints to the active deployment.

The selected Terraform or Bicep implementation creates the group with exact
ownership metadata. The deployment workflow never deletes the group, including
after failure. Use the ordered [cleanup script](cleanup.md) when removing an
environment.

Terraform uses local state. Keep `.terraform\` and `*.tfstate*` ignored and
retain `infra-terraform\.terraform.lock.hcl`. Terraform and Bicep environments
are not interchangeable; use a different environment name when changing
providers.

Omitting `-EnvironmentName` first checks the local default azd environment. The
script reuses it only when subscription, deployment mode, expected resource
group, and ownership all match; otherwise it generates a new environment and
group. This supports rerunning the same command after an interruption.

For an isolated test, provide a previously unused environment name:

```powershell
./scripts/deploy.ps1 `
  -DeploymentMode Source `
  -SubscriptionId "<subscription-id>" `
  -EnvironmentName "fpha-test-<unique-suffix>"
```

The script creates that environment and derives
`rg-fpha-test-<unique-suffix>`. Reuse the name only to resume that deployment.

Generated-name collisions fail rather than adopt an existing group. Reruns
resume only when the selected azd environment, deployment mode, derived group
name, and template ownership metadata all match.

## VPN handoff

For the default `pointToSite` mode, the script exports a resource-scoped profile
under `artifacts/p2s/<environment-name>/` and pauses. Import the
`AzureVPN/azurevpnconfig-resource-dns.xml` file in Azure VPN Client, connect with
Microsoft Entra ID, then press Enter.

On a safe resume, when the infrastructure fingerprint and live validators
still match and that environment's profile file exists, the script reuses the
profile. Keep the existing Azure VPN Client connection and do not re-import the
XML. The script exports a fresh profile only for the initial handoff, when the
local file is missing, or after infrastructure must be reconciled.

The ACR path adds only the exact validated registry login and regional data
hostnames, including their Private Link forms. It never sends the broad
`azurecr.io` suffix to the private resolver.

`-NoPrompt` never bypasses private connectivity: it continues only when private
DNS already resolves the deployed endpoints to RFC1918 addresses. Otherwise it
stops after writing the profile. Normal interactive use always includes the VPN
handoff in `pointToSite` mode.

After validation succeeds, the completion summary includes both the Foundry
playground URL and a copyable `azd ai agent invoke` command. The command pins the
validated agent version and explicitly selects the correct project directory
and azd environment.

The same summary prints a point-in-time security validation report at
`artifacts/validation/<environment-name>/latest.md`. Timestamped Markdown copies
in the same directory preserve prior runs. The report binds the checks to the
environment, deployment mode, resource group, Agent version, source revision and
clean/dirty tree state, and UTC execution time. A report is also written when a
check fails; the deployment still fails and later checks are marked `NOTRUN`.
The report is local evidence and can contain environment or resource
identifiers. Review and remove tenant- or environment-sensitive identifiers
before sharing it outside an approved support channel.

## Safe reruns and failures

After a VPN, ACR IAM, Agent readiness, or RBAC interruption, rerun the same
command. An explicit `-EnvironmentName` selects that environment; if omitted,
the compatible default is selected as described above. Infrastructure
reconciliation is skipped only when the stored fingerprint and live validators
still match. Otherwise the workflow runs `azd provision`. It never rolls back or
deletes partial resources.

Before preview and each provision attempt, the workflow reads the tagged
Firewall state. The initial no-policy creation stage runs only until that
Firewall has an attached policy; later reconciliations preserve the policy
instead of detaching and reattaching it.

The staged Firewall creation and policy-attachment sequence remains ordered to
avoid conflicting VNet and Firewall updates. Independent Firewall Policy rules
deploy alongside the initial Firewall creation. Private DNS Zones are also
created separately from their VNet links and Resolver, allowing ARM to overlap
the service private-endpoint branches with DNS network plumbing. These ordering
changes do not alter the Firewall rules, forced route, private endpoints, CMKs,
local-auth settings, or public-network-access settings.

Every external command is reported with its stage. Deletes, replacements,
generated-group ownership ambiguity, and attempted external ACR ownership stop
the workflow. Policy, quota, capacity, authorization, and region failures are
not retried by weakening controls.

For Bicep, during `azd provision`, the workflow also polls read-only ARM
deployment operations and prints the active leaf resource. `[PROGRESS]` marks a
stage change, while `[WAITING]` identifies the resource or nested deployment
that Azure Resource Manager is still processing. Progress output intentionally
omits elapsed-time and completion-time estimates.

When Bicep `azd provision` fails, the workflow reads the reported ARM deployment
operations and recursively expands nested deployments. The formatter redacts
common secret and token patterns, but it prints the leaf resource name and ID,
type, scope, UTC time, error code, target, message, and a GUID correlation ID
when available. Treat this output as tenant-sensitive and do not paste it into
a public issue without review. It classifies common conflict, authorization,
quota/capacity, policy, invalid-configuration, and service-side failures, plus
terminal `Failed` state, and prints whether an unchanged rerun is reasonable.
Unknown errors still produce an actionable fallback covering existing,
soft-deleted, and `Failed` resources, Azure Portal deployment operations, the
resource Activity Log, customer troubleshooting, and Azure Support evidence. A
diagnostic lookup failure is reported separately and never replaces the
original `azd provision` failure. Terraform failures retain Terraform's own
diagnostics; the workflow does not apply ARM deployment-operation diagnostics
to that provider.

Provision failure handling never deletes or directly changes Azure resources.
When every reported leaf failure is either a Failed Azure Firewall with a
transient service error or a Foundry private endpoint blocked while its account
is still provisioning, the workflow retries the same idempotent `azd provision`
command once. It performs no resource-level repair and never retries other
failure categories or more than once. Follow the printed guidance when that
bounded retry does not succeed.

## Existing environment and coworker handoff

Private connectivity and Foundry authorization are separate gates. A coworker
who only invokes a known Agent needs `Foundry Agent Consumer` on the Foundry
project. Add `Reader` on the solution resource group only when the coworker must
discover ARM outputs and run the full environment validation.

### Grant and hand off access

Use object IDs supplied through the organization's identity process so the
operator does not also need directory lookup permission:

```powershell
$SubscriptionId = "<subscription-id>"
$ResourceGroup = "<resource-group>"
$ProjectResourceId = "<foundry-project-resource-id>"
$TesterObjectId = "<tester-or-test-group-object-id>"
$PrincipalType = "User" # Use "Group" for a security group.

az role assignment create `
  --subscription $SubscriptionId `
  --assignee-object-id $TesterObjectId `
  --assignee-principal-type $PrincipalType `
  --role "Foundry Agent Consumer" `
  --scope $ProjectResourceId `
  --output none
```

For the full validation path only, add resource-group `Reader`:

```powershell
$ResourceGroupId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"

az role assignment create `
  --subscription $SubscriptionId `
  --assignee-object-id $TesterObjectId `
  --assignee-principal-type $PrincipalType `
  --role "Reader" `
  --scope $ResourceGroupId `
  --output none
```

`INVOCATION_TEST_PRINCIPAL_OBJECT_ID` can create one project-level consumer
assignment during provisioning. It is not an application allowlist. For repeat
testing, prefer an organization-managed Microsoft Entra security group with its
normal membership review.

Transfer these tenant-specific but non-secret coordinates through an approved
enterprise channel:

- repository URL and tested commit or release;
- subscription ID, resource group, and azd environment name;
- Foundry project resource ID and project endpoint;
- Agent name and exact version;
- for full validation, the resource-group deployment name `solution`.

Do not copy another user's `.azure` directory or post these coordinates in a
public issue. For P2S, follow the
[tester profile handoff](connectivity.md#tester-profile-handoff).

### Invoke-only test

From a clean clone at the tested commit, create local azd context without
provisioning or deploying:

```powershell
az login
azd auth login
az account set --subscription "<subscription-id>"

azd env new "<azd-environment-name>" `
  --subscription "<subscription-id>" `
  --no-prompt
azd env set AZURE_SUBSCRIPTION_ID "<subscription-id>"
azd env set AZURE_TENANT_ID (az account show --query tenantId -o tsv)
azd env set AZURE_RESOURCE_GROUP "<resource-group>"
azd env set FOUNDRY_PROJECT_ENDPOINT "<project-endpoint>"
azd env set AZURE_AI_PROJECT_ENDPOINT "<project-endpoint>"
azd env set AGENT_PRIVATE_SEARCH_AGENT_NAME "private-search-agent"
azd env set AGENT_PRIVATE_SEARCH_AGENT_VERSION "<exact-version>"
```

Keep the configured private access path connected, then invoke with isolated
state:

```powershell
azd ai agent invoke `
  --version "<exact-version>" `
  --new-session `
  --new-conversation `
  "What does the network baseline say about public fallback?"
```

The response must state that there is no public fallback and cite the private
`private-knowledge` Search index. A 403 usually means the tester lacks
`Foundry Agent Consumer` or is outside the private path. For HTTP 424
`session_not_ready`, wait 15-30 seconds, retry once, then inspect the exact
Agent version and logs.

### Restore the full azd environment

A tester with resource-group `Reader` can restore the intentionally non-secret
outputs from the RG-scoped `solution` module deployment:

```powershell
$outputs = az deployment group show `
  --subscription "<subscription-id>" `
  --resource-group "<resource-group>" `
  --name "solution" `
  --query properties.outputs `
  --output json | ConvertFrom-Json

if (-not $outputs) {
  throw "The solution deployment did not return outputs."
}

foreach ($output in $outputs.PSObject.Properties) {
  $name = $output.Name.ToUpperInvariant()
  $value = [string]$output.Value.value
  azd env set $name $value
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to restore azd value '$name'."
  }
}

azd env set AZURE_SUBSCRIPTION_ID "<subscription-id>"
azd env set AZURE_TENANT_ID (az account show --query tenantId -o tsv)
```

This reconstruction creates local files only. Do not publish
`azd env get-values` output; it contains tenant and resource identifiers.

### Validate the source deployment

For the default source-deployed Agent, restore its coordinates and run the
network and Agent checks:

```powershell
azd env set AGENT_PRIVATE_SEARCH_AGENT_NAME "private-search-agent"
azd env set AGENT_PRIVATE_SEARCH_AGENT_VERSION "<exact-version>"

./scripts/validate-network.ps1 -RequirePrivateResolution
./scripts/validate-agent.ps1
```

After testing, delete sessions created by the tester:

```powershell
azd ai agent sessions list --output json
azd ai agent sessions delete "<session-id>" --no-prompt
```

Remove an individual time-bound role assignment after the test window. For a
shared tester group, remove the user through the organization's
identity-governance process rather than deleting the shared assignment.

## Conditional identity extensions

For noninteractive deployment, service principals, workload identity
federation, or managed identity, follow the official
[azd pipeline guidance](https://learn.microsoft.com/azure/developer/azure-developer-cli/configure-devops-pipeline)
and [`azd auth login` reference](https://learn.microsoft.com/azure/developer/azure-developer-cli/reference#azd-auth-login).

If the workload requires a custom P2S audience or user/group-specific VPN
access, follow the official
[custom audience](https://learn.microsoft.com/azure/vpn-gateway/point-to-site-entra-register-custom-app)
and
[P2S user/group access](https://learn.microsoft.com/azure/vpn-gateway/point-to-site-entra-users-access)
guidance. Those are adopter-owned extensions and do not change this template's
gateway authentication contract.
