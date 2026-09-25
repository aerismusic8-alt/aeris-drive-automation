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
$intentRoot=Join-Path $runtime 'brain2-intent-queue'
$commandRoot=Join-Path $runtime 'brain2-command-queue'
foreach($root in @($intentRoot,$commandRoot)){
 foreach($d in @('pending','running','done','failed')){
  New-Item -ItemType Directory -Path (Join-Path $root $d) -Force|Out-Null
 }
}
# SSH User must be able to submit intents; SYSTEM owns Brain2/Control2 execution.
$acl=Get-Acl $intentRoot
$rule=New-Object System.Security.AccessControl.FileSystemAccessRule('User','Modify','ContainerInherit,ObjectInherit','None','Allow')
$acl.SetAccessRule($rule)
Set-Acl -Path $intentRoot -AclObject $acl
$controlTask='AERIS-PC2-BRAIN2-LOCAL-CONTROL'
$task='AERIS-PC2-BRAIN2-DECISION'
$trigger=New-ScheduledTaskTrigger -AtStartup
$principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
$controlArg='-NoProfile -ExecutionPolicy Bypass -File "' + $install + '\brain2-local-control-worker.ps1"'
$controlAction=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $controlArg
Register-ScheduledTask -TaskName $controlTask -Action $controlAction -Trigger $trigger -Principal $principal -Settings $settings -Force|Out-Null
$arg='-NoProfile -ExecutionPolicy Bypass -File "' + $install + '\brain2-decision-worker.ps1"'
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force|Out-Null
Start-ScheduledTask -TaskName $controlTask
Start-ScheduledTask -TaskName $task
Start-Sleep 3
foreach($name in @($controlTask,$task)){
 $state=Get-ScheduledTask -TaskName $name
 if($state.State -eq 'Disabled'){throw "TASK_DISABLED:$name"}
 Write-Host "BRAIN2_TASK=$name STATE=$($state.State)"
}
Write-Host 'BRAIN2_INSTALL=VERIFIED'
Write-Host "BRAIN2_INSTALL_ROOT=$install"
