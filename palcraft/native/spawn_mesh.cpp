// Palworld v1.0.5.102999 / UE5: reflected ProcessEvent parameters, no UE4SS
// marshalling of spawned actors or FTransform. Loaded only in the two lab paths.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <string>
struct Wire {char magic[8];uint64_t context,statics,klass,begin,finish;double x,y,z;uint64_t action,actor,process_event,functions[10];uint64_t mesh,material,set_mesh,set_material;double sx,sy,sz;};
struct alignas(16) Transform {double rotation[4],translation[3],pad0,scale[3],pad1;};
struct alignas(16) Begin {uint64_t context,klass;Transform transform;uint8_t collision,pad[7];uint64_t owner,result,tail;};
struct alignas(16) Finish {uint64_t actor,pad;Transform transform;uint64_t result,tail;};
struct Extent {double x,y,z;uint8_t update;uint8_t pad[7];};
static_assert(sizeof(Wire)==232&&sizeof(Transform)==96&&offsetof(Begin,result)==0x80&&offsetof(Finish,result)==0x70);
static std::wstring root;
static void output(bool ok,uint64_t actor,const char *stage){
 FILE*f=_wfopen((root+L"palcraft-spawn-result.json").c_str(),L"wb");
 if(f){std::fprintf(f,"{\"ok\":%s,\"actor\":\"0x%llx\",\"stage\":\"%s\"}",ok?"true":"false",(unsigned long long)actor,stage);std::fclose(f);}
}
extern "C" __declspec(dllexport) int palcraft_spawn_box(void*){
 wchar_t exe[512]{};GetModuleFileNameW(nullptr,exe,512);
 if(!lstrcmpiW(exe,L"D:\\PalworldServer-LAN\\BridgeLab\\Pal\\Binaries\\Win64\\PalServer-Win64-Shipping-Cmd.exe"))root=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\";
 else if(!lstrcmpiW(exe,L"D:\\PalworldServer-LAN\\PalCraft-Client\\Pal\\Binaries\\Win64\\Palworld-Win64-Shipping.exe"))root=L"D:\\PalworldServer-LAN\\PalCraft-Dev\\bridge\\";
 else return 0;
 Wire w{};FILE*f=_wfopen((root+L"palcraft-spawn-request.bin").c_str(),L"rb");
 if(!f)return 0;const bool loaded=std::fread(&w,1,sizeof(w),f)==sizeof(w);std::fclose(f);
 if(!loaded||std::memcmp(w.magic,"PALCMSH6",8)||!w.process_event){output(false,0,"invalid_request");return 0;}
 using ProcessEvent=void(__fastcall*)(void*,void*,void*);
 const auto invoke=reinterpret_cast<ProcessEvent>(w.process_event);
 if(w.action==1){output(false,w.actor,"destroy");invoke((void*)w.actor,(void*)w.functions[9],nullptr);output(true,0,"destroyed");return 0;}
 Transform t{};t.rotation[3]=1;t.translation[0]=w.x;t.translation[1]=w.y;t.translation[2]=w.z;t.scale[0]=w.sx;t.scale[1]=w.sy;t.scale[2]=w.sz;
 Begin b{};b.context=w.context;b.klass=w.klass;b.transform=t;b.collision=1;b.owner=w.context;
 output(false,0,"begin_spawn");invoke((void*)w.statics,(void*)w.begin,&b);
 if(!b.result){output(false,0,"spawn_returned_null");return 0;}
 void* component=*(void**)((uintptr_t)b.result+0x290);
 if(!component){output(false,b.result,"component_missing");return 0;}
 if(w.mesh){
 uint8_t mobility=2;invoke(component,(void*)w.functions[0],&mobility);
 struct MeshArgs{uint64_t mesh;uint8_t result;uint8_t pad[7];} meshArgs{w.mesh,0,{}};
 invoke(component,(void*)w.set_mesh,&meshArgs);
 if(!meshArgs.result){output(false,b.result,"mesh_failed");return 0;}
 struct MaterialArgs{int index,pad;uint64_t material;} materialArgs{0,0,w.material};
 invoke(component,(void*)w.set_material,&materialArgs);
 }
 Finish finish{};finish.actor=b.result;finish.transform=t;
 output(false,b.result,"finish_spawn");invoke((void*)w.statics,(void*)w.finish,&finish);
 if(!finish.result){output(false,0,"finish_returned_null");return 0;}
 void* actor=(void*)finish.result;void* box=*(void**)((uintptr_t)actor+0x290);
 if(!box){output(false,finish.result,"component_missing");return 0;}
 auto call=[&](int slot,void* object,void* args,const char*stage){output(false,finish.result,stage);invoke(object,(void*)w.functions[slot],args);};
 Extent extent{50,50,50,0,{}};uint8_t no=0,yes=1,collision=3;
 if(!w.mesh)call(0,box,&extent,"extent");
 call(1,box,&collision,"collision_enabled");
 call(2,box,&no,"overlaps_disabled");call(3,box,&no,"ignore_channels");
 // Palworld 1.0.5: Water=14, FluidTrace=19 and WaterPlaneRayCast=25 must
 // remain Ignore. BlockAll makes ordinary cubes look like water surfaces.
 for(uint8_t channel : {0,1,2,4,5,6,15,16,20,21,22,24,26,27,28,29}){
  uint8_t response[2]={channel,2};call(4,box,response,"physical_channels");
 }
 if(w.action==2)call(1,box,&no,"visual_only");
 // Both sides mirror the same block journal; local collision prediction needs
 // the configured shape, which TriggerBox does not replicate by default.
 call(5,box,&no,"component_replication");call(6,actor,&no,"actor_replication");
 call(7,actor,&no,"movement_replication");call(8,actor,(w.mesh&&w.action!=3)?&no:&yes,(w.mesh&&w.action!=3)?"visible":"hidden");
 output(true,finish.result,"configured");return 0;
}
BOOL APIENTRY DllMain(HMODULE,DWORD,LPVOID){return TRUE;}
