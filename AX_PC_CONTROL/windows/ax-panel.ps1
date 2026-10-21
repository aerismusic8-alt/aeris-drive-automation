# Identify what is covering the middle of the game.
#
# The same panel text is read every time, and a click on the Close button lands
# on a process that is not Roblox, so something is layered over the game. This
# lists Roblox's child windows, names the process that owns the point, and saves
# a close crop of the panel so it can be examined at size.
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'

Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class CH {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

  public static List<string> Children(IntPtr parent) {
    var rows = new List<string>();
    EnumChildWindows(parent, delegate(IntPtr h, IntPtr l) {
      RECT r; GetWindowRect(h, out r);
      var t = new StringBuilder(256); GetWindowText(h, t, 256);
      var c = new StringBuilder(256); GetClassName(h, c, 256);
      uint pid; GetWindowThreadProcessId(h, out pid);
      rows.Add(string.Format("{0}|{1},{2},{3}x{4}|vis={5}|pid={6}|class={7}|title={8}",
        h, r.Left, r.Top, r.Right-r.Left, r.Bottom-r.Top, IsWindowVisible(h), pid, c, t.ToString().Trim()));
      return true;
    }, IntPtr.Zero);
    return rows;
  }

  public static List<string> Owners(IntPtr h) {
    var rows = new List<string>();
    IntPtr cur = GetWindow(h, 4);  // GW_OWNER
    while (cur != IntPtr.Zero) {
      var c = new StringBuilder(256); GetClassName(cur, c, 256);
      var t = new StringBuilder(256); GetWindowText(cur, t, 256);
      uint pid; GetWindowThreadProcessId(cur, out pid);
      rows.Add("owner " + cur + " pid=" + pid + " class=" + c + " title=" + t);
      cur = GetWindow(cur, 4);
    }
    return rows;
  }
}
"@

$roblox = [AxHelper.Win]::FindWindow('Roblox')
Write-Output "ROBLOX=$roblox rect=$([AxHelper.Win]::RectOf($roblox))"

Write-Output '--- ROBLOX CHILD WINDOWS ---'
foreach ($row in [CH]::Children($roblox)) { Write-Output $row }

Write-Output '--- OWNED WINDOWS ---'
foreach ($row in [CH]::Owners($roblox)) { Write-Output $row }

foreach ($id in @(7796, 15520)) {
  $p = Get-Process -Id $id -ErrorAction SilentlyContinue
  if ($p) {
    Write-Output ("PROC $id name=" + $p.ProcessName + " mainHwnd=" + $p.MainWindowHandle + " title='" + $p.MainWindowTitle + "'")
    if ($p.MainWindowHandle -ne 0) {
      Write-Output ("  rect=" + [AxHelper.Win]::RectOf($p.MainWindowHandle))
    }
  } else {
    Write-Output "PROC $id not running"
  }
}

# Crop the panel region and save it enlarged, so the text and any button are
# large enough to read without guessing coordinates.
$crop = "$env:TEMP\ax-panel.png"
$b = [AxHelper.Win]::CaptureRect(620, 290, 420, 300, $crop)
Write-Output "PANEL_CROP=$crop BYTES=$b"
$src = [System.Drawing.Image]::FromFile($crop)
$big = New-Object System.Drawing.Bitmap(($src.Width * 3), ($src.Height * 3))
$g = [System.Drawing.Graphics]::FromImage($big)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.DrawImage($src, 0, 0, $big.Width, $big.Height)
$g.Dispose(); $src.Dispose()
$big.Save("$env:TEMP\ax-panel-big.png", [System.Drawing.Imaging.ImageFormat]::Png)
$big.Dispose()
Write-Output ("PANEL_BIG=$env:TEMP\ax-panel-big.png BYTES=" + (Get-Item "$env:TEMP\ax-panel-big.png").Length)
