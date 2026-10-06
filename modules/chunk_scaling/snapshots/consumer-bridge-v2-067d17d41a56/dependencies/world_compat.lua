-- Pure state reducer for authoritative MC events. It performs no Unreal calls or file writes.
-- World.new({dimension='minecraft:overworld',player=mc_uuid?,on_upsert,on_remove,on_lifecycle})
-- :ingest(row), :set_view(dim, player?), :get(dim,x,y,z), :fluid_at(dim,x,y,z), :status()
local World={};World.__index=World
local FULL={{0,0,0,1,1,1}}
local function finite(v)return type(v)=='number'and v==v and v~=math.huge and v~=-math.huge end
local function integer(v)return finite(v)and v==math.floor(v)end
local function copy(t)local r={};for k,v in pairs(t or{})do r[k]=v end;return r end
local function coordinate(at,n)
 if type(at)~='table'or #at~=n then return false end
 for i=1,n do if not integer(at[i])or math.abs(at[i])>30000000 then return false end end;return true
end
local function key(at)return('%d:%d:%d'):format(at[1],at[2],at[3])end
local function inside(at,b)return at[1]>=b[1]and at[2]>=b[2]and at[3]>=b[3]and at[1]<b[4]and at[2]<b[5]and at[3]<b[6]end
local function valid_bounds(b)
 if not coordinate(b,6)then return false end
 return b[1]<b[4]and b[2]<b[5]and b[3]<b[6]
