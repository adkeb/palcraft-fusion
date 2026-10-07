"""Three bounded production-function cases; no NSApp/CGWarp/Game/source installation."""
import importlib.util
import json
from pathlib import Path
import shlex
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
cpp=subprocess.run(['/usr/bin/nice','-n','19','/usr/bin/clang++','-std=c++17','-Wall','-Wextra',str(ROOT/'checks/host_warp.cpp'),'-o',str(ROOT/'checks/host_warp')],capture_output=True,text=True)
assert cpp.returncode==0,cpp.stderr
cpp=subprocess.run([str(ROOT/'checks/host_warp')],capture_output=True,text=True);assert cpp.returncode==0,cpp.stderr
source=(ROOT/'source/mac/hud_overlay.swift').read_text()
group=source[source.index('struct MacForegroundGroup:'):source.index('enum HUDProtocolError:')]
plan=source[source.index('struct MacHostMousePlan {'):source.index('private func hudMonotonic()')]
fixture='import Foundation\nimport CoreGraphics\n'+group+plan+'''
let group=MacForegroundGroup(version:1,token:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",game_pid:10,game_identity:"synthetic-game",helper_pid:11,helper_identity:"synthetic-helper",helper_bundle_id:"synthetic.bundle",helper_bundle:"synthetic.app",native_process_epoch:"1234:998877",own_root:"synthetic-root",game_exe:"synthetic-exe",private_user_dir:"synthetic-userdir")
var input:[String:Any]=["mouse_compatibility_mode":"relative-host-warp-v1","mouse_owner_token":group.token,"mouse_native_epoch":group.native_process_epoch,"mouse_host_eligible":true,"build":true,"focus":true,"menu":false,"unix":1000.0,"generation":8,"viewport_width":1280,"viewport_height":720]
func make(_ value:[String:Any],front:Int32=10,focus:Bool=true,buttons:Bool=false,now:Double=1000.1)->MacHostMousePlan?{
 return MacHostMousePlan.make(input:value,group:group,groupAlive:true,frontPID:front,focused:focus,cameraActive:true,renderAge:0.1,now:now,buttonsDown:buttons,bounds:CGRect(x:100,y:100,width:1600,height:928),title:28)
}
let p=make(input)!;precondition(p.point==CGPoint(x:900,y:578)&&p.x==640&&p.y==360)
precondition(p.observed(CGPoint(x:900,y:578)) && !p.observed(CGPoint(x:1498,y:578)))
precondition(make(input,front:11)==nil&&make(input,focus:false)==nil&&make(input,buttons:true)==nil)
precondition(make(input,now:1001)==nil)
input["menu"]=true;precondition(make(input)==nil);input["menu"]=false
input["mouse_host_eligible"]=false;precondition(make(input)==nil);input["mouse_host_eligible"]=true
input["mouse_owner_token"]="foreign";precondition(make(input)==nil)
print("real production HUD eligibility, header/scale center mapping and observed position confirmation: PASS (no GUI/warp)")
'''
swift=ROOT/'checks/pure_host.swift';swift.write_text(fixture)
r=subprocess.run(['/usr/bin/nice','-n','19','/usr/bin/swiftc',str(swift),'-o',str(ROOT/'checks/pure_host')],capture_output=True,text=True);assert r.returncode==0,r.stderr
r=subprocess.run([str(ROOT/'checks/pure_host')],capture_output=True,text=True);assert r.returncode==0,r.stderr
def load(name,folder):
 spec=importlib.util.spec_from_file_location(name,ROOT/folder/'launcher/crossover_menu_helper.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
old=load('old_menu','base');new=load('new_menu','source')
with tempfile.TemporaryDirectory(prefix='synthetic-host-warp-') as tmp:
 root=Path(tmp).resolve();p={'platform':'crossover','bottle_mode':'existing-selected','pal_entry_mode':'singleplayer','crossover_app':str(root/'CrossOver.app'),'bottle_root':str(root/'bottles/Fixture'),'bottle_name':'Fixture','windows_root':'Z:/fixture owned','fps':60,'launch_shipping':True,'mute':False};token='a'*32;target='PalCraft-Dev/player-tools/bin/PalCraftClientHost-v1.exe';wine=str(Path(p['crossover_app'])/'Contents/SharedSupport/CrossOver/bin/wine')
 args=[wine,'--bottle','Fixture','--enable-alt-loader','1','--debugmsg','-all','--dll','dwmapi=n,b','--env','SteamAppId=1623730','--workdir',old.windows(p['windows_root'],'PalCraft-Client'),old.windows(p['windows_root'],target),'--root',old.windows(p['windows_root']),'--control',old.windows(p['windows_root'],'.palcraft/control'),'--token',token,'--fps','60','--shipping']
 before=old.plan(root,p,args,target);after=new.plan(root,p,args,target)
 assert new.native_shortcut_request(after)==old.native_shortcut_request(before)
 raw=shlex.split(after['menu_command']);assert 'SteamAppId=1623730' in raw[raw.index('--env')+1] and token in raw[raw.index('--env')+1]
 env=shlex.split(new.native_environment({},owner_token=token)['CX_ENV'])
 assert 'SteamAppId=1623730' in env and 'WINEDLLOVERRIDES=dwmapi=n,b' in env
 assert 'PALCRAFT_MAC_MOUSE_MESSAGES=relative-host-warp-v1' in env and 'PALCRAFT_MOUSE_OWNER_TOKEN='+token in env
 try:new.native_environment({},owner_token='foreign')
 except new.MenuError:pass
 else:raise AssertionError('Invalid owner token must reject')
out=cpp.stdout+r.stdout
(ROOT/'checks/stdout.txt').write_text(out)
receipt={'schema':1,'ok':True,'bounded_source_case_groups_passed':3,'matched_observed_metadata_baseline_then_real_motion':True,'actual_HUD_plan_raw_menu_focus_buttons_and_observed_cursor_gates':True,'stale_foreign_epoch_token_and_oversized_record_refused':True,'original_menu_Steam_LNK_and_owner_token_producer_verified':True,'actual_production_headers_and_pure_HUD_functions_used':True,'all_owner_window_profile_cursor_input_and_time_fixtures_synthetic':True,'no_NSApp_CGWarp_GUI_Game_RPC_input_environment_install_or_runtime_operations':True,'actual_runtime_mouse_capture_not_verified':True}
(ROOT/'checks/receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(out+json.dumps(receipt))
