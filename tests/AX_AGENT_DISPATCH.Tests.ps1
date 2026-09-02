$ErrorActionPreference='Stop'
$root = Split-Path -Parent $PSScriptRoot
$registry = Get-Content -Raw "$root/AX_AGENT_CAPABILITY_REGISTRY.json" | ConvertFrom-Json
foreach ($agent in @('GEMINI','COPILOT')) {
  if ($registry.agents.$agent.execution_enabled -ne $false) { throw "UNVERIFIED_AGENT_ENABLED:$agent" }
  if ($registry.agents.$agent.status -ne 'AVAILABLE_FOR_REVIEW') { throw "UNEXPECTED_AGENT_STATUS:$agent" }
}
$gate = Get-Content -Raw "$root/AX_AGENT_ROUTE_GATE.ps1"
if ($gate -notmatch 'execution_enabled -ne \$true') { throw 'ROUTE_GATE_MISSING_EXECUTION_CHECK' }
$dispatch = Get-Content -Raw "$root/AX_AGENT_DISPATCH.ps1"
if ($dispatch -notmatch 'AGENT_ROUTE_NONE_VERIFIED') { throw 'NO_VERIFIED_ROUTE_GUARD_MISSING' }
Write-Host 'AX_AGENT_DISPATCH_TESTS: PASS'
