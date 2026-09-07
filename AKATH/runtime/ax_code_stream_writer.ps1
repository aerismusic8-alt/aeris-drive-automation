param(
  [Parameter(Mandatory=$true)][string]$Agent,
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$File,
  [Parameter(Mandatory=$true)][ValidateSet('START','LINE','END','ERROR')][string]$Event,
  [string]$Text=''
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$path=Join-Path $root 'dashboard\code-stream.json'
if(Test-Path $path){$stream=Get-Content -Raw $path|ConvertFrom-Json}else{$stream=[pscustomobject]@{schema='AX_CODE_STREAM_V1';status='IDLE';agent='NONE';taskId=$null;file=$null;startedAt=$null;updatedAt=$null;lines=@()}}
if($stream.schema -ne 'AX_CODE_STREAM_V1'){throw 'AX_CODE_STREAM_SCHEMA_INVALID'}
$now=(Get-Date).ToUniversalTime().ToString('o')
if($Event -eq 'START'){
  $stream.status='WRITING';$stream.agent=$Agent;$stream.taskId=$TaskId;$stream.file=$File;$stream.startedAt=$now;$stream.lines=@()
}elseif($stream.taskId -ne $TaskId){throw 'AX_CODE_STREAM_TASK_MISMATCH'}
if($Event -in @('LINE','ERROR')){
  $kind=if($Event -eq 'ERROR'){'stderr'}else{'code'}
  $next=1;if($stream.lines.Count -gt 0){$next=([int]$stream.lines[-1].seq)+1}
  $stream.lines+=,[pscustomobject]@{seq=$next;kind=$kind;text=$Text}
}
if($Event -eq 'END'){$stream.status='COMPLETED'}elseif($Event -eq 'ERROR'){$stream.status='ERROR'}
$stream.updatedAt=$now
$stream|ConvertTo-Json -Depth 20|Set-Content $path -Encoding UTF8
Write-Host "AX_CODE_STREAM=$($stream.status) agent=$Agent task=$TaskId file=$File seq=$($stream.lines.Count) at=$now"
