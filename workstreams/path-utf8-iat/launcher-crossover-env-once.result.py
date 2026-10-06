"""Launch only personal processes; remote services are prerequisites, never targets."""
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import time
import uuid
import zipfile
from pathlib import Path

from installer.core import (BIN, CLIENT, DEV, LOCAL_PORTS, TOOLS, USER, PlayerError,
                            atomic_json, digest, ensure_no_session, fail, get_state,
                            marker, operation_lock, owned_path, read_json, require_release_paths, validate_profile)


from installer.paths import bottle_mapping_matches, windows_path


def executable_role(root, state, role):
    matches = [entry for entry in state['manifest']['files'] if entry.get('role') == role]
    if len(matches) != 1:
        fail('COMPONENT_ROLE', '组件清单不唯一：' + role)
    return owned_path(root, matches[0]['target'])


def crossover_environment(profile):
    env = os.environ.copy()
    env['CX_BOTTLE_PATH'] = str(Path(profile['bottle_root']).parent)
    env['CX_BOTTLE'] = profile['bottle_name']
    env['SteamAppId'] = '1623730'
    return env


def bottle_plan(root):
    root = Path(root).absolute()
    state = get_state(root)
    p = validate_profile(state['profile'], root)
    if p['platform'] != 'crossover':
        fail('BOTTLE_PLATFORM', 'Windows 安装不需要 CrossOver bottle。')
    bottle = Path(p['bottle_root'])
    app = Path(p['crossover_app'])
    manager = app / 'Contents/SharedSupport/CrossOver/bin/cxbottle'
    if not manager.is_file():
        fail('CROSSOVER_MISSING', '找不到 CrossOver 的 cxbottle 工具。', '安装 CrossOver 并在配置中填写 CrossOver.app。')
    if bottle.exists():
        own = read_json(bottle / '.palcraft-bottle.json', {})
        if own.get('root_id') != marker(root)['id']:
            fail('BOTTLE_UNMANAGED', '指定 bottle 已存在且不属于此安装器。', '换用新的 PalCraft-Player-* 名称，不接管 Steam 或 PalCraftLab。')
    for parent in [bottle, *bottle.parents]:
        if parent.is_symlink():
            fail('BOTTLE_LINK', '专用 bottle 路径不能经由符号链接。')
    return {'ok': True, 'dry_run': True, 'bottle': str(bottle),
            'windows_root': p['windows_root'], 'mapping': {'drive': 'Z:', 'host': '/', 'changed': False},
            'create': not bottle.exists(), 'command': [str(manager), '--bottle', p['bottle_name'], '--scope', 'private', '--create', '--template', 'win10_64'],
            'bottle_path_environment': str(bottle.parent)}


def create_bottle(root, dry_run=False, runner=subprocess.run):
    root = Path(root).absolute()
    plan = bottle_plan(root)
    if dry_run:
        return plan
    with operation_lock(root):
        ensure_no_session(root)
        state = get_state(root)
        p = state['profile']
        bottle = Path(plan['bottle'])
        if plan['create']:
            completed = runner(plan['command'], env=crossover_environment(p), timeout=180, capture_output=True, text=True)
            if completed.returncode or not (bottle / 'cxbottle.conf').is_file():
                fail('BOTTLE_CREATE', 'CrossOver 创建专用 bottle 失败。', '查看 CrossOver 许可和安装状态；未改动已有 bottle。')
            atomic_json(bottle / '.palcraft-bottle.json', {'schema': 1, 'root_id': marker(root)['id'], 'bottle_name': p['bottle_name']})
        if not bottle_mapping_matches(bottle):
            fail('BOTTLE_PATH_MAPPING', '专用 bottle 缺少标准 Z: 路径映射。',
                 '请在 CrossOver 中重建本安装专用 bottle；启动器不会改写盘符。')
        return {'ok': True, 'bottle': str(bottle), 'windows_root': p['windows_root'],
                'mapping_changed': False, 'existing_bottles_modified': []}


