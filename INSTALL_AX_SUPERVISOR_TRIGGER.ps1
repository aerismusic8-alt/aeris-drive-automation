param(
  [int]$IntervalMinutes = 1,
  [string]$TaskName = 'AERIS AX Supervisor Trigger'
)

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'AX_SUPERVISOR_TRIGGER.ps1'
if (-not (Test-Path $scriptPath)) {
  throw "SUPERVISOR_SCRIPT_NOT_FOUND: $scriptPath"
}

if ($IntervalMinutes -lt 1) {
  throw 'INTERVAL_MUST_BE_AT_LEAST_1_MINUTE'
}

$action = New-ScheduledTaskAction `
  -Execute 'powershell.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger `
  -Once `
  -At (Get-Date).AddMinutes(1) `
  -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
  -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet `
  -StartWhenAvailable `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 4) `
  -MultipleInstances IgnoreNew

Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $action `
  -Trigger $trigger `
  -Settings $settings `
  -Description 'AERIS AX autonomous supervisor heartbeat. One-shot supervisor cycle; no nested trigger creation.' `
  -Force | Out-Null

Write-Host '=== AX SUPERVISOR TRIGGER INSTALLED ==='
Write-Host "Task: $TaskName"
Write-Host "Interval: $IntervalMinutes minute(s)"
Write-Host "Script: $scriptPath"
Write-Host 'Overlap policy: IGNORE_NEW'
Write-Host 'Next run: approximately 1 minute after installation'
