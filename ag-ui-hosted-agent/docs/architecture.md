# Architecture

## Why a gateway

A deployed Foundry Hosted Agent speaks the OpenAI Responses protocol, not AG-UI.
A browser also cannot hold the Microsoft Entra token that Foundry requires. So a
small server-side gateway sits between them. It does not translate the protocol
itself: `AgentFrameworkAgent` and `add_agent_framework_fastapi_endpoint` from
`agent-framework-ag-ui` do the translation, wrapping a `FoundryAgent` that points
at the deployed hosted agent by name.

## Request flow

1. The user opens the web app. Container Apps built-in authentication signs
   them in with Microsoft Entra ID and adds the `x-ms-client-principal-id`
   header to every request.
2. The page calls `POST /api/thread`. The web app forwards the call to the
   gateway's `POST /threads` with the user's object ID in `x-user-id`. The
   gateway creates a Foundry conversation with `metadata.owner` set to that ID
   and returns its `conv_...` ID.
3. CopilotKit uses the conversation ID as the AG-UI thread ID. Each message goes
   to the web app's CopilotKit runtime (`/api/copilotkit`), which builds an
   `HttpAgent` for that request with the user's ID in `x-user-id` and streams
   the run from the gateway.
4. The gateway's `authorization_scope_resolver` reads the thread ID, confirms
   the conversation's owner is the caller, and returns the user ID as the AG-UI
   authorization scope. Agent Framework then sends the turn to the hosted agent
   within that Foundry conversation (`use_service_session=True`,
   `service_session_id_from_thread_id=True`).
5. The hosted agent (`ResponsesHostServer`) runs the model and tools. When it
   reaches `escalate_claim`, it stores an approval request in Foundry and ends
   the turn. The gateway turns that into an AG-UI interrupt, and the web app
   shows the approval card.
6. The user's decision goes back as an AG-UI `resume`. The gateway forwards it
   to the hosted agent, which runs the tool once or records the rejection.

## Interop fixes in the gateway

`HostedApprovalAgent` in `src/gateway/app.py` works around two mismatches between
`agent-framework-ag-ui` 1.8.1 and CopilotKit 1.88 (`@ag-ui/client` 1.0.2):

- CopilotKit sends an approval decision twice, as `resume` and as a tool
  message. The gateway keeps only `resume`.
- The adapter ends the hosted approval call (`mcpr_...`) with a `TOOL_CALL_END`
  that has no `TOOL_CALL_START`. The browser client rejects that with
  `Cannot send 'TOOL_CALL_END' event: No active tool call found`, and the
  approval card never appears. The gateway drops the orphan event.

Remove the class when a package release fixes both and the approve, reject,
and follow-up checks pass without it.

## State

| State | Where it lives | Survives a restart of |
|---|---|---|
| Conversation history | Foundry conversation | web app, gateway, hosted agent |
| Pending approval request | Foundry (hosted agent approval store) | web app, hosted agent |
| AG-UI interrupt bookkeeping for a pending approval | Gateway memory | web app only |
| Thread owner | Foundry conversation metadata, cached in gateway memory | web app, gateway |

If the gateway restarts while an approval is pending, the resume fails with a
`RUN_ERROR` and the tool does not run. The conversation keeps working, so the
user asks again. For this reason the gateway runs a single replica.

## Security model

| Boundary | Control |
|---|---|
| Internet → web app | Microsoft Entra sign-in (built-in authentication, `RedirectToLoginPage`). The app registration has no client secret; the web app's managed identity is its federated credential. |
| Web app → gateway | Internal ingress only, reachable from inside the Container Apps environment. The web app sets `x-user-id` from the signed-in principal and never from client input. |
| Gateway → thread | `authorization_scope_resolver` rejects threads that are not `conv_` IDs (400), unknown conversations (404), and conversations owned by another user (403). Approval state is scoped per user. |
| Gateway → Foundry | Gateway managed identity with **Azure AI User** on the project only. The web app holds no Foundry role. |
| Containers → registry | Each app pulls with its own managed identity (**AcrPull**). The registry admin user is disabled. |
| Traces | `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=false` keeps prompt and response text out of telemetry. |

The gateway trusts `x-user-id` because only apps in the same Container Apps
environment can reach it. If you add other apps to that environment, or expose
the gateway, validate an Entra token in the gateway instead.

## Infrastructure layers

| Layer | Provider | Creates |
|---|---|---|
| `foundry` | `microsoft.foundry` (azd `azure.ai.projects` extension) | Resource group, Foundry account and project, model deployment, Application Insights |
| `app` | Bicep (`infra/app.bicep`) | Container Apps environment, `web` and `gateway` apps, container registry, two user-assigned identities, role assignments, Entra app registration with a federated credential, and the web app's authentication configuration |

`azd deploy` then deploys the hosted agent from source (Foundry builds it with
`remote_build`) and builds the two container images in the registry with ACR
Tasks.
