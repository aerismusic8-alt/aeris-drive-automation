[CmdletBinding()]
param(
  [string]$StateDir = $(if ($env:AKATH_STATE_DIR) { $env:AKATH_STATE_DIR } else { Join-Path $HOME '.akath/runtime' }),
  [switch]$ProbeMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
$statePath = Join-Path $StateDir 'runtime-state.json'
$lockPath = Join-Path $StateDir 'runtime.lock'
$runtimeId = if ($env:AKATH_RUNTIME_ID) { $env:AKATH_RUNTIME_ID } else { 'akath-primary' }
$runId = [guid]::NewGuid().ToString()
$started = [DateTime]::UtcNow
$ownsLock = $false

function Write-State {
  param(
    [string]$State,
    [string]$JobId,
    [string]$VerificationStatus,
    [string]$EvidenceRef,
    [string]$ErrorClass,
    [string]$NextAction,
    [int]$Attempt
  )
  $record = [ordered]@{
    runtime_id = $runtimeId
    state = $State
    run_id = $runId
    job_id = $JobId
    heartbeat_at = [DateTime]::UtcNow.ToString('o')
    lease_owner = $runtimeId
    attempt = $Attempt
    verification_status = $VerificationStatus
    evidence_ref = $EvidenceRef
    error_class = $ErrorClass
    next_action = $NextAction
  }
  $record | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -Path $statePath
}

function Write-Evidence {
  param([hashtable]$Data)
  $evidencePath = Join-Path $StateDir ("evidence-$runId.json")
  $Data | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $evidencePath
  return $evidencePath
}

$lock = $null
try {
  try {
    $lock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $ownsLock = $true
  } catch {
    Write-Output 'AKATH_RUNTIME=WAITING'
    Write-Output 'AKATH_REASON=LOCK_HELD'
    exit 0
  }

  Write-State 'RUNNING' '' 'UNVERIFIED' '' '' 'select authoritative next job' 1

  # Probe mode deliberately avoids financial/public side effects. It proves
  # autonomous wake-up, persistence, verification, and continuation semantics.
  if ($ProbeMode -or $env:AKATH_PROBE_MODE -eq 'true') {
    $jobId = "AKATH-PROBE-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))"
    $evidence = Write-Evidence @{
      runtime_id = $runtimeId
      run_id = $runId
      job_id = $jobId
      started_at = $started.ToString('o')
      completed_at = [DateTime]::UtcNow.ToString('o')
      probe = $true
      side_effects = 'none'
      verification_status = 'VERIFIED'
      next_job_ready = $true
    }
    Write-State 'VERIFIED' $jobId 'VERIFIED' $evidence '' 'wake for next job' 1
    Write-Output 'AKATH_RUNTIME=VERIFIED'
    Write-Output "AKATH_RUN_ID=$runId"
    Write-Output "AKATH_JOB_ID=$jobId"
    Write-Output "AKATH_EVIDENCE=$evidence"
    exit 0
  }

  # Production integration is intentionally fail-closed until an authoritative
  # queue adapter is configured. Never invent a successful execution result.
  Write-State 'BLOCKED' '' 'UNVERIFIED' '' 'SOURCE_STATE_UNAVAILABLE' 'configure authoritative queue adapter' 1
  Write-Output 'AKATH_RUNTIME=BLOCKED'
  Write-Output 'AKATH_REASON=SOURCE_STATE_UNAVAILABLE'
  exit 2
}
catch {
  $message = $_.Exception.GetType().Name
  Write-State 'FAILED' '' 'FAILED' '' $message 'diagnose and retry on next wake-up' 1
  Write-Output 'AKATH_RUNTIME=FAILED'
  Write-Output "AKATH_ERROR_CLASS=$message"
  exit 1
}
finally {
  if ($lock) { $lock.Dispose() }
  if ($ownsLock) {
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
  }
}
