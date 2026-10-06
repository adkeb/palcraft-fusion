#include "../../palcraft/native/material_profiles_v1.hpp"
#include <cassert>
#include <fstream>
#include <iostream>
using namespace palcraft::materials;
int main(int argc,char**argv) {
 assert(argc==2);
 std::vector<uint8_t> pixels{255,128,0,0,0,255,128,255,20,40,60,127,100,80,60,0,255,255,255,255,0,0,0,255};
 auto tinted=tint_rgba(pixels,0x804020);
 assert(tinted[0]==128&&tinted[1]==32&&tinted[2]==0&&tinted[3]==0);
 for(size_t i=3;i<pixels.size();i+=4)assert(tinted[i]==pixels[i]);
 assert(tint_rgba(pixels,0x123456,true)==pixels);
 auto png=png_rgba(3,2,tinted);
 std::ofstream file(argv[1],std::ios::binary);file.write(reinterpret_cast<char*>(png.data()),png.size());file.close();
 std::vector<uint8_t> large(128*128*4,0x77); // Crosses a stored-DEFLATE block boundary.
 auto second=png_rgba(128,128,large);
 std::ofstream another(std::string(argv[1])+".large.png",std::ios::binary);
 another.write(reinterpret_cast<char*>(second.data()),second.size());another.close();
 bool rejected=false;try{png_rgba(0,2,pixels);}catch(...){rejected=true;}assert(rejected);
 rejected=false;try{tint_rgba({1,2,3},0xffffff);}catch(...){rejected=true;}assert(rejected);
 assert(relative_path("textures/minecraft/block/oak_leaves.png.rgba"));
 assert(!relative_path("../saves/world.dat")&&!relative_path("/etc/passwd")&&!relative_path("D:/data")&&!relative_path("foo\"bar"));
 std::cout<<"{\"status\":\"passed\",\"runtime_assertions\":13,\"engine_calls\":0,\"mode\":\"night_low_power_single_worker\"}\n";
}
