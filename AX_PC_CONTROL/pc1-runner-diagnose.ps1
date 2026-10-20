# PC1: report every GitHub Actions runner on this machine and which repository
# each one actually serves.
#
# Why this exists: the runner service reported itself as Running, yet every job
# for this repository sat in the queue. "Running" only means the service is up.
# A runner is configured for exactly one repository at registration time, and
# its name encodes that choice:
#
#   actions.runner.<owner>-<repo>.<runner-name>
#
# so a service named for another repository looks perfectly healthy while being
# useless to us. The service name is the only place that target is visible, and
# the same value is stored in the runner folder's .runner file. This script
# reads both and prints them, so the mismatch is visible instead of inferred.
#
# Read-only by default. -Restart also restarts any service whose listener
# process is missing.
#
# Run: powershell -ExecutionPolicy Bypass -File pc1-runner-diagnose.ps1

param(
  [switch]$Restart
)

$ErrorActionPreference = 'Continue'

Write-Host '=========================================='
Write-Host ' AX PC1 RUNNER DIAGNOSE'
Write-Host '=========================================='
Write-Host "COMPUTER=$env:COMPUTERNAME"

# --- Services -------------------------------------------------------------
Write-Host ''
Write-Host 'STEP=SERVICES'
$services = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like 'actions.runner.*' -or $_.Name -like 'actions.*' -or
                 $_.DisplayName -like '*GitHub Actions*' -or $_.DisplayName -like '*Actions Runner*' })

if ($services.Count -eq 0) {
  Write-Host 'NO_RUNNER_SERVICE - nothing on this machine is registered as a runner service'
} else {
  foreach ($svc in $services) {
    Write-Host "SERVICE=$($svc.Name)"
    Write-Host "  STATE=$($svc.State) STARTMODE=$($svc.StartMode)"
    Write-Host "  PATH=$($svc.PathName)"

    # The service name carries the target repository: actions.runner.<owner>-<repo>.<name>
    if ($svc.Name -match '^actions\.runner\.(.+)\.([^.]+)$') {
      $target = $matches[1]
      $runnerName = $matches[2]
      Write-Host "  TARGET_FROM_NAME=$target RUNNER_NAME=$runnerName"
    }

    # The runner folder keeps the same facts in .runner, which is authoritative.
    $exe = $null
    if ($svc.PathName -match '"([^"]+)"') { $exe = $matches[1] }
    elseif ($svc.PathName) { $exe = ($svc.PathName -split ' ')[0] }

    if ($exe) {
      # <root>\bin\RunnerService.exe -> the .runner file sits at <root>\.runner
      $root = Split-Path (Split-Path $exe -Parent) -Parent
      $runnerFile = Join-Path $root '.runner'
      if (Test-Path -LiteralPath $runnerFile) {
        try {
          $cfg = Get-Content -LiteralPath $runnerFile -Raw | ConvertFrom-Json
          Write-Host "  RUNNER_FOLDER=$root"
          Write-Host "  GITHUB_URL=$($cfg.gitHubUrl)"
          Write-Host "  AGENT_NAME=$($cfg.agentName)"
          Write-Host "  POOL=$($cfg.poolName)"
        } catch {
          Write-Host "  RUNNER_FILE_UNREADABLE=$runnerFile"
        }
      } else {
        Write-Host "  RUNNER_FILE_MISSING=$runnerFile"
      }
    }
  }
}

# --- Listener processes ---------------------------------------------------
Write-Host ''
Write-Host 'STEP=LISTENER'
$listeners = @(Get-Process -Name 'Runner.Listener' -ErrorAction SilentlyContinue)
$workers = @(Get-Process -Name 'Runner.Worker' -ErrorAction SilentlyContinue)
Write-Host "LISTENER_COUNT=$($listeners.Count) WORKER_COUNT=$($workers.Count)"
foreach ($p in $listeners) { Write-Host "  LISTENER PID=$($p.Id)" }

# --- Other runner folders on disk ----------------------------------------
# A runner can be installed and configured without being registered as a
# service, so look for .runner files directly as well.
Write-Host ''
Write-Host 'STEP=OTHER_FOLDERS'
$roots = @(
  'C:\actions-runner', 'C:\ax-runner', 'C:\AX-Runtime',
  (Join-Path $env:USERPROFILE 'actions-runner'),
  (Join-Path $env:USERPROFILE 'runner'),
  'C:\'
)
$found = @()
foreach ($r in $roots) {
  if (-not (Test-Path -LiteralPath $r)) { continue }
  $dirs = @()
  try {
    $dirs = @(Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like '*runner*' })
  } catch { }
  foreach ($d in $dirs) {
    $f = Join-Path $d.FullName '.runner'
    if (Test-Path -LiteralPath $f) { $found += $f }
  }
}

if ($found.Count -eq 0) {
  Write-Host 'NO_OTHER_RUNNER_FOLDERS'
} else {
  foreach ($f in ($found | Select-Object -Unique)) {
    try {
      $cfg = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
      Write-Host "FOUND=$f"
      Write-Host "  GITHUB_URL=$($cfg.gitHubUrl) AGENT_NAME=$($cfg.agentName)"
    } catch {
      Write-Host "FOUND_UNREADABLE=$f"
    }
  }
}

# --- Optional repair ------------------------------------------------------
if ($Restart) {
  Write-Host ''
  Write-Host 'STEP=RESTART'
  if ($listeners.Count -eq 0 -and $services.Count -gt 0) {
    foreach ($svc in $services) {
      try {
        Restart-Service -Name $svc.Name -ErrorAction Stop
        Write-Host "RESTARTED=$($svc.Name)"
      } catch {
        Write-Host "RESTART_FAILED=$($svc.Name) ERROR=$($_.Exception.Message)"
      }
    }
  } else {
    Write-Host 'RESTART_SKIPPED - a listener is already running'
  }
}

Write-Host ''
Write-Host '=========================================='
Write-Host ' DONE - send the lines above'
Write-Host '=========================================='
