# Rename the experience in the Creator Dashboard, all in one process.
#
# Focus, click, clear and type must happen without a gap: each remote tool call
# is its own process, and the browser loses the caret between them, so the typed
# text lands nowhere. Doing the whole sequence here keeps the caret.
param(
  [string]$Title = 'Edge',
  [int]$FieldX = 591,
  [int]$FieldY = 477,
  [string]$NewName = 'AX Garden Legends',
  [string]$Out = 'C:\AX-Runtime\evidence\rename.txt'
)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'
Add-Type @"
using System; using System.Runtime.InteropServices;
public class M {
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
}
"@

$log = New-Object System.Collections.Generic.List[string]
function Emit([string]$s) { Write-Output $s; $log.Add($s) | Out-Null }

$h = [AxHelper.Win]::FindWindow($Title)
if ($h -eq [IntPtr]::Zero) { Emit 'NO_WINDOW'; exit 1 }
[AxHelper.Win]::Maximize($h) | Out-Null
Start-Sleep -Milliseconds 400
[AxHelper.Win]::Focus($h) | Out-Null
Start-Sleep -Milliseconds 700
Emit ("FOCUS=" + [AxHelper.Win]::TitleOf($h))

function ClickAt([int]$x, [int]$y) {
  [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
  Start-Sleep -Milliseconds 200
  [M]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
  [M]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 200
}

ClickAt $FieldX $FieldY
ClickAt $FieldX $FieldY
Start-Sleep -Milliseconds 400

[System.Windows.Forms.SendKeys]::SendWait('^a')
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait('{DEL}')
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait($NewName)
Start-Sleep -Milliseconds 1000
Emit ('TYPED=' + $NewName)

$rect = ([AxHelper.Win]::RectOf($h) -split ',')
$rx = [int]$rect[0]; $ry = [int]$rect[1]; $rw = [int]$rect[2]; $rh = [int]$rect[3]
$shot = 'C:\Users\User\AppData\Local\Temp\ax-rename.png'
[AxHelper.Win]::CaptureRect($rx, $ry, $rw, $rh, $shot) | Out-Null
$src = [System.Drawing.Image]::FromFile($shot)
$big = New-Object System.Drawing.Bitmap(($rw * 2), ($rh * 2))
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
  $minx = 1e9; $miny = 1e9
  foreach ($wd in $line.Words) { $r = $wd.BoundingRect; if ($r.X -lt $minx) { $minx = $r.X }; if ($r.Y -lt $miny) { $miny = $r.Y } }
  $sx = [int]($rx + ($minx / 2)); $sy = [int]($ry + ($miny / 2))
  if ($sy -gt 455 -and $sy -lt 505) { Emit ("FIELD|$sx,$sy|" + $line.Text) }
}
$log | Out-File -FilePath $Out -Encoding utf8
