$ErrorActionPreference='Stop'
$root = Split-Path -Parent $PSScriptRoot
$dispatch = Get-Content -Raw (Join-Path $root 'AX_AGENT_DISPATCH.ps1')
$bridge = Get-Content -Raw (Join-Path $root 'AX_AGENT_ROUTING_BRIDGE.ps1')

$required = @('AGENT_TASK_ACCEPTED','AGENT_TASK_EXECUTING','AGENT_TASK_RESULT','AGENT_EVIDENCE_VERIFIED','AGENT_WRITE_BACK_VERIFIED')
foreach ($token in $required) {
  if ($dispatch -notmatch [regex]::Escape($token)) { throw "DISPATCH_MISSING_CONTRACT:$token" }
}
if ($dispatch -match "exit 0\s*\n\s*}\s*catch") { }
if ($bridge -notmatch 'AGENT_EVIDENCE_VERIFIED') { throw 'BRIDGE_MISSING_VERIFIED_EVIDENCE_GATE' }
if ($bridge -notmatch 'AGENT_WRITE_BACK_VERIFIED') { throw 'BRIDGE_MISSING_WRITE_BACK_GATE' }
if ($dispatch -notmatch 'TASK_COMPLETION=NOT_CLAIMED') { throw 'DISPATCH_COMPLETION_GUARD_MISSING' }
Write-Output 'AX_AGENT_EXECUTION_CONTRACT_TESTS: PASS'
