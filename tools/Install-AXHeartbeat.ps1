$ErrorActionPreference = 'Stop'
$taskName = 'AX-Heartbeat'
$agentDir = 'C:\AX\Runtime'
$agentPath = Join-Path $agentDir 'AX-Heartbeat.ps1'
New-Item -ItemType Directory -Force -Path $agentDir | Out-Null

$agent = @'
$ErrorActionPreference = 'Continue'
$log = 'C:\AX\Runtime\heartbeat.log'
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Add-Content $log "[$timestamp] AX heartbeat started"

# The heartbeat is intentionally a local trigger/health signal.
# External execution must remain behind the configured AX permission gates.
try {
  Add-Content $log "[$timestamp] AX heartbeat tick"
} catch {
  Add-Content $log "[$timestamp] HEARTBEAT_ERROR $($_.Exception.Message)"
}
'@

Set-Content -Path $agentPath -Value $agent -Encoding UTF8

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$agentPath`""
$triggerBoot = New-ScheduledTaskTrigger -AtStartup
$triggerMinute = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration ([TimeSpan]::MaxValue)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($triggerBoot,$triggerMinute) -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Host "AX heartbeat installed and started: $taskName"
Get-ScheduledTask -TaskName $taskName | Select-Object TaskName,State
