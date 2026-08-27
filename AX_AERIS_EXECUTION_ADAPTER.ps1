param(
  [string]$StatusUrl = $(if (-not [string]::IsNullOrWhiteSpace($env:AX_AERIS_RUNTIME_URL)) {
    $env:AX_AERIS_RUNTIME_URL.TrimEnd('/')
  } else {
    'https://aeris-execution-runtime.aerismusic8.workers.dev'
  }),
  [int]$TimeoutSec = 15
)

$ErrorActionPreference = 'Stop'

Write-Host '=== AX AERIS EXECUTION ADAPTER ==='
Write-Host 'Mode: CONTROLLED / VERIFY-FIRST'
Write-Host 'Action: STATUS_PROBE_AND_RUNTIME_ACTION_PROOF'
Write-Host "Status URL: $StatusUrl"
Write-Host "Timeout: ${TimeoutSec}s"

try {
  $response = Invoke-WebRequest `
    -Uri $StatusUrl `
    -Method Get `
    -UseBasicParsing `
    -TimeoutSec $TimeoutSec

  Write-Host "HTTP Status: $($response.StatusCode)"

  if ($response.StatusCode -ne 200) {
    throw "AERIS_STATUS_HTTP_$($response.StatusCode)"
  }

  $body = $response.Content | ConvertFrom-Json

  if ($body.status -ne 'ONLINE') {
    throw 'AERIS_STATUS_NOT_ONLINE'
  }

  if ($body.service -ne 'AERIS_EXTERNAL_EXECUTION_RUNTIME') {
    throw 'AERIS_SERVICE_IDENTITY_MISMATCH'
  }

  if ($body.gate -ne 'GATE_3') {
    throw 'AERIS_GATE_IDENTITY_MISMATCH'
  }

  Write-Host "Service: $($body.service)"
  Write-Host "Version: $($body.version)"
  Write-Host "Gate: $($body.gate)"
  Write-Host "Runtime Mode: $($body.mode)"
  Write-Host "Apps Script: $($body.appsScript)"
  Write-Host "Gemini: $($body.gemini)"
  Write-Host 'AERIS Endpoint: ONLINE'
  Write-Host 'AERIS Verification: PASSED'

  # Real unattended runner action: create, read back, and verify an execution artifact.
  # RUNNER_TEMP exists inside GitHub Actions but may be absent during direct/local execution.
  $tempRoot = if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    $env:RUNNER_TEMP
  } elseif (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
    $env:TEMP
  } else {
    [System.IO.Path]::GetTempPath()
  }

  if (-not (Test-Path $tempRoot)) {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
  }

  $cycleId = [guid]::NewGuid().ToString()
  $proofPath = Join-Path $tempRoot "AX_AERIS_ACTION_$cycleId.json"
  $proof = @{
    cycleId = $cycleId
    action = 'CREATE_AND_VERIFY_RUNTIME_ARTIFACT'
    executed = $true
    verified = $false
    executedAt = (Get-Date).ToUniversalTime().ToString('o')
    runtime = $body.service
  } | ConvertTo-Json -Compress

  Set-Content -Path $proofPath -Value $proof -Encoding UTF8
  if (-not (Test-Path $proofPath)) {
    throw 'AX_AERIS_ACTION_ARTIFACT_NOT_CREATED'
  }

  $readBack = Get-Content -Raw -Path $proofPath | ConvertFrom-Json
  if ($readBack.cycleId -ne $cycleId -or $readBack.executed -ne $true) {
    throw 'AX_AERIS_ACTION_ARTIFACT_READBACK_FAILED'
  }

  $readBack.verified = $true
  $readBack | ConvertTo-Json -Compress | Set-Content -Path $proofPath -Encoding UTF8
  $final = Get-Content -Raw -Path $proofPath | ConvertFrom-Json

  if ($final.verified -ne $true) {
    throw 'AX_AERIS_ACTION_ARTIFACT_FINAL_VERIFY_FAILED'
  }

  Write-Host 'Unattended action: EXECUTED'
  Write-Host 'Unattended action read-back: PASSED'
  Write-Host 'Unattended action verification: PASSED'
  Write-Host "Action evidence: $proofPath"
  Write-Host 'Mutation: CONTROLLED_LOCAL_RUNTIME_ARTIFACT_ONLY'
  Write-Host 'Execution Result: VERIFIED'
}
catch {
  Write-Error "AERIS_ADAPTER_FAILED: $($_.Exception.Message)"
  exit 1
}

Write-Host '=== AX AERIS EXECUTION ADAPTER COMPLETE ==='
