local Wrapper=dofile(assert(arg[1])..'/client/material_profiles_interpolation.lua')
local checks=0
local function check(v,why)assert(v,why);checks=checks+1 end
local function obj(t)t=t or{};function t:IsValid()return true end;function t:GetAddress()return 9 end;return t end
local inherited=obj()
local parent=obj({MaterialDomain=0})
function parent:GetBlendMode()return 0 end
function parent:GetBaseMaterial()return self end
local paths={}
local provider=Wrapper.new({json={},asset_root='D:/bridge/models-v4/',name=function(x)return x end,seconds=function()return 0 end,
 load_asset=function()return parent end,
 import_texture=function(ctx,path)paths[#paths+1]=path;return obj({path=path})end,
 create_material=function(ctx,p,name)
  local m=obj({textures={}})
  function m:K2_GetTextureParameterValue(key)return inherited end
  function m:SetTextureParameterValue(key,v)self.textures[key]=v end
  function m:SetScalarParameterValue()end
  return m
 end}, {version=1,sprites={['minecraft:block/prismarine']={source_sha256='abc',source_duration_ticks=3,
 animation={frames={{index=0,time=1},{index=1,time=1},{index=2,time=1}},frames_dir='__palcraft_interpolation/hash/',ticks_per_second=20,interpolate=false}}}},
 'D:/bridge/material-interpolation-v1/')
local group={texture='minecraft:block/prismarine',alpha_mode='opaque',tint=-1,texture_meta={source_sha256='abc',
 animation={frames={{index=0,time=3}},interpolate=true}}}
local value=assert(provider:resolve(obj(),group))
check(paths[1]=='D:/bridge/material-interpolation-v1/__palcraft_interpolation/hash/0000.png','derived import mapping')
check(group.texture_meta.animation.interpolate==true,'frozen group metadata never changed')
check(provider:tick(.05),'new exact tick')
check(paths[2]:find('0001.png'),'pre-interpolated frame reached')
local imports=#paths;check(provider:tick(.05),'same tick')
check(#paths==imports,'same tick has no texture reimport')
check(provider:tick(.15),'loop')
check(value.path:find('0000.png'),'loop existing texture cache')
local bad={texture=group.texture,tint=-1,texture_meta={source_sha256='different',animation={interpolate=true}}}
local no,why=provider:resolve(obj(),bad)
check(not no and why=='interpolation_source_hash_mismatch','reject mismatched source package')
check(provider:status().shader_visible_verified==false,'no shader capability promotion')
print(string.format('{"status":"passed","checks":%d,"engine_calls":0,"mode":"night_low_power_light_contract"}',checks))
