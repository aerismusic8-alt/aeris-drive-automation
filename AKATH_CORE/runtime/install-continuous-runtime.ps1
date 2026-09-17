$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$launcher = Join-Path $PSScriptRoot 'start-bot.ps1'
$taskName = 'AERIS-AKATH-CONTINUOUS-RUNTIME'

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description 'AERIS AKATH continuous runtime. K explicitly controls shutdown.' -Force | Out-Null
Write-Host "[AX_INSTALL] $taskName registered"
Write-Host "[AX_INSTALL] launcher=$launcher"
Write-Host '[AX_INSTALL] runtime will restart after process failure/logon; it does not self-stop after completing jobs.'
