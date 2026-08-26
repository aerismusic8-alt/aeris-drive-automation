param(
  [int]$EstimatedWorkerRequests = 0,
  [int]$EstimatedQueueOperations = 0,
  [int]$EstimatedWorkflowSteps = 0,
  [string]$PolicyPath = "$PSScriptRoot\AX_RESOURCE_GOVERNOR.json",
  [string]$StatePath = "$env:USERPROFILE\.aeris\ax-resource-usage.json"
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PolicyPath)) { throw "AX_RESOURCE_GOVERNOR_POLICY_NOT_FOUND: $PolicyPath" }
$policy = Get-Content -Raw -Path $PolicyPath | ConvertFrom-Json
$dir = Split-Path -Parent $StatePath
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
$state = $null
if (Test-Path $StatePath) {
  try { $state = Get-Content -Raw -Path $StatePath | ConvertFrom-Json } catch { $state = $null }
}
if ($null -eq $state -or $state.date -ne $today) {
  $state = [pscustomobject]@{ date=$today; workerRequests=0; queueOperations=0; workflowSteps=0 }
}

$limits = $policy.policy
$nextWorker = [int]$state.workerRequests + $EstimatedWorkerRequests
$nextQueue = [int]$state.queueOperations + $EstimatedQueueOperations
$nextSteps = [int]$state.workflowSteps + $EstimatedWorkflowSteps

$workerPct = if ($limits.workers_requests_daily_limit -gt 0) { ($nextWorker / $limits.workers_requests_daily_limit) * 100 } else { 100 }
$queuePct = if ($limits.queues_operations_daily_limit -gt 0) { ($nextQueue / $limits.queues_operations_daily_limit) * 100 } else { 100 }
$stepsPct = if ($limits.workflow_steps_daily_limit -gt 0) { ($nextSteps / $limits.workflow_steps_daily_limit) * 100 } else { 100 }
$maxPct = [math]::Max($workerPct, [math]::Max($queuePct, $stepsPct))

$tier = if ($maxPct -ge $limits.hard_stop_percent) { 'HARD_STOP' } elseif ($maxPct -ge $limits.critical_percent) { 'CRITICAL' } elseif ($maxPct -ge $limits.conserve_percent) { 'CONSERVE' } else { 'NORMAL' }

Write-Host '=== AX RESOURCE GOVERNOR ==='
Write-Host "DateUTC: $today"
Write-Host ("Workers Requests: {0}/{1} ({2:N1}%)" -f $nextWorker,$limits.workers_requests_daily_limit,$workerPct)
Write-Host ("Queue Operations: {0}/{1} ({2:N1}%)" -f $nextQueue,$limits.queues_operations_daily_limit,$queuePct)
Write-Host ("Workflow Steps: {0}/{1} ({2:N1}%)" -f $nextSteps,$limits.workflow_steps_daily_limit,$stepsPct)
Write-Host "Tier: $tier"

if ($tier -eq 'HARD_STOP') {
  Write-Host 'Admission: BLOCKED'
  exit 20
}

$state.workerRequests = $nextWorker
$state.queueOperations = $nextQueue
$state.workflowSteps = $nextSteps
$state | ConvertTo-Json -Depth 5 | Set-Content -Path $StatePath -Encoding UTF8
Write-Host 'Admission: ALLOWED'
Write-Host '=== AX RESOURCE GOVERNOR COMPLETE ==='
exit 0
