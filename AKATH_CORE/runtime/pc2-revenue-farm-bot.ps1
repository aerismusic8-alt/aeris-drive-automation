$ErrorActionPreference = 'Continue'
$RuntimeDir = $PSScriptRoot
$NodeId = 'PC2-MAIN'
$StatePath = Join-Path $RuntimeDir 'revenue-farm-state.json'
$Evidence = Join-Path $RuntimeDir 'revenue-farm-evidence.jsonl'
$Specialist = Join-Path $RuntimeDir 'pc2-specialist.mjs'
$OutputRoot = Join-Path $RuntimeDir 'AERIS_REVENUE_OUTPUT'
$ControlQueuePath = Join-Path $RuntimeDir 'AX_CONTROL_QUEUE.json'
$ControlResultsDir = Join-Path $RuntimeDir 'AX_CONTROL_RESULTS'
$ControlPollSeconds = if ([string]::IsNullOrWhiteSpace($env:AX_PC2_CONTROL_POLL_SECONDS)) { 5 } else { [int]$env:AX_PC2_CONTROL_POLL_SECONDS }
$ControlBranch = if ([string]::IsNullOrWhiteSpace($env:AX_PC2_CONTROL_BRANCH)) { 'ax-pc2-production-planner' } else { $env:AX_PC2_CONTROL_BRANCH }
$ControlPollSeconds = [Math]::Max(2, $ControlPollSeconds)

$loopDelayValue = if ([string]::IsNullOrWhiteSpace($env:AX_PC2_REVENUE_LOOP_DELAY_SECONDS)) { 5 } else { [int]$env:AX_PC2_REVENUE_LOOP_DELAY_SECONDS }
$retryDelayValue = if ([string]::IsNullOrWhiteSpace($env:AX_PC2_REVENUE_RETRY_DELAY_SECONDS)) { 10 } else { [int]$env:AX_PC2_REVENUE_RETRY_DELAY_SECONDS }
$maxJobsValue = if ([string]::IsNullOrWhiteSpace($env:AX_PC2_REVENUE_MAX_JOBS)) { 0 } else { [int]$env:AX_PC2_REVENUE_MAX_JOBS }
$LoopDelaySeconds = [Math]::Max(1, $loopDelayValue)
$RetryDelaySeconds = [Math]::Max(1, $retryDelayValue)
$MaxJobs = [Math]::Max(0, $maxJobsValue)

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw 'PC2_NODE_JS_NOT_FOUND' }
if (-not (Test-Path $Specialist)) { throw 'PC2_SPECIALIST_MISSING' }
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
New-Item -ItemType Directory -Force -Path $ControlResultsDir | Out-Null

$env:AX_PC1_NODE_ID = $NodeId
$env:AX_PC1_EXECUTOR_COMMAND = $node.Source

$completedJobs = 0
$failedJobs = 0
$startedRuntime = (Get-Date).ToUniversalTime().ToString('o')
$lastControlPoll = [DateTime]::MinValue
$processedControlIds = @{}

function Write-ControlResult {
  param([object]$Result)
  $resultPath = Join-Path $ControlResultsDir "$($Result.command_id).json"
  $Result | ConvertTo-Json -Depth 30 | Set-Content -Path $resultPath -Encoding UTF8
  try {
    & git add -- $resultPath 2>$null
    & git commit -m "AX control result $($Result.command_id)" -- $resultPath 2>$null | Out-Null
    & git push origin "HEAD:$ControlBranch" 2>$null | Out-Null
    $Result.push_status = 'PUSHED'
  } catch {
    $Result.push_status = 'PUSH_FAILED'
    $Result.push_error = $_.Exception.Message
  }
  $Result | ConvertTo-Json -Depth 30 | Set-Content -Path $resultPath -Encoding UTF8
}

