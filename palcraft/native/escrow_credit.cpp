// BridgeLab v1.0.5 only. Produce ordinary converted material into ONE real,
// empty escrow slot after a saved MC-debit permit. No backpack staging, raw
// inventory write, container creation, replay or function-address argument.
#include "credit_abi_support.hpp"
#include "credit_fingerprints.hpp"
struct SlotId {Guid container;int32_t index;};
struct Array {void* data;int32_t num,max;};
struct SlotPayload {unsigned char item[40];int32_t count;float corruption;};
struct Produce {SlotPayload payload;SlotId target,from;};
struct CreditBody {
 uint64_t slot,slot_class,descriptor,descriptor_class;SlotId id;int32_t count;
 Guid tx;uint64_t generation;unsigned char fingerprint[32],mc_receipt_sha256[32];
};
struct CreditRequest {Header header;CreditBody body;};
struct Permit {
 Guid nonce,tx,container;int32_t slot,count;uint64_t generation;
 unsigned char fingerprint[32],mc_receipt_sha256[32];
};
static_assert(sizeof(SlotId)==20&&sizeof(SlotPayload)==48&&sizeof(Produce)==88&&sizeof(CreditBody)==144&&sizeof(CreditRequest)==208&&sizeof(Permit)==128,"Credit ABI changed");
static const wchar_t kCreditInput[]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\escrow-credit.request.bin";
static const wchar_t kCreditTemp[]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\escrow-credit.result.tmp";
static const wchar_t kCreditResult[]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\escrow-credit.result.json";
#ifdef PAL_PROBE_TEST
bool test_credit_claim(const Permit&);
uint8_t test_credit_prepare(void*,const Array*,const Array*,Array*,Array*);
void test_credit_apply(void*,const Array*,uint8_t);
void test_credit_free(void*);
#endif
static bool code_matches(uint64_t base,uint32_t rva,const unsigned char* expected,unsigned n) {
 unsigned char b[2048];return n<=sizeof b&&read(base+rva,b,n)&&same(b,expected,n);
}
static bool nonzero(const unsigned char* p,unsigned n){for(unsigned i=0;i<n;++i)if(p[i])return true;return false;}
static Permit permit_for(const CreditRequest&r) {
 Permit p{};p.nonce=r.header.nonce;p.tx=r.body.tx;p.container=r.body.id.container;
 p.slot=r.body.id.index;p.count=r.body.count;p.generation=r.body.generation;
 for(unsigned i=0;i<32;++i){p.fingerprint[i]=r.body.fingerprint[i];p.mc_receipt_sha256[i]=r.body.mc_receipt_sha256[i];}
 return p;
}
static bool claim(const Permit& expected) {
#ifdef PAL_PROBE_TEST
 return test_credit_claim(expected);
#else
 wchar_t base[240]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\escrow-credit-";unsigned length=0;while(base[length])++length;
 const wchar_t hex[]=L"0123456789abcdef";const uint32_t words[]={expected.nonce.a,expected.nonce.b,expected.nonce.c,expected.nonce.d};
 for(unsigned i=0;i<4;++i)for(unsigned j=8;j;--j)base[length++]=hex[(words[i]>>((j-1)*4))&15];
 wchar_t input[280],claimed[280];for(unsigned i=0;i<length;++i)input[i]=claimed[i]=base[i];
 const wchar_t in_suffix[]=L".permit.bin",out_suffix[]=L".claimed.bin";
 for(unsigned i=0;i<sizeof in_suffix/sizeof(wchar_t);++i)input[length+i]=in_suffix[i];
 for(unsigned i=0;i<sizeof out_suffix/sizeof(wchar_t);++i)claimed[length+i]=out_suffix[i];
 HANDLE f=CreateFileW(input,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(f==INVALID_HANDLE_VALUE)return false;
 Permit actual{};DWORD got=0;LARGE_INTEGER size{};
 bool ok=GetFileSizeEx(f,&size)&&size.QuadPart==sizeof actual&&ReadFile(f,&actual,sizeof actual,&got,nullptr)&&got==sizeof actual&&same(&actual,&expected,sizeof actual);
 CloseHandle(f);return ok&&MoveFileExW(input,claimed,MOVEFILE_WRITE_THROUGH); // no REPLACE
#endif
}
static bool publish(const CreditRequest&r,const char*stage,const char*error,bool attempted,bool observed,uint8_t status) {
 Out o;o.text("{\"native_escrow_credit_version\":1,\"lab_only\":true,\"nonce\":\"");o.guid(r.header.nonce);
 o.text("\",\"tx_hex\":\"");o.guid(r.body.tx);o.text("\",\"stage\":\"");o.text(stage);
 o.text("\",\"attempted\":");o.text(attempted?"true":"false");o.text(",\"observed\":");o.text(observed?"true":"false");
 o.text(",\"ok\":");o.text(observed&&!error?"true":"false");o.text(",\"native_status\":");o.number(status);
 o.text(",\"automatic_retry_allowed\":false");if(error){o.text(",\"error\":\"");o.text(error);o.ch('"');}o.ch('}');
 if(o.overflow)return false;
 HANDLE f=CreateFileW(kCreditTemp,GENERIC_WRITE,0,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);if(f==INVALID_HANDLE_VALUE)return false;
 DWORD got=0;bool ok=WriteFile(f,o.data,o.length,&got,nullptr)&&got==o.length&&FlushFileBuffers(f);CloseHandle(f);
 return ok&&MoveFileExW(kCreditTemp,kCreditResult,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}
static void free_arrays(uint64_t base,Array&a,Array&b) {
#ifdef PAL_PROBE_TEST
 if(a.data)test_credit_free(a.data);if(b.data)test_credit_free(b.data);
#else
 using Free=void(__fastcall*)(void*);auto f=(Free)(base+0x32a0700);if(a.data)f(a.data);if(b.data)f(b.data);
#endif
}
extern "C" __declspec(dllexport) int palcraft_escrow_credit_v1(void*) {
 if(!exe_matches())return 0;
 CreditRequest r{};DWORD got=0;LARGE_INTEGER size{};
 HANDLE f=CreateFileW(kCreditInput,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);if(f==INVALID_HANDLE_VALUE)return 0;
 bool ok=GetFileSizeEx(f,&size)&&size.QuadPart==sizeof r&&ReadFile(f,&r,sizeof r,&got,nullptr)&&got==sizeof r;CloseHandle(f);
 const char* error=nullptr;
 if(!ok||!same(r.header.magic,"PLESCR01",8)||r.header.version!=1||r.header.count!=1||r.header.reserved)error="invalid_credit_wire";
 if(!error&&(r.header.expires_unix<now()||r.header.expires_unix>now()+30))error="expired_request";
 if(!error&&r.header.thread_id!=GetCurrentThreadId())error="wrong_game_thread";
 uint64_t base=(uint64_t)GetModuleHandleW(nullptr);
 if(!error&&(!image_matches(base)||!code_matches(base,0x2e6c180,kPrepareCode,sizeof kPrepareCode)||
  !code_matches(base,0x2e60400,kCommitCode,sizeof kCommitCode)||!code_matches(base,0x32a0700,kGameFreeCode,sizeof kGameFreeCode)))error="game_fingerprint_mismatch";
 if(!error&&!valid_object(r.header.manager,r.header.manager_class))error="manager_object_mismatch";
 if(!error&&(r.body.count<1||r.body.count>64||r.body.id.index<0||r.body.id.index>=1000||r.body.generation<1||
  !nonzero(r.body.fingerprint,32)||!nonzero(r.body.mc_receipt_sha256,32)))error="unbound_conversion_request";
 SlotPayload before{},descriptor{};SlotId actual_id{};
 if(!error&&(!valid_object(r.body.slot,r.body.slot_class)||!read(r.body.slot+0x118,&actual_id,sizeof actual_id)||
  !same(&actual_id,&r.body.id,sizeof actual_id)))error="escrow_slot_id_mismatch";
 if(!error&&(!read(r.body.slot+0x12c,&before,sizeof before)||before.count!=0))error="escrow_not_empty";
 if(!error&&(!valid_object(r.body.descriptor,r.body.descriptor_class)||!read(r.body.descriptor+0x12c,&descriptor,sizeof descriptor)||
  descriptor.count!=r.body.count||descriptor.corruption!=0||nonzero(descriptor.item+8,32)||!nonzero(descriptor.item,8)))error="invalid_ordinary_item_descriptor";
 if(error){publish(r,"refused",error,false,false,255);return 0;}
 if(!claim(permit_for(r))){publish(r,"refused","saved_mc_debit_permit_missing_mismatched_or_claimed",false,false,255);return 0;}
 if(!publish(r,"claimed_before_prepare",nullptr,false,false,255))return 0;
 Produce product{};product.payload=descriptor;product.target=r.body.id;product.from.index=-1;
 Array products{&product,1,1},consumes{},results{},auxiliary{};
#ifdef PAL_PROBE_TEST
 auto status=test_credit_prepare((void*)r.header.manager,&products,&consumes,&results,&auxiliary);
#else
 using Prepare=uint8_t(__fastcall*)(void*,const Array*,const Array*,Array*,Array*);
 auto status=((Prepare)(base+0x2e6c180))((void*)r.header.manager,&products,&consumes,&results,&auxiliary);
#endif
 Produce prepared{};SlotPayload unchanged{};
 // This explicit produce preparation path is a Lab candidate. Do not install
 // until the live returned record's slot convention is validated, then retain
 // the exact same bound/empty/item checks. Never submit a mismatched record.
 bool valid=status<2&&results.num==1&&results.max>=1&&results.max<=65536&&results.data&&
  read((uint64_t)results.data,&prepared,sizeof prepared)&&same(&prepared.payload,&descriptor,sizeof descriptor)&&
  same(&prepared.target,&r.body.id,sizeof r.body.id)&&prepared.from.index==-1&&
  read(r.body.slot+0x12c,&unchanged,sizeof unchanged)&&same(&before,&unchanged,sizeof before);
 if(!valid){publish(r,"prepared_refused","prepare_or_beforeimage_mismatch",false,false,status);free_arrays(base,results,auxiliary);return 0;}
 if(!publish(r,"commit_intent",nullptr,true,false,status)){free_arrays(base,results,auxiliary);return 0;}
#ifdef PAL_PROBE_TEST
 test_credit_apply((void*)r.header.manager,&results,1);
#else
 using Apply=void(__fastcall*)(void*,const Array*,uint8_t);((Apply)(base+0x2e60400))((void*)r.header.manager,&results,1);
#endif
 SlotPayload after{};bool observed=read(r.body.slot+0x12c,&after,sizeof after)&&same(&after,&descriptor,sizeof after);
 publish(r,observed?"credited":"requires_recovery",observed?nullptr:"credit_afterimage_mismatch",true,observed,status);
 free_arrays(base,results,auxiliary);return 0;
}
