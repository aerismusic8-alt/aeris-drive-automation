# AX PC Permission Bootstrap
# Run on PC1/PC2 from an elevated PowerShell.
# Purpose: prepare the AERIS AX execution workspace for the authorized automation runtime.
# This intentionally does NOT disable Defender, UAC, or Firewall, and does not expose WinRM broadly.

$ErrorActionPreference = 'Stop'
$Root = 'C:\AERIS\AX'
$LogDir = Join-Path $Root 'logs'
$LogFile = Join-Path $LogDir 'permission-bootstrap.log'
New-Item -ItemType Directory -Force -Path $Root, "$Root\workspace", "$Root\scripts", $LogDir, "$Root\state" | Out-Null

function Write-Log([string]$Message) {
  "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Message" | Tee-Object -FilePath $LogFile -Append
}

Write-Log "START computer=$env:COMPUTERNAME user=$env:USERDOMAIN\\$env:USERNAME"

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Log 'FAIL administrator elevation required'
  throw 'Run this script from an elevated PowerShell (Run as Administrator).'
}
Write-Log 'OK administrator elevation verified'

# Permit local/current-user automation scripts without changing machine policy.
if ((Get-ExecutionPolicy -Scope CurrentUser) -eq 'Restricted') {
  Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
  Write-Log 'CHANGED CurrentUser execution policy to RemoteSigned'
}

$git = Get-Command git -ErrorAction SilentlyContinue
$gh = Get-Command gh -ErrorAction SilentlyContinue
Write-Log ('Git=' + $(if ($git) {'FOUND'} else {'NOT_FOUND'}))
Write-Log ('GitHubCLI=' + $(if ($gh) {'FOUND'} else {'NOT_FOUND'}))

# Grant the current interactive account full control over the AX workspace only.
& icacls $Root /grant "$env:USERDOMAIN\$env:USERNAME:(OI)(CI)F" /T /C | Out-Null
Write-Log 'OK AX workspace ACL applied to current account'

$winrm = Get-Service WinRM -ErrorAction SilentlyContinue
$manifest = [ordered]@{
  computer = $env:COMPUTERNAME
  user = "$env:USERDOMAIN\$env:USERNAME"
  elevated = $true
  timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
  powershell = $PSVersionTable.PSVersion.ToString()
  git = if ($git) {$git.Source} else {$null}
  githubCli = if ($gh) {$gh.Source} else {$null}
  axRoot = $Root
  winrmStatus = if ($winrm) {$winrm.Status.ToString()} else {$null}
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Root 'ax-capability-manifest.json') -Encoding UTF8

$checks = @(
  (Test-Path $Root),
  (Test-Path "$Root\workspace"),
  (Test-Path "$Root\scripts"),
  (Test-Path "$Root\logs"),
  (Test-Path "$Root\state"),
  (Test-Path (Join-Path $Root 'ax-capability-manifest.json'))
)
if ($checks -contains $false) {
  Write-Log 'FAIL verification'
  exit 1
}
Write-Log 'SUCCESS AX local execution workspace ready'
Write-Log 'END'
exit 0
