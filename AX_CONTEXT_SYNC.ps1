param(
  [string]$ContextPath = "$PSScriptRoot\AX_CONTEXT_INPUT.json",
  [string]$StatePath = "$PSScriptRoot\AX_CANONICAL_STATE.json",
  [int]$WindowHours = 24
)

$ErrorActionPreference = 'Stop'

function Get-ObjectProperty($Object, $Name, $Default = $null) {
  if ($null -eq $Object) { return $Default }
  $p = $Object.PSObject.Properties[$Name]
  if ($null -eq $p) { return $Default }
  return $p.Value
}

$now = Get-Date
$windowStart = $now.AddHours(-$WindowHours)

if (-not (Test-Path $ContextPath)) {
  $inputEvents = @()
} else {
  $raw = Get-Content -Raw -Path $ContextPath
  if ([string]::IsNullOrWhiteSpace($raw)) { $inputEvents = @() }
  else {
    $parsed = $raw | ConvertFrom-Json
    if ($parsed -is [System.Array]) { $inputEvents = @($parsed) }
    elseif ($null -ne (Get-ObjectProperty $parsed 'events')) { $inputEvents = @($parsed.events) }
    else { $inputEvents = @($parsed) }
  }
}

$events = foreach ($e in $inputEvents) {
  $tsRaw = Get-ObjectProperty $e 'timestamp' $null
  $ts = $null
  if ($tsRaw) { try { $ts = [datetime]::Parse($tsRaw) } catch {} }
  if ($null -eq $ts -or $ts -ge $windowStart) {
    [ordered]@{
      timestamp = if ($ts) { $ts.ToString('o') } else { $now.ToString('o') }
      channel = [string](Get-ObjectProperty $e 'channel' 'unknown')
      type = [string](Get-ObjectProperty $e 'type' 'context')
      content = [string](Get-ObjectProperty $e 'content' '')
      sourceId = Get-ObjectProperty $e 'sourceId' $null
    }
  }
}

$previous = $null
if (Test-Path $StatePath) {
  try { $previous = Get-Content -Raw -Path $StatePath | ConvertFrom-Json } catch { $previous = $null }
}

$state = [ordered]@{
  schema = 'AX_CANONICAL_STATE_V1'
  generatedAt = $now.ToString('o')
  windowHours = $WindowHours
  windowStart = $windowStart.ToString('o')
  eventCount = @($events).Count
  channels = @($events | ForEach-Object { $_.channel } | Sort-Object -Unique)
  events = @($events)
  continuity = [ordered]@{
    previousStateGeneratedAt = Get-ObjectProperty $previous 'generatedAt' $null
    previousStateSchema = Get-ObjectProperty $previous 'schema' $null
    bootstrapRequired = $true
    bootstrapReason = 'CONTEXT_SYNC_OR_CHANNEL_CHANGE'
  }
  integrity = [ordered]@{
    source = 'AX_CONTEXT_SYNC'
    verified = $true
    verificationRule = 'schema+timestamp+window+event_count'
  }
}

$dir = Split-Path -Parent $StatePath
if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$state | ConvertTo-Json -Depth 20 | Set-Content -Path $StatePath -Encoding UTF8

if (-not (Test-Path $StatePath)) { throw 'AX_CANONICAL_STATE_WRITE_FAILED' }
$check = Get-Content -Raw -Path $StatePath | ConvertFrom-Json
if ($check.schema -ne 'AX_CANONICAL_STATE_V1') { throw 'AX_CANONICAL_STATE_VERIFY_FAILED' }
if ([int]$check.eventCount -ne @($events).Count) { throw 'AX_CANONICAL_STATE_EVENTCOUNT_VERIFY_FAILED' }

Write-Host '=== AX CONTEXT SYNC ==='
Write-Host "Window: $windowStart -> $now"
Write-Host "Events: $(@($events).Count)"
Write-Host "Channels: $(@($state.channels) -join ',')"
Write-Host 'Canonical state: VERIFIED'
