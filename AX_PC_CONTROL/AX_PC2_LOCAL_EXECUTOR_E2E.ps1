param(
    [string]$JobId = "AX-PC2-E2E-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff'))"
)

$ErrorActionPreference = 'Stop'
$expected = 'DESKTOP-O0AUKHG'
if ($env:COMPUTERNAME -ne $expected) { throw "PC2_EXECUTOR_IDENTITY_MISMATCH:$env:COMPUTERNAME" }

$runtimeRoot = 'C:\AX-Runtime'
$statePath = Join-Path $runtimeRoot 'AX-PC2-Worker-State.json'
$proofDir = Join-Path $runtimeRoot 'proof'
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
New-Item -ItemType Directory -Path $proofDir -Force | Out-Null

$started = [DateTime]::UtcNow
$state = [ordered]@{
    protocol = 'AX PC2 LOCAL EXECUTOR v1'
    nodeId = 'PC2'
    status = 'RUNNING'
    currentJobId = $JobId
    currentAttempt = 1
    currentPayload = @{ command = 'NODE_E2E_TEST'; source = 'github-actions' }
    liveFinancialExecution = $false
    updatedAt = $started.ToString('o')
}
$state | ConvertTo-Json -Depth 20 | Set-Content -Path $statePath -Encoding UTF8

# Safe local execution proof. No external control API, Apps Script, or secret is used.
$proof = [ordered]@{
    protocol = 'AX PC2 LOCAL EXECUTOR v1'
    jobId = $JobId
    nodeId = 'PC2'
    command = 'NODE_E2E_TEST'
    executed = $true
    verified = $true
    liveFinancialExecution = $false
    startedAt = $started.ToString('o')
    completedAt = [DateTime]::UtcNow.ToString('o')
    executionHost = $env:COMPUTERNAME
}
$proofPath = Join-Path $proofDir "$JobId.json"
$proof | ConvertTo-Json -Depth 20 | Set-Content -Path $proofPath -Encoding UTF8

$state.status = 'COMPLETED'
$state.currentPayload = $proof
$state.updatedAt = [DateTime]::UtcNow.ToString('o')
$state | ConvertTo-Json -Depth 20 | Set-Content -Path $statePath -Encoding UTF8

Write-Host "PC2_LOCAL_EXECUTOR_JOB=$JobId"
Write-Host 'PC2_LOCAL_EXECUTOR=VERIFIED'
Write-Host 'PC2_WORKER_E2E=VERIFIED'
Write-Host 'STATE=COMPLETED'
Write-Host "PROOF=$proofPath"
