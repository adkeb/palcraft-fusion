"""Transactional installation. No game/server processes or network calls here."""
import contextlib
import hashlib
import json
import os
import re
import shutil
import stat
import sys
import time
import uuid
import zipfile
from pathlib import Path, PurePosixPath

from installer.paths import (PATH_CONTRACT, windows_root, validate_release_paths)


def require_release_paths(manifest, profile):
    try:
        validate_release_paths(manifest, profile)
    except ValueError as exc:
        fail('PATH_CONTRACT', str(exc), '请取得支持 windows-root-v1 的完整发布包。')
    validate_utf8_pair(manifest)


SCHEMA = 1
WINDOWS_ROOT = 'D:/PalworldServer-LAN'
CLIENT_JOURNAL = 'BridgeLab/rpc'
CLIENT = 'PalCraft-Client'
DEV = 'PalCraft-Dev'
USER = 'PalCraft-Client-User'
TOOLS = DEV + '/player-tools'
BIN = CLIENT + '/Pal/Binaries/Win64/'
UTF8_IAT_PROVIDER = 'ue4ss-scoped-iat-v1'
UTF8_IAT_PAIR = {
    'ue4ss': (BIN + 'ue4ss/UE4SS.dll', '0bb2b3fc6664257bf264ab5d21311d2c333407720652e5c335aac6e0e888f5e4', 20080128),
    'ue4ss_utf8_shim': (BIN + 'PalCraftUE4SSUtf8.dll', '18f2a593dba7b34845c17c8e65b1a593eca91aa1b7235ebfaae7bdbf9eb2593a', 9216),
}
LOCAL_PORTS = {'udp_tcp': 18321, 'mc_ws': 25599, 'mc_server': 25567, 'hud': 25603}
MAX_PAYLOAD = 1024 * 1024 * 1024
SECRET_KEYS = {'holder_private', 'host_secret', 'private', 'private_key', 'password', 'token',
               'authorization', 'access_token', 'refresh_token', 'steam_ticket'}


def contains_secret(value):
    if isinstance(value, dict):
        return any(str(k).lower() in SECRET_KEYS or contains_secret(v) for k, v in value.items())
    if isinstance(value, list):
        return any(contains_secret(v) for v in value)
    return False


class PlayerError(Exception):
    def __init__(self, code, message, action=''):
        super().__init__(message)
        self.code, self.message, self.action = code, message, action

    def as_dict(self):
        return {'ok': False, 'code': self.code, 'message': self.message, 'action': self.action}


def fail(code, message, action=''):
    raise PlayerError(code, message, action)


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text(encoding='utf-8'))
    except FileNotFoundError:
        if default is not None:
            return default
        fail('FILE_MISSING', '找不到配置文件：' + str(path), '请重新安装或运行配置向导。')
    except (ValueError, UnicodeError):
        fail('JSON_INVALID', '配置文件格式损坏：' + str(path), '保留原文件，从上一版恢复配置。')


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    data = json.dumps(value, ensure_ascii=False, indent=2) + '\n'
    with temp.open('w', encoding='utf-8') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, path)


def digest(path):
    sha = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            sha.update(block)
    return sha.hexdigest()


def safe_rel(value):
    if not isinstance(value, str) or '\\' in value or ':' in value or '\x00' in value:
        fail('PATH_INVALID', '安装包包含不合法路径。')
    parts = PurePosixPath(value).parts
    if not parts or value != '/'.join(parts) or value.startswith('/') or any(p in ('.', '..') for p in parts):
        fail('PATH_INVALID', '安装包路径越过安装目录。')
    if any(p.rstrip(' .') != p or p.split('.')[0].upper() in
           {'CON', 'PRN', 'AUX', 'NUL', *('COM' + str(i) for i in range(1, 10)),
            *('LPT' + str(i) for i in range(1, 10))} for p in parts):
        fail('PATH_INVALID', '安装包包含 Windows 不支持的文件名。')
    return value


def target_allowed(target):
    safe_rel(target)
    lower = target.lower()
    forbidden = ('/saved/', '/savegames/', '/steam/', '/steamapps/', '/userdata/',
                 '/config/', 'loginusers.vdf', 'ssfn', '.sav', '.ndjson', '.log', '.pdb')
    if any(x in lower for x in forbidden):
        return False
    if target.startswith(DEV + '/minecraft-mods/'):
        return bool(re.fullmatch(re.escape(DEV) + r'/minecraft-mods/passthrough[-A-Za-z0-9_.]*\.jar', target))
    if target.startswith(DEV + '/bridge/'):
        relative = target[len(DEV + '/bridge/'):]
        folders = ('entity-assets-v3/', 'material-pixels-v1/')
        if relative.startswith(folders) or re.match(r'models-v4-[a-f0-9]+/', relative):
            return Path(relative).suffix.lower() in {'.json', '.png', '.rgba', '.sha256'}
        if relative in {'material-evidence-v1/static-three-cleanup.json', 'material-evidence-v1/static-three-properties.json',
                        'material-evidence-v1/static-three-sample.png'}:
            return True
        return relative in {'model-assets.json', 'native-visual-settings.json', 'material-runtime-v1.json'}
    if target.startswith(TOOLS + '/'):
        if target.startswith(TOOLS + '/standalone/') and target.endswith('.lua'):
            return True
        return Path(target).suffix.lower() in {'.py', '.cpp', '.hpp', '.swift', '.exe', '.command', '.cmd', '.txt', '.md', '.java', '.patch', '.json'} or bool(re.fullmatch(re.escape(TOOLS) + r'/bin/hud-overlay[-A-Za-z0-9_.]*', target))
    if target.startswith(DEV + '/mcp/'):
        return Path(target).suffix.lower() in {'.py', '.json', '.txt', '.md'}
    if target.startswith('BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/'):
        return Path(target).suffix.lower() in {'.lua', '.json', '.dll', '.txt', '.hpp'}
    if not target.startswith(BIN):
        return False
    relative = target[len(BIN):]
    if '/' not in relative:
        return relative.lower().endswith(('.dll', '.addon64', '.ini', '.fx', '.fxh'))
    if relative.startswith('ue4ss/'):
        return Path(relative).suffix.lower() in {'.dll', '.lua', '.ini', '.txt', '.json', '.hpp'} or relative.endswith('/enabled.txt')
    return relative.startswith('reshade-shaders/') and Path(relative).suffix.lower() in {'.fx', '.fxh', '.png'}


def validate_utf8_pair(manifest):
    """This provider's Core and early dependency always share one release transaction."""
    requirements, files = manifest.get('requirements', {}), manifest.get('files', [])
    uses_iat = requirements.get('lua_path_provider') == UTF8_IAT_PROVIDER or any(
        f.get('role') == 'ue4ss_utf8_shim' or f.get('target') == UTF8_IAT_PAIR['ue4ss_utf8_shim'][0] or
        f.get('sha256') == UTF8_IAT_PAIR['ue4ss'][1] for f in files)
    if not uses_iat:
        return
    if (requirements.get('lua_path_provider') != UTF8_IAT_PROVIDER or
            type(requirements.get('ue4ss_utf8_abi')) is not int or requirements['ue4ss_utf8_abi'] != 1 or
            requirements.get('path_contract') != PATH_CONTRACT or
            requirements.get('lua_path_encoding') != 'utf-8-win32-v1'):
        fail('BUNDLE_UTF8_PAIR', 'UTF-8 Core/shim 发布必须声明同批路径 provider 和 ABI 1。')
    for role, (target, expected, size) in UTF8_IAT_PAIR.items():
        entries = [f for f in files if f.get('role') == role]
        if len(entries) != 1 or (entries[0].get('target'), entries[0].get('sha256'), entries[0].get('bytes')) != (target, expected, size):
            fail('BUNDLE_UTF8_PAIR', 'UTF-8 Core/shim 必须同一批准版本成对安装，文件缺失或路径、摘要不匹配。')


