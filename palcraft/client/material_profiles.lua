-- Runtime parent/parameter selection with real precompiled materials. No BlendMode
-- writes. Imported/tinted textures retain straight alpha and original UV0..1.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Timeline=dofile(dir..'texture_timeline.lua')
local M={version=1}
local function next_serial()
 _G.PalCraftMaterialProfileSerial=(_G.PalCraftMaterialProfileSerial or 0)+1
 return _G.PalCraftMaterialProfileSerial
end
local profiles={
 opaque={id='opaque_prop',parent='/Game/Pal/Material/Prop/MI_PalPropBase.MI_PalPropBase',texture='Base Texture',blend=0,lit=true},
 cutout={id='cutout_foliage',parent='/Game/Pal/Material/Nature/MI_PalLit_Foliage.MI_PalLit_Foliage',texture='Base Texture',blend=1,lit=true},
 cutout_unlit={id='cutout_sprite_unlit',parent='/Paper2D/MaskedUnlitSpriteMaterial.MaskedUnlitSpriteMaterial',texture='SpriteTexture',blend=1,lit=false}
}
M.parents=profiles
local function valid(o)return o and o.IsValid and o:IsValid()end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function relative(p)return type(p)=='string'and #p>0 and #p<=1024 and not p:find('..',1,true)and not p:find('[^%w_./%-]')and p:sub(1,1)~='/'end
local function sprite(g)return g.texture:gsub(':','/')end
local function rgb(value)
 if math.type(value)=='integer'and value>=0 and value<=0xffffff then return value end
 if type(value)=='table'and #value>=3 then
  for i=1,3 do if math.type(value[i])~='integer'or value[i]<0 or value[i]>255 then return nil end end
  return value[1]*65536+value[2]*256+value[3]
 end
end
local function tint_color(g,block)
 local meta=g.texture_meta or{}
 if meta.baked_diffuse_tint==true or(g.tint or-1)<0 then return nil,true end
 local colors=block and block.tint_colors
 local color=rgb(g.tint_rgb or(colors and(colors[tostring(g.tint)]or colors[g.tint])))
 return color,color~=nil
end
function M.descriptor(g,block,options)
 options=options or{}
 if type(g)~='table'or type(g.texture)~='string'or not relative(sprite(g))then return nil,'invalid_texture' end
 local mode=g.alpha_mode or'opaque'
 if mode~='opaque'and mode~='cutout'and mode~='translucent'then return nil,'invalid_alpha_mode'end
 -- Group semantics take precedence over PNG classification (glass, water, skull).
 if mode=='translucent'then return nil,'translucent_parent_not_probed'end
 local profile=mode=='cutout'and(g.shade==false and profiles.cutout_unlit or profiles.cutout)or profiles.opaque
 if mode=='opaque'and g.shade==false then return nil,'unlit_opaque_parent_not_evidenced'end
 local tint,available=tint_color(g,block)
 if not available then return nil,'minecraft_block_color_required'end
 local animation=g.texture_meta and g.texture_meta.animation
 if type(animation)~='table'or type(animation.frames)~='table'then animation=nil end -- JSON null is not an animation.
 if animation and animation.interpolate==true then return nil,'interpolated_texture_requires_bake_or_two_sample_shader'end
 local emission=g.light_emission or 0
 if not finite(emission)or emission<0 or emission>15 then return nil,'invalid_light_emission'end
 local path='textures/'..sprite(g)..'.png'
 if animation then
  local ok,sample=pcall(Timeline.sample,g.texture_meta,options.seconds or 0)
  if not ok or not sample or not relative(sample.path)then return nil,'invalid_texture_timeline'end
  path=sample.path
 end
 return{id=profile.id,parent_asset=profile.parent,texture_parameter=profile.texture,
  expected_blend=profile.blend,lit=profile.lit,alpha_mode=mode,tint_rgb=tint,
  baked_diffuse_tint=g.texture_meta and g.texture_meta.baked_diffuse_tint==true,
  texture_path=path,captured_texture_path=g.actual_renderer_capture==true and g.texture_path or nil,
  animation=animation,emission=emission,requires_game_thread=true,
  shader_verified=false,group=g}
