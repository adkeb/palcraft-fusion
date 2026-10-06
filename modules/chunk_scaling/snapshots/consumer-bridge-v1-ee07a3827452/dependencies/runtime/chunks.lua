-- Compose the actual chunk/model/collision modules. The companion retains its sole journal reader.
-- The native owner supplies install_consumer to switch OFF per-block callbacks before accepting rows.
local M={version=1}
function M.new(o)
 assert(o and o.client_dir and o.json and o.models and o.context and o.origin,'Chunk composition dependencies required')
 assert(o.collision_verified==true and(o.visuals==false or o.visual_verified==true),'Chunk native runtime verification required')
 assert(type(o.install_consumer)=='function','Single-reader consumer switch required')
 local dir=o.client_dir:gsub('\\','/'):gsub('/?$','/')
 local G=o.geometry or dofile(dir..'model_geometry_v2.lua')
 if not o.geometry then G.configure{json=o.json,root=assert(o.asset_root,'Frozen model assets required')}end
 local collision=o.collision or dofile(dir..'chunk_collision.lua').new{json=o.json,root=o.root,dll_path=o.collision_dll,
  process_event=o.process_event,log_path=o.log_path,resolve_address=o.resolve_address,native=o.native_collision}
 local adapter=dofile(dir..'chunk_adapter.lua').new{models=o.models,collision=collision,
  capabilities=o.capabilities,collision_verified=o.collision_verified,visual_verified=o.visual_verified,
  prepare_special=o.prepare_special,discard_special=o.discard_special,unload_special=o.unload_special,reset_special=o.reset_special,
  commit_transaction=function(fresh,old,packet,c)
   assert(#fresh.special+#old.special==0,'Special chunk transactions require a native owner callback')
   local transaction
   if #fresh.collision+#old.collision>0 then transaction={adapter=c,prepared=fresh.collision,
    previous=old.collision,expected_fence=assert(packet.fence,'Chunk world/view fence missing')}end
   return o.models.commit_transaction(fresh.visual,old.visual,transaction)
  end}
 if o.commit_transaction then
  adapter=dofile(dir..'chunk_adapter.lua').new{models=o.models,collision=collision,capabilities=o.capabilities,
   collision_verified=o.collision_verified,visual_verified=o.visual_verified,commit_transaction=o.commit_transaction,
   prepare_special=o.prepare_special,discard_special=o.discard_special,unload_special=o.unload_special,reset_special=o.reset_special}
 end
 local scheduler=dofile(dir..'chunk_scheduler.lua').new{geometry=G,adapter=adapter,context=o.context,origin=o.origin,
  session=o.world_session,context_alive=o.context_alive,frame_budget_ms=2,frame_steps=128,visuals=o.visuals~=false,view_player=o.player}
 assert(o.install_consumer(scheduler)==true,'Per-block journal consumer was not replaced')
 local api={scheduler=scheduler,adapter=adapter,collision=collision}
 function api.tick()return scheduler:tick(2,128)end
 function api.status()return scheduler:status()end
 function api.stop(context_alive)scheduler:reset(scheduler.session,false,context_alive==true);return true end
 api.view={prepare_view=function(r)return scheduler:prepare_view(r)end,readiness=function(t)return scheduler:readiness(t)end,
  activate=function(t)scheduler:activate(t);return true end,release=function(t)scheduler:release(t);return true end,
  abandon=function(t)scheduler:reset(scheduler.session,false,false);return true end}
 return api
end
return M
