param(
  [string]$RegistryPath = "$PSScriptRoot\AX_TASK_REGISTRY.json"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $RegistryPath)) { throw "AX_TASK_REGISTRY_NOT_FOUND: $RegistryPath" }
$registry = Get-Content -Raw -Path $RegistryPath | ConvertFrom-Json
$tasks = @($registry.tasks)
$byId = @{}
foreach ($task in $tasks) { $byId[$task.id] = $task }

$eligible = foreach ($task in $tasks) {
  if ($task.state -in $registry.policy.terminal_states -or $task.state -eq 'WAITING_K') { continue }
  $deps = @($task.depends_on)
  $depsReady = $true
  foreach ($dep in $deps) {
    if (-not $byId.ContainsKey($dep) -or $byId[$dep].state -ne 'COMPLETED') { $depsReady = $false; break }
  }
  if ($depsReady) { $task }
}
$selected = $eligible | Sort-Object -Property @{Expression={[int]$_.priority};Descending=$true} | Select-Object -First 1

Write-Host '=== AX DECISION ENGINE ==='
Write-Host "Registry: $RegistryPath"
Write-Host "Task Count: $($tasks.Count)"
Write-Host "Scheduler: priority=$($registry.policy.scheduler.priority_precedence) dependencies=$($registry.policy.scheduler.dependency_enforcement) event_driven=$($registry.policy.scheduler.event_driven_enabled)"
if ($null -eq $selected) {
  Write-Host 'Decision: NO_ELIGIBLE_TASK'
  Write-Host 'Next State: WAITING'
  exit 0
}
Write-Host 'Decision: SELECT_TASK'
Write-Host "Task ID: $($selected.id)"
Write-Host "Domain: $($selected.domain)"
Write-Host "Priority: $($selected.priority)"
Write-Host "State: $($selected.state)"
Write-Host "Trigger: $($selected.trigger)"
Write-Host "Next Action: $($selected.next_action)"
Write-Host 'Permission: CONTROLLED_AUTONOMOUS_PLANNING'
Write-Host 'Execution: DISPATCHED_TO_NEXT_GATE'
Write-Host '=== AX DECISION ENGINE COMPLETE ==='
