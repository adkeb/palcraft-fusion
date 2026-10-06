#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
typedef int (*result_fn)(void);
typedef const char *(*error_fn)(void);
typedef struct { DWORD version, mask, slots; uintptr_t target, crt; } Status;
typedef BOOL (*status_fn)(Status *);
static uint64_t iat_hash(HMODULE module) {
    BYTE *base=(BYTE *)module;
    IMAGE_DOS_HEADER *dos=(IMAGE_DOS_HEADER *)base;
    IMAGE_NT_HEADERS64 *pe=(IMAGE_NT_HEADERS64 *)(base+dos->e_lfanew);
    IMAGE_IMPORT_DESCRIPTOR *d=(IMAGE_IMPORT_DESCRIPTOR *)(base+pe->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress);
    uint64_t result=1469598103934665603ULL;
    for(;d->Name;++d){
        IMAGE_THUNK_DATA64 *p=(IMAGE_THUNK_DATA64 *)(base+d->FirstThunk);
        for(size_t i=0;p[i].u1.Function;++i){result^=p[i].u1.Function;result*=1099511628211ULL;}
    }
    return result;
}
static uint64_t exported_code_hash(void) {
    const char *names[]={"fopen","freopen","getenv","rename","remove","LoadLibraryExA","GetModuleFileNameA"};
    HMODULE crt=GetModuleHandleW(L"ucrtbase.dll"),kernel=GetModuleHandleW(L"kernel32.dll");
    uint64_t result=1469598103934665603ULL;
    for(size_t i=0;i<7;++i){
        const unsigned char *p=(const unsigned char *)(void *)GetProcAddress(i<5?crt:kernel,names[i]);
        if(!p)return 0;
        for(size_t j=0;j<32;++j){result^=p[j];result*=1099511628211ULL;}
    }
    return result;
}
int wmain(int argc, wchar_t **argv) {
    if (argc != 3) return 64;
    if (!SetPriorityClass(GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS)) return 65;
    int control = lstrcmpW(argv[2], L"control") == 0;
    uint64_t host_before=iat_hash(GetModuleHandleW(NULL)),code_before=exported_code_hash();
    HMODULE core = LoadLibraryW(argv[1]);
    if (!core) { printf("{\"load_error\":%lu}\n", GetLastError()); return 66; }
    result_fn early = (result_fn)(void *)GetProcAddress(core, "pc_probe_early_result");
    result_fn run = (result_fn)(void *)GetProcAddress(core, "pc_probe_run");
    error_fn error = (error_fn)(void *)GetProcAddress(core, "pc_probe_error");
    result_fn lifetime=(result_fn)(void *)GetProcAddress(core,"pc_probe_env_lifetime");
    if (!early || !run || !error || !lifetime) return 67;
    int boot = early();
    if (control) {
        printf("{\"control\":true,\"early_status\":%d,\"expected_failure\":%s}\n", boot, boot ? "true" : "false");
        FreeLibrary(core); return boot ? 0 : 68;
    }
    HMODULE shim = GetModuleHandleW(L"PalCraftUE4SSUtf8.dll");
    status_fn status = shim ? (status_fn)(void *)GetProcAddress(shim, "palcraft_utf8_status") : NULL;
    Status details = {0};
    if (!status || !status(&details) || details.target != (uintptr_t)core) return 69;
    /* The host's own CRT IAT must still point to its original provider export. */
    BOOL scoped = host_before==iat_hash(GetModuleHandleW(NULL))&&code_before&&code_before==exported_code_hash();
    int result = boot ? boot : run();
    int environment_stable=lifetime();
    int providers_complete=GetProcAddress((HMODULE)details.crt,"_wfreopen_s")!=NULL;
    if (result) fprintf(stderr, "FLOW_ERROR %s\n", error());
    printf("{\"early_status\":%d,\"flow_status\":%d,\"mask\":%lu,\"slots\":%lu,\"target_matches\":true,\"host_crt_unchanged\":%s,\"getenv_pointer_stable\":%s,\"secure_wide_provider_available\":%s,\"system_codepage\":%u,\"game_loaded\":false}\n",
           boot, result, details.mask, details.slots, scoped ? "true" : "false",environment_stable?"true":"false",providers_complete?"true":"false",GetACP());
    FreeLibrary(core);
    return !result && scoped && environment_stable && providers_complete ? 0 : 70;
}
