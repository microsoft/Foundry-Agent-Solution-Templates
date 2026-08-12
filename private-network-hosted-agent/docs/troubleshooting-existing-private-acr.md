# Troubleshoot existing private ACR Agent deployment

Use this guide when a digest-pinned image from an existing private Azure
Container Registry (ACR) does not produce an active, invocable Foundry Hosted
Agent.

Do not enable public fallback, ACR local authentication, anonymous pull, or
broader IAM to make a diagnostic pass.

## Fast symptom map

| Symptom | Most likely boundary | First action |
|---|---|---|
| `ProvisioningError` for a healthy Linux `amd64` image | Unsupported manifest packaging | Run the private-data-plane preflight and inspect all manifest media types |
| Agent/list API says `active`, but session creation returns HTTP 409 `agent_version_failed` | Aggregate status may not reflect exact-version usability | Query the exact version API and invoke that version |
| ACR token, manifest, or blob request returns 401/403 | Pull identity or ACR authorization | Verify the Foundry project and stable per-Agent identities against the registry role mode |
| ACR login/data endpoint resolves publicly or times out | Private DNS, Private Endpoint, or routing | Validate from the same private execution point used for deployment |
| Version is exactly `active`, but invoke returns HTTP 500 | Application, model, or Search runtime | Create/select a session and inspect `azd ai agent monitor` |
| Public caller receives `PublicNetworkAccessDisabled` or HTTP 403 | Expected isolation when PNA is disabled | Connect through the configured private access path; do not enable public access |

## Known manifest compatibility failure

Template acceptance evidence isolated an opaque Foundry provisioning failure
to the image manifest format. Treat the result as a validated template
compatibility boundary rather than a Microsoft platform guarantee:

- an otherwise healthy OCI v1 image failed with generic
  `ProvisioningError`;
- the same application config and layer blobs published as Docker distribution
  manifest schema 2 became active and invocable;
- a minimal Echo image and the full Python 3.13 model-and-Search image produced
  the same controlled result.

The failing top-level media type was:

```text
application/vnd.oci.image.manifest.v1+json
```

The accepted image used:

```text
manifest: application/vnd.docker.distribution.manifest.v2+json
config:   application/vnd.docker.container.image.v1+json
layers:   application/vnd.docker.image.rootfs.diff.tar.gzip
platform: linux/amd64
```

Architecture and local readiness are necessary but not sufficient. A Linux
`amd64` image can pull, start, and return healthy readiness while Foundry still
rejects its OCI v1 manifest.

## 1. Run the fail-closed preflight

From `scenarios\existing-private-acr` and an approved private path:

```powershell
..\..\scripts\validate-existing-acr.ps1 `
  -ValidateConnection `
  -ValidatePullAuthorization `
  -RequirePrivateDataPlane
```

The preflight verifies:

- Premium ACR, PNA disabled, and local/anonymous authentication disabled;
- approved ACR Private Endpoint and RFC1918 login/data endpoint DNS;
- Foundry project creation after 2026-06-25;
- exact Foundry `ContainerRegistry` connection target and resource ID;
- role-mode-aware pull authorization for the Foundry project and per-Agent
  identities;
- immutable digest existence;
- Docker schema 2 manifest, config, and layer media types;
- Linux `amd64` image config.

Fix the reported prerequisite instead of bypassing the check.

## 2. Query the exact Agent version

Aggregate Agent status may not reflect whether a specific version is usable.
Query the exact version endpoint:

```powershell
$projectEndpoint = "<https://resource.services.ai.azure.com/api/projects/project>"
$agentName = "<agent-name>"
$version = "<version>"
$token = az account get-access-token `
  --resource https://ai.azure.com `
  --query accessToken `
  --output tsv

try {
  Invoke-RestMethod `
    -Uri "$projectEndpoint/agents/$agentName/versions/$version?api-version=v1" `
    -Headers @{ Authorization = "Bearer $token" }
}
finally {
  Remove-Variable token -ErrorAction SilentlyContinue
}
```

