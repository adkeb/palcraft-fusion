"""The one local auth proxy. Protocol identity/proofs come from multiplayer/session_client.py."""
import asyncio
import importlib.util
import json
import logging
import signal
import time
from pathlib import Path

from installer.core import DEV, atomic_json, fail, get_state, owned_path, validate_profile
from launcher.runtime import executable_role
from launcher.websocket_wire import TextSocket, WireError
from launcher.native_bootstrap import NativeBootstrap

LOG = logging.getLogger('palcraft.session')
PLAYER_OPERATIONS = {'cam', 'host_pose', 'world_view_ack', 'key', 'mode', 'slot', 'scroll', 'inventory_toggle',
                     'pointer', 'wheel', 'gui_key', 'text', 'hud', 'view', 'inspect', 'blockinspect', 'blocksync',
                     'worldcompat_status', 'ground', 'exchange', 'exchange_balance', 'session_ping',
                     'travel_ready', 'travel_observed', 'travel_abort', 'material_tint_query', 'entity_visual_view'}
SAFE_SESSION_ERRORS = {
    'MC guest is waiting for its verified shared-world connection': 'guest_not_ready',
    'Certificate is not assigned to this guest': 'wrong_guest_certificate',
    'Guest credential unavailable': 'guest_credential_unavailable',
    'A guest process cannot change its MC profile': 'guest_identity_changed',
    'Challenge expired': 'challenge_expired',
    'Unsupported session protocol': 'unsupported_protocol',
    'Identity does not match connection': 'challenge_identity_mismatch',
    'Invalid holder proof': 'invalid_holder_proof',
    'Login scope missing': 'login_scope_missing',
    'Player already has an active connection': 'controller_already_active',
    'Wrong authentication purpose': 'wrong_authentication_purpose',
    'Invalid local host proof': 'invalid_host_hmac',
    'Another connection controls this guest': 'controller_already_active',
    'Session is detached or expired': 'lease_detached_or_expired',
    'Operation is not allowed in this session': 'operation_scope_denied',
    'Wrong session/player scope': 'wrong_session_player_scope',
    'Invalid sequence': 'invalid_sequence',
    'Replayed or reordered message': 'replayed_or_reordered_message',
    'Already bound': 'already_bound',
}


def safe_session_error(message, phase, operation=None):
    raw = message.get('error')
    code = SAFE_SESSION_ERRORS.get(raw, 'unrecognized_remote_session_error') if isinstance(raw, str) else 'missing_remote_session_error'
    result = {'code': code, 'phase': phase, 'operation': operation if operation in PLAYER_OPERATIONS else None}
    if isinstance(raw, str) and raw in SAFE_SESSION_ERRORS:
        result['reason'] = raw
    return result


