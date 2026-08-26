param(
  [string]$RegistryPath = "$PSScriptRoot\AX_TASK_REGISTRY.json"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $RegistryPath)) { throw "AX_TASK_REGISTRY_NOT_FOUND: $RegistryPath" }
$registry = Get-Content -Raw -Path $RegistryPath | ConvertFrom-Json
$tasks = @($registry.tasks)
$eligible = $tasks | Where-Object { $_.state -notin $registry.policy.terminal_states -and $_.state -ne 'WAITING_K' } | Sort-Object -Property @{Expression={[int]$_.priority};Descending=$true}
$selected = $eligible | Select-Object -First 1
Write-Host '=== AX ACTION DISPATCHER ==='
if ($null -eq $selected) { Write-Host 'Dispatch: NO_ELIGIBLE_TASK'; Write-Host 'Execution: NOT_PERFORMED'; exit 0 }
Write-Host "Task ID: $($selected.id)"
Write-Host "Domain: $($selected.domain)"
Write-Host "Priority: $($selected.priority)"
Write-Host "Requested Action: $($selected.next_action)"

if (-not [string]::IsNullOrWhiteSpace($env:AX_CLOUDFLARE_RUNTIME_URL)) {
  Write-Host '=== CLOUDFLARE CONTROLLED DISPATCH ==='
  $runtimeHealthy = $false
  try {
    $health = Invoke-RestMethod -Uri "$($env:AX_CLOUDFLARE_RUNTIME_URL)/health" -Method Get -TimeoutSec 10
    $runtimeHealthy = ($health.status -eq 'ONLINE' -and $health.mode -eq 'FREE_ONLY' -and $health.liveFinancialExecution -eq $false)
    if ($runtimeHealthy) {
      Write-Host 'Cloudflare Runtime Health: ONLINE / FREE_ONLY / LIVE_EXECUTION_DISABLED'
    } else {
      Write-Host 'Cloudflare Runtime Health: REJECTED_BY_HEALTH_POLICY'
    }
  } catch {
    Write-Host "Cloudflare Runtime Health: UNAVAILABLE ($($_.Exception.Message))"
  }
  if ($runtimeHealthy) {
    & powershell.exe -ExecutionPolicy Bypass -File "$PSScriptRoot\AX_CLOUDFLARE_DISPATCH_ADAPTER.ps1" -TaskId $selected.id -Domain $selected.domain -Priority ([int]$selected.priority) -Action $selected.next_action
    if ($LASTEXITCODE -ne 0) { throw "AX_CLOUDFLARE_DISPATCH_FAILED:$LASTEXITCODE" }
  } else {
    Write-Host 'Cloudflare Runtime: NOT_READY — local controlled path retained'
  }
} else {
  Write-Host 'Cloudflare Runtime: NOT_CONFIGURED'
}

switch ($selected.domain) {
  'AERIS' {
    Write-Host 'Route: AERIS_EXECUTION_QUEUE'
    Write-Host 'Execution Gate: CONTROLLED'
    & powershell.exe -ExecutionPolicy Bypass -File "$PSScriptRoot\AX_AERIS_EXECUTION_ADAPTER.ps1"
    if ($LASTEXITCODE -ne 0) { throw "AX_AERIS_EXECUTION_ADAPTER_FAILED:$LASTEXITCODE" }
  }
  'AICS' {
    Write-Host 'Route: AICS_RISK_ENGINE'
    if ($selected.id -eq 'AICS-LIVE-TRADING' -or $registry.policy.financial_execution_enabled -ne $true) {
      Write-Host 'Execution Gate: BLOCKED'
      Write-Host 'Reason: LIVE_FINANCIAL_EXECUTION_REQUIRES_K'
      if ($selected.id -eq 'AICS-PAPER-RISK-ENGINE') {
        & powershell.exe -ExecutionPolicy Bypass -File "$PSScriptRoot\AX_AICS_PAPER_RISK_ADAPTER.ps1" -TaskId $selected.id
        if ($LASTEXITCODE -ne 0) { throw "AX_AICS_PAPER_RISK_ADAPTER_FAILED:$LASTEXITCODE" }
      } else { Write-Host 'Execution: NOT_PERFORMED' }
    } else { Write-Host 'Execution Gate: CONTROLLED'; Write-Host 'Execution: NOT_PERFORMED' }
  }
  'AX' { Write-Host 'Route: AX_INTERNAL_EXECUTION'; Write-Host 'Execution Gate: CONTROLLED'; Write-Host 'Execution: NOT_PERFORMED' }
  default { Write-Host 'Route: UNKNOWN'; Write-Host 'Execution Gate: BLOCKED'; Write-Host 'Execution: NOT_PERFORMED' }
}
Write-Host '=== AX ACTION DISPATCHER COMPLETE ==='
