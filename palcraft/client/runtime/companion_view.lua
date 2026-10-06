-- Travel readiness over the existing per-block companion. Never reads a second journal.
-- It supports the current Overworld mapping only; auxiliary regions use the chunk adapter.
local M={version=1}
local function same_origin(a,b)
 for _,k in ipairs({'X','Y','Z'})do if type(a[k])~='number'or type(b[k])~='number'or math.abs(a[k]-b[k])>0.001 then return false end end
 return true
end
function M.new(o)
 local companion=assert(o.companion);local encode=o.encode_geometry or companion.geometry_signature
 assert(type(encode)=='function','Companion-owned geometry encoder required')
 local tickets={};local serial=0
 local api={}
 local function check(t)
  assert(tickets[t.id]==t and not t.released,'Stale companion view ticket')
 end
 function api.prepare_view(req)
  assert(req.dim=='minecraft:overworld','Per-block companion supports the existing Overworld only')
  assert(req.mapping and same_origin(req.mapping.origin,companion.origin),'Per-block companion cannot rebase its physical origin')
  assert(req.world_session==companion.world.session,'Companion world lifetime mismatch')
  assert(type(req.required_bounds)=='table'and #req.required_bounds==6,'Required bounds missing')
  assert(req.mapping.scale==100 and req.mapping.y_origin==64,'Companion coordinate mapping mismatch')
  serial=serial+1
  local t={id=serial,request=req,cache=nil};tickets[serial]=t;return t
 end
 function api.readiness(t)
  check(t);local r=t.request;local w=companion.world
  local proof={ready=false,world_session=r.world_session,dim=r.dim,view=r.view,region_id=r.mapping.region_id,
   generation=r.generation,covered_bounds=r.required_bounds,coverage_complete=false,snapshots_pending=0,
   collision_pending=1,visual_pending=1,collision_committed=false,visual_committed=false,revision=w.seq,errors={}}
  if not companion.running or companion.error or companion.world_error or companion.observer_error then
   proof.errors.companion=companion.error or companion.world_error or companion.observer_error or'stopped';return proof
  end
  if w.session~=r.world_session or w.dimension~=r.dim then proof.errors.world='world_or_dimension_changed';return proof end
  local pending=#companion.queue-(companion.queue_head or 1)+1
  -- Check complete committed coverage separately for each intersecting MC chunk.
  local b=r.required_bounds;local receipts={}
  for x=math.floor(b[1]/16),math.floor((b[4]-1)/16)do for z=math.floor(b[3]/16),math.floor((b[6]-1)/16)do
   local part={math.max(b[1],x*16),b[2],math.max(b[3],z*16),math.min(b[4],x*16+16),b[5],math.min(b[6],z*16+16)}
   local result=w:region_status(r.dim,part,r.player)
   proof.snapshots_pending=proof.snapshots_pending+(result.pending or 0)
   if not result.ready then proof.errors.coverage=result.reason;return proof end
   receipts[#receipts+1]=result.proof.snapshot
  end end
  proof.coverage_complete=true;proof.snapshot_receipts=receipts
  if pending>0 then proof.collision_pending=pending;proof.visual_pending=pending;return proof end
  if not o.verify_native then proof.errors.native='native_handle_and_capability_verifier_missing';return proof end
  -- Cache expensive actor verification until the logical or native revision changes.
  local key=r.world_session..':'..w.seq..':'..companion.changes
  if not t.cache or t.cache.key~=key then
   local expected={}
   for k,g in pairs(w.worlds[r.dim]and w.worlds[r.dim].blocks or{})do local at=g.at
    if at[1]>=b[1]and at[1]<b[4]and at[2]>=b[2]and at[2]<b[5]and at[3]>=b[3]and at[3]<b[6]then
     local entry=companion.actors[k]
     if not entry or entry.signature~=encode(g)or#entry.handles~=#g.boxes then
      proof.errors.native='geometry_or_collision_revision_not_applied:'..k;return proof
     end
     expected[#expected+1]={key=k,geometry=g,entry=entry}
    end
   end
   t.cache={key=key,result=o.verify_native(t,expected,r.mode)}
  end
  local native=t.cache.result
  if type(native)~='table'or native.collision_committed~=true or native.collision_verified~=true
   or(r.mode=='client'and(native.visual_committed~=true or native.visual_verified~=true))then
   proof.errors.native=native and native.error or'native_runtime_unverified';return proof
  end
  if native.errors and next(native.errors)then proof.errors=native.errors;return proof end
  proof.collision_committed=true;proof.collision_pending=0
  proof.visual_committed=r.mode~='client'or native.visual_committed==true;proof.visual_pending=0
  proof.native_evidence=native.evidence;proof.ready=true;return proof
 end
 function api.activate(t)
  check(t);assert(api.readiness(t).ready,'Companion view not ready')
  companion.set_view(t.request.dim,t.request.player);api.active=t;return true
 end
 function api.release(t)check(t);t.released=true;tickets[t.id]=nil;if api.active==t then api.active=nil end;return true end
 function api.abandon(t)return api.release(t)end
 return api
end
return M
