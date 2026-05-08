metadata name = 'App Agent'
metadata description = 'This module deploys a Microsoft.App/agents resource.'

import {
  diagnosticSettingFullType
  lockType
  roleAssignmentType
} from 'br/public:avm/utl/types/avm-common-types:0.6.1'

@description('Required. Name of the agent.')
@minLength(2)
@maxLength(32)
param name string

@description('Optional. Location for all resources.')
param location string = resourceGroup().location

@description('Optional. Legacy agent identity configuration. Not used by the current Microsoft.App/agents preview API.')
param agentIdentity agentIdentityType?

@description('Optional. Configuration for actions the agent can perform.')
param actionConfiguration actionConfigurationType?

@allowed([
  'High'
  'Low'
])
@description('Optional. First-class action access level. Ignored when actionConfiguration is supplied.')
param actionAccessLevel string?

@description('Optional. First-class managed identity resource ID used by actions. Ignored when actionConfiguration is supplied.')
param actionIdentity string?

@allowed([
  'autonomous'
  'readOnly'
  'review'
  'Autonomous'
  'ReadOnly'
  'Review'
])
@description('Optional. First-class action execution mode. Ignored when actionConfiguration is supplied.')
param actionMode string?

@description('Optional. The agent space ID referenced by the agent.')
param agentSpaceId string?

@description('Optional. Default AI model configuration for the agent.')
param defaultModel defaultModelType?

@description('Optional. Experimental feature flags for the agent.')
param experimentalSettings object?

@description('Optional. Incident management configuration.')
param incidentManagementConfiguration incidentManagementConfigurationType?

@description('Optional. Knowledge graph configuration for the agent.')
param knowledgeGraphConfiguration knowledgeGraphConfigurationType?

@description('Optional. MCP server configuration for the agent.')
param mcpServers array?

@description('Optional. Connector child resources to deploy under the agent. Use for ARM-supported connectors such as AppInsights, LogAnalytics, MonitorClient, and MCP endpoints.')
param connectors connectorType[]?

@description('Optional. Log configuration for the agent.')
param logConfiguration logConfigurationType?

@allowed([
  'Preview'
  'Stable'
])
@description('Optional. The upgrade channel of the agent.')
param upgradeChannel string = 'Stable'

@description('Optional. Tags of the resource.')
param tags tagsType?

@description('Required. User-assigned managed identities for this resource. Azure SRE Agent requires a user-assigned managed identity for resource operations and also creates an internal system-assigned identity.')
param managedIdentities managedIdentityUserAssignedType

@description('Optional. Array of role assignments to create.')
param roleAssignments roleAssignmentType[]?

@description('Optional. The diagnostic settings of the service.')
param diagnosticSettings diagnosticSettingFullType[]?

@description('Optional. The lock settings of the service.')
param lock lockType?

@description('Optional. Enable/disable usage telemetry for this module.')
param enableTelemetry bool = true

var formattedUserAssignedIdentities = reduce(
  map(managedIdentities.userAssignedResourceIds, id => { '${id}': {} }),
  {},
  (current, next) => union(current, next)
)

var identity = {
  type: 'SystemAssigned, UserAssigned'
  userAssignedIdentities: formattedUserAssignedIdentities
}

var hasFirstClassActionConfiguration = !empty(actionAccessLevel) || !empty(actionIdentity) || !empty(actionMode)
var actionConfigurationFromFirstClass = hasFirstClassActionConfiguration ? union(
  !empty(actionAccessLevel) ? { accessLevel: actionAccessLevel } : {},
  !empty(actionIdentity) ? { identity: actionIdentity } : {},
  !empty(actionMode) ? { mode: actionMode } : {}
) : {}
var effectiveActionConfiguration = !empty(actionConfiguration) ? actionConfiguration : actionConfigurationFromFirstClass

var formattedRoleAssignments = [
  for roleAssignment in (roleAssignments ?? []): union(roleAssignment, {
    roleDefinitionId: contains(roleAssignment.roleDefinitionIdOrName, '/providers/Microsoft.Authorization/roleDefinitions/')
      ? roleAssignment.roleDefinitionIdOrName
      : (contains(roleAssignment.roleDefinitionIdOrName, '-') ? subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleAssignment.roleDefinitionIdOrName) : roleDefinitions(roleAssignment.roleDefinitionIdOrName).id)
  })
]

