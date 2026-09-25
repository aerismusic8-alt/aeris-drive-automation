param(
  [string]$BaseUrl = 'http://127.0.0.1:18761'
)
$ErrorActionPreference='Stop'
$computer=$env:COMPUTERNAME
if($computer -ne 'DESKTOP-RGK6JKB'){
  throw "PC1 identity mismatch: $computer"
}
$health=Invoke-RestMethod -Uri "$BaseUrl/health" -Method Get -TimeoutSec 5
[pscustomobject]@{
  status='PASS'
  nodeId=$health.nodeId
  computerName=$health.computerName
  gatewayTimestamp=$health.timestampUtc
  checkedUtc=(Get-Date).ToUniversalTime().ToString('o')
  evidenceScope='PC1_LOCAL_GATEWAY'
} | ConvertTo-Json -Depth 5
