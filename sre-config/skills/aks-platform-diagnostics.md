## AKS Platform Diagnostics For Drasi

Primary scope:

- Resource group: `@@RG@@`
- AKS cluster: `@@AKS@@`
- AKS resource ID: `@@AKS_ID@@`
- Drasi namespace: `@@DRASI_NS@@`

Use this skill when Drasi symptoms appear to come from AKS platform health: node readiness, DNS, Cilium networking, private cluster connectivity, Dapr control plane, Azure Monitor agent, Gatekeeper policy, workload identity, storage attach/mount, or cluster upgrades.

## Operating rules

1. Start from cluster and node health before restarting Drasi workloads.
2. Use `az aks command invoke`; do not assume direct kubectl access.
3. Separate AKS platform failures from Drasi runtime failures. If only one Drasi component is failing and platform checks are clean, hand back to Drasi runtime diagnostics.
4. Keep all remediations in review mode with rollback and blast-radius notes.
5. In incident threads, do not narrate tool discovery or internal skill loading. Run the first evidence bundle, then summarize.
6. Every `kubectl get` command must include `-o wide`, `-o json`, or another explicit output option.

## Incident fast path

For AKS cluster stopped alerts or any failed Kubernetes access where cluster power is unknown, check control-plane state before running `az aks command invoke`:

```bash
az aks show -g @@RG@@ -n @@AKS@@ --query "{provisioningState:provisioningState,powerState:powerState.code,kubernetesVersion:kubernetesVersion}" -o json
```

If `powerState` is `Stopped`, do not attempt Kubernetes commands. Treat the outage as an administrative AKS stop until activity logs or operator context prove otherwise. For the `aks-cluster-stopped` route only, the operator has pre-approved autonomous start of the same managed cluster:

```bash
az aks start -g @@RG@@ -n @@AKS@@
```

This exception does not authorize node-pool scale-out, upgrade changes, networking changes, or cluster recreation. Validate by waiting for `powerState` to become `Running`, then run the baseline commands below.
Use AKS Run Command for Kubernetes validation, for example:

```bash
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get nodes -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get pods -n @@DRASI_NS@@ -o wide"
```

For Azure Monitor incidents that mention CoreDNS, kube-dns, DNS, node readiness, Dapr, or Cilium, run a deterministic evidence bundle before broad exploration.

For CoreDNS or kube-dns unavailable alerts:

```bash
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get deployment coredns -n kube-system -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get service kube-dns -n kube-system -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get endpoints kube-dns -n kube-system -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get nodes -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get events -n kube-system --sort-by=.lastTimestamp -o wide"
```

If the `coredns` deployment has desired replicas set to `0`, the strongest cause candidate is an explicit scale-to-zero action or controller change. Check HPA before proposing a restore:

```bash
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get hpa -A -o wide"
```

Review-mode remediation when no controller conflict exists:

```bash
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl scale deployment coredns -n kube-system --replicas=2"
```

Validate with deployment availability, kube-dns endpoints, and node/pod readiness.

## Kepner-Tregoe investigation frame

Use Kepner-Tregoe where the platform fault is not obvious:

1. Situation appraisal: identify urgency, impacted Drasi capability, platform layer, and containment need.
2. Problem specification: define what, where, when, and extent. Include nodes/namespaces/components that are healthy or not implicated as `IS NOT` comparisons.
3. Distinction and change analysis: compare healthy and unhealthy nodes/pods/system components and inspect recent AKS, node, policy, DNS, CNI, Dapr, identity, and storage changes.
4. Probable cause: test each candidate against telemetry and Kubernetes evidence.
5. Decision analysis: choose the lowest-risk reversible action that addresses the cause.
6. Potential problem analysis: document rollback triggers, monitoring signals, and validation criteria before proposing writes.

## Baseline commands

```bash
az aks show -g @@RG@@ -n @@AKS@@ --query "{provisioningState:provisioningState,powerState:powerState.code,kubernetesVersion:kubernetesVersion,privateCluster:apiServerAccessProfile.enablePrivateCluster,azureRBAC:azureProfile.enableAzureRBAC}" -o json
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get nodes -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get pods -n kube-system -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get pods -n dapr-system -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get events -A --sort-by=.lastTimestamp -o wide"
```

