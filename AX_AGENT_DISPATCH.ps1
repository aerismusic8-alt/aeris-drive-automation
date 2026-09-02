param(
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string[]]$Candidates
)
$ErrorActionPreference='Stop'
$gate = Join-Path $PSScriptRoot 'AX_AGENT_ROUTE_GATE.ps1'
$registryPath = Join-Path $PSScriptRoot 'AX_AGENT_CAPABILITY_REGISTRY.json'
if (-not (Test-Path $gate)) { throw "AX_AGENT_ROUTE_GATE_NOT_FOUND:$gate" }
if (-not (Test-Path $registryPath)) { throw "AX_AGENT_CAPABILITY_REGISTRY_NOT_FOUND:$registryPath" }
$registry = Get-Content -Raw $registryPath | ConvertFrom-Json

foreach ($agent in $Candidates) {
  try {
    $cap = $registry.agents.$agent
    if ($null -eq $cap) { continue }
    if ($cap.execution_enabled -ne $true) { continue }
    $connector = [string]$cap.executable_connector
    if ([string]::IsNullOrWhiteSpace($connector)) { continue }
    if (-not (Test-Path $connector)) { continue }

    $gateResult = & powershell.exe -ExecutionPolicy Bypass -File $gate -Agent $agent -TaskId $TaskId 2>&1
    if ($LASTEXITCODE -ne 0) { continue }

    $connectorResult = & powershell.exe -ExecutionPolicy Bypass -File $connector -TaskId $TaskId 2>&1
    if ($LASTEXITCODE -ne 0) { continue }
    $connectorText = ($connectorResult | Out-String).Trim()
    if ($connectorText -notmatch 'AGENT_TASK_ACCEPTED') { continue }

    Write-Output $connectorText
    Write-Output "AGENT_ROUTE_SELECTED agent=$agent task=$TaskId"
    Write-Output 'AGENT_TASK_ACCEPTED'
    Write-Output 'TASK_COMPLETION=NOT_CLAIMED'
    exit 0
  } catch { continue }
}

Write-Output "AGENT_ROUTE_NONE_VERIFIED task=$TaskId"
Write-Output 'AGENT_ROUTE_REASON=NO_EXECUTABLE_CONNECTOR_ACCEPTED'
exit 2
