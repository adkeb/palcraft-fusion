// BridgeLab-only, read-only native ABI probe. No Lua or UE4SS C++ ABI dependency.
// Lua calls this fixed C export through package.loadlib on the game thread.
// This module NEVER calls construction, material consumption, spawning or login.
#define WIN32_LEAN_AND_MEAN
#ifdef PAL_PROBE_TEST
#include "test_win32.hpp"
#else
#include <windows.h>
#endif
#include <stdint.h>

static const wchar_t kExe[] = L"D:\\PalworldServer-LAN\\BridgeLab\\Pal\\Binaries\\Win64\\PalServer-Win64-Shipping-Cmd.exe";
static const wchar_t kInput[] = L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\native-readonly.request.bin";
static const wchar_t kTemp[] = L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\native-readonly.result.tmp";
static const wchar_t kOutput[] = L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\native-readonly.result.json";
static const unsigned char kLookupCode[] = {
    0x40,0x53,0x48,0x83,0xec,0x20,0x48,0x8d,0x99,0xc0,0,0,0,0x4c,0x8b,0xc2,
    0x48,0x8b,0xcb,0x48,0x8d,0x54,0x24,0x30,0xe8,0xd3,0x16,0x96,0xfe,0x48,0x63,
    0x44,0x24,0x30,0x83,0xf8,0xff,0x74,0x1f,0x48,0xc1,0xe0,0x05,0x33,0xd2,
    0x48,0x03,0x03,0x48,0x8d,0x40,0x10,0x48,0x0f,0x44,0xc2,0x48,0x85,0xc0,
    0x74,0x09,0x48,0x8b,0,0x48,0x83,0xc4,0x20,0x5b,0xc3,0x33,0xc0,0x48,0x83,
    0xc4,0x20,0x5b,0xc3
};
struct Guid { uint32_t a,b,c,d; };
struct Header {
    char magic[8]; uint32_t version,count,thread_id,reserved;
    uint64_t expires_unix,manager,manager_class; Guid nonce;
};
struct Entry { uint64_t account,account_class,technology,inventory; Guid uid; };
struct Request { Header header; Entry entries[16]; };
static_assert(sizeof(Header)==64 && sizeof(Entry)==48, "Wire layout changed");
static bool same(const void* a,const void* b,unsigned n) {
    auto x=(const unsigned char*)a;auto y=(const unsigned char*)b;
    for(unsigned i=0;i<n;++i) if(x[i]!=y[i]) return false;
    return true;
}
static bool read(uint64_t address,void* output,SIZE_T size) {
    SIZE_T got=0;
    return address>0x10000 && ReadProcessMemory(GetCurrentProcess(),(const void*)address,output,size,&got) && got==size;
}
template<class T> static bool value(uint64_t address,T& out) { return read(address,&out,sizeof out); }
static uint64_t now() {
    FILETIME f;GetSystemTimeAsFileTime(&f);
    return (((uint64_t)f.dwHighDateTime<<32)|f.dwLowDateTime)/10000000ULL-11644473600ULL;
}
static bool exe_matches() {
    wchar_t path[512];DWORD n=GetModuleFileNameW(nullptr,path,512);
    if(!n || n>=512) return false;
    unsigned i=0;
    for(;kExe[i];++i) {
        auto a=path[i],b=kExe[i];
        if(a>=L'A'&&a<=L'Z')a+=32;if(b>=L'A'&&b<=L'Z')b+=32;
        if(a!=b)return false;
    }
    return path[i]==0;
}
static bool image_matches(uint64_t base) {
    uint16_t mz=0,machine=0;uint32_t offset=0,pe=0,stamp=0,size=0;
    if(!value(base,mz)||mz!=0x5a4d||!value(base+0x3c,offset)||offset>0x1000)return false;
    if(!value(base+offset,pe)||pe!=0x4550||!value(base+offset+4,machine)||machine!=0x8664)return false;
    if(!value(base+offset+8,stamp)||stamp!=0x6aa38b38||!value(base+offset+24+56,size)||size!=0x9731000)return false;
    unsigned char bytes[sizeof kLookupCode];
    return read(base+0x03034120,bytes,sizeof bytes)&&same(bytes,kLookupCode,sizeof bytes);
}
struct Out {
    char data[8192]; unsigned length=0; bool overflow=false;
    void ch(char c) { if(length<sizeof data)data[length++]=c;else overflow=true; }
    void text(const char* p) { while(*p)ch(*p++); }
    void hex(uint64_t n,unsigned digits) {
        const char* h="0123456789abcdef";
        for(unsigned i=digits;i;--i)ch(h[(n>>((i-1)*4))&15]);
    }
    void number(uint32_t n) {
        char b[10];unsigned i=0;do{b[i++]=(char)('0'+n%10);n/=10;}while(n);
        while(i)ch(b[--i]);
    }
    void guid(Guid g) { hex(g.a,8);hex(g.b,8);hex(g.c,8);hex(g.d,8); }
    void commit() {
        if(overflow)return;
        HANDLE f=CreateFileW(kTemp,GENERIC_WRITE,0,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
        if(f==INVALID_HANDLE_VALUE)return;
        DWORD written=0;BOOL ok=WriteFile(f,data,length,&written,nullptr);
        if(ok)ok=FlushFileBuffers(f);CloseHandle(f);
        if(ok&&written==length)MoveFileExW(kTemp,kOutput,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
    }
};
static bool valid_object(uint64_t object,uint64_t expected_class) {
    uint32_t flags=0;uint64_t klass=0,vtable=0;
    return value(object,vtable)&&vtable!=0&&value(object+8,flags)&&!(flags&0x60000000u)&&
        value(object+0x10,klass)&&klass==expected_class;
}
static const char* check_entry(const Entry& e,const Header& h,uint64_t image) {
    if(!valid_object(e.account,e.account_class))return "account_object_mismatch";
    uint64_t outer=0,tech=0,inventory=0;Guid uid{};
    if(!value(e.account+0x20,outer)||outer!=h.manager)return "account_outer_mismatch";
    if(!value(e.account+0xc8,uid)||!same(&uid,&e.uid,sizeof uid))return "account_uid_mismatch";
    if(!value(e.account+0x190,inventory)||inventory!=e.inventory)return "inventory_mismatch";
    if(!value(e.account+0x1a0,tech)||tech!=e.technology)return "technology_mismatch";
    if(!value(tech+0x20,outer)||outer!=e.account)return "technology_outer_mismatch";
    if(!value(inventory+0x20,outer)||outer!=e.account)return "inventory_outer_mismatch";
    // Matching 1.0.5 executable: only a const FGuid TMap lookup, no login/state creation.
#ifdef PAL_PROBE_TEST
    auto answer=test_native_lookup((void*)h.manager,&e.uid);
#else
    using Lookup = void* (__fastcall *)(void*,const Guid*);
    auto lookup=(Lookup)(image+0x03034120);
    auto answer=lookup((void*)h.manager,&e.uid);
#endif
    return (uint64_t)answer==e.account ? nullptr : "native_lookup_mismatch";
}
extern "C" __declspec(dllexport) int pal_native_readonly_v2(void*) {
    // No work in DllMain; no arbitrary entrypoint/address is accepted by this export.
    if(!exe_matches())return 0;
    Request r{};DWORD got=0;
    HANDLE f=CreateFileW(kInput,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(f==INVALID_HANDLE_VALUE)return 0;
    LARGE_INTEGER file_size{};
    BOOL read_ok=GetFileSizeEx(f,&file_size)&&ReadFile(f,&r,sizeof r,&got,nullptr);
    CloseHandle(f);
    Out o;o.text("{\"read_only\":true,\"not_a_builder\":true,\"native_probe_version\":1");
    o.text(",\"nonce\":\"");o.guid(r.header.nonce);o.text("\"");
    const char* error=nullptr;
    if(!read_ok||file_size.QuadPart!=got||got<64||!same(r.header.magic,"PLNRO001",8)||r.header.version!=1||
       r.header.reserved!=0||r.header.count==0||r.header.count>16||got!=64+48*r.header.count)error="invalid_wire_request";
    if(!error&&(r.header.expires_unix<now()||r.header.expires_unix>now()+30))error="expired_request";
    if(!error&&r.header.thread_id!=GetCurrentThreadId())error="wrong_thread";
    uint64_t image=(uint64_t)GetModuleHandleW(nullptr);
    if(!error&&!image_matches(image))error="executable_fingerprint_mismatch";
    if(!error&&!valid_object(r.header.manager,r.header.manager_class))error="manager_mismatch";
    if(error) { o.text(",\"ok\":false,\"error\":\"");o.text(error);o.text("\"}");o.commit();return 0; }
    o.text(",\"game_thread_id\":");o.number(GetCurrentThreadId());o.text(",\"accounts\":[");
    bool all_ok=true;
    for(unsigned i=0;i<r.header.count;++i) {
        if(i)o.ch(',');o.text("{\"player_uid_hex\":\"");o.guid(r.entries[i].uid);o.text("\",");
        auto problem=check_entry(r.entries[i],r.header,image);
        if(problem){all_ok=false;o.text("\"ok\":false,\"error\":\"");o.text(problem);o.ch('"');}
        else o.text("\"ok\":true,\"native_lookup_same_account\":true,\"account_outer_chain_matches\":true");
        o.ch('}');
    }
    o.text("],\"ok\":");o.text(all_ok?"true":"false");o.ch('}');o.commit();return 0;
}
extern "C" BOOL WINAPI DllMain(HINSTANCE,DWORD,LPVOID) { return TRUE; }
