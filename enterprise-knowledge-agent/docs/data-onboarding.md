# Bring your own enterprise data

The template includes a small sample Search index. All other data sources must already exist and remain customer-owned. First use [Data source and tool placement](data-sources.md) to choose between a Knowledge Source and a Toolbox tool, then follow the applicable section below. The included examples cover the following integration paths.

| Data and authorization need | Route | Example |
|---|---|---|
| PDF/Word with unified retrieval and citations | Customer Search index → Knowledge Base | `config/knowledge-sources/examples/search-index.example.yaml` |
| Read-only MCP grounding | MCP Knowledge Source | `config/knowledge-sources/examples/remote-mcp.example.yaml` |
| Published Fabric ontology | Fabric Knowledge Source | `config/knowledge-sources/examples/fabric-iq.example.yaml` |
| Per-user Microsoft 365 permissions | Work IQ Toolbox peer | `config/toolbox-tools/examples/work-iq-*.example.yaml` |
| Existing business API or agent | Toolbox peer | `config/toolbox-tools/examples/openapi.example.yaml` or `config/toolbox-tools/examples/a2a.example.yaml` |

Copy the selected example into its parent directory, give it a unique filename such as `30-customer-documents.yaml`, and set every environment value referenced by the file. Numeric prefixes control configuration order only. Adding a configuration file does not authorize the template to provision, populate, migrate, synchronize, or delete the external system.

## PDF and Word collections

PDF and Word files must be ingested, extracted, and chunked into a customer-owned Azure AI Search index before the agent can search them. Recommended retrievable fields are `document_id`, `title`, `content`, `source_url`, `page_number`, `section`, `last_modified`, and access-control metadata. Configure a semantic configuration over title and content.

Select the Terraform or Bicep manifest and create a **new** azd environment by following the README, but stop before `azd provision` or `azd up`. Do not convert an existing demo environment to BYO because its infrastructure and cleanup records refer to the demo Search service.

Before provisioning, have the Search owner confirm that the service supports semantic and agentic retrieval, has a system-assigned managed identity, and accepts Microsoft Entra data-plane authentication. The deploying identity needs **Search Service Contributor** and **Search Index Data Contributor** on that service so the template can create its Search objects and upload the sample data. BYO mode does not grant these roles.

The Search-index example expects searchable `content` and retrievable `document_id`, `title`, `source_url`, and `page_number` fields. Update the copied file to match your index schema. During provisioning, the template verifies the configured semantic configuration and fields before creating its Search objects.

BYO mode reuses the Search service, not the customer index. The template creates a separate, environment-scoped sample index, Knowledge Sources, and Knowledge Base. It does not upload data to or take ownership of the customer index.

```powershell
azd env set AZURE_SEARCH_MODE byo
azd env set AZURE_SEARCH_ENDPOINT https://<search-name>.search.windows.net
azd env set AZURE_SEARCH_SERVICE_ID /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Search/searchServices/<search-name>
azd env set CUSTOMER_SEARCH_INDEX_NAME <index-name>
azd env set CUSTOMER_SEARCH_SEMANTIC_CONFIG <semantic-config-name>
Copy-Item config/knowledge-sources/examples/search-index.example.yaml config/knowledge-sources/30-customer-documents.yaml
azd provision --no-prompt
```

After `azd provision`, grant the customer Search service's managed identity the
**Cognitive Services User** role on the Foundry account that hosts the Knowledge
Base model:

```powershell
$searchId = (azd env get-value AZURE_SEARCH_SERVICE_ID).Trim()
$searchPrincipalId = az search service show --ids $searchId --query identity.principalId --output tsv
$subscriptionId = (azd env get-value AZURE_SUBSCRIPTION_ID).Trim()
$foundryResourceGroup = (azd env get-value AZURE_FOUNDRY_RESOURCE_GROUP).Trim()
$accountName = (azd env get-value AZURE_AI_ACCOUNT_NAME).Trim()
$accountId = "/subscriptions/$subscriptionId/resourceGroups/$foundryResourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName"
az role assignment create --assignee-object-id $searchPrincipalId --assignee-principal-type ServicePrincipal --role "Cognitive Services User" --scope $accountId
```