## Checks

- CoreDNS and DNS latency for source databases, Key Vault, registry, and private endpoints.
- Cilium and Azure CNI health before calling an application incident.
- Dapr sidecar injector, placement, scheduler, sentry, and operator health.
- Azure Monitor agent pods so SRE Agent telemetry queries are trustworthy.
- Gatekeeper constraint failures that could block Drasi resources.
- Node pressure, image pulls, storage mounts, and workload identity token projection.
- AKS Run Command helper-pod scheduling, especially when user pools are at zero or taints block generic pods.
- Private cluster access assumptions: do not diagnose DNS/egress from local `kubectl` failure until `az aks show` and AKS Run Command evidence are checked.
- Alert coverage gaps: if an incident came through the catch-all response plan, identify whether a narrower response plan should be added after the cause is confirmed.

## Phase-based AKS false-positive routes

Route by failure phase before routing by product. Creation-time failures usually mean admission, identity, policy, or API-server health. Pending-time failures usually mean scheduling, capacity, subnet, or autoscaler. Broad post-creation failures usually mean node pressure, network, tunnel, SNAT, or control-plane health. Only hand back to Drasi runtime diagnostics after these checks are clean.

| Route | First evidence bundle | Required behaviour |
| --- | --- | --- |
| `aks-admission-webhook-failure` | `kubectl get mutatingwebhookconfiguration,validatingwebhookconfiguration -o wide`; `kubectl get svc,endpoints -A -o wide`; `kubectl get pods -A -o wide`; describe the named webhook service and backing pods. | Check webhook configuration, service, endpoints, backing pods, timeout settings, and `failurePolicy` before touching Drasi or nodes. If affected pods use workload identity, check `azure-workload-identity-webhook` first and treat labeled workload-identity pods as fail-closed candidates. |
| `aks-cluster-autoscaler-not-scaling` | Pending pod events, `kubectl get nodes -o wide`, `az aks nodepool list`, and cluster autoscaler status/log signals from Azure Monitor or kube-system logs when available. | Read pending-pod events, node-pool min/max, autoscaler enablement, backoff, and `failed to fix node group sizes` before inspecting Drasi. Treat that documented state as an autoscaler deadlock: propose disabling and re-enabling autoscaler in review mode rather than retrying workload operations. |
| `aks-metrics-api-unavailable` | `kubectl get apiservice v1beta1.metrics.k8s.io v1beta1.external.metrics.k8s.io -o json`; `kubectl get pods -A -l k8s-app=metrics-server -o wide`; `kubectl get pods -A -l app=keda-operator-metrics-apiserver -o wide`. | Check APIService health for `metrics.k8s.io` and `external.metrics.k8s.io`, then serving pods and network path. If KEDA is involved, test whether the APIService is `False` because of network, CNI, or service endpoint conditions. |
| `aks-node-pressure-eviction` | `kubectl describe node <node>`; `kubectl get events -A --field-selector reason=Evicted -o wide`; `kubectl top nodes` when metrics API works. | Check `DiskPressure`, `MemoryPressure`, `PIDPressure`, eviction events, kubelet messages, and node readiness before app-level remediation. Pressure evictions are kubelet actions and can make Drasi look broken without Drasi being the cause. |
| `aks-snat-port-exhaustion` | AKS node resource group load balancer SNAT metrics, node outbound failure logs, affected node pool, egress-heavy pods, and DNS/API intermittency timing. | Correlate intermittent egress failures, API problems, and node diagnostics to SNAT depletion. Prefer outbound-port and IP-capacity work, NAT Gateway, connection reuse, or egress shaping over restart cycles. |
| `aks-apiserver-overload` | Broad `kubectl` latency/errors, controller timeouts, audit/control-plane metrics when available, high-cardinality LIST/watch clients, and recent controller deployments. | Treat broad kubectl, controller, and watch timeouts as control-plane overload first. Identify the noisy client, reduce LIST pressure, and consider API Priority and Fairness protections before investigating Drasi. |
| `aks-konnectivity-tunnel-fault` | `kubectl get pods -n kube-system -l app=konnectivity-agent -o wide`; logs/events for konnectivity-agent; private cluster admin path symptoms for exec/logs/port-forward/Run Command. | If exec, logs, port-forward, Run Command, or private-cluster admin traffic degrades, test the control-plane-to-node tunnel before treating it as a workload or Drasi issue. |
| `aks-monitoring-agent-fault` | AKS monitoring add-on profile, `ama-logs` pods, Log Analytics table freshness, DCRs, DCR associations, and workspace ingestion status. | Missing `KubePodInventory` or `ContainerLogV2` with running `ama-logs` pods is a monitoring pipeline fault. Recreating the monitoring add-on or changing DCR/DCRA is a human-approval path with validation queries and rollback notes. |

