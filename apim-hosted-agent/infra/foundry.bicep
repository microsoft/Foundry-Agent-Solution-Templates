targetScope = 'resourceGroup'

@description('Microsoft Foundry account that owns the project and RAI policy.')
param foundryAccountName string

@description('Microsoft Foundry project whose managed identity receives account access.')
param foundryProjectName string

var foundryUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '53ca6127-db72-4b80-b1b0-d745d6d5456d'
)
var guardrailPolicyName = '${foundryProjectName}-agent-tool-guardrail'
var guardrailHarmCategories = [
  'Hate'
  'Sexual'
  'Selfharm'
  'Violence'
]
var guardrailInterventionSources = [
  'PreRun'
  'PreToolCall'
  'PostToolCall'
  'PostRun'
]
var guardrailHarmFilters = flatten(map(guardrailHarmCategories, category => map(guardrailInterventionSources, source => {
  name: category
  enabled: true
  blocking: true
  severityThreshold: 'Medium'
  source: source
})))

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundryAccount
  name: foundryProjectName
}

resource guardrailPolicy 'Microsoft.CognitiveServices/accounts/raiPolicies@2026-05-15-preview' = {
  parent: foundryAccount
  name: guardrailPolicyName
  properties: {
    basePolicyName: 'Microsoft.DefaultV2'
    mode: 'Blocking'
    contentFilters: concat(guardrailHarmFilters, [
      {
        name: 'Jailbreak'
        enabled: true
        blocking: true
        source: 'PreRun'
      }
      {
        name: 'Task Adherence'
        enabled: true
        blocking: true
        action: 'BLOCKING'
        source: 'PreToolCall'
      }
      {
        name: 'Indirect Attack'
        enabled: true
        blocking: true
        source: 'PostToolCall'
      }
      {
        name: 'Protected Material Text'
        enabled: true
        blocking: true
        source: 'PostRun'
      }
      {
        name: 'Protected Material Code'
        enabled: true
        blocking: true
        source: 'PostRun'
      }
    ])
  }
}

resource projectFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryAccount
  name: guid(foundryAccount.id, foundryProject.id, foundryUserRoleDefinitionId)
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: foundryUserRoleDefinitionId
  }
}

output GUARDRAIL_POLICY_ID string = guardrailPolicy.id
output GUARDRAIL_POLICY_NAME string = guardrailPolicy.name