-- Shared inert fluid adapter. The existing MC reducer is the only world reader.
-- No timer, propagation, HP mutation, RPC, process start, or deployment occurs here.
local M={version=1}
local source_dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
M.policy={enabled=1,default_response=0,block_channels={14,19,25},overlaps=false,
 damage=false,simulation='minecraft',ordinary_solid_policy_unchanged=true}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function clamp(n,a,b)return math.max(a,math.min(b,n))end
local function live(a)return a and a:IsValid()end
local function address(a)return type(a)=='number'and a or a:GetAddress()end
local function copy(t)local r={};for k,v in pairs(t)do r[k]=v end;return r end
local function signature(boxes)
 local r={};for _,b in ipairs(boxes)do for i=1,6 do r[#r+1]=('%.17g;'):format(b[i])end end;return table.concat(r)
end
-- Subtract the exact authoritative waterlogged VoxelShape union, without rasterization.
local function subtract(b,s)
 local a={math.max(b[1],s[1]),math.max(b[2],s[2]),math.max(b[3],s[3]),
  math.min(b[4],s[4]),math.min(b[5],s[5]),math.min(b[6],s[6])}
 if a[1]>=a[4]or a[2]>=a[5]or a[3]>=a[6]then return{b}end
 local r={}
 local function add(x,y,z,X,Y,Z)if x<X and y<Y and z<Z then r[#r+1]={x,y,z,X,Y,Z}end end
 add(b[1],b[2],b[3],a[1],b[5],b[6]);add(a[4],b[2],b[3],b[4],b[5],b[6])
 add(a[1],b[2],b[3],a[4],a[2],b[6]);add(a[1],a[5],b[3],a[4],b[5],b[6])
 add(a[1],a[2],b[3],a[4],a[5],a[3]);add(a[1],a[2],a[6],a[4],a[5],b[6])
 return r
end
-- Shared exact clipping for both query geometry and physical body contact.
function M.fluid_boxes(v)
 local at=assert(v.at);local h=assert(v.height)
 assert(finite(h)and h>=0 and h<=1,'Exact MC fluid height required')
 if h==0 then return{}end
 local remaining={{0,0,0,1,h,1}}
 if v.waterlogged then for _,s in ipairs(v.solid_boxes or{})do
  local next_boxes={};for _,b in ipairs(remaining)do for _,part in ipairs(subtract(b,s))do next_boxes[#next_boxes+1]=part end end
  remaining=next_boxes
 end end
 local boxes={};for _,b in ipairs(remaining)do boxes[#boxes+1]={b[1]+at[1],b[2]+at[2],b[3]+at[3],b[4]+at[1],b[5]+at[2],b[6]+at[3]}end
 return boxes
end
local function merge_axis(boxes,axis)
 local others={};for i=1,6 do if i~=axis and i~=axis+3 then others[#others+1]=i end end
 table.sort(boxes,function(a,b)
  for _,i in ipairs(others)do if a[i]~=b[i]then return a[i]<b[i]end end
  return a[axis]<b[axis]
 end)
 local out={}
 for _,b in ipairs(boxes)do
  local last=out[#out];local same=last~=nil
  if same then for _,i in ipairs(others)do if last[i]~=b[i]then same=false;break end end end
  if same and b[axis]<=last[axis+3]then last[axis+3]=math.max(last[axis+3],b[axis+3])
  else out[#out+1]=copy(b)end
 end
 return out
end
function M.geometry(volumes)
 local boxes={};local waters,lavas=0,0
 for _,v in ipairs(volumes)do
  if v.kind=='water'then
   local at=assert(v.at);local h=assert(v.height)
   for i=1,3 do assert(finite(at[i]),'Finite MC water coordinates required')end
   assert(finite(h)and h>=0 and h<=1,'Exact MC contact height required')
   if h>0 then
    waters=waters+1;for _,b in ipairs(M.fluid_boxes(v))do boxes[#boxes+1]=b end
   end
  elseif v.kind=='lava'then lavas=lavas+1 end
 end
 -- Merge only identical cross-sections. This preserves every contact boundary.
 for _,axis in ipairs({1,3,2,1,3})do boxes=merge_axis(boxes,axis)end
 table.sort(boxes,function(a,b)for i=1,6 do if a[i]~=b[i]then return a[i]<b[i]end end;return false end)
 local cm={};for _,b in ipairs(boxes)do cm[#cm+1]={b[1]*100,-b[6]*100,b[2]*100,b[4]*100,-b[3]*100,b[5]*100}end
 return cm,{water_cells=waters,lava_cells=lavas,query_boxes=#cm,contact_height='vanilla_flat_entity_volume',
  visual_surface='world_owner_weighted_corners',signature=signature(cm)}
end
M.function_paths={
 '/Script/Engine.Default__GameplayStatics','/Script/Engine.Actor',
 '/Script/Engine.GameplayStatics:BeginDeferredActorSpawnFromClass','/Script/Engine.GameplayStatics:FinishSpawningActor',
 '/Script/Engine.SceneComponent','/Script/Engine.BoxComponent','/Script/Engine.Actor:AddComponentByClass',
 '/Script/Engine.Actor:FinishAddComponent','/Script/Engine.BoxComponent:SetBoxExtent',
 '/Script/Engine.PrimitiveComponent:SetCollisionEnabled','/Script/Engine.PrimitiveComponent:SetCollisionResponseToAllChannels',
 '/Script/Engine.PrimitiveComponent:SetCollisionResponseToChannel','/Script/Engine.PrimitiveComponent:SetGenerateOverlapEvents',
 '/Script/Engine.SceneComponent:SetMobility','/Script/Engine.Actor:SetActorHiddenInGame',
 '/Script/Engine.Actor:K2_SetActorLocation','/Script/Engine.Actor:K2_DestroyActor'}
function M.encode(pointers,origin,revision,generation,action,boxes,fresh,old)
 assert(#pointers==19,'PALFLD01 requires context,17 reflected pointers,ProcessEvent')
 boxes,fresh,old=boxes or{},fresh or{},old or{}
 assert(#boxes<=512 and #fresh<=128 and #old<=128,'Fluid native batch limits')
 local out={string.pack('<c8'..string.rep('I8',19),'PALFLD01',table.unpack(pointers)),
  string.pack('<dddI8I8I4I4I4I4',origin[1],origin[2],origin[3],revision,generation,action,#boxes,#fresh,#old)}
 for _,b in ipairs(boxes)do out[#out+1]=string.pack('<dddddd',table.unpack(b))end
 for _,list in ipairs({fresh,old})do for _,h in ipairs(list)do
  out[#out+1]=string.pack('<I8I4I4',h.actor,#h.components,0)
  for _,c in ipairs(h.components)do out[#out+1]=string.pack('<I8',c)end
 end end
 return table.concat(out)
end
local Native={};M.Native=Native
function Native.new(o)
 assert(o.json and o.root and o.dll_path,'Fluid JSON/root/DLL configuration required')
 local generation=math.max(math.floor(os.time()*1000),(_G.PalCraftFluidNativeGeneration or 0)+1)
 local s={generation=o.generation or generation,handles={},abandon=true}
 _G.PalCraftFluidNativeGeneration=s.generation
 local root=o.root:gsub('\\','/'):gsub('/?$','/')
 local A={}
 local function setup()
  if s.functions then return end
  s.functions={}
  for _,p in ipairs(M.function_paths)do
   if o.resolve_address then s.functions[#s.functions+1]=assert(o.resolve_address(p))
   else local f=StaticFindObject(p);assert(live(f),'Missing fluid reflection: '..p);s.functions[#s.functions+1]=f:GetAddress()end
  end
  s.process_event=o.process_event
  if not s.process_event then for line in io.lines(assert(o.log_path,'Current UE4SS log path required'))do
   local p=line:match('ProcessEvent address (0x%x+)');if p then s.process_event=tonumber(p)end
  end end
  assert(s.process_event,'Current ProcessEvent address unavailable')
  s.call=o.native_call or assert(package.loadlib(o.dll_path,'palcraft_fluid_physics_batch'))
 end
 local function request(action,ctx,origin,revision,boxes,fresh,old)
  setup();local pointers={address(ctx)};for _,p in ipairs(s.functions)do pointers[#pointers+1]=p end;pointers[#pointers+1]=s.process_event
  local bytes=M.encode(pointers,origin or{0,0,0},revision or 0,s.generation,action,boxes,fresh,old)
  local tmp=root..'fluid-physics-request.pending';local path=root..'fluid-physics-request.bin'
  local f=assert(io.open(tmp,'wb'));assert(f:write(bytes));f:close();os.remove(path);assert(os.rename(tmp,path))
  -- Never reuse a previous result when the DLL refuses an executable/root.
  os.remove(root..'fluid-physics-result.json');s.call()
  f=assert(io.open(root..'fluid-physics-result.json','rb'),'Fluid DLL produced no receipt');local raw=f:read('*a');f:close()
  local r=o.json.decode(raw);assert(r.ok,'Fluid native '..tostring(r.stage))
  assert(r.generation==s.generation and r.revision==(revision or 0),'Stale fluid native receipt');return r
 end
 function A:replace(ctx,origin,revision,boxes)
  if s.context then assert(s.context==address(ctx),'Fluid UE world changed: reset required')end
  if s.abandon then request(3,ctx);s.abandon=false end
  s.context=address(ctx);s.context_object=ctx;local fresh={}
  local ok,err=pcall(function()
   for first=1,#boxes,512 do
    local page={};for i=first,math.min(first+511,#boxes)do page[#page+1]=boxes[i]end
    local r=request(0,ctx,origin,revision,page);local h={actor=assert(tonumber(r.actor)),components={}}
    for _,c in ipairs(r.components or{})do h.components[#h.components+1]=assert(tonumber(c))end
    assert(#h.components==#page,'Fluid component count mismatch');fresh[#fresh+1]=h
   end
   request(4,ctx,nil,revision,nil,fresh,s.handles);request(1,ctx,nil,revision,nil,fresh,s.handles)
  end)
  if not ok then
   if #fresh>0 then local released=pcall(request,2,ctx,nil,0,nil,nil,fresh);assert(released,'Fluid prepare rollback failed: '..tostring(err))end
   error(err)
  end
  s.handles=fresh;s.boxes=#boxes;s.commits=(s.commits or 0)+1;return true
 end
 function A:reset(context_alive)
  if context_alive and s.context and #s.handles>0 then request(2,s.context_object,nil,0,nil,nil,s.handles)end
  s.handles={};s.boxes=0;s.context=nil;s.context_object=nil;s.generation=s.generation+1
  _G.PalCraftFluidNativeGeneration=math.max(_G.PalCraftFluidNativeGeneration,s.generation)
  s.abandon=s.functions~=nil;s.functions=nil
 end
 function A:status()return{generation=s.generation,actors=#s.handles,boxes=s.boxes or 0,commits=s.commits or 0,
  collision=1,damage=false,water_channels={14,19,25}}end
 function A:inspect_handles()
  local handles={};for _,h in ipairs(s.handles)do handles[#handles+1]={actor=h.actor,components=copy(h.components)}end
  return handles
 end
 return A
end
-- Only functions/properties actually present in this lab's ObjectDump are used.
local Engine={};M.Engine=Engine
function Engine.new(o)
 local E={}
 function E:attach(p)
  assert(live(p.actor),'Live fluid participant required')
  if o.side=='server'then assert(p.actor:HasAuthority(),'Fluid physics requires Pal server authority')end
  local m=p.actor.CharacterMovement;assert(live(m),'Pal character movement required')
  assert(m:IsA('/Script/Pal.PalCharacterMovementComponent'),'Supported Pal movement component required')
  return{actor=p.actor,movement=m,original={gravity=m.GravityScale,water_z=m.WaterPlaneZ,
   water_z_prev=m.WaterPlaneZPrev,water_rate=m.InWaterRate},wet=false,swimming=false,
   mode=nil,custom=nil,requested=false,observed_ticks=0}
 end
 function E:pose(p)
  if p.shape=='aabb'then
   local b=assert(p.bounds,'Authoritative MC body AABB required');local h=b[5]-b[2]
   return{dim=p.dim,shape='aabb',bounds=b,feet=p.feet or{(b[1]+b[4])*.5,b[2],(b[3]+b[6])*.5},height=h,eye_height=p.eye_height or h*.9}
  end
  local a=p.actor;local c=a.CapsuleComponent
  assert(live(c),'Fluid capsule required');local half=c:GetScaledCapsuleHalfHeight()
  local radius=p.radius or c:GetScaledCapsuleRadius()*.01;local height=p.height or half*.02
  local O=o.origin;local base=O.y_origin or o.y_origin or 64
  local feet=p.feet
  if not feet then local pos=c:K2_GetComponentLocation()
   feet={(pos.X-O.X)/100,base+(pos.Z-half-O.Z)/100,-(pos.Y-O.Y)/100}
  end
  return{dim=p.dim,shape='capsule',feet=feet,radius=radius,height=height,eye_height=p.eye_height or height*.9}
 end
 function E:apply(s,p,contact,pose,dt)
  local m=s.movement;assert(live(m),'Fluid movement became invalid')
  local water=contact.kind=='water'and contact.wet
  local surface_known=water and contact.surface_known==true and finite(contact.surface)
  local rate=surface_known and clamp(contact.immersion or((contact.surface-pose.feet[2])/pose.height),0,1)or 0
  -- A real one-block source can lie just below the centre of a 1.8m capsule.
  local mode=m.MovementMode
  local swim=water and(contact.swimming or rate>=(o.swim_fraction or .45))and not p.passive
   and(mode==1 or mode==2 or mode==3 or mode==4)
  local before=m:IsSwimming();if swim and before then s.observed_ticks=s.observed_ticks+1 end
  if water and not s.wet then
   s.original={gravity=m.GravityScale,water_z=m.WaterPlaneZ,water_z_prev=m.WaterPlaneZPrev,water_rate=m.InWaterRate}
   s.gravity_acceleration=math.abs(m:GetGravityZ())
  end
  if swim and not s.swimming then s.mode=mode;s.custom=m.CustomMovementMode end
  if water then
   if surface_known then
    local z=o.origin.Z+(contact.surface-(o.origin.y_origin or o.y_origin or 64))*100
    m.WaterPlaneZPrev=m.WaterPlaneZ;m.WaterPlaneZ=z;m.InWaterRate=rate
   end
   if not s.wet then m:OnEnterWater()end
  elseif s.wet then m:OnExitWater()end
  if swim then
   m:SetMovementMode(4,0) -- EMovementMode::MOVE_Swimming (Flying is 5).
   if o.script_buoyancy~=false and surface_known then m.GravityScale=0;s.gravity_owned=true
   elseif s.gravity_owned then m.GravityScale=s.original.gravity;s.gravity_owned=false end
  elseif s.swimming then
   m.GravityScale=s.original.gravity;s.gravity_owned=false
   if m.MovementMode==4 then
    local restore=s.mode;-- Let native floor detection decide land vs fall after water exit.
    if restore==1 or restore==2 or restore==3 or restore==4 then restore=3 end
    m:SetMovementMode(restore,s.custom or 0)
   end
  end
  local impulse={X=0,Y=0,Z=0}
  if water and not p.passive and mode~=0 and dt>0 then
   local flow=contact.flow or{0,0,0};local force=(o.flow_acceleration or 560)*(contact.flow_weight or 0)
   impulse.X=(flow[1]or 0)*force*dt;impulse.Y=-(flow[3]or 0)*force*dt;impulse.Z=(flow[2]or 0)*force*dt
   if swim and o.script_buoyancy~=false and surface_known then
    local velocity=m:GetVelocity()
    -- Actual wet volume supplies buoyancy. A tiny lateral graze cannot cancel
    -- the whole body's gravity merely because its neighbouring water is deep.
    local acceleration=(s.gravity_acceleration or 0)*(rate/(o.float_fraction or .55)-1)
     -velocity.Z*(o.vertical_drag or 5)
    impulse.Z=impulse.Z+clamp(acceleration,-600,600)*dt
   end
   if impulse.X~=0 or impulse.Y~=0 or impulse.Z~=0 then m:AddImpulse(impulse,true)end
  end
  if not water and s.wet then
   m.WaterPlaneZ=s.original.water_z;m.WaterPlaneZPrev=s.original.water_z_prev;m.InWaterRate=s.original.water_rate
  end
  s.wet=water;s.swimming=swim;s.requested=swim
  return{mode=m.MovementMode,native_swimming=m:IsSwimming(),entered_water=m:IsEnteredWater(),
   water_plane=m.WaterPlaneZ,in_water_rate=m:GetInWaterRate(),pre_apply_swimming=before,
   surface_known=surface_known,surface_reason=contact.surface_reason,buoyancy_pending=water and not surface_known,
   immersed_body_fraction=rate,flow_weight=contact.flow_weight,
   script_buoyancy_applied=swim and surface_known and o.script_buoyancy~=false,
   sustained_swim_samples=s.observed_ticks,impulse=impulse,authority=o.side=='server',native_damage=false}
 end
 function E:release(s)
  if not live(s.actor)or not live(s.movement)then return false end
  if not s.wet and not s.swimming then return true end
  local m=s.movement
  if s.wet then m:OnExitWater()end
  m.GravityScale=s.original.gravity;m.WaterPlaneZ=s.original.water_z
  m.WaterPlaneZPrev=s.original.water_z_prev;m.InWaterRate=s.original.water_rate
  if s.swimming and m.MovementMode==4 then local mode=s.mode;if mode==1 or mode==2 or mode==3 or mode==4 then mode=3 end;m:SetMovementMode(mode,s.custom or 0)end
  return true
 end
 return E
end
-- Reuse actual shape proof from the entity authority without loading a DLL,
-- creating query bodies, moving the actor, or starting another damage cycle.
function M.environment_contact(o)
 assert(o and o.world and o.origin and o.contact_driver,'Existing world/origin/column driver required')
 local Shape=o.shape_contact_driver or dofile((o.shared_dir or source_dir)..'fluid_physics_contact.lua')
 local sampler=Shape.new{world=o.world,column_driver=o.contact_driver,volume_boxes=M.fluid_boxes,
  max_surface_cells=o.max_surface_cells,volume_tolerance=o.volume_tolerance}
 local engine=Engine.new{side='server',origin=o.origin,y_origin=o.y_origin}
 return function(q,target)
  local thread=o.game_thread or IsInGameThread;assert(thread and thread()==true,'Environment contact requires server game thread')
  if q.kind~='minecraft:lava'then return false,{known=false,reason='nonfluid_environment_requires_entity_proof'}end
  assert(target and live(target.actor)and target.actor:HasAuthority(),'Authoritative native lava target required')
  local dim=q.dimension or q.dim or target.dimension or o.world.dimension
  if dim~=o.world.dimension then return false,{known=false,reason='world_view_dimension_mismatch'}end
  local pose=engine:pose{actor=target.actor,dim=dim};pose.world_session=o.world.session
  local contact=sampler:sample(assert(q.target),pose)
  return contact.known==true and contact.lava==true,contact
 end,sampler
end
function M.new(o)
 assert(o and(o.side=='server'or o.side=='client'),'Explicit fluid side required')
 assert(o.world and o.world.fluid_at and o.world.fluid_volumes,'Existing MC world reducer required')
 assert(o.origin and o.contact_driver and o.contact_driver.new,'Origin and world-owner contact driver required')
 assert(type(o.resolve_participants)=='function','Fluid participant resolver required')
 local A={running=true,phase='waiting_for_tick',participants={},contacts={},observations={},ticks=0,
  samples=0,revision=0,simulation='minecraft',damage_owner='mc_hurt_to_pal_entity_authority',lava_damage_calls=0}
 local N=o.native or Native.new(o);local E=o.engine or Engine.new(o);A.native=N
 local Shape=o.shape_contact_driver or dofile((o.shared_dir or source_dir)..'fluid_physics_contact.lua')
 A.driver=Shape.new{world=o.world,column_driver=o.contact_driver,volume_boxes=M.fluid_boxes,
  require_committed=o.require_committed~=false,max_surface_cells=o.max_surface_cells,
  swim_fraction=o.swim_fraction,volume_tolerance=o.volume_tolerance,
  on_update=function(contact)A.contacts[contact.id]=contact end,
  authoritative_native_swimming_verified=false}
 local function thread()local f=o.game_thread or IsInGameThread;assert(type(f)=='function'and f()==true,'Fluid game-thread tick required')end
 local function context_alive()return A.context_object and live(A.context_object)end
 function A:remove(id,alive)
  local s=self.participants[id];if s and alive~=false then E:release(s)end
  self.driver:remove(id);self.participants[id]=nil;self.contacts[id]=nil;self.observations[id]=nil
 end
 function A:reset(reason,alive)
  thread();local ids={};for id in pairs(self.participants)do ids[#ids+1]=id end;for _,id in ipairs(ids)do self:remove(id,alive)end
  N:reset(alive==true);self.signature=nil;self.region_signature=nil;self.previous_time=nil;self.context=nil
  self.context_object=nil;self.fence=nil;self.next_query=0;self.phase=reason or'reset';return self:status()
 end
 function A:on_world(row)
  -- Called only after the one world reducer accepted the row; no ingest/read here.
  self.dirty=true;self.last_world_seq=row.seq;return true
 end
 function A:tick(ms,ctx)
  thread();assert(finite(ms),'Monotonic fluid tick milliseconds required');if not self.running then return self:status()end
  local context=o.resolve_context and o.resolve_context(ctx)or(ctx and(ctx.world_context or ctx.pc))
  assert(context and(type(context)=='number'or live(context)),'Live fluid UE world context required')
  local fence=tostring(o.world.session)..':'..tostring(o.world.dimension)..':'..tostring(o.world.view)
  if self.context and(self.context~=address(context)or self.fence~=fence)then
   self:reset('world_or_view_changed',self.context==address(context)and context_alive())
  end
  self.context=address(context);self.context_object=type(context)~='number'and context or nil;self.fence=fence
  -- A 100ms feature cadence on the 15FPS night client commonly yields 133ms.
  local dt=self.previous_time and clamp((ms-self.previous_time)/1000,0,o.max_force_dt or .2)or 0;self.previous_time=ms
  local list=o.resolve_participants(ctx)or{};local seen,regions,volumes={},{},{};local surfaces_known=true
  for _,p in ipairs(list)do
   assert(type(p.id)=='string'and type(p.dim)=='string','Fluid participant identity/dimension required')
   assert(not seen[p.id],'Duplicate fluid participant');seen[p.id]=true
   if p.dim~=o.world.dimension or not live(p.actor)then self:remove(p.id,live(p.actor))
   else
    local s=self.participants[p.id]
    if s and address(s.actor)~=address(p.actor)then self:remove(p.id);s=nil end
    if not s then s=E:attach(p);self.participants[p.id]=s end
    local pose=E:pose(p);pose.world_session=p.world_session or o.world.session
    pose.view=p.view or o.world.view;pose.player=p.mc_uuid or p.player_filter;p.pose=pose
    local contact=self.driver:sample(p.id,pose);p.contact=contact
    if contact.known~=false and contact.query_surface_known==false then surfaces_known=false end
    local f=pose.feet;local width=pose.radius or(pose.bounds and math.max(pose.bounds[4]-pose.bounds[1],pose.bounds[6]-pose.bounds[3])*.5)or 0
    local radius=math.max(math.ceil(o.query_radius or 6),math.ceil(width));local x,y,z=math.floor(f[1]/4)*4,math.floor(f[2]/4)*4,math.floor(f[3]/4)*4
    -- Never cut a proved deep water column at the old local +8 window and
    -- accidentally expose an artificial top face to Pal's native water traces.
    local top=math.max(y+8,math.ceil(f[2]+pose.height)+1)
    if contact.query_surface_known and finite(contact.query_max_surface)then top=math.max(top,math.ceil(contact.query_max_surface)+1)end
    local k=('%d:%d:%d:%d:%d'):format(x,y,z,top,radius);regions[k]={x-radius,y-4,z-radius,x+radius+4,top,z+radius+4}
   end
  end
  local removed={};for id in pairs(self.participants)do if not seen[id]then removed[#removed+1]=id end end
  for _,id in ipairs(removed)do self:remove(id)end
  local rk={};for k in pairs(regions)do rk[#rk+1]=k end;table.sort(rk);local region_signature=table.concat(rk,';')
  if region_signature~=self.region_signature then self.dirty=true end
  if o.world.seq~=self.revision then self.dirty=true end
  self.query_surface_pending=not surfaces_known;if not surfaces_known then self.dirty=true end
  if self.dirty and ms>=(self.next_query or 0)then
   self.next_query=ms+(o.query_interval_ms or 250);local cells={};local geometry_known=surfaces_known;local snapshot_known=true
   for _,k in ipairs(rk)do for _,v in ipairs(o.world:fluid_volumes(o.world.dimension,regions[k]))do
    local known=true
    if o.require_committed~=false and o.world.region_status then
     local a=v.at;known=o.world:region_status(o.world.dimension,{a[1],a[2],a[3],a[1]+1,a[2]+1,a[3]+1}).ready
    end
    if not known then geometry_known=false;snapshot_known=false end
    local c=('%d:%d:%d'):format(table.unpack(v.at));if known and not cells[c]then cells[c]=true;volumes[#volumes+1]=v end
   end end
   self.query_snapshot_pending=not snapshot_known
   if geometry_known then
    local boxes,meta=M.geometry(volumes);assert(#boxes<=(o.max_query_boxes or 4096),'Fluid query collider budget exceeded')
    if meta.signature~=self.signature then
     local O=o.origin;N:replace(context,{O.X,O.Y,O.Z-(O.y_origin or o.y_origin or 64)*100},o.world.seq or 0,boxes)
     self.signature=meta.signature
    end
    self.geometry=meta;self.revision=o.world.seq;self.region_signature=region_signature;self.dirty=false
   end
  end
  for _,p in ipairs(list)do local s=self.participants[p.id]
   if s and p.pose then
    local contact=p.contact
    if contact.known==false then
     if not self.contacts[p.id]then self.contacts[p.id]=contact end
     local previous=self.observations[p.id]or{};previous.known=false;previous.reason=contact.reason
     previous.physics_preserved=true;self.observations[p.id]=previous
    else self.observations[p.id]=E:apply(s,p,contact,p.pose,dt);self.observations[p.id].known=true end
    self.samples=self.samples+1
   end
  end
  self.ticks=self.ticks+1;self.phase='sampling_real_mc_contacts';return self:status()
 end
 function A:status()
  local ids={};local swimmers,lava=0,0
  for id,c in pairs(self.contacts)do local observation=self.observations[id];ids[#ids+1]={id=id,kind=c.kind,wet=c.wet,
   body=c.body,submerged=c.submerged,surface=c.surface,surface_known=c.surface_known,surface_reason=c.surface_reason,
   immersion=c.immersion,flow=c.flow,flow_weight=c.flow_weight,kinds=c.kinds,lava=c.lava,
   shape=c.shape,bounds=c.bounds,radius=c.radius,wet_fraction=c.wet_fraction,
   volume_error_estimate=c.volume_error_estimate,known=observation and observation.known,
   observation=observation}
   if observation and observation.native_swimming then swimmers=swimmers+1 end;if c.lava then lava=lava+1 end
  end
  table.sort(ids,function(a,b)return a.id<b.id end)
  return{version=1,running=self.running,phase=self.phase,side=o.side,ticks=self.ticks,samples=self.samples,
   world_session=o.world.session,dimension=o.world.dimension,revision=self.revision,participants=ids,
   observed_swimmers=swimmers,lava_contacts=lava,lava_damage_calls=0,query_snapshot_pending=self.query_snapshot_pending,
   query_surface_pending=self.query_surface_pending,
   damage_owner=self.damage_owner,simulation='minecraft',native=N:status(),
   geometry=self.geometry and{water_cells=self.geometry.water_cells,lava_cells=self.geometry.lava_cells,query_boxes=self.geometry.query_boxes},
   buoyancy=o.script_buoyancy~=false and'sampled_surface_controller'or'pal_native',
   contact_sampling='physical_capsule_or_aabb',shape_overlap='analytic_positive_volume',
   body_fraction='actual_clipped_volume',full_body_contact_runtime_verified=false,
   authoritative_native_swimming_verified=false,short_lab_experiment_pending=true}
 end
 function A:stop(reason,ctx)
  local alive=ctx and ctx.context_alive;if alive==nil then alive=context_alive()end
  self:reset(reason or'stopped',alive);self.running=false;return self:status()
 end
 return A
end
return M
