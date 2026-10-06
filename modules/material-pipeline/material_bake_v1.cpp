// Offline-built optional Lua loadlib bridge. It consumes only a texture bake
// request in the configured bridge root; it never calls Unreal or game actions.
#include "../palcraft/native/material_profiles_v1.hpp"
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <filesystem>
#if defined(_WIN32)
#include <windows.h>
#endif
namespace pm=palcraft::materials;
static std::filesystem::path root() {
#if defined(_WIN32)
 wchar_t path[2048]{};
 DWORD n=GetEnvironmentVariableW(L"PALCRAFT_BRIDGE_DIR",path,2048);
 if(n>0&&n<2048)return std::filesystem::path(path);
 return std::filesystem::path(L"D:/PalworldServer-LAN/PalCraft-Dev/bridge");
#else
 if(const char*p=std::getenv("PALCRAFT_BRIDGE_DIR"))return p;
 throw std::runtime_error("bridge root required");
#endif
}
static void execute() {
 auto base=root();
 std::ifstream file(base/"material-bake-request.bin",std::ios::binary);
 pm::BakeRequest q{};
 if(!file.read(reinterpret_cast<char*>(&q),sizeof(q)) || std::memcmp(q.magic,"PALCMAT1",8) ||
    q.reserved || q.input_bytes>1024 || q.output_bytes>1024 || q.tint_rgb>0xffffff)
    throw std::runtime_error("invalid bake request");
 std::string input(q.input_bytes,'\0'),output(q.output_bytes,'\0');
 if(!file.read(input.data(),input.size())||!file.read(output.data(),output.size())||file.peek()!=EOF||
    !pm::relative_path(input)||!pm::relative_path(output)||input.find("material-pixels-v1/")!=0||
    output.find("material-cache-v1/")!=0)throw std::runtime_error("invalid bake paths");
 pm::validate(q.width,q.height,size_t(q.width)*q.height*4);
 std::vector<uint8_t> rgba(size_t(q.width)*q.height*4);
 std::ifstream source(base/input,std::ios::binary);
 if(!source.read(reinterpret_cast<char*>(rgba.data()),rgba.size())||source.peek()!=EOF)throw std::runtime_error("invalid source pixels");
 auto png=pm::png_rgba(q.width,q.height,pm::tint_rgba(rgba,q.tint_rgb));
 auto target=base/output;std::filesystem::create_directories(target.parent_path());
 auto temp=target;temp+=".pending";
 {std::ofstream f(temp,std::ios::binary|std::ios::trunc);if(!f.write(reinterpret_cast<char*>(png.data()),png.size()))throw std::runtime_error("PNG write failed");}
 std::error_code error;std::filesystem::remove(target,error);std::filesystem::rename(temp,target);
}
#if defined(_WIN32)
#define EXPORT extern "C" __declspec(dllexport)
#else
#define EXPORT extern "C"
#endif
EXPORT int palcraft_bake_material_texture(void*) {
 bool ok=false;
 try {execute();ok=true;}catch(...){}
 try {std::ofstream f(root()/"material-bake-result.json",std::ios::trunc);f<<(ok?"{\"ok\":true,\"version\":1}":"{\"ok\":false,\"version\":1,\"stage\":\"bake\"}");}catch(...){}
 return 0; // Lua CFunction returns zero values; resolver reads the result file.
}
#ifdef PALCRAFT_MATERIAL_TEST
int main(){palcraft_bake_material_texture(nullptr);}
#endif
