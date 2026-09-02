$ErrorActionPreference = 'Stop'
$doc = Get-Content -Raw "$PSScriptRoot/../docs/MULTI_AGENT_DISPATCH_ACTIVATION.md"
if ($doc -notmatch 'Dependency-safe selection remains mandatory') { throw 'DEPENDENCY_RULE_MISSING' }
if ($doc -notmatch 'real business-result evidence') { throw 'BUSINESS_EVIDENCE_GATE_MISSING' }
if ($doc -notmatch 'Unknown/unverified connectors remain DISABLED') { throw 'UNVERIFIED_CONNECTOR_GUARD_MISSING' }
if ($doc -notmatch 'Existing running jobs must not be stopped') { throw 'RUNNING_JOB_PRESERVATION_MISSING' }
Write-Host 'MULTI_AGENT_DISPATCH_POLICY_TESTS: PASS'
