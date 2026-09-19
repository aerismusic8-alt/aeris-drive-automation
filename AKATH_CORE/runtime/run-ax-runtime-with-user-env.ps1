$ErrorActionPreference = 'Stop'
$RuntimeDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Main = Join-Path $RuntimeDir 'main.mjs'

if (-not (Test-Path $Main)) {
  throw "AX Runtime entrypoint not found: $Main"
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw 'Node.js is required on PC1.'
}

$geminiKey = [Environment]::GetEnvironmentVariable('GEMINI_API_KEY', 'User')
if ([string]::IsNullOrWhiteSpace($geminiKey)) {
  $geminiKey = (Get-ItemProperty -Path 'HKCU:\Environment' -Name 'GEMINI_API_KEY' -ErrorAction SilentlyContinue).GEMINI_API_KEY
}
if (-not [string]::IsNullOrWhiteSpace($geminiKey)) {
  $env:GEMINI_API_KEY = $geminiKey
}

$nodeId = [Environment]::GetEnvironmentVariable('AX_PC1_NODE_ID', 'User')
if ([string]::IsNullOrWhiteSpace($nodeId)) { $nodeId = 'PC1-MAIN' }
$env:AX_PC1_NODE_ID = $nodeId

$runtimeInterval = [Environment]::GetEnvironmentVariable('AX_RUNTIME_INTERVAL_MS', 'User')
if ([string]::IsNullOrWhiteSpace($runtimeInterval)) { $runtimeInterval = '5000' }
$env:AX_RUNTIME_INTERVAL_MS = $runtimeInterval

$syncInterval = [Environment]::GetEnvironmentVariable('AX_CANONICAL_SYNC_INTERVAL_MS', 'User')
if ([string]::IsNullOrWhiteSpace($syncInterval)) { $syncInterval = '15000' }
$env:AX_CANONICAL_SYNC_INTERVAL_MS = $syncInterval
$env:AX_RUNTIME_LIVE_CONSOLE = 'true'

$logDir = 'C:\AX-Runtime'
$logPath = Join-Path $logDir 'AX-Runtime.log'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Add-Content -Path $logPath -Value "`n=== AX_RUNTIME START $(Get-Date -Format o) node=$nodeId pid=$PID ==="

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& (Get-Command node).Source $Main 2>&1 | Tee-Object -FilePath $logPath -Append
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
Add-Content -Path $logPath -Value "=== AX_RUNTIME EXIT $(Get-Date -Format o) code=$exitCode ==="
exit $exitCode
