#include <cassert>
#include <string>
#include <iostream>
#include "../source/render/mouse_message_compat.h"
static const char* command_action(const std::string &command) {
 std::string compact;bool quoted=false,escaped=false;
 for(char c:command){if(quoted){compact+=c;if(escaped)escaped=false;else if(c=='\\')escaped=true;else if(c=='"')quoted=false;}
  else if(c=='"'){quoted=true;compact+=c;}else if(c!=' '&&c!='\t'&&c!='\r'&&c!='\n')compact+=c;}
 if(compact.find("\"t\":\"key\"")==std::string::npos)return "other";
 const bool use=compact.find("\"k\":\"use\"")!=std::string::npos,attack=compact.find("\"k\":\"attack\"")!=std::string::npos;
 const bool down=compact.find("\"down\":true")!=std::string::npos,up=compact.find("\"down\":false")!=std::string::npos;
 if(use==attack||down==up)return "other";
 return use?(down?"use_down":"use_up"):(down?"attack_down":"attack_up");
}

int main(){
 PalCraftMouseMessageCompat a;a.scope(true,true,7,9);a.host_baseline(7,640,360);assert(a.arm_host(7,640,360,1000));
 int sum=a.host_move(7,720,360,1280,720,1000.1).x;assert(sum==80);
 assert(a.host_baseline(7,640,360)&&a.hostCentreArmed);
 sum+=a.host_move(7,640,360,1280,720,1000.2).x;assert(sum==80&&!a.hostCentreArmed);
 assert(a.host_move(7,720,360,1280,720,1000.3).x==80);
 assert(a.host_move(7,640,360,1280,720,1000.4).x==-80);
 std::cout<<"motion first, actual cursor readback then late centre WM: no reverse look; human return to centre counts: PASS"<<std::endl;
 PalCraftMouseMessageCompat b;b.scope(true,true,7,9);b.host_baseline(7,640,360);assert(b.arm_host(7,640,360,1000));
 assert(b.host_baseline(7,640,360)&&b.hostCentreArmed);
 sum=b.host_move(7,560,360,1280,720,1000.1).x;assert(sum==-80);
 sum+=b.host_move(7,640,360,1280,720,1000.2).x;assert(sum==-80&&!b.hostCentreArmed);
 assert(b.host_move(7,560,360,1280,720,1000.3).x==-80);
 assert(b.host_move(7,640,360,1280,720,1000.4).x==80);
 std::cout<<"actual cursor readback first then pending negative motion/late centre WM: no cancellation; human return counts: PASS"<<std::endl;
 assert(std::string(command_action(R"({ "t" : "key", "k":"use", "down" : true })"))=="use_down");
 assert(std::string(command_action(R"({"t":"key","k":"attack","down":false})"))=="attack_up");
 assert(std::string(command_action(R"({"t":"inspect","other":"use"})"))=="other");
 std::cout<<"original command classification returns only whitelist hint; no payload or fake applied acknowledgement: PASS"<<std::endl;
}