function Invoke-ControlCommand {
  param([object]$Command)
  $commandId = [string]$Command.command_id
  $action = [string]($Command.payload.action ?? $Command.action)
  $started = (Get-Date).ToUniversalTime().ToString('o')
  $jobFile = Join-Path $RuntimeDir "ax-control-$commandId.json"
  $job = [ordered]@{
    task_id = $commandId
    type = 'CONTROL'
    title = [string]($Command.title ?? 'AX PowerShell control')
    capability = 'control'
    action = $action
    status = 'PENDING'
    payload = $Command.payload
  } | ConvertTo-Json -Depth 30 -Compress
  Set-Content -Path $jobFile -Value $job -Encoding UTF8

  try {
    Write-Host "[AX_CONTROL] CLAIM command=$commandId node=$NodeId action=$action"
    $stdoutLines = @(
      & $node.Source $Specialist $jobFile 2>&1 |
        ForEach-Object {
          Write-Host "[AX_CONTROL] $_"
          $_
        }
    )
    $exitCode = $LASTEXITCODE
    $jsonLine = $stdoutLines | Where-Object { $_ -is [string] -and $_ -match '^\{"ok":' } | Select-Object -Last 1
    $verified = $false
    $result = $null
    $errorText = $null
    if ($jsonLine) {
      $result = $jsonLine | ConvertFrom-Json
      $verified = ($result.evidence.verification.verified -eq $true) -and ($exitCode -eq 0)
    } else {
      $errorText = 'AX_CONTROL_RESULT_JSON_MISSING'
    }

    $record = [ordered]@{
      schemaVersion = '1.0'
      command_id = $commandId
      node = $NodeId
      executor = 'PC2_POWERSHELL_SPECIALIST'
      capability = 'control'
      action = $action
      execution = if ($exitCode -eq 0) { 'POWERSHELL_EXECUTED' } else { 'POWERSHELL_FAILED' }
      verification = @{ verified = $verified }
      exitCode = $exitCode
      stdout = if ($result) { $result.evidence.stdout } else { ($stdoutLines -join "`n") }
      stderr = if ($result) { $result.evidence.stderr } else { '' }
      result = $result
      error = $errorText
      started_at = $started
      completed_at = (Get-Date).ToUniversalTime().ToString('o')
      push_status = 'PENDING'
    }
    Write-ControlResult -Result $record
    Add-Content -Path $Evidence -Value ($record | ConvertTo-Json -Depth 30 -Compress)
    Write-Host "[AX_CONTROL] DONE command=$commandId verified=$verified push=$($record.push_status)"
  } catch {
    $record = [ordered]@{
      schemaVersion = '1.0'
      command_id = $commandId
      node = $NodeId
      executor = 'PC2_POWERSHELL_SPECIALIST'
      capability = 'control'
      action = $action
      execution = 'POWERSHELL_FAILED'
      verification = @{ verified = $false }
      exitCode = -1
      stdout = ''
      stderr = $_.Exception.Message
      error = $_.Exception.Message
      started_at = $started
      completed_at = (Get-Date).ToUniversalTime().ToString('o')
      push_status = 'PENDING'
    }
    Write-ControlResult -Result $record
    Add-Content -Path $Evidence -Value ($record | ConvertTo-Json -Depth 30 -Compress)
    Write-Host "[AX_CONTROL] FAILED command=$commandId error=$($_.Exception.Message)"
  } finally {
    Remove-Item $jobFile -Force -ErrorAction SilentlyContinue
  }
}

