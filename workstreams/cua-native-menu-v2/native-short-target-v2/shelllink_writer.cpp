// Only creates and reads a real ShellLink. It has no target-execution API.
#define UNICODE
#define _UNICODE
#define NOMINMAX
#include <windows.h>
#include <shobjidl.h>
#include <shlguid.h>
#include <objbase.h>
#include <objidl.h>
#include <cstdio>
#include <cstring>
#include <cwchar>

static int failure(const char* stage, HRESULT hr, DWORD system_error = 0) {
    std::printf("{\"schema\":1,\"backend\":\"IShellLinkW\",\"stage\":\"%s\","
                "\"hresult\":\"0x%08lX\",\"win32_error\":%lu,\"target_executed\":false}\n",
                stage, static_cast<unsigned long>(hr), static_cast<unsigned long>(system_error));
    return 1;
}

static HRESULT create_object(IShellLinkW** link) {
    return CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                            IID_IShellLinkW, reinterpret_cast<void**>(link));
}

static bool file_identity(const wchar_t* path, BY_HANDLE_FILE_INFORMATION* info, DWORD* error) {
    HANDLE file = CreateFileW(path, FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) { *error = GetLastError(); return false; }
    BOOL ok = GetFileInformationByHandle(file, info);
    *error = ok ? 0 : GetLastError(); CloseHandle(file);
    if (!ok || (info->nFileIndexHigh == 0 && info->nFileIndexLow == 0)) return false;
    return true;
}

static bool same_file(const BY_HANDLE_FILE_INFORMATION& first, const BY_HANDLE_FILE_INFORMATION& second) {
    return first.dwVolumeSerialNumber == second.dwVolumeSerialNumber &&
           first.nFileIndexHigh == second.nFileIndexHigh && first.nFileIndexLow == second.nFileIndexLow;
}

static int create_and_verify(wchar_t** fields) {
    DWORD target_attrs = GetFileAttributesW(fields[1]);
    if (target_attrs == INVALID_FILE_ATTRIBUTES || (target_attrs & FILE_ATTRIBUTE_DIRECTORY)) {
        DWORD error = GetLastError();
        return failure("target_file_attributes", HRESULT_FROM_WIN32(error ? error : ERROR_FILE_NOT_FOUND), error);
    }
    BY_HANDLE_FILE_INFORMATION original_info = {}, effective_info = {};
    DWORD identity_error = 0;
    if (!file_identity(fields[1], &original_info, &identity_error))
        return failure("original_target_file_identity", E_UNEXPECTED, identity_error);
    wchar_t short_target[32768] = {};
    const wchar_t* effective_target = fields[1];
    bool needs_ascii_alias = false;
    for (const wchar_t* p = fields[1]; *p; ++p) if (*p > 127) needs_ascii_alias = true;
    if (needs_ascii_alias) {
        DWORD count = GetShortPathNameW(fields[1], short_target, 32768);
        if (count == 0 || count >= 32768) return failure("GetShortPathNameW", E_UNEXPECTED, GetLastError());
        for (const wchar_t* p = short_target; *p; ++p)
            if (*p > 127) return failure("short_target_not_ASCII", E_UNEXPECTED);
        effective_target = short_target;
    }
    if (!file_identity(effective_target, &effective_info, &identity_error) || !same_file(original_info, effective_info))
        return failure("effective_target_not_same_original_file", E_UNEXPECTED, identity_error);
    IShellLinkW* link = nullptr;
    HRESULT hr = create_object(&link);
    if (FAILED(hr)) return failure("CoCreateInstance_IShellLinkW", hr);
    const char* stage = "SetPath";
    hr = link->SetPath(effective_target);
    if (SUCCEEDED(hr)) { stage = "SetArguments"; hr = link->SetArguments(fields[2]); }
    if (SUCCEEDED(hr)) { stage = "SetWorkingDirectory"; hr = link->SetWorkingDirectory(fields[3]); }
    if (SUCCEEDED(hr)) { stage = "SetDescription"; hr = link->SetDescription(fields[4]); }
    if (SUCCEEDED(hr)) { stage = "SetShowCmd"; hr = link->SetShowCmd(SW_SHOWNORMAL); }
    IPersistFile* persist = nullptr;
    if (SUCCEEDED(hr)) { stage = "QueryInterface_IPersistFile"; hr = link->QueryInterface(IID_IPersistFile, reinterpret_cast<void**>(&persist)); }
    if (SUCCEEDED(hr)) { stage = "IPersistFile_Save"; hr = persist->Save(fields[0], TRUE); }
    if (persist) persist->Release();
    link->Release();
    if (FAILED(hr)) return failure(stage, hr);

    // Load in a fresh COM object. No Resolve(), ShellExecute(), or target process.
    link = nullptr; persist = nullptr;
    hr = create_object(&link);
    if (FAILED(hr)) return failure("readback_CoCreateInstance", hr);
    hr = link->QueryInterface(IID_IPersistFile, reinterpret_cast<void**>(&persist));
    if (SUCCEEDED(hr)) hr = persist->Load(fields[0], STGM_READ);
    if (persist) persist->Release();
    if (FAILED(hr)) { link->Release(); return failure("readback_IPersistFile_Load", hr); }
    wchar_t buffer[32768] = {};
    hr = link->GetPath(buffer, 32768, nullptr, SLGP_RAWPATH);
    if (FAILED(hr)) { link->Release(); return failure("GetPath_readback_API", hr); }
    BY_HANDLE_FILE_INFORMATION readback_info = {};
    if (!file_identity(buffer, &readback_info, &identity_error) || !same_file(original_info, readback_info)) {
        link->Release(); return failure("GetPath_readback_not_same_original_file", E_UNEXPECTED, identity_error);
    }
    buffer[0] = 0; hr = link->GetArguments(buffer, 32768);
    if (FAILED(hr) || std::wcscmp(buffer, fields[2]) != 0) { link->Release(); return failure("readback_arguments", FAILED(hr) ? hr : E_UNEXPECTED); }
    buffer[0] = 0; hr = link->GetWorkingDirectory(buffer, 32768);
    if (FAILED(hr) || _wcsicmp(buffer, fields[3]) != 0) { link->Release(); return failure("readback_workdir", FAILED(hr) ? hr : E_UNEXPECTED); }
    buffer[0] = 0; hr = link->GetDescription(buffer, 32768);
    if (FAILED(hr) || std::wcscmp(buffer, fields[4]) != 0) { link->Release(); return failure("readback_description", FAILED(hr) ? hr : E_UNEXPECTED); }
    link->Release();
    WIN32_FILE_ATTRIBUTE_DATA attributes = {};
    if (!GetFileAttributesExW(fields[0], GetFileExInfoStandard, &attributes) || attributes.nFileSizeHigh != 0 || attributes.nFileSizeLow < 76)
        return failure("readback_link_size", E_UNEXPECTED, GetLastError());
    std::printf("{\"schema\":1,\"backend\":\"IShellLinkW\",\"stage\":\"verified\","
                "\"hresult\":\"0x00000000\",\"link_bytes\":%lu,\"readback_target\":true,"
                "\"readback_arguments\":true,\"readback_workdir\":true,\"readback_description\":true,"
                "\"same_original_file\":true,\"effective_target_source\":\"%s\","
                "\"GetPath_hresult\":\"0x00000000\",\"target_executed\":false}\n",
                static_cast<unsigned long>(attributes.nFileSizeLow), needs_ascii_alias ? "GetShortPathNameW" : "original_ASCII_target");
    return 0;
}

