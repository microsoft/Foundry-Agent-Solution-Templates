# Data source and tool placement

This guide is the decision point for placing an external capability in the Foundry IQ Knowledge Base or exposing it as a peer tool in Foundry Toolbox. It describes both platform placement options and the narrower set of paths maintained by this template. The default deployment keeps the Knowledge Base and `web_search` behind one Toolbox.

## Choose the responsibility boundary

Use a Knowledge Source when evidence should participate in Knowledge Base query planning, retrieval, reranking, synthesis, and citations with other sources. Use a Toolbox peer tool when the Agent needs an explicit or sequenced call, source-native output, current transactional state, or side effects. A peer tool is also preferable when it needs an independent identity, consent, approval, retry, or failure boundary.

Put maintained Knowledge Source fragments under `config/knowledge-sources/` and maintained peer-tool fragments under `config/toolbox-tools/`. Exact duplicate names, connections, or normalized endpoints are rejected; semantic duplicates with different identifiers require review. Examples are inert under each `examples/` directory. Copy one into its parent directory only after the external source and any required project connection exist.

## Platform placement options

| Placement | Capabilities |
|---|---|
| Foundry IQ Knowledge Source | Blob, SharePoint, OneLake, Azure SQL, and direct File Knowledge Sources |
| Toolbox peer tool | OpenAPI, A2A, Code Interpreter, Browser Automation, transactional APIs, and business actions |
| Either, when supported | Azure AI Search, web grounding, Work IQ, supported Fabric IQ items, and MCP servers |

For a capability that supports either path, select one path for the deployment; the alternatives do not imply duplicate or simultaneous integration. Confirm current service availability, authentication, tenant, region, and network support before choosing a path.

Foundry IQ File Knowledge Source and File Search are different products, not one component moved between layers. Similarly, an indexed projection of a database or CRM and its transactional API are separate interfaces and can have different placements.

## Template defaults and alternatives

The alternative paths below describe platform placement options. Unless a path is explicitly identified as maintained, this template does not include its configuration example.

| Capability | Maintained template path | Choose another supported path when |
|---|---|---|
| Azure AI Search | Knowledge Source; examples cover the synthetic index and a customer-owned index | The Agent needs an explicit index query with direct query controls |
| MCP | Microsoft Learn and the remote read-only MCP example are Knowledge Sources | The MCP server exposes explicit tasks, actions, source-native responses, or independent operational controls |
| Web grounding | Toolbox `web_search` built-in | Web results must contribute evidence to one cross-source grounded answer and the selected Knowledge Source integration is supported |
| Fabric IQ | Knowledge Source example | Source-native behavior or independent controls require a Toolbox peer |
| Work IQ | Toolbox peer examples using delegated user identity | Results must participate in unified Knowledge Base retrieval and the tenant supports the required Knowledge Source integration |
| File content | Customer-owned Search index for unified retrieval and citations | A distinct File Search experience is required; File Search is not interchangeable with a Foundry IQ File Knowledge Source |
| OpenAPI, A2A, Code Interpreter, and Browser Automation | Toolbox peer examples are provided for OpenAPI and A2A | Add only the distinct capability required by the workload; Code Interpreter and Browser Automation do not have maintained examples here |

Fabric IQ requires a published Fabric item. Work IQ Calendar and Mail require delegated user identity and the applicable Microsoft 365 tenant configuration. When selecting an optional capability, account for identity, freshness, regional and network availability, release status, and failure isolation.

Maintained references: [Foundry Toolbox](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox), [Knowledge sources](https://learn.microsoft.com/azure/search/agentic-knowledge-source-overview), and [Hosted-agent samples](https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/python/hosted-agents).

The synthetic demo Search service/index is the only data source created by this template. All other Search indexes, Fabric items, Work/SharePoint data, MCP servers, APIs, databases, and A2A agents are supplied and retained by the customer. See [data onboarding](data-onboarding.md) for implementation steps.

## Integration support matrix

The following paths have been validated with deployed services. Terraform and Bicep both support the template infrastructure; the table focuses on runtime data flow.

| Data or capability | Validated runtime path | Verified behavior |
|---|---|---|
| Synthetic enterprise content | Hosted Agent → Toolbox → Foundry IQ Knowledge Base → Azure AI Search index | Retrieves enterprise content with its source URL. |
| Customer-owned documents, such as PDF and Word files | Existing customer-owned Azure AI Search index → Search Knowledge Source → Foundry IQ Knowledge Base | Retrieves indexed document content with URL, page, section, file name, and file type metadata. |
| Microsoft product documentation | Hosted Agent → Toolbox → Foundry IQ Knowledge Base → Microsoft Learn MCP Knowledge Source | Produces a grounded answer with Microsoft Learn citations. |
| Custom read-only MCP content | Foundry IQ Knowledge Base → custom MCP Knowledge Source | Returns grounded content with an HTTPS URL, reference metadata, and source data. |
| Current public information | Hosted Agent → Toolbox → Web IQ | Returns current information with an HTTPS citation. |
| Microsoft 365 content through Work IQ | Hosted Agent → Toolbox → Work IQ using the calling user's identity | Executes user-scoped read operations successfully; Mail and Calendar were validated as representative examples. |
| Organizational API | Foundry Toolbox → OpenAPI service | Invokes a constrained API and returns structured results. |
| Database-backed business data | Hosted Agent → Toolbox → constrained OpenAPI service → database | Retrieves selected database content and preserves its source URL. |

For the customer-owned document path above, the customer is responsible for file storage, OCR, text extraction, chunking, synchronization, and indexing. Those ingestion steps are outside this template. The template connects an existing, retrieval-ready Azure AI Search index to the Knowledge Base.

The following supported extension paths have not yet been fully validated end to end in this template:

- Fabric Ontology as a Knowledge Source.
- Native database Knowledge Sources such as Azure SQL or OneLake. Database access through a constrained OpenAPI service is validated.
- SharePoint or other Microsoft 365 content composed inside a Knowledge Base. Work IQ through Toolbox peer tools is validated.
- Customer MCP Knowledge Sources that require authentication. Custom read-only MCP grounding is validated.
- Direct Hosted Agent → Knowledge Base connectivity without Toolbox.
- A2A used as a grounding path. A2A delegation through Toolbox is a separate optional capability.
