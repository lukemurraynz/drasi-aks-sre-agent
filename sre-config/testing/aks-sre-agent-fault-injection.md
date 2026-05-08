# AKS SRE Agent Fault Injection Matrix

Use this matrix to test whether Azure SRE Agent classifies AKS and Drasi faults by failure phase before proposing Drasi remediation. Run destructive scenarios only in a disposable cluster, a dedicated test namespace, or a dedicated test node pool. Restore immediately after each test.

## Alert Contract

Each scenario can be tested two ways:

- Controlled fault: create the condition in a disposable AKS environment and let Azure Monitor create the incident.
- Synthetic alert: create a temporary Azure Monitor alert rule whose title includes the route id, for example `sre-e2e-aks-admission-webhook-failure`, then verify response-plan routing without damaging the cluster.

The response-plan trigger string is always `sre-e2e-<route-id>`. Delete temporary alert rules after the incident thread is created and cooldown has cleared.

## Common Fault Additions

| Scenario | Fault method | Expected route | Required SRE Agent behaviour |
| --- | --- | --- | --- |
| Admission webhook unavailable or timing out | Block or scale down a non-core mutating or validating webhook in a disposable cluster, or block the service/endpoints path to it. | `aks-admission-webhook-failure` | Check MutatingWebhookConfiguration, ValidatingWebhookConfiguration, webhook Service, Endpoints, backing pods, timeout settings, and `failurePolicy` before touching Drasi or nodes. If affected pods use workload identity, check that webhook first. |
| Cluster autoscaler disabled, capped, or stuck | Disable cluster autoscaler on a user node pool, set max count too low, or create unschedulable pods in a pool that cannot scale. | `aks-cluster-autoscaler-not-scaling` | Read pending-pod events, autoscaler status, node-pool min/max settings, and autoscaler logs/status before inspecting Drasi. Treat `failed to fix node group sizes` as an autoscaler deadlock and recover by disabling and re-enabling autoscaler in review mode. |
| Metrics API or external metrics API unavailable | Disrupt metrics-server, disrupt `keda-metrics-apiserver`, or block the APIService path with policy/CNI in test. | `aks-metrics-api-unavailable` | Check APIService health for `metrics.k8s.io` and `external.metrics.k8s.io`, then serving pods and network path before blaming workload demand or Drasi performance. |
| Node-pressure eviction or pressure-driven NotReady | Fill `emptyDir`, generate log spam, or create deliberate memory/PID pressure on a dedicated test pool. | `aks-node-pressure-eviction` | Check `DiskPressure`, `MemoryPressure`, `PIDPressure`, eviction events, and kubelet behaviour before app-level remediation. |
| SNAT port exhaustion | Generate bursts of short-lived outbound connections from test jobs or a busy egress workload on a dedicated pool. | `aks-snat-port-exhaustion` | Correlate egress failures, intermittent API problems, and node diagnostics to SNAT depletion before proposing registry, DNS, or Drasi fixes. |
| API server overload or throttling | Run an intentionally noisy LIST/watch client against high-cardinality resources in a disposable cluster. | `aks-apiserver-overload` | Treat broad kubectl, controller, and watch timeouts as control-plane overload first. Identify noisy clients and reduce LIST pressure before Drasi analysis. |
| Konnectivity tunnel fault | Disrupt `konnectivity-agent` pods or block their control-plane path, especially on private clusters. | `aks-konnectivity-tunnel-fault` | If exec, logs, port-forward, Run Command, or private-cluster admin traffic degrades, test the control-plane-to-node tunnel before workload or Drasi diagnosis. |

## Upgrade And Rollout Additions

