"""One original temporary installer fixture: old deletion -> ordinary repaired update."""
import sys
sys.dont_write_bytecode = True
import argparse
import copy
import hashlib
import importlib.util
import io
import json
import tempfile
import zipfile
from pathlib import Path
from unittest.mock import patch

parser = argparse.ArgumentParser()
parser.add_argument('--base', required=True, type=Path)
parser.add_argument('--overlay', required=True, type=Path)
parser.add_argument('--fixture', required=True, type=Path)
a = parser.parse_args()
HERE = Path(__file__).resolve().parent
DELTA = HERE.parent
sys.path.insert(0, str(DELTA / 'source'))
sys.path.insert(1, str(a.overlay.resolve()))
sys.path.insert(2, str(a.base.resolve()))
import installer
installer.__path__.insert(0, str(DELTA / 'source/installer'))
installer.__path__.insert(1, str(a.overlay.resolve() / 'installer'))
from installer import core, standalone
from mac.scripts.prepare_launch import prepare_launch
spec = importlib.util.spec_from_file_location('unmodified_candidate10_core', DELTA / 'base/installer/core.py')
old_core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old_core)
spec = importlib.util.spec_from_file_location('original_player_fixture', a.fixture.resolve())
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
(HERE / 'temporary').mkdir(exist_ok=True)
tempfile.tempdir = str(HERE / 'temporary')
case = fixture.PlayerTests()
case.setUp()
try:
    root, backend = case.root, case.base / 'existing backend'
    mc_uuid = '11111111-1111-1111-1111-111111111111'
    identity = {'world_id': 'A' * 32, 'pal_uid': '22222222-0000-0000-0000-000000000000',
                'mc_uuid': mc_uuid, 'mc_name': 'Fixture'}
    case.profile.update(pal_entry_mode='singleplayer', standalone={'backend_root': str(backend),
        'save_account_directory': '123456789', 'enrollment_pending': True})
    case.profile['connection'].update(mode='strict-player', transport='local', server_session_id=None,
        identity=identity, local_ports={'mc_ws': 29599},
        frame_mapping='Local' + chr(92) + 'MCPassthroughFrame-' + mc_uuid)
    case.profile = core.validate_profile(case.profile, root)
    jar = io.BytesIO()
    with zipfile.ZipFile(jar, 'w') as archive:
        archive.writestr('fabric.mod.json', '{"schemaVersion":1,"id":"fixture","version":"fixture"}')
    mod_data = jar.getvalue()
    def release(version):
        dest = case.base / (version + '.zip')
        with zipfile.ZipFile(case.release1) as original, zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED) as archive:
            manifest = json.loads(original.read('manifest.json'))
            manifest['version'] = version
            manifest['requirements']['session_mode'] = 'strict-player'
            change = next(entry for entry in manifest['files'] if entry['role'] == 'client_main')
            changed_data = ('fixture never executed ' + version).encode()
            change.update(bytes=len(changed_data), sha256=hashlib.sha256(changed_data).hexdigest())
            for role, target, data in [
                ('minecraft_mod', core.DEV + '/minecraft-mods/passthrough-fixture.jar', mod_data),
                ('session_client', core.TOOLS + '/multiplayer/session_client.py', b'# fixture never executed\n')]:
                manifest['files'].append({'role': role, 'target': target, 'bytes': len(data),
                    'sha256': hashlib.sha256(data).hexdigest()})
                archive.writestr('payload/' + target, data)
            for entry in original.infolist():
                if entry.filename != 'manifest.json':
                    archive.writestr(entry, changed_data if entry.filename == 'payload/' + change['target']
                                     else original.read(entry.filename))
            archive.writestr('manifest.json', json.dumps(manifest))
        core.Bundle(dest)
        return dest
    releases = [release('template-v' + str(i)) for i in range(1, 5)]
    old_core.install(root, case.source, releases[0], case.profile)
    sentinel = root / core.USER / 'Saved/SaveGames/123456789' / identity['world_id'] / 'Level.sav'
    sentinel.parent.mkdir(parents=True)
    sentinel.write_bytes(b'fixture original Saved never touched')
    world = backend / 'server/world/level.dat'
    world.parent.mkdir(parents=True)
    world.write_bytes(b'fixture original MC world never touched')
    playerdata = world.parent / 'players/data' / (mc_uuid + '.dat')
    playerdata.parent.mkdir(parents=True)
    playerdata.write_bytes(b'fixture original MC inventory never touched')
    wal = root / core.DEV / 'bridge/exchange/original-ledger.json'
    wal.parent.mkdir(parents=True)
    wal.write_bytes(b'fixture original WAL never touched')
    kept = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in (sentinel, world, playerdata, wal)}
    target = core.TOOLS + '/standalone/previous-launch-plan.json'
    path = root / target
    original_args = {role: ['original-' + role, '空 格', '--unchanged="literal"'] for role in ('server', 'guest', 'hud')}
    roles = {role: {'role': role, 'cwd': str(cwd), 'executable': 'never-executed', 'main': 'never-executed',
                   'arguments': original_args[role], 'same_original_uuid': mc_uuid,
                   'frame_file': str(root / core.DEV / 'bridge/mcpt-hud.bin')}
             for role, cwd in [('server', backend / 'server'),
                               ('guest', backend / 'players' / mc_uuid / 'minecraft'),
                               ('hud', root / core.DEV / 'bridge')]}
    content = (json.dumps({'schema': 1, 'roles': roles, 'source_configuration_sha256': 'c' * 64,
                          'role_arguments_preserved': True}, ensure_ascii=False, indent=2) + '\n').encode()
    sha = hashlib.sha256(content).hexdigest()
    profile = copy.deepcopy(core.get_state(root)['profile'])
    profile['standalone']['backend_configuration'] = {'preserve_launch_template': str(path)}
    generated = standalone.generated_files(profile, core.get_state(root)['manifest'])
    generated[target] = content
    old_core.configure_standalone_transition(root, profile, generated)
    assert path.read_bytes() == content and core.get_state(root)['files'][target] == sha
    original_profile = core.get_state(root)['profile']
    old_core.update(root, releases[1])
    assert not path.exists() and target not in core.get_state(root)['files']
    assert core.get_state(root)['profile'] == original_profile
    deletions = []
    for receipt in (root / '.palcraft/transactions').glob('*/journal.json'):
        j = core.read_json(receipt)
        if any(c['target'] == target and c['new_sha256'] is None for c in j['changes']):
            deletions.append(receipt.parent)
    assert len(deletions) == 1
    backup = deletions[0] / 'before' / target
    assert backup.read_bytes() == content
    # A rejected recovery must not mutate state or regenerate fallback argv.
    backup.write_bytes(content + b'tampered')
    initial_state = core.get_state(root)
    try:
        core.update(root, releases[2])
        raise AssertionError('corrupt managed backup accepted')
    except core.PlayerError as exc:
        assert exc.code == 'RECOVERY_BACKUP'
    assert core.get_state(root) == initial_state and not path.exists()
    backup.write_bytes(content)
    core.update(root, releases[2])
    assert path.read_bytes() == content and core.get_state(root)['files'][target] == sha
    restored_receipt = next(j for j in (core.read_json(p) for p in (root / '.palcraft/transactions').glob('*/journal.json'))
                            if any(c['target'] == target and c['old_sha256'] is None and c['new_sha256'] == sha for c in j['changes'])
                            and j['before_state']['current'] == 'template-v2')
    assert restored_receipt['phase'] == 'committed'
    # Keep the template through later update, actual transaction undo and rollback.
    def fault(number, change):
        raise OSError('directed original transaction fault')
    state_v3 = core.get_state(root)
    try:
        core.update(root, releases[3], fault=fault)
        raise AssertionError('fault not reached')
    except OSError:
        pass
    assert core.get_state(root) == state_v3 and path.read_bytes() == content
    core.update(root, releases[3])
    assert path.read_bytes() == content and core.get_state(root)['files'][target] == sha
    core.rollback(root)
    assert core.get_state(root)['current'] == 'template-v3'
    assert path.read_bytes() == content and core.get_state(root)['profile'] == original_profile
    path.write_bytes(content + b'local edit')
    try:
        core.update(root, releases[3])
        raise AssertionError('modified owned template accepted')
    except core.PlayerError as exc:
        assert exc.code == 'UPDATE_CONFLICT'
    path.write_bytes(content)
    cfg_path = root / core.TOOLS / 'standalone/mac-runtime-config.json'
    backend.mkdir(exist_ok=True)
    core.atomic_json(backend / 'setup/mac-dependency-plan.json', {'libraries': []})
    library = backend / 'client/versions/26.3/26.3.jar'
    library.parent.mkdir(parents=True)
    library.write_bytes(b'fixture never executed')
    core.atomic_json(backend / 'client/versions/fabric-loader-0.19.5-26.3/fabric-loader-0.19.5-26.3.json',
                     {'arguments': {'jvm': []}, 'id': 'fixture'})
    prepare_launch(cfg_path)
    cfg = core.read_json(cfg_path)
    for role in original_args:
        metadata = core.read_json(Path(cfg['launch_dir']) / (role + '.json'))
        assert metadata['arguments'] == original_args[role]
        assert metadata['same_original_uuid'] == mc_uuid and metadata['configured_for_actual_boot'] is False
    assert all((p.read_bytes(), p.stat().st_mtime_ns) == value for p, value in kept.items())
    # Existing installed game session remains the ordinary mutation boundary.
    core.atomic_json(root / '.palcraft/session.json', {'token': '1' * 32, 'phase': 'bootstrap'})
    try:
        core.update(root, releases[3])
        raise AssertionError('active session update accepted')
    except core.PlayerError as exc:
        assert exc.code == 'CLIENT_BUSY'
    result = {'schema': 1, 'passed': True, 'original_player_installer_fixture_reused': True,
              'baseline_ordinary_update_deletion_reproduced': True,
              'original_config_only_transition_created_owned_template': True,
              'ordinary_Bundle_update_restored_only_verified_committed_deletion': True,
              'corrupt_archive_and_modified_current_file_rejected': True,
              'subsequent_update_rollback_and_fault_undo_retained_template': True,
              'original_prepare_launch_retained_three_role_argv_and_UUID': True,
              'active_session_mutation_rejected': True,
              'Saved_world_inventory_WAL_bytes_and_mtime_unchanged': True,
              'template_sha256_before_after': sha, 'all_fixtures_temporary': True,
              'processes_games_GUI_RPC_ports_and_Git': False, 'live_repair_applied': False}
    (HERE / 'receipt.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
finally:
    case.tearDown()
