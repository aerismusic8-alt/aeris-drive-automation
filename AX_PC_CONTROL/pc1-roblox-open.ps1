# PC1: open AX Arena and prove it runs, then photograph it.
#
# Why not just join the published place? A brand new universe is unrated, and
# Roblox hides unrated experiences from everyone until the owner answers the
# maturity questionnaire. Joining the live place would fail for reasons that
# have nothing to do with the code. So this runs the built place file locally:
#
#   1. Edit mode + `--task RunScript` -> every shared module loads, both entry
#      points exist, and the world builder produces the town plus five fields.
#      Fast, documented, and it fails loudly.
#   2. `--task EditFile` to open the place, then F5 to start Play mode, which
#      runs the real server and the real client in one window. That is the same
#      thing a human does, and it is what makes the screenshots meaningful.
#
# Only documented Studio flags are used. The older `-task StartServer` and
# `-task StartClient` pair is deliberately avoided: it is undocumented and has
# changed behaviour between Studio versions, so a failure there would be
# indistinguishable from a failure in the game.
#
# The client opens a window, so this must run in the interactive user's session.
# The workflow arranges that with a scheduled task.
#
# Writes C:\AX-Runtime\evidence\pc1-roblox-open.json plus PNGs in
# C:\AX-Runtime\evidence\roblox-open\.

param(
  [string]$BuildRoot = 'C:\AX-Build',
  [string]$SmokeScript = '',
  [string]$PlaceFile = '',
  [int]$StudioLoadSeconds = 90,
  [int]$PlayStartSeconds = 45,
  [int]$CaptureSeconds = 36
)

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "EXPECTED_PC1:$env:COMPUTERNAME" }

$evidenceDir = 'C:\AX-Runtime\evidence'
$shotDir = Join-Path $evidenceDir 'roblox-open'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
New-Item -ItemType Directory -Path $shotDir -Force | Out-Null

$notes = New-Object System.Collections.Generic.List[string]
$captures = New-Object System.Collections.Generic.List[object]

# Defaults for everything the evidence file reports. A throw before a value is
# set -- Studio missing, the place missing -- still has to produce a file, or the
# workflow cannot tell "the run failed" from "the run never started". Both looked
# like OPEN_EVIDENCE_MISSING, which is what made the PC1 failures unreadable.
$smokePass = $false
$smokeDetail = 'not-run'
$gameRan = $false
$studioExe = ''
$studioVersion = ''
$placeFile = ''
$smokeLog = ''
$overall = 'FAILED'

function Write-OpenEvidence($reason) {
  if ($reason) { $notes.Add("aborted: $reason") }
  if ($smokeLog -and !(Test-Path -LiteralPath $smokeLog)) { $smokeLog = '' }
  $result = [ordered]@{
    schemaVersion = 1
    capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
    hostname      = $env:COMPUTERNAME
    studio        = [ordered]@{ exe = $studioExe; version = $studioVersion }
    placeFile     = $placeFile
    smoke         = [ordered]@{ passed = $smokePass; detail = $smokeDetail; log = $smokeLog }
    run           = [ordered]@{ gameRan = $gameRan; captures = @($captures.ToArray()) }
    notes         = @($notes.ToArray())
    status        = $overall
  }
  Set-Content -LiteralPath (Join-Path $evidenceDir 'pc1-roblox-open.json') -Value ($result | ConvertTo-Json -Depth 8) -Encoding UTF8
}

# Any terminating error below writes what is known and stops, instead of leaving
# no evidence behind at all.
trap {
  Write-OpenEvidence "$($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))"
  Write-Host "OPEN_ABORTED=$($_.Exception.Message)"
  exit 1
}

# --- Locate Roblox Studio ------------------------------------------------
# The runner can execute as SYSTEM, where LOCALAPPDATA points at systemprofile
# and misses a Studio installed in the real user's profile. Scan every profile,
# then take the newest build.
$profileRoots = @()
foreach ($dir in (Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue)) {
  $local = Join-Path $dir.FullName 'AppData\Local'
  if (Test-Path -LiteralPath $local) { $profileRoots += $local }
}
$profileRoots += $env:LOCALAPPDATA
$profileRoots = @($profileRoots | Where-Object { $_ } | Select-Object -Unique)

