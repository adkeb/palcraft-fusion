-- Region-scoped world facade. Each region has its own native instances, so halo
-- overlap never assigns a Minecraft chunk to two different origins arbitrarily.
-- Canonical MC allocation stride and the prepared window are independent concepts.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local G=dofile(dir..'chunk_geometry.lua');local S=dofile(dir..'chunk_scheduler.lua')
local M={version=1};local Views={};Views.__index=Views
local function intersects(a,b)return a[1]<b[4]and a[4]>b[1]and a[2]<b[5]and a[5]>b[2]and a[3]<b[6]and a[6]>b[3]end
local function clip(a,b)
 if not intersects(a,b)then return nil end
 return{math.max(a[1],b[1]),math.max(a[2],b[2]),math.max(a[3],b[3]),math.min(a[4],b[4]),math.min(a[5],b[5]),math.min(a[6],b[6])}
end
local function inside(a,b)return a[1]>=b[1]and a[2]>=b[2]and a[3]>=b[3]and a[1]<b[4]and a[2]<b[5]and a[3]<b[6]end
local function validate_mapping(request)
 local m=assert(request.mapping,'Region mapping required');local anchor=assert(m.mc_anchor,'MC anchor required')
 assert(m.region_id and #anchor==3 and math.tointeger(anchor[1])and math.tointeger(anchor[2])and math.tointeger(anchor[3]),'Region id and integral anchor required')
 local origin=assert(m.origin,'Region origin required');for _,k in ipairs({'X','Y','Z'})do assert(type(origin[k])=='number'and origin[k]==origin[k]and math.abs(origin[k])<math.huge,'Finite region origin required')end
 assert(not m.dim or m.dim==request.dim,'Mapping dimension mismatch')
 assert(not m.world_session or m.world_session==request.world_session,'Mapping session mismatch')
 assert(not m.scale or m.scale==100,'Native scale must be100')
 local window=m.window_size or m.page_size or 656
 assert(math.tointeger(window)and window>0 and window%2==0,'Even integral region window required')
 local half=window//2
 -- Vertical coverage comes from requested MC bounds; horizontal halo has its own
 -- MC extent, while mapped geometry must fit the separately allocated UE region.
 local b=assert(request.required_bounds,'Required bounds needed')
 assert(#b==6,'Six required bounds coordinates');for _,n in ipairs(b)do assert(math.tointeger(n),'Integral view bounds')end
 assert(b[1]<b[4]and b[2]<b[5]and b[3]<b[6],'Positive view bounds')
 assert(b[1]>=anchor[1]-half and b[4]<=anchor[1]+half and b[3]>=anchor[3]-half and b[6]<=anchor[3]+half,'Requested ring exceeds region window')
 local physical=m.region_bounds
 if physical then
  assert(#physical==6,'Physical region bounds required')
  for _,n in ipairs(physical)do assert(type(n)=='number'and n==n and math.abs(n)<math.huge,'Finite physical bounds')end
  local y=m.y_origin or 64
  local transformed={origin.X+b[1]*100,origin.Y-b[6]*100,origin.Z+(b[2]-y)*100,
   origin.X+b[4]*100,origin.Y-b[3]*100,origin.Z+(b[5]-y)*100}
  for i=1,3 do assert(transformed[i]>=physical[i]and transformed[i+3]<=physical[i+3],'Requested MC coverage exceeds physical region')end
 end
 return window
end
function M.new(options)
 assert(options and options.adapter and options.geometry,'Native adapter and geometry required')
 return setmetatable({options=options,adapter=options.adapter,regions={},tickets={},generation=1,session=options.session,
  cursor=1,clock=options.clock or os.clock,next_view=0,stats={rows=0,ticks=0,max_tick_ms=0,budget_overruns=0}},Views)
end
function Views:prepare_view(request)
 assert(request.world_session and request.dim and request.view,'World/view/dimension required')
 assert(not self.session or self.session==request.world_session,'World session mismatch')
 local window=validate_mapping(request);local mapping=request.mapping;local region=self.regions[mapping.region_id]
 if region then
  assert(region.dim==request.dim and G.stable(region.mapping)==G.stable(mapping),'Referenced region mapping cannot change')
  assert(region.mode==(request.mode or'client'),'Region client/server mode mismatch')
 else
  local n=0;for _ in pairs(self.regions)do n=n+1 end;assert(n<(self.options.max_regions or 4),'Region capacity exhausted')
  -- Physical arenas cannot overlap. MC halos MAY overlap and get independent actors.
  if mapping.region_bounds then for _,r in pairs(self.regions)do if r.mapping.region_bounds then
   assert(not intersects(mapping.region_bounds,r.mapping.region_bounds),'Physical regions overlap')
  end end end
  local child_options={};for k,v in pairs(self.options)do child_options[k]=v end
  local proxy={};for k,v in pairs(self.adapter)do proxy[k]=v end;proxy.reset=function()end
  child_options.adapter=proxy;child_options.session=request.world_session;child_options.max_regions=1
  child_options.visuals=(request.mode or'client')=='client'and self.options.visuals~=false
  child_options.origins={};child_options.view_player=self.options.view_player
  local child=S.new(child_options);child.generation=self.generation
  region={id=mapping.region_id,dim=request.dim,mapping=G.clone(mapping),refs=0,mode=request.mode or'client',scheduler=child,
   window={mapping.mc_anchor[1]-window//2,-2147483648,mapping.mc_anchor[3]-window//2,mapping.mc_anchor[1]+window//2,2147483647,mapping.mc_anchor[3]+window//2}}
  if mapping.region_bounds then
   local p,o=mapping.region_bounds,mapping.origin
   -- Keep complete MC cells inside the physical allocation; ±327.68 cells does
   -- not permit a complete block occupying [327,328]. Required rings were checked.
   region.window[1]=math.max(region.window[1],math.ceil((p[1]-o.X)/100))
   region.window[4]=math.min(region.window[4],math.floor((p[4]-o.X)/100))
   region.window[3]=math.max(region.window[3],math.ceil((o.Y-p[5])/100))
   region.window[6]=math.min(region.window[6],math.floor((o.Y-p[2])/100))
  end
  self.regions[region.id]=region
 end
 self.session=request.world_session
 local child_request=G.clone(request);child_request.mapping.page_size=window
 local child_ticket=region.scheduler:prepare_view(child_request)
 self.next_view=self.next_view+1
 local ticket={id=tostring(request.view)..':'..self.generation..':'..self.next_view,world_session=request.world_session,
  generation=self.generation,session_generation=request.session_generation,dim=request.dim,view=request.view,
  player=request.player,region_id=region.id,region=region,child=child_ticket,mapping=G.clone(mapping),required_bounds=G.clone(request.required_bounds)}
 region.refs=region.refs+1;self.tickets[ticket.id]=ticket;return ticket
end
function Views:readiness(ticket)
 if self.tickets[ticket.id]~=ticket or ticket.released or ticket.generation~=self.generation or ticket.world_session~=self.session then
  return{ready=false,world_session=ticket.world_session,dim=ticket.dim,view=ticket.view,region_id=ticket.region_id,
   renderer_generation=self.generation,session_generation=ticket.session_generation,coverage_complete=false,
   snapshots_pending=0,collision_pending=0,visual_pending=0,collision_committed=false,visual_committed=false,errors={'stale_view'},revision=0}
 end
 return ticket.region.scheduler:readiness(ticket.child)
end
function Views:activate(ticket)
 assert(self:readiness(ticket).ready,'Region view not ready')
 local previous=self.active_view;ticket.region.scheduler:activate(ticket.child);self.active_view=ticket;return previous
end
function Views:release(ticket)
 assert(self.tickets[ticket.id]==ticket and not ticket.released and ticket.generation==self.generation and ticket.world_session==self.session,'Stale region view release')
 ticket.region.scheduler:release(ticket.child);ticket.released=true;ticket.region.refs=ticket.region.refs-1
 if self.active_view==ticket then self.active_view=nil end
 -- The last ticket retires ALL instances in that arena, including halo data beyond
 -- the ticket's immediate ring. Other arenas and players remain active.
 if ticket.region.refs==0 then
  local child=ticket.region.scheduler;local selected={};for _,ch in pairs(child.chunks)do selected[#selected+1]=ch end
  for _,ch in ipairs(selected)do child:unload(ch.dimension,ch.coords[1],ch.coords[2],ch.coords[3])end
  ticket.region.retiring=true
 end
 return true
end
function Views:_filtered(row,region)
 local dim=row.dim or row.dimension or'minecraft:overworld';if dim~=region.dim then return nil end
 local result={t=row.t,v=row.v,session=row.session,seq=row.seq,dim=dim,tick=row.tick,ops={},lifecycle={}}
 for _,life in ipairs(row.lifecycle or{})do
  local kind=life.op or life.kind or life.t or life.event;local include=true;local value=G.clone(life)
  if kind=='snapshot_begin'or kind=='snapshot_end'or kind=='snapshot_cancel'then
   value.bounds=life.bounds and clip(life.bounds,region.window);include=value.bounds~=nil
  elseif kind=='chunk_load'or kind=='chunk_unload'then
   local size=self.options.chunk_size or 16;local at=life.at
   include=at and intersects({at[1]*size,-2147483648,at[2]*size,(at[1]+1)*size,2147483647,(at[2]+1)*size},region.window)
  end
  if include then result.lifecycle[#result.lifecycle+1]=value end
 end
 if row.ops then for _,op in ipairs(row.ops)do if op.at and inside(op.at,region.window)then result.ops[#result.ops+1]=op end end
 else
  local by={};for _,b in ipairs(row.geometry or{})do by[G.stable(b.at)]=b end
  for _,kind in ipairs({'clear','set'})do local values=row[kind]or{}
   for i=1,#values,3 do local at={values[i],values[i+1],values[i+2]}
    if inside(at,region.window)then
     local op=kind=='set'and G.clone(by[G.stable(at)]or{at=at,id='palcraft:unknown'})or{at=at};op.op=kind=='set'and'upsert'or'remove';result.ops[#result.ops+1]=op
    end
   end
  end
 end
 return result
end
function Views:ingest(row)
 assert(type(row)=='table','World event required')
 if row.session and self.session and row.session~=self.session then
  self:reset(row.session,false,self.options.context_alive and self.options.context_alive()or false)
  return false,'world_session_changed_prepare_views_and_request_snapshots'
 end
 local n=0
 for _,region in pairs(self.regions)do if not region.retiring then
  local filtered=self:_filtered(row,region);if filtered then region.scheduler:ingest(filtered);n=n+1 end
 end end
 self.stats.rows=self.stats.rows+1;return true,n
end
function Views:tick(budget_ms,max_steps)
 budget_ms=budget_ms or self.options.frame_budget_ms or 2;max_steps=max_steps or self.options.frame_steps or 128
 local start=self.clock();local list=G.sorted_keys(self.regions);local steps=0
 local idle=0
 while #list>0 and steps<max_steps and(self.clock()-start)*1000<budget_ms and idle<#list do
  self.cursor=(self.cursor-1)%#list+1;local r=self.regions[list[self.cursor]];self.cursor=self.cursor+1
  local remaining=budget_ms-(self.clock()-start)*1000
  local done=r.scheduler:tick(math.max(0,remaining),math.min(32,max_steps-steps));steps=steps+done.steps
  if done.steps==0 then idle=idle+1 else idle=0 end
 end
 for id,r in pairs(self.regions)do if r.retiring and r.scheduler:status().pending==0 then self.regions[id]=nil end end
 local elapsed=(self.clock()-start)*1000;self.stats.ticks=self.stats.ticks+1;self.stats.max_tick_ms=math.max(self.stats.max_tick_ms,elapsed)
 if elapsed>budget_ms then self.stats.budget_overruns=self.stats.budget_overruns+1 end
 return{steps=steps,elapsed_ms=elapsed,pending=self:status().pending}
end
function Views:reset(session,keep_world,context_alive)
 -- Region bindings are invalid after a world reset; preserving their mappings across
 -- a new MC session would reuse invalid tickets. A reconnect requests fresh snapshots.
 assert(not keep_world,'Region reset requires fresh view bindings and snapshots')
 for _,r in pairs(self.regions)do r.scheduler:reset(session,false,context_alive)end
 self.generation=self.generation+1
 if self.adapter.reset then self.adapter.reset(self.generation,context_alive==true)end
 self.regions={};self.tickets={};self.active_view=nil;self.session=session;self.cursor=1
end
function Views:status()
 local result={version=M.version,session=self.session,generation=self.generation,regions=0,blocks=0,sections=0,pending=0,errors={},stats=G.clone(self.stats)}
 for id,r in pairs(self.regions)do local s=r.scheduler:status();result.regions=result.regions+1;result.blocks=result.blocks+s.blocks;result.sections=result.sections+s.sections;result.pending=result.pending+s.pending
  for k,v in pairs(s.errors)do result.errors[id..':'..k]=v end
 end
 return result
end
return M
