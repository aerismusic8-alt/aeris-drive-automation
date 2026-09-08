$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\AX_TASK_SELECTOR.ps1"

function Assert-Equal($actual, $expected, $message) {
  if ($actual -ne $expected) { throw "$message | expected=$expected actual=$actual" }
}

$registry = [pscustomobject]@{
  policy = [pscustomobject]@{ terminal_states = @('COMPLETED','BLOCKED','PAUSED','WAITING_K','CLOSED','RETIRED') }
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

$master = [pscustomobject]@{
  schema_version = '2.4'
  current_work = [pscustomobject]@{ active=$true; task_id='AKATH-6AI-REVENUE-TEAM' }
  tasks = @(
    [pscustomobject]@{ task_id='AKATH-6AI-REVENUE-TEAM'; task_type='SYSTEM'; category='REVENUE'; name='6-AI Revenue Team'; priority='P0_CASH_SURVIVAL'; approval_status='—'; execution_status='REPROCESS_QUEUED'; details=[pscustomobject]@{current_step='REPROCESS_QUEUED';next_step='START_CASH_ENGINE';blockers=@();retry_fallback=@()} }
    [pscustomobject]@{ task_id='MISSION-XM-PORTFOLIO-1M'; task_type='MISSION'; category='REVENUE'; name='XM Portfolio → 1,000,000 THB'; priority='P4_SPECULATIVE_XM'; approval_status='APPROVED'; execution_status='QUEUED / NON-LIVE'; details=[pscustomobject]@{current_step='QUEUED';next_step='RUN_SELF_HOSTED_XM_VERIFICATION';blockers=@();retry_fallback=@()} }
  )
}

$runtimeRegistry = Convert-AxMasterRegistry -MasterRegistry $master
Assert-Equal $runtimeRegistry.tasks.Count 2 'Runtime projection must preserve exact master task count'
Assert-Equal $runtimeRegistry.current_work.task_id 'AKATH-6AI-REVENUE-TEAM' 'Runtime projection must preserve canonical current_work'
Assert-Equal ($runtimeRegistry.tasks | Where-Object id -eq 'MISSION-XM-PORTFOLIO-1M').state 'RETIRED' 'XM mission must be retired from active selection'
$selected = Select-AxNextTask -Registry $runtimeRegistry
Assert-Equal $selected.id 'AKATH-6AI-REVENUE-TEAM' 'Revenue-first selection must not select retired XM work'

Write-Host 'AX_TASK_SELECTOR_TESTS: PASS'