## AKS upgrade blocker routes

| Route | First evidence bundle | Required behaviour |
| --- | --- | --- |
| `aks-upgrade-pdb-blocked` | AKS upgrade operation error, `kubectl get pdb -A -o wide`, `kubectl describe pdb -A`, node drain events, under-replicated workloads. | Recognise this as a node-drain failure. Inspect PDBs first and prefer fixing PDB/replica design or using conservative undrainable-node behaviour over Drasi restarts. |
| `aks-upgrade-capacity-blocked` | Upgrade operation error, `az vm list-usage`, target SKU and region availability, node-pool `maxSurge`/`maxUnavailable`, activity log error codes. | Treat `QuotaExceeded`, `InsufficientVCPUQuota`, `AllocationFailed`, `OverconstrainedAllocationRequest`, and `SKUNotAvailable` as platform-capacity blockers. Lower `maxSurge`, consider `maxUnavailable`, change SKU/zone, or request quota. |
| `aks-upgrade-subnet-ip-exhaustion` | Upgrade operation error, subnet free IPs, network plugin, current nodes, surge nodes, and `maxPods`. | Compute IP demand as `(current nodes + maxSurge nodes) * (1 + maxPods)`, then reclaim IPs, expand the subnet, lower `maxSurge`, or reduce `maxPods` before retrying. |
| `aks-upgrade-version-skew` | `az aks get-upgrades`, control-plane version, node-pool versions, region-supported versions, requested upgrade target. | Classify as upgrade-policy failure, not runtime failure. Use supported in-region versions and sequential or full control-plane-plus-node-pool upgrades so skew stays supported. |
| `k8s-finalizer-termination-stuck` | `kubectl get namespace,pvc -A -o json`; finalizers, owner references, admission webhooks, and unhealthy APIservices. | Inspect finalizers, owner references, webhook scope, and APIService health before force deletion. Force removal is a human-approval path only after dependency and webhook failure are understood. |

## Fault-injection coverage targets

Use these to evaluate whether Azure SRE Agent can classify unknown alerts and route to the right specialist. Run only in a test namespace or approved maintenance window and restore immediately after each test.

- Administrative AKS stop: `az aks stop`, then verify the Activity Log alert routes to AKS platform diagnostics and the agent does not attempt Kubernetes commands.
- AKS Run Command capacity blocker: keep the workload pool at zero or create an impossible scheduling condition for helper pods, then verify the agent reports operations-access capacity instead of repeatedly retrying.
- CoreDNS unavailable: scale `coredns` to zero, then verify the CoreDNS fast path checks deployment, pods, service, endpoints, nodes, and events before proposing restore.
- Cilium/network policy fault: introduce a test namespace network policy that blocks DNS or egress, then verify the agent separates CNI/policy from Drasi runtime failures.
- Image pull failure: deploy a test pod with a bad image or unauthorized registry and verify the agent distinguishes registry/auth/image-name issues from node health.
- Storage attach/mount failure: create a test PVC/pod with an invalid storage class or mount reference and verify storage-specific evidence collection.
- Dapr system degradation: scale or block a Dapr control-plane component in a test window and verify Dapr system checks run before Drasi pod restarts.
- Azure Monitor agent blind spot: disrupt or scale `ama-logs` only in test and verify the agent labels telemetry loss as observability risk and cross-checks with AKS Run Command.
- Admission webhook unavailable: block a disposable non-core webhook service or endpoints and verify webhook configuration, service, endpoints, backing pods, timeout, `failurePolicy`, and workload identity checks run before Drasi checks.
- Cluster autoscaler capped or stuck: create unschedulable pods or cap a user pool max too low and verify pending events, node-pool min/max, backoff, and documented deadlock handling are reported.
- Metrics API unavailable: disrupt `metrics-server` or `keda-metrics-apiserver` in test and verify APIService health is checked before workload demand or Drasi performance is blamed.
- Node-pressure eviction: create disk, memory, or PID pressure only on a dedicated test pool and verify kubelet eviction and node conditions are classified as platform health.
- SNAT port exhaustion: generate short-lived outbound connections from a dedicated pool and verify egress failures are tied to outbound port/IP capacity, not registry, DNS, or Drasi restarts.
- API server overload: run a noisy LIST/watch client in a disposable cluster and verify broad control-plane timeouts route to API-server pressure.
- Konnectivity tunnel fault: disrupt `konnectivity-agent` in a private-cluster test and verify exec/logs/port-forward/Run Command failures route to tunnel diagnostics.
- Upgrade blockers: run pre-production upgrade tests for strict PDBs, quota/SKU capacity, subnet IP headroom, and version skew so the agent classifies upgrade precheck failures before runtime incidents.

