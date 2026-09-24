$ErrorActionPreference='Stop'
$root='C:\AX-Runtime'
New-Item -ItemType Directory -Path $root -Force|Out-Null
$script=Join-Path $root 'brain2-local-control-worker.ps1'
Copy-Item (Join-Path $PSScriptRoot 'brain2-local-control-worker.ps1') $script -Force
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
$trigger=New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName 'AERIS-PC2-BRAIN2-LOCAL-CONTROL' -Action $action -Trigger $trigger -RunLevel Highest -Force|Out-Null
Start-ScheduledTask -TaskName 'AERIS-PC2-BRAIN2-LOCAL-CONTROL'
Write-Host 'BRAIN2_LOCAL_CONTROL=STARTED'