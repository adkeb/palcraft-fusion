-- Adapter for the existing per-block companion, independent of travel. The
-- owner supplies its already-confirmed player WorldView; origin and coverage
-- come from the actual renderer/reducer, with no authored position fallback.
local M={version=1}
local function companion(o)if type(o.companion)=='function'then return o.companion()end;return o.companion end
local function render_signature(J,g)
 return J.encode({id=g.id,state=g.state,properties=g.properties,boxes=g.boxes,visible=g.visible,
  render_kind=g.render_kind,fluid=g.fluid,tint_colors=g.tint_colors})
end
local function coverage(c,view)
 local bounds
 for _,receipt in pairs(c.world.committed_snapshots or{})do
  if receipt.committed==true and receipt.session==view.world_session and receipt.dim==view.dim
   and(not receipt.player or receipt.player==view.mc_uuid)then
   local b=receipt.bounds
   if not bounds then bounds={table.unpack(b)}
   else for i=1,3 do bounds[i]=math.min(bounds[i],b[i]);bounds[i+3]=math.max(bounds[i+3],b[i+3])end end
  end
 end
 return bounds
end
function M.per_block(o)
 assert(o and o.json and o.companion and type(o.confirmed_view)=='function','Existing companion/confirmed WorldView required')
 local J=o.json;local api={}
 function api.block_at(dim,at)
  local c=companion(o);if not c or c.running~=true or not c.world then return nil,false end
  local g=c.world:get(dim,table.unpack(at));if not g then return nil,false end
  local entry
  if type(c.block_render_entry)=='function'then entry=c.block_render_entry(dim,at)end
  if not entry and c.actors then entry=c.actors[('%d:%d:%d'):format(table.unpack(at))]end
  local expected_signature
  if type(c.render_signature)=='function'then expected_signature=c.render_signature(g)
  else expected_signature=render_signature(J,g)end
  local ready=c.world.dimension==dim and entry and(not entry.dim or entry.dim==dim)
   and entry.model~=nil and entry.model_status=='rendered'
   and entry.id==g.id and entry.visible~=false and entry.render_signature==expected_signature
  if ready and o.model_live then ready=o.model_live(entry.model,entry.model_component)==true end
  return g,ready==true
 end
 function api.view_provider(ctx)
  local c=companion(o);if not c or c.running~=true or c.error or c.world_error or not c.world or not c.origin then return end
  local view=o.confirmed_view(c,ctx)
  if not view or view.applied~=true or view.world_session~=c.world.session or view.dim~=c.world.dimension then return end
  if c.world.pending_view or c.pending_view then return end
  local bounds=o.visible_bounds and o.visible_bounds(c,view)or coverage(c,view);if not bounds then return end
  local origin=c.origin
  local mapping=view.mapping
  if not mapping then
   -- An identifier derived from the committed renderer's actual transform.
   -- It is an opaque fence string, never a new coordinate or allocation.
   mapping='per-block-origin:'..J.encode({origin.X,origin.Y,origin.Z,origin.y_origin or 64})
  end
  return{fence={world_session=view.world_session,dim=view.dim,view=view.view,mapping=mapping,mc_uuid=view.mc_uuid},
   origin=origin,bounds=bounds}
 end
 return api
end
return M
