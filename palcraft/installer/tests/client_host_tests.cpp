#define wmain palcraft_host_entry
#include "../../launcher/client_host_v1.cpp"
#undef wmain
#include <cassert>

static PROCESS_INFORMATION fake_process(const std::wstring& self) {
    std::wstring command = quote(self) + L" --fake-child";
    std::vector<wchar_t> buffer(command.begin(), command.end()); buffer.push_back(0);
    STARTUPINFOW start{}; start.cb = sizeof(start); PROCESS_INFORMATION info{};
    assert(CreateProcessW(self.c_str(), buffer.data(), nullptr, nullptr, FALSE,
                          CREATE_SUSPENDED | CREATE_NO_WINDOW, nullptr, nullptr, &start, &info));
    return info;
}
int wmain(int argc, wchar_t** argv) {
    if (argc == 2 && !wcscmp(argv[1], L"--fake-child")) { Sleep(30000); return 0; }
    assert(quote(L"a b") == L"\"a b\"");
    assert(quote(L"abc\\") == L"\"abc\\\\\"");
    assert(quote(L"a\"b") == L"\"a\\\"b\"");
    wchar_t filename[32768]{}; GetModuleFileNameW(nullptr, filename, 32768);
    const std::wstring self(filename);
    auto child = fake_process(self), unrelated = fake_process(self);
    HANDLE job = CreateJobObjectW(nullptr, nullptr); assert(job);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    assert(SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits)));
    assert(AssignProcessToJobObject(job, child.hProcess));
    ResumeThread(child.hThread); ResumeThread(unrelated.hThread);
    auto pids = job_pids(job);
    assert(std::find(pids.begin(), pids.end(), child.dwProcessId) != pids.end());
    assert(std::find(pids.begin(), pids.end(), unrelated.dwProcessId) == pids.end());
    assert(TerminateJobObject(job, 71));
    assert(WaitForSingleObject(child.hProcess, 5000) == WAIT_OBJECT_0);
    DWORD code = 0; assert(GetExitCodeProcess(unrelated.hProcess, &code)); assert(code == STILL_ACTIVE);
    TerminateProcess(unrelated.hProcess, 0); WaitForSingleObject(unrelated.hProcess, 5000);
    CloseHandle(child.hThread); CloseHandle(child.hProcess);
    CloseHandle(unrelated.hThread); CloseHandle(unrelated.hProcess); CloseHandle(job);
    std::cout << "{\"ok\":true,\"quote\":true,\"job_owned_child_terminated\":true,\"unrelated_process_survived\":true}\n";
    return 0;
}
