"""Launch personal processes and owned local singleplayer actors; remote services remain prerequisites."""
import json
import os
import re
import shutil
import signal
import socket
import struct
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


HOST_PROXY_PORT_ENV = 'PALCRAFT_HOST_PROXY_PORT'
BOOTSTRAP_MODE = 'singleplayer-bootstrap'
BOOTSTRAP_PENDING = ['real_pal_uid_and_authority', 'mc_shared_and_guest', 'authenticated_proxy', 'hud', 'ai', 'full_game_ready']


def _validate_launch_mode(profile, launch_mode):
    if launch_mode not in ('full', BOOTSTRAP_MODE):
        fail('LAUNCH_MODE', '不支持的启动阶段。')
    if launch_mode == BOOTSTRAP_MODE and (profile.get('pal_entry_mode') != 'singleplayer' or
            profile['connection']['transport'] != 'local' or profile['connection'].get('mode') != 'strict-player'):
        fail('BOOTSTRAP_SCOPE', '单机观察阶段需要 singleplayer、本地连接和 strict-player 配置。',
             '先配置实际的本地单机入口；观察完成后使用完整 start。')
    return launch_mode == BOOTSTRAP_MODE


def _require_proxy_port_runtime(state, profile):
    if (profile['connection']['transport'] == 'local' or profile['local_ports']['mc_ws'] != LOCAL_PORTS['mc_ws']):
        if state['manifest'].get('requirements', {}).get('native_host_proxy_port_env') != HOST_PROXY_PORT_ENV:
            fail('PROXY_PORT_COMPONENT', '当前原生组件没有个人代理端口契约。', '使用同批支持 PALCRAFT_HOST_PROXY_PORT 的原生模块和发布清单。')


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


def _selected_bottle_readonly(bottle):
    conf = bottle / 'cxbottle.conf'
    if not conf.is_file() or not bottle_mapping_matches(bottle):
        fail('BOTTLE_SELECTED', '所选既有 bottle 缺少配置或标准 Z: 映射。')
    text = conf.read_text(encoding='utf-8')
    if not re.search(r'(?im)^\s*"?WineArch"?\s*=\s*"?win64"?\s*$', text):
        fail('BOTTLE_SELECTED_ARCH', '所选既有 bottle 必须为 win64。')
    return True


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
    selected = p.get('bottle_mode') == 'existing-selected'
    if selected:
        _selected_bottle_readonly(bottle)
    elif bottle.exists():
        own = read_json(bottle / '.palcraft-bottle.json', {})
        if own.get('root_id') != marker(root)['id']:
            fail('BOTTLE_UNMANAGED', '指定 bottle 已存在且不属于此安装器。', '选择新建专用 bottle 或显式 existing-selected；不接管外部 bottle。')
    for parent in [bottle, *bottle.parents]:
        if parent.is_symlink():
            fail('BOTTLE_LINK', '专用 bottle 路径不能经由符号链接。')
    return {'ok': True, 'dry_run': True, 'bottle': str(bottle),
            'windows_root': p['windows_root'], 'mapping': {'drive': 'Z:', 'host': '/', 'changed': False},
            'create': not selected and not bottle.exists(), 'selected_external_runtime': selected,
            'command': [] if selected else [str(manager), '--bottle', p['bottle_name'], '--scope', 'private', '--create', '--template', 'win10_64'],
            'bottle_path_environment': str(bottle.parent)}


def create_bottle(root, dry_run=False, runner=subprocess.run):
    root = Path(root).absolute()
    plan = bottle_plan(root)
    if dry_run:
        return plan
    if plan.get('selected_external_runtime'):
        return {'ok': True, 'bottle': plan['bottle'], 'selected_external_runtime': True,
                'created': False, 'modified': False, 'ownership_claimed': False}
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
        addresses = ('127.0.0.1',) if udp else ('127.0.0.1', '0.0.0.0')
        for address in addresses:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM if udp else socket.SOCK_STREAM) as sock:
                if not udp:
                    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                sock.bind((address, port))
                if not udp:
                    sock.listen(1)
        return True
    except OSError:
        return False

