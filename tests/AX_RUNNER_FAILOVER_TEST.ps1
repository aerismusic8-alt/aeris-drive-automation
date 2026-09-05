$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..\AX_RUNNER_FAILOVER.ps1'

if (-not (Test-Path -LiteralPath $script)) {
  throw 'FAILOVER_IMPLEMENTATION_MISSING'
}

$pc2 = & $script -Pc1Online:$false -Pc2Online:$true
if ($pc2 -ne 'PC2-CODING-EXECUTOR') { throw "FAILOVER_EXPECTED_PC2_GOT:$pc2" }

$pc1 = & $script -Pc1Online:$true -Pc2Online:$true
if ($pc1 -ne 'PC1-AUTONOMOUS-EXECUTOR') { throw "PRIMARY_EXPECTED_PC1_GOT:$pc1" }

$none = & $script -Pc1Online:$false -Pc2Online:$false
if ($none -ne 'NO_RUNNER_AVAILABLE') { throw "NO_RUNNER_EXPECTED_GOT:$none" }

Write-Host 'AX_RUNNER_FAILOVER_TEST=PASS'
