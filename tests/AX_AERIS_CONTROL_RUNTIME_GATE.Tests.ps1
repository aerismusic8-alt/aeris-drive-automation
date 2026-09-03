$ErrorActionPreference='Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtime = Get-Content -Raw "$root/cloudflare/ax-control-runtime/src/index.ts"

if ($runtime -notmatch 'result\?\.accepted === true') { throw 'ACCEPTANCE_GATE_MISSING' }
if ($runtime -notmatch 'result\?\.executed === true') { throw 'EXECUTION_GATE_MISSING' }
if ($runtime -notmatch 'result\?\.verified === true') { throw 'VERIFICATION_GATE_MISSING' }
if ($runtime -notmatch 'result\?\.taskId') { throw 'TASK_ID_BINDING_MISSING' }
if ($runtime -notmatch 'evidence') { throw 'BUSINESS_EVIDENCE_GATE_MISSING' }
if ($runtime -notmatch 'writeBackVerified') { throw 'WRITE_BACK_VERIFICATION_GATE_MISSING' }
if ($runtime -notmatch 'AERIS_EXECUTION_NOT_VERIFIED') { throw 'FAIL_CLOSED_EXECUTION_GATE_MISSING' }

Write-Host 'AX_AERIS_CONTROL_RUNTIME_GATE_TESTS: PASS'