targetScope = 'resourceGroup'

@description('The azd environment name used to make resource names stable.')
param environmentName string = resourceGroup().name

@description('Static Web Apps is available in a subset of Azure regions.')
param location string = 'eastus2'

@description('Globally unique name for the frontend Static Web App.')
param staticWebAppName string
param backendResourceId string
param backendRegion string

resource frontend 'Microsoft.Web/staticSites@2025-03-01' = {
  name: staticWebAppName
  location: location
  tags: {
    'azd-env-name': environmentName
    'azd-service-name': 'frontend'
  }
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    allowConfigFileUpdates: true
    publicNetworkAccess: 'Enabled'
    stagingEnvironmentPolicy: 'Disabled'
  }
}

resource linkedBackend 'Microsoft.Web/staticSites/linkedBackends@2025-03-01' = {
  parent: frontend
  name: 'default'
  properties: {
    backendResourceId: backendResourceId
    region: backendRegion
  }
}

output AZURE_STATIC_WEB_APP_NAME string = frontend.name
output SERVICE_FRONTEND_ENDPOINT_URL string = 'https://${frontend.properties.defaultHostname}'
output SERVICE_FRONTEND_RESOURCE_ID string = frontend.id
