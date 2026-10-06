import importlib.util
import json
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path
BASE=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(BASE))
from launcher.session_proxy import SessionProxy
from test_sessions import credential, protocol

class MirrorTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='palcraft-mirror-test-')
        self.root=Path(self.temp.name).resolve()
        self.value=credential()
        self.proxy=SessionProxy(self.value,protocol,self.root/'status.json')
        self.lease=protocol.HostSession(self.value)
        public=protocol.inspect_grant(self.value['grant'])
        self.lease.bound({'t':'bound','session':{**public['identity'],'v':2,'legacy':False,
            'server_session_id':public['server_session_id'],'session_id':str(uuid.uuid4()),'generation':1,'expires_at':public['expires_at']}})
    def tearDown(self):self.temp.cleanup()
    def snapshot(self,kind='entity_snapshot',authority='mc_server'):
        return {'t':kind,'v':1,'authority':authority,'session':self.value['server_session_id'],'unix':time.time(),'entities':[]}
    def test_authenticated_snapshot_mirrored_then_marked_stale(self):
        self.proxy.mirror_event(self.snapshot(),self.lease)
        self.proxy.mirror_event(self.snapshot('pal_entity_snapshot','pal_server'),self.lease)
        self.assertEqual(json.loads((self.root/'entities/pal-state.json').read_text())['t'],'entity_snapshot')
        meta=json.loads((self.root/'entities/binding-meta.json').read_text())
        self.assertEqual(meta['host_session_id'],self.lease.session['session_id'])
        self.proxy.mark_mirrors_stale()
        self.assertTrue(json.loads((self.root/'entities/mc-state.json').read_text())['stale'])
        self.assertEqual(json.loads((self.root/'entities/pal-state.json').read_text())['unix'],0)
    def test_wrong_authority_never_creates_mailbox(self):
        with self.assertRaises(ValueError):self.proxy.mirror_event(self.snapshot(authority='client'),self.lease)
        self.assertFalse((self.root/'entities').exists())
    def test_other_pal_boot_never_creates_mailbox(self):
        row=self.snapshot();row['session']='another-pal-boot'
        with self.assertRaises(ValueError):self.proxy.mirror_event(row,self.lease)
        self.assertFalse((self.root/'entities').exists())
    def test_vitals_other_player_rejected(self):
        row=self.snapshot('player_vitals','pal_server');row['mc_uuid']=str(uuid.uuid4())
        with self.assertRaises(ValueError):self.proxy.mirror_event(row,self.lease)
        self.assertFalse((self.root/'player-vitals.json').exists())
