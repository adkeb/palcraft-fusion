import asyncio
import base64
import hashlib
import importlib.util
import json
import os
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path

BASE = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BASE))
from launcher.session_proxy import SessionProxy
from launcher.websocket_wire import TextSocket
from installer.credentials import inspect_credential, import_credential
from installer.core import DEV, TOOLS, PlayerError, atomic_json, get_state
import test_player_tools as fixtures

protocol_spec = importlib.util.spec_from_file_location('session_protocol_tests', BASE / 'multiplayer/session_client.py')
protocol = importlib.util.module_from_spec(protocol_spec)
protocol_spec.loader.exec_module(protocol)


def b64(data):
    return base64.urlsafe_b64encode(data).decode().rstrip('=')


def credential(name='FixturePlayer'):
    offline = bytearray(hashlib.md5(('OfflinePlayer:' + name).encode()).digest())
    offline[6], offline[8] = (offline[6] & 15) | 48, (offline[8] & 63) | 128
    identity = {'world_id': 'fixture-world', 'pal_uid': str(uuid.uuid4()),
                'mc_uuid': str(uuid.UUID(bytes=bytes(offline))), 'mc_name': name}
    now = int(time.time())
    grant = {**identity, 'v': 2, 'server_session_id': 'fixture-pal-boot', 'credential_id': str(uuid.uuid4()),
             'issued_at': now - 2, 'expires_at': now + 3600, 'holder_public': b64(b'fixture-public-key'),
             'scopes': ['mc.login', 'pose', 'input', 'gui', 'inventory', 'world.read', 'terrain']}
    # No claim of authority signature verification: this test uses fake issuer bytes and a fake pinned guest.
    return {'v': 2, 'grant': b64(json.dumps(grant).encode()) + '.' + b64(b'X' * 64),
            'holder_private': b64(b'FAKE_PRIVATE_KEY_DO_NOT_PACKAGE'), 'host_secret': b64(os.urandom(32)),
            'identity': identity, 'server_session_id': grant['server_session_id'], 'expires_at': grant['expires_at']}


class CredentialTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.PlayerTests(methodName='test_dry_run_has_no_files_or_network_or_processes')
        self.fixture.setUp()
        self.fixture.installed()
        self.value = credential()
        self.path = self.fixture.base / 'operator-credential.json'
        atomic_json(self.path, self.value)
        identity = self.value['identity']
        self.guest = {'schema': 1, 'kind': 'palcraft_guest', 'identity': identity,
                      'server_session_id': self.value['server_session_id'],
                      'guest': {'mc_ws_port': 29401, 'hud_port': 29402, 'mc_server_port': 25567,
                                'frame_mapping': 'Local\\MCPassthroughFrame-' + identity['mc_uuid']},
                      'world_origin': {'X': 400, 'Y': 500, 'Z': 600}}
        self.guest_path = self.fixture.base / 'guest.json'
        atomic_json(self.guest_path, self.guest)

    def tearDown(self):
        self.fixture.tearDown()

    def test_import_local_secrets_permission_without_signature_claim(self):
        preview = import_credential(self.fixture.root, self.path, self.guest_path, dry_run=True)
        target = self.fixture.root / '.palcraft/credentials/credential.json'
        self.assertFalse(target.exists())
        self.assertFalse(preview['signature_verified_locally'])
        result = import_credential(self.fixture.root, self.path, self.guest_path)
        self.assertEqual(target.read_bytes(), self.path.read_bytes())
        if os.name != 'nt':
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
        state = get_state(self.fixture.root)
        self.assertEqual(state['profile']['connection']['mode'], 'strict-player')
        self.assertEqual(state['profile']['connection']['remote_ports']['mc_ws'], 29401)
        self.assertEqual(state['profile']['connection']['world_origin']['X'], 400)
        self.assertNotIn(self.value['host_secret'], json.dumps(result))
        self.assertNotIn(self.value['holder_private'], json.dumps(state))

    def test_other_player_guest_manifest_rejected_without_writes(self):
        self.guest['identity'] = credential('AnotherPlayer')['identity']
        atomic_json(self.guest_path, self.guest)
        with self.assertRaises(PlayerError) as error:
            import_credential(self.fixture.root, self.path, self.guest_path)
        self.assertEqual(error.exception.code, 'GUEST_IDENTITY')
        self.assertFalse((self.fixture.root / '.palcraft/credentials').exists())

    def test_expired_certificate_does_not_bind(self):
        with self.assertRaises(PlayerError) as error:
            inspect_credential(self.path, now=self.value['expires_at'] + 1)
        self.assertEqual(error.exception.code, 'CREDENTIAL_EXPIRED')


class ProxyTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='palcraft-auth-proxy-test-')
        self.root = Path(self.temp.name).resolve()
        self.credential = credential()
        self.received = asyncio.Queue()
        self.disconnected = asyncio.Event()
        self.error = None
        self.guest_wires = set()
        self.native_wires = []
        self.guest_tasks = set()
        self.variant = 'normal'
        self.server = await asyncio.start_server(self.guest_handler, '127.0.0.1', 0)
        upstream = self.server.sockets[0].getsockname()[1]
        self.proxy = SessionProxy(self.credential, protocol, self.root / 'status.json', upstream, 0)
        self.proxy_server = await asyncio.start_server(self.proxy.handle, '127.0.0.1', 0, limit=16384)
        self.port = self.proxy_server.sockets[0].getsockname()[1]

    async def asyncTearDown(self):
        for wire in self.native_wires:
            await wire.close()
        for task in list(self.proxy.tasks):
            task.cancel()
        if self.proxy.tasks:
            await asyncio.gather(*self.proxy.tasks, return_exceptions=True)
        for task in list(self.guest_tasks):
            task.cancel()
        if self.guest_tasks:
            await asyncio.gather(*self.guest_tasks, return_exceptions=True)
        self.proxy_server.close(); await self.proxy_server.wait_closed()
        self.server.close(); await self.server.wait_closed()
        self.temp.cleanup()

    async def guest_handler(self, reader, writer):
        task = asyncio.current_task()
        self.guest_tasks.add(task)
        wire = None
        try:
            wire = await TextSocket.accept(reader, writer)
            self.guest_wires.add(wire)
            grant = protocol.inspect_grant(self.credential['grant'])
            challenge = {'t': 'challenge', 'v': 2, 'purpose': 'host.bind', 'nonce': b64(os.urandom(32)),
                         'endpoint': 'host:fixture:29401', 'world_id': grant['world_id'],
                         'server_session_id': grant['server_session_id'], 'mc_uuid': grant['mc_uuid']}
            hello = {'t': 'hello', 'v': 2, 'legacy': False, 'identity': grant['identity'],
                     'challenge': challenge, 'shm': 'Local\\MCPassthroughFrame-' + grant['mc_uuid'], 'pid': 123}
            if self.variant == 'wrong-identity':
                hello['identity'] = credential('OtherPlayer')['identity']
            await wire.send(json.dumps(hello))
            answer = json.loads(await wire.receive())
            if answer != protocol.host_answer(self.credential, hello):
                raise AssertionError('wrong host HMAC answer')
            scope = {**grant['identity'], 'v': 2, 'server_session_id': grant['server_session_id'],
                     'session_id': str(uuid.uuid4()), 'generation': 3, 'expires_at': grant['expires_at'], 'legacy': False}
            await wire.send(json.dumps({'t': 'bound', 'session': scope}))
            while True:
                message = json.loads(await wire.receive())
                await self.received.put(message)
                response_scope = dict(scope)
                if self.variant == 'stale-generation':
                    response_scope['generation'] = 2
                if self.variant == 'other-player-event':
                    response_scope['pal_uid'] = str(uuid.uuid4())
                if message['t'] != 'session_ping':
                    await wire.send(json.dumps({'t': 'blockpatch', 'session': 'raw-world-session',
                                                'fixture': 'normal-world-payload', 'host_session': response_scope}))
        except (EOFError, asyncio.IncompleteReadError, ConnectionError, asyncio.CancelledError):
            pass
        except Exception as exc:
            self.error = exc
        finally:
            self.disconnected.set()
            if wire:
                self.guest_wires.discard(wire)
                await wire.close()
            self.guest_tasks.discard(task)

    async def native(self):
        wire = await TextSocket.connect(self.port)
        self.native_wires.append(wire)
        return wire

    async def test_hmac_bind_scopes_camera_and_preserves_world_session(self):
        wire = await self.native()
        hello = json.loads(await asyncio.wait_for(wire.receive(), 2))
        self.assertEqual(hello['t'], 'hello')
        await wire.send(json.dumps({'t': 'cam', 'x': 10, 'y': 64, 'z': 20}))
        sent = await asyncio.wait_for(self.received.get(), 2)
        self.assertEqual(sent['session']['pal_uid'], self.credential['identity']['pal_uid'])
        self.assertEqual(sent['session']['generation'], 3)
        self.assertEqual(sent['seq'], 1)
        result = json.loads(await asyncio.wait_for(wire.receive(), 2))
        self.assertEqual(result['session'], 'raw-world-session')
        self.assertNotIn('host_session', result)
        state = json.loads((self.root / 'status.json').read_text())
        self.assertTrue(state['authenticated_host'])
        self.assertIsNone(state['mc_epoch'])
        self.assertFalse(state['mc_epoch_verified'])
        self.assertNotIn(self.credential['host_secret'], json.dumps(state))
        self.assertIsNone(self.error)

    async def test_stale_generation_event_closes_without_forwarding(self):
        self.variant = 'stale-generation'
        wire = await self.native()
        await wire.receive()
        await wire.send(json.dumps({'t': 'mode', 'build': True}))
        with self.assertRaises((EOFError, asyncio.IncompleteReadError)):
            await asyncio.wait_for(wire.receive(), 2)
        self.assertFalse(json.loads((self.root / 'status.json').read_text())['authenticated_host'])
        await asyncio.wait_for(self.disconnected.wait(), 2)

    async def test_other_player_event_closes_without_forwarding(self):
        self.variant = 'other-player-event'
        wire = await self.native()
        await wire.receive()
        await wire.send(json.dumps({'t': 'inspect'}))
        with self.assertRaises((EOFError, asyncio.IncompleteReadError)):
            await asyncio.wait_for(wire.receive(), 2)

    async def test_wrong_guest_identity_never_sends_camera(self):
        self.variant = 'wrong-identity'
        wire = await self.native()
        with self.assertRaises((EOFError, asyncio.IncompleteReadError)):
            await asyncio.wait_for(wire.receive(), 2)
        self.assertTrue(self.received.empty())
        self.assertEqual(json.loads((self.root / 'status.json').read_text())['state'], 'error')

    async def test_admin_commands_are_rejected(self):
        wire = await self.native()
        await wire.receive()
        await wire.send(json.dumps({'t': 'cmd', 'c': 'give @s diamond 64'}))
        with self.assertRaises((EOFError, asyncio.IncompleteReadError)):
            await asyncio.wait_for(wire.receive(), 2)
        self.assertTrue(self.received.empty())

    async def test_disconnect_releases_host_and_clears_fresh_bound(self):
        wire = await self.native()
        await wire.receive()
        await wire.close()
        await asyncio.wait_for(self.disconnected.wait(), 2)
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline and json.loads((self.root / 'status.json').read_text())['authenticated_host']:
            await asyncio.sleep(.02)
        self.assertFalse(json.loads((self.root / 'status.json').read_text())['authenticated_host'])

    async def test_second_controller_cannot_steal_bound_session(self):
        first = await self.native()
        await first.receive()
        with self.assertRaises((EOFError, asyncio.IncompleteReadError, ConnectionError)):
            await self.native()
        await first.send(json.dumps({'t': 'cam', 'x': 1}))
        self.assertEqual((await asyncio.wait_for(self.received.get(), 2))['t'], 'cam')
        self.assertTrue(json.loads((self.root / 'status.json').read_text())['authenticated_host'])
