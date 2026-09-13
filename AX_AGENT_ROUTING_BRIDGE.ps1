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
    'AERIS' { $Candidates=@('GEMINI_API','OPENAI') }
    'AX'    { $Candidates=@('OPENAI','GEMINI_API') }
    default { $Candidates=@('GEMINI_API','OPENAI') }
  }
}

# Capability metadata alone never grants execution ownership.
# Candidate names must match active executable entries in the capability registry.
foreach ($agent in $Candidates) {
  $cap = $registry.agents.$agent
  if ($null -eq $cap) { continue }
  if ($cap.execution_enabled -ne $true) { continue }
  $connector = [string]$cap.executable_connector
  if ([string]::IsNullOrWhiteSpace($connector)) { continue }
  if (-not (Test-Path $connector)) { continue }

  try {
    # Pass one candidate as a scalar across the native PowerShell process boundary.
    # Passing @($agent) can be rebound positionally by the child process on Windows.
    $route = & powershell.exe -ExecutionPolicy Bypass -File $dispatch -TaskId $TaskId -Candidates $agent 2>&1
    $routeText = ($route | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and
        $routeText -match 'AGENT_TASK_ACCEPTED' -and
        $routeText -match 'AGENT_TASK_EXECUTING' -and
        $routeText -match 'AGENT_TASK_RESULT' -and
        $routeText -match 'AGENT_EVIDENCE_VERIFIED' -and
        $routeText -match 'AGENT_WRITE_BACK_VERIFIED') {
      Write-Output $routeText
      Write-Output "AGENT_ROUTING=VERIFIED_EXECUTION_CONTRACT agent=$agent task=$TaskId"
      Write-Output 'TASK_COMPLETION=NOT_CLAIMED'
      exit 0
    }
  } catch { continue }
}

Write-Output "AGENT_ROUTING=FALLBACK_TO_CANONICAL_RUNTIME task=$TaskId"
Write-Output 'AGENT_ROUTING_REASON=NO_VERIFIED_HELPER_AGENT:NO_VERIFIED_EXECUTABLE_ACCEPTANCE:NO_VERIFIED_FULL_EXECUTION_CONTRACT'
exit 10
