-- Lazy native server collision scenes using the same companion's real consumer.
-- No second journal reader or tick; the first authoritative prepare supplies mapping/bounds.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={}
function M.new(o)
 local instance;local api={};local chunk_dir=assert(o.chunk_dir)
 local function build(request)
  local c=assert(o.companion(),'Server collision companion not started')
  assert(c.running and c.world,'Server world reducer not running')
  local models=o.models or dofile(assert(o.models_path))
  local options={client_dir=chunk_dir,companion=c,models=models,json=assert(o.json),origin=assert(o.origin),
   context=function()return c.context()end,root=assert(o.root),collision_dll=assert(o.collision_dll),
   log_path=o.log_path,geometry=o.geometry,geometry_version=o.geometry_version or 3,asset_root=o.asset_root,
   initial_view=request,world_session=request.world_session,player=request.player,visuals=false,
   collision_verified=o.collision_verified==true,visual_verified=false,frame_budget_ms=2,frame_steps=128}
  instance=dofile(dir..'chunks.lua').new(options)
  return assert(instance.initial_ticket,'Native initial prepare returned no ticket')
 end
 function api.prepare_view(request)
  if not instance then return build(request)end
  return instance.view.prepare_view(request)
 end
 for _,name in ipairs({'readiness','activate','release','abandon','can_recycle','retirement_status'})do
  api[name]=function(...)
   assert(instance,'Native server view not prepared')
   return instance.view[name](...)
  end
 end
 function api.status()return instance and instance.status()or{phase='waiting_for_authoritative_prepare',ready=false}end
 return api
end
return M
