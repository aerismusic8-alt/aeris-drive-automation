param(
  [string]$WebAppUrl = $(if ($env:AERIS_WEB_APP_URL) { $env:AERIS_WEB_APP_URL.TrimEnd('/') } else { 'https://script.google.com/macros/s/AKfycbwdK1NVd0_ZUVS_fRto6xRIWzUOkFi8BV90UxxKrujQYfYWvcaIlWNDXKxI9Ree7Zqx/exec' }),
  [string]$RuntimeUrl = $(if ($env:AX_AERIS_RUNTIME_URL) { $env:AX_AERIS_RUNTIME_URL.TrimEnd('/') } else { 'https://aeris-execution-runtime.aerismusic8.workers.dev' }),
  [string]$NodeId = $(if ($env:AX_NODE_ID) { $env:AX_NODE_ID } else { "$env:COMPUTERNAME-AX-NODE" }),
  [string]$Agent = $(if ($env:AX_NODE_AGENT) { $env:AX_NODE_AGENT } else { 'AX' }),
  [string]$SecretPath = $(if ($env:AX_NODE_SECRET_PATH) { $env:AX_NODE_SECRET_PATH } else { "$env:USERPROFILE\.aeris\node-secret.json" }),
  [int]$IntervalSec = 60,
  [switch]$Once
)

$ErrorActionPreference = 'Stop'

function Invoke-AerisPost {
  param([hashtable]$Payload)
  $json = $Payload | ConvertTo-Json -Depth 20 -Compress
  Invoke-RestMethod -Uri $WebAppUrl -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 30
}

function Save-NodeSecret {
  param([string]$Secret)
  $dir = Split-Path -Parent $SecretPath
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $obj = @{ nodeId = $NodeId; nodeSecret = $Secret; savedAt = (Get-Date).ToUniversalTime().ToString('o') }
  $obj | ConvertTo-Json -Compress | Set-Content -Path $SecretPath -Encoding UTF8
  try {
    icacls $SecretPath /inheritance:r /grant:r "$env:USERNAME`:F" | Out-Null
  } catch { Write-Host 'Secret ACL hardening: skipped' }
}

function Load-NodeSecret {
  if (-not (Test-Path $SecretPath)) { return $null }
  try {
    $obj = Get-Content -Raw -Path $SecretPath | ConvertFrom-Json
    if ($obj.nodeId -eq $NodeId -and -not [string]::IsNullOrWhiteSpace($obj.nodeSecret)) { return [string]$obj.nodeSecret }
  } catch { Write-Host "Secret file invalid; registration will be attempted." }
  return $null
}

function Register-Node {
  if ([string]::IsNullOrWhiteSpace($env:AERIS_NODE_BOOTSTRAP_SECRET)) {
    throw 'AERIS_NODE_BOOTSTRAP_SECRET_REQUIRED_FOR_FIRST_REGISTRATION'
  }
  Write-Host "REGISTER node=$NodeId agent=$Agent"
  $r = Invoke-AerisPost @{
    action='node_register'
    nodeId=$NodeId
    agent=$Agent
    capabilities=@('text_generation','structured_data_parsing','logical_reasoning','code_analysis','external_network_execution')
    bootstrapSecret=$env:AERIS_NODE_BOOTSTRAP_SECRET
  }
  if ($r.success -ne $true -or $r.result.verified -ne $true -or [string]::IsNullOrWhiteSpace($r.result.nodeSecret)) {
    throw "NODE_REGISTER_FAILED:$($r | ConvertTo-Json -Depth 10 -Compress)"
  }
  Save-NodeSecret -Secret ([string]$r.result.nodeSecret)
  Write-Host 'REGISTER: VERIFIED'
  return [string]$r.result.nodeSecret
}

function Get-NodeSecret {
  $secret = Load-NodeSecret
  if ($secret) { return $secret }
  return Register-Node
}

function Send-Heartbeat {
  param([string]$Secret)
  $r = Invoke-AerisPost @{
    action='node_heartbeat'; nodeId=$NodeId; nodeSecret=$Secret; status='ONLINE'; version='AX_NODE_RUNNER_1.0'
  }
  if ($r.success -ne $true -or $r.result.verified -ne $true) { throw "NODE_HEARTBEAT_FAILED:$($r | ConvertTo-Json -Depth 10 -Compress)" }
  Write-Host 'HEARTBEAT: VERIFIED'
}

