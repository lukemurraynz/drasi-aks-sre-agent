[CmdletBinding()]
param(
    [switch] $SkipScheduledTasks
)

$ErrorActionPreference = 'Stop'

function Get-AzdValue {
    param([Parameter(Mandatory)][string] $Name)

    if (Test-Path "Env:$Name") {
        $value = (Get-Item "Env:$Name").Value
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    $values = azd env get-values 2>$null
    foreach ($line in $values) {
        if ($line -match "^$([regex]::Escape($Name))=""(.*)""$") {
            return $Matches[1]
        }
    }

    return $null
}

function Get-SreToken {
    az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv
}

function Invoke-SreApi {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PUT', 'DELETE')][string] $Method,
        [Parameter(Mandatory)][string] $Path,
        [object] $Body
    )

    $token = Get-SreToken
    $headers = @{
        Authorization = "Bearer $token"
    }

    $uri = "$script:AgentEndpoint$Path"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -AllowInsecureRedirect
    }

    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Depth 20) -AllowInsecureRedirect
}

function Invoke-SreApiWithRetry {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PUT', 'DELETE')][string] $Method,
        [Parameter(Mandatory)][string] $Path,
        [object] $Body,
        [int] $Attempts = 5
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            return Invoke-SreApi -Method $Method -Path $Path -Body $Body
        }
        catch {
            if ($attempt -eq $Attempts) {
                throw
            }

            Start-Sleep -Seconds (5 * $attempt)
        }
    }
}

function New-SubAgentBody {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Instructions,
        [Parameter(Mandatory)][string] $HandoffDescription,
        [string[]] $Tools,
        [string[]] $McpTools = @(),
        [string[]] $Handoffs = @()
    )

    return @{
        name = $Name
        type = 'ExtendedAgent'
        tags = @('drasi', 'aks', 'production')
        owner = ''
        properties = @{
            instructions = $Instructions
            handoffDescription = $HandoffDescription
            handoffs = $Handoffs
            tools = $Tools
            mcpTools = $McpTools
            allowParallelToolCalls = $true
            enableSkills = $true
        }
    }
}

function New-SkillBody {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Description,
        [Parameter(Mandatory)][string] $SkillContent,
        [string[]] $Tools
    )

    return @{
        name = $Name
        type = 'Skill'
        properties = @{
            description = $Description
            tools = $Tools
            skillContent = $SkillContent
            additionalFiles = @()
        }
    }
}

function New-ConnectorBody {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $DataConnectorType,
        [Parameter(Mandatory)][string] $DataSource,
        [string] $Identity = '',
        [object] $ExtendedProperties
    )

    return @{
        name = $Name
        type = 'AgentConnector'
        properties = @{
            dataConnectorType = $DataConnectorType
            dataSource = $DataSource
            identity = $Identity
            extendedProperties = $ExtendedProperties
        }
    }
}

function Enable-AgentTools {
    param([Parameter(Mandatory)][string[]] $ToolNames)

    $overrides = @(
        $ToolNames |
            Sort-Object -Unique |
            ForEach-Object {
                @{
                    name = $_
                    enabled = $true
                }
            }
    )

    Invoke-SreApiWithRetry -Method POST -Path '/api/v2/agent/tools/configure' -Body @{
        overrides = $overrides
    } | Out-Null
}

function Get-TemplatedContent {
    param([Parameter(Mandatory)][string] $Path)

    $content = Get-Content -Raw -Path $Path
    $content = $content.Replace('@@SUBSCRIPTION_ID@@', $subscriptionId)
    $content = $content.Replace('@@RG@@', $resourceGroupName)
    $content = $content.Replace('@@RG_ID@@', "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName")
    $content = $content.Replace('@@AKS@@', $aksClusterName)
    $content = $content.Replace('@@AKS_ID@@', "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.ContainerService/managedClusters/$aksClusterName")
    $content = $content.Replace('@@LAW@@', $workspaceName)
    $content = $content.Replace('@@DRASI_NS@@', 'drasi-system')
    return $content
}

function Get-ScheduledTaskBody {
    param([Parameter(Mandatory)][string] $Path)

    $content = Get-TemplatedContent -Path $Path
    if ($content -notmatch "(?s)^---\r?\n(.*?)\r?\n---\r?\n(.*)$") {
        throw "Scheduled task file '$Path' must contain YAML-style front matter followed by the task prompt."
    }

    $metadataText = $Matches[1]
    $prompt = $Matches[2].Trim()
    $metadata = @{}

    foreach ($line in ($metadataText -split "\r?\n")) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }

        $parts = $trimmed -split ':', 2
        if ($parts.Count -ne 2) {
            throw "Invalid scheduled task metadata line in '$Path': $line"
        }

        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        $metadata[$key] = $value
    }

    foreach ($requiredKey in @('name', 'description', 'cronExpression', 'agent')) {
        if (-not $metadata.ContainsKey($requiredKey) -or [string]::IsNullOrWhiteSpace($metadata[$requiredKey])) {
            throw "Scheduled task file '$Path' is missing required metadata key '$requiredKey'."
        }
    }

    return @{
        name = $metadata['name']
        description = $metadata['description']
        cronExpression = $metadata['cronExpression']
        agentPrompt = $prompt
        agent = $metadata['agent']
    }
}

