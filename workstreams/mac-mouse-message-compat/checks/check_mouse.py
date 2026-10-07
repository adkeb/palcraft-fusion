"""Three bounded header cases plus their original pure Mac env producer. No Game/UI."""
import importlib.util
import json
from pathlib import Path
import shlex
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
def load(name, folder):
 s=importlib.util.spec_from_file_location(name,ROOT/folder/'launcher/crossover_menu_helper.py')
 m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
old=load('base_menu','base');new=load('new_menu','source')
with tempfile.TemporaryDirectory(prefix='synthetic-mouse-plan-') as temp:
 root=Path(temp).resolve();p={'platform':'crossover','bottle_mode':'existing-selected','pal_entry_mode':'singleplayer',
  'crossover_app':str(root/'CrossOver.app'),'bottle_root':str(root/'bottles/Fixture'),'bottle_name':'Fixture',
  'windows_root':'Z:/fixture owned','fps':60,'launch_shipping':True,'mute':False}
 target='PalCraft-Dev/player-tools/bin/PalCraftClientHost-v1.exe'
 wine=str(Path(p['crossover_app'])/'Contents/SharedSupport/CrossOver/bin/wine')
 command=[wine,'--bottle','Fixture','--enable-alt-loader','1','--debugmsg','-all','--dll','dwmapi=n,b','--env',
  'SteamAppId=1623730','--workdir',old.windows(p['windows_root'],'PalCraft-Client'),old.windows(p['windows_root'],target),
  '--root',old.windows(p['windows_root']),'--control',old.windows(p['windows_root'],'.palcraft/control'),
  '--token','a'*32,'--fps','60','--shipping']
 before=old.plan(root,p,command,target);after=new.plan(root,p,command,target)
 assert new.native_shortcut_request(after)==old.native_shortcut_request(before)
 raw=shlex.split(after['menu_command']);prior=shlex.split(before['menu_command'])
 field=raw.index('--env')+1
 assert raw[field]=='SteamAppId=1623730 PALCRAFT_MAC_MOUSE_MESSAGES=relative-v1'
 raw[field]='SteamAppId=1623730';assert raw==prior
 env=new.native_environment({'CX_ENV':'KEEP=one PALCRAFT_MAC_MOUSE_MESSAGES=wrong'})
 assignments=shlex.split(env['CX_ENV'])
 assert 'SteamAppId=1623730' in assignments and 'WINEDLLOVERRIDES=dwmapi=n,b' in assignments
 assert assignments.count('PALCRAFT_MAC_MOUSE_MESSAGES=relative-v1')==1 and 'KEEP=one' in assignments
 try:new.plan(root,{**p,'platform':'windows'},command,target)
 except new.MenuError:pass
 else:raise AssertionError('The selected Mac producer must reject Windows')

compiled=subprocess.run(['/usr/bin/nice','-n','19','/usr/bin/clang++','-std=c++17','-Wall','-Wextra',
 str(ROOT/'checks/mouse_compat.cpp'),'-o',str(ROOT/'checks/mouse_compat')],capture_output=True,text=True)
assert compiled.returncode==0,compiled.stderr
result=subprocess.run([str(ROOT/'checks/mouse_compat')],capture_output=True,text=True)
assert result.returncode==0,result.stderr
(ROOT/'checks/stdout.txt').write_text(result.stdout)
receipt={'schema':1,'ok':True,'bounded_input_source_cases_passed':4,
 'ordinary_small_delta_infinite_known_warp_cycles':True,'raw_exclusive_no_double_and_default_unchanged':True,
 'focus_menu_window_generation_large_jump_and_warp_resets':True,
 'no_warp_message_ack_real_cursor_observation_or_100ms_deadline_recovers':True,
 'official_mac_rawCommand_and_CX_ENV_explicit_flag_preserves_Steam_LNK_and_original_options':True,
 'real_production_header_methods_and_pure_menu_functions_used':True,
 'all_window_owner_coordinates_and_profile_fixture_data_synthetic':True,
 'Game_GUI_Rpc_activation_input_posting_current_process_or_installed_writes':False,
 'actual_mac_mouse_runtime_delivery_or_look_verified':False}
(ROOT/'checks/receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(result.stdout+json.dumps(receipt))
