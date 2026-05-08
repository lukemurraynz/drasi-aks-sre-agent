targetScope = 'resourceGroup'

metadata name = 'Using only defaults'
metadata description = 'This instance deploys the module with the minimum set of required parameters.'

@description('Optional. Token used to make the resource name unique.')
param nameToken string = uniqueString(resourceGroup().id, deployment().name)

resource agentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: take('id-agent-defaults-${nameToken}', 128)
  location: resourceGroup().location
}

module testDeployment '../../../main.bicep' = {
  name: 'agent-defaults-${substring(nameToken, 0, 6)}'
  params: {
    name: take('aa${nameToken}', 32)
    managedIdentities: {
      userAssignedResourceIds: [
        agentIdentity.id
      ]
    }
    enableTelemetry: false
  }
}
