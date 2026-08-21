# Cost planning

This template does not publish a fixed monthly price. Azure prices, regions,
API Management tiers, model usage, Hosted Agent session compute, Content Safety
traffic, data transfer, and customer discounts vary. The example below is a
planning baseline, not a quote or a prediction of an adopter's bill.

Use the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
with the intended region and workload, then retain the estimate with the
deployment approval.

## Typical minimal deployment example

As of **August 21, 2026**, a low-usage deployment of the template's default
configuration in **East US** is approximately **USD 160.38 for a 730-hour
month** at Microsoft public retail rates.

The example assumes:

- one Azure API Management Basic v2 unit deployed for 730 hours and fewer than
  10 million API calls;
- 100 aggregate billed Hosted Agent session-hours at 0.5 vCPU and 1 GiB;
- 1 million uncached short-context `gpt-5.6-luna` input tokens and 0.2 million
  output tokens;
- 10,000 aggregate Content Safety text records, representing approximately
  2,000 policy evaluations averaging five records each;
- 10 GB of eligible Internet egress within the first 100 GB allowance.

This estimate covers Azure charges only. It excludes customer discounts, taxes,
additional environments, production monitoring, availability and
disaster-recovery resources, traffic beyond the stated assumptions, and
third-party charges.

| Item | Example calculation | Estimated USD/month |
|---|---:|---:|
| Azure API Management Basic v2 | `730 h × $0.20548/h` | $150.00 |
| **Fixed baseline** | Always-on APIM service above | **$150.00** |
| Hosted Agent session compute | `100 session-h × (0.5 × $0.0994/vCPU-h + 1 × $0.0118/GiB-h)` | $6.15 |
| GPT-5.6 Luna Data Zone inference | `1M input × $0.22/M + 0.2M output × $1.32/M` | $0.48 |
| Azure AI Content Safety | `10K text records × $0.375/1K records` | $3.75 |
| Internet egress | `10 GB within the first 100 GB tier` | $0.00 |
| **Usage subtotal** | Usage-priced items above | **$10.38** |
| **Illustrative total** | `$150.00 fixed + $10.38 usage` | **$160.38** |

Replace every assumption with current rates and measured workload data before
approval.

## Rate details

Rates in this example come from the unauthenticated
[Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices).
USD values are public retail prices without customer discounts.

### Azure API Management

The template deploys one Basic v2 capacity unit. The East US public retail rate
for the first Basic v2 unit is **$0.20548/hour**, or approximately **$150.00 for
730 hours**.

