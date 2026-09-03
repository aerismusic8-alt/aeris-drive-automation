param(
  [string]$WorkerName = 'ax-control-runtime'
)

$ErrorActionPreference = 'Stop'

Write-Host "AX Secret Provisioning: $WorkerName"
Write-Host "Enter a unique high-entropy value for AX_MOBILE_INGRESS_SECRET. It will be sent only to Cloudflare Wrangler."
npx wrangler@latest secret put AX_MOBILE_INGRESS_SECRET --name $WorkerName

Write-Host "Enter a unique high-entropy value for AX_PC_PULL_SECRET. It will be sent only to Cloudflare Wrangler."
npx wrangler@latest secret put AX_PC_PULL_SECRET --name $WorkerName

Write-Host "Checking boolean auth status only (secret values are never printed)."
$health = Invoke-RestMethod -Uri "https://ax-control-runtime.aerismusic8.workers.dev/health" -Method Get
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
