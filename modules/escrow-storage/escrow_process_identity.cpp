// Fixed BridgeLab-only read-only process/creation-time attestation. No game
// function, save/inventory access, lifecycle action or process-memory read.
#include "credit_abi_support.hpp"
static const wchar_t kBootInput[]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\escrow-boot-process.request.bin";
static void decimal(Out&o,uint64_t n){char b[20];unsigned i=0;do{b[i++]=(char)('0'+n%10);n/=10;}while(n);while(i)o.ch(b[--i]);}
extern "C" __declspec(dllexport) int palcraft_escrow_process_identity_v1(void*) {
 if(!exe_matches())return 0;
 Header r{};DWORD got=0;LARGE_INTEGER size{};
 HANDLE f=CreateFileW(kBootInput,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(f==INVALID_HANDLE_VALUE)return 0;
 bool ok=GetFileSizeEx(f,&size)&&size.QuadPart==sizeof r&&ReadFile(f,&r,sizeof r,&got,nullptr)&&got==sizeof r;CloseHandle(f);
 if(!ok||!same(r.magic,"PLBOOT01",8)||r.version!=1||r.count!=1||r.reserved||r.manager||r.manager_class||
  r.thread_id!=GetCurrentThreadId()||r.expires_unix<now()||r.expires_unix>now()+30)return 0;
 FILETIME creation{},exit{},kernel{},user{};
 if(!GetProcessTimes(GetCurrentProcess(),&creation,&exit,&kernel,&user))return 0;
 uint64_t created=((uint64_t)creation.dwHighDateTime<<32)|creation.dwLowDateTime;
 Out o;o.text("{\"protocol\":3,\"kind\":\"palworld_process_identity\",\"boot_hex\":\"");o.guid(r.nonce);
 o.text("\",\"pid\":");o.number(GetCurrentProcessId());o.text(",\"thread_id\":");o.number(GetCurrentThreadId());
 o.text(",\"process_created_filetime\":\"");decimal(o,created);o.text("\",\"observed_unix\":");decimal(o,now());o.text(",\"read_only\":true}");
 if(o.overflow)return 0;
 wchar_t path[280]=L"D:\\PalworldServer-LAN\\BridgeLab\\rpc\\escrow-boot-process-";
 unsigned length=0;while(path[length])++length;const wchar_t h[]=L"0123456789abcdef";
 const uint32_t words[]={r.nonce.a,r.nonce.b,r.nonce.c,r.nonce.d};
 for(unsigned i=0;i<4;++i)for(unsigned j=8;j;--j)path[length++]=h[(words[i]>>((j-1)*4))&15];
 const wchar_t suffix[]=L".json";for(unsigned i=0;i<sizeof suffix/sizeof(wchar_t);++i)path[length+i]=suffix[i];
 // Non-replacing output: a hot reload cannot change the old boot identity.
 f=CreateFileW(path,GENERIC_WRITE,FILE_SHARE_READ,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(f==INVALID_HANDLE_VALUE)return 0;DWORD written=0;
 WriteFile(f,o.data,o.length,&written,nullptr);FlushFileBuffers(f);CloseHandle(f);return 0;
}
