local dir=assert(arg[1]);local Bind=dofile(dir..'/capture_shader_mid_bindings.lua')
local n=0;local function check(v,why)assert(v,why);n=n+1 end
local function obj(t)t=t or{};function t:IsValid()return true end;function t:GetAddress()return 250 end;return t end
local root='D:/bridge/entity-capture-v1/textures/';local a=root..string.rep('a',64)..'.png';local b=root..string.rep('b',64)..'.png'
local blend={v=1,source='actual_render_pipeline',equation='actual-fixture-equation',depth={compare='GREATER_THAN_OR_EQUAL',write=false},cull=true,
 shader_flags={'EMISSIVE','NO_OVERLAY','NO_CARDINAL_LIGHTING'},shader_values={}}
local params={MCColorModulator=true,MCTextureColumn0=true,MCTextureColumn1=true,MCTextureColumn2=true,MCTextureColumn3=true}
local scalar={};for _,name in ipairs({'MCNoCardinalLighting','MCPerFaceLighting','MCNoOverlay','MCEmissive','MCApplyTextureMatrix','MCAlphaCutoutEnabled','MCAlphaCutoutValue'})do scalar[name]=true end
local asset='/Game/PalCraftNative/Materials/M_MCEntity_Translucent.M_MCEntity_Translucent'
local variant={equation=blend.equation,depth_compare=blend.depth.compare,depth_write=false,cull=true,fog_consumed=true,
 inherited_parameters_evidence='fixture-only',vector_parameters=params,scalar_parameters=scalar}
local receipt={source_spec_sha256='5c89a00a47827ab6fd226afe2bc38ece54ac823a972be34efc1e4ef076799f7a',
 shader_source_sha256='ea4cd734681cefe548de5f13e010978a772c88ca672c0c32f2e9b808b18cd7ac',cooked_asset_evidence='fixture-only',parents={[asset]=variant}}
local parent=obj({MaterialDomain=0,ShadingModel=0});function parent:GetBlendMode()return 2 end;function parent:GetBaseMaterial()return self end
local created=0;local o={asset_root=root,cooked_contract=receipt,name=function(s)return s end,load_asset=function()return parent end,
 create_material=function()
  created=created+1;local mid=obj({vectors={},scalars={},textures={}})
  function mid:K2_GetTextureParameterValue()return obj()end;function mid:K2_GetVectorParameterValue()return{}end;function mid:K2_GetScalarParameterValue()return 0 end
  function mid:SetTextureParameterValue(k,v)self.textures[k]=v end;function mid:SetVectorParameterValue(k,v)self.vectors[k]=v end;function mid:SetScalarParameterValue(k,v)self.scalars[k]=v end
  return mid
 end,import_texture=function(_,path)return obj({path=path})end}
local g={actual_renderer_capture=true,alpha_mode='translucent',capture_blend=blend,capture_entity_id=12,capture_batch_index=1,capture_epoch=1,capture_producer_epoch='producer:9',
 texture_path=a,vertices={{}},vertex_colors={{.2,.4,.6,.8}},mc_shader_inputs={dynamic_transforms={available=true,ColorModulator={.2,.3,.4,.5},
 TextureMat={1,0,0,0,0,1,0,0,0,0,1,0,4,5,0,1}}}}
local ctx=obj();local bind=Bind.new(o);local first=assert(bind:resolve(ctx,g))
check(first.material.vectors.MCColorModulator.A==.5 and first.material.vectors.MCTextureColumn3.R==4,'bind actual colorMod and original column-major texture matrix')
g.capture_epoch=2;g.texture_path=b;g.mc_shader_inputs.dynamic_transforms.ColorModulator={.9,.8,.7,.6}
local nextvalue=assert(bind:resolve(ctx,g))
check(nextvalue==first and created==1 and nextvalue.material.vectors.MCColorModulator.R==.9 and nextvalue.textures.MCSampler0.path==b,'next retained frame updates same entity MID and true texture/vector values')
g.capture_entity_id=13;check(bind:resolve(ctx,g)~=first and created==2,'different entity sharing skin does not share per-row shader values')
o.cooked_contract=nil;local value,why=Bind.new(o):resolve(ctx,g)
check(not value and why=='native7_actual_cooked_parent_required','uncooked source never becomes material-supported')
print(string.format('{"status":"passed","checks":%d,"engine_calls":0,"real_cooked_parent":false,"only_new_mid_contract_fixture":true}',n))
