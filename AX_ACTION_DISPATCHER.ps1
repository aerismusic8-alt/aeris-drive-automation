param(
  [string]$RegistryPath = "$PSScriptRoot\AX_TASK_REGISTRY.json"
)

$ErrorActionPreference = 'Stop'

# ============================================================
# AX ACTION DISPATCHER
# ARCHITECTURE:
#
# AX Control Runtime
#   -> ax-control-runtime
#   -> ax-execution-events
#
# AERIS External Execution Runtime
#   -> aeris-execution-runtime
#   -> Gate 3.3.2 / Gemini / Apps Script
#
# IMPORTANT:
# These two runtimes MUST remain separate.
# ============================================================

if (-not (Test-Path $RegistryPath)) {
  throw "AX_TASK_REGISTRY_NOT_FOUND: $RegistryPath"
}

$registry = Get-Content -Raw -Path $RegistryPath | ConvertFrom-Json
$tasks = @($registry.tasks)

$eligible = $tasks |
  Where-Object {
    $_.state -notin $registry.policy.terminal_states -and
    $_.state -ne 'WAITING_K'
  } |
  Sort-Object -Property @{
    Expression = { [int]$_.priority }
    Descending = $true
  }

$selected = $eligible | Select-Object -First 1

Write-Host '=== AX ACTION DISPATCHER ==='

if ($null -eq $selected) {
  Write-Host 'Dispatch: NO_ELIGIBLE_TASK'
  Write-Host 'Execution: NOT_PERFORMED'
  exit 0
}

Write-Host "Task ID: $($selected.id)"
Write-Host "Domain: $($selected.domain)"
Write-Host "Priority: $($selected.priority)"
Write-Host "Requested Action: $($selected.next_action)"

# ============================================================
# RUNTIME DEFINITIONS
# ============================================================

$controlRuntimeUrl =
  'https://ax-control-runtime.aerismusic8.workers.dev'

$externalRuntimeUrl =
  'https://aeris-execution-runtime.aerismusic8.workers.dev'

Write-Host "AX Control Runtime: $controlRuntimeUrl"
Write-Host "AERIS External Runtime: $externalRuntimeUrl"

# ============================================================
# CONTROL RUNTIME SELECTION
# ============================================================

$runtimeUrl = $controlRuntimeUrl

if (-not [string]::IsNullOrWhiteSpace($env:AX_CONTROL_RUNTIME_URL)) {

  $candidateRuntimeUrl =
    $env:AX_CONTROL_RUNTIME_URL.TrimEnd('/')

  if (
    $candidateRuntimeUrl -eq $controlRuntimeUrl
  ) {
    $runtimeUrl = $candidateRuntimeUrl
  }
  else {
    Write-Host "Control runtime override rejected: $candidateRuntimeUrl"
    Write-Host "Using canonical AX Control Runtime: $controlRuntimeUrl"
  }
}

Write-Host "Selected Control Runtime: $runtimeUrl"

# ============================================================
# CONTROL RUNTIME HEALTH
# ============================================================

$runtimeHealthy = $false

Write-Host '=== AX CONTROL RUNTIME HEALTH ==='

try {

  $healthUrl =
    "$($runtimeUrl.TrimEnd('/'))/health"

  Write-Host "Health URL: $healthUrl"

  $health = Invoke-RestMethod `
    -Uri $healthUrl `
    -Method Get `
    -TimeoutSec 15

  Write-Host "Status: $($health.status)"
  Write-Host "Mode: $($health.mode)"
  Write-Host "Queue: $($health.queue)"
  Write-Host "Live Financial Execution: $($health.liveFinancialExecution)"

  $runtimeHealthy = (
    $health.status -eq 'ONLINE' -and
    $health.mode -eq 'FREE_ONLY' -and
    $health.liveFinancialExecution -eq $false -and
    $health.queue -eq 'ax-execution-events'
  )

  if ($runtimeHealthy) {

    Write-Host 'AX Control Runtime Health: ONLINE'
    Write-Host 'Mode: FREE_ONLY'
    Write-Host 'Live Financial Execution: DISABLED'
    Write-Host 'Queue: ax-execution-events'

  }
  else {

    Write-Host 'AX Control Runtime Health: REJECTED_BY_HEALTH_POLICY'
  }

}
catch {

  Write-Host `
    "AX Control Runtime Health: UNAVAILABLE ($($_.Exception.Message))"
}

# ============================================================
# CONTROLLED DISPATCH
# ============================================================

