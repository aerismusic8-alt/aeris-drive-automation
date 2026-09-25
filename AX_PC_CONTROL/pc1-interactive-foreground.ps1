$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$ev='C:\AX-Runtime\evidence';New-Item -ItemType Directory -Path $ev -Force|Out-Null
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FG2 {
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll",SetLastError=true)] public static extern uint GetWindowThreadProcessId(IntPtr hWnd,out uint pid);
}
'@
$rows=@();$deadline=([DateTime]::UtcNow).AddSeconds(15)
while([DateTime]::UtcNow -lt $deadline){
 $fg=[FG2]::GetForegroundWindow();[uint32]$pid=0;[void][FG2]::GetWindowThreadProcessId($fg,[ref]$pid)
 $name='';$cmd='';$parent='';$ppid=0
 if($pid){
  $p=Get-CimInstance Win32_Process -Filter "ProcessId=$pid" -ErrorAction SilentlyContinue
  if($p){$name=$p.Name;$cmd=$p.CommandLine;$ppid=[int]$p.ParentProcessId;$pp=Get-CimInstance Win32_Process -Filter "ProcessId=$ppid" -ErrorAction SilentlyContinue;if($pp){$parent=$pp.Name}}
 }
 $rows += [pscustomobject]@{TimestampUtc=[DateTime]::UtcNow.ToString('o');ForegroundPid=$pid;ForegroundName=$name;ForegroundParentPid=$ppid;ForegroundParentName=$parent;ForegroundCommandLine=$cmd}
 Start-Sleep -Milliseconds 100
}
$rows | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $ev 'pc1-interactive-foreground.json') -Encoding UTF8
$rows | Group-Object ForegroundName | Sort-Object Count -Descending | ForEach-Object {Write-Host "FG_$($_.Name)_COUNT=$($_.Count)"}
Write-Host "INTERACTIVE_CAPTURE=PASS"
