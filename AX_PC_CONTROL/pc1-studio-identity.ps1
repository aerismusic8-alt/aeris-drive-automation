# PC1: ask Studio what account it is signed in as
#
# Read-only. Uses the documented Studio CLI (--task RunScript) to run one
# small Luau file inside Studio and capture its output. It answers the only
# question that blocks the whole publish path: is PC1's Studio signed in, and
# can that account own a place?
#
# It never reads, copies, or transmits a credential. Studio reports its own
# user id; that is all.
#
# Writes C:\AX-Runtime\evidence\pc1-studio-identity.json

$ErrorActionPreference = 'Stop'

if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "EXPECTED_PC1:$env:COMPUTERNAME" }

$evidenceDir = 'C:\AX-Runtime\evidence'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$evidencePath = Join-Path $evidenceDir 'pc1-studio-identity.json'

function Write-Evidence($obj) {
  Set-Content -LiteralPath $evidencePath -Value ($obj | ConvertTo-Json -Depth 6) -Encoding UTF8
}

# --- Locate Studio --------------------------------------------------------
$studioExe = $null
foreach ($dir in (Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue)) {
  $root = Join-Path $dir.FullName 'AppData\Local\Roblox\Versions'
  if (Test-Path -LiteralPath $root) {
    $found = Get-ChildItem -Path $root -Recurse -Filter 'RobloxStudioBeta.exe' -ErrorAction SilentlyContinue |
      Select-Object -First 1 -ExpandProperty FullName
    if ($found) { $studioExe = $found; break }
  }
}

if (!$studioExe) {
  Write-Host "STUDIO=NOT_INSTALLED"
  Write-Evidence ([ordered]@{ status = 'NO_STUDIO'; hostname = $env:COMPUTERNAME })
  exit 0
}
Write-Host "STUDIO_EXE=$studioExe"

# --- Fetch the probe script ----------------------------------------------
$probeUrl = "https://raw.githubusercontent.com/aerismusic8-alt/aeris-drive-automation/$env:GITHUB_SHA/AX_PC_CONTROL/probe-identity.luau"
$probe = 'C:\AX-Build\probe-identity.luau'
New-Item -ItemType Directory -Path 'C:\AX-Build' -Force | Out-Null
Invoke-WebRequest -Uri $probeUrl -OutFile $probe -UseBasicParsing
Write-Host "PROBE_SCRIPT=$probe"

$outLog = 'C:\AX-Build\probe-identity.out.log'
if (Test-Path $outLog) { Remove-Item $outLog -Force }

# RunScript needs the interactive user's desktop session for a signed-in
# Studio, so it is launched through a scheduled task, the same way the
# existing interactive capture workflow does it.
$u = (Get-CimInstance Win32_ComputerSystem).UserName
if (!$u) { throw "NO_INTERACTIVE_USER" }
$sid = ([System.Security.Principal.NTAccount]$u).Translate([System.Security.Principal.SecurityIdentifier]).Value
Write-Host "INTERACTIVE_USER=$u"

$arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -StudioExe "{1}" -Probe "{2}" -Out "{3}"' -f `
  'C:\AX-Build\probe-identity-run.ps1', $studioExe, $probe, $outLog

$runner = 'C:\AX-Build\probe-identity-run.ps1'
$runnerBody = @'
param([string]$StudioExe, [string]$Probe, [string]$Out)
$ErrorActionPreference = 'Continue'
$runLog = 'C:\AX-Build\studio-run.log'
"START $(Get-Date -Format o)" | Set-Content -LiteralPath $runLog -Encoding UTF8
try {
  # Studio writes verbose logs to stdout; capture both streams so a failure is
  # visible instead of silent.
  & $StudioExe --task RunScript --runScriptFile $Probe --outputFile $Out --quitAfterExecution *>> $runLog
  "EXIT=$LASTEXITCODE" | Add-Content -LiteralPath $runLog -Encoding UTF8
} catch {
  "EXCEPTION=$($_.Exception.Message)" | Add-Content -LiteralPath $runLog -Encoding UTF8
}
"END $(Get-Date -Format o)" | Add-Content -LiteralPath $runLog -Encoding UTF8
'@
Set-Content -LiteralPath $runner -Value $runnerBody -Encoding UTF8

$name = 'AERIS-PC1-STUDIO-IDENTITY-PROBE'
Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$principal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $name
Write-Host "PROBE_STARTED=1"

# --- Wait for the output file -------------------------------------------
$deadline = (Get-Date).AddSeconds(240)
while ((Get-Date) -lt $deadline -and !(Test-Path $outLog)) { Start-Sleep -Milliseconds 1000 }
if (!(Test-Path $outLog)) {
  Write-Host "PROBE=NO_OUTPUT"
  $runLog = 'C:\AX-Build\studio-run.log'
  if (Test-Path $runLog) {
    Write-Host "--- studio-run.log (tail) ---"
    Get-Content -LiteralPath $runLog -Tail 40 | Write-Host
    Write-Host "--- end ---"
  } else {
    Write-Host "STUDIO_RUN_LOG=MISSING (Studio process never started)"
  }
  $latestLog = Get-ChildItem 'C:\Users\User\AppData\Local\Roblox\logs' -Filter '*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($latestLog) {
    Write-Host "ROBLOX_LOG=$($latestLog.FullName)"
    Get-Content -LiteralPath $latestLog.FullName -Tail 25 | Write-Host
  }
  Write-Evidence ([ordered]@{ status = 'NO_OUTPUT'; studioExe = $studioExe; interactiveUser = $u })
  Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
  exit 0
}

# Let Studio finish flushing.
Start-Sleep -Seconds 5
$raw = Get-Content -LiteralPath $outLog -Raw
Write-Host "PROBE_OUTPUT_BYTES=$($raw.Length)"

$fields = @{}
foreach ($line in ($raw -split "`r?`n")) {
  $t = $line.Trim()
  if ($t -match '^([A-Z_]+)=(.*)$') { $fields[$matches[1]] = $matches[2] }
}

Write-Host "PROBE=COMPLETE"
foreach ($k in $fields.Keys) { Write-Host ("PROBE_{0}={1}" -f $k, $fields[$k]) }

Write-Evidence ([ordered]@{
  schemaVersion   = 1
  capturedAt      = (Get-Date).ToUniversalTime().ToString('o')
  hostname        = $env:COMPUTERNAME
  status          = 'COMPLETE'
  interactiveUser = $u
  studioExe       = $studioExe
  fields          = $fields
  rawBytes        = $raw.Length
})

Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "IDENTITY_EVIDENCE=$evidencePath"
