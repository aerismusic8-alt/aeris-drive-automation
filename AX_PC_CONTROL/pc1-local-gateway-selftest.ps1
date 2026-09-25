$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){ throw "PC1 identity mismatch: $env:COMPUTERNAME" }
$base='http://127.0.0.1:18761'
$checked=(Get-Date).ToUniversalTime().ToString('o')
try {
  $h=Invoke-RestMethod "$base/health" -TimeoutSec 3
  [pscustomobject]@{
    status='PASS'
    nodeId=$h.nodeId
    computerName=$h.computerName
    gatewayAlive=$true
    checkedUtc=$checked
    evidenceScope='PC1_LOCAL_GATEWAY'
  } | ConvertTo-Json -Depth 5
} catch {
  [pscustomobject]@{
    status='NOT_VERIFIED'
    nodeId='PC1'
    computerName=$env:COMPUTERNAME
    gatewayAlive=$false
    checkedUtc=$checked
    reason=$_.Exception.Message
    evidenceScope='PC1_LOCAL_GATEWAY'
  } | ConvertTo-Json -Depth 5
}
