#include <cassert>
#include <cstdint>
#include <cwchar>
#include <string>
#include <iostream>
using DWORD=uint32_t;
constexpr DWORD ERROR_SUCCESS=0,ERROR_ENVVAR_NOT_FOUND=203;
static std::wstring configured;static bool present=false;static DWORD last_error=0;
static int connections=0,last_port=0,errors=0;static std::string last_host;
void SetLastError(DWORD e){last_error=e;}DWORD GetLastError(){return last_error;}
DWORD GetEnvironmentVariableW(const wchar_t*name,wchar_t*value,DWORD capacity){
 assert(std::wcscmp(name,L"PALCRAFT_HOST_PROXY_PORT")==0);
 if(!present){last_error=ERROR_ENVVAR_NOT_FOUND;return 0;}
 if(configured.empty())return 0;
 if(configured.size()+1>capacity)return DWORD(configured.size()+1);
 std::wcscpy(value,configured.c_str());return DWORD(configured.size());
}
struct WsClient{void start(const char*host,int port){++connections;last_port=port;last_host=host;}};
void status(bool connected,bool active){assert(!connected&&!active);}
void OutputDebugStringW(const wchar_t*){++errors;}
static int host_proxy_port(){
 wchar_t value[16]{};SetLastError(ERROR_SUCCESS);
 DWORD used=GetEnvironmentVariableW(L"PALCRAFT_HOST_PROXY_PORT",value,16);
 if(!used)return GetLastError()==ERROR_ENVVAR_NOT_FOUND?25599:0;
 if(used>=16)return 0;
 int port=0;
 for(DWORD i=0;i<used;++i){if(value[i]<L'0'||value[i]>L'9')return 0;port=port*10+int(value[i]-L'0');if(port>65535)return 0;}
 return port;
}
static DWORD startup(){
 const int proxyPort=host_proxy_port();
 if(!proxyPort){status(false,false);OutputDebugStringW(L"[PalCraft] Invalid PALCRAFT_HOST_PROXY_PORT; connection refused.\n");return 0;}
 WsClient ws;ws.start("127.0.0.1",proxyPort);
 return 1;
}
int main(){
 int cases=0;
 auto check=[&](bool exists,const wchar_t*value,int expected){
  present=exists;configured=value;connections=0;last_port=0;errors=0;last_error=ERROR_ENVVAR_NOT_FOUND;
  const auto started=startup();assert(started==(expected?1u:0u));
  assert(connections==(expected?1:0));assert(errors==(expected?0:1));
  if(expected)assert(last_port==expected&&last_host=="127.0.0.1");++cases;
 };
 check(false,L"",25599);
 check(true,L"1",1);check(true,L"65535",65535);check(true,L"25599",25599);check(true,L"25699",25699);
 check(true,L"00001",1);check(true,L"025599",25599);
 for(const auto*bad:{L"",L"0",L"00000",L"65536",L"655350",L"-1",L"+1",L" 25599",L"25599 ",L"1.0",L"25599x",L"1\n",L"4294967295",L"9999999999999999",L"00000000000000001",L"２５５９９"})check(true,bad,0);
 std::cout<<"proxy-port source parser/startup passed: "<<cases<<" cases, invalid explicit values created zero connections\n";
}