def protocol_from_release(root):
    state = get_state(root)
    path = executable_role(root, state, 'session_client')
    spec = importlib.util.spec_from_file_location('palcraft_multiplayer_session_client', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sign_receiver_from_path(path):
    """Load the next candidate's approved stdlib receiver, never create a transport."""
    spec = importlib.util.spec_from_file_location('palcraft_private_sign_receiver', Path(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.SignTextReceiver


class SessionProxy:
    def __init__(self, credential, protocol, status_path, upstream_port=25598, listen_port=25599, sign_receiver_factory=None):
        self.credential, self.protocol = credential, protocol
        self.status_path = Path(status_path)
        self.upstream_port, self.listen_port = upstream_port, listen_port
        self.active = False
        self.clients = set()
        self.tasks = set()
        self.public = protocol.inspect_grant(credential['grant'])
        self.latest_rejection, self.last_operation = None, None
        self.sign_receiver_factory = sign_receiver_factory
        self.sign_receiver_scope = None
        self.bootstrap = NativeBootstrap(self.status_path.parent / 'mc-bootstrap-status.json', self.public)

    def note_session_error(self, message, phase):
        self.latest_rejection = safe_session_error(message, phase, self.last_operation)
        LOG.warning('PROXY_SESSION_REJECTED %s', json.dumps(self.latest_rejection, ensure_ascii=False))

    def write_status(self, state, lease=None, code=None):
        scope = lease.session if lease is not None and lease.session else {}
        value = {'schema': 1, 'protocol': 2, 'state': state, 'identity': self.public['identity'],
                 'server_session_id': self.public['server_session_id'], 'session_id': scope.get('session_id'),
                 'generation': scope.get('generation'), 'expires_at': self.public['expires_at'],
                 'authenticated_host': state == 'bound', 'updated_unix': time.time(), 'code': code,
                 'mc_epoch': None, 'mc_epoch_verified': False,
                 'grant_signature_verified_locally': False}
        if self.latest_rejection is not None:
            value['last_session_rejection'] = self.latest_rejection
            if state == 'error' and code == 'PROXY_SESSION_REJECTED':
                value['session_error'] = self.latest_rejection
        if state == 'bound' and self.sign_receiver_scope == (scope.get('session_id'), scope.get('generation')):
            value['sign_text_receiver'] = {'version': 1, 'installed': True}
        if state != 'bound':
            self.sign_receiver_scope = None
        atomic_json(self.status_path, value)
        if state == 'bound' and lease is not None:
            self.bootstrap.heartbeat(lease)
        else:
            self.bootstrap.unbound(code or state)
        if state != 'bound':
            self.mark_mirrors_stale()

    def mirror_event(self, message, lease):
        """Only messages already accepted by HostSession.receive reach this method."""
        kind = message.get('t')
        names = {'pal_entity_snapshot': ('pal-state.json', 'pal_server'),
                 'entity_snapshot': ('mc-state.json', 'mc_server'),
                 'player_vitals': ('player-vitals.json', 'pal_server')}
        if kind not in names:
            return
        filename, authority = names[kind]
        if message.get('authority') != authority or message.get('v') != 1 or message.get('session') != self.public['server_session_id']:
            raise ValueError('PROXY_SNAPSHOT_AUTHORITY')
        if kind == 'player_vitals' and message.get('mc_uuid') != self.public['identity']['mc_uuid']:
            raise ValueError('PROXY_VITALS_IDENTITY')
        if len(json.dumps(message).encode('utf-8')) > 1024 * 1024:
            raise ValueError('PROXY_SNAPSHOT_TOO_LARGE')
        relative = filename if kind == 'player_vitals' else 'entities/' + filename
        target = owned_path(self.status_path.parent, relative)
        local = dict(message)
        if kind == 'pal_entity_snapshot':
            local['t'] = 'entity_snapshot'
        atomic_json(target, local)
        atomic_json(owned_path(self.status_path.parent, 'entities/binding-meta.json'),
                    {'schema': 1, 'state': 'bound', 'stale': False, 'updated_unix': time.time(),
                     'identity': self.public['identity'], 'server_session_id': self.public['server_session_id'],
                     'host_session_id': lease.session['session_id'], 'generation': lease.session['generation']})

    def mirror_travel(self, message):
        """Relay an accepted server travel row to this client's local journal."""
        if message.get('t') != 'travel':
            return
        identity = self.public['identity']
        if (message.get('v') != 1 or message.get('player') != identity['mc_uuid'] or
                message.get('pal_uid') != identity['pal_uid'] or message.get('world_id') != identity['world_id'] or
                message.get('server_session_id') != self.public['server_session_id']):
            raise ValueError('PROXY_TRAVEL_IDENTITY')
        raw = (json.dumps(message, ensure_ascii=False, separators=(',', ':')) + '\n').encode('utf-8')
        if len(raw) > 1024 * 1024:
            raise ValueError('PROXY_TRAVEL_TOO_LARGE')
        target = owned_path(self.status_path.parent, 'travel-events.ndjson')
        # Keep the authority's MC session/view fields intact. The client travel
        # replica validates them; HOST generation is a separate outer envelope.
        # Append across reconnects so an existing tail never sees truncation.
        with target.open('ab') as journal:
            journal.write(raw)

    def mark_mirrors_stale(self):
        for name, authority in (('pal-state.json', 'pal_server'), ('mc-state.json', 'mc_server')):
            path = owned_path(self.status_path.parent, 'entities/' + name)
            if path.exists():
                atomic_json(path, {'t': 'entity_snapshot', 'v': 1, 'authority': authority,
                                  'session': self.public['server_session_id'], 'unix': 0, 'stale': True, 'entities': []})
        meta = owned_path(self.status_path.parent, 'entities/binding-meta.json')
        if meta.exists():
            atomic_json(meta, {'schema': 1, 'state': 'unbound', 'stale': True, 'updated_unix': time.time()})
        vitals = owned_path(self.status_path.parent, 'player-vitals.json')
        if vitals.exists():
            atomic_json(vitals, {'v': 1, 't': 'player_vitals', 'unix': 0, 'stale': True})

    async def handle(self, reader, writer):
        task = asyncio.current_task()
        self.tasks.add(task)
        native, upstream, lease = None, None, None
        sub_tasks = []
        acquired = False
        sign_receiver = None
        try:
            peer = writer.get_extra_info('peername')
            if not peer or peer[0] != '127.0.0.1' or self.active:
                raise WireError('PROXY_CONTROLLER_BUSY')
            self.active, acquired = True, True
            native = await TextSocket.accept(reader, writer)
            self.clients.add(native)
            self.write_status('binding')
            upstream = await TextSocket.connect(self.upstream_port)
            hello = json.loads(await asyncio.wait_for(upstream.receive(), 5))
            if hello.get('t') != 'hello' or hello.get('v') != 2 or hello.get('legacy') is not False or hello.get('identity') != self.public['identity']:
                raise ValueError('PROXY_GUEST_IDENTITY')
            answer = self.protocol.host_answer(self.credential, hello)
            await upstream.send(json.dumps(answer, separators=(',', ':')))
            lease = self.protocol.HostSession(self.credential)
            bound = json.loads(await asyncio.wait_for(upstream.receive(), 5))
            if bound.get('t') == 'session_error':
                self.note_session_error(bound, 'bind')
                raise ValueError('PROXY_SESSION_REJECTED')
            lease.bound(bound)
            self.bootstrap.bound(lease)
            if type(lease.session.get('generation')) is not int or lease.session['generation'] <= 0:
                raise ValueError('PROXY_GENERATION')
            if self.sign_receiver_factory is not None:
                sign_receiver = self.sign_receiver_factory(owned_path(self.status_path.parent, 'sign-text-v1'), self.public['identity'])
                self.sign_receiver_scope = (lease.session['session_id'], lease.session['generation'])
            self.write_status('bound', lease)
            # Legacy native consumes a hello but never sees private credentials or authentication objects.
            await native.send(json.dumps({'t': 'hello', 'v': 2, 'legacy': False, 'shm': hello.get('shm'), 'pid': hello.get('pid')}))
            upstream_lock = asyncio.Lock()

            async def send_scoped(message):
                async with upstream_lock:
                    self.last_operation = message.get('t')
                    await upstream.send(json.dumps(lease.stamp(message), separators=(',', ':')))

            async def to_guest():
                while True:
                    message = json.loads(await native.receive())
                    allowed_operation = isinstance(message, dict) and (message.get('t') in PLAYER_OPERATIONS or
                                         message.get('t') == 'sign_text_view' and sign_receiver is not None)
                    if not allowed_operation:
                        raise ValueError('PROXY_OPERATION_DENIED')
                    if message.get('t') == 'sign_text_view':
                        # The unchanged genuine native request is the only fence source.
                        sign_receiver.bind(message)
                    await send_scoped(message)

            async def to_native():
                while True:
                    message = json.loads(await upstream.receive())
                    clean = lease.receive(message)
                    if clean.get('t') in ('entity_visual_asset', 'entity_visual_cache', 'entity_visual_cache_chunk'):
                        # The native cache needs this exact envelope, already checked above.
                        clean['host_session'] = message['host_session']
                    self.bootstrap.message(clean, lease)
                    # Host rebind metadata updates the mailbox, not the sequenced world reducer.
                    replay = clean.get('lifecycle')
                    if (clean.get('t') == 'blocks' and clean.get('v') == 2 and
                            'seq' not in clean and 'tick' not in clean and
                            isinstance(clean.get('native_binding'), dict) and isinstance(clean.get('world_view'), dict) and
                            isinstance(replay, list) and len(replay) == 1 and isinstance(replay[0], dict) and
                            replay[0].get('op') == 'player_view' and replay[0].get('reason') == 'host_rebind' and
                            replay[0].get('player') == clean['world_view']['player'] and
                            replay[0].get('to') == clean['world_view']['dim'] and
                            replay[0].get('view') == clean['world_view']['view'] and
                            replay[0].get('waiting_ack') == clean['world_view']['waiting_ack'] and
                            clean.get('session') == clean['world_view']['world_session'] and
                            clean.get('dim') == clean['world_view']['dim'] and
                            all(clean.get(key) == [] for key in ('set', 'clear', 'geometry'))):
                        continue
                    if clean.get('t') == 'session_error':
                        self.note_session_error(clean, 'bound')
                        raise ValueError('PROXY_SESSION_REJECTED')
                    if clean.get('t') in ('sign_text_asset', 'sign_text_snapshot'):
                        if sign_receiver is not None:
                            sign_receiver.receive(clean)
                            request = sign_receiver.retry_request()
                            if request is not None:
                                await send_scoped(request)
                        # Private glyph payloads never enter native's general input queue.
                        continue
                    self.mirror_event(clean, lease)
                    self.mirror_travel(clean)
                    await native.send(json.dumps(clean, separators=(',', ':')))

            async def heartbeat():
                while True:
                    await asyncio.sleep(2)
                    if time.time() >= self.public['expires_at']:
                        raise ValueError('PROXY_CREDENTIAL_EXPIRED')
                    await send_scoped({'t': 'session_ping'})
                    if sign_receiver is not None:
                        request = sign_receiver.retry_request()
                        if request is not None:
                            await send_scoped(request)
                    self.write_status('bound', lease)

            sub_tasks = [asyncio.create_task(to_guest()), asyncio.create_task(to_native()), asyncio.create_task(heartbeat())]
            done, _ = await asyncio.wait(sub_tasks, return_when=asyncio.FIRST_COMPLETED)
            for finished in done:
                finished.result()
        except asyncio.CancelledError:
            if acquired:
                self.write_status('unbound', code='PROXY_STOPPED')
        except (EOFError, asyncio.IncompleteReadError):
            if acquired:
                self.write_status('unbound', code='PROXY_DISCONNECTED')
        except (OSError, asyncio.TimeoutError, WireError, ValueError, KeyError, TypeError) as exc:
            # Do not log raw server messages, credential JSON or identities.
            known = {'PROXY_CONTROLLER_BUSY', 'PROXY_GUEST_IDENTITY', 'PROXY_GENERATION', 'PROXY_OPERATION_DENIED',
                     'PROXY_SESSION_REJECTED', 'PROXY_CREDENTIAL_EXPIRED', 'PROXY_SNAPSHOT_AUTHORITY',
                     'PROXY_VITALS_IDENTITY', 'PROXY_SNAPSHOT_TOO_LARGE'}
            code = str(exc) if isinstance(exc, WireError) or str(exc) in known else 'PROXY_BIND_OR_CONNECTION_FAILED'
            LOG.warning('%s: 个人认证连接已关闭；不会降级到旧协议。', code)
            if acquired:
                self.write_status('error', code=code)
        finally:
            for child in sub_tasks:
                child.cancel()
            if sub_tasks:
                await asyncio.gather(*sub_tasks, return_exceptions=True)
            if lease:
                lease.disconnected()
            if sign_receiver is not None:
                sign_receiver.close()
            # Closing upstream causes the Java owner to release this lease's keys/mode/GUI.
            for connection in (upstream, native):
                if connection:
                    await connection.close()
            if native:
                self.clients.discard(native)
            else:
                writer.close()
            if acquired:
                self.mark_mirrors_stale()
                self.active = False
                existing = json.loads(self.status_path.read_text())
                if existing.get('state') != 'error':
                    self.write_status('unbound')
            self.tasks.discard(task)

    async def serve(self, stop_event):
        self.write_status('idle')
        server = await asyncio.start_server(self.handle, '127.0.0.1', self.listen_port, limit=16384)
        try:
            async with server:
                await stop_event.wait()
        finally:
            for task in list(self.tasks):
                task.cancel()
            if self.tasks:
                await asyncio.gather(*self.tasks, return_exceptions=True)
            self.write_status('unbound', code='PROXY_STOPPED')
            self.mark_mirrors_stale()


async def run(root, token):
    root = Path(root).absolute()
    state = get_state(root)
    profile = validate_profile(state['profile'], root)
    current = json.loads(owned_path(root, '.palcraft/session.json').read_text())
    if current.get('token') != token or state['profile']['connection'].get('mode') != 'strict-player':
        fail('PROXY_SESSION', '严格代理需要当前个人会话与玩家凭据。')
    protocol = protocol_from_release(root)
    credential = protocol.load_credential(profile['connection']['credential_path'])
    receiver_factory = None
    if state['manifest'].get('requirements', {}).get('sign_text_transport_enabled') is True:
        receiver_factory = sign_receiver_from_path(executable_role(root, state, 'sign_text_receiver'))
    proxy = SessionProxy(credential, protocol, owned_path(root, DEV + '/bridge/session-bind-status.json'),
                         upstream_port=profile['proxy_upstream_port'], listen_port=profile['local_ports']['mc_ws'],
                         sign_receiver_factory=receiver_factory)
    event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for signum in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(signum, event.set)
        except NotImplementedError:
            pass
    await proxy.serve(event)