def health(root, check_ports=False, require_models=True, launch_mode='full', profile=None):
    root = Path(root).absolute()
    state = get_state(root)
    checks = []

    def add(code, ok, message, action=''):
        checks.append({'code': code, 'ok': bool(ok), 'message': message, 'action': action})

    if not state.get('installed') or not state.get('current'):
        add('NOT_INSTALLED', False, '尚未完成安装。', '运行安装向导。')
        return {'ok': False, 'checks': checks}
    p = validate_profile(state['profile'] if profile is None else profile, root)
    observing = _validate_launch_mode(p, launch_mode)
    shipping = owned_path(root, CLIENT + '/Pal/Binaries/Win64/Palworld-Win64-Shipping.exe')
    add('GAME_VERSION', shipping.is_file() and digest(shipping) == state.get('game_sha256'), '帕鲁版本校验。', '不要在此目录直接覆盖其他帕鲁版本。')
    generated_mcp = {}
    if p.get('standalone') is not None:
        from installer.standalone import generated_files
        import hashlib
        generated = generated_files(p, state['manifest'])
        for target in (DEV + '/mcp/ai-transport.json', DEV + '/mcp/mc-transport.json'):
            expected = hashlib.sha256(generated[target]).hexdigest()
            generated_mcp[target] = expected
    for entry in state['manifest']['files']:
        path = owned_path(root, entry['target'])
        expected = generated_mcp.get(entry['target'], entry['sha256'])
        registered = entry['target'] not in generated_mcp or state.get('files', {}).get(entry['target']) == expected
        add('FILE_HASH', registered and path.is_file() and digest(path) == expected, '组件校验：' + entry['target'], '更新或回退到完整发布包。')
    manifest_targets = {entry['target'] for entry in state['manifest']['files']}
    for target, expected in generated_mcp.items():
        if target not in manifest_targets:
            path = owned_path(root, target)
            add('FILE_HASH', state.get('files', {}).get(target) == expected and path.is_file() and digest(path) == expected,
                '组件校验：' + target, '重新配置本安装的正常 standalone 传输配置。')
    settings_entries = [f for f in state['manifest']['files'] if f.get('role') == 'ue4ss_settings']
    if not settings_entries:
        add('HOT_RELOAD', False, '缺少禁用热重载的 UE4SS 设置。', '发布者应加入 ue4ss_settings 组件。')
    else:
        text = owned_path(root, settings_entries[0]['target']).read_text(encoding='utf-8-sig')
        safe = all(re.search(r'^\s*' + key + r'\s*=\s*0\s*$', text, re.M) for key in ('EnableHotReloadSystem', 'EnableAutoReloadingLuaMods'))
        add('HOT_RELOAD', safe, '原生模块要求禁用 Lua 热重载。', '重新安装受控 UE4SS 设置。')
    if p['connection']['transport'] == 'ssh':
        add('SSH_MISSING', shutil.which('ssh') is not None, '系统 SSH 客户端。', '安装 OpenSSH 客户端；先用管理员提供的别名完成密钥登录。')
    try:
        _require_proxy_port_runtime(state, p)
    except PlayerError as exc:
        add(exc.code, False, exc.message, exc.action)
    if p['platform'] == 'crossover':
        app = Path(p['crossover_app'])
        add('CROSSOVER_MISSING', (app / 'Contents/SharedSupport/CrossOver/bin/wine').is_file(), 'CrossOver 运行时。', '安装 CrossOver 后重新配置路径。')
        bottle = Path(p['bottle_root'])
        if p.get('bottle_mode') == 'existing-selected':
            try:
                _selected_bottle_readonly(bottle)
                add('BOTTLE_SELECTED', True, '显式选择的外部 win64 Steam-ready runtime；本安装不拥有或修改该 bottle。')
            except PlayerError as exc:
                add(exc.code, False, exc.message, exc.action)
        else:
            own = read_json(bottle / '.palcraft-bottle.json', {})
            add('BOTTLE_UNMANAGED', own.get('root_id') == marker(root)['id'], '独立玩家 bottle。', '运行 bottle-create。')
        add('BOTTLE_PATH_MAPPING', bottle_mapping_matches(bottle), '专用 bottle 的标准 Z: 路径映射。', '在 CrossOver 中重建专用 bottle，启动器不会更改盘符。')
    else:
        add('PLATFORM', os.name == 'nt', 'Windows 客户端运行环境。')
    model_directory = state['manifest'].get('requirements', {}).get('player_runtime', {}).get('model_asset_directory', 'models')
    model_manifest = owned_path(root, DEV + '/bridge/' + model_directory + '/manifest.json')
    if require_models:
        model_info = read_json(model_manifest, {})
        add('MODELS_MISSING', model_info.get('schema') in (2, 4) and model_info.get('models', 0) > 0 and model_info.get('textures', 0) > 0,
            '本安装的模型与纹理清单已就绪。', '取得同批资源或运行本版规定的个人 Minecraft 资源转换入口。')
    if p['connection'].get('mode') == 'strict-player' and not observing:
        from installer.credentials import inspect_credential
        try:
            public = inspect_credential(p['connection']['credential_path'])
            same = public['identity'] == p['connection']['identity'] and public['server_session_id'] == p['connection']['server_session_id']
            add('CREDENTIAL_IDENTITY', same, '个人凭据与配置身份一致。', '重新导入当前服务器会话的凭据。')
            executable_role(root, state, 'session_client')
            add('PROXY_COMPONENT', True, '严格会话协议与唯一代理已安装。')
        except PlayerError as exc:
            add(exc.code, False, exc.message, exc.action)
    if check_ports and not observing:
        bindings = p['local_ports'] if p['connection']['transport'] == 'ssh' else {'mc_ws': p['local_ports']['mc_ws']}
        for name, port in bindings.items():
            add('PORT_BUSY', _port_free(port), '本地端口：' + name + ' ' + str(port), '先关闭另一个个人 PalCraft 客户端；启动器不会结束占用端口的程序。')
        if p['connection']['transport'] == 'ssh':
            if p['connection'].get('mode') == 'strict-player':
                add('PORT_BUSY', _port_free(p['proxy_upstream_port']), '严格代理上游 SSH 端口：' + str(p['proxy_upstream_port']), '关闭另一个个人客户端。')
            add('PORT_BUSY', _port_free(8321, udp=True), '本地 Palworld UDP 8321。', '关闭占用端口的个人程序。')
    return {'ok': all(x['ok'] for x in checks), 'version': state['current'], 'checks': checks, 'network_probed': False,
            'launch_mode': launch_mode, 'deferred': BOOTSTRAP_PENDING[:] if observing else []}


