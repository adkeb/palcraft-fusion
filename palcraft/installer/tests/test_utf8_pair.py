"""One exact approved Core/shim update and owned rollback; no DLL is executed."""
import copy
import json
import unittest
from pathlib import Path

import test_player_tools as fixtures
from installer.core import (BIN, USER, PlayerError, atomic_json, digest, get_state, install,
                            rollback, update, validate_utf8_pair)
from installer.packaging import build_release


class Utf8PairFlow(unittest.TestCase):
    def test_exact_pair_updates_and_rolls_back_together(self):
        fixture = fixtures.PlayerTests(methodName='test_dry_run_has_no_files_or_network_or_processes')
        fixture.setUp()
        try:
            fixture.root = fixture.base / 'Unicode player root'
            install(fixture.root, fixture.source, fixture.release1, fixture.profile)
            old_core = (fixture.root / BIN / 'ue4ss/UE4SS.dll').read_bytes()
            save = fixture.root / USER / 'Pal/Saved/SaveGames/preserved.sav'
            save.parent.mkdir(parents=True)
            save.write_bytes(b'PRIVATE_SAVE_FIXTURE')
            provider = Path(__file__).resolve().parents[3] / 'path-portability/next/ue4ss-utf8-iat-v1/frozen/pair-0bb2b3fc-shim-18f2a593/player-release-entries.json'
            approved = json.loads(provider.read_text())
            spec = json.loads((fixture.base / 'v1-spec.json').read_text())
            spec['version'] = 'utf8-pair-v1'
            spec['requirements'].update(approved['required_release_fields'])
            spec['files'] = [f for f in spec['files'] if f['role'] != 'ue4ss'] + approved['file_entries']
            spec_path, bundle = fixture.base / 'utf8-spec.json', fixture.base / 'utf8-release.zip'
            atomic_json(spec_path, spec)
            build_release(spec_path, bundle)
            update(fixture.root, bundle)
            manifest = get_state(fixture.root)['manifest']
            for f in approved['file_entries']:
                self.assertEqual(digest(fixture.root / f['target']), f['expected_sha256'])
            # Reject incomplete/mixed pairs without generating more ZIPs or touching a root.
            missing = copy.deepcopy(manifest)
            missing['files'] = [f for f in missing['files'] if f['role'] != 'ue4ss_utf8_shim']
            wrong_path = copy.deepcopy(manifest)
            next(f for f in wrong_path['files'] if f['role'] == 'ue4ss_utf8_shim')['target'] = BIN + 'ue4ss/PalCraftUE4SSUtf8.dll'
            mixed = copy.deepcopy(manifest)
            next(f for f in mixed['files'] if f['role'] == 'ue4ss')['sha256'] = '21b691a69a20c0801f465369d4fcbca7d7444764022fac2a7e8edc7709ef92b8'
            for malformed in (missing, wrong_path, mixed):
                with self.assertRaises(PlayerError) as error:
                    validate_utf8_pair(malformed)
                self.assertEqual(error.exception.code, 'BUNDLE_UTF8_PAIR')
            rollback(fixture.root)
            self.assertEqual((fixture.root / BIN / 'ue4ss/UE4SS.dll').read_bytes(), old_core)
            self.assertFalse((fixture.root / BIN / 'PalCraftUE4SSUtf8.dll').exists())
            self.assertEqual(save.read_bytes(), b'PRIVATE_SAVE_FIXTURE')
            self.assertEqual(get_state(fixture.root)['current'], 'v1')
        finally:
            fixture.tearDown()


if __name__ == '__main__':
    unittest.main()
