param([string]$RuntimeRoot='C:\AX-Runtime',[int]$PollSeconds=2)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-M9M4818'){throw "PC2_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$intentRoot=Join-Path $RuntimeRoot 'brain2-intent-queue'
$controlRoot=Join-Path $RuntimeRoot 'brain2-command-queue'
foreach($d in @('pending','running','done','failed')){New-Item -ItemType Directory -Path (Join-Path $intentRoot $d) -Force|Out-Null}
foreach($d in @('pending','running','done','failed')){New-Item -ItemType Directory -Path (Join-Path $controlRoot $d) -Force|Out-Null}
$ev=Join-Path $RuntimeRoot 'evidence';New-Item -ItemType Directory -Path $ev -Force|Out-Null
$hb=Join-Path $ev 'brain2-decision-heartbeat.json'
while($true){
 @{protocol='AX PC2 BRAIN2 DECISION BRAIN v1';nodeId='PC2';computerName=$env:COMPUTERNAME;role='BRAIN';status='ALIVE';heartbeatAt=[DateTime]::UtcNow.ToString('o');pollSeconds=$PollSeconds}|ConvertTo-Json|Set-Content $hb -Encoding UTF8
 Get-ChildItem (Join-Path $intentRoot 'pending') -Filter '*.json' -File|Sort LastWriteTime|%{
  $src=$_.FullName;$name=$_.Name;$run=Join-Path $intentRoot "running\$name"
  try{
   Move-Item $src $run -Force
   $i=Get-Content $run -Raw|ConvertFrom-Json
   if($i.targetNode -ne 'PC2'){throw 'TARGET_NODE_NOT_PC2'}
   if(-not $i.jobId){throw 'JOB_ID_MISSING'}
   if($i.expiresAt -and ([DateTime]$i.expiresAt) -lt [DateTime]::UtcNow){throw 'INTENT_EXPIRED'}
   $command=$null
   switch($i.intent){
    'CLOSE_STALE_TERMINALS' {$command='CLOSE_STALE_TERMINALS'}
    'NODE_HEALTH_CHECK' {$command='NODE_HEALTH_CHECK'}
    default {throw "BRAIN_INTENT_NOT_ALLOWED:$($i.intent)"}
   }
   $job=[ordered]@{protocol='AX PC2 BRAIN2 CONTROL COMMAND v1';jobId=$i.jobId;targetNode='PC2';command=$command;source='brain2';brainDecision='APPROVED';decidedAt=[DateTime]::UtcNow.ToString('o');expiresAt=$i.expiresAt}
   $dst=Join-Path $controlRoot "pending\$name"
   $job|ConvertTo-Json -Depth 10|Set-Content $dst -Encoding UTF8
   $proof=Join-Path $ev "$($i.jobId)-brain-decision.json"
   @{protocol='AX PC2 BRAIN2 DECISION PROOF v1';jobId=$i.jobId;nodeId='PC2';intent=$i.intent;decision='APPROVED';command=$command;decidedAt=[DateTime]::UtcNow.ToString('o');dispatchedTo='brain2-command-queue/pending'}|ConvertTo-Json -Depth 10|Set-Content $proof -Encoding UTF8
   $i|Add-Member status 'DISPATCHED_TO_CONTROL' -Force;$i|Add-Member evidencePath $proof -Force
   $i|ConvertTo-Json -Depth 10|Set-Content (Join-Path $intentRoot "done\$name") -Encoding UTF8
   Remove-Item $run -Force
  }catch{
   if(Test-Path $run){$i=Get-Content $run -Raw|ConvertFrom-Json;$i|Add-Member status 'FAILED' -Force;$i|Add-Member error $_.Exception.Message -Force;$i|ConvertTo-Json -Depth 10|Set-Content (Join-Path $intentRoot "failed\$name") -Encoding UTF8;Remove-Item $run -Force}
  }
 }
 Start-Sleep $PollSeconds
}
