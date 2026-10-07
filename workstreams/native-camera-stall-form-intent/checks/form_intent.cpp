// Four bounded native source cases. No WinAPI, Game or Wine process is used.
#include "../source/render/form_requests.h"
#include "actual_predicates.hpp"
#include <cassert>
#include <iostream>
int main(){
 std::atomic<bool> build{true},menu{true};
 auto reset=[&](bool active,bool connected,bool newConnection,bool suspended){if(actual_reset(active,connected,newConnection,suspended))palcraft_set_form_mode(build,menu,false);};
 reset(false,true,false,false);
 assert(build&&menu&&!actual_live(false,true,true,true,false));
 reset(true,true,false,false);assert(build&&menu&&actual_live(true,true,true,true,false));
 assert(!actual_live(true,true,false,true,false)&&!actual_live(true,true,true,false,false));
 std::cout<<"PASS transient_camera_stall_keeps_intent_while_stale_and_unfocused_input_stays_ineligible\n";
 for(int scenario=0;scenario<3;++scenario){
  build=true;menu=true;reset(scenario==0?false:true,scenario!=1,scenario==2,scenario==0);assert(!build&&!menu);
 }
 std::cout<<"PASS stopped_inactive_disconnected_and_changed_generation_clear_mode_and_menu\n";
 PalCraftFormRequests requests;requests.observed_generation(276);
 build=true;menu=true;requests.submit(false);
 int desired=requests.take(276,false,false,false);assert(desired==0);palcraft_set_form_mode(build,menu,desired==1);assert(!build&&!menu);
 requests.submit(true);assert(requests.take(276,false,false,false)==-1);assert(requests.take(276,true,false,false)==-1);
 requests.submit(true);assert(requests.take(276,true,false,true)==-1);
 requests.submit(true);assert(requests.take(277,true,true,false)==-1);
 requests.observed_generation(276);requests.submit(false);assert(requests.take(277,false,false,false)==-1);
 std::cout<<"PASS explicit_same_generation_off_clears_stall_but_on_paused_or_stale_requests_remain_rejected\n";
 assert(actual_exit_only(false,true,false,true,false,true,true,false,true));
 assert(!actual_exit_only(false,false,false,true,false,true,true,false,true));
 assert(!actual_exit_only(false,true,true,true,false,true,true,false,true));
 assert(!actual_exit_only(false,true,false,true,false,true,false,false,true));
 assert(!actual_exit_only(false,true,false,true,false,true,true,true,true));
 assert(!actual_exit_only(false,true,false,true,true,true,true,false,true));
 build=true;menu=true;palcraft_set_form_mode(build,menu,false);assert(!build&&!menu);
 std::cout<<"PASS physical_F5_stall_exit_requires_existing_intent_fresh_edge_foreground_scope_and_shared_exit_setter\n";
 std::cout<<"RESULT 4 PASS; source-only synthetic intent/focus cases; no real input/ready/ACK proof\n";
}
