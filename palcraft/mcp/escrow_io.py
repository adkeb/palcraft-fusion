"""Read and force exact source bytes without changing them.

Windows FlushFileBuffers needs GENERIC_WRITE. Opening a read-only CRT fd and
calling fsync is not sufficient. Use an existing shared read/write HANDLE, with
delete sharing so game atomic replacement is not blocked; never write or truncate.
"""
import os
from pathlib import Path


def _windows_fd(path, api=None, crt=None):
    import ctypes
    from ctypes import wintypes
    if api is None:
        api = ctypes.WinDLL('kernel32', use_last_error=True)
    if crt is None:
        import msvcrt as crt
    create = api.CreateFileW
    create.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p,
                       wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    create.restype = wintypes.HANDLE
    close = api.CloseHandle
    close.argtypes = [wintypes.HANDLE]
    close.restype = wintypes.BOOL
    # GENERIC_READ|GENERIC_WRITE, SHARE_READ|SHARE_WRITE|SHARE_DELETE,
    # OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL. No creation/truncation/data write.
    handle = create(str(Path(path).resolve()), 0xc0000000, 7, None, 3, 0x80, None)
    if handle == ctypes.c_void_p(-1).value or handle == -1:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        return crt.open_osfhandle(handle, os.O_RDWR | getattr(os, 'O_BINARY', 0))
    except BaseException:
        close(handle)
        raise


def read_and_force(path, max_bytes=None, system=None):
    path = Path(path)
    if (os.name if system is None else system) == 'nt':
        fd = _windows_fd(path)
        file = os.fdopen(fd, 'r+b')
    else:
        file = path.open('rb')
    with file:
        data = file.read() if max_bytes is None else file.read(max_bytes + 1)
        if max_bytes is not None and len(data) > max_bytes:
            raise ValueError('Source file exceeds verification size limit')
        os.fsync(file.fileno())
    return data
