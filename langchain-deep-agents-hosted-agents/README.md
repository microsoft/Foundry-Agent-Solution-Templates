# Deep Agent

Deep Agent adapts LangChain's official [Build a deep research agent](https://docs.langchain.com/oss/python/deepagents/deep-research) tutorial to Microsoft Foundry hosting. The research workflow follows the tutorial, while the model, web search, durable checkpointing, and Responses protocol server use Microsoft Foundry.

## TODO:
- Tracing
- Convert to a more specific scenario
- APIM

## What the sample demonstrates

- Planning research with `TodoListMiddleware` and state-backed files.
- Delegating focused topics to a single `research-agent` subagent type.
- Discovering current sources with the managed `web_search` tool in a Foundry Toolbox.
- Running approved terminal commands through PowerShell during local Windows development and the native shell in the hosted Linux runtime.
- Producing a structured report with consolidated inline citations.
- Hosting the compiled Deep Agents graph through `ResponsesHostServer`.
- Running long-running tasks as resilient background responses with reconnect, replay, and steering support.
- Persisting resilient conversation state with `FoundryCheckpointSaver` and long-term memory with `AsyncSqliteStore` plus LangMem tools.
- Integrating a Foundry hosted agent with other services: Azure Container Apps, Cosmos DB, and Azure Static Web Apps.

## How it works

The coordinator saves the request to `/research_request.md`, plans the work, and delegates research instead of searching directly. Research subagents use the tutorial's bounded search loop: two or three searches for simple questions and at most five for complex questions. The coordinator consolidates their citations, writes `/final_report.md`, and verifies that the report covers the original request.

The agent uses the `gpt-5.6-terra` model deployed in the Foundry project. Its coordinator and research subagent share all tools loaded from the `deep-agents-tools` Toolbox. The Toolbox is declared as an `azure.ai.toolbox` service in `azure.yaml`, and the hosted agent lists it under `uses`, so `azd` deploys the Toolbox before the agent.

Deep Agents also receives a `PlatformShellBackend`. On Windows it executes PowerShell commands on the local machine; in Foundry it executes commands inside the hosted Linux runtime. File and terminal tools are rooted at the current working directory locally and at the session `$HOME` when hosted, so agent-created files appear directly in session file listings. Every `execute` call requires human approval. The backend forwards only basic shell variables such as `PATH`, not application credentials, but shell access is still unrestricted within the account or container running the agent.

## Project structure

The application combines the hosted agent with a React client and a project-scoped API:

```text
src/langgraph-deep-agents/
backend/                    FastAPI, Foundry SDK, and Cosmos domain store
frontend/                   React and Vite client
infra/backend/              ACA, ACR, Cosmos, managed identity, and RBAC
infra/frontend/             Static Web Apps Standard and linked ACA backend
```

- `main.py` owns only the Foundry checkpoint and Responses server lifecycle.
- `agent.py` composes the coordinator, research subagent, and planning middleware.
- `utils.py` constructs the Foundry-backed chat model.
- `research_agent/prompts.py` contains the research workflow and delegation instructions.
- `research_agent/tools.py` loads the tools exposed by the Foundry Toolbox.

Each application project owns one Foundry session and shared persistent `$HOME`. Its conversations have separate Foundry conversation IDs. Cosmos stores project metadata and these mappings, partitioned by the Static Web Apps user ID. Foundry remains the source of truth for response history.

Long-term memory uses the official LangMem `manage_memory` and `search_memory` tools backed by LangGraph's `AsyncSqliteStore`. The SQLite database is stored at `$HOME/.deepagents/memories.sqlite` in the hosted session, so memories survive restarts and are shared across conversations in the same application project. This store is separate from thread-scoped LangGraph checkpoints and Foundry conversation history.

The project Files drawer browses that shared hosted-session `$HOME` as a lazy tree. FastAPI resolves the project's hidden session mapping, confines paths to the project workspace, and streams selected files as downloads; raw Foundry session IDs are not exposed in the UI. Double-clicking a recognized UTF-8 text file smaller than 1 MiB opens a read-only in-app preview. Larger and binary files remain download-only.

The API lists model deployments from the same Foundry project and intersects them with the official Responses API text/reasoning model matrix. The selected deployment is sent on every app request through `x-model-deployment-name`, validated by FastAPI, then forwarded to the hosted agent as `x-client-model` and the standard Responses `model` field. The coordinator and delegated research agents select that deployment for the current request; no Chat Completions API is used.

The composer supports two behaviors while a response is active. **Queue** stores messages in a client-side FIFO and submits them after the active response completes. **Steer** immediately creates a concurrent turn on the same platform conversation. The hosted Responses server runs with `resilient_background=True` and `steerable_conversations=True`, so the new turn cancels the active server stream and supersedes its work on the conversation chain.

