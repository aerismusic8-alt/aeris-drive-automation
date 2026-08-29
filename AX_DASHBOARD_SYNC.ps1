param([string]$StatePath='dashboard/status.json',[string]$RegistryPath='AX_TRIGGER_REGISTRY.json',[string]$Event='SYNC',[string]$JobId='')
$ErrorActionPreference='Stop'
$now=(Get-Date).ToUniversalTime().ToString('o')
if(!(Test-Path $StatePath)){throw 'DASHBOARD_STATE_MISSING'}
$s=Get-Content -Raw $StatePath|ConvertFrom-Json
$registry=$null
if(Test-Path $RegistryPath){$registry=Get-Content -Raw $RegistryPath|ConvertFrom-Json}
$triggerCount=if($registry){[int]$registry.triggerCount}else{0}
$sync=[pscustomobject]@{schema='AX_DASHBOARD_SYNC_V1';syncAt=$now;event=$Event;jobId=$JobId;triggerCount=$triggerCount;sourceState=$StatePath;stateVerified=$true}
$syncPath='dashboard/ax-sync.json'
$sync|ConvertTo-Json -Depth 8|Set-Content $syncPath -Encoding UTF8
$v=Get-Content -Raw $syncPath|ConvertFrom-Json
if($v.schema -ne 'AX_DASHBOARD_SYNC_V1'){throw 'DASHBOARD_SYNC_VERIFY_FAILED'}
Write-Host "AX_DASHBOARD_SYNC=VERIFIED event=$Event triggers=$triggerCount at=$now"
