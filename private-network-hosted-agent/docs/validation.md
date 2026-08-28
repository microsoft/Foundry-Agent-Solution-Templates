# Validation

Validation provides point-in-time evidence only for the controls implemented
by these scripts. It is not continuous monitoring, penetration testing, a
compliance assessment, or production certification.

## Validation layers

| Layer | Command | Private path required | Purpose |
|---|---|---|---|
| Unified workflow | `scripts/deploy.ps1` | Pauses for P2S; required after provision | Validates inputs, ownership, preview, deployment, exact Agent version, Search bootstrap, and grounded acceptance. |
| Preflight | `scripts/preflight.ps1` | No | Tools, subscription, providers, model, regional quota, Search location, and connectivity inputs. Makes no Azure changes. |
| Management plane | `scripts/validate-all.ps1` | No | Resource state, PNA/local auth, private endpoints, RBAC, CMK, and disallowed-resource checks. |
| Private data plane | `scripts/validate-all.ps1 -IncludePrivateDataPlane` | Yes | Private DNS, Search access, Agent status/invocation, citations, and fail-closed behavior. |
| Network only | `scripts/validate-network.ps1 -RequirePrivateResolution` | Yes | RFC1918 resolution for Foundry, Search, Key Vault, and configured ACR endpoints. |
| Existing ACR | `scripts/validate-existing-acr.ps1` | Optional by switch | ACR ownership boundary, project date, private settings, connection, pull authorization, digest, media types, and platform. |

## Controls covered

Management-plane and template-contract checks include:

- expected resource types and provisioning state;
- provider, region, model, quota, and RBAC prerequisites, including the required
  Foundry account and project vault-scope CMK grants;
- Foundry, Search, and Key Vault public-network configuration;
- Foundry and Search local-auth configuration;
- private endpoint approval;
- Key Vault protection, key separation, and Foundry CMK binding;
- absence of template-owned ACR, Dockerfile, App Insights, and Log Analytics;
- Terraform and Bicep contract parity and the selected provider's expected
  infrastructure files;
- optional existing ACR settings, connection target, and external pull
  authorization.

Private checks include:

- private DNS for Foundry, Search, Key Vault, and optional ACR endpoints;
- CMK-backed Search index creation and deterministic sample data;
- Agent query-only Search access and expected citations;
- public/key-auth rejection;
- Agent deployment and invocation;
- invocation-session creation and, only when the `-DeleteSession` switch is
  explicitly used, deletion of every session visible to the signed-in test
  principal.

## Controls not covered

Add workload-specific evidence for:

- customer authorization and document security;
- data ingestion, retention, deletion, backup, and DR;
- responsible AI, content safety, prompt injection, and response quality;
- performance, concurrency, quota exhaustion, availability, and failover;
- centralized monitoring and incident-response exercises;
- customer policy, regulatory, and compliance requirements.

See [Production adoption](production-readiness.md).

## Point-in-time report

`scripts/validate-all.ps1` writes a human-readable Markdown report under
`artifacts/validation/<environment-name>/`. The unified deployment prints the
stable `latest.md` path in its completion summary; timestamped Markdown copies
preserve earlier runs.

The report records:

- overall and per-control pass, fail, or not-run status;
- environment, deployment mode, resource group, Agent name and version;
- source revision and clean/dirty tree state, UTC execution time, validation
  scope, and duration;
- an acceptance decision and total checklist assertion count;
- each control family's security objective, validation method, observed result,
  and individually rendered acceptance checklist;
- explicit adopter-owned follow-up and report interpretation boundaries.

If a validator fails, the report is written before the command fails. Remaining
checks are marked `NOTRUN` rather than represented as successful.

A `PASSED` report means every listed control passed at that execution point. It
does not guarantee that the deployment is secure under every threat model and
does not change the production, compliance, privacy, lifecycle, monitoring, or
adopter-owned evidence boundaries above.

## Evidence handling

Store tenant-sensitive local output under ignored `artifacts/`. Never record
tokens, S2S shared keys, VPN profiles, private keys, Docker credentials,
customer prompts, or sensitive documents. Bind evidence to an exact
commit/release, environment, Agent version, date, and execution point. Follow
[`SUPPORT.md`](../SUPPORT.md) before sharing evidence and sanitize all public
issue attachments.
