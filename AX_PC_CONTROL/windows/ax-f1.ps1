# Open the Roblox client settings and read them.
#
# The world renders nearly black on this machine because the GPU cannot supply
# several of the engine's shaders ("shader DefaultUnifiedFlatTransparentVS... is
# not available" repeats in the client log). Roblox picks a simpler rendering
# path at a lower graphics quality, so the settings panel is opened and read to
# find the quality control.
#
# The panel is drawn by the client, so it is read with OCR. Its text is English,
# which is the one language the recogniser here handles, unlike the game's own
# Thai interface.
param(
  [string]$Title = 'Roblox',
  [int]$PanelX = 380,
  [int]$PanelY = 60,
  [int]$PanelW = 840,
  [int]$PanelH = 760,
  [int]$Scale = 2
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

function Ocr([string]$path, [int]$ox, [int]$oy, [int]$sc) {
  $src = [System.Drawing.Image]::FromFile($path)
  $big = New-Object System.Drawing.Bitmap(($src.Width * $sc), ($src.Height * $sc))
  $g = [System.Drawing.Graphics]::FromImage($big)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($src, 0, 0, $big.Width, $big.Height)
  $g.Dispose(); $src.Dispose()
  $bp = [IO.Path]::ChangeExtension($path, '.big.png')
  $big.Save($bp, [System.Drawing.Imaging.ImageFormat]::Png); $big.Dispose()

  $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($bp)) ([Windows.Storage.StorageFile])
  $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bmp = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
  $res = Await ($engine.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])
  foreach ($line in $res.Lines) {
    $minx = 1e9; $miny = 1e9; $maxx = -1e9; $maxy = -1e9
    foreach ($wd in $line.Words) {
      $b = $wd.BoundingRect
      if ($b.X -lt $minx) { $minx = $b.X }
      if ($b.Y -lt $miny) { $miny = $b.Y }
      if (($b.X + $b.Width) -gt $maxx) { $maxx = $b.X + $b.Width }
      if (($b.Y + $b.Height) -gt $maxy) { $maxy = $b.Y + $b.Height }
    }
    $cx = [int]($ox + ($minx + $maxx) / 2 / $sc); $cy = [int]($oy + ($miny + $maxy) / 2 / $sc)
    Write-Output ("  T|" + $cx + "," + $cy + "|" + $line.Text)
  }
}

$h = [AxHelper.Win]::FindWindow($Title)
if ($h -eq [IntPtr]::Zero) { Write-Output "NO_WINDOW '$Title'"; exit 1 }
[AxHelper.Win]::Maximize($h)
Start-Sleep -Milliseconds 400
[AxHelper.Win]::Focus($h) | Out-Null
Start-Sleep -Milliseconds 700
$r = ([AxHelper.Win]::RectOf($h) -split ',')
$rx = [int]$r[0]; $ry = [int]$r[1]; $rw = [int]$r[2]; $rh = [int]$r[3]

$before = "$env:TEMP\ax-f1-before.png"
[AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $before) | Out-Null
Write-Output "BEFORE bytes=$((Get-Item $before).Length)"

# F1 opens the client settings overlay.
[AxHelper.Win]::KeyDown(112, 59) | Out-Null
Start-Sleep -Milliseconds 90
[AxHelper.Win]::KeyUp(112, 59) | Out-Null
Start-Sleep -Milliseconds 2000

$after = "$env:TEMP\ax-f1-after.png"
[AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $after) | Out-Null
Write-Output "AFTER bytes=$((Get-Item $after).Length)"

foreach ($tag in @('before', 'after')) {
  Write-Output "--- OCR $tag ---"
  Ocr "$env:TEMP\ax-f1-$tag.png" $PanelX $PanelY $Scale
}
