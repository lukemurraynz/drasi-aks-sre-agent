---
name: drasi-daily-resilience-report
description: Create a daily Drasi resilience and operational risk report.
cronExpression: "0 18 * * *"
agent: drasi-incident-triage
---
Use the drasi-incident-triage subagent to produce a daily Drasi on AKS resilience report for resource group @@RG@@, cluster @@AKS@@.

Begin with AKS control-plane state:

```bash
az aks show -g @@RG@@ -n @@AKS@@ --query "{provisioningState:provisioningState,powerState:powerState.code}" -o json
```

If `powerState` is `Stopped`, call that out as the primary availability condition and avoid Kubernetes commands that require a running cluster.

When the cluster is running, use `kubectl_command_executor_agent` for all Kubernetes commands — pass only the raw kubectl command (e.g., `kubectl get pods -n drasi-system -o wide`). Do not use `RunAzCliReadCommands` for `az aks command invoke`.

Do not ask for local `kubectl` output unless `kubectl_command_executor_agent` is unavailable.

Include recurring errors, restart trends, source/reaction lag signals, AKS platform risks, open follow-ups, and recommended hardening.

Use Markdown tables for KT content. Include a KT appraisal table with rows for Situation, Spec, Distinction/change, Probable cause, Decision, and Potential problems. Include an `IS / IS NOT` table with dimensions for What, Where, When, and Extent when reporting an active or recent issue.
