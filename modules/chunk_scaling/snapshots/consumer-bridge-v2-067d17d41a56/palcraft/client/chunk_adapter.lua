-- Compose the native owner's visual adapter with compound colliders. The owner
-- supplies one atomic commit callback; this module never attempts a partial commit.
local M={version=1}
function M.new(options)
 assert(options and options.models and options.collision,'Models and colliders required')
 local visual,collision=options.models,options.collision
 local A={capabilities={atomic_commit=true,collision_compound=true}}
 for k,v in pairs(options.capabilities or visual.capabilities or{})do A.capabilities[k]=v end
 -- The implemented native ABI determines what can run. Acceptance is evidence
 -- recorded separately, so the first isolated Lab experiment is not circular.
 A.capabilities.collision_compound=type(collision.prepare)=='function'and type(collision.preflight)=='function'
  and type(collision.commit)=='function'and type(collision.unload)=='function'and type(collision.discard)=='function'
 A.capabilities.collision_verified=options.collision_verified==true
 A.capabilities.visual_verified=options.visual_verified==true
 A.prepare=assert(visual.prepare);A.prepare_collision=assert(collision.prepare)
 A.prepare_special=options.prepare_special
 function A.commit(prepared,previous,packet)
  previous=previous or{visual={},collision={},special={}}
  for _,h in ipairs(prepared.visual)do
   assert(h.revision==packet.revision,'Mixed visual revisions')
   if h.generation then assert(h.generation==packet.generation,'Stale visual generation')end
  end
  if #prepared.collision+#previous.collision>0 then collision.preflight(prepared.collision,previous.collision,packet.fence)end
  -- This callback must validate visual/special handles before any engine mutation,
  -- then publish visuals, switch collision, and retire old handles in one game tick.
  if options.commit_transaction then assert(options.commit_transaction(prepared,previous,packet,collision)~=false,'Native transaction rejected')
  else
   assert(#prepared.special+#previous.special==0,'Special transaction callback required')
   local coll
   if #prepared.collision+#previous.collision>0 then
    coll={adapter=collision,prepared=prepared.collision,previous=previous.collision,expected_fence=packet.fence}
   end
   visual.commit_transaction(prepared.visual,previous.visual,coll)
  end
  return prepared
 end
 local function retire_list(list,release)
  -- Remember successful cleanup if a later backend call fails. Retrying must not
  -- resend an already-released Model handle and strand the remaining colliders.
  while #list>0 do local index=#list;release(list[index]);list[index]=nil end
 end
 function A.discard(handles)
  retire_list(handles.visual or{},visual.discard)
  collision.discard(handles.collision);handles.collision={}
  if options.discard_special then retire_list(handles.special or{},options.discard_special)
  else assert(#(handles.special or{})==0,'Special discard unavailable')end
 end
 function A.unload(handles)
  retire_list(handles.visual or{},visual.unload)
  collision.unload(handles.collision);handles.collision={}
  if options.unload_special then retire_list(handles.special or{},options.unload_special)
  else assert(#(handles.special or{})==0,'Special unload unavailable')end
 end
 function A.reset(generation,context_alive)
  collision.reset(generation,context_alive)
  if visual.reset then visual.reset(generation,context_alive)end
  if options.reset_special then options.reset_special(generation,context_alive)end
 end
 return A
end
return M
