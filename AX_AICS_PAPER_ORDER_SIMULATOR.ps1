param(
  [string]$Symbol = 'BTC-USD',
  [ValidateSet('MOMENTUM_UP','MOMENTUM_DOWN','NEUTRAL','NO_SIGNAL')]
  [string]$Signal = 'NO_SIGNAL',
  [double]$EntryPrice = 0,
  [double]$PositionNotional = 0,
  [double]$StopDistancePct = 2.0
)
$ErrorActionPreference = 'Stop'
Write-Host '=== AX AICS PAPER ORDER SIMULATOR ==='
Write-Host 'Mode: PAPER_ONLY'
Write-Host "Symbol: $Symbol"
Write-Host "Signal: $Signal"

if ($EntryPrice -le 0) { throw 'PAPER_ORDER_INVALID_ENTRY_PRICE' }
if ($PositionNotional -lt 0) { throw 'PAPER_ORDER_INVALID_NOTIONAL' }
if ($StopDistancePct -le 0) { throw 'PAPER_ORDER_INVALID_STOP_DISTANCE' }

$action = 'HOLD'
if ($Signal -eq 'MOMENTUM_UP' -and $PositionNotional -gt 0) { $action = 'PAPER_BUY' }
elseif ($Signal -eq 'MOMENTUM_DOWN' -and $PositionNotional -gt 0) { $action = 'PAPER_SELL' }

$quantity = 0
if ($PositionNotional -gt 0) { $quantity = $PositionNotional / $EntryPrice }
$stopPrice = $EntryPrice
if ($action -eq 'PAPER_BUY') { $stopPrice = $EntryPrice * (1 - $StopDistancePct / 100) }
elseif ($action -eq 'PAPER_SELL') { $stopPrice = $EntryPrice * (1 + $StopDistancePct / 100) }

$orderId = "PAPER-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff'))"
Write-Host "Paper Order ID: $orderId"
Write-Host "Action: $action"
Write-Host ("Entry Price: {0:N8}" -f $EntryPrice)
Write-Host ("Quantity: {0:N8}" -f $quantity)
Write-Host ("Stop Price: {0:N8}" -f $stopPrice)
Write-Host 'Broker/Exchange order: DISABLED'
Write-Host 'Real capital: NOT USED'
Write-Host 'Verification: PASSED — simulated order only'
Write-Host '=== AX AICS PAPER ORDER SIMULATOR COMPLETE ==='
