$ErrorActionPreference = 'Stop'
$RuntimeDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$StatePath = Join-Path $RuntimeDir 'runtime-state.json'
if (-not (Test-Path $StatePath)) { throw 'runtime-state.json not found.' }
$State = Get-Content $StatePath -Raw | ConvertFrom-Json
[pscustomobject]@{
  RuntimeStatus = $State.runtimeStatus
  NodeId = $State.nodeId
  LastHeartbeatAt = $State.lastHeartbeatAt
  ActiveJob = $State.activeJob
  LastVerifiedJob = $State.lastVerifiedJob
} | Format-List
