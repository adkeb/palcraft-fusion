#!/usr/bin/env python3
"""Reproduce the exact current MC10.7 delta over a user-provided legal 10.6 base."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

def sha(data):
    return hashlib.sha256(data).hexdigest()

def file_sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def check_file(path, expected, description):
    path = Path(path)
    if not path.is_file() or file_sha(path) != expected:
        raise ValueError('Missing or different pinned input: ' + description)
    return path

def sources(freeze, recipe):
    root = freeze / 'source'
    actual = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
    allowed = recipe['allowed_source_members']
    expected_count = recipe['allowed_source_member_count']
    if len(allowed) != expected_count or actual != set(allowed) or len(actual) != expected_count:
        raise ValueError(f'Use the exact {expected_count}-member public source freeze, without caches or extra files')
    for name, expected in allowed.items():
        check_file(root / name, expected, name)
    return [root / name for name in sorted(recipe['compile_sources'])]

def class_inputs(root, recipe):
    actual = {p.relative_to(root).as_posix() for p in root.rglob('*.class')}
    expected = set(recipe['production_classes'])
    if actual != expected or len(expected) != 11:
        raise ValueError('Production directory must contain only the 11 pinned class entries; no compile overlay/helper')
    return {name: check_file(root / name, digest, name).read_bytes()
            for name, digest in recipe['production_classes'].items()}

def run(command):
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout or 'Tool exited unsuccessfully')

def compile_delta(base, jdk_home, runtime_root, fabric_api, freeze, recipe, directory):
    jdk = Path(jdk_home)
    release = (jdk / 'release').read_text()
    version = re.search(r'^JAVA_VERSION="([^"]+)"', release, re.MULTILINE)
    if not version or version.group(1) != recipe['jdk']['version']:
        raise ValueError('Exact class pins require the recorded JDK ' + recipe['jdk']['version'])
    compiler, java = jdk / 'bin/javac', jdk / 'bin/java'
    if not compiler.is_file() or not java.is_file():
        raise ValueError('Provide your installed official JDK home')
    fabric_api = check_file(fabric_api, recipe['fabric_api_distribution']['sha256'], 'official Fabric API distribution')
    cp = []
    embedded = directory / 'dependencies';embedded.mkdir()
    with zipfile.ZipFile(base) as base_zip, zipfile.ZipFile(fabric_api) as fabric_zip:
        for entry in recipe['classpath']:
            relative, origin = entry['relative'], entry['root']
            if origin == 'runtime':
                path = check_file(Path(runtime_root) / relative, entry['sha256'], relative)
            else:
                archive = base_zip if origin == 'base-embedded' else fabric_zip
                data = archive.read(relative)
                if sha(data) != entry['sha256']:
                    raise ValueError('Pinned embedded dependency differs: ' + relative)
                path = embedded / Path(relative).name;path.write_bytes(data)
            cp.append(path)
    helper_source = check_file(freeze / recipe['compile_interface_overlay']['source'],
        recipe['compile_interface_overlay']['source_sha256'], 'compile-only Fabric interface helper source')
    asm = next(path for path in cp if path.name == 'asm-9.10.1.jar')
    helper = directory / 'compile-helper';helper.mkdir()
    overlay = directory / 'fabric-interface-compile.jar'
    minecraft = next(path for path in cp if path.name == '26.3.jar')
    # These three small JVM tasks run sequentially. None starts Minecraft or Gradle.
    run([str(compiler), '-J-Xmx128m', '-classpath', str(asm), '-d', str(helper), str(helper_source)])
    run([str(java), '-Xmx128m', '-classpath', os.pathsep.join((str(helper), str(asm))),
         'FabricCompileInterfaces', str(minecraft), str(overlay)])
    with zipfile.ZipFile(overlay) as injected:
        if set(injected.namelist()) != set(recipe['compile_interface_overlay']['targets']):
            raise ValueError('Compile interface overlay contains unexpected members')
    classes = directory / 'production-classes';classes.mkdir()
    run([str(compiler), '-J-Xmx512m', *recipe['javac_flags'], '-classpath',
         os.pathsep.join(str(p) for p in [overlay, base, *cp]), '-d', str(classes),
         *(str(p) for p in sources(freeze, recipe))])
    return class_inputs(classes, recipe)

def build(base_mod, freeze, output, compiled_production=None, jdk_home=None,
          runtime_root=None, fabric_api=None, dry_run=False):
    freeze, output = Path(freeze).resolve(), Path(output).absolute()
    recipe = json.loads((freeze / 'build-recipe.json').read_text())
    base = check_file(base_mod, recipe['base_mod_sha256'], 'exact legal 10.6 base mod').resolve()
    selected_sources = sources(freeze, recipe)
    mode = 'assembly-from-pinned-production-classes' if compiled_production else 'compile-six-source-delta'
    if not compiled_production and not all((jdk_home, runtime_root, fabric_api)):
        raise ValueError('Source compile requires --jdk-home, --runtime-root and --fabric-api')
    plan = {'mode': mode, 'base_mod_sha256': recipe['base_mod_sha256'],
        'expected_jar_sha256': recipe['final_mod_sha256'], 'expected_bytes': recipe['final_mod_bytes'],
        'allowed_source_members': recipe['allowed_source_member_count'], 'changed_sources_to_compile': len(selected_sources),
        'production_class_allowlist': 11, 'output': str(output), 'worker_concurrency': 1,
        'game_network_GUI_or_Gradle': False, 'runtime_overlay_allowed': False}
    if dry_run:
        return {'ok': True, 'dry_run': True, **plan, 'dependency_verification_and_compile_performed': False}
    if output.exists():
        raise ValueError('Choose a new output; never overwrite an existing release')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='palcraft-mc10_7-', dir=output.parent) as temporary:
        classes = (class_inputs(Path(compiled_production).resolve(), recipe) if compiled_production else
            compile_delta(base, jdk_home, runtime_root, fabric_api, freeze, recipe, Path(temporary)))
        with zipfile.ZipFile(base) as old:
            if len(old.namelist()) != recipe['runtime_jar_entry_count'] or not set(classes).issubset(old.namelist()):
                raise ValueError('Pinned base runtime inventory differs')
            mod = json.loads(old.read('fabric.mod.json'));mod['version'] = recipe['version']
            replacements = {**classes, 'fabric.mod.json': (json.dumps(mod, ensure_ascii=False, indent=2) + '\n').encode()}
            with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as result:
                for info in old.infolist():
                    data = replacements[info.filename] if info.filename in replacements else old.read(info.filename)
                    result.writestr(copy.deepcopy(info), data)
        with zipfile.ZipFile(output) as result:
            if len(result.namelist()) != 173 or sum(n.endswith('.class') for n in result.namelist()) != 168:
                raise ValueError('Unexpected runtime inventory')
            if any(n.startswith(('net/minecraft/', 'FabricCompileInterfaces', 'compile-helper/')) for n in result.namelist()):
                raise ValueError('Compile-only content must never enter the runtime mod')
    actual = file_sha(output)
    receipt = {'ok': actual == recipe['final_mod_sha256'] and output.stat().st_size == recipe['final_mod_bytes'],
        **plan, 'version': recipe['version'], 'jar_sha256': actual, 'jar_bytes': output.stat().st_size,
        'binary_reproduced': actual == recipe['final_mod_sha256'],
        'six_changed_sources_compiled': compiled_production is None,
        'production_class_hashes_verified': True, 'full_source_project_recompiled': False,
        'fresh_environment_complete_source_build_verified': False,
        'runtime_or_pixel_acceptance': False, 'compile_helper_or_game_classes_packaged': False}
    output.with_suffix('.build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if not receipt['ok']:
        raise ValueError('Bytes differ from F35; retain receipt and do not silently promote this result')
    return receipt

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('base-mod', 'output'):
        p.add_argument('--' + name, required=True)
    p.add_argument('--freeze', default=str(Path(__file__).resolve().parents[1] / 'build/mc10_7'))
    p.add_argument('--compiled-production', help='Assembly only: your own exact 11-class directory; no JVM starts')
    p.add_argument('--jdk-home');p.add_argument('--runtime-root');p.add_argument('--fabric-api')
    p.add_argument('--dry-run', action='store_true')
    a = p.parse_args()
    print(json.dumps(build(a.base_mod, a.freeze, a.output, a.compiled_production,
        a.jdk_home, a.runtime_root, a.fabric_api, a.dry_run), indent=2))
