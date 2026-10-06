local dir=assert(arg[1]);local Route=dofile(dir..'/capture_blend_route.lua');local Profile=dofile(dir..'/capture_additive_materials.lua')
local n=0;local function check(v,why)assert(v,why);n=n+1 end
local group={texture='minecraft:eyes',vertex_colors={{.2,.4,.6,.8}},mc_light=15728880,mc_overlay=655360}
local base={v=1,source='actual_render_pipeline',mode='translucent',coverage={alpha_cutout='none'},light_mode='emissive_no_lightmap',overlay_mode='none'}
check(Route.apply(group,{render_type_name='eyes',capture_blend=base})and group.alpha_mode=='translucent'and not group.additive_material_required,'actual26.3 eyes stays translucent')
check(group.vertex_colors[1][4]==.8 and group.mc_light==15728880 and group.mc_overlay==655360,'no RGBA/light/overlay transformation')
local additive={};for k,v in pairs(base)do additive[k]=v end;additive.mode='additive';additive.equation='color=ADD(SRC_ALPHA,ONE);alpha=ADD(ZERO,ONE)'
check(Route.apply(group,{render_type_name='arbitrary-name',capture_blend=additive})and group.alpha_mode=='additive'and group.additive_material_required,'actual equation routes real additive independently of name')
check(not Route.apply({},{render_type_name='eyes',has_blending=true}),'unknown legacy hasBlending does not guess additive')
local complex={};for k,v in pairs(base)do complex[k]=v end;complex.mode='oit_or_multiple_targets'
check(not Route.apply({},{capture_blend=complex}),'OIT/multiple target contract stays explicit pending')
local masked={};for k,v in pairs(base)do masked[k]=v end;masked.mode='opaque';masked.coverage={alpha_cutout='0.1'}
local m={};check(Route.apply(m,{capture_blend=masked})and m.alpha_mode=='cutout','coverage derives actual texture alpha cutout')
local function obj(t)t=t or{};function t:IsValid()return true end;function t:GetAddress()return 200 end;return t end
local parent=obj({MaterialDomain=0});function parent:GetBlendMode()return self.blend or 3 end;function parent:GetBaseMaterial()return self end
local inherited=obj();local imports=0;local bound=0;local ctx=obj()
local descriptor={parent_asset='fixture:qualified-additive',texture_parameter='ActualSampler',asset_metadata_evidence='fixture-only',
 shader_contract={evidence='fixture-only',original_uv0=true,vertex_rgba=true,no_wpo_or_uv_animation=true,
  blend_equation=additive.equation,light_mode='emissive_no_lightmap',overlay_mode='none',actual_game_image=false}}
local opts={asset_root='D:/bridge/entity-capture-v1/textures/',descriptor=descriptor,name=function(s)return s end,
 load_asset=function()return parent end,create_material=function()
  local mid=obj();function mid:GetBlendMode()return 3 end;function mid:K2_GetTextureParameterValue()return inherited end
  function mid:SetTextureParameterValue(k,v)check(k=='ActualSampler'and v:IsValid(),'actual inherited sampler bound');bound=bound+1 end;return mid
 end,import_texture=function(_,path)imports=imports+1;return obj()end}
local p=Profile.new(opts);group.actual_renderer_capture=true;group.texture_path=opts.asset_root..string.rep('a',64)..'.png';group.capture_blend=additive
local value=assert(p:resolve(ctx,group));check(value.path==group.texture_path and not value.shader_verified and value.vertex_rgba==group.vertex_colors,'binds exact original PNG and retains raw semantics without shader image claim')
check(p:resolve(ctx,group)==value and imports==1 and bound==1,'same actual original texture/material cache reused')
parent.blend=2;check(not Profile.new(opts):resolve(ctx,group),'ordinary translucent is never additive substitute');parent.blend=3
parent.MaterialDomain=5;check(not Profile.new(opts):resolve(ctx,group),'UI additive is not a Surface material');parent.MaterialDomain=0
opts.descriptor=nil;check(not Profile.new(opts):resolve(ctx,group),'missing real parent/sampler descriptor stays pending')
print(string.format('{"status":"passed","checks":%d,"mode":"only_new_layer_route","engine_calls":0,"descriptor_is_fixture":true}',n))
