param(
  [string]$StatusUrl = $(if (-not [string]::IsNullOrWhiteSpace($env:AX_AERIS_RUNTIME_URL)) { "$($env:AX_AERIS_RUNTIME_URL.TrimEnd('/'))/health" } else { 'https://aeris-execution-runtime.aerismusic8.workers.dev/health' }),
  [int]$TimeoutSec = 15
)
$ErrorActionPreference = 'Stop'

Write-Host '=== AX AERIS EXECUTION ADAPTER ==='
Write-Host 'Mode: CONTROLLED / VERIFY-FIRST'
Write-Host 'Action: STATUS_PROBE'
Write-Host "Status URL: $StatusUrl"
Write-Host "Timeout: ${TimeoutSec}s"

try {
  $response = Invoke-WebRequest -Uri $StatusUrl -Method Get -UseBasicParsing -TimeoutSec $TimeoutSec
  Write-Host "HTTP Status: $($response.StatusCode)"

  if ($response.StatusCode -ne 200) {
    throw "AERIS_STATUS_HTTP_$($response.StatusCode)"
  }

  $body = $response.Content | ConvertFrom-Json

  if ($body.status -ne 'ONLINE') {
    throw 'AERIS_STATUS_NOT_ONLINE'
  }

  Write-Host 'AERIS Endpoint: ONLINE'
  Write-Host 'AERIS Verification: PASSED'
  Write-Host 'Mutation: NOT_PERFORMED'
  Write-Host 'Execution Result: VERIFIED_STATUS_ONLY'
}
catch {
  Write-Error "AERIS_ADAPTER_FAILED: $($_.Exception.Message)"
  exit 1
}

Write-Host '=== AX AERIS EXECUTION ADAPTER COMPLETE ==='
