-- Real companion-to-chunk handoff. The existing companion owns the only journal
-- reader/reducer/timer. This module routes accepted rows and retires old handles
-- only after replacement native resources have committed on that same game thread.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local G=dofile(dir..'chunk_geometry.lua')
local M={version=1};local Bridge={};Bridge.__index=Bridge
local function at_key(at)return('%d:%d:%d'):format(at[1],at[2],at[3])end
local function block_key(dim,at)return #dim..':'..dim..':'..at_key(at)end
local function inside(at,b)return at[1]>=b[1]and at[2]>=b[2]and at[3]>=b[3]and at[1]<b[4]and at[2]<b[5]and at[3]<b[6]end
local function section_key(dim,at,size)
 return block_key(dim,{math.floor(at[1]/size)*size,math.floor(at[2]/size)*size,math.floor(at[3]/size)*size})
end
local function entry_at(k,e)
 if e.at then return e.at end
 local x,y,z=tostring(k):match('^(-?%d+):(-?%d+):(-?%d+)$')
 return x and{tonumber(x),tonumber(y),tonumber(z)}or nil
end
local function present(v)return v~=nil and v~=false and not G.is_null(v)end
local function sign_body(g)return type(g.id)=='string'and g.id:match('_sign$')~=nil end
local function same_origin(a,b)
 if not a or not b then return false end
 for _,k in ipairs({'X','Y','Z'})do if type(a[k])~='number'or type(b[k])~='number'or math.abs(a[k]-b[k])>1e-6 then return false end end
 return(a.y_origin or 64)==(b.y_origin or 64)