def command_plan(root, token, launch_mode='full'):
    root = Path(root).absolute()
    state = get_state(root)
    p = validate_profile(state['profile'], root)
    observing = _validate_launch_mode(p, launch_mode)
    _require_proxy_port_runtime(state, p)
    ssh = shutil.which('ssh') or 'ssh'
    strict = p['connection'].get('mode') == 'strict-player'
    command = [ssh, '-N', '-T', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes', '-o', 'ConnectTimeout=10',
               '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2']
    for name, local in p['service_ports'].items():
        command += ['-L', '127.0.0.1:' + str(local) + ':127.0.0.1:' + str(p['connection']['remote_ports'][name])]
    if p['connection']['transport'] == 'ssh':
        command.append(p['connection']['ssh_target'])
    tools = owned_path(root, TOOLS)
    win_root = p['windows_root']
    require_release_paths(state['manifest'], p)
    control_windows = windows_path(win_root, '.palcraft/control')
    host = executable_role(root, state, 'client_host')
    host_windows = windows_path(win_root, host.relative_to(root).as_posix())
    args = ['--root', windows_path(win_root), '--control', control_windows, '--token', token, '--fps', str(p['fps'])]
    if p.get('launch_shipping') is True:
        args.append('--shipping')
    if p['mute']:
        args.append('--mute')
    commands = {}
    if p['connection']['transport'] == 'ssh':
        commands.update(ssh=command,
                        udp=[sys.executable, str(tools / 'launcher/udp_tunnel_player.py'), '--tcp-port', str(p['local_ports']['udp_tcp']), '--udp-port', '8321',
                             '--status-file', str(root / '.palcraft/transport/udp-status.json')])
    if strict and not observing:
        executable_role(root, state, 'session_client')
        commands['proxy'] = [sys.executable, str(tools / 'launcher/palcraft.py'), '_proxy', '--root', str(root), '--token', token]
    env = os.environ.copy()
    env['SteamAppId'] = '1623730'
    if p['platform'] == 'crossover':
        wine = Path(p['crossover_app']) / 'Contents/SharedSupport/CrossOver/bin/wine'
        commands['client'] = [str(wine), '--bottle', p['bottle_name'], '--enable-alt-loader', '1', '--debugmsg', '-all', '--dll', 'dwmapi=n,b',
                              '--env', 'SteamAppId=1623730',
                              '--workdir', windows_path(win_root, CLIENT), host_windows] + args
        if state['manifest'].get('requirements', {}).get('crossover_native_menu') == 'windows-menu-helper-v1':
            commands['client'] = [sys.executable, str(tools / 'launcher/crossover_menu_helper.py'),
                                  '--root', str(root), 'run', '--'] + commands['client']
        if not observing:
            hud = executable_role(root, state, 'mac_hud')
            commands['hud'] = [str(hud)]
        env = crossover_environment(p)
    else:
        commands['client'] = [str(host)] + args
    return {'ok': True, 'dry_run': True, 'root': str(root), 'commands': commands, 'stop_order': ['client', 'hud', 'proxy', 'udp', 'ssh'],
            'servers_started_or_stopped': [], 'transport': p['connection']['transport'],
            'launch_mode': launch_mode, 'game_ready': False, 'mc_actions_authorized': False,
            'pending': BOOTSTRAP_PENDING[:] if observing else [],
            'environment': {'SteamAppId': '1623730', 'PALCRAFT_WINDOWS_ROOT': win_root,
                HOST_PROXY_PORT_ENV: str(p['local_ports']['mc_ws']),
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


def _mac_game_foreground_group(root, token, runner=subprocess.run, identity_reader=process_identity):
    """Bind the one current native Game and its owned menu App; no process is adopted."""
    try:
        session = read_json(owned_path(root, '.palcraft/session.json'))
        scope = read_json(owned_path(root, '.palcraft/standalone/scope.json'))
        permission = read_json(owned_path(root, '.palcraft/standalone/owned-loaded-save-permission.json'))
        client = session['components']['client']
        opened = session['native_menu_open']
        bundle = str(owned_path(root, '.palcraft/native-menu/PalCraft Game.app'))
        if (session.get('token') != token or session.get('phase') not in ('starting', 'bootstrap', 'promoting', 'running')
                or opened.get('state') != 'returned' or opened.get('returncode') != 0
                or opened.get('token') != token or opened.get('bundle') != bundle
                or opened.get('client') != client or not opened.get('bundle_identifier')
                or identity_reader(client['pid']) != client['identity']):
            return None
        record_path = Path(permission['observation_file'])
        raw = record_path.read_bytes()
        import hashlib
        if hashlib.sha256(raw).hexdigest() != permission['observation_record_sha256']:
            return None
        record = json.loads(raw)
        observed = record['result']; native = observed['native_process']
        epoch = str(native['pid']) + ':' + native['process_created_filetime']
        normalize = lambda value: str(value).replace('\\', '/').replace('"', '').rstrip('/').lower()
        if (record.get('ok') is not True or observed.get('read_only') is not True
                or native.get('read_only') is not True or native.get('native_code_matched') is not True
                or native.get('kind') != 'palworld_client_process_identity'
                or native.get('executable_sha256') != scope['executable_sha256']
                or permission.get('source') != 'runtime_owned_normal_load_observation'
                or permission.get('process_epoch') != epoch
                or permission.get('actual_native_commandline_UserDir_physically_mapped') is not True
                or permission['native_context']['world_id'] != scope['world_directory']
                or permission['native_context']['host_uid'] != scope['pal_uid']
                or normalize(observed['native_user_dir']) != normalize(scope['private_user_dir_windows'])
                or observed['observed_unix'] < session['started_unix']):
            return None
        journal = read_json(owned_path(root, '.palcraft/standalone/journal-lifecycle/' + token + '/scope.json'))
        if journal.get('token') != token or journal.get('native_scope', {}).get('process_epoch') != epoch:
            return None
        exe, userdir = normalize(scope['pal_exe_windows']), normalize(scope['private_user_dir_windows'])
        # This selector exports PID numbers only and is scoped to the exact owned executable path.
        pattern = re.escape(scope['pal_exe_windows'].replace('\\', '/')).replace('/', r'[/\\]')
        found = runner(['/usr/bin/pgrep', '-f', pattern], capture_output=True, text=True, timeout=2)
        expected_birth = int(native['process_created_filetime']) / 10000000 - 11644473600
        matches = []
        for value in found.stdout.split():
            if not value.isdecimal():
                continue
            pid = int(value); birth = identity_reader(pid)
            if not birth or abs(time.mktime(time.strptime(birth, '%a %b %d %H:%M:%S %Y')) - expected_birth) > 2:
                continue
            result = runner(['/bin/ps', '-p', str(pid), '-o', 'args='], capture_output=True, text=True, timeout=2)
            command = normalize(result.stdout.strip())
            if (not command.startswith(exe + ' ') or not any(' -userdir=' + userdir + suffix in command for suffix in (' ', '/ '))):
                continue
            matches.append({'pid': pid, 'identity': birth})
        if len(matches) != 1:
            return None
        return {'version': 1, 'token': token, 'game_pid': matches[0]['pid'], 'game_identity': matches[0]['identity'],
                'helper_pid': client['pid'], 'helper_identity': client['identity'],
                'helper_bundle_id': opened['bundle_identifier'], 'helper_bundle': bundle,
                'native_process_epoch': epoch, 'own_root': str(root), 'game_exe': scope['pal_exe_windows'],
                'private_user_dir': scope['private_user_dir_windows']}
    except (PlayerError, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        return None


def _native_menu_application(pid, expected_executable):
    """Read one owned app's kernel/AppKit lifecycle; no launch or activation calls."""
    import ctypes
    if sys.platform != 'darwin':
        return None
    libproc = ctypes.CDLL('/usr/lib/libproc.dylib')
    libproc.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    libproc.proc_pidpath.restype = ctypes.c_int
    path = ctypes.create_string_buffer(4096)  # PROC_PIDPATHINFO_MAXSIZE
    if libproc.proc_pidpath(pid, path, len(path)) <= 0:
        return None
    kernel_executable = os.fsdecode(path.value)
    if kernel_executable != expected_executable:
        return None
    ctypes.CDLL('/System/Library/Frameworks/AppKit.framework/AppKit')
    objc = ctypes.CDLL('/usr/lib/libobjc.A.dylib')
    objc.objc_getClass.argtypes = [ctypes.c_char_p]
    objc.objc_getClass.restype = ctypes.c_void_p
    objc.sel_registerName.argtypes = [ctypes.c_char_p]
    objc.sel_registerName.restype = ctypes.c_void_p
    sel = lambda name: objc.sel_registerName(name.encode('ascii'))
    address = ctypes.cast(objc.objc_msgSend, ctypes.c_void_p).value
    object_call = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)(address)
    pid_call = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int)(address)
    integer_call = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)(address)
    bool_call = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)(address)
    string_call = ctypes.CFUNCTYPE(ctypes.c_char_p, ctypes.c_void_p, ctypes.c_void_p)(address)
    pool = object_call(object_call(objc.objc_getClass(b'NSAutoreleasePool'), sel('alloc')), sel('init'))
    try:
        # NSRunningApplication dynamic properties refresh at the next main-loop
        # turn. Zero seconds makes one pass; no new timer, reader or worker.
        cf = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
        cf.CFRunLoopRunInMode.argtypes = [ctypes.c_void_p, ctypes.c_double, ctypes.c_bool]
        cf.CFRunLoopRunInMode.restype = ctypes.c_int32
        mode = ctypes.c_void_p.in_dll(cf, 'kCFRunLoopDefaultMode').value
        cf.CFRunLoopRunInMode(mode, 0.0, True)
        app = pid_call(objc.objc_getClass(b'NSRunningApplication'), sel('runningApplicationWithProcessIdentifier:'), pid)
        if not app:
            return None
        def text(obj):
            value = string_call(obj, sel('UTF8String')) if obj else None
            return value.decode('utf-8') if value else None
        def url_path(name):
            url = object_call(app, sel(name))
            return text(object_call(url, sel('path'))) if url else None
        return {'pid': integer_call(app, sel('processIdentifier')),
                'kernel_executable': kernel_executable, 'executable': url_path('executableURL'),
                'bundle': url_path('bundleURL'), 'bundle_identifier': text(object_call(app, sel('bundleIdentifier'))),
                'finished_launching': bool_call(app, sel('isFinishedLaunching')),
                'terminated': bool_call(app, sel('isTerminated'))}
    finally:
        object_call(pool, sel('drain'))


