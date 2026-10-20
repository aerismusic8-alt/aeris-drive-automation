# Simulate the installer's cmdlet calls with fakes, to catch enum and parameter
# mistakes that only surface at runtime. That class of bug reached K twice: a
# wrong LogonType value ended a run before anything was registered, and a native
# command writing to stderr ended another. Both are caught here.
$ErrorActionPreference = 'Stop'
$fail = @()

function New-ScheduledTaskPrincipal {
  param([string]$UserId, [string]$LogonType, [string]$RunLevel)
  $valid = @('None', 'Password', 'S4U', 'Interactive', 'Group', 'ServiceAccount', 'InteractiveOrPassword')
  if ($LogonType -notin $valid) { throw "LogonType '$LogonType' is not valid. Valid: $($valid -join ', ')" }
  "principal user=$UserId logon=$LogonType level=$RunLevel"
}
function New-ScheduledTaskTrigger { param([string]$AtLogOn, [string]$User); "trigger user=$User" }
function New-ScheduledTaskAction { param([string]$Execute, [string]$Argument, [string]$WorkingDirectory); "action exe=$Execute" }
function New-ScheduledTaskSettingsSet {
  param([switch]$AllowStartIfOnBatteries, [switch]$DontStopIfGoingOnBatteries,
        [switch]$StartWhenAvailable, [int]$RestartCount, [object]$RestartInterval,
        [object]$ExecutionTimeLimit)
  "settings"
}

$src = Get-Content -Raw (Join-Path $PSScriptRoot 'pc1-install-reverse-channel.ps1')

# 1. The value Windows accepts must work.
try {
  $sid = 'S-1-5-21-1-2-3-1001'
  $r = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Highest
  Write-Host "PASS principal accepted: $r"
} catch {
  $fail += "Interactive rejected: $_"
  Write-Host "FAIL Interactive rejected: $_"
}

# 2. The fake must reject the value that Windows rejects, otherwise it proves
#    nothing about the real call.
try {
  New-ScheduledTaskPrincipal -UserId $sid -LogonType InteractiveToken -RunLevel Highest | Out-Null
  $fail += 'fake accepted InteractiveToken, so the fake is wrong'
  Write-Host 'FAIL fake accepted InteractiveToken'
} catch {
  Write-Host 'PASS fake rejects InteractiveToken, as Windows does'
}

# 3. The installer itself must use the accepted value everywhere.
if ($src -match '-LogonType\s+InteractiveToken') {
  $fail += 'installer still uses InteractiveToken'
  Write-Host 'FAIL installer uses InteractiveToken'
} else {
  Write-Host 'PASS installer does not use InteractiveToken'
}
if ($src -match '-LogonType\s+Interactive\b') {
  Write-Host 'PASS installer uses -LogonType Interactive'
} else {
  $fail += 'installer has no -LogonType Interactive'
  Write-Host 'FAIL installer missing -LogonType Interactive'
}

# 4. Native programs must go through Invoke-Native. A bare call that writes to
#    stderr terminates the script under ErrorActionPreference='Stop', even on
#    exit code 0, which silently skips everything after it.
$bare = [regex]::Matches($src, '(?m)^\s*&\s*\$(python|ts|script:PythonExe)\b')
if ($bare.Count -gt 0) {
  $fail += "$($bare.Count) bare native call(s)"
  Write-Host "FAIL bare native calls: $($bare.Count)"
} else {
  Write-Host 'PASS no bare native calls'
}

# 5. Every native call that remains must be inside the helper.
if ($src -match 'function Invoke-Native') {
  Write-Host 'PASS Invoke-Native helper present'
} else {
  $fail += 'Invoke-Native helper missing'
  Write-Host 'FAIL Invoke-Native helper missing'
}

# 6. Download must be pinned to a commit SHA, because raw.githubusercontent.com
#    caches for 300s and ignores a cache-busting query, so a branch URL can
#    silently serve the previous revision.
if ($src -match 'raw\.githubusercontent\.com/\$Repo/\$Sha/') {
  Write-Host 'PASS download pinned to SHA'
} else {
  $fail += 'download is not pinned to a SHA'
  Write-Host 'FAIL download not pinned to SHA'
}

# 7. The worker task must not carry the token on its command line.
if ($src -match 'argLine\s*=\s*"[^"]*--token') {
  $fail += 'token on the task command line'
  Write-Host 'FAIL token exposed on command line'
} else {
  Write-Host 'PASS token kept out of the command line'
}

# 8. The task must run in the user session, or screenshots come back black.
if ($src -match 'New-ScheduledTaskPrincipal -UserId \$sid -LogonType Interactive') {
  Write-Host 'PASS worker principal runs in the user session'
} else {
  $fail += 'worker principal not in the user session'
  Write-Host 'FAIL worker principal wrong'
}

# 9. The config must be written without a BOM. Set-Content -Encoding UTF8 on
#    PowerShell 5.1 emits one and json.load rejects it, which killed the worker
#    on the first real run before it ever polled.
if ($src -match 'Set-Content[^\r\n]*worker-config') {
  $fail += 'config written with Set-Content (adds a BOM on 5.1)'
  Write-Host 'FAIL config written with Set-Content'
} else {
  Write-Host 'PASS config not written with Set-Content'
}
if ($src -match 'WriteAllText') {
  Write-Host 'PASS config written BOM-free with WriteAllText'
} else {
  $fail += 'config not written with WriteAllText'
  Write-Host 'FAIL config not written BOM-free'
}

# 10. Verify must compare the hostname and the age. A rendezvous keeps state, so
#     a leftover hello reads as success while nothing here is connected, which is
#     what the first real run reported.
if ($src -match 'hello\.hostname\s*-ne\s*\$env:COMPUTERNAME') {
  Write-Host 'PASS verify compares the hostname'
} else {
  $fail += 'verify does not compare the hostname'
  Write-Host 'FAIL verify does not compare the hostname'
}
if ($src -match 'HELLO_AGE_SECONDS') {
  Write-Host 'PASS verify checks hello freshness'
} else {
  $fail += 'verify does not check freshness'
  Write-Host 'FAIL verify does not check freshness'
}

# 11. A failed step must not print a bare SUCCESS.
if ($src -match 'FAILED_STEPS') {
  Write-Host 'PASS result reports failed step count'
} else {
  $fail += 'result hides failed steps'
  Write-Host 'FAIL result hides failed steps'
}

Write-Host ''
if ($fail.Count -gt 0) {
  Write-Host "FAILURES: $($fail -join ' | ')"
  exit 1
}
Write-Host 'ALL INSTALLER CHECKS PASSED'
