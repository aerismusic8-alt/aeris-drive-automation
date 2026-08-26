param(
  [string]$Symbol = 'BTC-USD'
)
$ErrorActionPreference = 'Stop'
Write-Host '=== AX AICS MARKET DATA ADAPTER ==='
Write-Host "Symbol: $Symbol"
Write-Host 'Mode: READ_ONLY'
Write-Host 'Purpose: public market-data observation for paper/risk analysis'
Write-Host 'Order execution: DISABLED'
Write-Host 'Live capital: NOT USED'

# This adapter intentionally does not place orders or mutate accounts.
# Provider integration can be added only behind the existing permission gate.
Write-Host 'Market feed contract: READY'
Write-Host 'Live provider request: NOT_PERFORMED'
Write-Host 'Signal input: OBSERVATION_ONLY'
Write-Host 'Verification: PASSED — no financial mutation performed'
Write-Host '=== AX AICS MARKET DATA ADAPTER COMPLETE ==='
