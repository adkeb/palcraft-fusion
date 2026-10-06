-- Local player movement prediction. HP and other Pal movement remain server-owned.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={version=1}
function M.new(options)
 local o={};for k,v in pairs(options or{})do o[k]=v end;o.side='client'
 local shared=o.shared_dir or(dir..'../native/')
 local core=o.core or dofile(shared..'fluid_physics_core.lua')
 o.contact_driver=o.contact_driver or dofile(o.driver_path or(shared..'world_fluid.lua'))
 o.resolve_context=o.resolve_context or function(ctx)
  if ctx and ctx.collisions and ctx.collisions.context then return ctx.collisions.context()end
  return ctx and ctx.pc
 end
 o.resolve_participants=o.resolve_participants or function(ctx)
  assert(ctx and ctx.pc and ctx.pc:IsValid(),'Local fluid controller required')
  local pawn=ctx.pc.Pawn;assert(pawn and pawn:IsValid(),'Local fluid pawn required')
  local identity=assert(ctx.identity,'Bound local fluid identity required')
  -- ctx.identity is lab boot metadata; the runtime already checked the configured
  -- account against the possessed controller. Derive the UID from that controller.
  local g=ctx.pc:GetPlayerUId()
  local uid=('%08x-%04x-%04x-%04x-%04x%08x'):format(g.A&0xffffffff,(g.B>>16)&0xffff,g.B&0xffff,(g.C>>16)&0xffff,g.C&0xffff,g.D&0xffffffff)
  if identity.pal_uid then assert(identity.pal_uid==uid,'Local fluid UID changed')end
  return{{id='player:'..uid,actor=pawn,dim=o.world.dimension,player=true,player_filter=o.world.player}}
 end
 return core.new(o)
end
return M
