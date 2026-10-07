"""Two bounded actual-function cases; all owner identities/readbacks are synthetic."""
from contextlib import nullcontext
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import time
import types

DELTA = Path(__file__).resolve().parents[1]
core = types.ModuleType('installer.core')
core.DEV = 'PalCraft-Dev'
core.configure = core.get_state = lambda *a, **k: None
core.fail = lambda code, message: (_ for _ in ()).throw(ValueError(code))
core.marker = lambda root: {'id': 'fixture-root'}
core.operation_lock = lambda root: nullcontext()
core.owned_path = lambda root, rel: Path(root) / rel
core.read_json = lambda path, default=None: json.loads(path.read_text()) if path.is_file() else default
def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))
core.atomic_json = write
sys.modules['installer.core'] = core
runtime = types.ModuleType('launcher.runtime')
runtime.process_matches = lambda record: record.get('identity') == 'fixture-birth'
sys.modules['launcher.runtime'] = runtime
spec = importlib.util.spec_from_file_location('power', DELTA / 'proposal/player/installer/performance.py')
power = importlib.util.module_from_spec(spec); spec.loader.exec_module(power)

targets = {'pal_fps': 60, 'mc_fps': 60, 'hud_fps': 30}
assert power.readback_matches('pal', {'pal_fps': 60, 'settings_limit': 60}, targets)
assert not power.readback_matches('pal', {'pal_fps': 60, 'settings_limit': 10}, targets)
assert not power.readback_matches('pal', {'pal_fps': 60}, targets)

class Child:
    def __init__(self, pid): self.pid = pid
    def poll(self): return None

with tempfile.TemporaryDirectory(prefix='palcraft-readback-source-') as temp:
    root = Path(temp); token = 'a' * 32
    control = root / '.palcraft/control'; control.mkdir(parents=True)
    bridge = root / 'PalCraft-Dev/bridge'; bridge.mkdir(parents=True)
    native = {'process_epoch': 'fixture-epoch', 'server_session_id': 'fixture-SID', 'world_id': 'fixture-world', 'pal_uid': 'fixture-UID'}
    o = types.SimpleNamespace(root=root, token=token, control=control, closing=False,
        should_close=lambda: False, session={'phase': 'running'},
        children={'client': Child(1), 'hud': Child(2)},
        journal=types.SimpleNamespace(roles={'mc_guest': Child(4), 'hud_relay': Child(5)}, scope={'native_scope': native}, pending=None))
    write(control / (token + '.hud-child.json'), {'token': token, 'root_id': 'fixture-root', 'wrapper_pid': 2,
                                                 'child': {'pid': 3, 'identity': 'fixture-birth'}})
    request = {'schema': 1, 'kind': power.LIVE_KIND, 'root_id': 'fixture-root', 'token': token,
               'request_id': 'b' * 32, 'targets': targets, 'expires_unix': time.time() + 10}
    write(control / (token + '.performance-request.json'), request)
    owner = power.OwnedPerformance(o); owner.tick()
    directory = control / (token + '.performance')
    (bridge / 'client-op.lua').unlink()
    write(bridge / 'client-op-result.json', {'ok': False, 'result': 'Unrelated operation failed', 'unix': time.time()})
    for role, pid, key in (('mc_guest', 4, 'mc_fps'), ('hud_relay', 5, 'hud_fps'), ('hud', 3, 'hud_fps')):
        value = {key: request[key] for key in ('schema', 'kind', 'root_id', 'token', 'request_id')}
        value.update(role=role, pid=pid, ok=True, actual={key: targets[key]})
        write(directory / (role + '.json'), value)
    owner.tick()
    result = core.read_json(control / (token + '.performance-result.json'))
    assert result['status'] == 'pending' and not result['remote_applied'] and 'pal' not in result['readbacks']
    before = power.time.time
    try:
        power.time.time = lambda: request['expires_unix'] + 1
        owner.tick()
    finally:
        power.time.time = before
    result = core.read_json(control / (token + '.performance-result.json'))
    assert result['status'] == 'timeout' and not result['remote_applied'] and 'pal' not in result['readbacks']
    assert len(result['readbacks']) == 3

receipt = {'schema': 1, 'ok': True, 'cases_passed': 2,
           'cases': ['Pal t.MaxFPS and settings_limit must both match',
                     'uncorrelated generic queue error remains unknown until timeout; partial role readbacks retained'],
           'synthetic_owner_native_identity_clock_and_peer_readback_only': True,
           'Game_GUI_RPC_credential_installed_source_or_runtime_operations': False,
           'MC_or_Swift_recompile': False}
(DELTA / 'checks/receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt))