def _port_free(port, udp=False):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM if udp else socket.SOCK_STREAM) as sock:
            sock.bind(('127.0.0.1', port))
        return True
    except OSError:
        return False


def health(root, check_ports=False, require_models=True):
    root = Path(root).absolute()
    state = get_state(root)
    checks = []

    def add(code, ok, message, action=''):
        checks.append({'code': code, 'ok': bool(ok), 'message': message, 'action': action})

    if not state.get('installed') or not state.get('current'):
        add('NOT_INSTALLED', False, '尚未完成安装。', '运行安装向导。')
        return {'ok': False, 'checks': checks}
    p = validate_profile(state['profile'], root)
    shipping = owned_path(root, CLIENT + '/Pal/Binaries/Win64/Palworld-Win64-Shipping.exe')
    add('GAME_VERSION', shipping.is_file() and digest(shipping) == state.get('game_sha256'), '帕鲁版本校验。', '不要在此目录直接覆盖其他帕鲁版本。')
    for entry in state['manifest']['files']:
        path = owned_path(root, entry['target'])
        add('FILE_HASH', path.is_file() and digest(path) == entry['sha256'], '组件校验：' + entry['target'], '更新或回退到完整发布包。')
    settings_entries = [f for f in state['manifest']['files'] if f.get('role') == 'ue4ss_settings']
    if not settings_entries:
        add('HOT_RELOAD', False, '缺少禁用热重载的 UE4SS 设置。', '发布者应加入 ue4ss_settings 组件。')
    else:
        text = owned_path(root, settings_entries[0]['target']).read_text(encoding='utf-8-sig')
        safe = all(re.search(r'^\s*' + key + r'\s*=\s*0\s*$', text, re.M) for key in ('EnableHotReloadSystem', 'EnableAutoReloadingLuaMods'))
        add('HOT_RELOAD', safe, '原生模块要求禁用 Lua 热重载。', '重新安装受控 UE4SS 设置。')
    add('SSH_MISSING', shutil.which('ssh') is not None, '系统 SSH 客户端。', '安装 OpenSSH 客户端；先用管理员提供的别名完成密钥登录。')
    if p['platform'] == 'crossover':
        app = Path(p['crossover_app'])
        add('CROSSOVER_MISSING', (app / 'Contents/SharedSupport/CrossOver/bin/wine').is_file(), 'CrossOver 运行时。', '安装 CrossOver 后重新配置路径。')
        bottle = Path(p['bottle_root'])
        own = read_json(bottle / '.palcraft-bottle.json', {})
        add('BOTTLE_UNMANAGED', own.get('root_id') == marker(root)['id'], '独立玩家 bottle。', '运行 bottle-create。')
        add('BOTTLE_PATH_MAPPING', bottle_mapping_matches(bottle), '专用 bottle 的标准 Z: 路径映射。', '在 CrossOver 中重建专用 bottle，启动器不会更改盘符。')
    else:
        add('PLATFORM', os.name == 'nt', 'Windows 客户端运行环境。')
    model_manifest = owned_path(root, DEV + '/bridge/models/manifest.json')
    if require_models:
        model_info = read_json(model_manifest, {})
        add('MODELS_MISSING', model_info.get('schema') == 2 and model_info.get('models', 0) > 0 and model_info.get('textures', 0) > 0,
            'Minecraft 模型与纹理已从个人已有游戏提取。', '运行 resources 并选择自己已有的 Minecraft 客户端 jar。')
    if p['connection'].get('mode') == 'strict-player':
        from installer.credentials import inspect_credential
        try:
            public = inspect_credential(p['connection']['credential_path'])
            same = public['identity'] == p['connection']['identity'] and public['server_session_id'] == p['connection']['server_session_id']
            add('CREDENTIAL_IDENTITY', same, '个人凭据与配置身份一致。', '重新导入当前服务器会话的凭据。')
            executable_role(root, state, 'session_client')
            add('PROXY_COMPONENT', True, '严格会话协议与唯一代理已安装。')
        except PlayerError as exc:
            add(exc.code, False, exc.message, exc.action)
    if check_ports:
        for name, port in LOCAL_PORTS.items():
            add('PORT_BUSY', _port_free(port), '本地端口：' + name + ' ' + str(port), '先关闭另一个个人 PalCraft 客户端；启动器不会结束占用端口的程序。')
        if p['connection'].get('mode') == 'strict-player':
            add('PORT_BUSY', _port_free(25598), '严格代理上游 SSH 端口25598。', '关闭另一个个人客户端。')
        add('PORT_BUSY', _port_free(8321, udp=True), '本地 Palworld UDP 8321。', '关闭占用端口的个人程序。')
    return {'ok': all(x['ok'] for x in checks), 'version': state['current'], 'checks': checks, 'network_probed': False}


