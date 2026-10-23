param(
  [string]$ProcessName = 'RobloxPlayerBeta',
  [string]$OutDir = 'C:\AX-Runtime\evidence\capture',
  [int]$WaitSeconds = 4,
  [int]$WaitForWindowSeconds = 40
)

# Photograph one process's window, and nothing else.
#
# The open run captured whatever happened to be in front, which on PC1 is often
# a Chrome tab, so its screenshots proved nothing about the game. This brings the
# named process's own window to the front first and captures the full desktop
# only after that has been confirmed, so the frame is known to contain it.
#
# The foreground handoff needs AttachThreadInput: a background process calling
# SetForegroundWindow alone is refused by Windows, which is why the open run's
# keystroke landed in the wrong window. Attaching to the current foreground
# thread's input queue removes that restriction.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class AXCapture {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder t, int c);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder t, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

  public static string Title(IntPtr h) {
    StringBuilder sb = new StringBuilder(512);
    GetWindowText(h, sb, sb.Capacity);
    return sb.ToString();
  }
  public static string Class(IntPtr h) {
    StringBuilder sb = new StringBuilder(512);
    GetClassName(h, sb, sb.Capacity);
    return sb.ToString();
  }

  // The largest visible top-level window owned by the pid.
  public static IntPtr FindWindow(uint pid) {
    IntPtr best = IntPtr.Zero; long bestArea = 0;
    EnumWindows(delegate(IntPtr h, IntPtr p) {
      uint wpid; GetWindowThreadProcessId(h, out wpid);
      if (wpid != pid || !IsWindowVisible(h)) return true;
      RECT r; if (!GetWindowRect(h, out r)) return true;
      long area = (long)(r.Right - r.Left) * (r.Bottom - r.Top);
      if (area > bestArea) { bestArea = area; best = h; }
      return true;
    }, IntPtr.Zero);
    return best;
  }

  public static void ForceForeground(IntPtr h) {
    ShowWindow(h, 9);   // SW_RESTORE
    ShowWindow(h, 3);   // SW_MAXIMIZE
    IntPtr fg = GetForegroundWindow();
    uint fgPid;
    uint fgThread = GetWindowThreadProcessId(fg, out fgPid);
    uint me = GetCurrentThreadId();
    AttachThreadInput(fgThread, me, true);
    BringWindowToTop(h);
    SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040); // NOSIZE|NOMOVE|SHOWWINDOW
    SetForegroundWindow(h);
    AttachThreadInput(fgThread, me, false);
  }

  public static IntPtr Foreground() { return GetForegroundWindow(); }
}
'@

function Get-Title([IntPtr]$h) {
  if ($h -eq [IntPtr]::Zero) { return '' }
  return [AXCapture]::Title($h)
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# Roblox relaunches itself on join, so the process that is running when this
# starts may not be the one that ends up with the game window. Watch every
# instance of the name for up to WaitForWindowSeconds before giving up.
$hwnd = [IntPtr]::Zero
$proc = $null
$deadline = (Get-Date).AddSeconds($WaitForWindowSeconds)
while ((Get-Date) -lt $deadline) {
  $procs = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
  Write-Host "PROC_COUNT=$($procs.Count)"
  foreach ($p in $procs) {
    $h = [AXCapture]::FindWindow([uint32]$p.Id)
    if ($h -ne [IntPtr]::Zero) { $hwnd = $h; $proc = $p; break }
  }
  if ($hwnd -ne [IntPtr]::Zero) { break }
  Start-Sleep -Seconds 3
}

if (-not $proc) {
  Write-Host "CAPTURE_FAIL=NO_PROCESS:$ProcessName"
  exit 2
}
if ($hwnd -eq [IntPtr]::Zero) {
  Write-Host "CAPTURE_FAIL=NO_WINDOW pid=$($proc.Id)"
  exit 3
}

$before = Get-Title $hwnd
[AXCapture]::ForceForeground($hwnd)
Start-Sleep -Seconds $WaitSeconds

$fg = [AXCapture]::Foreground()
[uint32]$fgPid = 0
[void][AXCapture]::GetWindowThreadProcessId($fg, [ref]$fgPid)
$fgTitle = Get-Title $fg

Write-Host "TARGET_PID=$($proc.Id)"
Write-Host "TARGET_TITLE=$before"
Write-Host "FOREGROUND_TITLE=$fgTitle"
Write-Host "FOREGROUND_PID=$fgPid"
Write-Host "FOREGROUND_IS_TARGET=$($fgPid -eq $proc.Id)"

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
$img = Join-Path $OutDir "$ProcessName-$stamp.png"
$bmp.Save($img, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "CAPTURE_FILE=$img"
Write-Host "CAPTURE_BYTES=$((Get-Item -LiteralPath $img).Length)"
Write-Host "CAPTURE_DONE"
