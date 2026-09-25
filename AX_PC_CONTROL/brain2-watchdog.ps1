param([string]$RuntimeRoot='C:\AX-Runtime',[int]$PollSeconds=15)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-M9M4818'){throw "PC2_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$evidence=Join-Path $RuntimeRoot 'evidence'
New-Item -ItemType Directory -Path $evidence -Force|Out-Null
$hb=Join-Path $evidence 'brain2-watchdog-heartbeat.json'
$tasks=@('AERIS-PC2-BRAIN2-LOCAL-CONTROL','AERIS-PC2-BRAIN2-DECISION')
while($true){
  $actions=@()
  foreach($name in $tasks){
    try{
      $t=Get-ScheduledTask -TaskName $name -ErrorAction Stop
      if($t.State -eq 'Disabled'){Enable-ScheduledTask -TaskName $name|Out-Null;$actions+="ENABLED:$name"}
      $i=Get-ScheduledTaskInfo -TaskName $name -ErrorAction Stop
      if($t.State -ne 'Running' -and (($i.LastTaskResult -ne 0) -or -not $i.LastRunTime -or ((Get-Date)-$i.LastRunTime).TotalMinutes -gt 2)){
        Start-ScheduledTask -TaskName $name
        $actions+="STARTED:$name"
      }
    }catch{
      $actions+="MISSING:$name"
    }
  }
  @{protocol='AX PC2 BRAIN2 WATCHDOG v1';nodeId='PC2';computerName=$env:COMPUTERNAME;role='WATCHDOG';status='ALIVE';heartbeatAt=[DateTime]::UtcNow.ToString('o');actions=$actions}|ConvertTo-Json -Depth 10|Set-Content $hb -Encoding UTF8
  Start-Sleep $PollSeconds
}
