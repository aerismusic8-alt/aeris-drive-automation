param(
  [string]$RegistryPath = "$PSScriptRoot\AX_MASTER_BRAIN\AX_MASTER_TASK_REGISTRY_v2.json"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $RegistryPath)) { throw "AX_TASK_REGISTRY_NOT_FOUND: $RegistryPath" }
$selectorPath = Join-Path $PSScriptRoot 'AX_TASK_SELECTOR.ps1'
if (-not (Test-Path $selectorPath)) { throw "AX_TASK_SELECTOR_NOT_FOUND: $selectorPath" }
. $selectorPath
$sourceRegistry = Get-Content -Raw -Path $RegistryPath | ConvertFrom-Json
$registry = if ([string]$sourceRegistry.registry_role -eq 'AUTHORITATIVE_AKATH_MASTER_TASK_STATUS') { Convert-AxMasterRegistry -MasterRegistry $sourceRegistry } else { $sourceRegistry }
$tasks = @($registry.tasks)
$selected = Select-AxNextTask -Registry $registry

Write-Host '=== AX DECISION ENGINE ==='
Write-Host "Registry: $RegistryPath"
Write-Host "Canonical Source: $($registry.source)"
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
