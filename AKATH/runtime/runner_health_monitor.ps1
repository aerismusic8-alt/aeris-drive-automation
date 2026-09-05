[CmdletBinding()]
param(
  [string]$Repository = 'aerismusic8-alt/aeris-drive-automation',
  [string]$StatePath = $(if ($env:AKATH_RUNNER_HEALTH_STATE) { $env:AKATH_RUNNER_HEALTH_STATE } else { Join-Path $HOME '.akath/runner-health.json' }),
  [switch]$Once
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HeartbeatSeconds = 60
$DegradedSeconds = 120
$OfflineSeconds = 300
$FailoverSeconds = 60
$PollSeconds = 60

function Ensure-StateDirectory([string]$Path) {
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
}

function Read-State([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return [ordered]@{ nodes = @{}; updated_at = $null }
  }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -AsHashtable
}

function Save-State($State, [string]$Path) {
  Ensure-StateDirectory $Path
  $State.updated_at = [DateTime]::UtcNow.ToString('o')
  $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-RunnerSnapshot {
  if ([string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    throw 'GITHUB_TOKEN_REQUIRED_FOR_RUNNER_HEALTH'
  }
  $headers = @{ Authorization = "Bearer $env:GITHUB_TOKEN"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
  $uri = "https://api.github.com/repos/$Repository/actions/runners?per_page=100"
  $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 15
  return @($response.runners)
}

function Get-NodeState([datetime]$Now, $Runner, $Previous) {
  $busy = [bool]$Runner.busy
  $online = ($Runner.status -eq 'online')
  $lastSeen = if ($Previous.last_seen_at) { [DateTime]::Parse($Previous.last_seen_at).ToUniversalTime() } else { $null }
  $offlineSince = if ($Previous.offline_detected_at) { [DateTime]::Parse($Previous.offline_detected_at).ToUniversalTime() } else { $null }

  if ($online) {
    $lastSeen = $Now
    $offlineSince = $null
    $status = if ($busy) { 'BUSY' } else { 'ONLINE' }
    $failoverReady = $false
  } elseif ($lastSeen) {
    $age = ($Now - $lastSeen).TotalSeconds
    if ($age -lt $DegradedSeconds) { $status = 'DEGRADED' }
    elseif ($age -lt $OfflineSeconds) { $status = 'DEGRADED' }
    else { $status = 'OFFLINE' }
    if (-not $offlineSince) { $offlineSince = $Now }
    $failoverReady = ($status -eq 'OFFLINE' -and (($Now - $offlineSince).TotalSeconds -ge $FailoverSeconds))
  } else {
    $status = 'UNKNOWN'
    $failoverReady = $false
  }

  return [ordered]@{
    id = $Runner.id
    name = $Runner.name
    labels = @($Runner.labels | ForEach-Object { $_.name })
    status = $status
    busy = $busy
    last_seen_at = if ($lastSeen) { $lastSeen.ToString('o') } else { $null }
    offline_detected_at = if ($offlineSince) { $offlineSince.ToString('o') } else { $null }
    failover_ready = $failoverReady
  }
}

function Invoke-HealthCheck {
  $now = [DateTime]::UtcNow
  $state = Read-State $StatePath
  $runners = Get-RunnerSnapshot
  $byName = @{}
  foreach ($runner in $runners) { $byName[$runner.name] = $runner }

  $targets = @{
    PC1 = 'PC1-AUTONOMOUS-EXECUTOR'
    PC2 = 'PC2-CODING-EXECUTOR'
  }

  foreach ($target in $targets.Keys) {
    $runnerName = $targets[$target]
    $previous = if ($state.nodes.ContainsKey($target)) { $state.nodes[$target] } else { @{ last_seen_at = $null; offline_detected_at = $null } }
    if ($byName.ContainsKey($runnerName)) {
      $node = Get-NodeState $now $byName[$runnerName] $previous
    } else {
      $node = [ordered]@{
        id = $null; name = $runnerName; labels = @($runnerName); status = 'UNKNOWN'; busy = $false
        last_seen_at = $previous.last_seen_at; offline_detected_at = $previous.offline_detected_at; failover_ready = $false
      }
    }
    $state.nodes[$target] = $node
  }

  $state.policy = [ordered]@{
    heartbeat_seconds = $HeartbeatSeconds
    degraded_seconds = $DegradedSeconds
    offline_seconds = $OfflineSeconds
    failover_seconds = $FailoverSeconds
  }

  $pc1 = $state.nodes.PC1
  $pc2 = $state.nodes.PC2
  if ($pc1.failover_ready -and $pc2.status -in @('ONLINE','BUSY')) {
    $state.preferred_target = 'PC2'
    $state.failover_action = 'ROUTE_NEW_WORK_TO_PC2'
  } elseif ($pc2.failover_ready -and $pc1.status -in @('ONLINE','BUSY')) {
    $state.preferred_target = 'PC1'
    $state.failover_action = 'ROUTE_NEW_WORK_TO_PC1'
  } else {
    $state.preferred_target = if ($pc1.status -in @('ONLINE','BUSY')) { 'PC1' } elseif ($pc2.status -in @('ONLINE','BUSY')) { 'PC2' } else { $null }
    $state.failover_action = 'NONE'
  }

  Save-State $state $StatePath
  $state | ConvertTo-Json -Depth 10
}

while ($true) {
  try {
    Invoke-HealthCheck | Write-Output
  } catch {
    Write-Error $_
  }
  if ($Once) { break }
  Start-Sleep -Seconds $PollSeconds
}
