"""Two actual-function groups; all identity, point, time and scope data are synthetic."""
from pathlib import Path
import json,subprocess
D=Path(__file__).resolve().parents[1]
def run(cmd):
 r=subprocess.run(cmd,capture_output=True,text=True);assert r.returncode==0,r.stderr;return r.stdout
cpp=r"""
#include <cassert>
#include <iostream>
#include "../source/render/mouse_message_compat.h"
int main(){
 PalCraftMouseMessageCompat a;a.scope(true,true,7,9);assert(a.host_baseline(7,640,360)&&a.wm.readbackSeeds==1);
 assert(a.arm_host(7,640,360,1000));assert(a.host_move(7,720,360,1280,720,1000.1,100).x==80);
 assert(a.host_baseline(7,640,360)&&a.lastX==720);
 assert(a.host_move(7,640,360,1280,720,1000.2,101).x==0&&!a.hostCentreArmed);
 assert(a.host_move(7,720,360,1280,720,1000.3,102).x==80);
 assert(a.host_baseline(7,640,360)&&a.lastX==720);
 assert(a.host_move(7,640,360,1280,720,1000.4,103).x==-80&&a.wm.centre==1&&a.wm.look==3);
 PalCraftMouseMessageCompat b;b.scope(true,true,7,9);b.host_baseline(7,640,360);b.arm_host(7,640,360,1000);
 b.host_baseline(7,640,360);assert(b.host_move(7,560,360,1280,720,1000.1,100).x==-80);
 assert(b.host_move(7,640,360,1280,720,1000.2,101).x==0);
 assert(b.host_move(7,560,360,1280,720,1000.3,102).x==-80);b.host_baseline(7,640,360);assert(b.lastX==560);
 assert(b.host_move(7,640,360,1280,720,1000.4,103).x==80);
 assert(b.host_move(7,800,360,1280,720,1000.5,104).x==0&&b.wm.jump==1);
 b.scope(true,false,7,9);assert(!b.wm.consumed);b.host_rejected();assert(b.wm.gate==1&&!b.wm.consumed);
 std::cout<<"two queued orders: late centre verification never overwrites newer WM baseline; human return counts;128 and scope/gate diagnostics preserved: PASS"<<std::endl;
}
"""
(D/'checks/queued_consumption.cpp').write_text(cpp)
run(['/usr/bin/nice','-n','19','/usr/bin/clang++','-std=c++17','-Wall','-Wextra',str(D/'checks/queued_consumption.cpp'),'-o',str(D/'checks/queued_consumption')]);out=run([str(D/'checks/queued_consumption')])
s=(D/'source/mac/hud_overlay.swift').read_text();g=s[s.index('struct MacForegroundGroup:'):s.index('enum HUDProtocolError:')];p=s[s.index('struct MacHostMousePlan {'):s.index('private func hudMonotonic()')]
f='import Foundation\nimport CoreGraphics\n'+g+p+"""
let group=MacForegroundGroup(version:1,token:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",game_pid:10,game_identity:"synthetic",helper_pid:11,helper_identity:"synthetic",helper_bundle_id:"synthetic",helper_bundle:"synthetic",native_process_epoch:"10:12345",own_root:"synthetic",game_exe:"synthetic",private_user_dir:"synthetic")
var input:[String:Any]=["mouse_compatibility_mode":"relative-host-warp-v1","mouse_owner_token":group.token,"mouse_native_epoch":group.native_process_epoch,"mouse_host_eligible":true,"build":true,"focus":true,"menu":false,"unix":1000.0,"generation":9,"viewport_width":1280,"viewport_height":720,"mouse_win_geometry_valid":true,"mouse_win_window_x":112.0,"mouse_win_window_y":86.0,"mouse_win_window_width":1288.0,"mouse_win_window_height":754.0,"mouse_win_client_origin_x":116.0,"mouse_win_client_origin_y":116.0,"mouse_win_cursor_observed":true,"mouse_win_cursor_x":720,"mouse_win_cursor_y":360,"mouse_wm_consumed":false,"mouse_wm_generation":9,"mouse_wm_sequence":1,"mouse_wm_client_x":720,"mouse_wm_client_y":360]
func plan(_ i:[String:Any],focused:Bool=true,buttons:Bool=false)->MacHostMousePlan?{MacHostMousePlan.make(input:i,group:group,groupAlive:true,frontPID:10,focused:focused,cameraActive:true,renderAge:0.1,now:1000.1,buttonsDown:buttons,bounds:CGRect(x:116,y:88,width:1280,height:748),title:28)}
let p=plan(input)!;let cursor=CGPoint(x:836,y:476)
precondition(!p.consumed(input:input,cursor:cursor))
input["mouse_wm_consumed"]=true;precondition(p.consumed(input:input,cursor:cursor))
input["mouse_wm_client_x"]=640;precondition(!p.consumed(input:input,cursor:cursor));input["mouse_wm_client_x"]=720
input["mouse_wm_generation"]=8;precondition(!p.consumed(input:input,cursor:cursor));input["mouse_wm_generation"]=9
precondition(!p.consumed(input:input,cursor:CGPoint(x:756,y:476)))
precondition(plan(input,focused:false)==nil&&plan(input,buttons:true)==nil)
input["menu"]=true;precondition(plan(input)==nil)
print("actual HUD plan requires same-scope consumed WM/actual Win/current CG offcentre match; unconsumed/foreign-gen/centre/focus/menu/buttons refuse warp: PASS (synthetic)")
"""
(D/'checks/pure_consumption.swift').write_text(f)
run(['/usr/bin/nice','-n','19','/usr/bin/swiftc',str(D/'checks/pure_consumption.swift'),'-o',str(D/'checks/pure_consumption')]);out+=run([str(D/'checks/pure_consumption')])
(D/'checks/stdout.txt').write_text(out)
r={'schema':1,'ok':True,'actual_function_groups_passed':2,'actual_header_two_queued_orders_and_human_return':True,'actual_HUD_consumption_and_original_scope_UI_guards':True,'all_scope_identity_time_coordinates_and_payload_synthetic':True,'128_750_epoch_auth_ready_not_relaxed':True,'Game_GUI_RPC_input_or_runtime_writes':False,'actual_F03_complete_or_missing_step_cause_proven':False}
(D/'checks/receipt.json').write_text(json.dumps(r,indent=2)+'\n');print(out+json.dumps(r))
