$ErrorActionPreference = 'Stop'
$taskName = 'AX-Heartbeat'
$scriptDir = 'C:\AX-Runtime'
$scriptPath = Join-Path $scriptDir 'AX-Heartbeat.ps1'
New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null

$heartbeat = @'
$ErrorActionPreference = 'Stop'
$log = 'C:\AX-Runtime\AX-Heartbeat.log'
$runtimeUrl = if ($env:AX_AERIS_RUNTIME_URL) { $env:AX_AERIS_RUNTIME_URL.TrimEnd('/') } else { 'https://aeris-execution-runtime.aerismusic8.workers.dev' }
$ts = (Get-Date).ToUniversalTime().ToString('o')
try {
  $r = Invoke-WebRequest -Uri $runtimeUrl -Method Get -UseBasicParsing -TimeoutSec 15
  $line = "$ts HEARTBEAT HTTP=$($r.StatusCode) URL=$runtimeUrl"
  Add-Content -Path $log -Value $line
  if ($r.StatusCode -ne 200) { throw "HTTP_$($r.StatusCode)" }
  $body = $r.Content | ConvertFrom-Json
  if ($body.status -ne 'ONLINE') { throw 'RUNTIME_NOT_ONLINE' }
  Add-Content -Path $log -Value "$ts RUNTIME=ONLINE VERSION=$($body.version)"
} catch {
  Add-Content -Path $log -Value "$ts ERROR=$($_.Exception.Message)"
  exit 1
}
'@
Set-Content -Path $scriptPath -Value $heartbeat -Encoding UTF8

$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`""
$boot = New-ScheduledTaskTrigger -AtStartup
$minute = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($boot,$minute) -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Host "AX-Heartbeat installed and started: $taskName"
Write-Host "Script: $scriptPath"
