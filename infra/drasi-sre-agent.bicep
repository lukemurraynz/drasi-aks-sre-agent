targetScope = 'resourceGroup'

metadata name = 'Drasi Azure SRE Agent'
metadata description = 'Deploys an Azure SRE Agent for Drasi running on AKS by using the local AVM-style Microsoft.App/agents module.'

@description('Optional. Azure SRE Agent name.')
@minLength(2)
@maxLength(32)
param agentName string = 'drasi-sre-agent'

@description('Optional. Location for the Azure SRE Agent. Azure SRE Agent currently supports Australia East, East US 2, and Sweden Central.')
@allowed([
  'australiaeast'
  'eastus2'
  'swedencentral'
])
param location string = 'australiaeast'

@description('Optional. Log Analytics workspace name for SRE Agent telemetry. The deployment creates it when missing and reuses it when present.')
param logAnalyticsWorkspaceName string = 'drasi-law-6lmhe56rv6paa'

@description('Optional. Application Insights component name for SRE Agent telemetry.')
param applicationInsightsName string = 'appi-drasi-sre-agent'

@description('Optional. User-assigned managed identity name for Azure SRE Agent resource operations.')
param userAssignedIdentityName string = 'id-${agentName}'

@description('Optional. Azure resource IDs that the SRE Agent should treat as managed resources.')
param managedResourceIds string[] = [
  resourceGroup().id
]

@description('Optional. AKS cluster resource ID used for AKS-specific Azure Monitor activity log alerts.')
param aksClusterResourceId string = length(managedResourceIds) > 1 ? managedResourceIds[1] : ''

@description('Optional. Enables Azure SRE Agent knowledge graph resource indexing. Keep disabled when provider-side search resource provisioning fails for a target resource group.')
param enableKnowledgeGraph bool = false

@description('Optional. Deploys Azure Monitor alert rules that create incidents for Drasi platform faults.')
param deployAzureMonitorAlertRules bool = true

@description('Optional. Deploys always-firing synthetic metric alerts for end-to-end response-plan validation. Keep false outside controlled validation windows.')
param deploySyntheticRouteValidationAlerts bool = false

@description('Optional. Upgrade channel for the Azure SRE Agent. Preview enables the current workspace tools runtime used by newer SRE Agent capabilities.')
@allowed([
  'Preview'
  'Stable'
])
param upgradeChannel string = 'Preview'

@description('Optional. Enables current workspace tools and v2 agent loop capabilities where available in the Azure SRE Agent service.')
param enableCurrentAgentRuntimeFeatures bool = true

@description('Optional. Common tags.')
param tags object = {
  workload: 'drasi'
  capability: 'azure-sre-agent'
  environment: 'dev'
  managedBy: 'bicep'
}

var syntheticRouteIds = [
  'aks-admission-webhook-failure'
  'aks-cluster-autoscaler-not-scaling'
  'aks-metrics-api-unavailable'
  'aks-node-pressure-eviction'
  'aks-snat-port-exhaustion'
  'aks-apiserver-overload'
  'aks-konnectivity-tunnel-fault'
  'aks-upgrade-pdb-blocked'
  'aks-upgrade-capacity-blocked'
  'aks-upgrade-subnet-ip-exhaustion'
  'aks-upgrade-version-skew'
  'drasi-upgrade-partial-rollout'
  'drasi-source-bootstrap-race'
  'drasi-source-dependency-break'
  'k8s-finalizer-termination-stuck'
]

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource agentManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: userAssignedIdentityName
  location: location
  tags: tags
}

module sreAgent '../avm/res/app/agent/main.bicep' = {
  name: 'deploy-agent-resource-${agentName}'
  params: {
    name: agentName
    location: location
    actionConfiguration: {
      accessLevel: 'Low'
      identity: agentManagedIdentity.id
      mode: 'review'
    }
    defaultModel: {
      name: 'Automatic'
      provider: 'MicrosoftFoundry'
    }
    experimentalSettings: enableCurrentAgentRuntimeFeatures ? {
      EnableWorkspaceTools: true
      EnableV2AgentLoop: true
    } : null
    incidentManagementConfiguration: {
      connectionName: 'azmonitor'
      type: 'AzMonitor'
    }
    knowledgeGraphConfiguration: enableKnowledgeGraph ? {
      identity: agentManagedIdentity.id
      managedResources: managedResourceIds
    } : null
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: appInsights.properties.AppId
        applicationInsightsResourceId: appInsights.id
        connectionString: appInsights.properties.ConnectionString
      }
    }
    connectors: [
      {
        name: 'app-insights'
        dataConnectorType: 'AppInsights'
        dataSource: appInsights.id
        extendedProperties: {
          armResourceId: appInsights.id
          resource: {
            name: appInsights.name
          }
        }
        identity: 'system'
      }
      {
        name: 'log-analytics'
        dataConnectorType: 'LogAnalytics'
        dataSource: workspace.id
        extendedProperties: {
          armResourceId: workspace.id
          resource: {
            name: workspace.name
          }
        }
        identity: 'system'
      }
      {
        name: 'azure-monitor'
        dataConnectorType: 'MonitorClient'
        dataSource: 'n/a'
        identity: 'system'
      }
      {
        name: 'microsoft-learn'
        dataConnectorType: 'Mcp'
        dataSource: 'drasi-microsoft-learn-mcp'
        extendedProperties: {
          type: 'http'
          endpoint: 'https://learn.microsoft.com/api/mcp'
          authType: 'CustomHeaders'
          toolsVisibleToMetaAgent: [
            'microsoft-learn_microsoft_docs_search'
            'microsoft-learn_microsoft_code_sample_search'
            'microsoft-learn_microsoft_docs_fetch'
          ]
        }
        identity: ''
      }
      {
        name: 'drasi-docs'
        dataConnectorType: 'Mcp'
        dataSource: 'drasi-docs-gitmcp'
        extendedProperties: {
          type: 'http'
          endpoint: 'https://gitmcp.io/drasi-project/docs'
          authType: 'CustomHeaders'
          toolsVisibleToMetaAgent: [
            'drasi-docs_fetch_docs_documentation'
            'drasi-docs_search_docs_documentation'
            'drasi-docs_search_docs_code'
            'drasi-docs_fetch_generic_url_content'
          ]
        }
        identity: ''
      }
    ]
    mcpServers: []
    upgradeChannel: upgradeChannel
    managedIdentities: {
      userAssignedResourceIds: [
        agentManagedIdentity.id
      ]
    }
    roleAssignments: [
      {
        principalId: deployer().objectId
        principalType: 'User'
        roleDefinitionIdOrName: 'e79298df-d852-4c6d-84f9-5d13249d1e55'
      }
    ]
    lock: {
      kind: 'CanNotDelete'
      name: 'lock-${agentName}'
    }
    tags: union(tags, {
      'hidden-link: /app-insights-resource-id': appInsights.id
    })
    enableTelemetry: false
  }
}

