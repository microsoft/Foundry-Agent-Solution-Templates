# Operations

> **Template limitation:** this template has no centralized logs, alerts,
> dashboards, or forensic retention. The checks below are manual and
> point-in-time. A production adopter must design monitoring, retention,
> redaction, incident response, and on-call ownership before go-live.

## Ownership and inventory

Record the exact repository commit or release, azd environment name, generated
`RESOURCE_PREFIX`, Azure region, connectivity mode, top-level deployment name,
model version, and Agent version.

Use both the `azd-env-name` and `solution-template` tags to inventory
template-owned resources. A group created by `scripts/deploy.ps1` also has
`resource-group-ownership=template-created` and is dedicated to that
environment. The deployment workflow does not accept or adopt an existing
resource group.

The optional enterprise ACR, images, ACR networking, DNS, pipelines, and IAM are
external dependencies. Only the Foundry ACR connection is template-owned.

## Routine point-in-time checks

| Area | Check |
|---|---|
| Infrastructure | Run `scripts/validate-all.ps1` from the template root. |
| Private path | Connect through the configured private access path and run `scripts/validate-network.ps1 -RequirePrivateResolution`. |
| Agent | Run `scripts/validate-agent.ps1 -AgentVersion "<expected-version>"` against the recorded exact version. |
| Public-access boundary | Confirm Foundry, Search, and Key Vault PNA remains disabled and local auth remains disabled. |
| RBAC | Review deployment, consumer, Search, CMK, and optional ACR assignments for drift and least privilege. |
| Capacity | Review agent-subnet utilization, model quota, Hosted Agent sessions, Search throttling, replicas, and partitions. |
| Connectivity | Review VPN/BGP state, DNS Resolver health, private endpoint approval, and Firewall dependency failures. |
| Keys | Confirm both CMKs are enabled and service identities retain only required cryptographic access. |
| Optional ACR | Confirm digest availability, private login/data DNS, PNA/admin/anonymous settings, and pull-role authorization. |

Microsoft documents Hosted Agent session lifecycle and automatic compute
management in [Hosted agents](https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agents).
Do not infer an availability or recovery commitment from automatic scaling.

## Agent updates and sessions

Preview infrastructure changes before provisioning. Each `azd deploy` creates
or selects an Agent version; record the exact version and run private acceptance
before promotion. Follow [Release and upgrade guidance](release-and-upgrade.md).

After acceptance testing, list and remove test sessions:

```powershell
azd ai agent sessions list --output json
azd ai agent sessions delete "<session-id>" --no-prompt
```

Session deletion and platform retention behavior are Microsoft service
capabilities. Review current
[Hosted Agent documentation](https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agents)
and do not substitute test-session deletion for a customer data-retention
policy.

## CMK operations

- Retain Key Vault purge protection; never purge the vault as an operational
  shortcut.
- Rotate key versions without deleting or disabling the active version until
  Foundry and Search adoption is verified.
- Test service access after rotation and retain the prior version according to
  customer policy.
- Do not assume CMK covers every platform record. Microsoft defines the
  supported scope in
  [Foundry encryption documentation](https://learn.microsoft.com/azure/foundry/concepts/encryption-keys-portal).
- Search CMK is irreversible for an encrypted object and access depends on the
  key; see
  [Search CMK guidance](https://learn.microsoft.com/azure/search/search-security-manage-encryption-keys).

## Incident response

1. Preserve exact request IDs, timestamps, Agent version, deployment operation,
   and validation results in the approved incident evidence store. Sanitize
   tenant and resource identifiers before using a public repository issue.
2. Do not copy tokens, VPN profiles, S2S keys, customer prompts, or sensitive
   Search data into tickets.
3. Identify whether the failure is template code/configuration or an Azure
   service, quota, capacity, or preview issue.
4. Keep fail-closed settings unchanged while diagnosing.
5. Follow [Troubleshooting](troubleshooting.md) and [`SUPPORT.md`](../SUPPORT.md).

## Backup and disaster recovery

This template does not implement backup, regional failover, or restoration for
Agent state, Search data, customer ingestion, or external ACR images, and it
makes no backup or DR claim. Review current Microsoft documentation for
service-owned lifecycle capabilities.

The workload owner must define RTO/RPO, identify recoverable sources of truth,
design dependency recovery, and test a documented DR plan. Use
[Well-Architected disaster recovery guidance](https://learn.microsoft.com/azure/well-architected/reliability/disaster-recovery)
as general workload guidance.

## Teardown

> **Warning:** Do not begin cleanup by deleting the Foundry account, virtual
> network, or resource group. Foundry Capability Host and service association
> link cleanup is asynchronous.
> Out-of-order deletion can leave `legionservicelink` on the Agent subnet and
> block NSG, route-table, subnet, and VNet deletion.

Run the guarded script in the complete [Cleanup guide](cleanup.md). It deletes
project Capability Hosts before account Capability Hosts, purges the
soft-deleted Foundry account, and waits for the service-managed link to
disappear before subnet association or dedicated resource-group removal. Never
directly delete or patch a service association link. External ACRs, images,
ACR networking, DNS, IAM, and remote customer VNets remain outside the cleanup
boundary. In `vnetPeering` mode, cleanup removes only the exact reciprocal
peering child resource that this template created in the external VNet.