end
local Instance={};Instance.__index=Instance
function M.new(options)
 options=assert(options,'Material profile options required')
 assert(options.json and type(options.asset_root)=='string','json/asset_root required')
 local self=setmetatable({options=options,asset_root=options.asset_root:gsub('[\\/]+$','')..'/',
  bridge_root=(options.bridge_root or dofile(dir..'runtime/paths.lua').bridge):gsub('[\\/]+$','')..'/',
  materials={},textures={},stats={created=0,imports=0,updates=0,bakes=0,rejected=0},parents={}},Instance)
 self.load=options.load_asset or LoadAsset
 self.import=options.import_texture or function(ctx,path)
  return StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(ctx,path)
 end
 self.create=options.create_material or function(ctx,parent,name)
  return StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(ctx,parent,FName(name),0)
 end
 self.name=options.name or FName
 self.now=options.seconds or function(ctx)
  return StaticFindObject('/Script/Engine.Default__GameplayStatics'):GetTimeSeconds(ctx)
 end
 return self
end
function Instance:_game_thread()
 if IsInGameThread then assert(IsInGameThread(),'Material creation/update requires game thread')end
end
function Instance:_parent(ctx,d)
 local old=self.parents[d.id]
 if old and valid(old.material)and valid(old.parent)then return old end
 local parent=self.load(d.parent_asset)
 if not valid(parent)then return nil,'parent_asset_unavailable'end
 local ok,blend=pcall(function()return parent:GetBlendMode()end)
 if not ok or tonumber(blend)~=d.expected_blend then return nil,'parent_blend_mismatch'end
 local base=parent:GetBaseMaterial()
 if not valid(base)or tonumber(base.MaterialDomain)~=0 then return nil,'parent_not_surface'end
 local material=self.create(ctx,parent,'MC_MaterialProbe_v1_'..next_serial())
 if not valid(material)then return nil,'material_creation_failed'end
 -- Inspect inheritance BEFORE writing an override; a setter can otherwise
 -- appear to succeed for a name that the compiled shader never samples.
 local inherited=material:K2_GetTextureParameterValue(self.name(d.texture_parameter))
 if not valid(inherited)then return nil,'parent_texture_parameter_missing'end
 local result={parent=parent,material=material,base=base,blend=blend,
  verification={parent_loaded=true,blend_checked=true,surface_checked=true,texture_parameter_inherited=true,shader_visible=false}}
 self.parents[d.id]=result
 return result
