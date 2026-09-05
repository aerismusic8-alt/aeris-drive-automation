param(
  [string]$RegistryPath = "$PSScriptRoot\AX_TASK_REGISTRY.json",
  [string]$DispatcherPath = "$PSScriptRoot\AX_ACTION_DISPATCHER.ps1",
  [string]$LogPath = "$PSScriptRoot\AX_SUPERVISOR.log"
)

$ErrorActionPreference = 'Stop'

# ============================================================
# RETIRED M ACTING EXECUTIVE SUPERVISOR
# This compatibility shim exists only long enough for the
# existing Windows Task Scheduler entry to unregister itself.
# AX is now the operational owner. M must not dispatch work.
# ============================================================

$started = Get-Date
$modePath = Join-Path $PSScriptRoot 'M_ACTING_EXECUTIVE_MODE.json'

function Write-SupervisorLog([string]$Message) {
  $line = "[{0}] {1}" -f (Get-Date).ToUniversalTime().ToString('o'), $Message
  Add-Content -Path $LogPath -Value $line -Encoding UTF8
  Write-Host $line
}

if (-not (Test-Path $modePath)) {
  Write-SupervisorLog "M_MODE_POLICY_NOT_FOUND: $modePath"
  exit 12
}

$mode = Get-Content -Raw -Path $modePath | ConvertFrom-Json
if ($mode.status -eq 'RETIRED_PENDING_CLEANUP') {
  Write-SupervisorLog 'M_ACTING_EXECUTIVE_RETIREMENT_START'
  Write-SupervisorLog 'AX_OPERATIONAL_OWNERSHIP=ACTIVE'
  Write-SupervisorLog 'M_DISPATCH=DISABLED'

  $taskName = 'AERIS AX Supervisor Trigger'
  try {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
      Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
      Write-SupervisorLog "SCHEDULER_TASK_UNREGISTERED: $taskName"
    } else {
      Write-SupervisorLog "SCHEDULER_TASK_ALREADY_ABSENT: $taskName"
    }
  } catch {
    Write-SupervisorLog "SCHEDULER_RETIREMENT_FAILED: $($_.Exception.Message)"
    exit 21
  }

  # Persist a local proof that the old scheduler entry was removed.
  $proofPath = Join-Path $PSScriptRoot 'M_RETIREMENT_PROOF.json'
  $proof = [ordered]@{
    schema = 'M_RETIREMENT_PROOF_V1'
    status = 'VERIFIED'
    retired_at_utc = [DateTime]::UtcNow.ToString('o')
    scheduler_task = $taskName
    scheduler_task_present_after_unregister = [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
    operational_owner = 'AX'
    m_dispatch_enabled = $false
  }
  $proof | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $proofPath
  if ($proof.scheduler_task_present_after_unregister) {
    throw 'M_RETIREMENT_PROOF_TASK_STILL_PRESENT'
  }
  Write-SupervisorLog 'M_ACTING_EXECUTIVE_RETIREMENT_VERIFIED'
  exit 0
}

# Safety: any unexpected legacy mode is refused rather than dispatching.
Write-SupervisorLog "M_MODE_GATE_REJECTED: status=$($mode.status)"
Write-SupervisorLog 'M_DISPATCH=DISABLED'
exit 13
