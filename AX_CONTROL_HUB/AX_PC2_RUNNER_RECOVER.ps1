# AX PC2 Runner Recovery
# Purpose: recover a stopped GitHub Actions self-hosted runner service on PC2.
# Safe behavior: only targets Windows services whose names start with actions.runner.
# Does not install, re-register, or replace runner credentials.

$ErrorActionPreference = 'Stop'

Write-Host '=== AX PC2 RUNNER RECOVERY ==='
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "User:     $env:USERNAME"

$services = @(Get-Service | Where-Object { $_.Name -like 'actions.runner.*' })

if ($services.Count -eq 0) {
    Write-Host 'NO_ACTIONS_RUNNER_SERVICE_FOUND'
    Write-Host 'Check whether the GitHub Actions runner is installed on this PC.'
    exit 2
}

Write-Host 'Discovered runner services:'
$services | Select-Object Name, Status, StartType | Format-Table -AutoSize

$changed = $false
foreach ($svc in $services) {
    if ($svc.Status -ne 'Running') {
        Write-Host "Starting: $($svc.Name)"
        Start-Service -Name $svc.Name
        $changed = $true
    }
}

Start-Sleep -Seconds 3
$services = @(Get-Service | Where-Object { $_.Name -like 'actions.runner.*' })

Write-Host 'Post-recovery state:'
$services | Select-Object Name, Status, StartType | Format-Table -AutoSize

$notRunning = @($services | Where-Object { $_.Status -ne 'Running' })
if ($notRunning.Count -gt 0) {
    Write-Host 'RUNNER_RECOVERY_FAILED'
    exit 1
}

if ($changed) {
    Write-Host 'RUNNER_RECOVERY_STARTED'
} else {
    Write-Host 'RUNNER_ALREADY_RUNNING'
}

Write-Host '=== AX PC2 RUNNER RECOVERY COMPLETE ==='
exit 0
