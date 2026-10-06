local Profiles=dofile(assert(arg[1])..'/client/material_profiles.lua')
local checks=0
local function check(v,why)assert(v,why);checks=checks+1 end
local address=1
local function object(t)
 t=t or{};address=address+1;t.address=address
 function t:IsValid()return not self.dead end
 function t:GetAddress()return self.address end
 return t
end
local texture=object()
local parents={}
for key,p in pairs(Profiles.parents)do
 local base=object({MaterialDomain=0})
 parents[p.parent]=object({blend=p.blend,base=base,params={[p.texture]=texture,['Normal Map']=texture,['Emissive Texture']=texture}})
 parents[p.parent].GetBlendMode=function(self)return self.blend end
 parents[p.parent].GetBaseMaterial=function(self)return self.base end
end
local calls={imports=0,creates=0,bakes=0,names={}};local time=0
local ctx=object()
local opts={json={},asset_root='/mock/models/',bridge_root='/mock/bridge/',name=function(n)return n end,seconds=function()return time end,
 load_asset=function(path)return parents[path]or texture end,
 create_material=function(c,parent,name)
  calls.creates=calls.creates+1
  check(not calls.names[name],'unique MID names across profile instances/reloads')
  calls.names[name]=true
  local m=object({parent=parent,params={},scalars={}})
  function m:K2_GetTextureParameterValue(n)return self.params[n]or self.parent.params[n]end
  function m:SetTextureParameterValue(n,v)self.params[n]=v end
  function m:SetScalarParameterValue(n,v)self.scalars[n]=v end
  return m
 end,
 import_texture=function(c,path)calls.imports=calls.imports+1;return object({path=path})end,
 pixel_index={source_root='test-snapshot',textures={['textures/minecraft/block/grass_block_top.png']={path='textures/minecraft/block/grass_block_top.png.rgba',width=256,height=256,sha256='abc123'}}},
 bake_texture=function(input,output,w,h,rgb)calls.bakes=calls.bakes+1;check(rgb==0x91bd59,'exact caller tint');return '/mock/bridge/'..output end}
local module=Profiles.new(opts)
local value=assert(module:resolve(ctx,{texture='minecraft:block/oak_planks',shade=true,alpha_mode='opaque',tint=-1}))
check(value.material.params['Base Texture']==value.texture,'real texture parameter')
check(value.material.scalars['ChangeColor Rate']==0,'no extra recoloring')
check(not value.shader_verified,'runtime visual proof stays pending')
check(module:resolve(ctx,{texture='minecraft:block/oak_planks',shade=true,tint=-1})==value,'shared material cache')
local tinted=assert(module:resolve(ctx,{texture='minecraft:block/grass_block_top',alpha_mode='opaque',tint=0},{tint_colors={['0']=0x91bd59}}))
check(calls.bakes==1 and tinted.path:find('91bd59'),'baked tint path')
local baked=assert(Profiles.descriptor({texture='minecraft:palcraft/entity/banner/red',tint=0,texture_meta={baked_diffuse_tint=true}},{}))
check(baked.tint_rgb==nil,'baked banners are never tinted twice')
local missing,why=Profiles.descriptor({texture='minecraft:block/oak_leaves',alpha_mode='cutout',tint=0})
check(not missing and why=='minecraft_block_color_required','never guess all tint0 green')
local leaf=assert(module:resolve(ctx,{texture='minecraft:block/glass',alpha_mode='cutout',tint=-1}))
check(leaf.descriptor.expected_blend==1,'compiled masked parent selected')
local group={texture='minecraft:block/fire_0',alpha_mode='cutout',shade=false,tint=-1,
 texture_meta={animation={frames={{index=16,time=1},{index=0,time=2}},frames_dir='textures/minecraft/block/fire_0.frames/',ticks_per_second=20,interpolate=false}}}
local fire=assert(module:resolve(ctx,group))
check(fire.path:find('0016.png'),'original first animation index')
check(module:tick(.05),'timeline step')
check(fire.path:find('0000.png'),'next cropped frame')
check(module:tick(.15),'timeline wrap')
check(fire.path:find('0016.png'),'loop first original frame')
local lava=assert(module:resolve(ctx,{texture='minecraft:block/lava_still',alpha_mode='opaque',tint=-1,light_emission=15,
 texture_meta={animation={frames={{index=0,time=1},{index=1,time=1}},frames_dir='textures/minecraft/block/lava_still.frames/',ticks_per_second=20,interpolate=false}}}))
check(module:tick(.05),'emitting frame step')
check(lava.material.params['Emissive Texture']==lava.texture,'emission follows the same animated frame')
local reloaded=dofile(assert(arg[1])..'/client/material_profiles.lua')
local another=reloaded.new(opts)
check(another:resolve(ctx,{texture='minecraft:block/stone',alpha_mode='opaque'})~=nil,'profile reload has no duplicate FName')
local translucent,error=Profiles.descriptor({texture='minecraft:block/glass',alpha_mode='translucent',texture_meta={alpha_mode='cutout'}})
check(not translucent and error=='translucent_parent_not_probed','group transparency overrides PNG classification')
local interpolated,message=Profiles.descriptor({texture='minecraft:block/water_still',texture_meta={animation={frames={{index=0,time=1}},interpolate=true}}})
check(not interpolated and message:find('interpolated'),'do not silently skip interpolation')
local null=assert(Profiles.descriptor({texture='minecraft:block/stone',texture_meta={animation={}}}))
check(not null.animation,'JSON null/empty table never becomes playback')
local masked=parents[Profiles.parents.cutout.parent];masked.blend=0
module:reset()
local wrong,problem=module:resolve(ctx,{texture='minecraft:block/short_grass',alpha_mode='cutout'})
check(not wrong and problem=='parent_blend_mismatch','opaque parent never used for cutout')
masked.blend=1;masked.params['Base Texture']=nil
local no_parameter,reason=module:resolve(ctx,{texture='minecraft:block/short_grass',alpha_mode='cutout'})
check(not no_parameter and reason=='parent_texture_parameter_missing','unknown texture parameter is rejected before override')
print(string.format('{"status":"passed","checks":%d,"runtime_calls":0,"mode":"night_low_power_light_contract"}',checks))
