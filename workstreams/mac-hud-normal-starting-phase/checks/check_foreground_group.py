"""Three bounded source cases; mocked resolver files/processes, pure Swift selector."""
import ast, copy, hashlib, json, re, subprocess, tempfile, time, unittest
from pathlib import Path
from types import SimpleNamespace
HERE=Path(__file__).resolve().parents[1]
source=HERE/'source/launcher/runtime.py'
node=next(n for n in ast.parse(source.read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='_mac_game_foreground_group')

class OwnedGroup(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='owned-foreground-fixture-');self.root=Path(self.temp.name)
        self.token='a'*32;self.exe='Z:/fixture-owned/Palworld-Win64-Shipping.exe';self.user='Z:/fixture-owned/User'
        self.game_birth=time.strftime('%a %b %d %H:%M:%S %Y',time.localtime(1700000000))
        self.births={101:self.game_birth,202:'fixture-helper-birth'};self.pids='101';self.command=self.exe+' Pal -windowed -UserDir='+self.user+'/ -ExecCmds=t.MaxFPS 60'
        self.scope={'executable_sha256':'fixture-exe','world_directory':'fixture-world','pal_uid':'fixture-uid','pal_exe_windows':self.exe,'private_user_dir_windows':self.user}
        self.record={'ok':True,'result':{'read_only':True,'observed_unix':1700000002,'native_user_dir':self.user+'/',
            'native_process':{'pid':55,'process_created_filetime':str((1700000000+11644473600)*10000000),
            'read_only':True,'native_code_matched':True,'kind':'palworld_client_process_identity','executable_sha256':'fixture-exe'}}}
        self.write('observation.json',self.record)
        self.epoch='55:'+self.record['result']['native_process']['process_created_filetime']
        self.client={'pid':202,'identity':'fixture-helper-birth'}
        self.session={'token':self.token,'phase':'running','started_unix':1700000000,'components':{'client':self.client},
            'native_menu_open':{'state':'returned','returncode':0,'token':self.token,'client':self.client,
            'bundle':str(self.root/'.palcraft/native-menu/PalCraft Game.app'),'bundle_identifier':'fixture.owned.helper'}}
        self.permission={'observation_file':str(self.root/'observation.json'),
            'observation_record_sha256':hashlib.sha256((self.root/'observation.json').read_bytes()).hexdigest(),
            'source':'runtime_owned_normal_load_observation','process_epoch':self.epoch,
            'actual_native_commandline_UserDir_physically_mapped':True,'native_context':{'world_id':'fixture-world','host_uid':'fixture-uid'}}
        self.write('.palcraft/session.json',self.session);self.write('.palcraft/standalone/scope.json',self.scope)
        self.write('.palcraft/standalone/owned-loaded-save-permission.json',self.permission)
        self.write('.palcraft/standalone/journal-lifecycle/'+self.token+'/scope.json',{'token':self.token,'native_scope':{'process_epoch':self.epoch}})
        ns={'Path':Path,'json':json,'re':re,'time':time,'subprocess':subprocess,'PlayerError':RuntimeError,
            'owned_path':lambda r,p:r/p,'read_json':lambda p:json.loads(p.read_bytes()),'process_identity':self.births.get}
        exec(compile(ast.Module(body=[node],type_ignores=[]),'<exact-resolver-source>','exec'),ns)
        self.resolve=ns['_mac_game_foreground_group']
    def tearDown(self):self.temp.cleanup()
    def write(self,name,value):
        path=self.root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value))
    def runner(self,args,**kwargs):return SimpleNamespace(stdout=self.pids if args[0].endswith('pgrep') else self.command,returncode=0)
    def test_normal_producer_binds_unique_owned_Game_and_original_Helper(self):
        # Original promote spawns proxy before HUD; every spawn saves phase=starting.
        # This normal intermediate phase must retain the same valid ownership proof.
        for phase in ('promoting', 'starting', 'running'):
            self.session['phase']=phase;self.write('.palcraft/session.json',self.session)
            group=self.resolve(self.root,self.token,runner=self.runner,identity_reader=self.births.get)
            self.assertEqual((group['game_pid'],group['helper_pid'],group['native_process_epoch']),(101,202,self.epoch))
            self.assertEqual(group['helper_bundle_id'],'fixture.owned.helper')
        self.session['phase']='stopped';self.write('.palcraft/session.json',self.session)
        self.assertIsNone(self.resolve(self.root,self.token,runner=self.runner,identity_reader=self.births.get))
    def test_wrong_UserDir_or_stale_birth_or_ambiguous_Game_fail_closed(self):
        self.command=self.exe+' Pal -UserDir=Z:/other/User/ '
        self.assertIsNone(self.resolve(self.root,self.token,runner=self.runner,identity_reader=self.births.get))
        self.command=self.exe+' Pal -UserDir='+self.user+'/ ';self.births[101]=time.strftime('%a %b %d %H:%M:%S %Y',time.localtime(1699990000))
        self.assertIsNone(self.resolve(self.root,self.token,runner=self.runner,identity_reader=self.births.get))
        self.births[101]=self.game_birth;self.births[102]=self.game_birth;self.pids='101 102'
        self.assertIsNone(self.resolve(self.root,self.token,runner=self.runner,identity_reader=self.births.get))
    def test_exact_Swift_selector_allows_real_group_and_rejects_both_focus_loss_cases(self):
        swift=(HERE/'source/mac/hud_overlay.swift').read_text();start=swift.index('struct MacForegroundGroup:');at=swift.index('{',start);depth=1;end=at+1
        while depth:
            if swift[end]=='{':depth+=1
            if swift[end]=='}':depth-=1
            end+=1
        struct=swift[start:end]
        program='import Foundation\n'+struct+'''\n
let payload = "{\\"version\\":1,\\"token\\":\\"fixture\\",\\"game_pid\\":101,\\"game_identity\\":\\"fixture-game-birth\\",\\"helper_pid\\":202,\\"helper_identity\\":\\"fixture-helper-birth\\",\\"helper_bundle_id\\":\\"fixture.owned.helper\\",\\"helper_bundle\\":\\"/fixture/helper.app\\",\\"native_process_epoch\\":\\"55:fixture-ft\\",\\"own_root\\":\\"/fixture\\",\\"game_exe\\":\\"Z:/fixture/Game.exe\\",\\"private_user_dir\\":\\"Z:/fixture/User\\"}"
let group = try! JSONDecoder().decode(MacForegroundGroup.self, from: payload.data(using: .utf8)!)
assert(group.accepts(ownerPID:101, frontPID:202, frontBundleID:"fixture.owned.helper"))
assert(group.accepts(ownerPID:101, frontPID:101, frontBundleID:nil))
assert(!group.accepts(ownerPID:101, frontPID:999, frontBundleID:"other.app"))
assert(!group.accepts(ownerPID:101, frontPID:202, frontBundleID:"other.helper"))
assert(!group.accepts(ownerPID:999, frontPID:202, frontBundleID:"fixture.owned.helper"))
print("owned-group-and-two-focus-loss-cases-passed")
'''
        path=self.root/'pure-group.swift';path.write_text(program)
        result=subprocess.run(['/usr/bin/swift',str(path)],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr);self.assertIn('cases-passed',result.stdout)

if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(OwnedGroup))
    receipt={'schema':1,'passed':result.wasSuccessful(),'tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),
        'runtime_source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'HUD_source_sha256':hashlib.sha256((HERE/'source/mac/hud_overlay.swift').read_bytes()).hexdigest(),
        'exact_source_resolver_and_Swift_selector_exercised':True,'all_fixture_data_synthetic_temporary':True,
        'Game_HUD_binary_GUI_CUA_RPC_or_focus_sidecar_started_or_written':False,'native750_and_loss_focus_release_changed':False}
    print(json.dumps(receipt,indent=2))
    raise SystemExit(0 if result.wasSuccessful() else 1)