if ($runtimeHealthy) {

  Write-Host '=== CONTROLLED CLOUDFLARE DISPATCH ==='
  Write-Host 'Runtime Gate: READY'
  Write-Host 'Execution Gate: CONTROLLED'

  & powershell.exe `
    -ExecutionPolicy Bypass `
    -File "$PSScriptRoot\AX_CLOUDFLARE_DISPATCH_ADAPTER.ps1" `
    -RuntimeUrl $runtimeUrl `
    -TaskId $selected.id `
    -Domain $selected.domain `
    -Priority ([int]$selected.priority) `
    -Action $selected.next_action

  if ($LASTEXITCODE -ne 0) {
    throw "AX_CLOUDFLARE_DISPATCH_FAILED:$LASTEXITCODE"
  }

}
else {

  Write-Host '=== CONTROLLED CLOUDFLARE DISPATCH ==='
  Write-Host 'Runtime Gate: NOT_READY'
  Write-Host 'Controlled execution deferred'
  Write-Host 'Mutation: NOT_PERFORMED'
}

# ============================================================
# DOMAIN ROUTING
# ============================================================

switch ($selected.domain) {

  # ----------------------------------------------------------
  # AERIS
  # ----------------------------------------------------------

  'AERIS' {

    Write-Host '=== AERIS DOMAIN ROUTING ==='

    Write-Host 'Route: AERIS_EXECUTION_QUEUE'
    Write-Host 'External Runtime: aeris-execution-runtime'
    Write-Host 'Execution Gate: CONTROLLED'

    # AERIS execution belongs to the existing
    # Gate 3.3.2 External Execution Runtime.
    #
    # IMPORTANT:
    # Do NOT send the AERIS execution adapter through
    # ax-control-runtime.

    try {

      $externalHealthUrl =
        "$($externalRuntimeUrl.TrimEnd('/'))/health"

      Write-Host "External Runtime Health: $externalHealthUrl"

      $externalHealth = Invoke-RestMethod `
        -Uri $externalHealthUrl `
        -Method Get `
        -TimeoutSec 15

      Write-Host "External Runtime Status: $($externalHealth.status)"
      Write-Host "External Runtime Mode: $($externalHealth.mode)"

      $externalHealthy = (
        $externalHealth.status -eq 'ONLINE' -and
        $externalHealth.liveFinancialExecution -ne $true
      )

      if ($externalHealthy) {

        Write-Host 'AERIS External Runtime: ONLINE'

        Write-Host '=== AX AERIS EXECUTION ADAPTER ==='

        & powershell.exe `
          -ExecutionPolicy Bypass `
          -File "$PSScriptRoot\AX_AERIS_EXECUTION_ADAPTER.ps1" `
          -StatusUrl $externalHealthUrl

        if ($LASTEXITCODE -ne 0) {
          throw "AX_AERIS_EXECUTION_ADAPTER_FAILED:$LASTEXITCODE"
        }

      }
      else {

        Write-Host 'AERIS External Runtime: REJECTED_BY_HEALTH_POLICY'
        Write-Host 'Execution: DEFERRED'
        Write-Host 'Mutation: NOT_PERFORMED'
      }

    }
    catch {

      Write-Host `
        "AERIS External Runtime: UNAVAILABLE ($($_.Exception.Message))"

      Write-Host 'Execution: DEFERRED'
      Write-Host 'Mutation: NOT_PERFORMED'
    }
  }

  # ----------------------------------------------------------
  # AICS
  # ----------------------------------------------------------

  'AICS' {

    Write-Host '=== AICS DOMAIN ROUTING ==='
    Write-Host 'Route: AICS_RISK_ENGINE'

    if (
      $selected.id -eq 'AICS-LIVE-TRADING' -or
      $registry.policy.financial_execution_enabled -ne $true
    ) {

      Write-Host 'Execution Gate: BLOCKED'
      Write-Host 'Reason: LIVE_FINANCIAL_EXECUTION_REQUIRES_K'

      if ($selected.id -eq 'AICS-PAPER-RISK-ENGINE') {

        Write-Host 'Paper Risk Engine: CONTROLLED'

        & powershell.exe `
          -ExecutionPolicy Bypass `
          -File "$PSScriptRoot\AX_AICS_PAPER_RISK_ADAPTER.ps1" `
          -TaskId $selected.id

        if ($LASTEXITCODE -ne 0) {
          throw "AX_AICS_PAPER_RISK_ADAPTER_FAILED:$LASTEXITCODE"
        }

      }
      else {

        Write-Host 'Execution: NOT_PERFORMED'
      }

    }
    else {

      Write-Host 'Execution Gate: CONTROLLED'
      Write-Host 'Execution: NOT_PERFORMED'
    }
  }

  # ----------------------------------------------------------
  # AX
  # ----------------------------------------------------------

  'AX' {

    Write-Host '=== AX INTERNAL ROUTING ==='
    Write-Host 'Route: AX_INTERNAL_EXECUTION'
    Write-Host 'Execution Gate: CONTROLLED'
    Write-Host 'Execution: NOT_PERFORMED'
  }

  # ----------------------------------------------------------
  # UNKNOWN
  # ----------------------------------------------------------

  default {

    Write-Host 'Route: UNKNOWN'
    Write-Host 'Execution Gate: BLOCKED'
    Write-Host 'Execution: NOT_PERFORMED'
  }
}

# ============================================================
# FINAL
# ============================================================

Write-Host ''
Write-Host '=== AX ACTION DISPATCHER COMPLETE ==='
Write-Host "Control Runtime: $runtimeUrl"
Write-Host "External Runtime: $externalRuntimeUrl"
Write-Host 'Live Financial Execution: DISABLED'
