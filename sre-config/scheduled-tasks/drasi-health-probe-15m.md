---
name: drasi-health-probe-15m
description: Run a 15-minute Drasi and AKS health probe.
cronExpression: "*/15 * * * *"
agent: drasi-incident-triage
---
Use the drasi-incident-triage subagent to run a concise Kepner-Tregoe situation appraisal for Drasi on AKS in resource group @@RG@@, cluster @@AKS@@.

First check AKS control-plane state:

```bash
az aks show -g @@RG@@ -n @@AKS@@ --query "{provisioningState:provisioningState,powerState:powerState.code}" -o json
```

If `powerState` is `Stopped`, report the cluster as intentionally or administratively stopped, do not attempt `kubectl` or `kubectl_command_executor_agent`, and note that the `aks-cluster-stopped` incident route is pre-approved to start the same managed cluster autonomously with `az aks start -g @@RG@@ -n @@AKS@@`. This exception does not authorize scale-out, upgrades, networking changes, or cluster recreation.

Check drasi-system pod health, recent events, restart spikes, source/reaction lag symptoms, and AKS platform health.

Use `kubectl_command_executor_agent` for all Kubernetes commands — pass only the raw kubectl command (e.g., `kubectl get pods -n drasi-system -o wide`). Do not use `RunAzCliReadCommands` for `az aks command invoke`.

Do not ask for local `kubectl` output unless `kubectl_command_executor_agent` is unavailable. Include `-o wide`, `-o json`, or another explicit `-o` output option on every `kubectl get` command.

Always return a short final status. If unhealthy, use Markdown tables:

| KT step | Outcome |
| --- | --- |
| Situation | Severity, urgency, affected capability, fault domain, and containment need. |
| Spec | What, where, when, extent, and telemetry gaps. |
| Distinction/change | Before/after state, healthy/unhealthy comparisons, and recent changes. |
| Probable cause | Strongest cause and weaker alternatives. |
| Decision | Review-mode action, effectiveness, risk, reversibility, rollback, and validation. |
| Potential problems | Post-action risks, prevention, contingency, and validation signals. |

Also include an `IS / IS NOT` table with dimensions for What, Where, When, and Extent.
