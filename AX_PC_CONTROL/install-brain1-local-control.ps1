$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$root='C:\AX-Runtime';New-Item -ItemType Directory -Path $root -Force|Out-Null
foreach($n in @('brain1-decision-worker.ps1','brain1-local-control-worker.ps1','brain1-watchdog.ps1')){Copy-Item (Join-Path $PSScriptRoot $n) (Join-Path $root $n) -Force}
function Add-Hidden($name,$script){
$arg='-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$script+'"'
$a=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$t=New-ScheduledTaskTrigger -AtLogOn
$s=New-ScheduledTaskSettingsSet -Hidden -RestartCount 999 -RestartInterval (New-TimeSpan -Seconds 5)
$sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$p=New-ScheduledTaskPrincipal -UserId $sid -LogonType InteractiveToken -RunLevel Limited
Register-ScheduledTask -TaskName $name -Action $a -Trigger $t -Settings $s -Principal $p -Force|Out-Null
Start-ScheduledTask -TaskName $name
}
Add-Hidden 'AERIS-PC1-BRAIN1-DECISION' (Join-Path $root 'brain1-decision-worker.ps1')
Add-Hidden 'AERIS-PC1-BRAIN1-LOCAL-CONTROL' (Join-Path $root 'brain1-local-control-worker.ps1')
Add-Hidden 'AERIS-PC1-BRAIN1-WATCHDOG' (Join-Path $root 'brain1-watchdog.ps1')
@{protocol='AX PC1 BRAIN1 INSTALL v2';nodeId='PC1';computerName=$env:COMPUTERNAME;status='INSTALLED';principalSid=$sid;installedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root 'brain1-install-proof.json') -Encoding UTF8
