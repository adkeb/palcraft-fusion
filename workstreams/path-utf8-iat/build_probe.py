#!/usr/bin/env python3
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
from add_dependency import apply

ROOT = Path(__file__).resolve().parent
TASK = ROOT.parents[1]
WORKSPACE = TASK.parents[2]
PIN = '2281fa311e417b1dfddedbcd49972d764fddb244'
UPSTREAM = ROOT.parent / 'ue4ss-2281fa31-utf8-v1/source'
ZIG = WORKSPACE / 'work/palworld-live/research/zig-aarch64-macos-0.15.2/zig'


def main():
    os.nice(19)
    pristine = ROOT / 'work/pristine-LuaRaw'
    files = subprocess.check_output(['git', '-C', str(UPSTREAM), 'ls-tree', '-r', '--name-only', PIN,
                                     'deps/first/LuaRaw'], text=True).splitlines()
    for path in files:
        relative = Path(path).relative_to('deps/first/LuaRaw')
        target = pristine / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(subprocess.check_output(['git', '-C', str(UPSTREAM), 'show', PIN + ':' + path]))
    names = re.findall(r'"(src/[^"]+\.c)"', (pristine / 'xmake.lua').read_text())
    assert len(names) == 33
    artifacts = ROOT / 'artifacts'
    env = {**os.environ, 'ZIG_LOCAL_CACHE_DIR': str(ROOT / 'work/zig-local'),
           'ZIG_GLOBAL_CACHE_DIR': str(TASK / 'work/zig-global')}
    common = [str(ZIG), '-target', 'x86_64-windows-gnu', '-O', 'ReleaseSmall', '-j1',
              '-fcompiler-rt', '-lc', '-lkernel32', '-I' + str(pristine / 'src'), '-I' + str(pristine / 'include')]
    commands = [
        [common[0], 'build-lib', '-dynamic', *common[1:],
         '-femit-bin=' + str(artifacts / 'pristine/UE4SS.dll'), '-cflags', '-std=c11',
         '-DLUA_BUILD_AS_DLL', '--', *[str(pristine / n) for n in names], str(ROOT / 'fixture_core.c')],
        [common[0], 'build-exe', *common[1:], '-municode',
         '-femit-bin=' + str(artifacts / 'PcUtf8EarlyProbe.exe'), str(ROOT / 'fixture_host.c')]
    ]
    for index, command in enumerate(commands):
        Path(command[next(i for i, s in enumerate(command) if s.startswith('-femit-bin='))].split('=', 1)[1]).parent.mkdir(parents=True, exist_ok=True)
        print('Building same-pin unpatched initializer fixture ' + str(index + 1), flush=True)
        with (ROOT / 'evidence' / ('fixture-build-' + str(index) + '.log')).open('w') as log:
            result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            print((ROOT / 'evidence' / ('fixture-build-' + str(index) + '.log')).read_text())
            raise SystemExit(result.returncode)
    before = artifacts / 'pristine/UE4SS.dll'
    report = apply(before, artifacts / 'fixture/ue4ss/UE4SS.dll', hashlib.sha256(before.read_bytes()).hexdigest())
    (ROOT / 'evidence/fixture-import-extension.json').write_text(json.dumps(report, indent=2) + '\n')
    (ROOT / 'evidence/fixture-commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    print(json.dumps({'fixture_added_import': report['candidate_sha256'], 'game_or_actual_core_executed': False}))


if __name__ == '__main__':
    main()
