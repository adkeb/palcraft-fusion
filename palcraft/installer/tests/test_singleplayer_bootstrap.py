"""Temporary-root tests; no Wine, Palworld, Steam or backend is executed."""
import copy
import json
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from installer.core import BIN, CLIENT, DEV, TOOLS, PlayerError, atomic_json, digest, validate_profile
from launcher import runtime


class SingleplayerBootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='palcraft-bootstrap-')
        self.root = Path(self.temp.name).resolve() / '玩家 客户端'
        self.root.mkdir()
        atomic_json(self.root / '.palcraft/owner.json', {
            'kind': 'palcraft-player-owned-root', 'root': str(self.root), 'id': 'bootstrap-fixture'})
        app = self.root.parent / 'apps/CrossOver.app'
        wine = app / 'Contents/SharedSupport/CrossOver/bin/wine'
        wine.parent.mkdir(parents=True)
        wine.write_bytes(b'fixture, never executed')
        bottle = self.root.parent / 'bottles/SelectedFixture'
        (bottle / 'dosdevices').mkdir(parents=True)
        (bottle / 'dosdevices/z:').symlink_to('/')
        (bottle / 'cxbottle.conf').write_text('WineArch = "win64"\n')
        mc_uuid = '11111111-1111-1111-1111-111111111111'
        self.profile = {
            'platform': 'crossover', 'bottle_mode': 'existing-selected',
            'bottle_name': bottle.name, 'bottle_root': str(bottle), 'crossover_app': str(app),
            'pal_entry_mode': 'singleplayer', 'launch_shipping': True, 'fps': 60,
            'connection': {'transport': 'local', 'mode': 'strict-player',
                'local_ports': {'mc_ws': 29599},
                'remote_ports': {'udp_tcp': 18321, 'mc_ws': 25599, 'mc_server': 25567, 'hud': 25603},
                'server_session_id': 'fixture-observation', 'frame_mapping': 'Local' + chr(92) + 'MCPassthroughFrame-' + mc_uuid,
                'world_origin': {'X': 0, 'Y': 0, 'Z': 0},
                'identity': {'pal_uid': '22222222-0000-0000-0000-000000000000',
                             'mc_uuid': mc_uuid, 'mc_name': 'Fixture', 'world_id': 'fixture-world'}}}
        files = []
        for role, target, data in [
            ('client_host', TOOLS + '/bin/PalCraftClientHost-v1.exe', b'fixture-host'),
            ('mac_hud', TOOLS + '/bin/hud-overlay-player', b'fixture-hud'),
            ('session_client', TOOLS + '/multiplayer/session_client.py', b'fixture-protocol'),
            ('ue4ss_settings', BIN + 'ue4ss/UE4SS-settings.ini',
             b'EnableHotReloadSystem = 0\nEnableAutoReloadingLuaMods = 0\n')]:
            path = self.root / target
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            files.append({'role': role, 'target': target, 'sha256': digest(path)})
        shipping = self.root / BIN / 'Palworld-Win64-Shipping.exe'
        shipping.write_bytes(b'fixture-shipping')
        atomic_json(self.root / DEV / 'bridge/models/manifest.json', {'schema': 4, 'models': 1, 'textures': 1})
        self.state = {'installed': True, 'current': 'fixture', 'profile': self.profile,
                      'game_sha256': digest(shipping),
                      'manifest': {'files': files, 'requirements': {'native_host_proxy_port_env': runtime.HOST_PROXY_PORT_ENV}}}
        atomic_json(self.root / '.palcraft/state.json', self.state)
        self.token = '1' * 32
        self.calls = []

    def tearDown(self):
        self.temp.cleanup()

    def session(self, launch_mode):
        atomic_json(self.root / '.palcraft/session.json', {
            'token': self.token, 'phase': 'starting', 'components': {}, 'launch_mode': launch_mode})
        fake = self.root / 'fixture_host.py'
        fake.write_text("import time\nfrom pathlib import Path\nroot=Path(" + repr(str(self.root)) + ")\n"
                        "(root/'host-started').write_text('started')\n"
                        "while not (root/'.palcraft/control/'" + repr(self.token + '.stop') + ").exists(): time.sleep(.01)\n")
        def unavailable(port, kind, timeout):
            self.calls.append(kind)
            raise OSError('backend deliberately unavailable')
        return runtime.Session(self.root, self.token, {'client': [sys.executable, str(fake)]}, unavailable, .01)

    def test_bootstrap_lifecycle_skips_unavailable_backend_and_never_grants_ready(self):
        session = self.session(runtime.BOOTSTRAP_MODE)
        thread = threading.Thread(target=session.run)
        thread.start()
        try:
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                saved = json.loads((self.root / '.palcraft/session.json').read_text())
                if saved['phase'] == 'bootstrap':
                    break
                time.sleep(.01)
            self.assertEqual(saved['phase'], 'bootstrap')
            self.assertEqual(set(saved['components']), {'client'})
            self.assertEqual(self.calls, [])
            observed = runtime.status(self.root)
            self.assertTrue(observed['supervisor_alive'])
            self.assertFalse(observed['game_ready'])
            self.assertFalse(observed['transport_ready'])
            self.assertFalse(observed['mc_actions_authorized'])
            self.assertIn('ai', observed['pending'])
            self.assertTrue(runtime.stop(self.root, timeout=3)['ok'])
        finally:
            runtime._write_control(self.root, self.token, 'close')
            thread.join(timeout=3)
            self.assertFalse(thread.is_alive())

    def test_full_start_still_requires_backend_before_host(self):
        result = self.session('full').run(startup_timeout=0)
        self.assertEqual(result['code'], 'REMOTE_UNAVAILABLE')
        self.assertEqual(self.calls, ['mc_ws'])
        self.assertFalse((self.root / 'host-started').exists())

    def test_dry_plan_retains_same_host_and_full_plan_retains_proxy_and_hud(self):
        # Minimal fixture does not contain a production UE4SS pair; its ABI is tested elsewhere.
        with patch.object(runtime, 'require_release_paths'):
            observed = runtime.start(self.root, dry_run=True, boot_singleplayer=True)
            full = runtime.start(self.root, dry_run=True)
        self.assertEqual(set(observed['commands']), {'client'})
        self.assertEqual(set(full['commands']), {'client', 'proxy', 'hud'})
        self.assertEqual(observed['commands']['client'], full['commands']['client'])
        self.assertIn('--shipping', observed['commands']['client'])
        self.assertEqual(validate_profile(self.profile, self.root)['game_endpoint'], None)
        self.assertFalse((self.root / '.palcraft/session.json').exists())
        profile = copy.deepcopy(self.profile)
        profile['pal_entry_mode'] = 'dedicated'
        with self.assertRaises(PlayerError) as error:
            runtime._validate_launch_mode(validate_profile(profile, self.root), runtime.BOOTSTRAP_MODE)
        self.assertEqual(error.exception.code, 'BOOTSTRAP_SCOPE')

    def test_observation_defers_missing_credential_but_rejects_corrupt_game(self):
        observed = runtime.health(self.root, check_ports=True, launch_mode=runtime.BOOTSTRAP_MODE)
        self.assertTrue(observed['ok'])
        self.assertIn('authenticated_proxy', observed['deferred'])
        self.assertFalse(runtime.health(self.root)['ok'])
        (self.root / BIN / 'Palworld-Win64-Shipping.exe').write_bytes(b'corrupt')
        broken = runtime.health(self.root, launch_mode=runtime.BOOTSTRAP_MODE)
        self.assertFalse(broken['ok'])
        self.assertFalse(next(check['ok'] for check in broken['checks'] if check['code'] == 'GAME_VERSION'))


if __name__ == '__main__':
    unittest.main()
