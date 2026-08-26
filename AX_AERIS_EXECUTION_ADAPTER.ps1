param(
  [string]$RuntimeUrl = $(if (-not [string]::IsNullOrWhiteSpace($env:AX_AERIS_RUNTIME_URL)) {
    $env:AX_AERIS_RUNTIME_URL.TrimEnd('/')
  } else {
    'https://aeris-execution-runtime.aerismusic8.workers.dev'
  }),
  [int]$TimeoutSec = 15
)

$ErrorActionPreference = 'Stop'

Write-Host '=== AX AERIS EXECUTION ADAPTER ==='
Write-Host 'Mode: CONTROLLED / VERIFY-FIRST'
Write-Host 'Action: STATUS_PROBE'
Write-Host "Runtime URL: $RuntimeUrl"
Write-Host "Timeout: ${TimeoutSec}s"

$StatusUrl = "$RuntimeUrl/health"

try {
  Write-Host "Status URL: $StatusUrl"

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

  Write-Host "Service: $($body.service)"
  Write-Host "Status: $($body.status)"
  Write-Host "Mode: $($body.mode)"
  Write-Host "Live Financial Execution: $($body.liveFinancialExecution)"
  Write-Host "Queue: $($body.queue)"

  if ($body.status -ne 'ONLINE') {
    throw 'AERIS_STATUS_NOT_ONLINE'
  }

  if ($body.mode -ne 'FREE_ONLY') {
    throw 'AERIS_RUNTIME_MODE_NOT_FREE_ONLY'
  }

  if ($body.liveFinancialExecution -ne $false) {
    throw 'AERIS_LIVE_FINANCIAL_EXECUTION_ENABLED'
  }

  if ([string]::IsNullOrWhiteSpace($body.queue)) {
    throw 'AERIS_QUEUE_NOT_DECLARED'
  }

  Write-Host 'AERIS Endpoint: ONLINE'
  Write-Host 'AERIS Mode: FREE_ONLY'
  Write-Host 'AERIS Financial Execution: DISABLED'
  Write-Host 'AERIS Verification: PASSED'
  Write-Host 'Mutation: NOT_PERFORMED'
  Write-Host 'Execution Result: VERIFIED_STATUS_ONLY'
}
catch {
  Write-Error "AERIS_ADAPTER_FAILED: $($_.Exception.Message)"
  exit 1
}

Write-Host '=== AX AERIS EXECUTION ADAPTER COMPLETE ==='
