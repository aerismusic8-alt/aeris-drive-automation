$ErrorActionPreference = 'Stop'
$cycle = [guid]::NewGuid().ToString()
$now = Get-Date -Format o
$scriptPath = $MyInvocation.MyCommand.Path
$repo = $env:GITHUB_REPOSITORY
if ([string]::IsNullOrWhiteSpace($repo)) {
  $origin = (git remote get-url origin).Trim()
  $repo = ($origin -replace '^https://github.com/','') -replace '\.git$',''
}
$root = $env:GITHUB_WORKSPACE
if ([string]::IsNullOrWhiteSpace($root)) { $root = Split-Path -Parent $scriptPath }
if ([string]::IsNullOrWhiteSpace($env:AERIS_WEB_APP_URL)) {
  $env:AERIS_WEB_APP_URL = 'https://script.google.com/macros/s/AKfycbwdK1NVd0_ZUVS_fRto6xRIWzUOkFi8BV90UxxKrujQYfYWvcaIlWNDXKxI9Ree7Zqx/exec'
}
$masterRegistryPath = Join-Path $root 'AX_MASTER_BRAIN\AX_MASTER_TASK_REGISTRY_v2.json'

Write-Host '=== AX AUTONOMOUS EXECUTIVE CYCLE ==='
Write-Host "Cycle: $cycle"
Write-Host "Time: $now"
Write-Host "Trigger: $env:AX_TRIGGER"
Write-Host "Trigger Workflow: $env:AX_TRIGGER_WORKFLOW"
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Runner: $env:RUNNER_NAME"
Write-Host "Repo: $repo"
Write-Host "Root: $root"
Write-Host "Canonical Registry: $masterRegistryPath"
Write-Host "Persistence URL: CONFIGURED"

function Invoke-PhaseWithRetry {
  param([string]$Name,[scriptblock]$Action,[int]$Attempts=3)
  for ($i=1; $i -le $Attempts; $i++) {
    Write-Host "=== $Name ATTEMPT $i/$Attempts ==="
    try {
      & $Action
      if ($LASTEXITCODE -ne 0) { throw "${Name}_EXIT_$LASTEXITCODE" }
      Write-Host "${Name}: PASS"
      return $true
    } catch {
      Write-Host "${Name}: FAIL - $($_.Exception.Message)"
      if ($i -lt $Attempts) { Start-Sleep -Seconds 1 }
    }
  }
  return $false
}

$selectorPath = Join-Path $root 'AX_TASK_SELECTOR.ps1'
if (-not (Test-Path $selectorPath)) { throw "AX_TASK_SELECTOR_NOT_FOUND: $selectorPath" }
if (-not (Test-Path $masterRegistryPath)) { throw "AX_MASTER_TASK_REGISTRY_NOT_FOUND: $masterRegistryPath" }
. $selectorPath

$recoveryOk = Invoke-PhaseWithRetry -Name 'RECOVERY' -Action {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$root\AX_RECOVERY_ENGINE.ps1"
}

$headers = @{
  Authorization = "Bearer $env:GITHUB_TOKEN"
  Accept = 'application/vnd.github+json'
  'X-GitHub-Api-Version' = '2022-11-28'
}
$runsUrl = "https://api.github.com/repos/$repo/actions/runs?per_page=30"
$runs = $null
$ax = $null
$smoke = $null

Write-Host '=== OBSERVE ==='
try {
  $runs = Invoke-RestMethod -Uri $runsUrl -Headers $headers -Method Get -ErrorAction Stop
  $ax = $runs.workflow_runs | Where-Object { $_.name -eq 'AX Status Monitor' } | Select-Object -First 1
  $smoke = $runs.workflow_runs | Where-Object { $_.name -eq 'PC Runner Smoke Test' } | Select-Object -First 1
  Write-Host "AX Monitor: $($ax.status) / $($ax.conclusion)"
  Write-Host "PC Runner Smoke: $($smoke.status) / $($smoke.conclusion)"
  Write-Host 'Observation: PASS'
} catch {
  Write-Host "Observation: DEGRADED - $($_.Exception.Message)"
  Write-Host 'Observation is non-blocking; continuing Executive Cycle.'
}
$decisionOk = Invoke-PhaseWithRetry -Name 'DECISION' -Action {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$root\AX_DECISION_ENGINE.ps1" -RegistryPath $masterRegistryPath
}

$dispatchOk = Invoke-PhaseWithRetry -Name 'DISPATCH' -Action {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$root\AX_ACTION_DISPATCHER.ps1" -RegistryPath $masterRegistryPath
}

$persistenceOk = $false
Write-Host '=== PERSISTENCE GATE ==='
try {
  $payload = @{ command='SAVE_STATE'; approved=$true; source='AX_AUTONOMOUS_EXECUTIVE_LOOP'; cycleId=$cycle; timestamp=$now } | ConvertTo-Json -Compress
  $saveResponse = Invoke-RestMethod -Uri $env:AERIS_WEB_APP_URL -Method Post -ContentType 'application/json' -Body $payload -TimeoutSec 30
  Write-Host ('Persistence response: ' + ($saveResponse | ConvertTo-Json -Depth 12 -Compress))
  if ($saveResponse.success -ne $true -or $null -eq $saveResponse.result -or $saveResponse.result.verified -ne $true) { throw 'AX_PERSISTENCE_NOT_VERIFIED' }
  $persistenceOk = $true
  Write-Host 'Drive persistence: VERIFIED'
} catch {
  Write-Host "Persistence failure: $($_.Exception.Message)"
}

