$ErrorActionPreference = 'Stop'
$RuntimeDir = $PSScriptRoot
$RepoRoot = Split-Path -Parent (Split-Path -Parent $RuntimeDir)
$Main = Join-Path $RuntimeDir 'main.mjs'
$State = Join-Path $RuntimeDir 'runtime-state.json'
$Evidence = Join-Path $RuntimeDir 'evidence.jsonl'

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw 'PC2_NODE_JS_NOT_FOUND' }

$env:AX_PC1_NODE_ID = 'PC2-MAIN'
$env:AX_PC1_EXECUTOR_COMMAND = $node.Source
$env:AX_RUNTIME_INTERVAL_MS = if ($env:AX_RUNTIME_INTERVAL_MS) { $env:AX_RUNTIME_INTERVAL_MS } else { '5000' }
$env:AX_CANONICAL_SYNC_INTERVAL_MS = if ($env:AX_CANONICAL_SYNC_INTERVAL_MS) { $env:AX_CANONICAL_SYNC_INTERVAL_MS } else { '15000' }

$existing = Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -like '*AKATH_CORE\runtime\main.mjs*' }
foreach ($process in $existing) {
  if ($process.ProcessId -ne $PID) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Host "[PC2_BOOT] stale AX runtime stopped pid=$($process.ProcessId)"
  }
}

$before = if (Test-Path $State) { (Get-Content $State -Raw | ConvertFrom-Json).lastVerifiedJob } else { $null }
Write-Host "[PC2_BOOT] node=$env:AX_PC1_NODE_ID"
Write-Host "[PC2_BOOT] executor=$env:AX_PC1_EXECUTOR_COMMAND"
Write-Host '[PC2_BOOT] starting continuous runtime'

Start-Process -FilePath $node.Source -ArgumentList ('"' + $Main + '"') -WorkingDirectory $RuntimeDir -WindowStyle Hidden | Out-Null

$deadline = (Get-Date).AddSeconds(90)
$verified = $false
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 3
  if (-not (Test-Path $State)) { continue }
  $state = Get-Content $State -Raw | ConvertFrom-Json
  if ($state.nodeId -ne 'PC2-MAIN') { throw "PC2_NODE_ID_MISMATCH:$($state.nodeId)" }
  if ($state.runtimeStatus -ne 'ONLINE') { continue }
  if ([string]::IsNullOrWhiteSpace($state.lastVerifiedJob)) { continue }
  if ($state.lastVerifiedJob -eq $before) { continue }
  $verified = $true
  Write-Host "[PC2_BOOT] FIRST_BOT_JOB_VERIFIED=$($state.lastVerifiedJob)"
  Write-Host "[PC2_BOOT] RUNTIME_STATUS=$($state.runtimeStatus)"
  Write-Host "[PC2_BOOT] NODE_ID=$($state.nodeId)"
  break
}

if (-not $verified) {
  $stateText = if (Test-Path $State) { Get-Content $State -Raw } else { 'STATE_FILE_MISSING' }
  throw "PC2_FIRST_BOT_JOB_NOT_VERIFIED after 90s: $stateText"
}

if (Test-Path $Evidence) {
  Get-Content $Evidence -Tail 3 | ForEach-Object { Write-Host "[PC2_EVIDENCE] $_" }
}

Write-Host '[PC2_BOOT] CONTINUOUS_RUNTIME=ONLINE'
Write-Host '[PC2_BOOT] FIRST_BOT_JOB=VERIFIED'
