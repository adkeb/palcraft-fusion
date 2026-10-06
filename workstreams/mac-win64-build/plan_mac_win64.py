#!/usr/bin/env python3
"""Plan a pinned, Mac-only Win64 bridge build; compile only with --execute."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

HERE = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('module')
    parser.add_argument('--overlay-source', type=Path)
    parser.add_argument('--overlay-sha256')
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    catalog = json.loads((HERE / 'catalog.json').read_text())
    if args.module not in catalog['modules']:
        parser.error('Select a recorded bridge module; full UE4SS C++ rebuild is not supported by this route.')
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        parser.error('This entry is restricted to the recorded arm64 Mac.')
    zig = Path(catalog['zig']['path'])
    if not zig.is_file() or digest(zig) != catalog['zig']['sha256']:
        parser.error('The pinned Mac compiler is absent or changed.')
    module = catalog['modules'][args.module]
    for relative, expected in module['input_pins'].items():
        path = HERE / relative
        if not path.is_file() or digest(path) != expected:
            parser.error('Pinned build input differs: ' + relative)
    original_source = HERE / module['translation_unit']
    source = original_source
    if args.overlay_source:
        source = args.overlay_source.resolve()
        if not args.overlay_sha256 or digest(source) != args.overlay_sha256:
            parser.error('A changed source requires its exact owner-provided SHA256.')
    elif args.overlay_sha256:
        parser.error('--overlay-sha256 requires --overlay-source.')
    source_hash = digest(source)
    destination = HERE / 'work' / args.module / source_hash[:12]
    input_root = HERE / 'inputs' / args.module
    if args.overlay_source:
        input_root = destination / 'inputs'
        source = input_root / original_source.relative_to(HERE / 'inputs' / args.module)
    values = {'zig': str(zig), 'source': str(source), 'input': str(input_root),
              'work': str(destination), 'artifact': str(destination / module['artifact_basename'])}
    commands = [['/usr/bin/nice', '-n', '19'] + [part.format(**values) for part in row]
                for row in module['commands']]
    plan = {'module': args.module, 'compiler_target': 'x86_64-windows-gnu',
            'route': 'unchanged-existing-Win64-C/raw-wire-bridge-recipe',
            'source_sha256': source_hash, 'commands': commands, 'cwd': str(destination),
            'baseline_abi': module['abi'], 'executed': False,
            'remote_or_game_or_install_actions': []}
    if args.execute:
        destination.mkdir(parents=True, exist_ok=True)
        if args.overlay_source:
            shutil.copytree(HERE / 'inputs' / args.module, input_root, dirs_exist_ok=True)
            shutil.copy2(args.overlay_source.resolve(), source)
            if digest(source) != source_hash:
                parser.error('Changed source moved during staging.')
        environment = dict(os.environ)
        environment['ZIG_LOCAL_CACHE_DIR'] = str(destination / '.zig-local')
        environment['ZIG_GLOBAL_CACHE_DIR'] = str(destination / '.zig-global')
        for index, command in enumerate(commands):
            with (destination / ('build-' + str(index) + '.log')).open('w') as output:
                subprocess.run(command, cwd=destination, env=environment,
                               stdout=output, stderr=subprocess.STDOUT, check=True)
        artifact = Path(values['artifact'])
        plan.update(executed=True, artifact_sha256=digest(artifact), artifact_bytes=artifact.stat().st_size)
        (destination / 'build-receipt.json').write_text(json.dumps(plan, indent=2) + '\n')
    print(json.dumps(plan, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
