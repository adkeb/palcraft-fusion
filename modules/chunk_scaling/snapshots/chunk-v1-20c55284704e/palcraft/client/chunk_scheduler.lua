-- Cooperative chunk execution, snapshot reconciliation and native transaction fencing.
-- adapter methods run only on the caller's Unreal game thread. Tests use a data adapter.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local G=dofile(dir..'chunk_geometry.lua')
local M={version=1};local Scheduler={};Scheduler.__index=Scheduler
local function key(dim,cx,cy,cz)return #dim..':'..dim..':'..cx..':'..cy..':'..cz end
local function count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
local function empty_handles()return{visual={},collision={},special={}}end
function M.new(options)
 assert(options and options.geometry and options.adapter,'Geometry and adapter required')
 local size,tile=options.chunk_size or 16,options.tile_size or 4
 assert(math.tointeger(size)and math.tointeger(tile)and size>0 and tile>0 and size%tile==0,'Integral tile must divide chunk')
 local self=setmetatable({options=options,geometry=options.geometry,adapter=options.adapter,size=size,tile=tile,
  chunks={},queue={},head=1,tail=0,snapshots={},coverage={},views={},regions={},view_counter=0,session=options.session,generation=1,last_seq=-1,
  clock=options.clock or os.clock,stats={changes=0,noops=0,stale_rows=0,cancelled_jobs=0,commits=0,
   prepared_pages=0,tiles_built=0,unloads=0,resets=0,native_calls=0,budget_overruns=0,max_tick_ms=0},errors={}},Scheduler)
 return self
end
function Scheduler:_chunk(dim,x,y,z,create)
 local cx,cy,cz=G.chunk_coords(x,y,z,self.size);local k=key(dim,cx,cy,cz);local ch=self.chunks[k]
 if not ch and create then
  ch={key=k,dimension=dim,at={cx*self.size,cy*self.size,cz*self.size},coords={cx,cy,cz},blocks={},count=0,
   dirty={},tiles={},revision=0,generation=self.generation};self.chunks[k]=ch
 end
 return ch
end
function Scheduler:get(dim,x,y,z)
 local ch=self:_chunk(dim,x,y,z);return ch and ch.blocks[G.local_index(x,y,z,self.size)]
end
function Scheduler:_enqueue(ch)
 if ch.queued then return end
 ch.queued=true;self.tail=self.tail+1;self.queue[self.tail]=ch
end
function Scheduler:_touch(dim,x,y,z,touched)
 local ch=self:_chunk(dim,x,y,z);if not ch or ch.removed then return end
 ch.dirty[G.tile_index(x,y,z,self.size,self.tile)]=true;touched[ch]=true
end
function Scheduler:_change(dim,at,block,touched)
 local x,y,z=table.unpack(at);local ch=self:_chunk(dim,x,y,z,block~=nil)
 if not ch then self.stats.noops=self.stats.noops+1;return end
 local index=G.local_index(x,y,z,self.size);local old=ch.blocks[index]
 if(old and block and old.signature==block.signature)or(not old and not block)then self.stats.noops=self.stats.noops+1;return end
 ch.removed=nil;ch.blocks[index]=block;ch.count=ch.count+(block and 1 or 0)-(old and 1 or 0)
 self:_touch(dim,x,y,z,touched)
 for _,d in pairs(G.directions)do self:_touch(dim,x+d[1],y+d[2],z+d[3],touched)end
 self.stats.changes=self.stats.changes+1
end
function Scheduler:_publish(touched)
 for ch in pairs(touched)do ch.revision=ch.revision+1;ch.error=nil;self.errors[ch.key]=nil;self:_enqueue(ch)end
