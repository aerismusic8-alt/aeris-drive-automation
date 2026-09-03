param(
  [string]$StatePath='dashboard/status.json',
  [string]$RegistryPath='AX_TRIGGER_REGISTRY.json',
  [string]$TaskRegistryPath='AX_TASK_REGISTRY.json',
  [string]$ActiveExecutionsPath='AX_ACTIVE_EXECUTIONS.json',
  [string]$Event='SYNC',
  [string]$JobId=''
)
$ErrorActionPreference='Stop'
$now=(Get-Date).ToUniversalTime().ToString('o')
if(!(Test-Path $StatePath)){throw 'DASHBOARD_STATE_MISSING'}
$s=Get-Content -Raw $StatePath|ConvertFrom-Json
$registry=$null
if(Test-Path $RegistryPath){$registry=Get-Content -Raw $RegistryPath|ConvertFrom-Json}
$taskRegistry=$null
if(Test-Path $TaskRegistryPath){$taskRegistry=Get-Content -Raw $TaskRegistryPath|ConvertFrom-Json}
$active=$null
if(Test-Path $ActiveExecutionsPath){$active=Get-Content -Raw $ActiveExecutionsPath|ConvertFrom-Json}
$triggerCount=if($registry){[int]$registry.triggerCount}else{0}

$sync=[pscustomobject]@{schema='AX_DASHBOARD_SYNC_V1';syncAt=$now;event=$Event;jobId=$JobId;triggerCount=$triggerCount;sourceState=$StatePath;stateVerified=$true}
$syncPath='dashboard/ax-sync.json'
$sync|ConvertTo-Json -Depth 8|Set-Content $syncPath -Encoding UTF8

$tasks=@()
if($taskRegistry -and $taskRegistry.tasks){
  $tasks=@($taskRegistry.tasks|ForEach-Object{
    [pscustomobject]@{
      id=[string]$_.id
      status=if($_.state){[string]$_.state}else{'UNKNOWN'}
      agent=if($_.domain){[string]$_.domain}else{$null}
      action=if($_.next_action){[string]$_.next_action}else{$null}
      result=$null
      verification=$null
      error=$null
      retry=$null
      timestamp=$null
    }
  })
}
[pscustomobject]@{schema='AX_TASK_QUEUE_V1';updatedAt=$now;tasks=$tasks}|ConvertTo-Json -Depth 12|Set-Content 'dashboard/task-queue.json' -Encoding UTF8

$history=@()
if(Test-Path 'dashboard/activity.json'){
  try{$old=Get-Content -Raw 'dashboard/activity.json'|ConvertFrom-Json;if($old.events){$history=@($old.events)}}catch{$history=@()}
}
$history=@([pscustomobject]@{id="$now-$Event-$JobId";type='DASHBOARD_SYNC';message="System=$($s.system) Overall=$($s.overall) SelectedTask=$($s.selectedTask)";status=if($s.overall){[string]$s.overall}else{'UNKNOWN'};timestamp=$now})+$history
$history=@($history|Select-Object -First 100)
[pscustomobject]@{schema='AX_ACTIVITY_V1';updatedAt=$now;events=$history}|ConvertTo-Json -Depth 12|Set-Content 'dashboard/activity.json' -Encoding UTF8

$agents=@()
if($active -and $active.executions){
  $agents=@($active.executions|ForEach-Object{
    [pscustomobject]@{
      id=if($_.triggerId){[string]$_.triggerId}else{$null}
      name=if($_.triggerId){[string]$_.triggerId}else{'AX runtime'}
      status=if($_.status){[string]$_.status}else{'UNKNOWN'}
      role='AX runtime execution'
      route=if($_.runner){[string]$_.runner}else{$null}
      timestamp=if($_.lastSeen){[string]$_.lastSeen}else{$null}
    }
  })
}
[pscustomobject]@{schema='AX_AGENTS_V1';updatedAt=$now;agents=$agents}|ConvertTo-Json -Depth 12|Set-Content 'dashboard/agents.json' -Encoding UTF8

$v=Get-Content -Raw $syncPath|ConvertFrom-Json
$q=Get-Content -Raw 'dashboard/task-queue.json'|ConvertFrom-Json
$a=Get-Content -Raw 'dashboard/activity.json'|ConvertFrom-Json
$g=Get-Content -Raw 'dashboard/agents.json'|ConvertFrom-Json
if($v.schema -ne 'AX_DASHBOARD_SYNC_V1' -or $v.stateVerified -ne $true){throw 'DASHBOARD_SYNC_VERIFY_FAILED'}
if($q.schema -ne 'AX_TASK_QUEUE_V1' -or $null -eq $q.tasks){throw 'DASHBOARD_QUEUE_VERIFY_FAILED'}
if($a.schema -ne 'AX_ACTIVITY_V1' -or $null -eq $a.events){throw 'DASHBOARD_ACTIVITY_VERIFY_FAILED'}
if($g.schema -ne 'AX_AGENTS_V1' -or $null -eq $g.agents){throw 'DASHBOARD_AGENT_VERIFY_FAILED'}
Write-Host "AX_DASHBOARD_SYNC=VERIFIED event=$Event triggers=$triggerCount tasks=$($q.tasks.Count) events=$($a.events.Count) agents=$($g.agents.Count) at=$now"
