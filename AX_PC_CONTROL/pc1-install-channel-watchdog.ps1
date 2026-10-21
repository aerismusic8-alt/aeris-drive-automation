# Register the reverse-channel watchdog as a scheduled task.
#
# The worker is restarted by its own task settings when it crashes. That covers a
# process that dies. It does not cover a process that is alive but no longer
# polling, which is what happened on 2026-10-21: jobs were dequeued and never
# answered while the task still read Running. The watchdog is the thing that
# notices, by reading the heartbeat the worker writes each cycle.
#
# The task is registered Hidden and with -WindowStyle Hidden, so it adds nothing
# to the desktop. It restarts on failure like the worker task does, because a
# watchdog that stops watching is worse than none: everything looks fine.
#
#   powershell -ExecutionPolicy Bypass -File pc1-install-channel-watchdog.ps1
#   powershell -ExecutionPolicy Bypass -File pc1-install-channel-watchdog.ps1 -Uninstall

param(
  [string]$RuntimeRoot = 'C:\AX-Runtime',
  [int]$HealthySeconds = 180,
  [int]$MarginSeconds = 60,
  [int]$PollSeconds = 30,
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME" }

$taskName = 'AERIS-PC1-CHANNEL-WATCHDOG'
$reverseDir = Join-Path $RuntimeRoot 'reverse'
$watchdog = Join-Path $reverseDir 'pc1-reverse-channel-watchdog.ps1'

if ($Uninstall) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "UNINSTALLED=$taskName"
  exit 0
}

if (-not (Test-Path -LiteralPath $watchdog)) {
  throw "WATCHDOG_MISSING:$watchdog (deploy it with ax-push-script.py first)"
}

# The watchdog refuses to run off PC1 and needs the reverse dir to exist.
New-Item -ItemType Directory -Path $reverseDir -Force | Out-Null

# Prove it runs and its decision table holds before registering anything. A task
# that is registered but throws on every start is the failure mode this whole
# file exists to prevent, so it is not repeated here.
$check = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $watchdog -SelfTest 2>&1 | Out-String
Write-Host $check
if ($check -notmatch 'SELFTEST_RESULT=PASS') { throw 'WATCHDOG_SELFTEST_FAILED' }

$argLine = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden " +
  "-File `"$watchdog`" -HealthySeconds $HealthySeconds -MarginSeconds $MarginSeconds -PollSeconds $PollSeconds"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argLine
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$sid = ([System.Security.Principal.NTAccount]$env:USERNAME).Translate(
  [System.Security.Principal.SecurityIdentifier]).Value
$principal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit ([TimeSpan]::Zero) -Hidden

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
  -Principal $principal -Settings $settings `
  -Description 'Watches the reverse-channel heartbeat and restarts the worker when it stops polling.' | Out-Null
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 8

$info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
$state = (Get-ScheduledTask -TaskName $taskName).State
Write-Host "WATCHDOG_TASK=$taskName STATE=$state LAST_RESULT=$($info.LastTaskResult)"

$hbPath = Join-Path (Join-Path $RuntimeRoot 'evidence') 'reverse-control-watchdog-heartbeat.json'
if (Test-Path -LiteralPath $hbPath) {
  Write-Host "WATCHDOG_HEARTBEAT=$(Get-Content -LiteralPath $hbPath -Raw)"
} else {
  Write-Host 'WATCHDOG_HEARTBEAT=missing (first poll has not written yet)'
}
