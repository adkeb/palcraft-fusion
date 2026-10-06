-- One bounded game-thread metadata inspection. The runtime owner executes this
-- only inside a granted RPC window. No Actor/mesh/texture overrides or console.
assert(IsInGameThread and IsInGameThread(),'Additive metadata requires the existing game-thread RPC')
local companion=assert(_G.PalCraftCollisionCompanion,'Existing companion context required')
local ctx=assert(companion.context());assert(ctx:IsValid(),'Existing world context unavailable')
local candidates={
 '/Game/Others/ProjectilesVol2/Materials/M_Additive.M_Additive',
 '/Game/Pal/Material/Effect/M_GlowColor.M_GlowColor',
 '/Game/Pal/Effect/Material/M_VFX_Dome_01_TF.M_VFX_Dome_01_TF',
 '/Game/Pal/Material/UI/Ingame/MI_UI_AuraEffect_Add.MI_UI_AuraEffect_Add',
 '/Paper2D/DefaultSpriteMaterial.DefaultSpriteMaterial',
 '/Engine/EngineMaterials/EmissiveMeshMaterial.EmissiveMeshMaterial'
}
local parameter_candidates={'Texture','Base Texture','BaseTexture','SpriteTexture','ParticleTexture','Particle Texture',
 'Emissive Texture','EmissiveTexture','MainTex','Diffuse','DiffuseTexture','TextureParam'}
local function valid(o)return o and o.IsValid and o:IsValid()end
local report={version=1,read_only_gameplay=true,actors_created=0,texture_overrides=0,blend_writes=0,
 metadata_only=true,shader_accepted=false,observed_unix=os.time(),parents={}}
local keep={};_G.PalCraftAdditiveMetadataMIDs=keep
local create=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary')
for i,path in ipairs(candidates)do
 local row={asset=path,texture_parameters={},scalar_defaults={},vector_defaults={},candidate_only=true};report.parents[#report.parents+1]=row
 local ok,why=pcall(function()
  local parent=StaticFindObject(path);if not valid(parent)then parent=LoadAsset(path)end
  if not valid(parent)then row.reason='asset_unavailable';return end
  row.loaded=true;row.blend=tonumber(parent:GetBlendMode());local base=parent:GetBaseMaterial()
  if not valid(base)then row.reason='base_unavailable';return end
  row.base=base:GetFullName();row.domain=tonumber(base.MaterialDomain)
  for _,name in ipairs({'ShadingModel','bDisableDepthTest','bUsedWithParticleSprites','bUsedWithNiagaraSprites'})do
   local got,value=pcall(function()return base[name]end);if got and(type(value)=='boolean'or type(value)=='number')then row[name]=value end
  end
  if row.domain~=0 then row.reason='not_surface';return end
  local names={};for _,name in ipairs(parameter_candidates)do names[name]='candidate_getter' end
  -- Use only the real declared MIC overrides; guessed names stay explicitly
  -- labelled until an inherited pre-override MID getter actually succeeds.
  local current=parent
  for _=1,4 do
   if not valid(current)then break end
   pcall(function()
    local a=current.TextureParameterValues
    for j=1,math.min(32,a:GetArrayNum())do local value=a[j];names[value.ParameterInfo.Name:ToString()]='declared_override' end
   end)
   pcall(function()
    local a=current.ScalarParameterValues
    for j=1,math.min(32,a:GetArrayNum())do local v=a[j];row.scalar_defaults[v.ParameterInfo.Name:ToString()]=v.ParameterValue end
   end)
   pcall(function()
    local a=current.VectorParameterValues
    for j=1,math.min(32,a:GetArrayNum())do local v=a[j];local c=v.ParameterValue;row.vector_defaults[v.ParameterInfo.Name:ToString()]={c.R,c.G,c.B,c.A}end
   end)
   local got,p=pcall(function()return current.Parent end);current=got and p or nil
  end
  local mid=create:CreateDynamicMaterialInstance(ctx,parent,FName('MC_AdditiveMetadata_'..i..'_'..report.observed_unix),0)
  if not valid(mid)then row.reason='inspection_mid_unavailable';return end
  keep[#keep+1]=mid;row.mid_blend=tonumber(mid:GetBlendMode())
  local sorted={};for name in pairs(names)do sorted[#sorted+1]=name end;table.sort(sorted)
  for _,name in ipairs(sorted)do
   local got,texture=pcall(function()return mid:K2_GetTextureParameterValue(FName(name))end)
   if got and valid(texture)then row.texture_parameters[name]={inherited=true,texture=texture:GetFullName(),discovered_by=names[name]}end
  end
  row.additive_surface=row.blend==3 and row.domain==0 and row.mid_blend==3
  row.reason=row.additive_surface and'additive_parent_parameter_metadata_only'or'not_additive'
 end)
 if not ok then row.reason='inspection_error';row.error=tostring(why)end
end
return report
