"""Bounded file-only fixtures; no real credential, issuer, service, or install."""
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'source/multiplayer'))


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


new = module('new_prepare_guest', HERE / 'source/multiplayer/prepare_guest.py')
old = module('old_prepare_guest', HERE / 'base/multiplayer/prepare_guest.py')
vector = json.loads((HERE / 'checks/fixtures/public-vector.json').read_bytes())
fixture_data = (HERE / 'checks/fixtures/synthetic-credential.json').read_bytes()
fixture = json.loads(fixture_data)
public = new.inspect_grant(fixture['grant'])


class MacGuestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='palcraft-mac-guest-source-check-')
        self.root = Path(self.temp.name).resolve()
        self.backend, self.data, self.launch = (self.root / name for name in ('backend', 'data', 'launch'))
        self.launch.mkdir()
        self.credential = self.data / '.palcraft/credentials/credential.json'
        self.credential.parent.mkdir(parents=True)
        self.credential.write_bytes(fixture_data)
        self.identity = fixture['identity']
        self.bridge = self.data / 'PalCraft-Dev/bridge'
        self.run = self.backend / 'players' / self.identity['mc_uuid'] / 'minecraft'
        self.frame = self.bridge / 'mcpt-hud.bin'
        self.mapping = 'Local\\MCPassthroughFrame-' + self.identity['mc_uuid']
        self.args = ['-XstartOnFirstThread', '--enable-native-access=ALL-UNNAMED',
            '-Dpalcraft.sessions.mode=strict', '-Dpalcraft.session.credential=' + str(self.credential),
            '-Dpalcraft.bridgeDir=' + str(self.bridge), '-Dpalcraft.frameFile=' + str(self.frame),
            '-Dpalcraft.frameName=' + self.mapping, '-Dpassthrough.port=25599',
            '-Dpalcraft.server=127.0.0.1:25567', '-Dpalcraft.maxFps=10',
            '-Dpalcraft.exchange.enabled=true', '-classpath', 'preserved-native-libraries',
            'net.fabricmc.loader.impl.launch.knot.KnotClient', '--username', self.identity['mc_name'],
            '--gameDir', str(self.run), '--uuid', self.identity['mc_uuid'], '--accessToken', '0']
        self.roles = {
            'guest': {'schema': 1, 'role': 'guest', 'main': 'KnotClient',
                'executable': str(self.backend / 'java/Contents/Home/bin/java'),
                'cwd': str(self.run), 'same_original_uuid': self.identity['mc_uuid'],
                'frame_file': str(self.frame), 'arguments': self.args},
            'hud': {'schema': 1, 'role': 'hud', 'main': str(self.backend / 'hud/hud_relay.py'),
                'executable': 'python3', 'cwd': str(self.bridge),
                'same_original_uuid': self.identity['mc_uuid'], 'frame_file': str(self.frame),
                'arguments': ['--frame-file', str(self.frame), '--fps', '10', '--port', '25603']}}
        self.write_roles()
        self.options = dict(remote_root=str(self.backend), mc_ws_port=25599, hud_port=25603,
            mc_server_address='127.0.0.1:25567', allocation_file=self.root / 'allocations.json',
            output=self.root / 'public-guest.json', remote_host='local', now=vector['now'],
            max_fps=10, platform='mac-local', mac_data_root=self.data, mac_launch_dir=self.launch)

    def tearDown(self):
        self.temp.cleanup()

    def write_roles(self):
        for role, value in self.roles.items():
            (self.launch / (role + '.json')).write_text(json.dumps(value))

    def prepare(self, **updates):
        return new.prepare(str(self.credential), **{**self.options, **updates})

    def rejected_without_outputs(self, **updates):
        with self.assertRaises(ValueError):
            self.prepare(**updates)
        self.assertFalse(self.options['output'].exists())
        self.assertFalse(self.options['allocation_file'].exists())

    def test_windows_default_entire_manifest_and_allocation_match_original(self):
        options = dict(remote_root='D:/PalworldServer-LAN/PalCraft-Dev', mc_ws_port=29901,
            hud_port=29903, mc_server_address='127.0.0.1:25567', now=vector['now'])
        a = old.prepare(str(self.credential), **options,
            allocation_file=self.root / 'old-alloc.json', output=self.root / 'old-guest.json')
        b = new.prepare(str(self.credential), **options,
            allocation_file=self.root / 'new-alloc.json', output=self.root / 'new-guest.json')
        self.assertEqual(a, b)
        self.assertEqual((self.root / 'old-alloc.json').read_bytes(), (self.root / 'new-alloc.json').read_bytes())
        self.assertEqual(b['remote_host'], '5090')
        self.assertNotIn('platform', b)

    def test_mac_DTO_has_enrolled_identity_SID_and_exact_preserved_arguments(self):
        before = {role: (self.launch / (role + '.json')).read_bytes() for role in self.roles}
        manifest = self.prepare()
        self.assertEqual(manifest['identity'], public['identity'])
        self.assertEqual(manifest['server_session_id'], public['server_session_id'])
        self.assertEqual(manifest['expires_at'], public['expires_at'])
        self.assertEqual(manifest['guest']['frame_mapping'], self.mapping)
        self.assertEqual(manifest['guest']['frame_file'], str(self.frame))
        self.assertEqual(manifest['guest']['jvm_args'] + [manifest['guest']['main_class']] + manifest['guest']['mc_args'], self.args)
        self.assertEqual(manifest['guest']['hud_args'], self.roles['hud']['arguments'])
        self.assertEqual(manifest['remote_host'], 'local')
        self.assertTrue(manifest['prepared_only']); self.assertFalse(manifest['starts_processes'])
        encoded = json.dumps(manifest)
        for secret in (fixture['grant'], fixture['host_secret'], fixture['holder_private']):
            self.assertNotIn(secret, encoded)
        self.assertEqual(self.credential.read_bytes(), fixture_data)
        self.assertEqual(before, {role: (self.launch / (role + '.json')).read_bytes() for role in self.roles})

    def test_real_installed_consumer_schema_function_accepts_Mac_DTO(self):
        self.prepare()
        core = types.ModuleType('installer.core')
        class ConsumerError(ValueError):
            pass
        def fail(code, message, *args):
            raise ConsumerError(code)
        def unused(*args, **kwargs):
            raise AssertionError('No installed state/write function is allowed')
        core.fail = fail
        core.read_json = lambda path: json.loads(Path(path).read_bytes())
        core.validate_profile = lambda profile, root: profile
        for name in ('atomic_json', 'configure', 'ensure_no_session', 'get_state', 'operation_lock', 'owned_path'):
            setattr(core, name, unused)
        with patch.dict(sys.modules, {'installer.core': core}):
            consumer = module('isolated_installed_credentials_consumer', HERE / 'consumer/credentials.py')
        profile = {'connection': {'remote_ports': {'udp_tcp': 25566}, 'transport': 'local'}}
        with patch.object(consumer.time, 'time', return_value=vector['now']):
            prepared, inspected = consumer.prepare_credential_profile(profile, self.data, self.credential, self.options['output'])
        self.assertEqual(prepared['connection']['identity'], public['identity'])
        self.assertEqual(prepared['connection']['server_session_id'], public['server_session_id'])
        self.assertEqual(prepared['connection']['frame_mapping'], self.mapping)
        self.assertEqual(prepared['connection']['remote_ports'], {'udp_tcp': 25566, 'mc_ws': 25599, 'hud': 25603, 'mc_server': 25567})
        self.assertFalse(inspected['signature_verified_locally'])

    def test_wrong_role_UUID_or_name_rejected(self):
        for key in ('--uuid', '--username'):
            with self.subTest(key=key):
                index = self.args.index(key) + 1; previous = self.args[index]
                self.args[index] = 'corrupted-synthetic-role'
                self.write_roles(); self.rejected_without_outputs()
                self.args[index] = previous

    def test_wrong_ports_server_FPS_and_duplicate_property_rejected(self):
        for old_value, bad_value in (
                ('-Dpassthrough.port=25599', '-Dpassthrough.port=29999'),
                ('-Dpalcraft.server=127.0.0.1:25567', '-Dpalcraft.server=127.0.0.1:25568'),
                ('-Dpalcraft.maxFps=10', '-Dpalcraft.maxFps=15')):
            with self.subTest(value=old_value):
                index = self.args.index(old_value); self.args[index] = bad_value
                self.write_roles(); self.rejected_without_outputs()
                self.args[index] = old_value
        self.args.append('-Dpassthrough.port=25599')
        self.write_roles(); self.rejected_without_outputs()

    def test_frame_file_metadata_or_data_root_mismatch_rejected(self):
        self.roles['hud']['frame_file'] = str(self.data / 'another-frame.bin')
        self.write_roles(); self.rejected_without_outputs()
        self.roles['hud']['frame_file'] = str(self.frame); self.write_roles()
        self.rejected_without_outputs(mac_data_root=self.backend)
        self.rejected_without_outputs(remote_root='D:/PalworldServer-LAN/PalCraft-Dev')

    def test_local_mode_requires_explicit_roots_and_local_host(self):
        self.rejected_without_outputs(mac_launch_dir=None)
        self.rejected_without_outputs(mac_data_root=None)
        self.rejected_without_outputs(remote_host='5090')
        self.rejected_without_outputs(platform='windows')

    def test_credential_public_SID_mismatch_and_expiry_rejected(self):
        malformed = copy.deepcopy(fixture); malformed['server_session_id'] = 'corrupted-fixture-SID'
        self.credential.write_text(json.dumps(malformed))
        self.rejected_without_outputs()
        self.credential.write_bytes(fixture_data)
        self.rejected_without_outputs(now=public['expires_at'])

    def allocated_other(self, manifest):
        other = copy.deepcopy(manifest)
        other['identity']['mc_uuid'] = '22222222-2222-2222-2222-222222222222'
        other['guest']['frame_mapping'] = 'Local\\MCPassthroughFrame-22222222-2222-2222-2222-222222222222'
        other['guest']['bridge_dir'] = str(self.data / 'other-guest/bridge')
        other['guest']['run_dir'] = str(self.backend / 'other-guest/minecraft')
        other['guest']['credential_file'] = str(self.data / 'other-guest/credential.json')
        other['guest']['frame_file'] = str(self.data / 'other-guest/frame.bin')
        return other

    def test_allocation_port_alias_frame_and_credential_collisions_rejected(self):
        manifest = self.prepare()
        for collision in ('port', 'frame_file', 'credential_file', 'run_dir'):
            with self.subTest(collision=collision):
                other = self.allocated_other(manifest)
                other['remote_host'] = 'localhost'
                if collision != 'port':
                    other['guest'].update(mc_ws_port=29901, hud_port=29903)
                    other['guest'][collision] = manifest['guest'][collision]
                allocation = {'schema': 1, 'guests': [other]}
                raw = json.dumps(allocation).encode(); self.options['allocation_file'].write_bytes(raw)
                output_before = self.options['output'].read_bytes()
                with self.assertRaises(ValueError): self.prepare()
                self.assertEqual(self.options['allocation_file'].read_bytes(), raw)
                self.assertEqual(self.options['output'].read_bytes(), output_before)

    def test_same_identity_renewal_replaces_old_SID_and_local_alias_row(self):
        manifest = self.prepare()
        manifest['server_session_id'] = 'old-synthetic-session'; manifest['remote_host'] = 'localhost'
        self.options['allocation_file'].write_text(json.dumps({'schema': 1, 'guests': [manifest]}))
        result = self.prepare(remote_host='127.0.0.1')
        rows = json.loads(self.options['allocation_file'].read_bytes())['guests']
        self.assertEqual(rows, [result])
        self.assertEqual(result['server_session_id'], public['server_session_id'])

    def test_public_output_cannot_replace_credential_or_role(self):
        for output in (self.credential, self.launch / 'guest.json'):
            with self.subTest(output=output.name):
                original = output.read_bytes()
                with self.assertRaises(ValueError): self.prepare(output=output)
                self.assertEqual(output.read_bytes(), original)
        self.assertFalse(self.options['allocation_file'].exists())

    def test_normal_cli_chooses_local_scope_and_only_prepares_files(self):
        argv = ['prepare_guest.py', '--credential', str(self.credential), '--output', str(self.options['output']),
            '--allocations', str(self.options['allocation_file']), '--platform', 'mac-local',
            '--remote-root', str(self.backend), '--mac-data-root', str(self.data),
            '--mac-launch-dir', str(self.launch), '--mc-ws-port', '25599', '--hud-port', '25603', '--max-fps', '10']
        stdout = io.StringIO()
        with patch.object(sys, 'argv', argv), patch.object(new.time, 'time', return_value=vector['now']), patch('sys.stdout', stdout):
            new.main()
        result = json.loads(stdout.getvalue())
        self.assertTrue(result['ok']); self.assertTrue(result['prepared_only'])
        self.assertEqual(json.loads(self.options['output'].read_bytes())['remote_host'], 'local')


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(MacGuestTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    receipt = {'schema': 1, 'passed': result.wasSuccessful(), 'tests': result.testsRun,
        'failures': len(result.failures), 'errors': len(result.errors),
        'changed_source_sha256': hashlib.sha256((HERE / 'source/multiplayer/prepare_guest.py').read_bytes()).hexdigest(),
        'installed_consumer_source_sha256': hashlib.sha256((HERE / 'consumer/credentials.py').read_bytes()).hexdigest(),
        'fixed_existing_synthetic_credential_only': True, 'new_credential_key_or_grant_generated': False,
        'actual_credential_or_current_runtime_files_read': False,
        'actual_installed_consumer_inspect_and_prepare_schema_function_exercised': True,
        'full_profile_validate_or_installed_state_function_exercised': False,
        'windows_entire_default_manifest_and_allocations_equal_original': True,
        'network_ports_processes_or_GUI_used': False, 'current_ready_or_gameplay_claimed': False}
    print(json.dumps(receipt, indent=2))
    raise SystemExit(0 if result.wasSuccessful() else 1)
