$ErrorActionPreference = 'Stop'

$workflowPath = Join-Path $env:GITHUB_WORKSPACE '.github/workflows/ax-pc2-local-dispatch-e2e.yml'
$workflow = Get-Content $workflowPath -Raw

if ($workflow -match 'Sort-Object LastWriteTime -Descending \| Select-Object -First 1') {
    throw 'STALE_PROOF_SELECTOR_PRESENT'
}
if ($workflow -notmatch 'GITHUB_RUN_ID') {
    throw 'CURRENT_RUN_ID_NOT_BOUND'
}
if ($workflow -notmatch 'GITHUB_RUN_ATTEMPT') {
    throw 'CURRENT_RUN_ATTEMPT_NOT_BOUND'
}
if ($workflow -notmatch 'dispatch\\\$\{JobId\}\.json') {
    throw 'EXACT_DISPATCH_RECORD_NOT_VERIFIED'
}

Write-Host 'LOCAL_DISPATCH_PROOF_GATE_TEST=PASSED'
