param([int]$Attempts=6,[int]$DelaySeconds=5)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){ throw "PC1 identity mismatch: $env:COMPUTERNAME" }
$results=@()
for($i=1;$i -le $Attempts;$i++){
  try {
    $h=Invoke-RestMethod 'http://127.0.0.1:18761/health' -TimeoutSec 3
    $results += [pscustomobject]@{attempt=$i;status='PASS';nodeId=$h.nodeId;computerName=$h.computerName;timestampUtc=$h.timestampUtc}
    break
  } catch {
    $results += [pscustomobject]@{attempt=$i;status='NOT_VERIFIED';reason=$_.Exception.Message}
    if($i -lt $Attempts){ Start-Sleep -Seconds $DelaySeconds }
  }
}
[pscustomobject]@{
  nodeId='PC1'
  computerName=$env:COMPUTERNAME
  verified=($results.status -contains 'PASS')
  evidenceScope='PC1_LOCAL_GATEWAY'
  checkedUtc=(Get-Date).ToUniversalTime().ToString('o')
  attempts=$results
} | ConvertTo-Json -Depth 8
