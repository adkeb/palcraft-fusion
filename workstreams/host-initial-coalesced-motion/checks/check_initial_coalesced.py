from pathlib import Path
import subprocess,json
D=Path(__file__).resolve().parents[1]
def run(cmd):
 r=subprocess.run(cmd,capture_output=True,text=True);assert r.returncode==0,r.stderr;return r.stdout
cpp=r"""
#include <cassert>
#include <iostream>
#include "../source/render/mouse_message_compat.h"
int main(){
 PalCraftMouseMessageCompat initial;initial.scope(true,true,7,9);assert(!initial.point&&initial.scopeSerial==1);
 assert(initial.arm_host(7,640,360,1000));assert(initial.host_baseline(7,640,360,0));
 assert(initial.host_move(7,720,360,1280,720,1000.1,100).x==80&&initial.wm.seed==0); // No centre WM supplied.
 initial.host_baseline(7,640,360,0);assert(initial.lastX==720); // A newer WM cannot be overwritten by seq0.
 std::cout<<"initial real-centre parameter/seq0 with no centre WM seeds before first80; oldseq0 cannot overwrite new WM: PASS"<<std::endl;
 PalCraftMouseMessageCompat host;host.scope(true,true,7,9);host.host_baseline(7,640,360);
 assert(host.host_move(7,800,360,1280,720,1000,100).x==160&&host.wm.look==1&&host.wm.jump==0);
 PalCraftMouseMessageCompat legacy;legacy.scope(true,true,7,9);legacy.move(7,640,360,1280,720);
 assert(legacy.move(7,800,360,1280,720).x==0); // Existing ordinary/Windows mode retains128.
 std::cout<<"owned host ordinary coalesced160 counts160; original legacy128 rule unchanged: PASS"<<std::endl;
}
"""
(D/'checks/initial_coalesced.cpp').write_text(cpp)
run(['/usr/bin/nice','-n','19','/usr/bin/clang++','-std=c++17','-Wall','-Wextra',str(D/'checks/initial_coalesced.cpp'),'-o',str(D/'checks/initial_coalesced')]);out=run([str(D/'checks/initial_coalesced')])
s=(D/'source/mac/hud_overlay.swift').read_text();g=s[s.index('struct MacForegroundGroup:'):s.index('enum HUDProtocolError:')];p=s[s.index('struct MacHostMousePlan {'):s.index('private func hudMonotonic()')]
f='import Foundation\nimport CoreGraphics\n'+g+p+"""
let plan=MacHostMousePlan(point:CGPoint(x:756,y:476),x:640,y:360,width:1280,height:720,generation:9)
var input:[String:Any]=["mouse_wm_point_established":false,"mouse_wm_generation":9,"mouse_wm_scope_serial":1]
precondition(plan.initialCapture(input:input,previousScope:nil))
precondition(!plan.initialCapture(input:input,previousScope:1))
input["mouse_wm_point_established"]=true;precondition(!plan.initialCapture(input:input,previousScope:nil))
input["mouse_wm_point_established"]=false;input["mouse_wm_generation"]=8;precondition(!plan.initialCapture(input:input,previousScope:nil))
print("actual initialCapture allows one current-scope pointless setup only; established/reused/foreign generation refuse initial path: PASS (synthetic)")
"""
(D/'checks/pure_initial.swift').write_text(f)
run(['/usr/bin/nice','-n','19','/usr/bin/swiftc',str(D/'checks/pure_initial.swift'),'-o',str(D/'checks/pure_initial')]);out+=run([str(D/'checks/pure_initial')])
(D/'checks/stdout.txt').write_text(out)
r={'schema':1,'ok':True,'targeted_cases_passed':2,'initial_no_centre_WM_and_first80':True,'coalesced160_host_only_legacy128_kept':True,'HUD_initial_once_scope_rule_actual_function_checked':True,'all_scope_coordinates_times_and_observations_synthetic':True,'Game_GUI_RPC_actual_CG_or_Win_queries_or_runtime_operations':False,'actual_F03_all_requested_pixels_proven':False}
(D/'checks/receipt.json').write_text(json.dumps(r,indent=2)+'\n');print(out+json.dumps(r))
