"""Two actual-header queued orders and one diagnostic-only command classifier. Synthetic only."""
from pathlib import Path
import subprocess,json
D=Path(__file__).resolve().parents[1]
s=(D/'source/render/palcraft.cpp').read_text()
fn=s[s.index('static const char* command_action('):s.index('static void status(')]
f='#include <cassert>\n#include <string>\n#include <iostream>\n#include "../source/render/mouse_message_compat.h"\n'+fn+"""
int main(){
 PalCraftMouseMessageCompat a;a.scope(true,true,7,9);a.host_baseline(7,640,360);assert(a.arm_host(7,640,360,1000));
 int sum=a.host_move(7,720,360,1280,720,1000.1).x;assert(sum==80);
 assert(a.host_baseline(7,640,360)&&a.hostCentreArmed);
 sum+=a.host_move(7,640,360,1280,720,1000.2).x;assert(sum==80&&!a.hostCentreArmed);
 assert(a.host_move(7,720,360,1280,720,1000.3).x==80);
 assert(a.host_move(7,640,360,1280,720,1000.4).x==-80);
 std::cout<<"motion first, actual cursor readback then late centre WM: no reverse look; human return to centre counts: PASS"<<std::endl;
 PalCraftMouseMessageCompat b;b.scope(true,true,7,9);b.host_baseline(7,640,360);assert(b.arm_host(7,640,360,1000));
 assert(b.host_baseline(7,640,360)&&b.hostCentreArmed);
 sum=b.host_move(7,560,360,1280,720,1000.1).x;assert(sum==-80);
 sum+=b.host_move(7,640,360,1280,720,1000.2).x;assert(sum==-80&&!b.hostCentreArmed);
 assert(b.host_move(7,560,360,1280,720,1000.3).x==-80);
 assert(b.host_move(7,640,360,1280,720,1000.4).x==80);
 std::cout<<"actual cursor readback first then pending negative motion/late centre WM: no cancellation; human return counts: PASS"<<std::endl;
 assert(std::string(command_action(R"({ "t" : "key", "k":"use", "down" : true })"))=="use_down");
 assert(std::string(command_action(R"({"t":"key","k":"attack","down":false})"))=="attack_up");
 assert(std::string(command_action(R"({"t":"inspect","other":"use"})"))=="other");
 std::cout<<"original command classification returns only whitelist hint; no payload or fake applied acknowledgement: PASS"<<std::endl;
}
"""
(D/'checks/queued_cases.cpp').write_text(f)
cmd=['/usr/bin/nice','-n','19','/usr/bin/clang++','-std=c++17','-Wall','-Wextra',str(D/'checks/queued_cases.cpp'),'-o',str(D/'checks/queued_cases')]
r=subprocess.run(cmd,capture_output=True,text=True);assert r.returncode==0,r.stderr
r=subprocess.run([str(D/'checks/queued_cases')],capture_output=True,text=True);assert r.returncode==0,r.stderr
(D/'checks/stdout.txt').write_text(r.stdout)
receipt={'schema':1,'ok':True,'actual_header_queued_order_cases_passed':2,'diagnostic_command_classifier_case_passed':1,'case_scope_identity_timestamp_coordinates_payload_synthetic':True,'Game_GUI_RPC_or_runtime_operations':False,'actual_negative_navigation_all1600_capture_or_torch_input_cause_verified':False}
(D/'checks/receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(r.stdout+json.dumps(receipt))
