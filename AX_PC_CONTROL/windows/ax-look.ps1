# Look at one window on PC1: focus it, capture it, and read its text.
#
# Everything happens in one process. Split into separate calls the focus gets
# taken back before the capture runs, and the picture shows whatever ended up on
# top instead of the window asked for.
#
# The crop is saved so the caller can fetch the exact image that was read, and
# cropping matters: OCR on the full 1600x900 desktop drops the small UI text,
# while a crop to the window keeps it.
#
# The rectangle is passed as four plain numbers rather than one comma string,
# because a comma inside an argument becomes an array in PowerShell and the
# script then gets four arguments instead of one.
param(
  [string]$Title = '',
  [int]$Handle = 0,
  [int]$X = -1,
  [int]$Y = -1,
  [int]$W = 0,
  [int]$H = 0,
  [string]$Shot = "$env:TEMP\ax-look.png",
  [switch]$NoFocus,
  [switch]$Maximize
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class LW {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

function Text-Of([IntPtr]$h) {
  $sb = New-Object System.Text.StringBuilder 512
  [LW]::GetWindowText($h, $sb, 512) | Out-Null
  return $sb.ToString()
}

# Exact title wins. Otherwise the shortest title that contains the name, so
# asking for "Roblox" picks the player window and not a browser tab about Roblox.
function Find-Handle([string]$name) {
  $best = 0; $bestScore = 0
  foreach ($p in Get-Process) {
    $h = $p.MainWindowHandle
    if ($h -eq 0) { continue }
    $t = $p.MainWindowTitle
    if (-not $t) { continue }
    if ($t -eq $name) { return [int]$h }
    if ($t -like "*$name*") {
      $score = 1000 - $t.Length
      if ($score -gt $bestScore) { $bestScore = $score; $best = [int]$h }
    }
  }
  return $best
}

$h = if ($Handle -gt 0) { $Handle } else { Find-Handle $Title }
if ($h -eq 0) { Write-Output "NO_WINDOW title='$Title'"; exit 1 }
$target = [IntPtr]$h
Write-Output ("TARGET handle=$h title='" + (Text-Of $target) + "'")

if (-not $NoFocus) {
  if ([LW]::IsIconic($target)) { [LW]::ShowWindow($target, 9) | Out-Null; Start-Sleep -Milliseconds 400 }
  if ($Maximize) { [LW]::ShowWindow($target, 3) | Out-Null; Start-Sleep -Milliseconds 600 }  # SW_MAXIMIZE
  $fg = [LW]::GetForegroundWindow()
  $fgT = [LW]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
  $tT  = [LW]::GetWindowThreadProcessId($target, [IntPtr]::Zero)
  $me  = [LW]::GetCurrentThreadId()
  [LW]::AttachThreadInput($me, $fgT, $true) | Out-Null
  [LW]::AttachThreadInput($me, $tT, $true) | Out-Null
  [LW]::BringWindowToTop($target) | Out-Null
  [LW]::SetForegroundWindow($target) | Out-Null
  [LW]::AttachThreadInput($me, $fgT, $false) | Out-Null
  [LW]::AttachThreadInput($me, $tT, $false) | Out-Null
  Start-Sleep -Seconds 2
  $now = [LW]::GetForegroundWindow()
  Write-Output "FOCUSED=$($now -eq $target) foreground=$(Text-Of $now)"
}

if ($W -le 0 -or $H -le 0) {
  $r = New-Object LW+RECT
  [LW]::GetWindowRect($target, [ref]$r) | Out-Null
  $X = $r.Left; $Y = $r.Top; $W = $r.Right - $r.Left; $H = $r.Bottom - $r.Top
  Write-Output "RECT_FROM_WINDOW=$X,$Y,$W,$H"
} else {
  Write-Output "RECT_GIVEN=$X,$Y,$W,$H"
}

# Clamp to the virtual screen so a window that hangs off the edge still crops.
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$cx = [Math]::Max($X, $b.Left)
$cy = [Math]::Max($Y, $b.Top)
$cw = [Math]::Min($X + $W, $b.Right) - $cx
$ch = [Math]::Min($Y + $H, $b.Bottom) - $cy
if ($cw -le 0 -or $ch -le 0) { Write-Output 'RECT_OFFSCREEN'; exit 1 }

$full = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($full)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $full.Size)
$g.Dispose()
$rect = New-Object System.Drawing.Rectangle(($cx - $b.Left), ($cy - $b.Top), $cw, $ch)
$crop = $full.Clone($rect, $full.PixelFormat)
$crop.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png)
$crop.Dispose(); $full.Dispose()
Write-Output ("SHOT=$Shot BYTES=" + (Get-Item $Shot).Length)

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
  Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($t, $rt) { $m = $asTaskGeneric.MakeGenericMethod($rt); $nt = $m.Invoke($null, @($t)); $nt.Wait(-1) | Out-Null; $nt.Result }

[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Shot)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
Write-Output '--- TEXT ---'
foreach ($line in $result.Lines) { Write-Output $line.Text }
Write-Output ("LINES=" + $result.Lines.Count)
