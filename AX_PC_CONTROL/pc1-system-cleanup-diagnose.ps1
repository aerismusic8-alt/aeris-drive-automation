$ErrorActionPreference='Continue'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$ev='C:\AX-Runtime\evidence\desktop-capture';New-Item -ItemType Directory -Path $ev -Force|Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DesktopCapture {
 [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
 [DllImport("user32.dll")] public static extern IntPtr GetWindowDC(IntPtr hWnd);
 [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll",SetLastError=true)] public static extern uint GetWindowThreadProcessId(IntPtr hWnd,out uint pid);
}
'@
$rows=@();$deadline=(Get-Date).AddSeconds(60);$n=0
while((Get-Date) -lt $deadline){
 try{
  $screen=[System.Windows.Forms.Screen]::PrimaryScreen
 }catch{
  Add-Type -AssemblyName System.Windows.Forms
  $screen=[System.Windows.Forms.Screen]::PrimaryScreen
 }
 $bmp=New-Object System.Drawing.Bitmap($screen.Bounds.Width,$screen.Bounds.Height)
 $g=[System.Drawing.Graphics]::FromImage($bmp)
 $g.CopyFromScreen($screen.Bounds.Location,[System.Drawing.Point]::Empty,$screen.Bounds.Size)
 $n++;$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
 $img=Join-Path $ev ("desktop-$stamp.png");$bmp.Save($img,[System.Drawing.Imaging.ImageFormat]::Png);$g.Dispose();$bmp.Dispose()
 $fg=[DesktopCapture]::GetForegroundWindow();[uint32]$pid=0;[void][DesktopCapture]::GetWindowThreadProcessId($fg,[ref]$pid)
 $p=if($pid){Get-CimInstance Win32_Process -Filter "ProcessId=$pid" -ErrorAction SilentlyContinue}else{$null}
 $rows += [pscustomobject]@{TimestampUtc=(Get-Date).ToUniversalTime().ToString('o');Image=$img;ForegroundPid=$pid;ForegroundName=$p.Name;ForegroundCommandLine=$p.CommandLine}
 Start-Sleep -Seconds 5
}
$rows|ConvertTo-Json -Depth 6|Set-Content (Join-Path $ev 'desktop-capture-index.json') -Encoding UTF8
Write-Host "DESKTOP_CAPTURE_PASS=1"
Write-Host "CAPTURE_SECONDS=60"
Write-Host "CAPTURE_COUNT=$n"
