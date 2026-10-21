# Install the winremote MCP server on PC1.
#
# This is the piece that lets an agent actually operate the Windows desktop:
# screenshots, PowerShell, file transfer, GUI clicks, services, scheduled tasks.
# It is a standard MCP server, so any MCP client can drive it, including an
# OpenHands conversation.
#
# Run once, on PC1, from an elevated PowerShell:
#
#   powershell -ExecutionPolicy Bypass -File install-pc1-winremote-mcp.ps1
#
# The script installs the package, picks an auth key, registers an auto-start
# task, and proves the server answers on localhost before returning.
#
# Reaching it from outside PC1's own network is a separate problem. The server
# binds localhost by default and that is deliberate. To accept connections from
# another machine you need a tunnel or a forwarded port plus TLS, because a
# bearer token sent over plain HTTP across a network is not protection. The
# script prints the two supported shapes and stops there rather than opening a
# port on its own.

param(
  [string]$RuntimeRoot = 'C:\AX-Runtime',
  [int]$Port = 8090,
  # Bind address. Leave at loopback unless a tunnel or a firewall sits in front.
  [string]$BindHost = '127.0.0.1',
  # Local-only testing flag. Refused by the server on a non-loopback bind.
  [switch]$AllowInsecureRemote,
  # Pre-existing key to reuse instead of generating one.
  [string]$AuthKey
)

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME" }

$principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'ELEVATION_REQUIRED: re-run this from an elevated PowerShell'
}

$evidenceDir = Join-Path $RuntimeRoot 'evidence'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$configDir = Join-Path $RuntimeRoot 'winremote'
New-Item -ItemType Directory -Path $configDir -Force | Out-Null

Write-Host 'STEP=PYTHON'
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { throw 'PYTHON_NOT_FOUND: install Python 3.10+ and retry' }
$pyVersion = (& $python -c "import sys;print('%d.%d'%sys.version_info[:2])").Trim()
Write-Host "PYTHON=$python VERSION=$pyVersion"

Write-Host 'STEP=INSTALL_PACKAGE'
& $python -m pip install --quiet --upgrade winremote-mcp
if ($LASTEXITCODE -ne 0) { throw "PIP_INSTALL_FAILED:$LASTEXITCODE" }
$pkgVersion = (& $python -c "import winremote;print(getattr(winremote,'__version__','unknown'))").Trim()
Write-Host "PACKAGE_VERSION=$pkgVersion"

# The key is generated locally and never printed in full, so it does not end up
# in a transcript. It is stored where only the account running the task can read
# it, and it is never written into the repository.
Write-Host 'STEP=AUTH_KEY'
if ([string]::IsNullOrWhiteSpace($AuthKey)) {
  $bytes = New-Object byte[] 32
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $AuthKey = [Convert]::ToBase64String($bytes).Replace('+','-').Replace('/','_').TrimEnd('=')
}
$keyFile = Join-Path $configDir 'winremote-auth.key'
Set-Content -LiteralPath $keyFile -Value $AuthKey -Encoding ASCII -NoNewline
$acl = Get-Acl -LiteralPath $keyFile
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl','Allow')
$acl.AddAccessRule($rule)
Set-Acl -LiteralPath $keyFile -AclObject $acl
Write-Host "AUTH_KEY_FILE=$keyFile (contents not shown)"
Write-Host "AUTH_KEY_PREFIX=$($AuthKey.Substring(0,4))... (first 4 chars only)"

