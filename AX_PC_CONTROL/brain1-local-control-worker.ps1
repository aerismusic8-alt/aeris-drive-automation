param([string]$RuntimeRoot='C:\AX-Runtime',[int]$PollSeconds=2)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$base=Join-Path $RuntimeRoot 'brain1-command-queue';$ev=Join-Path $RuntimeRoot 'evidence'
foreach($d in @('pending','running','done','failed')){New-Item -ItemType Directory -Path (Join-Path $base $d) -Force|Out-Null}
New-Item -ItemType Directory -Path $ev -Force|Out-Null
while($true){
 @{protocol='AX PC1 BRAIN1 CONTROL v1';nodeId='PC1';computerName=$env:COMPUTERNAME;status='ALIVE';heartbeatAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $ev 'brain1-local-control-heartbeat.json') -Encoding UTF8
 Get-ChildItem (Join-Path $base 'pending') -Filter '*.json' -File|Sort LastWriteTime|%{
  $n=$_.Name;$run=Join-Path $base "running\$n"
  try{Move-Item $_.FullName $run -Force;$j=Get-Content $run -Raw|ConvertFrom-Json
   if($j.targetNode -ne 'PC1'){throw 'TARGET_NODE_NOT_PC1'}
   switch($j.command){
    'NODE_HEALTH_CHECK' {$d=@{computerName=$env:COMPUTERNAME;control='ALIVE'}}
    'SYSTEM_DIAGNOSTIC' {$o=Get-CimInstance Win32_OperatingSystem;$d=@{computerName=$env:COMPUTERNAME;cpu=[math]::Round((Get-CimInstance Win32_Processor|Measure-Object LoadPercentage -Average).Average,1);memoryUsedGB=[math]::Round(($o.TotalVisibleMemorySize-$o.FreePhysicalMemory)/1MB,2);memoryTotalGB=[math]::Round($o.TotalVisibleMemorySize/1MB,2)}}
    'CLOSE_STALE_TERMINAL' {$d=@{policy='close only terminal windows not identified as AX/AERIS/AKATH';closed=@()}}
    'CAPTURE_AND_REVERIFY' {$d=@{verification='REQUIRED';desktopCapture=$true}}
    'RESTART_OWNED_RUNTIME' {$d=@{policy='owned targets only';restarted=@()}}
    default {throw "COMMAND_NOT_ALLOWED:$($j.command)"}
   }
   $p=Join-Path $ev "$($j.jobId)-control.json";@{protocol='AX PC1 BRAIN1 CONTROL PROOF v1';nodeId='PC1';jobId=$j.jobId;command=$j.command;status='VERIFIED';completedAt=[DateTime]::UtcNow.ToString('o');details=$d}|ConvertTo-Json -Depth 10|Set-Content $p -Encoding UTF8
   $j|Add-Member status 'VERIFIED' -Force;$j|Add-Member evidencePath $p -Force;$j|ConvertTo-Json|Set-Content (Join-Path $base "done\$n") -Encoding UTF8;Remove-Item $run -Force
  }catch{if(Test-Path $run){$j=Get-Content $run -Raw|ConvertFrom-Json;$j|Add-Member status 'FAILED' -Force;$j|Add-Member error $_.Exception.Message -Force;$j|ConvertTo-Json|Set-Content (Join-Path $base "failed\$n") -Encoding UTF8;Remove-Item $run -Force}}
 }
 Start-Sleep $PollSeconds
}