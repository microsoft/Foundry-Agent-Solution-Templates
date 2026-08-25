# Contributor guidance

Preserve these invariants:

- Terraform and azd are the default deployment path. Bicep remains a supported
  companion implementation. Keep both implementations behaviorally equivalent.
- The default Hosted Agent is Python 3.13 source code with `remote_build`.
- The opt-in ACR scenario consumes only a digest-pinned image from an existing
  enterprise ACR and creates only its Foundry project connection.
- Public fallback, Dockerfiles, template-owned ACR resources, ACR networking,
  ACR IAM, App Insights, and Log Analytics are out of scope.
- Do not weaken `publicNetworkAccess`, local-auth, CMK, private endpoint, or
  least-privilege defaults to make a test pass.
- Never put a site-to-site shared key in source, azd environment files, output,
  logs, or test fixtures. Terraform necessarily records the configured value in
  its ignored local state and generated working files; treat both as secrets.

Before diagnosing an existing private ACR deployment, read
`docs/troubleshooting-existing-private-acr.md`. Do not add development-only
fixtures or environment-specific acceptance records to this template, publish
them as template guidance, or treat their ACR, network, IAM, or Agent resources
as template-owned. Review release artifacts for environment identifiers.

Customer-facing documentation must distinguish:

- controls implemented and validated by this template;
- capabilities, limits, privacy, and lifecycle behavior owned by Microsoft and
  cited from current Microsoft Learn documentation;
- workload decisions and production evidence owned by the adopter.

Do not claim an SLA, HA/DR, backup, continuous monitoring, compliance,
production readiness, or complete CMK coverage unless current Microsoft
documentation and repository implementation support the exact claim.
