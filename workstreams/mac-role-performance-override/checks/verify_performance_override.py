"""Three bounded synthetic file-only checks; no real credential or runtime."""
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'checks/dependencies'))


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


old = module('original_prepare_launch', HERE / 'base/mac/scripts/prepare_launch.py')
new = module('candidate_prepare_launch', HERE / 'source/mac/scripts/prepare_launch.py')
dto = module('original_Mac_DTO_guard', HERE / 'checks/dependencies/prepare_guest.py')
identity = json.loads((HERE / 'checks/fixtures/synthetic-credential.json').read_bytes())['identity']


class PerformanceOverrideTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='palcraft-role-performance-source-check-')
        self.root = Path(self.temp.name).resolve()
        backend, data = self.root / 'backend', self.root / 'data'
        for relative, value in (
                ('setup/mac-dependency-plan.json', {'libraries': []}),
                ('client/versions/fabric-loader-0.19.5-26.3/fabric-loader-0.19.5-26.3.json',
                 {'id': 'synthetic-fixture-loader', 'arguments': {'jvm': ['-Dfixture.preserved=original']}})):
            path = backend / relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(json.dumps(value))
        library = backend / 'client/versions/26.3/26.3.jar'
        library.parent.mkdir(parents=True, exist_ok=True); library.write_bytes(b'SYNTHETIC_FILE_ONLY_NOT_A_RUNTIME_JAR')
        self.bridge, self.run = data / 'bridge', backend / 'players' / identity['mc_uuid'] / 'minecraft'
        self.launch = self.root / 'launch'
        self.cfg = {'software_root': str(backend), 'java_home': str(backend / 'java/Contents/Home'),
            'guest_mc_uuid': identity['mc_uuid'], 'guest_mc_name': identity['mc_name'],
            'guest_bridge_dir': str(self.bridge), 'server_bridge_dir': str(data / 'server-bridge'),
            'entity_dir': str(data / 'entities'), 'exchange_dir': str(data / 'exchange'), 'rpc_root': str(data / 'rpc'),
            'authority_public': str(data / 'authority-public.json'), 'credential_file': str(data / 'credential.json'),
            'frame_file': str(self.bridge / 'mcpt-hud.bin'), 'guest_ws': 25599,
            'minecraft_server': '127.0.0.1:25567', 'server_game_dir': str(backend / 'server'),
            'guest_game_dir': str(self.run), 'launch_dir': str(self.launch),
            'feature_jvm_public': {'palcraft.exchange.enabled': 'true', 'palcraft.travel.enabled': 'true'},
            'performance': {'mc_fps': 60, 'hud_fps': 30, 'render_distance': 8, 'simulation_distance': 12},
            'configured_for_actual_boot': False, 'mod_filename': 'synthetic-fixture-only.jar', 'mod_sha256': 'fixture-only'}
        self.config = self.root / 'config.json'; self.config.write_text(json.dumps(self.cfg))
        old.prepare_launch(self.config)
        self.template = {'roles': {role: json.loads((self.launch / (role + '.json')).read_bytes())
                                 for role in ('server', 'guest', 'hud')}}
        values = self.template['roles']['guest']['arguments']
        index = next(i for i, value in enumerate(values) if value.startswith('-Dpalcraft.maxFps='))
        values[index] = '-Dpalcraft.maxFps=10'
        values = self.template['roles']['hud']['arguments']; values[values.index('--fps') + 1] = '10'
        self.template_path = self.root / 'preserved-template.json'; self.template_path.write_text(json.dumps(self.template))
        self.cfg['preserve_launch_template'] = str(self.template_path)
        self.config.write_text(json.dumps(self.cfg))
        old.prepare_launch(self.config)
        self.before = self.snapshot()
        self.inputs = {path: path.read_bytes() for path in (self.config, self.template_path)}

    def tearDown(self):
        self.temp.cleanup()

    def snapshot(self):
        return {path.name: path.read_bytes() for path in self.launch.iterdir() if path.is_file()}

    def assert_inputs_unchanged(self):
        self.assertEqual({path: path.read_bytes() for path in self.inputs}, self.inputs)

    def test_no_override_all_role_and_args_bytes_equal_original(self):
        old_result = old.prepare_launch(self.config)
        new_result = new.prepare_launch(self.config)
        self.assertEqual(old_result, new_result)
        self.assertEqual(self.snapshot(), self.before)
        self.assert_inputs_unchanged()

    def test_explicit_day_and_night_only_two_FPS_values_change_and_2089_guard_accepts(self):
        for values in ({'mc_fps': 60, 'hud_fps': 30}, {'mc_fps': 10, 'hud_fps': 10}):
            with self.subTest(values=values):
                override = self.root / 'policy-values.json'; override.write_text(json.dumps(values))
                argv = ['prepare_launch.py', '--config', str(self.config), '--performance-override', str(override)]
                stdout = io.StringIO()
                with patch.object(sys, 'argv', argv), patch('sys.stdout', stdout): new.main()
                self.assertTrue(json.loads(stdout.getvalue())['prepared_only'])
                actual = self.snapshot()
                for name in ('server.json', 'server.args', 'hud-overlay-env.json'):
                    self.assertEqual(actual[name], self.before[name])
                for role, key in (('guest', 'mc_fps'), ('hud', 'hud_fps')):
                    before = json.loads(self.before[role + '.json']); after = json.loads(actual[role + '.json'])
                    expected = copy.deepcopy(before)
                    args = expected['arguments']
                    if role == 'guest':
                        i = next(i for i, value in enumerate(args) if value.startswith('-Dpalcraft.maxFps='))
                        args[i] = '-Dpalcraft.maxFps=' + str(values[key])
                    else: args[args.index('--fps') + 1] = str(values[key])
                    self.assertEqual(after, expected)
                guest = json.loads(actual['guest.json'])
                expected_args = '\n'.join(json.dumps(value, ensure_ascii=False) for value in guest['arguments']) + '\n'
                self.assertEqual(actual['guest.args'].decode(), expected_args)
                # Existing 2089 parses the real temporary producer outputs; its FPS/identity/ports guards are unchanged.
                endpoint, _ = dto.mac_guest(identity, remote_root=self.cfg['software_root'], data_root=self.root / 'data',
                    launch_dir=self.launch, mc_ws_port=25599, hud_port=25603,
                    mc_server_address='127.0.0.1:25567',
                    mapping='Local\\MCPassthroughFrame-' + identity['mc_uuid'], max_fps=values['mc_fps'])
                self.assertEqual(endpoint['max_fps'], values['mc_fps'])
                self.assertEqual(endpoint['hud_args'][endpoint['hud_args'].index('--fps') + 1], str(values['hud_fps']))
                self.assert_inputs_unchanged()

    def test_invalid_and_ambiguous_override_rejected_before_role_file_publication(self):
        for values in ({'mc_fps': 61, 'hud_fps': 30}, {'mc_fps': True, 'hud_fps': 30},
                       {'mc_fps': 60, 'hud_fps': 0}, {'mc_fps': 60, 'hud_fps': 121},
                       {'mc_fps': 60}, {'mc_fps': 60, 'hud_fps': 30, 'identity': 'not-an-override-field'}):
            with self.subTest(values=values):
                with self.assertRaises(ValueError): new.prepare_launch(self.config, performance_override=values)
                self.assertEqual(self.snapshot(), self.before)
                self.assert_inputs_unchanged()
        for role, extra in (('guest', ['-Dpalcraft.maxFps=10']), ('hud', ['--fps', '10'])):
            with self.subTest(role=role):
                template = copy.deepcopy(self.template); template['roles'][role]['arguments'].extend(extra)
                self.template_path.write_text(json.dumps(template))
                with self.assertRaises(ValueError):
                    new.prepare_launch(self.config, performance_override={'mc_fps': 60, 'hud_fps': 30})
                self.assertEqual(self.snapshot(), self.before)
                self.template_path.write_bytes(self.inputs[self.template_path])


