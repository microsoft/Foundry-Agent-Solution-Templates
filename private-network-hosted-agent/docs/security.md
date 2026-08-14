# Security controls and claim boundary

This document distinguishes controls implemented by the template from Microsoft
platform capabilities and customer responsibilities. It is not a compliance
attestation or a workload-specific threat model.

## Preventive controls

- Foundry, Search, and Key Vault public network access disabled.
- Foundry/Search local key authentication disabled.
- Private endpoints and linked private DNS zones.
- Agent-subnet default route to Azure Firewall with no broad allow-all rule.
- Separate Foundry/Search CMKs with service-specific key roles and the Foundry
  account and project vault roles required for Hosted Agent creation.
- Dedicated runtime identity and query-only Search role.
- Non-sensitive sample Search data in `demo-data/search-documents.json`. The
  sample code does not implement customer data ingestion, file upload, or
  application-managed persistent storage. Conversation and session history are
  platform-managed data.
- Optional enterprise ACR requires Premium, disabled public/admin/anonymous
  access, approved Private Link, digest pinning, and externally managed
  least-privilege pull authorization for the selected repository.

## Deliberate exceptions

- Agent-subnet TCP/443 egress through Azure Firewall is limited to the
  `AzureActiveDirectory` service tag, `mcr.microsoft.com`,
  `*.login.microsoft.com`, and the active Azure cloud login host. These support
  managed-identity token acquisition and source-code Agent provisioning.
- Operator authentication and Azure control-plane operations originate outside
  the solution VNet and do not traverse its Firewall.
- Foundry/Search CMK key access requires Key Vault trusted-services bypass.
- The template has no centralized monitoring or diagnostic retention.

## Shared responsibility

| Party | Responsibility in this solution |
|---|---|
| Template | Deploy the documented Bicep topology, fail-closed network/authentication defaults, least-privilege baseline roles, sample Agent, and validation scripts. |
| Microsoft | Operate Azure and Foundry platform capabilities according to current product documentation and contractual terms. |
| Adopter | Threat model, user/document authorization, data lifecycle, responsible AI, monitoring, incident response, capacity, availability, DR, compliance, and secure customization. |

