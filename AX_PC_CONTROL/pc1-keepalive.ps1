# PC1 keepalive: keep the machine reachable without a walk to the desk.
#
# Two services have to stay up for AX to touch PC1 at all:
#
#   1. The GitHub Actions runner service. When it stops, every queued job sits
#      in `queued` with no runner assigned, and nothing on the control side
#      notices. That is what happened on 2026-10-19 and it needed a human at
#      the machine to fix.
#   2. The MeshCentral agent service. That agent is the outbound connection
#      that makes phone remote control possible at all. If it stops, PC1
#      disappears from the MeshCentral console and remote control is gone too,
#      which is the moment the machine becomes unreachable by every path.
#
# This script starts whichever of them is stopped and records what it did. It
# is deliberately non-destructive: a stopped service is started, and a service
# that is not installed at all is reported and left alone. Nothing is deleted,
# reconfigured or reinstalled.
#
# Repair PC1 by hand, once, from the machine itself:
#   powershell -ExecutionPolicy Bypass -File pc1-keepalive.ps1 -Once
#
# Or install it as a scheduled task with install-pc1-keepalive.ps1, after which
# it repairs the machine on its own and this class of outage stops needing a
# person.

param(
  [string]$RuntimeRoot = 'C:\AX-Runtime',
  [int]$PollSeconds = 30,
  [switch]$Once
)

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME" }

$evidenceDir = Join-Path $RuntimeRoot 'evidence'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$heartbeatPath = Join-Path $evidenceDir 'pc1-keepalive-heartbeat.json'
$logPath = Join-Path $evidenceDir 'pc1-keepalive.log'

function Write-Log([string]$Line) {
  $stamp = (Get-Date).ToUniversalTime().ToString('o')
  "$stamp $Line" | Add-Content -LiteralPath $logPath -Encoding UTF8
  Write-Host $Line
}

# Service discovery by pattern, because the runner service name embeds the
# repository slug and the MeshCentral service name varies by agent build.
function Get-AgentService {
  param([string[]]$NamePatterns, [string[]]$DisplayPatterns)
  $found = New-Object System.Collections.Generic.List[object]
  foreach ($s in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
    $hit = $false
    foreach ($p in $NamePatterns) { if ($s.Name -like $p) { $hit = $true } }
    foreach ($p in $DisplayPatterns) { if ($s.DisplayName -like $p) { $hit = $true } }
    if ($hit) { $found.Add($s) }
  }
  return @($found)
}

# Starting a service needs an elevated token. The scheduled task supplies one;
# a plain interactive run may not, so a failure is recorded rather than thrown.
function Invoke-EnsureRunning {
  param($Service, $Actions)
  $name = [string]$Service.Name
  if ($Service.State -eq 'Running') { return }
  try {
    Start-Service -Name $name -ErrorAction Stop
    $Actions.Add("STARTED:${name}")
    Write-Log "STARTED:${name} (was $($Service.State))"
  } catch {
    $Actions.Add("START_FAILED:${name}:$($_.Exception.Message)")
    Write-Log "START_FAILED:${name}:$($_.Exception.Message)"
  }
}

$runnerNamePatterns = @('actions.runner.*')
$runnerDisplayPatterns = @('*GitHub Actions*')
$meshNamePatterns = @('Mesh Agent*', 'MeshCentralAgent*', 'MeshCentral Agent*')
$meshDisplayPatterns = @('*Mesh Agent*', '*MeshCentral*Agent*')

while ($true) {
  $actions = New-Object System.Collections.Generic.List[string]

  $runners = Get-AgentService -NamePatterns $runnerNamePatterns -DisplayPatterns $runnerDisplayPatterns
  if ($runners.Count -eq 0) {
    $actions.Add('RUNNER_SERVICE_MISSING')
    Write-Log 'RUNNER_SERVICE_MISSING: the runner is not installed as a service on this machine'
  } else {
    foreach ($r in $runners) { Invoke-EnsureRunning -Service $r -Actions $actions }
  }

  # The agent may be installed as a service or run interactively as a process,
  # depending on how it was deployed, so both are checked.
  $meshServices = Get-AgentService -NamePatterns $meshNamePatterns -DisplayPatterns $meshDisplayPatterns
  $meshProcesses = @(Get-Process -Name 'meshagent' -ErrorAction SilentlyContinue)
  if ($meshServices.Count -eq 0 -and $meshProcesses.Count -eq 0) {
    $actions.Add('MESH_AGENT_NOT_FOUND')
    Write-Log 'MESH_AGENT_NOT_FOUND: no MeshCentral agent service and no meshagent process'
  } else {
    foreach ($m in $meshServices) { Invoke-EnsureRunning -Service $m -Actions $actions }
  }

  # Re-read the state after repairing, so the heartbeat describes the machine
  # as it is now rather than as it was before the repair.
  $runners = Get-AgentService -NamePatterns $runnerNamePatterns -DisplayPatterns $runnerDisplayPatterns
  $meshServices = Get-AgentService -NamePatterns $meshNamePatterns -DisplayPatterns $meshDisplayPatterns
  $meshProcesses = @(Get-Process -Name 'meshagent' -ErrorAction SilentlyContinue)
  $runnerProcesses = @(Get-Process -Name 'Runner.Listener', 'Runner.Worker' -ErrorAction SilentlyContinue)

  $report = [ordered]@{
    protocol        = 'AX PC1 KEEPALIVE v1'
    nodeId          = 'PC1'
    computerName    = $env:COMPUTERNAME
    status          = 'ALIVE'
    heartbeatAt     = (Get-Date).ToUniversalTime().ToString('o')
    runnerServices  = @($runners | ForEach-Object { [ordered]@{ name = $_.Name; state = $_.State; startMode = $_.StartMode } })
    meshServices    = @($meshServices | ForEach-Object { [ordered]@{ name = $_.Name; state = $_.State; startMode = $_.StartMode } })
    runnerProcesses = @($runnerProcesses | ForEach-Object { $_.Id })
    meshProcesses   = @($meshProcesses | ForEach-Object { $_.Id })
    actions         = @($actions)
  }
  Set-Content -LiteralPath $heartbeatPath -Value ($report | ConvertTo-Json -Depth 6) -Encoding UTF8

  Write-Host "RUNNER_SERVICES=$($runners.Count) MESH_SERVICES=$($meshServices.Count) MESH_PROCS=$($meshProcesses.Count)"
  Write-Host "ACTIONS=$(if ($actions.Count -gt 0) { $actions -join ',' } else { 'none' })"

  if ($Once) {
    Write-Host 'KEEPALIVE=ONCE'
    break
  }
  Start-Sleep -Seconds $PollSeconds
}
