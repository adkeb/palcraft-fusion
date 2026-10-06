// No submit/apply function exists in this DLL. Preparing native transaction
// records is separate from 0x02E60400, which this source NEVER calls.
#ifndef PAL_READONLY_IMPLEMENTATION_ALREADY_INCLUDED
#include "readonly_probe.cpp"
#endif
#ifdef PAL_PROBE_TEST
uint8_t test_native_prepare(void*,const void*,const void*,void*,void*);
void test_native_free(void*);
#endif
#include "material_fingerprints.hpp"
static const wchar_t kMaterialInput[]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\native-material.request.bin";
static const wchar_t kMaterialTemp[]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\native-material.result.tmp";
static const wchar_t kMaterialOutput[]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\native-material.result.json";
struct SlotId {Guid container;int32_t index;};
struct Consume {SlotId id;int32_t num;};
struct MaterialEntry {uint64_t slot,slot_class;Consume consume;int32_t expected_count;uint32_t reserved;};
struct Array {void* data;int32_t num,max;};
struct SlotPayload {unsigned char item[40];int32_t count;float corruption;};
struct PreparedRecord {SlotPayload payload;SlotId source,target;};
struct MaterialRequest {Header header;MaterialEntry entries[8];};
static_assert(sizeof(SlotId)==20&&sizeof(Consume)==24&&sizeof(MaterialEntry)==48&&sizeof(Array)==16&&sizeof(SlotPayload)==48&&sizeof(PreparedRecord)==88,"native layouts changed");
static bool code_matches(uint64_t image,uint32_t rva,const unsigned char* bytes,unsigned n) {
    unsigned char b[2048];return n<=sizeof b&&read(image+rva,b,n)&&same(bytes,b,n);
}
static void material_commit(Out& o) {
    if(o.overflow)return;
    HANDLE f=CreateFileW(kMaterialTemp,GENERIC_WRITE,0,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(f==INVALID_HANDLE_VALUE)return;
    DWORD written=0;BOOL ok=WriteFile(f,o.data,o.length,&written,nullptr);
    if(ok)ok=FlushFileBuffers(f);CloseHandle(f);
    if(ok&&written==o.length)MoveFileExW(kMaterialTemp,kMaterialOutput,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}
static const char* check_material_entry(const MaterialEntry& e,SlotPayload& before) {
    if(e.reserved||e.consume.num!=1||e.expected_count<2||e.consume.id.index<0||e.consume.id.index>4095)return "invalid_material_request";
    if(!valid_object(e.slot,e.slot_class))return "slot_object_mismatch";
    int32_t index=0;Guid container{};
    if(!value(e.slot+0x118,index)||index!=e.consume.id.index||!value(e.slot+0x11c,container)||!same(&container,&e.consume.id.container,16))return "slot_id_mismatch";
    if(!read(e.slot+0x12c,&before,sizeof before)||before.count!=e.expected_count)return "slot_count_mismatch";
    unsigned char empty[32]{};
    if(!same(before.item+8,empty,32))return "dynamic_item_rejected";
    return nullptr;
}
extern "C" __declspec(dllexport) int pal_native_material_preview_v1(void*) {
    if(!exe_matches())return 0;
    MaterialRequest r{};DWORD got=0;
    HANDLE f=CreateFileW(kMaterialInput,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(f==INVALID_HANDLE_VALUE)return 0;
    LARGE_INTEGER size{};BOOL size_ok=GetFileSizeEx(f,&size);
    BOOL read_ok=ReadFile(f,&r,sizeof r,&got,nullptr);CloseHandle(f);
    Out o;o.text("{\"read_only\":true,\"not_a_builder\":true,\"submit_called\":false,\"native_material_preview_version\":1,\"nonce\":\"");o.guid(r.header.nonce);o.ch('"');
    const char* error=nullptr;
    if(!size_ok||size.QuadPart!=112||!read_ok||got<64||!same(r.header.magic,"PLNMV001",8)||r.header.version!=1||r.header.reserved||r.header.count!=1||got!=112)error="invalid_wire_request";
    if(!error&&(r.header.expires_unix<now()||r.header.expires_unix>now()+30))error="expired_request";
    if(!error&&r.header.thread_id!=GetCurrentThreadId())error="wrong_thread";
    uint64_t image=(uint64_t)GetModuleHandleW(nullptr);
    if(!error&&(!image_matches(image)||!code_matches(image,0x2e6c180,kPrepareCode,sizeof kPrepareCode)||
       !code_matches(image,0x2e6b7d0,kConsumePrepareCode,sizeof kConsumePrepareCode)||
       !code_matches(image,0x32a0700,kGameFreeCode,sizeof kGameFreeCode)))error="executable_fingerprint_mismatch";
    if(!error&&!valid_object(r.header.manager,r.header.manager_class))error="item_manager_mismatch";
    SlotPayload before{};
    if(!error)error=check_material_entry(r.entries[0],before);
    if(error){o.text(",\"ok\":false,\"error\":\"");o.text(error);o.text("\"}");material_commit(o);return 0;}
    Array produce{},consumes{&r.entries[0].consume,1,1},results{},auxiliary{};
    // ABI derived from matched manager-move call site 0x02E66A22. Native helper
    // reads live slots and produces local record arrays; caller commits separately.
#ifdef PAL_PROBE_TEST
    auto status=test_native_prepare((void*)r.header.manager,&produce,&consumes,&results,&auxiliary);
#else
    using Prepare=uint8_t(__fastcall*)(void*,const Array*,const Array*,Array*,Array*);
    auto status=((Prepare)(image+0x2e6c180))((void*)r.header.manager,&produce,&consumes,&results,&auxiliary);
#endif
    o.text(",\"native_status\":");o.number(status);
    bool valid=status<2&&results.num==1&&results.max>=results.num&&results.max<=65536&&results.data;
    PreparedRecord after{};if(valid)valid=read((uint64_t)results.data,&after,sizeof after);
    if(valid)valid=same(&after.source,&r.entries[0].consume.id,sizeof(SlotId))&&
        same(after.payload.item,before.item,40)&&after.payload.count==before.count-1&&
        same(&after.payload.corruption,&before.corruption,4);
    SlotPayload live_after{};
    bool unchanged=read(r.entries[0].slot+0x12c,&live_after,sizeof live_after)&&same(&live_after,&before,sizeof before);
    o.text(",\"live_slot_unchanged\":");o.text(unchanged?"true":"false");
    o.text(",\"prepared_count\":");o.number(results.num<0?0:(uint32_t)results.num);
    if(valid){o.text(",\"count_before\":");o.number(before.count);o.text(",\"planned_count_after\":");o.number(after.payload.count);}
    // Returned arrays were allocated by the game, so only its FMemory::Free may free them.
#ifdef PAL_PROBE_TEST
    if(results.data)test_native_free(results.data);if(auxiliary.data)test_native_free(auxiliary.data);
#else
    using Free=void(__fastcall*)(void*);
    auto game_free=(Free)(image+0x32a0700);
    if(results.data)game_free(results.data);if(auxiliary.data)game_free(auxiliary.data);
#endif
    o.text(",\"ok\":");o.text(valid&&unchanged?"true":"false");
    if(!valid||!unchanged){o.text(",\"error\":\"");o.text(!unchanged?"unexpected_live_change":"native_prepared_record_mismatch");o.ch('"');}
    o.ch('}');material_commit(o);return 0;
}
