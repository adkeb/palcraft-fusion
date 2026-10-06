// Verifies native water-query policy/transaction and independently decodes Lua wire.
// This test dispatches a fake ProcessEvent and cannot prove live UE physics.
#include "../../native/fluid_physics.cpp"
#include <stdexcept>
#include <iostream>
using namespace palcraft_fluid_physics;
static int checks=0;
static void check(bool b,const char*m){++checks;if(!b)throw std::runtime_error(m);}
struct Component {int collision=0;bool overlap=false;bool registered=false;std::map<int,int> responses;};
static Wire wire;static uint64_t next=0x50000;static std::map<uint64_t,Component> components;
static std::set<uint64_t> actors;static bool fail_box=false;static int calls=0;
static void event(void*object,void*function,void*args){
 ++calls;auto o=(uint64_t)object,f=(uint64_t)function;
 if(f==wire.begin){auto&a=*(Begin*)args;a.result=next+=0x100;actors.insert(a.result);}
 else if(f==wire.add_component){auto&a=*(Add*)args;
  check(a.deferred==1,"Water component creation is deferred");
  if(fail_box&&a.klass==wire.box_class){a.result=0;return;}
  a.result=next+=0x100;components[a.result]={};
 }
 else if(f==wire.set_collision)components[o].collision=*(uint8_t*)args;
 else if(f==wire.set_overlap)components[o].overlap=*(uint8_t*)args;
 else if(f==wire.set_all_channels)for(int i=0;i<32;i++)components[o].responses[i]=*(uint8_t*)args;
 else if(f==wire.set_channel){auto*a=(uint8_t*)args;components[o].responses[a[0]]=a[1];}
 else if(f==wire.finish_add_component){auto&a=*(FinishAdd*)args;
  check(components[a.component].collision==0&&!components[a.component].overlap,"Prepare does not enable water or overlap events");components[a.component].registered=true;
 }
 else if(f==wire.set_extent){auto&e=*(Extent*)args;check(e.x>0&&e.y>0&&e.z>0,"MC water extents stay positive");}
 else if(f==wire.finish){auto&a=*(Finish*)args;a.result=a.actor;}
 else if(f==wire.destroy_actor)actors.erase(o);
}
static void write(FILE*f,const Request&r){
 fwrite(&r.wire,1,sizeof r.wire,f);fwrite(r.boxes.data(),sizeof(Box),r.boxes.size(),f);
 for(auto*list:{&r.fresh,&r.previous})for(const auto&h:*list){HandleHeader hh{h.actor,(uint32_t)h.components.size(),0};fwrite(&hh,1,sizeof hh,f);fwrite(h.components.data(),sizeof(uint64_t),h.components.size(),f);}
}
static void parse_bad(const Request&r,const char*expect){
 FILE*f=tmpfile();write(f,r);rewind(f);Request parsed;const char*error="request";bool ok=read_request(f,parsed,error);fclose(f);
 check(!ok&&std::string(error)==expect,expect);
}
int main(int argc,char**argv){try{
 check(argc==2,"Lua-generated request path required");FILE*f=fopen(argv[1],"rb");check(f!=nullptr,"Lua wire exists");
 Request r;const char*error="request";bool parsed=read_request(f,r,error);fclose(f);check(parsed,"Independent C++ decoding accepts Lua request");
 check(r.wire.revision==9&&r.wire.generation==7&&r.boxes.size()==1,"Lua/C++ revision/count layout agrees");
 check(r.boxes[0].minx==0&&r.boxes[0].maxx==400&&r.boxes[0].miny==-400&&r.boxes[0].minz==6400,"Decoded pool bounds preserve MC to Pal axes");
 auto bad=r;memcpy(bad.wire.magic,"PALCCOL1",8);parse_bad(bad,"request");
 bad=r;bad.wire.boxes=513;parse_bad(bad,"request_limit");
 bad=r;bad.boxes[0].maxz=bad.boxes[0].minz;parse_bad(bad,"box_extent");
 bad=r;bad.boxes[0].minx=std::nan("");parse_bad(bad,"box_finite");
 Runtime runtime;wire=r.wire;auto prep=runtime.execute(r,event);check(prep.ok&&runtime.retained()==1,"True water preparation retains one page");
 auto c=components[prep.handle.components[0]];check(c.collision==0&&!c.overlap,"Prepared water is not active");
 for(int i=0;i<32;i++){int expected=(i==14||i==19||i==25)?2:0;check(c.responses[i]==expected,"Only genuine water-query channels block");}
 Request commit=r;commit.wire.action=Commit;commit.wire.boxes=0;commit.boxes.clear();commit.fresh={prep.handle};commit.wire.new_handles=1;
 auto result=runtime.execute(commit,event);check(result.ok&&components[prep.handle.components[0]].collision==1,"Commit enables QueryOnly rather than physical blocking");
 auto stale=commit;stale.wire.generation++;auto before=calls;check(!runtime.execute(stale,event).ok&&calls==before,"Stale world cannot invoke engine calls");
 fail_box=true;auto failed=runtime.execute(r,event);fail_box=false;
 check(!failed.ok&&actors.size()==1&&runtime.retained()==1,"Failed water preparation destroys its partial Actor and preserves committed water");
 Request unload=commit;unload.wire.action=Unload;unload.fresh.clear();unload.wire.new_handles=0;unload.previous={prep.handle};unload.wire.old_handles=1;
 result=runtime.execute(unload,event);check(result.ok&&actors.empty()&&runtime.retained()==0,"Unload destroys query Actor without leaving fake water");
 check(components[prep.handle.components[0]].collision==0,"Query body is disabled before destruction");
 std::cout<<"{\"ok\":true,\"suite\":\"fluid_native_wire_and_query_policy\",\"checks\":"<<checks<<",\"live_ue_physics_verified\":false,\"power_mode\":\"night_low_power\"}\n";
 return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<"\n";return 1;}}
