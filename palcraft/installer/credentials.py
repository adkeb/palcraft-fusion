"""Import an operator-issued local credential. Inspection is not signature verification."""
import base64
import json
import os
import re
import time
import uuid
from pathlib import Path

from installer.core import (atomic_json, configure, ensure_no_session, fail, get_state,
                            operation_lock, owned_path, read_json, validate_profile)

CREDENTIAL_REL = '.palcraft/credentials/credential.json'
IDENTITY_KEYS = ('world_id', 'pal_uid', 'mc_uuid', 'mc_name')


def decode64(text):
    if not isinstance(text, str) or not re.fullmatch(r'[A-Za-z0-9_-]+', text):
        fail('CREDENTIAL_ENCODING', '玩家凭据编码不合法。')
    try:
        return base64.b64decode(text + '=' * (-len(text) % 4), altchars=b'-_', validate=True)
    except ValueError:
        fail('CREDENTIAL_ENCODING', '玩家凭据编码不合法。')


def inspect_credential(path, now=None):
    path = Path(path)
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 32768:
        fail('CREDENTIAL_FILE', '玩家凭据缺失、过大或是链接。')
    value = read_json(path)
    token = value.get('grant', '')
    if value.get('v') != 2 or not isinstance(token, str) or len(token) > 8192 or token.count('.') != 1:
        fail('CREDENTIAL_SCHEMA', '需要服务器管理员签发的 v2 玩家凭据。')
    try:
        grant = json.loads(decode64(token.split('.')[0]).decode('utf-8'))
    except (ValueError, UnicodeError):
        fail('CREDENTIAL_GRANT', '玩家证书内容损坏。')
    if len(decode64(token.split('.')[1])) != 64:
        fail('CREDENTIAL_ENCODING', '玩家证书签名长度不正确。')
    host_key = decode64(value.get('host_secret', ''))
    private_key = decode64(value.get('holder_private', ''))
    if len(host_key) != 32 or not private_key or grant.get('v') != 2:
        fail('CREDENTIAL_KEY', '玩家凭据缺少正确的 host_secret 或 holder_private。')
    identity = {key: grant.get(key) for key in IDENTITY_KEYS}
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.:/-]{0,127}', str(identity['world_id'])):
        fail('CREDENTIAL_IDENTITY', '玩家证书世界标识不合法。')
    try:
        for key in ('pal_uid', 'mc_uuid'):
            if str(uuid.UUID(identity[key])) != identity[key] or uuid.UUID(identity[key]).int == 0:
                fail('CREDENTIAL_IDENTITY', '玩家证书 UUID 不合法。')
        uuid.UUID(grant['credential_id'])
    except (ValueError, TypeError, KeyError, AttributeError):
        fail('CREDENTIAL_IDENTITY', '玩家证书身份不完整。')
    name = identity['mc_name']
    if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9_]{1,16}', name):
        fail('CREDENTIAL_IDENTITY', '玩家证书 Minecraft 名称不合法。')
    # This is how the operator/guest computes the offline identity; no private key is exposed.
    offline = bytearray(__import__('hashlib').md5(('OfflinePlayer:' + name).encode()).digest())
    offline[6], offline[8] = (offline[6] & 15) | 48, (offline[8] & 63) | 128
    if str(uuid.UUID(bytes=bytes(offline))) != identity['mc_uuid']:
        fail('CREDENTIAL_IDENTITY', '玩家 MC 名称与持久 UUID 不一致。')
    session_id = grant.get('server_session_id')
    if not isinstance(session_id, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.:/-]{0,127}', session_id):
        fail('CREDENTIAL_IDENTITY', '缺少证书绑定的帕鲁服务器会话。')
    scopes = grant.get('scopes')
    needed = {'mc.login', 'pose', 'input', 'gui', 'inventory', 'world.read', 'terrain'}
    if not isinstance(scopes, list) or set(scopes) != needed:
        fail('CREDENTIAL_SCOPE', '只接受正常玩家权限证书，不能导入管理员或 relay 权限。')
    issued, expires = grant.get('issued_at'), grant.get('expires_at')
    clock = time.time() if now is None else now
    if type(issued) is not int or type(expires) is not int or issued > clock + 5 or expires <= clock or not 0 < expires - issued <= 86400:
        fail('CREDENTIAL_EXPIRED', '玩家凭据已过期、尚未生效或有效期异常。', '从服务器管理员重新取得当前服务器会话的玩家凭据。')
    if value.get('identity') != identity or value.get('server_session_id') != session_id or value.get('expires_at') != expires:
        fail('CREDENTIAL_MISMATCH', '凭据的公开字段与证书内容不一致。')
    return {'v': 2, 'identity': identity, 'server_session_id': session_id, 'expires_at': expires,
            'inspection_only': True, 'signature_verified_locally': False,
            'trust_source': 'operator-issued file received over administrator-authenticated SSH'}


