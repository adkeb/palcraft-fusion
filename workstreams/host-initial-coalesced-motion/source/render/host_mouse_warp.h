#pragma once
#include <cstdio>
#include <cstring>
#include <cmath>

// Dedicated bounded record emitted by Foundation JSONSerialization.sortedKeys.
// These are observed Mac cursor coordinates and a viewport-center mapping;
// they never pretend to be a Win cursor observation or a game/world pose.
struct PalCraftHostMouseWarp {
 int schema=0,x=0,y=0,width=0,height=0;
 unsigned generation=0;unsigned long long sequence=0;
 double globalX=0,globalY=0,observed=0,requested=0;
 char token[33]{},epoch[64]{},phase[9]{};
 bool parse(const char* text,size_t bytes) {
  if(bytes==0||bytes>2048||text[bytes]!=0)return false;
  int end=-1;
  int count=std::sscanf(text,"{\"client_target_x\":%d,\"client_target_y\":%d,\"consumed_sequence\":%llu,\"generation\":%u,\"global_x\":%lf,\"global_y\":%lf,\"observed_unix\":%lf,\"owner_token\":\"%32[0-9a-f]\",\"phase\":\"%8[a-z]\",\"process_epoch\":\"%63[0-9:]\",\"request_unix\":%lf,\"schema\":%d,\"viewport_height\":%d,\"viewport_width\":%d}%n",
   &x,&y,&sequence,&generation,&globalX,&globalY,&observed,token,phase,epoch,&requested,&schema,&height,&width,&end);
  return count==14&&end==static_cast<int>(bytes)&&schema==2&&std::strlen(token)==32&&
   width>0&&width<=32768&&height>0&&height<=32768&&std::isfinite(globalX)&&std::isfinite(globalY)&&std::isfinite(observed)&&std::isfinite(requested)&&
   (std::strcmp(phase,"request")==0||std::strcmp(phase,"observed")==0);
 }
 bool matches(const char* owner,const char* process,unsigned gen,int w,int h,double now)const {
  return std::strcmp(token,owner)==0&&std::strcmp(epoch,process)==0&&generation==gen&&width==w&&height==h&&
   x==w/2&&y==h/2&&now-requested>=-.25&&now-requested<1;
 }
 bool is_request()const{return std::strcmp(phase,"request")==0;}
 bool actual_observed(double now)const{return std::strcmp(phase,"observed")==0&&observed>=requested&&now-observed>=-.25&&now-observed<=.5;}
};
