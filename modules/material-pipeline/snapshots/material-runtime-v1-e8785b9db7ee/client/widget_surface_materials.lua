-- Actual Widget3DPassThrough consumer, separate from frozen material-v1.
-- Static UV/alpha-clear was seen in the leased3sample capture; overlap/correct
-- intermediate alpha still requires its own evidence. No runtime BlendMode writes.
local M={version=1,parent_asset='/Engine/EngineMaterials/Widget3DPassThrough_Translucent.Widget3DPassThrough_Translucent',texture_parameter='SlateUI'}
local function valid(o)return o and o.IsValid and o:IsValid()end
local function norm(p)return p:gsub('[\\/]+$','')..'/'end
function M.new(options)
 assert(options and options.asset_root and options.json,'Material root/json required')
 local self={options=options,root=norm(options.asset_root),materials={},textures={},serial=0,updates=0}
 local load=options.load_asset or LoadAsset
 local name=options.name or FName
 local import=options.import_texture or function(ctx,path)
  return StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(ctx,path)
 end
 local create=options.create_material or function(ctx,parent,n)
  return StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(ctx,parent,name(n),0)
 end
 function self:resolve(ctx,group)
  if IsInGameThread then assert(IsInGameThread(),'Widget material resolution requires game thread')end
  assert(valid(ctx),'Material context required')
  if group.alpha_mode~='translucent'then return nil,'not_translucent_group'end
  if group.fluid_visual and group.tint_role~='water'then return nil,'fluid_semantics_do_not_match_water'end
  if(group.tint or-1)>=0 and not(group.texture_meta and group.texture_meta.baked_diffuse_tint==true)and group.tint_rgb==nil then
   return nil,'actual_biome_color_required'
  end
  local proof=options.proof
  if not options.probe_mode and(not proof or proof.parent_asset~=M.parent_asset or proof.static_uv0_alpha_clear~=true or not proof.capture_evidence)then
   return nil,'widget_static_sampling_proof_required'
  end
  local parent=load(M.parent_asset)
  if not valid(parent)or tonumber(parent:GetBlendMode())~=2 then return nil,'parent_not_translucent'end
  local base=parent:GetBaseMaterial()
  if not valid(base)or tonumber(base.MaterialDomain)~=0 then return nil,'parent_not_surface'end
  local original=group.texture_path or self.root..'textures/'..assert(group.texture):gsub(':','/')..'.png'
  local path=original
  if group.tint_rgb~=nil and not(group.texture_meta and group.texture_meta.baked_diffuse_tint==true)then
   if not options.tint_texture then return nil,'actual_tint_bake_consumer_required'end
   path=options.tint_texture(original,group.tint_rgb,group);if not path then return nil,'tint_texture_unavailable'end
  end
  local ctxid=tostring(ctx:GetAddress())
  local family=group.material_key or group.texture or original
  local key=ctxid..':'..family..':'..tostring(group.tint_rgb or'baked_or_none')
  local value=self.materials[key]
  if not value or not valid(value.material)then
   _G.PalCraftWidgetMaterialSerial=(_G.PalCraftWidgetMaterialSerial or 0)+1
   local mid=create(ctx,parent,'MC_WidgetSurface_'.._G.PalCraftWidgetMaterialSerial)
   if not valid(mid)then return nil,'mid_unavailable'end
   local inherited=mid:K2_GetTextureParameterValue(name(M.texture_parameter))
   if not valid(inherited)then return nil,'slateui_inherited_parameter_missing'end
   value={material=mid,parent=parent,verification={blend2=true,surface0=true,inherited_slateui=true,
    static_uv0_alpha_clear=proof and proof.static_uv0_alpha_clear==true or false,
    intermediate_alpha=proof and proof.intermediate_alpha==true or false,
    overlap_sorting=proof and proof.overlap_sorting==true or false},group=group}
   self.materials[key]=value
  end
  if value.path~=path or not valid(value.texture)then
   local tk=ctxid..':'..path
   local texture=self.textures[tk]
   if not valid(texture)then texture=import(ctx,path);if not valid(texture)then return nil,'texture_unavailable'end;texture.Filter=0;self.textures[tk]=texture end
   value.material:SetTextureParameterValue(name(M.texture_parameter),texture)
   value.texture=texture;value.path=path;self.updates=self.updates+1
  end
  value.shader_visible=proof and proof.static_uv0_alpha_clear==true or false
  value.translucent_depth_verified=proof and proof.overlap_sorting==true or false
  value.fluid_physics_changed=false
  return value
 end
 function self:reset()self.materials={};self.textures={}end
 function self:status()return{version=1,parent=M.parent_asset,parameter=M.texture_parameter,updates=self.updates,
  static_sampling=options.proof and options.proof.static_uv0_alpha_clear==true or false,
  full_translucent_capability=false,physics_modified=false}end
 return self
end
return M
