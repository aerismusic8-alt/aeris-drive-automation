# Play: close the client menu, then walk and prove the world responded.
#
# ESC opens the Roblox client menu, which is a dark overlay that swallows
# movement keys. The first job is therefore to close it and confirm the game
# world is visible again, which is done by measuring how much of the frame is
# black: the world is bright, the menu is nearly all black.
#
# Only then is W held. The before and after frames are compared by the caller,
# and the frames are left on disk to be pulled.
param(
  [string]$Title = 'Roblox',
  [int]$HoldMs = 2500,
  [string]$OutDir = $env:TEMP
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'

$h = [AxHelper.Win]::FindWindow($Title)
if ($h -eq [IntPtr]::Zero) { Write-Output "NO_WINDOW '$Title'"; exit 1 }
[AxHelper.Win]::Maximize($h)
Start-Sleep -Milliseconds 400
[AxHelper.Win]::Focus($h) | Out-Null
Start-Sleep -Milliseconds 600

$r = ([AxHelper.Win]::RectOf($h) -split ',')
$rx = [int]$r[0]; $ry = [int]$r[1]; $rw = [int]$r[2]; $rh = [int]$r[3]

function Shot([string]$name) {
  $p = Join-Path $OutDir $name
  [AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $p) | Out-Null
  return $p
}

# How dark is the frame? The client menu is almost entirely black, the world is
# bright, so this is a reliable "is a menu covering the game" test.
function Darkness([string]$path) {
  $bmp = [System.Drawing.Bitmap]::FromFile($path)
  $dark = 0; $total = 0
  for ($y = 0; $y -lt $bmp.Height; $y += 12) {
    for ($x = 0; $x -lt $bmp.Width; $x += 12) {
      $c = $bmp.GetPixel($x, $y)
      if (($c.R + $c.G + $c.B) -lt 90) { $dark++ }
      $total++
    }
  }
  $bmp.Dispose()
  return [Math]::Round(100.0 * $dark / $total, 1)
}

function TapKey([int]$vk, [int]$scan) {
  [AxHelper.Win]::KeyDown($vk, $scan) | Out-Null
  Start-Sleep -Milliseconds 90
  [AxHelper.Win]::KeyUp($vk, $scan) | Out-Null
}

$p = Shot 'ax-play-a.png'
Write-Output ("A darkness=" + (Darkness $p) + "%")

# Close the client menu if it is open. ESC toggles it.
if ((Darkness $p) -gt 60) {
  Write-Output 'MENU_OPEN closing'
  TapKey 27 1
  Start-Sleep -Milliseconds 1500
  $p = Shot 'ax-play-a.png'
  Write-Output ("A2 darkness=" + (Darkness $p) + "%")
}

Write-Output ("FG=" + ([AxHelper.Win]::Foreground() -eq $h))

# Click into the 3D view so the pointer is over the world, then walk.
[AxHelper.Win]::Click([int]($rx + $rw / 2), [int]($ry + $rh / 2))
Start-Sleep -Milliseconds 500
$before = Shot 'ax-play-before.png'
Write-Output ("BEFORE=" + $before + " darkness=" + (Darkness $before) + "%")

[AxHelper.Win]::HoldKey(87, 17, $HoldMs) | Out-Null
Start-Sleep -Milliseconds 900
$after = Shot 'ax-play-after.png'
Write-Output ("AFTER=" + $after + " darkness=" + (Darkness $after) + "%")

# A second move in a different direction, to see the scene change again.
[AxHelper.Win]::HoldKey(68, 32, 1500) | Out-Null
Start-Sleep -Milliseconds 900
$after2 = Shot 'ax-play-after2.png'
Write-Output ("AFTER2=" + $after2 + " darkness=" + (Darkness $after2) + "%")
