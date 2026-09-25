param([string]$RuntimeRoot='C:\AX-Runtime',[int]$PollSeconds=15)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$ev=Join-Path $RuntimeRoot 'evidence';New-Item -ItemType Directory -Path $ev -Force|Out-Null
while($true){
 $a=@()
 foreach($n in @('AERIS-PC1-BRAIN1-DECISION','AERIS-PC1-BRAIN1-LOCAL-CONTROL')){
  try{$t=Get-ScheduledTask -TaskName $n -EA Stop;if($t.State -ne 'Running'){Start-ScheduledTask -TaskName $n;$a+="STARTED:$n"}}catch{$a+="MISSING:$n"}
 }
 @{protocol='AX PC1 BRAIN1 WATCHDOG v1';nodeId='PC1';status='ALIVE';heartbeatAt=[DateTime]::UtcNow.ToString('o');actions=$a}|ConvertTo-Json|Set-Content (Join-Path $ev 'brain1-watchdog-heartbeat.json') -Encoding UTF8
 Start-Sleep $PollSeconds
}