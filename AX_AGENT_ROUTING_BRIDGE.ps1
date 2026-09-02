param(
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$Domain,
  [string[]]$Candidates = @()
)

$ErrorActionPreference='Stop'

$dispatch = Join-Path $PSScriptRoot 'AX_AGENT_DISPATCH.ps1'
if (-not (Test-Path $dispatch)) { throw "AX_AGENT_DISPATCH_NOT_FOUND:$dispatch" }

if ($Candidates.Count -eq 0) {
  switch ($Domain) {
    'AERIS' { $Candidates=@('GEMINI','COPILOT') }
    'AX'    { $Candidates=@('COPILOT','GEMINI') }
    default { $Candidates=@('GEMINI','COPILOT') }
  }
}

$result = & powershell.exe -ExecutionPolicy Bypass -File $dispatch -TaskId $TaskId -Candidates $Candidates 2>&1

if ($LASTEXITCODE -eq 0) {
  Write-Output ($result | Out-String).Trim()
  Write-Output 'AGENT_ROUTING=VERIFIED_AGENT_SELECTED'
  exit 0
}

# Unverified/unavailable helper agents are capacity-unavailable, not task failure.
Write-Output "AGENT_ROUTING=FALLBACK_TO_CANONICAL_RUNTIME task=$TaskId"
Write-Output 'AGENT_ROUTING_REASON=NO_VERIFIED_HELPER_AGENT'
exit 10
