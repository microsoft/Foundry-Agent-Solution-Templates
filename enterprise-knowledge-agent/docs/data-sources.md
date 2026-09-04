# Data source placement

Put read-only sources that need unified retrieval, reranking, and citations under `config/knowledge-sources/`. Put source-native tools, business actions, or distinct identity flows under `config/toolbox-tools/`. Exact duplicate names, connections, or normalized endpoints are rejected; semantic duplicates with different identifiers require review. Examples are inert under each `examples/` directory. Copy one into its parent directory only after the external source and any required project connection exist.

- Search and MCP: use native Knowledge Source fragments.
- Web: use the Toolbox `web_search` built-in.
- Fabric IQ: bring a published Fabric item and small synthetic dataset; use a native Knowledge Source for unified grounding or a Toolbox peer for source-native behavior. Validate one known-answer query.
- Work IQ: use a Toolbox peer with delegated user identity. Calendar and Mail examples are provided, but customers must validate them against their Microsoft 365 tenant. Offline fixtures do not prove a live call.
- File Search, OpenAPI, A2A, Code Interpreter, and Browser Automation: add only when the workload requires that distinct capability.

Maintained references: [Foundry Toolbox](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox), [Knowledge sources](https://learn.microsoft.com/azure/search/agentic-knowledge-source-overview), and [Hosted-agent samples](https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/python/hosted-agents).

The synthetic demo Search service/index is the only data source created by this template. All other Search indexes, Fabric items, Work/SharePoint data, MCP servers, APIs, databases, and A2A agents are supplied and retained by the customer. See [data onboarding](data-onboarding.md).