def command_plan(root, token):
    root = Path(root).absolute()
    state = get_state(root)
    p = validate_profile(state['profile'], root)
    ssh = shutil.which('ssh') or 'ssh'
    strict = p['connection'].get('mode') == 'strict-player'
    command = [ssh, '-N', '-T', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes', '-o', 'ConnectTimeout=10',
               '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2']
    for name, local in LOCAL_PORTS.items():
        if strict and name == 'mc_ws':
            local = 25598
        command += ['-L', '127.0.0.1:' + str(local) + ':127.0.0.1:' + str(p['connection']['remote_ports'][name])]
    command.append(p['connection']['ssh_target'])
    tools = owned_path(root, TOOLS)
    win_root = p['windows_root']
    require_release_paths(state['manifest'], p)
    control_windows = windows_path(win_root, '.palcraft/control')
    host = executable_role(root, state, 'client_host')
    host_windows = windows_path(win_root, host.relative_to(root).as_posix())
    args = ['--root', windows_path(win_root), '--control', control_windows, '--token', token, '--fps', str(p['fps'])]
    if p['mute']:
        args.append('--mute')
    commands = {'ssh': command,
                'udp': [sys.executable, str(tools / 'launcher/udp_tunnel_player.py'), '--tcp-port', '18321', '--udp-port', '8321',
                        '--status-file', str(root / '.palcraft/transport/udp-status.json')]}
    if strict:
        executable_role(root, state, 'session_client')
        commands['proxy'] = [sys.executable, str(tools / 'launcher/palcraft.py'), '_proxy', '--root', str(root), '--token', token]
    env = os.environ.copy()
    env['SteamAppId'] = '1623730'
    if p['platform'] == 'crossover':
        wine = Path(p['crossover_app']) / 'Contents/SharedSupport/CrossOver/bin/wine'
        commands['client'] = [str(wine), '--bottle', p['bottle_name'], '--debugmsg', '-all', '--dll', 'dwmapi=n,b',
                              '--env', 'SteamAppId=1623730',
                              '--workdir', windows_path(win_root, CLIENT), host_windows] + args
        hud = executable_role(root, state, 'mac_hud')
        commands['hud'] = [str(hud)]
        env = crossover_environment(p)
    else:
        commands['client'] = [str(host)] + args
    return {'ok': True, 'dry_run': True, 'root': str(root), 'commands': commands, 'stop_order': ['client', 'hud', 'proxy', 'udp', 'ssh'],
            'servers_started_or_stopped': [], 'environment': {'SteamAppId': '1623730', 'PALCRAFT_WINDOWS_ROOT': win_root,
                'CX_BOTTLE_PATH': env.get('CX_BOTTLE_PATH')}}


