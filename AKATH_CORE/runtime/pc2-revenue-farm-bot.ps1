$ErrorActionPreference = 'Continue'
$RuntimeDir = $PSScriptRoot
$NodeId = 'PC2-MAIN'
$State = Join-Path $RuntimeDir 'revenue-farm-state.json'
$Evidence = Join-Path $RuntimeDir 'revenue-farm-evidence.jsonl'
$Specialist = Join-Path $RuntimeDir 'pc2-specialist.mjs'
$OutputRoot = Join-Path $RuntimeDir 'AERIS_REVENUE_OUTPUT'

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

$env:AX_PC1_NODE_ID = $NodeId
$env:AX_PC1_EXECUTOR_COMMAND = $node.Source

$completedJobs = 0
$failedJobs = 0
$startedRuntime = (Get-Date).ToUniversalTime().ToString('o')

Write-Host '[PC2_REVENUE_BOT] =========================================='
Write-Host '[PC2_REVENUE_BOT] AERIS REVENUE FARM'
Write-Host "[PC2_REVENUE_BOT] NODE_ID=$NodeId"
Write-Host '[PC2_REVENUE_BOT] SPECIALIST=PC2_POWERSHELL_SPECIALIST'
Write-Host '[PC2_REVENUE_BOT] MODE=24/7'
Write-Host '[PC2_REVENUE_BOT] ACTION=youtube_short_package'
Write-Host "[PC2_REVENUE_BOT] LOOP_DELAY_SECONDS=$LoopDelaySeconds"
Write-Host "[PC2_REVENUE_BOT] MAX_JOBS=$MaxJobs (0=UNLIMITED)"
Write-Host '[PC2_REVENUE_BOT] =========================================='

while ($true) {
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
    $state | ConvertTo-Json -Depth 20 | Set-Content -Path $State -Encoding UTF8

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
    $state | ConvertTo-Json -Depth 20 | Set-Content -Path $State -Encoding UTF8
    Start-Sleep -Seconds $RetryDelaySeconds
  }
  finally {
    Remove-Item $jobFile -Force -ErrorAction SilentlyContinue
  }

  Start-Sleep -Seconds $LoopDelaySeconds
}

Write-Host '[PC2_REVENUE_BOT] STOPPED'
Write-Host "[PC2_REVENUE_BOT] COMPLETED=$completedJobs FAILED=$failedJobs"
