$ErrorActionPreference = 'Stop'
$RuntimeDir = $PSScriptRoot
$bot = Join-Path $RuntimeDir 'pc2-revenue-farm-bot.ps1'
$taskName = 'AERIS-AKATH-PC2-REVENUE-FARM'

if (-not (Test-Path $bot)) { throw 'PC2_REVENUE_BOT_MISSING' }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$bot`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

Write-Host "PC2_REVENUE_FARM_INSTALLED task=$taskName bot=$bot"
