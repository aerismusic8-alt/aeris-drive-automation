param([string]$Path='AX_ACTIVE_EXECUTIONS.json',[string]$TriggerId='',[string]$JobId='',[string]$Status='ACTIVE',[string]$Runner='',[string]$Result='')
$ErrorActionPreference='Stop'
$now=(Get-Date).ToUniversalTime().ToString('o')
$items=@()
if(Test-Path $Path){try{$d=Get-Content -Raw $Path|ConvertFrom-Json;if($d.executions){$items=@($d.executions)}}catch{$items=@()}}
if($TriggerId){$items=@($items|Where-Object{$_.triggerId -ne $TriggerId})
 $items += [pscustomobject]@{triggerId=$TriggerId;jobId=$JobId;status=$Status;runner=$Runner;lastSeen=$now;result=$Result}}
$cut=(Get-Date).ToUniversalTime().AddMinutes(-10)
$items=@($items|ForEach-Object{ $ls=[datetime]$_.lastSeen; if($ls -gt $cut){$_} else {[pscustomobject]@{triggerId=$_.triggerId;jobId=$_.jobId;status='STALE';runner=$_.runner;lastSeen=$_.lastSeen;result=$_.result}}})
$doc=[ordered]@{schema='AX_ACTIVE_EXECUTIONS_V1';updatedAt=$now;activeCount=@($items|Where-Object{$_.status -eq 'ACTIVE'}).Count;staleCount=@($items|Where-Object{$_.status -eq 'STALE'}).Count;executions=@($items)}
$doc|ConvertTo-Json -Depth 10|Set-Content $Path -Encoding UTF8
$v=Get-Content -Raw $Path|ConvertFrom-Json
if($v.schema -ne 'AX_ACTIVE_EXECUTIONS_V1'){throw 'ACTIVE_EXECUTIONS_VERIFY_FAILED'}
Write-Host "AX_ACTIVE_EXECUTIONS=VERIFIED active=$($v.activeCount) stale=$($v.staleCount)"
