// Owns only the copied personal Palworld process tree in one Win32 job.
// No task/service/server API, no global process-name termination, no RPC.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "windows_paths.hpp"
#include <algorithm>
#include <cwchar>
#include <iostream>
#include <string>
#include <vector>

static std::wstring quote(const std::wstring& arg) {
    std::wstring out = L"\"";
    unsigned backslashes = 0;
    for (wchar_t c : arg) {
        if (c == L'\\') { ++backslashes; continue; }
        if (c == L'\"') { out.append(backslashes * 2 + 1, L'\\'); out += c; }
        else { out.append(backslashes, L'\\'); out += c; }
        backslashes = 0;
    }
    out.append(backslashes * 2, L'\\');
    return out + L"\"";
}

static std::wstring read_small(const std::wstring& path) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return L"";
    char bytes[128]{}; DWORD count = 0;
    ReadFile(file, bytes, sizeof(bytes) - 1, &count, nullptr); CloseHandle(file);
    return std::wstring(bytes, bytes + count);
}

static bool fresh(const std::wstring& path, unsigned age) {
    WIN32_FILE_ATTRIBUTE_DATA data{};
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) return false;
    FILETIME now{}; GetSystemTimeAsFileTime(&now);
    ULARGE_INTEGER a{}, b{};
    a.LowPart = now.dwLowDateTime; a.HighPart = now.dwHighDateTime;
    b.LowPart = data.ftLastWriteTime.dwLowDateTime; b.HighPart = data.ftLastWriteTime.dwHighDateTime;
    return b.QuadPart <= a.QuadPart + 20000000ULL && a.QuadPart <= b.QuadPart + age * 10000000ULL;
}

static std::vector<DWORD> job_pids(HANDLE job) {
    std::vector<unsigned char> storage(sizeof(JOBOBJECT_BASIC_PROCESS_ID_LIST) + 4096 * sizeof(ULONG_PTR));
    auto list = reinterpret_cast<JOBOBJECT_BASIC_PROCESS_ID_LIST*>(storage.data());
    if (!QueryInformationJobObject(job, JobObjectBasicProcessIdList, list, static_cast<DWORD>(storage.size()), nullptr))
        return {};
    std::vector<DWORD> pids;
    for (DWORD i = 0; i < list->NumberOfProcessIdsInList; ++i) pids.push_back(static_cast<DWORD>(list->ProcessIdList[i]));
    return pids;
}

static BOOL CALLBACK close_window(HWND window, LPARAM context) {
    auto& pids = *reinterpret_cast<std::vector<DWORD>*>(context);
    DWORD pid = 0; GetWindowThreadProcessId(window, &pid);
    if (std::find(pids.begin(), pids.end(), pid) != pids.end()) PostMessageW(window, WM_CLOSE, 0, 0);
    return TRUE;
}

