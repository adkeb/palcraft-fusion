"""Personal display profiles and opt-in updates handled by the current local owner."""
import copy
import json
import os
import re
import time
import uuid
from pathlib import Path
from installer.core import configure, fail, get_state

PRESETS = {
    'normal': {'pal_fps': 60, 'mc_fps': 60, 'hud_fps': 30},
    'night': {'pal_fps': 15, 'mc_fps': 10, 'hud_fps': 10},
}


def validate_performance(value, pal_fps):
    if not isinstance(value, dict) or value.get('preset') not in ('normal', 'night', 'custom'):
        fail('CONFIG_PERFORMANCE', '帧率配置请选择 normal、night 或 custom。')
    for key, maximum in (('pal_fps', 120), ('mc_fps', 60), ('hud_fps', 120)):
        minimum = 10 if key == 'pal_fps' else 1
        if type(value.get(key)) is not int or not minimum <= value[key] <= maximum:
            fail('CONFIG_PERFORMANCE', key + ' 的帧率值不合法。')
    if value['pal_fps'] != pal_fps:
        fail('CONFIG_PERFORMANCE', 'fps 与 performance.pal_fps 必须一致。')
    return dict(value)


def with_preset(profile, preset, pal_fps=None, mc_fps=None, hud_fps=None):
    if preset not in PRESETS and preset != 'custom':
        fail('CONFIG_PERFORMANCE', '请选择 normal、night 或 custom。')
    result = copy.deepcopy(profile)
    values = dict(PRESETS.get(preset, result.get('performance', PRESETS['normal'])))
    values['preset'] = preset
    for key, value in (('pal_fps', pal_fps), ('mc_fps', mc_fps), ('hud_fps', hud_fps)):
        if value is not None:
            values[key] = value
    if any(x is not None for x in (pal_fps, mc_fps, hud_fps)):
        values['preset'] = 'custom'
    result['fps'] = values['pal_fps']
    result['performance'] = validate_performance(values, values['pal_fps'])
    return result


def remote_plan(profile):
    values = profile.get('performance', {**PRESETS['night'], 'preset': 'night'})
    return {'schema': 1, 'kind': 'palcraft-personal-performance-request',
            'identity': profile.get('connection', {}).get('identity'),
            'preset': values['preset'], 'targets': {key: values[key] for key in ('pal_fps', 'mc_fps', 'hud_fps')},
            'guest_jvm_argument': '-Dpalcraft.maxFps=' + str(values['mc_fps']),
            'hud_relay_arguments': ['--fps', str(values['hud_fps'])],
            'remote_applied': False, 'hardware_controls': False,
            'operator_action': 'Apply targets only to this assigned personal guest/relay; the player launcher does not control backend processes.'}


def set_performance(root, preset, pal_fps=None, mc_fps=None, hud_fps=None, dry_run=False,
                    live=False, mc_render_distance=None, mc_muted=None, timeout=10):
    state = get_state(root)
    profile = with_preset(state['profile'], preset, pal_fps, mc_fps, hud_fps)
    if live:
        targets = {key: profile['performance'][key] for key in ('pal_fps', 'mc_fps', 'hud_fps')}
        if mc_render_distance is not None:
            targets['mc_render_distance'] = mc_render_distance
        if mc_muted is not None:
            targets['mc_muted'] = mc_muted
        return request_live(root, targets, dry_run, timeout)
    if mc_render_distance is not None or mc_muted is not None:
        fail('CONFIG_PERFORMANCE', 'MC 距离和静音参数需要 --live。')
    configured = configure(root, profile, dry_run=dry_run)
    return {'ok': configured['ok'], 'dry_run': dry_run, 'performance': profile['performance'],
            'local_client_applies': 'on next personal client start', 'remote_plan': remote_plan(profile),
            'remote_applied': False, 'hardware_controls': False,
            'message': '个人帕鲁帧率已配置；MC/HUD目标需运营者应用到对应个人guest/relay。'}


LIVE_KIND = 'palcraft-owned-live-performance-v1'


