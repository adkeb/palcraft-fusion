-- Visual-only adapter for entity_combat's exact native_id-bound Actor.
-- No authority spawn, position/HP writes or collider changes.
local M={version=1}
local function valid(x)return x and x:IsValid()end
function M.new(o)
 local Models,Visuals,Pose=assert(o.models),assert(o.visuals),assert(o.pose)
 local O,context=assert(o.origin),assert(o.context)
 local A={};local handles={};local stats={created=0,updates=0,removed=0,variant_rebuilds=0}
 local function geometry(row)
  local groups,effects=Pose.geometry(Visuals,row)
  if not groups then return nil,effects end
  for _,g in ipairs(groups)do g.shade=false;g.material_root=o.asset_root end
  return groups,effects
 end
 local function placement(row)return{X=O.X+row.x*100,Y=O.Y-row.z*100,Z=O.Z+(row.y-(O.y_origin or 64))*100}end
 local function bind(row,actor)
  assert(valid(actor),'Authoritative entity Actor unavailable')
  assert(type(row.id)=='string'and row.id:match('^mc:'),'MC entity identity required')
  local mesh=actor:GetMainMesh();assert(valid(mesh),'Character mesh unavailable')
  return{actor=actor,actor_address=actor:GetAddress(),mesh=mesh,was_visible=mesh:IsVisible(),id=row.id}
 end
 local function create(row,actor,old)
  local groups,why=geometry(row);if not groups then return nil,why end
  local binding=old or bind(row,actor)
  local ctx=context();local model=Models.spawn_groups(ctx,O,groups,{row.x,row.y,row.z},{hidden=true})
  assert(model,'Entity visual creation failed')
  Models.set_actor_pose(model,placement(row),Pose.actor_yaw(row));Models.set_visible(model,true)
  -- Hide only after the native visual exists. Always retain the previous mesh
  -- visibility for removal/stop; the combat body remains authoritative.
  binding.mesh:SetVisibility(false,false)
  local h={model=model,binding=binding,id=row.id,rig_key=groups[1].rig_key or row.kind,texture=groups[1].texture_path,groups=groups}
  handles[h]=true;stats.created=stats.created+1;return h
 end
 function A.spawn(row,actor)return create(row,actor)end
 function A.update(h,row,actor)
  assert(handles[h]and h.id==row.id,'Stale entity visual handle')
  assert(valid(actor)and actor:GetAddress()==h.binding.actor_address,'Entity combat Actor binding changed')
  local groups,why=geometry(row);assert(groups,why)
  local rig=groups[1].rig_key or row.kind
  local topology_changed=#groups~=#h.groups
  if not topology_changed then for i,g in ipairs(groups)do if #g.vertices~=#h.groups[i].vertices or #g.indices~=#h.groups[i].indices then topology_changed=true;break end end end
  if topology_changed or rig~=h.rig_key or groups[1].texture_path~=h.texture then
   local replacement=create(row,actor,h.binding)
   Models.release_model(h.model,true);handles[replacement]=nil
   h.model,h.groups,h.rig_key,h.texture=replacement.model,replacement.groups,replacement.rig_key,replacement.texture
   stats.variant_rebuilds=stats.variant_rebuilds+1
  else Models.update_groups(h.model,groups);h.groups=groups end
  Models.set_actor_pose(h.model,placement(row),Pose.actor_yaw(row));h.binding.mesh:SetVisibility(false,false)
  stats.updates=stats.updates+1
 end
 function A.remove(h)
  if not handles[h]then return end
  Models.release_model(h.model,true)
  if valid(h.binding.mesh)then h.binding.mesh:SetVisibility(h.binding.was_visible,false)end
  handles[h]=nil;stats.removed=stats.removed+1
 end
 function A.stop()local all={};for h in pairs(handles)do all[#all+1]=h end;for _,h in ipairs(all)do A.remove(h)end end
 function A.status()return{version=1,visual_only=true,stats=stats,shader_verified=false,pending={'hurt/white overlay material binding','equipment/aura'}}end
 return A
end
return M
