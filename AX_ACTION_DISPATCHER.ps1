param(
  [string]$RegistryPath = "$PSScriptRoot\AX_TASK_REGISTRY.json"
)

$ErrorActionPreference = 'Stop'

# ============================================================
# AX ACTION DISPATCHER
# Route contract:
#   AX Control Runtime    -> GET /health
#   AERIS External Runtime -> GET /
#   Helper agents         -> verified capability route, then canonical fallback
# ============================================================

if (-not (Test-Path $RegistryPath)) {
  throw "AX_TASK_REGISTRY_NOT_FOUND: $RegistryPath"
}

$selectorPath = Join-Path $PSScriptRoot 'AX_TASK_SELECTOR.ps1'
if (-not (Test-Path $selectorPath)) {
  throw "AX_TASK_SELECTOR_NOT_FOUND: $selectorPath"
}
. $selectorPath

$registry = Get-Content -Raw -Path $RegistryPath | ConvertFrom-Json
$tasks = @($registry.tasks)

# Canonical selector: dependencies are enforced before priority.
$selected = Select-AxNextTask -Registry $registry

Write-Host '=== AX ACTION DISPATCHER ==='

if ($null -eq $selected) {
  Write-Host 'Dispatch: NO_ELIGIBLE_TASK'
  Write-Host 'Execution: NOT_PERFORMED'
  exit 0
}

# Defense-in-depth: revalidate the selected task immediately before dispatch.
if (-not (Test-AxTaskDependencies -Registry $registry -Task $selected)) {
  throw "AX_DEPENDENCY_GATE_REJECTED:$($selected.id)"
}

Write-Host "Task ID: $($selected.id)"
Write-Host "Domain: $($selected.domain)"
Write-Host "Priority: $($selected.priority)"
Write-Host "Requested Action: $($selected.next_action)"
Write-Host 'Dependency Gate: PASSED'

# ============================================================
# HELPER-AGENT ROUTING
# Gemini/Copilot may only take work when their executable capability
# is verified. If not, they are unavailable capacity and the task
# falls through to the canonical runtime. Route acceptance is NOT
# task completion and never mutates task state.
# ============================================================

$agentRoutingBridge = Join-Path $PSScriptRoot 'AX_AGENT_ROUTING_BRIDGE.ps1'
$agentRouteSelected = $false

