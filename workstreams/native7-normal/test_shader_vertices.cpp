#define PALCRAFT_MODEL_TEST
#include "procedural_mesh_v7.cpp"
#include <cassert>
#include <iostream>

static int section_creates=0,section_updates=0;
static double expected_light_u=240;
static uint64_t material=1000,applied_material=0;
static void event(void*,void*fn,void*p){
 auto id=(uintptr_t)fn;
 if(id==13)((Begin*)p)->result=0x1111;
 else if(id==16)((Add*)p)->result=0x2222;
 else if(id==14)((Finish*)p)->result=0x1111;
 else if(id==17){
  auto&s=*(LinearSection*)p;
  assert(s.vertices.count==4&&s.uv1.count==4&&s.uv2.count==4&&s.colors.count==4);
  assert(s.uv3.count==0&&s.collision==0&&s.srgb==0);
  assert(((Vec3*)s.normals.data)[0].z==0);
  for(int i=0;i<s.tangents.count;i++)assert(finite(((Tangent*)s.tangents.data)[i].x));
  assert(((Vec2*)s.uv1.data)[0].v==10&&((Vec2*)s.uv2.data)[0].u==240);
  const auto&c=((LinearColor*)s.colors.data)[0];
  assert(std::abs(c.r-64.f/255)<1e-6&&std::abs(c.g-32.f/255)<1e-6&&std::abs(c.b-16.f/255)<1e-6&&std::abs(c.a-128.f/255)<1e-6);
  ++section_creates;
 }else if(id==18){
  struct Material{int32_t index,pad;uint64_t material;};
  applied_material=((Material*)p)->material;
 }else if(id==99){
  auto&s=*(LinearUpdateSection*)p;
  assert(s.uv1.count==4&&s.uv2.count==4&&s.colors.count==4&&s.srgb==0);
  assert(((Vec2*)s.uv2.data)[0].u==expected_light_u);
  ++section_updates;
 }
}
static Wire wire(){
 Wire w{};memcpy(w.magic,"PALCPRC7",8);
 for(size_t i=0;i<18;i++){uint64_t v=i+10;memcpy((char*)&w+8+i*8,&v,8);}
 w.sections=1;w.reserved=2;return w;
}
static ShaderVertex vertices[4]={
 {{{{0,0,0},{0,0,0},{0,0}},0x80402010,0},{0,10},{240,240}},
 {{{{100,0,0},{0,0,1},{1,0}},0xff112233,0},{15,10},{0,240}},
 {{{{100,100,0},{0,0,1},{1,1}},0x00335577,0},{15,3},{0,0}},
 {{{{0,100,0},{0,0,1},{0,1}},0xffffffff,0},{0,3},{240,0}}
};
static void body(FILE*f,bool shader=true){
 Header h{material,4,6};fwrite(&h,1,sizeof h,f);
 if(shader)fwrite(vertices,1,sizeof vertices,f);
 else for(auto&v:vertices)fwrite(&v.original,1,sizeof(ColoredVertex),f);
 int32_t indices[]={0,2,1,0,3,2};fwrite(indices,1,sizeof indices,f);
}
int main(){
 Wire w=wire();FILE*f=tmpfile();assert(f);fwrite(&w,1,sizeof w,f);body(f);rewind(f);
 Request request;const char*error=nullptr;assert(read_request(f,request,error));fclose(f);
 assert(request.shader_vertices&&request.groups[0].uv1[1].u==15&&request.groups[0].uv2[3].v==0);
 auto made=create_model(request,event);assert(made.ok&&section_creates==1&&applied_material==1000);
 UpdateWire update{};update.geometry=w;memcpy(update.geometry.magic,"PALCUPD7",8);
 update.actor=made.actor;update.component=made.component;update.native_id=made.native_id;update.update_section=99;
 vertices[0].light_uv.u=16;expected_light_u=16;material=2000;
 f=tmpfile();fwrite(&update,1,sizeof update,f);body(f);rewind(f);
 auto changed=update_model(f,event);fclose(f);assert(changed.ok&&changed.native_id==made.native_id&&section_updates==1&&section_creates==1&&applied_material==2000);
 vertices[0].overlay_uv.u=std::numeric_limits<double>::quiet_NaN();
 f=tmpfile();fwrite(&w,1,sizeof w,f);body(f);rewind(f);
 Request bad;assert(!read_request(f,bad,error)&&!strcmp(error,"shader_uv"));fclose(f);assert(section_creates==1);
 vertices[0].overlay_uv.u=0;
 vertices[0].original.vertex.normal={0,0,1}; // Valid legacy request isolates the layout guard.
 memcpy(update.geometry.magic,"PALCUPD1",8);
 f=tmpfile();fwrite(&update,1,sizeof update,f);body(f,false);rewind(f);
 auto wrong=update_model(f,event);fclose(f);assert(!wrong.ok&&!strcmp(wrong.stage,"update_vertex_layout")&&section_updates==1);
 ReleaseWire release{};memcpy(release.magic,"PALCREL1",8);release.context=w.context;release.action=2;
 assert(release_model(release,event).ok&&model_records.empty());
 std::cout<<"{\"ok\":true,\"directed_cases\":4,\"vertex_bytes\":104,\"create_parameter_bytes\":"<<sizeof(LinearSection)<<",\"update_parameter_bytes\":"<<sizeof(LinearUpdateSection)<<",\"original_uv1_uv2_and_rgba_reached_native_parameters\":true,\"wrong_uv_or_layout_rejected_before_calls\":true,\"engine_boundary\":\"simulated reflected calls\",\"actual_engine_called\":false}\n";
}
