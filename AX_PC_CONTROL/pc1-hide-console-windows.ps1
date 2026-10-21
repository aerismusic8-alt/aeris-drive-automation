# Make the AX/AERIS background tasks stop putting console windows on the desktop.
#
# Measured on PC1 before this script: a 993x519 cmd.exe window titled
# "Administrator: C:\WINDOWS\system32\cmd.exe" and a 993x519 python.exe console
# beside it. Those two are the winremote task and the server it launches, and
# they sit on top of the desktop for the life of the machine. On a phone-driven
# machine that is not cosmetic: the windows cover the thing being driven.
#
# The cause is that a scheduled task with an Interactive principal gets a visible
# console unless it says otherwise, and these tasks never said otherwise.
#
# Three levers, applied per task:
#
#   1. python.exe becomes pythonw.exe. pythonw has no console at all, so there is
#      nothing to show and nothing to flash.
#   2. A cmd.exe action that runs a .cmd file is re-launched through a hidden
#      PowerShell, so the console the .cmd would create is never shown. The .cmd
#      itself is left alone, so its logging still works.
#   3. A powershell.exe action without -WindowStyle Hidden gets it, and the
#      task's own Hidden flag is set.
#
# Only tasks in Ready or Running are touched. A Disabled task is not producing
# windows now, and changing one would be a change with no evidence behind it.
#
#   powershell -ExecutionPolicy Bypass -File pc1-hide-console-windows.ps1 -SelfTest
#   powershell -ExecutionPolicy Bypass -File pc1-hide-console-windows.ps1            # dry run
#   powershell -ExecutionPolicy Bypass -File pc1-hide-console-windows.ps1 -Apply

