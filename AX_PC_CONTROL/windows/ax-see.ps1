# Read the text on screen and say where it is, in screen coordinates.
#
# Knowing the words is not enough to operate a game; the agent needs the position
# of a button to click it. Windows OCR returns a bounding box for every word, and
# this unions those into one box per line.
#
# The crop is scaled up before OCR. The game's UI text is small, and the engine
# misses it at native size while reading it reliably at 2x. Coordinates are
# divided back down so they still refer to real screen positions.
#
# Capture and focus come from the prebuilt helper DLL, which keeps this inside
# the 30 second limit on a remote Shell call.
param(
  [string]$Title = 'Roblox',
  [int]$Scale = 2,
  [string]$Shot = "$env:TEMP\ax-see.png",
  [string]$OutFile = '',
  [switch]$NoFocus
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'

$lines = New-Object System.Collections.Generic.List[string]
function Emit([string]$s) { Write-Output $s; if ($OutFile) { $lines.Add($s) | Out-Null } }

$h = [AxHelper.Win]::FindWindow($Title)
if ($h -eq [IntPtr]::Zero) { Emit "NO_WINDOW '$Title'"; exit 1 }
if (-not $NoFocus) {
  [AxHelper.Win]::Maximize($h)
  Start-Sleep -Milliseconds 300
  [AxHelper.Win]::Focus($h) | Out-Null
  Start-Sleep -Milliseconds 400
}
$rect = ([AxHelper.Win]::RectOf($h) -split ',')
$rx = [int]$rect[0]; $ry = [int]$rect[1]; $rw = [int]$rect[2]; $rh = [int]$rect[3]
Emit "WINDOW=$rx,$ry,$rw,$rh title='$([AxHelper.Win]::TitleOf($h))' fg=$([AxHelper.Win]::Foreground() -eq $h)"

$bytes = [AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $Shot)
Emit "CROP=$Shot BYTES=$bytes"

# Scale up for the recogniser, then work in scaled pixels.
$src = [System.Drawing.Image]::FromFile($Shot)
$big = New-Object System.Drawing.Bitmap(($rw * $Scale), ($rh * $Scale))
$g = [System.Drawing.Graphics]::FromImage($big)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($src, 0, 0, $big.Width, $big.Height)
$g.Dispose(); $src.Dispose()
$bigPath = [IO.Path]::ChangeExtension($Shot, '.big.png')
$big.Save($bigPath, [System.Drawing.Imaging.ImageFormat]::Png)
$big.Dispose()

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
  Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($t, $rt) { $m = $asTaskGeneric.MakeGenericMethod($rt); $nt = $m.Invoke($null, @($t)); $nt.Wait(-1) | Out-Null; $nt.Result }

[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($bigPath)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])

Emit ("LINES=" + $result.Lines.Count)
foreach ($line in $result.Lines) {
  $minx = 1e9; $miny = 1e9; $maxx = -1e9; $maxy = -1e9
  foreach ($wd in $line.Words) {
    $r = $wd.BoundingRect
    if ($r.X -lt $minx) { $minx = $r.X }
    if ($r.Y -lt $miny) { $miny = $r.Y }
    if (($r.X + $r.Width) -gt $maxx) { $maxx = $r.X + $r.Width }
    if (($r.Y + $r.Height) -gt $maxy) { $maxy = $r.Y + $r.Height }
  }
  $sx = [int]($rx + ($minx / $Scale)); $sy = [int]($ry + ($miny / $Scale))
  $sw2 = [int](($maxx - $minx) / $Scale); $sh2 = [int](($maxy - $miny) / $Scale)
  $cx = $sx + [int]($sw2 / 2); $cy = $sy + [int]($sh2 / 2)
  Emit ("BOX|$sx,$sy,$sw2,$sh2|CENTER=$cx,$cy|" + $line.Text)
}

if ($OutFile) { $lines | Out-File -FilePath $OutFile -Encoding utf8 }