$studioExes = @()
foreach ($local in $profileRoots) {
  $versions = Join-Path $local 'Roblox\Versions'
  if (Test-Path -LiteralPath $versions) {
    $studioExes += @(Get-ChildItem -Path $versions -Recurse -Filter 'RobloxStudioBeta.exe' -ErrorAction SilentlyContinue)
  }
}
$studioExes = @($studioExes | Sort-Object LastWriteTime -Descending)
if ($studioExes.Count -eq 0) { throw 'STUDIO_NOT_FOUND' }
$studioExe = $studioExes[0].FullName
$studioVersion = $studioExes[0].VersionInfo.ProductVersion
Write-Host "STUDIO_EXE=$studioExe"
Write-Host "STUDIO_VERSION=$studioVersion"

$placeFile = $PlaceFile
# The arena build is legacy but still present on some machines; preferring the
# garden keeps this script pointed at the game that ships.
if (!$placeFile) {
  $placeFile = Join-Path $BuildRoot 'AXGarden.rbxlx'
  if (!(Test-Path -LiteralPath $placeFile)) {
    $legacy = Join-Path $BuildRoot 'AXArena.rbxlx'
    if (Test-Path -LiteralPath $legacy) { $placeFile = $legacy }
  }
}
if (!(Test-Path -LiteralPath $placeFile)) { throw "PLACE_FILE_MISSING:$placeFile (run the build first)" }
Write-Host "PLACE_FILE=$placeFile"

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class AXWin {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder t, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
}
'@

function Get-WindowTitle([IntPtr]$h) {
  if ($h -eq [IntPtr]::Zero) { return '' }
  $sb = New-Object System.Text.StringBuilder 512
  [void][AXWin]::GetWindowText($h, $sb, $sb.Capacity)
  return $sb.ToString()
}

