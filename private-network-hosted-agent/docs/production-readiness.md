# Production adoption

This template is a validated preventive baseline, not a production
certification. A production deployment is ready only after the workload owner
closes the gates below for the intended users, data, regions, scale, and
regulatory context.

Use the
[Well-Architected AI workload design principles](https://learn.microsoft.com/azure/well-architected/ai/design-principles)
together with current Hosted Agent documentation; neither replaces a
workload-specific production review.

## What the template establishes

- private endpoints and public-network disablement for Foundry, Search, and Key
  Vault;
- keyless authentication for Foundry and Search;
- managed identity and query-only Search access for the Agent;
- default-deny Agent egress with documented Microsoft dependencies;
- separate Foundry and Search CMKs;
- repeatable management-plane and private data-plane checks;
- no public fallback when a private dependency fails.

## Gates the adopter must close

| Gate | Required production decision or evidence | Current template state |
|---|---|---|
| Workload threat model | Assets, actors, abuse cases, trust boundaries, mitigations, and residual risk approved by security owners. | Architecture boundaries are documented; no customer-specific threat model. |
| User and data authorization | Define who can invoke the Agent and which documents each identity may retrieve. | `Foundry Agent Consumer` controls invocation; one shared demo index has no document-level authorization. |
| Data governance | Classification, residency, retention, deletion, backup, legal hold, and incident handling. | Non-sensitive sample data only; no customer ingestion lifecycle. |
| Responsible AI and quality | Use-case risk review, content controls, prompt-injection tests, evaluation dataset, quality thresholds, and human escalation. | Template security and acceptance checks only; no workload quality evaluation dataset or thresholds. |
| Availability and DR | Approved RTO/RPO, dependency redundancy, region strategy, recovery procedure, and regular DR exercises. | Single core region for Foundry, networking, and Key Vault; Search and an existing enterprise ACR may be in other regions. No template backup, failover, or DR automation. |
| Monitoring and incident response | Metrics, traces/logs, retention, redaction, alerts, ownership, escalation, and forensic access. | No App Insights, Log Analytics, central alerts, or forensic retention. |
| Capacity and performance | Concurrent users/sessions, latency, token volume, model quota, subnet utilization, Search scale, and load-test results. | Fixed sample capacity; Search Basic with one replica and one partition. |
| Release and supply chain | Reviewed dependencies, build provenance, artifact promotion, approvals, rollback, and supported-version policy. | Template baseline and exact-commit deployment; no published release policy. |
| Cost approval | Current calculator estimate for the selected region, connectivity mode, load, retention, and optional ACR. | Cost categories documented; no authoritative workload estimate. |
| Compliance and legal | Organizational policies, regulatory review, contractual commitments, and Azure Policy requirements. | No compliance certification or guarantee. |

## Platform statements that must remain Microsoft-owned

- Microsoft documents Hosted Agent isolation, identity, lifecycle, and scaling;
  see [Hosted agents](https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agents).
- Regions, tools, quotas, and preview status change; see
  [limits, quotas, and regions](https://learn.microsoft.com/azure/foundry/agents/concepts/limits-quotas-regions).
- Data processing and storage boundaries depend on deployment type; see
  [Agent data privacy and security](https://learn.microsoft.com/azure/foundry/responsible-ai/agents/data-privacy-security)
  and [Azure OpenAI data privacy](https://learn.microsoft.com/azure/foundry/responsible-ai/openai/data-privacy).
- CMK scope and regional availability are defined by
  [Microsoft Foundry encryption documentation](https://learn.microsoft.com/azure/foundry/concepts/encryption-keys-portal).

Do not claim an Agent Service SLA, zone redundancy, automatic regional failover,
backup of Agent state, or a recovery objective unless current Microsoft
contractual documentation and a tested workload design support that claim.

## Release decision

Do not label a derived deployment production-ready until every applicable gate
has an owner, evidence, and approval. Record exceptions as accepted risks, not
as template defaults.
