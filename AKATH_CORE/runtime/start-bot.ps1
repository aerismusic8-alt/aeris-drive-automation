$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')

$env:AX_PC1_NODE_ID = if ($env:AX_PC1_NODE_ID) { $env:AX_PC1_NODE_ID } else { 'PC2-MAIN' }
$env:AX_RUNTIME_INTERVAL_MS = if ($env:AX_RUNTIME_INTERVAL_MS) { $env:AX_RUNTIME_INTERVAL_MS } else { '5000' }
$env:AX_CANONICAL_SYNC_INTERVAL_MS = if ($env:AX_CANONICAL_SYNC_INTERVAL_MS) { $env:AX_CANONICAL_SYNC_INTERVAL_MS } else { '15000' }

Write-Host "[AX_BOOT] node=$env:AX_PC1_NODE_ID"
Write-Host "[AX_BOOT] runtime=continuous; stop only by explicit operator shutdown"
node '.\AKATH_CORE\runtime\main.mjs'
