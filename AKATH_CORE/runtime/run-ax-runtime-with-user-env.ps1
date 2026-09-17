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
  throw 'GEMINI_API_KEY is not set in the Windows User environment.'
}

$env:GEMINI_API_KEY = $geminiKey
$env:AX_PC1_NODE_ID = [Environment]::GetEnvironmentVariable('AX_PC1_NODE_ID', 'User') ?? 'PC1-MAIN'
$env:AX_RUNTIME_INTERVAL_MS = [Environment]::GetEnvironmentVariable('AX_RUNTIME_INTERVAL_MS', 'User') ?? '5000'
$env:AX_CANONICAL_SYNC_INTERVAL_MS = [Environment]::GetEnvironmentVariable('AX_CANONICAL_SYNC_INTERVAL_MS', 'User') ?? '15000'

& (Get-Command node).Source $Main
exit $LASTEXITCODE
