// Durability only; no inventory API. Trusted startup PALCRAFT_EXCHANGE_ROOT binds
// exactly one directory. Revision/current/receipt share its volume and authority.
#include <windows.h>
#include <stdint.h>
struct CommitRequest {char magic[8];uint32_t version;char revision[128],current_temp[128],current[128];};
static_assert(sizeof(CommitRequest)==396,"Exchange WAL ABI changed");
static wchar_t root[32768];static unsigned root_len;static bool initialized;
static char row[4*1024*1024],export_row[4*1024*1024],receipt_row[4*1024*1024];
static bool eq(const char*a,const char*b,unsigned n){for(unsigned i=0;i<n;++i)if(a[i]!=b[i])return false;return true;}
static unsigned len(const char*s){unsigned n=0;while(n<128&&s[n])++n;return n;}
static bool is(const char*a,const char*b){unsigned n=0;while(b[n])++n;return len(a)==n&&eq(a,b,n);}
static bool init(){
 if(initialized)return root_len>0;initialized=true;
 DWORD n=GetEnvironmentVariableW(L"PALCRAFT_EXCHANGE_ROOT",root,32768);
 if(!n||n>=32700||n<3||root[1]!=L':'||(root[2]!=L'\\'&&root[2]!=L'/'))return false;
 while(n&&(root[n-1]==L'\\'||root[n-1]==L'/'))--n;root[n++]=L'\\';root[n]=0;root_len=n;return true;
}
static bool path(const char*name,wchar_t*out,bool optional=false){
 unsigned n=len(name);if(n==128||(!n&&!optional))return false;if(!n){out[0]=0;return true;}
 for(unsigned i=0;i<n;++i){char c=name[i];if(!((c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='-'||c=='.')||(i&&c=='.'&&name[i-1]=='.'))return false;}
 if(n<5||!eq(name+n-5,".json",5)||!(eq(name,"pal-",4)||(n>=7&&eq(name,"escrow-",7))))return false;
 for(unsigned i=0;i<root_len;++i)out[i]=root[i];for(unsigned i=0;i<=n;++i)out[root_len+i]=(wchar_t)name[i];return true;
}
static bool read(const wchar_t*p,char*b,DWORD&n,bool force=false){
 HANDLE f=CreateFileW(p,GENERIC_READ|(force?GENERIC_WRITE:0),FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(f==INVALID_HANDLE_VALUE)return false;LARGE_INTEGER size;DWORD got=0;
 bool ok=GetFileSizeEx(f,&size)&&size.QuadPart>0&&size.QuadPart<=4*1024*1024;
 if(ok){n=(DWORD)size.QuadPart;ok=ReadFile(f,b,n,&got,nullptr)&&got==n&&(!force||FlushFileBuffers(f));}CloseHandle(f);return ok;
}
static bool install(const wchar_t*p,const char*b,DWORD n,bool replace){
 wchar_t t[33000];unsigned at=0;while(p[at]){t[at]=p[at];++at;}const wchar_t suffix[]=L".native-tmp";for(unsigned i=0;i<sizeof suffix/sizeof(wchar_t);++i)t[at+i]=suffix[i];
 HANDLE f=CreateFileW(t,GENERIC_WRITE,0,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);if(f==INVALID_HANDLE_VALUE)return false;
 DWORD put=0;bool ok=WriteFile(f,b,n,&put,nullptr)&&put==n&&FlushFileBuffers(f);CloseHandle(f);
 if(ok)ok=MoveFileExW(t,p,MOVEFILE_WRITE_THROUGH|(replace?MOVEFILE_REPLACE_EXISTING:0));if(!ok)DeleteFileW(t);return ok;
}
extern "C" __declspec(dllexport) int palcraft_exchange_commit_v3(void*){
 if(!init())return 0;
 wchar_t request[33000];for(unsigned i=0;i<root_len;++i)request[i]=root[i];const wchar_t input[]=L"durable-request.bin";
 for(unsigned i=0;i<sizeof input/sizeof(wchar_t);++i)request[root_len+i]=input[i];
 CommitRequest q;DWORD got=0;LARGE_INTEGER size;HANDLE f=CreateFileW(request,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(f==INVALID_HANDLE_VALUE)return 0;bool ok=GetFileSizeEx(f,&size)&&size.QuadPart==sizeof q&&ReadFile(f,&q,sizeof q,&got,nullptr)&&got==sizeof q;CloseHandle(f);
 if(!ok||!eq(q.magic,"PLWAL003",8)||q.version!=3)return 0;
 wchar_t revision[33000],current_temp[33000],current[33000];
 if(!path(q.revision,revision)||!path(q.current_temp,current_temp,true)||!path(q.current,current,true)||(!current[0])!=(!current_temp[0]))return 0;
 unsigned n=len(q.revision),r=0;while(r+2<n&&!(q.revision[r]=='.'&&q.revision[r+1]=='r'))++r;
 if(r+8>=n||!eq(q.revision+n-5,".json",5))return 0;
 for(unsigned i=r+2;i<r+8;++i)if(q.revision[i]<'0'||q.revision[i]>'9')return 0;
 if(!((n==r+13&&eq(q.revision+r+8,".json",5))||(n==r+31&&eq(q.revision+r+8,".unconfirmed",12))))return 0;
 if(n==r+31)for(unsigned i=r+20;i<r+26;++i)if(q.revision[i]<'0'||q.revision[i]>'9')return 0;
 if(current[0]&&!is(q.current,"escrow-leases-current.json"))return 0;
 DWORD row_size=0,export_size=0,receipt_size=0;if(!read(revision,row,row_size,true))return 0;
 if(current[0]&&(!read(current_temp,export_row,export_size,true)||!install(current,export_row,export_size,true)))return 0;
 wchar_t receipt[33000];unsigned at=0;while(revision[at]){receipt[at]=revision[at];++at;}at-=5;
 const wchar_t suffix[]=L".durable.json";for(unsigned i=0;i<sizeof suffix/sizeof(wchar_t);++i)receipt[at+i]=suffix[i];
 if(GetFileAttributesW(receipt)!=INVALID_FILE_ATTRIBUTES){if(!read(receipt,receipt_row,receipt_size,true)||receipt_size!=row_size||!eq(receipt_row,row,row_size))return 0;}
 else if(!install(receipt,row,row_size,false))return 0;
 return 0; // loadlib C ABI uses no Lua stack. Lua verifies this exact forced copy.
}
extern "C" BOOL WINAPI DllMain(HINSTANCE,DWORD,LPVOID){return TRUE;}