def status(root):
    root = Path(root).absolute()
    state = get_state(root)
    p = validate_profile(state['profile'], root) if state.get('profile') else None
    direct = p is not None and p['connection']['transport'] == 'local'
    session = read_json(root / '.palcraft/session.json', {})
    observing = session.get('launch_mode') == BOOTSTRAP_MODE
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
    bootstrap = {}
    if direct:
        bootstrap = read_json(owned_path(root, DEV + '/bridge/mc-bootstrap-status.json'), {})
        host = bootstrap.get('host_scope') if isinstance(bootstrap.get('host_scope'), dict) else {}
        native = bootstrap.get('native_binding') if isinstance(bootstrap.get('native_binding'), dict) else {}
        view = bootstrap.get('world_view') if isinstance(bootstrap.get('world_view'), dict) else {}
        identity = p['connection']['identity']
        boot = p['connection']['server_session_id']
        bound = (bound and binding.get('identity') == identity and binding.get('server_session_id') == boot
                 and isinstance(binding.get('session_id'), str) and bool(binding['session_id'])
                 and type(binding.get('generation')) is int and binding['generation'] > 0
                 and type(binding.get('expires_at')) in (int, float) and binding['expires_at'] > current)
        live_native = (type(native.get('expires_at')) in (int, float) and native['expires_at'] > current
                       and native.get('v') == 2 and native.get('legacy') is False
                       and isinstance(native.get('mc_epoch'), str) and bool(native['mc_epoch'])
                       and all(native.get(key) == value for key, value in identity.items())
                       and native.get('server_session_id') == boot)
        transport_ready = (bound and bootstrap.get('state') == 'bound'
                           and bootstrap.get('authenticated_host') is True and bootstrap.get('native_mc_verified') is True
                           and fresh(bootstrap, 'updated_unix') and bootstrap.get('identity') == identity
                           and all(host.get(key) == value for key, value in identity.items())
                           and host.get('server_session_id') == boot
                           and host.get('session_id') == binding.get('session_id')
                           and host.get('generation') == binding.get('generation')
                           and live_native and view.get('player') == identity['mc_uuid']
                           and isinstance(view.get('world_session'), str) and bool(view['world_session'])
                           and view.get('waiting_ack') is False)
    local_gate = client.get('host_input_gate', {}).get('allowed') is True and fresh(client, 'unix')
    required = {'client'} if direct else {'client', 'ssh', 'udp'}
    if state.get('profile', {}).get('connection', {}).get('mode') == 'strict-player':
        required.add('proxy')
    if state.get('profile', {}).get('platform') == 'crossover':
        required.add('hud')
    from launcher.journal_lifecycle import enabled
    if p is not None and enabled(p) and not observing:
        required.update(('mc_server', 'mc_guest', 'hud_relay'))
    components_ready = all(process_matches(session.get('components', {}).get(name, {})) for name in required)
    game_ready = not observing and alive and components_ready and session.get('phase') == 'running' and bound and transport_ready and local_gate
    return {'ok': True, 'installed': state.get('installed', False), 'version': state.get('current'),
            'phase': session.get('phase', 'stopped'), 'supervisor_alive': alive,
            'components': {k: {'pid': v.get('pid'), 'alive': process_matches(v)} for k, v in session.get('components', {}).items()},
            'binding': binding, 'udp_transport': udp if not direct else {'mode': 'direct', 'tunnel_started': False},
            'native_mc': bootstrap, 'transport': p['connection']['transport'] if p is not None else None,
            'transport_ready': False if observing else transport_ready, 'game_ready': game_ready,
            'launch_mode': session.get('launch_mode', 'full'), 'mc_actions_authorized': game_ready,
            'pending': BOOTSTRAP_PENDING[:] if observing else [],
            'ready_definition': ('singleplayer bootstrap observation; full readiness and MC actions pending' if observing else
                                'fresh strict binding + real local Pal UID gate + accepted matching native MC bootstrap + living managed session'
                                 if direct else 'fresh strict binding + real local Pal UID gate + responding personal UDP + living managed session'),
            'code': session.get('code'), 'message': session.get('message'), 'servers_started_or_stopped': []}


def _write_control(root, token, mode):
    if not re.fullmatch(r'[a-f0-9]{32}', token):
        fail('SESSION_TOKEN', '会话控制标识损坏，拒绝关闭其他进程。')
    path = owned_path(root, '.palcraft/control/' + token + '.stop')
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp')
    temp.write_text(mode + '\n', encoding='ascii')
    os.replace(temp, path)


