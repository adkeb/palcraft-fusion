#include "../source/render/host_mouse_warp.h"
#include "../source/render/mouse_message_compat.h"
#include <cassert>
#include <iostream>
int main(){
 const char* json="{\"client_center_x\":640,\"client_center_y\":360,\"generation\":8,\"global_x\":900,\"global_y\":578,\"observed_unix\":1000.0,\"owner_token\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"process_epoch\":\"1234:998877\",\"schema\":1,\"viewport_height\":720,\"viewport_width\":1280}";
 PalCraftHostMouseWarp seen;assert(seen.parse(json,std::strlen(json)));
 assert(seen.matches("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","1234:998877",8,1280,720,1000.1,999.0));
 PalCraftMouseMessageCompat m;m.scope(true,true,7,8);m.move(7,800,400,1280,720);
 long long look=50;assert(m.host_baseline(7,seen.x,seen.y));assert(look==50);
 auto delta=m.move(7,660,370,1280,720);look+=delta.x;assert(delta.x==20&&delta.y==10&&look==70);
 assert(m.raw()==false);assert(!m.host_baseline(7,640,360));assert(m.move(7,680,370,1280,720).x==0);
 m.scope(true,false,7,8);assert(!m.host_baseline(7,640,360));
 std::cout<<"matched observed warp rebases only; following ordinary motion is real; RAW/focus closes host baseline: PASS\n";
 assert(!seen.matches("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","1234:998877",8,1280,720,1000.1,999));
 assert(!seen.matches("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","1234:998878",8,1280,720,1000.1,999));
 assert(!seen.matches("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","1234:998877",9,1280,720,1000.1,999));
 assert(!seen.matches("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","1234:998877",8,640,360,1000.1,999));
 assert(!seen.matches("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","1234:998877",8,1280,720,1001,999));
 assert(!seen.matches("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","1234:998877",8,1280,720,1000.1,1000));
 assert(!seen.parse(json,2049));
 std::cout<<"stale/foreign token/epoch/generation/viewport and replay/oversized metadata refused: PASS\n";
}
