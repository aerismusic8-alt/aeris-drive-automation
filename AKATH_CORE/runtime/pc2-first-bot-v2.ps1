$ErrorActionPreference = 'Continue'
$RuntimeDir = $PSScriptRoot
$NodeId = 'PC2-MAIN'
$State = Join-Path $RuntimeDir 'runtime-state.json'
$Evidence = Join-Path $RuntimeDir 'evidence.jsonl'
$Specialist = Join-Path $RuntimeDir 'pc2-specialist.mjs'
$LoopDelaySeconds = [Math]::Max(1, [int]($env:AX_PC2_LOOP_DELAY_SECONDS ?? '2'))
$RetryDelaySeconds = [Math]::Max(1, [int]($env:AX_PC2_RETRY_DELAY_SECONDS ?? '5'))
$MaxJobs = [Math]::Max(0, [int]($env:AX_PC2_MAX_JOBS ?? '0'))

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw 'PC2_NODE_JS_NOT_FOUND' }
if (-not (Test-Path $Specialist)) { throw 'PC2_SPECIALIST_MISSING' }

$env:AX_PC1_NODE_ID = $NodeId
$env:AX_PC1_EXECUTOR_COMMAND = $node.Source

$existing = Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -like '*AKATH_CORE\runtime\main.mjs*' }
foreach ($process in $existing) {
  Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
  Write-Host "[PC2_BOOT] legacy runtime stopped pid=$($process.ProcessId)"
}

$completedJobs = 0
$failedJobs = 0
$startedRuntime = (Get-Date).ToUniversalTime().ToString('o')

Write-Host '[PC2_BOOT] =========================================='
Write-Host '[PC2_BOT] JUMTASK CONTINUOUS BOT'
Write-Host "[PC2_BOOT] NODE_ID=$NodeId"
Write-Host '[PC2_BOOT] SPECIALIST=PC2_POWERSHELL_SPECIALIST'
Write-Host '[PC2_BOOT] MODE=24/7'
Write-Host '[PC2_BOOT] CLAIM=LOCAL_JUMTASK_QUEUE'
Write-Host "[PC2_BOOT] LOOP_DELAY_SECONDS=$LoopDelaySeconds"
Write-Host "[PC2_BOOT] MAX_JOBS=$MaxJobs (0=UNLIMITED)"
Write-Host '[PC2_BOOT] =========================================='

while ($true) {
  if ($MaxJobs -gt 0 -and $completedJobs -ge $MaxJobs) {
    Write-Host "[PC2_BOT] MAX_JOBS_REACHED completed=$completedJobs"
    break
  }

  $taskId = "JUMTASK-PC2-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  $JumtaskOutput = Join-Path $RuntimeDir "jumtask-output-$taskId.txt"
  $jobFile = Join-Path $RuntimeDir "pc2-jumtask-job-$taskId.json"
  $env:AX_PC2_JUMTASK_OUTPUT = $JumtaskOutput
  $job = @{
    task_id = $taskId
    type = 'WORK'
    title = 'JUMTASK — continuous PC2 production task'
    capability = 'powershell'
    status = 'PENDING'
    payload = @{ action = 'jumtask'; capability = 'powershell' }
  } | ConvertTo-Json -Compress
  Set-Content -Path $jobFile -Value $job -Encoding UTF8

  $started = (Get-Date).ToUniversalTime().ToString('o')
  Write-Host ''
  Write-Host '[JUMTASK] =========================================='
  Write-Host "[JUMTASK] CLAIM task=$taskId node=$NodeId"
  Write-Host '[JUMTASK] START'

  try {
    $stdoutLines = @(
      & $node.Source $Specialist $jobFile 2>&1 |
        ForEach-Object {
          Write-Host $_
          $_
        }
    )
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "PC2_JUMTASK_EXECUTION_FAILED:$($stdoutLines -join "`n")" }

    $jsonLine = $stdoutLines |
      Where-Object { $_ -is [string] -and $_ -match '^\{"ok":' } |
      Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($jsonLine)) { throw 'PC2_JUMTASK_RESULT_JSON_MISSING' }
    $result = $jsonLine | ConvertFrom-Json

    if ($result.evidence.node -ne $NodeId) { throw "PC2_NODE_EVIDENCE_MISMATCH:$($result.evidence.node)" }
    if ($result.evidence.executor -ne 'PC2_POWERSHELL_SPECIALIST') { throw "PC2_EXECUTOR_MISMATCH:$($result.evidence.executor)" }
    if ($result.evidence.verification.verified -ne $true) { throw 'PC2_JUMTASK_VERIFICATION_NOT_PASSED' }
    if ($result.result.stdout -notmatch 'JUMTASK_OK') { throw 'PC2_JUMTASK_OUTPUT_NOT_VERIFIED' }
    if (-not (Test-Path $JumtaskOutput)) { throw 'PC2_JUMTASK_OUTPUT_FILE_MISSING' }
    $outputContent = Get-Content -Path $JumtaskOutput -Raw
    if ($outputContent -notmatch 'JUMTASK_OK') { throw 'PC2_JUMTASK_OUTPUT_FILE_INVALID' }

    $record = [ordered]@{
      executor = $result.evidence.executor
      capability = 'powershell'
      node = $NodeId
      hostIdentity = $result.evidence.hostIdentity
      verification = $result.evidence.verification
      execution = $result.evidence.execution
      stdout = $result.evidence.stdout
      stderr = $result.evidence.stderr
      exitCode = $result.evidence.exitCode
      jobId = $taskId
      result = $result.result
      outputFile = $JumtaskOutput
      event = 'RESULT'
      started_at = $started
      completed_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    Add-Content -Path $Evidence -Value ($record | ConvertTo-Json -Compress)

    $completedJobs++
    $state = [ordered]@{
      schemaVersion = '1.0'
      runtimeStatus = 'ONLINE'
      nodeId = $NodeId
      mode = 'CONTINUOUS_JUMTASK'
      startedAt = $startedRuntime
      lastHeartbeatAt = (Get-Date).ToUniversalTime().ToString('o')
      activeJob = $null
      lastVerifiedJob = $taskId
      lastOutputFile = $JumtaskOutput
      completedJobs = $completedJobs
      failedJobs = $failedJobs
      recovery = @{ autonomous = $true }
    }
    $state | ConvertTo-Json -Depth 20 | Set-Content -Path $State -Encoding UTF8

    Write-Host "[JUMTASK] RESULT=JUMTASK_OK task=$taskId"
    Write-Host '[JUMTASK] VERIFY verified=true'
    Write-Host "[JUMTASK] DONE completed=$completedJobs"
    Write-Host "[JUMTASK] OUTPUT=$outputContent"
  }
  catch {
    $failedJobs++
    Write-Host "[JUMTASK] FAILED task=$taskId error=$($_.Exception.Message)"
    Write-Host "[JUMTASK] RETRY_IN_SECONDS=$RetryDelaySeconds"
    $state = [ordered]@{
      schemaVersion = '1.0'
      runtimeStatus = 'ONLINE'
      nodeId = $NodeId
      mode = 'CONTINUOUS_JUMTASK'
      startedAt = $startedRuntime
      lastHeartbeatAt = (Get-Date).ToUniversalTime().ToString('o')
      activeJob = $null
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

Write-Host '[PC2_BOT] STOPPED'
Write-Host "[PC2_BOT] COMPLETED=$completedJobs FAILED=$failedJobs"