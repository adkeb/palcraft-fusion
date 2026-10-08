
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
