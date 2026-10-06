// UE5 game-thread bridge. Geometry and materials come from Minecraft's models.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <vector>
struct Wire {char magic[8];uint64_t context,statics,klass,begin,finish,component_class,add_component,create_section,set_material,process_event,set_location;double x,y,z;uint32_t sections,reserved;};
struct alignas(16) Transform {double rotation[4],translation[3],pad0,scale[3],pad1;};
struct alignas(16) Begin {uint64_t context,klass;Transform transform;uint8_t collision,pad[7];uint64_t owner,result,tail;};
struct alignas(16) Finish {uint64_t actor,pad;Transform transform;uint64_t result,tail;};
struct alignas(16) Add {uint64_t klass;uint8_t manual,pad[7];Transform relative;uint8_t deferred,pad2[7];uint64_t result;};
struct Array {void* data;int32_t count,capacity;};
struct Section {int32_t index,pad;Array vertices,triangles,normals,uv,colors,tangents;uint8_t collision,pad2[7];};
struct Vec3 {double x,y,z;};struct Vec2 {double u,v;};
struct Vertex {Vec3 position,normal;Vec2 uv;};
static_assert(sizeof(Wire)==128&&sizeof(Vertex)==64&&offsetof(Add,result)==0x78&&offsetof(Section,collision)==0x68);
static constexpr auto root=L"D:\\PalworldServer-LAN\\PalCraft-Dev\\bridge\\";
static void output(bool ok,uint64_t actor,uint64_t component,const char*stage){
 FILE*f=_wfopen(L"D:\\PalworldServer-LAN\\PalCraft-Dev\\bridge\\model-result.json",L"wb");
 if(f){std::fprintf(f,"{\"ok\":%s,\"actor\":\"0x%llx\",\"component\":\"0x%llx\",\"stage\":\"%s\"}",ok?"true":"false",(unsigned long long)actor,(unsigned long long)component,stage);std::fclose(f);}
}
template<class T> static Array arr(std::vector<T>&v){return{v.data(),int32_t(v.size()),int32_t(v.size())};}
extern "C" __declspec(dllexport) int palcraft_create_model(void*){
 wchar_t exe[512]{};GetModuleFileNameW(nullptr,exe,512);
 if(lstrcmpiW(exe,L"D:\\PalworldServer-LAN\\PalCraft-Client\\Pal\\Binaries\\Win64\\Palworld-Win64-Shipping.exe"))return 0;
 FILE*f=_wfopen(L"D:\\PalworldServer-LAN\\PalCraft-Dev\\bridge\\model-request.bin",L"rb");if(!f)return 0;
 Wire w{};if(fread(&w,1,sizeof w,f)!=sizeof w||memcmp(w.magic,"PALCPRC2",8)||w.sections>1024){fclose(f);output(false,0,0,"request");return 0;}
 using Event=void(__fastcall*)(void*,void*,void*);auto call=(Event)w.process_event;
 Transform t{};t.rotation[3]=1;t.scale[0]=t.scale[1]=t.scale[2]=1;t.translation[0]=w.x;t.translation[1]=w.y;t.translation[2]=w.z;
 Begin b{};b.context=w.context;b.klass=w.klass;b.transform=t;b.collision=1;b.owner=w.context;
 output(false,0,0,"spawn");call((void*)w.statics,(void*)w.begin,&b);
 if(!b.result){fclose(f);output(false,0,0,"spawn_null");return 0;}
 Add a{};a.klass=w.component_class;a.relative.rotation[3]=1;a.relative.scale[0]=a.relative.scale[1]=a.relative.scale[2]=1;
 output(false,b.result,0,"add_component");call((void*)b.result,(void*)w.add_component,&a);
 if(!a.result){fclose(f);output(false,b.result,0,"component_null");return 0;}
 for(uint32_t section=0;section<w.sections;section++){
  struct Header{uint64_t material;uint32_t vertices,indices;}h{};
  if(fread(&h,1,sizeof h,f)!=sizeof h||h.vertices>1000000||h.indices>3000000){fclose(f);output(false,b.result,a.result,"geometry_header");return 0;}
  std::vector<Vertex> input(h.vertices);std::vector<int32_t> indices(h.indices);
  if(fread(input.data(),sizeof(Vertex),h.vertices,f)!=h.vertices||fread(indices.data(),4,h.indices,f)!=h.indices){fclose(f);output(false,b.result,a.result,"geometry_body");return 0;}
  std::vector<Vec3> positions,normals;std::vector<Vec2> uv;
  for(auto&v:input){positions.push_back(v.position);normals.push_back(v.normal);uv.push_back(v.uv);}
  Section s{};s.index=section;s.vertices=arr(positions);s.triangles=arr(indices);s.normals=arr(normals);s.uv=arr(uv);
  output(false,b.result,a.result,"mesh_section");call((void*)a.result,(void*)w.create_section,&s);
  struct Material{int32_t index,pad;uint64_t material;}m{int32_t(section),0,h.material};
  call((void*)a.result,(void*)w.set_material,&m);
 }
 fclose(f);Finish finish{};finish.actor=b.result;finish.transform=t;
 output(false,b.result,a.result,"finish");call((void*)w.statics,(void*)w.finish,&finish);
 // The bare Actor acquires its root after BeginDeferredSpawn. Explicitly place
 // that new root after FinishSpawningActor instead of retaining identity.
 struct Location{Vec3 position;uint8_t sweep,pad[7],hit[0xe8],teleport,result,pad2[6];}location{};
 location.position={w.x,w.y,w.z};location.teleport=1;
 if(finish.result)call((void*)finish.result,(void*)w.set_location,&location);
 output(finish.result!=0,finish.result,a.result,"created");return 0;
}
BOOL APIENTRY DllMain(HMODULE,DWORD,LPVOID){return TRUE;}