static void write_status(const std::wstring& path, const char* phase, DWORD exit_code = 0,
                         DWORD primary_pid = 0, bool primary_alive = false, DWORD job_active = 0) {
    std::string data = "{\"schema\":1,\"phase\":\"" + std::string(phase) + "\",\"exit_code\":" + std::to_string(exit_code) +
        ",\"primary_pid\":" + std::to_string(primary_pid) + ",\"primary_alive\":" + (primary_alive ? "true" : "false") +
        ",\"job_active_processes\":" + std::to_string(job_active) + "}\n";
    const auto temp = path + L".tmp";
    HANDLE f = CreateFileW(temp.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return;
    DWORD count = 0; WriteFile(f, data.data(), static_cast<DWORD>(data.size()), &count, nullptr); FlushFileBuffers(f); CloseHandle(f);
    MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
}

int wmain(int argc, wchar_t** argv) {
    std::wstring root, control, token; int fps = 15; bool mute = false, dry = false, shipping = false;
    for (int i = 1; i < argc; ++i) {
        std::wstring key = argv[i];
        if (key == L"--mute") mute = true;
        else if (key == L"--shipping") shipping = true;
        else if (key == L"--dry-run") dry = true;
        else if (i + 1 < argc && key == L"--root") root = argv[++i];
        else if (i + 1 < argc && key == L"--control") control = argv[++i];
        else if (i + 1 < argc && key == L"--token") token = argv[++i];
        else if (i + 1 < argc && key == L"--fps") fps = _wtoi(argv[++i]);
        else { std::cerr << "HOST_ARGS: unsupported argument\n"; return 64; }
    }
    root = palcraft_paths::normalize(root);
    if (root.empty() || !palcraft_paths::same(control, palcraft_paths::join(root, L".palcraft\\control")) ||
        read_small(palcraft_paths::join(root, L".palcraft\\owner.json")).find(L"palcraft-player-owned-root") == std::wstring::npos ||
        token.size() != 32 || token.find_first_not_of(L"0123456789abcdef") != std::wstring::npos || fps < 10 || fps > 120) {
        std::cerr << "HOST_SCOPE: only this owned installation and token are supported\n"; return 64;
    }
    const auto game_root = root + L"\\PalCraft-Client";
    const auto game = game_root + (shipping ? L"\\Pal\\Binaries\\Win64\\Palworld-Win64-Shipping.exe" : L"\\Palworld.exe");
    const auto user = root + L"/PalCraft-Client-User/";
    std::wstring command = quote(game) + (shipping ? L" Pal -nosteam" : L"") + L" -windowed -ResX=1280 -ResY=720 -ForceRes -NoVSync " +
        quote(L"-UserDir=" + user) + L" " + quote(L"-ExecCmds=t.MaxFPS " + std::to_wstring(fps));
    if (mute) command += L" -nosound";
    if (dry) { std::wcout << L"HOST_DRY_RUN " << command << L"\n"; return 0; }
    const auto heartbeat = control + L"\\" + token + L".heartbeat";
    const auto request = control + L"\\" + token + L".stop";
    const auto status = control + L"\\" + token + L".host.json";
    if (!fresh(heartbeat, 15)) { std::cerr << "HOST_LEASE: supervisor heartbeat missing\n"; return 65; }
    SetEnvironmentVariableW(L"SteamAppId", L"1623730");
    if (!SetEnvironmentVariableW(L"PALCRAFT_WINDOWS_ROOT", root.c_str())) {
        std::cerr << "HOST_ROOT: environment failed\n"; return 64;
    }
    HANDLE job = CreateJobObjectW(nullptr, nullptr);
    if (!job) { std::cerr << "HOST_JOB: create failed\n"; return 66; }
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) {
        CloseHandle(job); std::cerr << "HOST_JOB: limit failed\n"; return 66;
    }
    STARTUPINFOW startup{}; startup.cb = sizeof(startup); PROCESS_INFORMATION process{};
    std::vector<wchar_t> buffer(command.begin(), command.end()); buffer.push_back(0);
    if (!CreateProcessW(game.c_str(), buffer.data(), nullptr, nullptr, FALSE, CREATE_SUSPENDED,
                         nullptr, game_root.c_str(), &startup, &process)) {
        CloseHandle(job); std::cerr << "HOST_GAME: create failed " << GetLastError() << "\n"; return 67;
    }
    if (!AssignProcessToJobObject(job, process.hProcess)) {
        TerminateProcess(process.hProcess, 68); CloseHandle(process.hThread); CloseHandle(process.hProcess); CloseHandle(job);
        std::cerr << "HOST_JOB: assignment failed; own suspended game cancelled\n"; return 68;
    }
    ResumeThread(process.hThread); CloseHandle(process.hThread);
    write_status(status, "running", 0, process.dwProcessId, true, 1);
    std::vector<std::pair<DWORD, HANDLE>> children{{process.dwProcessId, process.hProcess}};
    ULONGLONG closing_at = 0, last_close = 0, last_status = 0; bool owner_gone = false, forced = false;
    DWORD result = 0;
    for (;;) {
        const DWORD primary_wait = WaitForSingleObject(process.hProcess, 0);
        const bool primary_alive = primary_wait == WAIT_TIMEOUT;
        if (primary_wait == WAIT_FAILED) {
            std::cerr << "HOST_PRIMARY_QUERY_FAILED " << GetLastError() << "\n"; result = 72; break;
        }
        if (primary_wait == WAIT_OBJECT_0 && shipping) {
            if (!GetExitCodeProcess(process.hProcess, &result)) result = 72;
            std::cout << "HOST_PRIMARY_EXIT pid=" << process.dwProcessId << " code=" << result << "\n";
            // Shipping is the actual game. Wine may retain stale ActiveProcesses
            // accounting after its handle is signaled; never wait on that ghost.
            break;
        }
        auto pids = job_pids(job);
        for (DWORD pid : pids) {
            if (std::any_of(children.begin(), children.end(), [pid](const auto& row) { return row.first == pid; })) continue;
            HANDLE child = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid);
            BOOL belongs = FALSE;
            if (child && IsProcessInJob(child, job, &belongs) && belongs) children.emplace_back(pid, child);
            else if (child) CloseHandle(child);
        }
        JOBOBJECT_BASIC_ACCOUNTING_INFORMATION account{};
        if (!QueryInformationJobObject(job, JobObjectBasicAccountingInformation, &account, sizeof(account), nullptr)) {
            std::cerr << "HOST_JOB: accounting failed\n"; result = 69; break;
        }
        if (account.ActiveProcesses == 0) break;
        const auto mode = read_small(request);
        const auto now = GetTickCount64();
        if (now - last_status > 1000) {
            write_status(status, closing_at ? "closing" : "running", 0, process.dwProcessId, primary_alive, account.ActiveProcesses);
            last_status = now;
        }
        owner_gone = owner_gone || !fresh(heartbeat, 15);
        if (mode.find(L"force") == 0) {
            TerminateJobObject(job, 70); forced = true; result = 70; break;
        }
        if (owner_gone || mode.find(L"close") == 0) {
            if (!closing_at) { closing_at = now; write_status(status, "closing", 0, process.dwProcessId, primary_alive, account.ActiveProcesses); }
            if (now - last_close > 2000) { EnumWindows(close_window, reinterpret_cast<LPARAM>(&pids)); last_close = now; }
            // An explicit normal stop waits indefinitely for saving. A dead owner cannot leave an unbounded orphan.
            if (owner_gone && now - closing_at > 60000) {
                std::cerr << "HOST_OWNER_EXIT: grace period expired; closing only this job\n";
                TerminateJobObject(job, 71); forced = true; result = 71; break;
            }
        }
        Sleep(150);
    }
    if (!forced) {
        for (const auto& child : children) {
            DWORD exit_code = 0;
            if (GetExitCodeProcess(child.second, &exit_code) && exit_code != STILL_ACTIVE && exit_code != 0) result = exit_code;
        }
    }
    for (const auto& child : children) CloseHandle(child.second);
    CloseHandle(job);
    write_status(status, result ? "failed" : "stopped", result, process.dwProcessId, false, 0);
    std::cout << "HOST_EXIT " << result << "\n";
    return static_cast<int>(result);
}
