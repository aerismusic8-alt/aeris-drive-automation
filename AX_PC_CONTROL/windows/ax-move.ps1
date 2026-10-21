# Prove that input moves the character: capture, walk, capture again.
#
# Both captures happen in one process with no gap. Capturing in a separate call
# does not work, because the window loses focus in between and the second shot
# shows a different window.
#
# The before and after images are what a caller diffs to decide whether the game
# responded, rather than trusting that a key was sent.
param(
  [string]$Title = 'Roblox',
  [string]$Key = 'W',
  [int]$HoldMs = 2000,
  [string]$Before = "$env:TEMP\ax-move-before.png",
  [string]$After = "$env:TEMP\ax-move-after.png",
  [switch]$NoClick
)

$ErrorActionPreference = 'Continue'
$sw = [Diagnostics.Stopwatch]::StartNew()
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'

$h = [AxHelper.Win]::FindWindow($Title)
if ($h -eq [IntPtr]::Zero) { Write-Output "NO_WINDOW '$Title'"; exit 1 }
Write-Output "TARGET=$h title='$([AxHelper.Win]::TitleOf($h))' rect=$([AxHelper.Win]::RectOf($h))"

[AxHelper.Win]::Maximize($h)
Start-Sleep -Milliseconds 400
$focused = [AxHelper.Win]::Focus($h)
Start-Sleep -Milliseconds 500
Write-Output "FOCUSED=$focused t=$($sw.ElapsedMilliseconds)ms"

$rect = ([AxHelper.Win]::RectOf($h) -split ',')
$cx = [int]$rect[0] + [int]([int]$rect[2] / 2)
$cy = [int]$rect[1] + [int]([int]$rect[3] / 2)

if (-not $NoClick) {
  [AxHelper.Win]::Click($cx, $cy)
  Start-Sleep -Milliseconds 400
  Write-Output "CLICKED=$cx,$cy"
}

# Let the scene settle before the first frame, otherwise the before/after diff
# picks up animation rather than the effect of the key.
Start-Sleep -Milliseconds 800
$b1 = [AxHelper.Win]::CaptureScreen($Before)
Write-Output "BEFORE=$Before BYTES=$b1 t=$($sw.ElapsedMilliseconds)ms"

$letter = $Key.Substring(0, 1).ToUpper()
$vk = [int][char]$letter
$scan = 0
switch ($letter) {
  'W' { $scan = 17 } 'A' { $scan = 30 } 'S' { $scan = 31 } 'D' { $scan = 32 }
}
$sent = [AxHelper.Win]::HoldKey($vk, $scan, $HoldMs)
Write-Output "HELD=$letter vk=$vk scan=$scan ms=$HoldMs sent=$sent"

Start-Sleep -Milliseconds 800
$b2 = [AxHelper.Win]::CaptureScreen($After)
Write-Output "AFTER=$After BYTES=$b2 t=$($sw.ElapsedMilliseconds)ms"
