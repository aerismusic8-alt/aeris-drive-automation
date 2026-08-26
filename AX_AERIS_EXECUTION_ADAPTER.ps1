param(
  [string]$StatusUrl = 'https://script.google.com/macros/s/AKfycbwz6F8EWTD7YwnGkyu4Mq_JHtBkk6nOwl9TYjWDsMsQTtS5EVj3I6hmakuW6yP_YGQH/exec?mode=status'
)
$ErrorActionPreference = 'Stop'
Write-Host '=== AX AERIS EXECUTION ADAPTER ==='
Write-Host 'Mode: CONTROLLED / VERIFY-FIRST'
Write-Host 'Action: STATUS_PROBE'
try {
  $response = Invoke-WebRequest -Uri $StatusUrl -Method Get -UseBasicParsing -TimeoutSec 20
  Write-Host "HTTP Status: $($response.StatusCode)"
  if ($response.StatusCode -ne 200) { throw "AERIS_STATUS_HTTP_$($response.StatusCode)" }
  Write-Host 'AERIS Endpoint: ONLINE'
  Write-Host 'AERIS Verification: PASSED'
  Write-Host 'Mutation: NOT_PERFORMED'
  Write-Host 'Execution Result: VERIFIED_STATUS_ONLY'
} catch {
  Write-Error "AERIS_ADAPTER_FAILED: $($_.Exception.Message)"
  exit 1
}
Write-Host '=== AX AERIS EXECUTION ADAPTER COMPLETE ==='
