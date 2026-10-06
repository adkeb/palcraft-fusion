-- A separate display-only material owner for text. Parent names below are
-- candidates: a runtime probe must prove the actual Pal shader has no WPO and
-- samples SpriteTexture. Status never promotes them to engine-verified itself.
local M={version=1};local Instance={};Instance.__index=Instance
local function valid(v)return v and v.IsValid and v:IsValid()end
local candidates={
 cutout={id='sign_masked_unlit',parent='/Paper2D/MaskedUnlitSpriteMaterial.MaskedUnlitSpriteMaterial',parameter='SpriteTexture',blend=1},
 translucent={id='sign_translucent_unlit',parent='/Paper2D/TranslucentUnlitSpriteMaterial.TranslucentUnlitSpriteMaterial',parameter='SpriteTexture',blend=2}
}
M.candidates=candidates
function M.new(o)
 o=assert(o);assert(type(o.root)=='string','Private sign texture root required')
 return setmetatable({o=o,root=o.root:gsub('[\\/]+$','')..'/',parents={},instances={},textures={},serial=0,clock=0,
  stats={materials=0,imports=0,changes=0,releases=0}},Instance)
end
function Instance:_thread()if IsInGameThread then assert(IsInGameThread(),'Text materials require game thread')end end
function Instance:_profile(ctx,mode)
 local spec=(self.o.profiles or candidates)[mode];if not spec then return nil,'text_parent_missing'end
 local proof=self.o.verified_profiles and self.o.verified_profiles[mode]
 if not self.o.allow_candidate and not(proof and proof.shader_visible==true and proof.unlit==true and proof.no_wpo==true)then
  return nil,'text_parent_requires_native_scene_probe'
 end
 local cached=self.parents[spec.id];if cached and valid(cached.parent)then return cached end
 local parent=(self.o.load_asset or LoadAsset)(spec.parent)
 if not valid(parent)or tonumber(parent:GetBlendMode())~=spec.blend then return nil,'text_parent_blend_unavailable'end
 local base=parent:GetBaseMaterial()
 if not valid(base)or tonumber(base.MaterialDomain)~=0 then return nil,'text_parent_surface_unavailable'end
 local create=self.o.create_material or function(c,p,n)return StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(c,p,(self.o.name or FName)(n),0)end
 self.serial=self.serial+1;local probe=create(ctx,parent,'MC_SignParent_'..self.serial)
 local name=self.o.name or FName
 if not valid(probe)or not valid(probe:K2_GetTextureParameterValue(name(spec.parameter)))then return nil,'text_parent_texture_parameter_unavailable'end
 cached={spec=spec,parent=parent,proof=proof,create=create};self.parents[spec.id]=cached;return cached
end
function Instance:_texture(ctx,g)
 local image=g.image;local context=tostring(ctx:GetAddress());local key=context..':'..image.sha256
 self.clock=self.clock+1
 local cached=self.textures[key];if cached and valid(cached.texture)then cached.last=self.clock;return cached end
 assert(image.path=='textures/'..image.sha256..'.png','Unsafe text image path')
 local path=self.root..image.path
 if self.o.verify_image then assert(self.o.verify_image(path,image),'Text PNG hash/size rejected')end
 local importer=self.o.import_texture or function(c,p)return StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(c,p)end
 local texture=importer(ctx,path);if not valid(texture)then return nil,'text_png_import_failed'end
 texture.Filter=0
 cached={texture=texture,path=path,refs=0,last=self.clock,key=key};self.textures[key]=cached;self.stats.imports=self.stats.imports+1
 return cached
end
function Instance:prepare_groups(ctx,groups)
 self:_thread();assert(valid(ctx),'Text world context unavailable')
 local prepared={}
 for i,g in ipairs(groups)do
  assert(g.text_plane==true and g.sign_key and(g.side=='front'or g.side=='back'),'Text plane material contract required')
  local p,why=self:_profile(ctx,g.alpha_mode or'cutout');if not p then error(why)end
  local texture;texture,why=self:_texture(ctx,g);if not texture then error(why)end
  local key=tostring(ctx:GetAddress())..':'..g.sign_key..':'..g.side
  local old=self.instances[key];local material=old and old.profile_id==p.spec.id and old.material
  if not valid(material)then
   self.serial=self.serial+1;material=p.create(ctx,p.parent,'MC_Sign_'..self.serial)
   assert(valid(material),'Text MID creation failed');self.stats.materials=self.stats.materials+1
  end
  prepared[i]={key=key,material=material,texture=texture,parameter=p.spec.parameter,profile_id=p.spec.id,group=g,previous=old}
 end
 return prepared
end
function Instance:commit_groups(prepared,set_material)
 self:_thread();local name=self.o.name or FName
 -- Both imported images and all candidate MIDs exist before changing either side.
 for _,v in ipairs(prepared)do assert(valid(v.material)and valid(v.texture.texture),'Text material preflight failed')end
 for i,v in ipairs(prepared)do
  local old=v.previous
  if not old or old.texture~=v.texture or old.material~=v.material then
   v.material:SetTextureParameterValue(name(v.parameter),v.texture.texture)
   if set_material and(not old or old.material~=v.material)then set_material(i-1,v.material)end
   v.texture.refs=v.texture.refs+1
   if old then old.texture.refs=old.texture.refs-1 end
   self.stats.changes=self.stats.changes+1
  end
  v.previous=nil -- do not retain every earlier MID/texture through an update chain
  self.instances[v.key]=v
 end
 self:_trim();return prepared
end
function Instance:resolve(ctx,g)
 local key=tostring(ctx:GetAddress())..':'..g.sign_key..':'..g.side
 local existing=self.instances[key]
 if existing and valid(existing.material)and existing.group.image.sha256==g.image.sha256 then return existing end
 local staged=self:prepare_groups(ctx,{g});self:commit_groups(staged);return staged[1]
end
function Instance:_trim()
 local unused={};for key,t in pairs(self.textures)do if t.refs<=0 then unused[#unused+1]={key=key,last=t.last}end end
 table.sort(unused,function(a,b)return a.last<b.last end)
 for i=1,#unused-(self.o.unused_texture_cache or 32)do self.textures[unused[i].key]=nil end
end
function Instance:release(sign_key,context)
 self:_thread();local prefix=tostring(context)..':'..sign_key..':'
 for key,v in pairs(self.instances)do if key:sub(1,#prefix)==prefix then
  v.texture.refs=v.texture.refs-1;self.instances[key]=nil;self.stats.releases=self.stats.releases+1
 end end
 self:_trim()
end
function Instance:reset()self:_thread();self.parents={};self.instances={};self.textures={}end
function Instance:status()
 local count,texture_count=0,0;for _ in pairs(self.instances)do count=count+1 end;for _ in pairs(self.textures)do texture_count=texture_count+1 end
 return{version=1,instances=count,textures=texture_count,stats=self.stats,runtime_verified=false,
  alpha='straight',light='vanilla_lightmap_baked',parent_scene_verification_required=true}
end
return M
