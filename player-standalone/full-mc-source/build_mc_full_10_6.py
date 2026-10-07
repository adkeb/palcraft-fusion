#!/usr/bin/env python3
"""Build all 100 production sources and reproduce the historical mixed-debug10.6 JAR."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import zipfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pinned(path, expected):
    path = Path(path)
    data = path.read_bytes()
    if digest(data) != expected:
        raise ValueError('Pinned input differs: ' + path.name)
    return data


def historical_lines(data, delta):
    """Change only counted LineNumberTable u16 source lines; never Code/ABI bytes."""
    x = bytearray(data); p = 8
    count = struct.unpack_from('>H', x, p)[0]; p += 2; cp = {}; index = 1
    while index < count:
        tag = x[p]; p += 1
        if tag == 1:
            size = struct.unpack_from('>H', x, p)[0]; p += 2
            cp[index] = bytes(x[p:p + size]).decode('utf8', errors='replace'); p += size
        elif tag in (3, 4): p += 4
        elif tag in (5, 6): p += 8; index += 1
        elif tag in (7, 8, 16, 19, 20): p += 2
        elif tag in (9, 10, 11, 12, 17, 18): p += 4
        elif tag == 15: p += 3
        else: raise ValueError('Unknown constant-pool tag')
        index += 1
    p += 6
    count = struct.unpack_from('>H', x, p)[0]; p += 2 + 2 * count
    count = struct.unpack_from('>H', x, p)[0]; p += 2
    for _ in range(count):
        p += 6; attrs = struct.unpack_from('>H', x, p)[0]; p += 2
        for _ in range(attrs):
            size = struct.unpack_from('>I', x, p + 2)[0]; p += 6 + size
    count = struct.unpack_from('>H', x, p)[0]; p += 2
    for _ in range(count):
        p += 6; attrs = struct.unpack_from('>H', x, p)[0]; p += 2
        for _ in range(attrs):
            key, size = struct.unpack_from('>HI', x, p); p += 6
            if cp[key] == 'Code':
                q = p + 8 + struct.unpack_from('>I', x, p + 4)[0]
                exceptions = struct.unpack_from('>H', x, q)[0]; q += 2 + 8 * exceptions
                subattrs = struct.unpack_from('>H', x, q)[0]; q += 2
                for _ in range(subattrs):
                    name, subsize = struct.unpack_from('>HI', x, q); q += 6
                    if cp[name] == 'LineNumberTable':
                        lines = struct.unpack_from('>H', x, q)[0]
                        for line in range(lines):
                            offset = q + 2 + 4 * line + 2
                            value = struct.unpack_from('>H', x, offset)[0] + delta
                            if not 0 < value < 65536: raise ValueError('Invalid historical source line')
                            struct.pack_into('>H', x, offset, value)
                    q += subsize
            p += size
    return bytes(x)


def compile_profiles(freeze, recipe, jdk_home, runtime_root, fabric_api, websocket_jar, work):
    jdk = Path(jdk_home)
    if 'JAVA_VERSION="' + recipe['jdk']['version'] + '"' not in (jdk / 'release').read_text():
        raise ValueError('Provide the recorded exact JDK release')
    fabric = pinned(fabric_api, recipe['fabric_api_distribution']['sha256'])
    dependency_dir = work / 'dependencies'; dependency_dir.mkdir()
    cp = []
    with zipfile.ZipFile(fabric_api) as archive:
        for entry in recipe['classpath']:
            if entry['root'] == 'runtime':
                path = Path(runtime_root) / entry['relative']; pinned(path, entry['sha256'])
            elif entry['root'] == 'websocket-standalone':
                path = Path(websocket_jar); pinned(path, entry['sha256'])
            else:
                data = archive.read(entry['relative'])
                if digest(data) != entry['sha256']: raise ValueError('Fabric nested dependency differs')
                path = dependency_dir / Path(entry['relative']).name; path.write_bytes(data)
            cp.append(path)
    environment = os.environ.copy()
    for key in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS', 'CLASSPATH'):
        environment.pop(key, None)
    environment['JAVA_TOOL_OPTIONS'] = '-XX:ActiveProcessorCount=1 -XX:+UseSerialGC -Djava.io.tmpdir=' + str(work)
    commands = []
    def run(command):
        result = subprocess.run(command, capture_output=True, text=True, env=environment)
        commands.append({'argv': command, 'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
        if result.returncode: raise RuntimeError(result.stderr)
    helper = work / 'helper'; helper.mkdir()
    helper_source = freeze / recipe['compile_interface_helper']['source']
    pinned(helper_source, recipe['compile_interface_helper']['sha256'])
    asm = next(path for path in cp if path.name == 'asm-9.10.1.jar')
    minecraft = next(path for path in cp if path.name == '26.3.jar')
    overlay = work / 'compile-only-interface.jar'
    run([str(jdk/'bin/javac'), '-J-Xmx128m', '-classpath', str(asm), '-d', str(helper), str(helper_source)])
    run([str(jdk/'bin/java'), '-Xmx128m', '-classpath', os.pathsep.join((str(helper), str(asm))),
         'FabricCompileInterfaces', str(minecraft), str(overlay)])
    with zipfile.ZipFile(overlay) as archive:
        if set(archive.namelist()) != {'net/minecraft/server/network/ServerCommonPacketListenerImpl.class',
                                     'net/minecraft/server/network/ServerLoginPacketListenerImpl.class'}:
            raise ValueError('Unexpected compile-only overlay')
    sources = [str(freeze/'source'/name) for name in sorted(recipe['source_members']) if name.endswith('.java')]
    if len(sources) != 100: raise ValueError('All 100 production sources are required')
    profiles = {}
    for profile, extra_flags in recipe['profiles'].items():
        path = work / profile; path.mkdir(); profiles[profile] = path
        run([str(jdk/'bin/javac'), '-J-Xmx512m', *extra_flags, *recipe['javac_common_flags'], '-classpath',
             os.pathsep.join(str(path) for path in [overlay, *cp]), '-d', str(path), *sources])
    return profiles, commands


def pack(freeze, recipe, profiles, output):
    target_names = set(recipe['class_sha256'])
    for profile, path in profiles.items():
        if {p.relative_to(path).as_posix() for p in path.rglob('*.class')} != target_names:
            raise ValueError('A full 168-class source output is required for each profile')
        for name, expected in recipe['raw_' + profile + '_class_sha256'].items():
            pinned(path / name, expected)
    payload = {}
    selected = {}
    for name, selection in recipe['class_profile_selection'].items():
        data = (profiles[selection['profile']] / name).read_bytes()
        if 'LineNumberTable_line_delta' in selection:
            data = historical_lines(data, selection['LineNumberTable_line_delta'])
        if digest(data) != recipe['class_sha256'][name]: raise ValueError('Generated class differs: ' + name)
        payload[name] = data; selected[name] = selection
    for name, expected in recipe['packaged_resources'].items():
        target = 'META-INF/MANIFEST.MF' if name == 'MANIFEST.MF' else name
        payload[target] = pinned(freeze/'packaged-resources'/name, expected)
    return payload, selected


def build(freeze, output, *, jdk_home=None, runtime_root=None, fabric_api=None, websocket_jar=None,
          fresh_default_classes=None, fresh_g_classes=None):
    freeze = Path(freeze).resolve(); output = Path(output).absolute()
    recipe = json.loads((freeze/'full-build-recipe.json').read_text())
    if output.exists(): raise ValueError('Choose a new output')
    for name, expected in recipe['source_members'].items(): pinned(freeze/'source'/name, expected)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='mc-full-source-', dir=output.parent) as temp:
        work = Path(temp)
        if fresh_default_classes is not None or fresh_g_classes is not None:
            if not fresh_default_classes or not fresh_g_classes: raise ValueError('Supply both freshly compiled source profile directories')
            profiles = {'default':Path(fresh_default_classes).resolve(), 'g':Path(fresh_g_classes).resolve()}
            commands = []; compiled_this_call = False
        else:
            if not all((jdk_home, runtime_root, fabric_api, websocket_jar)): raise ValueError('Provide your legal cached SDK/toolchain/dependency paths')
            profiles, commands = compile_profiles(freeze, recipe, jdk_home, runtime_root, fabric_api, websocket_jar, work)
            compiled_this_call = True
        payload, selected = pack(freeze, recipe, profiles, output)
        ws_entry = next(e for e in recipe['classpath'] if e['root'] == 'websocket-standalone')
        if not websocket_jar: raise ValueError('The declared third-party WebSocket JAR is required for packaging')
        payload['META-INF/jars/Java-WebSocket-1.6.0.jar'] = pinned(websocket_jar, ws_entry['sha256'])
        if set(payload) != {entry['filename'] for entry in recipe['zip_entry_order_and_metadata']}:
            raise ValueError('Runtime inventory is not exactly the recorded source/dependency inventory')
        with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            for entry in recipe['zip_entry_order_and_metadata']:
                info = zipfile.ZipInfo(entry['filename'], tuple(entry['date_time']))
                for key in ('compress_type','create_system','create_version','extract_version','external_attr','internal_attr','flag_bits'):
                    setattr(info, key, entry[key])
                info.comment = bytes.fromhex(entry['comment_hex']); info.extra = bytes.fromhex(entry['extra_hex'])
                archive.writestr(info, payload[entry['filename']])
    actual = digest(output.read_bytes())
    receipt = {'ok': actual == recipe['target_jar_sha256'] and output.stat().st_size == recipe['target_jar_bytes'],
               'jar_sha256': actual, 'jar_bytes': output.stat().st_size, 'production_sources':100,'production_classes':168,
               'full_source_compiled_this_call':compiled_this_call,'packing_existing_fresh_profile_dirs':not compiled_this_call,
               'actual_compile_commands':commands,'historical_debug_profile_selection':selected,
               'old_project_class_byte_reuse':0,'old_application_jar_on_classpath':False,
               'compile_helper_or_game_overlay_in_runtime':False,'historical_manifest_metadata_preserved':True,
               'game_GUI_runtime_or_full42_verified':False}
    output.with_suffix('.build.json').write_text(json.dumps(receipt, indent=2)+'\n')
    if not receipt['ok']: raise ValueError('Exact10.6 bytes differ; preserve receipt, do not promote')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--freeze', default=str(Path(__file__).resolve().parent))
    for name in ('output','websocket-jar'): parser.add_argument('--'+name, required=True)
    for name in ('jdk-home','runtime-root','fabric-api','fresh-default-classes','fresh-g-classes'): parser.add_argument('--'+name)
    args = parser.parse_args()
    result = build(args.freeze,args.output,jdk_home=args.jdk_home,runtime_root=args.runtime_root,
                   fabric_api=args.fabric_api,websocket_jar=args.websocket_jar,
                   fresh_default_classes=args.fresh_default_classes,fresh_g_classes=args.fresh_g_classes)
    print(json.dumps({k:v for k,v in result.items() if k not in ['actual_compile_commands','historical_debug_profile_selection']}))
