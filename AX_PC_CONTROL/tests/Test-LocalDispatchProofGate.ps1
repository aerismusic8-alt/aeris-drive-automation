$ErrorActionPreference = 'Stop'

$workflowPath = Join-Path $env:GITHUB_WORKSPACE '.github/workflows/ax-pc2-local-dispatch-e2e.yml'
$workflow = Get-Content $workflowPath -Raw

if ($workflow -match 'Sort-Object LastWriteTime -Descending \| Select-Object -First 1') {
    throw 'STALE_PROOF_SELECTOR_PRESENT'
}

$jobBindingPattern = 'AX_DISPATCH_JOB_ID:\s*AX-PC2-DISPATCH-\$\{\{\s*github\.run_id\s*\}\}-\$\{\{\s*github\.run_attempt\s*\}\}'
if ($workflow -notmatch $jobBindingPattern) {
    throw 'CURRENT_RUN_ID_OR_ATTEMPT_NOT_BOUND'
}

if ($workflow -notmatch 'dispatch\\\$\{JobId\}\.json') {
    throw 'EXACT_DISPATCH_RECORD_NOT_VERIFIED'
}

Write-Host 'LOCAL_DISPATCH_PROOF_GATE_TEST=PASSED'
