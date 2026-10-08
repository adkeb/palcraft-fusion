"""One actual-plan case, all scope/geometry/cursor values synthetic; no Game or CGWarp."""
from pathlib import Path
import json,subprocess
D=Path(__file__).resolve().parents[1]
s=(D/'source/mac/hud_overlay.swift').read_text()
g=s[s.index('struct MacForegroundGroup:'):s.index('enum HUDProtocolError:')]
p=s[s.index('struct MacHostMousePlan {'):s.index('private func hudMonotonic()')]
f='import Foundation\nimport CoreGraphics\n'+g+p+"""
let group=MacForegroundGroup(version:1,token:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",game_pid:10,game_identity:"synthetic",helper_pid:11,helper_identity:"synthetic",helper_bundle_id:"synthetic",helper_bundle:"synthetic",native_process_epoch:"10:12345",own_root:"synthetic",game_exe:"synthetic",private_user_dir:"synthetic")
let input:[String:Any]=["mouse_compatibility_mode":"relative-host-warp-v1","mouse_owner_token":group.token,"mouse_native_epoch":group.native_process_epoch,"mouse_host_eligible":true,"build":true,"focus":true,"menu":false,"unix":1000.0,"generation":9,"viewport_width":1280,"viewport_height":720,"mouse_win_geometry_valid":true,"mouse_win_window_x":112.0,"mouse_win_window_y":86.0,"mouse_win_window_width":1288.0,"mouse_win_window_height":754.0,"mouse_win_client_origin_x":116.0,"mouse_win_client_origin_y":116.0]
let plan=MacHostMousePlan.make(input:input,group:group,groupAlive:true,frontPID:10,focused:true,cameraActive:true,renderAge:0.1,now:1000.1,buttonsDown:false,bounds:CGRect(x:116,y:88,width:1280,height:748),title:28)!
precondition(plan.x==640 && plan.y==360 && plan.point==CGPoint(x:756,y:476))
precondition(!plan.observed(CGPoint(x:756,y:474)))
precondition(plan.observed(CGPoint(x:756,y:476)))
print("actual plan uses integer client-screen centre(756,476); clipped outer rectangles do not scale it; observed(756,474) is rejected: PASS (synthetic)")
"""
(D/'checks/pure_center.swift').write_text(f)
command=['/usr/bin/nice','-n','19','/usr/bin/swiftc',str(D/'checks/pure_center.swift'),'-o',str(D/'checks/pure_center')]
r=subprocess.run(command,capture_output=True,text=True);assert r.returncode==0,r.stderr
r=subprocess.run([str(D/'checks/pure_center')],capture_output=True,text=True);assert r.returncode==0,r.stderr
(D/'checks/stdout.txt').write_text(r.stdout)
receipt={'schema':1,'ok':True,'limited_actual_function_cases_passed':1,'actual_plan_extracted_from_production_source':True,'integer_client_screen_centre_not_outer_rect_scaling':True,'different_cursor_not_claimed_as_observed':True,'all_scope_geometry_timestamp_and_cursor_data_synthetic':True,'CGWarp_Game_GUI_RPC_input_or_runtime_writes':False,'actual_infinite_look_verified':False}
(D/'checks/receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(r.stdout+json.dumps(receipt))
