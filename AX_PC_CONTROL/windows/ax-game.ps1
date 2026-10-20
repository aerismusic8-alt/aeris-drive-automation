# Drive the game on PC1: look, walk, jump, click.
#
# Uses the prebuilt ax-helper.dll, so it starts in milliseconds. Compiling the
# helper inline on every call took minutes and never fit the 30 second cap on a
# remote Shell call.
#
# Actions:
#   look  - focus the window and screenshot it
#   walk  - focus, click into the game, hold a movement key, screenshot after
#   tap   - press and release one key
#   click - click a point and screenshot after
param(
  [ValidateSet('look', 'walk', 'tap', 'click')]
  [string]$Action = 'look',
  [string]$Title = 'Roblox',
  [string]$Key = 'W',
  [int]$HoldMs = 1500,
  [int]$X = -1,
  [int]$Y = -1,
  [string]$Shot = "$env:TEMP\ax-game.png",
  [switch]$Maximize
)

$ErrorActionPreference = 'Continue'
$sw = [Diagnostics.Stopwatch]::StartNew()
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$dll = 'C:\AX-Runtime\evidence\ax-helper.dll'
if (-not (Test-Path $dll)) { Write-Output "NO_DLL $dll"; exit 1 }
Add-Type -Path $dll
Write-Output "T_load=$($sw.ElapsedMilliseconds)ms"

$h = [AxHelper.Win]::FindWindow($Title)
if ($h -eq [IntPtr]::Zero) { Write-Output "NO_WINDOW '$Title'"; exit 1 }
Write-Output "TARGET=$h title='$([AxHelper.Win]::TitleOf($h))' rect=$([AxHelper.Win]::RectOf($h))"

if ($Maximize) { [AxHelper.Win]::Maximize($h); Start-Sleep -Milliseconds 500 }
$focused = [AxHelper.Win]::Focus($h)
Start-Sleep -Milliseconds 500
Write-Output "FOCUSED=$focused t=$($sw.ElapsedMilliseconds)ms"

# Clicking the middle of the window does two things the game needs: it confirms
# the window has focus, and it puts the pointer inside the 3D view so the camera
# responds to the mouse.
$rect = ([AxHelper.Win]::RectOf($h) -split ',')
$cx = [int]$rect[0] + [int]([int]$rect[2] / 2)
$cy = [int]$rect[1] + [int]([int]$rect[3] / 2)

switch ($Action) {
  'look' { }
  'walk' {
    [AxHelper.Win]::Click($cx, $cy)
    Start-Sleep -Milliseconds 300
    Write-Output "CLICKED=$cx,$cy"
    $letter = $Key.Substring(0, 1).ToUpper()
    $vk = [int][char]$letter
    $scan = 0
    try { $scan = [int][System.Windows.Forms.Keys]::Parse($letter) } catch { }
    $sent = [AxHelper.Win]::HoldKey($vk, $scan, $HoldMs)
    Write-Output "HELD key=$letter vk=$vk scan=$scan ms=$HoldMs sent=$sent t=$($sw.ElapsedMilliseconds)ms"
    Start-Sleep -Milliseconds 400
  }
  'tap' {
    $vk = 0
    $scan = 0
    switch ($Key) {
      'Space' { $vk = 32; $scan = 57 }
      'W' { $vk = 87; $scan = 17 }
      'A' { $vk = 65; $scan = 30 }
      'S' { $vk = 83; $scan = 31 }
      'D' { $vk = 68; $scan = 32 }
      default { $vk = [int][char]$Key.ToUpper()[0]; $scan = 0 }
    }
    [AxHelper.Win]::KeyDown($vk, $scan) | Out-Null
    Start-Sleep -Milliseconds 120
    [AxHelper.Win]::KeyUp($vk, $scan) | Out-Null
    Write-Output "TAPPED=$Key vk=$vk scan=$scan"
  }
  'click' {
    if ($X -ge 0) { $cx = $X }
    if ($Y -ge 0) { $cy = $Y }
    [AxHelper.Win]::Click($cx, $cy)
    Write-Output "CLICKED=$cx,$cy"
    Start-Sleep -Milliseconds 500
  }
}

$bytes = [AxHelper.Win]::CaptureScreen($Shot)
Write-Output "SHOT=$Shot BYTES=$bytes t=$($sw.ElapsedMilliseconds)ms"