def live_targets(value):
    if not isinstance(value, dict) or set(value) - {'pal_fps', 'mc_fps', 'hud_fps', 'mc_render_distance', 'mc_muted'}:
        fail('PERFORMANCE_TARGETS', '实时性能参数不合法。')
    validate_performance({'preset': 'custom', **value}, value.get('pal_fps'))
    if 'mc_render_distance' in value and (type(value['mc_render_distance']) is not int or not 2 <= value['mc_render_distance'] <= 32):
        fail('PERFORMANCE_TARGETS', 'MC 渲染距离必须为 2..32。')
    if 'mc_muted' in value and type(value['mc_muted']) is not bool:
        fail('PERFORMANCE_TARGETS', 'MC 静音值必须为 true 或 false。')
    return dict(value)


def role_environment(root, token, role, env):
    """Called only by the existing owner immediately before its role Popen."""
    from installer.core import marker, owned_path
    result = dict(env)
    result.update(PALCRAFT_PERFORMANCE_DIR=str(owned_path(root, '.palcraft/control/' + token + '.performance')),
                  PALCRAFT_PERFORMANCE_TOKEN=token, PALCRAFT_PERFORMANCE_ROOT_ID=marker(root)['id'],
                  PALCRAFT_PERFORMANCE_ROLE=role)
    return result


def request_live(root, targets, dry_run=False, timeout=10):
    from installer.core import atomic_json, marker, operation_lock, owned_path, read_json
    from launcher.runtime import process_matches
    from launcher.journal_lifecycle import enabled
    root = Path(root).absolute()
    targets = live_targets(targets)
    if not 1 <= timeout <= 30:
        fail('PERFORMANCE_TIMEOUT', '实时性能等待时间必须为 1..30 秒。')
    with operation_lock(root):
        state = get_state(root)
        session = read_json(owned_path(root, '.palcraft/session.json'), {})
        token = session.get('token', '')
        if (not enabled(state['profile']) or session.get('phase') != 'running'
                or not re.fullmatch(r'[a-f0-9]{32}', token)
                or not process_matches(session.get('supervisor', {}))):
            fail('PERFORMANCE_OWNER', '实时性能请求需要本安装正在运行的原单机 supervisor。')
        heartbeat = owned_path(root, '.palcraft/control/' + token + '.heartbeat')
        if not heartbeat.is_file() or time.time() - heartbeat.stat().st_mtime > 12:
            fail('PERFORMANCE_OWNER', '原 supervisor 租约未在刷新。')
        request_path = owned_path(root, '.palcraft/control/' + token + '.performance-request.json')
        previous = read_json(request_path, {})
        if previous.get('expires_unix', 0) > time.time():
            fail('PERFORMANCE_PENDING', '本会话已有待处理的实时性能请求。')
        request = {'schema': 1, 'kind': LIVE_KIND, 'root_id': marker(root)['id'], 'token': token,
                   'request_id': uuid.uuid4().hex, 'targets': targets, 'expires_unix': time.time() + timeout}
        if dry_run:
            return {'ok': True, 'dry_run': True, 'targets': targets, 'config_changed': False,
                    'remote_applied': False, 'owner_phase': session['phase']}
        atomic_json(request_path, request)
    result_path = owned_path(root, '.palcraft/control/' + token + '.performance-result.json')
    latest = None
    while time.time() < request['expires_unix']:
        value = read_json(result_path, {})
        if all(value.get(key) == request[key] for key in ('kind', 'root_id', 'token', 'request_id')):
            latest = value
            if value.get('status') != 'pending':
                return value
        time.sleep(.1)
    return {**(latest or {}), 'ok': False, 'status': 'timeout', 'remote_applied': False,
            'request_id': request['request_id'], 'targets': targets, 'config_changed': False,
            'message': '未取得全部实际读回；已取得的读回保留，不声称配置等于实时生效。'}


