# A short play session: walk, turn, jump, and photograph each step.
#
# The frames are captured while the game is the foreground window, because
# Roblox stops rendering when it is not. Each capture has the movement that
# preceded it in the name, so the caller can pull them and see the character in
# different places rather than trusting a single frame.
#
# The client menu is closed first: ESC toggles it, and while it is open WASD is
# ignored. Frame darkness is the test, since the world is bright and the menu is
# almost entirely black.
param(
  [string]$Title = 'Roblox',
  [int]$StepMs = 2200,
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
Write-Output "GAME=$h rect=$($r -join ',') fg=$([AxHelper.Win]::Foreground() -eq $h)"

function Darkness([string]$path) {
  $bmp = [System.Drawing.Bitmap]::FromFile($path)
  $dark = 0; $total = 0
  for ($y = 0; $y -lt $bmp.Height; $y += 16) {
    for ($x = 0; $x -lt $bmp.Width; $x += 16) {
      $c = $bmp.GetPixel($x, $y)
      if (($c.R + $c.G + $c.B) -lt 90) { $dark++ }
      $total++
    }
  }
  $bmp.Dispose()
  return [Math]::Round(100.0 * $dark / $total, 1)
}

function Step([string]$name) {
  $p = Join-Path $OutDir "ax-session-$name.png"
  [AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $p) | Out-Null
  Write-Output ("STEP $name darkness=" + (Darkness $p) + "% bytes=" + (Get-Item $p).Length)
}

function Tap([int]$vk, [int]$scan) {
  [AxHelper.Win]::KeyDown($vk, $scan) | Out-Null
  Start-Sleep -Milliseconds 90
  [AxHelper.Win]::KeyUp($vk, $scan) | Out-Null
  Start-Sleep -Milliseconds 700
}

# Close the client menu if it is up.
$probe = Join-Path $OutDir 'ax-session-probe.png'
[AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $probe) | Out-Null
if ((Darkness $probe) -gt 55) {
  Write-Output 'MENU_OPEN closing'
  Tap 27 1
  Start-Sleep -Milliseconds 1200
}
[AxHelper.Win]::Focus($h) | Out-Null
Start-Sleep -Milliseconds 300

# Put the pointer in the 3D view so the world has control.
[AxHelper.Win]::Click([int]($rx + $rw / 2), [int]($ry + $rh / 2))
Start-Sleep -Milliseconds 400

Step 'start'

[AxHelper.Win]::HoldKey(87, 17, $StepMs) | Out-Null   # W forward
Start-Sleep -Milliseconds 700
Step 'after-W'

[AxHelper.Win]::HoldKey(68, 32, $StepMs) | Out-Null   # D right
Start-Sleep -Milliseconds 700
Step 'after-D'

Tap 32 57                                             # Space jump
Step 'after-jump'

[AxHelper.Win]::HoldKey(83, 31, $StepMs) | Out-Null   # S back
Start-Sleep -Milliseconds 700
Step 'after-S'

Write-Output ("FG_END=" + [AxHelper.Win]::TitleOf([AxHelper.Win]::Foreground()))
