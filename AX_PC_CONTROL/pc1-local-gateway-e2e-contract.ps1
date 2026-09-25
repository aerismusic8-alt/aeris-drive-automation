param(
 [string]$Gateway='http://127.0.0.1:18761',
 [string]$RuntimeRoot='C:\AX-Runtime'
)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$jobId="pc1-gateway-contract-$([guid]::NewGuid().ToString('N'))"
$intent=[ordered]@{
 targetNode='PC1'
 jobId=$jobId
 intent='NODE_HEALTH_CHECK'
 requestedUtc=[DateTime]::UtcNow.ToString('o')
 source='PC1_LOCAL_BRAIN'
 evidenceScope='PC1_LOCAL'
}
$result=[ordered]@{
 status='NOT_VERIFIED'
 nodeId='PC1'
 computerName=$env:COMPUTERNAME
 jobId=$jobId
 checkedUtc=[DateTime]::UtcNow.ToString('o')
 evidenceScope='PC1_LOCAL'
 gatewayHealth=$false
 intentAccepted=$false
 queueEvidence=$false
}
try{
 $h=Invoke-RestMethod "$Gateway/health" -TimeoutSec 3
 $result.gatewayHealth=($h.status -eq 'ALIVE' -and $h.nodeId -eq 'PC1' -and $h.computerName -eq $env:COMPUTERNAME)
 $json=$intent|ConvertTo-Json -Depth 8
 $resp=Invoke-RestMethod "$Gateway/intent" -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 3
 $result.intentAccepted=($resp.accepted -eq $true -and $resp.nodeId -eq 'PC1' -and $resp.jobId -eq $jobId)
 $queueFile=Join-Path $RuntimeRoot "brain1-intent-queue\pending\$jobId.json"
 Start-Sleep -Milliseconds 250
 $result.queueEvidence=Test-Path $queueFile
 $result.status=if($result.gatewayHealth -and $result.intentAccepted -and $result.queueEvidence){'PASS'}else{'NOT_VERIFIED'}
}catch{
 $result.error=$_.Exception.Message
}
$result|ConvertTo-Json -Depth 8