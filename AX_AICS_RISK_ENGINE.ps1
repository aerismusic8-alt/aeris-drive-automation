param(
  [ValidateSet('MOMENTUM_UP','MOMENTUM_DOWN','NEUTRAL','NO_SIGNAL')]
  [string]$Signal = 'NO_SIGNAL',
  [double]$Capital = 1000,
  [double]$RiskPercent = 0.5,
  [double]$StopDistancePct = 2.0
)
$ErrorActionPreference = 'Stop'
Write-Host '=== AX AICS RISK ENGINE ==='
Write-Host 'Mode: PAPER_ONLY'
Write-Host "Signal: $Signal"
Write-Host ("Paper Capital: {0:N2}" -f $Capital)

if ($Capital -le 0) { throw 'RISK_ENGINE_INVALID_CAPITAL' }
if ($RiskPercent -le 0 -or $RiskPercent -gt 2) { throw 'RISK_ENGINE_RISK_PERCENT_OUT_OF_BOUNDS' }
if ($StopDistancePct -le 0) { throw 'RISK_ENGINE_INVALID_STOP_DISTANCE' }

$riskBudget = $Capital * ($RiskPercent / 100)
$positionNotional = $riskBudget / ($StopDistancePct / 100)

if ($Signal -eq 'NO_SIGNAL' -or $Signal -eq 'NEUTRAL') {
  $positionNotional = 0
}

Write-Host ("Risk Budget: {0:N2}" -f $riskBudget)
Write-Host ("Max Paper Position Notional: {0:N2}" -f $positionNotional)
Write-Host 'Live orders: DISABLED'
Write-Host 'Real capital: NOT USED'
Write-Host 'Risk decision: READY_FOR_PAPER_SIMULATION'
Write-Host 'Verification: PASSED — bounded, non-executing risk calculation'
Write-Host '=== AX AICS RISK ENGINE COMPLETE ==='