$script:AgentEndpoint = Get-AzdValue -Name 'AZURE_SRE_AGENT_ENDPOINT'
$resourceGroupName = Get-AzdValue -Name 'DRASI_RESOURCE_GROUP_NAME'
$aksClusterName = Get-AzdValue -Name 'DRASI_AKS_CLUSTER_NAME'
$workspaceName = Get-AzdValue -Name 'DRASI_LOG_ANALYTICS_WORKSPACE_NAME'
$subscriptionId = Get-AzdValue -Name 'AZURE_SUBSCRIPTION_ID'

if ([string]::IsNullOrWhiteSpace($script:AgentEndpoint)) {
    throw 'AZURE_SRE_AGENT_ENDPOINT was not found. Run azd provision first so outputs are written to the AZD environment.'
}

$script:AgentEndpoint = $script:AgentEndpoint.TrimEnd('/')

Write-Host "Configuring Azure SRE Agent data-plane resources at $script:AgentEndpoint"

$commonTools = @(
    'SearchMemory',
    'RunAzCliReadCommands',
    'QueryLogAnalyticsByWorkspaceId',
    'QueryAppInsightsByResourceId',
    'ExecutePythonCode'
)

$microsoftLearnMcpTools = @(
    'microsoft-learn_microsoft_docs_search',
    'microsoft-learn_microsoft_code_sample_search',
    'microsoft-learn_microsoft_docs_fetch'
)

$drasiDocsMcpTools = @(
    'drasi-docs_fetch_docs_documentation',
    'drasi-docs_search_docs_documentation',
    'drasi-docs_search_docs_code',
    'drasi-docs_fetch_generic_url_content'
)

$docsMcpTools = $microsoftLearnMcpTools + $drasiDocsMcpTools
$skillReadTools = $commonTools + $docsMcpTools
$skillWriteTools = $skillReadTools + @('RunAzCliWriteCommands')
$writeTools = $commonTools + @('RunAzCliWriteCommands')

$requiredAgentTools = $skillWriteTools

Write-Host 'Ensuring MCP connector tools are visible to the agent'
$microsoftLearnConnector = New-ConnectorBody -Name 'microsoft-learn' -DataConnectorType 'Mcp' -DataSource 'drasi-microsoft-learn-mcp' -ExtendedProperties @{
    type = 'http'
    endpoint = 'https://learn.microsoft.com/api/mcp'
    authType = 'CustomHeaders'
    toolsVisibleToMetaAgent = $microsoftLearnMcpTools
}
$drasiDocsConnector = New-ConnectorBody -Name 'drasi-docs' -DataConnectorType 'Mcp' -DataSource 'drasi-docs-gitmcp' -ExtendedProperties @{
    type = 'http'
    endpoint = 'https://gitmcp.io/drasi-project/docs'
    authType = 'CustomHeaders'
    toolsVisibleToMetaAgent = $drasiDocsMcpTools
}

Invoke-SreApiWithRetry -Method PUT -Path '/api/v2/extendedAgent/connectors/microsoft-learn' -Body $microsoftLearnConnector | Out-Null
Invoke-SreApiWithRetry -Method PUT -Path '/api/v2/extendedAgent/connectors/drasi-docs' -Body $drasiDocsConnector | Out-Null

Write-Host 'Enabling required built-in and MCP tools used by Drasi SRE content'
Enable-AgentTools -ToolNames $requiredAgentTools

$skillDir = Join-Path $PSScriptRoot '..\sre-config\skills'
$skills = @(
    (New-SkillBody -Name 'drasi-runtime-diagnostics' -Description 'Diagnose Drasi runtime, source, query, reaction, Redis, Mongo, and Dapr-sidecar issues on AKS using Kepner-Tregoe.' -SkillContent (Get-TemplatedContent -Path (Join-Path $skillDir 'drasi-runtime-diagnostics.md')) -Tools $skillWriteTools),
    (New-SkillBody -Name 'aks-platform-diagnostics' -Description 'Diagnose AKS platform issues affecting Drasi, including nodes, DNS, Cilium, Dapr, Azure Monitor, Gatekeeper, identity, and storage.' -SkillContent (Get-TemplatedContent -Path (Join-Path $skillDir 'aks-platform-diagnostics.md')) -Tools $skillWriteTools),
    (New-SkillBody -Name 'drasi-remediation-review' -Description 'Review proposed Drasi or AKS remediation actions for safety, rollback, validation, and Kepner-Tregoe decision quality.' -SkillContent (Get-TemplatedContent -Path (Join-Path $skillDir 'drasi-remediation-review.md')) -Tools $skillReadTools)
)

