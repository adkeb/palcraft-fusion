"""Original Session loop and owned temporary Python children; AppKit/open are mocked."""
import sys
sys.dont_write_bytecode = True
import argparse
import copy
import importlib.util
import json
import subprocess
import tempfile
import threading
import time
from pathlib import Path
from unittest.mock import patch

parser = argparse.ArgumentParser()
parser.add_argument('--base', required=True, type=Path)
parser.add_argument('--player-overlay', required=True, type=Path)
parser.add_argument('--menu-overlay', required=True, type=Path)
parser.add_argument('--fixture', required=True, type=Path)
a = parser.parse_args()
HERE = Path(__file__).resolve().parent
DELTA = HERE.parent
sys.path.insert(0, str(DELTA / 'source'))
sys.path.insert(1, str(a.base.resolve()))
import installer, launcher
installer.__path__.insert(0, str(a.player_overlay.resolve() / 'installer'))
launcher.__path__.insert(0, str(DELTA / 'source/launcher'))
launcher.__path__.insert(1, str(a.player_overlay.resolve() / 'launcher'))
launcher.__path__.insert(2, str(a.menu_overlay.resolve() / 'launcher'))
from installer import core
from launcher import runtime, crossover_menu_helper as menu
spec = importlib.util.spec_from_file_location('original_bootstrap_fixture', a.fixture.resolve())
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
(HERE / 'temporary').mkdir(exist_ok=True)
tempfile.tempdir = str(HERE / 'temporary')
actual_run = subprocess.run
results = []

def setup():
    case = fixture.SingleplayerBootstrapTests()
    case.setUp()
    identity = {'world_id': 'A' * 32, 'pal_uid': '22222222-0000-0000-0000-000000000000',
                'mc_uuid': '11111111-1111-1111-1111-111111111111', 'mc_name': 'Fixture'}
    case.profile['connection']['identity'] = identity
    case.profile['connection']['frame_mapping'] = 'Local' + chr(92) + 'MCPassthroughFrame-' + identity['mc_uuid']
    case.profile = core.validate_profile(case.profile, case.root)
    case.state['profile'] = case.profile
    case.state['manifest']['requirements']['crossover_native_menu'] = menu.REQUIREMENT
    core.atomic_json(case.root / '.palcraft/state.json', case.state)
    core.atomic_json(case.root / '.palcraft/session.json', {'token': case.token, 'phase': 'starting',
                       'components': {}, 'launch_mode': runtime.BOOTSTRAP_MODE})
    script = case.root / core.TOOLS / 'launcher/crossover_menu_helper.py'
    script.parent.mkdir(parents=True, exist_ok=True)
    script.write_text("import time\nfrom pathlib import Path\nroot=Path(" + repr(str(case.root)) + ")\n"
                      "(root/'fixture-helper-started').write_text('fixture only')\n"
                      "while not (root/'.palcraft/control/" + case.token + ".stop').exists(): time.sleep(.01)\n")
    with patch.object(runtime, 'require_release_paths'):
        commands = runtime.command_plan(case.root, case.token, runtime.BOOTSTRAP_MODE)['commands']
    session = runtime.Session(case.root, case.token, commands=commands, probe=lambda *args, **kw: True, poll_seconds=.01)
    spec = menu.plan(case.root, case.profile, commands['client'][6:],
                     next(e['target'] for e in case.state['manifest']['files'] if e['role'] == 'client_host'))
    bundle = spec['bundle']
    executable = bundle / 'Contents/MacOS/Menu Helper'
    ready = {'pid': None, 'kernel_executable': str(executable), 'executable': str(executable),
             'bundle': str(bundle), 'bundle_identifier': spec['bundle_id'],
             'finished_launching': True, 'terminated': False}
    return case, session, ready

# Actual original loop waits for readiness, sends exactly one normal open, then
# uses the original .stop, Popen wait/poll and finish. No real app or game exists.
case, session, ready = setup()
thread = threading.Thread(target=session.run)
open_calls, observations = [], []
def observe(pid, expected_executable):
    observations.append(pid)
    value = dict(ready, pid=pid)
    if len(observations) == 1:
        return None
    if len(observations) == 2:
        value['finished_launching'] = False
    if len(observations) == 3:
        value['bundle'] = 'different-owned-app-is-refused'
    return value
def runner(command, *args, **kwargs):
    if command[:2] == ['/usr/bin/open', '-a']:
        open_calls.append(list(command))
        assert command == ['/usr/bin/open', '-a', ready['bundle']]
        assert session.children['client'].poll() is None
        return subprocess.CompletedProcess(command, 0, '', '')
    return actual_run(command, *args, **kwargs)