function Sync-ControlQueue {
  param([switch]$Force)
  $now = Get-Date
  if (-not $Force -and (($now - $lastControlPoll).TotalSeconds -lt $ControlPollSeconds)) { return }
  $lastControlPoll = $now
  try {
    & git fetch origin $ControlBranch --quiet 2>$null | Out-Null
    $json = & git show "origin/$ControlBranch`:AKATH_CORE/runtime/AX_CONTROL_QUEUE.json" 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($json -join ''))) { return }
    $queue = ($json -join "`n") | ConvertFrom-Json
    foreach ($command in @($queue.commands)) {
      $id = [string]$command.command_id
      if ([string]::IsNullOrWhiteSpace($id) -or $processedControlIds.ContainsKey($id)) { continue }
      if ([string]$command.status -and [string]$command.status -ne 'PENDING') { $processedControlIds[$id] = $true; continue }
      Invoke-ControlCommand -Command $command
      $processedControlIds[$id] = $true
    }
  } catch {
    Write-Host "[AX_CONTROL] POLL_FAILED error=$($_.Exception.Message)"
  }
}

Write-Host '[PC2_REVENUE_BOT] =========================================='
Write-Host '[PC2_REVENUE_BOT] AERIS REVENUE FARM'
Write-Host "[PC2_REVENUE_BOT] NODE_ID=$NodeId"
Write-Host '[PC2_REVENUE_BOT] SPECIALIST=PC2_POWERSHELL_SPECIALIST'
Write-Host '[PC2_REVENUE_BOT] MODE=24/7'
Write-Host '[PC2_REVENUE_BOT] ACTION=youtube_short_package'
Write-Host "[PC2_REVENUE_BOT] LOOP_DELAY_SECONDS=$LoopDelaySeconds"
Write-Host "[PC2_REVENUE_BOT] CONTROL_POLL_SECONDS=$ControlPollSeconds"
Write-Host "[PC2_REVENUE_BOT] CONTROL_BRANCH=$ControlBranch"
Write-Host "[PC2_REVENUE_BOT] MAX_JOBS=$MaxJobs (0=UNLIMITED)"
Write-Host '[PC2_REVENUE_BOT] =========================================='

