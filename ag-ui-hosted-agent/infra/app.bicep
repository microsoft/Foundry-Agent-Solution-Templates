targetScope = 'subscription'

@description('azd environment name; seeds resource names.')
param environmentName string
@description('Region for the Container Apps resources.')
param location string
@description('Resource group created by the Foundry layer.')
param resourceGroupName string
param foundryAccountName string
param foundryProjectName string
param foundryProjectEndpoint string
@description('Hosted agent name; must match the agent service name in azure.yaml.')
param agentName string = 'claims-triage'
param webExists bool = false
param gatewayExists bool = false

module resources 'resources.bicep' = {
  name: 'ag-ui-app'
  scope: resourceGroup(resourceGroupName)
  params: {
    environmentName: environmentName
    location: location
    foundryAccountName: foundryAccountName
    foundryProjectName: foundryProjectName
    foundryProjectEndpoint: foundryProjectEndpoint
    agentName: agentName
    webExists: webExists
    gatewayExists: gatewayExists
  }
}

output AZURE_CONTAINER_REGISTRY_ENDPOINT string = resources.outputs.registryEndpoint
output WEB_URL string = resources.outputs.webUrl
output WEB_APP_REGISTRATION_CLIENT_ID string = resources.outputs.appRegistrationClientId
