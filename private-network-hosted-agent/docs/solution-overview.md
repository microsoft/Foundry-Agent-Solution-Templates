# Solution overview

## Purpose

This solution template demonstrates how to deploy a Microsoft Foundry Hosted
Agent with a private application data plane and fail-closed security defaults.
It is intended for cloud architects, security reviewers, platform engineers,
and application teams that need a concrete starting point for a private agent
deployment.

The sample Agent answers questions from a non-sensitive Azure AI Search index
and returns citations. The business behavior is intentionally simple so the
template can focus on network isolation, identity, encryption, deployment,
and validation.

## When to use this template

Use it to:

- evaluate a private Foundry Hosted Agent architecture in Azure public cloud;
- demonstrate public-network and local-auth disablement;
- review managed identity and least-privilege access to Azure AI Search;
- exercise Terraform or companion Bicep provisioning with azd and repeatable
  security checks;
- start a customer design that will add its own authorization, data lifecycle,
  reliability, monitoring, and responsible-AI controls.

Do not treat it as:

- a security, privacy, compliance, availability, or production certification;
- an air-gapped design or a zero-public-egress design;
- a ready-made multitenant authorization or document-security solution;
- a backup, disaster-recovery, monitoring, or incident-response implementation;
- a substitute for customer threat modeling and workload-specific testing.

## Demonstrated controls

- Foundry, Azure AI Search, and Key Vault public network access is disabled.
- Foundry and Search local key authentication is disabled.
- Private endpoints and private DNS are created for the application data plane.
- Hosted Agent egress is routed through Azure Firewall with a documented
  allowlist.
- Foundry and the Search sample index use separate customer-managed keys.
- The Hosted Agent receives a dedicated runtime identity and query-only Search
  access.
- Validation scripts reject public fallback and broader authentication.

These are template implementation statements. Microsoft is responsible for
platform behavior and service limits, which are cited from Microsoft Learn
throughout the documentation.

## Current support boundary

| Area | Current template boundary |
|---|---|
| Cloud | Azure public cloud. The Terraform and Bicep implementations use public-cloud private DNS suffixes. |
| Default deployment | Source deployment with `remote_build` and the Foundry-managed `python_3_13` runtime. Local Python is a separate workstation prerequisite; 3.13 is the documented and tested baseline, while invoke-only clients do not need Python. |
| Optional deployment | Digest-pinned image from an existing enterprise private ACR. The template does not create or manage that ACR. |
| Infrastructure | Terraform in `infra-terraform` is the default azd path. Bicep in `infra-bicep` is a supported companion. |
| Connectivity | P2S, S2S, or VNet peering. P2S is the documented default and end-to-end validation path. |
| Client | Default P2S instructions target Windows Azure VPN Client. macOS needs customer-managed DNS or another approved private path. |
| Agent behavior | One Search tool, one shared demo index, citations, and Responses protocol 2.0. |
| Data | Non-sensitive sample documents only. No customer ingestion or file upload. |
| Operations | Point-in-time validation only; no central logging, alerting, or forensic retention. |

Review [Production adoption](production-readiness.md) before using this design
for a production workload. For technical components and traffic flows, see
[Architecture](architecture.md).