def start(root, dry_run=False, timeout=20, boot_singleplayer=False, normal_stop_receipt=None, sync_receipt=None):
    root = Path(root).absolute()
    from launcher.journal_lifecycle import enabled, prepare_cold_boot
    standalone = enabled(get_state(root)['profile'])
    existing = read_json(owned_path(root, '.palcraft/session.json'), {})
    if not boot_singleplayer and existing.get('launch_mode') == BOOTSTRAP_MODE and existing.get('phase') in ('bootstrap', 'promoting'):
        if normal_stop_receipt is not None:
            fail('JOURNAL_SCOPE', '运行中的 promotion 不能归档当前事件卷。')
        return promote(root, dry_run=dry_run, timeout=timeout, sync_receipt=sync_receipt)
    if normal_stop_receipt is not None and not (boot_singleplayer or standalone):
        fail('JOURNAL_SCOPE', '日志停机回执仅用于本机独立单机 cold boot。')
    boot_singleplayer = boot_singleplayer or standalone
    launch_mode = BOOTSTRAP_MODE if boot_singleplayer else 'full'
    journal_maintenance = (prepare_cold_boot(root, dry_run, normal_stop_receipt)
                           if standalone or normal_stop_receipt is not None else None)
    if dry_run:
        result = command_plan(root, '0' * 32, launch_mode)
        if journal_maintenance is not None:
            result['journal_maintenance'] = journal_maintenance
        return result
    with operation_lock(root):
        ensure_no_session(root)
        checks = health(root, check_ports=True, launch_mode=launch_mode)
        if not checks['ok']:
            bad = next(x for x in checks['checks'] if not x['ok'])
            fail(bad['code'], bad['message'], bad['action'])
        token = uuid.uuid4().hex
        state = get_state(root)
        session = {'schema': 1, 'token': token, 'phase': 'starting', 'components': {}, 'started_unix': time.time(),
                   'launch_mode': launch_mode, 'game_ready': False,
                   'pending': BOOTSTRAP_PENDING[:] if boot_singleplayer else []}
        if journal_maintenance is not None:
            session['journal_maintenance'] = journal_maintenance
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
        if session['phase'] in ('running', 'bootstrap'):
            return {'ok': True, 'phase': session['phase'], 'launch_mode': launch_mode, 'game_ready': False,
                    'mc_actions_authorized': False, 'pending': session.get('pending', []),
                    'message': ('单机观察进程已启动；正常加载实际存档后观察真实 Pal UID 和 authority，完整 MC/HUD/AI 尚待启动。'
                                if boot_singleplayer else '个人客户端进程已启动；真实入服/身份/传输状态见 status。'),
                    'servers_started_or_stopped': []}
        if session['phase'] in ('failed', 'stopped'):
            fail(session.get('code', 'CLIENT_START'), session.get('message', '客户端启动失败。'), '运行 diagnostics，按错误提示处理后重试。')
        if process.poll() is not None:
            session.update(phase='failed', code='SUPERVISOR_EXIT', message='启动器后台进程异常退出。')
            atomic_json(root / '.palcraft/session.json', session)
            fail('SUPERVISOR_EXIT', '启动器后台进程异常退出。', '运行 diagnostics。')
        time.sleep(0.15)
    fail('START_PENDING', '启动仍在进行。', '运行 status 查看结果；stop 可以取消本次启动。')


def _promotion_profile(root, state, proposed=None):
    before = validate_profile(state['profile'], root)
    after = validate_profile(before if proposed is None else proposed, root)
    _validate_launch_mode(after, BOOTSTRAP_MODE)
    stable = ('platform', 'windows_root', 'bottle_name', 'bottle_root', 'bottle_mode',
              'crossover_app', 'pal_entry_mode', 'launch_shipping', 'fps', 'mute')
    if any(before.get(key) != after.get(key) for key in stable) or before['local_ports']['mc_ws'] != after['local_ports']['mc_ws']:
        fail('PROMOTE_GAME_CHANGE', '接入完整服务不能改变正在运行的游戏、bottle、路径、帧率或代理端口。')
    old_identity, new_identity = before['connection']['identity'], after['connection']['identity']
    if any(old_identity.get(key) != new_identity.get(key) for key in ('world_id', 'mc_uuid', 'mc_name')):
        fail('PROMOTE_IDENTITY', '接入完整服务必须保留同一世界和 Minecraft 玩家。')
    config = read_json(owned_path(root, DEV + '/bridge/runtime-config.json'), {})
    if config.get('identity') != new_identity:
        fail('PROMOTE_SCOPE', 'profile 身份尚未与本进程 runtime-config 对齐。',
             '先由正常登记流程发布当前身份和玩家凭据，再接入完整服务；服务仍验证真实 boot 和签名。')
    return after


def promote(root, profile=None, dry_run=False, timeout=20, sync_receipt=None):
    root = Path(root).absolute()
    with operation_lock(root):
        state = get_state(root)
        session = read_json(owned_path(root, '.palcraft/session.json'), {})
        if session.get('launch_mode') == 'full' and session.get('phase') == 'running':
            return {'ok': True, 'phase': 'running', 'already_full': True, 'game_ready': status(root)['game_ready']}
        if (session.get('launch_mode') != BOOTSTRAP_MODE or session.get('phase') not in ('bootstrap', 'promoting') or
                not process_matches(session.get('supervisor', {})) or not process_matches(session.get('components', {}).get('client', {}))):
            fail('PROMOTE_SESSION', '没有可接入完整服务的同一活动单机 bootstrap 会话。')
        candidate = _promotion_profile(root, state, profile)
        plan = command_plan(root, session['token'], 'full')
        result = {'ok': True, 'dry_run': dry_run, 'launch_mode': 'full', 'same_client_pid': session['components']['client']['pid'],
                  'new_components': [name for name in plan['commands'] if name != 'client'],
                  'new_host_or_game': False, 'game_ready': False, 'servers_started_or_stopped': []}
        from launcher.journal_lifecycle import enabled
        if enabled(candidate):
            result['owned_standalone_roles'] = ['mc_server', 'mc_guest', 'hud_relay']
        if dry_run:
            return result
        request_path = owned_path(root, '.palcraft/control/' + session['token'] + '.promote.json')
        previous = read_json(request_path, {})
        if previous:
            if previous.get('token') != session['token'] or previous.get('profile') != candidate:
                fail('PROMOTE_PENDING', '另一个完整服务接入请求仍在处理，未覆盖它。')
            request_id = previous['request_id']
        else:
            request_id = uuid.uuid4().hex
            request = {'token': session['token'], 'request_id': request_id, 'profile': candidate}
            if sync_receipt is not None:
                request['sync_receipt'] = str(Path(sync_receipt).absolute())
            atomic_json(request_path, request)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        current = read_json(root / '.palcraft/session.json', {})
        if current.get('token') != session['token']:
            fail('SESSION_REPLACED', '单机会话已改变，不会接管新游戏。')
        if current.get('promotion_request_id') == request_id:
            if current.get('promotion_state') == 'complete':
                return {**result, 'phase': 'running', 'servers_started_or_stopped': result.get('owned_standalone_roles', []),
                        'message': '完整连接组件已接入同一游戏；真实身份与 native MC ACK 就绪状态见 status。'}
            if current.get('promotion_state') == 'failed':
                fail(current.get('code', 'PROMOTE_FAILED'), current.get('message', '完整服务接入失败。'),
                     '同一游戏保持 bootstrap；处理真实前置后重试，或保存并正常退出。')
        if current.get('phase') in ('stopped', 'failed', 'closing'):
            fail('PROMOTE_SESSION', '同一游戏正在退出或已退出，未启动替代游戏。')
        time.sleep(.15)
    fail('PROMOTE_PENDING', '完整服务接入仍在处理。', '运行 status；保留当前单机进程，不重复启动 Host/Game。')


