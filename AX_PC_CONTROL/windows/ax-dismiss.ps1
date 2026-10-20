# Dismiss whatever dialog is covering the game, then look again.
#
# The game screen was completely static between captures, and OCR showed a panel
# with a Close button in the middle of the window. A modal panel blocks input
# from reaching the world, so a movement key does nothing until it is closed.
#
# Everything runs in one process: focus, look, click, look. Doing the click in a
# separate call loses the focus in between.
param(
  [string]$Title = 'Roblox',
  [int]$ClickX = 1309,
  [int]$ClickY = 205,
  [string]$Shot1 = "$env:TEMP\ax-before-dismiss.png",
  [string]$Shot2 = "$env:TEMP\ax-after-dismiss.png"
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
  Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($t, $rt) { $m = $asTaskGeneric.MakeGenericMethod($rt); $nt = $m.Invoke($null, @($t)); $nt.Wait(-1) | Out-Null; $nt.Result }
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

function Ocr-Lines([string]$path) {
  $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
  $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bmp = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
  $res = Await ($engine.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])
  $out = @()
  foreach ($l in $res.Lines) { $out += $l.Text }
  return $out
}

# Capture and upscale so the small UI text is readable.
function Shoot-Scaled([string]$path, [int]$rx, [int]$ry, [int]$rw, [int]$rh) {
  [AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $path) | Out-Null
  $src = [System.Drawing.Image]::FromFile($path)
  $big = New-Object System.Drawing.Bitmap(($rw * 2), ($rh * 2))
  $g = [System.Drawing.Graphics]::FromImage($big)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($src, 0, 0, $big.Width, $big.Height)
  $g.Dispose(); $src.Dispose()
  $bigPath = [IO.Path]::ChangeExtension($path, '.big.png')
  $big.Save($bigPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $big.Dispose()
  return $bigPath
}

$h = [AxHelper.Win]::FindWindow($Title)
if ($h -eq [IntPtr]::Zero) { Write-Output "NO_WINDOW '$Title'"; exit 1 }
[AxHelper.Win]::Maximize($h)
Start-Sleep -Milliseconds 400
[AxHelper.Win]::Focus($h) | Out-Null
Start-Sleep -Milliseconds 600
$rect = ([AxHelper.Win]::RectOf($h) -split ',')
$rx = [int]$rect[0]; $ry = [int]$rect[1]; $rw = [int]$rect[2]; $rh = [int]$rect[3]
Write-Output "WINDOW=$rx,$ry,$rw,$rh fg=$([AxHelper.Win]::Foreground() -eq $h)"

Write-Output '--- BEFORE TEXT ---'
foreach ($l in (Ocr-Lines (Shoot-Scaled $Shot1 $rx $ry $rw $rh))) { Write-Output $l }

Write-Output "CLICKING=$ClickX,$ClickY target=$([AxHelper.Win]::WindowAt($ClickX,$ClickY))"
[AxHelper.Win]::Click($ClickX, $ClickY)
Start-Sleep -Milliseconds 1500

Write-Output '--- AFTER TEXT ---'
foreach ($l in (Ocr-Lines (Shoot-Scaled $Shot2 $rx $ry $rw $rh))) { Write-Output $l }
