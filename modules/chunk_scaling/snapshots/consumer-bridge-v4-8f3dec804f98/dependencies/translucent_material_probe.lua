-- Separate from frozen material_profiles-v1. Read/probe only when the lead owns
-- the engine lease. No callbacks, BlendMode overrides, or capability promotion.
local M={version=1,candidates={
 {id='widget_surface_translucent',parent_asset='/Engine/EngineMaterials/Widget3DPassThrough_Translucent.Widget3DPassThrough_Translucent',
  texture_candidates={'SlateUI'},vector_candidates={'TintColorAndOpacity','BackColor'},scalar_candidates={'OpacityFromTexture'},
  source='Actual MaterialInstanceConstant in local ObjectDump; parameter names are candidates until default/liveWidget or sampling proof.'},
 {id='pal_helicopter_glass',parent_asset='/Game/Pal/Model/Other/AttackHelicopter/Material/M_PalProp_AttackHelicopterGlass.M_PalProp_AttackHelicopterGlass',
  texture_candidates={'Base Texture'},vector_candidates={},scalar_candidates={},
  source='Actual Material in local ObjectDump; sampled texture/opacity/refraction remain unknown.'},
 {id='river_transparent',parent_asset='/Game/Others/UltimateRiverTool/Materials/Generic/M_Transparent.M_Transparent',
  texture_candidates={'Base Texture'},vector_candidates={},scalar_candidates={},
  source='Actual Material in local ObjectDump; default parameter and sampling remain unknown.'}
}}
local function valid(o)return o and o.IsValid and o:IsValid()end
local function address(o)return valid(o)and o:GetAddress()or nil end
function M.probe(ctx,id,api)
 if IsInGameThread then assert(IsInGameThread(),'Material probe requires game thread')end
 api=api or{}
 local chosen;for _,c in ipairs(M.candidates)do if c.id==id then chosen=c end end
 assert(chosen and valid(ctx),'Valid context/candidate required')
 local load=api.load_asset or LoadAsset
 local name=api.name or FName
 local parent=load(chosen.parent_asset)
 local report={candidate=id,parent_asset=chosen.parent_asset,shader_visible=false,capability_translucent=false,
  texture_parameters={},vector_parameters={},scalar_parameters={},writes=0}
 if not valid(parent)then report.reason='parent_unavailable';return report end
 local base=parent:GetBaseMaterial()
 report.blend=tonumber(parent:GetBlendMode());report.domain=valid(base)and tonumber(base.MaterialDomain)or nil
 report.parent=parent;report.base=base
 if report.blend~=2 or report.domain~=0 then report.reason='not_translucent_surface';return report end
 _G.PalCraftTranslucentProbeSerial=(_G.PalCraftTranslucentProbeSerial or 0)+1
 local mid
 if api.create_material then mid=api.create_material(ctx,parent,'MC_TranslucentProbe_'.._G.PalCraftTranslucentProbeSerial)
 else mid=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(
  ctx,parent,name('MC_TranslucentProbe_'.._G.PalCraftTranslucentProbeSerial),0)end
 if not valid(mid)then report.reason='mid_unavailable';return report end
 report.material=mid
 for _,key in ipairs(chosen.texture_candidates)do
  local value=mid:K2_GetTextureParameterValue(name(key))
  report.texture_parameters[key]={default_address=address(value),inherited_default=valid(value),
   sampling_verified=false,default_null_requires_live_widget_or_quad_proof=not valid(value)}
 end
 for _,key in ipairs(chosen.vector_candidates)do
  local ok,value=pcall(function()return mid:K2_GetVectorParameterValue(name(key))end)
  report.vector_parameters[key]={read_ok=ok,default=value,defined_in_shader=false}
 end
 for _,key in ipairs(chosen.scalar_candidates)do
  local ok,value=pcall(function()return mid:K2_GetScalarParameterValue(name(key))end)
  report.scalar_parameters[key]={read_ok=ok,default=value,defined_in_shader=false}
 end
 report.reason='sampling_and_depth_order_probe_required'
 return report
end
function M.observe_widget(widget,api)
 -- An existing WidgetComponent MID may supply SlateUI even if the parent's
 -- default texture is null. This records a fact and never changes that widget.
 api=api or{};local name=api.name or FName
 assert(valid(widget),'WidgetComponent required')
 local mid=widget:GetMaterialInstance()
 if not valid(mid)then return{observed=false,reason='no_live_widget_mid'}end
 local texture=mid:K2_GetTextureParameterValue(name('SlateUI'))
 return{observed=true,material_address=address(mid),slateui_address=address(texture),
  texture_present=valid(texture),blend=tonumber(mid:GetBlendMode()),
  shader_sampling_verified=false,widget_modified=false}
end
function M.approved_descriptor(report,proof)
 -- Only native/lead's explicit actual sampling/depth evidence opens this gate.
 assert(report and report.blend==2 and report.domain==0,'Translucent Surface proof required')
 assert(type(proof)=='table'and proof.parent_asset==report.parent_asset and proof.texture_parameter and
  proof.uv0_sampled==true and proof.alpha_sampled==true and proof.depth_order_verified==true and proof.capture_evidence,
  'Actual native alpha/UV/depth capture required')
 return{parent_asset=report.parent_asset,expected_blend=2,texture_parameter=proof.texture_parameter,
  alpha_mode='translucent',shader_visible=true,probe_evidence=proof.capture_evidence}
end
return M
