# Is the Roblox window alive and rendering?
#
# Two captures a few seconds apart with no input in between. A running game
# animates, so the frames differ; identical frames mean the window is frozen or
# is not being redrawn.
#
# Responding and CPU time come from the process: a hung window reports
# Responding=False, and a window that is not rendering accumulates no CPU.
$ErrorActionPreference = 'Continue'
$sw = [Diagnostics.Stopwatch]::StartNew()
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'

$p = Get-Process -Name RobloxPlayerBeta -ErrorAction SilentlyContinue |
     Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Output 'NO_ROBLOX_PROCESS'; exit 1 }

$p.Refresh()
Write-Output ("PROC pid=" + $p.Id + " responding=" + $p.Responding +
  " cpu_s=" + [Math]::Round($p.TotalProcessorTime.TotalSeconds, 2) +
  " mem_mb=" + [Math]::Round($p.WorkingSet64 / 1MB, 0) +
  " threads=" + $p.Threads.Count)

$h = [AxHelper.Win]::FindWindow('Roblox')
Write-Output ("HANDLE=" + $h + " rect=" + [AxHelper.Win]::RectOf($h) +
  " fg_is_target=" + ([AxHelper.Win]::Foreground() -eq $h) +
  " fg='" + [AxHelper.Win]::TitleOf([AxHelper.Win]::Foreground()) + "'")

$r = ([AxHelper.Win]::RectOf($h) -split ',')
$b1 = [AxHelper.Win]::CaptureRect([int]$r[0], [int]$r[1], [int]$r[2], [int]$r[3], "$env:TEMP\ax-probe-a.png")
Start-Sleep -Seconds 3
$p.Refresh()
$b2 = [AxHelper.Win]::CaptureRect([int]$r[0], [int]$r[1], [int]$r[2], [int]$r[3], "$env:TEMP\ax-probe-b.png")
$p.Refresh()
Write-Output ("CAP_A=$b1 CAP_B=$b2 cpu_after=" + [Math]::Round($p.TotalProcessorTime.TotalSeconds, 2) +
  " t=$($sw.ElapsedMilliseconds)ms")

# What is actually under the middle of the Roblox window right now?
$mx = [int]$r[0] + [int]([int]$r[2] / 2)
$my = [int]$r[1] + [int]([int]$r[3] / 2)
Write-Output ("WINDOW_AT_CENTER=" + [AxHelper.Win]::WindowAt($mx, $my))