def process_identity(pid):
    if not isinstance(pid, int) or pid <= 0:
        return None
    try:
        if os.name == 'nt':
            import ctypes
            from ctypes import wintypes
            kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
            kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
            kernel32.OpenProcess.restype = wintypes.HANDLE
            kernel32.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(ctypes.c_ulonglong)] * 4
            kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
            handle = kernel32.OpenProcess(0x1000, False, pid)
            if not handle:
                return None
            creation, exit_, kernel, user = (ctypes.c_ulonglong() for _ in range(4))
            ok = kernel32.GetProcessTimes(handle, *(ctypes.byref(x) for x in (creation, exit_, kernel, user)))
            kernel32.CloseHandle(handle)
            return str(creation.value) if ok else None
        result = subprocess.run(['ps', '-p', str(pid), '-o', 'lstart='], capture_output=True, text=True, timeout=2)
        return result.stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def process_matches(record):
    return bool(record.get('identity')) and process_identity(record.get('pid')) == record['identity']


def status(root):
    root = Path(root).absolute()
    state = get_state(root)
    session = read_json(root / '.palcraft/session.json', {})
    alive = process_matches(session.get('supervisor', {}))
    binding = read_json(owned_path(root, DEV + '/bridge/session-bind-status.json'), {}) if state.get('profile', {}).get('connection', {}).get('mode') == 'strict-player' else {'state': 'legacy-lab'}
    udp = read_json(owned_path(root, '.palcraft/transport/udp-status.json'), {})
    client = read_json(owned_path(root, DEV + '/bridge/client-status.json'), {})
    current = time.time()
    def fresh(value, key):
        stamp = value.get(key)
        return type(stamp) in (int, float) and -5 <= current - stamp <= 3
    bound = binding.get('state') == 'bound' and binding.get('authenticated_host') is True and fresh(binding, 'updated_unix')
    transport_ready = udp.get('connected_peers', 0) > 0 and fresh(udp, 'updated_unix') and fresh(udp, 'last_reply_unix')
    local_gate = client.get('host_input_gate', {}).get('allowed') is True and fresh(client, 'unix')
    required = {'client', 'ssh', 'udp'}
    if state.get('profile', {}).get('connection', {}).get('mode') == 'strict-player':
        required.add('proxy')
    if state.get('profile', {}).get('platform') == 'crossover':
        required.add('hud')
    components_ready = all(process_matches(session.get('components', {}).get(name, {})) for name in required)
    game_ready = alive and components_ready and session.get('phase') == 'running' and bound and transport_ready and local_gate
    return {'ok': True, 'installed': state.get('installed', False), 'version': state.get('current'),
            'phase': session.get('phase', 'stopped'), 'supervisor_alive': alive,
            'components': {k: {'pid': v.get('pid'), 'alive': process_matches(v)} for k, v in session.get('components', {}).items()},
            'binding': binding, 'udp_transport': udp, 'transport_ready': transport_ready, 'game_ready': game_ready,
            'ready_definition': 'fresh strict binding + real local Pal UID gate + responding personal UDP + living managed session',
            'code': session.get('code'), 'message': session.get('message'), 'servers_started_or_stopped': []}


def _write_control(root, token, mode):
    if not re.fullmatch(r'[a-f0-9]{32}', token):
        fail('SESSION_TOKEN', '会话控制标识损坏，拒绝关闭其他进程。')
    path = owned_path(root, '.palcraft/control/' + token + '.stop')
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp')
    temp.write_text(mode + '\n', encoding='ascii')
    os.replace(temp, path)


