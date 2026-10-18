# PC1: capture Studio's sign-in screen so the user can scan it from a phone
#
# Studio on PC1 is installed but not signed in (its own log shows an attempted
# QR sign-in that never completed). Roblox signs Studio in with a QR code that
# the Roblox mobile app scans. That is a phone-native flow: the user does not
# need Studio, a keyboard, or a computer.
#
# This script starts Studio in the interactive desktop session and photographs
# the screen so the QR code can be recovered from the image. It never reads a
# credential; a QR code for signing in is not a secret until it is scanned, and
# it expires in two minutes.

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "EXPECTED_PC1:$env:COMPUTERNAME" }

$ev = 'C:\AX-Runtime\evidence\studio-login'
New-Item -ItemType Directory -Path $ev -Force | Out-Null
Get-ChildItem -LiteralPath $ev -Filter '*.jpg' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$studioExe = $null
foreach ($dir in (Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue)) {
  $root = Join-Path $dir.FullName 'AppData\Local\Roblox\Versions'
  if (Test-Path -LiteralPath $root) {
    $found = Get-ChildItem -Path $root -Recurse -Filter 'RobloxStudioBeta.exe' -ErrorAction SilentlyContinue |
      Select-Object -First 1 -ExpandProperty FullName
    if ($found) { $studioExe = $found; break }
  }
}
if (!$studioExe) { throw 'STUDIO_NOT_FOUND' }
Write-Host "STUDIO_EXE=$studioExe"

# Stale instances fight over the single-instance lock and leave Studio frozen
# on its start page, which is what the earlier probe hit.
$stale = @(Get-Process -Name 'RobloxStudioBeta' -ErrorAction SilentlyContinue)
Write-Host "STALE_STUDIO_COUNT=$($stale.Count)"
foreach ($p in $stale) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; Write-Host "KILLED=$($p.Id)" } catch { Write-Host "KILL_FAILED=$($p.Id)" } }
Start-Sleep -Seconds 3

$u = (Get-CimInstance Win32_ComputerSystem).UserName
if (!$u) { throw 'NO_INTERACTIVE_USER' }
$sid = ([System.Security.Principal.NTAccount]$u).Translate([System.Security.Principal.SecurityIdentifier]).Value
Write-Host "INTERACTIVE_USER=$u"

# --- Runner: launch Studio and take timed screenshots --------------------
$runner = 'C:\AX-Build\studio-login-capture.ps1'
New-Item -ItemType Directory -Path 'C:\AX-Build' -Force | Out-Null
$runnerBody = @'
param([string]$StudioExe, [string]$OutDir)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$proc = Start-Process -FilePath $StudioExe -PassThru
"LAUNCHED_PID=$($proc.Id)" | Write-Host

# Studio needs time to paint the start page and fetch its login QR.
$shots = @(45)
$prev = 0
foreach ($t in $shots) {
  Start-Sleep -Seconds ($t - $prev)
  $prev = $t
  try {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bmp = New-Object System.Drawing.Bitmap($screen.Bounds.Width, $screen.Bounds.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($screen.Bounds.Location, [System.Drawing.Point]::Empty, $screen.Bounds.Size)
    $file = Join-Path $OutDir ("login-$t" + "s.jpg")
    # Crop to the middle band where Studio paints the code and store as JPEG:
    # the full-screen PNG takes ~25s to upload, the code expires in ~120s.
    $band = New-Object System.Drawing.Rectangle(
      [int]($screen.Bounds.Width * 0.5), [int]($screen.Bounds.Height * 0.35),
      [int]($screen.Bounds.Width * 0.3), [int]($screen.Bounds.Height * 0.4))
    $crop = $bmp.Clone($band, $bmp.PixelFormat)
    $crop.Save($file, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $crop.Dispose()
    $g.Dispose(); $bmp.Dispose()
    "SHOT=$file BYTES=$((Get-Item $file).Length) AT=$((Get-Date).ToUniversalTime().ToString('o'))" | Write-Host
  } catch {
    "SHOT_FAILED=$t EX=$($_.Exception.Message)" | Write-Host
  }
  # Window titles tell us whether Studio reached its sign-in page.
  $fg = [System.Windows.Forms.Form]::ActiveForm
  "ACTIVE_FORM=$($fg.Title)" | Write-Host
  foreach ($p in (Get-Process -Name 'RobloxStudioBeta' -ErrorAction SilentlyContinue)) {
    if ($p.MainWindowTitle) { "STUDIO_WINDOW=$($p.MainWindowTitle)" | Write-Host }
  }
}
"CAPTURE_DONE=1" | Write-Host
'@
Set-Content -LiteralPath $runner -Value $runnerBody -Encoding UTF8

$name = 'AERIS-PC1-STUDIO-LOGIN-QR'
Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
$arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -StudioExe "{1}" -OutDir "{2}"' -f $runner, $studioExe, $ev
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$principal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 6)
Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $name
Write-Host "CAPTURE_TASK_STARTED=1"

$deadline = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $deadline -and !(Test-Path (Join-Path $ev 'login-45s.jpg'))) { Start-Sleep -Milliseconds 700 }

$shots = @(Get-ChildItem -LiteralPath $ev -Filter '*.jpg' -ErrorAction SilentlyContinue)
Write-Host "PNG_COUNT=$($shots.Count)"
foreach ($s in $shots) { Write-Host ("PNG={0} BYTES={1}" -f $s.FullName, $s.Length) }

@{
  status = if ($shots.Count -gt 0) { 'CAPTURED' } else { 'NO_SCREENSHOT' }
  shotCount = $shots.Count
  interactiveUser = $u
  studioExe = $studioExe
  capturedAt = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json | Set-Content (Join-Path 'C:\AX-Runtime\evidence' 'pc1-studio-login.json') -Encoding UTF8

Write-Host "LOGIN_CAPTURE=COMPLETE"
