#!/usr/bin/env python3
"""Build current MC10.10 from all 100 public production sources; fresh-only, with explicit historical debug profiles."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time
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


def compile_profiles(freeze, recipe, jdk_home, runtime_root, fabric_api, websocket_jar, work, commands):
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
    def run(command):
        started = time.monotonic()
        result = subprocess.run(command, capture_output=True, text=True, env=environment, cwd=work)
        record = {'argv': command, 'exit_code': result.returncode, 'elapsed_seconds': round(time.monotonic()-started, 6), 'stdout': result.stdout, 'stderr': result.stderr}
        commands.append(record)
        (work/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
        print(json.dumps({'compiler_stage': len(commands), 'exit_code': result.returncode, 'elapsed_seconds': record['elapsed_seconds']}), flush=True)
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



def build(input_source, output, *, jdk, runtime, fabric, websocket, work_dir=None):
    freeze = Path(input_source).expanduser().resolve()
    output = Path(output).expanduser().resolve()
    jdk = Path(jdk).expanduser().resolve()
    runtime = Path(runtime).expanduser().resolve()
    fabric = Path(fabric).expanduser().resolve()
    websocket = Path(websocket).expanduser().resolve()
    recipe_data = (freeze/'build-recipe.json').read_bytes()
    recipe = json.loads(recipe_data)
    if output.exists(): raise ValueError('Choose a new output; existing JARs are never replaced')
    if not recipe.get('full_project_compilation_only') or recipe.get('precompiled_source_profiles_allowed'):
        raise ValueError('Only the declared fresh-source recipe is accepted')
    sources = [name for name in recipe['source_members'] if name.endswith('.java')]
    if len(sources) != 100: raise ValueError('Exactly 100 declared production sources are required')
    for name, expected in recipe['source_members'].items(): pinned(freeze/'source'/name, expected)
    for name in sources:
        if not name.startswith(('src/main/java/','src/client/java/')):
            raise ValueError('Production source outside main/client roots')
    output.parent.mkdir(parents=True, exist_ok=True)
    work = Path(work_dir).expanduser().resolve() if work_dir else output.with_suffix('.work')
    if work.exists(): raise ValueError('A new empty work directory is required; compiled profiles cannot be supplied')
    work.mkdir(parents=True)
    started = time.monotonic()
    commands = []
    receipt = {'ok': False, 'target_version': recipe['target_version'], 'recipe_sha256': digest(recipe_data),
               'production_sources': 100, 'full_source_compiled_this_call': False,
               'precompiled_source_profiles_accepted': False, 'old_project_class_byte_reuse': 0,
               'old_application_jar_on_classpath': False, 'compile_helper_or_game_overlay_in_runtime': False,
               'game_GUI_server_runtime_or_full42_verified': False,
               'other_user_fresh_environment_verified': False, 'nice': os.getpriority(os.PRIO_PROCESS,0) if hasattr(os,'getpriority') else None,
               'sequential_JVM_jobs': True, 'actual_compile_commands': commands}
    try:
        profiles, _ = compile_profiles(freeze, recipe, jdk, runtime, fabric, websocket, work, commands)
        profile_hashes = {name: {p.relative_to(path).as_posix(): digest(p.read_bytes()) for p in sorted(path.rglob('*.class'))}
                          for name,path in profiles.items()}
        receipt.update(full_source_compiled_this_call=True,
                       generated_project_classes_per_profile={name:len(files) for name,files in profile_hashes.items()},
                       total_generated_project_class_files=sum(len(files) for files in profile_hashes.values()),
                       fresh_generated_class_sha256=profile_hashes,
                       production_source_compiler_invocations=len(profiles))
        payload, selected = pack(freeze, recipe, profiles, output)
        ws_entry = next(e for e in recipe['classpath'] if e['root'] == 'websocket-standalone')
        payload['META-INF/jars/Java-WebSocket-1.6.0.jar'] = pinned(websocket, ws_entry['sha256'])
        inventory = [entry['filename'] for entry in recipe['zip_entry_order_and_metadata']]
        if set(payload) != set(inventory): raise ValueError('Runtime entry inventory differs')
        if any(name.startswith(('net/minecraft/','FabricCompileInterfaces')) for name in payload):
            raise ValueError('A compile-only helper or dependency overlay would leak into runtime')
        with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            for entry in recipe['zip_entry_order_and_metadata']:
                info = zipfile.ZipInfo(entry['filename'], tuple(entry['date_time']))
                for key in ('compress_type','create_system','create_version','extract_version','external_attr','internal_attr','flag_bits'):
                    setattr(info,key,entry[key])
                info.comment=bytes.fromhex(entry['comment_hex']); info.extra=bytes.fromhex(entry['extra_hex'])
                archive.writestr(info,payload[entry['filename']])
        actual = digest(output.read_bytes())
        receipt.update(jar_sha256=actual, jar_bytes=output.stat().st_size,
                       production_classes=len(selected), runtime_entries=len(payload),
                       historical_debug_profile_selection=selected,
                       historical_manifest_metadata_preserved=True,
                       exact_current_10_10_class_hashes_verified=True,
                       ok=actual == recipe['target_jar_sha256'] and output.stat().st_size == recipe['target_jar_bytes'])
        if not receipt['ok']: raise ValueError('Exact current10.10 JAR differs; retain the result and receipt, do not promote')
        return receipt
    except Exception as error:
        receipt['error']=str(error)
        raise
    finally:
        receipt['elapsed_seconds']=round(time.monotonic()-started,6)
        output.with_suffix('.build.json').write_text(json.dumps(receipt,indent=2)+'\n')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-source',default=str(Path(__file__).resolve().parent),help='Public recipe/helper/packaged-resources/source tree')
    for name in ('jdk','runtime','fabric','websocket','output'):
        parser.add_argument('--'+name,required=True)
    parser.add_argument('--work-dir',help='New directory for retained fresh compiler evidence')
    args=parser.parse_args()
    try:
        result=build(args.input_source,args.output,jdk=args.jdk,runtime=args.runtime,fabric=args.fabric,websocket=args.websocket,work_dir=args.work_dir)
    except Exception as error:
        parser.exit(1,'Source build failed: '+str(error)+'\n')
    print(json.dumps({key:value for key,value in result.items() if key not in ['actual_compile_commands','historical_debug_profile_selection','fresh_generated_class_sha256']},indent=2))
