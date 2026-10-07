"""Sequential native diagnostic build using the user's Zig compiler and public sources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

from pe_reader import pe_report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    zig, output = args.zig.resolve(), args.output.resolve()
    if not zig.is_file():
        parser.error('Provide the installed Zig0.15.2 executable.')
    if output.exists():
        parser.error('Output must be a new directory; existing files are preserved.')
    try:
        os.nice(max(0, 19 - os.getpriority(os.PRIO_PROCESS, 0)))
    except (AttributeError, OSError):
        pass
    output.mkdir(parents=True)
    source = here / 'source'
    env = os.environ.copy()
    env['ZIG_LOCAL_CACHE_DIR'] = str(output / 'cache/local')
    env['ZIG_GLOBAL_CACHE_DIR'] = str(output / 'cache/global')
    units = ('palcraft', 'controls', 'ws', 'compositor')
    objects = []
    for name in units:
        obj = output / (name + '.obj')
        command = [str(zig), 'c++', '-target', 'x86_64-windows-gnu',
                   '-std=c++17', '-O2', '-DNOMINMAX', '-Wall', '-Wextra',
                   '-Wno-unknown-attributes', '-fno-lto',
                   '-I' + str(source / 'render/sdk'), '-c',
                   str(source / 'render' / (name + '.cpp')), '-o', str(obj)]
        subprocess.run(command, cwd=source, env=env, check=True)
        objects.append(obj)
    artifact = output / 'PalCraftRender-v16-portable-operator-mode-off-observer.dll'
    subprocess.run([str(zig), 'c++', '-target', 'x86_64-windows-gnu',
                    '-shared', '-fno-lto', *map(str, objects), '-o', str(artifact),
                    '-lws2_32', '-luser32', '-ld3d11', '-ldxgi'],
                   cwd=source, env=env, check=True)
    data = artifact.read_bytes()
    result = {'schema': 1, 'artifact': str(artifact), 'bytes': len(data),
              'sha256': hashlib.sha256(data).hexdigest(), 'pe': pe_report(artifact),
              'source_units_compiled': list(units), 'previous_object_bytes_reused': False,
              'game_executed': False, 'historical_binary_hash_equality_claimed': False}
    (output / 'build-result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
