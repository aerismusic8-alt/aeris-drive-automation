param(
  [string]$RegistryPath = "$PSScriptRoot\AX_TASK_REGISTRY.json",
  [string]$DispatcherPath = "$PSScriptRoot\AX_ACTION_DISPATCHER.ps1",
  [string]$LogPath = "$PSScriptRoot\AX_SUPERVISOR.log"
)

$ErrorActionPreference = 'Stop'

# ============================================================
# M ACTING EXECUTIVE SUPERVISOR
# Purpose:
#   M temporarily owns the AX operational/control-plane duties
#   until AX runtime identity is verified.
#   AX remains the master-brain/intelligence layer only.
#
# Loop:
#   Observe -> Analyze/Route -> Dispatch -> record evidence.
#
# This script is ONE-SHOT. Windows Task Scheduler invokes it on
# the existing heartbeat. It never creates another trigger.
# ============================================================

$started = Get-Date
$modePath = Join-Path $PSScriptRoot 'M_ACTING_EXECUTIVE_MODE.json'

function Write-SupervisorLog([string]$Message) {
  $line = "[{0}] {1}" -f (Get-Date).ToUniversalTime().ToString('o'), $Message
  Add-Content -Path $LogPath -Value $line -Encoding UTF8
  Write-Host $line
}

Write-SupervisorLog '=== M ACTING EXECUTIVE CYCLE START ==='

if (-not (Test-Path $RegistryPath)) {
  Write-SupervisorLog "REGISTRY_NOT_FOUND: $RegistryPath"
  exit 10
}

if (-not (Test-Path $DispatcherPath)) {
  Write-SupervisorLog "DISPATCHER_NOT_FOUND: $DispatcherPath"
  exit 11
}

if (-not (Test-Path $modePath)) {
  Write-SupervisorLog "M_MODE_POLICY_NOT_FOUND: $modePath"
  exit 12
}

# Prevent overlapping supervisor cycles when a previous cycle is still running.
$mutexName = 'Global\AERIS_M_ACTING_EXECUTIVE_CYCLE'
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$lockAcquired = $false

try {
  $lockAcquired = $mutex.WaitOne(0)
  if (-not $lockAcquired) {
    Write-SupervisorLog 'CYCLE_SKIPPED: PREVIOUS_M_CYCLE_STILL_RUNNING'
    exit 0
  }

  $mode = Get-Content -Raw -Path $modePath | ConvertFrom-Json
  if ($mode.mode -ne 'M_ACTING_EXECUTIVE' -or $mode.status -ne 'ACTIVE_PENDING_RUNTIME_VERIFICATION') {
    Write-SupervisorLog 'M_MODE_GATE_REJECTED'
    exit 13
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
  Write-SupervisorLog 'OPERATOR: M_ACTING_EXECUTIVE'
  Write-SupervisorLog 'MASTER_BRAIN: AX_INTELLIGENCE_ONLY_UNTIL_IDENTITY_VERIFIED'
  Write-SupervisorLog "OBSERVE: TASK=$($selected.id) STATE=$($selected.state) PRIORITY=$($selected.priority)"
  Write-SupervisorLog "DECISION: ACTION=$($selected.next_action)"

  # The existing dispatcher remains the canonical execution path.
  # M owns invocation/supervision; dispatcher owns runtime gates and routing.
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DispatcherPath -RegistryPath $RegistryPath
  $exitCode = $LASTEXITCODE

  if ($exitCode -eq 0) {
    Write-SupervisorLog 'DISPATCH: CYCLE_RETURNED_SUCCESS'
  }
  else {
    Write-SupervisorLog "DISPATCH: CYCLE_RETURNED_EXITCODE=$exitCode"
  }

  Write-SupervisorLog "CYCLE_DURATION_SECONDS=$([math]::Round(((Get-Date)-$started).TotalSeconds,2))"
  Write-SupervisorLog '=== M ACTING EXECUTIVE CYCLE END ==='
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
