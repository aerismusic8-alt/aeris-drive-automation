param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-M9M4818'){throw "PC2_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$install='C:\AX-PC2';$runtime='C:\AX-Runtime'
New-Item -ItemType Directory -Path $install -Force|Out-Null
New-Item -ItemType Directory -Path (Join-Path $runtime 'evidence') -Force|Out-Null
Copy-Item (Join-Path $SourceRoot 'AX_PC_CONTROL\brain2-watchdog.ps1') (Join-Path $install 'brain2-watchdog.ps1') -Force
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "'+$install+'\brain2-watchdog.ps1"')
$trigger=New-ScheduledTaskTrigger -AtStartup
$principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName 'AERIS-PC2-BRAIN2-WATCHDOG' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force|Out-Null
Start-ScheduledTask -TaskName 'AERIS-PC2-BRAIN2-WATCHDOG'
Start-Sleep 2
$t=Get-ScheduledTask -TaskName 'AERIS-PC2-BRAIN2-WATCHDOG' -ErrorAction Stop
if($t.State -eq 'Disabled'){throw 'WATCHDOG_TASK_DISABLED'}
Write-Host "BRAIN2_WATCHDOG=$($t.State)"
