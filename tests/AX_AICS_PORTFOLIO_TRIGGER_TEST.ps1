$ErrorActionPreference = 'Stop'

$trigger = Join-Path $PSScriptRoot '..' 'AX_AICS_PORTFOLIO_TRIGGER.ps1'
if (-not (Test-Path -LiteralPath $trigger)) {
  throw "TRIGGER_SCRIPT_MISSING:$trigger"
}

$env:AX_PORTFOLIO_TRIGGER_SECRET = 'test-secret'

function Get-TestSignature {
  param(
    [hashtable]$Command
  )
  $canonical = @(
    [string]$Command.task_id,
    [string]$Command.command_id,
    [string]$Command.source,
    [string]$Command.issued_at,
    [string]$Command.action,
    [string]$Command.symbol,
    [string]$Command.volume,
    [string]$Command.position_id,
    [string]$Command.strategy_version,
    [string]$Command.mode
  ) -join '|'
  $hmac = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($env:AX_PORTFOLIO_TRIGGER_SECRET))
  try {
    return ([Convert]::ToHexString($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)))).ToLowerInvariant()
  } finally {
    $hmac.Dispose()
  }
}

function Invoke-Trigger {
  param([hashtable]$Command)
  $Command.signature = Get-TestSignature -Command $Command
  $json = $Command | ConvertTo-Json -Compress
  $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $trigger -CommandJson $json 2>&1
  [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($out -join [Environment]::NewLine) }
}

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$task = 'AICS-LIVE-TRADING'

$unauthorized = Invoke-Trigger -Command @{
  task_id=$task; command_id='test-unauthorized'; source='MOBILE'; issued_at=$now; action='OPEN'; symbol='XAUUSD'; volume=0.01; position_id=''; strategy_version='TEST-1'; mode='SIMULATION'
}
if ($unauthorized.ExitCode -eq 0 -or $unauthorized.Output -notmatch 'AX_SOURCE_ONLY_REJECTED') { throw "UNAUTHORIZED_SOURCE_NOT_REJECTED:$($unauthorized.Output)" }

$open = Invoke-Trigger -Command @{
  task_id=$task; command_id='test-open-001'; source='AX'; issued_at=$now; action='OPEN'; symbol='XAUUSD'; volume=0.01; position_id='POS-001'; strategy_version='TEST-1'; mode='SIMULATION'
}
if ($open.ExitCode -ne 0 -or $open.Output -notmatch 'ORDER_OPEN_SIMULATED') { throw "OPEN_SIMULATION_FAILED:$($open.Output)" }

$openReplay = Invoke-Trigger -Command @{
  task_id=$task; command_id='test-open-001'; source='AX'; issued_at=$now; action='OPEN'; symbol='XAUUSD'; volume=0.01; position_id='POS-001'; strategy_version='TEST-1'; mode='SIMULATION'
}
if ($openReplay.ExitCode -ne 0 -or $openReplay.Output -notmatch 'IDEMPOTENT_REPLAY') { throw "OPEN_IDEMPOTENCY_FAILED:$($openReplay.Output)" }

$close = Invoke-Trigger -Command @{
  task_id=$task; command_id='test-close-001'; source='AX'; issued_at=$now; action='CLOSE'; symbol='XAUUSD'; volume=0.01; position_id='POS-001'; strategy_version='TEST-1'; mode='SIMULATION'
}
if ($close.ExitCode -ne 0 -or $close.Output -notmatch 'ORDER_CLOSE_SIMULATED') { throw "CLOSE_SIMULATION_FAILED:$($close.Output)" }

$live = Invoke-Trigger -Command @{
  task_id=$task; command_id='test-live-001'; source='AX'; issued_at=$now; action='OPEN'; symbol='XAUUSD'; volume=0.01; position_id='POS-LIVE'; strategy_version='TEST-1'; mode='LIVE'
}
if ($live.ExitCode -eq 0 -or $live.Output -notmatch 'LIVE_EXECUTION_LOCKED') { throw "LIVE_LOCK_FAILED:$($live.Output)" }

Write-Host 'AX_AICS_PORTFOLIO_TRIGGER_TEST=PASS'
Write-Host 'AX_SOURCE_ONLY=PASS'
Write-Host 'ORDER_OPEN_SIMULATED=PASS'
Write-Host 'ORDER_CLOSE_SIMULATED=PASS'
Write-Host 'IDEMPOTENCY=PASS'
Write-Host 'LIVE_EXECUTION_LOCK=PASS'
