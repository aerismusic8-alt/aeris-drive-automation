param([string]$RuntimeRoot='C:\AX-Runtime')
$ErrorActionPreference='Stop'
if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'AX_PC2_ADMIN_REQUIRED' }
$repoRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
$runtime=Join-Path $repoRoot 'AX_PC2_CONTROL_RUNTIME_V1.ps1'
New-Item -ItemType Directory -Force $RuntimeRoot | Out-Null
Copy-Item $runtime (Join-Path $RuntimeRoot 'AX_PC2_CONTROL_RUNTIME_V1.ps1') -Force
$wrapper=Join-Path $RuntimeRoot 'AX_PC2_CONTROL_WRAPPER.ps1'
@"
while (`$true) { try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$RuntimeRoot\AX_PC2_CONTROL_RUNTIME_V1.ps1' -RuntimeRoot '$RuntimeRoot' } catch { Start-Sleep 5 } Start-Sleep 2 }
"@ | Set-Content $wrapper -Encoding UTF8
$task='AX-Control-PC2'
$tr="powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$wrapper`""
& schtasks.exe /Create /TN $task /SC ONSTART /RU SYSTEM /RL HIGHEST /TR $tr /F | Out-Host
if($LASTEXITCODE -ne 0){throw 'AX_PC2_SCHEDULED_TASK_CREATE_FAILED'}
& schtasks.exe /Run /TN $task | Out-Host
if($LASTEXITCODE -ne 0){throw 'AX_PC2_SCHEDULED_TASK_RUN_FAILED'}
Start-Sleep 5
$state=Join-Path $RuntimeRoot 'control-state.json'
if(!(Test-Path $state)){throw 'AX_PC2_STATE_NOT_CREATED'}
$s=Get-Content -Raw $state|ConvertFrom-Json
if($s.nodeId -ne 'PC2'){throw 'AX_PC2_NODE_ID_INVALID'}
if($s.status -notin @('ONLINE','EXECUTING')){throw "AX_PC2_NOT_ONLINE:$($s.status)"}
Write-Host 'AX_PC2_PERSISTENT_TASK=VERIFIED'
Write-Host 'AX_PC2_AUTO_START=CONFIGURED'
Write-Host 'AX_PC2_RUNTIME=ONLINE'
