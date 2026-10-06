import io
import json
import sys
import unittest
import zipfile
from pathlib import Path
from PIL import Image
BASE=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(BASE))
import test_player_tools as fixtures
from installer.core import atomic_json,digest,get_state,DEV
from installer.resources import prepare_resources

class ResourceTests(unittest.TestCase):
    def setUp(self):
        self.fixture=fixtures.PlayerTests(methodName='test_dry_run_has_no_files_or_network_or_processes')
        self.fixture.setUp();self.fixture.installed()
    def tearDown(self):self.fixture.tearDown()
    def test_real_converter_from_personal_tiny_jar(self):
        f=self.fixture;state=get_state(f.root)
        entry=next(x for x in state['manifest']['files'] if x['role']=='model_processor')
        source=BASE/'native/prepare_models_v2.py';target=f.root/entry['target']
        target.write_bytes(source.read_bytes());entry['sha256']=digest(target);entry['bytes']=target.stat().st_size
        state['files'][entry['target']]=entry['sha256'];atomic_json(f.root/'.palcraft/state.json',state)
        image=Image.new('RGBA',(16,16),(100,150,200,255));png=io.BytesIO();image.save(png,format='PNG')
        jar=f.base/'personal-fixture-client.jar'
        with zipfile.ZipFile(jar,'w') as archive:
            archive.writestr('version.json','{"id":"26.3"}')
            archive.writestr('assets/minecraft/blockstates/stone.json','{"variants":{"":{"model":"minecraft:block/stone"}}}')
            archive.writestr('assets/minecraft/models/block/stone.json',json.dumps({'textures':{'all':'minecraft:block/stone'},'elements':[{'from':[0,0,0],'to':[16,16,16],'faces':{'north':{'texture':'#all'}}}]}))
            archive.writestr('assets/minecraft/textures/block/stone.png',png.getvalue())
        before=digest(jar)
        self.assertTrue(prepare_resources(f.root,jar,dry_run=True)['dry_run'])
        self.assertFalse((f.root/DEV/'bridge/models').exists())
        result=prepare_resources(f.root,jar)
        self.assertEqual(result['models'],1);self.assertEqual(result['textures'],1)
        self.assertEqual(digest(jar),before)
        self.assertTrue((f.root/DEV/'bridge/models/textures/minecraft/block/stone.png').exists())
        self.assertFalse(any(p.suffix=='.jar' for p in (f.root/DEV/'bridge/models').rglob('*')))
