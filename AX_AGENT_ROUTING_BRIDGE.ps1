param(
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$Domain,
  [string[]]$Candidates = @()
)

$ErrorActionPreference='Stop'

$registryPath = Join-Path $PSScriptRoot 'AX_AGENT_CAPABILITY_REGISTRY.json'
$dispatch = Join-Path $PSScriptRoot 'AX_AGENT_DISPATCH.ps1'
if (-not (Test-Path $registryPath)) { throw "AX_AGENT_CAPABILITY_REGISTRY_NOT_FOUND:$registryPath" }
if (-not (Test-Path $dispatch)) { throw "AX_AGENT_DISPATCH_NOT_FOUND:$dispatch" }

$registry = Get-Content -Raw $registryPath | ConvertFrom-Json

if ($Candidates.Count -eq 0) {
  switch ($Domain) {
    'AERIS' { $Candidates=@('GEMINI','COPILOT') }
    'AX'    { $Candidates=@('COPILOT','GEMINI') }
    default { $Candidates=@('GEMINI','COPILOT') }
  }
}

# A helper agent is selectable only when both execution permission and a
# concrete executable connector are verified. A capability record alone is
# never enough to take ownership of a task.
$verifiedCandidates = @()
foreach ($agent in $Candidates) {
  $cap = $registry.agents.$agent
  if ($null -eq $cap) { continue }
  if ($cap.execution_enabled -ne $true) { continue }
  if ([string]::IsNullOrWhiteSpace([string]$cap.executable_connector)) { continue }
  $verifiedCandidates += $agent
}

if ($verifiedCandidates.Count -eq 0) {
  Write-Output "AGENT_ROUTING=FALLBACK_TO_CANONICAL_RUNTIME task=$TaskId"
  Write-Output 'AGENT_ROUTING_REASON=NO_VERIFIED_EXECUTABLE_HELPER'
  exit 10
}

$result = & powershell.exe -ExecutionPolicy Bypass -File $dispatch -TaskId $TaskId -Candidates $verifiedCandidates 2>&1

if ($LASTEXITCODE -eq 0) {
  Write-Output ($result | Out-String).Trim()
  Write-Output 'AGENT_ROUTING=VERIFIED_AGENT_SELECTED'
  exit 0
}

Write-Output "AGENT_ROUTING=FALLBACK_TO_CANONICAL_RUNTIME task=$TaskId"
Write-Output 'AGENT_ROUTING_REASON=HELPER_ROUTE_REJECTED'
exit 10