var properties = union(
  {
    upgradeChannel: upgradeChannel
  },
  !empty(agentIdentity) ? { agentIdentity: agentIdentity } : {},
  !empty(effectiveActionConfiguration) ? { actionConfiguration: effectiveActionConfiguration } : {},
  !empty(agentSpaceId) ? { agentSpaceId: agentSpaceId } : {},
  !empty(defaultModel) ? { defaultModel: defaultModel } : {},
  !empty(experimentalSettings) ? { experimentalSettings: experimentalSettings } : {},
  !empty(incidentManagementConfiguration) ? { incidentManagementConfiguration: incidentManagementConfiguration } : {},
  !empty(knowledgeGraphConfiguration) ? { knowledgeGraphConfiguration: knowledgeGraphConfiguration } : {},
  !empty(mcpServers) ? { mcpServers: mcpServers } : {},
  !empty(logConfiguration) ? { logConfiguration: logConfiguration } : {}
)

#disable-next-line no-deployments-resources
resource avmTelemetry 'Microsoft.Resources/deployments@2024-03-01' = if (enableTelemetry) {
  name: take(
    '46d3xbcp.res.app-agent.${replace('-..--..-', '.', '-')}.${substring(uniqueString(deployment().name, location), 0, 4)}',
    64
  )
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      resources: []
      outputs: {
        telemetry: {
          type: 'String'
          value: 'For more information, see https://aka.ms/avm/TelemetryInfo'
        }
      }
    }
  }
}

resource agent 'Microsoft.App/agents@2025-05-01-preview' = {
  name: name
  location: location
  identity: any(identity)
  tags: any(tags)
  properties: properties
}

#disable-next-line BCP081
resource agentConnectors 'Microsoft.App/agents/connectors@2025-05-01-preview' = [
  for connector in (connectors ?? []): {
    parent: agent
    name: connector.name
    properties: {
      dataConnectorType: connector.dataConnectorType
      dataSource: connector.dataSource
      extendedProperties: connector.?extendedProperties
      identity: connector.?identity
    }
  }
]

resource agentLock 'Microsoft.Authorization/locks@2020-05-01' = if (!empty(lock ?? {}) && lock.?kind != 'None') {
  name: lock.?name ?? 'lock-${name}'
  scope: agent
  properties: {
    level: lock.?kind ?? ''
    notes: lock.?notes ?? (lock.?kind == 'CanNotDelete' ? 'Cannot delete resource or child resources.' : 'Cannot delete or modify the resource or child resources.')
  }
}

resource agentRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleAssignment in formattedRoleAssignments: {
    name: roleAssignment.?name ?? guid(agent.id, roleAssignment.principalId, roleAssignment.roleDefinitionId)
    scope: agent
    properties: {
      roleDefinitionId: roleAssignment.roleDefinitionId
      principalId: roleAssignment.principalId
      description: roleAssignment.?description
      principalType: roleAssignment.?principalType
      condition: roleAssignment.?condition
      conditionVersion: !empty(roleAssignment.?condition) ? (roleAssignment.?conditionVersion ?? '2.0') : null
      delegatedManagedIdentityResourceId: roleAssignment.?delegatedManagedIdentityResourceId
    }
  }
]

#disable-next-line use-recent-api-versions
resource agentDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = [
  for diagnosticSetting in (diagnosticSettings ?? []): {
    name: diagnosticSetting.?name ?? '${name}-diagnosticSettings'
    scope: agent
    properties: {
      storageAccountId: diagnosticSetting.?storageAccountResourceId
      workspaceId: diagnosticSetting.?workspaceResourceId
      eventHubAuthorizationRuleId: diagnosticSetting.?eventHubAuthorizationRuleResourceId
      eventHubName: diagnosticSetting.?eventHubName
      logs: [
        for group in (diagnosticSetting.?logCategoriesAndGroups ?? [
          {
            categoryGroup: 'allLogs'
          }
        ]): {
          category: group.?category
          categoryGroup: group.?categoryGroup
          enabled: group.?enabled ?? true
        }
      ]
      metrics: [
        for group in (diagnosticSetting.?metricCategories ?? [
          {
            category: 'AllMetrics'
          }
        ]): {
          category: group.category
          enabled: group.?enabled ?? true
          timeGrain: null
        }
      ]
      marketplacePartnerId: diagnosticSetting.?marketplacePartnerResourceId
      logAnalyticsDestinationType: diagnosticSetting.?logAnalyticsDestinationType
    }
  }
]

@description('The resource ID of the deployed resource.')
output resourceId string = agent.id

@description('The name of the deployed resource.')
output name string = agent.name

@description('The resource group the resource was deployed into.')
output resourceGroupName string = resourceGroup().name

@description('The location the resource was deployed into.')
output location string = agent.location

@description('The resource IDs of the user-assigned managed identities attached to the agent.')
output userAssignedMIResourceIds string[] = map(items(agent.?identity.?userAssignedIdentities ?? {}), identityItem => identityItem.key)

