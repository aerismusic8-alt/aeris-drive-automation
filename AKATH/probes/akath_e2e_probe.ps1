[CmdletBinding()]
param(
  [string]$StateDir = $(if ($env:AKATH_STATE_DIR) { $env:AKATH_STATE_DIR } else { Join-Path $HOME '.akath/runtime' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot/../runtime/akath_worker.ps1" -StateDir $StateDir -ProbeMode
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$state = Get-Content -Raw -LiteralPath (Join-Path $StateDir 'runtime-state.json') | ConvertFrom-Json
if ($state.state -ne 'VERIFIED') { throw "PROBE_NOT_VERIFIED:$($state.state)" }
if ($state.verification_status -ne 'VERIFIED') { throw 'PROBE_VERIFICATION_FAILED' }
if ([string]::IsNullOrWhiteSpace($state.evidence_ref)) { throw 'PROBE_EVIDENCE_MISSING' }
Write-Output "probe_run_id=$($state.run_id)"
Write-Output "job_id=$($state.job_id)"
Write-Output "verification_status=$($state.verification_status)"
Write-Output 'next_job_ready=true'
