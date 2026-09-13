param(
  [string]$RegistryPath = "$PSScriptRoot\AX_MASTER_BRAIN\AX_MASTER_TASK_REGISTRY_v2.json"
)

$ErrorActionPreference = 'Stop'

# AX ACTION DISPATCHER
# Canonical routes: AX helper agents, PC Dispatch Gateway, then canonical runtimes.

if (-not (Test-Path $RegistryPath)) { throw "AX_TASK_REGISTRY_NOT_FOUND: $RegistryPath" }
$selectorPath = Join-Path $PSScriptRoot 'AX_TASK_SELECTOR.ps1'
if (-not (Test-Path $selectorPath)) { throw "AX_TASK_SELECTOR_NOT_FOUND: $selectorPath" }
. $selectorPath

$sourceRegistry = Get-Content -Raw -Path $RegistryPath | ConvertFrom-Json
$registry = if ([string]$sourceRegistry.registry_role -eq 'AUTHORITATIVE_AKATH_MASTER_TASK_STATUS') { Convert-AxMasterRegistry -MasterRegistry $sourceRegistry } else { $sourceRegistry }
$selected = Select-AxNextTask -Registry $registry

Write-Host '=== AX ACTION DISPATCHER ==='
Write-Host "Canonical Registry: $RegistryPath"
if ($null -eq $selected) { Write-Host 'Dispatch: NO_ELIGIBLE_TASK'; Write-Host 'Execution: NOT_PERFORMED'; exit 0 }
if (-not (Test-AxTaskDependencies -Registry $registry -Task $selected)) { throw "AX_DEPENDENCY_GATE_REJECTED:$($selected.id)" }

Write-Host "Task ID: $($selected.id)"
Write-Host "Domain: $($selected.domain)"
Write-Host "Priority: $($selected.priority)"
Write-Host "Requested Action: $($selected.next_action)"
Write-Host 'Dependency Gate: PASSED'

# ============================================================
# PC DISPATCH GATEWAY — CANONICAL PC EXECUTION ROUTE
# ============================================================
$pcGateway = Join-Path $PSScriptRoot 'AX_PC_DISPATCH_GATEWAY.ps1'
if ([string]$selected.domain -eq 'PC' -and (Test-Path $pcGateway)) {
  Write-Host 'PC Gateway: CANONICAL'
  Write-Host 'PC Node: PC2-CODING-EXECUTOR'
  Write-Host 'PC Command: health'
  & powershell.exe -ExecutionPolicy Bypass -File $pcGateway -TaskId $selected.id -Command health -NodeId 'PC2-CODING-EXECUTOR' -Enqueue
  if ($LASTEXITCODE -ne 0) { throw "AX_PC_GATEWAY_FAILED:$LASTEXITCODE" }
  Write-Host 'PC_GATEWAY_SELECTED=TRUE'
  Write-Host 'PC_COMPLETION=NOT_CLAIMED_UNTIL_RESULT_ACK_VERIFIED'
  exit 0
}

# ============================================================
# HELPER-AGENT ROUTING
# ============================================================
$agentRoutingBridge = Join-Path $PSScriptRoot 'AX_AGENT_ROUTING_BRIDGE.ps1'
$agentRouteSelected = $false
if (Test-Path $agentRoutingBridge) {
  # Let the routing bridge resolve the domain's candidate list itself.
  # Passing a PowerShell array across a native powershell.exe boundary caused
  # positional binding failures on the self-hosted Windows runner.
  $agentRoutingResult = & powershell.exe -ExecutionPolicy Bypass -File $agentRoutingBridge -TaskId $selected.id -Domain $selected.domain 2>&1
  if ($LASTEXITCODE -eq 0) {
    $agentRouteSelected = $true
    Write-Host 'Helper Agent Route: VERIFIED_EXECUTOR_OWNERSHIP'
    Write-Host ($agentRoutingResult | Out-String).Trim()
    Write-Host 'Task Completion: NOT_CLAIMED_BY_DISPATCHER'
    Write-Host 'Canonical Runtime: SKIPPED_TO_PREVENT_DUPLICATE_EXECUTION'
    exit 0
  }
  else {
    Write-Host 'Helper Agent Route: UNAVAILABLE'
    Write-Host ($agentRoutingResult | Out-String).Trim()
    Write-Host 'Fallback: CANONICAL_RUNTIME'
  }
}
else {
  Write-Host 'Helper Agent Routing Bridge: NOT_PRESENT'
  Write-Host 'Fallback: CANONICAL_RUNTIME'
}

# ============================================================
# CANONICAL RUNTIMES
# ============================================================
$controlRuntimeUrl = 'https://ax-control-runtime.aerismusic8.workers.dev'
$aerisRuntimeUrl   = 'https://aeris-execution-runtime.aerismusic8.workers.dev'
Write-Host "AX Control Runtime: $controlRuntimeUrl"
Write-Host "AERIS External Runtime: $aerisRuntimeUrl"

