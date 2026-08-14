# Cost planning

This template does not publish a fixed monthly price. Azure prices, regions,
model usage, Hosted Agent compute, network traffic, retention, and customer
discounts vary. The example below is a planning baseline, not a quote or a
prediction of an adopter's bill.

Use the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
with the intended region and workload, then retain the estimate with the
production approval.

## Typical minimal deployment example

As of **August 7, 2026**, a low-usage deployment of the template's default
point-to-site configuration in **West US 3** is approximately **USD 1,603 for a
730-hour month** at Microsoft public retail rates. This example uses one Azure
Firewall Standard, one `VpnGw2AZ` gateway, one DNS Private Resolver inbound
endpoint, one Azure AI Search Basic search unit (one replica by one partition),
three Private Endpoints, five Private DNS zones, two Standard IPv4 public IP
addresses, and Hosted Agent sessions sized at 0.5 vCPU and 1 GiB. It assumes
100 aggregate active Agent session-hours, 1 million GPT-5.1 input tokens,
0.2 million output tokens, 10 GB processed by the Firewall, 10 GB in and 10 GB
out through Private Link, 1 million private DNS queries, and 10,000 Key Vault
operations. It excludes discounts, taxes, Internet or inter-region egress,
optional enterprise ACR costs, production monitoring, and adopter-owned
connectivity or availability resources.

| Item | Example calculation | Estimated USD/month |
|---|---:|---:|
| Azure Firewall Standard | `1 × 730 h × $1.25/h` | $912.50 |
| VPN Gateway `VpnGw2AZ` | `1 × 730 h × $0.54/h` | $394.20 |
| DNS Private Resolver inbound endpoint | `1 × $180/month` | $180.00 |
| Azure AI Search Basic | `1 search unit × 730 h × $0.101/h` | $73.73 |
| Private Endpoints | `3 × 730 h × $0.01/h` | $21.90 |
| Standard IPv4 public IP addresses | `2 × 730 h × $0.005/h` | $7.30 |
| Private DNS zones | `5 × $0.50/month` | $2.50 |
| **Fixed baseline** | Always-on resources above | **$1,592.13** |
| Hosted Agent session compute | `100 aggregate active session-h × (0.5 × $0.0994/vCPU-h + 1 × $0.0118/GiB-h)` | $6.15 |
| GPT-5.1 Standard inference | `1M input × $1.375/M + 0.2M output × $11/M` | $3.58 |
| Firewall data processing | `10 GB × $0.016/GB` | $0.16 |
| Private Link data processing | `10 GB in × $0.004/GB + 10 GB out × $0.006/GB` | $0.10 |
| Private DNS queries | `1M × $0.40/M` | $0.40 |
| Key Vault operations | `10,000 × $0.03/10,000` | $0.03 |
| **Example usage subtotal** | Usage-priced items above | **$10.42** |
| **Illustrative total** | `$1,592.13 fixed + $10.42 usage` | **$1,602.55 (about $1,603)** |

To replace the assumptions, use this monthly formula with current rates for the
chosen region and agreement:

`monthly estimate = always-on resource hours + Agent active session compute + model input/output tokens + Firewall/Private Link/DNS/Key Vault usage + data transfer + optional resources`

Hosted Agents scale per session rather than by a configured replica count, so
use the sum of active session-hours across concurrent sessions. The template's
`AZURE_AI_MODEL_CAPACITY=10` is Regional Standard quota/capacity allocation; it
does not create ten always-on model instances. Regional Standard inference is
usage-priced, so replace the example token quantities and rates rather than
multiplying model capacity by 730 hours. For P2S or S2S, retain the VPN Gateway;
for VNet peering, remove the VPN Gateway and its public IP and add peering data
charges.

Rates above were retrieved from the unauthenticated
[Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices).
Microsoft documents that USD values from this API are public retail prices
without customer discounts. Re-run the estimate in the Azure Pricing Calculator
before approval because prices and meters can change.

## Cost components

| Component | Applies when | Main cost drivers |
|---|---|---|
| Microsoft Foundry Hosted Agent | All | Container compute, active sessions, inference calls, and tool usage. See [Foundry pricing](https://azure.microsoft.com/pricing/details/microsoft-foundry/) and [Hosted Agent overview](https://learn.microsoft.com/azure/foundry/agents/overview). |
| Model deployment | All | Model, regional deployment type, input/output tokens, provisioned capacity or pay-as-you-go usage. |
| Azure Firewall Standard | All | Fixed deployment cost plus processed data. |
| VPN Gateway `VpnGw2AZ` | P2S or S2S | Gateway time and data transfer. VNet peering does not deploy this gateway. |
| Private DNS Resolver | All | Inbound endpoint and DNS query volume. |
| Azure AI Search Basic | All | Search service hours, replicas, partitions, and optional features. |
| Private Endpoints | All | Endpoint hours and processed data. |
| Key Vault | All | Key operations, key versions, and retained protected resources. |
| Public IP addresses | Firewall and VPN modes | Allocated Standard public IP resources. |
| Existing Premium ACR | Optional ACR scenario | Enterprise-owned registry, storage, transfer, Private Endpoint, pipeline, and image retention. |

Official price pages:

- [Azure Firewall](https://azure.microsoft.com/pricing/details/azure-firewall/)
- [VPN Gateway](https://azure.microsoft.com/pricing/details/vpn-gateway/)
- [Azure DNS Private Resolver](https://azure.microsoft.com/pricing/details/dns/)
- [Azure AI Search](https://azure.microsoft.com/pricing/details/search/)
- [Azure Private Link](https://azure.microsoft.com/pricing/details/private-link/)
- [Key Vault](https://azure.microsoft.com/pricing/details/key-vault/)
- [Azure Container Registry](https://azure.microsoft.com/pricing/details/container-registry/)
- [Azure OpenAI models](https://azure.microsoft.com/pricing/details/cognitive-services/openai-service/)

## Estimate inputs to collect

- Azure region and connectivity mode;
- expected concurrent sessions, requests, input/output tokens, and session
  duration;
- model deployment type and quota;
- Search document count, index size, query rate, replicas, and partitions;
- ingress/egress and private endpoint data volume;
- retention period for Agent sessions, Search indexes, images, and keys;
- availability and DR resources;
- optional monitoring volume and retention when a production design adds it;
- optional enterprise ACR storage and build pipeline.

## Cost guardrails

Security controls are not optional cost switches. Do not reduce cost by enabling
public access, local authentication, mutable image tags, or bypassing the
Firewall. Use an approved connectivity mode, right-size from measured load, and
remove only resources owned by the template.

Review [Operations](operations.md) before deployment and agree on inventory,
budget alerts outside this template, and teardown ownership.
