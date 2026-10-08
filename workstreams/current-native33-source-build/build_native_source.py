#!/usr/bin/env python3
"""Build all four native translation units from a supplied source tree.

No existing project object/DLL is an input. Output directories must be new.
Only a compiler and its standard Windows libraries/headers are required.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

UNITS = ('palcraft', 'controls', 'ws', 'compositor')
COMPILE_FLAGS = ['-target', 'x86_64-windows-gnu', '-std=c++17', '-O2', '-DNOMINMAX',
                 '-Wall', '-Wextra', '-Wno-unknown-attributes', '-fno-lto']
LINK_FLAGS = ['-target', 'x86_64-windows-gnu', '-shared', '-fno-lto']
LIBRARIES = ['-lws2_32', '-luser32', '-ld3d11', '-ldxgi']

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def build(source_root, zig, output):
    source_root, zig, output = Path(source_root).resolve(), Path(zig).resolve(), Path(output).absolute()
    if not zig.is_file(): raise ValueError('Provide an existing Zig executable')
    required = [source_root / 'render' / (name + '.cpp') for name in UNITS]
    required += [source_root / 'launcher/windows_paths.hpp', source_root / 'render/sdk/reshade.hpp']
    if not all(path.is_file() for path in required):
        raise ValueError('--source-root must contain render/{palcraft,controls,ws,compositor}.cpp, SDK and launcher/windows_paths.hpp')
    work = output.parent / (output.name + '.source-build')
    if output.exists() or work.exists(): raise ValueError('Use a new output path; preserve previous results')
    output.parent.mkdir(parents=True, exist_ok=True)
    work.mkdir(); objects = work / 'objects'; objects.mkdir()
    env = dict(os.environ)
    env['ZIG_GLOBAL_CACHE_DIR'] = str(work / 'cache/global')
    env['ZIG_LOCAL_CACHE_DIR'] = str(work / 'cache/local')
    if hasattr(os, 'nice'): os.nice(max(0, 19 - os.getpriority(os.PRIO_PROCESS, 0)))
    calls = []
    def run(stage, command):
        print('Compiling/linking ' + stage + ' from source, one process', flush=True)
        started = time.monotonic()
        with (work / (stage + '.log')).open('w') as log:
            result = subprocess.run(command, cwd=source_root, env=env, stdout=log, stderr=log)
        calls.append({'stage': stage, 'exit_code': result.returncode,
                      'elapsed_seconds': round(time.monotonic() - started, 3), 'argv': command})
        if result.returncode:
            print((work / (stage + '.log')).read_text(), flush=True)
            (work / 'failed-build.json').write_text(json.dumps({'calls': calls}, indent=2) + '\n')
            raise RuntimeError('Source build failed: ' + stage)
    for name in UNITS:
        target = objects / (name + '.obj')
        assert not target.exists()
        run(name, [str(zig), 'c++', *COMPILE_FLAGS, '-I' + str(source_root / 'render/sdk'),
                   '-c', str(source_root / 'render' / (name + '.cpp')), '-o', str(target)])
    run('link', [str(zig), 'c++', *LINK_FLAGS, *[str(objects / (name + '.obj')) for name in UNITS],
                 '-o', str(output), *LIBRARIES])
    pins = {path.relative_to(source_root).as_posix(): sha(path)
            for path in sorted(source_root.rglob('*')) if path.is_file() and path.suffix in ('.cpp', '.h', '.hpp')}
    receipt = {'schema': 1, 'ok': True, 'source_root': str(source_root), 'output': str(output),
               'output_sha256': sha(output), 'output_bytes': output.stat().st_size,
               'source_pins': pins, 'four_translation_units_compiler_invoked': list(UNITS),
               'fresh_output_object_pins': {name + '.obj': sha(objects / (name + '.obj')) for name in UNITS},
               'existing_project_objects_or_DLL_link_inputs': [], 'project_object_reuse': False,
               'compiler_standard_dependency_cache_only': True, 'isolated_empty_build_cache': True,
               'worker_concurrency': 1, 'nice': 19 if hasattr(os, 'nice') else None, 'calls': calls,
               'output_executed_installed_or_Game_verified': False,
               'other_users_fresh_compiler_environment_verified': False}
    (work / 'build-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: receipt[key] for key in ('output', 'output_sha256', 'output_bytes',
                    'four_translation_units_compiler_invoked', 'project_object_reuse')}, indent=2), flush=True)
    return receipt

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', required=True, type=Path)
    parser.add_argument('--zig', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args(); build(args.source_root, args.zig, args.output)
