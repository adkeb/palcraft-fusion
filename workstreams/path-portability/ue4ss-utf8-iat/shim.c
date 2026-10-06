/* One module's named IAT only. No CRT code patch, C++ ABI, thread, or locale change. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stddef.h>

typedef void *(__cdecl *wfopen_fn)(const wchar_t *, const wchar_t *);
typedef void *(__cdecl *wfreopen_fn)(const wchar_t *, const wchar_t *, void *);
typedef int (__cdecl *wfreopen_s_fn)(void **, const wchar_t *, const wchar_t *, void *);
typedef int (__cdecl *wremove_fn)(const wchar_t *);
typedef int (__cdecl *wrename_fn)(const wchar_t *, const wchar_t *);
typedef int *(__cdecl *errno_fn)(void);
typedef int (__cdecl *wsystem_fn)(const wchar_t *);
typedef void *(__cdecl *wpopen_fn)(const wchar_t *, const wchar_t *);
typedef wchar_t *(__cdecl *wtmpnam_fn)(wchar_t *);

static struct {
    HMODULE target, crt;
    DWORD tls, mask, slots;
    wfopen_fn open;
    wfreopen_fn reopen;
    wfreopen_s_fn reopen_s;
    wremove_fn remove;
    wrename_fn rename;
    errno_fn error;
    wsystem_fn system;
    wpopen_fn popen;
    wtmpnam_fn tmpnam;
} state = {.tls = TLS_OUT_OF_INDEXES};
typedef struct Environment { char *name, *value; struct Environment *next; } Environment;
typedef struct { Environment *environment; char temporary[260]; } ThreadStorage;

static int equal(const char *a, const char *b) {
    while (*a && *a == *b) { ++a; ++b; }
    return *a == *b;
}
static void set_error(int value) { if (state.error) *state.error() = value; }
static wchar_t *wide(const char *value) {
    if (!value) { set_error(22); return NULL; }
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, NULL, 0);
    if (!count) { set_error(42); return NULL; }
    wchar_t *result = HeapAlloc(GetProcessHeap(), 0, (SIZE_T)count * sizeof(wchar_t));
    if (!result) { set_error(12); return NULL; }
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, result, count)) {
        HeapFree(GetProcessHeap(), 0, result); set_error(42); return NULL;
    }
    return result;
}
static char *utf8(const wchar_t *value) {
    int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, NULL, 0, NULL, NULL);
    if (!count) { set_error(42); return NULL; }
    char *result = HeapAlloc(GetProcessHeap(), 0, (SIZE_T)count);
    if (!result) { set_error(12); return NULL; }
    if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, result, count, NULL, NULL)) {
        HeapFree(GetProcessHeap(), 0, result); set_error(42); return NULL;
    }
    return result;
}
static void release(void *value) { if (value) HeapFree(GetProcessHeap(), 0, value); }
static ThreadStorage *thread_storage(void) {
    ThreadStorage *value = TlsGetValue(state.tls);
    if (!value) {
        value = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*value));
        if (!value || !TlsSetValue(state.tls, value)) { release(value); set_error(12); return NULL; }
    }
    return value;
}
static void release_thread(void) {
    ThreadStorage *value = TlsGetValue(state.tls);
    if (value) {
        Environment *entry=value->environment;
        while(entry){Environment *next=entry->next;release(entry->name);release(entry->value);release(entry);entry=next;}
        release(value); TlsSetValue(state.tls, NULL);
    }
}
static void *__cdecl utf8_fopen(const char *path, const char *mode) {
    wchar_t *p = wide(path), *m = wide(mode);
    void *result = p && m ? state.open(p, m) : NULL;
    release(p); release(m); return result;
}
static void *__cdecl utf8_freopen(const char *path, const char *mode, void *stream) {
    wchar_t *p = path ? wide(path) : NULL, *m = wide(mode);
    void *result = (!path || p) && m ? state.reopen(p, m, stream) : NULL;
    release(p); release(m); return result;
}
static int __cdecl utf8_freopen_s(void **out, const char *path, const char *mode, void *stream) {
    wchar_t *p = path ? wide(path) : NULL, *m = wide(mode);
    int result = (!path || p) && m ? state.reopen_s(out, p, m, stream) : 42;
    release(p); release(m); return result;
}
static int __cdecl utf8_remove(const char *path) {
    wchar_t *p = wide(path); int result = p ? state.remove(p) : -1;
    release(p); return result;
}
static int __cdecl utf8_rename(const char *from, const char *to) {
    wchar_t *a = wide(from), *b = wide(to);
    int result = a && b ? state.rename(a, b) : -1;
    release(a); release(b); return result;
}
static char *__cdecl utf8_getenv(const char *name) {
    ThreadStorage *storage = thread_storage(); wchar_t *key = wide(name);
    if (!storage || !key) { release(key); return NULL; }
    SetLastError(ERROR_SUCCESS);
    DWORD count = GetEnvironmentVariableW(key, NULL, 0);
    if (!count && GetLastError() != ERROR_SUCCESS) { release(key); return NULL; }
    wchar_t *value = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, (SIZE_T)(count ? count : 1) * sizeof(wchar_t));
    if (!value) { release(key); set_error(12); return NULL; }
    if (count && GetEnvironmentVariableW(key, value, count) >= count) {
        release(key); release(value); return NULL;
    }
    char *result = utf8(value); release(key); release(value);
    if(!result)return NULL;
    Environment *entry=storage->environment;
    while(entry&&!equal(entry->name,name))entry=entry->next;
    if(entry){
        if(equal(entry->value,result)){release(result);return entry->value;}
        /* A changed variable may invalidate its own old value, as the CRT does. */
        release(entry->value);entry->value=result;return result;
    }
    size_t name_count=0;while(name[name_count])++name_count;
    entry=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*entry));
    char *copy=HeapAlloc(GetProcessHeap(),0,name_count+1);
    if(!entry||!copy){release(entry);release(copy);release(result);set_error(12);return NULL;}
    for(size_t i=0;i<=name_count;++i)copy[i]=name[i];
    entry->name=copy;entry->value=result;entry->next=storage->environment;storage->environment=entry;
    return result;
}
static HMODULE WINAPI utf8_load_library(const char *path, HANDLE file, DWORD flags) {
    wchar_t *value = wide(path);
    if (!value) { SetLastError(ERROR_NO_UNICODE_TRANSLATION); return NULL; }
    HMODULE result = LoadLibraryExW(value, file, flags);
    DWORD error = GetLastError(); release(value); SetLastError(error); return result;
}
static DWORD WINAPI utf8_module_filename(HMODULE module, char *out, DWORD capacity) {
    wchar_t *path = HeapAlloc(GetProcessHeap(), 0, 32768 * sizeof(wchar_t));
    if (!path) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return 0; }
    DWORD used = GetModuleFileNameW(module, path, 32768);
    if (!used || used >= 32768) { DWORD error = GetLastError(); release(path); SetLastError(error); return 0; }
    int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path, -1, NULL, 0, NULL, NULL);
    if (!size || !out || !capacity || (DWORD)size > capacity) {
        release(path); if (out && capacity) out[0] = 0; SetLastError(ERROR_INSUFFICIENT_BUFFER); return capacity;
    }
    int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path, -1, out, (int)capacity, NULL, NULL);
    release(path); return count ? (DWORD)count - 1 : 0;
}
static int __cdecl utf8_system(const char *command) {
    if (!command) return state.system(NULL);
    wchar_t *value = wide(command); int result = value ? state.system(value) : -1;
    release(value); return result;
}
static void *__cdecl utf8_popen(const char *command, const char *mode) {
    wchar_t *c = wide(command), *m = wide(mode);
    void *result = c && m ? state.popen(c, m) : NULL;
    release(c); release(m); return result;
}
static char *__cdecl utf8_tmpnam(char *buffer) {
    wchar_t *value = state.tmpnam(NULL);
    if (!value) return NULL;
    char *text = utf8(value); if (!text) return NULL;
    size_t count = 0; while (text[count]) ++count;
    if (count >= 260) { release(text); set_error(34); return NULL; }
    ThreadStorage *storage = thread_storage();
    if (!buffer && !storage) { release(text); return NULL; }
    char *result = buffer ? buffer : storage->temporary;
    for (size_t i = 0; i <= count; ++i) result[i] = text[i];
    release(text); return result;
}
typedef struct { const char *name; void *function; DWORD bit; } Entry;
static Entry entries[] = {
    {"fopen", utf8_fopen, 1}, {"freopen", utf8_freopen, 2},
    {"remove", utf8_remove, 4}, {"rename", utf8_rename, 8}, {"getenv", utf8_getenv, 16},
    {"LoadLibraryExA", utf8_load_library, 32}, {"GetModuleFileNameA", utf8_module_filename, 64},
    {"freopen_s", utf8_freopen_s, 128}, {"system", utf8_system, 256},
    {"_popen", utf8_popen, 512}, {"tmpnam", utf8_tmpnam, 1024}
};
static ULONG_PTR *slot_for(HMODULE module, const char *wanted) {
    BYTE *base = (BYTE *)module;
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)base;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return NULL;
    IMAGE_NT_HEADERS64 *pe = (IMAGE_NT_HEADERS64 *)(base + dos->e_lfanew);
    if (pe->Signature != IMAGE_NT_SIGNATURE || pe->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64) return NULL;
    DWORD rva = pe->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
    if (!rva) return NULL;
    IMAGE_IMPORT_DESCRIPTOR *import = (IMAGE_IMPORT_DESCRIPTOR *)(base + rva);
    for (; import->Name; ++import) {
        if (!import->OriginalFirstThunk) continue;
        IMAGE_THUNK_DATA64 *lookup = (IMAGE_THUNK_DATA64 *)(base + import->OriginalFirstThunk);
        IMAGE_THUNK_DATA64 *iat = (IMAGE_THUNK_DATA64 *)(base + import->FirstThunk);
        for (size_t i = 0; lookup[i].u1.AddressOfData; ++i) {
            if (IMAGE_SNAP_BY_ORDINAL64(lookup[i].u1.Ordinal)) continue;
            IMAGE_IMPORT_BY_NAME *name = (IMAGE_IMPORT_BY_NAME *)(base + lookup[i].u1.AddressOfData);
            if (equal((char *)name->Name, wanted)) return (ULONG_PTR *)&iat[i].u1.Function;
        }
    }
    return NULL;
}
static BOOL initialize(void) {
    state.target = GetModuleHandleW(L"UE4SS.dll");
    if (!state.target) return FALSE;
    /* Manual loading beside an unmodified 9.2 Core is refused before any write. */
    if (!slot_for(state.target, "palcraft_utf8_dependency_marker")) return FALSE;
    ULONG_PTR *original = slot_for(state.target, "fopen");
    if (!original || !GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                                        (LPCWSTR)*original, &state.crt)) return FALSE;
    state.open = (wfopen_fn)(void *)GetProcAddress(state.crt, "_wfopen");
    state.reopen = (wfreopen_fn)(void *)GetProcAddress(state.crt, "_wfreopen");
    state.reopen_s = (wfreopen_s_fn)(void *)GetProcAddress(state.crt, "_wfreopen_s");
    state.remove = (wremove_fn)(void *)GetProcAddress(state.crt, "_wremove");
    state.rename = (wrename_fn)(void *)GetProcAddress(state.crt, "_wrename");
    state.error = (errno_fn)(void *)GetProcAddress(state.crt, "_errno");
    state.system = (wsystem_fn)(void *)GetProcAddress(state.crt, "_wsystem");
    state.popen = (wpopen_fn)(void *)GetProcAddress(state.crt, "_wpopen");
    state.tmpnam = (wtmpnam_fn)(void *)GetProcAddress(state.crt, "_wtmpnam");
    if (!state.open || !state.reopen || !state.remove || !state.rename || !state.error) return FALSE;
    for (size_t i = 0; i < 7; ++i) if (!slot_for(state.target, entries[i].name)) return FALSE;
    state.tls = TlsAlloc(); if (state.tls == TLS_OUT_OF_INDEXES) return FALSE;
    for (size_t i = 0; i < sizeof(entries)/sizeof(entries[0]); ++i) {
        ULONG_PTR *slot = slot_for(state.target, entries[i].name); if (!slot) continue;
        if ((i == 7 && !state.reopen_s) || (i == 8 && !state.system) ||
            (i == 9 && !state.popen) || (i == 10 && !state.tmpnam)) return FALSE;
        DWORD protection;
        if (!VirtualProtect(slot, sizeof(*slot), PAGE_READWRITE, &protection)) return FALSE;
        InterlockedExchangePointer((void *volatile *)slot, entries[i].function);
        DWORD ignored; VirtualProtect(slot, sizeof(*slot), protection, &ignored);
        state.mask |= entries[i].bit; ++state.slots;
    }
    return (state.mask & 127) == 127;
}
typedef struct { DWORD version, mask, slots; uintptr_t target, crt; } Status;
__declspec(dllexport) DWORD palcraft_utf8_dependency_marker(void) { return 1; }
__declspec(dllexport) BOOL palcraft_utf8_status(Status *result) {
    if (!result) return FALSE;
    result->version = 1; result->mask = state.mask; result->slots = state.slots;
    result->target = (uintptr_t)state.target; result->crt = (uintptr_t)state.crt;
    return (state.mask & 127) == 127;
}
BOOL WINAPI DllMain(HMODULE module, DWORD reason, LPVOID reserved) {
    (void)module; (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) return initialize();
    if (reason == DLL_THREAD_DETACH && state.tls != TLS_OUT_OF_INDEXES) release_thread();
    if (reason == DLL_PROCESS_DETACH && state.tls != TLS_OUT_OF_INDEXES) { release_thread(); TlsFree(state.tls); }
    return TRUE;
}
