# Coding Agent Instructions

This project is a **Microsoft Foundry hosted agent** fronted by Azure API
Management (APIM). Preserve the governed request paths: callers enter through
the APIM agent API, the hosted agent reaches its model through the APIM model
API, and MCP tools are exposed through APIM tool APIs.

## Key files

- `azure.yaml` — azd orchestration for the Foundry project, toolbox, hosted
  agent, infrastructure layers, environment variables, and deployment hooks
- `src/main.py` — Agent Framework setup, APIM-backed `FoundryChatClient`, and
  Foundry Toolbox integration
- `src/end_user_identity.py` — hashes Foundry's trusted platform user identity
  and forwards it only to the APIM model API for per-user token enforcement
- `infra/apim.bicep` — APIM service, shared configuration, and module
  orchestration
- `infra/modules/apim-agent.bicep` — hosted-agent ingress API
- `infra/modules/apim-model.bicep` — hosted-agent model gateway, portal
  Product, and resource links
- `infra/modules/apim-tool-*.bicep` — governed Microsoft Learn and optional
  GitHub MCP gateways
- `infra/foundry.bicep` — Foundry project RBAC and Bicep-owned MCP connections
- `infra/*.parameters.json` — azd parameter mappings for the Bicep layers
- `infra/policies/` — APIM authentication, rate-limit, token-limit, Content
  Safety, OAuth, and tool-governance policies
- `scripts/` — postprovision link synchronization and postdeploy hosted-agent
  identity binding
- `APIM-POLICIES.md` — policy behavior, counter keys, trust boundaries, and
  configuration reference

## Preserve these invariants

- Bicep and azd are the supported provisioning and deployment path.
- Keep `services.project.deployments` in `azure.yaml` aligned with
  `modelDeploymentName` in `infra/apim.parameters.json`.
- Keep the hosted agent's model endpoint on the project-compatible APIM path.
  Do not bypass APIM with a direct Foundry endpoint.
- Derive per-user model quota keys only from Foundry's platform-provided
  `user_id_key`. Do not trust a caller-supplied identity header or log the raw
  platform user identifier.
- Keep the model API restricted to the hosted-agent managed identity.
- Keep caller authorization in Foundry RBAC. APIM currently validates and
  forwards the `https://ai.azure.com/` bearer token; it does not replace
  downstream Foundry authorization.
- Keep MCP connections declared in `infra/foundry.bicep`. GitHub is optional
  and must remain disabled when both OAuth settings are absent.
- Treat APIM named values as administrator-facing policy configuration.
  Persistent default changes belong in Bicep because reprovisioning overwrites
  manual named-value edits.
- Do not bypass the configured authentication, identity checks, rate limits,
  token limits, Content Safety, or GitHub user/tool controls to make a test
  pass.

## Development workflow

Run commands from `apim-hosted-agent`:

```powershell
azd provision --no-prompt # Provision Foundry, APIM, connections, and RBAC
azd deploy --no-prompt    # Deploy the toolbox and hosted agent
azd down                  # Remove the environment after reviewing resources
```

Test deployed traffic through
`https://<apim-name>.azure-api.net/agent/responses` with a bearer token for
`https://ai.azure.com/`. If GitHub MCP is enabled, update its OAuth App callback
to the exported `GITHUB_OAUTH_REDIRECT_URL` before testing the tool.

## Microsoft Foundry Skill

Install the **Microsoft Foundry Skill** for guided deployment, evaluation, and troubleshooting workflows.

Direct install (preferred, works with any coding agent):

```bash
npx skills add https://github.com/microsoft/azure-skills --skill microsoft-foundry
```

Or install the Azure Skills Plugin:

- **Copilot CLI**: `/plugin marketplace add microsoft/azure-skills` then `/plugin install azure@azure-skills`
- **Claude Code**: `/plugin install azure@claude-plugins-official`

Then ask naturally, e.g. `Use the Microsoft Foundry Skill to deploy this agent.`

## References

- [Hosted agents overview](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents)
- [Microsoft Foundry Skill](https://learn.microsoft.com/en-us/azure/foundry/how-to/develop/use-microsoft-foundry-skill)
