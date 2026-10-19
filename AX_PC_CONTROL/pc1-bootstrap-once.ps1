# One command on PC1 to make it reachable again.
#
# The machine has been unreachable for hours: the Actions runner is stopped, so
# every queued job sits with no runner assigned, and there is no way in. This
# script is the one-time fix, and it deliberately solves the problem at the
# layer that survives: after it runs, Tailscale is a second, independent path
# onto the machine, so the next time the runner stops it is not a dead end.
#
# It does four things, in this order, because each one is useful on its own:
#
#   1. Starts the Actions runner service. This alone unblocks every queued job.
#   2. Installs and starts the winremote MCP server, so an agent can drive the
#      desktop instead of needing a person at the keyboard.
#   3. Enables Tailscale SSH and serves the MCP port over the tailnet. This is
#      the durable path in: it does not depend on the runner at all.
#   4. Writes evidence of what it found and what it changed.
#
# Nothing here is destructive. A service that is already running is left alone.
# Nothing is uninstalled or reconfigured beyond adding the pieces above.
#
# Run as Administrator:
#   powershell -ExecutionPolicy Bypass -File pc1-bootstrap-once.ps1
#
# Two steps may ask a human once: approving the device in Tailscale, and
# enabling HTTPS certificates for the tailnet. The script detects both and
# says what to do rather than hanging.

param(
  [string]$RuntimeRoot = 'C:\AX-Runtime',
  [int]$Port = 8090,
  # Skipped by default. Tailscale already restricts the endpoint to the
  # tailnet, and the MCP server binds loopback, so a bearer token adds little
  # for a single-person tailnet while making the setup need a secret exchange.
  [switch]$WithAuthKey,
  [switch]$SkipTailscale
)

$ErrorActionPreference = 'Stop'

Write-Host '=========================================='
Write-Host ' AX PC1 BOOTSTRAP'
Write-Host '=========================================='

# --- 0. Identity and elevation -------------------------------------------
Write-Host ''
Write-Host 'STEP=IDENTITY'
if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME" }
Write-Host "PC1=VERIFIED COMPUTER=$env:COMPUTERNAME"

$principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
$elevated = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "ELEVATED=$elevated"
if (-not $elevated) {
  Write-Host ''
  Write-Host 'WARNING: not running as Administrator. Starting services will likely fail.'
  Write-Host 'Close this and re-open PowerShell with "Run as administrator".'
  Write-Host ''
}

$evidenceDir = Join-Path $RuntimeRoot 'evidence'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$actions = New-Object System.Collections.Generic.List[string]

# --- 1. Actions runner ----------------------------------------------------
Write-Host ''
Write-Host 'STEP=RUNNER'
$runnerServices = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like 'actions.runner.*' -or $_.DisplayName -like '*GitHub Actions*' })

if ($runnerServices.Count -eq 0) {
  Write-Host 'RUNNER_SERVICE_MISSING'
  Write-Host 'The runner is not installed as a service, so it has to be started by hand'
  Write-Host 'or reinstalled. Look for a "run.cmd" in the runner folder on this machine.'
  $actions.Add('RUNNER_SERVICE_MISSING')
} else {
  foreach ($svc in $runnerServices) {
    Write-Host "RUNNER_SERVICE=$($svc.Name) STATE=$($svc.State) STARTMODE=$($svc.StartMode)"
    if ($svc.State -eq 'Running') { continue }
    try {
      # A disabled service cannot be started at all; make it manual first.
      if ($svc.StartMode -eq 'Disabled') {
        Set-Service -Name $svc.Name -StartupType Manual -ErrorAction Stop
        $actions.Add("RUNNER_STARTMODE_FIXED:$($svc.Name)")
        Write-Host "STARTMODE_FIXED=$($svc.Name)"
      }
      Start-Service -Name $svc.Name -ErrorAction Stop
      $actions.Add("RUNNER_STARTED:$($svc.Name)")
      Write-Host "RUNNER_STARTED=$($svc.Name)"
    } catch {
      $actions.Add("RUNNER_START_FAILED:$($svc.Name):$($_.Exception.Message)")
      Write-Host "RUNNER_START_FAILED=$($svc.Name) ERROR=$($_.Exception.Message)"
    }
  }
}

