"""One player lifecycle through an arbitrary Unicode directory; never starts a game."""
import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
from test_player_tools import PlayerTests
from installer.core import (CLIENT, DEV, USER, PlayerError, atomic_json, digest,
                            get_state, install, uninstall, validate_profile)
from installer.paths import normalize_windows_root, windows_path, windows_root
from installer.packaging import build_release
from launcher.runtime import Session, command_plan, create_bottle

EVIDENCE = {}


class PortablePathFlow(PlayerTests):
    def test_unicode_directory_lifecycle_without_drive_d(self):
        self.root = self.base / '玩家 安装' / 'PalCraft 自选目录'
        source_before = {str(p.relative_to(self.source)): digest(p) for p in self.source.rglob('*') if p.is_file()}
        win = windows_root(r'c:\Games\玩家 PalCraft', {'platform': 'windows'})
        self.assertEqual(win, 'C:/Games/玩家 PalCraft')
        self.assertEqual(windows_path(win, '.palcraft/control'), 'C:\\Games\\玩家 PalCraft\\.palcraft\\control')
        with self.assertRaises(ValueError):
            normalize_windows_root('/Users/player/PalCraft')
        with self.assertRaises(ValueError):
            normalize_windows_root('C:/Games/../production')
        preview = install(self.root, self.source, self.release1, self.profile, dry_run=True)
        self.assertFalse(self.root.exists())
        self.assertEqual(preview['client_journal_dir'], str(self.root / 'BridgeLab/rpc'))
        expected = 'Z:' + self.root.as_posix()
        self.assertEqual(preview['profile']['windows_root'], expected)
        install(self.root, self.source, self.release1, self.profile)
        journal = self.root / 'BridgeLab/rpc/palcraft-events.ndjson'
        self.assertTrue(journal.parent.is_dir())
        journal.write_bytes(b'LOCAL_NATIVE_JOURNAL_FIXTURE')
        self.assertEqual(get_state(self.root)['profile']['windows_root'], expected)
        state = get_state(self.root)
        bundle_targets = {f['target'] for f in state['manifest']['files']}
        self.assertIn('PalCraft-Dev/player-tools/installer/paths.py', bundle_targets)
        self.assertIn('PalCraft-Dev/player-tools/launcher/windows_paths.hpp', bundle_targets)

        # The fake cxbottle runner models CrossOver's existing standard Z: mapping.
        # The launcher itself creates or retargets no DOS device.
        calls = []
        def runner(argv, **kwargs):
            calls.append(argv)
            self.bottle.mkdir(parents=True)
            (self.bottle / 'cxbottle.conf').write_text('fixture')
            (self.bottle / 'dosdevices').mkdir()
            (self.bottle / 'dosdevices/z:').symlink_to('/')
            return subprocess.CompletedProcess(argv, 0, '', '')
        bottle_result = create_bottle(self.root, runner=runner)
        self.assertFalse((self.bottle / 'dosdevices/d:').exists())
        self.assertFalse(bottle_result['mapping_changed'])
        protected = self.base / '别的磁盘'
        protected.mkdir()
        (self.bottle / 'dosdevices/d:').symlink_to(protected)
        create_bottle(self.root, runner=runner)
        self.assertEqual(len(calls), 1)
        self.assertEqual((self.bottle / 'dosdevices/d:').resolve(), protected)

        token = 'a' * 32
        plan = command_plan(self.root, token)
        command = plan['commands']['client']
        self.assertEqual(command[command.index('--root') + 1], windows_path(expected))
        self.assertEqual(command[command.index('--control') + 1], windows_path(expected, '.palcraft/control'))
        self.assertEqual(command[command.index('--workdir') + 1], windows_path(expected, CLIENT))
        self.assertEqual(command.count('--env'), 1)
        self.assertEqual(plan['environment']['PALCRAFT_WINDOWS_ROOT'], expected)
        # Resolve the actual logical Windows argument through the bottle's Z:.
        mapped = (self.bottle / 'dosdevices/z:').resolve() / command[command.index('--root') + 1][3:].replace('\\', '/')
        self.assertEqual(mapped, self.root)

        atomic_json(self.root / '.palcraft/session.json', {'schema': 1, 'token': token, 'phase': 'starting', 'components': {}})
        (self.root / '.palcraft/logs').mkdir()
        with patch('launcher.runtime.process_identity', return_value='fixture'), \
             patch('launcher.runtime.subprocess.Popen', return_value=SimpleNamespace(pid=99999)) as popen:
            session = Session(self.root, token)
            session.spawn('client')
            env = popen.call_args.kwargs['env']
            self.assertEqual(env['PALCRAFT_WINDOWS_ROOT'], expected)
            self.assertEqual(env['PALCRAFT_BRIDGE_DIR'], windows_path(expected, DEV + '/bridge'))
            session.spawn('hud')
            self.assertEqual(popen.call_args.kwargs['env']['PALCRAFT_BRIDGE_DIR'], str(self.root / DEV / 'bridge'))
            for stream in session.outputs:
                stream.close()
        atomic_json(self.root / '.palcraft/session.json', {'schema': 1, 'phase': 'stopped'})

        save = self.root / USER / 'Pal/Saved/SaveGames/玩家.sav'
        save.parent.mkdir(parents=True)
        save.write_bytes(b'PLAYER_SAVE')
        untracked = self.root / DEV / 'bridge/notes.txt'
        untracked.write_bytes(b'USER_NOTES')
        result = uninstall(self.root)
        self.assertTrue(result['saves_preserved'])
        self.assertEqual(save.read_bytes(), b'PLAYER_SAVE')
        self.assertEqual(untracked.read_bytes(), b'USER_NOTES')
        self.assertEqual(journal.read_bytes(), b'LOCAL_NATIVE_JOURNAL_FIXTURE')
        self.assertEqual(source_before, {str(p.relative_to(self.source)): digest(p) for p in self.source.rglob('*') if p.is_file()})
        self.assertTrue(self.bottle.exists())
        self.assertEqual((self.bottle / 'dosdevices/d:').resolve(), protected)

        # A frozen old D-only release is refused before it can copy any game.
        spec = json.loads((self.base / 'v1-spec.json').read_text())
        spec['version'] = 'legacy'
        spec['requirements'].pop('path_contract')
        spec['requirements'].pop('lua_path_encoding')
        legacy_spec = self.base / 'legacy-spec.json'
        atomic_json(legacy_spec, spec)
        legacy = self.base / 'legacy.zip'
        build_release(legacy_spec, legacy)
        untouched = self.base / '新玩家 无D盘'
        with self.assertRaises(PlayerError) as error:
            install(untouched, self.source, legacy, self.profile, dry_run=True)
        self.assertEqual(error.exception.code, 'PATH_CONTRACT')
        self.assertFalse(untouched.exists())
        EVIDENCE.update({'windows_root': win, 'crossover_windows_root': expected,
                         'no_d_mapping_created': True, 'existing_d_mapping_unchanged': True,
                         'source_game_and_save_unchanged': True, 'player_save_preserved': True,
                         'untracked_files_preserved': True, 'legacy_release_refused_before_write': True,
                         'native_windows_bridge_env_is_logical_path': True,
                         'client_spawn_mocked': True, 'server_mutations': []})
