[CmdletBinding()]
param(
  [string]$StateDir = $(if ($env:AKATH_STATE_DIR) { $env:AKATH_STATE_DIR } else { Join-Path $HOME '.akath/runtime' }),
  [int]$StaleSeconds = 900
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$statePath = Join-Path $StateDir 'runtime-state.json'

if (-not (Test-Path -LiteralPath $statePath)) {
  Write-Output 'AKATH_WATCHDOG=BLOCKED'
  Write-Output 'AKATH_REASON=SOURCE_STATE_UNAVAILABLE'
  exit 2
}

$state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
$now = [DateTime]::UtcNow
$heartbeat = [DateTime]::Parse($state.heartbeat_at).ToUniversalTime()
$age = ($now - $heartbeat).TotalSeconds

if ($state.state -eq 'VERIFIED') {
  Write-Output 'AKATH_WATCHDOG=HEALTHY'
  Write-Output 'AKATH_REASON=VERIFIED_STATE'
  exit 0
}

if (($state.state -eq 'RUNNING' -or $state.state -eq 'RECOVERING') -and $age -gt $StaleSeconds) {
  $recovery = [ordered]@{
    runtime_id = $state.runtime_id
    run_id = $state.run_id
    previous_state = $state.state
    detected_at = $now.ToString('o')
    heartbeat_age_seconds = [math]::Round($age, 1)
    recovery_status = 'RECOVERING'
  }
  $evidence = Join-Path $StateDir ("recovery-$($state.run_id).json")
  $recovery | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -Path $evidence
  $state.state = 'RECOVERING'
  $state.verification_status = 'UNVERIFIED'
  $state.evidence_ref = $evidence
  $state.error_class = 'STALE_HEARTBEAT'
  $state.next_action = 'retry on next autonomous wake-up'
  $state.heartbeat_at = $now.ToString('o')
  $state | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -Path $statePath
  Write-Output 'AKATH_WATCHDOG=RECOVERING'
  Write-Output 'AKATH_REASON=STALE_HEARTBEAT'
  exit 1
}

Write-Output 'AKATH_WATCHDOG=HEALTHY'
Write-Output 'AKATH_HEARTBEAT_AGE_SECONDS=$([math]::Round($age,1))'
exit 0
