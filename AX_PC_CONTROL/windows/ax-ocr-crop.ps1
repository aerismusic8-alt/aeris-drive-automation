# Read a rectangle of the screen at high magnification.
#
# The game draws its own interface, so its text is pixels rather than a window
# that can be queried. Scaling a small region up 4x is what makes the words
# legible to the recogniser, and the coordinates are reported in screen space so
# the result can be clicked.
param(
  [int]$X = 600,
  [int]$Y = 280,
  [int]$W = 460,
  [int]$H = 320,
  [int]$Scale = 4,
  [string]$Tag = 'crop'
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'

$shot = "$env:TEMP\ax-ocr-$Tag.png"
[AxHelper.Win]::CaptureRect($X, $Y, $W, $H, $shot) | Out-Null
Write-Output "CROP=$shot BYTES=$((Get-Item $shot).Length) rect=$X,$Y,$W,$H scale=$Scale"

$src = [System.Drawing.Image]::FromFile($shot)
$big = New-Object System.Drawing.Bitmap(($W * $Scale), ($H * $Scale))
$g = [System.Drawing.Graphics]::FromImage($big)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($src, 0, 0, $big.Width, $big.Height)
$g.Dispose(); $src.Dispose()
$bigPath = "$env:TEMP\ax-ocr-$Tag-big.png"
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
$bmp = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$result = Await ($engine.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])

Write-Output ("LINES=" + $result.Lines.Count)
foreach ($line in $result.Lines) {
  $minx = 1e9; $miny = 1e9; $maxx = -1e9; $maxy = -1e9
  foreach ($wd in $line.Words) {
    $r = $wd.BoundingRect
    if ($r.X -lt $minx) { $minx = $r.X }
    if ($r.Y -lt $miny) { $miny = $r.Y }
    if (($r.X + $r.Width) -gt $maxx) { $maxx = $r.X + $r.Width }
    if (($r.Y + $r.Height) -gt $maxy) { $maxy = $r.Y + $r.Height }
  }
  $sx = [int]($X + ($minx / $Scale)); $sy = [int]($Y + ($miny / $Scale))
  $cx = $sx + [int](($maxx - $minx) / $Scale / 2); $cy = $sy + [int](($maxy - $miny) / $Scale / 2)
  Write-Output ("BOX|$sx,$sy|CENTER=$cx,$cy|" + $line.Text)
}
