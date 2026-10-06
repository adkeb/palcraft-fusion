-- Shared lab companion: MC is authoritative; Unreal owns rendering and physics.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Paths=dofile(dir..'runtime/paths.lua');local client=Paths.role(dir)=='client'
assert(client or Paths.role(dir)=='server','Use the configured client or BridgeLab installation')
local J=dofile(dir..'json.lua');local JOURNAL=Paths.journal
local SHARED=Paths.bridge
local ROOT=client and SHARED or JOURNAL
local minecraft_renderer=false
local models
if client then local f=io.open(dir..'models.lua','rb');if f then f:close();models=dofile(dir..'models.lua')end end
local EVENT_PATH=JOURNAL..'palcraft-events.ndjson'
local settings=io.open(SHARED..'world-backend.json','rb');if settings then local v=J.decode(settings:read('*a'));settings:close();if v.journal then EVENT_PATH=v.journal end end
local O={X=-308099.9282280116,Y=187800.81696803804,Z=3480.330899345611}
local origin=io.open(SHARED..'world-origin.json','rb');if origin then O=J.decode(origin:read('*a'));origin:close()end
local FULL={{0,0,0,1,1,1}}
local M={items={},actors={},queue={},queued={},queue_head=1,offset=0,pending='',running=true,changes=0,origin=O}
M.models=models
M.geometry_signature=function(g)return J.encode(g)end
local visual_pipeline
local native,addresses,process_event,world_address,mesh,parent,normal;local materials={}
local bound_context,bound_context_address,bound_world_address
local function live(x)return x and x:IsValid()and not x:GetFullName():find('Default__',1,true)end
local function write(name,v)local f=assert(io.open(ROOT..name,'wb'));f:write(J.encode(v));f:close()end
local function address(name)local o=StaticFindObject(name);assert(o and o:IsValid(),name);return o:GetAddress()end
local function context()for _,a in ipairs(FindAllOf('GameStateBase')or{})do if live(a)then return a end end;error('No game state')end
local function prepare()
 if native then return end
 native=assert(package.loadlib(dir..'../../../../PalCraftMesh-v6.dll','palcraft_spawn_box'))
 if client then
  mesh=LoadAsset('/Engine/BasicShapes/Cube.Cube');assert(mesh:IsValid(),'Cube asset')
  parent=LoadAsset('/Game/Pal/Model/Prop/Architecture/Architecture_Wood/Material/MI_PalProp_Wall_Wood.MI_PalProp_Wall_Wood')
  assert(parent:IsValid(),'Wood material')
  normal=LoadAsset('/Engine/EngineMaterials/DefaultNormal.DefaultNormal')
 end
 for line in io.lines(dir..'../../../UE4SS.log')do local a=line:match('ProcessEvent address (0x%x+)');if a then process_event=tonumber(a)end end
 assert(process_event,'ProcessEvent address unavailable')
 addresses={}
 for _,name in ipairs({'BoxComponent:SetBoxExtent','PrimitiveComponent:SetCollisionEnabled','PrimitiveComponent:SetGenerateOverlapEvents','PrimitiveComponent:SetCollisionResponseToAllChannels','PrimitiveComponent:SetCollisionResponseToChannel','ActorComponent:SetIsReplicated','Actor:SetReplicates','Actor:SetReplicateMovement','Actor:SetActorHiddenInGame','Actor:K2_DestroyActor'})do addresses[#addresses+1]=address('/Script/Engine.'..name)end
 if client then addresses[1]=address('/Script/Engine.SceneComponent:SetMobility')end
end
local function material_for(id)
 if not client then return 0 end
 local texture_name=(id or 'minecraft:oak_planks'):gsub('^minecraft:',''):gsub('_stairs$',''):gsub('_slab$','')
 if texture_name=='oak'then texture_name='oak_planks'end
 if materials[texture_name]then return materials[texture_name]:GetAddress()end
 local texture_path=SHARED..'textures/'..texture_name..'.png';local f=io.open(texture_path,'rb')
 if f then f:close()else texture_path=SHARED..'textures/stone.png'end
 local ctx=context()
 local material=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(ctx,parent,FName('PalCraft_'..texture_name),0)
 assert(material:IsValid(),'Dynamic material')
 local texture=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(ctx,texture_path)
 assert(texture:IsValid(),'MC texture');texture.Filter=0
 material:SetTextureParameterValue(FName('Base Texture'),texture)
 if normal and normal:IsValid()then material:SetTextureParameterValue(FName('Normal Map'),normal)end
 material:SetScalarParameterValue(FName('Roughness Add'),0.6)
 materials[texture_name]=material;return material:GetAddress()
end
local function invoke(action,actor,x,y,z,bounds,id)
 prepare();local ctx=context():GetAddress()
 if not world_address then world_address=ctx end;assert(ctx==world_address,'World changed')
 local b=bounds or FULL[1]
 local p={O.X+(x+(b[1]+b[4])*.5)*100,O.Y-(z+(b[3]+b[6])*.5)*100,O.Z+(y-64+(b[2]+b[5])*.5)*100}
 local fields={ctx,address('/Script/Engine.Default__GameplayStatics'),address(client and '/Script/Engine.StaticMeshActor'or'/Script/Engine.TriggerBox'),address('/Script/Engine.GameplayStatics:BeginDeferredActorSpawnFromClass'),address('/Script/Engine.GameplayStatics:FinishSpawningActor')}
 local material=action==0 and material_for(id)or 0
 local f=assert(io.open(ROOT..'palcraft-spawn-request.bin','wb'))
 f:write(string.pack('<c8I8I8I8I8I8','PALCMSH6',table.unpack(fields)))
 f:write(string.pack('<dddI8I8I8',p[1],p[2],p[3],action,actor or 0,process_event))
 f:write(string.pack('<'..string.rep('I8',10),table.unpack(addresses)))
 f:write(string.pack('<I8I8I8I8ddd',client and mesh:GetAddress()or 0,material,address('/Script/Engine.StaticMeshComponent:SetStaticMesh'),address('/Script/Engine.PrimitiveComponent:SetMaterial'),b[4]-b[1],b[6]-b[3],b[5]-b[2]))
 f:close();native()
 f=assert(io.open(ROOT..'palcraft-spawn-result.json','rb'));local result=J.decode(f:read('*a'));f:close()
 assert(result.ok,'Native block: '..tostring(result.stage));return tonumber(result.actor)
end
local function key(x,y,z)return('%d:%d:%d'):format(x,y,z)end
local function enqueue(kind,x,y,z,geometry)
 if M.chunk_consumer and M.chunk_consumer.filter_legacy(kind,x,y,z,geometry)==false then return end
 local k=key(x,y,z);local pending=M.queued[k]
 if pending then pending[1]=kind;pending[5]=geometry;return end
 local q={kind,x,y,z,geometry};M.queued[k]=q;M.queue[#M.queue+1]=q
end
local function queued_count()return #M.queue-M.queue_head+1 end
-- The existing reducer/journal/timer remains the sole owner. Installing a
-- binding does not destroy old actors: its postcommit callback retires each section.
function M.install_consumer(binding)
 assert(type(binding)=='table'and type(binding.filter_legacy)=='function'
  and type(binding.on_row)=='function'and type(binding.tick)=='function'
  and type(binding.stop)=='function'and type(binding.block_render_entry)=='function','Chunk consumer binding required')
 assert(M.running and not M.error,'Companion is not running')
 assert(not M.chunk_consumer or M.chunk_consumer==binding,'Another chunk consumer owns the journal')
 M.chunk_consumer=binding;return true
end
local world_observers,world_observer_order={},{}
function M.set_world_observer(observer,owner)
 assert(not observer or type(observer)=='table','World observer required')
 owner=owner or'default'
 if observer then
  if not world_observers[owner]then world_observer_order[#world_observer_order+1]=owner end
  world_observers[owner]=observer
 else
  world_observers[owner]=nil
  for i=#world_observer_order,1,-1 do if world_observer_order[i]==owner then table.remove(world_observer_order,i)end end
 end
 if owner=='default'then M.world_observer=observer end
end
M.context=context
function M.context_alive()
 if not bound_context or not bound_context:IsValid()then return false end
 local ok,current=pcall(context)
 if not ok or current:GetAddress()~=bound_context_address then return false end
 if bound_world_address then
  local good,world=pcall(function()return current:GetWorld()end)
  if not good or not world or not world:IsValid()or world:GetAddress()~=bound_world_address then return false end
 end
 return true
end
local function observe(method,...)
 -- Snapshot subscriptions before callbacks; each owner sees one reducer row once.
 local callbacks={}
 for _,owner in ipairs(world_observer_order)do
  local observer=world_observers[owner]
  if observer and observer[method]then callbacks[#callbacks+1]=observer[method]end
 end
 local first_ok,first_result
 for i,callback in ipairs(callbacks)do
  local ok,result=pcall(callback,...)
  if not ok then M.observer_error=tostring(result)end
  if i==1 then first_ok,first_result=ok,result end
 end
 return first_ok,first_result
end

local World=dofile(dir..'world_compat.lua')
M.world=World.new({dimension='minecraft:overworld',auto_view=false,
 on_upsert=function(g)enqueue('set',g.at[1],g.at[2],g.at[3],g)end,
 on_remove=function(g)enqueue('clear',g.at[1],g.at[2],g.at[3],g)end,
 on_lifecycle=function(event)
  M.last_lifecycle=event
  if visual_pipeline then visual_pipeline.on_lifecycle(event)elseif models and models.block_event then models.block_event(event)end
  observe('on_lifecycle',event,M.ingesting_row,M)
  -- Move and acknowledge the host before changing its native view.
  if event.op=='player_view'then M.pending_view=event;return false end
 end,
 on_error=function(event)M.world_error=event end})
function M.set_view(dimension,player)
 M.world:set_view(dimension,player);M.pending_view=nil
 return M.world:status()
end
local function boxes_for(g)
 if not g then return FULL end
 if g.boxes then return g.boxes end
 if g.solid==false or g.non_solid==true or(g.fluid and g.fluid.kind~='none'and not g.fluid.waterlogged and g.solid~=true)then return{}end
 return FULL
end
local function destroy_model(actor)if models and models.release_model then assert(models.release_model(actor,true),'Native model lifetime is not owned by this renderer')else invoke(1,actor,0,64,0)end end
function M.retire_legacy(section,keys,mode)
 assert(not IsInGameThread or IsInGameThread(),'Legacy retirement requires game thread')
 mode=mode or'both';assert(mode=='visual'or mode=='collision'or mode=='both','Retirement mode')
 local result={ok=true,retired=0,remaining=0,errors={}}
 for _,k in ipairs(keys)do
  local entry=M.actors[k]
  if entry then
   local function attempt(callback)
    local ok,why=pcall(callback)
    if not ok then result.ok=false;result.errors[k]=tostring(why)end
    return ok
   end
   if(mode=='visual'or mode=='both')and entry.model then
    if attempt(function()destroy_model(entry.model)end)then entry.model=nil;entry.model_component=nil;entry.model_status='retired_to_chunk'end
   end
   if mode=='collision'or mode=='both'then
    local survivors={}
    for _,h in ipairs(entry.handles)do
     if not attempt(function()invoke(1,h,entry.at[1],entry.at[2],entry.at[3])end)then survivors[#survivors+1]=h end
    end
    entry.handles=survivors
   end
   if not entry.model and #entry.handles==0 then M.actors[k]=nil;result.retired=result.retired+1
   else result.remaining=result.remaining+#entry.handles+(entry.model and 1 or 0)end
  end
 end
 if result.retired>0 then M.changes=M.changes+result.retired end
 return result
end
function M.block_render_entry(dim,at)
 if M.chunk_consumer and M.chunk_consumer.block_render_entry then return M.chunk_consumer.block_render_entry(dim,at)end
 local entry=M.actors[key(at[1],at[2],at[3])]
 if entry and entry.dim==dim then return entry end
end
function M.render_signature(g)
 return J.encode({id=g.id,state=g.state,properties=g.properties,boxes=g.boxes,
  visible=g.visible,render_kind=g.render_kind,fluid=g.fluid,tint_colors=g.tint_colors})
end
-- Material replies resume the existing logical block or dirty its existing
-- section. They never ingest a synthetic world row or replace a collider.
function M.retry_material_block(block)
 if M.chunk_consumer and M.chunk_consumer.retry_material_block
  and M.chunk_consumer.retry_material_block(block)==true then return true end
 if block.dim~=M.world.dimension then return true end
 local g=M.world:get(block.dim,block.x,block.y,block.z)
 local entry=M.block_render_entry(block.dim,{block.x,block.y,block.z})
 if not g or not entry or g.id~=block.id or g.state~=block.state or entry.visible==false or entry.model then return true end
 local ok,a,b=pcall(models.spawn,context(),O,g,block.x,block.y,block.z)
 if ok then entry.model=a;entry.model_component=a and b or nil;entry.model_status=a and'rendered'or b
 else entry.model_status='model_error: '..tostring(a)end
 if a and ok then M.changes=M.changes+1 end
 return true
end
local function apply(kind,x,y,z,geometry)
 local k=key(x,y,z);local previous=M.actors[k]
 local signature=kind=='set'and J.encode(geometry or {id='minecraft:oak_planks',boxes=FULL})or nil
 if previous and signature==previous.signature then return end
 local render_signature
 if geometry then render_signature=M.render_signature(geometry)end
 if previous and kind=='set'and render_signature==previous.render_signature then
  -- Revision/container bookkeeping must not recreate the static collider or
  -- reset a lid that is currently animating. Logical proof still tracks full g.
  previous.signature=signature;return
 end
 if previous then for _,a in ipairs(previous.handles)do invoke(1,a,x,y,z)end;if previous.model then destroy_model(previous.model)end;M.actors[k]=nil end
 if kind=='set'then
  local entry={handles={},signature=signature,render_signature=render_signature,at={x,y,z},dim=geometry and geometry.dim or M.world.dimension,id=geometry and geometry.id or'minecraft:oak_planks'};M.actors[k]=entry
  local visible=not geometry or(geometry.visible~=false and geometry.render_kind~='none')
  entry.visible=visible
  if models and geometry and visible then
   local ok,a,b=pcall(models.spawn,context(),O,geometry,x,y,z)
   if ok then entry.model=a;entry.model_component=a and b or nil;entry.model_status=a and'rendered'or b
   else entry.model_status='model_error: '..tostring(a)end
  end
  for _,b in ipairs(boxes_for(geometry))do entry.handles[#entry.handles+1]=invoke(client and(minecraft_renderer or entry.model or not visible or(visual_pipeline and visual_pipeline.material_runtime))and 3 or 0,nil,x,y,z,b,entry.id)end
 end
 M.changes=M.changes+1
end
local function update_items()
 if not client or minecraft_renderer then return end
 local f=io.open(SHARED..'drops.json','rb');local data
 if f then local ok,r=pcall(J.decode,f:read('*a'));f:close();if ok and os.time()-(r.unix or 0)<3 then data=r end end
 local wanted={}
 for _,d in ipairs(data and data.items or{})do
  local key=tostring(d.id);wanted[key]=true;local entry=M.items[key]
  if not entry then
   local h=invoke(0,nil,d.x,d.y,d.z,{-0.15,0.1,-0.15,0.15,0.4,0.15},d.item)
   local actor;for _,a in ipairs(FindAllOf('StaticMeshActor')or{})do if live(a)and a:GetAddress()==h then actor=a;break end end
   assert(live(actor),'Dropped item actor unavailable');actor:SetActorEnableCollision(false)
   entry={handle=h,actor=actor,item=d.item};M.items[key]=entry
  end
  entry.actor:K2_SetActorLocation({X=O.X+d.x*100,Y=O.Y-d.z*100,Z=O.Z+(d.y-64+.3)*100},false,{},true)
  entry.actor:K2_SetActorRotation({Pitch=0,Yaw=(os.clock()*60)%360,Roll=0},false)
 end
 for k,v in pairs(M.items)do if not wanted[k]then if live(v.actor)then v.actor:K2_DestroyActor()end;M.items[k]=nil end end
end
function M.status()
 local n,shapes,drops,model_count=0,0,0,0;local types,unconverted={},{};for _ in pairs(M.items)do drops=drops+1 end
 for _,a in pairs(M.actors)do n=n+1;shapes=shapes+#a.handles;types[a.id]=(types[a.id]or 0)+1;if a.model then model_count=model_count+1 elseif client and a.visible~=false then unconverted[a.id]=a.model_status or'basic_mesh'end end
 return {running=M.running,error=M.error,blocks=n,shapes=shapes,models=model_count,unconverted=unconverted,drops=drops,types=types,pending=queued_count(),changes=M.changes,offset=M.offset,side=client and'client'or'server',render=client and'native_unreal_mesh'or'collision',version=9,model_renderer=models and models.status(),world_state=M.world:status(),world_error=M.world_error,pending_view=M.pending_view,observer_error=M.observer_error,chunk_consumer_error=M.chunk_consumer_error,chunk_consumer=M.chunk_consumer and M.chunk_consumer.status and M.chunk_consumer.status(),visual_pipeline=visual_pipeline and visual_pipeline.status(),origin=O}
end
M.status_json=function()return J.encode(M.status())end
function M.stop(context_alive)
 if context_alive==false or(client and not M.context_alive())then M.abandon();return M.status()end
 M.running=false
 -- Shared Models.reset must run last: text/entities and legacy block models
 -- still own lifetime records while their explicit cleanup is in progress.
 if visual_pipeline then visual_pipeline.stop()end
 for _,drop in pairs(M.items)do if live(drop.actor)then drop.actor:K2_DestroyActor()end end
 M.items={}
 for k,entry in pairs(M.actors)do
  local retired=M.retire_legacy(nil,{k},'both')
  assert(retired.ok,'Legacy stop cleanup failed: '..J.encode(retired.errors))
 end
 if M.chunk_consumer then M.chunk_consumer.stop(true);M.chunk_consumer=nil end
 return M.status()
end
function M.abandon()
 if visual_pipeline then visual_pipeline.stop(false)end
 if M.chunk_consumer then M.chunk_consumer.stop(false);M.chunk_consumer=nil end
 if models and models.abandon_models then models.abandon_models()end
 M.running=false;M.actors={};M.items={};M.queue={};M.queued={};M.queue_head=1;M.pending=''
 M.ingesting_row=nil;M.pending_view=nil;M.world_observer=nil;M.abandoned=true
 bound_context=nil;bound_context_address=nil;bound_world_address=nil
end
local tick
tick=function()
 if not M.running then return end
 local ok,e=pcall(function()
  if client and bound_context and not M.context_alive()then M.abandon();return end
  if client and not bound_context then
   bound_context=context();bound_context_address=bound_context:GetAddress()
   local ok,world=pcall(function()return bound_context:GetWorld()end)
   if ok and world and world:IsValid()then bound_world_address=world:GetAddress()end
  end
  if client and models and not M.visual_pipeline_checked then
   M.visual_pipeline_checked=true
   local f=io.open(SHARED..'native-visual-settings.json','rb')
   if f then
    local config=J.decode(f:read('*a'));f:close()
    if config.enabled==true and config.version==1 then
     visual_pipeline=dofile(dir..'native_visual_pipeline.lua').new({models=models,json=J,bridge_root=SHARED,origin=O,context=context,companion=M})
     M.visual_pipeline=visual_pipeline;_G.PalCraftNativeEntityRenderer=visual_pipeline.entity_renderer
    end
   end
  end
  if not M.cleaned then
   M.cleaned=true;local owner=context():GetAddress()
   for _,a in ipairs(FindAllOf(client and 'StaticMeshActor'or'TriggerBox')or{})do
    if live(a)then
     local o=a:GetOwner();local p=a:K2_GetActorLocation()
     if live(o)and o:GetAddress()==owner and math.abs(p.X-O.X)<6400 and math.abs(p.Y-O.Y)<6400 then invoke(1,a:GetAddress(),0,64,0)end
    end
   end
  end
  local f=io.open(EVENT_PATH,'rb')
  if f then f:seek('set',M.offset);M.pending=M.pending..(f:read(262144)or'');M.offset=f:seek();f:close()end
  while true do
   local last=M.pending:find('\n',1,true);if not last then break end
   local line=M.pending:sub(1,last-1);M.pending=M.pending:sub(last+1)
   if #line>0 then local row=J.decode(line)
    if row.t=='blocks'then
     M.ingesting_row=row
     local accepted,reason=M.world:ingest(row)
     M.ingesting_row=nil
     if not accepted then M.world_error={reason=reason}end
     if M.chunk_consumer then
      local routed,why=M.chunk_consumer.on_row(row,accepted,reason)
      if routed==false then M.chunk_consumer_error=why end
     end
     observe('on_row',row,accepted,reason,M)
    elseif client and row.t=='material_tint'and visual_pipeline and visual_pipeline.material_runtime then
     -- This is the SAME authenticated native event journal and reader.
     local accepted,reason=visual_pipeline.accept_material_tint(row)
     M.material_reply_status={request_id=row.request_id,accepted=accepted,reason=reason}
    elseif client and(row.t=='entity_visual_asset'or row.t=='entity_visual_cache'or row.t=='entity_visual_cache_chunk')then
     -- Reuse the sole authenticated journal; capture rows never enter the world reducer.
     if visual_pipeline then
      local accepted,reason=visual_pipeline.receive_capture(row)
      M.capture_reply_status={t=row.t,accepted=accepted,reason=reason}
     end
    end
   end
  end
  M.item_tick=(M.item_tick or 0)+1;if client and M.item_tick%4==0 then update_items()end
  for _=1,math.min(4,queued_count())do
   local q=M.queue[M.queue_head];M.queue[M.queue_head]=false;M.queue_head=M.queue_head+1
   M.queued[key(q[2],q[3],q[4])]=nil
   if not M.chunk_consumer or M.chunk_consumer.filter_legacy(q[1],q[2],q[3],q[4],q[5])~=false then apply(table.unpack(q))end
  end
  if M.queue_head>#M.queue then M.queue={};M.queue_head=1 end
  if M.chunk_consumer then M.chunk_consumer.tick()end
  if visual_pipeline then
   local time=StaticFindObject('/Script/Engine.Default__GameplayStatics')
   visual_pipeline.tick(time:GetWorldDeltaSeconds(context()),time:GetTimeSeconds(context()))
  end
  observe('tick',M)
 end)
 if not ok then M.error=tostring(e);M.running=false end
 write('palcraft-collision-status.json',M.status())
 if M.running then ExecuteInGameThreadWithDelay(50,tick)end
end
ExecuteInGameThreadWithDelay(500,tick)
return M
