# Install the AX -> PC1 reverse control channel on PC1.
#
# PC1 is behind NAT and off the agent's network, so the agent cannot dial in.
# This installs a worker that polls the agent's rendezvous endpoint from the
# inside, so every connection is outbound: no port forward, no tunnel, no inbound
# firewall rule, and no new credential on the GitHub side.
#
# Once this is running the agent can see the screen and run commands on PC1 with
# nobody sitting at the machine. That is the point: K should not have to be the
# hands.
#
# The worker runs in the logged-on user session, not as SYSTEM. A SYSTEM process
# lives in session 0, which has no desktop, so screenshots come back black. It
# is registered with restart-on-failure so it comes back after a reboot or a
# crash without anyone touching the machine.
#
# Run as Administrator:
#   powershell -ExecutionPolicy Bypass -File pc1-install-reverse-channel.ps1 `
#     -Sha <commit-sha> -Rendezvous https://<host>/ -Token <token>

param(
  [Parameter(Mandatory = $true)][string]$Sha,
  [Parameter(Mandatory = $true)][string]$Rendezvous,
  [Parameter(Mandatory = $true)][string]$Token,
  [string]$Repo = 'aerismusic8-alt/aeris-drive-automation',
  [string]$RuntimeRoot = 'C:\AX-Runtime',
  [string]$McpUrl = 'http://127.0.0.1:8090/mcp',
  [int]$Poll = 3,
  # Skip touching the MCP server's tier configuration.
  [switch]$SkipMcpTier
)

$ErrorActionPreference = 'Stop'
$InstallVersion = '2026-10-20.1'

Write-Host '=========================================='
Write-Host ' AX PC1 REVERSE CONTROL CHANNEL'
Write-Host '=========================================='
Write-Host "INSTALL_VERSION=$InstallVersion"
Write-Host "SHA=$Sha"

$actions = New-Object System.Collections.Generic.List[string]

function Step([string]$name, [scriptblock]$body) {
  Write-Host ''
  Write-Host "STEP=$name"
  try {
    & $body
  } catch {
    Write-Host "STEP_FAILED=$name ERROR=$($_.Exception.Message)"
    $actions.Add("FAILED:$name")
  }
}

# --- 1. Identity ----------------------------------------------------------
Step 'IDENTITY' {
  if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME" }
  Write-Host "PC1=VERIFIED COMPUTER=$env:COMPUTERNAME"
  $principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
  $elevated = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
  Write-Host "ELEVATED=$elevated"
  if (-not $elevated) { throw 'NOT_ELEVATED' }
  $actions.Add('IDENTITY_OK')
}

# --- 2. Python and the MCP client library --------------------------------
# The worker needs fastmcp to talk to the MCP server. winremote-mcp already
# installs it, so this is a check rather than an install.
Step 'PYTHON' {
  $python = (Get-Command python -ErrorAction SilentlyContinue).Source
  if (-not $python) {
    foreach ($c in @('C:\Python314\python.exe', 'C:\Python313\python.exe', 'C:\Python312\python.exe')) {
      if (Test-Path -LiteralPath $c) { $python = $c; break }
    }
  }
  if (-not $python) { throw 'PYTHON_NOT_FOUND' }
  Write-Host "PYTHON=$python"

  & $python -c "import fastmcp, sys; print('FASTMCP_OK', fastmcp.__version__, sys.version.split()[0])"
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'fastmcp missing - installing winremote-mcp to bring it in'
    & $python -m pip install --quiet --disable-pip-version-check winremote-mcp 2>&1 | Out-String | Write-Host
    & $python -c "import fastmcp; print('FASTMCP_OK', fastmcp.__version__)"
    if ($LASTEXITCODE -ne 0) { throw 'FASTMCP_INSTALL_FAILED' }
  }
  $script:PythonExe = $python
  $actions.Add('PYTHON_OK')
}

# --- 3. MCP server must expose Shell -------------------------------------
# The default tier set is 1+2, which has no Shell, FileWrite or App. Without
# tier3 the agent can look at the screen but cannot act on the machine, which is
# not control. Re-register the MCP task with --enable-tier3 if it is missing it.
Step 'MCP_TIER3' {
  if ($SkipMcpTier) { Write-Host 'SKIPPED_BY_FLAG'; return }

  $taskName = 'AERIS-PC1-WINREMOTE-MCP'
  $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if (-not $task) { Write-Host 'MCP_TASK_ABSENT - leaving it to the bootstrap script'; return }

  $existing = ($task.Actions | ForEach-Object { $_.Arguments }) -join ' '
  if ($existing -match '--enable-tier3') {
    Write-Host 'MCP_TIER3=already'
    $actions.Add('MCP_TIER3_PRESENT')
    return
  }

  Write-Host 'MCP_TIER3=missing - rewriting the start script with --enable-tier3'
  $batPath = 'C:\AX-Runtime\winremote\start-winremote-mcp.cmd'
  $logPath = 'C:\AX-Runtime\winremote\mcp-server.log'
  if (Test-Path -LiteralPath $batPath) {
    $bat = Get-Content -LiteralPath $batPath -Raw
    $bat = $bat -replace '(-m winremote[^\r\n]*?)(\s*>>)', '$1 --enable-tier3$2'
    if ($bat -notmatch '--enable-tier3') {
      $bat = $bat -replace '(-m winremote)', '$1 --enable-tier3'
    }
    Set-Content -LiteralPath $batPath -Value $bat -Encoding ASCII
    Write-Host "MCP_START_SCRIPT_UPDATED=$batPath"
  } else {
    Write-Host "MCP_START_SCRIPT_MISSING=$batPath"
  }

  Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
  Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  Write-Host 'MCP_TASK_RESTARTED'
  $actions.Add('MCP_TIER3_ADDED')
}

