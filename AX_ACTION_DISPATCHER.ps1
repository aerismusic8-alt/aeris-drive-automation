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
  Where-Object { $_.state -notin $registry.policy.terminal_states -and $_.state -ne 'WAITING_K' } |
  Sort-Object -Property @{Expression={[int]$_.priority};Descending=$true}
$selected = $eligible | Select-Object -First 1

Write-Host "=== AX ACTION DISPATCHER ==="
if ($null -eq $selected) {
  Write-Host "Dispatch: NO_ELIGIBLE_TASK"
  Write-Host "Execution: NOT_PERFORMED"
  exit 0
}

Write-Host "Task ID: $($selected.id)"
Write-Host "Domain: $($selected.domain)"
Write-Host "Priority: $($selected.priority)"
Write-Host "Requested Action: $($selected.next_action)"

switch ($selected.domain) {
  'AERIS' {
    Write-Host "Route: AERIS_EXECUTION_QUEUE"
    Write-Host "Execution Gate: CONTROLLED"
    Write-Host "Execution: NOT_PERFORMED"
  }
  'AICS' {
    Write-Host "Route: AICS_RISK_ENGINE"
    if ($selected.id -eq 'AICS-LIVE-TRADING' -or $registry.policy.financial_execution_enabled -ne $true) {
      Write-Host "Execution Gate: BLOCKED"
      Write-Host "Reason: LIVE_FINANCIAL_EXECUTION_REQUIRES_K"
      Write-Host "Execution: NOT_PERFORMED"
    } else {
      Write-Host "Execution Gate: CONTROLLED"
      Write-Host "Execution: NOT_PERFORMED"
    }
  }
  'AX' {
    Write-Host "Route: AX_INTERNAL_EXECUTION"
    Write-Host "Execution Gate: CONTROLLED"
    Write-Host "Execution: NOT_PERFORMED"
  }
  default {
    Write-Host "Route: UNKNOWN"
    Write-Host "Execution Gate: BLOCKED"
    Write-Host "Execution: NOT_PERFORMED"
  }
}

Write-Host "=== AX ACTION DISPATCHER COMPLETE ==="
