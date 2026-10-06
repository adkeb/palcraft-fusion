#define main account_probe_main
#include "test_readonly.cpp"
#undef main
#define PAL_READONLY_IMPLEMENTATION_ALREADY_INCLUDED
#include "material_preview.cpp"
static unsigned prepares=0,frees=0;static int outcome=0;
uint8_t test_native_prepare(void*,const void* pv,const void* cv,void* rv,void* av){
 ++prepares;auto&p=*(const Array*)pv;auto&c=*(const Array*)cv;auto&r=*(Array*)rv;auto&a=*(Array*)av;
 assert(p.num==0&&!p.data&&c.num==1&&c.max==1&&a.num==0&&r.num==0);
 auto*consume=(Consume*)c.data;assert(consume->num==1);
 if(outcome==1)return 20;
 PreparedRecord pr{};std::memcpy(&pr.payload,regions[3].data.data()+0x12c,48);pr.payload.count-=outcome==2?2:1;
 pr.source=consume->id;pr.target.index=-1;
 Region out{0x800000,std::vector<unsigned char>(sizeof pr)};put(out.data,0,pr);regions.push_back(out);
 r.data=(void*)out.address;r.num=1;r.max=1;
 if(outcome==3)put<int32_t>(regions[3].data,0x154,19);
 return 0;
}
void test_native_free(void*){++frees;}
static void material_setup(){
 setup();prepares=frees=0;outcome=0;
 regions.push_back({image_base+0x2e6c180,std::vector<unsigned char>(kPrepareCode,kPrepareCode+sizeof kPrepareCode)});
 regions.push_back({image_base+0x2e6b7d0,std::vector<unsigned char>(kConsumePrepareCode,kConsumePrepareCode+sizeof kConsumePrepareCode)});
 regions.push_back({image_base+0x32a0700,std::vector<unsigned char>(kGameFreeCode,kGameFreeCode+sizeof kGameFreeCode)});
 auto&s=regions[3].data;s.assign(0x200,0);put<uint64_t>(s,0,0x100100);put<uint64_t>(s,0x10,0x500100);
 Guid id{0x12345678,9,10,11};put<int32_t>(s,0x118,3);put<Guid>(s,0x11c,id);put<uint32_t>(s,0x12c,0x1234);put<int32_t>(s,0x154,20);
 std::memcpy(input.data(),"PLNMV001",8);
 MaterialEntry e{0x500000,0x500100,{id,3,1},20,0};put(input,64,e);
}
static void material_check(const char*expected,unsigned n,unsigned freed){pal_native_material_preview_v1(nullptr);assert(output.find(expected)!=std::string::npos);assert(prepares==n&&frees==freed);}

#ifndef PAL_SKIP_MATERIAL_TEST_MAIN
int main(){
 material_setup();material_check("\"ok\":true",1,1);assert(output.find("\"planned_count_after\":19")!=std::string::npos);
 material_setup();outcome=1;material_check("native_prepared_record_mismatch",1,0);
 material_setup();outcome=2;material_check("native_prepared_record_mismatch",1,1);
 material_setup();outcome=3;material_check("unexpected_live_change",1,1);
 material_setup();thread_id++;material_check("wrong_thread",0,0);
 material_setup();put<int32_t>(input,100,2);material_check("invalid_material_request",0,0);
 material_setup();put<int32_t>(input,104,1);material_check("invalid_material_request",0,0);
 material_setup();put<uint32_t>(regions[3].data,0x134,1);material_check("dynamic_item_rejected",0,0);
 material_setup();put<int32_t>(regions[3].data,0x154,19);material_check("slot_count_mismatch",0,0);
 material_setup();put<int32_t>(regions[3].data,0x118,4);material_check("slot_id_mismatch",0,0);
 material_setup();regions[6].data[0]^=1;material_check("executable_fingerprint_mismatch",0,0);
 material_setup();input.push_back(0);material_check("invalid_wire_request",0,0);
 std::cout<<"12 native material preview checks passed; live game semantics remain unverified\n";
}

#endif
