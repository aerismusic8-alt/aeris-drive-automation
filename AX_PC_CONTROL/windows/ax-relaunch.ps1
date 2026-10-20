# Relaunch the live Roblox client on this place and report how the world looks.
#
# Roblox only serves the place version that was live when the client joined, so
# a change to Lighting cannot be seen in a client that is already running.
# Closing and reopening through the roblox:// protocol is what picks up the new
# version, and the darkness reading before and after is the evidence that the
# world now renders instead of showing only the HUD.
#
# Launching a windowed app needs the interactive desktop, so this is meant to be
# run from the interactive session (a scheduled task owned by the logged-in user)
# rather than from a service context.
param(
  [long]$PlaceId = 79945905295644,
  [int]$WaitSeconds = 75,
  [string]$OutDir = $env:TEMP
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'

function DarkPct([string]$path) {
  $bmp = [System.Drawing.Bitmap]::FromFile($path)
  $dark = 0; $n = 0
  for ($y = 0; $y -lt $bmp.Height; $y += 12) {
    for ($x = 0; $x -lt $bmp.Width; $x += 12) {
      $c = $bmp.GetPixel($x, $y)
      if (($c.R + $c.G + $c.B) -lt 60) { $dark++ }
      $n++
    }
  }
  $bmp.Dispose()
  return [Math]::Round(100.0 * $dark / [Math]::Max(1, $n), 1)
}

# Close the running client. Target the image name, which belongs to Roblox and
# to nothing else here, rather than a broad process match.
$old = Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue
if ($old) {
  Write-Output ("KILLING old client pids=" + (($old | ForEach-Object { $_.Id }) -join ','))
  $old | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 4
} else {
  Write-Output 'NO_RUNNING_CLIENT'
}

# The modern deep link. The older placeId form is kept as a fallback because the
# handler accepts one or the other depending on the client version.
$links = @(
  "roblox://experiences/start?placeId=$PlaceId",
  "roblox://placeId=$PlaceId"
)
foreach ($link in $links) {
  Write-Output "LAUNCH $link"
  try { Start-Process $link | Out-Null } catch { Write-Output ("LAUNCH_ERR " + $_.Exception.Message) }
  Start-Sleep -Seconds 6
  $p = Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue
  if ($p) { Write-Output ("CLIENT_STARTED pid=" + (($p | ForEach-Object { $_.Id }) -join ',')); break }
}

# Wait for the window, then read the world.
$h = [IntPtr]::Zero
$deadline = (Get-Date).AddSeconds($WaitSeconds)
while ((Get-Date) -lt $deadline) {
  $h = [AxHelper.Win]::FindWindow('Roblox')
  if ($h -ne [IntPtr]::Zero) { break }
  Start-Sleep -Seconds 3
}
if ($h -eq [IntPtr]::Zero) { Write-Output 'NO_WINDOW_AFTER_WAIT'; exit 1 }

Start-Sleep -Seconds 12   # let the place stream in
[AxHelper.Win]::Maximize($h)
Start-Sleep -Milliseconds 500
[AxHelper.Win]::Focus($h) | Out-Null
Start-Sleep -Milliseconds 700
$r = ([AxHelper.Win]::RectOf($h) -split ',')
$rx = [int]$r[0]; $ry = [int]$r[1]; $rw = [int]$r[2]; $rh = [int]$r[3]

$shot = Join-Path $OutDir 'ax-relaunch.png'
[AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $shot) | Out-Null
Write-Output ("HWND=$h rect=$rx,$ry,$rw,$rh")
Write-Output ("SHOT=$shot bytes=" + (Get-Item $shot).Length)
Write-Output ("DARK_PCT=" + (DarkPct $shot))
