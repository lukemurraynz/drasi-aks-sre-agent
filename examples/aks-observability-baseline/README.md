# AKS Observability Baseline for Azure SRE Agent

Use this example when adding AKS monitoring pipeline coverage to an Azure SRE Agent deployment.

This baseline is intentionally split from the generic `avm/res/app/agent` module. The AVM module deploys the SRE Agent resource, identities, connectors, diagnostics, and RBAC surface. Workload-specific alert rules, KQL, synthetic route validation, and cleanup commands belong in the consuming wrapper or environment overlay.

## Included Pattern

- Container Insights missing alert.
- DCR/DCRA diagnostic checklist.
- Synthetic route validation metric alerts, disabled by default.
- Cleanup commands for synthetic alert rules.
- Expected SRE Agent evidence checks.

## Baseline Alert

Deploy a scheduled query rule that alerts when AKS inventory disappears from Log Analytics.

```kusto
KubePodInventory
| where TimeGenerated > ago(30m)
| summarize CurrentRows=count()
| where CurrentRows == 0
```

Recommended alert settings:

| Setting | Value |
| ------- | ----- |
| Rule name | `aks-container-insights-missing` |
| Severity | `2` |
| Frequency | `PT5M` |
| Window | `PT30M` |
| Route | `aks-monitoring-agent-fault` |
| Default mode | `Review` |

The Drasi wrapper already implements this as `alertAksContainerInsightsMissing` in `infra/drasi-sre-agent.bicep`.

## Data-Path Proof

Before trusting log alerts or blaming the workload, prove the workspace has recent AKS data.

```kusto
KubePodInventory
| where TimeGenerated > ago(30m)
| summarize Rows=count(), LastSeen=max(TimeGenerated)
```

```kusto
ContainerLogV2
| where TimeGenerated > ago(30m)
| summarize Rows=count(), LastSeen=max(TimeGenerated)
```

```kusto
InsightsMetrics
| where TimeGenerated > ago(30m)
| summarize Rows=count(), LastSeen=max(TimeGenerated)
```

```kusto
Heartbeat
| where TimeGenerated > ago(30m)
| summarize Rows=count(), LastSeen=max(TimeGenerated)
```

Expected SRE Agent evidence:

- Query result for each table above.
- AKS resource ID and Log Analytics workspace resource ID.
- Current Container Insights or monitoring add-on state.
- DCR and DCRA names and resource IDs.
- `ama-logs` pod status from `kube-system`.
- Recent Azure Activity Log changes for monitoring add-ons, workspace, DCRs, or AKS.

## DCR/DCRA Checklist

Use this checklist when `ama-logs` is running but `KubePodInventory` or `ContainerLogV2` has no recent rows.

1. Confirm the AKS cluster is associated with the expected Log Analytics workspace.
1. List data collection rules linked to the cluster.
1. List data collection rule associations scoped to the cluster.
1. Confirm the DCR destination points to the expected workspace.
1. Check `ama-logs` pods for restart loops, image pull failures, or config errors.
1. Check Azure Activity Log for recent DCR, DCRA, workspace, or monitoring add-on changes.
1. Keep remediation in Review mode unless the operator has approved add-on or DCR recreation.

Useful Azure CLI commands:

```bash
az monitor data-collection rule association list \
  --scope "$AKS_CLUSTER_RESOURCE_ID" \
  --query "[].{name:name,id:id,dataCollectionRuleId:dataCollectionRuleId}"
```

```bash
az monitor data-collection rule list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[].{name:name,id:id,destinations:properties.destinations}"
```

```bash
kubectl get pods -n kube-system -l rsName=ama-logs
kubectl logs -n kube-system -l rsName=ama-logs --tail=200
```

## Synthetic Route Validation

Synthetic alerts are for validation windows only. They must remain disabled by default.

In this repo, enable them only by setting:

```bash
azd env set DEPLOY_SYNTHETIC_ROUTE_VALIDATION_ALERTS true
azd provision
```

The Drasi wrapper uses `deploySyntheticRouteValidationAlerts = false` by default and creates metric alerts named:

```text
sre-e2e-<route-id>
```

Expected SRE Agent evidence:

- Alert title contains the route ID.
- Response plan matches the expected route.
- Agent states that the alert is synthetic validation, not a real fault.
- Agent gathers the route-specific first evidence set.
- Agent avoids production remediation for synthetic incidents.

## Cleanup

Delete synthetic route validation alerts after testing.

```bash
az monitor metrics alert list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?starts_with(name, 'sre-e2e-')].name" \
  --output tsv |
while read -r alert_name; do
  az monitor metrics alert delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "$alert_name"
done
```

Disable the deployment toggle before the next provision:

```bash
azd env set DEPLOY_SYNTHETIC_ROUTE_VALIDATION_ALERTS false
```

## Autonomy Boundary

Keep these actions approval-gated:

- AKS monitoring add-on changes.
- DCR or DCRA recreation.
- Node-pool scaling or autoscaler changes.
- Upgrade retries or surge changes.
- Finalizer removal.
- Network policy, route table, firewall, or private DNS changes.

The only recommended autonomous AKS remediation in this blueprint is:

```text
aks-cluster-stopped -> az aks start
```

Use it only when the route is pre-approved, scoped to the managed cluster, and followed by a validation check that the cluster reaches `Running`.
