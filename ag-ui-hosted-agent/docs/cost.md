# Cost planning

This template does not have a fixed monthly price. As of **November 14, 2026**, a
low-usage deployment of the default configuration is approximately **USD 18 per
730-hour month** at Azure public retail rates in East US 2. This is a planning
example, not a quote.

The estimate assumes:
- 100 active hours each for the web app and the gateway, at 0.5 vCPU and 1 GiB;
- 100 aggregate Hosted Agent session-hours at 0.5 vCPU and 1 GiB;
- 1 million `gpt-5.4-mini` Global Standard input tokens and 0.2 million output tokens.

| Item | Example calculation | Estimated USD/month |
|---|---:|---:|
| Azure Container Registry Basic | `730 h × $0.1666/day ÷ 24` | $5.07 |
| Container Apps vCPU (after the monthly free grant of 180,000 vCPU-seconds) | `(360,000 − 180,000) vCPU-s × $0.000024` | $4.32 |
| Container Apps memory (after the monthly free grant of 360,000 GiB-seconds) | `(720,000 − 360,000) GiB-s × $0.000003` | $1.08 |
| Hosted Agent session compute | `100 h × (0.5 × $0.10 + 1 × $0.01)` | $6.00 |
| GPT-5.4 mini Global Standard | `1M input × $0.75/M + 0.2M output × $4.50/M` | $1.65 |
| **Illustrative total** | | **$18.12 (about $18)** |

The container registry is the only always-on cost. Both container apps scale to
zero when idle, so they cost nothing between conversations, but the first
request after an idle period waits for a cold start. The Container Apps free
grant applies once per subscription. Other apps in the same subscription use
it too.

The estimate excludes taxes, customer discounts, data transfer, additional
environments, and the Application Insights and Log Analytics ingestion the
Foundry layer enables for tracing.

Use the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
with the intended region and workload before deployment. Remove disposable
environments with `azd down --purge`, then delete the app registration (see the
README).

Official references: [Foundry Agent Service pricing](https://azure.microsoft.com/pricing/details/foundry-agent-service/),
[Azure OpenAI pricing](https://azure.microsoft.com/pricing/details/azure-openai/),
[Azure Container Apps pricing](https://azure.microsoft.com/pricing/details/container-apps/),
[Azure Container Registry pricing](https://azure.microsoft.com/pricing/details/container-registry/),
and the [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices).
