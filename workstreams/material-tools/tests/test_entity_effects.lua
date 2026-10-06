local dir=assert(arg[1])
local Effects=dofile(dir..'/client/entity_material_effects.lua')
local Probe=dofile(dir..'/client/translucent_material_probe.lua')
local checks=0
local function check(v,why)assert(v,why);checks=checks+1 end
local alpha={255,242,229,216,203,191,178,165,152,140,127,114,101,89,76,63}
for u=0,15 do
 local sample=Effects.overlay({white_overlay=u/15})
 check(sample.u==u and sample.v==10 and sample.base_weight_byte==alpha[u+1],'JVM float LUT')
 local red=Effects.overlay({red_overlay=true,white_overlay=u/15})
 check(red.v==3 and red.base_weight_byte==178 and red.key=='red','red row dominates white')
end
check(Effects.creeper_progress(.2)==0,'even swelling phase')
check(Effects.creeper_progress(.55)>0,'odd swelling phase')
local descriptor=Effects.descriptor({entity_visual=true,alpha_mode='cutout',tint=-1,texture='minecraft:entity/pig',
 render_effects={red_overlay=true,scale_xz=3,scale_y=2,death_roll=1}}, {skins={['minecraft:entity/pig']={variants={red='pig/red.png'}}}}, 'D:/bridge/entity-overlays-v1/')
check(descriptor.texture_path=='D:/bridge/entity-overlays-v1/pig/red.png','runtime relative root')
check(descriptor.geometry_effects_already_applied and not descriptor.changes_hp and not descriptor.changes_world_position,'do not double transform or change authority')
local function obj(t)
 t=t or{};function t:IsValid()return true end;function t:GetAddress()return 42 end;return t
end
local parent=obj({blend=2,base=obj({MaterialDomain=0})})
function parent:GetBlendMode()return self.blend end
function parent:GetBaseMaterial()return self.base end
local mid=obj()
function mid:K2_GetTextureParameterValue(n)return nil end
function mid:K2_GetVectorParameterValue(n)return{R=0,G=0,B=0,A=0}end
function mid:K2_GetScalarParameterValue(n)return 0 end
local ctx=obj()
local report=Probe.probe(ctx,'widget_surface_translucent',{load_asset=function()return parent end,name=function(n)return n end,create_material=function()return mid end})
check(report.blend==2 and report.domain==0 and not report.capability_translucent and report.writes==0,'probe reads, never promotes capability')
check(report.texture_parameters.SlateUI.default_null_requires_live_widget_or_quad_proof,'null default not accepted as sampling')
local ok=pcall(Probe.approved_descriptor,report,{})
check(not ok,'asset name/set-get cannot claim true shader')
local proof={parent_asset=report.parent_asset,texture_parameter='SlateUI',uv0_sampled=true,alpha_sampled=true,depth_order_verified=true,capture_evidence='owner-qualified-test-only'}
check(Probe.approved_descriptor(report,proof).alpha_mode=='translucent','actual capture contract gate')
parent.blend=0
local opaque=Probe.probe(ctx,'widget_surface_translucent',{load_asset=function()return parent end,name=function(n)return n end})
check(opaque.reason=='not_translucent_surface','no BlendMode rewriting')
print(string.format('{"status":"passed","checks":%d,"engine_calls":0,"mode":"night_low_power_light_contract"}',checks))
