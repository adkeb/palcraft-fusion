
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
