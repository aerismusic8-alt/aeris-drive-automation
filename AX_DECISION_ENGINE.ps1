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

Write-Host "=== AX DECISION ENGINE ==="
Write-Host "Registry: $RegistryPath"
Write-Host "Task Count: $($tasks.Count)"

if ($null -eq $selected) {
  Write-Host "Decision: NO_ELIGIBLE_TASK"
  Write-Host "Next State: WAITING_K"
  exit 0
}

Write-Host "Decision: SELECT_TASK"
Write-Host "Task ID: $($selected.id)"
Write-Host "Domain: $($selected.domain)"
Write-Host "Priority: $($selected.priority)"
Write-Host "State: $($selected.state)"
Write-Host "Next Action: $($selected.next_action)"
Write-Host "Permission: READ_ONLY_PLANNING"
Write-Host "Execution: NOT_PERFORMED"
Write-Host "=== AX DECISION ENGINE COMPLETE ==="
