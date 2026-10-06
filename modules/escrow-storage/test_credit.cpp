#define PAL_PROBE_TEST
#include "escrow_credit.cpp"
#include <cassert>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>
struct Region {uint64_t address;std::vector<unsigned char> data;};
static std::vector<Region> regions;
static std::vector<unsigned char> input;
static std::string output;
static uint64_t image_base=0x10000000,current_time=2000000000;
static uint32_t thread_id=1234;
static unsigned prepares=0,applies=0,claims=0,frees=0;
static bool permitted=true;
static int outcome=0;
HANDLE GetCurrentProcess(){return (HANDLE)1;}
BOOL ReadProcessMemory(HANDLE,const void*p,void*out,SIZE_T n,SIZE_T*done){
 for(auto&r:regions){auto a=(uint64_t)p;if(a>=r.address&&a+n>=a&&a+n<=r.address+r.data.size()){
  std::memcpy(out,r.data.data()+a-r.address,n);*done=n;return 1;}}
 *done=0;return 0;
}
void GetSystemTimeAsFileTime(FILETIME*f){auto t=(current_time+11644473600ULL)*10000000ULL;f->dwLowDateTime=(DWORD)t;f->dwHighDateTime=(DWORD)(t>>32);}
DWORD GetModuleFileNameW(void*,wchar_t*p,DWORD n){assert(n>sizeof kExe/sizeof(wchar_t));std::memcpy(p,kExe,sizeof kExe);return sizeof kExe/sizeof(wchar_t)-1;}
HANDLE GetModuleHandleW(void*){return (HANDLE)image_base;}
DWORD GetCurrentThreadId(){return thread_id;}
HANDLE CreateFileW(const wchar_t*,DWORD access,DWORD,void*,DWORD,DWORD,void*){return (HANDLE)(uintptr_t)(access==GENERIC_READ?1:2);}
BOOL ReadFile(HANDLE,void*p,DWORD n,DWORD*got,void*){*got=(DWORD)(input.size()<n?input.size():n);std::memcpy(p,input.data(),*got);return 1;}
BOOL GetFileSizeEx(HANDLE,LARGE_INTEGER*s){s->QuadPart=input.size();return 1;}
BOOL WriteFile(HANDLE,const void*p,DWORD n,DWORD*w,void*){output.assign((const char*)p,n);*w=n;return 1;}
BOOL FlushFileBuffers(HANDLE){return 1;}
BOOL CloseHandle(HANDLE){return 1;}
BOOL MoveFileExW(const wchar_t*,const wchar_t*,DWORD){return 1;}
bool test_credit_claim(const Permit&p){++claims;assert(p.count==16&&p.generation==2&&p.nonce.a==1);if(!permitted)return false;permitted=false;return true;}
uint8_t test_credit_prepare(void*,const Array*p,const Array*c,Array*r,Array*a){
 ++prepares;assert(p->num==1&&p->max==1&&c->num==0&&!c->data&&r->num==0&&a->num==0);
 if(outcome==1)return 20;
 Produce value=*(Produce*)p->data;
 if(outcome==2)value.target.index=4;
 if(outcome==3)value.payload.count=17;
 if(outcome==4)value.from.index=0;
 if(outcome==5)value.payload.item[8]=1;
 Region result{0x900000,std::vector<unsigned char>(sizeof value)};std::memcpy(result.data.data(),&value,sizeof value);regions.push_back(result);
 r->data=(void*)result.address;r->num=1;r->max=1;
 if(outcome==6)std::memcpy(regions[3].data.data()+0x12c,&value.payload,sizeof value.payload);
 return 0;
}
void test_credit_apply(void*,const Array*r,uint8_t kind){
 ++applies;assert(kind==1&&r->num==1);
 if(outcome==7)return;
 Produce p{};assert(read((uint64_t)r->data,&p,sizeof p));
 if(outcome==8)p.payload.count=32;
 std::memcpy(regions[3].data.data()+0x12c,&p.payload,sizeof p.payload);
}
void test_credit_free(void*){++frees;}
template<class T>static void put(std::vector<unsigned char>&v,unsigned off,T x){assert(off+sizeof x<=v.size());std::memcpy(v.data()+off,&x,sizeof x);}
static void setup(){
 regions.clear();input.clear();output.clear();thread_id=1234;prepares=applies=claims=frees=0;permitted=true;outcome=0;
 Region pe{image_base,std::vector<unsigned char>(4096)};put<uint16_t>(pe.data,0,0x5a4d);put<uint32_t>(pe.data,0x3c,0x100);put<uint32_t>(pe.data,0x100,0x4550);
 put<uint16_t>(pe.data,0x104,0x8664);put<uint32_t>(pe.data,0x108,0x6aa38b38);put<uint32_t>(pe.data,0x150,0x9731000);regions.push_back(pe);
 regions.push_back({image_base+0x3034120,std::vector<unsigned char>(kLookupCode,kLookupCode+sizeof kLookupCode)});
 Region manager{0x400000,std::vector<unsigned char>(0x200)};put<uint64_t>(manager.data,0,0x100100);put<uint64_t>(manager.data,0x10,0x400100);regions.push_back(manager);
 Guid cid{0x2c2fc605,0x4f72bb9b,0x81f4569d,0xc8842626};SlotId id{cid,0};
 Region slot{0x500000,std::vector<unsigned char>(0x200)};put<uint64_t>(slot.data,0,0x100100);put<uint64_t>(slot.data,0x10,0x500100);put(slot.data,0x118,id);regions.push_back(slot);
 Region descriptor{0x600000,std::vector<unsigned char>(0x200)};put<uint64_t>(descriptor.data,0,0x100100);put<uint64_t>(descriptor.data,0x10,0x500100);
 SlotPayload item{};item.item[0]=0x12;item.item[1]=0x34;item.count=16;put(descriptor.data,0x12c,item);regions.push_back(descriptor);
 regions.push_back({image_base+0x2e6c180,std::vector<unsigned char>(kPrepareCode,kPrepareCode+sizeof kPrepareCode)});
 regions.push_back({image_base+0x2e60400,std::vector<unsigned char>(kCommitCode,kCommitCode+sizeof kCommitCode)});
 regions.push_back({image_base+0x32a0700,std::vector<unsigned char>(kGameFreeCode,kGameFreeCode+sizeof kGameFreeCode)});
 CreditRequest r{};std::memcpy(r.header.magic,"PLESCR01",8);r.header.version=1;r.header.count=1;r.header.thread_id=1234;r.header.expires_unix=current_time+15;
 r.header.manager=0x400000;r.header.manager_class=0x400100;r.header.nonce={1,2,3,4};
 r.body.slot=0x500000;r.body.slot_class=0x500100;r.body.descriptor=0x600000;r.body.descriptor_class=0x500100;r.body.id=id;r.body.count=16;
 r.body.tx={5,6,7,8};r.body.generation=2;r.body.fingerprint[0]=0x11;r.body.mc_receipt_sha256[0]=0x22;
 input.resize(sizeof r);put(input,0,r);
}
static unsigned passed=0;
static void check(const char*needle,unsigned expected_calls){palcraft_escrow_credit_v1(nullptr);if(output.find(needle)==std::string::npos)std::cerr<<"case "<<passed+1<<" expected "<<needle<<" actual "<<output<<"\n";assert(output.find(needle)!=std::string::npos);assert(applies==expected_calls);++passed;}
int main(){
 setup();check("\"ok\":true",1);assert(prepares==1&&frees==1);
 check("escrow_not_empty",1);assert(prepares==1);
 put<int32_t>(regions[3].data,0x154,0);check("or_claimed",1);assert(prepares==1);
 setup();permitted=false;check("or_claimed",0);assert(prepares==0);
 setup();thread_id=1235;check("wrong_game_thread",0);assert(claims==0);
 setup();put<uint64_t>(input,24,current_time-1);check("expired_request",0);
 setup();put<uint64_t>(input,24,current_time+31);check("expired_request",0);
 setup();input.resize(207);check("invalid_credit_wire",0);
 setup();input.push_back(0);check("invalid_credit_wire",0);
 setup();put<int32_t>(input,116,65);check("unbound_conversion_request",0);
 setup();put<uint64_t>(input,136,0);check("unbound_conversion_request",0);
 setup();put<int32_t>(regions[3].data,0x154,1);check("escrow_not_empty",0);assert(claims==0);
 setup();put<int32_t>(regions[3].data,0x118,1);check("escrow_slot_id_mismatch",0);
 setup();put<uint32_t>(regions[4].data,0x134,1);check("invalid_ordinary_item_descriptor",0);
 setup();put<int32_t>(regions[4].data,0x154,15);check("invalid_ordinary_item_descriptor",0);
 setup();regions[6].data[0]^=1;check("game_fingerprint_mismatch",0);
 for(int n=1;n<=6;++n){setup();outcome=n;check("prepare_or_beforeimage_mismatch",0);assert(prepares==1);}
 setup();outcome=7;check("credit_afterimage_mismatch",1);assert(output.find("\"observed\":false")!=std::string::npos);
 setup();outcome=8;check("credit_afterimage_mismatch",1);
 std::cout<<"RESULT native_credit_cases="<<passed<<" runtime_verified=false power_mode=night_low_power\n";
}
