#pragma once
#include <cstddef>
#include <cstdint>
#define __declspec(x)
#define __fastcall
#define WINAPI
using DWORD=uint32_t;using BOOL=int;using SIZE_T=size_t;
using HANDLE=void*;using HINSTANCE=void*;using LPVOID=void*;
struct FILETIME {DWORD dwLowDateTime,dwHighDateTime;};
struct LARGE_INTEGER {int64_t QuadPart;};
#define INVALID_HANDLE_VALUE ((HANDLE)-1)
#define GENERIC_WRITE 1
#define GENERIC_READ 2
#define FILE_SHARE_READ 4
#define CREATE_ALWAYS 8
#define OPEN_EXISTING 16
#define FILE_ATTRIBUTE_NORMAL 32
#define MOVEFILE_REPLACE_EXISTING 64
#define MOVEFILE_WRITE_THROUGH 128
#define TRUE 1
HANDLE GetCurrentProcess();
BOOL ReadProcessMemory(HANDLE,const void*,void*,SIZE_T,SIZE_T*);
void GetSystemTimeAsFileTime(FILETIME*);
DWORD GetModuleFileNameW(void*,wchar_t*,DWORD);
HANDLE GetModuleHandleW(void*);
DWORD GetCurrentThreadId();
HANDLE CreateFileW(const wchar_t*,DWORD,DWORD,void*,DWORD,DWORD,void*);
BOOL ReadFile(HANDLE,void*,DWORD,DWORD*,void*);
BOOL GetFileSizeEx(HANDLE,LARGE_INTEGER*);
BOOL WriteFile(HANDLE,const void*,DWORD,DWORD*,void*);
BOOL FlushFileBuffers(HANDLE);
BOOL CloseHandle(HANDLE);
BOOL MoveFileExW(const wchar_t*,const wchar_t*,DWORD);
void* test_native_lookup(void*,const void*);
