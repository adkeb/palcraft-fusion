-- Real Additive-only provider for the existing captured native mesh pipeline.
-- The runtime descriptor comes from an inspected/cooked parent, never its name.
-- Original PNG, vertex RGBA, mc_light and mc_overlay are not rebaked/replaced.
local M={version=1,expected_blend=3}
local function valid(o)return o and o.IsValid and o:IsValid()end
local function root(path)return path:gsub('\\','/'):gsub('/+$','')..'/'end
local function capture_path(base,path)
 if type(path)~='string'or path:sub(1,#base)~=base then return false end
 local name=path:sub(#base+1)
 return #name==68 and name:sub(-4)=='.png'and not name:sub(1,64):find('[^0-9a-f]')
end
function M.new(options)
 local base=root(assert(options.asset_root));local load=options.load_asset or LoadAsset;local name=options.name or FName
 local create=options.create_material or function(ctx,parent,label)
  return StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(ctx,parent,name(label),0)
 end
 local import=options.import_texture or function(ctx,path)
  return StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(ctx,path)
 end
 local self={materials={},textures={},stats={created=0,imports=0,rejected=0},descriptor=options.descriptor}
 function self:resolve(ctx,group)
  if IsInGameThread then assert(IsInGameThread(),'Additive material binding requires the existing game thread')end
  assert(valid(ctx),'Existing material context required')
  if group.actual_renderer_capture~=true or group.additive_material_required~=true then return nil,'not_actual_additive_capture'end
  -- An eyes name/hasBlending flag is not an actual blend equation (MC26.3 eyes
  -- uses TRANSLUCENT). Unknown equations keep their existing explicit pending.
  local blend=group.capture_blend
  if type(blend)~='table'or blend.mode~='additive'or blend.source~='actual_render_pipeline'then
   return nil,'actual_additive_blend_metadata_required'
  end
  if not capture_path(base,group.texture_path)then return nil,'capture_additive_png_outside_cache'end
  if group.tint_rgb~=nil or(group.tint or-1)>=0 or(group.texture_meta and group.texture_meta.animation)then
   return nil,'capture_additive_original_pixels_required'
  end
  local d=self.descriptor
  if not d or not d.parent_asset or not d.texture_parameter or not d.asset_metadata_evidence then
   return nil,'capture_additive_parent_metadata_required'
  end
  local contract=d.shader_contract
  if not contract or not contract.evidence or contract.original_uv0~=true or contract.vertex_rgba~=true
   or contract.no_wpo_or_uv_animation~=true or contract.blend_equation~=blend.equation
   or contract.light_mode~=blend.light_mode or contract.overlay_mode~=blend.overlay_mode then
   return nil,'capture_additive_shader_contract_required'
  end
  local parent=load(d.parent_asset)
  if not valid(parent)or tonumber(parent:GetBlendMode())~=3 then return nil,'capture_parent_not_additive'end
  local material_base=parent:GetBaseMaterial()
  if not valid(material_base)or tonumber(material_base.MaterialDomain)~=0 then return nil,'capture_additive_parent_not_surface'end
  local key=tostring(ctx:GetAddress())..':'..d.parent_asset..':'..group.texture_path..':'..blend.equation
  local value=self.materials[key]
  if value and valid(value.material)and valid(value.texture)then return value end
  _G.PalCraftCaptureAdditiveSerial=(_G.PalCraftCaptureAdditiveSerial or 0)+1
  local mid=create(ctx,parent,'MC_CaptureAdditive_'.._G.PalCraftCaptureAdditiveSerial)
  if not valid(mid)or tonumber(mid:GetBlendMode())~=3 then return nil,'capture_additive_mid_unavailable'end
  local inherited=mid:K2_GetTextureParameterValue(name(d.texture_parameter))
  if not valid(inherited)then return nil,'capture_additive_inherited_sampler_missing'end
  local texture_key=tostring(ctx:GetAddress())..':'..group.texture_path
  local texture=self.textures[texture_key]
  if not valid(texture)then texture=import(ctx,group.texture_path)
   if not valid(texture)then return nil,'capture_additive_png_import_failed'end
   texture.Filter=0;self.textures[texture_key]=texture;self.stats.imports=self.stats.imports+1
  end
  mid:SetTextureParameterValue(name(d.texture_parameter),texture)
  value={material=mid,texture=texture,path=group.texture_path,group=group,
   vertex_rgba=group.vertex_colors,mc_light=group.mc_light,mc_overlay=group.mc_overlay,
   verification={actual_additive_blend3=true,surface0=true,inherited_sampler=true,
    original_png_preserved=true,shader_contract_evidence=contract.evidence,actual_game_image=contract.actual_game_image==true},
   shader_verified=contract.actual_game_image==true}
  self.materials[key]=value;self.stats.created=self.stats.created+1;return value
 end
 function self:reset()self.materials={};self.textures={}end
 function self:status()return{version=1,parent_descriptor_present=self.descriptor~=nil,stats=self.stats,
  full_additive_accepted=self.descriptor and self.descriptor.shader_contract and self.descriptor.shader_contract.actual_game_image==true or false}end
 return self
end
return M