Write-Host 'STEP=AUTOSTART_TASK'
# The package's own installer writes a .bat into the user profile and runs it as
# the logged-on user, which stops working when that user is not logged in. A
# SYSTEM task that reads the key file directly is more reliable for a machine
# that is supposed to be reachable unattended.
$taskName = 'AERIS-PC1-WINREMOTE-MCP'
$batPath = Join-Path $configDir 'start-winremote-mcp.cmd'
$bindArgs = "--transport streamable-http --host $BindHost --port $Port"
if ($BindHost -ne '127.0.0.1' -and -not $AllowInsecureRemote) {
  # Remote binds must carry the key, so pass it from the protected file.
  $bat = @"
@echo off
set PYTHONIOENCODING=utf-8
set /p WINREMOTE_AUTH_KEY=<"$keyFile"
"$python" -m winremote $bindArgs --auth-key "%WINREMOTE_AUTH_KEY%"
"@
} else {
  $bat = @"
@echo off
set PYTHONIOENCODING=utf-8
"$python" -m winremote $bindArgs
"@
}
Set-Content -LiteralPath $batPath -Value $bat -Encoding ASCII
Write-Host "START_SCRIPT=$batPath"

$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$batPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = 'PT30S'
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
  -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit ([TimeSpan]::Zero)
$taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $taskPrincipal -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Host "TASK_REGISTERED=$taskName"

Write-Host 'STEP=HEALTH_CHECK'
$healthy = $false
foreach ($attempt in 1..20) {
  Start-Sleep -Seconds 3
  try {
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 5
    if ($r.status -eq 'ok') { $healthy = $true; Write-Host "HEALTH=ok VERSION=$($r.version) ATTEMPT=$attempt"; break }
  } catch { }
}
if (-not $healthy) { throw "MCP_SERVER_NOT_HEALTHY: http://127.0.0.1:$Port/health did not answer" }

# A real tool call, not just the health endpoint, so a server that starts but
# cannot do anything does not pass.
Write-Host 'STEP=TOOL_CALL_PROOF'
$client = Join-Path $PSScriptRoot 'ax-winremote-mcp.py'
$toolProof = $null
if (Test-Path -LiteralPath $client) {
  $toolProof = & $python $client --url "http://127.0.0.1:$Port/mcp" --call GetSystemInfo --args '{}' 2>&1 | Out-String
  Write-Host "TOOL_CALL_OUTPUT=$($toolProof.Trim())"
  if ($toolProof -notmatch '"isError":\s*false') { throw "MCP_TOOL_CALL_FAILED:$toolProof" }
} else {
  Write-Host "CLIENT_SCRIPT_MISSING=$client (skipping tool call proof)"
}

$report = [ordered]@{
  schemaVersion  = 1
  capturedAt     = (Get-Date).ToUniversalTime().ToString('o')
  hostname       = $env:COMPUTERNAME
  python         = $python
  pythonVersion  = $pyVersion
  packageVersion = $pkgVersion
  taskName       = $taskName
  bindHost       = $BindHost
  port           = $Port
  localUrl       = "http://127.0.0.1:$Port/mcp"
  authKeyFile    = $keyFile
  authKeyPrefix  = $AuthKey.Substring(0,4)
  healthOk       = $healthy
  toolCallProof  = if ($toolProof) { 'GetSystemInfo returned isError=false' } else { 'skipped' }
}
Set-Content -LiteralPath (Join-Path $evidenceDir 'pc1-winremote-mcp-install.json') `
  -Value ($report | ConvertTo-Json -Depth 6) -Encoding UTF8

Write-Host ''
Write-Host 'INSTALL=COMPLETE'
Write-Host ''
Write-Host 'The server answers only on localhost. To drive PC1 from another machine,'
Write-Host 'Tailscale is the least work: it gives TLS, needs no inbound port on the'
Write-Host 'router, and only admits machines in your own tailnet.'
Write-Host ''
Write-Host 'On PC1:'
Write-Host '  winget install --id Tailscale.Tailscale -e'
Write-Host '  tailscale up'
Write-Host '  tailscale serve --bg 8090'
Write-Host '  tailscale serve status   # prints the https://<host>.<tailnet>.ts.net URL'
Write-Host ''
Write-Host 'Then point the MCP client at that URL with the key from:'
Write-Host "  $keyFile"
Write-Host ''
Write-Host 'Use serve, not funnel. Funnel publishes the endpoint to the whole'
Write-Host 'internet; serve keeps it inside the tailnet.'
Write-Host 'Do not bind 0.0.0.0 on a routed or internet-facing network without TLS.'
