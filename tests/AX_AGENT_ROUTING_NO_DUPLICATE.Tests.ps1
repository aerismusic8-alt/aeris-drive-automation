$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$dispatcher=Get-Content -Raw "$root\AX_ACTION_DISPATCHER.ps1"
$bridge=Get-Content -Raw "$root\AX_AGENT_ROUTING_BRIDGE.ps1"

# Regression: selecting a helper agent must never be followed by a second
# canonical runtime dispatch of the same task. The helper route must own
# execution only when a real executable connector is verified.
if ($dispatcher -notmatch '\$agentRouteSelected = \$true') { throw 'DUPLICATE_DISPATCH_GUARD_MISSING' }
if ($dispatcher -notmatch 'Canonical Runtime: SKIPPED_TO_PREVENT_DUPLICATE_EXECUTION') { throw 'DUPLICATE_CANONICAL_EXECUTION_GUARD_MISSING' }
if ($bridge -notmatch 'execution_enabled') { throw 'BRIDGE_EXECUTION_CAPABILITY_CHECK_MISSING' }
if ($bridge -notmatch 'executable_connector') { throw 'BRIDGE_EXECUTABLE_CONNECTOR_GUARD_MISSING' }
Write-Host 'AX_AGENT_ROUTING_NO_DUPLICATE_TESTS: PASS'
