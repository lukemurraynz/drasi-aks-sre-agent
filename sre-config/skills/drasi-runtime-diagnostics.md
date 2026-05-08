## Drasi Runtime Diagnostics

Primary scope:

- Resource group: `@@RG@@`
- AKS cluster: `@@AKS@@`
- AKS resource ID: `@@AKS_ID@@`
- Drasi namespace: `@@DRASI_NS@@`

Use this skill for Drasi runtime issues: query staleness, processing lag, source connector failures, reaction failures, `CrashLoopBackOff`, Redis or Mongo pressure, Drasi API failures, Dapr sidecar failures, and noisy restarts in `drasi-system`.

## Operating rules

1. Start with read-only evidence. Use `az aks command invoke` for Kubernetes commands because the cluster API is private.
2. Always identify the exact failing component, recent change window, blast radius, and whether the issue is platform, Drasi runtime, or source/reaction specific.
3. Prefer `kubectl get`, `kubectl describe`, `kubectl logs --previous`, recent events, and Azure Monitor KQL before proposing remediation.
4. Keep the SRE Agent in review mode. Any write action must be proposed with the command, expected effect, risk, and rollback.
5. Do not delete Drasi CRDs, stateful volumes, Mongo/Redis data, or source/reaction custom resources unless a human explicitly approves it.
6. In incident threads, do not narrate tool discovery or internal skill loading. Run the first evidence bundle, then summarize.
7. Every `kubectl get` command must include `-o wide`, `-o json`, or another explicit output option.

## Incident fast path

For Azure Monitor incidents that mention Drasi, a reaction, source, query, pod availability, or `CrashLoopBackOff`, run a deterministic evidence bundle before broad exploration:

```bash
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get deployments -n @@DRASI_NS@@ -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get pods -n @@DRASI_NS@@ -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get events -n @@DRASI_NS@@ --sort-by=.lastTimestamp -o wide"
```

This skill is authorized to investigate Drasi workloads in the scoped AKS cluster and propose review-mode, reversible Kubernetes remediations. Do not refuse routine diagnostics or safe scale-restore proposals for in-scope Drasi deployments.

If the alert title or description names a specific workload such as `log-changes-reaction`, inspect that workload directly:

```bash
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get deployment log-changes-reaction -n @@DRASI_NS@@ -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl describe deployment log-changes-reaction -n @@DRASI_NS@@"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get pods -n @@DRASI_NS@@ -l app=log-changes-reaction -o wide"
```

If the alert title or description names a source workload such as `pg-source-change-router`, `pg-source-change-dispatcher`, `pg-source-proxy`, `pg-source-query-api`, or `pg-source-reactivator`, inspect that deployment directly:

```bash
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get deployment pg-source-change-router -n @@DRASI_NS@@ -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl describe deployment pg-source-change-router -n @@DRASI_NS@@"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get pods -n @@DRASI_NS@@ -l drasi/service=change-router -o wide"
```

If desired replicas are `0` while the alert is about unavailable pods, the strongest cause candidate is explicit scale-to-zero or an autoscaler. Check controllers before proposing a restore:

```bash
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get hpa -A -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get scaledobject -A -o wide"
```

If KEDA `ScaledObject` is not installed, state that and continue. Review-mode remediation for `log-changes-reaction` with no controller conflict:

```bash
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl scale deployment log-changes-reaction -n @@DRASI_NS@@ --replicas=1"
```

For `pg-source-change-router` unavailable with no controller conflict:

```bash
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl scale deployment pg-source-change-router -n @@DRASI_NS@@ --replicas=1"
```

Validate with deployment availability, pod readiness, current logs, and the original alert metric returning to healthy.

## Kepner-Tregoe investigation frame

Use Kepner-Tregoe structure where the incident has ambiguity or customer impact:

1. Situation appraisal: list the concerns, urgency, severity, affected Drasi function, and immediate containment need.
2. Problem specification: state what is failing, where it is failing, when it started, and the extent. Include explicit `IS` and `IS NOT` comparisons.
3. Distinction and change analysis: compare failing and non-failing pods/components, then identify recent changes in Kubernetes events, restarts, images, config, identities, source connectivity, and Azure resource state.
4. Probable cause: test each candidate cause against the facts before recommending action.
5. Decision analysis: compare remediation options by effectiveness, risk, blast radius, reversibility, and time to validate.
6. Potential problem analysis: list what could go wrong during remediation, prevention steps, rollback triggers, and validation signals.

## Baseline commands

```bash
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get pods -n @@DRASI_NS@@ -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl get events -n @@DRASI_NS@@ --sort-by=.lastTimestamp -o wide"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl describe pod -n @@DRASI_NS@@ <pod>"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl logs -n @@DRASI_NS@@ <pod> --all-containers --tail=200"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl logs -n @@DRASI_NS@@ <pod> --all-containers --previous --tail=200"
```

## Drasi-specific checks

- Check `drasi-api`, `drasi-resource-provider`, `default-query-host`, `default-publish-api`, and `default-view-svc` first.
- For source issues, inspect source router, dispatcher, proxy, query API, and reactivator pods together. A single source pod crash can be a symptom of upstream credentials, DNS, schema, or source database connectivity.
- For reaction issues, inspect reaction pod logs, associated source/query readiness, and Dapr sidecar status.
- For query staleness or lag, compare source connector errors, query host logs, Redis/Mongo readiness, and recent restart counts before restarting anything.

## Drasi lifecycle routes

Use these routes when only Drasi resources are unhealthy after source CRUD, Continuous Query CRUD, reaction CRUD, install, or upgrade actions. If symptoms span many namespaces, or pod creation/scheduling fails before Drasi starts, hand back to AKS platform diagnostics first.