Basic v2 includes the first 10 million calls with no incremental call charge.
The public meter charges **$0.03 per 10,000 calls** after the included quantity.
Verify both rates with the
[API Management retail price query](https://prices.azure.com/api/retail/prices?currencyCode=USD&$filter=serviceName%20eq%20%27API%20Management%27%20and%20armRegionName%20eq%20%27eastus%27%20and%20skuName%20eq%20%27Basic%20v2%27)
and [API Management pricing](https://azure.microsoft.com/pricing/details/api-management/).

### Microsoft Foundry Hosted Agent

The public Hosted Agent compute rates in East US are:

- **$0.0994 per vCPU-hour**;
- **$0.0118 per GiB-hour**.

The template configures 0.5 vCPU and 1 GiB per session. Estimate aggregate
billed session-hours across concurrent sessions and warm idle periods. Hosted
sessions deprovision after their configured idle timeout. See
[Foundry Agent Service pricing](https://azure.microsoft.com/pricing/details/foundry-agent-service/)
and [Hosted Agent session management](https://learn.microsoft.com/azure/foundry/agents/how-to/manage-hosted-sessions).

The corresponding public meter query is
[Foundry Agents Hosted pricing in East US](https://prices.azure.com/api/retail/prices?currencyCode=USD&$filter=productName%20eq%20%27Foundry%20Agents%27%20and%20skuName%20eq%20%27Hosted%27%20and%20armRegionName%20eq%20%27eastus%27).

### GPT-5.6 Luna Data Zone model

Public East US Data Zone Standard rates effective August 1, 2026 are:

| Context band | Input | Cached input | Cache write | Output |
|---|---:|---:|---:|---:|
| Short context | $0.22/M tokens | $0.022/M tokens | $0.275/M tokens | $1.32/M tokens |
| Long context | $0.44/M tokens | $0.044/M tokens | $0.55/M tokens | $1.98/M tokens |

The illustrative estimate assumes uncached short-context traffic. Verify the
context band and current meters with the
[GPT-5.6 Luna Data Zone retail price query](https://prices.azure.com/api/retail/prices?currencyCode=USD&$filter=armRegionName%20eq%20%27eastus%27%20and%20contains(meterName,%20%275.6%20luna%27)%20and%20contains(skuName,%20%27Std%20DZ%27))
and [Azure OpenAI pricing](https://azure.microsoft.com/pricing/details/azure-openai/).

The configured 100 model capacity units allocate quota and throughput for this
Standard deployment. They are not 100 always-on model instances and must not be
multiplied by 730 hours. Billing uses model token consumption. See
[Azure OpenAI quota](https://learn.microsoft.com/azure/foundry/openai/how-to/quota).

### Azure AI Content Safety

The East US Standard text rate is **$0.375 per 1,000 text records**. One text
record contains up to 1,000 Unicode characters, so longer text consumes multiple
records.

The template evaluates content at agent, model, and MCP policy boundaries.
Estimate aggregate metered text records across every inbound and outbound policy
evaluation, not only user requests. Verify the rate with the
[Content Safety retail price query](https://prices.azure.com/api/retail/prices?currencyCode=USD&$filter=productName%20eq%20%27Content%20Safety%27%20and%20skuName%20eq%20%27Standard%27%20and%20armRegionName%20eq%20%27eastus%27),
[Content Safety pricing](https://azure.microsoft.com/pricing/details/content-safety/),
and the [`llm-content-safety` policy reference](https://learn.microsoft.com/azure/api-management/llm-content-safety-policy).

### Foundry, Toolbox, and connections

The Azure Retail Prices API does not expose a separate fixed meter for creating
a Foundry account, project, Toolbox, or connection. Billing comes from the
underlying services and operations, including Hosted Agent compute, model
tokens, Content Safety, and data transfer. See
[Manage costs for Microsoft Foundry](https://learn.microsoft.com/azure/foundry/concepts/manage-costs)
and [Foundry Toolbox](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox).

### Data transfer

For the East US Microsoft global network egress meter, the first 100 GB is
priced at **$0/GB** and the next tier begins at **$0.087/GB**. The 10 GB example
is free only while the billing scope still has allowance available.

Add calculator inputs for Internet egress above the allowance, inter-region or
inter-zone transfer, MCP traffic, and future private networking. See
[Bandwidth pricing](https://azure.microsoft.com/pricing/details/bandwidth/).

## Estimate formula

Use current rates for the selected region and agreement:

`monthly estimate = APIM service hours and excess calls + Hosted Agent billed session compute + model input/output/cache tokens + Content Safety text records + data transfer + optional Azure environments`

The per-user APIM token limits govern traffic but are not an Azure billing cap.
A request can contain multiple model turns, and tool schemas and MCP results
contribute to model token usage.

## Estimate inputs to collect

- Azure region and APIM tier;
- APIM capacity units, deployment hours, and monthly calls;
- concurrent Hosted Agent sessions, idle timeout, and aggregate billed
  session-hours;
- requests per user and model turns per request;
- model context band and average input, output, cached, cache-write,
  tool-schema, and tool-result tokens;
- Content Safety evaluations and aggregate text records;
- MCP call volume and response size;
- Internet, inter-region, and inter-zone data transfer;
- development, test, production, availability, and disaster-recovery
  environments.

## Cost guardrails

- Create Azure Cost Management budgets and alerts for the target subscription or
  resource group.
- Keep APIM authentication, managed identity, TLS validation, Content Safety,
  and governance controls enabled when optimizing cost.
- Right-size APIM, model capacity, and Hosted Agent usage from measured load.
- Review named-value token limits as traffic controls rather than billing
  guarantees.
- Re-run the Azure Pricing Calculator before approval because rates and meters
  can change.
- Run `azd down` for disposable environments after reviewing the resource group
  and linked Foundry/APIM resources.
