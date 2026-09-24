$base='C:\AX-Runtime\brain2-command-queue\pending'
New-Item -ItemType Directory -Path $base -Force|Out-Null
$id="PC2-TERMINAL-CLEANUP-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff'))"
@{protocol='AX PC2 BRAIN2 LOCAL CONTROL QUEUE v1';jobId=$id;targetNode='PC2';command='CLOSE_STALE_TERMINALS';requestedBy='BRAIN2'}|ConvertTo-Json|Set-Content (Join-Path $base "$id.json") -Encoding UTF8
Write-Host "QUEUED=$id"