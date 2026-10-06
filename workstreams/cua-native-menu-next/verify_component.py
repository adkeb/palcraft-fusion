#!/usr/bin/env python3
"""Source-only validation. Never runs Wine, cxmenu, an app, or lsregister."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

import crossover_menu_helper as m

VENDOR = os.environ.get('PALCRAFT_CROSSOVER_APP', '/Applications/CrossOver.app')


class SourceChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve() / '玩家 客户端'
        self.root.mkdir()
        self.profile = dict(platform='crossover', bottle_mode='existing-selected',
            pal_entry_mode='singleplayer', crossover_app=VENDOR,
            bottle_root=str(Path(self.temp.name)/'bottle'), bottle_name='PalCraft-Test',
            windows_root='Z:' + str(self.root).replace('/', '\\'), fps=15, mute=True, launch_shipping=True)
        self.target = 'PalCraft-Dev/bin/PalCraftClientHost.exe'
        self.original = [VENDOR + '/Contents/SharedSupport/CrossOver/bin/wine', '--bottle', 'PalCraft-Test',
            '--enable-alt-loader','1','--debugmsg','-all','--dll','dwmapi=n,b','--env','SteamAppId=1623730',
            '--workdir',m.windows(self.profile['windows_root'],'PalCraft-Client'),
            m.windows(self.profile['windows_root'],self.target), '--root', self.profile['windows_root'],
            '--control',m.windows(self.profile['windows_root'],'.palcraft/control'), '--token','a'*32,
            '--fps','15','--shipping','--mute']
        self.spec=m.plan(self.root,self.profile,self.original,self.target)

    def test_pure_plan_preserves_target_arguments(self):
        before=list(self.root.rglob('*'))
        s=m.plan(self.root,self.profile,self.original,self.target)
        self.assertEqual(s['arguments'],self.original[14:])
        self.assertEqual(s['target'],self.original[13])
        self.assertEqual(before,list(self.root.rglob('*')))
        self.assertIn('--wait-children',s['launch'])
        self.assertEqual(s['launch'][s['launch'].index('--enable-alt-loader')+1],'1')
        self.assertNotIn('&',s['launch'])

    def test_launcher_cli_keeps_original_argv_as_remainder(self):
        args=m.parse_cli(['--root',str(self.root),'run','--']+self.original)
        self.assertEqual(args.root,str(self.root))
        self.assertEqual(args.original,self.original)

    def test_normalized_profile_slashes_match_original_windows_argv(self):
        profile=dict(self.profile,windows_root=self.profile['windows_root'].replace('\\','/'))
        planned=m.plan(self.root,profile,self.original,self.target)
        self.assertEqual(planned['target'],self.spec['target'])
        self.assertEqual(planned['arguments'],self.spec['arguments'])

    def test_session_requires_original_supervisor_and_this_client(self):
        runtime=types.ModuleType('launcher.runtime')
        runtime.process_matches=lambda component:component.get('identity')=='fixture-alive'
        session=dict(token=self.spec['token'],phase='bootstrap',
            supervisor=dict(pid=os.getppid(),identity='fixture-alive'),
            components=dict(client=dict(pid=os.getpid(),identity='fixture-alive')))
        path=self.root/'.palcraft/session.json';path.parent.mkdir()
        with patch.dict(sys.modules,{'launcher':types.ModuleType('launcher'),'launcher.runtime':runtime}):
            path.write_text(json.dumps(session));m.session_guard(self.spec)
            for where,field,value in [('session','phase','closing'),('session','token','b'*32),
                                     ('supervisor','pid',os.getppid()+1),('client','pid',os.getpid()+1),
                                     ('client','identity','stale')]:
                edited=json.loads(json.dumps(session))
                target=edited if where=='session' else edited['supervisor'] if where=='supervisor' else edited['components']['client']
                target[field]=value;path.write_text(json.dumps(edited))
                with self.subTest(where=where,field=field),self.assertRaises(m.MenuError):m.session_guard(self.spec)
            path.write_text(json.dumps(session));control=self.root/'.palcraft/control';control.mkdir()
            (control/(self.spec['token']+'.stop')).touch()
            with self.assertRaises(m.MenuError):m.session_guard(self.spec)

    def test_changed_host_arguments_and_bottle_rejected(self):
        for index,value in [(2,'Steam'),(13,'C:\\other.exe'),(-3,'60'),(19,'b'*31)]:
            command=self.original[:];command[index]=value
            with self.subTest(index=index),self.assertRaises(m.MenuError):
                m.plan(self.root,self.profile,command,self.target)

    def test_shortcut_is_file_creation_only_and_quotes_exact_args(self):
        source=m.shortcut_source(self.spec)
        self.assertIn('link.TargetPath = ' + m.vb_string(self.spec['target']),source)
        self.assertIn('link.Arguments = ' + m.vb_string(subprocess.list2cmdline(self.spec['arguments'])),source)
        self.assertIn('link.Save',source)
        for operation in ['SendKeys','shell.Run','shell.Exec']:
            self.assertNotIn(operation,source)
        self.assertEqual(m.menu_script_name('a+b^c d'),'a^2Bb^5Ec+d')
        with self.assertRaises(m.MenuError):m.vb_string('bad\npath')

    def test_real_template_and_bundle_metadata(self):
        m.write_bundle(self.spec,self.profile,'E20930E2-2D71-4CC8-A8DE-86D163AA49BC')
        bundle=self.spec['bundle']
        executable=bundle/'Contents/MacOS/Menu Helper'
        self.assertEqual(hashlib.sha256(executable.read_bytes()).hexdigest(),m.HELPER_SHA256)
        self.assertTrue(executable.stat().st_mode & 0o111)
        info=plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
        self.assertEqual(info['CXHelperAppBottleName'],'PalCraft-Test')
        self.assertEqual(info['CrossOverHelperMenuPath'],self.spec['menu'])
        self.assertEqual(info['NSPrincipalClass'],'CXFBHelperApp')
        self.assertNotIn('CFBundleURLTypes',info)
        self.assertNotIn(self.spec['token'],json.dumps(info))
        self.assertNotIn('Steam.app',json.dumps(info))
        with self.assertRaises(m.MenuError):list(m.archive_entries(b'wrong'))

    def test_only_owned_setup_then_register_and_no_game(self):
        bottle=self.spec['bottle'];bottle.mkdir()
        conf='[CrossOver]\n"BuildTimestamp"="100"\n[Bottle]\n"Timestamp"="100"\n"BottleID"="E20930E2-2D71-4CC8-A8DE-86D163AA49BC"\n"MenuMode"="ignore"\n'
        (bottle/'cxbottle.conf').write_text(conf)
        calls=[];guards=[]
        def runner(command,**kwargs):
            calls.append(command)
            if '--wl-app' in command:
                script=self.spec['home']/'create-shortcut.vbs'
                self.assertIn('link.Save',script.read_bytes().decode('utf-16'))
                self.spec['link'].write_bytes(b'fixture-only-not-a-real-link')
            elif '--create' in command:
                self.spec['menu_script'].parent.mkdir(parents=True)
                self.spec['menu_script'].write_text('# fixture-only\n')
                self.assertEqual(command[command.index('--type')+1],'windows')
                self.assertNotIn('--command',command)
                self.assertNotIn('--sync',command)
            return subprocess.CompletedProcess(command,0,b'',b'')
        m.prepare(self.spec,self.profile,{'SteamAppId':'1623730'},runner=runner,guard=lambda s:guards.append(s['owner']))
        self.assertEqual(len(calls),3)
        self.assertEqual(calls[-1],[m.LSREGISTER,'-f',str(self.spec['bundle'])])
        self.assertTrue(all('--start' not in c for c in calls))
        self.assertFalse((self.spec['home']/'create-shortcut.vbs').exists())
        self.assertEqual((bottle/'cxbottle.conf').read_text(),conf)
        receipt=json.loads((self.spec['home']/'prepared.json').read_text())
        self.assertFalse(receipt['actual_window_owner_proven'])
        self.assertFalse(receipt['physical_f5_proven'])
        self.assertNotIn(self.spec['token'],json.dumps(receipt))
        self.assertGreaterEqual(len(guards),3)

    def test_setup_failure_never_installs_or_registers(self):
        bottle=self.spec['bottle'];bottle.mkdir()
        (bottle/'cxbottle.conf').write_text('[CrossOver]\n"BuildTimestamp"="1"\n[Bottle]\n"Timestamp"="1"\n"BottleID"="abc"\n"MenuMode"="ignore"\n')
        calls=[]
        def runner(c,**kw):calls.append(c);return subprocess.CompletedProcess(c,1,b'',b'')
        with self.assertRaises(m.MenuError):m.prepare(self.spec,self.profile,{},runner=runner,guard=lambda s:None)
        self.assertEqual(len(calls),1)
        self.assertFalse((self.spec['home']/'create-shortcut.vbs').exists())
        self.assertFalse(self.spec['bundle'].exists())

    def test_upgrade_and_symlink_rejected_before_setup(self):
        bottle=self.spec['bottle'];bottle.mkdir()
        (bottle/'cxbottle.conf').write_text('[CrossOver]\n"BuildTimestamp"="1"\n[Bottle]\n"Timestamp"="0"\n"BottleID"="abc"\n')
        with self.assertRaises(m.MenuError):m.prepare(self.spec,self.profile,{},runner=lambda *a,**kw:self.fail('must not run'),guard=lambda s:None)
        alias=Path(self.temp.name)/'alias';alias.symlink_to(self.root)
        with self.assertRaises(m.MenuError):m.plan(alias,self.profile,self.original,self.target)
        with self.assertRaises(m.MenuError):m.checked_path(alias/'x',Path(self.temp.name))


if __name__=='__main__':unittest.main(verbosity=2)
