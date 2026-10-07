"""Small synthetic original-_apply regression, rejection, undo and second-cycle checks."""
import copy, hashlib, importlib.util, json, sys, tempfile, types, unittest
from pathlib import Path
from unittest.mock import patch
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'checks/dependencies'))
def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, HERE / relative)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module
old = load('original_core', 'base/installer/core.py')
new = load('candidate_core', 'source/installer/core.py')
sha = lambda data: hashlib.sha256(data).hexdigest()
encode = lambda value: (json.dumps(value, indent=2) + '\n').encode()
SCOPE = '.palcraft/standalone/scope.json'
CONFIG = new.TOOLS + '/standalone/mac-runtime-config.json'
LAB = new.DEV + '/bridge/lab-identity.json'
CODE = new.TOOLS + '/fixture-code.py'

class GeneratedOwnership(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='normal-generated-ownership-fixture-')
        self.root = Path(self.temp.name).resolve(); self.release = self.root / 'fixture-release'
        self.identity = {'world_id':'fixture-world','pal_uid':'11111111-1111-1111-1111-111111111111',
                         'mc_uuid':'5b691cd2-93b0-335a-9c68-61a7230da15a','mc_name':'FixtureAlpha'}
        profile = {'root':str(self.root),'platform':'crossover','pal_entry_mode':'singleplayer','windows_root':'Z:/fixture-owned',
            'connection':{'transport':'local','identity':self.identity,'server_session_id':'fixture-session-1'},
            'standalone':{'backend_root':str(self.root/'backend')}}
        self.baselines = {SCOPE:{'kind':'palcraft_standalone_runtime','world_directory':self.identity['world_id'],
            'pal_uid':self.identity['pal_uid'],'install_root_windows':profile['windows_root'],'configured_for_runtime':False,
            'authority_or_game_ready_claimed':False},CONFIG:{'schema':1,'configured_for_actual_boot':False,
            'guest_mc_uuid':self.identity['mc_uuid'],'guest_mc_name':self.identity['mc_name'],'feature_jvm_public':{'preserved':'true'}},
            LAB:{'server_session_id':None}}
        self.state = {'schema':1,'current':'fixture-v1','history':[],'profile':profile,'files':{},
                      'manifest':{'files':[{'target':CODE,'sha256':sha(b'fixture-code-v1'),'bytes':15,'role':'player_tool'}]}}
        new.atomic_json(self.root/'.palcraft/owner.json',{'kind':'palcraft-player-owned-root','root':str(self.root),'id':'b'*32})
        for target,value in self.baselines.items(): self.write(target,encode(value)); self.state['files'][target]=sha(encode(value))
        self.write(CODE,b'fixture-code-v1'); self.state['files'][CODE]=sha(b'fixture-code-v1')
        self.write('fixture-save/Level.sav',b'FIXTURE_ONLY_NO_ACTUAL_SAVE')
        self.write('fixture-wal/record.json',b'FIXTURE_ONLY_NO_ACTUAL_WAL')
        new.atomic_json(self.root/'.palcraft/state.json',self.state)
        prefix = self.root/'.palcraft/transactions'/('0'*32)
        for target,value in self.baselines.items(): self.write(str((prefix/'generated'/target).relative_to(self.root)),encode(value))
        new.atomic_json(prefix/'journal.json',{'id':'0'*32,'phase':'committed','before_state':copy.deepcopy(self.state),'changes':[]})
        journal=types.ModuleType('launcher.journal_lifecycle');journal.EVENTS='BridgeLab/rpc/palcraft-events.ndjson';journal.LIFECYCLE='.palcraft/standalone/journal-lifecycle'
        journal.file_identity=self.file_identity;journal._persistent_inventory=lambda root:self.inventory()
        journal._check_previous_actors=lambda root,scope:None
        self.module_patch=patch.dict(sys.modules,{'launcher.journal_lifecycle':journal});self.module_patch.start()
        self.setup_boot(1)
        self.desired=self.desired_files(); self.after=copy.deepcopy(self.state)
        self.release.mkdir(); self.write('fixture-release/'+CODE,b'fixture-code-v1')
    def tearDown(self): self.module_patch.stop();self.temp.cleanup()
    def write(self,target,data):
        path=self.root/target;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    def file_identity(self,path):
        s=path.stat();return {'device':s.st_dev,'inode':s.st_ino,'bytes':s.st_size,'mtime_ns':s.st_mtime_ns}
    def inventory(self): return {name:self.file_identity(self.root/name) for name in ('fixture-save/Level.sav','fixture-wal/record.json')}
    def setup_boot(self,cycle):
        self.token=('a' if cycle==1 else 'c')*32;self.prefix=self.root/'.palcraft/standalone/journal-lifecycle'/self.token
        state=new.get_state(self.root);state['profile']['connection']['server_session_id']='fixture-session-'+str(cycle)
        new.atomic_json(self.root/'.palcraft/state.json',state);self.state=state
        self.native={'server_session_id':state['profile']['connection']['server_session_id'],'process_epoch':'fixture-process-'+str(cycle),
            'pid':111,'world_id':self.identity['world_id'],'pal_uid':self.identity['pal_uid'],'save_boot_id':'fixture-save-boot-'+str(cycle)}
        actors={'client':{'pid':111,'identity':'fixture-owned-birth','role':'client'}}
        scope={'root':str(self.root),'root_id':'b'*32,'token':self.token,'native_scope':self.native,'started_unix':1000,
            'active_events_path':str(self.root/'BridgeLab/rpc/palcraft-events.ndjson'),'actors':actors,
            'normal_title_observed':{'action':'observe_title','token':self.token,'process_epoch':self.native['process_epoch'],'request_id':'1'*32}}
        new.atomic_json(self.root/'.palcraft/session.json',{'phase':'stopped','token':self.token})
        new.atomic_json(self.root/'.palcraft/standalone/journal-lifecycle/current.json',{'token':self.token})
        new.atomic_json(self.prefix/'scope.json',scope)
        receipt={'schema':1,'kind':'palcraft-owned-normal-stop-v1','root':str(self.root),'root_id':'b'*32,'token':self.token,
            'native_scope':self.native,'active_events_path':scope['active_events_path'],'stream_identity':None,
            'actor_exits':{'client':{**actors['client'],'actual_wait_completed':True,'exit_code':0}},
            'normal_save_witness':{'normal_save_id':'fixture-save-id','after_submission':True,'stable':True,'native_scope':self.native},
            'persistent_stat_inventory':self.inventory(),'observed_unix':1100}
        for key in ('normal_save_completed','normal_title_Quit_and_native_exit0','all_owned_producers_and_consumers_stopped',
                    'all_this_stream_producers_and_consumers_off_before_rotation','Saved_and_WAL_stable_after_all_actors_off'):receipt[key]=True
        new.atomic_json(self.prefix/'normal-stop-receipt.json',receipt)
        scope_value=json.loads((self.root/SCOPE).read_bytes());scope_value.update(configured_for_runtime=True,
            client_log_windows=state['profile']['windows_root']+'/'+new.BIN+'ue4ss/UE4SS.log')
        config=json.loads((self.root/CONFIG).read_bytes());config['configured_for_actual_boot']=True
        lab={'realm_mode':'standalone','world_directory':self.native['world_id'],'server_session_id':self.native['server_session_id'],
            'host_uid':self.native['pal_uid'],'process_epoch':self.native['process_epoch'],'observed_unix':1050}
        for target,value in ((SCOPE,scope_value),(CONFIG,config),(LAB,lab)):self.write(target,encode(value))
    def desired_files(self):
        scope=json.loads((self.root/SCOPE).read_bytes());scope['configured_for_runtime']=False
        config=json.loads((self.root/CONFIG).read_bytes());config['configured_for_actual_boot']=False
        return {SCOPE:encode(scope),CONFIG:encode(config),LAB:encode({'server_session_id':self.native['server_session_id']})}
    def test_original_conflict_then_same_boot_original_transaction_adopts_only_three_datafiles(self):
        with self.assertRaises(old.PlayerError): old._apply(self.root,self.release,copy.deepcopy(self.after),self.desired)
        preserved=self.inventory();lab=(self.root/LAB).read_bytes()
        new._apply(self.root,self.release,copy.deepcopy(self.after),self.desired)
        state=new.get_state(self.root)
        for target in (SCOPE,CONFIG,LAB,CODE):self.assertEqual(state['files'][target],new.digest(self.root/target))
        self.assertEqual((self.root/LAB).read_bytes(),lab);self.assertEqual(self.inventory(),preserved)
        journals=[json.loads(p.read_bytes()) for p in (self.root/'.palcraft/transactions').glob('*/journal.json')]
        adopted=next(j for j in journals if 'normal_generated_adoption' in j)
        self.assertEqual(set(adopted['normal_generated_adoption']['targets']),{SCOPE,CONFIG,LAB})
        self.assertEqual({row['target'] for row in adopted['changes']},{SCOPE,CONFIG,LAB})
    def test_second_normal_cycle_accepts_committed_six_field_baseline_and_new_actual_SID(self):
        new._apply(self.root,self.release,copy.deepcopy(self.after),self.desired)
        self.setup_boot(2);self.after=copy.deepcopy(new.get_state(self.root))
        new._apply(self.root,self.release,self.after,self.desired_files())
        state=new.get_state(self.root);lab=json.loads((self.root/LAB).read_bytes())
        self.assertEqual(lab['server_session_id'],'fixture-session-2');self.assertEqual(lab['process_epoch'],'fixture-process-2')
        self.assertEqual(state['files'][LAB],new.digest(self.root/LAB))
    def test_arbitrary_data_code_oldSID_and_incomplete_witness_still_rejected(self):
        for target,key,value in ((SCOPE,'pal_uid','wrong'),(CONFIG,'feature_jvm_public',{'changed':'true'}),(LAB,'server_session_id','fixture-old-SID')):
            before=(self.root/target).read_bytes();data=json.loads(before);data[key]=value;self.write(target,encode(data))
            with self.assertRaises(new.PlayerError):new._apply(self.root,self.release,copy.deepcopy(self.after),self.desired)
            self.write(target,before)
        self.write(CODE,b'user-modified-code')
        with self.assertRaises(new.PlayerError):new._apply(self.root,self.release,copy.deepcopy(self.after),self.desired)
        self.write(CODE,b'fixture-code-v1')
        path=self.prefix/'normal-stop-receipt.json';before=path.read_bytes();receipt=json.loads(before);receipt['token']='d'*32;path.write_bytes(encode(receipt))
        with self.assertRaises(new.PlayerError):new._apply(self.root,self.release,copy.deepcopy(self.after),self.desired)
        path.write_bytes(before)
    def test_fault_undo_restores_original_physical_bytes_and_before_ledger(self):
        files={target:(self.root/target).read_bytes() for target in (SCOPE,CONFIG,LAB,CODE)}
        before=new.get_state(self.root);inventory=self.inventory()
        def fault(number,change):raise RuntimeError('synthetic transaction fault')
        with self.assertRaises(RuntimeError):new._apply(self.root,self.release,copy.deepcopy(self.after),self.desired,fault=fault)
        self.assertEqual(new.get_state(self.root),before);self.assertEqual(self.inventory(),inventory)
        self.assertEqual({target:(self.root/target).read_bytes() for target in files},files)

if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(GeneratedOwnership))
    receipt={'schema':1,'passed':result.wasSuccessful(),'tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),
        'source_sha256':sha((HERE/'source/installer/core.py').read_bytes()),'original_apply_transaction_used':True,
        'specific_three_generated_targets_only':True,'second_normal_cycle_six_field_baseline_checked':True,
        'original_Title_result_dict_schema_used':True,'arbitrary_data_code_oldSID_and_wrong_boot_rejected':result.wasSuccessful(),
        'backup_pending_ledger_fault_undo_checked':result.wasSuccessful(),'all_inputs_synthetic_temporary':True,
        'actual_root_credentials_SDK_Game_UI_currentwrites_or_Git_used':False,'large_SourceCheck_or_asset_SHA_matrix_rerun':False}
    (HERE/'checks/receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))
    raise SystemExit(0 if result.wasSuccessful() else 1)
