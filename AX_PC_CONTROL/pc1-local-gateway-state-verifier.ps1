param([string]$RuntimeRoot='C:\AX-Runtime')
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$now=[DateTime]::UtcNow
function ReadFresh($path){
 if(!(Test-Path $path)){return $false}
 try{
  $x=Get-Content $path -Raw|ConvertFrom-Json
  $t=$null
  foreach($k in @('heartbeatAt','timestampUtc','updatedUtc','checkedUtc')){
   if($x.PSObject.Properties.Name -contains $k){$t=[DateTime]::Parse($x.$k);break}
  }
  return ($null -ne $t -and ($now-$t).TotalSeconds -le 30)
 }catch{return $false}
}
$gateway=$false
try{
 $h=Invoke-RestMethod 'http://127.0.0.1:18761/health' -TimeoutSec 3
 $gateway=($h.status -eq 'ALIVE' -and $h.nodeId -eq 'PC1' -and $h.computerName -eq $env:COMPUTERNAME)
}catch{}
$brain=ReadFresh (Join-Path $RuntimeRoot 'evidence\brain1-decision-heartbeat.json')
$control=ReadFresh (Join-Path $RuntimeRoot 'evidence\brain1-local-control-heartbeat.json')
$state='NOT_VERIFIED'
if($gateway){$state='ALIVE'}
if($gateway -and $brain -and $control){$state='READY'}
[pscustomobject]@{
 status=$state
 nodeId='PC1'
 computerName=$env:COMPUTERNAME
 checkedUtc=$now.ToString('o')
 gatewayAlive=$gateway
 brainHeartbeatFresh=$brain
 controlHeartbeatFresh=$control
 evidenceScope='PC1_LOCAL'
 rule='UNKNOWN/NOT_VERIFIED unless fresh local evidence; READY requires gateway+brain+control'
}|ConvertTo-Json -Depth 6