# App Agent

This module deploys a `Microsoft.App/agents` resource by using API version `2025-05-01-preview`.

The module follows the repository `bicep-avm-authoring` guidance for the AVM resource module interface:

- `name`, `location`, `tags`, and typed resource-specific configuration.
- User-assigned managed identity support for SRE Agent resource operations.
- Connector child resource deployment for ARM-supported SRE Agent connectors.
- Role assignments, diagnostic settings, resource locks, telemetry, and required outputs.
- Exported user-defined types for complex parameters.

> This README is a checked-in starter. Regenerate it with the AVM Bicep documentation tooling before publishing the module.

## Minimum Example

```bicep
resource agentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-sreagent01'
  location: resourceGroup().location
}

module agent 'br/public:avm/res/app/agent:0.1.0' = {
  name: 'agentDeployment'
  params: {
    name: 'sreagent01'
    actionAccessLevel: 'Low'
    actionIdentity: agentIdentity.id
    actionMode: 'review'
    knowledgeGraphConfiguration: {
      identity: agentIdentity.id
      managedResources: [
        resourceGroup().id
      ]
    }
    connectors: [
      {
        name: 'azure-monitor'
        dataConnectorType: 'MonitorClient'
        dataSource: 'n/a'
        identity: 'system'
      }
      {
        name: 'microsoft-learn'
        dataConnectorType: 'Mcp'
        dataSource: 'microsoft-learn-mcp'
        extendedProperties: {
          type: 'http'
          endpoint: 'https://learn.microsoft.com/api/mcp'
          authType: 'CustomHeaders'
        }
        identity: ''
      }
    ]
    managedIdentities: {
      userAssignedResourceIds: [
        agentIdentity.id
      ]
    }
  }
}
```

## Azure Monitor Incident Platform Example

Use the incident management configuration with managed resources and Azure Monitor connectors in the wrapper deployment. Keep workload-specific alert rules outside this generic module.

```bicep
module agent 'br/public:avm/res/app/agent:0.1.0' = {
  name: 'sreAgentDeployment'
  params: {
    name: 'sreagent01'
    actionAccessLevel: 'Low'
    actionIdentity: agentIdentity.id
    actionMode: 'review'
    incidentManagementConfiguration: {
      connectionName: 'azmonitor'
      type: 'AzMonitor'
    }
    knowledgeGraphConfiguration: {
      identity: agentIdentity.id
      managedResources: [
        resourceGroup().id
        aksCluster.id
      ]
    }
    connectors: [
      {
        name: 'azure-monitor'
        dataConnectorType: 'MonitorClient'
        dataSource: 'n/a'
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
    ]
    managedIdentities: {
      userAssignedResourceIds: [
        agentIdentity.id
      ]
    }
  }
}
```

## MCP Connector Example

For MCP connectors, connector health is not enough. Include `toolsVisibleToMetaAgent` when the agent must be able to call specific tools from the meta-agent.

```bicep
module agent 'br/public:avm/res/app/agent:0.1.0' = {
  name: 'sreAgentDeployment'
  params: {
    name: 'sreagent01'
    connectors: [
      {
        name: 'microsoft-learn'
        dataConnectorType: 'Mcp'
        dataSource: 'microsoft-learn-mcp'
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
    ]
    managedIdentities: {
      userAssignedResourceIds: [
        agentIdentity.id
      ]
    }
  }
}
```

## Notes

- The agent name must match the Azure schema pattern: start with a letter, end with a letter or number, and use only letters, numbers, and hyphens.
- The agent resource uses both `SystemAssigned` and `UserAssigned` identity. The system-assigned identity is internal; set `actionConfiguration.identity` and `knowledgeGraphConfiguration.identity` to the user-assigned managed identity resource ID.
- Prefer `actionAccessLevel`, `actionIdentity`, and `actionMode` for simple deployments. Use `actionConfiguration` when you need to pass the provider object directly; when supplied, it takes precedence over the first-class action parameters.
- Assign `SRE Agent Administrator` on the agent resource to the deploying operator or owning group.
- Use scoped permissions and production rollout in Review mode before autonomous operation.
- Sensitive connection values are modeled as secure properties on the exported user-defined types.
- Use the `connectors` parameter for generic ARM-supported connector child resources such as Azure Monitor, Application Insights, Log Analytics, and MCP HTTP endpoints.
- Keep tenant-sensitive or data-plane-only setup outside this resource module until the provider surface is stable. This includes custom skills, subagents, response plans, scheduled tasks, enabled MCP tool selection after provisioning, and workload-specific runbooks.
- Keep workload alerts in the consuming wrapper module. The AVM module should deploy the generic agent, identities, connectors, diagnostics, and RBAC surface; AKS, Drasi, Container Apps, or application alert rules belong with the workload.
