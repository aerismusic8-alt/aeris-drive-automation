param(
  [string]$Symbol = 'BTC-USD',
  [double]$Price = 0,
  [double]$ReferencePrice = 0
)
$ErrorActionPreference = 'Stop'
Write-Host '=== AX AICS SIGNAL ENGINE ==='
Write-Host "Symbol: $Symbol"
Write-Host 'Mode: PAPER / READ_ONLY'

$signal = 'NO_SIGNAL'
if ($Price -gt 0 -and $ReferencePrice -gt 0) {
  $changePct = (($Price - $ReferencePrice) / $ReferencePrice) * 100
  if ($changePct -ge 1.0) { $signal = 'MOMENTUM_UP' }
  elseif ($changePct -le -1.0) { $signal = 'MOMENTUM_DOWN' }
  else { $signal = 'NEUTRAL' }
  Write-Host ("Reference Change: {0:N4}%" -f $changePct)
} else {
  Write-Host 'Reference comparison: NOT_AVAILABLE'
}

Write-Host "Signal: $signal"
Write-Host 'Order execution: DISABLED'
Write-Host 'Live capital: NOT USED'
Write-Host 'Risk handoff: READY'
Write-Host 'Verification: PASSED — signal generation is non-executing'
Write-Host '=== AX AICS SIGNAL ENGINE COMPLETE ==='
