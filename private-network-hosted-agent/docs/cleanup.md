# Cleanup

Use the guarded cleanup script when removing an environment that deployed
Foundry Agent Service into a virtual network. The detailed manual sequence is
retained below for audit, troubleshooting, and recovery from an interrupted
run.

This procedure uses Azure management-plane operations only. It does not require
the operator workstation to resolve Foundry private endpoints or connect to the
environment VPN. Do not connect a VPN solely for environment teardown.

> **Warning:** Do not start cleanup by deleting the Foundry account, virtual
> network, or resource group, and do not delete them out of order. Foundry
> cleanup is asynchronous. Out-of-order deletion can race service cleanup and
> leave a service association link (SAL) named `legionservicelink` on the Agent
> subnet. The SAL can then block removal of the subnet, its network security
> group (NSG), route table, and the virtual network.

Do not send `DELETE` or `PATCH` requests to
`Microsoft.Network/.../serviceAssociationLinks`. A SAL is service-managed, and
directly modifying it is not a supported recovery path. Remove the owning
Foundry resources in the order below and allow the platform to remove the link.

## Preferred cleanup command

Run from the template root with the exact azd environment name:

```powershell
./scripts/cleanup.ps1 -EnvironmentName "<environment-name>"
```

The script searches the template-root source project and
`scenarios\existing-private-acr`. It continues only when exactly one project
contains that environment. It derives every Azure target from the azd
environment, verifies `rg-<environment-name>` and all three resource-group
ownership tags, verifies the Foundry account/project and solution VNet IDs, then
requires the complete resource-group name as confirmation.

For noninteractive automation, use `-Force`. This skips only the typed
confirmation; it does not bypass target, ownership, ordering, or wait checks:

```powershell
./scripts/cleanup.ps1 `
  -EnvironmentName "<environment-name>" `
  -Force
```

Use `-WhatIf` for a read-only target and ownership validation plus ordered
deletion preview. Use `-Confirm` only when a separate PowerShell confirmation
is required at each high-impact stage; it does not replace the resource-group
name confirmation. The local azd environment is retained by default so an
interrupted cleanup can resume. Add `-RemoveLocalEnvironment` only when local
state should be deleted after Azure confirms that the resource group is absent.
The script stores only the non-secret account incarnation and accepted purge
request in that local environment. These values prevent duplicate mutations and
detect a recreated account; they are not used as proof that Azure cleanup
finished. On every run, the script queries both the active account and the exact
soft-deleted account. A later redeployment creates a different account
incarnation and does not inherit prior cleanup progress.

The script intentionally has no subscription, resource-group, Foundry resource,
VNet, timeout, polling, or project-directory override. Missing or contradictory
azd/ARM values fail before deletion rather than accepting a caller-supplied
replacement.

The script waits up to 30 minutes for `legionservicelink` to disappear. If that
limit expires, it stops before changing subnet associations or deleting the
network/resource group. Rerun the same command later. The platform cleanup can
take longer than this script wait window; never bypass the SAL check.

Account deletion status is reported separately. If Azure exposes the exact
soft-deleted account, the script requests purge and waits until that resource is
absent. Some account deletions do not produce an observable soft-deleted
resource. In that case, the script continues only after three consecutive
queries confirm that both the active and exact soft-deleted resources are
absent. Each message includes the observed state and elapsed time.

During the final asynchronous resource-group deletion, the script reports the
elapsed time and remaining resource count on every poll. When the resource set
changes, it lists resources deleted since the prior check and the resources
still remaining. This reporting is read-only and does not alter Azure's
resource-group deletion operation.

On a rerun, if the dedicated resource group is already absent, the script makes
one exact soft-deleted-account query and checks the deterministic reciprocal
VNet peering when applicable. If neither residual exists, it reports that the
environment is already absent and returns immediately without confirmation or
polling. Real residual resources still follow the guarded recovery path.

For `vnetPeering`, the template created one deterministic reciprocal peering
named `to-<solution-vnet>` inside the customer VNet. The script verifies that
this exact child resource still targets the owned solution VNet, then deletes
only that peering before deleting the solution VNet. It never deletes or changes
the external VNet itself or any other peering.

## Scope and ownership

Each supported environment owns one dedicated `rg-<environment-name>`. Complete
all Foundry, capability-host, purge, and SAL steps before deleting that group.
The script refuses an existing group without exact template ownership metadata.

The opt-in existing-private-ACR deployment creates only the Foundry project
connection to the registry. It does not own the registry, repositories, images,
ACR networking, DNS, pipelines, or IAM.

