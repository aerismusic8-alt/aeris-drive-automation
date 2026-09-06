$ErrorActionPreference='Stop'
$root = Split-Path -Parent $PSScriptRoot
$installer = Get-Content -Raw (Join-Path $root 'AX_PC_CONTROL/INSTALL_AX_PC_NODE.ps1')

# PowerShell is not a native Windows service host. The node must be launched by
# Task Scheduler (or a real service wrapper), not registered as powershell.exe.
if ($installer -match 'sc\.exe\s+create\s+\$serviceName') {
  throw 'PC_NODE_MUST_NOT_REGISTER_POWERSHELL_AS_WINDOWS_SERVICE'
}
if ($installer -notmatch 'Register-ScheduledTask') {
  throw 'PC_NODE_SCHEDULED_TASK_AUTOSTART_MISSING'
}
if ($installer -notmatch 'RunLevel Highest') {
  throw 'PC_NODE_ELEVATED_TASK_REQUIRED'
}
if ($installer -notmatch 'AX-PC-NODE-\$Node') {
  throw 'PC_NODE_TASK_NAME_MISSING'
}

Write-Output 'AX_PC_NODE_AUTOSTART_CONTRACT_TESTS: PASS'