def stop(root, force=False, dry_run=False, timeout=45):
    root = Path(root).absolute()
    marker(root)
    session = read_json(root / '.palcraft/session.json', {})
    if session.get('phase') in (None, 'stopped', 'failed'):
        return {'ok': True, 'phase': session.get('phase', 'stopped'), 'message': '个人客户端已关闭。',
                'journal_lifecycle': session.get('journal_lifecycle'), 'servers_started_or_stopped': []}
    if dry_run:
        from launcher.journal_lifecycle import enabled
        order = ['client', 'hud', 'proxy', 'udp', 'ssh']
        if enabled(get_state(root)['profile']) and not force:
            order = ['original_save_request_and_file_witness', 'native_Title_and_exit', 'hud', 'proxy',
                     'mc_guest', 'hud_relay', 'mc_server_console_stop', 'Saved_WAL_and_stream_off_witness']
        return {'ok': True, 'dry_run': True, 'force': force, 'stop_order': order, 'servers_started_or_stopped': []}
    # No signal is sent to a PID read from a file. The native host only observes its own token.
    from launcher.journal_lifecycle import LIFECYCLE, enabled, request_normal_stop
    lifecycle = owned_path(root, LIFECYCLE + '/' + session['token'] + '/scope.json')
    if not force and enabled(get_state(root)['profile']) and lifecycle.is_file():
        request_normal_stop(root, session)
    else:
        _write_control(root, session['token'], 'force' if force else 'close')
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        now = read_json(root / '.palcraft/session.json')
        if now['token'] != session['token']:
            fail('SESSION_REPLACED', '会话已更换，不会关闭新会话。')
        if now['phase'] in ('stopped', 'failed'):
            return {'ok': True, 'phase': now['phase'], 'graceful': not force,
                    'journal_lifecycle': now.get('journal_lifecycle'),
                    'servers_started_or_stopped': [v['role'] for v in (now.get('journal_lifecycle') or {}).get('actor_exits', {}).values()
                                                   if v.get('role') in ('mc_server', 'mc_guest', 'hud_relay')]}
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
            # The relay's existing clock handshake works before any game frame.
            # Validate its exact nonce response instead of waiting for video.
            nonce = os.urandom(8)
            sock.sendall(b'TIME\n' + nonce)
            data = bytearray()
            while len(data) < 32:
                part = sock.recv(32 - len(data))
                if not part:
                    fail('HUD_UNAVAILABLE', '个人 HUD 服务连接已关闭。')
                data.extend(part)
            magic, version, size, echoed, received_ns, sent_ns = struct.unpack('!4sHHQQQ', data)
            if (magic != b'HCLK' or version != 1 or size != 32 or
                    echoed != int.from_bytes(nonce, 'big') or received_ns <= 0 or sent_ns < received_ns):
                fail('HUD_UNAVAILABLE', '个人 HUD 服务的时钟握手不匹配。')
        elif kind == 'mc_server':
            # TCP reachability only; the MC guest owns login/authentication.
            pass
    return True


