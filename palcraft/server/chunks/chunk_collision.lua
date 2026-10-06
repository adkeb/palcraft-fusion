-- PALCCOL1 bridge, initialized explicitly by the companion's game-thread adapter.
-- No engine lookup or request write occurs when this module is loaded.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local G=dofile(dir..'chunk_geometry.lua')
local M={version=1}
local paths={
 '/Script/Engine.Default__GameplayStatics','/Script/Engine.Actor',
 '/Script/Engine.GameplayStatics:BeginDeferredActorSpawnFromClass','/Script/Engine.GameplayStatics:FinishSpawningActor',
 '/Script/Engine.SceneComponent','/Script/Engine.BoxComponent','/Script/Engine.Actor:AddComponentByClass',
 '/Script/Engine.Actor:FinishAddComponent','/Script/Engine.BoxComponent:SetBoxExtent',
 '/Script/Engine.PrimitiveComponent:SetCollisionEnabled','/Script/Engine.PrimitiveComponent:SetCollisionResponseToAllChannels',
 '/Script/Engine.PrimitiveComponent:SetCollisionResponseToChannel','/Script/Engine.PrimitiveComponent:SetGenerateOverlapEvents',
 '/Script/Engine.SceneComponent:SetMobility','/Script/Engine.Actor:SetActorHiddenInGame',
 '/Script/Engine.Actor:K2_SetActorLocation','/Script/Engine.Actor:K2_DestroyActor'}
