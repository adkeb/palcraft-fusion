#pragma once
#include <cstdio>
#include <cstring>
#include <cmath>

// Dedicated bounded record emitted by Foundation JSONSerialization.sortedKeys.
// These are observed Mac cursor coordinates and a viewport-center mapping;
// they never pretend to be a Win cursor observation or a game/world pose.
struct PalCraftHostMouseWarp {
 int schema=0,x=0,y=0,width=0,height=0;
 unsigned generation=0;
 double globalX=0,globalY=0,observed=0;
 char token[33]{},epoch[64]{};
 bool parse(const char* text,size_t bytes) {
  if(bytes==0||bytes>2048||text[bytes]!=0)return false;
  int end=-1;
  int count=std::sscanf(text,"{\"client_center_x\":%d,\"client_center_y\":%d,\"generation\":%u,\"global_x\":%lf,\"global_y\":%lf,\"observed_unix\":%lf,\"owner_token\":\"%32[0-9a-f]\",\"process_epoch\":\"%63[0-9:]\",\"schema\":%d,\"viewport_height\":%d,\"viewport_width\":%d}%n",
   &x,&y,&generation,&globalX,&globalY,&observed,token,epoch,&schema,&height,&width,&end);
  return count==11&&end==static_cast<int>(bytes)&&schema==1&&std::strlen(token)==32&&
   width>0&&width<=32768&&height>0&&height<=32768&&std::isfinite(globalX)&&std::isfinite(globalY)&&std::isfinite(observed);
 }
 bool matches(const char* owner,const char* process,unsigned gen,int w,int h,double now,double previous)const {
  return std::strcmp(token,owner)==0&&std::strcmp(epoch,process)==0&&generation==gen&&width==w&&height==h&&
   x==w/2&&y==h/2&&observed>previous&&now-observed>=-.25&&now-observed<=.5;
 }
};
