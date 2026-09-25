$ErrorActionPreference='Continue'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$ev='C:\AX-Runtime\evidence';New-Item -ItemType Directory -Path $ev -Force|Out-Null
function Get-TailscaleEntries {
 $paths=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
 Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Tailscale' } | Select-Object DisplayName,DisplayVersion,UninstallString,QuietUninstallString
}
$before=@(Get-TailscaleEntries)
$service=Get-Service -Name Tailscale -ErrorAction SilentlyContinue
if($service){Stop-Service Tailscale -Force -ErrorAction SilentlyContinue}
$entries=@($before)
foreach($e in $entries){
 $u=if($e.QuietUninstallString){$e.QuietUninstallString}else{$e.UninstallString}
 if($u){
  if($u -match '(?i)msiexec'){
   $args=$u -replace '(?i)^.*?msiexec(?:\.exe)?\s*',''
   if($args -notmatch '(?i)/x'){ $args='/x '+$args }
   Start-Process msiexec.exe -ArgumentList ($args+' /qn /norestart') -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
  } else {
   Start-Process cmd.exe -ArgumentList '/c',$u -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
  }
 }
}
$after=@(Get-TailscaleEntries)
$terminalNames=@('powershell','pwsh','cmd','conhost','WindowsTerminal')
$proc=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {$terminalNames -contains $_.Name} | Select-Object Name,ProcessId,ParentProcessId,CommandLine)
$tasks=@(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {$_.TaskName -match 'AERIS|AKATH|AX' -or $_.TaskPath -match 'AERIS|AKATH|AX'} | ForEach-Object {
 $i=$_.Actions|ForEach-Object { $_.Execute+' '+$_.Arguments }
 [pscustomobject]@{TaskName=$_.TaskName;TaskPath=$_.TaskPath;State=$_.State;LastRun=$_.LastRunTime;LastResult=$_.LastTaskResult;Action=($i -join ' | ')}
})
$parents=@()
foreach($p in $proc){$pp=Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)" -ErrorAction SilentlyContinue;if($pp){$parents+=[pscustomobject]@{Child=$p.Name;ChildPid=$p.ProcessId;Parent=$pp.Name;ParentPid=$pp.ProcessId;ParentCommandLine=$pp.CommandLine}}}
$status=if($after.Count -eq 0){'TAILSCALE_REMOVED_AND_TERMINAL_DIAGNOSED'}else{'TAILSCALE_REMAINING'}
[pscustomobject]@{
 protocol='AX PC1 SYSTEM CLEANUP DIAGNOSIS v1';nodeId='PC1';computerName=$env:COMPUTERNAME;status=$status;timestampUtc=[DateTime]::UtcNow.ToString('o')
 tailscale=[pscustomobject]@{beforeCount=$before.Count;before=$before;afterCount=$after.Count;after=$after}
 terminal=[pscustomobject]@{processCount=$proc.Count;processes=$proc;scheduledTaskCount=$tasks.Count;scheduledTasks=$tasks;parentTrace=$parents}
}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $ev 'pc1-system-cleanup-diagnosis.json') -Encoding UTF8
Write-Host "TAILSCALE_BEFORE=$($before.Count)"
Write-Host "TAILSCALE_AFTER=$($after.Count)"
Write-Host "TERMINAL_PROCESS_COUNT=$($proc.Count)"
Write-Host "SCHEDULED_TASK_COUNT=$($tasks.Count)"
