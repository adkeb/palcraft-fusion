#define PAL_SKIP_MATERIAL_TEST_MAIN
#include "test_material.cpp"
#define PAL_MATERIAL_IMPLEMENTATION_ALREADY_INCLUDED
#include "material_roundtrip.cpp"
static bool permit=true;static unsigned claims=0,applies=0;static int apply_outcome=0;
bool test_roundtrip_claim(const Guid&g){assert(g.a==1&&g.b==2&&g.c==3&&g.d==4);++claims;if(!permit)return false;permit=false;return true;}
void test_roundtrip_apply(void*,const Array*a,uint8_t operation){
 ++applies;assert(a->num==1&&a->max>=1);assert(operation==(applies==1?3:1));
 PreparedRecord r{};if(!read((uint64_t)a->data,&r,sizeof r))std::memcpy(&r,a->data,sizeof r);
 assert(r.source.index==3&&r.source.container.a==0x12345678);
 if(apply_outcome==1&&applies==1)return;
 if(apply_outcome==2&&applies==2)return;
 if(apply_outcome==3&&applies==1)r.payload.count-=1;
 if(apply_outcome==4&&applies==2)r.payload.item[0]^=1;
 std::memcpy(regions[3].data.data()+0x12c,&r.payload,48);
}
static void rt_setup(){material_setup();permit=true;claims=applies=0;apply_outcome=0;std::memcpy(input.data(),"PLNRT001",8);
 regions.push_back({image_base+0x2e60400,std::vector<unsigned char>(kCommitCode,kCommitCode+sizeof kCommitCode)});}
static void rt_check(const char*expected,unsigned expected_calls){pal_native_material_roundtrip_v1(nullptr);assert(output.find(expected)!=std::string::npos);assert(applies==expected_calls);}
int main(){
 rt_setup();rt_check("\"ok\":true",2);assert(output.find("\"count_after_consume\":19")!=std::string::npos);assert(output.find("\"count_after_restore\":20")!=std::string::npos);
 rt_check("already_claimed",2);assert(claims==2);
 rt_setup();permit=false;rt_check("already_claimed",0);assert(prepares==0);
 rt_setup();apply_outcome=1;rt_check("unexpected_intermediate_payload",1);assert(output.find("\"restore_called\":false")!=std::string::npos);
 rt_setup();apply_outcome=2;rt_check("restore_did_not_recover",2);
 rt_setup();apply_outcome=3;rt_check("unexpected_intermediate_payload",1);
 rt_setup();apply_outcome=4;rt_check("restore_did_not_recover",2);
 rt_setup();outcome=1;rt_check("prepare_or_live_beforeimage_mismatch",0);
 rt_setup();thread_id++;rt_check("wrong_thread",0);assert(claims==0);
 rt_setup();regions.back().data[0]^=1;rt_check("executable_fingerprint_mismatch",0);assert(claims==0);
 rt_setup();put<float>(regions[3].data,0x158,0.5f);rt_check("nonzero_corruption_rejected",0);assert(claims==0);
 rt_setup();put<uint32_t>(regions[3].data,0x134,1);rt_check("dynamic_item_rejected",0);assert(claims==0);
 rt_setup();input.push_back(0);rt_check("invalid_wire_request",0);assert(claims==0);
 std::cout<<"13 native roundtrip/claim/compensation mock cases passed; live commit remains unverified\n";
}
