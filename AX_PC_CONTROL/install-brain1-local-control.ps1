$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$root='C:\AX-Runtime';New-Item -ItemType Directory -Path $root -Force|Out-Null

# The Brain1 workers must run inside the interactive desktop session so that
# Vision/desktop evidence is real. This installer is normally executed by the
# GitHub self-hosted runner, which runs as a service account (observed on PC1 as
# NT AUTHORITY\SYSTEM, not the logged-on user), so WindowsIdentity::GetCurrent()
# would resolve to that account: the -AtLogOn trigger would never fire and the
# tasks would never start. Resolve the logged-on user instead and register the
# tasks against that account.
$interactiveUser=(Get-CimInstance Win32_ComputerSystem).UserName
if([string]::IsNullOrWhiteSpace($interactiveUser)){throw 'NO_INTERACTIVE_USER'}
$sid=([System.Security.Principal.NTAccount]$interactiveUser).Translate([System.Security.Principal.SecurityIdentifier]).Value

foreach($n in @('brain1-decision-worker.ps1','brain1-local-control-worker.ps1','brain1-watchdog.ps1')){Copy-Item (Join-Path $PSScriptRoot $n) (Join-Path $root $n) -Force}

# The workers write heartbeats and control proofs under $root. When $root is
# created by the service account the interactive user cannot write there, which
# silently breaks the evidence gate, so grant the account explicit modify rights.
# Best-effort: a failure here is recorded in the proof rather than aborting the
# install, because the task registration below is the primary contract.
$aclGranted=$true;$aclError=$null
try{
$acl=Get-Acl $root
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($sid,'Modify','ContainerInherit,ObjectInherit','None','Allow')))
Set-Acl -Path $root -AclObject $acl
}catch{$aclGranted=$false;$aclError=$_.Exception.Message}

$installed=@()
function Add-Hidden($name,$script){
$arg='-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$script+'"'
$a=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$t=New-ScheduledTaskTrigger -AtLogOn -User $interactiveUser
# RestartInterval is serialised into the task XML as an ISO-8601 duration and
# Task Scheduler rejects anything below PT1M with 0x80041318, so a 5-second
# restart is not expressible here.
$s=New-ScheduledTaskSettingsSet -Hidden -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$p=New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $name -Action $a -Trigger $t -Settings $s -Principal $p -Force|Out-Null
Start-ScheduledTask -TaskName $name
$script:installed+=$name
}

# A false INSTALLED proof is worse than a loud failure: the evidence gate treats
# a written proof file as progress. Record the real outcome on every exit path.
$proof=@{protocol='AX PC1 BRAIN1 INSTALL v3';nodeId='PC1';computerName=$env:COMPUTERNAME;interactiveUser=$interactiveUser;principalSid=$sid;aclGranted=$aclGranted;status='PENDING';installedAt=[DateTime]::UtcNow.ToString('o')}
if(-not $aclGranted){$proof.aclError=$aclError}
try{
Add-Hidden 'AERIS-PC1-BRAIN1-DECISION' (Join-Path $root 'brain1-decision-worker.ps1')
Add-Hidden 'AERIS-PC1-BRAIN1-LOCAL-CONTROL' (Join-Path $root 'brain1-local-control-worker.ps1')
Add-Hidden 'AERIS-PC1-BRAIN1-WATCHDOG' (Join-Path $root 'brain1-watchdog.ps1')
$proof.status='INSTALLED'
}catch{
$proof.status='FAILED'
$proof.error=$_.Exception.Message
$proof.installedTasks=$installed
# An access denial here is a host privilege problem, not a script defect: the
# runner service account cannot register a task owned by the interactive user.
if($_.Exception.Message -match 'Access is denied|0x80070005'){
$proof.hostAction='Run the self-hosted runner as the interactive user, or grant the runner account the right to register scheduled tasks for that user.'
}
$proof|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'brain1-install-proof.json') -Encoding UTF8
throw
}
$proof.installedTasks=$installed
$proof|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'brain1-install-proof.json') -Encoding UTF8
