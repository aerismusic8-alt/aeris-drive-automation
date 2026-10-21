# OCR one region of a window at high scale, so small button labels are readable.
#
# ax-see.ps1 reads the whole window at 2x, which is not enough to tell a Save
# button from a Cancel button when the label is a few pixels tall. This crops a
# region and scales it up before recognising, then reports screen coordinates so
# the result can be clicked directly.
param(
  [string]$Title = 'Edge',
  [int]$CX = 470,
  [int]$CY = 650,
  [int]$CW = 950,
  [int]$CH = 190,
  [int]$Scale = 4,
  [string]$Out = 'C:\AX-Runtime\evidence\crop.txt'
)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'

$log = New-Object System.Collections.Generic.List[string]
function Emit([string]$s) { Write-Output $s; $log.Add($s) | Out-Null }

$h = [AxHelper.Win]::FindWindow($Title)
if ($h -eq [IntPtr]::Zero) { Emit 'NO_WINDOW'; exit 1 }
$rect = ([AxHelper.Win]::RectOf($h) -split ',')
$rx = [int]$rect[0]; $ry = [int]$rect[1]

$shot = 'C:\Users\User\AppData\Local\Temp\ax-crop.png'
[AxHelper.Win]::CaptureRect($CX, $CY, $CW, $CH, $shot) | Out-Null
Emit "CROP=$CX,$CY,$CW,$CH BYTES=$([IO.File]::ReadAllBytes($shot).Length)"

$src = [System.Drawing.Image]::FromFile($shot)
$big = New-Object System.Drawing.Bitmap(($CW * $Scale), ($CH * $Scale))
$g = [System.Drawing.Graphics]::FromImage($big)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($src, 0, 0, $big.Width, $big.Height); $g.Dispose(); $src.Dispose()
$bigPath = [IO.Path]::ChangeExtension($shot, '.big.png')
$big.Save($bigPath, [System.Drawing.Imaging.ImageFormat]::Png); $big.Dispose()

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
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
foreach ($line in $result.Lines) {
  $minx = 1e9; $miny = 1e9; $maxx = -1e9; $maxy = -1e9
  foreach ($wd in $line.Words) {
    $r = $wd.BoundingRect
    if ($r.X -lt $minx) { $minx = $r.X }; if ($r.Y -lt $miny) { $miny = $r.Y }
    if (($r.X + $r.Width) -gt $maxx) { $maxx = $r.X + $r.Width }
    if (($r.Y + $r.Height) -gt $maxy) { $maxy = $r.Y + $r.Height }
  }
  $sx = [int]($CX + ($minx / $Scale)); $sy = [int]($CY + ($miny / $Scale))
  $cx = $sx + [int](($maxx - $minx) / $Scale / 2); $cy = $sy + [int](($maxy - $miny) / $Scale / 2)
  Emit ("BOX|$sx,$sy|CENTER=$cx,$cy|" + $line.Text)
}
$log | Out-File -FilePath $Out -Encoding utf8