@description('The principal ID of the system-assigned managed identity attached to the agent.')
output systemAssignedMIPrincipalId string = agent.identity.principalId

@description('The Azure SRE Agent endpoint.')
output agentEndpoint string = agent.properties.agentEndpoint

@description('The resource IDs of the deployed connector child resources.')
output connectorResourceIds string[] = [
  for connector in (connectors ?? []): resourceId('Microsoft.App/agents/connectors', name, connector.name)
]

@export()
@description('Agent action execution configuration.')
type actionConfigurationType = {
  @description('Optional. The access level of the action.')
  accessLevel: ('High' | 'Low')?

  @description('Optional. The identity used by the action.')
  identity: string?

  @description('Optional. The execution mode of the action.')
  mode: ('autonomous' | 'readOnly' | 'review' | 'Autonomous' | 'ReadOnly' | 'Review')?
}

@export()
@description('Agent identity configuration for accessing resources.')
type agentIdentityType = {
  @description('Required. Initial sponsor group ID.')
  initialSponsorGroupId: string
}

@export()
@description('Application Insights configuration for agent logs.')
type applicationInsightsConfigurationType = {
  @description('Optional. The Application ID for the Application Insights resource.')
  appId: string?

  @description('Optional. The resource ID for the Application Insights resource.')
  applicationInsightsResourceId: string?

  @secure()
  @description('Optional. The connection string for the Application Insights resource.')
  connectionString: string?
}

@export()
@description('Agent connector child resource configuration.')
type connectorType = {
  @description('Required. Connector child resource name.')
  name: string

  @description('Required. Connector type, for example AppInsights, LogAnalytics, MonitorClient, or Mcp.')
  dataConnectorType: string

  @description('Required. Connector data source. Some connector types use an Azure resource ID; others use a logical source value.')
  dataSource: string

  @description('Optional. Connector-specific extended properties.')
  extendedProperties: object?

  @description('Optional. Connector identity setting. Built-in Azure connectors often use system; external MCP connectors can use an empty string depending on provider behavior.')
  identity: string?
}

@export()
@description('MCP HTTP connector extended properties helper. Use inside connectorType.extendedProperties for MCP connectors that need explicit tool visibility.')
type mcpConnectorExtendedPropertiesType = {
  @description('Required. MCP transport type.')
  type: 'http'

  @description('Required. MCP server endpoint.')
  endpoint: string

  @description('Optional. Authentication type used by the connector.')
  authType: string?

  @description('Optional. Tool names visible to the meta-agent. Use this when connector health alone is not enough to activate tools for the agent.')
  toolsVisibleToMetaAgent: string[]?
}

@export()
@description('Azure resource connector extended properties helper. Use inside connectorType.extendedProperties for ARM-backed connectors such as Application Insights and Log Analytics.')
type azureResourceConnectorExtendedPropertiesType = {
  @description('Required. Azure resource ID backing the connector.')
  armResourceId: string

  @description('Optional. Portal display metadata for the backing resource.')
  resource: {
    @description('Optional. Backing resource name.')
    name: string?
  }?
}

@export()
@description('Default AI model configuration for the agent.')
type defaultModelType = {
  @description('Optional. Model name, for example gpt-5, claude-opus-4-5, or claude-sonnet-4-5.')
  name: string?

  @description('Optional. AI provider name, for example MicrosoftFoundry or Anthropic.')
  provider: string?
}

@export()
@description('Incident management system connection configuration.')
type incidentManagementConfigurationType = {
  @secure()
  @description('Optional. The key for the connection.')
  connectionKey: string?

  @description('Optional. The name of the connection.')
  connectionName: string?

  @description('Optional. The URL of the connection.')
  connectionUrl: string?

  @description('Optional. The user for the connection.')
  oboUser: string?

  @description('Optional. The type of incident management system.')
  type: string?
}

@export()
@description('Knowledge graph configuration for the agent.')
type knowledgeGraphConfigurationType = {
  @description('Optional. The identity used to access the knowledge graph.')
  identity: string?

  @description('Optional. The list of resources managed by the agent.')
  managedResources: string[]?
}

@export()
@description('Log configuration for the agent.')
type logConfigurationType = {
  @description('Optional. Application Insights configuration.')
  applicationInsightsConfiguration: applicationInsightsConfigurationType?
}

@export()
@description('Tags to apply to the resource.')
type tagsType = {
  @description('Optional. A tag name and value pair.')
  *: string
}

@export()
@description('User-assigned managed identities for Azure SRE Agent.')
type managedIdentityUserAssignedType = {
  @minLength(1)
  @description('Required. The user-assigned managed identity resource IDs to assign to the agent.')
  userAssignedResourceIds: string[]
}
