param(
  [string]$RegistryPath = "$PSScriptRoot\AX_TRIGGER_REGISTRY.json",
  [string]$TriggerId = '',
  [string]$Source = 'unknown',
  [string]$Event = 'heartbeat',
  [string]$Status = 'ACTIVE',
  [string]$Result = ''
)
$ErrorActionPreference='Stop'
$now=(Get-Date).ToUniversalTime().ToString('o')
$items=@()
if(Test-Path $RegistryPath){
  try{$x=Get-Content -Raw $RegistryPath|ConvertFrom-Json;if($x.triggers){$items=@($x.triggers)}}catch{$items=@()}
}
if([string]::IsNullOrWhiteSpace($TriggerId)){ $TriggerId = "TRG-$([guid]::NewGuid().ToString('N').Substring(0,12))" }
$found=$false
$items=@($items|ForEach-Object{
  if($_.triggerId -eq $TriggerId){$found=$true;[pscustomobject]@{triggerId=$TriggerId;source=$Source;lastSeen=$now;lastEvent=$Event;status=$Status;executionCount=([int]$_.executionCount)+1;successCount=([int]$_.successCount)+$(if($Status -eq 'ACTIVE'){1}else{0});failureCount=([int]$_.failureCount)+$(if($Status -eq 'FAILED'){1}else{0});lastResult=$Result}}
  else{$_}
})
if(-not $found){$items+= [pscustomobject]@{triggerId=$TriggerId;source=$Source;lastSeen=$now;lastEvent=$Event;status=$Status;executionCount=1;successCount=$(if($Status -eq 'ACTIVE'){1}else{0});failureCount=$(if($Status -eq 'FAILED'){1}else{0});lastResult=$Result}}
$doc=[ordered]@{schema='AX_TRIGGER_REGISTRY_V1';updatedAt=$now;heartbeatTimeoutSeconds=120;triggerCount=@($items).Count;triggers=@($items)}
$doc|ConvertTo-Json -Depth 10|Set-Content $RegistryPath -Encoding UTF8
$verify=Get-Content -Raw $RegistryPath|ConvertFrom-Json
if($verify.schema -ne 'AX_TRIGGER_REGISTRY_V1'){throw 'AX_TRIGGER_REGISTRY_VERIFY_FAILED'}
if([int]$verify.triggerCount -ne @($items).Count){throw 'AX_TRIGGER_REGISTRY_COUNT_VERIFY_FAILED'}
Write-Host "TRIGGER_REGISTRY VERIFIED count=$($verify.triggerCount) trigger=$TriggerId status=$Status"