foreach ($skill in $skills) {
    $name = $skill.name
    Write-Host "Creating/updating skill: $name"
    Invoke-SreApiWithRetry -Method PUT -Path "/api/v2/extendedAgent/skills/$name" -Body $skill | Out-Null
}

$agentDir = Join-Path $PSScriptRoot '..\sre-config\agents'
$triageInstructions = Get-TemplatedContent -Path (Join-Path $agentDir 'drasi-incident-triage.md')
$runtimeInstructions = Get-TemplatedContent -Path (Join-Path $agentDir 'drasi-runtime-diagnostics.md')
$aksInstructions = Get-TemplatedContent -Path (Join-Path $agentDir 'aks-platform-diagnostics.md')
$reviewInstructions = Get-TemplatedContent -Path (Join-Path $agentDir 'drasi-remediation-review.md')

$subAgents = @(
    (New-SubAgentBody -Name 'drasi-remediation-review' -Instructions $reviewInstructions -HandoffDescription 'Review Drasi and AKS remediation proposals for safety, rollback, and validation.' -Tools $commonTools -McpTools $docsMcpTools),
    (New-SubAgentBody -Name 'drasi-runtime-diagnostics' -Instructions $runtimeInstructions -HandoffDescription 'Diagnose Drasi runtime, source, query, reaction, Redis, Mongo, and Dapr-sidecar issues.' -Tools $writeTools -McpTools $docsMcpTools -Handoffs @('drasi-remediation-review')),
    (New-SubAgentBody -Name 'aks-platform-diagnostics' -Instructions $aksInstructions -HandoffDescription 'Diagnose AKS platform issues that affect Drasi availability or processing.' -Tools $writeTools -McpTools $docsMcpTools -Handoffs @('drasi-remediation-review')),
    (New-SubAgentBody -Name 'drasi-incident-triage' -Instructions $triageInstructions -HandoffDescription 'Triage Drasi on AKS incidents using Kepner-Tregoe and route to the right specialist.' -Tools $commonTools -McpTools $docsMcpTools -Handoffs @('drasi-runtime-diagnostics', 'aks-platform-diagnostics', 'drasi-remediation-review'))
)

foreach ($subAgent in $subAgents) {
    $name = $subAgent.name
    Write-Host "Creating/updating subagent: $name"
    Invoke-SreApiWithRetry -Method PUT -Path "/api/v2/extendedAgent/agents/$name" -Body $subAgent | Out-Null
}

Write-Host 'Creating/updating Azure Monitor response plans'
$responsePlanPath = Join-Path $PSScriptRoot '..\sre-config\response-plans\response-plans.json'
$responsePlans = @(Get-TemplatedContent -Path $responsePlanPath | ConvertFrom-Json)

foreach ($plan in $responsePlans) {
    try {
        Invoke-SreApi -Method DELETE -Path "/api/v1/incidentPlayground/filters/$($plan.id)" -Body $null | Out-Null
    }
    catch {
    }

    Invoke-SreApiWithRetry -Method PUT -Path "/api/v1/incidentPlayground/filters/$($plan.id)" -Body $plan | Out-Null
}

if (-not $SkipScheduledTasks) {
    Write-Host 'Creating/updating scheduled health checks'
    $scheduledTaskDir = Join-Path $PSScriptRoot '..\sre-config\scheduled-tasks'
    $scheduledTaskDefinitions = @(
        Get-ScheduledTaskBody -Path (Join-Path $scheduledTaskDir 'drasi-health-probe-15m.md')
        Get-ScheduledTaskBody -Path (Join-Path $scheduledTaskDir 'drasi-daily-resilience-report.md')
    )

    $tasks = @()
    try {
        $tasks = Invoke-SreApiWithRetry -Method GET -Path '/api/v1/scheduledtasks' -Body $null -Attempts 3
    }
    catch {
        Write-Warning "Could not list existing scheduled tasks. Continuing with create attempts. $($_.Exception.Message)"
    }

    foreach ($existing in @($tasks)) {
        if ($existing.name -in $scheduledTaskDefinitions.name) {
            try {
                Invoke-SreApi -Method DELETE -Path "/api/v1/scheduledtasks/$($existing.id)" -Body $null | Out-Null
            }
            catch {
                Write-Warning "Could not delete existing scheduled task $($existing.name). $($_.Exception.Message)"
            }
        }
    }

    foreach ($scheduledTask in $scheduledTaskDefinitions) {
        Invoke-SreApiWithRetry -Method POST -Path '/api/v1/scheduledtasks' -Body $scheduledTask | Out-Null
    }
}

Write-Host 'Azure SRE Agent data-plane configuration complete.'