| Scenario | Fault method | Expected route | Required SRE Agent behaviour |
| --- | --- | --- | --- |
| Upgrade blocked by strict PDB or undrainable nodes | Apply a strict PDB such as `maxUnavailable: 0` to a singleton or under-replicated workload, then start an AKS upgrade in a disposable cluster. | `aks-upgrade-pdb-blocked` | Recognise node-drain failure, inspect PDBs first, and prefer PDB/replica design fixes or conservative undrainable-node handling over Drasi restarts. |
| Upgrade blocked by quota, SKU, or allocation capacity | Set high `maxSurge` in a region or subscription with tight VM-family or regional quota, or use a constrained SKU. | `aks-upgrade-capacity-blocked` | Check quota and capacity first, then lower `maxSurge`, consider `maxUnavailable`, change SKU/zone, or request quota. Treat quota/allocation errors as platform blockers. |
| Upgrade blocked by subnet IP exhaustion | Reduce subnet headroom, keep `maxPods` high, and start an upgrade that needs surge nodes. | `aks-upgrade-subnet-ip-exhaustion` | Compute IP demand with AKS guidance, then reclaim IPs, expand the subnet, lower `maxSurge`, or reduce `maxPods` before retrying. |
| Upgrade blocked by version skew or unsupported hop | Attempt a minor-version skip, or do a control-plane-only upgrade that leaves node pools too far behind. | `aks-upgrade-version-skew` | Classify as upgrade-policy failure. Validate supported versions in-region and perform sequential or full control-plane-plus-node-pool upgrades. |
| Drasi partial upgrade or failed rollback | Interrupt Drasi upgrade, or introduce readiness failures mid-rollout in `drasi-system`. | `drasi-upgrade-partial-rollout` | Watch `drasi-system` rollout, preserve Sources, Continuous Queries, Reactions, Secrets, and ConfigMaps, and use Drasi rollback if health checks fail. |

## Drasi And Kubernetes Lifecycle Edge Cases

| Scenario | Fault method | Expected route | Required SRE Agent behaviour |
| --- | --- | --- | --- |
| Drasi source and Continuous Query bootstrap race | Create a Source and immediately create a dependent Continuous Query before the Source has connected cleanly. | `drasi-source-bootstrap-race` | Confirm Source health, then delete and recreate the affected Continuous Query. Do not bounce the cluster. |
| Drasi source deleted while dependent queries remain | Delete a Source object, or remove the connectivity object it depends on, while dependent queries still exist. | `drasi-source-dependency-break` | Route as a source-lifecycle dependency failure. Identify dependent queries and restore/recreate dependencies instead of treating it as platform outage. |
| Namespace or PVC stuck terminating | Delete a namespace or PVC while a matching webhook/APIService path is broken, or while protection finalizers remain active. | `k8s-finalizer-termination-stuck` | Inspect finalizers, owner references, webhook scope, and APIService health before force deletion. |

## Synthetic Alert Examples

Use synthetic alerts when the real fault would endanger a shared cluster. The alert title must include the route id so `sre-config/response-plans/response-plans.json` can route it directly.

```powershell
$routeId = "aks-admission-webhook-failure"
$alertName = "sre-e2e-$routeId"

az monitor metrics alert create `
  --name $alertName `
  --resource-group <agent-resource-group> `
  --scopes <aks-cluster-resource-id> `
  --description "sre-e2e-$routeId synthetic route test" `
  --condition "avg kube_node_status_allocatable_cpu_cores > 0" `
  --action <sre-agent-action-group-resource-id> `
  --evaluation-frequency 1m `
  --window-size 5m `
  --severity 3 `
  --auto-mitigate false
```

Use a stable, non-invasive AKS metric so Azure Alerts Management creates a fired alert record without damaging the cluster. Delete the metric alert after the incident thread is created because `auto-mitigate false` can otherwise create duplicate fired records.

## Pass Criteria

| Check | Pass condition |
| --- | --- |
| Route | Incident lands on the expected response plan id and specialist agent. |
| Phase classification | Agent identifies creation, pending, metrics, node, network, control-plane, upgrade, or Drasi lifecycle phase before product remediation. |
| Evidence | First response includes the route-specific evidence bundle from the relevant skill. |
| Remediation safety | Any write action is review-mode only and includes exact command, risk, rollback, and validation. |
| Cleanup | Fault objects, temporary namespaces, test node-pool settings, and synthetic alert rules are removed. |

## Current Priority

Run these first because they have high false-positive risk and deterministic evidence:

1. `aks-admission-webhook-failure`
2. `aks-node-pressure-eviction`
3. `aks-upgrade-pdb-blocked`
4. `aks-upgrade-capacity-blocked`
5. `aks-upgrade-subnet-ip-exhaustion`
6. `drasi-source-bootstrap-race`
