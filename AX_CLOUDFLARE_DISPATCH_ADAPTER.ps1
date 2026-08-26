param(
  [string]$RuntimeUrl = $(if (-not [string]::IsNullOrWhiteSpace($env:AX_AERIS_RUNTIME_URL)) {
    $env:AX_AERIS_RUNTIME_URL.TrimEnd('/')
  } else {
    'https://aeris-execution-runtime.aerismusic8.workers.dev'
  }),
  [int]$TimeoutSec = 15
)

$ErrorActionPreference = 'Stop'

Write-Host '=== CLOUDFLARE CONTROLLED DISPATCH ==='
Write-Host 'Mode: CONTROLLED / VERIFY-FIRST'
Write-Host "Runtime: $RuntimeUrl"
Write-Host "Timeout: ${TimeoutSec}s"

try {
  # ============================================================
  # RUNTIME HEALTH / IDENTITY PROBE
  # The current AERIS Runtime exposes GET /
  # and does not expose GET /health.
  # ============================================================

  $probeUrl = "$RuntimeUrl/"
  Write-Host "Health Probe: $probeUrl"

  $response = Invoke-WebRequest `
    -Uri $probeUrl `
    -Method Get `
    -UseBasicParsing `
    -TimeoutSec $TimeoutSec

  Write-Host "HTTP Status: $($response.StatusCode)"

  if ($response.StatusCode -ne 200) {
    throw "AERIS_RUNTIME_HTTP_$($response.StatusCode)"
  }

  $body = $response.Content | ConvertFrom-Json

  # ============================================================
  # REQUIRED RUNTIME IDENTITY
  # ============================================================

  if ($body.status -ne 'ONLINE') {
    throw 'AERIS_RUNTIME_STATUS_NOT_ONLINE'
  }

  if ($body.service -ne 'AERIS_EXTERNAL_EXECUTION_RUNTIME') {
    throw 'AERIS_RUNTIME_SERVICE_IDENTITY_MISMATCH'
  }

  if ($body.gate -ne 'GATE_3') {
    throw 'AERIS_RUNTIME_GATE_IDENTITY_MISMATCH'
  }

  # ============================================================
  # REQUIRED EXECUTION CAPABILITIES
  # ============================================================

  if ($body.appsScript -ne 'OAUTH_READY') {
    throw 'AERIS_APPS_SCRIPT_NOT_READY'
  }

  if ($body.appsScriptExecution -ne 'READY') {
    throw 'AERIS_APPS_SCRIPT_EXECUTION_NOT_READY'
  }

  if ($body.gemini -ne 'READY') {
    throw 'AERIS_GEMINI_NOT_READY'
  }

  # ============================================================
  # VERIFY EXPECTED ENDPOINT
  # ============================================================

  $executeEndpoint = $body.endpoints | Where-Object {
    $_ -eq 'POST /execute'
  }

  if (-not $executeEndpoint) {
    throw 'AERIS_EXECUTE_ENDPOINT_NOT_AVAILABLE'
  }

  # ============================================================
  # CONTROLLED DISPATCH GATE
  # ============================================================

  Write-Host "Service: $($body.service)"
  Write-Host "Status: $($body.status)"
  Write-Host "Version: $($body.version)"
  Write-Host "Gate: $($body.gate)"
  Write-Host "Runtime Mode: $($body.mode)"
  Write-Host "Apps Script: $($body.appsScript)"
  Write-Host "Apps Script Execution: $($body.appsScriptExecution)"
  Write-Host "Gemini: $($body.gemini)"
  Write-Host "Token Storage: $($body.tokenStorage)"

  Write-Host 'Cloudflare Runtime Health: AVAILABLE'
  Write-Host 'Cloudflare Runtime: READY'
  Write-Host 'Route: AERIS_EXECUTION_QUEUE'
  Write-Host 'Execution Gate: CONTROLLED'
  Write-Host 'Verification: PASSED'
  Write-Host 'Mutation: NOT_PERFORMED_BY_HEALTH_PROBE'
}
catch {
  Write-Error "CLOUDFLARE_DISPATCH_ADAPTER_FAILED: $($_.Exception.Message)"
  exit 1
}

Write-Host '=== CLOUDFLARE CONTROLLED DISPATCH COMPLETE ==='
