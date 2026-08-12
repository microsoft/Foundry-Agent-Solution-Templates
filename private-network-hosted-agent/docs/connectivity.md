# Connectivity, DNS, and routing

Exactly one mode is selected.

The current Bicep uses Azure public-cloud private DNS suffixes. Sovereign-cloud
deployment is not supported or validated by this template.

## Deployment commands

Run one of these commands from the template root after replacing the
placeholders. These examples use the default source Agent package path.

### Point-to-site

```powershell
./scripts/deploy.ps1 `
  -DeploymentMode Source `
  -SubscriptionId "<subscription-id>" `
  -ConnectivityMode pointToSite `
  -P2sAddressPool "172.20.0.0/24"
```

### Site-to-site

Read the shared key without echoing it, expose it only to the current PowerShell
process for deployment, and remove it even if deployment fails:

```powershell
$env:S2S_SHARED_KEY = [System.Net.NetworkCredential]::new(
  '',
  (Read-Host -Prompt 'Site-to-site shared key' -AsSecureString)
).Password

try {
  ./scripts/deploy.ps1 `
    -DeploymentMode Source `
    -SubscriptionId "<subscription-id>" `
    -ConnectivityMode siteToSite `
    -S2sGatewayIpAddress "<customer-vpn-gateway-ipv4>" `
    -S2sRemoteAddressPrefixes @("10.80.0.0/16", "10.81.0.0/16")
}
finally {
  Remove-Item Env:S2S_SHARED_KEY -ErrorAction SilentlyContinue
}
```

Never put the shared key in the command, source, an azd environment, output,
logs, or a test fixture. For BGP, also pass `-S2sEnableBgp`,
`-S2sRemoteAsn <asn>`, and
`-S2sBgpPeeringAddress "<customer-bgp-peer-ipv4>"`.

### VNet peering

```powershell
./scripts/deploy.ps1 `
  -DeploymentMode Source `
  -SubscriptionId "<subscription-id>" `
  -ConnectivityMode vnetPeering `
  -RemoteVnetResourceId "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Network/virtualNetworks/<vnet-name>"
```

## Public dependencies by connectivity mode

Changing the connectivity mode changes caller ingress, but it does not change
the Hosted Agent's own identity or source-deployment requirements.

| Dependency | Point-to-site | Site-to-site | VNet peering |
|---|---|---|---|
| VPN Gateway public IP | Required as the OpenVPN tunnel endpoint | Required as the IPsec/IKE tunnel endpoint | Not deployed |
| Microsoft Entra sign-in from VPN client | Required by this template's P2S authentication | Not used | Not used |
| Agent egress through Firewall public IP to Entra and `mcr.microsoft.com` | Required | Required | Required |
| Operator access to Microsoft Entra and ARM | Required for deployment/administration | Required for deployment/administration | Required for deployment/administration |

The VPN Gateway public IP is a transport endpoint, not an authentication
endpoint. The P2S client reaches Microsoft Entra separately to authenticate the
user. The Azure Firewall public IP is a different resource used for the Agent
subnet's documented outbound SNAT and is deployed in all three modes.

The template can completely remove the VPN Gateway and its public IP by
selecting `vnetPeering`. It cannot remove the Firewall public IP without
redesigning the egress topology. Azure Firewall forced tunneling can move tenant
egress to an upstream firewall and use a management-only public IP, but this
template intentionally does not implement that topology.

## Point-to-site

The default deploys `VpnGw2AZ`, OpenVPN, and Microsoft Entra authentication.
The Azure VPN Client uses two independent public paths: Microsoft Entra for user
authentication, and the VPN Gateway public IP for tunnel establishment. Neither
path is the Hosted Agent's Firewall egress.
After `azd provision` completes:

1. On Windows, install Azure VPN Client.
2. Run `scripts/export-p2s-profile.ps1`.
3. Locate `AzureVPN/azurevpnconfig-resource-dns.xml` below `artifacts/p2s`.
4. Import that file into Azure VPN Client.
5. Connect and sign in with Microsoft Entra ID.
6. Run `scripts/validate-network.ps1 -RequirePrivateResolution`.

Microsoft documents that additional Azure VPN Client DNS suffixes don't persist
on macOS. For macOS clients, use customer-managed DNS conditional forwarding to
the Resolver inbound endpoint, or another configured private access path. Don't
claim the generated resource-scoped DNS profile as a persistent macOS solution.

Do not run `azd deploy`, Search seeding, or private data-plane validation until
the private-resolution check passes. Network access and Foundry RBAC are
independent: a connected user still needs the appropriate Azure roles.

### Tester profile handoff

For a coworker who will test an existing environment, the deployment owner
should run `scripts/export-p2s-profile.ps1` and transfer only
`azurevpnconfig-resource-dns.xml` through an approved secure channel. The
tester imports that profile and authenticates with their own Microsoft Entra
account.

Do not grant Network Contributor merely so a tester can generate a profile. If
self-service generation is required, use a custom role containing only
`Microsoft.Network/virtualNetworkGateways/generatevpnprofile/action` and the
required gateway read permission. The template does not add a separate Entra
group restriction to the VPN Gateway, so profile distribution must follow the
adopter's access policy. The profile provides network configuration, not
Foundry authorization; assign the minimum invocation role separately as
described in [coworker handoff](deployment.md#existing-environment-and-coworker-handoff).

Never commit or attach a VPN profile to a public issue. Keep Azure VPN Client
connected until validation and test-session cleanup finish.

## Site-to-site

Azure creates its gateway, Local Network Gateway, and IPsec/IKE connection.
The Azure gateway public IP terminates the encrypted tunnel. S2S does not use
the P2S Azure VPN Client or its Microsoft Entra user-authentication flow.
The customer configures and secures the remote gateway, PSK, BGP/routes, HA,
source filtering, and conditional DNS. The PSK is an ephemeral secure input.

## VNet peering

Azure creates reciprocal peerings. Peering is non-transitive and does not
connect a public laptop. The operator needs peering permission on both VNets.
This mode does not deploy a VPN Gateway, `GatewaySubnet`, or gateway public IP.
It still deploys Azure Firewall because the Hosted Agent's approved public
egress is independent of caller connectivity.

## DNS

Connected DNS servers conditionally forward Foundry, Search, and Key Vault
private zones to the resolver inbound IP. CIDRs must not overlap. The
`GatewaySubnet` has no NSG or default route.

The template VNet itself uses Azure-provided DNS so resources in that VNet can
resolve linked Private DNS Zones through Azure DNS. Do not configure the
Resolver inbound endpoint as the custom DNS server for the same VNet.

P2S clients and external/connected networks use the Resolver inbound endpoint
as their DNS target or conditional-forwarding destination. The export script
injects that inbound IP and scopes it to the exact Foundry, Search, and Key
Vault resource FQDNs, including their Private Link CNAMEs. Exact resource names
avoid collisions with enterprise-managed broad NRPT suffixes and avoid routing
unrelated DNS queries through the VPN resolver.

The private endpoint subnet NSG explicitly allows HTTPS from the configured P2S
address pool. This provides network reachability for connected operators and
callers; Foundry, Search, and Key Vault still require their independent Entra
RBAC permissions, and local/key authentication remains disabled.

On Windows, verify the active suffix-specific rules after connecting:

```powershell
Get-DnsClientNrptPolicy -Effective |
  Where-Object Namespace -Match 'services\.ai\.azure\.com|search\.windows\.net|vault\.azure\.net'
