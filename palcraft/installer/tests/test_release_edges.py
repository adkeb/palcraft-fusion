import json
import sys
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch
BASE=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(BASE))
import installer.core as core
import test_player_tools as fixtures
from installer.packaging import build_release

class ReleaseEdgeTests(unittest.TestCase):
    def setUp(self):
        self.fixture=fixtures.PlayerTests(methodName='test_dry_run_has_no_files_or_network_or_processes')
        self.fixture.setUp()
    def tearDown(self):self.fixture.tearDown()
    def test_initial_copy_crash_after_directory_publish_is_reentrant(self):
        real_replace=core.os.replace
        triggered=[]
        def crash_after_copy(source,target):
            result=real_replace(source,target)
            if Path(target)==self.fixture.root/core.CLIENT and not triggered:
                triggered.append(True);raise SystemExit(97)
            return result
        with patch.object(core.os,'replace',crash_after_copy):
            with self.assertRaises(SystemExit):
                core.install(self.fixture.root,self.fixture.source,self.fixture.release1,self.fixture.profile)
        self.assertTrue((self.fixture.root/'.palcraft/base-copy.pending.json').exists())
        self.assertEqual(core.install(self.fixture.root,self.fixture.source,self.fixture.release1,self.fixture.profile)['version'],'v1')
        self.assertFalse((self.fixture.root/'.palcraft/base-copy.pending.json').exists())
    def test_profile_rejects_embedded_private_key_before_any_write(self):
        profile=json.loads(json.dumps(self.fixture.profile));profile['connection']['host_secret']='PRIVATE_KEY'
        with self.assertRaises(core.PlayerError) as err:
            core.install(self.fixture.root,self.fixture.source,self.fixture.release1,profile)
        self.assertEqual(err.exception.code,'CONFIG_SECRET');self.assertFalse(self.fixture.root.exists())
    def jar_bundle(self, copyrighted):
        mod=self.fixture.base/'mod.jar'
        with zipfile.ZipFile(mod,'w') as jar:
            jar.writestr('fabric.mod.json','{"id":"passthrough"}')
            jar.writestr('net/minecraft/client/Minecraft.class' if copyrighted else 'dev/rehan/passthrough/Own.class',b'fixture only')
        spec=json.loads((self.fixture.base/'v1-spec.json').read_text())
        spec['files'].append({'source':str(mod),'target':core.DEV+'/minecraft-mods/passthrough-test.jar','role':'minecraft_mod'})
        path=self.fixture.base/'mod-spec.json';core.atomic_json(path,spec)
        output=self.fixture.base/'mod-release.zip';build_release(path,output)
        return output
    def test_own_fabric_mod_can_ship(self):self.assertTrue(core.Bundle(self.jar_bundle(False)).manifest['files'])
    def test_minecraft_game_classes_cannot_ship(self):
        with self.assertRaises(core.PlayerError) as err:self.jar_bundle(True)
        self.assertEqual(err.exception.code,'BUNDLE_COPYRIGHT')
