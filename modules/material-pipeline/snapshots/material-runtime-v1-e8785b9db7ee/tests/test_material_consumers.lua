local dir=assert(arg[1])
local Tint=dofile(dir..'/client/biome_tint_consumer.lua')
local Widget=dofile(dir..'/client/widget_surface_materials.lua')
local count=0;local function check(v,why)assert(v,why);count=count+1 end
local scope={mc_uuid='bound',world_session='w',dim='minecraft:overworld',view=1}
local t=Tint.new();t:bind(scope)
local event={mc_uuid='bound',world_session='w',dim=scope.dim,view=1,source='minecraft:material_tint_v1',read_only=true,
 rows={{x=1,y=64,z=2,id='minecraft:oak_leaves',tint_source='minecraft:block_tint_source.colorInWorld',tint_colors={['0']=0x91bd59}}}}
check(t:accept(event),'exact trusted tint accepted')
local group={texture='minecraft:block/oak_leaves',alpha_mode='cutout',tint=0}
local applied=assert(t:apply(group,{x=1,y=64,z=2,id='minecraft:oak_leaves'}))
check(applied.tint_rgb==0x91bd59 and group.tint_rgb==nil,'actual RGB copied, frozen group untouched')
local none,why=t:apply(group,{x=2,y=64,z=2,id='minecraft:oak_leaves'})
check(not none and why=='actual_block_tint_pending','no biome/index0 color guess')
local baked={tint=0,texture_meta={baked_diffuse_tint=true}}
check(t:apply(baked,{})==baked,'banner/text baked tint bypass')
local foreign={};for k,v in pairs(event)do foreign[k]=v end;foreign.mc_uuid='other'
check(not t:accept(foreign),'foreign bound player refused')
local nextscope={mc_uuid='bound',world_session='w',dim=scope.dim,view=2};t:bind(nextscope)
check(not t:apply(group,{x=1,y=64,z=2,id='minecraft:oak_leaves'}),'newview invalidates tint')
local function obj(v)v=v or{};function v:IsValid()return true end;function v:GetAddress()return 1 end;return v end
local parent=obj({MaterialDomain=0});function parent:GetBlendMode()return 2 end;function parent:GetBaseMaterial()return self end
local texture=obj();local created,imported=0,0
local options={json={},asset_root='D:/bridge/models/',name=function(n)return n end,
 proof={parent_asset=Widget.parent_asset,static_uv0_alpha_clear=true,intermediate_alpha=false,overlap_sorting=false,capture_evidence='actual-private3sample'},
 load_asset=function()return parent end,
 create_material=function()
  created=created+1
  local m=obj({params={}})
  function m:K2_GetTextureParameterValue()return texture end
  function m:SetTextureParameterValue(k,v)self.params[k]=v end
  return m
 end,
 import_texture=function(ctx,p)imported=imported+1;return obj({path=p})end,
 tint_texture=function(original,rgb)return original..'.'..string.format('%06x',rgb)..'.png'end}
local w=Widget.new(options);local ctx=obj()
local water={texture='minecraft:block/water_still',alpha_mode='translucent',tint=0,tint_role='water',fluid_visual=true,tint_rgb=0x3f76e4}
local value=assert(w:resolve(ctx,water))
check(value.material.params.SlateUI==value.texture,'actual SlateUI consumer binds')
check(value.path:find('3f76e4'),'actual water color consumed')
check(value.shader_visible and not value.translucent_depth_verified,'static sample proof never becomes sorting proof')
water.texture_path='D:/frame/0010.png'
local update=assert(w:resolve(ctx,water))
check(update==value and created==1,'same existingMID family updated for frame')
check(imported==2,'only changed texture imported')
water.tint_rgb=nil
check(not w:resolve(ctx,water),'water raw white is not accepted as biome tint')
parent.GetBlendMode=function()return 0 end
check(not w:resolve(ctx,{texture='minecraft:block/glass',alpha_mode='translucent',tint=-1}),'no dynamic blend override')
print(string.format('{"status":"passed","checks":%d,"engine_calls":0,"mode":"night_low_power_light_contract"}',count))
