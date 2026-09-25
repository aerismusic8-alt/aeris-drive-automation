param(
 [string]$Gateway='http://127.0.0.1:18761',
 [string]$RuntimeRoot='C:\AX-Runtime'
)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$checked=[DateTime]::UtcNow.ToString('o')
$checks=[ordered]@{
 identity=$env:COMPUTERNAME -eq 'DESKTOP-RGK6JKB'
 gatewayHealth=$false
 brainHeartbeat=$false
 controlHeartbeat=$false
}
try{
 $h=Invoke-RestMethod "$Gateway/health" -TimeoutSec 3
 $checks.gatewayHealth=($h.status -eq 'ALIVE' -and $h.nodeId -eq 'PC1' -and $h.computerName -eq $env:COMPUTERNAME)
}catch{}
foreach($name in @('brain1-decision-heartbeat.json','brain1-local-control-heartbeat.json')){
 $p=Join-Path $RuntimeRoot "evidence\$name"
 if(Test-Path $p){
  try{
   $x=Get-Content $p -Raw|ConvertFrom-Json
   $age=([DateTime]::UtcNow-[DateTime]::Parse($x.heartbeatAt)).TotalSeconds
   if($age -le 30 -and $x.nodeId -eq 'PC1' -and $x.computerName -eq $env:COMPUTERNAME){
    if($name -like 'brain1-decision*'){$checks.brainHeartbeat=$true}else{$checks.controlHeartbeat=$true}
   }
  }catch{}
 }
}
$ready=($checks.Values -notcontains $false)
[pscustomobject]@{
 status=if($ready){'READY'}else{'NOT_VERIFIED'}
 nodeId='PC1'
 computerName=$env:COMPUTERNAME
 checkedUtc=$checked
 evidenceScope='PC1_LOCAL'
 checks=$checks
 verificationRule='fresh gateway + brain heartbeat + control heartbeat + identity'
}|ConvertTo-Json -Depth 8