resource sreActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (deployAzureMonitorAlertRules) {
  name: 'ag-${agentName}'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'drasi-sre'
    enabled: true
  }
}

resource alertDrasiPodCrashLoop 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (deployAzureMonitorAlertRules) {
  name: 'drasi-CrashLoopBackOff'
  location: location
  tags: tags
  properties: {
    severity: 1
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      workspace.id
    ]
    criteria: {
      allOf: [
        {
          query: '''
            KubePodInventory
            | where TimeGenerated > ago(5m)
            | where Namespace == "drasi-system"
            | where ContainerStatusReason =~ "CrashLoopBackOff"
               or PodStatus =~ "CrashLoopBackOff"
               or ContainerRestartCount >= 5
            | summarize CrashLoopingContainers = dcount(strcat(Name, "/", ContainerName))
          '''
          timeAggregation: 'Total'
          metricMeasureColumn: 'CrashLoopingContainers'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        sreActionGroup.id
      ]
    }
    autoMitigate: true
    description: 'Drasi pod CrashLoopBackOff or restart storm detected in drasi-system. Route to Azure SRE Agent drasi-platform-fault response plan.'
  }
}

resource alertAksContainerInsightsMissing 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (deployAzureMonitorAlertRules) {
  name: 'aks-container-insights-missing'
  location: location
  tags: tags
  properties: {
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT30M'
    scopes: [
      workspace.id
    ]
    criteria: {
      allOf: [
        {
          query: '''
            KubePodInventory
            | where TimeGenerated > ago(30m)
            | summarize CurrentRows=count()
            | where CurrentRows == 0
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        sreActionGroup.id
      ]
    }
    autoMitigate: true
    description: 'AKS Container Insights inventory is missing from Log Analytics. Route to Azure SRE Agent aks-monitoring-agent-fault response plan.'
  }
}

resource syntheticRouteValidationAlerts 'Microsoft.Insights/metricAlerts@2018-03-01' = [for routeId in syntheticRouteIds: if (deployAzureMonitorAlertRules && deploySyntheticRouteValidationAlerts && !empty(aksClusterResourceId)) {
  name: 'sre-e2e-${routeId}'
  location: 'global'
  tags: union(tags, {
    purpose: 'synthetic-route-validation'
  })
  properties: {
    description: 'Synthetic SRE route validation for ${routeId}. Expected route: ${routeId}. Delete after validation.'
    severity: 3
    enabled: true
    scopes: [
      aksClusterResourceId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: false
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'allocatableCpuPresent'
          criterionType: 'StaticThresholdCriterion'
          metricName: 'kube_node_status_allocatable_cpu_cores'
          timeAggregation: 'Average'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    actions: [
      {
        actionGroupId: sreActionGroup.id
      }
    ]
  }
}]

resource alertAksClusterStopped 'Microsoft.Insights/activityLogAlerts@2020-10-01' = if (deployAzureMonitorAlertRules && !empty(aksClusterResourceId)) {
  name: 'aks-cluster-stopped'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [
      subscription().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Administrative'
        }
        {
          field: 'resourceId'
          equals: aksClusterResourceId
        }
        {
          field: 'operationName'
          equals: 'Microsoft.ContainerService/managedClusters/stop/action'
        }
        {
          field: 'status'
          equals: 'Succeeded'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: sreActionGroup.id
        }
      ]
    }
    description: 'AKS cluster stop operation detected for the Drasi cluster. Route to Azure SRE Agent aks-cluster-stopped response plan.'
  }
}

@description('The deployed Azure SRE Agent resource ID.')
output agentResourceId string = sreAgent.outputs.resourceId

@description('The deployed Azure SRE Agent name.')
output agentName string = sreAgent.outputs.name

@description('The user-assigned managed identity resource ID used by the SRE Agent.')
output agentUserAssignedIdentityResourceId string = agentManagedIdentity.id

@description('The user-assigned managed identity principal ID used by the SRE Agent.')
output agentUserAssignedIdentityPrincipalId string = agentManagedIdentity.properties.principalId

@description('The system-assigned managed identity principal ID used by the SRE Agent.')
output agentSystemAssignedIdentityPrincipalId string = sreAgent.outputs.systemAssignedMIPrincipalId

@description('The Application Insights resource ID used for SRE Agent telemetry.')
output applicationInsightsResourceId string = appInsights.id

@description('The Azure SRE Agent endpoint.')
output agentEndpoint string = sreAgent.outputs.agentEndpoint
