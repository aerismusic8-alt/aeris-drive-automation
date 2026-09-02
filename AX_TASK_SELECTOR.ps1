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
