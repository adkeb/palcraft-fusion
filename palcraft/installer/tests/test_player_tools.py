import asyncio
import hashlib
import importlib.util
import json
import os
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
import zipfile
from pathlib import Path

BASE = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BASE))
from installer.core import (BIN, CLIENT, DEV, TOOLS, USER, Bundle, PlayerError, atomic_json,
                            configure, digest, get_state, install, recover_transactions,
                            rollback, uninstall, update, validate_profile)
from installer.packaging import build_release
from launcher.runtime import (Session, _port_free, create_bottle, diagnostics, health,
                              process_identity, recover_session, start, status, stop)
from launcher.udp_tunnel_player import LocalRelay


FAKE = '''import json,os,signal,sys,time
from pathlib import Path
name,root,token,behavior=sys.argv[1:]
root=Path(root)
trace=root/'.palcraft/fake-trace.txt'
def event(value):
 with trace.open('a') as f:f.write(name+' '+value+'\\n')
def close(*args):
 event('stopped');raise SystemExit(0)
signal.signal(signal.SIGTERM,close)
event('started')
if behavior=='fail':raise SystemExit(9)
started=time.time()
while True:
 if name=='client':
  request=root/'.palcraft/control'/(token+'.stop')
  heartbeat=root/'.palcraft/control'/(token+'.heartbeat')
  mode=request.read_text() if request.exists() else ''
  if mode.startswith('force') or (mode.startswith('close') and behavior!='refuse'):
   event('closed');break
  if heartbeat.exists() and time.time()-heartbeat.stat().st_mtime>2:
   event('owner_gone');break
 elif behavior=='delayed-fail' and time.time()-started>1.5:
  raise SystemExit(7)
 time.sleep(.05)
'''


class PlayerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='palcraft-player-test-')
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / 'drive_d/PalworldServer-LAN'
        self.source = self.base / 'owned-game'
        for name, data in [('Palworld.exe', b'owned-launcher'), ('Pal/Binaries/Win64/Palworld-Win64-Shipping.exe', b'owned-shipping'),
                           ('Pal/Content/Paks/base.pak', b'owned-pak'), ('Pal/Saved/SaveGames/private.sav', b'SOURCE_SAVE'),
                           ('Pal/Binaries/Win64/ue4ss/Mods/Old/main.lua', b'OLD_MOD'), ('Pal/Binaries/Win64/dwmapi.dll', b'OLD_INJECTION')]:
            p = self.source / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
        self.app = self.base / 'apps/CrossOver.app'
        binaries = self.app / 'Contents/SharedSupport/CrossOver/bin'
        binaries.mkdir(parents=True)
        for name in ('cxbottle', 'wine'):
            p = binaries / name
            p.write_text('fixture only')
        self.bottle = self.base / 'bottles/PalCraft-Player-Fixture'
        self.profile = {'schema': 1, 'platform': 'crossover', 'bottle_name': self.bottle.name,
                        'bottle_root': str(self.bottle), 'crossover_app': str(self.app), 'mute': True, 'fps': 60,
                        'connection': {'ssh_target': 'test-bridge', 'server_session_id': 'PRIVATE_SESSION_MARKER',
                                       'world_origin': {'X': 100, 'Y': 200, 'Z': 300},
                                       'remote_ports': {'udp_tcp': 18321, 'mc_ws': 29001, 'mc_server': 25567, 'hud': 29002},
                                       'identity': {'pal_uid': 'PAL_PRIVATE', 'mc_uuid': str(uuid.uuid4()), 'mc_name': 'PrivateName', 'world_id': 'private-world'}}}
        self.payload = self.base / 'approved-payload'
        self.payload.mkdir()
        self.processes = []
        self.release1 = self.release('v1')

    def tearDown(self):
        # Only handles explicitly created by a test are touched.
        for p in self.processes:
            if p.poll() is None:
                p.terminate()
                try:
                    p.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    p.kill(); p.wait()
        self.temp.cleanup()

    def release(self, version):
        entries = []
        mapping = {'client_main': BIN + 'ue4ss/Mods/PalCraftClient/Scripts/main.lua',
                   'json_lua': BIN + 'ue4ss/Mods/PalCraftClient/Scripts/json.lua',
                   'runtime_paths': BIN + 'ue4ss/Mods/PalCraftClient/Scripts/runtime/paths.lua',
                   'collisions_lua': BIN + 'ue4ss/Mods/PalCraftClient/Scripts/palcraft-collisions.lua',
                   'models_lua': BIN + 'ue4ss/Mods/PalCraftClient/Scripts/models.lua',
                   'ue4ss': BIN + 'ue4ss/UE4SS.dll', 'proxy_dll': BIN + 'dwmapi.dll',
                   'native_render': BIN + 'PalCraftRender.dll', 'native_mesh': BIN + 'PalCraftMesh.dll',
                   'native_model': BIN + 'PalCraftModel.dll', 'client_host': TOOLS + '/bin/PalCraftClientHost-v1.exe',
                   'mac_hud': TOOLS + '/bin/hud-overlay-player', 'model_processor': TOOLS + '/assets/prepare_models_v2.py',
                   'ue4ss_settings': BIN + 'ue4ss/UE4SS-settings.ini', 'license': TOOLS + '/licenses/fixture.txt'}
        # Extensionless executable is deliberately supported only for the mac_hud role target.
        mapping['mac_hud'] = TOOLS + '/bin/hud-overlay-player.command'
        for role, target in mapping.items():
            source = self.payload / (version + '-' + role + '.bin')
            data = (version + '-' + role).encode()
            if role == 'ue4ss_settings':
                data = b'[General]\nEnableHotReloadSystem = 0\nEnableAutoReloadingLuaMods = 0\n'
            source.write_bytes(data)
            entries.append({'source': str(source), 'target': target, 'role': role, 'executable': role == 'mac_hud'})
        spec = {'version': version, 'platform': 'crossover', 'source_revision': 'fixture-' + version,
                'requirements': {'palworld_shipping_sha256': [digest(self.source / 'Pal/Binaries/Win64/Palworld-Win64-Shipping.exe')],
                                 'minecraft_version': '26.3', 'path_contract': 'windows-root-v1', 'lua_path_encoding': 'utf-8-win32-v1'}, 'licenses': [{'component': 'fixture', 'license': 'fixture-only', 'notice_target': mapping['license']}],
                'files': entries}
        spec_path = self.base / (version + '-spec.json')
        atomic_json(spec_path, spec)
        output = self.base / (version + '.zip')
        build_release(spec_path, output)
        return output

    def installed(self):
        install(self.root, self.source, self.release1, self.profile)
        return get_state(self.root)

    def make_fake_session(self, client='normal', ssh='normal', hud='normal'):
        self.installed()
        token = uuid.uuid4().hex
        atomic_json(self.root / '.palcraft/session.json', {'schema': 1, 'token': token, 'phase': 'starting', 'components': {}})
        fake = self.base / 'fake.py'
        fake.write_text(FAKE)
        commands = {name: [sys.executable, str(fake), name, str(self.root), token, behavior]
                    for name, behavior in [('client', client), ('ssh', ssh), ('udp', 'normal'), ('hud', hud)]}
        driver = self.base / 'driver.py'
        driver.write_text('import sys\nfrom pathlib import Path\nsys.path.insert(0,' + repr(str(BASE)) + ')\n'
                          'from launcher.runtime import Session\n'
                          + ('def probe(*a,**kw):raise OSError("fixture unavailable")\n' if ssh == 'fail' else 'def probe(*a,**kw):return True\n') +
                          'Session(' + repr(str(self.root)) + ',' + repr(token) + ',' + repr(commands) + ',probe=probe).run()\n')
        p = subprocess.Popen([sys.executable, str(driver)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.processes.append(p)
        return p, token

    def wait_phase(self, phases, timeout=6):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = json.loads((self.root / '.palcraft/session.json').read_text())
            if value['phase'] in phases:
                return value
            time.sleep(.05)
        self.fail('session did not reach ' + repr(phases) + ': ' + (self.root / '.palcraft/session.json').read_text())

    def expect_code(self, code, fn):
        with self.assertRaises(PlayerError) as err:
            fn()
        self.assertEqual(err.exception.code, code)

    def test_dry_run_has_no_files_or_network_or_processes(self):
        result = install(self.root, self.source, self.release1, self.profile, dry_run=True)
        self.assertTrue(result['dry_run'])
        self.assertFalse(self.root.exists())
        self.assertFalse(self.bottle.exists())
        self.assertEqual(result['servers_started_or_stopped'], [])

    def test_install_reentrant_and_source_isolated(self):
        state = self.installed()
        before = dict(state['files'])
        result = install(self.root, self.source, self.release1, self.profile)
        self.assertEqual(before, get_state(self.root)['files'])
        self.assertEqual(result['version'], 'v1')
        self.assertFalse((self.root / CLIENT / 'Pal/Saved').exists())
        self.assertFalse((self.root / CLIENT / 'Pal/Binaries/Win64/ue4ss/Mods/Old').exists())
        self.assertEqual((self.source / 'Pal/Binaries/Win64/dwmapi.dll').read_bytes(), b'OLD_INJECTION')
        self.assertEqual((self.source / 'Pal/Saved/SaveGames/private.sav').read_bytes(), b'SOURCE_SAVE')

    def test_update_rollback_preserves_personal_save(self):
        self.installed()
        save = self.root / USER / 'Saved/SaveGames/my.sav'
        save.parent.mkdir(parents=True)
        save.write_bytes(b'PLAYER_SAVE_SENTINEL')
        second = self.release('v2')
        update(self.root, second)
        self.assertEqual(get_state(self.root)['current'], 'v2')
        rollback(self.root)
        self.assertEqual(get_state(self.root)['current'], 'v1')
        self.assertEqual(save.read_bytes(), b'PLAYER_SAVE_SENTINEL')

    def test_failure_injection_rolls_back_all_files(self):
        before = self.installed()
        second = self.release('v2')
        def fail_after_first(number, item):
            if number == 0:
                raise OSError('simulated disk failure')
        with self.assertRaises(OSError):
            update(self.root, second, fault=fail_after_first)
        state = get_state(self.root)
        self.assertEqual(state['current'], 'v1')
        for relative, sha in before['files'].items():
            self.assertEqual(digest(self.root / relative), sha)

    def test_abrupt_exit_recovery_is_reentrant(self):
        before = self.installed()
        second = self.release('v2')
        def abrupt(number, item):
            if number == 1:
                raise SystemExit(97)
        with self.assertRaises(SystemExit):
            update(self.root, second, fault=abrupt)
        self.assertEqual(len(recover_transactions(self.root)), 1)
        self.assertEqual(recover_transactions(self.root), [])
        for relative, sha in before['files'].items():
            self.assertEqual(digest(self.root / relative), sha)

    def test_modified_payload_is_never_overwritten(self):
        self.installed()
        path = self.root / BIN / 'PalCraftRender.dll'
        path.write_bytes(b'USER_MODIFIED')
        self.expect_code('UPDATE_CONFLICT', lambda: update(self.root, self.release('v2')))
        self.assertEqual(path.read_bytes(), b'USER_MODIFIED')

    def test_source_version_mismatch(self):
        (self.source / 'Pal/Binaries/Win64/Palworld-Win64-Shipping.exe').write_bytes(b'OTHER_GAME_VERSION')
        self.expect_code('GAME_VERSION', lambda: install(self.root, self.source, self.release1, self.profile))
        self.assertFalse(self.root.exists())

    def test_preexisting_unmanaged_directory_protected(self):
        self.root.mkdir(parents=True)
        (self.root / 'production-data.txt').write_text('PROTECTED')
        self.expect_code('UNMANAGED_DIRECTORY', lambda: install(self.root, self.source, self.release1, self.profile))
        self.assertEqual((self.root / 'production-data.txt').read_text(), 'PROTECTED')

    def test_original_bottle_rejected(self):
        p = {**self.profile, 'bottle_name': 'Steam'}
        self.expect_code('BOTTLE_PROTECTED', lambda: validate_profile(p, self.root))

    def test_fake_bottle_create_and_standard_mapping_reentrant(self):
        self.installed()
        calls = []
        def runner(argv, **kwargs):
            calls.append((argv, kwargs['env']['CX_BOTTLE_PATH']))
            self.bottle.mkdir(parents=True)
            (self.bottle / 'cxbottle.conf').write_text('fixture')
            (self.bottle / 'dosdevices').mkdir()
            (self.bottle / 'dosdevices/z:').symlink_to('/')
            return subprocess.CompletedProcess(argv, 0, '', '')
        self.assertTrue(create_bottle(self.root, dry_run=True)['create'])
        self.assertFalse(self.bottle.exists())
        create_bottle(self.root, runner=runner)
        create_bottle(self.root, runner=runner)
        self.assertEqual(len(calls), 1)
        self.assertEqual((self.bottle / 'dosdevices/z:').resolve(), Path('/'))
        self.assertFalse((self.bottle / 'dosdevices/d:').exists())

    def test_bottle_conflicting_mapping_never_replaced(self):
        self.installed()
        self.bottle.mkdir(parents=True)
        from installer.core import marker
        atomic_json(self.bottle / '.palcraft-bottle.json', {'root_id': marker(self.root)['id']})
        (self.bottle / 'dosdevices').mkdir()
        other = self.base / 'PROTECTED_DRIVE'
        other.mkdir()
        (self.bottle / 'dosdevices/d:').symlink_to(other)
        (self.bottle / 'dosdevices/z:').symlink_to(other)
        self.expect_code('BOTTLE_PATH_MAPPING', lambda: create_bottle(self.root))
        self.assertEqual((self.bottle / 'dosdevices/d:').resolve(), other)

    def test_bundle_hash_corruption_rejected(self):
        corrupted = self.base / 'bad.zip'
        with zipfile.ZipFile(self.release1) as source, zipfile.ZipFile(corrupted, 'w') as target:
            for name in source.namelist():
                data = source.read(name)
                if name.endswith('PalCraftRender.dll'):
                    data += b'CORRUPT'
                target.writestr(name, data)
        self.expect_code('BUNDLE_HASH', lambda: Bundle(corrupted))

    def test_bundle_traversal_and_unlisted_personal_data_rejected(self):
        for name in ('../escape.txt', 'payload/Steam/loginusers.vdf'):
            bad = self.base / (uuid.uuid4().hex + '.zip')
            shutil.copy2(self.release1, bad)
            with zipfile.ZipFile(bad, 'a') as archive:
                archive.writestr(name, b'PRIVATE')
            self.assertRaises(PlayerError, Bundle, bad)

    def test_directory_symlink_protected(self):
        self.installed()
        path = self.root / DEV / 'player-tools/licenses'
        shutil.rmtree(path)
        path.symlink_to(self.base / 'external')
        self.expect_code('DIRECTORY_LINK', lambda: update(self.root, self.release('v2')))

    def test_uninstall_preserves_saves_and_user_changes(self):
        self.installed()
        save = self.root / USER / 'Saved/SaveGames/a.sav'
        save.parent.mkdir(parents=True)
        save.write_bytes(b'KEEP_SAVE')
        modified = self.root / BIN / 'PalCraftMesh.dll'
        modified.write_bytes(b'KEEP_MODIFIED')
        other = self.root / CLIENT / 'user_notes.txt'
        other.write_text('KEEP_UNOWNED')
        result = uninstall(self.root)
        self.assertTrue(result['saves_preserved'])
        self.assertEqual(save.read_bytes(), b'KEEP_SAVE')
        self.assertEqual(modified.read_bytes(), b'KEEP_MODIFIED')
        self.assertTrue(other.exists())
        self.assertFalse(get_state(self.root)['installed'])
        uninstall(self.root)

    def test_session_busy_blocks_update_uninstall(self):
        self.installed()
        atomic_json(self.root / '.palcraft/session.json', {'phase': 'running'})
        self.expect_code('CLIENT_BUSY', lambda: update(self.root, self.release('v2')))
        self.expect_code('CLIENT_BUSY', lambda: uninstall(self.root))

    def test_profile_shell_injection_rejected(self):
        p = json.loads(json.dumps(self.profile))
        p['connection']['ssh_target'] = 'test; echo UNSAFE'
        self.expect_code('CONFIG_SSH', lambda: validate_profile(p, self.root))

    def test_doctor_missing_dependencies_chinese(self):
        self.installed()
        report = health(self.root)
        self.assertFalse(report['ok'])
        self.assertIn('MODELS_MISSING', {x['code'] for x in report['checks'] if not x['ok']})
        self.assertIn('BOTTLE_UNMANAGED', {x['code'] for x in report['checks'] if not x['ok']})

    def test_start_dry_run_has_fixed_local_ports_and_no_process(self):
        self.installed()
        result = start(self.root, dry_run=True)
        self.assertIn('127.0.0.1:25599:127.0.0.1:29001', result['commands']['ssh'])
        self.assertIn('--bottle', result['commands']['client'])
        self.assertNotIn('Steam', result['commands']['client'])
        self.assertEqual(result['servers_started_or_stopped'], [])
        self.assertFalse((self.root / '.palcraft/session.json').exists())

    def test_fake_normal_close_preserves_unrelated_process(self):
        other = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(30)'])
        self.processes.append(other)
        process, token = self.make_fake_session()
        self.wait_phase({'running'})
        result = stop(self.root, timeout=6)
        self.assertEqual(result['phase'], 'stopped')
        self.assertIsNone(other.poll())
        process.wait(timeout=3)
        trace = (self.root / '.palcraft/fake-trace.txt').read_text().splitlines()
        self.assertLess(trace.index('client closed'), trace.index('hud stopped'))
        self.assertLess(trace.index('hud stopped'), trace.index('udp stopped'))
        self.assertLess(trace.index('udp stopped'), trace.index('ssh stopped'))
        self.assertEqual(stop(self.root)['phase'], 'stopped')

    def test_fake_refused_close_does_not_teardown_services(self):
        process, token = self.make_fake_session(client='refuse')
        self.wait_phase({'running'})
        self.expect_code('CLOSE_PENDING', lambda: stop(self.root, timeout=.5))
        self.assertTrue(all(x['alive'] for x in status(self.root)['components'].values()))
        self.assertEqual(stop(self.root, force=True, timeout=6)['phase'], 'stopped')
        process.wait(timeout=3)

    def test_fake_ssh_failure_cleans_startup(self):
        process, token = self.make_fake_session(ssh='fail')
        session = self.wait_phase({'failed'})
        process.wait(timeout=3)
        self.assertNotIn('client', session['components'])

    def test_fake_connection_failure_requests_game_close(self):
        process, token = self.make_fake_session(hud='delayed-fail')
        self.wait_phase({'running'})
        session = self.wait_phase({'failed'})
        process.wait(timeout=3)
        self.assertEqual(session['code'], 'CONNECTION_LOST')
        self.assertIn('client closed', (self.root / '.palcraft/fake-trace.txt').read_text())

    def test_fake_owner_crash_worker_leases_expire(self):
        process, token = self.make_fake_session()
        self.wait_phase({'running'})
        process.kill(); process.wait()
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline and 'client owner_gone' not in (self.root / '.palcraft/fake-trace.txt').read_text():
            time.sleep(.1)
        result = recover_session(self.root, wait_seconds=16)
        self.assertEqual(result['phase'], 'stopped')
        self.assertIn('client owner_gone', (self.root / '.palcraft/fake-trace.txt').read_text())

    def test_stale_pid_record_never_signals_unrelated_process(self):
        self.installed()
        other = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(30)'])
        self.processes.append(other)
        atomic_json(self.root / '.palcraft/session.json', {'phase': 'running', 'token': uuid.uuid4().hex,
                    'supervisor': {'pid': other.pid, 'identity': 'not-this-process'},
                    'components': {'client': {'pid': other.pid, 'identity': 'not-this-process'}}})
        recover_session(self.root, wait_seconds=.5)
        self.assertIsNone(other.poll())

    def test_diagnostics_excludes_player_files_and_redacts(self):
        self.installed()
        path = self.root / '.palcraft/logs/ssh.log'
        path.parent.mkdir()
        path.write_text('test-bridge PRIVATE_SESSION_MARKER 100.74.50.81\n{"holder_private":"PRIVATE_KEY_SENTINEL"}\n'
                        '-----BEGIN PRIVATE KEY-----\nSECRETSENTINEL\n-----END PRIVATE KEY-----\n')
        secret = self.root / USER / 'save.sav'
        secret.write_text('PRIVATE_SAVE_SENTINEL')
        output = self.base / 'diagnostics.zip'
        diagnostics(self.root, output)
        with zipfile.ZipFile(output) as archive:
            text = ''.join(archive.read(n).decode() for n in archive.namelist())
            for sentinel in ('test-bridge', 'PRIVATE_SESSION_MARKER', '100.74.50.81', 'PRIVATE_KEY_SENTINEL', 'SECRETSENTINEL', 'PRIVATE_SAVE_SENTINEL'):
                self.assertNotIn(sentinel, text)
            self.assertFalse(any(n.endswith('.sav') for n in archive.namelist()))

    def test_ephemeral_port_conflict_only_checks_no_termination(self):
        with socket.socket() as s:
            s.bind(('127.0.0.1', 0))
            self.assertFalse(_port_free(s.getsockname()[1]))


class UdpTests(unittest.IsolatedAsyncioTestCase):
    async def test_frame_echo_and_idle_peer_cleanup(self):
        async def echo(reader, writer):
            try:
                while True:
                    header = await reader.readexactly(4)
                    count = struct.unpack('!I', header)[0]
                    writer.write(header + await reader.readexactly(count)); await writer.drain()
            except asyncio.IncompleteReadError:
                pass
            finally:
                writer.close(); await writer.wait_closed()
        server = await asyncio.start_server(echo, '127.0.0.1', 0)
        relay = LocalRelay(server.sockets[0].getsockname()[1], idle_seconds=.25)
        transport, _ = await asyncio.get_running_loop().create_datagram_endpoint(lambda: relay, local_addr=('127.0.0.1', 0))
        got = asyncio.Future()
        class Receiver(asyncio.DatagramProtocol):
            def datagram_received(self, data, addr):
                if not got.done():got.set_result(data)
        client, _ = await asyncio.get_running_loop().create_datagram_endpoint(Receiver, local_addr=('127.0.0.1', 0))
        try:
            client.sendto(b'PAID_SURVIVAL_TEST_PACKET', transport.get_extra_info('sockname'))
            self.assertEqual(await asyncio.wait_for(got, 2), b'PAID_SURVIVAL_TEST_PACKET')
            await asyncio.sleep(.4)
            self.assertEqual(relay.peers, {})
        finally:
            client.close(); await relay.close(); server.close(); await server.wait_closed()

    async def test_invalid_oversized_frame_releases_peer(self):
        async def bad(reader, writer):
            await reader.read(100)
            writer.write(struct.pack('!I', 100000)); await writer.drain()
            writer.close(); await writer.wait_closed()
        server = await asyncio.start_server(bad, '127.0.0.1', 0)
        relay = LocalRelay(server.sockets[0].getsockname()[1], idle_seconds=.5)
        transport, _ = await asyncio.get_running_loop().create_datagram_endpoint(lambda: relay, local_addr=('127.0.0.1', 0))
        client, _ = await asyncio.get_running_loop().create_datagram_endpoint(asyncio.DatagramProtocol, local_addr=('127.0.0.1', 0))
        try:
            client.sendto(b'probe', transport.get_extra_info('sockname'))
            await asyncio.sleep(.3)
            self.assertEqual(relay.peers, {})
        finally:
            client.close(); await relay.close(); server.close(); await server.wait_closed()


if __name__ == '__main__':
    unittest.main(verbosity=2)