param(
  [string]$RuntimeRoot = 'C:\AX-Runtime',
  [switch]$Apply,
  [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME" }

$evidenceDir = Join-Path $RuntimeRoot 'evidence'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$logPath = Join-Path $evidenceDir 'hide-console-windows.log'

function Write-Log([string]$Line) {
  $stamp = (Get-Date).ToUniversalTime().ToString('o')
  "$stamp $Line" | Add-Content -LiteralPath $logPath -Encoding UTF8
  Write-Host $Line
}

function Convert-ToWindowless {
  # Rewrite one action so it does not open a console. Takes strings, returns
  # strings and a note, and touches nothing, so the rule can be tested on its own.
  # Returns $null when the action already behaves.
  param([string]$Execute, [string]$Arguments, [bool]$PythonwExists)

  $exe = $Execute
  $args = $Arguments
  $notes = New-Object System.Collections.Generic.List[string]

  if ($exe -match '(?i)(^|\\)python\.exe$' -or $exe -match '(?i)^python$') {
    if ($PythonwExists) {
      # A bare "python" resolves through PATH, and pythonw sits beside python in
      # every CPython install, so swapping the name keeps the same lookup.
      $exe = $exe -replace '(?i)python(\.exe)?$', 'pythonw.exe'
      $notes.Add('PYTHONW')
    } else {
      $notes.Add('NO_PYTHONW')
    }
  }

  if ($exe -match '(?i)powershell(\.exe)?$') {
    if ($args -notmatch '(?i)-WindowStyle\s+Hidden') {
      $args = "-WindowStyle Hidden $args"
      $notes.Add('WINDOWSTYLE_HIDDEN')
    } else {
      $notes.Add('ALREADY_HIDDEN')
    }
  }

  if ($exe -match '(?i)cmd(\.exe)?$' -and $args -match '(?i)\.cmd"') {
    # A console app launched from a hidden PowerShell inherits that hidden
    # console, so the .cmd's own window never appears. The .cmd is untouched, so
    # its redirection to a log file still works.
    $inner = ($args -replace '(?i)^\s*/c\s+', '').Trim()
    $exe = 'powershell.exe'
    $args = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"& $inner`""
    $notes.Add('CMD_WRAPPED_HIDDEN')
  }

  if ($notes.Count -eq 0) { return $null }
  [pscustomobject]@{ Execute = $exe; Arguments = $args; Notes = @($notes) }
}

function Invoke-SelfTest {
  $cases = @(
    @{ Name = 'python full path'; Exe = 'C:\Python314\python.exe'; Args = '-u "w.py" --config "c.json"'; Py = $true;
       ExpectExe = 'C:\Python314\pythonw.exe'; ExpectArg = '-u "w.py" --config "c.json"' },
    @{ Name = 'python bare'; Exe = 'python.exe'; Args = '-u "w.py"'; Py = $true;
       ExpectExe = 'pythonw.exe'; ExpectArg = '-u "w.py"' },
    @{ Name = 'python bare no extension'; Exe = 'python'; Args = 'C:\x\agent-evaluator.py'; Py = $true;
       ExpectExe = 'pythonw.exe'; ExpectArg = 'C:\x\agent-evaluator.py' },
    @{ Name = 'python with no pythonw'; Exe = 'C:\Python314\python.exe'; Args = '-u "w.py"'; Py = $false;
       ExpectExe = 'C:\Python314\python.exe'; ExpectArg = '-u "w.py"' },
    @{ Name = 'powershell plain'; Exe = 'powershell.exe'; Args = '-NoProfile -File "x.ps1"'; Py = $true;
       ExpectExe = 'powershell.exe'; ExpectArg = '-WindowStyle Hidden -NoProfile -File "x.ps1"' },
    @{ Name = 'powershell already hidden'; Exe = 'powershell.exe'; Args = '-WindowStyle Hidden -NoProfile -File "x.ps1"'; Py = $true;
       ExpectExe = 'powershell.exe'; ExpectArg = '-WindowStyle Hidden -NoProfile -File "x.ps1"' },
    @{ Name = 'cmd running a cmd file'; Exe = 'cmd.exe'; Args = '/c "C:\AX-Runtime\winremote\start-winremote-mcp.cmd"'; Py = $true;
       ExpectExe = 'powershell.exe';
       ExpectArg = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "& "C:\AX-Runtime\winremote\start-winremote-mcp.cmd""' }
  )
  $failed = 0
  foreach ($c in $cases) {
    $r = Convert-ToWindowless -Execute $c.Exe -Arguments $c.Args -PythonwExists $c.Py
    if ($null -eq $r) {
      $failed++
      Write-Host "SELFTEST_FAIL $($c.Name): returned null"
      continue
    }
    if ($r.Execute -ne $c.ExpectExe -or $r.Arguments -ne $c.ExpectArg) {
      $failed++
      Write-Host "SELFTEST_FAIL $($c.Name)"
      Write-Host "  got      '$($r.Execute) $($r.Arguments)'"
      Write-Host "  expected '$($c.ExpectExe) $($c.ExpectArg)'"
    } else {
      Write-Host "SELFTEST_OK $($c.Name)"
    }
  }
  if ($failed -gt 0) { Write-Host "SELFTEST_RESULT=FAIL failed=$failed"; exit 1 }
  Write-Host 'SELFTEST_RESULT=PASS'
  exit 0
}

if ($SelfTest) { Invoke-SelfTest }

$TASK_NS = 'http://schemas.microsoft.com/windows/2004/02/mit/task'

function Set-TaskWindowless {
  # Rewrite a task's actions and Hidden flag by editing its exported XML.
  #
  # Set-ScheduledTask -Settings on a settings object that came from
  # Get-ScheduledTask fails with "Argument types do not match" on this machine,
  # on every task that has a trigger, while it succeeds on a bare test task. The
  # XML route does not go through that binder at all: the task is exported,
  # the two things that need to change are changed in place, and the result is
  # registered over the original. Everything else, including the principal and
  # the triggers, is carried through untouched because it is the same document.
  param(
    [string]$TaskName,
    [int[]]$ActionIndex,
    [string[]]$NewExecute,
    [string[]]$NewArguments,
    [bool]$SetHidden,
    [string]$BackupDir
  )

  $xml = [xml](Export-ScheduledTask -TaskName $TaskName)
  $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
  $ns.AddNamespace('t', $TASK_NS)

  if ($BackupDir) {
    $safe = $TaskName -replace '[^\w\-]', '_'
    $xml.OuterXml | Set-Content -LiteralPath (Join-Path $BackupDir "$safe.xml") -Encoding UTF8
  }

  $execs = @($xml.SelectNodes('//t:Actions/t:Exec', $ns))
  for ($i = 0; $i -lt $ActionIndex.Count; $i++) {
    $node = $execs[$ActionIndex[$i]]
    if (-not $node) { throw "ACTION_INDEX_MISSING:$($ActionIndex[$i])" }
    $cmd = $node.SelectSingleNode('t:Command', $ns)
    $arg = $node.SelectSingleNode('t:Arguments', $ns)
    $cmd.InnerText = $NewExecute[$i]
    if (-not $arg) {
      $arg = $xml.CreateElement('Arguments', $TASK_NS)
      [void]$node.AppendChild($arg)
    }
    $arg.InnerText = $NewArguments[$i]
  }

  if ($SetHidden) {
    $settings = $xml.SelectSingleNode('//t:Settings', $ns)
    $hidden = $xml.SelectSingleNode('//t:Settings/t:Hidden', $ns)
    if (-not $hidden) {
      $hidden = $xml.CreateElement('Hidden', $TASK_NS)
      [void]$settings.AppendChild($hidden)
    }
    $hidden.InnerText = 'true'
  }

  Register-ScheduledTask -TaskName $TaskName -Xml $xml.OuterXml -Force | Out-Null
}

$pythonwExists = Test-Path -LiteralPath 'C:\Python314\pythonw.exe'
$backupDir = Join-Path $evidenceDir 'task-backups'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
Write-Log "START pythonwExists=$pythonwExists apply=$($Apply.IsPresent)"

$tasks = Get-ScheduledTask | Where-Object {
  ($_.TaskName -like 'AERIS*' -or $_.TaskName -like 'AX-*') -and
  ([string]$_.State -eq 'Ready' -or [string]$_.State -eq 'Running')
}

$changed = 0
$changedNames = New-Object System.Collections.Generic.List[string]

foreach ($task in $tasks) {
  $index = New-Object System.Collections.Generic.List[int]
  $exes = New-Object System.Collections.Generic.List[string]
  $argLine = New-Object System.Collections.Generic.List[string]
  $notes = New-Object System.Collections.Generic.List[string]
  $actions = @($task.Actions)

  for ($i = 0; $i -lt $actions.Count; $i++) {
    $r = Convert-ToWindowless -Execute ([string]$actions[$i].Execute) -Arguments ([string]$actions[$i].Arguments) -PythonwExists $pythonwExists
    if ($null -eq $r) { continue }
    foreach ($n in $r.Notes) { $notes.Add($n) }
    if ($r.Execute -ne $actions[$i].Execute -or $r.Arguments -ne $actions[$i].Arguments) {
      $index.Add($i); $exes.Add($r.Execute); $argLine.Add($r.Arguments)
    }
  }

  $needsChange = $index.Count -gt 0
  $needsHidden = -not ([bool]$task.Settings.Hidden)
  if (-not $needsChange -and -not $needsHidden) {
    Write-Log "SKIP $($task.TaskName) notes=$($notes -join ',')"
    continue
  }

  $tag = if ($needsChange) { 'REWRITE' } else { 'HIDDEN_ONLY' }
  Write-Log "$tag $($task.TaskName) notes=$($notes -join ',') actions=$($index -join '/') apply=$($Apply.IsPresent)"

  if ($Apply) {
    try {
      Set-TaskWindowless -TaskName $task.TaskName -ActionIndex $index.ToArray() `
        -NewExecute $exes.ToArray() -NewArguments $argLine.ToArray() `
        -SetHidden $true -BackupDir $backupDir
      $changed++
      $changedNames.Add($task.TaskName)
      Write-Log "APPLIED $($task.TaskName)"
    } catch {
      Write-Log "APPLY_FAILED $($task.TaskName): $($_.Exception.Message)"
    }
  }
}

if (-not $Apply) { Write-Log "DRY_RUN done changed_would_be=$changed"; exit 0 }

# Restart the tasks whose action changed, so the running process is the new one.
# The reverse-control task is skipped: restarting it would drop the channel this
# script is being driven through. Its new action takes effect on the next start.
$skip = @('AERIS-PC1-REVERSE-CONTROL')
foreach ($name in $changedNames) {
  if ($skip -contains $name) { Write-Log "RESTART_DEFERRED $name (would drop the channel)"; continue }
  try {
    Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    Start-ScheduledTask -TaskName $name
    Write-Log "RESTARTED $name"
  } catch {
    Write-Log "RESTART_FAILED ${name}: $($_.Exception.Message)"
  }
}

Start-Sleep -Seconds 10
Write-Log "DONE changed=$changed restarted=$($changedNames -join ',')"