The execution-mode selector defaults to **Default**, which requires approval for terminal execution. **Auto** sends `x-client-execution-mode: auto` on each response and disables the agent's request-scoped HITL predicate, so every available tool runs without approval. Queued messages retain the execution mode selected when they were queued.

Every turn uses `background=true`, `stream=true`, and `store=true` with a client-generated stable response ID. A create stream may close while its response is still `queued` or `in_progress`; the browser then retrieves the server-advertised response ID and resumes after the latest SSE `sequence_number` until a terminal event arrives. The backend opens Foundry streams before returning HTTP 200 so retrieval 404s and retryable 5xx responses remain visible to this recovery loop. The deployed Foundry endpoint rejects `conversation` and `previous_response_id` together, so backend requests stay on the platform conversation chain while the browser retains the prior response ID for steering state and stable ID partitioning.

Deep Agents implements approval with LangChain's `HumanInTheLoopMiddleware`, whose interrupt expects a `decisions` list when resumed. The host emits paired `function_call` and `mcp_approval_request` items for that interrupt. The browser answers through the richer `function_call_output` channel with `{"resume":{"decisions":[...]}}`; the simpler `mcp_approval_response` echo used by Foundry's resilient trip-planning sample applies to that sample's custom boolean interrupt and does not satisfy the middleware contract.

In Azure, Static Web Apps built-in Entra authentication fronts the linked Container App. Linking creates the `Azure Static Web Apps (Linked)` identity provider, so ACA accepts only proxied SWA traffic. The API uses a user-assigned managed identity for Foundry and Cosmos; no app registration or stored credential is required.

## Prerequisites

1. Install the [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd).
2. Install the Foundry agent extension with `azd extension install azure.ai.agents`.
3. Install Python 3.12 or newer and Node.js 22 or newer.
4. Authenticate locally with `az login` and `azd auth login`.
5. For provisioning, use an identity with permission to create role assignments, such as Owner or Role Based Access Control Administrator plus Contributor, on the target resource group.

## Run the full app locally

```powershell
python -m venv backend/.venv
backend/.venv/Scripts/python.exe -m pip install -r backend/requirements-dev.txt
Copy-Item backend/.env.example backend/.env
Set-Location frontend
npm install
npm run dev
```

Set `FOUNDRY_PROJECT_ENDPOINT`, `FOUNDRY_AGENT_VERSION`, and `FOUNDRY_MODEL_NAME` in the ignored `backend/.env`, then open the Vite URL shown in the terminal. Vite proxies `/api` to FastAPI on port 8000. Local development uses `DefaultAzureCredential` and persists project mappings in the ignored SQLite database `backend/.data/deep-coding.db` (the legacy filename is retained to preserve existing local projects), so projects and conversations survive API restarts. Delete that file when you intentionally want a clean local workspace.

Run backend tests and build the frontend with:

```powershell
backend/.venv/Scripts/python.exe -m pytest -q backend/tests
Set-Location frontend
npm run build
```

## Provision and deploy

Deployment-specific values belong in the selected azd environment, which is stored under ignored `.azure/<environment>/.env`. Start from the committed root `.env.example`:

```powershell
Copy-Item .env.example .env
# Fill in .env, then import its non-comment entries into the active azd environment.
Get-Content .env | Where-Object { $_ -match '^[A-Z][A-Z0-9_]*=' } | ForEach-Object {
	$name, $value = $_ -split '=', 2
	azd env set $name $value
}
```

The copied root `.env` is ignored. Generated agent versions, service IDs, and endpoints are written by azd to its ignored environment and therefore are intentionally omitted from `.env.example`.

```bash
azd provision
azd deploy
```

The layered deployment runs in this order:

1. Foundry model, Toolbox, and hosted agent.
2. Container Apps Consumption, ACR, Cosmos DB serverless, managed identity, and least-privilege role assignments.
3. Static Web Apps Standard and its linked ACA backend.

The API scales from zero to three replicas. Static Web Apps must use the Standard plan for a linked Container Apps backend. Review those costs and run `azd provision --preview backend` before applying infrastructure changes.

After deployment, unauthenticated browser requests are redirected to `/.auth/login/aad`. Approve an `execute` request only after reviewing the full command; terminal execution uses the hosted agent's Linux container, while the session `$HOME` persists across stopped sessions.

See [Microsoft Foundry hosted agents](https://learn.microsoft.com/azure/foundry/agents/how-to/deploy-hosted-agent) for the complete deployment workflow.

## Debug in VS Code

Open this sample folder in VS Code, select its Python environment, install `requirements.txt`, and create `.env` from `.env.example`. Press **F5** to start the server under `debugpy` and open Foundry Toolkit Agent Inspector.