param(
  [string]$RegistryPath = "$PSScriptRoot\AX_TASK_REGISTRY.json",
  [string]$DispatcherPath = "$PSScriptRoot\AX_ACTION_DISPATCHER.ps1",
  [string]$LogPath = "$PSScriptRoot\AX_SUPERVISOR.log"
)

$ErrorActionPreference = 'Stop'

# ============================================================
# AX SUPERVISOR TRIGGER
# Purpose:
#   Wake the AX execution loop on a heartbeat.
#   Observe -> Analyze/Route -> Dispatch -> record evidence.
#
# This script is intentionally ONE-SHOT. Windows Task Scheduler
# should invoke it every minute during the test phase.
# It must never create another scheduler trigger itself.
# ============================================================

$started = Get-Date

function Write-SupervisorLog([string]$Message) {
  $line = "[{0}] {1}" -f (Get-Date).ToUniversalTime().ToString('o'), $Message
  Add-Content -Path $LogPath -Value $line -Encoding UTF8
  Write-Host $line
}

Write-SupervisorLog '=== AX SUPERVISOR CYCLE START ==='

if (-not (Test-Path $RegistryPath)) {
  Write-SupervisorLog "REGISTRY_NOT_FOUND: $RegistryPath"
  exit 10
}

if (-not (Test-Path $DispatcherPath)) {
  Write-SupervisorLog "DISPATCHER_NOT_FOUND: $DispatcherPath"
  exit 11
}

# Prevent overlapping supervisor cycles when a previous cycle is still running.
$mutexName = 'Global\AERIS_AX_SUPERVISOR_CYCLE'
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$lockAcquired = $false

try {
  $lockAcquired = $mutex.WaitOne(0)
  if (-not $lockAcquired) {
    Write-SupervisorLog 'CYCLE_SKIPPED: PREVIOUS_CYCLE_STILL_RUNNING'
    exit 0
  }

  $registry = Get-Content -Raw -Path $RegistryPath | ConvertFrom-Json
  $eligible = @($registry.tasks | Where-Object {
    $_.state -notin $registry.policy.terminal_states -and
    $_.state -ne 'WAITING_K'
  }) | Sort-Object -Property @{ Expression = { [int]$_.priority }; Descending = $true }

  if ($eligible.Count -eq 0) {
    Write-SupervisorLog 'OBSERVE: NO_ELIGIBLE_TASK'
    Write-SupervisorLog 'DECISION: WAIT_FOR_NEXT_HEARTBEAT'
    exit 0
  }

  $selected = $eligible[0]
  Write-SupervisorLog "OBSERVE: TASK=$($selected.id) STATE=$($selected.state) PRIORITY=$($selected.priority)"
  Write-SupervisorLog "DECISION: ACTION=$($selected.next_action)"

  # The dispatcher performs runtime health gates and controlled routing.
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DispatcherPath -RegistryPath $RegistryPath
  $exitCode = $LASTEXITCODE

  if ($exitCode -eq 0) {
    Write-SupervisorLog 'DISPATCH: CYCLE_RETURNED_SUCCESS'
  }
  else {
    Write-SupervisorLog "DISPATCH: CYCLE_RETURNED_EXITCODE=$exitCode"
  }

  Write-SupervisorLog "CYCLE_DURATION_SECONDS=$([math]::Round(((Get-Date)-$started).TotalSeconds,2))"
  Write-SupervisorLog '=== AX SUPERVISOR CYCLE END ==='
  exit $exitCode
}
catch {
  Write-SupervisorLog "SUPERVISOR_ERROR: $($_.Exception.Message)"
  Write-SupervisorLog 'RECOVERY: NEXT_HEARTBEAT_WILL_RETRY'
  exit 20
}
finally {
  if ($lockAcquired) {
    $mutex.ReleaseMutex() | Out-Null
  }
  $mutex.Dispose()
}
