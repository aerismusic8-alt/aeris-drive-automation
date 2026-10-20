// Helper library for driving PC1: window focus, real key holds, mouse, capture.
//
// Compiled once into ax-helper.dll and loaded with Add-Type -Path. Compiling the
// C# on every call costs a minute or more on this machine (csc start-up plus a
// virus scan of the temporary assembly), which does not fit in the 30 second cap
// on a remote Shell call. Loading a finished DLL costs milliseconds.
//
// SendInput is used rather than a simple key tap because a game reads held keys
// to move a character, and it is given scan codes so the game accepts them as
// real keyboard input.
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace AxHelper
{
    public static class Win
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        private struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }

        [StructLayout(LayoutKind.Sequential)]
        private struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr extra; }

        [StructLayout(LayoutKind.Explicit)]
        private struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }

        [StructLayout(LayoutKind.Sequential)]
        private struct INPUT { public uint type; public INPUTUNION u; }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint n, INPUT[] a, int size);

        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr h, int c);
        [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
        [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
        [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint a, uint b, bool f);
        [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr h);
        [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll")] private static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
        [DllImport("user32.dll", CharSet = CharSet.Auto)] private static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(POINT p);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr l);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }
        private delegate bool EnumProc(IntPtr h, IntPtr l);

        public static string TitleOf(IntPtr h)
        {
            var sb = new StringBuilder(512);
            GetWindowText(h, sb, 512);
            return sb.ToString();
        }

        /// <summary>Find a window: exact title first, else shortest title containing name.</summary>
        public static IntPtr FindWindow(string name)
        {
            IntPtr best = IntPtr.Zero;
            int bestScore = 0;
            foreach (Process p in Process.GetProcesses())
            {
                IntPtr h = p.MainWindowHandle;
                if (h == IntPtr.Zero) continue;
                string t;
                try { t = p.MainWindowTitle; } catch { continue; }
                if (string.IsNullOrEmpty(t)) continue;
                if (t == name) return h;
                if (t.IndexOf(name, StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    int score = 1000 - t.Length;
                    if (score > bestScore) { bestScore = score; best = h; }
                }
            }
            return best;
        }

        public static IntPtr Foreground() { return GetForegroundWindow(); }

        public static string RectOf(IntPtr h)
        {
            RECT r;
            if (!GetWindowRect(h, out r)) return "0,0,0,0";
            return string.Format("{0},{1},{2},{3}", r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
        }

        /// <summary>Make the window foreground. A background process is not allowed to do this
        /// on its own, so the input queues of the current and foreground threads are attached
        /// first, which is the documented way around that rule.</summary>
        public static bool Focus(IntPtr h)
        {
            if (IsIconic(h)) { ShowWindow(h, 9); System.Threading.Thread.Sleep(300); }
            IntPtr fg = GetForegroundWindow();
            uint fgT = GetWindowThreadProcessId(fg, IntPtr.Zero);
            uint tT = GetWindowThreadProcessId(h, IntPtr.Zero);
            uint me = GetCurrentThreadId();
            AttachThreadInput(me, fgT, true);
            AttachThreadInput(me, tT, true);
            BringWindowToTop(h);
            SetForegroundWindow(h);
            AttachThreadInput(me, fgT, false);
            AttachThreadInput(me, tT, false);
            return GetForegroundWindow() == h;
        }

        public static void Maximize(IntPtr h) { ShowWindow(h, 3); }

        public static void Click(int x, int y)
        {
            SetCursorPos(x, y);
            System.Threading.Thread.Sleep(120);
            mouse_event(0x0002, 0, 0, 0, IntPtr.Zero);   // left down
            System.Threading.Thread.Sleep(60);
            mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);   // left up
        }

        public static void MoveTo(int x, int y) { SetCursorPos(x, y); }

        /// <summary>Move the pointer relative to where it is. Used to turn the camera.</summary>
        public static void MouseMoveRel(int dx, int dy)
        {
            mouse_event(0x0001, (uint)dx, (uint)dy, 0, IntPtr.Zero);   // MOUSEEVENTF_MOVE
        }

        /// <summary>Press and release one key.</summary>
        public static uint KeyDown(int vk, int scan)
        {
            INPUT[] a = new INPUT[1];
            a[0].type = 1;
            a[0].u.ki.wVk = (ushort)vk;
            a[0].u.ki.wScan = (ushort)scan;
            a[0].u.ki.dwFlags = 8;   // KEYEVENTF_SCANCODE
            return SendInput(1, a, Marshal.SizeOf(typeof(INPUT)));
        }

        public static uint KeyUp(int vk, int scan)
        {
            INPUT[] a = new INPUT[1];
            a[0].type = 1;
            a[0].u.ki.wVk = (ushort)vk;
            a[0].u.ki.wScan = (ushort)scan;
            a[0].u.ki.dwFlags = 8 | 2;   // SCANCODE | KEYUP
            return SendInput(1, a, Marshal.SizeOf(typeof(INPUT)));
        }

        /// <summary>Hold a key for a while. This is what walks a character.</summary>
        public static uint HoldKey(int vk, int scan, int ms)
        {
            uint d = KeyDown(vk, scan);
            System.Threading.Thread.Sleep(ms);
            KeyUp(vk, scan);
            return d;
        }

        /// <summary>Capture the whole virtual screen to a PNG. Returns the byte count.</summary>
        public static long CaptureScreen(string path)
        {
            Rectangle b = SystemInformation.VirtualScreen;
            using (Bitmap bmp = new Bitmap(b.Width, b.Height))
            {
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.CopyFromScreen(b.Left, b.Top, 0, 0, bmp.Size);
                }
                bmp.Save(path, ImageFormat.Png);
            }
            return new System.IO.FileInfo(path).Length;
        }

        /// <summary>Capture one rectangle of the screen to a PNG.</summary>
        public static long CaptureRect(int x, int y, int w, int h, string path)
        {
            Rectangle b = SystemInformation.VirtualScreen;
            using (Bitmap full = new Bitmap(b.Width, b.Height))
            {
                using (Graphics g = Graphics.FromImage(full))
                {
                    g.CopyFromScreen(b.Left, b.Top, 0, 0, full.Size);
                }
                int cx = Math.Max(x, b.Left), cy = Math.Max(y, b.Top);
                int cw = Math.Min(x + w, b.Right) - cx, ch = Math.Min(y + h, b.Bottom) - cy;
                if (cw <= 0 || ch <= 0) return -1;
                using (Bitmap crop = full.Clone(new Rectangle(cx - b.Left, cy - b.Top, cw, ch), full.PixelFormat))
                {
                    crop.Save(path, ImageFormat.Png);
                }
            }
            return new System.IO.FileInfo(path).Length;
        }

        /// <summary>Name of the window under a screen point, or "" if none.</summary>
        public static string WindowAt(int x, int y)
        {
            POINT p; p.X = x; p.Y = y;
            IntPtr h = WindowFromPoint(p);
            if (h == IntPtr.Zero) return "";
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            return TitleOf(h) + " pid=" + pid;
        }

        [DllImport("user32.dll")] private static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);

        /// <summary>Move and resize a window. Used to shove a stray window off the game.</summary>
        public static bool Move(IntPtr h, int x, int y, int w, int ht)
        {
            return MoveWindow(h, x, y, w, ht, true);
        }

        /// <summary>First top-level window belonging to a process, or zero.</summary>
        public static IntPtr WindowOfPid(int pid)
        {
            IntPtr found = IntPtr.Zero;
            EnumWindows(delegate(IntPtr h, IntPtr l)
            {
                uint p;
                GetWindowThreadProcessId(h, out p);
                if ((int)p == pid) { found = h; return false; }
                return true;
            }, IntPtr.Zero);
            return found;
        }
    }
}