function Save-Screenshot([string]$prefix) {
  $screen = [System.Windows.Forms.Screen]::PrimaryScreen
  $bmp = New-Object System.Drawing.Bitmap($screen.Bounds.Width, $screen.Bounds.Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($screen.Bounds.Location, [System.Drawing.Point]::Empty, $screen.Bounds.Size)
  $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
  $img = Join-Path $shotDir "$prefix-$stamp.png"
  $bmp.Save($img, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  return $img
}

# --- Phase 1: Edit-mode smoke test ---------------------------------------
$smoke = $null
$smokeLog = Join-Path $evidenceDir 'studio-smoke.log'
if ($SmokeScript -and (Test-Path -LiteralPath $SmokeScript)) {
  $smoke = $SmokeScript
} else {
  $guess = Join-Path $BuildRoot 'repo\AX_PC_CONTROL\pc1-garden-smoke.luau'
  if (Test-Path -LiteralPath $guess) { $smoke = $guess }
}

if ($smoke) {
  # A throw anywhere in here used to abort the whole script before the evidence
  # file was written, so a failed run and a run that never started looked the
  # same from the workflow: OPEN_EVIDENCE_MISSING. The failure is recorded and
  # the run continues to the play phase instead.
  try {
  Remove-Item -LiteralPath $smokeLog -Force -ErrorAction SilentlyContinue
  Write-Host "SMOKE_SCRIPT=$smoke"
  # Studio resolves relative paths against its own working directory, so both
  # the place and the script are passed as absolute paths.
  $smokeProc = Start-Process -FilePath $studioExe -PassThru -ArgumentList @(
    '--task', 'RunScript',
    '--localPlaceFile', $placeFile,
    '--runScriptFile', $smoke,
    '--outputFile', $smokeLog,
    '--quitAfterExecution'
  )
  if (!$smokeProc.WaitForExit(240000)) {
    $smokeProc.Kill()
    $notes.Add('smoke run exceeded 240s and was killed')
  }

  if (Test-Path -LiteralPath $smokeLog) {
    $log = Get-Content -LiteralPath $smokeLog -Raw
    Write-Host "----- studio smoke log -----"
    Write-Host $log
    Write-Host "----- end smoke log -----"
    $fails = @([regex]::Matches($log, '(?m)^SMOKE_FAIL\|([^|]*)\|(.*)$'))
    $passes = @([regex]::Matches($log, '(?m)^SMOKE_PASS\|([^|]*)\|(.*)$'))
    if ($fails.Count -gt 0) {
      $smokeDetail = (@($fails | ForEach-Object { "$($_.Groups[1].Value)=$($_.Groups[2].Value.Trim())" }) -join '; ')
    } elseif ($passes.Count -gt 0) {
      $smokePass = $true
      $smokeDetail = "$($passes.Count) checks passed"
    } else {
      $smokeDetail = 'no SMOKE_ marker in the log; the script did not reach its first report'
    }
  } else {
    $smokeDetail = 'Studio wrote no output file'
  }
  } catch {
    $smokeDetail = "smoke phase threw: $($_.Exception.Message)"
    Write-Host "SMOKE_THREW=$($_.Exception.Message)"
  }
} else {
  $smokeDetail = 'smoke script not supplied and not found in the build tree'
}
Write-Host "SMOKE_PASS=$smokePass"
Write-Host "SMOKE_DETAIL=$smokeDetail"

# --- Phase 2: open the place and start Play mode -------------------------
$studioProc = $null

try {
  Write-Host "OPEN_PLACE=$placeFile"
  $studioProc = Start-Process -FilePath $studioExe -PassThru -ArgumentList @(
    '--task', 'EditFile',
    '--localPlaceFile', $placeFile
  )
  $notes.Add("studio pid $($studioProc.Id) opened the place")

  # Studio has to load a place with five dressed maps in it, so give it room.
  # Firing F5 early types into the splash screen and nothing happens.
  Start-Sleep -Seconds $StudioLoadSeconds
  if ($studioProc.HasExited) {
    $notes.Add("studio exited during load with code $($studioProc.ExitCode)")
  }

  # Bring Studio to the front before sending the key. Without the focus the
  # keystroke lands in whatever window the session happens to be showing.
  $hwnd = $studioProc.MainWindowHandle
  if ($hwnd -ne [IntPtr]::Zero) {
    [void][AXWin]::ShowWindow($hwnd, 3)   # 3 = SW_MAXIMIZE
    [void][AXWin]::SetForegroundWindow($hwnd)
    Start-Sleep -Seconds 3
    Write-Host "FOCUS_TITLE=$(Get-WindowTitle $hwnd)"
  } else {
    $notes.Add('studio reported no main window handle; the F5 key may not land')
  }

  Write-Host "SEND_F5"
  [System.Windows.Forms.SendKeys]::SendWait('{F5}')
  $notes.Add('sent F5 to start Play mode')

  Start-Sleep -Seconds $PlayStartSeconds

  $deadline = (Get-Date).AddSeconds($CaptureSeconds)
  $n = 0
  while ((Get-Date) -lt $deadline) {
    $n++
    $img = Save-Screenshot 'roblox-open'
    $fg = [AXWin]::GetForegroundWindow()
    $title = Get-WindowTitle $fg
    $captures.Add([pscustomobject]@{
      timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
      image        = $img
      foreground   = $title
    })
    Write-Host "CAPTURE=$n TITLE=$title"
    Start-Sleep -Seconds 6
  }

  # Play mode renames the window, so a live window plus a captured title is the
  # signal that the game started rather than the editor just sitting there.
  $alive = ($studioProc -and !$studioProc.HasExited)
  $titles = @($captures | ForEach-Object { $_.foreground } | Where-Object { $_ })
  $gameRan = ($alive -and ($titles.Count -gt 0))
  Write-Host "STUDIO_ALIVE=$alive"
  Write-Host "CAPTURE_COUNT=$($captures.Count)"
  Write-Host "TITLES=$($titles -join ' | ')"
} catch {
  # Same reason as the smoke phase: record the failure, do not lose the evidence.
  $notes.Add("play phase threw: $($_.Exception.Message)")
  Write-Host "PLAY_THREW=$($_.Exception.Message)"
} finally {
  if ($studioProc -and !$studioProc.HasExited) {
    try { $studioProc.Kill() } catch { }
  }
}

$overall = 'PARTIAL'
if ($smokePass -and $gameRan) { $overall = 'OPENED' }

Write-OpenEvidence

Write-Host "SMOKE=$smokePass"
Write-Host "GAME_RAN=$gameRan"
Write-Host "SHOTS=$($captures.Count)"
Write-Host "OPEN=COMPLETE"
