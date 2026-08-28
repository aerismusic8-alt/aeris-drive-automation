param(
  [Parameter(Mandatory=$true)][string]$Command,
  [string]$WorkingDirectory = $PSScriptRoot,
  [int]$MaxAttempts = 3,
  [int]$TimeoutSec = 60
)

$ErrorActionPreference = 'Stop'
Set-Location $WorkingDirectory

function Invoke-AxAttempt {
  param([string]$AttemptCommand)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $AttemptCommand 2>&1 | Out-String
    $code = $LASTEXITCODE
    $sw.Stop()
    [pscustomobject]@{ Success=($code -eq 0); ExitCode=$code; Output=$output.Trim(); ElapsedMs=$sw.ElapsedMilliseconds }
  } catch {
    $sw.Stop()
    [pscustomobject]@{ Success=$false; ExitCode=1; Output=$_.Exception.Message; ElapsedMs=$sw.ElapsedMilliseconds }
  }
}

Write-Host '=== AX SELF-HEALING EXECUTOR ==='
Write-Host "Command: $Command"
Write-Host "MaxAttempts: $MaxAttempts"

$attempt = 0
$history = @()
while ($attempt -lt $MaxAttempts) {
  $attempt++
  Write-Host "=== ATTEMPT $attempt/$MaxAttempts ==="
  $result = Invoke-AxAttempt -AttemptCommand $Command
  $history += $result
  Write-Host "ExitCode: $($result.ExitCode)"
  Write-Host "ElapsedMs: $($result.ElapsedMs)"
  if ($result.Output) { $result.Output | Write-Host }
  if ($result.Success) {
    Write-Host 'SELF_HEALING_RESULT=PASS'
    exit 0
  }

  if ($attempt -lt $MaxAttempts) {
    Write-Host 'RESULT=FAIL; retrying same controlled action'
    Start-Sleep -Seconds 1
  }
}

Write-Host 'SELF_HEALING_RESULT=BLOCKED'
Write-Host "Attempts=$attempt"
Write-Host 'Reason=All controlled attempts failed; no destructive fallback was performed.'
exit 1
