# Bring your own enterprise data

The template creates only its small synthetic Search demo. Customer data sources must already exist and remain customer-owned. Choose a route below, copy the matching example into its parent directory, set every referenced azd environment value, and rerun `azd up --no-prompt`.

| Data and authorization need | Route | Example |
|---|---|---|
| PDF/Word with unified retrieval and citations | Customer Search index → Knowledge Base | `config/knowledge-sources/examples/search-index.example.yaml` |
| Read-only MCP grounding | MCP Knowledge Source | `config/knowledge-sources/examples/remote-mcp.example.yaml` |
| Published Fabric ontology | Fabric Knowledge Source | `config/knowledge-sources/examples/fabric-iq.example.yaml` |
| Per-user Microsoft 365 permissions | Work IQ Toolbox peer | `config/toolbox-tools/examples/work-iq-*.example.yaml` |
| Existing business API or agent | Toolbox peer | `openapi.example.yaml` or `a2a.example.yaml` |

Activation never authorizes this template to provision, populate, migrate, synchronize, or delete the referenced system. Use a unique filename such as `30-customer-documents.yaml`; numeric prefixes only control deterministic order.

## PDF and Word collections

Files are not searchable merely because they are copied into the agent folder. Ingest, extract, and chunk them into a customer-owned Azure AI Search index first. Recommended retrievable fields are `document_id`, `title`, `content`, `source_url`, `page_number`, `section`, `last_modified`, and access-control metadata. Configure a semantic configuration over title and content.

```powershell
azd env set AZURE_SEARCH_MODE byo
azd env set AZURE_SEARCH_ENDPOINT https://<search-name>.search.windows.net
azd env set AZURE_SEARCH_SERVICE_ID /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Search/searchServices/<search-name>
azd env set CUSTOMER_SEARCH_INDEX_NAME <index-name>
azd env set CUSTOMER_SEARCH_SEMANTIC_CONFIG <semantic-config-name>
Copy-Item config/knowledge-sources/examples/search-index.example.yaml config/knowledge-sources/30-customer-documents.yaml
azd up --no-prompt
```

Confirm the index contains a non-sensitive known fact such as `DOC-VERIFY-2026`. Ask for that fact and require its source URL and page/section. A 404 indicates the wrong Search service/index; missing citations usually indicate non-retrievable citation fields or incorrect `sourceDataFields`. The customer Search managed identity needs model invocation permission, while the provisioning user and Hosted Agent identity need appropriate Search roles. The template does not change customer-owned RBAC.

## SharePoint libraries

| Requirement | Route |
|---|---|
| Enforce the signed-in user's current Microsoft 365 permissions | Work IQ or supported SharePoint grounding through a Toolbox peer |
| Unified reranking and citations across sources | Customer-managed SharePoint synchronization into Search, then the Search-index placeholder |

Keep synchronization and ACL mapping outside this template. Use a harmless known document title for manual validation. A response that ignores user permissions is not proof of a correct delegated path. Cleanup preserves the SharePoint site, library, synchronized index, and customer connection.

## Work IQ placeholders

The template provides inactive Mail and Calendar examples but does not create Microsoft 365 data, grant permissions, assign licenses, or claim live Work IQ validation. The caller needs delegated user identity, tenant-policy access, and Microsoft 365 Copilot Business Chat.

```powershell
azd ai connection create workiq-calendar-conn --kind remote-tool --target https://agent365.svc.cloud.microsoft/agents/servers/mcp_CalendarTools --auth-type user-entra-token --audience ea9ffc3e-8a23-4a7d-836d-234d7c7565c1
azd ai connection create workiq-mail-conn --kind remote-tool --target https://agent365.svc.cloud.microsoft/agents/servers/mcp_MailTools --auth-type user-entra-token --audience ea9ffc3e-8a23-4a7d-836d-234d7c7565c1
azd env set WORKIQ_CALENDAR_CONNECTION_NAME workiq-calendar-conn
azd env set WORKIQ_MAIL_CONNECTION_NAME workiq-mail-conn
```

Copy only the required examples into `config/toolbox-tools/`. Preflight confirms each connection exists. Static validation covers shape, substitution, default exclusion, duplicate detection, and digest participation. Validate live Mail or Calendar access through a user-authenticated Microsoft 365 channel before production use.

## Databases, APIs, MCP, and A2A

Do not give the model unrestricted database credentials or arbitrary SQL execution. Expose an approved least-privilege API or MCP server. Actions and source-native operations belong in Toolbox; citation-oriented read-only MCP retrieval can be composed into the Knowledge Base. Existing agents can be exposed through optional A2A.

Verify endpoint reachability and minimal authentication scopes. Document allowed operations, timeouts, retries, data boundaries, and audit expectations. Seed a non-sensitive known response such as `API-VERIFY-2026`, invoke that operation, and confirm its tool name and result. Cleanup preserves customer APIs, MCP servers, databases, A2A agents, and connections.
