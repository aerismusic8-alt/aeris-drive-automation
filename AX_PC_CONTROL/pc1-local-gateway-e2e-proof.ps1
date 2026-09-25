param([string]$Gateway='http://127.0.0.1:18761',[string]$RuntimeRoot='C:\AX-Runtime')
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$checked=[DateTime]::UtcNow.ToString('o')
$jobId="pc1-gateway-e2e-"+([guid]::NewGuid().ToString('N'))
$intent=[ordered]@{targetNode='PC1';jobId=$jobId;intent='NODE_HEALTH_CHECK';requestedUtc=$checked;source='PC1_LOCAL_BRAIN';eventNode='PC1'}
$h=$null;$post=$null
try{
 $h=Invoke-RestMethod "$Gateway/health" -TimeoutSec 3
 if($h.nodeId -ne 'PC1' -or $h.computerName -ne $env:COMPUTERNAME){throw 'GATEWAY_IDENTITY_MISMATCH'}
 $json=$intent|ConvertTo-Json
 $post=Invoke-RestMethod "$Gateway/intent" -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 3
 $queue=Join-Path $RuntimeRoot "brain1-intent-queue\pending\$jobId.json"
 $queued=Test-Path $queue
 [pscustomobject]@{status=if($queued -and $post.accepted){'PASS'}else{'NOT_VERIFIED'};nodeId='PC1';computerName=$env:COMPUTERNAME;gatewayAlive=$true;intentAccepted=[bool]$post.accepted;queueFilePresent=$queued;jobId=$jobId;checkedUtc=$checked;evidenceScope='PC1_LOCAL_GATEWAY_E2E'}|ConvertTo-Json -Depth 8
}catch{
 [pscustomobject]@{status='NOT_VERIFIED';nodeId='PC1';computerName=$env:COMPUTERNAME;gatewayAlive=($null -ne $h);intentAccepted=$false;queueFilePresent=$false;jobId=$jobId;checkedUtc=$checked;reason=$_.Exception.Message;evidenceScope='PC1_LOCAL_GATEWAY_E2E'}|ConvertTo-Json -Depth 8
}