function Pull-Job {
  param([string]$Secret)
  $r = Invoke-AerisPost @{
    action='node_pull'; nodeId=$NodeId; nodeSecret=$Secret
  }
  if ($r.success -ne $true -or $r.result.verified -ne $true) { throw "NODE_PULL_FAILED:$($r | ConvertTo-Json -Depth 10 -Compress)" }
  return $r.result
}

function Execute-Job {
  param($Job)
  $jobId = [string]$Job.delegationJobId
  $payload = $Job.payload
  $command = [string]$payload.command
  if ([string]::IsNullOrWhiteSpace($command)) { $command = [string]$payload.type }
  if ([string]::IsNullOrWhiteSpace($command)) { throw 'NODE_JOB_COMMAND_MISSING' }

  Write-Host "EXECUTE job=$jobId command=$command"
  $r = Invoke-RestMethod -Uri "$RuntimeUrl/execute" -Method Post -ContentType 'application/json' -Body (@{
    jobId=$jobId
    command=$command
    payload=$payload
    source='AX_NODE_RUNNER'
  } | ConvertTo-Json -Depth 20 -Compress) -TimeoutSec 60

  if ($r.accepted -ne $true -or $r.executed -ne $true -or $r.verified -ne $true) {
    throw "NODE_EXTERNAL_EXECUTION_NOT_VERIFIED:$($r | ConvertTo-Json -Depth 20 -Compress)"
  }
  Write-Host "EXECUTE: VERIFIED provider=$($r.provider) model=$($r.model)"
  return $r
}

function Complete-Job {
  param([string]$Secret,[string]$JobId,$Execution)
  $r = Invoke-AerisPost @{
    action='node_complete'; nodeId=$NodeId; nodeSecret=$Secret; delegationJobId=$JobId; execution=$Execution
  }
  if ($r.success -ne $true -or $r.result.verified -ne $true -or $r.result.status -ne 'NODE_JOB_COMPLETED') {
    throw "NODE_COMPLETE_FAILED:$($r | ConvertTo-Json -Depth 10 -Compress)"
  }
  Write-Host "COMPLETE: VERIFIED job=$JobId"
}

function Invoke-NodeCycle {
  $secret = Get-NodeSecret
  try {
    Send-Heartbeat -Secret $secret
  } catch {
    if ($_.Exception.Message -match 'NODE_NOT_TRUSTED|NODE_AUTHENTICATION_FAILED') {
      Write-Host 'Stored node credential rejected; re-registration requires bootstrap secret.'
      Remove-Item -Force -ErrorAction SilentlyContinue $SecretPath
      $secret = Register-Node
      Send-Heartbeat -Secret $secret
    } else { throw }
  }

  $job = Pull-Job -Secret $secret
  if ($job.available -ne $true) {
    Write-Host 'PULL: NO_NODE_JOB_AVAILABLE'
    return
  }

  $execution = Execute-Job -Job $job
  Complete-Job -Secret $secret -JobId ([string]$job.delegationJobId) -Execution $execution
}

Write-Host '=== AX NODE RUNNER 1.0 ==='
Write-Host "Node: $NodeId"
Write-Host "Agent: $Agent"
Write-Host "WebApp: $WebAppUrl"
Write-Host "Runtime: $RuntimeUrl"
Write-Host "IntervalSec: $IntervalSec"
Write-Host 'Live financial execution: DISABLED'

if ($Once) {
  Invoke-NodeCycle
  Write-Host '=== AX NODE RUNNER ONCE COMPLETE ==='
  exit 0
}

while ($true) {
  $cycle = [guid]::NewGuid().ToString()
  Write-Host "=== NODE CYCLE $cycle ==="
  try {
    Invoke-NodeCycle
    Write-Host 'CYCLE: PASS'
  } catch {
    Write-Host "CYCLE: FAIL - $($_.Exception.Message)"
  }
  Start-Sleep -Seconds ([Math]::Max(5,$IntervalSec))
}
