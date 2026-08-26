
param(
  [string]$RegistryPath = "$PSScriptRoot\AX_TASK_REGISTRY.json"
)

$ErrorActionPreference = 'Stop'

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
# CANONICAL AERIS EXECUTION RUNTIME
# ============================================================

$canonicalRuntimeUrl = 'https://aeris-execution-runtime.aerismusic8.workers.dev'
$runtimeUrl = $canonicalRuntimeUrl

if (-not [string]::IsNullOrWhiteSpace($env:AX_CLOUDFLARE_RUNTIME_URL)) {
  $candidateRuntimeUrl = $env:AX_CLOUDFLARE_RUNTIME_URL.TrimEnd('/')

  if ($candidateRuntimeUrl -eq $canonicalRuntimeUrl) {
    $runtimeUrl = $candidateRuntimeUrl
  }
  else {
    Write-Host "Runtime environment override rejected: $candidateRuntimeUrl"
    Write-Host "Using canonical runtime: $canonicalRuntimeUrl"
  }
}

Write-Host "Canonical Runtime: $canonicalRuntimeUrl"
Write-Host "Selected Runtime: $runtimeUrl"

# ============================================================
# CLOUDFLARE CONTROLLED DISPATCH
# ============================================================

$runtimeHealthy = $false

Write-Host '=== CLOUDFLARE CONTROLLED DISPATCH ==='

try {
  $healthUrl = "$($runtimeUrl.TrimEnd('/'))/health"
  Write-Host "Health URL: $healthUrl"

  $health = Invoke-RestMethod `
    -Uri $healthUrl `
    -Method Get `
    -TimeoutSec 15

  $runtimeHealthy = (
    $health.status -eq 'ONLINE' -and
    (
      $health.mode -eq 'REAL_GEMINI_DISPATCH' -or
      $health.mode -eq 'FREE_ONLY'
    ) -and
    $health.liveFinancialExecution -ne $true
  )

  if ($runtimeHealthy) {
    Write-Host 'Cloudflare Runtime Health: ONLINE'
    Write-Host "Runtime Status: $($health.status)"
    Write-Host "Runtime Mode: $($health.mode)"
    Write-Host "Gemini: $($health.gemini)"
    Write-Host "Apps Script: $($health.appsScript)"
    Write-Host "Token Storage: $($health.tokenStorage)"
    Write-Host 'Live Financial Execution: DISABLED'
  }
  else {
    Write-Host 'Cloudflare Runtime Health: REJECTED_BY_HEALTH_POLICY'
    Write-Host "Status: $($health.status)"
    Write-Host "Mode: $($health.mode)"
  }
}
catch {
  Write-Host "Cloudflare Runtime Health: UNAVAILABLE ($($_.Exception.Message))"
}

# ============================================================
# CONTROLLED CLOUDFLARE DISPATCH ADAPTER
# ============================================================

if ($runtimeHealthy) {

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

  Write-Host 'Cloudflare Runtime: NOT_READY'
  Write-Host 'Controlled execution deferred'
  Write-Host 'Mutation: NOT_PERFORMED'
}

# ============================================================
# DOMAIN ROUTING
# ============================================================

switch ($selected.domain) {

  'AERIS' {

    Write-Host 'Route: AERIS_EXECUTION_QUEUE'
    Write-Host 'Execution Gate: CONTROLLED'

    if ($runtimeHealthy) {

      Write-Host '=== AX AERIS EXECUTION ADAPTER ==='

      & powershell.exe `
        -ExecutionPolicy Bypass `
        -File "$PSScriptRoot\AX_AERIS_EXECUTION_ADAPTER.ps1" `
        -StatusUrl "$($runtimeUrl.TrimEnd('/'))/health"

      if ($LASTEXITCODE -ne 0) {
        throw "AX_AERIS_EXECUTION_ADAPTER_FAILED:$LASTEXITCODE"
      }

    }
    else {

      Write-Host 'Execution: DEFERRED — Cloudflare Runtime health gate not ready'
      Write-Host 'Mutation: NOT_PERFORMED'
    }
  }

  'AICS' {

    Write-Host 'Route: AICS_RISK_ENGINE'

    if (
      $selected.id -eq 'AICS-LIVE-TRADING' -or
      $registry.policy.financial_execution_enabled -ne $true
    ) {

      Write-Host 'Execution Gate: BLOCKED'
      Write-Host 'Reason: LIVE_FINANCIAL_EXECUTION_REQUIRES_K'

      if ($selected.id -eq 'AICS-PAPER-RISK-ENGINE') {

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

  'AX' {

    Write-Host 'Route: AX_INTERNAL_EXECUTION'
    Write-Host 'Execution Gate: CONTROLLED'
    Write-Host 'Execution: NOT_PERFORMED'
  }

  default {

    Write-Host 'Route: UNKNOWN'
    Write-Host 'Execution Gate: BLOCKED'
    Write-Host 'Execution: NOT_PERFORMED'
  }
}

Write-Host '=== AX ACTION DISPATCHER COMPLETE ==='
