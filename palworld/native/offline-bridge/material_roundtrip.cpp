// ISOLATED BridgeLab mutation experiment. Exactly consume ONE nondynamic Wood
// then compensate the SAME slot through the game's native transaction commit.
// No build, spawn, login, owner change, raw write, arbitrary function API or retry.
// The caller verifies Wood, a fresh Lab backup, and durable intent before arming.
#ifndef PAL_MATERIAL_IMPLEMENTATION_ALREADY_INCLUDED
#include "material_preview.cpp"
#endif
#include "roundtrip_fingerprint.hpp"
#ifdef PAL_PROBE_TEST
bool test_roundtrip_claim(const Guid&);
void test_roundtrip_apply(void*,const Array*,uint8_t);
#endif
static const wchar_t kRoundInput[]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\native-roundtrip.request.bin";
static const wchar_t kRoundPermit[]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\native-roundtrip.permit.bin";
static const wchar_t kRoundClaimed[]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\native-roundtrip.claimed.bin";
static const wchar_t kRoundTemp[]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\native-roundtrip.result.tmp";
static const wchar_t kRoundOutput[]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\native-roundtrip.result.json";
static bool claim(const Guid& nonce) {
#ifdef PAL_PROBE_TEST
    return test_roundtrip_claim(nonce);
#else
    HANDLE f=CreateFileW(kRoundPermit,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(f==INVALID_HANDLE_VALUE)return false;
    Guid permit{};DWORD got=0;LARGE_INTEGER size{};
    bool ok=GetFileSizeEx(f,&size)&&size.QuadPart==16&&ReadFile(f,&permit,16,&got,nullptr)&&got==16&&same(&permit,&nonce,16);
    CloseHandle(f);
    // No REPLACE flag: an existing claimed permit permanently blocks another call.
    return ok&&MoveFileExW(kRoundPermit,kRoundClaimed,MOVEFILE_WRITE_THROUGH);
#endif
}
struct Trial {
    Guid nonce{},container{};int32_t slot_index=0;SlotPayload original{};const char* stage="validating";const char* error=nullptr;
    int32_t before=0,intermediate=0,after=0;bool consumed=false,restored=false,ok=false;
    bool publish()const {
        Out o;o.text("{\"native_roundtrip_version\":1,\"lab_only\":true,\"read_only\":false,\"not_a_builder\":true,\"nonce\":\"");o.guid(nonce);
        o.text("\",\"stage\":\"");o.text(stage);o.text("\",\"consume_called\":");o.text(consumed?"true":"false");
        o.text(",\"restore_called\":");o.text(restored?"true":"false");o.text(",\"count_before\":");o.number(before<0?0:before);
        o.text(",\"count_after_consume\":");o.number(intermediate<0?0:intermediate);o.text(",\"count_after_restore\":");o.number(after<0?0:after);
        o.text(",\"container_id_hex\":\"");o.guid(container);o.text("\",\"slot_index\":");o.number(slot_index<0?0:slot_index);
        o.text(",\"original_payload_hex\":\"");for(unsigned i=0;i<sizeof original;++i)o.hex(((const unsigned char*)&original)[i],2);o.ch('"');
        o.text(",\"ok\":");o.text(ok?"true":"false");o.text(",\"complete_payload_restored\":");o.text(ok?"true":"false");
        o.text(",\"automatic_retry_allowed\":false");if(error){o.text(",\"error\":\"");o.text(error);o.ch('"');}o.ch('}');
        if(o.overflow)return false;
        HANDLE f=CreateFileW(kRoundTemp,GENERIC_WRITE,0,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
        if(f==INVALID_HANDLE_VALUE)return false;DWORD got=0;
        BOOL saved=WriteFile(f,o.data,o.length,&got,nullptr)&&got==o.length&&FlushFileBuffers(f);CloseHandle(f);
        return saved&&MoveFileExW(kRoundTemp,kRoundOutput,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
    }
};
static void apply_transaction(uint64_t image,void* manager,const Array& records,uint8_t operation) {
#ifdef PAL_PROBE_TEST
    test_roundtrip_apply(manager,&records,operation);
#else
    using Apply=void(__fastcall*)(void*,const Array*,uint8_t);
    ((Apply)(image+0x2e60400))(manager,&records,operation);
#endif
}
static void free_arrays(uint64_t image,Array& a,Array& b) {
#ifdef PAL_PROBE_TEST
    if(a.data)test_native_free(a.data);if(b.data)test_native_free(b.data);
#else
    using Free=void(__fastcall*)(void*);auto f=(Free)(image+0x32a0700);
    if(a.data)f(a.data);if(b.data)f(b.data);
#endif
}
extern "C" __declspec(dllexport) int pal_native_material_roundtrip_v1(void*) {
    if(!exe_matches())return 0;
    MaterialRequest r{};DWORD got=0;LARGE_INTEGER size{};
    HANDLE f=CreateFileW(kRoundInput,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(f==INVALID_HANDLE_VALUE)return 0;
    bool read_ok=GetFileSizeEx(f,&size)&&size.QuadPart==112&&ReadFile(f,&r,sizeof r,&got,nullptr);CloseHandle(f);
    Trial t;t.nonce=r.header.nonce;
    if(!read_ok||got!=112||!same(r.header.magic,"PLNRT001",8)||r.header.version!=1||r.header.count!=1||r.header.reserved)t.error="invalid_wire_request";
    if(!t.error&&(r.header.expires_unix<now()||r.header.expires_unix>now()+30))t.error="expired_request";
    if(!t.error&&r.header.thread_id!=GetCurrentThreadId())t.error="wrong_thread";
    uint64_t image=(uint64_t)GetModuleHandleW(nullptr);
    if(!t.error&&(!image_matches(image)||!code_matches(image,0x2e6c180,kPrepareCode,sizeof kPrepareCode)||
       !code_matches(image,0x2e6b7d0,kConsumePrepareCode,sizeof kConsumePrepareCode)||
       !code_matches(image,0x2e60400,kCommitCode,sizeof kCommitCode)||
       !code_matches(image,0x32a0700,kGameFreeCode,sizeof kGameFreeCode)))t.error="executable_fingerprint_mismatch";
    if(!t.error&&!valid_object(r.header.manager,r.header.manager_class))t.error="item_manager_mismatch";
    SlotPayload before{};if(!t.error)t.error=check_material_entry(r.entries[0],before);
    if(!t.error&&before.corruption!=0.0f)t.error="nonzero_corruption_rejected";
    if(t.error){t.publish();return 0;}
    t.before=before.count;t.original=before;t.container=r.entries[0].consume.id.container;t.slot_index=r.entries[0].consume.id.index;
    // Claim nonce before even preparing. Any later interruption requires manual review.
    if(!claim(t.nonce)){t.error="permit_missing_mismatched_or_already_claimed";t.publish();return 0;}
    t.stage="claimed_before_prepare";if(!t.publish())return 0;
    Array produce{},consumes{&r.entries[0].consume,1,1},results{},auxiliary{};
#ifdef PAL_PROBE_TEST
    auto status=test_native_prepare((void*)r.header.manager,&produce,&consumes,&results,&auxiliary);
#else
    using Prepare=uint8_t(__fastcall*)(void*,const Array*,const Array*,Array*,Array*);
    auto status=((Prepare)(image+0x2e6c180))((void*)r.header.manager,&produce,&consumes,&results,&auxiliary);
#endif
    PreparedRecord decrement{};SlotPayload current{};
    bool valid=status<2&&results.num==1&&results.max>=1&&results.max<=65536&&results.data&&
        read((uint64_t)results.data,&decrement,sizeof decrement)&&
        same(&decrement.source,&r.entries[0].consume.id,sizeof(SlotId))&&
        same(decrement.payload.item,before.item,40)&&decrement.payload.count==before.count-1&&
        same(&decrement.payload.corruption,&before.corruption,4)&&
        read(r.entries[0].slot+0x12c,&current,sizeof current)&&same(&current,&before,sizeof before);
    if(!valid){t.error="prepare_or_live_beforeimage_mismatch";t.publish();free_arrays(image,results,auxiliary);return 0;}
    t.stage="consume_intent";
    if(!t.publish()){free_arrays(image,results,auxiliary);return 0;}
    // EPalItemOperationType::Dispose=3; normal explicit-slot disposal caller uses it.
    t.consumed=true;apply_transaction(image,(void*)r.header.manager,results,3);
    bool observed=read(r.entries[0].slot+0x12c,&current,sizeof current);
    t.intermediate=observed?current.count:0;
    if(!observed||!same(&current,&decrement.payload,sizeof current)) {
        t.stage="consume_outcome_requires_review";t.error="unexpected_intermediate_payload_no_blind_restore";
        t.publish();free_arrays(image,results,auxiliary);return 0;
    }
    // Exact original beforeimage, same engine-prepared slot identifiers. No new ID.
    PreparedRecord refund=decrement;refund.payload=before;Array refunds{&refund,1,1};
    t.stage="restore_intent";bool audit_saved=t.publish();
    // Even if this second audit write fails, compensate the verified in-memory debit.
    t.restored=true;apply_transaction(image,(void*)r.header.manager,refunds,1);
    observed=read(r.entries[0].slot+0x12c,&current,sizeof current);t.after=observed?current.count:0;
    t.ok=observed&&same(&current,&before,sizeof before);t.stage=t.ok?"restored":"restore_outcome_requires_review";
    if(!t.ok)t.error="restore_did_not_recover_exact_original_payload";
    else if(!audit_saved)t.error="restored_but_intermediate_audit_write_failed";
    t.publish();free_arrays(image,results,auxiliary);return 0;
}