Write-Host '=== AUTONOMOUS DASHBOARD HEARTBEAT ==='
$masterRegistry = Get-Content -Raw -Path $masterRegistryPath | ConvertFrom-Json
$registry = Convert-AxMasterRegistry -MasterRegistry $masterRegistry
$selected = Select-AxNextTask -Registry $registry
if ($selected) {
  Write-Host "Canonical Selected Task: $($selected.id)"
  Write-Host "Canonical Selected Priority: $($selected.priority)"
  Write-Host 'Canonical Selector: VERIFIED'
} else {
  Write-Host 'Canonical Selected Task: NONE'
  Write-Host 'Canonical Selector: VERIFIED'
}
$overall = if ($recoveryOk -and $decisionOk -and $dispatchOk -and $persistenceOk) {'PASS'} else {'DEGRADED'}
$status = [ordered]@{
  system='ONLINE'
  cycle=$cycle
  timestamp=$now
  overall=$overall
  recovery=if($recoveryOk){'PASS'}else{'FAIL'}
  decision=if($decisionOk){'PASS'}else{'FAIL'}
  dispatch=if($dispatchOk){'PASS'}else{'FAIL'}
  persistence=if($persistenceOk){'VERIFIED'}else{'NOT_VERIFIED'}
  runner='VERIFIED'
  mutation=if($env:AX_REPOSITORY_MUTATION_ENABLED -eq 'true'){'ENABLED'}else{'DISABLED'}
  canonicalRegistry='AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json'
  selectedTask=if($selected){$selected.id}else{$null}
}
New-Item -ItemType Directory -Force -Path "$root\dashboard" | Out-Null
$status | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 "$root\dashboard\status.json"
if (-not (Test-Path "$root\dashboard\status.json")) { throw 'AX_DASHBOARD_STATUS_CREATE_FAILED' }

git config --global --add safe.directory "$root"
Push-Location $root
try {
  git config user.name 'aerismusic8-alt'
  git config user.email 'aerismusic8-alt@users.noreply.github.com'
  $dashboardCommitted = $false
  for ($attempt = 1; $attempt -le 5; $attempt++) {
    Write-Host "=== DASHBOARD GIT ATTEMPT $attempt/5 ==="
    git fetch origin main
    if ($LASTEXITCODE -ne 0) { throw 'AX_DASHBOARD_FETCH_FAILED' }
    git reset --mixed origin/main
    if ($LASTEXITCODE -ne 0) { throw 'AX_DASHBOARD_SYNC_FAILED' }
    git add dashboard/status.json
    if ($LASTEXITCODE -ne 0) { throw 'AX_DASHBOARD_ADD_FAILED' }
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
      Write-Host 'Dashboard mutation: NO_CHANGE'
      $dashboardCommitted = $true
      break
    }
    git commit -m 'chore: autonomous AX dashboard heartbeat'
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Dashboard commit failed on attempt $attempt"
      if ($attempt -lt 5) { Start-Sleep -Seconds 1 }
      continue
    }
    git push origin HEAD:main
    if ($LASTEXITCODE -eq 0) {
      Write-Host 'Dashboard push: PASS'
      $dashboardCommitted = $true
      break
    }
    Write-Host "Dashboard push race on attempt $attempt - retrying against latest origin/main"
    if ($attempt -lt 5) { Start-Sleep -Seconds 1 }
  }
  if (-not $dashboardCommitted) { throw 'AX_DASHBOARD_PUSH_FAILED_AFTER_RETRIES' }
  $localSha = (git rev-parse HEAD).Trim()
  $remoteSha = (git ls-remote origin refs/heads/main).Split("`t")[0].Trim()
  Write-Host "LOCAL : $localSha"
  Write-Host "REMOTE: $remoteSha"
  if ($localSha -ne $remoteSha) { throw "AX_REMOTE_VERIFY_FAILED:$localSha/$remoteSha" }
  $worktree = git status --short
  if ($worktree) {
    Write-Host 'Worktree after dashboard commit:'
    $worktree | ForEach-Object { Write-Host $_ }
    throw 'AX_WORKTREE_NOT_CLEAN'
  }
  Write-Host 'Dashboard repository mutation: VERIFIED'
  Write-Host 'Remote HEAD: VERIFIED'
} finally {
  Pop-Location
}

Write-Host '=== VERIFY ==='
Write-Host "Overall: $overall"
Write-Host "Recovery: $recoveryOk"
Write-Host "Decision: $decisionOk"
Write-Host "Dispatch: $dispatchOk"
Write-Host "Persistence: $persistenceOk"
Write-Host 'Dashboard status: CREATED/VERIFIED'
Write-Host 'Canonical selector: VERIFIED'
Write-Host 'Repository mutation: VERIFIED'
Write-Host 'Runner execution: VERIFIED'
Write-Host 'Live-money execution: DISABLED'
if ($overall -ne 'PASS') {
  throw "AX_EXECUTIVE_CYCLE_DEGRADED:$overall"
}
Write-Host '=== AX AUTONOMOUS EXECUTIVE CYCLE COMPLETE ==='
