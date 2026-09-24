param([string]$SourceRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-M9M4818'){throw "PC2_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$install='C:\AX-PC2'
$runtime='C:\AX-Runtime'
New-Item -ItemType Directory -Path $install -Force|Out-Null
New-Item -ItemType Directory -Path $runtime -Force|Out-Null
$files=@(
 'AX_PC_CONTROL\brain2-decision-worker.ps1',
 'AX_PC_CONTROL\brain2-local-control-worker.ps1',
 'AX_PC_CONTROL\PC2_SSH_BRAIN2_ENTRY.ps1'
)
foreach($f in $files){
 $src=Join-Path $SourceRoot $f
 if(-not(Test-Path $src)){throw "SOURCE_MISSING:$src"}
 Copy-Item $src (Join-Path $install (Split-Path $f -Leaf)) -Force
}
$task='AERIS-PC2-BRAIN2-DECISION'
$arg='-NoProfile -ExecutionPolicy Bypass -File "' + $install + '\brain2-decision-worker.ps1"'
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$trigger=New-ScheduledTaskTrigger -AtStartup
$principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force|Out-Null
Start-ScheduledTask -TaskName $task
Start-Sleep 2
$state=Get-ScheduledTask -TaskName $task
if($state.State -eq 'Disabled'){throw 'BRAIN2_TASK_DISABLED'}
Write-Host 'BRAIN2_INSTALL=VERIFIED'
Write-Host "BRAIN2_TASK=$task"
Write-Host "BRAIN2_INSTALL_ROOT=$install"