def start(root, dry_run=False, timeout=20):
    root = Path(root).absolute()
    if dry_run:
        return command_plan(root, '0' * 32)
    with operation_lock(root):
        ensure_no_session(root)
        checks = health(root, check_ports=True)
        if not checks['ok']:
            bad = next(x for x in checks['checks'] if not x['ok'])
            fail(bad['code'], bad['message'], bad['action'])
        token = uuid.uuid4().hex
        state = get_state(root)
        session = {'schema': 1, 'token': token, 'phase': 'starting', 'components': {}, 'started_unix': time.time()}
        atomic_json(root / '.palcraft/session.json', session)
        logs = owned_path(root, '.palcraft/logs')
        logs.mkdir(exist_ok=True)
        tool = root / TOOLS / 'launcher/palcraft.py'
        with (logs / 'supervisor.log').open('ab') as output:
            cmd = [sys.executable, str(tool), '_session', '--root', str(root), '--token', token]
            try:
                process = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                                           start_new_session=os.name != 'nt', creationflags=0x08000000 if os.name == 'nt' else 0)
            except OSError as exc:
                session.update(phase='failed', code='SUPERVISOR_START', message=str(exc))
                atomic_json(root / '.palcraft/session.json', session)
                fail('SUPERVISOR_START', '启动器无法运行后台监督进程。', '运行 diagnostics 获取启动日志。')
        # The supervisor itself writes its identity; the starter never overwrites its newer state.
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        session = read_json(root / '.palcraft/session.json')
        if session['token'] != token:
            fail('SESSION_REPLACED', '启动期间会话被更换，已停止等待。')
        if session['phase'] == 'running':
            return {'ok': True, 'phase': 'running', 'game_ready': False, 'message': '个人客户端进程已启动；真实入服/身份/UDP状态见 status。', 'servers_started_or_stopped': []}
        if session['phase'] in ('failed', 'stopped'):
            fail(session.get('code', 'CLIENT_START'), session.get('message', '客户端启动失败。'), '运行 diagnostics，按错误提示处理后重试。')
        if process.poll() is not None:
            session.update(phase='failed', code='SUPERVISOR_EXIT', message='启动器后台进程异常退出。')
            atomic_json(root / '.palcraft/session.json', session)
            fail('SUPERVISOR_EXIT', '启动器后台进程异常退出。', '运行 diagnostics。')
        time.sleep(0.15)
    fail('START_PENDING', '启动仍在进行。', '运行 status 查看结果；stop 可以取消本次启动。')


def stop(root, force=False, dry_run=False, timeout=45):
    root = Path(root).absolute()
    marker(root)
    session = read_json(root / '.palcraft/session.json', {})
    if session.get('phase') in (None, 'stopped', 'failed'):
        return {'ok': True, 'phase': session.get('phase', 'stopped'), 'message': '个人客户端已关闭。', 'servers_started_or_stopped': []}
    if dry_run:
        return {'ok': True, 'dry_run': True, 'force': force, 'stop_order': ['client', 'hud', 'proxy', 'udp', 'ssh'], 'servers_started_or_stopped': []}
    # No signal is sent to a PID read from a file. The native host only observes its own token.
    _write_control(root, session['token'], 'force' if force else 'close')
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        now = read_json(root / '.palcraft/session.json')
        if now['token'] != session['token']:
            fail('SESSION_REPLACED', '会话已更换，不会关闭新会话。')
        if now['phase'] in ('stopped', 'failed'):
            return {'ok': True, 'phase': now['phase'], 'graceful': not force, 'servers_started_or_stopped': []}
        if not process_matches(now.get('supervisor', {})):
            return recover_session(root, wait_seconds=max(0, deadline - time.monotonic()))
        time.sleep(0.15)
    fail('CLOSE_PENDING', '游戏尚未完成正常退出，连接服务仍保留。', '在游戏中保存并退出后再运行 stop；仅确认接受未保存进度丢失时使用 stop --force。')


def recover_session(root, dry_run=False, wait_seconds=45):
    root = Path(root).absolute()
    session = read_json(owned_path(root, '.palcraft/session.json'), {})
    if session.get('phase') in (None, 'stopped', 'failed'):
        return {'ok': True, 'message': '没有待恢复的客户端会话。'}
    if process_matches(session.get('supervisor', {})):
        fail('CLIENT_BUSY', '后台启动器仍运行，请使用 stop 正常关闭。')
    if dry_run:
        return {'ok': True, 'dry_run': True, 'action': 'request_owned_client_close_and_wait_for_workers'}
    _write_control(root, session['token'], 'close')
    deadline = time.monotonic() + wait_seconds
    while True:
        alive = {k: v for k, v in session.get('components', {}).items() if process_matches(v)}
        if not alive:
            session.update(phase='stopped', code='OWNER_EXIT_RECOVERED', message='已恢复异常退出的个人启动器；未操作远端服务。')
            atomic_json(root / '.palcraft/session.json', session)
            return {'ok': True, 'phase': 'stopped', 'servers_started_or_stopped': []}
        if time.monotonic() >= deadline:
            fail('RECOVERY_PENDING', '仍有本次会话的进程在退出。', '先在个人游戏窗口保存退出；启动器不会按旧 PID 强制结束其他程序。')
        time.sleep(0.2)


