"""Three bounded source cases. All owner/native identities and role data are synthetic.

No installed state, world, credential, Game, GUI, socket, or running role is accessed.
The Pal script uses fake reflected setters; Swift exercises Foundation timers only.
"""
import ast
import argparse
from contextlib import nullcontext
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import threading
import time
import types

DELTA = Path(__file__).resolve().parents[1]
LUA = Path(os.environ.get('PALCRAFT_CHECK_LUA') or shutil.which('lua') or 'lua')
profile = {'fps': 60, 'performance': {'preset': 'normal', 'pal_fps': 60, 'mc_fps': 60, 'hud_fps': 30}}
configure_calls = []
core = types.ModuleType('installer.core')
core.DEV = 'PalCraft-Dev'
core.get_state = lambda root: {'profile': copy.deepcopy(profile)}
core.configure = lambda root, value, dry_run=False: configure_calls.append((copy.deepcopy(value), dry_run)) or {'ok': True}
core.fail = lambda code, message: (_ for _ in ()).throw(ValueError(code + ': ' + message))
core.marker = lambda root: {'id': 'fixture-root'}
core.owned_path = lambda root, relative: Path(root) / relative
core.operation_lock = lambda root: nullcontext()
def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    pending = path.with_suffix('.tmp'); pending.write_text(json.dumps(value)); pending.replace(path)
core.atomic_json = atomic_json
core.read_json = lambda path, default=None: json.loads(path.read_text()) if path.is_file() else default
sys.modules['installer.core'] = core
runtime = types.ModuleType('launcher.runtime')
runtime.process_matches = lambda record: record.get('identity') == 'fixture-birth'
sys.modules['launcher.runtime'] = runtime

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module

base = load('base_performance', DELTA / 'base/player/installer/performance.py')
power = load('proposal_performance', DELTA / 'proposal/player/installer/performance.py')
source = (DELTA / 'proposal/player/mac/hud/hud_relay.py').read_text()
relay_class = next(v for v in ast.parse(source).body if isinstance(v, ast.ClassDef) and v.name == 'Producer')
relay_env = {'threading': threading, 'time': time, 'os': os, 'json': json, 'Path': Path, 'WindowsMapping': object}
exec(compile(ast.Module(body=[relay_class], type_ignores=[]), 'actual-relay-Producer', 'exec'), relay_env)
Producer = relay_env['Producer']

class Child:
    def __init__(self, pid): self.pid = pid
    def poll(self): return None

def fixture(root, expires=None):
    token = 'a' * 32
    bridge = root / 'PalCraft-Dev/bridge'; bridge.mkdir(parents=True)
    control = root / '.palcraft/control'; control.mkdir(parents=True)
    request = {'schema': 1, 'kind': power.LIVE_KIND, 'root_id': 'fixture-root', 'token': token,
               'request_id': 'b' * 32, 'expires_unix': expires or time.time() + 20,
               'targets': {'pal_fps': 60, 'mc_fps': 60, 'hud_fps': 30, 'mc_render_distance': 4, 'mc_muted': True}}
    atomic_json(control / (token + '.performance-request.json'), request)
    (control / (token + '.heartbeat')).write_text('fixture')
    atomic_json(control / (token + '.hud-child.json'), {'token': token, 'root_id': 'fixture-root',
                'wrapper_pid': 12, 'child': {'pid': 13, 'identity': 'fixture-birth'}, 'created_by_this_worker': True})
    native = {'process_epoch': 'fixture-epoch', 'server_session_id': 'fixture-SID', 'world_id': 'fixture-world', 'pal_uid': 'fixture-UID'}
    owner = types.SimpleNamespace(root=root, token=token, control=control, closing=False,
        should_close=lambda: False, session={'phase': 'running'},
        children={'client': Child(11), 'hud': Child(12)},
        journal=types.SimpleNamespace(roles={'mc_guest': Child(14), 'hud_relay': Child(os.getpid())},
                                      scope={'native_scope': native}, pending=None))
    return owner, request, power.OwnedPerformance(owner)

