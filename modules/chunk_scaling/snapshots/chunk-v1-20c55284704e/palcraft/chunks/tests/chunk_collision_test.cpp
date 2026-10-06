#include "../../native/chunk_collision.cpp"
#include <stdexcept>
#include <iostream>
using namespace palcraft_chunk_collision_impl;
static int checks=0;
static void check(bool yes,const char*message){++checks;if(!yes)throw std::runtime_error(message);}
static Request request(){
 Request r;auto&w=r.wire;memcpy(w.magic,"PALCCOL1",8);
 uint64_t*first=&w.context;for(int i=0;i<19;i++)first[i]=0x10000+(i+1)*0x100;
 w.x=120;w.y=-250;w.z=300;w.revision=7;w.generation=1;w.action=Prepare;w.boxes=2;
 r.boxes={{0,-100,0,100,0,100},{100,-100,0,200,0,50}};return r;
}
static void write(FILE*f,const Request&r){
 fwrite(&r.wire,1,sizeof r.wire,f);fwrite(r.boxes.data(),sizeof(Box),r.boxes.size(),f);
 for(const auto*list:{&r.fresh,&r.previous})for(const auto&h:*list){
  HandleHeader header{h.actor,uint32_t(h.components.size()),0};fwrite(&header,1,sizeof header,f);fwrite(h.components.data(),sizeof(uint64_t),h.components.size(),f);
 }
}
static bool parses(const Request&r,const char*expected=nullptr){
 FILE*f=tmpfile();write(f,r);rewind(f);Request parsed;const char*error="request";bool ok=read_request(f,parsed,error);fclose(f);
 if(expected)check(!ok&&std::string(error)==expected,expected);else check(ok,"Valid request");return ok;
}
struct Component {int collision=0;bool registered=false;bool overlaps=false;double x=0,y=0,z=0,ex=0,ey=0,ez=0;std::map<int,int> responses;};
static Wire active_wire;static uint64_t next_object=0x50000;static std::map<uint64_t,Component> comps;
static std::set<uint64_t> actors;static int adds=0,destroyed=0;static bool fail_box=false;
static void fake(void*object,void*function,void*args){
 uint64_t o=(uint64_t)object,f=(uint64_t)function;const auto&w=active_wire;
 if(f==w.begin){auto&a=*(Begin*)args;a.result=next_object+=0x100;actors.insert(a.result);}
 else if(f==w.add_component){auto&a=*(Add*)args;++adds;
  check(a.deferred==1,"Component is deferred");
  if(fail_box&&a.klass==w.box_class){a.result=0;return;}
  a.result=next_object+=0x100;comps[a.result]={};auto&c=comps[a.result];c.x=a.relative.translation[0];c.y=a.relative.translation[1];c.z=a.relative.translation[2];
 }
 else if(f==w.set_collision)comps[o].collision=*(uint8_t*)args;
 else if(f==w.set_overlap)comps[o].overlaps=*(uint8_t*)args;
 else if(f==w.set_all_channels){for(int i=0;i<32;i++)comps[o].responses[i]=*(uint8_t*)args;}
 else if(f==w.set_channel){auto*a=(uint8_t*)args;comps[o].responses[a[0]]=a[1];}
 else if(f==w.set_extent){auto&e=*(Extent*)args;check(!comps[o].registered,"Extent configured before registration");check(e.x>0&&e.y>0&&e.z>0,"Positive extents");comps[o].ex=e.x;comps[o].ey=e.y;comps[o].ez=e.z;}
 else if(f==w.finish_add_component){auto&a=*(FinishAdd*)args;auto&c=comps[a.component];check(c.collision==0&&!c.overlaps,"Prepare never enables collision/overlaps");c.registered=true;}
 else if(f==w.finish){auto&a=*(Finish*)args;a.result=a.actor;}
 else if(f==w.destroy_actor){++destroyed;actors.erase(o);}
}
int main(int argc,char**argv){try{
 auto valid=request();parses(valid);
 auto bad=valid;bad.wire.boxes=1025;parses(bad,"request_limit");
 bad=valid;bad.boxes[0].minx=std::nan("");parses(bad,"box_finite");
 bad=valid;bad.boxes[0].maxx=0;parses(bad,"box_extent");
 bad=valid;bad.wire.scene_class=0;parses(bad,"prepare_pointer");
 bad=valid;bad.wire.action=Unload;parses(bad,"action_counts");
 bad=valid;bad.wire.generation=0;parses(bad,"request");
 {FILE*f=tmpfile();write(f,valid);fputc(0,f);rewind(f);Request q;const char*e="";check(!read_request(f,q,e)&&std::string(e)=="trailing_bytes","Trailing data rejected");fclose(f);}
 active_wire=valid.wire;Runtime runtime;auto first=runtime.execute(valid,fake);
 check(first.ok&&first.handle.components.size()==2&&adds==3,"One actor, one root, two boxes");
 check(runtime.retained()==1,"Prepared handle retained");
 for(auto p:first.handle.components){const auto&c=comps[p];check(c.registered&&c.collision==0&&!c.overlaps,"No prepared physics");
  for(auto channel:block_channels)check(c.responses.at(channel)==2,"Physical channel blocks");
  for(auto channel:water_channels)check(c.responses.at(channel)==0,"Water channel ignores");
 }
 const auto&b=comps[first.handle.components[0]];check(b.x==50&&b.y==-50&&b.z==50&&b.ex==50,"Exact center/extents");
 Request tx;tx.wire=valid.wire;tx.wire.action=Preflight;tx.wire.boxes=0;tx.wire.new_handles=1;tx.fresh={first.handle};
 parses(tx);check(runtime.execute(tx,fake).ok,"Preflight no mutation");check(comps[first.handle.components[0]].collision==0,"Preflight leaves physics disabled");
 tx.wire.action=Commit;check(runtime.execute(tx,fake).ok,"Commit staged collider");check(comps[first.handle.components[0]].collision==3,"Commit enables physics");
 check(!runtime.execute(tx,fake).ok,"Cannot commit active handle again");
 auto second=runtime.execute(valid,fake);check(second.ok,"Prepare replacement");
 tx.fresh={second.handle};tx.previous={first.handle};tx.wire.old_handles=1;
 check(runtime.execute(tx,fake).ok&&runtime.retained()==1,"Replace releases old actor atomically");check(!actors.count(first.handle.actor),"Old actor destroyed");
 auto forged=tx;forged.fresh[0].actor=0x90000;int before=destroyed;
 check(!runtime.execute(forged,fake).ok&&destroyed==before,"Forged handle rejected before mutation");
 forged=tx;forged.previous=forged.fresh;parses(forged,"duplicate_actor");
 Request unload;unload.wire=valid.wire;unload.wire.action=Unload;unload.wire.boxes=0;unload.wire.old_handles=1;unload.previous={second.handle};
 check(runtime.execute(unload,fake).ok&&runtime.retained()==0,"Unload releases all native handles");
 fail_box=true;before=destroyed;auto failed=runtime.execute(valid,fake);fail_box=false;
 check(!failed.ok&&failed.handle.actor==0&&destroyed==before+1&&runtime.retained()==0,"Partial prepare cleans actor");
 auto third=runtime.execute(valid,fake);check(third.ok,"Prepare before travel");
 {FILE*f=tmpfile();write_result(f,third);check(ftell(f)>0,"Native result serialized");fclose(f);}
 Request abandon;abandon.wire=valid.wire;abandon.wire.action=Abandon;abandon.wire.boxes=0;abandon.wire.generation=2;
 before=destroyed;check(runtime.execute(abandon,fake).ok&&runtime.retained()==0&&destroyed==before,"Travel abandons stale handles without dereference");
 check(!runtime.execute(valid,fake).ok,"Stale generation rejected");
 if(argc>1){FILE*f=fopen(argv[1],"rb");check(f!=nullptr,"Lua fixture exists");Request from_lua;const char*error="";check(read_request(f,from_lua,error),"Lua/C++ wire agreement");fclose(f);check(from_lua.wire.x==120&&from_lua.boxes.size()==2,"Lua wire coordinates");}
 std::cout<<"{\"status\":\"passed\",\"checks\":"<<checks<<",\"wire_bytes\":"<<sizeof(Wire)<<",\"boxes_per_actor\":2,\"runtime_verified\":false}\n";
 return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<"\n";return 1;}}
