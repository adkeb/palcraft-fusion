"""Three pure normal-menu cases. No vendor command, Game or actual root is used."""
import hashlib
import importlib.util
import json
import shlex
import tempfile
import unittest
from pathlib import Path
import sys
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parents[1]
def load(name, where):
    spec=importlib.util.spec_from_file_location(name,HERE/where/'launcher/crossover_menu_helper.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
old=load('base_menu','base');new=load('trace_menu','source')


class LoaderTrace(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='synthetic-loader-plan-')
        self.root=Path(self.temp.name).resolve()/'player root';self.root.mkdir()
        self.profile={'platform':'crossover','bottle_mode':'existing-selected','pal_entry_mode':'singleplayer',
            'crossover_app':str(self.root/'CrossOver.app'),'bottle_root':str(self.root/'bottles/Fixture'),
            'bottle_name':'Fixture','windows_root':'Z:/fixture owned','fps':60,'launch_shipping':True,'mute':False}
        self.target='PalCraft-Dev/player-tools/bin/PalCraftClientHost-v1.exe';self.token='a'*32
        p=self.profile;wine=str(Path(p['crossover_app'])/'Contents/SharedSupport/CrossOver/bin/wine')
        self.command=[wine,'--bottle',p['bottle_name'],'--enable-alt-loader','1','--debugmsg','-all',
            '--dll','dwmapi=n,b','--env','SteamAppId=1623730','--workdir',old.windows(p['windows_root'],'PalCraft-Client'),
            old.windows(p['windows_root'],self.target),'--root',old.windows(p['windows_root']),'--control',
            old.windows(p['windows_root'],'.palcraft/control'),'--token',self.token,'--fps','60','--shipping']
    def tearDown(self):self.temp.cleanup()
    def test_default_plan_native_env_and_link_request_byte_equal_to_base99578(self):
        base=old.plan(self.root,self.profile,self.command,self.target)
        candidate=new.plan(self.root,self.profile,self.command,self.target)
        self.assertEqual(candidate,base);self.assertEqual(candidate['menu_command'].encode(),base['menu_command'].encode())
        self.assertEqual(new.native_shortcut_request(candidate),old.native_shortcut_request(base))
        env={'CX_ENV':'KEEP=one OTHER="two words" SteamAppId=wrong WINEDLLOVERRIDES=wrong',
             'CX_DEBUGMSG':'old-debug','CX_LOG':'/synthetic/legacy.log',new.TRACE_ENV:''}
        self.assertEqual(new.native_environment(env),old.native_environment(env))
    def test_optin_persists_vendor_trace_flags_only_and_uses_same_owned_boot_log(self):
        base=old.plan(self.root,self.profile,self.command,self.target)
        mode=new.resolve_trace_mode({new.TRACE_ENV:'loader'})
        candidate=new.plan(self.root,self.profile,self.command,self.target,trace_mode=mode)
        log=self.root/'.palcraft/logs'/('client-loader-'+self.token+'.log')
        self.assertEqual(candidate['wine_trace_log'],log)
        raw=shlex.split(candidate['menu_command']);i=raw.index('--cx-log')
        self.assertEqual(raw[i+1],str(log));del raw[i:i+2]
        self.assertEqual(raw[raw.index('--debugmsg')+1],new.TRACE_DEBUGMSG)
        raw[raw.index('--debugmsg')+1]='-all';self.assertEqual(raw,shlex.split(base['menu_command']))
        self.assertEqual(new.native_shortcut_request(candidate),old.native_shortcut_request(base))
        for key in base:self.assertEqual(candidate[key],base[key]) if key!='menu_command' else None
        env=new.native_environment({},trace_mode=mode)
        self.assertEqual(env['CX_DEBUGMSG'],new.TRACE_DEBUGMSG);self.assertNotIn('CX_LOG',env)
    def test_wrong_mode_rejected_before_any_producer_operation(self):
        with self.assertRaises(new.MenuError):new.resolve_trace_mode({new.TRACE_ENV:'full'})
        with self.assertRaises(new.MenuError):new.plan(self.root,self.profile,self.command,self.target,trace_mode='full')
        with self.assertRaises(new.MenuError):new.native_environment({},trace_mode='full')


if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(LoaderTrace))
    receipt={'schema':1,'passed':result.wasSuccessful(),'tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),
        'base_sha256':hashlib.sha256((HERE/'base/launcher/crossover_menu_helper.py').read_bytes()).hexdigest(),
        'source_sha256':hashlib.sha256((HERE/'source/launcher/crossover_menu_helper.py').read_bytes()).hexdigest(),
        'default_plan_command_native_env_and_LNK_request_equal':result.wasSuccessful(),
        'optin_raw_command_vendor_log_owned_root_same_token':result.wasSuccessful(),
        'wrong_mode_rejected':result.wasSuccessful(),'all_inputs_synthetic_temporary':True,
        'vendor_registration_Game_runtime_Popen_GUI_RPC_credentials_currentfiles_or_Git_used':False,
        'actual_loader_trace_capture_or_exit53_cause_verified':False}
    print(json.dumps(receipt,indent=2))
    raise SystemExit(0 if result.wasSuccessful() else 1)
