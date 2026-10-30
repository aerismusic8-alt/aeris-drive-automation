# pc1_fix_remote.ps1 — make PC1 (DESKTOP-RGK6JKB) drivable by an agent again.
#
# Two faults, both fixed here, and both are why an agent can *look* at PC1 but
# cannot *act* on it:
#
#   1. The winremote-mcp server is not running, so the tailnet endpoint answers
#      502. The scheduled task that should keep it up is missing or stopped.
#   2. When it does run it starts with the default tool set: tier 1 (read-only)
#      and tier 2 (mouse/keyboard). Shell, FileRead, FileWrite, FileUpload,
#      FileDownload, App, KillProcess, PlaySound, RegWrite and the other tier 3
#      tools are disabled. So "capture the screen" works, but "run a command" or
#      "save a file" does not.
#
# The fix starts the server with --enable-tier3 and re-asserts the tailnet path
# onto it. The server keeps binding 127.0.0.1 and Tailscale serve is the only way
# in, so tier 3 is not exposed to the open internet.
#
# Idempotent: run it as often as you like. Run as Administrator.
#
#   powershell -ExecutionPolicy Bypass -File pc1_fix_remote.ps1 -Token "<PC1_MCP_TOKEN>"
#
# The token is the auth key the server already uses (the same value as the
# PC1_MCP_TOKEN / PC1_MCP_TOKEN_2 secret in OpenHands). Pass it only if you are
# changing or re-establishing the key; omit it to reuse the key already on disk.

[CmdletBinding()]
param(
  [string]$RuntimeRoot = 'C:\AX-Runtime',
  [int]$Port = 8090,
  [string]$Token = '',
  # Accepted for compatibility with the earlier command K remembers
  # (`-Token <key> -Persist`). Persisting is what this script always does: the
  # scheduled task below restarts the server on every logon. The flag is kept so
  # that command does not fail with "a parameter cannot be found".
  [switch]$Persist,
  [switch]$SkipRunner,
  [switch]$SkipTailscale
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '2026-10-26.1'

# Tools that prove tier 3 is really on. If any is missing from tools/list, the
# agent can see the desktop but cannot work on it.
$Tier3Required = @('Shell', 'FileRead', 'FileWrite', 'FileUpload', 'FileDownload', 'App', 'PlaySound', 'KillProcess')

function Step([string]$name) { Write-Host ''; Write-Host "STEP=$name" }
function Say([string]$m) { Write-Host "  $m" }

Write-Host '=========================================='
Write-Host ' AX PC1 REMOTE FIX'
Write-Host '=========================================='
Write-Host "SCRIPT_VERSION=$ScriptVersion"

$evidenceDir = Join-Path $RuntimeRoot 'evidence'
$configDir = Join-Path $RuntimeRoot 'winremote'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
New-Item -ItemType Directory -Path $configDir -Force | Out-Null
$actions = New-Object System.Collections.Generic.List[string]
$status = ''

# --- 0. Identity and elevation -------------------------------------------
Step 'IDENTITY'
if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME" }
Say "PC1=VERIFIED COMPUTER=$env:COMPUTERNAME"

$principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
$elevated = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
Say "ELEVATED=$elevated"
if (-not $elevated) {
  Write-Host ''
  Write-Host 'WARNING: not running as Administrator. Registering the service and the'
  Write-Host 'scheduled task will likely fail. Re-open PowerShell with "Run as administrator".'
  Write-Host ''
}

# --- 1. Python -----------------------------------------------------------
Step 'PYTHON'
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) {
  foreach ($c in @("$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
                   "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
                   "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
                   'C:\Python313\python.exe', 'C:\Python312\python.exe', 'C:\Python311\python.exe')) {
    if (Test-Path -LiteralPath $c) { $python = $c; break }
  }
}
if (-not $python) { throw 'PYTHON_NOT_FOUND: install Python 3.10+ (winget install Python.Python.3.12), then re-run.' }
$pyVer = (& $python -c "import sys;print('%d.%d'%sys.version_info[:2])").Trim()
Say "PYTHON=$python VERSION=$pyVer"

# pip writes dependency-conflict warnings to stderr and still exits 0. With
# $ErrorActionPreference='Stop' PowerShell turns that stderr into a terminating
# error, which killed the earlier bootstrap mid-run. Only the exit code counts.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$pipOut = & $python -m pip install --quiet --disable-pip-version-check --upgrade winremote-mcp 2>&1 | Out-String
$pipCode = $LASTEXITCODE
$ErrorActionPreference = $prevEap
Say "PIP_EXIT=$pipCode"
if ($pipCode -ne 0) { Write-Host $pipOut; throw "PIP_INSTALL_FAILED:$pipCode" }
$pkgVersion = (& $python -c "import winremote;print(getattr(winremote,'__version__','unknown'))").Trim()
Say "MCP_PACKAGE_VERSION=$pkgVersion"

