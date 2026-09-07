param(
  [Parameter(Mandatory=$true)][string]$Agent,
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$File,
  [Parameter(Mandatory=$true)][ValidateSet('START','LINE','END','ERROR')][string]$Event,
  [string]$Text=''
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$streamPath=Join-Path $root 'dashboard\code-stream.json'
$targetPath=Join-Path $root $File
if(Test-Path $streamPath){$stream=Get-Content -Raw $streamPath|ConvertFrom-Json}else{$stream=[pscustomobject]@{schema='AX_CODE_STREAM_V1';status='IDLE';agent='NONE';taskId=$null;file=$null;startedAt=$null;updatedAt=$null;lines=@()}}
if($stream.schema -ne 'AX_CODE_STREAM_V1'){throw 'AX_CODE_STREAM_SCHEMA_INVALID'}
$now=(Get-Date).ToUniversalTime().ToString('o')
if($Event -eq 'START'){
  $stream.status='WRITING';$stream.agent=$Agent;$stream.taskId=$TaskId;$stream.file=$File;$stream.startedAt=$now;$stream.lines=@()
  $parent=Split-Path -Parent $targetPath
  if(-not(Test-Path $parent)){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
  Set-Content -LiteralPath $targetPath -Value '' -Encoding UTF8
}elseif($stream.taskId -ne $TaskId){throw 'AX_CODE_STREAM_TASK_MISMATCH'}
if($Event -eq 'LINE'){
  $stream.lines+=,[pscustomobject]@{seq=($stream.lines.Count+1);kind='code';text=$Text}
  Add-Content -LiteralPath $targetPath -Value $Text -Encoding UTF8
}elseif($Event -eq 'ERROR'){
  $stream.lines+=,[pscustomobject]@{seq=($stream.lines.Count+1);kind='stderr';text=$Text}
}
if($Event -eq 'END'){$stream.status='COMPLETED'}elseif($Event -eq 'ERROR'){$stream.status='ERROR'}
$stream.updatedAt=$now
$stream|ConvertTo-Json -Depth 20|Set-Content $streamPath -Encoding UTF8
Write-Host "AX_CODE_STREAM=$($stream.status) agent=$Agent task=$TaskId file=$File seq=$($stream.lines.Count) at=$now"