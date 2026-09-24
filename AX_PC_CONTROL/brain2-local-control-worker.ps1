param([string]$RuntimeRoot='C:\AX-Runtime',[int]$PollSeconds=2)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-M9M4818'){throw "PC2_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$base=Join-Path $RuntimeRoot 'brain2-command-queue'
$dirs=@('pending','running','done','failed')
$dirs|%{New-Item -ItemType Directory -Path (Join-Path $base $_) -Force|Out-Null}
$ev=Join-Path $RuntimeRoot 'evidence';New-Item -ItemType Directory -Path $ev -Force|Out-Null
$hb=Join-Path $ev 'brain2-local-control-heartbeat.json'
while($true){
 @{protocol='AX PC2 BRAIN2 LOCAL CONTROL QUEUE v1';nodeId='PC2';computerName=$env:COMPUTERNAME;status='ALIVE';heartbeatAt=[DateTime]::UtcNow.ToString('o');pollSeconds=$PollSeconds;queueRoot=$base}|ConvertTo-Json|Set-Content $hb -Encoding UTF8
 Get-ChildItem (Join-Path $base 'pending') -Filter '*.json' -File|Sort LastWriteTime|%{
  $src=$_.FullName;$name=$_.Name;$run=Join-Path $base "running\$name"
  try{
   Move-Item $src $run -Force
   $job=Get-Content $run -Raw|ConvertFrom-Json
   if($job.targetNode -ne 'PC2'){throw 'TARGET_NODE_NOT_PC2'}
   if(-not $job.jobId){throw 'JOB_ID_MISSING'}
   if($job.expiresAt -and ([DateTime]$job.expiresAt) -lt [DateTime]::UtcNow){throw 'JOB_EXPIRED'}
   switch($job.command){
    'CLOSE_STALE_TERMINALS' {
     $protected='brain2|brain-2|control2|control-2|akath|ax-runtime'
     $closed=@();$skipped=@()
     Get-Process|?{$_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match '(?i)(Windows Terminal|PowerShell|Command Prompt|cmd\.exe)'}|%{
      $p=$_;$cmd='';try{$cmd=(Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -EA Stop).CommandLine}catch{}
      if("$($p.ProcessName) $($p.MainWindowTitle) $cmd" -match $protected){$skipped+=$p.Id;return}
      try{if($p.CloseMainWindow()){Start-Sleep -Milliseconds 700;if(-not(Get-Process -Id $p.Id -EA SilentlyContinue)){$closed+=$p.Id}else{$skipped+=$p.Id}}else{$skipped+=$p.Id}}catch{$skipped+=$p.Id}
     }
     $remaining=@(Get-Process|?{$_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match '(?i)(Windows Terminal|PowerShell|Command Prompt|cmd\.exe)'})
     if($remaining.Count){throw "TERMINALS_REMAIN:$($remaining.Count)"}
     $details=@{closed=$closed;skipped=$skipped;remaining=0}
    }
    default{throw "COMMAND_NOT_ALLOWED:$($job.command)"}
   }
   $proof=Join-Path $ev "$($job.jobId).json"
   @{protocol='AX PC2 BRAIN2 LOCAL CONTROL QUEUE v1';nodeId='PC2';jobId=$job.jobId;command=$job.command;status='VERIFIED';completedAt=[DateTime]::UtcNow.ToString('o');details=$details}|ConvertTo-Json -Depth 10|Set-Content $proof -Encoding UTF8
   $job|Add-Member status 'VERIFIED' -Force;$job|Add-Member evidencePath $proof -Force
   $job|ConvertTo-Json -Depth 10|Set-Content (Join-Path $base "done\$name") -Encoding UTF8
   Remove-Item $run -Force
  }catch{
   if(Test-Path $run){$job=Get-Content $run -Raw|ConvertFrom-Json;$job|Add-Member status 'FAILED' -Force;$job|Add-Member error $_.Exception.Message -Force;$job|ConvertTo-Json -Depth 10|Set-Content (Join-Path $base "failed\$name") -Encoding UTF8;Remove-Item $run -Force}
  }
 }
 Start-Sleep $PollSeconds
}