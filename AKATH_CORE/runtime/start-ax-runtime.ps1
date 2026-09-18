param(
  [switch]$Live
)

$ErrorActionPreference = 'Stop'
$RuntimeDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Main = Join-Path $RuntimeDir 'main.mjs'
$Specialist = Join-Path $RuntimeDir 'pc1-specialist.mjs'
$TaskName = 'AERIS-AKATH-AX-RUNTIME'
$Log = Join-Path $RuntimeDir 'ax-watchdog.log'

function Write-WatchdogLog([string]$Message) {
  $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
  Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
  Write-Output $line
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js is required on PC1.' }

$env:AX_PC1_NODE_ID = if ($env:AX_PC1_NODE_ID) { $env:AX_PC1_NODE_ID } else { 'PC1-MAIN' }
$env:AX_RUNTIME_INTERVAL_MS = if ($env:AX_RUNTIME_INTERVAL_MS) { $env:AX_RUNTIME_INTERVAL_MS } else { '5000' }
$env:AX_RUNTIME_LIVE_CONSOLE = if ($Live) { 'true' } else { 'false' }

# Remove the 72-hour Task Scheduler execution ceiling so this watchdog can remain alive.
# This is best-effort: the watchdog still provides process-level self-restart if the runtime exits.
try {
  $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
  Set-ScheduledTask -TaskName $TaskName -Settings $settings -ErrorAction Stop | Out-Null
  Write-WatchdogLog "TASK_SETTINGS execution_limit=UNLIMITED task=$TaskName"
} catch {
  Write-WatchdogLog "TASK_SETTINGS_UPDATE_FAILED $($_.Exception.Message)"
}

Write-WatchdogLog "WATCHDOG_ONLINE node=$env:AX_PC1_NODE_ID"

while ($true) {
  try {
    $existing = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue | Where-Object {
      $_.CommandLine -and $_.CommandLine -like "*$Main*"
    }

    if ($existing) {
      $ids = @($existing | ForEach-Object { [int]$_.ProcessId })
      if ($ids.Count -gt 1) {
        Write-WatchdogLog "DUPLICATE_RUNTIME detected_pids=$($ids -join ',') keeping=$($ids[0])"
        Start-Sleep -Seconds 5
        continue
      }

      $pid = $ids[0]
      Write-WatchdogLog "RUNTIME_ALREADY_ONLINE pid=$pid"
      try {
        Wait-Process -Id $pid -ErrorAction Stop
      } catch {
        # Process may have exited between discovery and Wait-Process.
      }
      Write-WatchdogLog "RUNTIME_EXITED pid=$pid action=RESTART"
      Start-Sleep -Seconds 3
      continue
    }

    Write-WatchdogLog "RUNTIME_MISSING action=START"
    $p = Start-Process -FilePath 'node' -ArgumentList ('"' + $Main + '"') -WorkingDirectory $RuntimeDir -WindowStyle Hidden -PassThru
    Write-WatchdogLog "RUNTIME_STARTED pid=$($p.Id)"

    try {
      Wait-Process -Id $p.Id -ErrorAction Stop
    } catch {
      # Normal path when the child exits.
    }

    Write-WatchdogLog "RUNTIME_EXITED pid=$($p.Id) action=RESTART"
    Start-Sleep -Seconds 3
  } catch {
    Write-WatchdogLog "WATCHDOG_ERROR $($_.Exception.Message) action=RETRY"
    Start-Sleep -Seconds 10
  }
}