class Session:
    """Popen handles belong to this instance; no unscoped pkill/Stop-Process."""
    def __init__(self, root, token, commands=None, probe=None, poll_seconds=0.15):
        self.root, self.token = Path(root).absolute(), token
        self.state = get_state(root)
        self.probe = probe or _connect_probe
        self.poll_seconds = poll_seconds
        self.children, self.outputs = {}, []
        self.session = read_json(self.root / '.palcraft/session.json')
        if self.session.get('token') != token:
            fail('SESSION_TOKEN', '后台会话标识不一致。')
        self.launch_mode = self.session.get('launch_mode', 'full')
        self.observing = _validate_launch_mode(validate_profile(self.state['profile'], self.root), self.launch_mode)
        self.commands = commands if commands is not None else command_plan(root, token, self.launch_mode)['commands']
        if self.observing and set(self.commands) != {'client'}:
            fail('BOOTSTRAP_COMPONENTS', '单机观察阶段仅允许本安装的 Host/Game。')
        self.session['supervisor'] = {'pid': os.getpid(), 'identity': process_identity(os.getpid())}
        self.control = owned_path(root, '.palcraft/control')
        self.control.mkdir(exist_ok=True)
        self.heartbeat = self.control / (token + '.heartbeat')
        self.failure = None
        self.closing = False
        self.native_menu_host_seen = False
        self.native_menu_open_attempted = self.session.get('native_menu_open', {}).get('attempted') is True
        from launcher.journal_lifecycle import NormalLifecycle, enabled
        self.journal = NormalLifecycle(self) if enabled(self.state['profile']) else None
        from installer.performance import OwnedPerformance
        self.performance = OwnedPerformance(self)

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
        p = validate_profile(self.state['profile'], self.root)
        env['PALCRAFT_WINDOWS_ROOT'] = p['windows_root']
        if p.get('pal_entry_mode') == 'singleplayer':
            env['PALCRAFT_PAL_EXE'] = windows_path(p['windows_root'], 'PalCraft-Client/Pal/Binaries/Win64/Palworld-Win64-Shipping.exe')
            env['PALCRAFT_RPC_ROOT'] = windows_path(p['windows_root'], 'BridgeLab/rpc')
            env['PALCRAFT_EXCHANGE_ROOT'] = windows_path(p['windows_root'], 'PalCraft-Dev/bridge/exchange')
        env[HOST_PROXY_PORT_ENV] = str(p['local_ports']['mc_ws'])
        env['PALCRAFT_HUD_PORT'] = str(p['service_ports']['hud'])
        env['PALCRAFT_BRIDGE_DIR'] = (str(self.root / DEV / 'bridge')
            if name == 'hud' and self.state['profile']['platform'] == 'crossover'
            else windows_path(env['PALCRAFT_WINDOWS_ROOT'], DEV + '/bridge'))
        env['PALCRAFT_FRAME_NAME'] = self.state['profile']['connection'].get('frame_mapping', 'Local\\MCPassthroughFrame')
        env['PALCRAFT_TITLEBAR_HEIGHT'] = str(self.state['profile'].get('titlebar_height', 28))
        if name == 'hud' and p.get('pal_entry_mode') == 'singleplayer' and p['platform'] == 'crossover':
            env['PALCRAFT_MAC_FOREGROUND_GROUP_REQUIRED'] = '1'
            group = _mac_game_foreground_group(self.root, self.token)
            env['PALCRAFT_MAC_FOREGROUND_GROUP'] = json.dumps(group, separators=(',', ':')) if group else ''
        if name == 'hud' and self.journal is not None:
            from installer.performance import role_environment
            env = role_environment(self.root, self.token, name, env)
            env['PALCRAFT_HUD_FPS'] = str(p.get('performance', {}).get('hud_fps', 60))
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
        if self.journal is not None:
            self.journal.register(name, self.session['components'][name])
        self.save('closing' if self.closing else 'starting')
        return process

    def should_close(self):
        normal_request = self.root / '.palcraft/standalone/journal-lifecycle' / self.token / 'stop-request.json'
        return (self.control / (self.token + '.stop')).exists() or (self.journal is not None and normal_request.exists())

    def native_menu_open_tick(self):
        """One standard open event to this Session's already launched native Helper."""
        if (sys.platform != 'darwin' or self.state['profile']['platform'] != 'crossover'
                or self.state['manifest'].get('requirements', {}).get('crossover_native_menu') != 'windows-menu-helper-v1'
                or self.native_menu_open_attempted or self.closing or self.should_close()):
            return
        host = owned_path(self.root, '.palcraft/control/' + self.token + '.host.json')
        self.native_menu_host_seen |= host.exists() or bool(self.journal and self.journal.scope.get('native_scope'))
        if self.native_menu_host_seen:
            return
        client = self.children.get('client')
        if client is None or client.poll() is not None:
            return
        current = read_json(self.root / '.palcraft/session.json')
        record = self.session.get('components', {}).get('client', {})
        if (current.get('token') != self.token or current.get('phase') not in ('starting', 'bootstrap', 'running')
                or current.get('components', {}).get('client') != record
                or record.get('pid') != client.pid or not process_matches(record)):
            return
        command = self.commands['client']
        prefix = [sys.executable, str(owned_path(self.root, TOOLS + '/launcher/crossover_menu_helper.py')),
                  '--root', str(self.root), 'run', '--']
        if command[:len(prefix)] != prefix:
            return
        from launcher.crossover_menu_helper import MenuError, plan
        try:
            hosts = [entry for entry in self.state['manifest']['files'] if entry.get('role') == 'client_host']
            if len(hosts) != 1:
                return
            spec = plan(self.root, validate_profile(self.state['profile'], self.root),
                        command[len(prefix):], hosts[0]['target'])
            bundle = owned_path(self.root, '.palcraft/native-menu/PalCraft Game.app')
            executable = owned_path(self.root, '.palcraft/native-menu/PalCraft Game.app/Contents/MacOS/Menu Helper')
            app = _native_menu_application(client.pid, str(executable))
        except (MenuError, OSError, ValueError, AttributeError):
            return
        if (not app or app.get('pid') != client.pid or app.get('kernel_executable') != str(executable)
                or app.get('executable') != str(executable) or app.get('bundle') != str(bundle)
                or app.get('bundle_identifier') != spec['bundle_id']
                or app.get('finished_launching') is not True or app.get('terminated') is not False
                or self.should_close() or host.exists() or client.poll() is not None or not process_matches(record)):
            return
        self.native_menu_open_attempted = True  # Unknown outcomes must never cause another open.
        receipt = {'schema': 1, 'attempted': True, 'token': self.token, 'client': dict(record),
                   'bundle': str(bundle), 'bundle_identifier': spec['bundle_id'],
                   'finished_launching_observed': True, 'requested_unix': time.time(),
                   'command': ['/usr/bin/open', '-a', str(bundle)], 'state': 'requested',
                   'game_ready_claimed': False, 'client_exit_code_before': client.poll()}
        self.session['native_menu_open'] = receipt
        self.save(self.session['phase'])
        try:
            result = subprocess.run(receipt['command'], stdin=subprocess.DEVNULL, capture_output=True,
                                    text=True, timeout=5)
            receipt.update(state='returned', returncode=result.returncode,
                           stdout=result.stdout[-2500:], stderr=result.stderr[-2500:])
        except (OSError, subprocess.SubprocessError) as error:
            receipt.update(state='outcome_unknown', error=str(error))
        receipt.update(observed_unix=time.time(), client_exit_code_after=client.poll(),
                       same_owned_client_identity_after=process_matches(record))
        self.save(self.session['phase'])

    def journal_tick(self):
        if self.journal is not None:
            try:
                self.journal.tick()
                self.session.pop('journal_error', None)
            except (PlayerError, OSError, KeyError, ValueError) as error:
                self.session['journal_error'] = {'code': getattr(error, 'code', 'JOURNAL_OBSERVATION_PENDING'),
                                                  'message': str(error)}

    def promote_full(self, request, startup_timeout=15):
        previous_commands = self.commands
        added = []
        output_count = len(self.outputs)
        try:
            if request.get('token') != self.token or not re.fullmatch(r'[a-f0-9]{32}', str(request.get('request_id', ''))):
                fail('SESSION_TOKEN', '完整服务接入控制标识不一致。')
            self.save('promoting', promotion_request_id=request['request_id'], promotion_state='pending', game_ready=False)
            state = get_state(self.root)
            profile = _promotion_profile(self.root, state, request.get('profile'))
            checks = health(self.root, check_ports=True, profile=profile)
            if not checks['ok']:
                bad = next(check for check in checks['checks'] if not check['ok'])
                fail(bad['code'], bad['message'], bad['action'])
            deadline = time.monotonic() + startup_timeout
            services = ('mc_ws', 'mc_server') if profile['platform'] == 'windows' else ('mc_ws', 'hud', 'mc_server')
            if self.journal is not None:
                receipt = request.get('sync_receipt') or str(self.root / '.palcraft/standalone/sync-receipt.json')
                self.journal.start_roles(receipt, profile)
                deadline = time.monotonic() + startup_timeout
            for name in services:
                while True:
                    self.beat()
                    if self.should_close() or self.children['client'].poll() is not None:
                        fail('PROMOTE_CANCELLED', '同一游戏正在退出，完整服务接入已取消。')
                    try:
                        self.probe(profile['service_ports'][name], name, timeout=.5)
                        break
                    except (OSError, PlayerError):
                        if time.monotonic() >= deadline:
                            fail('REMOTE_UNAVAILABLE', '本机完整服务未就绪：' + name)
                        time.sleep(self.poll_seconds)
            # Normal enrollment already published bridge scope and the private credential.
            # Only update the public launcher profile; preserve every runtime-config field.
            state['profile'] = profile
            atomic_json(self.root / '.palcraft/state.json', state)
            self.state = state
            self.commands = command_plan(self.root, self.token, 'full')['commands']
            if self.commands['client'] != previous_commands['client']:
                fail('PROMOTE_GAME_CHANGE', '完整服务计划试图改变已有 Host/Game，已拒绝。')
            for name in ('proxy', 'hud'):
                if name in self.commands:
                    added.append(name)
                    self.spawn(name)
            for _ in range(6):
                self.beat()
                time.sleep(self.poll_seconds)
                if self.should_close() or any(child.poll() is not None for child in self.children.values()):
                    fail('PROMOTE_COMPONENT', '接入完整服务时组件退出或收到正常关闭请求。')
            self.observing, self.launch_mode = False, 'full'
            self.save('running', launch_mode='full', promotion_state='complete', code=None, message=None,
                      game_ready=False, pending=[])
            return True
        except (PlayerError, OSError) as error:
            for name in added:
                child = self.children.pop(name, None)
                self.session['components'].pop(name, None)
                if child is None:
                    continue
                if child.poll() is None:
                    child.terminate()
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        child.kill(); child.wait(timeout=5)
                if self.journal is not None:
                    self.journal.record_exit(name, child, 'promotion_unwind')
            if self.journal is not None:
                self.journal.stop_roles()
                self.journal.roles.clear()
            for output in self.outputs[output_count:]:
                output.close()
            del self.outputs[output_count:]
            self.commands = previous_commands
            self.save('bootstrap', launch_mode=BOOTSTRAP_MODE, promotion_state='failed', game_ready=False,
                      pending=BOOTSTRAP_PENDING[:], code=getattr(error, 'code', 'PROMOTE_IO'),
                      message=getattr(error, 'message', str(error)))
            return False

    def run(self, startup_timeout=15):
        (self.root / '.palcraft/logs').mkdir(exist_ok=True)
        self.save('starting')
        self.beat()
        try:
            p = validate_profile(self.state['profile'], self.root)
            if 'ssh' in self.commands:
                self.spawn('ssh')
            deadline = time.monotonic() + startup_timeout
            services = () if self.observing else (('mc_ws', 'mc_server') if p['connection']['transport'] == 'local' and p['platform'] == 'windows' else ('mc_ws', 'hud', 'mc_server'))
            for name in services:
                while True:
                    self.beat()
                    if self.should_close():
                        return self.finish('stopped', 'START_CANCELLED', '启动已取消。')
                    if 'ssh' in self.children and self.children['ssh'].poll() is not None:
                        fail('SSH_CONNECT', 'SSH 转发退出。', '检查登录密钥、已知主机记录及个人端口租约；不要覆盖 known_hosts。')
                    try:
                        self.probe(p['service_ports'][name], name, timeout=0.5)
                        break
                    except (OSError, PlayerError):
                        if time.monotonic() >= deadline:
                            fail('REMOTE_UNAVAILABLE', '个人服务未就绪：' + name, '联系服务器管理员启动你的个人 guest/HUD；此工具不会重启服务器。')
                        time.sleep(self.poll_seconds)
            if 'proxy' in self.commands:
                self.spawn('proxy')
            if 'udp' in self.commands:
                self.spawn('udp')
            if 'hud' in self.commands:
                self.spawn('hud')
            self.spawn('client')
            for _ in range(6):
                self.beat()
                time.sleep(self.poll_seconds)
                if any(child.poll() is not None for child in self.children.values()):
                    fail('COMPONENT_START', '某个个人组件在启动时退出。', '运行 diagnostics 查看组件日志。')
            self.save('bootstrap' if self.observing else 'running', game_ready=False,
                      pending=BOOTSTRAP_PENDING[:] if self.observing else [])
            while True:
                self.beat()
                self.journal_tick()
                if self.should_close():
                    self.closing = True
                    self.save('closing', message='正在等待个人游戏保存并退出。')
                self.native_menu_open_tick()
                client = self.children['client']
                if client.poll() is not None:
                    code = client.returncode
                    return self.finish('stopped' if code == 0 else 'failed', 'CLIENT_EXIT' if code else 'OK',
                                       '个人客户端已退出。' if code == 0 else '客户端异常退出，已关闭本次连接组件。')
                request_path = self.control / (self.token + '.promote.json')
                if self.observing and not self.closing and request_path.is_file():
                    self.promote_full(read_json(request_path))
                    request_path.unlink(missing_ok=True)
                dead = [name for name, proc in self.children.items() if name != 'client' and proc.poll() is not None]
                if self.journal is not None:
                    dead += [name for name, proc in self.journal.roles.items() if proc.poll() is not None]
                if dead:
                    self.failure = ('CONNECTION_LOST', '连接组件异常退出：' + ', '.join(dead))
                    if self.journal is not None:
                        from launcher.journal_lifecycle import request_normal_stop
                        request_normal_stop(self.root, self.session)
                    else:
                        _write_control(self.root, self.token, 'close')
                    self.closing = True
                    self.save('closing', code=self.failure[0], message=self.failure[1] + '；等待游戏正常退出。')
                try:
                    self.performance.tick()
                except (PlayerError, OSError, KeyError, ValueError) as error:
                    self.session['performance_error'] = {'code': getattr(error, 'code', 'PERFORMANCE_IO'),
                                                         'message': str(error)}
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
        if self.journal is not None:
            self.journal.stop_roles()
            try:
                journal_result = self.journal.finish(phase)
            except (PlayerError, OSError, ValueError) as error:
                journal_result = {'ok': False, 'code': getattr(error, 'code', 'JOURNAL_WITNESS_PENDING'),
                                  'message': str(error), 'normal_stop_receipt_created': False}
            self.session['journal_lifecycle'] = journal_result
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
    child_record = {'pid': child.pid, 'identity': process_identity(child.pid)}
    if component == 'hud' and os.environ.get('PALCRAFT_PERFORMANCE_TOKEN') == token:
        atomic_json(owned_path(root, '.palcraft/control/' + token + '.hud-child.json'),
                    {'token': token, 'root_id': marker(root)['id'], 'wrapper_pid': os.getpid(),
                     'child': child_record, 'created_by_this_worker': True})
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
        atomic_json(owned_path(root, '.palcraft/control/' + token + '.' + component + '.' + str(os.getpid()) + '-exit.json'),
                    {'token': token, 'component': component, 'child': child_record,
                     'actual_wait_completed': True, 'exit_code': child.wait()})
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
