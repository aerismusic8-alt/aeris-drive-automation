# Send keyboard and mouse input to a window on PC1.
#
# pyautogui, which the remote tools use, can tap a key but not hold one down, and
# walking in a game needs a key held. SendInput with scan codes is what a game
# actually reads, so that is what this uses.
#
# The window is focused first and given a moment: Roblox only takes keyboard
# input once it is the foreground window.
#
# A screenshot is taken before and after, so a caller can tell whether the input
# did anything rather than assuming it landed.
param(
  [string]$Title = 'Roblox',
  [int]$Handle = 0,
  [string]$Key = '',
  [int]$HoldMs = 1500,
  [int]$ClickX = -1,
  [int]$ClickY = -1,
  [string]$Before = "$env:TEMP\ax-in-before.png",
  [string]$After = "$env:TEMP\ax-in-after.png",
  [switch]$NoShot
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class IN {
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }

  [DllImport("user32.dll", SetLastError=true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint data, IntPtr extra);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);

  public static uint Key(ushort vk, ushort scan, bool up) {
    INPUT[] a = new INPUT[1];
    a[0].type = 1; // INPUT_KEYBOARD
    a[0].u.ki.wVk = vk;
    a[0].u.ki.wScan = scan;
    // KEYEVENTF_SCANCODE makes the game see a physical key; KEYEVENTF_KEYUP releases.
    a[0].u.ki.dwFlags = (up ? 2u : 0u) | 8u;
    return SendInput(1, a, Marshal.SizeOf(typeof(INPUT)));
  }
}
"@

function Text-Of([IntPtr]$h) {
  $sb = New-Object System.Text.StringBuilder 256
  [IN]::GetWindowText($h, $sb, 256) | Out-Null
  return $sb.ToString()
}

function Find-Handle([string]$name) {
  $best = 0; $bestScore = 0
  foreach ($p in Get-Process) {
    $h = $p.MainWindowHandle
    if ($h -eq 0) { continue }
    $t = $p.MainWindowTitle
    if (-not $t) { continue }
    if ($t -eq $name) { return [int]$h }
    if ($t -like "*$name*") { $s = 1000 - $t.Length; if ($s -gt $bestScore) { $bestScore = $s; $best = [int]$h } }
  }
  return $best
}

function Save-Shot([string]$path) {
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

$h = if ($Handle -gt 0) { $Handle } else { Find-Handle $Title }
if ($h -eq 0) { Write-Output "NO_WINDOW title='$Title'"; exit 1 }
$target = [IntPtr]$h
Write-Output ("TARGET=$h title='" + (Text-Of $target) + "'")

if ([IN]::IsIconic($target)) { [IN]::ShowWindow($target, 9) | Out-Null; Start-Sleep -Milliseconds 400 }
$fg = [IN]::GetForegroundWindow()
$fgT = [IN]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
$tT  = [IN]::GetWindowThreadProcessId($target, [IntPtr]::Zero)
$me  = [IN]::GetCurrentThreadId()
[IN]::AttachThreadInput($me, $fgT, $true) | Out-Null
[IN]::AttachThreadInput($me, $tT, $true) | Out-Null
[IN]::BringWindowToTop($target) | Out-Null
[IN]::SetForegroundWindow($target) | Out-Null
[IN]::AttachThreadInput($me, $fgT, $false) | Out-Null
[IN]::AttachThreadInput($me, $tT, $false) | Out-Null
Start-Sleep -Milliseconds 800
Write-Output ("FOREGROUND_IS_TARGET=" + ([IN]::GetForegroundWindow() -eq $target))

if (-not $NoShot) { Save-Shot $Before; Write-Output ("BEFORE=$Before BYTES=" + (Get-Item $Before).Length) }

if ($ClickX -ge 0 -and $ClickY -ge 0) {
  # A click also tells the game the mouse is over it, which some titles want
  # before they accept movement keys.
  [IN]::SetCursorPos($ClickX, $ClickY) | Out-Null
  Start-Sleep -Milliseconds 150
  [IN]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)   # LEFTDOWN
  Start-Sleep -Milliseconds 60
  [IN]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)   # LEFTUP
  Write-Output "CLICKED=$ClickX,$ClickY"
  Start-Sleep -Milliseconds 400
}

if ($Key) {
  $vk = [int][char]([string]$Key).ToUpper()[0]
  # Scan code comes from the keyboard layout, which keeps the game happy.
  $scan = [byte]([System.Windows.Forms.Keys]::$($Key.ToUpper())).value__ 2>$null
  if (-not $scan) { $scan = 0 }
  $down = [IN]::Key([ushort]$vk, [ushort]$scan, $false)
  Write-Output "KEYDOWN key=$Key vk=$vk sent=$down"
  Start-Sleep -Milliseconds $HoldMs
  $up = [IN]::Key([ushort]$vk, [ushort]$scan, $true)
  Write-Output "KEYUP key=$Key sent=$up held=${HoldMs}ms"
  Start-Sleep -Milliseconds 500
}

if (-not $NoShot) { Save-Shot $After; Write-Output ("AFTER=$After BYTES=" + (Get-Item $After).Length) }
