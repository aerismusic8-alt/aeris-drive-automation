$ErrorActionPreference='Stop'
$root = Split-Path -Parent $PSScriptRoot
$dispatch = Get-Content -Raw "$root/AX_AGENT_DISPATCH.ps1"
$bridge = Get-Content -Raw "$root/AX_AGENT_ROUTING_BRIDGE.ps1"
$registry = Get-Content -Raw "$root/AX_AGENT_CAPABILITY_REGISTRY.json" | ConvertFrom-Json

if ($dispatch -notmatch 'executable_connector') { throw 'DISPATCH_CONNECTOR_REQUIRED' }
if ($dispatch -notmatch 'Test-Path \$connector') { throw 'DISPATCH_CONNECTOR_PATH_GUARD_MISSING' }
if ($dispatch -notmatch 'AGENT_TASK_ACCEPTED') { throw 'DISPATCH_ACCEPTANCE_EVIDENCE_MISSING' }
if ($dispatch -notmatch 'TASK_COMPLETION=NOT_CLAIMED') { throw 'DISPATCH_FALSE_COMPLETION_GUARD_MISSING' }
if ($bridge -notmatch 'NO_VERIFIED_EXECUTABLE_ACCEPTANCE') { throw 'BRIDGE_FALLBACK_GUARD_MISSING' }
foreach ($agent in @('GEMINI','COPILOT')) {
  if ($registry.agents.$agent.execution_enabled -ne $false) { throw "UNVERIFIED_AGENT_ENABLED:$agent" }
  if ($null -ne $registry.agents.$agent.executable_connector) { throw "UNVERIFIED_CONNECTOR_PRESENT:$agent" }
}
Write-Host 'AX_AGENT_CONNECTOR_CONTRACT_TESTS: PASS'