/* Same-pin unpatched LuaRaw. First script is loaded during this module's attach,
   before the host gets a chance to call a public callback. No Unreal is present. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
static lua_State *vm;
static int early = -1;
static int open_libraries(lua_State *state) { luaL_openlibs(state); return 0; }
__declspec(dllexport) int pc_probe_early_result(void) { return early; }
__declspec(dllexport) int pc_probe_env_lifetime(void) {
    const char *first=getenv("PALCRAFT_WINDOWS_ROOT");
    if(!first)return 0;
    size_t count=strlen(first);
    char *snapshot=malloc(count+1);if(!snapshot)return 0;
    memcpy(snapshot,first,count+1);
    const char *second=getenv("PALCRAFT_UTF8_FLOW_SCRIPT");
    int ok=second&&strcmp(first,snapshot)==0;
    free(snapshot);return ok;
}
__declspec(dllexport) int pc_probe_run(void) {
    if (early) return early;
    const char *script = getenv("PALCRAFT_UTF8_FLOW_SCRIPT");
    if (!script) return 81;
    int status = luaL_loadfilex(vm, script, NULL);
    if (!status) status = lua_pcall(vm, 0, 0, 0);
    return status;
}
__declspec(dllexport) const char *pc_probe_error(void) {
    return vm ? lua_tostring(vm, -1) : "no Lua state";
}
BOOL WINAPI DllMain(HMODULE module, DWORD reason, LPVOID reserved) {
    (void)module; (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        vm = luaL_newstate(); if (!vm) { early = 82; return TRUE; }
        lua_pushcfunction(vm, open_libraries);
        early = lua_pcall(vm, 0, 0, 0);
        if (early) return TRUE;
        const char *script = getenv("PALCRAFT_UTF8_BOOTSTRAP_SCRIPT");
        if (!script) { early = 83; return TRUE; }
        early = luaL_loadfilex(vm, script, NULL);
        if (!early) early = lua_pcall(vm, 0, 0, 0);
    }
    if (reason == DLL_PROCESS_DETACH && vm) lua_close(vm);
    return TRUE;
}
