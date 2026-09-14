param(
  [string]$RegistryPath = "$PSScriptRoot\AX_MASTER_BRAIN\AX_MASTER_TASK_REGISTRY_v2.json"
)

$ErrorActionPreference = 'Stop'
$cycle = [guid]::NewGuid().ToString()
$now = Get-Date -Format o
$root = $PSScriptRoot
$repo = $env:GITHUB_REPOSITORY

if ([string]::IsNullOrWhiteSpace($repo)) {
  try { $repo = ((git remote get-url origin).Trim() -replace '^https://github.com/','') -replace '\.git$','' } catch {}
}
if ([string]::IsNullOrWhiteSpace($env:AERIS_WEB_APP_URL)) {
  $env:AERIS_WEB_APP_URL = 'https://script.google.com/macros/s/AKfycbwdK1NVd0_ZUVS_fRto6xRIWzUOkFi8BV90UxxKrujQYfYWvcaIlWNDXKxI9Ree7Zqx/exec'
}

$selectorPath = Join-Path $root 'AX_TASK_SELECTOR.ps1'
if (-not (Test-Path $selectorPath)) { throw "AX_TASK_SELECTOR_NOT_FOUND: $selectorPath" }
if (-not (Test-Path $RegistryPath)) { throw "AX_MASTER_TASK_REGISTRY_NOT_FOUND: $RegistryPath" }
. $selectorPath

Write-Host '=== AX AUTONOMOUS EXECUTIVE CYCLE V2 ==='
Write-Host "Cycle: $cycle"
Write-Host "Time: $now"
Write-Host "Trigger: $env:AX_TRIGGER"
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Runner: $env:RUNNER_NAME"
Write-Host "Canonical Registry: $RegistryPath"

function Invoke-Phase {
  param([string]$Name,[scriptblock]$Action)
  $started = Get-Date
  Write-Host "=== $Name START $($started.ToUniversalTime().ToString('o')) ==="
  try {
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "${Name}_EXIT_$LASTEXITCODE" }
    $ended = Get-Date
    Write-Host "${Name}: PASS"
    Write-Host "${Name}_ELAPSED_SECONDS=$([math]::Round(($ended-$started).TotalSeconds,2))"
    return $true
  } catch {
    $ended = Get-Date
    Write-Host "${Name}: FAIL - $($_.Exception.Message)"
    Write-Host "${Name}_ELAPSED_SECONDS=$([math]::Round(($ended-$started).TotalSeconds,2))"
    return $false
  }
}

$recoveryOk = Invoke-Phase 'RECOVERY' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$root\AX_RECOVERY_ENGINE.ps1"
}

$observeOk = Invoke-Phase 'OBSERVE' {
  if ([string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN) -or [string]::IsNullOrWhiteSpace($repo)) { throw 'GITHUB_OBSERVE_CONFIG_MISSING' }
  $headers = @{ Authorization = "Bearer $env:GITHUB_TOKEN"; Accept='application/vnd.github+json'; 'X-GitHub-Api-Version'='2022-11-28' }
  $runs = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/actions/runs?per_page=20" -Headers $headers -Method Get
  $ax = $runs.workflow_runs | Where-Object { $_.name -eq 'AX Status Monitor' } | Select-Object -First 1
  $smoke = $runs.workflow_runs | Where-Object { $_.name -eq 'PC Runner Smoke Test' } | Select-Object -First 1
  Write-Host "AX Monitor: $($ax.status) / $($ax.conclusion)"
  Write-Host "PC Runner Smoke: $($smoke.status) / $($smoke.conclusion)"
}

$decisionOk = Invoke-Phase 'DECISION' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$root\AX_DECISION_ENGINE.ps1" -RegistryPath $RegistryPath
}

$dispatchOk = Invoke-Phase 'DISPATCH' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$root\AX_ACTION_DISPATCHER.ps1" -RegistryPath $RegistryPath
}

$persistenceOk = Invoke-Phase 'PERSISTENCE' {
  $payload = @{ command='SAVE_STATE'; approved=$true; source='AX_AUTONOMOUS_EXECUTIVE_LOOP_V2'; cycleId=$cycle; timestamp=$now } | ConvertTo-Json -Compress
  try {
    $response = Invoke-WebRequest -Uri $env:AERIS_WEB_APP_URL -Method Post -ContentType 'application/json' -Body $payload -TimeoutSec 30 -UseBasicParsing
    Write-Host "PERSISTENCE_HTTP_STATUS=$($response.StatusCode)"
    Write-Host "PERSISTENCE_BODY=$($response.Content)"
    $saveResponse = $response.Content | ConvertFrom-Json
    if ($saveResponse.success -ne $true -or $null -eq $saveResponse.result -or $saveResponse.result.verified -ne $true) { throw 'AX_PERSISTENCE_NOT_VERIFIED' }
    Write-Host 'Drive persistence: VERIFIED'
  } catch {
    if ($_.Exception.Response) {
      try { Write-Host "PERSISTENCE_HTTP_STATUS=$([int]$_.Exception.Response.StatusCode.value__)" } catch {}
      try { $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); $body = $reader.ReadToEnd(); $reader.Close(); Write-Host "PERSISTENCE_BODY=$body" } catch {}
    }
    throw
  }
}

$masterRegistry = Get-Content -Raw -Path $RegistryPath | ConvertFrom-Json
$registry = Convert-AxMasterRegistry -MasterRegistry $masterRegistry
$selected = Select-AxNextTask -Registry $registry
if ($selected) {
  Write-Host "Canonical Selected Task: $($selected.id)"
  Write-Host "Canonical Selected Priority: $($selected.priority)"
} else {
  Write-Host 'Canonical Selected Task: NONE'
}

$status = [ordered]@{
  system='ONLINE'
  cycle=$cycle
  timestamp=$now
  overall=if($recoveryOk -and $observeOk -and $decisionOk -and $dispatchOk -and $persistenceOk){'PASS'}else{'DEGRADED'}
  recovery=if($recoveryOk){'PASS'}else{'FAIL'}
  observe=if($observeOk){'PASS'}else{'FAIL'}
  decision=if($decisionOk){'PASS'}else{'FAIL'}
  dispatch=if($dispatchOk){'PASS'}else{'FAIL'}
  persistence=if($persistenceOk){'VERIFIED'}else{'NOT_VERIFIED'}
  runner='VERIFIED'
  repositoryMutation='DISABLED_IN_EXECUTIVE_CYCLE'
  canonicalRegistry='AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json'
  selectedTask=if($selected){$selected.id}else{$null}
}

New-Item -ItemType Directory -Force -Path "$root\dashboard" | Out-Null
$status | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 "$root\dashboard\status.json"
Write-Host 'Dashboard status: LOCAL_PROJECTION_ONLY'
Write-Host 'Repository mutation: DISABLED_IN_EXECUTIVE_CYCLE'
Write-Host '=== VERIFY ==='
$status | ConvertTo-Json -Depth 10 -Compress | Write-Host

if ($status.overall -ne 'PASS') {
  throw "AX_EXECUTIVE_CYCLE_DEGRADED:$($status.overall)"
}
Write-Host '=== AX AUTONOMOUS EXECUTIVE CYCLE V2 COMPLETE ==='