# --- 4. Install the worker ------------------------------------------------
Step 'WORKER_INSTALL' {
  $dir = Join-Path $RuntimeRoot 'reverse'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $workerPath = Join-Path $dir 'ax-pc1-worker.py'

  $url = "https://raw.githubusercontent.com/$Repo/$Sha/AX_PC_CONTROL/ax-pc1-worker.py"
  Write-Host "DOWNLOAD=$url"
  # Pinned to a commit SHA on purpose: raw.githubusercontent.com caches for 300
  # seconds and ignores a cache-busting query, so a branch URL can silently hand
  # back the previous revision.
  Invoke-WebRequest -Uri $url -OutFile $workerPath -UseBasicParsing
  $size = (Get-Item -LiteralPath $workerPath).Length
  Write-Host "WORKER_BYTES=$size"
  if ($size -lt 2000) { throw "WORKER_TOO_SMALL:$size" }

  # The token and URL live in a file rather than on the task's command line,
  # which is readable by any process on the machine.
  $cfg = Join-Path $dir 'worker-config.json'
  @{ rendezvous = $Rendezvous; token = $Token; mcpUrl = $McpUrl; poll = $Poll } |
    ConvertTo-Json | Set-Content -LiteralPath $cfg -Encoding UTF8
  Write-Host "WORKER_CONFIG=$cfg"

  $script:WorkerPath = $workerPath
  $script:WorkerDir = $dir
  $script:WorkerConfig = $cfg
  $actions.Add('WORKER_INSTALLED')
}

# --- 5. Smoke test before registering anything ---------------------------
# A one-shot poll cycle, so a broken URL, a wrong token or a missing library
# shows up here with the reason, instead of as a task that runs and does nothing.
Step 'SMOKE_TEST' {
  if (-not $script:WorkerPath) { throw 'WORKER_NOT_INSTALLED' }
  & $script:PythonExe -u $script:WorkerPath --config $script:WorkerConfig --once
  Write-Host "SMOKE_EXIT=$LASTEXITCODE"
  if ($LASTEXITCODE -ne 0) { throw "SMOKE_TEST_EXIT_$LASTEXITCODE" }
  $actions.Add('SMOKE_TEST_OK')
}

# --- 6. Register the worker as a restarting task -------------------------
Step 'SCHEDULED_TASK' {
  if (-not $script:WorkerPath) { throw 'WORKER_NOT_INSTALLED' }
  $taskName = 'AERIS-PC1-REVERSE-CONTROL'

  $taskUser = $env:USERNAME
  $sid = ([System.Security.Principal.NTAccount]$taskUser).Translate(
    [System.Security.Principal.SecurityIdentifier]).Value

  # The token stays in the config file. Putting it on the command line would
  # expose it to every process on the machine, and it is the only thing guarding
  # remote command execution here.
  $argLine = "-u `"$($script:WorkerPath)`" --config `"$($script:WorkerConfig)`""
  $action = New-ScheduledTaskAction -Execute $script:PythonExe -Argument $argLine -WorkingDirectory $script:WorkerDir
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $taskUser
  # Interactive (not InteractiveToken) is the name this cmdlet accepts, and it
  # runs in the user's session so screen capture works.
  $principal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Highest
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Description 'Polls the AX rendezvous and runs MCP tool calls on this machine.' | Out-Null
  Start-ScheduledTask -TaskName $taskName
  Write-Host "WORKER_TASK=$taskName USER=$taskUser"
  Start-Sleep -Seconds 6
  $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
  Write-Host "WORKER_TASK_LAST_RESULT=$($info.LastTaskResult)"
  $actions.Add('WORKER_TASK_REGISTERED')
}

# --- 7. Verify the agent can see this machine ---------------------------
# Ask the rendezvous what it has heard. A hello from this host means the agent
# now has a live path in, which is the whole objective.
Step 'VERIFY' {
  $stateUrl = ($Rendezvous.TrimEnd('/')) + '/ax/state'
  try {
    $r = Invoke-RestMethod -Uri $stateUrl -Headers @{ 'X-AX-Token' = $Token } -TimeoutSec 15
  } catch {
    Write-Host "VERIFY_UNREACHABLE=$($_.Exception.Message)"
    $actions.Add('VERIFY_UNREACHABLE')
    return
  }
  $hello = $r.hello
  if ($hello -and $hello.hostname) {
    Write-Host "AGENT_SEES_HOST=$($hello.hostname)"
    Write-Host "AGENT_SEES_USER=$($hello.user)"
    $actions.Add('CHANNEL_LIVE')
  } else {
    Write-Host 'CHANNEL_NO_HELLO_YET - the worker has not checked in yet'
    $actions.Add('CHANNEL_NO_HELLO')
  }
}

# --- Result ---------------------------------------------------------------
Write-Host ''
Write-Host '=========================================='
Write-Host ' RESULT'
Write-Host '=========================================='
Write-Host "ACTIONS=$($actions -join ',')"
$workerTask = Get-ScheduledTask -TaskName 'AERIS-PC1-REVERSE-CONTROL' -ErrorAction SilentlyContinue
if ($workerTask) { Write-Host "WORKER_TASK_STATE=$($workerTask.State)" }
Write-Host ''
if ($actions -contains 'CHANNEL_LIVE') {
  Write-Host 'SUCCESS - the agent can now control this machine without anyone at the keyboard.'
} else {
  Write-Host 'NOT_LIVE_YET - send the lines above back.'
}
Write-Host ''
Write-Host 'Log: $env:TEMP\ax-pc1-worker.log'
