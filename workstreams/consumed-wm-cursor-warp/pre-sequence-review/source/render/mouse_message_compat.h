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
 int hostX=0,hostY=0;double hostRequest=0;bool hostCentreArmed=false;
 struct WMObservation{uint64_t received=0,look=0,centre=0,seed=0,jump=0,gate=0,outside=0,readbackSeeds=0,readbackVerifies=0;
  int x=0,y=0;uint64_t sequence=0,tick=0;bool consumed=false;const char*reason="none";}wm;
 void scope(bool on,bool live,uintptr_t h,int gen) {
  if(on!=enabled||live!=eligible||h!=window||gen!=generation) {
   rawSeen=point=usedMessage=warpPending=false;
   hostRequest=0;hostCentreArmed=false;wm.consumed=false;
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
 bool arm_host(uintptr_t h,int x,int y,double request) {
  if(!eligible||h!=window||request<=hostRequest)return false;
  hostX=x;hostY=y;hostRequest=request;hostCentreArmed=true;return true;
 }
 void host_rejected(){++wm.received;++wm.gate;wm.consumed=false;wm.reason="gate";}
 Delta host_move(uintptr_t h,int x,int y,int width,int height,double now,uint64_t tick=0) {
  ++wm.received;wm.consumed=false;
  if(!enabled||!eligible||rawSeen||h!=window){++wm.gate;wm.reason="gate";return {};}
  if(hostCentreArmed&&(now-hostRequest<0||now-hostRequest>=1))hostCentreArmed=false;
  Delta d{};
  if(hostCentreArmed&&x==hostX&&y==hostY){
   hostCentreArmed=false;lastX=x;lastY=y;point=true;++wm.centre;wm.reason="centre";
  }else{
   const bool hadPoint=point;const int dx=x-lastX,dy=y-lastY;
   d=move(h,x,y,width,height);
   if(x<0||y<0||x>=width||y>=height){++wm.outside;wm.reason="outside";}
   else if(!hadPoint){++wm.seed;wm.reason="seed";}
   else if(std::abs(dx)>128||std::abs(dy)>128){++wm.jump;wm.reason="jump";}
   else if(d.x||d.y){++wm.look;wm.reason="look";}else wm.reason="zero";
  }
  if(point&&x>=0&&y>=0&&x<width&&y<height){wm.x=x;wm.y=y;wm.sequence=wm.received;wm.tick=tick;wm.consumed=true;}
  return d;
 }
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
  if(point){++wm.readbackVerifies;return true;} // A cursor query must never overwrite a consumed WM baseline.
  lastX=x;lastY=y;point=true;warpPending=false;++wm.readbackSeeds;return true;
 }
};