end
function Scheduler:apply_blocks(dim,blocks,clears)
 dim=dim or'minecraft:overworld';assert(type(dim)=='string','Dimension string required')
 -- Validate the whole event before changing authoritative state.
 local normalized={};for i,b in ipairs(blocks or{})do normalized[i]=G.normalize(b)end
 for _,at in ipairs(clears or{})do assert(#at==3,'Clear coordinate');for _,n in ipairs(at)do assert(math.tointeger(n),'Integral clear coordinate')end end
 local touched={}
 for _,at in ipairs(clears or{})do self:_change(dim,at,nil,touched)end
 for _,b in ipairs(normalized)do self:_change(dim,b.at,b,touched)end
 self:_publish(touched);return true
end
function Scheduler:unload(dim,cx,cy,cz)
 for i=#self.coverage,1,-1 do local c=self.coverage[i];local b=c.bounds
  if c.dim==dim and b[1]<(cx+1)*self.size and b[4]>cx*self.size and b[3]<(cz+1)*self.size and b[6]>cz*self.size and(cy==nil or(b[2]<(cy+1)*self.size and b[5]>cy*self.size))then table.remove(self.coverage,i)end
 end
 local selected={}
 for _,ch in pairs(self.chunks)do if ch.dimension==dim and ch.coords[1]==cx and ch.coords[3]==cz and(cy==nil or ch.coords[2]==cy)then selected[#selected+1]=ch end end
 local touched={}
 for _,ch in ipairs(selected)do
  for _,b in pairs(ch.blocks)do for _,d in pairs(G.directions)do self:_touch(dim,b.at[1]+d[1],b.at[2]+d[2],b.at[3]+d[3],touched)end end
  ch.blocks={};ch.count=0;ch.removed=true;ch.revision=ch.revision+1;self:_enqueue(ch);touched[ch]=nil
 end
 self:_publish(touched);return true
end
function Scheduler:_discard(job)
 if job and job.prepared and(#job.prepared.visual+#job.prepared.collision+#job.prepared.special)>0 then
  self.adapter.discard(job.prepared);self.stats.native_calls=self.stats.native_calls+1
 end
end
-- Use context_alive=false after Unreal world travel: stale UObject handles are
-- abandoned through adapter.reset, never dereferenced or destroyed in the new world.
function Scheduler:reset(session,keep_world,context_alive)
 for _,ch in pairs(self.chunks)do if context_alive then
  self:_discard(ch.job);if ch.active then self.adapter.unload(ch.active)end
 end end
 if self.adapter.reset then self.adapter.reset(self.generation+1,context_alive==true)end
 self.generation=self.generation+1;self.session=session;self.last_seq=-1;self.snapshots={};self.coverage={};self.views={};self.regions={};self.active_view=nil;self.queue={};self.head=1;self.tail=0;self.errors={}
 if not keep_world then self.chunks={}
 else for _,ch in pairs(self.chunks)do
  ch.active=nil;ch.packet=nil;ch.job=nil;ch.queued=nil;ch.removed=nil;ch.error=nil;ch.tiles={};ch.dirty={}
  ch.revision=ch.revision+1;ch.generation=self.generation
  for _,b in pairs(ch.blocks)do ch.dirty[G.tile_index(b.at[1],b.at[2],b.at[3],self.size,self.tile)]=true end
  if ch.count>0 then self:_enqueue(ch)end
 end end
 self.stats.resets=self.stats.resets+1;return true
end
function Scheduler:reconnect(context_alive)return self:reset(self.session,true,context_alive)end
local function inside(at,bounds)
 return at[1]>=bounds[1]and at[2]>=bounds[2]and at[3]>=bounds[3]and at[1]<bounds[4]and at[2]<bounds[5]and at[3]<bounds[6]
end
local function bounds_ok(b)
 if type(b)~='table'or #b~=6 then return false end
 for i=1,6 do if not math.tointeger(b[i])then return false end end
 return b[1]<b[4]and b[2]<b[5]and b[3]<b[6]
end
function Scheduler:_snapshot_end(id)
 local s=assert(self.snapshots[id],'Unknown snapshot '..tostring(id));local blocks,clears={},{}
 for _,ch in pairs(self.chunks)do if ch.dimension==s.dim then for _,b in pairs(ch.blocks)do
  if inside(b.at,s.bounds)and not s.blocks[G.stable(b.at)]then clears[#clears+1]=b.at end
 end end end
 for _,b in pairs(s.blocks)do blocks[#blocks+1]=b end
 self:apply_blocks(s.dim,blocks,clears)
 self.coverage[#self.coverage+1]={dim=s.dim,bounds=s.bounds,session=self.session,generation=self.generation,snapshot=id,player=s.player,seq=self.last_seq}
 self.snapshots[id]=nil
end
local function selected(self,life)return not self.options.view_player or not life.player or life.player==self.options.view_player end
-- v2 ops and lifecycle are preferred; legacy set/clear is still accepted. A complete
-- snapshot is reconciled only at end. Deltas received while scanning are replayed last.
function Scheduler:ingest(row)
 assert(type(row)=='table','World row required')
 local new_session=row.session and self.session and row.session~=self.session
 if row.seq then
  assert(math.tointeger(row.seq),'Integral event seq required')
  if not new_session and row.seq<=self.last_seq then self.stats.stale_rows=self.stats.stale_rows+1;return false,'stale' end
 end
 local dim=row.dim or row.dimension or'minecraft:overworld'
 local ops={};local source=row.ops
 if source then
  for _,op in ipairs(source)do
   local kind=op.op or op.kind or(op.id and'set')or'clear'
   if kind=='upsert'then kind='set'end
   if kind=='remove'then kind='clear'end
   assert(kind=='set'or kind=='clear','Unknown block operation '..tostring(kind))
   assert(type(op.at)=='table'and #op.at==3,'Operation at required')
   for _,n in ipairs(op.at)do assert(math.tointeger(n),'Integral operation at')end
   local block=kind=='set'and G.normalize(op)or nil
   ops[#ops+1]={kind=kind,at=op.at,block=block,snapshot=op.snapshot}
  end
 else
  local by={};for _,b in ipairs(row.geometry or{})do by[G.stable(b.at)]=b end
  for _,kind in ipairs({'clear','set'})do local values=row[kind]or{};assert(#values%3==0,'Legacy coordinate triples')
   for i=1,#values,3 do local at={values[i],values[i+1],values[i+2]}
    for _,n in ipairs(at)do assert(math.tointeger(n),'Integral legacy at')end
    -- A set without exact geometry is explicitly incomplete; never a free cube.
    local b=kind=='set'and G.normalize(by[G.stable(at)]or{at=at,id='palcraft:unknown',state='',incomplete=true})or nil
    ops[#ops+1]={kind=kind,at=at,block=b}
   end
  end
 end
 -- Validate the complete incoming operation set before changing blocks or snapshots.
 local virtual={};if not new_session then for id,s in pairs(self.snapshots)do virtual[id]={dim=s.dim,bounds=s.bounds,blocks=s.blocks,count=s.count,changed={}}end end
 for _,life in ipairs(row.lifecycle or{})do if selected(self,life)then
  local kind=life.op or life.kind or life.t or life.event
  if kind=='snapshot_begin'then
   assert(life.snapshot and bounds_ok(life.bounds),'Snapshot id and exclusive bounds required')
   virtual[life.snapshot]={dim=life.dim or dim,bounds=life.bounds,blocks={},count=0,changed={}}
  elseif kind=='snapshot_cancel'then virtual[life.snapshot]=nil
  elseif kind=='chunk_unload'then
   assert(type(life.at)=='table'and #life.at==2 and math.tointeger(life.at[1])and math.tointeger(life.at[2]),'Integral chunk unload coordinates required')
  end
 end end
 for _,op in ipairs(ops)do if op.snapshot and virtual[op.snapshot]then
  local s=virtual[op.snapshot];assert(s.dim==dim and inside(op.at,s.bounds),'Snapshot operation outside scope')
  local k=G.stable(op.at);local existed=s.changed[k];if existed==nil then existed=s.blocks[k]~=nil end
  local exists=op.block~=nil;s.count=s.count+(exists and 1 or 0)-(existed and 1 or 0);s.changed[k]=exists
  assert(s.count<=(self.options.max_snapshot_blocks or 262144),'Snapshot capacity exceeded; request resync')
 end end
 if new_session then self:reset(row.session,false,self.options.context_alive and self.options.context_alive()or false)
 elseif row.session and not self.session then self.session=row.session end
 for _,life in ipairs(row.lifecycle or{})do if selected(self,life)then
  local kind=life.op or life.kind or life.t or life.event
  if kind=='snapshot_begin'then
   self.snapshots[life.snapshot]={dim=life.dim or dim,bounds=G.clone(life.bounds),player=life.player,blocks={},count=0,overrides={}}
  elseif kind=='snapshot_cancel'then self.snapshots[life.snapshot]=nil
  elseif kind=='chunk_unload'then self:unload(life.dim or dim,life.at[1],nil,life.at[2])
  elseif kind=='world_unload'then
   local chs={};for _,ch in pairs(self.chunks)do if ch.dimension==(life.dim or dim)then chs[#chs+1]=ch end end
   for _,ch in ipairs(chs)do self:unload(ch.dimension,ch.coords[1],ch.coords[2],ch.coords[3])end
  elseif kind=='resync_required'then
   for i=#self.coverage,1,-1 do if self.coverage[i].dim==(life.dim or dim)then table.remove(self.coverage,i)end end
  end
 end end
 local touched={}
 for _,op in ipairs(ops)do
  if op.snapshot then
   local s=self.snapshots[op.snapshot]
   if s then
    assert(s.dim==dim and inside(op.at,s.bounds),'Snapshot operation outside scope')
    local k=G.stable(op.at)
    s.count=s.count+(op.block and 1 or 0)-(s.blocks[k]and 1 or 0)
    s.blocks[k]=op.block
   end
  else
   self:_change(dim,op.at,op.block,touched)
   for _,s in pairs(self.snapshots)do if s.dim==dim and inside(op.at,s.bounds)then s.overrides[G.stable(op.at)]={block=op.block}end end
  end
 end
 self:_publish(touched)
 for _,life in ipairs(row.lifecycle or{})do if selected(self,life)and(life.op or life.kind or life.t or life.event)=='snapshot_end'and self.snapshots[life.snapshot]then
  local s=self.snapshots[life.snapshot];for k,v in pairs(s.overrides)do s.blocks[k]=v.block end
  self:_snapshot_end(life.snapshot)
 end end
 if row.seq then self.last_seq=row.seq end;return true
end
function Scheduler:_new_job(ch)
 local previous=ch.tiles;local tiles={};for k,v in pairs(previous)do tiles[k]=v end
 local revision=ch.revision;local dirty=G.sorted_keys(ch.dirty);local opts={}
 for k,v in pairs(self.options)do opts[k]=v end;opts.chunk_size=self.size;opts.tile_size=self.tile
 local job={revision=revision,generation=self.generation,prepared=empty_handles(),phase='build'}
 job.co=coroutine.create(function()
  for _,index in ipairs(dirty)do
   tiles[index]=G.build_tile(opts,ch,index,function(...)return self:get(...)end);self.stats.tiles_built=self.stats.tiles_built+1
  end
  return G.assemble(opts,ch,tiles,previous),tiles
 end);ch.job=job;return job
end
function Scheduler:_requirements(packet)
 local cap=self.adapter.capabilities or{};local r=packet.requirements
 for _,name in ipairs({'atomic_commit','fluids','dynamic','fallbacks','tint','animation','lighting'})do
  if r[name]and not cap[name]then return false,'unsupported_'..name end
 end
 if r.collision_compound and not(cap.collision_compound or cap.compound_collision)then return false,'unsupported_collision_compound'end
 for mode in pairs(r.alpha_modes)do if not(cap.alpha_modes and cap.alpha_modes[mode]or cap[mode])then return false,'unsupported_alpha_'..mode end end
 return true
end
function Scheduler:_context()return type(self.options.context)=='function'and self.options.context()or self.options.context end
function Scheduler:_origin(ch)
 ch.region_id=nil
 local found
 for _,region in pairs(self.regions)do if region.refs>0 and region.dim==ch.dimension then
  local anchor=region.mapping.mc_anchor;local radius=(region.mapping.page_size or 256)/2
  if ch.at[1]<anchor[1]+radius and ch.at[1]+self.size>anchor[1]-radius and ch.at[3]<anchor[3]+radius and ch.at[3]+self.size>anchor[3]-radius then
   assert(not found or G.stable(found.mapping.origin)==G.stable(region.mapping.origin),'Overlapping region mappings')
   found=region
  end
 end end
 if found then
  ch.region_id=found.id
  local origin=G.clone(found.mapping.origin);origin.y_origin=found.mapping.y_origin or 64;return origin
 end
 local mapped=(self.options.origins or{})[ch.dimension]
 if mapped then return mapped end
 assert(ch.dimension=='minecraft:overworld','Explicit dimension/region mapping required: '..ch.dimension)
 return self.options.origin or{X=0,Y=0,Z=0}
end
function Scheduler:_fence(ch)
 local region=ch.region_id and self.regions[ch.region_id]
 return{world_session=tostring(self.session or'legacy-journal'),dim=ch.dimension,
  view=region and region.native_view or 0,mapping=region and tostring(region.id)or('legacy-origin:'..G.stable(self:_origin(ch)))}
end
function Scheduler:_step(ch,deadline)
 local job=ch.job
 if job and(job.revision~=ch.revision or job.generation~=self.generation)then
  self:_discard(job);ch.job=nil;job=nil;self.stats.cancelled_jobs=self.stats.cancelled_jobs+1
 end
 if ch.removed then
  if ch.active then self.adapter.unload(ch.active);self.stats.native_calls=self.stats.native_calls+1 end
  self.chunks[ch.key]=nil;ch.active=nil;self.stats.unloads=self.stats.unloads+1;return false
 end
 if ch.error then return false end
 if not job then if next(ch.dirty)==nil then return false end;job=self:_new_job(ch)end
 if job.phase=='build'then
  local ok,value,tiles=coroutine.resume(job.co);assert(ok,value)
  if coroutine.status(job.co)=='dead'then
   job.packet=value;job.tiles=tiles
   local supported,why=self:_requirements(value);assert(supported,why)
   self:_origin(ch);job.fence=self:_fence(ch);job.packet.fence=G.clone(job.fence);job.packet.world_session=self.session
   job.phase='visual';job.index=1
  end
 elseif job.phase=='visual'then
  local page=job.packet.visual_pages[job.index]
  if not page then job.phase='collision';job.index=1
  else
   page.dimension=ch.dimension;page.generation=self.generation
   page.fence=G.clone(job.fence)
   job.prepared.visual[#job.prepared.visual+1]=assert(self.adapter.prepare(self:_context(),self:_origin(ch),page),'Visual prepare returned no handle')
   self.stats.prepared_pages=self.stats.prepared_pages+1;self.stats.native_calls=self.stats.native_calls+1;job.index=job.index+1
  end
 elseif job.phase=='collision'then
  local page=job.packet.collision_pages[job.index]
  if not page then job.phase='special';job.index=1
  else
   page.dimension=ch.dimension;page.generation=self.generation
   page.fence=G.clone(job.fence)
   job.prepared.collision[#job.prepared.collision+1]=assert(self.adapter.prepare_collision(self:_context(),self:_origin(ch),page),'Collision prepare returned no handle')
   self.stats.prepared_pages=self.stats.prepared_pages+1;self.stats.native_calls=self.stats.native_calls+1;job.index=job.index+1
  end
 elseif job.phase=='special'then
  local types={'fluids','dynamic','fallbacks'};local which=types[job.special_kind or 1]
  if not which then job.phase='commit'
  else local value=job.packet[which][job.index]
   if not value then job.special_kind=(job.special_kind or 1)+1;job.index=1
   else
    job.prepared.special[#job.prepared.special+1]=assert(self.adapter.prepare_special(self:_context(),self:_origin(ch),which,value,job.packet),'Special prepare returned no handle')
    self.stats.prepared_pages=self.stats.prepared_pages+1;self.stats.native_calls=self.stats.native_calls+1;job.index=job.index+1
   end
  end
 elseif job.phase=='commit'then
  -- Lua callbacks are serialized on the game thread. The adapter MUST apply all
  -- pages (including colliders/fluid/dynamic handles) together, or leave old active.
  job.packet.region_id=ch.region_id
  ch.active=self.adapter.commit(job.prepared,ch.active,job.packet)or job.prepared
  self.stats.native_calls=self.stats.native_calls+1;self.stats.commits=self.stats.commits+1
  ch.packet=job.packet;ch.tiles=job.tiles;ch.dirty={};ch.job=nil;return false
 end
 return true
end
function Scheduler:tick(budget_ms,max_steps)
 budget_ms=budget_ms or self.options.frame_budget_ms or 2;max_steps=max_steps or self.options.frame_steps or 128
 assert(budget_ms>=0 and max_steps>=0,'Nonnegative frame budget')
 local start=self.clock();local deadline=start+budget_ms/1000;local steps=0
 while steps<max_steps and self.head<=self.tail and self.clock()<deadline do
  local ch=self.queue[self.head];self.queue[self.head]=nil;self.head=self.head+1;ch.queued=nil
  local ok,again=pcall(self._step,self,ch,deadline)
  if not ok then
   local cleanup_ok,cleanup_error=pcall(self._discard,self,ch.job)
   ch.job=nil;ch.error=tostring(again);self.errors[ch.key]=ch.error
   if not cleanup_ok then ch.error=ch.error..'; cleanup: '..tostring(cleanup_error);self.errors[ch.key]=ch.error end
  elseif again then self:_enqueue(ch)end
  steps=steps+1
 end
 if self.head>self.tail then self.queue={};self.head=1;self.tail=0 end
 local elapsed=(self.clock()-start)*1000;self.stats.max_tick_ms=math.max(self.stats.max_tick_ms,elapsed)
 if elapsed>budget_ms then self.stats.budget_overruns=self.stats.budget_overruns+1 end
 return{steps=steps,elapsed_ms=elapsed,pending=self.tail-self.head+1,errors=count(self.errors)}
end
function Scheduler:retry()
 self.errors={};for _,ch in pairs(self.chunks)do if ch.error then ch.error=nil;ch.job=nil;self:_enqueue(ch)end end
end
function Scheduler:status()
 local blocks,sections,dirty,active=0,0,0,0
 for _,ch in pairs(self.chunks)do blocks=blocks+ch.count;sections=sections+1;dirty=dirty+count(ch.dirty);if ch.active then active=active+1 end end
 return{version=M.version,session=self.session,generation=self.generation,last_seq=self.last_seq,
  blocks=blocks,sections=sections,active_sections=active,dirty_tiles=dirty,pending=self.tail-self.head+1,
  pending_snapshots=count(self.snapshots),errors=G.clone(self.errors),stats=G.clone(self.stats)}
end
local function overlaps(a,b)return a[1]<b[4]and a[4]>b[1]and a[2]<b[5]and a[5]>b[2]and a[3]<b[6]and a[6]>b[3]end
local function section_bounds(ch,size)return{ch.at[1],ch.at[2],ch.at[3],ch.at[1]+size,ch.at[2]+size,ch.at[3]+size}end
local function coverage_complete(self,ticket)
 local bounds=ticket.required_bounds;local covers,cuts={},{bounds[1],bounds[4]}
 for _,c in ipairs(self.coverage)do if c.dim==ticket.dim and c.session==ticket.world_session and c.generation==ticket.generation and(not c.player or not ticket.player or c.player==ticket.player)and overlaps(bounds,c.bounds)then
  covers[#covers+1]=c.bounds
  for _,x in ipairs({c.bounds[1],c.bounds[4]})do if x>bounds[1]and x<bounds[4]then cuts[#cuts+1]=x end end
 end end
 if #covers==0 then return false end;table.sort(cuts)
 for i=1,#cuts-1 do if cuts[i]<cuts[i+1]then
  local x=(cuts[i]+cuts[i+1])*.5;local rects={}
  for _,b in ipairs(covers)do if b[1]<=x and b[4]>=x then rects[#rects+1]={b[2],b[3],b[5],b[6]}end end
  if not G.covered({{bounds[2],bounds[3],bounds[5],bounds[6]}},rects)then return false end
 end end
 return true
end
function Scheduler:prepare_view(request)
 assert(request and type(request.dim)=='string'and request.world_session and request.view,'View dim/session/id required')
 assert(bounds_ok(request.required_bounds),'Explicit required_bounds (exclusive max) required')
 local mapping=assert(request.mapping,'Dimension/region mapping required');local origin=assert(mapping.origin,'Mapping origin required')
 assert(mapping.region_id and mapping.mc_anchor and #mapping.mc_anchor==3,'Mapping region_id and mc_anchor required')
 assert(not mapping.world_session or mapping.world_session==request.world_session,'Mapping world_session mismatch')
 assert(not mapping.dim or mapping.dim==request.dim,'Mapping dimension mismatch')
 assert(not mapping.scale or mapping.scale==100,'Native geometry requires scale=100')
 for _,k in ipairs({'X','Y','Z'})do assert(type(origin[k])=='number'and origin[k]==origin[k]and math.abs(origin[k])<math.huge,'Finite origin '..k..' required')end
 if self.session then assert(request.world_session==self.session,'View world_session mismatch')else self.session=request.world_session end
 local region=self.regions[mapping.region_id]
 local radius=(mapping.page_size or 256)/2;local b=request.required_bounds;local a=mapping.mc_anchor
 assert(b[1]>=a[1]-radius and b[4]<=a[1]+radius and b[3]>=a[3]-radius and b[6]<=a[3]+radius,'Required bounds outside region page')
 if region then assert(region.dim==request.dim and G.stable(region.mapping)==G.stable(mapping),'Region mapping changed before last release')
 else
  local occupied=0;for _,r in pairs(self.regions)do if r.refs>0 then occupied=occupied+1 end end
  assert(occupied<(self.options.max_regions or 4),'Region capacity exhausted')
  local radius=(mapping.page_size or 256)/2
  for _,r in pairs(self.regions)do if r.refs>0 and r.dim==request.dim then
   local a=r.mapping.mc_anchor
   assert(math.abs(a[1]-mapping.mc_anchor[1])>=radius+(r.mapping.page_size or 256)/2 or math.abs(a[3]-mapping.mc_anchor[3])>=radius+(r.mapping.page_size or 256)/2,'Overlapping Minecraft page regions')
  end end
  region={id=mapping.region_id,dim=request.dim,mapping=G.clone(mapping),refs=0,native_view=math.tointeger(request.view)or(self.view_counter+1)};self.regions[region.id]=region
 end
 region.refs=region.refs+1
 self.view_counter=self.view_counter+1
 local ticket={id=tostring(request.view)..':'..self.generation..':'..self.view_counter,player=request.player,view=request.view,
  world_session=request.world_session,dim=request.dim,generation=self.generation,mapping=G.clone(mapping),
  region_id=region.id,mode=request.mode or'client',required_bounds=G.clone(request.required_bounds),
  session_generation=request.session_generation,
  visual=request.mode~='server'and request.visual~=false and self.options.visuals~=false,collision=request.collision~=false}
 self.views[ticket.id]=ticket
 -- Native failures due solely to a missing mapping become retryable now.
 for _,ch in pairs(self.chunks)do if ch.dimension==ticket.dim and overlaps(section_bounds(ch,self.size),ticket.required_bounds)then
  if ch.error then ch.error=nil;ch.job=nil;self.errors[ch.key]=nil end
  if ch.packet and ch.region_id~=ticket.region_id then
   for _,block in pairs(ch.blocks)do ch.dirty[G.tile_index(block.at[1],block.at[2],block.at[3],self.size,self.tile)]=true end
   ch.revision=ch.revision+1
  end
  self:_enqueue(ch)
 end end
 return ticket
end
function Scheduler:readiness(ticket)
 local result={ready=false,world_session=ticket.world_session,dim=ticket.dim,view=ticket.view,region_id=ticket.region_id,generation=ticket.generation,
  renderer_generation=self.generation,session_generation=ticket.session_generation,visual_committed=false,collision_committed=false,
  coverage_complete=false,snapshots_pending=0,visual_pending=0,collision_pending=0,errors={},revision=0}
 if self.views[ticket.id]~=ticket or ticket.released or ticket.generation~=self.generation or ticket.world_session~=self.session then result.errors[1]='stale_view';return result end
 result.coverage_complete=coverage_complete(self,ticket)
 local region=self.regions[ticket.region_id];result.fence=region and{world_session=ticket.world_session,dim=ticket.dim,view=region.native_view,mapping=tostring(region.id)}or nil
 for _,s in pairs(self.snapshots)do if s.dim==ticket.dim and overlaps(s.bounds,ticket.required_bounds)then result.snapshots_pending=result.snapshots_pending+1 end end
 local cap=self.adapter.capabilities or{}
 if ticket.visual and cap.visual_verified~=true then result.errors[#result.errors+1]='visual_runtime_unverified'end
 if ticket.collision and cap.collision_verified~=true then result.errors[#result.errors+1]='collision_runtime_unverified'end
 for _,ch in pairs(self.chunks)do if ch.dimension==ticket.dim and overlaps(section_bounds(ch,self.size),ticket.required_bounds)then
  result.revision=math.max(result.revision,ch.revision)
  if ch.error then result.errors[#result.errors+1]=ch.key..': '..ch.error end
  local ready=not ch.removed and ch.packet and ch.packet.revision==ch.revision and ch.active~=nil and next(ch.dirty)==nil and not ch.job and(ch.count==0 or ch.packet.region_id==ticket.region_id)
  if not ready then if ticket.visual then result.visual_pending=result.visual_pending+1 end;if ticket.collision then result.collision_pending=result.collision_pending+1 end end
 end end
 result.ready=result.coverage_complete and result.snapshots_pending==0 and result.visual_pending==0 and result.collision_pending==0 and #result.errors==0
 result.covered_bounds=result.coverage_complete and G.clone(ticket.required_bounds)or nil
 result.collision_committed=cap.collision_verified==true and result.coverage_complete and result.snapshots_pending==0 and result.collision_pending==0 and #result.errors==0
 result.visual_committed=not ticket.visual or(cap.visual_verified==true and result.coverage_complete and result.snapshots_pending==0 and result.visual_pending==0 and #result.errors==0)
 result.renderer_generation=self.generation;result.session_generation=ticket.session_generation
 return result
end
function Scheduler:activate(ticket)
 local ready=self:readiness(ticket);assert(ready.ready,'View not ready: '..G.stable(ready))
 if self.adapter.activate_view then self.adapter.activate_view(ticket)end
 local previous=self.active_view;self.active_view=ticket;ticket.active=true;return previous
end
function Scheduler:release(ticket)
 assert(self.views[ticket.id]==ticket and ticket.generation==self.generation and ticket.world_session==self.session,'Stale view release')
 ticket.released=true;ticket.active=false;if self.active_view==ticket then self.active_view=nil end
 local region=self.regions[ticket.region_id];region.refs=region.refs-1
 if region.refs==0 then self.regions[ticket.region_id]=nil end
 local unload={}
 for _,ch in pairs(self.chunks)do if ch.dimension==ticket.dim and overlaps(section_bounds(ch,self.size),ticket.required_bounds)then
  local retained=false
  for _,other in pairs(self.views)do if not other.released and other.dim==ch.dimension and overlaps(section_bounds(ch,self.size),other.required_bounds)then retained=true;break end end
  if not retained then unload[#unload+1]=ch end
 end end
 for _,ch in ipairs(unload)do self:unload(ch.dimension,ch.coords[1],ch.coords[2],ch.coords[3])end
 return true
end
return M
