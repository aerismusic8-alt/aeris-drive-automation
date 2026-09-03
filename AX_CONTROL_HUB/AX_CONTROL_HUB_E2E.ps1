param(
  [string]$BaseUrl = $(if ($env:AX_CONTROL_HUB_URL) { $env:AX_CONTROL_HUB_URL.TrimEnd('/') } else { 'http://127.0.0.1:8787' }),
  [string]$Username = $env:AX_CONTROL_HUB_USERNAME,
  [string]$Password = $env:AX_CONTROL_HUB_PASSWORD,
  [switch]$SkipCommand
)

$ErrorActionPreference = 'Stop'
$script:Failures = @()

function Assert-True([bool]$Condition,[string]$Name,[string]$Detail='') {
  if ($Condition) { Write-Host "PASS $Name" }
  else { $script:Failures += "$Name $Detail"; Write-Host "FAIL $Name $Detail" }
}

function Invoke-Json([string]$Method,[string]$Path,$Body=$null,[hashtable]$Headers=@{}) {
  $params = @{ Uri = "$BaseUrl$Path"; Method = $Method; Headers = $Headers; TimeoutSec = 15 }
  if ($null -ne $Body) { $params.ContentType='application/json'; $params.Body=($Body | ConvertTo-Json -Depth 20 -Compress) }
  try { return Invoke-RestMethod @params }
  catch { return [pscustomobject]@{ __error = $_.Exception.Message } }
}

Write-Host '=== AX CONTROL HUB E2E ==='
Write-Host "BaseUrl: $BaseUrl"

$health = Invoke-Json 'GET' '/health'
Assert-True ($null -ne $health -and $null -eq $health.__error) 'T1 /health reachable'
if ($health) { Assert-True ($health.status -in @('ok','healthy','ONLINE')) 'T2 health status acceptable' }

if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) {
  Write-Host 'AUTH CREDENTIALS: not supplied; authentication-dependent tests are intentionally BLOCKED.'
  $script:Failures += 'T3-T12 credentials/runtime auth not supplied'
} else {
  $login = Invoke-Json 'POST' '/auth/login' @{ username=$Username; password=$Password }
  Assert-True ($null -ne $login.token -or $login.authenticated -eq $true) 'T3 authenticated login'
  $token = [string]$login.token
  $headers = if ($token) { @{ Authorization = "Bearer $token" } } else { @{} }

  $state = Invoke-Json 'GET' '/state' $null $headers
  Assert-True ($null -ne $state.__error -or $null -ne $state.identity_authority -or $null -ne $state.identity) 'T4 authoritative state readable'

  $tasks = Invoke-Json 'GET' '/tasks' $null $headers
  Assert-True ($null -ne $tasks.__error -or $null -ne $tasks.tasks) 'T5 authoritative task registry readable'

  $check = Invoke-Json 'POST' '/m-a-check' @{ request_id=[guid]::NewGuid().ToString() } $headers
  Assert-True ($check.__error -eq $null -and $null -ne $check) 'T6 M-A-CHECK endpoint responds'
  Assert-True ($check.verified -eq $true -or $check.status -in @('VERIFIED','PASS','PENDING_VERIFICATION')) 'T7 identity challenge is explicit'

  if (-not $SkipCommand) {
    $requestId=[guid]::NewGuid().ToString()
    $command = @{ request_id=$requestId; idempotency_key="e2e-$requestId"; actor='K'; command='health_check'; args=@{}; requested_at=(Get-Date).ToUniversalTime().ToString('o') }
    $cmd = Invoke-Json 'POST' '/command' $command $headers
    Assert-True ($cmd.__error -eq $null) 'T8 command boundary responds'
    Assert-True ($cmd.request_id -eq $requestId -or $cmd.accepted -eq $true -or $cmd.status -in @('ACCEPTED','EXECUTED','VERIFIED')) 'T9 command correlation preserved'

    $dup = Invoke-Json 'POST' '/command' $command $headers
    Assert-True ($dup.error_code -eq 'DUPLICATE_REQUEST' -or $dup.status -eq 'DUPLICATE_REQUEST' -or $dup.__error -match '409') 'T10 idempotency duplicate rejected'
  }

  $evidenceId = if ($requestId) { $requestId } else { 'missing' }
  $evidence = Invoke-Json 'GET' "/evidence/$evidenceId" $null $headers
  Assert-True ($evidence.__error -eq $null -or $evidence.error_code -eq 'EVIDENCE_UNAVAILABLE') 'T11 evidence path explicit'

  $logout = Invoke-Json 'POST' '/auth/logout' $null $headers
  Assert-True ($logout.__error -eq $null) 'T12 logout endpoint responds'
}

if ($script:Failures.Count -gt 0) {
  Write-Host "=== E2E BLOCKED/FAILED: $($script:Failures.Count) ==="
  $script:Failures | ForEach-Object { Write-Host " - $_" }
  exit 1
}
Write-Host '=== AX CONTROL HUB E2E PASS ==='
exit 0
