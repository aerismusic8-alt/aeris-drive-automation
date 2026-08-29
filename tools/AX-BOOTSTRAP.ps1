$ErrorActionPreference = 'Stop'
$serviceName = 'actions.runner.aerismusic8-alt-aeris-drive-automation.DESKTOP-RGK6JKB'
$repo = 'aerismusic8-alt/aeris-drive-automation'

Write-Host '=== AX EXECUTION BRIDGE BOOTSTRAP ===' -ForegroundColor Cyan
Write-Host "Repository: $repo"
Write-Host "Runner service: $serviceName"

$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host 'Runner service not found on this PC.' -ForegroundColor Yellow
    Write-Host 'The runner must be installed/configured on this PC before unattended AX execution can work.' -ForegroundColor Yellow
    exit 2
}

if ($svc.Status -ne 'Running') {
    Write-Host 'Starting self-hosted runner service...'
    Start-Service -Name $serviceName
    Start-Sleep -Seconds 3
    $svc = Get-Service -Name $serviceName
}

if ($svc.Status -ne 'Running') {
    throw 'Runner service could not be started.'
}

Write-Host 'Runner service: RUNNING' -ForegroundColor Green

$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($git) { Write-Host "Git: $($git.Source)" } else { Write-Host 'Git: NOT FOUND' -ForegroundColor Yellow }

$runnerRoot = 'C:\actions-runner'
if (Test-Path $runnerRoot) {
    Write-Host "Runner root: $runnerRoot" -ForegroundColor Green
} else {
    Write-Host "Runner root not found at $runnerRoot; service exists, so continuing." -ForegroundColor Yellow
}

$evidence = [ordered]@{
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
    computer = $env:COMPUTERNAME
    repository = $repo
    runnerService = $serviceName
    runnerStatus = $svc.Status.ToString()
    runnerOnlinePrerequisite = ($svc.Status -eq 'Running')
}

$evidenceDir = Join-Path $PSScriptRoot '..\evidence'
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$evidencePath = Join-Path $evidenceDir 'AX-EXECUTION-BRIDGE-BOOTSTRAP.json'
$evidence | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $evidencePath

Write-Host "Evidence: $evidencePath" -ForegroundColor Green
Write-Host 'BOOTSTRAP PASS: self-hosted runner service is running.' -ForegroundColor Green
Write-Host 'AX can dispatch only through workflows/queues already configured for this runner.' -ForegroundColor Cyan
exit 0
