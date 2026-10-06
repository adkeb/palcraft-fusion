-- Real native consumer for the existing exact-Actor observer and authenticated
-- capture cache. No transport, authority spawn, HP/AI/collider changes.
local M={version=1}
local function valid(o)return o and o:IsValid()end
local function same_topology(a,b)
 if #a~=#b then return false end
 for i,g in ipairs(a)do
  local old=b[i]
  if g.texture_path~=old.texture_path or g.alpha_mode~=old.alpha_mode or #g.vertices~=#old.vertices or #g.indices~=#old.indices then return false end
  for j,index in ipairs(g.indices)do if index~=old.indices[j]then return false end end
 end
 return true
end
function M.new(o)
 local Models,Capture=assert(o.models),assert(o.capture)
 assert(Models.version>=6,'Original vertex RGBA native consumer required')
 assert(type(o.read_visual)=='function'and type(o.verify_visual)=='function','Existing authenticated visual cache callbacks required')
 local A={};local retained={};local stats={created=0,updates=0,rebuilds=0,removed=0,pending=0};local diagnostic
 local function groups(row,actor)
  local frame,scope=o.read_visual(row)
  if not frame then return nil,'authenticated_capture_pending'end
  local verified,why=o.verify_visual(frame,scope,row,actor)
  if verified~=true then return nil,why or'capture_scope_not_verified'end
  local result,effects=Capture.geometry(row,frame)
  if not result then return nil,effects end
  if effects.missing_textures and #effects.missing_textures>0 then return nil,'capture_resources_incomplete'end
  if frame.unsupported_submissions and next(frame.unsupported_submissions)then return nil,'capture_submissions_not_consumed'end
  for _,g in ipairs(result)do
   local accepted,reason;if o.material_supported then accepted,reason=o.material_supported(g)end
   if accepted~=true then return nil,reason or'capture_material_layer_not_supported'end
  end
  return result,frame
 end
 local function origin()return type(o.origin)=='function'and o.origin()or o.origin end
 local function location(row,O)return{X=O.X+row.x*100,Y=O.Y-row.z*100,Z=O.Z+(row.y-(O.y_origin or 64))*100}end
 local function create(row,actor,data,binding)
  assert(valid(actor),'Exact authoritative Actor unavailable')
  local mesh=binding and binding.mesh or actor:GetMainMesh();assert(valid(mesh),'Actual body visual mesh unavailable')
  local b=binding or{actor=actor,actor_address=actor:GetAddress(),mesh=mesh,was_visible=mesh:IsVisible()}
  local O=assert(origin(),'Committed capture origin required')
  local model=Models.spawn_groups(o.context(),O,data,{row.x,row.y,row.z},{hidden=true})
  Models.set_actor_pose(model,location(row,O),0);Models.set_visible(model,true)
  b.mesh:SetVisibility(false,false)
  local h={model=model,binding=b,row_id=row.id,groups=data};retained[h]=true;stats.created=stats.created+1;return h
 end
 function A.spawn(row,actor)
  local data,frame=groups(row,actor)
  if not data then diagnostic=frame;stats.pending=stats.pending+1;return nil,frame end
  local h=create(row,actor,data);h.capture_seq=frame.seq;return h
 end
 function A.update(h,row,actor)
  assert(retained[h]and h.row_id==row.id and valid(actor)and actor:GetAddress()==h.binding.actor_address,'Capture Actor binding changed')
  local data,frame=groups(row,actor)
  if not data then
   Models.set_visible(h.model,false);if valid(h.binding.mesh)then h.binding.mesh:SetVisibility(h.binding.was_visible,false)end
   diagnostic=frame;stats.pending=stats.pending+1;return false,frame
  end
  if frame.seq~=h.capture_seq then
   if same_topology(data,h.groups)then Models.update_groups(h.model,data)
   else
    local fresh=create(row,actor,data,h.binding);Models.release_model(h.model,true)
    retained[fresh]=nil;h.model=fresh.model;stats.rebuilds=stats.rebuilds+1
   end
   h.groups=data;h.capture_seq=frame.seq;stats.updates=stats.updates+1
  end
  Models.set_actor_pose(h.model,location(row,origin()),0);Models.set_visible(h.model,true);h.binding.mesh:SetVisibility(false,false)
  return true
 end
 function A.suspend()
  for h in pairs(retained)do
   Models.set_visible(h.model,false)
   if valid(h.binding.mesh)then h.binding.mesh:SetVisibility(h.binding.was_visible,false)end
  end
 end
 function A.remove(h,context_alive)
  if not retained[h]then return end
  Models.release_model(h.model,context_alive~=false)
  if context_alive~=false and valid(h.binding.mesh)then h.binding.mesh:SetVisibility(h.binding.was_visible,false)end
  retained[h]=nil;stats.removed=stats.removed+1
 end
 function A.stop(context_alive)local handles={};for h in pairs(retained)do handles[#handles+1]=h end;for _,h in ipairs(handles)do A.remove(h,context_alive)end end
 function A.status()return{version=1,stats=stats,diagnostic=diagnostic,authority='visual_only',vertex_rgba_consumed=true,world_orientation_baked=true,native_yaw=0,engine_verified=false}end
 return A
end
return M
