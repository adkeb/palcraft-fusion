"""Three limited actual-function groups. All geometry/window/time fixtures synthetic; no GUI."""
from pathlib import Path
import subprocess,json
ROOT=Path(__file__).resolve().parents[1]
def run(command):
 r=subprocess.run(command,capture_output=True,text=True);assert r.returncode==0,r.stderr;return r.stdout
run(['/usr/bin/nice','-n','19','/usr/bin/clang++','-std=c++17','-Wall','-Wextra',str(ROOT/'checks/ordinary_phase.cpp'),'-o',str(ROOT/'checks/ordinary_phase')])
out=run([str(ROOT/'checks/ordinary_phase')])
s=(ROOT/'source/mac/hud_overlay.swift').read_text();group=s[s.index('struct MacForegroundGroup:'):s.index('enum HUDProtocolError:')];plan=s[s.index('struct MacHostMousePlan {'):s.index('private func hudMonotonic()')]
fixture='import Foundation\nimport CoreGraphics\n'+group+plan+'''
let g=MacForegroundGroup(version:1,token:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",game_pid:10,game_identity:"synthetic",helper_pid:11,helper_identity:"synthetic",helper_bundle_id:"synthetic",helper_bundle:"synthetic",native_process_epoch:"2852:123456",own_root:"synthetic",game_exe:"synthetic",private_user_dir:"synthetic")
var input:[String:Any]=["mouse_compatibility_mode":"relative-host-warp-v1","mouse_owner_token":g.token,"mouse_native_epoch":g.native_process_epoch,"mouse_host_eligible":true,"build":true,"focus":true,"menu":false,"unix":1000.0,"generation":9,"viewport_width":1280,"viewport_height":720,"mouse_win_geometry_valid":true,"mouse_win_window_x":116.0,"mouse_win_window_y":88.0,"mouse_win_window_width":1280.0,"mouse_win_window_height":748.0,"mouse_win_client_origin_x":120.0,"mouse_win_client_origin_y":117.0]
func make(_ i:[String:Any],buttons:Bool=false,front:Int32=10)->MacHostMousePlan?{
 MacHostMousePlan.make(input:i,group:g,groupAlive:true,frontPID:front,focused:true,cameraActive:true,renderAge:0.1,now:1000.1,buttonsDown:buttons,bounds:CGRect(x:116,y:88,width:1280,height:748),title:28)
}
let p=make(input)!;precondition(p.point==CGPoint(x:760,y:477));precondition(!p.observed(CGPoint(x:756,y:476)))
precondition(p.observed(CGPoint(x:760,y:477)))
precondition(make(input,buttons:true)==nil&&make(input,front:11)==nil)
input["menu"]=true;precondition(make(input)==nil);input["menu"]=false
input["mouse_win_geometry_valid"]=false;precondition(make(input)==nil)
print("actual native origin/window geometry maps client center; no fixed28px inference or fake observation; UI guards: PASS (synthetic)")
'''
src=ROOT/'checks/pure_geometry.swift';src.write_text(fixture)
run(['/usr/bin/nice','-n','19','/usr/bin/swiftc',str(src),'-o',str(ROOT/'checks/pure_geometry')]);out+=run([str(ROOT/'checks/pure_geometry')])
# Actual production WM_INPUT guard is inspected in its context; no synthetic RAW source is run.
native=(ROOT/'source/render/controls.cpp').read_text();assert 'if(macMouseMode()!=2&&mode&&!ui&&live' in native
assert 'GetCursorPos(&actual)&&ScreenToClient(window,&actual)&&actual.x==seen.x&&actual.y==seen.y' in native
assert 'mouseCompat.host_move' in native
(ROOT/'checks/stdout.txt').write_text(out)
r={'schema':1,'ok':True,'bounded_case_groups_passed':3,'actual_header_20steps1600_pending_center_no_cancellation':True,'actual_HUD_geometry_4_and_1_border_example_synthetic_not_actual_measurement':True,'request_not_observation_foreign_tuple_and_UI_guards':True,'hostmode_RAW_disabled_guard_and_actual_Win_cursor_query_in_original_handler_reviewed':True,'all_identity_window_cursor_geometry_clock_data_synthetic':True,'Game_GUI_RPC_actual_CGWarp_input_pose_or_runtime_writes':False,'real_v4_mapping_or_infinite_look_verified':False}
(ROOT/'checks/receipt.json').write_text(json.dumps(r,indent=2)+'\n');print(out+json.dumps(r))
