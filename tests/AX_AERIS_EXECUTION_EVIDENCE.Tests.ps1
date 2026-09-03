$ErrorActionPreference = 'Stop'

$adapterPath = Join-Path $PSScriptRoot '..\AX_AERIS_EXECUTION_ADAPTER.ps1'
if (-not (Test-Path $adapterPath)) { throw "ADAPTER_NOT_FOUND:$adapterPath" }

$adapter = Get-Content -Raw -Path $adapterPath

# RED: a local proof artifact is not business execution evidence.
if ($adapter -match "Mutation:\s*CONTROLLED_LOCAL_RUNTIME_ARTIFACT_ONLY" -and
    $adapter -match "Execution Result:\s*VERIFIED") {
    throw 'BUSINESS_EXECUTION_EVIDENCE_GATE_VIOLATED: local proof artifact is being promoted to VERIFIED execution'
}

if ($adapter -match "Action:\s*STATUS_PROBE_AND_RUNTIME_ACTION_PROOF") {
    throw 'BUSINESS_EXECUTION_NOT_IMPLEMENTED: adapter still performs status probe/proof artifact only'
}

Write-Host 'AX_AERIS_EXECUTION_EVIDENCE_TEST=PASS'