def _connect_probe(port, kind, timeout=3):
    with socket.create_connection(('127.0.0.1', port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        if kind == 'mc_ws':
            sock.sendall(b'GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ZmFrZXBhbGNyYWZ0a2V5MQ==\r\nSec-WebSocket-Version: 13\r\n\r\n')
            data = sock.recv(4096)
            if not data.startswith(b'HTTP/1.1 101'):
                fail('MC_WS_UNAVAILABLE', '个人 MC 桥接服务未提供 WebSocket 握手。')
        elif kind == 'hud':
            # The HUD owns protocol validation. EOF means SSH cannot reach the remote relay.
            data = sock.recv(1)
            if not data:
                fail('HUD_UNAVAILABLE', '个人 HUD 服务无法连接。')
        elif kind == 'mc_server':
            # TCP reachability only; the MC guest owns login/authentication.
            pass
    return True


class Session:
    """Popen handles belong to this instance; no unscoped pkill/Stop-Process."""
    def __init__(self, root, token, commands=None, probe=None, poll_seconds=0.15):
        self.root, self.token = Path(root).absolute(), token
        self.state = get_state(root)
        self.commands = commands or command_plan(root, token)['commands']
        self.probe = probe or _connect_probe
        self.poll_seconds = poll_seconds
        self.children, self.outputs = {}, []
        self.session = read_json(self.root / '.palcraft/session.json')
        if self.session.get('token') != token:
            fail('SESSION_TOKEN', '后台会话标识不一致。')
        self.session['supervisor'] = {'pid': os.getpid(), 'identity': process_identity(os.getpid())}
        self.control = owned_path(root, '.palcraft/control')
        self.control.mkdir(exist_ok=True)
        self.heartbeat = self.control / (token + '.heartbeat')
        self.failure = None
        self.closing = False

    def save(self, phase, **kwargs):
        self.session.update(phase=phase, **kwargs)
        atomic_json(self.root / '.palcraft/session.json', self.session)

    def beat(self):
        self.heartbeat.write_text(str(int(time.time())) + '\n', encoding='ascii')

    def spawn(self, name):
        output = (self.root / '.palcraft/logs' / (name + '.log')).open('ab')
        self.outputs.append(output)
        env = crossover_environment(self.state['profile']) if self.state['profile']['platform'] == 'crossover' else os.environ.copy()
        env['SteamAppId'] = '1623730'
        env['PALCRAFT_WINDOWS_ROOT'] = validate_profile(self.state['profile'], self.root)['windows_root']
        env['PALCRAFT_HUD_PORT'] = '25603'
        env['PALCRAFT_BRIDGE_DIR'] = (str(self.root / DEV / 'bridge')
            if name == 'hud' and self.state['profile']['platform'] == 'crossover'
            else windows_path(env['PALCRAFT_WINDOWS_ROOT'], DEV + '/bridge'))
        env['PALCRAFT_FRAME_NAME'] = self.state['profile']['connection'].get('frame_mapping', 'Local\\MCPassthroughFrame')
        env['PALCRAFT_TITLEBAR_HEIGHT'] = str(self.state['profile'].get('titlebar_height', 28))
        if name in ('ssh', 'udp', 'hud', 'proxy'):
            # Worker leases expire if the supervisor crashes; the game is managed by its Win32 job host.
            args = [sys.executable, str(self.root / TOOLS / 'launcher/palcraft.py'), '_worker',
                    '--root', str(self.root), '--token', self.token, '--component', name, '--'] + self.commands[name]
        else:
            args = self.commands[name]
        process = subprocess.Popen(args, cwd=str(self.root / CLIENT), env=env, stdin=subprocess.DEVNULL,
                                   stdout=output, stderr=subprocess.STDOUT, start_new_session=os.name != 'nt')
        self.children[name] = process
        self.session['components'][name] = {'pid': process.pid, 'identity': process_identity(process.pid)}
        self.save('closing' if self.closing else 'starting')
        return process

    def should_close(self):
        return (self.control / (self.token + '.stop')).exists()

    def run(self, startup_timeout=15):
        (self.root / '.palcraft/logs').mkdir(exist_ok=True)
        self.save('starting')
        self.beat()
        try:
            self.spawn('ssh')
            deadline = time.monotonic() + startup_timeout
            for name in ('mc_ws', 'hud', 'mc_server'):
                while True:
                    self.beat()
                    if self.should_close():
                        return self.finish('stopped', 'START_CANCELLED', '启动已取消。')
                    if self.children['ssh'].poll() is not None:
                        fail('SSH_CONNECT', 'SSH 转发退出。', '检查登录密钥、已知主机记录及个人端口租约；不要覆盖 known_hosts。')
                    try:
                        self.probe(25598 if name == 'mc_ws' and self.state['profile']['connection'].get('mode') == 'strict-player' else LOCAL_PORTS[name], name, timeout=0.5)
                        break
                    except (OSError, PlayerError):
                        if time.monotonic() >= deadline:
                            fail('REMOTE_UNAVAILABLE', '个人服务未就绪：' + name, '联系服务器管理员启动你的个人 guest/HUD；此工具不会重启服务器。')
                        time.sleep(self.poll_seconds)
            if 'proxy' in self.commands:
                self.spawn('proxy')
            self.spawn('udp')
            if 'hud' in self.commands:
                self.spawn('hud')
            self.spawn('client')
            for _ in range(6):
                self.beat()
                time.sleep(self.poll_seconds)
                if any(child.poll() is not None for child in self.children.values()):
                    fail('COMPONENT_START', '某个个人组件在启动时退出。', '运行 diagnostics 查看组件日志。')
            self.save('running')
            while True:
                self.beat()
                if self.should_close():
                    self.closing = True
                    self.save('closing', message='正在等待个人游戏保存并退出。')
                client = self.children['client']
                if client.poll() is not None:
                    code = client.returncode
                    return self.finish('stopped' if code == 0 else 'failed', 'CLIENT_EXIT' if code else 'OK',
                                       '个人客户端已退出。' if code == 0 else '客户端异常退出，已关闭本次连接组件。')
                dead = [name for name, proc in self.children.items() if name != 'client' and proc.poll() is not None]
                if dead:
                    self.failure = ('CONNECTION_LOST', '连接组件异常退出：' + ', '.join(dead))
                    _write_control(self.root, self.token, 'close')
                    self.closing = True
                    self.save('closing', code=self.failure[0], message=self.failure[1] + '；等待游戏正常退出。')
                time.sleep(self.poll_seconds)
        except PlayerError as exc:
            # Startup failure before client launch can unwind immediately. If a client exists, ask its job host to close.
            if 'client' in self.children and self.children['client'].poll() is None:
                _write_control(self.root, self.token, 'close')
                self.save('closing', code=exc.code, message=exc.message)
                while self.children['client'].poll() is None:
                    self.beat()
                    time.sleep(self.poll_seconds)
            return self.finish('failed', exc.code, exc.message)
        except (OSError, KeyboardInterrupt) as exc:
            if 'client' in self.children and self.children['client'].poll() is None:
                _write_control(self.root, self.token, 'close')
                self.save('closing', code='SUPERVISOR_ERROR', message='监督进程请求游戏正常关闭。')
                while self.children['client'].poll() is None:
                    self.beat()
                    time.sleep(self.poll_seconds)
            return self.finish('failed', 'SUPERVISOR_ERROR', str(exc))

    def finish(self, phase, code, message):
        # Service wrappers only stop after the game process job is empty.
        for name in ('hud', 'proxy', 'udp', 'ssh'):
            child = self.children.get(name)
            if child is not None and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=5)
        for output in self.outputs:
            output.close()
        if self.failure:
            phase, code, message = 'failed', self.failure[0], self.failure[1]
        self.save(phase, code=code, message=message, stopped_unix=time.time())
        self.heartbeat.unlink(missing_ok=True)
        return {'ok': phase == 'stopped', 'phase': phase, 'code': code, 'message': message}


def run_worker(root, token, component, argv, lease_seconds=12):
    if component not in ('ssh', 'udp', 'hud', 'proxy') or not argv:
        fail('WORKER_COMPONENT', '无效的个人连接组件。')
    root = Path(root).absolute()
    session = read_json(owned_path(root, '.palcraft/session.json'))
    if session.get('token') != token:
        fail('SESSION_TOKEN', '连接组件租约已失效。')
    heartbeat = owned_path(root, '.palcraft/control/' + token + '.heartbeat')
    child = subprocess.Popen(argv, stdin=subprocess.DEVNULL)
    stopping = False

    def request_stop(*unused):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    try:
        while child.poll() is None and not stopping:
            if not heartbeat.is_file() or time.time() - heartbeat.stat().st_mtime > lease_seconds:
                break
            time.sleep(0.2)
    finally:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=3)
    return child.returncode or 0


