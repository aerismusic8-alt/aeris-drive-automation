$ErrorActionPreference='Continue'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$ev='C:\AX-Runtime\evidence';New-Item -ItemType Directory -Path $ev -Force|Out-Null
function Get-TailscaleEntries {
 $paths=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
 Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Tailscale' } | Select-Object DisplayName,DisplayVersion,UninstallString,QuietUninstallString
}
$before=@(Get-TailscaleEntries)
$service=Get-Service -Name Tailscale -ErrorAction SilentlyContinue
if($service -and $service.Status -ne 'Stopped'){Stop-Service Tailscale -Force -ErrorAction SilentlyContinue}
foreach($e in @($before)){
 $u=if($e.QuietUninstallString){$e.QuietUninstallString}else{$e.UninstallString}
 if($u){
  if($u -match '(?i)msiexec'){
   $args=$u -replace '(?i)^.*?msiexec(?:\.exe)?\s*',''
   if($args -notmatch '(?i)/x'){ $args='/x '+$args }
   Start-Process msiexec.exe -ArgumentList ($args+' /qn /norestart') -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
  } else { Start-Process cmd.exe -ArgumentList '/c',$u -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue }
 }
}
$after=@(Get-TailscaleEntries)
$terminalNames=@('powershell.exe','pwsh.exe','cmd.exe','conhost.exe','WindowsTerminal.exe')
$sample=@();$deadline=([DateTime]::UtcNow).AddSeconds(45)
while([DateTime]::UtcNow -lt $deadline){
 $now=[DateTime]::UtcNow.ToString('o')
 foreach($p in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {$terminalNames -contains $_.Name})){
  $sample += [pscustomobject]@{TimestampUtc=$now;Name=$p.Name;ProcessId=$p.ProcessId;ParentProcessId=$p.ParentProcessId;CommandLine=$p.CommandLine}
 }
 Start-Sleep -Milliseconds 500
}
$unique=@($sample | Sort-Object ProcessId -Unique)
$allTasks=@(Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
 $i=$_.Actions|ForEach-Object { $_.Execute+' '+$_.Arguments }
 [pscustomobject]@{TaskName=$_.TaskName;TaskPath=$_.TaskPath;State=$_.State;LastRun=$_.LastRunTime;LastResult=$_.LastTaskResult;Action=($i -join ' | ')}
})
$ownedTasks=@($allTasks | Where-Object {$_.TaskName -match 'AERIS|AKATH|AX' -or $_.TaskPath -match 'AERIS|AKATH|AX'})
$parents=@()
foreach($p in $unique){
 $pp=Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)" -ErrorAction SilentlyContinue
 if($pp){$parents+=[pscustomobject]@{Child=$p.Name;ChildPid=$p.ProcessId;Parent=$pp.Name;ParentPid=$pp.ProcessId;ParentCommandLine=$pp.CommandLine}}
}
$status=if($after.Count -eq 0){'TAILSCALE_REMOVED_AND_TERMINAL_DIAGNOSED'}else{'TAILSCALE_REMAINING'}
[pscustomobject]@{
 protocol='AX PC1 SYSTEM CLEANUP DIAGNOSIS v2';nodeId='PC1';computerName=$env:COMPUTERNAME;status=$status;timestampUtc=[DateTime]::UtcNow.ToString('o')
 tailscale=[pscustomobject]@{beforeCount=$before.Count;before=$before;afterCount=$after.Count;after=$after}
 terminal=[pscustomobject]@{sampleSeconds=45;sampleCount=$sample.Count;uniqueProcessCount=$unique.Count;processes=$unique;scheduledTaskCount=$ownedTasks.Count;scheduledTasks=$ownedTasks;allScheduledTaskCount=$allTasks.Count;parentTrace=$parents}
}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $ev 'pc1-system-cleanup-diagnosis.json') -Encoding UTF8
Write-Host "TAILSCALE_BEFORE=$($before.Count)"
Write-Host "TAILSCALE_AFTER=$($after.Count)"
Write-Host "TERMINAL_SAMPLE_COUNT=$($sample.Count)"
Write-Host "TERMINAL_UNIQUE_PROCESS_COUNT=$($unique.Count)"
Write-Host "AERIS_TASK_COUNT=$($ownedTasks.Count)"
Write-Host "ALL_SCHEDULED_TASK_COUNT=$($allTasks.Count)"
