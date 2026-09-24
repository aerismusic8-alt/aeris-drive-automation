param(
 [Parameter(Mandatory=$true)][ValidateSet('CLOSE_STALE_TERMINALS','NODE_HEALTH_CHECK')][string]$Command,
 [string]$JobId = "SSH-PC2-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff'))",
 [int]$TtlSeconds = 300
)
$ErrorActionPreference='Stop'
$expected='DESKTOP-M9M4818'
if($env:COMPUTERNAME -ne $expected){throw "PC2_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$base='C:\AX-Runtime\brain2-command-queue'
$pending=Join-Path $base 'pending'
New-Item -ItemType Directory -Path $pending -Force|Out-Null
$job=[ordered]@{
 protocol='AX PC2 BRAIN2 SSH ENTRY v1'
 jobId=$JobId
 targetNode='PC2'
 command=$Command
 source='ssh'
 submittedAt=[DateTime]::UtcNow.ToString('o')
 expiresAt=[DateTime]::UtcNow.AddSeconds($TtlSeconds).ToString('o')
}
$path=Join-Path $pending "$JobId.json"
$job|ConvertTo-Json -Depth 10|Set-Content $path -Encoding UTF8
Write-Output ("BRAIN2_ACCEPTED jobId={0} command={1}" -f $JobId,$Command)
