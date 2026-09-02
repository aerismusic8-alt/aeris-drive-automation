param(
  [Parameter(Mandatory=$true)][string]$Agent,
  [Parameter(Mandatory=$true)][string]$TaskId
)
$ErrorActionPreference='Stop'
$registry=Get-Content -Raw "$PSScriptRoot/AX_AGENT_CAPABILITY_REGISTRY.json" | ConvertFrom-Json
if (-not $registry.agents.$Agent) { throw "AGENT_NOT_REGISTERED:$Agent" }
$cap=$registry.agents.$Agent
if ($cap.execution_enabled -ne $true) { throw "AGENT_EXECUTION_NOT_VERIFIED:$Agent" }
if ([string]::IsNullOrWhiteSpace([string]$cap.executable_connector)) { throw "AGENT_EXECUTABLE_CONNECTOR_NOT_VERIFIED:$Agent" }
if ([string]::IsNullOrWhiteSpace($TaskId)) { throw 'TASK_ID_REQUIRED' }
Write-Output "ROUTE_ACCEPTED agent=$Agent task=$TaskId"
