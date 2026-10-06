// Matched client e590 only, raw Win64 ABI; trusted actual exe path plus full SHA256.
// Lua calls this fixed C export through package.loadlib on the game thread.
// Helpers read only this process; actual bounded produce is defined in the paired client credit.
#define WIN32_LEAN_AND_MEAN
#ifdef PAL_PROBE_TEST
#include "credit_test_win32.hpp"
#else
#include <windows.h>
#endif
#include <stdint.h>
#include <bcrypt.h>
#include "credit_client_fingerprints.hpp"

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
static bool executable_sha(const wchar_t* path) {
 static const unsigned char expected[]={0xe5,0x90,0xb5,0xe7,0xbf,0xaa,0x3f,0xea,0x40,0xfa,0xb1,0xa0,0x2c,0xc7,0x2c,0x8f,0xc5,0xfd,0x6f,0x86,0x31,0xef,0x23,0x08,0xe9,0x5a,0xc5,0x6c,0x25,0x19,0x58,0x37};
 BCRYPT_ALG_HANDLE algorithm=nullptr;BCRYPT_HASH_HANDLE hash=nullptr;DWORD object_size=0,got=0;unsigned char digest[32]{};
 HANDLE file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(file==INVALID_HANDLE_VALUE)return false;LARGE_INTEGER size{};bool ok=GetFileSizeEx(file,&size)&&size.QuadPart==161802312;
 unsigned char* object=nullptr;unsigned char* buffer=nullptr;
 if(ok)ok=BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0)>=0;
 if(ok)ok=BCryptGetProperty(algorithm,BCRYPT_OBJECT_LENGTH,(PUCHAR)&object_size,sizeof object_size,&got,0)>=0&&object_size>0&&object_size<=65536;
 if(ok){object=(unsigned char*)HeapAlloc(GetProcessHeap(),0,object_size);buffer=(unsigned char*)HeapAlloc(GetProcessHeap(),0,65536);ok=object&&buffer;}
 if(ok)ok=BCryptCreateHash(algorithm,&hash,object,object_size,nullptr,0,0)>=0;
 uint64_t total=0;
 while(ok){DWORD n=0;if(!ReadFile(file,buffer,65536,&n,nullptr)){ok=false;break;}if(!n)break;total+=n;ok=BCryptHashData(hash,buffer,n,0)>=0;}
 if(ok)ok=total==161802312&&BCryptFinishHash(hash,digest,sizeof digest,0)>=0&&same(digest,expected,sizeof expected);
 if(hash)BCryptDestroyHash(hash);if(algorithm)BCryptCloseAlgorithmProvider(algorithm,0);
 if(object)HeapFree(GetProcessHeap(),0,object);if(buffer)HeapFree(GetProcessHeap(),0,buffer);CloseHandle(file);return ok;
}
static bool same_file(const wchar_t* a,const wchar_t* b) {
 HANDLE x=CreateFileW(a,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
 HANDLE y=CreateFileW(b,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(x==INVALID_HANDLE_VALUE||y==INVALID_HANDLE_VALUE){if(x!=INVALID_HANDLE_VALUE)CloseHandle(x);if(y!=INVALID_HANDLE_VALUE)CloseHandle(y);return false;}
 BY_HANDLE_FILE_INFORMATION i{},j{};bool ok=GetFileInformationByHandle(x,&i)&&GetFileInformationByHandle(y,&j)&&
  (i.nFileIndexHigh||i.nFileIndexLow)&&i.dwVolumeSerialNumber==j.dwVolumeSerialNumber&&i.nFileIndexHigh==j.nFileIndexHigh&&i.nFileIndexLow==j.nFileIndexLow;
 CloseHandle(x);CloseHandle(y);return ok;
}
static bool exe_matches() {
 static bool checked=false,matched=false;if(checked)return matched;checked=true;
 wchar_t actual[32768]{},expected[32768]{},a[32768]{},b[32768]{};
 DWORD n=GetModuleFileNameW(nullptr,actual,32768),m=GetEnvironmentVariableW(L"PALCRAFT_PAL_EXE",expected,32768);
 if(!n||n>=32768||!m||m>=32768)return false;
 DWORD x=GetFullPathNameW(actual,32768,a,nullptr),y=GetFullPathNameW(expected,32768,b,nullptr);
 if(!x||x>=32768||!y||y>=32768)return false;
 if(CompareStringOrdinal(a,-1,b,-1,TRUE)!=CSTR_EQUAL&&!same_file(a,b))return false;
 matched=executable_sha(a);return matched;
}
static bool image_matches(uint64_t base) {
    uint16_t mz=0,machine=0;uint32_t offset=0,pe=0,stamp=0,size=0;
    if(!value(base,mz)||mz!=0x5a4d||!value(base+0x3c,offset)||offset>0x1000)return false;
    if(!value(base+offset,pe)||pe!=0x4550||!value(base+offset+4,machine)||machine!=0x8664)return false;
    if(!value(base+offset+8,stamp)||stamp!=0x6aa377c1||!value(base+offset+24+56,size)||size!=0xa011000)return false;
    unsigned char bytes[sizeof kLookupCode];
    return read(base+0x03189af0,bytes,sizeof bytes)&&same(bytes,kLookupCode,sizeof bytes);
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
};
static bool valid_object(uint64_t object,uint64_t expected_class) {
    uint32_t flags=0;uint64_t klass=0,vtable=0;
    return value(object,vtable)&&vtable!=0&&value(object+8,flags)&&!(flags&0x60000000u)&&
        value(object+0x10,klass)&&klass==expected_class;
}
