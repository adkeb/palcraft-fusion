// Lua publishes the actual Palworld camera on the game thread. This worker only
// handles input, files and loopback WebSocket traffic; it never calls Unreal.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "../launcher/windows_paths.hpp"
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <atomic>
#include <mutex>
#include <ctime>
#include <cmath>
#include "compositor.h"
#include "ws.h"
#include "controls.h"

extern "C" __declspec(dllexport) const char *NAME="PalCraft Minecraft Fusion";
extern "C" __declspec(dllexport) const char *DESCRIPTION="Minecraft world and survival input inside Palworld";
static HMODULE module;static HANDLE worker;
static std::atomic<bool> stopping{false};
#pragma pack(push,1)
struct Camera {
 char magic[8];uint32_t version,flags;double unix_time;
 double x,y,z,px,py,pz;float yaw,pitch,roll,fov,near_clip,far_clip;
};
struct CameraLive {Camera camera;uint64_t input_tick_ms,lua_frame;};
#pragma pack(pop)
static_assert(sizeof(Camera)==96);
static_assert(sizeof(CameraLive)==112);
struct Timing{uint64_t count=0;double sum=0,max=0;void add(double ms){++count;sum+=ms;if(ms>max)max=ms;}void clear(){count=0;sum=max=0;}};
static std::mutex cameraLock;
static Camera memoryCamera{};
static uint64_t memoryPublishFrame=0;
static std::string memoryCaptureScope;
static Timing inputCameraTiming;
static std::atomic<uint64_t> cameraRevision{0};
static std::atomic<ULONGLONG> committedAt{0};
static std::atomic<uint64_t> commitReads{0},compatWrites{0},fileReads{0},journalWrites{0};
static bool validCamera(const Camera &c){return !std::memcmp(c.magic,"PALCRFT1",8)&&c.version==2;}
extern "C" __declspec(dllexport) int palcraft_suspend_actions(void *){controls_suspend_actions(true);return 0;}
extern "C" __declspec(dllexport) int palcraft_resume_actions(void *){controls_suspend_actions(false);return 0;}
extern "C" __declspec(dllexport) int palcraft_form_on(void *){controls_request_form(true);return 0;}
extern "C" __declspec(dllexport) int palcraft_form_off(void *){controls_request_form(false);return 0;}
extern "C" __declspec(dllexport) int palcraft_commit_camera(void *) {
 // The v15 Lua writer keeps camera-live.bin open and flushes before calling us.
 // This function runs on that same game thread, so there is no torn read.
 static HANDLE file=INVALID_HANDLE_VALUE;
 if(file==INVALID_HANDLE_VALUE)file=CreateFileW(palcraft_paths::bridge_file(L"camera-live.bin").c_str(),GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(file!=INVALID_HANDLE_VALUE){
  CameraLive c{};LARGE_INTEGER at{};DWORD n=0;
  if(SetFilePointerEx(file,at,nullptr,FILE_BEGIN)&&ReadFile(file,&c,sizeof c,&n,nullptr)&&n>=sizeof(Camera)&&validCamera(c.camera)){
   std::string captureScope;
   if(c.camera.flags&4){
    uint32_t length=0;DWORD count=0;
    if(n!=sizeof c||!ReadFile(file,&length,sizeof length,&count,nullptr)||count!=sizeof length||length<2||length>4096)return 0;
    captureScope.resize(length);
    if(!ReadFile(file,captureScope.data(),length,&count,nullptr)||count!=length||captureScope.front()!='{'||captureScope.back()!='}')return 0;
   }
   // Camera coordinates and their production-time scope are copied together.
   // Scope must never be obtained from a later ACK/current-view sidecar.
   {std::lock_guard<std::mutex> lock(cameraLock);memoryCamera=c.camera;memoryPublishFrame=n==sizeof c?c.lua_frame:0;
    memoryCaptureScope=std::move(captureScope);auto now=GetTickCount64();if(n==sizeof c&&(c.camera.flags&1)&&c.input_tick_ms&&now>=c.input_tick_ms&&now-c.input_tick_ms<300)inputCameraTiming.add(double(now-c.input_tick_ms));}
   committedAt=GetTickCount64();++cameraRevision;++commitReads;return 0;
  }
  CloseHandle(file);file=INVALID_HANDLE_VALUE;return 0;
 }
 // Existing v2 file publishers remain compatible.
 MoveFileExW(palcraft_paths::bridge_file(L"camera.tmp").c_str(),palcraft_paths::bridge_file(L"camera.bin").c_str(),MOVEFILE_REPLACE_EXISTING);
 return 0;
}
static std::string read_file(const wchar_t *path) {
 ++fileReads;HANDLE f=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,0,nullptr);
 if(f==INVALID_HANDLE_VALUE)return {};
 LARGE_INTEGER length{};if(!GetFileSizeEx(f,&length)||length.QuadPart<0||length.QuadPart>64*1024*1024){CloseHandle(f);return {};}
 std::string bytes(static_cast<size_t>(length.QuadPart),'\0');DWORD n=0;
 ReadFile(f,bytes.data(),static_cast<DWORD>(bytes.size()),&n,nullptr);CloseHandle(f);bytes.resize(n);return bytes;
}
static void append_events(const std::string &s) {
 if(s.empty())return;
 HANDLE f=CreateFileW(palcraft_paths::journal_file(L"palcraft-events.ndjson").c_str(),FILE_APPEND_DATA,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_ALWAYS,0,nullptr);
 if(f==INVALID_HANDLE_VALUE)return;DWORD n=0;if(WriteFile(f,s.data(),static_cast<DWORD>(s.size()),&n,nullptr)&&n==s.size())++journalWrites;CloseHandle(f);
}
static void publish_compat(const Camera &c){
 FILE*f=_wfopen(palcraft_paths::bridge_file(L"camera.tmp").c_str(),L"wb");
 if(f){bool ok=fwrite(&c,1,sizeof c,f)==sizeof c;fclose(f);if(ok&&MoveFileExW(palcraft_paths::bridge_file(L"camera.tmp").c_str(),palcraft_paths::bridge_file(L"camera.bin").c_str(),MOVEFILE_REPLACE_EXISTING))++compatWrites;}
}
static void status(bool connected,bool active) {
 FILE *f=_wfopen(palcraft_paths::bridge_file(L"render-status.json").c_str(),L"wb");
 if(f){std::fprintf(f,"{\"websocket_connected\":%s,\"camera_active\":%s,\"version\":15,\"camera_transport\":\"%s\",\"updated_unix\":%lld}",connected?"true":"false",active?"true":"false",cameraRevision?"persistent_file_to_memory":"legacy_file",static_cast<long long>(std::time(nullptr)));std::fclose(f);}
}
static double millis(){static LARGE_INTEGER frequency=[](){LARGE_INTEGER v{};QueryPerformanceFrequency(&v);return v;}();LARGE_INTEGER v{};QueryPerformanceCounter(&v);return double(v.QuadPart)*1000/double(frequency.QuadPart);}
static int host_proxy_port(){
 wchar_t value[16]{};SetLastError(ERROR_SUCCESS);
 DWORD used=GetEnvironmentVariableW(L"PALCRAFT_HOST_PROXY_PORT",value,16);
 if(!used)return GetLastError()==ERROR_ENVVAR_NOT_FOUND?25599:0;
 if(used>=16)return 0;
 int port=0;
 for(DWORD i=0;i<used;++i){if(value[i]<L'0'||value[i]>L'9')return 0;port=port*10+int(value[i]-L'0');if(port>65535)return 0;}
 return port;
}
static DWORD WINAPI loop(void *) {
 const int proxyPort=host_proxy_port();
 if(!proxyPort){status(false,false);OutputDebugStringW(L"[PalCraft] Invalid PALCRAFT_HOST_PROXY_PORT; connection refused.\n");return 0;}
 WsClient ws;ws.start("127.0.0.1",proxyPort);
 const bool wine=GetProcAddress(GetModuleHandleW(L"ntdll.dll"),"wine_get_version")!=nullptr;
 ULONGLONG registerAfter=0,lastStatus=0,lastFiles=0,lastCompat=0,lastCameraRead=0;
 std::string sentGround;int oldGeneration=-1;unsigned long frame=0;
 uint64_t sentRevision=0;Camera c{};bool active=false;
 Timing cadence,work,controls,network;double previous=0;
 while(!stopping) {
  const auto tick=GetTickCount64();double started=millis();if(previous)cadence.add(started-previous);previous=started;
  uint64_t revision=cameraRevision.load(),publishFrame=0;std::string captureScope;
  if(revision){std::lock_guard<std::mutex> lock(cameraLock);c=memoryCamera;publishFrame=memoryPublishFrame;captureScope=memoryCaptureScope;auto committed=committedAt.load();active=validCamera(c)&&(c.flags&1)&&(tick>=committed?tick-committed:0)<750;}
  else if(tick-lastCameraRead>=16){
   lastCameraRead=tick;std::string bytes=read_file(palcraft_paths::bridge_file(L"camera.bin").c_str());
   active=false;if(bytes.size()==sizeof c){std::memcpy(&c,bytes.data(),sizeof c);active=validCamera(c)&&(c.flags&1)&&std::abs(double(std::time(nullptr))-c.unix_time)<3;}
  }
  compositor::set_active(active);
  if(!wine&&tick-registerAfter>=1000){registerAfter=tick;compositor::try_register(module);}
  // Drain a bounded batch before sampling controls, so feedback does not add a
  // full worker period to inventory/focus transitions during large block replays.
  std::string message,feedback,batch;for(int i=0;i<128&&ws.poll(message);++i){
   if(message.find("\"t\":\"feedback\"")!=std::string::npos){controls_feedback(message);feedback=std::move(message);}
   else{batch+=message;batch+='\n';}
  }
  double section=millis();controls_tick(ws,active);controls.add(millis()-section);section=millis();
  if(active){
   compositor::set_host_planes(c.near_clip,c.far_clip);compositor::set_host_pose(c.yaw,c.pitch,c.roll,c.fov,c.x,c.y,c.z);
   if(ws.connected()){
    bool connectedNow=oldGeneration!=ws.generation();
    if(connectedNow){oldGeneration=ws.generation();sentGround.clear();sentRevision=0;ws.send("{\"t\":\"blocksync\",\"r\":32}");}
    if(connectedNow||!revision||revision!=sentRevision){
     char b[1024];std::snprintf(b,sizeof b,"{\"t\":\"cam\",\"f\":%lu,\"p\":[%.6f,%.6f,%.6f],\"r\":[%.5f,%.5f,%.5f],\"fov\":%.5f,\"aspect\":%.6f,\"fp\":true,\"pl\":[%.6f,%.6f,%.6f],\"h\":%.5f,\"g\":%s}",++frame,c.x,c.y,c.z,c.yaw,c.pitch,c.roll,c.fov,controls_viewport_aspect(),c.px,c.py,c.pz,c.yaw,(c.flags&2)?"true":"false");
     std::string packet=b;
     if(!captureScope.empty()){
      packet.pop_back();packet+=",\"publish_frame\":"+std::to_string(publishFrame)+",\"source_generation\":"+std::to_string(ws.generation());
      if(captureScope.size()>2)packet+=","+captureScope.substr(1,captureScope.size()-2);packet+='}';
     }
     if(ws.send(packet))sentRevision=revision;
    }
    if(tick-lastFiles>=100){
     lastFiles=tick;std::string ground=read_file(palcraft_paths::bridge_file(L"ground.json").c_str());
     if(!ground.empty()&&ground!=sentGround){ws.send(ground);sentGround=ground;}
     std::string command=read_file(palcraft_paths::bridge_file(L"command.json").c_str());
     if(!command.empty()&&ws.send(command))DeleteFileW(palcraft_paths::bridge_file(L"command.json").c_str());
    }
   }
  }
  network.add(millis()-section);
  append_events(batch);
  if(!feedback.empty()){
   FILE*f=_wfopen(palcraft_paths::bridge_file(L"feedback.tmp").c_str(),L"wb");
   if(f){fwrite(feedback.data(),1,feedback.size(),f);fclose(f);MoveFileExW(palcraft_paths::bridge_file(L"feedback.tmp").c_str(),palcraft_paths::bridge_file(L"feedback.json").c_str(),MOVEFILE_REPLACE_EXISTING);}
  }
  if(revision&&tick-lastCompat>=100){lastCompat=tick;publish_compat(c);}
  work.add(millis()-started);
  if(tick-lastStatus>=1000){
   lastStatus=tick;status(ws.connected(),active);
   Timing inputCamera;{std::lock_guard<std::mutex> lock(cameraLock);inputCamera=inputCameraTiming;inputCameraTiming.clear();}
   FILE*f=_wfopen(palcraft_paths::bridge_file(L"render-performance.json").c_str(),L"wb");
   if(f){std::fprintf(f,"{\"version\":15,\"unix\":%lld,\"clock\":\"QueryPerformanceCounter\",\"samples\":%llu,\"loop_interval_mean_ms\":%.6f,\"loop_interval_max_ms\":%.6f,\"work_mean_ms\":%.6f,\"work_max_ms\":%.6f,\"controls_mean_ms\":%.6f,\"controls_max_ms\":%.6f,\"network_mean_ms\":%.6f,\"network_max_ms\":%.6f,\"input_to_camera_samples\":%llu,\"input_to_camera_mean_ms\":%.6f,\"input_to_camera_max_ms\":%.6f,\"camera_commits\":%llu,\"camera_compat_writes\":%llu,\"file_reads\":%llu,\"journal_batches\":%llu,\"camera_ws_frames\":%lu}",static_cast<long long>(std::time(nullptr)),static_cast<unsigned long long>(work.count),cadence.count?cadence.sum/cadence.count:0,cadence.max,work.count?work.sum/work.count:0,work.max,controls.count?controls.sum/controls.count:0,controls.max,network.count?network.sum/network.count:0,network.max,static_cast<unsigned long long>(inputCamera.count),inputCamera.count?inputCamera.sum/inputCamera.count:0,inputCamera.max,static_cast<unsigned long long>(commitReads.load()),static_cast<unsigned long long>(compatWrites.load()),static_cast<unsigned long long>(fileReads.load()),static_cast<unsigned long long>(journalWrites.load()),frame);fclose(f);}
   cadence.clear();work.clear();controls.clear();network.clear();
  }
  auto spent=GetTickCount64()-tick;Sleep(spent<8?static_cast<DWORD>(8-spent):0);
 }
 ws.stop();return 0;
}
BOOL APIENTRY DllMain(HMODULE h,DWORD reason,LPVOID reserved) {
 if(reason==DLL_PROCESS_ATTACH){module=h;HMODULE pinned=nullptr;GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&loop),&pinned);DisableThreadLibraryCalls(h);worker=CreateThread(nullptr,0,loop,nullptr,0,nullptr);}
 if(reason==DLL_PROCESS_DETACH){stopping=true;if(!reserved&&worker)WaitForSingleObject(worker,3000);compositor::unregister(h);}
 return TRUE;
}
