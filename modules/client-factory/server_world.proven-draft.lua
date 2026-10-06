-- Lazy collision-only travel views over the actual companion/chunk consumer.
-- The authoritative prepare supplies its mapping and bounds. No reader or tick.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={version=1}
local function copy(t)local r={};for k,v in pairs(t or{})do r[k]=v end;return r end
local function root(p)return assert(p):gsub('\\','/'):gsub('/?$','/')end
function M.new(o)
 o=assert(o);local J=assert(o.json);local scripts=root(o.scripts_dir)
 local chunk_dir=root(o.chunk_dir or(scripts..'chunks/'));local rpc=root(o.rpc_root or o.root)
 local get_companion=assert(o.companion);assert(type(get_companion)=='function','Real companion getter required')
 local instance,companion,delegate;local tickets={}
 local api={version=M.version,recovery_scenes={}}
 local function thread()
  local f=o.game_thread or IsInGameThread;assert(type(f)=='function'and f()==true,'server_world_requires_game_thread')
 end
 local function backend()
  assert(instance,'Server native view not prepared');return instance
 end
 local function claim(ticket)
  assert(ticket and ticket.dim and ticket.world_session and ticket.region_id,'Actual native ticket required')
  tickets[ticket]=true;return ticket
 end
 local function remove_retained(ticket)
  for i=#api.recovery_scenes,1,-1 do if api.recovery_scenes[i].ticket==ticket then table.remove(api.recovery_scenes,i)end end
 end
 function api.prepare_view(request)
  thread();assert(request and request.mode=='server','Collision-only authoritative server prepare required')
  local c=assert(get_companion(),'Server collision companion not started')
  assert(c.running==true and c.world and not c.error,'Actual server companion not running')
  assert(c.world.session==request.world_session,'Authoritative prepare/reducer world session mismatch')
  if delegate then return delegate.prepare_view(request)end
  if instance then
   assert(c==companion and instance.views.session==request.world_session,'Occupied server scene requires explicit companion recovery')
   return claim(instance.view.prepare_view(request))
  end
  if c.chunk_consumer then
   local previous=c.chunk_consumer.server_world_view
   assert(previous and previous~=api,'Another consumer owns the companion journal')
   delegate=previous;return delegate.prepare_view(request)
  end
  -- Models is the existing transaction coordinator. visuals=false leaves its
  -- visual lists empty, so commit_transaction never opens the client Model DLL.
  local models=o.models or c.models or dofile(o.models_path or(scripts..'models.lua'))
  local info=assert(models.status(),'Actual Models status required')
  local opts=copy(o.chunk_options)
  opts.client_dir=chunk_dir;opts.companion=c;opts.models=models;opts.json=J;opts.root=rpc
  opts.context=assert(c.context,'server/main.lua companion.context required')
  opts.origin=assert(o.origin);opts.initial_view=request;opts.world_session=request.world_session
  opts.visuals=false;opts.max_regions=opts.max_regions or o.max_regions or 16
  -- Filter scope belongs to each authoritative request, not the first player.
  opts.player=nil
  opts.geometry=opts.geometry or o.geometry or{geometry=assert(models.geometry)}
  opts.geometry_version=o.geometry_version or info.geometry_version or models.geometry_version or 2
  opts.asset_root=o.asset_root or assert(info.asset_root,'Actual Models asset root required')
  opts.collision_dll=opts.collision_dll or o.collision_dll or(scripts..'../../../../PalCraftChunkCollision-v1.dll')
  opts.log_path=opts.log_path or o.log_path or(scripts..'../../../UE4SS.log')
  opts.frame_budget_ms=opts.frame_budget_ms or 2;opts.frame_steps=opts.frame_steps or 128
  instance=dofile(dir..'chunks.lua').new(opts);companion=c
  c.chunk_consumer.server_world_view=api
  return claim(instance.initial_ticket)
 end
 for _,name in ipairs({'readiness','activate','can_recycle','retirement_status'})do
  api[name]=function(...)
   thread();if delegate then return delegate[name](...)end
   return backend().view[name](...)
  end
 end
 function api.release(ticket)
  thread();if delegate then return delegate.release(ticket)end
  assert(tickets[ticket]and not ticket.abandoned,'Unknown or abandoned server ticket')
  assert(backend().view.release(ticket)==true,'Actual server region release failed')
  tickets[ticket]=nil;remove_retained(ticket);return true
 end
 function api.abandon(ticket)
  thread();if delegate then return delegate.abandon(ticket)end
  if ticket.abandoned then return true end
  assert(tickets[ticket],'Unknown server scene abandon')
  -- A dead UWorld invalidates every ticket in this one consumer. Clear native
  -- bookkeeping through its real context=false path, never touch stale actors.
  if instance then
   assert(instance.stop(false)==true,'Dead server scene cleanup failed')
   if companion.chunk_consumer==instance.bridge.binding then companion.chunk_consumer=nil end
   for t in pairs(tickets)do t.abandoned=true;remove_retained(t)end
   instance=nil;companion=nil
  end
  return true
 end
 function api.retain_scene(scene)
  thread();if delegate then return delegate.retain_scene(scene)end
  assert(scene and scene.occupied==true and tickets[scene.ticket]and not scene.ticket.released,'Occupied real server scene required')
  assert(scene.mapping.region_id==scene.ticket.region_id and scene.mapping.world_session==scene.ticket.world_session,'Retained server scene fence mismatch')
  remove_retained(scene.ticket);api.recovery_scenes[#api.recovery_scenes+1]=scene;return true
 end
 function api.status()
  if delegate then return delegate.status()end
  if not instance then return{version=M.version,phase='waiting_for_authoritative_prepare',ready=false,companion_driven=true,engine_verified=false}end
  local s=instance.status();s.collision_only=true;s.retained_scene_count=#api.recovery_scenes
  return s
 end
 function api.stop(context_alive)
  thread();if delegate then return delegate.stop(context_alive)end
  if not instance then return true end
  assert(instance.stop(context_alive==true)==true,'Server chunk lifecycle stop failed')
  if companion.chunk_consumer==instance.bridge.binding then companion.chunk_consumer=nil end
  for t in pairs(tickets)do t.abandoned=true end
  instance=nil;companion=nil;tickets={}
  for i=#api.recovery_scenes,1,-1 do table.remove(api.recovery_scenes,i)end
  return true
 end
 return api
end
return M
