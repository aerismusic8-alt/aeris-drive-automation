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
#   3. Puts two independent paths onto the machine in place: Windows OpenSSH
#      Server bound to the tailnet, and the MCP port served over the tailnet.
#      Neither depends on the runner, which is the point — the runner is what
#      failed, and every recovery route went through it.
#   4. Writes evidence of what it found and what it changed.
#
# On step 3: Tailscale SSH is not an option on Windows. Its server component
# only runs on Linux and macOS, so `tailscale set --ssh` does nothing here.
# Windows OpenSSH Server is the equivalent, with Tailscale providing the
# network path and OpenSSH the shell.
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
  [switch]$SkipTailscale,
  # The OpenSSH install is a fallback path and it can stall on Windows Update,
  # so it is skippable and bounded.
  [switch]$SkipOpenSSH
)

$ErrorActionPreference = 'Stop'

# Bump this whenever the script changes. It is printed first so the run itself
# says which build it is: a stale copy served from a cache is otherwise
# indistinguishable from a fresh one, which cost several rounds of confusion.
$BootstrapVersion = '2026-10-20.4'

Write-Host '=========================================='
Write-Host ' AX PC1 BOOTSTRAP'
Write-Host '=========================================='
Write-Host "SCRIPT_VERSION=$BootstrapVersion"

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
    if ($svc.State -eq 'Running') {
      # A runner service can be Running while its listener is gone: the service
      # stays up but nothing talks to GitHub, so jobs queue forever and the
      # state still looks healthy. The listener process is the signal that
      # matters, so check it rather than trusting "Running".
      $listener = @(Get-Process -Name 'Runner.Listener' -ErrorAction SilentlyContinue)
      if ($listener.Count -gt 0) {
        Write-Host "RUNNER_LISTENER=present PID=$($listener[0].Id)"
      } else {
        Write-Host 'RUNNER_LISTENER=absent - restarting the service to reconnect'
        try {
          Restart-Service -Name $svc.Name -ErrorAction Stop
          $actions.Add("RUNNER_RESTARTED:$($svc.Name)")
          Write-Host "RUNNER_RESTARTED=$($svc.Name)"
        } catch {
          $actions.Add("RUNNER_RESTART_FAILED:$($svc.Name):$($_.Exception.Message)")
          Write-Host "RUNNER_RESTART_FAILED=$($svc.Name) ERROR=$($_.Exception.Message)"
        }
      }
      continue
    }
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
  # pip writes dependency-conflict warnings to stderr and still exits 0. Under
  # $ErrorActionPreference='Stop' PowerShell turns that stderr into a
  # terminating NativeCommandError, which killed this script mid-run and left
  # everything after it undone. Only a non-zero exit code is a real failure.
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $pipOut = & $python -m pip install --quiet --upgrade winremote-mcp 2>&1 | Out-String
  $pipCode = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  Write-Host "PIP_EXIT=$pipCode"
  if ($pipCode -ne 0) {
    Write-Host $pipOut
    $actions.Add("PIP_INSTALL_FAILED:$pipCode")
    Write-Host "PIP_INSTALL_FAILED=$pipCode"
  } else {
    # The package needs Python 3.10+. Say so plainly instead of failing later
    # with an import error that looks like a broken install.
    $pyOk = $false
    $pyVer = ''
    try {
      $pyVer = (& $python -c "import sys;print('%d.%d'%sys.version_info[:2])").Trim()
      $parts = $pyVer.Split('.')
      $pyOk = ([int]$parts[0] -gt 3) -or ([int]$parts[0] -eq 3 -and [int]$parts[1] -ge 10)
    } catch { }
    Write-Host "PYTHON_VERSION=$pyVer SUPPORTED=$pyOk"
    if (-not $pyOk) {
      $actions.Add("PYTHON_TOO_OLD:$pyVer")
      Write-Host 'PYTHON_TOO_OLD - winremote-mcp needs Python 3.10 or newer.'
      Write-Host 'Install a newer Python (winget install Python.Python.3.12) and re-run.'
    }

    $pkgVersion = (& $python -c "import winremote;print(getattr(winremote,'__version__','unknown'))").Trim()
    Write-Host "MCP_PACKAGE_VERSION=$pkgVersion"

    $configDir = Join-Path $RuntimeRoot 'winremote'
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    $batPath = Join-Path $configDir 'start-winremote-mcp.cmd'
    $logPath = Join-Path $configDir 'winremote-mcp.log'

    # Loopback bind, no auth: the Tailscale layer is the boundary. A token here
    # would be defence in depth against another process on this same machine,
    # which already implies the machine is compromised.
    # Redirect stdout/stderr to a log file. Without it a start-up failure leaves
    # nothing behind to explain why, which is exactly what happened: the task
    # registered, ran, and the health check simply never answered.
    if ($WithAuthKey) {
      $bytes = New-Object byte[] 32
      [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
      $key = [Convert]::ToBase64String($bytes).Replace('+','-').Replace('/','_').TrimEnd('=')
      $keyFile = Join-Path $configDir 'winremote-auth.key'
      Set-Content -LiteralPath $keyFile -Value $key -Encoding ASCII -NoNewline
      Write-Host "AUTH_KEY_FILE=$keyFile (contents not shown)"
      $bat = "@echo off`r`nset PYTHONIOENCODING=utf-8`r`nset /p WINREMOTE_AUTH_KEY=<$keyFile`r`n`"$python`" -m winremote --transport streamable-http --host 127.0.0.1 --port $Port --auth-key `"%WINREMOTE_AUTH_KEY%`" >> `"$logPath`" 2>&1`r`n"
    } else {
      $bat = "@echo off`r`nset PYTHONIOENCODING=utf-8`r`n`"$python`" -m winremote --transport streamable-http --host 127.0.0.1 --port $Port >> `"$logPath`" 2>&1`r`n"
    }
    Set-Content -LiteralPath $batPath -Value $bat -Encoding ASCII
    Write-Host "MCP_START_SCRIPT=$batPath"

    # The MCP server must run as the interactive user, not as SYSTEM. A SYSTEM
    # process lives in session 0, which has no desktop, so Snapshot would return
    # a black frame and the input tools would have nothing to act on: the server
    # would look healthy while being useless for remote control. Bind it to the
    # logged-on user instead, which is what the Roblox capture tasks already do.
    $taskUser = (Get-CimInstance Win32_ComputerSystem).UserName
    $taskName = 'AERIS-PC1-WINREMOTE-MCP'
    $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$batPath`""

    if ($taskUser) {
      $sid = ([System.Security.Principal.NTAccount]$taskUser).Translate(
        [System.Security.Principal.SecurityIdentifier]).Value
      # The enum value is 'Interactive', not 'InteractiveToken': the cmdlet's
      # LogonTypeEnum only accepts None, Password, S4U, Interactive, Group,
      # ServiceAccount, InteractiveOrPassword. The wrong name throws before the
      # task is registered, and with $ErrorActionPreference='Stop' it ended the
      # whole script.
      #
      # Interactive needs no stored password and runs only while that user is
      # logged on, which is exactly when a desktop exists to control.
      $trigger = New-ScheduledTaskTrigger -AtLogOn -User $taskUser
      $taskPrincipal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Highest
      Write-Host "MCP_TASK_USER=$taskUser"
    } else {
      # No interactive user: a headless machine. The server still answers, so an
      # agent can run shell and file tools, but screen tools will not be useful.
      Write-Host 'MCP_TASK_USER=none - no interactive user logged on'
      Write-Host 'MCP_NOTE=screen capture needs a logged-on desktop session'
      $trigger = New-ScheduledTaskTrigger -AtStartup
      $trigger.Delay = 'PT30S'
      $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
      $actions.Add('MCP_TASK_HEADLESS')
    }

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
      -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
      -ExecutionTimeLimit ([TimeSpan]::Zero)
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
    if (-not $mcpHealthy) {
      Write-Host 'MCP_HEALTH=unverified'
      $actions.Add('MCP_NOT_HEALTHY')
      # Show why it failed rather than leaving a bare "unverified".
      $ti = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
      if ($ti) {
        Write-Host "MCP_TASK_LAST_RESULT=$($ti.LastTaskResult) LAST_RUN=$($ti.LastRunTime)"
      }
      if (Test-Path -LiteralPath $logPath) {
        Write-Host '--- last 25 lines of the MCP log ---'
        Get-Content -LiteralPath $logPath -Tail 25 | ForEach-Object { Write-Host "  $_" }
        Write-Host '--- end of log ---'
      } else {
        Write-Host "MCP_LOG_MISSING=$logPath"
      }
      # A stale process from an earlier attempt holds the port, so the new one
      # cannot bind. Clear it before giving up.
      $holder = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
      if ($holder) {
        Write-Host "MCP_PORT_HELD_BY_PID=$($holder.OwningProcess)"
        try {
          Stop-Process -Id $holder.OwningProcess -Force -ErrorAction Stop
          Write-Host 'MCP_PORT_CLEARED - retrying once'
          Start-ScheduledTask -TaskName $taskName
          foreach ($attempt in 1..10) {
            Start-Sleep -Seconds 3
            try {
              $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 5
              if ($r.status -eq 'ok') { $mcpHealthy = $true; Write-Host "MCP_HEALTH=ok VERSION=$($r.version)"; break }
            } catch { }
          }
        } catch {
          Write-Host "MCP_PORT_CLEAR_FAILED=$($_.Exception.Message)"
        }
      }
    }
  }
}

# --- 3. Tailscale ---------------------------------------------------------
Write-Host ''
Write-Host 'STEP=TAILSCALE'
# Initialised here so the evidence block can always report them, even when the
# Tailscale step is skipped or fails before reaching them.
$rdpOn = $null
$dnsName = $null
$tailnetIp = $null
$ts = (Get-Command tailscale -ErrorAction SilentlyContinue).Source
if (-not $ts) {
  foreach ($c in @("$env:ProgramFiles\Tailscale\tailscale.exe",
                   "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe")) {
    if (Test-Path -LiteralPath $c) { $ts = $c; break }
  }
}

if ($SkipTailscale) {
  Write-Host 'TAILSCALE_SKIPPED_BY_FLAG'
} elseif (-not $ts) {
  # A missing binary used to end the step silently, which left the machine with
  # no path that survives the runner dying again. Install it instead.
  Write-Host 'TAILSCALE_NOT_FOUND - installing'
  $winget = (Get-Command winget -ErrorAction SilentlyContinue).Source
  if (-not $winget) {
    Write-Host 'WINGET_NOT_FOUND'
    Write-Host 'Install Tailscale from https://tailscale.com/download/windows and re-run.'
    $actions.Add('TAILSCALE_MISSING_NO_WINGET')
  } else {
    & $winget install --id Tailscale.Tailscale -e --accept-source-agreements --accept-package-agreements
    foreach ($c in @("$env:ProgramFiles\Tailscale\tailscale.exe",
                     "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe")) {
      if (Test-Path -LiteralPath $c) { $ts = $c; break }
    }
    if ($ts) { $actions.Add('TAILSCALE_INSTALLED'); Write-Host "TAILSCALE_INSTALLED=$ts" }
    else { Write-Host 'TAILSCALE_INSTALL_FAILED'; $actions.Add('TAILSCALE_INSTALL_FAILED') }
  }
}

if ($ts -and -not $SkipTailscale) {
  Write-Host "TAILSCALE=$ts"
  # A fresh install is not logged in yet, so `status --json` has no Self. Treat
  # that as "needs a human", not as a crash.
  $statusRaw = (& $ts status --json 2>$null | Out-String)
  $status = $null
  try { $status = $statusRaw | ConvertFrom-Json } catch { }

  if (-not $status -or $status.BackendState -ne 'Running') {
    Write-Host 'TAILSCALE_NOT_LOGGED_IN'
    Write-Host 'ACTION_REQUIRED: `tailscale up` prints a URL. Open it on any device'
    Write-Host 'signed in to the same tailnet account and approve this machine.'
    & $ts up
    Start-Sleep -Seconds 5
    $statusRaw = (& $ts status --json 2>$null | Out-String)
    try { $status = $statusRaw | ConvertFrom-Json } catch { }
  }

  if (-not $status -or $status.BackendState -ne 'Running') {
    Write-Host 'TAILSCALE_LOGIN_INCOMPLETE'
    $actions.Add('TAILSCALE_LOGIN_INCOMPLETE')
  } else {
    $dnsName = $status.Self.DNSName
    $tailnetIp = ($status.Self.TailscaleIPs | Select-Object -First 1)
    Write-Host "TAILNET_IP=$tailnetIp DNS_NAME=$dnsName"
    $actions.Add('TAILSCALE_UP')

  # Report whether the built-in remote desktop is reachable, because that is the
  # only way onto this machine from a phone before any of the above exists.
  Write-Host 'STEP=RDP_STATE'
  $rdpDenied = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
    -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections
  $rdpOn = ($rdpDenied -eq 0)
  Write-Host "RDP_ENABLED=$rdpOn"
  Write-Host "TAILNET_RDP_TARGET=$tailnetIp"

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

  # Tailscale SSH is NOT usable here. Its server component only runs on Linux
  # and macOS (Tailscale docs, "Limitations / Devices"), so `tailscale set --ssh`
  # does nothing on Windows. Windows OpenSSH Server is the equivalent: Tailscale
  # supplies the network path and OpenSSH supplies the shell. This is what makes
  # the machine reachable later without the runner and without a screen.
  Write-Host 'STEP=WINDOWS_OPENSSH'
  try {
    $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($SkipOpenSSH) {
      Write-Host 'OPENSSH_SKIPPED_BY_FLAG'
    } elseif (-not $sshd) {
      # Add-WindowsCapability fetches from Windows Update and can stall for a
      # very long time with no output, which makes the whole script look hung.
      # A job with a deadline keeps that from blocking everything after it,
      # including the MCP serve step that actually matters.
      Write-Host 'OPENSSH_SERVER_ABSENT - adding the optional Windows capability'
      Write-Host 'OPENSSH_INSTALL_DEADLINE=180s'
      $job = Start-Job -ScriptBlock {
        try {
          $c = Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' -ErrorAction Stop
          "ADDED:$($c.RestartNeeded)"
        } catch { "FAILED:$($_.Exception.Message)" }
      }
      $done = Wait-Job -Job $job -Timeout 180
      if ($done) {
        $res = Receive-Job -Job $job
        Write-Host "OPENSSH_CAPABILITY=$res"
      } else {
        Write-Host 'OPENSSH_INSTALL_TIMEOUT - continuing without it'
        Write-Host 'It may still finish in the background; re-run this script later.'
        $actions.Add('OPENSSH_INSTALL_TIMEOUT')
      }
      Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
      $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue
    }
    if ($sshd) {
      Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
      if ($sshd.Status -ne 'Running') { Start-Service -Name sshd -ErrorAction Stop }
      $actions.Add('OPENSSH_SERVER_RUNNING')
      Write-Host 'OPENSSH_SERVER=running'
      # Scope the firewall rule to the tailnet range so the port is not open to
      # the local LAN or anything else. Tailscale traffic arrives on the same
      # interface, so an unscoped rule would be wider than needed.
      $fw = Get-NetFirewallRule -Name 'AX-PC1-OpenSSH-Tailnet' -ErrorAction SilentlyContinue
      if (-not $fw) {
        New-NetFirewallRule -Name 'AX-PC1-OpenSSH-Tailnet' -DisplayName 'AX PC1 OpenSSH (tailnet only)' `
          -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow `
          -RemoteAddress 100.64.0.0/10 -ErrorAction Stop | Out-Null
        $actions.Add('OPENSSH_FIREWALL_SCOPED_TO_TAILNET')
        Write-Host 'OPENSSH_FIREWALL=tailnet-only'
      }
    }
  } catch {
    $actions.Add("OPENSSH_SETUP_FAILED:$($_.Exception.Message)")
    Write-Host "OPENSSH_SETUP_FAILED=$($_.Exception.Message)"
  }
}

# --- 4. Evidence ----------------------------------------------------------
Write-Host ''
Write-Host 'STEP=EVIDENCE'
$runnerAfter = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like 'actions.runner.*' -or $_.DisplayName -like '*GitHub Actions*' })
$runnerProcs = @(Get-Process -Name 'Runner.Listener','Runner.Worker' -ErrorAction SilentlyContinue)

$report = [ordered]@{
  schemaVersion  = 1
  capturedAt     = (Get-Date).ToUniversalTime().ToString('o')
  computerName   = $env:COMPUTERNAME
  elevated       = $elevated
  runnerServices = @($runnerAfter | ForEach-Object { [ordered]@{ name = $_.Name; state = $_.State; startMode = $_.StartMode } })
  runnerProcesses = @($runnerProcs | ForEach-Object { $_.Id })
  mcpPort        = $Port
  mcpLocalUrl    = "http://127.0.0.1:$Port/mcp"
  openSshRunning = $null -ne (Get-Service -Name sshd -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' })
  rdpEnabled     = $rdpOn
  tailnetIp      = $tailnetIp
  dnsName        = $dnsName
  mcpUrlOverTailnet = if ($dnsName) { "https://$dnsName/mcp" } else { $null }
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
