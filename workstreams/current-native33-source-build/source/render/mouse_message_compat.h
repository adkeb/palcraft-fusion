#pragma once
#include <cstdint>
#include <cstdlib>

// One current hook/connection/focus epoch. No second mouse source is added to
// RAW. Ordinary coordinates seed/rebase a point, never a world/camera pose.
struct PalCraftMouseMessageCompat {
 struct Delta { int x=0,y=0; };
 struct Warp { bool requested=false;int x=0,y=0; };
 bool enabled=false,eligible=false,rawSeen=false,point=false,usedMessage=false;
 bool warpPending=false;int warpX=0,warpY=0;uint64_t warpAt=0;
 uintptr_t window=0;int generation=-1,lastX=0,lastY=0;
 void scope(bool on,bool live,uintptr_t h,int gen) {
  if(on!=enabled||live!=eligible||h!=window||gen!=generation) {
   rawSeen=point=usedMessage=warpPending=false;
  }
  enabled=on;eligible=live;window=h;generation=gen;
 }
 bool raw() {
  if(!enabled||!eligible)return true;
  const bool overlap=!rawSeen&&usedMessage;
  rawSeen=true;point=warpPending=false;
  // Prefer no double turn at source transition: conservatively suppress at
  // most the first RAW packet after ordinary motion, even if it was distinct.
  return !overlap;
 }
 bool raw_motion(int x,int y){return (x!=0||y!=0)&&raw();}
 bool host_capture(bool hostMode)const{return hostMode&&eligible;}
 Delta move(uintptr_t h,int x,int y,int width,int height) {
  if(!enabled||!eligible||rawSeen||h!=window)return {};
  if(warpPending){
   if(x==warpX&&y==warpY){warpPending=false;lastX=x;lastY=y;point=true;}
   return {}; // The exact requested center is a baseline, never look motion.
  }
  if(x<0||y<0||x>=width||y>=height){point=false;return {};}
  if(!point){lastX=x;lastY=y;point=true;return {};}
  Delta d{x-lastX,y-lastY};lastX=x;lastY=y;
  // Seed a new point after a warp/discontinuous jump instead of accumulating
  // it. A normal small mouse stroke remains the original cumulative delta.
  if(std::abs(d.x)>128||std::abs(d.y)>128)return {};
  usedMessage|=d.x!=0||d.y!=0;
  return d;
 }
 Warp recenter(uintptr_t h,int width,int height,uint64_t now) {
  if(!enabled||!eligible||rawSeen||!point||warpPending||h!=window)return {};
  const int x=width/2,y=height/2;
  if(lastX==x&&lastY==y)return {};
  warpPending=true;warpX=x;warpY=y;warpAt=now;
  return {true,x,y};
 }
 void observe_cursor(uintptr_t h,int x,int y,int width,int height,uint64_t now) {
  if(!eligible||h!=window||!warpPending)return;
  if((x==warpX&&y==warpY)||now-warpAt>=100){
   warpPending=false;lastX=x;lastY=y;point=x>=0&&y>=0&&x<width&&y<height;
  }
 }
 void cancel_warp(uintptr_t h){if(h==window){warpPending=point=false;}}
 bool host_baseline(uintptr_t h,int x,int y) {
  if(!enabled||!eligible||rawSeen||h!=window)return false;
  lastX=x;lastY=y;point=true;warpPending=false;return true;
 }
};
