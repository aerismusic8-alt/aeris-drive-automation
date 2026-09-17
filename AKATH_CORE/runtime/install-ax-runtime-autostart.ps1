param(
  [switch]$StartNow
)

$ErrorActionPreference = 'Stop'
$RuntimeDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Main = Join-Path $RuntimeDir 'main.mjs'
$Bootstrap = Join-Path $RuntimeDir 'run-ax-runtime-with-user-env.ps1'
$TaskName = 'AERIS-AKATH-AX-RUNTIME'

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw 'Node.js is required on PC1.'
}
if (-not (Test-Path $Main)) {
  throw "AX Runtime entrypoint not found: $Main"
}
if (-not (Test-Path $Bootstrap)) {
  throw "AX Runtime environment bootstrap not found: $Bootstrap"
}

$powershellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
$userId = "$env:USERDOMAIN\$env:USERNAME"

[Environment]::SetEnvironmentVariable('AX_PC1_NODE_ID', 'PC1-MAIN', 'User')
[Environment]::SetEnvironmentVariable('AX_RUNTIME_INTERVAL_MS', '5000', 'User')
[Environment]::SetEnvironmentVariable('AX_CANONICAL_SYNC_INTERVAL_MS', '15000', 'User')

$action = New-ScheduledTaskAction `
  -Execute $powershellPath `
  -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $Bootstrap) `
  -WorkingDirectory $RuntimeDir

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$principal = New-ScheduledTaskPrincipal `
  -UserId $userId `
  -LogonType Interactive `
  -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
  -StartWhenAvailable `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -RestartCount 999 `
  -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $action `
  -Trigger $trigger `
  -Principal $principal `
  -Settings $settings `
  -Description 'AERIS/AKATH AX autonomous PC1 execution runtime. Starts at user logon and restarts on failure.' `
  -Force | Out-Null

Write-Output "AX Runtime autostart registered: $TaskName"
Write-Output "Runtime: $Main"
Write-Output "Bootstrap: $Bootstrap"
Write-Output "User: $userId"

if ($StartNow) {
  Start-ScheduledTask -TaskName $TaskName
  Write-Output 'AX Runtime start requested now.'
}

Write-Output 'One-time bootstrap complete. Future user logons will start AX Runtime automatically.'
