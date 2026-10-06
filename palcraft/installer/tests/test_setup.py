"""One installation entry keeps the exact registered identity and launch prerequisites."""
import json
import subprocess
import unittest
from pathlib import Path

import test_player_tools as fixtures
from test_sessions import credential
from installer.core import DEV, USER, atomic_json, get_state
from installer.setup import setup_player


class SetupFlow(unittest.TestCase):
    def test_single_entry_prepares_same_uuid_and_never_starts_game(self):
        f = fixtures.PlayerTests(methodName='test_dry_run_has_no_files_or_network_or_processes')
        f.setUp()
        try:
            root = f.base / 'player setup root'
            value = credential()
            cred, guest = f.base / 'credential.json', f.base / 'guest.json'
            atomic_json(cred, value)
            atomic_json(guest, {'schema': 1, 'identity': value['identity'], 'server_session_id': value['server_session_id'],
                               'guest': {'mc_ws_port': 29001, 'hud_port': 29002, 'mc_server_port': 25567,
                                         'frame_mapping': 'Local\\MCPassthroughFrame-' + value['identity']['mc_uuid']}})
            before = setup_player(root, f.source, f.release1, f.profile, cred, guest, dry_run=True)
            self.assertFalse(root.exists())
            self.assertEqual(before['launch']['mc_uuid'], value['identity']['mc_uuid'])
            self.assertFalse(before['launch']['new_uuid_generated'])
            def runner(argv, **kwargs):
                f.bottle.mkdir(parents=True)
                (f.bottle / 'cxbottle.conf').write_text('fixture')
                (f.bottle / 'dosdevices').mkdir()
                (f.bottle / 'dosdevices/z:').symlink_to('/')
                return subprocess.CompletedProcess(argv, 0, '', '')
            result = setup_player(root, f.source, f.release1, f.profile, cred, guest, bottle_runner=runner)
            self.assertEqual(get_state(root)['profile']['connection']['identity'], value['identity'])
            self.assertEqual(result['game_or_services_started'], [])
            self.assertFalse(result['launch']['java_fabric']['ready'])
            self.assertFalse(result['launch']['actual_player_startup_accepted'])
            self.assertTrue((root / '.palcraft/credentials/credential.json').is_file())
            runtime = json.loads((root / DEV / 'bridge/runtime-config.json').read_text())
            self.assertEqual(runtime['identity'], value['identity'])
            save = root / USER / 'Pal/Saved/SaveGames/fixture.sav'
            save.parent.mkdir(parents=True)
            save.write_bytes(b'USER_SAVE')
            other = f.base / 'second player root'
            public_profile = get_state(root)['profile']
            public_profile.pop('windows_root')
            check = setup_player(other, f.source, f.release1, public_profile, cred, guest,
                                 previous_root=root, fabric_entry='normal-fabric-entry.cmd', dry_run=True)
            self.assertEqual(check['launch']['identity'], value['identity'])
            self.assertTrue(check['launch']['save_migration']['required'])
            self.assertFalse(check['launch']['save_migration']['performed'])
            self.assertFalse(other.exists())
            self.assertEqual(save.read_bytes(), b'USER_SAVE')
        finally:
            f.tearDown()


if __name__ == '__main__':
    unittest.main()
