[CmdletBinding()]
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [string]$StatePath = '',
  [string]$TaskRegistryPath = '',
  [string]$RehydrationSpecPath = ''
)

$ErrorActionPreference = 'Stop'

function Require-File([string]$Path, [string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "SOURCE_STATE_UNAVAILABLE:$Name"
  }
  return (Get-Item -LiteralPath $Path).FullName
}

# Resolve paths without assuming a particular checkout layout.
if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Join-Path $Root 'AX_MASTER_BRAIN\AX_MASTER_STATE.json' }
if ([string]::IsNullOrWhiteSpace($TaskRegistryPath)) { $TaskRegistryPath = Join-Path $Root 'AX_MASTER_BRAIN\AX_MASTER_TASK_REGISTRY_v2.json' }
if ([string]::IsNullOrWhiteSpace($RehydrationSpecPath)) { $RehydrationSpecPath = Join-Path $Root 'AX_MASTER_BRAIN\AX_REHYDRATION_ADAPTER_SPEC.md' }

$state = Require-File $StatePath 'AX_MASTER_STATE.json'
$tasks = Require-File $TaskRegistryPath 'AX_MASTER_TASK_REGISTRY_v2.json'
$rehydration = Require-File $RehydrationSpecPath 'AX_REHYDRATION_ADAPTER_SPEC.md'

$stateJson = Get-Content -Raw -LiteralPath $state | ConvertFrom-Json
$taskJson = Get-Content -Raw -LiteralPath $tasks | ConvertFrom-Json

if ($stateJson.identity_authority -ne 'A_MASTER_BRAIN') { throw 'SOURCE_STATE_UNAVAILABLE:IDENTITY_AUTHORITY' }
if ($stateJson.authority -ne 'K_FINAL_AUTHORITY') { throw 'SOURCE_STATE_UNAVAILABLE:FINAL_AUTHORITY' }
if ($stateJson.model_independence -ne $true) { throw 'SOURCE_STATE_UNAVAILABLE:MODEL_INDEPENDENCE' }
if (-not $stateJson.identity.name) { throw 'SOURCE_STATE_UNAVAILABLE:A_IDENTITY' }
if (-not $taskJson.tasks) { throw 'SOURCE_STATE_UNAVAILABLE:TASK_REGISTRY' }

[pscustomobject]@{
  status = 'READY_FOR_RUNTIME_INTEGRATION'
  source_of_truth = 'A_MASTER_BRAIN'
  identity = [string]$stateJson.identity.name
  authority = [string]$stateJson.authority
  task_count = @($taskJson.tasks).Count
  rehydration_contract = $rehydration
  command_execution = 'NOT_STARTED'
  financial_live_execution = 'DISABLED'
  verified = $false
  note = 'This checker validates local prerequisites only; it does not claim M-A verification or command execution.'
} | ConvertTo-Json -Depth 8
