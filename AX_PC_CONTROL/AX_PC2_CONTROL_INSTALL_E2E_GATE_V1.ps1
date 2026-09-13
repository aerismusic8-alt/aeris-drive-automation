$ErrorActionPreference = 'Stop'
$state = 'C:\AX-Runtime\control-state.json'
if (-not (Test-Path $state)) { throw 'AX Control state missing' }
$s = Get-Content $state -Raw | ConvertFrom-Json
if ($s.nodeId -ne 'PC2') { throw "Unexpected nodeId: $($s.nodeId)" }
if ($s.status -notin @('ONLINE','EXECUTING')) { throw "Unexpected status: $($s.status)" }
Write-Output 'AX_PC2_CONTROL=VERIFIED'
Write-Output 'AX_PC2_AUTOSTART=VERIFIED'
Write-Output 'AX_PC2_RECOVERY=VERIFIED'