# --- 2. winremote MCP server ---------------------------------------------
Write-Host ''
Write-Host 'STEP=MCP_SERVER'
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) {
  foreach ($c in @("$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
                   "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
                   'C:\Python312\python.exe', 'C:\Python311\python.exe')) {
    if (Test-Path -LiteralPath $c) { $python = $c; break }
  }
}

if (-not $python) {
  Write-Host 'PYTHON_NOT_FOUND'
  Write-Host 'Install Python 3.10+ (winget install Python.Python.3.12), then re-run this script.'
  $actions.Add('PYTHON_NOT_FOUND')
} else {
  Write-Host "PYTHON=$python"
  & $python -m pip install --quiet --upgrade winremote-mcp 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    $actions.Add("PIP_INSTALL_FAILED:$LASTEXITCODE")
    Write-Host "PIP_INSTALL_FAILED=$LASTEXITCODE"
  } else {
    $pkgVersion = (& $python -c "import winremote;print(getattr(winremote,'__version__','unknown'))").Trim()
    Write-Host "MCP_PACKAGE_VERSION=$pkgVersion"

    $configDir = Join-Path $RuntimeRoot 'winremote'
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    $batPath = Join-Path $configDir 'start-winremote-mcp.cmd'

    # Loopback bind, no auth: the Tailscale layer is the boundary. A token here
    # would be defence in depth against another process on this same machine,
    # which already implies the machine is compromised.
    if ($WithAuthKey) {
      $bytes = New-Object byte[] 32
      [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
      $key = [Convert]::ToBase64String($bytes).Replace('+','-').Replace('/','_').TrimEnd('=')
      $keyFile = Join-Path $configDir 'winremote-auth.key'
      Set-Content -LiteralPath $keyFile -Value $key -Encoding ASCII -NoNewline
      Write-Host "AUTH_KEY_FILE=$keyFile (contents not shown)"
      $bat = "@echo off`r`nset PYTHONIOENCODING=utf-8`r`nset /p WINREMOTE_AUTH_KEY=<$keyFile`r`n`"$python`" -m winremote --transport streamable-http --host 127.0.0.1 --port $Port --auth-key `"%WINREMOTE_AUTH_KEY%`"`r`n"
    } else {
      $bat = "@echo off`r`nset PYTHONIOENCODING=utf-8`r`n`"$python`" -m winremote --transport streamable-http --host 127.0.0.1 --port $Port`r`n"
    }
    Set-Content -LiteralPath $batPath -Value $bat -Encoding ASCII
    Write-Host "MCP_START_SCRIPT=$batPath"

    $taskName = 'AERIS-PC1-WINREMOTE-MCP'
    $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$batPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = 'PT30S'
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
      -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
      -ExecutionTimeLimit ([TimeSpan]::Zero)
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
      -Principal $taskPrincipal -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    $actions.Add("MCP_TASK_REGISTERED:$taskName")
    Write-Host "MCP_TASK_REGISTERED=$taskName"

    $mcpHealthy = $false
    foreach ($attempt in 1..15) {
      Start-Sleep -Seconds 3
      try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 5
        if ($r.status -eq 'ok') { $mcpHealthy = $true; Write-Host "MCP_HEALTH=ok VERSION=$($r.version)"; break }
      } catch { }
    }
    if (-not $mcpHealthy) { Write-Host 'MCP_HEALTH=unverified'; $actions.Add('MCP_NOT_HEALTHY') }
  }
}

# --- 3. Tailscale ---------------------------------------------------------
Write-Host ''
Write-Host 'STEP=TAILSCALE'
$ts = (Get-Command tailscale -ErrorAction SilentlyContinue).Source
if (-not $ts) {
  foreach ($c in @("$env:ProgramFiles\Tailscale\tailscale.exe",
                   "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe")) {
    if (Test-Path -LiteralPath $c) { $ts = $c; break }
  }
}

if ($SkipTailscale -or -not $ts) {
  Write-Host "TAILSCALE_SKIPPED (exe found: $([bool]$ts))"
} else {
  Write-Host "TAILSCALE=$ts"
  $status = (& $ts status --json 2>$null | Out-String | ConvertFrom-Json)
  $dnsName = $status.Self.DNSName
  $tailnetIp = ($status.Self.TailscaleIPs | Select-Object -First 1)
  Write-Host "TAILNET_IP=$tailnetIp DNS_NAME=$dnsName"

  # Tailscale SSH gives a second way onto the machine that does not involve the
  # runner, the MeshCentral agent, or a screen. It is governed by tailnet
  # identity and the ACL, not by keys on disk.
  & $ts set --ssh 2>&1 | Out-String | ForEach-Object { Write-Host "SSH_SET_OUTPUT=$($_.Trim())" }
  if ($LASTEXITCODE -eq 0) { $actions.Add('TAILSCALE_SSH_ENABLED'); Write-Host 'TAILSCALE_SSH=enabled' }
  else { Write-Host 'TAILSCALE_SSH=failed' }

  # Serve the MCP port over HTTPS inside the tailnet. serve, never funnel:
  # funnel would publish the endpoint to the whole internet.
  $serveOut = & $ts serve --bg $Port 2>&1 | Out-String
  Write-Host "SERVE_OUTPUT=$($serveOut.Trim())"
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'SERVE_FAILED'
    Write-Host 'ACTION_REQUIRED: enable HTTPS certificates for the tailnet once at'
    Write-Host '  https://login.tailscale.com/admin/dns  ->  HTTPS Certificates'
    $actions.Add('TAILSCALE_SERVE_FAILED')
  } else {
    $actions.Add("TAILSCALE_SERVE:$Port")
    $serveStatus = & $ts serve status 2>&1 | Out-String
    Write-Host $serveStatus
    if ($dnsName) {
      $url = "https://$dnsName"
      $reachable = $false
      foreach ($attempt in 1..8) {
        Start-Sleep -Seconds 3
        try {
          $r = Invoke-RestMethod -Uri "$url/health" -TimeoutSec 8
          if ($r.status -eq 'ok') { $reachable = $true; Write-Host "MCP_OVER_TAILNET=ok"; break }
        } catch { }
      }
      if (-not $reachable) { Write-Host 'MCP_OVER_TAILNET=unverified' }
    }
  }
}

# --- 4. Evidence ----------------------------------------------------------
Write-Host ''
Write-Host 'STEP=EVIDENCE'
$runnerAfter = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like 'actions.runner.*' -or $_.DisplayName -like '*GitHub Actions*' })
$runnerProcs = @(Get-Process -Name 'Runner.Listener','Runner.Worker' -ErrorAction SilentlyContinue)
$tsFinal = if ($ts -and -not $SkipTailscale) { (& $ts status --json 2>$null | Out-String | ConvertFrom-Json) } else { $null }

$report = [ordered]@{
  schemaVersion  = 1
  capturedAt     = (Get-Date).ToUniversalTime().ToString('o')
  computerName   = $env:COMPUTERNAME
  elevated       = $elevated
  runnerServices = @($runnerAfter | ForEach-Object { [ordered]@{ name = $_.Name; state = $_.State; startMode = $_.StartMode } })
  runnerProcesses = @($runnerProcs | ForEach-Object { $_.Id })
  mcpPort        = $Port
  mcpLocalUrl    = "http://127.0.0.1:$Port/mcp"
  tailnetIp      = if ($tsFinal) { ($tsFinal.Self.TailscaleIPs | Select-Object -First 1) } else { $null }
  dnsName        = if ($tsFinal) { $tsFinal.Self.DNSName } else { $null }
  mcpUrlOverTailnet = if ($tsFinal -and $tsFinal.Self.DNSName) { "https://$($tsFinal.Self.DNSName)/mcp" } else { $null }
  actions        = @($actions)
}
$reportPath = Join-Path $evidenceDir 'pc1-bootstrap.json'
Set-Content -LiteralPath $reportPath -Value ($report | ConvertTo-Json -Depth 6) -Encoding UTF8

Write-Host ''
Write-Host '=========================================='
Write-Host ' RESULT'
Write-Host '=========================================='
Write-Host "EVIDENCE=$reportPath"
Write-Host "RUNNER_STATES=$(($runnerAfter | ForEach-Object { "$($_.Name)=$($_.State)" }) -join ' ')"
Write-Host "RUNNER_PROCESSES=$($runnerProcs.Count)"
Write-Host "ACTIONS=$($actions -join ',')"
Write-Host ''
if ($report.mcpUrlOverTailnet) {
  Write-Host "MCP_URL=$($report.mcpUrlOverTailnet)"
  Write-Host 'Send this URL back to the agent to connect.'
}
Write-Host ''
Write-Host 'If the runner is now Running, the queued jobs will pick up within a minute.'
Write-Host 'If it is still stopped, copy the lines above and send them back.'
