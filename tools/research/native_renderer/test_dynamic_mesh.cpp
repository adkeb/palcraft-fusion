#define PALCRAFT_MODEL_TEST
#include "../palcraft/native/procedural_mesh.cpp"
#include <cassert>
#include <iostream>
static int spawned=0,updated=0,destroyed=0;
static void event(void*,void*fn,void*p){
 auto id=(uintptr_t)fn;
 if(id==13){((Begin*)p)->result=0x1111;++spawned;}
 else if(id==16)((Add*)p)->result=0x2222;
 else if(id==14)((Finish*)p)->result=0x1111;
 else if(id==99){auto&s=*(UpdateSection*)p;assert(s.vertices.count==4&&s.normals.count==4&&s.uv.count==4&&s.tangents.count==4);assert(((Vec3*)s.vertices.data)[2].z==35);++updated;}
 else if(id==26)++destroyed;
}
static FILE* packet(Request&r,const Result&created,uint64_t token=0,bool wrong_topology=false){
 FILE*f=tmpfile();assert(f);UpdateWire w{r.wire,created.actor,created.component,token?token:created.native_id,99};memcpy(w.geometry.magic,"PALCUPD1",8);fwrite(&w,1,sizeof w,f);
 for(const auto&g:r.groups){Header h{g.material,uint32_t(g.positions.size()),uint32_t(g.indices.size())};fwrite(&h,1,sizeof h,f);
  for(size_t i=0;i<g.positions.size();i++){Vertex v{g.positions[i],g.normals[i],g.uv[i]};if(i==2)v.position.z=35;fwrite(&v,1,sizeof v,f);}
  auto indices=g.indices;if(wrong_topology)std::swap(indices[1],indices[2]);fwrite(indices.data(),4,indices.size(),f);
 }rewind(f);return f;
}
int main(){Request r;auto&w=r.wire;memcpy(w.magic,"PALCPRC4",8);for(size_t i=0;i<18;i++){uint64_t p=i+10;memcpy((char*)&w+8+i*8,&p,8);}w.sections=1;
 Geometry g;g.material=1000;g.positions={{0,0,0},{100,0,0},{100,100,0},{0,100,0}};g.normals.assign(4,{0,0,1});g.uv={{0,0},{1,0},{1,1},{0,1}};g.indices={0,2,1,0,3,2};g.colors.assign(4,0xffffffff);calculate_tangents(g);r.groups.push_back(g);
 Result created=create_model(r,event);assert(created.ok&&created.native_id&&spawned==1);
 FILE*f=packet(r,created);auto result=update_model(f,event);fclose(f);assert(result.ok&&result.actor==created.actor&&result.component==created.component&&updated==1&&spawned==1&&!destroyed);
 f=packet(r,created,created.native_id+1);result=update_model(f,event);fclose(f);assert(!result.ok&&std::strcmp(result.stage,"stale_model")==0&&updated==1);
 f=packet(r,created,0,true);result=update_model(f,event);fclose(f);assert(!result.ok&&std::strcmp(result.stage,"update_topology")==0&&updated==1);
 ReleaseWire release{};memcpy(release.magic,"PALCREL1",8);release.context=w.context;release.actor=created.actor;release.component=created.component;release.native_id=created.native_id;release.destroy=26;release.process_event=19;release.action=1;
 result=release_model(release,event);assert(result.ok&&destroyed==1&&model_records.empty());result=release_model(release,event);assert(!result.ok&&destroyed==1);
 created=create_model(r,event);release.action=2;result=release_model(release,event);assert(result.ok&&model_records.empty()&&destroyed==1);
 std::cout<<"{\"ok\":true,\"checks\":7,\"update_wire_bytes\":"<<sizeof(UpdateWire)<<",\"same_actor_component\":true,\"no_spawn_per_update\":true,\"stale_topology_rejected_before_update\":true,\"release_and_abandon_checked\":true}\n";
}
