# Cost planning

This template does not have a fixed monthly price. As of **September 4, 2026**, a low-usage deployment of the default configuration is approximately **USD 82 per 730-hour month** at Azure public retail rates. This is a planning example, not a quote.

The estimate assumes one Azure AI Search Basic unit in West US 2, 100 aggregate Hosted Agent session-hours at 0.5 vCPU and 1 GiB, 1 million `gpt-5.4-mini` Global Standard input tokens, 0.2 million output tokens, and 100 Web IQ searches. Model tokens include both Agent and Knowledge Base activity.

| Item | Example calculation | Estimated USD/month |
|---|---:|---:|
| Azure AI Search Basic | `730 h × $0.10/h` | $73.00 |
| Hosted Agent session compute | `100 h × (0.5 × $0.10 + 1 × $0.01)` | $6.00 |
| GPT-5.4 mini Global Standard | `1M input × $0.75/M + 0.2M output × $4.50/M` | $1.65 |
| Web IQ / Grounding with Bing | `100 searches × $14/1,000` | $1.40 |
| **Illustrative total** | | **$82.05 (about $82)** |

Azure AI Search is the main always-on cost. Agent compute, model tokens, and Web IQ are usage based. The estimate excludes taxes, customer discounts, data transfer, additional environments, monitoring, availability resources, and customer-owned Search, Fabric, Microsoft 365, APIs, MCP servers, databases, or remote agents.

With `AZURE_SEARCH_MODE=byo`, this template does not create or delete the existing Search service, but that service continues to incur charges on its owning billing scope. Model capacity allocates quota and does not represent continuously running model instances.

Use the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) with the intended regions and workload before deployment. Remove disposable environments with `azd down --purge --force`.

Official references: [Microsoft Foundry pricing](https://azure.microsoft.com/pricing/details/microsoft-foundry/), [Foundry Agent Service pricing](https://azure.microsoft.com/pricing/details/foundry-agent-service/), [Azure OpenAI pricing](https://azure.microsoft.com/pricing/details/azure-openai/), [Azure AI Search pricing](https://azure.microsoft.com/pricing/details/search/), and the [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices).
