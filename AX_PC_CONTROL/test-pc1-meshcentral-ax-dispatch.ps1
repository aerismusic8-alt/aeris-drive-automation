param([string]$JobId='AX-MESH-PROOF-001')
$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot 'pc1-meshcentral-ax-dispatch.ps1'
if(-not (Test-Path $script)){throw 'ADAPTER_SCRIPT_MISSING'}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Action Health
if($LASTEXITCODE -ne 0){throw 'MESH_HEALTH_FAILED'}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Action DispatchIntent -Intent NODE_HEALTH_CHECK -JobId $JobId
if($LASTEXITCODE -ne 0){throw 'MESH_INTENT_DISPATCH_FAILED'}
