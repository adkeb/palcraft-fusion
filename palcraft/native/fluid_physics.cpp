// True MC water query bodies, separate from ordinary solid/visual collision.
// Reflected UE5 parameter ABI is the local v3/chunk owner's verified ABI.
// Collision is QueryOnly. Only Water14, FluidTrace19, WaterPlaneRayCast25 block.
// No overlap delegates, PhysicsVolume weak-reference writes, damage, or propagation.
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "../launcher/windows_paths.hpp"
#endif
#include <cstdint>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <vector>
#include <map>
#include <set>
#include <string>

namespace palcraft_fluid_physics {
enum Action : uint32_t {Prepare=0,Commit=1,Unload=2,Abandon=3,Preflight=4};
struct Wire {
 char magic[8];
 uint64_t context,statics,actor_class,begin,finish,scene_class,box_class,
  add_component,finish_add_component,set_extent,set_collision,set_all_channels,
  set_channel,set_overlap,set_mobility,set_hidden,set_location,destroy_actor,process_event;
 double x,y,z;uint64_t revision,generation;
 uint32_t action,boxes,new_handles,old_handles;
};
struct Box {double minx,miny,minz,maxx,maxy,maxz;};
struct HandleHeader {uint64_t actor;uint32_t components,reserved;};
struct Handle {uint64_t actor=0;std::vector<uint64_t> components;};
struct Request {Wire wire{};std::vector<Box> boxes;std::vector<Handle> fresh,previous;};
struct Result {bool ok=false;const char* stage="request";Handle handle;uint64_t revision=0,generation=0;};
struct alignas(16) Transform {double rotation[4],translation[3],pad0,scale[3],pad1;};
struct alignas(16) Begin {uint64_t context,klass;Transform transform;uint8_t collision,pad[7];uint64_t owner,result,tail;};
struct alignas(16) Finish {uint64_t actor,pad;Transform transform;uint64_t result,tail;};
struct alignas(16) Add {uint64_t klass;uint8_t manual,pad[7];Transform relative;uint8_t deferred,pad2[7];uint64_t result;};
struct alignas(16) FinishAdd {uint64_t component;uint8_t manual,pad[7];Transform relative;};
struct Extent {double x,y,z;uint8_t update,pad[7];};
struct Location {double x,y,z;uint8_t sweep,pad[7],hit[0xe8],teleport,result,pad2[6];};
static_assert(sizeof(Wire)==216&&sizeof(Box)==48&&sizeof(HandleHeader)==16);
static_assert(sizeof(Transform)==96&&offsetof(Begin,result)==0x80&&offsetof(Finish,result)==0x70);
static_assert(offsetof(Add,result)==0x78&&sizeof(FinishAdd)==0x70&&sizeof(Extent)==32);
#if defined(_WIN32)
using Event=void(__fastcall*)(void*,void*,void*);
#else
using Event=void(*)(void*,void*,void*);
#endif
constexpr uint8_t water_channels[]={14,19,25};
constexpr uint32_t page_limit=512,handle_limit=128;
static bool pointer(uint64_t n){return n>=0x10000&&(n&7)==0;}
static bool coordinate(double n){return std::isfinite(n)&&std::abs(n)<=3e9;}
static bool read_handles(FILE*f,uint32_t count,std::vector<Handle>&out,const char*&error){
 uint32_t total=0;
 for(uint32_t i=0;i<count;i++){
  HandleHeader h{};
  if(fread(&h,1,sizeof h,f)!=sizeof h||!pointer(h.actor)||!h.components||h.components>page_limit||h.reserved){error="handle_header";return false;}
  total+=h.components;if(total>65536){error="handle_limit";return false;}
  Handle v;v.actor=h.actor;v.components.resize(h.components);
  if(fread(v.components.data(),sizeof(uint64_t),h.components,f)!=h.components){error="handle_body";return false;}
  for(auto p:v.components)if(!pointer(p)){error="handle_pointer";return false;}
  out.push_back(std::move(v));
 }
 return true;
}
static bool read_request(FILE*f,Request&r,const char*&error){
 auto&w=r.wire;
 if(fread(&w,1,sizeof w,f)!=sizeof w||memcmp(w.magic,"PALFLD01",8)||w.action>Preflight||!w.generation){error="request";return false;}
 if(w.boxes>page_limit||w.new_handles>handle_limit||w.old_handles>handle_limit){error="request_limit";return false;}
 if(!pointer(w.context)||!pointer(w.process_event)){error="request_pointer";return false;}
 if(w.action==Prepare){
  if(!w.boxes||w.new_handles||w.old_handles){error="prepare_counts";return false;}
  const uint64_t functions[]={w.statics,w.actor_class,w.begin,w.finish,w.scene_class,w.box_class,w.add_component,
   w.finish_add_component,w.set_extent,w.set_collision,w.set_all_channels,w.set_channel,w.set_overlap,
   w.set_mobility,w.set_hidden,w.set_location,w.destroy_actor};
  for(auto p:functions)if(!pointer(p)){error="prepare_pointer";return false;}
  if(!coordinate(w.x)||!coordinate(w.y)||!coordinate(w.z)){error="origin";return false;}
 }else if(w.boxes||(w.action==Unload&&w.new_handles)||(w.action==Abandon&&(w.new_handles||w.old_handles))){error="action_counts";return false;}
 if((w.action==Commit||w.action==Unload||w.action==Preflight)&&(!pointer(w.set_collision)||!pointer(w.destroy_actor))){error="commit_pointer";return false;}
 r.boxes.resize(w.boxes);
 if(fread(r.boxes.data(),sizeof(Box),w.boxes,f)!=w.boxes){error="box_body";return false;}
 for(const auto&b:r.boxes){
  const double coords[]={b.minx,b.miny,b.minz,b.maxx,b.maxy,b.maxz};
  for(auto n:coords)if(!coordinate(n)){error="box_finite";return false;}
  if(!(b.minx<b.maxx&&b.miny<b.maxy&&b.minz<b.maxz)){error="box_extent";return false;}
 }
 if(!read_handles(f,w.new_handles,r.fresh,error)||!read_handles(f,w.old_handles,r.previous,error))return false;
 std::set<uint64_t> actors,components;
 for(const auto*list:{&r.fresh,&r.previous})for(const auto&h:*list){
  if(!actors.insert(h.actor).second){error="duplicate_actor";return false;}
  for(auto p:h.components)if(!components.insert(p).second){error="duplicate_component";return false;}
 }
 if(fgetc(f)!=EOF){error="trailing_bytes";return false;}return true;
}
static Transform transform(double x=0,double y=0,double z=0){
 Transform t{};t.rotation[3]=1;t.scale[0]=t.scale[1]=t.scale[2]=1;
 t.translation[0]=x;t.translation[1]=y;t.translation[2]=z;return t;
}
class Runtime {
 uint64_t context=0,generation=0;
 struct Resource {Handle handle;bool active=false;uint64_t revision;};
 std::map<uint64_t,Resource> resources;
 bool registered(const Handle&h)const{
  auto i=resources.find(h.actor);return i!=resources.end()&&i->second.handle.components==h.components;
 }
public:
 size_t retained()const{return resources.size();}
 Result execute(const Request&r,Event call){
  const auto&w=r.wire;Result out;out.revision=w.revision;out.generation=w.generation;
  auto event=[&](uint64_t object,uint64_t fn,void*p){call((void*)object,(void*)fn,p);};
  if(w.action==Abandon){
   if(generation&&w.generation<=generation){out.stage="stale_abandon";return out;}
   // Calling owner has observed UE world loss: never dereference the old UObjects.
   resources.clear();context=w.context;generation=w.generation;out.ok=true;out.stage="abandoned";return out;
  }
  if(!generation){generation=w.generation;context=w.context;}
  if(generation!=w.generation||context!=w.context){out.stage="stale_context";return out;}
  if(w.action!=Prepare){
   for(const auto&h:r.fresh)if(!registered(h)||resources[h.actor].active||resources[h.actor].revision!=w.revision){out.stage="unknown_prepared_handle";return out;}
   for(const auto&h:r.previous)if(!registered(h)){out.stage="unknown_previous_handle";return out;}
   if(w.action==Preflight){out.ok=true;out.stage="preflight";return out;}
   uint8_t no=0,query_only=1;
   // One game-thread commit: no physics step between disabling old and enabling new.
   for(const auto&h:r.previous)for(auto c:h.components)event(c,w.set_collision,&no);
   for(const auto&h:r.fresh){for(auto c:h.components)event(c,w.set_collision,&query_only);resources[h.actor].active=true;}
   for(const auto&h:r.previous){event(h.actor,w.destroy_actor,nullptr);resources.erase(h.actor);}
   out.ok=true;out.stage=w.action==Unload?"unloaded":"committed";return out;
  }
  Begin begin{};begin.context=w.context;begin.klass=w.actor_class;begin.transform=transform(w.x,w.y,w.z);begin.collision=1;begin.owner=w.context;
  event(w.statics,w.begin,&begin);
  if(!begin.result){out.stage="spawn_null";return out;}out.handle.actor=begin.result;
  auto fail=[&](const char*s){event(out.handle.actor,w.destroy_actor,nullptr);out.handle={};out.stage=s;return out;};
  if(!pointer(begin.result))return fail("spawn_pointer");
  uint8_t no=0,yes=1,movable=2;
  event(begin.result,w.set_hidden,&yes);
  Add root{};root.klass=w.scene_class;root.relative=transform();root.deferred=1;
  event(begin.result,w.add_component,&root);if(!pointer(root.result))return fail("root_null");
  event(root.result,w.set_mobility,&movable);
  FinishAdd root_finish{};root_finish.component=root.result;root_finish.relative=root.relative;
  event(begin.result,w.finish_add_component,&root_finish);
  for(const auto&b:r.boxes){
   Add add{};add.klass=w.box_class;add.relative=transform((b.minx+b.maxx)*.5,(b.miny+b.maxy)*.5,(b.minz+b.maxz)*.5);add.deferred=1;
   event(begin.result,w.add_component,&add);if(!pointer(add.result))return fail("box_null");
   event(add.result,w.set_mobility,&movable);
   event(add.result,w.set_collision,&no);event(add.result,w.set_all_channels,&no);event(add.result,w.set_overlap,&no);
   for(auto channel:water_channels){uint8_t response[2]={channel,2};event(add.result,w.set_channel,response);}
   Extent extent{(b.maxx-b.minx)*.5,(b.maxy-b.miny)*.5,(b.maxz-b.minz)*.5,0,{}};
   event(add.result,w.set_extent,&extent);
   FinishAdd finished{};finished.component=add.result;finished.relative=add.relative;
   event(begin.result,w.finish_add_component,&finished);out.handle.components.push_back(add.result);
  }
  Finish finish{};finish.actor=begin.result;finish.transform=begin.transform;
  event(w.statics,w.finish,&finish);if(!pointer(finish.result)||finish.result!=begin.result)return fail("finish_actor");
  Location location{};location.x=w.x;location.y=w.y;location.z=w.z;location.teleport=1;
  event(begin.result,w.set_location,&location);
  resources.emplace(out.handle.actor,Resource{out.handle,false,w.revision});out.ok=true;out.stage="prepared";return out;
 }
};
static void write_result(FILE*f,const Result&r){
 std::fprintf(f,"{\"ok\":%s,\"stage\":\"%s\",\"version\":1,\"actor\":\"0x%llx\",\"revision\":%llu,\"generation\":%llu,\"collision\":1,\"damage\":false,\"components\":[",r.ok?"true":"false",r.stage,(unsigned long long)r.handle.actor,(unsigned long long)r.revision,(unsigned long long)r.generation);
 for(size_t i=0;i<r.handle.components.size();i++)std::fprintf(f,"%s\"0x%llx\"",i?",":"",(unsigned long long)r.handle.components[i]);
 std::fprintf(f,"]}");
}
} // namespace palcraft_fluid_physics
#if defined(_WIN32)
extern "C" __declspec(dllexport) int palcraft_fluid_physics_batch(void*){
 using namespace palcraft_fluid_physics;
 const auto root=palcraft_paths::io_root();
 if(root.empty())return 0;
 FILE*f=_wfopen((std::wstring(root)+L"fluid-physics-request.bin").c_str(),L"rb");if(!f)return 0;
 Request r;const char*error="request";bool valid=false;
 try{valid=read_request(f,r,error);}catch(...){error="allocation";}fclose(f);
 static DWORD thread=GetCurrentThreadId();static Runtime runtime;Result result;
 if(!valid)result.stage=error;
 else if(thread!=GetCurrentThreadId())result.stage="wrong_thread";
 else try{result=runtime.execute(r,(Event)r.wire.process_event);}catch(...){result.stage="execution_exception";}
 f=_wfopen((std::wstring(root)+L"fluid-physics-result.json").c_str(),L"wb");if(f){write_result(f,result);fclose(f);}return 0;
}
BOOL APIENTRY DllMain(HMODULE,DWORD,LPVOID){return TRUE;}
#endif
