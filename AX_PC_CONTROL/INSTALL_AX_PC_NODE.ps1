[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)] [ValidateSet('PC1','PC2')] [string]$Node,
  [Parameter(Mandatory=$true)] [string]$ControlRuntimeUrl,
  [Parameter(Mandatory=$true)] [string]$TransportSecret,
  [Parameter(Mandatory=$false)] [string]$WorkingDirectory = 'C:\AKATH'
)

$ErrorActionPreference='Stop'
if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'ADMINISTRATOR_REQUIRED'}

$root='C:\AKATH\AX_PC_CONTROL'
New-Item -ItemType Directory -Path $root -Force | Out-Null
Copy-Item -LiteralPath "$PSScriptRoot\AX_PC_NODE.ps1" -Destination "$root\AX_PC_NODE.ps1" -Force

$nodeId = if($Node -eq 'PC1'){'PC1-AUTONOMOUS-EXECUTOR'}else{'PC2-CODING-EXECUTOR'}
$config=@{
  nodeId=$nodeId
  displayName=$Node
  controlRuntimeUrl=$ControlRuntimeUrl
  pollSeconds=10
  requestTimeoutSeconds=120
  allowedCommands=@('health','runner-status','runner-start','runner-stop','runner-restart','service-status','service-start','service-stop','service-restart','task-status','process-status','git-status','terminal-powershell')
  terminal=@{enabled=$true;maxExecutionSeconds=300;maxOutputBytes=65536;workingDirectory=$WorkingDirectory}
} | ConvertTo-Json -Depth 10
Set-Content -LiteralPath "$root\AX_PC_NODE_CONFIG.json" -Value $config -Encoding UTF8

[Environment]::SetEnvironmentVariable('AX_PC_PULL_SECRET',$TransportSecret,'Machine')

$taskName="AX-PC-NODE-$Node"
$oldServiceName=$taskName
$existingService=Get-Service -Name $oldServiceName -ErrorAction SilentlyContinue
if($existingService){
  if($existingService.Status -ne 'Stopped'){Stop-Service $oldServiceName -Force -ErrorAction SilentlyContinue}
  sc.exe delete $oldServiceName | Out-Null
  Start-Sleep -Seconds 2
}

$oldTask=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if($oldTask){Unregister-ScheduledTask -TaskName $taskName -Confirm:$false}

$psExe=(Get-Command powershell.exe -ErrorAction Stop).Source
$arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$root+'\AX_PC_NODE.ps1" -ConfigPath "'+$root+'\AX_PC_NODE_CONFIG.json"'
$action=New-ScheduledTaskAction -Execute $psExe -Argument $arguments -WorkingDirectory $root
$trigger=New-ScheduledTaskTrigger -AtStartup
$principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "AKATH AX PC Node $Node outbound control worker" -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

Start-Sleep -Seconds 2
$taskInfo=Get-ScheduledTaskInfo -TaskName $taskName
Write-Output "AX_PC_NODE_INSTALLED|$Node|$nodeId|TASK=$taskName|STATE=$((Get-ScheduledTask -TaskName $taskName).State)|LAST_RUN=$($taskInfo.LastRunTime)"
