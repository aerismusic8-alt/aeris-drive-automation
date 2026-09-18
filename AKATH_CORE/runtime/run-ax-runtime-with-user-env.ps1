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
if ([string]::IsNullOrWhiteSpace($geminiKey)) {
  throw 'GEMINI_API_KEY is not set in the Windows User environment.'
}

$env:GEMINI_API_KEY = $geminiKey

$nodeId = [Environment]::GetEnvironmentVariable('AX_PC1_NODE_ID', 'User')
if ([string]::IsNullOrWhiteSpace($nodeId)) { $nodeId = 'PC1-MAIN' }
$env:AX_PC1_NODE_ID = $nodeId

$runtimeInterval = [Environment]::GetEnvironmentVariable('AX_RUNTIME_INTERVAL_MS', 'User')
if ([string]::IsNullOrWhiteSpace($runtimeInterval)) { $runtimeInterval = '5000' }
$env:AX_RUNTIME_INTERVAL_MS = $runtimeInterval

$syncInterval = [Environment]::GetEnvironmentVariable('AX_CANONICAL_SYNC_INTERVAL_MS', 'User')
if ([string]::IsNullOrWhiteSpace($syncInterval)) { $syncInterval = '15000' }
$env:AX_CANONICAL_SYNC_INTERVAL_MS = $syncInterval

& (Get-Command node).Source $Main
exit $LASTEXITCODE