end
local function valid_block(g)
 if type(g)~='table'or not coordinate(g.at,3)or(g.op~='upsert'and g.op~='remove')then return false end
 if type(g.id)~='string'or not g.id:match('^[%w_%.%-]+:[%w_/%.%-]+$')then return false end
 if type(g.boxes)~='table'or #g.boxes>256 then return false end
 for _,box in ipairs(g.boxes)do
  if type(box)~='table'or #box~=6 then return false end
  for i=1,6 do if not finite(box[i])or math.abs(box[i])>16 then return false end end
  if box[1]>=box[4]or box[2]>=box[5]or box[3]>=box[6]then return false end
 end
 if type(g.solid)~='boolean'or g.solid~=(#g.boxes>0)or type(g.visible)~='boolean'then return false end
 if type(g.fluid)~='table'or(g.fluid.kind~='none'and g.fluid.kind~='water'and g.fluid.kind~='lava'and g.fluid.kind~='other')then return false end
 if g.fluid.kind~='none'and(not finite(g.fluid.height)or g.fluid.height<0 or g.fluid.height>1)then return false end
 if g.snapshot~=nil and type(g.snapshot)~='string'then return false end
 return true
end
local function valid_event(e)
 if type(e)~='table'or type(e.op)~='string'then return false end
 if e.op=='snapshot_begin'or e.op=='snapshot_end'or e.op=='snapshot_cancel'then
  return type(e.snapshot)=='string'and coordinate(e.at,2)and valid_bounds(e.bounds)
 elseif e.op=='chunk_load'or e.op=='chunk_unload'then return coordinate(e.at,2)
 elseif e.op=='player_view'then return type(e.player)=='string'and type(e.to)=='string'and integer(e.view)
 end
 return true
end
function World.new(options)
 options=options or{}
 return setmetatable({options=options,dimension=options.dimension or'minecraft:overworld',player=options.player,
  worlds={},snapshots={},committed_snapshots={},committed_order={},retired={},session=nil,seq=0,last_gap_seq=0,
  applied=0,duplicates=0,rejected=0,legacy=0,gaps=0,needs_resync=false},World)
end
function World:_world(dim)
 local w=self.worlds[dim];if not w then w={blocks={},chunks={},metadata={}};self.worlds[dim]=w end;return w
end
function World:_callback(name,value)
 local f=self.options[name];if f then return f(value)end
end
function World:_event(row,e)
 local event=copy(e);event.dim=row.dim;event.session=self.session;event.seq=row.seq;event.tick=row.tick
 event.schema=row.v;event.row_ops=#(row.ops or{});event.row_lifecycle=#(row.lifecycle or{})
 return self:_callback('on_lifecycle',event)
end
function World:_remove(dim,k)
 local blocks=self:_world(dim).blocks;local previous=blocks[k]
 if not previous then return end;blocks[k]=nil
 if dim==self.dimension then local g=copy(previous);g.op='remove';self:_callback('on_remove',g)end
end
function World:_put(dim,g)
 local value=copy(g);value.dim=dim;value.session=self.session;value.revision=self.seq
 local blocks=self:_world(dim).blocks;local k=key(value.at)
 if g.op=='remove'then self:_remove(dim,k)
 else blocks[k]=value;if dim==self.dimension then self:_callback('on_upsert',value)end end
end
function World:set_view(dim,player,view)
 assert(type(dim)=='string','dimension key required')
 if player~=nil then self.player=player end
 if view~=nil then self.view=view elseif self.pending_view and self.pending_view.to==dim then self.view=self.pending_view.view end
 if self.pending_view and self.pending_view.to==dim then self.pending_view=nil end
 if dim==self.dimension then return end
 local old=self.worlds[self.dimension]
 if old then for _,g in pairs(old.blocks)do local removed=copy(g);removed.op='remove';self:_callback('on_remove',removed)end end
 self.dimension=dim;local current=self.worlds[dim]
 if current then for _,g in pairs(current.blocks)do self:_callback('on_upsert',g)end end
end
function World:_clear_dimension(dim)
 local world=self.worlds[dim]
 if world then
  local keys={};for k in pairs(world.blocks)do keys[#keys+1]=k end
  for _,k in ipairs(keys)do self:_remove(dim,k)end
 end
 self.worlds[dim]=nil
 for id,stage in pairs(self.snapshots)do if stage.dim==dim then self.snapshots[id]=nil end end
 for id,receipt in pairs(self.committed_snapshots)do if receipt.dim==dim then self.committed_snapshots[id]=nil end end
end
function World:_reset(session)
 if self.session then self.retired[self.session]=true end
 local dimensions={};for dim in pairs(self.worlds)do dimensions[#dimensions+1]=dim end
 for _,dim in ipairs(dimensions)do self:_clear_dimension(dim)end
 self.worlds={};self.snapshots={};self.committed_snapshots={};self.committed_order={};self.session=session;self.seq=0;self.last_gap_seq=0;self.needs_resync=true
 self:_callback('on_lifecycle',{op='session_reset',session=session,dim=self.dimension,resync_required=true})
end
function World:_touch(dim,g)
 for _,stage in pairs(self.snapshots)do
  if stage.dim==dim and inside(g.at,stage.bounds)then stage.touched[key(g.at)]=true end
 end
end
function World:_snapshot_end(row,e)
 local stage=self.snapshots[e.snapshot]
 if not stage then return end
 local world=self:_world(stage.dim);local nextValues={};local removals={};local upserts={}
 if stage.replace then for k,g in pairs(world.blocks)do
  if inside(g.at,stage.bounds)and not stage.touched[k]then nextValues[k]=false end
 end end
 for k,g in pairs(stage.blocks)do if not stage.touched[k]then nextValues[k]=g end end
 -- Commit the entire logical region before callbacks observe it. The renderer can coalesce its own queue.
 for k,g in pairs(nextValues)do
  if g==false or g.op=='remove'then
   local previous=world.blocks[k]
   if previous then world.blocks[k]=nil;local removed=copy(previous);removed.op='remove';removals[#removals+1]=removed end
  else local value=copy(g);value.dim=stage.dim;value.session=self.session;value.revision=row.seq
   world.blocks[k]=value;upserts[#upserts+1]=value
  end
 end
 self.snapshots[e.snapshot]=nil
 local ignored,stored=0,0;for _ in pairs(stage.touched)do ignored=ignored+1 end
 for _,g in pairs(world.blocks)do if inside(g.at,stage.bounds)then stored=stored+1 end end
 local receipt={snapshot=e.snapshot,session=self.session,dim=stage.dim,player=stage.player,at=stage.at,bounds=stage.bounds,
  begin_seq=stage.begin_seq,end_seq=row.seq,upserts=#upserts,removals=#removals,newer_deltas=ignored,blocks=stored,committed=true}
 self.committed_snapshots[e.snapshot]=receipt;self.committed_order[#self.committed_order+1]=e.snapshot
 while #self.committed_order>256 do self.committed_snapshots[table.remove(self.committed_order,1)]=nil end
 if stage.dim==self.dimension then
  for _,g in ipairs(removals)do self:_callback('on_remove',g)end
  for _,g in ipairs(upserts)do self:_callback('on_upsert',g)end
 end
 self.needs_resync=false
 return receipt
end
function World:_lifecycle(row,e)
 local world=self:_world(row.dim)
 if e.op=='snapshot_begin'then
  self.snapshots[e.snapshot]={dim=row.dim,bounds=e.bounds,at=e.at,player=e.player,begin_seq=row.seq,replace=e.replace~=false,blocks={},touched={}}
 elseif e.op=='snapshot_cancel'then self.snapshots[e.snapshot]=nil
 elseif e.op=='snapshot_end'then
  local receipt=self:_snapshot_end(row,e);local finished=copy(e)
  finished.committed=receipt~=nil;finished.commit=receipt;self:_event(row,finished);return
 elseif e.op=='chunk_load'then world.chunks[e.at[1]..':'..e.at[2]]=true
 elseif e.op=='chunk_unload'then
  local keys={};for k,g in pairs(world.blocks)do
   if math.floor(g.at[1]/16)==e.at[1]and math.floor(g.at[3]/16)==e.at[2]then keys[#keys+1]=k end
  end
  for _,k in ipairs(keys)do self:_remove(row.dim,k)end
  world.chunks[e.at[1]..':'..e.at[2]]=nil
  for id,stage in pairs(self.snapshots)do
   if stage.dim==row.dim and stage.at[1]==e.at[1]and stage.at[2]==e.at[2]then self.snapshots[id]=nil end
  end
  for id,receipt in pairs(self.committed_snapshots)do
   if receipt.dim==row.dim and receipt.at[1]==e.at[1]and receipt.at[2]==e.at[2]then self.committed_snapshots[id]=nil end
  end
 elseif e.op=='world_load'then world.metadata=copy(e)
 elseif e.op=='world_unload'then self:_clear_dimension(row.dim)
 elseif e.op=='resync_required'then self.needs_resync=true
 elseif e.op=='player_view'and self.player and e.player==self.player then
  self.pending_view=copy(e)
  local proceed=self:_event(row,e)
  if self.options.auto_view~=false and proceed~=false then self:set_view(e.to)end
  return
 end
 self:_event(row,e)
end
function World:_reject(reason)
 self.rejected=self.rejected+1;self:_callback('on_error',{reason=reason,session=self.session,seq=self.seq})
 return false,reason
end
function World:_legacy(row)
 if self.session then self.duplicates=self.duplicates+1;return true,'legacy_after_v2' end
 local dimension=row.dim or'minecraft:overworld';local geometry={}
 for _,g in ipairs(row.geometry or{})do if not coordinate(g.at,3)then return self:_reject('legacy_geometry')end;geometry[key(g.at)]=g end
 for _,kind in ipairs({'clear','set'})do
  local values=row[kind]or{};if type(values)~='table'or #values%3~=0 then return self:_reject('legacy_coordinates')end
  for i=1,#values,3 do if not coordinate({values[i],values[i+1],values[i+2]},3)then return self:_reject('legacy_coordinates')end end
 end
 for _,kind in ipairs({'clear','set'})do for i=1,#(row[kind]or{}),3 do
  local values=row[kind];local at={values[i],values[i+1],values[i+2]};local original=geometry[key(at)]
  local g=copy(original);g.at=at;g.op=kind=='set'and'upsert'or'remove'
  g.id=g.id or'palcraft:legacy_unknown';g.boxes=g.boxes or FULL;g.solid=#g.boxes>0
  g.visible=kind=='set'and original~=nil;g.render_kind=g.visible and'block'or'none'
  g.fluid={kind='none',empty=true,collision='ignore',simulation='minecraft'}
  g.legacy=true;g.geometry_missing=original==nil
  self:_put(dimension,g)
 end end
 self.legacy=self.legacy+1;return true,'legacy'
end
function World:ingest(row)
 if type(row)~='table'or row.t~='blocks'then return false,'not_world_event' end
 if row.v==nil then return self:_legacy(row)end
 if row.v~=2 or type(row.session)~='string'or row.session==''or not integer(row.seq)or row.seq<1 or type(row.dim)~='string'then
  return self:_reject('envelope')
 end
 if self.retired[row.session]then self.duplicates=self.duplicates+1;return true,'retired_session' end
 if self.session==row.session and row.seq<=self.seq then self.duplicates=self.duplicates+1;return true,'duplicate' end
 if type(row.ops)~='table'or #row.ops>8192 or(row.lifecycle~=nil and type(row.lifecycle)~='table')then return self:_reject('batch')end
 for _,g in ipairs(row.ops)do if not valid_block(g)then return self:_reject('block_state')end end
 for _,e in ipairs(row.lifecycle or{})do if not valid_event(e)then return self:_reject('lifecycle')end end
 if self.session~=row.session then self:_reset(row.session)end
 if self.seq>0 and row.seq>self.seq+1 then
  self.gaps=self.gaps+1;self.needs_resync=true;self.last_gap_seq=row.seq
  self:_event(row,{op='sequence_gap',expected=self.seq+1,received=row.seq,resync_required=true})
 end
 self.seq=row.seq
 for _,e in ipairs(row.lifecycle or{})do self:_lifecycle(row,e)end
 for _,g in ipairs(row.ops)do
  if g.snapshot then
   local stage=self.snapshots[g.snapshot]
   if stage and stage.dim==row.dim and inside(g.at,stage.bounds)then stage.blocks[key(g.at)]=g end
  else self:_touch(row.dim,g);self:_put(row.dim,g)end
 end
 self.applied=self.applied+1;return true,'applied'
end
function World:get(dim,x,y,z)
 local world=self.worlds[dim];return world and world.blocks[key({x,y,z})]or nil
end
function World:fluid_at(dim,x,y,z)
 local g=self:get(dim,math.floor(x),math.floor(y),math.floor(z));local f=g and g.fluid
 if not f or f.kind=='none'or y-g.at[2]>=(f.height or 0)then return nil end
 -- Waterlogged solids are excluded from the volume. The voxel boxes remain the collision authority.
 if f.waterlogged then for _,b in ipairs(g.boxes or{})do
  local lx,ly,lz=x-g.at[1],y-g.at[2],z-g.at[3]
  if lx>=b[1]and lx<b[4]and ly>=b[2]and ly<b[5]and lz>=b[3]and lz<b[6]then return nil end
 end end
 local result=copy(f);result.at=g.at;result.dim=dim;result.solid=g.solid
 result.collision='ignore';return result
end
function World:fluid_volumes(dim,bounds)
 assert(valid_bounds(bounds),'finite exclusive region bounds required')
 local result={};local world=self.worlds[dim]
 for _,g in pairs(world and world.blocks or{})do local fluid=g.fluid
  if fluid and fluid.kind~='none'and g.at[1]<bounds[4]and g.at[1]+1>bounds[1]and g.at[2]<bounds[5]
   and g.at[2]+fluid.height>bounds[2]and g.at[3]<bounds[6]and g.at[3]+1>bounds[3]then
   result[#result+1]={at=g.at,dim=dim,kind=fluid.kind,height=fluid.height,source=fluid.source,falling=fluid.falling,
    flow=fluid.flow,surface=fluid.surface,waterlogged=fluid.waterlogged,solid_boxes=g.boxes,collision='ignore',simulation='minecraft'}
  end
 end
 return result
end
function World:committed_snapshot(id)return self.committed_snapshots[id]end
function World:region_status(dim,bounds,player)
 assert(valid_bounds(bounds),'finite exclusive region bounds required')
 local result={ready=false,dim=dim,bounds=bounds,session=self.session,seq=self.seq,reason='no_committed_snapshot',pending=0}
 for _,stage in pairs(self.snapshots)do
  local b=stage.bounds
  if stage.dim==dim and(not player or stage.player==player)and b[1]<bounds[4]and b[4]>bounds[1]
   and b[2]<bounds[5]and b[5]>bounds[2]and b[3]<bounds[6]and b[6]>bounds[3]then result.pending=result.pending+1 end
 end
 if result.pending>0 then result.reason='snapshot_in_progress';return result end
 for _,receipt in pairs(self.committed_snapshots)do local b=receipt.bounds
  if receipt.dim==dim and(not player or receipt.player==player)and receipt.session==self.session
   and receipt.end_seq>=self.last_gap_seq and b[1]<=bounds[1]and b[2]<=bounds[2]and b[3]<=bounds[3]
   and b[4]>=bounds[4]and b[5]>=bounds[5]and b[6]>=bounds[6]then
   result.ready=true;result.reason='committed_snapshot';result.proof=receipt;return result
  end
 end
 return result
end
function World:status()
 local dimensions={};local total=0;local active=0;local pending=0
 for dim,world in pairs(self.worlds)do local n=0;for _ in pairs(world.blocks)do n=n+1 end
  dimensions[dim]=n;total=total+n;if dim==self.dimension then active=n end
 end
 for _ in pairs(self.snapshots)do pending=pending+1 end
 return {v=2,session=self.session,seq=self.seq,dimension=self.dimension,view=self.view,player=self.player,
  pending_view=self.pending_view,blocks=total,visible_view_blocks=active,dimensions=dimensions,snapshots=pending,applied=self.applied,
  duplicates=self.duplicates,rejected=self.rejected,legacy=self.legacy,gaps=self.gaps,needs_resync=self.needs_resync}
end
return World
