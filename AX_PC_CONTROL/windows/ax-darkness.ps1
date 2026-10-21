# Photograph the live client and report how dark the world is.
#
# This is the cheap measurement that distinguishes a rendered world from the
# failure mode where only the HUD survives: the HUD is a small bright corner,
# so a frame that is almost entirely near-black means the 3D view is not
# drawing.
param(
  [string]$Title = 'Roblox',
  [string]$Out = "$env:TEMP\ax-view.png"
)

Add-Type -AssemblyName System.Drawing
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'

$h = [AxHelper.Win]::FindWindow($Title)
if ($h -eq [IntPtr]::Zero) { Write-Output "NO_WINDOW '$Title'"; exit 1 }
Write-Output ("BEFORE fg=" + ([AxHelper.Win]::Foreground() -eq $h))
[AxHelper.Win]::Maximize($h) | Out-Null
Start-Sleep -Milliseconds 600
[AxHelper.Win]::Focus($h) | Out-Null
Start-Sleep -Milliseconds 900

$r = ([AxHelper.Win]::RectOf($h) -split ',')
$rx = [int]$r[0]; $ry = [int]$r[1]; $rw = [int]$r[2]; $rh = [int]$r[3]
[AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $Out) | Out-Null

$bmp = [System.Drawing.Bitmap]::FromFile($Out)
$dark = 0; $n = 0; $sum = 0.0
for ($y = 0; $y -lt $bmp.Height; $y += 10) {
  for ($x = 0; $x -lt $bmp.Width; $x += 10) {
    $c = $bmp.GetPixel($x, $y)
    $v = $c.R + $c.G + $c.B
    if ($v -lt 60) { $dark++ }
    $sum += $v / 3.0
    $n++
  }
}
$bmp.Dispose()
Write-Output ("HWND=$h rect=$rx,$ry,$rw,$rh fg=" + ([AxHelper.Win]::Foreground() -eq $h))
Write-Output ("SHOT=$Out bytes=" + (Get-Item $Out).Length)
Write-Output ("DARK_PCT=" + [Math]::Round(100.0 * $dark / [Math]::Max(1, $n), 1) + " AVG_LUMA=" + [Math]::Round($sum / [Math]::Max(1, $n), 1))
