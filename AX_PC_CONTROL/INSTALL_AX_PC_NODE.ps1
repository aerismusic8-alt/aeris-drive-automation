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

$serviceName="AX-PC-NODE-$Node"
$existing=Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if($existing){Stop-Service $serviceName -Force -ErrorAction SilentlyContinue; sc.exe delete $serviceName | Out-Null; Start-Sleep -Seconds 2}

$binPath='powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$root+'\AX_PC_NODE.ps1" -ConfigPath "'+$root+'\AX_PC_NODE_CONFIG.json"'
sc.exe create $serviceName binPath= $binPath start= auto DisplayName= "AX PC Node $Node" | Out-Null
sc.exe failure $serviceName reset= 86400 actions= restart/5000/restart/15000/restart/30000 | Out-Null
Start-Service $serviceName

Write-Output "AX_PC_NODE_INSTALLED|$Node|$nodeId|SERVICE=$serviceName"
Get-Service -Name $serviceName | Select-Object Name,Status,StartType
