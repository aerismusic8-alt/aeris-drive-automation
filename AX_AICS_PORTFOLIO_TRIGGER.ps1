param(
  [Parameter(Mandatory=$true)]
  [string]$CommandJson
)

$ErrorActionPreference = 'Stop'

$TASK_ID = 'AICS-LIVE-TRADING'
$ALLOWED_SOURCE = 'AX'
$ALLOWED_ACTIONS = @('OPEN','CLOSE')
$ALLOWED_MODES = @('SIMULATION','LIVE')
$MAX_CLOCK_SKEW_SECONDS = 300
$LIVE_LOCK_REASON = 'LIVE_FINANCIAL_EXECUTION_REQUIRES_EXPLICIT_K_UNLOCK'

function Fail-Trigger {
  param(
    [int]$Code,
    [string]$Message
  )
  Write-Output $Message
  exit $Code
}

function Get-CanonicalCommand {
  param([Parameter(Mandatory=$true)]$Command)
  return @(
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
}

function Get-HmacHex {
  param(
    [Parameter(Mandatory=$true)][string]$Canonical,
    [Parameter(Mandatory=$true)][string]$Secret
  )
  $hmac = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($Secret))
  try {
    return ([Convert]::ToHexString($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($Canonical)))).ToLowerInvariant()
  } finally {
    $hmac.Dispose()
  }
}

function Get-StatePath {
  $override = [Environment]::GetEnvironmentVariable('AX_PORTFOLIO_STATE_PATH')
  if (-not [string]::IsNullOrWhiteSpace($override)) { return $override }
  return (Join-Path $PSScriptRoot 'AX_AICS_PORTFOLIO_STATE.json')
}

function Read-State {
  $path = Get-StatePath
  if (-not (Test-Path -LiteralPath $path)) {
    return [pscustomobject]@{
      schema = 'AX_AICS_PORTFOLIO_STATE_V1'
      task_id = $TASK_ID
      positions = @()
      commands = @()
    }
  }
  $raw = Get-Content -Raw -LiteralPath $path
  if ([string]::IsNullOrWhiteSpace($raw)) { throw 'PORTFOLIO_STATE_EMPTY' }
  $state = $raw | ConvertFrom-Json
  if ($state.schema -ne 'AX_AICS_PORTFOLIO_STATE_V1') { throw 'PORTFOLIO_STATE_SCHEMA_INVALID' }
  if ([string]$state.task_id -ne $TASK_ID) { throw 'PORTFOLIO_STATE_TASK_ID_INVALID' }
  return $state
}

