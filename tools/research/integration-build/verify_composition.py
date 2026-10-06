"""Verify a composed Java candidate without running a game or old test matrices."""
import argparse
import hashlib
import json
import struct
import zipfile
from pathlib import Path
from verify_artifact import TARGETS, class_methods


def sha(data):
    return hashlib.sha256(data).hexdigest()


def verify(snapshot, game_jar, evidence, extra_targets=None):
    manifest = json.loads((snapshot / 'source-manifest.json').read_text())
    build = json.loads((snapshot / 'build-result.json').read_text(encoding='utf-8-sig'))
    assert build['exit_code'] == 0 and build['tasks'] == 'assemble'
    assert build['source_hash'] == manifest['source_hash']
    assert sha((snapshot / 'source.zip').read_bytes()) == manifest['archive_sha256']
    with zipfile.ZipFile(snapshot / 'source.zip') as source:
        assert set(source.namelist()) == set(manifest['files'])
        for name, digest in manifest['files'].items():
            assert sha(source.read(name)) == digest, name
        version = next(line.split('=', 1)[1] for line in source.read('gradle.properties').decode().splitlines() if line.startswith('version='))

    prior = json.loads((evidence / 'source-manifest.json').read_text())
    log = (evidence / 'gradle-build.log').read_text(encoding='utf-8-sig')
    markers = ['TravelRebaseContract: PASS (19', 'WorldPoseScopeContract: PASS (12',
               'PASS v3 import full/empty/terminal/restart/release',
               'PASS v3 export full/empty/terminal/restart/release']
    assert all(marker in log for marker in markers), 'Missing actual prior directed test output'
    names = ['build.gradle',
             'src/contractTest/java/dev/rehan/passthrough/ExchangeRecoveryCrashTest.java',
             'src/contractTest/java/dev/rehan/passthrough/TravelRebaseContract.java',
             'src/contractTest/java/dev/rehan/passthrough/session/WorldPoseScopeContract.java',
             'src/main/java/dev/rehan/passthrough/BridgeTravelGate.java',
             'src/main/java/dev/rehan/passthrough/CompleteLineJournal.java',
             'src/main/java/dev/rehan/passthrough/ExchangeJournal.java',
             'src/main/java/dev/rehan/passthrough/ResourceExchange.java',
             'src/main/java/dev/rehan/passthrough/TravelRebaseValidator.java',
             'src/main/java/dev/rehan/passthrough/session/WorldPoseScope.java']
    for name in names:
        assert prior['files'][name] == manifest['files'][name], 'Changed directed test input: ' + name

    artifact = next(row for row in build['artifacts'] if row['name'].endswith('.jar') and '-sources' not in row['name'])
    jar = snapshot / artifact['name']
    assert jar.stat().st_size == artifact['bytes'] and sha(jar.read_bytes()) == artifact['sha256']
    with zipfile.ZipFile(jar) as archive:
        mod = json.loads(archive.read('fabric.mod.json'))
        assert mod['version'] == version and mod['depends']['java'] == '>=25'
        classes = [name for name in archive.namelist() if name.endswith('.class')]
        assert all(struct.unpack('>H', archive.read(name)[6:8])[0] == 69 for name in classes)
        assert not any(name.startswith(('net/minecraft/', 'assets/minecraft/')) for name in archive.namelist())
        mixins = []
        for resource, key in [('passthrough.mixins.json', 'mixins'), ('passthrough.client.mixins.json', 'client')]:
            config = json.loads(archive.read(resource))
            assert len(config[key]) == len(set(config[key]))
            for name in config[key]:
                path = config['package'].replace('.', '/') + '/' + name + '.class'
                assert path in classes, path
                mixins.append(path)
        for name in ['client/EntityCaptureExporter', 'client/visual/VanillaEntityCapture', 'client/material/MaterialTintFeature']:
            assert 'dev/rehan/passthrough/' + name + '.class' in classes

    targets = dict(TARGETS)
    targets['net/minecraft/client/renderer/LevelRenderer'] = [('render', '(Lcom/mojang/blaze3d/resource/GraphicsResourceAllocator;ZLnet/minecraft/client/renderer/state/level/CameraRenderState;Lcom/mojang/renderpearl/api/buffers/GpuBufferSlice;Lorg/joml/Vector4f;ZZ)V')]
    targets['net/minecraft/client/renderer/GameRenderer'] = [('onResourceManagerReload', '(Lnet/minecraft/server/packs/resources/ResourceManager;)V')]
    target_checks = []
    with zipfile.ZipFile(game_jar) as game:
        for target, required in targets.items():
            methods = class_methods(game.read(target + '.class'))
            for name, descriptor in required:
                assert (name, descriptor) in methods, target + '.' + name
                target_checks.append({'class': target, 'method': name, 'descriptor': descriptor})
        fields = class_methods(game.read('net/minecraft/server/network/ServerLoginPacketListenerImpl.class'), True)
        assert ('authenticatedProfile', 'Lcom/mojang/authlib/GameProfile;') in fields
        if extra_targets:
            extra = json.loads(extra_targets.read_text())
            assert extra['actual_oracle_sha256'] == sha(game_jar.read_bytes())
            for row in extra['target_checks']:
                is_field = 'field' in row
                members = class_methods(game.read(row['class'] + '.class'), is_field)
                key = (row['field'] if is_field else row['method'], row['descriptor'])
                assert key in members, row
                target_checks.append(row)
    result = {'schema_version': 1, 'snapshot': manifest['snapshot'], 'mod_version': version,
              'source_hash': manifest['source_hash'], 'jar_sha256': artifact['sha256'], 'jar_bytes': artifact['bytes'],
              'classes': len(classes), 'mixins': len(mixins), 'java_class_major': 69,
              'jar_and_exact_source_hashes': 'PASS', 'no_minecraft_game_assets': 'PASS',
              'new_material_capture_classes': 'PASS', 'mixin_registration': 'PASS',
              'actual_target_descriptors': target_checks, 'minecraft_oracle_sha256': sha(game_jar.read_bytes()),
              'directed_tests': 'reused actual PASS: rebase19, scope12, V3 import/export2',
              'test_evidence_source': str(evidence), 'unchanged_test_and_production_input_hashes': {name: manifest['files'][name] for name in names},
              'old_matrices_repeated': False, 'runtime_actions': False,
              'runtime': 'pending lead-controlled cold loading, material color and native visual acceptance; target presence does not prove Mixin application'}
    (snapshot / 'artifact-checks.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key not in ('actual_target_descriptors', 'unchanged_test_and_production_input_hashes')}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--minecraft-jar', type=Path, required=True)
    parser.add_argument('--test-evidence', type=Path, required=True)
    parser.add_argument('--extra-targets', type=Path)
    args = parser.parse_args()
    verify(args.snapshot, args.minecraft_jar, args.test_evidence, args.extra_targets)
