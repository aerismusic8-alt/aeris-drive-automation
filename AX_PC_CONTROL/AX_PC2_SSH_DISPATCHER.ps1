param(
 [Parameter(Mandatory=$true)][ValidateSet('CLOSE_STALE_TERMINALS','NODE_HEALTH_CHECK')][string]$Command,
 [string]$HostName='192.168.1.111',
 [string]$UserName='User',
 [string]$KeyPath="$env:USERPROFILE\.ssh\id_ed25519",
 [string]$JobId="AX-PC2-SSH-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff'))"
)
$ErrorActionPreference='Stop'
if(-not(Test-Path $KeyPath)){throw "SSH_KEY_MISSING:$KeyPath"}
$remote="powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\AX-PC2\PC2_SSH_BRAIN2_ENTRY.ps1 -Command $Command -JobId $JobId"
$args=@('-4','-i',$KeyPath,'-o','IdentitiesOnly=yes','-o','PasswordAuthentication=no','-o','KbdInteractiveAuthentication=no','-o','StrictHostKeyChecking=yes',"$UserName@$HostName",$remote)
$out=& ssh.exe @args 2>&1
if($LASTEXITCODE -ne 0){throw "PC2_SSH_DISPATCH_FAILED"}
if(-not(($out -join " ") -match "BRAIN2_ACCEPTED")){throw "PC2_SSH_ACCEPTANCE_MISSING"}
Write-Output "PC2_SSH_DISPATCH=VERIFIED"
Write-Output "JOB_ID=$JobId"
Write-Output "TARGET=PC2"
