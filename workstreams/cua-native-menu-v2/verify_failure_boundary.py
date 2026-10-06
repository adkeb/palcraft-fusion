#!/usr/bin/env python3
"""Only the new real failure boundary and native launch-route regressions."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import struct
import sys
import tempfile
import unittest

import crossover_menu_helper as m


class NewBoundaryChecks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name).resolve();self.home=self.root/'.palcraft/native-menu'
        self.home.mkdir(parents=True)
        self.spec=dict(root=self.root,home=self.home,token='a'*32,
            link=self.root/'missing.lnk',link_windows='C:\\windows\\Start Menu\\PalCraft\\owner\\Game.lnk')

    def test_real_nonzero_exit_and_utf16_stderr_are_visible(self):
        completed=subprocess.CompletedProcess(['fixture'],5,b'',
            'WScript engine failed HRESULT 0x80040154'.encode('utf-16'))
        detail=m.step_receipt(self.spec,'create_windows_shelllink',completed)
        report=json.loads(detail)
        self.assertEqual(report['returncode'],5)
        self.assertIn('0x80040154',report['stderr'])
        self.assertFalse(report['link_exists'])
        self.assertIsNone(report['link_bytes'])
        self.assertFalse(report['target_executed'])
        self.assertEqual(json.loads((self.home/'setup-diagnostic.json').read_text()),report)

    def test_zero_exit_with_missing_link_is_distinct_and_tokens_redacted(self):
        completed=subprocess.CompletedProcess(['fixture'],0,('received --token '+'a'*32).encode(),b'other bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
        report=json.loads(m.step_receipt(self.spec,'create_windows_shelllink',completed))
        self.assertEqual(report['returncode'],0)
        self.assertFalse(report['link_exists'])
        text=json.dumps(report);self.assertNotIn('a'*32,text);self.assertNotIn('b'*32,text)
        self.assertIn('<redacted-token>',text)

    def test_ignored_flag_is_not_the_native_launch_route(self):
        p=dict(platform='crossover',bottle_mode='existing-selected',pal_entry_mode='singleplayer',
            crossover_app='/Applications/CrossOver.app',bottle_root=str(self.root/'bottle'),
            bottle_name='PalCraftLab',windows_root='Z:'+str(self.root),fps=15,mute=True,launch_shipping=True)
        target='PalCraft-Dev/player-tools/bin/PalCraftClientHost-v1.exe'
        command=['/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine',
            '--bottle','PalCraftLab','--enable-alt-loader','1','--debugmsg','-all','--dll','dwmapi=n,b',
            '--env','SteamAppId=1623730','--workdir',m.windows(p['windows_root'],'PalCraft-Client'),m.windows(p['windows_root'],target),
            '--root',m.windows(p['windows_root']),'--control',m.windows(p['windows_root'],'.palcraft/control'),
            '--token','a'*32,'--fps','15','--shipping','--mute']
        spec=m.plan(self.root,p,command,target)
        self.assertEqual(spec['launch'],[str(spec['bundle']/'Contents/MacOS/Menu Helper')])
        self.assertNotIn('--enable-alt-loader',spec['helper_command'])
        self.assertEqual(spec['arguments'],command[14:])
        self.assertEqual(spec['target'],command[13])
        self.assertIn('--dll dwmapi=n,b',spec['helper_command'])
        self.assertIn('--env SteamAppId=1623730',spec['helper_command'])

    def test_native_request_keeps_UTF16_unicode_and_full_quoted_arguments(self):
        spec=dict(self.spec,target='Z:\\玩家 客户端🧪\\HOST.exe',
                  arguments=['--root','Z:\\玩家 客户端🧪','--token','a'*32,'--fps','15','--shipping','--mute'],
                  workdir='Z:\\玩家 客户端🧪\\PalCraft-Client',description='PalCraft Game')
        request=m.native_shortcut_request(spec)
        self.assertEqual(request[:8],b'PCSLNK01')
        self.assertEqual(struct.unpack_from('<I',request,8)[0],5)
        fields=[];offset=12
        for _ in range(5):
            units=struct.unpack_from('<I',request,offset)[0];offset+=4
            fields.append(request[offset:offset+units*2].decode('utf-16-le'));offset+=units*2
        self.assertEqual(offset,len(request))
        self.assertEqual(fields,[spec['link_windows'],spec['target'],subprocess.list2cmdline(spec['arguments']),spec['workdir'],spec['description']])
        with self.assertRaises(m.MenuError):m.native_shortcut_request(dict(spec,target='bad\0path'))

    def test_native_readback_is_required_even_for_zero_exit_and_existing_file(self):
        self.spec['link'].write_bytes(b'existing-file-is-not-proof')
        self.assertIsNone(m.native_readback(subprocess.CompletedProcess([],0,b'',b''),self.spec))
        verified=dict(backend='IShellLinkW',stage='verified',readback_target=True,
            readback_arguments=True,readback_workdir=True,readback_description=True,target_executed=False,same_original_file=True)
        completion=subprocess.CompletedProcess([],0,(json.dumps(verified)+'\n').encode(),b'')
        self.assertEqual(m.native_readback(completion,self.spec),verified)
        for name in ['readback_target','readback_arguments','readback_workdir','readback_description','same_original_file']:
            changed=dict(verified);changed[name]=False
            self.assertIsNone(m.native_readback(subprocess.CompletedProcess([],0,json.dumps(changed).encode(),b''),self.spec))

    def test_selected_creator_prepare_is_single_producer_then_native_bundle(self):
        p=dict(platform='crossover',bottle_mode='existing-selected',pal_entry_mode='singleplayer',
            crossover_app=os.environ.get('PALCRAFT_CROSSOVER_APP', '/Applications/CrossOver.app'),
            bottle_root=str(self.root/'bottle'),bottle_name='PalCraftLab',windows_root='Z:'+str(self.root),
            fps=15,mute=True,launch_shipping=True)
        target='PalCraft-Dev/player-tools/bin/PalCraftClientHost-v1.exe'
        command=[p['crossover_app']+'/Contents/SharedSupport/CrossOver/bin/wine','--bottle','PalCraftLab',
            '--enable-alt-loader','1','--debugmsg','-all','--dll','dwmapi=n,b','--env','SteamAppId=1623730',
            '--workdir',m.windows(p['windows_root'],'PalCraft-Client'),m.windows(p['windows_root'],target),
            '--root',m.windows(p['windows_root']),'--control',m.windows(p['windows_root'],'.palcraft/control'),
            '--token','a'*32,'--fps','15','--shipping','--mute']
        spec=m.plan(self.root,p,command,target)
        writer=self.root/'PalCraftShellLink-v2.exe'
        shutil.copyfile(Path(__file__).parent/'native-short-target-v2/PalCraftShellLink-v2.exe',writer)
        spec.update(writer=writer,writer_windows=m.windows(p['windows_root'],writer.name))
        spec['bottle'].mkdir()
        (spec['bottle']/'cxbottle.conf').write_text('[CrossOver]\n"BuildTimestamp"="1"\n[Bottle]\n"Timestamp"="1"\n"BottleID"="owned-test-id"\n"MenuMode"="ignore"\n')
        calls=[]
        def runner(c,**kwargs):
            calls.append(c)
            if c[0]==str(spec['wine']):
                self.assertIn('--wait-children',c)
                self.assertIn(spec['writer_windows'],c)
                self.assertNotIn('--wl-app',c)
                request=(spec['home']/'create-shortcut.bin').read_bytes()
                self.assertTrue(request.startswith(b'PCSLNK01'))
                spec['link'].write_bytes(b'fixture-not-a-live-ShellLink')
                out=dict(backend='IShellLinkW',stage='verified',readback_target=True,
                    readback_arguments=True,readback_workdir=True,readback_description=True,target_executed=False,same_original_file=True)
                return subprocess.CompletedProcess(c,0,json.dumps(out).encode(),b'')
            if '--create' in c:
                spec['menu_script'].parent.mkdir(parents=True);spec['menu_script'].write_text('# fixture\n')
            return subprocess.CompletedProcess(c,0,b'',b'')
        m.prepare(spec,p,{},runner=runner,guard=lambda s:None)
        self.assertEqual(len(calls),3)
        self.assertEqual(calls[-1][0],m.LSREGISTER)
        self.assertFalse((spec['home']/'create-shortcut.bin').exists())
        self.assertFalse(list(spec['home'].rglob('*.vbs')))
        receipt=json.loads((spec['home']/'prepared.json').read_text())
        self.assertEqual(receipt['shelllink_producer'],'native_IShellLinkW_IPersistFile')
        self.assertEqual(receipt['launch_route'],'genuine_vendor_Menu_Helper_executable')
        self.assertFalse(receipt['actual_window_owner_proven'])


if __name__=='__main__':unittest.main(verbosity=2)
