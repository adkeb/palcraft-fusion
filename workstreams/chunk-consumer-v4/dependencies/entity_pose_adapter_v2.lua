-- New actual age/climate/scale fields; preserves the immutable V1 adapter.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Base=dofile(dir..'entity_pose_adapter.lua')
local M={body_yaw=Base.body_yaw,actor_yaw=Base.actor_yaw}
function M.pose(row)
 local s=Base.pose(row)
 s.baby=row.baby==true
 s.variant=row.pig_variant or row.variant
 s.scale=row.scale or 1
 s.age_scale=row.age_scale or(s.baby and .5 or 1)
 return s
end
function M.geometry(visuals,row)
 local groups,effects=visuals.geometry(row.kind,M.pose(row))
 if groups then for _,g in ipairs(groups)do
  g.authoritative_entity_id=row.id;g.pose_source='mc_server_scalars'
  g.baby_variant_pending=false
 end end
 return groups,effects
end
return M
