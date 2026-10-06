-- Server factory, composed by server/features.lua on its existing game thread.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={version=1}
function M.new(options)
 local o={};for k,v in pairs(options or{})do o[k]=v end;o.side='server'
 local shared=o.shared_dir or(dir..'../native/')
 local core=o.core or dofile(shared..'fluid_physics_core.lua')
 o.contact_driver=o.contact_driver or dofile(o.driver_path or(dir..'world_fluid.lua'))
 o.resolve_context=o.resolve_context or function(ctx)
  if ctx and ctx.companion and ctx.companion.context then return ctx.companion.context()end
  return ctx and(ctx.world_context or ctx.pc)
 end
 o.resolve_participants=o.resolve_participants or function(ctx)
  local entity=o.entity_authority or _G.PalCraftEntityAuthority
  assert(entity and entity.running,'Server entity authority required for fluid participants')
  local list={};local session=ctx and ctx.presence and ctx.presence.server_session_id
  if session then assert(entity.session==session,'Fluid/entity Pal boot mismatch')end
  for id,e in pairs(entity.native or{})do
   if e.actor and e.actor:IsValid()and e.actor:HasAuthority()then
    list[#list+1]={id=id,actor=e.actor,dim=e.dimension or o.world.dimension,player=e.player}
   end
  end
  return list
 end
 return core.new(o)
end
return M
