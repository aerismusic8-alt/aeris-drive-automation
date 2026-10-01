param(
    [Parameter(Mandatory=$true)]
    [string]$JobId
)

$ErrorActionPreference = 'Stop'
$expected = 'DESKTOP-M9M4818'
if ($env:COMPUTERNAME -ne $expected) { throw "PC2_VERIFIER_IDENTITY_MISMATCH:$env:COMPUTERNAME" }

$runtimeRoot = 'C:\AX-Runtime'
$statePath = Join-Path $runtimeRoot 'AX-PC2-Worker-State.json'
$proofPath = Join-Path (Join-Path $runtimeRoot 'proof') "$JobId.json"
$verificationDir = Join-Path $runtimeRoot 'verification'
New-Item -ItemType Directory -Path $verificationDir -Force | Out-Null

if (-not (Test-Path $statePath)) { throw 'PC2_WORKER_STATE_MISSING' }
if (-not (Test-Path $proofPath)) { throw 'PC2_EXECUTION_PROOF_MISSING' }
$state = Get-Content $statePath -Raw | ConvertFrom-Json
$proof = Get-Content $proofPath -Raw | ConvertFrom-Json
if ($state.status -ne 'COMPLETED') { throw "PC2_WORKER_NOT_COMPLETED:$($state.status)" }
if ($state.currentJobId -ne $JobId) { throw 'PC2_WORKER_JOB_MISMATCH' }
if ($proof.executed -ne $true -or $proof.nodeId -ne 'PC2') { throw 'PC2_EXECUTION_PROOF_INVALID' }
if ($proof.verificationStatus -eq 'VERIFIED') { throw 'PC2_SELF_ATTESTED_PROOF_REJECTED' }
if ($proof.liveFinancialExecution -ne $false) { throw 'UNEXPECTED_LIVE_FINANCIAL_EXECUTION_FLAG' }

$mediaPath = Join-Path (Join-Path $runtimeRoot 'media') "$JobId.mp4"
if (-not (Test-Path $mediaPath)) { throw 'MEDIA_OUTPUT_MISSING' }
$mediaInfo = Get-Item $mediaPath
if ($mediaInfo.Length -le 10000) { throw 'MEDIA_OUTPUT_TOO_SMALL' }

$ffmpeg = Join-Path (Join-Path $runtimeRoot 'tools\ffmpeg') 'ffmpeg.exe'
if (-not (Test-Path $ffmpeg)) { throw 'FFMPEG_NOT_FOUND_FOR_INDEPENDENT_VERIFY' }
& $ffmpeg -hide_banner -loglevel error -i $mediaPath -f null NUL
if ($LASTEXITCODE -ne 0) { throw "MEDIA_DECODE_VERIFY_FAILED:$LASTEXITCODE" }

$verification = [ordered]@{
    protocol = 'AX PC2 LOCAL INDEPENDENT VERIFIER v1'
    jobId = $JobId
    nodeId = 'PC2'
    verified = $true
    verifier = 'AX_PC2_LOCAL_VERIFY_E2E.ps1'
    basis = @('worker_state_completed','execution_proof_executed_without_self_verification','media_exists','media_size_gt_10kb','ffmpeg_decode_exit_0')
    liveFinancialExecution = $false
    verifiedAt = [DateTime]::UtcNow.ToString('o')
    executionProof = $proofPath
    mediaPath = $mediaPath
}
$verificationPath = Join-Path $verificationDir "$JobId.json"
$verification | ConvertTo-Json -Depth 20 | Set-Content -Path $verificationPath -Encoding UTF8
Write-Host "INDEPENDENT_VERIFICATION=$verificationPath"
Write-Host 'RESULT_VERIFIED=VERIFIED'
Write-Host 'LIVE_FINANCIAL_REWARD=NOT_EXECUTED'