$controlRuntimeHealthy = $false
try {
  $controlHealth = Invoke-RestMethod -Uri "$($controlRuntimeUrl.TrimEnd('/'))/health" -Method Get -TimeoutSec 15
  $controlRuntimeHealthy = ($controlHealth.status -eq 'ONLINE' -and $controlHealth.mode -eq 'FREE_ONLY' -and $controlHealth.liveFinancialExecution -eq $false -and $controlHealth.queue -eq 'ax-execution-events')
  if ($controlRuntimeHealthy) { Write-Host 'AX Control Runtime Health: ONLINE' } else { Write-Host 'AX Control Runtime Health: REJECTED_BY_POLICY' }
} catch { Write-Host "AX Control Runtime Health: UNAVAILABLE ($($_.Exception.Message))" }

$aerisRuntimeHealthy = $false
try {
  $aerisResponse = Invoke-WebRequest -Uri "$($aerisRuntimeUrl.TrimEnd('/'))/" -Method Get -UseBasicParsing -TimeoutSec 15
  if ($aerisResponse.StatusCode -ne 200) { throw "AERIS_RUNTIME_HTTP_$($aerisResponse.StatusCode)" }
  $aerisHealth = $aerisResponse.Content | ConvertFrom-Json
  $identity = ($aerisHealth.service -eq 'AERIS_EXTERNAL_EXECUTION_RUNTIME' -and $aerisHealth.status -eq 'ONLINE' -and $aerisHealth.gate -eq 'GATE_3')
  $capabilities = ($aerisHealth.appsScript -eq 'OAUTH_READY' -and $aerisHealth.appsScriptExecution -eq 'READY' -and $aerisHealth.gemini -eq 'READY' -and (@($aerisHealth.endpoints) -contains 'POST /execute'))
  $financialSafe = ($aerisHealth.liveFinancialExecution -ne $true)
  $aerisRuntimeHealthy = ($identity -and $capabilities -and $financialSafe)
  if ($aerisRuntimeHealthy) { Write-Host 'AERIS External Runtime Health: ONLINE' } else { Write-Host 'AERIS External Runtime Health: REJECTED_BY_POLICY' }
} catch { Write-Host "AERIS External Runtime Health: UNAVAILABLE ($($_.Exception.Message))" }

Write-Host '=== CONTROLLED CLOUDFLARE DISPATCH ==='
if ($controlRuntimeHealthy -and $aerisRuntimeHealthy) {
  Write-Host 'Runtime Gate: READY'
  Write-Host 'Execution Gate: CONTROLLED'
  $eventId = [guid]::NewGuid().ToString()
  $event = @{ id=$eventId; taskId=[string]$selected.id; domain=[string]$selected.domain; priority=[int]$selected.priority; action=[string]$selected.next_action; createdAt=(Get-Date).ToUniversalTime().ToString('o'); source='AX_ACTION_DISPATCHER' }
  $enqueueHeaders = @{ Authorization="Bearer $env:GITHUB_TOKEN"; 'X-AERIS-REPOSITORY'='aerismusic8-alt/aeris-drive-automation'; 'Content-Type'='application/json' }
  $enqueueResponse = Invoke-RestMethod -Uri "$($controlRuntimeUrl.TrimEnd('/'))/enqueue" -Method Post -Headers $enqueueHeaders -Body ($event | ConvertTo-Json -Compress) -TimeoutSec 15
  if ($enqueueResponse.accepted -ne $true) { throw 'AX_CONTROL_RUNTIME_ENQUEUE_NOT_ACCEPTED' }
  Write-Host 'AX Control Runtime: EVENT_ACCEPTED'
  Write-Host "Event ID: $eventId"
  Write-Host "Queued: $($enqueueResponse.queued)"
  if ($selected.domain -eq 'AERIS') {
    Write-Host 'AERIS Execution: QUEUED_TO_CONTROL_RUNTIME_QUEUE_CONSUMER'
    Write-Host 'Business Execution: NOT_CLAIMED_BY_DISPATCHER'
  }
  elseif ($selected.domain -eq 'AICS') {
    Write-Host '=== AICS DOMAIN ROUTING ==='
    Write-Host 'Execution Gate: BLOCKED'
    Write-Host 'Reason: LIVE_FINANCIAL_EXECUTION_REQUIRES_K'
    if ($selected.id -eq 'AICS-PAPER-RISK-ENGINE') {
      $paperAdapter="$PSScriptRoot\AX_AICS_PAPER_RISK_ADAPTER.ps1"
      if (Test-Path $paperAdapter) { & powershell.exe -ExecutionPolicy Bypass -File $paperAdapter -TaskId $selected.id; if ($LASTEXITCODE -ne 0) { throw "AX_AICS_PAPER_RISK_ADAPTER_FAILED:$LASTEXITCODE" } }
    }
  }
}
else { Write-Host 'Runtime Gate: NOT_READY'; Write-Host 'Controlled execution deferred'; Write-Host 'Mutation: NOT_PERFORMED' }

Write-Host '=== PERMISSION ==='
Write-Host 'Live-money execution: DISABLED'
Write-Host 'Financial transactions: NOT PERMITTED'
Write-Host 'Repository mutation: NOT_PERFORMED_BY_THIS_CYCLE'
Write-Host '=== AX ACTION DISPATCHER COMPLETE ==='
Write-Host "Helper Agent Route Selected: $agentRouteSelected"
Write-Host 'Live Financial Execution: DISABLED'
