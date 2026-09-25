param([string]$RuntimeRoot='C:\AX-Runtime',[int]$PollSeconds=2)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$intent=Join-Path $RuntimeRoot 'brain1-intent-queue';$control=Join-Path $RuntimeRoot 'brain1-command-queue';$ev=Join-Path $RuntimeRoot 'evidence'
foreach($r in @($intent,$control,$ev)){New-Item -ItemType Directory -Path $r -Force|Out-Null}
foreach($d in @('pending','running','done','failed')){New-Item -ItemType Directory -Path (Join-Path $intent $d) -Force|Out-Null;New-Item -ItemType Directory -Path (Join-Path $control $d) -Force|Out-Null}
while($true){
 @{protocol='AX PC1 BRAIN1 DECISION v1';nodeId='PC1';computerName=$env:COMPUTERNAME;status='ALIVE';heartbeatAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $ev 'brain1-decision-heartbeat.json') -Encoding UTF8
 Get-ChildItem (Join-Path $intent 'pending') -Filter '*.json' -File|Sort LastWriteTime|%{
  $n=$_.Name;$run=Join-Path $intent "running\$n"
  try{Move-Item $_.FullName $run -Force;$i=Get-Content $run -Raw|ConvertFrom-Json
   if($i.targetNode -ne 'PC1'){throw 'TARGET_NODE_NOT_PC1'};if(!$i.jobId){throw 'JOB_ID_MISSING'}
   $allowed=@('NODE_HEALTH_CHECK','SYSTEM_DIAGNOSTIC','CLOSE_STALE_TERMINAL','CAPTURE_AND_REVERIFY','RESTART_OWNED_RUNTIME')
   if($allowed -notcontains $i.intent){throw "BRAIN_INTENT_NOT_ALLOWED:$($i.intent)"}
   $job=[ordered]@{protocol='AX PC1 BRAIN1 CONTROL COMMAND v1';jobId=$i.jobId;targetNode='PC1';command=$i.intent;source='brain1';brainDecision='APPROVED';decidedAt=[DateTime]::UtcNow.ToString('o')}
   $job|ConvertTo-Json|Set-Content (Join-Path $control "pending\$n") -Encoding UTF8
   $i|Add-Member status 'DISPATCHED_TO_CONTROL' -Force;$i|ConvertTo-Json|Set-Content (Join-Path $intent "done\$n") -Encoding UTF8;Remove-Item $run -Force
  }catch{if(Test-Path $run){$i=Get-Content $run -Raw|ConvertFrom-Json;$i|Add-Member status 'FAILED' -Force;$i|Add-Member error $_.Exception.Message -Force;$i|ConvertTo-Json|Set-Content (Join-Path $intent "failed\$n") -Encoding UTF8;Remove-Item $run -Force}}
 }
 Start-Sleep $PollSeconds
}