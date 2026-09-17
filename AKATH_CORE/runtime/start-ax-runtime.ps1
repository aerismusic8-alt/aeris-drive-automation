$ErrorActionPreference = 'Stop'
$RuntimeDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Main = Join-Path $RuntimeDir 'main.mjs'
$Specialist = Join-Path $RuntimeDir 'pc1-specialist.mjs'

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw 'Node.js is required on PC1.' }

$env:AX_PC1_NODE_ID = if ($env:AX_PC1_NODE_ID) { $env:AX_PC1_NODE_ID } else { 'PC1-MAIN' }
$env:AX_PC1_EXECUTOR_COMMAND = if ($env:AX_PC1_EXECUTOR_COMMAND) { $env:AX_PC1_EXECUTOR_COMMAND } else { $node.Source }
$env:AX_RUNTIME_INTERVAL_MS = if ($env:AX_RUNTIME_INTERVAL_MS) { $env:AX_RUNTIME_INTERVAL_MS } else { '5000' }

Start-Process -FilePath 'node' -ArgumentList ('"' + $Main + '"') -WorkingDirectory $RuntimeDir -WindowStyle Hidden
Write-Output "AX Runtime started detached on $env:AX_PC1_NODE_ID"
Write-Output "AX PC1 executor command bound: $env:AX_PC1_EXECUTOR_COMMAND"
Write-Output "AX PC1 Specialist bound: $Specialist"
