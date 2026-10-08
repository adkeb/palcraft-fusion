#include "../source/render/mouse_message_compat.h"
#include <cassert>
#include <iostream>
int main(){
 PalCraftMouseMessageCompat state;state.scope(true,true,7,3);
 assert(!state.raw_motion(0,0)&&!state.rawSeen);
 assert(state.host_capture(true));
 assert(state.raw_motion(12,-3)&&state.rawSeen);
 assert(state.host_capture(true)); // Physical cursor capture is independent of RAW motion authority.
 assert(state.move(7,640,360,1280,720).x==0);
 assert(state.move(7,660,370,1280,720).x==0);
 assert(!state.host_baseline(7,640,360)); // Host metadata never manufactures RAW or look.
 assert(state.raw_motion(-8,2));
 state.scope(true,false,7,3);assert(!state.host_capture(true));
 std::cout<<"zero-motion does not select RAW; RAW motion retains host capture but refuses ordinary delta/baseline: PASS (synthetic scope only)\n";
}