class Bundle:
    def __init__(self, filename):
        self.path = Path(filename).resolve()
        try:
            with zipfile.ZipFile(self.path) as archive:
                infos = archive.infolist()
                names = [i.filename for i in infos]
                if len(names) > 10000 or len(names) != len({n.casefold() for n in names}):
                    fail('BUNDLE_INVALID', '安装包有重复文件或文件数异常。')
                if sum(i.file_size for i in infos) > MAX_PAYLOAD:
                    fail('BUNDLE_TOO_LARGE', '安装包超过 1 GiB 上限。')
                for item in infos:
                    safe_rel(item.filename)
                    if item.is_dir() or stat.S_ISLNK(item.external_attr >> 16) or item.flag_bits & 1:
                        fail('BUNDLE_INVALID', '安装包包含目录、链接或加密条目。')
                if 'manifest.json' not in names or archive.getinfo('manifest.json').file_size > 4 * 1024 * 1024:
                    fail('BUNDLE_INVALID', '安装包缺少有效 manifest.json。')
                self.manifest = json.loads(archive.read('manifest.json').decode('utf-8'))
                if not isinstance(self.manifest, dict):
                    fail('BUNDLE_INVALID', '安装包 manifest 必须是对象。')
                self._validate_manifest()
                expected = {'manifest.json'} | {'payload/' + f['target'] for f in self.manifest['files']}
                if set(names) != expected:
                    fail('BUNDLE_INVALID', '安装包含有清单以外的文件。')
                for entry in self.manifest['files']:
                    data = archive.read('payload/' + entry['target'])
                    if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
                        fail('BUNDLE_HASH', '文件校验失败：' + entry['target'], '重新取得发布包，不要强行安装。')
                    if entry['target'].lower().endswith('.json') and contains_secret(json.loads(data)):
                        fail('BUNDLE_PRIVATE_DATA', '发布包不能包含个人凭据或私钥。')
                    if entry['target'].lower().endswith('.jar'):
                        import io
                        with zipfile.ZipFile(io.BytesIO(data)) as jar:
                            if 'fabric.mod.json' not in jar.namelist() or any(n.startswith(('net/minecraft/', 'assets/minecraft/')) for n in jar.namelist()):
                                fail('BUNDLE_COPYRIGHT', '玩家包仅接受独立 Fabric mod，不能包含 Minecraft 游戏本体或资源。')
        except (zipfile.BadZipFile, KeyError, ValueError, TypeError, UnicodeError) as exc:
            fail('BUNDLE_INVALID', '安装包格式损坏：' + str(exc))
        self.sha256 = digest(self.path)

    def _validate_manifest(self):
        m = self.manifest
        if m.get('schema') != SCHEMA or m.get('kind') != 'palcraft-player-release':
            fail('BUNDLE_SCHEMA', '不支持此安装包格式。')
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,63}', m.get('version', '')):
            fail('BUNDLE_VERSION', '安装包版本号不合法。')
        if m.get('platform') not in ('crossover', 'windows', 'both'):
            fail('BUNDLE_PLATFORM', '安装包没有明确支持的平台。')
        requirements = m.get('requirements', {})
        hashes = requirements.get('palworld_shipping_sha256', [])
        if not hashes or any(not re.fullmatch(r'[a-f0-9]{64}', x) for x in hashes):
            fail('BUNDLE_COMPATIBILITY', '发布包必须列出已验证的帕鲁 Shipping.exe 校验值。')
        files = m.get('files')
        if not isinstance(files, list) or not files:
            fail('BUNDLE_INVALID', '安装包没有文件清单。')
        seen = set()
        for entry in files:
            target = entry['target']
            if not target_allowed(target) or target.casefold() in seen:
                fail('BUNDLE_PATH', '安装包目的路径不受支持：' + target)
            seen.add(target.casefold())
            if not re.fullmatch(r'[a-f0-9]{64}', entry['sha256']) or type(entry['bytes']) is not int or entry['bytes'] < 0:
                fail('BUNDLE_INVALID', '安装包校验字段不合法。')
        roles = {f.get('role') for f in files}
        required = {'client_main', 'ue4ss', 'proxy_dll', 'native_render', 'native_mesh', 'native_model',
                    'json_lua', 'collisions_lua', 'models_lua', 'client_host', 'model_processor', 'ue4ss_settings'}
        if requirements.get('assets_mode') == 'bundled-models-v4':
            required.remove('model_processor')
        if requirements.get('path_contract') == PATH_CONTRACT:
            if requirements.get('lua_path_encoding') != 'utf-8-win32-v1':
                fail('BUNDLE_PATH_ENCODING', '自选目录发布包必须包含支持 UTF-8 文件路径的 Lua 运行时。')
            required.add('runtime_paths')
        validate_utf8_pair(m)
        if requirements.get('session_mode') == 'strict-player':
            required.add('session_client')
        if m['platform'] in ('crossover', 'both'):
            required.add('mac_hud')
        if not required.issubset(roles):
            fail('BUNDLE_INCOMPLETE', '安装包缺少组件：' + ', '.join(sorted(required - roles)))
        if not m.get('licenses') or not m.get('source_revision'):
            fail('BUNDLE_PROVENANCE', '发布包必须附来源版本和依赖许可清单。')

    def extract(self, destination):
        destination = Path(destination)
        with zipfile.ZipFile(self.path) as archive:
            for entry in self.manifest['files']:
                target = destination / entry['target']
                target.parent.mkdir(parents=True, exist_ok=True)
                with target.open('wb') as stream:
                    stream.write(archive.read('payload/' + entry['target']))
                if entry.get('executable'):
                    target.chmod(0o755)


def owned_path(root, relative):
    safe_rel(relative)
    root = Path(root).absolute()
    current = root
    if root.is_symlink():
        fail('DIRECTORY_LINK', '安装目录不能是符号链接。')
    for part in PurePosixPath(relative).parts:
        current = current / part
        if current.is_symlink():
            fail('DIRECTORY_LINK', '安装目录内有链接，已停止写入：' + str(current))
    if not current.resolve().is_relative_to(root.resolve()):
        fail('DIRECTORY_ESCAPE', '文件越过安装目录。')
    return current


def validate_root(root, platform):
    root = Path(root).absolute()
    if root == Path(root.anchor) or root == Path.home():
        fail('DIRECTORY_INVALID', '不能把系统目录或个人主目录用作安装目录。')
    for parent in [root, *root.parents]:
        if parent.is_symlink():
            fail('DIRECTORY_LINK', '安装目录的父路径不能是符号链接。')
    return root


def marker(root, required=True):
    path = owned_path(root, '.palcraft/owner.json')
    value = read_json(path, {})
    if value.get('kind') != 'palcraft-player-owned-root' or value.get('root') != str(Path(root).absolute()):
        if required:
            fail('UNMANAGED_DIRECTORY', '该目录不属于玩家安装器，未作任何修改。', '请使用新的独立安装目录，不要接管开发目录或其他游戏安装。')
        return None
    return value


def get_state(root):
    marker(root)
    return read_json(owned_path(root, '.palcraft/state.json'), {'schema': SCHEMA, 'current': None, 'history': [], 'files': {}, 'base_files': {}})


def ensure_no_session(root):
    session = read_json(owned_path(root, '.palcraft/session.json'), {})
    if session.get('phase') not in (None, 'stopped', 'failed'):
        fail('CLIENT_BUSY', '客户端会话尚未关闭，不能安装、更新或卸载。', '先运行 stop；若启动器异常退出，运行 status/recover-session。')


@contextlib.contextmanager
def operation_lock(root):
    path = owned_path(root, '.palcraft/operation.lock')
    path.parent.mkdir(parents=True, exist_ok=True)
    stream = path.open('a+b')
    try:
        if os.name == 'nt':
            import msvcrt
            stream.seek(0)
            stream.write(b'0')
            stream.flush()
            stream.seek(0)
            try:
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError:
                fail('OPERATION_BUSY', '另一个安装或启动操作正在进行，请稍后重试。')
        else:
            import fcntl
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                fail('OPERATION_BUSY', '另一个安装或启动操作正在进行，请稍后重试。')
        yield
    finally:
        stream.close()


