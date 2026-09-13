param([string]$RuntimeRoot='C:\AX-Runtime')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$runtime=Join-Path $root 'AX_PC2_CONTROL_RUNTIME_V1.ps1'
New-Item -ItemType Directory -Force $RuntimeRoot | Out-Null
Copy-Item $runtime (Join-Path $RuntimeRoot 'AX_PC2_CONTROL_RUNTIME_V1.ps1') -Force
$task='AX-Control-PC2'
$wrapper=Join-Path $RuntimeRoot 'AX_PC2_CONTROL_WRAPPER.ps1'
@"
while (`$true) { try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$RuntimeRoot\AX_PC2_CONTROL_RUNTIME_V1.ps1' -RuntimeRoot '$RuntimeRoot' } catch { Start-Sleep 5 } Start-Sleep 2 }
"@ | Set-Content $wrapper -Encoding UTF8
$taskConfigured=$false
try {
  $createOutput = & schtasks.exe /Create /TN $task /SC ONSTART /RU SYSTEM /RL HIGHEST /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$wrapper`"" /F 2>&1
  if($LASTEXITCODE -eq 0){
    $taskConfigured=$true
    & schtasks.exe /Run /TN $task | Out-Null
  }
} catch {
  $taskConfigured=$false
}
if(-not $taskConfigured){
  Write-Warning 'AX_PC2_AUTOSTART_TASK_NOT_CONFIGURED: insufficient privilege for SYSTEM scheduled task; starting local wrapper directly.'
  Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$wrapper) -WindowStyle Hidden
}
Start-Sleep 3
$state=Join-Path $RuntimeRoot 'control-state.json'
if(!(Test-Path $state)){throw 'AX_PC2_STATE_NOT_CREATED'}
$s=Get-Content -Raw $state|ConvertFrom-Json
if($s.nodeId -ne 'PC2'){throw 'AX_PC2_NODE_ID_INVALID'}
Write-Host 'AX_PC2_BOOTSTRAP=VERIFIED'
Write-Host "AX_PC2_STATUS=$($s.status)"
if($taskConfigured){Write-Host 'AX_PC2_AUTO_START=CONFIGURED'}else{Write-Host 'AX_PC2_AUTO_START=DEGRADED'}
Write-Host 'AX_PC2_RECOVERY_WRAPPER=CONFIGURED'