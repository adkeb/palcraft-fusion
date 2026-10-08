
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