if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PerformanceOverrideTests))
    receipt = {'schema': 1, 'passed': result.wasSuccessful(), 'tests': result.testsRun,
        'failures': len(result.failures), 'errors': len(result.errors),
        'source_sha256': hashlib.sha256((HERE / 'source/mac/scripts/prepare_launch.py').read_bytes()).hexdigest(),
        'base_sha256': hashlib.sha256((HERE / 'base/mac/scripts/prepare_launch.py').read_bytes()).hexdigest(),
        'default_output_bytes_and_argv_equal_original': result.wasSuccessful(),
        'explicit_only_MC_maxFPS_and_HUD_FPS_values_changed': result.wasSuccessful(),
        '2089_original_role_FPS_identity_port_frame_guards_accept_producer_outputs': result.wasSuccessful(),
        'override_invalid_or_duplicate_positions_rejected_before_role_publication': result.wasSuccessful(),
        'existing_template_and_config_fixture_bytes_unchanged': result.wasSuccessful(),
        'all_fixtures_temporary_and_synthetic': True, 'new_credential_key_UID_SID_grant_or_signature_created': False,
        'actual_credential_current_runtime_saved_vendor_or_installed_files_read_or_written': False,
        'original_12_Mac_DTO_checks_rerun': False, 'MC_GUI_network_RPC_Popen_or_Git_operations': False,
        'actual_performance_or_gameplay_accepted': False}
    (HERE / 'verification.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=2))
    raise SystemExit(0 if result.wasSuccessful() else 1)
