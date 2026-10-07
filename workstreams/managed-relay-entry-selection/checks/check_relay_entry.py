"""Three bounded original generator calls with synthetic temp config/template data.

No credential contents, Game, environment changes, socket, process or installed
file is used. Config paths below are inert references and are never launched.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
def load(name, folder):
    spec = importlib.util.spec_from_file_location(name, ROOT / folder / 'mac/scripts/prepare_launch.py')
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value
old = load('base_prepare', 'base'); new = load('new_prepare', 'source')

class RelayEntry(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='synthetic-relay-entry-')
        root = Path(self.temp.name)
        software = root / 'backend'; plan = software / 'setup/mac-dependency-plan.json'
        plan.parent.mkdir(parents=True); plan.write_text(json.dumps({'libraries': [{'path': 'fixture.jar'}]}))
        for name in ('client/libraries/fixture.jar', 'client/versions/26.3/26.3.jar'):
            file = software / name; file.parent.mkdir(parents=True, exist_ok=True); file.write_bytes(b'synthetic')
        version = software / 'client/versions/fabric-loader-0.19.5-26.3/fabric-loader-0.19.5-26.3.json'
        version.parent.mkdir(parents=True); version.write_text(json.dumps({'id': 'fixture', 'arguments': {'jvm': ['-Dfixture.keep=yes']}}))
        self.path = root / 'runtime-config.json'
        self.cfg = {'software_root': str(software), 'java_home': str(root / 'java'), 'guest_mc_uuid': 'fixture-UUID',
                    'guest_mc_name': 'Fixture', 'launch_dir': str(root / 'launch'), 'feature_jvm_public': {'fixture.feature': 'true'},
                    'authority_public': 'synthetic-public-reference', 'server_bridge_dir': str(root / 'server-bridge'),
                    'guest_bridge_dir': str(root / 'owned/bridge'), 'entity_dir': str(root / 'entities'),
                    'exchange_dir': str(root / 'exchange'), 'rpc_root': str(root / 'rpc'),
                    'guest_game_dir': str(root / 'guest'), 'server_game_dir': str(root / 'server'),
                    'credential_file': str(root / 'credential-reference-not-read.json'), 'frame_file': str(root / 'frame.bin'),
                    'guest_ws': 25599, 'minecraft_server': '127.0.0.1:25567',
                    'performance': {'mc_fps': 10, 'hud_fps': 10, 'render_distance': 4, 'simulation_distance': 5},
                    'configured_for_actual_boot': True, 'mod_filename': 'fixture.jar', 'mod_sha256': '0' * 64,
                    'hud_relay_script': str(root / 'owned/mac/hud/hud_relay.py')}
        self.template_path = root / 'previous-launch-plan.json'
        self.cfg['preserve_launch_template'] = str(self.template_path)
        self.template = {'roles': {}}
        for role, cwd, args in (
                ('server', self.cfg['server_game_dir'], ['-Dfixture.server=yes', '-jar', 'fixture-server.jar', 'nogui']),
                ('guest', self.cfg['guest_game_dir'], ['-Dpalcraft.maxFps=10', '-Dfixture.guest=yes', '--uuid', 'fixture-UUID']),
                ('hud', self.cfg['guest_bridge_dir'], ['--frame-file', self.cfg['frame_file'], '--fps', '10', '--port', '25603', '--status-file', 'fixture-status.json'])):
            self.template['roles'][role] = {'cwd': cwd, 'same_original_uuid': 'fixture-UUID',
                                           'frame_file': self.cfg['frame_file'], 'arguments': args,
                                           'executable': 'fixture-executable-' + role, 'main': 'fixture-legacy-main-' + role}
        self.template_path.write_text(json.dumps(self.template))
        self.template_hash = hashlib.sha256(self.template_path.read_bytes()).hexdigest()
    def tearDown(self): self.temp.cleanup()
    def run_generator(self, module, override=None):
        self.path.write_text(json.dumps(self.cfg))
        result = module.prepare_launch(self.path, performance_override=override)
        out = Path(self.cfg['launch_dir'])
        files = {file.name: file.read_bytes() for file in out.iterdir() if file.is_file()}
        self.assertEqual(hashlib.sha256(self.template_path.read_bytes()).hexdigest(), self.template_hash)
        self.assertFalse(Path(self.cfg['credential_file']).exists())
        return result, files
    def assert_only_main_changed(self, before, after):
        self.assertEqual(set(before), set(after))
        for name in before:
            if name != 'hud.json': self.assertEqual(before[name], after[name], name)
        a, b = json.loads(before['hud.json']), json.loads(after['hud.json'])
        self.assertEqual(b['main'], self.cfg['hud_relay_script'])
        self.assertNotEqual(a['main'], b['main'])
        b['main'] = a['main']; self.assertEqual(a, b)
    def test_declared_managed_relay_wins_over_legacy_template_main(self):
        result, before = self.run_generator(old)
        actual, after = self.run_generator(new)
        self.assertEqual(result, actual)
        self.assert_only_main_changed(before, after)
    def test_missing_declared_entry_keeps_original_template_semantics(self):
        del self.cfg['hud_relay_script']
        result, before = self.run_generator(old)
        actual, after = self.run_generator(new)
        self.assertEqual(result, actual); self.assertEqual(before, after)
        self.assertEqual(json.loads(after['hud.json'])['main'], 'fixture-legacy-main-hud')
    def test_every_other_field_and_explicit_fps_override_preserved(self):
        override = {'mc_fps': 60, 'hud_fps': 30}
        result, before = self.run_generator(old, override)
        actual, after = self.run_generator(new, override)
        self.assertEqual(result, actual); self.assert_only_main_changed(before, after)
        hud = json.loads(after['hud.json']); guest = json.loads(after['guest.json'])
        self.assertEqual(hud['arguments'][hud['arguments'].index('--fps') + 1], '30')
        self.assertIn('-Dpalcraft.maxFps=60', guest['arguments'])

if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(RelayEntry))
    receipt = {'schema': 1, 'ok': result.wasSuccessful(), 'cases_passed': result.testsRun if result.wasSuccessful() else 0,
               'cases': ['declared managed HUD relay entry overrides old template main',
                         'missing cfg.hud_relay_script keeps original full generator bytes',
                         'all other fields/files, executable/args/cwd/ports/frame/UUID and explicit FPS override preserved'],
               'original_template_not_modified': True, 'all_config_template_libraries_and_identity_data_synthetic': True,
               'credential_reference_only_no_contents': True, 'actual_relay_or_Game_started_updated_or_requested': False}
    (ROOT / 'checks/receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt)); raise SystemExit(0 if result.wasSuccessful() else 1)
