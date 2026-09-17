$ErrorActionPreference = 'Stop'
$RuntimeDir = $PSScriptRoot
$bot = Join-Path $RuntimeDir 'pc2-first-bot-v2.ps1'
$taskName = 'AERIS-AKATH-PC2-JUMTASK-BOT'

if (-not (Test-Path $bot)) { throw 'PC2_JUMTASK_BOT_MISSING' }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$bot`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description 'AERIS PC2 JUMTASK 24/7 production bot. K explicitly controls shutdown.' -Force | Out-Null
Write-Host "[PC2_INSTALL] $taskName registered"
Write-Host "[PC2_INSTALL] bot=$bot"
Write-Host '[PC2_INSTALL] restart-on-failure=ON'
Write-Host '[PC2_INSTALL] execution-limit=NONE'
Write-Host '[PC2_INSTALL] mode=24/7'