if (Test-Path $agentRoutingBridge) {
  $agentCandidates = @('GEMINI','COPILOT')
  $agentRoutingResult = & powershell.exe `
    -ExecutionPolicy Bypass `
    -File $agentRoutingBridge `
    -TaskId $selected.id `
    -Domain $selected.domain `
    -Candidates $agentCandidates 2>&1

  if ($LASTEXITCODE -eq 0) {
    $agentRouteSelected = $true
    Write-Host 'Helper Agent Route: VERIFIED'
    Write-Host ($agentRoutingResult | Out-String).Trim()
    Write-Host 'Task Completion: NOT_CLAIMED'
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

# ============================================================
# AX CONTROL RUNTIME HEALTH
# ============================================================

$controlRuntimeHealthy = $false

Write-Host '=== AX CONTROL RUNTIME HEALTH ==='

try {
  $controlHealthUrl = "$($controlRuntimeUrl.TrimEnd('/'))/health"
  Write-Host "Health URL: $controlHealthUrl"
  $controlHealth = Invoke-RestMethod -Uri $controlHealthUrl -Method Get -TimeoutSec 15
  $controlRuntimeHealthy = (
    $controlHealth.status -eq 'ONLINE' -and
    $controlHealth.mode -eq 'FREE_ONLY' -and
    $controlHealth.liveFinancialExecution -eq $false -and
    $controlHealth.queue -eq 'ax-execution-events'
  )
  if ($controlRuntimeHealthy) {
    Write-Host 'AX Control Runtime Health: ONLINE'
    Write-Host "Mode: $($controlHealth.mode)"
    Write-Host "Queue: $($controlHealth.queue)"
    Write-Host 'Live Financial Execution: DISABLED'
  }
  else {
    Write-Host 'AX Control Runtime Health: REJECTED_BY_POLICY'
    Write-Host "Status: $($controlHealth.status)"
    Write-Host "Mode: $($controlHealth.mode)"
  }
}
catch {
  Write-Host "AX Control Runtime Health: UNAVAILABLE ($($_.Exception.Message))"
}

# ============================================================
# AERIS EXTERNAL RUNTIME HEALTH
# IMPORTANT: AERIS Runtime exposes GET /, not GET /health.
# ============================================================

$aerisRuntimeHealthy = $false
$aerisIdentityVerified = $false

Write-Host '=== AERIS EXTERNAL RUNTIME HEALTH ==='

try {
  $aerisProbeUrl = "$($aerisRuntimeUrl.TrimEnd('/'))/"
  Write-Host "Identity Probe: $aerisProbeUrl"
  $aerisResponse = Invoke-WebRequest -Uri $aerisProbeUrl -Method Get -UseBasicParsing -TimeoutSec 15
  if ($aerisResponse.StatusCode -ne 200) { throw "AERIS_RUNTIME_HTTP_$($aerisResponse.StatusCode)" }
  $aerisHealth = $aerisResponse.Content | ConvertFrom-Json
  $aerisIdentityVerified = (
    $aerisHealth.service -eq 'AERIS_EXTERNAL_EXECUTION_RUNTIME' -and
    $aerisHealth.status -eq 'ONLINE' -and
    $aerisHealth.gate -eq 'GATE_3'
  )
  $aerisCapabilitiesVerified = (
    $aerisHealth.appsScript -eq 'OAUTH_READY' -and
    $aerisHealth.appsScriptExecution -eq 'READY' -and
    $aerisHealth.gemini -eq 'READY' -and
    (@($aerisHealth.endpoints) -contains 'POST /execute')
  )
  $aerisFinancialSafe = ($aerisHealth.liveFinancialExecution -ne $true)
  $aerisRuntimeHealthy = ($aerisIdentityVerified -and $aerisCapabilitiesVerified -and $aerisFinancialSafe)
  if ($aerisRuntimeHealthy) {
    Write-Host 'AERIS External Runtime Health: ONLINE'
    Write-Host "Service: $($aerisHealth.service)"
    Write-Host "Status: $($aerisHealth.status)"
    Write-Host "Version: $($aerisHealth.version)"
    Write-Host "Gate: $($aerisHealth.gate)"
    Write-Host "Mode: $($aerisHealth.mode)"
    Write-Host "Apps Script: $($aerisHealth.appsScript)"
    Write-Host "Apps Script Execution: $($aerisHealth.appsScriptExecution)"
    Write-Host "Gemini: $($aerisHealth.gemini)"
    Write-Host "Token Storage: $($aerisHealth.tokenStorage)"
    Write-Host 'Live Financial Execution: DISABLED'
  }
  else { Write-Host 'AERIS External Runtime Health: REJECTED_BY_POLICY' }
}
catch { Write-Host "AERIS External Runtime Health: UNAVAILABLE ($($_.Exception.Message))" }

# ============================================================
# CONTROLLED DISPATCH
# ============================================================

Write-Host '=== CONTROLLED CLOUDFLARE DISPATCH ==='

if ($controlRuntimeHealthy -and $aerisRuntimeHealthy) {
  Write-Host 'Runtime Gate: READY'
  Write-Host 'Execution Gate: CONTROLLED'
  Write-Host 'Health Verification: PASSED'
  Write-Host '=== AX CONTROL QUEUE DISPATCH ==='
  Write-Host "Task: $($selected.id)"
  Write-Host "Action: $($selected.next_action)"

  $eventId = [guid]::NewGuid().ToString()
  $event = @{
    id=$eventId; taskId=[string]$selected.id; domain=[string]$selected.domain
    priority=[int]$selected.priority; action=[string]$selected.next_action
    createdAt=(Get-Date).ToUniversalTime().ToString('o'); source='AX_ACTION_DISPATCHER'
  }
  $eventJson = $event | ConvertTo-Json -Compress

  try {
    $enqueueHeaders = @{
      Authorization="Bearer $env:GITHUB_TOKEN"
      'X-AERIS-REPOSITORY'='aerismusic8-alt/aeris-drive-automation'
      'Content-Type'='application/json'
    }
    $enqueueResponse = Invoke-RestMethod -Uri "$($controlRuntimeUrl.TrimEnd('/'))/enqueue" -Method Post -Headers $enqueueHeaders -Body $eventJson -TimeoutSec 15
    if ($enqueueResponse.accepted -ne $true) { throw 'AX_CONTROL_RUNTIME_ENQUEUE_NOT_ACCEPTED' }
    Write-Host 'AX Control Runtime: EVENT_ACCEPTED'
    Write-Host "Event ID: $eventId"
    Write-Host "Queued: $($enqueueResponse.queued)"
  }
  catch { Write-Host "AX Control Runtime enqueue failed: $($_.Exception.Message)"; throw }

  if ($selected.domain -eq 'AERIS') {
    Write-Host '=== AERIS DOMAIN ROUTING ==='
    Write-Host 'Route: AERIS_EXECUTION_QUEUE'
    Write-Host 'External Runtime: aeris-execution-runtime'
    Write-Host 'Execution Gate: CONTROLLED'
    Write-Host 'External Runtime Health: VERIFIED'
    $aerisAdapter = "$PSScriptRoot\AX_AERIS_EXECUTION_ADAPTER.ps1"
    if (Test-Path $aerisAdapter) {
      Write-Host '=== AX AERIS EXECUTION ADAPTER ==='
      & powershell.exe -ExecutionPolicy Bypass -File $aerisAdapter -StatusUrl "$($aerisRuntimeUrl.TrimEnd('/'))/"
      if ($LASTEXITCODE -ne 0) { throw "AX_AERIS_EXECUTION_ADAPTER_FAILED:$LASTEXITCODE" }
      Write-Host 'AERIS Execution Adapter: COMPLETED'
    }
    else { Write-Host "AERIS adapter not found: $aerisAdapter"; Write-Host 'Execution: QUEUED_TO_CONTROL_RUNTIME' }
  }
  elseif ($selected.domain -eq 'AICS') {
    Write-Host '=== AICS DOMAIN ROUTING ==='
    Write-Host 'Route: AICS_RISK_ENGINE'
    if ($selected.id -eq 'AICS-LIVE-TRADING' -or $registry.policy.financial_execution_enabled -ne $true) {
      Write-Host 'Execution Gate: BLOCKED'
      Write-Host 'Reason: LIVE_FINANCIAL_EXECUTION_REQUIRES_K'
      if ($selected.id -eq 'AICS-PAPER-RISK-ENGINE') {
        $paperAdapter="$PSScriptRoot\AX_AICS_PAPER_RISK_ADAPTER.ps1"
        if (Test-Path $paperAdapter) {
          & powershell.exe -ExecutionPolicy Bypass -File $paperAdapter -TaskId $selected.id
          if ($LASTEXITCODE -ne 0) { throw "AX_AICS_PAPER_RISK_ADAPTER_FAILED:$LASTEXITCODE" }
          Write-Host 'AICS Paper Risk Adapter: COMPLETED'
        } else { Write-Host "AICS paper adapter not found: $paperAdapter"; Write-Host 'Execution: NOT_PERFORMED' }
      } else { Write-Host 'Execution: NOT_PERFORMED' }
    } else { Write-Host 'Execution Gate: CONTROLLED'; Write-Host 'Execution: NOT_PERFORMED' }
  }
  elseif ($selected.domain -eq 'AX') {
    Write-Host '=== AX INTERNAL ROUTING ==='
    Write-Host 'Route: AX_INTERNAL_EXECUTION'
    Write-Host 'Execution Gate: CONTROLLED'
    Write-Host 'Execution: QUEUED_TO_CONTROL_RUNTIME'
  }
  else {
    Write-Host '=== UNKNOWN DOMAIN ==='
    Write-Host 'Route: UNKNOWN'
    Write-Host 'Execution Gate: BLOCKED'
    Write-Host 'Execution: NOT_PERFORMED'
  }
}
else {
  Write-Host 'Runtime Gate: NOT_READY'
  Write-Host 'Controlled execution deferred'
  Write-Host 'Mutation: NOT_PERFORMED'
}

Write-Host '=== PERMISSION ==='
Write-Host 'Live-money execution: DISABLED'
Write-Host 'Financial transactions: NOT PERMITTED'
Write-Host 'Repository mutation: NOT_PERFORMED_BY_THIS_CYCLE'
Write-Host '=== AX ACTION DISPATCHER COMPLETE ==='
Write-Host "Control Runtime: $controlRuntimeUrl"
Write-Host "External Runtime: $aerisRuntimeUrl"
Write-Host "Control Runtime Healthy: $controlRuntimeHealthy"
Write-Host "External Runtime Healthy: $aerisRuntimeHealthy"
Write-Host "Helper Agent Route Selected: $agentRouteSelected"
Write-Host 'Live Financial Execution: DISABLED'
