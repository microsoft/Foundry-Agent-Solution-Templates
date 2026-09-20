# Cost boundaries

Offline scripted-model tests make no Azure calls. Deployment and real model
verification require an Azure subscription and can incur charges.

- The hosted runtime requests 0.5 CPU and 1 GiB memory; deployed hosted
  capacity can incur compute charges.
- `gpt-4.1-mini` uses a GlobalStandard deployment with capacity 10. Capacity
  is a quota allocation, not a currency budget or token-usage limit. Verify
  regional availability and current quota before provisioning.
- Planning, subagent calls, file operations and report synthesis each add
  model tokens; a research run makes multiple model calls.
- Foundry/provider-created supporting storage, monitoring or build resources
  may also be billable. Inspect the resources actually provisioned.
- Mock search has no external service or API-key cost.

Use Azure Cost Management to inspect actual charges. No fixed price estimate
is promised. Run `azd down` after verification and confirm the environment's
resources have been removed.