end
function Instance:_bake(relative_png,color)
 local index=self.options.pixel_index
 if not index then return nil,'tint_pixel_package_required'end
 local pixels=index.textures and index.textures[relative_png]
 if not pixels or not relative(pixels.path)then return nil,'tint_pixels_missing'end
 local identity=pixels.sha256 or self.options.pixel_index.source_root
 if type(identity)~='string'or not identity:match('^[%w_%-]+$')then return nil,'tint_pixels_identity_required'end
 local output='material-cache-v1/'..identity:sub(1,32)..'/'..relative_png:gsub('%.png$','')..string.format('_%06x.png',color)
 local existing=io.open(self.bridge_root..output,'rb')
 if existing then existing:close();return self.bridge_root..output end
 local input='material-pixels-v1/'..pixels.path
 local root=self.bridge_root
 if self.options.bake_texture then
  local path,why=self.options.bake_texture(input,output,pixels.width,pixels.height,color)
  if not path then return nil,why or'tint_bake_failed'end
  self.stats.bakes=self.stats.bakes+1;return path
 end
 local native=self.native_bake
 if not native then
  native=package.loadlib(assert(self.options.bake_library,'bake_library required for tinted groups'),'palcraft_bake_material_texture')
  if not native then return nil,'tint_bake_library_unavailable'end
  self.native_bake=native
 end
 -- The utility DLL uses the same PALCRAFT_BRIDGE_DIR as this instance.
 local f=assert(io.open(root..'material-bake-request.pending','wb'))
 f:write(string.pack('<c8I4I4I4I4I4I4','PALCMAT1',pixels.width,pixels.height,color,#input,#output,0),input,output);f:close()
 os.remove(root..'material-bake-request.bin');assert(os.rename(root..'material-bake-request.pending',root..'material-bake-request.bin'))
 os.remove(root..'material-bake-result.json');native()
 f=io.open(root..'material-bake-result.json','rb')
 if not f then return nil,'tint_bake_no_result'end
 local result=self.options.json.decode(f:read('*a'));f:close()
 if not result.ok then return nil,'tint_bake_failed'end
 self.stats.bakes=self.stats.bakes+1
 return root..output
end
function Instance:_texture(ctx,d)
 local path=self.asset_root..d.texture_path
 if d.captured_texture_path then
  -- The authenticated capture cache publishes only content-addressed PNGs.
  local direct=d.captured_texture_path
  local file=type(direct)=='string'and direct:sub(#self.asset_root+1)
  if not file or direct:sub(1,#self.asset_root)~=self.asset_root
   or #file~=68 or file:sub(-4)~='.png'or file:sub(1,64):find('[^0-9a-f]')then return nil,'capture_png_path_outside_cache'end
  if d.tint_rgb or d.animation then return nil,'capture_png_must_preserve_original_pixels'end
  path=direct
 end
 if d.tint_rgb then local why;path,why=self:_bake(d.texture_path,d.tint_rgb);if not path then return nil,why end end
 local key=tostring(ctx:GetAddress())..':'..path
 local old=self.textures[key]
 if valid(old)then return old,path end
 local texture=self.import(ctx,path)
 if not valid(texture)then return nil,'texture_import_failed'end
 texture.Filter=0 -- TF_Nearest, backed by local enum/object dump and existing renderer.
 self.textures[key]=texture;self.stats.imports=self.stats.imports+1
 return texture,path
end
function Instance:resolve(ctx,g,block)
 self:_game_thread()
 if not valid(ctx)then return nil,'context_unavailable'end
 local seconds=self.now(ctx)
 local d,why=M.descriptor(g,block,{seconds=seconds})
 if not d then self.stats.rejected=self.stats.rejected+1;return nil,why end
 local key=tostring(ctx:GetAddress())..':'..g.texture..':'..d.id..':'..tostring(d.tint_rgb or'baked_or_none')..':'..d.emission..':'..tostring(d.captured_texture_path or'')
 local old=self.materials[key]
 if old and valid(old.material)and valid(old.texture)then return old end
 local p;p,why=self:_parent(ctx,d);if not p then return nil,why end
 local texture,path;texture,path=self:_texture(ctx,d);if not texture then return nil,path end
 local material=self.create(ctx,p.parent,'MC_Material_v1_'..next_serial())
 if not valid(material)then return nil,'material_creation_failed'end
 material:SetTextureParameterValue(self.name(d.texture_parameter),texture)
 if d.lit then
  material:SetScalarParameterValue(self.name('Roughness Add'),1)
  material:SetScalarParameterValue(self.name('ChangeColor Rate'),0)
  local normal=self.load('/Engine/EngineMaterials/DefaultNormal.DefaultNormal')
  if valid(normal)and valid(material:K2_GetTextureParameterValue(self.name('Normal Map')))then
   material:SetTextureParameterValue(self.name('Normal Map'),normal)
  end
  if d.emission>0 then
   local inherited=material:K2_GetTextureParameterValue(self.name('Emissive Texture'))
   if not valid(inherited)then return nil,'emissive_texture_parameter_missing'end
   material:SetTextureParameterValue(self.name('Emissive Texture'),texture)
   material:SetScalarParameterValue(self.name('Emissive Texture Intensity'),d.emission/15)
  end
 end
 local value={material=material,texture=texture,path=path,descriptor=d,ctx=ctx,block=block,
  verification=p.verification,shader_verified=false,frame_update=d.animation~=nil}
 self.materials[key]=value;self.stats.created=self.stats.created+1
 return value
end
function Instance:tick(seconds)
 self:_game_thread();assert(finite(seconds)and seconds>=0,'Monotonic/game seconds required')
 for key,value in pairs(self.materials)do
  if not valid(value.ctx)or not valid(value.material)then self.materials[key]=nil
  elseif value.frame_update then
   local d,why=M.descriptor(value.descriptor.group,value.block,{seconds=seconds})
   if not d then return nil,why end
   if d.texture_path~=value.descriptor.texture_path then
    local texture,path=self:_texture(value.ctx,d)
    if not texture then return nil,path end
    value.material:SetTextureParameterValue(self.name(d.texture_parameter),texture)
    if d.lit and d.emission>0 then value.material:SetTextureParameterValue(self.name('Emissive Texture'),texture)end
    value.texture=texture;value.path=path;value.descriptor=d
    self.stats.updates=self.stats.updates+1
   end
  end
 end
 return true
end
function Instance:reset()self.materials={};self.textures={};self.parents={}end
function Instance:status()
 local n=0;for _ in pairs(self.materials)do n=n+1 end
 return{version=1,materials=n,stats=self.stats,shader_visible_verified=false,
  supported_paths={'opaque','cutout','RGB-prebaked-tint','discrete-cropped-frame-playback'},
  pending_paths={'translucent-parent-probe','texture-interpolation','emission-calibration','tint-color-routing'}}
end
return M
