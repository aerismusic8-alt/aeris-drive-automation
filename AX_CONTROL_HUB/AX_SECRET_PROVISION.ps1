param(
  [string]$WorkerName = 'ax-control-runtime',
  [string]$RuntimeUrl = 'https://ax-control-runtime.aerismusic8.workers.dev'
)

$ErrorActionPreference = 'Stop'

function New-HighEntropySecret {
  param([int]$Length = 48)
  $bytes = New-Object byte[] $Length
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  return ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '').Substring(0, $Length)
}

function Set-WorkerSecret {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Value
  )
  Write-Host "Provisioning $Name (value is never printed)..."
  $Value | npx wrangler@latest secret put $Name --name $WorkerName
  if ($LASTEXITCODE -ne 0) { throw "WRANGLER_SECRET_PUT_FAILED:$Name" }
}

Write-Host "=== AX CONTROL RUNTIME SECRET PROVISIONING ==="
Write-Host "Worker: $WorkerName"
Write-Host "Runtime: $RuntimeUrl"
Write-Host "Security: generated in memory; never committed, displayed, or written to disk."

# Wrangler must already be authenticated to the target Cloudflare account.
npx wrangler@latest whoami
if ($LASTEXITCODE -ne 0) { throw 'CLOUDFLARE_WRANGLER_AUTH_REQUIRED' }

$mobileSecret = New-HighEntropySecret
$pcSecret = New-HighEntropySecret

try {
  Set-WorkerSecret -Name 'AX_MOBILE_INGRESS_SECRET' -Value $mobileSecret
  Set-WorkerSecret -Name 'AX_PC_PULL_SECRET' -Value $pcSecret
}
finally {
  $mobileSecret = $null
  $pcSecret = $null
}

Write-Host 'Checking deployed health booleans only...'
$health = Invoke-RestMethod -Uri "$RuntimeUrl/health" -Method Get -TimeoutSec 30
[pscustomobject]@{
  status = $health.status
  mode = $health.mode
  liveFinancialExecution = $health.liveFinancialExecution
  mobileIngressAuthConfigured = $health.mobileIngressAuthConfigured
  pcPullAuthConfigured = $health.pcPullAuthConfigured
  gatewayInbox = $health.gatewayInbox
} | Format-List

if ($health.status -ne 'ONLINE' -or
    $health.mode -ne 'FREE_ONLY' -or
    $health.liveFinancialExecution -ne $false -or
    $health.mobileIngressAuthConfigured -ne $true -or
    $health.pcPullAuthConfigured -ne $true -or
    $health.gatewayInbox -ne 'AX_GATEWAY_INBOX') {
  throw 'AX_AUTH_CONFIGURATION_VERIFICATION_FAILED'
}

Write-Host 'AX_AUTH_CONFIGURATION_VERIFIED'
Write-Host 'Secret values were not displayed or persisted.'