def redact(text, state, root):
    p = state.get('profile', {})
    connection = p.get('connection', {})
    secrets = [str(root), str(Path.home()), p.get('bottle_root'), connection.get('ssh_target'),
               connection.get('server_session_id'), connection.get('credential_path')]
    for key in ('pal_uid', 'mc_uuid', 'mc_name', 'world_id'):
        secrets.append(connection.get('identity', {}).get(key))
    for value in sorted((str(x) for x in secrets if x), key=len, reverse=True):
        text = text.replace(value, '<已隐藏>')
    text = '\n'.join('<敏感日志行已隐藏>' if re.search(r'(?i)(password|token|holder_private|authorization|private_key|secret|ticket)', line) else line for line in text.splitlines())
    text = re.sub(r'(?i)(password|token|holder_private|authorization|private_key|secret)\s*[=:]\s*[^\s,}]+', r'\1=<已隐藏>', text)
    text = re.sub(r'(?i)[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', '<身份已隐藏>', text)
    text = re.sub(r'(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)', '<地址已隐藏>', text)
    text = re.sub(r'(?<!\d)7656119\d{10}(?!\d)', '<Steam身份已隐藏>', text)
    text = re.sub(r'\[U:1:\d+\]', '<Steam身份已隐藏>', text)
    return text