Record the subscription, resource group, Foundry account, Foundry project,
location, virtual network, and Agent subnet in the approved operations record
before starting. These tenant-specific destructive-operation targets must not
be posted in a public issue. The examples below use PowerShell variables:

```powershell
$subscriptionId = "<subscription-id>"
$resourceGroup = "<foundry-resource-group>"
$accountName = "<AZURE_AI_ACCOUNT_NAME>"
$projectName = "<AZURE_AI_PROJECT_NAME>"
$location = "<AZURE_LOCATION>"
$vnetResourceGroup = "<virtual-network-resource-group>"
$vnetName = "<virtual-network-name>"
$agentSubnetName = "snet-agent"
$apiVersion = "2025-04-01-preview"

az account set --subscription $subscriptionId
```

Use deployment records and the active azd environment to fill these values.
Do not paste complete azd environment output into tickets or logs because it can
contain environment-specific values.

## Supported manual order

Deleting Hosted Agent sessions or versions separately is not required when the
entire Foundry project and account are being removed. Those operations use the
Foundry data plane and therefore require private connectivity when public access
is disabled. Skip them for full environment teardown; do not weaken network
controls or connect a VPN just to perform redundant child-resource deletion.

If the project or account will be retained and only Agent data must be removed,
that is a different cleanup boundary. Use the matching private connection and
delete sessions before their Agent versions, without continuing to the
project/account/network steps below.

### 1. Delete project Capability Hosts

Capability Hosts are nested resources. Always handle every project Capability
Host before the account Capability Host. List the project hosts:

```powershell
$projectHostsUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName/projects/$projectName/capabilityHosts?api-version=$apiVersion"
az rest --method get --url $projectHostsUrl
```

For each returned project host name, issue a separate deletion:

```powershell
$projectHostName = "<project-capability-host-name>"
$encodedProjectHostName = [uri]::EscapeDataString($projectHostName)
$projectHostUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName/projects/$projectName/capabilityHosts/${encodedProjectHostName}?api-version=$apiVersion"
az rest --method delete --url $projectHostUrl
```

Capability Host deletion can take many minutes. A successful `DELETE` means
Azure accepted an asynchronous operation, not that backend cleanup is complete.
Re-run the project-host `GET` until the host is no longer returned before
proceeding. An empty project-host collection is valid; continue to the account
host instead of creating or deleting another resource.

### 2. Delete the account Capability Host

The account host convention used by Foundry Agent Service is
`{accountName}@aml_aiagentservice`:

```powershell
$accountHostName = "$accountName@aml_aiagentservice"
$encodedAccountHostName = [uri]::EscapeDataString($accountHostName)
$accountHostsUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName/capabilityHosts?api-version=$apiVersion"
$accountHostUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName/capabilityHosts/${encodedAccountHostName}?api-version=$apiVersion"

az rest --method get --url $accountHostsUrl
az rest --method delete --url $accountHostUrl
```

Re-run the account-host `GET` until the account host is absent. Do not proceed
merely because the initial request returned successfully.

### 3. Delete the Foundry project and account

Delete each project before its parent account:

```powershell
$projectUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName/projects/$projectName?api-version=$apiVersion"
az rest --method delete --url $projectUrl

az cognitiveservices account delete `
  --name $accountName `
  --resource-group $resourceGroup
```

The Foundry account must be dedicated to this template environment. If it
contains an unexpected project, stop and establish ownership rather than
assuming every child is safe to delete. Only after confirming that every
project belongs to the environment should you repeat the project Capability
Host and project deletion steps for each project before deleting the account.

### 4. Purge the soft-deleted Foundry account

Account deletion can produce a soft-deleted resource. Query the exact deleted
resource and, when it exists, purge it:

```powershell
az cognitiveservices account show-deleted `
  --name $accountName `
  --resource-group $resourceGroup `
  --location $location

az cognitiveservices account purge `
  --name $accountName `
  --resource-group $resourceGroup `
  --location $location
```

Purge is permanent. It requires
`Microsoft.CognitiveServices/locations/resourceGroups/deletedAccounts/delete`
at the required scope. A transient `RequestConflict` immediately after account deletion usually means
soft-delete propagation is incomplete. Wait, query the exact deleted resource
again, and retry the same purge command. If both the active and exact
soft-deleted resources remain absent across repeated reads, there is no deleted
resource available to purge.

### 5. Wait for `legionservicelink` to disappear

Inspect the Agent subnet:

