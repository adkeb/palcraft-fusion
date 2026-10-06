"""One V4 activation transaction using a small verified namespace, no conversion/game."""
import hashlib
import json
import unittest
from pathlib import Path

import test_player_tools as fixtures
from installer.core import DEV, atomic_json, configure, digest, get_state, install
from installer.resources_v4 import activate


class ResourceActivationFlow(unittest.TestCase):
    def test_v4_selector_material_config_and_identity_remain_atomic(self):
        f = fixtures.PlayerTests(methodName='test_dry_run_has_no_files_or_network_or_processes')
        f.setUp()
        try:
            install(f.root, f.source, f.release1, f.profile)
            identity = get_state(f.root)['profile']['connection']['identity']
            registry = {'version': 1, 'enabled': True, 'bake_library': 'UNCHANGED_LIBRARY',
                        'widget_proof': {'capture_evidence': 'UNCHANGED_EVIDENCE'},
                        'pixel_packages': {'old/': {'namespace': 'old', 'index_path': 'material-pixels-v1/old/index.json'}}}
            atomic_json(f.root / DEV / 'bridge/material-runtime-v1.json', registry)
            staging = f.base / 'producer-staging'
            namespace = 'models-v4-' + 'a' * 64
            atomic_json(staging / 'bridge' / namespace / 'manifest.json', {'schema': 4, 'models': 1, 'textures': 1})
            atomic_json(staging / 'bridge/material-pixels-v1' / namespace / 'index.json', {'schema': 1})
            selector = {'schema_version': 1, 'directory': namespace, 'provider_version': 3, 'content_hash': 'a' * 64}
            atomic_json(staging / 'bridge/model-assets.json', selector)
            package = {namespace + '/': {'namespace': namespace, 'index_path': 'material-pixels-v1/' + namespace + '/index.json'}}
            atomic_json(staging / 'bridge/material-runtime-v1.json', {'version': 1, 'enabled': True, 'pixel_packages': package})
            files = [{'path': p.relative_to(staging).as_posix(), 'sha256': digest(p), 'bytes': p.stat().st_size}
                     for p in staging.rglob('*') if p.is_file()]
            report = {'schema': 4, 'namespace': namespace, 'files': files,
                      'model_manifest_sha256': digest(staging / 'bridge' / namespace / 'manifest.json'),
                      'runtime_config_patch': {'model_asset_directory': namespace}, 'minecraft_jar_sha256': 'b' * 64}
            result = activate(f.root, staging, report)
            self.assertTrue(result['identity_preserved'])
            state = get_state(f.root)
            self.assertEqual(state['profile']['connection']['identity'], identity)
            runtime = json.loads((f.root / DEV / 'bridge/runtime-config.json').read_text())
            self.assertEqual(runtime['model_asset_directory'], namespace)
            material = json.loads((f.root / DEV / 'bridge/material-runtime-v1.json').read_text())
            self.assertEqual(material['bake_library'], registry['bake_library'])
            self.assertEqual(material['widget_proof'], registry['widget_proof'])
            self.assertEqual(material['pixel_packages']['old/'], registry['pixel_packages']['old/'])
            # A later normal configure operation retains this personal namespace.
            configure(f.root, state['profile'])
            self.assertEqual(json.loads((f.root / DEV / 'bridge/runtime-config.json').read_text())['model_asset_directory'], namespace)
        finally:
            f.tearDown()


if __name__ == '__main__':
    unittest.main()