try:
    with patch.object(runtime, '_native_menu_application', side_effect=observe), patch.object(runtime.subprocess, 'run', side_effect=runner):
        thread.start()
        deadline = time.monotonic() + 3
        while not session.session.get('native_menu_open', {}).get('state') == 'returned':
            assert time.monotonic() < deadline
            time.sleep(.01)
        time.sleep(.05)
        assert len(open_calls) == 1 and len(observations) == 4
        receipt = core.read_json(case.root / '.palcraft/session.json')['native_menu_open']
        child = session.children['client']
        assert receipt['client']['pid'] == child.pid and runtime.process_matches(receipt['client'])
        assert receipt['returncode'] == 0 and receipt['client_exit_code_before'] is None
        assert receipt['client_exit_code_after'] is None and receipt['same_owned_client_identity_after'] is True
        assert receipt['game_ready_claimed'] is False and session.session['game_ready'] is False
        assert runtime.stop(case.root, timeout=3)['ok']
        thread.join(timeout=3)
        assert not thread.is_alive() and child.wait(timeout=1) == 0
        assert session.session['phase'] == 'stopped' and session.session['code'] == 'OK'
        assert receipt['client']['identity'] == session.session['components']['client']['identity']
    results.append('original_loop_pending_finished_and_exact_app_gates_once_open_then_original_stop')
finally:
    if thread.is_alive():
        runtime._write_control(case.root, case.token, 'close')
        thread.join(timeout=3)
    case.tearDown()

# A current-token Host permanently disables the event even if the file later
# disappears. A mismatched original child birth and a stop request never send.
case, session, ready = setup()
child = None
calls = []
try:
    (case.root / '.palcraft/logs').mkdir(exist_ok=True)
    child = session.spawn('client')
    ready['pid'] = child.pid
    session.save('bootstrap', game_ready=False)
    with patch.object(runtime, '_native_menu_application', return_value=ready) as observer, patch.object(runtime.subprocess, 'run', side_effect=runner):
        record = dict(session.session['components']['client'])
        session.session['components']['client']['identity'] = 'wrong-birth'
        session.save('bootstrap')
        session.native_menu_open_tick()
        assert observer.call_count == 0 and not session.native_menu_open_attempted
        session.session['components']['client'] = record
        session.save('bootstrap')
        host = session.control / (case.token + '.host.json')
        core.atomic_json(host, {'phase': 'running', 'primary_alive': True, 'fixture_only': True})
        session.native_menu_open_tick()
        host.unlink()
        session.native_menu_open_tick()
        assert session.native_menu_host_seen is True and observer.call_count == 0
        runtime._write_control(case.root, case.token, 'close')
        session.native_menu_open_tick()
        assert not session.native_menu_open_attempted
    child.wait(timeout=3)
    session.finish('stopped', 'OK', 'fixture original child wait completed')
    results.append('own_birth_host_seen_and_original_stop_refuse_open')
finally:
    if child is not None and child.poll() is None:
        runtime._write_control(case.root, case.token, 'close')
        child.wait(timeout=3)
    case.tearDown()

# A timeout is an unknown outcome of the sole request, not a reason to replay.
case, session, ready = setup()
child = None
unknown_calls = []
def unknown_runner(command, *args, **kwargs):
    if command[:2] == ['/usr/bin/open', '-a']:
        unknown_calls.append(command)
        raise subprocess.TimeoutExpired(command, 5)
    return actual_run(command, *args, **kwargs)
try:
    (case.root / '.palcraft/logs').mkdir(exist_ok=True)
    child = session.spawn('client')
    ready['pid'] = child.pid
    session.save('bootstrap', game_ready=False)
    # This own fixture child is Python, so its true kernel executable must fail
    # the expected Helper path before AppKit is ever loaded by the adapter.
    assert runtime._native_menu_application(child.pid, ready['executable']) is None
    with patch.object(runtime, '_native_menu_application', return_value=ready), patch.object(runtime.subprocess, 'run', side_effect=unknown_runner):
        session.native_menu_open_tick()
        session.native_menu_open_tick()
        receipt = session.session['native_menu_open']
        assert len(unknown_calls) == 1 and receipt['state'] == 'outcome_unknown'
        assert session.native_menu_open_attempted and receipt['client_exit_code_after'] is None
        assert session.session['game_ready'] is False and child.poll() is None
    runtime._write_control(case.root, case.token, 'close')
    child.wait(timeout=3)
    session.finish('stopped', 'OK', 'fixture original child wait completed')
    results.append('actual_own_kernel_mismatch_blocks_AppKit_and_unknown_request_never_replays')
finally:
    if child is not None and child.poll() is None:
        runtime._write_control(case.root, case.token, 'close')
        child.wait(timeout=3)
    case.tearDown()

result = {'schema': 1, 'passed': True, 'checks': results,
          'original_bootstrap_fixture_and_Session_loop_reused': True,
          'actual_owned_temporary_Python_Popen_children': 3,
          'AppKit_lifecycle_boundary_mocked': True, 'usr_bin_open_event_mocked': True,
          'actual_own_child_kernel_path_read_only': True,
          'native_AppKit_adapter_or_vendor_open_engine_verified': False,
          'current_game_or_GUI_RPC_Git_installed_sources_or_worlds_operated_on': False,
          'new_session_identity_or_game_ready_claimed': False}
(HERE / 'receipt.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
