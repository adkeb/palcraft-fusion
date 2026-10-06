// UE5 game-thread bridge. A model becomes visible only after its complete
// geometry, materials and visual-only collision policy are ready.
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "windows_paths.hpp"
#elif !defined(PALCRAFT_MODEL_TEST)
#error Windows bridge; define PALCRAFT_MODEL_TEST for the portable contract test.
#endif
#include <cstdint>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <vector>
#include <algorithm>
#include <limits>
#include <unordered_map>

struct Wire {
 char magic[8];
 uint64_t context,statics,klass,begin,finish,component_class,add_component,
 create_section,set_material,process_event,set_location,finish_add_component,
 set_collision,set_collision_response,set_mobility,set_overlaps,destroy_actor,set_hidden;
 double x,y,z;uint32_t sections,reserved;
};
struct alignas(16) Transform {double rotation[4],translation[3],pad0,scale[3],pad1;};
struct alignas(16) Begin {uint64_t context,klass;Transform transform;uint8_t collision,pad[7];uint64_t owner,result,tail;};
struct alignas(16) Finish {uint64_t actor,pad;Transform transform;uint64_t result,tail;};
struct alignas(16) Add {uint64_t klass;uint8_t manual,pad[7];Transform relative;uint8_t deferred,pad2[7];uint64_t result;};
struct alignas(16) FinishAdd {uint64_t component;uint8_t manual,pad[7];Transform relative;};
struct Array {void* data;int32_t count,capacity;};
struct Section {int32_t index,pad;Array vertices,triangles,normals,uv,colors,tangents;uint8_t collision,pad2[7];};
struct Vec3 {double x,y,z;};struct Vec2 {double u,v;};
struct Vertex {Vec3 position,normal;Vec2 uv;};
struct ColoredVertex {Vertex vertex;uint32_t color,pad;};
static_assert(sizeof(ColoredVertex)==72);
struct Tangent {Vec3 x;uint8_t flip,pad[7];};
struct Header {uint64_t material;uint32_t vertices,indices;};
struct Geometry {uint64_t material;std::vector<Vec3> positions,normals;std::vector<Vec2> uv;std::vector<int32_t> indices;std::vector<uint32_t> colors;std::vector<Tangent> tangents;};
struct Request {Wire wire{};std::vector<Geometry> groups;uint32_t vertices=0,indices=0;};
struct Result {bool ok=false;uint64_t actor=0,component=0,native_id=0;const char*stage="request";};
static_assert(sizeof(Wire)==184&&sizeof(Vertex)==64&&sizeof(Tangent)==32);
static_assert(sizeof(Transform)==96&&offsetof(Begin,result)==0x80&&offsetof(Finish,result)==0x70);
static_assert(offsetof(Add,result)==0x78&&sizeof(FinishAdd)==0x70&&offsetof(Section,collision)==0x68);
#if defined(_WIN32)
using Event=void(__fastcall*)(void*,void*,void*);
#else
using Event=void(*)(void*,void*,void*);
#endif
static void output(const Result&r,const Request*request=nullptr){
#if defined(_WIN32)
 FILE*f=_wfopen(palcraft_paths::bridge_file(L"model-result.json").c_str(),L"wb");
 if(f){std::fprintf(f,"{\"ok\":%s,\"actor\":\"0x%llx\",\"component\":\"0x%llx\",\"stage\":\"%s\",\"version\":6,\"native_id\":%llu,\"sections\":%u,\"vertices\":%u,\"indices\":%u}",r.ok?"true":"false",(unsigned long long)r.actor,(unsigned long long)r.component,r.stage,(unsigned long long)r.native_id,request?unsigned(request->groups.size()):0,request?request->vertices:0,request?request->indices:0);std::fclose(f);}
#else
 (void)r;(void)request;
#endif
}
template<class T> static Array arr(std::vector<T>&v){return{v.empty()?nullptr:v.data(),int32_t(v.size()),int32_t(v.size())};}
static Vec3 add(Vec3 a,Vec3 b){return{a.x+b.x,a.y+b.y,a.z+b.z};}
static Vec3 subtract(Vec3 a,Vec3 b){return{a.x-b.x,a.y-b.y,a.z-b.z};}
static Vec3 multiply(Vec3 a,double b){return{a.x*b,a.y*b,a.z*b};}
static double dot(Vec3 a,Vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
static Vec3 cross(Vec3 a,Vec3 b){return{a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
static Vec3 unit(Vec3 a){return multiply(a,1/std::sqrt(dot(a,a)));}
static bool finite(Vec3 a){return std::isfinite(a.x)&&std::isfinite(a.y)&&std::isfinite(a.z);}
static void calculate_tangents(Geometry&g){
 std::vector<Vec3> tx(g.positions.size()),ty(g.positions.size());
 for(size_t k=0;k<g.indices.size();k+=3){
  int a=g.indices[k],b=g.indices[k+1],c=g.indices[k+2];
  Vec3 ab=subtract(g.positions[b],g.positions[a]),ac=subtract(g.positions[c],g.positions[a]);
  double u1=g.uv[b].u-g.uv[a].u,v1=g.uv[b].v-g.uv[a].v,u2=g.uv[c].u-g.uv[a].u,v2=g.uv[c].v-g.uv[a].v;
  double det=u1*v2-u2*v1;if(std::abs(det)<1e-12)continue;
  Vec3 x=multiply(subtract(multiply(ab,v2),multiply(ac,v1)),1/det);
  Vec3 y=multiply(subtract(multiply(ac,u1),multiply(ab,u2)),1/det);
  for(int i:{a,b,c}){tx[i]=add(tx[i],x);ty[i]=add(ty[i],y);}
 }
 g.tangents.resize(g.positions.size());
 for(size_t i=0;i<g.positions.size();i++){
  Vec3 n=g.normals[i],x=subtract(tx[i],multiply(n,dot(n,tx[i])));
  if(dot(x,x)<1e-12)x=cross(std::abs(n.z)<.9?Vec3{0,0,1}:Vec3{0,1,0},n);
  x=unit(x);g.tangents[i].x=x;g.tangents[i].flip=dot(cross(n,x),ty[i])<0;
 }
}
// Read and validate everything before allocating an Unreal actor. In particular,
// an invalid index must never reach the render-thread section proxy.
static bool read_request(FILE*f,Request&r,const char*&error,bool header_loaded=false){
 auto fail=[&](const char*s){error=s;return false;};
 Wire&w=r.wire;
 if((!header_loaded&&fread(&w,1,sizeof w,f)!=sizeof w)||(memcmp(w.magic,"PALCPRC4",8)&&memcmp(w.magic,"PALCPRC6",8))||!w.sections||w.sections>256||(w.reserved&~3u))return fail("request");
 for(size_t i=0;i<18;i++){uint64_t pointer;std::memcpy(&pointer,(const char*)&w+8+i*8,8);if(!pointer)return fail("function_address");}
 if(!std::isfinite(w.x)||!std::isfinite(w.y)||!std::isfinite(w.z))return fail("location");
 for(uint32_t section=0;section<w.sections;section++){
  Header h{};
  if(fread(&h,1,sizeof h,f)!=sizeof h||!h.material||h.vertices<3||h.vertices>65536||!h.indices||h.indices>262144||h.indices%3)return fail("geometry_header");
  if(r.vertices+h.vertices>1000000||r.indices+h.indices>3000000)return fail("geometry_limit");
  Geometry g{};g.material=h.material;std::vector<Vertex> input(h.vertices);g.indices.resize(h.indices);
  g.colors.assign(h.vertices,0xffffffffu);
  if(w.reserved&2u){std::vector<ColoredVertex> colored(h.vertices);if(fread(colored.data(),sizeof(ColoredVertex),h.vertices,f)!=h.vertices)return fail("geometry_body");for(size_t i=0;i<h.vertices;i++){input[i]=colored[i].vertex;g.colors[i]=colored[i].color;}}
  else if(fread(input.data(),sizeof(Vertex),h.vertices,f)!=h.vertices)return fail("geometry_body");
  if(fread(g.indices.data(),sizeof(int32_t),h.indices,f)!=h.indices)return fail("geometry_body");
  for(auto index:g.indices)if(index<0||uint32_t(index)>=h.vertices)return fail("geometry_index");
  g.positions.reserve(h.vertices);g.normals.reserve(h.vertices);g.uv.reserve(h.vertices);
  for(const auto&v:input){
   const double normal_squared=dot(v.normal,v.normal);
   if(!finite(v.position)||!finite(v.normal)||!std::isfinite(normal_squared)||normal_squared<1e-12||
      std::abs(v.position.x)>1e8||std::abs(v.position.y)>1e8||std::abs(v.position.z)>1e8||
      !std::isfinite(v.uv.u)||!std::isfinite(v.uv.v)||std::abs(v.uv.u)>1e6||std::abs(v.uv.v)>1e6)return fail("geometry_vertex");
   g.positions.push_back(v.position);g.normals.push_back(unit(v.normal));g.uv.push_back(v.uv);
  }
  calculate_tangents(g);
  r.vertices+=h.vertices;r.indices+=h.indices;r.groups.push_back(std::move(g));
 }
 if(fgetc(f)!=EOF)return fail("geometry_trailing_bytes");
 return true;
}
struct ModelRecord {uint64_t context,component,id;std::vector<uint32_t> vertices;std::vector<std::vector<int32_t>> indices;};
static std::unordered_map<uint64_t,ModelRecord> model_records;
static uint64_t model_serial=0;
struct UpdateWire {Wire geometry;uint64_t actor,component,native_id,update_section;};
struct UpdateSection {int32_t index,pad;Array vertices,normals,uv,colors,tangents;};
static_assert(sizeof(UpdateWire)==216&&sizeof(UpdateSection)==0x58&&offsetof(UpdateSection,tangents)==0x48);
static Result update_model(FILE*f,Event call){
 Result result;UpdateWire wire{};
 auto fail=[&](const char*s){result.stage=s;return result;};
 if(fread(&wire,1,sizeof wire,f)!=sizeof wire||memcmp(wire.geometry.magic,"PALCUPD1",8)||!wire.update_section)return fail("update_request");
 auto found=model_records.find(wire.actor);
 if(found==model_records.end()||found->second.id!=wire.native_id||found->second.context!=wire.geometry.context||found->second.component!=wire.component)return fail("stale_model");
 Request request;request.wire=wire.geometry;memcpy(request.wire.magic,"PALCPRC4",8);const char*error="update_geometry";
 if(!read_request(f,request,error,true))return fail(error);
 const auto&record=found->second;
 if(request.groups.size()!=record.vertices.size())return fail("update_topology");
 for(size_t i=0;i<request.groups.size();i++)if(request.groups[i].positions.size()!=record.vertices[i]||request.groups[i].indices!=record.indices[i])return fail("update_topology");
 // Complete validation precedes every render-thread update command. Topology,
 // materials, component registration and physics remain unchanged.
 for(size_t i=0;i<request.groups.size();i++){
  auto&g=request.groups[i];UpdateSection section{};section.index=int32_t(i);section.vertices=arr(g.positions);section.normals=arr(g.normals);section.uv=arr(g.uv);section.colors=arr(g.colors);section.tangents=arr(g.tangents);
  call((void*)wire.component,(void*)wire.update_section,&section);
 }
 result.actor=wire.actor;result.component=wire.component;result.native_id=wire.native_id;result.ok=true;result.stage="updated";return result;
}
struct ReleaseWire {char magic[8];uint64_t context,actor,component,native_id,destroy,process_event;uint32_t action,reserved;};
static_assert(sizeof(ReleaseWire)==64);
static Result release_model(const ReleaseWire&w,Event call){
 Result r;r.stage="release_request";
 if(memcmp(w.magic,"PALCREL1",8)||w.reserved||w.action>2)return r;
 if(w.action==2){for(auto i=model_records.begin();i!=model_records.end();){if(i->second.context==w.context)i=model_records.erase(i);else ++i;}r.ok=true;r.stage="abandoned";return r;}
 auto i=model_records.find(w.actor);
 if(i==model_records.end()||i->second.context!=w.context||i->second.component!=w.component||i->second.id!=w.native_id){r.stage="stale_model";return r;}
 if(w.action==1){if(!w.destroy||!w.process_event){r.stage="release_functions";return r;}call((void*)w.actor,(void*)w.destroy,nullptr);}
 model_records.erase(i);r.ok=true;r.stage=w.action==1?"destroyed":"released";return r;
}
static Result create_model(Request&r,Event call){
 const Wire&w=r.wire;Result result;
 auto stage=[&](const char*s){result.stage=s;output(result,&r);};
 Transform t{};t.rotation[3]=1;t.scale[0]=t.scale[1]=t.scale[2]=1;t.translation[0]=w.x;t.translation[1]=w.y;t.translation[2]=w.z;
 Begin b{};b.context=w.context;b.klass=w.klass;b.transform=t;b.collision=1;b.owner=w.context;
 stage("spawn");call((void*)w.statics,(void*)w.begin,&b);
 if(!b.result){stage("spawn_null");return result;}result.actor=b.result;
 uint8_t hidden=(w.reserved&1u)?1:0;
 stage("actor_visibility_before_registration");call((void*)b.result,(void*)w.set_hidden,&hidden);
 auto fail=[&](const char*s){call((void*)result.actor,(void*)w.destroy_actor,nullptr);result.actor=result.component=0;stage(s);return result;};
 Add a{};a.klass=w.component_class;a.relative.rotation[3]=1;a.relative.scale[0]=a.relative.scale[1]=a.relative.scale[2]=1;a.deferred=1;
 stage("add_deferred_component");call((void*)b.result,(void*)w.add_component,&a);
 if(!a.result)return fail("component_null");result.component=a.result;
 uint8_t no=0,movable=2;
 stage("visual_component_policy");
 call((void*)a.result,(void*)w.set_mobility,&movable);
 call((void*)a.result,(void*)w.set_collision,&no);
 call((void*)a.result,(void*)w.set_collision_response,&no);
 call((void*)a.result,(void*)w.set_overlaps,&no);
 for(size_t i=0;i<r.groups.size();i++){
  auto&g=r.groups[i];Section s{};s.index=int32_t(i);s.vertices=arr(g.positions);s.triangles=arr(g.indices);s.normals=arr(g.normals);s.uv=arr(g.uv);s.colors=arr(g.colors);s.tangents=arr(g.tangents);
  stage("unregistered_mesh_section");call((void*)a.result,(void*)w.create_section,&s);
  struct Material{int32_t index,pad;uint64_t material;}m{int32_t(i),0,g.material};
  stage("unregistered_material");call((void*)a.result,(void*)w.set_material,&m);
 }
 FinishAdd add{};add.component=a.result;add.relative=a.relative;
 stage("register_complete_component");call((void*)b.result,(void*)w.finish_add_component,&add);
 Finish finish{};finish.actor=b.result;finish.transform=t;
 stage("finish");call((void*)w.statics,(void*)w.finish,&finish);
 if(!finish.result)return fail("finish_null");result.actor=finish.result;
 // A bare Actor gains its root during FinishAddComponent, after BeginDeferred.
 struct Location{Vec3 position;uint8_t sweep,pad[7],hit[0xe8],teleport,result,pad2[6];}location{};
 location.position={w.x,w.y,w.z};location.teleport=1;
 stage("location");call((void*)finish.result,(void*)w.set_location,&location);
 ModelRecord record{w.context,a.result,++model_serial,{},{}};
 for(const auto&g:r.groups){record.vertices.push_back(uint32_t(g.positions.size()));record.indices.push_back(g.indices);}
 result.native_id=record.id;model_records[result.actor]=std::move(record);
 result.ok=true;stage("created");return result;
}
#if defined(_WIN32)
static bool allowed_executable(){return palcraft_paths::executable_role()==palcraft_paths::Role::client;}
static bool game_thread(){static DWORD owner=GetCurrentThreadId();return owner==GetCurrentThreadId();}
extern "C" __declspec(dllexport) int palcraft_update_model(void*){
 if(!allowed_executable()||!game_thread())return 0;
 FILE*f=_wfopen(palcraft_paths::bridge_file(L"model-update-request.bin").c_str(),L"rb");if(!f)return 0;
 Wire header{};uint64_t event=0;
 if(fread(&header,1,sizeof header,f)==sizeof header)event=header.process_event;rewind(f);
 Result r;
 try{r=event?update_model(f,(Event)event):Result{};}catch(...){r.stage="update_allocation";}
 fclose(f);output(r);return 0;
}
extern "C" __declspec(dllexport) int palcraft_release_model(void*){
 if(!allowed_executable()||!game_thread())return 0;
 FILE*f=_wfopen(palcraft_paths::bridge_file(L"model-release-request.bin").c_str(),L"rb");if(!f)return 0;
 ReleaseWire w{};bool ok=fread(&w,1,sizeof w,f)==sizeof w;fclose(f);
 Result r;if(ok)r=release_model(w,(Event)w.process_event);output(r);return 0;
}
extern "C" __declspec(dllexport) int palcraft_create_model(void*){
 if(!allowed_executable())return 0;
 FILE*f=_wfopen(palcraft_paths::bridge_file(L"model-request.bin").c_str(),L"rb");if(!f)return 0;
 Request r;const char*error="request";bool ok=false;
 try{ok=read_request(f,r,error);}catch(...){error="request_allocation";}
 fclose(f);
 if(!ok){Result result;result.stage=error;output(result);return 0;}
 // UE4SS's ExecuteInGameThread is the only caller. Refuse calls from another
 // thread after the first invocation; never enqueue raw UObject addresses.
 if(!game_thread()){Result result;result.stage="wrong_thread";output(result);return 0;}
 create_model(r,(Event)r.wire.process_event);return 0;
}
BOOL APIENTRY DllMain(HMODULE,DWORD,LPVOID){return TRUE;}
#endif
