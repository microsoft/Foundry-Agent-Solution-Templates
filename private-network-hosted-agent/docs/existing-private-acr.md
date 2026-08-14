# Existing private Azure Container Registry

Use this opt-in workflow when an enterprise pipeline already publishes the
Hosted Agent image to an existing Azure Container Registry (ACR). The default
template-root workflow remains Python 3.13 source deployment with
`remote_build`.

The Bicep template does not create or configure the ACR, its Private Endpoint,
Private DNS zone/link, or ACR role assignments. It creates only a managed
identity `ContainerRegistry` connection under the Foundry project.

## Platform date requirement

Fully private ACR is supported only when the Foundry project was created
**after June 25, 2026**. Projects created before that date require the registry
public endpoint to remain reachable. This template has no public fallback and
rejects those projects.

See the Microsoft Foundry
[private-network limitations](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/virtual-networks#limitations).

## Enterprise prerequisites

The registry owner must provide:

- the canonical ACR ARM resource ID;
- the exact ACR `loginServer`, including a Domain Name Label hash when present;
- a Linux `amd64` image already published by an enterprise pipeline as a
  **Docker distribution manifest schema 2**
  (`application/vnd.docker.distribution.manifest.v2+json`);
- the image reference pinned as
  `<login-server>/<repository>@sha256:<64-lowercase-hex>`;
- Premium SKU, public network access disabled, admin user disabled, anonymous
  pull disabled, and a `registry` Private Endpoint in the Approved state;
- `privatelink.azurecr.io` resolution and routing from the solution VNet;
- pull authorization for both identities described in
  [the external RBAC handoff](#create-the-agent-identity-and-complete-the-external-rbac-handoff).

Use these Microsoft procedures when the prerequisite does not already exist:

- [Create an ACR with Azure CLI](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-get-started-azure-cli)
- [Configure ACR Private Link and `privatelink.azurecr.io`](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-endpoints)
- [Deploy a Hosted Agent from an existing/private ACR](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-private-azure-container-registry)
- [ACR RBAC role selection](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-rbac-built-in-roles-overview)
- [ACR ABAC repository conditions](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-rbac-abac-repository-permissions)

## Start here: preferred unified workflow

First [collect the required deployment values](#collect-the-required-deployment-values).
Then run from the template root:

```powershell
./scripts/deploy.ps1 `
  -DeploymentMode ExistingPrivateAcr `
  -SubscriptionId "<subscription-id>" `
  -ContainerRegistryResourceId "<acr-arm-resource-id>" `
  -ContainerRegistryEndpoint "<exact-login-server>" `
  -ContainerImage "<login-server>/<repository>@sha256:<digest>"
```

The script owns the workflow; its planned pauses are only for adopter-owned
actions:

| Phase | Operator action | Continue only when |
|---|---|---|
| Network pause | Follow [Complete the external private network handoff](#complete-the-external-private-network-handoff). | Private DNS, routing, VPN, and the fail-closed network validation pass. |
| Initial Agent deployment | Let the script create the stable Hosted Agent identity. The script classifies the expected registry-authentication `ImageError` as the transition to the IAM handoff rather than a completed deployment. | The script confirms the stable Agent identity was created. |
| IAM pause | Follow [Create the Agent identity and complete the external RBAC handoff](#create-the-agent-identity-and-complete-the-external-rbac-handoff). | Both exact-scope pull assignments have propagated and the fail-closed ACR validation passes. |
| Completion | Let the script retry deployment and run acceptance validation. | The exact Agent version is active and the final validation report passes. |

The network and IAM handoffs are adopter-owned changes to the existing
enterprise ACR boundary. The template validates them but does not apply them.

## Collect the required deployment values

The unified command requires four enterprise values. The registry name,
repository, and approved image build are inputs from the registry owner or image
pipeline; they are not selected by this template.

| Deployment parameter | Value source |
|---|---|
| `SubscriptionId` | Subscription in which the template deploys the Foundry solution. The ACR can be in another subscription because its canonical ARM ID identifies its scope. |
| `ContainerRegistryResourceId` | Exact `id` returned by the ACR management API. |
| `ContainerRegistryEndpoint` | Exact `loginServer` returned by the ACR management API. Do not construct this hostname because it can contain a Domain Name Label hash. |
| `ContainerImage` | Pipeline-approved repository and immutable manifest digest, formatted as `<login-server>/<repository>@sha256:<64-lowercase-hex>`. |

Start with the subscription, resource group, and registry name shown on the ACR
Overview page. The following management-plane query works without access to the
ACR private endpoint:

```powershell
$acrSubscriptionId = "<acr-subscription-id>"
$acrResourceGroup = "<acr-resource-group>"
$acrName = "<acr-name>"

$registry = az acr show `
  --subscription $acrSubscriptionId `
  --resource-group $acrResourceGroup `
  --name $acrName `
  --query '{resourceId:id,loginServer:loginServer}' `
  --output json | ConvertFrom-Json

$registry
```

Select the repository and image build approved by the enterprise pipeline. From
an execution point that can resolve and reach the ACR private endpoint, list the
available repositories and their manifest digests:

```powershell
az acr repository list `
  --subscription $subscriptionId `
  --name $acrName `
  --output table

$repository = "<pipeline-approved-repository>"

az acr manifest list-metadata `
  --subscription $subscriptionId `
  --registry $acrName `
  --name $repository `
  --query '[].{digest:digest,tags:tags,timestamp:timestamp}' `
  --output table

$digest = "sha256:<64-lowercase-hex-from-approved-build>"
$containerImage = "$($registry.loginServer)/${repository}@${digest}"
$containerImage
```

Do not choose a digest based only on recency or a mutable tag. Confirm the
intended build with the image pipeline owner. If the repository or manifest
queries return 403, a public IP, or a timeout, move to the approved private
execution point or request the complete digest-pinned image reference from the
registry owner. Do not enable the ACR public endpoint or local authentication.

These queries follow the Microsoft documentation for
[`az acr show`](https://learn.microsoft.com/en-us/cli/azure/acr#az-acr-show),
[ACR repositories and manifest digests](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-concepts),
and
[`az acr manifest list-metadata`](https://learn.microsoft.com/en-us/cli/azure/acr/manifest#az-acr-manifest-list-metadata).
The Microsoft Foundry
[pre-built image workflow](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-private-azure-container-registry)
accepts a digest-pinned image; this template additionally enforces the manifest
and platform requirements below.

## Why a digest is required

Tags can move. Microsoft recommends avoiding mutable stable tags for
deployments, using unique deployment identifiers, and identifies the manifest
digest as the image content's unique SHA-256 identifier. Foundry also
recommends digest pinning for reproducible pre-built image deployment.

References:

- [Foundry pre-built image deployment](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-private-azure-container-registry)
- [ACR image tag and version best practices](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-image-tag-version)

This template therefore rejects tag-only image references even though the
platform accepts them.

## Required container manifest format

Digest pinning identifies content but does not identify a compatible manifest
format. The enterprise image pipeline must publish the Docker distribution
schema 2, Linux `amd64` image required in the prerequisites above. The
private-data-plane preflight verifies the manifest, config, layer, and platform
metadata directly from the pinned digest and fails before deployment on an
incompatible image.

This requirement is a template-observed compatibility boundary, not a
Microsoft-documented platform guarantee. The evidence, exact accepted media
types, symptom diagnosis, and schema 2 remediation are maintained in
[Troubleshoot existing private ACR Agent deployment](troubleshooting-existing-private-acr.md#known-manifest-compatibility-failure).

## Complete the external private network handoff

This section is the canonical checklist for the network pause printed by
`scripts/deploy.ps1`. The ACR owner or network operator performs these changes
outside the template. Do not press Enter at the network pause until the final
validation step passes.

The template creates and validates the Foundry-side resources and exports the
resource-scoped VPN profile. It does not create or change the enterprise ACR
Private Endpoint, ACR Private DNS zone or links, VNet peering, hub routing, or
ACR IAM.

### Identify the exact resources

Use the environment name printed by the deployment. The Existing Private ACR
azd environment is under `scenarios\existing-private-acr`, not the template
root:

```powershell
Set-Location scenarios\existing-private-acr

$environmentName = "<environment-name-printed-by-deploy.ps1>"
$values = azd env get-values `
  --environment $environmentName `
  --output json | ConvertFrom-Json -AsHashtable

$solutionVnetId = $values['AZURE_VNET_ID']
$acrResourceId = $values['AZURE_CONTAINER_REGISTRY_RESOURCE_ID']
$acrLoginServer = $values['AZURE_CONTAINER_REGISTRY_ENDPOINT']

$solutionVnetParts = $solutionVnetId -split '/'
$solutionVnetSubscriptionId = $solutionVnetParts[2]
$solutionVnetResourceGroup = $solutionVnetParts[4]
$solutionVnetName = $solutionVnetParts[8]

$acrParts = $acrResourceId -split '/'
$acrSubscriptionId = $acrParts[2]
$acrResourceGroup = $acrParts[4]
$acrName = $acrParts[8]

$acr = az acr show `
  --subscription $acrSubscriptionId `
  --resource-group $acrResourceGroup `
  --name $acrName `
  --query '{loginServer:loginServer,dataEndpointHostNames:dataEndpointHostNames,privateEndpointConnections:privateEndpointConnections}' `
  --output json | ConvertFrom-Json

[pscustomobject]@{
  SolutionVnetResourceGroup = $solutionVnetResourceGroup
  SolutionVnetName = $solutionVnetName
  AcrResourceGroup = $acrResourceGroup
  AcrName = $acrName
  AcrLoginServer = $acr.loginServer
  AcrDataEndpoints = $acr.dataEndpointHostNames -join ', '
}
```

Do not paste complete azd environment output into tickets or logs. Record only
the non-secret identifiers needed by the network owner.

### 1. Verify the ACR Private Endpoint and DNS zone group

In Azure Portal:

1. Open the existing ACR, then select **Networking** > **Private access**.
2. Open the approved Private Endpoint for the `registry` subresource.
3. Select **DNS configuration** and open its Private DNS zone group.
4. Confirm the zone is `privatelink.azurecr.io`.
5. Confirm the zone group manages an A record for the exact ACR `loginServer`
   and every hostname returned in `dataEndpointHostNames`.

The standard zone name is `privatelink.azurecr.io`; it is shared and is not
specific to this template or one registry. Use a Private DNS zone group on the
Private Endpoint rather than manually predicting A records. The exact login
server can contain a Domain Name Label hash.

To audit the same configuration with Azure CLI:

```powershell
$approvedPrivateEndpointIds = @(
  $acr.privateEndpointConnections |
    Where-Object {
      $_.privateLinkServiceConnectionState.status -eq 'Approved'
    } |
    ForEach-Object {
      $_.privateEndpoint.id
    }
)

$approvedPrivateEndpointIds
```

For the selected `registry` endpoint, list its DNS zone groups:

```powershell
$privateEndpointId = "<approved-registry-private-endpoint-resource-id>"
$privateEndpointParts = $privateEndpointId -split '/'
$privateEndpointSubscriptionId = $privateEndpointParts[2]
$privateEndpointResourceGroup = $privateEndpointParts[4]
$privateEndpointName = $privateEndpointParts[8]

az network private-endpoint dns-zone-group list `
  --subscription $privateEndpointSubscriptionId `
  --resource-group $privateEndpointResourceGroup `
  --endpoint-name $privateEndpointName `
  --output table
```

Stop and ask the ACR owner to correct the endpoint when its connection is not
approved, its group ID is not `registry`, the zone group is missing, or the
login/data endpoint records are absent. Do not enable the ACR public endpoint,
local authentication, or anonymous pull.

### 2. Link ACR Private DNS to the Foundry solution VNet

The `privatelink.azurecr.io` zone must have a virtual network link to the exact
Foundry VNet identified above.

In Azure Portal:

1. Open **Private DNS zones** > `privatelink.azurecr.io`.
2. Select **Virtual network links** > **Add**.
3. Enter a unique link name.
4. Select the subscription and `$solutionVnetName`.
5. Leave **Enable auto registration** disabled and save.
6. Confirm the link status is **Completed**.

Equivalent Azure CLI:

```powershell
$acrPrivateDnsZoneSubscriptionId = "<subscription-id-containing-privatelink.azurecr.io>"
$acrPrivateDnsZoneResourceGroup = "<resource-group-containing-privatelink.azurecr.io>"
$dnsLinkName = "link-$environmentName-<unique-suffix>"

az network private-dns link vnet create `
  --subscription $acrPrivateDnsZoneSubscriptionId `
  --resource-group $acrPrivateDnsZoneResourceGroup `
  --zone-name privatelink.azurecr.io `
  --name $dnsLinkName `
  --virtual-network $solutionVnetId `
  --registration-enabled false
```

A Private DNS VNet link provides name resolution but not network reachability.
Complete the next step even when the link reports `Completed`.

### 3. Establish approved routing to the ACR Private Endpoint

If the ACR Private Endpoint is already in the Foundry solution VNet, no peering
is required. Otherwise, the adopter must provide an approved route between the
two VNets, such as direct VNet peering or an enterprise hub. Address spaces must
not overlap.

For direct peering with point-to-site validation through the Foundry VPN
Gateway, create both peering directions. The required end state is:

| Peering resource | Allow VNet access | Allow forwarded traffic | Allow gateway transit | Use remote gateway |
|---|---:|---:|---:|---:|
| Foundry VNet to ACR VNet | Yes | Yes | Yes | No |
| ACR VNet to Foundry VNet | Yes | Yes | No | Yes |

In Azure Portal:

1. Open the Foundry solution VNet and select **Peerings** > **Add**.
2. Select the ACR Private Endpoint VNet as the remote VNet.
3. In the Foundry/local section, enable VNet access, forwarded traffic, and
   gateway transit. Do not enable use of the remote gateway.
4. In the ACR/remote section, enable VNet access, forwarded traffic, and use of
   the remote Foundry gateway. Do not enable gateway transit.
5. Create the peerings and require both directions to show **Connected**.

Equivalent Azure CLI:

```powershell
$acrVnetId = "<vnet-containing-the-acr-private-endpoint>"
$acrVnetParts = $acrVnetId -split '/'
$acrVnetSubscriptionId = $acrVnetParts[2]
$acrVnetResourceGroup = $acrVnetParts[4]
$acrVnetName = $acrVnetParts[8]

az network vnet peering create `
  --subscription $solutionVnetSubscriptionId `
  --resource-group $solutionVnetResourceGroup `
  --vnet-name $solutionVnetName `
  --name "to-$acrVnetName" `
  --remote-vnet $acrVnetId `
  --allow-vnet-access `
  --allow-forwarded-traffic `
  --allow-gateway-transit

az network vnet peering create `
  --subscription $acrVnetSubscriptionId `
  --resource-group $acrVnetResourceGroup `
  --vnet-name $acrVnetName `
  --name "to-$solutionVnetName" `
  --remote-vnet $solutionVnetId `
  --allow-vnet-access `
  --allow-forwarded-traffic `
  --use-remote-gateways
```

An ACR VNet can use only one remote VNet gateway. If it already has a peering
with `Use remote gateway` enabled, do not silently replace that route. Ask the
network owner whether the previous path can be retired, or use an approved
private execution point and routing design that preserves the existing
dependency. The error stating that the remote VNet has no gateway usually means
`Use remote gateway` was enabled on the Foundry side instead of the ACR side.

### 4. Connect the Foundry VPN profile and validate

For point-to-site deployment:

1. Import
   `artifacts\p2s\<environment-name>\AzureVPN\azurevpnconfig-resource-dns.xml`
   into Azure VPN Client.
2. Remove an older profile for the same Foundry gateway before importing a
   newly exported profile.
3. Connect and complete Microsoft Entra sign-in.
4. Use this Foundry VPN profile for validation.

An ACR-side VPN profile does not validate the Foundry deployment path.

Confirm the VPN installed routes for both the Foundry VNet and the VNet
containing the ACR Private Endpoint:

```powershell
Get-NetRoute -AddressFamily IPv4 |
  Where-Object InterfaceAlias -Like '*<current-foundry-vpn-profile-name>*' |
  Select-Object DestinationPrefix, NextHop, InterfaceAlias
```

Then require every ACR login/data hostname to resolve to an RFC1918 address and
accept HTTPS:

```powershell
$acrHosts = @($acr.loginServer) + @($acr.dataEndpointHostNames)

foreach ($hostname in $acrHosts) {
  Resolve-DnsName $hostname -Type A
  Test-NetConnection $hostname -Port 443
}
```

Finally run the template's fail-closed validation from
`scenarios\existing-private-acr`:

```powershell
..\..\scripts\validate-existing-acr.ps1 `
  -ValidateConnection `
  -RequirePrivateDataPlane
```

Continue only when the script reports `[OK]`, every hostname resolves privately,
and every HTTPS test reports `TcpTestSucceeded: True`. At the network pause,
press Enter only after these checks pass.

After the network validation passes, press Enter and let the deployment create
the stable per-Agent identity. Do not grant speculative identities or broaden
network access before the script reaches the IAM pause.

## Create the Agent identity and complete the external RBAC handoff

The template binds the `ContainerRegistry` connection to the Foundry project
identity. Foundry also creates a stable per-agent identity when the Agent is
first created. The preferred deployment script performs that initial creation,
classifies only the expected registry-authentication `ImageError` as the IAM
handoff, and prints the stable values needed by the ACR administrator. Other
initial deployment failures remain fatal:

- `AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID`;
- `AZURE_AI_AGENT_PRINCIPAL_ID`;
- required pull role for the registry's `roleAssignmentMode`;
- `AZURE_CONTAINER_REGISTRY_RESOURCE_ID`;
- repository parsed from `AZURE_CONTAINER_IMAGE`.

These values are not credentials, but they identify tenant resources. Transfer
them to the ACR owner only through an approved enterprise channel; do not post
them in a public issue.

The administrator grants the required role to both principals outside this
template.
`AZD_AGENT_SKIP_ROLE_ASSIGNMENTS=true` prevents the Foundry azd extension from
writing role assignments; preflight rejects the scenario when that control is
absent. Do not put credentials, admin passwords, access tokens, or Docker auth
files in azd environment values.

### Select the role from the ACR authorization mode

Read the registry mode:

```powershell
$acrResourceId = "<registry-scope-printed-by-deploy.ps1>"
$acrParts = $acrResourceId -split '/'
$acrSubscriptionId = $acrParts[2]
$acrResourceGroup = $acrParts[4]
$acrName = $acrParts[8]

az acr show `
  --subscription $acrSubscriptionId `
  --resource-group $acrResourceGroup `
  --name $acrName `
  --query roleAssignmentMode `
  --output tsv
```

Use only the role printed by the deployment:

| ACR `roleAssignmentMode` | Pull role |
|---|---|
| `LegacyRegistryPermissions` | `AcrPull` |
| `AbacRepositoryPermissions` | `Container Registry Repository Reader` |

`AcrPull` is not honored by an ABAC-enabled registry. For ABAC, the enterprise
ACR owner may apply a repository condition that permits the exact repository
printed by the deployment.

### Grant both identities access in Azure Portal

Repeat these steps once for the Foundry project principal and once for the
Hosted Agent principal:

1. Open the existing ACR in Azure Portal.
2. Select **Access control (IAM)** > **Add** > **Add role assignment**.
3. Select the exact pull role printed by `scripts/deploy.ps1`.
4. On **Members**, select **Managed identity**, then select the identity matching
   the printed principal/object ID. If the stable Hosted Agent identity is not
   discoverable in the Portal picker, use the Azure CLI procedure below.
5. For an ABAC registry, apply the enterprise-approved condition for the printed
   repository when repository-scoped access is required.
6. On **Review + assign**, confirm the scope is the ACR resource itself, not the
   subscription or resource group.

Do not grant `Contributor`, `Owner`, ACR push roles, or broader scope to hide a
pull authorization failure.

### Grant both identities access with Azure CLI

Use the two principal IDs, role, and registry scope printed at the IAM pause:

```powershell
$projectPrincipalId = "<printed-foundry-project-principal>"
$agentPrincipalId = "<printed-hosted-agent-principal>"
$pullRole = "<role-printed-by-deploy.ps1>"
$acrResourceId = "<registry-scope-printed-by-deploy.ps1>"

foreach ($principalId in @($projectPrincipalId, $agentPrincipalId)) {
  az role assignment create `
    --subscription $acrSubscriptionId `
    --assignee-object-id $principalId `
    --assignee-principal-type ServicePrincipal `
    --role $pullRole `
    --scope $acrResourceId
}
```

This exact command is appropriate for `AcrPull` on a
`LegacyRegistryPermissions` registry. For an ABAC registry that requires a
repository condition, the ACR owner must add the approved condition when
creating each `Container Registry Repository Reader` assignment.

### Verify propagation before continuing

Require both identities to show the exact role at the exact registry scope:

```powershell
foreach ($principalId in @($projectPrincipalId, $agentPrincipalId)) {
  az role assignment list `
    --subscription $acrSubscriptionId `
    --assignee-object-id $principalId `
    --scope $acrResourceId `
    --query "[?scope=='$acrResourceId'].{principalId:principalId,role:roleDefinitionName,scope:scope}" `
    --output table
}
```

Role assignment propagation can take several minutes. Keep the deployment
paused and rerun the read-only validation until it passes:

```powershell
..\..\scripts\validate-existing-acr.ps1 `
  -ValidateConnection `
  -ValidatePullAuthorization `
  -RequirePrivateDataPlane
```

Press Enter at the IAM pause only after the script reports `[OK]`. The running
deployment then revalidates the same boundary before retrying the Agent.

The validation checks the ACR settings, project creation date, exact Foundry
connection, both pull assignments, RFC1918 login/data endpoint DNS, digest,
Docker schema 2 media types, and Linux `amd64` platform without changing the
enterprise ACR or IAM.

## Manual/audit scenario configuration

The preferred workflow above is the customer deployment path. Use this
lower-level flow only for audit or troubleshooting, from the scenario directory:

```powershell
Set-Location scenarios\existing-private-acr

azd env new "<environment-name>" `
  --subscription "<subscription-id>" `
  --no-prompt

azd env set AZURE_SUBSCRIPTION_ID "<subscription-id>"
azd env set AZURE_TENANT_ID "<tenant-id>"
azd env set AZURE_CONTAINER_REGISTRY_RESOURCE_ID "<acr-arm-resource-id>"
azd env set AZURE_CONTAINER_REGISTRY_ENDPOINT "<exact-login-server>"
azd env set AZURE_CONTAINER_IMAGE "<login-server>/<repository>@sha256:<digest>"
azd env set AZD_AGENT_SKIP_ACR true
azd env set AZD_AGENT_SKIP_ROLE_ASSIGNMENTS true
```

The subscription-scope template derives and creates
`rg-<environment-name>`. Do not set or override `AZURE_RESOURCE_GROUP`.

For an already provisioned environment, reconstruct the remaining non-secret
values from the successful ARM deployment as described in
[Restore the full azd environment](deployment.md#restore-the-full-azd-environment).
Do not copy another user's `.azure` directory.

Run the read-only preflight, preview, and provision:

```powershell
..\..\scripts\validate-existing-acr.ps1
azd provision --preview --no-prompt
azd provision --no-prompt
```

The preview must not create or update a
`Microsoft.ContainerRegistry/registries`, ACR Private Endpoint, Private DNS
zone/link, or ACR role assignment.

Run the initial Agent deployment to create or discover its stable identity:

```powershell
azd deploy private-search-agent-acr --no-prompt

$agent = azd ai agent show private-search-agent-acr --output json |
  ConvertFrom-Json
$agentPrincipalId = $agent.instance_identity.principal_id
azd env set AZURE_AI_AGENT_PRINCIPAL_ID "$agentPrincipalId"
```

Complete the external RBAC handoff above before continuing.

## Manual deployment and validation

For the lower-level flow only, complete the RBAC handoff, keep the private path
connected, and retry deployment:

```powershell
azd deploy private-search-agent-acr --no-prompt
azd ai agent show private-search-agent-acr --output json
..\..\scripts\assign-agent-search-role.ps1
..\..\scripts\validate-all.ps1 -IncludePrivateDataPlane
```

`AZD_AGENT_SKIP_ACR=true` makes `azure.ai.agents` version `1.0.0-beta.7` use the
configured digest as a pre-built image. The scenario's
`docker.remoteBuild: true` setting is the azd core lifecycle switch that keeps
its framework package step empty; the agents extension then skips build,
pull, retag, publish, and ACR creation. It does not run an ACR Task. The
deployment principal therefore needs no ACR push permission.

The Agent must become active and return the expected private Search citations.
Public Foundry, Search, Key Vault, and ACR fallback remains disabled.

## Ownership and teardown

Use the ordered [cleanup workflow](cleanup.md) to delete the template-owned
Agent versions and sessions, Foundry ACR connection, and dedicated solution
resource group. Preserve the enterprise registry, repository, images, Private
Endpoint, Private DNS, and ACR role assignments unless their owner removes them
through a separate governed process.
