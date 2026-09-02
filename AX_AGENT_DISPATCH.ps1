param(
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string[]]$Candidates
)
$ErrorActionPreference='Stop'
$gate = Join-Path $PSScriptRoot 'AX_AGENT_ROUTE_GATE.ps1'
if (-not (Test-Path $gate)) { throw "AX_AGENT_ROUTE_GATE_NOT_FOUND:$gate" }

foreach ($agent in $Candidates) {
  try {
    $result = & powershell.exe -ExecutionPolicy Bypass -File $gate -Agent $agent -TaskId $TaskId 2>&1
    if ($LASTEXITCODE -eq 0) {
      Write-Output "AGENT_ROUTE_SELECTED agent=$agent task=$TaskId"
      exit 0
    }
  } catch {
    continue
  }
}

Write-Output "AGENT_ROUTE_NONE_VERIFIED task=$TaskId"
exit 2
