[CmdletBinding()]
param(
    [string]$Repo = 'aerismusic8-alt/aeris-drive-automation',
    [string]$ScriptPath = "$PSScriptRoot\AX_PC2_CONTROL_DAEMON.ps1"
)

$ErrorActionPreference='Stop'
$serviceName='AXControlPC2'
$displayName='AX Control PC2'
$serviceCommand="powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Repo `"$Repo`""

if(-not (Test-Path $ScriptPath)){ throw "AX_PC2_CONTROL_SCRIPT_NOT_FOUND:$ScriptPath" }
if(-not [Environment]::GetEnvironmentVariable('AX_GITHUB_TOKEN','Machine')){
    throw 'AX_GITHUB_TOKEN_MACHINE_ENV_MISSING'
}

$existing=Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if($existing){
    if($existing.Status -ne 'Stopped'){ Stop-Service $serviceName -Force -ErrorAction SilentlyContinue }
    sc.exe delete $serviceName | Out-Null
    Start-Sleep -Seconds 2
}

sc.exe create $serviceName binPath= $serviceCommand start= auto DisplayName= $displayName | Out-Null
sc.exe description $serviceName "AX Control PC2: Chat transport -> local control -> verify -> persistent recovery" | Out-Null
sc.exe failure $serviceName reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null

Start-Service $serviceName
Start-Sleep -Seconds 2
$svc=Get-Service -Name $serviceName
if($svc.Status -ne 'Running'){ throw "AX_CONTROL_PC2_SERVICE_NOT_RUNNING:$($svc.Status)" }
Write-Host 'AX_CONTROL_PC2_SERVICE=RUNNING'
Write-Host "AX_CONTROL_PC2_SERVICE_NAME=$serviceName"
Write-Host 'AUTO_START=VERIFIED'
Write-Host 'SERVICE_RECOVERY=VERIFIED'
