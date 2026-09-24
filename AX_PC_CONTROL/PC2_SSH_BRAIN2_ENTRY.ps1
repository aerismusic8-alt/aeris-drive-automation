param(
 [Parameter(Mandatory=$true)][ValidateSet('CLOSE_STALE_TERMINALS','NODE_HEALTH_CHECK')][string]$Command,
 [string]$JobId = "SSH-PC2-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff'))",
 [int]$TtlSeconds = 300
)
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-M9M4818'){throw "PC2_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$base='C:\AX-Runtime\brain2-intent-queue'
$pending=Join-Path $base 'pending'
New-Item -ItemType Directory -Path $pending -Force|Out-Null
$intent=[ordered]@{
 protocol='AX PC2 BRAIN2 INTENT QUEUE v1'
 jobId=$JobId
 targetNode='PC2'
 intent=$Command
 source='ssh'
 submittedAt=[DateTime]::UtcNow.ToString('o')
 expiresAt=[DateTime]::UtcNow.AddSeconds($TtlSeconds).ToString('o')
}
$path=Join-Path $pending "$JobId.json"
$intent|ConvertTo-Json -Depth 10|Set-Content $path -Encoding UTF8
Write-Output ("BRAIN2_INTENT_ACCEPTED jobId={0} intent={1}" -f $JobId,$Command)
