# Walk for a while and watch the world's brightness, to catch a fall.
#
# The earlier report was "83% black after walking", which reads as the character
# falling out of the map. Brightness is the right instrument: a fall shows as the
# view going dark and then a bright respawn flash, while a character walking on a
# platform keeps a lit view the whole way.
param(
  [string]$Title = 'Roblox',
  [int]$HoldMs = 900,
  [int]$Steps = 8
)

Add-Type -AssemblyName System.Drawing
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'

$h = [AxHelper.Win]::FindWindow($Title)
if ($h -eq [IntPtr]::Zero) { Write-Output "NO_WINDOW '$Title'"; exit 1 }
[AxHelper.Win]::Maximize($h) | Out-Null
Start-Sleep -Milliseconds 500
[AxHelper.Win]::Focus($h) | Out-Null
Start-Sleep -Milliseconds 700
$r = ([AxHelper.Win]::RectOf($h) -split ',')
$rx = [int]$r[0]; $ry = [int]$r[1]; $rw = [int]$r[2]; $rh = [int]$r[3]
Write-Output ("HWND=$h fg=" + ([AxHelper.Win]::Foreground() -eq $h))

function Read([string]$tag) {
  $p = "$env:TEMP\ax-fall-$tag.png"
  [AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $p) | Out-Null
  $bmp = [System.Drawing.Bitmap]::FromFile($p)
  $dark = 0; $n = 0
  for ($y = 0; $y -lt $bmp.Height; $y += 12) {
    for ($x = 0; $x -lt $bmp.Width; $x += 12) {
      $c = $bmp.GetPixel($x, $y)
      if (($c.R + $c.G + $c.B) -lt 60) { $dark++ }
      $n++
    }
  }
  $bmp.Dispose()
  Write-Output ("STEP $tag DARK_PCT=" + [Math]::Round(100.0 * $dark / [Math]::Max(1, $n), 1))
}

# Click once so the client has keyboard focus, then hold W for each step. The
# step is short enough that the character cannot cross the platform between
# readings.
[AxHelper.Win]::Click([int]($rx + $rw / 2), [int]($ry + $rh / 2))
Start-Sleep -Milliseconds 400
Read 'before'

for ($i = 1; $i -le $Steps; $i++) {
  [AxHelper.Win]::HoldKey(87, 17, $HoldMs) | Out-Null
  Start-Sleep -Milliseconds 300
  Read ('{0:d2}' -f $i)
}