def pal_operation(request, native):
    """The original game-thread mailbox changes FPS only, never the world/save."""
    q = lambda value: json.dumps(value, ensure_ascii=False)
    prefix = "assert(IsInGameThread(),'Owned game thread required')\nlocal sp=assert(_G.PalCraftStandaloneBootstrap)\n"
    prefix += "local p,epoch=assert(_G.PalCraftStandalonePermissions).process()\nassert(epoch==" + q(native['process_epoch']) + ",'Native boot changed')\n"
    prefix += "local r=assert(sp.local_realm:current())\nassert(r.server_session_id==" + q(native['server_session_id']) + " and r.world_id==" + q(native['world_id']) + " and r.host_uid==" + q(native['pal_uid']) + ",'Loaded world changed')\n"
    prefix += "assert(os.time()<=" + str(request['expires_unix']) + ",'Performance request expired')\n"
    prefix += "local limit=" + str(request['targets']['pal_fps']) + "\n"
    return prefix + """local found={}
for _,v in ipairs(FindAllOf('GameUserSettings')or{})do
 if v and v:IsValid() and not v:GetFullName():find('Default__',1,true)then found[#found+1]=v end
end
assert(#found==1,'Actual GameUserSettings singleton required')
local s=found[1]
for _,name in ipairs({'SetFrameRateLimit','ApplyNonResolutionSettings','GetFrameRateLimit'})do
 assert(tostring(s[name]):match('^UFunction:'),'GameUserSettings API missing: '..name)
end
local k=assert(StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'))
assert(k:IsValid() and r.pc:IsValid(),'Actual client settings/controller unavailable')
s:SetFrameRateLimit(limit);s:ApplyNonResolutionSettings()
if math.abs(k:GetConsoleVariableFloatValue('t.MaxFPS')-limit)>=.01 then
 k:ExecuteConsoleCommand(r.pc,'t.MaxFPS '..tostring(limit),r.pc)
end
local actual={pal_fps=k:GetConsoleVariableFloatValue('t.MaxFPS'),settings_limit=s:GetFrameRateLimit()}
assert(math.abs(actual.pal_fps-limit)<.01 and math.abs(actual.settings_limit-limit)<.01,'Actual Pal FPS did not apply')
""" + "return {kind=" + q(LIVE_KIND) + ",root_id=" + q(request['root_id']) + ",token=" + q(request['token']) + ",request_id=" + q(request['request_id']) + ",process_epoch=epoch,actual=actual}\n"


def readback_matches(role, actual, targets):
    if not isinstance(actual, dict):
        return False
    key = 'pal_fps' if role == 'pal' else 'mc_fps' if role == 'mc_guest' else 'hud_fps'
    value = actual.get(key)
    if not isinstance(value, (int, float)) or abs(value - targets[key]) >= .001:
        return False
    if role == 'pal':
        limit = actual.get('settings_limit')
        return isinstance(limit, (int, float)) and abs(limit - targets['pal_fps']) < .001
    return role != 'mc_guest' or all(actual.get(key) == targets[key]
                                   for key in ('mc_render_distance', 'mc_muted') if key in targets)


