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
# service, so look for .runner files directly as well. The service name carries
# one target; the machine may hold a second, correctly configured runner that
# simply is not the one running.
Write-Host ''
Write-Host 'STEP=OTHER_FOLDERS'
$found = @()

# Named locations first: fast and covers the usual install paths.
$roots = @(
  'C:\actions-runner', 'C:\ax-runner', 'C:\runner', 'C:\AX-Runtime',
  (Join-Path $env:USERPROFILE 'actions-runner'),
  (Join-Path $env:USERPROFILE 'runner')
)
foreach ($r in $roots) {
  if (-not (Test-Path -LiteralPath $r)) { continue }
  if (Test-Path -LiteralPath (Join-Path $r '.runner')) { $found += (Join-Path $r '.runner') }
  try {
    $dirs = @(Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like '*runner*' })
  } catch { $dirs = @() }
  foreach ($d in $dirs) {
    $f = Join-Path $d.FullName '.runner'
    if (Test-Path -LiteralPath $f) { $found += $f }
  }
}

# Then a bounded sweep, because the folder name is not predictable. Depth is
# capped so this stays fast on a machine with a lot of files.
try {
  $deep = @(Get-ChildItem -LiteralPath 'C:\' -Filter '.runner' -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue)
  foreach ($f in $deep) { $found += $f.FullName }
} catch { }

$found = @($found | Select-Object -Unique)
if ($found.Count -eq 0) {
  Write-Host 'NO_RUNNER_FOLDERS_FOUND'
} else {
  foreach ($f in $found) {
    try {
      $cfg = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
      Write-Host "FOUND=$f"
      Write-Host "  GITHUB_URL=$($cfg.gitHubUrl)"
      Write-Host "  AGENT_NAME=$($cfg.agentName) POOL=$($cfg.poolName)"
      # Whether this folder's runner is the one the service starts.
      $isService = $false
      foreach ($svc in $services) {
        if ($svc.PathName -and $f.StartsWith((Split-Path (Split-Path $svc.PathName -Parent) -Parent))) { $isService = $true }
      }
      Write-Host "  RUNS_AS_SERVICE=$isService"
      Write-Host "  START_CMD=$((Join-Path (Split-Path $f -Parent) 'run.cmd'))"
    } catch {
      Write-Host "FOUND_UNREADABLE=$f"
    }
  }
}

# --- MCP server state -----------------------------------------------------
Write-Host ''
Write-Host 'STEP=MCP'
$port = 8090
$taskName = 'AERIS-PC1-WINREMOTE-MCP'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
  $ti = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
  Write-Host "MCP_TASK=$($task.TaskName) STATE=$($task.State)"
  if ($ti) { Write-Host "MCP_LAST_RESULT=$($ti.LastTaskResult) LAST_RUN=$($ti.LastRunTime)" }
  Write-Host "MCP_TASK_USER=$($task.Principal.UserId) LOGON=$($task.Principal.LogonType)"
} else {
  Write-Host 'MCP_TASK_ABSENT'
}

$listen = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
Write-Host "MCP_PORT_LISTENING=$($listen.Count -gt 0)"
if ($listen) { Write-Host "MCP_PORT_PID=$($listen[0].OwningProcess)" }

$healthy = $false
try {
  $r = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 5
  if ($r.status -eq 'ok') { $healthy = $true; Write-Host "MCP_HEALTH=ok VERSION=$($r.version)" }
} catch { Write-Host "MCP_HEALTH_ERROR=$($_.Exception.Message)" }
if (-not $healthy) { Write-Host 'MCP_HEALTH=not-ok' }

$log = 'C:\AX-Runtime\winremote\winremote-mcp.log'
if (Test-Path -LiteralPath $log) {
  Write-Host '--- MCP log tail ---'
  Get-Content -LiteralPath $log -Tail 30 | ForEach-Object { Write-Host "  $_" }
  Write-Host '--- end ---'
} else {
  Write-Host "MCP_LOG_MISSING=$log"
}

# --- Optional repair ------------------------------------------------------
if ($Restart) {
  Write-Host ''
  Write-Host 'STEP=RESTART'

  # If a folder on this machine is configured for the target repository but is
  # not the runner the service starts, start it. This is the common shape of the
  # problem: the service points at the wrong repository while the right runner
  # sits on disk unused.
  $targetRepo = 'aerismusic8-alt/aeris-drive-automation'
  $started = $false
  foreach ($f in $found) {
    try {
      $cfg = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
    } catch { continue }
    if ($cfg.gitHubUrl -notlike "*$targetRepo*") { continue }

    $folder = Split-Path $f -Parent
    $isService = $false
    foreach ($svc in $services) {
      if ($svc.PathName -and $f.StartsWith((Split-Path (Split-Path $svc.PathName -Parent) -Parent))) { $isService = $true }
    }
    Write-Host "MATCHES_TARGET=$folder RUNS_AS_SERVICE=$isService"

    if ($isService) { continue }

    $runCmd = Join-Path $folder 'run.cmd'
    if (-not (Test-Path -LiteralPath $runCmd)) { Write-Host "RUN_CMD_MISSING=$runCmd"; continue }

    # Run it hidden in its own process. The runner dials out to GitHub, so no
    # inbound port is involved.
    Write-Host "STARTING_RUNNER=$runCmd"
    Start-Process -FilePath $runCmd -WorkingDirectory $folder -WindowStyle Hidden
    $started = $true
  }

  if (-not $started) {
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
      Write-Host 'NO_REPAIR_ACTION - no runner for the target repo found on disk'
    }
  }

  Start-Sleep -Seconds 10
  $after = @(Get-Process -Name 'Runner.Listener' -ErrorAction SilentlyContinue)
  Write-Host "LISTENER_COUNT_AFTER=$($after.Count)"
}

Write-Host ''
Write-Host '=========================================='
Write-Host ' DONE - send the lines above'
Write-Host '=========================================='