def validate_profile(profile, root):
    if not isinstance(profile, dict):
        fail('CONFIG_SCHEMA', '玩家 profile 必须是 JSON 对象。')
    if contains_secret(profile):
        fail('CONFIG_SECRET', '连接配置不能内嵌密码、票据或私钥。', '使用 credential-import 单独导入管理员签发的凭据。')
    p = dict(profile)
    if p.get('game_copy_mode', 'copy') not in ('copy', 'apfs-clone'):
        fail('CONFIG_COPY', '游戏复制方式只能为 copy 或 apfs-clone。')
    if p.get('schema', SCHEMA) != SCHEMA or p.get('platform') not in ('windows', 'crossover'):
        fail('CONFIG_PLATFORM', '请选择 windows 或 crossover 平台。')
    validate_root(root, p['platform'])
    connection = p.get('connection', {})
    if not isinstance(connection, dict):
        fail('CONFIG_SCHEMA', 'connection 必须是 JSON 对象。')
    connection = dict(connection)
    p['connection'] = connection
    transport = connection.get('transport', 'ssh')
    if transport not in ('ssh', 'local'):
        fail('CONFIG_TRANSPORT', '连接方式只能为 ssh 或 local。')
    connection['transport'] = transport
    target = connection.get('ssh_target', '')
    if transport == 'ssh' and (not isinstance(target, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._@-]{0,190}', target)):
        fail('CONFIG_SSH', 'SSH 主机或别名不合法。', '使用服务器管理员提供的 SSH 别名；先完成 SSH 密钥登录。')
    ports = connection.get('remote_ports', {})
    if not isinstance(ports, dict) or set(ports) != set(LOCAL_PORTS) or any(type(v) is not int or v < 1024 or v > 65535 for v in ports.values()):
        fail('CONFIG_PORT', '连接配置需要 udp_tcp、mc_ws、mc_server、hud 四个远端端口。')
    mode = connection.get('mode', 'legacy-lab')
    if mode not in ('legacy-lab', 'strict-player'):
        fail('CONFIG_SESSION_MODE', '只支持 legacy-lab 或 strict-player 会话模式。')
    connection['mode'] = mode
    overrides = connection.get('local_ports', {})
    if (not isinstance(overrides, dict) or not set(overrides).issubset(LOCAL_PORTS)
            or any(type(v) is not int or not 1 <= v <= 65535 for v in overrides.values())):
        fail('CONFIG_LOCAL_PORT', '本地端口只能覆盖 udp_tcp、mc_ws、mc_server、hud，范围为 1 到 65535。')
    local_ports = {**LOCAL_PORTS, **overrides}
    upstream = connection.get('upstream_ws_port', 25598)
    if type(upstream) is not int or not 1 <= upstream <= 65535:
        fail('CONFIG_LOCAL_PORT', '严格代理上游本地端口范围为 1 到 65535。')
    if transport == 'local':
        if mode != 'strict-player' or 'mc_ws' not in overrides:
            fail('CONFIG_LOCAL_PROXY', '本机后端连接需要 strict-player 和显式个人代理端口 connection.local_ports.mc_ws。')
        if local_ports['mc_ws'] in ports.values():
            fail('CONFIG_LOCAL_PROXY', '个人代理端口不能与本机后端任何监听端口相同。')
        if 'upstream_ws_port' in connection:
            fail('CONFIG_LOCAL_PROXY', '本机代理直接连接 remote_ports.mc_ws，不能另设 SSH 上游端口。')
        service_ports = dict(ports)
        upstream = ports['mc_ws']
    else:
        bound_ports = list(local_ports.values())
        if mode == 'strict-player':
            bound_ports.append(upstream)
        if len(bound_ports) != len(set(bound_ports)):
            fail('CONFIG_LOCAL_PORT', '个人代理和 SSH 转发的本地 TCP 端口必须各不相同。')
        service_ports = dict(local_ports)
        if mode == 'strict-player':
            service_ports['mc_ws'] = upstream
    if mode == 'strict-player':
        credential = str(Path(root).absolute() / '.palcraft/credentials/credential.json')
        connection.setdefault('credential_path', credential)
        if connection.get('credential_path') != credential:
            fail('CONFIG_CREDENTIAL', '严格玩家凭据必须保存在本安装的独立凭据目录。', '运行 credential-import。')
        identity = connection.get('identity', {})
        if set(identity) != {'world_id', 'pal_uid', 'mc_name', 'mc_uuid'}:
            fail('CONFIG_IDENTITY', '严格玩家配置缺少四项身份字段。')
        if connection.get('frame_mapping') != 'Local\\MCPassthroughFrame-' + str(identity.get('mc_uuid')):
            fail('CONFIG_FRAME', '严格 HUD 映射必须属于此玩家的 MC UUID。')
    session_id = connection.get('server_session_id', '')
    pending_standalone = (session_id is None and p.get('pal_entry_mode') == 'singleplayer' and transport == 'local'
                         and isinstance(p.get('standalone'), dict) and p['standalone'].get('enrollment_pending') is True)
    if not pending_standalone and (not isinstance(session_id, str) or not session_id.strip() or len(session_id) > 256 or any(c in session_id for c in '\r\n\x00')):
        fail('CONFIG_IDENTITY', '缺少服务器会话标识，不能启用桥接。', '从服务器管理员取得个人连接配置，不能复用其他玩家配置。')
    origin = connection.get('world_origin')
    if not isinstance(origin, dict) or set(origin) != {'X', 'Y', 'Z'} or any(type(v) not in (int, float) or not -1e10 < v < 1e10 for v in origin.values()):
        fail('CONFIG_ORIGIN', '缺少共享世界坐标原点。')
    if type(p.get('fps', 15)) is not int or not 10 <= p.get('fps', 15) <= 120:
        fail('CONFIG_FPS', '帧率上限应为 10 到 120。')
    from installer.performance import PRESETS, validate_performance
    if 'performance' not in p:
        preset = 'normal' if p.get('fps', 15) >= 60 else 'night'
        p['performance'] = {**PRESETS[preset], 'preset': preset, 'pal_fps': p.get('fps', 15)}
        if p['performance']['pal_fps'] != PRESETS[preset]['pal_fps']:
            p['performance']['preset'] = 'custom'
    p['performance'] = validate_performance(p['performance'], p.get('fps', 15))
    if type(p.get('mute', True)) is not bool:
        fail('CONFIG_SOUND', '静音选项必须为 true 或 false。')
    if p['platform'] == 'crossover':
        bottle = p.get('bottle_name', '')
        bottle_mode = p.get('bottle_mode', 'create-owned')
        if bottle_mode not in ('create-owned', 'existing-selected'):
            fail('BOTTLE_MODE', 'bottle_mode 只能为 create-owned 或 existing-selected。')
        p['bottle_mode'] = bottle_mode
        if bottle_mode == 'create-owned' and not re.fullmatch(r'PalCraft-Player-[A-Za-z0-9_-]{1,40}', bottle):
            fail('BOTTLE_PROTECTED', '新建模式只接受 PalCraft-Player-* 专用 bottle。')
        if bottle_mode == 'existing-selected' and (not isinstance(bottle, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_. -]{0,63}', bottle)):
            fail('BOTTLE_SELECTED', '请显式选择已有合法 CrossOver bottle 名称。')
        app = Path(p.get('crossover_app', '')).expanduser().absolute()
        bottle_root = Path(p.get('bottle_root', '')).expanduser().absolute()
        if app.name != 'CrossOver.app' or bottle_root.name != bottle or not p.get('bottle_root'):
            fail('CONFIG_CROSSOVER', 'CrossOver.app 路径或专用 bottle 路径不完整。')
        p['crossover_app'], p['bottle_root'] = str(app), str(bottle_root)
    try:
        p['windows_root'] = windows_root(root, p)
    except ValueError as exc:
        fail('CONFIG_ROOT', str(exc))
    p['schema'], p['root'] = SCHEMA, str(Path(root).absolute())
    p['local_ports'] = local_ports
    p['proxy_upstream_port'] = upstream
    p['service_ports'] = service_ports
    pal_entry = p.get('pal_entry_mode', 'dedicated')
    if pal_entry not in ('dedicated', 'singleplayer'):
        fail('PAL_ENTRY_MODE', '帕鲁入口只能为 dedicated 或 singleplayer。')
    p['pal_entry_mode'] = pal_entry
    p['game_endpoint'] = None if pal_entry == 'singleplayer' else {'host': '127.0.0.1', 'port': 8321}
    p.setdefault('fps', 15)
    p.setdefault('mute', True)
    return p


def _source_files(source):
    source = Path(source).resolve()
    required = ['Palworld.exe', 'Pal/Binaries/Win64/Palworld-Win64-Shipping.exe']
    if any(not (source / x).is_file() for x in required) or not (source / 'Pal/Content/Paks').is_dir():
        fail('GAME_MISSING', '请选择已有的正版 Palworld 游戏目录。', '目录需含 Palworld.exe、Shipping.exe 和 Pal/Content/Paks。')
    denied = ('ue4ss', 'saved', 'savegames', 'mods', 'userdata', 'steam', 'steamapps', 'reshade-shaders')
    files = []
    for base in ('Palworld.exe', 'Engine', 'Pal/Binaries', 'Pal/Content', 'Pal/Plugins'):
        start = source / base
        if not start.exists():
            continue
        candidates = [start] if start.is_file() else sorted(start.rglob('*'))
        for path in candidates:
            rel = path.relative_to(source)
            if path.is_symlink():
                fail('SOURCE_LINK', '游戏源目录含链接，无法保证隔离复制：' + str(rel))
            if not path.is_file():
                continue
            lower = path.name.lower()
            if any(part.lower() in denied for part in rel.parts) or lower.startswith(('palcraft', 'reshade', 'ssfn')) or lower in ('dwmapi.dll', 'dxgi.dll', 'loginusers.vdf') or path.suffix.lower() in ('.sav', '.log', '.pdb'):
                continue
            files.append((path, rel.as_posix()))
    return source, files


def install_plan(root, source, bundle_path, profile):
    profile = validate_profile(profile, root)
    root = validate_root(root, profile['platform'])
    bundle = Bundle(bundle_path)
    require_release_paths(bundle.manifest, profile)
    _bridge_files(profile, bundle.manifest)
    if bundle.manifest['platform'] not in (profile['platform'], 'both'):
        fail('BUNDLE_PLATFORM', '该发布包不支持所选平台。')
    if root.exists() and any(root.iterdir()) and marker(root, False) is None:
        fail('UNMANAGED_DIRECTORY', '安装目录已有内容，安装器不会接管它。', '请选择空的独立安装目录。')
    source, files = _source_files(source)
    if source == root or root.is_relative_to(source) or source.is_relative_to(root):
        fail('SOURCE_OVERLAP', '游戏源目录与目标目录不能相互包含。')
    game_hash = digest(source / 'Pal/Binaries/Win64/Palworld-Win64-Shipping.exe')
    if game_hash not in bundle.manifest['requirements']['palworld_shipping_sha256']:
        fail('GAME_VERSION', '帕鲁版本与此发布包不匹配。', '取得支持当前 Shipping.exe 的发布包；不要跳过版本校验。')
    existing = get_state(root) if marker(root, False) else {}
    copy_game = not (root / CLIENT / 'Palworld.exe').is_file()
    mode = profile.get('game_copy_mode', 'copy')
    needed = sum(path.stat().st_size for path, _ in files) if copy_game else 0
    needed += sum(f['bytes'] for f in bundle.manifest['files']) * 3 + 256 * 1024 * 1024
    parent = root
    while not parent.exists():
        parent = parent.parent
    if copy_game and mode == 'apfs-clone':
        if sys.platform != 'darwin' or source.stat().st_dev != parent.stat().st_dev:
            fail('CLONE_VOLUME', 'APFS 写时复制需要 Mac 上同一卷的源与目标目录。')
        needed = sum(f['bytes'] for f in bundle.manifest['files']) * 3 + len(files) * 65536 + 256 * 1024 * 1024
    if shutil.disk_usage(parent).free < needed:
        fail('DISK_SPACE', '磁盘空间不足，需要至少 ' + str(round(needed / 1024 ** 3, 2)) + ' GiB。')
    # This is the personal native journal directory, never a server payload.
    for relative in ('BridgeLab', CLIENT_JOURNAL):
        directory = owned_path(root, relative)
        if directory.exists() and not directory.is_dir():
            fail('CLIENT_JOURNAL', '个人事件目录被文件占用：' + str(directory))
    return {'ok': True, 'dry_run': True, 'version': bundle.manifest['version'], 'root': str(root),
            'game_source': str(source), 'copy_game': copy_game, 'game_files': len(files),
            'game_copy_mode': mode, 'source_file_inodes_shared': False,
            'payload_files': len(bundle.manifest['files']), 'required_free_bytes': needed,
            'previous_version': existing.get('current'), 'private_user_dir': str(root / USER),
            'client_journal_dir': str(root / CLIENT_JOURNAL),
            'servers_started_or_stopped': [], 'profile': profile}


def _recover_base_copy(root):
    pending_path = owned_path(root, '.palcraft/base-copy.pending.json')
    if not pending_path.exists():
        return False
    pending = read_json(pending_path)
    state = get_state(root)
    if pending.get('kind') != 'owned-base-copy' or not re.fullmatch(r'\.palcraft/staging/base-[a-f0-9]{32}', pending.get('staging', '')):
        fail('BASE_RECOVERY', '游戏复制恢复记录损坏。')
    target = owned_path(root, CLIENT)
    staging = owned_path(root, pending['staging'])
    container = target if target.exists() else staging
    for relative, expected in pending['files'].items():
        if not relative.startswith(CLIENT + '/'):
            fail('BASE_RECOVERY', '游戏复制记录包含未授权路径。')
        path = owned_path(container, relative[len(CLIENT) + 1:])
        if not path.is_file() or path.stat().st_size != expected['bytes'] or path.stat().st_mtime_ns != expected['mtime_ns']:
            fail('BASE_RECOVERY_CONFLICT', '游戏副本在中断后被修改，未接管它。')
    if digest(container / 'Pal/Binaries/Win64/Palworld-Win64-Shipping.exe') != pending['game_sha256']:
        fail('BASE_RECOVERY_CONFLICT', '中断后游戏版本校验失败。')
    if not target.exists():
        os.replace(staging, target)
    state['base_files'], state['game_sha256'] = pending['files'], pending['game_sha256']
    atomic_json(root / '.palcraft/state.json', state)
    pending_path.unlink()
    return True


def _clone_file(source, destination):
    import ctypes
    library = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    clone = library.clonefile
    clone.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int)
    clone.restype = ctypes.c_int
    if clone(os.fsencode(source), os.fsencode(destination), 0) != 0:
        fail('CLONE_FILE', '写时复制失败，未发布游戏副本：' + str(destination), '检查 APFS/同一卷支持，或显式选择普通 copy。')
    shutil.copystat(source, destination)


def _base_copy(root, source, allowed_hashes, copy_mode='copy'):
    _recover_base_copy(root)
    state = get_state(root)
    if state.get('base_files'):
        game = root / CLIENT / 'Pal/Binaries/Win64/Palworld-Win64-Shipping.exe'
        if state.get('game_sha256') not in allowed_hashes or not game.is_file() or digest(game) != state.get('game_sha256'):
            fail('GAME_MODIFIED', '已安装的帕鲁游戏文件有变化。', '先保留存档卸载，再从匹配的正版安装重新复制。')
        return state
    _, files = _source_files(source)
    staging = owned_path(root, '.palcraft/staging/base-' + uuid.uuid4().hex)
    staging.mkdir(parents=True)
    info = {}
    try:
        for original, relative in files:
            target = staging / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if copy_mode == 'apfs-clone':
                _clone_file(original, target)
            else:
                shutil.copy2(original, target)
            st = target.stat()
            info[CLIENT + '/' + relative] = {'bytes': st.st_size, 'mtime_ns': st.st_mtime_ns}
        copied_hash = digest(staging / 'Pal/Binaries/Win64/Palworld-Win64-Shipping.exe')
        if copied_hash not in allowed_hashes:
            fail('GAME_SOURCE_CHANGED', '复制期间游戏版本发生变化，未启用该副本。', '等待 Steam 更新完成后重试。')
        target = owned_path(root, CLIENT)
        if target.exists():
            fail('GAME_UNTRACKED', '目标客户端目录已有未登记文件，拒绝覆盖。')
        atomic_json(root / '.palcraft/base-copy.pending.json', {'kind': 'owned-base-copy',
                    'staging': staging.relative_to(root).as_posix(), 'files': info, 'game_sha256': copied_hash})
        os.replace(staging, target)
        state['base_files'] = info
        state['game_sha256'] = digest(root / CLIENT / 'Pal/Binaries/Win64/Palworld-Win64-Shipping.exe')
        atomic_json(root / '.palcraft/state.json', state)
        owned_path(root, '.palcraft/base-copy.pending.json').unlink()
    finally:
        if staging.exists() and not owned_path(root, '.palcraft/base-copy.pending.json').exists():
            shutil.rmtree(staging)
    return state


def _undo(root, journal):
    transaction = owned_path(root, '.palcraft/transactions/' + journal['id'])
    for item in reversed(journal['changes']):
        target = owned_path(root, item['target'])
        actual = digest(target) if target.is_file() else None
        if actual not in (item['new_sha256'], item['old_sha256']):
            fail('RECOVERY_CONFLICT', '恢复时发现文件被其他程序修改：' + item['target'], '已保留事务备份，请运行 diagnostics 后联系管理员。')
        if item['old_sha256'] is None:
            if target.exists():
                target.unlink()
        else:
            backup = transaction / 'before' / item['target']
            if not backup.is_file() or digest(backup) != item['old_sha256']:
                fail('RECOVERY_BACKUP', '事务备份损坏，未覆盖当前文件。')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(backup, target)
    atomic_json(root / '.palcraft/state.json', journal['before_state'])
    journal['phase'] = 'rolled_back'
    atomic_json(transaction / 'journal.json', journal)


def recover_transactions(root):
    marker(root)
    recovered = []
    if _recover_base_copy(root):
        recovered.append('base-copy')
    directory = owned_path(root, '.palcraft/transactions')
    if directory.exists():
        for path in sorted(directory.glob('*/journal.json')):
            if path.is_symlink() or path.parent.is_symlink():
                fail('DIRECTORY_LINK', '恢复目录包含链接。')
            journal = read_json(path)
            if journal['phase'] not in ('committed', 'rolled_back'):
                _undo(root, journal)
                recovered.append(journal['id'])
    return recovered


def _retained_launch_template(root, profile, before):
    """Retain the transition's one owned argv template in ordinary release transactions."""
    spec = profile.get('standalone') or {}
    pointer = (spec.get('backend_configuration') or {}).get('preserve_launch_template')
    if not pointer:
        return {}
    target = TOOLS + '/standalone/previous-launch-plan.json'
    path = owned_path(root, target)
    if pointer != str(path):
        fail('GENERATED_CONFIG_SCOPE', '原启动模板必须属于本安装的固定生成路径。')
    expected = before.get('files', {}).get(target)
    if path.is_file():
        if expected is None:
            fail('GENERATED_CONFIG_UNMANAGED', '原启动模板未登记在本安装的文件归属中，拒绝接管。')
        if digest(path) != expected:
            fail('UPDATE_CONFLICT', '已安装文件被修改，不能覆盖：' + target)
        content = path.read_bytes()
    else:
        # An older ordinary update omitted this generated dependency. Recover only
        # an actual committed deletion with its own managed-SHA and before backup.
        candidates = {}
        directory = owned_path(root, '.palcraft/transactions')
        for receipt in sorted(directory.glob('*/journal.json')):
            receipt = owned_path(root, receipt.relative_to(root).as_posix())
            journal = read_json(receipt)
            previous = journal.get('before_state', {})
            old = previous.get('profile', {})
            old_spec = old.get('standalone') or {}
            if (journal.get('phase') != 'committed' or journal.get('id') != receipt.parent.name
                    or old.get('root') != profile.get('root')
                    or old.get('platform') != profile.get('platform')
                    or old.get('pal_entry_mode') != profile.get('pal_entry_mode')
                    or old.get('connection', {}).get('identity') != profile['connection']['identity']
                    or old_spec.get('backend_root') != spec.get('backend_root')
                    or (old_spec.get('backend_configuration') or {}).get('preserve_launch_template') != pointer):
                continue
            for change in journal.get('changes', []):
                sha = change.get('old_sha256')
                if (change.get('target') != target or change.get('new_sha256') is not None
                        or not isinstance(sha, str) or not re.fullmatch(r'[a-f0-9]{64}', sha)
                        or previous.get('files', {}).get(target) != sha
                        or (expected is not None and expected != sha)):
                    continue
                backup = owned_path(root, (receipt.parent / 'before' / target).relative_to(root).as_posix())
                if not backup.is_file() or digest(backup) != sha:
                    fail('RECOVERY_BACKUP', '原启动模板的事务备份缺失或损坏，未恢复。')
                candidates[sha] = backup.read_bytes()
        if len(candidates) != 1:
            fail('GENERATED_CONFIG_MISSING', '缺少唯一且校验通过的原受管理启动模板，未重造角色参数。')
        content = next(iter(candidates.values()))
    try:
        value = json.loads(content)
        identity = profile['connection']['identity']
        bridge = str(root / DEV / 'bridge')
        roles = value['roles']
        cwds = {'server': str(Path(spec['backend_root']) / 'server'),
                'guest': str(Path(spec['backend_root']) / 'players' / identity['mc_uuid'] / 'minecraft'),
                'hud': bridge}
        if (value.get('schema') != 1 or value.get('role_arguments_preserved') is not True
                or set(roles) != set(cwds)
                or any(row.get('role') != role or row.get('cwd') != cwds[role]
                       or row.get('same_original_uuid') != identity['mc_uuid']
                       or row.get('frame_file') != str(root / DEV / 'bridge/mcpt-hud.bin')
                       or not isinstance(row.get('arguments'), list)
                       or not all(isinstance(arg, str) for arg in row['arguments'])
                       for role, row in roles.items())):
            fail('GENERATED_CONFIG_SCOPE', '原启动模板不属于当前后端、玩家或帧路径。')
    except (ValueError, TypeError, KeyError, AttributeError):
        fail('GENERATED_CONFIG_SCOPE', '原启动模板结构不完整，未重造角色参数。')
    return {target: content}


NORMAL_STANDALONE_DATA = {'.palcraft/standalone/scope.json',
    TOOLS + '/standalone/mac-runtime-config.json', DEV + '/bridge/lab-identity.json'}


def _managed_generated_baseline(root, before, target):
    """Only the exact managed bytes from an original committed transaction qualify."""
    expected = before.get('files', {}).get(target)
    if not isinstance(expected, str) or not re.fullmatch(r'[a-f0-9]{64}', expected):
        fail('GENERATED_OWNER_UNMANAGED', '正常生成数据必须已有本安装的文件归属：' + target)
    candidates = {}
    directory = owned_path(root, '.palcraft/transactions')
    for receipt in sorted(directory.glob('*/journal.json')):
        receipt = owned_path(root, receipt.relative_to(root).as_posix())
        journal = read_json(receipt)
        if journal.get('phase') != 'committed' or journal.get('id') != receipt.parent.name:
            continue
        changes = journal.get('changes', [])
        for location in ('generated', 'before'):
            proven = (journal.get('before_state', {}).get('files', {}).get(target) == expected
                      or any(row.get('target') == target and row.get('new_sha256' if location == 'generated' else 'old_sha256') == expected
                             for row in changes))
            if not proven:
                continue
            path = owned_path(root, (receipt.parent / location / target).relative_to(root).as_posix())
            if path.is_file() and digest(path) == expected:
                candidates[expected] = path.read_bytes()
    if len(candidates) != 1:
        fail('GENERATED_OWNER_BASELINE', '缺少原已提交事务内校验通过的受管理生成数据：' + target)
    return json.loads(next(iter(candidates.values())))


def _same_boot_generated_stop(root, before, after):
    """Read the original complete off witness; never save, stop, rotate, or mint one."""
    from launcher.journal_lifecycle import (EVENTS, LIFECYCLE, _check_previous_actors,
        _persistent_inventory, file_identity, UNSAVED_CRASH_KIND, UNSAVED_CRASH_RECEIPT,
        _crash_persistent_inventory, _unsaved_crash_receipt_matches)
    owner = marker(root)
    session = read_json(owned_path(root, '.palcraft/session.json'))
    pointer = read_json(owned_path(root, LIFECYCLE + '/current.json'))
    token = session.get('token', '')
    saved_crash = session.get('phase') == 'failed' and session.get('code') == 'CLIENT_EXIT'
    if ((session.get('phase') != 'stopped' and not saved_crash) or not re.fullmatch(r'[a-f0-9]{32}', token)
            or pointer.get('token') != token):
        fail('GENERATED_OWNER_STOP', '正常生成数据归属需要当前同 boot 的完整正常停机见证。')
    prefix = LIFECYCLE + '/' + token + '/'
    scope = read_json(owned_path(root, prefix + 'scope.json'))
    receipt_path = owned_path(root, prefix + ('saved-crash-off-receipt.json' if saved_crash else 'normal-stop-receipt.json'))
    unsaved_path = owned_path(root, prefix + UNSAVED_CRASH_RECEIPT)
    unsaved_crash = saved_crash and unsaved_path.is_file()
    if unsaved_crash:
        receipt_path = unsaved_path
    if not receipt_path.is_file():
        fail('GENERATED_OWNER_STOP', '尚无当前同 boot 的完整正常停机回执，未采纳生成数据。', '用原 finalize-stop 签收已有真实正常关闭记录后，再运行普通 update。')
    receipt = read_json(receipt_path)
    native = scope.get('native_scope', {})
    title = scope.get('normal_title_observed', {})
    if unsaved_crash:
        stop_truth = _unsaved_crash_receipt_matches(root, scope, session, receipt)
    elif saved_crash:
        from launcher.journal_lifecycle import _saved_crash_receipt_matches
        stop_truth = _saved_crash_receipt_matches(root, scope, session, receipt)
    else:
        stop_truth = (isinstance(title, dict) and title.get('action') == 'observe_title'
            and title.get('token') == token and title.get('process_epoch') == native.get('process_epoch')
            and bool(title.get('request_id')) and receipt.get('normal_title_Quit_and_native_exit0') is True)
    actors, exits = scope.get('actors', {}), receipt.get('actor_exits', {})
    witness = receipt.get('normal_save_witness', {})
    stream = owned_path(root, EVENTS)
    stream_identity = file_identity(stream) if stream.exists() else None
    identity = before['profile']['connection'].get('identity', {})
    next_connection = after['profile']['connection']
    required = ('server_session_id', 'process_epoch', 'world_id', 'pal_uid', 'save_boot_id')
    if (scope.get('root') != str(root) or scope.get('root_id') != owner['id'] or scope.get('token') != token
            or receipt.get('schema') != 1 or receipt.get('kind') != (UNSAVED_CRASH_KIND if unsaved_crash else 'palcraft-owned-saved-crash-off-v1' if saved_crash else 'palcraft-owned-normal-stop-v1')
            or receipt.get('root') != str(root) or receipt.get('root_id') != owner['id'] or receipt.get('token') != token
            or receipt.get('native_scope') != native or not stop_truth
            or any(not isinstance(native.get(key), str) or not native[key] for key in required)
            or type(native.get('pid')) is not int or native['pid'] < 1
            or native['world_id'] != identity.get('world_id') or native['pal_uid'] != identity.get('pal_uid')
            or native['server_session_id'] != before['profile']['connection'].get('server_session_id')
            or next_connection.get('identity') != identity or next_connection.get('server_session_id') != native['server_session_id']
            or receipt.get('active_events_path') != str(stream) or scope.get('active_events_path') != str(stream)
            or receipt.get('stream_identity') != stream_identity
            or not actors or set(exits) != set(actors)
            or any(exits[name].get('actual_wait_completed') is not True
                   or any(exits[name].get(key) != actor.get(key) for key in ('pid', 'identity', 'role'))
                   for name, actor in actors.items())
            or any(receipt.get(key) is not True for key in ((() if unsaved_crash else ('normal_save_completed',)) + (
                   'all_owned_producers_and_consumers_stopped', 'all_this_stream_producers_and_consumers_off_before_rotation',
                   'Saved_and_WAL_stable_after_all_actors_off')))
            or (not unsaved_crash and (witness.get('native_scope') != native or witness.get('after_submission') is not True
                or witness.get('stable') is not True or not witness.get('normal_save_id')))
            or (unsaved_crash and (receipt.get('normal_save_completed') is not False
                or receipt.get('mutations_may_be_unpersisted') is not True))):
        fail('GENERATED_OWNER_SCOPE', '完整正常停机见证、当前进程世界身份或事件卷不一致，未采纳生成数据。')
    inventory = _crash_persistent_inventory if unsaved_crash else _persistent_inventory
    if inventory(root) != receipt.get('persistent_stat_inventory'):
        fail('GENERATED_OWNER_SAVE', '正常停机后 Saved/WAL 已更改，未采纳旧见证。')
    _check_previous_actors(root, scope)
    return native, scope, receipt, digest(receipt_path)


def _normal_generated_adoption(root, before, after, extra_files):
    profile = before.get('profile', {})
    if (profile.get('platform') != 'crossover' or profile.get('pal_entry_mode') != 'singleplayer'
            or profile.get('standalone') is None or profile.get('connection', {}).get('transport') != 'local'):
        return {}, None
    changed = {}
    for target in NORMAL_STANDALONE_DATA:
        path = owned_path(root, target)
        expected = before.get('files', {}).get(target)
        if expected and path.is_file() and digest(path) != expected:
            changed[target] = path.read_bytes()
    if not changed:
        return {}, None
    native, scope, receipt, receipt_sha = _same_boot_generated_stop(root, before, after)
    identity = profile['connection']['identity']
    expected_log = profile['windows_root'] + '/' + BIN + 'ue4ss/UE4SS.log'
    adopted = {}
    for target, raw in changed.items():
        value = json.loads(raw)
        baseline = _managed_generated_baseline(root, before, target)
        if target == '.palcraft/standalone/scope.json':
            expected = dict(baseline)
            if type(baseline.get('configured_for_runtime')) is not bool or value.get('configured_for_runtime') is not True:
                fail('GENERATED_OWNER_DATA', '只接受原正常登记生成的 configured_for_runtime=true。')
            expected.update(configured_for_runtime=True, client_log_windows=expected_log)
            if (value != expected or value.get('world_directory') != native['world_id'] or value.get('pal_uid') != native['pal_uid']
                    or value.get('install_root_windows') != profile['windows_root']):
                fail('GENERATED_OWNER_DATA', 'scope 只能含原正常登记位和真实客户端日志路径变化。')
            desired = json.loads(extra_files[target]) if target in extra_files else {}
            if desired.get('client_log_windows') != expected_log:
                fail('GENERATED_OWNER_LOG', '新正常生成器必须保留原真实 client_log_windows，不能退回旧字段。')
        elif target == TOOLS + '/standalone/mac-runtime-config.json':
            expected = dict(baseline)
            if type(baseline.get('configured_for_actual_boot')) is not bool or value.get('configured_for_actual_boot') is not True:
                fail('GENERATED_OWNER_DATA', '只接受原正常登记生成的 configured_for_actual_boot=true。')
            expected['configured_for_actual_boot'] = True
            if value != expected or value.get('guest_mc_uuid') != identity['mc_uuid'] or value.get('guest_mc_name') != identity['mc_name']:
                fail('GENERATED_OWNER_DATA', 'Mac 配置除原正常登记位外发生变化，未采纳。')
        else:
            keys = {'realm_mode', 'world_directory', 'server_session_id', 'host_uid', 'process_epoch', 'observed_unix'}
            observed = value.get('observed_unix')
            if (set(baseline) not in ({'server_session_id'}, keys) or set(value) != keys or value.get('realm_mode') != 'standalone'
                    or value.get('world_directory') != native['world_id'] or value.get('host_uid') != native['pal_uid']
                    or value.get('server_session_id') != native['server_session_id'] or value.get('process_epoch') != native['process_epoch']
                    or type(observed) is not int or observed < scope.get('started_unix', float('inf')) - 5
                    or observed > receipt.get('observed_unix', 0) + 5):
                fail('GENERATED_OWNER_DATA', 'lab identity 必须来自当前同 boot 原 dispatcher 的六项真实字段。')
            # Keep the actual current SID/process epoch, never an old release's identity placeholder.
            extra_files[target] = raw
        adopted[target] = hashlib.sha256(raw).hexdigest()
    receipt_key = ('unsaved_crash_off_receipt_sha256' if receipt.get('kind') == 'palcraft-owned-unsaved-crash-off-v1'
                   else 'saved_crash_off_receipt_sha256' if receipt.get('kind') == 'palcraft-owned-saved-crash-off-v1'
                   else 'normal_stop_receipt_sha256')
    return adopted, {receipt_key: receipt_sha, 'targets': sorted(adopted),
        **({'normal_save_completed': False, 'mutations_may_be_unpersisted': True,
            'original_business_recovery': receipt['original_business_recovery']}
           if receipt.get('kind') == 'palcraft-owned-unsaved-crash-off-v1' else {})}


def _apply(root, release, state_after, extra_files=None, fault=None, configuration_only=False):
    before = get_state(root)
    extra_files = dict(extra_files or {})
    adopted_generated, adoption_receipt = _normal_generated_adoption(root, before, state_after, extra_files)
    if not configuration_only:
        extra_files.update(_retained_launch_template(root, state_after['profile'], before))
    directory = root / '.palcraft/transactions' / uuid.uuid4().hex
    directory.mkdir(parents=True)
    if configuration_only and (state_after.get('manifest') != before.get('manifest') or
                               state_after.get('current') != before.get('current')):
        fail('CONFIG_RELEASE', '仅配置事务不能更换发布清单或版本。')
    desired = {} if configuration_only else {entry['target']: (release / entry['target'], entry['sha256']) for entry in state_after['manifest']['files']}
    for target, content in extra_files.items():
        safe_rel(target)
        generated = directory / 'generated' / target
        generated.parent.mkdir(parents=True, exist_ok=True)
        generated.write_bytes(content)
        desired[target] = (generated, digest(generated))
    changes = []
    targets = set(desired) if configuration_only else set(before.get('files', {})) | set(desired)
    for target in sorted(targets):
        path = owned_path(root, target)
        old_sha = digest(path) if path.is_file() else None
        expected = before.get('files', {}).get(target)
        if expected and old_sha not in (None, expected) and adopted_generated.get(target) != old_sha:
            fail('UPDATE_CONFLICT', '已安装文件被修改，不能覆盖：' + target, '备份自己的修改，或保留存档后重新安装。')
        new_sha = desired[target][1] if target in desired else None
        if old_sha == new_sha and target not in adopted_generated:
            continue
        if old_sha:
            backup = directory / 'before' / target
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup)
        changes.append({'target': target, 'old_sha256': old_sha, 'new_sha256': new_sha})
    journal = {'schema': SCHEMA, 'id': directory.name, 'phase': 'applying', 'before_state': before, 'changes': changes}
    if adoption_receipt is not None:
        journal['normal_generated_adoption'] = adoption_receipt
    atomic_json(directory / 'journal.json', journal)
    try:
        for number, change in enumerate(changes):
            path = owned_path(root, change['target'])
            if change['new_sha256'] is None:
                if path.exists():
                    path.unlink()
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                pending = path.with_name(path.name + '.palcraft-pending')
                shutil.copy2(desired[change['target']][0], pending)
                os.replace(pending, path)
            if fault:
                fault(number, change)
        state_after['files'] = ({**before.get('files', {}), **{target: value[1] for target, value in desired.items()}}
                                if configuration_only else {target: value[1] for target, value in desired.items()})
        atomic_json(root / '.palcraft/state.json', state_after)
        journal['phase'] = 'committed'
        atomic_json(directory / 'journal.json', journal)
    except Exception:
        _undo(root, journal)
        raise


