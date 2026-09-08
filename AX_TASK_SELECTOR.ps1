function Get-AxRetirementPolicy {
  $path = Join-Path $PSScriptRoot 'AX_MASTER_BRAIN\AX_RETIREMENT_POLICY.json'
  if (-not (Test-Path $path)) {
    return [pscustomobject]@{ retired_task_ids=@(); replacement_priority=@() }
  }
  return (Get-Content -Raw -Path $path | ConvertFrom-Json)
}

function Convert-AxMasterPriority {
  param([string]$Priority)
  switch -Regex ($Priority) {
    '^P0_' { return 1000 }
    '^P1_' { return 900 }
    '^P2_' { return 800 }
    '^P3_' { return 700 }
    '^P4_' { return 400 }
    '^P5_' { return 100 }
    default { return 0 }
  }
}

function Convert-AxMasterTaskState {
  param($Task, $RetiredTaskIds)
  $execution = [string]$Task.execution_status
  $approval = [string]$Task.approval_status
  $id = [string]$Task.task_id
  if ($id -in @($RetiredTaskIds)) { return 'RETIRED' }
  if ($execution -match 'RETIRED') { return 'RETIRED' }
  if ($execution -match 'CLOSED') { return 'CLOSED' }
  if ($execution -match '^COMPLETED') { return 'COMPLETED' }
  if ($approval -eq 'WAITING_K') { return 'WAITING_K' }
  if (@($Task.details.blockers).Count -gt 0 -and $execution -notmatch 'QUEUED|NON-LIVE') { return 'BLOCKED' }
  return 'QUEUED'
}

function Convert-AxMasterRegistry {
  param(
    [Parameter(Mandatory=$true)]$MasterRegistry
  )

  if ([string]$MasterRegistry.registry_role -ne 'AUTHORITATIVE_AKATH_MASTER_TASK_STATUS' -and
      [string]$MasterRegistry.schema_version -notmatch '^2\.') {
    throw 'AX_MASTER_REGISTRY_SCHEMA_NOT_RECOGNIZED'
  }

  $retirementPolicy = Get-AxRetirementPolicy
  $retiredTaskIds = @($retirementPolicy.retired_businesses | ForEach-Object { @($_.task_ids) })
  $runtimeTasks = foreach ($task in @($MasterRegistry.tasks)) {
    $state = Convert-AxMasterTaskState -Task $task -RetiredTaskIds $retiredTaskIds
    [pscustomobject]@{
      id = [string]$task.task_id
      domain = [string]$task.category
      title = [string]$task.name
      state = $state
      priority = Convert-AxMasterPriority -Priority ([string]$task.priority)
      depends_on = @()
      trigger = if ($task.task_type -eq 'SYSTEM') { 'event_or_heartbeat' } else { 'mission_goal' }
      next_action = [string]$task.details.next_step
      task_type = [string]$task.task_type
      master_priority = [string]$task.priority
      approval_status = [string]$task.approval_status
      execution_status = [string]$task.execution_status
      canonical_task_id = [string]$task.task_id
    }
  }

  $currentWork = $null
  if ($null -ne $MasterRegistry.current_work) {
    $currentWork = [pscustomobject]@{
      active = [bool]$MasterRegistry.current_work.active
      task_id = [string]$MasterRegistry.current_work.task_id
    }
    if ($currentWork.task_id -in $retiredTaskIds) {
      $replacement = $runtimeTasks | Where-Object { $_.state -notin @('RETIRED','CLOSED','BLOCKED','WAITING_K') } | Sort-Object priority -Descending | Select-Object -First 1
      if ($replacement) { $currentWork.task_id = [string]$replacement.id }
    }
  }

  [pscustomobject]@{
    source = 'AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json'
    canonical = $true
    retirement_policy = 'AX_MASTER_BRAIN/AX_RETIREMENT_POLICY.json'
    policy = [pscustomobject]@{
      terminal_states = @('COMPLETED','BLOCKED','PAUSED','WAITING_K','CLOSED','RETIRED')
      scheduler = [pscustomobject]@{
        heartbeat_minutes = 5
        event_driven_enabled = $true
        priority_precedence = $true
        dependency_enforcement = $true
      }
    }
    current_work = $currentWork
    tasks = @($runtimeTasks)
  }
}

function Get-AxEligibleTasks {
  param(
    [Parameter(Mandatory=$true)]$Registry
  )

  $tasks = @($Registry.tasks)
  $byId = @{}
  foreach ($task in $tasks) {
    $byId[[string]$task.id] = $task
  }

  foreach ($task in $tasks) {
    if ($task.state -in $Registry.policy.terminal_states -or $task.state -eq 'WAITING_K') {
      continue
    }

    $depsReady = $true
    foreach ($dep in @($task.depends_on)) {
      if (-not $byId.ContainsKey([string]$dep) -or $byId[[string]$dep].state -ne 'COMPLETED') {
        $depsReady = $false
        break
      }
    }

    if ($depsReady) {
      $task
    }
  }
}

function Select-AxNextTask {
  param(
    [Parameter(Mandatory=$true)]$Registry
  )

  $eligible = @(Get-AxEligibleTasks -Registry $Registry)
  return ($eligible | Sort-Object -Property @{Expression={[int]$_.priority};Descending=$true} | Select-Object -First 1)
}

function Test-AxTaskDependencies {
  param(
    [Parameter(Mandatory=$true)]$Registry,
    [Parameter(Mandatory=$true)]$Task
  )

  $tasks = @($Registry.tasks)
  $byId = @{}
  foreach ($candidate in $tasks) {
    $byId[[string]$candidate.id] = $candidate
  }

  foreach ($dep in @($Task.depends_on)) {
    if (-not $byId.ContainsKey([string]$dep) -or $byId[[string]$dep].state -ne 'COMPLETED') {
      return $false
    }
  }

  return $true
}