function Write-State {
  param([Parameter(Mandatory=$true)]$State)
  $path = Get-StatePath
  $dir = Split-Path -Parent $path
  if (-not [string]::IsNullOrWhiteSpace($dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $tmp = "$path.tmp"
  $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmp -Encoding utf8
  Move-Item -LiteralPath $tmp -Destination $path -Force
}

if ([string]::IsNullOrWhiteSpace($env:AX_PORTFOLIO_TRIGGER_SECRET)) {
  Fail-Trigger 30 'AX_TRIGGER_SECRET_MISSING'
}

try {
  $command = $CommandJson | ConvertFrom-Json
} catch {
  Fail-Trigger 31 'AX_COMMAND_JSON_INVALID'
}

foreach ($field in @('task_id','command_id','source','issued_at','action','symbol','volume','strategy_version','mode','signature')) {
  if ($null -eq $command.PSObject.Properties[$field]) { Fail-Trigger 32 "AX_COMMAND_FIELD_MISSING:$field" }
}

if ([string]$command.task_id -ne $TASK_ID) { Fail-Trigger 33 "AX_TASK_REJECTED:$($command.task_id)" }
if ([string]$command.source -ne $ALLOWED_SOURCE) { Fail-Trigger 20 'AX_SOURCE_ONLY_REJECTED' }
if ([string]$command.action -notin $ALLOWED_ACTIONS) { Fail-Trigger 34 "AX_ACTION_REJECTED:$($command.action)" }
if ([string]$command.mode -notin $ALLOWED_MODES) { Fail-Trigger 35 "AX_MODE_REJECTED:$($command.mode)" }
if ([string]$command.symbol -notmatch '^[A-Z0-9._-]{1,24}$') { Fail-Trigger 36 'AX_SYMBOL_REJECTED' }

$volume = 0.0
if (-not [double]::TryParse([string]$command.volume, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$volume)) { Fail-Trigger 37 'AX_VOLUME_INVALID' }
if ($volume -le 0 -or $volume -gt 1000) { Fail-Trigger 37 'AX_VOLUME_OUT_OF_RANGE' }

$issuedAt = 0L
if (-not [Int64]::TryParse([string]$command.issued_at, [ref]$issuedAt)) { Fail-Trigger 38 'AX_ISSUED_AT_INVALID' }
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if ([Math]::Abs($now - $issuedAt) -gt $MAX_CLOCK_SKEW_SECONDS) { Fail-Trigger 39 'AX_COMMAND_EXPIRED_OR_FUTURE' }

$canonical = Get-CanonicalCommand -Command $command
$expectedSignature = Get-HmacHex -Canonical $canonical -Secret $env:AX_PORTFOLIO_TRIGGER_SECRET
if (-not [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals(
    [Text.Encoding]::UTF8.GetBytes([string]$command.signature),
    [Text.Encoding]::UTF8.GetBytes($expectedSignature))) {
  Fail-Trigger 21 'AX_SIGNATURE_REJECTED'
}

if ([string]$command.mode -eq 'LIVE') {
  Write-Output "LIVE_EXECUTION_LOCKED:$LIVE_LOCK_REASON"
  exit 40
}

$state = Read-State
$commands = @($state.commands)
$positions = @($state.positions)
$existingCommand = $commands | Where-Object { [string]$_.command_id -eq [string]$command.command_id } | Select-Object -First 1
if ($null -ne $existingCommand) {
  Write-Output "IDEMPOTENT_REPLAY command_id=$($command.command_id) result=$($existingCommand.result)"
  exit 0
}

switch ([string]$command.action) {
  'OPEN' {
    $existingPosition = $positions | Where-Object { [string]$_.position_id -eq [string]$command.position_id -and [string]$_.status -eq 'OPEN' } | Select-Object -First 1
    if ($null -ne $existingPosition) { Fail-Trigger 41 "POSITION_ALREADY_OPEN:$($command.position_id)" }
    if ([string]::IsNullOrWhiteSpace([string]$command.position_id)) { Fail-Trigger 42 'AX_POSITION_ID_REQUIRED_FOR_OPEN' }

    $positions += [pscustomobject]@{
      position_id = [string]$command.position_id
      symbol = [string]$command.symbol
      volume = $volume
      strategy_version = [string]$command.strategy_version
      status = 'OPEN'
      opened_at = $now
      closed_at = $null
    }
    $result = 'ORDER_OPEN_SIMULATED'
  }
  'CLOSE' {
    if ([string]::IsNullOrWhiteSpace([string]$command.position_id)) { Fail-Trigger 43 'AX_POSITION_ID_REQUIRED_FOR_CLOSE' }
    $position = $positions | Where-Object { [string]$_.position_id -eq [string]$command.position_id -and [string]$_.status -eq 'OPEN' } | Select-Object -First 1
    if ($null -eq $position) { Fail-Trigger 44 "OPEN_POSITION_NOT_FOUND:$($command.position_id)" }
    $position.status = 'CLOSED'
    $position.closed_at = $now
    $result = 'ORDER_CLOSE_SIMULATED'
  }
}

$commands += [pscustomobject]@{
  command_id = [string]$command.command_id
  action = [string]$command.action
  source = [string]$command.source
  mode = [string]$command.mode
  position_id = [string]$command.position_id
  strategy_version = [string]$command.strategy_version
  accepted_at = $now
  result = $result
}
$state.positions = $positions
$state.commands = $commands
$state.updated_at = $now
Write-State -State $state

Write-Output "$result task_id=$TASK_ID command_id=$($command.command_id) position_id=$($command.position_id)"
Write-Output 'AX_TRIGGER_SOURCE=AX_ONLY'
Write-Output 'AX_TRIGGER_VERIFICATION=PASS'
exit 0
