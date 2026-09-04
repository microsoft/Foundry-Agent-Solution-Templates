targetScope = 'resourceGroup'

param searchServiceName string
param searchLocation string
@allowed(['basic', 'standard'])
param searchSku string
param principalId string
@allowed(['demo', 'byo'])
param searchMode string
param existingSearchEndpoint string
param existingSearchServiceId string

var createDemoSearch = searchMode == 'demo'
var searchServiceContributor = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
var searchIndexDataContributor = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7')

resource search 'Microsoft.Search/searchServices@2025-05-01' = if (createDemoSearch) {
  name: searchServiceName
  location: searchLocation
  identity: { type: 'SystemAssigned' }
  sku: { name: searchSku }
  properties: {
    disableLocalAuth: true
    publicNetworkAccess: 'enabled'
    hostingMode: 'Default'
  }
}
resource deployerServiceContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (createDemoSearch) {
  scope: search
  name: guid(search.id, principalId, searchServiceContributor)
  properties: { roleDefinitionId: searchServiceContributor, principalId: principalId }
}
resource deployerDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (createDemoSearch) {
  scope: search
  name: guid(search.id, principalId, searchIndexDataContributor)
  properties: { roleDefinitionId: searchIndexDataContributor, principalId: principalId }
}

output AZURE_SEARCH_ENDPOINT string = createDemoSearch ? 'https://${search.name}.search.windows.net' : existingSearchEndpoint
output AZURE_SEARCH_SERVICE_NAME string = createDemoSearch ? search.name : last(split(existingSearchServiceId, '/'))
output AZURE_SEARCH_SERVICE_ID string = createDemoSearch ? search.id : existingSearchServiceId
output AZURE_SEARCH_PRINCIPAL_ID string = createDemoSearch ? search!.identity.principalId : ''
