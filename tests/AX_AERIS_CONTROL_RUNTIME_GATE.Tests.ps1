$ErrorActionPreference='Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtime = Get-Content -Raw "$root/cloudflare/ax-control-runtime/src/index.ts"

function Assert-Literal([string]$Text, [string]$Needle, [string]$ErrorCode) {
  if ($Text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) { throw $ErrorCode }
}

Assert-Literal $runtime 'result?.accepted === true' 'ACCEPTANCE_GATE_MISSING'
Assert-Literal $runtime 'result?.executed === true' 'EXECUTION_GATE_MISSING'
Assert-Literal $runtime 'result?.verified === true' 'VERIFICATION_GATE_MISSING'
Assert-Literal $runtime 'const responseTaskMatches = result?.taskId === event.taskId' 'TASK_ID_BINDING_MISSING'
Assert-Literal $runtime 'hasValidBusinessEvidence(result, event.taskId)' 'BUSINESS_EVIDENCE_GATE_MISSING'
Assert-Literal $runtime 'result.evidence?.taskId' 'EVIDENCE_TASK_ID_BINDING_MISSING'
Assert-Literal $runtime 'hasVerifiedWriteBack(result)' 'WRITE_BACK_VERIFICATION_GATE_MISSING'
Assert-Literal $runtime 'writeBackVerified === true' 'WRITE_BACK_FLAG_GATE_MISSING'
Assert-Literal $runtime 'AERIS_EXECUTION_NOT_VERIFIED' 'FAIL_CLOSED_EXECUTION_GATE_MISSING'

Write-Host 'AX_AERIS_CONTROL_RUNTIME_GATE_TESTS: PASS'
