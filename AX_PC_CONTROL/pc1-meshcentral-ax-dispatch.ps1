param(
  [ValidateSet('Health','DispatchIntent','RunAllowedCommand')]
  [string]$Action = 'Health',
  [string]$Intent,
  [string]$JobId,
  [string]$EventNode = 'PC1',
  [string]$Command
)

$ErrorActionPreference = 'Stop'
$ExpectedNode = 'DESKTOP-RGK6JKB'
$ExpectedNodeId = 'PC1'

function Get-RequiredEnv([string]$Name) {
  $v = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($v)) { throw "MESH_ADAPTER_CONFIG_MISSING:$Name" }
  return $v
}

$meshCtrl = Get-RequiredEnv 'AKATH_MESHCTRL_JS'
$meshUrl = Get-RequiredEnv 'AKATH_MESHCTRL_URL'
$meshUser = Get-RequiredEnv 'AKATH_MESHCTRL_LOGINUSER'
$keyFile = [Environment]::GetEnvironmentVariable('AKATH_MESHCTRL_KEYFILE')
$meshPass = [Environment]::GetEnvironmentVariable('AKATH_MESHCTRL_LOGINPASS')

if (-not (Test-Path -LiteralPath $meshCtrl)) { throw "MESHCTRL_NOT_FOUND:$meshCtrl" }
if (-not (Test-Path -LiteralPath $meshUrl)) { throw "MESH_URL_CONFIG_INVALID" }

function Invoke-MeshCtrl([string[]]$Args) {
  $all = @($Args)
  $all += @('--url', $meshUrl, '--loginuser', $meshUser)
  if (-not [string]::IsNullOrWhiteSpace($keyFile)) {
    $all += @('--loginkeyfile', $keyFile)
  } elseif (-not [string]::IsNullOrWhiteSpace($meshPass)) {
    $all += @('--loginpass', $meshPass)
  } else {
    throw 'MESH_AUTH_NOT_CONFIGURED: set AKATH_MESHCTRL_KEYFILE or AKATH_MESHCTRL_LOGINPASS'
  }
  $out = & node $meshCtrl @all 2>&1
  $code = $LASTEXITCODE
  [pscustomobject]@{ ExitCode=$code; Output=(@($out) -join [Environment]::NewLine) }
}

function Resolve-DeviceId {
  $r = Invoke-MeshCtrl @('listdevices','--json')
  if ($r.ExitCode -ne 0) { throw "MESH_LIST_DEVICES_FAILED:$($r.Output)" }
  $json = $r.Output | ConvertFrom-Json
  $items = @()
  if ($json -is [array]) { $items = $json }
  elseif ($json.devices) { $items = @($json.devices) }
  else {
    foreach ($p in $json.PSObject.Properties) {
      if ($p.Value -is [array]) { $items += @($p.Value) }
    }
  }
  $match = $items | Where-Object {
    $_.name -eq $ExpectedNode -or $_.computername -eq $ExpectedNode -or $_.computerName -eq $ExpectedNode
  } | Select-Object -First 1
  if (-not $match) { throw "MESH_DEVICE_NOT_FOUND:$ExpectedNode" }
  if (-not $match.id) { throw 'MESH_DEVICE_ID_MISSING' }
  return [string]$match.id
}

function Invoke-RemotePowerShell([string]$DeviceId,[string]$Script) {
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
  $remote = "$b=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64'));Invoke-Expression $b"
  $r = Invoke-MeshCtrl @('RunCommand','--id',$DeviceId,'--run',$remote,'--powershell','--reply')
  if ($r.ExitCode -ne 0) { throw "MESH_RUNCOMMAND_FAILED:$($r.Output)" }
  return $r.Output
}

if ($Action -eq 'Health') {
  $deviceId = Resolve-DeviceId
  $out = Invoke-RemotePowerShell $deviceId "hostname"
  if ($out -notmatch [regex]::Escape($ExpectedNode)) { throw "MESH_REMOTE_IDENTITY_MISMATCH:$out" }
  [ordered]@{status='ALIVE';nodeId=$ExpectedNodeId;computerName=$ExpectedNode;deviceId=$deviceId;remoteOutput=$out.Trim();checkedAt=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Depth 5
  exit 0
}

if ($EventNode -ne $ExpectedNodeId) { throw 'EVENT_NODE_MUST_BE_PC1' }
if ([string]::IsNullOrWhiteSpace($JobId)) { throw 'JOB_ID_MISSING' }

$allowedIntents = @(
  'NODE_HEALTH_CHECK','SYSTEM_DIAGNOSTIC','CLOSE_STALE_TERMINAL',
  'CAPTURE_AND_REVERIFY','RESTART_OWNED_RUNTIME','INCIDENT_LOCAL_DIAGNOSE'
)
if ($Action -eq 'DispatchIntent') {
  if ($allowedIntents -notcontains $Intent) { throw "INTENT_NOT_ALLOWED:$Intent" }
  $deviceId = Resolve-DeviceId
  $intentJson = [ordered]@{
    protocol='AX PC1 BRAIN1 INTENT v1'
    jobId=$JobId
    targetNode='PC1'
    intent=$Intent
    eventNode='PC1'
    source='AX_MESH_ADAPTER'
    requestedAt=[DateTime]::UtcNow.ToString('o')
  } | ConvertTo-Json -Compress
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($intentJson))
  $remote = "$root='C:\AX-Runtime\brain1-intent-queue\pending';New-Item -ItemType Directory -Path $root -Force|Out-Null;$j=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64'));Set-Content -Path (Join-Path $root ('$JobId.json')) -Value $j -Encoding UTF8"
  $out = Invoke-RemotePowerShell $deviceId $remote
  [ordered]@{status='DISPATCHED';nodeId='PC1';computerName=$ExpectedNode;jobId=$JobId;intent=$Intent;deviceId=$deviceId;remoteOutput=$out.Trim();dispatchedAt=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Depth 5
  exit 0
}

if ($Action -eq 'RunAllowedCommand') {
  if ([string]::IsNullOrWhiteSpace($Command)) { throw 'COMMAND_MISSING' }
  $allowed = @('hostname','Get-Date','Get-Process powershell,WindowsTerminal,cmd,conhost -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,MainWindowTitle')
  if ($allowed -notcontains $Command) { throw 'REMOTE_COMMAND_NOT_ALLOWED' }
  $deviceId = Resolve-DeviceId
  $out = Invoke-RemotePowerShell $deviceId $Command
  [ordered]@{status='EXECUTED';nodeId='PC1';computerName=$ExpectedNode;jobId=$JobId;command=$Command;deviceId=$deviceId;remoteOutput=$out.Trim();completedAt=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Depth 5
  exit 0
}
