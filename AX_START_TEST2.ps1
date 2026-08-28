# AX TEST 2 — EXECUTION OBSERVABILITY BOOTSTRAP
$ErrorActionPreference = "Stop"

$stateDir = Join-Path $PSScriptRoot "AX_RUNTIME_STATE"
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

$stateFile = Join-Path $stateDir "AX_EXECUTION_STATE.json"

$state = [ordered]@{
    testId        = "AX-TEST-2-DASHBOARD"
    status        = "RUNNING"
    startedAt     = (Get-Date).ToUniversalTime().ToString("o")
    lastActivityAt= (Get-Date).ToUniversalTime().ToString("o")
    nextAction    = "BUILD_DASHBOARD"
    deadlineAt    = (Get-Date).ToUniversalTime().AddMinutes(15).ToString("o")
    timeoutMinutes= 15
    host          = $env:COMPUTERNAME
    user          = $env:USERNAME
    runner        = $env:RUNNER_NAME
    cycle         = [guid]::NewGuid().ToString()
    verification  = "PENDING"
}

$state | ConvertTo-Json -Depth 10 | Set-Content $stateFile -Encoding UTF8

Write-Host "=== AX TEST 2 STARTED ===" -ForegroundColor Cyan
Write-Host "Test ID: $($state.testId)"
Write-Host "Started: $($state.startedAt)"
Write-Host "Deadline: $($state.deadlineAt)"
Write-Host "Next Action: $($state.nextAction)"
Write-Host "State: $stateFile"
Write-Host "=== AX TEST 2 TIMER ACTIVE ===" -ForegroundColor Green
