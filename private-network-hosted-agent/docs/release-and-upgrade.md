# Release and upgrade guidance

This template does not publish a supported release train, upgrade SLA, or
compatibility window. Deploy and hand off an exact tested commit rather than an
unpinned branch.

## Record every deployment

Capture:

- repository commit or release;
- Azure region and connectivity mode;
- Azure CLI, azd, Bicep, PowerShell, Python, and azd extension versions;
- model deployment name/version/capacity;
- top-level ARM deployment name;
- Agent name and immutable version;
- validation date and approved evidence-store reference; create a sanitized
  summary only when reporting through a public channel.

Microsoft documents that each Hosted Agent deployment creates a version; see
[Manage hosted agents](https://learn.microsoft.com/azure/foundry/agents/how-to/manage-hosted-agent).

## Upgrade procedure

1. Review repository, dependency, API-version, model, and Microsoft platform
   changes.
2. Check current regions, quotas, preview status, CMK availability, and known
   limitations.
3. Run unit and repository contract tests.
4. Run preflight against the target subscription and regions.
5. Preview Bicep changes and review replacements, deletes, and ownership.
6. Deploy to a non-production environment through the same private topology.
7. Run management-plane and private data-plane validation plus workload-specific
   quality, authorization, load, and recovery tests.
8. Approve promotion and retain the previous Agent version until rollback
   criteria and data compatibility are understood.

## Model lifecycle

The Bicep sets `NoAutoUpgrade` for the pinned model version. That avoids an
unreviewed automatic version change but does not prevent model retirement.
Track current
[model retirements and upgrades](https://learn.microsoft.com/azure/foundry/openai/concepts/model-retirements)
and validate a replacement before the retirement date.

## Rollback boundary

- A previous Agent version can be retained for comparison, but infrastructure,
  Search schema, customer data, and platform behavior might not be backward
  compatible.
- CMK adoption and Search object encryption have irreversible constraints
  documented by Microsoft. Review
  [Foundry CMK](https://learn.microsoft.com/azure/foundry/concepts/encryption-keys-portal)
  and
  [Search CMK](https://learn.microsoft.com/azure/search/search-security-manage-encryption-keys)
  before changing keys or encrypted objects.
- Do not promise in-place rollback without a tested procedure for the exact
  change.

Adopters must define supported versions, security update handling, deprecation
notice, and support ownership before general delivery.
