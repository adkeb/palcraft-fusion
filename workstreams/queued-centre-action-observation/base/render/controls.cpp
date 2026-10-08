#include "controls.h"
#include "input_transport.h"
#include "form_requests.h"
#include "mouse_message_compat.h"
#include "host_mouse_warp.h"
#include <windows.h>
#include <windowsx.h>
#include "../launcher/windows_paths.hpp"
#include <atomic>
#include <mutex>
#include <vector>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <cwchar>

namespace {
std::atomic<bool> accepts{false},menu{false},build{false};
std::atomic<bool> actionsSuspended{false};
PalCraftFormRequests formRequests;
void set_build_mode(bool on){palcraft_set_form_mode(build,menu,on);}
std::atomic<ULONGLONG> feedbackAt{0},mouseAfter{0};
std::atomic<long long> mouseX{0},mouseY{0};
std::mutex mouseCompatLock;PalCraftMouseMessageCompat mouseCompat;
int macMouseMode(){
 static const int mode=[](){wchar_t value[32]{};GetEnvironmentVariableW(L"PALCRAFT_MAC_MOUSE_MESSAGES",value,32);
  if(std::wcscmp(value,L"relative-host-warp-v1")==0)return 2;
  return std::wcscmp(value,L"relative-v1")==0?1:0;}();return mode;
}
bool macMouseMessages(){return macMouseMode()!=0;}
const char* mouseOwnerToken(){
 static const std::string token=[](){wchar_t value[40]{};std::string s;
  if(GetEnvironmentVariableW(L"PALCRAFT_MOUSE_OWNER_TOKEN",value,40)!=32)return s;
  for(int i=0;i<32;++i){if(!((value[i]>='0'&&value[i]<='9')||(value[i]>='a'&&value[i]<='f')))return std::string{};s+=static_cast<char>(value[i]);}
  return s;}();return token.c_str();
}
const char* mouseNativeEpoch(){
 static const std::string epoch=[](){FILETIME born{},exit{},kernel{},user{};
  if(!GetProcessTimes(GetCurrentProcess(),&born,&exit,&kernel,&user))return std::string{};
  ULARGE_INTEGER stamp{};stamp.LowPart=born.dwLowDateTime;stamp.HighPart=born.dwHighDateTime;
  char s[64];std::snprintf(s,sizeof s,"%lu:%llu",static_cast<unsigned long>(GetCurrentProcessId()),static_cast<unsigned long long>(stamp.QuadPart));return std::string(s);}();
 return epoch.c_str();
}
void recenterMessageMouse(HWND h,const RECT&r){
 if(macMouseMode()==2)return; // The existing Mac HUD is the one physical warp producer.
 PalCraftMouseMessageCompat::Warp warp;
 {std::lock_guard<std::mutex> lock(mouseCompatLock);warp=mouseCompat.recenter(reinterpret_cast<uintptr_t>(h),r.right-r.left,r.bottom-r.top,GetTickCount64());}
 if(!warp.requested)return;
 POINT p{warp.x,warp.y};
 // A tracked warp on our current foreground client permits unlimited normal
 // FPS turns. The ensuing center message only acknowledges the new baseline.
 if(!accepts.load()||!build.load()||menu.load()||actionsSuspended.load()||GetForegroundWindow()!=h
    ||!ClientToScreen(h,&p)||!SetCursorPos(p.x,p.y)){
  std::lock_guard<std::mutex> lock(mouseCompatLock);mouseCompat.cancel_warp(reinterpret_cast<uintptr_t>(h));
 }
}
HWND window=nullptr;WNDPROC original=nullptr;
std::mutex queueLock;std::vector<std::string> events;
uint64_t inputWrites=0,jsonWrites=0,focusReads=0,keyPolls=0,suppressed=0;
uint32_t viewportWidth=0,viewportHeight=0;
double unixNow(){
 FILETIME ft{};GetSystemTimeAsFileTime(&ft);ULARGE_INTEGER u{};u.LowPart=ft.dwLowDateTime;u.HighPart=ft.dwHighDateTime;
 return double(u.QuadPart)/10000000.0-11644473600.0;
}
int modifiers(){return ((GetAsyncKeyState(VK_SHIFT)&0x8000)?3:0)|((GetAsyncKeyState(VK_CONTROL)&0x8000)?192:0)|((GetAsyncKeyState(VK_MENU)&0x8000)?768:0);}
void enqueue(std::string s){std::lock_guard<std::mutex> lock(queueLock);if(events.size()<512)events.push_back(std::move(s));}
int scan(int vk){if(vk>='A'&&vk<='Z')return vk-'A'+4;if(vk>='1'&&vk<='9')return vk-'1'+30;if(vk=='0')return 39;switch(vk){case VK_RETURN:return 40;case VK_ESCAPE:return 41;case VK_BACK:return 42;case VK_TAB:return 43;case VK_SPACE:return 44;case VK_DELETE:return 76;case VK_RIGHT:return 79;case VK_LEFT:return 80;case VK_DOWN:return 81;case VK_UP:return 82;case VK_HOME:return 74;case VK_END:return 77;default:return 0;}}
std::string pointer(HWND h,int button=-1,int down=-1){POINT p{};RECT r{};GetCursorPos(&p);ScreenToClient(h,&p);GetClientRect(h,&r);double x=double(p.x)/(r.right?r.right:1),y=double(p.y)/(r.bottom?r.bottom:1);char b[240];if(button<0)std::snprintf(b,sizeof b,"{\"t\":\"pointer\",\"x\":%.6f,\"y\":%.6f,\"mods\":%d}",x,y,modifiers());else std::snprintf(b,sizeof b,"{\"t\":\"pointer\",\"x\":%.6f,\"y\":%.6f,\"button\":%d,\"down\":%s,\"mods\":%d}",x,y,button,down?"true":"false",modifiers());return b;}
LRESULT CALLBACK hook(HWND h,UINT m,WPARAM w,LPARAM l){
 if(m==WM_APP+0x32){
  const int releaseKeys[]={'W','A','S','D','E','F','Q','R',VK_SPACE,VK_SHIFT,VK_CONTROL};
  for(int k:releaseKeys)CallWindowProcW(original,h,WM_KEYUP,k,0);
  CallWindowProcW(original,h,WM_LBUTTONUP,0,0);CallWindowProcW(original,h,WM_RBUTTONUP,0,0);return 0;
 }
 // While the MC form owns input, losing macOS focus does not give the hidden
 // Pal character back its keyboard/mouse path. Only F5/session exit does that.
 bool ui=menu.load(),mode=build.load(),live=accepts.load();
 if(ui||mode){
  if(ui&&m==WM_SETCURSOR){SetCursor(LoadCursorW(nullptr,MAKEINTRESOURCEW(32512)));return TRUE;}
  if(ui&&(m==WM_LBUTTONDOWN||m==WM_LBUTTONUP||m==WM_RBUTTONDOWN||m==WM_RBUTTONUP||m==WM_MBUTTONDOWN||m==WM_MBUTTONUP)){
   int b=(m==WM_LBUTTONDOWN||m==WM_LBUTTONUP)?1:((m==WM_RBUTTONDOWN||m==WM_RBUTTONUP)?3:2);
   if(live)enqueue(pointer(h,b,m==WM_LBUTTONDOWN||m==WM_RBUTTONDOWN||m==WM_MBUTTONDOWN));return 0;
  }
  if(m==WM_MOUSEWHEEL){char b[100];std::snprintf(b,sizeof b,"{\"t\":\"%s\",\"d\":%d}",ui?"wheel":"scroll",GET_WHEEL_DELTA_WPARAM(w)/WHEEL_DELTA);if(live)enqueue(b);return 0;}
  if(ui&&(m==WM_KEYDOWN||m==WM_SYSKEYDOWN)){
   if(live&&w!=VK_F8){int s=scan(static_cast<int>(w));if(s){int code=(w>='A'&&w<='Z')?int(w)+32:((w>=32&&w<=126)?int(w):(1<<30)|s);char b[150];std::snprintf(b,sizeof b,"{\"t\":\"gui_key\",\"scan\":%d,\"key\":%d,\"mods\":%d}",s,code,modifiers());enqueue(b);}}
   return 0;
  }
  if(ui&&m==WM_CHAR){
   if(live&&w>=32&&w!=127){wchar_t c[2]={static_cast<wchar_t>(w),0};char u[8]{};int n=WideCharToMultiByte(CP_UTF8,0,c,1,u,8,nullptr,nullptr);std::string s="{\"t\":\"text\",\"text\":\"";for(int i=0;i<n;i++){if(u[i]=='"'||u[i]=='\\')s+='\\';s+=u[i];}s+="\"}";enqueue(s);}return 0;
  }
  if(m==WM_MOUSEMOVE){
   if(mode&&!ui&&live&&!actionsSuspended.load()&&GetTickCount64()>=mouseAfter){
    RECT r{};if(GetClientRect(h,&r)){
     {std::lock_guard<std::mutex> lock(mouseCompatLock);
      auto d=macMouseMode()==2?mouseCompat.host_move(reinterpret_cast<uintptr_t>(h),GET_X_LPARAM(l),GET_Y_LPARAM(l),r.right-r.left,r.bottom-r.top,unixNow()):
        mouseCompat.move(reinterpret_cast<uintptr_t>(h),GET_X_LPARAM(l),GET_Y_LPARAM(l),r.right-r.left,r.bottom-r.top);
      mouseX+=d.x;mouseY+=d.y;}
     recenterMessageMouse(h,r);
    }
   }
   return 0;
  }
  if(m==WM_KEYUP||m==WM_SYSKEYUP||m==WM_KEYDOWN||m==WM_SYSKEYDOWN||m==WM_CHAR)return 0;
  if(m==WM_LBUTTONDOWN||m==WM_LBUTTONUP||m==WM_RBUTTONDOWN||m==WM_RBUTTONUP||m==WM_MBUTTONDOWN||m==WM_MBUTTONUP)return 0;
  if(m==WM_INPUT){
   if(macMouseMode()!=2&&mode&&!ui&&live&&GetTickCount64()>=mouseAfter){RAWINPUT raw{};UINT size=sizeof raw;if(GetRawInputData(reinterpret_cast<HRAWINPUT>(l),RID_INPUT,&raw,&size,sizeof(RAWINPUTHEADER))!=UINT(-1)&&raw.header.dwType==RIM_TYPEMOUSE&&!(raw.data.mouse.usFlags&MOUSE_MOVE_ABSOLUTE)){
    std::lock_guard<std::mutex> lock(mouseCompatLock);
    if(mouseCompat.raw_motion(raw.data.mouse.lLastX,raw.data.mouse.lLastY)){mouseX+=raw.data.mouse.lLastX;mouseY+=raw.data.mouse.lLastY;}
   }}
   return DefWindowProcW(h,m,w,l);
  }
 }
 return CallWindowProcW(original,h,m,w,l);
}
void writeSnapshot(bool focused,const bool *keys,int generation){
 static HANDLE file=INVALID_HANDLE_VALUE;static uint64_t sequence=0;static ULONGLONG retry=0;
 auto now=GetTickCount64();
 if(file==INVALID_HANDLE_VALUE&&now>=retry){
  file=CreateFileW(palcraft_paths::bridge_file(L"input-live.bin").c_str(),GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);retry=now+500;
 }
 PalCraftInputSnapshot s{};std::memcpy(s.magic,"PALINP15",8);
 sequence+=2;s.sequence=s.sequence_end=sequence;s.tick_ms=now;s.unix_time=unixNow();
 s.mouse_x=mouseX.load();s.mouse_y=mouseY.load();s.generation=static_cast<uint32_t>(generation);
 bool moving=focused&&build&&!menu;
 s.flags=(menu?PalCraftMenu:0)|(build?PalCraftBuild:0)|(focused?PalCraftFocus:0)|(moving&&keys[VK_SPACE]?PalCraftJump:0)|(moving&&keys[VK_SHIFT]?PalCraftSneak:0)|(moving&&keys[VK_CONTROL]?PalCraftSprint:0);
 s.forward=moving?int(keys['W'])-int(keys['S']):0;s.strafe=moving?int(keys['D'])-int(keys['A']):0;
 s.viewport_width=viewportWidth;s.viewport_height=viewportHeight;
 if(file!=INVALID_HANDLE_VALUE){
  LARGE_INTEGER at{};at.QuadPart=8;DWORD n=0;uint64_t busy=sequence-1;
  bool ok=SetFilePointerEx(file,at,nullptr,FILE_BEGIN)&&WriteFile(file,&busy,sizeof busy,&n,nullptr)&&n==sizeof busy;
  at.QuadPart=0;ok=ok&&SetFilePointerEx(file,at,nullptr,FILE_BEGIN)&&WriteFile(file,&s,sizeof s,&n,nullptr)&&n==sizeof s;
  if(ok)++inputWrites;else{CloseHandle(file);file=INVALID_HANDLE_VALUE;}
 }
 // HUD/legacy readers need mode transitions immediately, plus a 10Hz heartbeat;
 // camera and movement consumers use the 8ms binary snapshot.
 static ULONGLONG written=0;static uint32_t oldFlags=~uint32_t(0);
 if(now-written<100&&oldFlags==s.flags)return;written=now;oldFlags=s.flags;
 bool hostEligible=false;double armed=0;{std::lock_guard<std::mutex> lock(mouseCompatLock);hostEligible=mouseCompat.host_capture(macMouseMode()==2);armed=mouseCompat.hostRequest;}
 RECT mouseWindow{},mouseClient{};POINT mouseOrigin{},mouseCursor{};
 bool mouseGeometry=window&&GetWindowRect(window,&mouseWindow)&&GetClientRect(window,&mouseClient)&&ClientToScreen(window,&mouseOrigin);
 bool mouseCursorObserved=mouseGeometry&&GetCursorPos(&mouseCursor)&&ScreenToClient(window,&mouseCursor);
 char data[2048];std::snprintf(data,sizeof data,"{\"menu\":%s,\"build\":%s,\"focus\":%s,\"unix\":%.6f,\"forward\":%d,\"strafe\":%d,\"jump\":%s,\"sneak\":%s,\"sprint\":%s,\"mouse_x\":%lld,\"mouse_y\":%lld,\"generation\":%u,\"tick_ms\":%llu,\"viewport_width\":%u,\"viewport_height\":%u,\"mouse_compatibility_mode\":\"%s\",\"mouse_owner_token\":\"%s\",\"mouse_native_epoch\":\"%s\",\"mouse_host_eligible\":%s,\"mouse_host_armed_request\":%.6f,\"mouse_win_geometry_valid\":%s,\"mouse_win_window_x\":%ld,\"mouse_win_window_y\":%ld,\"mouse_win_window_width\":%ld,\"mouse_win_window_height\":%ld,\"mouse_win_client_origin_x\":%ld,\"mouse_win_client_origin_y\":%ld,\"mouse_win_cursor_observed\":%s,\"mouse_win_cursor_x\":%ld,\"mouse_win_cursor_y\":%ld}",menu?"true":"false",build?"true":"false",focused?"true":"false",s.unix_time,s.forward,s.strafe,(s.flags&PalCraftJump)?"true":"false",(s.flags&PalCraftSneak)?"true":"false",(s.flags&PalCraftSprint)?"true":"false",static_cast<long long>(s.mouse_x),static_cast<long long>(s.mouse_y),s.generation,static_cast<unsigned long long>(s.tick_ms),s.viewport_width,s.viewport_height,macMouseMode()==2?"relative-host-warp-v1":(macMouseMode()==1?"relative-v1":"raw"),mouseOwnerToken(),mouseNativeEpoch(),hostEligible?"true":"false",armed,mouseGeometry?"true":"false",mouseWindow.left,mouseWindow.top,mouseWindow.right-mouseWindow.left,mouseWindow.bottom-mouseWindow.top,mouseOrigin.x,mouseOrigin.y,mouseCursorObserved?"true":"false",mouseCursor.x,mouseCursor.y);
 FILE*f=_wfopen(palcraft_paths::bridge_file(L"input-state.tmp").c_str(),L"wb");if(f){fputs(data,f);fclose(f);if(MoveFileExW(palcraft_paths::bridge_file(L"input-state.tmp").c_str(),palcraft_paths::bridge_file(L"input-state.json").c_str(),MOVEFILE_REPLACE_EXISTING))++jsonWrites;}
}
bool platformFocused(){
 static ULONGLONG checked=0;static bool focused=true;static bool companionSeen=false;
 auto now=GetTickCount64();if(now-checked<25)return focused;checked=now;++focusReads;
 HANDLE f=CreateFileW(palcraft_paths::bridge_file(L"platform-focus.txt").c_str(),GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,0,nullptr);
 if(f==INVALID_HANDLE_VALUE)return focused=!companionSeen;
 companionSeen=true;char b[96]{};DWORD n=0;ReadFile(f,b,sizeof(b)-1,&n,nullptr);CloseHandle(f);
 double stamp=0;int enabled=0;double age=unixNow();
 focused=std::sscanf(b,"%lf %d",&stamp,&enabled)==2&&enabled==1&&age-stamp>=-1&&age-stamp<1.5;return focused;
}
}
void controls_feedback(const std::string &s){menu=build&&s.find("\"screen\":true")!=std::string::npos;feedbackAt=GetTickCount64();}
double controls_viewport_aspect(){return viewportWidth&&viewportHeight?double(viewportWidth)/viewportHeight:16.0/9.0;}
void controls_suspend_actions(bool paused){actionsSuspended=paused;}
void controls_request_form(bool on){formRequests.submit(on);}
void controls_tick(WsClient &ws,bool active){
 const auto tick=GetTickCount64();DWORD pid=0;HWND h=GetForegroundWindow();GetWindowThreadProcessId(h,&pid);
 bool live=active&&ws.connected()&&pid==GetCurrentProcessId()&&platformFocused()&&!actionsSuspended;
 if(live&&!accepts)mouseAfter=tick+40;accepts=live;
 if(live&&h!=window){
  if(window&&original&&IsWindow(window))SetWindowLongPtrW(window,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(original));
  window=h;original=reinterpret_cast<WNDPROC>(SetWindowLongPtrW(h,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(hook)));
 }
 static ULONGLONG viewportAt=0;if(window&&tick-viewportAt>=100){viewportAt=tick;RECT r{};if(GetClientRect(window,&r)){viewportWidth=static_cast<uint32_t>(r.right-r.left);viewportHeight=static_cast<uint32_t>(r.bottom-r.top);}}
 static int generation=-1;bool newConnection=ws.connected()&&ws.generation()!=generation;
 // Diagnostic state only; no new log, transport, timer or mode writer.
 struct BuildOffObservation{const char*reason="none";ULONGLONG tick=0;int generationBefore=-1,generationAfter=-1;
  bool active=false,connected=false,suspended=false,f5=false,esc=false;int requested=-1;};
 static BuildOffObservation lastBuildOff;bool observedBuildOff=false;
 auto observeBuildMode=[&](bool on,const char*reason){
  const bool before=build.load();set_build_mode(on);
  if(before&&!build.load()){
   lastBuildOff.reason=reason;lastBuildOff.tick=tick;lastBuildOff.generationBefore=generation;
   lastBuildOff.active=active;lastBuildOff.connected=ws.connected();lastBuildOff.suspended=actionsSuspended.load();
   observedBuildOff=true;
  }
 };
 if(!ws.connected()||newConnection||(!active&&actionsSuspended.load()))observeBuildMode(false,!ws.connected()?"websocket_disconnected":(newConnection?"connection_generation_changed":"camera_inactive"));
 if(newConnection)generation=ws.generation();
 formRequests.observed_generation(generation);
 const int requested=formRequests.take(generation,active&&ws.connected(),newConnection,actionsSuspended.load());
 if(requested>=0)observeBuildMode(requested==1,"explicit_form_off_request");
 static bool was[256]{};bool now[256]{};
 const int keys[]={'W','A','S','D','E','1','2','3','4','5','6','7','8','9',VK_SPACE,VK_SHIFT,VK_CONTROL,VK_ESCAPE,VK_F5,VK_F6,VK_F7,VK_F8,VK_F9,VK_F10,VK_LBUTTON,VK_RBUTTON};
 for(int k:keys){now[k]=(GetAsyncKeyState(k)&0x8000)!=0;++keyPolls;}
 auto rising=[&](int k){return live&&!newConnection&&now[k]&&!was[k];};
 if(rising(VK_F5))observeBuildMode(!build.load(),"f5_toggle_off");
 else if(!active&&build.load()&&!newConnection&&now[VK_F5]&&!was[VK_F5]&&ws.connected()&&pid==GetCurrentProcessId()&&!actionsSuspended.load()&&platformFocused())observeBuildMode(false,"f5_toggle_off");
 if(build&&(rising(VK_F8)||(!menu&&rising('E'))))ws.send("{\"t\":\"inventory_toggle\"}");
 if(build&&!menu&&rising(VK_ESCAPE))observeBuildMode(false,"escape_without_guest_menu");
 if(observedBuildOff){lastBuildOff.generationAfter=generation;lastBuildOff.f5=now[VK_F5];lastBuildOff.esc=now[VK_ESCAPE];lastBuildOff.requested=requested;}
 if(!build)menu=false;
 static bool oldBuild=false;static bool oldLive=false;
 if(newConnection||oldBuild!=build){ws.send(build?"{\"t\":\"mode\",\"on\":true}":"{\"t\":\"mode\",\"on\":false}");if(window)PostMessageW(window,WM_APP+0x32,0,0);oldBuild=build;}
 // A lost-focus GUI drag must release its mouse button in the guest, otherwise
 // the next pointer move after focus returns continues the old drag.
 static bool dragWas[3]{};const int dragKeys[]={VK_LBUTTON,VK_MBUTTON,VK_RBUTTON};const int dragButtons[]={1,2,3};
 if(oldLive&&!live&&menu){for(int i=0;i<3;++i)if(dragWas[i])ws.send(pointer(window,dragButtons[i],0));}
 for(int i=0;i<3;++i)dragWas[i]=live&&menu&&(GetAsyncKeyState(dragKeys[i])&0x8000);oldLive=live;
 static bool attackWas=false,useWas=false;
 bool attack=live&&!menu&&build&&(now[VK_F9]||now[VK_LBUTTON]);bool use=live&&!menu&&build&&(now[VK_F10]||now[VK_RBUTTON]);
 if(newConnection||attack!=attackWas)ws.send(attack?"{\"t\":\"key\",\"k\":\"attack\",\"down\":true}":"{\"t\":\"key\",\"k\":\"attack\",\"down\":false}");
 if(newConnection||use!=useWas)ws.send(use?"{\"t\":\"key\",\"k\":\"use\",\"down\":true}":"{\"t\":\"key\",\"k\":\"use\",\"down\":false}");attackWas=attack;useWas=use;
 if(build&&!menu){
  if(rising(VK_F6))ws.send("{\"t\":\"scroll\",\"d\":1}");if(rising(VK_F7))ws.send("{\"t\":\"scroll\",\"d\":-1}");
  for(int n=0;n<9;n++)if(rising('1'+n)){char b[50];std::snprintf(b,sizeof b,"{\"t\":\"slot\",\"n\":%d}",n);ws.send(b);}
 }
 static ULONGLONG pointerAt=0;if(live&&menu&&tick-pointerAt>=16){pointerAt=tick;ClipCursor(nullptr);ws.send(pointer(window));}
 bool watchMouseWarp=false;
 {std::lock_guard<std::mutex> lock(mouseCompatLock);mouseCompat.scope(macMouseMessages(),live&&build&&!menu&&!newConnection,
    reinterpret_cast<uintptr_t>(window),generation);watchMouseWarp=mouseCompat.warpPending;}
 if(macMouseMode()==1&&watchMouseWarp&&live&&build&&!menu&&!newConnection&&window){
  POINT p{};RECT r{};if(GetCursorPos(&p)&&ScreenToClient(window,&p)&&GetClientRect(window,&r)){
   std::lock_guard<std::mutex> lock(mouseCompatLock);
   mouseCompat.observe_cursor(reinterpret_cast<uintptr_t>(window),p.x,p.y,r.right-r.left,r.bottom-r.top,tick);
  }
 }
 if(macMouseMode()==2&&live&&build&&!menu&&!newConnection&&window){
  static ULONGLONG readAt=0;static double lastHostWarp=0;
  if(tick-readAt>=25){readAt=tick;FILE*f=_wfopen(palcraft_paths::bridge_file(L"mac-mouse-host.json").c_str(),L"rb");
   if(f){char data[2049]{};size_t n=std::fread(data,1,2048,f);const bool complete=std::fgetc(f)==EOF;std::fclose(f);
    PalCraftHostMouseWarp seen;RECT r{};
    if(complete&&seen.parse(data,n)&&GetClientRect(window,&r)&&seen.matches(mouseOwnerToken(),mouseNativeEpoch(),generation,r.right-r.left,r.bottom-r.top,unixNow())){
     std::lock_guard<std::mutex> lock(mouseCompatLock);
     if(seen.is_request())mouseCompat.arm_host(reinterpret_cast<uintptr_t>(window),seen.x,seen.y,seen.requested);
     else if(seen.actual_observed(unixNow())&&seen.requested==mouseCompat.hostRequest&&seen.observed>lastHostWarp){
      POINT actual{};
      if(GetCursorPos(&actual)&&ScreenToClient(window,&actual)&&actual.x==seen.x&&actual.y==seen.y&&
         mouseCompat.host_baseline(reinterpret_cast<uintptr_t>(window),actual.x,actual.y))lastHostWarp=seen.observed;
     }
    }
   }
  }
 }
 writeSnapshot(live,now,generation);
 std::vector<std::string> pending;{std::lock_guard<std::mutex> lock(queueLock);pending.swap(events);}for(auto&s:pending){if(live&&build)ws.send(s);else ++suppressed;}
 for(int k:keys)was[k]=now[k];
 static ULONGLONG profiled=0;if(tick-profiled>=1000){profiled=tick;FILE*f=_wfopen(palcraft_paths::bridge_file(L"controls-performance.json").c_str(),L"wb");if(f){std::fprintf(f,"{\"version\":15,\"unix\":%.6f,\"sample_tick_ms\":%llu,\"binary_writes\":%llu,\"json_writes\":%llu,\"focus_reads\":%llu,\"key_polls\":%llu,\"suppressed_events\":%llu,\"focus\":%s,\"build\":%s,\"menu\":%s,\"viewport_width\":%u,\"viewport_height\":%u",unixNow(),static_cast<unsigned long long>(tick),static_cast<unsigned long long>(inputWrites),static_cast<unsigned long long>(jsonWrites),static_cast<unsigned long long>(focusReads),static_cast<unsigned long long>(keyPolls),static_cast<unsigned long long>(suppressed),live?"true":"false",build?"true":"false",menu?"true":"false",viewportWidth,viewportHeight);std::fprintf(f,",\"last_build_off_reason\":\"%s\",\"last_build_off_tick_ms\":%llu,\"last_build_off_generation\":{\"before\":%d,\"after\":%d},\"last_build_off_active\":%s,\"last_build_off_connected\":%s,\"last_build_off_suspended\":%s,\"last_build_off_f5\":%s,\"last_build_off_esc\":%s,\"last_build_off_requested\":%d}",lastBuildOff.reason,static_cast<unsigned long long>(lastBuildOff.tick),lastBuildOff.generationBefore,lastBuildOff.generationAfter,lastBuildOff.active?"true":"false",lastBuildOff.connected?"true":"false",lastBuildOff.suspended?"true":"false",lastBuildOff.f5?"true":"false",lastBuildOff.esc?"true":"false",lastBuildOff.requested);fclose(f);}}
}
