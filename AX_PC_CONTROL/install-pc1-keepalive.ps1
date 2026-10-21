# Install the PC1 keepalive as a scheduled task.
#
# Run this once, on PC1, from an elevated PowerShell. After that the keepalive
# repairs the runner and MeshCentral agent services on its own, so a stopped
# service no longer needs someone to walk to the machine.
#
#   powershell -ExecutionPolicy Bypass -File install-pc1-keepalive.ps1
#
# The task runs at startup and repeats, and it runs as SYSTEM so that
# Start-Service is allowed. It is not tied to a logged-on user, because the
# whole point is to recover a machine whose user session may be gone.

param(
  [string]$TaskName = 'AERIS-PC1-KEEPALIVE',
  [string]$RuntimeRoot = 'C:\AX-Runtime'
)

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME" }

$principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'ELEVATION_REQUIRED: re-run this from an elevated PowerShell'
}

# Prefer the deployed copy under the runtime root, and fall back to the copy
# sitting next to this installer, so the task does not depend on a path that
# may be cleaned up later.
$runtimeDir = Join-Path $RuntimeRoot 'bin'
New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
$target = Join-Path $runtimeDir 'pc1-keepalive.ps1'
$source = Join-Path $PSScriptRoot 'pc1-keepalive.ps1'
if (!(Test-Path -LiteralPath $source)) { throw "KEEPALIVE_SCRIPT_MISSING:$source" }
Copy-Item -LiteralPath $source -Destination $target -Force
Write-Host "DEPLOYED=$target"

$arg = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $target + '"'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg

# AtStartup covers a reboot; the repetition covers a service that dies while
# the machine stays up, which is the case that caused the outage.
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = 'PT1M'

$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -RestartCount 999 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit ([TimeSpan]::Zero)

# RunLevel Highest with the SYSTEM account: the task has to start services, and
# SYSTEM does not need a stored password, so this survives a password change.
$taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $taskPrincipal -Force | Out-Null
Write-Host "TASK_REGISTERED=$TaskName"

Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 8

$info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
Write-Host "TASK_STATE=$((Get-ScheduledTask -TaskName $TaskName).State)"
Write-Host "LAST_RUN=$($info.LastRunTime) RESULT=$($info.LastTaskResult)"

$heartbeat = Join-Path $RuntimeRoot 'evidence\pc1-keepalive-heartbeat.json'
if (Test-Path -LiteralPath $heartbeat) {
  $h = Get-Content -LiteralPath $heartbeat -Raw | ConvertFrom-Json
  Write-Host "RUNNER_SERVICES=$(@($h.runnerServices).Count)"
  Write-Host "MESH_SERVICES=$(@($h.meshServices).Count)"
  Write-Host "MESH_PROCS=$(@($h.meshProcesses).Count)"
  Write-Host "ACTIONS=$(@($h.actions) -join ',')"
  Write-Host 'KEEPALIVE=INSTALLED'
} else {
  throw "KEEPALIVE_HEARTBEAT_MISSING:$heartbeat"
}
