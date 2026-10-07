"""Exact scope-field and original enrollment writer boundaries; synthetic issuer only."""
import sys
sys.dont_write_bytecode = True
import argparse
import copy
import importlib.util
import json
import tempfile
from pathlib import Path
from unittest.mock import patch

parser = argparse.ArgumentParser()
parser.add_argument('--base', type=Path, required=True)
parser.add_argument('--player-overlay', type=Path, required=True)
a = parser.parse_args()
HERE = Path(__file__).resolve().parent
DELTA = HERE.parent
sys.path.insert(0, str(DELTA / 'source'))
sys.path.insert(1, str(a.base.resolve()))
import installer
installer.__path__.insert(0, str(DELTA / 'source/installer'))
installer.__path__.insert(1, str(a.player_overlay.resolve() / 'installer'))
from installer import core, credentials, standalone
spec = importlib.util.spec_from_file_location('original_candidate11_standalone', DELTA / 'base/installer/standalone.py')
original = importlib.util.module_from_spec(spec)
spec.loader.exec_module(original)
(HERE / 'temporary').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='normal-fluid-scope-', dir=HERE / 'temporary') as temporary:
    home = Path(temporary).resolve()
    root = home / '玩家 客户端'
    root.mkdir()
    bottle = home / 'bottles/SelectedFixture'
    (bottle / 'dosdevices').mkdir(parents=True)
    (bottle / 'dosdevices/z:').symlink_to('/')
    (bottle / 'cxbottle.conf').write_text('WineArch = "win64"\n')
    resume = {'persistent_identity': {'world_id': 'A' * 32,
        'pal_uid': '22222222-0000-0000-0000-000000000000', 'mc_uuid': None, 'mc_name': 'Fixture'},
        'save_account_directory': '123456789', 'world_origin': {'X': 0, 'Y': 0, 'Z': 0}}
    profile = standalone.make_profile(root, resume, bottle_name=bottle.name, bottle_root=bottle,
        crossover_app=home / 'apps/CrossOver.app', backend_root=home / 'existing backend')
    manifest = {'files': [{'role': 'minecraft_mod', 'target': core.DEV + '/minecraft-mods/passthrough-fixture.jar',
                           'sha256': 'f' * 64, 'bytes': 1}]}
    old = original.generated_files(profile, manifest)
    new = standalone.generated_files(profile, manifest)
    target = '.palcraft/standalone/scope.json'
    before, after = json.loads(old[target]), json.loads(new[target])
    assert 'client_log_windows' not in before
    expected = profile['windows_root'] + '/' + core.BIN + 'ue4ss/UE4SS.log'
    assert after.pop('client_log_windows') == expected and after == before
    assert all(new[key] == old[key] for key in old if key != target)
    assert not expected.startswith(profile['windows_root'] + '/BridgeLab/')
    assert json.loads(new[target])['fluid_dll_windows'] == before['fluid_dll_windows']
    core.atomic_json(root / '.palcraft/owner.json', {'kind': 'palcraft-player-owned-root',
                                                   'root': str(root), 'id': 'fluid-scope-fixture'})
    core.atomic_json(root / '.palcraft/state.json', {'installed': True, 'current': 'fixture',
                                                   'manifest': manifest, 'profile': profile, 'files': {}})
    scope = dict(before, retained_native_observation_reference='synthetic reference unchanged')
    cfg = json.loads(old[core.TOOLS + '/standalone/mac-runtime-config.json'])
    cfg['unknown_original_performance'] = {'retained': True}
    scope_path = root / target
    cfg_path = root / core.TOOLS / 'standalone/mac-runtime-config.json'
    permission_path = root / '.palcraft/standalone/owned-loaded-save-permission.json'
    core.atomic_json(scope_path, scope)
    core.atomic_json(cfg_path, cfg)
    core.atomic_json(permission_path, {'native_context': {'world_id': 'A' * 32}, 'fixture_boundary_only': True})
    existing = {}
    for relative in ['PalCraft-Client-User/Saved/SaveGames/123456789/' + 'A' * 32 + '/Level.sav',
                     core.DEV + '/bridge/exchange/existing-WAL.json']:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'fixture persistent existing data never touched')
        existing[path] = (path.read_bytes(), path.stat().st_mtime_ns)
    output = home / 'normal-enrollment-profile.json'
    issued = copy.deepcopy(profile)
    issued['connection']['server_session_id'] = 'standalone:fixture-original-issuer-boundary'
    with patch.object(credentials, 'prepare_credential_profile', return_value=(issued, {'inspection_only': True})) as issuer:
        result = standalone.enrollment_profile(root, home / 'fixture-guest-manifest-reference.json', output)
        assert issuer.call_count == 1 and result['new_identity_SID_grant_or_private_key_generated'] is False
    after_scope = core.read_json(scope_path)
    assert after_scope == dict(scope, configured_for_runtime=True, client_log_windows=expected)
    assert core.read_json(cfg_path) == dict(cfg, configured_for_actual_boot=True)
    public = core.read_json(output)
    assert public['connection']['identity'] == profile['connection']['identity']
    assert public['connection']['server_session_id'] == issued['connection']['server_session_id']
    assert public['standalone']['enrollment_pending'] is False
    assert after_scope['authority_or_game_ready_claimed'] is False
    snapshots = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in (scope_path, cfg_path, output)}
    core.atomic_json(permission_path, {'native_context': {'world_id': 'B' * 32}, 'fixture_boundary_only': True})
    with patch.object(credentials, 'prepare_credential_profile', return_value=(issued, {'inspection_only': True})):
        try:
            standalone.enrollment_profile(root, home / 'fixture-guest-manifest-reference.json', output)
            raise AssertionError('original permission world mismatch accepted')
        except core.PlayerError as error:
            assert error.code == 'ENROLLMENT_OBSERVATION'
    assert all((path.read_bytes(), path.stat().st_mtime_ns) == value for path, value in snapshots.items())
    assert all((path.read_bytes(), path.stat().st_mtime_ns) == value for path, value in existing.items())
    result = {'schema': 1, 'passed': True,
        'original_scope_generator_before_after_only_client_log_windows_changed': True,
        'Unicode_space_owned_root_windows_mapping_targets_private_client_UE4SS_log': True,
        'all_other_generated_files_and_scope_fields_unchanged': True,
        'original_enrollment_entry_backfills_old_scope_and_preserves_existing_fields': True,
        'original_issuer_boundary_mocked_no_credential_content_read': True,
        'original_permission_world_mismatch_still_refused_before_writes': True,
        'native_DLL_authority_UID_world_Saved_WAL_unchanged': True,
        'current_Lua_VM_reloaded_or_re_read_proven': False,
        'games_GUI_RPC_ports_Git_live_sources_or_actual_credentials_operated_on': False}
    (HERE / 'receipt.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