The template uses Responses protocol 2.0. Caller and session isolation are
platform-owned capabilities, not controls implemented by the template. Direct
Microsoft Entra callers are isolated by identity; this template does not
implement delegated end-user identity. See
[Isolate hosted agent sessions per user](https://learn.microsoft.com/azure/foundry/agents/how-to/isolate-sessions-per-user).

Microsoft's current sources include:

- [Hosted Agent identity and isolation](https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agents)
- [Foundry network isolation](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks)
- [Foundry RBAC](https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry)
- [Agent data privacy and security](https://learn.microsoft.com/azure/foundry/responsible-ai/agents/data-privacy-security)
- [Foundry encryption](https://learn.microsoft.com/azure/foundry/concepts/encryption-keys-portal)
- [Azure AI Search security](https://learn.microsoft.com/azure/search/search-security-built-in)

## Threat considerations

| Threat | Template mitigation | Residual customer responsibility |
|---|---|---|
| Public data-plane exposure | PNA disabled, Private Link, private DNS, and validation that rejects public resolution/access. | Govern connected networks, endpoints, proxies, and DNS. |
| Credential leakage | Managed identities, local auth disabled, no committed secrets, ephemeral S2S key input. | Protect operator sessions, CI federation, support evidence, and customer secrets. |
| Excess privilege | Dedicated Agent identity and query-only Search role; consumer role for invocation. | Access reviews, document-level authorization, group lifecycle, and custom-tool permissions. |
| Data exfiltration by retrieved instructions | Retrieved text is treated as data; Agent egress is restricted. | Use-case prompt-injection tests, output controls, data minimization, and authorization filters. |
| Key loss or revocation | Purge protection, separate CMKs, service-specific cryptographic roles. | Rotation, recovery, escrow, separation of duties, and tested key incident procedures. |
| Dependency outage or regional failure | Fail-closed behavior prevents public fallback. | Availability design, RTO/RPO, backup, DR, and user-facing degradation strategy. |
| Supply-chain compromise | Exact-version Python dependency pins for the default remote source build; digest-pinned existing ACR image. | Dependency scanning, trusted build pipeline, signing/attestation, and promotion policy. |

## Security and compliance review matrix

These are intentional, reviewable exceptions to the private data-plane
boundary. They are not public fallback paths.

| Flow | Source | Destination | Protocol | Reason and lifecycle | Information carried | Enforcement |
|---|---|---|---|---|---|---|
| VPN transport | Azure VPN Client or customer VPN device | VPN Gateway public IP | OpenVPN over TLS for P2S; IPsec/IKE for S2S | Establish the encrypted caller-to-VNet tunnel; present only in P2S/S2S modes | Encrypted tunnel packets | VPN Gateway configuration; no gateway or public IP is deployed for peering |
| P2S user authentication | Azure VPN Client | Microsoft Entra endpoints | HTTPS 443 | Authenticate the human VPN user; P2S only and separate from tunnel transport | Interactive authentication and OAuth tokens | Customer workstation, proxy, Conditional Access, and endpoint-security controls |
| Managed identity authentication | Hosted Agent subnet | `AzureActiveDirectory` service tag, `*.login.microsoft.com`, and the active Azure cloud login host | TCP/HTTPS 443 | Obtain Microsoft Entra tokens during provisioning and runtime | OAuth requests and tokens; not prompts, Search documents, or CMK material | Agent-subnet `0.0.0.0/0` UDR through Azure Firewall; service-tag and FQDN allowlist |
| Source-code provisioning | Hosted Agent subnet | `mcr.microsoft.com` | HTTPS 443 | Retrieve Microsoft runtime/build artifacts when source-code Agent versions are provisioned or updated | Microsoft-hosted build/runtime artifacts; no general web browsing | Azure Firewall application rule restricted to the named FQDN |
| Operator authentication | Administrator/test workstation | Microsoft Entra endpoints | HTTPS 443 | Authenticate `az` and `azd`; independent of P2S authentication | Interactive authentication and OAuth tokens | Customer workstation, proxy, Conditional Access, and endpoint-security controls |
| Azure management plane | Administrator workstation or approved CI identity | Azure Resource Manager | HTTPS 443 | Provision resources, inspect ARM deployments, and manage RBAC | Resource configuration and deployment metadata | Azure RBAC, TLS, customer egress policy, and Azure control-plane audit records |
| Private application data plane | Approved caller or Hosted Agent | Foundry account/project and Azure AI Search private endpoint IPs | HTTPS 443 | Upload Agent source, manage/invoke Agent versions, query private Search data, and invoke the account-scoped model through the project endpoint | Packaged Agent source, prompts/responses, and Search queries/results | VPN/approved private path, private DNS, Private Link, PNA disabled, local auth disabled, Entra RBAC |
| CMK trusted-service access | Service-managed Foundry and Search control planes | Key Vault | HTTPS 443 | Perform required wrap, unwrap, and key metadata operations while CMKs are configured | Cryptographic operations; no key material leaves Key Vault | Key Vault `AzureServices` bypass, service-specific key roles, and the required Foundry account and project vault roles; PNA remains disabled |
| Optional private image pull | Foundry Hosted Agent platform | Enterprise ACR private endpoint | HTTPS 443 | Pull the exact pre-built Agent image selected by digest | Docker distribution schema 2 manifest and layers | `privatelink.azurecr.io`, PNA/admin/anonymous access disabled, managed identity, `AcrPull` or ABAC repository reader |
| Unapproved Internet | Hosted Agent subnet | Any destination not listed above | Any | No approved purpose | None expected | Denied by Azure Firewall default behavior |

The Firewall public IP is an outbound SNAT surface in this template, not an
application ingress surface: no DNAT rules are defined. The VPN Gateway public
IP is intentionally reachable only as the managed VPN tunnel endpoint. These
two public IP resources are unrelated to each other and to the P2S Entra
authentication flow.

Reviewers should validate the effective Firewall Policy against
`infra/modules/network.bicep`, confirm public network access remains disabled on
Foundry, Search, and Key Vault, and retain evidence from
`scripts/validate-network.ps1` and `scripts/validate-all.ps1`.

Do not claim that all traffic stays in the VNet, that every platform data store
is CMK-covered, or that an authorized agent cannot disclose data it is allowed
to read.

Foundry account/project and Search application data-plane traffic, approved
operator access to the Key Vault data plane, and optional enterprise ACR image
pulls use private endpoints. The account-scoped model is invoked through the
project endpoint. Service-managed Foundry and Search CMK operations instead use
the Key Vault `AzureServices` trusted-services bypass and are not claimed to
traverse the template VNet. The public exceptions do not provide a public
client data-plane fallback.
See [Architecture: Traffic outside the VNet](architecture.md#traffic-outside-the-vnet)
for the exact paths and reasons.
