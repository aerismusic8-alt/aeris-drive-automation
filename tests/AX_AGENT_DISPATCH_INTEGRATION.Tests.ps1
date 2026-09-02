$ErrorActionPreference='Stop'
$root=$PSScriptRoot+'\..'
$gate=Get-Content -Raw "$root\AX_AGENT_ROUTE_GATE.ps1"
$dispatch=Get-Content -Raw "$root\AX_AGENT_DISPATCH.ps1"
$registry=Get-Content -Raw "$root\AX_AGENT_CAPABILITY_REGISTRY.json"
if ($dispatch -notmatch 'AX_AGENT_ROUTE_GATE') { throw 'DISPATCHER_GATE_NOT_REFERENCED' }
if ($dispatch -notmatch 'execution_enabled') { throw 'EXECUTION_CAPABILITY_CHECK_MISSING' }
if ($gate -notmatch 'AGENT_EXECUTION_NOT_VERIFIED') { throw 'GATE_REJECTION_MISSING' }
if ($registry -notmatch 'UNVERIFIED_CONNECTORS_DISABLED') { throw 'REGISTRY_POLICY_MISSING' }
if ($registry -notmatch 'GEMINI') { throw 'GEMINI_REGISTRATION_MISSING' }
if ($registry -notmatch 'COPILOT') { throw 'COPILOT_REGISTRATION_MISSING' }
Write-Host 'AX_AGENT_DISPATCH_INTEGRATION_TESTS: PASS'