```

### Enterprise DNS and TLS interception

Managed endpoint security products can override Windows NRPT, intercept UDP/53,
or reset TLS to RFC1918 destinations even when the Azure VPN route is correct.
When the diagnostic pattern below is confirmed, it indicates a customer
endpoint/network policy issue rather than an Azure Private Endpoint or template
configuration issue.

Diagnostic pattern:

- `Get-NetRoute` shows the template VNet route on the Azure VPN interface.
- Gateway health shows the connected P2S client and transferred packets.
- `Test-NetConnection <private-endpoint-ip> -Port 443` succeeds.
- A TCP DNS query to the Resolver inbound IP returns the private endpoint, but a
  UDP query returns a corporate synthetic IP.
- TLS to the private endpoint is reset by the endpoint security stack.

Do not disable or bypass enterprise security software locally. Use one of these
customer-approved resolutions:

1. Configure the enterprise DNS/security service to exclude the exact resource
   FQDNs and the template VNet/P2S CIDRs from DNS/TLS interception.
2. Configure enterprise DNS conditional forwarding for the Private Link zones
   to the Resolver inbound endpoint.
3. Test from an approved unmanaged device or an Azure execution point inside
   the VNet.

Useful comparison:

```powershell
# UDP is the normal Windows DNS path.
Resolve-DnsName <resource-fqdn> -Server <resolver-ip> -Type A -DnsOnly

# If only TCP returns the private IP, a client/network DNS interceptor is likely active.
Resolve-DnsName <resource-fqdn> -Server <resolver-ip> -Type A -DnsOnly -TcpOnly
```

The template does not attempt to stop, reconfigure, or bypass customer endpoint
security agents.

For the point-to-site path, the validation script checks these generated
hostnames:

- `<account>.services.ai.azure.com`
- `<search>.search.windows.net`
- `<vault>.vault.azure.net`

Each hostname must return at least one RFC1918 address. A public address or
resolution failure means the private path is not ready.

See [Configuration reference](configuration.md) for CIDRs and
mode-specific values, and [Troubleshooting](troubleshooting.md) for symptom
routing. Microsoft documents the underlying requirements and limits:

- [Foundry networking options](https://learn.microsoft.com/azure/foundry/agents/concepts/networking-options)
- [Use a virtual network with Agent Service](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks)
- [Private Link for Microsoft Foundry](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link)
