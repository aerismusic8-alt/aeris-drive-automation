[CmdletBinding()]
param(
  [string]$StateDir = $(if ($env:AKATH_STATE_DIR) { $env:AKATH_STATE_DIR } else { Join-Path $HOME '.akath/runtime' }),
  [switch]$ProbeMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Adapter = Join-Path $PSScriptRoot 'ax_rehydration_adapter.py'
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
  $record | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $statePath
}

function Write-Evidence {
  param([hashtable]$Data)
  $evidencePath = Join-Path $StateDir ("evidence-$runId.json")
  $Data | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -Path $evidencePath
  return $evidencePath
}

function Invoke-Rehydration {
  if (-not (Test-Path -LiteralPath $Adapter)) { throw 'REHYDRATION_ADAPTER_MISSING' }
  $pythonExe = $env:AKATH_PORTABLE_PYTHON
  if ([string]::IsNullOrWhiteSpace($pythonExe) -or -not (Test-Path -LiteralPath $pythonExe)) {
    $pythonExe = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
  }
  if ([string]::IsNullOrWhiteSpace($pythonExe) -or -not (Test-Path -LiteralPath $pythonExe)) { throw 'PYTHON_RUNTIME_NOT_FOUND' }
  $output = & $pythonExe $Adapter rehydrate 2>&1
  if ($LASTEXITCODE -ne 0) {
    $text = ($output -join "`n").Trim()
    if ($text) {
      try { return ($text | ConvertFrom-Json) } catch { throw "REHYDRATION_FAILED:$text" }
    }
    throw 'REHYDRATION_FAILED'
  }
  $text = ($output -join "`n").Trim()
  if (-not $text) { throw 'REHYDRATION_EMPTY_RESULT' }
  $result = $text | ConvertFrom-Json
  if ($result.rehydration_status -ne 'VERIFIED') { throw 'REHYDRATION_NOT_VERIFIED' }
  return $result
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

  Write-State 'RUNNING' '' 'UNVERIFIED' '' '' 'rehydrate authoritative A MASTER BRAIN' 1
  $rehydration = Invoke-Rehydration

  # Probe mode remains side-effect free. Production mode now proves that the
  # runtime can reconstruct A from the authoritative Brain before any cycle.
  $jobId = if ($ProbeMode -or $env:AKATH_PROBE_MODE -eq 'true') {
    "AKATH-PROBE-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))"
  } else {
    "AKATH-REHYDRATION-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))"
  }

  $evidence = Write-Evidence @{
    runtime_id = $runtimeId
    run_id = $runId
    job_id = $jobId
    started_at = $started.ToString('o')
    completed_at = [DateTime]::UtcNow.ToString('o')
    probe = [bool]($ProbeMode -or $env:AKATH_PROBE_MODE -eq 'true')
    side_effects = 'none'
    verification_status = 'VERIFIED'
    rehydration = $rehydration
    next_job_ready = $true
  }

  Write-State 'VERIFIED' $jobId 'VERIFIED' $evidence '' 'A context reconstructed; select authoritative next job' 1
  Write-Output 'AKATH_RUNTIME=VERIFIED'
  Write-Output "AKATH_RUN_ID=$runId"
  Write-Output "AKATH_JOB_ID=$jobId"
  Write-Output "AKATH_EVIDENCE=$evidence"
  Write-Output 'AKATH_REHYDRATION=VERIFIED'
  exit 0
}
catch {
  $message = $_.Exception.Message
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