RUNTIME_FEATURES = {'entities_enabled', 'entity_visuals_enabled', 'food_enabled', 'environment_enabled',
                    'world_overworld', 'chunk_enabled', 'travel_enabled', 'fluid_physics_enabled',
                    'sign_text_enabled', 'exchange_enabled', 'lab_candidate', 'rebase_enabled',
                    'world_scoped_cam_enabled', 'operator_enabled', 'entity_capture_enabled', 'material_tint_enabled',
                    'boot_observer_enabled'}


def _bridge_files(profile, manifest=None):
    connection = profile['connection']
    runtime = {'schema': 1, 'identity': connection.get('identity'), 'session_mode': connection.get('mode', 'legacy-lab'),
               'entities_enabled': connection.get('mode') == 'strict-player', 'strict_sessions': connection.get('mode') == 'strict-player',
               'travel_enabled': False, 'exchange_enabled': False, 'chunk_enabled': False,
               'fluid_enabled': False, 'power_profile': profile.get('performance', {}).get('preset', 'night')}
    options = (manifest or {}).get('requirements', {}).get('player_runtime', {})
    for key, value in options.get('features', {}).items():
        if key not in RUNTIME_FEATURES or type(value) is not bool:
            fail('RUNTIME_CONFIG', '发布包的客户端功能配置不受支持：' + str(key))
        runtime[key] = value
    if options.get('model_asset_directory') is not None:
        name = options['model_asset_directory']
        if not isinstance(name, str) or not re.fullmatch(r'models-v4-[a-f0-9]+', name):
            fail('RUNTIME_CONFIG', '模型资源目录必须位于本安装的个人 bridge 中。')
        runtime['model_asset_directory'] = name
    runtime['exchange_root'] = profile['windows_root'] + '/' + DEV + '/bridge/exchange'
    runtime.update(collision_verified=False, visual_verified=False, runtime_accepted=False, in_game_verified=False)
    runtime['pal_entry_mode'] = profile.get('pal_entry_mode', 'dedicated')
    from installer.performance import remote_plan
    files = {DEV + '/bridge/lab-identity.json': (json.dumps({'server_session_id': connection['server_session_id']}, ensure_ascii=False) + '\n').encode(),
            DEV + '/bridge/world-origin.json': (json.dumps(connection['world_origin']) + '\n').encode(),
            DEV + '/bridge/runtime-config.json': (json.dumps(runtime, ensure_ascii=False) + '\n').encode(),
            DEV + '/bridge/personal-performance-request.json': (json.dumps(remote_plan(profile), ensure_ascii=False) + '\n').encode()}
    if profile.get('standalone') is not None:
        from installer.standalone import generated_files
        files.update(generated_files(profile, manifest))
    return files