Deploy the agent after this role assignment is complete:

```powershell
azd deploy --no-prompt
```

The Hosted Agent identity also needs **Search Index Data Reader** on the customer
Search service. If this role is missing, `azd deploy` prints the exact
`az role assignment create` command and stops. Have the Search owner run that
command, then rerun `azd deploy --no-prompt`.

These customer-owned role assignments are not created by Terraform or Bicep in
BYO mode.

For cleanup, select the same manifest and azd environment used for deployment.
Preserve `.azure/<environment-name>/enterprise-knowledge-ownership.json`; it records
which Search objects the environment may delete. If deployment or cleanup fails,
resolve the reported error and rerun the command. Do not edit or recreate this file
manually on a shared Search service.

Template-created indexes, Knowledge Sources, and Knowledge Bases use stable names
scoped to `AZURE_ENV_NAME`. Multiple environments can therefore use the same
customer Search service without overwriting each other's retrieval configuration.
Customer index names and contents are never renamed or owned by the template.

A 404 usually indicates the wrong Search service or index. Missing citations usually indicate non-retrievable citation fields or incorrect `sourceDataFields`.

## SharePoint libraries

| Requirement | Route |
|---|---|
| Enforce the signed-in user's current Microsoft 365 permissions | Work IQ through a Toolbox peer; the included examples cover Mail and Calendar |
| Unified reranking and citations across sources | A supported SharePoint Knowledge Source, or customer-managed SharePoint synchronization into Search; this template provides only the Search-index example |

Keep synchronization and ACL mapping outside this template. Responses must honor the signed-in user's permissions. Cleanup preserves the SharePoint site, library, synchronized index, and customer connection.

## Work IQ placeholders

The template provides inactive Mail and Calendar examples but does not create Microsoft 365 data, grant permissions, or assign licenses. The caller needs delegated user identity, tenant-policy access, and Microsoft 365 Copilot Business Chat.

```powershell
azd ai connection create workiq-calendar-conn --kind remote-tool --target https://agent365.svc.cloud.microsoft/agents/servers/mcp_CalendarTools --auth-type user-entra-token --audience ea9ffc3e-8a23-4a7d-836d-234d7c7565c1
azd ai connection create workiq-mail-conn --kind remote-tool --target https://agent365.svc.cloud.microsoft/agents/servers/mcp_MailTools --auth-type user-entra-token --audience ea9ffc3e-8a23-4a7d-836d-234d7c7565c1
azd env set WORKIQ_CALENDAR_CONNECTION_NAME workiq-calendar-conn
azd env set WORKIQ_MAIL_CONNECTION_NAME workiq-mail-conn
```

Copy only the required examples into `config/toolbox-tools/`. During provisioning, the template confirms that each referenced project connection exists. Mail and Calendar access must use a user-authenticated Microsoft 365 channel.

## Databases, APIs, MCP, and A2A

Do not give the model unrestricted database credentials or arbitrary SQL execution. Expose an approved least-privilege API or MCP server. Actions and source-native operations belong in Toolbox; citation-oriented read-only MCP retrieval can be composed into the Knowledge Base. Existing agents can be exposed through optional A2A.

Use reachable endpoints and minimal authentication scopes. Document allowed operations, timeouts, retries, data boundaries, and audit expectations. Cleanup preserves customer APIs, MCP servers, databases, A2A agents, and connections.

For the remote MCP example, set `CUSTOMER_MCP_ENDPOINT` to an HTTPS Streamable
HTTP endpoint and `CUSTOMER_MCP_TOOL_NAME` to an advertised read-only tool. The
example does not configure authentication. Ensure the endpoint is reachable from
Azure AI Search and use a separate authenticated integration when the server does
not allow anonymous access.
