$ErrorActionPreference='Stop'
if($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB'){throw "PC1_IDENTITY_MISMATCH:$env:COMPUTERNAME"}
$ev='C:\AX-Runtime\evidence\interactive-desktop';New-Item -ItemType Directory -Path $ev -Force|Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text;
public static class AXDesktop {
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd,out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd,StringBuilder text,int count);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd,StringBuilder text,int count);
}
public sealed class AXForegroundEvent { public long AtMs; public IntPtr Hwnd; public uint Pid; }
public sealed class AXForegroundHook {
 private const uint EVENT_SYSTEM_FOREGROUND=3, WINEVENT_OUTOFCONTEXT=0, WINEVENT_SKIPOWNPROCESS=2;
 private delegate void WinEventDelegate(IntPtr h,uint e,IntPtr hwnd,int idObject,int idChild,uint tid,uint ms);
 private readonly WinEventDelegate _delegate;
 private IntPtr _hook=IntPtr.Zero;
 private readonly ConcurrentQueue<AXForegroundEvent> _events=new ConcurrentQueue<AXForegroundEvent>();
 [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SetWinEventHook(uint min,uint max,IntPtr mod,WinEventDelegate proc,uint pid,uint tid,uint flags);
 [DllImport("user32.dll",SetLastError=true)] static extern bool UnhookWinEvent(IntPtr hook);
 [DllImport("user32.dll")] static extern bool PeekMessage(out MSG msg,IntPtr hwnd,uint min,uint max,uint remove);
 [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG msg);
 [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG msg);
 [StructLayout(LayoutKind.Sequential)] struct POINT{public int x;public int y;}
 [StructLayout(LayoutKind.Sequential)] struct MSG{public IntPtr hwnd;public uint message;public UIntPtr wParam;public IntPtr lParam;public uint time;public POINT pt;}
 public AXForegroundHook(){_delegate=new WinEventDelegate(OnEvent);}
 void OnEvent(IntPtr h,uint e,IntPtr hwnd,int idObject,int idChild,uint tid,uint ms){
  if(e!=EVENT_SYSTEM_FOREGROUND)return;
  uint pid=0;if(hwnd!=IntPtr.Zero)AXDesktop.GetWindowThreadProcessId(hwnd,out pid);
  _events.Enqueue(new AXForegroundEvent{AtMs=DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),Hwnd=hwnd,Pid=pid});
 }
 public void Start(){_hook=SetWinEventHook(EVENT_SYSTEM_FOREGROUND,EVENT_SYSTEM_FOREGROUND,IntPtr.Zero,_delegate,0,0,WINEVENT_OUTOFCONTEXT|WINEVENT_SKIPOWNPROCESS);if(_hook==IntPtr.Zero)throw new InvalidOperationException("SETWINEVENTHOOK_FAILED");}
 public AXForegroundEvent[] Drain(){var a=new System.Collections.Generic.List<AXForegroundEvent>();AXForegroundEvent x;while(_events.TryDequeue(out x))a.Add(x);return a.ToArray();}
 public void Pump(int ms){var until=Environment.TickCount+ms;while(Environment.TickCount<until){MSG m;while(PeekMessage(out m,IntPtr.Zero,0,0,1)){TranslateMessage(ref m);DispatchMessage(ref m);}System.Threading.Thread.Sleep(10);}}
 public void Stop(){if(_hook!=IntPtr.Zero){UnhookWinEvent(_hook);_hook=IntPtr.Zero;}}
}
'@
$hook=New-Object AXForegroundHook;$hook.Start()
$rows=New-Object System.Collections.Generic.List[object]
$deadline=(Get-Date).AddSeconds(90);$lastPid=0;$lastCaptureMs=0;$n=0;$eventCount=0
try{
 while((Get-Date) -lt $deadline){
  $hook.Pump(100);$events=@($hook.Drain());$eventCount+=$events.Count
  $hwnd=[AXDesktop]::GetForegroundWindow();[uint32]$pid=0;[void][AXDesktop]::GetWindowThreadProcessId($hwnd,[ref]$pid)
  $shouldCapture=($events.Count -gt 0 -or $pid -ne $lastPid);$nowMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  if($shouldCapture -and (($nowMs-$lastCaptureMs) -ge 50)){
   $screen=[System.Windows.Forms.Screen]::PrimaryScreen;$bmp=New-Object System.Drawing.Bitmap($screen.Bounds.Width,$screen.Bounds.Height);$g=[System.Drawing.Graphics]::FromImage($bmp)
   $g.CopyFromScreen($screen.Bounds.Location,[System.Drawing.Point]::Empty,$screen.Bounds.Size);$n++
   $stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ');$img=Join-Path $ev ("desktop-$stamp.png")
   $bmp.Save($img,[System.Drawing.Imaging.ImageFormat]::Png);$g.Dispose();$bmp.Dispose()
   $title=New-Object System.Text.StringBuilder 512;$class=New-Object System.Text.StringBuilder 256
   [void][AXDesktop]::GetWindowText($hwnd,$title,$title.Capacity);[void][AXDesktop]::GetClassName($hwnd,$class,$class.Capacity)
   $p=if($pid){Get-CimInstance Win32_Process -Filter "ProcessId=$pid" -ErrorAction SilentlyContinue}else{$null}
   $rows.Add([pscustomobject]@{TimestampUtc=(Get-Date).ToUniversalTime().ToString('o');Image=$img;Trigger=if($events.Count -gt 0){'FOREGROUND_EVENT'}else{'PID_CHANGE'};EventCount=$events.Count;ForegroundPid=$pid;ForegroundName=$p.Name;ForegroundTitle=$title.ToString();ForegroundClass=$class.ToString();ForegroundCommandLine=$p.CommandLine})
   $lastCaptureMs=$nowMs;$lastPid=$pid
  }
 }
}finally{$hook.Stop()}
@($rows)|ConvertTo-Json -Depth 8|Set-Content (Join-Path $ev 'interactive-desktop-capture-index.json') -Encoding UTF8
@{status='PASS';nodeId='PC1';captureSeconds=90;captureCount=$n;foregroundEventCount=$eventCount;samplingMode='EVENT_SYSTEM_FOREGROUND_PLUS_100MS_PUMP';completedAt=[DateTime]::UtcNow.ToString('o');evidenceScope='PC1_INTERACTIVE_DESKTOP'}|ConvertTo-Json|Set-Content 'C:\AX-Runtime\evidence\pc1-interactive-desktop-capture-proof.json' -Encoding UTF8
Write-Host "INTERACTIVE_DESKTOP_CAPTURE=PASS";Write-Host "CAPTURE_SECONDS=90";Write-Host "CAPTURE_COUNT=$n";Write-Host "FOREGROUND_EVENT_COUNT=$eventCount"
