# Run the winremote MCP server in the foreground for a moment and show what it
# says.
#
# Why this exists: the scheduled task reported itself as running, the port was
# never bound, and the log file was empty. Rather than guess at the cause from
# the outside, this clears the stale process and starts the server where its
# output is visible on screen. An import error, a missing dependency or a bind
# failure all show up in seconds this way.
#
# Read-only apart from stopping the stuck process. Nothing is installed.
#
# Run as Administrator:
#   powershell -ExecutionPolicy Bypass -File pc1-mcp-foreground-test.ps1

param(
  [int]$Port = 8090,
  [int]$Seconds = 20
)

$ErrorActionPreference = 'Continue'

Write-Host '=========================================='
Write-Host ' AX PC1 MCP FOREGROUND TEST'
Write-Host '=========================================='

$taskName = 'AERIS-PC1-WINREMOTE-MCP'
Write-Host "TASK=$taskName"

# --- 1. Clear anything already holding the port ---------------------------
Write-Host ''
Write-Host 'STEP=CLEAR'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
  Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  Write-Host 'TASK_STOPPED'
  Start-Sleep -Seconds 2
}

$holders = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
if ($holders.Count -eq 0) {
  Write-Host 'PORT_FREE'
} else {
  foreach ($h in $holders) {
    Write-Host "PORT_HELD_BY=$($h.OwningProcess)"
    $p = Get-Process -Id $h.OwningProcess -ErrorAction SilentlyContinue
    if ($p) { Write-Host "  PROCESS=$($p.ProcessName)" }
    Stop-Process -Id $h.OwningProcess -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Seconds 2
  $still = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
  Write-Host "PORT_STILL_HELD=$($still.Count -gt 0)"
}

# --- 2. Find python -------------------------------------------------------
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) {
  foreach ($c in @('C:\Python314\python.exe', 'C:\Python313\python.exe', 'C:\Python312\python.exe')) {
    if (Test-Path -LiteralPath $c) { $python = $c; break }
  }
}
if (-not $python) { Write-Host 'PYTHON_NOT_FOUND'; exit 1 }
Write-Host "PYTHON=$python"

# --- 3. Import check ------------------------------------------------------
# This separates "the package is broken" from "the server cannot bind", which
# are different problems with different fixes.
Write-Host ''
Write-Host 'STEP=IMPORT_CHECK'
& $python -c "import winremote, sys; print('IMPORT_OK', winremote.__version__, sys.version.split()[0])"
Write-Host "IMPORT_EXIT=$LASTEXITCODE"

# --- 4. Run in the foreground --------------------------------------------
Write-Host ''
Write-Host "STEP=RUN_FOREGROUND (${Seconds}s, output appears below)"
Write-Host 'If it prints a startup banner, the server works and the problem is the'
Write-Host 'scheduled task. If it prints a traceback, that traceback is the answer.'
Write-Host ''

$log = Join-Path $env:TEMP 'mcp-foreground.log'
if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

# -u so nothing is buffered and every line lands in the file as it happens.
$proc = Start-Process -FilePath $python `
  -ArgumentList @('-u', '-m', 'winremote', '--transport', 'streamable-http',
                  '--host', '127.0.0.1', '--port', $Port) `
  -RedirectStandardOutput $log -RedirectStandardError "$log.err" `
  -NoNewWindow -PassThru

# Watch for the port coming up, and stop early when it does.
$up = $false
foreach ($i in 1..$Seconds) {
  Start-Sleep -Seconds 1
  if ($proc.HasExited) { break }
  $l = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
  if ($l.Count -gt 0) { $up = $true; break }
}

if ($up) {
  Write-Host "PORT_LISTENING=True after ~$i s"
  try {
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 5
    Write-Host "HEALTH=$($r.status) VERSION=$($r.version)"
  } catch { Write-Host "HEALTH_ERROR=$($_.Exception.Message)" }
} else {
  Write-Host 'PORT_LISTENING=False'
}

if ($proc.HasExited) {
  Write-Host "PROCESS_EXITED=True EXIT_CODE=$($proc.ExitCode)"
} else {
  Write-Host 'PROCESS_EXITED=False (still running - that means it started fine)'
  Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '--- stdout ---'
if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log } else { Write-Host '(empty)' }
Write-Host '--- stderr ---'
if (Test-Path -LiteralPath "$log.err") { Get-Content -LiteralPath "$log.err" } else { Write-Host '(empty)' }

Write-Host ''
Write-Host '=========================================='
Write-Host ' DONE - send everything above'
Write-Host '=========================================='
