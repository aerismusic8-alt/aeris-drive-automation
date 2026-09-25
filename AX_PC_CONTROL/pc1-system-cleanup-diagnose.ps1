$ErrorActionPreference='Continue'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$ev='C:\AX-Runtime\evidence';New-Item -ItemType Directory -Path $ev -Force|Out-Null
$terminalNames=@('powershell.exe','pwsh.exe','cmd.exe','conhost.exe','WindowsTerminal.exe')
$rows=@();$deadline=([DateTime]::UtcNow).AddSeconds(30)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FG { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll",SetLastError=true)] public static extern uint GetWindowThreadProcessId(IntPtr hWnd,out uint pid); }
'@
while([DateTime]::UtcNow -lt $deadline){
 $fg=[FG]::GetForegroundWindow();[uint32]$fgpid=0;[void][FG]::GetWindowThreadProcessId($fg,[ref]$fgpid)
 $fgn='';$fgcmd=''
 if($fgpid){$fp=Get-CimInstance Win32_Process -Filter "ProcessId=$fgpid" -ErrorAction SilentlyContinue;if($fp){$fgn=$fp.Name;$fgcmd=$fp.CommandLine}}
 foreach($p in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {$terminalNames -contains $_.Name})){
  $rows += [pscustomobject]@{TimestampUtc=[DateTime]::UtcNow.ToString('o');ForegroundPid=$fgpid;ForegroundName=$fgn;ForegroundCommandLine=$fgcmd;Name=$p.Name;Pid=$p.ProcessId;ParentPid=$p.ParentProcessId;CommandLine=$p.CommandLine}
 }
 Start-Sleep -Milliseconds 500
}
$parents=@()
foreach($p in @($rows | Sort-Object Pid -Unique)){
 $pp=Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentPid)" -ErrorAction SilentlyContinue
 if($pp){$parents += [pscustomobject]@{Child=$p.Name;ChildPid=$p.Pid;Parent=$pp.Name;ParentPid=$pp.ProcessId;ParentCommandLine=$pp.CommandLine}}
}
[pscustomobject]@{
 protocol='AX PC1 FOREGROUND STEAL DIAGNOSIS v1';nodeId='PC1';computerName=$env:COMPUTERNAME;timestampUtc=[DateTime]::UtcNow.ToString('o')
 sampleSeconds=30;sampleCount=$rows.Count;uniqueProcesses=@($rows|Sort-Object Pid -Unique);parentTrace=$parents
}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $ev 'pc1-foreground-diagnosis.json') -Encoding UTF8
$rows | Group-Object Name | Sort-Object Count -Descending | ForEach-Object {Write-Host "PROCESS_$($_.Name)=$($_.Count)"}
$rows | Group-Object ForegroundName | Sort-Object Count -Descending | ForEach-Object {Write-Host "FOREGROUND_$($_.Name)=$($_.Count)"}
