$ErrorActionPreference='Continue'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$ev='C:\AX-Runtime\evidence';New-Item -ItemType Directory -Path $ev -Force|Out-Null
$terminalNames=@('powershell.exe','pwsh.exe','cmd.exe','conhost.exe','WindowsTerminal.exe')
$procs=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
$focus=@($procs|Where-Object {$terminalNames -contains $_.Name})
$trace=@()
foreach($p in $focus){
 $parent=$procs|Where-Object {$_.ProcessId -eq $p.ParentProcessId}|Select-Object -First 1
 $trace += [pscustomobject]@{Name=$p.Name;Pid=$p.ProcessId;ParentPid=$p.ParentProcessId;ParentName=$parent.Name;CommandLine=$p.CommandLine;ParentCommandLine=$parent.CommandLine;CreationDate=$p.CreationDate}
}
$tasks=@()
Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
 $t=$_
 $i=Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue
 $actions=@($t.Actions|ForEach-Object { [pscustomobject]@{Execute=$_.Execute;Arguments=$_.Arguments;WorkingDirectory=$_.WorkingDirectory} })
 $tasks += [pscustomobject]@{TaskName=$t.TaskName;TaskPath=$t.TaskPath;State=$t.State;Author=$t.Author;PrincipalUserId=$t.Principal.UserId;LogonType=$t.Principal.LogonType;RunLevel=$t.Principal.RunLevel;LastRunTime=$i.LastRunTime;LastTaskResult=$i.LastTaskResult;Actions=$actions}
}
$interesting=@($tasks|Where-Object {$_.TaskName -match 'AERIS|AKATH|AX|BRAIN|RUNTIME|TERMINAL|NODE' -or ($_.Actions.Execute -match 'powershell|cmd|WindowsTerminal|wt.exe|node.exe')})
[pscustomobject]@{protocol='AX PC1 FOREGROUND ROOT-CAUSE SNAPSHOT v2';nodeId='PC1';computerName=$env:COMPUTERNAME;timestampUtc=[DateTime]::UtcNow.ToString('o');terminalProcesses=$trace;interestingTasks=$interesting}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $ev 'pc1-foreground-rootcause.json') -Encoding UTF8
Write-Host "TERMINAL_PROCESS_COUNT=$(@($trace).Count)"
Write-Host "INTERESTING_TASK_COUNT=$(@($interesting).Count)"
$trace|ForEach-Object{Write-Host ("PROC {0} PID={1} PARENT={2} PPID={3} CMD={4}" -f $_.Name,$_.Pid,$_.ParentName,$_.ParentPid,$_.CommandLine)}
$interesting|ForEach-Object{Write-Host ("TASK {0} USER={1} LOGON={2} RUNLEVEL={3} STATE={4} EXEC={5} ARGS={6}" -f $_.TaskName,$_.PrincipalUserId,$_.LogonType,$_.RunLevel,$_.State,(($_.Actions|Select-Object -First 1).Execute),(($_.Actions|Select-Object -First 1).Arguments))}
Write-Host "ROOTCAUSE_SNAPSHOT=PASS"
