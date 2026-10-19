# PC1 remote access status: what can reach this machine right now, and what is
# missing.
#
# The question this answers is "can K control PC1 from a phone, and if not, what
# has to be installed". It reports the facts and the required next step. It
# never installs anything and never reads a credential: the MeshCentral login
# key and password stay where they are, and only their presence is reported.
#
# Two remote paths exist and they are independent:
#
#   Runner path  - GitHub Actions reaches PC1 through the outbound runner
#                  service. Good for running scripts, useless for looking at
#                  the screen. Requires nothing inbound.
#   MeshCentral  - an outbound agent connection to a MeshCentral server, which
#                  gives browser remote desktop, terminal and file transfer.
#                  This is the path that works from a phone, and it needs no
#                  port forward because the agent dials out.
#
# If MeshCentral is configured here, the phone instructions are printed. If it
# is not, the report says what has to happen, because "install a MeshCentral
# server and agent" is a decision for the owner, not something to do silently.

param(
  [string]$RuntimeRoot = 'C:\AX-Runtime'
)

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME" }

$evidenceDir = Join-Path $RuntimeRoot 'evidence'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null

function Get-MatchingService {
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

# --- Runner path ---------------------------------------------------------
$runnerServices = Get-MatchingService -NamePatterns @('actions.runner.*') -DisplayPatterns @('*GitHub Actions*')
$runnerProcs = @(Get-Process -Name 'Runner.Listener', 'Runner.Worker' -ErrorAction SilentlyContinue)
$runnerReady = (($runnerServices | Where-Object { $_.State -eq 'Running' }).Count -gt 0) -or ($runnerProcs.Count -gt 0)

# --- MeshCentral path ----------------------------------------------------
# Names vary between agent builds, so match loosely on both name and display
# name rather than trusting one fixed string.
$meshServices = Get-MatchingService `
  -NamePatterns @('Mesh Agent*', 'MeshCentralAgent*', 'MeshCentral Agent*', 'meshagent*') `
  -DisplayPatterns @('*Mesh Agent*', '*MeshCentral*Agent*')
$meshProcs = @(Get-Process -Name 'meshagent' -ErrorAction SilentlyContinue)

# The agent stores its server URL and mesh id in its own state file. Read the
# presence of the file and, when present, only the server host - never a token,
# certificate or key.
$meshAgentExe = $null
foreach ($candidate in @(
    'C:\Program Files\Mesh Agent\MeshAgent.exe',
    'C:\Program Files (x86)\Mesh Agent\MeshAgent.exe',
    'C:\Program Files\MeshCentral Agent\MeshAgent.exe'
  )) {
  if (Test-Path -LiteralPath $candidate) { $meshAgentExe = $candidate; break }
}
if (-not $meshAgentExe) {
  $found = @(Get-ChildItem -Path 'C:\Program Files', 'C:\Program Files (x86)' -Recurse -Filter 'MeshAgent.exe' -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($found.Count -gt 0) { $meshAgentExe = $found[0].FullName }
}

$meshAgentVersion = $null
$meshServerHost = $null
$meshStateFile = $null
if ($meshAgentExe) {
  $meshAgentVersion = (Get-Item -LiteralPath $meshAgentExe).VersionInfo.ProductVersion
  foreach ($statePath in @(
      'C:\Program Files\Mesh Agent\MeshAgent.msh',
      'C:\Program Files (x86)\Mesh Agent\MeshAgent.msh'
    )) {
    if (Test-Path -LiteralPath $statePath) {
      $meshStateFile = $statePath
      foreach ($line in (Get-Content -LiteralPath $statePath -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*MeshServer\s*=\s*(\S+)') { $meshServerHost = $Matches[1] }
      }
      break
    }
  }
}

# The adapter's own configuration: presence only, never the values.
$adapterConfig = [ordered]@{
  meshctrlJsPresent = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('AKATH_MESHCTRL_JS'))
  urlPresent        = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('AKATH_MESHCTRL_URL'))
  userPresent       = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('AKATH_MESHCTRL_LOGINUSER'))
  keyFilePresent    = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('AKATH_MESHCTRL_KEYFILE'))
  passwordPresent   = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('AKATH_MESHCTRL_LOGINPASS'))
}
$adapterReady = ($adapterConfig.meshctrlJsPresent -and $adapterConfig.urlPresent -and
                 $adapterConfig.userPresent -and ($adapterConfig.keyFilePresent -or $adapterConfig.passwordPresent))

