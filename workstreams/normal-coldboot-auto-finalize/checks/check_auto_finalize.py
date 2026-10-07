"""Original persisted-wait recovery in a temporary root; no game or real native scope."""
import sys
sys.dont_write_bytecode = True
import argparse
import copy
import json
import subprocess
import tempfile
import time
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

parser = argparse.ArgumentParser()
parser.add_argument('--base', required=True, type=Path)
a = parser.parse_args()
HERE = Path(__file__).resolve().parent
DELTA = HERE.parent
sys.path.insert(0, str(DELTA / 'source'))
sys.path.insert(1, str(a.base.resolve()))
import installer, launcher
installer.__path__.insert(0, str(DELTA / 'source/installer'))
launcher.__path__.insert(0, str(DELTA / 'source/launcher'))
from installer import core, cli
from launcher import runtime, journal_lifecycle as journal
(HERE / 'temporary').mkdir(exist_ok=True)
actors = []
checks = []
with tempfile.TemporaryDirectory(prefix='same-boot-finalize-', dir=HERE / 'temporary') as temporary:
    root = Path(temporary).resolve() / 'owned player'
    root.mkdir()
    token = '1' * 32
    identity = {'world_id': 'A' * 32, 'pal_uid': '22222222-0000-0000-0000-000000000000',
                'mc_uuid': '11111111-1111-1111-1111-111111111111', 'mc_name': 'Fixture'}
    profile = {'platform': 'crossover', 'pal_entry_mode': 'singleplayer',
               'connection': {'transport': 'local', 'identity': identity},
               'standalone': {'save_account_directory': '123456789'}}
    core.atomic_json(root / '.palcraft/owner.json', {'root': str(root), 'id': 'finalize-fixture',
                       'kind': 'palcraft-player-owned-root'})
    core.atomic_json(root / '.palcraft/state.json', {'profile': profile})
    started = time.time() - 10
    owner = SimpleNamespace(root=root, token=token, children={}, session={'token': token, 'started_unix': started})
    life = journal.NormalLifecycle(owner, quiet_seconds=.02)
    def child():
        p = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(.08)'])
        actors.append(p)
        record = {'pid': p.pid, 'identity': runtime.process_identity(p.pid)}
        assert record['identity']
        return p, record
    supervisor, supervisor_record = child()
    client, record = child()
    life.register('client', record)
    owner.children['client'] = client
    supervisor.wait(timeout=3);client.wait(timeout=3)
    native = {'server_session_id': 'standalone:fixture-original-native', 'process_epoch': '1234:134000000000000001',
              'pid': 1234, 'world_id': identity['world_id'], 'pal_uid': identity['pal_uid'],
              'save_boot_id': 'fixture-original-save-boot'}
    life.scope['native_scope'] = native
    life.scope['normal_title_observed'] = {'request_id': '2' * 32, 'token': token,
                                         'process_epoch': native['process_epoch'], 'action': 'observe_title',
                                         'observed_unix': int(time.time())}
    life.save_scope()
    sp = lambda name: journal._scope_path(root, token, name)
    core.atomic_json(sp('stop-request.json'), {'token': token, 'root_id': 'finalize-fixture', 'force': False})
    save_id = '33333333-3333-3333-3333-333333333333'
    expected = {'protocol': 3, 'id': save_id, 'world_directory': native['world_id'], 'pal_uid': native['pal_uid']}
    submitted = time.time() - 2
    core.atomic_json(sp('save-request.json'), {'request': expected, 'submitted_unix': submitted, 'level_before': {}})
    level = root / core.USER / 'Saved/SaveGames/123456789' / identity['world_id'] / 'Level.sav'
    level.parent.mkdir(parents=True)
    level.write_bytes(b'fixture actual postsubmission stable Level file')
    core.atomic_json(root / '.palcraft/standalone/scope.json', {'installed_level_path_host': str(level)})
    exchange = root / core.DEV / 'bridge/exchange'
    for revision, status in [(1, 'normal_save_intent'), (2, 'normal_save_requested')]:
        row = dict(expected, revision=revision, status=status, boot_id=native['save_boot_id'])
        path = exchange / ('pal-client-save-' + save_id + '.r' + format(revision, '06d') + '.json')
        core.atomic_json(path, row);core.atomic_json(path.with_suffix('.durable.json'), row)
    wal = exchange / ('pal-client-save-' + save_id + '.r000002.json')
    st = journal.file_identity(level)
    witness = {'normal_save_id': save_id, 'level_mtime': st['mtime_ns'] / 1e9, 'level_bytes': st['bytes'],
               'level_sha256': core.digest(level), 'after_submission': True, 'stable': True,
               'normal_save_completed': True, 'native_scope': native, 'save_request_durable_sha256': core.digest(wal)}
    life.save_witness = witness
    core.atomic_json(sp('normal-save-file-witness.json'), witness)
    for action in ('return_title', 'observe_title', 'quit_title'):
        value = dict(life.scope['normal_title_observed'], action=action)
        request = {'request_id': value['request_id'], 'submitted_unix': submitted}
        core.atomic_json(sp(action + '-request.json'), request)
        core.atomic_json(sp(action + '-observation.json'), {'ok': True, 'result': value})
    core.atomic_json(root / '.palcraft/control' / (token + '.host.json'),
                     {'phase': 'stopped', 'exit_code': 0, 'primary_pid': native['pid'],
                      'primary_alive': False, 'job_active_processes': 0})
    event = root / journal.EVENTS
    event.parent.mkdir(parents=True, exist_ok=True)
    event.write_bytes(b'fixture original full immutable event volume\n')
    # Original finish itself creates the missing-receipt evidence using actual
    # Popen.wait, with only the native/port boundary simulated.
    with patch.object(runtime, '_port_free', return_value=False):
        pending = life.finish('stopped')
    assert pending['code'] == 'JOURNAL_WITNESS_PENDING' and pending['actor_exits']['client']['actual_wait_completed']
    assert pending['failed_conjuncts'] == ['port:25567', 'port:25599', 'port:25603']
    session = {'token': token, 'phase': 'stopped', 'normal_stop_stage': 'await_native_exit',
               'supervisor': supervisor_record, 'started_unix': started, 'journal_lifecycle': pending}
    core.atomic_json(root / '.palcraft/session.json', session)
    receipt_path = sp('normal-stop-receipt.json')
    assert not receipt_path.exists()
    def refusal(code):
        try:
            journal.prepare_cold_boot(root)
            raise AssertionError('bad input accepted')
        except core.PlayerError as error:
            assert error.code == code, error.code
        assert not receipt_path.exists()
    with patch.object(runtime, '_port_free', return_value=True):
        original_scope = copy.deepcopy(life.scope)
        broken = copy.deepcopy(original_scope);broken['token'] = '4' * 32
        core.atomic_json(sp('scope.json'), broken)
        refusal('JOURNAL_SCOPE')
        core.atomic_json(sp('scope.json'), original_scope)
        checks.append('wrong_scope_rejected')
        broken = copy.deepcopy(pending);broken['actor_exits']['client']['actual_wait_completed'] = False
        core.atomic_json(sp('incomplete-stop.json'), broken)
        core.atomic_json(root / '.palcraft/session.json', dict(session, journal_lifecycle=broken))
        refusal('JOURNAL_WITNESS_PENDING')
        core.atomic_json(sp('incomplete-stop.json'), pending);core.atomic_json(root / '.palcraft/session.json', session)
        checks.append('missing_original_actualwait_rejected')
        active, active_record = child()
        core.atomic_json(root / '.palcraft/session.json', dict(session, supervisor=active_record))
        refusal('JOURNAL_ACTOR_ALIVE')
        active.wait(timeout=3);core.atomic_json(root / '.palcraft/session.json', session)
        checks.append('actual_owned_live_supervisor_rejected_without_signalling')
        before = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in [level, event, wal, sp('scope.json'), root / '.palcraft/session.json']}
        dry = journal.finalize_stop(root, dry_run=True, quiet_seconds=.02)
        assert dry['ok'] and dry['dry_run'] and not receipt_path.exists()
        result = journal.finalize_stop(root, quiet_seconds=.02)
        assert result['ok'] and Path(result['normal_stop_receipt']) == receipt_path
        receipt = core.read_json(receipt_path)
        assert receipt['kind'] == 'palcraft-owned-normal-stop-v1' and receipt['token'] == token
        assert receipt['actor_exits'] == pending['actor_exits'] and receipt['normal_save_witness'] == witness
        assert receipt['stream_identity'] == journal.file_identity(event)
        assert all((p.read_bytes(), p.stat().st_mtime_ns) == v for p, v in before.items())
        checks.append('original_incomplete_finish_restored_by_same_issuer_without_save_stop_Popen_or_phase_edit')
        receipt_path.unlink()
        automatic_dry = journal.prepare_cold_boot(root, dry_run=True)
        assert automatic_dry['would_finalize_original_stop'] and not receipt_path.exists()
        unchanged = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in [level, wal, root / '.palcraft/session.json']}
        started = journal.prepare_cold_boot(root)
        assert started['ok'] and receipt_path.is_file() and not event.exists()
        archive = Path(started['archive'])
        assert archive.read_bytes() == before[event][0]
        assert all((p.read_bytes(), p.stat().st_mtime_ns) == v for p, v in unchanged.items())
        new_receipt = core.read_json(receipt_path)
        assert new_receipt['actor_exits'] == pending['actor_exits'] and new_receipt['normal_save_witness'] == witness
        checks.append('normal_coldboot_auto_finalizes_existing_stop_then_uses_original_rotator')
    # Original conservative bind must not mistake an actual LISTEN as free.
    import socket
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0));listener.listen()
        assert runtime._port_free(listener.getsockname()[1]) is False
    checks.append('unchanged_conservative_port_probe_rejects_real_ephemeral_LISTEN')
    for p in actors:
        assert p.poll() is not None
    report = {'schema': 1, 'passed': True, 'checks': checks,
              'original_NormalLifecycle_finish_actual_Popen_wait_record_used': True,
              'native_save_Title_host_boundary_simulated_in_temporary_fixture_only': True,
              'new_save_stop_signal_adopted_PID_or_fake_Popen_in_finalizer': False,
              'current_game_GUI_RPC_credential_Git_installed_state_or_actual_receipt_written': False,
              'actual_same_boot_finalization_by_runtime_done': False}
    (HERE / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
