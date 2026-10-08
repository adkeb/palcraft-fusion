#include "../source/render/mouse_message_compat.h"
#include "../source/render/host_mouse_warp.h"
#include <cassert>
#include <iostream>
int main(){
 PalCraftMouseMessageCompat m;m.scope(true,true,7,9);m.move(7,640,360,1280,720);
 long long look=0;
 for(int i=0;i<20;++i){const double request=1000+i*.2;assert(m.arm_host(7,640,360,request));
  auto d=m.host_move(7,720,360,1280,720,request+.01);assert(d.x==80);look+=d.x;
  d=m.host_move(7,640,360,1280,720,request+.02);assert(d.x==0&&d.y==0);assert(!m.hostCentreArmed);}
 assert(look==1600); // Pending never drops noncenter ordinary movement; warp never subtracts it.
 auto human=m.host_move(7,720,360,1280,720,1003.9);assert(human.x==80);
 human=m.host_move(7,640,360,1280,720,1003.91);assert(human.x==-80); // Another ordinary visit to center is motion.
 assert(m.arm_host(7,640,360,1004));assert(m.host_baseline(7,640,360)&&!m.hostCentreArmed);
 const char* request="{\"client_target_x\":640,\"client_target_y\":360,\"generation\":9,\"global_x\":760,\"global_y\":477,\"observed_unix\":0,\"owner_token\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"phase\":\"request\",\"process_epoch\":\"2852:123456\",\"request_unix\":1000,\"schema\":2,\"viewport_height\":720,\"viewport_width\":1280}";
 PalCraftHostMouseWarp r;assert(r.parse(request,std::strlen(request))&&r.is_request()&&!r.actual_observed(1000.2));
 assert(r.matches("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","2852:123456",9,1280,720,1000.2));
 assert(!r.matches("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","2852:123456",9,1280,720,1000.2));
 assert(!r.matches("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","2852:654321",9,1280,720,1000.2));
 m.scope(true,false,7,9);assert(!m.arm_host(7,640,360,1001));
 std::cout<<"ordinary20x80 accumulates1600; armed center never cancels; request/observation and foreign scope distinguished: PASS\n";
}
