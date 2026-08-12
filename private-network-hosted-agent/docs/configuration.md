# Configuration reference

Use this reference with [First deployment](deployment.md). Values are supplied
through the active azd environment and mapped by `infra/main.parameters.json`.
Do not commit `.azure/<environment>/`, generated VPN profiles, tokens, or
secrets.

## Core values

| azd value | Required | Default | Purpose and constraints |
|---|---|---|---|
| `AZURE_SUBSCRIPTION_ID` | Yes | None | Target subscription. |
| `AZURE_TENANT_ID` | Yes | Current tenant, set by the deploy script | Used by P2S Microsoft Entra authentication. |
| `AZURE_RESOURCE_GROUP` | Output | `rg-<environment-name>` | Dedicated group created by subscription-scope Bicep. It cannot be supplied or overridden. Use `scripts/cleanup.ps1` for ordered teardown. |
| `AZURE_ENV_NAME` | Yes | Compatible default or generated | Names local azd state and contributes to resource names. Use a previously unused explicit `-EnvironmentName` for a separate deployment. |
| `AZURE_LOCATION` | Yes | `westus3` | Foundry, VNet, Key Vault, Firewall, VPN, and DNS Resolver location. Must support the selected model and required Foundry features. P2S and S2S also require Availability Zones for `VpnGw2AZ`. |
| `AZURE_SEARCH_LOCATION` | No | `westus3` | Azure AI Search location. It can differ from the Foundry region; apply the region-selection requirements below. |
| `DEPLOYMENT_PRINCIPAL_OBJECT_ID` | Yes | Current operator, resolved by the deploy script | Operator or CI object ID used for deployment and Search bootstrap roles. |
| `INVOCATION_TEST_PRINCIPAL_OBJECT_ID` | No | Empty | Creates `Foundry Agent Consumer` for one test principal. It is not an application allowlist. |
| `CONNECTIVITY_MODE` | No | `pointToSite` | `pointToSite`, `siteToSite`, or `vnetPeering`. Exactly one mode is deployed. |
| `AZURE_AI_MODEL_DEPLOYMENT_NAME` | No | `gpt-5.1` | Model resource name. The current Bicep and preflight allow only the documented model/version pair. |
| `AZURE_AI_MODEL_VERSION` | No | `2025-11-13` | Pinned model version. Changing it requires coordinated Bicep, preflight, azd, test, and validation updates. |
| `AZURE_AI_MODEL_CAPACITY` | No | `10` | Regional Standard capacity, allowed range 1-300. Availability and quota are not guaranteed. |

### Region and capacity selection

Check current Microsoft documentation before choosing a region or model:

