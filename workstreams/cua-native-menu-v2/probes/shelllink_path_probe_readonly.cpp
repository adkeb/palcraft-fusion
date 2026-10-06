// Loads the existing diagnostic .lnk and reads paths/metadata only. No Save/Resolve/target execution.
#include <windows.h>
#include <shobjidl.h>
#include <shlguid.h>
#include <objbase.h>
#include <objidl.h>
#include <cstdio>
#include <cstring>

static void json_wide(const wchar_t* text) {
    char utf8[131072] = {};
    WideCharToMultiByte(CP_UTF8, 0, text, -1, utf8, sizeof(utf8), nullptr, nullptr);
    std::putchar('"');
    for (const unsigned char* p = reinterpret_cast<const unsigned char*>(utf8); *p; ++p) {
        if (*p == '"' || *p == '\\') { std::putchar('\\'); std::putchar(*p); }
        else if (*p < 32) std::printf("\\u%04X", static_cast<unsigned>(*p));
        else std::putchar(*p);
    }
    std::putchar('"');
}

static void file_metadata(const wchar_t* path) {
    HANDLE file = CreateFileW(path, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) { std::printf("{\"open_error\":%lu}", static_cast<unsigned long>(GetLastError())); return; }
    BY_HANDLE_FILE_INFORMATION info = {};
    BOOL info_ok = GetFileInformationByHandle(file, &info); DWORD info_error = info_ok ? 0 : GetLastError();
    wchar_t final_path[32768] = {}; DWORD count = GetFinalPathNameByHandleW(file, final_path, 32768, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    DWORD final_error = count && count < 32768 ? 0 : GetLastError();
    CloseHandle(file);
    std::printf("{\"info_ok\":%s,\"info_error\":%lu,\"volume_serial\":%lu,\"file_index_high\":%lu,\"file_index_low\":%lu,\"final_path_error\":%lu,\"final_path\":",
        info_ok ? "true" : "false", static_cast<unsigned long>(info_error), static_cast<unsigned long>(info.dwVolumeSerialNumber),
        static_cast<unsigned long>(info.nFileIndexHigh), static_cast<unsigned long>(info.nFileIndexLow), static_cast<unsigned long>(final_error));
    json_wide(final_path); std::putchar('}');
}

int wmain(int argc, wchar_t** argv) {
    if (argc != 3) { std::puts("{\"stage\":\"argument_count\",\"target_executed\":false}"); return 1; }
    HRESULT init_hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(init_hr)) { std::printf("{\"stage\":\"CoInitializeEx\",\"hresult\":\"0x%08lX\"}\n", static_cast<unsigned long>(init_hr)); return 1; }
    IShellLinkW* link = nullptr;
    HRESULT create_hr = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW, reinterpret_cast<void**>(&link));
    if (FAILED(create_hr)) { CoUninitialize(); std::printf("{\"stage\":\"CoCreateInstance\",\"hresult\":\"0x%08lX\"}\n", static_cast<unsigned long>(create_hr)); return 1; }
    IPersistFile* persist = nullptr;
    HRESULT load_hr = link->QueryInterface(IID_IPersistFile, reinterpret_cast<void**>(&persist));
    if (SUCCEEDED(load_hr)) load_hr = persist->Load(argv[1], STGM_READ);
    if (persist) persist->Release();
    std::printf("{\"schema\":1,\"backend\":\"IShellLinkW\",\"operation\":\"existing_link_GetPath_only\",\"load_hresult\":\"0x%08lX\",\"expected_target\":", static_cast<unsigned long>(load_hr));
    json_wide(argv[2]); std::printf(",\"expected_metadata\":");file_metadata(argv[2]);
    wchar_t original_short[32768] = {};
    DWORD short_count = GetShortPathNameW(argv[2], original_short, 32768);
    DWORD short_error = short_count && short_count < 32768 ? 0 : GetLastError();
    if (!short_count || short_count >= 32768) original_short[0] = 0;
    std::printf(",\"windows_ACP\":%u,\"original_short_path_count\":%lu,\"original_short_path_error\":%lu,\"original_short_path\":",
        static_cast<unsigned>(GetACP()), static_cast<unsigned long>(short_count), static_cast<unsigned long>(short_error));
    json_wide(original_short); std::printf(",\"original_short_metadata\":");file_metadata(original_short);
    std::printf(",\"paths\":[");
    DWORD flags[] = {0, SLGP_RAWPATH, SLGP_SHORTPATH};
    for (unsigned i = 0; i < 3; ++i) {
        wchar_t path[32768] = {}; WIN32_FIND_DATAW found = {};
        HRESULT hr = SUCCEEDED(load_hr) ? link->GetPath(path, 32768, &found, flags[i]) : load_hr;
        if (i) std::putchar(',');
        std::printf("{\"flags\":%lu,\"hresult\":\"0x%08lX\",\"path\":", static_cast<unsigned long>(flags[i]), static_cast<unsigned long>(hr));
        json_wide(path); std::printf(",\"metadata\":");file_metadata(path);std::putchar('}');
    }
    wchar_t workdir[32768] = {};
    HRESULT workdir_hr = SUCCEEDED(load_hr) ? link->GetWorkingDirectory(workdir, 32768) : load_hr;
    std::printf("],\"workdir_hresult\":\"0x%08lX\",\"workdir\":", static_cast<unsigned long>(workdir_hr));json_wide(workdir);
    wchar_t drive[4] = {argv[2][0], L':', L'\\', 0};
    wchar_t label[261] = {}; DWORD serial = 0, component_max = 0, fs_flags = 0;
    BOOL volume_ok = GetVolumeInformationW(drive, label, 261, &serial, &component_max, &fs_flags, nullptr, 0);
    DWORD volume_error = volume_ok ? 0 : GetLastError();
    WIN32_FILE_ATTRIBUTE_DATA attributes = {};
    BOOL attrs_ok = GetFileAttributesExW(argv[2], GetFileExInfoStandard, &attributes);
    DWORD attrs_error = attrs_ok ? 0 : GetLastError();
    auto time_value = [](FILETIME time) -> unsigned long long {
        return (static_cast<unsigned long long>(time.dwHighDateTime) << 32) | time.dwLowDateTime;
    };
    std::printf(",\"actual_volume\":{\"ok\":%s,\"error\":%lu,\"drive_type\":%lu,\"serial\":%lu,\"label\":",
        volume_ok ? "true" : "false", static_cast<unsigned long>(volume_error), static_cast<unsigned long>(GetDriveTypeW(drive)), static_cast<unsigned long>(serial));
    json_wide(label);
    std::printf("},\"actual_target_file\":{\"ok\":%s,\"error\":%lu,\"attributes\":%lu,\"size\":%llu,\"creation_filetime\":%llu,\"access_filetime\":%llu,\"write_filetime\":%llu}",
        attrs_ok ? "true" : "false", static_cast<unsigned long>(attrs_error), static_cast<unsigned long>(attributes.dwFileAttributes),
        (static_cast<unsigned long long>(attributes.nFileSizeHigh) << 32) | attributes.nFileSizeLow,
        time_value(attributes.ftCreationTime), time_value(attributes.ftLastAccessTime), time_value(attributes.ftLastWriteTime));
    std::printf(",\"saved_again\":false,\"resolved\":false,\"target_executed\":false,\"arguments_dumped\":false}\n");
    link->Release();CoUninitialize();return FAILED(load_hr) ? 1 : 0;
}
