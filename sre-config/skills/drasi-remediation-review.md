## Drasi Remediation Review

Use this skill before executing any Drasi or AKS write action.
Return review results as Markdown tables, not long prose.

Approve only when the proposal includes:

- Exact command and target resource.
- Kepner-Tregoe decision analysis showing why this action addresses the evidence better than safer alternatives.
- Expected customer impact.
- Rollback command or natural rollback path.
- Validation command and success criteria.
- Potential problem analysis covering what could go wrong, prevention, contingency, and rollback trigger.

Decision review table:

| Review area | Finding |
| --- | --- |
| Evidence-to-action link | Whether the proposed action directly addresses the observed evidence. |
| Effectiveness | Why this action is expected to work. |
| Risk | Blast radius and customer impact. |
| Reversibility | Rollback command or natural rollback path. |
| Alternatives | Safer or lower-impact options considered. |
| Validation | Commands and success criteria. |
| Potential problems | What could go wrong, prevention, contingency, and rollback trigger. |

Reject or ask for human approval when the action deletes persistent data, changes IAM/RBAC, deletes CRDs, scales or upgrades the cluster, modifies networking, changes cluster autoscaler or node-pool settings, changes AKS add-ons, recreates Azure Monitor Container Insights, creates or changes Data Collection Rules or DCR associations, removes finalizers, force deletes namespaces/PVCs, changes webhook `failurePolicy`, lowers upgrade safety settings, drops schema/data, or hides symptoms without root-cause evidence.

Exception: for the `aks-cluster-stopped` route only, starting the same managed AKS cluster with `az aks start -g @@RG@@ -n @@AKS@@` is pre-approved after evidence confirms `powerState` is `Stopped`. This does not approve node-pool scale-out, upgrades, networking changes, or cluster recreation.

## Fast approval path

Replica restoration can use a shorter approval path when all of these are true:

- The alert maps directly to a named Kubernetes deployment.
- Evidence shows desired or available replicas are `0` or below the expected minimum.
- HPA, KEDA, or another controller is absent or not expected to immediately reverse the change.
- The command is reversible and affects only the named deployment.

The proposal still must include the exact command, prior replica count if known, expected healthy state, validation command, rollback command, and rollback trigger.

Examples:

```bash
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl scale deployment coredns -n kube-system --replicas=2"
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "kubectl scale deployment log-changes-reaction -n @@DRASI_NS@@ --replicas=1"
```

Cluster scale-out, RBAC, networking, CRD, node-pool autoscaler changes, AKS upgrade setting changes, AKS add-on or Azure Monitor DCR changes, finalizer removal, webhook policy changes, and persistent data changes remain human-approval actions even when they are likely to fix the incident.