M.function_paths=paths
local function address(ctx)return type(ctx)=='number'and ctx or ctx:GetAddress()end
function M.encode(pointers,origin,revision,generation,action,boxes,fresh,old)
 assert(#pointers==19,'PALCCOL1 requires context,17 reflected objects/functions,ProcessEvent')
 local parts={string.pack('<c8'..string.rep('I8',19),'PALCCOL1',table.unpack(pointers))}
 parts[#parts+1]=string.pack('<dddI8I8I4I4I4I4',origin[1],origin[2],origin[3],revision,generation,action,#boxes,#fresh,#old)
 for _,b in ipairs(boxes)do parts[#parts+1]=string.pack('<dddddd',table.unpack(b))end
 for _,list in ipairs({fresh,old})do for _,h in ipairs(list)do
  parts[#parts+1]=string.pack('<I8I4I4',h.actor,#h.components,0)
  for _,p in ipairs(h.components)do parts[#parts+1]=string.pack('<I8',p)end
 end end
 return table.concat(parts)
end
function M.new(options)
 assert(options and options.json and options.root,'JSON and bridge root required')
 -- Native DLL state outlives Lua adapter objects and MC sessions. Keep its wire
 -- epoch separate from renderer generation and remember it across factory reloads.
 local lifetimes=_G.PalCraftChunkCollisionLifetimes or{};_G.PalCraftChunkCollisionLifetimes=lifetimes
 local lifetime_key=((options.dll_path or'injected-native')..'|'..options.root):gsub('\\','/'):lower()
 local lifetime=lifetimes[lifetime_key]
 if not lifetime then lifetime={epoch=options.native_epoch or options.generation or 1};lifetimes[lifetime_key]=lifetime end
 local state={generation=options.generation or 1,native_epoch=lifetime.epoch,handles={},needs_abandon=false};local A={version=2}
 local function setup()
  if state.functions then return end
  state.functions={}
  for _,path in ipairs(paths)do
   if options.resolve_address then state.functions[#state.functions+1]=assert(options.resolve_address(path))
   else local o=StaticFindObject(path);assert(o and o:IsValid(),path);state.functions[#state.functions+1]=o:GetAddress()end
  end
  state.process_event=options.process_event
  if not state.process_event then
   for line in io.lines(options.log_path or(dir..'../../../UE4SS.log'))do
    local a=line:match('ProcessEvent address (0x%x+)');if a then state.process_event=tonumber(a)end
   end
  end
  assert(state.process_event,'ProcessEvent unavailable')
  state.native=options.native or assert(package.loadlib(assert(options.dll_path,'Chunk collision DLL path required'),'palcraft_chunk_collision'))
 end
 local function request(action,ctx,origin,revision,boxes,fresh,old)
  setup();local pointers={ctx};for _,p in ipairs(state.functions)do pointers[#pointers+1]=p end;pointers[#pointers+1]=state.process_event
  local bytes=M.encode(pointers,origin or{0,0,0},revision or 0,state.native_epoch,action,boxes or{},fresh or{},old or{})
  local pending=options.root..'chunk-collision-request.pending';local path=options.root..'chunk-collision-request.bin'
  local f=assert(io.open(pending,'wb'));assert(f:write(bytes));assert(f:close());os.remove(path);assert(os.rename(pending,path))
  os.remove(options.root..'chunk-collision-result.json');state.native();f=assert(io.open(options.root..'chunk-collision-result.json','rb'))
  local raw=f:read('*a');f:close();local result=options.json.decode(raw)
  assert(result.ok,'Chunk collision: '..tostring(result.stage))
  assert(result.generation==state.native_epoch,'Chunk collision wire epoch mismatch')
  lifetime.epoch=state.native_epoch;lifetime.context=ctx
  if action==3 then lifetime.abandoned=true else lifetime.abandoned=false end
  return result
 end
 local function list_check(list)
  for _,h in ipairs(list or{})do assert(h.generation==state.generation and h.native_epoch==state.native_epoch and state.handles[h.actor]==h,'Stale/unknown chunk collision handle')end
 end
 function A.rebind_context(ctx,next_epoch,old_world_gone)
  assert(old_world_gone==true,'Rebinding requires a confirmed ended UWorld; live floors must not be abandoned')
  ctx=address(ctx);setup()
  local epoch=next_epoch or(math.max(state.native_epoch,lifetime.epoch)+1)
  assert(math.tointeger(epoch)and epoch>math.max(state.native_epoch,lifetime.epoch),'Native context epoch must increase')
  local prior_epoch=state.native_epoch;state.native_epoch=epoch
  local ok,result=pcall(request,3,ctx)
  if not ok then state.native_epoch=prior_epoch;error(result)end
  state.handles={};state.context=ctx;state.needs_abandon=false;lifetime.abandoned=false
  -- This action changes bookkeeping only. No old UObject is dereferenced.
  return result
 end
 function A.prepare(ctx,origin,payload)
  ctx=address(ctx);setup()
  if state.needs_abandon or lifetime.abandoned then A.rebind_context(ctx,nil,true)end
  if lifetime.context and lifetime.context~=ctx then
   assert(options.old_world_gone==true,'Native UWorld changed: confirmed rebind_context is required')
   A.rebind_context(ctx,nil,true)
  end
  if state.context then assert(state.context==ctx,'World changed: call collision.reset before prepare')end
  state.context=ctx
  local at=assert(payload.at);local boxes={};assert(#payload.boxes<=1024,'Native collider page limit')
  for _,r in ipairs(payload.boxes)do
   local p=r.properties or{}
   assert(G.stable(p.policy or G.collision_policy)==G.stable(G.collision_policy),'Unsupported collision channel policy')
   assert(p.material==nil and p.friction==nil and p.fluid_contact==nil,'Unsupported physics properties require dedicated collider adapter')
   boxes[#boxes+1]=assert(r.cm,'Exact cm collision AABB required')
  end
  local world={origin.X+at[1]*100,origin.Y-at[3]*100,origin.Z+(at[2]-(origin.y_origin or options.y_origin or 64))*100}
  local r=request(0,ctx,world,payload.revision,boxes)
  assert(r.revision==payload.revision,'Collision response revision mismatch')
  local h={actor=assert(tonumber(r.actor)),components={},revision=r.revision,generation=state.generation,native_epoch=state.native_epoch,context=ctx,
   fence=G.clone(payload.fence),native_registered=true,state='prepared'}
  for _,p in ipairs(r.components or{})do h.components[#h.components+1]=assert(tonumber(p))end
  assert(#h.components==#boxes,'Collision component count mismatch');state.handles[h.actor]=h;return h
 end
 function A.preflight(fresh,old,expected_fence)
  fresh,old=fresh or{},old or{};list_check(fresh);list_check(old)
  local revision=fresh[1]and fresh[1].revision or 0
  local fence=expected_fence or(fresh[1]and fresh[1].fence)
  for _,h in ipairs(fresh)do
   assert(h.revision==revision and h.state=='prepared','Mixed/stale collider revisions')
   assert(G.stable(h.fence)==G.stable(fence),'Mixed collider world/view fence')
  end
  return request(4,assert(state.context),nil,revision,nil,fresh,old)
 end
 function A.commit(fresh,old,expected_fence)
  fresh,old=fresh or{},old or{};list_check(fresh);list_check(old)
  local revision=fresh[1]and fresh[1].revision or 0
  local fence=expected_fence or(fresh[1]and fresh[1].fence)
  for _,h in ipairs(fresh)do assert(h.revision==revision and h.state=='prepared'and G.stable(h.fence)==G.stable(fence),'Mixed/stale collider fence')end
  request(1,assert(state.context),nil,revision,nil,fresh,old)
  for _,h in ipairs(old)do state.handles[h.actor]=nil;h.state='released'end
  for _,h in ipairs(fresh)do h.state='active'end
  return fresh
 end
 function A.unload(handles)
  if handles and handles.actor then handles={handles}end
  handles=handles or{};if #handles==0 then return end
  list_check(handles);request(2,assert(state.context),nil,0,nil,nil,handles)
  for _,h in ipairs(handles)do state.handles[h.actor]=nil;h.state='released'end
 end
 A.discard=A.unload
 function A.reset(generation,context_alive)
  assert(generation>state.generation,'Collision generation must increase')
  if context_alive then local all={};for _,h in pairs(state.handles)do all[#all+1]=h end;A.unload(all)end
  if state.context then
   -- Eagerly forget the old context even if this adapter is about to be discarded.
   -- Use its captured integer address; action3 never invokes an old UObject.
   A.rebind_context(state.context,nil,true)
   lifetime.abandoned=true -- This was the ended context, not the next live UWorld.
  end
  state.handles={};state.context=nil;state.generation=generation;state.needs_abandon=true;state.functions=nil
 end
 function A.status()local n=0;for _ in pairs(state.handles)do n=n+1 end;return{version=2,generation=state.generation,native_epoch=state.native_epoch,
  context=state.context,bookkeeping_context=lifetime.context,abandoned=lifetime.abandoned==true,retained_actors=n}end
 return A
end
return M