def install(root, source, bundle_path, profile, dry_run=False, fault=None):
    plan = install_plan(root, source, bundle_path, profile)
    if dry_run:
        return plan
    root = Path(plan['root'])
    root.mkdir(parents=True, exist_ok=True)
    with operation_lock(root):
        if marker(root, False) is None:
            if any(p.name != '.palcraft' for p in root.iterdir()) or any(p.name != 'operation.lock' for p in (root / '.palcraft').iterdir()):
                fail('UNMANAGED_DIRECTORY', '安装前目录被其他程序写入，未接管它。')
            atomic_json(root / '.palcraft/owner.json', {'schema': SCHEMA, 'kind': 'palcraft-player-owned-root', 'root': str(root), 'id': uuid.uuid4().hex})
        ensure_no_session(root)
        recover_transactions(root)
        bundle = Bundle(bundle_path)
        state = _base_copy(root, source, bundle.manifest['requirements']['palworld_shipping_sha256'], plan['game_copy_mode'])
        profile = plan['profile']
        version = bundle.manifest['version']
        release = owned_path(root, '.palcraft/releases/' + version)
        if release.exists():
            previous = read_json(release / 'release-info.json')
            if previous['bundle_sha256'] != bundle.sha256:
                fail('VERSION_REUSED', '同一版本号对应不同文件，已拒绝安装。', '发布者必须为新内容使用新版本号。')
        else:
            staging = owned_path(root, '.palcraft/staging/release-' + uuid.uuid4().hex)
            bundle.extract(staging)
            atomic_json(staging / 'release-info.json', {'manifest': bundle.manifest, 'bundle_sha256': bundle.sha256})
            release.parent.mkdir(parents=True, exist_ok=True)
            os.replace(staging, release)
        history = list(state.get('history', []))
        if state.get('current') and state['current'] != version:
            history.append(state['current'])
        after = {**state, 'current': version, 'history': history, 'manifest': bundle.manifest,
                 'profile': profile, 'installed': True, 'updated_unix': time.time()}
        extras = _bridge_files(profile, bundle.manifest)
        owned_path(root, CLIENT_JOURNAL).mkdir(parents=True, exist_ok=True)
        _apply(root, release, after, extras, fault)
        owned_path(root, USER).mkdir(exist_ok=True)
        return {'ok': True, 'version': version, 'previous_version': state.get('current'), 'root': str(root), 'private_user_dir': str(root / USER),
                'client_journal_dir': str(root / CLIENT_JOURNAL), 'servers_started_or_stopped': []}