class OwnedPerformance:
    """Nonblocking work in the existing Session loop, using its own Popen handles."""
    def __init__(self, owner):
        self.owner = owner
        self.pending = None
        self.seen = None

    def tick(self):
        from installer.core import DEV, atomic_json, marker, operation_lock, owned_path, read_json
        from launcher.runtime import process_matches
        o = self.owner
        root_id = marker(o.root)['id']
        request_path = o.control / (o.token + '.performance-request.json')
        result_path = o.control / (o.token + '.performance-result.json')
        directory = owned_path(o.root, '.palcraft/control/' + o.token + '.performance')
        request = self.pending['request'] if self.pending else read_json(request_path, {})
        if not request or (self.pending is None and request.get('request_id') == self.seen):
            return
        if (request.get('schema') != 1 or request.get('kind') != LIVE_KIND
                or request.get('root_id') != root_id or request.get('token') != o.token
                or not re.fullmatch(r'[a-f0-9]{32}', str(request.get('request_id', '')))):
            return

        def publish(status, message=None):
            reads = self.pending['readbacks'] if self.pending else {}
            result = {key: request[key] for key in ('schema', 'kind', 'root_id', 'token', 'request_id', 'targets')}
            result.update(ok=status == 'applied', status=status, remote_applied=status == 'applied',
                          readbacks=reads, config_changed=False, world_or_saved_changed_by_request=False, unix=time.time())
            if message:
                result['message'] = message
            atomic_json(result_path, result)
            if status != 'pending':
                self.pending = None
                self.seen = request['request_id']
                for path in (request_path, directory / 'request.json'):
                    if read_json(path, {}).get('request_id') == request['request_id']:
                        path.unlink(missing_ok=True)
            else:
                self.pending['published_readbacks'] = json.dumps(reads, sort_keys=True)

        if o.closing or o.should_close() or o.session.get('phase') != 'running':
            publish('cancelled', '原会话正在停止或尚未完整运行。')
            return
        if request.get('expires_unix', 0) <= time.time():
            publish('timeout', '原角色未在请求期限内完成全部读回。')
            return
        roles = {'mc_guest': o.journal.roles.get('mc_guest') if o.journal else None,
                 'hud_relay': o.journal.roles.get('hud_relay') if o.journal else None,
                 'hud': o.children.get('hud')}
        client = o.children.get('client')
        if (client is None or client.poll() is not None
                or any(child is None or child.poll() is not None for child in roles.values())
                or not o.journal.scope.get('native_scope')):
            publish('unavailable', '需要本 supervisor 已拥有的 client、个人 MC 和两层 HUD；不会另行启动或接管角色。')
            return
        hud_child = read_json(o.control / (o.token + '.hud-child.json'), {})
        if (hud_child.get('token') != o.token or hud_child.get('root_id') != root_id
                or hud_child.get('wrapper_pid') != roles['hud'].pid
                or not process_matches(hud_child.get('child', {}))):
            publish('unavailable', '原 HUD worker 的实际 child 身份未取得。')
            return
        if self.pending is None:
            live_targets(request['targets'])
            with operation_lock(o.root):
                bridge = o.root / DEV / 'bridge'
                target = bridge / 'client-op.lua'
                if target.exists() or (bridge / 'client-op.pending').exists() or o.journal.pending is not None:
                    return  # Existing form/normal lifecycle operation keeps the mailbox.
                result = bridge / 'client-op-result.json'
                prior = result.stat().st_mtime_ns if result.exists() else None
                source = pal_operation(request, o.journal.scope['native_scope'])
                pending = bridge / 'client-op.pending'
                pending.write_text(source, encoding='utf-8')
                os.replace(pending, target)
            self.pending = {'request': request, 'prior_pal_result': prior, 'readbacks': {},
                            'pids': {'mc_guest': roles['mc_guest'].pid, 'hud_relay': roles['hud_relay'].pid,
                                     'hud': hud_child['child']['pid']}}
            directory.mkdir(exist_ok=True)
            atomic_json(directory / 'request.json', request)
            publish('pending')
        reads = self.pending['readbacks']
        for role, pid in self.pending['pids'].items():
            value = read_json(directory / (role + '.json'), {})
            if (all(value.get(key) == request[key] for key in ('kind', 'root_id', 'token', 'request_id'))
                    and value.get('role') == role and value.get('pid') == pid):
                reads[role] = value
                if value.get('ok') is True and not readback_matches(role, value.get('actual'), request['targets']):
                    reads[role] = {**value, 'ok': False, 'error': 'Actual role readback differs from the request'}
        pal_result = o.root / DEV / 'bridge/client-op-result.json'
        if pal_result.exists() and pal_result.stat().st_mtime_ns != self.pending['prior_pal_result']:
            value = read_json(pal_result, {})
            result = value.get('result')
            if value.get('ok') is True and isinstance(result, dict) and all(result.get(key) == request[key] for key in ('kind', 'root_id', 'token', 'request_id')):
                reads['pal'] = {'ok': readback_matches('pal', result.get('actual'), request['targets'])
                                     and result.get('process_epoch') == o.journal.scope['native_scope']['process_epoch'],
                                'actual': result.get('actual'), 'process_epoch': result.get('process_epoch')}
            # Generic mailbox errors carry no operation ID. They cannot prove
            # this request failed; retain unknown until its normal deadline.
        if any(value.get('ok') is not True for value in reads.values()):
            publish('rejected', '至少一个原角色未完成实际参数应用；读回保留。')
        elif set(reads) == {'pal', 'mc_guest', 'hud_relay', 'hud'}:
            publish('applied')
        elif json.dumps(reads, sort_keys=True) != self.pending['published_readbacks']:
            publish('pending')
