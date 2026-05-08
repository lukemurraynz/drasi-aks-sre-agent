targetScope = 'resourceGroup'

metadata name = 'Drasi Azure SRE Agent Baseline RBAC'
metadata description = 'Assigns scoped Azure roles to the Azure SRE Agent identities for Drasi AKS operations.'

@description('Required. Existing AKS cluster name that hosts Drasi.')
param aksClusterName string

@description('Required. Principal ID of the SRE Agent user-assigned managed identity.')
param userAssignedPrincipalId string

@description('Required. Principal ID of the SRE Agent system-assigned managed identity.')
param systemAssignedPrincipalId string

var readerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
var monitoringReaderRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
var logAnalyticsReaderRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
var aksClusterUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4abbcc35-e782-43d8-92c5-2d3f1bd2253f')
var aksRbacClusterAdminRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b')

var rgReaderRoleDefinitionIds = [
  readerRoleDefinitionId
  monitoringReaderRoleDefinitionId
  logAnalyticsReaderRoleDefinitionId
]

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
}

resource userAssignedRgRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleDefinitionId in rgReaderRoleDefinitionIds: {
    name: guid(resourceGroup().id, userAssignedPrincipalId, roleDefinitionId)
    properties: {
      roleDefinitionId: roleDefinitionId
      principalId: userAssignedPrincipalId
      principalType: 'ServicePrincipal'
    }
  }
]

resource systemAssignedRgRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleDefinitionId in rgReaderRoleDefinitionIds: {
    name: guid(resourceGroup().id, systemAssignedPrincipalId, roleDefinitionId)
    properties: {
      roleDefinitionId: roleDefinitionId
      principalId: systemAssignedPrincipalId
      principalType: 'ServicePrincipal'
    }
  }
]

resource userAssignedAksClusterUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, userAssignedPrincipalId, aksClusterUserRoleDefinitionId)
  scope: aksCluster
  properties: {
    roleDefinitionId: aksClusterUserRoleDefinitionId
    principalId: userAssignedPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource userAssignedAksRbacClusterAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, userAssignedPrincipalId, aksRbacClusterAdminRoleDefinitionId)
  scope: aksCluster
  properties: {
    roleDefinitionId: aksRbacClusterAdminRoleDefinitionId
    principalId: userAssignedPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource systemAssignedAksRbacClusterAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, systemAssignedPrincipalId, aksRbacClusterAdminRoleDefinitionId)
  scope: aksCluster
  properties: {
    roleDefinitionId: aksRbacClusterAdminRoleDefinitionId
    principalId: systemAssignedPrincipalId
    principalType: 'ServicePrincipal'
  }
}
