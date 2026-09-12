$ErrorActionPreference = 'Stop'

$workflowPath = Join-Path $env:GITHUB_WORKSPACE '.github/workflows/ax-pc2-local-dispatch-e2e.yml'
$workflow = Get-Content $workflowPath -Raw

if ($workflow.Contains('Sort-Object LastWriteTime -Descending | Select-Object -First 1')) {
    throw 'STALE_PROOF_SELECTOR_PRESENT'
}
if (-not $workflow.Contains('GITHUB_RUN_ID')) {
    throw 'CURRENT_RUN_ID_NOT_BOUND'
}
if (-not $workflow.Contains('GITHUB_RUN_ATTEMPT')) {
    throw 'CURRENT_RUN_ATTEMPT_NOT_BOUND'
}
if (-not $workflow.Contains('$recordPath = Join-Path $dispatchDir "$jobId.json"'.Replace('\"','"'))) {
    throw 'EXACT_DISPATCH_RECORD_NOT_VERIFIED'
}
if (-not $workflow.Contains('-JobId $env:AX_DISPATCH_JOB_ID')) {
    throw 'DISPATCH_JOB_ID_NOT_PASSED_TO_DISPATCHER'
}

Write-Host 'LOCAL_DISPATCH_PROOF_GATE_TEST=PASSED'