int wmain(int argc, wchar_t** argv) {
    if (argc != 2) return failure("request_argument_count", E_INVALIDARG);
    HANDLE file = CreateFileW(argv[1], GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return failure("request_open", HRESULT_FROM_WIN32(GetLastError()), GetLastError());
    LARGE_INTEGER size = {};
    if (!GetFileSizeEx(file, &size) || size.QuadPart < 12 || size.QuadPart > 262144) {
        CloseHandle(file); return failure("request_size", E_INVALIDARG);
    }
    BYTE* data = static_cast<BYTE*>(HeapAlloc(GetProcessHeap(), 0, static_cast<SIZE_T>(size.QuadPart)));
    if (!data) { CloseHandle(file); return failure("request_allocation", E_OUTOFMEMORY); }
    DWORD read = 0;
    BOOL read_ok = ReadFile(file, data, static_cast<DWORD>(size.QuadPart), &read, nullptr);
    DWORD read_error = GetLastError(); CloseHandle(file);
    if (!read_ok || read != size.QuadPart) { HeapFree(GetProcessHeap(), 0, data); return failure("request_read", HRESULT_FROM_WIN32(read_error ? read_error : ERROR_READ_FAULT), read_error); }
    DWORD count = 0; std::memcpy(&count, data + 8, 4);
    if (std::memcmp(data, "PCSLNK01", 8) != 0 || count != 5) { HeapFree(GetProcessHeap(), 0, data); return failure("request_header", E_INVALIDARG); }
    wchar_t* fields[5] = {};
    DWORD offset = 12;
    bool valid = true;
    for (unsigned i = 0; i < 5 && valid; ++i) {
        if (offset + 4 > read) { valid = false; break; }
        DWORD units = 0; std::memcpy(&units, data + offset, 4); offset += 4;
        if (units > 32767 || offset + units * 2 > read) { valid = false; break; }
        fields[i] = static_cast<wchar_t*>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, (units + 1) * 2));
        if (!fields[i]) { valid = false; break; }
        std::memcpy(fields[i], data + offset, units * 2); offset += units * 2;
        for (DWORD j = 0; j < units; ++j) if (fields[i][j] == 0) valid = false;
    }
    HeapFree(GetProcessHeap(), 0, data);
    if (offset != read || !fields[0] || !fields[1] || !fields[3] || !fields[0][0] || !fields[1][0] || !fields[3][0]) valid = false;
    int result = 1;
    if (!valid) result = failure("request_UTF16_records", E_INVALIDARG);
    else {
        HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        if (FAILED(hr)) result = failure("CoInitializeEx", hr);
        else { result = create_and_verify(fields); CoUninitialize(); }
    }
    for (wchar_t* field : fields) if (field) HeapFree(GetProcessHeap(), 0, field);
    return result;
}