def update(root, bundle_path, dry_run=False, fault=None):
    root = Path(root).absolute()
    state = get_state(root)
    bundle = Bundle(bundle_path)
    require_release_paths(bundle.manifest, validate_profile(state['profile'], root))
    if not state.get('installed'):
        fail('NOT_INSTALLED', '尚未安装客户端。')
    if state['profile']['platform'] not in (bundle.manifest['platform'],) and bundle.manifest['platform'] != 'both':
        fail('BUNDLE_PLATFORM', '更新包与安装平台不匹配。')
    if state['game_sha256'] not in bundle.manifest['requirements']['palworld_shipping_sha256']:
        fail('GAME_VERSION', '更新包不支持当前帕鲁版本。')
    if dry_run:
        return {'ok': True, 'dry_run': True, 'from_version': state['current'], 'to_version': bundle.manifest['version'], 'payload_files': len(bundle.manifest['files'])}
    with operation_lock(root):
        ensure_no_session(root)
        recover_transactions(root)
        state = get_state(root)
        version = bundle.manifest['version']
        release = owned_path(root, '.palcraft/releases/' + version)
        if release.exists():
            if read_json(release / 'release-info.json')['bundle_sha256'] != bundle.sha256:
                fail('VERSION_REUSED', '版本号相同但内容不同，拒绝更新。')
        else:
            staging = owned_path(root, '.palcraft/staging/release-' + uuid.uuid4().hex)
            bundle.extract(staging)
            atomic_json(staging / 'release-info.json', {'manifest': bundle.manifest, 'bundle_sha256': bundle.sha256})
            release.parent.mkdir(parents=True, exist_ok=True)
            os.replace(staging, release)
        history = list(state.get('history', []))
        if state['current'] != version:
            history.append(state['current'])
        after = {**state, 'current': version, 'history': history, 'manifest': bundle.manifest, 'updated_unix': time.time()}
        _apply(root, release, after, _bridge_files(state['profile'], bundle.manifest), fault)
        return {'ok': True, 'version': version, 'previous_version': state['current'], 'saves_preserved': True}


