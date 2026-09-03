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
Write-Host 'Mode: READ_ONLY / VERIFY-FIRST'
Write-Host 'Action: RUNTIME_HEALTH_PROBE_ONLY'
Write-Host "Status URL: $StatusUrl"
Write-Host "Timeout: ${TimeoutSec}s"

try {
  $response = Invoke-WebRequest `
    -Uri $StatusUrl `
    -Method Get `
    -UseBasicParsing `
    -TimeoutSec $TimeoutSec

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
  Write-Host 'Runtime Health Verification: PASSED'
  Write-Host 'Business Execution Evidence: NOT_PRODUCED'
  Write-Host 'Business Completion: NOT_CLAIMED'
  Write-Host 'Proof Artifact: NONE'
}
catch {
  Write-Error "AERIS_ADAPTER_FAILED: $($_.Exception.Message)"
  exit 1
}

Write-Host '=== AX AERIS EXECUTION ADAPTER COMPLETE ==='