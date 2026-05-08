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

If `powerState` is `Stopped`, call that out as the primary availability condition and avoid Kubernetes run-command checks that require a running cluster.

When the cluster is running, use Kubernetes commands through AKS Run Command:

```bash
az aks command invoke -g @@RG@@ -n @@AKS@@ --command "<kubectl command>"
```

Do not ask for local `kubectl` output unless AKS Run Command is unavailable.

Include recurring errors, restart trends, source/reaction lag signals, AKS platform risks, open follow-ups, and recommended hardening.

Use Markdown tables for KT content. Include a KT appraisal table with rows for Situation, Spec, Distinction/change, Probable cause, Decision, and Potential problems. Include an `IS / IS NOT` table with dimensions for What, Where, When, and Extent when reporting an active or recent issue.