def rollback(root, dry_run=False):
    root = Path(root).absolute()
    state = get_state(root)
    if not state.get('history'):
        fail('ROLLBACK_EMPTY', '没有可回退的上一版。')
    version = state['history'][-1]
    previous = read_json(owned_path(root, '.palcraft/releases/' + version + '/release-info.json'))
    require_release_paths(previous['manifest'], validate_profile(state['profile'], root))
    if dry_run:
        return {'ok': True, 'dry_run': True, 'from_version': state['current'], 'to_version': version}
    with operation_lock(root):
        ensure_no_session(root)
        recover_transactions(root)
        state = get_state(root)
        version = state['history'][-1]
        release = owned_path(root, '.palcraft/releases/' + version)
        info = read_json(release / 'release-info.json')
        require_release_paths(info['manifest'], validate_profile(state['profile'], root))
        for entry in info['manifest']['files']:
            if digest(owned_path(release, entry['target'])) != entry['sha256']:
                fail('ROLLBACK_HASH', '上一版快照损坏，未进行回退。')
        after = {**state, 'current': version, 'history': state['history'][:-1], 'manifest': info['manifest'], 'updated_unix': time.time()}
        _apply(root, release, after, _bridge_files(state['profile'], info['manifest']))
        return {'ok': True, 'version': version, 'previous_version': state['current'], 'saves_preserved': True}


