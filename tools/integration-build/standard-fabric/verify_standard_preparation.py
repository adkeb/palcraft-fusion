"""Check the prepared normal roots and copy map without executing game code."""
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path('D:/PalworldServer-LAN/PalCraft-Standard-10.1')
HERE = Path(__file__).resolve().parent
receipt = json.loads((ROOT / 'dependency-stage-receipt.json').read_text())
catalog = json.loads((HERE / 'dependency-catalog.json').read_text())


def sha(path, algorithm='sha256'):
    h = hashlib.new(algorithm)
    with path.open('rb') as file:
        for data in iter(lambda: file.read(1024 * 1024), b''): h.update(data)
    return h.hexdigest()


for item in receipt['files']:
    file = ROOT / item['relative']
    assert file.is_file() and file.stat().st_size == item['bytes']
    assert sha(file) == item['sha256'], item['relative']
with zipfile.ZipFile(ROOT / 'server/fabric-server-launch.jar') as jar:
    manifest = jar.read('META-INF/MANIFEST.MF').decode().replace('\r\n ', '')
    assert 'Main-Class: net.fabricmc.loader.impl.launch.server.FabricServerLauncher' in manifest
    classpath = next(line.split(': ', 1)[1] for line in manifest.splitlines() if line.startswith('Class-Path:'))
    for name in classpath.split(): assert (ROOT / 'server' / name).is_file()
mod = ROOT / 'server/mods/passthrough-0.2.0-integration.10.1.jar'
with zipfile.ZipFile(mod) as jar:
    manifest_mod = jar.read('META-INF/MANIFEST.MF').decode().replace('\r\n ', '')
    assert 'Fabric-Mapping-Namespace: official' in manifest_mod
    assert not any(name.startswith(('net/minecraft/', 'assets/minecraft/')) for name in jar.namelist())
    assert 'dev/rehan/passthrough/client/EntityCaptureExporter.class' in jar.namelist()
    assert 'passthrough.client.mixins.json' in jar.namelist()
launches = []
for role in ['server', 'guest']:
    info = json.loads((ROOT / 'launch' / (role + '.json')).read_text(encoding='utf-8-sig'))
    args = [json.loads(line) for line in (ROOT / 'launch' / (role + '.args')).read_text().splitlines()]
    assert '-Dfabric.development=false' in args
    assert not any(any(text in argument.lower() for text in ['fabric.dli', 'devlaunchinjector', '.gradle/', '.gradle\\', 'build/classes', 'build\\classes', 'build/resources', 'build\\resources']) for argument in args)
    if role == 'server':
        assert '-jar' in args and args[args.index('-jar') + 1] == str(ROOT / 'server/fabric-server-launch.jar')
        main = 'net.fabricmc.loader.impl.launch.server.FabricServerLauncher'
    else:
        main = 'net.fabricmc.loader.impl.launch.knot.KnotClient'
        assert main in args
        cp = args[args.index('-classpath') + 1].split(';')
        assert len(cp) == 82 and all(Path(path).is_file() for path in cp)
        assert not any('passthrough' in path or 'fabric-api-' in path for path in cp), 'Mods must come from the normal mods directory'
        assert args.count('--username') == 1 and args[args.index('--username') + 1] == 'PalCraft'
        assert args.count('--uuid') == 1 and args[args.index('--uuid') + 1] == '11111111-1111-1111-1111-111111111111'
        assert args[args.index('--accessToken') + 1] == '0'
    mods = list((Path(info['cwd']) / 'mods').glob('*.jar'))
    ids = []
    for file in mods:
        with zipfile.ZipFile(file) as jar: ids.append(json.loads(jar.read('fabric.mod.json'))['id'])
    assert sorted(ids) == ['fabric-api', 'passthrough']
    launches.append({'role': role, 'cwd': info['cwd'], 'main': main, 'production': True,
                     'args_sha256': sha(ROOT / 'launch' / (role + '.args')), 'top_level_mod_ids': ids})
assert not (ROOT / 'server/world').exists()
assert not (ROOT / 'world-migration-receipt.json').exists()
assert not any(file.name in ['launcher_accounts.json', 'credential.json'] for file in ROOT.rglob('*'))
files = []
for file in sorted(ROOT.rglob('*')):
    if file.is_file() and file.name not in ['copy-manifest.json', 'verification.json']:
        rel = file.relative_to(ROOT).as_posix()
        # Software/metadata copy roots are relative and independent of Gradle caches.
        files.append({'relative': rel, 'bytes': file.stat().st_size, 'sha256': sha(file),
                      'kind': 'mod' if '/mods/' in rel else 'normal_software_dependency_or_metadata'})
copy_map = {'schema': 1, 'source_root': str(ROOT), 'destination_root': '<chosen ordinary player/backend install root>',
            'files': files, 'private_keys': [], 'account_data': [], 'worlds': [], 'runtime_accepted': False}
(ROOT / 'copy-manifest.json').write_text(json.dumps(copy_map, ensure_ascii=False, indent=2) + '\n')
proof = {'schema': 1, 'namespace': 'official', 'remap_required': False, 'recompiled': False,
         'source_mod_sha256': sha(mod), 'normal_roots_materialized': True, 'files_hashed': len(files),
         'assets_verified': receipt['asset_objects'], 'official_server_launcher': True,
         'launches': launches, 'dev_dli_classpath_dependency': False, 'scripts_syntax_checked': True,
         'launch_arguments_prepared_and_checked': True, 'current_world_moved': False,
         'minecraft_started': False, 'services_changed': False, 'private_keys_or_accounts_read': False,
         'normal_launch_runtime_accepted': False, 'D01_D04_closed': False}
(ROOT / 'verification.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(proof, ensure_ascii=False), flush=True)
