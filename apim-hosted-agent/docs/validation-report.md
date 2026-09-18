# APIM-hosted agent validation report

Date: 2026-09-17

## Scope

This validation covered the `apim-hosted-agent` template on the
`codex/optional-google-mcp` branch. Google MCP remained disabled in every
scenario.

Four isolated environments exercised the full matrix:

| GitHub MCP | Infrastructure | Region |
| --- | --- | --- |
| Disabled | Bicep | Sweden Central |
| Disabled | Terraform | France Central |
| Enabled | Bicep | Germany West Central |
| Enabled | Terraform | Norway East |

Each environment requested:

- one resource group;
- one Microsoft Foundry account and project;
- one `gpt-5.6-luna` `2026-07-09` deployment with 100
  `DataZoneStandard` capacity units;
- one Basic v2 API Management service;
- one hosted agent and toolbox.

## Initial failures

The clean baseline exposed the same resource-group contract defect through both
infrastructure providers.

### Bicep

The Foundry layer created `rg-<environment>-foundry`, while the APIM layer
targeted `rg-<environment>`. APIM provisioning then failed with
`ResourceNotFound` for the Foundry account and project.

### Terraform

The Foundry layer completed, but `AZURE_RESOURCE_GROUP` remained unset when the
dependent Terraform layer evaluated its variables. Terraform failed because
the resource-group name was blank and the generated Foundry project parent ID
was invalid.

## Fix

The template now uses one canonical resource-group input:

- `azure.yaml` and `azure-terraform.yaml` bind the azd project to
  `${AZURE_RESOURCE_GROUP}`;
- the README sets `AZURE_RESOURCE_GROUP` to the Foundry layer's deterministic
  `rg-<environment>-foundry` name before provisioning;
- template and README logic no longer read or copy
  `AZURE_FOUNDRY_RESOURCE_GROUP`.

The Microsoft Foundry azd provider may still maintain
`AZURE_FOUNDRY_RESOURCE_GROUP` as internal layer-ownership state. The template
does not consume it.

## Fixed rerun results

| GitHub MCP | Infrastructure | Provision | Deploy and APIM smoke | MCP verification | Cleanup |
| --- | --- | --- | --- | --- | --- |
| Disabled | Bicep | Pass on clean first attempt | Active agent; HTTP 200 completed response | Learn present; GitHub and Google absent | Resources removed; one run required targeted completion after `azd down` reported a redundant Foundry ownership check |
| Disabled | Terraform | Pass from zero resources after a quota-race retry | Active agent; HTTP 200 completed response | Learn present; GitHub and Google absent | Pass |
| Enabled | Bicep | Pass from zero resources after a quota-race retry | Active agent; HTTP 200; OAuth consent surfaced | Read-only GitHub repository search completed; Learn present; Google absent | Pass |
| Enabled | Terraform | Pass on clean provision | Active agent; HTTP 200; OAuth consent surfaced | Read-only GitHub repository metadata request completed; Learn present; Google absent | Pass |

No test wrote to GitHub. The GitHub checks used public, read-only repository
operations.

## Environmental observations

### Shared model quota

The subscription had 333 available `DataZoneStandard` units while four
concurrent environments requested 400 units. Some first attempts therefore
failed with `InsufficientQuota` after concurrent usage changed between
preflight and provisioning. The affected partial resources were removed, the
tests were serialized, and fresh retries passed without a template workaround.

### OAuth consent

One consent page returned a transient `Code ... not found` error even though a
subsequent stateless GitHub tool request completed successfully. The Bicep flow
required a fresh consent link before reporting authentication success. Both
providers ultimately completed read-only GitHub tool calls.

### Bicep teardown

One GitHub-disabled Bicep run saw `azd down` delete the shared resource group
before the Foundry layer's redundant ownership check, causing a nonzero command
exit after the resources were already removed. Targeted verification and
cleanup confirmed that no resources remained. A later GitHub-enabled Bicep run
completed the same `azd down` flow with exit code 0, so the behavior was not
consistently reproducible.

## Final state

All four fixed scenarios passed the documented provision, deploy, active-agent,
APIM response, and MCP topology checks. Both GitHub-enabled scenarios completed
read-only tool calls after consent. All validation resource groups, Foundry
resources, APIM services, soft-deleted Foundry accounts, local azd
environments, and locally stored OAuth credentials were removed.

Sanitized command output and timing evidence are retained in the four validation
session artifacts and are intentionally not committed with this report.

## Follow-up retained and Google validation

A second six-session run used 50 `DataZoneStandard` capacity units per
environment so the deployments fit within the subscription's 333-unit quota.

### Retained manual-test environments

| Scenario | Resource group | APIM responses endpoint | State |
| --- | --- | --- | --- |
| GitHub disabled, Bicep | `rg-manual-nghb-90c838-foundry` | `https://apim-xfh-90c838-mnghb.azure-api.net/agent/responses` | Active; HTTP 200 completed smoke response |
| GitHub disabled, Terraform | `rg-manual-nght-90c838-foundry` | `https://apim-xfh-90c838-mnght.azure-api.net/agent/responses` | Active; HTTP 200 completed smoke response |
| GitHub enabled, Bicep | `rg-manual-ghb-90c838-foundry` | `https://apim-xfh-90c838-mghb.azure-api.net/agent/responses` | Active; OAuth consent remains unresolved for manual investigation |
| GitHub enabled, Terraform | `rg-manual-ght-90c838-foundry` | `https://apim-xfh-90c838-mght.azure-api.net/agent/responses` | Active; OAuth consent links returned 404 during validation |

These four Azure environments and their local azd environments were
intentionally retained. The GitHub-enabled environments retain their local
OAuth configuration for manual testing.

### Google MCP validation

Google tool names were removed from the guide before testing. Both providers
discovered the server inventory at runtime and selected a safe tool only after
discovery.

| Infrastructure | Result |
| --- | --- |
| Bicep | Provision and deploy passed. Hosted-agent authorization succeeded, the runtime selected an advertised arithmetic tool dynamically, and the result was validated without personal output. Direct Toolbox `tools/list` required separate developer-identity consent and was not completed before cleanup. |
| Terraform | Provision and deploy passed. Authenticated `tools/list` returned the live inventory, a safe advertised arithmetic tool returned the expected result, and no identity-bearing tool was invoked. |

Both Google Azure environments, local azd environments, and locally stored
Google credentials were deleted after testing. The external Cloud Run service
and Google OAuth application were not modified by cleanup.

### Follow-up documentation findings

- The Google guide previously used `azd up`, which deploys before the generated
  OAuth callback can be registered. The guide now uses `azd provision`, callback
  registration, then `azd deploy`.
- A `store=false` response cannot be resumed with `previous_response_id`.
  The guide intentionally keeps requests stateless: each retry creates a new
  response and uses only that response's newest, single-use consent URL.
- Google tool validation now uses `tools/list` and an advertised safe tool
  instead of assuming a fixed inventory.
- Foundry can require distinct consent for the hosted-agent caller and the
  developer identity used for direct Toolbox calls.