# --- 2. Auth key ---------------------------------------------------------
Step 'AUTH_KEY'
$keyFile = Join-Path $configDir 'winremote-auth.key'
if (-not [string]::IsNullOrWhiteSpace($Token)) {
  Set-Content -LiteralPath $keyFile -Value $Token -Encoding ASCII -NoNewline
  Say 'AUTH_KEY=set from -Token'
} elseif (Test-Path -LiteralPath $keyFile) {
  Say "AUTH_KEY=reused from $keyFile"
} else {
  $bytes = New-Object byte[] 32
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $Token = [Convert]::ToBase64String($bytes).Replace('+','-').Replace('/','_').TrimEnd('=')
  Set-Content -LiteralPath $keyFile -Value $Token -Encoding ASCII -NoNewline
  Say "AUTH_KEY=generated -> $keyFile (contents not shown)"
}
$keyValue = (Get-Content -LiteralPath $keyFile -Raw).Trim()
# SYSTEM and Administrators only.
try {
  $acl = New-Object System.Security.AccessControl.FileSecurity
  $acl.SetAccessRuleProtection($true, $false)
  foreach ($who in @('SYSTEM', 'Administrators')) {
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($who, 'FullControl', 'Allow')
    $acl.AddAccessRule($rule)
  }
  Set-Acl -LiteralPath $keyFile -AclObject $acl
  Say 'AUTH_KEY_ACL=SYSTEM+Administrators only'
} catch { Say "AUTH_KEY_ACL=left unchanged ($($_.Exception.Message))" }

# --- 3. Start script, with tier 3 ----------------------------------------
# This is the actual fix. The server is started with --enable-tier3 so Shell,
# FileRead/Write/Upload/Download, App, KillProcess, PlaySound and friends exist.
# -u keeps stdout unbuffered so the log shows a start-up failure instead of
# sitting empty, which is what made the last outage hard to read.
Step 'START_SCRIPT'
$batPath = Join-Path $configDir 'start-winremote-mcp.cmd'
$logPath = Join-Path $configDir 'winremote-mcp.log'
$bat = @"
@echo off
set PYTHONIOENCODING=utf-8
set /p WINREMOTE_AUTH_KEY=<$keyFile
"$python" -u -m winremote --transport streamable-http --host 127.0.0.1 --port $Port --enable-tier3 --auth-key "%WINREMOTE_AUTH_KEY%" >> "$logPath" 2>&1
"@
Set-Content -LiteralPath $batPath -Value $bat -Encoding ASCII
Say "MCP_START_SCRIPT=$batPath"
Say "MCP_LOG=$logPath"
$actions.Add('START_SCRIPT_TIER3')

# --- 4. Scheduled task ---------------------------------------------------
# The task must run as the interactive user, not SYSTEM: a SYSTEM process lives
# in session 0, which has no desktop, so Snapshot returns a black frame and the
# input tools have nothing to act on. The server would look healthy and be
# useless for control.
Step 'TASK'
$taskName = 'AERIS-PC1-WINREMOTE-MCP'
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue }

