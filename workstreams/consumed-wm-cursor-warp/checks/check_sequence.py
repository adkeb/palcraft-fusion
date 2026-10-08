from pathlib import Path
import json,subprocess
D=Path(__file__).resolve().parents[1]
def run(cmd):
 r=subprocess.run(cmd,capture_output=True,text=True);assert r.returncode==0,r.stderr;return r.stdout
cpp=r"""
#include <cassert>
#include <iostream>
#include "../source/render/mouse_message_compat.h"
#include "../source/render/host_mouse_warp.h"
int main(){
 PalCraftMouseMessageCompat m;m.scope(true,true,7,9);m.host_baseline(7,640,360);
 assert(m.host_move(7,720,360,1280,720,1000.1,100).x==80&&m.wm.sequence==1);m.arm_host(7,640,360,1000.2);
 const char* json=R"({"client_target_x":640,"client_target_y":360,"consumed_sequence":1,"generation":9,"global_x":756,"global_y":476,"observed_unix":1000.3,"owner_token":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","phase":"observed","process_epoch":"10:12345","request_unix":1000.2,"schema":2,"viewport_height":720,"viewport_width":1280})";
 PalCraftHostMouseWarp p;assert(p.parse(json,std::strlen(json))&&p.sequence==1);
 assert(m.host_baseline(7,640,360,p.sequence)&&m.lastX==640); // Real centre query; no centre WM supplied.
 assert(m.host_move(7,720,360,1280,720,1000.4,101).x==80&&m.wm.sequence==2);
 assert(m.host_baseline(7,640,360,p.sequence)&&m.lastX==720); // Late older observation cannot overwrite new WM.
 assert(m.host_move(7,640,360,1280,720,1000.5,102).x==0); // Original one-shot centre WM still consumes.
 assert(m.host_move(7,720,360,1280,720,1000.6,103).x==80);
 assert(m.host_move(7,640,360,1280,720,1000.7,104).x==-80); // Human return after centre acknowledgement remains motion.
 std::cout<<"same prewarp WMseq and real centre may rebase without centreWM; newer WMseq is never overwritten; one-shot/human return retained: PASS"<<std::endl;
}
"""
(D/'checks/sequence_case.cpp').write_text(cpp)
run(['/usr/bin/nice','-n','19','/usr/bin/clang++','-std=c++17','-Wall','-Wextra',str(D/'checks/sequence_case.cpp'),'-o',str(D/'checks/sequence_case')]);out=run([str(D/'checks/sequence_case')])
s=(D/'source/mac/hud_overlay.swift').read_text();g=s[s.index('struct MacForegroundGroup:'):s.index('enum HUDProtocolError:')];plan=s[s.index('struct MacHostMousePlan {'):s.index('private func hudMonotonic()')]
old=(D/'checks/pure_consumption.swift').read_text();body=old[old.index('let group='):]
body=body.replace('input["mouse_wm_consumed"]=true;precondition(p.consumed(input:input,cursor:cursor))','input["mouse_wm_consumed"]=true;precondition(p.consumed(input:input,cursor:cursor))\nprecondition(!p.consumed(input:input,cursor:cursor,afterSequence:1))\ninput["mouse_wm_sequence"]=2;precondition(p.consumed(input:input,cursor:cursor,afterSequence:1))')
(D/'checks/pure_sequence.swift').write_text('import Foundation\nimport CoreGraphics\n'+g+plan+body)
run(['/usr/bin/nice','-n','19','/usr/bin/swiftc',str(D/'checks/pure_sequence.swift'),'-o',str(D/'checks/pure_sequence')]);out+=run([str(D/'checks/pure_sequence')])
(D/'checks/sequence-stdout.txt').write_text(out)
r={'schema':1,'ok':True,'additional_native_sequence_fixture_passed':True,'actual_HUD_sequence_reuse_refused_and_guards_passed':True,'original_two_queue_groups_preserved':'pre-sequence-review/checks/receipt.json','all_scope_coordinates_times_metadata_payload_synthetic':True,'no_centre_WM_fixture_does_not_fake_input_or_pose':True,'Game_GUI_RPC_or_runtime_operations':False,'actual_F03_or_each_missing_step_cause_proven':False}
(D/'checks/sequence-receipt.json').write_text(json.dumps(r,indent=2)+'\n');print(out+json.dumps(r))
