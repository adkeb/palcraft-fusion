"""Materialize normal Minecraft/Fabric dependencies from verified existing cache.

This script copies software only. It never reads launcher accounts/credentials,
copies worlds, starts Minecraft, or invokes Gradle.
"""
import hashlib
import json
import shutil
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
CATALOG = json.loads((HERE / 'dependency-catalog.json').read_text())
ROOT = Path(CATALOG['target_standard_root'])
CACHE = Path('D:/PalworldServer-LAN/PalCraft-Dev/workstreams/integration/gradle-home/caches')
USER_MC = Path('C:/Users/PLAYER/AppData/Roaming/.minecraft')
SOURCE_MC = CACHE / 'fabric-loom/26.3'
MOD = Path('D:/PalworldServer-LAN/PalCraft-Dev/workstreams/integration/tint-prepare-10-1-52ee271b7560/mc/build/libs/passthrough-0.2.0-integration.10.1.jar')
UUID = '11111111-1111-1111-1111-111111111111'
assert not (ROOT / 'dependency-stage-receipt.json').exists(), 'Refuse to replace completed staging'
ROOT.mkdir(parents=True, exist_ok=True)
client, server, player = ROOT / 'client', ROOT / 'server', ROOT / 'players' / UUID / 'minecraft'
for folder in [client, server, player / 'mods', server / 'mods', ROOT / 'state' / UUID / 'bridge', ROOT / 'scripts']:
    folder.mkdir(parents=True, exist_ok=True)
records = []


def digest(path, kind='sha1'):
    h = hashlib.new(kind)
    with path.open('rb') as file:
        for data in iter(lambda: file.read(1024 * 1024), b''):
            h.update(data)
    return h.hexdigest()


def record(path, source, role, expected=None):
    records.append({'relative': path.relative_to(ROOT).as_posix(), 'source': str(source),
                    'role': role, 'bytes': path.stat().st_size, 'sha1': digest(path),
                    'sha256': digest(path, 'sha256'), 'official_expected_sha1': expected})


def copy_checked(source, target, expected, role):
    assert source.is_file() and digest(source) == expected, 'Cached content mismatch: ' + str(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    assert digest(target) == expected
    record(target, source, role, expected)


def locate(row):
    group, artifact, version, *classifier = row['coordinate'].split(':')
    filename = Path(row['relative']).name
    candidates = [USER_MC / 'libraries' / row['relative']]
    module = CACHE / 'modules-2/files-2.1' / group / artifact / version
    if module.is_dir(): candidates += list(module.glob('*/' + filename))
    for file in candidates:
        if file.is_file() and digest(file) == row['sha1']:
            return file
    download = HERE / 'official-dependency-downloads' / row['relative']
    download.parent.mkdir(parents=True, exist_ok=True)
    if not download.exists():
        with urllib.request.urlopen(row['url'], timeout=45) as response, download.open('wb') as file:
            shutil.copyfileobj(response, file)
    assert digest(download) == row['sha1'], 'Official download hash mismatch'
    return download


for row in CATALOG['libraries']:
    source = locate(row)
    copy_checked(source, client / 'libraries' / row['relative'], row['sha1'], row['role'])
    if row['role'] == 'fabric_library':
        copy_checked(source, server / 'libraries' / row['relative'], row['sha1'], row['role'])
print(json.dumps({'phase': 'libraries', 'client_libraries': len(CATALOG['libraries']), 'server_fabric_libraries': 7}), flush=True)
info = json.loads((HERE / 'mojang_minecraft_info.json').read_text())
copy_checked(SOURCE_MC / 'minecraft-client.jar', client / 'versions/26.3/26.3.jar', info['downloads']['client']['sha1'], 'official_minecraft_client')
copy_checked(SOURCE_MC / 'minecraft-server.jar', server / 'server.jar', info['downloads']['server']['sha1'], 'official_minecraft_server_bundler')
(client / 'versions/26.3/26.3.json').write_text(json.dumps(info, indent=2) + '\n')
record(client / 'versions/26.3/26.3.json', HERE / 'mojang_minecraft_info.json', 'official_minecraft_version_metadata')
profile = json.loads((HERE / 'fabric-client-profile.json').read_text())
folder = client / 'versions' / profile['id']
folder.mkdir(parents=True, exist_ok=True)
(folder / (profile['id'] + '.json')).write_text(json.dumps(profile, indent=2) + '\n')
record(folder / (profile['id'] + '.json'), HERE / 'fabric-client-profile.json', 'official_fabric_profile')

index = CACHE / 'fabric-loom/assets/indexes/26.3-34.json'
copy_checked(index, client / 'assets/indexes/34.json', info['assetIndex']['sha1'], 'official_asset_index')
objects = json.loads(index.read_text())['objects']
unique = {value['hash']: value['size'] for value in objects.values()}
missing = []
for sha, size in unique.items():
    source = CACHE / 'fabric-loom/assets/objects' / sha[:2] / sha
    if not source.is_file() or source.stat().st_size != size or digest(source) != sha:
        source = USER_MC / 'assets/objects' / sha[:2] / sha
    if not source.is_file() or source.stat().st_size != size or digest(source) != sha:
        missing.append({'hash': sha, 'bytes': size})
        continue
    copy_checked(source, client / 'assets/objects' / sha[:2] / sha, sha, 'official_asset_object')
    if len(records) % 1000 == 0: print(json.dumps({'phase': 'assets', 'files_copied': len(records)}), flush=True)
if missing:
    (HERE / 'missing-assets.json').write_text(json.dumps(missing, indent=2) + '\n')
    raise RuntimeError('Cached assets missing; explicit official fetch required: ' + str(len(missing)))
api = CATALOG['fabric_api']
api_source = locate(api)
assert digest(MOD, 'sha256') == CATALOG['mod']['sha256']
for mods in [server / 'mods', player / 'mods']:
    copy_checked(api_source, mods / Path(api['relative']).name, api['sha1'], 'fabric_api_mod')
    shutil.copy2(MOD, mods / MOD.name)
    record(mods / MOD.name, MOD, 'passthrough_production_mod')
receipt = {'schema': 1, 'root': str(ROOT), 'minecraft': '26.3', 'fabric_loader': '0.19.5', 'java_major': 25,
           'mod_sha256': CATALOG['mod']['sha256'], 'asset_objects': len(unique), 'files': records,
           'dev_classpath_dependency': False, 'compiled': False, 'worlds_copied': False,
           'private_keys_or_accounts_read': False, 'minecraft_started': False, 'runtime_accepted': False}
(ROOT / 'dependency-stage-receipt.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'phase': 'complete', 'root': str(ROOT), 'files': len(records), 'assets': len(unique), 'runtime_accepted': False}), flush=True)
