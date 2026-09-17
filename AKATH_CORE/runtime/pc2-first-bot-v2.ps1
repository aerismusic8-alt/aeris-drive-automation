$ErrorActionPreference = 'Stop'
$RuntimeDir = $PSScriptRoot
$NodeId = 'PC2-MAIN'
$State = Join-Path $RuntimeDir 'runtime-state.json'
$Evidence = Join-Path $RuntimeDir 'evidence.jsonl'
$Specialist = Join-Path $RuntimeDir 'pc2-specialist.mjs'
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

$taskId = "AKATH-PC2-FIRST-BOT-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
$jobFile = Join-Path $RuntimeDir 'pc2-first-bot-job.json'
$job = @{
  task_id = $taskId
  capability = 'powershell'
  payload = @{ action = 'runtime_identity' }
} | ConvertTo-Json -Compress
Set-Content -Path $jobFile -Value $job -Encoding UTF8

$started = (Get-Date).ToUniversalTime().ToString('o')
Write-Host "[PC2_BOOT] NODE_ID=$NodeId"
Write-Host "[PC2_BOOT] SPECIALIST=PC2_POWERSHELL_SPECIALIST"
Write-Host "[PC2_BOOT] FIRST_BOT_JOB=$taskId"

$stdout = & $node.Source $Specialist $jobFile 2>&1 | Out-String
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) { throw "PC2_FIRST_BOT_EXECUTION_FAILED:$stdout" }

$result = $stdout | ConvertFrom-Json
if ($result.evidence.node -ne $NodeId) { throw "PC2_NODE_EVIDENCE_MISMATCH:$($result.evidence.node)" }
if ($result.evidence.executor -ne 'PC2_POWERSHELL_SPECIALIST') { throw "PC2_EXECUTOR_MISMATCH:$($result.evidence.executor)" }
if ($result.evidence.verification.verified -ne $true) { throw 'PC2_VERIFICATION_NOT_PASSED' }
if ([string]::IsNullOrWhiteSpace($result.result.hostIdentity.computerName)) { throw 'PC2_HOST_IDENTITY_MISSING' }

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
  recovery = @{}
}
$state | ConvertTo-Json -Depth 20 | Set-Content -Path $State -Encoding UTF8

Remove-Item $jobFile -Force -ErrorAction SilentlyContinue
Write-Host "[PC2_BOOT] FIRST_BOT_JOB_VERIFIED=$taskId"
Write-Host '[PC2_BOOT] RUNTIME_STATUS=ONLINE'
Write-Host '[PC2_BOOT] NODE_ID=PC2-MAIN'
Write-Host "[PC2_BOOT] HOST=$($result.result.hostIdentity.computerName)"
Write-Host '[PC2_BOOT] CONTINUOUS_RUNTIME=ONLINE'
Write-Host '[PC2_BOOT] FIRST_BOT_JOB=VERIFIED'
