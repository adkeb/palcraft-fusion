"""Four bounded original-Popen fixtures; every save/native identity is synthetic."""
import copy
import hashlib
import json
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'dependencies'))
import installer, launcher
installer.__path__.insert(0, str(HERE / 'source/installer'))
launcher.__path__.insert(0, str(HERE / 'source/launcher'))
from installer import core, cli
from launcher import runtime, journal_lifecycle as journal


class Boot:
    def __init__(self, crash=True, alive_supervisor=False):
        self.temp = tempfile.TemporaryDirectory(prefix='synthetic-saved-crash-')
        self.root = Path(self.temp.name).resolve() / 'owned player'
        self.root.mkdir(); self.token = '1' * 32
        self.identity = {'world_id': 'A' * 32, 'pal_uid': '22222222-0000-0000-0000-000000000000',
                         'mc_uuid': '11111111-1111-1111-1111-111111111111', 'mc_name': 'Fixture'}
        self.native = {'server_session_id': 'standalone:synthetic-original', 'process_epoch': '1234:134000000000000001',
                       'pid': 1234, 'world_id': self.identity['world_id'], 'pal_uid': self.identity['pal_uid'],
                       'save_boot_id': 'synthetic-save-boot'}
        self.profile = {'root': str(self.root), 'platform': 'crossover', 'pal_entry_mode': 'singleplayer',
            'windows_root': 'Z:/synthetic-owned',
            'connection': {'transport': 'local', 'identity': self.identity, 'server_session_id': self.native['server_session_id']},
            'standalone': {'save_account_directory': '123456789', 'backend_root': str(self.root/'backend')}}
        core.atomic_json(self.root/'.palcraft/owner.json', {'root': str(self.root), 'id': 'b'*32,
                         'kind': 'palcraft-player-owned-root'})
        self.level = self.root/core.USER/'Saved/SaveGames/123456789'/self.identity['world_id']/'Level.sav'
        self.level.parent.mkdir(parents=True); self.level.write_bytes(b'SYNTHETIC_ONLY_POSTSUBMISSION_SAVE')
        self.targets = ('.palcraft/standalone/scope.json', core.TOOLS+'/standalone/mac-runtime-config.json',
                        core.DEV+'/bridge/lab-identity.json')
        self.code_target = core.TOOLS+'/fixture-code.py'
        self.baselines = {
            self.targets[0]: {'kind':'palcraft_standalone_runtime', 'installed_level_path_host':str(self.level),
                'world_directory':self.native['world_id'], 'pal_uid':self.native['pal_uid'],
                'install_root_windows':self.profile['windows_root'], 'configured_for_runtime':False},
            self.targets[1]: {'schema':1, 'configured_for_actual_boot':False,
                'guest_mc_uuid':self.identity['mc_uuid'], 'guest_mc_name':self.identity['mc_name'],
                'feature_jvm_public':{'unchanged':'true'}}, self.targets[2]: {'server_session_id':None}}
        self.state = {'schema':1,'current':'synthetic-v1','history':[],'profile':self.profile,'files':{},
            'manifest':{'files':[{'target':self.code_target,'role':'player_tool','bytes':15,
                'sha256':hashlib.sha256(b'fixture-code-v1').hexdigest()}]}}
        for target,value in self.baselines.items():
            core.atomic_json(self.root/target,value); self.state['files'][target]=core.digest(self.root/target)
        path=self.root/self.code_target;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'fixture-code-v1')
        self.state['files'][self.code_target]=core.digest(path)
        core.atomic_json(self.root/'.palcraft/state.json',self.state)
        committed=self.root/'.palcraft/transactions'/('0'*32)
        for target,value in self.baselines.items():core.atomic_json(committed/'generated'/target,value)
        core.atomic_json(committed/'journal.json',{'id':'0'*32,'phase':'committed','before_state':copy.deepcopy(self.state),'changes':[]})
        started=time.time()-10
        self.owner=SimpleNamespace(root=self.root,token=self.token,children={},session={'token':self.token,'started_unix':started})
        self.life=journal.NormalLifecycle(self.owner,quiet_seconds=.001)
        self.processes=[]
        def spawn(exit_code,sleep):
            p=subprocess.Popen([sys.executable,'-c',f'import time,sys;time.sleep({sleep});sys.exit({exit_code})'])
            self.processes.append(p);record={'pid':p.pid,'identity':runtime.process_identity(p.pid)}
            assert record['identity'];return p,record
        self.supervisor,supervisor_record=spawn(0,2 if alive_supervisor else .06)
        client,client_record=spawn(3 if crash else 0,.08)
        self.life.register('client',client_record);self.owner.children['client']=client
        client.wait(timeout=3)
        if not alive_supervisor:self.supervisor.wait(timeout=3)
        self.life.scope['native_scope']=self.native
        if not crash:self.life.scope['normal_title_observed']={'action':'observe_title','token':self.token,
            'process_epoch':self.native['process_epoch'],'request_id':'2'*32,'observed_unix':int(time.time())}
        self.life.save_scope()
        self.sp=lambda name:journal._scope_path(self.root,self.token,name)
        core.atomic_json(self.sp('stop-request.json'),{'token':self.token,'root_id':'b'*32,'force':False})
        save_id='33333333-3333-3333-3333-333333333333';submitted=time.time()-2
        expected={'protocol':3,'id':save_id,'world_directory':self.native['world_id'],'pal_uid':self.native['pal_uid']}
        core.atomic_json(self.sp('save-request.json'),{'request':expected,'submitted_unix':submitted})
        exchange=self.root/core.DEV/'bridge/exchange'
        for revision,status in [(1,'normal_save_intent'),(2,'normal_save_requested')]:
            row=dict(expected,revision=revision,status=status,boot_id=self.native['save_boot_id'])
            path=exchange/f'pal-client-save-{save_id}.r{revision:06d}.json'
            core.atomic_json(path,row);core.atomic_json(path.with_suffix('.durable.json'),row)
        self.wal=exchange/f'pal-client-save-{save_id}.r000002.json'
        stat=journal.file_identity(self.level)
        self.witness={'normal_save_id':save_id,'level_mtime':stat['mtime_ns']/1e9,'level_bytes':stat['bytes'],
            'level_sha256':core.digest(self.level),'after_submission':True,'stable':True,'normal_save_completed':True,
            'native_scope':self.native,'save_request_durable_sha256':core.digest(self.wal)}
        self.life.save_witness=self.witness;core.atomic_json(self.sp('normal-save-file-witness.json'),self.witness)
        for action in (('return_title',) if crash else ('return_title','observe_title','quit_title')):
            value={'action':action,'token':self.token,'process_epoch':self.native['process_epoch'],
                   'request_id':'2'*32,'observed_unix':int(time.time())}
            core.atomic_json(self.sp(action+'-request.json'),{'request_id':value['request_id'],'submitted_unix':submitted})
            core.atomic_json(self.sp(action+'-observation.json'),{'ok':True,'result':value})
        self.host={'schema':1,'phase':'failed' if crash else 'stopped','exit_code':3 if crash else 0,
                   'primary_pid':self.native['pid'],'primary_alive':False,'job_active_processes':0}
        core.atomic_json(self.root/'.palcraft/control'/f'{self.token}.host.json',self.host)
        self.event=self.root/journal.EVENTS;self.event.parent.mkdir(parents=True,exist_ok=True)
        self.event.write_bytes(b'SYNTHETIC_ONLY_ORIGINAL_EVENT_VOLUME\n')
        with patch.object(runtime,'_port_free',return_value=False):self.pending=self.life.finish('failed' if crash else 'stopped')
        self.session={'token':self.token,'phase':'failed' if crash else 'stopped','code':'CLIENT_EXIT' if crash else None,
            'normal_stop_stage':'observe_title' if crash else 'await_native_exit','supervisor':supervisor_record,
            'started_unix':started,'journal_lifecycle':self.pending}
        core.atomic_json(self.root/'.palcraft/session.json',self.session)
        scope=copy.deepcopy(self.baselines[self.targets[0]])
        scope.update(configured_for_runtime=True,client_log_windows=self.profile['windows_root']+'/'+core.BIN+'ue4ss/UE4SS.log')
        config=copy.deepcopy(self.baselines[self.targets[1]]);config['configured_for_actual_boot']=True
        lab={'realm_mode':'standalone','world_directory':self.native['world_id'],'host_uid':self.native['pal_uid'],
            'server_session_id':self.native['server_session_id'],'process_epoch':self.native['process_epoch'],'observed_unix':int(time.time())}
        for target,value in zip(self.targets,(scope,config,lab)):core.atomic_json(self.root/target,value)
        scope['configured_for_runtime']=False;config['configured_for_actual_boot']=False
        self.desired={self.targets[0]:(json.dumps(scope)+'\n').encode(),self.targets[1]:(json.dumps(config)+'\n').encode(),
                      self.targets[2]:(json.dumps({'server_session_id':self.native['server_session_id']})+'\n').encode()}
        self.release=self.root/'synthetic-release';code=self.release/self.code_target
        code.parent.mkdir(parents=True);code.write_bytes(b'fixture-code-v1')
    def close(self):
        for child in self.processes:child.wait(timeout=4)
        self.temp.cleanup()


