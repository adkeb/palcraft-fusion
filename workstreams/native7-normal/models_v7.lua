-- Minecraft models become complete, visual-only Unreal procedural meshes.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local J=dofile(dir..'json.lua')
local ROOT=dofile(dir..'runtime/paths.lua').bridge
local ShaderAttributes=dofile(dir..'native_shader_attributes.lua')
local ASSETS=ROOT..'models-v2/'
local asset_package,geometry_version
geometry_version=2
local config_file=io.open(ROOT..'model-assets.json','rb')
if config_file then
 asset_package=J.decode(config_file:read('*a'));config_file:close()
 local major=type(asset_package.directory)=='string'and tonumber(asset_package.directory:match('^models%-v([234])%-%x+$'))
 assert(asset_package.schema_version==1 and major,'Invalid model asset package')
 geometry_version=asset_package.provider_version or(major>=3 and 3 or 2)
 assert(geometry_version==2 or geometry_version==3,'Unsupported geometry provider')
 ASSETS=ROOT..asset_package.directory..'/'
end
local Geometry=dofile(dir..'model_geometry_v'..geometry_version..'.lua')
Geometry.configure({json=J,root=ASSETS})
local M={version=7,geometry_version=geometry_version,shader_attributes=ShaderAttributes.status(),stats={created=0,sections=0,vertices=0,indices=0,updates=0,released=0}}
local native,pe,parent,normal,material_provider,update_native,release_native,update_section
local model_states,block_animations,block_targets={},{},{}
local handles,generation,world_context={},1,nil
local function clear_dead_models()
 model_states={};block_animations={};block_targets={};handles={};world_context=nil;M.active_fence=nil
end
-- Retain resources separately from each companion's actors/tick closure. A
-- replay can reuse textures; it never merges old and new companion state.
local resources=_G.PalCraftNativeModelResources or{}
_G.PalCraftNativeModelResources=resources
function M.geometry(id,state,x,y,z,options)return Geometry.geometry(id,state,x,y,z,options)end
local function address(path)local o=StaticFindObject(path);assert(o and o:IsValid(),path);return o:GetAddress()end
local functions
local function ensure_runtime()
 if native then return end
 parent=LoadAsset('/Game/Pal/Material/Prop/MI_PalPropBase.MI_PalPropBase');assert(parent:IsValid(),'Base prop material unavailable')
 normal=LoadAsset('/Engine/EngineMaterials/DefaultNormal.DefaultNormal')
 for line in io.lines(dir..'../../../UE4SS.log')do local a=line:match('ProcessEvent address (0x%x+)');if a then pe=tonumber(a)end end;assert(pe,'ProcessEvent')
 native=assert(package.loadlib(dir..'../../../../PalCraftModel-v7.dll','palcraft_create_model'))
 update_native=assert(package.loadlib(dir..'../../../../PalCraftModel-v7.dll','palcraft_update_model'))
 release_native=assert(package.loadlib(dir..'../../../../PalCraftModel-v7.dll','palcraft_release_model'))
 update_section=address('/Script/ProceduralMeshComponent.ProceduralMeshComponent:UpdateMeshSection_LinearColor')
 functions={address('/Script/Engine.Default__GameplayStatics'),address('/Script/Engine.Actor'),address('/Script/Engine.GameplayStatics:BeginDeferredActorSpawnFromClass'),address('/Script/Engine.GameplayStatics:FinishSpawningActor'),address('/Script/ProceduralMeshComponent.ProceduralMeshComponent'),address('/Script/Engine.Actor:AddComponentByClass'),address('/Script/ProceduralMeshComponent.ProceduralMeshComponent:CreateMeshSection_LinearColor'),address('/Script/Engine.PrimitiveComponent:SetMaterial'),pe,address('/Script/Engine.Actor:K2_SetActorLocation'),address('/Script/Engine.Actor:FinishAddComponent'),address('/Script/Engine.PrimitiveComponent:SetCollisionEnabled'),address('/Script/Engine.PrimitiveComponent:SetCollisionResponseToAllChannels'),address('/Script/Engine.SceneComponent:SetMobility'),address('/Script/Engine.PrimitiveComponent:SetGenerateOverlapEvents'),address('/Script/Engine.Actor:K2_DestroyActor'),address('/Script/Engine.Actor:SetActorHiddenInGame')}
