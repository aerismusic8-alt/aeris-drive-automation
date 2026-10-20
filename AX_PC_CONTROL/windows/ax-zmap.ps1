# Map every top-level window: z-order, rectangle, owner process, topmost flag.
#
# The Roblox window reports itself as foreground, yet a click at a point inside
# its rectangle landed on a different process. The likely reason is another
# window marked always-on-top, which paints over the game and keeps receiving
# clicks no matter how often the game is focused. Listing the windows in z-order
# with their extended styles shows whether that is the case and which window it is.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path 'C:\AX-Runtime\evidence\ax-helper.dll'
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class Z {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

  public static List<string> List() {
    var rows = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      RECT r; GetWindowRect(h, out r);
      int w = r.Right - r.Left, ht = r.Bottom - r.Top;
      if (w < 80 || ht < 80) return true;
      var t = new StringBuilder(256); GetWindowText(h, t, 256);
      var c = new StringBuilder(256); GetClassName(h, c, 256);
      uint pid; GetWindowThreadProcessId(h, out pid);
      int ex = GetWindowLong(h, -20);   // GWL_EXSTYLE
      bool topmost = (ex & 0x8) != 0;   // WS_EX_TOPMOST
      bool layered = (ex & 0x80000) != 0;
      rows.Add(string.Format("{0}|{1},{2},{3},{4}|pid={5}|topmost={6}|layered={7}|class={8}|title={9}",
        h, r.Left, r.Top, w, ht, pid, topmost, layered, c, t.ToString().Trim()));
      return true;
    }, IntPtr.Zero);
    return rows;
  }
}
"@

$procs = @{}
foreach ($p in Get-Process) { $procs[$p.Id] = $p.ProcessName }

Write-Output 'Z-ORDER (top first):'
foreach ($row in [Z]::List()) {
  $opid = [int](($row -split 'pid=')[1].Split('|')[0])
  $name = if ($procs.ContainsKey($opid)) { $procs[$opid] } else { '?' }
  Write-Output ("$name $row")
}

# Which window is really under a few points the game claims to own?
foreach ($pt in @(@(800, 426), @(1309, 205), @(400, 600), @(1000, 700))) {
  Write-Output ("AT " + $pt[0] + "," + $pt[1] + " -> " + [AxHelper.Win]::WindowAt($pt[0], $pt[1]))
}
