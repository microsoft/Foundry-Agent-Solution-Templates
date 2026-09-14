targetScope = 'subscription'

@description('Existing resource group created by the Foundry infrastructure layer.')
param resourceGroupName string

@description('Azure AI Search service name.')
param searchServiceName string = 'srch-${take(uniqueString(subscription().id, resourceGroupName), 12)}'
@description('Azure region for Search; may differ from the Foundry project when regional capacity requires it.')
param searchLocation string = 'westus2'
@allowed(['basic', 'standard'])
param searchSku string = 'basic'
@description('Provisioning principal object ID.')
param principalId string
@allowed(['demo', 'byo'])
param searchMode string = 'demo'
@description('Existing Search endpoint required in byo mode.')
param existingSearchEndpoint string = ''
@description('Existing Search resource ID required in byo mode.')
param existingSearchServiceId string = ''

module search './search-service.bicep' = {
  name: 'enterprise-knowledge-search'
  scope: resourceGroup(resourceGroupName)
  params: {
    searchServiceName: searchServiceName
    searchLocation: searchLocation
    searchSku: searchSku
    principalId: principalId
    searchMode: searchMode
    existingSearchEndpoint: existingSearchEndpoint
    existingSearchServiceId: existingSearchServiceId
  }
}

output AZURE_SEARCH_ENDPOINT string = search.outputs.AZURE_SEARCH_ENDPOINT
output AZURE_SEARCH_SERVICE_NAME string = search.outputs.AZURE_SEARCH_SERVICE_NAME
output AZURE_SEARCH_SERVICE_ID string = search.outputs.AZURE_SEARCH_SERVICE_ID
output AZURE_SEARCH_PRINCIPAL_ID string = search.outputs.AZURE_SEARCH_PRINCIPAL_ID
