#!/usr/bin/env python3
"""Optional tiny Windows object checks using the already bundled cross compiler."""
import json
import os
import subprocess
import time
from pathlib import Path

OUT = Path(__file__).resolve().parent
WORKSPACE = OUT.parents[2]
WORK = OUT / 'work/check'
ZIG = WORKSPACE / 'work/palworld-live/research/zig-aarch64-macos-0.15.2/zig'
LUA_HEADERS = WORKSPACE / 'work/palworld-live/research/lua-5.4.8/src'


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    environment = {**os.environ, 'ZIG_LOCAL_CACHE_DIR': str(OUT / 'work/zig-local'),
                   'ZIG_GLOBAL_CACHE_DIR': str(OUT / 'work/zig-global')}
    probes = []
    for name, header, compiler, options in [
        ('windows-boundary', 'helpers/ue4ss/palcraft_utf8_paths.h', 'cc', []),
        ('windows-boundary-cpp', 'helpers/launcher/windows_paths.hpp', 'c++', ['-std=c++17'])
    ]:
        source = WORK / (name + ('.cpp' if compiler == 'c++' else '.c'))
        source.write_text('#include "' + str(OUT / header) + '"\nint main(void) { return 0; }\n')
        probes.append((name, source, compiler, options))
    for name in ('liolib', 'lauxlib', 'loslib', 'loadlib'):
        probes.append((name, OUT / ('candidate/ue4ss/deps/first/LuaRaw/src/' + name + '.c'),
                       'cc', ['-I' + str(LUA_HEADERS)]))
    started = time.monotonic()
    results = []
    for name, source, compiler, options in probes:
        command = [str(ZIG), compiler, '-target', 'x86_64-windows-gnu', *options,
                   '-c', str(source), '-o', str(WORK / (name + '-windows.o'))]
        result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=15)
        results.append({'name': name, 'returncode': result.returncode, 'log': result.stdout + result.stderr})
        if result.returncode:
            break
    report = {'ok': len(results) == len(probes) and all(r['returncode'] == 0 for r in results),
              'target': 'x86_64-windows-gnu', 'objects_only': True, 'linked_dll': False,
              'runtime_executed': False, 'elapsed_seconds': round(time.monotonic() - started, 3), 'checks': results}
    (OUT / 'evidence/windows-object-check.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    raise SystemExit(0 if report['ok'] else 1)


if __name__ == '__main__':
    main()