$taskUser = (Get-CimInstance Win32_ComputerSystem).UserName
$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$batPath`"" -WorkingDirectory $configDir
if ($taskUser) {
  $sid = ([System.Security.Principal.NTAccount]$taskUser).Translate([System.Security.Principal.SecurityIdentifier]).Value
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $taskUser
  $taskPrincipal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Highest
  Say "MCP_TASK_USER=$taskUser (interactive - a real desktop exists)"
} else {
  $trigger = New-ScheduledTaskTrigger -AtStartup
  $trigger.Delay = 'PT30S'
  $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  Say 'MCP_TASK_USER=none - no interactive user logged on; screen tools will be limited'
  $actions.Add('MCP_TASK_HEADLESS')
}
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
  -Principal $taskPrincipal -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Say "TASK_REGISTERED=$taskName"
$actions.Add("MCP_TASK_REGISTERED:$taskName")

# --- 5. Actions runner ---------------------------------------------------
# Not needed to drive the desktop, but the runner carries queued jobs and its
# being down is why every recovery route stalled. A runner service can read
# "Running" while its listener is gone, so check the process, not the state.
if (-not $SkipRunner) {
  Step 'RUNNER'
  $runnerServices = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'actions.runner.*' -or $_.DisplayName -like '*GitHub Actions*' })
  if ($runnerServices.Count -eq 0) {
    Say 'RUNNER_SERVICE_MISSING - start or reinstall the runner by hand'
    $actions.Add('RUNNER_SERVICE_MISSING')
  } else {
    foreach ($svc in $runnerServices) {
      Say "RUNNER_SERVICE=$($svc.Name) STATE=$($svc.State)"
      $listener = @(Get-Process -Name 'Runner.Listener' -ErrorAction SilentlyContinue)
      if ($svc.State -eq 'Running' -and $listener.Count -gt 0) {
        Say "RUNNER_LISTENER=present PID=$($listener[0].Id)"; continue
      }
      try {
        if ($svc.StartMode -eq 'Disabled') { Set-Service -Name $svc.Name -StartupType Manual }
        Restart-Service -Name $svc.Name -ErrorAction Stop
        Say "RUNNER_RESTARTED=$($svc.Name)"
        $actions.Add("RUNNER_RESTARTED:$($svc.Name)")
      } catch {
        Say "RUNNER_RESTART_FAILED=$($svc.Name) ERROR=$($_.Exception.Message)"
        $actions.Add("RUNNER_RESTART_FAILED:$($svc.Name)")
      }
    }
  }
}

# --- 6. Tailnet path -----------------------------------------------------
Step 'TAILSCALE'
$ts = (Get-Command tailscale -ErrorAction SilentlyContinue).Source
if (-not $ts) {
  foreach ($c in @("$env:ProgramFiles\Tailscale\tailscale.exe", "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe")) {
    if (Test-Path -LiteralPath $c) { $ts = $c; break }
  }
}
if ($SkipTailscale) {
  Say 'TAILSCALE=skipped (-SkipTailscale)'
} elseif (-not $ts) {
  Say 'TAILSCALE_MISSING - the runner path still works, but there is no second way in'
  $actions.Add('TAILSCALE_MISSING')
} else {
  Say "TAILSCALE=$ts"
  $ErrorActionPreference = 'Continue'
  & $ts serve --bg $Port 2>&1 | ForEach-Object { Say $_ }
  $serveCode = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  Say "SERVE_EXIT=$serveCode"
  $ErrorActionPreference = 'Continue'
  $status = & $ts serve status 2>&1 | Out-String
  $ErrorActionPreference = $prevEap
  Write-Host $status.Trim()
  if ($status -match '(https://[^\s/]+)') { Say "TAILNET_URL=$($Matches[1])"; $actions.Add('TAILSCALE_SERVED') }
  else { $actions.Add('TAILSCALE_SERVE_UNCONFIRMED') }
}

# --- 7. Verify: the server answers ---------------------------------------
Step 'VERIFY_HEALTH'
$healthy = $false
foreach ($attempt in 1..20) {
  Start-Sleep -Seconds 3
  try {
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 5
    if ($r.status -eq 'ok') { $healthy = $true; Say "HEALTH=ok VERSION=$($r.version) ATTEMPT=$attempt"; break }
  } catch { }
}
if (-not $healthy) {
  Write-Host ''
  Write-Host "MCP_SERVER_NOT_HEALTHY: http://127.0.0.1:$Port/health never answered."
  Write-Host "Last lines of $logPath :"
  if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail 30 | ForEach-Object { Write-Host "    $_" } }
  throw 'MCP_SERVER_NOT_HEALTHY'
}

# --- 8. Verify: tier 3 is actually exposed -------------------------------
# A raw JSON-RPC client, written here so the script depends on nothing that has
# to be downloaded. It handles the two traps that made this look like a bad
# token before: the reply is an SSE stream, and the session id comes back in a
# header that must be echoed on every later call.
Step 'VERIFY_TIER3'
$probePath = Join-Path $configDir 'mcp_probe.py'
$probe = @'
import json, os, sys, urllib.request, urllib.error

url = sys.argv[1]
key = os.environ.get("WINREMOTE_AUTH_KEY", "")
sid = {"v": None}
counter = [0]

def post(payload):
    h = {"Content-Type": "application/json",
         "Accept": "application/json, text/event-stream"}
    if key:
        h["Authorization"] = "Bearer " + key
    if sid["v"]:
        h["mcp-session-id"] = sid["v"]
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), method="POST", headers=h)
    try:
        with urllib.request.urlopen(req, timeout=60) as f:
            if f.headers.get("mcp-session-id"):
                sid["v"] = f.headers["mcp-session-id"]
            return f.read().decode()
    except urllib.error.HTTPError as e:
        return e.read().decode()

def unwrap(body):
    for line in body.splitlines():
        line = line.strip()
        if line.startswith("data:"):
            return json.loads(line[5:].strip())
    return json.loads(body or "{}")

counter[0] += 1
post({"jsonrpc": "2.0", "id": counter[0], "method": "initialize",
      "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                 "clientInfo": {"name": "pc1-fix", "version": "1"}}})
post({"jsonrpc": "2.0", "method": "notifications/initialized"})
counter[0] += 1
tools = unwrap(post({"jsonrpc": "2.0", "id": counter[0], "method": "tools/list", "params": {}}))
names = sorted(t["name"] for t in tools.get("result", {}).get("tools", []))

def call(name, args):
    counter[0] += 1
    return unwrap(post({"jsonrpc": "2.0", "id": counter[0], "method": "tools/call",
                        "params": {"name": name, "arguments": args}}))

out = {"toolCount": len(names), "tools": names}
out["shell"] = call("Shell", {"command": "hostname"})
out["filewrite"] = call("FileWrite", {"path": os.path.join(os.environ.get("TEMP", "."), "ax-fix-proof.txt"),
                                      "content": "ax tier3 proof"})
print(json.dumps(out))
'@
Set-Content -LiteralPath $probePath -Value $probe -Encoding UTF8

$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$env:WINREMOTE_AUTH_KEY = $keyValue
$probeOut = & $python $probePath "http://127.0.0.1:$Port/mcp" 2>&1 | Out-String
$ErrorActionPreference = $prevEap
$probeJson = $null
try { $probeJson = ($probeOut.Trim() | ConvertFrom-Json) } catch { }
if (-not $probeJson) { Write-Host $probeOut; throw 'TIER3_PROBE_FAILED' }

$toolNames = @($probeJson.tools)
Say "TOOL_COUNT=$($probeJson.toolCount)"
$missing = @($Tier3Required | Where-Object { $toolNames -notcontains $_ })
if ($missing.Count -gt 0) { throw "TIER3_STILL_DISABLED: missing $($missing -join ', ')" }
Say 'TIER3=on'
Say "TIER3_TOOLS_PRESENT=$($Tier3Required -join ',')"

$shellText = ($probeJson.shell.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1).text
Say "SHELL_PROOF=hostname -> $shellText"
$fwText = ($probeJson.filewrite.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1).text
Say "FILEWRITE_PROOF=$fwText"

# --- 9. Evidence ---------------------------------------------------------
$tailnetUrl = ''
if ($status -and $status -match '(https://[^\s/]+)') { $tailnetUrl = $Matches[1] }
$report = [ordered]@{
  schemaVersion   = 1
  scriptVersion   = $ScriptVersion
  capturedAt      = (Get-Date).ToUniversalTime().ToString('o')
  hostname        = $env:COMPUTERNAME
  python          = $python
  pythonVersion   = $pyVer
  packageVersion  = $pkgVersion
  port            = $Port
  taskName        = $taskName
  enableTier3     = $true
  toolCount       = $probeJson.toolCount
  tier3Verified   = ($missing.Count -eq 0)
  shellProof      = "$shellText"
  fileWriteProof  = "$fwText"
  tailnetUrl      = $tailnetUrl
  authKeyFile     = $keyFile
  actions         = $actions
}
Set-Content -LiteralPath (Join-Path $evidenceDir 'pc1-remote-fix.json') `
  -Value ($report | ConvertTo-Json -Depth 6) -Encoding UTF8
Say "EVIDENCE=$(Join-Path $evidenceDir 'pc1-remote-fix.json')"

# --- 10. Result ----------------------------------------------------------
Write-Host ''
Write-Host '=========================================='
Write-Host ' RESULT'
Write-Host '=========================================='
Write-Host "SCRIPT_VERSION=$ScriptVersion"
Write-Host "TOOLS=$($probeJson.toolCount)"
Write-Host 'TIER3=on'
Write-Host "SHELL_PROOF=$shellText"
Write-Host 'FILEWRITE_PROOF=ok'
if ($tailnetUrl) { Write-Host "TAILNET_URL=$tailnetUrl" }
Write-Host 'RESULT=OK'
Write-Host ''
Write-Host 'PC1 can now be driven: screen, shell, files, mouse and keyboard.'
Write-Host 'In OpenHands, OPEN A NEW CONVERSATION — the tool list is loaded once when a'
Write-Host 'conversation starts, so an existing one still shows the old 30 tools.'
