$ErrorActionPreference = 'Stop'
$RuntimeDir = $PSScriptRoot
$NodeId = 'PC2-MAIN'
$State = Join-Path $RuntimeDir 'runtime-state.json'
$Evidence = Join-Path $RuntimeDir 'evidence.jsonl'
$Specialist = Join-Path $RuntimeDir 'pc2-specialist.mjs'
$JumtaskOutput = Join-Path $RuntimeDir 'jumtask-output.txt'
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw 'PC2_NODE_JS_NOT_FOUND' }
if (-not (Test-Path $Specialist)) { throw 'PC2_SPECIALIST_MISSING' }

$env:AX_PC1_NODE_ID = $NodeId
$env:AX_PC1_EXECUTOR_COMMAND = $node.Source
$env:AX_PC2_JUMTASK_OUTPUT = $JumtaskOutput

$existing = Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -like '*AKATH_CORE\runtime\main.mjs*' }
foreach ($process in $existing) {
  Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
  Write-Host "[PC2_BOOT] legacy runtime stopped pid=$($process.ProcessId)"
}

$taskId = "JUMTASK-PC2-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
$jobFile = Join-Path $RuntimeDir 'pc2-jumtask-job.json'
$job = @{
  task_id = $taskId
  type = 'WORK'
  title = 'JUMTASK — first real PC2 output task'
  capability = 'powershell'
  status = 'PENDING'
  payload = @{ action = 'jumtask'; capability = 'powershell' }
} | ConvertTo-Json -Compress
Set-Content -Path $jobFile -Value $job -Encoding UTF8

$started = (Get-Date).ToUniversalTime().ToString('o')
Write-Host '[PC2_BOOT] =========================================='
Write-Host '[PC2_BOOT] JUMTASK REAL EXECUTION'
Write-Host "[PC2_BOOT] NODE_ID=$NodeId"
Write-Host '[PC2_BOOT] SPECIALIST=PC2_POWERSHELL_SPECIALIST'
Write-Host "[PC2_BOOT] TASK_ID=$taskId"
Write-Host '[PC2_BOOT] LIVE_OUTPUT=ON'
Write-Host '[PC2_BOOT] =========================================='

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

$state = [ordered]@{
  schemaVersion = '1.0'
  runtimeStatus = 'ONLINE'
  nodeId = $NodeId
  lastHeartbeatAt = (Get-Date).ToUniversalTime().ToString('o')
  activeJob = $null
  lastVerifiedJob = $taskId
  lastOutputFile = $JumtaskOutput
  recovery = @{}
}
$state | ConvertTo-Json -Depth 20 | Set-Content -Path $State -Encoding UTF8

Remove-Item $jobFile -Force -ErrorAction SilentlyContinue
Write-Host '[PC2_BOOT] =========================================='
Write-Host "[PC2_BOOT] JUMTASK_DONE=$taskId"
Write-Host '[PC2_BOOT] JUMTASK_VERIFIED=TRUE'
Write-Host "[PC2_BOOT] OUTPUT_FILE=$JumtaskOutput"
Write-Host "[PC2_BOOT] OUTPUT=$outputContent"
Write-Host '[PC2_BOOT] =========================================='