Require the exact response to report `active`, and then create a session and
invoke that same version. HTTP 409 `agent_version_failed` means the version is
not usable even if an aggregate view says otherwise.

## 3. Publish a template-supported image

The template-supported remediation is to rebuild or re-export the image through
the enterprise pipeline with Docker media types. Do not manually rewrite
manifest descriptors in a production pipeline; direct Registry API rewriting
is useful only as a controlled diagnostic comparison.

One Buildx pattern is:

```powershell
$image = "<login-server>/<repository>:<unique-build-id>"

docker buildx build `
  --platform linux/amd64 `
  --output "type=registry,name=$image,push=true,oci-mediatypes=false" `
  --provenance=false `
  --sbom=false `
  .
```

Builder and registry behavior can vary. Treat the private-data-plane preflight,
not the build command's exit code, as the final media-type check.

This compatibility example disables image-attached provenance and SBOM output.
The external enterprise image pipeline remains responsible for retaining
equivalent supply-chain evidence through its governed attestation and artifact
processes.

Resolve the immutable digest after publication and configure:

```powershell
azd env set AZURE_CONTAINER_IMAGE `
  "<login-server>/<repository>@sha256:<64-lowercase-hex>"
```

Never fall back to a mutable tag.

## 4. Differentiate image, IAM, and network failures

### Pull identity and RBAC

The template's `ContainerRegistry` connection uses the Foundry project identity
exposed as `AZURE_AI_PROJECT_IDENTITY_PRINCIPAL_ID`. Foundry also uses the
stable per-Agent identity exposed as `AZURE_AI_AGENT_PRINCIPAL_ID`. Grant the
required pull role to both identities at the exact registry scope.

- For `RBAC Registry Permissions`, grant exact-scope `AcrPull`.
- For `RBAC Registry + ABAC Repository Permissions`, grant
  `Container Registry Repository Reader`, optionally conditioned to the
  selected repository.
- Do not grant the deployment principal ACR push permission for the pre-built
  path.

`AcrPull` does not authorize pull on an ABAC-enabled registry.

### Private DNS and routing

Validate from the actual private execution point:

- the exact hashed ACR `loginServer`, not a constructed hostname;
- the ACR login endpoint and every configured data endpoint;
- the Foundry project hostname when Foundry PNA is disabled;
- RFC1918 resolution and HTTPS reachability through the intended route.

Do not enable ACR or Foundry public access to distinguish DNS from IAM.

### Application, model, and Search

After the exact version is active, invoke it:

```powershell
azd ai agent invoke private-search-agent-acr `
  "What does the network baseline say about public fallback?" `
  --version "<active-version>" `
  --new-session `
  --new-conversation
```

If invocation fails after a session exists:

```powershell
azd ai agent monitor --tail 100
azd ai agent monitor --type system --tail 100
```

Check the model deployment name, Foundry User role, Search endpoint/index
variables, and `Search Index Data Reader` on the Agent identity.

## 5. Collect support evidence

When the exact version still fails, record:

- project endpoint, Agent name, and exact version;
- digest-pinned image reference and all media types;
- Linux `amd64` config;
- exact-version status and error;
- deployment and session request IDs;
- ACR role mode and non-secret identity principal ID;
- private DNS results from the execution point;
- whether local `/readiness` succeeds;
- whether a session exists and, if so, its system logs and trace ID.

No session means `azd ai agent monitor` has no container logs to retrieve.
Preserve the request IDs for Foundry backend support.

## Guardrails for automated troubleshooting

Agents and scripts must not:

- enable Foundry or ACR public network access;
- enable ACR admin credentials, anonymous pull, or local auth;
- substitute a tag for the configured digest;
- create template-owned ACR, network, Private Endpoint, DNS, or IAM;
- grant broader roles to hide an authorization error;
- trust aggregate status without querying and invoking the exact version;
- delete enterprise-owned registry resources during template teardown.

See [Existing private ACR](existing-private-acr.md) for the deployment workflow.
The schema requirement is the template-enforced compatibility boundary
described above.
