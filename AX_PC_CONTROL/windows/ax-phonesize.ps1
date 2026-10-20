# Look at the HUD at phone sizes.
#
# The HUD is laid out in fixed pixels against a 1280x720 reference, so judging it
# on this 1600x860 window says nothing about a phone. Resizing the client to real
# phone viewport sizes and photographing each one is what shows whether the
# panels collide, whether a touch target is too small, and whether anything sits
# under the topbar.
#
# Roblox only renders while it is the foreground window, so each size is focused
# again after the move.
param(
  [string]$Title = 'Roblox',
  [string]$OutDir = $env:TEMP
)

Add-Type -AssemblyName System.Drawing
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'

# Landscape phone viewports in logical points: a small Android, a common
# mid-range phone, and a large iPhone. The HUD has to survive all three.
$sizes = @(
  @{ name = 'small-640x360'; w = 640; h = 360 },
  @{ name = 'mid-800x375'; w = 800; h = 375 },
  @{ name = 'iphone-844x390'; w = 844; h = 390 }
)

$h = [AxHelper.Win]::FindWindow($Title)
if ($h -eq [IntPtr]::Zero) { Write-Output "NO_WINDOW '$Title'"; exit 1 }

function DarkPct([string]$path) {
  $bmp = [System.Drawing.Bitmap]::FromFile($path)
  $dark = 0; $n = 0
  for ($y = 0; $y -lt $bmp.Height; $y += 8) {
    for ($x = 0; $x -lt $bmp.Width; $x += 8) {
      $c = $bmp.GetPixel($x, $y)
      if (($c.R + $c.G + $c.B) -lt 60) { $dark++ }
      $n++
    }
  }
  $bmp.Dispose()
  return [Math]::Round(100.0 * $dark / [Math]::Max(1, $n), 1)
}

foreach ($s in $sizes) {
  $sw = [int]$s.w; $sh = [int]$s.h
  # Keep the window on screen: start at 0,0 so the client's own viewport is the
  # whole frame and nothing else clips the picture.
  [AxHelper.Win]::Move($h, 0, 0, $sw, $sh) | Out-Null
  Start-Sleep -Milliseconds 900
  [AxHelper.Win]::Focus($h) | Out-Null
  Start-Sleep -Milliseconds 1200

  $r = ([AxHelper.Win]::RectOf($h) -split ',')
  $rx = [int]$r[0]; $ry = [int]$r[1]; $rw = [int]$r[2]; $rh = [int]$r[3]
  $path = Join-Path $OutDir ("ax-phone-" + $s.name + ".png")
  [AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $path) | Out-Null
  Write-Output ("PHONE " + $s.name + " asked=${sw}x${sh} got=${rw}x${rh} at=$rx,$ry fg=" + ([AxHelper.Win]::Foreground() -eq $h) + " dark=" + (DarkPct $path) + " file=$path")
}

# Leave the window usable rather than tiny.
[AxHelper.Win]::Move($h, 0, 0, 1280, 720) | Out-Null
Start-Sleep -Milliseconds 600
[AxHelper.Win]::Focus($h) | Out-Null
Write-Output 'RESTORED 1280x720'
