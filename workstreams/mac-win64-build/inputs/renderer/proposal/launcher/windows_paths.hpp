#pragma once
// The launcher passes a logical Windows root. No host paths or drive mutations.
#include <string>
#include <cwctype>
#include <utility>
#if defined(_WIN32)
#include <windows.h>
#endif

namespace palcraft_paths {
inline std::wstring normalize(std::wstring path) {
    for (auto& c : path) if (c == L'/') c = L'\\';
    while (!path.empty() && path.back() == L'\\') path.pop_back();
    if (path.size() < 4 || !((path[0] >= L'A' && path[0] <= L'Z') ||
        (path[0] >= L'a' && path[0] <= L'z')) || path[1] != L':' || path[2] != L'\\') return {};
    for (size_t start = 3; start < path.size();) {
        auto end = path.find(L'\\', start);
        if (end == std::wstring::npos) end = path.size();
        auto part = path.substr(start, end - start);
        if (part.empty() || part == L"." || part == L".." || part.back() == L' ' || part.back() == L'.' ||
            part.find_first_of(L"<>:\"|?*") != std::wstring::npos) return {};
        for (auto c : part) if (c < 32) return {};
        auto device = part.substr(0, part.find(L'.'));
        for (auto& c : device) c = static_cast<wchar_t>(std::towupper(c));
        if (device == L"CON" || device == L"PRN" || device == L"AUX" || device == L"NUL" ||
            (device.size() == 4 && (device.substr(0, 3) == L"COM" || device.substr(0, 3) == L"LPT") &&
             device[3] >= L'1' && device[3] <= L'9')) return {};
        start = end + 1;
    }
    path[0] = static_cast<wchar_t>(std::towupper(path[0]));
    return path;
}
inline std::wstring join(const std::wstring& root, const wchar_t* relative) {
    return root.empty() ? std::wstring{} : root + L"\\" + relative;
}
inline std::wstring expected_executable(const std::wstring& root, bool server) {
    return join(root, server ? L"BridgeLab\\Pal\\Binaries\\Win64\\PalServer-Win64-Shipping-Cmd.exe" :
                              L"PalCraft-Client\\Pal\\Binaries\\Win64\\Palworld-Win64-Shipping.exe");
}
#if defined(_WIN32)
inline std::wstring read_root() {
    SetLastError(ERROR_SUCCESS);
    DWORD size = GetEnvironmentVariableW(L"PALCRAFT_WINDOWS_ROOT", nullptr, 0);
    if (!size) return GetLastError() == ERROR_ENVVAR_NOT_FOUND ? L"D:\\PalworldServer-LAN" : std::wstring{};
    std::wstring value(size, L'\0');
    DWORD used = GetEnvironmentVariableW(L"PALCRAFT_WINDOWS_ROOT", value.data(), size);
    if (!used || used >= size) return {};
    value.resize(used);
    return normalize(value);
}
inline const std::wstring& root() { static const auto value = read_root(); return value; }
inline std::wstring canonical(const std::wstring& path) {
    if (path.empty()) return {};
    DWORD size = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
    if (!size) return {};
    std::wstring out(size, L'\0');
    DWORD used = GetFullPathNameW(path.c_str(), size, out.data(), nullptr);
    if (!used || used >= size) return {};
    out.resize(used);
    size = GetLongPathNameW(out.c_str(), nullptr, 0);
    if (size) {
        std::wstring expanded(size, L'\0');
        used = GetLongPathNameW(out.c_str(), expanded.data(), size);
        if (used && used < size) { expanded.resize(used); out = std::move(expanded); }
    }
    return normalize(out);
}
inline bool same(const std::wstring& a, const std::wstring& b) {
    auto left = canonical(a), right = canonical(b);
    return !left.empty() && !right.empty() && CompareStringOrdinal(left.c_str(), -1, right.c_str(), -1, TRUE) == CSTR_EQUAL;
}
enum class Role { none, client, server };
inline Role executable_role() {
    static const Role role = [] {
        std::wstring exe(32768, L'\0');
        DWORD used = GetModuleFileNameW(nullptr, exe.data(), static_cast<DWORD>(exe.size()));
        if (!used || used >= exe.size()) return Role::none;
        exe.resize(used);
        if (same(exe, expected_executable(root(), false))) return Role::client;
        if (same(exe, expected_executable(root(), true))) return Role::server;
        return Role::none;
    }();
    return role;
}
inline std::wstring io_root() {
    switch (executable_role()) {
        case Role::client: return join(root(), L"PalCraft-Dev\\bridge\\");
        case Role::server: return join(root(), L"BridgeLab\\rpc\\");
        default: return {};
    }
}
inline std::wstring bridge_file(const wchar_t* name) {
    return executable_role() == Role::none ? std::wstring{} : join(root(), (L"PalCraft-Dev\\bridge\\" + std::wstring(name)).c_str());
}
inline std::wstring journal_file(const wchar_t* name) {
    return executable_role() == Role::none ? std::wstring{} : join(root(), (L"BridgeLab\\rpc\\" + std::wstring(name)).c_str());
}
#endif
} // namespace palcraft_paths
