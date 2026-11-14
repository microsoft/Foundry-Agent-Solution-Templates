# Contributor guidance

Before you change the AG-UI wiring, the CopilotKit frontend, approvals, or the
gateway, install and read the
[`foundry-hosted-agent-copilotkit`](https://awesome-copilot.github.com/skill/foundry-hosted-agent-copilotkit/)
skill. This template is its wiring A: an AG-UI gateway over a Responses hosted agent.

Preserve these invariants:

- **Foundry owns conversation state.** The AG-UI thread ID is a Foundry
  conversation ID (`conv_...`). Do not add a thread, snapshot, or history store
  to the gateway or the web app.
- **The gateway is the only caller of Foundry.** Only its managed identity holds
  Azure AI User on the project. The web app holds no Foundry role.
- **Every thread has an owner.** `/threads` records the signed-in user in the
  conversation metadata, and the AG-UI authorization scope rejects any other
  user. Never configure `single_user=True`.
- **The gateway stays internal.** Only the web app has external ingress, and it
  requires Entra sign-in. Built-in authentication uses the web app's managed
  identity as a federated credential. Do not add a client secret.
- **Side-effecting tools need approval.** Use `approval_mode="always_require"`
  and keep the approval payload `{approved: boolean}`.
- **The gateway runs one replica.** Pending approvals are held in gateway memory.
  Scaling out needs session affinity first.
- **Prompt and response text stays out of traces.**
  `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT` stays `false`.
- **Keep `HostedApprovalAgent` until upstream fixes land.** Delete it only
  after approve, reject, and follow-up turns pass in a browser without it
  (see `docs/architecture.md`).
- **Dependencies are pinned with `==`.** The hosted agent is built remotely, so
  local success does not prove the deployed build.

A change is done only when the skill's completion criteria pass against the
deployed agent through the real UI: approve and reject both work, an approved
tool runs exactly once, and cards still render after the run finishes.

Validate offline before you open a pull request:

```powershell
pip install -r requirements-dev.txt
ruff check . ; ruff format --check . ; pytest
cd src/web ; npm ci ; npm run typecheck ; npm test ; npm run build
az bicep build --file infra/app.bicep --stdout > $null
```

Sample data is synthetic. Do not add real customer, policy, or claim data.
