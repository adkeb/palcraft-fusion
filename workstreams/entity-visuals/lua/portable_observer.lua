-- Visual observer only: no entities spawned in MC, pickup, grants or damage.
local P={}
function P.new(o)
 local Models,Visuals=assert(o.models),assert(o.visuals)
 local O,session,dimension=assert(o.origin),assert(o.session),assert(o.dimension)
 local now=o.now or os.time
 local M={views={},epochs={},revisions={},stats={spawned=0,updated=0,replaced=0,removed=0},pending={}}
 local function position(row)return{X=O.X+row.x*100,Y=O.Y-row.z*100,Z=O.Z+(row.y-(O.y_origin or 64))*100}end
 local function release(h)
  Models.release_model(h.model,o.context_alive and o.context_alive()or true);M.stats.removed=M.stats.removed+1
 end
 local function create(row,groups)
  local model=Models.spawn_groups(o.context(),O,groups,{row.x,row.y,row.z},{hidden=true})
  assert(model,'Portable native world mesh not created')
  Models.set_actor_pose(model,position(row),0);Models.set_visible(model,true)
  M.stats.spawned=M.stats.spawned+1
  return{model=model,row=row,groups=groups}
 end
 local function same(a,b)
  if #a~=#b then return false end
  for i,g in ipairs(a)do if g.texture_path~=b[i].texture_path or #g.vertices~=#b[i].vertices or #g.indices~=#b[i].indices then return false end end
  return true
 end
 function M.apply(snapshot)
  local stream=snapshot.t=='drops'and'items'or snapshot.t=='entity_snapshot'and'projectiles'or nil
  if not stream then return nil,'other_snapshot_type' end
  -- A bare legacy drops.json lacks authority/session/epoch. Caller must supply
  -- its authenticated world binding; do not promote file freshness to authority.
  if snapshot.authority~='mc_server'or snapshot.session~=session then return nil,'unbound_authority' end
  if type(snapshot.epoch)~='string'or type(snapshot.revision)~='number'or type(snapshot.unix)~='number'then return nil,'missing_snapshot_identity' end
  if now()-snapshot.unix>3 or now()-snapshot.unix<-5 then return nil,'stale_snapshot' end
  if M.epochs[stream]==snapshot.epoch and snapshot.revision<(M.revisions[stream]or -1)then return nil,'old_revision' end
  if M.epochs[stream]and M.epochs[stream]~=snapshot.epoch then
   for k,h in pairs(M.views)do if h.stream==stream then release(h);M.views[k]=nil end end
  end
  M.epochs[stream]=snapshot.epoch;M.revisions[stream]=snapshot.revision
  local desired={}
  for _,r in ipairs(stream=='items'and(snapshot.items or{})or(snapshot.entities or{}))do
   if(stream=='items'or r.category=='projectile')and(r.dimension or snapshot.dimension)==dimension and r.alive~=false then
    local stable=r.uuid or r.id
    if type(stable)=='string'then
     local key=stream..':'..snapshot.epoch..':'..stable;desired[key]=true
     local row={};for name,value in pairs(r)do row[name]=value end
     row.category=stream=='items'and'item'or'projectile'
     local groups,why=Visuals.geometry(row)
     if groups then
      local prior=M.views[key]
      if not prior then
       local h=create(row,groups);h.stream=stream;M.views[key]=h
       -- Only native mesh commit may authorize the legacy visual removal.
       if stream=='items'and o.on_drop_committed then o.on_drop_committed(r,h)end
      elseif not same(prior.groups,groups)then
       local h=create(row,groups);h.stream=stream;M.views[key]=h;release(prior);M.stats.replaced=M.stats.replaced+1
      else
       Models.update_groups(prior.model,groups);Models.set_actor_pose(prior.model,position(row),0)
       prior.groups,prior.row=groups,row;M.stats.updated=M.stats.updated+1
      end
      M.pending[key]=nil
     else M.pending[key]=why end
    end
   end
  end
  for key,h in pairs(M.views)do if h.stream==stream and not desired[key]then release(h);M.views[key]=nil;M.pending[key]=nil end end
  return M.status()
 end
 function M.status()
  local n=0;for _ in pairs(M.views)do n=n+1 end
  return{visual_only=true,authority_unchanged=true,world_models=n,stats=M.stats,pending=M.pending,
   effects_verified=false,inventory_writes=0,pickup_events_sent=0,damage_events_sent=0}
 end
 function M.stop()for k,h in pairs(M.views)do release(h);M.views[k]=nil end;M.pending={}end
 return M
end
return P