while ($true) {
  Sync-ControlQueue

  if ($MaxJobs -gt 0 -and $completedJobs -ge $MaxJobs) {
    Write-Host "[PC2_REVENUE_BOT] MAX_JOBS_REACHED completed=$completedJobs"
    break
  }

  $taskId = "PC2-REV-YT-SHORT-$($completedJobs + 1)-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  $jobFile = Join-Path $RuntimeDir "pc2-revenue-job-$taskId.json"
  $outputDir = Join-Path $OutputRoot $taskId
  $env:AX_PC2_REVENUE_OUTPUT = $outputDir
  $env:AX_PC2_REVENUE_TASK_ID = $taskId
  $job = [ordered]@{
    task_id = $taskId
    type = 'REVENUE'
    title = 'AERIS YouTube Short production package'
    capability = 'revenue'
    action = 'youtube_short_package'
    status = 'PENDING'
    payload = @{
      action = 'youtube_short_package'
      capability = 'revenue'
      channel = 'AERISMusicTH'
      autonomous = $true
      output = $outputDir
    }
  } | ConvertTo-Json -Depth 10 -Compress
  Set-Content -Path $jobFile -Value $job -Encoding UTF8

  $started = (Get-Date).ToUniversalTime().ToString('o')
  Write-Host ''
  Write-Host '[REVENUE] =========================================='
  Write-Host "[REVENUE] CLAIM task=$taskId node=$NodeId"
  Write-Host '[REVENUE] START action=youtube_short_package'

  try {
    $stdoutLines = @(
      & $node.Source $Specialist $jobFile 2>&1 |
        ForEach-Object {
          Write-Host $_
          $_
        }
    )
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "PC2_REVENUE_EXECUTION_FAILED:$($stdoutLines -join "`n")" }

    $jsonLine = $stdoutLines |
      Where-Object { $_ -is [string] -and $_ -match '^\{"ok":' } |
      Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($jsonLine)) { throw 'PC2_REVENUE_RESULT_JSON_MISSING' }
    $result = $jsonLine | ConvertFrom-Json

    if ($result.evidence.node -ne $NodeId) { throw "PC2_NODE_EVIDENCE_MISMATCH:$($result.evidence.node)" }
    if ($result.evidence.executor -ne 'PC2_POWERSHELL_SPECIALIST') { throw "PC2_EXECUTOR_MISMATCH:$($result.evidence.executor)" }
    if ($result.evidence.verification.verified -ne $true) { throw 'PC2_REVENUE_VERIFICATION_NOT_PASSED' }
    if ($result.result.stdout -notmatch 'YOUTUBE_SHORT_PACKAGE_READY') { throw 'PC2_REVENUE_OUTPUT_NOT_VERIFIED' }

    $manifest = Join-Path $outputDir 'manifest.json'
    $metadata = Join-Path $outputDir 'metadata.json'
    $scriptFile = Join-Path $outputDir 'script.txt'
    foreach ($file in @($manifest, $metadata, $scriptFile)) {
      if (-not (Test-Path $file)) { throw "PC2_REVENUE_OUTPUT_FILE_MISSING:$file" }
    }

    $record = [ordered]@{
      executor = $result.evidence.executor
      capability = 'revenue'
      node = $NodeId
      hostIdentity = $result.evidence.hostIdentity
      verification = $result.evidence.verification
      execution = $result.evidence.execution
      stdout = $result.evidence.stdout
      stderr = $result.evidence.stderr
      exitCode = $result.evidence.exitCode
      jobId = $taskId
      action = 'youtube_short_package'
      channel = 'AERISMusicTH'
      outputDir = $outputDir
      manifest = $manifest
      metadata = $metadata
      script = $scriptFile
      event = 'RESULT'
      started_at = $started
      completed_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    Add-Content -Path $Evidence -Value ($record | ConvertTo-Json -Depth 20 -Compress)

    $completedJobs++
    $state = [ordered]@{
      schemaVersion = '1.0'
      runtimeStatus = 'ONLINE'
      nodeId = $NodeId
      mode = 'CONTINUOUS_REVENUE_FARM'
      startedAt = $startedRuntime
      lastHeartbeatAt = (Get-Date).ToUniversalTime().ToString('o')
      lastVerifiedJob = $taskId
      lastOutputDir = $outputDir
      completedJobs = $completedJobs
      failedJobs = $failedJobs
      recovery = @{ autonomous = $true; retry = $true }
    }
    $state | ConvertTo-Json -Depth 20 | Set-Content -Path $StatePath -Encoding UTF8

    Write-Host '[REVENUE] RESULT=YOUTUBE_SHORT_PACKAGE_READY'
    Write-Host '[REVENUE] VERIFY verified=true'
    Write-Host "[REVENUE] DONE completed=$completedJobs"
    Write-Host "[REVENUE] OUTPUT=$outputDir"
  }
  catch {
    $failedJobs++
    Write-Host "[REVENUE] FAILED task=$taskId error=$($_.Exception.Message)"
    Write-Host "[REVENUE] RETRY_IN_SECONDS=$RetryDelaySeconds"
    $state = [ordered]@{
      schemaVersion = '1.0'
      runtimeStatus = 'ONLINE'
      nodeId = $NodeId
      mode = 'CONTINUOUS_REVENUE_FARM'
      startedAt = $startedRuntime
      lastHeartbeatAt = (Get-Date).ToUniversalTime().ToString('o')
      lastVerifiedJob = $null
      completedJobs = $completedJobs
      failedJobs = $failedJobs
      lastError = $_.Exception.Message
      recovery = @{ autonomous = $true; retry = $true }
    }
    $state | ConvertTo-Json -Depth 20 | Set-Content -Path $StatePath -Encoding UTF8
    Start-Sleep -Seconds $RetryDelaySeconds
  }
  finally {
    Remove-Item $jobFile -Force -ErrorAction SilentlyContinue
  }

  Start-Sleep -Seconds $LoopDelaySeconds
}

Write-Host '[PC2_REVENUE_BOT] STOPPED'
Write-Host "[PC2_REVENUE_BOT] COMPLETED=$completedJobs FAILED=$failedJobs"
