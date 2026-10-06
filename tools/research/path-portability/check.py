#!/usr/bin/env python3
"""Bounded source check: one fixture lifecycle, Lua paths, and a small native helper."""
import ast
import hashlib
import importlib
import io
import json
import os
import shutil
import subprocess
import sys
import time
import unittest
from pathlib import Path

OUT = Path(__file__).resolve().parent
SOURCE = OUT.parent / 'palcraft'
WORKSPACE = OUT.parents[2]
WORK = OUT / 'work/check'
EVIDENCE = OUT / 'evidence'


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, timeout=25, **kwargs)
    if result.returncode:
        raise RuntimeError(' '.join(str(x) for x in command) + '\n' + result.stdout + result.stderr)
    return result.stdout


def main():
    started = time.monotonic()
    EVIDENCE.mkdir(exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    staging = WORK / 'palcraft'
    staging.mkdir(exist_ok=True)
    for folder in ('installer', 'launcher'):
        shutil.copytree(SOURCE / folder, staging / folder, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    for path in (OUT / 'candidate/palcraft').rglob('*'):
        if path.is_file():
            target = staging / path.relative_to(OUT / 'candidate/palcraft')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
    for path in (OUT / 'candidate/palcraft').rglob('*.py'):
        ast.parse(path.read_text(), filename=str(path))
    sys.path.insert(0, str(staging / 'installer/tests'))
    sys.path.insert(0, str(staging))
    module = importlib.import_module('test_portable_paths')
    suite = unittest.TestSuite([module.PortablePathFlow('test_unicode_directory_lifecycle_without_drive_d')])
    log = io.StringIO()
    result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite)
    (EVIDENCE / 'path-flow.log').write_text(log.getvalue())
    if not result.wasSuccessful():
        print(log.getvalue())
        raise SystemExit(1)
    lua = WORKSPACE / 'work/palworld-live/research/lua-5.4.8/src/lua'
    for path in (OUT / 'candidate/palcraft').rglob('*.lua'):
        run([str(lua.with_name('luac')), '-p', str(path)])
    lua_output = run([str(lua), str(OUT / 'tests/path_contract.lua'),
                      str(OUT / 'candidate/palcraft/runtime/paths.lua')],
                     env={**os.environ, 'PALCRAFT_WINDOWS_ROOT': 'c:\\Games\\玩家 PalCraft'})
    executable = WORK / 'path_contract'
    run(['clang++', '-std=c++17', '-O0', str(OUT / 'tests/path_contract.cpp'), '-o', str(executable)])
    run([str(executable)])

    manifest = json.loads((OUT / 'manifest.json').read_text())
    combined = ''.join((OUT / entry['patch']).read_text() for entry in manifest['files'])
    patch = OUT / 'patches/palcraft-windows-root-v1.patch'
    patch.write_text(combined)
    apply_output = run(['patch', '--dry-run', '-p1', '-d', str(OUT / 'work/base/palcraft'), '-i', str(patch)])
    (EVIDENCE / 'patch-dry-run.log').write_text(apply_output)
    drift = []
    for entry in manifest['files']:
        live = SOURCE / entry['path']
        if entry['base_sha256'] and hashlib.sha256(live.read_bytes()).hexdigest() != entry['base_sha256']:
            drift.append(entry['path'])
    evidence = {'schema': 1, 'ok': True, 'contract': manifest['contract'], 'lifecycle_tests': result.testsRun,
                'elapsed_seconds': round(time.monotonic() - started, 3), 'path_flow': module.EVIDENCE,
                'lua_result': lua_output.strip(), 'native_check': 'portable header normalization and expected executable layout',
                'patch_applies_to_exact_bases': True, 'live_owner_drift_at_check': drift,
                'windows_dlls_rebuilt': False, 'windows_or_wine_runtime_checked': False,
                'game_or_remote_processes_started': [], 'live_source_modified': False}
    (EVIDENCE / 'check.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(evidence, ensure_ascii=False))


if __name__ == '__main__':
    main()
