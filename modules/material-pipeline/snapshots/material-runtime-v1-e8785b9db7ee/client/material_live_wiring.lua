-- Instantiated by the existing client_world factory before chunk composition.
-- It decorates the selected Models.geometry and the sole visual pipeline tick.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Driver=dofile(dir..'material_scene_driver.lua')
local M={version=1}
function M.attach(options)
 local c,p,models=assert(options.companion),assert(options.pipeline),assert(options.models)
 assert(p.add_material_handler and p.tick and p.stop and models.geometry,'Actual native pipeline/geometry required')
 local settings={};for k,v in pairs(options.material_options)do settings[k]=v end
 settings.retry_scene=function(_,block)
  assert(c.retry_material_block,'Companion material retry hook required')
  return c.retry_material_block(block)
 end
 local driver=Driver.new(settings);local raw_geometry=models.geometry;local old_tick,old_stop=p.tick,p.stop
 local old_bind,old_accept=p.bind_material_scope,p.accept_material_tint
 local handler=p.add_material_handler(function(g)return not g.entity_visual and not g.text_plane end,function(ctx,g,root)
  local material,why=driver:resolve(ctx,g,root);assert(material,'Material scene pending: '..tostring(why));return material
 end)
 local function geometry(id,state,x,y,z,opts)
  local groups,why,detail=raw_geometry(id,state,x,y,z,opts);if not groups then return nil,why,detail end
  local scope=driver.scope;local dim=scope and scope.dim or c.world.dimension
  local original=c.world:get(dim,x,y,z)
  if not original or original.id~=id or original.state~=state then return nil,'authoritative_material_block_pending'end
  local block={id=id,state=state,properties=original.properties,dim=dim,x=x,y=y,z=z}
  local scene_key=('%s:%d:%d:%d'):format(dim,x,y,z)
  local colored,pending=driver:prepare(scene_key,block,groups)
  return colored,pending,detail
 end
 models.geometry=geometry
 p.bind_material_scope=function(scope)return driver:bind_material_scope(scope)end
 p.accept_material_tint=function(reply)return driver:accept_material_tint(reply)end
 p.tick=function(delta,seconds)local ok,why=driver:tick(seconds);p.material_runtime_reason=ok and nil or why;return old_tick(delta,seconds)end
 local stopped=false
 local function detach()
  if stopped then return true end;stopped=true
  if models.geometry==geometry then models.geometry=raw_geometry end
  assert(p.remove_material_handler,'Native material handler removal hook required');p.remove_material_handler(handler)
  driver:reset();p.tick=old_tick;p.stop=old_stop;p.bind_material_scope=old_bind;p.accept_material_tint=old_accept;p.material_runtime=nil;return true
 end
 p.stop=function()detach();return old_stop()end
 local api={driver=driver,bind_material_scope=function(scope)return p.bind_material_scope(scope)end,stop=detach,status=function()return driver:status()end}
 p.material_runtime=api;return api
end
return M
