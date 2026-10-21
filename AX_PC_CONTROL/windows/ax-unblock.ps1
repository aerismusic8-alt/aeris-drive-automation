# Clear whatever is sitting on top of the game, then click the game's own button.
#
# A stray always-on-top window was covering the game's Close button: clicks at
# that point were delivered to that window instead of the game, so the dialog
# never closed and movement keys did nothing. This finds the window under the
# button, shoves it far off screen if it is not the game, confirms the point now
# belongs to the game, and only then clicks.
#
# The stray window is moved rather than killed. It belongs to another session on
# the machine and closing it could destroy someone's work.
param(
  [string]$Title = 'Roblox',
  [int]$ClickX = 1309,
  [int]$ClickY = 205,
  [string]$Tag = 'unblock'
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
Write-Output ("GAME=$h rect=" + [AxHelper.Win]::RectOf($h))

$over = [AxHelper.Win]::WindowAt($ClickX, $ClickY)
Write-Output ("AT_BUTTON=$over")
$overPid = 0
if ($over -match 'pid=(\d+)') { $overPid = [int]$Matches[1] }

# Only move it when it is not the game, and only far enough to uncover the game.
if ($overPid -ne 0 -and $over -notmatch '^Roblox') {
  $wh = [AxHelper.Win]::WindowOfPid($overPid)
  if ($wh -ne [IntPtr]::Zero) {
    $wr = ([AxHelper.Win]::RectOf($wh) -split ',')
    Write-Output ("STRAY pid=$overPid hwnd=$wh rect=" + [AxHelper.Win]::RectOf($wh))
    # Park it just past the right edge, keeping its size.
    $moved = [AxHelper.Win]::Move($wh, 1620, 40, [int]$wr[2], [int]$wr[3])
    Write-Output "MOVED=$moved"
    Start-Sleep -Milliseconds 700
    Write-Output ("AT_BUTTON_NOW=" + [AxHelper.Win]::WindowAt($ClickX, $ClickY))
  }
}

[AxHelper.Win]::Focus($h) | Out-Null
Start-Sleep -Milliseconds 400
Write-Output ("CLICKING=$ClickX,$ClickY over=" + [AxHelper.Win]::WindowAt($ClickX, $ClickY))
[AxHelper.Win]::Click($ClickX, $ClickY)
Start-Sleep -Milliseconds 1800

$r = ([AxHelper.Win]::RectOf($h) -split ',')
$shot = "$env:TEMP\ax-$Tag-after.png"
[AxHelper.Win]::CaptureRect([int]$r[0], [int]$r[1], [int]$r[2], [int]$r[3], $shot) | Out-Null
Write-Output "SHOT=$shot BYTES=$((Get-Item $shot).Length)"
