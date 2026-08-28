param(
  [string]$Target = "AX_MUTATION_E2E_PROOF.txt"
)

$ErrorActionPreference = "Stop"

$stamp = (Get-Date).ToUniversalTime().ToString("o")
$content = "AX MUTATION E2E PROOF`nEXECUTED_AT=$stamp`nHOST=$env:COMPUTERNAME"

& "$PSScriptRoot\AX_REPOSITORY_MUTATION_GATE.ps1" `
  -FilePath $Target `
  -Content $content `
  -CommitMessage "AX E2E mutation verification"

if ($LASTEXITCODE -ne 0) {
  throw "AX_MUTATION_E2E_FAILED"
}

Write-Host "AX_MUTATION_E2E=VERIFIED"
