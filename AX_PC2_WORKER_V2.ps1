param(
  [string]$ApiUrl = $(if ($env:AX_AERIS_NODE_API_URL) { $env:AX_AERIS_NODE_API_URL } else { 'https://script.google.com/macros/s/AKfycbwz6F8EWTD7YwnGkyu4Mq_JHtBkk6nOwl9TYjWDsMsQTtS5EVj3I6hmakuW6yP_YGQH/exec' }),
  [string]$NodeId = $(if ($env:AX_PC2_NODE_ID) { $env:AX_PC2_NODE_ID } else { $env:COMPUTERNAME }),
  [string]$NodeSecret = $env:AX_PC2_NODE_SECRET,
  [int]$PollSeconds = 10,
  [int]$MaxAttempts = 3,
  [switch]$Once
)

$ErrorActionPreference = 'Stop'
$Root = 'C:\AX-Runtime'
$StatePath = Join-Path $Root 'AX-PC2-Worker-State.json'
$LogPath = Join-Path $Root 'AX-PC2-Worker-V2.log'
$ProofRoot = Join-Path $Root 'proof'
New-Item -ItemType Directory -Path $Root -Force | Out-Null
New-Item -ItemType Directory -Path $ProofRoot -Force | Out-Null

function NowUtc { return (Get-Date).ToUniversalTime().ToString('o') }
function Log([string]$m) {
  $line = "$(NowUtc) [$NodeId] $m"
  Add-Content -Path $LogPath -Value $line
  Write-Host $line
}
function Save-State([string]$status,[string]$jobId='', [int]$attempt=0, $payload=$null) {
  $state = [ordered]@{ protocol='AX PC2 WORKER v2'; nodeId=$NodeId; status=$status; currentJobId=$jobId; currentAttempt=$attempt; currentPayload=$payload; liveFinancialExecution=$false; updatedAt=(NowUtc) }
  $tmp = "$StatePath.tmp"
  $state | ConvertTo-Json -Depth 20 | Set-Content -Path $tmp -Encoding UTF8
  Move-Item $tmp $StatePath -Force
}
function Get-PropertyValue($object,[string]$name) {
  if ($null -ne $object -and $null -ne $object.PSObject.Properties[$name]) { return $object.PSObject.Properties[$name].Value }
  return $null
}
function Headers {
  if ([string]::IsNullOrWhiteSpace($NodeSecret)) { throw 'AX_PC2_NODE_SECRET_REQUIRED' }
  return @{ Accept='application/json'; 'Content-Type'='application/json' }
}
function Post-Node($body) {
  $r = Invoke-RestMethod -Uri $ApiUrl -Method Post -Headers (Headers) -Body ($body | ConvertTo-Json -Depth 20 -Compress) -TimeoutSec 30
  if ($r.success -ne $true) {
    $reason = Get-PropertyValue $r 'error'
    if ([string]::IsNullOrWhiteSpace([string]$reason)) { $reason = Get-PropertyValue (Get-PropertyValue $r 'result') 'reason' }
    if ([string]::IsNullOrWhiteSpace([string]$reason)) { $reason = 'UNKNOWN' }
    throw "NODE_API_REJECTED:$reason"
  }
  return $r.result
}
function Pull-Job {
  $result = Post-Node @{ action='node_pull'; nodeId=$NodeId; nodeSecret=$NodeSecret; version='AX-PC2-WORKER-V2' }
  if ($result.available -eq $true) { return $result }
  return $null
}
function Execute-Safe($payload, [string]$jobId) {
  $command = Get-PropertyValue $payload 'command'
  if ([string]::IsNullOrWhiteSpace([string]$command)) { $command = Get-PropertyValue $payload 'action' }
  $command = ([string]$command).Trim().ToUpperInvariant()
  $proof = Join-Path $ProofRoot "$jobId.json"
  switch ($command) {
    'TEST_EXECUTION' { }
    'CREATE_LOCAL_PROOF' { }
    default { throw "COMMAND_NOT_IN_PC2_SAFE_ALLOWLIST:$command" }
  }
  $record = [ordered]@{ protocol='AX-PC2-WORKER-V2'; jobId=$jobId; nodeId=$NodeId; command=$command; executed=$true; verified=$false; liveFinancialExecution=$false; timestamp=(NowUtc) }
  $record | ConvertTo-Json -Depth 20 | Set-Content $proof -Encoding UTF8
  $read = Get-Content -Raw $proof | ConvertFrom-Json
  if ($read.jobId -ne $jobId -or $read.nodeId -ne $NodeId -or $read.executed -ne $true -or $read.liveFinancialExecution -ne $false) { throw 'LOCAL_EXECUTION_VERIFICATION_FAILED' }
  $record.verified=$true
  $record.proofPath=$proof
  return $record
}
function Complete-Job($jobId,$execution) {
  return Post-Node @{ action='node_complete'; nodeId=$NodeId; nodeSecret=$NodeSecret; delegationJobId=$jobId; execution=$execution }
}

if ([string]::IsNullOrWhiteSpace($NodeSecret)) { throw 'AX_PC2_NODE_SECRET_REQUIRED' }
Log '=== AX PC2 WORKER V2 START ==='
Save-State 'ONLINE'

while ($true) {
  try {
    Save-State 'POLLING'
    $pulled = Pull-Job
    if ($null -eq $pulled) {
      Save-State 'IDLE'
      Log 'PULL=NO_JOB'
    }
    else {
      $jobId = [string]$pulled.delegationJobId
      $payload = $pulled.payload
      if ([string]::IsNullOrWhiteSpace($jobId)) { throw 'NODE_PULL_MISSING_JOB_ID' }
      Save-State 'CLAIMED' $jobId 0 $payload
      Log "PULL=LEASED JOB=$jobId"
      $done=$false
      for ($attempt=1; $attempt -le $MaxAttempts; $attempt++) {
        Save-State 'EXECUTING' $jobId $attempt $payload
        try {
          $execution = Execute-Safe $payload $jobId
          if ($execution.verified -ne $true -or $execution.executed -ne $true) { throw 'EXECUTION_NOT_VERIFIED' }
          $result = Complete-Job $jobId $execution
          if ($result.verified -ne $true) { throw 'NODE_COMPLETION_NOT_VERIFIED' }
          Save-State 'COMPLETED' $jobId $attempt $payload
          Log "JOB=$jobId EXECUTE=VERIFIED COMPLETE=RECORDED ATTEMPT=$attempt"
          $done=$true
          break
        }
        catch {
          Log "JOB=$jobId ATTEMPT=$attempt ERROR=$($_.Exception.Message)"
          if ($attempt -ge $MaxAttempts) {
            Save-State 'FAILED' $jobId $attempt $payload
            throw
          }
          Start-Sleep -Seconds ([Math]::Min(60, [int][Math]::Pow(2,$attempt)))
        }
      }
      if (-not $done) { throw "JOB_NOT_COMPLETED:$jobId" }
    }
  }
  catch {
    Save-State 'ERROR'
    Log "LOOP_ERROR=$($_.Exception.Message)"
  }
  if ($Once) { break }
  Start-Sleep -Seconds $PollSeconds
}

Save-State 'STOPPED'
Log '=== AX PC2 WORKER V2 STOP ==='
