param(
    [string]$JobId = "AX-PC2-DISPATCH-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff'))",
    [ValidateSet('NODE_E2E_TEST')]
    [string]$Command = 'NODE_E2E_TEST'
)

$ErrorActionPreference = 'Stop'
$expected = 'DESKTOP-M9M4818'
if ($env:COMPUTERNAME -ne $expected) { throw "PC2_DISPATCHER_IDENTITY_MISMATCH:$env:COMPUTERNAME" }

$dispatchStarted = [DateTime]::UtcNow
$runtimeRoot = 'C:\AX-Runtime'
$dispatchDir = Join-Path $runtimeRoot 'dispatch'
New-Item -ItemType Directory -Path $dispatchDir -Force | Out-Null

$record = [ordered]@{
    protocol = 'AX PC2 LOCAL DISPATCHER v1'
    jobId = $JobId
    command = $Command
    targetNode = 'PC2'
    dispatcher = 'AX'
    transport = 'local-pcsev'
    externalRuntimeApi = $false
    appsScript = $false
    dispatchStatus = 'ACCEPTED'
    dispatchedAt = $dispatchStarted.ToString('o')
}
$record | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $dispatchDir "$JobId.json") -Encoding UTF8
Write-Host "DISPATCH_JOB=$JobId"
Write-Host 'DISPATCH_ACCEPTED=VERIFIED'
Write-Host 'DISPATCH_TARGET=PC2'
Write-Host 'DISPATCH_TRANSPORT=LOCAL_PCSEV'

$executor = Join-Path $PSScriptRoot 'AX_PC2_LOCAL_EXECUTOR_E2E.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $executor -JobId $JobId
if ($LASTEXITCODE -ne 0) { throw "PC2_EXECUTOR_EXIT:$LASTEXITCODE" }

$statePath = Join-Path $runtimeRoot 'AX-PC2-Worker-State.json'
if (-not (Test-Path $statePath)) { throw 'PC2_WORKER_STATE_MISSING' }
$state = Get-Content $statePath -Raw | ConvertFrom-Json
if ($state.status -ne 'COMPLETED') { throw "PC2_DISPATCH_NOT_COMPLETED:$($state.status)" }

$proof = Get-ChildItem (Join-Path $runtimeRoot 'proof') -File | Where-Object { $_.BaseName -eq $JobId } | Select-Object -First 1
if (-not $proof) { throw 'PC2_DISPATCH_PROOF_MISSING' }
$proofData = Get-Content $proof.FullName -Raw | ConvertFrom-Json
if ($proofData.verified -ne $true -or $proofData.nodeId -ne 'PC2') { throw 'PC2_DISPATCH_PROOF_NOT_VERIFIED' }

$completedAt = [DateTime]::UtcNow
$record.dispatchStatus = 'COMPLETED'
$record.completedAt = $completedAt.ToString('o')
$record.verified = $true
$record.proof = $proof.FullName
$record | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $dispatchDir "$JobId.json") -Encoding UTF8

Write-Host 'PC2_EXECUTED=VERIFIED'
Write-Host 'RESULT_VERIFIED=VERIFIED'
Write-Host 'STATE=COMPLETED'
Write-Host 'WRITE_BACK=VERIFIED'
Write-Host "PROOF=$($proof.FullName)"