class SavedCrash(unittest.TestCase):
    def setUp(self):self.boots=[];self.ports=patch.object(runtime,'_port_free',return_value=True);self.ports.start()
    def tearDown(self):
        self.ports.stop()
        for boot in self.boots:boot.close()
    def boot(self,**kwargs):
        b=Boot(**kwargs);self.boots.append(b);return b
    def test_normal_zero_Title_requirements_remain_and_normal_kind_unchanged(self):
        b=self.boot(crash=False)
        with self.assertRaises(core.PlayerError):journal.finalize_saved_crash(b.root,quiet_seconds=.001)
        original=b.life.scope['normal_title_observed'];scope=core.read_json(b.sp('scope.json'));scope.pop('normal_title_observed')
        core.atomic_json(b.sp('scope.json'),scope)
        with self.assertRaises(core.PlayerError):journal.finalize_stop(b.root,quiet_seconds=.001)
        scope['normal_title_observed']=original;core.atomic_json(b.sp('scope.json'),scope)
        result=journal.finalize_stop(b.root,quiet_seconds=.001);receipt=core.read_json(result['normal_stop_receipt'])
        self.assertEqual(receipt['kind'],'palcraft-owned-normal-stop-v1');self.assertIs(receipt['normal_title_Quit_and_native_exit0'],True)
        self.assertFalse(b.sp(journal.SAVED_CRASH_RECEIPT).exists())
    def test_actual_wait_three_saved_off_is_distinct_then_original_three_data_transaction_and_rotator(self):
        b=self.boot();paths=[b.level,b.wal,b.event,b.sp('scope.json'),b.root/'.palcraft/session.json']
        before={path:(path.read_bytes(),path.stat().st_mtime_ns) for path in paths}
        with self.assertRaises(core.PlayerError):journal.finalize_stop(b.root,quiet_seconds=.001)
        dry=journal.finalize_saved_crash(b.root,dry_run=True,quiet_seconds=.001)
        self.assertTrue(dry['ok']);self.assertFalse(b.sp(journal.SAVED_CRASH_RECEIPT).exists())
        result=journal.finalize_saved_crash(b.root,quiet_seconds=.001);receipt=core.read_json(result['saved_crash_off_receipt'])
        self.assertEqual(receipt['kind'],journal.SAVED_CRASH_KIND);self.assertIs(receipt['normal_title_Quit_and_native_exit0'],False)
        self.assertEqual(receipt['client_exit_code'],3);self.assertEqual(receipt['host_observation'],b.host)
        self.assertEqual(receipt['actor_exits'],b.pending['actor_exits']);self.assertFalse(b.sp('normal-stop-receipt.json').exists())
        self.assertEqual({path:(path.read_bytes(),path.stat().st_mtime_ns) for path in paths},before)
        self.assertEqual(cli.make_parser().parse_args(['finalize-saved-crash','--root',str(b.root)]).command,'finalize-saved-crash')
        preserved=journal._persistent_inventory(b.root)
        core._apply(b.root,b.release,copy.deepcopy(core.get_state(b.root)),b.desired)
        transaction=next(core.read_json(p) for p in (b.root/'.palcraft/transactions').glob('*/journal.json') if 'normal_generated_adoption' in core.read_json(p))
        adoption=transaction['normal_generated_adoption']
        self.assertEqual(set(adoption['targets']),set(b.targets));self.assertIn('saved_crash_off_receipt_sha256',adoption)
        self.assertNotIn('normal_stop_receipt_sha256',adoption);self.assertEqual(journal._persistent_inventory(b.root),preserved)
        event_sha=core.digest(b.event);plan=journal.prepare_cold_boot(b.root,dry_run=True)
        self.assertTrue(plan['ok']);rotation=journal.prepare_cold_boot(b.root)
        self.assertEqual(core.digest(Path(rotation['archive'])),event_sha)
        self.assertEqual(journal._persistent_inventory(b.root),preserved)
        self.assertEqual(core.read_json(b.root/'.palcraft/session.json')['phase'],'failed')
    def test_unfinished_save_cannot_issue_saved_crash_receipt(self):
        b=self.boot();witness=copy.deepcopy(b.witness);witness['normal_save_completed']=False
        core.atomic_json(b.sp('normal-save-file-witness.json'),witness)
        pending=copy.deepcopy(b.pending);pending['normal_save_witness']=witness
        core.atomic_json(b.sp('incomplete-stop.json'),pending);session=copy.deepcopy(b.session);session['journal_lifecycle']=pending
        core.atomic_json(b.root/'.palcraft/session.json',session)
        with self.assertRaises(core.PlayerError):journal.finalize_saved_crash(b.root,quiet_seconds=.001)
        self.assertFalse(b.sp(journal.SAVED_CRASH_RECEIPT).exists())
    def test_real_owned_supervisor_still_alive_cannot_issue_or_signal(self):
        b=self.boot(alive_supervisor=True);self.assertIsNone(b.supervisor.poll())
        with self.assertRaises(core.PlayerError) as caught:journal.finalize_saved_crash(b.root,quiet_seconds=.001)
        self.assertEqual(caught.exception.code,'JOURNAL_ACTOR_ALIVE');self.assertIsNone(b.supervisor.poll())
        self.assertFalse(b.sp(journal.SAVED_CRASH_RECEIPT).exists())


if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SavedCrash))
    receipt={'schema':1,'passed':result.wasSuccessful(),'tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),
        'actual_created_Popen_wait_exit3_used':True,'all_world_Save_WAL_native_host_inputs_synthetic_temporary':True,
        'normal_Title_exit0_requirements_retained':True,'distinct_saved_crash_kind_and_failed_phase_retained':True,
        'original_apply_three_targets_and_original_named_rotator_used':True,'actual_root_Save_credentials_Game_SDK_GUI_RPC_Git_or_restart_used':False,
        'source_pins':{str(p.relative_to(HERE)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((HERE/'source').rglob('*.py'))}}
    print(json.dumps(receipt,indent=2))
    raise SystemExit(0 if result.wasSuccessful() else 1)
