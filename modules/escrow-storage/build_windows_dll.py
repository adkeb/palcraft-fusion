#!/usr/bin/env python3
"""One-worker, nice19 Windows x64 cross-build; verify only unless --build is explicit."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess

TASK = Path(__file__).resolve().parent
BASE = TASK.parents[2]
ZIG = BASE / 'work/palworld-live/research/zig-aarch64-macos-0.15.2/zig'
DLL = TASK / 'palcraft_escrow_credit_v1.dll'


def build_command():
    return [str(ZIG), 'build-lib', '-dynamic', '-fno-entry', '-target', 'x86_64-windows-gnu', '-O', 'ReleaseSmall',
            '-j1', '-fcompiler-rt', '-femit-bin=' + str(DLL), '-lc', '-lkernel32', '-cflags', '-std=c++17',
            '-fno-exceptions', '-fno-rtti', '-fno-stack-protector', '--', str(TASK / 'escrow_credit.cpp')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true')
    args = parser.parse_args()
    if hasattr(os, 'nice'):
        os.nice(19)
    command = build_command()
    if args.build:
        subprocess.run(command, cwd=BASE, check=True)
    data = DLL.read_bytes()
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    if data[:2] != b'MZ' or data[pe:pe + 4] != b'PE\0\0' or struct.unpack_from('<H', data, pe + 4)[0] != 0x8664 or struct.unpack_from('<H', data, pe + 24)[0] != 0x20b:
        raise ValueError('DLL is not Windows x64 PE32+')
    details = subprocess.check_output(['/usr/bin/objdump', '-p', str(DLL)], text=True)
    imports = re.findall(r'DLL Name: (\S+)', details)
    exports = re.findall(r'^\s+\d+\s+0x[0-9a-f]+\s+(\S+)\s*$', details, re.M)
    if exports != ['palcraft_escrow_credit_v1']:
        raise ValueError('Unexpected native export list: ' + repr(exports))
    if not imports or any(name.lower() != 'kernel32.dll' and not name.lower().startswith('api-ms-win-crt-') for name in imports):
        raise ValueError('Unexpected DLL runtime dependency')
    sources = [TASK / 'escrow_credit.cpp', TASK / 'credit_abi_support.hpp', TASK / 'credit_fingerprints.hpp']
    report = {'status': 'windows_x64_dll_built_and_static_verified_runtime_pending',
              'updated_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'dll': str(DLL.relative_to(BASE)), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
              'target': 'x86_64-windows-gnu', 'format': 'PE32+', 'exports': exports, 'imports': imports,
              'compiler': subprocess.check_output([str(ZIG), 'version'], text=True).strip(),
              'build_command': command, 'jobs': 1, 'priority': 'nice19', 'power_mode': 'night_low_power',
              'no_deployment': True, 'no_rpc_or_game_process': True, 'live_produce_verified': False,
              'system_runtime': 'Windows UCRT API sets plus KERNEL32; no Lua/UE4SS C++ ABI library dependency',
              'source_sha256': {str(path.relative_to(BASE)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}}
    (TASK / 'windows-build-evidence.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    (TASK / 'windows-pe-inspection.txt').write_text(details)
    print(json.dumps({key: report[key] for key in ['status', 'dll', 'bytes', 'sha256', 'exports', 'jobs', 'priority', 'live_produce_verified']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