end
local function material(ctx,g)
 -- Entity skins use their own frozen package and opaque, non-WPO parent.
 -- Block profiles/tints/texture timelines stay with the material provider.
 if material_provider then
  local value=material_provider(ctx,g,g.material_root or ASSETS)
  local m=type(value)=='table'and value.material or value
  assert(m and m:IsValid(),'Material provider rejected '..g.texture)
  resources['provider:'..tostring(m:GetAddress())]=value
  return m:GetAddress()
 end
 local name=g.texture
 local texture_path=g.entity_visual and g.texture_path or(ASSETS..'textures/'..name:gsub(':','/')..'.png')
 if g.entity_visual then assert(type(texture_path)=='string'and texture_path:find(ROOT..'entity-assets-',1,true)==1,'Entity skin outside frozen entity assets')end
 local key=texture_path..':'..(g.alpha_mode or'opaque')..':'..(g.tint or-1)..':'..tostring(g.shade~=false)..':'..(g.light_emission or 0)
 local old=resources[key]
 if old and old.material:IsValid()and old.texture:IsValid()then return old.material:GetAddress()end
 _G.PalCraftNativeMaterialSerial=(_G.PalCraftNativeMaterialSerial or 0)+1
 local m=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(ctx,parent,FName('MC_v4_'..name:gsub('[:/]','_')..'_'.._G.PalCraftNativeMaterialSerial),0)
 local tex=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(ctx,texture_path)
 assert(m:IsValid()and tex:IsValid(),'Model texture '..name);tex.Filter=0
 m:SetTextureParameterValue(FName('Base Texture'),tex)
 if normal:IsValid()then m:SetTextureParameterValue(FName('Normal Map'),normal)end
 m:SetScalarParameterValue(FName('Roughness Add'),1);m:SetScalarParameterValue(FName('ChangeColor Rate'),0)
 resources[key]={material=m,texture=tex,alpha_mode=g.alpha_mode or'opaque'}
 return m:GetAddress()
