-- Standalone server facade over ONE existing client native consumer.
-- No native factory, journal reader or timer is created here.
local M={version=1}
local function copy(x)
 if type(x)~='table'then return x end
 local r={};for k,v in pairs(x)do r[k]=copy(v)end;return r
end
function M.new(o)
 assert(o and o.local_realm and o.client_worker,'Standalone local realm and existing worker required')
 local realm=o.local_realm;local tickets={};local counter=0
 local api={recovery_scenes={}}
 local function thread()
  local f=o.game_thread or IsInGameThread
  assert(type(f)=='function'and f()==true,'standalone_views_require_game_thread')
 end
 local function current()
  local p=realm:current()
  if not p or p.mode~='standalone'or realm:validate(p,p.pc)~=true then return nil,'standalone_actual_host_pending'end
  return p
 end
 local function same_realm(a,b)
  return a and b and a.server_session_id==b.server_session_id and a.world_id==b.world_id and a.host_uid==b.host_uid
 end
 local function worker(request,p)
  local w=o.client_worker()
  if not w or w.stopped or not w.ctx or not w.ctx.pc then return nil,'standalone_client_worker_pending'end
  if realm:validate(p,w.ctx.pc)~=true then return nil,'standalone_local_controller_changed'end
  local c=w.companion
  if not c or c.running~=true or c.error or not c.world then return nil,'standalone_companion_pending'end
  if not c.context then return nil,'standalone_collision_world_pending'end
  local ok,ctx=pcall(c.context)
  if not ok or realm:same_world(ctx,p)~=true then return nil,'standalone_collision_world_changed'end
  local b=w.features and w.features.mc_binding
  if not b or b.pal_uid~=p.host_uid or b.world_id~=p.world_id or b.server_session_id~=p.server_session_id
   or b.mc_uuid~=request.player or b.session_id~=request.session_id or b.generation~=request.session_generation
   or b.mc_epoch~=request.mc_epoch then return nil,'standalone_authenticated_binding_pending'end
  if c.world.session~=request.world_session then return nil,'standalone_reducer_epoch_pending'end
  local chunks=w.chunks
  if not chunks or not chunks.view or not chunks.bridge or chunks.bridge.installed~=true
   or c.chunk_consumer~=chunks.bridge.binding then return nil,'standalone_single_native_consumer_pending'end
  return w
 end
 local function owned(t)
  assert(t and tickets[t]and not t.released and not t.abandoned,'Actual owned standalone server lease required')
 end
 local function get_native(t)
  owned(t)
  local p,reason=current()
  if not p or not same_realm(p,t.realm)then return nil,'standalone_realm_changed'end
  local w,why=worker(t.request,p);if not w then return nil,why end
  if t.worker and t.worker~=w then return nil,'standalone_native_owner_changed'end
  if not t.native then
   -- Same local authoritative UWorld: the client-mode region has the real visual
   -- and collision instance. Region mode is NOT changed on an existing region.
   local request=copy(t.request);request.mode='client'
   t.native=assert(w.chunks.view.prepare_view(request),'Actual shared native ticket required')
   t.worker=w;t.native_view=w.chunks.view
   assert(t.native.world_session==t.world_session and t.native.dim==t.dim and t.native.view==t.view
    and t.native.region_id==t.region_id,'Actual native view fence differs')
  end
  return t.native,t.native_view
 end
 function api.prepare_view(request)
  thread();assert(request and request.mode=='server','Authoritative server prepare required')
  local p=assert(current(),'Actual Standalone local host required')
  assert(type(request.session_id)=='string'and type(request.mc_epoch)=='string'
   and type(request.session_generation)=='number','Existing authenticated MC tuple required')
  counter=counter+1
  local t={id='standalone-server:'..counter,request=copy(request),realm=p,
   world_session=request.world_session,dim=request.dim,view=request.view,player=request.player,
   session_generation=request.session_generation,region_id=assert(request.mapping).region_id,
   mapping=copy(request.mapping),required_bounds=copy(request.required_bounds)}
  tickets[t]=true
  -- A pending lease has NO fake native ticket or ready/committed flags.
  get_native(t)
  return t
 end
 function api.readiness(t)
  thread();local native,view=get_native(t)
  if not native then return{ready=false,coverage_complete=false,collision_committed=false,
   world_session=t.world_session,dim=t.dim,view=t.view,region_id=t.region_id,
   session_generation=t.session_generation,reason=view,errors={view}}end
  local proof=assert(view.readiness(native),'Actual shared consumer readiness required')
  assert(proof.world_session==t.world_session and proof.dim==t.dim and proof.view==t.view
   and proof.region_id==t.region_id,'Shared collision proof fence differs')
  if proof.ready then assert(proof.collision_committed==true and proof.coverage_complete==true,
   'Standalone authority cannot substitute uncommitted native collision')end
  return proof
 end
 function api.activate(t)
  thread();assert(api.readiness(t).ready==true,'Actual shared native target not ready')
  assert(t.native_view.activate(t.native)==true,'Shared native activation failed')
  t.worker.companion.set_view(t.dim,t.player)
  return true
 end
 local function forget(t)
  for i=#api.recovery_scenes,1,-1 do if api.recovery_scenes[i].ticket==t then table.remove(api.recovery_scenes,i)end end
 end
 function api.release(t)
  thread();owned(t)
  if t.native then
   local p=current()
   assert(p and same_realm(p,t.realm)and realm:validate(p,t.worker.ctx.pc)==true
    and not t.worker.stopped,'Dead shared world requires abandon')
   assert(t.native_view.release(t.native)==true,'Shared native reference release failed')
  end
  t.released=true;tickets[t]=nil;forget(t);return true
 end
 function api.abandon(t)
  thread();owned(t)
  local p=current()
  assert(not p or not same_realm(p,t.realm)or(t.worker and t.worker.stopped),
   'Live shared scene requires owned reference release')
  -- Client world lifecycle alone stops/abandons the shared physical consumer.
  -- Never call old-world UObject methods or stop the other role from this facade.
  t.abandoned=true;tickets[t]=nil;forget(t);return true
 end
 function api.retain_scene(scene)
  thread();owned(assert(scene).ticket)
  assert(scene.occupied==true and scene.mapping.region_id==scene.ticket.region_id
   and scene.mapping.world_session==scene.ticket.world_session,'Occupied scene fence mismatch')
  forget(scene.ticket);api.recovery_scenes[#api.recovery_scenes+1]=scene;return true
 end
 function api.retirement_status(id,fence)
  thread();local p=current();local w=o.client_worker()
  if not p or not w or w.stopped or not w.chunks or realm:validate(p,w.ctx.pc)~=true then
   return{region_id=id,state='standalone_native_owner_pending',can_recycle=false,pending=0,errors={}}
  end
  return w.chunks.view.retirement_status(id,fence)
 end
 function api.can_recycle(id,fence)return api.retirement_status(id,fence).can_recycle==true end
 function api.status()
  local n,prepared=0,0;for t in pairs(tickets)do n=n+1;if t.native then prepared=prepared+1 end end
  return{version=M.version,shared_single_native_consumer=true,owned_server_leases=n,
   real_native_tickets=prepared,retained_scene_count=#api.recovery_scenes,owns_journal=false,owns_timer=false}
 end
 return api
end
return M

