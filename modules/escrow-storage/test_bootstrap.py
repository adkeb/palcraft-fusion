import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

BASE = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BASE / 'work/minecraft-fusion/palcraft/mcp'))
import escrow_bootstrap as boot
import escrow_rehydrate as rearm
from test_escrow import fixture, CID

WORLD = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
SERVER = Path('D:/PalworldServer-LAN/BridgeLab')


class Bootstrap(unittest.TestCase):
    def setup_boot(self, root):
        lease, saved = fixture()
        lease['status'] = 'claimed'; lease['operations'] = {}
        saved['containers'][CID]['slots'] = {}
        saved['header'] = {'version': 100, 'revision': 102999, 'timestamp': [2026,10,6,3,0,0,100], 'timestamp_ticks': '639000000000000000'}
        level = root / 'installed' / WORLD / 'Level.sav'; level.parent.mkdir(parents=True); level.write_bytes(b'actual-closed-fixture-checkpoint')
        ledger = root / 'exchange'; ledger.mkdir()
        boot.atomic(ledger / 'escrow-leases-current.json', {'protocol':3,'revision':1,'leases':{CID:lease}})
        with patch.object(boot, 'lab_config', return_value=WORLD):
            envelope = boot.prepare(ledger, SERVER, level, stopped_check=lambda _: [], decoder=lambda *_: saved)
        process = {'pid': 1234, 'executable': str(SERVER / boot.EXE_REL), 'process_created_filetime':'134000000000000000',
                   'process_created_unix': envelope['captured_unix'] + .01}
        with patch.object(boot, 'lab_config', return_value=WORLD):
            boot.bind(ledger, SERVER, level, 1234, process_reader=lambda _:process, process_list=lambda _:[1234])
        native = {'protocol':3,'kind':'palworld_process_identity','boot_hex':envelope['boot_id'].replace('-',''),
                  'pid':1234,'thread_id':80,'process_created_filetime':process['process_created_filetime'],'observed_unix':int(time.time()),'read_only':True}
        expected = boot.read(envelope['expected_path']); directory=ledger/'bootstrap'/envelope['boot_id']; rpc=root/'rpc';rpc.mkdir()
        boot.atomic(rpc/('escrow-boot-process-'+envelope['boot_id'].replace('-','')+'.json'),native)
        observation={'protocol':3,'kind':'palworld_loaded_checkpoint_observation','boot_id':envelope['boot_id'],'epoch':envelope['epoch'],
          'observed_unix':int(time.time()),'process_identity':native,'loaded_world_data':True,'all_levels_loaded':True,'uses_backup':False,
          'load_failed_directory':'','world_directory':WORLD,'server_session_id':'actual-fixture-session','header':expected['header'],
          'containers':expected['containers'],'transaction_slots':expected['transaction_slots']}
        boot.atomic(directory/'loaded.json',observation)
        return ledger, level, rpc, envelope, process, observation

    def test_stopped_capture_new_real_process_loaded_header_inventory_and_slots(self):
        with tempfile.TemporaryDirectory() as d:
            ledger,level,rpc,env,proc,observation=self.setup_boot(Path(d))
            with patch.object(boot,'lab_config',return_value=WORLD):
                cert=boot.finalize(ledger,SERVER,level,1234,rpc,process_reader=lambda _:proc,process_list=lambda _:[1234])
                verify=boot.verifier(ledger,SERVER,level,process_reader=lambda _:proc,process_list=lambda _:[1234])
                self.assertTrue(verify(cert))
                self.assertEqual(cert['loaded_level_sha256'],hashlib.sha256(level.read_bytes()).hexdigest())
                # A later ordinary autosave preserves the sealed actual boot evidence.
                level.write_bytes(b'new-normal-world-save')
                self.assertTrue(verify(cert))
                self.assertFalse(verify({**cert,'pid':9999}))

    def test_running_process_forbids_checkpoint_capture(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'Level.sav';p.write_bytes(b'unchanged')
            with patch.object(boot,'lab_config',return_value=WORLD),self.assertRaisesRegex(ValueError,'stop has not completed'):
                boot.prepare(Path(d)/'ledger',SERVER,p,stopped_check=lambda _:[1234],decoder=lambda *_:{})
            self.assertEqual(p.read_bytes(),b'unchanged')

    def test_incomplete_world_failed_directory_or_wrong_beforeimage_refuses_cert(self):
        for field,value in [('loaded_world_data',False),('all_levels_loaded',False),('load_failed_directory','failed-world'),('world_directory','other'),('transaction_slots',[])]:
            with self.subTest(field=field),tempfile.TemporaryDirectory() as d:
                ledger,level,rpc,env,proc,obs=self.setup_boot(Path(d));obs[field]=value
                boot.atomic(ledger/'bootstrap'/env['boot_id']/'loaded.json',obs)
                with patch.object(boot,'lab_config',return_value=WORLD),self.assertRaises(ValueError):
                    boot.finalize(ledger,SERVER,level,1234,rpc,process_reader=lambda _:proc,process_list=lambda _:[1234])
                self.assertFalse((ledger/'escrow-boot-certificate.json').exists())

    def test_backup_diagnostic_true_with_identical_checkpoint_accepts(self):
        with tempfile.TemporaryDirectory() as d:
            ledger,level,rpc,env,proc,obs=self.setup_boot(Path(d));obs['uses_backup']=True
            boot.atomic(ledger/'bootstrap'/env['boot_id']/'loaded.json',obs)
            with patch.object(boot,'lab_config',return_value=WORLD):
                cert=boot.finalize(ledger,SERVER,level,1234,rpc,process_reader=lambda _:proc,process_list=lambda _:[1234])
                verify=boot.verifier(ledger,SERVER,level,process_reader=lambda _:proc,process_list=lambda _:[1234])
                self.assertTrue(verify(cert))
                self.assertEqual(boot.finalize(ledger,SERVER,level,1234,rpc,process_reader=lambda _:proc,process_list=lambda _:[1234]),cert)
            self.assertIs(boot.read(ledger/'bootstrap'/env['boot_id']/'loaded.json')['uses_backup'],True)

    def test_backup_diagnostic_true_does_not_accept_different_checkpoint(self):
        for field in ['header','containers','transaction_slots']:
            with self.subTest(field=field),tempfile.TemporaryDirectory() as d:
                ledger,level,rpc,env,proc,obs=self.setup_boot(Path(d));obs['uses_backup']=True
                with patch.object(boot,'lab_config',return_value=WORLD):
                    cert=boot.finalize(ledger,SERVER,level,1234,rpc,process_reader=lambda _:proc,process_list=lambda _:[1234])
                    if field=='header':obs[field]={**obs[field],'revision':obs[field]['revision']+1}
                    else:obs[field]=[]
                    boot.atomic(ledger/'bootstrap'/env['boot_id']/'loaded.json',obs)
                    with self.assertRaisesRegex(ValueError,'differs|differ'):
                        boot.finalize(ledger,SERVER,level,1234,rpc,process_reader=lambda _:proc,process_list=lambda _:[1234])
                    self.assertFalse(boot.verifier(ledger,SERVER,level,process_reader=lambda _:proc,process_list=lambda _:[1234])(cert))

    def test_wrong_in_process_pid_creation_and_same_pid_reuse_refused(self):
        with tempfile.TemporaryDirectory() as d:
            ledger,level,rpc,env,proc,obs=self.setup_boot(Path(d))
            changed={**proc,'process_created_filetime':'134000000000000001'}
            with patch.object(boot,'lab_config',return_value=WORLD),self.assertRaisesRegex(ValueError,'process changed'):
                boot.finalize(ledger,SERVER,level,1234,rpc,process_reader=lambda _:changed,process_list=lambda _:[1234])

    def test_real_historical_save_decodes_startup_signature(self):
        data=(BASE/'work/palworld-live/lab/serial-chest-after-Level.sav').read_bytes()
        saved=boot.decode_save(data,BASE/'work/palworld-save-toolkit/python/vendor')
        self.assertEqual(len(boot.container_signature(saved)),1404)
        self.assertEqual(saved['header']['version'],100)
        self.assertEqual(saved['header']['timestamp'],[2026,10,4,17,31,35,783])
        self.assertTrue(saved['header']['real_date_time_ticks'].isdigit())


if __name__=='__main__':unittest.main()
