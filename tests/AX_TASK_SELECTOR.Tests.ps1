$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\AX_TASK_SELECTOR.ps1"

function Assert-Equal($actual, $expected, $message) {
  if ($actual -ne $expected) { throw "$message | expected=$expected actual=$actual" }
}

$registry = [pscustomobject]@{
  policy = [pscustomobject]@{ terminal_states = @('COMPLETED','BLOCKED','PAUSED','WAITING_K') }
  tasks = @(
    [pscustomobject]@{ id='AERIS-AUTONOMOUS-COMPANY-ENGINE'; state='QUEUED'; priority=80; depends_on=@(); domain='AERIS'; next_action='build-engine' }
    [pscustomobject]@{ id='AX-REVENUE-001'; state='REPROCESS_QUEUED'; priority=110; depends_on=@('AERIS-AUTONOMOUS-COMPANY-ENGINE'); domain='AERIS'; next_action='revenue-action' }
  )
}

$selected = Select-AxNextTask -Registry $registry
Assert-Equal $selected.id 'AERIS-AUTONOMOUS-COMPANY-ENGINE' 'Blocked dependency must not outrank an eligible task'

$registry.tasks[0].state = 'COMPLETED'
$selected = Select-AxNextTask -Registry $registry
Assert-Equal $selected.id 'AX-REVENUE-001' 'Dependent task should become eligible after dependency completion'

$gate = Test-AxTaskDependencies -Registry $registry -Task $registry.tasks[1]
Assert-Equal $gate $true 'Dependency gate should pass after prerequisite completion'

$registry.tasks[0].state = 'QUEUED'
$gate = Test-AxTaskDependencies -Registry $registry -Task $registry.tasks[1]
Assert-Equal $gate $false 'Dependency gate must reject when prerequisite is not COMPLETED'

Write-Host 'AX_TASK_SELECTOR_TESTS: PASS'
