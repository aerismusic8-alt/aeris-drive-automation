# Expose the PC1 MCP server to the tailnet over HTTPS.
#
# Why Tailscale rather than a plain port forward:
#
#   - `tailscale serve` provisions a real TLS certificate, so the auth key is
#     not crossing the network in the clear.
#   - both ends dial out, so no inbound port is opened on the router.
#   - only devices in the same tailnet can reach it. There is no public
#     endpoint to find.
#
# Use `serve`, never `funnel`. Funnel publishes the endpoint to the whole
# internet, which is the opposite of the point here.
#
# Run on PC1 after install-pc1-winremote-mcp.ps1:
#
#   powershell -ExecutionPolicy Bypass -File install-pc1-tailscale-serve.ps1
#
# Two steps need a human once: the browser login for `tailscale up`, and
# consenting to enable HTTPS in the tailnet the first time `serve` runs. The
# script detects both and says so instead of hanging.

param(
  [int]$Port = 8090,
  [string]$RuntimeRoot = 'C:\AX-Runtime'
)

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME" }

$evidenceDir = Join-Path $RuntimeRoot 'evidence'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null

Write-Host 'STEP=TAILSCALE_PRESENT'
$ts = (Get-Command tailscale -ErrorAction SilentlyContinue).Source
if (-not $ts) {
  # Common install locations, in case PATH has not been refreshed.
  foreach ($candidate in @(
      "$env:ProgramFiles\Tailscale\tailscale.exe",
      "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe")) {
    if (Test-Path -LiteralPath $candidate) { $ts = $candidate; break }
  }
}
if (-not $ts) {
  Write-Host 'TAILSCALE_NOT_FOUND - installing'
  $winget = (Get-Command winget -ErrorAction SilentlyContinue).Source
  if (-not $winget) {
    throw 'WINGET_NOT_FOUND: install Tailscale from https://tailscale.com/download/windows and re-run'
  }
  & $winget install --id Tailscale.Tailscale -e --accept-source-agreements --accept-package-agreements
  $ts = "$env:ProgramFiles\Tailscale\tailscale.exe"
  if (-not (Test-Path -LiteralPath $ts)) { throw 'TAILSCALE_INSTALL_FAILED: binary still not found' }
}
Write-Host "TAILSCALE=$ts"

Write-Host 'STEP=LOGIN_STATE'
$statusRaw = & $ts status --json 2>$null | Out-String
$loggedIn = $false
$selfIp = $null
$dnsName = $null
if ($statusRaw) {
  try {
    $status = $statusRaw | ConvertFrom-Json
    if ($status.BackendState -eq 'Running' -and $status.Self) {
      $loggedIn = $true
      $selfIp = ($status.Self.TailscaleIPs | Select-Object -First 1)
      $dnsName = $status.Self.DNSName
    }
  } catch { }
}

if (-not $loggedIn) {
  Write-Host 'NOT_LOGGED_IN'
  Write-Host 'ACTION_REQUIRED: a human has to approve this device once.'
  Write-Host 'Running `tailscale up`. It prints a URL to open in a browser.'
  Write-Host 'The browser does not have to be on PC1; any device signed in to the'
  Write-Host 'same tailnet account can approve it.'
  & $ts up
  $statusRaw = & $ts status --json 2>$null | Out-String
  $status = $statusRaw | ConvertFrom-Json
  if ($status.BackendState -ne 'Running') { throw 'TAILSCALE_LOGIN_INCOMPLETE' }
  $selfIp = ($status.Self.TailscaleIPs | Select-Object -First 1)
  $dnsName = $status.Self.DNSName
}
Write-Host "TAILNET_IP=$selfIp DNS_NAME=$dnsName"

Write-Host 'STEP=SERVE_HTTPS'
# `serve` needs HTTPS enabled for the tailnet. The CLI asks interactively the
# first time; when that prompt is not answerable it exits non-zero and the
# message says to enable it in the admin console.
$serveOut = & $ts serve --bg $Port 2>&1 | Out-String
Write-Host "SERVE_OUTPUT=$($serveOut.Trim())"
if ($LASTEXITCODE -ne 0) {
  Write-Host 'SERVE_FAILED'
  Write-Host 'ACTION_REQUIRED: enable HTTPS certificates for the tailnet once, at'
  Write-Host '  https://login.tailscale.com/admin/dns  ->  HTTPS Certificates'
  Write-Host 'Then re-run this script. Nothing else needs changing.'
  throw "TAILSCALE_SERVE_FAILED:$serveOut"
}

Write-Host 'STEP=SERVE_STATUS'
$serveStatus = & $ts serve status 2>&1 | Out-String
Write-Host $serveStatus

# Confirm the endpoint actually answers rather than trusting the config dump.
Write-Host 'STEP=VERIFY_OVER_TAILNET'
$url = if ($dnsName) { "https://$dnsName" } else { $null }
$reachable = $false
if ($url) {
  foreach ($attempt in 1..10) {
    Start-Sleep -Seconds 3
    try {
      $r = Invoke-RestMethod -Uri "$url/health" -TimeoutSec 8
      if ($r.status -eq 'ok') { $reachable = $true; Write-Host "TAILNET_HEALTH=ok ATTEMPT=$attempt"; break }
    } catch {
      if ($attempt -eq 10) { Write-Host "LAST_ERROR=$($_.Exception.Message)" }
    }
  }
}
if (-not $reachable) {
  Write-Host 'TAILNET_HEALTH=unverified'
  Write-Host 'The serve config is in place but the endpoint did not answer. The usual'
  Write-Host 'cause is the MCP server not running on the loopback port it proxies to.'
} else {
  Write-Host "MCP_OVER_TAILNET=$url/mcp"
}

$report = [ordered]@{
  schemaVersion  = 1
  capturedAt     = (Get-Date).ToUniversalTime().ToString('o')
  hostname       = $env:COMPUTERNAME
  tailscaleExe   = $ts
  tailnetIp      = $selfIp
  dnsName        = $dnsName
  servedPort     = $Port
  mcpUrlOverTailnet = if ($url) { "$url/mcp" } else { $null }
  healthOverTailnet = if ($reachable) { 'ok' } else { 'unverified' }
  serveStatus    = ($serveStatus -split "`n" | Where-Object { $_.Trim() })
}
Set-Content -LiteralPath (Join-Path $evidenceDir 'pc1-tailscale-serve.json') `
  -Value ($report | ConvertTo-Json -Depth 6) -Encoding UTF8

Write-Host ''
Write-Host 'TAILSCALE=COMPLETE'
if ($url) {
  Write-Host ''
  Write-Host 'Call the MCP server from any tailnet machine with:'
  Write-Host "  python3 AX_PC_CONTROL/ax-winremote-mcp.py --url $url/mcp --auth-key <key> --list-tools"
  Write-Host ''
  Write-Host 'From a machine that is not in the tailnet, run tailscaled in userspace'
  Write-Host 'mode and add --tailnet-proxy socks5://127.0.0.1:1055'
}
