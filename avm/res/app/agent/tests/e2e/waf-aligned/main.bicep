targetScope = 'resourceGroup'

metadata name = 'WAF-aligned'
metadata description = 'This instance deploys the module with safer operational defaults for production-style validation.'

@description('Optional. Token used to make the resource name unique.')
param nameToken string = uniqueString(resourceGroup().id, deployment().name)

resource agentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: take('id-agent-waf-${nameToken}', 128)
  location: resourceGroup().location
}

module testDeployment '../../../main.bicep' = {
  name: 'agent-waf-${substring(nameToken, 0, 6)}'
  params: {
    name: take('aw${nameToken}', 32)
    actionConfiguration: {
      accessLevel: 'Low'
      identity: agentIdentity.id
      mode: 'review'
    }
    defaultModel: {
      name: 'gpt-5'
      provider: 'MicrosoftFoundry'
    }
    knowledgeGraphConfiguration: {
      identity: agentIdentity.id
      managedResources: [
        resourceGroup().id
      ]
    }
    managedIdentities: {
      userAssignedResourceIds: [
        agentIdentity.id
      ]
    }
    lock: {
      kind: 'CanNotDelete'
    }
    tags: {
      environment: 'waf'
      workload: 'sre'
    }
    enableTelemetry: false
  }
}