## Known issue patterns from closed Drasi issues

Use these as search hints, not as proof. Confirm each pattern with live AKS evidence.

- Drasi install support for AKS and AZD has been an explicit product concern. Treat environment drift, private cluster access, Azure RBAC, and workspace linkage as first-class checks. Reference: drasi-project/drasi-platform#194.
- Dapr install/name and timeout failures have occurred. Inspect Dapr release naming, namespace, CRDs, control-plane pods, image pulls, and admission/webhook readiness. References: drasi-project/drasi-platform#119 and #193.
- Ingress host issues have occurred. For external access faults, inspect ingress host rules, service endpoints, DNS records, TLS, and whether private cluster/network design intentionally blocks public access. Reference: drasi-project/drasi-platform#323.
- Azure Linux image support has changed over time. For node/image compatibility issues, capture node OS image, Kubernetes version, container image tags, and image pull/runtime errors. Reference: drasi-project/drasi-platform#249.

## AKS Run Command failure mode

Private AKS incident investigation depends on `az aks command invoke`, which schedules a helper pod into the cluster. If command invoke fails with an error similar to `Unschedulable - 0/N nodes are available`, do not keep retrying Kubernetes commands.

Treat that as an operations access capacity blocker:

- Check node capacity, taints, and pending pods when possible.
- State clearly that the Kubernetes API may still be healthy; the helper pod cannot schedule.
- Short-term containment is usually scaling a schedulable workload node pool out by one node, then retrying evidence collection.
- Production prevention is reserved operations headroom or a dedicated operations node pool/toleration design for run-command style investigations.

## Output format

Return concise Markdown tables, not long prose.

Start with this KT appraisal table:

| KT step | Outcome |
| --- | --- |
| Situation | Severity, urgency, impacted Drasi capability, AKS platform layer, and containment need. |
| Spec | What, where, when, extent, and telemetry gaps such as stale Log Analytics tables. |
| Distinction/change | Before/after state, healthy/unhealthy comparisons, node pool state, and recent AKS changes. |
| Probable cause | Strongest cause and weaker alternatives. |
| Decision | Preferred review-mode action, effectiveness, risk, reversibility, rollback, and validation. |
| Potential problems | Post-action risks, prevention, contingency, rollback triggers, and validation signals. |

Then include an `IS / IS NOT` problem-specification table:

| Dimension | IS | IS NOT |
| --- | --- | --- |
| What | Observed platform symptom or failing component. | Similar platform/runtime symptoms not supported by evidence. |
| Where | Affected AKS cluster, node pool, namespace, component, or dependency. | Unaffected or unproven locations. |
| When | Detection time and recent change window. | Time windows not implicated. |
| Extent | Blast radius across nodes, namespaces, and Drasi capability. | Components or namespaces not impacted or not yet proven impacted. |

After the tables, add short sections for evidence, proposed fix in review mode, rollback, and validation commands.