def diagnostics(root, output):
    root = Path(root).absolute()
    state = get_state(root)
    report = {'schema': 1, 'version': state.get('current'), 'platform': state.get('profile', {}).get('platform'),
              'health': health(root), 'status': status(root), 'generated_unix': time.time(),
              'privacy': '不收集游戏存档、Steam 数据、凭据、私钥或玩家身份文件。'}
    output = Path(output).absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('diagnostics.json', redact(json.dumps(report, ensure_ascii=False, indent=2), state, root))
        for name in ('supervisor', 'ssh', 'proxy', 'udp', 'hud', 'client'):
            path = owned_path(root, '.palcraft/logs/' + name + '.log')
            if path.is_file():
                with path.open('rb') as stream:
                    stream.seek(max(0, path.stat().st_size - 8192))
                    text = stream.read(8192).decode('utf-8', errors='replace')
                # Never include multi-line key blocks even in accidental tool output.
                text = re.sub(r'-----BEGIN[^-]*PRIVATE KEY-----.*?(?:-----END[^-]*PRIVATE KEY-----|\Z)', '<私钥已隐藏>', text, flags=re.S)
                archive.writestr('logs/' + name + '.log', redact(text, state, root))
    return {'ok': True, 'path': str(output), 'message': '已生成脱敏诊断包；分享前仍可自行查看。'}
