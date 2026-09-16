$ErrorActionPreference = 'Stop'
$RuntimeDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Main = Join-Path $RuntimeDir 'main.mjs'

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js is required on PC1.' }
if ([string]::IsNullOrWhiteSpace($env:AX_PC1_EXECUTOR_COMMAND)) { throw 'AX_PC1_EXECUTOR_COMMAND is required. Bind it to the existing PC1 Specialist/executor command; do not invent a URL.' }

$env:AX_PC1_NODE_ID = if ($env:AX_PC1_NODE_ID) { $env:AX_PC1_NODE_ID } else { 'PC1-MAIN' }
$env:AX_RUNTIME_INTERVAL_MS = if ($env:AX_RUNTIME_INTERVAL_MS) { $env:AX_RUNTIME_INTERVAL_MS } else { '5000' }

Start-Process -FilePath 'node' -ArgumentList ('"' + $Main + '"') -WorkingDirectory $RuntimeDir -WindowStyle Hidden
Write-Output "AX Runtime started detached on $env:AX_PC1_NODE_ID"