| Route | First evidence bundle | Required behaviour |
| --- | --- | --- |
| `drasi-source-bootstrap-race` | `kubectl get sources,continuousqueries -n @@DRASI_NS@@ -o yaml`; source connector pod logs; query host/resource provider logs; recent events ordered by timestamp. | Recognise the documented race where a Continuous Query can enter a broken state if it is created before its Source connects cleanly and bootstrap fails. Confirm Source health, then propose deleting and recreating the affected Continuous Query in review mode. Do not bounce the cluster or restart unrelated Drasi components. |
| `drasi-source-dependency-break` | `kubectl get sources,continuousqueries,reactions -n @@DRASI_NS@@ -o yaml`; events and resource provider logs around the source deletion or connectivity object deletion. | Route as a source-lifecycle dependency failure. Deleting a Source or its connectivity dependency can stop dependent Continuous Queries from receiving changes. Identify orphaned/dependent queries and propose restoring the Source/dependency or recreating dependent queries only with explicit review. |
| `drasi-upgrade-partial-rollout` | `kubectl rollout status deployment -n @@DRASI_NS@@ --timeout=60s`; `kubectl get deployments,pods,events -n @@DRASI_NS@@ -o wide`; `kubectl get sources,continuousqueries,reactions,secrets,configmaps -n @@DRASI_NS@@ -o wide`. | Watch the `drasi-system` rollout, preserve Sources, Continuous Queries, Reactions, Secrets, and ConfigMaps, and use Drasi rollback when health checks fail. Treat upgrade as rolling and health-checked; prefer rollback or rollout repair over deleting persistent Drasi state. |

## Known issue patterns from closed Drasi issues

Use these as search hints, not as proof. Confirm each pattern with live evidence.

- Invalid or stuck resources can make CLI wait/list operations appear unresponsive. Check resource provider logs and invalid Drasi custom resources before treating the CLI as the root cause. Reference: drasi-project/drasi-platform#109.
- Dapr installation/name assumptions have broken Drasi installs before. If install or system pods fail, compare the live Dapr namespace, Helm release name, and Dapr control-plane health. Reference: drasi-project/drasi-platform#119.
- Dapr install can hit context deadline exceeded. For related symptoms, inspect Dapr operator/sentry/placement/scheduler readiness, events, image pulls, and network egress. Reference: drasi-project/drasi-platform#193.
- Ingress host configuration has caused deployment issues. If Drasi API, query endpoints, or reactions are unreachable, inspect ingress resources, host rules, DNS, and private/public exposure mode. Reference: drasi-project/drasi-platform#323.
- ContinuousQuery create/update parser errors were reported after initial deployment. For query failures, capture the query spec, parser error, Drasi version, and whether the issue affects new queries only or existing query execution. Reference: drasi-project/drasi-platform#366.
- Fresh installs have returned 404 for source listing. If source/query APIs disagree with pod health, inspect API routes, resource provider readiness, and CRD discovery before restarting pods. Reference: drasi-project/drasi-platform#425.
- Replayable source and resumable reaction work in drasi-core means sequence stamping, replay flags, checkpoints, result sequence, and row signatures are operationally important. For lag/staleness, inspect sequence/checkpoint/resume errors in source and reaction logs. References: drasi-project/drasi-core#345, #363, #364, #366, #395.

## Azure Monitor KQL starting points

Use Log Analytics with the attached workspace. If a table is missing, state that and continue with Kubernetes evidence.

```kusto
KubePodInventory
| where TimeGenerated > ago(30m)
| where Namespace == "@@DRASI_NS@@"
| project TimeGenerated, Name, PodStatus, ContainerStatus, ContainerStatusReason, ContainerRestartCount
| order by TimeGenerated desc
```

```kusto
ContainerLogV2
| where TimeGenerated > ago(30m)
| where Namespace == "@@DRASI_NS@@"
| where LogMessage has_any ("error", "exception", "panic", "timeout", "lag", "stale", "CrashLoopBackOff")
| project TimeGenerated, PodName, ContainerName, LogMessage
| order by TimeGenerated desc
```

## Output format

Return:

- Incident summary and severity.
- KT appraisal as a Markdown table with rows for Situation, Spec, Distinction/change, Probable cause, Decision, and Potential problems.
- KT problem specification as an `IS / IS NOT` Markdown table with dimensions for What, Where, When, and Extent.
- Evidence with exact resources and timestamps.
- Root cause or strongest hypothesis.
- Proposed remediation in review mode.
- Potential problems, rollback, and validation commands.

Use this KT appraisal table shape:

| KT step | Outcome |
| --- | --- |
| Situation | Severity, urgency, affected Drasi function, fault domain, and containment need. |
| Spec | What, where, when, extent, and telemetry gaps. |
| Distinction/change | Before/after state, failing/non-failing pods or components, and recent changes. |
| Probable cause | Strongest cause and weaker alternatives. |
| Decision | Preferred review-mode action, effectiveness, risk, reversibility, rollback, and validation. |
| Potential problems | Post-action risks, prevention, contingency, rollback triggers, and validation signals. |

Use this `IS / IS NOT` table shape:

| Dimension | IS | IS NOT |
| --- | --- | --- |
| What | Observed Drasi symptom or failing component. | Similar symptoms/components not supported by evidence. |
| Where | Affected namespace, pod, deployment, source, query, reaction, or dependency. | Unaffected or unproven locations. |
| When | Detection time and recent change window. | Time windows not implicated. |
| Extent | Blast radius across Drasi capability and dependent components. | Components/capabilities not impacted or not yet proven impacted. |
