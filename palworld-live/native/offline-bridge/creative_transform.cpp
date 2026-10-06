// BridgeLab fixed native server construction entry, preserving real owner UID.
// The public ByPlayer wrapper fixes scale to 1; this adapter passes native scale.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
struct Guid {uint32_t a,b,c,d;};
struct Vec {double x,y,z;};
struct Quat {double x,y,z,w;};
struct Wire {char magic[8];uint32_t thread,reserved;uint64_t expires,manager,klass,name;Vec position;Quat rotation;Vec scale;Guid uid;};
struct alignas(16) Request {uint64_t name;Vec position;Quat rotation;Vec scale;Guid uid;uint8_t normal;uint8_t padding[7];};
struct Extra {uint64_t objects;int32_t num,max;uint8_t byte0;uint8_t padding[3];Guid id;uint8_t byte1;uint8_t tail[3];};
struct Shared {uint64_t object,control;};
static_assert(sizeof(Request)==0x70 && sizeof(Extra)==0x28,"ABI layout");
static const wchar_t* root=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\";
static bool read(uint64_t p,void* v,size_t n){SIZE_T got=0;return p>0x10000&&ReadProcessMemory(GetCurrentProcess(),(void*)p,v,n,&got)&&got==n;}
static bool bytes(uint64_t p,const uint8_t* wanted,unsigned n){uint8_t b[32];if(n>32||!read(p,b,n))return false;for(unsigned i=0;i<n;i++)if(b[i]!=wanted[i])return false;return true;}
static void output(const char* text){HANDLE f=CreateFileW(L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\creative-transform-result.json",GENERIC_WRITE,FILE_SHARE_READ,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);if(f==INVALID_HANDLE_VALUE)return;DWORD got;WriteFile(f,text,(DWORD)lstrlenA(text),&got,nullptr);FlushFileBuffers(f);CloseHandle(f);}
extern "C" __declspec(dllexport) int pal_creative_transform_v2(void*){
 wchar_t exe[512];GetModuleFileNameW(nullptr,exe,512);
 if(lstrcmpiW(exe,L"D:\\PalworldServer-LAN\\BridgeLab\\Pal\\Binaries\\Win64\\PalServer-Win64-Shipping-Cmd.exe")){output("{\"ok\":false,\"error\":\"wrong_executable\"}");return 0;}
 Wire w{};HANDLE f=CreateFileW(L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\creative-transform-request.bin",GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);if(f==INVALID_HANDLE_VALUE)return 0;
 DWORD got=0;bool loaded=ReadFile(f,&w,sizeof(w),&got,nullptr)&&got==sizeof(w);CloseHandle(f);
 uint64_t base=(uint64_t)GetModuleHandleW(nullptr),klass=0;uint32_t flags=0;
 const uint8_t signature[]={0x40,0x53,0x55,0x56,0x57,0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57,0x48,0x81,0xec,0x88,0x00,0x00,0x00};
 if(!loaded||w.thread!=GetCurrentThreadId()||w.reserved||!bytes(base+0x2f254d0,signature,sizeof(signature))||!read(w.manager+0x10,&klass,8)||klass!=w.klass||!read(w.manager+8,&flags,4)||(flags&0x60000000u)){output("{\"ok\":false,\"error\":\"context_or_fingerprint_mismatch\"}");return 0;}
 Request req{};req.name=w.name;req.position=w.position;req.rotation=w.rotation;req.scale=w.scale;req.uid=w.uid;req.normal=0;Extra extra{};extra.byte1=1;Shared shared{};
 output("{\"ok\":false,\"stage\":\"native_call_started\"}");
 using Spawn=void*(__fastcall*)(void*,Shared*,const Request*,const Extra*);
 ((Spawn)(base+0x2f254d0))((void*)w.manager,&shared,&req,&extra);
 bool acquired=shared.object!=0;
 if(shared.control){auto p=(LONG*)(shared.control+8);if(InterlockedExchangeAdd(p,-1)==1){auto vt=*(uint64_t**)shared.control;((void(__fastcall*)(void*))vt[0])((void*)shared.control);if(InterlockedExchangeAdd((LONG*)(shared.control+12),-1)==1)((void(__fastcall*)(void*,uint32_t))vt[1])((void*)shared.control,0xffffffffu);}}
 output(acquired?"{\"ok\":true,\"queued\":true,\"owner_uid_preserved\":true,\"scale_preserved\":true}":"{\"ok\":false,\"stage\":\"no_request_handler\"}");return 0;
}
extern "C" BOOL WINAPI DllMain(HINSTANCE,DWORD,LPVOID){return TRUE;}