def configure(root, profile, dry_run=False):
    root = Path(root).absolute()
    state = get_state(root)
    profile = validate_profile(profile, root)
    if profile['platform'] != state['profile']['platform']:
        fail('CONFIG_PLATFORM', '不能通过配置把已有安装切换到另一平台。')
    if dry_run:
        return {'ok': True, 'dry_run': True, 'profile': profile}
    with operation_lock(root):
        ensure_no_session(root)
        recover_transactions(root)
        state = get_state(root)
        after = {**state, 'profile': profile}
        _apply(root, root / '.palcraft/releases' / state['current'], after, _bridge_files(profile, state['manifest']))
        return {'ok': True, 'message': '配置已保存。'}


def configure_standalone_transition(root, profile, extra_files, dry_run=False, fault=None, preflight=None):
    """Use the original recoverable transaction for selected generated config, retaining every payload entry."""
    root = Path(root).absolute()
    state = get_state(root)
    profile = validate_profile(profile, root)
    allowed = {'.palcraft/standalone/scope.json', '.palcraft/standalone/resume.json',
               TOOLS + '/standalone/mac-runtime-config.json', TOOLS + '/standalone/previous-launch-plan.json',
               DEV + '/mcp/ai-transport.json', DEV + '/mcp/mc-transport.json'}
    if (profile.get('standalone') is None or profile['platform'] != state['profile']['platform']
            or not extra_files or not set(extra_files).issubset(allowed)):
        fail('CONFIG_STANDALONE', '迁移只接受当前平台的独立单机 profile 与原生成配置目的路径。')
    for content in extra_files.values():
        if contains_secret(json.loads(content)):
            fail('CONFIG_SECRET', '迁移配置不能带入个人私钥或凭据内容。')
    if dry_run:
        return {'ok': True, 'dry_run': True, 'profile': profile, 'configuration_targets': sorted(extra_files)}
    with operation_lock(root):
        ensure_no_session(root)
        recover_transactions(root)
        if preflight is not None:
            preflight()
        state = get_state(root)
        after = {**state, 'profile': profile}
        _apply(root, None, after, extra_files, fault, configuration_only=True)
    return {'ok': True, 'configuration_targets': sorted(extra_files), 'payload_or_Saved_or_backend_files_reapplied': False}


def uninstall(root, dry_run=False, purge_saves=False):
    root = Path(root).absolute()
    state = get_state(root)
    removable, kept = [], []
    for rel, sha in state.get('files', {}).items():
        path = owned_path(root, rel)
        if path.is_file():
            (removable if digest(path) == sha else kept).append(rel)
    for rel, expected in state.get('base_files', {}).items():
        path = owned_path(root, rel)
        if path.is_file():
            st = path.stat()
            (removable if st.st_size == expected['bytes'] and st.st_mtime_ns == expected['mtime_ns'] else kept).append(rel)
    result = {'ok': True, 'dry_run': dry_run, 'remove_files': len(removable), 'modified_files_preserved': kept,
              'saves_preserved': not purge_saves, 'save_directory': str(root / USER), 'bottle_preserved': True, 'servers_started_or_stopped': []}
    if dry_run:
        return result
    with operation_lock(root):
        ensure_no_session(root)
        recover_transactions(root)
        for rel in removable:
            owned_path(root, rel).unlink(missing_ok=True)
        if purge_saves:
            save = owned_path(root, USER)
            if save.exists():
                shutil.rmtree(save)
        for tree in (CLIENT, DEV):
            directory = owned_path(root, tree)
            if directory.exists():
                for path in sorted(directory.rglob('*'), reverse=True):
                    if path.is_dir() and not path.is_symlink():
                        try:
                            path.rmdir()
                        except OSError:
                            pass
                try:
                    directory.rmdir()
                except OSError:
                    pass
        atomic_json(root / '.palcraft/state.json', {'schema': SCHEMA, 'installed': False, 'current': None,
                    'history': [], 'files': {}, 'base_files': {}, 'preserved': kept, 'profile': state['profile']})
    return result
