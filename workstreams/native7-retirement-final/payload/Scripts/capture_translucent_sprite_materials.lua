-- Independent exact Paper2D translucent candidate. Parent/parameter metadata is
-- not copied into visual acceptance; light/overlay stay explicit native inputs.
local M={version=1,parent_asset='/Paper2D/TranslucentUnlitSpriteMaterial.TranslucentUnlitSpriteMaterial',parameter='SpriteTexture'}
local function valid(o)return o and o.IsValid and o:IsValid()end
function M.new(o)
 local root=assert(o.asset_root):gsub('[\\/]+$','')..'/'
 local load=o.load_asset or LoadAsset;local name=o.name or FName
 local create=o.create_material or function(ctx,parent,label)
  return StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(ctx,parent,name(label),0)
 end
 local import=o.import_texture or function(ctx,path)
  return StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(ctx,path)
 end
 local self={materials={},textures={}}
 function self:resolve(ctx,g)
  if IsInGameThread then assert(IsInGameThread(),'Captured translucent material requires game thread')end
  local b=g.capture_blend
  if not valid(ctx)or g.actual_renderer_capture~=true or type(b)~='table'or b.source~='actual_render_pipeline'or b.mode~='translucent'then
   return nil,'not_original_translucent_capture'
  end
  local path=g.texture_path;local file=type(path)=='string'and path:sub(#root+1)
  if not file or path:sub(1,#root)~=root or #file~=68 or file:sub(-4)~='.png'or file:sub(1,64):find('[^0-9a-f]')then return nil,'capture_sprite_png_outside_cache'end
  local contract=o.shader_contract
  if not contract or not contract.evidence or contract.original_uv0~=true or contract.vertex_rgba~=true
   or contract.original_alpha~=true or contract.blend_equation~=b.equation
   or contract.light_mode~=b.light_mode or contract.overlay_mode~=b.overlay_mode then
   return nil,'capture_sprite_translucent_shader_contract_required'
  end
  local parent=load(M.parent_asset)
  if not valid(parent)or tonumber(parent:GetBlendMode())~=2 then return nil,'paper_parent_not_translucent'end
  local base=parent:GetBaseMaterial()
  if not valid(base)or tonumber(base.MaterialDomain)~=0 or tonumber(base.ShadingModel)~=0 then return nil,'paper_parent_not_unlit_surface'end
  local key=tostring(ctx:GetAddress())..':'..path..':'..b.equation
  local value=self.materials[key];if value and valid(value.material)and valid(value.texture)then return value end
  _G.PalCraftCaptureSpriteSerial=(_G.PalCraftCaptureSpriteSerial or 0)+1
  local mid=create(ctx,parent,'MC_CaptureSprite_'.._G.PalCraftCaptureSpriteSerial)
  if not valid(mid)or tonumber(mid:GetBlendMode())~=2 then return nil,'paper_translucent_mid_unavailable'end
  local inherited=mid:K2_GetTextureParameterValue(name(M.parameter))
  if not valid(inherited)then return nil,'paper_inherited_sprite_sampler_missing'end
  local texture=self.textures[path]
  if not valid(texture)then texture=import(ctx,path);if not valid(texture)then return nil,'paper_capture_texture_import_failed'end;texture.Filter=0;self.textures[path]=texture end
  mid:SetTextureParameterValue(name(M.parameter),texture)
  value={material=mid,texture=texture,path=path,group=g,vertex_rgba=g.vertex_colors,mc_light=g.mc_light,mc_overlay=g.mc_overlay,
   shader_verified=contract.actual_game_image==true,verification={blend2=true,surface0=true,unlit=true,inherited_sprite_texture=true,original_png=true,contract_evidence=contract.evidence}}
  self.materials[key]=value;return value
 end
 function self:reset()self.materials={};self.textures={}end
 return self
end
return M