- [Agent limits, quotas, and regions](https://learn.microsoft.com/azure/foundry/agents/concepts/limits-quotas-regions)
- [Azure OpenAI quota and limits](https://learn.microsoft.com/azure/foundry/openai/how-to/quota)
- [Foundry customer-managed keys](https://learn.microsoft.com/azure/foundry/concepts/encryption-keys-portal)
- [Azure AI Search regions and capacity constraints](https://learn.microsoft.com/azure/search/search-region-support)

The Search region does not have to match the Foundry region. The default places
both Foundry and Search in West US 3. Region availability, capacity, and quota
can change. Recheck the linked region tables before every deployment, and
override `AZURE_SEARCH_LOCATION` when current Microsoft guidance or workload
residency requirements call for another supported region. Search still uses a
private endpoint in the template VNet.

For `pointToSite` and `siteToSite`, preflight reads the selected subscription's
live location metadata and requires Availability Zone mappings before deploying
`VpnGw2AZ`. The `vnetPeering` mode does not deploy a VPN Gateway and skips this
check. See [Azure regions with Availability Zones](https://learn.microsoft.com/azure/reliability/regions-list)
and [zone-redundant VPN Gateway deployment](https://learn.microsoft.com/azure/vpn-gateway/create-zone-redundant-vnet-gateway).

The Bicep intentionally omits explicit zones on Azure Firewall and its Standard
public IP. In a region that supports Availability Zones, new Firewalls without
explicit zones are zone-redundant by default; in other regions they remain
regional. The `VpnGw2AZ` gateway uses a zone-redundant Standard public IP
declared across zones 1, 2, and 3, as required by the VPN Gateway resource
provider. These are Microsoft-managed platform behaviors, not a template
availability guarantee. See
[Azure Firewall Availability Zones](https://learn.microsoft.com/azure/firewall/deploy-availability-zone-powershell).

## Network values

All CIDRs must be non-overlapping with connected networks. The defaults place
the agent in a `/24` subnet. Microsoft recommends a `/24` agent subnet for
production planning because upgrades and scaling temporarily consume additional
addresses; see the
[Agent networking deep dive](https://learn.microsoft.com/azure/foundry/agents/concepts/agents-networking-deep-dive).

| azd value | Default | Applies to | Purpose |
|---|---|---|---|
| `VNET_ADDRESS_PREFIX` | `10.42.0.0/16` | All | Template-owned VNet address space. |
| `AGENT_SUBNET_PREFIX` | `10.42.0.0/24` | All | Delegated Hosted Agent subnet. |
| `PRIVATE_ENDPOINT_SUBNET_PREFIX` | `10.42.1.0/24` | All | Foundry, Search, and Key Vault private endpoints. |
| `FIREWALL_SUBNET_PREFIX` | `10.42.2.0/26` | All | Azure Firewall subnet. |
| `GATEWAY_SUBNET_PREFIX` | `10.42.3.0/27` | P2S/S2S | VPN Gateway subnet. |
| `DNS_INBOUND_SUBNET_PREFIX` | `10.42.4.0/28` | All | Private DNS Resolver inbound endpoint subnet. |
| `DNS_INBOUND_IP_ADDRESS` | `10.42.4.4` | All | Static resolver inbound address; must belong to the resolver subnet. |
| `P2S_ADDRESS_POOL` | `172.20.0.0/24` | P2S | VPN client address pool. |

## Connectivity-specific values

| azd/process value | Required when | Handling |
|---|---|---|
| `AZURE_TENANT_ID` | P2S | Tenant used for Azure VPN Client sign-in. |
| `S2S_GATEWAY_IP_ADDRESS` | S2S | Public IP of the customer VPN device. |
| `S2S_REMOTE_ADDRESS_PREFIXES` | S2S | JSON array of customer-side prefixes. |
| `S2S_ENABLE_BGP` | S2S | `true` or `false`; default `false`. |
| `S2S_REMOTE_ASN` | S2S with BGP (optional) | Default `65010`. |
| `S2S_BGP_PEERING_ADDRESS` | S2S with BGP | Customer-side BGP peer address. |
| `S2S_SHARED_KEY` | S2S | Secret process environment variable only. Never use `azd env set`, source files, logs, or fixtures. The orchestrator includes only its SHA-256 digest inside the overall infrastructure fingerprint so a rotation forces reconciliation; it does not persist the key or its standalone digest. Remove the key from the process after provisioning. |
| `REMOTE_VNET_RESOURCE_ID` | VNet peering | Canonical ARM ID of the customer-managed VNet, ending at `/providers/Microsoft.Network/virtualNetworks/<name>` with no child path. |

Use the executable [connectivity-mode commands](connectivity.md#deployment-commands)
and replace their placeholders with customer values.

## Existing private ACR values

The ACR workflow uses its own `scenarios/existing-private-acr/azure.yaml` and
requires `azure.ai.agents >= 1.0.0-beta.7`.

| azd value | Required | Constraint |
|---|---|---|
| `AZURE_CONTAINER_REGISTRY_RESOURCE_ID` | Yes | Canonical full ARM ID of the existing enterprise ACR. |
| `AZURE_CONTAINER_REGISTRY_ENDPOINT` | Yes | Exact lowercase Azure public-cloud login server without scheme or path. |
| `AZURE_CONTAINER_IMAGE` | Yes | Lowercase image reference pinned by `@sha256:<digest>`; tags are rejected. |
| `AZD_AGENT_SKIP_ACR` | Yes | Must be `true`; prevents azd from creating or publishing to an ACR. |
| `AZD_AGENT_SKIP_ROLE_ASSIGNMENTS` | Yes | Must be `true`; external ACR IAM remains enterprise-owned. |
| `AZURE_AI_AGENT_PRINCIPAL_ID` | After first Agent creation | Stable per-Agent identity used to validate external pull authorization. |

The unified script sets these values in the scenario azd environment. Follow
[Existing private ACR](existing-private-acr.md); do not combine this scenario
with the default source-deployment workflow.
