#include "../source/render/mouse_message_compat.h"
#include <cassert>
#include <iostream>
int main(){
 {
  PalCraftMouseMessageCompat m;m.scope(true,true,7,3);
  assert(m.move(7,620,350,1280,720).x==0);
  auto d=m.move(7,640,360,1280,720);assert(d.x==20&&d.y==10);
  // Exact center crossing is real motion when no own warp was requested.
  for(int i=0;i<10;i++){
   d=m.move(7,660,360,1280,720);assert(d.x==20&&d.y==0);
   auto warp=m.recenter(7,1280,720,10+i);assert(warp.requested&&warp.x==640&&warp.y==360);
   d=m.move(7,640,360,1280,720);assert(d.x==0&&d.y==0);
  }
  std::cout<<"ordinary small deltas and unlimited tracked center-warp cycles: PASS\n";
 }
 {
  PalCraftMouseMessageCompat m;m.scope(true,true,7,3);
  m.move(7,600,300,1280,720);assert(m.move(7,620,300,1280,720).x==20);
  assert(!m.raw());assert(m.rawSeen);
  assert(m.move(7,640,300,1280,720).x==0);assert(!m.recenter(7,1280,720,10).requested);
  assert(m.raw()); // All later packets exclusively retain the original RAW path.
  PalCraftMouseMessageCompat first;first.scope(true,true,7,3);assert(first.raw());
  assert(first.move(7,620,300,1280,720).x==0);
  PalCraftMouseMessageCompat off;off.scope(false,true,7,3);assert(off.raw());
  assert(off.move(7,620,300,1280,720).x==0);
  std::cout<<"RAW-first/RAW-switch exclusive and Windows/default RAW unchanged: PASS\n";
 }
 {
  PalCraftMouseMessageCompat m;m.scope(true,true,7,3);m.move(7,600,300,1280,720);
  m.scope(true,false,7,3);assert(m.move(7,620,300,1280,720).x==0);assert(!m.recenter(7,1280,720,10).requested);
  m.scope(true,true,7,3);assert(m.move(7,620,300,1280,720).x==0);
  m.scope(true,true,8,3);assert(m.move(7,640,300,1280,720).x==0);assert(m.move(8,640,300,1280,720).x==0);
  m.scope(true,true,8,4);assert(m.move(8,660,300,1280,720).x==0);
  assert(m.move(8,1000,600,1280,720).x==0);
  auto warp=m.recenter(8,1280,720,10);assert(warp.requested);
  assert(m.move(8,640,360,1280,720).x==0);
  assert(m.move(8,660,360,1280,720).x==20);
  m.scope(true,false,8,4);m.scope(true,true,8,4);assert(m.move(8,900,400,1280,720).x==0);
  std::cout<<"focus/menu/window/generation reset, large jump and synthetic warp ignored: PASS\n";
 }
 {
  PalCraftMouseMessageCompat m;m.scope(true,true,7,3);m.move(7,660,360,1280,720);
  assert(m.recenter(7,1280,720,0).requested);assert(m.warpPending);
  // No WM_MOUSEMOVE acknowledgement: only a real cursor read observes center.
  m.observe_cursor(7,640,360,1280,720,8);assert(!m.warpPending);
  assert(m.move(7,660,360,1280,720).x==20);
  assert(m.recenter(7,1280,720,10).requested);
  m.observe_cursor(7,700,360,1280,720,50);assert(m.warpPending);
  m.observe_cursor(7,700,360,1280,720,111);assert(!m.warpPending);
  assert(m.move(7,720,360,1280,720).x==20);
  std::cout<<"no message ACK: real cursor center or bounded deadline rebases without stuck input: PASS\n";
 }
}
