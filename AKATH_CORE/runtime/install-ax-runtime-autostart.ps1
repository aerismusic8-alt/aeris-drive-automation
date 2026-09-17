param(
  [ValidateSet('PC1-MAIN','PC2-MAIN')]
  [string]$NodeId = 'PC1-MAIN',
  [switch]$StartNow
)
$ErrorActionPreference = 'Stop'
$RuntimeDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Start = Join-Path $RuntimeDir 'start-ax-runtime.ps1'
if (-not (Test-Path $Start)) { throw "AX runtime launcher not found: $Start" }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js is required.' }
$specialist = if ($NodeId -eq 'PC2-MAIN') { 'pc2-specialist.mjs' } else { 'pc1-specialist.mjs' }
$control = if ($NodeId -eq 'PC2-MAIN') { 'pc2-specialist.mjs' } else { 'pc1-specialist-control.mjs' }
$TaskName = "AERIS-AKATH-AX-RUNTIME-$NodeId"
$ps = (Get-Command powershell.exe).Source
$q = [char]34
$args = '-NoProfile -ExecutionPolicy Bypass -File ' + $q + $Start + $q + ' -NodeId ' + $q + $NodeId + $q + ' -Specialist ' + $q + $specialist + $q + ' -ControlSpecialist ' + $q + $control + $q
$action = New-ScheduledTaskAction -Execute $ps -Argument $args
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "AERIS AKATH AX continuous runtime for $NodeId" -Force | Out-Null
Write-Output "[AX_AUTOSTART] INSTALLED task=$TaskName node=$NodeId"
if ($StartNow) { Start-ScheduledTask -TaskName $TaskName; Write-Output "[AX_AUTOSTART] STARTED task=$TaskName" }