param(
  [string]$NodeId = 'PC1-MAIN',
  [string]$Specialist = 'pc1-specialist.mjs',
  [string]$ControlSpecialist = 'pc1-specialist-control.mjs'
)
$ErrorActionPreference = 'Stop'
$RuntimeDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Main = Join-Path $RuntimeDir 'main.mjs'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js is required.' }
if (-not (Test-Path $Main)) { throw "AX Runtime entrypoint not found: $Main" }
$env:AX_EXECUTOR_NODE_ID = $NodeId
$env:AX_PC1_NODE_ID = $NodeId
$env:AX_SPECIALIST_EXECUTOR = $Specialist
$env:AX_CONTROL_SPECIALIST_EXECUTOR = $ControlSpecialist
$env:AX_PC1_EXECUTOR_COMMAND = if ($env:AX_PC1_EXECUTOR_COMMAND) { $env:AX_PC1_EXECUTOR_COMMAND } else { (Get-Command node).Source }
$env:AX_RUNTIME_INTERVAL_MS = if ($env:AX_RUNTIME_INTERVAL_MS) { $env:AX_RUNTIME_INTERVAL_MS } else { '5000' }
$env:AX_CANONICAL_SYNC_INTERVAL_MS = if ($env:AX_CANONICAL_SYNC_INTERVAL_MS) { $env:AX_CANONICAL_SYNC_INTERVAL_MS } else { '15000' }
Write-Output "[AX_BOOT] node=$NodeId specialist=$Specialist"
Write-Output '[AX_BOOT] runtime=continuous'
node $Main