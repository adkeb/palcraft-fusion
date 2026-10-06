#pragma once
// Portable texture preparation and UE parameter ABI descriptions. No shader
// compilation, BlendMode override, actor spawn, or engine pointer mutation.
#include <cstdint>
#include <cstddef>
#include <vector>
#include <string>
#include <stdexcept>
#include <fstream>
#include <algorithm>

namespace palcraft::materials {
constexpr uint32_t version = 1;
struct Profile {
    const char *id, *parent_asset, *texture_parameter;
    uint8_t required_blend;
    bool lit;
};
inline constexpr Profile opaque{"opaque_prop",
    "/Game/Pal/Material/Prop/MI_PalPropBase.MI_PalPropBase", "Base Texture", 0, true};
inline constexpr Profile cutout{"cutout_foliage",
    "/Game/Pal/Material/Nature/MI_PalLit_Foliage.MI_PalLit_Foliage", "Base Texture", 1, true};
inline constexpr Profile cutout_unlit{"cutout_sprite_unlit",
    "/Paper2D/MaskedUnlitSpriteMaterial.MaskedUnlitSpriteMaterial", "SpriteTexture", 1, false};
// Names and parameter offsets are from the local UE4SS_ObjectDump, not hardcoded
// UObject offsets. The owner may invoke these only through resolved UFunctions.
struct Name { uint32_t index, number; };
struct LinearColor { float r,g,b,a; };
struct SetTexture { Name name; uint64_t texture; };
struct SetScalar { Name name; float value; };
struct SetVector { Name name; LinearColor value; };
static_assert(sizeof(Name)==8 && offsetof(SetTexture,texture)==8 && sizeof(SetTexture)==16);
static_assert(offsetof(SetScalar,value)==8 && sizeof(SetScalar)==12);
static_assert(offsetof(SetVector,value)==8 && sizeof(SetVector)==24);

struct BakeRequest {
    char magic[8];
    uint32_t width,height,tint_rgb,input_bytes,output_bytes,reserved;
};
static_assert(sizeof(BakeRequest)==32);
inline void validate(uint32_t w,uint32_t h,size_t bytes) {
    if(!w || !h || w>1024 || h>1024 || uint64_t(w)*h*4!=bytes)
        throw std::runtime_error("invalid RGBA dimensions");
}
inline std::vector<uint8_t> tint_rgba(const std::vector<uint8_t>&rgba,uint32_t tint_rgb,bool already_baked=false) {
    if(rgba.size()%4 || tint_rgb>0xffffff)throw std::runtime_error("invalid tint/RGBA");
    std::vector<uint8_t> result=rgba;
    if(already_baked)return result;
    const uint32_t color[3]={(tint_rgb>>16)&255,(tint_rgb>>8)&255,tint_rgb&255};
    for(size_t i=0;i<result.size();i+=4)for(size_t c=0;c<3;c++)
        result[i+c]=uint8_t(uint32_t(result[i+c])*color[c]/255);
    // Straight PNG alpha is unchanged. The texture sampler/parent owns masking.
    return result;
}
inline uint32_t crc32(const uint8_t *p,size_t n) {
    uint32_t crc=~uint32_t(0);
    for(size_t i=0;i<n;i++){crc^=p[i];for(int b=0;b<8;b++)crc=(crc>>1)^(0xedb88320u&uint32_t(-int32_t(crc&1)));}
    return ~crc;
}
inline void be32(std::vector<uint8_t>&v,uint32_t n){v.push_back(n>>24);v.push_back(n>>16);v.push_back(n>>8);v.push_back(n);}
inline void chunk(std::vector<uint8_t>&png,const char *kind,const std::vector<uint8_t>&data) {
    be32(png,uint32_t(data.size()));
    size_t start=png.size();
    png.insert(png.end(),kind,kind+4);png.insert(png.end(),data.begin(),data.end());
    be32(png,crc32(png.data()+start,4+data.size()));
}
inline std::vector<uint8_t> png_rgba(uint32_t w,uint32_t h,const std::vector<uint8_t>&rgba) {
    validate(w,h,rgba.size());
    std::vector<uint8_t> raw;raw.reserve(rgba.size()+h);
    for(uint32_t y=0;y<h;y++){raw.push_back(0);raw.insert(raw.end(),rgba.begin()+size_t(y)*w*4,rgba.begin()+size_t(y+1)*w*4);}
    // Stored DEFLATE blocks avoid a runtime compressor dependency. Tint variants
    // are cached once; original/pre-cropped model PNGs keep their compression.
    std::vector<uint8_t> z{0x78,0x01};
    uint32_t a=1,b=0;
    for(uint8_t c:raw){a=(a+c)%65521;b=(b+a)%65521;}
    for(size_t i=0;i<raw.size();) {
        uint32_t count=uint32_t(std::min<size_t>(65535,raw.size()-i));
        z.push_back(i+count==raw.size()?1:0);
        z.push_back(count&255);z.push_back(count>>8);z.push_back((~count)&255);z.push_back(((~count)>>8)&255);
        z.insert(z.end(),raw.begin()+i,raw.begin()+i+count);i+=count;
    }
    be32(z,(b<<16)|a);
    std::vector<uint8_t> png{137,80,78,71,13,10,26,10},ihdr;
    be32(ihdr,w);be32(ihdr,h);ihdr.insert(ihdr.end(),{8,6,0,0,0});
    chunk(png,"IHDR",ihdr);chunk(png,"sRGB",{0});chunk(png,"IDAT",z);chunk(png,"IEND",{});
    return png;
}
inline bool relative_path(const std::string&p) {
    if(p.empty() || p.size()>1024 || p.front()=='/' || p.front()=='\\' || p.find("..")!=std::string::npos)return false;
    for(unsigned char c:p)if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='-'||c=='/'||c=='.'))return false;
    return true;
}
} // namespace palcraft::materials
