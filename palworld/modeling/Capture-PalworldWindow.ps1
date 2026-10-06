$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$root='D:\PalworldServer-LAN\BridgeLab\view'
$report=Join-Path $root 'capture-status.json'
$image=Join-Path $root 'palworld-window.png'
try {
  Add-Type -AssemblyName System.Drawing
  Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public class PalWindowView {
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
 [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
 public delegate bool EnumProc(IntPtr hwnd,IntPtr param);
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb,IntPtr p);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h,ref POINT p);
 [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 public static IntPtr Find(uint target) {
   IntPtr found=IntPtr.Zero; long area=0;
   EnumWindows((h,p)=>{uint owner;GetWindowThreadProcessId(h,out owner);RECT r;
     if(owner==target && IsWindowVisible(h) && GetClientRect(h,out r)) {
       long size=(long)(r.Right-r.Left)*(r.Bottom-r.Top);
       if(size>area){area=size;found=h;}
     }return true;},IntPtr.Zero);return found;
 }
 public static uint ForegroundPid() {uint pid;GetWindowThreadProcessId(GetForegroundWindow(),out pid);return pid;}
 public static string Capture(uint pid,string path) {
   SetProcessDPIAware();IntPtr h=Find(pid);
   if(h==IntPtr.Zero) throw new Exception("Game window was not found in this interactive session");
   if(IsIconic(h)) throw new Exception("Game window is minimized; capture does not restore or focus it");
   RECT r;if(!GetClientRect(h,out r))throw new Exception("GetClientRect failed");
   int width=r.Right-r.Left,height=r.Bottom-r.Top;if(width<300||height<200)throw new Exception("Game client area is too small");
   POINT p=new POINT();ClientToScreen(h,ref p);
   string method;
   using(Bitmap b=new Bitmap(width,height,PixelFormat.Format32bppArgb)) {
     using(Graphics g=Graphics.FromImage(b)) {
       if(ForegroundPid()==pid) {g.CopyFromScreen(p.X,p.Y,0,0,new Size(width,height),CopyPixelOperation.SourceCopy);method="foreground_game_client_area";}
       else {IntPtr dc=g.GetHdc();bool ok;try{ok=PrintWindow(h,dc,3);}finally{g.ReleaseHdc(dc);}if(!ok)throw new Exception("PrintWindow failed for background game");method="background_game_PrintWindow";}
     }
     long sum=0;int samples=0,min=255,max=0;
     for(int y=0;y<height;y+=31)for(int x=0;x<width;x+=31){Color c=b.GetPixel(x,y);int v=(c.R+c.G+c.B)/3;sum+=v;samples++;min=Math.Min(min,v);max=Math.Max(max,v);}
     b.Save(path,ImageFormat.Png);
     return String.Format("{{\"method\":\"{0}\",\"width\":{1},\"height\":{2},\"mean_luminance\":{3},\"luminance_range\":{4},\"game_pid\":{5},\"foreground_pid\":{6}}}",method,width,height,sum/samples,max-min,pid,ForegroundPid());
   }
 }
}
'@
  $game=Get-Process -Name 'Palworld-Win64-Shipping' -ErrorAction Stop|Where-Object {$_.SessionId -eq [Diagnostics.Process]::GetCurrentProcess().SessionId}|Select-Object -First 1
  if(!$game){throw 'Game is not running in this interactive session'}
  $result=[PalWindowView]::Capture([uint32]$game.Id,$image)|ConvertFrom-Json
  $result|Add-Member status 'captured'
  $result|Add-Member captured_utc ([DateTime]::UtcNow.ToString('o'))
  $result|Add-Member image_path $image
  $result|ConvertTo-Json -Compress|Set-Content -LiteralPath $report -Encoding UTF8
}catch {
  @{status='failed';error=$_.Exception.Message;session=[Diagnostics.Process]::GetCurrentProcess().SessionId}|ConvertTo-Json -Compress|Set-Content -LiteralPath $report -Encoding UTF8
  exit 1
}
