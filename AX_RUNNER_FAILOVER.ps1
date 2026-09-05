param(
  [bool]$Pc1Online = $false,
  [bool]$Pc2Online = $false
)

$ErrorActionPreference = 'Stop'

if ($Pc1Online) {
  Write-Output 'PC1-AUTONOMOUS-EXECUTOR'
  exit 0
}

if ($Pc2Online) {
  Write-Output 'PC2-CODING-EXECUTOR'
  exit 0
}

Write-Output 'NO_RUNNER_AVAILABLE'
exit 0
