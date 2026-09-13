param(
  [Parameter(Mandatory=$false)][string]$TaskId,
  [Parameter(Mandatory=$false)][ValidateSet('health','runner-status','service-status','git-status','process-status','task-status','terminal-powershell')][string]$Command = 'health',
  [Parameter(Mandatory=$false)][string]$NodeId = 'PC2-CODING-EXECUTOR',
  [Parameter(Mandatory=$false)][string]$ControlRuntimeUrl = 'https://ax-control-runtime.aerismusic8.workers.dev',
  [Parameter(Mandatory=$false)][switch]$Enqueue,
  [Parameter(Mandatory=$false)][hashtable]$Arguments = @{},
  [Parameter(Mandatory=$false)][string]$Repository = 'aerismusic8-alt/aeris-drive-automation'
)

$ErrorActionPreference = 'Stop'

function New-AxPcDispatchEvent {
  param([string]$TaskId,[string]$Command,[hashtable]$Arguments=@{},[string]$NodeId,[string]$Repository)
  $requestId = [guid]::NewGuid().ToString()
  $content = @{ operation=$Command; args=$Arguments } | ConvertTo-Json -Depth 10 -Compress
  [pscustomobject]@{
    id=$requestId; requestId=$requestId; request_id=$requestId
    taskId=$TaskId; task_id=$TaskId
    repository=$Repository; repositoryFullName=$Repository; repo=$Repository
    domain='PC'; targetType='PC_NODE'; nodeId=$NodeId
    command=$Command; action=$Command; arguments=$Arguments
    content_type=$Command; content=$content
    priority=1; createdAt=(Get-Date).ToUniversalTime().ToString('o')
    source='AX_PC_DISPATCH_GATEWAY'
  }
}

function Test-AxPcDispatchCompletion {
  param([Parameter(Mandatory=$true)][string[]]$Lifecycle)
  return ($Lifecycle -contains 'VERIFIED')
}

function Invoke-AxPcDispatchGateway {
  param([string]$TaskId,[string]$Command,[string]$NodeId,[string]$ControlRuntimeUrl,[hashtable]$Arguments=@{},[string]$Repository)
  $event = New-AxPcDispatchEvent -TaskId $TaskId -Command $Command -Arguments $Arguments -NodeId $NodeId -Repository $Repository
  $headers = @{ 'Content-Type'='application/json'; 'X-AERIS-REPOSITORY'=$Repository }
  if ($env:GITHUB_TOKEN) { $headers.Authorization="Bearer $env:GITHUB_TOKEN" }
  $started=Get-Date
  $response=Invoke-RestMethod -Uri "$($ControlRuntimeUrl.TrimEnd('/'))/enqueue" -Method Post -Headers $headers -Body ($event|ConvertTo-Json -Depth 10 -Compress) -TimeoutSec 15
  $elapsedMs=[int]((Get-Date)-$started).TotalMilliseconds
  if ($response.accepted -ne $true) { throw "PC_GATEWAY_ENQUEUE_REJECTED:$($event.requestId)" }
  [pscustomobject]@{requestId=$event.requestId;taskId=$event.taskId;repository=$event.repository;nodeId=$event.nodeId;command=$event.command;lifecycle=@('QUEUED');accepted=$true;verified=$false;enqueueDurationMs=$elapsedMs;queued=$response.queued;completionClaim='NOT_CLAIMED_UNTIL_PC_RESULT_AND_ACK_VERIFIED'}
}

if ($TaskId -and $Enqueue) {
  $result=Invoke-AxPcDispatchGateway -TaskId $TaskId -Command $Command -NodeId $NodeId -ControlRuntimeUrl $ControlRuntimeUrl -Arguments $Arguments -Repository $Repository
  $result|ConvertTo-Json -Depth 10
  exit 0
}
if (-not $TaskId) {
  Write-Output 'AX_PC_DISPATCH_GATEWAY READY'
  Write-Output "Canonical Repository: $Repository"
  Write-Output "Canonical Node: $NodeId"
  Write-Output "Control Runtime: $ControlRuntimeUrl"
  Write-Output 'Lifecycle: QUEUED -> PULLED -> EXECUTED -> RESULT_RECEIVED -> ACK_RECEIVED -> VERIFIED'
  Write-Output 'Completion rule: VERIFIED only'
  exit 0
}
throw 'PC_GATEWAY_USAGE: provide -Enqueue to dispatch a task'