# The MeshCentral adapter is driven from the AX control host, not from PC1, so
# its configuration living on PC1 would be unusual. Report it either way.
$meshReady = (($meshServices | Where-Object { $_.State -eq 'Running' }).Count -gt 0) -or ($meshProcs.Count -gt 0)

$interactiveUser = (Get-CimInstance Win32_ComputerSystem).UserName
$interactive = -not [string]::IsNullOrWhiteSpace($interactiveUser)

# --- What has to happen next --------------------------------------------
$nextSteps = New-Object System.Collections.Generic.List[string]
if (-not $runnerReady) {
  $nextSteps.Add('RUNNER DOWN: start the actions.runner.* service on PC1, or run install-pc1-keepalive.ps1 once from an elevated shell so it stays up on its own.')
}
if (-not $meshReady -and -not $meshAgentExe) {
  $nextSteps.Add('NO REMOTE DESKTOP: no MeshCentral agent is installed, so there is no phone path to this screen. Install a MeshCentral agent on PC1, pointed at a MeshCentral server, then remote desktop works from a phone browser with no port forward.')
} elseif (-not $meshReady) {
  $nextSteps.Add('MESH AGENT STOPPED: the agent is installed but not running, so PC1 is invisible to MeshCentral. Start it, and let the keepalive task keep it started.')
}
if (-not $adapterReady) {
  $nextSteps.Add('ADAPTER UNCONFIGURED: the AX MeshCentral adapter on the control host has no AKATH_MESHCTRL_* environment, so AX cannot dispatch through MeshCentral. Set them on the control host, not in Git.')
}
if (-not $interactive) {
  $nextSteps.Add('NO INTERACTIVE SESSION: nobody is logged on at the console, so a screenshot would show the lock screen. Log in at PC1, or enable autologon, before expecting a usable desktop capture.')
}

$status = if ($runnerReady -and $meshReady) { 'FULL' }
          elseif ($runnerReady -or $meshReady) { 'PARTIAL' }
          else { 'UNREACHABLE' }

$report = [ordered]@{
  schemaVersion     = 1
  capturedAt        = (Get-Date).ToUniversalTime().ToString('o')
  hostname          = $env:COMPUTERNAME
  status            = $status
  interactiveUser   = $interactiveUser
  interactiveSession = $interactive
  runnerPath        = [ordered]@{
    ready     = $runnerReady
    services  = @($runnerServices | ForEach-Object { [ordered]@{ name = $_.Name; state = $_.State; startMode = $_.StartMode } })
    processes = @($runnerProcs | ForEach-Object { $_.Id })
  }
  meshCentralPath   = [ordered]@{
    ready         = $meshReady
    agentExe      = $meshAgentExe
    agentVersion  = $meshAgentVersion
    stateFile     = $meshStateFile
    serverHost    = $meshServerHost
    services      = @($meshServices | ForEach-Object { [ordered]@{ name = $_.Name; state = $_.State; startMode = $_.StartMode } })
    processes     = @($meshProcs | ForEach-Object { $_.Id })
  }
  adapterConfig     = $adapterConfig
  nextSteps         = @($nextSteps)
}

Set-Content -LiteralPath (Join-Path $evidenceDir 'pc1-remote-access-status.json') `
  -Value ($report | ConvertTo-Json -Depth 8) -Encoding UTF8

$runnerSummary = (@($runnerServices | ForEach-Object { $_.Name + ':' + $_.State }) -join ',')
$meshSummary = (@($meshServices | ForEach-Object { $_.Name + ':' + $_.State }) -join ',')

Write-Host "STATUS=$status"
Write-Host "RUNNER_READY=$runnerReady"
Write-Host "MESH_READY=$meshReady"
Write-Host "MESH_AGENT_EXE=$meshAgentExe"
Write-Host "MESH_SERVER_HOST=$meshServerHost"
Write-Host "INTERACTIVE_SESSION=$interactive USER=$interactiveUser"
Write-Host "RUNNER_SERVICES=$runnerSummary"
Write-Host "MESH_SERVICES=$meshSummary"
Write-Host 'NEXT_STEPS:'
foreach ($s in $nextSteps) { Write-Host " - $s" }
Write-Host 'REMOTE_ACCESS_STATUS=COMPLETE'
