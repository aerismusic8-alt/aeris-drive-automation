$ErrorActionPreference='Stop'
$registry=Get-Content -Raw "$PSScriptRoot/../AX_AGENT_CAPABILITY_REGISTRY.json" | ConvertFrom-Json
foreach($agent in @('GEMINI','COPILOT')) {
  if ($registry.agents.$agent.execution_enabled -ne $false) { throw "UNVERIFIED_AGENT_MUST_BE_DISABLED:$agent" }
  if ($registry.agents.$agent.status -ne 'AVAILABLE_FOR_REVIEW') { throw "UNVERIFIED_AGENT_STATUS_INVALID:$agent" }
}
$gate=Get-Content -Raw "$PSScriptRoot/../AX_AGENT_ROUTE_GATE.ps1"
if ($gate -notmatch 'AGENT_EXECUTION_NOT_VERIFIED') { throw 'EXECUTION_GATE_MISSING' }
Write-Host 'AX_AGENT_ROUTE_GATE_TESTS: PASS'
