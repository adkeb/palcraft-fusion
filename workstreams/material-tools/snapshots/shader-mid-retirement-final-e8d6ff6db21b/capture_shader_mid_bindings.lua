-- Native7 material-source contract. This writes actual captured inputs to the
-- existing MID on the game thread; no renderer, timer, readback or world reader.
local M={version=1}
local parents={opaque={name='Opaque',blend=0},cutout={name='Masked',blend=1},translucent={name='Translucent',blend=2},additive={name='Additive',blend=3}}
local function valid(o)return o and o.IsValid and o:IsValid()end
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function vector(a,n)if type(a)~='table'or #a~=n then return false end;for _,v in ipairs(a)do if not finite(v)then return false end end;return true end
local function path(root,p)
 if type(p)~='string'or p:sub(1,#root)~=root then return false end
 local name=p:sub(#root+1);return #name==68 and name:sub(-4)=='.png'and not name:sub(1,64):find('[^0-9a-f]')
end
local function color(v)return{R=v[1],G=v[2],B=v[3],A=v[4]or 0}end
function M.new(o)
 local root=assert(o.asset_root):gsub('[\\/]+$','')..'/'
 local load=o.load_asset or LoadAsset;local name=o.name or FName
 local create=o.create_material or function(ctx,p,label)return StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(ctx,p,name(label),0)end
 local import=o.import_texture or function(ctx,p)return StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(ctx,p)end
 local self={materials={},textures={},stats={created=0,updates=0,imports=0}}
 local function collect_textures()
  -- Every material here belongs to a retained native row. Explicit retirement
  -- removes row entries first, so this operation never dereferences UObjects.
  local used={};for _,retained in pairs(self.materials)do
   for _,texture in pairs(retained.textures)do used[texture]=true end
  end
  for key,texture in pairs(self.textures)do if not used[texture]then self.textures[key]=nil end end
 end
 function self:resolve(ctx,g)
  if IsInGameThread then assert(IsInGameThread(),'Original shader MID inputs require game thread')end
  if not valid(ctx)or g.actual_renderer_capture~=true then return nil,'original_shader_capture_required'end
  local b=g.capture_blend;local target=b and parents[g.alpha_mode]
  if not target or b.source~='actual_render_pipeline'or b.v~=1 or g.material_binding_reason then return nil,'typed_shader_route_not_supported'end
  local receipt=o.cooked_contract
  if not receipt or receipt.source_spec_sha256~='5c89a00a47827ab6fd226afe2bc38ece54ac823a972be34efc1e4ef076799f7a'
   or receipt.shader_source_sha256~='ea4cd734681cefe548de5f13e010978a772c88ca672c0c32f2e9b808b18cd7ac'
   or not receipt.cooked_asset_evidence then return nil,'native7_actual_cooked_parent_required'end
  local asset='/Game/PalCraftNative/Materials/M_MCEntity_'..target.name..'.M_MCEntity_'..target.name
  local contract=receipt.parents and receipt.parents[asset]
  if type(b.depth)~='table'or not contract or contract.equation~=b.equation or contract.depth_compare~=b.depth.compare or contract.depth_write~=b.depth.write
   or contract.cull~=b.cull or not contract.inherited_parameters_evidence then return nil,'native7_cooked_variant_contract_mismatch'end
  local flags={};for _,flag in ipairs(b.shader_flags or{})do flags[flag]=true end
  for _,flag in ipairs({'GLINT','DISSOLVE','OIT_ACCUMULATE','OIT_ALPHA_ONLY','OIT_ADDITIVE'})do if flags[flag]then return nil,'native7_'..flag..'_shader_not_consumed'end end
  if contract.fog_consumed~=true then return nil,'native7_original_fog_contract_required'end
  local inputs=g.mc_shader_inputs or{};local dynamic=inputs.dynamic_transforms
  if not dynamic or dynamic.available~=true or not vector(dynamic.ColorModulator,4)or not vector(dynamic.TextureMat,16)then return nil,'native7_original_dynamic_inputs_pending'end
  local cardinal=inputs.cardinal_lighting
  local need_light=flags.PER_FACE_LIGHTING or not flags.NO_CARDINAL_LIGHTING
  if need_light and(not cardinal or cardinal.available~=true or cardinal.space~='minecraft_original_normal_basis'
   or not vector(cardinal.Light0_Direction,3)or not vector(cardinal.Light1_Direction,3))then return nil,'native7_original_cardinal_inputs_pending'end
  if not g.capture_entity_id or not g.capture_batch_index or not g.capture_epoch or not g.capture_producer_epoch then return nil,'native7_exact_entity_batch_epoch_required'end
  local samplers={MCSampler0=g.texture_path};local count=#g.vertices
  for _,layer in ipairs({{sampler='Sampler1',parameter='MCSampler1',needed=not flags.NO_OVERLAY,uv='overlay_uvs',written='mc_uv1_written_vertices'},
   {sampler='Sampler2',parameter='MCSampler2',needed=not flags.EMISSIVE,uv='light_uvs',written='mc_uv2_written_vertices'}})do
   if layer.needed then
    local descriptor=(g.mc_shader_textures or{})[layer.sampler];local p=(g.mc_sampler_paths or{})[layer.sampler]
    if not descriptor or descriptor.source_epoch~=g.capture_epoch or not descriptor.source or not descriptor.revision
     or not path(root,p)or p:sub(-68,-5)~=descriptor.sha256 or not vector({descriptor.width,descriptor.height},2)
     or descriptor.width<=0 or descriptor.height<=0 then return nil,'native7_'..layer.sampler..'_original_resource_pending'end
    local uv=g[layer.uv];if g[layer.written]~=count or type(uv)~='table'or #uv~=count then return nil,'native7_'..layer.sampler..'_original_uv_pending'end
    for _,pair in ipairs(uv)do if not vector(pair,2)or not math.tointeger(pair[1])or not math.tointeger(pair[2])then return nil,'native7_original_uv_integer_required'end end
    samplers[layer.parameter]=p
   end
  end
  if not path(root,samplers.MCSampler0)then return nil,'native7_original_sampler0_pending'end
  local vectors={MCColorModulator=dynamic.ColorModulator}
  if need_light then vectors.MCLight0=cardinal.Light0_Direction;vectors.MCLight1=cardinal.Light1_Direction end
  for column=0,3 do local offset=column*4;vectors['MCTextureColumn'..column]={dynamic.TextureMat[offset+1],dynamic.TextureMat[offset+2],dynamic.TextureMat[offset+3],dynamic.TextureMat[offset+4]}end
  local values=b.shader_values or{};local threshold=values.ALPHA_CUTOUT and tonumber(values.ALPHA_CUTOUT)
  if values.ALPHA_CUTOUT and(not finite(threshold)or threshold<0 or threshold>1)then return nil,'native7_alpha_cutout_value_invalid'end
  local scalars={MCNoCardinalLighting=flags.NO_CARDINAL_LIGHTING and 1 or 0,MCPerFaceLighting=flags.PER_FACE_LIGHTING and 1 or 0,
   MCNoOverlay=flags.NO_OVERLAY and 1 or 0,MCEmissive=flags.EMISSIVE and 1 or 0,MCApplyTextureMatrix=flags.APPLY_TEXTURE_MATRIX and 1 or 0,
   MCAlphaCutoutEnabled=threshold and 1 or 0,MCAlphaCutoutValue=threshold or 0}
  -- The producer epoch scopes MID lifetime; the changing retained-frame epoch
  -- scopes resources. Per-frame UBO/texture changes update this SAME row MID.
  local key=tostring(ctx:GetAddress())..':'..g.capture_entity_id..':'..g.capture_batch_index..':'..g.capture_producer_epoch..':'..asset..':'..tostring(b.equation)
  local value=self.materials[key]
  if not value or not valid(value.material)then
   local parent=load(asset);if not valid(parent)or tonumber(parent:GetBlendMode())~=target.blend then return nil,'native7_parent_asset_or_blend_mismatch'end
   local base=parent:GetBaseMaterial();if not valid(base)or tonumber(base.MaterialDomain)~=0 or tonumber(base.ShadingModel)~=0 then return nil,'native7_parent_not_unlit_surface'end
   _G.PalCraftShaderMIDSerial=(_G.PalCraftShaderMIDSerial or 0)+1
   local mid=create(ctx,parent,'MC_OriginalShader_'.._G.PalCraftShaderMIDSerial);if not valid(mid)then return nil,'native7_mid_unavailable'end
   -- Receipt gives exact cooked declarations. Texture inheritance is checked
   -- before overrides; vectors/scalars are read before writing their real inputs.
   for parameter in pairs(samplers)do if not valid(mid:K2_GetTextureParameterValue(name(parameter)))then return nil,'native7_inherited_sampler_missing'end end
   for parameter in pairs(vectors)do if not contract.vector_parameters or contract.vector_parameters[parameter]~=true then return nil,'native7_vector_declaration_missing'end;mid:K2_GetVectorParameterValue(name(parameter))end
   for parameter in pairs(scalars)do if not contract.scalar_parameters or contract.scalar_parameters[parameter]~=true then return nil,'native7_scalar_declaration_missing'end;mid:K2_GetScalarParameterValue(name(parameter))end
   value={material=mid,textures={}};self.materials[key]=value;self.stats.created=self.stats.created+1
  end
  for parameter,p in pairs(samplers)do
   local tk=tostring(ctx:GetAddress())..':'..p;local texture=self.textures[tk]
   if not valid(texture)then texture=import(ctx,p);if not valid(texture)then return nil,'native7_original_texture_import_failed'end;self.textures[tk]=texture;self.stats.imports=self.stats.imports+1 end
   value.material:SetTextureParameterValue(name(parameter),texture);value.textures[parameter]=texture
  end
  for parameter,v in pairs(vectors)do value.material:SetVectorParameterValue(name(parameter),color(v))end
  for parameter,v in pairs(scalars)do value.material:SetScalarParameterValue(name(parameter),v)end
  value.retirement={ctx=tostring(ctx:GetAddress()),entity=g.capture_entity_id,producer_epoch=g.capture_producer_epoch}
  value.group=g;value.original_shader_inputs=g.mc_shader_inputs;value.vertex_rgba=g.vertex_colors;value.overlay_uvs=g.overlay_uvs;value.light_uvs=g.light_uvs
  collect_textures()
  value.shader_verified=contract.actual_game_image==true;self.stats.updates=self.stats.updates+1;return value
 end
 function self:retire_entity(ctx,entity_id,producer_epoch)
  -- Called only after the native consumer confirms release/retirement of this
  -- exact authoritative entity row. No native destroy and no file deletion.
  local address=type(ctx)=='string'and ctx or tostring(ctx:GetAddress())
  for key,value in pairs(self.materials)do local row=value.retirement
   if row and row.ctx==address and row.entity==entity_id and row.producer_epoch==producer_epoch then self.materials[key]=nil end
  end
  collect_textures();return true
 end
 function self:reset()self.materials={};self.textures={}end
 return self
end
return M
