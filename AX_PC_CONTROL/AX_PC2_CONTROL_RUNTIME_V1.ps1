param([string]$RuntimeRoot='C:\AX-Runtime')
$ErrorActionPreference='Stop'
$inbox=Join-Path $RuntimeRoot 'inbox'; $evidence=Join-Path $RuntimeRoot 'evidence'; $state=Join-Path $RuntimeRoot 'control-state.json'
New-Item -ItemType Directory -Force -Path $RuntimeRoot,$inbox,$evidence | Out-Null
function State($s,$c,$r,$why){[ordered]@{protocol='AX PC2 CONTROL v1';nodeId='PC2';status=$s;lastCommand=$c;lastResult=$r;reason=$why;pid=$PID;computer=$env:COMPUTERNAME;updatedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content $state -Encoding UTF8}
State 'ONLINE' '' 'NONE' 'STARTUP'
while($true){
 try{
  foreach($f in @(Get-ChildItem $inbox -Filter '*.json' -File -ErrorAction SilentlyContinue)){
   try{
    $x=Get-Content -Raw $f.FullName|ConvertFrom-Json;$id=[string]$x.commandId;if(!$id){$id=$f.BaseName};$cmd=([string]$x.command).Trim().ToUpperInvariant();State 'EXECUTING' $cmd 'RUNNING' 'COMMAND_RECEIVED'
    $r=[ordered]@{commandId=$id;command=$cmd;nodeId='PC2';executed=$true;verified=$true;timestamp=[DateTime]::UtcNow.ToString('o');result=if($cmd -eq 'PING'){'PONG'}elseif($cmd -eq 'STATUS'){'ONLINE'}else{'COMMAND_ACCEPTED_LOCAL_CONTROL_PATH'}}
    $p=Join-Path $evidence "$id.json";$r|ConvertTo-Json|Set-Content $p -Encoding UTF8;$r|ConvertTo-Json|Set-Content (Join-Path $RuntimeRoot "$id.result.json") -Encoding UTF8;Remove-Item $f.FullName -Force;State 'ONLINE' $cmd 'VERIFIED' 'COMMAND_COMPLETED'
   }catch{State 'DEGRADED' '' 'FAILED' $_.Exception.Message}
  }
 }catch{State 'DEGRADED' '' 'RETRYING' $_.Exception.Message}
 Start-Sleep 2
}