def pal_fake_readback(request, native):
    script = """local frameLimit,maxFPS=15,15
function IsInGameThread()return true end
local s={};function s:IsValid()return true end;function s:GetFullName()return 'GameUserSettings Fixture' end
local function api(f)return setmetatable({}, {__tostring=function()return 'UFunction: Fixture' end,__call=function(_,...)return f(...)end})end
s.SetFrameRateLimit=api(function(_,v)frameLimit=v end)
s.ApplyNonResolutionSettings=api(function()end)
s.GetFrameRateLimit=api(function()return frameLimit end)
function FindAllOf(name)assert(name=='GameUserSettings');return {s}end
local k={};function k:IsValid()return true end;function k:GetConsoleVariableFloatValue()return maxFPS end
function k:ExecuteConsoleCommand(pc,command,owner)assert(pc==owner);maxFPS=assert(tonumber(command:match('t.MaxFPS (%d+)')))end
function StaticFindObject()return k end
local pc={};function pc:IsValid()return true end
local r={pc=pc,server_session_id='fixture-SID',world_id='fixture-world',host_uid='fixture-UID'}
_G.PalCraftStandaloneBootstrap={local_realm={current=function()return r end}}
_G.PalCraftStandalonePermissions={process=function()return {},'fixture-epoch' end}
local result=(function()
""" + power.pal_operation(request, native) + """end)()
assert(result.actual.pal_fps==60 and result.actual.settings_limit==60)
assert(result.request_id=='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' and result.process_epoch=='fixture-epoch')
print('Pal existing mailbox FPS setter/readback: PASS (fake UE only)')
"""
    result = subprocess.run([str(LUA), '-'], input=script, text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
    return {'kind': request['kind'], 'root_id': request['root_id'], 'token': request['token'],
            'request_id': request['request_id'], 'actual': {'pal_fps': 60, 'settings_limit': 60}, 'process_epoch': 'fixture-epoch'}

def swift_timer_case(directory, request):
    source = (DELTA / 'proposal/hud/hud_overlay.swift').read_text()
    methods = source[source.index('    private func scheduleDisplay()'):source.index('    private func position()')]
    harness = '''import Foundation
final class TimerFixture {
private var displayTimer: Timer?
private var displayFPS = 60.0
private var powerSeen: String?
private let powerEnvironment = ProcessInfo.processInfo.environment
private func display() { }
''' + methods + '''
func check() {
 scheduleDisplay(); let previous = displayTimer!
 applyOwnedPerformance()
 precondition(!previous.isValid && displayTimer!.isValid)
 precondition(abs(displayTimer!.timeInterval - 1.0/30.0) < 0.000001)
 let current = displayTimer!; applyOwnedPerformance(); precondition(displayTimer === current)
 displayTimer?.invalidate()
 print("Actual extracted Foundation timer apply/readback: PASS (no NSApp/UI)")
}
}
TimerFixture().check()
'''
    src = DELTA / 'checks/timer_fixture.swift'
    unchanged = src.is_file() and src.read_text() == harness
    src.write_text(harness)
    binary = DELTA / 'checks/timer_fixture'
    if not unchanged or not binary.is_file():
        result = subprocess.run(['/usr/bin/nice', '-n', '19', '/usr/bin/swiftc', str(src), '-o', str(binary)], text=True, capture_output=True)
        assert result.returncode == 0, result.stderr
    env = power.role_environment(directory.parents[2], request['token'], 'hud', os.environ)
    env['PALCRAFT_PERFORMANCE_DIR'] = str(directory)
    result = subprocess.run([str(binary)], env=env, text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
    value = json.loads((directory / 'hud.json').read_text())
    assert value['ok'] and abs(value['actual']['hud_fps'] - 30) < .001

def case_default():
    before = base.set_performance(Path('fixture'), 'night', dry_run=True)
    first = configure_calls[-1]
    after = power.set_performance(Path('fixture'), 'night', dry_run=True)
    assert after == before and configure_calls[-1] == first
    tree = ast.parse((DELTA / 'proposal/player/installer/cli.py').read_text())
    parser_fn = next(v for v in tree.body if isinstance(v, ast.FunctionDef) and v.name == 'make_parser')
    ns = {'argparse': argparse}; exec(compile(ast.Module(body=[parser_fn], type_ignores=[]), 'actual-CLI-parser', 'exec'), ns)
    parser = ns['make_parser']()
    value = parser.parse_args(['performance', '--root', 'fixture', '--preset', 'normal', '--live', '--mc-render-distance', '4', '--mc-muted', 'true'])
    assert value.live and value.mc_render_distance == 4 and value.mc_muted == 'true'
    assert parser.parse_args(['finalize-stop', '--root', 'fixture', '--codec-python', 'fixture-python']).codec_python == 'fixture-python'

def case_apply(root):
    o, request, owner = fixture(root)
    owner.tick()
    directory = o.control / (o.token + '.performance')
    assert (root / 'PalCraft-Dev/bridge/client-op.lua').is_file()
    assert json.loads((o.control / (o.token + '.performance-result.json')).read_text())['remote_applied'] is False
    native = o.journal.scope['native_scope']
    actual = pal_fake_readback(request, native)
    (root / 'PalCraft-Dev/bridge/client-op.lua').unlink()
    atomic_json(root / 'PalCraft-Dev/bridge/client-op-result.json', {'ok': True, 'result': actual})
    env = power.role_environment(root, o.token, 'hud_relay', os.environ)
    prior = dict(os.environ); os.environ.update(env)
    try:
        producer = Producer(types.SimpleNamespace(clients=0), 10, None)
        producer.power_checked = time.monotonic() - .251  # Advance this pure case to the next normal poll.
        assert (directory / 'request.json').is_file(), list(directory.iterdir())
        assert time.time() - (directory.parent / (o.token + '.heartbeat')).stat().st_mtime <= 12
        producer.apply_owned_performance()
        assert abs(producer.period - 1/30) < .000001, (producer.power_env, producer.period, request)
    finally:
        os.environ.clear(); os.environ.update(prior)
    swift_timer_case(directory, request)
    # Owner Popen handles remain synthetic. Correlated actual getter values are
    # fixtures, never a statement that the MC/HUD Game roles ran or are ready.
    hud = json.loads((directory / 'hud.json').read_text()); hud['pid'] = 13; atomic_json(directory / 'hud.json', hud)
    value = {key: request[key] for key in ('schema', 'kind', 'root_id', 'token', 'request_id')}
    value.update(role='mc_guest', pid=14, ok=True, actual={'mc_fps': 60, 'mc_render_distance': 4, 'mc_muted': True})
    atomic_json(directory / 'mc_guest.json', value)
    owner.tick()
    result = json.loads((o.control / (o.token + '.performance-result.json')).read_text())
    assert result['ok'] and result['remote_applied'] and set(result['readbacks']) == {'pal', 'mc_guest', 'hud_relay', 'hud'}
    assert result['config_changed'] is False

def case_reject(root):
    o, request, owner = fixture(root)
    stale = {**request, 'token': 'c' * 32}
    atomic_json(o.control / (o.token + '.performance-request.json'), stale)
    owner.tick(); assert not (root / 'PalCraft-Dev/bridge/client-op.lua').exists()
    atomic_json(o.control / (o.token + '.performance-request.json'), request)
    owner.tick()
    directory = o.control / (o.token + '.performance')
    value = {key: request[key] for key in ('schema', 'kind', 'root_id', 'token', 'request_id')}
    value.update(role='mc_guest', pid=14, ok=True, actual={'mc_fps': 10, 'mc_render_distance': 4, 'mc_muted': True})
    atomic_json(directory / 'mc_guest.json', value)
    owner.tick()
    result = json.loads((o.control / (o.token + '.performance-result.json')).read_text())
    assert result['status'] == 'rejected' and not result['remote_applied']
    o.closing = True; owner.seen = None
    atomic_json(o.control / (o.token + '.performance-request.json'), request)
    owner.tick()
    assert json.loads((o.control / (o.token + '.performance-result.json')).read_text())['status'] == 'cancelled'

case_default()
with tempfile.TemporaryDirectory(prefix='palcraft-source-power-') as temp:
    case_apply(Path(temp) / 'apply')
    case_reject(Path(temp) / 'reject')
receipt = {'schema': 1, 'ok': True, 'cases_passed': 3, 'cases': [
    'default configure return/profile unchanged',
    'same-owner request; original Pal mailbox script; relay period; actual extracted Foundation timer; four correlated readbacks',
    'stale owner rejected; mismatching actual options rejected; closing owner cancelled'],
    'all_native_owner_identity_and_MC_options_data_synthetic': True,
    'Foundation_Timer_only_no_NSApp_or_GUI': True, 'Pal_reflected_setters_fake_UE': True,
    'actual_MC_HUD_Game_roles_or_live_effect_not_verified': True,
    'installed_state_credentials_world_Game_GUI_RPC_network_or_Popen_role_actions': False}
(DELTA / 'checks/receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt))
