#define PAL_PROBE_TEST
#include "readonly_probe.cpp"
#include <cassert>
#include <cstring>
#include <string>
#include <vector>
#include <iostream>
struct Region {uint64_t address;std::vector<unsigned char> data;};
static std::vector<Region> regions;
static std::vector<unsigned char> input;
static std::string output;
static std::wstring filename;
static uint64_t current_time=2000000000ULL;
static uint32_t thread_id=1234;
static uint64_t returned_account=0x500000;
static unsigned calls=0;
static bool fail_read=false;
static uint64_t image_base=0x10000000,manager_address=0x400000,account_address=0x500000;
HANDLE GetCurrentProcess(){return (HANDLE)1;}
BOOL ReadProcessMemory(HANDLE,const void* p,void* o,SIZE_T n,SIZE_T* done){
 for(auto&r:regions){auto a=(uint64_t)p;if(a>=r.address&&a+n>=a&&a+n<=r.address+r.data.size()){
  std::memcpy(o,r.data.data()+a-r.address,n);*done=n;return 1;}}
 *done=0;return 0;
}
void GetSystemTimeAsFileTime(FILETIME*f){auto t=(current_time+11644473600ULL)*10000000ULL;f->dwLowDateTime=(DWORD)t;f->dwHighDateTime=(DWORD)(t>>32);}
DWORD GetModuleFileNameW(void*,wchar_t*p,DWORD n){if(filename.size()+1>n)return n;std::memcpy(p,filename.c_str(),(filename.size()+1)*sizeof(wchar_t));return filename.size();}
HANDLE GetModuleHandleW(void*){return (HANDLE)image_base;}
DWORD GetCurrentThreadId(){return thread_id;}
HANDLE CreateFileW(const wchar_t*,DWORD access,DWORD,void*,DWORD,DWORD,void*){return (HANDLE)(uintptr_t)(access==GENERIC_READ?1:2);}
BOOL ReadFile(HANDLE,void*p,DWORD n,DWORD*got,void*){*got=(DWORD)(input.size()<n?input.size():n);std::memcpy(p,input.data(),*got);return !fail_read;}
BOOL GetFileSizeEx(HANDLE,LARGE_INTEGER*s){s->QuadPart=input.size();return 1;}
BOOL WriteFile(HANDLE,const void*p,DWORD n,DWORD*w,void*){output.assign((const char*)p,n);*w=n;return 1;}
BOOL FlushFileBuffers(HANDLE){return 1;}BOOL CloseHandle(HANDLE){return 1;}BOOL MoveFileExW(const wchar_t*,const wchar_t*,DWORD){return 1;}
void*test_native_lookup(void*,const void*){++calls;return (void*)returned_account;}
template<class T>void put(std::vector<unsigned char>&v,unsigned p,T x){assert(p+sizeof x<=v.size());std::memcpy(v.data()+p,&x,sizeof x);}
static void setup(){
 filename=kExe;thread_id=1234;calls=0;fail_read=false;returned_account=account_address;output.clear();regions.clear();
 Region pe{image_base,std::vector<unsigned char>(4096)};put<uint16_t>(pe.data,0,0x5a4d);put<uint32_t>(pe.data,0x3c,0x100);
 put<uint32_t>(pe.data,0x100,0x4550);put<uint16_t>(pe.data,0x104,0x8664);put<uint32_t>(pe.data,0x108,0x6aa38b38);put<uint32_t>(pe.data,0x150,0x9731000);regions.push_back(pe);
 regions.push_back({image_base+0x3034120,std::vector<unsigned char>(kLookupCode,kLookupCode+sizeof kLookupCode)});
 Region manager{manager_address,std::vector<unsigned char>(0x200)};put<uint64_t>(manager.data,0,0x100100);put<uint64_t>(manager.data,0x10,0x400100);regions.push_back(manager);
 Region account{account_address,std::vector<unsigned char>(0x200)};put<uint64_t>(account.data,0,0x100100);put<uint64_t>(account.data,0x10,0x500100);put<uint64_t>(account.data,0x20,manager_address);
 Guid uid{0xd8178a9d,0,0,0};put<Guid>(account.data,0xc8,uid);put<uint64_t>(account.data,0x190,0x600000);put<uint64_t>(account.data,0x1a0,0x700000);regions.push_back(account);
 Region inv{0x600000,std::vector<unsigned char>(64)};put<uint64_t>(inv.data,0x20,account_address);regions.push_back(inv);
 Region tech{0x700000,std::vector<unsigned char>(64)};put<uint64_t>(tech.data,0x20,account_address);regions.push_back(tech);
 Header h{};std::memcpy(h.magic,"PLNRO001",8);h.version=1;h.count=1;h.thread_id=1234;h.expires_unix=current_time+15;h.manager=manager_address;h.manager_class=0x400100;h.nonce={1,2,3,4};
 Entry e{account_address,0x500100,0x700000,0x600000,uid};input.resize(112);put(input,0,h);put(input,64,e);
}
static void check(const char* expected,unsigned expected_calls){pal_native_readonly_v2(nullptr);assert(output.find(expected)!=std::string::npos);assert(calls==expected_calls);}
int main(){
 setup();check("\"ok\":true",1);assert(output.find("000000000000400080000000000000fe")!=std::string::npos);
 setup();thread_id=1235;check("wrong_thread",0);
 setup();put<uint64_t>(input,24,current_time-1);check("expired_request",0);
 setup();put<uint64_t>(input,24,current_time+31);check("expired_request",0);
 setup();input[0]='X';check("invalid_wire_request",0);
 setup();input.resize(111);check("invalid_wire_request",0);
 setup();put<uint32_t>(input,12,16);input.resize(833);check("invalid_wire_request",0);
 setup();put<uint32_t>(input,12,17);check("invalid_wire_request",0);
 setup();put<uint32_t>(input,20,1);check("invalid_wire_request",0);
 setup();fail_read=true;check("invalid_wire_request",0);
 setup();regions[1].data[0]^=1;check("executable_fingerprint_mismatch",0);
 setup();put<uint32_t>(regions[0].data,0x108,0);check("executable_fingerprint_mismatch",0);
 setup();put<uint32_t>(regions[2].data,8,0x60000000);check("manager_mismatch",0);
 setup();put<uint64_t>(regions[3].data,0x20,0x400010);check("account_outer_mismatch",0);
 setup();put<uint32_t>(regions[3].data,0xc8,99);check("account_uid_mismatch",0);
 setup();put<uint64_t>(regions[3].data,0x190,0x600010);check("inventory_mismatch",0);
 setup();put<uint64_t>(regions[3].data,0x1a0,0x700010);check("technology_mismatch",0);
 setup();put<uint64_t>(regions[4].data,0x20,0x500010);check("inventory_outer_mismatch",0);
 setup();put<uint64_t>(regions[5].data,0x20,0x500010);check("technology_outer_mismatch",0);
 setup();returned_account=0;check("native_lookup_mismatch",1);
 setup();filename=L"D:\\PalworldServer-LAN\\Pal\\Binaries\\Win64\\PalServer-Win64-Shipping-Cmd.exe";pal_native_readonly_v2(nullptr);assert(output.empty()&&calls==0);
 std::cout<<"21 native bridge gate checks passed; game ABI remains lab-unverified\n";return 0;
}
