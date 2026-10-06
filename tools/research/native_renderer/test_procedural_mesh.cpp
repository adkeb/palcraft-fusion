#define PALCRAFT_MODEL_TEST
#include "../palcraft/native/procedural_mesh.cpp"
#include <cassert>
#include <string>
#include <iostream>

static int sections=0,materials=0,registered=0,engine_calls=0,destroyed=0;
static bool add_fails=false,finish_fails=false;static int hidden_before=-1;
static void fake_event(void*,void*function,void*args){
 ++engine_calls;
 switch((uintptr_t)function){
 case 13:((Begin*)args)->result=0x1111;break;
 case 14:assert(registered==1);((Finish*)args)->result=finish_fails?0:0x1111;break;
 case 16:{auto&a=*(Add*)args;assert(a.deferred==1&&a.manual==0);a.result=add_fails?0:0x2222;break;}
 case 17:{auto&s=*(Section*)args;assert(!registered&&!s.collision);assert(s.vertices.count==4&&s.triangles.count==6);assert(s.normals.count==4&&s.uv.count==4&&s.colors.count==4&&s.tangents.count==4);auto*t=(Tangent*)s.tangents.data;assert(std::abs(t[0].x.x-1)<1e-10&&!t[0].flip);++sections;break;}
 case 18:assert(!registered);++materials;break;
 case 20:assert(registered==1);break;
 case 21:assert(sections==materials&&sections>0);assert(((FinishAdd*)args)->component==0x2222);++registered;break;
 case 22:case 23:case 25:assert(*(uint8_t*)args==0&&!registered);break;
 case 24:assert(*(uint8_t*)args==2&&!registered);break;
 case 26:++destroyed;break;
 case 27:assert(!registered);hidden_before=*(uint8_t*)args;assert(hidden_before<=1);break;
 default:assert(false);
 }
}
static Wire header(){Wire w{};memcpy(w.magic,"PALCPRC4",8);for(size_t i=0;i<18;i++){uint64_t value=i+10;memcpy((char*)&w+8+i*8,&value,8);}w.sections=2;w.x=-308099.9;w.y=187800.8;w.z=3421.3;return w;}
static std::vector<unsigned char> fixture(){
 Wire w=header();std::vector<unsigned char> data;
 auto append=[&](const void*p,size_t n){auto*b=(const unsigned char*)p;data.insert(data.end(),b,b+n);};append(&w,sizeof w);
 Vertex v[4]={{{0,0,0},{0,0,1},{0,0}},{{100,0,0},{0,0,1},{1,0}},{{100,100,0},{0,0,1},{1,1}},{{0,100,0},{0,0,1},{0,1}}};int32_t indices[6]={0,2,1,0,3,2};
 for(int i=0;i<2;i++){Header h{uint64_t(1000+i),4,6};append(&h,sizeof h);append(v,sizeof v);append(indices,sizeof indices);}return data;
}
static bool read(const std::vector<unsigned char>&data,Request&r,std::string&stage){FILE*f=tmpfile();assert(f);fwrite(data.data(),1,data.size(),f);rewind(f);const char*error="none";bool ok=read_request(f,r,error);fclose(f);stage=error;return ok;}
static void reset(){sections=materials=registered=engine_calls=destroyed=0;add_fails=finish_fails=false;hidden_before=-1;}
int main(int argc,char**argv){
 int tests=0;std::string error;
 {Request r;assert(read(fixture(),r,error));assert(r.vertices==8&&r.indices==12);reset();auto result=create_model(r,fake_event);assert(result.ok&&result.actor==0x1111&&result.component==0x2222&&registered==1&&sections==2&&materials==2&&!destroyed&&hidden_before==0);++tests;}
 auto bad=[&](std::vector<unsigned char>d,const char*expected){Request r;reset();assert(!read(d,r,error)&&error==expected&&!engine_calls);++tests;};
 {Request r;auto d=fixture();uint32_t hidden=1;memcpy(d.data()+offsetof(Wire,reserved),&hidden,4);assert(read(d,r,error));reset();auto result=create_model(r,fake_event);assert(result.ok&&registered==1&&hidden_before==1);++tests;}
 {auto d=fixture();uint32_t invalid=2;memcpy(d.data()+offsetof(Wire,reserved),&invalid,4);bad(d,"request");}
 {auto d=fixture();d[0]='X';bad(d,"request");}
 {auto d=fixture();uint64_t zero=0;memcpy(d.data()+8+10*8,&zero,8);bad(d,"function_address");}
 {auto d=fixture();double nan=std::numeric_limits<double>::quiet_NaN();memcpy(d.data()+offsetof(Wire,x),&nan,8);bad(d,"location");}
 {auto d=fixture();uint32_t count=5;memcpy(d.data()+sizeof(Wire)+offsetof(Header,indices),&count,4);bad(d,"geometry_header");}
 {auto d=fixture();int32_t index=4;memcpy(d.data()+sizeof(Wire)+sizeof(Header)+4*sizeof(Vertex),&index,4);bad(d,"geometry_index");}
 {auto d=fixture();int32_t index=-1;memcpy(d.data()+sizeof(Wire)+sizeof(Header)+4*sizeof(Vertex),&index,4);bad(d,"geometry_index");}
 {auto d=fixture();double nan=std::numeric_limits<double>::quiet_NaN();memcpy(d.data()+sizeof(Wire)+sizeof(Header),&nan,8);bad(d,"geometry_vertex");}
 {auto d=fixture();Vec3 huge{1e308,0,0};memcpy(d.data()+sizeof(Wire)+sizeof(Header)+offsetof(Vertex,normal),&huge,sizeof huge);bad(d,"geometry_vertex");}
 {auto d=fixture();Vec3 zero{};memcpy(d.data()+sizeof(Wire)+sizeof(Header)+offsetof(Vertex,normal),&zero,sizeof zero);bad(d,"geometry_vertex");}
 {auto d=fixture();d.resize(d.size()-1);bad(d,"geometry_body");}
 {auto d=fixture();d.push_back(0);bad(d,"geometry_trailing_bytes");}
 {Request r;assert(read(fixture(),r,error));reset();add_fails=true;auto result=create_model(r,fake_event);assert(!result.ok&&!result.actor&&!result.component&&destroyed==1&&!registered);++tests;}
 {Request r;assert(read(fixture(),r,error));reset();finish_fails=true;auto result=create_model(r,fake_event);assert(!result.ok&&!result.actor&&!result.component&&destroyed==1&&registered==1);++tests;}
 if(argc>1){FILE*f=fopen(argv[1],"rb");assert(f);Request r;const char*why=nullptr;assert(read_request(f,r,why));fclose(f);assert(r.wire.x==200&&r.wire.y==0&&r.wire.z==300&&r.wire.reserved==1);reset();auto result=create_model(r,fake_event);assert(result.ok&&hidden_before==1&&registered==1&&sections==1);++tests;}
 std::cout<<"{\"ok\":true,\"tests\":"<<tests<<",\"abi_wire_bytes\":"<<sizeof(Wire)<<",\"deferred_registration\":true,\"visual_collision\":\"disabled_ignore_all\",\"invalid_geometry_before_engine_calls\":true,\"uv_tangents\":true}\n";
}