```powershell
az network vnet subnet show `
  --resource-group $vnetResourceGroup `
  --vnet-name $vnetName `
  --name $agentSubnetName `
  --query "serviceAssociationLinks[].{name:name, link:link, linkedResourceType:linkedResourceType, provisioningState:provisioningState}" `
  --output table
```

Continue only when the command returns no service association links. Capability
Host deletion and SAL cleanup are separate asynchronous backend operations. The
official Foundry cleanup sample warns that SAL cleanup can require a later retry
and can take up to 24 hours. Keep the environment intact and retry the read-only
subnet query later rather than repeatedly deleting network resources.

If `legionservicelink` remains after the Capability Hosts are gone, the account
is purged, and the supported wait period has elapsed, open an Azure Support
request. Include sanitized resource IDs, timestamps, operation/request IDs, the
SAL `linkedResourceType`, and confirmation that project hosts were deleted
before the account host. Do not include credentials, VPN profiles, prompts,
customer data, or site-to-site shared keys.

### 6. Remove remaining subnet associations

After the SAL query is empty and after confirming no retained workload uses the
associations, detach the Agent subnet NSG and route table and remove its
delegation:

```powershell
az network vnet subnet update `
  --resource-group $vnetResourceGroup `
  --vnet-name $vnetName `
  --name $agentSubnetName `
  --nsg null

az network vnet subnet update `
  --resource-group $vnetResourceGroup `
  --vnet-name $vnetName `
  --name $agentSubnetName `
  --route-table null

az network vnet subnet update `
  --resource-group $vnetResourceGroup `
  --vnet-name $vnetName `
  --name $agentSubnetName `
  --remove delegations
```

The solution VNet is template-owned. A remote customer VNet used by the peering
mode remains external; remove only the template-created reciprocal peering
described above.

### 7. Delete the remaining template resources

Delete the dedicated group only after the previous steps complete and the SAL
query is empty. Preserve Key Vault purge protection; do not purge the vault as
a cleanup shortcut:

```powershell
az group delete `
  --name $resourceGroup `
  --yes `
  --no-wait

do {
  Start-Sleep -Seconds 15
  $resourceGroupExists = az group exists --name $resourceGroup
} while ($resourceGroupExists -eq "true")
```

Resource-group deletion is also asynchronous. Check its final status before
considering cleanup complete.

## Troubleshooting

### `Workspace not found` or no Capability Host is returned

First verify the active subscription and the exact resource group, account, and
project names. Query both project and account Capability Host collection URLs.
If the correct scope returns an empty collection, or a delete retry returns
`404` after a prior accepted deletion, that host is already absent; continue to
the next scope. Do not recreate a Capability Host merely to delete it.

If `Workspace not found` occurs while the project still exists and the
Capability Host collection cannot be verified, preserve the account and
network and contact Azure Support rather than bypassing the Capability Host
step.

### Purge returns `RequestConflict`

Soft-delete propagation can lag behind account deletion. Wait, use
`az cognitiveservices account show-deleted` with the exact name, resource group,
and location, then retry `az cognitiveservices account purge`. Verify that no
project or Capability Host remains if conflicts continue.

### `legionservicelink` persists

Re-query project and account Capability Hosts and confirm the Foundry account
was purged. Then wait and retry the read-only subnet query. Backend SAL cleanup
can take up to 24 hours according to the official Foundry cleanup sample. If the
link remains after that supported cleanup and wait, contact Azure Support.
Never directly delete or patch the SAL.

### NSG, route-table, subnet, or VNet deletion reports a dependency

These errors can be downstream symptoms of the SAL. Inspect
`serviceAssociationLinks` before changing the NSG, route table, delegation, or
VNet. If `legionservicelink` exists, return to the supported Foundry cleanup and
wait steps. After it disappears, use the Azure VNet deletion troubleshooting
guidance to check private endpoints, IP configurations, gateways, peerings, and
other legitimate dependencies.

### Agent commands return `403 Public access is disabled`

Do not enable public access or connect a VPN when deleting the complete
environment. Agent session and version commands use the Foundry data plane, but
they are not part of this management-plane teardown. Start with the project
Capability Host collection and continue in the documented order.

## Official sources

- [Set up private networking for Foundry Agent Service](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks)
- [Recover or purge deleted Microsoft Foundry resources](https://learn.microsoft.com/azure/ai-services/recover-purge-resources)
- [Troubleshoot failure to delete or modify a virtual network or subnet](https://learn.microsoft.com/troubleshoot/azure/virtual-network/virtual-network-troubleshoot-cannot-delete-vnet)
- [Official Foundry private-network cleanup sample](https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/deployment-tools/cleanup/cleanup.ps1)
