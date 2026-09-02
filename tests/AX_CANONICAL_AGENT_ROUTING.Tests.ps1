$ErrorActionPreference='Stop'
$root=$PSScriptRoot+'\..'
$dispatcher=Get-Content -Raw "$root\AX_ACTION_DISPATCHER.ps1"
$bridge=Get-Content -Raw "$root\AX_AGENT_ROUTING_BRIDGE.ps1"
$registry=Get-Content -Raw "$root\AX_AGENT_CAPABILITY_REGISTRY.json" | ConvertFrom-Json

if ($dispatcher -notmatch 'AX_AGENT_ROUTING_BRIDGE') { throw 'CANONICAL_DISPATCHER_AGENT_BRIDGE_MISSING' }
if ($dispatcher -notmatch 'Fallback: CANONICAL_RUNTIME') { throw 'CANONICAL_FALLBACK_MISSING' }
if ($dispatcher -notmatch 'Task Completion: NOT_CLAIMED') { throw 'FALSE_COMPLETION_GUARD_MISSING' }
if ($dispatcher -notmatch 'Test-AxTaskDependencies') { throw 'DEPENDENCY_GATE_MISSING' }
if ($bridge -notmatch 'NO_VERIFIED_HELPER_AGENT') { throw 'UNVERIFIED_AGENT_FALLBACK_MISSING' }
if ($bridge -notmatch 'exit 10') { throw 'NON_FATAL_AGENT_FALLBACK_MISSING' }
if ($registry.agents.GEMINI.execution_enabled -ne $false) { throw 'GEMINI_MUST_REMAIN_DISABLED' }
if ($registry.agents.COPILOT.execution_enabled -ne $false) { throw 'COPILOT_MUST_REMAIN_DISABLED' }
if ($registry.policy -ne 'UNVERIFIED_CONNECTORS_DISABLED') { throw 'UNVERIFIED_CONNECTOR_POLICY_MISSING' }
Write-Host 'AX_CANONICAL_AGENT_ROUTING_TESTS: PASS'