end
function M.spawn_groups(ctx,origin,groups,at,options)
 options=options or{};local x,y,z=table.unpack(at)
 if #groups==0 then return nil,'occluded' end
 ShaderAttributes.validate(groups)
 ensure_runtime()
 local pointers={ctx:GetAddress()};for _,p in ipairs(functions)do pointers[#pointers+1]=p end
 -- Resolve all textures before publishing a request. Native validates the whole
 -- request before spawning and registers only after all sections have materials.
 local mats={};for i,g in ipairs(groups)do mats[i]=material(ctx,g)end
 local pending=ROOT..'model-request.pending'
 local f=assert(io.open(pending,'wb'))
 f:write(string.pack('<c8'..string.rep('I8',18),'PALCPRC7',table.unpack(pointers)))
 f:write(string.pack('<dddI4I4',origin.X+x*100,origin.Y-z*100,origin.Z+(y-(origin.y_origin or 64))*100,#groups,(options.hidden and 1 or 0)+2))
 for i,g in ipairs(groups)do
  f:write(string.pack('<I8I4I4',mats[i],#g.vertices,#g.indices))
  for vertex_index,v in ipairs(g.vertices)do
   local color=g.vertex_colors and g.vertex_colors[vertex_index]or{1,1,1,1}
   local function byte(value)assert(type(value)=='number'and value>=0 and value<=1,'Vertex RGBA outside original normalized range');return math.floor(value*255+.5)end
   local rgba=(byte(color[4])<<24)|(byte(color[1])<<16)|(byte(color[2])<<8)|byte(color[3])
   local nx,ny,nz=ShaderAttributes.normal(g,v)
   f:write(string.pack('<ddddddddI4I4',v[1],v[2],v[3],nx,ny,nz,v[7],v[8],rgba,0))
   f:write(string.pack('<dddd',ShaderAttributes.vertex(g,vertex_index)))
  end
  for _,index in ipairs(g.indices)do f:write(string.pack('<I4',index))end
 end
 f:close();os.remove(ROOT..'model-request.bin');assert(os.rename(pending,ROOT..'model-request.bin'));os.remove(ROOT..'model-result.json');native()
 f=assert(io.open(ROOT..'model-result.json','rb'));local result=J.decode(f:read('*a'));f:close();assert(result.ok,'Procedural model: '..tostring(result.stage))
 M.stats.created=M.stats.created+1;M.stats.sections=M.stats.sections+(result.sections or 0);M.stats.vertices=M.stats.vertices+(result.vertices or 0);M.stats.indices=M.stats.indices+(result.indices or 0)
 local actor,component=tonumber(result.actor),tonumber(result.component)
 assert(result.native_id and result.native_id>0,'Native model lifetime token missing')
 model_states[actor]={actor=actor,component=component,native_id=result.native_id,ctx=ctx,pointers=pointers,
  position={origin.X+x*100,origin.Y-z*100,origin.Z+(y-(origin.y_origin or 64))*100},groups=groups,materials=mats}
 return actor,component,result.native_id
end
function M.spawn(ctx,origin,geometry,x,y,z,options)
 local groups,why=M.geometry(geometry.id,geometry.state,x,y,z,options)
 if not groups then return nil,why end
 local actor,component,token=M.spawn_groups(ctx,origin,groups,{x,y,z},options)
 if actor and Geometry.clip then
  local clip,spec=Geometry.clip(geometry.id,geometry.state,x,y,z)
  if clip then
   local dim=geometry.dim or'minecraft:overworld';local key=dim..':'..x..':'..y..':'..z
   block_animations[actor]={actor=actor,id=geometry.id,at={x,y,z},dim=dim,key=key,
    groups=groups,clip=clip,spec=spec,progress=0,target=block_targets[key]or 0,accumulator=0}
  end
 end
 return actor,component,token
end
M.capabilities={version=7,opaque=true,cutout=false,translucent=false,tint=false,animation=false,dynamic=false,
 compound_collision=false,hidden_prepare=true,atomic_pages=true}
local function current_model(actor)
 local state=assert(model_states[actor],'Unknown model lifetime')
 assert(state.ctx:IsValid(),'Model world unloaded')
 if state.object and state.object:IsValid()and state.root and state.root:IsValid()then return state end
 for _,component in ipairs(FindAllOf('ProceduralMeshComponent')or{})do
  if component:IsValid()and component:GetAddress()==state.component then
   local object=component:GetOwner();local owner=object and object:IsValid()and object:GetOwner()
   if object and object:IsValid()and object:GetAddress()==actor and owner and owner:IsValid()and owner:GetAddress()==state.ctx:GetAddress()then state.object=object;state.root=component;return state end
  end
 end
 error('Model Actor/component lifetime changed')
end
function M.update_groups(actor,groups)
 assert(not IsInGameThread or IsInGameThread(),'Model update requires game thread')
 ShaderAttributes.validate(groups)
 local state=current_model(actor);assert(#groups==#state.groups,'Model update topology changed')
 for i,g in ipairs(groups)do
  assert(#g.vertices==#state.groups[i].vertices and #g.indices==#state.groups[i].indices,'Model update topology changed')
  for j,index in ipairs(g.indices)do assert(index==state.groups[i].indices[j],'Model update index changed')end
 end
 -- Resolve the actual same-frame shader resources before publishing any native
 -- update. Native7 applies a changed MID to the existing section after validation.
 local mats={};for i,g in ipairs(groups)do mats[i]=material(state.ctx,g)end
 local pending=ROOT..'model-update-request.pending';local f=assert(io.open(pending,'wb'))
 f:write(string.pack('<c8'..string.rep('I8',18),'PALCUPD7',table.unpack(state.pointers)))
 f:write(string.pack('<dddI4I4',state.position[1],state.position[2],state.position[3],#groups,2))
 f:write(string.pack('<I8I8I8I8',actor,state.component,state.native_id,update_section))
 for i,g in ipairs(groups)do
  f:write(string.pack('<I8I4I4',mats[i],#g.vertices,#g.indices))
  for vertex_index,v in ipairs(g.vertices)do
   local color=g.vertex_colors and g.vertex_colors[vertex_index]or{1,1,1,1}
   local function byte(value)assert(type(value)=='number'and value>=0 and value<=1,'Vertex RGBA outside original normalized range');return math.floor(value*255+.5)end
   local rgba=(byte(color[4])<<24)|(byte(color[1])<<16)|(byte(color[2])<<8)|byte(color[3])
   local nx,ny,nz=ShaderAttributes.normal(g,v)
   f:write(string.pack('<ddddddddI4I4',v[1],v[2],v[3],nx,ny,nz,v[7],v[8],rgba,0))
   f:write(string.pack('<dddd',ShaderAttributes.vertex(g,vertex_index)))
  end
  for _,index in ipairs(g.indices)do f:write(string.pack('<I4',index))end
 end
 f:close();os.remove(ROOT..'model-update-request.bin');assert(os.rename(pending,ROOT..'model-update-request.bin'));os.remove(ROOT..'model-result.json');update_native()
 f=assert(io.open(ROOT..'model-result.json','rb'));local result=J.decode(f:read('*a'));f:close()
 assert(result.ok and result.native_id==state.native_id,'Native model update: '..tostring(result.stage))
 state.materials=mats;M.stats.updates=M.stats.updates+1;return actor
end
function M.release_model(actor,destroy)
 local state=model_states[actor];if not state then return false end
 ensure_runtime()
 if destroy then current_model(actor)end
 local f=assert(io.open(ROOT..'model-release-request.pending','wb'))
 f:write(string.pack('<c8I8I8I8I8I8I8I4I4','PALCREL1',state.pointers[1],actor,state.component,state.native_id,functions[16],pe,destroy and 1 or 0,0));f:close()
 os.remove(ROOT..'model-release-request.bin');assert(os.rename(ROOT..'model-release-request.pending',ROOT..'model-release-request.bin'))
 os.remove(ROOT..'model-result.json');release_native()
 f=assert(io.open(ROOT..'model-result.json','rb'));local result=J.decode(f:read('*a'));f:close()
 assert(result.ok and result.stage==(destroy and'destroyed'or'released'),'Native model release: '..tostring(result.stage))
 model_states[actor]=nil;block_animations[actor]=nil;M.stats.released=M.stats.released+1;return true
end
function M.abandon_models()
 if not release_native then clear_dead_models();return end
 local contexts={};for _,s in pairs(model_states)do contexts[s.pointers[1]]=true end
 for context in pairs(contexts)do
  local f=assert(io.open(ROOT..'model-release-request.pending','wb'))
  f:write(string.pack('<c8I8I8I8I8I8I8I4I4','PALCREL1',context,0,0,0,0,pe,2,0));f:close()
  os.remove(ROOT..'model-release-request.bin');assert(os.rename(ROOT..'model-release-request.pending',ROOT..'model-release-request.bin'));os.remove(ROOT..'model-result.json');release_native()
  f=assert(io.open(ROOT..'model-result.json','rb'));local result=J.decode(f:read('*a'));f:close();assert(result.ok and result.stage=='abandoned','Native model abandon failed')
 end
 clear_dead_models()
end
function M.block_event(event)
 local e=event.block_event or event
 if event.op~='block_event'or e.type~=1 or e.phase=='rejected'or e.applied==false then return false end
 local at=e.at or event.at;if not at then return false end
 local key=(event.dim or'minecraft:overworld')..':'..at[1]..':'..at[2]..':'..at[3];block_targets[key]=(e.data or 0)>0 and 1 or 0
 for _,a in pairs(block_animations)do if a.dim==(event.dim or'minecraft:overworld')and a.at[1]==at[1]and a.at[2]==at[2]and a.at[3]==at[3]then a.target=(e.data or 0)>0 and 1 or 0 end end
 return true
end
function M.tick_animations(delta_seconds)
 assert(type(delta_seconds)=='number'and delta_seconds>=0,'Animation delta required')
 for actor,a in pairs(block_animations)do
  if a.progress~=a.target then
   a.accumulator=a.accumulator+math.min(delta_seconds,.25)
   local ticks=math.floor(a.accumulator/.05);a.accumulator=a.accumulator-ticks*.05
   if ticks>0 then
    a.progress=a.target>a.progress and math.min(a.target,a.progress+ticks*.1)or math.max(a.target,a.progress-ticks*.1)
    M.update_groups(actor,Geometry.animate(a.groups,a.clip,a.progress,a.spec))
   end
  else a.accumulator=0 end
 end
end
function M.set_actor_pose(actor,position,yaw)
 local state=current_model(actor)
 state.object:K2_SetActorLocation(position,false,{},true)
 state.object:K2_SetActorRotation({Pitch=0,Yaw=yaw,Roll=0},false)
end
function M.set_visible(actor,visible)current_model(actor).object:SetActorHiddenInGame(not visible)end
function M.set_material_provider(provider,verified_capabilities)
 assert(not provider or type(provider)=='function','Material resolver function required')
 material_provider=provider
 for key,value in pairs(verified_capabilities or{})do M.capabilities[key]=value end
end
local function game_thread()
 if IsInGameThread then assert(IsInGameThread(),'Model transaction requires game thread')end
end
local function fence_key(f)
 assert(type(f)=='table'and type(f.world_session)=='string'and #f.world_session>0,'World session fence required')
 assert(type(f.dim)=='string'and #f.dim>0,'Dimension fence required')
 assert(math.tointeger(f.view)and f.view>=0,'View fence required')
 assert(type(f.mapping)=='string'and #f.mapping>0,'Mapping fence required')
 return J.encode({world_session=f.world_session,dim=f.dim,view=f.view,mapping=f.mapping})
end
local function descriptor_present(value)
 if value==nil or value==false or value==J.null then return false end
 -- JSON decoders can have distinct null singleton tables across modules.
 -- An empty descriptor has no animation to execute.
 if type(value)=='table'and next(value)==nil then return false end
 return true
end
local function validate_materials(groups,allow_block_clip)
 for _,g in ipairs(groups)do
  local mode=g.alpha_mode or'opaque'
  assert(M.capabilities[mode],'Unsupported native material: '..mode)
  assert((g.tint or-1)<0 or M.capabilities.tint,'Native biome tint not accepted')
  assert(not descriptor_present(g.animation_clip)and not descriptor_present(g.animation)or M.capabilities.animation or allow_block_clip,'Native animation not accepted')
 end
end
function M.prepare(ctx,origin,batch)
 game_thread();assert(ctx and ctx:IsValid(),'Model context unavailable')
 assert(type(batch)=='table'and type(batch.groups)=='table'and #batch.groups>0,'Nonempty model batch required')
 assert(type(batch.at)=='table'and #batch.at==3 and math.tointeger(batch.revision),'Batch placement/revision required')
 assert(not batch.generation or batch.generation==generation,'Superseded model batch generation')
 local fence=fence_key(batch.fence);validate_materials(batch.groups,batch.block_clip~=nil)
 local context=ctx:GetAddress();assert(not world_context or context==world_context,'Reset model adapter before world travel')
 local actor,component=M.spawn_groups(ctx,origin,batch.groups,batch.at,{hidden=true})
 assert(actor and component,'Native model preparation failed');world_context=context
 local h={actor=actor,component=component,revision=batch.revision,generation=generation,world=context,
  fence={world_session=batch.fence.world_session,dim=batch.fence.dim,view=batch.fence.view,mapping=batch.fence.mapping},
  fence_key=fence,state='prepared',native_registered=true}
 handles[actor]=h;return h
end
function M.prepare_block(ctx,origin,entry,packet)
 assert(type(entry)=='table'and entry.id and entry.at and entry.groups,'Exact dynamic block descriptor required')
 assert(Geometry.clip,'Geometry provider does not expose block clips')
 local clip,spec=Geometry.clip(entry.id,entry.state,entry.at[1],entry.at[2],entry.at[3])
 assert(clip,'Block is not a supported original animation')
 local h=M.prepare(ctx,origin,{groups=entry.groups,at=entry.at,revision=packet.revision,generation=packet.generation,
  fence=packet.fence,block_clip=clip})
 local dim=packet.dimension or packet.dim or packet.fence.dim
 local key=dim..':'..entry.at[1]..':'..entry.at[2]..':'..entry.at[3]
 block_animations[h.actor]={actor=h.actor,id=entry.id,at=entry.at,dim=dim,key=key,groups=entry.groups,
  clip=clip,spec=spec,progress=0,target=block_targets[key]or 0,accumulator=0}
 return h
end
local function list(value)
 if not value then return{}end
 return value.actor and{value}or value
end
local function validate_handle(h,state)
 assert(type(h)=='table'and handles[h.actor]==h,'Unknown native model handle')
 assert(h.generation==generation and h.world==world_context,'Stale model generation/context')
 assert(not state or h.state==state,'Model handle is not '..tostring(state))
end
local function actor_objects(fresh,old)
 local wanted,found={},{}
 for _,h in ipairs(fresh)do wanted[h.actor]=true end
 for _,h in ipairs(old)do wanted[h.actor]=true end
 for _,a in ipairs(FindAllOf('Actor')or{})do if a:IsValid()and wanted[a:GetAddress()]then found[a:GetAddress()]=a end end
 for _,h in ipairs(fresh)do assert(found[h.actor],'Prepared actor unavailable')end
 return found
end
function M.commit_transaction(prepared,previous,collision)
 game_thread();prepared,previous=list(prepared),list(previous)
 local seen,fence,revision={}
 for _,h in ipairs(prepared)do
  validate_handle(h,'prepared');assert(not seen[h.actor],'Duplicate prepared model');seen[h.actor]=true
  fence=fence or h.fence_key;revision=revision or h.revision
  assert(h.fence_key==fence and h.revision==revision,'Mixed world/view/revision transaction')
 end
 for _,h in ipairs(previous)do validate_handle(h,'active');assert(not seen[h.actor],'Model exists in both revisions');seen[h.actor]=true end
 if collision and collision.expected_fence then assert(not fence or fence==fence_key(collision.expected_fence),'Superseded world view')end
 local objects=actor_objects(prepared,previous)
 if collision then
  assert(collision.adapter and collision.adapter.preflight and collision.adapter.commit,'Collision transaction adapter required')
  collision.adapter.preflight(collision.prepared or{},collision.previous or{})
  -- Every prospective visual is valid before collider commit mutates physics.
  collision.adapter.commit(collision.prepared or{},collision.previous or{})
 end
 for _,h in ipairs(prepared)do objects[h.actor]:SetActorHiddenInGame(false);h.state='active'end
 for _,h in ipairs(previous)do local a=objects[h.actor];if a then a:SetActorHiddenInGame(true)end end
 for _,h in ipairs(previous)do local a=objects[h.actor];if a then M.release_model(h.actor,true)else M.release_model(h.actor,false)end;h.state='released';handles[h.actor]=nil end
 if prepared[1]then M.active_fence=prepared[1].fence end
 return{visual=prepared,registered=true,revision=revision,fence=prepared[1]and prepared[1].fence}
end
function M.commit(prepared,previous)return M.commit_transaction(prepared,previous)end
function M.unload(value)
 game_thread();local selected=list(value)
 for _,h in ipairs(selected)do validate_handle(h)end
 local objects=actor_objects({},selected)
 for _,h in ipairs(selected)do local a=objects[h.actor];if a then M.release_model(h.actor,true)else M.release_model(h.actor,false)end;h.state='released';handles[h.actor]=nil end
end
function M.discard(value)
 for _,h in ipairs(list(value))do validate_handle(h,'prepared')end
 return M.unload(value)
end
function M.reset(next_generation,context_alive)
 game_thread();assert(math.tointeger(next_generation)and next_generation>generation,'Model generation must increase')
 if context_alive then local all={};for _,h in pairs(handles)do all[#all+1]=h end;M.unload(all)end
 if not context_alive then M.abandon_models()end
 -- Live reset unloads only transactional handles. Legacy/entity/sign callers
 -- retain their raw lifetime tokens until their explicit release_model cleanup.
 handles={};block_targets={};generation=next_generation;world_context=nil;M.active_fence=nil
end
function M.status()return{version=M.version,geometry_version=M.geometry_version,stats=M.stats,asset_root=ASSETS,asset_package=asset_package,capabilities=M.capabilities,generation=generation,active_fence=M.active_fence}end
return M
