# Customization

## Use Foundry IQ without a Toolbox

The default template keeps Foundry IQ and Web IQ behind one Toolbox. If the application needs only Knowledge Base grounding, it can connect the Agent directly to the Knowledge Base MCP endpoint. This removes the Toolbox and `web_search`, but it is a source customization that the adopter must maintain.

### 1. Connect the Agent directly

In `src/main.py`, replace `FoundryToolbox` with an `MCPStreamableHTTPTool` authenticated for Azure AI Search. The essential shape is:

```python
import httpx

from agent_framework import Agent, MCPStreamableHTTPTool
from azure.identity import DefaultAzureCredential, get_bearer_token_provider


class SearchTokenAuth(httpx.Auth):
    def __init__(self, token_provider):
        self._token_provider = token_provider

    def auth_flow(self, request):
        request.headers["Authorization"] = f"Bearer {self._token_provider()}"
        yield request


credential = DefaultAzureCredential()
token_provider = get_bearer_token_provider(
    credential,
    "https://search.azure.com/.default",
)
http_client = httpx.AsyncClient(
    auth=SearchTokenAuth(token_provider),
    timeout=120.0,
)
knowledge_base = MCPStreamableHTTPTool(
    name="knowledge_base",
    url=os.environ["KB_MCP_ENDPOINT"],
    http_client=http_client,
    load_prompts=False,
)

agent = Agent(
    client=client,
    tools=knowledge_base,
    instructions=(
        "Use knowledge_base_retrieve for enterprise knowledge and Microsoft "
        "product documentation. Preserve exact HTTPS source URLs and page or "
        "section metadata; do not invent URLs."
    ),
    default_options={"store": False},
)
```

Add `httpx` to `src/requirements.txt`. Keep the existing `FoundryChatClient` and `ResponsesHostServer` setup.

### 2. Pass the Knowledge Base endpoint

In `azure.yaml`, replace the Agent's `TOOLBOX_ENDPOINT` environment variable with:

```yaml
- name: KB_MCP_ENDPOINT
  value: ${KB_MCP_ENDPOINT}
```

The provisioning script already writes `KB_MCP_ENDPOINT` after creating the Knowledge Base.

### 3. Remove Toolbox lifecycle operations

In `scripts/provision.py`, stop calling `configure_toolbox`. Retain Search index, Knowledge Source, Knowledge Base, preflight, and ownership logic. In `scripts/predown.ps1`, remove the Toolbox and project-connection deletion commands; keep `cleanup.py` so template-owned Search objects are removed safely.

The Agent managed identity still needs `Search Index Data Reader` on the Search service. Keep `scripts/postdeploy.ps1`. The direct MCP client requests an Azure AI Search token rather than a Foundry Toolbox token.

### 4. Expected behavior

After `azd up --no-prompt`, enterprise-document and Microsoft Learn questions use `knowledge_base_retrieve` and preserve citations. Web IQ is unavailable because this customization removes `web_search`. During cleanup, template-owned Search objects are removed and customer-owned sources remain.
