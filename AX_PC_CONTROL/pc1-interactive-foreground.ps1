$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$ev='C:\AX-Runtime\evidence\interactive-desktop';New-Item -ItemType Directory -Path $ev -Force|Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class AXDesktop {
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll",SetLastError=true)] public static extern uint GetWindowThreadProcessId(IntPtr hWnd,out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd,StringBuilder text,int count);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd,StringBuilder text,int count);
}
'@
$rows=@();$deadline=(Get-Date).AddSeconds(90);$n=0
while((Get-Date) -lt $deadline){
 $screen=[System.Windows.Forms.Screen]::PrimaryScreen
 $bmp=New-Object System.Drawing.Bitmap($screen.Bounds.Width,$screen.Bounds.Height)
 $g=[System.Drawing.Graphics]::FromImage($bmp)
 $g.CopyFromScreen($screen.Bounds.Location,[System.Drawing.Point]::Empty,$screen.Bounds.Size)
 $n++;$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
 $img=Join-Path $ev ("desktop-$stamp.png");$bmp.Save($img,[System.Drawing.Imaging.ImageFormat]::Png);$g.Dispose();$bmp.Dispose()
 $fg=[AXDesktop]::GetForegroundWindow();[uint32]$pid=0;[void][AXDesktop]::GetWindowThreadProcessId($fg,[ref]$pid)
 $title=New-Object System.Text.StringBuilder 512;$class=New-Object System.Text.StringBuilder 256
 [void][AXDesktop]::GetWindowText($fg,$title,$title.Capacity);[void][AXDesktop]::GetClassName($fg,$class,$class.Capacity)
 $p=if($pid){Get-CimInstance Win32_Process -Filter "ProcessId=$pid" -ErrorAction SilentlyContinue}else{$null}
 $rows += [pscustomobject]@{TimestampUtc=(Get-Date).ToUniversalTime().ToString('o');Image=$img;ForegroundPid=$pid;ForegroundName=$p.Name;ForegroundTitle=$title.ToString();ForegroundClass=$class.ToString();ForegroundCommandLine=$p.CommandLine}
 Start-Sleep -Seconds 2
}
$rows|ConvertTo-Json -Depth 6|Set-Content (Join-Path $ev 'interactive-desktop-capture-index.json') -Encoding UTF8
@{status='PASS';nodeId='PC1';captureSeconds=90;captureCount=$n;completedAt=[DateTime]::UtcNow.ToString('o');evidenceScope='PC1_INTERACTIVE_DESKTOP'}|ConvertTo-Json|Set-Content 'C:\AX-Runtime\evidence\pc1-interactive-desktop-capture-proof.json' -Encoding UTF8
Write-Host "INTERACTIVE_DESKTOP_CAPTURE=PASS"
Write-Host "CAPTURE_SECONDS=90"
Write-Host "CAPTURE_COUNT=$n"