def prepare_credential_profile(profile, root, credential_path, guest_manifest_path):
    root = Path(root).absolute()
    inspected = inspect_credential(credential_path)
    guest = read_json(guest_manifest_path)
    if guest.get('schema') != 1 or guest.get('identity') != inspected['identity'] or guest.get('server_session_id') != inspected['server_session_id']:
        fail('GUEST_IDENTITY', '个人 guest 清单与玩家凭据不是同一玩家或同一服务器会话。')
    endpoint = guest.get('guest', {})
    for key in ('mc_ws_port', 'hud_port', 'mc_server_port'):
        if type(endpoint.get(key)) is not int or not 1024 <= endpoint[key] <= 65535:
            fail('GUEST_PORT', '个人 guest 清单缺少有效端口：' + key)
    if endpoint['mc_ws_port'] == endpoint['hud_port']:
        fail('GUEST_PORT', '个人 MCWS 和 HUD 端口不能相同。')
    frame = endpoint.get('frame_mapping', '')
    if frame != 'Local\\MCPassthroughFrame-' + inspected['identity']['mc_uuid']:
        fail('GUEST_FRAME', 'HUD 共享内存映射与个人 UUID 不一致。')
    profile = json.loads(json.dumps(profile))
    if guest.get('world_origin') is not None:
        profile['connection']['world_origin'] = guest['world_origin']
    connection = profile['connection']
    connection.update(mode='strict-player', identity=inspected['identity'], server_session_id=inspected['server_session_id'],
                      credential_path=str(root / CREDENTIAL_REL), frame_mapping=frame,
                      guest_manifest_sha256=__import__('hashlib').sha256(Path(guest_manifest_path).read_bytes()).hexdigest())
    connection['remote_ports'].update(mc_ws=endpoint['mc_ws_port'], hud=endpoint['hud_port'], mc_server=endpoint['mc_server_port'])
    profile = validate_profile(profile, root)
    return profile, inspected


def import_credential(root, credential_path, guest_manifest_path, dry_run=False):
    root = Path(root).absolute()
    state = get_state(root)
    profile, inspected = prepare_credential_profile(state['profile'], root, credential_path, guest_manifest_path)
    frame = profile['connection']['frame_mapping']
    result = {'ok': True, 'dry_run': dry_run, **inspected, 'credential_destination': str(root / CREDENTIAL_REL),
              'frame_mapping': frame, 'secrets_displayed': False}
    if dry_run:
        return result
    with operation_lock(root):
        ensure_no_session(root)
        target = owned_path(root, CREDENTIAL_REL)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.parent.chmod(0o700)
        temp = target.with_name('credential-' + uuid.uuid4().hex + '.tmp')
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(Path(credential_path).read_bytes())
                stream.flush(); os.fsync(stream.fileno())
            os.replace(temp, target)
            if os.name != 'nt':
                target.chmod(0o600)
        finally:
            temp.unlink(missing_ok=True)
    # configure() takes its own lock after credential publication; no secret is copied into install journals.
    configure(root, profile)
    return result
