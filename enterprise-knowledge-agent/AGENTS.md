# Contributor guidance

Preserve the architecture: one Responses-protocol Hosted Agent connects only to one Foundry Toolbox. The Toolbox exposes the composed Foundry IQ Knowledge Base and `web_search`; the agent must not initialize Search or web clients directly. Keep Search keyless with local authentication disabled. Keep `2026-08-01-preview` pinned for all Knowledge Source and Knowledge Base operations. Configuration fragments are native platform payloads and must not contain plaintext secrets.

Terraform and azd are the default deployment path; Bicep remains a supported companion implementation. Keep both implementations behaviorally equivalent.

Run `python -m unittest discover -s tests -v`, `terraform fmt -check`, `terraform validate`, `terraform test`, and compile Bicep before submitting infrastructure changes. Live validation must use an isolated non-production resource group and must not record endpoints, authentication material, raw responses, or user data.
