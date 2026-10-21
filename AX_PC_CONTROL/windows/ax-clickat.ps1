# Click one point in the game window, then report what the screen looks like.
#
# Focus, click, wait and re-read all happen in one process, because splitting them
# loses the foreground window in between and the click then lands elsewhere.
#
# The result is reported as: how dark the frame is (a dialog dims the world), and
# the text still visible in the middle of the window. That is enough to tell
# whether the click dismissed what was covering the game.
param(
  [string]$Title = 'Roblox',
  [Parameter(Mandatory = $true)][int]$ClickX,
  [Parameter(Mandatory = $true)][int]$ClickY,
  [int]$WaitMs = 1800,
  [string]$Tag = 'click'
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

$h = [AxHelper.Win]::FindWindow($Title)
if ($h -eq [IntPtr]::Zero) { Write-Output "NO_WINDOW '$Title'"; exit 1 }
[AxHelper.Win]::Maximize($h)
Start-Sleep -Milliseconds 400
[AxHelper.Win]::Focus($h) | Out-Null
Start-Sleep -Milliseconds 600

$r = ([AxHelper.Win]::RectOf($h) -split ',')
$rx = [int]$r[0]; $ry = [int]$r[1]; $rw = [int]$r[2]; $rh = [int]$r[3]

function Darkness([string]$path) {
  $bmp = [System.Drawing.Bitmap]::FromFile($path)
  $dark = 0; $total = 0
  for ($y = 0; $y -lt $bmp.Height; $y += 12) {
    for ($x = 0; $x -lt $bmp.Width; $x += 12) {
      $c = $bmp.GetPixel($x, $y)
      if (($c.R + $c.G + $c.B) -lt 90) { $dark++ }
      $total++
    }
  }
  $bmp.Dispose()
  return [Math]::Round(100.0 * $dark / $total, 1)
}

# Read the middle of the window, scaled up, and report text with screen position.
function ReadCenter([string]$path) {
  $cx = 600; $cy = 280; $cw = 460; $ch = 320
  [AxHelper.Win]::CaptureRect($cx, $cy, $cw, $ch, $path) | Out-Null
  $src = [System.Drawing.Image]::FromFile($path)
  $big = New-Object System.Drawing.Bitmap(($cw * 3), ($ch * 3))
  $g = [System.Drawing.Graphics]::FromImage($big)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($src, 0, 0, $big.Width, $big.Height)
  $g.Dispose(); $src.Dispose()
  $bp = [IO.Path]::ChangeExtension($path, '.big.png')
  $big.Save($bp, [System.Drawing.Imaging.ImageFormat]::Png)
  $big.Dispose()
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
    $sx = [int]($cx + $minx / 3); $sy = [int]($cy + $miny / 3)
    Write-Output ("  TEXT|" + $sx + "," + $sy + "|" + $line.Text)
  }
}

$before = "$env:TEMP\ax-$Tag-before.png"
[AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $before) | Out-Null
Write-Output ("BEFORE darkness=" + (Darkness $before) + "%")

Write-Output ("CLICK=$ClickX,$ClickY over=" + [AxHelper.Win]::WindowAt($ClickX, $ClickY))
[AxHelper.Win]::Click($ClickX, $ClickY)
Start-Sleep -Milliseconds $WaitMs

$after = "$env:TEMP\ax-$Tag-after.png"
[AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $after) | Out-Null
Write-Output ("AFTER darkness=" + (Darkness $after) + "%")

Write-Output '--- TEXT NOW ---'
ReadCenter "$env:TEMP\ax-$Tag-ocr.png"