end
local function model_list(handles)
 local out={};for _,h in ipairs(handles.visual or{})do out[#out+1]=h end
 for _,h in ipairs(handles.special or{})do assert(h.kind=='dynamic'and h.native,'Non-model special requires explicit transaction adapter');out[#out+1]=h.native end
 return out
end
function M.new(o)
 assert(o and o.companion and o.views and o.geometry and o.models and o.json,'Companion/views/geometry/models/JSON required')
 local c=o.companion
 assert(c.world and type(c.world.ingest)=='function'and c.actors,'Existing authoritative companion reducer required')
 assert(type(c.install_consumer)=='function'and type(c.retire_legacy)=='function','Native companion handoff hooks required')
 assert(o.views.adapter and o.views.regions,'Existing per-ticket chunk_views facade required')
 assert(next(o.views.regions)==nil,'Install bridge before preparing region tickets')
 local self=setmetatable({options=o,companion=c,world=c.world,views=o.views,geometry=o.geometry,models=o.models,json=o.json,
  size=o.chunk_size or 16,installed=false,legacy_dimension=c.world.dimension or'minecraft:overworld',legacy_origin=G.clone(c.origin),
  bootstrap={},retirements={},scenes={},region_mappings={},block_events={},latest={},class_cache={},error=nil,
  stats={rows=0,legacy_suppressed=0,commits=0,retired_sections=0,retirement_retries=0,seeded_blocks=0}},Bridge)
 self.render_signature=assert(o.render_signature or c.render_signature,'Companion-owned render signature encoder required')
 self:_attach_adapter()
 local binding={version=1,bridge=self}
 binding.filter_legacy=function(kind,x,y,z,g)return self:filter_legacy(kind,{x,y,z},g)end
 binding.on_row=function(row,accepted,reason)return self:on_row(row,accepted,reason)end
 binding.tick=function()return self:tick()end
 binding.stop=function(alive)return self:stop(alive)end
 binding.block_render_entry=function(dim,at)return self:block_render_entry(dim,at)end
 binding.status=function()return self:status()end
 binding.retry_material_block=function(block)
  local n=0;local at={block.x,block.y,block.z}
  for _,region in pairs(self.views.regions)do
   local b=region.window
   if not region.retiring and region.dim==block.dim and at[1]>=b[1]and at[1]<b[4]
    and at[2]>=b[2]and at[2]<b[5]and at[3]>=b[3]and at[3]<b[6]
    and region.scheduler:invalidate_material(block.dim,at)then n=n+1 end
  end
  return n>0
 end
 self.binding=binding;return self
end
-- Complete executable factory for the runtime owner. No external fake installer
-- is required: it invokes the actual companion.install_consumer binding.
function M.compose(o)
 assert(o and o.companion and o.models and o.json and o.context,'Runtime companion/models/JSON/context required')
 for _,name in ipairs({'prepare','commit_transaction','discard','unload'})do assert(type(o.models[name])=='function','Actual native Models.'..name..' required')end
 local geometry=o.geometry
 if not geometry then
  geometry=dofile(dir..'model_geometry_v'..(o.geometry_version or 2)..'.lua')
  geometry.configure({json=o.json,root=assert(o.asset_root,'Frozen model assets required')})
 end
 local collision=o.collision or dofile(dir..'chunk_collision.lua').new({json=o.json,root=assert(o.root),dll_path=assert(o.collision_dll),
  process_event=o.process_event,log_path=o.log_path,resolve_address=o.resolve_address,native=o.native_collision})
 local adapter=dofile(dir..'chunk_adapter.lua').new({models=o.models,collision=collision,capabilities=o.capabilities,
  collision_verified=o.collision_verified,visual_verified=o.visual_verified,prepare_special=o.prepare_special,
  discard_special=o.discard_special,unload_special=o.unload_special,reset_special=o.reset_special})
 local Views=dofile(dir..'chunk_views.lua')
 local views=Views.new({geometry=geometry,adapter=adapter,context=o.context,session=o.world_session or o.companion.world.session,
  context_alive=o.context_alive,visuals=o.visuals~=false,view_player=o.player,max_regions=o.max_regions or 4,
  frame_budget_ms=o.frame_budget_ms or 2,frame_steps=o.frame_steps or 128,clock=o.clock})
 local options={};for k,v in pairs(o)do options[k]=v end
 options.geometry=geometry;options.views=views;options.collision=collision
 local bridge=M.new(options)
 local initial=assert(o.initial_view,'Actual initial view/mapping/bounds required')
 local initial_ticket=bridge:prepare_view(initial);bridge:install()
 local api={bridge=bridge,views=views,adapter=adapter,collision=collision,initial_ticket=initial_ticket,companion_driven=true}
 -- The original companion callback already drives work. Feature ticks inspect
 -- state instead of doubling the native frame budget or creating another timer.
 function api.tick()return bridge:status()end
 function api.status()return bridge:status()end
 function api.stop(context_alive)return bridge:stop(context_alive==true)end
 api.view={prepare_view=function(r)return bridge:prepare_view(r)end,readiness=function(t)return bridge:readiness(t)end,
  activate=function(t)return bridge:activate(t)end,release=function(t)return bridge:release(t)end,
  abandon=function(t)return bridge:release(t)end,can_recycle=function(id,f)return bridge:can_recycle(id,f)end,
  retirement_status=function(id,f)return bridge:retirement_status(id,f)end}
 return api
end
function Bridge:_attach_adapter()
 local a=self.views.adapter;local o=self.options;local models=self.models
 local old_prepare=a.prepare_special;local old_discard=a.discard;local old_unload=a.unload
 a.prepare_special=function(ctx,origin,kind,entry,packet)
  if kind~='dynamic'then
   assert(old_prepare,'Unbaked '..kind..' requires an existing verified native adapter')
   return old_prepare(ctx,origin,kind,entry,packet)
  end
  assert(type(models.prepare_block)=='function','Native Models.prepare_block clip/part binding required')
  local h=models.prepare_block(ctx,origin,entry,packet)
  local event=self.block_events[block_key(packet.dimension,entry.at)]
  if event and models.block_event then models.block_event(event)end
  return{kind='dynamic',native=h,at=G.clone(entry.at),block=entry.block,
   revision=packet.revision,generation=packet.generation,fence=G.clone(packet.fence)}
 end
 a.commit=function(fresh,old,packet)
  self:before_commit(packet);old=old or{visual={},collision={},special={}}
  local scene_plan=self:_scene_plan(fresh,packet)
  local result
  if o.commit_special_transaction then result=o.commit_special_transaction(fresh,old,packet,self)
  else
   local transaction
   if #fresh.collision+#old.collision>0 then
    a.collision_preflight(fresh.collision,old.collision,packet.fence)
    transaction={adapter=o.collision or a.collision_adapter,prepared=fresh.collision,previous=old.collision,expected_fence=packet.fence}
   end
   result=models.commit_transaction(model_list(fresh),model_list(old),transaction)
  end
  assert(result~=false,'Native chunk transaction rejected')
  -- A failed old-handle retirement cannot be reported as a failed PREPARE and
  -- cause the scheduler to discard the already committed replacement colliders.
  local published,why=pcall(self.after_commit,self,fresh,packet,scene_plan)
  if not published then self.error='postcommit scene/retirement fault: '..tostring(why)end
  return fresh
 end
 local function split(handles,discard)
  while #(handles.special or{})>0 do
   local index=#handles.special;local h=handles.special[index]
   if h.kind=='dynamic'and h.native then (discard and models.discard or models.unload)(h.native)
   else
    local action=discard and o.discard_special or o.unload_special
    assert(action,'Explicit special cleanup adapter required');action(h)
   end
   handles.special[index]=nil
  end
 end
 a.discard=function(handles)split(handles,true);return old_discard(handles)end
 a.unload=function(handles)
  local actors={};for _,h in ipairs(handles.visual or{})do actors[h.actor]=true end
  for _,h in ipairs(handles.special or{})do if h.native then actors[h.native.actor]=true end end
  split(handles,false);old_unload(handles)
  for _,scene in pairs(self.scenes)do for k,e in pairs(scene)do if actors[e.model]then scene[k]=nil end end end
 end
 local collision=o.collision or a.collision_adapter
 assert(collision and collision.preflight and collision.commit,'Real compound collision adapter required')
 a.collision_adapter=collision;a.collision_preflight=collision.preflight
end
function Bridge:install()
 assert(not self.installed,'Chunk consumer already installed')
 assert(self.views.adapter.capabilities.collision_compound==true,'Actual compound collision ABI required')
 if self.options.visuals~=false then assert(type(self.models.prepare)=='function'and type(self.models.commit_transaction)=='function','Actual native visual transaction API required')end
 assert(self.companion.install_consumer(self.binding)==true,'Companion did not switch its real consumer')
 self.installed=true;return true
end
function Bridge:_covered(dim,at)
 for _,r in pairs(self.views.regions)do if not r.retiring and r.refs>0 and r.dim==dim and inside(at,r.window)then return true end end
 return false
end
function Bridge:filter_legacy(kind,at,g)
 if not self.installed then return true end
 local dim=g and g.dim or self.world.dimension
 if not self:_covered(dim,at)then return true end
 -- Dynamic models/signs/entity skins are moved through the existing native
 -- pipeline as per-block special handles; no renderer or new timer is invented.
 self.stats.legacy_suppressed=self.stats.legacy_suppressed+1;return false
end
function Bridge:_classify(g)
 if g.dynamic then return'dynamic'end
 local signature=G.stable({id=g.id,state=g.state,properties=g.properties})
 if self.class_cache[signature]then return self.class_cache[signature]end
 local groups=self.geometry.geometry(g.id,g.state,g.at[1],g.at[2],g.at[3])
 local kind='static'
 if not groups then kind='fallback'
 elseif sign_body(g)then
  for _,group in ipairs(groups)do if present(group.animation_clip)then kind='dynamic';break end end
 else for _,group in ipairs(groups)do if present(group.part)or present(group.block_entity)or present(group.animation_clip)then kind='dynamic';break end end end
 self.class_cache[signature]=kind;return kind
end
function Bridge:_transform(row)
 if self.options.visuals==false then return row end -- Collision-only server never queries visual model assets.
 local out={};for k,v in pairs(row)do out[k]=v end
 if row.ops then
  out.ops={};for _,op in ipairs(row.ops)do
   local g={};for k,v in pairs(op)do g[k]=v end
   if op.op=='upsert'or op.op=='set'then
    local kind=self:_classify(op);if kind=='static'then
     g.chunk_visual='static'
     if sign_body(op)then g.chunk_model_lookup=true;g.chunk_rigid_model=true end
    end
   end
   out.ops[#out.ops+1]=g
  end
 end
 return out
end
function Bridge:on_row(row,accepted,reason)
 if not self.installed or row.t~='blocks'then return true end
 if accepted~=true then self.error='World reducer rejected row: '..tostring(reason);return false,self.error end
 if reason=='duplicate'or reason=='retired_session'or reason=='legacy_after_v2' then return true end
 if row.session and self.views.session and row.session~=self.views.session then
  -- Leave existing native resources visible/solid. A new binding must stage a
  -- replacement world explicitly; never erase it just because MC reattached.
  self.error='world_session_changed_requires_staged_rebind';return false,self.error
 end
 local dimension=row.dim or'minecraft:overworld'
 for _,op in ipairs(row.ops or{})do if not op.snapshot then self.latest[block_key(dimension,op.at)]=row.seq or self.world.seq end end
 for _,e in ipairs(row.lifecycle or{})do if e.op=='block_event'then
  local event={};for k,v in pairs(e)do event[k]=v end;event.dim=row.dim;event.session=row.session
  self.block_events[block_key(dimension,event.at)]=event
 end end
 local ok,why=self.views:ingest(self:_transform(row));if ok==false and why~='stale'then self.error=why;return false,why end
 self.stats.rows=self.stats.rows+1;return true
end
function Bridge:prepare_view(req)
 local ticket=self.views:prepare_view(req)
 self.region_mappings[ticket.region_id]={mapping=G.clone(ticket.mapping),dim=ticket.dim,window=G.clone(ticket.region.window)}
 ticket.region.commit_hold='companion_bootstrap'
 local world=self.world.worlds[req.dim];local list={}
 for _,g in pairs(world and world.blocks or{})do
  if inside(g.at,ticket.region.window)then list[#list+1]=g end
 end
 local receipts={}
 for _,r in pairs(self.world.committed_snapshots or{})do
  if r.committed and r.session==req.world_session and r.dim==req.dim and r.end_seq>=(self.world.last_gap_seq or 0)
   and(not r.player or not req.player or r.player==req.player)then receipts[#receipts+1]=G.clone(r)end
 end
 ticket._companion_bootstrap={session_id=req.session_id,mc_epoch=req.mc_epoch,base_seq=self.world.seq,
  total=#list,scanned=0,completed=false}
 self.bootstrap[#self.bootstrap+1]={ticket=ticket,blocks=list,index=1,base_seq=self.world.seq,receipts=receipts}
 return ticket
end
function Bridge:_seed_one()
 local job=self.bootstrap[1];if not job then return end
 if job.ticket.released or job.ticket.generation~=self.views.generation then
  table.remove(self.bootstrap,1);local pending=false
  for _,other in ipairs(self.bootstrap)do if other.ticket.region==job.ticket.region then pending=true;break end end
  if not pending then job.ticket.region.commit_hold=nil end;return
 end
 local child=job.ticket.region.scheduler;local blocks={}
 for _=1,(self.options.seed_blocks_per_tick or 32)do
  local old=job.blocks[job.index];if not old then break end;job.index=job.index+1
  local at=old.at;local seq=self.latest[block_key(job.ticket.dim,at)]or-1
  if seq<=job.base_seq then
   local current=self.world:get(job.ticket.dim,table.unpack(at))
   if current then local transformed=self:_transform({ops={current}}).ops[1];blocks[#blocks+1]=transformed end
  end
 end
 job.ticket._companion_bootstrap.scanned=job.index-1
 if #blocks>0 then child:apply_blocks(job.ticket.dim,blocks);self.stats.seeded_blocks=self.stats.seeded_blocks+#blocks end
 if job.index>#job.blocks then
  -- This is a copy of the authoritative reducer's actual committed receipts,
  -- not synthetic snapshot_end evidence invented from an empty renderer queue.
  for _,r in ipairs(job.receipts)do child.coverage[#child.coverage+1]={dim=r.dim,bounds=r.bounds,session=r.session,
   generation=child.generation,snapshot=r.snapshot,player=r.player,seq=r.end_seq,source='companion_reducer_receipt'}end
  job.ticket._companion_bootstrap.completed=true
  table.remove(self.bootstrap,1)
  local pending=false;for _,other in ipairs(self.bootstrap)do if other.ticket.region==job.ticket.region then pending=true;break end end
  if not pending then job.ticket.region.commit_hold=nil end
 end
end
function Bridge:before_commit(packet)
 assert(self.installed and not self.error,'Chunk bridge is not accepting commits')
 assert(packet.fence and packet.fence.world_session==self.world.session,'Stale authoritative world session')
 assert(packet.generation==self.views.generation,'Stale bridge renderer generation')
 local region=assert(self.views.regions[packet.region_id],'Region retired before chunk commit')
 assert(region.refs>0 and not region.retiring,'Region reference released before commit')
end
function Bridge:_legacy_keys(packet)
 local region=self.views.regions[packet.region_id]
 if not region or not same_origin(region.mapping.origin,self.legacy_origin)then return{}end
 local result={};local target=section_key(packet.dimension,packet.at,self.size)
 for k,e in pairs(self.companion.actors)do local at=entry_at(k,e);local dim=e.dim or self.legacy_dimension
  if at and dim==packet.dimension and section_key(dim,at,self.size)==target then result[#result+1]=k end
 end
 table.sort(result);return result
end
function Bridge:_retire(task)
 local ok,result=pcall(self.companion.retire_legacy,task.section,task.keys,'both')
 if not ok then task.error=tostring(result);return false end
 if not result or result.ok~=true then task.error=result and(result.error or G.stable(result.errors))or'Legacy retirement did not confirm success';return false end
 task.error=nil;self.stats.retired_sections=self.stats.retired_sections+1;return true
end
function Bridge:_scene_plan(fresh,packet)
 local plan={}
 for k,record in pairs(packet.static_model_blocks or{})do
  local native={};for page in pairs(record.pages)do native[#native+1]=assert(fresh.visual[page],'Batched sign body native page missing')end
  assert(#native>0 and record.faces>0,'Batched sign body has no contributed geometry')
  local g=assert(self.world:get(packet.dimension,table.unpack(record.at)),'Static sign block disappeared before commit')
  assert(g.id==record.id and g.state==record.state,'Static sign state changed before commit')
  plan[k]={at=record.at,dim=packet.dimension,model=native[1].actor,model_component=native[1].component,
   model_status='rendered',id=g.id,visible=g.visible~=false,render_signature=self.render_signature(g),
   signature=self.companion.geometry_signature(g),native_handle=native[1],native_handles=native,
   revision=packet.revision,batched=true,contributed_faces=record.faces}
 end
 for _,h in ipairs(fresh.special or{})do if h.kind=='dynamic'then
  -- Encode the reducer-owned value through its OWN JSON provider, not the
  -- normalized renderer copy which may have a different array/null metatable.
  local g=assert(self.world:get(packet.dimension,table.unpack(h.at)),'Dynamic block disappeared before commit')
  assert(g.id==h.block.id and g.state==h.block.state,'Dynamic block state changed before commit')
  plan[at_key(h.at)]={at=h.at,dim=packet.dimension,model=h.native.actor,model_component=h.native.component,
   model_status='rendered',id=g.id,visible=g.visible~=false,render_signature=self.render_signature(g),
   signature=self.companion.geometry_signature(g),native_handle=h.native,revision=packet.revision}
 end end
 return plan
end
function Bridge:after_commit(fresh,packet,scene_plan)
 local scene=self.scenes[packet.region_id]or{};self.scenes[packet.region_id]=scene
 -- Replace only this section's scene identities; shared static actor handles are
 -- never inserted into companion.actors, so old stop/clear cannot destroy them twice.
 local target=section_key(packet.dimension,packet.at,self.size)
 for k,e in pairs(scene)do if section_key(e.dim,e.at,self.size)==target then scene[k]=nil end end
 for k,entry in pairs(scene_plan or{})do scene[k]=entry end
 local keys=self:_legacy_keys(packet)
 if #keys>0 then
  local id=packet.region_id..':'..target
  local task={section={at=G.clone(packet.at),dim=packet.dimension,region_id=packet.region_id,fence=G.clone(packet.fence)},keys=keys}
  if self:_retire(task)then self.retirements[id]=nil else self.retirements[id]=task end
 end
 self.stats.commits=self.stats.commits+1
end
function Bridge:tick()
 if not self.installed then return end
 if self.error then return{error=self.error,pending=self.views:status().pending}end
 self:_seed_one()
 local result=self.views:tick(self.options.frame_budget_ms or 2,self.options.frame_steps or 128)
 -- A bounded cleanup retry remains on the existing companion's callback.
 for id,task in pairs(self.retirements)do
  self.stats.retirement_retries=self.stats.retirement_retries+1
  if self:_retire(task)then self.retirements[id]=nil end
  break
 end
 return result
end
function Bridge:block_render_entry(dim,at)
 local t=self.views.active_view
 if not t or t.released or t.dim~=dim then return nil end
 return(self.scenes[t.region_id]or{})[at_key(at)]
end
function Bridge:readiness(ticket)
 local proof=self.views:readiness(ticket)
 if ticket._companion_bootstrap then
  local progress=G.clone(ticket._companion_bootstrap)
  progress.ticket_id=ticket.id;progress.world_session=ticket.world_session;progress.dim=ticket.dim;progress.view=ticket.view
  progress.region_id=ticket.region_id;progress.generation=ticket.generation
  progress.session_generation=ticket.session_generation;progress.player=ticket.player;proof.companion_bootstrap=progress
 end
 if self.error then proof.errors[#proof.errors+1]=self.error end
 for _,job in ipairs(self.bootstrap)do if job.ticket==ticket then proof.snapshots_pending=proof.snapshots_pending+1;proof.errors[#proof.errors+1]='companion_bootstrap_pending'end end
 for _,task in pairs(self.retirements)do if task.section.region_id==ticket.region_id then proof.errors[#proof.errors+1]='legacy_retirement_pending: '..tostring(task.error)end end
 for _,stage in pairs(self.world.snapshots or{})do if stage.dim==ticket.dim then
  local a,b=stage.bounds,ticket.required_bounds
  if a[1]<b[4]and a[4]>b[1]and a[2]<b[5]and a[5]>b[2]and a[3]<b[6]and a[6]>b[3]then
   proof.snapshots_pending=proof.snapshots_pending+1;proof.errors[#proof.errors+1]='authoritative_snapshot_pending'
  end
 end end
 if self.world.needs_resync then proof.errors[#proof.errors+1]='authoritative_world_resync_required'end
 proof.ready=proof.ready and #proof.errors==0;return proof
end
function Bridge:activate(ticket)
 assert(self:readiness(ticket).ready,'Replacement view/legacy retirement not ready')
 self.views:activate(ticket);return true
end
function Bridge:release(ticket)return self.views:release(ticket)end
function Bridge:retirement_status(region_id,expected)
 local status=self.views:retirement_status(region_id,expected)
 if status.state=='stale_fence'then return status end
 for _,task in pairs(self.retirements)do if task.section.region_id==region_id then
  status.can_recycle=false;status.state='legacy_retirement_pending';status.errors.legacy=task.error;return status
 end end
 local recorded=self.region_mappings[region_id]
 if recorded and same_origin(recorded.mapping.origin,self.legacy_origin)then
  for k,e in pairs(self.companion.actors)do local at=entry_at(k,e)
   if at and(e.dim or self.legacy_dimension)==recorded.dim and inside(at,recorded.window)then
    status.can_recycle=false;status.state='legacy_resources_still_owned';return status
   end
  end
 end
 return status
end
function Bridge:can_recycle(region_id,expected)return self:retirement_status(region_id,expected).can_recycle end
function Bridge:stop(context_alive)
 -- Explicit companion stop, never the install/release path.
 if context_alive then
  -- The shared Models provider also owns entities/signs and surviving legacy
  -- actors. Unload only this bridge's resources, without resetting that provider.
  for _,region in pairs(self.views.regions)do region.scheduler:reset(self.views.session,false,true)end
  self.views.regions={};self.views.tickets={};self.views.active_view=nil
 else self.views:reset(self.views.session,false,false)end
 self.installed=false;self.scenes={};return true
end
function Bridge:status()
 local pending=0;for _ in pairs(self.retirements)do pending=pending+1 end
 return{version=M.version,installed=self.installed,error=self.error,bootstrap_pending=#self.bootstrap,
  legacy_retirement_pending=pending,world_session=self.world.session,views=self.views:status(),stats=G.clone(self.stats),
  interface_capabilities={compound_collision=self.views.adapter.capabilities.collision_compound,atomic_commit=true},
  acceptance={collision_verified=self.views.adapter.capabilities.collision_verified==true,
   visual_verified=self.views.adapter.capabilities.visual_verified==true}}
end
return M
