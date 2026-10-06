-- Lazy native server collision scenes using the same companion's real consumer.
-- No second journal reader or tick; authoritative prepare supplies mapping/bounds.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={}
function M.new(o)
 local instance,companion;local tickets={};local api={recovery_scenes={}};local chunk_dir=assert(o.chunk_dir)
 local function thread()
  local f=o.game_thread or IsInGameThread;assert(type(f)=='function'and f()==true,'server_views_require_game_thread')
 end
 local function forget(ticket)
  for i=#api.recovery_scenes,1,-1 do if api.recovery_scenes[i].ticket==ticket then table.remove(api.recovery_scenes,i)end end
 end
 local function claim(ticket)assert(ticket,'Actual server ticket required');tickets[ticket]=true;return ticket end
 local function build(request,c)
  assert(c.running and c.world and not c.error,'Server world reducer not running')
  local models=o.models or c.models or dofile(assert(o.models_path))
  local info=assert(models.status(),'Actual Models status required')
  local options={client_dir=chunk_dir,companion=c,models=models,json=assert(o.json),origin=assert(o.origin),
   context=function()return c.context()end,root=assert(o.root),collision_dll=assert(o.collision_dll),
   collision=o.collision,log_path=o.log_path,geometry=o.geometry or{geometry=assert(models.geometry)},
   geometry_version=o.geometry_version or info.geometry_version,asset_root=o.asset_root or info.asset_root,
   initial_view=request,world_session=request.world_session,visuals=false,max_regions=o.max_regions or 16,
   collision_verified=o.collision_verified==true,visual_verified=false,
   frame_budget_ms=o.frame_budget_ms or 2,frame_steps=o.frame_steps or 128}
  -- The one reducer contains all authenticated players' authoritative snapshots.
  -- Do not bind every child scheduler to the first request's player.
  instance=dofile(dir..'chunks.lua').new(options);companion=c
  return claim(instance.initial_ticket)
 end
 function api.prepare_view(request)
  thread();assert(request and request.mode=='server','Collision-only authoritative prepare required')
  local c=assert(o.companion(),'Server collision companion not started')
  assert(c.running==true and c.world and c.world.session==request.world_session,'Authoritative prepare/reducer mismatch')
  if instance and(instance.bridge.installed==false or companion~=c)then
   -- A replacement companion must finish its actual stop/abandon first. Never
   -- tear out an occupied scene because a getter or MC world epoch changed.
   assert(instance.bridge.installed==false,'Previous companion native consumer still owns occupied scenes')
   instance=nil;companion=nil;tickets={}
   for i=#api.recovery_scenes,1,-1 do table.remove(api.recovery_scenes,i)end
  end
  if not instance then return build(request,c)end
  assert(instance.views.session==request.world_session,'New world session requires actual companion reset')
  return claim(instance.view.prepare_view(request))
 end
 for _,name in ipairs({'readiness','activate','can_recycle','retirement_status'})do
  api[name]=function(...)
   thread();assert(instance,'Native server view not prepared');return instance.view[name](...)
  end
 end
 function api.release(ticket)
  thread();assert(instance and tickets[ticket]and not ticket.abandoned,'Actual owned server ticket required')
  assert(instance.view.release(ticket)==true,'Server ticket release failed')
  tickets[ticket]=nil;forget(ticket);return true
 end
 function api.abandon(ticket)
  thread();assert(tickets[ticket],'Actual owned server ticket required')
  if ticket.abandoned then return true end
  -- A dead UWorld invalidates all this consumer's tickets. The real false-context
  -- path clears native bookkeeping without UObject calls, once for the consumer.
  if instance and instance.bridge.installed then
   assert(instance.stop(false)==true,'Dead server scene cleanup failed')
   if companion.chunk_consumer==instance.bridge.binding then companion.chunk_consumer=nil end
  end
  for t in pairs(tickets)do t.abandoned=true;forget(t)end
  instance=nil;companion=nil;return true
 end
 function api.retain_scene(scene)
  thread();assert(scene and scene.occupied==true and tickets[scene.ticket]and not scene.ticket.released,'Occupied native scene required')
  assert(scene.mapping.region_id==scene.ticket.region_id and scene.mapping.world_session==scene.ticket.world_session,'Retained scene fence mismatch')
  forget(scene.ticket);api.recovery_scenes[#api.recovery_scenes+1]=scene;return true
 end
 function api.status()
  if not instance then return{phase='waiting_for_authoritative_prepare',ready=false,companion_driven=true}end
  local s=instance.status();s.collision_only=true;s.retained_scene_count=#api.recovery_scenes;return s
 end
 return api
end
return M
