# Customize the template safely

This template is a security baseline, not a generic application generator.
Customize business behavior only after documenting the workload's data,
identity, network, reliability, and responsible-AI requirements.

## Security invariants

Do not remove or weaken these controls to simplify development:

- Foundry, Search, Key Vault, and optional ACR public access remains disabled.
- Foundry and Search local/key authentication remains disabled.
- Private endpoints and private DNS remain the application data-plane path.
- Hosted Agent egress remains default-deny with only documented dependencies.
- Managed identities and least-privilege RBAC replace client secrets and keys.
- Foundry and Search CMK configuration remains enabled.
- Bicep and azd remain the deployment path.
- Do not add Terraform, a Dockerfile, a template-owned ACR, or public fallback.
- Never store the S2S shared key in source, azd state, logs, output, or fixtures.

## Replace the sample knowledge

The sample index schema is defined in `scripts/seed_search.py`:

| Field | Current behavior |
|---|---|
| `id` | Search document key |
| `title` | Searchable and returned to the Agent |
| `content` | Searchable grounding text |
| `source_url` | Returned citation target |

`demo-data/search-documents.json` is deterministic and non-sensitive. Before
using customer data:

1. Define data ownership, classification, residency, retention, deletion,
   backup, and legal requirements.
2. Design ingestion outside this sample instead of committing customer content.
3. Add tenant/user/document authorization and Search filters when users are not
   allowed to read every indexed document.
4. Treat retrieved text as untrusted data and test prompt-injection behavior.
5. Update the schema, selected fields, citation renderer, validation corpus, and
   tests together.

The current implementation performs a simple text query and selects
`id`, `title`, `content`, and `source_url`. It does not implement vectors,
semantic ranking, ingestion pipelines, or document-level security.

Microsoft identifies document-level permissions, monitoring, and network access
as customer configuration responsibilities for Azure AI Search:
[Security in Azure AI Search](https://learn.microsoft.com/azure/search/search-security-built-in).

## Change Agent behavior

- `agent/search-agent/search_agent/orchestrator.py` contains the system prompt,
  tool-selection requirement, and grounded response flow.
- `agent/search-agent/search_agent/tools/search_private_knowledge.py` contains
  the tool schema and direct Search SDK query.
- `agent/search-agent/search_agent/citations.py` renders citations.
- `agent/search-agent/main.py` adapts Responses protocol history to the sample.

Keep the model from answering outside supported Search evidence unless the
approved use case explicitly requires another behavior. Add tests for every new
tool, authorization rule, and failure mode.

Microsoft states that workload owners are responsible for use-case-specific
responsible-AI mitigations and testing:
[Hosted agents](https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agents).

## Change model or capacity

The model is declared in both `azure.yaml` and Bicep and is validated by
`scripts/preflight.ps1`. A model change must update:

1. `azure.yaml` deployment name, model name/version, and capacity;
2. allowed values and defaults in `infra/main.bicep`;
3. `infra/main.parameters.json`;
4. preflight availability and quota checks;
5. repository contract tests and acceptance prompts;
6. cost, residency, safety, and model-retirement review.

Do not assume model or quota availability. Check current
[regions and limits](https://learn.microsoft.com/azure/foundry/agents/concepts/limits-quotas-regions)
and [quota guidance](https://learn.microsoft.com/azure/foundry/openai/how-to/quota).

## Change networking

Use [Connectivity, DNS, and routing](connectivity.md). Customer CIDRs, DNS,
routes, TLS inspection, S2S devices, BGP, peering permissions, and endpoint
policy cannot be inferred by the template. Validate the final path with
`scripts/validate-network.ps1`; do not enable public access as a diagnostic.

## Use a pre-built enterprise image

Use [Existing private ACR](existing-private-acr.md). That workflow consumes an
immutable image from infrastructure owned and secured outside this template.
It is not a Docker customization path for the default source deployment.

## Re-run acceptance

After any customization:

1. run unit and repository contract tests;
2. run `scripts/preflight.ps1`;
3. preview Bicep changes;
4. run management-plane validation;
5. connect through the configured private access path;
6. run private data-plane validation and workload-specific tests;
7. record sanitized evidence against an exact commit or release.

Passing the template tests provides evidence only for the checks they perform.
It does not certify the customized workload for production.
