# Walk in short bursts and photograph each one.
#
# A single before/after pair cannot tell a slow walk from a teleport or from a
# scene change. Capturing after each short hold shows the view creeping forward,
# which is what movement actually looks like, and it keeps each step small enough
# that the character cannot run off the platform in one go.
param(
  [string]$Title = 'Roblox',
  [int]$BurstMs = 450,
  [int]$Bursts = 6,
  [string]$OutDir = $env:TEMP
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'

$h = [AxHelper.Win]::FindWindow($Title)
if ($h -eq [IntPtr]::Zero) { Write-Output "NO_WINDOW '$Title'"; exit 1 }
[AxHelper.Win]::Maximize($h)
Start-Sleep -Milliseconds 500
[AxHelper.Win]::Focus($h) | Out-Null
Start-Sleep -Milliseconds 700
$r = ([AxHelper.Win]::RectOf($h) -split ',')
$rx = [int]$r[0]; $ry = [int]$r[1]; $rw = [int]$r[2]; $rh = [int]$r[3]
Write-Output "GAME=$h fg=$([AxHelper.Win]::Foreground() -eq $h)"

function Shot([string]$name) {
  $p = Join-Path $OutDir "ax-burst-$name.png"
  [AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $p) | Out-Null
  $bmp = [System.Drawing.Bitmap]::FromFile($p)
  # Sample a coarse grid to get a cheap signature of the frame, so the log shows
  # whether the view changed without needing the images back in the sandbox.
  $sum = 0; $n = 0
  for ($y = 0; $y -lt $bmp.Height; $y += 40) {
    for ($x = 0; $x -lt $bmp.Width; $x += 40) {
      $c = $bmp.GetPixel($x, $y); $sum += ($c.R + $c.G + $c.B); $n++
    }
  }
  $bmp.Dispose()
  Write-Output ("BURST $name sig=" + [Math]::Round($sum / [Math]::Max(1, $n), 1) + " bytes=" + (Get-Item $p).Length)
}

[AxHelper.Win]::Click([int]($rx + $rw / 2), [int]($ry + $rh / 2))
Start-Sleep -Milliseconds 400
Shot '00'

for ($i = 1; $i -le $Bursts; $i++) {
  [AxHelper.Win]::HoldKey(87, 17, $BurstMs) | Out-Null
  Start-Sleep -Milliseconds 250
  Shot ('{0:d2}-W' -f $i)
}

# Turn with the mouse so the camera pans, which is a different sort of movement.
[AxHelper.Win]::MoveTo([int]($rx + $rw / 2), [int]($ry + $rh / 2))
Start-Sleep -Milliseconds 200
[AxHelper.Win]::MouseMoveRel(220, 0) | Out-Null
Start-Sleep -Milliseconds 700
Shot '99-turn'
